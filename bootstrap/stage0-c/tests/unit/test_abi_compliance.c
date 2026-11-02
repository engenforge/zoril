/* ABI compliance tests — Section 1, 3, 7 of doc/spec/abi.md */
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "il_type.h"
#include "il_cfg.h"
#include "il_print.h"
#include "il_read.h"
#include "il_region.h"

int tests_run = 0;
int tests_passed = 0;

/* --- Section 1: Primitive type sizes and alignments --- */

static bool test_primitive_sizes(void) {
    ILModule* mod = il_mod_create();
    ASSERT(il_type_size(mod, il_type_unit())  == 0, "unit size must be 0");
    ASSERT(il_type_size(mod, il_type_bool())  == 1, "bool size must be 1");
    ASSERT(il_type_size(mod, il_type_u8())    == 1, "u8 size must be 1");
    ASSERT(il_type_size(mod, il_type_i8())    == 1, "i8 size must be 1");
    ASSERT(il_type_size(mod, il_type_u16())   == 2, "u16 size must be 2");
    ASSERT(il_type_size(mod, il_type_i16())   == 2, "i16 size must be 2");
    ASSERT(il_type_size(mod, il_type_u32())   == 4, "u32 size must be 4");
    ASSERT(il_type_size(mod, il_type_i32())   == 4, "i32 size must be 4");
    ASSERT(il_type_size(mod, il_type_f32())   == 4, "f32 size must be 4");
    ASSERT(il_type_size(mod, il_type_u64())   == 8, "u64 size must be 8");
    ASSERT(il_type_size(mod, il_type_i64())   == 8, "i64 size must be 8");
    ASSERT(il_type_size(mod, il_type_f64())   == 8, "f64 size must be 8");
    ASSERT(il_type_size(mod, il_type_usize()) == 8, "usize size must be 8");
    ASSERT(il_type_size(mod, il_type_isize()) == 8, "isize size must be 8");
    ASSERT(il_type_size(mod, il_type_never()) == 0, "never size must be 0");
    il_mod_free(mod);
    return true;
}

static bool test_primitive_alignments(void) {
    ILModule* mod = il_mod_create();
    ASSERT(il_type_align(mod, il_type_unit())  == 1, "unit align must be 1");
    ASSERT(il_type_align(mod, il_type_bool())  == 1, "bool align must be 1");
    ASSERT(il_type_align(mod, il_type_u8())    == 1, "u8 align must be 1");
    ASSERT(il_type_align(mod, il_type_i8())    == 1, "i8 align must be 1");
    ASSERT(il_type_align(mod, il_type_u16())   == 2, "u16 align must be 2");
    ASSERT(il_type_align(mod, il_type_i16())   == 2, "i16 align must be 2");
    ASSERT(il_type_align(mod, il_type_u32())   == 4, "u32 align must be 4");
    ASSERT(il_type_align(mod, il_type_i32())   == 4, "i32 align must be 4");
    ASSERT(il_type_align(mod, il_type_f32())   == 4, "f32 align must be 4");
    ASSERT(il_type_align(mod, il_type_u64())   == 8, "u64 align must be 8");
    ASSERT(il_type_align(mod, il_type_i64())   == 8, "i64 align must be 8");
    ASSERT(il_type_align(mod, il_type_f64())   == 8, "f64 align must be 8");
    ASSERT(il_type_align(mod, il_type_usize()) == 8, "usize align must be 8");
    ASSERT(il_type_align(mod, il_type_isize()) == 8, "isize align must be 8");
    ASSERT(il_type_align(mod, il_type_never()) == 1, "never align must be 1");
    il_mod_free(mod);
    return true;
}

/* --- Section 2: Compound type layout --- */

static bool test_slice_layout(void) {
    ILModule* mod = il_mod_create();
    const ILType* slice = il_type_slice(il_type_u8(), REGION_STATIC, false);
    ASSERT(il_type_size(mod, slice)  == 16, "slice size must be 16 (ptr+len)");
    ASSERT(il_type_align(mod, slice) ==  8, "slice align must be 8");
    il_mod_free(mod);
    return true;
}

static bool test_array_layout(void) {
    ILModule* mod = il_mod_create();
    const ILType* arr = il_type_array(il_type_u32(), 5);
    ASSERT(il_type_size(mod, arr)  == 20, "u32[5] size must be 20");
    ASSERT(il_type_align(mod, arr) ==  4, "u32[5] align must be 4");
    il_mod_free(mod);
    return true;
}

static bool test_struct_layout_padding(void) {
    /* struct { u8 a; u32 b; } => offset(b)=4, total=8, align=4 */
    ILModule* mod = il_mod_create();
    ILTypeDef* def = il_type_def_struct_create(1, "S", NULL, true);
    il_type_def_add_field(def, "a", il_type_u8());
    il_type_def_add_field(def, "b", il_type_u32());
    il_mod_add_type_def(mod, def);
    ASSERT(il_type_def_size(mod, def)  == 8, "struct{u8,u32} size must be 8");
    ASSERT(il_type_def_get_field_offset(mod, def, 0) == 0, "field a offset must be 0");
    ASSERT(il_type_def_get_field_offset(mod, def, 1) == 4, "field b offset must be 4");
    il_mod_free(mod);
    return true;
}

/* --- Section 3: Enum (sum type) layout --- */

static bool test_enum_tag_is_u32(void) {
    ILTypeDef* def = il_type_def_sum_create(1, "Color", NULL, true);
    ASSERT(il_type_def_tag_size(def) == 4, "enum tag must be 4 bytes (u32)");
    il_type_def_free(def);
    return true;
}

static bool test_enum_layout_rules(void) {
    /*
     * enum Foo { A(u64) }
     *   tag_sz          = 4
     *   max_variant_align = 8  (u64)
     *   payload_offset  = align_to(4, 8) = 8
     *   enum_align      = max(4, 8) = 8
     *   total_size      = align_to(8 + 8, 8) = 16
     */
    ILModule* mod = il_mod_create();
    ILTypeDef* def = il_type_def_sum_create(1, "Foo", NULL, true);
    il_type_def_add_field(def, "A", il_type_u64());
    il_mod_add_type_def(mod, def);

    ASSERT(il_type_def_size(mod, def)  == 16, "enum{A(u64)} total size must be 16");
    ASSERT(il_type_def_get_field_offset(mod, def, 0) == 8, "enum payload offset must be 8");

    const ILType* sum_ty = il_type_struct(NULL, 1);
    ASSERT(il_type_align(mod, sum_ty) == 8, "enum{A(u64)} align must be 8");
    il_mod_free(mod);
    return true;
}

static bool test_enum_layout_small_variant(void) {
    /*
     * enum Bar { A(u8) }
     *   tag_sz          = 4
     *   max_variant_align = 1  (u8)
     *   payload_offset  = align_to(4, 1) = 4
     *   enum_align      = max(4, 1) = 4
     *   total_size      = align_to(4 + 1, 4) = 8
     */
    ILModule* mod = il_mod_create();
    ILTypeDef* def = il_type_def_sum_create(1, "Bar", NULL, true);
    il_type_def_add_field(def, "A", il_type_u8());
    il_mod_add_type_def(mod, def);

    ASSERT(il_type_def_size(mod, def)  == 8, "enum{A(u8)} total size must be 8");
    ASSERT(il_type_def_get_field_offset(mod, def, 0) == 4, "enum{A(u8)} payload offset must be 4");

    const ILType* sum_ty = il_type_struct(NULL, 1);
    ASSERT(il_type_align(mod, sum_ty) == 4, "enum{A(u8)} align must be 4");
    il_mod_free(mod);
    return true;
}

/* --- Section 7.2: Region IDs --- */

static bool test_region_ids(void) {
    ASSERT(REGION_STATIC == 0xFFFFFFF1U, "'static region ID must be 0xFFFFFFF1");
    ASSERT(REGION_LOCAL  == 0xFFFFFFF2U, "'local region ID must be 0xFFFFFFF2");
    ASSERT(REGION_HEAP   == 0xFFFFFFF3U, "'heap region ID must be 0xFFFFFFF3");
    return true;
}

/* --- Section 7.3: Name-mangling round-trip via il_print / il_read --- */

/* These tests verify that il_print_type produces the canonical text that
   il_read_type can re-parse back to the identical type kind. */

static bool test_print_usize(void) {
    char buf[64];
    il_print_type(NULL, il_type_usize(), buf, sizeof(buf));
    ASSERT(strcmp(buf, "usize") == 0, "usize must print as 'usize'");
    return true;
}

static bool test_print_isize(void) {
    char buf[64];
    il_print_type(NULL, il_type_isize(), buf, sizeof(buf));
    ASSERT(strcmp(buf, "isize") == 0, "isize must print as 'isize'");
    return true;
}

static bool test_print_never(void) {
    char buf[64];
    il_print_type(NULL, il_type_never(), buf, sizeof(buf));
    ASSERT(strcmp(buf, "never") == 0, "never must print as 'never'");
    return true;
}

static bool test_read_usize(void) {
    const char* end;
    const ILType* t = il_read_type("usize", &end);
    ASSERT(t != NULL,                    "il_read_type(\"usize\") must not return NULL");
    ASSERT(t->kind == IL_TY_USIZE,       "parsed type must have kind IL_TY_USIZE");
    return true;
}

static bool test_read_isize(void) {
    const char* end;
    const ILType* t = il_read_type("isize", &end);
    ASSERT(t != NULL,                    "il_read_type(\"isize\") must not return NULL");
    ASSERT(t->kind == IL_TY_ISIZE,       "parsed type must have kind IL_TY_ISIZE");
    return true;
}

static bool test_read_never(void) {
    const char* end;
    const ILType* t = il_read_type("never", &end);
    ASSERT(t != NULL,                    "il_read_type(\"never\") must not return NULL");
    ASSERT(t->kind == IL_TY_NEVER,       "parsed type must have kind IL_TY_NEVER");
    return true;
}

/* --- Section 7.1: implicit parameter helpers (ABI §7.1) --- */

static bool test_needs_env_ptr_normal_fn(void) {
    ILFunction* fn = il_func_create(1, "foo", il_type_unit(), true, false, "test.zrl");
    ASSERT(il_func_needs_env_ptr(fn), "normal non-extern non-main fn needs env ptr");
    il_func_free(fn);
    return true;
}

static bool test_needs_env_ptr_extern_fn(void) {
    ILFunction* fn = il_func_create(1, "ext", il_type_unit(), true, false, "test.zrl");
    fn->is_extern = true;
    ASSERT(!il_func_needs_env_ptr(fn), "extern fn must NOT need env ptr");
    il_func_free(fn);
    return true;
}

static bool test_needs_env_ptr_main(void) {
    ILFunction* fn = il_func_create(1, "main", il_type_unit(), true, false, "test.zrl");
    ASSERT(!il_func_needs_env_ptr(fn), "main must NOT need env ptr");
    il_func_free(fn);
    return true;
}

static bool test_user_param_offset_plain(void) {
    /* No sret, no env ptr (extern) → offset = 0 */
    ILFunction* fn = il_func_create(1, "ext", il_type_unit(), true, false, "test.zrl");
    fn->is_extern = true;
    ASSERT(il_func_user_param_offset(fn) == 0, "extern fn: user param offset must be 0");
    il_func_free(fn);
    return true;
}

static bool test_user_param_offset_env_only(void) {
    /* No sret, but env ptr present → offset = 1 */
    ILFunction* fn = il_func_create(1, "foo", il_type_unit(), true, false, "test.zrl");
    ASSERT(il_func_user_param_offset(fn) == 1, "non-extern fn without sret: offset must be 1");
    il_func_free(fn);
    return true;
}

static bool test_user_param_offset_sret_and_env(void) {
    /* sret + env ptr → offset = 2 */
    ILFunction* fn = il_func_create(1, "foo", il_type_unit(), true, false, "test.zrl");
    fn->is_sret = true;
    ASSERT(il_func_user_param_offset(fn) == 2, "fn with sret+env: offset must be 2");
    il_func_free(fn);
    return true;
}

/* Round-trip: print then re-read must give the same kind. */
static bool test_roundtrip_usize(void) {
    char buf[64];
    il_print_type(NULL, il_type_usize(), buf, sizeof(buf));
    const char* end;
    const ILType* t = il_read_type(buf, &end);
    ASSERT(t != NULL,              "round-trip parse of usize must not return NULL");
    ASSERT(t->kind == IL_TY_USIZE, "round-trip usize kind must be IL_TY_USIZE");
    return true;
}

static bool test_roundtrip_isize(void) {
    char buf[64];
    il_print_type(NULL, il_type_isize(), buf, sizeof(buf));
    const char* end;
    const ILType* t = il_read_type(buf, &end);
    ASSERT(t != NULL,              "round-trip parse of isize must not return NULL");
    ASSERT(t->kind == IL_TY_ISIZE, "round-trip isize kind must be IL_TY_ISIZE");
    return true;
}

static bool test_roundtrip_never(void) {
    char buf[64];
    il_print_type(NULL, il_type_never(), buf, sizeof(buf));
    const char* end;
    const ILType* t = il_read_type(buf, &end);
    ASSERT(t != NULL,              "round-trip parse of never must not return NULL");
    ASSERT(t->kind == IL_TY_NEVER, "round-trip never kind must be IL_TY_NEVER");
    return true;
}

/* --- id:1006: ILPrimMeta table --- */

static bool test_prim_meta_u8(void) {
    const ILPrimMeta* m = il_prim_meta(IL_TY_U8);
    ASSERT(m != NULL,            "IL_TY_U8 must have metadata");
    ASSERT(m->size == 1,         "u8 size must be 1");
    ASSERT(m->align == 1,        "u8 align must be 1");
    ASSERT(strcmp(m->name, "u8") == 0, "u8 name must be 'u8'");
    ASSERT(strcmp(m->qbe_val,   "w") == 0, "u8 qbe_val must be 'w'");
    ASSERT(strcmp(m->qbe_store, "b") == 0, "u8 qbe_store must be 'b'");
    ASSERT(strcmp(m->qbe_load,  "ub") == 0,"u8 qbe_load must be 'ub'");
    return true;
}

static bool test_prim_meta_i16(void) {
    const ILPrimMeta* m = il_prim_meta(IL_TY_I16);
    ASSERT(m != NULL,               "IL_TY_I16 must have metadata");
    ASSERT(m->size == 2,            "i16 size must be 2");
    ASSERT(m->align == 2,           "i16 align must be 2");
    ASSERT(strcmp(m->name,      "i16") == 0, "i16 name");
    ASSERT(strcmp(m->qbe_store, "h")   == 0, "i16 qbe_store must be 'h'");
    ASSERT(strcmp(m->qbe_load,  "sh")  == 0, "i16 qbe_load must be 'sh'");
    return true;
}

static bool test_prim_meta_f64(void) {
    const ILPrimMeta* m = il_prim_meta(IL_TY_F64);
    ASSERT(m != NULL,                  "IL_TY_F64 must have metadata");
    ASSERT(m->size == 8,               "f64 size must be 8");
    ASSERT(strcmp(m->qbe_val,   "d") == 0, "f64 qbe_val must be 'd'");
    ASSERT(strcmp(m->qbe_store, "d") == 0, "f64 qbe_store must be 'd'");
    ASSERT(strcmp(m->qbe_load,  "d") == 0, "f64 qbe_load must be 'd'");
    return true;
}

static bool test_prim_meta_unit(void) {
    const ILPrimMeta* m = il_prim_meta(IL_TY_UNIT);
    ASSERT(m != NULL,        "IL_TY_UNIT must have metadata");
    ASSERT(m->size == 0,     "unit size must be 0");
    ASSERT(m->align == 1,    "unit align must be 1");
    ASSERT(m->qbe_val == NULL,   "unit qbe_val must be NULL");
    ASSERT(m->qbe_store == NULL, "unit qbe_store must be NULL");
    ASSERT(m->qbe_load == NULL,  "unit qbe_load must be NULL");
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);

    RUN_TEST(test_primitive_sizes);
    RUN_TEST(test_primitive_alignments);
    RUN_TEST(test_slice_layout);
    RUN_TEST(test_array_layout);
    RUN_TEST(test_struct_layout_padding);
    RUN_TEST(test_enum_tag_is_u32);
    RUN_TEST(test_enum_layout_rules);
    RUN_TEST(test_enum_layout_small_variant);
    RUN_TEST(test_region_ids);
    RUN_TEST(test_print_usize);
    RUN_TEST(test_print_isize);
    RUN_TEST(test_print_never);
    RUN_TEST(test_read_usize);
    RUN_TEST(test_read_isize);
    RUN_TEST(test_read_never);
    RUN_TEST(test_roundtrip_usize);
    RUN_TEST(test_roundtrip_isize);
    RUN_TEST(test_roundtrip_never);
    RUN_TEST(test_needs_env_ptr_normal_fn);
    RUN_TEST(test_needs_env_ptr_extern_fn);
    RUN_TEST(test_needs_env_ptr_main);
    RUN_TEST(test_user_param_offset_plain);
    RUN_TEST(test_user_param_offset_env_only);
    RUN_TEST(test_user_param_offset_sret_and_env);

    RUN_TEST(test_prim_meta_u8);
    RUN_TEST(test_prim_meta_i16);
    RUN_TEST(test_prim_meta_f64);
    RUN_TEST(test_prim_meta_unit);

    printf("[%2d/%2d] ABI Compliance Tests\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
