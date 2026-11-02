#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include "surface_parser.h"
#include "surface_lexer.h"
#include "diagnostics.h"
#include "surface_parser_internal.h"

static bool is_namespace(Parser* parser, const char* name) {
    for (uint32_t i = 0; i < parser->namespace_count; i++) {
        if (strcmp(parser->namespaces[i], name) == 0) return true;
    }
    return false;
}

// `ns::name`, with `ns` one of this file's imports, reads as `name`.
static void skip_namespace_prefix(Parser* parser) {
    while (parser->current.kind == TOK_IDENT && is_namespace(parser, parser->current.as.ident)) {
        Lexer ahead = parser->lexer;
        Token sep = lexer_next(&ahead);
        if (sep.kind != TOK_COLONCOLON) { lexer_token_free(sep); return; }
        Token name = lexer_next(&ahead);
        lexer_token_free(sep);
        if (name.kind != TOK_IDENT) { lexer_token_free(name); return; }
        lexer_token_free(parser->current);
        parser->lexer = ahead;
        parser->current = name;
    }
}

void parser_add_namespace(Parser* parser, const char* name) {
    if (parser->namespace_count < sizeof(parser->namespaces) / sizeof(parser->namespaces[0])) {
        parser->namespaces[parser->namespace_count++] = name;
    }
}

void parser_advance(Parser* parser) {
    lexer_token_free(parser->previous);
    parser->previous = parser->current;
    if (parser->has_buffered) {
        parser->current = parser->buffered;
        parser->has_buffered = false;
        return;
    }
    parser->current = lexer_next(&parser->lexer);
    if (parser->current.kind == TOK_ERROR) {
        parser->had_error = true;
        parser_error(parser, "Lexer error: unexpected character or invalid token");
    }
    skip_namespace_prefix(parser);
}

void parser_buffer(Parser* parser, Token tok) {
    parser->buffered = parser->current;
    parser->current = tok;
    parser->has_buffered = true;
}

bool parser_check(Parser* parser, TokenKind kind) {
    return parser->current.kind == kind;
}

bool parser_match(Parser* parser, TokenKind kind) {
    if (!parser_check(parser, kind)) return false;
    parser_advance(parser);
    return true;
}

void parser_diag_at(Parser* parser, DiagnosticSeverity severity, const char* fmt, ...) {
    if (severity == DIAG_ERROR) parser->had_error = true;
    va_list args;
    va_start(args, fmt);
    SourceLocation loc = {
        .file_path = parser->file_path,
        .source = parser->lexer.src,
        .line = parser->current.line,
        .col = parser->current.col,
        .offset = parser->current.offset,
        .length = parser->current.length
    };
    if (loc.length == 0) loc.length = 1;
    
    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    
    diag_emit(parser->report, severity, loc, "%s", buf);
    if (severity == DIAG_ERROR || severity == DIAG_FATAL) {
        parser->had_error = true;
    }
}

void parser_error(Parser* parser, const char* message) {
    parser_diag_at(parser, DIAG_ERROR, "%s", message);
}

void parser_synchronize(Parser* parser) {
    parser_advance(parser);
    while (parser->current.kind != TOK_EOF) {
        if (parser->previous.kind == TOK_SEMICOLON) return;

        switch (parser->current.kind) {
            case TOK_STRUCT:
            case TOK_ENUM:
            case TOK_FN:
            case TOK_LET:
            case TOK_FOR:
            case TOK_IF:
            case TOK_WHILE:
            case TOK_LOOP:
            case TOK_MATCH:
            case TOK_RETURN:
            case TOK_TRAIT:
            case TOK_IMPL:
            case TOK_PUB:
            case TOK_STATIC:
            case TOK_CONST:
            case TOK_TYPE:
            case TOK_RBRACE:
                return;
            default:
                break;
        }

        parser_advance(parser);
    }
}

void parser_consume_gt(Parser* parser, const char* message) {
    if (parser_match(parser, TOK_GT)) return;
    if (parser_match(parser, TOK_SHR)) {
        Token gt = parser->previous;
        gt.kind = TOK_GT;
        gt.length = 1;
        gt.col++;
        gt.offset++;
        parser_buffer(parser, gt);
        return;
    }
    parser_error(parser, message);
}

char* parser_dup_ident(const Parser* parser) {
    uint32_t len = parser->previous.length;
    char* res = arena_alloc(parser->arena, (size_t)len + 1, 1);
    memcpy(res, parser->lexer.src + parser->previous.offset, len);
    res[len] = '\0';
    return res;
}

char* parser_strdup(Parser* parser, const char* s) {
    if (!s) return NULL;
    size_t len = strlen(s);
    char* res = arena_alloc(parser->arena, len + 1, 1);
    memcpy(res, s, len + 1);
    return res;
}

void parser_consume(Parser* parser, TokenKind kind, const char* message) {
    if (parser->current.kind == kind) {
        parser_advance(parser);
        return;
    }
    parser_error(parser, message);
    if (parser->current.kind != TOK_EOF) {
        parser_advance(parser);
    }
}


const char* type_to_suffix(const ILType* ty) {
    if (!ty) return "unknown";
    switch (ty->kind) {
        case IL_TY_I8: return "i8";
        case IL_TY_I16: return "i16";
        case IL_TY_I32: return "i32";
        case IL_TY_I64: return "i64";
        case IL_TY_U8: return "u8";
        case IL_TY_U16: return "u16";
        case IL_TY_U32: return "u32";
        case IL_TY_U64: return "u64";
        case IL_TY_F32: return "f32";
        case IL_TY_F64: return "f64";
        case IL_TY_BOOL: return "bool";
        case IL_TY_USIZE: return "usize";
        case IL_TY_ISIZE: return "isize";
        case IL_TY_PTR: return "ptr";
        case IL_TY_SLICE: {
            if (ty->as.slice.element && ty->as.slice.element->kind == IL_TY_U8) return "su8";
            return "slice";
        }
        case IL_TY_ARRAY: return "array";
        case IL_TY_STRUCT: return ty->as.struct_sum.name;
        case IL_TY_SUM: return ty->as.struct_sum.name;
        default: return "other";
    }
}

SurfaceModule* surface_parse_module(const char* src, const char* file_path, DiagnosticReport* report) {
    SurfaceModule* mod = calloc(1, sizeof(SurfaceModule));
    if (!mod) return NULL;
    arena_init(&mod->arena, 1024 * 1024);
    mod->file_path = file_path;
    mod->source = src;

    Parser parser;
    memset(&parser, 0, sizeof(Parser));
    parser.lexer = lexer_create(src);
    parser.allow_struct_literal = true;
    parser.file_path = file_path;
    parser.report = report;
    parser.arena = &mod->arena;
    parser_advance(&parser);

    uint32_t capacity = 4;
    mod->imports = ARENA_ALLOC_ARRAY(parser.arena, ImportDecl*, capacity);
    mod->functions = ARENA_ALLOC_ARRAY(parser.arena, FunctionDecl*, capacity);
    mod->type_defs = ARENA_ALLOC_ARRAY(parser.arena, TypeDef*, capacity);
    mod->globals = ARENA_ALLOC_ARRAY(parser.arena, GlobalDecl*, capacity);
    mod->type_aliases = ARENA_ALLOC_ARRAY(parser.arena, TypeAliasDecl*, capacity);
    mod->traits = ARENA_ALLOC_ARRAY(parser.arena, TraitDecl*, capacity);
    mod->impls = ARENA_ALLOC_ARRAY(parser.arena, ImplDecl*, capacity);

    while (!parser_check(&parser, TOK_EOF)) {
        bool is_pub = false;
        bool is_extern = false;
        bool is_must_use = false;

        while (parser_match(&parser, TOK_PUB) || parser_match(&parser, TOK_EXTERN) || parser_match(&parser, TOK_UNSAFE) || parser_match(&parser, TOK_HASH)) {
            if (parser.previous.kind == TOK_PUB) {
                is_pub = true;
            } else if (parser.previous.kind == TOK_EXTERN) {
                is_extern = true;
            } else if (parser.previous.kind == TOK_HASH) {
                parse_attribute(&parser, &is_must_use);
            }
        }

        if (mod->import_count >= capacity - 1 || mod->function_count >= capacity - 1 || 
            mod->type_def_count >= capacity - 1 || mod->global_count >= capacity - 1 ||
            mod->type_alias_count >= capacity - 1 || mod->trait_count >= capacity - 1 || 
            mod->impl_count >= capacity - 1) {
            uint32_t old_capacity = capacity;
            capacity *= 2;
            
            ImportDecl** new_imports = ARENA_ALLOC_ARRAY(parser.arena, ImportDecl*, capacity);
            memcpy(new_imports, mod->imports, old_capacity * sizeof(ImportDecl*));
            mod->imports = new_imports;

            FunctionDecl** new_functions = ARENA_ALLOC_ARRAY(parser.arena, FunctionDecl*, capacity);
            memcpy(new_functions, mod->functions, old_capacity * sizeof(FunctionDecl*));
            mod->functions = new_functions;

            TypeDef** new_type_defs = ARENA_ALLOC_ARRAY(parser.arena, TypeDef*, capacity);
            memcpy(new_type_defs, mod->type_defs, old_capacity * sizeof(TypeDef*));
            mod->type_defs = new_type_defs;

            GlobalDecl** new_globals = ARENA_ALLOC_ARRAY(parser.arena, GlobalDecl*, capacity);
            memcpy(new_globals, mod->globals, old_capacity * sizeof(GlobalDecl*));
            mod->globals = new_globals;

            TypeAliasDecl** new_aliases = ARENA_ALLOC_ARRAY(parser.arena, TypeAliasDecl*, capacity);
            memcpy(new_aliases, mod->type_aliases, old_capacity * sizeof(TypeAliasDecl*));
            mod->type_aliases = new_aliases;

            TraitDecl** new_traits = ARENA_ALLOC_ARRAY(parser.arena, TraitDecl*, capacity);
            memcpy(new_traits, mod->traits, old_capacity * sizeof(TraitDecl*));
            mod->traits = new_traits;

            ImplDecl** new_impls = ARENA_ALLOC_ARRAY(parser.arena, ImplDecl*, capacity);
            memcpy(new_impls, mod->impls, old_capacity * sizeof(ImplDecl*));
            mod->impls = new_impls;
        }

        if (parser_check(&parser, TOK_IDENT) && strcmp(parser.current.as.ident, "use") == 0) {
            // `use ns::name;` / `use ns::{a, b};`: every module's items are in scope already.
            while (!parser_check(&parser, TOK_SEMICOLON) && !parser_check(&parser, TOK_EOF)) parser_advance(&parser);
            parser_consume(&parser, TOK_SEMICOLON, "Expect ';' after use");
        } else if (parser_check(&parser, TOK_IMPORT)) {
            if (is_pub) parser_error(&parser, "Imports cannot be public");
            if (is_extern) parser_error(&parser, "Imports cannot be extern");
            ImportDecl* imp = parse_import(&parser);
            if (imp) mod->imports[mod->import_count++] = imp;
        } else if (parser_check(&parser, TOK_STRUCT)) {
            TypeDef* def = ARENA_ALLOC(parser.arena, TypeDef);
            if (def) {
                def->kind = TYPE_DEF_STRUCT;
                def->is_pub = is_pub;
                def->file_path = parser.file_path;
                def->as.struct_decl = parse_struct(&parser, is_pub);
                mod->type_defs[mod->type_def_count++] = def;
            }
        } else if (parser_check(&parser, TOK_ENUM)) {
            TypeDef* def = ARENA_ALLOC(parser.arena, TypeDef);
            if (def) {
                def->kind = TYPE_DEF_ENUM;
                def->is_pub = is_pub;
                def->file_path = parser.file_path;
                def->as.enum_decl = parse_enum(&parser, is_pub);
                mod->type_defs[mod->type_def_count++] = def;
            }
        } else if (parser_check(&parser, TOK_TRAIT)) {
            TraitDecl* trait = parse_trait(&parser, is_pub);
            if (trait) mod->traits[mod->trait_count++] = trait;
        } else if (parser_check(&parser, TOK_IMPL)) {
            ImplDecl* impl = parse_impl(&parser);
            if (impl) mod->impls[mod->impl_count++] = impl;
        } else if (parser_check(&parser, TOK_FN)) {
            FunctionDecl* fn = parse_function(&parser, is_extern);
            if (fn) {
                fn->is_pub = is_pub;
                fn->is_must_use = is_must_use;
                mod->functions[mod->function_count++] = fn;
            }
        } else if (parser_check(&parser, TOK_CONST) || parser_check(&parser, TOK_STATIC)) {
            bool is_const = parser_check(&parser, TOK_CONST);
            GlobalDecl* g = parse_global(&parser, is_const);
            if (g) {
                g->is_pub = is_pub;
                mod->globals[mod->global_count++] = g;
            }
        } else if (parser_check(&parser, TOK_TYPE)) {
            TypeAliasDecl* alias = parse_type_alias(&parser, is_pub);
            if (alias) {
                mod->type_aliases[mod->type_alias_count++] = alias;
            }
        } else {
            char buf[128];
            lexer_token_print(parser.current, buf, sizeof(buf));
            char error_msg[256];
            snprintf(error_msg, sizeof(error_msg), "Unexpected token in top-level declaration: %s", buf);
            parser_error(&parser, error_msg);
            parser_synchronize(&parser);
        }
    }
    lexer_token_free(parser.current);
    lexer_token_free(parser.previous);
    if (parser.had_error) {
        surface_mod_free(mod);
        return NULL;
    }
    return mod;
}

Expression* expr_create(Parser* parser) {
    Expression* expr = ARENA_ALLOC(parser->arena, Expression);
    if (expr) {
        memset(expr, 0, sizeof(Expression));
        expr->file_path = parser->file_path;
        expr->source = parser->lexer.src;
        expr->line = parser->previous.line;
        expr->col = parser->previous.col;
        expr->offset = parser->previous.offset;
        expr->length = parser->previous.length;
    }
    return expr;
}

Statement* stmt_create(Parser* parser) {
    Statement* stmt = ARENA_ALLOC(parser->arena, Statement);
    if (stmt) {
        memset(stmt, 0, sizeof(Statement));
        stmt->file_path = parser->file_path;
        stmt->source = parser->lexer.src;
        stmt->line = parser->previous.line;
        stmt->col = parser->previous.col;
        stmt->offset = parser->previous.offset;
        stmt->length = parser->previous.length;
    }
    return stmt;
}

void surface_expr_free(Expression* expr) { (void)expr; }
void surface_block_free(BlockExpr* block) { (void)block; }
void surface_if_expr_free(IfExpr* if_expr) { (void)if_expr; }

void surface_mod_free(SurfaceModule* mod) {
    if (!mod) return;
    arena_destroy(&mod->arena);
    free(mod);
}

void surface_mod_merge(SurfaceModule* dest, SurfaceModule* src) {
    if (!dest || !src) return;
    arena_merge(&dest->arena, &src->arena);

    if (src->function_count > 0) {
        FunctionDecl** new_fns = ARENA_ALLOC_ARRAY(&dest->arena, FunctionDecl*, dest->function_count + src->function_count);
        memcpy(new_fns, dest->functions, dest->function_count * sizeof(FunctionDecl*));
        memcpy(new_fns + dest->function_count, src->functions, src->function_count * sizeof(FunctionDecl*));
        dest->functions = new_fns;
        dest->function_count += src->function_count;
    }
    if (src->type_def_count > 0) {
        TypeDef** new_defs = ARENA_ALLOC_ARRAY(&dest->arena, TypeDef*, dest->type_def_count + src->type_def_count);
        memcpy(new_defs, dest->type_defs, dest->type_def_count * sizeof(TypeDef*));
        memcpy(new_defs + dest->type_def_count, src->type_defs, src->type_def_count * sizeof(TypeDef*));
        dest->type_defs = new_defs;
        dest->type_def_count += src->type_def_count;
    }
    if (src->global_count > 0) {
        GlobalDecl** new_globs = ARENA_ALLOC_ARRAY(&dest->arena, GlobalDecl*, dest->global_count + src->global_count);
        memcpy(new_globs, dest->globals, dest->global_count * sizeof(GlobalDecl*));
        memcpy(new_globs + dest->global_count, src->globals, src->global_count * sizeof(GlobalDecl*));
        dest->globals = new_globs;
        dest->global_count += src->global_count;
    }
    if (src->type_alias_count > 0) {
        TypeAliasDecl** new_als = ARENA_ALLOC_ARRAY(&dest->arena, TypeAliasDecl*, dest->type_alias_count + src->type_alias_count);
        memcpy(new_als, dest->type_aliases, dest->type_alias_count * sizeof(TypeAliasDecl*));
        memcpy(new_als + dest->type_alias_count, src->type_aliases, src->type_alias_count * sizeof(TypeAliasDecl*));
        dest->type_aliases = new_als;
        dest->type_alias_count += src->type_alias_count;
    }
    if (src->trait_count > 0) {
        TraitDecl** new_traits = ARENA_ALLOC_ARRAY(&dest->arena, TraitDecl*, dest->trait_count + src->trait_count);
        memcpy(new_traits, dest->traits, dest->trait_count * sizeof(TraitDecl*));
        memcpy(new_traits + dest->trait_count, src->traits, src->trait_count * sizeof(TraitDecl*));
        dest->traits = new_traits;
        dest->trait_count += src->trait_count;
    }
    if (src->impl_count > 0) {
        ImplDecl** new_impls = ARENA_ALLOC_ARRAY(&dest->arena, ImplDecl*, dest->impl_count + src->impl_count);
        memcpy(new_impls, dest->impls, dest->impl_count * sizeof(ImplDecl*));
        memcpy(new_impls + dest->impl_count, src->impls, src->impl_count * sizeof(ImplDecl*));
        dest->impls = new_impls;
        dest->impl_count += src->impl_count;
    }
    
}
