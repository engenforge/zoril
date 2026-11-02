#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_ast.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "surface_lower_internal.h"
#include "il_cfg.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_unresolved_symbol_no_crash(void) {
    const char* source =
        "fn main() {\n"
        "    let x = unknown_var;\n"
        "    unknown_func();\n"
        "    let y = Type.unknown_method(x);\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) {
        diag_report_destroy(diag);
        return false;
    }

    // This should NOT crash
    ILModule* mod = surface_lower_module(smod, diag, false);

    // We expect some diagnostics to be emitted
    ASSERT(diag->has_errors, "Should have reported errors for unresolved symbols");

    if (mod) il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

/* Regression for id:136 — lower_lvalue SEGV when val.type is NULL.
   An unresolved type on a let binding leaves the symbol with a NULL
   type; using it as an lvalue (borrow or assignment target) previously
   caused a null dereference inside the stack-promotion path. */
static bool test_unresolved_type_lvalue_borrow_no_crash(void) {
    const char* source =
        "fn foo() {\n"
        "    let mut x: UnknownType = 0;\n"
        "    let _ = &mut x;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) { diag_report_destroy(diag); return false; }

    ILModule* mod = surface_lower_module(smod, diag, false);

    ASSERT(diag->has_errors, "Should report error for unresolved type");

    if (mod) il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

static bool test_unresolved_type_lvalue_assign_no_crash(void) {
    const char* source =
        "fn foo() {\n"
        "    let mut x: UnknownType = 0;\n"
        "    x = 1;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) { diag_report_destroy(diag); return false; }

    ILModule* mod = surface_lower_module(smod, diag, false);

    ASSERT(diag->has_errors, "Should report error for unresolved type");

    if (mod) il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

/* Regression for lvalue_crash.zrl: struct literal in a loop with a diverging
   member initialiser (continue inside a block expression). Previously crashed
   in lower_lvalue's stack-promotion path when current_block was NULL after
   the diverging control flow. */
static bool test_struct_literal_lvalue_divergence_no_crash(void) {
    const char* source =
        "struct S0 { a: i32 }\n"
        "pub fn main() {\n"
        "    loop {\n"
        "        let x = &mut (S0 { a: { continue; 0 } }).a;\n"
        "    }\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) { diag_report_destroy(diag); return true; }

    ILModule* mod = surface_lower_module(smod, diag, false);
    if (mod) il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

/* Regression for noncallable_crash.zrl: calling a variable that holds a
   plain integer rather than a function. Previously crashed in lower_closure_call
   when the callee had no callable type. Should emit an error without crashing. */
static bool test_call_on_noncallable_no_crash(void) {
    const char* source =
        "pub fn main() {\n"
        "    let x = 42;\n"
        "    let y = x();\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) { diag_report_destroy(diag); return true; }

    ILModule* mod = surface_lower_module(smod, diag, false);
    if (mod) il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

/* Regression for ec_unresolved_capture.zrl: closure capturing a variable of
   unresolved type. Previously crashed in resolve_capture with a NULL pointer
   dereference. Should emit an unresolved-type error without crashing. */
static bool test_closure_unresolved_capture_no_crash(void) {
    const char* source =
        "pub fn main() {\n"
        "    let x: NonExistent = 0;\n"
        "    let f = |dummy: i32| {\n"
        "        let z = x;\n"
        "    };\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) { diag_report_destroy(diag); return true; }

    ILModule* mod = surface_lower_module(smod, diag, false);

    ASSERT(diag->has_errors, "Should report error for unresolved captured type");

    if (mod) il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

/* Regression for 31142a9: method call with explicit type args on a type that
   has no such method. Previously leaked the method_type_args allocation on
   the !target_fn error path in lower_method_call. Detectable under ASan/LSan. */
static bool test_method_turbofish_on_wrong_type_no_crash(void) {
    const char* source =
        "fn main() {\n"
        "    let x = 42;\n"
        "    x.get_a::<i32>();\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) { diag_report_destroy(diag); return true; }

    ILModule* mod = surface_lower_module(smod, diag, false);
    if (mod) il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

static bool test_malformed_expression_node_no_crash(void) {
    ILModule* mod = il_mod_create();
    DiagnosticReport* report = diag_report_create();
    LowerContext lctx = { .module = mod, .report = report, .current_block = il_block_create(1) };
    
    // Malformed struct literal with NULL field name
    Expression expr;
    memset(&expr, 0, sizeof(Expression));
    expr.kind = EXPR_STRUCT;
    expr.as.struct_expr.name = "MyStruct";
    expr.as.struct_expr.field_count = 1;
    expr.as.struct_expr.field_names = calloc(1, sizeof(char*));
    expr.as.struct_expr.field_values = calloc(1, sizeof(Expression*));
    expr.as.struct_expr.field_names[0] = NULL; // Malformed!
    expr.as.struct_expr.field_values[0] = calloc(1, sizeof(Expression));
    expr.as.struct_expr.field_values[0]->kind = EXPR_INT;
    
    // This should NOT crash
    lower_expression(&lctx, &expr, NULL, (ILValue){0});

    free(expr.as.struct_expr.field_names);
    free(expr.as.struct_expr.field_values[0]);
    free(expr.as.struct_expr.field_values);
    il_mod_free(mod);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_unresolved_symbol_no_crash);
    RUN_TEST(test_unresolved_type_lvalue_borrow_no_crash);
    RUN_TEST(test_unresolved_type_lvalue_assign_no_crash);
    RUN_TEST(test_struct_literal_lvalue_divergence_no_crash);
    RUN_TEST(test_call_on_noncallable_no_crash);
    RUN_TEST(test_closure_unresolved_capture_no_crash);
    RUN_TEST(test_method_turbofish_on_wrong_type_no_crash);
    RUN_TEST(test_malformed_expression_node_no_crash);
    printf("[%2d/%2d] Lowerer Robustness Audit\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
