#ifndef IL_TYPE_H
#define IL_TYPE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "il_region.h"
#include "arena.h"

// Tag for the type union
typedef enum {
    IL_TY_UNIT = 0,
    IL_TY_BOOL = 1,
    IL_TY_U8 = 2, IL_TY_U16 = 3, IL_TY_U32 = 4, IL_TY_U64 = 5,
    IL_TY_I8 = 6, IL_TY_I16 = 7, IL_TY_I32 = 8, IL_TY_I64 = 9,
    IL_TY_F32 = 10, IL_TY_F64 = 11,
    IL_TY_PTR = 12,
    IL_TY_BOX = 13,
    IL_TY_SLICE = 14,
    IL_TY_ARRAY = 15,
    IL_TY_SUM = 16,    // Option, Result, user enums
    IL_TY_STRUCT = 17,
    IL_TY_VAR = 18,              // Type variable (e.g., T)
    IL_TY_GENERIC_INSTANCE = 19, // Box<i32>
    IL_TY_FD = 20,     // Typed file descriptor
    IL_TY_ASYNC_CONTEXT = 21, // Async I/O context (io_uring or kqueue)
    IL_TY_FN = 22,      // Function pointer
    IL_TY_TUPLE = 23,  // Tuple type (T1, T2, ...)
    IL_TY_NEVER = 24,   // Never / bottom type (diverging expressions: return, break, all arms terminate)
    IL_TY_USIZE = 25,
    IL_TY_ISIZE = 26,
    IL_TY_CHAR = 27
} ILTypeKind;

/* Capability annotation for file descriptor types. */
typedef enum {
    IL_CAP_READ  = 1, /* fd<r>  -- read-only */
    IL_CAP_WRITE = 2, /* fd<w>  -- write-only */
    IL_CAP_RW    = 3  /* fd<rw> -- read-write */
} ILFdCap;

// Forward declaration for recursive types
typedef struct ILType ILType;

typedef struct {
    Arena arena;
    const ILType * buckets[1024];
    uint32_t type_count;
} ILContext;

extern ILContext* global_il_ctx;

void il_ctx_init(ILContext* ctx);
void il_ctx_destroy(ILContext* ctx);

// The Type Node
struct ILType {
    ILTypeKind kind;
    const struct ILType* next_intern;

    // Union payloads for composite types
    union {
        struct {
            const ILType* pointee;
            uint32_t region_id; // Interned region ID
            bool is_mut;
        } ptr;

        struct {
            const ILType* pointee;
            uint32_t region_id;
            bool is_mut;
        } box;

        struct {
            const ILType* element;
            uint32_t region_id;
            bool is_mut;
        } slice;

        struct {
            const ILType* element;
            uint64_t length;
        } array;

        // Sum types and structs would point to a symbol table entry
        // defining their variants/fields.
        struct {
            uint32_t type_def_id;
            char* name;
            const ILType ** type_args;
            uint32_t type_arg_count;
        } struct_sum;

        struct {
            char* name;
        } var;

        struct {
            const ILType* base;
            const ILType ** type_args;
            uint32_t type_arg_count;
        } generic_instance;

        struct {
            ILFdCap cap;
        } fd;

        struct {
            const ILType* return_type;
            const ILType ** param_types;
            uint32_t param_count;
            bool is_variadic;
        } function;

        struct {
            const ILType ** elements;
            uint32_t count;
        } tuple;
    } as;
    uint64_t serial;
};

const ILType* il_type_bool(void);
const ILType* il_type_char(void);
const ILType* il_type_u8(void);
const ILType* il_type_u16(void);
const ILType* il_type_u32(void);
const ILType* il_type_u64(void);
const ILType* il_type_usize(void);
const ILType* il_type_isize(void);
const ILType* il_type_i8(void);
const ILType* il_type_i16(void);
const ILType* il_type_i32(void);
const ILType* il_type_i64(void);
const ILType* il_type_f32(void);
const ILType* il_type_f64(void);
const ILType* il_type_array(const ILType* element, uint64_t length);
const ILType* il_type_struct(const char* name, uint32_t type_def_id);
const ILType* il_type_struct_gen(const char* name, uint32_t type_def_id, const ILType ** type_args, uint32_t type_arg_count);
const ILType* il_type_sum(const char* name, uint32_t type_def_id);
const ILType* il_type_sum_gen(const char* name, uint32_t type_def_id, const ILType ** type_args, uint32_t type_arg_count);
const ILType* il_type_var(const char* name);
const ILType* il_type_fn(const ILType* return_type, const ILType ** param_types, uint32_t param_count, bool is_variadic);
const ILType* il_type_tuple(const ILType ** elements, uint32_t count);
const ILType* il_type_ptr(const ILType* pointee, uint32_t region_id, bool is_mut);
const ILType* il_type_box(const ILType* pointee, uint32_t region_id, bool is_mut);
const ILType* il_type_slice(const ILType* element, uint32_t region_id, bool is_mut);
const ILType* il_type_unit(void);
const ILType* il_type_never(void);
const ILType* il_type_fd(ILFdCap cap);
const ILType* il_type_async_context(void);
bool is_aggregate_type_layout(const ILType* ty);
bool requires_pass_by_ref(const void* mod, const ILType* ty);
bool is_numeric_type(const ILType* t);
bool is_integral_type(const ILType* t);
bool is_integer_type(const ILType* t);
bool is_float_type(const ILType* t);
bool is_unsigned_type(const ILType* t);
bool is_signed_type(const ILType* t);
bool is_pointer_type(const void* mod, const ILType* t);
int numeric_type_rank(ILTypeKind kind);
const char* il_type_kind_str(ILTypeKind kind);
bool il_type_structurally_eq(const ILType* a, const ILType* b);
bool il_type_eq(const ILType* a, const ILType* b);
/* Whether an ELEM_ADDR on a base of type BASE yielding RESULT steps a raw pointer to
 * slices (a `Vec<[T]>`'s data) rather than indexing through a pointer to one slice header:
 * both bases are Ptr<Slice>, but only the raw step yields a pointer to the slice type. */
bool il_elem_addr_steps_raw_slices(const ILType* base, const ILType* result);
void il_type_print(const ILType* type, char* buffer, size_t max_len);
uint32_t il_type_get_indirection_level(const ILType* t);
bool il_type_is_copy(const ILType* type);
bool il_type_is_copy_mod(const void* mod, const ILType* type);
bool il_type_is_generic_mod(const void* mod, const ILType* type);

bool il_type_is_assignable(const ILType* source, const ILType* target);

char* mangle_type(const ILType* type);
char* mangle_generic_name(const char* base_name, uint32_t count, const ILType ** args);

const ILType* il_type_fixup(const void* vmod, const ILType* type);

/* Primitive type metadata table — avoids repeating the same type switch in
 * il_type_size/align, qbe_map_type/store/load, and il_print_type/il_read_type.
 * Returns NULL for composite types (ARRAY, TUPLE, STRUCT, SUM) whose properties
 * depend on their contents. */
typedef struct {
    uint8_t     size;      /* size in bytes (0 = zero-sized) */
    uint8_t     align;     /* alignment in bytes */
    const char* name;      /* canonical text name (for il_print/il_read) */
    const char* qbe_val;   /* qbe_map_type result   (NULL = ZST) */
    const char* qbe_store; /* qbe_map_store_type result (NULL = ZST) */
    const char* qbe_load;  /* qbe_map_load_type result  (NULL = ZST) */
} ILPrimMeta;

const ILPrimMeta* il_prim_meta(ILTypeKind kind);

#endif
