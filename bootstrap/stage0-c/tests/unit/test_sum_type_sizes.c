#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_type.h"
#include "il_cfg.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_sum_type_size_basic(void) {
    const char* src = 
        "enum MyEnum {\n"
        "    A,\n"
        "    B(i32),\n"
        "    C(i64),\n"
        "}\n";

    DiagnosticReport report = {0};
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", &report);
    ASSERT(smod != NULL, "Failed to parse module");
    ASSERT(!report.has_errors, "Parsing had errors");

    ILModule* mod = surface_lower_module(smod, &report, false);
    ASSERT(mod != NULL, "Failed to lower module");

    ILTypeDef* def = il_mod_get_type_def_by_name(mod, "MyEnum");
    ASSERT(def != NULL, "Failed to find MyEnum ILTypeDef");
    
    const ILType* ty = il_type_struct_gen(def->name, def->id, NULL, 0);
    ASSERT(ty != NULL, "Failed to create MyEnum ILType");

    size_t size = il_type_size(mod, ty);
    size_t align = il_type_align(mod, ty);

    // MyEnum: 
    // Tag: 4 bytes (align 4)
    // Variant A: unit (size 0)
    // Variant B: i32 (size 4, align 4)
    // Variant C: i64 (size 8, align 8)
    
    // Max variant size = 8, max variant align = 8
    // Payload offset = align(tag_size(4), variant_align(8)) = 8
    // Total size = 8 (offset) + 8 (payload) = 16
    // Total align = max(tag_align(4), variant_align(8)) = 8
    
    ASSERT(size == 16, "MyEnum size should be 16");
    ASSERT(align == 8, "MyEnum align should be 8");

    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

static bool test_sum_type_size_large(void) {
    const char* src = 
        "struct Large { x: i64, y: i64, z: i64 }\n"
        "enum Complex {\n"
        "    Small(i8),\n"
        "    Big(Large),\n"
        "}\n";

    DiagnosticReport report = {0};
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", &report);
    ASSERT(smod != NULL, "Failed to parse module");

    ILModule* mod = surface_lower_module(smod, &report, false);
    ASSERT(mod != NULL, "Failed to lower module");

    ILTypeDef* def = il_mod_get_type_def_by_name(mod, "Complex");
    ASSERT(def != NULL, "Failed to find Complex ILTypeDef");

    const ILType* ty = il_type_struct_gen(def->name, def->id, NULL, 0);
    ASSERT(ty != NULL, "Failed to create Complex ILType");

    size_t size = il_type_size(mod, ty);
    size_t align = il_type_align(mod, ty);

    // Large: 24 bytes, align 8
    // Tag: 4 bytes, align 4
    // Variant Small: 1 byte, align 1
    // Variant Big: 24 bytes, align 8
    
    // Payload offset = 8
    // Total size = 8 + 24 = 32
    // Total align = 8
    
    ASSERT(size == 32, "Complex size should be 32");
    ASSERT(align == 8, "Complex align should be 8");

    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_sum_type_size_basic);
    RUN_TEST(test_sum_type_size_large);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
