#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "qbe_emit.h"
#include "verifier.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_slice_copy_e2e(void) {
    if (!test_has_backend()) {
        static char reason[256];
        snprintf(reason, sizeof(reason), "backend (%s) not found", test_get_backend_bin());
        SKIP(reason);
    }

    const char* source = 
        "fn sys_write(fd: u64, buf: &[u8]) -> i64 {\n"
        "    return @syscall(1, fd, buf.ptr, buf.len);\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let msg = \"Hello slice\\n\";\n"
        "    let msg2 = msg;\n" // This triggers a slice load/copy
        "    sys_write(1, msg2);\n"
        "    return 0;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test_slice.zrl", diag);
    ASSERT(smod != NULL, "Parse failed");

    ILModule* mod = surface_lower_module(smod, diag, false);
    ASSERT(mod != NULL, "Lowering failed");

    VerificationResult vres = verify_module(mod);
    ASSERT(vres.is_safe, "Verifier failed");
    verify_result_free(&vres);

    pid_t pid = getpid();
    char ssa_path[256], s_path[256], o_path[256], rt_path[256], bin_path[256];
    snprintf(ssa_path, sizeof(ssa_path), "../build/test_slice_e2e_%d.ssa", (int)pid);
    snprintf(s_path, sizeof(s_path), "../build/test_slice_e2e_%d.s", (int)pid);
    snprintf(o_path, sizeof(o_path), "../build/test_slice_e2e_%d.o", (int)pid);
    snprintf(rt_path, sizeof(rt_path), "../build/test_slice_rt_%d.o", (int)pid);
    snprintf(bin_path, sizeof(bin_path), "../build/test_slice_e2e_%d_bin", (int)pid);

    FILE* out = fopen(ssa_path, "w");
    ABORT_IF_NULL(out);
    qbe_emit_module(mod, out);
    fclose(out);

    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "%s -o %s %s", test_get_backend_bin(), s_path, ssa_path);
    int res = system(cmd);
    ASSERT(res == 0, "backend compilation failed");

    // Link against runtime
    const char* runtime_src = "../lib/rt/runtime.s";
    if (access(runtime_src, F_OK) != 0) runtime_src = "lib/rt/runtime.s";
    char link_cmd[1024];
    snprintf(link_cmd, sizeof(link_cmd), "%s -o %s %s && %s -o %s %s && %s -o %s %s %s",
             test_get_assembler_bin(), o_path, s_path, test_get_assembler_bin(), rt_path, runtime_src, test_get_linker_bin(), bin_path, o_path, rt_path);
    res = system(link_cmd);
    ASSERT(res == 0, "link failed");

    char run_cmd[1024];
    snprintf(run_cmd, sizeof(run_cmd), "%s > /dev/null", bin_path);
    res = system(run_cmd);
    ASSERT(res == 0, "Execution failed (likely SIGSEGV)");

    remove(ssa_path);
    remove(s_path);
    remove(o_path);
    remove(rt_path);
    remove(bin_path);

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

static bool test_slice_index_pass_by_ref(void) {
    if (!test_has_backend()) {
        static char reason[256];
        snprintf(reason, sizeof(reason), "backend (%s) not found", test_get_backend_bin());
        SKIP(reason);
    }

    const char* source =
        "struct Large { a: u64, b: u64, c: u64 }\n"
        "struct Buffer { b0: u64, b1: u64, b2: u64, b3: u64, b4: u64, b5: u64 }\n"
        "fn take(val: Large) -> u64 {\n"
        "    return val.b;\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let mut buf = Buffer { b0: 10, b1: 20, b2: 30, b3: 40, b4: 50, b5: 60 };\n"
        "    let s = @slice(&mut buf as *mut Large, 2 as usize);\n"
        "    let r = take(s[1]);\n"
        "    if r != 50 { return 1; }\n"
        "    return 0;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test_slice_index_pass_by_ref.zrl", diag);
    ASSERT(smod != NULL, "Parse failed");

    ILModule* mod = surface_lower_module(smod, diag, false);
    ASSERT(mod != NULL, "Lowering failed");

    VerificationResult vres = verify_module(mod);
    ASSERT(vres.is_safe, "Verifier failed");
    verify_result_free(&vres);

    pid_t pid = getpid();
    char ssa_path[256], s_path[256], o_path[256], rt_path[256], bin_path[256];
    snprintf(ssa_path, sizeof(ssa_path), "../build/test_slice_idx_e2e_%d.ssa", (int)pid);
    snprintf(s_path, sizeof(s_path), "../build/test_slice_idx_e2e_%d.s", (int)pid);
    snprintf(o_path, sizeof(o_path), "../build/test_slice_idx_e2e_%d.o", (int)pid);
    snprintf(rt_path, sizeof(rt_path), "../build/test_slice_idx_rt_%d.o", (int)pid);
    snprintf(bin_path, sizeof(bin_path), "../build/test_slice_idx_e2e_%d_bin", (int)pid);

    FILE* out = fopen(ssa_path, "w");
    ABORT_IF_NULL(out);
    qbe_emit_module(mod, out);
    fclose(out);

    char cmd2[1024];
    snprintf(cmd2, sizeof(cmd2), "%s -o %s %s", test_get_backend_bin(), s_path, ssa_path);
    int res = system(cmd2);
    ASSERT(res == 0, "backend compilation failed");

    const char* runtime_src2 = "../lib/rt/runtime.s";
    if (access(runtime_src2, F_OK) != 0) runtime_src2 = "lib/rt/runtime.s";
    char link_cmd2[1024];
    snprintf(link_cmd2, sizeof(link_cmd2), "%s -o %s %s && %s -o %s %s && %s -o %s %s %s",
             test_get_assembler_bin(), o_path, s_path, test_get_assembler_bin(), rt_path, runtime_src2, test_get_linker_bin(), bin_path, o_path, rt_path);
    res = system(link_cmd2);
    ASSERT(res == 0, "link failed");

    char run_cmd2[1024];
    snprintf(run_cmd2, sizeof(run_cmd2), "%s > /dev/null", bin_path);
    res = system(run_cmd2);
    ASSERT(res == 0, "Execution failed");

    remove(ssa_path);
    remove(s_path);
    remove(o_path);
    remove(rt_path);
    remove(bin_path);

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_slice_copy_e2e);
    RUN_TEST(test_slice_index_pass_by_ref);
    printf("[%2d/%2d] Slice End-to-End Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == (tests_passed + tests_skipped)) ? 0 : 1;
}
