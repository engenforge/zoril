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

static bool test_implicit_return(void) {
    const char* src = "fn main() -> i32 { 42 }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    if (!smod) return false;
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    if (!il_mod) { surface_mod_free(smod); return false; }
    
    const ILFunction* func = il_mod->functions[0];
    bool found_ret = false;
    for (uint32_t b = 0; b < func->block_count; b++) {
        const ILBasicBlock* blk = func->blocks[b];
        for (uint32_t i = 0; i < blk->instr_count; i++) {
            if (blk->instructions[i]->opcode == IL_OP_RETURN) {
                found_ret = true;
                break;
            }
        }
    }
    
    VerificationResult v_res = verify_module(il_mod);
    bool success = found_ret && v_res.is_safe;
    if (!success) {
        fprintf(stderr, "[FAIL] %s:%d: Module should be valid and have ret\n", __FILE__, __LINE__);
        for (uint32_t i = 0; i < v_res.error_count; i++) {
            fprintf(stderr, "  %s at block %u, instr %u\n", v_res.errors[i].message, v_res.errors[i].block_id, v_res.errors[i].instr_index);
        }
    }
    verify_result_free(&v_res);
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return success;
}

static bool test_binary_operators(void) {
    const char* src = "fn main() -> bool { (1 + 2 * 3) == 7 }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    if (!smod) return false;
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    if (!il_mod) { surface_mod_free(smod); return false; }
    
    VerificationResult v_res = verify_module(il_mod);
    bool success = v_res.is_safe;
    if (!success) {
        fprintf(stderr, "[FAIL] %s:%d: Module should be valid\n", __FILE__, __LINE__);
        for (uint32_t i = 0; i < v_res.error_count; i++) {
            fprintf(stderr, "  %s at block %u, instr %u\n", v_res.errors[i].message, v_res.errors[i].block_id, v_res.errors[i].instr_index);
        }
    }
    verify_result_free(&v_res);
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return success;
}

static bool test_if_expression(void) {
    const char* src = "fn main() -> i32 { let x = if true { 1 } else { 2 }; x }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    if (!smod) return false;
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    if (!il_mod) { surface_mod_free(smod); return false; }
    
    VerificationResult v_res = verify_module(il_mod);
    bool success = v_res.is_safe;
    if (!success) {
        fprintf(stderr, "[FAIL] %s:%d: If expression should be valid\n", __FILE__, __LINE__);
        for (uint32_t i = 0; i < v_res.error_count; i++) {
            fprintf(stderr, "  %s at block %u, instr %u\n", v_res.errors[i].message, v_res.errors[i].block_id, v_res.errors[i].instr_index);
        }
    }
    verify_result_free(&v_res);
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return success;
}

// id:043 — two or more sequential bare blocks inside a function body were
// mis-parsed as struct literals ("Expect struct name before '{'").
static bool test_regression_sequential_bare_blocks(void) {
    const char* src =
        "fn main() -> i32 {\n"
        "    { let mut x = 1; }\n"
        "    { let mut y = 2; }\n"
        "    { let mut z = 3; }\n"
        "    return 0;\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        for (uint32_t i = 0; i < report->count; i++)
            fprintf(stderr, "  %s\n", report->diagnostics[i].message);
        diag_report_destroy(report);
        return false;
    }
    // Three sequential block-statements + one return = 4 statements total.
    const FunctionDecl* fn = smod->functions[0];
    ASSERT(fn->body->stmt_count == 4, "Three block-statements + return should be parsed");
    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "sequential bare blocks should lower successfully");
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_implicit_return);
    RUN_TEST(test_binary_operators);
    RUN_TEST(test_if_expression);
    RUN_TEST(test_regression_sequential_bare_blocks);
    printf("[%2d/%2d] Syntax Sugar Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
