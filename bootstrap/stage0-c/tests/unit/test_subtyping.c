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

static bool test_static_to_local_assignment_accepted(void) {
    const ILType * u32_ty = il_type_u32();

    const ILType * local_ptr_ty = il_type_ptr(u32_ty, REGION_LOCAL, true);
    const ILType * static_ptr_ty = il_type_ptr(u32_ty, REGION_STATIC, true);
    const ILType * ptr_to_local_ptr_ty = il_type_ptr(local_ptr_ty, REGION_LOCAL, true);

    ILFunction* func = il_func_create_synthetic_with_params(1, (const ILType*[]){static_ptr_ty, local_ptr_ty, u32_ty}, 3, "test", u32_ty);
    ILBasicBlock* b = il_block_create(1);

    ILInstruction* alloc = il_build_alloc(REGION_LOCAL, local_ptr_ty, ptr_to_local_ptr_ty, (ILValue){0});
    alloc->result_id = 4;
    il_block_add_instr(b, alloc);
    
    ILValue static_val = { .id = 1, .type = static_ptr_ty };
    ILInstruction* store = il_build_store((ILValue){.id=alloc->result_id, .type=ptr_to_local_ptr_ty}, static_val);
    il_block_add_instr(b, store);
    
    ILValue ret_val = { .id = 3, .type = u32_ty };
    ILInstruction* ret = il_build_return(ret_val);
    il_block_add_instr(b, ret);
    
    il_func_add_block(func, b);
    ILModule* mod = il_mod_create();
    il_mod_add_func(mod, func);
    
    il_func_auto_drop(NULL, func);
    VerificationResult res = verify_module(mod);
    bool success = res.is_safe;
    if (!success) fprintf(stderr, "[FAIL] %s:%d: Static-to-local pointer assignment should be accepted\n", __FILE__, __LINE__);
    
    verify_result_free(&res);
    il_mod_free(mod);
    
    
    
    

    return success;
}

static bool test_local_to_static_assignment_rejected(void) {
    const ILType * u32_ty = il_type_u32();

    const ILType * local_ptr_ty = il_type_ptr(u32_ty, REGION_LOCAL, true);
    const ILType * static_ptr_ty = il_type_ptr(u32_ty, REGION_STATIC, true);
    const ILType * ptr_to_static_ptr_ty = il_type_ptr(static_ptr_ty, REGION_LOCAL, true);

    ILFunction* func = il_func_create_synthetic_with_params(1, (const ILType*[]){static_ptr_ty, local_ptr_ty, u32_ty}, 3, "test", u32_ty);
    ILBasicBlock* b = il_block_create(1);

    ILInstruction* alloc = il_build_alloc(REGION_LOCAL, static_ptr_ty, ptr_to_static_ptr_ty, (ILValue){0});
    alloc->result_id = 4;
    il_block_add_instr(b, alloc);
    
    ILValue local_val = { .id = 2, .type = local_ptr_ty };
    const ILInstruction* store = il_build_store((ILValue){.id=alloc->result_id, .type=ptr_to_static_ptr_ty}, local_val);
    bool builder_rejected = (store == NULL);
    
    ILValue ret_val = { .id = 3, .type = u32_ty };
    ILInstruction* ret = il_build_return(ret_val);
    il_block_add_instr(b, ret);
    
    il_func_add_block(func, b);
    ILModule* mod = il_mod_create();
    il_mod_add_func(mod, func);
    
    il_func_auto_drop(NULL, func);
    VerificationResult res = verify_module(mod);
    bool success = builder_rejected && res.is_safe;
    if (!builder_rejected) fprintf(stderr, "[FAIL] %s:%d: Local-to-static pointer assignment should be rejected by builder\n", __FILE__, __LINE__);
    if (!res.is_safe) fprintf(stderr, "[FAIL] %s:%d: Module should be safe if builder prevented the bad store\n", __FILE__, __LINE__);
    
    verify_result_free(&res);
    il_mod_free(mod);
    
    
    
    

    return success;
}

static bool test_region_cast_accepted(void) {
    const ILType * u32_ty = il_type_u32();

    const ILType * unit_ty = il_type_unit();

    const ILType * static_ptr_ty = il_type_ptr(u32_ty, REGION_STATIC, true);
    
    ILInstruction* alloc1 = il_build_alloc(REGION_STATIC, u32_ty, static_ptr_ty, (ILValue){0});
    alloc1->result_id = 1;

    ILValue static_val = { .id = 1, .type = static_ptr_ty };

    ILFunction* func = il_func_create_synthetic_with_params(1, (const ILType*[]){static_ptr_ty}, 1, "test", unit_ty);
    ILBasicBlock* b = il_block_create(1);
    
    il_block_add_instr(b, alloc1);

    ILInstruction* cast = il_build_region_cast(static_val, REGION_LOCAL);
    cast->result_id = 2;
    il_block_add_instr(b, cast);
    
    ILInstruction* ret = il_build_return((ILValue){.id = 0, .type = unit_ty});
    il_block_add_instr(b, ret);
    
    il_func_add_block(func, b);
    ILModule* mod = il_mod_create();
    il_mod_add_func(mod, func);
    
    il_func_auto_drop(NULL, func);
    VerificationResult res = verify_module(mod);
    bool is_safe = res.is_safe;
    if (!is_safe) {
        for (uint32_t i = 0; i < res.error_count; i++) {
            fprintf(stderr, "Verification error: %s\n", res.errors[i].message);
        }
    }
    verify_result_free(&res);
    il_mod_free(mod);
    
    
    

    return is_safe;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_static_to_local_assignment_accepted);
    RUN_TEST(test_local_to_static_assignment_rejected);
    RUN_TEST(test_region_cast_accepted);
    printf("[%2d/%2d] Region subtyping and assignability\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
