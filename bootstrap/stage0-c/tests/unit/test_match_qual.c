#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_ast.h"
#include "surface_parser.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_parse_qualified_match(void) {
    const char* src = 
        "enum Option { Some(i32), None }\n"
        "fn check(x: Option) -> i32 {\n"
        "    match x {\n"
        "        Option.Some(v) => v,\n"
        "        Option.None => 0\n"
        "    }\n"
        "}\n";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    
    ASSERT(mod != NULL, "Parser should produce a module");
    ASSERT(mod->function_count == 1, "Module should have one function");
    
    const BlockExpr* body = mod->functions[0]->body;
    ASSERT(body->stmt_count == 0, "Body should have 0 statements (match is result)");
    ASSERT(body->result != NULL, "Body should have a result");
    const Expression* body_res = body->result;
    ASSERT(body_res->kind == EXPR_MATCH, "Should be match expression");
    
    const MatchExpr* match = &body_res->as.match_expr;
    ASSERT(match->arm_count == 2, "Should have 2 arms");
    
    ASSERT(match->arms[0]->pattern->kind == PATTERN_VARIANT, "First arm should be variant pattern");
    ASSERT(strcmp(match->arms[0]->pattern->as.variant.name, "Option.Some") == 0, "First variant should be Option.Some");
    ASSERT(match->arms[0]->pattern->as.variant.bind_count == 1, "First arm should have 1 binding");
    ASSERT(match->arms[0]->pattern->as.variant.bind_names[0] != NULL, "First arm should have a binding");
    ASSERT(strcmp(match->arms[0]->pattern->as.variant.bind_names[0], "v") == 0, "First binding should be v");
    
    ASSERT(match->arms[1]->pattern->kind == PATTERN_VARIANT, "Second arm should be variant pattern");
    ASSERT(strcmp(match->arms[1]->pattern->as.variant.name, "Option.None") == 0, "Second variant should be Option.None");
    ASSERT(match->arms[1]->pattern->as.variant.bind_count == 0, "Second arm should NOT have bindings");

    surface_mod_free(mod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_parse_qualified_match);

    printf("[%2d/%2d] Qualified Match Pattern\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
