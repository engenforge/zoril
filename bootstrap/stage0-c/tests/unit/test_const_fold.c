#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include "test_harness.h"
#include "../include/il_cfg.h"
#include "../include/il_instr.h"
#include "../include/il_pass.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

/* Build a single-block function: const a, const b, <op> a b -> v3, ret v3 */
static ILFunction* make_binop_func(ILOpcode op, uint64_t a, uint64_t b,
                                   ILTypeKind operand_kind, ILTypeKind result_kind) {
    const ILType * op_ty = (operand_kind == IL_TY_U32) ? il_type_u32() : il_type_bool();
    const ILType * res_ty = (result_kind == IL_TY_U32) ? il_type_u32() : il_type_bool();

    ILInstruction* c_a = il_build_const(a, op_ty);   ABORT_IF_NULL(c_a);
    c_a->result_id = 1;
    ILInstruction* c_b = il_build_const(b, op_ty);   ABORT_IF_NULL(c_b);
    c_b->result_id = 2;

    ILValue va = { .id = 1, .type = op_ty };
    ILValue vb = { .id = 2, .type = op_ty };

    ILInstruction* binop = NULL;
    switch (op) {
        case IL_OP_ADD:     binop = il_build_add(va, vb); break;
        case IL_OP_SUB:     binop = il_build_sub(va, vb); break;
        case IL_OP_MUL:     binop = il_build_mul(va, vb); break;
        case IL_OP_AND:     binop = il_build_and(va, vb); break;
        case IL_OP_OR:      binop = il_build_or(va, vb);  break;
        case IL_OP_XOR:     binop = il_build_xor(va, vb); break;
        case IL_OP_CMP_LT: {
            const ILType * bool_ty = il_type_bool();
            binop = il_build_cmp_lt(va, vb, bool_ty);
            break;
        }
        case IL_OP_CMP_EQ: {
            const ILType * bool_ty = il_type_bool();
            binop = il_build_cmp_eq(va, vb, bool_ty);
            break;
        }
        default: break;
    }
    ABORT_IF_NULL(binop);
    binop->result_id = 3;

    ILValue vr = { .id = 3, .type = res_ty };
    ILInstruction* ret = il_build_return(vr); ABORT_IF_NULL(ret);

    ILBasicBlock* block = il_block_create(1); ABORT_IF_NULL(block);
    il_block_add_instr(block, c_a);
    il_block_add_instr(block, c_b);
    il_block_add_instr(block, binop);
    il_block_add_instr(block, ret);

    ILFunction* func = il_func_create_synthetic(1, "test_fold", res_ty); ABORT_IF_NULL(func);
    il_func_add_block(func, block);

    return func;
}

/* Fold: 3 + 4 == 7 */
static bool test_fold_add(void) {
    ILFunction* func = make_binop_func(IL_OP_ADD, 3, 4, IL_TY_U32, IL_TY_U32);
    ASSERT(func != NULL, "make_binop_func returned NULL");

    il_func_assign_rpo_ids(func);
    il_pass_const_fold(NULL, func);

    const ILInstruction* instr = func->blocks[0]->instructions[2];
    ASSERT(instr->opcode == IL_OP_CONST, "add(3,4) should be folded to const");
    ASSERT(instr->operands.const_val.u.val == 7, "3 + 4 should fold to 7");

    il_func_free(func);
    return true;
}

/* Fold: 10 - 3 == 7 */
static bool test_fold_sub(void) {
    ILFunction* func = make_binop_func(IL_OP_SUB, 10, 3, IL_TY_U32, IL_TY_U32);
    ASSERT(func != NULL, "make_binop_func returned NULL");

    il_func_assign_rpo_ids(func);
    il_pass_const_fold(NULL, func);

    const ILInstruction* instr = func->blocks[0]->instructions[2];
    ASSERT(instr->opcode == IL_OP_CONST, "sub(10,3) should be folded to const");
    ASSERT(instr->operands.const_val.u.val == 7, "10 - 3 should fold to 7");

    il_func_free(func);
    return true;
}

/* Fold: 6 * 7 == 42 */
static bool test_fold_mul(void) {
    ILFunction* func = make_binop_func(IL_OP_MUL, 6, 7, IL_TY_U32, IL_TY_U32);
    ASSERT(func != NULL, "make_binop_func returned NULL");

    il_func_assign_rpo_ids(func);
    il_pass_const_fold(NULL, func);

    const ILInstruction* instr = func->blocks[0]->instructions[2];
    ASSERT(instr->opcode == IL_OP_CONST, "mul(6,7) should be folded to const");
    ASSERT(instr->operands.const_val.u.val == 42, "6 * 7 should fold to 42");

    il_func_free(func);
    return true;
}

/* Fold: 3 < 5 == 1 (true) */
static bool test_fold_cmp_lt_true(void) {
    ILFunction* func = make_binop_func(IL_OP_CMP_LT, 3, 5, IL_TY_U32, IL_TY_BOOL);
    ASSERT(func != NULL, "make_binop_func returned NULL");

    il_func_assign_rpo_ids(func);
    il_pass_const_fold(NULL, func);

    const ILInstruction* instr = func->blocks[0]->instructions[2];
    ASSERT(instr->opcode == IL_OP_CONST, "cmp_lt(3,5) should be folded to const");
    ASSERT(instr->operands.const_val.u.val == 1, "3 < 5 should fold to 1 (true)");

    il_func_free(func);
    return true;
}

/* Fold: 5 < 3 == 0 (false) */
static bool test_fold_cmp_lt_false(void) {
    ILFunction* func = make_binop_func(IL_OP_CMP_LT, 5, 3, IL_TY_U32, IL_TY_BOOL);
    ASSERT(func != NULL, "make_binop_func returned NULL");

    il_func_assign_rpo_ids(func);
    il_pass_const_fold(NULL, func);

    const ILInstruction* instr = func->blocks[0]->instructions[2];
    ASSERT(instr->opcode == IL_OP_CONST, "cmp_lt(5,3) should be folded to const");
    ASSERT(instr->operands.const_val.u.val == 0, "5 < 3 should fold to 0 (false)");

    il_func_free(func);
    return true;
}

/* Fold: 7 == 7 == 1 (true) */
static bool test_fold_cmp_eq(void) {
    ILFunction* func = make_binop_func(IL_OP_CMP_EQ, 7, 7, IL_TY_U32, IL_TY_BOOL);
    ASSERT(func != NULL, "make_binop_func returned NULL");

    il_func_assign_rpo_ids(func);
    il_pass_const_fold(NULL, func);

    const ILInstruction* instr = func->blocks[0]->instructions[2];
    ASSERT(instr->opcode == IL_OP_CONST, "cmp_eq(7,7) should be folded to const");
    ASSERT(instr->operands.const_val.u.val == 1, "7 == 7 should fold to 1 (true)");

    il_func_free(func);
    return true;
}

/* Chained fold: (2 + 3) * 4 == 20 */
static bool test_fold_chained(void) {
    const ILType * u32_ty = il_type_u32();

    ILInstruction* c2 = il_build_const(2, u32_ty); ABORT_IF_NULL(c2); c2->result_id = 1;
    ILInstruction* c3 = il_build_const(3, u32_ty); ABORT_IF_NULL(c3); c3->result_id = 2;
    ILValue v1 = { .id = 1, .type = u32_ty };
    ILValue v2 = { .id = 2, .type = u32_ty };
    ILInstruction* add = il_build_add(v1, v2); ABORT_IF_NULL(add); add->result_id = 3;

    ILInstruction* c4 = il_build_const(4, u32_ty); ABORT_IF_NULL(c4); c4->result_id = 4;
    ILValue v3 = { .id = 3, .type = u32_ty };
    ILValue v4 = { .id = 4, .type = u32_ty };
    ILInstruction* mul = il_build_mul(v3, v4); ABORT_IF_NULL(mul); mul->result_id = 5;

    ILValue v5 = { .id = 5, .type = u32_ty };
    ILInstruction* ret = il_build_return(v5); ABORT_IF_NULL(ret);

    ILBasicBlock* block = il_block_create(1); ABORT_IF_NULL(block);
    il_block_add_instr(block, c2);
    il_block_add_instr(block, c3);
    il_block_add_instr(block, add);
    il_block_add_instr(block, c4);
    il_block_add_instr(block, mul);
    il_block_add_instr(block, ret);

    ILFunction* func = il_func_create_synthetic(1, "test_chained", u32_ty); ABORT_IF_NULL(func);
    il_func_add_block(func, block);

    il_func_assign_rpo_ids(func);
    il_pass_const_fold(NULL, func);

    /* Both add and mul should have been folded */
    const ILInstruction* add_instr = func->blocks[0]->instructions[2];
    const ILInstruction* mul_instr = func->blocks[0]->instructions[4];

    ASSERT(add_instr->opcode == IL_OP_CONST, "add(2,3) should be folded");
    ASSERT(add_instr->operands.const_val.u.val == 5, "2 + 3 should fold to 5");
    ASSERT(mul_instr->opcode == IL_OP_CONST, "mul(5,4) should be folded via chain");
    ASSERT(mul_instr->operands.const_val.u.val == 20, "(2+3) * 4 should fold to 20");

    il_func_free(func);
    return true;
}

/* Non-const operand: add(param, 4) must NOT be folded */
static bool test_no_fold_nonconstant(void) {
    const ILType * u32_ty = il_type_u32();

    /* v1 is a parameter (id=1), not defined by a const instruction */
    ILInstruction* c4 = il_build_const(4, u32_ty); ABORT_IF_NULL(c4); c4->result_id = 2;
    ILValue v1 = { .id = 1, .type = u32_ty }; /* param */
    ILValue v2 = { .id = 2, .type = u32_ty };
    ILInstruction* add = il_build_add(v1, v2); ABORT_IF_NULL(add); add->result_id = 3;

    ILValue v3 = { .id = 3, .type = u32_ty };
    ILInstruction* ret = il_build_return(v3); ABORT_IF_NULL(ret);

    ILBasicBlock* block = il_block_create(1); ABORT_IF_NULL(block);
    il_block_add_instr(block, c4);
    il_block_add_instr(block, add);
    il_block_add_instr(block, ret);

    const ILType * param_ty = il_type_u32();

    ILFunction* func = il_func_create_synthetic(1, "test_nofold", u32_ty); ABORT_IF_NULL(func);
    il_func_add_param(func, param_ty);
    il_func_add_block(func, block);

    il_func_assign_rpo_ids(func);
    il_pass_const_fold(NULL, func);

    const ILInstruction* add_instr = func->blocks[0]->instructions[1];
    ASSERT(add_instr->opcode == IL_OP_ADD, "add(param,4) must NOT be folded");

    il_func_free(func);
    return true;
}

/* i32::MAX +% 1 < 0  →  true (wraps to i32::MIN which is negative) */
static bool test_fold_wrapping_add_sign_extend(void) {
    const ILType* i32_ty  = il_type_i32();
    const ILType* bool_ty = il_type_bool();

    ILInstruction* c_max = il_build_const(0x7FFFFFFFu, i32_ty); ABORT_IF_NULL(c_max); c_max->result_id = 1;
    ILInstruction* c_one = il_build_const(1, i32_ty);            ABORT_IF_NULL(c_one); c_one->result_id = 2;
    ILValue v1 = { .id = 1, .type = i32_ty };
    ILValue v2 = { .id = 2, .type = i32_ty };
    ILInstruction* wrap = il_build_wrapping_add(v1, v2); ABORT_IF_NULL(wrap); wrap->result_id = 3;

    ILInstruction* c_zer = il_build_const(0, i32_ty); ABORT_IF_NULL(c_zer); c_zer->result_id = 4;
    ILValue v3 = { .id = 3, .type = i32_ty };
    ILValue v4 = { .id = 4, .type = i32_ty };
    ILInstruction* cmp = il_build_cmp_lt(v3, v4, bool_ty); ABORT_IF_NULL(cmp); cmp->result_id = 5;

    ILValue v5 = { .id = 5, .type = bool_ty };
    ILInstruction* ret = il_build_return(v5); ABORT_IF_NULL(ret);

    ILBasicBlock* block = il_block_create(1); ABORT_IF_NULL(block);
    il_block_add_instr(block, c_max);
    il_block_add_instr(block, c_one);
    il_block_add_instr(block, wrap);
    il_block_add_instr(block, c_zer);
    il_block_add_instr(block, cmp);
    il_block_add_instr(block, ret);

    ILFunction* func = il_func_create_synthetic(1, "test_wrap_sign", bool_ty); ABORT_IF_NULL(func);
    il_func_add_block(func, block);
    il_func_assign_rpo_ids(func);
    il_pass_const_fold(NULL, func);

    const ILInstruction* wrap_instr = func->blocks[0]->instructions[2];
    const ILInstruction* cmp_instr  = func->blocks[0]->instructions[4];

    ASSERT(wrap_instr->opcode == IL_OP_CONST, "wrapping_add(i32::MAX, 1) should be folded");
    /* After truncation, i32::MAX+1 = 0x80000000 sign-extended = 0xFFFFFFFF80000000 */
    ASSERT((int64_t)wrap_instr->operands.const_val.u.val == -2147483648LL,
           "i32::MAX +% 1 should fold to i32::MIN (-2147483648)");

    ASSERT(cmp_instr->opcode == IL_OP_CONST, "comparison should be folded");
    ASSERT(cmp_instr->operands.const_val.u.val == 1,
           "i32::MAX +% 1 < 0 should fold to true (1)");

    il_func_free(func);
    return true;
}

/* i32::MIN -% 1 > 0  →  true (wraps to i32::MAX which is positive) */
static bool test_fold_wrapping_sub_sign_extend(void) {
    const ILType* i32_ty  = il_type_i32();
    const ILType* bool_ty = il_type_bool();

    ILInstruction* c_min = il_build_const(0x80000000u, i32_ty); ABORT_IF_NULL(c_min); c_min->result_id = 1;
    ILInstruction* c_one = il_build_const(1, i32_ty);            ABORT_IF_NULL(c_one); c_one->result_id = 2;
    ILValue v1 = { .id = 1, .type = i32_ty };
    ILValue v2 = { .id = 2, .type = i32_ty };
    ILInstruction* wrap = il_build_wrapping_sub(v1, v2); ABORT_IF_NULL(wrap); wrap->result_id = 3;

    ILInstruction* c_zer = il_build_const(0, i32_ty); ABORT_IF_NULL(c_zer); c_zer->result_id = 4;
    ILValue v3 = { .id = 3, .type = i32_ty };
    ILValue v4 = { .id = 4, .type = i32_ty };
    ILInstruction* cmp = il_build_cmp_lt(v4, v3, bool_ty); ABORT_IF_NULL(cmp); cmp->result_id = 5;

    ILValue v5 = { .id = 5, .type = bool_ty };
    ILInstruction* ret = il_build_return(v5); ABORT_IF_NULL(ret);

    ILBasicBlock* block = il_block_create(1); ABORT_IF_NULL(block);
    il_block_add_instr(block, c_min);
    il_block_add_instr(block, c_one);
    il_block_add_instr(block, wrap);
    il_block_add_instr(block, c_zer);
    il_block_add_instr(block, cmp);
    il_block_add_instr(block, ret);

    ILFunction* func = il_func_create_synthetic(1, "test_wrap_sub_sign", bool_ty); ABORT_IF_NULL(func);
    il_func_add_block(func, block);
    il_func_assign_rpo_ids(func);
    il_pass_const_fold(NULL, func);

    const ILInstruction* wrap_instr = func->blocks[0]->instructions[2];
    const ILInstruction* cmp_instr  = func->blocks[0]->instructions[4];

    ASSERT(wrap_instr->opcode == IL_OP_CONST, "wrapping_sub(i32::MIN, 1) should be folded");
    ASSERT((int64_t)wrap_instr->operands.const_val.u.val == 2147483647LL,
           "i32::MIN -% 1 should fold to i32::MAX (2147483647)");

    ASSERT(cmp_instr->opcode == IL_OP_CONST, "comparison should be folded");
    ASSERT(cmp_instr->operands.const_val.u.val == 1,
           "0 < i32::MIN -% 1 should fold to true (1)");

    il_func_free(func);
    return true;
}

/* u32 wrapping add: u32::MAX +% 1 == 0 (wraps to 0, unsigned) */
static bool test_fold_wrapping_add_u32(void) {
    const ILType* u32_ty  = il_type_u32();
    const ILType* bool_ty = il_type_bool();

    ILInstruction* c_max = il_build_const(0xFFFFFFFFu, u32_ty); ABORT_IF_NULL(c_max); c_max->result_id = 1;
    ILInstruction* c_one = il_build_const(1, u32_ty);            ABORT_IF_NULL(c_one); c_one->result_id = 2;
    ILValue v1 = { .id = 1, .type = u32_ty };
    ILValue v2 = { .id = 2, .type = u32_ty };
    ILInstruction* wrap = il_build_wrapping_add(v1, v2); ABORT_IF_NULL(wrap); wrap->result_id = 3;

    ILInstruction* c_zer = il_build_const(0, u32_ty); ABORT_IF_NULL(c_zer); c_zer->result_id = 4;
    ILValue v3 = { .id = 3, .type = u32_ty };
    ILValue v4 = { .id = 4, .type = u32_ty };
    ILInstruction* cmp = il_build_cmp_lt(v3, v4, bool_ty); ABORT_IF_NULL(cmp); cmp->result_id = 5;

    ILValue v5 = { .id = 5, .type = bool_ty };
    ILInstruction* ret = il_build_return(v5); ABORT_IF_NULL(ret);

    ILBasicBlock* block = il_block_create(1); ABORT_IF_NULL(block);
    il_block_add_instr(block, c_max);
    il_block_add_instr(block, c_one);
    il_block_add_instr(block, wrap);
    il_block_add_instr(block, c_zer);
    il_block_add_instr(block, cmp);
    il_block_add_instr(block, ret);

    ILFunction* func = il_func_create_synthetic(1, "test_wrap_u32", bool_ty); ABORT_IF_NULL(func);
    il_func_add_block(func, block);
    il_func_assign_rpo_ids(func);
    il_pass_const_fold(NULL, func);

    const ILInstruction* wrap_instr = func->blocks[0]->instructions[2];
    const ILInstruction* cmp_instr  = func->blocks[0]->instructions[4];

    ASSERT(wrap_instr->opcode == IL_OP_CONST, "wrapping_add(u32::MAX, 1) should be folded");
    ASSERT(wrap_instr->operands.const_val.u.val == 0,
           "u32::MAX +% 1 should fold to 0");

    ASSERT(cmp_instr->opcode == IL_OP_CONST, "comparison should be folded");
    ASSERT(cmp_instr->operands.const_val.u.val == 0,
           "u32::MAX +% 1 < 0 should fold to false (0) for unsigned");

    il_func_free(func);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_fold_add);
    RUN_TEST(test_fold_sub);
    RUN_TEST(test_fold_mul);
    RUN_TEST(test_fold_cmp_lt_true);
    RUN_TEST(test_fold_cmp_lt_false);
    RUN_TEST(test_fold_cmp_eq);
    RUN_TEST(test_fold_chained);
    RUN_TEST(test_no_fold_nonconstant);
    RUN_TEST(test_fold_wrapping_add_sign_extend);
    RUN_TEST(test_fold_wrapping_sub_sign_extend);
    RUN_TEST(test_fold_wrapping_add_u32);

    printf("Results: %d/%d passed\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_passed == tests_run) ? 0 : 1;
}
