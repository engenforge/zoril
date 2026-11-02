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
#include "il_print.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_never_return_coercion(void) {
    fprintf(stderr, "RUNNING test_never_return_coercion\n");
    // A function that ends in 'return' should be considered to return 'never',
    // which is then assignable to the actual function return type.
    const char* src = 
        "fn test(cond: bool) -> i32 {\n"
        "    if cond {\n"
        "        return 42;\n"
        "    } else {\n"
        "        return 0;\n"
        "    }\n"
        "}";
    
    ILContext ctx;
    il_ctx_init(&ctx);
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        fprintf(stderr, "Parsing failed for source:\n%s\n", src);
        fprintf(stderr, "Parsing failed with %u errors, report->has_errors=%d\n", report->count, report->has_errors);
        for (uint32_t i = 0; i < report->count; i++) {
            const Diagnostic* d = &report->diagnostics[i];
            fprintf(stderr, "error: %s at %u:%u\n", d->message, d->location.line, d->location.col);
        }
    }
    ASSERT(smod != NULL, "Parse should succeed");
    
    ILModule* il_mod = surface_lower_module(smod, report, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");
    
    VerificationResult vres = verify_module(il_mod);
    bool success = vres.is_safe;
    if (!success) {
        fprintf(stderr, "Verification failed for source:\n%s\n", src);
        il_mod_print(il_mod, stderr);
        for (uint32_t i = 0; i < vres.error_count; i++) {
            fprintf(stderr, "error: %s at %u:%u\n", vres.errors[i].message, vres.errors[i].line, vres.errors[i].col);
        }
    }
    verify_result_free(&vres);
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    il_ctx_destroy(&ctx);
    return success;
}

static bool test_infinite_loop_divergence(void) {
    // A loop {} with no break should have type 'never'.
    const char* src = 
        "fn panics() -> never {\n"
        "    loop {}\n"
        "}\n"
        "fn test() -> i32 {\n"
        "    panics();\n"
        "}";
    
    ILContext ctx;
    il_ctx_init(&ctx);
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        fprintf(stderr, "Parsing failed for source:\n%s\n", src);
        fprintf(stderr, "Parsing failed with %u errors, report->has_errors=%d\n", report->count, report->has_errors);
        for (uint32_t i = 0; i < report->count; i++) {
            const Diagnostic* d = &report->diagnostics[i];
            fprintf(stderr, "error: %s at %u:%u\n", d->message, d->location.line, d->location.col);
        }
    }
    ASSERT(smod != NULL, "Parse should succeed");
    
    ILModule* il_mod = surface_lower_module(smod, report, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");
    
    VerificationResult vres = verify_module(il_mod);
    bool success = vres.is_safe;
    if (!success) {
        fprintf(stderr, "Verification failed for source:\n%s\n", src);
        il_mod_print(il_mod, stderr);
        for (uint32_t i = 0; i < vres.error_count; i++) {
            fprintf(stderr, "error: %s at %u:%u\n", vres.errors[i].message, vres.errors[i].line, vres.errors[i].col);
        }
    }
    verify_result_free(&vres);
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    il_ctx_destroy(&ctx);
    return success;
}

static bool test_never_match_coercion(void) {
    const char* src = 
        "enum Status { Ok, Fatal }\n"
        "fn panics() -> never { loop {} }\n"
        "fn test(s: Status) -> i32 {\n"
        "    return match s {\n"
        "        Status.Ok => 0,\n"
        "        Status.Fatal => panics(),\n"
        "    };\n"
        "}";
    
    ILContext ctx;
    il_ctx_init(&ctx);
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        fprintf(stderr, "Parsing failed for source:\n%s\n", src);
        fprintf(stderr, "Parsing failed with %u errors, report->has_errors=%d\n", report->count, report->has_errors);
        for (uint32_t i = 0; i < report->count; i++) {
            const Diagnostic* d = &report->diagnostics[i];
            fprintf(stderr, "error: %s at %u:%u\n", d->message, d->location.line, d->location.col);
        }
    }
    ASSERT(smod != NULL, "Parse should succeed");
    
    ILModule* il_mod = surface_lower_module(smod, report, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");
    
    VerificationResult vres = verify_module(il_mod);
    bool success = vres.is_safe;
    if (!success) {
        fprintf(stderr, "Verification failed for source:\n%s\n", src);
        il_mod_print(il_mod, stderr);
        for (uint32_t i = 0; i < vres.error_count; i++) {
            fprintf(stderr, "error: %s at %u:%u\n", vres.errors[i].message, vres.errors[i].line, vres.errors[i].col);
        }
    }
    verify_result_free(&vres);
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    il_ctx_destroy(&ctx);
    return success;
}

static bool test_never_phi_coercion(void) {
    const char* src =
        "struct Foo { a: i64, b: i64, c: i64 }\n"
        "fn panics() -> never { loop {} }\n"
        "fn test(cond: bool) -> Foo {\n"
        "    let x = if cond {\n"
        "        panics()\n"
        "    } else {\n"
        "        Foo { a: 1, b: 2, c: 3 }\n"
        "    };\n"
        "    return x;\n"
        "}\n";
    
    ILContext ctx;
    il_ctx_init(&ctx);
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        fprintf(stderr, "Parsing failed for source:\n%s\n", src);
        for (uint32_t i = 0; i < report->count; i++) {
            const Diagnostic* d = &report->diagnostics[i];
            fprintf(stderr, "error: %s at %u:%u\n", d->message, d->location.line, d->location.col);
        }
    }
    ASSERT(smod != NULL, "Parse should succeed");
    
    ILModule* il_mod = surface_lower_module(smod, report, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");
    
    VerificationResult vres = verify_module(il_mod);
    bool success = vres.is_safe;
    if (!success) {
        fprintf(stderr, "Verification failed for source:\n%s\n", src);
        il_mod_print(il_mod, stderr);
        for (uint32_t i = 0; i < vres.error_count; i++) {
            fprintf(stderr, "error: %s at %u:%u\n", vres.errors[i].message, vres.errors[i].line, vres.errors[i].col);
        }
    }
    verify_result_free(&vres);
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    il_ctx_destroy(&ctx);
    return success;
}

static bool test_regression_never_phi_coercion(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    const char* src =
        "struct Foo { a: i64, b: i64, c: i64 }\n"
        "fn panics() -> never { loop {} }\n"
        "fn test(cond: bool) -> Foo {\n"
        "    let x = if cond {\n"
        "        panics()\n"
        "    } else {\n"
        "        Foo { a: 1, b: 2, c: 3 }\n"
        "    };\n"
        "    return x;\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) diag_report_print(report, stderr);
    ASSERT(smod != NULL, "Parse should succeed");
    
    ILModule* mod = surface_lower_module(smod, report, false);
    if (!mod) diag_report_print(report, stderr);
    ASSERT(mod != NULL, "Lowering should succeed");

    char* ptr;
    size_t size;
    FILE* stream = open_memstream(&ptr, &size);
    qbe_emit_module(mod, stream);
    fclose(stream);

    // If correctly implemented, the result for x should be compatible with Foo.
    // If one branch diverges (panics), the lowerer may optimize away the PHI
    // and just use the value from the other branch.
    // We check that the code still compiles and Foo is correctly handled.
    bool success = (strstr(ptr, "function l $z_test") != NULL) && (strstr(ptr, "type :Foo") != NULL);
    
    if (!success) {
        printf("DEBUG: QBE for never_phi_coercion:\n%s\n", ptr);
    }
    free(ptr);
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    il_ctx_destroy(&ctx);

    ASSERT(success, "Function test and struct Foo should be emitted");
    return true;
}

static bool test_tuple_literal_divergence(void) {
    fprintf(stderr, "RUNNING test_tuple_literal_divergence\n");
    const char* src = 
        "fn test() -> i32 {\n"
        "    let x = ({ return 42; 0 }, 0);\n"
        "    return 0;\n"
        "}";
    
    ILContext ctx;
    il_ctx_init(&ctx);
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parse should succeed");
    
    ILModule* il_mod = surface_lower_module(smod, report, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");
    
    VerificationResult vres = verify_module(il_mod);
    bool success = vres.is_safe;
    verify_result_free(&vres);
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    il_ctx_destroy(&ctx);
    return success;
}

static bool test_struct_literal_divergence(void) {
    fprintf(stderr, "RUNNING test_struct_literal_divergence\n");
    const char* src = 
        "struct S { a: i32, b: i32 }\n"
        "fn test() -> i32 {\n"
        "    let x = S { a: { return 42; 0 }, b: 0 };\n"
        "    return 0;\n"
        "}";
    
    ILContext ctx;
    il_ctx_init(&ctx);
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parse should succeed");
    
    ILModule* il_mod = surface_lower_module(smod, report, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");
    
    VerificationResult vres = verify_module(il_mod);
    bool success = vres.is_safe;
    verify_result_free(&vres);
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    il_ctx_destroy(&ctx);
    return success;
}

int main(void) {
    RUN_TEST(test_never_return_coercion);
    RUN_TEST(test_infinite_loop_divergence);
    RUN_TEST(test_never_match_coercion);
    RUN_TEST(test_never_phi_coercion);
    RUN_TEST(test_regression_never_phi_coercion);
    RUN_TEST(test_tuple_literal_divergence);
    RUN_TEST(test_struct_literal_divergence);
    printf("test_divergence: %d/%d tests passed\n", tests_passed, tests_run);
    return tests_passed == tests_run ? 0 : 1;
}
