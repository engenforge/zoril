#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "il_type.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_cfg.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_sizeof_primitives(void) {
    const char* src = "fn main() { let a = sizeof(i32); let b = sizeof(u8); let c = sizeof(f64); }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should succeed");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");
    
    const ILFunction* main_func = il_mod_get_func_by_name(il_mod, "main");
    ASSERT(main_func != NULL, "Should find main function");
    
    bool found_4 = false;
    bool found_1 = false;
    bool found_8 = false;
    for (uint32_t i = 0; i < main_func->blocks[0]->instr_count; i++) {
        const ILInstruction* instr = main_func->blocks[0]->instructions[i];
        if (instr->opcode == IL_OP_CONST) {
            if (instr->operands.const_val.u.val == 4) found_4 = true;
            if (instr->operands.const_val.u.val == 1) found_1 = true;
            if (instr->operands.const_val.u.val == 8) found_8 = true;
        }
    }
    ASSERT(found_4, "Should have found sizeof(i32) == 4");
    ASSERT(found_1, "Should have found sizeof(u8) == 1");
    ASSERT(found_8, "Should have found sizeof(f64) == 8");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_alignof_primitives(void) {
    const char* src = "fn main() { let a = alignof(i32); let b = alignof(u8); let c = alignof(f64); }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should succeed");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");
    
    const ILFunction* main_func = il_mod_get_func_by_name(il_mod, "main");
    
    bool found_4 = false;
    bool found_1 = false;
    bool found_8 = false;
    for (uint32_t i = 0; i < main_func->blocks[0]->instr_count; i++) {
        const ILInstruction* instr = main_func->blocks[0]->instructions[i];
        if (instr->opcode == IL_OP_CONST) {
            if (instr->operands.const_val.u.val == 4) found_4 = true;
            if (instr->operands.const_val.u.val == 1) found_1 = true;
            if (instr->operands.const_val.u.val == 8) found_8 = true;
        }
    }
    ASSERT(found_4, "Should have found alignof(i32) == 4");
    ASSERT(found_1, "Should have found alignof(u8) == 1");
    ASSERT(found_8, "Should have found alignof(f64) == 8");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_sizeof_struct(void) {
    const char* src = "struct Point { x: i32, y: i32 } fn main() { let s = sizeof(Point); }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should succeed");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");
    
    const ILFunction* main_func = il_mod_get_func_by_name(il_mod, "main");
    
    bool found_8 = false;
    for (uint32_t i = 0; i < main_func->blocks[0]->instr_count; i++) {
        const ILInstruction* instr = main_func->blocks[0]->instructions[i];
        if (instr->opcode == IL_OP_CONST && instr->operands.const_val.u.val == 8) found_8 = true;
    }
    ASSERT(found_8, "Should have found sizeof(Point) == 8 (i32+i32)");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_sizeof_tuple(void) {
    const char* src = "fn main() { let s = sizeof((i32, u8)); }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should succeed");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");
    
    const ILFunction* main_func = il_mod_get_func_by_name(il_mod, "main");
    
    // (i32, u8) -> i32 (4) at 0, u8 (1) at 4. Total 5. Max align 4. Final size 8.
    bool found_8 = false;
    for (uint32_t i = 0; i < main_func->blocks[0]->instr_count; i++) {
        const ILInstruction* instr = main_func->blocks[0]->instructions[i];
        if (instr->opcode == IL_OP_CONST && instr->operands.const_val.u.val == 8) found_8 = true;
    }
    ASSERT(found_8, "Should have found sizeof((i32, u8)) == 8");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_sizeof_generic_struct(void) {
    const char* src = "struct Wrapper<T> { val: T } fn main() { let s = sizeof(Wrapper<i32>); }";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should succeed");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed");
    
    const ILFunction* main_func = il_mod_get_func_by_name(il_mod, "main");
    
    // Wrapper<i32> -> val: i32 -> size 4.
    bool found_4 = false;
    for (uint32_t i = 0; i < main_func->blocks[0]->instr_count; i++) {
        const ILInstruction* instr = main_func->blocks[0]->instructions[i];
        if (instr->opcode == IL_OP_CONST && instr->operands.const_val.u.val == 4) found_4 = true;
    }
    ASSERT(found_4, "Should have found sizeof(Wrapper<i32>) == 4");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_sizeof_primitives);
    RUN_TEST(test_alignof_primitives);
    RUN_TEST(test_sizeof_struct);
    RUN_TEST(test_sizeof_tuple);
    RUN_TEST(test_sizeof_generic_struct);
    printf("[%2d/%2d] Sizeof/Alignof Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
