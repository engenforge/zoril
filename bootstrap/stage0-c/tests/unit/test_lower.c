#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_print.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_lower_minimal(void) {
    const char* src = "fn main() -> i32 { return 0; }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should produce a module");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should produce an IL module");
    ASSERT(il_mod->function_count == 1, "IL module should have 1 function");
    
    const ILFunction* func = il_mod->functions[0];
    const ILBasicBlock* block = func->blocks[0];
    
    ASSERT(block->instr_count == 2, "Should have 2 instructions (const and return)");
    ASSERT(block->instructions[0]->opcode == IL_OP_CONST, "First should be const");
    ASSERT(block->instructions[1]->opcode == IL_OP_RETURN, "Second should be return");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_lower_params_and_arith(void) {
    const char* src = "fn add(a: i32, b: i32) -> i32 { return a + b; }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    
    ASSERT(il_mod != NULL, "Lowering should succeed");
    const ILFunction* func = il_mod->functions[0];
    const ILBasicBlock* block = func->blocks[0];
    
    ASSERT(block->instr_count == 2, "Should have 2 instructions (add and return)");
    ASSERT(block->instructions[0]->opcode == IL_OP_CHECKED_ADD, "First should be checked_add");
    ASSERT(block->instructions[1]->opcode == IL_OP_RETURN, "Second should be return");
    
    const ILInstruction* add_instr = block->instructions[0];
    ASSERT(add_instr->operands.binary.left == 2, "Left operand should be id 2 (a)");
    ASSERT(add_instr->operands.binary.right == 3, "Right operand should be id 3 (b)");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_lower_if(void) {
    const char* src = "fn max(a: i32, b: i32) -> i32 { if (a < b) { return b; } else { return a; } }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    
    ASSERT(il_mod != NULL, "Lowering should succeed");
    const ILFunction* func = il_mod->functions[0];
    
    // Check block structure: entry, then, else, join (optional join if both return)
    // Wait, Zoril IL blocks are identified by IDs.
    // In our lowering, we might create 3 or 4 blocks.
    ASSERT(func->block_count >= 3, "Should have at least entry, then, and else blocks");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_lower_defer(void) {
    const char* src = "fn test_defer() -> i32 { defer { return 1; } return 0; }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    
    ASSERT(il_mod != NULL, "Lowering should succeed");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_lower_for(void) {
    const char* src = "fn test_loop() { for i in 0..10 { } }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    
    ASSERT(il_mod != NULL, "Lowering should succeed");
    const ILFunction* func = il_mod->functions[0];
    
    ASSERT(func->block_count >= 4, "Should have at least 4 blocks for for-loop");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_lower_minimal);
    RUN_TEST(test_lower_params_and_arith);
    RUN_TEST(test_lower_if);
    RUN_TEST(test_lower_defer);
    RUN_TEST(test_lower_for);

    printf("[%2d/%2d] Surface to IL Lowering\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
