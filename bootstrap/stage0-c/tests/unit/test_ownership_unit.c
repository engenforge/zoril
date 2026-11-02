#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "il_ownership.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_ownership_lifecycle(void) {
    OwnershipState* s = ownership_state_create(10);
    ASSERT(s != NULL, "Failed to create ownership state");
    
    ownership_set(s, 1, VAL_AVAILABLE);
    ASSERT(ownership_get(s, 1) == VAL_AVAILABLE, "Status mismatch");

    ownership_state_free(s);
    return true;
}

static bool test_ownership_merge(void) {
    OwnershipState* s1 = ownership_state_create(10);
    OwnershipState* s2 = ownership_state_create(10);
    
    ownership_set(s1, 1, VAL_AVAILABLE);
    ownership_set(s2, 1, VAL_AVAILABLE);
    
    ownership_state_merge(s1, s2);
    ASSERT(ownership_get(s1, 1) == VAL_AVAILABLE, "Merge should preserve status");

    ownership_state_free(s1);
    ownership_state_free(s2);
    return true;
}

static bool test_ownership_copy(void) {
    OwnershipState* s1 = ownership_state_create(10);
    ownership_set(s1, 1, VAL_AVAILABLE);
    
    OwnershipState* s2 = ownership_state_copy(s1);
    ASSERT(ownership_get(s2, 1) == VAL_AVAILABLE, "Copy failed");

    ownership_state_free(s1);
    ownership_state_free(s2);
    return true;
}

static bool test_ownership_analysis(void) {
    ILType i32_ty = { .kind = IL_TY_I32 };
    const ILType * box_ty = il_type_box(&i32_ty, REGION_HEAP, true);
    const ILType * ret_ty = box_ty;
    ILFunction* func = il_func_create_synthetic(1, "test", ret_ty);
    
    ILBasicBlock* b1 = il_block_create(1);
    ILBasicBlock* b2 = il_block_create(2);
    il_func_add_block(func, b1);
    il_func_add_block(func, b2);
    il_block_add_successor(b1, b2);
    
    // b1:
    // %1 = alloc i32
    // %2 = move %1
    ILInstruction* c1 = il_build_alloc(REGION_HEAP, &i32_ty, box_ty, (ILValue){0});
    c1->result_id = 1; // Overwrite default 0
    il_block_add_instr(b1, c1);
    
    ILValue v1 = { .id = 1, .type = box_ty };
    ILInstruction* m1 = il_build_move(v1);
    m1->result_id = 2;
    il_block_add_instr(b1, m1);
    
    il_func_assign_rpo_ids(func);
    
    OwnershipAnalysisResult res = il_func_analyze_ownership(NULL, func);
    ASSERT(res.states != NULL, "Analysis failed");
    
    uint32_t b2_rpo = 0;
    for (uint32_t i = 0; i < func->block_count; i++) {
        if (func->blocks[i]->id == 2) b2_rpo = i;
    }

    ASSERT(ownership_get(res.states[b2_rpo], 1) == VAL_MOVED, "Value 1 should be MOVED in b2 entry");
    ASSERT(ownership_get(res.states[b2_rpo], 2) == VAL_AVAILABLE, "Value 2 should be AVAILABLE in b2 entry");

    il_func_ownership_result_free(res, func->block_count);
    il_func_free(func);
    
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_ownership_lifecycle);
    RUN_TEST(test_ownership_merge);
    RUN_TEST(test_ownership_copy);
    RUN_TEST(test_ownership_analysis);
    printf("[%2d/%2d] IL ownership state management\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return tests_passed == tests_run ? 0 : 1;
}
