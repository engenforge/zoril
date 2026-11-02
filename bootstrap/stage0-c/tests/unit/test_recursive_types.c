#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "il_read.h"
#include "il_type.h"
#include "il_cfg.h"
#include "verifier.h"
#include "il_pass.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_recursive_ptr_struct(void) {
    const char* il = 
        "type T1: struct {\n"
        "  val: u32,\n"
        "  next: PtrMut<T1, 'a>\n"
        "}\n"
        "f0: u32 get_val(p: PtrMut<T1, 'a>) {\n"
        "  @b0:\n"
        "    v2: PtrMut<u32, 'a> = field_addr v1, 0\n"
        "    v3: u32 = load v2\n"
        "    ret v3\n"
        "}\n";
    
    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should read module with recursive struct");
    
    // Ptr is Copy, so auto_drop won't insert anything.
    il_func_auto_drop(mod, mod->functions[0]);
    VerificationResult res = verify_module(mod);
    ASSERT(res.is_safe, "Module should be safe");
    verify_result_free(&res);

    il_mod_free(mod);
    return true;
}

static bool test_box_type_reading(void) {
    const char* il = 
        "f0: unit use_box(b: BoxMut<u32>) {\n"
        "  @b0:\n"
        "    drop v1\n"
        "    ret\n"
        "}\n";
    
    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should read module with Box type");
    ASSERT(mod->function_count > 0, "Should have one function");
    const ILFunction* func = mod->functions[0];
    ASSERT(func->param_count == 1, "Should have one parameter");
    ASSERT(func->param_types[0]->kind == IL_TY_BOX, "Parameter type should be Box");
    
    il_mod_free(mod);
    return true;
}

static bool test_recursive_box_struct(void) {
    const char* il = 
        "type T1: struct {\n"
        "  val: u32,\n"
        "  next: BoxMut<T1>\n"
        "}\n"
        "f0: u32 get_val(p: PtrMut<T1, 'a>) {\n"
        "  @b0:\n"
        "    v2: PtrMut<u32, 'a> = field_addr v1, 0\n"
        "    v3: u32 = load v2\n"
        "    ret v3\n"
        "}\n";
    
    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should read module with recursive Box struct");
    
    // Ptr is Copy, so auto_drop won't insert anything.
    il_func_auto_drop(mod, mod->functions[0]);
    VerificationResult res = verify_module(mod);
    ASSERT(res.is_safe, "Module should be safe");
    verify_result_free(&res);

    il_mod_free(mod);
    return true;
}

static bool test_box_is_owned(void) {
    const char* il = 
        "f0: unit use_box(b: BoxMut<u32>) {\n"
        "  @b0:\n"
        "    ret\n"
        "}\n";
    
    ILModule* mod = il_read_module(il, NULL);
    if (!mod) {
        fprintf(stderr, "[FAIL] %s:%d: Should read module\n", __FILE__, __LINE__);
        return false;
    }
    
    VerificationResult res = verify_module(mod);
    bool found_leak = false;
    for (uint32_t i = 0; i < res.error_count; i++) {
        if (strstr(res.errors[i].message, "leaked")) found_leak = true;
    }
    
    bool success = !res.is_safe && found_leak;
    if (!success) {
        if (res.is_safe) fprintf(stderr, "[FAIL] %s:%d: Module should NOT be safe because Box is not dropped\n", __FILE__, __LINE__);
        if (!found_leak) fprintf(stderr, "[FAIL] %s:%d: Should have found a leak error\n", __FILE__, __LINE__);
    }

    verify_result_free(&res);
    il_mod_free(mod);
    return success;
}

static bool test_ptr_is_copy(void) {
    const char* il = 
        "f0: unit use_ptr(p: PtrMut<u32, 'a>) {\n"
        "  @b0:\n"
        "    ret\n"
        "}\n";
    
    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should read module");
    
    VerificationResult res = verify_module(mod);
    ASSERT(res.is_safe, "Module should be safe because Ptr is copyable");
    verify_result_free(&res);

    il_mod_free(mod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_recursive_ptr_struct);
    RUN_TEST(test_box_type_reading);
    RUN_TEST(test_recursive_box_struct);
    RUN_TEST(test_box_is_owned);
    RUN_TEST(test_ptr_is_copy);

    printf("[%2d/%2d] Recursive types (Box/Pointer)\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
