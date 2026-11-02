#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_ast.h"
#include "surface_parser.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_parse_impl_decl(void) {
    const char* src = 
        "struct MyStruct { x: i32 }\n"
        "impl MyStruct {\n"
        "    pub const MY_CONST: i32 = 42;\n"
        "    type MyType = i32;\n"
        "    fn test(self) -> i32 {\n"
        "        self.x + MyStruct.MY_CONST\n"
        "    }\n"
        "}\n";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    
    ASSERT(mod != NULL, "Parser should produce a module");
    ASSERT(mod->impl_count == 1, "Module should have one impl block");
    
    const ImplDecl* impl = mod->impls[0];
    ASSERT(impl->method_count == 1, "Should have 1 method");
    ASSERT(impl->global_count == 1, "Should have 1 constant");
    ASSERT(impl->type_alias_count == 1, "Should have 1 type alias");
    
    ASSERT(strcmp(impl->globals[0]->name, "MY_CONST") == 0, "Constant name should be MY_CONST");
    ASSERT(impl->globals[0]->is_pub == true, "Constant should be public");
    
    ASSERT(strcmp(impl->type_aliases[0]->name, "MyType") == 0, "Type alias name should be MyType");

    surface_mod_free(mod);
    return true;
}

#include "il_instr.h"
#include "il_cfg.h"
#include "surface_lower.h"
#include "il_type.h"

static bool test_lower_impl_decl(void) {
    const char* src = 
        "struct MyStruct { x: i32 }\n"
        "impl MyStruct {\n"
        "    pub const MY_CONST: i32 = 42;\n"
        "    type MyType = i32;\n"
        "    fn test(self) -> MyStruct.MyType {\n"
        "        self.x + MyStruct.MY_CONST\n"
        "    }\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let s = MyStruct { x: 8 };\n"
        "    s.test()\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parser should produce a module");
    
    ILModule* ilmod = surface_lower_module(smod, report, false);
    ASSERT(ilmod != NULL, "Lowering should produce an IL module");
    
    // Check if MyStruct_MY_CONST exists in ilmod->globals
    bool found_const = false;
    for (uint32_t i = 0; i < ilmod->global_count; i++) {
        if (strcmp(ilmod->globals[i]->name, "MyStruct_MY_CONST") == 0) {
            found_const = true;
            break;
        }
    }
    ASSERT(found_const, "Should find lowered associated constant MyStruct_MY_CONST");
    
    il_mod_free(ilmod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_parse_impl_decl);
    RUN_TEST(test_lower_impl_decl);

    printf("[%2d/%2d] Impl Declarations\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
