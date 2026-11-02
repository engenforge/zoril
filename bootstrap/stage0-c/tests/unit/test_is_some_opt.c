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

/* Lower src and return a heap-allocated IL dump string (caller frees).
 * Returns NULL and prints diagnostics on error. */
static char* lower_and_print(const char* src) {
    DiagnosticReport report = {0};
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", &report);
    if (!smod || report.has_errors) return NULL;

    ILModule* mod = surface_lower_module(smod, &report, false);
    surface_mod_free(smod);
    if (!mod || report.has_errors) { if (mod) il_mod_free(mod); return NULL; }

    /* Size the buffer generously. */
    size_t buf_size = 65536;
    char* buf = malloc(buf_size);
    if (!buf) { il_mod_free(mod); return NULL; }
    il_print_module(mod, buf, buf_size);
    il_mod_free(mod);
    return buf;
}

/* A two-arm Option match should use is_some, not variant_match, for the
 * Some arm. */
static bool test_is_some_emitted_for_option_match(void) {
    const char* src =
        "enum Option<T> { None, Some(T) }\n"
        "fn unwrap_or(opt: Option<i32>, def: i32) -> i32 {\n"
        "    match opt {\n"
        "        Some(v) => v,\n"
        "        None => def,\n"
        "    }\n"
        "}\n";

    char* il = lower_and_print(src);
    ASSERT(il != NULL, "Lowering should succeed");

    ASSERT(strstr(il, "is_some") != NULL,
           "Two-arm Option match should emit is_some");
    /* The Some arm must NOT use variant_match — is_some replaces it. */
    ASSERT(strstr(il, "variant_match") == NULL,
           "Two-arm Option match should not use variant_match at all");

    free(il);
    return true;
}

/* When the arms are in reversed order (None first, Some second) the
 * optimization still fires — Some has tag=1 regardless of arm order. */
static bool test_is_some_reversed_arm_order(void) {
    const char* src =
        "enum Option<T> { None, Some(T) }\n"
        "fn unwrap_or_rev(opt: Option<i32>, def: i32) -> i32 {\n"
        "    match opt {\n"
        "        None => def,\n"
        "        Some(v) => v,\n"
        "    }\n"
        "}\n";

    char* il = lower_and_print(src);
    ASSERT(il != NULL, "Lowering should succeed");
    ASSERT(strstr(il, "is_some") != NULL,
           "Reversed-arm Option match should still emit is_some");
    free(il);
    return true;
}

/* A wildcard instead of an explicit None arm is also covered. */
static bool test_is_some_with_wildcard_else(void) {
    const char* src =
        "enum Option<T> { None, Some(T) }\n"
        "fn is_pos(opt: Option<i32>) -> bool {\n"
        "    match opt {\n"
        "        Some(v) => v > 0,\n"
        "        _ => false,\n"
        "    }\n"
        "}\n";

    char* il = lower_and_print(src);
    ASSERT(il != NULL, "Lowering should succeed");
    ASSERT(strstr(il, "is_some") != NULL,
           "Option match with wildcard else should emit is_some");
    free(il);
    return true;
}

/* A three-arm match must NOT use the is_some optimisation. */
static bool test_no_is_some_for_three_arm_match(void) {
    const char* src =
        "enum Tri { A, B(i32), C }\n"
        "fn tri(t: Tri) -> i32 {\n"
        "    match t {\n"
        "        A => 1,\n"
        "        B(v) => v,\n"
        "        C => 3,\n"
        "    }\n"
        "}\n";

    char* il = lower_and_print(src);
    ASSERT(il != NULL, "Lowering should succeed");
    ASSERT(strstr(il, "is_some") == NULL,
           "Three-arm match must not use is_some");
    ASSERT(strstr(il, "variant_match") != NULL,
           "Three-arm match must use variant_match");
    free(il);
    return true;
}

/* A borrow match (self: &Option) also fires is_some — used by is_some(). */
static bool test_is_some_on_borrow(void) {
    const char* src =
        "enum Option<T> { None, Some(T) }\n"
        "fn check(opt: &Option<i32>) -> bool {\n"
        "    match opt {\n"
        "        Some(_) => true,\n"
        "        None => false,\n"
        "    }\n"
        "}\n";

    char* il = lower_and_print(src);
    ASSERT(il != NULL, "Lowering borrow match should succeed");
    ASSERT(strstr(il, "is_some") != NULL,
           "Borrow match on Option should emit is_some");
    free(il);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);

    RUN_TEST(test_is_some_emitted_for_option_match);
    RUN_TEST(test_is_some_reversed_arm_order);
    RUN_TEST(test_is_some_with_wildcard_else);
    RUN_TEST(test_no_is_some_for_three_arm_match);
    RUN_TEST(test_is_some_on_borrow);

    printf("Results: %d/%d passed\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_passed == tests_run) ? 0 : 1;
}
