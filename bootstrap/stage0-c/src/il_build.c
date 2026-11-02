#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>
#include "il_type.h"
#include "il_instr.h"
#include "diagnostics.h"

extern bool il_type_eq(const ILType* a, const ILType* b);
extern bool il_type_is_assignable(const ILType* source, const ILType* target);

const ILType* il_build_unit_type(void) {
    return il_type_unit();
}

// Internal helper for validating binary arithmetic operands
ILValue il_value_copy_type(ILValue val) {
    return (ILValue){ .id = val.id, .type = val.type };
}

static bool validate_arithmetic_operands(ILValue left, ILValue right) {
    if (!left.type || !right.type) return false;
    if (!il_type_eq(left.type, right.type)) return false;

    if (is_integral_type(left.type) || is_float_type(left.type) ||
        left.type->kind == IL_TY_BOOL || left.type->kind == IL_TY_SLICE ||
        left.type->kind == IL_TY_PTR || left.type->kind == IL_TY_BOX ||
        left.type->kind == IL_TY_SUM) {
        return true;
    }
    return false;
}
// build_binary_arith is the single implementation for all binary arithmetic and
// bitwise instruction builders.  When result_type is NULL the result type is
// copied from the left operand (the common case); callers that produce a
// different result type (e.g. checked_add -> Option) pass it explicitly.
static ILInstruction* build_binary_arith(ILOpcode op, ILValue left, ILValue right,
                                         const ILType* result_type) {
    bool is_bitwise = (op == IL_OP_AND || op == IL_OP_OR || op == IL_OP_XOR);
    bool operands_ok = validate_arithmetic_operands(left, right);
    
    if (is_bitwise && operands_ok && is_float_type(left.type)) {
        operands_ok = false;
    }

    if (!operands_ok) {
        // Special case: allow bitwise ops on bools
        if (is_bitwise && left.type && right.type && 
            left.type->kind == IL_TY_BOOL && right.type->kind == IL_TY_BOOL) {
            operands_ok = true;
        }
    }

    if (!operands_ok) return NULL;

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->opcode = (uint8_t)op;
    instr->result_type = result_type ? result_type : left.type;
    instr->result_id = 0;
    instr->operands.binary.left  = left.id;
    instr->operands.binary.right = right.id;

    return instr;
}

ILInstruction* il_build_add(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_ADD, left, right, NULL);
}

ILInstruction* il_build_sub(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_SUB, left, right, NULL);
}

ILInstruction* il_build_mul(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_MUL, left, right, NULL);
}

ILInstruction* il_build_div(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_DIV, left, right, NULL);
}

ILInstruction* il_build_rem(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_REM, left, right, NULL);
}

ILInstruction* il_build_and(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_AND, left, right, NULL);
}

ILInstruction* il_build_or(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_OR, left, right, NULL);
}

ILInstruction* il_build_xor(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_XOR, left, right, NULL);
}

ILInstruction* il_build_shl(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_SHL, left, right, NULL);
}

ILInstruction* il_build_shr(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_SHR, left, right, NULL);
}

ILInstruction* il_build_wrapping_add(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_WRAPPING_ADD, left, right, NULL);
}

ILInstruction* il_build_wrapping_sub(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_WRAPPING_SUB, left, right, NULL);
}

ILInstruction* il_build_wrapping_mul(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_WRAPPING_MUL, left, right, NULL);
}

ILInstruction* il_build_saturating_add(ILValue left, ILValue right) {
    return build_binary_arith(IL_OP_SATURATING_ADD, left, right, NULL);
}

ILInstruction* il_build_checked_add(ILValue left, ILValue right, const ILType* option_type) {
    if (option_type != NULL && option_type->kind != IL_TY_SUM) return NULL;
    return build_binary_arith(IL_OP_CHECKED_ADD, left, right, option_type);
}

ILInstruction* il_build_checked_sub(ILValue left, ILValue right, const ILType* option_type) {
    if (option_type != NULL && option_type->kind != IL_TY_SUM) return NULL;
    return build_binary_arith(IL_OP_CHECKED_SUB, left, right, option_type);
}

ILInstruction* il_build_checked_mul(ILValue left, ILValue right, const ILType* option_type) {
    if (option_type != NULL && option_type->kind != IL_TY_SUM) return NULL;
    return build_binary_arith(IL_OP_CHECKED_MUL, left, right, option_type);
}

ILInstruction* il_build_alloc(uint32_t region_id, const ILType* alloc_type, const ILType* ptr_type, ILValue allocator) {
    if (alloc_type == NULL || ptr_type == NULL || (ptr_type->kind != IL_TY_PTR && ptr_type->kind != IL_TY_BOX)) {
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_ALLOC;
    instr->result_type = ptr_type;
    instr->result_id = 0;
    
    instr->operands.alloc.region_id = region_id;
    instr->operands.alloc.allocator_id = allocator.id;

    return instr;
}

ILInstruction* il_build_load(ILValue ptr) {
    if (ptr.type == NULL || (ptr.type->kind != IL_TY_PTR && ptr.type->kind != IL_TY_BOX && ptr.type->kind != IL_TY_SLICE)) {
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_LOAD;
    const ILType* pointee = NULL;
    if (ptr.type->kind == IL_TY_PTR) pointee = ptr.type->as.ptr.pointee;
    else if (ptr.type->kind == IL_TY_BOX) pointee = ptr.type->as.box.pointee;
    else if (ptr.type->kind == IL_TY_SLICE) pointee = ptr.type->as.slice.element;
    
    instr->result_type = pointee;
    instr->result_id = 0;
    instr->operands.load.ptr = ptr.id;

    return instr;
}

ILInstruction* il_build_store(ILValue ptr, ILValue value) {
    if (ptr.type == NULL || (ptr.type->kind != IL_TY_PTR && ptr.type->kind != IL_TY_BOX)) {
        return NULL;
    }
    const ILType* pointee = (ptr.type->kind == IL_TY_PTR) ? ptr.type->as.ptr.pointee : ptr.type->as.box.pointee;
    bool assignable = il_type_is_assignable(value.type, pointee);
    if (!assignable && is_numeric_type(value.type) && is_numeric_type(pointee)) {
        if (numeric_type_rank(value.type->kind) == numeric_type_rank(pointee->kind)) {
            assignable = true;
        }
    }

    if (!assignable) {
        char val_ty_str[128];
        char ptr_ty_str[128];
        il_type_print(value.type, val_ty_str, sizeof(val_ty_str));
        il_type_print(pointee, ptr_ty_str, sizeof(ptr_ty_str));
        fprintf(stderr, "DEBUG: il_build_store failed. value.type=%s, pointee=%s\n", val_ty_str, ptr_ty_str);
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_STORE;
    instr->result_type = il_build_unit_type();
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.store.ptr = ptr.id;
    instr->operands.store.value = value.id;
    return instr;
}

ILInstruction* il_build_drop(ILValue value) {
    if (value.type == NULL) {
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_DROP;
    instr->result_type = il_build_unit_type();
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.drop.value = value.id;

    return instr;
}

ILInstruction* il_build_bounds_check(ILValue index, ILValue length) {
    if (!is_integral_type(index.type) || !is_integral_type(length.type)) {
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_BOUNDS_CHECK;
    instr->result_type = il_build_unit_type();
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.bounds_check.index = index.id;
    instr->operands.bounds_check.length = length.id;

    return instr;
}

ILInstruction* il_build_move(ILValue source) {
    if (source.type == NULL) {
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_MOVE;
    instr->result_type = source.type;
    instr->result_id = 0;
    instr->operands.move.source = source.id;

    return instr;
}

ILInstruction* il_build_bitcast(ILValue source, const ILType* target_type) {
    if (source.type == NULL || target_type == NULL) return NULL;
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_BITCAST;
    instr->result_type = target_type;
    instr->result_id = 0;
    instr->operands.bitcast.source = source.id;
    return instr;
}

ILInstruction* il_build_call_ptr(ILValue func_ptr, const ILValue* args, uint32_t num_args, const ILType* result_type) {
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_CALL_PTR;
    instr->result_type = result_type;
    instr->result_id = 0;
    instr->operands.call_ptr.func_ptr_id = func_ptr.id;
    instr->operands.call_ptr.num_args = num_args;
    if (num_args > 0) {
        instr->operands.call_ptr.arg_ids = calloc(num_args, sizeof(uint32_t));
        for (uint32_t i = 0; i < num_args; i++) {
            instr->operands.call_ptr.arg_ids[i] = args[i].id;
        }
    }
    return instr;
}

ILInstruction* il_build_call(uint32_t func_id, const ILValue* args, uint32_t num_args, const ILType* result_type) {
    if (result_type == NULL) {
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_CALL;
    instr->result_type = result_type;
    instr->result_id = 0;
    instr->operands.call.func_id = func_id;
    instr->operands.call.num_args = num_args;
    
    if (num_args > 0 && args != NULL) {
        instr->operands.call.arg_ids = (uint32_t*)malloc(sizeof(uint32_t) * num_args);
        if (!instr->operands.call.arg_ids) {
            free(instr);
            return NULL;
        }
        for (uint32_t i = 0; i < num_args; i++) {
            instr->operands.call.arg_ids[i] = args[i].id;
        }
    } else {
        instr->operands.call.arg_ids = NULL;
    }

    return instr;
}

ILInstruction* il_build_return(ILValue value) {
    if (value.type == NULL) {
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_RETURN;
    instr->result_type = il_build_unit_type();
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.ret.value = value.id;

    return instr;
}

ILInstruction* il_build_branch(ILValue condition, uint32_t then_block_id, uint32_t else_block_id) {
    if (condition.type == NULL || condition.type->kind != IL_TY_BOOL) {
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_BRANCH;
    instr->result_type = il_build_unit_type();
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.branch.condition = condition.id;
    instr->operands.branch.then_block_id = then_block_id;
    instr->operands.branch.else_block_id = else_block_id;

    return instr;
}

ILInstruction* il_build_jump(uint32_t target_block_id) {
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_JUMP;
    instr->result_type = il_build_unit_type();
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.jump.target_block_id = target_block_id;

    return instr;
}
ILInstruction* il_build_phi(const ILPhiIncoming* incoming, uint32_t num_incoming, const ILType* result_type) {
    if (num_incoming == 0 || result_type == NULL) return NULL;

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_PHI;
    instr->result_type = result_type;
    instr->result_id = 0;
    instr->operands.phi.num_incoming = num_incoming;
    if (num_incoming > 0 && incoming != NULL) {
        instr->operands.phi.incoming = calloc(num_incoming, sizeof(ILPhiIncoming));
        if (!instr->operands.phi.incoming) {
            free(instr);
            return NULL;
        }
        for (uint32_t i = 0; i < num_incoming; i++) {
            instr->operands.phi.incoming[i].block_id = incoming[i].block_id;
            instr->operands.phi.incoming[i].value_id = incoming[i].value_id;
        }
    }
    return instr;
}

ILInstruction* il_build_fd_open(ILValue path, ILValue flags, ILValue mode,
                                const ILType* fd_type) {
    if (!fd_type || fd_type->kind != IL_TY_FD) return NULL;
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_FD_OPEN;
    instr->result_type = fd_type;
    instr->result_id = 0;

    instr->operands.fd_open.path  = path.id;
    instr->operands.fd_open.flags = flags.id;
    instr->operands.fd_open.mode  = mode.id;
    return instr;
}

ILInstruction* il_build_fd_close(ILValue fd) {
    if (!fd.type || fd.type->kind != IL_TY_FD) return NULL;
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_FD_CLOSE;
    instr->result_type = il_build_unit_type();
    instr->result_id = 0;

    instr->operands.fd_close.fd = fd.id;
    return instr;
}

ILInstruction* il_build_fd_read(ILValue fd, ILValue buf, ILValue count,
                                const ILType* i64_type) {
    if (!fd.type || (fd.type->kind != IL_TY_FD && fd.type->kind != IL_TY_I64 && fd.type->kind != IL_TY_U64 && fd.type->kind != IL_TY_I32 && fd.type->kind != IL_TY_U32)) return NULL;
    if (!i64_type || i64_type->kind != IL_TY_I64) return NULL;
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_FD_READ;
    instr->result_type = i64_type;
    instr->result_id = 0;

    instr->operands.fd_io.fd    = fd.id;
    instr->operands.fd_io.buf   = buf.id;
    instr->operands.fd_io.count = count.id;
    return instr;
}

ILInstruction* il_build_fd_write(ILValue fd, ILValue buf, ILValue count,
                                 const ILType* i64_type) {
    if (!fd.type || (fd.type->kind != IL_TY_FD && fd.type->kind != IL_TY_I64 && fd.type->kind != IL_TY_U64 && fd.type->kind != IL_TY_I32 && fd.type->kind != IL_TY_U32)) return NULL;
    if (!i64_type || i64_type->kind != IL_TY_I64) return NULL;
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_FD_WRITE;
    instr->result_type = i64_type;
    instr->result_id = 0;

    instr->operands.fd_io.fd    = fd.id;
    instr->operands.fd_io.buf   = buf.id;
    instr->operands.fd_io.count = count.id;
    return instr;
}

ILInstruction* il_build_async_setup(ILValue entries, const ILType* ctx_type) {
    if (!ctx_type || ctx_type->kind != IL_TY_ASYNC_CONTEXT) return NULL;
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_ASYNC_SETUP;
    instr->result_type = ctx_type;
    instr->result_id = 0;

    instr->operands.async_setup.entries = entries.id;
    return instr;
}

ILInstruction* il_build_async_enter(ILValue ctx, ILValue to_submit,
                                      ILValue min_complete,
                                      const ILType* i64_type) {
    if (!ctx.type || ctx.type->kind != IL_TY_ASYNC_CONTEXT) return NULL;
    if (!i64_type || i64_type->kind != IL_TY_I64) return NULL;
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_ASYNC_ENTER;
    instr->result_type = i64_type;
    instr->result_id = 0;

    instr->operands.async_enter.ctx          = ctx.id;
    instr->operands.async_enter.to_submit    = to_submit.id;
    instr->operands.async_enter.min_complete = min_complete.id;
    return instr;
}

ILInstruction* il_build_async_close(ILValue ctx) {
    if (!ctx.type || ctx.type->kind != IL_TY_ASYNC_CONTEXT) return NULL;
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_ASYNC_CLOSE;
    instr->result_type = il_build_unit_type();
    instr->result_id = 0;

    instr->operands.async_close.ctx = ctx.id;
    return instr;
}

void il_instr_free(ILInstruction* instr) {
    if (instr == NULL) return;

    // Result type
    
    // Opcode-specific cleanup
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
            break;
        case IL_OP_ALLOC:
            break;
        case IL_OP_LOAD:
            break;
        case IL_OP_STORE:
            break;
        case IL_OP_MOVE:
        case IL_OP_UNWRAP:
        case IL_OP_IS_SOME:
            break;
        case IL_OP_BITCAST:
            break;
        case IL_OP_DROP:
            break;
        case IL_OP_BOUNDS_CHECK:
            break;
        case IL_OP_SLICE_LOAD:
            break;
        case IL_OP_ARRAY_CONSTRUCT:
            free(instr->operands.array_construct.element_ids);
            break;
        case IL_OP_ARRAY_LOAD:
            break;
        case IL_OP_ARRAY_STORE:
            break;
        case IL_OP_SLICE_STORE:
            break;
        case IL_OP_SLICE_LEN:
        case IL_OP_SLICE_DATA:
            break;
        case IL_OP_SLICE_CONSTRUCT:
            break;
        case IL_OP_REGION_CAST:
            break;
        case IL_OP_CALL:
            free(instr->operands.call.arg_ids);
            break;
        case IL_OP_CALL_PTR:
            free(instr->operands.call_ptr.arg_ids);
            break;
        case IL_OP_FUNC_ADDR:
            break;
        case IL_OP_RETURN:
            break;
        case IL_OP_BRANCH:
            break;
        case IL_OP_JUMP:
            break;
        case IL_OP_FIELD_ADDR:
            break;
        case IL_OP_ELEM_ADDR:
            break;
        case IL_OP_VARIANT_MATCH:
            break;
        case IL_OP_SUM_CONSTRUCT:
            break;
        case IL_OP_FD_OPEN:
            break;
        case IL_OP_FD_CLOSE:
            break;
        case IL_OP_FD_READ:
        case IL_OP_FD_WRITE:
            break;
        case IL_OP_ASYNC_SETUP:
            break;
        case IL_OP_ASYNC_ENTER:
            break;
        case IL_OP_ASYNC_CLOSE:
            break;
        case IL_OP_SYSCALL:
            free(instr->operands.syscall_op.arg_ids);
            break;
        case IL_OP_PHI:
            free(instr->operands.phi.incoming);
            break;
        case IL_OP_STRING_CONST:
            free(instr->operands.string_literal.val);
            break;
        default:
            break;
    }
    free(instr);
}

ILInstruction* il_build_slice_load(ILValue slice_ptr, ILValue index) {
    if (slice_ptr.type == NULL) return NULL;
    bool is_slice = (slice_ptr.type->kind == IL_TY_SLICE);
    bool is_ptr_to_slice = (slice_ptr.type->kind == IL_TY_PTR && slice_ptr.type->as.ptr.pointee->kind == IL_TY_SLICE);
    if (!is_slice && !is_ptr_to_slice) return NULL;
    if (index.type == NULL) return NULL;

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    const ILType* actual_slice = is_slice ? slice_ptr.type : slice_ptr.type->as.ptr.pointee;
    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_SLICE_LOAD;
    instr->result_type = actual_slice->as.slice.element;
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.slice_load.slice_ptr = slice_ptr.id;
    instr->operands.slice_load.index = index.id;

    return instr;
}

ILInstruction* il_build_slice_store(ILValue slice_ptr, ILValue index, ILValue value) {
    if (slice_ptr.type == NULL) return NULL;
    bool is_slice = (slice_ptr.type->kind == IL_TY_SLICE);
    bool is_ptr_to_slice = (slice_ptr.type->kind == IL_TY_PTR && slice_ptr.type->as.ptr.pointee->kind == IL_TY_SLICE);
    if (!is_slice && !is_ptr_to_slice) return NULL;
    if (index.type == NULL) return NULL;
    const ILType* actual_slice = is_slice ? slice_ptr.type : slice_ptr.type->as.ptr.pointee;
    if (!il_type_is_assignable(value.type, actual_slice->as.slice.element)) return NULL;

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_SLICE_STORE;
    instr->result_type = il_build_unit_type();
    instr->result_id = 0;
    instr->operands.slice_store.slice_ptr = slice_ptr.id;
    instr->operands.slice_store.index = index.id;
    instr->operands.slice_store.value = value.id;

    return instr;
}

ILInstruction* il_build_slice_len(ILValue slice_ptr, const ILType* u64_type) {
    if (slice_ptr.type == NULL) return NULL;
    bool is_slice = (slice_ptr.type->kind == IL_TY_SLICE);
    bool is_ptr_to_slice = (slice_ptr.type->kind == IL_TY_PTR && slice_ptr.type->as.ptr.pointee->kind == IL_TY_SLICE);
    if (!is_slice && !is_ptr_to_slice) return NULL;

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_SLICE_LEN;
    instr->result_type = u64_type;
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.slice_op.slice_ptr = slice_ptr.id;
    return instr;
}

ILInstruction* il_build_slice_data(ILValue slice_ptr, const ILType* ptr_type) {
    if (slice_ptr.type == NULL) return NULL;
    bool is_slice = (slice_ptr.type->kind == IL_TY_SLICE);
    bool is_ptr_to_slice = (slice_ptr.type->kind == IL_TY_PTR && slice_ptr.type->as.ptr.pointee->kind == IL_TY_SLICE);
    if (!is_slice && !is_ptr_to_slice) return NULL;

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_SLICE_DATA;
    instr->result_type = ptr_type;
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.slice_op.slice_ptr = slice_ptr.id;
    return instr;
}

ILInstruction* il_build_is_some(ILValue option, const ILType* bool_type) {
    if (option.type == NULL) return NULL;
    /* Accept SUM directly or a pointer/box whose pointee is a SUM type. */
    const ILType* inner = option.type;
    if (inner->kind == IL_TY_PTR) inner = inner->as.ptr.pointee;
    else if (inner->kind == IL_TY_BOX) inner = inner->as.box.pointee;
    if (inner->kind != IL_TY_SUM) return NULL;
    if (bool_type == NULL || bool_type->kind != IL_TY_BOOL) return NULL;

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_IS_SOME;
    instr->result_type = bool_type;
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.move.source = option.id;

    return instr;
}

ILInstruction* il_build_unwrap(ILValue option, const ILType* result_type) {
    if (option.type == NULL) return NULL;
    const ILType* t = option.type;
    if (t->kind == IL_TY_PTR) t = t->as.ptr.pointee;
    if (t->kind != IL_TY_SUM) return NULL;
    if (result_type == NULL) return NULL;

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_UNWRAP;
    instr->result_type = result_type;
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.move.source = option.id;

    return instr;
}

ILInstruction* il_build_region_cast(ILValue source, uint32_t target_region_id) {
    if (source.type == NULL || source.type->kind != IL_TY_PTR) {
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_REGION_CAST;
    instr->result_type = il_type_ptr(source.type->as.ptr.pointee, target_region_id, source.type->as.ptr.is_mut);
    if (!instr->result_type) { free(instr); return NULL; }
    
    instr->result_id = 0;
    instr->operands.region_cast.source = source.id;
    instr->operands.region_cast.target_region_id = target_region_id;

    return instr;
}

ILInstruction* il_build_func_addr(uint32_t func_id, const ILType* fn_type) {
    if (fn_type == NULL || fn_type->kind != IL_TY_FN) {
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->opcode = IL_OP_FUNC_ADDR;
    instr->result_type = fn_type;
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.func_addr.func_id = func_id;
    return instr;
}

ILInstruction* il_build_global_addr(uint32_t global_id, const ILType* ptr_type) {
    if (ptr_type == NULL || ptr_type->kind != IL_TY_PTR) {
        return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_GLOBAL_ADDR;
    instr->result_type = ptr_type;
    if (!instr->result_type) { free(instr); return NULL; }
    instr->result_id = 0;
    instr->operands.global_addr.global_id = global_id;

    return instr;
}

ILInstruction* il_build_field_addr(ILValue struct_ptr, uint32_t field_index, const ILType* ptr_type) {
    if (ptr_type == NULL || ptr_type->kind != IL_TY_PTR) return NULL;

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_FIELD_ADDR;
    instr->result_type = ptr_type;
    instr->result_id = 0;
    instr->operands.field_addr.struct_ptr = struct_ptr.id;
    instr->operands.field_addr.field_index = field_index;

    return instr;
}

ILInstruction* il_build_elem_addr(ILValue base, ILValue index, const ILType* ptr_type) {
    if (ptr_type == NULL || ptr_type->kind != IL_TY_PTR) return NULL;

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_ELEM_ADDR;
    instr->result_type = ptr_type;
    instr->result_id = 0;
    instr->operands.elem_addr.base = base.id;
    instr->operands.elem_addr.index = index.id;

    return instr;
}

ILInstruction* il_build_variant_match(ILValue sum_ptr, uint32_t variant_index, uint32_t target_block_id, uint32_t next_block_id) {
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_VARIANT_MATCH;
    instr->result_type = NULL;
    instr->result_id = 0;
    instr->operands.variant_match.sum_ptr = sum_ptr.id;
    instr->operands.variant_match.variant_index = variant_index;
    instr->operands.variant_match.target_block_id = target_block_id;
    instr->operands.variant_match.next_block_id = next_block_id;

    return instr;
}

ILInstruction* il_build_syscall(uint32_t syscall_num, const ILValue* args, uint32_t num_args, const ILType* result_type) {
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_SYSCALL;
    instr->result_type = result_type;
    instr->result_id = 0;
    
    instr->operands.syscall_op.syscall_num = syscall_num;
    instr->operands.syscall_op.num_args = num_args;
    if (num_args > 0 && args != NULL) {
        instr->operands.syscall_op.arg_ids = calloc(num_args, sizeof(uint32_t));
        if (!instr->operands.syscall_op.arg_ids) {
            free(instr);
            return NULL;
        }
        for (uint32_t i = 0; i < num_args; i++) {
            instr->operands.syscall_op.arg_ids[i] = args[i].id;
        }
    } else {
        instr->operands.syscall_op.arg_ids = NULL;
    }

    return instr;
}

ILInstruction* il_build_const(uint64_t val, const ILType* type) {
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_CONST;
    instr->result_type = type;
    instr->result_id = 0;
    instr->operands.const_val.u.val = val;

    return instr;
}

ILInstruction* il_build_fconst(double val, const ILType* type) {
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_CONST;
    instr->result_type = type;
    instr->result_id = 0;
    instr->operands.const_val.u.fval = val;

    return instr;
}


static ILInstruction* build_cmp(ILOpcode op, ILValue left, ILValue right, const ILType* bool_type) {
    if (op != IL_OP_CMP_EQ && op != IL_OP_CMP_NE) {
        if (!validate_arithmetic_operands(left, right)) return NULL;
    } else {
        if (!left.type || !right.type) return NULL;
    }

    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->opcode = (uint8_t)op;
    instr->result_type = bool_type;
    instr->result_id = 0;
    instr->operands.binary.left = left.id;
    instr->operands.binary.right = right.id;

    return instr;
}

ILInstruction* il_build_cmp_lt(ILValue left, ILValue right, const ILType* bool_type) {
    return build_cmp(IL_OP_CMP_LT, left, right, bool_type);
}

ILInstruction* il_build_cmp_le(ILValue left, ILValue right, const ILType* bool_type) {
    return build_cmp(IL_OP_CMP_LE, left, right, bool_type);
}

ILInstruction* il_build_cmp_gt(ILValue left, ILValue right, const ILType* bool_type) {
    return build_cmp(IL_OP_CMP_GT, left, right, bool_type);
}

ILInstruction* il_build_cmp_ge(ILValue left, ILValue right, const ILType* bool_type) {
    return build_cmp(IL_OP_CMP_GE, left, right, bool_type);
}

ILInstruction* il_build_cmp_eq(ILValue left, ILValue right, const ILType* bool_type) {
    return build_cmp(IL_OP_CMP_EQ, left, right, bool_type);
}

ILInstruction* il_build_cmp_ne(ILValue left, ILValue right, const ILType* bool_type) {
    return build_cmp(IL_OP_CMP_NE, left, right, bool_type);
}

ILInstruction* il_build_sum_construct(uint32_t type_def_id, uint32_t variant_index, ILValue payload, const ILType* result_type) {
    ILInstruction* instr = (ILInstruction*)calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_SUM_CONSTRUCT;
    instr->result_type = result_type;
    instr->result_id = 0;
    instr->operands.sum_construct.type_def_id = type_def_id;
    instr->operands.sum_construct.variant_index = variant_index;
    instr->operands.sum_construct.payload_id = payload.id;
    return instr;
}
ILInstruction* il_build_slice_construct(ILValue ptr, ILValue len, const ILType* slice_ty) {
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;

    instr->line = 0; instr->col = 0; instr->opcode = IL_OP_SLICE_CONSTRUCT;
    instr->result_type = slice_ty;
    instr->result_id = 0;
    instr->operands.slice_construct.ptr = ptr.id;
    instr->operands.slice_construct.len = len.id;
    return instr;
}

ILInstruction* il_build_array_construct(const ILValue* elements, uint32_t count, const ILType* array_type) {
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_ARRAY_CONSTRUCT;
    instr->result_type = array_type;
    instr->result_id = 0;
    
    instr->operands.array_construct.count = count;
    if (count > 0) {
        instr->operands.array_construct.element_ids = calloc(count, sizeof(uint32_t));
        for (uint32_t i = 0; i < count; i++) {
            instr->operands.array_construct.element_ids[i] = elements[i].id;
        }
    }
    return instr;
}

ILInstruction* il_build_array_load(ILValue array_ptr, ILValue index, const ILType* result_type) {
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_ARRAY_LOAD;
    instr->result_type = result_type;
    instr->result_id = 0;
    instr->operands.array_load.array_ptr = array_ptr.id;
    instr->operands.array_load.index = index.id;
    return instr;
}

ILInstruction* il_build_array_store(ILValue array_ptr, ILValue index, ILValue value) {
    ILInstruction* instr = calloc(1, sizeof(ILInstruction));
    if (!instr) return NULL;
    instr->opcode = IL_OP_ARRAY_STORE;
    instr->result_type = il_build_unit_type();
    instr->result_id = 0;
    instr->operands.array_store.array_ptr = array_ptr.id;
    instr->operands.array_store.index = index.id;
    instr->operands.array_store.value = value.id;
    return instr;
}
