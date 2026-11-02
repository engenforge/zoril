#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "qbe_emit.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_match_pressure_lower(void) {
    // This test ensures that a large match with many locals can at least be lowered
    // and emitted without the compiler crashing or producing invalid SSA.
    // Register corruption is hard to catch here, but we can verify the structure.
    const char* src =
        "enum Large {\n"
        "    V1(i64), V2(i64), V3(i64), V4(i64), V5(i64),\n"
        "    V6(i64), V7(i64), V8(i64), V9(i64), V10(i64)\n"
        "}\n"
        "fn work(a: i64, b: i64, c: i64, d: i64) -> i64 { return a + b + c + d; }\n"
        "fn test(v: Large) -> i64 {\n"
        "    let a = 1; let b = 2; let c = 3; let d = 4;\n"
        "    match v {\n"
        "        Large.V1(x) => work(x, a, b, c) + d,\n"
        "        Large.V2(x) => work(x, a, b, c) + d,\n"
        "        Large.V3(x) => work(x, a, b, c) + d,\n"
        "        Large.V4(x) => work(x, a, b, c) + d,\n"
        "        Large.V5(x) => work(x, a, b, c) + d,\n"
        "        Large.V6(x) => work(x, a, b, c) + d,\n"
        "        Large.V7(x) => work(x, a, b, c) + d,\n"
        "        Large.V8(x) => work(x, a, b, c) + d,\n"
        "        Large.V9(x) => work(x, a, b, c) + d,\n"
        "        Large.V10(x) => work(x, a, b, c) + d,\n"
        "    }\n"
        "}\n";

    DiagnosticReport report = {0};
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", &report);
    ASSERT(smod != NULL, "Failed to parse");
    
    ILModule* mod = surface_lower_module(smod, &report, false);
    ASSERT(mod != NULL, "Failed to lower");
    ASSERT(!report.has_errors, "Lowering had errors");

    char* buf = NULL;
    size_t size = 0;
    FILE* out = open_memstream(&buf, &size);
    qbe_emit_module(mod, out);
    fclose(out);

    // Basic sanity check: should have many call instructions
    int call_count = 0;
    char* p = buf;
    while ((p = strstr(p, "call $z_work")) != NULL) {
        call_count++;
        p += 1;
    }
    ASSERT(call_count == 10, "Should have 10 calls to work");

    free(buf);
    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

int main(void) {
    RUN_TEST(test_match_pressure_lower);
    return (tests_run == tests_passed) ? 0 : 1;
}
