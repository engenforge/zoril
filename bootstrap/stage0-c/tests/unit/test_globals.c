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

static void cleanup(SurfaceModule* smod, ILModule* mod, const VerificationResult* res) {
    if (mod) il_mod_free(mod);
    if (smod) surface_mod_free(smod);
    if (res) verify_result_free((VerificationResult*)res);
}

static bool test_global_lowering(void) {
    const char* src = 
        "static counter: i32 = 42;\n"
        "const MAX: i32 = 100;\n"
        "fn get_counter() -> i32 { return counter; }\n"
        "fn set_counter(val: i32) { counter = val; }\n";
        
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    if (!smod) { ASSERT(false, "Parser should produce a module"); }
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    if (!il_mod) { surface_mod_free(smod); ASSERT(false, "Lowering should succeed"); }
    
    // Verify get_counter
    ILFunction* get_fn = il_mod_get_func_by_name(il_mod, "get_counter");
    if (!get_fn) { cleanup(smod, il_mod, NULL); ASSERT(false, "get_counter should exist"); }
    
    bool found_gaddr = false;
    bool found_load = false;
    for (uint32_t i = 0; i < get_fn->blocks[0]->instr_count; i++) {
        const ILInstruction* instr = get_fn->blocks[0]->instructions[i];
        if (instr->opcode == IL_OP_GLOBAL_ADDR) found_gaddr = true;
        if (instr->opcode == IL_OP_LOAD) found_load = true;
    }
    if (!found_gaddr) { cleanup(smod, il_mod, NULL); ASSERT(false, "get_counter should use global_addr"); }
    if (!found_load) { cleanup(smod, il_mod, NULL); ASSERT(false, "get_counter should use load"); }
    
    // Verify set_counter
    ILFunction* set_fn = il_mod_get_func_by_name(il_mod, "set_counter");
    if (!set_fn) { cleanup(smod, il_mod, NULL); ASSERT(false, "set_counter should exist"); }
    
    bool found_store = false;
    for (uint32_t i = 0; i < set_fn->blocks[0]->instr_count; i++) {
        const ILInstruction* instr = set_fn->blocks[0]->instructions[i];
        if (instr->opcode == IL_OP_STORE) found_store = true;
    }
    if (!found_store) { cleanup(smod, il_mod, NULL); ASSERT(false, "set_counter should use store"); }
    
    // Verify initial values
    const ILGlobal* g_counter = il_mod_get_global_by_name(il_mod, "counter");
    if (!g_counter) { cleanup(smod, il_mod, NULL); ASSERT(false, "counter global should exist"); }
    if (g_counter->data_len != 4) { cleanup(smod, il_mod, NULL); ASSERT(false, "counter should be 4 bytes"); }
    if (*(int32_t*)g_counter->init_data != 42) { cleanup(smod, il_mod, NULL); ASSERT(false, "counter should be init to 42"); }

    VerificationResult res = verify_module(il_mod);
    bool safe = res.is_safe;
    cleanup(smod, il_mod, &res);
    ASSERT(safe, "IL module should be safe");
    return true;
}

static bool test_const_eval_lowering(void) {
    const char* src = 
        "struct TestStruct {}\n"
        "impl TestStruct {\n"
        "    const Y: u64 = 42 as u64;\n"
        "}\n"
        "const X: i32 = -1 as i32;\n";
        
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) { ASSERT(false, "Parser should produce a module"); }
    
    ILModule* il_mod = surface_lower_module(smod, report, false);
    if (!il_mod) { surface_mod_free(smod); ASSERT(false, "Lowering should succeed"); }
    
    const ILGlobal* g_x = il_mod_get_global_by_name(il_mod, "X");
    if (!g_x) { cleanup(smod, il_mod, NULL); ASSERT(false, "X global should exist"); }
    if (*(int32_t*)g_x->init_data != -1) { cleanup(smod, il_mod, NULL); ASSERT(false, "X should be init to -1"); }

    const ILGlobal* g_y = il_mod_get_global_by_name(il_mod, "TestStruct_Y");
    if (!g_y) { cleanup(smod, il_mod, NULL); ASSERT(false, "TestStruct_Y global should exist"); }
    if (*(uint64_t*)g_y->init_data != 42) { cleanup(smod, il_mod, NULL); ASSERT(false, "TestStruct_Y should be init to 42"); }

    cleanup(smod, il_mod, NULL);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_global_lowering);
    RUN_TEST(test_const_eval_lowering);
    
    printf("[%2d/%2d] Global variable lowering\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
