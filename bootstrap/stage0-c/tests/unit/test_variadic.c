#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include "surface_parser.h"
#include "surface_lower.h"
#include "verifier.h"
#include "diagnostics.h"
#include "il_print.h"
#include "qbe_emit.h"
#include "il_type.h"

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    const char* source = 
        "extern fn printf(fmt: *u8, ...) -> i32;\n"
        "\n"
        "fn main() -> i32 {\n"
        "    let x = 42;\n"
        "    let y = 3.14;\n"
        "    printf(\"Answer is %d and pi is %f\\n\", x, y);\n"
        "    return 0;\n"
        "}\n";

    printf("Testing variadic FFI lowering...\n");

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) {
        printf("Failed to parse module.\n");
        diag_render_terminal(diag);
        diag_report_destroy(diag);
        il_ctx_destroy(&ctx);
        return 1;
    }
    diag_report_destroy(diag);

    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        printf("Failed to lower module.\n");
        surface_mod_free(smod);
        il_ctx_destroy(&ctx);
        return 1;
    }

    char il_buf[16384];
    il_buf[0] = '\0';
    il_print_module(mod, il_buf, sizeof(il_buf));
    printf("--- IL ---\n%s\n", il_buf);

    VerificationResult res = verify_module(mod);
    if (!res.is_safe) {
        printf("IL Verification failed:\n");
        for (uint32_t i = 0; i < res.error_count; i++) {
            printf("  %s at block %u, instr %u\n", res.errors[i].message, res.errors[i].block_id, res.errors[i].instr_index);
        }
        verify_result_free(&res);
        il_mod_free(mod);
        surface_mod_free(smod);
        il_ctx_destroy(&ctx);
        return 1;
    }
    verify_result_free(&res);

    printf("--- QBE ---\n");
    qbe_emit_module(mod, stdout);

    // Verify ... is in the QBE output
    char qbe_buf[16384];
    FILE* mem_stream = fmemopen(qbe_buf, sizeof(qbe_buf), "w");
    if (mem_stream) {
        qbe_emit_module(mod, mem_stream);
        fclose(mem_stream);
        if (strstr(qbe_buf, "..., ")) {
            printf("Success: QBE output contains '..., '\n");
        } else {
            printf("FAILURE: QBE output missing '..., '\n");
            il_mod_free(mod);
            surface_mod_free(smod);
            il_ctx_destroy(&ctx);
            return 1;
        }
    }

    il_mod_free(mod);
    surface_mod_free(smod);
    printf("DONE\n");
    il_ctx_destroy(&ctx);
    return 0;
}
