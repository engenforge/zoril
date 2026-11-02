#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "verifier.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_match_aggregate_bind(void) {
    const char* source = 
        "enum Shape {\n"
        "    Circle(i32),\n"
        "    Rectangle((i32, i32)),\n"
        "    Point,\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let s = Shape.Rectangle((10, 20));\n"
        "    return match s {\n"
        "        Shape.Rectangle(dims) => dims.0 + dims.1,\n"
        "        _ => 0,\n"
        "    };\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test_match.zrl", diag);
    ASSERT(smod != NULL, "Parse failed");

    ILModule* mod = surface_lower_module(smod, diag, false);
    if (!mod) {
        diag_report_print(diag, stderr);
    }
    ASSERT(mod != NULL, "Lowering failed");

    VerificationResult vres = verify_module(mod);
    if (!vres.is_safe) {
        for (uint32_t i = 0; i < vres.error_count; i++) {
            fprintf(stderr, "Verification error in %s: %s\n", vres.errors[i].func_name, vres.errors[i].message);
        }
    }
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
    RUN_TEST(test_match_aggregate_bind);
    printf("[%2d/%2d] Match Aggregate Bind Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
