#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_type.h"
#include "verifier.h"
#include "diagnostics.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_usize_isize_exists(void) {
    const char* src = 
        "fn main() -> i32 {\n"
        "    let x: usize = 10usize;\n"
        "    let y: isize = -5isize;\n"
        "    if x == 10usize && y == -5isize { 0 } else { 1 }\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        diag_render_terminal(report);
        diag_report_destroy(report);
        return false;
    }
    
    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(report);
        return false;
    }
    
    VerificationResult vres = verify_module(mod);
    bool ok = vres.is_safe;
    verify_result_free(&vres);
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return ok;
}

static bool test_usize_indexing(void) {
    const char* src = 
        "fn main() -> i32 {\n"
        "    let arr: [i32; 3] = [10, 20, 30];\n"
        "    let idx: usize = 1;\n"
        "    if arr[idx] == 20 { 0 } else { 1 }\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        diag_render_terminal(report);
        diag_report_destroy(report);
        return false;
    }
    
    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(report);
        return false;
    }
    
    VerificationResult vres = verify_module(mod);
    bool ok = vres.is_safe;
    verify_result_free(&vres);
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return ok;
}

static bool test_usize_isize_limits(void) {
    const char* src = 
        "fn main() -> i32 {\n"
        "    // 64-bit limits\n"
        "    let max_u: usize = 18446744073709551615usize;\n"
        "    let max_i: isize = 9223372036854775807isize;\n"
        "    let min_i: isize = -9223372036854775808isize;\n"
        "    if max_u > 0usize && max_i > 0isize && min_i < 0isize { 0 } else { 1 }\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        diag_render_terminal(report);
        diag_report_destroy(report);
        return false;
    }
    
    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(report);
        return false;
    }
    
    VerificationResult vres = verify_module(mod);
    bool ok = vres.is_safe;
    verify_result_free(&vres);
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return ok;
}

static bool test_usize_isize_conversions(void) {
    const char* src = 
        "fn main() -> i32 {\n"
        "    let u: usize = 42usize;\n"
        "    let i: isize = -42isize;\n"
        "    let a: u64 = u as u64;\n"
        "    let b: i64 = i as i64;\n"
        "    let c: u32 = u as u32;\n"
        "    let d: usize = a as usize;\n"
        "    let e: isize = b as isize;\n"
        "    if a == 42 && b == -42 && c == 42 && d == 42usize && e == -42isize { 0 } else { 1 }\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        diag_render_terminal(report);
        diag_report_destroy(report);
        return false;
    }
    
    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(report);
        return false;
    }
    
    VerificationResult vres = verify_module(mod);
    bool ok = vres.is_safe;
    verify_result_free(&vres);
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return ok;
}

static bool test_usize_sizeof_alignof(void) {
    const char* src = 
        "fn main() -> i32 {\n"
        "    let s_u = sizeof(usize);\n"
        "    let a_u = alignof(usize);\n"
        "    let s_i = sizeof(isize);\n"
        "    let a_i = alignof(isize);\n"
        "    if s_u == 8 && a_u == 8 && s_i == 8 && a_i == 8 { 0 } else { 1 }\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        diag_render_terminal(report);
        diag_report_destroy(report);
        return false;
    }
    
    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(report);
        return false;
    }
    
    VerificationResult vres = verify_module(mod);
    bool ok = vres.is_safe;
    verify_result_free(&vres);
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return ok;
}

static bool test_usize_isize_arith_overflow(void) {
    const char* src = 
        "fn main() -> i32 {\n"
        "    let a: usize = 18446744073709551614usize;\n"
        "    let b: usize = 1usize;\n"
        "    let c = a + b;\n"
        "    if c == 18446744073709551615usize { 0 } else { 1 }\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        diag_render_terminal(report);
        diag_report_destroy(report);
        return false;
    }
    
    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(report);
        return false;
    }
    
    VerificationResult vres = verify_module(mod);
    bool ok = vres.is_safe;
    verify_result_free(&vres);
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return ok;
}

static bool test_usize_as_array_type(void) {
    const char* src = 
        "struct Foo {\n"
        "    data: [i32; 10usize]\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let f = Foo { data: [0; 10usize] };\n"
        "    if f.data.len == 10usize { 0 } else { 1 }\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        diag_render_terminal(report);
        diag_report_destroy(report);
        return false;
    }
    
    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(report);
        return false;
    }
    
    VerificationResult vres = verify_module(mod);
    bool ok = vres.is_safe;
    verify_result_free(&vres);
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return ok;
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_usize_isize_exists);
    RUN_TEST(test_usize_indexing);
    RUN_TEST(test_usize_isize_limits);
    RUN_TEST(test_usize_isize_conversions);
    RUN_TEST(test_usize_sizeof_alignof);
    RUN_TEST(test_usize_isize_arith_overflow);
    RUN_TEST(test_usize_as_array_type);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
