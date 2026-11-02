#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_lexer.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_multiline_comments(void) {
    const char* src = "fn /* comment */ main() /* more \n comments */ { }";
    Lexer lexer = lexer_create(src);
    
    Token tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_FN, "Should have found 'fn'");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_IDENT, "Should have found 'main'");
    ASSERT(strcmp(tok.as.ident, "main") == 0, "Should be 'main'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_LPAREN, "Should have found '('");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_RPAREN, "Should have found ')'");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_LBRACE, "Should have found '{'");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_RBRACE, "Should have found '}'");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_EOF, "Should be at EOF");
    
    lexer_destroy(&lexer);
    return true;
}

static bool test_nested_comments(void) {
    const char* src = "fn /* outer /* inner */ outer again */ main() { }";
    Lexer lexer = lexer_create(src);
    
    Token tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_FN, "Should have found 'fn'");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_IDENT, "Should have found 'main'");
    ASSERT(strcmp(tok.as.ident, "main") == 0, "Should be 'main'");
    lexer_token_free(tok);
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_LPAREN, "Should have found '('");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_RPAREN, "Should have found ')'");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_LBRACE, "Should have found '{'");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_RBRACE, "Should have found '}'");
    
    tok = lexer_next(&lexer);
    ASSERT(tok.kind == TOK_EOF, "Should be at EOF");
    
    lexer_destroy(&lexer);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_multiline_comments);
    RUN_TEST(test_nested_comments);
    printf("[%2d/%2d] Multi-line Comment Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
