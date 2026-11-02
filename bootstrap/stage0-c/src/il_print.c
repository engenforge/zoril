#include "il_print.h"
#include "string_table.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Append a formatted string to a (buf, rem) pair and return early on overflow. */
#define EMIT(buf, rem, ...) do { \
    int _n = snprintf((buf), (rem), __VA_ARGS__); \
    if (_n < 0 || (size_t)_n >= (rem)) return; \
    (buf) += _n; (rem) -= (size_t)_n; \
} while (0)

void il_print_type(const ILModule* mod, const ILType* type, char* buffer, size_t max_len) {
    if (type == NULL || buffer == NULL || max_len == 0) {
        if (buffer && max_len > 0) {
            buffer[0] = '\0';
        }
        return;
    }

    switch (type->kind) {
        case IL_TY_UNIT: snprintf(buffer, max_len, "unit"); break;
        case IL_TY_BOOL: snprintf(buffer, max_len, "bool"); break;
        case IL_TY_U8:   snprintf(buffer, max_len, "u8"); break;
        case IL_TY_U16:  snprintf(buffer, max_len, "u16"); break;
        case IL_TY_U32:  snprintf(buffer, max_len, "u32"); break;
        case IL_TY_U64:  snprintf(buffer, max_len, "u64"); break;
        case IL_TY_I8:   snprintf(buffer, max_len, "i8"); break;
        case IL_TY_I16:  snprintf(buffer, max_len, "i16"); break;
        case IL_TY_I32:  snprintf(buffer, max_len, "i32"); break;
        case IL_TY_I64:  snprintf(buffer, max_len, "i64"); break;
        case IL_TY_F32:   snprintf(buffer, max_len, "f32");   break;
        case IL_TY_F64:   snprintf(buffer, max_len, "f64");   break;
        case IL_TY_USIZE: snprintf(buffer, max_len, "usize"); break;
        case IL_TY_ISIZE: snprintf(buffer, max_len, "isize"); break;

        case IL_TY_PTR: {
            char inner[128];
            il_print_type(mod, type->as.ptr.pointee, inner, sizeof(inner));
            const char* reg = il_region_name(mod, type->as.ptr.region_id);
            const char* mut = type->as.ptr.is_mut ? "Mut" : "";
            if (reg) {
                snprintf(buffer, max_len, "Ptr%s<%s, '%s>", mut, inner, reg);
            } else {
                snprintf(buffer, max_len, "Ptr%s<%s, %u>", mut, inner, type->as.ptr.region_id);
            }
            break;
        }

        case IL_TY_BOX: {
            char inner[128];
            il_print_type(mod, type->as.box.pointee, inner, sizeof(inner));
            const char* mut = type->as.box.is_mut ? "Mut" : "";
            snprintf(buffer, max_len, "Box%s<%s>", mut, inner);
            break;
        }

        case IL_TY_SLICE: {
            char inner[128];
            il_print_type(mod, type->as.slice.element, inner, sizeof(inner));
            const char* mut = type->as.slice.is_mut ? "Mut" : "";
            const char* reg = il_region_name(mod, type->as.slice.region_id);
            if (reg) {
                snprintf(buffer, max_len, "Slice%s<%s, '%s>", mut, inner, reg);
            } else {
                snprintf(buffer, max_len, "Slice%s<%s, %u>", mut, inner, type->as.slice.region_id);
            }
            break;
        }

        case IL_TY_ARRAY: {
            char inner[128];
            il_print_type(mod, type->as.array.element, inner, sizeof(inner));
            snprintf(buffer, max_len, "[%s; %llu]", inner, (unsigned long long)type->as.array.length);
            break;
        }

        case IL_TY_SUM:
        case IL_TY_STRUCT:
            snprintf(buffer, max_len, "T%u", type->as.struct_sum.type_def_id);
            break;

        case IL_TY_FD:
            switch (type->as.fd.cap) {
                case IL_CAP_READ:  snprintf(buffer, max_len, "fd<r>");  break;
                case IL_CAP_WRITE: snprintf(buffer, max_len, "fd<w>");  break;
                case IL_CAP_RW:    snprintf(buffer, max_len, "fd<rw>"); break;
                default:           snprintf(buffer, max_len, "fd<?>"); break;
            }
            break;

        case IL_TY_ASYNC_CONTEXT:
            snprintf(buffer, max_len, "async_context");
            break;

        case IL_TY_FN: {
            EMIT(buffer, max_len, "fn(");
            for (uint32_t i = 0; i < type->as.function.param_count; i++) {
                char t_buf[128];
                il_print_type(mod, type->as.function.param_types[i], t_buf, sizeof(t_buf));
                EMIT(buffer, max_len, "%s", t_buf);
                if (i < type->as.function.param_count - 1 || type->as.function.is_variadic) EMIT(buffer, max_len, ", ");
            }
            if (type->as.function.is_variadic) EMIT(buffer, max_len, "...");
            char r_buf[128];
            il_print_type(mod, type->as.function.return_type, r_buf, sizeof(r_buf));
            EMIT(buffer, max_len, ") -> %s", r_buf);
            break;
        }

        case IL_TY_TUPLE: {
            EMIT(buffer, max_len, "(");
            for (uint32_t i = 0; i < type->as.tuple.count; i++) {
                char t_buf[128];
                il_print_type(mod, type->as.tuple.elements[i], t_buf, sizeof(t_buf));
                EMIT(buffer, max_len, "%s", t_buf);
                if (i < type->as.tuple.count - 1) EMIT(buffer, max_len, ", ");
            }
            if (type->as.tuple.count == 1) EMIT(buffer, max_len, ",");
            EMIT(buffer, max_len, ")");
            break;
        }

        case IL_TY_NEVER: snprintf(buffer, max_len, "never"); break;

        case IL_TY_GENERIC_INSTANCE: {
            char b_buf[128];
            il_print_type(mod, type->as.generic_instance.base, b_buf, sizeof(b_buf));
            EMIT(buffer, max_len, "%s<", b_buf);
            for (uint32_t i = 0; i < type->as.generic_instance.type_arg_count; i++) {
                char a_buf[128];
                il_print_type(mod, type->as.generic_instance.type_args[i], a_buf, sizeof(a_buf));
                EMIT(buffer, max_len, "%s", a_buf);
                if (i < type->as.generic_instance.type_arg_count - 1) EMIT(buffer, max_len, ", ");
            }
            EMIT(buffer, max_len, ">");
            break;
        }

        default:
            snprintf(buffer, max_len, "unknown");
            break;
    }
}

static const char* opcode_to_str(ILOpcode op) {
    switch (op) {
        case IL_OP_ADD: return "add";
        case IL_OP_SUB: return "sub";
        case IL_OP_MUL: return "mul";
        case IL_OP_DIV: return "div";
        case IL_OP_REM: return "rem";
        case IL_OP_AND: return "and";
        case IL_OP_OR: return "or";
        case IL_OP_XOR: return "xor";
        case IL_OP_SHL: return "shl";
        case IL_OP_SHR: return "shr";
        case IL_OP_CMP_LT: return "lt";
        case IL_OP_CMP_LE: return "le";
        case IL_OP_CMP_GT: return "gt";
        case IL_OP_CMP_GE: return "ge";
        case IL_OP_CMP_EQ: return "eq";
        case IL_OP_CMP_NE: return "ne";
        case IL_OP_WRAPPING_ADD: return "wrapping_add";
        case IL_OP_WRAPPING_SUB: return "wrapping_sub";
        case IL_OP_WRAPPING_MUL: return "wrapping_mul";
        case IL_OP_SATURATING_ADD: return "saturating_add";
        case IL_OP_CHECKED_ADD: return "checked_add";
        case IL_OP_CHECKED_SUB: return "checked_sub";
        case IL_OP_CHECKED_MUL: return "checked_mul";
        case IL_OP_ALLOC: return "alloc";
        case IL_OP_LOAD: return "load";
        case IL_OP_STORE: return "store";
        case IL_OP_DROP: return "drop";
        case IL_OP_BOUNDS_CHECK: return "bounds_check";
        case IL_OP_SLICE_LOAD: return "slice_load";
        case IL_OP_SLICE_STORE: return "slice_store";
        case IL_OP_SLICE_LEN: return "slice_len";
        case IL_OP_SLICE_DATA: return "slice_data";
        case IL_OP_SLICE_CONSTRUCT: return "slice_construct";
        case IL_OP_ARRAY_CONSTRUCT: return "array_construct";
        case IL_OP_ARRAY_LOAD: return "array_load";
        case IL_OP_ARRAY_STORE: return "array_store";
        case IL_OP_MOVE: return "move";
        case IL_OP_BITCAST: return "bitcast";
        case IL_OP_REGION_CAST: return "region_cast";
        case IL_OP_CALL: return "call";
        case IL_OP_CALL_PTR: return "call_ptr";
        case IL_OP_RETURN: return "ret";
        case IL_OP_BRANCH: return "branch";
        case IL_OP_JUMP: return "jump";
        case IL_OP_GLOBAL_ADDR: return "global_addr";
        case IL_OP_FUNC_ADDR: return "func_addr";
        case IL_OP_FIELD_ADDR: return "field_addr";
        case IL_OP_ELEM_ADDR: return "elem_addr";
        case IL_OP_VARIANT_MATCH: return "variant_match";
        case IL_OP_SUM_CONSTRUCT: return "sum_construct";
        case IL_OP_IS_SOME: return "is_some";
        case IL_OP_UNWRAP: return "unwrap";
        case IL_OP_SYSCALL: return "syscall";
        case IL_OP_CONST: return "const";
        case IL_OP_STRING_CONST: return "string_const";
        case IL_OP_PHI: return "phi";
        case IL_OP_FD_OPEN:       return "fd_open";
        case IL_OP_FD_CLOSE:      return "fd_close";
        case IL_OP_FD_READ:   return "fd_read";
        case IL_OP_FD_WRITE:  return "fd_write";
        case IL_OP_ASYNC_SETUP: return "async_setup";
        case IL_OP_ASYNC_ENTER: return "async_enter";
        case IL_OP_ASYNC_CLOSE: return "async_close";
        case IL_OP_INVALID: return "invalid";
        default: return "unknown";
    }
}

static void print_binary_instr(const ILInstruction* instr, const char* type_buf, char* buffer, size_t max_len) {
    snprintf(buffer, max_len, "v%u: %s = %s v%u, v%u",
             instr->result_id, type_buf, opcode_to_str(instr->opcode),
             instr->operands.binary.left, instr->operands.binary.right);
}

static void print_mem_instr(const ILModule* mod, const ILInstruction* instr, const char* type_buf, char* buffer, size_t max_len) {
    switch (instr->opcode) {
        case IL_OP_ALLOC: {
            char alloc_type_buf[128];
            const ILType* alloc_ty = (instr->result_type && (instr->result_type->kind == IL_TY_PTR || instr->result_type->kind == IL_TY_BOX)) ? instr->result_type->as.ptr.pointee : NULL;
            il_print_type(mod, alloc_ty, alloc_type_buf, sizeof(alloc_type_buf));
            const char* reg = il_region_name(mod, instr->operands.alloc.region_id);
            if (reg) {
                snprintf(buffer, max_len, "v%u: %s = alloc '%s, %s", 
                         instr->result_id, type_buf, reg, alloc_type_buf);
            } else {
                snprintf(buffer, max_len, "v%u: %s = alloc %u, %s", 
                         instr->result_id, type_buf, instr->operands.alloc.region_id, alloc_type_buf);
            }
            break;
        }
        case IL_OP_LOAD:
            snprintf(buffer, max_len, "v%u: %s = load v%u",
                     instr->result_id, type_buf, instr->operands.load.ptr);
            break;
        case IL_OP_STORE:
            snprintf(buffer, max_len, "store v%u, v%u",
                     instr->operands.store.ptr, instr->operands.store.value);
            break;
        case IL_OP_DROP:
            snprintf(buffer, max_len, "drop v%u", instr->operands.drop.value);
            break;
        case IL_OP_GLOBAL_ADDR:
            snprintf(buffer, max_len, "v%u: %s = global_addr g%u",
                     instr->result_id, type_buf, instr->operands.global_addr.global_id);
            break;
        case IL_OP_FUNC_ADDR:
            snprintf(buffer, max_len, "v%u: %s = func_addr f%u",
                     instr->result_id, type_buf, instr->operands.func_addr.func_id);
            break;
        case IL_OP_FIELD_ADDR:
            snprintf(buffer, max_len, "v%u: %s = field_addr v%u, %u",
                     instr->result_id, type_buf, instr->operands.field_addr.struct_ptr, instr->operands.field_addr.field_index);
            break;
        case IL_OP_ELEM_ADDR:
            snprintf(buffer, max_len, "v%u: %s = elem_addr v%u, v%u",
                     instr->result_id, type_buf, instr->operands.elem_addr.base, instr->operands.elem_addr.index);
            break;
        default: break;
    }
}

static void print_control_flow_instr(const ILInstruction* instr, char* buffer, size_t max_len) {
    switch (instr->opcode) {
        case IL_OP_RETURN:
            snprintf(buffer, max_len, "ret v%u", instr->operands.ret.value);
            break;
        case IL_OP_BRANCH:
            snprintf(buffer, max_len, "branch v%u, b%u, b%u",
                     instr->operands.branch.condition,
                     instr->operands.branch.then_block_id,
                     instr->operands.branch.else_block_id);
            break;
        case IL_OP_JUMP:
            snprintf(buffer, max_len, "jump b%u", instr->operands.jump.target_block_id);
            break;
        case IL_OP_BOUNDS_CHECK:
            snprintf(buffer, max_len, "bounds_check v%u, v%u",
                     instr->operands.bounds_check.index, instr->operands.bounds_check.length);
            break;
        default: break;
    }
}

static void print_sum_instr(const ILInstruction* instr, const char* type_buf, char* buffer, size_t max_len) {
    switch (instr->opcode) {
        case IL_OP_IS_SOME:
            snprintf(buffer, max_len, "v%u: %s = is_some v%u", instr->result_id, type_buf, instr->operands.move.source);
            break;
        case IL_OP_UNWRAP:
            snprintf(buffer, max_len, "v%u: %s = unwrap v%u", instr->result_id, type_buf, instr->operands.move.source);
            break;
        case IL_OP_VARIANT_MATCH:
            if (instr->operands.variant_match.target_block_id == IL_NO_BLOCK) {
                snprintf(buffer, max_len, "v%u: %s = variant_match v%u, %u", instr->result_id, type_buf,
                         instr->operands.variant_match.sum_ptr, instr->operands.variant_match.variant_index);
                break;
            }
            snprintf(buffer, max_len, "variant_match v%u, %u, @b%u, @b%u",
                     instr->operands.variant_match.sum_ptr,
                     instr->operands.variant_match.variant_index,
                     instr->operands.variant_match.target_block_id,
                     instr->operands.variant_match.next_block_id);
            break;
        case IL_OP_SUM_CONSTRUCT:
            snprintf(buffer, max_len, "v%u = sum_construct %u, %u, v%u",
                     instr->result_id,
                     instr->operands.sum_construct.type_def_id,
                     instr->operands.sum_construct.variant_index,
                     instr->operands.sum_construct.payload_id);
            break;
        default: break;
    }
}

static void print_slice_instr(const ILInstruction* instr, const char* type_buf, char* buffer, size_t max_len) {
    switch (instr->opcode) {
        case IL_OP_SLICE_LOAD:
            snprintf(buffer, max_len, "v%u: %s = slice_load v%u, v%u",
                     instr->result_id, type_buf, instr->operands.slice_load.slice_ptr, instr->operands.slice_load.index);
            break;
        case IL_OP_SLICE_STORE:
            snprintf(buffer, max_len, "slice_store v%u, v%u, v%u",
                     instr->operands.slice_store.slice_ptr, instr->operands.slice_store.index, instr->operands.slice_store.value);
            break;
        case IL_OP_SLICE_LEN:
            snprintf(buffer, max_len, "v%u: %s = slice_len v%u",
                     instr->result_id, type_buf, instr->operands.slice_op.slice_ptr);
            break;
        case IL_OP_SLICE_DATA:
            snprintf(buffer, max_len, "v%u: %s = slice_data v%u",
                     instr->result_id, type_buf, instr->operands.slice_op.slice_ptr);
            break;
        case IL_OP_SLICE_CONSTRUCT:
            snprintf(buffer, max_len, "v%u: %s = slice_construct v%u, v%u",
                     instr->result_id, type_buf, instr->operands.slice_construct.ptr, instr->operands.slice_construct.len);
            break;
        default: break;
    }
}

static void print_array_instr(const ILInstruction* instr, const char* type_buf, char* buffer, size_t max_len) {
    if (instr->opcode == IL_OP_ARRAY_CONSTRUCT) {
        int w = snprintf(buffer, max_len, "v%u: %s = array_construct [", instr->result_id, type_buf);
        size_t written = (w >= 0) ? (size_t)w : 0;
        for (uint32_t i = 0; i < instr->operands.array_construct.count; i++) {
            if (written < max_len) {
                int w_arg = snprintf(buffer + written, max_len - written, "v%u%s", 
                                     instr->operands.array_construct.element_ids[i],
                                     (i == instr->operands.array_construct.count - 1) ? "" : ", ");
                if (w_arg > 0) written += (size_t)w_arg;
            }
        }
        if (written < max_len) {
            snprintf(buffer + written, max_len - written, "]");
        }
    } else if (instr->opcode == IL_OP_ARRAY_LOAD) {
        snprintf(buffer, max_len, "v%u: %s = array_load v%u, v%u",
                 instr->result_id, type_buf, instr->operands.array_load.array_ptr, instr->operands.array_load.index);
    } else if (instr->opcode == IL_OP_ARRAY_STORE) {
        snprintf(buffer, max_len, "array_store v%u, v%u, v%u",
                 instr->operands.array_store.array_ptr, instr->operands.array_store.index, instr->operands.array_store.value);
    }
}

static void print_conversion_instr(const ILModule* mod, const ILInstruction* instr, const char* type_buf, char* buffer, size_t max_len) {
    switch (instr->opcode) {
        case IL_OP_MOVE:
            snprintf(buffer, max_len, "v%u: %s = move v%u",
                     instr->result_id, type_buf, instr->operands.move.source);
            break;
        case IL_OP_BITCAST:
            snprintf(buffer, max_len, "v%u: %s = bitcast v%u",
                     instr->result_id, type_buf, instr->operands.bitcast.source);
            break;
        case IL_OP_REGION_CAST: {
            const char* reg = il_region_name(mod, instr->operands.region_cast.target_region_id);
            if (reg) {
                snprintf(buffer, max_len, "v%u: %s = region_cast '%s, v%u",
                         instr->result_id, type_buf, reg, instr->operands.region_cast.source);
            } else {
                snprintf(buffer, max_len, "v%u: %s = region_cast %u, v%u",
                         instr->result_id, type_buf, instr->operands.region_cast.target_region_id, instr->operands.region_cast.source);
            }
            break;
        }
        default: break;
    }
}

static void print_io_instr(const ILInstruction* instr, const char* type_buf, char* buffer, size_t max_len) {
    switch (instr->opcode) {
        case IL_OP_FD_OPEN:
            snprintf(buffer, max_len, "v%u: %s = fd_open v%u, v%u, v%u",
                     instr->result_id, type_buf,
                     instr->operands.fd_open.path,
                     instr->operands.fd_open.flags,
                     instr->operands.fd_open.mode);
            break;
        case IL_OP_FD_CLOSE:
            snprintf(buffer, max_len, "fd_close v%u", instr->operands.fd_close.fd);
            break;
        case IL_OP_FD_READ:
            snprintf(buffer, max_len, "v%u: %s = fd_read v%u, v%u, v%u",
                     instr->result_id, type_buf,
                     instr->operands.fd_io.fd,
                     instr->operands.fd_io.buf,
                     instr->operands.fd_io.count);
            break;
        case IL_OP_FD_WRITE:
            snprintf(buffer, max_len, "v%u: %s = fd_write v%u, v%u, v%u",
                     instr->result_id, type_buf,
                     instr->operands.fd_io.fd,
                     instr->operands.fd_io.buf,
                     instr->operands.fd_io.count);
            break;
        case IL_OP_ASYNC_SETUP:
            snprintf(buffer, max_len, "v%u: %s = async_setup v%u",
                     instr->result_id, type_buf,
                     instr->operands.async_setup.entries);
            break;
        case IL_OP_ASYNC_ENTER:
            snprintf(buffer, max_len, "v%u: %s = async_enter v%u, v%u, v%u",
                     instr->result_id, type_buf,
                     instr->operands.async_enter.ctx,
                     instr->operands.async_enter.to_submit,
                     instr->operands.async_enter.min_complete);
            break;
        case IL_OP_ASYNC_CLOSE:
            snprintf(buffer, max_len, "async_close v%u",
                     instr->operands.async_close.ctx);
            break;
        default: break;
    }
}

static void print_other_instr(const ILInstruction* instr, const char* type_buf, char* buffer, size_t max_len) {
    switch (instr->opcode) {
        case IL_OP_CALL:
            snprintf(buffer, max_len, "v%u: %s = call f%u",
                     instr->result_id, type_buf, instr->operands.call.func_id); 
            if (instr->operands.call.num_args > 0) {
                strncat(buffer, "(", max_len - strlen(buffer) - 1);
                for (uint32_t i = 0; i < instr->operands.call.num_args; i++) {
                    size_t used = strlen(buffer);
                    snprintf(buffer + used, max_len - used, "v%u%s",
                             instr->operands.call.arg_ids[i],
                             (i == instr->operands.call.num_args - 1) ? "" : ", ");
                }
                strncat(buffer, ")", max_len - strlen(buffer) - 1);
            }
            break;
        case IL_OP_CALL_PTR:
            snprintf(buffer, max_len, "v%u: %s = call_ptr v%u",
                     instr->result_id, type_buf, instr->operands.call_ptr.func_ptr_id); 
            if (instr->operands.call_ptr.num_args > 0) {
                strncat(buffer, "(", max_len - strlen(buffer) - 1);
                for (uint32_t i = 0; i < instr->operands.call_ptr.num_args; i++) {
                    size_t used = strlen(buffer);
                    snprintf(buffer + used, max_len - used, "v%u%s",
                             instr->operands.call_ptr.arg_ids[i],
                             (i == instr->operands.call_ptr.num_args - 1) ? "" : ", ");
                }
                strncat(buffer, ")", max_len - strlen(buffer) - 1);
            }
            break;
        case IL_OP_PHI: {
            int len = snprintf(buffer, max_len, "v%u = phi ", instr->result_id);
            for (uint32_t i = 0; i < instr->operands.phi.num_incoming; i++) {
                if (len >= (int)max_len) break;
                len += snprintf(buffer + len, max_len - (size_t)len, "[@b%u, v%u]%s",
                                instr->operands.phi.incoming[i].block_id,
                                instr->operands.phi.incoming[i].value_id,
                                (i == instr->operands.phi.num_incoming - 1) ? "" : ", ");
            }
            break;
        }
        case IL_OP_SYSCALL: {
            int w = snprintf(buffer, max_len, "v%u: %s = syscall %u",
                                   instr->result_id, type_buf, instr->operands.syscall_op.syscall_num);
            size_t written = (w >= 0) ? (size_t)w : 0;
            for (uint32_t i = 0; i < instr->operands.syscall_op.num_args; i++) {
                if (written < max_len) {
                    int w_arg = snprintf(buffer + written, max_len - written, ", v%u",
                                        instr->operands.syscall_op.arg_ids[i]);
                    if (w_arg > 0) written += (size_t)w_arg;
                }
            }
            break;
        }
        case IL_OP_CONST:
            if (instr->result_type && (instr->result_type->kind == IL_TY_F32 || instr->result_type->kind == IL_TY_F64)) {
                snprintf(buffer, max_len, "v%u: %s = const %f", instr->result_id, type_buf, instr->operands.const_val.u.fval);
            } else {
                snprintf(buffer, max_len, "v%u: %s = const %lu", instr->result_id, type_buf, instr->operands.const_val.u.val);
            }
            break;
        case IL_OP_STRING_CONST: {
            int w = snprintf(buffer, max_len, "v%u: %s = string_const \"", instr->result_id, type_buf);
            size_t written = (w >= 0) ? (size_t)w : 0;
            for (uint32_t i = 0; i < instr->operands.string_literal.len; i++) {
                char c = instr->operands.string_literal.val[i];
                if (written + 4 >= max_len) break; // Buffer safety
                if (c == '\n') { buffer[written++] = '\\'; buffer[written++] = 'n'; }
                else if (c == '\r') { buffer[written++] = '\\'; buffer[written++] = 'r'; }
                else if (c == '\t') { buffer[written++] = '\\'; buffer[written++] = 't'; }
                else if (c == '"') { buffer[written++] = '\\'; buffer[written++] = '"'; }
                else if (c == '\\') { buffer[written++] = '\\'; buffer[written++] = '\\'; }
                else if (c < 32 || c > 126) {
                    int r = snprintf(buffer + written, max_len - written, "\\x%02x", (unsigned char)c);
                    if (r > 0) written += (size_t)r;
                } else {
                    buffer[written++] = c;
                }
            }
            if (written < max_len - 1) {
                buffer[written++] = '"';
                buffer[written] = '\0';
            }
            break;
        }
        default: break;
    }
}

void il_print_instr(const ILModule* mod, const ILInstruction* instr, char* buffer, size_t max_len) {
    if (instr == NULL || buffer == NULL || max_len == 0) return;

    char type_buf[128] = "";
    if (instr->result_type) {
        il_print_type(mod, instr->result_type, type_buf, sizeof(type_buf));
    }

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
            print_binary_instr(instr, type_buf, buffer, max_len);
            break;
        case IL_OP_ALLOC:
        case IL_OP_LOAD:
        case IL_OP_STORE:
        case IL_OP_DROP:
        case IL_OP_GLOBAL_ADDR:
        case IL_OP_FUNC_ADDR:
        case IL_OP_FIELD_ADDR:
        case IL_OP_ELEM_ADDR:
            print_mem_instr(mod, instr, type_buf, buffer, max_len);
            break;
        case IL_OP_RETURN:
        case IL_OP_BRANCH:
        case IL_OP_JUMP:
        case IL_OP_BOUNDS_CHECK:
            print_control_flow_instr(instr, buffer, max_len);
            break;
        case IL_OP_IS_SOME:
        case IL_OP_UNWRAP:
        case IL_OP_VARIANT_MATCH:
        case IL_OP_SUM_CONSTRUCT:
            print_sum_instr(instr, type_buf, buffer, max_len);
            break;
        case IL_OP_SLICE_LOAD:
        case IL_OP_SLICE_STORE:
        case IL_OP_SLICE_LEN:
        case IL_OP_SLICE_DATA:
        case IL_OP_SLICE_CONSTRUCT:
            print_slice_instr(instr, type_buf, buffer, max_len);
            break;
        case IL_OP_ARRAY_CONSTRUCT:
        case IL_OP_ARRAY_LOAD:
        case IL_OP_ARRAY_STORE:
            print_array_instr(instr, type_buf, buffer, max_len);
            break;
        case IL_OP_MOVE:
        case IL_OP_BITCAST:
        case IL_OP_REGION_CAST:
            print_conversion_instr(mod, instr, type_buf, buffer, max_len);
            break;
        case IL_OP_FD_OPEN:
        case IL_OP_FD_CLOSE:
        case IL_OP_FD_READ:
        case IL_OP_FD_WRITE:
        case IL_OP_ASYNC_SETUP:
        case IL_OP_ASYNC_ENTER:
        case IL_OP_ASYNC_CLOSE:
            print_io_instr(instr, type_buf, buffer, max_len);
            break;
        case IL_OP_CALL:
        case IL_OP_CALL_PTR:
        case IL_OP_PHI:
        case IL_OP_SYSCALL:
        case IL_OP_CONST:
            print_other_instr(instr, type_buf, buffer, max_len);
            break;
        default:
            snprintf(buffer, max_len, "v%u: %s = %s", instr->result_id, type_buf, opcode_to_str(instr->opcode));
            break;
    }
}

void il_print_func(const ILModule* mod, const ILFunction* func, char* buffer, size_t max_len) {
    if (func == NULL || buffer == NULL || max_len == 0) return;

    char ret_buf[128];
    il_print_type(mod, func->return_type, ret_buf, sizeof(ret_buf));
    EMIT(buffer, max_len, "f%u:%s %s %s(", func->id, func->is_must_use ? " must_use" : "", ret_buf, func->name ? func->name : "");

    for (uint32_t i = 0; i < func->param_count; i++) {
        char p_buf[128];
        il_print_type(mod, func->param_types[i], p_buf, sizeof(p_buf));
        EMIT(buffer, max_len, "%s%s", p_buf, (i == func->param_count - 1 && !func->is_variadic) ? "" : ", ");
    }
    if (func->is_variadic) EMIT(buffer, max_len, "...");

    EMIT(buffer, max_len, ") {\n");

    for (uint32_t i = 0; i < func->block_count; i++) {
        const ILBasicBlock* b = func->blocks[i];
        EMIT(buffer, max_len, "  @b%u:\n", b->id);

        for (uint32_t j = 0; j < b->instr_count; j++) {
            char i_buf[256];
            il_print_instr(mod, b->instructions[j], i_buf, sizeof(i_buf));
            EMIT(buffer, max_len, "    %s\n", i_buf);
        }
    }

    EMIT(buffer, max_len, "}\n");
}

void il_print_type_def(const ILModule* mod, const ILTypeDef* def, char* buffer, size_t max_len) {
    if (!def || !buffer || max_len == 0) return;

    EMIT(buffer, max_len, "type T%u: %s {\n", def->id, def->is_sum ? "sum" : "struct");

    for (uint32_t i = 0; i < def->field_count; i++) {
        char t_buf[128];
        il_print_type(mod, def->fields[i].type, t_buf, sizeof(t_buf));
        EMIT(buffer, max_len, "  %s: %s%s\n", def->fields[i].name, t_buf, (i == def->field_count - 1) ? "" : ",");
    }

    snprintf(buffer, max_len, "}\n\n");
}

void il_print_module(const ILModule* mod, char* buffer, size_t max_len) {
    if (mod == NULL || buffer == NULL || max_len == 0) return;

    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        il_print_type_def(mod, mod->type_defs[i], buffer, max_len);
        size_t used = strlen(buffer);
        buffer += used; max_len -= used;
    }

    for (uint32_t i = 0; i < mod->global_count; i++) {
        ILGlobal* g = mod->globals[i];
        char t_buf[128];
        il_print_type(mod, g->type, t_buf, sizeof(t_buf));
        EMIT(buffer, max_len, "global g%u: %s %s = {", g->id, t_buf, g->name ? g->name : "");

        for (uint32_t j = 0; j < g->data_len; j++) {
            EMIT(buffer, max_len, "0x%02X%s", g->init_data[j], (j == g->data_len - 1) ? "" : ", ");
        }

        EMIT(buffer, max_len, "}\n");
    }

    for (uint32_t i = 0; i < mod->function_count; i++) {
        il_print_func(mod, mod->functions[i], buffer, max_len);
        size_t used = strlen(buffer);
        buffer += used; max_len -= used;
    }
}

void il_func_print(const ILModule* mod, const ILFunction* func, FILE* out) {
    char* buf = malloc(65536);
    if (buf) {
        il_print_func(mod, func, buf, 65536);
        fprintf(out, "%s", buf);
        free(buf);
    }
}

void il_mod_print(const ILModule* mod, FILE* out) {
    for (uint32_t i = 0; i < mod->function_count; i++) {
        il_func_print(mod, mod->functions[i], out);
    }
}
