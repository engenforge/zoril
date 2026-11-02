#include <stdlib.h>
#include <string.h>
#include "surface_scope.h"

Scope* scope_create(Scope* parent, ILFunction* owner_func) {
    Scope* scope = calloc(1, sizeof(Scope));
    if (scope) {
        scope->parent = parent;
        scope->owner_func = owner_func;
    }
    return scope;
}

void scope_free(Scope* scope) {
    if (!scope) return;
    
    Symbol* sym = scope->symbols;
    while (sym) {
        Symbol* next = sym->next;
        free(sym->name);
        free(sym);
        sym = next;
    }
    
    DeferNode* defer = scope->defers;
    while (defer) {
        DeferNode* next = defer->next;
        free(defer);
        defer = next;
    }
    
    free(scope);
}

void symbol_add(Scope* scope, const char* name, ILValue value, bool is_lvalue) {
    if (!scope) return;
    Symbol* sym = calloc(1, sizeof(Symbol));
    if (sym) {
        sym->name = name ? strdup(name) : NULL;
        sym->value = (ILValue){ .id = value.id, .type = value.type };
        sym->is_lvalue = is_lvalue;
        sym->next = scope->symbols;
        scope->symbols = sym;
    }
}

Symbol* symbol_lookup(Scope* scope, const char* name) {
    while (scope) {
        Symbol* sym = scope->symbols;
        while (sym) {
            if (sym->name && strcmp(sym->name, name) == 0) {
                return sym;
            }
            sym = sym->next;
        }
        scope = scope->parent;
    }
    return NULL;
}
