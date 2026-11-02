#ifndef SURFACE_PARSER_INTERNAL_H
#define SURFACE_PARSER_INTERNAL_H

#include "surface_parser.h"
#include "surface_lexer.h"
#include "diagnostics.h"
#include "arena.h"

#define ARENA_ALLOC(arena, type) ((type*)memset(arena_alloc(arena, sizeof(type), _Alignof(type)), 0, sizeof(type)))
#define ARENA_ALLOC_ARRAY(arena, type, count) ((type*)memset(arena_alloc(arena, sizeof(type) * (uint32_t)(count), _Alignof(type)), 0, sizeof(type) * (uint32_t)(count)))
#define ARENA_REALLOC_ARRAY(arena, type, old_ptr, old_count, new_count) \
    ((type*)arena_realloc(arena, old_ptr, sizeof(type) * (uint32_t)(old_count), sizeof(type) * (uint32_t)(new_count), _Alignof(type)))

typedef struct {
    Lexer lexer;
    Token current;
    Token previous;
    Token buffered;
    bool has_buffered;
    bool had_error;
    bool allow_struct_literal;
    const char* file_path;
    DiagnosticReport* report;
    Arena* arena;
    // The names this file's imports are known by (alias, else file stem): `ns::item` reads as
    // `item` (parser_advance), every module's items sharing one namespace here.
    const char* namespaces[64];
    uint32_t namespace_count;
} Parser;

void parser_advance(Parser* parser);
void parser_add_namespace(Parser* parser, const char* name);
void parser_buffer(Parser* parser, Token tok);
bool parser_check(Parser* parser, TokenKind kind);
bool parser_match(Parser* parser, TokenKind kind);
void parser_diag_at(Parser* parser, DiagnosticSeverity severity, const char* fmt, ...) PRINTF_FORMAT(3, 4);
void parser_error(Parser* parser, const char* message);
void parser_synchronize(Parser* parser);
void parser_consume(Parser* parser, TokenKind kind, const char* message);
void parser_consume_gt(Parser* parser, const char* message);
char* parser_dup_ident(const Parser* parser);
char* parser_strdup(Parser* parser, const char* s);

// Common parsing helpers
const char* type_to_suffix(const ILType* ty);
const ILType* parse_type(Parser* parser);
char** parse_type_params(Parser* parser, uint32_t* count, char*** bounds_out);
const ILType ** parse_type_args(Parser* parser, uint32_t* count);

// Main entry points
Expression* parse_expression(Parser* parser);
Expression* parse_expression_no_binary(Parser* parser);
BlockExpr* parse_block(Parser* parser);
IfExpr* parse_if_expr_internal(Parser* parser);

StructDecl* parse_struct(Parser* parser, bool is_pub);
EnumDecl* parse_enum(Parser* parser, bool is_pub);
FunctionDecl* parse_function(Parser* parser, bool is_extern);
/* Parses the body of one `#[...]` attribute after the '#'; sets *is_must_use for
 * #[must_use]. */
void parse_attribute(Parser* parser, bool* is_must_use);
ImportDecl* parse_import(Parser* parser);
GlobalDecl* parse_global(Parser* parser, bool is_const);
TypeAliasDecl* parse_type_alias(Parser* parser, bool is_pub);
TraitDecl* parse_trait(Parser* parser, bool is_pub);
ImplDecl* parse_impl(Parser* parser);

void surface_expr_free(Expression* expr);
void surface_block_free(BlockExpr* block);
void surface_if_expr_free(IfExpr* if_expr);

Expression* expr_create(Parser* parser);
Statement* stmt_create(Parser* parser);

#endif
