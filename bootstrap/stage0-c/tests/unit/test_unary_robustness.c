#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_ast.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_cfg.h"
#include "verifier.h"
#include "il_type.h"
#include "qbe_emit.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_unary_not_bool(void) {
    const char* source = 
        "fn main() -> i32 {\n"
        "    let flag: bool = true;\n"
        "    let negated = !flag;\n"
        "    return 0;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) {
        diag_render_terminal(diag);
        diag_report_destroy(diag);
        return false;
    }

    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(diag);
        return false;
    }

    VerificationResult vres = verify_module(mod);
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return vres.is_safe;
}

static bool test_unary_neg_int(void) {
    const char* source = 
        "fn main() -> i32 {\n"
        "    let x = 10;\n"
        "    let y = -x;\n"
        "    return 0;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) {
        diag_report_destroy(diag);
        return false;
    }

    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(diag);
        return false;
    }

    VerificationResult vres = verify_module(mod);
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return vres.is_safe;
}

// Test that !x on an integer type emits XOR with all-ones (bitwise NOT),
// not XOR with 1 (which would only flip the lowest bit).
static bool test_unary_not_int_is_bitwise_not(void) {
    const char* source =
        "pub fn not_u64(x: u64) -> u64 { return !x; }\n"
        "fn main() -> i32 { return 0; }\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) {
        diag_render_terminal(diag);
        diag_report_destroy(diag);
        return false;
    }

    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(diag);
        return false;
    }

    char* output = malloc(64 * 1024);
    if (!output) { il_mod_free(mod); surface_mod_free(smod); diag_report_destroy(diag); return false; }
    memset(output, 0, 64 * 1024);
    FILE* out = fmemopen(output, 64 * 1024, "w");
    qbe_emit_module(mod, out);
    fclose(out);

    // Must XOR with all-ones (18446744073709551615) for bitwise NOT on u64,
    // NOT with 1 (which was the bug: x ^ 1 = flip lowest bit only).
    bool has_allones = strstr(output, "18446744073709551615") != NULL;
    ASSERT(has_allones, "!u64 must emit XOR with 18446744073709551615 (all-ones), not XOR with 1");

    free(output);
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

// Regression: !bool must still emit XOR with 1 (logical NOT), not XOR with all-ones.
static bool test_unary_not_bool_stays_xor1(void) {
    const char* source =
        "pub fn not_bool(x: bool) -> bool { return !x; }\n"
        "fn main() -> i32 { return 0; }\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) {
        diag_render_terminal(diag);
        diag_report_destroy(diag);
        return false;
    }

    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(diag);
        return false;
    }

    char* output = malloc(64 * 1024);
    if (!output) { il_mod_free(mod); surface_mod_free(smod); diag_report_destroy(diag); return false; }
    memset(output, 0, 64 * 1024);
    FILE* out = fmemopen(output, 64 * 1024, "w");
    qbe_emit_module(mod, out);
    fclose(out);

    // Bool NOT must still XOR with 1 (logical NOT: !true = 0, !false = 1).
    // It must NOT use the all-ones constant.
    bool has_xor1 = strstr(output, "xor") != NULL;
    bool has_allones = strstr(output, "18446744073709551615") != NULL;
    ASSERT(has_xor1, "!bool must emit an xor instruction");
    ASSERT(!has_allones, "!bool must NOT use all-ones constant");

    free(output);
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_unary_not_bool);
    RUN_TEST(test_unary_neg_int);
    RUN_TEST(test_unary_not_int_is_bitwise_not);
    RUN_TEST(test_unary_not_bool_stays_xor1);

    printf("[%2d/%2d] Unary Operator Robustness\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
