#include "il_type.h"
#include "il_cfg.h"
#include "string_table.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdio.h>
#include <assert.h>

ILContext* global_il_ctx = NULL;

void il_ctx_init(ILContext* ctx) {
    arena_init(&ctx->arena, 1024 * 1024);
    memset(ctx->buckets, 0, sizeof(ctx->buckets));
    ctx->type_count = 0;
    global_il_ctx = ctx;
}

void il_ctx_destroy(ILContext* ctx) {
    arena_destroy(&ctx->arena);
    if (global_il_ctx == ctx) global_il_ctx = NULL;
}

static uint32_t hash_uint32(uint32_t h, uint32_t val) {
    return h * 33 + val;
}

static uint32_t type_hash(const ILType* t) {
    if (!t) return 0;
    uint32_t h = 5381;
    h = hash_uint32(h, (uint32_t)t->kind);
    switch (t->kind) {
        case IL_TY_UNIT: case IL_TY_NEVER: case IL_TY_BOOL: case IL_TY_CHAR:
        case IL_TY_U8: case IL_TY_U16: case IL_TY_U32: case IL_TY_U64: case IL_TY_USIZE:
        case IL_TY_I8: case IL_TY_I16: case IL_TY_I32: case IL_TY_I64: case IL_TY_ISIZE:
        case IL_TY_F32: case IL_TY_F64:
        case IL_TY_ASYNC_CONTEXT:
            return h;
        case IL_TY_PTR:
            h = hash_uint32(h, type_hash(t->as.ptr.pointee));
            h = hash_uint32(h, t->as.ptr.region_id);
            h = hash_uint32(h, t->as.ptr.is_mut ? 1 : 0);
            break;
        case IL_TY_BOX:
            h = hash_uint32(h, type_hash(t->as.box.pointee));
            h = hash_uint32(h, t->as.box.region_id);
            h = hash_uint32(h, t->as.box.is_mut ? 1 : 0);
            break;
        case IL_TY_SLICE:
            h = hash_uint32(h, type_hash(t->as.slice.element));
            h = hash_uint32(h, t->as.slice.region_id);
            h = hash_uint32(h, t->as.slice.is_mut ? 1 : 0);
            break;
        case IL_TY_ARRAY:
            h = hash_uint32(h, type_hash(t->as.array.element));
            h = hash_uint32(h, (uint32_t)t->as.array.length);
            break;
        case IL_TY_STRUCT:
        case IL_TY_SUM:
            h = hash_uint32(h, t->as.struct_sum.type_def_id);
            if (t->as.struct_sum.name) {
                for (const char* p = t->as.struct_sum.name; *p; p++) h = hash_uint32(h, (uint32_t)*p);
            }
            for (uint32_t i = 0; i < t->as.struct_sum.type_arg_count; i++) {
                h = hash_uint32(h, type_hash(t->as.struct_sum.type_args[i]));
            }
            break;
        case IL_TY_FN:
            h = hash_uint32(h, type_hash(t->as.function.return_type));
            h = hash_uint32(h, t->as.function.is_variadic ? 1 : 0);
            for (uint32_t i = 0; i < t->as.function.param_count; i++) {
                h = hash_uint32(h, type_hash(t->as.function.param_types[i]));
            }
            break;
        case IL_TY_TUPLE:
            for (uint32_t i = 0; i < t->as.tuple.count; i++) {
                h = hash_uint32(h, type_hash(t->as.tuple.elements[i]));
            }
            break;
        case IL_TY_VAR:
            if (t->as.var.name) {
                for (const char* p = t->as.var.name; *p; p++) h = hash_uint32(h, (uint32_t)*p);
            }
            break;
        case IL_TY_FD:
            h = hash_uint32(h, (uint32_t)t->as.fd.cap);
            break;
        default: break;
    }
    return h;
}

bool il_type_structurally_eq(const ILType* a, const ILType* b) {
    if (a == b) return true;
    if (a == NULL || b == NULL) return false;
    if (a->kind != b->kind && !((a->kind == IL_TY_STRUCT || a->kind == IL_TY_SUM) && (b->kind == IL_TY_STRUCT || b->kind == IL_TY_SUM) && a->as.struct_sum.type_def_id != 0 && a->as.struct_sum.type_def_id == b->as.struct_sum.type_def_id)) return false;
    switch (a->kind) {
        case IL_TY_PTR: return a->as.ptr.region_id == b->as.ptr.region_id && a->as.ptr.is_mut == b->as.ptr.is_mut && il_type_structurally_eq(a->as.ptr.pointee, b->as.ptr.pointee);
        case IL_TY_BOX: return a->as.box.region_id == b->as.box.region_id && a->as.box.is_mut == b->as.box.is_mut && il_type_structurally_eq(a->as.box.pointee, b->as.box.pointee);
        case IL_TY_SLICE: return a->as.slice.is_mut == b->as.slice.is_mut && a->as.slice.region_id == b->as.slice.region_id && il_type_structurally_eq(a->as.slice.element, b->as.slice.element);
        case IL_TY_ARRAY: return a->as.array.length == b->as.array.length && il_type_structurally_eq(a->as.array.element, b->as.array.element);
        case IL_TY_SUM:
        case IL_TY_STRUCT:
            if (a->as.struct_sum.type_def_id != b->as.struct_sum.type_def_id) return false;
            if (a->as.struct_sum.type_arg_count != b->as.struct_sum.type_arg_count) return false;
            for (uint32_t i = 0; i < a->as.struct_sum.type_arg_count; i++) if (!il_type_structurally_eq(a->as.struct_sum.type_args[i], b->as.struct_sum.type_args[i])) return false;
            if (a->as.struct_sum.name && b->as.struct_sum.name) return strcmp(a->as.struct_sum.name, b->as.struct_sum.name) == 0;
            return a->as.struct_sum.name == b->as.struct_sum.name;
        case IL_TY_VAR: if (a->as.var.name && b->as.var.name) return strcmp(a->as.var.name, b->as.var.name) == 0; return a->as.var.name == b->as.var.name;
        case IL_TY_FD: return a->as.fd.cap == b->as.fd.cap;
        case IL_TY_ASYNC_CONTEXT: return true;
        case IL_TY_FN:
            if (a->as.function.is_variadic != b->as.function.is_variadic) return false;
            if (!il_type_structurally_eq(a->as.function.return_type, b->as.function.return_type)) return false;
            if (a->as.function.param_count != b->as.function.param_count) return false;
            for (uint32_t i = 0; i < a->as.function.param_count; i++) if (!il_type_structurally_eq(a->as.function.param_types[i], b->as.function.param_types[i])) return false;
            return true;
        case IL_TY_TUPLE:
            if (a->as.tuple.count != b->as.tuple.count) return false;
            for (uint32_t i = 0; i < a->as.tuple.count; i++) if (!il_type_structurally_eq(a->as.tuple.elements[i], b->as.tuple.elements[i])) return false;
            return true;
        default: return true;
    }
}

static uint64_t next_type_serial = 1;

static ILType* fallback_buckets[1024];

static const ILType* type_intern(const ILType* t) {
    uint32_t h = type_hash(t);
    uint32_t idx = h % 1024;
    
    if (global_il_ctx) {
        const ILType* entry = global_il_ctx->buckets[idx];
        while (entry) {
            if (il_type_structurally_eq(entry, t)) return entry;
            entry = entry->next_intern;
        }
    } else {
        const ILType* entry = fallback_buckets[idx];
        while (entry) {
            if (il_type_structurally_eq(entry, t)) return entry;
            entry = entry->next_intern;
        }
    }
    
    // Not found, create new instance
    ILType* interned = NULL;
    if (global_il_ctx) {
        interned = arena_alloc(&global_il_ctx->arena, sizeof(ILType), _Alignof(ILType));
    } else {
        interned = calloc(1, sizeof(ILType));
    }
    
    if (!interned) return NULL;
    memcpy(interned, t, sizeof(ILType));
    interned->serial = next_type_serial++;
    
    // Deep-copy owned fields
    if (t->kind == IL_TY_STRUCT || t->kind == IL_TY_SUM) {
        if (t->as.struct_sum.name) {
            if (global_il_ctx) {
                size_t nlen = strlen(t->as.struct_sum.name);
                char* nname = arena_alloc(&global_il_ctx->arena, nlen + 1, 1);
                memcpy(nname, t->as.struct_sum.name, nlen + 1);
                interned->as.struct_sum.name = nname;
            } else {
                interned->as.struct_sum.name = strdup(t->as.struct_sum.name);
            }
        }
        if (t->as.struct_sum.type_arg_count > 0) {
            size_t sz = sizeof(const ILType*) * t->as.struct_sum.type_arg_count;
            if (global_il_ctx) {
                const ILType** cp = arena_alloc(&global_il_ctx->arena, sz, _Alignof(const ILType*));
                memcpy((void*)cp, t->as.struct_sum.type_args, sz);
                interned->as.struct_sum.type_args = cp;
            } else {
                const ILType** cp = malloc(sz);
                if (cp) { memcpy(cp, t->as.struct_sum.type_args, sz); interned->as.struct_sum.type_args = cp; }
            }
        }
    } else if (t->kind == IL_TY_FN) {
        if (t->as.function.param_count > 0) {
            size_t sz = sizeof(const ILType*) * t->as.function.param_count;
            if (global_il_ctx) {
                const ILType** cp = arena_alloc(&global_il_ctx->arena, sz, _Alignof(const ILType*));
                memcpy((void*)cp, t->as.function.param_types, sz);
                interned->as.function.param_types = cp;
            } else {
                const ILType** cp = malloc(sz);
                if (cp) { memcpy(cp, t->as.function.param_types, sz); interned->as.function.param_types = cp; }
            }
        }
    } else if (t->kind == IL_TY_TUPLE) {
        if (t->as.tuple.count > 0) {
            size_t sz = sizeof(const ILType*) * t->as.tuple.count;
            if (global_il_ctx) {
                const ILType** cp = arena_alloc(&global_il_ctx->arena, sz, _Alignof(const ILType*));
                memcpy((void*)cp, t->as.tuple.elements, sz);
                interned->as.tuple.elements = cp;
            } else {
                const ILType** cp = malloc(sz);
                if (cp) { memcpy(cp, t->as.tuple.elements, sz); interned->as.tuple.elements = cp; }
            }
        }
    } else if (t->kind == IL_TY_VAR) {
        if (t->as.var.name) {
            if (global_il_ctx) {
                size_t nlen = strlen(t->as.var.name);
                char* nname = arena_alloc(&global_il_ctx->arena, nlen + 1, 1);
                memcpy(nname, t->as.var.name, nlen + 1);
                interned->as.var.name = nname;
            } else {
                interned->as.var.name = strdup(t->as.var.name);
            }
        }
    }

    if (global_il_ctx) {
        interned->next_intern = global_il_ctx->buckets[idx];
        global_il_ctx->buckets[idx] = interned;
        global_il_ctx->type_count++;
    } else {
        interned->next_intern = fallback_buckets[idx];
        fallback_buckets[idx] = interned;
    }
    
    return interned;
}

bool is_numeric_type(const ILType* t) {
    if (!t) return false;
    switch (t->kind) {
        case IL_TY_U8: case IL_TY_U16: case IL_TY_U32: case IL_TY_U64: case IL_TY_USIZE:
        case IL_TY_I8: case IL_TY_I16: case IL_TY_I32: case IL_TY_I64: case IL_TY_ISIZE:
        case IL_TY_F32: case IL_TY_F64:
        case IL_TY_BOOL:
            return true;
        default:
            return false;
    }
}

bool is_integral_type(const ILType* t) {
    if (!t) return false;
    switch (t->kind) {
        case IL_TY_U8: case IL_TY_U16: case IL_TY_U32: case IL_TY_U64: case IL_TY_USIZE:
        case IL_TY_I8: case IL_TY_I16: case IL_TY_I32: case IL_TY_I64: case IL_TY_ISIZE:
        case IL_TY_FD: case IL_TY_ASYNC_CONTEXT:
            return true;
        default:
            return false;
    }
}

bool is_integer_type(const ILType* t) {
    return is_integral_type(t);
}

bool is_float_type(const ILType* t) {
    if (!t) return false;
    return t->kind == IL_TY_F32 || t->kind == IL_TY_F64;
}

bool is_unsigned_type(const ILType* t) {
    if (!t) return false;
    switch (t->kind) {
        case IL_TY_U8: case IL_TY_U16: case IL_TY_U32: case IL_TY_U64: case IL_TY_USIZE:
            return true;
        default:
            return false;
    }
}

bool is_signed_type(const ILType* t) {
    if (!t) return false;
    switch (t->kind) {
        case IL_TY_I8: case IL_TY_I16: case IL_TY_I32: case IL_TY_I64: case IL_TY_ISIZE:
            return true;
        default:
            return false;
    }
}

int numeric_type_rank(ILTypeKind kind) {
    switch (kind) {
        case IL_TY_BOOL: return 1;
        case IL_TY_U8:  case IL_TY_I8:  return 2;
        case IL_TY_U16: case IL_TY_I16: return 3;
        case IL_TY_U32: case IL_TY_I32: case IL_TY_F32: return 4;
        case IL_TY_U64: case IL_TY_I64: case IL_TY_F64: case IL_TY_USIZE: case IL_TY_ISIZE: return 5;
        default: return 0;
    }
}

const char* il_type_kind_str(ILTypeKind kind) {
    switch (kind) {
        case IL_TY_UNIT: return "unit";
        case IL_TY_BOOL: return "bool";
        case IL_TY_U8:   return "u8";
        case IL_TY_U16:  return "u16";
        case IL_TY_U32:  return "u32";
        case IL_TY_U64:  return "u64";
        case IL_TY_USIZE: return "usize";
        case IL_TY_ISIZE: return "isize";
        case IL_TY_I8:   return "i8";
        case IL_TY_I16:  return "i16";
        case IL_TY_I32:  return "i32";
        case IL_TY_I64:  return "i64";
        case IL_TY_F32:  return "f32";
        case IL_TY_F64:  return "f64";
        case IL_TY_PTR:  return "ptr";
        case IL_TY_BOX:  return "box";
        case IL_TY_SLICE: return "slice";
        case IL_TY_ARRAY: return "array";
        case IL_TY_SUM:    return "enum";
        case IL_TY_STRUCT: return "struct";
        case IL_TY_VAR:    return "type_var";
        case IL_TY_GENERIC_INSTANCE: return "generic_instance";
        case IL_TY_FD:      return "fd";
        case IL_TY_ASYNC_CONTEXT: return "async_context";
        case IL_TY_FN:      return "fn";
        case IL_TY_TUPLE:   return "tuple";
        case IL_TY_NEVER:   return "never";
        default:            return "unknown";
    }
}

static bool il_type_is_numeric_assignable(const ILType* source, const ILType* target) {
    if (source->kind == target->kind) return true;
    if (is_integral_type(source) && is_integral_type(target)) {
        if (numeric_type_rank(source->kind) == numeric_type_rank(target->kind)) return true;
        return numeric_type_rank(target->kind) >= numeric_type_rank(source->kind);
    }
    if (is_float_type(source) && is_float_type(target)) {
        return numeric_type_rank(target->kind) >= numeric_type_rank(source->kind);
    }
    return false;
}

bool is_pointer_type(const void* mod, const ILType* t) {
    if (!t) return false;
    if (t->kind == IL_TY_PTR || t->kind == IL_TY_BOX || t->kind == IL_TY_SLICE) return true;
    if (t->kind == IL_TY_STRUCT || t->kind == IL_TY_SUM) {
        const char* name = t->as.struct_sum.name;
        if (!name && mod && t->as.struct_sum.type_def_id != 0) {
            const ILTypeDef* def = il_mod_get_type_def(mod, t->as.struct_sum.type_def_id);
            if (def) name = def->name;
        }
        if (name) {
            if (strncmp(name, "Ptr_", 4) == 0 || strncmp(name, "Box_", 4) == 0 || strncmp(name, "PtrMut_", 7) == 0 || strncmp(name, "BoxMut_", 7) == 0) {
                return true;
            }
        }
    }
    return false;
}

void il_type_print(const ILType* type, char* buffer, size_t max_len) {
    if (!type) { snprintf(buffer, max_len, "unknown"); return; }
    switch (type->kind) {
        case IL_TY_UNIT: snprintf(buffer, max_len, "unit"); break;
        case IL_TY_BOOL: snprintf(buffer, max_len, "bool"); break;
        case IL_TY_U8:   snprintf(buffer, max_len, "u8"); break;
        case IL_TY_U16:  snprintf(buffer, max_len, "u16"); break;
        case IL_TY_U32:  snprintf(buffer, max_len, "u32"); break;
        case IL_TY_U64:  snprintf(buffer, max_len, "u64"); break;
        case IL_TY_USIZE: snprintf(buffer, max_len, "usize"); break;
        case IL_TY_I8:   snprintf(buffer, max_len, "i8"); break;
        case IL_TY_I16:  snprintf(buffer, max_len, "i16"); break;
        case IL_TY_I32:  snprintf(buffer, max_len, "i32"); break;
        case IL_TY_I64:  snprintf(buffer, max_len, "i64"); break;
        case IL_TY_ISIZE: snprintf(buffer, max_len, "isize"); break;
        case IL_TY_F32:  snprintf(buffer, max_len, "f32"); break;
        case IL_TY_F64:  snprintf(buffer, max_len, "f64"); break;
        case IL_TY_PTR: {
            char p_buf[128];
            il_type_print(type->as.ptr.pointee, p_buf, sizeof(p_buf));
            snprintf(buffer, max_len, "Ptr<%s, %u>", p_buf, type->as.ptr.region_id);
            break;
        }
        case IL_TY_BOX: {
            char p_buf[128];
            il_type_print(type->as.box.pointee, p_buf, sizeof(p_buf));
            snprintf(buffer, max_len, "Box<%s, %u>", p_buf, type->as.box.region_id);
            break;
        }
        case IL_TY_SLICE: {
            char p_buf[128];
            il_type_print(type->as.slice.element, p_buf, sizeof(p_buf));
            snprintf(buffer, max_len, "Slice<%s, %u>", p_buf, type->as.slice.region_id);
            break;
        }
        case IL_TY_ARRAY: {
            char p_buf[128];
            il_type_print(type->as.array.element, p_buf, sizeof(p_buf));
            snprintf(buffer, max_len, "[%s; %lu]", p_buf, (unsigned long)type->as.array.length);
            break;
        }
        case IL_TY_STRUCT:
        case IL_TY_SUM:
            snprintf(buffer, max_len, "%s", type->as.struct_sum.name ? type->as.struct_sum.name : "anonymous_struct");
            break;
        case IL_TY_VAR:
            snprintf(buffer, max_len, "%s", type->as.var.name ? type->as.var.name : "T");
            break;
        case IL_TY_FD: snprintf(buffer, max_len, "fd"); break;
        case IL_TY_ASYNC_CONTEXT: snprintf(buffer, max_len, "async_context"); break;
        case IL_TY_FN: snprintf(buffer, max_len, "fn(...)"); break;
        case IL_TY_TUPLE: snprintf(buffer, max_len, "(...)"); break;
        case IL_TY_NEVER: snprintf(buffer, max_len, "never"); break;
        default: snprintf(buffer, max_len, "type_%d", type->kind); break;
    }
}

uint32_t il_type_get_indirection_level(const ILType* t) {
    uint32_t level = 0;
    while (t && (t->kind == IL_TY_PTR || t->kind == IL_TY_BOX || t->kind == IL_TY_SLICE)) {
        level++;
        if (t->kind == IL_TY_PTR) t = t->as.ptr.pointee;
        else if (t->kind == IL_TY_BOX) t = t->as.box.pointee;
        else t = t->as.slice.element;
    }
    return level;
}

typedef struct {
    char* buffer;
    size_t cap;
    size_t len;
} TypeMangler;

static void mangler_ensure(TypeMangler* m, size_t needed) {
    if (m->len + needed >= m->cap) {
        size_t ncap = m->cap * 2;
        while (m->len + needed >= ncap) ncap *= 2;
        char* nbuf = realloc(m->buffer, ncap);
        if (!nbuf) abort();
        m->buffer = nbuf;
        m->cap = ncap;
    }
}

static void mangler_append(TypeMangler* m, const char* str) {
    if (!str) return;
    size_t slen = strlen(str);
    mangler_ensure(m, slen + 1);
    memcpy(m->buffer + m->len, str, slen);
    m->len += slen;
    m->buffer[m->len] = '\0';
}

static void mangle_type_rec(const ILType* type, TypeMangler* m, int depth) {
    if (!type) { mangler_append(m, "unit"); return; }
    if (depth > 500) { mangler_append(m, "too_deep"); return; }

    switch (type->kind) {
        case IL_TY_UNIT: mangler_append(m, "unit"); break;
        case IL_TY_BOOL: mangler_append(m, "bool"); break;
        case IL_TY_U8:   mangler_append(m, "u8"); break;
        case IL_TY_U16:  mangler_append(m, "u16"); break;
        case IL_TY_U32:  mangler_append(m, "u32"); break;
        case IL_TY_U64:  mangler_append(m, "u64"); break;
        case IL_TY_USIZE: mangler_append(m, "usize"); break;
        case IL_TY_I8:   mangler_append(m, "i8"); break;
        case IL_TY_I16:  mangler_append(m, "i16"); break;
        case IL_TY_I32:  mangler_append(m, "i32"); break;
        case IL_TY_I64:  mangler_append(m, "i64"); break;
        case IL_TY_ISIZE: mangler_append(m, "isize"); break;
        case IL_TY_F32:  mangler_append(m, "f32"); break;
        case IL_TY_F64:  mangler_append(m, "f64"); break;
        case IL_TY_FD:   mangler_append(m, "fd"); break;
        case IL_TY_ASYNC_CONTEXT: mangler_append(m, "async"); break;
        case IL_TY_PTR:
            mangler_append(m, "p");
            mangle_type_rec(type->as.ptr.pointee, m, depth + 1);
            break;
        case IL_TY_BOX:
            mangler_append(m, "b");
            mangle_type_rec(type->as.box.pointee, m, depth + 1);
            break;
        case IL_TY_SLICE:
            mangler_append(m, "s");
            mangle_type_rec(type->as.slice.element, m, depth + 1);
            break;
        case IL_TY_ARRAY: {
            char buf[32];
            snprintf(buf, sizeof(buf), "a%llu", (unsigned long long)type->as.array.length);
            mangler_append(m, buf);
            mangle_type_rec(type->as.array.element, m, depth + 1);
            break;
        }
        case IL_TY_TUPLE:
            mangler_append(m, "t");
            for (uint32_t i = 0; i < type->as.tuple.count; i++) {
                mangle_type_rec(type->as.tuple.elements[i], m, depth + 1);
            }
            break;
        case IL_TY_FN:
            mangler_append(m, "fn");
            mangle_type_rec(type->as.function.return_type, m, depth + 1);
            for (uint32_t i = 0; i < type->as.function.param_count; i++) {
                mangle_type_rec(type->as.function.param_types[i], m, depth + 1);
            }
            break;
        case IL_TY_STRUCT:
        case IL_TY_SUM: {
            if (!type->as.struct_sum.name) {
                mangler_append(m, "anon");
                break;
            }
            mangler_append(m, type->as.struct_sum.name);
            // Generics are handled during lowering by creating new TypeDefs with 
            // mangled names (Base_Arg1_Arg2), so we usually just emit the name here.
            // However, for unlowered generic instances (type_def_id == 0), we mangle args.
            if (type->as.struct_sum.type_arg_count > 0 && type->as.struct_sum.type_def_id == 0) {
                for (uint32_t i = 0; i < type->as.struct_sum.type_arg_count; i++) {
                    mangler_append(m, "_");
                    mangle_type_rec(type->as.struct_sum.type_args[i], m, depth + 1);
                }
            }
            break;
        }
        case IL_TY_NEVER: mangler_append(m, "never"); break;
        default: mangler_append(m, "unknown"); break;
    }
}

char* mangle_type(const ILType* type) {
    TypeMangler m;
    m.cap = 256;
    m.buffer = malloc(m.cap);
    if (!m.buffer) return strdup("oom");
    m.len = 0;
    m.buffer[0] = '\0';
    mangle_type_rec(type, &m, 0);
    return m.buffer;
}

char* mangle_generic_name(const char* base_name, uint32_t count, const ILType** args) {
    TypeMangler m;
    m.cap = 512;
    m.buffer = malloc(m.cap);
    if (!m.buffer) return strdup("oom");
    m.len = 0;
    m.buffer[0] = '\0';
    mangler_append(&m, base_name);
    for (uint32_t i = 0; i < count; i++) {
        mangler_append(&m, "_");
        mangle_type_rec(args[i], &m, 0);
    }
    return m.buffer;
}

const ILType* il_type_bool(void) { ILType t = { .kind = IL_TY_BOOL }; return type_intern(&t); }
const ILType* il_type_char(void) { ILType t = { .kind = IL_TY_CHAR }; return type_intern(&t); }
const ILType* il_type_u8(void) { ILType t = { .kind = IL_TY_U8 }; return type_intern(&t); }
const ILType* il_type_u16(void) { ILType t = { .kind = IL_TY_U16 }; return type_intern(&t); }
const ILType* il_type_u32(void) { ILType t = { .kind = IL_TY_U32 }; return type_intern(&t); }
const ILType* il_type_u64(void) { ILType t = { .kind = IL_TY_U64 }; return type_intern(&t); }
const ILType* il_type_usize(void) { ILType t = { .kind = IL_TY_USIZE }; return type_intern(&t); }
const ILType* il_type_isize(void) { ILType t = { .kind = IL_TY_ISIZE }; return type_intern(&t); }
const ILType* il_type_i8(void) { ILType t = { .kind = IL_TY_I8 }; return type_intern(&t); }
const ILType* il_type_i16(void) { ILType t = { .kind = IL_TY_I16 }; return type_intern(&t); }
const ILType* il_type_i32(void) { ILType t = { .kind = IL_TY_I32 }; return type_intern(&t); }
const ILType* il_type_i64(void) { ILType t = { .kind = IL_TY_I64 }; return type_intern(&t); }
const ILType* il_type_f32(void) { ILType t = { .kind = IL_TY_F32 }; return type_intern(&t); }
const ILType* il_type_f64(void) { ILType t = { .kind = IL_TY_F64 }; return type_intern(&t); }

const ILType* il_type_array(const ILType* element, uint64_t length) {
    ILType t = { .kind = IL_TY_ARRAY };
    t.as.array.element = element;
    t.as.array.length = length;
    return type_intern(&t);
}

const ILType* il_type_struct(const char* name, uint32_t type_def_id) {
    return il_type_struct_gen(name, type_def_id, NULL, 0);
}

const ILType* il_type_struct_gen(const char* name, uint32_t type_def_id, const ILType** type_args, uint32_t type_arg_count) {
    ILType t = { .kind = IL_TY_STRUCT };
    t.as.struct_sum.name = (char*)name;
    t.as.struct_sum.type_def_id = type_def_id;
    t.as.struct_sum.type_args = (const ILType**)type_args;
    t.as.struct_sum.type_arg_count = type_arg_count;
    return type_intern(&t);
}

const ILType* il_type_sum(const char* name, uint32_t type_def_id) {
    return il_type_sum_gen(name, type_def_id, NULL, 0);
}

const ILType* il_type_sum_gen(const char* name, uint32_t type_def_id, const ILType** type_args, uint32_t type_arg_count) {
    ILType t = { .kind = IL_TY_SUM };
    t.as.struct_sum.name = (char*)name;
    t.as.struct_sum.type_def_id = type_def_id;
    t.as.struct_sum.type_args = (const ILType**)type_args;
    t.as.struct_sum.type_arg_count = type_arg_count;
    return type_intern(&t);
}

const ILType* il_type_var(const char* name) {
    ILType t = { .kind = IL_TY_VAR };
    t.as.var.name = (char*)name;
    return type_intern(&t);
}

const ILType* il_type_fn(const ILType* return_type, const ILType** param_types, uint32_t param_count, bool is_variadic) {
    ILType t = { .kind = IL_TY_FN };
    t.as.function.return_type = return_type;
    t.as.function.param_types = param_types;
    t.as.function.param_count = param_count;
    t.as.function.is_variadic = is_variadic;
    return type_intern(&t);
}

const ILType* il_type_tuple(const ILType** elements, uint32_t count) {
    ILType t = { .kind = IL_TY_TUPLE };
    t.as.tuple.elements = elements;
    t.as.tuple.count = count;
    return type_intern(&t);
}

const ILType* il_type_ptr(const ILType* pointee, uint32_t region_id, bool is_mut) {
    ILType t = { .kind = IL_TY_PTR };
    t.as.ptr.pointee = pointee;
    t.as.ptr.region_id = region_id;
    t.as.ptr.is_mut = is_mut;
    return type_intern(&t);
}

const ILType* il_type_box(const ILType* pointee, uint32_t region_id, bool is_mut) {
    ILType t = { .kind = IL_TY_BOX };
    t.as.box.pointee = pointee;
    t.as.box.region_id = region_id;
    t.as.box.is_mut = is_mut;
    return type_intern(&t);
}

const ILType* il_type_slice(const ILType* element, uint32_t region_id, bool is_mut) {
    ILType t = { .kind = IL_TY_SLICE };
    t.as.slice.element = element;
    t.as.slice.region_id = region_id;
    t.as.slice.is_mut = is_mut;
    return type_intern(&t);
}

static ILType unit_type  = { .kind = IL_TY_UNIT };
static ILType never_type = { .kind = IL_TY_NEVER };
const ILType* il_type_unit(void) { return &unit_type; }
const ILType* il_type_never(void) { return &never_type; }

const ILType* il_type_fd(ILFdCap cap) {
    ILType t = { .kind = IL_TY_FD };
    t.as.fd.cap = cap;
    return type_intern(&t);
}

const ILType* il_type_async_context(void) {
    ILType t = { .kind = IL_TY_ASYNC_CONTEXT };
    return type_intern(&t);
}

bool is_aggregate_type_layout(const ILType* ty) {
    if (!ty) return false;
    return (ty->kind == IL_TY_STRUCT || ty->kind == IL_TY_SUM || ty->kind == IL_TY_ARRAY || ty->kind == IL_TY_TUPLE || ty->kind == IL_TY_SLICE);
}

bool requires_pass_by_ref(const void* mod, const ILType* ty) {
    if (!ty) return false;
    if (!is_aggregate_type_layout(ty)) return false;
    if (ty->kind == IL_TY_SLICE) return false;
    if (!mod) return true; 
    size_t sz = il_type_size(mod, ty);
    return sz > 16;
}

bool il_elem_addr_steps_raw_slices(const ILType* base, const ILType* result) {
    if (!base || !result || base->kind != IL_TY_PTR || result->kind != IL_TY_PTR) return false;
    const ILType* pointee = base->as.ptr.pointee;
    return pointee && pointee->kind == IL_TY_SLICE && il_type_eq(result->as.ptr.pointee, pointee);
}

bool il_type_eq(const ILType* a, const ILType* b) {
    if (a == b) return true;
    if (!a || !b) return false;
    return il_type_structurally_eq(a, b);
}

bool il_type_is_assignable(const ILType* source, const ILType* target) {
    if (source == target) return true;
    if (!source || !target) return false;
    if (source->kind == IL_TY_NEVER) return true;
    if (target->kind == IL_TY_UNIT) return true;
    bool kind_ok = (source->kind == target->kind);
    if (!kind_ok) {
        if ((source->kind == IL_TY_STRUCT || source->kind == IL_TY_SUM) && (target->kind == IL_TY_STRUCT || target->kind == IL_TY_SUM)) kind_ok = true;
        else if (source->kind == IL_TY_BOX && target->kind == IL_TY_PTR) kind_ok = true;
        else if (target->kind == IL_TY_SLICE) {
            if (source->kind == IL_TY_ARRAY) kind_ok = true;
            else if (source->kind == IL_TY_PTR && source->as.ptr.pointee->kind == IL_TY_ARRAY) kind_ok = true;
            else if (source->kind == IL_TY_BOX && source->as.box.pointee->kind == IL_TY_ARRAY) kind_ok = true;
        }
    }
    if (!kind_ok) return false;
    switch (source->kind) {
        case IL_TY_PTR:
            if (target->kind == IL_TY_SLICE) {
                if (target->as.slice.is_mut && !source->as.ptr.is_mut) return false;
                if (!il_region_outlives(source->as.ptr.region_id, target->as.slice.region_id)) return false;
                if (source->as.ptr.pointee->kind == IL_TY_ARRAY) return il_type_eq(source->as.ptr.pointee->as.array.element, target->as.slice.element);
                return false;
            }
            if (target->as.ptr.is_mut && !source->as.ptr.is_mut) return false;
            if (!il_region_outlives(source->as.ptr.region_id, target->as.ptr.region_id)) return false;
            if (!source->as.ptr.pointee || !target->as.ptr.pointee) return false;
            if (!target->as.ptr.is_mut) return il_type_is_assignable(source->as.ptr.pointee, target->as.ptr.pointee);
            return il_type_eq(source->as.ptr.pointee, target->as.ptr.pointee);
        case IL_TY_BOX:
            if (target->kind == IL_TY_PTR) {
                if (target->as.ptr.is_mut && !source->as.box.is_mut) return false;
                if (!source->as.box.pointee || !target->as.ptr.pointee) return false;
                if (!target->as.ptr.is_mut) return il_type_is_assignable(source->as.box.pointee, target->as.ptr.pointee);
                return il_type_eq(source->as.box.pointee, target->as.ptr.pointee);
            }
            if (target->as.box.is_mut && !source->as.box.is_mut) return false;
            if (source->as.box.region_id != target->as.box.region_id) return false;
            if (!source->as.box.pointee || !target->as.box.pointee) return false;
            return il_type_eq(source->as.box.pointee, target->as.box.pointee);
        case IL_TY_SLICE:
            if (target->as.slice.is_mut && !source->as.slice.is_mut) return false;
            if (!il_region_outlives(source->as.slice.region_id, target->as.slice.region_id)) return false;
            return il_type_eq(source->as.slice.element, target->as.slice.element);
        case IL_TY_ARRAY:
            if (source->as.array.length != target->as.array.length) return false;
            return il_type_eq(source->as.array.element, target->as.array.element);
        case IL_TY_SUM:
        case IL_TY_STRUCT:
            if (source->as.struct_sum.type_def_id != 0 && source->as.struct_sum.type_def_id == target->as.struct_sum.type_def_id) return true;
            if (source->as.struct_sum.name && target->as.struct_sum.name) {
                if (strcmp(source->as.struct_sum.name, target->as.struct_sum.name) == 0) {
                     if (source->as.struct_sum.type_arg_count == target->as.struct_sum.type_arg_count) {
                         bool args_match = true;
                         for (uint32_t i = 0; i < source->as.struct_sum.type_arg_count; i++) {
                             if (!il_type_is_assignable(source->as.struct_sum.type_args[i], target->as.struct_sum.type_args[i])) {
                                 args_match = false;
                                 break;
                             }
                         }
                         if (args_match) return true;
                     }
                     // A monomorphized type is assignable to its base generic type if the target has no arguments.
                     if (target->as.struct_sum.type_arg_count == 0) return true;
                }
                const char *s_name = source->as.struct_sum.name, *t_name = target->as.struct_sum.name;
                const char *s_under = strchr(s_name, '_'), *t_under = strchr(t_name, '_');
                if (s_under && !t_under) { 
                    size_t base_len = (size_t)(s_under - s_name); 
                    if (strncmp(s_name, t_name, base_len) == 0 && t_name[base_len] == '\0') return true;
                }
                if (t_under && !s_under) { 
                    size_t base_len = (size_t)(t_under - t_name); 
                    if (strncmp(s_name, t_name, base_len) == 0 && s_name[base_len] == '\0') return true;
                }
            }
            return source->as.struct_sum.name == target->as.struct_sum.name;
        case IL_TY_TUPLE:
            if (source->as.tuple.count != target->as.tuple.count) return false;
            for (uint32_t i = 0; i < source->as.tuple.count; i++) if (!il_type_is_assignable(source->as.tuple.elements[i], target->as.tuple.elements[i])) return false;
            return true;
        default:
            if (is_numeric_type(source) && is_numeric_type(target)) return il_type_is_numeric_assignable(source, target);
            return il_type_eq(source, target);
    }
}

static bool il_type_is_copy_internal(const void* mod, const ILType* type, int depth) {
    if (type == NULL) return true;
    if (depth > 500) return true;
    bool res = false;
    switch (type->kind) {
        case IL_TY_U8: case IL_TY_U16: case IL_TY_U32: case IL_TY_U64: case IL_TY_USIZE:
        case IL_TY_I8: case IL_TY_I16: case IL_TY_I32: case IL_TY_I64: case IL_TY_ISIZE:
        case IL_TY_F32: case IL_TY_F64:
        case IL_TY_BOOL: case IL_TY_UNIT:
        case IL_TY_PTR: case IL_TY_FN: res = true; break;
        case IL_TY_BOX: res = false; break;
        case IL_TY_FD:
        case IL_TY_ASYNC_CONTEXT: res = false; break;
        case IL_TY_STRUCT:
        case IL_TY_SUM: {
            if (!mod) { res = false; break; }
            const ILTypeDef* def = il_mod_get_type_def(mod, type->as.struct_sum.type_def_id);
            if (!def) { res = false; break; }
            if (def->drop_fn_name != NULL) { res = false; break; }
            res = true;
            for (uint32_t i = 0; i < def->field_count; i++) if (!il_type_is_copy_internal(mod, def->fields[i].type, depth + 1)) { res = false; break; }
            break;
        }
        /* A slice is a view (pointer, length), Copy whether or not it may write: the language
           treats `[mut T]` as Copy too, and src/ keeps them in struct fields it reads. */
        case IL_TY_SLICE: res = true; break;
        case IL_TY_ARRAY: res = il_type_is_copy_internal(mod, type->as.array.element, depth + 1); break;
        case IL_TY_TUPLE:
            res = true;
            for (uint32_t i = 0; i < type->as.tuple.count; i++) if (!il_type_is_copy_internal(mod, type->as.tuple.elements[i], depth + 1)) { res = false; break; }
            break;
        default: res = false; break;
    }
    return res;
}

bool il_type_is_copy_mod(const void* mod, const ILType* type) { return il_type_is_copy_internal(mod, type, 0); }
bool il_type_is_copy(const ILType* type) { return il_type_is_copy_mod(NULL, type); }

bool il_type_is_generic_mod(const void* mod, const ILType* type) {
    if (type == NULL) return false;
    switch (type->kind) {
        case IL_TY_VAR: return true;
        case IL_TY_PTR: return il_type_is_generic_mod(mod, type->as.ptr.pointee);
        case IL_TY_BOX: return il_type_is_generic_mod(mod, type->as.box.pointee);
        case IL_TY_SLICE: return il_type_is_generic_mod(mod, type->as.slice.element);
        case IL_TY_ARRAY: return il_type_is_generic_mod(mod, type->as.array.element);
        case IL_TY_TUPLE: for (uint32_t i = 0; i < type->as.tuple.count; i++) if (il_type_is_generic_mod(mod, type->as.tuple.elements[i])) return true; return false;
        case IL_TY_STRUCT:
        case IL_TY_SUM:
            if (type->as.struct_sum.type_def_id == 0) return true;
            for (uint32_t i = 0; i < type->as.struct_sum.type_arg_count; i++) if (il_type_is_generic_mod(mod, type->as.struct_sum.type_args[i])) return true;
            if (mod) { const ILTypeDef* def = il_mod_get_type_def(mod, type->as.struct_sum.type_def_id); if (def && def->is_generic) return true; }
            return false;
        case IL_TY_FN:
            if (il_type_is_generic_mod(mod, type->as.function.return_type)) return true;
            for (uint32_t i = 0; i < type->as.function.param_count; i++) if (il_type_is_generic_mod(mod, type->as.function.param_types[i])) return true;
            return false;
        default: return false;
    }
}

/* ── Primitive type metadata table ── */

/* Indexed by ILTypeKind (0..26).  NULL name/qbe_* means "composite or N/A". */
static const ILPrimMeta PRIM_META[] = {
    /* UNIT */          {0, 1, "unit",          NULL, NULL, NULL},
    /* BOOL */          {1, 1, "bool",          "w",  "b",  "ub"},
    /* U8   */          {1, 1, "u8",            "w",  "b",  "ub"},
    /* U16  */          {2, 2, "u16",           "w",  "h",  "uh"},
    /* U32  */          {4, 4, "u32",           "w",  "w",  "w"},
    /* U64  */          {8, 8, "u64",           "l",  "l",  "l"},
    /* I8   */          {1, 1, "i8",            "w",  "b",  "sb"},
    /* I16  */          {2, 2, "i16",           "w",  "h",  "sh"},
    /* I32  */          {4, 4, "i32",           "w",  "w",  "w"},
    /* I64  */          {8, 8, "i64",           "l",  "l",  "l"},
    /* F32  */          {4, 4, "f32",           "s",  "s",  "s"},
    /* F64  */          {8, 8, "f64",           "d",  "d",  "d"},
    /* PTR  */          {8, 8, NULL,            "l",  "l",  "l"},
    /* BOX  */          {8, 8, NULL,            "l",  "l",  "l"},
    /* SLICE */         {16,8, NULL,            "l",  "l",  "l"},
    /* ARRAY */         {0, 0, NULL,            "l",  "l",  "l"},  /* size/align vary */
    /* SUM  */          {0, 0, NULL,            "l",  "l",  "l"},  /* size/align vary */
    /* STRUCT */        {0, 0, NULL,            "l",  "l",  "l"},  /* size/align vary */
    /* VAR  */          {0, 1, NULL,            NULL, NULL, NULL},
    /* GENERIC_INST */  {0, 1, NULL,            NULL, NULL, NULL},
    /* FD   */          {8, 8, "fd",            "l",  "l",  "l"},
    /* ASYNC_CONTEXT */ {8, 8, "async_context", "l",  "l",  "l"},
    /* FN   */          {8, 8, NULL,            "l",  "l",  "l"},
    /* TUPLE */         {0, 0, NULL,            "l",  "l",  "l"},  /* size/align vary */
    /* NEVER */         {0, 1, "never",         "l",  NULL, NULL},
    /* USIZE */         {8, 8, "usize",         "l",  "l",  "l"},
    /* ISIZE */         {8, 8, "isize",         "l",  "l",  "l"},
    /* CHAR  */         {4, 4, "char",          "w",  "w",  "w"},
};

const ILPrimMeta* il_prim_meta(ILTypeKind kind) {
    if ((unsigned)kind >= sizeof(PRIM_META) / sizeof(PRIM_META[0])) return NULL;
    return &PRIM_META[kind];
}

/* ── Type layout (moved from il_cfg.c; il_cfg owns blocks/functions/graph) ── */

size_t il_type_size(const ILModule* mod, const ILType* type) {
    if (type == NULL) return 0;
    const ILPrimMeta* m = il_prim_meta(type->kind);
    if (m && m->align != 0) return m->size; /* fixed-size primitive */
    switch (type->kind) {
        case IL_TY_ARRAY: {
            size_t s = il_type_size(mod, type->as.array.element);
            size_t a = il_type_align(mod, type->as.array.element);
            size_t padded_s = (s + a - 1) & ~(a - 1);
            return (size_t)type->as.array.length * padded_s;
        }
        case IL_TY_TUPLE: {
            size_t size = 0;
            size_t max_align = 1;
            for (uint32_t i = 0; i < type->as.tuple.count; i++) {
                size_t s = il_type_size(mod, type->as.tuple.elements[i]);
                size_t a = il_type_align(mod, type->as.tuple.elements[i]);
                if (a > max_align) max_align = a;
                size = (size + a - 1) & ~(a - 1);
                size += s;
            }
            return (size + max_align - 1) & ~(max_align - 1);
        }
        case IL_TY_SUM:
        case IL_TY_STRUCT: {
            const ILTypeDef* def = il_mod_get_type_def(mod, type->as.struct_sum.type_def_id);
            size_t sz = il_type_def_size(mod, def);
            if (sz == 0) return 8;
            return sz;
        }
        case IL_TY_VAR: return 8;
        case IL_TY_SLICE: return 16;
        default: return 0;
    }
}

size_t il_type_align(const ILModule* mod, const ILType* type) {
    if (type == NULL) return 1;
    const ILPrimMeta* m = il_prim_meta(type->kind);
    if (m && m->align != 0) return m->align; /* fixed-alignment primitive */
    switch (type->kind) {
        case IL_TY_SLICE: return 8;
        case IL_TY_ARRAY: return il_type_align(mod, type->as.array.element);
        case IL_TY_TUPLE: {
            size_t max_align = 1;
            for (uint32_t i = 0; i < type->as.tuple.count; i++) {
                size_t a = il_type_align(mod, type->as.tuple.elements[i]);
                if (a > max_align) max_align = a;
            }
            return max_align;
        }
        case IL_TY_SUM:
        case IL_TY_STRUCT: {
            const ILTypeDef* def = il_mod_get_type_def(mod, type->as.struct_sum.type_def_id);
            if (!def && mod && type->as.struct_sum.name) {
                for (uint32_t i = 0; i < mod->type_def_count; i++) {
                    if (mod->type_defs[i]->name && strcmp(mod->type_defs[i]->name, type->as.struct_sum.name) == 0) {
                        def = mod->type_defs[i];
                        break;
                    }
                }
            }
            if (!def) return 8;
            size_t max_align = def->is_sum ? il_type_def_tag_size(def) : 1;
            for (uint32_t i = 0; i < def->field_count; i++) {
                size_t a = il_type_align(mod, def->fields[i].type);
                if (a > max_align) max_align = a;
            }
            return max_align;
        }
        default: return 1;
    }
}

size_t il_type_def_tag_size(const ILTypeDef* def) {
    if (!def || !def->is_sum) return 0;
    /* Zoril-C formerly used 1 or 2 bytes for small enums, but the self-hosted
     * compiler expects u32 tags (4 bytes). Using a smaller store leaves
     * garbage in the upper bytes of the tag word on the stack. */
    return 4;
}

size_t il_type_def_size(const ILModule* mod, const ILTypeDef* def) {
    if (!def) return 0;
    if (def->is_sum) {
        size_t tag_sz = il_type_def_tag_size(def);
        size_t max_variant_size = 0;
        size_t max_variant_align = 1;
        for (uint32_t i = 0; i < def->field_count; i++) {
            size_t s = il_type_size(mod, def->fields[i].type);
            size_t a = il_type_align(mod, def->fields[i].type);
            if (s > max_variant_size) max_variant_size = s;
            if (a > max_variant_align) max_variant_align = a;
        }
        size_t payload_offset = (tag_sz + max_variant_align - 1) & ~(max_variant_align - 1);
        size_t total_size = payload_offset + max_variant_size;
        size_t max_align = (max_variant_align > tag_sz) ? max_variant_align : tag_sz;
        return (total_size + max_align - 1) & ~(max_align - 1);
    } else {
        size_t offset = 0;
        size_t max_align = 1;
        for (uint32_t i = 0; i < def->field_count; i++) {
            size_t s = il_type_size(mod, def->fields[i].type);
            size_t a = il_type_align(mod, def->fields[i].type);
            if (a > max_align) max_align = a;
            offset = (offset + a - 1) & ~(a - 1);
            offset += s;
        }
        return (offset + max_align - 1) & ~(max_align - 1);
    }
}

size_t il_type_def_get_field_offset(const ILModule* mod, const ILTypeDef* def, uint32_t field_index) {
    if (!def || field_index >= def->field_count) return 0;
    if (def->is_sum) {
        size_t tag_sz = il_type_def_tag_size(def);
        size_t max_variant_align = 1;
        for (uint32_t i = 0; i < def->field_count; i++) {
            size_t a = il_type_align(mod, def->fields[i].type);
            if (a > max_variant_align) max_variant_align = a;
        }
        return (tag_sz + max_variant_align - 1) & ~(max_variant_align - 1);
    }
    size_t offset = 0;
    for (uint32_t i = 0; i <= field_index; i++) {
        size_t s = il_type_size(mod, def->fields[i].type);
        size_t a = il_type_align(mod, def->fields[i].type);
        offset = (offset + a - 1) & ~(a - 1);
        if (i == field_index) return offset;
        offset += s;
    }
    return offset;
}

size_t il_type_get_tuple_field_offset(const ILModule* mod, const ILType* type, uint32_t field_index) {
    if (!type || type->kind != IL_TY_TUPLE || field_index >= type->as.tuple.count) return 0;
    size_t offset = 0;
    for (uint32_t i = 0; i <= field_index; i++) {
        const ILType* elem_ty = type->as.tuple.elements[i];
        size_t s = il_type_size(mod, elem_ty);
        size_t a = il_type_align(mod, elem_ty);
        offset = (offset + a - 1) & ~(a - 1);
        if (i == field_index) return offset;
        offset += s;
    }
    return offset;
}
