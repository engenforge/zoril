#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_instr.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_aggregate_access_optimization(void) {
    const char* src =
        "struct Data { a: i64, b: i64 }\n"
        "fn get_data() -> Data { return Data { a: 1, b: 2 }; }\n"
        "fn test() -> i64 {\n"
        "    let x = get_data().a + get_data().b;\n"
        "    return x;\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    ASSERT(smod != NULL, "Source should parse");

    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Source should lower");

    const ILFunction* fn = il_mod_get_func_by_name(mod, "test");
    ASSERT(fn != NULL, "Function 'test' should exist");

    int alloc_count = 0;
    int aggregate_load_count = 0;

    for (uint32_t b = 0; b < fn->block_count; b++) {
        const ILBasicBlock* block = fn->blocks[b];
        for (uint32_t i = 0; i < block->instr_count; i++) {
            const ILInstruction* instr = block->instructions[i];
            
            if (instr->opcode == IL_OP_ALLOC) {
                alloc_count++;
            }
            
            if (instr->opcode == IL_OP_LOAD) {
                const ILType* res_ty = instr->result_type;
                if (res_ty && (res_ty->kind == IL_TY_STRUCT || res_ty->kind == IL_TY_TUPLE)) {
                    aggregate_load_count++;
                }
            }
        }
    }

    // CURRENT BASELINE: 6 allocs, 2 aggregate loads
    // Original bloat: 12 allocs, 6 aggregate loads
    // First optimization (surgical): 4 allocs, 2 aggregate loads
    printf("DEBUG: test() has %d allocs, %d aggregate loads\n", alloc_count, aggregate_load_count);

    ASSERT(aggregate_load_count <= 2, "Too many aggregate loads");
    ASSERT(alloc_count <= 4, "Too many allocations");

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

static bool test_ensure_assignable_structural_equality(void) {
    const char* src =
        "struct Generic<T> { val: T }\n"
        "fn make_generic() -> Generic<i64> { return Generic<i64> { val: 42 }; }\n"
        "fn test() -> i64 {\n"
        "    // In older unoptimized ensure_assignable, this assignment might cause an IL_OP_MOVE\n"
        "    // due to lack of structural equality check if types are monomorphized independently.\n"
        "    let g: Generic<i64> = make_generic();\n"
        "    return g.val;\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test_ensure.zrl", report);
    ASSERT(smod != NULL, "Source should parse");

    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Source should lower");

    const ILFunction* fn = il_mod_get_func_by_name(mod, "test");
    ASSERT(fn != NULL, "Function 'test' should exist");

    int move_count = 0;

    for (uint32_t b = 0; b < fn->block_count; b++) {
        const ILBasicBlock* block = fn->blocks[b];
        for (uint32_t i = 0; i < block->instr_count; i++) {
            const ILInstruction* instr = block->instructions[i];
            if (instr->opcode == IL_OP_MOVE) {
                const ILType* res_ty = instr->result_type;
                if (res_ty && res_ty->kind == IL_TY_STRUCT) {
                    move_count++;
                }
            }
        }
    }

    printf("DEBUG: test() has %d struct IL_OP_MOVE instructions\n", move_count);

    // ensure_assignable optimization prevents unnecessary structural IL_OP_MOVE instructions
    // during variable assignment for monomorphized or structurally equal generic types.
    ASSERT(move_count == 0, "Structural equality optimization should prevent struct IL_OP_MOVEs");

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    RUN_TEST(test_aggregate_access_optimization);
    RUN_TEST(test_ensure_assignable_structural_equality);
    printf("[%2d/%2d] Stack optimization tests\n", tests_passed, tests_run);
    return (tests_run == tests_passed) ? 0 : 1;
}
