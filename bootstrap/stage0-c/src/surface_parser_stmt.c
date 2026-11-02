#include <stdlib.h>
#include <string.h>
#include "surface_parser.h"
#include "surface_parser_internal.h"

static Statement* parse_statement_impl(Parser* parser) {
    if (parser_match(parser, TOK_SEMICOLON)) {
        Statement* stmt = stmt_create(parser);
        if (!stmt) return NULL;
        stmt->kind = STMT_RESERVED;
        return stmt;
    }
    if (parser_match(parser, TOK_RETURN)) {
        Statement* stmt = stmt_create(parser);
        if (!stmt) return NULL;
        stmt->kind = STMT_RETURN;
        if (!parser_check(parser, TOK_SEMICOLON)) {
            stmt->as.ret = parse_expression(parser);
        }
        parser_consume(parser, TOK_SEMICOLON, "Expect ';' after return");
        return stmt;
    }
    if (parser_match(parser, TOK_LET)) {
        Statement* stmt = stmt_create(parser);
        if (!stmt) return NULL;
        stmt->kind = STMT_LET;
        if (parser_match(parser, TOK_MUT)) {
            stmt->as.let.is_mutable = true;
        }
        parser_consume(parser, TOK_IDENT, "Expect variable name");
        if (parser->previous.kind == TOK_IDENT) {
            stmt->as.let.name = parser_dup_ident(parser);
        } else {
            stmt->as.let.name = parser_strdup(parser, "?");
        }
        if (parser_match(parser, TOK_COLON)) {
            stmt->as.let.type = parse_type(parser);
        }
        parser_consume(parser, TOK_ASSIGN, "Expect '='");
        stmt->as.let.init = parse_expression(parser);
        parser_consume(parser, TOK_SEMICOLON, "Expect ';' after let");
        return stmt;
    }
    if (parser_match(parser, TOK_FOR)) {
        Statement* stmt = stmt_create(parser);
        if (!stmt) return NULL;
        stmt->kind = STMT_FOR;
        parser_consume(parser, TOK_IDENT, "Expect loop variable");
        if (parser->previous.kind == TOK_IDENT) {
            stmt->as.for_loop.var_name = parser_dup_ident(parser);
        } else {
            stmt->as.for_loop.var_name = parser_strdup(parser, "?");
        }
        parser_consume(parser, TOK_IN, "Expect 'in'");
        bool old_allow = parser->allow_struct_literal;
        parser->allow_struct_literal = false;
        stmt->as.for_loop.start = parse_expression(parser);
        parser_consume(parser, TOK_DOTDOT, "Expect '..'");
        stmt->as.for_loop.end = parse_expression(parser);
        parser->allow_struct_literal = old_allow;
        stmt->as.for_loop.body = parse_block(parser);
        return stmt;
    }
    if (parser_match(parser, TOK_BREAK)) {
        Statement* stmt = stmt_create(parser);
        if (!stmt) return NULL;
        stmt->kind = STMT_BREAK;
        parser_consume(parser, TOK_SEMICOLON, "Expect ';' after break");
        return stmt;
    }
    if (parser_match(parser, TOK_CONTINUE)) {
        Statement* stmt = stmt_create(parser);
        if (!stmt) return NULL;
        stmt->kind = STMT_CONTINUE;
        parser_consume(parser, TOK_SEMICOLON, "Expect ';' after continue");
        return stmt;
    }
    if (parser_match(parser, TOK_DEFER)) {
        Statement* stmt = stmt_create(parser);
        if (!stmt) return NULL;
        stmt->kind = STMT_DEFER;
        if (parser_check(parser, TOK_LBRACE)) {
            stmt->as.defer_block = parse_block(parser);
            if (parser_check(parser, TOK_SEMICOLON)) {
                parser_advance(parser);
            }
        } else {
            stmt->as.defer_block = ARENA_ALLOC(parser->arena, BlockExpr);
            if (stmt->as.defer_block) {
                stmt->as.defer_block->statements = ARENA_ALLOC(parser->arena, Statement*);
                if (stmt->as.defer_block->statements) {
                    stmt->as.defer_block->stmt_count = 1;
                    Statement* inner = stmt_create(parser);
                    if (inner) {
                        inner->kind = STMT_EXPR;
                        inner->as.expr = parse_expression(parser);
                        stmt->as.defer_block->statements[0] = inner;
                    }
                }
            }
            if (!parser_check(parser, TOK_SEMICOLON) && parser->previous.kind != TOK_SEMICOLON) {
                 parser_consume(parser, TOK_SEMICOLON, "Expect ';' after defer expression");
            } else if (parser_check(parser, TOK_SEMICOLON)) {
                 parser_advance(parser);
            }
        }
        return stmt;
    }

    Expression* expr = parse_expression(parser);
    if (expr) {
        Statement* stmt = stmt_create(parser);
        if (!stmt) {  return NULL; }
        stmt->kind = STMT_EXPR;
        stmt->as.expr = expr;
        
        bool is_block_expr = (expr->kind == EXPR_IF || expr->kind == EXPR_WHILE || 
                              expr->kind == EXPR_MATCH || expr->kind == EXPR_BLOCK);
        
        if (is_block_expr) {
            if (parser_match(parser, TOK_SEMICOLON)) {
                // optional
            }
        } else {
            parser_consume(parser, TOK_SEMICOLON, "Expect ';' after expression statement");
        }
        return stmt;
    }
    return NULL;
}

static Statement* parse_statement(Parser* parser) {
    Token start_tok = parser->current;
    Statement* stmt = parse_statement_impl(parser);
    if (stmt) {
        stmt->line = start_tok.line;
        stmt->col = start_tok.col;
        stmt->offset = start_tok.offset;
        stmt->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
    }
    return stmt;
}

BlockExpr* parse_block(Parser* parser) {
    parser_consume(parser, TOK_LBRACE, "Expect '{' to start block");
    BlockExpr* block = ARENA_ALLOC(parser->arena, BlockExpr);
    if (!block) return NULL;
    uint32_t capacity = 8;
    block->statements = ARENA_ALLOC_ARRAY(parser->arena, Statement*, capacity);
    if (!block->statements) {  return NULL; }

    while (!parser_check(parser, TOK_RBRACE) && !parser_check(parser, TOK_EOF)) {
        // We need to differentiate between a statement and a result expression.
        // A statement usually ends in a semicolon, or is a block-like expression.
        
        bool is_stmt_keyword = (parser_check(parser, TOK_LET) || parser_check(parser, TOK_RETURN) ||
                                parser_check(parser, TOK_FOR) || parser_check(parser, TOK_DEFER) || 
                                parser_check(parser, TOK_BREAK) || parser_check(parser, TOK_CONTINUE));
        
        // Peek ahead for if/while/loop/match which can be EITHER stmt or result.
        bool is_block_keyword = (parser_check(parser, TOK_IF) || parser_check(parser, TOK_WHILE) || 
                                 parser_check(parser, TOK_LOOP) || parser_check(parser, TOK_MATCH) ||
                                 parser_check(parser, TOK_LBRACE) || parser_check(parser, TOK_UNSAFE));

        if (is_stmt_keyword) {
            Statement* stmt = parse_statement(parser);
            if (stmt) {
                if (block->stmt_count >= capacity) {
                    uint32_t old_capacity = capacity;
                    capacity *= 2;
                    block->statements = ARENA_REALLOC_ARRAY(parser->arena, Statement*, block->statements, old_capacity, capacity);
                }
                block->statements[block->stmt_count++] = stmt;
            }
            continue;
        }

        if (is_block_keyword) {
            // Statement position: the block ends the expression. See
            // parse_expression_no_binary().
            Expression* expr = parse_expression_no_binary(parser);
            if (parser_match(parser, TOK_SEMICOLON)) {
                // Semicolon present -> definitely a statement.
                Statement* stmt = stmt_create(parser);
                if (stmt) {
                    stmt->kind = STMT_EXPR;
                    stmt->as.expr = expr;
                    if (block->stmt_count >= capacity) {
                        uint32_t old_capacity = capacity;
                        capacity *= 2;
                        block->statements = ARENA_REALLOC_ARRAY(parser->arena, Statement*, block->statements, old_capacity, capacity);
                    }
                    block->statements[block->stmt_count++] = stmt;
                }
            } else if (parser_check(parser, TOK_RBRACE)) {
                // No semicolon and followed by '}' -> definitely result.
                block->result = expr;
                break;
            } else {
                // No semicolon but followed by more tokens -> treat as statement (optional semicolon).
                Statement* stmt = stmt_create(parser);
                if (stmt) {
                    stmt->kind = STMT_EXPR;
                    stmt->as.expr = expr;
                    if (block->stmt_count >= capacity) {
                        uint32_t old_capacity = capacity;
                        capacity *= 2;
                        block->statements = ARENA_REALLOC_ARRAY(parser->arena, Statement*, block->statements, old_capacity, capacity);
                    }
                    block->statements[block->stmt_count++] = stmt;
                }
            }
            continue;
        }

        // Other expressions: must have semicolon to be a statement, otherwise it's the result.
        Expression* expr = parse_expression(parser);
        if (expr) {
            if (parser_match(parser, TOK_SEMICOLON)) {
                Statement* stmt = stmt_create(parser);
                if (stmt) {
                    stmt->kind = STMT_EXPR;
                    stmt->as.expr = expr;
                    if (block->stmt_count >= capacity) {
                        uint32_t old_capacity = capacity;
                        capacity *= 2;
                        block->statements = ARENA_REALLOC_ARRAY(parser->arena, Statement*, block->statements, old_capacity, capacity);
                    }
                    block->statements[block->stmt_count++] = stmt;
                }
            } else if (parser_check(parser, TOK_RBRACE)) {
                block->result = expr;
                break;
            } else {
                parser_error(parser, "Expect ';' after expression or '}' to end block");
                parser_synchronize(parser);
            }
        } else {
            parser_synchronize(parser);
        }
    }
    parser_consume(parser, TOK_RBRACE, "Expect '}' after block");
    return block;
}
