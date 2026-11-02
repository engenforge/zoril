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

static bool test_fd_leak_rejected(void) {
    const ILType* fd_ty = il_type_fd(IL_CAP_RW);
    const ILType* unit_ty = il_type_unit();

    ILBasicBlock* block = il_block_create(0);
    
    // v1 = fd_open(...)
    ILInstruction* open = il_build_fd_open((ILValue){0}, (ILValue){0}, (ILValue){0}, fd_ty);
    open->result_id = 1;
    open->result_type = fd_ty;
    il_block_add_instr(block, open);

    // return unit (v1 is leaked!)
    ILInstruction* ret = il_build_return((ILValue){.id = 0, .type = unit_ty});
    il_block_add_instr(block, ret);

    ILFunction* func = il_func_create_synthetic(1, "test_leak", unit_ty);
    il_func_add_block(func, block);
    func->entry_block = block;

    ILModule* dummy_mod = il_mod_create();
    VerificationResult res = verify_function(dummy_mod, func);

    bool has_leak_err = false;
    for (uint32_t i = 0; i < res.error_count; i++) {
        if (res.errors[i].type == VERIFY_ERR_LEAK) { has_leak_err = true; break; }
    }

    il_func_free(func);
    verify_result_free(&res);
    il_mod_free(dummy_mod);

    ASSERT(has_leak_err, "FD leak should be rejected with VERIFY_ERR_LEAK");
    return true;
}

static bool test_fd_drop_rejected(void) {
    const ILType* fd_ty = il_type_fd(IL_CAP_RW);
    const ILType* unit_ty = il_type_unit();

    ILBasicBlock* block = il_block_create(0);
    
    // v1 = fd_open(...)
    ILInstruction* open = il_build_fd_open((ILValue){0}, (ILValue){0}, (ILValue){0}, fd_ty);
    open->result_id = 1;
    open->result_type = fd_ty;
    il_block_add_instr(block, open);

    // drop(v1) -- forbidden for linear resources
    ILInstruction* drop = il_build_drop((ILValue){.id = 1, .type = fd_ty});
    il_block_add_instr(block, drop);

    // return unit
    ILInstruction* ret = il_build_return((ILValue){.id = 0, .type = unit_ty});
    il_block_add_instr(block, ret);

    ILFunction* func = il_func_create_synthetic(1, "test_drop", unit_ty);
    il_func_add_block(func, block);
    func->entry_block = block;

    ILModule* dummy_mod = il_mod_create();
    VerificationResult res = verify_function(dummy_mod, func);

    bool has_leak_err = false;
    for (uint32_t i = 0; i < res.error_count; i++) {
        if (res.errors[i].type == VERIFY_ERR_LEAK && strstr(res.errors[i].message, "must be explicitly closed, not dropped")) {
            has_leak_err = true; break;
        }
    }

    il_func_free(func);
    verify_result_free(&res);
    il_mod_free(dummy_mod);

    ASSERT(has_leak_err, "FD drop should be rejected with error about explicit close");
    return true;
}

static bool test_fd_proper_close_accepted(void) {
    const ILType* fd_ty = il_type_fd(IL_CAP_RW);
    const ILType* unit_ty = il_type_unit();

    ILBasicBlock* block = il_block_create(0);
    
    // v1 = fd_open(...)
    ILInstruction* open = il_build_fd_open((ILValue){0}, (ILValue){0}, (ILValue){0}, fd_ty);
    open->result_id = 1;
    open->result_type = fd_ty;
    il_block_add_instr(block, open);

    // fd_close(v1)
    ILInstruction* close = il_build_fd_close((ILValue){.id = 1, .type = fd_ty});
    il_block_add_instr(block, close);

    // return unit
    ILInstruction* ret = il_build_return((ILValue){.id = 0, .type = unit_ty});
    il_block_add_instr(block, ret);

    ILFunction* func = il_func_create_synthetic(1, "test_ok", unit_ty);
    il_func_add_block(func, block);
    func->entry_block = block;

    ILModule* dummy_mod = il_mod_create();
    VerificationResult res = verify_function(dummy_mod, func);

    bool safe = res.is_safe;
    if (!safe) {
        for (uint32_t i = 0; i < res.error_count; i++) {
            fprintf(stderr, "Unexpected error: %s\n", res.errors[i].message);
        }
    }

    il_func_free(func);
    verify_result_free(&res);
    il_mod_free(dummy_mod);

    ASSERT(safe, "Properly closed FD should be accepted");
    return true;
}

static bool test_async_leak_rejected(void) {
    const ILType* ctx_ty = il_type_async_context();
    const ILType* unit_ty = il_type_unit();

    ILBasicBlock* block = il_block_create(0);
    
    // v1 = async_setup(...)
    ILInstruction* open = il_build_async_setup((ILValue){0}, ctx_ty);
    open->result_id = 1;
    open->result_type = ctx_ty;
    il_block_add_instr(block, open);

    // return unit (v1 is leaked!)
    ILInstruction* ret = il_build_return((ILValue){.id = 0, .type = unit_ty});
    il_block_add_instr(block, ret);

    ILFunction* func = il_func_create_synthetic(1, "test_leak_async", unit_ty);
    il_func_add_block(func, block);
    func->entry_block = block;

    ILModule* dummy_mod = il_mod_create();
    VerificationResult res = verify_function(dummy_mod, func);

    bool has_leak_err = false;
    for (uint32_t i = 0; i < res.error_count; i++) {
        if (res.errors[i].type == VERIFY_ERR_LEAK) { has_leak_err = true; break; }
    }

    il_func_free(func);
    verify_result_free(&res);
    il_mod_free(dummy_mod);

    ASSERT(has_leak_err, "Async context leak should be rejected");
    return true;
}

static bool test_async_drop_rejected(void) {
    const ILType* ctx_ty = il_type_async_context();
    const ILType* unit_ty = il_type_unit();

    ILBasicBlock* block = il_block_create(0);
    
    // v1 = async_setup(...)
    ILInstruction* open = il_build_async_setup((ILValue){0}, ctx_ty);
    open->result_id = 1;
    open->result_type = ctx_ty;
    il_block_add_instr(block, open);

    // drop(v1)
    ILInstruction* drop = il_build_drop((ILValue){.id = 1, .type = ctx_ty});
    il_block_add_instr(block, drop);

    // return unit
    ILInstruction* ret = il_build_return((ILValue){.id = 0, .type = unit_ty});
    il_block_add_instr(block, ret);

    ILFunction* func = il_func_create_synthetic(1, "test_drop_async", unit_ty);
    il_func_add_block(func, block);
    func->entry_block = block;

    ILModule* dummy_mod = il_mod_create();
    VerificationResult res = verify_function(dummy_mod, func);

    bool has_err = false;
    for (uint32_t i = 0; i < res.error_count; i++) {
        if (res.errors[i].type == VERIFY_ERR_LEAK && strstr(res.errors[i].message, "must be explicitly closed, not dropped")) {
            has_err = true; break;
        }
    }

    il_func_free(func);
    verify_result_free(&res);
    il_mod_free(dummy_mod);

    ASSERT(has_err, "Async context drop should be rejected");
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_fd_leak_rejected);
    RUN_TEST(test_fd_drop_rejected);
    RUN_TEST(test_fd_proper_close_accepted);
    RUN_TEST(test_async_leak_rejected);
    RUN_TEST(test_async_drop_rejected);
    return 0;
}
