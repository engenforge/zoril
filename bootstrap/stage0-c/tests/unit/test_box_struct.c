#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include "surface_parser.h"
#include "surface_lexer.h"
#include "test_harness.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_box_struct_literal(void) {
    const char* src = 
        "struct Arena {\n"
        "    start: *u8,\n"
        "    offset: u64\n"
        "}\n"
        "fn main() {\n"
        "    let a = box Arena {\n"
        "        start: @ptr_cast<*u8>(0),\n"
        "        offset: 0\n"
        "    };\n"
        "}\n";
    
    SurfaceModule* mod = surface_parse_module(src, "test_box_struct.zrl", NULL);
    ASSERT(mod != NULL, "Parser should produce a module");
    surface_mod_free(mod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_box_struct_literal);
    printf("[%2d/%2d] Box Struct Literal Parser Test\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
