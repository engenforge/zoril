#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "test_harness.h"
#include "il_type.h"
#include "il_instr.h"
#include "il_print.h"
#include "il_cfg.h"
#include "qbe_emit.h"
#include "verifier.h"
#include "surface_parser.h"
#include "surface_lower.h"

int tests_run = 0;
int tests_passed = 0;

/* qbe_map_type(BoxMut<T>) must return "l" — it's a heap pointer. */
static bool test_box_type_mapped_to_l(void) {
    ILType inner;
    inner.kind = IL_TY_U8;

    ILType box_ty;
    box_ty.kind = IL_TY_BOX;
    box_ty.as.box.pointee = &inner;
    box_ty.as.box.region_id = 0;
    box_ty.as.box.is_mut = true;

    const char* mapped = qbe_map_type(&box_ty);
    ASSERT(mapped != NULL, "qbe_map_type(BoxMut<T>) should not return NULL");
    ASSERT(strcmp(mapped, "l") == 0, "qbe_map_type(BoxMut<T>) should return \"l\"");
    return true;
}

/* Emit QBE IR for a function that returns BoxMut<T> and capture the output. */
static bool test_box_fn_qbe_ir(void) {
    const char* src =
        "struct Point { x: i32, y: i32 }\n"
        "fn make_point(x: i32) -> Box<Point> {\n"
        "    let p = box Point { x: x, y: 0 };\n"
        "    return p;\n"
        "}\n"
        "fn use_point(x: i32) -> i32 {\n"
        "    let p = make_point(x);\n"
        "    let val = p.x;\n"
        "    @drop(p);\n"
        "    return val;\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        diag_report_destroy(report);
        return false;
    }

    ILModule* mod = surface_lower_module(smod, NULL, false);
    surface_mod_free(smod);
    diag_report_destroy(report);
    if (!mod) return false;

    VerificationResult vres = verify_module(mod);
    bool safe = vres.is_safe;
    
    bool success = true;
    if (!safe) {
        printf("[FAIL] Verification failed:\n");
        for (uint32_t i = 0; i < vres.error_count; i++) {
            printf("  - %s:%u:%u: %s\n", vres.errors[i].file_path, vres.errors[i].line, vres.errors[i].col, vres.errors[i].message);
        }
        success = false;
        verify_result_free(&vres);
        goto cleanup;
    }
    verify_result_free(&vres);

    pid_t pid = getpid();
    char ssa_path[256], s_path[256];
    snprintf(ssa_path, sizeof(ssa_path), "../build/box_qbe_test_%d.ssa", (int)pid);
    snprintf(s_path, sizeof(s_path), "../build/box_qbe_test_%d.s", (int)pid);

    /* Emit QBE IR to a temporary file */
    FILE* out = fopen(ssa_path, "w");
    if (!out) { success = false; goto cleanup; }
    qbe_emit_module(mod, out);
    fclose(out);

    /* Read the emitted IR back into a buffer */
    FILE* in = fopen(ssa_path, "r");
    if (!in) { success = false; goto cleanup; }
    char buf[8192];
    size_t nread = fread(buf, 1, sizeof(buf) - 1, in);
    buf[nread] = '\0';
    fclose(in);

    /* The function signature for make_point must include return type "l" */
    if (strstr(buf, "export function l $z_make_point") == NULL) { success = false; goto cleanup; }

    /* Call to make_point must capture its BoxMut<T> result as "l" */
    if (strstr(buf, "=l call $z_make_point") == NULL) { success = false; goto cleanup; }

    /* The IR must be valid QBE */
    if (!test_has_backend()) {
        remove(ssa_path);
        remove(s_path);
        il_mod_free(mod);
        static char reason[256];
        snprintf(reason, sizeof(reason), "backend (%s) not found — skipping IR acceptance check", test_get_backend_bin());
        SKIP(reason);
    } else {
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "%s -o %s %s", test_get_backend_bin(), s_path, ssa_path);
        int res = system(cmd);
        if (res != 0) success = false;
    }

cleanup:
    remove(ssa_path);
    remove(s_path);
    il_mod_free(mod);
    return success;
}

static bool test_if_return_no_dead_code(void) {
    const char* src =
        "struct A { cap: u64, off: u64 }\n"
        "fn check(a: Box<A>) -> i32 {\n"
        "    let cap = a.cap;\n"
        "    @drop(a);\n"
        "    if cap != 1 {\n"
        "        return 1;\n"
        "    }\n"
        "    return 0;\n"
        "}\n";

    DiagnosticReport* report = diag_report_create();
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", report);
    if (!smod) {
        diag_report_destroy(report);
        return false;
    }

    ILModule* mod = surface_lower_module(smod, NULL, false);
    surface_mod_free(smod);
    diag_report_destroy(report);
    if (!mod) return false;

    VerificationResult vres = verify_module(mod);
    bool safe = vres.is_safe;
    
    bool success = true;
    if (!safe) {
        printf("[FAIL] Verification failed:\n");
        for (uint32_t i = 0; i < vres.error_count; i++) {
            printf("  - %s:%u:%u: %s\n", vres.errors[i].file_path, vres.errors[i].line, vres.errors[i].col, vres.errors[i].message);
        }
        success = false;
        verify_result_free(&vres);
        goto cleanup;
    }
    verify_result_free(&vres);

    pid_t pid = getpid();
    char ssa_path[256], s_path[256];
    snprintf(ssa_path, sizeof(ssa_path), "../build/box_if_test_%d.ssa", (int)pid);
    snprintf(s_path, sizeof(s_path), "../build/box_if_test_%d.s", (int)pid);

    FILE* out = fopen(ssa_path, "w");
    if (!out) { success = false; goto cleanup; }
    qbe_emit_module(mod, out);
    fclose(out);

    if (!test_has_backend()) {
        remove(ssa_path);
        remove(s_path);
        il_mod_free(mod);
        static char reason[256];
        snprintf(reason, sizeof(reason), "backend (%s) not found — skipping IR acceptance check", test_get_backend_bin());
        SKIP(reason);
    } else {
        char cmd[1024];
        snprintf(cmd, sizeof(cmd), "%s -o %s %s", test_get_backend_bin(), s_path, ssa_path);
        int res = system(cmd);
        if (res != 0) success = false;
    }

cleanup:
    remove(ssa_path);
    remove(s_path);
    il_mod_free(mod);
    return success;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_box_type_mapped_to_l);
    RUN_TEST(test_box_fn_qbe_ir);
    RUN_TEST(test_if_return_no_dead_code);

    printf("%d/%d tests passed.\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == (tests_passed + tests_skipped)) ? 0 : 1;
}
