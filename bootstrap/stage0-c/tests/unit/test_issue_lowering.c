#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include "surface_parser.h"
#include "surface_lower.h"
#include "verifier.h"
#include "il_print.h"
#include "test_harness.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_lower_struct_literal_types(void) {
    const char* src = 
        "struct Data {\n"
        "    id: u64,\n"
        "    ptr: *u8\n"
        "}\n"
        "fn main() {\n"
        "    let d = Data {\n"
        "        id: 123,\n"
        "        ptr: @ptr_cast<*u8>(0)\n"
        "    };\n"
        "}\n";
    
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parse failed");
    
    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Lowering failed");
    
    VerificationResult res = verify_module(mod);
    bool safe = res.is_safe;
    if (!safe) {
        for (uint32_t i = 0; i < res.error_count; i++) {
            printf("Verification Error: %s\n", res.errors[i].message);
        }
    }
    verify_result_free(&res);
    il_mod_free(mod);
    surface_mod_free(smod);
    
    ASSERT(safe, "Module should be safe");
    return true;
}

static bool test_lower_box_struct(void) {
    const char* src = 
        "struct Arena {\n"
        "    cap: u64\n"
        "}\n"
        "fn create() -> Box<Arena> {\n"
        "    return box Arena { cap: 1024 };\n"
        "}\n"
        "fn consume(a: Box<Arena>) {\n"
        "    @drop(a);\n"
        "}\n"
        "fn main() {\n"
        "    let a = create();\n"
        "    consume(a);\n"
        "}\n";
    
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parse failed");
    
    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Lowering failed");
    
    VerificationResult res = verify_module(mod);
    bool safe = res.is_safe;
    if (!safe) {
        printf("Failing IL for Box struct test:\n");
        char buffer[8192];
        il_print_module(mod, buffer, sizeof(buffer));
        printf("%s\n", buffer);
        for (uint32_t i = 0; i < res.error_count; i++) {
            printf("Verification Error: %s\n", res.errors[i].message);
        }
    }
    verify_result_free(&res);
    il_mod_free(mod);
    surface_mod_free(smod);
    
    ASSERT(safe, "Box of struct should be safe");
    return true;
}

static bool test_lower_box_variable(void) {
    const char* src = 
        "struct Data { x: u64 }\n"
        "fn main() {\n"
        "    let d = Data { x: 1 };\n"
        "    let b = box d;\n"
        "    @drop(b);\n"
        "}\n";
    
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parse failed");
    
    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Lowering failed");
    
    VerificationResult res = verify_module(mod);
    bool safe = res.is_safe;
    if (!safe) {
        for (uint32_t i = 0; i < res.error_count; i++) {
            printf("Verification Error: %s\n", res.errors[i].message);
        }
    }
    verify_result_free(&res);
    il_mod_free(mod);
    surface_mod_free(smod);
    
    ASSERT(safe, "Boxing a variable should be safe");
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_lower_struct_literal_types);
    RUN_TEST(test_lower_box_struct);
    RUN_TEST(test_lower_box_variable);
    printf("[%2d/%2d] Lowering Fixes\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
