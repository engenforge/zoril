#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "test_harness.h"

int tests_run = 0;
int tests_passed = 0;

static bool compile_source_and_run(const char* name, const char* src, int expected_exit) {
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
    snprintf(cmd, sizeof(cmd), "%s -I %s %s -o %s > /dev/null 2>&1", zoril_bin, include_path, zrl_path, bin_path);
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

static bool test_monomorphized_method_params(void) {
    const char* src =
        "struct Large {\n"
        "    pub a: u64,\n"
        "    pub b: u64,\n"
        "    pub c: u64,\n"
        "    pub d: u64,\n"
        "}\n"
        "struct Wrapper<T> { val: T }\n"
        "impl Wrapper<T> {\n"
        "    fn process(self: &Wrapper<T>, x: T, y: u64) -> Large {\n"
        "        // If parameter mapping is wrong, x or y might be misaligned/wrong types\n"
        "        return Large { a: y, b: y, c: y, d: y };\n"
        "    }\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let w = Wrapper { val: 42 };\n"
        "    // x is i32, y is u64. \n"
        "    // If mapping is off by 1, y might be read from x's register or vice versa.\n"
        "    let res = w.process(100, 7);\n"
        "    if res.a == 7 as u64 { return 0; }\n"
        "    return 1;\n"
        "}\n";

    ASSERT(compile_source_and_run("mono_param", src, 0), "Monomorphized method parameter mapping should be correct");
    return true;
}

static bool test_monomorphized_function_params(void) {
    const char* src =
        "struct Large {\n"
        "    pub a: u64,\n"
        "    pub b: u64,\n"
        "}\n"
        "fn generic_fn<T>(a: u64, b: T, c: u64) -> Large {\n"
        "    return Large { a: a, b: c };\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let res = generic_fn::<i32>(123, 456, 789);\n"
        "    if res.a != 123 as u64 { return 1; }\n"
        "    if res.b != 789 as u64 { return 2; }\n"
        "    return 0;\n"
        "}\n";

    ASSERT(compile_source_and_run("mono_fn_param", src, 0), "Monomorphized function parameter mapping should be correct");
    return true;
}

static bool test_monomorphized_many_params(void) {
    const char* src =
        "fn many_params<T>(a: u8, b: T, c: u16, d: T, e: u32, f: u64) -> u64 {\n"
        "    return a as u64 + c as u64 + e as u64 + f;\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let res = many_params::<bool>(1, true, 2, false, 3, 4);\n"
        "    if res == 10 as u64 { return 0; }\n"
        "    return 1;\n"
        "}\n";

    ASSERT(compile_source_and_run("mono_many_params", src, 0), "Monomorphized function with many params should work");
    return true;
}

static bool test_monomorphized_generic_return_aggregate(void) {
    const char* src =
        "struct Large { pub a: u64, pub b: u64 }\n"
        "struct Wrapper<T> { val: T }\n"
        "impl Wrapper<T> {\n"
        "    fn get(self: &Wrapper<T>) -> T {\n"
        "        return self.val;\n"
        "    }\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let w = Wrapper { val: Large { a: 1, b: 2 } };\n"
        "    let res = w.get();\n"
        "    if res.a == 1 as u64 { return 0; }\n"
        "    return 1;\n"
        "}\n";

    ASSERT(compile_source_and_run("mono_gen_ret_agg", src, 0), "Monomorphized method returning generic aggregate should work");
    return true;
}

int main(void) {
    printf("Running monomorphized parameter mapping tests...\n");
    test_monomorphized_method_params();
    test_monomorphized_function_params();
    test_monomorphized_many_params();
    test_monomorphized_generic_return_aggregate();
    
    printf("\nTest Summary: %d passed, %d failed\n", tests_passed, tests_run - tests_passed);
    return (tests_passed == tests_run) ? 0 : 1;
}
