#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_type.h"
#include "diagnostics.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_match_enum_exhaustive(void) {
    const char* src = 
        "enum E { A, B }\n"
        "fn test_match(e: E) -> i32 {\n"
        "    match e {\n"
        "        E.A => 1,\n"
        "        E.B => 2\n"
        "    }\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parser should succeed for exhaustive enum match");
    
    ILModule* il_mod = surface_lower_module(smod, report, false);
    ASSERT(!report->has_errors, "Lowering should succeed for exhaustive enum match");
    
    if (il_mod) il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

static bool test_match_enum_non_exhaustive(void) {
    const char* src = 
        "enum E { A, B }\n"
        "fn test_match(e: E) -> i32 {\n"
        "    match e {\n"
        "        E.A => 1\n"
        "    }\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parser should succeed for non-exhaustive enum match");
    
    ILModule* il_mod = surface_lower_module(smod, report, false);
    bool failed = report->has_errors;
    
    if (il_mod) il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    
    ASSERT(failed, "Match on enum without covering all variants should fail");
    return true;
}

static bool test_match_bool_non_exhaustive(void) {
    const char* src = 
        "fn test_match(b: bool) -> i32 {\n"
        "    match b {\n"
        "        true => 1\n"
        "    }\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parser should succeed for non-exhaustive bool match");
    
    ILModule* il_mod = surface_lower_module(smod, report, false);
    bool failed = report->has_errors;
    
    if (il_mod) il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    
    ASSERT(failed, "Match on bool without covering all values should fail");
    return true;
}

static bool test_match_enum_with_wildcard(void) {
    const char* src = 
        "enum E { A, B, C }\n"
        "fn test_match(e: E) -> i32 {\n"
        "    match e {\n"
        "        E.A => 1,\n"
        "        _ => 2\n"
        "    }\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parser should succeed for enum match with wildcard");
    
    ILModule* il_mod = surface_lower_module(smod, report, false);
    ASSERT(!report->has_errors, "Lowering should succeed for enum match with wildcard");
    
    if (il_mod) il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

static bool test_match_or_pattern_type_mismatch(void) {
    const char* src = 
        "enum Foo {\n"
        "    A(i32),\n"
        "    B(bool),\n"
        "}\n"
        "fn test(f: Foo) -> i32 {\n"
        "    return match f {\n"
        "        Foo.A(v) | Foo.B(v) => 1,\n"
        "    };\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parser should succeed");
    
    ILModule* il_mod = surface_lower_module(smod, report, false);
    bool failed = false;
    for (uint32_t i = 0; i < report->count; i++) {
        if (report->diagnostics[i].severity == DIAG_ERROR && 
            strstr(report->diagnostics[i].message, "type")) {
            failed = true;
            break;
        }
    }
    
    if (il_mod) il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    
    ASSERT(failed, "Mismatched OR-pattern bindings should fail type checking");
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    
    RUN_TEST(test_match_enum_exhaustive);
    RUN_TEST(test_match_enum_non_exhaustive);
    RUN_TEST(test_match_bool_non_exhaustive);
    RUN_TEST(test_match_enum_with_wildcard);
    RUN_TEST(test_match_or_pattern_type_mismatch);

    printf("[%2d/%2d] Match Exhaustiveness Checking\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
