#include "il_cfg.h"
#include "qbe_emit.h"
#include "surface_ast.h"
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

static void cleanup(SurfaceModule* smod, ILModule* mod, DiagnosticReport* report) {
    if (mod) il_mod_free(mod);
    if (smod) surface_mod_free(smod);
    if (report) diag_report_destroy(report);
}

static bool test_cast_precedence_unary(void) {
    const char* src = 
        "fn test(p: *i32) -> *u8 {\n"
        "    return &*p as *u8;\n" // Should be (&(*p)) as *u8
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) { diag_render_terminal(report); cleanup(NULL, NULL, report); ASSERT(false, "Parse failed"); }

    ILModule* mod = surface_lower_module(smod, report, false);
    if (!mod) { 
        diag_render_terminal(report);
        cleanup(smod, NULL, report); 
        ASSERT(false, "Lowering failed"); 
    }

    VerificationResult res = verify_module(mod);
    bool safe = res.is_safe;
    if (!safe) {
        for (uint32_t i = 0; i < res.error_count; i++) printf("Verify error: %s\n", res.errors[i].message);
    }
    verify_result_free(&res);

    cleanup(smod, mod, report);
    ASSERT(safe, "Verification failed");
    return true;
}

static bool test_cast_precedence_logical(void) {
    const char* src = 
        "fn test(b: bool) -> i32 {\n"
        "    return !b as i32;\n" // Should be (!b) as i32
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) { diag_render_terminal(report); cleanup(NULL, NULL, report); ASSERT(false, "Parse failed"); }

    ILModule* mod = surface_lower_module(smod, report, false);
    if (!mod) { diag_render_terminal(report); cleanup(smod, NULL, report); ASSERT(false, "Lowering failed"); }

    VerificationResult res = verify_module(mod);
    bool safe = res.is_safe;
    if (!safe) {
        for (uint32_t i = 0; i < res.error_count; i++) printf("Verify error: %s\n", res.errors[i].message);
    }
    verify_result_free(&res);

    cleanup(smod, mod, report);
    ASSERT(safe, "Verification failed");
    return true;
}

static bool test_nested_casts(void) {
    const char* src = 
        "fn test(p: *i32) -> u64 {\n"
        "    return p as *u8 as u64;\n" // Should be (p as *u8) as u64
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) { diag_render_terminal(report); cleanup(NULL, NULL, report); ASSERT(false, "Parse failed"); }

    ILModule* mod = surface_lower_module(smod, report, false);
    if (!mod) { diag_render_terminal(report); cleanup(smod, NULL, report); ASSERT(false, "Lowering failed"); }

    VerificationResult res = verify_module(mod);
    bool safe = res.is_safe;
    if (!safe) {
        for (uint32_t i = 0; i < res.error_count; i++) printf("Verify error: %s\n", res.errors[i].message);
    }
    verify_result_free(&res);

    cleanup(smod, mod, report);
    ASSERT(safe, "Verification failed");
    return true;
}

static bool test_regression_as_precedence(void) {
    const char* src = 
        "fn main() {\n"
        "    let mut x: u64 = 0;\n"
        "    let p = &mut x as *mut u64;\n"
        "    let y = *p as u32 + 1u32;\n"
        "    let is_ok = true;\n"
        "    let z = !is_ok as u32;\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        printf("Parse failed:\n");
        for (uint32_t i = 0; i < report->count; i++) printf("  %s\n", report->diagnostics[i].message);
        diag_report_destroy(report);
        return false;
    }
    
    FunctionDecl* main_fn = smod->functions[0];
    
    // Check 'let y = *p as u32 + 1u32;'
    const Statement* let_y = main_fn->body->statements[2];
    const Expression* init_y = let_y->as.let.init;
    ASSERT(init_y->kind == EXPR_BINARY, "y init should be binary (+)");
    ASSERT(init_y->as.binary.left->kind == EXPR_CAST, "Left of + should be cast");
    ASSERT(init_y->as.binary.left->as.cast_expr.expr->kind == EXPR_UNARY, "Cast operand should be unary (*)");

    // Check 'let z = !is_ok as u32;'
    const Statement* let_z = main_fn->body->statements[4];
    const Expression* init_z = let_z->as.let.init;
    ASSERT(init_z->kind == EXPR_CAST, "z init should be cast");
    ASSERT(init_z->as.cast_expr.expr->kind == EXPR_UNARY, "Cast operand should be unary (!)");
    
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_cast_precedence_unary);
    RUN_TEST(test_cast_precedence_logical);
    RUN_TEST(test_nested_casts);
    RUN_TEST(test_regression_as_precedence);
    printf("[%2d/%2d] Cast Precedence Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
