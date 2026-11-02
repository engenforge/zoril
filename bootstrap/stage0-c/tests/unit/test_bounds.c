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

static bool test_bounds_check_satisfied_accepted(void) {
    const ILType * u32_type = il_type_u32();
    const ILType * slice_u32 = il_type_slice(u32_type, 1, false);
    const ILType * u64_type = il_type_u64();

    ILValue v_slice = { .id = 1, .type = slice_u32 };
    ILValue v_idx = { .id = 2, .type = u64_type };

    ILInstruction* slen = il_build_slice_len(v_slice, u64_type);
    if (!slen) { return false; }
    slen->result_id = 3;

    ILInstruction* bchk = il_build_bounds_check(v_idx, (ILValue){.id=slen->result_id, .type=il_type_u64()});
    if (!bchk) { il_instr_free(slen); return false; }

    ILInstruction* sload = il_build_slice_load(v_slice, v_idx);
    if (!sload) { il_instr_free(bchk); il_instr_free(slen); return false; }

    ILBasicBlock* block = il_block_create(1);
    if (!block) { il_instr_free(sload); il_instr_free(bchk); il_instr_free(slen); return false; }
    il_block_add_instr(block, slen);
    il_block_add_instr(block, bchk);
    il_block_add_instr(block, sload);

    const ILType * ret_type = u32_type;
    ILFunction* func = il_func_create_synthetic(1, "test_func", ret_type);
    if (!func) { il_block_free(block); return false; }

    il_func_add_param(func, slice_u32); // v1
    il_func_add_param(func, u64_type);   // v2
    il_func_add_block(func, block);

    il_func_assign_rpo_ids(func);
    il_func_calculate_dominators(func);

    VerificationResult res = verify_function(NULL, func);

    bool success = true;
    if (res.is_safe != true) {
        fprintf(stderr, "[FAIL] %s:%d: Guarded slice access should be accepted\n", __FILE__, __LINE__);
        success = false;
        goto cleanup;
    }
    if (res.error_count != 0) {
        fprintf(stderr, "[FAIL] %s:%d: Should have 0 errors\n", __FILE__, __LINE__);
        success = false;
        goto cleanup;
    }

cleanup:
    il_func_free(func);
    verify_result_free(&res);
    return success;
}

static bool test_slice_store_satisfied_accepted(void) {
    const ILType * u32_type = NULL;
    const ILType * slice_u32 = NULL;
    const ILType * u64_type = NULL;
    ILValue v_slice = {0};
    ILValue v_idx = {0};
    ILValue v_val = {0};
    ILInstruction* slen = NULL;
    ILInstruction* bchk = NULL;
    ILInstruction* sstore = NULL;
    ILBasicBlock* block = NULL;
    ILFunction* func = NULL;
    VerificationResult res = {0};
    bool success = false;

    u32_type = il_type_u32();
    slice_u32 = il_type_slice(u32_type, 1, true);
    if (!slice_u32) goto cleanup;

    u64_type = il_type_u64();

    v_slice = (ILValue){ .id = 1, .type = slice_u32 };
    v_idx = (ILValue){ .id = 2, .type = u64_type };
    v_val = (ILValue){ .id = 4, .type = u32_type };

    slen = il_build_slice_len(v_slice, u64_type);
    if (!slen) goto cleanup;
    slen->result_id = 3;

    bchk = il_build_bounds_check(v_idx, (ILValue){.id=slen->result_id, .type=il_type_u64()});
    if (!bchk) goto cleanup;

    sstore = il_build_slice_store(v_slice, v_idx, v_val);
    if (!sstore) goto cleanup;

    ILInstruction* drop_slice = il_build_drop(v_slice);
    if (!drop_slice) goto cleanup;

    block = il_block_create(1);
    if (!block) { il_instr_free(drop_slice); goto cleanup; }
    il_block_add_instr(block, slen);
    il_block_add_instr(block, bchk);
    il_block_add_instr(block, sstore);
    il_block_add_instr(block, drop_slice);

    const ILType * ret_type = il_type_unit();
    // Parameters v1 (slice), v2 (index), v4 (value).
    func = il_func_create_synthetic(1, "test_func", ret_type);
    if (!func) { il_block_free(block); goto cleanup; }
    il_func_add_param(func, slice_u32); // v1
    il_func_add_param(func, u64_type);   // v2
    il_func_add_param(func, il_type_unit());           // v3 (unused)
    il_func_add_param(func, u32_type);   // v4
    il_func_add_block(func, block);

    il_func_assign_rpo_ids(func);
    il_func_calculate_dominators(func);

    res = verify_function(NULL, func);

    if (res.is_safe != true) {
        fprintf(stderr, "[FAIL] %s:%d: Guarded slice store should be accepted. Errors:\n", __FILE__, __LINE__);
        for (uint32_t i = 0; i < res.error_count; i++) {
            fprintf(stderr, "  %s at block %u, instr %u\n", res.errors[i].message, res.errors[i].block_id, res.errors[i].instr_index);
        }
        goto cleanup;
    }
    if (res.error_count != 0) {
        fprintf(stderr, "[FAIL] %s:%d: Should have 0 errors\n", __FILE__, __LINE__);
        goto cleanup;
    }
    success = true;

cleanup:
    if (func) il_func_free(func);
    else if (block) il_block_free(block);
    else {
        if (sstore) il_instr_free(sstore);
        if (bchk) il_instr_free(bchk);
        if (slen) il_instr_free(slen);
    }
    verify_result_free(&res);
    return success;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_bounds_check_satisfied_accepted);
    RUN_TEST(test_slice_store_satisfied_accepted);
    printf("[%2d/%2d] Slice and array bounds check verification\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
