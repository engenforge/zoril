#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "test_harness.h"
#include "il_read.h"
#include "qbe_emit.h"
#include "verifier.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_e2e_syscall(void) {
    if (!test_has_backend()) {
        static char reason[256];
        snprintf(reason, sizeof(reason), "backend (%s) not found", test_get_backend_bin());
        SKIP(reason);
    }
    if (!test_has_link_cc()) {
        static char reason[256];
        snprintf(reason, sizeof(reason), "GCC/Clang-compatible driver (%s) not available", test_get_link_cc_bin());
        SKIP(reason);
    }

        const char* sys_zil =
        "const global g1: [u8; 12] = { 84, 101, 115, 116, 32, 83, 121, 115, 99, 97, 108, 10 }\n"
        "f100: i64 sys_write(fd: u32, buf: Ptr<u8, 'a>, count: u64) {\n"
        "  @b0:\n"
        "    v4: i64 = syscall 1, v1, v2, v3\n"
        "    ret v4\n"
        "}\n"
        "f102: unit sys_exit(code: i32) {\n"
        "  @b0:\n"
        "    v2: u64 = syscall 60, v1\n"
        "    v3: unit = alloc 'local, unit\n"
        "    ret v3\n"
        "}\n"
        "f0: i32 do_hello(fd: u32, count: u64, code: i32) {\n"
        "  @b0:\n"
        "    v4: Ptr<[u8; 12], 'static> = global_addr g1\n"
        "    v5: Ptr<u8, 'static> = region_cast 'static, v4\n"
        "    v6: i64 = call 100(v1, v5, v2)\n"
        "    v7: unit = call 102(v3)\n"
        "    v8: i32 = alloc 'local, i32\n"
        "    ret v8\n"
        "}\n";

    ILModule* mod = il_read_module(sys_zil, NULL);
    ASSERT(mod != NULL, "Module parsing failed");

    VerificationResult vres = verify_module(mod);
    if (!vres.is_safe) {
        for (uint32_t i = 0; i < vres.error_count; i++) {
            printf("Verifier error: %s (block %u, instr %u)\n", vres.errors[i].message, vres.errors[i].block_id, vres.errors[i].instr_index);
        }
    }
    bool safe = vres.is_safe;
    verify_result_free(&vres);
    if (!safe) {
        il_mod_free(mod);
        return false;
    }

    pid_t pid = getpid();
    char ssa_path[256], cout_path[256], s_path[256], bin_path[256], out_path[256];
    snprintf(ssa_path, sizeof(ssa_path), "../build/e2e_syscall_%d.ssa", (int)pid);
    snprintf(cout_path, sizeof(cout_path), "../build/e2e_syscall_main_%d.c", (int)pid);
    snprintf(s_path, sizeof(s_path), "../build/e2e_syscall_%d.s", (int)pid);
    snprintf(bin_path, sizeof(bin_path), "../build/e2e_syscall_%d_bin", (int)pid);
    snprintf(out_path, sizeof(out_path), "../build/e2e_syscall_%d.out", (int)pid);

    FILE* out = fopen(ssa_path, "w");
    ABORT_IF_NULL(out);
    qbe_emit_module(mod, out);
    fclose(out);

    FILE* cout = fopen(cout_path, "w");
    ABORT_IF_NULL(cout);
    fprintf(cout, "#include <stdint.h>\nextern int32_t z_do_hello(uint32_t fd, uint64_t count, int32_t code);\nint main(void) { z_do_hello(1, 12, 0); return 0; }\n");
    fclose(cout);

    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "%s -o %s %s", test_get_backend_bin(), s_path, ssa_path);
    int res = system(cmd);
    ASSERT(res == 0, "backend compilation should succeed");

    // Link against the standard library runtime
    char link_cmd[1024];
    snprintf(link_cmd, sizeof(link_cmd), "%s -fno-stack-protector -o %s %s %s ../lib/rt/runtime.c ../lib/rt/sys_linux_x86_64.s", test_get_link_cc_bin(), bin_path, s_path, cout_path);
    res = system(link_cmd);
    ASSERT(res == 0, "link compilation should succeed");

    char run_cmd[1024];
    snprintf(run_cmd, sizeof(run_cmd), "%s > %s", bin_path, out_path);
    res = system(run_cmd);
    ASSERT(res == 0, "binary execution should succeed (exit 0)");

    // Clean up
    remove(ssa_path);
    remove(s_path);
    remove(bin_path);
    remove(out_path);
    remove(cout_path);
    il_mod_free(mod);

    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_e2e_syscall);
    printf("[%2d/%2d] End-to-end Syscall pipeline\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == (tests_passed + tests_skipped)) ? 0 : 1;
}
