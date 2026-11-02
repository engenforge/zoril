#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "verifier.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static void cleanup(SurfaceModule* smod, ILModule* mod, DiagnosticReport* report) __attribute__((unused));
static void cleanup(SurfaceModule* smod, ILModule* mod, DiagnosticReport* report) {
    if (mod) il_mod_free(mod);
    if (smod) surface_mod_free(smod);
    if (report) diag_report_destroy(report);
}

static bool test_closure_multiple_calls_move(void) {
    const char* src = 
        "fn test() -> Box<i32> {\n"
        "    let b = box 42;\n"
        "    let f = | | { return b; };\n" // Moves 'b' out of closure on first call
        "    let a = f();\n"
        "    let b_val = f();\n" // Error: capture 'b' was already moved in first call
        "    return b_val;\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        diag_report_destroy(report);
        return false;
    }

    ILModule* mod = surface_lower_module(smod, report, false);
    
    bool found_error = false;
    for (uint32_t i = 0; i < report->count; i++) {
        if (report->diagnostics[i].severity == DIAG_ERROR && 
            strstr(report->diagnostics[i].message, "moved")) {
            found_error = true;
            break;
        }
    }

    if (!found_error && mod) {
        VerificationResult res = verify_module(mod);
        if (!res.is_safe) found_error = true;
        verify_result_free(&res);
    }

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    
    ASSERT(found_error, "Should report error when calling closure twice if it moves its capture");
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_closure_multiple_calls_move);
    printf("[%2d/%2d] Closure Safety Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
