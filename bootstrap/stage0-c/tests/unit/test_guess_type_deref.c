#include "il_cfg.h"
#include "surface_lower.h"
#include "surface_parser.h"
#include "surface_ast.h"
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "test_harness.h"
#include "il_read.h"
#include "il_type.h"
#include "verifier.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_repro_guess_type_deref(void) {
    const char* src =
        "struct Ast { decls: u64 }\n"
        "fn foo(ast: *mut Ast) {\n"
        "    (*ast).decls = 1;\n"
        "}\n";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "repro.zrl", report);
    ASSERT(smod != NULL, "Should parse");
    
    ILModule* mod = surface_lower_module(smod, NULL, false);
    ASSERT(mod != NULL, "Should lower");
    
    const ILFunction* fn = il_mod_get_func_by_name(mod, "foo");
    ASSERT(fn != NULL, "foo should be present");
    
    bool has_store = false;
    for (uint32_t b = 0; b < fn->block_count; b++) {
        for (uint32_t i = 0; i < fn->blocks[b]->instr_count; i++) {
            if (fn->blocks[b]->instructions[i]->opcode == IL_OP_STORE) {
                has_store = true;
            }
        }
    }
    
    // If guess_type fails to handle deref (*ast), then expected_type for the assignment
    // will be NULL. The RHS '1' will be lowered as i32. 
    // The LHS (*ast).decls has type u64.
    // il_build_store(PtrMut<u64>, i32) returns NULL.
    // So the STORE instruction will be missing.
    ASSERT(has_store, "foo should have a STORE instruction for the field assignment");
    
    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_repro_guess_type_deref);
    printf("[%2d/%2d] Repro guess_type deref\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
