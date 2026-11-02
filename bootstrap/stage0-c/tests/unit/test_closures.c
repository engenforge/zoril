#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include "surface_parser.h"
#include "surface_lower.h"
#include "verifier.h"
#include "diagnostics.h"
#include "il_print.h"
#include "il_type.h"
#include "test_harness.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_closures_capture(void) {
    const char* source = 
        "fn main() -> i32 {\n"
        "    let y = 10;\n"
        "    let f = |x: i32| -> i32 { return x + y; };\n"
        "    return f(32);\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    ASSERT(smod != NULL, "Parse failed");

    ILModule* mod = surface_lower_module(smod, diag, false);
    ASSERT(mod != NULL, "Lowering failed");

    VerificationResult res = verify_module(mod);
    bool safe = res.is_safe;
    verify_result_free(&res);
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return safe;
}

static bool test_closures_lower(void) {
    const char* source = 
        "fn main() -> i32 {\n"
        "    let f = |x: i32| -> i32 { return x + 1; };\n"
        "    return f(41);\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    ASSERT(smod != NULL, "Parse failed");

    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Lowering failed");

    VerificationResult res = verify_module(mod);
    bool safe = res.is_safe;
    verify_result_free(&res);
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return safe;
}

static bool test_closures_parser(void) {
    const char* source = 
        "fn main() {\n"
        "  let f = |a: i32, b: i32| -> i32 { a + b };\n"
        "  let g = |x| x * 2;\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(source, "test.zrl", report);
    ASSERT(mod != NULL, "Parse failed");

    bool ok = true;
    if (mod->function_count != 1) ok = false;
    else {
        FunctionDecl* main_fn = mod->functions[0];
        if (main_fn->body->stmt_count != 2) ok = false;
        else {
            Statement* s1 = main_fn->body->statements[0];
            const ClosureExpr* c1 = &s1->as.let.init->as.closure;
            if (c1->param_count != 2 || strcmp(c1->params[0].name, "a") != 0) ok = false;

            Statement* s2 = main_fn->body->statements[1];
            const ClosureExpr* c2 = &s2->as.let.init->as.closure;
            if (c2->param_count != 1 || strcmp(c2->params[0].name, "x") != 0) ok = false;
        }
    }

    surface_mod_free(mod);
    diag_report_destroy(report);
    return ok;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    
    RUN_TEST(test_closures_capture);
    RUN_TEST(test_closures_lower);
    RUN_TEST(test_closures_parser);
    
    printf("[%2d/%2d] Consolidated Closures Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
