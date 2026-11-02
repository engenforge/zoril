#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_match_range_inclusive(void) {
    const char* src = 
        "fn test_match(x: i32) -> i32 {\n"
        "    match x {\n"
        "        1..=10 => 1,\n"
        "        20..=30 => 2,\n"
        "        _ => 0\n"
        "    }\n"
        "}\n";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should produce a module for inclusive range match");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed for inclusive range match");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_match_range_char(void) {
    const char* src = 
        "fn test_match(x: u8) -> bool {\n"
        "    match x {\n"
        "        'a'..='z' | 'A'..='Z' => true,\n"
        "        _ => false\n"
        "    }\n"
        "}\n";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should produce a module for char range match");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed for char range match");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_match_range_exclusive(void) {
    const char* src = 
        "fn test_match(x: i32) -> i32 {\n"
        "    match x {\n"
        "        1..10 => 1,\n"
        "        _ => 0\n"
        "    }\n"
        "}\n";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should produce a module for exclusive range match");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed for exclusive range match");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    
    RUN_TEST(test_match_range_inclusive);
    RUN_TEST(test_match_range_char);
    RUN_TEST(test_match_range_exclusive);

    printf("[%2d/%2d] Match Range Patterns\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
