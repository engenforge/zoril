#ifndef SURFACE_LOWER_INTERNAL_H
#define SURFACE_LOWER_INTERNAL_H

#include "surface_ast.h"
#include "il_cfg.h"
#include "surface_scope.h"
#include "diagnostics.h"

typedef struct Substitution {
    const char* name;
    const char* bound; // optional trait bound
    const ILType* type;
    const struct Substitution* next;
} Substitution;

typedef struct Capture {
    char* name;
    const ILType* type;
    ILValue original_value;
    bool is_lvalue;
    ILValue internal_value;
    struct Capture* next;
} Capture;

typedef struct LoopInfo {
    ILBasicBlock* header;
    ILBasicBlock* exit;
    const Scope* loop_scope;
    uint32_t break_count;
    struct LoopInfo* parent;
} LoopInfo;

typedef struct LowerContext {
    Scope* current_scope;
    ILFunction* current_func;
    const FunctionDecl* current_surface_func;
    const ImplDecl* current_surface_impl;
    ILBasicBlock* current_block;
    uint32_t next_value_id;
    uint32_t next_block_id;
    ILModule* module;
    const SurfaceModule* surface_mod;
    LoopInfo* current_loop;
    const Substitution* current_substs;
    Capture* captures;
    ILTypeDef** generic_defs;
    uint32_t generic_def_count;
    uint32_t generic_def_capacity;
    ILValue env_ptr;
    uint32_t sret_id;
    DiagnosticReport* report;
    const char* current_file;
    const char* current_source;
    uint32_t current_line;
    uint32_t current_col;
    uint32_t current_offset;
    struct LowerContext* parent_ctx;
    bool* value_moved;
    uint32_t value_moved_capacity;
    bool release_mode;
    ILValue* temporaries;
    uint32_t temporary_count;
    uint32_t temporary_capacity;
} LowerContext;

const ILType* lower_type(const SurfaceModule* smod, ILModule* ilmod, DiagnosticReport* report, bool release_mode, const ILType* type, const Substitution* substs);
const ILType* lower_type_with_loc(const SurfaceModule* smod, ILModule* ilmod, DiagnosticReport* report, bool release_mode, const ILType* type, const Substitution* substs, SourceLocation loc);
const ILType* substitute_type(const ILType* type, const Substitution* substs);
const ILType* resolve_type_aliases(const SurfaceModule* smod, const ILType* type, int depth);
const ILType* get_closure_type(ILModule* ilmod, const ILType* fn_ty);
Substitution* derive_substs(const SurfaceModule* smod, const ILType* target_type);

const ILType* guess_type(LowerContext* ctx, const Expression* expr);
ILValue ensure_value(LowerContext* ctx, ILValue val, const ILType* expected);
ILValue lower_expression(LowerContext* ctx, const Expression* expr, const ILType* expected_type, ILValue dest_ptr);
ILValue lower_expression_move(LowerContext* ctx, const Expression* expr, const ILType* expected_type, ILValue dest_ptr);
ILValue lower_expression_internal(LowerContext* ctx, const Expression* expr, const ILType* expected_type, bool is_move, ILValue dest_ptr, bool allow_lvalue, bool force_value);
ILValue lower_lvalue(LowerContext* ctx, const Expression* expr, bool is_mut);
ILValue lower_call(LowerContext* ctx, const Expression* e, const ILType* expected_type, ILValue dest_ptr);
ILValue lower_if_expr(LowerContext* ctx, const IfExpr* if_expr, const ILType* expected_type, ILValue dest_ptr);
ILValue lower_while_expr(LowerContext* ctx, const WhileExpr* expr, const ILType* expected_type, ILValue dest_ptr);
ILValue lower_block(LowerContext* ctx, const BlockExpr* block, const ILType* expected_type, ILValue dest_ptr);
void lower_statement(LowerContext* ctx, const Statement* stmt);
bool block_is_terminated(ILBasicBlock* block);
bool block_ends_with_jump_to(ILBasicBlock* block, uint32_t target_id);

// Diagnostics
void emit_diag_at(LowerContext* ctx, DiagnosticSeverity severity, const Expression* expr, const char* fmt, ...) PRINTF_FORMAT(4, 5);
void emit_stmt_diag_at(LowerContext* ctx, DiagnosticSeverity severity, const Statement* stmt, const char* fmt, ...) PRINTF_FORMAT(4, 5);

// Other internal helpers needed across split modules
ILValue emit(LowerContext* ctx, ILInstruction* instr);
void emit_void(LowerContext* ctx, ILInstruction* instr);
void scope_push(LowerContext* ctx);
void scope_pop(LowerContext* ctx, uint32_t exempt_id);
void symbol_add_ctx(LowerContext* ctx, const char* name, ILValue value, bool is_lvalue);
ILBasicBlock* create_block(LowerContext* ctx);
const ILType* unify_numeric_types(const ILType* a, const ILType* b);
ILValue ensure_assignable(LowerContext* ctx, ILValue val, const ILType* target);
void mark_moved(LowerContext* ctx, uint32_t id);
bool is_moved(LowerContext* ctx, uint32_t id);
bool* save_moved_state(const LowerContext* ctx, uint32_t* out_cap);
void restore_moved_state(LowerContext* ctx, bool* state, uint32_t cap);
void run_all_defers(LowerContext* ctx, uint32_t exempt_id);
void run_defers_in_scope(LowerContext* ctx, Scope* scope);
void scope_emit_drops(LowerContext* ctx, Scope* scope, uint32_t exempt_id);
void emit_return(LowerContext* ctx, ILValue val);
ILValue resolve_capture(LowerContext* ctx, const Symbol* sym);
void lower_context_cleanup(LowerContext* ctx);
ILFunction* monomorphize_function(const SurfaceModule* smod, ILModule* ilmod, DiagnosticReport* report, bool release_mode, const FunctionDecl* sfn, const ILType ** type_args, const char* mangled_name, const Substitution* initial_substs);
ILFunction* monomorphize_method(const SurfaceModule* smod, ILModule* ilmod, DiagnosticReport* report, bool release_mode, const ImplDecl* simpl, const FunctionDecl* sfn, const ILType ** type_args, const char* mangled_name);
ILGlobal* find_global(const ILModule* mod, const char* name);
bool eval_const_int(const SurfaceModule* smod, const Expression* expr, uint64_t* out_val);
bool type_implements_trait(const SurfaceModule* smod, const ILType* type, const char* trait_name, const Substitution* substs);

void run_defers_up_to(LowerContext* ctx, const Scope* limit, uint32_t exempt_id);
ILValue promote_to_lvalue(LowerContext* ctx, ILValue val);
ILValue lower_member_access(LowerContext* ctx, const MemberExpr* expr, const ILType* expected_type, bool is_move, bool allow_lvalue);
ILValue lower_match_expr(LowerContext* ctx, const MatchExpr* expr, const ILType* expected_type, ILValue dest_ptr);

/* Small helpers shared across the surface_lower_*.c translation units */
static inline bool is_borrow_type(const ILType* t) {
    if (!t) return false;
    uint32_t rid = 0;
    if (t->kind == IL_TY_PTR)   rid = t->as.ptr.region_id;
    else if (t->kind == IL_TY_SLICE) rid = t->as.slice.region_id;
    else return false;
    return rid != REGION_LOCAL && rid != REGION_HEAP && rid != REGION_STATIC && rid != 0;
}
static inline uint32_t get_region(const ILType* t) {
    if (!t) return REGION_LOCAL;
    if (t->kind == IL_TY_PTR)   return t->as.ptr.region_id;
    if (t->kind == IL_TY_BOX)   return t->as.box.region_id;
    if (t->kind == IL_TY_SLICE) return t->as.slice.region_id;
    return REGION_LOCAL;
}
static inline bool is_vec_type(const ILType* ty, const ILType** out_elem_ty) {
    if (!ty) return false;
    if (ty->kind != IL_TY_STRUCT) return false;
    const char* name = ty->as.struct_sum.name;
    if (!name) return false;
    if (strcmp(name, "Vec") == 0 || strncmp(name, "Vec_", 4) == 0) {
        if (out_elem_ty) {
            if (ty->as.struct_sum.type_arg_count > 0 && ty->as.struct_sum.type_args) {
                *out_elem_ty = ty->as.struct_sum.type_args[0];
            } else {
                *out_elem_ty = NULL;
            }
        }
        return true;
    }
    return false;
}
static inline const ILType* get_vec_element_type(ILModule* mod, const ILType* ty) {
    if (!ty) return NULL;
    if (ty->kind == IL_TY_PTR) ty = ty->as.ptr.pointee;
    const ILType* elem_ty = NULL;
    if (!is_vec_type(ty, &elem_ty)) return NULL;
    if (elem_ty) return elem_ty;
    if (ty && ty->kind == IL_TY_PTR) ty = ty->as.ptr.pointee;
    if (mod && ty && ty->kind == IL_TY_STRUCT) {
        const ILTypeDef* def = NULL;
        if (ty->as.struct_sum.type_def_id != 0) {
            def = il_mod_get_type_def(mod, ty->as.struct_sum.type_def_id);
        } else if (ty->as.struct_sum.name) {
            def = il_mod_get_type_def_by_name(mod, ty->as.struct_sum.name);
        }
        if (def && def->field_count > 0 && def->fields[0].type && def->fields[0].type->kind == IL_TY_PTR) {
            return def->fields[0].type->as.ptr.pointee;
        }
    }
    return NULL;
}
ILValue ensure_usize(LowerContext* ctx, ILValue val);
void emit_bounds_check(LowerContext* ctx, ILValue index, ILValue length);
const ILType* guess_type_internal(LowerContext* ctx, const Expression* expr, const ILType* expected_type);
Symbol* symbol_lookup_ctx(LowerContext* ctx, const char* name);
bool match_type_param(LowerContext* ctx, const ILType* param_type, const ILType* arg_type, const char* param_name, const ILType** out_arg);
void add_jump(LowerContext* ctx, ILBasicBlock* target);
ILTypeDef* find_type_def(LowerContext* ctx, const char* name);
const FunctionDecl* find_method_decl(const SurfaceModule* smod, const char* type_name, const char* method_name, const ImplDecl** out_impl);
int find_field_index(const ILTypeDef* def, const char* name);
void emit_drop_dispatch(LowerContext* ctx, ILValue val);
bool is_mut_borrow(const ILType* t);
void verify_no_type_cycles(ILModule* mod, DiagnosticReport* report);

#endif
