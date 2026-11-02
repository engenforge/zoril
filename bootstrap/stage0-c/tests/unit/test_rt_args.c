#include "test_harness.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static bool test_clobbered_args(void) {
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
    const char* src =
        "extern fn __zoril_syscall_3(sysno: i64, a: i64, b: i64, c: i64) -> i64;\n"
        "fn main(argc: i64, argv: *u64) -> i32 {\n"
        "    if argc < 1 as i64 {\n"
        "        let failure1 = \"FAILURE: argc is less than 1\\n\";\n"
        "        __zoril_syscall_3(1 as i64, 1 as i64, &failure1[0] as *u8 as i64, 29 as i64);\n"
        "        return 1;\n"
        "    }\n"
        "    let program_name_ptr = *argv;\n"
        "    if program_name_ptr as u64 == 0 as u64 {\n"
        "        let failure2 = \"FAILURE: argv[0] is null\\n\";\n"
        "        __zoril_syscall_3(1 as i64, 1 as i64, &failure2[0] as *u8 as i64, 25 as i64);\n"
        "        return 1;\n"
        "    }\n"
        "    let success = \"SUCCESS: argc/argv preserved\\n\";\n"
        "    __zoril_syscall_3(1 as i64, 1 as i64, &success[0] as *u8 as i64, 29 as i64);\n"
        "    return 0;\n"
        "}\n";
    
    char zrl_path[512];
    test_get_tmp_path(zrl_path, sizeof(zrl_path), "args.zrl");
    char bin_path[512];
    test_get_tmp_path(bin_path, sizeof(bin_path), "args_bin");
    
    FILE* f = fopen(zrl_path, "w");
    fprintf(f, "%s", src);
    fclose(f);

    const char* include_path = access("lib/zoril", F_OK) == 0 ? "lib/zoril" : "../lib/zoril";
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "%s -I %s %s -o %s > /dev/null 2>&1", zoril_bin, include_path, zrl_path, bin_path);
    if (system(cmd) != 0) {
        // Compilation failed, but we'll catch it with the run failure
    }
    
    char run_cmd[1024];
    snprintf(run_cmd, sizeof(run_cmd), "%s test_arg", bin_path);
    FILE* pipe = popen(run_cmd, "r");
    char output[4096] = {0};
    int res = -1;
    if (pipe) {
        if (fread(output, 1, sizeof(output)-1, pipe) == 0) {
            // Empty output or error
        }
        res = pclose(pipe);
    }

    // Cleanup
    remove(zrl_path);
    remove(bin_path);
    
    char ssa_path[512], s_path[512], o_path[512];
    snprintf(ssa_path, sizeof(ssa_path), "%s.ssa", bin_path);
    snprintf(s_path, sizeof(s_path), "%s.s", bin_path);
    snprintf(o_path, sizeof(o_path), "%s.o", bin_path);
    remove(ssa_path);
    remove(s_path);
    remove(o_path);
    
    if (WEXITSTATUS(res) != 0 || strstr(output, "SUCCESS") == NULL) {
        fprintf(stderr, "Failed with exit %d. Output: %s\n", WEXITSTATUS(res), output);
        return false;
    }
    
    return true;
}

int tests_run = 0;
int tests_passed = 0;

int main(void) {
    RUN_TEST(test_clobbered_args);
    printf("[%2d/%2d] Runtime tests\n", tests_passed, tests_run);
    return (tests_run == (tests_passed + tests_skipped)) ? 0 : 1;
}
