#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include "test_harness.h"
#include "surface_lower.h"
#include "surface_parser.h"
#include "il_cfg.h"
#include "il_instr.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;
static bool check_opcodes(const char* source, bool release_mode, ILOpcode expected_plus, ILOpcode expected_wrap_plus) {
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", report);
    if (!smod) {
        diag_report_destroy(report);
        ASSERT(false, "Parsing failed");
    }

    ILModule* mod = surface_lower_module(smod, report, release_mode);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(report);
        ASSERT(false, "Lowering failed");
    }

    bool found_plus = false;
    bool found_wrap_plus = false;

    for (uint32_t i = 0; i < mod->function_count; i++) {
        ILFunction* func = mod->functions[i];
        if (strcmp(func->name, "test") != 0) continue;

        for (uint32_t b = 0; b < func->block_count; b++) {
            ILBasicBlock* block = func->blocks[b];
            for (uint32_t j = 0; j < block->instr_count; j++) {
                const ILInstruction* instr = block->instructions[j];
                if (instr->opcode == expected_plus) found_plus = true;
                if (instr->opcode == expected_wrap_plus) found_wrap_plus = true;
            }
        }
    }

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);

    ASSERT(found_plus, "Expected addition opcode not found");
    ASSERT(found_wrap_plus, "Expected wrapping addition opcode not found");
    return true;
}

static bool test_debug_arith(void) {
    const char* source = 
        "fn test(a: i32, b: i32) -> i32 {\n"
        "    let x = a + b;\n"
        "    let y = a +% b;\n"
        "    x + y\n"
        "}\n";
    
    // In debug mode, + is checked, +% is wrapping
    ASSERT(check_opcodes(source, false, IL_OP_CHECKED_ADD, IL_OP_WRAPPING_ADD), "Debug arith failed");
    return true;
}

static bool test_release_arith(void) {
    const char* source = 
        "fn test(a: i32, b: i32) -> i32 {\n"
        "    let x = a + b;\n"
        "    let y = a +% b;\n"
        "    x + y\n"
        "}\n";
    
    // In release mode, both are wrapping
    ASSERT(check_opcodes(source, true, IL_OP_WRAPPING_ADD, IL_OP_WRAPPING_ADD), "Release arith failed");
    return true;
}

static bool test_all_ops_debug(void) {
    const char* source = 
        "fn test(a: i32, b: i32) -> i32 {\n"
        "    let x = a - b;\n"
        "    let y = a -% b;\n"
        "    let z = a * b;\n"
        "    let w = a *% b;\n"
        "    x + y + z + w\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", report);
    if (!smod) {
        diag_report_destroy(report);
        return false;
    }
    ILModule* mod = surface_lower_module(smod, report, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(report);
        return false;
    }

    bool found_checked_sub = false;
    bool found_wrap_sub = false;
    bool found_checked_mul = false;
    bool found_wrap_mul = false;

    ILFunction* func = NULL;
    for (uint32_t i = 0; i < mod->function_count; i++) {
        if (strcmp(mod->functions[i]->name, "test") == 0) { func = mod->functions[i]; break; }
    }

    if (func) {
        for (uint32_t b = 0; b < func->block_count; b++) {
            ILBasicBlock* block = func->blocks[b];
            for (uint32_t j = 0; j < block->instr_count; j++) {
                const ILInstruction* instr = block->instructions[j];
                if (instr->opcode == IL_OP_CHECKED_SUB) found_checked_sub = true;
                if (instr->opcode == IL_OP_WRAPPING_SUB) found_wrap_sub = true;
                if (instr->opcode == IL_OP_CHECKED_MUL) found_checked_mul = true;
                if (instr->opcode == IL_OP_WRAPPING_MUL) found_wrap_mul = true;
            }
        }
    }

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);

    ASSERT(func != NULL, "test function not found");
    ASSERT(found_checked_sub, "Missing checked_sub");
    ASSERT(found_wrap_sub, "Missing wrap_sub");
    ASSERT(found_checked_mul, "Missing checked_mul");
    ASSERT(found_wrap_mul, "Missing wrap_mul");

    return true;
}

static bool test_assignment_arith(void) {
    const char* source = 
        "fn test(mut a: i32, b: i32) -> i32 {\n"
        "    a += b;\n"
        "    a +%= b;\n"
        "    a -%= b;\n"
        "    a *%= b;\n"
        "    a\n"
        "}\n";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", report);
    if (!smod) {
        diag_report_destroy(report);
        return false;
    }
    ILModule* mod = surface_lower_module(smod, report, false);
    if (!mod) {
        surface_mod_free(smod);
        diag_report_destroy(report);
        return false;
    }

    bool found_checked_add = false;
    bool found_wrap_add = false;
    bool found_wrap_sub = false;
    bool found_wrap_mul = false;

    ILFunction* func = NULL;
    for (uint32_t i = 0; i < mod->function_count; i++) {
        if (strcmp(mod->functions[i]->name, "test") == 0) { func = mod->functions[i]; break; }
    }

    if (func) {
        for (uint32_t b = 0; b < func->block_count; b++) {
            ILBasicBlock* block = func->blocks[b];
            for (uint32_t j = 0; j < block->instr_count; j++) {
                const ILInstruction* instr = block->instructions[j];
                if (instr->opcode == IL_OP_CHECKED_ADD) found_checked_add = true;
                if (instr->opcode == IL_OP_WRAPPING_ADD) found_wrap_add = true;
                if (instr->opcode == IL_OP_WRAPPING_SUB) found_wrap_sub = true;
                if (instr->opcode == IL_OP_WRAPPING_MUL) found_wrap_mul = true;
            }
        }
    }

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);

    ASSERT(func != NULL, "test function not found");
    ASSERT(found_checked_add, "Missing checked_add in assignment");
    ASSERT(found_wrap_add, "Missing wrap_add in assignment");
    ASSERT(found_wrap_sub, "Missing wrap_sub in assignment");
    ASSERT(found_wrap_mul, "Missing wrap_mul in assignment");

    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_debug_arith);
    RUN_TEST(test_release_arith);
    RUN_TEST(test_all_ops_debug);
    RUN_TEST(test_assignment_arith);
    il_ctx_destroy(&ctx);
    return 0;
}
