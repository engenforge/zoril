#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_ast.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_cfg.h"
#include "verifier.h"
#include "qbe_emit.h"
#include "il_type.h"
#include "il_instr.h"
#include "diagnostics.h"

int tests_run = 0;
int tests_passed = 0;

// From test_qbe_conversions.c
static bool test_float_conversions_emit(void) {
    const char* source = 
        "fn main() {\n"
        "    let i: i32 = 42;\n"
        "    let f: f32 = i as f32;\n"
        "    let d: f64 = i as f64;\n"
        "    let l: i64 = 100;\n"
        "    let f2: f32 = l as f32;\n"
        "    let d2: f64 = l as f64;\n"
        "    let ui: u32 = 42;\n"
        "    let uf: f32 = ui as f32;\n"
        "    let ud: f64 = ui as f64;\n"
        "    let ul: u64 = 100;\n"
        "    let uf2: f32 = ul as f32;\n"
        "    let ud2: f64 = ul as f64;\n"
        "    \n"
        "    let i3: i32 = f as i32;\n"
        "    let i4: i32 = d as i32;\n"
        "    \n"
        "    let f3: f32 = d as f32;\n"
        "    let d3: f64 = f as f64;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) {
        diag_report_destroy(diag);
        return false;
    }

    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(diag);
        return false;
    }

    char* output = malloc(1024 * 1024);
    if (!output) {
        il_mod_free(mod);
        surface_mod_free(smod);
        diag_report_destroy(diag);
        return false;
    }
    memset(output, 0, 1024 * 1024);
    FILE* out = fmemopen(output, 1024 * 1024, "w");
    qbe_emit_module(mod, out);
    fclose(out);

    ASSERT(strstr(output, "=s swtof") != NULL, "Should emit swtof for s result");
    ASSERT(strstr(output, "=d swtof") != NULL, "Should emit swtof for d result");
    ASSERT(strstr(output, "=s sltof") != NULL, "Should emit sltof for s result");
    ASSERT(strstr(output, "=d sltof") != NULL, "Should emit sltof for d result");
    ASSERT(strstr(output, "=s uwtof") != NULL, "Should emit uwtof for s result");
    ASSERT(strstr(output, "=d uwtof") != NULL, "Should emit uwtof for d result");
    ASSERT(strstr(output, "=s ultof") != NULL, "Should emit ultof for s result");
    ASSERT(strstr(output, "=d ultof") != NULL, "Should emit ultof for d result");
    ASSERT(strstr(output, "=w stosi") != NULL, "Should emit stosi for w result");
    ASSERT(strstr(output, "=w dtosi") != NULL, "Should emit dtosi for w result");
    ASSERT(strstr(output, "=d exts") != NULL, "Should emit exts");
    ASSERT(strstr(output, "=s truncd") != NULL, "Should emit truncd");

    free(output);
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

// From test_qbe_emit.c
static bool test_qbe_type_mapping(void) {
    const ILType * u32_type = il_type_u32();
    const ILType * i64_type = il_type_i64();
    const ILType * bool_type = il_type_bool();
    const ILType * ptr_type = il_type_ptr(il_type_u8(), 0, false);
    const ILType * unit_type = il_type_unit();

    ASSERT(strcmp(qbe_map_type(u32_type), "w") == 0, "u32 should map to w");
    ASSERT(strcmp(qbe_map_type(i64_type), "l") == 0, "i64 should map to l");
    ASSERT(strcmp(qbe_map_type(bool_type), "w") == 0, "bool should map to w");
    ASSERT(strcmp(qbe_map_type(ptr_type), "l") == 0, "ptr should map to l");
    ASSERT(qbe_map_type(unit_type) == NULL, "unit should have no direct mapping");

    return true;
}

static bool test_qbe_ssa_mapping(void) {
    char buf[16];
    qbe_map_ssa(1, buf);
    ASSERT(strcmp(buf, "%v1") == 0, "SSA 1 should map to %v1");
    return true;
}

static bool test_qbe_arith_emission(void) {
    const ILType * u32_type = il_type_u32();
    ILValue v1 = { .id = 1, .type = u32_type };
    ILValue v2 = { .id = 2, .type = u32_type };
    ILInstruction* add = il_build_add(v1, v2);
    add->result_id = 3;
    char* ptr; size_t size;
    FILE* stream = open_memstream(&ptr, &size);
    qbe_emit_instr(NULL, NULL, add, 0, stream);
    fclose(stream);
    ASSERT(strstr(ptr, "%v3 =w add %v1, %v2") != NULL, "ADD emission should match QBE syntax");
    free(ptr); il_instr_free(add);
    return true;
}

static bool test_qbe_phi_emission(void) {
    const ILType * u32_type = il_type_u32();
    ILPhiIncoming incoming[2] = {
        { .block_id = 1, .value_id = 10 },
        { .block_id = 2, .value_id = 20 }
    };
    ILInstruction* phi = il_build_phi(incoming, 2, u32_type);
    phi->result_id = 30;
    char* ptr; size_t size;
    FILE* stream = open_memstream(&ptr, &size);
    qbe_emit_instr(NULL, NULL, phi, 0, stream);
    fclose(stream);
    ASSERT(strstr(ptr, "%v30 =w phi @b1 %v10, @b2 %v20") != NULL, "PHI emission should match QBE syntax");
    free(ptr); il_instr_free(phi);
    return true;
}

static bool test_qbe_struct_layout_emission(void) {
    const ILType * u32_ty = il_type_u32();
    const ILType * bool_ty = il_type_bool();
    ILModule* mod = il_mod_create();
    ILTypeDef* def = il_type_def_struct_create(1, "Point", "test.zrl", true);
    il_type_def_add_field(def, "x", u32_ty);
    il_type_def_add_field(def, "y", u32_ty);
    il_type_def_add_field(def, "is_valid", bool_ty);
    il_mod_add_type_def(mod, def);
    char* ptr; size_t size;
    FILE* stream = open_memstream(&ptr, &size);
    qbe_emit_module(mod, stream);
    fclose(stream);
    ASSERT(strstr(ptr, "type :Point = { w, w, b, b 3 }") != NULL, "Struct type definition missing or wrong");
    free(ptr); il_mod_free(mod);
    return true;
}

// From test_qbe_signedness.c
static bool test_qbe_signedness_e2e(void) {
    const char* source = 
        "fn audit(p8: *mut u8, p8s: *mut i8, p16: *mut u16, p16s: *mut i16, p32: *mut u32, p32s: *mut i32, p64: *mut u64) {\n"
        "    let a: u8 = *p8;\n"
        "    let b: i8 = *p8s;\n"
        "    let c: u16 = *p16;\n"
        "    let d: i16 = *p16s;\n"
        "    let e: u32 = *p32;\n"
        "    let f: i32 = *p32s;\n"
        "    let g: u64 = *p64;\n"
        "    \n"
        "    *p8 = a;\n"
        "    *p16 = c;\n"
        "    *p32 = e;\n"
        "    *p64 = g;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) { diag_report_destroy(diag); return false; }
    ILModule* mod = surface_lower_module(smod, NULL, false);
    char* output = malloc(1024 * 1024);
    FILE* out = fmemopen(output, 1024 * 1024, "w");
    qbe_emit_module(mod, out);
    fclose(out);

    ASSERT(strstr(output, "=w loadub") != NULL, "Should emit loadub for u8");
    ASSERT(strstr(output, "=w loadsb") != NULL, "Should emit loadsb for i8");
    ASSERT(strstr(output, "=w loaduh") != NULL, "Should emit loaduh for u16");
    ASSERT(strstr(output, "=w loadsh") != NULL, "Should emit loadsh for i16");
    ASSERT(strstr(output, "=w loadw") != NULL,  "Should emit loadw for u32/i32");
    ASSERT(strstr(output, "=l loadl") != NULL,  "Should emit loadl for u64");

    free(output); il_mod_free(mod); surface_mod_free(smod); diag_report_destroy(diag);
    return true;
}

static bool test_qbe_signedness_arith(void) {
    const char* source = 
        "fn main() {\n"
        "    let a: u32 = 10;\n"
        "    let b: u32 = 3;\n"
        "    let c = a / b;\n"
        "    let d = a % b;\n"
        "    let e = a < b;\n"
        "    let f = a > b;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) { diag_report_destroy(diag); return false; }
    ILModule* mod = surface_lower_module(smod, NULL, false);
    char* output = malloc(1024 * 1024);
    FILE* out = fmemopen(output, 1024 * 1024, "w");
    qbe_emit_module(mod, out);
    fclose(out);

    ASSERT(strstr(output, "=w udiv") != NULL, "Should emit udiv for u32");
    ASSERT(strstr(output, "=w urem") != NULL, "Should emit urem for u32");
    ASSERT(strstr(output, "=w cultw") != NULL, "Should emit cultw for u32");
    ASSERT(strstr(output, "=w cugtw") != NULL, "Should emit cugtw for u32");

    free(output); il_mod_free(mod); surface_mod_free(smod); diag_report_destroy(diag);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    
    RUN_TEST(test_float_conversions_emit);
    RUN_TEST(test_qbe_type_mapping);
    RUN_TEST(test_qbe_ssa_mapping);
    RUN_TEST(test_qbe_arith_emission);
    RUN_TEST(test_qbe_phi_emission);
    RUN_TEST(test_qbe_struct_layout_emission);
    RUN_TEST(test_qbe_signedness_e2e);
    RUN_TEST(test_qbe_signedness_arith);
    
    printf("[%2d/%2d] Consolidated QBE Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
