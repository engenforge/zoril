#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdio.h>
#include "surface_lexer.h"

Lexer lexer_create(const char* src) {
    Lexer lexer;
    lexer.src = src;
    lexer.pos = 0;
    lexer.len = strlen(src);
    lexer.line = 1;
    lexer.col = 1;
    return lexer;
}

void lexer_destroy(Lexer* lexer) {
    (void)lexer;
}

void lexer_token_free(Token tok) {
    if (tok.kind == TOK_IDENT || tok.kind == TOK_ANNOT) {
        free(tok.as.ident);
    } else if (tok.kind == TOK_STRING) {
        free(tok.as.str.val);
    }
    if (tok.suffix) {
        free(tok.suffix);
    }
}

static Token lexer_next_impl(Lexer* lexer) {
    Token tok;
    tok.as.ident = NULL;
    tok.as.int_val = 0;
    tok.suffix = NULL;
    tok.line = lexer->line;
    tok.col = lexer->col;

    if (lexer->pos >= lexer->len) {
        tok.kind = TOK_EOF;
        return tok;
    }

    char c = lexer->src[lexer->pos++];

    if (c == 'r' && lexer->pos < lexer->len && lexer->src[lexer->pos] == '"') {
        lexer->pos++; // skip "
        size_t capacity = 16;
        size_t len = 0;
        char* str = malloc(capacity);
        if (!str) { tok.kind = TOK_ERROR; return tok; }
        while (lexer->pos < lexer->len && lexer->src[lexer->pos] != '"') {
            if (len + 1 >= capacity) {
                capacity *= 2;
                char* new_str = realloc(str, capacity);
                if (!new_str) { free(str); tok.kind = TOK_ERROR; return tok; }
                str = new_str;
            }
            str[len++] = lexer->src[lexer->pos++];
        }
        if (lexer->pos < lexer->len) lexer->pos++; // Skip ending quote
        str[len] = '\0';
        tok.as.str.val = str;
        tok.as.str.len = (uint32_t)len;
        tok.kind = TOK_STRING;
        return tok;
    }

    switch (c) {
        case '(': tok.kind = TOK_LPAREN; return tok;
        case ')': tok.kind = TOK_RPAREN; return tok;
        case '{': tok.kind = TOK_LBRACE; return tok;
        case '}': tok.kind = TOK_RBRACE; return tok;
        case '[': tok.kind = TOK_LBRACKET; return tok;
        case ']': tok.kind = TOK_RBRACKET; return tok;
        case '#': tok.kind = TOK_HASH; return tok;
        case ';': tok.kind = TOK_SEMICOLON; return tok;
        case ':':
            if (lexer->pos < lexer->len && lexer->src[lexer->pos] == ':') {
                lexer->pos++;
                tok.kind = TOK_COLONCOLON;
                return tok;
            }
            tok.kind = TOK_COLON;
            return tok;
        case ',': tok.kind = TOK_COMMA; return tok;
        case '&':
            if (lexer->pos < lexer->len) {
                if (lexer->src[lexer->pos] == '&') {
                    lexer->pos++;
                    tok.kind = TOK_AMP_AMP;
                    return tok;
                } else if (lexer->src[lexer->pos] == '=') {
                    lexer->pos++;
                    tok.kind = TOK_AMP_ASSIGN;
                    return tok;
                }
            }
            tok.kind = TOK_AMP;
            return tok;
        case '+':
            if (lexer->pos < lexer->len) {
                if (lexer->src[lexer->pos] == '=') {
                    lexer->pos++;
                    tok.kind = TOK_PLUS_ASSIGN;
                    return tok;
                } else if (lexer->src[lexer->pos] == '%') {
                    lexer->pos++;
                    if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '=') {
                        lexer->pos++;
                        tok.kind = TOK_PLUS_PERCENT_ASSIGN;
                        return tok;
                    }
                    tok.kind = TOK_PLUS_PERCENT;
                    return tok;
                }
            }
            tok.kind = TOK_PLUS;
            return tok;
        case '*':
            if (lexer->pos < lexer->len) {
                if (lexer->src[lexer->pos] == '=') {
                    lexer->pos++;
                    tok.kind = TOK_STAR_ASSIGN;
                    return tok;
                } else if (lexer->src[lexer->pos] == '%') {
                    lexer->pos++;
                    if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '=') {
                        lexer->pos++;
                        tok.kind = TOK_STAR_PERCENT_ASSIGN;
                        return tok;
                    }
                    tok.kind = TOK_STAR_PERCENT;
                    return tok;
                }
            }
            tok.kind = TOK_STAR;
            return tok;
        case '/':
            if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '=') {
                lexer->pos++;
                tok.kind = TOK_SLASH_ASSIGN;
                return tok;
            }
            tok.kind = TOK_SLASH;
            return tok;
        case '%':
            if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '=') {
                lexer->pos++;
                tok.kind = TOK_PERCENT_ASSIGN;
                return tok;
            }
            tok.kind = TOK_PERCENT;
            return tok;
        case '|':
            if (lexer->pos < lexer->len) {
                if (lexer->src[lexer->pos] == '|') {
                    lexer->pos++;
                    tok.kind = TOK_PIPE_PIPE;
                    return tok;
                } else if (lexer->src[lexer->pos] == '=') {
                    lexer->pos++;
                    tok.kind = TOK_PIPE_ASSIGN;
                    return tok;
                }
            }
            tok.kind = TOK_OR;
            return tok;
        case '^':
            if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '=') {
                lexer->pos++;
                tok.kind = TOK_XOR_ASSIGN;
                return tok;
            }
            tok.kind = TOK_XOR;
            return tok;
        case '<':
            if (lexer->pos < lexer->len) {
                if (lexer->src[lexer->pos] == '=') {
                    lexer->pos++;
                    tok.kind = TOK_LE;
                    return tok;
                } else if (lexer->src[lexer->pos] == '<') {
                    lexer->pos++;
                    if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '=') {
                        lexer->pos++;
                        tok.kind = TOK_SHL_ASSIGN;
                        return tok;
                    }
                    tok.kind = TOK_SHL;
                    return tok;
                }
            }
            tok.kind = TOK_LT;
            return tok;
        case '>':
            if (lexer->pos < lexer->len) {
                if (lexer->src[lexer->pos] == '=') {
                    lexer->pos++;
                    tok.kind = TOK_GE;
                    return tok;
                } else if (lexer->src[lexer->pos] == '>') {
                    lexer->pos++;
                    if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '=') {
                        lexer->pos++;
                        tok.kind = TOK_SHR_ASSIGN;
                        return tok;
                    }
                    tok.kind = TOK_SHR;
                    return tok;
                }
            }
            tok.kind = TOK_GT;
            return tok;
        case '-':
            if (lexer->pos < lexer->len) {
                if (lexer->src[lexer->pos] == '>') {
                    lexer->pos++;
                    tok.kind = TOK_ARROW;
                    return tok;
                } else if (lexer->src[lexer->pos] == '=') {
                    lexer->pos++;
                    tok.kind = TOK_MINUS_ASSIGN;
                    return tok;
                } else if (lexer->src[lexer->pos] == '%') {
                    lexer->pos++;
                    if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '=') {
                        lexer->pos++;
                        tok.kind = TOK_MINUS_PERCENT_ASSIGN;
                        return tok;
                    }
                    tok.kind = TOK_MINUS_PERCENT;
                    return tok;
                }
            }
            tok.kind = TOK_MINUS;
            return tok;
        case '=':
            if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '=') {
                lexer->pos++;
                tok.kind = TOK_EQ;
                return tok;
            }
            if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '>') {
                lexer->pos++;
                tok.kind = TOK_ARROW;
                return tok;
            }
            tok.kind = TOK_ASSIGN;
            return tok;
        case '!':
            if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '=') {
                lexer->pos++;
                tok.kind = TOK_NE;
                return tok;
            }
            tok.kind = TOK_BANG;
            return tok;
        case '?':
            tok.kind = TOK_QUESTION;
            return tok;
        case '.':
            if (lexer->pos + 1 < lexer->len && lexer->src[lexer->pos] == '.' && lexer->src[lexer->pos+1] == '.') {
                lexer->pos += 2;
                tok.kind = TOK_ELLIPSIS;
                return tok;
            }
            if (lexer->pos + 1 < lexer->len && lexer->src[lexer->pos] == '.' && lexer->src[lexer->pos+1] == '=') {
                lexer->pos += 2;
                tok.kind = TOK_DOTDOTEQ;
                return tok;
            }
            if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '.') {
                lexer->pos++;
                tok.kind = TOK_DOTDOT;
                return tok;
            }
            tok.kind = TOK_DOT;
            return tok;
        case '"': {
            size_t capacity = 16;
            size_t len = 0;
            char* str = malloc(capacity);
            if (!str) { tok.kind = TOK_ERROR; return tok; }
            while (lexer->pos < lexer->len && lexer->src[lexer->pos] != '"') {
                if (len + 1 >= capacity) {
                    capacity *= 2;
                    char* new_str = realloc(str, capacity);
                    if (!new_str) { free(str); tok.kind = TOK_ERROR; return tok; }
                    str = new_str;
                }
                if (lexer->src[lexer->pos] == '\\' && lexer->pos + 1 < lexer->len) {
                    lexer->pos++;
                    char esc = lexer->src[lexer->pos++];
                    switch (esc) {
                        case 'n': str[len++] = '\n'; break;
                        case 't': str[len++] = '\t'; break;
                        case 'r': str[len++] = '\r'; break;
                        case '0': str[len++] = '\0'; break;
                        case '\\': str[len++] = '\\'; break;
                        case '"': str[len++] = '"'; break;
                        case '\'': str[len++] = '\''; break;
                        case '\n': break; // skip escaped newline (line continuation)
                        case 'x': {
                            uint8_t val = 0;
                            int count = 0;
                            while (count < 2 && lexer->pos < lexer->len && isxdigit(lexer->src[lexer->pos])) {
                                char hc = lexer->src[lexer->pos++];
                                uint8_t digit = 0;
                                if (isdigit(hc)) digit = (uint8_t)(hc - '0');
                                else if (hc >= 'a' && hc <= 'f') digit = (uint8_t)(hc - 'a' + 10);
                                else if (hc >= 'A' && hc <= 'F') digit = (uint8_t)(hc - 'A' + 10);
                                val = (uint8_t)(val * 16 + digit);
                                count++;
                            }
                            if (count > 0) {
                                str[len++] = (char)val;
                            } else {
                                str[len++] = 'x';
                            }
                            break;
                        }
                        default: str[len++] = esc; break;
                    }
                } else {
                    str[len++] = lexer->src[lexer->pos++];
                }
            }
            if (lexer->pos < lexer->len) lexer->pos++; // Skip ending quote
            str[len] = '\0';
            tok.as.str.val = str;
            tok.as.str.len = (uint32_t)len;
            tok.kind = TOK_STRING;
            return tok;
        }
        case '\'': {
            if (lexer->pos < lexer->len) {
                uint64_t val = 0;
                if (lexer->src[lexer->pos] == '\\' && lexer->pos + 1 < lexer->len) {
                    lexer->pos++;
                    char esc = lexer->src[lexer->pos++];
                    switch (esc) {
                        case 'n': val = '\n'; break;
                        case 't': val = '\t'; break;
                        case 'r': val = '\r'; break;
                        case '0': val = '\0'; break;
                        case '\\': val = '\\'; break;
                        case '"': val = '"'; break;
                        case '\'': val = '\''; break;
                        case 'x': {
                            uint8_t hex_val = 0;
                            int count = 0;
                            while (count < 2 && lexer->pos < lexer->len && isxdigit(lexer->src[lexer->pos])) {
                                char hc = lexer->src[lexer->pos++];
                                uint8_t digit = 0;
                                if (isdigit(hc)) digit = (uint8_t)(hc - '0');
                                else if (hc >= 'a' && hc <= 'f') digit = (uint8_t)(hc - 'a' + 10);
                                else if (hc >= 'A' && hc <= 'F') digit = (uint8_t)(hc - 'A' + 10);
                                hex_val = (uint8_t)(hex_val * 16 + digit);
                                count++;
                            }
                            if (count > 0) {
                                val = (uint64_t)hex_val;
                            } else {
                                val = 'x';
                            }
                            break;
                        }
                        default: val = (uint8_t)esc; break;
                    }
                } else {
                    val = (uint8_t)lexer->src[lexer->pos++];
                }
                if (lexer->pos < lexer->len && lexer->src[lexer->pos] == '\'') {
                    lexer->pos++;
                }
                tok.as.int_val = val;
                tok.kind = TOK_INT;
                return tok;
            }
            tok.kind = TOK_ERROR;
            return tok;
        }
    }

    if (isdigit(c)) {
        lexer->pos--;
        int base = 10;
        bool is_float = false;

        // Check for base prefix
        if (lexer->src[lexer->pos] == '0' && lexer->pos + 1 < lexer->len) {
            char next = lexer->src[lexer->pos + 1];
            if (next == 'x' || next == 'X') {
                base = 16;
                lexer->pos += 2;
            } else if (next == 'b' || next == 'B') {
                base = 2;
                lexer->pos += 2;
            } else if (next == 'o' || next == 'O') {
                base = 8;
                lexer->pos += 2;
            }
        }

        // We need to parse the number manually to ignore underscores
        char num_buf[128];
        size_t num_len = 0;

        // Collect characters ignoring underscores
        while (lexer->pos < lexer->len) {
            char cur = lexer->src[lexer->pos];
            if (cur == '_') {
                lexer->pos++;
                continue;
            }
            if (base == 16 && isxdigit(cur)) {
                if (num_len < sizeof(num_buf) - 1) num_buf[num_len++] = cur;
                lexer->pos++;
            } else if (base == 10 && isdigit(cur)) {
                if (num_len < sizeof(num_buf) - 1) num_buf[num_len++] = cur;
                lexer->pos++;
            } else if (base == 8 && cur >= '0' && cur <= '7') {
                if (num_len < sizeof(num_buf) - 1) num_buf[num_len++] = cur;
                lexer->pos++;
            } else if (base == 2 && (cur == '0' || cur == '1')) {
                if (num_len < sizeof(num_buf) - 1) num_buf[num_len++] = cur;
                lexer->pos++;
            } else if (base == 10 && cur == '.' && lexer->pos + 1 < lexer->len && isdigit(lexer->src[lexer->pos+1])) {
                is_float = true;
                if (num_len < sizeof(num_buf) - 1) num_buf[num_len++] = cur;
                lexer->pos++;
            } else if (base == 10 && is_float && (cur == 'e' || cur == 'E')) {
                if (num_len < sizeof(num_buf) - 1) num_buf[num_len++] = cur;
                lexer->pos++;
                if (lexer->pos < lexer->len && (lexer->src[lexer->pos] == '+' || lexer->src[lexer->pos] == '-')) {
                    if (num_len < sizeof(num_buf) - 1) num_buf[num_len++] = lexer->src[lexer->pos];
                    lexer->pos++;
                }
            } else {
                break;
            }
        }

        num_buf[num_len] = '\0';

        if (is_float) {
            tok.as.float_val = strtod(num_buf, NULL);
            tok.kind = TOK_FLOAT;
        } else {
            tok.as.int_val = strtoull(num_buf, NULL, base);
            tok.kind = TOK_INT;
        }

        // Handle suffix (e.g. 0u64)
        if (lexer->pos < lexer->len && (isalpha(lexer->src[lexer->pos]) || lexer->src[lexer->pos] == '_')) {
            size_t s_start = lexer->pos;
            while (lexer->pos < lexer->len && (isalnum(lexer->src[lexer->pos]) || lexer->src[lexer->pos] == '_')) {
                lexer->pos++;
            }
            size_t s_len = lexer->pos - s_start;
            tok.suffix = malloc(s_len + 1);
            if (tok.suffix) {
                memcpy(tok.suffix, lexer->src + s_start, s_len);
                tok.suffix[s_len] = '\0';
            }
        }

        return tok;
    }

    if (isalpha(c) || c == '_') {
        size_t start = lexer->pos - 1;
        while (lexer->pos < lexer->len && (isalnum(lexer->src[lexer->pos]) || lexer->src[lexer->pos] == '_')) {
            lexer->pos++;
        }
        size_t len = lexer->pos - start;
        char* ident = malloc(len + 1);
        if (!ident) { tok.kind = TOK_ERROR; return tok; }
        memcpy(ident, lexer->src + start, len);
        ident[len] = '\0';

        if (strcmp(ident, "fn") == 0) tok.kind = TOK_FN;
        else if (strcmp(ident, "return") == 0) tok.kind = TOK_RETURN;
        else if (strcmp(ident, "let") == 0) tok.kind = TOK_LET;
        else if (strcmp(ident, "as") == 0) tok.kind = TOK_AS;
        else if (strcmp(ident, "mut") == 0) tok.kind = TOK_MUT;
        else if (strcmp(ident, "while") == 0) tok.kind = TOK_WHILE;
        else if (strcmp(ident, "for") == 0) tok.kind = TOK_FOR;
        else if (strcmp(ident, "break") == 0) tok.kind = TOK_BREAK;
        else if (strcmp(ident, "continue") == 0) tok.kind = TOK_CONTINUE;
        else if (strcmp(ident, "in") == 0) tok.kind = TOK_IN;
        else if (strcmp(ident, "loop") == 0) tok.kind = TOK_LOOP;
        else if (strcmp(ident, "never") == 0) tok.kind = TOK_NEVER;
        else if (strcmp(ident, "defer") == 0) tok.kind = TOK_DEFER;
        else if (strcmp(ident, "if") == 0) tok.kind = TOK_IF;
        else if (strcmp(ident, "else") == 0) tok.kind = TOK_ELSE;
        else if (strcmp(ident, "struct") == 0) tok.kind = TOK_STRUCT;
        else if (strcmp(ident, "enum") == 0) tok.kind = TOK_ENUM;
        else if (strcmp(ident, "type") == 0) tok.kind = TOK_TYPE;
        else if (strcmp(ident, "trait") == 0) tok.kind = TOK_TRAIT;
        else if (strcmp(ident, "impl") == 0) tok.kind = TOK_IMPL;
        else if (strcmp(ident, "Box") == 0) tok.kind = TOK_BOX;
        else if (strcmp(ident, "box") == 0) tok.kind = TOK_BOX;
        else if (strcmp(ident, "match") == 0) tok.kind = TOK_MATCH;
        else if (strcmp(ident, "const") == 0) tok.kind = TOK_CONST;
        else if (strcmp(ident, "static") == 0) tok.kind = TOK_STATIC;
        else if (strcmp(ident, "import") == 0) tok.kind = TOK_IMPORT;
        else if (strcmp(ident, "pub") == 0) tok.kind = TOK_PUB;
        else if (strcmp(ident, "extern") == 0) tok.kind = TOK_EXTERN;
        else if (strcmp(ident, "sizeof") == 0) tok.kind = TOK_SIZEOF;
        else if (strcmp(ident, "i8") == 0) tok.kind = TOK_IDENT;
        else if (strcmp(ident, "i16") == 0) tok.kind = TOK_IDENT;
        else if (strcmp(ident, "i32") == 0) tok.kind = TOK_IDENT;
        else if (strcmp(ident, "i64") == 0) tok.kind = TOK_IDENT;
        else if (strcmp(ident, "u8") == 0) tok.kind = TOK_IDENT;
        else if (strcmp(ident, "u16") == 0) tok.kind = TOK_IDENT;
        else if (strcmp(ident, "u32") == 0) tok.kind = TOK_IDENT;
        else if (strcmp(ident, "u64") == 0) tok.kind = TOK_IDENT;
        else if (strcmp(ident, "f32") == 0) tok.kind = TOK_IDENT;
        else if (strcmp(ident, "f64") == 0) tok.kind = TOK_IDENT;
        else if (strcmp(ident, "bool") == 0) tok.kind = TOK_IDENT;
        else if (strcmp(ident, "str") == 0) tok.kind = TOK_IDENT;
        else if (strcmp(ident, "alignof") == 0) tok.kind = TOK_ALIGNOF;
        else if (strcmp(ident, "true") == 0) tok.kind = TOK_TRUE;
        else if (strcmp(ident, "false") == 0) tok.kind = TOK_FALSE;
        else if (strcmp(ident, "unsafe") == 0) tok.kind = TOK_UNSAFE;
        else tok.kind = TOK_IDENT;

        if (tok.kind == TOK_IDENT) {
            tok.as.ident = ident;
        } else {
            free(ident);
        }
        return tok;
    }

    if (c == '@') {
        size_t start = lexer->pos - 1;
        while (lexer->pos < lexer->len && (isalnum(lexer->src[lexer->pos]) || lexer->src[lexer->pos] == '_')) {
            lexer->pos++;
        }
        size_t len = lexer->pos - start;
        tok.as.ident = malloc(len + 1);
        if (tok.as.ident) {
            memcpy(tok.as.ident, lexer->src + start, len);
            tok.as.ident[len] = '\0';
        }
        tok.kind = TOK_ANNOT;
        return tok;
    }

    tok.kind = TOK_ERROR;
    return tok;
}

Token lexer_next(Lexer* lexer) {
    while (lexer->pos < lexer->len) {
        if (isspace(lexer->src[lexer->pos])) {
            if (lexer->src[lexer->pos] == '\n') {
                lexer->line++;
                lexer->col = 1;
            } else {
                lexer->col++;
            }
            lexer->pos++;
        } else if (lexer->pos + 1 < lexer->len && lexer->src[lexer->pos] == '/' && lexer->src[lexer->pos+1] == '/') {
            // Skip single-line comment
            while (lexer->pos < lexer->len && lexer->src[lexer->pos] != '\n') {
                lexer->pos++;
            }
        } else if (lexer->pos + 1 < lexer->len && lexer->src[lexer->pos] == '/' && lexer->src[lexer->pos+1] == '*') {
            // Skip multi-line comment (with nesting)
            int depth = 1;
            lexer->pos += 2; lexer->col += 2;
            while (lexer->pos < lexer->len && depth > 0) {
                if (lexer->src[lexer->pos] == '/' && lexer->pos + 1 < lexer->len && lexer->src[lexer->pos+1] == '*') {
                    depth++;
                    lexer->pos += 2; lexer->col += 2;
                } else if (lexer->src[lexer->pos] == '*' && lexer->pos + 1 < lexer->len && lexer->src[lexer->pos+1] == '/') {
                    depth--;
                    lexer->pos += 2; lexer->col += 2;
                } else {
                    if (lexer->src[lexer->pos] == '\n') {
                        lexer->line++;
                        lexer->col = 1;
                    } else {
                        lexer->col++;
                    }
                    lexer->pos++;
                }
            }
        } else {
            break;
        }
    }

    size_t start_pos = lexer->pos;
    uint32_t start_line = lexer->line;
    uint32_t start_col = lexer->col;

    Token tok = lexer_next_impl(lexer);
    tok.line = start_line;
    tok.col = start_col;
    tok.offset = (uint32_t)start_pos;
    tok.length = (uint32_t)(lexer->pos - start_pos);

    // Update lexer line/col based on what was consumed in lexer_next_impl
    for (size_t i = start_pos; i < lexer->pos; i++) {
        if (lexer->src[i] == '\n') {
            lexer->line++;
            lexer->col = 1;
        } else {
            lexer->col++;
        }
    }

    return tok;
}

void lexer_token_print(Token tok, char* buf, size_t max_len) {
    switch (tok.kind) {
        case TOK_EOF: snprintf(buf, max_len, "EOF"); break;
        case TOK_ERROR: snprintf(buf, max_len, "ERROR"); break;
        case TOK_IDENT: snprintf(buf, max_len, "IDENT(%s)", (tok.as.ident ? tok.as.ident : "?")); break;
        case TOK_INT: snprintf(buf, max_len, "INT(%llu)", (unsigned long long)tok.as.int_val); break;
        case TOK_FLOAT: snprintf(buf, max_len, "FLOAT(%f)", tok.as.float_val); break;
        case TOK_STRING: snprintf(buf, max_len, "STRING"); break;
        case TOK_FN: snprintf(buf, max_len, "fn"); break;
        case TOK_LET: snprintf(buf, max_len, "let"); break;
        case TOK_MUT: snprintf(buf, max_len, "mut"); break;
        case TOK_RETURN: snprintf(buf, max_len, "return"); break;
        case TOK_AS: snprintf(buf, max_len, "as"); break;
        case TOK_IF: snprintf(buf, max_len, "if"); break;
        case TOK_ELSE: snprintf(buf, max_len, "else"); break;
        case TOK_WHILE: snprintf(buf, max_len, "while"); break;
        case TOK_FOR: snprintf(buf, max_len, "for"); break;
        case TOK_LOOP: snprintf(buf, max_len, "loop"); break;
        case TOK_BREAK: snprintf(buf, max_len, "break"); break;
        case TOK_CONTINUE: snprintf(buf, max_len, "continue"); break;
        case TOK_IN: snprintf(buf, max_len, "in"); break;
        case TOK_STRUCT: snprintf(buf, max_len, "struct"); break;
        case TOK_ENUM: snprintf(buf, max_len, "enum"); break;
        case TOK_MATCH: snprintf(buf, max_len, "match"); break;
        case TOK_NEVER: snprintf(buf, max_len, "never"); break;
        case TOK_BOX: snprintf(buf, max_len, "box/Box"); break;
        case TOK_UNSAFE: snprintf(buf, max_len, "unsafe"); break;
        case TOK_LPAREN: snprintf(buf, max_len, "("); break;
        case TOK_RPAREN: snprintf(buf, max_len, ")"); break;
        case TOK_LBRACE: snprintf(buf, max_len, "{"); break;
        case TOK_RBRACE: snprintf(buf, max_len, "}"); break;
        case TOK_LBRACKET: snprintf(buf, max_len, "["); break;
        case TOK_RBRACKET: snprintf(buf, max_len, "]"); break;
        case TOK_HASH: snprintf(buf, max_len, "#"); break;
        case TOK_SEMICOLON: snprintf(buf, max_len, ";"); break;
        case TOK_COLON: snprintf(buf, max_len, ":"); break;
        case TOK_COMMA: snprintf(buf, max_len, ","); break;
        case TOK_DOT: snprintf(buf, max_len, "."); break;
        case TOK_DOTDOT: snprintf(buf, max_len, ".."); break;
        case TOK_DOTDOTEQ: snprintf(buf, max_len, "..="); break;
        case TOK_ELLIPSIS: snprintf(buf, max_len, "..."); break;
        case TOK_ARROW: snprintf(buf, max_len, "->"); break;
        default: snprintf(buf, max_len, "Token(%d)", tok.kind); break;
    }
}
