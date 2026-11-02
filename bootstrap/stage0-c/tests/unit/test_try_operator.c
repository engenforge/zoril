#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "../include/surface_parser.h"
#include "../include/surface_lower.h"
#include "../include/il_print.h"
#include "../include/verifier.h"
#include "il_type.h"

/* Surface code using ? to propagate errors from a Result-returning call */
static const char* TRY_CODE =
    "enum Result {\n"
    "    Ok(i32),\n"
    "    Err(i32)\n"
    "}\n"
    "fn inner(x: i32) -> Result {\n"
    "    if x > 0 {\n"
    "        Result.Ok(x)\n"
    "    } else {\n"
    "        Result.Err(0)\n"
    "    }\n"
    "}\n"
    "fn process(x: i32) -> Result {\n"
    "    let v = inner(x)?;\n"
    "    Result.Ok(v + 1)\n"
    "}\n";

static bool test_try_parses(void) {
    SurfaceModule* smod = surface_parse_module(TRY_CODE, "test.zrl", NULL);
    if (!smod) return false;
    bool success = smod->function_count == 2;
    surface_mod_free(smod);
    return success;
}

static bool test_try_lowers(void) {
    SurfaceModule* smod = surface_parse_module(TRY_CODE, "test.zrl", NULL);
    if (!smod) return false;

    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) { surface_mod_free(smod); return false; }

    char il_buf[8192];
    il_print_module(mod, il_buf, sizeof(il_buf));
    printf("Generated IL:\n%s\n", il_buf);

    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

static bool test_try_verifies_safe(void) {
    SurfaceModule* smod = surface_parse_module(TRY_CODE, "test.zrl", NULL);
    if (!smod) return false;

    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) { surface_mod_free(smod); return false; }

    VerificationResult res = verify_module(mod);
    bool success = res.is_safe;
    if (!success) {
        for (uint32_t i = 0; i < res.error_count; i++) {
            fprintf(stderr, "Verifier error: %s (block %u, instr %u)\n",
                   res.errors[i].message, res.errors[i].block_id, res.errors[i].instr_index);
        }
    }
    verify_result_free(&res);
    il_mod_free(mod);
    surface_mod_free(smod);
    return success;
}

/* The ? operator on a non-Result type must fail gracefully (no crash) */
static bool test_try_on_non_result_is_graceful(void) {
    const char* bad_code =
        "fn process() -> i32 {\n"
        "    let v = 42?;\n"
        "    v\n"
        "}\n";

    SurfaceModule* smod = surface_parse_module(bad_code, "test.zrl", NULL);
    if (!smod) return true; /* parse failure is acceptable */

    ILModule* mod = surface_lower_module(smod, NULL, false);
    /* Lowering should fail gracefully (NULL or empty) rather than crash */
    if (mod) il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    int passed = 0, total = 0;
    #define RUN(fn) do { \
        total++; \
        if (fn()) { printf("[PASS] test_try_operator: " #fn "\n"); passed++; } \
        else        printf("[FAIL] test_try_operator: " #fn "\n"); \
    } while(0)

    RUN(test_try_parses);
    RUN(test_try_lowers);
    RUN(test_try_verifies_safe);
    RUN(test_try_on_non_result_is_graceful);

    #undef RUN
    printf("Results: %d/%d passed\n", passed, total);
    il_ctx_destroy(&ctx);
    return (passed == total) ? 0 : 1;
}
