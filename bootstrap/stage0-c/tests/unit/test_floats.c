#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "qbe_emit.h"
#include "diagnostics.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool run_float_test(const char* name, const char* src) {
    if (!test_has_backend()) {
        static char reason[256];
        snprintf(reason, sizeof(reason), "backend (%s) not available", test_get_backend_bin());
        SKIP(reason);
    }
    DiagnosticReport* report = diag_report_create();
    char zil_name[256];
    snprintf(zil_name, sizeof(zil_name), "%s.zil", name);
    SurfaceModule* mod = surface_parse_module(src, zil_name, report);
    if (!mod || report->count > 0) {
        diag_render_terminal(report);
        diag_report_destroy(report);
        return false;
    }

    ILModule* il_mod = surface_lower_module(mod, NULL, false);
    if (!il_mod) {
        surface_mod_free(mod);
        diag_report_destroy(report);
        return false;
    }

    char qbe_path[512], s_path[512], bin_path[512];
    test_get_tmp_path(qbe_path, sizeof(qbe_path), name);
    strcat(qbe_path, ".qbe");
    test_get_tmp_path(s_path, sizeof(s_path), name);
    strcat(s_path, ".s");
    test_get_tmp_path(bin_path, sizeof(bin_path), name);

    FILE* qbe_out = fopen(qbe_path, "w");
    if (!qbe_out) {
        perror("fopen");
        il_mod_free(il_mod);
        surface_mod_free(mod);
        diag_report_destroy(report);
        return false;
    }
    qbe_emit_module(il_mod, qbe_out);
    fclose(qbe_out);

    const char* runtime_src = "../lib/rt/runtime.s";
    if (access(runtime_src, F_OK) != 0) runtime_src = "lib/rt/runtime.s";
    char rt_o[512];
    snprintf(rt_o, sizeof(rt_o), "%s_rt.o", bin_path);
    char o_path[512];
    snprintf(o_path, sizeof(o_path), "%s.o", bin_path);
    
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "%s -o %s %s && %s -o %s %s && %s -o %s %s && %s -o %s %s %s && %s", 
             test_get_backend_bin(), s_path, qbe_path,
             test_get_assembler_bin(), o_path, s_path,
             test_get_assembler_bin(), rt_o, runtime_src,
             test_get_linker_bin(), bin_path, o_path, rt_o,
             bin_path);
    int ret = system(cmd);

    // Cleanup
    remove(qbe_path);
    remove(s_path);
    remove(bin_path);
    remove(o_path);
    remove(rt_o);

    il_mod_free(il_mod);
    surface_mod_free(mod);
    diag_report_destroy(report);

    return ret == 0;
}

static bool test_floats_basic(void) {
    const char* src = 
        "fn add_f64(a: f64, b: f64) -> f64 { return a + b; }\n"
        "fn main() -> i32 {\n"
        "  let x: f64 = 1.5;\n"
        "  let y: f64 = 2.5;\n"
        "  if (add_f64(x, y) == 4.0) { return 0; } else { return 1; }\n"
        "}\n";
    return run_float_test("test_floats_basic", src);
}

static bool test_floats_mixed(void) {
    const char* src = 
        "fn main() -> i32 {\n"
        "  let x: f64 = 42.5;\n"
        "  let y: i32 = @int_cast<i32>(x);\n"
        "  if (y == 42) { return 0; } else { return 1; }\n"
        "}\n";
    return run_float_test("test_floats_mixed", src);
}

static bool test_floats_globals(void) {
    const char* src = 
        "static PI: f64 = 3.14159;\n"
        "fn main() -> i32 {\n"
        "  if (PI > 3.0) { return 0; } else { return 1; }\n"
        "}\n";
    return run_float_test("test_floats_globals", src);
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_floats_basic);
    RUN_TEST(test_floats_mixed);
    RUN_TEST(test_floats_globals);
    il_ctx_destroy(&ctx);
    return (tests_run == (tests_passed + tests_skipped)) ? 0 : 1;
}
