#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "qbe_emit.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_unwrap_bool_width(void) {
    const char* src = 
        "enum State { Active(bool), Inactive }\n"
        "fn check(s: State) -> bool {\n"
        "    match s {\n"
        "        State.Active(b) => b,\n"
        "        State.Inactive => false,\n"
        "    }\n"
        "}\n";

    DiagnosticReport report = {0};
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", &report);
    ASSERT(smod != NULL, "Failed to parse module");
    ASSERT(!report.has_errors, "Parsing had errors");

    ILModule* mod = surface_lower_module(smod, &report, false);
    ASSERT(mod != NULL, "Failed to lower module");
    ASSERT(!report.has_errors, "Lowering had errors");

    FILE* tmp = tmpfile();
    ASSERT(tmp != NULL, "Failed to create temp file");
    qbe_emit_module(mod, tmp);
    
    long size = ftell(tmp);
    rewind(tmp);
    char* ssa = malloc((size_t)size + 1);
    ASSERT(fread(ssa, 1, (size_t)size, tmp) == (size_t)size, "Failed to read back SSA");
    ssa[size] = '\0';
    fclose(tmp);
    
    // In the buggy version, it uses 'loadw' for the bool payload:
    // We expect 'loadub' (unsigned byte) for a bool.
    // We search for "loadub %payload_ptr" or similar.
    
    ASSERT(strstr(ssa, "loadub") != NULL, "Should use loadub for bool payload");
    
    // To ensure no corruption, the specific unwrap of %payload_ptr5 (or whatever it is)
    // must NOT use loadw. Since we can't easily track the result ID in strstr, 
    // we'll just check that loadub exists. 
    // Actually, we can check for "loadw %payload_ptr" which should NOT exist.
    ASSERT(strstr(ssa, "loadw %payload_ptr") == NULL, "Should not use loadw for payload pointer");

    free(ssa);
    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_unwrap_bool_width);

    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
