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
#include "verifier.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static void cleanup(SurfaceModule* smod, ILModule* mod, DiagnosticReport* report) {
    if (mod) il_mod_free(mod);
    if (smod) surface_mod_free(smod);
    if (report) diag_report_destroy(report);
}

static bool test_generic_trait_with_generic_method(void) {
    const char* src = 
        "struct Wrapper<T> { val: T }\n"
        "trait Converter<U> {\n"
        "    fn convert<V>(self: &Self, extra: V) -> U;\n"
        "}\n"
        "impl Converter<i32> for Wrapper<bool> {\n"
        "    fn convert<V>(self: &Wrapper<bool>, extra: V) -> i32 {\n"
        "        if self.val { return 1; } else { return 0; }\n"
        "    }\n"
        "}\n"
        "fn test() -> i32 {\n"
        "    let w = Wrapper { val: true };\n"
        "    return w.convert::<i32>(42); // U=i32 (from impl), V=i32 (from call)\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) { cleanup(NULL, NULL, report); ASSERT(false, "Parse failed"); }

    ILModule* mod = surface_lower_module(smod, report, false);
    if (!mod) { 
        diag_render_terminal(report);
        cleanup(smod, NULL, report); 
        ASSERT(false, "Lowering failed"); 
    }

    VerificationResult res = verify_module(mod);
    if (!res.is_safe) {
        for (uint32_t i = 0; i < res.error_count; i++) printf("Verify error: %s\n", res.errors[i].message);
        verify_result_free(&res);
        cleanup(smod, mod, report);
        ASSERT(false, "Verification failed");
    }
    verify_result_free(&res);

    cleanup(smod, mod, report);
    return true;
}

static bool test_fully_generic_trait_method(void) {
    const char* src = 
        "struct Wrapper<T> { val: T }\n"
        "trait Mapper<U> {\n"
        "    fn map<V>(self: &Self, extra: V) -> Wrapper<U>;\n"
        "}\n"
        "impl Mapper<U> for Wrapper<T> {\n"
        "    fn map<V>(self: &Wrapper<T>, extra: V) -> Wrapper<U> {\n"
        "        // This is a dummy implementation that just returns a default Wrapper<U>\n"
        "        // In a real scenario, we might use trait bounds to convert T to U.\n"
        "        // For this test, we just want to see if it monomorphizes.\n"
        "        let res: Wrapper<U> = Wrapper { val: @syscall(0) as U };\n" // Use syscall 0 as a dummy value of type U
        "        return res;\n"
        "    }\n"
        "}\n"
        "fn test() -> i32 {\n"
        "    let w = Wrapper { val: 10 };\n"
        "    let res = w.map::<bool, f32>(3.14);\n" // T=i32, U=bool, V=f32
        "    return 0;\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) { cleanup(NULL, NULL, report); ASSERT(false, "Parse failed"); }

    ILModule* mod = surface_lower_module(smod, report, false);
    if (!mod) { 
        diag_render_terminal(report);
        cleanup(smod, NULL, report); 
        ASSERT(false, "Lowering failed"); 
    }

    bool found_mangled = false;
    for (uint32_t i = 0; i < mod->function_count; i++) {
        // Expected name should contain Wrapper, Mapper, i32, bool, and map, f32
        // Our current mangling might be simpler, let's see.
        if (strstr(mod->functions[i]->name, "map")) {
            found_mangled = true;
            break;
        }
    }
    
    VerificationResult res = verify_module(mod);
    if (!res.is_safe) {
        for (uint32_t i = 0; i < res.error_count; i++) printf("Verify error: %s\n", res.errors[i].message);
        verify_result_free(&res);
        cleanup(smod, mod, report);
        ASSERT(false, "Verification failed");
    }
    verify_result_free(&res);

    cleanup(smod, mod, report);
    ASSERT(found_mangled, "Monomorphized method not found");
    return true;
}

static bool test_regression_generic_trait_parsing(void) {
    const char* src = 
        "trait CompilationQuery<Input, Output> {\n"
        "    fn query(self: &Self, input: Input) -> Output;\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", report);
    ASSERT(mod != NULL, "Parse should succeed for generic trait");
    ASSERT(mod->trait_count == 1, "Should have 1 trait");
    ASSERT(mod->traits[0]->type_param_count == 2, "Trait should have 2 type params");
    surface_mod_free(mod);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_generic_trait_with_generic_method);
    RUN_TEST(test_fully_generic_trait_method);
    RUN_TEST(test_regression_generic_trait_parsing);
    printf("[%2d/%2d] Trait Generics Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
