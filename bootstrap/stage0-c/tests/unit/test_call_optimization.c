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

static bool test_call_arg_optimization(void) {
    const char* src =
        "struct Large { a: i32, b: i32, c: i32, d: i32, e: i32 }\n"
        "fn take_large(arg: Large) {}\n"
        "fn test_call() {\n"
        "    let l = Large { a: 1, b: 2, c: 3, d: 4, e: 5 };\n"
        "    take_large(l);\n"
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

    // Find test_call function in the output
    char* fn_start = strstr(buf, "export function $z_test_call");
    ASSERT(fn_start != NULL, "Should find test_call function");
    char* next_fn = strstr(fn_start + strlen("export function $z_test_call"), "function $");
    if (next_fn) *next_fn = '\0'; // Truncate to just this function

    // Count calls to $memcpy
    int memcpy_count = 0;
    char* p = fn_start;
    while ((p = strstr(p, "call $memcpy")) != NULL) {
        memcpy_count++;
        p += strlen("call $memcpy");
    }

    fprintf(stderr, "DEBUG: test_call has %d calls to $memcpy\n", memcpy_count);
    if (memcpy_count == 0) {
        fprintf(stderr, "DEBUG: Buffer content for test_call:\n%s\n", fn_start);
    }
    
    // GOAL: 0 memcpy operations.
    ASSERT(memcpy_count == 0, "Redundant memcpy operations should be elided");
    
    free(buf);
    il_mod_free(il_mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    il_ctx_destroy(&ctx);
    return true;
}

int main(void) {
    RUN_TEST(test_call_arg_optimization);
    return (tests_run == tests_passed) ? 0 : 1;
}
