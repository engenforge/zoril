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

static bool test_match_wildcard_not_last(void) {
    const char* src = 
        "enum Kind { A, B, C }\n"
        "fn check(k: Kind) -> i32 {\n"
        "    match k {\n"
        "        Kind.A => 1,\n"
        "        _ => 2,\n"
        "        Kind.C => 3,\n"
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
    
    // In the buggy version, arm 'Kind.C => 3' is ignored because of the preceding wildcard.
    // The Phi node would only have 2 incoming blocks (for A and wildcard).
    // We expect it to have 3 incoming blocks.
    
    // Search for the Phi node with 3 blocks
    // More precise check: count occurrences of "@b" in the first Phi line
    char* phi_line = strstr(ssa, "phi ");
    int b_count = 0;
    if (phi_line) {
        char* p = phi_line;
        while (*p && *p != '\n') {
            if (p[0] == '@' && p[1] == 'b') b_count++;
            p++;
        }
    }

    ASSERT(b_count == 3, "Match Phi should have 3 incoming blocks even with middle wildcard");

    free(ssa);
    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_match_wildcard_not_last);

    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
