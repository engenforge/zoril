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

/* fd<r> as a parameter, fd_read -> i64: must be safe */
static bool test_fd_read_from_read_capable(void) {
    const char* il =
        "f0: i64 safe_read(myfd: fd<r>, buf: u64, count: u64) {\n"
        "  @b0:\n"
        "    v4: i64 = fd_read v1, v2, v3\n"
        "    fd_close v1\n"
        "    ret v4\n"
        "}\n";

    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should parse fd<r> read function");

    VerificationResult res = verify_module(mod);
    if (!res.is_safe) {
        for (uint32_t i = 0; i < res.error_count; i++)
            printf("  error: %s\n", res.errors[i].message);
    }
    bool ok = res.is_safe;
    verify_result_free(&res);
    il_mod_free(mod);
    ASSERT(ok, "fd<r> + fd_read must be safe");
    return true;
}

/* fd<w> as a parameter, fd_write -> i64: must be safe */
static bool test_fd_write_to_write_capable(void) {
    const char* il =
        "f0: i64 safe_write(myfd: fd<w>, buf: u64, count: u64) {\n"
        "  @b0:\n"
        "    v4: i64 = fd_write v1, v2, v3\n"
        "    fd_close v1\n"
        "    ret v4\n"
        "}\n";

    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should parse fd<w> write function");

    VerificationResult res = verify_module(mod);
    bool ok = res.is_safe;
    verify_result_free(&res);
    il_mod_free(mod);
    ASSERT(ok, "fd<w> + fd_write must be safe");
    return true;
}

/* fd<rw> as a parameter, fd_read AND fd_write: must both be safe */
static bool test_fd_rw_allows_both(void) {
    const char* il =
        "f0: i64 rw_read(myfd: fd<rw>, buf: u64, count: u64) {\n"
        "  @b0:\n"
        "    v4: i64 = fd_read v1, v2, v3\n"
        "    fd_close v1\n"
        "    ret v4\n"
        "}\n"
        "f1: i64 rw_write(myfd: fd<rw>, buf: u64, count: u64) {\n"
        "  @b0:\n"
        "    v4: i64 = fd_write v1, v2, v3\n"
        "    fd_close v1\n"
        "    ret v4\n"
        "}\n";

    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should parse fd<rw> functions");

    VerificationResult res = verify_module(mod);
    bool ok = res.is_safe;
    verify_result_free(&res);
    il_mod_free(mod);
    ASSERT(ok, "fd<rw> must allow both reads and writes");
    return true;
}

/* fd<r> as a parameter, fd_write: must be REJECTED */
static bool test_fd_write_to_read_only_rejected(void) {
    const char* il =
        "f0: i64 bad_write(myfd: fd<r>, buf: u64, count: u64) {\n"
        "  @b0:\n"
        "    v4: i64 = fd_write v1, v2, v3\n"
        "    ret v4\n"
        "}\n";

    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should parse fd<r> + fd_write function");

    VerificationResult res = verify_module(mod);
    bool ok = !res.is_safe;
    verify_result_free(&res);
    il_mod_free(mod);
    ASSERT(ok, "fd_write on fd<r> must be rejected by verifier");
    return true;
}

/* fd<w> as a parameter, fd_read: must be REJECTED */
static bool test_fd_read_from_write_only_rejected(void) {
    const char* il =
        "f0: i64 bad_read(myfd: fd<w>, buf: u64, count: u64) {\n"
        "  @b0:\n"
        "    v4: i64 = fd_read v1, v2, v3\n"
        "    ret v4\n"
        "}\n";

    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should parse fd<w> + fd_read function");

    VerificationResult res = verify_module(mod);
    bool ok = !res.is_safe;
    verify_result_free(&res);
    il_mod_free(mod);
    ASSERT(ok, "fd_read on fd<w> must be rejected by verifier");
    return true;
}

/* fd_open yields an fd; fd_close accepts it */
static bool test_fd_open_and_close(void) {
    const char* il =
        "f0: unit open_close(path: u64) {\n"
        "  @b0:\n"
        "    v2: u64 = const 2\n"
        "    v3: u64 = const 420\n"
        "    v4: fd<rw> = fd_open v1, v2, v3\n"
        "    fd_close v4\n"
        "    ret\n"
        "}\n";

    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should parse fd_open/fd_close");

    VerificationResult res = verify_module(mod);
    if (!res.is_safe) {
        for (uint32_t i = 0; i < res.error_count; i++)
            printf("  error: %s\n", res.errors[i].message);
    }
    bool ok = res.is_safe;
    verify_result_free(&res);
    il_mod_free(mod);
    ASSERT(ok, "fd_open + fd_close must be safe");
    return true;
}

/* Type equality: fd<r> != fd<w> != fd<rw> */
static bool test_fd_type_equality(void) {
    const ILType * r_ty  = il_type_fd(IL_CAP_READ);
    const ILType * w_ty  = il_type_fd(IL_CAP_WRITE);
    const ILType * rw_ty = il_type_fd(IL_CAP_RW);

    ASSERT(r_ty  != NULL, "fd<r> type should be created");
    ASSERT(w_ty  != NULL, "fd<w> type should be created");
    ASSERT(rw_ty != NULL, "fd<rw> type should be created");

    ASSERT( il_type_eq(r_ty,  r_ty),  "fd<r> == fd<r>");
    ASSERT(!il_type_eq(r_ty,  w_ty),  "fd<r> != fd<w>");
    ASSERT(!il_type_eq(r_ty,  rw_ty), "fd<r> != fd<rw>");
    ASSERT(!il_type_eq(w_ty,  rw_ty), "fd<w> != fd<rw>");

    
    
    
    return true;
}

/* fd is NOT a copy type (linear resource) */
static bool test_fd_is_not_copy(void) {
    const ILType * r_ty = il_type_fd(IL_CAP_READ);
    ASSERT(r_ty != NULL, "fd<r> type should be created");
    bool not_copy = !il_type_is_copy(r_ty);
    
    ASSERT(not_copy, "fd type must not be copy (it is a linear resource)");
    return true;
}

/* Test that the C API builders produce correct instructions */
static bool test_fd_builders(void) {
    const ILType * fd_ty  = il_type_fd(IL_CAP_RW);  ABORT_IF_NULL(fd_ty);
    const ILType * i64_ty = il_type_i64(); ABORT_IF_NULL(i64_ty);
    const ILType * u64_ty = il_type_u64(); ABORT_IF_NULL(u64_ty);

    ILValue path  = { .id = 1, .type = u64_ty };
    ILValue fd_v  = { .id = 2, .type = fd_ty  };
    ILValue buf   = { .id = 3, .type = u64_ty };
    ILValue cnt   = { .id = 4, .type = u64_ty };
    ILValue flags = { .id = 5, .type = u64_ty };
    ILValue mode  = { .id = 6, .type = u64_ty };

    ILInstruction* open_i  = il_build_fd_open(path, flags, mode, fd_ty);
    ILInstruction* read_i  = il_build_fd_read(fd_v, buf, cnt, i64_ty);
    ILInstruction* write_i = il_build_fd_write(fd_v, buf, cnt, i64_ty);
    ILInstruction* close_i = il_build_fd_close(fd_v);

    ASSERT(open_i  != NULL, "fd_open builder should succeed");
    ASSERT(read_i  != NULL, "fd_read builder should succeed");
    ASSERT(write_i != NULL, "fd_write builder should succeed");
    ASSERT(close_i != NULL, "fd_close builder should succeed");

    ASSERT(open_i->opcode  == IL_OP_FD_OPEN,  "fd_open opcode");
    ASSERT(read_i->opcode  == IL_OP_FD_READ,  "fd_read opcode");
    ASSERT(write_i->opcode == IL_OP_FD_WRITE, "fd_write opcode");
    ASSERT(close_i->opcode == IL_OP_FD_CLOSE, "fd_close opcode");

    ASSERT(open_i->result_type->kind  == IL_TY_FD, "fd_open result type");
    ASSERT(read_i->result_type->kind  == IL_TY_I64, "fd_read result type");
    ASSERT(write_i->result_type->kind == IL_TY_I64, "fd_write result type");

    ASSERT(open_i->operands.fd_open.flags == flags.id, "fd_open flags");
    ASSERT(open_i->operands.fd_open.mode  == mode.id,  "fd_open mode");

    il_instr_free(open_i);
    il_instr_free(read_i);
    il_instr_free(write_i);
    il_instr_free(close_i);
    
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_fd_type_equality);
    RUN_TEST(test_fd_is_not_copy);
    RUN_TEST(test_fd_builders);
    RUN_TEST(test_fd_read_from_read_capable);
    RUN_TEST(test_fd_write_to_write_capable);
    RUN_TEST(test_fd_rw_allows_both);
    RUN_TEST(test_fd_write_to_read_only_rejected);
    RUN_TEST(test_fd_read_from_write_only_rejected);
    RUN_TEST(test_fd_open_and_close);

    printf("Results: %d/%d passed\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_passed == tests_run) ? 0 : 1;
}
