#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "qbe_emit.h"
#include "verifier.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_slice_field_assign(void) {
    const char* source = 
        "struct S {\n"
        "    s: [i32],\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let mut arr = [10, 20, 30];\n"
        "    let mut x = S { s: @slice(&mut arr[0], 3) };\n"
        "    x.s[1] = 42;\n"
        "    return x.s[1];\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test_slice_field.zrl", diag);
    ASSERT(smod != NULL, "Parse failed");

    ILModule* mod = surface_lower_module(smod, diag, false);
    if (mod == NULL || diag->has_errors) {
        diag_report_print(diag, stderr);
    }
    ASSERT(mod != NULL, "Lowering failed");
    ASSERT(!diag->has_errors, "Lowering produced errors");

    VerificationResult vres = verify_module(mod);
    ASSERT(vres.is_safe, "Verifier failed");
    verify_result_free(&vres);

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_slice_field_assign);
    printf("[%2d/%2d] Slice Field Assignment Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
