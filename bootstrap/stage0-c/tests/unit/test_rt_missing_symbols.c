#include "test_harness.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static bool test_missing_symbols(void) {
    const char* env_bin = getenv("ZORIL_BIN");
    const char* zoril_bin = NULL;
    if (env_bin && env_bin[0] && access(env_bin, F_OK) == 0) {
        zoril_bin = env_bin;
    } else if (access("build/zoril-c", F_OK) == 0) {
        zoril_bin = "build/zoril-c";
    } else if (access("../build/zoril-c", F_OK) == 0) {
        zoril_bin = "../build/zoril-c";
    }
    if (!zoril_bin) {
        SKIP("zoril compiler binary not found");
    }
    if (!test_has_backend()) {
        static char reason[256];
        snprintf(reason, sizeof(reason), "backend not available (%s)", test_get_backend_bin());
        SKIP(reason);
    }
    const char* src =
        "struct Data {\n"
        "    a: u64,\n"
        "    b: u64,\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let mut x = Data { a: 1, b: 2 };\n"
        "    let mut y = Data { a: 3, b: 4 };\n"
        "    x = y;\n"
        "    return 0 as i32;\n"
        "}\n";
    
    char zrl_path[512];
    test_get_tmp_path(zrl_path, sizeof(zrl_path), "missing.zrl");
    char ssa_path[512];
    test_get_tmp_path(ssa_path, sizeof(ssa_path), "missing_bin.ssa");
    char s_path[512];
    test_get_tmp_path(s_path, sizeof(s_path), "missing_bin.s");
    char bin_path[512];
    test_get_tmp_path(bin_path, sizeof(bin_path), "missing_bin");
    
    FILE* f = fopen(zrl_path, "w");
    fprintf(f, "%s", src);
    fclose(f);

    const char* include_path = access("lib/zoril", F_OK) == 0 ? "lib/zoril" : "../lib/zoril";
    const char* sys_s = access("lib/rt/sys_linux_x86_64.s", F_OK) == 0 ? "lib/rt/sys_linux_x86_64.s" : "../lib/rt/sys_linux_x86_64.s";
    char s_obj[512];
    test_get_tmp_path(s_obj, sizeof(s_obj), "missing_bin.o");
    char sys_obj[512];
    test_get_tmp_path(sys_obj, sizeof(sys_obj), "missing_sys.o");
    char cmd[2048];

    // We expect compiling against ONLY sys_linux_x86_64.s to FAIL without weak symbols,
    // or succeed if we add standard C library implementations or weak stubs.
    snprintf(cmd, sizeof(cmd), "%s -I %s --emit-ir %s -o %s > /dev/null 2>&1 && %s %s > %s && %s -o %s %s > /dev/null 2>&1 && %s -o %s %s > /dev/null 2>&1 && %s -o %s %s %s > /dev/null 2>&1",
             zoril_bin, include_path, zrl_path, ssa_path,
             test_get_backend_bin(), ssa_path, s_path,
             test_get_assembler_bin(), s_obj, s_path,
             test_get_assembler_bin(), sys_obj, sys_s,
             test_get_linker_bin(), bin_path, s_obj, sys_obj);
    int compile_res = system(cmd);

    // Cleanup
    remove(zrl_path);
    remove(bin_path);
    remove(ssa_path);
    remove(s_path);
    remove(s_obj);
    remove(sys_obj);
    
    if (WEXITSTATUS(compile_res) != 0) {
        fprintf(stderr, "Failed to compile against sys_linux_x86_64.s due to missing symbols.\n");
        return false;
    }
    
    return true;
}

int tests_run = 0;
int tests_passed = 0;

int main(void) {
    RUN_TEST(test_missing_symbols);
    printf("[%2d/%2d] Runtime missing symbols tests\n", tests_passed, tests_run);
    return (tests_run == (tests_passed + tests_skipped)) ? 0 : 1;
}
