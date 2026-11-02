#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "diagnostics.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_circular_type_alias(void) {
    const char* src = "type A = B; type B = A; fn test() -> A {}";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    bool ok = (smod != NULL);
    
    ILModule* ilmod = NULL;
    if (ok) {
        ilmod = surface_lower_module(smod, report, false);
        ok = (ilmod != NULL);
    }
    
    if (ilmod) il_mod_free(ilmod);
    if (smod) surface_mod_free(smod);
    diag_report_destroy(report);

    ASSERT(ok, "Should not crash on circular alias");
    return true;
}

static bool test_recursive_generic(void) {
    const char* src = "struct Wrapper<T> { inner: Wrapper<Box<T>> } fn test() -> Wrapper<i32> {}";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    bool ok = (smod != NULL);
    
    ILModule* ilmod = NULL;
    if (ok) {
        ilmod = surface_lower_module(smod, report, false);
    }

    if (ilmod) il_mod_free(ilmod);
    if (smod) surface_mod_free(smod);
    diag_report_destroy(report);

    return true; // Reaching here means no crash
}

static bool test_deeply_nested_type_mangling(void) {
    // Generate a deeply nested tuple type string: (((...i32...)))
    size_t depth = 100;
    size_t cap = 4096;
    char* src = malloc(cap);
    if (!src) return false;
    strcpy(src, "fn test() { let x: ");
    for (size_t i = 0; i < depth; i++) strcat(src, "(");
    strcat(src, "i32");
    for (size_t i = 0; i < depth; i++) strcat(src, ",)");
    strcat(src, " = 0 as ");
    for (size_t i = 0; i < depth; i++) strcat(src, "(");
    strcat(src, "i32");
    for (size_t i = 0; i < depth; i++) strcat(src, ",)");
    strcat(src, "; }");

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (smod) {
        ILModule* ilmod = surface_lower_module(smod, report, false);
        if (ilmod) il_mod_free(ilmod);
        surface_mod_free(smod);
    }
    diag_report_destroy(report);
    free(src);

    return true; // No crash is success
}

/* Regression for ec_illegal_recursion.zrl: a struct with a direct self-referential
   field (struct S { a: S }) that has infinite size. Previously caused OOM and
   stack overflow during type lowering. Should emit a recursion/infinite-size
   error without crashing. */
static bool test_direct_recursive_struct_no_crash(void) {
    const char* src =
        "struct S { a: S }\n"
        "pub fn main() {\n"
        "    let x: S = 0 as S;\n"
        "    let y = sizeof(S);\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (smod) {
        ILModule* ilmod = surface_lower_module(smod, report, false);
        if (ilmod) il_mod_free(ilmod);
        surface_mod_free(smod);
    }

    bool has_recursion_error = false;
    for (uint32_t i = 0; i < report->count; i++) {
        if (strstr(report->diagnostics[i].message, "recursive") ||
            strstr(report->diagnostics[i].message, "infinite size")) {
            has_recursion_error = true;
            break;
        }
    }
    diag_report_destroy(report);

    ASSERT(has_recursion_error, "Should have reported a recursion/infinite-size error");
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_circular_type_alias);
    RUN_TEST(test_recursive_generic);
    RUN_TEST(test_deeply_nested_type_mangling);
    RUN_TEST(test_direct_recursive_struct_no_crash);

    printf("[%2d/%2d] Circular and Recursive Type Robustness\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return tests_run == tests_passed ? 0 : 1;
}
