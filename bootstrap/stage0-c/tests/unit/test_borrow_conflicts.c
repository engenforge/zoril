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

static bool test_assignment_sibling_borrow(void) {
    const char* src =
        "struct Counter { val: i32 }\n"
        "impl Counter {\n"
        "    fn inc(self: &mut Counter) {\n"
        "        self.val = self.val + 1;\n"
        "    }\n"
        "}\n";

    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parse should succeed");

    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Lowering should succeed");
    
    VerificationResult res = verify_module(mod);
    bool verified = res.is_safe;
    if (!verified) {
        for (uint32_t i = 0; i < res.error_count; i++) {
            printf("VERIFY ERROR in %s: %s\n", res.errors[i].func_name, res.errors[i].message);
        }
    }
    verify_result_free(&res);
    ASSERT(verified, "Module should pass verification");

    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

static bool test_compound_assignment_ssa(void) {
    const char* src =
        "fn main() -> i32 {\n"
        "    let mut x = 10;\n"
        "    x += 5;\n"
        "    return x;\n"
        "}\n";

    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parse should succeed");

    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Lowering should succeed");

    VerificationResult res = verify_module(mod);
    bool verified = res.is_safe;
    if (!verified) {
        for (uint32_t i = 0; i < res.error_count; i++) {
            printf("VERIFY ERROR in %s: %s\n", res.errors[i].func_name, res.errors[i].message);
        }
    }
    verify_result_free(&res);
    ASSERT(verified, "Module should pass verification");

    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

static bool test_compound_assignment_visibility(void) {
    const char* src =
        "fn main() -> i32 {\n"
        "    let mut x = 10;\n"
        "    x += 5;\n"
        "    let y = x;\n"
        "    if y != 15 { return 1; }\n"
        "    return 0;\n"
        "}\n";

    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parse should succeed");

    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Lowering should succeed");

    VerificationResult res = verify_module(mod);
    bool verified = res.is_safe;
    if (!verified) {
        for (uint32_t i = 0; i < res.error_count; i++) {
            printf("VERIFY ERROR in %s: %s\n", res.errors[i].func_name, res.errors[i].message);
        }
    }
    verify_result_free(&res);
    ASSERT(verified, "Module should pass verification");

    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_assignment_sibling_borrow);
    RUN_TEST(test_compound_assignment_ssa);
    RUN_TEST(test_compound_assignment_visibility);
    printf("[%2d/%2d] Borrow Conflict Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
