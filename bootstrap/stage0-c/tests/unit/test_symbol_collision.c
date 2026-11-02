#include "il_cfg.h"
#include "surface_lower.h"
#include "surface_parser.h"
#include "surface_ast.h"
#include "il_type.h"
#include "il_instr.h"
#include "qbe_emit.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_memcpy_collision(void) {
    const char* src =
        "pub fn memcpy(dest: *mut u8, src: *u8, n: u64) {\n"
        "    // user implementation\n"
        "}\n"
        "struct Large { a: u64, b: u64, c: u64, d: u64, e: u64 }\n"
        "fn test(dest: &mut Large, src: Large) {\n"
        "    *dest = src;\n"
        "}\n";

    ILContext ctx;
    il_ctx_init(&ctx);
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parse should succeed");

    ILModule* il_mod = surface_lower_module(smod, report, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");

    // Capture QBE output to a buffer
    char* buf = NULL;
    size_t size = 0;
    FILE* out = open_memstream(&buf, &size);
    
    qbe_emit_module(il_mod, out);
    fclose(out);

    // We expect BOTH $z_memcpy (the user function) and $memcpy (the compiler call)
    // Actually, currently it would emit BOTH as $memcpy, which is the bug.
    
    bool found_z_memcpy = (strstr(buf, "export function $z_memcpy") != NULL);
    bool found_call_memcpy = (strstr(buf, "call $memcpy") != NULL);
    bool found_direct_memcpy_export = (strstr(buf, "export function $memcpy") != NULL);

    fprintf(stderr, "DEBUG: found_z_memcpy=%d, found_call_memcpy=%d, found_direct_memcpy_export=%d\n", 
            found_z_memcpy, found_call_memcpy, found_direct_memcpy_export);

    // The fix should ensure user function is $z_memcpy
    ASSERT(found_z_memcpy, "User memcpy should be mangled to $z_memcpy");
    ASSERT(!found_direct_memcpy_export, "User memcpy should NOT be exported as $memcpy");
    ASSERT(found_call_memcpy, "Compiler should still call $memcpy for aggregates");

    free(buf);
    il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    il_ctx_destroy(&ctx);
    return true;
}

int main(void) {
    RUN_TEST(test_memcpy_collision);
    return (tests_run == tests_passed) ? 0 : 1;
}
