#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include "il_type.h"
#include "il_cfg.h"
#include "il_instr.h"
#include "verifier.h"
#include "test_harness.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_ptr_mut_assignability(void) {
    const ILType * u32_ty = il_type_u32();

    const ILType * ptr_mut = il_type_ptr(u32_ty, REGION_LOCAL, true);
    const ILType * ptr_imm = il_type_ptr(u32_ty, REGION_LOCAL, false);

    ASSERT(il_type_is_assignable(ptr_mut, ptr_imm), "Mut to Imm should be assignable");
    ASSERT(!il_type_is_assignable(ptr_imm, ptr_mut), "Imm to Mut should NOT be assignable");

    return true;
}

static bool test_store_mut_check(void) {
    ILModule* mod = il_mod_create();
    const ILType * u32_ty = il_type_u32();

    const ILType * ptr_mut_ty = il_type_ptr(u32_ty, REGION_LOCAL, true);
    const ILType * ptr_imm_ty = il_type_ptr(u32_ty, REGION_LOCAL, false);

    ILFunction* func = il_func_create_synthetic(0, "test_store", il_type_unit());
    il_func_add_param(func, ptr_mut_ty);
    il_func_add_param(func, ptr_imm_ty);
    il_func_add_param(func, u32_ty); // v3
    il_mod_add_func(mod, func);

    ILBasicBlock* block = il_block_create(0);
    il_func_add_block(func, block);

    ILValue v_val = { .id = 3, .type = u32_ty }; 
    ILValue v_ptr_mut = { .id = 1, .type = ptr_mut_ty };
    ILValue v_ptr_imm = { .id = 2, .type = ptr_imm_ty };

    // Valid store
    il_block_add_instr(block, il_build_store(v_ptr_mut, v_val));
    VerificationResult res1 = verify_module(mod);
    ASSERT(res1.is_safe, "Store to mut pointer should be safe");
    verify_result_free(&res1);

    // Invalid store
    il_block_add_instr(block, il_build_store(v_ptr_imm, v_val));
    VerificationResult res2 = verify_module(mod);
    ASSERT(!res2.is_safe, "Store to imm pointer should NOT be safe");
    // Check error message
    bool found_error = false;
    for (uint32_t i = 0; i < res2.error_count; i++) {
        if (strstr(res2.errors[i].message, "immutable")) {
            found_error = true;
            break;
        }
    }
    ASSERT(found_error, "Should report error about immutable pointer");
    verify_result_free(&res2);

    il_mod_free(mod);
    
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_ptr_mut_assignability);
    RUN_TEST(test_store_mut_check);
    printf("[%2d/%2d] Mut Borrows (&mut T) IL Verification\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
