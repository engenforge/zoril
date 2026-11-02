#ifndef SURFACE_LEXER_H
#define SURFACE_LEXER_H

#include <stdint.h>
#include <stdbool.h>

typedef enum {
    TOK_FN,
    TOK_IDENT,
    TOK_LPAREN,
    TOK_RPAREN,
    TOK_LBRACE,
    TOK_RBRACE,
    TOK_LBRACKET,
    TOK_RBRACKET,
    TOK_RETURN,
    TOK_INT,
    TOK_FLOAT,
    TOK_STRING,
    TOK_TRUE,
    TOK_FALSE,
    TOK_F32,
    TOK_F64,
    TOK_SEMICOLON,
    TOK_COLON,
    TOK_COLONCOLON,
    TOK_COMMA,
    TOK_ARROW,
    TOK_LET,
    TOK_MUT,
    TOK_AS,
    TOK_ASSIGN,
    TOK_PLUS_ASSIGN,
    TOK_MINUS_ASSIGN,
    TOK_STAR_ASSIGN,
    TOK_SLASH_ASSIGN,
    TOK_PERCENT_ASSIGN,
    TOK_AMP_ASSIGN,
    TOK_PIPE_ASSIGN,
    TOK_XOR_ASSIGN,
    TOK_SHL_ASSIGN,
    TOK_SHR_ASSIGN,
    TOK_WHILE,
    TOK_FOR,
    TOK_BREAK,
    TOK_CONTINUE,
    TOK_IN,
    TOK_LOOP,
    TOK_NEVER,
    TOK_DOTDOT,
    TOK_DOTDOTEQ,
    TOK_ELLIPSIS,
    TOK_DEFER,
    TOK_IF,
    TOK_ELSE,
    TOK_STRUCT,
    TOK_ENUM,
    TOK_TYPE,
    TOK_TRAIT,
    TOK_IMPL,
    TOK_BOX,
    TOK_MATCH,
    TOK_CONST,
    TOK_STATIC,
    TOK_IMPORT,
    TOK_PUB,
    TOK_EXTERN,
    TOK_ANNOT,
    TOK_HASH,
    TOK_AMP,
    TOK_AMP_AMP,
    TOK_BANG,
    TOK_PLUS,
    TOK_MINUS,
    TOK_STAR,
    TOK_SLASH,
    TOK_PERCENT,
    TOK_OR,
    TOK_PIPE_PIPE,
    TOK_XOR,
    TOK_SHL,
    TOK_SHR,
    TOK_LT,
    TOK_LE,
    TOK_GT,
    TOK_GE,
    TOK_EQ,
    TOK_NE,
    TOK_DOT,
    TOK_QUESTION,
    TOK_SIZEOF,
    TOK_ALIGNOF,
    TOK_PLUS_PERCENT,
    TOK_MINUS_PERCENT,
    TOK_STAR_PERCENT,
    TOK_PLUS_PERCENT_ASSIGN,
    TOK_MINUS_PERCENT_ASSIGN,
    TOK_STAR_PERCENT_ASSIGN,
    TOK_UNSAFE,
    TOK_EOF,
    TOK_ERROR,
} TokenKind;

typedef struct {
    TokenKind kind;
    union {
        char* ident;
        struct {
            char* val;
            uint32_t len;
        } str;
        uint64_t int_val;
        double float_val;
    } as;
    char* suffix;
    uint32_t line;
    uint32_t col;
    uint32_t offset;
    uint32_t length;
} Token;

typedef struct {
    const char* src;
    size_t pos;
    size_t len;
    uint32_t line;
    uint32_t col;
} Lexer;

Lexer lexer_create(const char* src);
void lexer_destroy(Lexer* lexer);
Token lexer_next(Lexer* lexer);
void lexer_token_free(Token tok);
void lexer_token_print(Token tok, char* buf, size_t max_len);

#endif
