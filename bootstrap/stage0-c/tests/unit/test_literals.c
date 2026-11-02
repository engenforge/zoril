#include "verifier.h"
#include "il_cfg.h"
#include "qbe_emit.h"
#include "surface_lower.h"
#include "surface_parser.h"
#include "surface_ast.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_lexer.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_hex_literal(void) {
    const char* src = "0xFF 0x1A_2B";
    Lexer lexer = lexer_create(src);
    
    Token tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_INT, "Should be int");
    ASSERT(tok.as.int_val == 255, "0xFF is 255");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_INT, "Should be int");
    ASSERT(tok.as.int_val == 0x1A2B, "0x1A_2B parsed correctly");
    
    lexer_destroy(&lexer);
    return true;
}

static bool test_binary_literal(void) {
    const char* src = "0b1010 0b1100_0011";
    Lexer lexer = lexer_create(src);
    
    Token tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_INT, "Should be int");
    ASSERT(tok.as.int_val == 10, "0b1010 is 10");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_INT, "Should be int");
    ASSERT(tok.as.int_val == 195, "0b1100_0011 is 195");
    
    lexer_destroy(&lexer);
    return true;
}

static bool test_octal_literal(void) {
    const char* src = "0o755 0o6_4_4";
    Lexer lexer = lexer_create(src);
    
    Token tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_INT, "Should be int");
    ASSERT(tok.as.int_val == 493, "0o755 is 493");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_INT, "Should be int");
    ASSERT(tok.as.int_val == 420, "0o6_4_4 is 420");
    
    lexer_destroy(&lexer);
    return true;
}

static bool test_decimal_underscores(void) {
    const char* src = "1_000_000 1_2_3.4_5_6";
    Lexer lexer = lexer_create(src);
    
    Token tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_INT, "Should be int");
    ASSERT(tok.as.int_val == 1000000, "1_000_000 is 1000000");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_FLOAT, "Should be float");
    ASSERT(tok.as.float_val > 123.455 && tok.as.float_val < 123.457, "1_2_3.4_5_6 is 123.456");
    
    lexer_destroy(&lexer);
    return true;
}

static bool test_suffixes(void) {
    const char* src = "123u64 0xFFu8 3.14f32";
    Lexer lexer = lexer_create(src);
    
    Token tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_INT, "Should be int");
    ASSERT(tok.as.int_val == 123, "Value should be 123");
    ASSERT(tok.suffix && strcmp(tok.suffix, "u64") == 0, "Suffix should be u64");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_INT, "Should be int");
    ASSERT(tok.as.int_val == 255, "Value should be 255");
    ASSERT(tok.suffix && strcmp(tok.suffix, "u8") == 0, "Suffix should be u8");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_FLOAT, "Should be float");
    ASSERT(tok.suffix && strcmp(tok.suffix, "f32") == 0, "Suffix should be f32");
    lexer_token_free(tok);
    
    lexer_destroy(&lexer);
    return true;
}

static bool test_regression_literal_suffixes(void) {
    const char* src = 
        "fn main() {\n"
        "    let a = 1u8;\n"
        "    let b = 2i16;\n"
        "    let c = 3.0f32;\n"
        "    let d = 4.0f64;\n"
        "}\n";
    
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    ASSERT(smod != NULL, "Parse failed");
    
    const FunctionDecl* f = smod->functions[0];
    
    ASSERT(f->body->statements[0]->as.let.init->type->kind == IL_TY_U8, "1u8 type");
    ASSERT(f->body->statements[1]->as.let.init->type->kind == IL_TY_I16, "2i16 type");
    ASSERT(f->body->statements[2]->as.let.init->type->kind == IL_TY_F32, "3.0f32 type");
    ASSERT(f->body->statements[3]->as.let.init->type->kind == IL_TY_F64, "4.0f64 type");
    
    surface_mod_free(smod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_hex_literal);
    RUN_TEST(test_binary_literal);
    RUN_TEST(test_octal_literal);
    RUN_TEST(test_decimal_underscores);
    RUN_TEST(test_suffixes);
    RUN_TEST(test_regression_literal_suffixes);
    printf("[%2d/%2d] Numeric Literals Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
