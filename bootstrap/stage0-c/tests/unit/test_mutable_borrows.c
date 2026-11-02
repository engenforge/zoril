#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include "surface_parser.h"
#include "surface_lower.h"
#include "verifier.h"
#include "diagnostics.h"
#include "il_print.h"
#include "il_type.h"

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    const char* source = 
        "struct Point { x: i32, y: i32 }\n"
        "fn main() -> i32 {\n"
        "    let mut p = Point { x: 10, y: 20 };\n"
        "    let px = &mut p.x;\n"
        "    *px = 30;\n"
        "    \n"
        "    let mut x = 40;\n"
        "    let rx = &mut x;\n"
        "    *rx = 50;\n"
        "    \n"
        "    return p.x + x;\n" // Should be 30 + 50 = 80
        "}\n";

    printf("Testing mutable borrows...\n");

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
        return 1;
    }

    VerificationResult res = verify_module(il_mod);
    if (!res.is_safe) {
        printf("IL Verification failed:\n");
        char il_buf[16384];
        il_buf[0] = '\0';
        il_print_module(il_mod, il_buf, sizeof(il_buf));
        printf("%s\n", il_buf);
        for (uint32_t i = 0; i < res.error_count; i++) {
            printf("  %s at block %u, instr %u\n", res.errors[i].message, res.errors[i].block_id, res.errors[i].instr_index);
        }
        verify_result_free(&res);
        il_mod_free(il_mod);
        surface_mod_free(mod);
        return 1;
    }
    verify_result_free(&res);

    printf("[PASS] test_mutable_borrows\n");

    il_mod_free(il_mod);
    surface_mod_free(mod);
    il_ctx_destroy(&ctx);
    return 0;
}
