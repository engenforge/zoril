#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "qbe_emit.h"
#include "il_cfg.h"
#include "verifier.h"
#include "il_type.h"
#include "diagnostics.h"

int tests_run = 0;
int tests_passed = 0;

static void cleanup(SurfaceModule* smod, ILModule* ilmod, DiagnosticReport* report) {
    if (ilmod) il_mod_free(ilmod);
    if (smod) surface_mod_free(smod);
    if (report) diag_report_destroy(report);
}

// From test_generics_complex.c
static bool test_generic_impl_return_variant(void) {
    const char* src = 
        "struct Big { a: i64, b: i64, c: i64 }\n"
        "enum MyOption<T> { Some(T), None }\n"
        "struct Wrapper<T> { val: T }\n"
        "impl Wrapper<T> {\n"
        "    fn get_none(self: &Wrapper<T>) -> MyOption<T> {\n"
        "        return MyOption.None;\n"
        "    }\n"
        "    fn get_some(self: &Wrapper<T>) -> MyOption<T> {\n"
        "        return MyOption.Some(self.val);\n"
        "    }\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let b = Big { a: 1, b: 2, c: 3 };\n"
        "    let w = Wrapper { val: b };\n"
        "    let n = w.get_none();\n"
        "    let s = w.get_some();\n"
        "    return 0;\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) { diag_render_terminal(report); cleanup(NULL, NULL, report); ASSERT(false, "Parse should succeed"); }
    
    ILModule* mod = surface_lower_module(smod, report, false);
    if (!mod) { diag_render_terminal(report); cleanup(smod, NULL, report); ASSERT(false, "Lowering should succeed"); }
    
    const ILFunction* f_none = il_mod_get_func_by_name(mod, "Wrapper_Big_get_none");
    const ILFunction* f_some = il_mod_get_func_by_name(mod, "Wrapper_Big_get_some");
    
    if (!f_none || !f_some) {
        cleanup(smod, mod, report); ASSERT(false, "Should have monomorphized methods");
    }
    
    ASSERT(f_none->is_sret, "get_none should be sret");
    ASSERT(f_some->is_sret, "get_some should be sret");
    
    char* ir;
    size_t ir_size;
    FILE* stream = open_memstream(&ir, &ir_size);
    qbe_emit_module(mod, stream);
    fclose(stream);
    
    bool ir_ok = (strstr(ir, "Wrapper_Big_get_none") != NULL && strstr(ir, "Wrapper_Big_get_some") != NULL);
    free(ir);
    if (!ir_ok) { cleanup(smod, mod, report); ASSERT(false, "IR should contain methods"); }
    
    VerificationResult vres = verify_module(mod);
    bool safe = vres.is_safe;
    verify_result_free(&vres);
    
    cleanup(smod, mod, report);
    ASSERT(safe, "Module should be safe");
    return true;
}

static bool test_mangled_call_generic(void) {
    const char* src = 
        "struct Foo<T> { x: T }\n"
        "impl Foo<T> {\n"
        "    fn set(self: &mut Foo<T>, val: T) {\n"
        "        self.x = val;\n"
        "    }\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let mut f = Foo { x: 42 };\n"
        "    Foo_set(&mut f, 100);\n" 
        "    return 0;\n"
        "}\n";
        
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) { cleanup(NULL, NULL, report); ASSERT(false, "Parse failed"); }
    
    ILModule* mod = surface_lower_module(smod, report, false);
    if (!mod) { cleanup(smod, NULL, report); ASSERT(false, "Lowering failed"); }
    
    const ILFunction* f_set = il_mod_get_func_by_name(mod, "Foo_i32_set");
    bool found = (f_set != NULL);
    
    cleanup(smod, mod, report);
    ASSERT(found, "Should have monomorphized Foo_i32_set from Foo_set call");
    return true;
}

// From test_generics_lower.c
static bool test_generic_struct_monomorphize(void) {
    const char* src =
        "struct Wrapper<T> { value: T }\n"
        "fn use_wrapper() -> i32 {\n"
        "    let w: Wrapper<i32> = Wrapper { value: 42 };\n"
        "    return w.value;\n"
        "}\n";

    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parse should succeed");

    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Lowering should succeed");

    bool found_wrapper_i32 = false;
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        if (strcmp(mod->type_defs[i]->name, "Wrapper_i32") == 0) found_wrapper_i32 = true;
    }
    ASSERT(found_wrapper_i32, "Monomorphized Wrapper_i32 should appear in IL");

    VerificationResult res = verify_module(mod);
    if (!res.is_safe) {
        for (uint32_t i = 0; i < res.error_count; i++) {
            fprintf(stderr, "Verify error: %s at %s:%u:%u\n", res.errors[i].message, res.errors[i].func_name, res.errors[i].line, res.errors[i].col);
        }
    }
    ASSERT(res.is_safe, "Monomorphized module should pass verification");
    verify_result_free(&res);

    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

static bool test_generic_fn_skipped(void) {
    const char* src = "fn identity<T>(x: T) -> T { return x; }\n";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parse should succeed");

    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Lowering should succeed");
    ASSERT(mod->function_count == 0, "Generic function should not appear in IL");

    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

// From test_generics_nested.c
static bool test_nested_generic_monomorphize(void) {
    const char* src =
        "struct Pair<T, U> { a: T, b: U }\n"
        "struct Wrapper<T> { inner: T }\n"
        "fn make_pair<T, U>(a: T, b: U) -> Pair<T, U> { return Pair { a: a, b: b }; }\n"
        "fn wrap<T>(val: T) -> Wrapper<T> { return Wrapper { inner: val }; }\n"
        "fn main() -> i32 {\n"
        "    let p = make_pair(10, 20);\n"
        "    let w = wrap(p);\n"
        "    return w.inner.a;\n"
        "}\n";

    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parse should succeed");

    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Lowering should succeed");

    bool found_pair = false;
    bool found_wrapper = false;
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        if (strstr(mod->type_defs[i]->name, "Pair_")) found_pair = true;
        if (strstr(mod->type_defs[i]->name, "Wrapper_")) found_wrapper = true;
    }
    ASSERT(found_pair, "Monomorphized Pair should appear");
    ASSERT(found_wrapper, "Monomorphized Wrapper should appear");

    VerificationResult res = verify_module(mod);
    bool verified = res.is_safe;
    verify_result_free(&res);
    ASSERT(verified, "Module should pass verification");

    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

// From test_generics_parser.c
static bool test_parse_generic_struct(void) {
    const char* src = "struct MyBox<T> { value: T }";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test.zil", report);
    ASSERT(mod != NULL, "Parse should succeed");
    ASSERT(mod->type_def_count == 1, "Should have 1 type def");
    TypeDef* def = mod->type_defs[0];
    ASSERT(def->kind == TYPE_DEF_STRUCT, "Should be a struct");
    const StructDecl* s = def->as.struct_decl;
    ASSERT(strcmp(s->name, "MyBox") == 0, "Name should be MyBox");
    ASSERT(s->type_param_count == 1, "Should have 1 type param");
    surface_mod_free(mod);
    diag_report_destroy(report);
    return true;
}

// From test_generics_recursion.c
static bool test_deep_recursion_limit(void) {
    const char* src = 
        "struct Wrapper<T> { val: T }\n"
        "struct Infinite<T> { next: Infinite<Wrapper<T>> }\n"
        "fn test() -> i32 {\n"
        "    let n: Infinite<i32> = 0 as Infinite<i32>;\n"
        "    return 0;\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) { cleanup(NULL, NULL, report); ASSERT(false, "Parse failed"); }

    ILModule* mod = surface_lower_module(smod, report, false);

    bool found_recursion_error = false;
    for (uint32_t i = 0; i < report->count; i++) {
        if (report->diagnostics[i].severity == DIAG_ERROR && 
            strstr(report->diagnostics[i].message, "recursion")) {
            found_recursion_error = true;
            break;
        }
    }

    cleanup(smod, mod, report);
    ASSERT(found_recursion_error, "Should report error for deep generic recursion");
    return true;
}

// From test_generics_zst.c
static bool test_vec_unit(void) {
    const char* src =
        "struct Vec<T> { ptr: *mut T, len: u64, cap: u64 }\n"
        "impl<T> Vec<T> {\n"
        "    fn new() -> Vec<T> {\n"
        "        return Vec { ptr: 0 as *mut T, len: 0, cap: 0 };\n"
        "    }\n"
        "    fn push(self: &mut Vec<T>, val: T) {\n"
        "    }\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let mut v = Vec::<()>.new();\n"
        "    v.push(());\n"
        "    return 0;\n"
        "}\n";

    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parse should succeed");

    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Lowering should succeed");

    VerificationResult res = verify_module(mod);
    bool verified = res.is_safe;
    verify_result_free(&res);
    ASSERT(verified, "Module should pass verification");

    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

static bool test_deep_generic_syntax_error_leak(void) {
    // Unclosed angle bracket in deep generic
    const char* src = "fn test() { let x: Vec<Vec<i32> = 0; }";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    
    // We don't care about the result, just that it doesn't leak under Valgrind/ASan
    cleanup(smod, NULL, report);
    return true;
}

static bool test_deep_generic_semantic_error_leak(void) {
    // Unknown type in deep generic
    const char* src = "fn test() { let x: Vec<Vec<UnknownType>> = 0; }";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (smod) {
        ILModule* mod = surface_lower_module(smod, report, false);
        cleanup(smod, mod, report);
    } else {
        cleanup(NULL, NULL, report);
    }
    return true;
}

static bool test_generic_method_mismatch_leak(void) {
    // Wrong number of type arguments in method call
    const char* src = 
        "struct Wrapper<T> { val: T }\n"
        "impl Wrapper<T> { fn foo<U>(self: &Self) {} }\n"
        "fn test() { let w = Wrapper { val: 42 }; w.foo::<i32, bool>(); }";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (smod) {
        ILModule* mod = surface_lower_module(smod, report, false);
        cleanup(smod, mod, report);
    } else {
        cleanup(NULL, NULL, report);
    }
    return true;
}

static bool test_deeply_nested_generic_monomorphize(void) {
    const char* src = 
        "struct Wrapper<T> { val: T }\n"
        "fn test() -> Wrapper<Wrapper<Wrapper<i32>>> {\n"
        "    return Wrapper { val: Wrapper { val: Wrapper { val: 42 } } };\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parse should succeed");

    ILModule* mod = surface_lower_module(smod, report, false);
    ASSERT(mod != NULL, "Lowering should succeed");
    ASSERT(!report->has_errors, "Should have no errors");

    bool found_v3 = false;
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        if (strstr(mod->type_defs[i]->name, "Wrapper_Wrapper_Wrapper_i32")) {
            found_v3 = true;
            // Verify that it has a valid type_def_id and it's not 0
            ASSERT(mod->type_defs[i]->id != 0, "Monomorphized type should have non-zero ID");
        }
    }
    ASSERT(found_v3, "Should have found deeply nested monomorphized type");

    cleanup(smod, mod, report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    
    RUN_TEST(test_generic_impl_return_variant);
    RUN_TEST(test_mangled_call_generic);
    RUN_TEST(test_generic_struct_monomorphize);
    RUN_TEST(test_generic_fn_skipped);
    RUN_TEST(test_nested_generic_monomorphize);
    RUN_TEST(test_deeply_nested_generic_monomorphize);
    RUN_TEST(test_parse_generic_struct);
    RUN_TEST(test_deep_recursion_limit);
    RUN_TEST(test_vec_unit);
    RUN_TEST(test_deep_generic_syntax_error_leak);
    RUN_TEST(test_deep_generic_semantic_error_leak);
    RUN_TEST(test_generic_method_mismatch_leak);

    printf("[%2d/%2d] Consolidated Generics Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
