#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_type.h"
#include "il_instr.h"
#include "il_print.h"
#include "verifier.h"
#include "diagnostics.h"
#include "surface_scope.h"
#include "il_pass.h"

int tests_run = 0;
int tests_passed = 0;

// From test_surface_errors.c
static bool test_result_match_safety(void) {
    const char* code = "enum Result { Ok(i32), Err(i32) } fn test_match(r: Result) -> i32 { match r { Ok(v) => v, Err(e) => e } }";
    SurfaceModule* smod = surface_parse_module(code, "test.zrl", NULL);
    if (!smod) return false;
    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) { surface_mod_free(smod); return false; }
    VerificationResult res = verify_module(mod);
    bool success = res.is_safe;
    verify_result_free(&res);
    il_mod_free(mod);
    surface_mod_free(smod);
    return success;
}

// From test_surface_pointers.c
static bool test_box_type(void) {
    const char* src = "fn main() -> Box<i32> { }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser failed for Box<T>");
    ASSERT(smod->functions[0]->return_type->kind == IL_TY_BOX, "Should be Box");
    surface_mod_free(smod);
    return true;
}

// From test_surface_scope.c
static bool test_symbol_shadowing(void) {
    ILFunction fake_func = { .id = 1 };
    Scope* root = scope_create(NULL, &fake_func);
    Scope* child = scope_create(root, &fake_func);
    const ILType * t_u32 = il_type_u32();
    ILValue val_root = { .id = 10, .type = t_u32 };
    ILValue val_child = { .id = 20, .type = t_u32 };
    symbol_add(root, "foo", val_root, false);
    symbol_add(child, "foo", val_child, true);
    const Symbol* sym = symbol_lookup(child, "foo");
    ASSERT(sym->value.id == 20, "Shadowing failed");
    scope_free(child);
    scope_free(root);
    return true;
}

// From test_surface_strings.c
static bool test_string_literal_parsing(void) {
    const char* src = "fn main() { \"hello zoril\" }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser failed for string literal");
    ASSERT(smod->functions[0]->body->result->kind == EXPR_STRING, "Expr kind mismatch");
    surface_mod_free(smod);
    return true;
}

// From test_surface_types.c
static bool test_lower_struct_literal(void) {
    const char* src = "struct Point { x: i32, y: i32 } fn main() { Point { x: 1, y: 2 } }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering failed");
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_arena_capacity_check(void) {
    const char* code = 
        "struct Arena { capacity: u64 }\n"
        "fn arena_init(capacity: u64) -> Box<Arena> { return box Arena { capacity: capacity }; }\n"
        "struct BigData { x: u64, y: u64, z: u64, w: u64 }\n"
        "fn main() -> i32 {\n"
        "    let mut arena = arena_init(16);\n" // Capacity 16 bytes
        "    let x = box(arena) BigData { x: 1, y: 2, z: 3, w: 4 };\n" // Allocates 32 bytes! Should fail compile-time.
        "    return 0;\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(code, "test.zrl", report);
    if (!smod) { diag_report_destroy(report); return false; }
    ILModule* mod = surface_lower_module(smod, report, false);
    if (!mod) { surface_mod_free(smod); diag_report_destroy(report); return false; }
    
    // Run the pass explicitly because tests bypass zoril-c.c
    for (uint32_t i = 0; i < mod->function_count; i++) {
        il_pass_const_fold(NULL, mod->functions[i]);
        il_pass_arena_capacity_check(mod, mod->functions[i], report);
    }
    
    // Check if report has the capacity exceeded error
    bool found_error = false;
    for (uint32_t i = 0; i < report->count; i++) {
        // printf("DEBUG report: %s\n", report->diagnostics[i].message);
        if (report->diagnostics[i].severity == DIAG_ERROR && strstr(report->diagnostics[i].message, "arena capacity exceeded at compile time")) {
            found_error = true;
            break;
        }
    }
    
    if (!found_error) {
        char buf[4096];
        il_print_module(mod, buf, sizeof(buf));
        fprintf(stderr, "IL Dump:\n%s\n", buf);
        for (uint32_t i = 0; i < report->count; i++) {
            fprintf(stderr, "Report: %s\n", report->diagnostics[i].message);
        }
    }

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return found_error;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    
    RUN_TEST(test_result_match_safety);
    RUN_TEST(test_box_type);
    RUN_TEST(test_symbol_shadowing);
    RUN_TEST(test_string_literal_parsing);
    RUN_TEST(test_lower_struct_literal);
    RUN_TEST(test_arena_capacity_check);
    
    printf("[%2d/%2d] Consolidated Surface Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
