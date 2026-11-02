#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "il_read.h"
#include "il_type.h"
#include "verifier.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_syscall_reading(void) {
    const char* il = 
        "f0: u64 my_syscall(fd: u32) {\n"
        "  @b0:\n"
        "    v2: u64 = syscall 1, v1\n"
        "    ret v2\n"
        "}\n";
    
    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should read module with syscall");
    
    VerificationResult res = verify_module(mod);
    ASSERT(res.is_safe, "Module should be safe");
    verify_result_free(&res);

    il_mod_free(mod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_syscall_reading);

    printf("[%2d/%2d] System Call layer\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
