#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "verifier.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_string_literal_no_leak(void) {
    const char* src = 
        "fn main() -> i32 {\n"
        "    let msg = \"hello\";\n"
        "    return 0;\n"
        "}\n";
    
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Should parse module");
    
    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Should lower module");
    
    VerificationResult vres = verify_module(mod);
    bool is_safe = vres.is_safe;
    
    if (!is_safe) {
        for (uint32_t i = 0; i < vres.error_count; i++) {
            printf("  Error: %s\n", vres.errors[i].message);
        }
    }
    
    ASSERT(is_safe, "String literal should not be considered a leak (SliceMut<u8> is copyable)");
    
    verify_result_free(&vres);
    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_string_literal_no_leak);

    printf("[%2d/%2d] String literal leak test\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
