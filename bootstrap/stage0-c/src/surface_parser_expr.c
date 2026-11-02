#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <ctype.h>
#include "surface_parser_internal.h"
#include "il_type.h"

// Forward declarations for static expression helpers
static Expression* parse_unary(Parser* parser);
static void reject_assignment_condition(Parser* parser, Expression* cond);
static Expression* parse_cast(Parser* parser);
static Expression* parse_binary(Parser* parser, Expression* left, int precedence);
static Expression* parse_primary(Parser* parser);
static Expression* parse_array_expr(Parser* parser);
static Expression* parse_block_expr(Parser* parser);
static MatchExpr* parse_match_expr(Parser* parser);
IfExpr* parse_if_expr_internal(Parser* parser);
static Expression* parse_tuple_expr_tail(Parser* parser, Expression* first, Token start_tok);

char** parse_type_params(Parser* parser, uint32_t* count, char*** bounds_out) {
    *count = 0;
    if (bounds_out) *bounds_out = NULL;
    if (!parser_match(parser, TOK_LT)) return NULL;
    uint32_t capacity = 4;
    char** params = ARENA_ALLOC_ARRAY(parser->arena, char*, capacity);
    char** bounds = ARENA_ALLOC_ARRAY(parser->arena, char*, capacity);
    if (!params || !bounds) {   return NULL; }
    while (!parser_check(parser, TOK_GT) && !parser_check(parser, TOK_EOF)) {
        parser_consume(parser, TOK_IDENT, "Expect type parameter name");
        if (parser->had_error) goto cleanup;
        
        params[*count] = parser_dup_ident(parser);
        
        if (parser_match(parser, TOK_COLON)) {
            parser_consume(parser, TOK_IDENT, "Expect trait name after ':'");
            if (parser->had_error) goto cleanup;
            bounds[*count] = parser_dup_ident(parser);
        } else {
            bounds[*count] = NULL;
        }
        
        (*count)++;
        
        if (*count >= capacity) {
            uint32_t old_capacity = capacity;
            capacity *= 2;
            params = ARENA_REALLOC_ARRAY(parser->arena, char*, params, old_capacity, capacity);
            bounds = ARENA_REALLOC_ARRAY(parser->arena, char*, bounds, old_capacity, capacity);
        }

        if (!parser_match(parser, TOK_COMMA)) break;
    }
    parser_consume(parser, TOK_GT, "Expect '>' after type parameters");
    if (parser->had_error) goto cleanup;
    
    if (bounds_out) {
        *bounds_out = bounds;
    } else {
        (void)0;
        
    }
    return params;

cleanup:
    // If realloc failed, params/bounds are still valid pointers to old memory
    // and *count reflects correctly how many strings we allocated.
    // However, if realloc failed halfway, we might have already incremented *count
    // but not yet allocated the next slot. Actually *count is only incremented
    // AFTER successful strdup of name and optionally bound.
    for (uint32_t i = 0; i < capacity; i++) {
        (void)0;
        (void)0;
    }
    
    
    *count = 0;
    return NULL;
}

const ILType ** parse_type_args(Parser* parser, uint32_t* count) {
    *count = 0;
    if (!parser_match(parser, TOK_LT)) return NULL;
    uint32_t capacity = 4;
    const ILType ** args = ARENA_ALLOC_ARRAY(parser->arena, const ILType*, capacity);
    if (!args) return NULL;
    while (!parser_check(parser, TOK_GT) && !parser_check(parser, TOK_SHR) && !parser_check(parser, TOK_EOF)) {
        args[(*count)++] = parse_type(parser);
        if ((*count) >= capacity) {
            uint32_t old_capacity = capacity;
            capacity *= 2;
            const ILType ** tmp = ARENA_REALLOC_ARRAY(parser->arena, const ILType*, args, old_capacity, capacity);
            if (!tmp) { return NULL; }
            args = tmp;
        }
        if (!parser_match(parser, TOK_COMMA)) break;
    }
    if (parser_match(parser, TOK_SHR)) {
        Token gt = parser->previous;
        gt.kind = TOK_GT;
        gt.length = 1;
        gt.col++;
        gt.offset++;
        parser_buffer(parser, gt);
    } else {
        parser_consume_gt(parser, "Expect '>' after type arguments");
    }
    return args;
}

static void parse_dotted_name(Parser* parser, char* buf, size_t size, const char* err_msg) {
    strncpy(buf, parser->previous.as.ident, size - 1);
    buf[size - 1] = '\0';
    while (parser_match(parser, TOK_DOT)) {
        size_t len = strlen(buf);
        if (len + 2 >= size) { parser_error(parser, "Name too long"); break; }
        strncat(buf, ".", size - len - 1);
        if (parser_match(parser, TOK_IDENT)) {
            if (strlen(buf) + strlen(parser->previous.as.ident) + 1 >= size) {
                parser_error(parser, "Name too long");
                break;
            }
            strncat(buf, parser->previous.as.ident, size - strlen(buf) - 1);
        } else {
            parser_error(parser, err_msg);
        }
    }
}

const ILType* parse_type(Parser* parser) {
    if (parser_match(parser, TOK_FN)) {
        parser_consume(parser, TOK_LPAREN, "Expect '(' after 'fn'");
        uint32_t count = 1; // Unified ABI: first argument is always env pointer
        uint32_t capacity = 4;
        const ILType ** param_types = ARENA_ALLOC_ARRAY(parser->arena, const ILType*, capacity);
        if (!param_types) abort();
        param_types[0] = il_type_ptr(il_type_unit(), REGION_STATIC, false);
        while (!parser_check(parser, TOK_RPAREN) && !parser_check(parser, TOK_EOF)) {
                if (parser_match(parser, TOK_MUT)) { /* allowed but ignored */ }
            const ILType* pt = parse_type(parser);
            if (pt) {
                if (count >= capacity) {
                    uint32_t old_capacity = capacity;
                    capacity *= 2;
                    const ILType ** new_param_types = ARENA_REALLOC_ARRAY(parser->arena, const ILType*, param_types, old_capacity, capacity);
                    if (!new_param_types) return NULL;
                    param_types = new_param_types;
                }
                param_types[count++] = pt;
            }
            if (!parser_match(parser, TOK_COMMA)) break;
        }
        parser_consume(parser, TOK_RPAREN, "Expect ')' after function parameters");
        const ILType* ret_type = NULL;
        if (parser_match(parser, TOK_ARROW)) {
            ret_type = parse_type(parser);
        } else {
            ret_type = il_type_unit();
        }
        const ILType* t = il_type_fn(ret_type, param_types, count, false);
        (void)0;
        
        
        return t;
    }
    if (parser_match(parser, TOK_LPAREN)) {
        if (parser_match(parser, TOK_RPAREN)) {
            return il_type_unit();
        }
        uint32_t count = 0;
        uint32_t capacity = 4;
        const ILType ** elements = ARENA_ALLOC_ARRAY(parser->arena, const ILType*, capacity);
        if (!elements) return NULL;
        while (!parser_check(parser, TOK_RPAREN) && !parser_check(parser, TOK_EOF)) {
                if (parser_match(parser, TOK_MUT)) { /* allowed but ignored */ }
            elements[count++] = parse_type(parser);
            if (count >= capacity) {
                uint32_t old_capacity = capacity;
                capacity *= 2;
                const ILType ** new_elements = ARENA_REALLOC_ARRAY(parser->arena, const ILType*, elements, old_capacity, capacity);
                if (!new_elements) return NULL;
                elements = new_elements;
            }
            if (!parser_match(parser, TOK_COMMA)) break;
        }
        parser_consume(parser, TOK_RPAREN, "Expect ')' after tuple type");
        const ILType* t = il_type_tuple(elements, count);
        (void)0;
        
        return t;
    }
    if (parser_match(parser, TOK_BOX)) {
        parser_consume(parser, TOK_LT, "Expect '<' after Box");
        const ILType* inner = parse_type(parser);
        parser_consume_gt(parser, "Expect '>' after Box type");
        const ILType* t = il_type_box(inner, REGION_HEAP, true);
        
        return t;
    }
    if (parser_match(parser, TOK_STAR)) {
        bool is_mut = parser_match(parser, TOK_MUT);
        const ILType* inner = parse_type(parser);
        const ILType* t = il_type_ptr(inner, REGION_STATIC, is_mut);
        
        return t;
    }
    if (parser_match(parser, TOK_AMP)) {
        bool is_mut = parser_match(parser, TOK_MUT);
        const ILType* inner = parse_type(parser);
        const ILType* t = il_type_ptr(inner, REGION_LOCAL, is_mut);
        
        return t;
    }
    /* `&&T` lexes as one `&&` token: a reference to a reference. */
    if (parser_match(parser, TOK_AMP_AMP)) {
        bool is_mut = parser_match(parser, TOK_MUT);
        const ILType* inner = il_type_ptr(parse_type(parser), REGION_LOCAL, is_mut);
        return il_type_ptr(inner, REGION_LOCAL, false);
    }
    if (parser_match(parser, TOK_LBRACKET)) {
        bool is_mut = parser_match(parser, TOK_MUT);
        const ILType* inner = parse_type(parser);
        if (parser_match(parser, TOK_SEMICOLON)) {
            parser_consume(parser, TOK_INT, "Expect array size after ';'");
            uint64_t length = parser->previous.as.int_val;
            parser_consume(parser, TOK_RBRACKET, "Expect ']' after array size");
            const ILType* t = il_type_array(inner, length);
            
            return t;
        } else {
            parser_consume(parser, TOK_RBRACKET, "Expect ']' after slice type");
            const ILType* t = il_type_slice(inner, REGION_LOCAL, is_mut);
            
            return t;
        }
    }
    if (parser_match(parser, TOK_NEVER)) {
        return il_type_never();
    }
    if (parser_match(parser, TOK_IDENT)) {
        char name_buf[512];
        parse_dotted_name(parser, name_buf, sizeof(name_buf), "Expect identifier after '.' in type name");

        const ILType* type = NULL;
        if (strcmp(name_buf, "i8") == 0) type = il_type_i8();
        else if (strcmp(name_buf, "i16") == 0) type = il_type_i16();
        else if (strcmp(name_buf, "i32") == 0) type = il_type_i32();
        else if (strcmp(name_buf, "i64") == 0) type = il_type_i64();
        else if (strcmp(name_buf, "u8") == 0) type = il_type_u8();
        else if (strcmp(name_buf, "u16") == 0) type = il_type_u16();
        else if (strcmp(name_buf, "u32") == 0) type = il_type_u32();
        else if (strcmp(name_buf, "u64") == 0) type = il_type_u64();
        else if (strcmp(name_buf, "usize") == 0) type = il_type_usize();
        else if (strcmp(name_buf, "isize") == 0) type = il_type_isize();
        else if (strcmp(name_buf, "f32") == 0) type = il_type_f32();
        else if (strcmp(name_buf, "f64") == 0) type = il_type_f64();
        else if (strcmp(name_buf, "bool") == 0) type = il_type_bool();
        else if (strcmp(name_buf, "char") == 0) type = il_type_char();
        else if (strcmp(name_buf, "unit") == 0) type = il_type_unit();
        else if (strcmp(name_buf, "never") == 0) type = il_type_never();
        else if (strcmp(name_buf, "async_context") == 0) type = il_type_async_context();
        else if (strcmp(name_buf, "fd") == 0) {
            ILFdCap cap = IL_CAP_RW;
            if (parser_match(parser, TOK_LT)) {
                if (parser_match(parser, TOK_IDENT)) {
                    if (strcmp(parser->previous.as.ident, "r") == 0) cap = IL_CAP_READ;
                    else if (strcmp(parser->previous.as.ident, "w") == 0) cap = IL_CAP_WRITE;
                    else if (strcmp(parser->previous.as.ident, "rw") == 0) cap = IL_CAP_RW;
                    else parser_error(parser, "Expect 'r', 'w', or 'rw' for fd capability");
                } else {
                    parser_error(parser, "Expect capability after '<' in fd type");
                }
                parser_consume_gt(parser, "Expect '>' after fd capability");
            }
            type = il_type_fd(cap);
        }
        else if (strcmp(name_buf, "str") == 0) {
            const ILType* u8_ty = il_type_u8();
            type = il_type_slice(u8_ty, REGION_STATIC, false); // Static
            
        }
        else {
            // Check if it might be a generic variable or a struct/enum
            uint32_t type_arg_count = 0;
            const ILType ** type_args = NULL;
            if (parser_check(parser, TOK_LT)) {
                type_args = parse_type_args(parser, &type_arg_count);
            }
            type = il_type_struct_gen(parser_strdup(parser, name_buf), 0, type_args, type_arg_count);
        }
        return type;
    }
    parser_error(parser, "Expect type name or prefix");
    if (parser->current.kind != TOK_EOF) parser_advance(parser);
    return NULL;
}

Expression* parse_literal_expr(Parser* parser) {
    Token tok = parser->current;
    Expression* expr = expr_create(parser);
    if (!expr) return NULL;
    if (parser_match(parser, TOK_INT)) {
        expr->kind = EXPR_INT;
        expr->as.int_val = parser->previous.as.int_val;
        if (parser->previous.suffix) {
            const char* s = parser->previous.suffix;
            if (strcmp(s, "u8") == 0) expr->type = il_type_u8();
            else if (strcmp(s, "u16") == 0) expr->type = il_type_u16();
            else if (strcmp(s, "u32") == 0) expr->type = il_type_u32();
            else if (strcmp(s, "u64") == 0) expr->type = il_type_u64();
            else if (strcmp(s, "i8") == 0) expr->type = il_type_i8();
            else if (strcmp(s, "i16") == 0) expr->type = il_type_i16();
            else if (strcmp(s, "i32") == 0) expr->type = il_type_i32();
            else if (strcmp(s, "i64") == 0) expr->type = il_type_i64();
            else if (strcmp(s, "usize") == 0) expr->type = il_type_usize();
            else if (strcmp(s, "isize") == 0) expr->type = il_type_isize();
            else {
                parser_diag_at(parser, DIAG_ERROR, "Invalid integer suffix: %s", s);
            }
        }
    } else if (parser_match(parser, TOK_FLOAT)) {
        expr->kind = EXPR_FLOAT;
        expr->as.float_val = parser->previous.as.float_val;
        if (parser->previous.suffix) {
            const char* s = parser->previous.suffix;
            if (strcmp(s, "f32") == 0) expr->type = il_type_f32();
            else if (strcmp(s, "f64") == 0) expr->type = il_type_f64();
            else {
                parser_diag_at(parser, DIAG_ERROR, "Invalid float suffix: %s", s);
            }
        }
    } else if (parser_match(parser, TOK_STRING)) {
        expr->kind = EXPR_STRING;
        expr->as.string_val.len = parser->previous.as.str.len;
        expr->as.string_val.val = arena_alloc(parser->arena, expr->as.string_val.len + 1, 1);
        if (expr->as.string_val.val) {
            memcpy(expr->as.string_val.val, parser->previous.as.str.val, expr->as.string_val.len);
            expr->as.string_val.val[expr->as.string_val.len] = '\0';
        }
    } else if (parser_match(parser, TOK_TRUE)) {
        expr->kind = EXPR_BOOL;
        expr->as.bool_val = true;
    } else if (parser_match(parser, TOK_FALSE)) {
        expr->kind = EXPR_BOOL;
        expr->as.bool_val = false;
    } else {
        
        return NULL;
    }
    expr->line = tok.line;
    expr->col = tok.col;
    expr->offset = tok.offset;
    expr->length = tok.length;
    return expr;
}

static void parse_struct_literal_body(Parser* parser, Expression* expr) {
    uint32_t capacity = 4;
    expr->as.struct_expr.field_names = ARENA_ALLOC_ARRAY(parser->arena, char*, capacity);
    expr->as.struct_expr.field_values = ARENA_ALLOC_ARRAY(parser->arena, Expression*, capacity);
    while (!parser_check(parser, TOK_RBRACE) && !parser_check(parser, TOK_EOF)) {
        if (!parser_match(parser, TOK_IDENT)) {
            parser_error(parser, "Expect field name");
            break;
        }
        char* f_name = parser_dup_ident(parser);
        parser_consume(parser, TOK_COLON, "Expect ':' after field name");
        if (parser->had_error) {  break; }
        Expression* f_val = parse_expression(parser);
        if (parser->had_error) {   break; }
        expr->as.struct_expr.field_names[expr->as.struct_expr.field_count] = f_name;
        expr->as.struct_expr.field_values[expr->as.struct_expr.field_count] = f_val;
        expr->as.struct_expr.field_count++;
        if (expr->as.struct_expr.field_count >= capacity) {
            uint32_t old_capacity = capacity;
            capacity *= 2;
            expr->as.struct_expr.field_names = ARENA_REALLOC_ARRAY(parser->arena, char*, expr->as.struct_expr.field_names, old_capacity, capacity);
            expr->as.struct_expr.field_values = ARENA_REALLOC_ARRAY(parser->arena, Expression*, expr->as.struct_expr.field_values, old_capacity, capacity);
        }
        if (!parser_match(parser, TOK_COMMA)) break;
    }
    parser_consume(parser, TOK_RBRACE, "Expect '}' after struct literal");
}

Expression* parse_identifier_or_struct_expr(Parser* parser) {
    if (!parser_check(parser, TOK_IDENT)) return NULL;
    Token tok = parser->current;
    parser_advance(parser);
    char* name = parser_dup_ident(parser);
    if (!name) return NULL;

    Expression* expr = expr_create(parser);
    if (!expr) {  return NULL; }
    
    if (parser->allow_struct_literal && parser_match(parser, TOK_LBRACE)) {
        expr->kind = EXPR_STRUCT;
        expr->as.struct_expr.name = name;
        parse_struct_literal_body(parser, expr);
    } else {
        expr->kind = EXPR_VAR;
        expr->as.var.name = name;
    }
    
    expr->line = tok.line;
    expr->col = tok.col;
    expr->offset = tok.offset;
    expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - tok.offset);
    return expr;
}

Expression* parse_annotation_expr(Parser* parser) {
    if (!parser_check(parser, TOK_ANNOT)) return NULL;
    Token tok = parser->current;
    parser_advance(parser);
    const char* name = parser->previous.as.ident;
    Expression* expr = NULL;
    if (strcmp(name, "@ptr_cast") == 0 || strcmp(name, "@int_cast") == 0 || strcmp(name, "@ptr_from_int") == 0) {
        parser_consume(parser, TOK_LT, "Expect '<' after cast");
        const ILType* target = parse_type(parser);
        parser_consume(parser, TOK_GT, "Expect '>' after cast type");
        parser_consume(parser, TOK_LPAREN, "Expect '(' after cast");
        Expression* inner = parse_expression(parser);
        parser_consume(parser, TOK_RPAREN, "Expect ')' after cast expression");
        expr = expr_create(parser);
        if (expr) {
            expr->kind = EXPR_CAST;
            expr->as.cast_expr.expr = inner;
            expr->as.cast_expr.target_type = target;
            expr->line = tok.line;
            expr->col = tok.col;
            expr->offset = tok.offset;
            expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - tok.offset);
        }
    } else if (strcmp(name, "@drop") == 0 || strcmp(name, "@alloca") == 0 || strcmp(name, "@syscall") == 0 || strcmp(name, "@slice") == 0 || strcmp(name, "@saturating_add") == 0 || strcmp(name, "@region_cast") == 0 || strcmp(name, "@fd_open") == 0 || strcmp(name, "@fd_close") == 0 || strcmp(name, "@fd_read") == 0 || strcmp(name, "@fd_write") == 0 || strcmp(name, "@fd_from_raw") == 0 ||
               strcmp(name, "@async_setup") == 0 || strcmp(name, "@async_enter") == 0 || strcmp(name, "@async_close") == 0) {
        char* name_copy = parser_strdup(parser, name);
        const ILType ** type_args = NULL;
        uint32_t type_arg_count = 0;
        if (parser_check(parser, TOK_LT)) {
            type_args = parse_type_args(parser, &type_arg_count);
        }
        parser_consume(parser, TOK_LPAREN, "Expect '(' after annotation");
        Expression* args[8];
        uint32_t arg_count = 0;
        while (!parser_check(parser, TOK_RPAREN) && !parser_check(parser, TOK_EOF) && arg_count < 8) {
            args[arg_count++] = parse_expression(parser);
            if (!parser_match(parser, TOK_COMMA)) break;
        }
        parser_consume(parser, TOK_RPAREN, "Expect ')' after annotation arguments");
        expr = expr_create(parser);
        if (expr) {
            expr->kind = EXPR_CALL;
            expr->as.call.name = name_copy;
            expr->as.call.type_args = type_args;
            expr->as.call.type_arg_count = type_arg_count;
            expr->as.call.args = ARENA_ALLOC_ARRAY(parser->arena, Expression*, arg_count);
            if (expr->as.call.args) {
                memcpy(expr->as.call.args, args, arg_count * sizeof(Expression*));
                expr->as.call.arg_count = arg_count;
            }
            expr->line = tok.line;
            expr->col = tok.col;
            expr->offset = tok.offset;
            expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - tok.offset);
        } else {
            
        }
    }
    return expr;
}

Expression* parse_array_expr(Parser* parser) {
    if (!parser_match(parser, TOK_LBRACKET)) return NULL;
    Token start_tok = parser->previous;
    
    Expression* expr = expr_create(parser);
    if (!expr) return NULL;
    expr->kind = EXPR_ARRAY;
    
    uint32_t capacity = 4;
    expr->as.array_expr.elements = ARENA_ALLOC_ARRAY(parser->arena, Expression*, capacity);
    expr->as.array_expr.count = 0;
    expr->as.array_expr.fill_count = NULL;
    
    if (!parser_check(parser, TOK_RBRACKET)) {
        Expression* first = parse_expression(parser);
        if (first) {
            expr->as.array_expr.elements[expr->as.array_expr.count++] = first;
            
            if (parser_match(parser, TOK_SEMICOLON)) {
                // [expr; count] syntax
                expr->as.array_expr.fill_count = parse_expression(parser);
                if (!expr->as.array_expr.fill_count) {
                    parser_error(parser, "Expect count expression after ';'");
                }
            } else {
                // [expr, expr, ...] syntax
                if (parser_match(parser, TOK_COMMA)) {
                    while (!parser_check(parser, TOK_RBRACKET) && !parser_check(parser, TOK_EOF)) {
                        Expression* elem = parse_expression(parser);
                        if (elem) {
                            if (expr->as.array_expr.count >= capacity) {
                                uint32_t old_capacity = capacity;
                                capacity *= 2;
                                expr->as.array_expr.elements = ARENA_REALLOC_ARRAY(parser->arena, Expression*, expr->as.array_expr.elements, old_capacity, capacity);
                            }
                            expr->as.array_expr.elements[expr->as.array_expr.count++] = elem;
                        }
                        if (!parser_match(parser, TOK_COMMA)) break;
                    }
                }
            }
        }
    }
    
    parser_consume(parser, TOK_RBRACKET, "Expect ']' after array elements");
    
    expr->line = start_tok.line;
    expr->col = start_tok.col;
    expr->offset = start_tok.offset;
    expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
    
    return expr;
}

Expression* parse_closure_expr(Parser* parser) {
    if (!parser_match(parser, TOK_OR)) return NULL;
    Token start_tok = parser->previous;

    Expression* expr = expr_create(parser);
    if (!expr) return NULL;
    expr->kind = EXPR_CLOSURE;

    while (!parser_check(parser, TOK_OR) && !parser_check(parser, TOK_EOF)) {
        expr->as.closure.params = ARENA_REALLOC_ARRAY(parser->arena, Param, expr->as.closure.params, expr->as.closure.param_count, expr->as.closure.param_count + 1);
        Param* p = &expr->as.closure.params[expr->as.closure.param_count++];
        p->is_mutable = parser_match(parser, TOK_MUT);
        parser_consume(parser, TOK_IDENT, "Expect parameter name");
        if (parser->previous.kind == TOK_IDENT) {
            p->name = parser_dup_ident(parser);
        } else {
            p->name = parser_strdup(parser, "?");
        }
        if (parser_match(parser, TOK_COLON)) {
            p->type = parse_type(parser);
        } else {
            p->type = NULL;
        }
        if (!parser_match(parser, TOK_COMMA)) break;
    }
    parser_consume(parser, TOK_OR, "Expect '|' after closure parameters");

    if (parser_match(parser, TOK_ARROW)) {
        expr->as.closure.return_type = parse_type(parser);
    }

    if (parser_check(parser, TOK_LBRACE)) {
        expr->as.closure.body = parse_block(parser);
    } else {
        Expression* body_expr = parse_expression(parser);
        expr->as.closure.body = ARENA_ALLOC(parser->arena, BlockExpr);
        if (expr->as.closure.body) {
            expr->as.closure.body->result = body_expr;
        }
    }

    expr->line = start_tok.line;
    expr->col = start_tok.col;
    expr->offset = start_tok.offset;
    expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
    return expr;
}

Expression* parse_block_expr(Parser* parser) {
    bool is_unsafe = false;
    Token tok = parser->current;
    if (parser_match(parser, TOK_UNSAFE)) {
        is_unsafe = true;
    }
    if (!parser_check(parser, TOK_LBRACE)) {
        if (is_unsafe) {
            parser_error(parser, "Expect '{' after 'unsafe'");
        }
        return NULL;
    }
    BlockExpr* block = parse_block(parser);
    if (!block) return NULL;
    Expression* expr = expr_create(parser);
    if (!expr) {  return NULL; }
    expr->kind = EXPR_BLOCK;
    expr->as.block = block;
    expr->line = tok.line;
    expr->col = tok.col;
    expr->offset = tok.offset;
    expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - tok.offset);
    return expr;
}

static bool is_likely_turbofish(Parser* parser) {
    if (parser->current.kind != TOK_LT) return false;
    
    // Simple lookahead in the source string to see if this < is followed by a matching >
    // and then a '(' or '{', which strongly indicates a turbofish.
    const char* p = parser->lexer.src + parser->lexer.pos;
    int depth = 1;
    while (*p && depth > 0) {
        if (*p == '<') {
            if (*(p+1) == '<' || *(p+1) == '=') {
                p++;
            } else {
                depth++;
            }
        } else if (*p == '>') {
            if (*(p+1) == '>' || *(p+1) == '=') {
                p++;
            } else {
                depth--;
            }
        } else if (*p == '=' && *(p+1) == '>') {
            p++;
        } else if (*p == '-' && *(p+1) == '>') {
            p++;
        } else if (*p == ';') {
            return false; 
        }
        p++;
    }
    
    if (depth == 0) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (*p == '(' || *p == '{') return true;
    }
    return false;
}

Expression* apply_postfix_ops(Parser* parser, Expression* expr, Token start_tok) {
    while (true) {
        // Block-like expressions (if, match, block) cannot be called or indexed
        // without explicit outer parentheses, to avoid parsing `if ... { }(args)`
        // as a call on the if result instead of two separate statements.
        bool is_block_expr = (expr->kind == EXPR_IF ||
                              expr->kind == EXPR_WHILE ||
                              expr->kind == EXPR_MATCH ||
                              expr->kind == EXPR_BLOCK);
        if (is_block_expr && (parser_check(parser, TOK_LPAREN) ||
                              parser_check(parser, TOK_LBRACKET) ||
                              parser_check(parser, TOK_LBRACE))) {
            break;
        }
        if (parser_match(parser, TOK_LPAREN)) {
            Expression* call = expr_create(parser);
            if (!call) return expr;
            call->kind = EXPR_CALL;
            if (expr->kind == EXPR_VAR) {
                call->as.call.name = expr->as.var.name;
                call->as.call.type_args = expr->as.var.type_args;
                call->as.call.type_arg_count = expr->as.var.type_arg_count;
                expr->as.var.name = NULL;
                expr->as.var.type_args = NULL;
                expr->as.var.type_arg_count = 0;
                
            } else if (expr->kind == EXPR_MEMBER) {
                call->as.call.receiver = expr->as.member.object;
                call->as.call.name = expr->as.member.field_name;
                call->as.call.type_args = expr->as.member.type_args;
                call->as.call.type_arg_count = expr->as.member.type_arg_count;
                expr->as.member.object = NULL;
                expr->as.member.field_name = NULL;
                expr->as.member.type_args = NULL;
                expr->as.member.type_arg_count = 0;
                
            } else {
                call->as.call.callee = expr;
            }
            uint32_t capacity = 4;
            call->as.call.args = ARENA_ALLOC_ARRAY(parser->arena, Expression*, capacity);
            while (!parser_check(parser, TOK_RPAREN) && !parser_check(parser, TOK_EOF)) {
                if (parser_match(parser, TOK_MUT)) { /* allowed but ignored */ }
                Expression* arg = parse_expression(parser);
                if (arg) {
                    if (call->as.call.arg_count >= capacity) {
                        uint32_t old_capacity = capacity;
                        capacity *= 2;
                        call->as.call.args = ARENA_REALLOC_ARRAY(parser->arena, Expression*, call->as.call.args, old_capacity, capacity);
                    }

                    call->as.call.args[call->as.call.arg_count++] = arg;
                }
                if (!parser_match(parser, TOK_COMMA)) break;
            }
            parser_consume(parser, TOK_RPAREN, "Expect ')' after arguments");
            call->line = start_tok.line;
            call->col = start_tok.col;
            call->offset = start_tok.offset;
            call->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
            expr = call;
        } else if (parser_match(parser, TOK_COLONCOLON) || is_likely_turbofish(parser)) {
            if (parser->previous.kind == TOK_COLONCOLON) {
                parser_consume(parser, TOK_LT, "Expect '<' after '::'");
            } else {
                parser_advance(parser); // Consume TOK_LT
            }
            
            const ILType ** type_args = NULL;
            uint32_t type_arg_count = 0;
            uint32_t capacity = 4;
            type_args = ARENA_ALLOC_ARRAY(parser->arena, const ILType*, capacity);
            if (!type_args) abort();
            
            while (!parser_check(parser, TOK_GT) && !parser_check(parser, TOK_EOF)) {
                const ILType* t = parse_type(parser);
                if (t) {
                    if (type_arg_count >= capacity) {
                        uint32_t old_capacity = capacity;
                        capacity *= 2;
                        const ILType ** new_type_args = ARENA_REALLOC_ARRAY(parser->arena, const ILType*, type_args, old_capacity, capacity);
                        if (!new_type_args) return expr;
                        type_args = new_type_args;
                    }
                    type_args[type_arg_count++] = t;
                }
                if (!parser_match(parser, TOK_COMMA)) break;
            }
            parser_consume_gt(parser, "Expect '>' after type arguments");
            
            if (expr->kind == EXPR_VAR) {
                if (expr->as.var.type_args) {
                    for (uint32_t i = 0; i < expr->as.var.type_arg_count; i++) {
                        
                    }
                    
                }
                expr->as.var.type_args = type_args;
                expr->as.var.type_arg_count = type_arg_count;
                expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
            } else if (expr->kind == EXPR_MEMBER) {
                if (expr->as.member.type_args) {
                    for (uint32_t i = 0; i < expr->as.member.type_arg_count; i++) {
                        
                    }
                    
                }
                expr->as.member.type_args = type_args;
                expr->as.member.type_arg_count = type_arg_count;
                expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
            } else {
                parser_error(parser, "Turbofish '::<' can only be applied to identifiers");
                (void)0;
                
            }
        } else if (parser_match(parser, TOK_DOT)) {
            char* member_name = NULL;
            if (parser_match(parser, TOK_IDENT)) {
                member_name = parser_dup_ident(parser);
            } else if (parser_match(parser, TOK_INT)) {
                char buf[32];
                snprintf(buf, sizeof(buf), "%llu", (unsigned long long)parser->previous.as.int_val);
                member_name = parser_strdup(parser, buf);
            } else {
                parser_error(parser, "Expect member name or tuple index after '.'");
                return expr;
            }
            Expression* mem = expr_create(parser);
            if (!mem) {  return expr; }
            mem->kind = EXPR_MEMBER;
            mem->as.member.object = expr;
            mem->as.member.field_name = member_name;
            mem->line = start_tok.line;
            mem->col = start_tok.col;
            mem->offset = start_tok.offset;
            mem->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
            expr = mem;
        } else if (parser_match(parser, TOK_QUESTION)) {
            Expression* try_expr = expr_create(parser);
            if (!try_expr) return expr;
            try_expr->kind = EXPR_TRY;
            try_expr->as.try_expr = expr;
            try_expr->line = start_tok.line;
            try_expr->col = start_tok.col;
            try_expr->offset = start_tok.offset;
            try_expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
            expr = try_expr;
        } else if (parser_match(parser, TOK_LBRACKET)) {
            Expression* index_val = parse_expression(parser);
            parser_consume(parser, TOK_RBRACKET, "Expect ']' after index");
            Expression* idx_expr = expr_create(parser);
            if (!idx_expr) {  return expr; }
            idx_expr->kind = EXPR_INDEX;
            idx_expr->as.index_expr.left = expr;
            idx_expr->as.index_expr.index = index_val;
            idx_expr->line = start_tok.line;
            idx_expr->col = start_tok.col;
            idx_expr->offset = start_tok.offset;
            idx_expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
            expr = idx_expr;
        } else if (parser->allow_struct_literal && parser_match(parser, TOK_LBRACE)) {
            if (expr->kind == EXPR_VAR) {
                char* name = expr->as.var.name;
                const ILType ** type_args = expr->as.var.type_args;
                uint32_t type_arg_count = expr->as.var.type_arg_count;
                expr->as.var.name = NULL;
                expr->as.var.type_args = NULL;
                expr->as.var.type_arg_count = 0;
                
                expr->kind = EXPR_STRUCT;
                expr->as.struct_expr.name = name;
                expr->as.struct_expr.type_args = type_args;
                expr->as.struct_expr.type_arg_count = type_arg_count;
                parse_struct_literal_body(parser, expr);
            } else if (expr->kind == EXPR_MEMBER) {
                char* name = expr->as.member.field_name;
                const ILType ** type_args = expr->as.member.type_args;
                uint32_t type_arg_count = expr->as.member.type_arg_count;
                // The module prefix (receiver) is dropped; only the member name becomes the struct name.
                expr->as.member.field_name = NULL;
                expr->as.member.type_args = NULL;
                expr->as.member.type_arg_count = 0;
                
                
                expr->as.member.object = NULL;
                
                expr->kind = EXPR_STRUCT;
                expr->as.struct_expr.name = name;
                expr->as.struct_expr.type_args = type_args;
                expr->as.struct_expr.type_arg_count = type_arg_count;
                parse_struct_literal_body(parser, expr);
            } else {
                parser_error(parser, "Expect struct name before '{'");
                break;
            }
            expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
        } else {
            break;
        }
    }
    return expr;
}

Expression* parse_tuple_expr_tail(Parser* parser, Expression* first, Token start_tok) {
    Expression* expr = expr_create(parser);
    if (!expr) return first;
    expr->kind = EXPR_TUPLE;
    uint32_t capacity = 4;
    expr->as.tuple_expr.elements = ARENA_ALLOC_ARRAY(parser->arena, Expression*, capacity);
    if (expr->as.tuple_expr.elements) {
        expr->as.tuple_expr.elements[expr->as.tuple_expr.count++] = first;
    }
    
    while (!parser_check(parser, TOK_RPAREN) && !parser_check(parser, TOK_EOF)) {
                if (parser_match(parser, TOK_MUT)) { /* allowed but ignored */ }
        if (expr->as.tuple_expr.count >= capacity) {
            uint32_t old_capacity = capacity;
            capacity *= 2;
            expr->as.tuple_expr.elements = ARENA_REALLOC_ARRAY(parser->arena, Expression*, expr->as.tuple_expr.elements, old_capacity, capacity);
        }

        Expression* element = parse_expression(parser);
        if (element) {
            expr->as.tuple_expr.elements[expr->as.tuple_expr.count++] = element;
        }
        if (!parser_match(parser, TOK_COMMA)) break;
    }
    parser_consume(parser, TOK_RPAREN, "Expect ')' after tuple");
    expr->line = start_tok.line;
    expr->col = start_tok.col;
    expr->offset = start_tok.offset;
    expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
    return expr;
}

Expression* parse_primary(Parser* parser) {
    Token start_tok = parser->current;
    Expression* expr = parse_literal_expr(parser);
    if (!expr) expr = parse_identifier_or_struct_expr(parser);
    if (!expr && parser_match(parser, TOK_LPAREN)) {
        if (parser_match(parser, TOK_RPAREN)) {
            expr = expr_create(parser);
            if (expr) {
                expr->kind = EXPR_TUPLE;
                expr->as.tuple_expr.count = 0;
            }
        } else {
            expr = parse_expression(parser);
            if (parser_match(parser, TOK_COMMA)) {
                expr = parse_tuple_expr_tail(parser, expr, start_tok);
            } else {
                parser_consume(parser, TOK_RPAREN, "Expect ')' after expression");
            }
        }
        if (expr) {
            expr->line = start_tok.line;
            expr->col = start_tok.col;
            expr->offset = start_tok.offset;
            expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
        }
    }
    if (!expr && (parser_match(parser, TOK_SIZEOF) || parser_match(parser, TOK_ALIGNOF))) {
        Token op_tok = parser->previous;
        parser_consume(parser, TOK_LPAREN, "Expect '(' after sizeof/alignof");
        const ILType* target = parse_type(parser);
        parser_consume(parser, TOK_RPAREN, "Expect ')' after type");
        expr = expr_create(parser);
        if (expr) {
            expr->kind = (op_tok.kind == TOK_SIZEOF) ? EXPR_SIZEOF : EXPR_ALIGNOF;
            expr->as.type_expr = target;
            expr->line = start_tok.line;
            expr->col = start_tok.col;
            expr->offset = start_tok.offset;
            expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
        } else {
            
        }
    }
    if (!expr && parser_match(parser, TOK_IF)) {
        expr = expr_create(parser);
        if (expr) {
            expr->kind = EXPR_IF;
            expr->as.if_expr = parse_if_expr_internal(parser);
            expr->line = start_tok.line;
            expr->col = start_tok.col;
            expr->offset = start_tok.offset;
            expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
        }
    }
    if (!expr && parser_match(parser, TOK_WHILE)) {
        expr = expr_create(parser);
        if (expr) {
            expr->kind = EXPR_WHILE;
            bool old_allow = parser->allow_struct_literal;
            parser->allow_struct_literal = false;
            expr->as.while_expr.condition = parse_expression(parser);
            parser->allow_struct_literal = old_allow;
            reject_assignment_condition(parser, expr->as.while_expr.condition);
            expr->as.while_expr.body = parse_block(parser);
            expr->line = start_tok.line;
            expr->col = start_tok.col;
            expr->offset = start_tok.offset;
            expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
        }
    }
    if (!expr && parser_match(parser, TOK_LOOP)) {
        expr = expr_create(parser);
        if (expr) {
            expr->kind = EXPR_WHILE;
            // Condition is constant true
            expr->as.while_expr.condition = expr_create(parser);
            if (expr->as.while_expr.condition) {
                expr->as.while_expr.condition->kind = EXPR_BOOL;
                expr->as.while_expr.condition->as.bool_val = true;
            }
            expr->as.while_expr.body = parse_block(parser);
            expr->line = start_tok.line;
            expr->col = start_tok.col;
            expr->offset = start_tok.offset;
            expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
        }
    }
    if (!expr && parser_match(parser, TOK_MATCH)) {
        expr = expr_create(parser);
        if (expr) {
            expr->kind = EXPR_MATCH;
            MatchExpr* m = parse_match_expr(parser);
            if (m) { expr->as.match_expr = *m;  }
            expr->line = start_tok.line;
            expr->col = start_tok.col;
            expr->offset = start_tok.offset;
            expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
        }
    }
    if (!expr) expr = parse_annotation_expr(parser);
    if (!expr) expr = parse_closure_expr(parser);
    if (!expr) expr = parse_block_expr(parser);
    if (!expr) expr = parse_array_expr(parser);
    if (expr) expr = apply_postfix_ops(parser, expr, start_tok);
    if (!expr) parser_error(parser, "Expect expression");
    return expr;
}

const struct { TokenKind tok; int prec; const char* op; } binary_ops[] = {
    { TOK_STAR,      20, "*"  },
    { TOK_SLASH,     20, "/"  },
    { TOK_PERCENT,   20, "%"  },
    { TOK_STAR_PERCENT, 20, "*%" },
    { TOK_PLUS,      11, "+"  },
    { TOK_MINUS,     11, "-"  },
    { TOK_PLUS_PERCENT, 11, "+%" },
    { TOK_MINUS_PERCENT, 11, "-%" },
    { TOK_SHL,       10, "<<" },
    { TOK_SHR,       10, ">>" },
    /* Rust-style ordering: bitwise & ^ | bind tighter than comparisons,
       and all six comparisons share one (non-associative) level. */
    { TOK_AMP,        9, "&"  },
    { TOK_XOR,        8, "^"  },
    { TOK_OR,         7, "|"  },
    { TOK_LT,         6, "<"  },
    { TOK_LE,         6, "<=" },
    { TOK_GT,         6, ">"  },
    { TOK_GE,         6, ">=" },
    { TOK_EQ,         6, "==" },
    { TOK_NE,         6, "!=" },
    { TOK_AMP_AMP,    4, "&&" },
    { TOK_PIPE_PIPE,  3, "||" },
    { TOK_ASSIGN,         2, "="  },
    { TOK_PLUS_ASSIGN,    2, "+=" },
    { TOK_MINUS_ASSIGN,   2, "-=" },
    { TOK_STAR_ASSIGN,    2, "*=" },
    { TOK_SLASH_ASSIGN,   2, "/=" },
    { TOK_PERCENT_ASSIGN, 2, "%=" },
    { TOK_PLUS_PERCENT_ASSIGN, 2, "+%=" },
    { TOK_MINUS_PERCENT_ASSIGN, 2, "-%=" },
    { TOK_STAR_PERCENT_ASSIGN, 2, "*%=" },
    { TOK_AMP_ASSIGN,     2, "&=" },
    { TOK_PIPE_ASSIGN,    2, "|=" },
    { TOK_XOR_ASSIGN,     2, "^=" },
    { TOK_SHL_ASSIGN,     2, "<<="},
    { TOK_SHR_ASSIGN,     2, ">>="},
};

// True for "=" and the compound assignments ("+=", "<<=", ...); false for
// the comparisons that also end in '=' ("==", "!=", "<=", ">=").
static bool op_is_assignment(const char* op) {
    if (!op) return false;
    size_t n = strlen(op);
    if (n == 0 || op[n - 1] != '=') return false;
    return strcmp(op, "==") != 0 && strcmp(op, "!=") != 0 &&
           strcmp(op, "<=") != 0 && strcmp(op, ">=") != 0;
}

static void reject_assignment_condition(Parser* parser, Expression* cond) {
    if (cond && cond->kind == EXPR_BINARY && op_is_assignment(cond->as.binary.op)) {
        parser_error(parser, "assignment in a condition yields no value; did you mean `==`?");
    }
}

static bool tok_is_comparison(TokenKind t) {
    return t == TOK_LT || t == TOK_LE || t == TOK_GT || t == TOK_GE ||
           t == TOK_EQ || t == TOK_NE;
}

static bool parser_at_comparison(Parser* parser) {
    return parser_check(parser, TOK_LT) || parser_check(parser, TOK_LE) ||
           parser_check(parser, TOK_GT) || parser_check(parser, TOK_GE) ||
           parser_check(parser, TOK_EQ) || parser_check(parser, TOK_NE);
}

Expression* parse_binary(Parser* parser, Expression* left, int precedence) {
    while (true) {
        int current_precedence = 0;
        const char* op = NULL;
        TokenKind op_tok = TOK_EOF;
        for (size_t i = 0; i < sizeof(binary_ops) / sizeof(binary_ops[0]); i++) {
            if (parser_check(parser, binary_ops[i].tok)) {
                current_precedence = binary_ops[i].prec;
                op = binary_ops[i].op;
                op_tok = binary_ops[i].tok;
                break;
            }
        }

        if (current_precedence <= precedence) break;
        parser_advance(parser);

        Expression* right = parse_cast(parser);
        if (right) {
            right = parse_binary(parser, right, current_precedence);
            if (tok_is_comparison(op_tok) && parser_at_comparison(parser)) {
                parser_error(parser, "comparison operators cannot be chained; use `a < b && b < c`");
            }
            Expression* new_expr = expr_create(parser);
            if (!new_expr) {  return left; }
            new_expr->kind = EXPR_BINARY;
            new_expr->as.binary.op = parser_strdup(parser, op);
            if (!new_expr->as.binary.op) {   return left; }
            new_expr->as.binary.left = left;
            new_expr->as.binary.right = right;
            new_expr->line = left->line;
            new_expr->col = left->col;
            new_expr->offset = left->offset;
            new_expr->length = (uint32_t)(right->offset + right->length - left->offset);
            left = new_expr;
        }
    }
    return left;
}

Expression* parse_unary(Parser* parser) {
    Token start_tok = parser->current;
    if (parser_match(parser, TOK_RETURN)) {
        Expression* inner = NULL;
        // Check if there is an expression after return.
        // Return-as-expression usually appears in match arms or as result expressions.
        if (!parser_check(parser, TOK_SEMICOLON) && !parser_check(parser, TOK_RBRACE) && !parser_check(parser, TOK_COMMA) && !parser_check(parser, TOK_RPAREN)) {
            inner = parse_expression(parser);
        }
        Expression* expr = expr_create(parser);
        if (expr) {
            expr->kind = EXPR_RETURN;
            expr->as.ret_expr = inner;
            expr->line = start_tok.line;
            expr->col = start_tok.col;
            expr->offset = start_tok.offset;
            expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
        }
        return expr;
    }
    /* `&&x` lexes as one `&&` token: a reference to a reference. */
    if (parser_match(parser, TOK_AMP_AMP)) {
        Token amp_tok = parser->previous;
        bool is_mut = parser_match(parser, TOK_MUT);
        Expression* operand = parse_unary(parser);
        Expression* inner = expr_create(parser);
        Expression* outer = expr_create(parser);
        if (inner && outer) {
            inner->kind = EXPR_UNARY;
            inner->as.unary.op = parser_strdup(parser, "&");
            inner->as.unary.expr = operand;
            inner->as.unary.is_mut = is_mut;
            inner->line = amp_tok.line;
            inner->col = amp_tok.col + 1;
            inner->offset = amp_tok.offset + 1;
            inner->length = operand ? (uint32_t)(operand->offset + operand->length - inner->offset) : 1;
            outer->kind = EXPR_UNARY;
            outer->as.unary.op = parser_strdup(parser, "&");
            outer->as.unary.expr = inner;
            outer->as.unary.is_mut = false;
            outer->line = amp_tok.line;
            outer->col = amp_tok.col;
            outer->offset = amp_tok.offset;
            outer->length = inner->length + 1;
        }
        return outer;
    }
    if (parser_match(parser, TOK_MINUS) || parser_match(parser, TOK_STAR) || parser_match(parser, TOK_AMP) || parser_match(parser, TOK_BANG)) {
        Token op_tok = parser->previous;
        const char* op_str = "";
        if (op_tok.kind == TOK_MINUS) op_str = "-";
        else if (op_tok.kind == TOK_STAR) op_str = "*";
        else if (op_tok.kind == TOK_AMP) op_str = "&";
        else if (op_tok.kind == TOK_BANG) op_str = "!";
        
        char* op = parser_strdup(parser, op_str);
        bool is_mut = false;
        if (op_tok.kind == TOK_AMP || op_tok.kind == TOK_STAR) {
            is_mut = parser_match(parser, TOK_MUT);
        }
        Expression* operand = parse_unary(parser);
        Expression* expr = expr_create(parser);
        if (expr) {
            expr->kind = EXPR_UNARY;
            expr->as.unary.op = op;
            expr->as.unary.expr = operand;
            expr->as.unary.is_mut = is_mut;
            expr->line = start_tok.line;
            expr->col = start_tok.col;
            expr->offset = start_tok.offset;
            if (operand) {
                expr->length = (uint32_t)(operand->offset + operand->length - start_tok.offset);
            } else {
                expr->length = start_tok.length;
            }
        } else {
            
            
        }
        return expr;
    }
    if (parser_match(parser, TOK_BOX)) {
         Expression* allocator = NULL;
         if (parser_match(parser, TOK_LPAREN)) {
             allocator = parse_expression(parser);
             parser_consume(parser, TOK_RPAREN, "Expect ')' after allocator");
         }
         Expression* inner = parse_unary(parser);
         Expression* expr = expr_create(parser);
         if (expr) {
             expr->kind = EXPR_BOX;
             expr->as.box_expr.inner = inner;
             expr->as.box_expr.allocator = allocator;
             expr->line = start_tok.line;
             expr->col = start_tok.col;
             expr->offset = start_tok.offset;
             expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
         } else {
             
             
         }
         return expr;
    }
    return parse_primary(parser);
}

Expression* parse_cast(Parser* parser) {
    Token start_tok = parser->current;
    Expression* expr = parse_unary(parser);
    if (!expr) return NULL;

    while (parser_match(parser, TOK_AS)) {
        const ILType* target_type = parse_type(parser);
        if (!target_type) return expr;
        Expression* cast_expr = expr_create(parser);
        if (!cast_expr) {  return expr; }
        cast_expr->kind = EXPR_CAST;
        cast_expr->as.cast_expr.expr = expr;
        cast_expr->as.cast_expr.target_type = target_type;
        cast_expr->line = start_tok.line;
        cast_expr->col = start_tok.col;
        cast_expr->offset = start_tok.offset;
        cast_expr->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
        expr = cast_expr;
    }
    return expr;
}

Expression* parse_expression(Parser* parser) {
    Expression* left = parse_cast(parser);
    if (!left) return NULL;
    return parse_binary(parser, left, 0);
}

// A block-like expression (`if`, `while`, `loop`, `match`, a bare `{ ... }`) in STATEMENT position
// ends at its closing brace and does not continue into a binary operator. Without this rule the
// next statement is swallowed whenever it starts with a token that is also a binary operator
// (`*`, `&`, `-`): `if c { return; } *p_len = 0 as usize;` parsed as a multiply of two unit
// values. Rust's rule, for the same ambiguity.
Expression* parse_expression_no_binary(Parser* parser) {
    return parse_cast(parser);
}

BlockExpr* parse_block(Parser* parser);

static Pattern* parse_pattern(Parser* parser) {
    Pattern* p = ARENA_ALLOC(parser->arena, Pattern);
    if (!p) return NULL;

    if (parser_match(parser, TOK_INT)) {
        uint64_t start = parser->previous.as.int_val;
        if (parser_match(parser, TOK_DOTDOT) || parser_match(parser, TOK_DOTDOTEQ)) {
            bool inclusive = (parser->previous.kind == TOK_DOTDOTEQ);
            parser_consume(parser, TOK_INT, "Expect end value for range pattern");
            p->kind = PATTERN_RANGE;
            p->as.range.start = start;
            p->as.range.end = parser->previous.as.int_val;
            p->as.range.is_inclusive = inclusive;
        } else {
            p->kind = PATTERN_INT;
            p->as.int_val = start;
        }
    } else if (parser_match(parser, TOK_TRUE)) {
        p->kind = PATTERN_BOOL;
        p->as.bool_val = true;
    } else if (parser_match(parser, TOK_FALSE)) {
        p->kind = PATTERN_BOOL;
        p->as.bool_val = false;
    } else if (parser_match(parser, TOK_IDENT)) {
        if (strcmp(parser->previous.as.ident, "_") == 0) {
            p->kind = PATTERN_WILD;
        } else {
            p->kind = PATTERN_VARIANT;
            char variant_buf[512];
            parse_dotted_name(parser, variant_buf, sizeof(variant_buf), "Expect identifier after '.' in match arm");
            p->as.variant.name = parser_strdup(parser, variant_buf);
            
            if (parser_match(parser, TOK_LPAREN)) {
                uint32_t bind_count = 0;
                uint32_t bind_capacity = 4;
                char** binds = ARENA_ALLOC_ARRAY(parser->arena, char*, bind_capacity);
                while (!parser_check(parser, TOK_RPAREN) && !parser_check(parser, TOK_EOF)) {
                    if (parser_match(parser, TOK_IDENT)) {
                        if (bind_count >= bind_capacity) {
                            uint32_t old_cap = bind_capacity;
                            bind_capacity *= 2;
                            binds = ARENA_REALLOC_ARRAY(parser->arena, char*, binds, old_cap, bind_capacity);
                        }
                        if (strcmp(parser->previous.as.ident, "_") == 0) {
                            binds[bind_count++] = NULL;
                        } else {
                            binds[bind_count++] = parser_dup_ident(parser);
                        }
                    } else {
                        parser_error(parser, "Expect identifier in pattern bind list");
                    }
                    if (!parser_match(parser, TOK_COMMA)) break;
                }
                parser_consume(parser, TOK_RPAREN, "Expect ')' after bind list");
                p->as.variant.bind_names = binds;
                p->as.variant.bind_count = bind_count;
            } else {
                p->as.variant.bind_names = NULL;
                p->as.variant.bind_count = 0;
            }
        }
    } else {
        parser_error(parser, "Expect pattern in match arm");
        return NULL;
    }
    return p;
}

MatchExpr* parse_match_expr(Parser* parser) {
    MatchExpr* m = ARENA_ALLOC(parser->arena, MatchExpr);
    if (!m) return NULL;
    bool old_allow = parser->allow_struct_literal;
    parser->allow_struct_literal = false;
    m->target = parse_expression(parser);
    parser->allow_struct_literal = old_allow;
    parser_consume(parser, TOK_LBRACE, "Expect '{' after match target");
    uint32_t capacity = 4;
    m->arms = ARENA_ALLOC_ARRAY(parser->arena, MatchArm*, capacity);
    while (!parser_check(parser, TOK_RBRACE) && !parser_check(parser, TOK_EOF)) {
        MatchArm* arm = ARENA_ALLOC(parser->arena, MatchArm);
        if (!arm) {
            parser_error(parser, "Out of memory");
            break;
        }
        
        Pattern* head = NULL;
        Pattern* tail = NULL;
        
        do {
            Pattern* p = parse_pattern(parser);
            if (!p) break;

            if (!head) {
                head = p;
                tail = p;
            } else {
                tail->next = p;
                tail = p;
            }
        } while (parser_match(parser, TOK_OR));

        arm->pattern = head;

        if (parser->had_error) break;

        if (!parser_match(parser, TOK_ARROW)) {
             parser_error(parser, "Expect '=>' after match arm");
             break;
        }
        arm->body = parse_expression(parser);
        if (m->arm_count >= capacity) {
            uint32_t old_capacity = capacity;
            capacity *= 2;
            m->arms = ARENA_REALLOC_ARRAY(parser->arena, MatchArm*, m->arms, old_capacity, capacity);
        }
        m->arms[m->arm_count++] = arm;
        if (!parser_match(parser, TOK_COMMA)) break;
    }
    parser_consume(parser, TOK_RBRACE, "Expect '}' after match arms");
    return m;
}

IfExpr* parse_if_expr_internal(Parser* parser) {
    IfExpr* if_expr = ARENA_ALLOC(parser->arena, IfExpr);
    if (!if_expr) return NULL;
    if (parser_match(parser, TOK_ANNOT)) {
        if (strcmp(parser->previous.as.ident, "@unlikely") == 0) if_expr->annotation = ANNOT_UNLIKELY;
        else if (strcmp(parser->previous.as.ident, "@likely") == 0) if_expr->annotation = ANNOT_LIKELY;
    }
    bool old_allow = parser->allow_struct_literal;
    parser->allow_struct_literal = false;
    if_expr->condition = parse_expression(parser);
    parser->allow_struct_literal = old_allow;
    reject_assignment_condition(parser, if_expr->condition);
    if_expr->then_block = parse_block(parser);
    if (parser_match(parser, TOK_ELSE)) {
        if (parser_match(parser, TOK_IF)) {
            IfExpr* nested_if = parse_if_expr_internal(parser);
            BlockExpr* b = ARENA_ALLOC(parser->arena, BlockExpr);
            if (b) {
                b->result = expr_create(parser);
                if (b->result) {
                    b->result->kind = EXPR_IF;
                    b->result->as.if_expr = nested_if;
                } else {
                    
                    
                    b = NULL;
                }
            } else {
                
            }
            if_expr->else_block = b;
        } else {
            if_expr->else_block = parse_block(parser);
        }
    }
    return if_expr;
}
