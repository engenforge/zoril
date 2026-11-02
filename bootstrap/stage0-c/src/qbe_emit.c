#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "qbe_emit.h"
#include "diagnostics.h"

/* `fn main()` returns unit, but the process exit status comes from main's return register.
 * Emit it as returning `w` with value 0, matching the self-hosted compiler, rather than
 * leaving whatever the last call left in %eax as the exit status. */
static bool is_unit_main(const ILFunction* func) {
    return func && !func->is_sret && func->name && strcmp(func->name, "main") == 0 &&
           (!func->return_type || func->return_type->kind == IL_TY_UNIT);
}

static void qbe_get_type_name_string(const ILType* type, char* buf, size_t max_len);
const char* qbe_map_func_abi_type(const ILType* type);

static const ILModule* current_mod = NULL;

// Returns the QBE type token for a field inside a QBE aggregate type definition.
// This differs from qbe_map_abi_type: bool/u8/i8 use "b" (byte), not "w".
static const char* qbe_map_aggregate_field_type(const ILType* type) {
    if (!type) return "b";
    switch (type->kind) {
        case IL_TY_U8: case IL_TY_I8: case IL_TY_BOOL: return "b";
        case IL_TY_U16: case IL_TY_I16: return "h";
        case IL_TY_U32: case IL_TY_I32: return "w";
        case IL_TY_F32: return "s";
        case IL_TY_F64: return "d";
        default: return "l";
    }
}

static bool qbe_is_aggregate(const ILType* type) {
    if (!type) return false;
    return (type->kind == IL_TY_STRUCT || type->kind == IL_TY_SUM || 
            type->kind == IL_TY_TUPLE || type->kind == IL_TY_ARRAY || 
            type->kind == IL_TY_SLICE);
}

const char* qbe_map_type(const ILType* type) {
    if (!type) return NULL;
    const ILPrimMeta* m = il_prim_meta(type->kind);
    if (m) return m->qbe_val;
    /* Composite types — all aggregate / opaque-pointer in QBE */
    return "l";
}

const char* qbe_map_store_type(const ILType* type) {
    if (!type) return "w";
    const ILPrimMeta* m = il_prim_meta(type->kind);
    if (m) return m->qbe_store ? m->qbe_store : "w";
    return "l"; /* composite aggregate */
}

const char* qbe_map_load_type(const ILType* type) {
    if (!type) return "w";
    const ILPrimMeta* m = il_prim_meta(type->kind);
    if (m) return m->qbe_load ? m->qbe_load : "w";
    return "l"; /* composite aggregate */
}

const char* qbe_map_abi_type(const ILType* type) {
    if (!type) return NULL;
    
    if (qbe_is_aggregate(type)) {
        // If it's a large aggregate (> 16 bytes), always pass by reference (l).
        if (il_type_size(current_mod, type) > 16) {
            return "l";
        }
        // Small aggregates pass by value using their QBE type tag.
        return qbe_map_func_abi_type(type);
    }
    
    return qbe_map_type(type);
}

const char* qbe_map_func_abi_type(const ILType* type) {
    if (!type) return NULL;
    
    if (type->kind == IL_TY_STRUCT || type->kind == IL_TY_SUM || 
        type->kind == IL_TY_TUPLE || type->kind == IL_TY_ARRAY || 
        type->kind == IL_TY_SLICE) {
        static char buffers[4][256];
        static int next = 0;
        char* buf = buffers[next];
        next = (next + 1) % 4;
        
        buf[0] = ':';
        qbe_get_type_name_string(type, buf + 1, 255);
        return buf;
    }
    
    return qbe_map_type(type);
}

static void qbe_emit_func_sym(const char* name, bool is_extern, FILE* out) {
    if (is_extern || strcmp(name, "main") == 0 || strcmp(name, "abort") == 0 || 
        strncmp(name, "__zoril_syscall_", 16) == 0) {
        fprintf(out, "$%s", name);
    } else {
        fprintf(out, "$z_%s", name);
    }
}

void qbe_map_ssa(uint32_t id, char* buf) {
    sprintf(buf, "%%v%u", id);
}

static const ILType* get_val_type(const ILFunction* func, uint32_t id) {
    if (id == 0) return il_type_unit();
    if (func) {
        if (id <= func->param_count) return func->param_types[id - 1];
        for (uint32_t i = 0; i < func->block_count; i++) {
            const ILBasicBlock* b = func->blocks[i];
            for (uint32_t j = 0; j < b->instr_count; j++) {
                if (b->instructions[j]->result_id == id) return b->instructions[j]->result_type;
            }
        }
    }
    return il_type_unit();
}

static void emit_val(uint32_t id, FILE* out) {
    if (id == 0) {
        fprintf(out, "0");
        return;
    }
    char buf[16];
    qbe_map_ssa(id, buf);
    fprintf(out, "%s", buf);
}

/* Returns the QBE comparison mnemonic for a comparison opcode and operand type. */
static const char* get_cmp_suffix(ILOpcode op, const char* op_ty, bool is_unsigned) {
    bool is_l = (op_ty && strcmp(op_ty, "l") == 0);
    bool is_s = (op_ty && strcmp(op_ty, "s") == 0);
    bool is_d = (op_ty && strcmp(op_ty, "d") == 0);
    bool is_fp = is_s || is_d;

    switch (op) {
        case IL_OP_CMP_LT: 
            if (is_fp) return is_s ? "clts" : "cltd";
            if (is_unsigned) return is_l ? "cultl" : "cultw";
            return is_l ? "csltl" : "csltw";
        case IL_OP_CMP_LE:
            if (is_fp) return is_s ? "cles" : "cled";
            if (is_unsigned) return is_l ? "culel" : "culew";
            return is_l ? "cslel" : "cslew";
        case IL_OP_CMP_GT:
            if (is_fp) return is_s ? "cgts" : "cgtd";
            if (is_unsigned) return is_l ? "cugtl" : "cugtw";
            return is_l ? "csgtl" : "csgtw";
        case IL_OP_CMP_GE:
            if (is_fp) return is_s ? "cges" : "cged";
            if (is_unsigned) return is_l ? "cugel" : "cugew";
            return is_l ? "csgel" : "csgew";
        case IL_OP_CMP_EQ: return is_s ? "ceqs"  : is_d ? "ceqd"  : is_l ? "ceql"  : "ceqw";
        case IL_OP_CMP_NE: return is_s ? "cnes"  : is_d ? "cned"  : is_l ? "cnel"  : "cnew";
        default: return NULL;
    }
}


static void ensure_l_val(uint32_t id, const ILType* ty, FILE* out, const ILModule* mod, char* out_buf) {
    if (id == 0) {
        sprintf(out_buf, "0");
        return;
    }
    const char* kind = qbe_map_type(ty);
    if (kind && strcmp(kind, "w") == 0) {
        uint32_t ext_id = ((ILModule*)mod)->next_label_id++;
        sprintf(out_buf, "%%ext%u", ext_id);
        if (ty->kind == IL_TY_I32 || ty->kind == IL_TY_I16 || ty->kind == IL_TY_I8) {
            fprintf(out, "\t%s =l extsw ", out_buf);
        } else {
            fprintf(out, "\t%s =l extuw ", out_buf);
        }
        emit_val(id, out);
        fprintf(out, "\n");
    } else {
        qbe_map_ssa(id, out_buf);
    }
}

static void emit_fd_io_instr(const ILModule* mod, const ILFunction* func, const ILInstruction* instr, FILE* out) {
    char res_buf[16];
    qbe_map_ssa(instr->result_id, res_buf);
    switch (instr->opcode) {
        case IL_OP_FD_OPEN: { /* openat(AT_FDCWD=-100, path, flags, mode) -- syscall 257 */
            char a1[32], a2[32], a3[32];
            ensure_l_val(instr->operands.fd_open.path, get_val_type(func, instr->operands.fd_open.path), out, mod, a1);
            ensure_l_val(instr->operands.fd_open.flags, get_val_type(func, instr->operands.fd_open.flags), out, mod, a2);
            ensure_l_val(instr->operands.fd_open.mode, get_val_type(func, instr->operands.fd_open.mode), out, mod, a3);
            fprintf(out, "\t%s =l call $__zoril_syscall_4(l 257, l -100, l %s, l %s, l %s)\n", res_buf, a1, a2, a3);
            break;
        }
        case IL_OP_FD_CLOSE: { /* close(fd) -- syscall 3 */
            char a1[32];
            ensure_l_val(instr->operands.fd_close.fd, get_val_type(func, instr->operands.fd_close.fd), out, mod, a1);
            fprintf(out, "\tcall $__zoril_syscall_1(l 3, l %s)\n", a1);
            break;
        }
        case IL_OP_FD_READ: { /* read(fd, buf, count) -- syscall 0 */
            char a1[32], a2[32], a3[32];
            ensure_l_val(instr->operands.fd_io.fd, get_val_type(func, instr->operands.fd_io.fd), out, mod, a1);
            ensure_l_val(instr->operands.fd_io.buf, get_val_type(func, instr->operands.fd_io.buf), out, mod, a2);
            ensure_l_val(instr->operands.fd_io.count, get_val_type(func, instr->operands.fd_io.count), out, mod, a3);
            fprintf(out, "\t%s =l call $__zoril_syscall_3(l 0, l %s, l %s, l %s)\n", res_buf, a1, a2, a3);
            break;
        }
        case IL_OP_FD_WRITE: { /* write(fd, buf, count) -- syscall 1 */
            char a1[32], a2[32], a3[32];
            ensure_l_val(instr->operands.fd_io.fd, get_val_type(func, instr->operands.fd_io.fd), out, mod, a1);
            ensure_l_val(instr->operands.fd_io.buf, get_val_type(func, instr->operands.fd_io.buf), out, mod, a2);
            ensure_l_val(instr->operands.fd_io.count, get_val_type(func, instr->operands.fd_io.count), out, mod, a3);
            fprintf(out, "\t%s =l call $__zoril_syscall_3(l 1, l %s, l %s, l %s)\n", res_buf, a1, a2, a3);
            break;
        }
        default: break;
    }
}

static void emit_async_instr(const ILModule* mod, const ILFunction* func, const ILInstruction* instr, FILE* out) {
    char res_buf[16];
    qbe_map_ssa(instr->result_id, res_buf);
    switch (instr->opcode) {
        case IL_OP_ASYNC_SETUP: { /* Linux: io_uring_setup(entries, params=NULL) -- syscall 425 */
            char a1[32];
            ensure_l_val(instr->operands.async_setup.entries, get_val_type(func, instr->operands.async_setup.entries), out, mod, a1);
            fprintf(out, "\t%s =l call $__zoril_syscall_2(l 425, l %s, l 0)\n", res_buf, a1);
            break;
        }
        case IL_OP_ASYNC_ENTER: { /* Linux: io_uring_enter(fd, to_submit, min_complete, flags=0) -- syscall 426 */
            char a1[32], a2[32], a3[32];
            ensure_l_val(instr->operands.async_enter.ctx, get_val_type(func, instr->operands.async_enter.ctx), out, mod, a1);
            ensure_l_val(instr->operands.async_enter.to_submit, get_val_type(func, instr->operands.async_enter.to_submit), out, mod, a2);
            ensure_l_val(instr->operands.async_enter.min_complete, get_val_type(func, instr->operands.async_enter.min_complete), out, mod, a3);
            fprintf(out, "\t%s =l call $__zoril_syscall_4(l 426, l %s, l %s, l %s, l 0)\n", res_buf, a1, a2, a3);
            break;
        }
        case IL_OP_ASYNC_CLOSE: { /* Linux: close(ring_fd) -- syscall 3 */
            char a1[32];
            ensure_l_val(instr->operands.async_close.ctx, get_val_type(func, instr->operands.async_close.ctx), out, mod, a1);
            fprintf(out, "\tcall $__zoril_syscall_1(l 3, l %s)\n", a1);
            break;
        }
        default: break;
    }
}

static void emit_arith_instr(const ILModule* mod, const ILFunction* func, const ILInstruction* instr, const char* ty_str, FILE* out) {
    char res_buf[16];
    switch (instr->opcode) {
        case IL_OP_ADD:
        case IL_OP_SUB:
        case IL_OP_MUL:
        case IL_OP_DIV:
        case IL_OP_REM:
        case IL_OP_AND:
        case IL_OP_OR:
        case IL_OP_XOR:
        case IL_OP_SHL:
        case IL_OP_SHR: {
            const char* op;
            const ILType* left_ty = get_val_type(func, instr->operands.binary.left);
            switch (instr->opcode) {
                case IL_OP_ADD: op = "add"; break;
                case IL_OP_SUB: op = "sub"; break;
                case IL_OP_MUL: op = "mul"; break;
                case IL_OP_DIV: op = (is_unsigned_type(left_ty)) ? "udiv" : "div"; break;
                case IL_OP_REM: op = (is_unsigned_type(left_ty)) ? "urem" : "rem"; break;
                case IL_OP_AND: op = "and"; break;
                case IL_OP_OR:  op = "or";  break;
                case IL_OP_XOR: op = "xor"; break;
                case IL_OP_SHL: op = "shl"; break;
                case IL_OP_SHR: op = (is_unsigned_type(left_ty)) ? "shr" : "sar"; break;
                default: op = "add"; break;
            }
            qbe_map_ssa(instr->result_id, res_buf);
            fprintf(out, "\t%s =%s %s ", res_buf, ty_str ? ty_str : "w", op);
            emit_val(instr->operands.binary.left, out);
            fprintf(out, ", ");
            emit_val(instr->operands.binary.right, out);
            fprintf(out, "\n");
            break;
        }
        case IL_OP_CMP_LT:
        case IL_OP_CMP_LE:
        case IL_OP_CMP_GT:
        case IL_OP_CMP_GE:
        case IL_OP_CMP_EQ:
        case IL_OP_CMP_NE: {
            qbe_map_ssa(instr->result_id, res_buf);
            const ILType* left_ty = get_val_type(func, instr->operands.binary.left);
            const char* op_ty_str = qbe_map_type(left_ty);
            const char* suffix = get_cmp_suffix(instr->opcode, op_ty_str ? op_ty_str : "w", is_unsigned_type(left_ty));
            fprintf(out, "\t%s =w %s ", res_buf, suffix);
            emit_val(instr->operands.binary.left, out);
            fprintf(out, ", ");
            emit_val(instr->operands.binary.right, out);
            fprintf(out, "\n");
            break;
        }
        case IL_OP_WRAPPING_ADD:
        case IL_OP_WRAPPING_SUB:
        case IL_OP_WRAPPING_MUL: {
            const char* op = (instr->opcode == IL_OP_WRAPPING_ADD) ? "add" :
                             (instr->opcode == IL_OP_WRAPPING_SUB) ? "sub" : "mul";
            const ILType* res_ty = instr->result_type;
            qbe_map_ssa(instr->result_id, res_buf);
            
            if (res_ty && (res_ty->kind == IL_TY_U8 || res_ty->kind == IL_TY_I8 || 
                          res_ty->kind == IL_TY_U16 || res_ty->kind == IL_TY_I16)) {
                uint32_t raw_id = ((ILModule*)mod)->next_label_id++;
                fprintf(out, "\t%%raw%u =%s %s ", raw_id, ty_str ? ty_str : "w", op);
                emit_val(instr->operands.binary.left, out);
                fprintf(out, ", ");
                emit_val(instr->operands.binary.right, out);
                fprintf(out, "\n");
                
                if (res_ty->kind == IL_TY_U8 || res_ty->kind == IL_TY_I8) {
                    if (res_ty->kind == IL_TY_I8) {
                        uint32_t trunc_id = ((ILModule*)mod)->next_label_id++;
                        fprintf(out, "\t%%trunc%u =w and %%raw%u, 255\n", trunc_id, raw_id);
                        fprintf(out, "\t%s =w extsb %%trunc%u\n", res_buf, trunc_id);
                    } else {
                        fprintf(out, "\t%s =w and %%raw%u, 255\n", res_buf, raw_id);
                    }
                } else { // U16 or I16
                    if (res_ty->kind == IL_TY_I16) {
                        uint32_t trunc_id = ((ILModule*)mod)->next_label_id++;
                        fprintf(out, "\t%%trunc%u =w and %%raw%u, 65535\n", trunc_id, raw_id);
                        fprintf(out, "\t%s =w extsh %%trunc%u\n", res_buf, trunc_id);
                    } else {
                        fprintf(out, "\t%s =w and %%raw%u, 65535\n", res_buf, raw_id);
                    }
                }
            } else {
                fprintf(out, "\t%s =%s %s ", res_buf, ty_str ? ty_str : "w", op);
                emit_val(instr->operands.binary.left, out);
                fprintf(out, ", ");
                emit_val(instr->operands.binary.right, out);
                fprintf(out, "\n");
            }
            break;
        }
        case IL_OP_SATURATING_ADD: {
            const char* kind = ty_str ? ty_str : "w";
            uint32_t label_id = mod ? ((ILModule*)mod)->next_label_id++ : 0;
            
            qbe_map_ssa(instr->result_id, res_buf);
            fprintf(out, "\t%%raw%u =%s add ", label_id, kind);
            emit_val(instr->operands.binary.left, out);
            fprintf(out, ", ");
            emit_val(instr->operands.binary.right, out);
            fprintf(out, "\n");
            
            fprintf(out, "\t%%overflow%u =w cult%s %%raw%u, ", label_id, kind, label_id);
            emit_val(instr->operands.binary.left, out);
            fprintf(out, "\n");
            
            if (strcmp(kind, "l") == 0) {
                fprintf(out, "\t%%ext_overflow%u =l extuw %%overflow%u\n", label_id, label_id);
                fprintf(out, "\t%%neg%u =l sub 0, %%ext_overflow%u\n", label_id, label_id);
            } else {
                fprintf(out, "\t%%neg%u =w sub 0, %%overflow%u\n", label_id, label_id);
            }
            
            fprintf(out, "\t%s =%s or %%raw%u, %%neg%u\n", res_buf, kind, label_id, label_id);
            break;
        }
        case IL_OP_CHECKED_ADD:
        case IL_OP_CHECKED_SUB:
        case IL_OP_CHECKED_MUL: {
            const ILType* left_ty = get_val_type(func, instr->operands.binary.left);
            const char* kind = qbe_map_type(left_ty);
            if (!kind) kind = "w";
            const char* op = (instr->opcode == IL_OP_CHECKED_ADD) ? "add" :
                             (instr->opcode == IL_OP_CHECKED_SUB) ? "sub" : "mul";
            
            qbe_map_ssa(instr->result_id, res_buf);
            
            fprintf(out, "\t%s =%s %s ", res_buf, kind, op);
            emit_val(instr->operands.binary.left, out);
            fprintf(out, ", ");
            emit_val(instr->operands.binary.right, out);
            fprintf(out, "\n");
            
            // In QBE we can't easily trap on overflow without splitting the block,
            // which breaks PHI predecessors. Proper checked arithmetic requires
            // explicit IL control flow or a different lowering strategy.
            // For now, emit the operation so it type-checks and runs as wrapping.
            break;
        }
        default: ICE("Unhandled arithmetic opcode: %d", instr->opcode); break;
    }
}

static void emit_mem_instr(const ILModule* mod, const ILFunction* func, const ILInstruction* instr, const char* ty_str, FILE* out) {
    (void)ty_str;
    char res_buf[16];
    switch (instr->opcode) {
        case IL_OP_ALLOC: {
            const ILType* alloc_ty = instr->result_type && (instr->result_type->kind == IL_TY_PTR || instr->result_type->kind == IL_TY_BOX) ? instr->result_type->as.ptr.pointee : NULL;
            size_t size = il_type_size(mod, alloc_ty);
            qbe_map_ssa(instr->result_id, res_buf);
            
            if (instr->operands.alloc.allocator_id != 0) {
                fprintf(out, "\t%s =l call $zoril_allocator_alloc(l ", res_buf);
                emit_val(instr->operands.alloc.allocator_id, out);
                fprintf(out, ", l %zu)\n", size);
            } else if (instr->operands.alloc.region_id == REGION_HEAP) {
                fprintf(out, "\t%s =l call $malloc(l %zu)\n", res_buf, size);
            }
            // Local stack allocations are hoisted to the entry block.
            break;
        }
        case IL_OP_LOAD: {
            const ILType* ptr_ty = get_val_type(func, instr->operands.load.ptr);
            if (ptr_ty == NULL || (ptr_ty->kind != IL_TY_PTR && ptr_ty->kind != IL_TY_BOX)) {
                ICE("IL_OP_LOAD operand is not a pointer");
                return;
            }
            const ILType* res_type = instr->result_type;
            qbe_map_ssa(instr->result_id, res_buf);
            if (res_type && (res_type->kind == IL_TY_STRUCT || res_type->kind == IL_TY_SUM || res_type->kind == IL_TY_ARRAY || res_type->kind == IL_TY_TUPLE || res_type->kind == IL_TY_SLICE)) {
                size_t size = il_type_size(mod, res_type);
                fprintf(out, "\tcall $memcpy(l %s, l ", res_buf);
                emit_val(instr->operands.load.ptr, out);
                fprintf(out, ", l %zu)\n", size == 0 ? 8 : size);
            } else {
                const char* r_ty_str = qbe_map_type(res_type);
                if (!r_ty_str) return; // unit type, nothing to load
                const char* l_ty_str = qbe_map_load_type(res_type);
                fprintf(out, "\t%s =%s load%s ", res_buf, r_ty_str, l_ty_str);
                emit_val(instr->operands.load.ptr, out);
                fprintf(out, "\n");
            }
            break;
        }
        case IL_OP_STORE: {
            const ILType* ptr_type = get_val_type(func, instr->operands.store.ptr);
            const ILType* val_type = NULL;
            if (ptr_type && (ptr_type->kind == IL_TY_PTR || ptr_type->kind == IL_TY_BOX)) {
                val_type = (ptr_type->kind == IL_TY_PTR) ? ptr_type->as.ptr.pointee : ptr_type->as.box.pointee;
            } else {
                val_type = get_val_type(func, instr->operands.store.value);
            }

            if (val_type && (val_type->kind == IL_TY_STRUCT || val_type->kind == IL_TY_SUM || val_type->kind == IL_TY_ARRAY || val_type->kind == IL_TY_TUPLE || val_type->kind == IL_TY_SLICE)) {
                size_t size = il_type_size(mod, val_type);
                fprintf(out, "\t# memcpy size %zu\n", size);
                fprintf(out, "\tcall $memcpy(l ");
                emit_val(instr->operands.store.ptr, out);
                fprintf(out, ", l ");
                emit_val(instr->operands.store.value, out);
                fprintf(out, ", l %zu)\n", size);
            } else {
                const char* s_ty_str = qbe_map_store_type(val_type);
                if (!s_ty_str) return; // unit type, nothing to store
                fprintf(out, "\tstore%s ", s_ty_str);
                emit_val(instr->operands.store.value, out);
                fprintf(out, ", ");
                emit_val(instr->operands.store.ptr, out);
                fprintf(out, "\n");
            }
            break;
        }
        case IL_OP_DROP: {
            const ILType* val_ty = get_val_type(func, instr->operands.drop.value);
            if (val_ty && val_ty->kind == IL_TY_BOX) {
                fprintf(out, "\tcall $free(l ");
                emit_val(instr->operands.drop.value, out);
                fprintf(out, ")\n");
            } else {
                fprintf(out, "\t# drop ");
                emit_val(instr->operands.drop.value, out);
                fprintf(out, "\n");
            }
            break;
        }
        case IL_OP_GLOBAL_ADDR: {
            qbe_map_ssa(instr->result_id, res_buf);
            fprintf(out, "\t%s =l copy $g%u\n", res_buf, instr->operands.global_addr.global_id);
            break;
        }
        case IL_OP_FUNC_ADDR: {
            qbe_map_ssa(instr->result_id, res_buf);
            const char* func_name = "unknown";
            bool is_extern = true;
            if (mod) {
                for (uint32_t f = 0; f < mod->function_count; f++) {
                    if (mod->functions[f]->id == instr->operands.func_addr.func_id) {
                        func_name = mod->functions[f]->name;
                        is_extern = mod->functions[f]->is_extern;
                        break;
                    }
                }
            }
            fprintf(out, "\t%s =l copy ", res_buf);
            qbe_emit_func_sym(func_name, is_extern, out);
            fprintf(out, "\n");
            break;
        }
        case IL_OP_FIELD_ADDR: {
            const ILType* ptr_type = get_val_type(func, instr->operands.field_addr.struct_ptr);
            if (!ptr_type || (ptr_type->kind != IL_TY_PTR && ptr_type->kind != IL_TY_BOX)) {
                ICE("IL_OP_FIELD_ADDR operand is not a pointer"); return;
            }
            const ILType* agg_ty = (ptr_type->kind == IL_TY_PTR) ? ptr_type->as.ptr.pointee : ptr_type->as.box.pointee;
            if (!agg_ty || (agg_ty->kind != IL_TY_STRUCT && agg_ty->kind != IL_TY_SUM && agg_ty->kind != IL_TY_TUPLE && agg_ty->kind != IL_TY_SLICE)) {
                ICE("IL_OP_FIELD_ADDR target is not a struct/sum/tuple/slice"); return;
            }
            size_t offset = 0;
            if (agg_ty->kind == IL_TY_TUPLE) {
                offset = il_type_get_tuple_field_offset(mod, agg_ty, instr->operands.field_addr.field_index);
            } else if (agg_ty->kind == IL_TY_SLICE) {
                if (instr->operands.field_addr.field_index == 0) offset = 0;
                else if (instr->operands.field_addr.field_index == 1) offset = 8;
                else ICE("IL_OP_FIELD_ADDR slice index out of bounds");
            } else {
                const ILTypeDef* def = il_mod_get_type_def(mod, agg_ty->as.struct_sum.type_def_id);
                offset = il_type_def_get_field_offset(mod, def, instr->operands.field_addr.field_index);
            }
            
            qbe_map_ssa(instr->result_id, res_buf);
            fprintf(out, "\t%s =l add ", res_buf);
            emit_val(instr->operands.field_addr.struct_ptr, out);
            fprintf(out, ", %zu\n", offset);
            break;
        }
        default: ICE("Unhandled memory opcode: %d", instr->opcode); break;
    }
}

static const ILBasicBlock* find_block(const ILFunction* func, uint32_t block_id) {
    for (uint32_t i = 0; i < func->block_count; i++) {
        if (func->blocks[i]->id == block_id) return func->blocks[i];
    }
    return NULL;
}

static bool is_phi_large(const ILInstruction* instr) {
    if (instr->opcode != IL_OP_PHI) return false;
    if (instr->operands.phi.num_incoming > 32) return true;
    const ILType* ty = instr->result_type;
    if (ty && (ty->kind == IL_TY_STRUCT || ty->kind == IL_TY_SUM ||
               ty->kind == IL_TY_ARRAY || ty->kind == IL_TY_TUPLE ||
               ty->kind == IL_TY_SLICE)) {
        return true;
    }
    return false;
}

static void emit_phi_stores(const ILModule* mod, const ILFunction* func, uint32_t current_block_id, uint32_t target_block_id, FILE* out) {
    const ILBasicBlock* target = find_block(func, target_block_id);
    if (!target) return;

    for (uint32_t i = 0; i < target->instr_count; i++) {
        const ILInstruction* instr = target->instructions[i];
        if (instr->opcode != IL_OP_PHI) break;
        if (!is_phi_large(instr)) continue;

        // Find if this block is an incoming predecessor
        for (uint32_t j = 0; j < instr->operands.phi.num_incoming; j++) {
            if (instr->operands.phi.incoming[j].block_id == current_block_id) {
                char slot_buf[32];
                sprintf(slot_buf, "%%phi_slot_%u", instr->result_id);
                const ILType* val_ty = get_val_type(func, instr->operands.phi.incoming[j].value_id);
                
                bool phi_result_is_aggregate = instr->result_type &&
                    (instr->result_type->kind == IL_TY_STRUCT || instr->result_type->kind == IL_TY_SUM ||
                     instr->result_type->kind == IL_TY_ARRAY || instr->result_type->kind == IL_TY_TUPLE ||
                     instr->result_type->kind == IL_TY_SLICE);

                if (phi_result_is_aggregate) {
                    if (requires_pass_by_ref(mod, instr->result_type)) {
                        // Large aggregate: always a memcpy from a pointer
                        size_t size = il_type_size(mod, instr->result_type);
                        fprintf(out, "\tcall $memcpy(l %s, l ", slot_buf);
                        emit_val(instr->operands.phi.incoming[j].value_id, out);
                        fprintf(out, ", l %zu)\n", size);
                    } else {
                        // Small aggregate: stored as a value (w/l/s/d)
                        const char* ty = qbe_map_store_type(instr->result_type);
                        fprintf(out, "\tstore%s ", ty ? ty : "w");
                        emit_val(instr->operands.phi.incoming[j].value_id, out);
                        fprintf(out, ", %s\n", slot_buf);
                    }
                } else {
                    const char* ty = qbe_map_store_type(val_ty);
                    fprintf(out, "\tstore%s ", ty ? ty : "w");
                    emit_val(instr->operands.phi.incoming[j].value_id, out);
                    fprintf(out, ", %s\n", slot_buf);
                }
                break;
            }
        }
    }
}

static void emit_control_flow_instr(ILModule* mod, const ILFunction* func, const ILInstruction* instr, uint32_t current_block_id, FILE* out) {
    (void)mod;
    switch (instr->opcode) {
        case IL_OP_RETURN: {
            const ILType* ret_ty = get_val_type(func, instr->operands.ret.value);
            if (is_unit_main(func)) {
                fprintf(out, "\tret 0\n");
            } else if (func->is_sret || (ret_ty && ret_ty->kind == IL_TY_UNIT)) {
                fprintf(out, "\tret\n");
            } else {
                fprintf(out, "\tret ");
                emit_val(instr->operands.ret.value, out);
                fprintf(out, "\n");
            }
            break;
        }
        case IL_OP_BRANCH: {
            emit_phi_stores(mod, func, current_block_id, instr->operands.branch.then_block_id, out);
            emit_phi_stores(mod, func, current_block_id, instr->operands.branch.else_block_id, out);
            fprintf(out, "\tjnz ");
            emit_val(instr->operands.branch.condition, out);
            fprintf(out, ", @b%u, @b%u\n",
                instr->operands.branch.then_block_id,
                instr->operands.branch.else_block_id);
            break;
        }
        case IL_OP_JUMP: {
            emit_phi_stores(mod, func, current_block_id, instr->operands.jump.target_block_id, out);
            fprintf(out, "\tjmp @b%u\n", instr->operands.jump.target_block_id);
            break;
        }

        case IL_OP_BOUNDS_CHECK: {
            // No-op in QBE because we now use explicit block splitting in IL.
            // This instruction remains as a marker for the verifier.
            break;
        }
        default: break;
    }
}

static void emit_sum_instr(const ILModule* mod, const ILFunction* func, const ILInstruction* instr, uint32_t current_block_id, const char* ty_str, FILE* out) {
    char res_buf[16];
    switch (instr->opcode) {
        case IL_OP_IS_SOME: {
            qbe_map_ssa(instr->result_id, res_buf);
            const ILType* sum_ty = get_val_type(func, instr->operands.move.source);
            if (sum_ty && (sum_ty->kind == IL_TY_PTR || sum_ty->kind == IL_TY_BOX)) sum_ty = sum_ty->as.ptr.pointee;
            size_t tag_sz = 4;
            if (sum_ty && sum_ty->kind == IL_TY_SUM) {
                const ILTypeDef* def = il_mod_get_type_def(mod, sum_ty->as.struct_sum.type_def_id);
                if (def) tag_sz = il_type_def_tag_size(def);
            }
            const char* load_inst = tag_sz == 1 ? "loadub" : (tag_sz == 2 ? "loaduh" : "loadw");
            fprintf(out, "\t%%tag =w %s ", load_inst);
            emit_val(instr->operands.move.source, out);
            fprintf(out, "\n");
            fprintf(out, "\t%s =w ceqw %%tag, 1\n", res_buf);
            break;
        }
        case IL_OP_UNWRAP: {
            const ILType* res_type = instr->result_type;
            const ILType* sum_ty = get_val_type(func, instr->operands.move.source);
            if (sum_ty->kind == IL_TY_PTR || sum_ty->kind == IL_TY_BOX) {
                sum_ty = sum_ty->as.ptr.pointee;
            }
            const ILTypeDef* def = il_mod_get_type_def(mod, sum_ty->as.struct_sum.type_def_id);
            size_t offset = il_type_def_get_field_offset(mod, def, 0); // All variants share same offset

            qbe_map_ssa(instr->result_id, res_buf);
            fprintf(out, "\t%%payload_ptr%u =l add ", instr->result_id);
            emit_val(instr->operands.move.source, out);
            fprintf(out, ", %zu\n", offset);
            if (res_type && (res_type->kind == IL_TY_STRUCT || res_type->kind == IL_TY_SUM || res_type->kind == IL_TY_ARRAY || res_type->kind == IL_TY_TUPLE || res_type->kind == IL_TY_SLICE)) {
                size_t p_size = il_type_size(mod, res_type);
                fprintf(out, "\tcall $memcpy(l %s, l %%payload_ptr%u, l %zu)\n", res_buf, instr->result_id, p_size);
            } else {
                const char* u_ty_str = ty_str ? ty_str : "w";
                const char* l_ty = qbe_map_load_type(res_type);
                fprintf(out, "\t%s =%s load%s %%payload_ptr%u\n", res_buf, u_ty_str, l_ty ? l_ty : u_ty_str, instr->result_id);
            }
            break;
        }
        case IL_OP_VARIANT_MATCH: {
            const ILType* sum_ptr_ty = get_val_type(func, instr->operands.variant_match.sum_ptr);
            if (sum_ptr_ty == NULL || (sum_ptr_ty->kind != IL_TY_PTR && sum_ptr_ty->kind != IL_TY_BOX)) {
                ICE("IL_OP_VARIANT_MATCH operand is not a pointer"); return;
            }
            uint32_t label_id = mod ? ((ILModule*)mod)->next_label_id++ : 0;
            
            size_t tag_sz = 4;
            const ILType* sum_ty = sum_ptr_ty;
            if (sum_ty && (sum_ty->kind == IL_TY_PTR || sum_ty->kind == IL_TY_BOX)) {
                sum_ty = (sum_ty->kind == IL_TY_PTR) ? sum_ty->as.ptr.pointee : sum_ty->as.box.pointee;
            }
            if (sum_ty && (sum_ty->kind == IL_TY_SUM || sum_ty->kind == IL_TY_STRUCT)) {
                const ILTypeDef* def = il_mod_get_type_def(mod, sum_ty->as.struct_sum.type_def_id);
                if (def) tag_sz = il_type_def_tag_size(def);
            }
            const char* load_inst = tag_sz == 1 ? "loadub" : (tag_sz == 2 ? "loaduh" : "loadw");
            fprintf(out, "\t%%tag%u =w %s ", label_id, load_inst);
            emit_val(instr->operands.variant_match.sum_ptr, out);
            fprintf(out, "\n");

            uint32_t tag = instr->operands.variant_match.variant_index;
            if (!sum_ty || (sum_ty->kind != IL_TY_SUM && sum_ty->kind != IL_TY_STRUCT)) {
                ICE("IL_OP_VARIANT_MATCH target is not a sum type"); return;
            }
            const ILTypeDef* def = il_mod_get_type_def(mod, sum_ty->as.struct_sum.type_def_id);
            if (!def) {
                ICE("IL_OP_VARIANT_MATCH sum type definition not found"); return;
            }
            if (instr->operands.variant_match.variant_index < def->field_count) {
                if (def->fields[instr->operands.variant_match.variant_index].has_tag) {
                    tag = (uint32_t)def->fields[instr->operands.variant_match.variant_index].tag;
                }
            }

            if (instr->operands.variant_match.target_block_id == IL_NO_BLOCK) {
                // Value form: the comparison is the result, and control flow is a later branch.
                qbe_map_ssa(instr->result_id, res_buf);
                fprintf(out, "\t%s =w ceqw %%tag%u, %u\n", res_buf, label_id, tag);
                break;
            }
            fprintf(out, "\t%%match%u =w ceqw %%tag%u, %u\n", label_id, label_id, tag);
            emit_phi_stores(mod, func, current_block_id, instr->operands.variant_match.target_block_id, out);
            emit_phi_stores(mod, func, current_block_id, instr->operands.variant_match.next_block_id, out);
            fprintf(out, "\tjnz %%match%u, @b%u, @b%u\n", label_id, 
                instr->operands.variant_match.target_block_id,
                instr->operands.variant_match.next_block_id);

            break;
        }

        case IL_OP_SUM_CONSTRUCT: {
            qbe_map_ssa(instr->result_id, res_buf);
            const ILTypeDef* def = il_mod_get_type_def(mod, instr->operands.sum_construct.type_def_id);
            if (!def) {
                ICE("IL_OP_SUM_CONSTRUCT type definition not found"); return;
            }
            
            uint32_t tag = instr->operands.sum_construct.variant_index;
            if (def && instr->operands.sum_construct.variant_index < def->field_count) {
                if (def->fields[instr->operands.sum_construct.variant_index].has_tag) {
                    tag = (uint32_t)def->fields[instr->operands.sum_construct.variant_index].tag;
                }
            }

            // Store tag
            size_t tag_sz = il_type_def_tag_size(def);
            const char* store_inst = tag_sz == 1 ? "storeb" : (tag_sz == 2 ? "storeh" : "storew");
            fprintf(out, "\t%s %u, %s\n", store_inst, tag, res_buf);
            
            // Store payload
            uint32_t payload_id = instr->operands.sum_construct.payload_id;
            const ILType* payload_ty = get_val_type(func, payload_id);
            if (payload_ty && payload_ty->kind != IL_TY_UNIT) {
                const ILType* expected_payload_ty = def->fields[instr->operands.sum_construct.variant_index].type;
                if (!expected_payload_ty || il_type_is_generic_mod(mod, expected_payload_ty)) {
                    expected_payload_ty = payload_ty;
                }
                size_t offset = il_type_def_get_field_offset(mod, def, instr->operands.sum_construct.variant_index);
                fprintf(out, "\t%%payload_ptr%u =l add %s, %zu\n", instr->result_id, res_buf, offset);
                
                if (expected_payload_ty->kind == IL_TY_STRUCT || expected_payload_ty->kind == IL_TY_SUM || expected_payload_ty->kind == IL_TY_ARRAY || expected_payload_ty->kind == IL_TY_TUPLE || expected_payload_ty->kind == IL_TY_SLICE) {
                    size_t p_size = il_type_size(mod, expected_payload_ty);
                    fprintf(out, "\tcall $memcpy(l %%payload_ptr%u, l ", instr->result_id);
                    emit_val(payload_id, out);
                    fprintf(out, ", l %zu)\n", p_size == 0 ? 8 : p_size);
                } else {
                    const char* p_ty_str = qbe_map_store_type(expected_payload_ty);
                    fprintf(out, "\tstore%s ", p_ty_str);
                    emit_val(payload_id, out);
                    fprintf(out, ", %%payload_ptr%u\n", instr->result_id);
                }
            }
            break;
        }
        default: ICE("Unhandled sum opcode: %d", instr->opcode); break;
    }
}

static void emit_array_instr(const ILModule* mod, const ILFunction* func, const ILInstruction* instr, FILE* out) {
    char res_buf[16];
    qbe_map_ssa(instr->result_id, res_buf);
    
    size_t elem_size = 0;
    const char* elem_ty = "w";
    
    if (instr->result_type && instr->result_type->kind == IL_TY_ARRAY) {
        elem_size = il_type_size(mod, instr->result_type->as.array.element);
        elem_ty = qbe_map_store_type(instr->result_type->as.array.element);
    }
    if (!elem_ty) elem_ty = "w";

    for (uint32_t i = 0; i < instr->operands.array_construct.count; i++) {
        fprintf(out, "\t%%elem_addr_%u_%u =l add %s, %zu\n", instr->result_id, i, res_buf, i * elem_size);
        uint32_t eid = instr->operands.array_construct.element_ids[i];
        const ILType* ety = get_val_type(func, eid);
        if (ety && (ety->kind == IL_TY_STRUCT || ety->kind == IL_TY_SUM || ety->kind == IL_TY_ARRAY || ety->kind == IL_TY_TUPLE)) {
            fprintf(out, "\tcall $memcpy(l %%elem_addr_%u_%u, l ", instr->result_id, i);
            emit_val(eid, out);
            fprintf(out, ", l %zu)\n", elem_size);
        } else {
            fprintf(out, "\tstore%s ", elem_ty);
            emit_val(eid, out);
            fprintf(out, ", %%elem_addr_%u_%u\n", instr->result_id, i);
        }
    }
}

static void emit_slice_instr(const ILModule* mod, const ILFunction* func, const ILInstruction* instr, FILE* out) {
    char res_buf[16];
    switch (instr->opcode) {
        case IL_OP_SLICE_LEN: {
            const ILType* slice_ptr_ty = get_val_type(func, instr->operands.slice_op.slice_ptr);
            if (!slice_ptr_ty || (slice_ptr_ty->kind != IL_TY_PTR && slice_ptr_ty->kind != IL_TY_SLICE)) {
                ICE("IL_OP_SLICE_LEN operand is not a pointer or slice"); return;
            }
            qbe_map_ssa(instr->result_id, res_buf);
            fprintf(out, "\t%%len_ptr%u =l add ", instr->result_id);
            emit_val(instr->operands.slice_op.slice_ptr, out);
            fprintf(out, ", 8\n");
            fprintf(out, "\t%s =l loadl %%len_ptr%u\n", res_buf, instr->result_id);
            break;
        }
        case IL_OP_SLICE_DATA: {
            const ILType* slice_ptr_ty = get_val_type(func, instr->operands.slice_op.slice_ptr);
            if (!slice_ptr_ty || (slice_ptr_ty->kind != IL_TY_PTR && slice_ptr_ty->kind != IL_TY_SLICE)) {
                ICE("IL_OP_SLICE_DATA operand is not a pointer or slice"); return;
            }
            qbe_map_ssa(instr->result_id, res_buf);
            fprintf(out, "\t%s =l loadl ", res_buf);
            emit_val(instr->operands.slice_op.slice_ptr, out);
            fprintf(out, "\n");
            break;
        }
        case IL_OP_SLICE_LOAD: {
            fprintf(out, "\t%%data_ptr%u =l loadl ", instr->result_id);
            emit_val(instr->operands.slice_load.slice_ptr, out);
            fprintf(out, "\n");
            
            size_t elem_size = il_type_size(mod, instr->result_type);
            const char* sl_ty_str = qbe_map_load_type(instr->result_type);
            const char* r_ty_str = qbe_map_type(instr->result_type);
            if (!r_ty_str) r_ty_str = "w";

            fprintf(out, "\t%%offset%u =l mul ", instr->result_id);
            emit_val(instr->operands.slice_load.index, out);
            fprintf(out, ", %zu\n", elem_size);
            fprintf(out, "\t%%elem_addr%u =l add %%data_ptr%u, %%offset%u\n", instr->result_id, instr->result_id, instr->result_id);
            qbe_map_ssa(instr->result_id, res_buf);
            if (instr->result_type && (instr->result_type->kind == IL_TY_STRUCT || instr->result_type->kind == IL_TY_SUM || instr->result_type->kind == IL_TY_ARRAY || instr->result_type->kind == IL_TY_TUPLE || instr->result_type->kind == IL_TY_SLICE)) {
                fprintf(out, "\tcall $memcpy(l %s, l %%elem_addr%u, l %zu)\n", res_buf, instr->result_id, elem_size);
            } else {
                fprintf(out, "\t%s =%s load%s %%elem_addr%u\n", res_buf, r_ty_str, sl_ty_str, instr->result_id);
            }
            break;
        }
        case IL_OP_SLICE_STORE: {
            fprintf(out, "\t%%data_ptr%u =l loadl ", instr->result_id);
            emit_val(instr->operands.slice_store.slice_ptr, out);
            fprintf(out, "\n");

            // Size and store by the slice's element type, not the value's: an aggregate value is
            // carried as a pointer to it, so sizing by the value stored an 8-byte address at an
            // 8-byte stride into a slice of (say) 24-byte structs.
            const ILType* val_ty = get_val_type(func, instr->operands.slice_store.value);
            const ILType* slice_ty = get_val_type(func, instr->operands.slice_store.slice_ptr);
            if (slice_ty && slice_ty->kind == IL_TY_PTR) slice_ty = slice_ty->as.ptr.pointee;
            const ILType* elem_ty = (slice_ty && slice_ty->kind == IL_TY_SLICE) ? slice_ty->as.slice.element : val_ty;
            size_t elem_size = il_type_size(mod, elem_ty);
            const char* ss_ty_str = qbe_map_store_type(elem_ty);

            fprintf(out, "\t%%offset%u =l mul ", instr->result_id);
            emit_val(instr->operands.slice_store.index, out);
            fprintf(out, ", %zu\n", elem_size);
            fprintf(out, "\t%%elem_addr%u =l add %%data_ptr%u, %%offset%u\n", instr->result_id, instr->result_id, instr->result_id);

            if (elem_ty && is_aggregate_type_layout(elem_ty)) {
                fprintf(out, "\tcall $memcpy(l %%elem_addr%u, l ", instr->result_id);
                emit_val(instr->operands.slice_store.value, out);
                fprintf(out, ", l %zu)\n", elem_size);
            } else {
                fprintf(out, "\tstore%s ", ss_ty_str);
                emit_val(instr->operands.slice_store.value, out);
                fprintf(out, ", %%elem_addr%u\n", instr->result_id);
            }
            break;
        }
        case IL_OP_SLICE_CONSTRUCT: {
            if (!instr->result_type || instr->result_type->kind != IL_TY_SLICE) {
                ICE("IL_OP_SLICE_CONSTRUCT result is not a slice type"); return;
            }
            qbe_map_ssa(instr->result_id, res_buf);
            fprintf(out, "\tstorel ");
            emit_val(instr->operands.slice_construct.ptr, out);
            fprintf(out, ", %s\n", res_buf);
            fprintf(out, "\t%%len_ptr%u =l add %s, 8\n", instr->result_id, res_buf);
            fprintf(out, "\tstorel ");
            emit_val(instr->operands.slice_construct.len, out);
            fprintf(out, ", %%len_ptr%u\n", instr->result_id);
            break;
        }
        case IL_OP_ARRAY_CONSTRUCT:
            emit_array_instr(mod, func, instr, out);
            break;
        case IL_OP_ARRAY_LOAD: {
            size_t elem_size = il_type_size(mod, instr->result_type);
            const char* al_ty_str = qbe_map_load_type(instr->result_type);
            const char* r_ty_str = qbe_map_type(instr->result_type);
            if (!r_ty_str) r_ty_str = "w";
            
            fprintf(out, "\t%%offset_%u =l mul ", instr->result_id);
            emit_val(instr->operands.array_load.index, out);
            fprintf(out, ", %zu\n", elem_size);
            fprintf(out, "\t%%elem_addr_%u =l add ", instr->result_id);
            emit_val(instr->operands.array_load.array_ptr, out);
            fprintf(out, ", %%offset_%u\n", instr->result_id);
            qbe_map_ssa(instr->result_id, res_buf);
            if (instr->result_type && (instr->result_type->kind == IL_TY_STRUCT || instr->result_type->kind == IL_TY_SUM || instr->result_type->kind == IL_TY_ARRAY || instr->result_type->kind == IL_TY_TUPLE || instr->result_type->kind == IL_TY_SLICE)) {
                fprintf(out, "\tcall $memcpy(l %s, l %%elem_addr_%u, l %zu)\n", res_buf, instr->result_id, elem_size);
            } else {
                fprintf(out, "\t%s =%s load%s %%elem_addr_%u\n", res_buf, r_ty_str, al_ty_str, instr->result_id);
            }
            break;
        }
        case IL_OP_ARRAY_STORE: {
            const ILType* val_ty = get_val_type(func, instr->operands.array_store.value);
            size_t elem_size = il_type_size(mod, val_ty);
            const char* as_ty_str = qbe_map_store_type(val_ty);
            
            fprintf(out, "\t%%offset_st_%u =l mul ", instr->result_id);
            emit_val(instr->operands.array_store.index, out);
            fprintf(out, ", %zu\n", elem_size);
            fprintf(out, "\t%%elem_addr_st_%u =l add ", instr->result_id);
            emit_val(instr->operands.array_store.array_ptr, out);
            fprintf(out, ", %%offset_st_%u\n", instr->result_id);
            fprintf(out, "\tstore%s ", as_ty_str);
            emit_val(instr->operands.array_store.value, out);
            fprintf(out, ", %%elem_addr_st_%u\n", instr->result_id);
            break;
        }
        case IL_OP_ELEM_ADDR: {
            const ILType* base_ty = get_val_type(func, instr->operands.elem_addr.base);
            bool is_slice = base_ty->kind == IL_TY_SLICE || (base_ty->kind == IL_TY_PTR && base_ty->as.ptr.pointee && base_ty->as.ptr.pointee->kind == IL_TY_SLICE
                && !il_elem_addr_steps_raw_slices(base_ty, instr->result_type));
            const ILType* elem_ty = NULL;
            if (is_slice) {
                elem_ty = (base_ty->kind == IL_TY_SLICE) ? base_ty->as.slice.element : base_ty->as.ptr.pointee->as.slice.element;
                fprintf(out, "\t%%data_ptr_%u =l loadl ", instr->result_id);
                emit_val(instr->operands.elem_addr.base, out);
                fprintf(out, "\n");
            } else if (base_ty->kind == IL_TY_PTR) {
                const ILType* pointee = base_ty->as.ptr.pointee;
                if (pointee && pointee->kind == IL_TY_ARRAY) {
                    elem_ty = pointee->as.array.element;
                } else {
                    // Raw pointer indexing: pointee IS the element type
                    elem_ty = pointee;
                }
            } else {
                elem_ty = base_ty->as.ptr.pointee->as.array.element;
            }
            
            size_t elem_size = il_type_size(mod, elem_ty);
            
            fprintf(out, "\t%%offset_ea_%u =l mul ", instr->result_id);
            emit_val(instr->operands.elem_addr.index, out);
            fprintf(out, ", %zu\n", elem_size);
            
            qbe_map_ssa(instr->result_id, res_buf);
            fprintf(out, "\t%s =l add ", res_buf);
            if (is_slice) {
                fprintf(out, "%%data_ptr_%u", instr->result_id);
            } else {
                emit_val(instr->operands.elem_addr.base, out);
            }
            fprintf(out, ", %%offset_ea_%u\n", instr->result_id);
            break;
        }
        default: ICE("Unhandled slice opcode: %d", instr->opcode); break;
    }
}

static void emit_conversion_instr(const ILFunction* func, const ILInstruction* instr, const char* ty_str, FILE* out) {
    (void)func;
    if (!ty_str) return;
    char res_buf[16];
    qbe_map_ssa(instr->result_id, res_buf);
    const ILType* src_il_ty;
    if (instr->opcode == IL_OP_MOVE) src_il_ty = get_val_type(func, instr->operands.move.source);
    else if (instr->opcode == IL_OP_BITCAST) src_il_ty = get_val_type(func, instr->operands.bitcast.source);
    else src_il_ty = get_val_type(func, instr->operands.region_cast.source);
    const char* src_ty = qbe_map_type(src_il_ty);
    const char* dst_ty = ty_str;
    const char* op = "copy";
    bool is_unsigned = is_unsigned_type(src_il_ty);

    if (src_ty && dst_ty) {
        if (strcmp(src_ty, "s") == 0 && strcmp(dst_ty, "d") == 0) op = "exts";
        else if (strcmp(src_ty, "d") == 0 && strcmp(dst_ty, "s") == 0) op = "truncd";
        else if (strcmp(src_ty, "s") == 0 && (strcmp(dst_ty, "w") == 0 || strcmp(dst_ty, "l") == 0)) op = is_unsigned ? "stoui" : "stosi";
        else if (strcmp(src_ty, "d") == 0 && (strcmp(dst_ty, "w") == 0 || strcmp(dst_ty, "l") == 0)) op = is_unsigned ? "dtoui" : "dtosi";
        else if (strcmp(src_ty, "w") == 0 && strcmp(dst_ty, "s") == 0) op = is_unsigned ? "uwtof" : "swtof";
        else if (strcmp(src_ty, "l") == 0 && strcmp(dst_ty, "s") == 0) op = is_unsigned ? "ultof" : "sltof";
        else if (strcmp(src_ty, "w") == 0 && strcmp(dst_ty, "d") == 0) op = is_unsigned ? "uwtof" : "swtof";
        else if (strcmp(src_ty, "l") == 0 && strcmp(dst_ty, "d") == 0) op = is_unsigned ? "ultof" : "sltof";
        else if (strcmp(src_ty, "w") == 0 && strcmp(dst_ty, "l") == 0) op = is_unsigned ? "extuw" : "extsw";
    }

    fprintf(out, "\t%s =%s %s ", res_buf, dst_ty ? dst_ty : "w", op);
    if (instr->opcode == IL_OP_MOVE) {
        emit_val(instr->operands.move.source, out);
    } else if (instr->opcode == IL_OP_BITCAST) {
        emit_val(instr->operands.bitcast.source, out);
    } else {
        emit_val(instr->operands.region_cast.source, out);
    }
    fprintf(out, "\n");
}

static void emit_phi_large(const ILModule* mod, const ILFunction* func, const ILInstruction* instr, const char* ty_str, const char* res_buf, FILE* out) {
    (void)func;
    char slot_buf[32];
    sprintf(slot_buf, "%%phi_slot_%u", instr->result_id);
    
    const ILType* res_type = instr->result_type;
    if (requires_pass_by_ref(mod, res_type)) {
        // Large Aggregate Phi: res_buf is already an alloc pointer. Copy slot to res_buf.
        size_t size = il_type_size(mod, res_type);
        fprintf(out, "\tcall $memcpy(l %s, l %s, l %zu)\n", res_buf, slot_buf, size);
    } else {
        const char* qbe_ty = ty_str ? ty_str : "w";
        const char* l_ty = qbe_map_load_type(res_type);
        fprintf(out, "\t%s =%s load%s %s\n", res_buf, qbe_ty, l_ty ? l_ty : qbe_ty, slot_buf);
    }
}

static void emit_other_instr(const ILModule* mod, const ILFunction* func, const ILInstruction* instr, const char* ty_str, FILE* out) {
    char res_buf[16];
    switch (instr->opcode) {
        case IL_OP_CALL: {
            qbe_map_ssa(instr->result_id, res_buf);
            const char* func_name = "abort";
            uint32_t fixed_param_count = 0;
            bool is_variadic = false;
            bool is_extern = true;
            if (mod) {
                for (uint32_t f = 0; f < mod->function_count; f++) {
                    if (mod->functions[f]->id == instr->operands.call.func_id) {
                        func_name = mod->functions[f]->name;
                        fixed_param_count = mod->functions[f]->param_count;
                        is_variadic = mod->functions[f]->is_variadic;
                        is_extern = mod->functions[f]->is_extern;
                        break;
                    }
                }
            }
            if (ty_str) {
                const char* abi_ret = qbe_map_func_abi_type(instr->result_type);
                fprintf(out, "\t%s =%s call ", res_buf, abi_ret ? abi_ret : ty_str);
                qbe_emit_func_sym(func_name, is_extern, out);
                fprintf(out, "(");
            } else {
                fprintf(out, "\tcall ");
                qbe_emit_func_sym(func_name, is_extern, out);
                fprintf(out, "(");
            }

            for (uint32_t i = 0; i < instr->operands.call.num_args; i++) {
                if (is_variadic && i == fixed_param_count) {
                    fprintf(out, "..., ");
                }
                const ILType* aty = get_val_type(func, instr->operands.call.arg_ids[i]);
                const char* arg_ty = qbe_map_abi_type(aty);
                fprintf(out, "%s ", arg_ty ? arg_ty : "l");
                emit_val(instr->operands.call.arg_ids[i], out);
                if (i < instr->operands.call.num_args - 1) fprintf(out, ", ");
            }
            fprintf(out, ")\n");
            break;
        }
        case IL_OP_CALL_PTR: {
            qbe_map_ssa(instr->result_id, res_buf);
            if (ty_str) {
                const char* abi_ret = qbe_map_func_abi_type(instr->result_type);
                fprintf(out, "\t%s =%s call ", res_buf, abi_ret ? abi_ret : ty_str);
            } else {
                fprintf(out, "\tcall ");
            }
            emit_val(instr->operands.call_ptr.func_ptr_id, out);
            fprintf(out, "(");

            bool is_variadic = false;
            uint32_t fixed_param_count = 0;
            const ILType* fty = get_val_type(func, instr->operands.call_ptr.func_ptr_id);
            if (fty && fty->kind == IL_TY_FN) {
                is_variadic = fty->as.function.is_variadic;
                fixed_param_count = fty->as.function.param_count;
            }

            for (uint32_t i = 0; i < instr->operands.call_ptr.num_args; i++) {
                if (is_variadic && i == fixed_param_count) {
                    fprintf(out, "..., ");
                }
                const ILType* aty = get_val_type(func, instr->operands.call_ptr.arg_ids[i]);
                const char* arg_ty = qbe_map_abi_type(aty);
                fprintf(out, "%s ", arg_ty ? arg_ty : "l");
                emit_val(instr->operands.call_ptr.arg_ids[i], out);
                if (i < instr->operands.call_ptr.num_args - 1) fprintf(out, ", ");
            }
            fprintf(out, ")\n");
            break;
        }
        case IL_OP_SYSCALL: {
            qbe_map_ssa(instr->result_id, res_buf);
            uint32_t num_args = instr->operands.syscall_op.num_args;
            char* args_bufs = NULL;
            if (num_args > 0) {
                args_bufs = malloc(num_args * 32);
                for (uint32_t i = 0; i < num_args; i++) {
                    ensure_l_val(instr->operands.syscall_op.arg_ids[i], get_val_type(func, instr->operands.syscall_op.arg_ids[i]), out, mod, args_bufs + i * 32);
                }
            }

            if (ty_str) {
                fprintf(out, "\t%s =%s call $__zoril_syscall_%u(l %u", res_buf, ty_str, num_args, instr->operands.syscall_op.syscall_num);
            } else {
                fprintf(out, "\tcall $__zoril_syscall_%u(l %u", num_args, instr->operands.syscall_op.syscall_num);
            }
            for (uint32_t i = 0; i < num_args; i++) {
                fprintf(out, ", l %s", args_bufs + i * 32);
            }
            fprintf(out, ")\n");
            if (args_bufs) free(args_bufs);
            break;
        }
        case IL_OP_CONST: {
            if (!ty_str) return;
            qbe_map_ssa(instr->result_id, res_buf);
            const char* kind = ty_str;
            if (strcmp(kind, "s") == 0) {
                union { float f; uint32_t u; } uf;
                uf.f = (float)instr->operands.const_val.u.fval;
                fprintf(out, "\t%s =s loads $s_%u\n", res_buf, uf.u);
            } else if (strcmp(kind, "d") == 0) {
                union { double d; uint64_t u; } ud;
                ud.d = instr->operands.const_val.u.fval;
                fprintf(out, "\t%s =d loadd $d_%lu\n", res_buf, ud.u);
            } else {
                fprintf(out, "\t%s =%s copy %lu\n", res_buf, kind, instr->operands.const_val.u.val);
            }
            break;
        }
        case IL_OP_STRING_CONST: {
            qbe_map_ssa(instr->result_id, res_buf);
            if (instr->operands.string_literal.val) {
                uint32_t len = instr->operands.string_literal.len;
                fprintf(out, "\t%s =l alloc8 16\n", res_buf);
                fprintf(out, "\tstorel $str_%u, %s\n", instr->result_id, res_buf);
                fprintf(out, "\t%%len_ptr%u =l add %s, 8\n", instr->result_id, res_buf);
                fprintf(out, "\tstorel %u, %%len_ptr%u\n", len, instr->result_id);
            }
            break;
        }
        case IL_OP_PHI: {
            if (!ty_str) return;
            qbe_map_ssa(instr->result_id, res_buf);
            if (is_phi_large(instr)) {
                emit_phi_large(mod, func, instr, ty_str, res_buf, out);
            } else {
                fprintf(out, "\t%s =%s phi ", res_buf, ty_str);
                for (uint32_t i = 0; i < instr->operands.phi.num_incoming; i++) {
                    if (i > 0) fprintf(out, ", ");
                    fprintf(out, "@b%u ", instr->operands.phi.incoming[i].block_id);
                    emit_val(instr->operands.phi.incoming[i].value_id, out);
                }
                fprintf(out, "\n");
            }
            break;
        }
        default: break;
    }
}

void qbe_emit_instr(const ILModule* mod, const ILFunction* func, const ILInstruction* instr, uint32_t current_block_id, FILE* out) {
    if (!instr) return;

    const char* ty_str = qbe_map_type(instr->result_type);

    switch (instr->opcode) {
        case IL_OP_ADD:
        case IL_OP_SUB:
        case IL_OP_MUL:
        case IL_OP_DIV:
        case IL_OP_REM:
        case IL_OP_AND:
        case IL_OP_OR:
        case IL_OP_XOR:
        case IL_OP_SHL:
        case IL_OP_SHR:
        case IL_OP_CMP_LT:
        case IL_OP_CMP_LE:
        case IL_OP_CMP_GT:
        case IL_OP_CMP_GE:
        case IL_OP_CMP_EQ:
        case IL_OP_CMP_NE:
        case IL_OP_WRAPPING_ADD:
        case IL_OP_WRAPPING_SUB:
        case IL_OP_WRAPPING_MUL:
        case IL_OP_SATURATING_ADD:
        case IL_OP_CHECKED_ADD:
        case IL_OP_CHECKED_SUB:
        case IL_OP_CHECKED_MUL:
            emit_arith_instr(mod, func, instr, ty_str, out);
            break;
        case IL_OP_RETURN:
        case IL_OP_BRANCH:
        case IL_OP_JUMP:
            emit_control_flow_instr((ILModule*)mod, func, instr, current_block_id, out);
            break;
        case IL_OP_ALLOC:
        case IL_OP_LOAD:
        case IL_OP_STORE:
            emit_mem_instr(mod, func, instr, ty_str, out);
            break;
        case IL_OP_IS_SOME:
        case IL_OP_UNWRAP:
            emit_sum_instr(mod, func, instr, current_block_id, ty_str, out);
            break;
        case IL_OP_BOUNDS_CHECK:
            emit_control_flow_instr((ILModule*)mod, func, instr, current_block_id, out);
            break;
        case IL_OP_SLICE_LEN:
        case IL_OP_SLICE_DATA:
        case IL_OP_SLICE_LOAD:
        case IL_OP_SLICE_STORE:
        case IL_OP_SLICE_CONSTRUCT:
        case IL_OP_ARRAY_CONSTRUCT:
        case IL_OP_ARRAY_LOAD:
        case IL_OP_ARRAY_STORE:
        case IL_OP_ELEM_ADDR:
            emit_slice_instr(mod, func, instr, out);
            break;
        case IL_OP_MOVE:
        case IL_OP_BITCAST:
        case IL_OP_REGION_CAST:
            emit_conversion_instr(func, instr, ty_str, out);
            break;
        case IL_OP_DROP:
        case IL_OP_GLOBAL_ADDR:
        case IL_OP_FUNC_ADDR:
        case IL_OP_FIELD_ADDR:
            emit_mem_instr(mod, func, instr, ty_str, out);
            break;
        case IL_OP_VARIANT_MATCH:
        case IL_OP_SUM_CONSTRUCT:
            emit_sum_instr(mod, func, instr, current_block_id, ty_str, out);
            break;
        case IL_OP_CALL:
        case IL_OP_CALL_PTR:
        case IL_OP_SYSCALL:
        case IL_OP_CONST:
        case IL_OP_STRING_CONST:
        case IL_OP_PHI:
            emit_other_instr(mod, func, instr, ty_str, out);
            break;
        case IL_OP_FD_OPEN:
        case IL_OP_FD_CLOSE:
        case IL_OP_FD_READ:
        case IL_OP_FD_WRITE:
            emit_fd_io_instr(mod, func, instr, out);
            break;
        case IL_OP_ASYNC_SETUP:
        case IL_OP_ASYNC_ENTER:
        case IL_OP_ASYNC_CLOSE:
            emit_async_instr(mod, func, instr, out);
            break;
        default:
            ICE("Unhandled opcode in QBE emitter: %d", instr->opcode);
            break;
    }
}

void qbe_emit_block(const ILModule* mod, const ILFunction* func, const ILBasicBlock* block, FILE* out) {
    fprintf(out, "@b%u\n", block->id);
    
    uint32_t i = 0;
    // QBE PHIs MUST come first. Standard QBE Phis (is_phi_large == false) are emitted first.
    for (uint32_t j = 0; j < block->instr_count; j++) {
        const ILInstruction* instr = block->instructions[j];
        if (instr->opcode != IL_OP_PHI) break;
        if (!is_phi_large(instr)) {
            qbe_emit_instr(mod, func, instr, block->id, out);
        }
    }
    
    // Then we do a second pass for large/aggregate Phis (which emit load/memcpy/call).
    for (uint32_t j = 0; j < block->instr_count; j++) {
        const ILInstruction* instr = block->instructions[j];
        if (instr->opcode != IL_OP_PHI) break;
        if (is_phi_large(instr)) {
            qbe_emit_instr(mod, func, instr, block->id, out);
        }
    }
    
    // Advance i past all Phis for the main instruction loop
    while (i < block->instr_count && block->instructions[i]->opcode == IL_OP_PHI) {
        i++;
    }
    
    if (func->block_count > 0 && func->blocks[0] == block) {
        // Hoist all local stack allocations to the entry block to prevent stack overflow in loops.
        for (uint32_t b = 0; b < func->block_count; b++) {
            const ILBasicBlock* blk = func->blocks[b];
            for (uint32_t j = 0; j < blk->instr_count; j++) {
                const ILInstruction* instr = blk->instructions[j];
                if (instr->opcode == IL_OP_ALLOC) {
                    if (instr->operands.alloc.allocator_id == 0 && instr->operands.alloc.region_id != REGION_HEAP) {
                        char res_buf[16];
                        qbe_map_ssa(instr->result_id, res_buf);
                        const ILType* alloc_ty = instr->result_type && (instr->result_type->kind == IL_TY_PTR || instr->result_type->kind == IL_TY_BOX) ? instr->result_type->as.ptr.pointee : NULL;
                        size_t size = il_type_size(mod, alloc_ty);
                        int align = 8;
                        const char* a_ty_str = qbe_map_type(alloc_ty);
                        if (a_ty_str && strcmp(a_ty_str, "w") == 0) align = 4;
                        fprintf(out, "\t%s =l alloc%d %zu\n", res_buf, align, size);
                    }
                } else if (instr->opcode == IL_OP_SUM_CONSTRUCT) {
                    char res_buf[16];
                    qbe_map_ssa(instr->result_id, res_buf);
                    const ILTypeDef* def = il_mod_get_type_def(mod, instr->operands.sum_construct.type_def_id);
                    size_t size = il_type_def_size(mod, def);
                    fprintf(out, "\t%s =l alloc8 %zu\n", res_buf, size);
                } else if (instr->opcode == IL_OP_SLICE_CONSTRUCT) {
                    char res_buf[16];
                    qbe_map_ssa(instr->result_id, res_buf);
                    fprintf(out, "\t%s =l alloc8 16\n", res_buf);
                } else if (instr->opcode == IL_OP_ARRAY_CONSTRUCT) {
                    char res_buf[16];
                    qbe_map_ssa(instr->result_id, res_buf);
                    size_t elem_size = 0;
                    size_t elem_align = 8;
                    if (instr->result_type && instr->result_type->kind == IL_TY_ARRAY) {
                        elem_size = il_type_size(mod, instr->result_type->as.array.element);
                        elem_align = il_type_align(mod, instr->result_type->as.array.element);
                    }
                    if (elem_align < 4) elem_align = 4;
                    if (elem_align > 8) elem_align = 8;
                    uint32_t total_size = (uint32_t)elem_size * instr->operands.array_construct.count;
                    fprintf(out, "\t%s =l alloc%zu %u\n", res_buf, elem_align, total_size == 0 ? (uint32_t)elem_size : total_size);
                } else if (is_phi_large(instr)) {
                    char slot_buf[32];
                    sprintf(slot_buf, "%%phi_slot_%u", instr->result_id);
                    const char* ty = qbe_map_type(instr->result_type);
                    size_t size = il_type_size(mod, instr->result_type);
                    int align = 8;
                    if (ty && strcmp(ty, "w") == 0) align = 4;
                    fprintf(out, "\t%s =l alloc%d %zu\n", slot_buf, align, size);
                    
                    // If it's an aggregate Phi, we also need to allocate the result SSA ID itself
                    if (instr->result_type && (instr->result_type->kind == IL_TY_STRUCT || instr->result_type->kind == IL_TY_SUM ||
                                             instr->result_type->kind == IL_TY_ARRAY || instr->result_type->kind == IL_TY_TUPLE ||
                                             instr->result_type->kind == IL_TY_SLICE)) {
                        char res_buf[16];
                        qbe_map_ssa(instr->result_id, res_buf);
                        fprintf(out, "\t%s =l alloc%d %zu\n", res_buf, align, size);
                    }
                } else if (instr->opcode == IL_OP_UNWRAP) {
                    const ILType* res_type = instr->result_type;
                    if (res_type && (res_type->kind == IL_TY_STRUCT || res_type->kind == IL_TY_SUM || res_type->kind == IL_TY_ARRAY || res_type->kind == IL_TY_TUPLE || res_type->kind == IL_TY_SLICE)) {
                        char res_buf[16];
                        qbe_map_ssa(instr->result_id, res_buf);
                        size_t size = il_type_size(mod, res_type);
                        size_t align = il_type_align(mod, res_type);
                        if (align < 4) align = 4;
                        if (align > 8) align = 8;
                        fprintf(out, "\t%s =l alloc%zu %zu\n", res_buf, align, size == 0 ? 8 : size);
                    }
                } else if (instr->opcode == IL_OP_LOAD || instr->opcode == IL_OP_ARRAY_LOAD || instr->opcode == IL_OP_SLICE_LOAD) {
                    const ILType* res_type = instr->result_type;
                    if (res_type && (res_type->kind == IL_TY_STRUCT || res_type->kind == IL_TY_SUM || res_type->kind == IL_TY_ARRAY || res_type->kind == IL_TY_TUPLE || res_type->kind == IL_TY_SLICE)) {
                        char res_buf[16];
                        qbe_map_ssa(instr->result_id, res_buf);
                        size_t size = il_type_size(mod, res_type);
                        size_t align = il_type_align(mod, res_type);
                        if (align < 4) align = 4;
                        if (align > 8) align = 8;
                        fprintf(out, "\t%s =l alloc%zu %zu\n", res_buf, align, size == 0 ? 8 : size);
                    }
                }
            }
        }
    }
    
    for (; i < block->instr_count; i++) {
        qbe_emit_instr(mod, func, block->instructions[i], block->id, out);
    }
}

void qbe_emit_func(const ILModule* mod, const ILFunction* func, FILE* out) {
    if (!func || func->is_extern) return;

    const char* ret_ty = func->is_sret ? "l" : qbe_map_func_abi_type(func->return_type);
    if (is_unit_main(func)) ret_ty = "w";

    fprintf(out, "export function %s%s", ret_ty ? ret_ty : "", ret_ty ? " " : "");
    qbe_emit_func_sym(func->name, func->is_extern, out);
    fprintf(out, "(");

    for (uint32_t i = 0; i < func->param_count; i++) {
        const ILType* pty = func->param_types[i];
        const char* param_ty = qbe_map_abi_type(pty);
        fprintf(out, "%s %%v%u%s", param_ty ? param_ty : "l", i + 1, (i < func->param_count - 1) ? ", " : "");
    }
    fprintf(out, ") {\n");
    for (uint32_t i = 0; i < func->block_count; i++) {
        qbe_emit_block(mod, func, func->blocks[i], out);
    }
    fprintf(out, "@panic\n");
    fprintf(out, "\tcall $abort()\n");
    if (func->is_sret) {
        fprintf(out, "\tret %%v1\n");
    } else if (ret_ty) {
        if (ret_ty[0] == 's' || ret_ty[0] == 'd') {
            fprintf(out, "\tret %s_0\n", ret_ty);
        } else {
            fprintf(out, "\tret 0\n");
        }
    } else {
        fprintf(out, "\tret\n");
    }
    fprintf(out, "}\n");
}

void qbe_emit_global(const ILModule* mod, const ILGlobal* global, FILE* out) {
    if (!global) return;
    fprintf(out, "data $g%u = {", global->id);
    for (uint32_t i = 0; i < global->data_len; i++) {
        fprintf(out, " b %u%s", global->init_data[i], (i == global->data_len - 1) ? "" : ",");
    }
    // Pad to type size if needed
    size_t ty_size = il_type_size(mod, global->type);
    if (global->data_len < ty_size) {
        fprintf(out, "%s z %zu", (global->data_len == 0 ? "" : ","), ty_size - global->data_len);
    }
    fprintf(out, " }\n");
}

static bool type_depends_on(const ILType* type, const char* name) {
    if (!type || !name) return false;

    // Check if this type matches name directly (when mangled)
    char abi_name[256];
    qbe_get_type_name_string(type, abi_name, sizeof(abi_name));
    if (strcmp(abi_name, name) == 0) return true;

    if (type->kind == IL_TY_STRUCT || type->kind == IL_TY_SUM) {
        if (type->as.struct_sum.name && strcmp(type->as.struct_sum.name, name) == 0) return true;
        for (uint32_t i = 0; i < type->as.struct_sum.type_arg_count; i++) {
            if (type_depends_on(type->as.struct_sum.type_args[i], name)) return true;
        }
    }
    if (type->kind == IL_TY_TUPLE) {
        for (uint32_t i = 0; i < type->as.tuple.count; i++) {
            if (type_depends_on(type->as.tuple.elements[i], name)) return true;
        }
    }
    if (type->kind == IL_TY_ARRAY) {
        return type_depends_on(type->as.array.element, name);
    }
    if (type->kind == IL_TY_SLICE) {
        return type_depends_on(type->as.slice.element, name);
    }
    if (type->kind == IL_TY_PTR) return false;
    if (type->kind == IL_TY_BOX) return false;
    return false;
}

static const ILType ** extra_types = NULL;
static uint32_t extra_types_count = 0;
static uint32_t extra_types_capacity = 0;

static void add_extra_type(const ILType* ty) {
    if (!ty) return;
    if (ty->kind != IL_TY_STRUCT && ty->kind != IL_TY_SUM && 
        ty->kind != IL_TY_TUPLE && ty->kind != IL_TY_ARRAY && 
        ty->kind != IL_TY_SLICE) {
        // Recurse into pointers/boxes even if they aren't 'extra types' themselves
        if (ty->kind == IL_TY_PTR) add_extra_type(ty->as.ptr.pointee);
        else if (ty->kind == IL_TY_BOX) add_extra_type(ty->as.box.pointee);
        return;
    }

    for (uint32_t i = 0; i < extra_types_count; i++) {
        if (il_type_eq(extra_types[i], ty)) return;
    }

    if (extra_types_count >= extra_types_capacity) {
        uint32_t new_capacity = extra_types_capacity == 0 ? 16 : extra_types_capacity * 2;
        const ILType ** new_extra_types = realloc(extra_types, new_capacity * sizeof(const ILType*));
        if (!new_extra_types) return;
        extra_types = new_extra_types;
        extra_types_capacity = new_capacity;
    }
    extra_types[extra_types_count++] = ty;
    
    if (ty->kind == IL_TY_ARRAY) {
        add_extra_type(ty->as.array.element);
    } else if (ty->kind == IL_TY_SLICE) {
        add_extra_type(ty->as.slice.element);
    } else if (ty->kind == IL_TY_TUPLE) {
        for (uint32_t i = 0; i < ty->as.tuple.count; i++) {
            add_extra_type(ty->as.tuple.elements[i]);
        }
    } else if (ty->kind == IL_TY_STRUCT || ty->kind == IL_TY_SUM) {
        if (current_mod) {
            const ILTypeDef* def = il_mod_get_type_def(current_mod, ty->as.struct_sum.type_def_id);
            if (def) {
                for (uint32_t i = 0; i < def->field_count; i++) {
                    add_extra_type(def->fields[i].type);
                }
            }
        }
        for (uint32_t i = 0; i < ty->as.struct_sum.type_arg_count; i++) {
            add_extra_type(ty->as.struct_sum.type_args[i]);
        }
    }
}

static void collect_extra_types(const ILModule* mod) {
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        const ILTypeDef* def = mod->type_defs[i];
        for (uint32_t j = 0; j < def->field_count; j++) {
            add_extra_type(def->fields[j].type);
        }
    }

    for (uint32_t i = 0; i < mod->global_count; i++) {
        add_extra_type(mod->globals[i]->type);
    }

    for (uint32_t i = 0; i < mod->function_count; i++) {
        const ILFunction* func = mod->functions[i];
        add_extra_type(func->return_type);
        for (uint32_t j = 0; j < func->param_count; j++) {
            add_extra_type(func->param_types[j]);
        }
        for (uint32_t j = 0; j < func->block_count; j++) {
            const ILBasicBlock* bb = func->blocks[j];
            for (uint32_t k = 0; k < bb->instr_count; k++) {
                const ILInstruction* instr = bb->instructions[k];
                add_extra_type(instr->result_type);
                switch (instr->opcode) {
                    case IL_OP_ALLOC: add_extra_type(instr->result_type && (instr->result_type->kind == IL_TY_PTR || instr->result_type->kind == IL_TY_BOX) ? instr->result_type->as.ptr.pointee : NULL); break;
                    case IL_OP_STORE: add_extra_type(get_val_type(func, instr->operands.store.value)); break;
                    case IL_OP_LOAD: add_extra_type(get_val_type(func, instr->operands.load.ptr)); break;
                    case IL_OP_CALL:
                        for (uint32_t m = 0; m < instr->operands.call.num_args; m++) {
                            add_extra_type(get_val_type(func, instr->operands.call.arg_ids[m]));
                        }
                        break;
                    default: break;
                }
            }
        }
    }
}

static void qbe_get_type_name_string(const ILType* type, char* buf, size_t max_len) {
    if (!type) { snprintf(buf, max_len, "Unknown"); return; }
    if (type->kind == IL_TY_STRUCT || type->kind == IL_TY_SUM) {
        snprintf(buf, max_len, "%s", type->as.struct_sum.name ? type->as.struct_sum.name : "AnonStruct");
    } else if (type->kind == IL_TY_SLICE) {
        char elem_buf[64];
        qbe_get_type_name_string(type->as.slice.element, elem_buf, sizeof(elem_buf));
        snprintf(buf, max_len, "Slice_%s", elem_buf);
    } else if (type->kind == IL_TY_ARRAY) {
        char elem_buf[64];
        qbe_get_type_name_string(type->as.array.element, elem_buf, sizeof(elem_buf));
        snprintf(buf, max_len, "Array_%zu_%s", (size_t)type->as.array.length, elem_buf);
    } else if (type->kind == IL_TY_TUPLE) {
        snprintf(buf, max_len, "Tuple_%u", type->as.tuple.count);
    } else if (type->kind == IL_TY_U8) snprintf(buf, max_len, "u8");
    else if (type->kind == IL_TY_I8) snprintf(buf, max_len, "i8");
    else if (type->kind == IL_TY_U16) snprintf(buf, max_len, "u16");
    else if (type->kind == IL_TY_I16) snprintf(buf, max_len, "i16");
    else if (type->kind == IL_TY_U32) snprintf(buf, max_len, "u32");
    else if (type->kind == IL_TY_I32) snprintf(buf, max_len, "i32");
    else if (type->kind == IL_TY_U64) snprintf(buf, max_len, "u64");
    else if (type->kind == IL_TY_I64) snprintf(buf, max_len, "i64");
    else if (type->kind == IL_TY_F32) snprintf(buf, max_len, "f32");
    else if (type->kind == IL_TY_F64) snprintf(buf, max_len, "f64");
    else if (type->kind == IL_TY_BOOL) snprintf(buf, max_len, "bool");
    else if (type->kind == IL_TY_PTR) snprintf(buf, max_len, "ptr");
    else snprintf(buf, max_len, "T_%d", type->kind);
}

static void qbe_emit_all_type_defs(const ILModule* mod, FILE* out) {
    uint32_t total_count = mod->type_def_count + extra_types_count;
    if (total_count == 0) return;

    ILTypeDef** all_defs = calloc(total_count, sizeof(ILTypeDef*));
    if (!all_defs) abort();

    uint32_t unique_count = 0;
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        bool duplicate = false;
        for (uint32_t j = 0; j < unique_count; j++) {
            const char* n1 = all_defs[j]->name;
            const char* n2 = mod->type_defs[i]->name;
            if (n1 && n2 && strcmp(n1, n2) == 0) {
                duplicate = true; break;
            }
        }
        if (!duplicate) all_defs[unique_count++] = (ILTypeDef*)mod->type_defs[i];
    }

    uint32_t num_extra_added = 0;
    ILTypeDef** extra_to_free = calloc(extra_types_count, sizeof(ILTypeDef*));

    // Convert extra_types to temporary ILTypeDefs
    for (uint32_t i = 0; i < extra_types_count; i++) {
        const ILType* ty = extra_types[i];
        char name[256];
        qbe_get_type_name_string(ty, name, sizeof(name));

        bool duplicate = false;
        for (uint32_t j = 0; j < unique_count; j++) {
            const char* n1 = all_defs[j]->name;
            if (n1 && strcmp(n1, name) == 0) {
                duplicate = true; break;
            }
        }
        if (duplicate) continue;

        ILTypeDef* def = calloc(1, sizeof(ILTypeDef));
        if (!def) abort();
        def->name = strdup(name);

        if (ty->kind == IL_TY_ARRAY) {
            il_type_def_add_field(def, "0", ty->as.array.element);
            // Special flag for array emission
            def->field_capacity = (uint32_t)ty->as.array.length; 
            def->drop_fn_name = (char*)1; // Sentinel marking the type as an array (checked below)
        } else if (ty->kind == IL_TY_TUPLE) {
            for (uint32_t j = 0; j < ty->as.tuple.count; j++) {
                char f[16]; snprintf(f, sizeof(f), "%u", j);
                il_type_def_add_field(def, f, ty->as.tuple.elements[j]);
            }
        } else if (ty->kind == IL_TY_SLICE) {
            il_type_def_add_field(def, "ptr", il_type_ptr(il_type_unit(), REGION_STATIC, false));
            il_type_def_add_field(def, "len", il_type_u64());
            def->is_sum = false;
        }
        all_defs[unique_count++] = def;
        extra_to_free[num_extra_added++] = def;
    }

    bool* emitted = calloc(unique_count, sizeof(bool));
    if (!emitted) abort();
    uint32_t emitted_count = 0;

    for (uint32_t pass = 0; pass < unique_count && emitted_count < unique_count; pass++) {
        for (uint32_t i = 0; i < unique_count; i++) {
            if (emitted[i]) continue;
            const ILTypeDef* def = all_defs[i];

            // Skip generic types (they have no fixed layout in QBE)
            bool fields_generic = false;
            for (uint32_t j = 0; j < def->field_count; j++) {
                if (il_type_is_generic_mod(mod, def->fields[j].type)) {
                    fields_generic = true;
                    break;
                }
            }
            if (def->is_generic || fields_generic) {
                emitted[i] = true;
                emitted_count++;
                continue;
            }

            bool ready = true;
            for (uint32_t j = 0; j < def->field_count; j++) {
                for (uint32_t k = 0; k < unique_count; k++) {
                    if (i == k) continue;
                    if (!emitted[k] && type_depends_on(def->fields[j].type, all_defs[k]->name)) {
                        ready = false;
                        break;
                    }
                }
                if (!ready) break;
            }

            if (ready) {
                if (def->drop_fn_name == (char*)1) { // The array sentinel set above
                    const char* elem_abi = qbe_map_abi_type(def->fields[0].type);
                    fprintf(out, "type :%s = { %s %u }\n", def->name, elem_abi ? elem_abi : "b", (uint32_t)def->field_capacity);
                } else if (def->is_sum) {
                    fprintf(out, "type :%s = { ", def->name);
                    size_t max_payload_size = 0;
                    size_t max_payload_align = 4; // tag is w (4)
                    for (uint32_t j = 0; j < def->field_count; j++) {
                        size_t s = il_type_size(mod, def->fields[j].type);
                        if (s > max_payload_size) max_payload_size = s;
                        size_t a = il_type_align(mod, def->fields[j].type);
                        if (a > max_payload_align) max_payload_align = a;
                    }
                    
                    // Tag
                    fprintf(out, "w");
                    size_t payload_offset = (4 + max_payload_align - 1) & ~(max_payload_align - 1);
                    if (payload_offset > 4) {
                        fprintf(out, ", b %zu", payload_offset - 4);
                    }
                    
                    if (max_payload_size > 0) {
                        size_t rem = max_payload_size;
                        if (max_payload_align >= 8) {
                            size_t l_count = rem / 8;
                            if (l_count > 0) {
                                fprintf(out, ", l %zu", l_count);
                                rem %= 8;
                            }
                        } else if (max_payload_align >= 4) {
                            size_t w_count = rem / 4;
                            if (w_count > 0) {
                                fprintf(out, ", w %zu", w_count);
                                rem %= 4;
                            }
                        }
                        if (rem > 0) {
                            fprintf(out, ", b %zu", rem);
                        }
                    }

                    size_t total_size = payload_offset + max_payload_size;
                    size_t total_align = max_payload_align;
                    size_t final_size = (total_size + total_align - 1) & ~(total_align - 1);
                    if (final_size > total_size) {
                        fprintf(out, ", b %zu", final_size - total_size);
                    }
                    fprintf(out, " }\n");
                } else {
                    fprintf(out, "type :%s = { ", def->name);
                    size_t current_offset = 0;
                    size_t max_align = 1;
                    for (uint32_t j = 0; j < def->field_count; j++) {
                        size_t s = il_type_size(mod, def->fields[j].type);
                        size_t a = il_type_align(mod, def->fields[j].type);
                        if (a > max_align) max_align = a;
                        
                        size_t padded_offset = (current_offset + a - 1) & ~(a - 1);
                        if (padded_offset > current_offset) {
                            fprintf(out, "%sb %zu", j == 0 ? "" : ", ", padded_offset - current_offset);
                            current_offset = padded_offset;
                        }

                        const char* ty = qbe_map_aggregate_field_type(def->fields[j].type);
                        size_t qbe_s = 0;
                        if (def->fields[j].type->kind == IL_TY_STRUCT || 
                            def->fields[j].type->kind == IL_TY_SUM ||
                            def->fields[j].type->kind == IL_TY_TUPLE ||
                            def->fields[j].type->kind == IL_TY_ARRAY ||
                            def->fields[j].type->kind == IL_TY_SLICE) {
                            // Nested aggregate
                            char nested_name[256];
                            qbe_get_type_name_string(def->fields[j].type, nested_name, sizeof(nested_name));
                            fprintf(out, "%s:%s", (j == 0 && current_offset == 0) ? "" : ", ", nested_name);
                            qbe_s = s;
                        } else if (ty) {
                            fprintf(out, "%s%s", (j == 0 && current_offset == 0) ? "" : ", ", ty);
                            if (strcmp(ty, "b") == 0) qbe_s = 1;
                            else if (strcmp(ty, "h") == 0) qbe_s = 2;
                            else if (strcmp(ty, "w") == 0) qbe_s = 4;
                            else if (strcmp(ty, "s") == 0) qbe_s = 4;
                            else if (strcmp(ty, "d") == 0) qbe_s = 8;
                            else qbe_s = 8;
                        }
                        current_offset += qbe_s;
                        if (qbe_s < s) {
                            fprintf(out, ", b %zu", s - qbe_s);
                            current_offset += (s - qbe_s);
                        }
                    }
                    // Tail padding
                    size_t aligned_size = (current_offset + max_align - 1) & ~(max_align - 1);
                    if (aligned_size > current_offset) {
                        fprintf(out, ", b %zu", aligned_size - current_offset);
                    }
                    if (def->field_count == 0) fprintf(out, "b 0");
                    fprintf(out, " }\n");
                }
                emitted[i] = true;
                emitted_count++;
            }
        }
    }

    // Force emission of any remaining types (e.g. recursive)
    for (uint32_t i = 0; i < unique_count; i++) {
        if (!emitted[i]) {
            const ILTypeDef* def = all_defs[i];
            if (def->is_sum) {
                fprintf(out, "type :%s = { w, b 0 }\n", def->name); 
            } else {
                fprintf(out, "type :%s = { b 0 }\n", def->name);
            }
        }
    }

    // Free temporary defs
    for (uint32_t i = 0; i < num_extra_added; i++) {
        extra_to_free[i]->drop_fn_name = NULL; // Clear the sentinel before freeing
        il_type_def_free(extra_to_free[i]);
    }
    free(extra_to_free);
    free(all_defs);
    free(emitted);
}


static void qbe_emit_float_constants(const ILModule* mod, FILE* out) {
    uint64_t seen_d[256];
    uint32_t seen_s[256];
    uint32_t num_d = 0, num_s = 0;

    for (uint32_t f = 0; f < mod->function_count; f++) {
        const ILFunction* func = mod->functions[f];
        if (!func || func->is_extern) continue;
        for (uint32_t b = 0; b < func->block_count; b++) {
            const ILBasicBlock* block = func->blocks[b];
            for (uint32_t i = 0; i < block->instr_count; i++) {
                const ILInstruction* instr = block->instructions[i];
                if (instr->opcode == IL_OP_CONST) {
                    if (instr->result_type && instr->result_type->kind == IL_TY_F32) {
                        union { float f; uint32_t u; } uf;
                        uf.f = (float)instr->operands.const_val.u.fval;
                        bool found = false;
                        for (uint32_t j = 0; j < num_s; j++) if (seen_s[j] == uf.u) { found = true; break; }
                        if (!found && num_s < 256) {
                            seen_s[num_s++] = uf.u;
                            fprintf(out, "data $s_%u = { w %u }\n", uf.u, uf.u);
                        }
                    } else if (instr->result_type && instr->result_type->kind == IL_TY_F64) {
                        union { double d; uint64_t u; } ud;
                        ud.d = instr->operands.const_val.u.fval;
                        bool found = false;
                        for (uint32_t j = 0; j < num_d; j++) if (seen_d[j] == ud.u) { found = true; break; }
                        if (!found && num_d < 256) {
                            seen_d[num_d++] = ud.u;
                            fprintf(out, "data $d_%lu = { l %lu }\n", ud.u, ud.u);
                        }
                    }
                }
            }
        }
    }
}

static void qbe_emit_string_constants(const ILModule* mod, FILE* out) {
    if (!mod || !out) return;
    for (uint32_t f = 0; f < mod->function_count; f++) {
        const ILFunction* func = mod->functions[f];
        if (!func || func->is_extern) continue;
        for (uint32_t b = 0; b < func->block_count; b++) {
            const ILBasicBlock* block = func->blocks[b];
            for (uint32_t i = 0; i < block->instr_count; i++) {
                const ILInstruction* instr = block->instructions[i];
                if (instr->opcode == IL_OP_STRING_CONST && instr->operands.string_literal.val) {
                    fprintf(out, "data $str_%u = { ", instr->result_id);
                    for (uint32_t m = 0; m < instr->operands.string_literal.len; m++) {
                        fprintf(out, "b %d, ", (int)instr->operands.string_literal.val[m]);
                    }
                    fprintf(out, "b 0 }\n");
                }
            }
        }
    }
}

void qbe_emit_module(const ILModule* mod, FILE* out) {
    if (!mod || !out) return;
    current_mod = mod;
    
    collect_extra_types(mod);
    
    qbe_emit_all_type_defs(mod, out);
    qbe_emit_float_constants(mod, out);
    qbe_emit_string_constants(mod, out);

    for (uint32_t i = 0; i < mod->global_count; i++) {
        qbe_emit_global(mod, mod->globals[i], out);
    }
    for (uint32_t i = 0; i < mod->function_count; i++) {
        qbe_emit_func(mod, mod->functions[i], out);
    }
    
    // Cleanup extra_types
    free(extra_types);
    extra_types = NULL;
    extra_types_count = 0;
    extra_types_capacity = 0;
}
