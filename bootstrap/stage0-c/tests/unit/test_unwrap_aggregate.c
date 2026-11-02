#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "test_harness.h"

int tests_run = 0;
int tests_passed = 0;

static bool compile_source_and_run(const char* name, const char* src, int expected_exit, bool use_core) {
    char zrl_name[256];
    snprintf(zrl_name, sizeof(zrl_name), "%s.zrl", name);
    char zrl_path[512];
    test_get_tmp_path(zrl_path, sizeof(zrl_path), zrl_name);

    char bin_name[256];
    snprintf(bin_name, sizeof(bin_name), "%s_bin", name);
    char bin_path[512];
    test_get_tmp_path(bin_path, sizeof(bin_path), bin_name);

    FILE* f = fopen(zrl_path, "w");
    if (!f) return false;
    fprintf(f, "%s", src);
    fclose(f);

    const char* zoril_bin = NULL;
    if (access("../build/zoril-c", F_OK) == 0) zoril_bin = "../build/zoril-c";
    else if (access("../../build/zoril-c", F_OK) == 0) zoril_bin = "../../build/zoril-c";
    else if (access("../../../build/zoril-c", F_OK) == 0) zoril_bin = "../../../build/zoril-c";
    
    if (!zoril_bin) {
        remove(zrl_path);
        return false;
    }

    char cmd[1024];
    const char* include_path = access("lib/zoril", F_OK) == 0 ? "lib/zoril" : "../lib/zoril";
    if (use_core) {
        snprintf(cmd, sizeof(cmd), "%s -I %s %s -o %s > /dev/null 2>&1", zoril_bin, include_path, zrl_path, bin_path);
    } else {
        snprintf(cmd, sizeof(cmd), "%s -I %s %s -o %s > /dev/null 2>&1", zoril_bin, include_path, zrl_path, bin_path);
    }
    int res = system(cmd);

    if (res != 0) {
        remove(zrl_path);
        return false;
    }

    int ret = system(bin_path);
    
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

    if (!WIFEXITED(ret)) return false;
    return WEXITSTATUS(ret) == expected_exit;
}

static bool test_unwrap_large_struct(void) {
    const char* src =
        "struct Large {\n"
        "    pub a: u64,\n"
        "    pub b: u64,\n"
        "    pub c: u64,\n"
        "    pub d: u64,\n"
        "}\n"
        "enum Container {\n"
        "    Payload(Large),\n"
        "    Empty,\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let l = Large { a: 1, b: 2, c: 3, d: 4 };\n"
        "    let c = Container.Payload(l);\n"
        "    \n"
        "    match c {\n"
        "        Container.Payload(p) => {\n"
        "            if p.a != 1 as u64 { return 1; }\n"
        "            if p.b != 2 as u64 { return 2; }\n"
        "            if p.c != 3 as u64 { return 3; }\n"
        "            if p.d != 4 as u64 { return 4; }\n"
        "            return 0;\n"
        "        },\n"
        "        _ => return 5,\n"
        "    }\n"
        "}\n";

    ASSERT(compile_source_and_run("unwrap_agg", src, 0, false), "Unwrap of aggregate variant should work");
    return true;
}

static bool test_unwrap_aggregate_param(void) {
    const char* src =
        "struct Large {\n"
        "    pub a: u64,\n"
        "    pub b: u64,\n"
        "    pub c: u64,\n"
        "    pub d: u64,\n"
        "}\n"
        "fn take_option(o: Option<Large>) -> u64 {\n"
        "    let p = o.unwrap();\n"
        "    return p.a + p.b + p.c + p.d;\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let l = Large { a: 1, b: 2, c: 3, d: 4 };\n"
        "    let o = Option.Some(l);\n"
        "    let res = take_option(o);\n"
        "    if res == 10 as u64 { return 0; }\n"
        "    return 1;\n"
        "}\n";

    ASSERT(compile_source_and_run("unwrap_agg_param", src, 0, true), "Unwrap of aggregate payload from parameter should work");
    return true;
}

static bool test_unwrap_result_aggregate(void) {
    const char* src =
        "struct Large {\n"
        "    pub a: u64,\n"
        "    pub b: u64,\n"
        "}\n"
        "fn get_result(b: bool) -> Result<Large, u64> {\n"
        "    if b {\n"
        "        return Result.Ok(Large { a: 10, b: 20 });\n"
        "    } else {\n"
        "        return Result.Err(50 as u64);\n"
        "    }\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let r = get_result(true);\n"
        "    if r.is_err() { return 1; }\n"
        "    let p = match r {\n"
        "        Result.Ok(val) => val,\n"
        "        _ => Large { a: 0, b: 0 },\n"
        "    };\n"
        "    if p.a != 10 as u64 { return 2; }\n"
        "    if p.b != 20 as u64 { return 3; }\n"
        "    return 0;\n"
        "}\n";

    ASSERT(compile_source_and_run("unwrap_result_agg", src, 0, true), "Unwrap of Result aggregate payload should work");
    return true;
}

int main(void) {
    printf("Running unwrap_aggregate tests...\n");
    test_unwrap_large_struct();
    test_unwrap_aggregate_param();
    test_unwrap_result_aggregate();
    
    printf("\nTest Summary: %d passed, %d failed\n", tests_passed, tests_run - tests_passed);
    return (tests_passed == tests_run) ? 0 : 1;
}
