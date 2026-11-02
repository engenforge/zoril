#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "il_type.h"
#include "il_instr.h"
#include "il_cfg.h"
#include "verifier.h"
#include "il_pass.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_cross_block_use_after_move_rejected(void) {
    const ILType * u32_type = il_type_u32();
    const ILType * box_u32 = il_type_box(u32_type, REGION_LOCAL, true);

    ILValue v_box = { .id = 1, .type = box_u32 };
    
    ILInstruction* alloc = il_build_alloc(REGION_LOCAL, u32_type, box_u32, (ILValue){0});
    alloc->result_id = 1;
    const ILType * bool_type = il_type_bool();
    ILValue v_cond = { .id = 2, .type = bool_type };
    ILInstruction* branch = il_build_branch(v_cond, 2, 3);
    
    ILBasicBlock* b1 = il_block_create(1);
    il_block_add_instr(b1, alloc);
    il_block_add_instr(b1, branch);

    ILInstruction* move_instr = il_build_move(v_box);
    move_instr->result_id = 3;
    ILInstruction* jump_b4_from_b2 = il_build_branch(v_cond, 4, 4);
    ILBasicBlock* b2 = il_block_create(2);
    il_block_add_instr(b2, move_instr);
    il_block_add_instr(b2, jump_b4_from_b2);

    ILInstruction* jump_b4_from_b3 = il_build_branch(v_cond, 4, 4);
    ILBasicBlock* b3 = il_block_create(3);
    il_block_add_instr(b3, jump_b4_from_b3);

    ILInstruction* drop_instr = il_build_drop(v_box);
    ILBasicBlock* b4 = il_block_create(4);
    il_block_add_instr(b4, drop_instr);

    il_block_add_successor(b1, b2);
    il_block_add_successor(b1, b3);
    il_block_add_successor(b2, b4);
    il_block_add_successor(b3, b4);

    const ILType * unit_ret = il_type_unit();
    ILFunction* func = il_func_create_synthetic(1, "test_func", unit_ret);
    il_func_add_block(func, b1);
    il_func_add_block(func, b2);
    il_func_add_block(func, b3);
    il_func_add_block(func, b4);

    il_func_auto_drop(NULL, func);
    VerificationResult res = verify_function(NULL, func);

    bool is_safe = res.is_safe;
    il_func_free(func);
    verify_result_free(&res);

    ASSERT(is_safe == false, "Cross-block use after move should be rejected");
    return true;
}

static bool test_sibling_block_move_accepted(void) {
    const ILType * u32_type = il_type_u32();
    const ILType * box_u32 = il_type_box(u32_type, REGION_LOCAL, true);

    ILValue v_box = { .id = 1, .type = box_u32 };
    
    ILInstruction* alloc = il_build_alloc(REGION_LOCAL, u32_type, box_u32, (ILValue){0});
    alloc->result_id = 1;
    const ILType * bool_type = il_type_bool();
    ILValue v_cond = { .id = 2, .type = bool_type };
    ILInstruction* branch = il_build_branch(v_cond, 2, 3);
    
    ILBasicBlock* b1 = il_block_create(1);
    il_block_add_instr(b1, alloc);
    il_block_add_instr(b1, branch);

    ILInstruction* move_instr = il_build_move(v_box);
    move_instr->result_id = 3;
    const ILType * unit_type = il_type_unit();
    ILValue unit_val2 = { .id = 0, .type = unit_type };
    ILInstruction* ret_instr2 = il_build_return(unit_val2);

    ILBasicBlock* b2 = il_block_create(2);
    il_block_add_instr(b2, move_instr);
    ILInstruction* drop_v3 = il_build_drop((ILValue){.id = 3, .type = box_u32});
    il_block_add_instr(b2, drop_v3);
    il_block_add_instr(b2, ret_instr2);

    ILInstruction* drop_instr = il_build_drop(v_box);
    ILValue unit_val3 = { .id = 0, .type = unit_type };
    ILInstruction* ret_instr3 = il_build_return(unit_val3);
    ILBasicBlock* b3 = il_block_create(3);
    il_block_add_instr(b3, drop_instr);
    il_block_add_instr(b3, ret_instr3);

    il_block_add_successor(b1, b2);
    il_block_add_successor(b1, b3);

    const ILType * func_ret_type = il_type_unit();
    ILFunction* func = il_func_create_synthetic_with_params(1, (const ILType*[]){box_u32, bool_type}, 2, "test_func", func_ret_type);
    il_func_add_block(func, b1);
    il_func_add_block(func, b2);
    il_func_add_block(func, b3);

    il_func_auto_drop(NULL, func);
    VerificationResult res = verify_function(NULL, func);

    bool is_safe = res.is_safe;
    if (!is_safe) {
        for (uint32_t i = 0; i < res.error_count; i++) fprintf(stderr, "Error: %s\n", res.errors[i].message);
    }

    il_func_free(func);
    verify_result_free(&res);

    ASSERT(is_safe == true, "Move in sibling block should not affect this path");
    return true;
}

static bool test_leak_detected(void) {
    const ILType * u32_ty = il_type_u32();
    const ILType * unit_ty = il_type_unit();
    const ILType * box_u32 = il_type_box(u32_ty, REGION_LOCAL, true);

    ILInstruction* alloc = il_build_alloc(REGION_LOCAL, u32_ty, box_u32, (ILValue){0});
    alloc->result_id = 1;

    ILValue unit_val = { .id = 0, .type = unit_ty };
    ILInstruction* ret = il_build_return(unit_val);

    ILBasicBlock* b = il_block_create(1);
    il_block_add_instr(b, alloc);
    il_block_add_instr(b, ret);

    ILFunction* func = il_func_create_synthetic(1, "test_leak", unit_ty);
    il_func_add_block(func, b);

    // Note: We DO NOT call il_func_auto_drop here because we WANT to detect the leak.
    VerificationResult res = verify_function(NULL, func);
    bool is_safe = res.is_safe;
    bool found_leak = false;
    for (uint32_t i = 0; i < res.error_count; i++) {
        if (res.errors[i].type == VERIFY_ERR_LEAK) found_leak = true;
    }

    il_func_free(func);
    verify_result_free(&res);

    ASSERT(is_safe == false, "Verifier should detect a leak of a non-copy value");
    ASSERT(found_leak, "Expected leak error in verification results");
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);

    RUN_TEST(test_cross_block_use_after_move_rejected);
    RUN_TEST(test_sibling_block_move_accepted);
    RUN_TEST(test_leak_detected);

    printf("[%2d/%2d] Move semantics and ownership tracking\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
