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

static bool test_match_int_literals(void) {
    const char* src = 
        "fn test_match(x: i32) -> i32 {\n"
        "    match x {\n"
        "        1 => 10,\n"
        "        2 => 20,\n"
        "        _ => 30\n"
        "    }\n"
        "}\n";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should produce a module for integer match");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed for integer match");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_match_bool_literals(void) {
    const char* src = 
        "fn test_match(x: bool) -> i32 {\n"
        "    match x {\n"
        "        true => 1,\n"
        "        false => 0\n"
        "    }\n"
        "}\n";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should produce a module for bool match");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed for bool match");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_match_multi_literal(void) {
    const char* src = 
        "fn test_match(x: i32) -> i32 {\n"
        "    match x {\n"
        "        1 | 2 => 10,\n"
        "        3 | 4 | 5 => 20,\n"
        "        _ => 30\n"
        "    }\n"
        "}\n";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should produce a module for multi-literal match");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed for multi-literal match");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
}

static bool test_match_char_literal(void) {
    const char* src = 
        "fn test_match(x: u8) -> i32 {\n"
        "    match x {\n"
        "        'a' => 1,\n"
        "        'b' | 'c' => 2,\n"
        "        _ => 0\n"
        "    }\n"
        "}\n";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parser should produce a module for char match");
    
    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed for char match");
    
    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
    }

    static bool test_match_return_as_expression(void) {
    const char* src =
        "fn test_match(x: i32) -> i32 {\n"
        "    let y = match x {\n"
        "        1 => return 10,\n"
        "        2 => 20,\n"
        "        _ => 30,\n"
        "    };\n"
        "    return y;\n"
        "}\n";

    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parse should succeed for match with return arm");

    ILModule* il_mod = surface_lower_module(smod, NULL, false);
    ASSERT(il_mod != NULL, "Lowering should succeed for match with return arm");

    il_mod_free(il_mod);
    surface_mod_free(smod);
    return true;
    }

    int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);

    RUN_TEST(test_match_int_literals);
    RUN_TEST(test_match_bool_literals);
    RUN_TEST(test_match_multi_literal);
    RUN_TEST(test_match_char_literal);
    RUN_TEST(test_match_return_as_expression);

    printf("[%2d/%2d] Match Literal Patterns\n", tests_passed, tests_run);

    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
