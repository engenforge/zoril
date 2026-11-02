#include "verifier.h"
#include "qbe_emit.h"
#include "surface_lower.h"
#include "surface_parser.h"
#include "surface_ast.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "il_cfg.h"
#include "il_print.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_struct_definition(void) {
    ILModule* mod = il_mod_create();
    ABORT_IF_NULL(mod);

    ILTypeDef* def = il_type_def_struct_create(1, "MyStruct", NULL, true);
    ABORT_IF_NULL(def);

    const ILType * u32_ty = il_type_u32();
    il_type_def_add_field(def, "x", u32_ty);

    il_mod_add_type_def(mod, def);

    const ILTypeDef* retrieved = il_mod_get_type_def(mod, 1);
    ASSERT(retrieved != NULL, "Should retrieve type definition");
    ASSERT(strcmp(retrieved->name, "MyStruct") == 0, "Name should match");
    ASSERT(retrieved->field_count == 1, "Field count should match");
    ASSERT(strcmp(retrieved->fields[0].name, "x") == 0, "Field name should match");

    il_mod_free(mod);
    return true;
}

static bool test_type_def_printing(void) {
    ILModule* mod = il_mod_create();
    ILTypeDef* def = il_type_def_struct_create(1, "MyStruct", NULL, true);
    const ILType * u32_ty = il_type_u32();
    il_type_def_add_field(def, "x", u32_ty);
    il_mod_add_type_def(mod, def);

    char buffer[1024] = {0};
    il_print_module(mod, buffer, sizeof(buffer));

    ASSERT(strstr(buffer, "type T1: struct {") != NULL, "Should print struct definition");
    ASSERT(strstr(buffer, "x: u32") != NULL, "Should print field");

    il_mod_free(mod);
    return true;
}

#include "il_read.h"
#include "il_type.h"

static bool test_type_def_reading(void) {
    const char* il = 
        "type T1: struct {\n"
        "  x: u32,\n"
        "  y: bool\n"
        "}\n";
    
    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should read module");
    ASSERT(mod->type_def_count == 1, "Should have one type definition");
    
    const ILTypeDef* def = mod->type_defs[0];
    ASSERT(def->id == 1, "ID should match");
    ASSERT(!def->is_sum, "Should be a struct");
    ASSERT(def->field_count == 2, "Should have two fields");
    ASSERT(strcmp(def->fields[0].name, "x") == 0, "First field name should be x");
    ASSERT(def->fields[0].type->kind == IL_TY_U32, "First field type should be u32");
    ASSERT(strcmp(def->fields[1].name, "y") == 0, "Second field name should be y");
    ASSERT(def->fields[1].type->kind == IL_TY_BOOL, "Second field type should be bool");

    il_mod_free(mod);
    return true;
}

static bool test_sum_type(void) {
    const char* il = 
        "type T2: sum {\n"
        "  None: unit,\n"
        "  Some: u32\n"
        "}\n";
    
    ILModule* mod = il_read_module(il, NULL);
    ASSERT(mod != NULL, "Should read module");
    ASSERT(mod->type_def_count == 1, "Should have one type definition");
    
    const ILTypeDef* def = mod->type_defs[0];
    ASSERT(def->id == 2, "ID should match");
    ASSERT(def->is_sum, "Should be a sum type");
    ASSERT(def->field_count == 2, "Should have two variants");
    ASSERT(strcmp(def->fields[0].name, "None") == 0, "First variant name should be None");
    ASSERT(def->fields[1].name != NULL && strcmp(def->fields[1].name, "Some") == 0, "Second variant name should be Some");

    char buffer[1024] = {0};
    il_print_module(mod, buffer, sizeof(buffer));
    ASSERT(strstr(buffer, "type T2: sum {") != NULL, "Should print sum definition");

    il_mod_free(mod);
    return true;
}

// id:045 — duplicate struct definition (forward/partial decl) where the second
// definition adds fields missing from the first.  surface_lower_module must
// reuse the existing ILTypeDef rather than silently discarding the second def.
static bool test_regression_duplicate_struct_adds_fields(void) {
    // Two 'Ctx' definitions: first has 2 fields, second adds a third.
    // The lowered type def must have all 3 fields so field access works.
    const char* src =
        "struct Ctx { x: u64, y: u64 }\n"             // partial (forward) definition
        "struct Ctx { x: u64, y: u64, depth: u32 }\n" // complete definition
        "fn get_depth(p: *mut Ctx) -> u32 {\n"
        "    return (*p).depth;\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let mut c = Ctx { x: 0 as u64, y: 0 as u64, depth: 7 as u32 };\n"
        "    let d = get_depth(&mut c as *mut Ctx);\n"
        "    if d != 7 as u32 { return 1; }\n"
        "    return 0;\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parse should succeed");
    ILModule* mod = surface_lower_module(smod, report, false);
    surface_mod_free(smod);
    ASSERT(mod != NULL, "Lowering should succeed");

    // Find the Ctx type def and verify it has 3 fields
    const ILTypeDef* ctx_def = NULL;
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        if (mod->type_defs[i]->name && strcmp(mod->type_defs[i]->name, "Ctx") == 0) {
            ctx_def = mod->type_defs[i];
            break;
        }
    }
    ASSERT(ctx_def != NULL, "Ctx type def should exist");
    ABORT_IF_NULL(ctx_def);
    ASSERT(ctx_def->field_count == 3, "Ctx should have 3 fields after merging both definitions");

    // Verify get_depth lowers without verification errors
    VerificationResult vres = verify_module(mod);
    ASSERT(vres.is_safe, "Module should pass verification");
    verify_result_free(&vres);

    il_mod_free(mod);
    diag_report_destroy(report);
    return true;
}

// Similar to id:045 but for enum (sum type) — duplicate enum definition where
// the second definition adds a variant missing from the first.
static bool test_regression_duplicate_enum_adds_variants(void) {
    const char* src =
        "enum Op { Add, Sub }\n"                 // partial definition
        "enum Op { Add, Sub, Mul(u32) }\n"       // complete definition adds Mul variant
        "fn is_mul(op: *mut Op) -> bool {\n"
        "    return match *op {\n"
        "        Op.Mul(_) => true,\n"
        "        _ => false,\n"
        "    };\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let mut o = Op.Mul(42 as u32);\n"
        "    if is_mul(&mut o as *mut Op) { return 0; }\n"
        "    return 1;\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parse should succeed");
    ILModule* mod = surface_lower_module(smod, report, false);
    surface_mod_free(smod);
    ASSERT(mod != NULL, "Lowering should succeed");

    // Find Op type def — it must have 3 variants
    const ILTypeDef* op_def = NULL;
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        if (mod->type_defs[i]->name && strcmp(mod->type_defs[i]->name, "Op") == 0) {
            op_def = mod->type_defs[i];
            break;
        }
    }
    ASSERT(op_def != NULL, "Op type def should exist");
    ABORT_IF_NULL(op_def);
    ASSERT(op_def->field_count == 3, "Op should have 3 variants after merging both definitions");

    VerificationResult vres = verify_module(mod);
    ASSERT(vres.is_safe, "Module should pass verification");
    verify_result_free(&vres);

    il_mod_free(mod);
    diag_report_destroy(report);
    return true;
}

// When a struct is referenced as a field type before its surface definition is
// processed, lower_type_internal pre-registers the type def using the FIRST
// definition found.  surface_lower_module must then patch in any missing fields
// from a later (more complete) definition of the same name.
static bool test_regression_forward_ref_struct_gets_complete_fields(void) {
    // Wrapper references Inner before Inner's complete definition is seen.
    // The first Inner definition has 1 field; the second adds 'tag: u32'.
    const char* src =
        "struct Inner { val: u64 }\n"              // partial — seen when lowering Wrapper
        "struct Wrapper { inner: *mut Inner }\n"   // forces lower_type_internal on Inner
        "struct Inner { val: u64, tag: u32 }\n"    // complete definition
        "fn get_tag(w: *mut Wrapper) -> u32 {\n"
        "    return (*(*w).inner).tag;\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let mut i = Inner { val: 0 as u64, tag: 9 as u32 };\n"
        "    let mut w = Wrapper { inner: &mut i as *mut Inner };\n"
        "    if get_tag(&mut w as *mut Wrapper) != 9 as u32 { return 1; }\n"
        "    return 0;\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Parse should succeed");
    ILModule* mod = surface_lower_module(smod, report, false);
    surface_mod_free(smod);
    ASSERT(mod != NULL, "Lowering should succeed");

    const ILTypeDef* inner_def = NULL;
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        if (mod->type_defs[i]->name && strcmp(mod->type_defs[i]->name, "Inner") == 0) {
            inner_def = mod->type_defs[i];
            break;
        }
    }
    ASSERT(inner_def != NULL, "Inner type def should exist");
    ABORT_IF_NULL(inner_def);
    ASSERT(inner_def->field_count == 2, "Inner should have 2 fields after merging both definitions");

    VerificationResult vres = verify_module(mod);
    ASSERT(vres.is_safe, "Module should pass verification");
    verify_result_free(&vres);

    il_mod_free(mod);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_struct_definition);
    RUN_TEST(test_type_def_printing);
    RUN_TEST(test_type_def_reading);
    RUN_TEST(test_sum_type);

    RUN_TEST(test_regression_duplicate_struct_adds_fields);
    RUN_TEST(test_regression_duplicate_enum_adds_variants);
    RUN_TEST(test_regression_forward_ref_struct_gets_complete_fields);
    printf("[%2d/%2d] User-defined type definitions\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
