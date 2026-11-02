#include "il_cfg.h"
#include "qbe_emit.h"
#include "surface_ast.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_print.h"
#include "verifier.h"
#include "diagnostics.h"

#include "test_harness.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_method_parsing(void) {
    const char* src = 
        "struct Point { x: i32, y: i32 }\n"
        "impl Point {\n"
        "    fn dist(self) -> i32 { return self.x + self.y; }\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let p = Point { x: 10, y: 20 };\n"
        "    return p.dist();\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_methods.zil", report);
    
    if (!mod) {
        diag_report_destroy(report);
        return false;
    }
    ILModule* il_mod = surface_lower_module(mod, NULL, false);
    if (!il_mod) {
        surface_mod_free(mod);
        diag_report_destroy(report);
        return false;
    }
    VerificationResult vres = verify_module(il_mod);
    bool ok = vres.is_safe;
    verify_result_free(&vres);
    il_mod_free(il_mod);
    surface_mod_free(mod);
    diag_report_destroy(report);
    return ok;
}

static bool test_pointer_method_calls(void) {
    const char* src = 
        "struct Counter { val: i32 }\n"
        "impl Counter {\n"
        "    fn inc(self: &mut Counter) { self.val = self.val + 1; }\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let mut c = Counter { val: 0 };\n"
        "    let p = &mut c;\n"
        "    (*p).inc();\n"
        "    p.inc();\n"
        "    let mut b = box Counter { val: 0 };\n"
        "    b.inc();\n"
        "    return 0;\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_methods_ptr.zil", report);
    if (!mod) {
        diag_report_destroy(report);
        return false;
    }
    ILModule* il_mod = surface_lower_module(mod, NULL, false);
    if (!il_mod) {
        surface_mod_free(mod);
        diag_report_destroy(report);
        return false;
    }
    char buf[16384];
    il_print_module(il_mod, buf, sizeof(buf));
    printf("--- IL OUTPUT ---\n%s\n-----------------\n", buf);
    VerificationResult vres = verify_module(il_mod);
    bool ok = vres.is_safe;
    
    // Make sure we didn't generate extra allocs for the method receivers
    const ILFunction* main_fn = il_mod_get_func_by_name(il_mod, "main");
    int alloc_count = 0;
    for (uint32_t b = 0; b < main_fn->block_count; b++) {
        for (uint32_t i = 0; i < main_fn->blocks[b]->instr_count; i++) {
            if (main_fn->blocks[b]->instructions[i]->opcode == IL_OP_ALLOC) alloc_count++;
        }
    }
    
    verify_result_free(&vres);
    il_mod_free(il_mod);
    surface_mod_free(mod);
    diag_report_destroy(report);

    printf("alloc_count = %d\n", alloc_count);
    ASSERT(alloc_count <= 5, "Too many allocations, temporary copy likely generated");

    return ok;
}

// id:041 — method call as the body of a match arm was mis-parsed because
// apply_postfix_ops stopped consuming postfix operators after block-like
// expressions (match/if/block arms).
static bool test_regression_method_call_in_match_arm(void) {
    const char* src =
        "struct AST { count: u32 }\n"
        "impl AST {\n"
        "    fn alloc(self: &mut AST) -> u32 {\n"
        "        self.count = self.count + 1;\n"
        "        return self.count;\n"
        "    }\n"
        "}\n"
        "struct Parser { ast: *mut AST }\n"
        "enum Kind { A, B }\n"
        "impl Parser {\n"
        "    fn test(self: &mut Parser, k: Kind) -> u32 {\n"
        "        return match k {\n"
        "            Kind.A => (*self.ast).alloc(),\n"
        "            Kind.B => 0,\n"
        "        };\n"
        "    }\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        for (uint32_t i = 0; i < report->count; i++)
            fprintf(stderr, "  %s\n", report->diagnostics[i].message);
        diag_report_destroy(report);
        return false;
    }
    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "method call in match arm should lower successfully");
    // The match arm body should be a call, not a bare zero — verify Parser_test
    // is present and has more than 1 block (match dispatch + arms).
    const ILFunction* fn = il_mod_get_func_by_name(mod, "Parser_test");
    ASSERT(fn != NULL, "Parser_test should be present");
    ASSERT(fn->block_count > 1, "Parser_test should have multiple blocks for match dispatch");
    VerificationResult vres = verify_module(mod);
    ASSERT(vres.is_safe, "module should be safe");
    verify_result_free(&vres);
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

// Similar bug: method call after if-expression (same postfix family as id:041).
// In the id:041 family, apply_postfix_ops stopped consuming tokens after any
// block-like expression.  Verify that `(if c { a } else { b }).get()` is
// treated as a call whose receiver is the if-expression, not a bare if.
static bool test_regression_method_call_after_if_expr(void) {
    const char* src =
        "struct Ctr { val: i32 }\n"
        "impl Ctr {\n"
        "    fn get(self: &Ctr) -> i32 { return self.val; }\n"
        "}\n"
        "fn test(cond: bool, a: Ctr, b: Ctr) -> i32 {\n"
        "    return if cond { a } else { b }.get();\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        for (uint32_t i = 0; i < report->count; i++)
            fprintf(stderr, "  %s\n", report->diagnostics[i].message);
        diag_report_destroy(report);
        return false;
    }
    // The return statement's expression should be a CALL (method call), not an IF.
    // If the bug were present the `.get()` would be dropped and the return
    // expression would be the EXPR_IF directly.
    const FunctionDecl* fn = smod->functions[smod->function_count - 1];
    // fn body has one statement: STMT_RETURN
    ASSERT(fn->body->stmt_count == 1, "fn body should have one statement");
    const Statement* ret = fn->body->statements[0];
    ASSERT(ret->kind == STMT_RETURN, "statement should be a return");
    ASSERT(ret->as.ret != NULL, "return should have a value");
    ASSERT(ret->as.ret->kind == EXPR_CALL,
           "method call after if-expression should be EXPR_CALL, not EXPR_IF");
    const CallExpr* call = &ret->as.ret->as.call;
    ASSERT(call->receiver != NULL && call->receiver->kind == EXPR_IF,
           "call receiver should be the if-expression");
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

static bool test_method_forward_ref(void) {
    const char* src =
        "struct Foo { x: i32 }\n"
        "impl Foo {\n"
        "    fn a(self: &mut Foo) {\n"
        "        self.b();\n"
        "    }\n"
        "    fn b(self: &mut Foo) {\n"
        "        self.x = 42;\n"
        "    }\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parse should succeed");

    ILModule* il_mod = surface_lower_module(smod, report, false);
    
    if (report->has_errors) {
        for (uint32_t i = 0; i < report->count; i++) {
            fprintf(stderr, "Error: %s\n", report->diagnostics[i].message);
        }
    }
    
    ASSERT(!report->has_errors, "Lowering should succeed without errors");
    ASSERT(il_mod != NULL, "Lowering should succeed");

    il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_method_parsing);
    RUN_TEST(test_pointer_method_calls);
    
    RUN_TEST(test_regression_method_call_in_match_arm);
    RUN_TEST(test_regression_method_call_after_if_expr);
    RUN_TEST(test_method_forward_ref);
    printf("[%2d/%2d] Method Definitions\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
