#ifndef SURFACE_SCOPE_H
#define SURFACE_SCOPE_H

#include "surface_ast.h"
#include "il_instr.h"
#include "il_cfg.h"

typedef struct Symbol {
    char* name;
    ILValue value;
    bool is_lvalue;
    struct Symbol* next;
} Symbol;

typedef struct DeferNode {
    const BlockExpr* block;
    struct DeferNode* next;
} DeferNode;

typedef struct Scope {
    Symbol* symbols;
    DeferNode* defers;
    struct Scope* parent;
    ILFunction* owner_func;
    uint32_t temporary_start;
} Scope;

Scope* scope_create(Scope* parent, ILFunction* owner_func);
void scope_free(Scope* scope);

void symbol_add(Scope* scope, const char* name, ILValue value, bool is_lvalue);
Symbol* symbol_lookup(Scope* scope, const char* name);

#endif
