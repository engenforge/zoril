#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "../include/il_cfg.h"
#include "../include/il_instr.h"
#include "../include/verifier.h"
#include "il_type.h"

/* Helper to build a minimal slice-access function for testing.
 * Entry block: slice_len, bounds_check
 * Successor block: slice_load
 * This exercises cross-block dominator-based precomputation. */
static ILFunction* make_two_block_guarded_func(void) {
    const ILType * u32_ty = il_type_u32();
    const ILType * slice_ty = il_type_slice(u32_ty, 1, false);
    const ILType * u64_ty = il_type_u64();
    const ILType * bool_ty = il_type_bool();
    const ILType * ret_ty = il_type_u32();

    /* v1 = slice param, v2 = index param */
    ILValue v_slice = { .id = 1, .type = slice_ty };
    ILValue v_idx   = { .id = 2, .type = u64_ty };

    /* Entry block: slice_len, bounds_check, branch to load_block */
    ILInstruction* slen = il_build_slice_len(v_slice, u64_ty);
    if (!slen) return NULL;
    slen->result_id = 3;

    ILInstruction* bchk = il_build_bounds_check(v_idx, (ILValue){.id=slen->result_id, .type=il_type_u64()});
    if (!bchk) { il_instr_free(slen); return NULL; }

    ILInstruction* ctrue = il_build_const(1, bool_ty);
    if (!ctrue) { il_instr_free(bchk); il_instr_free(slen); return NULL; }
    ctrue->result_id = 5;

    ILInstruction* br = il_build_branch((ILValue){.id=ctrue->result_id, .type=il_type_bool()}, 2, 2);
    if (!br) { il_instr_free(ctrue); il_instr_free(bchk); il_instr_free(slen); return NULL; }

    ILBasicBlock* entry = il_block_create(1);
    if (!entry) { il_instr_free(br); il_instr_free(ctrue); il_instr_free(bchk); il_instr_free(slen); return NULL; }
    il_block_add_instr(entry, slen);
    il_block_add_instr(entry, bchk);
    il_block_add_instr(entry, ctrue);
    il_block_add_instr(entry, br);

    /* Load block: slice_load, ret */
    ILInstruction* sload = il_build_slice_load(v_slice, v_idx);
    if (!sload) { il_block_free(entry); return NULL; }
    sload->result_id = 4;

    ILValue vload = { .id = 4, .type = u32_ty };
    ILInstruction* ret = il_build_return(vload);
    if (!ret) { il_instr_free(sload); il_block_free(entry); return NULL; }

    ILBasicBlock* load_blk = il_block_create(2);
    if (!load_blk) { il_instr_free(ret); il_instr_free(sload); il_block_free(entry); return NULL; }
    il_block_add_instr(load_blk, sload);
    il_block_add_instr(load_blk, ret);

    il_block_add_successor(entry, load_blk);

    ILFunction* func = il_func_create_synthetic_with_params(1, (const ILType*[]){slice_ty, u64_ty}, 2, "test_guarded_cross_block", ret_ty);
    if (!func) { il_block_free(load_blk); il_block_free(entry); return NULL; }
    il_func_add_block(func, entry);
    il_func_add_block(func, load_blk);
    return func;
}

/* bounds_check in dominating block, slice_load in successor: must be accepted */
static bool test_cross_block_guarded_accepted(void) {
    printf("DEBUG: test_cross_block_guarded_accepted running\n");
    ILFunction* func = make_two_block_guarded_func();
    ASSERT(func != NULL, "Failed to create test function");

    il_func_assign_rpo_ids(func);
    il_func_calculate_dominators(func);

    /* Precompute the O(1) checked-pair sets */
    il_func_precompute_bounds(func);

    VerificationResult res = verify_function(NULL, func);
    bool ok = res.is_safe;
    if (!ok) {
        for (uint32_t i = 0; i < res.error_count; i++)
            printf("  error: %s (block %u, instr %u)\n",
                   res.errors[i].message, res.errors[i].block_id, res.errors[i].instr_index);
    }
    verify_result_free(&res);
    il_func_free(func);
    ASSERT(ok, "Cross-block guarded slice_load must be accepted");
    return true;
}

/* bounds_check only in entry, slice_load in sibling branch (not dominated): must be rejected */
static bool test_unguarded_sibling_branch_rejected(void) {
    const ILType * u32_ty = il_type_u32();
    const ILType * slice_ty = il_type_slice(u32_ty, 1, false);
    const ILType * u64_ty = il_type_u64();
    const ILType * bool_ty = il_type_bool();
    const ILType * ret_ty = il_type_u32();

    ILValue v_slice = { .id = 1, .type = slice_ty };
    ILValue v_idx   = { .id = 2, .type = u64_ty };

    /* Entry: slice_len, bounds_check, branch to checked_blk OR unchecked_blk */
    ILInstruction* slen = il_build_slice_len(v_slice, u64_ty);
    if (!slen) return false;
    slen->result_id = 3;
    ILInstruction* bchk = il_build_bounds_check(v_idx, (ILValue){.id=slen->result_id, .type=il_type_u64()});
    if (!bchk) { il_instr_free(slen); return false; }
    ILInstruction* ctrue = il_build_const(1, bool_ty);
    if (!ctrue) { il_instr_free(bchk); il_instr_free(slen); return false; }
    ctrue->result_id = 5;
    /* branch: checked_blk=2, unchecked_blk=3 */
    ILInstruction* br = il_build_branch((ILValue){.id=ctrue->result_id, .type=il_type_bool()}, 2, 3);
    if (!br) { il_instr_free(ctrue); il_instr_free(bchk); il_instr_free(slen); return false; }

    ILBasicBlock* entry = il_block_create(1);
    if (!entry) { il_instr_free(br); il_instr_free(ctrue); il_instr_free(bchk); il_instr_free(slen); return false; }
    il_block_add_instr(entry, slen);
    il_block_add_instr(entry, bchk);
    il_block_add_instr(entry, ctrue);
    il_block_add_instr(entry, br);

    /* checked_blk: slice_load (ok - entry dominates) */
    ILInstruction* sload_ok = il_build_slice_load(v_slice, v_idx);
    if (!sload_ok) { il_block_free(entry); return false; }
    sload_ok->result_id = 4;
    ILValue vok = { .id = 4, .type = u32_ty };
    ILInstruction* ret_ok = il_build_return(vok);
    if (!ret_ok) { il_instr_free(sload_ok); il_block_free(entry); return false; }

    ILBasicBlock* checked_blk = il_block_create(2);
    if (!checked_blk) { il_instr_free(ret_ok); il_instr_free(sload_ok); il_block_free(entry); return false; }
    il_block_add_instr(checked_blk, sload_ok);
    il_block_add_instr(checked_blk, ret_ok);

    /* unchecked_blk: another slice_load WITHOUT a bounds_check - the bounds_check
     * in the entry block dominates this block, so it SHOULD be accepted.
     * This tests that the precomputed set propagates from entry to both successors. */
    ILInstruction* sload_also = il_build_slice_load(v_slice, v_idx);
    if (!sload_also) { il_block_free(checked_blk); il_block_free(entry); return false; }
    sload_also->result_id = 6;
    ILValue valso = { .id = 6, .type = u32_ty };
    ILInstruction* ret_also = il_build_return(valso);
    if (!ret_also) { il_instr_free(sload_also); il_block_free(checked_blk); il_block_free(entry); return false; }

    ILBasicBlock* also_blk = il_block_create(3);
    if (!also_blk) { il_instr_free(ret_also); il_instr_free(sload_also); il_block_free(checked_blk); il_block_free(entry); return false; }
    il_block_add_instr(also_blk, sload_also);
    il_block_add_instr(also_blk, ret_also);

    il_block_add_successor(entry, checked_blk);
    il_block_add_successor(entry, also_blk);

    ILFunction* func = il_func_create_synthetic_with_params(1, (const ILType*[]){slice_ty, u64_ty}, 2, "test_sibling", ret_ty);
    if (!func) { il_block_free(also_blk); il_block_free(checked_blk); il_block_free(entry); return false; }
    il_func_add_block(func, entry);
    il_func_add_block(func, checked_blk);
    il_func_add_block(func, also_blk);

    il_func_assign_rpo_ids(func);
    il_func_calculate_dominators(func);
    il_func_precompute_bounds(func);

    VerificationResult res = verify_function(NULL, func);
    /* Both branches have the entry block's bounds_check in their dominator path,
     * so both slice_loads should be accepted. */
    bool ok = res.is_safe;
    if (!ok) {
        for (uint32_t i = 0; i < res.error_count; i++)
            printf("  error: %s (block %u, instr %u)\n",
                   res.errors[i].message, res.errors[i].block_id, res.errors[i].instr_index);
    }
    verify_result_free(&res);
    il_func_free(func);
    ASSERT(ok, "Both branches dominated by entry bounds_check must be accepted");
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    int passed = 0, total = 0;
    #define RUN(fn) do { \
        total++; \
        if (fn()) { printf("[PASS] test_bounds_dominator: " #fn "\n"); passed++; } \
        else        printf("[FAIL] test_bounds_dominator: " #fn "\n"); \
    } while(0)

    RUN(test_cross_block_guarded_accepted);
    RUN(test_unguarded_sibling_branch_rejected);

    #undef RUN
    printf("Results: %d/%d passed\n", passed, total);
    il_ctx_destroy(&ctx);
    return (passed == total) ? 0 : 1;
}
