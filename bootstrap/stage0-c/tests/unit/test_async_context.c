#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "../include/il_cfg.h"
#include "../include/il_type.h"
#include "../include/il_instr.h"
#include "../include/il_read.h"
#include "../include/verifier.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

/* async_context is NOT a copy type (linear resource) */
static bool test_async_context_type_not_copy(void) {
    const ILType * ring_ty = il_type_async_context();
    ASSERT(ring_ty != NULL, "async_context type should be created");
    bool not_copy = !il_type_is_copy(ring_ty);
    
    ASSERT(not_copy, "async_context type must not be copy (it is a linear resource)");
    return true;
}

/* Test that the C API builders produce correct instructions */
static bool test_async_context_builders(void) {
    const ILType * ring_ty = il_type_async_context();         ABORT_IF_NULL(ring_ty);
    const ILType * i64_ty  = il_type_i64(); ABORT_IF_NULL(i64_ty);
    const ILType * u32_ty  = il_type_u32(); ABORT_IF_NULL(u32_ty);

    ILValue entries = { .id = 1, .type = u32_ty  };
    ILValue ring_v  = { .id = 2, .type = ring_ty };
    ILValue n       = { .id = 3, .type = u32_ty  };

    ILInstruction* setup_i = il_build_async_setup(entries, ring_ty);
    ILInstruction* enter_i = il_build_async_enter(ring_v, n, n, i64_ty);
    ILInstruction* close_i = il_build_async_close(ring_v);

    ASSERT(setup_i != NULL, "async_setup builder should succeed");
    ASSERT(enter_i != NULL, "async_enter builder should succeed");
    ASSERT(close_i != NULL, "async_close builder should succeed");

    ASSERT(setup_i->opcode == IL_OP_ASYNC_SETUP, "async_setup opcode");
    ASSERT(enter_i->opcode == IL_OP_ASYNC_ENTER, "async_enter opcode");
    ASSERT(close_i->opcode == IL_OP_ASYNC_CLOSE, "async_close opcode");

    ASSERT(setup_i->result_type->kind == IL_TY_ASYNC_CONTEXT, "async_setup result type");
    ASSERT(enter_i->result_type->kind == IL_TY_I64,     "async_enter result type");

    il_instr_free(setup_i);
    il_instr_free(enter_i);
    il_instr_free(close_i);
    
    return true;
}

/* async_setup → async_close: must be safe */
static bool test_async_setup_and_close(void) {
    const char* il =
        "f0: unit async_lifecycle(entries: u32) {\n"
        "  @b0:\n"
        "    v2: async_context = async_setup v1\n"
        "    async_close v2\n"
        "    ret\n"
        "}\n";

    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should parse async_setup/close function");

    VerificationResult res = verify_module(mod);
    if (!res.is_safe) {
        for (uint32_t i = 0; i < res.error_count; i++)
            printf("  error: %s\n", res.errors[i].message);
    }
    bool ok = res.is_safe;
    verify_result_free(&res);
    il_mod_free(mod);
    ASSERT(ok, "async_setup + async_close must be safe");
    return true;
}

/* Full cycle: setup → enter (borrow) → close → ret: must be safe */
static bool test_async_full_cycle(void) {
    const char* il =
        "f0: i64 async_cycle(entries: u32, n: u32) {\n"
        "  @b0:\n"
        "    v3: async_context = async_setup v1\n"
        "    v4: i64 = async_enter v3, v2, v2\n"
        "    async_close v3\n"
        "    ret v4\n"
        "}\n";

    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should parse full async cycle function");

    VerificationResult res = verify_module(mod);
    if (!res.is_safe) {
        for (uint32_t i = 0; i < res.error_count; i++)
            printf("  error: %s\n", res.errors[i].message);
    }
    bool ok = res.is_safe;
    verify_result_free(&res);
    il_mod_free(mod);
    ASSERT(ok, "Full async cycle must be safe");
    return true;
}

/* async_setup without close: verifier must REJECT the leak */
static bool test_async_leak_rejected(void) {
    const char* il =
        "f0: unit async_leak(entries: u32) {\n"
        "  @b0:\n"
        "    v2: async_context = async_setup v1\n"
        "    ret\n"
        "}\n";

    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should parse leaking async function");

    VerificationResult res = verify_module(mod);
    bool ok = !res.is_safe;
    verify_result_free(&res);
    il_mod_free(mod);
    ASSERT(ok, "async_setup without close must be rejected by verifier");
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_async_context_type_not_copy);
    RUN_TEST(test_async_context_builders);
    RUN_TEST(test_async_setup_and_close);
    RUN_TEST(test_async_full_cycle);
    RUN_TEST(test_async_leak_rejected);

    printf("Results: %d/%d passed\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_passed == tests_run) ? 0 : 1;
}
