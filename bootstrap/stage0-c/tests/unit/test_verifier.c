#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "il_type.h"
#include "il_instr.h"
#include "il_cfg.h"
#include "verifier.h"

int tests_run = 0;
int tests_passed = 0;


static bool test_store_type_mismatch_rejected(void) {
    const ILType * u32_type = il_type_u32();
    const ILType * u64_type = il_type_u64();
    const ILType * ptr_u32 = il_type_ptr(u32_type, 1, true);

    ILValue v_ptr = { .id = 1, .type = ptr_u32 };
    ILValue v_val = { .id = 2, .type = u64_type }; // Mismatch: u64 into PtrMut<u32>
    
    ILInstruction* store = calloc(1, sizeof(ILInstruction));
    if (!store) {   return false; }
    store->opcode = IL_OP_STORE;
    store->operands.store.ptr = v_ptr.id;
    store->operands.store.value = v_val.id;

    const ILType * unit_type = il_type_unit();
    store->result_type = unit_type;

    ILBasicBlock* block = il_block_create(1);
    if (!block) { il_instr_free(store);   return false; }
    il_block_add_instr(block, store);

    const ILType * func_ret_type = il_type_unit();
    ILFunction* func = il_func_create_synthetic_with_params(1, (const ILType*[]){ptr_u32, u64_type}, 2, "test_func", func_ret_type);
    if (!func) { il_block_free(block);   return false; }
    
    il_func_add_block(func, block);

    VerificationResult res = verify_function(NULL, func);

    bool is_rejected = !res.is_safe;
    bool has_mismatch_err = false;
    for (uint32_t i = 0; i < res.error_count; i++) {
        if (res.errors[i].type == VERIFY_ERR_TYPE_MISMATCH) { has_mismatch_err = true; break; }
    }

    il_func_free(func);
    
    verify_result_free(&res);

    ASSERT(is_rejected, "Store mismatch should be rejected");
    ASSERT(has_mismatch_err, "Should have type mismatch error");
    return true;
}

static bool test_return_type_mismatch_rejected(void) {
    const ILType * u32_type = il_type_u32();
    const ILType * u64_type = il_type_u64();

    ILValue v_val = { .id = 1, .type = u64_type };
    
    ILInstruction* ret_instr = calloc(1, sizeof(ILInstruction));
    if (!ret_instr) {   return false; }
    ret_instr->opcode = IL_OP_RETURN;
    ret_instr->operands.ret.value = v_val.id;

    const ILType * unit_type = il_type_unit();
    ret_instr->result_type = unit_type;

    ILBasicBlock* block = il_block_create(1);
    if (!block) { il_instr_free(ret_instr);   return false; }
    il_block_add_instr(block, ret_instr);

    // Function expects u32, but returns u64
    ILFunction* func = il_func_create_synthetic_with_params(1, (const ILType*[]){u64_type}, 1, "test_func", u32_type);
    if (!func) { il_block_free(block);   return false; }
    
    il_func_add_block(func, block);

    VerificationResult res = verify_function(NULL, func);

    bool is_rejected = !res.is_safe;
    bool has_mismatch_err = false;
    for (uint32_t i = 0; i < res.error_count; i++) {
        if (res.errors[i].type == VERIFY_ERR_TYPE_MISMATCH) { has_mismatch_err = true; break; }
    }

    il_func_free(func);
    
    verify_result_free(&res);

    ASSERT(is_rejected, "Return mismatch should be rejected");
    ASSERT(has_mismatch_err, "Should have type mismatch error");
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_store_type_mismatch_rejected);
    RUN_TEST(test_return_type_mismatch_rejected);

    printf("[%2d/%2d] Basic verifier compatibility checks\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
