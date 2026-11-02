#include "verifier.h"
#include "il_cfg.h"
#include "qbe_emit.h"
#include "surface_ast.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "diagnostics.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static void cleanup(SurfaceModule* smod, ILModule* mod, DiagnosticReport* report) {
    if (mod) il_mod_free(mod);
    if (smod) surface_mod_free(smod);
    if (report) diag_report_destroy(report);
}

static bool test_private_struct_field_access(void) {
    const char* lib_src = 
        "struct Data { pub a: i32, b: i32 }\n";
    const char* main_src = 
        "import \"lib.zrl\";\n"
        "fn main() -> i32 {\n"
        "    let d = Data { a: 1, b: 2 };\n"
        "    return d.b;\n" // Error: 'b' is private
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* lib_mod = surface_parse_module(lib_src, "lib.zrl", report);
    SurfaceModule* main_mod = surface_parse_module(main_src, "main.zrl", report);
    if (lib_mod) lib_mod->file_path = "lib.zrl";
    if (main_mod) main_mod->file_path = "main.zrl";
    
    if (!lib_mod || !main_mod) {
        if (lib_mod) surface_mod_free(lib_mod);
        if (main_mod) surface_mod_free(main_mod);
        diag_report_destroy(report);
        ASSERT(false, "Parse failed");
    }

    surface_mod_merge(main_mod, lib_mod);
    surface_mod_free(lib_mod);
    ILModule* mod = surface_lower_module(main_mod, report, false);

    bool found_error = false;
    for (uint32_t i = 0; i < report->count; i++) {
        if (report->diagnostics[i].severity == DIAG_ERROR && 
            strstr(report->diagnostics[i].message, "private")) {
            found_error = true;
            break;
        }
    }

    cleanup(main_mod, mod, report);
    ASSERT(found_error, "Should report error for private field access");
    return true;
}

static bool test_private_method_access(void) {
    const char* lib_src = 
        "struct Data { x: i32 }\n"
        "impl Data {\n"
        "    pub fn new() -> Data { return Data { x: 0 }; }\n"
        "    fn private_method(self: &Data) -> i32 { return self.x; }\n"
        "}\n";
    const char* main_src = 
        "import \"lib.zrl\";\n"
        "fn main() -> i32 {\n"
        "    let d = Data.new();\n"
        "    return d.private_method();\n" // Error: private_method is private
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* lib_mod = surface_parse_module(lib_src, "lib.zrl", report);
    SurfaceModule* main_mod = surface_parse_module(main_src, "main.zrl", report);
    if (lib_mod) lib_mod->file_path = "lib.zrl";
    if (main_mod) main_mod->file_path = "main.zrl";
    
    if (!lib_mod || !main_mod) {
        if (lib_mod) surface_mod_free(lib_mod);
        if (main_mod) surface_mod_free(main_mod);
        diag_report_destroy(report);
        ASSERT(false, "Parse failed");
    }

    surface_mod_merge(main_mod, lib_mod);
    surface_mod_free(lib_mod);
    ILModule* mod = surface_lower_module(main_mod, report, false);

    bool found_error = false;
    for (uint32_t i = 0; i < report->count; i++) {
        if (report->diagnostics[i].severity == DIAG_ERROR && 
            strstr(report->diagnostics[i].message, "private")) {
            found_error = true;
            break;
        }
    }

    cleanup(main_mod, mod, report);
    ASSERT(found_error, "Should report error for private method access");
    return true;
}

static bool test_private_function_access(void) {
    const char* lib_src = 
        "fn private_fn() -> i32 { return 42; }\n"
        "pub fn public_fn() -> i32 { return private_fn(); }\n";
    const char* main_src = 
        "import \"lib.zrl\";\n"
        "fn main() -> i32 {\n"
        "    return private_fn();\n" // Error: private_fn is private
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* lib_mod = surface_parse_module(lib_src, "lib.zrl", report);
    SurfaceModule* main_mod = surface_parse_module(main_src, "main.zrl", report);
    if (lib_mod) lib_mod->file_path = "lib.zrl";
    if (main_mod) main_mod->file_path = "main.zrl";
    
    if (!lib_mod || !main_mod) {
        if (lib_mod) surface_mod_free(lib_mod);
        if (main_mod) surface_mod_free(main_mod);
        diag_report_destroy(report);
        ASSERT(false, "Parse failed");
    }

    surface_mod_merge(main_mod, lib_mod);
    surface_mod_free(lib_mod);
    ILModule* mod = surface_lower_module(main_mod, report, false);

    bool found_error = false;
    for (uint32_t i = 0; i < report->count; i++) {
        if (report->diagnostics[i].severity == DIAG_ERROR && 
            strstr(report->diagnostics[i].message, "private")) {
            found_error = true;
            break;
        }
    }

    cleanup(main_mod, mod, report);
    ASSERT(found_error, "Should report error for private function access");
    return true;
}

static bool test_private_global_access(void) {
    const char* lib_src = 
        "static mut private_g: i32 = 0;\n"
        "pub static mut public_g: i32 = 0;\n";
    const char* main_src = 
        "import \"lib.zrl\";\n"
        "fn main() -> i32 {\n"
        "    return private_g;\n" // Error: private_g is private
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* lib_mod = surface_parse_module(lib_src, "lib.zrl", report);
    SurfaceModule* main_mod = surface_parse_module(main_src, "main.zrl", report);
    if (lib_mod) lib_mod->file_path = "lib.zrl";
    if (main_mod) main_mod->file_path = "main.zrl";
    
    if (!lib_mod || !main_mod) {
        if (lib_mod) surface_mod_free(lib_mod);
        if (main_mod) surface_mod_free(main_mod);
        diag_report_destroy(report);
        ASSERT(false, "Parse failed");
    }

    surface_mod_merge(main_mod, lib_mod);
    surface_mod_free(lib_mod);
    ILModule* mod = surface_lower_module(main_mod, report, false);

    bool found_error = false;
    for (uint32_t i = 0; i < report->count; i++) {
        if (report->diagnostics[i].severity == DIAG_ERROR && 
            strstr(report->diagnostics[i].message, "private")) {
            found_error = true;
            break;
        }
    }

    cleanup(main_mod, mod, report);
    ASSERT(found_error, "Should report error for private global access");
    return true;
}

static bool test_private_type_access(void) {
    const char* lib_src = 
        "struct PrivateData { x: i32 }\n"
        "pub fn get_private() -> PrivateData { return PrivateData { x: 42 }; }\n";
    const char* main_src = 
        "import \"lib.zrl\";\n"
        "fn main() -> i32 {\n"
        "    let d: PrivateData = get_private();\n" // Error: PrivateData is private
        "    return d.x;\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* lib_mod = surface_parse_module(lib_src, "lib.zrl", report);
    SurfaceModule* main_mod = surface_parse_module(main_src, "main.zrl", report);
    if (lib_mod) lib_mod->file_path = "lib.zrl";
    if (main_mod) main_mod->file_path = "main.zrl";
    
    if (!lib_mod || !main_mod) {
        if (lib_mod) surface_mod_free(lib_mod);
        if (main_mod) surface_mod_free(main_mod);
        diag_report_destroy(report);
        ASSERT(false, "Parse failed");
    }

    surface_mod_merge(main_mod, lib_mod);
    surface_mod_free(lib_mod);
    ILModule* mod = surface_lower_module(main_mod, report, false);

    bool found_error = false;
    for (uint32_t i = 0; i < report->count; i++) {
        if (report->diagnostics[i].severity == DIAG_ERROR && 
            strstr(report->diagnostics[i].message, "private")) {
            found_error = true;
            break;
        }
    }

    cleanup(main_mod, mod, report);
    ASSERT(found_error, "Should report error for private type access");
    return true;
}

static bool test_regression_symbol_prefixing(void) {
    const char* src =
        "struct S { x: u64 }\n"
        "pub fn zoril_memcpy(dest: *mut u8, src: *mut u8, n: u64) { }\n"
        "fn internal_func() { }\n"
        "pub extern fn external_func();\n"
        "fn main() {\n"
        "    let mut s1 = S { x: 1 };\n"
        "    let s2 = s1;\n" // This triggers an internal memcpy call
        "    zoril_memcpy(0 as *mut u8, 0 as *mut u8, 0);\n"
        "    internal_func();\n"
        "    external_func();\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parse should succeed");
    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Lowering should succeed");

    char* ptr;
    size_t size;
    FILE* stream = open_memstream(&ptr, &size);
    qbe_emit_module(mod, stream);
    fclose(stream);

    // Zoril functions should be prefixed with z_ (except main and externs)
    ASSERT(strstr(ptr, "function $z_zoril_memcpy") != NULL, "zoril_memcpy should be $z_zoril_memcpy");
    ASSERT(strstr(ptr, "function $z_internal_func") != NULL, "internal_func should be $z_internal_func");
    ASSERT(strstr(ptr, "call $external_func") != NULL, "extern func should NOT be prefixed");
    // `export function $main(` or `export function w $main(` (a unit main returns 0).
    ASSERT(strstr(ptr, " $main(") != NULL && strstr(ptr, "$z_main(") == NULL, "main should NOT be prefixed");
    
    // Internal memcpy calls should still use $memcpy (no z_ prefix)
    ASSERT(strstr(ptr, "call $memcpy") != NULL, "Internal memcpy calls should NOT be prefixed");

    free(ptr);
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_private_struct_field_access);
    RUN_TEST(test_private_method_access);
    RUN_TEST(test_private_function_access);
    RUN_TEST(test_private_global_access);
    RUN_TEST(test_private_type_access);
    RUN_TEST(test_regression_symbol_prefixing);
    printf("[%2d/%2d] Visibility Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
