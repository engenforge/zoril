#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "surface_parser_internal.h"
#include "il_type.h"

/* Build a mangled name for an ILType, including type args (e.g. Stack<i32> -> "Stack_i32"). */
static char* impl_type_to_name(Parser* parser, const ILType* ty) {
    if (!ty) return parser_strdup(parser, "unknown");
    if (ty->kind == IL_TY_STRUCT || ty->kind == IL_TY_SUM) {
        const char* base = ty->as.struct_sum.name ? ty->as.struct_sum.name : "unknown";
        if (ty->as.struct_sum.type_arg_count == 0) return parser_strdup(parser, base);
        size_t len = strlen(base);
        for (uint32_t i = 0; i < ty->as.struct_sum.type_arg_count; i++)
            len += strlen(type_to_suffix(ty->as.struct_sum.type_args[i])) + 1;
        char* buf = arena_alloc(parser->arena, len + 1, 1);
        if (!buf) return NULL;
        strcpy(buf, base);
        for (uint32_t i = 0; i < ty->as.struct_sum.type_arg_count; i++) {
            strcat(buf, "_");
            strcat(buf, type_to_suffix(ty->as.struct_sum.type_args[i]));
        }
        return buf;
    }
    return parser_strdup(parser, type_to_suffix(ty));
}

StructDecl* parse_struct(Parser* parser, bool is_pub) {
    Token start_tok = parser->current;
    parser_consume(parser, TOK_STRUCT, "Expect 'struct'");
    parser_consume(parser, TOK_IDENT, "Expect struct name");
    StructDecl* decl = ARENA_ALLOC(parser->arena, StructDecl);
    if (!decl) return NULL;
    decl->file_path = parser->file_path;
    decl->is_pub = is_pub;
    decl->line = start_tok.line;
    decl->col = start_tok.col;
    decl->name = parser_dup_ident(parser);
    if (parser_check(parser, TOK_LT)) {
        decl->type_params = parse_type_params(parser, &decl->type_param_count, &decl->type_bounds);
    }
    parser_consume(parser, TOK_LBRACE, "Expect '{' before struct body");
    uint32_t capacity = 4;
    decl->fields = ARENA_ALLOC_ARRAY(parser->arena, Param, capacity);
    while (!parser_check(parser, TOK_RBRACE) && !parser_check(parser, TOK_EOF)) {
        bool is_field_pub = parser_match(parser, TOK_PUB);
        parser_consume(parser, TOK_IDENT, "Expect field name");
        if (decl->field_count >= capacity) {
            uint32_t old_capacity = capacity;
            capacity *= 2;
            decl->fields = ARENA_REALLOC_ARRAY(parser->arena, Param, decl->fields, old_capacity, capacity);
        }
        decl->fields[decl->field_count].name = parser_dup_ident(parser);
        decl->fields[decl->field_count].is_pub = is_field_pub;
        parser_consume(parser, TOK_COLON, "Expect ':' after field name");
        decl->fields[decl->field_count].type = parse_type(parser);
        decl->field_count++;
        if (!parser_match(parser, TOK_COMMA)) break;
    }
    parser_consume(parser, TOK_RBRACE, "Expect '}' after struct body");
    decl->offset = start_tok.offset;
    decl->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
    return decl;
}

EnumDecl* parse_enum(Parser* parser, bool is_pub) {
    Token start_tok = parser->current;
    parser_consume(parser, TOK_ENUM, "Expect 'enum'");
    parser_consume(parser, TOK_IDENT, "Expect enum name");
    EnumDecl* decl = ARENA_ALLOC(parser->arena, EnumDecl);
    if (!decl) return NULL;
    decl->file_path = parser->file_path;
    decl->is_pub = is_pub;
    decl->line = start_tok.line;
    decl->col = start_tok.col;
    decl->name = parser_dup_ident(parser);
    if (parser_check(parser, TOK_LT)) {
        decl->type_params = parse_type_params(parser, &decl->type_param_count, &decl->type_bounds);
    }
    parser_consume(parser, TOK_LBRACE, "Expect '{' before enum body");
    uint32_t capacity = 4;
    decl->variants = ARENA_ALLOC_ARRAY(parser->arena, Param, capacity);
    while (!parser_check(parser, TOK_RBRACE) && !parser_check(parser, TOK_EOF)) {
        bool is_variant_pub = parser_match(parser, TOK_PUB);
        parser_consume(parser, TOK_IDENT, "Expect variant name");
        if (decl->variant_count >= capacity) {
            uint32_t old_capacity = capacity;
            capacity *= 2;
            decl->variants = ARENA_REALLOC_ARRAY(parser->arena, Param, decl->variants, old_capacity, capacity);
        }
        decl->variants[decl->variant_count].name = parser_dup_ident(parser);
        decl->variants[decl->variant_count].is_pub = is_variant_pub;
        if (parser_match(parser, TOK_LPAREN)) {
            if (parser_match(parser, TOK_RPAREN)) {
                decl->variants[decl->variant_count].type = il_type_unit();
            } else {
                uint32_t type_count = 0;
                uint32_t type_capacity = 4;
                const ILType ** types = ARENA_ALLOC_ARRAY(parser->arena, const ILType*, type_capacity);
                while (!parser_check(parser, TOK_RPAREN) && !parser_check(parser, TOK_EOF)) {
                    const ILType* t = parse_type(parser);
                    if (type_count >= type_capacity) {
                        uint32_t old_cap = type_capacity;
                        type_capacity *= 2;
                        types = ARENA_REALLOC_ARRAY(parser->arena, const ILType*, types, old_cap, type_capacity);
                    }
                    types[type_count++] = t;
                    if (!parser_match(parser, TOK_COMMA)) break;
                }
                parser_consume(parser, TOK_RPAREN, "Expect ')' after variant type list");
                if (type_count == 1) {
                    decl->variants[decl->variant_count].type = types[0];
                } else {
                    decl->variants[decl->variant_count].type = il_type_tuple(types, type_count);
                }
            }
        } else {
            decl->variants[decl->variant_count].type = il_type_unit();
        }
        if (parser_match(parser, TOK_ASSIGN)) {
            parser_consume(parser, TOK_INT, "Expect integer for variant tag");
            decl->variants[decl->variant_count].tag = parser->previous.as.int_val;
            decl->variants[decl->variant_count].has_tag = true;
        } else {
            decl->variants[decl->variant_count].tag = 0;
            decl->variants[decl->variant_count].has_tag = false;
        }
        decl->variant_count++;
        if (!parser_match(parser, TOK_COMMA)) break;
    }
    parser_consume(parser, TOK_RBRACE, "Expect '}' after enum body");
    decl->offset = start_tok.offset;
    decl->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
    return decl;
}

FunctionDecl* parse_function(Parser* parser, bool is_extern) {
    Token start_tok = parser->current;
    parser_consume(parser, TOK_FN, "Expect 'fn'");
    parser_consume(parser, TOK_IDENT, "Expect function name");
    FunctionDecl* fn = ARENA_ALLOC(parser->arena, FunctionDecl);
    if (!fn) return NULL;
    fn->file_path = parser->file_path;
    fn->is_extern = is_extern;
    fn->line = start_tok.line;
    fn->col = start_tok.col;
    fn->name = parser_dup_ident(parser);
    if (parser_check(parser, TOK_LT)) {
        fn->type_params = parse_type_params(parser, &fn->type_param_count, &fn->type_bounds);
    }
    parser_consume(parser, TOK_LPAREN, "Expect '('");
    if (!parser_check(parser, TOK_RPAREN)) {
        uint32_t capacity = 4;
        fn->params = ARENA_ALLOC_ARRAY(parser->arena, Param, capacity);
        if (fn->params) {
            while (!parser_check(parser, TOK_RPAREN) && !parser_check(parser, TOK_EOF)) {
                bool is_mut = parser_match(parser, TOK_MUT);
                if (parser_match(parser, TOK_ELLIPSIS)) {
                    fn->is_variadic = true;
                    break;
                }
                parser_consume(parser, TOK_IDENT, "Expect parameter name");
                char* param_name = NULL;
                if (parser->previous.kind == TOK_IDENT) {
                    param_name = parser_dup_ident(parser);
                } else {
                    param_name = parser_strdup(parser, "?");
                }
                if (!param_name) break;
                if (fn->param_count >= capacity) {
                    uint32_t old_capacity = capacity;
                    capacity *= 2;
                    Param* new_params = ARENA_REALLOC_ARRAY(parser->arena, Param, fn->params, old_capacity, capacity);
                    if (new_params) fn->params = new_params;
                }
                fn->params[fn->param_count].name = param_name;
                fn->params[fn->param_count].is_mutable = is_mut;
                if (strcmp(param_name, "self") == 0 && !parser_check(parser, TOK_COLON)) {
                    fn->params[fn->param_count].type = NULL;
                } else {
                    parser_consume(parser, TOK_COLON, "Expect ':' after parameter name");
                    fn->params[fn->param_count].type = parse_type(parser);
                }
                fn->param_count++;
                if (!parser_match(parser, TOK_COMMA)) break;
            }
        }
    }
    parser_consume(parser, TOK_RPAREN, "Expect ')'");
    if (parser_match(parser, TOK_ARROW)) {
        fn->return_type = parse_type(parser);
    }
    if (is_extern) {
        parser_consume(parser, TOK_SEMICOLON, "Expect ';' after extern function declaration");
        fn->body = NULL;
    } else if (parser_match(parser, TOK_SEMICOLON)) {
        fn->body = NULL;
    } else {
        fn->body = parse_block(parser);
    }
    fn->line = start_tok.line;
    fn->col = start_tok.col;
    fn->offset = start_tok.offset;
    fn->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
    return fn;
}

ImportDecl* parse_import(Parser* parser) {
    Token start_tok = parser->current;
    parser_consume(parser, TOK_IMPORT, "Expect 'import'");

    char* path = NULL;
    if (parser_match(parser, TOK_STRING)) {
        path = parser_strdup(parser, parser->previous.as.str.val);
    } else if (parser_match(parser, TOK_IDENT)) {
        path = parser_dup_ident(parser);
        if (path) {
            while (parser_match(parser, TOK_DOT)) {
                parser_consume(parser, TOK_IDENT, "Expect component in path");
                const char* next = (parser->previous.kind == TOK_IDENT) ? parser->previous.as.ident : "?";
                char* new_path = arena_alloc(parser->arena, strlen(path) + strlen(next) + 2, 1);
                if (!new_path) {
                    
                    return NULL;
                }
                sprintf(new_path, "%s.%s", path, next);
                
                path = new_path;
            }
        }
    } else {
        parser_error(parser, "Expect module path (identifier or string literal)");
    }

    char* alias = NULL;
    if (parser_match(parser, TOK_AS)) {
        parser_consume(parser, TOK_IDENT, "Expect alias after 'as'");
        if (parser->previous.kind == TOK_IDENT) {
            alias = parser_dup_ident(parser);
        } else {
            alias = parser_strdup(parser, "?");
        }
        if (!alias) {
            
            return NULL;
        }
    }
    parser_consume(parser, TOK_SEMICOLON, "Expect ';' after import");

    ImportDecl* decl = ARENA_ALLOC(parser->arena, ImportDecl);
    if (!decl) {
        
        
        return NULL;
    }
    decl->file_path = parser->file_path;
    decl->path = path;
    decl->alias = alias;
    if (alias) {
        parser_add_namespace(parser, alias);
    } else if (path) {
        // The file stem: `a/util.zrl` is `util`.
        const char* base = strrchr(path, '/');
        base = base ? base + 1 : path;
        size_t n = strlen(base);
        if (n > 4 && strcmp(base + n - 4, ".zrl") == 0) n -= 4;
        char* stem = arena_alloc(parser->arena, n + 1, 1);
        memcpy(stem, base, n);
        stem[n] = 0;
        parser_add_namespace(parser, stem);
    }
    decl->line = start_tok.line;
    decl->col = start_tok.col;
    decl->offset = start_tok.offset;
    decl->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
    return decl;
}

GlobalDecl* parse_global(Parser* parser, bool is_const) {
    Token start_tok = parser->current;
    parser_consume(parser, is_const ? TOK_CONST : TOK_STATIC, "Expect 'const' or 'static'");
    if (!is_const && parser_match(parser, TOK_MUT)) { /* allowed but ignored */ }
    parser_consume(parser, TOK_IDENT, "Expect global name");
    char* name = parser_dup_ident(parser);
    
    const ILType* type = NULL;
    if (parser_match(parser, TOK_COLON)) {
        type = parse_type(parser);
    }
    
    Expression* init = NULL;
    if (parser_match(parser, TOK_ASSIGN)) {
        init = parse_expression(parser);
    }
    
    parser_consume(parser, TOK_SEMICOLON, "Expect ';' after global declaration");
    
    GlobalDecl* decl = ARENA_ALLOC(parser->arena, GlobalDecl);
    if (decl) {
        decl->file_path = parser->file_path;
        decl->name = name;
        decl->type = type;
        decl->init = init;
        decl->is_const = is_const;
        decl->line = start_tok.line;
        decl->col = start_tok.col;
        decl->offset = start_tok.offset;
        decl->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
    } else {
        
        
        
    }
    return decl;
}

TypeAliasDecl* parse_type_alias(Parser* parser, bool is_pub) {
    parser_consume(parser, TOK_TYPE, "Expect 'type'");
    parser_consume(parser, TOK_IDENT, "Expect alias name");
    char* name = parser_dup_ident(parser);
    parser_consume(parser, TOK_ASSIGN, "Expect '='");
    const ILType* target = parse_type(parser);
    parser_consume(parser, TOK_SEMICOLON, "Expect ';' after type alias");
    
    TypeAliasDecl* decl = ARENA_ALLOC(parser->arena, TypeAliasDecl);
    if (decl) {
        decl->file_path = parser->file_path;
        decl->name = name;
        decl->target = target;
        decl->is_pub = is_pub;
    } else {
        
        
    }
    return decl;
}

TraitDecl* parse_trait(Parser* parser, bool is_pub) {
    Token start_tok = parser->current;
    parser_consume(parser, TOK_TRAIT, "Expect 'trait'");
    parser_consume(parser, TOK_IDENT, "Expect trait name");
    char* name = parser_dup_ident(parser);
    TraitDecl* trait = ARENA_ALLOC(parser->arena, TraitDecl);
    if (!trait) {  return NULL; }
    trait->file_path = parser->file_path;
    trait->line = start_tok.line;
    trait->col = start_tok.col;
    trait->offset = start_tok.offset;
    trait->name = name;
    trait->is_pub = is_pub;

    if (parser_check(parser, TOK_LT)) {
        trait->type_params = parse_type_params(parser, &trait->type_param_count, &trait->type_bounds);
    }

    parser_consume(parser, TOK_LBRACE, "Expect '{' before trait body");
    uint32_t capacity = 4;
    trait->methods = ARENA_ALLOC_ARRAY(parser->arena, FunctionDecl*, capacity);
    if (!trait->methods) {   return NULL; }

    while (!parser_check(parser, TOK_RBRACE) && !parser_check(parser, TOK_EOF)) {
        bool is_must_use = false;
        while (parser_match(parser, TOK_HASH) || parser_match(parser, TOK_UNSAFE)) {
            if (parser->previous.kind == TOK_HASH) {
                parse_attribute(parser, &is_must_use);
            }
        }

        if (parser_check(parser, TOK_FN)) {
            FunctionDecl* fn = parse_function(parser, false);
            if (fn) {
                fn->is_must_use = is_must_use;
                if (trait->method_count >= capacity) {
                    uint32_t old_capacity = capacity;
                    capacity *= 2;
                    trait->methods = ARENA_REALLOC_ARRAY(parser->arena, FunctionDecl*, trait->methods, old_capacity, capacity);
                }
                trait->methods[trait->method_count++] = fn;
            }
        } else {
            parser_error(parser, "Only functions are allowed in trait blocks");
            parser_advance(parser);
        }
    }
    parser_consume(parser, TOK_RBRACE, "Expect '}' after trait block");
    trait->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
    return trait;
}

ImplDecl* parse_impl(Parser* parser) {
    Token start_tok = parser->current;
    parser_consume(parser, TOK_IMPL, "Expect \"impl\"");
    
    char** type_params = NULL;
    uint32_t type_param_count = 0;
    if (parser_check(parser, TOK_LT)) {
        type_params = parse_type_params(parser, &type_param_count, NULL);
    }

    const ILType* type1 = parse_type(parser);
    if (!type1) {
        if (type_params) {
            (void)0;
            
        }
        return NULL;
    }
    char* name1 = impl_type_to_name(parser, type1);

    char* trait_name = NULL;
    const ILType* trait_type = NULL;
    char* target_name = NULL;
    const ILType* target_type = NULL;

    if (parser_match(parser, TOK_FOR)) {
        trait_name = name1;
        trait_type = type1;
        target_type = parse_type(parser);
        if (!target_type) { 
             
             
            if (type_params) {
                (void)0;
                
            }
            return NULL; 
        }
        target_name = impl_type_to_name(parser, target_type);
        
    } else {
        target_type = type1;
        target_name = name1;
    }
    
    parser_consume(parser, TOK_LBRACE, "Expect \"{\" after impl block");

    ImplDecl* impl = ARENA_ALLOC(parser->arena, ImplDecl);
    if (!impl) { 
        
        
        
        if (type_params) {
            (void)0;
            
        }
        return NULL; 
    }
    impl->file_path = parser->file_path;
    impl->line = start_tok.line;
    impl->col = start_tok.col;
    impl->offset = start_tok.offset;
    impl->trait_name = trait_name;
    impl->trait_type = trait_type;
    impl->target_name = target_name;
    impl->target_type = target_type;
    impl->type_params = type_params;
    impl->type_param_count = type_param_count;
    uint32_t m_cap = 4;
    impl->methods = ARENA_ALLOC_ARRAY(parser->arena, FunctionDecl*, m_cap);
    impl->il_methods = ARENA_ALLOC_ARRAY(parser->arena, void*, m_cap);
    
    uint32_t g_cap = 4;
    impl->globals = ARENA_ALLOC_ARRAY(parser->arena, GlobalDecl*, g_cap);
    
    uint32_t a_cap = 4;
    impl->type_aliases = ARENA_ALLOC_ARRAY(parser->arena, TypeAliasDecl*, a_cap);

    if (!impl->methods || !impl->il_methods || !impl->globals || !impl->type_aliases) { 
        (void)0;
        (void)0;
        (void)0;
        (void)0;
        
        (void)0;
        
         
        return NULL; 
    }

    while (!parser_check(parser, TOK_RBRACE) && !parser_check(parser, TOK_EOF)) {
        bool is_pub = false;
        bool is_must_use = false;

        while (parser_match(parser, TOK_PUB) || parser_match(parser, TOK_HASH) || parser_match(parser, TOK_UNSAFE)) {
            if (parser->previous.kind == TOK_PUB) {
                is_pub = true;
            } else if (parser->previous.kind == TOK_HASH) {
                parse_attribute(parser, &is_must_use);
            }
        }

        if (parser_check(parser, TOK_FN)) {
            FunctionDecl* fn = parse_function(parser, false);
            if (fn) {
                fn->is_pub = is_pub;
                fn->is_must_use = is_must_use;
                if (impl->method_count >= m_cap) {
                    uint32_t old_m_cap = m_cap;
                    m_cap *= 2;
                    impl->methods = ARENA_REALLOC_ARRAY(parser->arena, FunctionDecl*, impl->methods, old_m_cap, m_cap);
                    impl->il_methods = ARENA_REALLOC_ARRAY(parser->arena, void*, impl->il_methods, old_m_cap, m_cap);
                }
                impl->il_methods[impl->method_count] = NULL;
                impl->methods[impl->method_count++] = fn;
            }
        } else if (parser_check(parser, TOK_CONST) || parser_check(parser, TOK_STATIC)) {
            bool is_const = parser_check(parser, TOK_CONST);
            GlobalDecl* g = parse_global(parser, is_const);
            if (g) {
                g->is_pub = is_pub;
                if (impl->global_count >= g_cap) {
                    uint32_t old_g_cap = g_cap;
                    g_cap *= 2;
                    impl->globals = ARENA_REALLOC_ARRAY(parser->arena, GlobalDecl*, impl->globals, old_g_cap, g_cap);
                }
                impl->globals[impl->global_count++] = g;
            }
        } else if (parser_check(parser, TOK_TYPE)) {
            TypeAliasDecl* alias = parse_type_alias(parser, is_pub);
            if (alias) {
                if (impl->type_alias_count >= a_cap) {
                    uint32_t old_a_cap = a_cap;
                    a_cap *= 2;
                    impl->type_aliases = ARENA_REALLOC_ARRAY(parser->arena, TypeAliasDecl*, impl->type_aliases, old_a_cap, a_cap);
                }
                impl->type_aliases[impl->type_alias_count++] = alias;
            }
        } else {
            parser_error(parser, "Only functions, constants, and type aliases are allowed in impl blocks");
            parser_synchronize(parser);
        }
    }
    parser_consume(parser, TOK_RBRACE, "Expect '}' after impl block");
    impl->length = (uint32_t)(parser->previous.offset + parser->previous.length - start_tok.offset);
    return impl;
}

/* #[must_use] sets *is_must_use. #[borrows(a, b)], #[stores(..)] and #[fresh] are
 * accepted and ignored: they state which parameters a returned reference points into,
 * where a reference parameter is stored, or that a raw pointer result is a new mapping,
 * which only the safety checker of the self-hosted compiler uses (stage0-C is not that
 * checker, language_subset.md §1.6).
 * Anything else is an error. */
void parse_attribute(Parser* parser, bool* is_must_use) {
    parser_consume(parser, TOK_LBRACKET, "Expect '[' after '#'");
    parser_consume(parser, TOK_IDENT, "Expect attribute name");
    if (parser->previous.kind == TOK_IDENT && strcmp(parser->previous.as.ident, "must_use") == 0) {
        *is_must_use = true;
    } else if (parser->previous.kind == TOK_IDENT && strcmp(parser->previous.as.ident, "borrows") == 0) {
        parser_consume(parser, TOK_LPAREN, "Expect '(' after borrows");
        while (!parser_check(parser, TOK_RPAREN) && !parser_check(parser, TOK_EOF)) {
            parser_consume(parser, TOK_IDENT, "Expect a parameter name in #[borrows(...)]");
            if (!parser_match(parser, TOK_COMMA)) break;
        }
        parser_consume(parser, TOK_RPAREN, "Expect ')' after #[borrows(...");
    } else if (parser->previous.kind == TOK_IDENT && strcmp(parser->previous.as.ident, "stores") == 0) {
        parser_consume(parser, TOK_LPAREN, "Expect '(' after stores");
        while (!parser_check(parser, TOK_RPAREN) && !parser_check(parser, TOK_EOF)) {
            parser_advance(parser);
        }
        parser_consume(parser, TOK_RPAREN, "Expect ')' after #[stores(...");
    } else if (parser->previous.kind == TOK_IDENT && strcmp(parser->previous.as.ident, "fresh") == 0) {
        (void)0;
    } else if (parser->previous.kind == TOK_IDENT) {
        char buf[128];
        snprintf(buf, sizeof(buf), "Unknown attribute '%s'", parser->previous.as.ident);
        parser_error(parser, buf);
    }
    parser_consume(parser, TOK_RBRACKET, "Expect ']' after attribute");
}
