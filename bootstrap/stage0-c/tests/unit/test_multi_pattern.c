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

static bool compile_source_fails(const char* name, const char* src, const char* expected_err) {
    char zrl_name[256];
    snprintf(zrl_name, sizeof(zrl_name), "neg_%s.zrl", name);
    char zrl_path[512];
    test_get_tmp_path(zrl_path, sizeof(zrl_path), zrl_name);

    char bin_name[256];
    snprintf(bin_name, sizeof(bin_name), "neg_%s_bin", name);
    char bin_path[512];
    test_get_tmp_path(bin_path, sizeof(bin_path), bin_name);

    char err_name[256];
    snprintf(err_name, sizeof(err_name), "neg_%s.err", name);
    char err_path[512];
    test_get_tmp_path(err_path, sizeof(err_path), err_name);

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
    snprintf(cmd, sizeof(cmd), "%s %s -o %s > %s 2>&1", zoril_bin, zrl_path, bin_path, err_path);
    int res = system(cmd);

    bool failed_as_expected = (res != 0);
    if (failed_as_expected && expected_err) {
        FILE* ef = fopen(err_path, "r");
        if (ef) {
            char buf[4096];
            size_t n = fread(buf, 1, sizeof(buf)-1, ef);
            buf[n] = '\0';
            fclose(ef);
            if (strstr(buf, expected_err) == NULL) {
                failed_as_expected = false;
                printf("Error message mismatch for %s. Expected: '%s', Got:\n%s\n", name, expected_err, buf);
            }
        } else {
            failed_as_expected = false;
        }
    }

    // Cleanup
    remove(zrl_path);
    remove(bin_path);
    remove(err_path);
    
    char ssa_path[512], s_path[512], o_path[512];
    snprintf(ssa_path, sizeof(ssa_path), "%s.ssa", bin_path);
    snprintf(s_path, sizeof(s_path), "%s.s", bin_path);
    snprintf(o_path, sizeof(o_path), "%s.o", bin_path);
    remove(ssa_path);
    remove(s_path);
    remove(o_path);

    return failed_as_expected;
}

static bool test_multi_pattern_different_payload_wildcards(void) {
    const char* src =
        "enum Foo { A(u32), B(u64), C([u8]) }\n"
        "fn check(f: Foo) -> bool {\n"
        "    return match f {\n"
        "        Foo.A(_) | Foo.B(_) | Foo.C(_) => true,\n"
        "    };\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    if !check(Foo.A(10 as u32)) { return 1; }\n"
        "    if !check(Foo.B(20 as u64)) { return 2; }\n"
        "    return 0;\n"
        "}\n";

    ASSERT(compile_source_and_run("multi_wild", src, 0), "Multi-pattern with different payload types (wildcards) should work");
    return true;
}

static bool test_multi_pattern_different_payload_mixed(void) {
    const char* src =
        "enum Foo { A(u32), B, C(u64) }\n"
        "fn check(f: Foo) -> bool {\n"
        "    return match f {\n"
        "        Foo.A(_) | Foo.B | Foo.C(_) => true,\n"
        "    };\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    if !check(Foo.B) { return 1; }\n"
        "    return 0;\n"
        "}\n";

    ASSERT(compile_source_and_run("multi_mixed", src, 0), "Multi-pattern with mixed payload and no-payload variants should work");
    return true;
}

static bool test_multi_pattern_binding_same_type(void) {
    const char* src =
        "enum Foo { A(u32), B(u32) }\n"
        "fn check(f: Foo) -> u32 {\n"
        "    return match f {\n"
        "        Foo.A(x) | Foo.B(x) => x,\n"
        "    };\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    if check(Foo.A(10 as u32)) != 10 as u32 { return 1; }\n"
        "    if check(Foo.B(20 as u32)) != 20 as u32 { return 2; }\n"
        "    return 0;\n"
        "}\n";

    ASSERT(compile_source_and_run("multi_bind", src, 0), "Multi-pattern with bindings of same type should work");
    return true;
}

static bool test_multi_pattern_negative_mismatches(void) {
    const char* diff_names =
        "enum Foo { A(u32), B(u32) }\n"
        "fn check(f: Foo) -> u32 {\n"
        "    return match f {\n"
        "        Foo.A(x) | Foo.B(y) => x,\n"
        "    };\n"
        "}\n";
    ASSERT(compile_source_fails("diff_names", diff_names, "Variable bindings in multi-pattern match must have the same name"), "Mismatched binding names should be rejected");

    const char* diff_types =
        "enum Foo { A(u32), B(u64) }\n"
        "fn check(f: Foo) -> u64 {\n"
        "    return match f {\n"
        "        Foo.A(x) | Foo.B(x) => x as u64,\n"
        "    };\n"
        "}\n";
    ASSERT(compile_source_fails("diff_types", diff_types, "Variable bindings in multi-pattern match must have the same type"), "Mismatched binding types should be rejected");

    const char* mixed_wild =
        "enum Foo { A(u32), B(u32) }\n"
        "fn check(f: Foo) -> u32 {\n"
        "    return match f {\n"
        "        Foo.A(x) | Foo.B(_) => 0,\n"
        "    };\n"
        "}\n";
    ASSERT(compile_source_fails("mixed_wild", mixed_wild, "mixed wildcard and named binding"), "Mixed wildcard and named binding should be rejected");

    return true;
}

int main(void) {
    printf("Running multi-pattern match tests...\n");
    test_multi_pattern_different_payload_wildcards();
    test_multi_pattern_different_payload_mixed();
    test_multi_pattern_binding_same_type();
    test_multi_pattern_negative_mismatches();
    
    printf("\nTest Summary: %d passed, %d failed\n", tests_passed, tests_run - tests_passed);
    return (tests_passed == tests_run) ? 0 : 1;
}
