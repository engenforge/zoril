#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_print.h"
#include "verifier.h"
#include "diagnostics.h"
#include "il_type.h"

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    const char* source = 
        "fn main() -> i32 {\n"
        "    let x = if true { 1 } else { 2 };\n"
        "    let y = if false { 3 } else if true { 4 } else { 5 };\n"
        "    return x + y;\n"
        "}\n";

    printf("Testing if-expressions and PHI nodes...\n");

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* mod = surface_parse_module(source, "test.zrl", diag);
    if (!mod) {
        printf("Failed to parse module.\n");
        diag_render_terminal(diag);
        diag_report_destroy(diag);
        return 1;
    }
    diag_report_destroy(diag);

    ILModule* il_mod = surface_lower_module(mod, NULL, false);
    if (!il_mod) {
        printf("Failed to lower module.\n");
        surface_mod_free(mod);
        il_ctx_destroy(&ctx);
        return 1;
    }

    VerificationResult res = verify_module(il_mod);
    if (!res.is_safe) {
        printf("IL Verification failed.\n");
        verify_result_free(&res);
        il_mod_free(il_mod);
        surface_mod_free(mod);
        il_ctx_destroy(&ctx);
        return 1;
    }
    verify_result_free(&res);

    printf("[PASS] test_simple_if\n");

    il_mod_free(il_mod);
    surface_mod_free(mod);
    il_ctx_destroy(&ctx);
    return 0;
}
