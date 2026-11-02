#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include "surface_parser.h"
#include "surface_lexer.h"
#include "surface_lower.h"
#include "verifier.h"
#include "diagnostics.h"
#include "il_print.h"
#include "il_type.h"
#include "test_harness.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_array_borrows(void) {
    const char* source = 
        "fn main() -> i32 {\n"
        "    let mut x = 10;\n"
        "    {\n"
        "        let p = &mut x;\n"
        "        *p = 50;\n"
        "    }\n"
        "    let res = x;\n"
        "    return res;\n"
        "}\n"
        "fn test_immut() -> i32 {\n"
        "    let x = 10;\n"
        "    {\n"
        "        let p = &x;\n"
        "        let val = *p;\n"
        "        return val;\n"
        "    }\n"
        "}\n"
        "fn test_slice(s: [mut i32]) -> i32 {\n"
        "    {\n"
        "        let p = &mut s[0];\n"
        "        *p = 100;\n"
        "    }\n"
        "    let res = s[0];\n"
        "    return res;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* mod = surface_parse_module(source, "test.zrl", diag);
    ASSERT(mod != NULL, "Parse should succeed");

    ILModule* il_mod = surface_lower_module(mod, diag, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");

    VerificationResult res = verify_module(il_mod);
    bool safe = res.is_safe;
    if (!safe) {
        for (uint32_t i = 0; i < res.error_count; i++) {
            fprintf(stderr, "  %s at block %u, instr %u\n", res.errors[i].message, res.errors[i].block_id, res.errors[i].instr_index);
        }
    }
    verify_result_free(&res);
    il_mod_free(il_mod);
    surface_mod_free(mod);
    diag_report_destroy(diag);
    return safe;
}

static bool test_array_indexing(void) {
    const char* src = "fn test() -> i32 { let arr = [10, 20, 30]; arr[1] = 40; return arr[1]; }";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_array_index.zil", report);
    
    bool ok = true;
    if (!mod) {
        ok = false;
    } else {
        ILModule* il_mod = surface_lower_module(mod, NULL, false);
        if (!il_mod) {
            ok = false;
        } else {
            VerificationResult vres = verify_module(il_mod);
            if (vres.error_count > 0) {
                ok = false;
            } else {
                char buf[4096];
                il_print_module(il_mod, buf, sizeof(buf));
                if (!strstr(buf, "array_load") || !strstr(buf, "array_store") || !strstr(buf, "bounds_check")) {
                    ok = false;
                }
            }
            verify_result_free(&vres);
            il_mod_free(il_mod);
        }
        surface_mod_free(mod);
    }
    
    diag_report_destroy(report);
    return ok;
}

static bool test_slice_indexing(void) {
    const char* src = "fn test(s: [mut i32]) -> i32 { s[1] = 40; return s[1]; }";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_slice_index.zil", report);
    
    bool ok = true;
    if (!mod) {
        ok = false;
    } else {
        ILModule* il_mod = surface_lower_module(mod, NULL, false);
        if (!il_mod) {
            ok = false;
        } else {
            VerificationResult vres = verify_module(il_mod);
            if (vres.error_count > 0) {
                ok = false;
            } else {
                char buf[4096];
                il_print_module(il_mod, buf, sizeof(buf));
                if (!strstr(buf, "slice_load") || !strstr(buf, "slice_store") || !strstr(buf, "bounds_check")) {
                    ok = false;
                }
            }
            verify_result_free(&vres);
            il_mod_free(il_mod);
        }
        surface_mod_free(mod);
    }
    
    diag_report_destroy(report);
    return ok;
}

static bool test_array_literal_parse(void) {
    const char* src = "fn test() { let arr: [i32; 3] = [1, 2, 3]; let empty: [i32; 0] = []; }";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_array.zil", report);
    
    bool ok = true;
    if (!mod) {
        ok = false;
    } else {
        if (mod->function_count == 1 && mod->functions[0]->body && mod->functions[0]->body->stmt_count == 2) {
            const Statement* s1 = mod->functions[0]->body->statements[0];
            const Statement* s2 = mod->functions[0]->body->statements[1];
            
            if (s1->as.let.init->kind != EXPR_ARRAY) ok = false;
            if (s1->as.let.init->as.array_expr.count != 3) ok = false;
            if (s1->as.let.type == NULL || s1->as.let.type->kind != IL_TY_ARRAY || s1->as.let.type->as.array.length != 3) ok = false;
            
            if (s2->as.let.init->kind != EXPR_ARRAY) ok = false;
            if (s2->as.let.init->as.array_expr.count != 0) ok = false;
            if (s2->as.let.type == NULL || s2->as.let.type->kind != IL_TY_ARRAY || s2->as.let.type->as.array.length != 0) ok = false;
        } else {
            ok = false;
        }
        surface_mod_free(mod);
    }
    
    diag_report_destroy(report);
    return ok;
}

static bool test_array_literal_lower(void) {
    const char* src = "fn test() { let arr = [1, 2, 3]; let slice: [i32] = [4, 5]; }";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_array_lower.zil", report);
    
    bool ok = true;
    if (!mod) {
        ok = false;
    } else {
        ILModule* il_mod = surface_lower_module(mod, NULL, false);
        if (!il_mod) {
            ok = false;
        } else {
            char buf[4096];
            il_print_module(il_mod, buf, sizeof(buf));
            if (!strstr(buf, "array_construct") || !strstr(buf, "slice_construct")) {
                ok = false;
            }
            il_mod_free(il_mod);
        }
        surface_mod_free(mod);
    }
    
    diag_report_destroy(report);
    return ok;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    
    RUN_TEST(test_array_borrows);
    RUN_TEST(test_array_indexing);
    RUN_TEST(test_slice_indexing);
    RUN_TEST(test_array_literal_parse);
    RUN_TEST(test_array_literal_lower);
    
    printf("[%2d/%2d] Array and Slice Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return tests_passed == tests_run ? 0 : 1;
}
