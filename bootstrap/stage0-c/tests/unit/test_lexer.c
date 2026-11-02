#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_lexer.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_lex_minimal(void) {
    const char* src = "fn main() { return 0; }";
    Lexer lexer = lexer_create(src);
    
    Token tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_FN, "Should be 'fn'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_IDENT, "Should be ident");
    ASSERT(strcmp(tok.as.ident, "main") == 0, "Ident should be 'main'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_LPAREN, "Should be '('");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_RPAREN, "Should be ')'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_LBRACE, "Should be '{'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_RETURN, "Should be 'return'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_INT, "Should be int");
    ASSERT(tok.as.int_val == 0, "Int should be 0");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_SEMICOLON, "Should be ';'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_RBRACE, "Should be '}'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_EOF, "Should be EOF");
    lexer_token_free(tok);
    
    lexer_destroy(&lexer);
    return true;
}

static bool test_lex_comments(void) {
    const char* src = "// comment\nfn // more comment\n main() {}";
    Lexer lexer = lexer_create(src);
    
    Token tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_FN, "Should skip leading comment and find 'fn'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_IDENT, "Should skip comment after 'fn' and find 'main'");
    ASSERT(strcmp(tok.as.ident, "main") == 0, "Ident should be 'main'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_LPAREN, "Should be '('");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_RPAREN, "Should be ')'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_LBRACE, "Should be '{'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_RBRACE, "Should be '}'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_EOF, "Should be EOF");
    lexer_token_free(tok);
    
    lexer_destroy(&lexer);
    return true;
}

static bool test_lex_ranges(void) {
    const char* src = ".. ..=";
    Lexer lexer = lexer_create(src);
    
    Token tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_DOTDOT, "Should be '..'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_DOTDOTEQ, "Should be '..='");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_EOF, "Should be EOF");
    lexer_token_free(tok);
    
    lexer_destroy(&lexer);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_lex_minimal);
    RUN_TEST(test_lex_comments);
    RUN_TEST(test_lex_ranges);

    printf("[%2d/%2d] Surface Syntax Lexer\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
