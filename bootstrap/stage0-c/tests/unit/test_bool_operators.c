#include "qbe_emit.h"
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
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_bool_compound_assign(void) {
    const char* source = 
        "fn main() {\n"
        "    let mut a: bool = true;\n"
        "    a &= false;\n"
        "    let mut b: bool = false;\n"
        "    b |= true;\n"
        "    let mut c: bool = true;\n"
        "    c ^= true;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", diag);
    if (!smod) {
        diag_render_terminal(diag);
        diag_report_destroy(diag);
        return false;
    }

    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(diag);
        return false;
    }

    VerificationResult vres = verify_module(mod);
    bool is_safe = vres.is_safe;
    if (!is_safe) {
        printf("Verification failed:\n");
        for (uint32_t i = 0; i < vres.error_count; i++) {
            printf("  %s at block %u, instr %u\n", vres.errors[i].message, vres.errors[i].block_id, vres.errors[i].instr_index);
        }
    }
    verify_result_free(&vres);
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return is_safe;
}

static bool test_bool_constant_folding(void) {
    const char* source = 
        "fn main() -> bool {\n"
        "    return !true;\n"
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

    // Explicitly trigger constant folding
    #include "il_pass.h"
    for (uint32_t i = 0; i < mod->function_count; i++) {
        il_pass_const_fold(NULL, mod->functions[i]);
    }

    // Verify it was folded to a constant
    ILFunction* main_fn = mod->functions[0];
    bool found_xor = false;
    for (uint32_t i = 0; i < main_fn->block_count; i++) {
        const ILBasicBlock* b = main_fn->blocks[i];
        for (uint32_t j = 0; j < b->instr_count; j++) {
            if (b->instructions[j]->opcode == IL_OP_XOR) found_xor = true;
        }
    }
    ASSERT(found_xor == false, "XOR should have been constant folded");

    VerificationResult vres = verify_module(mod);
    bool is_safe = vres.is_safe;
    verify_result_free(&vres);

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return is_safe;
}

static bool test_complex_prefix_postfix(void) {
    const char* source = 
        "struct Wrapper { flag: bool }\n"
        "fn main() {\n"
        "    let w = Wrapper { flag: true };\n"
        "    let x = !w.flag;\n"
        "    let p = &w;\n"
        "    let y = !p.flag;\n"
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

    VerificationResult vres = verify_module(mod);
    bool is_safe = vres.is_safe;
    if (!is_safe) {
        printf("Verification failed:\n");
        for (uint32_t i = 0; i < vres.error_count; i++) {
            printf("  %s at block %u, instr %u\n", vres.errors[i].message, vres.errors[i].block_id, vres.errors[i].instr_index);
        }
    }
    verify_result_free(&vres);
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return is_safe;
}

static bool test_logical_short_circuit(void) {
    const char* source = 
        "fn main(a: bool, b: bool, c: bool) -> bool {\n"
        "    let x = a && b;\n"
        "    let y = b || c;\n"
        "    return x && y;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test_short_circuit.zrl", diag);
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

    VerificationResult vres = verify_module(mod);
    bool is_safe = vres.is_safe;
    verify_result_free(&vres);

    // Verify that PHI nodes were generated for short-circuiting
    ILFunction* main_fn = mod->functions[0];
    int phi_count = 0;
    for (uint32_t i = 0; i < main_fn->block_count; i++) {
        const ILBasicBlock* b = main_fn->blocks[i];
        for (uint32_t j = 0; j < b->instr_count; j++) {
            if (b->instructions[j]->opcode == IL_OP_PHI) {
                phi_count++;
            }
        }
    }
    
    ASSERT(phi_count == 3, "Expected 3 PHI nodes for 3 logical operators");
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return is_safe;
}

// id:042 — il_build_cmp_eq / il_build_cmp_ne returned NULL when operands were
// pointer or box types because validate_arithmetic_operands did not allow them.
static bool test_regression_ptr_cmp_not_null(void) {
    const ILType * i32_ty  = il_type_i32();
    const ILType * bool_ty = il_type_bool();
    const ILType * ptr_ty  = il_type_ptr(i32_ty, REGION_LOCAL, false);
    const ILType * box_ty  = il_type_box(i32_ty, REGION_LOCAL, true);

    ILValue p1 = { .id = 1, .type = ptr_ty };
    ILValue p2 = { .id = 2, .type = ptr_ty };
    ILInstruction* eq_ptr = il_build_cmp_eq(p1, p2, bool_ty);
    ASSERT(eq_ptr != NULL, "cmp_eq on two PTR values must not return NULL");
    ILInstruction* ne_ptr = il_build_cmp_ne(p1, p2, bool_ty);
    ASSERT(ne_ptr != NULL, "cmp_ne on two PTR values must not return NULL");

    ILValue b1 = { .id = 3, .type = box_ty };
    ILValue b2 = { .id = 4, .type = box_ty };
    ILInstruction* eq_box = il_build_cmp_eq(b1, b2, bool_ty);
    ASSERT(eq_box != NULL, "cmp_eq on two BOX values must not return NULL");
    ILInstruction* ne_box = il_build_cmp_ne(b1, b2, bool_ty);
    ASSERT(ne_box != NULL, "cmp_ne on two BOX values must not return NULL");

    il_instr_free(eq_ptr);
    il_instr_free(ne_ptr);
    il_instr_free(eq_box);
    il_instr_free(ne_box);
    
    
    
    
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_bool_compound_assign);
    RUN_TEST(test_bool_constant_folding);
    RUN_TEST(test_complex_prefix_postfix);
    RUN_TEST(test_logical_short_circuit);
    
    RUN_TEST(test_regression_ptr_cmp_not_null);
    printf("[%2d/%2d] Bool Operator Robustness\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
