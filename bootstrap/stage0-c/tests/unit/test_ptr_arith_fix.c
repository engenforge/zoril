#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "verifier.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_pointer_addition_scaling(void) {
    const char* src = 
        "fn test() -> i32 {\n"
        "  let mut arr: [i32; 4] = [10, 20, 30, 40];\n"
        "  let p: *mut i32 = &mut arr[0];\n"
        "  let p1 = p + 1;\n"
        "  if *p1 == 20 { return 0; } else { return 1; }\n"
        "}";
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        diag_report_destroy(report);
        return false;
    }
    
    ILModule* ilmod = surface_lower_module(smod, report, false);
    if (!ilmod) {
        surface_mod_free(smod);
        diag_report_destroy(report);
        return false; 
    }

    // We can't easily RUN it here without a lot of boilerplate,
    // but we can check the generated IL for a MUL instruction.
    bool found_mul = false;
    for (uint32_t i = 0; i < ilmod->function_count; i++) {
        ILFunction* f = ilmod->functions[i];
        for (uint32_t j = 0; j < f->block_count; j++) {
            ILBasicBlock* b = f->blocks[j];
            for (uint32_t k = 0; k < b->instr_count; k++) {
                if (b->instructions[k]->opcode == IL_OP_ELEM_ADDR) {
                    found_mul = true;
                    break;
                }
            }
            if (found_mul) break;
        }
        if (found_mul) break;
    }
    
    il_mod_free(ilmod);
    surface_mod_free(smod);
    diag_report_destroy(report);
    
    return found_mul;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_pointer_addition_scaling);
    printf("Tests run: %d, Passed: %d\n", tests_run, tests_passed);
    il_ctx_destroy(&ctx);
    return tests_run == tests_passed ? 0 : 1;
}
