#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "verifier.h"
#include "il_print.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_slice_builtin(void) {
    const char* src = 
        "extern fn malloc(size: u64) -> *mut i32;\n"
        "fn test() -> i32 {\n"
        "  let mut p = malloc(8);\n"
        "  *p = 42;\n"
        "  let s = @slice(p, 1);\n"
        "  return s[0];\n"
        "}";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        diag_report_destroy(report);
        return false;
    }
    
    ILModule* ilmod = surface_lower_module(smod, report, false);
    if (!ilmod) {
        surface_mod_free(smod);
        diag_report_destroy(report);
        return false; 
    }

    VerificationResult vres = verify_module(ilmod);
    bool success = vres.is_safe;
    if (!success) {
        for (uint32_t i = 0; i < vres.error_count; i++) {
            printf("Error: %s at block %u, instr %u\n", vres.errors[i].message, vres.errors[i].block_id, vres.errors[i].instr_index);
        }
    }
    
    verify_result_free(&vres);
    il_mod_free(ilmod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    
    return success;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_slice_builtin);
    printf("Tests run: %d, Passed: %d\n", tests_run, tests_passed);
    il_ctx_destroy(&ctx);
    return tests_run == tests_passed ? 0 : 1;
}
