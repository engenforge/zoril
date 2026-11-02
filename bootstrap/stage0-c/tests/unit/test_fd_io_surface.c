#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_print.h"
#include "il_type.h"
#include "verifier.h"

int tests_run = 0;
int tests_passed = 0;

/* Parse and lower src, returning the IL module (caller frees) or NULL on
 * any parse/lower error. */
static ILModule* compile(const char* src) {
    DiagnosticReport report = {0};
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", &report);
    if (!smod || report.has_errors) return NULL;
    ILModule* mod = surface_lower_module(smod, &report, false);
    surface_mod_free(smod);
    if (!mod || report.has_errors) { if (mod) il_mod_free(mod); return NULL; }
    return mod;
}

/* io::open returns fd<rw>; io::close consumes it.  The function body should
 * lower without errors and the IL should contain fd_open / fd_close. */
static bool test_open_close_roundtrip(void) {
    const char* src =
        "pub fn open(path: [u8], flags: u64, mode: u64) -> fd<rw> {\n"
        "    return @fd_open(path.ptr, flags, mode);\n"
        "}\n"
        "pub fn close(f: fd<rw>) {\n"
        "    @fd_close(f);\n"
        "}\n"
        "fn use_file(path: [u8]) {\n"
        "    let f = open(path, 0 as u64, 0 as u64);\n"
        "    close(f);\n"
        "}\n";

    ILModule* mod = compile(src);
    ASSERT(mod != NULL, "open/close roundtrip should compile without errors");

    /* The IL should contain fd_open and fd_close opcodes. */
    char buf[32768];
    il_print_module(mod, buf, sizeof(buf));
    ASSERT(strstr(buf, "fd_open")  != NULL, "IL should contain fd_open");
    ASSERT(strstr(buf, "fd_close") != NULL, "IL should contain fd_close");

    il_mod_free(mod);
    return true;
}

/* open() returns fd<rw>.  Passing that value to a function expecting fd<rw>
 * must lower cleanly. */
static bool test_open_result_is_fd_type(void) {
    const char* src =
        "pub fn open(path: [u8], flags: u64, mode: u64) -> fd<rw> {\n"
        "    return @fd_open(path.ptr, flags, mode);\n"
        "}\n"
        "pub fn close(f: fd<rw>) {\n"
        "    @fd_close(f);\n"
        "}\n"
        "fn write_and_close(path: [u8], msg: [u8]) {\n"
        "    let f = open(path, 1 as u64, 420 as u64);\n"
        "    @fd_write(f, msg.ptr, msg.len as u64);\n"
        "    close(f);\n"
        "}\n";

    ILModule* mod = compile(src);
    ASSERT(mod != NULL,
           "Using the fd<rw> return of open with fd_write/close should compile");
    il_mod_free(mod);
    return true;
}

/* Forgetting to close the fd should be detectable (the IL should still lower,
 * but the verifier should flag the leak).  This confirms fd<rw> is tracked as
 * a linear resource once returned from open(). */
static bool test_unclosed_fd_flagged_by_verifier(void) {
    const char* src =
        "pub fn open(path: [u8], flags: u64, mode: u64) -> fd<rw> {\n"
        "    return @fd_open(path.ptr, flags, mode);\n"
        "}\n"
        "fn leak_fd(path: [u8]) {\n"
        "    let _f = open(path, 0 as u64, 0 as u64);\n"
        "    /* _f is never closed — should be a verifier leak */\n"
        "}\n";

    DiagnosticReport report = {0};
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", &report);
    ASSERT(smod != NULL && !report.has_errors, "Parsing should succeed");

    ILModule* mod = surface_lower_module(smod, &report, false);
    surface_mod_free(smod);
    ASSERT(mod != NULL, "Lowering an unclosed fd should still produce IL");

    VerificationResult vr = verify_module(mod);
    bool found_leak = false;
    for (uint32_t i = 0; i < vr.error_count; i++) {
        if (vr.errors[i].type == VERIFY_ERR_LEAK) { found_leak = true; break; }
    }
    verify_result_free(&vr);
    il_mod_free(mod);

    ASSERT(found_leak, "Verifier should flag the unclosed fd<rw> as a leak");
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);

    RUN_TEST(test_open_close_roundtrip);
    RUN_TEST(test_open_result_is_fd_type);
    RUN_TEST(test_unclosed_fd_flagged_by_verifier);

    printf("Results: %d/%d passed\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_passed == tests_run) ? 0 : 1;
}
