#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include "test_harness.h"
#include "surface_lower.h"
#include "surface_parser.h"
#include "il_cfg.h"
#include "il_instr.h"
#include "il_pass.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_drop_registration(void) {
    const char* source = 
        "struct MyBox { data: i32 }\n"
        "trait Drop { fn drop(self: MyBox); }\n"
        "impl Drop for MyBox {\n"
        "    fn drop(self: MyBox) {\n"
        "    }\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", report);
    ASSERT(smod != NULL, "Module parsing failed");

    ILModule* mod = surface_lower_module(smod, report, false);
    ASSERT(mod != NULL, "Module lowering failed");

    const ILTypeDef* ityp = NULL;
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        if (strcmp(mod->type_defs[i]->name, "MyBox") == 0) {
            ityp = mod->type_defs[i];
            break;
        }
    }
    ASSERT(ityp != NULL, "MyBox type def not found");
    ABORT_IF_NULL(ityp);
    ASSERT(ityp->drop_fn_name != NULL, "drop_fn_name should not be NULL");
    ASSERT(strcmp(ityp->drop_fn_name, "MyBox_drop") == 0, "drop_fn_name should be MyBox_drop");

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

static bool test_generic_drop_registration(void) {
    const char* source = 
        "struct GenericBox<T> { data: T }\n"
        "trait Drop { fn drop(self: GenericBox<T>); }\n"
        "impl Drop for GenericBox<T> {\n"
        "    fn drop(self: GenericBox<T>) {\n"
        "    }\n"
        "}\n"
        "fn main() {\n"
        "    let b: GenericBox<i32> = GenericBox { data: 42 };\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", report);
    ASSERT(smod != NULL, "Module parsing failed");

    for (uint32_t i = 0; i < smod->impl_count; i++) {
        fprintf(stderr, "Parsed impl: trait=%s, target=%s\n", smod->impls[i]->trait_name ? smod->impls[i]->trait_name : "NULL", smod->impls[i]->target_name);
    }

    ILModule* mod = surface_lower_module(smod, report, false);
    ASSERT(mod != NULL, "Module lowering failed");

    const ILTypeDef* ityp = NULL;
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        fprintf(stderr, "Found type: %s\n", mod->type_defs[i]->name);
        if (strcmp(mod->type_defs[i]->name, "GenericBox_i32") == 0) {
            ityp = mod->type_defs[i];
            break;
        }
    }
    ASSERT(ityp != NULL, "GenericBox_i32 type def not found");
    ABORT_IF_NULL(ityp);
    ASSERT(ityp->drop_fn_name != NULL, "drop_fn_name should not be NULL");
    ASSERT(strcmp(ityp->drop_fn_name, "GenericBox_i32_drop") == 0, "drop_fn_name should be GenericBox_i32_drop");

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

static bool test_drop_insertion_at_scope_exit(void) {
    const char* source = 
        "struct Droppable { data: i32 }\n"
        "trait Drop { fn drop(self: Droppable); }\n"
        "impl Drop for Droppable {\n"
        "    fn drop(self: Droppable) {}\n"
        "}\n"
        "fn test() {\n"
        "    let d: Droppable = Droppable { data: 1 };\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", report);
    ASSERT(smod != NULL, "Module parsing failed");

    ILModule* mod = surface_lower_module(smod, report, false);
    ASSERT(mod != NULL, "Module lowering failed");

    ILFunction* ifn = il_mod_get_func_by_name(mod, "test");
    ASSERT(ifn != NULL, "test function not found");

    // Verify that a call to Droppable_drop is inserted
    bool found_drop = false;
    for (uint32_t b = 0; b < ifn->block_count; b++) {
        ILBasicBlock* block = ifn->blocks[b];
        for (uint32_t i = 0; i < block->instr_count; i++) {
            const ILInstruction* instr = block->instructions[i];
            if (instr->opcode == IL_OP_CALL) {
                // Find function name for this call
                for (uint32_t f = 0; f < mod->function_count; f++) {
                    if (mod->functions[f]->id == instr->operands.call.func_id) {
                        if (strcmp(mod->functions[f]->name, "Droppable_drop") == 0) {
                            found_drop = true;
                            break;
                        }
                    }
                }
            }
        }
    }
    ASSERT(found_drop, "Droppable_drop call not found at scope exit");

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

static bool test_move_suppresses_drop(void) {
    const char* source = 
        "struct Droppable { data: i32 }\n"
        "trait Drop { fn drop(self: Droppable); }\n"
        "impl Drop for Droppable {\n"
        "    fn drop(self: Droppable) {}\n"
        "}\n"
        "fn consume(d: Droppable) {}\n"
        "fn test() {\n"
        "    let d: Droppable = Droppable { data: 1 };\n"
        "    consume(d);\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", report);
    ASSERT(smod != NULL, "Module parsing failed");

    ILModule* mod = surface_lower_module(smod, report, false);
    ASSERT(mod != NULL, "Module lowering failed");

    ILFunction* ifn = il_mod_get_func_by_name(mod, "test");
    ASSERT(ifn != NULL, "test function not found");

    // Verify that only ONE call to Droppable_drop exists (the one in 'consume', or none in 'test')
    // Wait, 'consume' also takes Droppable by value, so it should also drop it!
    // But 'test' should NOT drop it because it was moved.
    
    uint32_t drop_calls = 0;
    for (uint32_t b = 0; b < ifn->block_count; b++) {
        ILBasicBlock* block = ifn->blocks[b];
        for (uint32_t i = 0; i < block->instr_count; i++) {
            const ILInstruction* instr = block->instructions[i];
            if (instr->opcode == IL_OP_CALL) {
                const ILFunction* callee = NULL;
                for (uint32_t f = 0; f < mod->function_count; f++) {
                    if (mod->functions[f]->id == instr->operands.call.func_id) {
                        callee = mod->functions[f];
                        break;
                    }
                }
                if (callee && strcmp(callee->name, "Droppable_drop") == 0) {
                    drop_calls++;
                }
            }
        }
    }
    ASSERT(drop_calls == 0, "Droppable_drop should NOT be called in test() because value was moved");

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

static bool test_early_return_drop(void) {
    const char* source = 
        "enum Result<T, E> { Ok(T), Err(E) }\n"
        "struct Droppable { data: i32 }\n"
        "trait Drop { fn drop(self: Droppable); }\n"
        "impl Drop for Droppable {\n"
        "    fn drop(self: Droppable) {}\n"
        "}\n"
        "fn test() -> Result<i32, i32> {\n"
        "    let d: Droppable = Droppable { data: 1 };\n"
        "    let res: Result<i32, i32> = Result.Err(1);\n"
        "    res?;\n"
        "    Result.Ok(0)\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test.zrl", report);
    ASSERT(smod != NULL, "Module parsing failed");

    ILModule* mod = surface_lower_module(smod, report, false);
    ASSERT(mod != NULL, "Module lowering failed");

    ILFunction* ifn = il_mod_get_func_by_name(mod, "test");
    ASSERT(ifn != NULL, "test function not found");

    // Run auto-drop pass
    il_func_auto_drop(mod, ifn);

    // We expect TWO calls to Droppable_drop in test():
    // 1. One before the early return from 'res?' (in the Error block)
    // 2. One before the normal return at the end
    
    uint32_t drop_calls = 0;
    for (uint32_t b = 0; b < ifn->block_count; b++) {
        ILBasicBlock* block = ifn->blocks[b];
        for (uint32_t i = 0; i < block->instr_count; i++) {
            const ILInstruction* instr = block->instructions[i];
            if (instr->opcode == IL_OP_CALL) {
                const ILFunction* callee = NULL;
                for (uint32_t f = 0; f < mod->function_count; f++) {
                    if (mod->functions[f]->id == instr->operands.call.func_id) {
                        callee = mod->functions[f];
                        break;
                    }
                }
                if (callee && strcmp(callee->name, "Droppable_drop") == 0) {
                    drop_calls++;
                }
            }
        }
    }
    ASSERT(drop_calls >= 2, "Droppable_drop should be called at both return points (normal and early via ?)");

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_drop_registration);
    RUN_TEST(test_generic_drop_registration);
    RUN_TEST(test_drop_insertion_at_scope_exit);
    RUN_TEST(test_move_suppresses_drop);
    RUN_TEST(test_early_return_drop);
    printf("[%2d/%2d] Drop Trait Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
