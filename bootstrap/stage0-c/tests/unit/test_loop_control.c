#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "verifier.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_while_break(void) {
    const char* src = 
        "fn test() -> i32 {\n"
        "  let mut i = 0;\n"
        "  while true {\n"
        "    if i == 5 { break; }\n"
        "    i = i + 1;\n"
        "  }\n"
        "  return i;\n"
        "}";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    if (!smod) return false;
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    if (!il_mod) { surface_mod_free(smod); return false; }
    
    VerificationResult vres = verify_module(il_mod);
    bool success = vres.is_safe;
    if (!success) {
        fprintf(stderr, "[FAIL] %s:%d: Module should pass verification\n", __FILE__, __LINE__);
        for (uint32_t i = 0; i < vres.error_count; i++) {
            fprintf(stderr, "  %s at block %u, instr %u\n", vres.errors[i].message, vres.errors[i].block_id, vres.errors[i].instr_index);
        }
    }
    verify_result_free(&vres);
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return success;
}

static bool test_for_continue(void) {
    const char* src = 
        "fn test() -> i32 {\n"
        "  let mut sum = 0;\n"
        "  for i in 0..10 {\n"
        "    if i == 5 { continue; }\n"
        "    sum = sum + i;\n"
        "  }\n"
        "  return sum;\n"
        "}";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    if (!smod) return false;
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    if (!il_mod) { surface_mod_free(smod); return false; }
    
    VerificationResult vres = verify_module(il_mod);
    bool success = vres.is_safe;
    if (!success) {
        fprintf(stderr, "[FAIL] %s:%d: Module should pass verification\n", __FILE__, __LINE__);
        for (uint32_t i = 0; i < vres.error_count; i++) {
            fprintf(stderr, "  %s at block %u, instr %u\n", vres.errors[i].message, vres.errors[i].block_id, vres.errors[i].instr_index);
        }
    }
    verify_result_free(&vres);
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return success;
}

static bool test_break_defer(void) {
    const char* src = 
        "fn test(p: *mut i32) {\n"
        "  while true {\n"
        "    defer *p = 1;\n"
        "    break;\n"
        "  }\n"
        "}";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    if (!smod) return false;
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    if (!il_mod) { surface_mod_free(smod); return false; }
    
    VerificationResult vres = verify_module(il_mod);
    bool success = vres.is_safe;
    if (!success) {
        fprintf(stderr, "[FAIL] %s:%d: Module should pass verification\n", __FILE__, __LINE__);
        for (uint32_t i = 0; i < vres.error_count; i++) {
            fprintf(stderr, "  %s at block %u, instr %u\n", vres.errors[i].message, vres.errors[i].block_id, vres.errors[i].instr_index);
        }
    }
    verify_result_free(&vres);
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return success;
}

static bool test_nested_break_continue_defer(void) {
    const char* src = 
        "fn test(p: *mut i32) {\n"
        "  defer *p = 0;\n"
        "  for i in 0..10 {\n"
        "    defer *p = 1;\n"
        "    while true {\n"
        "      defer *p = 2;\n"
        "      if i == 5 { break; }\n"
        "      if i == 6 { continue; }\n"
        "      return;\n"
        "    }\n"
        "  }\n"
        "}";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    if (!smod) return false;
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    if (!il_mod) { surface_mod_free(smod); return false; }
    
    VerificationResult vres = verify_module(il_mod);
    bool success = vres.is_safe;
    if (!success) {
        fprintf(stderr, "[FAIL] %s:%d: Module should pass verification\n", __FILE__, __LINE__);
        for (uint32_t i = 0; i < vres.error_count; i++) {
            fprintf(stderr, "  %s at block %u, instr %u\n", vres.errors[i].message, vres.errors[i].block_id, vres.errors[i].instr_index);
        }
    }
    verify_result_free(&vres);
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return success;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_while_break);
    RUN_TEST(test_for_continue);
    RUN_TEST(test_break_defer);
    RUN_TEST(test_nested_break_continue_defer);
    printf("test_loop_control: %d/%d tests passed\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return tests_passed == tests_run ? 0 : 1;
}
