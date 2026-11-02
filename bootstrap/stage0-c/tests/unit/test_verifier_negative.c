#include <stdbool.h>
#include <stdio.h>
#include "test_harness.h"
#include "../include/il_read.h"
#include "../include/verifier.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool check_error(const char* src, VerifierErrorType expected_type, const char* label) {
    ILModule* mod = il_read_module(src, NULL);
    if (!mod) {
        fprintf(stderr, "[FAIL] %s: Failed to parse IL\n", label);
        return false;
    }
    
    VerificationResult res = verify_module(mod);
    bool found = false;
    if (!res.is_safe) {
        for (uint32_t i = 0; i < res.error_count; i++) {
            if (res.errors[i].type == expected_type) {
                found = true;
                break;
            }
        }
    }
    
    if (!found) {
        fprintf(stderr, "[FAIL] %s: Expected error %d but it was not found\n", label, expected_type);
        if (res.is_safe) fprintf(stderr, "  (Module was reported as SAFE)\n");
        else {
             for (uint32_t i = 0; i < res.error_count; i++) {
                 fprintf(stderr, "  (Found error type %d instead: %s)\n", res.errors[i].type, res.errors[i].message);
             }
        }
    }
    
    verify_result_free(&res);
    il_mod_free(mod);
    return found;
}

bool test_err_type_mismatch(void) {
    const char* src = 
        "f0: i32 main() {"
        "  @b0:"
        "    v1: i32 = const 10"
        "    v2: u32 = const 20"
        "    v3: i32 = add v1, v2" // Type mismatch
        "    ret v3"
        "}";
    return check_error(src, VERIFY_ERR_TYPE_MISMATCH, "VERIFY_ERR_TYPE_MISMATCH");
}

bool test_err_leak(void) {
    const char* src = 
        "f0: unit main() {"
        "  @b0:"
        "    v1: BoxMut<i32> = alloc 'heap, i32"
        "    v2: unit = const 0" // Dummy
        "    ret v2" // v1 leaked
        "}";
    return check_error(src, VERIFY_ERR_LEAK, "VERIFY_ERR_LEAK");
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_err_type_mismatch);
    RUN_TEST(test_err_leak);
    il_ctx_destroy(&ctx);
    return (tests_passed == tests_run) ? 0 : 1;
}
