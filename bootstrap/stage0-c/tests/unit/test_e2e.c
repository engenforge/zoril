#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "test_harness.h"
#include "il_type.h"
#include "il_instr.h"
#include "il_cfg.h"
#include "qbe_emit.h"
#include "verifier.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_e2e_pipeline(void) {
    if (!test_has_backend()) {
        static char reason[256];
        snprintf(reason, sizeof(reason), "backend (%s) not found", test_get_backend_bin());
        SKIP(reason);
    }

    const ILType * unit_type = il_type_unit();

    ILFunction* func = il_func_create_synthetic(1, "main", unit_type);
    ABORT_IF_NULL(func);

    ILBasicBlock* b1 = il_block_create(1);
    ABORT_IF_NULL(b1);
    
    ILValue ret_val = { .id = 0, .type = unit_type };
    ILInstruction* ret = il_build_return(ret_val);
    

    il_block_add_instr(b1, ret);
    il_func_add_block(func, b1);

    ILModule* mod = il_mod_create();
    il_mod_add_func(mod, func);

    VerificationResult vres = verify_module(mod);
    ASSERT(vres.is_safe, "Module should pass verification");
    verify_result_free(&vres);

    pid_t pid = getpid();
    char ssa_path[256], s_path[256], o_path[256], rt_path[256], bin_path[256];
    snprintf(ssa_path, sizeof(ssa_path), "../build/e2e_test_%d.ssa", (int)pid);
    snprintf(s_path, sizeof(s_path), "../build/e2e_test_%d.s", (int)pid);
    snprintf(o_path, sizeof(o_path), "../build/e2e_test_%d.o", (int)pid);
    snprintf(rt_path, sizeof(rt_path), "../build/e2e_test_rt_%d.o", (int)pid);
    snprintf(bin_path, sizeof(bin_path), "../build/e2e_test_%d_bin", (int)pid);

    FILE* out = fopen(ssa_path, "w");
    ABORT_IF_NULL(out);
    qbe_emit_module(mod, out);
    fclose(out);

    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "%s -o %s %s", test_get_backend_bin(), s_path, ssa_path);
    int res = system(cmd);
    ASSERT(res == 0, "backend compilation should succeed");

    const char* runtime_src = "../lib/rt/runtime.s";
    if (access(runtime_src, F_OK) != 0) runtime_src = "lib/rt/runtime.s";
    snprintf(cmd, sizeof(cmd), "%s -o %s %s && %s -o %s %s && %s -o %s %s %s",
             test_get_assembler_bin(), o_path, s_path, test_get_assembler_bin(), rt_path, runtime_src, test_get_linker_bin(), bin_path, o_path, rt_path);
    res = system(cmd);
    ASSERT(res == 0, "assembler and linker should succeed");

    res = system(bin_path);
    ASSERT(res != -1, "binary execution should succeed");

    remove(ssa_path);
    remove(s_path);
    remove(o_path);
    remove(rt_path);
    remove(bin_path);
    il_mod_free(mod);

    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_e2e_pipeline);
    printf("[%2d/%2d] End-to-end compilation pipeline\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == (tests_passed + tests_skipped)) ? 0 : 1;
}
