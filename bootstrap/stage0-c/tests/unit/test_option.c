#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include "test_harness.h"
#include "il_type.h"
#include "il_instr.h"
#include "il_cfg.h"
#include "verifier.h"

int tests_run = 0;
int tests_passed = 0;

static const ILType* get_option_u32_type(void) {
    static const ILType* ty = NULL;
    if (!ty) ty = il_type_sum("Option", 1);
    return ty;
}

static bool test_unguarded_unwrap_rejected(void) {
    const ILType * u32_type = il_type_u32();
    const ILType * option_u32 = get_option_u32_type();

    ILValue v_opt = { .id = 1, .type = option_u32 };
    
    ILInstruction* unwrap = il_build_unwrap(v_opt, u32_type);
    ABORT_IF_NULL(unwrap);
    unwrap->result_id = 2;

    ILBasicBlock* block = il_block_create(1);
    ABORT_IF_NULL(block);
    il_block_add_instr(block, unwrap);

    const ILType * unit_ret = il_type_unit();
    ILFunction* func = il_func_create_synthetic_with_params(1, (const ILType*[]){option_u32}, 1, "test_func", unit_ret);
    ABORT_IF_NULL(func);
    
    il_func_add_block(func, block);

    il_func_assign_rpo_ids(func);
    il_func_calculate_dominators(func);
    VerificationResult res = verify_function(NULL, func);

    bool is_safe = res.is_safe;
    bool found_err = false;
    for (uint32_t i = 0; i < res.error_count; i++) {
        if (res.errors[i].type == VERIFY_ERR_UNHANDLED_OPTION) {
            found_err = true;
            break;
        }
    }

    il_func_free(func);
    verify_result_free(&res);

    ASSERT(is_safe == false, "Unguarded unwrap should be rejected");
    ASSERT(found_err, "Should have unguarded-unwrap error");
    return true;
}

static bool test_guarded_unwrap_accepted(void) {
    const ILType * u32_type = il_type_u32();
    const ILType * option_u32 = get_option_u32_type();
    const ILType * bool_type = il_type_bool();

    ILValue v_opt = { .id = 1, .type = option_u32 };
    
    ILInstruction* is_some = il_build_is_some(v_opt, bool_type);
    ABORT_IF_NULL(is_some);
    is_some->result_id = 10;
    ILValue v_cond = { .id = 10, .type = bool_type };
    ILInstruction* branch = il_build_branch(v_cond, 2, 3);
    ABORT_IF_NULL(branch);
    
    ILBasicBlock* b1 = il_block_create(1);
    ABORT_IF_NULL(b1);
    il_block_add_instr(b1, is_some);
    il_block_add_instr(b1, branch);

    ILInstruction* unwrap = il_build_unwrap(v_opt, u32_type);
    ABORT_IF_NULL(unwrap);
    unwrap->result_id = 11;
    const ILType * unit_type = il_type_unit();
    ILValue unit_val = { .id = 0, .type = unit_type };
    ILInstruction* ret2 = il_build_return(unit_val);
    ABORT_IF_NULL(ret2);

    ILBasicBlock* b2 = il_block_create(2);
    ABORT_IF_NULL(b2);
    il_block_add_instr(b2, unwrap);
    il_block_add_instr(b2, ret2);

    ILInstruction* ret3 = il_build_return(unit_val);
    ABORT_IF_NULL(ret3);
    ILBasicBlock* b3 = il_block_create(3);
    ABORT_IF_NULL(b3);
    il_block_add_instr(b3, il_build_drop(v_opt));
    il_block_add_instr(b3, ret3);

    ILFunction* func = il_func_create_synthetic_with_params(1, (const ILType*[]){option_u32}, 1, "test_func", unit_type);
    ABORT_IF_NULL(func);
    il_func_add_block(func, b1);
    il_func_add_block(func, b2);
    il_func_add_block(func, b3);
    il_block_add_successor(b1, b2);
    il_block_add_successor(b1, b3);

    il_func_assign_rpo_ids(func);
    il_func_calculate_dominators(func);
    VerificationResult res = verify_function(NULL, func);
    bool is_safe = res.is_safe;
    if (!is_safe) {
        for (uint32_t i = 0; i < res.error_count; i++) {
            fprintf(stderr, "Error: %s\n", res.errors[i].message);
        }
    }
    il_func_free(func);
    verify_result_free(&res);

    ASSERT(is_safe == true, "Guarded unwrap should be accepted");
    return true;
}

static bool test_unwrap_after_reassign_rejected(void) {
    const ILType * u32_type = il_type_u32();
    const ILType * option_u32 = get_option_u32_type();
    const ILType * bool_type = il_type_bool();
    const ILType * unit_type = il_type_unit();

    ILValue v_opt = { .id = 1, .type = option_u32 };
    ILInstruction* is_some = il_build_is_some(v_opt, bool_type);
    is_some->result_id = 10;
    ILValue v_cond = { .id = 10, .type = bool_type };
    ILInstruction* branch = il_build_branch(v_cond, 2, 3);
    
    ILBasicBlock* b1 = il_block_create(1);
    il_block_add_instr(b1, is_some);
    il_block_add_instr(b1, branch);

    ILValue v_opt_new = { .id = 12, .type = option_u32 };
    ILInstruction* unwrap = il_build_unwrap(v_opt_new, u32_type);
    unwrap->result_id = 11;

    ILBasicBlock* b2 = il_block_create(2);
    il_block_add_instr(b2, unwrap);
    il_block_add_instr(b2, il_build_return((ILValue){0, unit_type}));

    ILBasicBlock* b3 = il_block_create(3);
    il_block_add_instr(b3, il_build_return((ILValue){0, unit_type}));

    ILFunction* func = il_func_create_synthetic_with_params(1, (const ILType*[]){option_u32, option_u32}, 2, "test_func", unit_type);
    il_func_add_block(func, b1);
    il_func_add_block(func, b2);
    il_func_add_block(func, b3);
    il_block_add_successor(b1, b2);
    il_block_add_successor(b1, b3);

    il_func_assign_rpo_ids(func);
    il_func_calculate_dominators(func);
    VerificationResult res = verify_function(NULL, func);
    bool is_safe = res.is_safe;
    il_func_free(func);
    verify_result_free(&res);

    ASSERT(is_safe == false, "Unwrap of different SSA ID should be rejected");
    return true;
}

static bool test_nested_guards(void) {
    const ILType * u32_type = il_type_u32();
    const ILType * option_u32 = get_option_u32_type();
    const ILType * bool_type = il_type_bool();
    const ILType * unit_type = il_type_unit();

    ILValue v_opt = { .id = 1, .type = option_u32 };
    ILInstruction* is_some = il_build_is_some(v_opt, bool_type);
    is_some->result_id = 10;
    ILInstruction* branch = il_build_branch((ILValue){10, bool_type}, 2, 4);

    ILBasicBlock* b1 = il_block_create(1);
    il_block_add_instr(b1, is_some);
    il_block_add_instr(b1, branch);

    ILBasicBlock* b2 = il_block_create(2);
    il_block_add_instr(b2, il_build_jump(3));

    ILBasicBlock* b3 = il_block_create(3);
    ILInstruction* unwrap = il_build_unwrap(v_opt, u32_type);
    unwrap->result_id = 11;
    il_block_add_instr(b3, unwrap);
    il_block_add_instr(b3, il_build_return((ILValue){0, unit_type}));

    ILBasicBlock* b4 = il_block_create(4);
    il_block_add_instr(b4, il_build_drop(v_opt));
    il_block_add_instr(b4, il_build_return((ILValue){0, unit_type}));

    ILFunction* func = il_func_create_synthetic_with_params(1, (const ILType*[]){option_u32}, 1, "test_func", unit_type);
    il_func_add_block(func, b1);
    il_func_add_block(func, b2);
    il_func_add_block(func, b3);
    il_func_add_block(func, b4);
    il_block_add_successor(b1, b2);
    il_block_add_successor(b1, b4);
    il_block_add_successor(b2, b3);

    il_func_assign_rpo_ids(func);
    il_func_calculate_dominators(func);
    VerificationResult res = verify_function(NULL, func);
    bool is_safe = res.is_safe;
    if (!is_safe) {
        for (uint32_t i = 0; i < res.error_count; i++) fprintf(stderr, "Error: %s\n", res.errors[i].message);
    }
    il_func_free(func);
    verify_result_free(&res);

    ASSERT(is_safe == true, "Nested guarded unwrap should be accepted");
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_unguarded_unwrap_rejected);
    RUN_TEST(test_guarded_unwrap_accepted);
    RUN_TEST(test_unwrap_after_reassign_rejected);
    RUN_TEST(test_nested_guards);

    printf("[%2d/%2d] Option/Sum type safety\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
