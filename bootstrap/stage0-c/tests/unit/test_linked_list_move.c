#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "verifier.h"
#include "il_print.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_linked_list_move(void) {
    const char* source = 
        "enum List<T> {\n"
        "    Nil,\n"
        "    Cons((T, Box<List<T>>)),\n"
        "}\n"
        "fn cons<T>(head: T, tail: List<T>) -> List<T> {\n"
        "    return List.Cons((head, box tail));\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    let l = cons(10, List.Nil);\n"
        "    return 0;\n"
        "}\n";

    DiagnosticReport* diag = diag_report_create();
    SurfaceModule* smod = surface_parse_module(source, "test_move.zrl", diag);
    ASSERT(smod != NULL, "Parse failed");

    ILModule* mod = surface_lower_module(smod, diag, false);
    if (!mod) {
        diag_report_print(diag, stderr);
    }
    ASSERT(mod != NULL, "Lowering failed");

    VerificationResult vres = verify_module(mod);
    if (!vres.is_safe) {
        il_mod_print(mod, stderr);
        for (uint32_t i = 0; i < vres.error_count; i++) {
            fprintf(stderr, "Verification error in %s: %s\n", vres.errors[i].func_name, vres.errors[i].message);
        }
    }
    ASSERT(vres.is_safe, "Verifier failed");
    verify_result_free(&vres);

    il_mod_free(mod);
    surface_mod_free(smod);
    diag_report_destroy(diag);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_linked_list_move);
    printf("[%2d/%2d] Linked List Move Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
