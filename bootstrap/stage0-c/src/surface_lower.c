#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include "il_print.h"
#include "surface_lower.h"
#include "surface_lower_internal.h"
#include "surface_scope.h"
#include "il_instr.h"
#include "string_table.h"
#include "diagnostics.h"


void lower_context_cleanup(LowerContext* ctx);
ILValue resolve_capture(LowerContext* ctx, const Symbol* sym);

void mark_moved(LowerContext* ctx, uint32_t id) {
    if (id == 0) return;
    if (id >= ctx->value_moved_capacity) {
        uint32_t new_cap = ctx->value_moved_capacity == 0 ? 64 : ctx->value_moved_capacity * 2;
        while (id >= new_cap) new_cap *= 2;
        ctx->value_moved = realloc(ctx->value_moved, new_cap * sizeof(bool));
        memset(ctx->value_moved + ctx->value_moved_capacity, 0, (new_cap - ctx->value_moved_capacity) * sizeof(bool));
        ctx->value_moved_capacity = new_cap;
    }
    ctx->value_moved[id] = true;

    // Also mark in parent context if it exists, as the ID is global to the ILModule
    if (ctx->parent_ctx) {
        mark_moved(ctx->parent_ctx, id);
    }
}

bool is_moved(LowerContext* ctx, uint32_t id) {
    if (id == 0 || id >= ctx->value_moved_capacity) return false;
    return ctx->value_moved[id];
}

bool* save_moved_state(const LowerContext* ctx, uint32_t* out_cap) {
    *out_cap = ctx->value_moved_capacity;
    if (ctx->value_moved_capacity == 0) return NULL;
    bool* copy = malloc(ctx->value_moved_capacity * sizeof(bool));
    if (copy) memcpy(copy, ctx->value_moved, ctx->value_moved_capacity * sizeof(bool));
    return copy;
}

void restore_moved_state(LowerContext* ctx, bool* state, uint32_t cap) {
    if (ctx->value_moved) free(ctx->value_moved);
    ctx->value_moved = state;
    ctx->value_moved_capacity = cap;
}

void scope_push(LowerContext* ctx) {
    ctx->current_scope = scope_create(ctx->current_scope, ctx->current_func);
    if (ctx->current_scope) {
        ctx->current_scope->temporary_start = ctx->temporary_count;
    }
}

ILValue lower_block(LowerContext* ctx, const BlockExpr* block, const ILType* expected_type, ILValue dest_ptr);
bool block_is_terminated(ILBasicBlock* block);

/* Free a substitution chain built during monomorphization. */
static void substitutions_free(Substitution* head) {
    while (head) {
        Substitution* next = (Substitution*)head->next;
        free(head);
        head = next;
    }
}

/* Initialise *ctx and assign SSA IDs for all implicit and explicit parameters.
 * Populates ctx->sret_id, ctx->env_ptr, and adds each user param to the scope.
 * Must be called after the ILFunction skeleton (including params) is fully built. */
static void init_lower_context(LowerContext* ctx,
                                const SurfaceModule* smod, ILModule* ilmod,
                                DiagnosticReport* report, bool release_mode,
                                const FunctionDecl* sfn, const ImplDecl* simpl,
                                ILFunction* ifn, Substitution* substs) {
    memset(ctx, 0, sizeof(LowerContext));
    ctx->release_mode        = release_mode;
    ctx->current_func        = ifn;
    ctx->current_surface_func = sfn;
    ctx->current_surface_impl = simpl;
    ctx->module              = ilmod;
    ctx->surface_mod         = smod;
    ctx->report              = report;
    ctx->current_file        = sfn->file_path;
    ctx->current_source      = smod->source;
    ctx->next_value_id       = 1;
    ctx->next_block_id       = 1;
    ctx->current_substs      = substs;

    ILBasicBlock* entry = create_block(ctx);
    ctx->current_block = entry;

    scope_push(ctx);
    if (ifn->is_sret) {
        ctx->sret_id = ctx->next_value_id++;
    }
    if (il_func_needs_env_ptr(ifn)) {
        ctx->env_ptr = (ILValue){ .id = ctx->next_value_id++,
                                  .type = il_type_ptr(il_type_unit(), REGION_STATIC, false) };
    }
    for (uint32_t k = 0; k < sfn->param_count; k++) {
        const ILType* orig_pty = lower_type(smod, ilmod, report, release_mode,
                                            sfn->params[k].type, substs);
        const ILType* ptype = ifn->param_types[k + il_func_user_param_offset(ifn)];
        ILValue pval = { .id = ctx->next_value_id++, .type = ptype };

        bool is_lvalue = !ifn->is_extern && requires_pass_by_ref(ilmod, orig_pty);
        if (sfn->params[k].is_mutable || (!is_lvalue && is_aggregate_type_layout(orig_pty))) {
            const ILType* ptr_ty = il_type_ptr(ptype, REGION_LOCAL, true);
            ILValue ptr = emit(ctx, il_build_alloc(REGION_LOCAL, ptype, ptr_ty, (ILValue){0}));
            emit_void(ctx, il_build_store(ptr, pval));
            symbol_add_ctx(ctx, sfn->params[k].name, ptr, true);
        } else {
            symbol_add_ctx(ctx, sfn->params[k].name, pval, is_lvalue);
        }
    }
}

/* If fn's return type requires pass-by-reference, convert it to an sret function:
 * set is_sret, stash the original return type in sret_type, change the declared
 * return to unit, and prepend a Ptr<ret, 'local, mut> parameter. */
static void apply_sret_if_needed(const ILModule* mod, ILFunction* fn) {
    if (!requires_pass_by_ref(mod, fn->return_type)) return;
    fn->is_sret = true;
    fn->sret_type = fn->return_type;
    fn->return_type = il_type_unit();
    il_func_add_param(fn, il_type_ptr(fn->sret_type, REGION_LOCAL, true));
}

ILFunction* monomorphize_function(const SurfaceModule* smod, ILModule* ilmod, DiagnosticReport* report, bool release_mode, const FunctionDecl* sfn, const ILType ** type_args, const char* mangled_name, const Substitution* initial_substs) {
    ILFunction* existing = (ILFunction*)il_mod_get_func_by_name(ilmod, mangled_name);
    if (existing) return existing;

    // 1. Build substitutions
    Substitution* head = NULL;
    
    // Start with initial substitutions (e.g. from an impl block)
    const Substitution* is = initial_substs;
    while (is) {
        Substitution* n = calloc(1, sizeof(Substitution));
        if (!n) break;
        n->name = is->name;
        n->type = is->type;
        n->next = head;
        head = n;
        is = is->next;
    }
    
    // Add function-level type arguments
    for (uint32_t j = 0; j < sfn->type_param_count; j++) {
        const char* bound = sfn->type_bounds ? sfn->type_bounds[j] : NULL;
        const ILType* arg_ty = type_args ? type_args[j] : il_type_unit();

        if (bound && !type_implements_trait(smod, arg_ty, bound, initial_substs)) {
            char type_buf[128];
            il_type_print(arg_ty, type_buf, sizeof(type_buf));
            diag_emit(report, DIAG_ERROR, (SourceLocation){.file_path = sfn->file_path, .line = sfn->line, .col = sfn->col},
                "Type '%s' does not implement trait '%s' required by '%s'", 
                type_buf, bound, sfn->type_params[j]);
        }

        Substitution* n = calloc(1, sizeof(Substitution));
        if (!n) break;
        n->name = sfn->type_params[j];
        n->bound = bound;
        n->type = arg_ty;
        n->next = head;
        head = n;
    }

    // 2. Create skeleton
    const ILType* ret_type = sfn->return_type ? lower_type(smod, ilmod, report, release_mode, sfn->return_type, head) : il_type_unit();
    ILFunction* ifn = il_func_create((uint32_t)(ilmod->function_count + 1), mangled_name, ret_type, sfn->is_pub, sfn->is_must_use, sfn->file_path);
    ifn->is_extern = sfn->is_extern;
    ifn->is_variadic = sfn->is_variadic;
    apply_sret_if_needed(ilmod, ifn);
    if (il_func_needs_env_ptr(ifn)) {
        il_func_add_param(ifn, il_type_ptr(il_type_unit(), REGION_STATIC, false));
    }
    il_mod_add_func(ilmod, ifn);

    for (uint32_t k = 0; k < sfn->param_count; k++) {
        const Param* sp = &sfn->params[k];
        const ILType* pty = lower_type(smod, ilmod, report, release_mode, sp->type, head);
        if (!ifn->is_extern && requires_pass_by_ref(ilmod, pty)) {
            pty = il_type_ptr(pty, REGION_LOCAL, true);
        }
        il_func_add_param(ifn, pty);
    }

    // 3. Lower body. An extern has no body: its IL function is only a declaration, exactly as it
    // is for a module's non-generic functions, which the other body-lowering path skips the same
    // way (`if (sfn->is_extern) continue;`). Lowering one here synthesized a `return unit` for the
    // absent body and then rejected it against a `-> never` return type, which is how
    // `pub extern fn zoril_abort() -> never;` failed whenever a call reached it through this path.
    if (sfn->is_extern) {
        substitutions_free(head);
        return ifn;
    }

    LowerContext mctx;
    init_lower_context(&mctx, smod, ilmod, report, release_mode, sfn, NULL, ifn, head);

    ILValue dest = {0};
    if (ifn->is_sret) {
        dest = (ILValue){ .id = mctx.sret_id, .type = il_type_ptr(ifn->sret_type, REGION_LOCAL, true) };
    }
    ILValue res = lower_block(&mctx, sfn->body, ifn->is_sret ? ifn->sret_type : ifn->return_type, dest);

    uint32_t exempt_id = 0;
    if (res.type) exempt_id = res.id;
    run_all_defers(&mctx, exempt_id);
    scope_pop(&mctx, exempt_id);

    if (!block_is_terminated(mctx.current_block)) {
        if (res.type) {
            if (ifn->is_sret && res.id == mctx.sret_id) {
                ILValue unit_res = { .id = 0, .type = il_type_unit() };
                emit_return(&mctx, unit_res);
            } else {
                const ILType* effective_ret = ifn->is_sret ? ifn->sret_type : ifn->return_type;
                ILValue assigned = ensure_assignable(&mctx, res, effective_ret);
                res = assigned;
                if (ifn->is_sret) {
                    const ILType* ptr_ty = il_type_ptr(ifn->sret_type, REGION_LOCAL, true);
                    ILValue sret_ptr = { .id = mctx.sret_id, .type = ptr_ty };
                    emit_void(&mctx, il_build_store(sret_ptr, res));
                    if (!il_type_is_copy_mod(mctx.module, res.type)) mark_moved(&mctx, res.id);
                    ILValue unit_res = { .id = 0, .type = il_type_unit() };
                    emit_return(&mctx, unit_res);
                } else {
                    emit_return(&mctx, res);
                }
            }
        } else {
            ILValue unit_res = { .id = 0, .type = il_type_unit() };
            emit_return(&mctx, unit_res);
        }
    }

    lower_context_cleanup(&mctx);
    substitutions_free(head);
    return ifn;
}
ILValue lower_block(LowerContext* ctx, const BlockExpr* block, const ILType* expected_type, ILValue dest_ptr);
ILValue lower_if_expr(LowerContext* ctx, const IfExpr* if_expr, const ILType* expected_type, ILValue dest_ptr);
ILValue lower_lvalue(LowerContext* ctx, const Expression* expr, bool is_mut);


void symbol_add_ctx(LowerContext* ctx, const char* name, ILValue value, bool is_lvalue) {
    symbol_add(ctx->current_scope, name, value, is_lvalue);
    if (ctx->current_func && value.id != 0) {
        il_func_set_val_name(ctx->current_func, value.id, name);
    }
}


ILBasicBlock* create_block(LowerContext* ctx) {
    ILBasicBlock* block = il_block_create(ctx->next_block_id++);
    il_func_add_block(ctx->current_func, block);
    return block;
}

// emit assigns the next value ID to instr, appends it to the current block,
// and returns a fresh ILValue owning a copy of the result type.

ILValue emit(LowerContext* ctx, ILInstruction* instr) {
    if (!instr || (instr->result_type == NULL && instr->opcode != IL_OP_VARIANT_MATCH)) {
        if (!ctx->current_block || block_is_terminated(ctx->current_block) || (ctx->report && ctx->report->has_errors)) {
            // Error already reported or in dead code, don't ICE, just return a dummy value
            if (instr) il_instr_free(instr);
            return (ILValue){0};
        }
        if (ctx->report) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "Internal error: IL instruction construction failed");
            if (instr) il_instr_free(instr);
            return (ILValue){0};
        }
        ICE("IL instruction construction failed");
    }
    if (!ctx->current_block || block_is_terminated(ctx->current_block)) {
        il_instr_free(instr);
        return (ILValue){ .id = 0, .type = NULL };
    }
    instr->line = (uint16_t)ctx->current_line;
    instr->col = (uint8_t)ctx->current_col;
    if (instr->result_id == 0) {
        instr->result_id = ctx->next_value_id++;
    }
    il_block_add_instr(ctx->current_block, instr);
    
    if (instr->result_type && instr->result_type->kind == IL_TY_NEVER) {
        ctx->current_block = NULL;
    }

    // Instruction OWNS its result_type.
    // 'emit' returns an OWNED copy. The caller IS responsible for freeing it.
    ILValue res = { .id = instr->result_id, .type = instr->result_type };

    // Track as temporary if it's a non-copy value or a pointer borrowing from a local variable (SSA ID).
    // EXCEPT for linear resources (fd, async_context) which must be explicitly closed.
    bool needs_tracking = false;
    if (res.type) {
        if (!il_type_is_copy_mod(ctx->module, res.type)) {
            if (res.type->kind != IL_TY_FD && res.type->kind != IL_TY_ASYNC_CONTEXT) {
                needs_tracking = true;
            }
        } else if (res.type->kind == IL_TY_PTR) {
            if (is_ssa_region(res.type->as.ptr.region_id)) needs_tracking = true;
        } else if (res.type->kind == IL_TY_BOX) {
            if (is_ssa_region(res.type->as.box.region_id)) needs_tracking = true;
        } else if (res.type->kind == IL_TY_SLICE) {
            if (is_ssa_region(res.type->as.slice.region_id)) needs_tracking = true;
        }
    }

    if (needs_tracking) {
        if (ctx->temporary_count >= ctx->temporary_capacity) {
            uint32_t new_cap = ctx->temporary_capacity == 0 ? 32 : ctx->temporary_capacity * 2;
            ctx->temporaries = realloc(ctx->temporaries, new_cap * sizeof(ILValue));
            ctx->temporary_capacity = new_cap;
        }
        // The temporaries list gets its OWN copy of the type to manage auto-dropping.
        ctx->temporaries[ctx->temporary_count++] = (ILValue){ .id = res.id, .type = res.type };
    }

    return res;
}

void emit_void(LowerContext* ctx, ILInstruction* instr) {
    emit(ctx, instr);
    
}
void emit_diag_at(LowerContext* ctx, DiagnosticSeverity severity, const Expression* expr, const char* fmt, ...) {
    if (!ctx || !ctx->report) return;
    va_list args;
    va_start(args, fmt);
    SourceLocation loc = {
        .file_path = expr && expr->file_path ? expr->file_path : ctx->current_file,
        .source = expr && expr->source ? expr->source : ctx->current_source,
        .line = expr ? expr->line : ctx->current_line,
        .col = expr ? expr->col : ctx->current_col,
        .offset = expr ? expr->offset : ctx->current_offset,
        .length = expr ? expr->length : 0
    };
    
    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    
    diag_emit(ctx->report, severity, loc, "%s", buf);
}

void emit_stmt_diag_at(LowerContext* ctx, DiagnosticSeverity severity, const Statement* stmt, const char* fmt, ...) {
    if (!ctx || !ctx->report) return;
    va_list args;
    va_start(args, fmt);
    SourceLocation loc = {
        .file_path = stmt && stmt->file_path ? stmt->file_path : ctx->current_file,
        .source = stmt && stmt->source ? stmt->source : ctx->current_source,
        .line = stmt ? stmt->line : ctx->current_line,
        .col = stmt ? stmt->col : ctx->current_col,
        .offset = stmt ? stmt->offset : ctx->current_offset,
        .length = stmt ? stmt->length : 0
    };
    
    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    
    diag_emit(ctx->report, severity, loc, "%s", buf);
}

void emit_return(LowerContext* ctx, ILValue val) {
    if (!ctx->current_block) {
        return;
    }
    if (ctx->current_func->is_sret) {
        // If val is already the sret pointer itself (struct was written directly into it),
        // skip the ensure_assignable + store — the struct is already in place.
        if (val.id == ctx->sret_id) {
            ILValue unit_val = { .id = 0, .type = il_type_unit() };
            ILInstruction* ret = il_build_return(unit_val);
            if (ret) {
                ret->line = (uint16_t)ctx->current_line;
                ret->col = (uint8_t)ctx->current_col;
                il_block_add_instr(ctx->current_block, ret);
            }
            return;
        }
        ILValue assigned = ensure_assignable(ctx, val, ctx->current_func->sret_type);
        const ILType* ptr_ty = il_type_ptr(ctx->current_func->sret_type, REGION_LOCAL, true);
        ILValue sret_ptr = { .id = ctx->sret_id, .type = ptr_ty };
        ILInstruction* store = il_build_store(sret_ptr, assigned);
        if (store) {
            store->line = (uint16_t)ctx->current_line;
            store->col = (uint8_t)ctx->current_col;
            il_block_add_instr(ctx->current_block, store);
        }

        ILValue unit_val = { .id = 0, .type = il_type_unit() };
        ILInstruction* ret = il_build_return(unit_val);
        if (ret) {
            ret->line = (uint16_t)ctx->current_line;
            ret->col = (uint8_t)ctx->current_col;
            il_block_add_instr(ctx->current_block, ret);
        }
    } else {
        ILValue assigned = ensure_assignable(ctx, val, ctx->current_func->return_type);
        ILInstruction* ret = il_build_return(assigned);
        if (ret) {
            ret->line = (uint16_t)ctx->current_line;
            ret->col = (uint8_t)ctx->current_col;
            il_block_add_instr(ctx->current_block, ret);
        }
    }
}

const ILType* unify_numeric_types(const ILType* a, const ILType* b) {
    if (!a && !b) return il_type_u64();
    if (!a) return b;
    if (!b) return a;
    if (!is_numeric_type(a) || !is_numeric_type(b)) return a;
    
    if (numeric_type_rank(a->kind) >= numeric_type_rank(b->kind)) {
        return a;
    } else {
        return b;
    }
}

static uint32_t get_region_id(const ILType* t) {
    if (!t) return 0;
    if (t->kind == IL_TY_PTR) return t->as.ptr.region_id;
    if (t->kind == IL_TY_BOX) return t->as.box.region_id;
    if (t->kind == IL_TY_SLICE) return t->as.slice.region_id;
    return 0;
}

static const ILType* with_region_id(const ILType* t, uint32_t region_id) {
    if (!t) return NULL;
    if (t->kind == IL_TY_PTR) return il_type_ptr(t->as.ptr.pointee, region_id, t->as.ptr.is_mut);
    if (t->kind == IL_TY_BOX) return il_type_box(t->as.box.pointee, region_id, t->as.box.is_mut);
    if (t->kind == IL_TY_SLICE) return il_type_slice(t->as.slice.element, region_id, t->as.slice.is_mut);
    return t;
}

ILValue ensure_assignable(LowerContext* ctx, ILValue val, const ILType* target) {
    if (!val.type || !target) return val;
    if (!ctx) {
        if (il_type_eq(val.type, target)) return (ILValue){ .id = val.id, .type = target };
        return val;
    }
    
    if (il_type_eq(val.type, target) || il_type_structurally_eq(val.type, target)) {
        return (ILValue){ .id = val.id, .type = target };
    }

    if (val.type->kind == IL_TY_SLICE && target->kind == IL_TY_SLICE) {
        if (val.type->as.slice.is_mut == target->as.slice.is_mut &&
            il_type_structurally_eq(val.type->as.slice.element, target->as.slice.element) &&
            il_region_outlives(val.type->as.slice.region_id, target->as.slice.region_id)) {
            // Safe to use longer-lived region where shorter-lived is expected.
            // We return val.type (longer-lived) to avoid verifier errors if this is later returned.
            return (ILValue){ .id = val.id, .type = val.type };
        }
    }
    if (val.type->kind == IL_TY_PTR && target->kind == IL_TY_PTR) {
        if (val.type->as.ptr.is_mut == target->as.ptr.is_mut &&
            il_type_structurally_eq(val.type->as.ptr.pointee, target->as.ptr.pointee) &&
            il_region_outlives(val.type->as.ptr.region_id, target->as.ptr.region_id)) {
            return (ILValue){ .id = val.id, .type = val.type };
        }
    }

    // ABI: Aggregates are often passed as pointers but used as values in IL.
    if (val.type->kind == IL_TY_PTR && (il_type_eq(val.type->as.ptr.pointee, target) || il_type_structurally_eq(val.type->as.ptr.pointee, target))) {
        if (requires_pass_by_ref(ctx->module, target)) {
            // Do not cast the value's type. This keeps it as a pointer for move tracking of the pointer itself (which is trivial),
            // but wait, if target is an aggregate, the lowerer wants an aggregate type.
            // Actually, if the target is an aggregate, ensure_assignable should return an aggregate so type checks pass later.
            return (ILValue){ .id = val.id, .type = target };
        }
    }
    // ABI reverse: aggregate val (whose SSA ID is a pointer, or an actual aggregate value) assigned to a PtrMut param.
    if (target->kind == IL_TY_PTR && is_aggregate_type_layout(val.type) &&
        requires_pass_by_ref(ctx->module, val.type) &&
        il_type_is_assignable(val.type, target->as.ptr.pointee)) {
        // Return val UNMODIFIED so that it retains its aggregate type.
        // This ensures `!il_type_is_copy_mod(val.type)` correctly identifies it as a move,
        // and `mark_moved` is called on the aggregate. The verifier will allow this assignment.
        return val;
    }

    // Special case: linear resources (fd, async_context) are often structurally equivalent
    // even if not strictly il_type_eq (e.g. if one has different capabilities but we allow assignment).
    // If they are assignable, we should avoid a move if they are already "the same thing" logically.
    if ((val.type->kind == IL_TY_FD && target->kind == IL_TY_FD) ||
        (val.type->kind == IL_TY_ASYNC_CONTEXT && target->kind == IL_TY_ASYNC_CONTEXT)) {
        if (il_type_is_assignable(val.type, target)) {
            return (ILValue){ .id = val.id, .type = target };
        }
    }
    
    // never (bottom type) coerces to any type
    if (val.type->kind == IL_TY_NEVER) {
        if (val.id == 0 || il_type_eq(val.type, target) || !ctx->current_block || block_is_terminated(ctx->current_block)) {
            return (ILValue){ .id = val.id, .type = target };
        }
        ILInstruction* conv = il_build_bitcast(val, target);
        return emit(ctx, conv);
    }
    
    // 1. Array to Slice coercion
    if (target->kind == IL_TY_SLICE || (target->kind == IL_TY_PTR && target->as.ptr.pointee->kind == IL_TY_SLICE)) {
        const ILType* slice_ty = (target->kind == IL_TY_SLICE) ? target : target->as.ptr.pointee;
        
        // Handle Slice value to Slice pointer
        if (val.type->kind == IL_TY_SLICE && target->kind == IL_TY_PTR && target->as.ptr.pointee->kind == IL_TY_SLICE) {
            const ILType* slice_ptr_ty = il_type_ptr(val.type, REGION_LOCAL, true);
            ILValue slice_ptr = emit(ctx, il_build_alloc(REGION_LOCAL, val.type, slice_ptr_ty, (ILValue){0}));
            emit_void(ctx, il_build_store(slice_ptr, val));
            if (!il_type_is_copy_mod(ctx->module, val.type)) mark_moved(ctx, val.id);
            return slice_ptr;
        }

        if (val.type->kind == IL_TY_ARRAY) {
            const ILType* array_ptr_ty = il_type_ptr(val.type, REGION_LOCAL, true);
            ILValue array_ptr = emit(ctx, il_build_alloc(REGION_LOCAL, val.type, array_ptr_ty, (ILValue){0}));
            emit_void(ctx, il_build_store(array_ptr, val));
            if (!il_type_is_copy_mod(ctx->module, val.type)) mark_moved(ctx, val.id);
            
            const ILType* u64_ty = il_type_u64();
            ILValue len_val = emit(ctx, il_build_const(val.type->as.array.length, u64_ty));
            ILValue slice_val = emit(ctx, il_build_slice_construct(array_ptr, len_val, slice_ty));
            
            
            if (target->kind == IL_TY_PTR) {
                const ILType* slice_ptr_res_ty = il_type_ptr(slice_val.type, REGION_LOCAL, true);
                ILValue slice_ptr_res = emit(ctx, il_build_alloc(REGION_LOCAL, slice_val.type, slice_ptr_res_ty, (ILValue){0}));
                emit_void(ctx, il_build_store(slice_ptr_res, slice_val));
                if (!il_type_is_copy_mod(ctx->module, slice_val.type)) mark_moved(ctx, slice_val.id);
                return slice_ptr_res;
            }
            return slice_val;
        }
        
        if (val.type->kind == IL_TY_PTR && val.type->as.ptr.pointee->kind == IL_TY_ARRAY) {
            const ILType* u64_ty = il_type_u64();
            ILValue len_val = emit(ctx, il_build_const(val.type->as.ptr.pointee->as.array.length, u64_ty));
            ILValue slice_val = emit(ctx, il_build_slice_construct(val, len_val, slice_ty));
            
            
            if (target->kind == IL_TY_PTR) {
                const ILType* slice_ptr_res_ty = il_type_ptr(slice_val.type, REGION_LOCAL, true);
                ILValue slice_ptr_res = emit(ctx, il_build_alloc(REGION_LOCAL, slice_val.type, slice_ptr_res_ty, (ILValue){0}));
                emit_void(ctx, il_build_store(slice_ptr_res, slice_val));
                if (!il_type_is_copy_mod(ctx->module, slice_val.type)) mark_moved(ctx, slice_val.id);
                return slice_ptr_res;
            }
            return slice_val;
        }
    }

    // 2. Pointer coercion
    if (is_pointer_type(ctx->module, val.type) && is_pointer_type(ctx->module, target)) {
        // When the source is a non-copy Box, the bitcast transfers ownership — mark it moved.
        bool src_is_box = (val.type->kind == IL_TY_BOX);
        
        uint32_t src_rid = get_region_id(val.type);
        uint32_t tgt_rid = get_region_id(target);
        const ILType* final_target = target;
        if (is_ssa_region(src_rid) && (tgt_rid == REGION_LOCAL || tgt_rid == 0)) {
            final_target = with_region_id(target, src_rid);
        }

        if (il_type_eq(val.type, final_target)) {
            return (ILValue){ .id = val.id, .type = val.type };
        }
        
        bool ok = il_type_is_assignable(val.type, final_target);
        if (!ok) {
            // Special case: allow bitcasting pointers to different structs (for closures/envs)
            // or unit (void*), but ONLY if the indirection level matches.
            uint32_t s_level = il_type_get_indirection_level(val.type);
            uint32_t t_level = il_type_get_indirection_level(final_target);
            if (s_level == t_level) {
                ok = true;
            }
        }

        if (ok) {
            if (il_type_eq(val.type, final_target)) {
                return (ILValue){ .id = val.id, .type = val.type };
            }
            ILValue res = emit(ctx, il_build_bitcast(val, final_target));
            if (src_is_box) mark_moved(ctx, val.id);
            return res;
        }
    } else if (il_type_is_assignable(val.type, target)) {
        if (il_type_eq(val.type, target)) {
            return (ILValue){ .id = val.id, .type = val.type };
        }
        ILInstruction* conv = il_build_move(val);
        if (conv) {
            if (conv->opcode == IL_OP_MOVE) {
                conv->result_type = target;
            }
            ILValue result = emit(ctx, conv);
            mark_moved(ctx, val.id);  // prevent double-drop: move consumed val
            return result;
        }
    }

    // 3. Borrowing a Box
    if (val.type->kind == IL_TY_PTR && val.type->as.ptr.pointee && val.type->as.ptr.pointee->kind == IL_TY_BOX && target->kind == IL_TY_PTR) {
        // id:1000 fix: ONLY auto-deref if the target is NOT a pointer to a pointer.
        uint32_t t_level = il_type_get_indirection_level(target);
        if (t_level == 1 && il_type_is_assignable(val.type->as.ptr.pointee->as.box.pointee, target->as.ptr.pointee)) {
            const ILType* ptr_ptr_ty = il_type_ptr(target, val.type->as.ptr.region_id, val.type->as.ptr.is_mut);
            ILValue casted_ptr = emit(ctx, il_build_bitcast(val, ptr_ptr_ty));
            ILValue loaded = emit(ctx, il_build_load(casted_ptr));
            return loaded;
        }
    }
    
    // 4. Coercing a Box to a Pointer
    if (val.type->kind == IL_TY_BOX && target->kind == IL_TY_PTR) {
        if (il_type_is_assignable(val.type->as.box.pointee, target->as.ptr.pointee)) {
            ILValue res = emit(ctx, il_build_bitcast(val, target));
            mark_moved(ctx, val.id);  // Box ownership transferred to raw ptr
            return res;
        }
    }
    
    // 5. Auto-load
    if (val.type->kind == IL_TY_PTR || val.type->kind == IL_TY_BOX) {
        const ILType* pointee = (val.type->kind == IL_TY_PTR) ? val.type->as.ptr.pointee : val.type->as.box.pointee;
        if (!is_pointer_type(ctx->module, target) && il_type_is_assignable(pointee, target)) {
            ILValue loaded = emit(ctx, il_build_load(val));
            return ensure_assignable(ctx, loaded, target);
        }
    }

    // 6. Numeric conversions
    if (is_numeric_type(val.type) && is_numeric_type(target)) {
        if (il_type_is_assignable(val.type, target)) {
            if (il_type_eq(val.type, target)) {
                return (ILValue){ .id = val.id, .type = val.type };
            }
            ILInstruction* mv = il_build_move(val);
            if (mv) {
                mv->result_type = target;
                ILValue res = emit(ctx, mv);
                mark_moved(ctx, val.id);
                return res;
            }
        } else {
            return emit(ctx, il_build_bitcast(val, target));
        }
    }
    
    char s_buf[128], t_buf[128];
    il_type_print(val.type, s_buf, sizeof(s_buf));
    il_type_print(target, t_buf, sizeof(t_buf));
    emit_diag_at(ctx, DIAG_ERROR, NULL, "type mismatch: expected %s, found %s", t_buf, s_buf);

    return (ILValue){ .id = val.id, .type = val.type };
}
ILGlobal* find_global(const ILModule* mod, const char* name) {
    if (!mod) return NULL;
    for (uint32_t i = 0; i < mod->global_count; i++) {
        if (strcmp(mod->globals[i]->name, name) == 0) {
            return mod->globals[i];
        }
    }
    return NULL;
}

const FunctionDecl* find_method_decl(const SurfaceModule* smod, const char* type_name, const char* method_name, const ImplDecl** out_impl) {
    if (!smod || !type_name || !method_name) return NULL;
    for (uint32_t i = 0; i < smod->impl_count; i++) {
        const char* target = smod->impls[i]->target_name;
        bool match = false;
        if (strcmp(target, type_name) == 0) {
            match = true;
        } else {
            // Case 1: target is generic like "Foo_T", type_name is base "Foo"
            const char* t_underscore = strchr(target, '_');
            if (t_underscore) {
                size_t base_len = (size_t)(t_underscore - target);
                if (strncmp(target, type_name, base_len) == 0 && type_name[base_len] == '\0') {
                    match = true;
                }
            }
            // Case 2: type_name is monomorphized like "Foo_i32", target is base "Foo"
            if (!match) {
                const char* n_underscore = strchr(type_name, '_');
                if (n_underscore) {
                    size_t base_len = (size_t)(n_underscore - type_name);
                    if (strncmp(target, type_name, base_len) == 0 && target[base_len] == '\0') {
                        match = true;
                    }
                }
            }
        }

        if (match) {
            for (uint32_t j = 0; j < smod->impls[i]->method_count; j++) {
                if (strcmp(smod->impls[i]->methods[j]->name, method_name) == 0) {
                    if (out_impl) *out_impl = smod->impls[i];
                    return smod->impls[i]->methods[j];
                }
            }
        }
    }
    return NULL;
}

ILFunction* monomorphize_method(const SurfaceModule* smod, ILModule* ilmod, DiagnosticReport* report, bool release_mode, const ImplDecl* simpl, const FunctionDecl* sfn, const ILType ** type_args, const char* mangled_name) {
    ILFunction* existing = (ILFunction*)il_mod_get_func_by_name(ilmod, mangled_name);
    if (existing) return existing;

    // 1. Find the surface TypeDef to get parameter names for the STRUCT
    const char* base_target_name = simpl->target_name;
    const char* underscore = strchr(base_target_name, '_');
    char base_buf[128];
    if (underscore) {
        size_t len = (size_t)(underscore - base_target_name);
        if (len >= sizeof(base_buf)) len = sizeof(base_buf) - 1;
        strncpy(base_buf, base_target_name, len);
        base_buf[len] = '\0';
        base_target_name = base_buf;
    }

    const TypeDef* styp = NULL;
    for (uint32_t i = 0; i < smod->type_def_count; i++) {
        const char* name = (smod->type_defs[i]->kind == TYPE_DEF_STRUCT) ? smod->type_defs[i]->as.struct_decl->name : smod->type_defs[i]->as.enum_decl->name;
        if (strcmp(name, base_target_name) == 0) {
            styp = smod->type_defs[i];
            break;
        }
    }
    if (!styp) return NULL;

    uint32_t struct_param_count = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_param_count : styp->as.enum_decl->type_param_count;
    char** struct_param_names = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_params : styp->as.enum_decl->type_params;
    char** struct_param_bounds = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_bounds : styp->as.enum_decl->type_bounds;

    // 2. Build substitutions for Struct, Trait, AND Method
    Substitution* head = NULL;
    uint32_t current_offset = 0;

    // 2.1 Struct substitutions
    for (uint32_t i = 0; i < struct_param_count; i++) {
        const char* bound = struct_param_bounds ? struct_param_bounds[i] : NULL;
        const ILType* arg_ty = type_args[current_offset + i];

        if (bound && !type_implements_trait(smod, arg_ty, bound, NULL)) {
            char type_buf[128];
            il_type_print(arg_ty, type_buf, sizeof(type_buf));
            diag_emit(report, DIAG_ERROR, (SourceLocation){.file_path = sfn->file_path, .line = sfn->line, .col = sfn->col},
                "Type '%s' does not implement trait '%s' required by struct/enum '%s' parameter '%s'", 
                type_buf, bound, base_target_name, struct_param_names[i]);
        }

        Substitution* s = calloc(1, sizeof(Substitution));
        if (!s) abort();
        s->name = struct_param_names[i];
        s->bound = bound;
        s->type = arg_ty;
        s->next = head;
        head = s;
    }
    current_offset += struct_param_count;

    // 2.2 Trait substitutions (if this is a trait impl)
    if (simpl->trait_name) {
        const TraitDecl* trait = NULL;
        for (uint32_t i = 0; i < smod->trait_count; i++) {
            const char* tname = smod->traits[i]->name;
            bool trait_match = false;
            if (strcmp(tname, simpl->trait_name) == 0) {
                trait_match = true;
            } else {
                const char* t_underscore = strchr(simpl->trait_name, '_');
                if (t_underscore) {
                    size_t base_len = (size_t)(t_underscore - simpl->trait_name);
                    if (strncmp(simpl->trait_name, tname, base_len) == 0 && tname[base_len] == '\0') {
                        trait_match = true;
                    }
                }
            }

            if (trait_match) {
                trait = smod->traits[i];
                break;
            }
        }
        if (trait) {
            for (uint32_t i = 0; i < trait->type_param_count; i++) {
                const char* bound = trait->type_bounds ? trait->type_bounds[i] : NULL;
                const ILType* arg_ty = type_args[current_offset + i];

                if (bound && !type_implements_trait(smod, arg_ty, bound, head)) {
                    char type_buf[128];
                    il_type_print(arg_ty, type_buf, sizeof(type_buf));
                    diag_emit(report, DIAG_ERROR, (SourceLocation){.file_path = sfn->file_path, .line = sfn->line, .col = sfn->col},
                        "Type '%s' does not implement trait '%s' required by trait '%s' parameter '%s'", 
                        type_buf, bound, trait->name, trait->type_params[i]);
                }

                Substitution* s = calloc(1, sizeof(Substitution));
                if (!s) abort();
                s->name = trait->type_params[i];
                s->bound = bound;
                s->type = arg_ty;
                s->next = head;
                head = s;
            }
            current_offset += trait->type_param_count;
        }
    }

    // 2.3 Method substitutions
    for (uint32_t i = 0; i < sfn->type_param_count; i++) {
        const char* bound = sfn->type_bounds ? sfn->type_bounds[i] : NULL;
        const ILType* arg_ty = type_args[current_offset + i];

        if (bound && !type_implements_trait(smod, arg_ty, bound, head)) {
            char type_buf[128];
            il_type_print(arg_ty, type_buf, sizeof(type_buf));
            diag_emit(report, DIAG_ERROR, (SourceLocation){.file_path = sfn->file_path, .line = sfn->line, .col = sfn->col},
                "Type '%s' does not implement trait '%s' required by method '%s' parameter '%s'", 
                type_buf, bound, sfn->name, sfn->type_params[i]);
        }

        Substitution* s = calloc(1, sizeof(Substitution));
        if (!s) abort();
        s->name = sfn->type_params[i];
        s->bound = bound;
        s->type = arg_ty;
        s->next = head;
        head = s;
    }

    // 3. Create skeleton and lower body
    const ILType* ret_type = sfn->return_type ? lower_type(smod, ilmod, report, release_mode, sfn->return_type, head) : il_type_unit();
    ILFunction* ifn = il_func_create((uint32_t)(ilmod->function_count + 1), mangled_name, ret_type, sfn->is_pub, sfn->is_must_use, sfn->file_path);
    ifn->is_variadic = sfn->is_variadic;
    apply_sret_if_needed(ilmod, ifn);
    if (il_func_needs_env_ptr(ifn)) {
        il_func_add_param(ifn, il_type_ptr(il_type_unit(), REGION_STATIC, false));
    }
    
    for (uint32_t k = 0; k < sfn->param_count; k++) {
        const ILType* pty = lower_type(smod, ilmod, report, release_mode, sfn->params[k].type, head);
        if (!ifn->is_extern && requires_pass_by_ref(ilmod, pty)) {
            pty = il_type_ptr(pty, REGION_LOCAL, true);
        }
        il_func_add_param(ifn, pty);
    }
    il_mod_add_func(ilmod, ifn);

    if (simpl->trait_name && strcmp(simpl->trait_name, "Drop") == 0 && strcmp(sfn->name, "drop") == 0) {
        char type_mname[512];
        strncpy(type_mname, mangled_name, sizeof(type_mname));
        type_mname[sizeof(type_mname)-1] = '\0';
        char* last_underscore = strrchr(type_mname, '_');
        if (last_underscore) {
            *last_underscore = '\0';
            for (uint32_t i = 0; i < ilmod->type_def_count; i++) {
                if (strcmp(ilmod->type_defs[i]->name, type_mname) == 0) {
                    if (ilmod->type_defs[i]->drop_fn_name) free(ilmod->type_defs[i]->drop_fn_name);
                    ilmod->type_defs[i]->drop_fn_name = strdup(mangled_name);
                    break;
                }
            }
        }
    }

    LowerContext mctx;
    init_lower_context(&mctx, smod, ilmod, report, release_mode, sfn, simpl, ifn, head);

    ILValue res = lower_block(&mctx, sfn->body, ifn->is_sret ? ifn->sret_type : ifn->return_type, (ILValue){0});

    if (simpl->trait_name && strcmp(simpl->trait_name, "Drop") == 0 && strcmp(sfn->name, "drop") == 0) {
        const Symbol* self_sym = symbol_lookup(mctx.current_scope, "self");
        if (self_sym) mark_moved(&mctx, self_sym->value.id);
    }

    if (!block_is_terminated(mctx.current_block)) {
        if (res.type) emit_return(&mctx, res);
        else { ILValue uv = { .id = 0, .type = il_type_unit() }; emit_return(&mctx, uv); }
    }

    run_all_defers(&mctx, 0);
    scope_pop(&mctx, 0);
    lower_context_cleanup(&mctx);
    substitutions_free(head);
    return ifn;
}

bool type_implements_trait(const SurfaceModule* smod, const ILType* type, const char* trait_name, const Substitution* substs) {
    if (!smod || !type || !trait_name) return false;

    // 1. If the type is a generic parameter, check its bounds in the current context
    if (type->kind == IL_TY_VAR || ((type->kind == IL_TY_STRUCT || type->kind == IL_TY_SUM) && type->as.struct_sum.type_arg_count == 0)) {
        const char* name = (type->kind == IL_TY_VAR) ? type->as.var.name : type->as.struct_sum.name;
        const Substitution* s = substs;
        while (s) {
            if (strcmp(s->name, name) == 0) {
                if (s->bound && strcmp(s->bound, trait_name) == 0) return true;
                // Recursive check if needed? Zoril doesn't support T: U: Trait yet.
                break;
            }
            s = s->next;
        }
    }

    // 2. Concrete type check
    char* type_name = NULL;
    if (type->kind == IL_TY_STRUCT || type->kind == IL_TY_SUM) {
        type_name = type->as.struct_sum.name;
    } else {
        // Primitive types
        static char buf[64];
        il_type_print(type, buf, sizeof(buf));
        type_name = buf;
    }
    if (!type_name) return false;

    // Base name for monomorphized types
    char base_name_buf[128];
    const char* underscore = strchr(type_name, '_');
    if (underscore) {
        size_t len = (size_t)(underscore - type_name);
        if (len >= sizeof(base_name_buf)) len = sizeof(base_name_buf) - 1;
        strncpy(base_name_buf, type_name, len);
        base_name_buf[len] = '\0';
        type_name = base_name_buf;
    }

    for (uint32_t i = 0; i < smod->impl_count; i++) {
        const ImplDecl* impl = smod->impls[i];
        if (!impl->trait_name) continue;

        bool trait_match = (strcmp(impl->trait_name, trait_name) == 0);
        if (!trait_match) {
            const char* t_underscore = strchr(impl->trait_name, '_');
            if (t_underscore) {
                size_t t_len = (size_t)(t_underscore - impl->trait_name);
                if (strncmp(impl->trait_name, trait_name, t_len) == 0 && trait_name[t_len] == '\0') trait_match = true;
            }
        }
        if (!trait_match) continue;

        bool type_match = (strcmp(impl->target_name, type_name) == 0);
        if (!type_match) {
            const char* i_underscore = strchr(impl->target_name, '_');
            if (i_underscore) {
                size_t i_len = (size_t)(i_underscore - impl->target_name);
                if (strncmp(impl->target_name, type_name, i_len) == 0 && type_name[i_len] == '\0') type_match = true;
            }
        }
        if (type_match) return true;
    }

    return false;
}

ILTypeDef* find_type_def(LowerContext* ctx, const char* name) {
    if (!ctx || !ctx->module) return NULL;

    // Check substitutions first
    const Substitution* s = ctx->current_substs;
    while (s) {
        if (strcmp(s->name, name) == 0) {
            if (s->type->kind == IL_TY_STRUCT || s->type->kind == IL_TY_SUM) {
                return il_mod_get_type_def(ctx->module, s->type->as.struct_sum.type_def_id);
            }
        }
        s = s->next;
    }

    for (uint32_t i = 0; i < ctx->module->type_def_count; i++) {
        if (strcmp(ctx->module->type_defs[i]->name, name) == 0) {
            return ctx->module->type_defs[i];
        }
    }

    // Resolve alias if needed
    if (!ctx->surface_mod) return NULL;
    for (uint32_t i = 0; i < ctx->surface_mod->type_alias_count; i++) {
        if (strcmp(ctx->surface_mod->type_aliases[i]->name, name) == 0) {
            const ILType* target = ctx->surface_mod->type_aliases[i]->target;
            if (target->kind == IL_TY_STRUCT || target->kind == IL_TY_SUM) {
                return find_type_def(ctx, target->as.struct_sum.name);
            }
        }
    }

    // Search surface module for generic types OR traits
    for (uint32_t i = 0; i < ctx->surface_mod->type_def_count; i++) {
        const TypeDef* styp = ctx->surface_mod->type_defs[i];
        const char* sname = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->name : styp->as.enum_decl->name;
        if (strcmp(sname, name) == 0) {
            for (uint32_t j = 0; j < ctx->generic_def_count; j++) {
                if (strcmp(ctx->generic_defs[j]->name, sname) == 0) return ctx->generic_defs[j];
            }

            ILTypeDef* def = calloc(1, sizeof(ILTypeDef));
            if (!def) abort();
            def->name = strdup(sname);
            if (!def->name) abort();
            def->is_sum = (styp->kind == TYPE_DEF_ENUM);
            def->is_generic = true;
            if (ctx->generic_def_count >= ctx->generic_def_capacity) {
                ctx->generic_def_capacity = ctx->generic_def_capacity ? ctx->generic_def_capacity * 2 : 4;
                ctx->generic_defs = realloc(ctx->generic_defs, ctx->generic_def_capacity * sizeof(ILTypeDef*));
                if (!ctx->generic_defs) abort();
            }
            ctx->generic_defs[ctx->generic_def_count++] = def;

            if (styp->kind == TYPE_DEF_STRUCT) {
                for (uint32_t j = 0; j < styp->as.struct_decl->field_count; j++) {
                    il_type_def_add_field_pub(def, styp->as.struct_decl->fields[j].name, lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, styp->as.struct_decl->fields[j].type, NULL), styp->as.struct_decl->fields[j].is_pub, false, 0);
                }
            } else {
                for (uint32_t j = 0; j < styp->as.enum_decl->variant_count; j++) {
                    il_type_def_add_field_pub(def, styp->as.enum_decl->variants[j].name, lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, styp->as.enum_decl->variants[j].type, NULL), styp->as.enum_decl->variants[j].is_pub, styp->as.enum_decl->variants[j].has_tag, styp->as.enum_decl->variants[j].tag);
                }
            }
            return def;
        }
    }

    for (uint32_t i = 0; i < ctx->surface_mod->trait_count; i++) {
        const TraitDecl* trait = ctx->surface_mod->traits[i];
        if (strcmp(trait->name, name) == 0) {
            for (uint32_t j = 0; j < ctx->generic_def_count; j++) {
                if (strcmp(ctx->generic_defs[j]->name, name) == 0) return ctx->generic_defs[j];
            }
            ILTypeDef* def = calloc(1, sizeof(ILTypeDef));
            if (!def) abort();
            def->name = strdup(name);
            def->is_generic = true;
            if (ctx->generic_def_count >= ctx->generic_def_capacity) {
                ctx->generic_def_capacity = ctx->generic_def_capacity ? ctx->generic_def_capacity * 2 : 4;
                ctx->generic_defs = realloc(ctx->generic_defs, ctx->generic_def_capacity * sizeof(ILTypeDef*));
                if (!ctx->generic_defs) abort();
            }
            ctx->generic_defs[ctx->generic_def_count++] = def;

            for (uint32_t j = 0; j < trait->method_count; j++) {
                // Traits don't have fields, but they have methods. 
                // lower_method_call will use find_method_decl, so we just need this ILTypeDef to exist.
                // We could add empty fields or just leave it.
            }
            return def;
        }
    }

    return NULL;
}
int find_field_index(const ILTypeDef* def, const char* name) {
    if (!def) return -1;
    for (uint32_t i = 0; i < def->field_count; i++) {
        if (strcmp(def->fields[i].name, name) == 0) return (int)i;
    }
    return -1;
}






void lower_context_cleanup(LowerContext* ctx) {
    while (ctx->current_scope) scope_pop(ctx, 0);
    ctx->current_scope = NULL;
    if (ctx->value_moved) free(ctx->value_moved);
    ctx->value_moved = NULL;
    ctx->value_moved_capacity = 0;
    
    ctx->env_ptr.type = NULL;
    Capture* cap = ctx->captures;
    while (cap) {
        Capture* next = cap->next;
        free(cap->name);
        
        free(cap);
        cap = next;
    }
    ctx->captures = NULL;
    for (uint32_t i = 0; i < ctx->generic_def_count; i++) {
        il_type_def_free(ctx->generic_defs[i]);
    }
    free(ctx->generic_defs);
    ctx->generic_defs = NULL;
    ctx->generic_def_count = 0;
    ctx->generic_def_capacity = 0;

    if (ctx->temporaries) {
        for (uint32_t i = 0; i < ctx->temporary_count; i++) {
            
        }
        free(ctx->temporaries);
    }
    ctx->temporaries = NULL;
    ctx->temporary_count = 0;
    ctx->temporary_capacity = 0;
}

static const GlobalDecl* find_global_decl(const SurfaceModule* smod, const char* name, const char* target_type) {
    if (target_type) {
        for (uint32_t i = 0; i < smod->impl_count; i++) {
            if (strcmp(smod->impls[i]->target_name, target_type) == 0) {
                for (uint32_t j = 0; j < smod->impls[i]->global_count; j++) {
                    if (strcmp(smod->impls[i]->globals[j]->name, name) == 0) {
                        return smod->impls[i]->globals[j];
                    }
                }
            }
        }
        
        // Check module aliases
        for (uint32_t i = 0; i < smod->import_count; i++) {
            const char* alias = smod->imports[i]->alias;
            char buf[128];
            if (!alias) {
                const char* last_slash = strrchr(smod->imports[i]->path, '/');
                const char* start = last_slash ? last_slash + 1 : smod->imports[i]->path;
                const char* dot = strchr(start, '.');
                size_t len = dot ? (size_t)(dot - start) : strlen(start);
                if (len >= sizeof(buf)) len = sizeof(buf) - 1;
                strncpy(buf, start, len); buf[len] = '\0';
                alias = buf;
            }
            
            if (strcmp(alias, target_type) == 0) {
                for (uint32_t j = 0; j < smod->global_count; j++) {
                    if (strcmp(smod->globals[j]->name, name) == 0 &&
                        smod->imports[i]->resolved_path &&
                        strcmp(smod->globals[j]->file_path, smod->imports[i]->resolved_path) == 0) {
                        return smod->globals[j];
                    }
                }
            }
        }
    } else {
        for (uint32_t i = 0; i < smod->global_count; i++) {
            if (strcmp(smod->globals[i]->name, name) == 0) {
                return smod->globals[i];
            }
        }
    }
    return NULL;
}

static bool eval_const_int_rec(const SurfaceModule* smod, const Expression* expr, uint64_t* out_val, const GlobalDecl** visit_stack, int stack_depth) {
    if (!expr || stack_depth > 64) return false;

    if (expr->kind == EXPR_INT) {
        *out_val = expr->as.int_val;
        return true;
    }
    if (expr->kind == EXPR_BOOL) {
        *out_val = expr->as.bool_val ? 1 : 0;
        return true;
    }
    if (expr->kind == EXPR_CAST) {
        return eval_const_int_rec(smod, expr->as.cast_expr.expr, out_val, visit_stack, stack_depth);
    }
    if (expr->kind == EXPR_UNARY && expr->as.unary.op && strcmp(expr->as.unary.op, "-") == 0) {
        uint64_t inner = 0;
        if (eval_const_int_rec(smod, expr->as.unary.expr, &inner, visit_stack, stack_depth)) {
            *out_val = (uint64_t)(-(int64_t)inner);
            return true;
        }
    }
    if (expr->kind == EXPR_VAR) {
        const GlobalDecl* sg = find_global_decl(smod, expr->as.var.name, NULL);
        if (sg && sg->is_const) {
            for (int i = 0; i < stack_depth; i++) {
                if (visit_stack[i] == sg) return false; // Cycle
            }
            visit_stack[stack_depth] = sg;
            return eval_const_int_rec(smod, sg->init, out_val, visit_stack, stack_depth + 1);
        }
    }
    if (expr->kind == EXPR_MEMBER) {
        if (expr->as.member.object->kind == EXPR_VAR) {
            const char* type_name = expr->as.member.object->as.var.name;
            const char* member_name = expr->as.member.field_name;
            const GlobalDecl* sg = find_global_decl(smod, member_name, type_name);
            if (sg && sg->is_const) {
                for (int i = 0; i < stack_depth; i++) {
                    if (visit_stack[i] == sg) return false; // Cycle
                }
                visit_stack[stack_depth] = sg;
                return eval_const_int_rec(smod, sg->init, out_val, visit_stack, stack_depth + 1);
            }
        }
    }
    if (expr->kind == EXPR_BINARY) {
        uint64_t left = 0, right = 0;
        if (eval_const_int_rec(smod, expr->as.binary.left, &left, visit_stack, stack_depth) &&
            eval_const_int_rec(smod, expr->as.binary.right, &right, visit_stack, stack_depth)) {
            const char* op = expr->as.binary.op;
            if (strcmp(op, "+") == 0) { *out_val = left + right; return true; }
            if (strcmp(op, "-") == 0) { *out_val = left - right; return true; }
            if (strcmp(op, "*") == 0) { *out_val = left * right; return true; }
            if (strcmp(op, "/") == 0) { if (right == 0) return false; *out_val = left / right; return true; }
            if (strcmp(op, "%") == 0) { if (right == 0) return false; *out_val = left % right; return true; }
            if (strcmp(op, "&") == 0) { *out_val = left & right; return true; }
            if (strcmp(op, "|") == 0) { *out_val = left | right; return true; }
            if (strcmp(op, "^") == 0) { *out_val = left ^ right; return true; }
            if (strcmp(op, "<<") == 0) { *out_val = left << right; return true; }
            if (strcmp(op, ">>") == 0) { *out_val = left >> right; return true; }
        }
    }
    return false;
}

bool eval_const_int(const SurfaceModule* smod, const Expression* expr, uint64_t* out_val) {
    const GlobalDecl* visit_stack[64];
    return eval_const_int_rec(smod, expr, out_val, visit_stack, 0);
}

static void lower_global_decl_internal(const SurfaceModule* smod, ILModule* mod, DiagnosticReport* report, bool release_mode, const GlobalDecl* sg, const char* mangled_name) {
    const ILType* gty = sg->type ? lower_type(smod, mod, report, release_mode, sg->type, NULL) : NULL;
    
    uint64_t const_val = 0;
    bool is_const_int = eval_const_int(smod, sg->init, &const_val);

    if (sg->is_const && !is_const_int) {
        // If it's not a string or float, and we expected an integer (or no type given), it's an error.
        if (sg->init && sg->init->kind != EXPR_STRING && sg->init->kind != EXPR_FLOAT) {
            SourceLocation loc = { .file_path = sg->file_path, .source = sg->init->source, .line = sg->line, .col = sg->col, .offset = sg->offset, .length = sg->length };
            diag_emit(report, DIAG_ERROR, loc, "Cannot evaluate constant expression at compile time (possibly cyclic)");
        }
    } else if (!is_const_int) {
        // A `static` whose initializer this compiler cannot evaluate used to be *zeroed* in
        // silence - the data section got `z <size>`, so the program ran with a zeroed global and
        // nothing said so. Report it instead, the way the self-hosted compiler rejects a form it
        // cannot materialize (tests/error_reporting/err_static_init_*.zrl). Char literals, struct
        // and array literals, enum variants, calls and another static's name are still not
        // evaluated here: this is the bootstrap compiler, not the language's checker, and a
        // program that needs one of those is outside what it can translate.
        if (sg->init && sg->init->kind != EXPR_STRING && sg->init->kind != EXPR_FLOAT) {
            SourceLocation loc = { .file_path = sg->file_path, .source = sg->init->source, .line = sg->line, .col = sg->col, .offset = sg->offset, .length = sg->length };
            diag_emit(report, DIAG_ERROR, loc, "a static's initializer must be a constant this compiler can evaluate: an integer, bool or float literal, a byte string, or arithmetic and casts over those");
        }
    }

    if (!gty && is_const_int) {
        gty = il_type_i32();
    }
    
    ILGlobal* ig = il_global_create((uint32_t)mod->global_count, mangled_name ? mangled_name : sg->name, gty, sg->is_const, sg->is_pub, sg->file_path);
    if (is_const_int && gty) {
        size_t size = il_type_size(mod, gty);
        if (size > 0) {
            uint8_t* data = calloc(1, size);
            if (data) {
                memcpy(data, &const_val, size > 8 ? 8 : size);
                il_global_set_init_data(ig, data, (uint32_t)size);
                free(data);
            }
        }
    } else if (sg->init && sg->init->kind == EXPR_STRING) {
        il_global_set_init_data(ig, (const uint8_t*)sg->init->as.string_val.val, (uint32_t)sg->init->as.string_val.len + 1);
    } else if (sg->init && sg->init->kind == EXPR_FLOAT && gty) {
        size_t size = il_type_size(mod, gty);
        if (size > 0) {
            uint8_t* data = calloc(1, size);
            if (data) {
                double val = sg->init->as.float_val;
                if (gty->kind == IL_TY_F32) {
                    float fval = (float)val;
                    memcpy(data, &fval, 4);
                } else {
                    memcpy(data, &val, 8);
                }
                il_global_set_init_data(ig, data, (uint32_t)size);
                free(data);
            }
        }
    }
    
    il_mod_add_global(mod, ig);
}

ILModule* surface_lower_module(const SurfaceModule* smod, DiagnosticReport* report, bool release_mode) {
    (void)emit_stmt_diag_at;
    if (!smod) return NULL;
    
    ILModule* mod = il_mod_create();
    if (!mod) return NULL;
    
    for (uint32_t i = 0; i < smod->type_def_count; i++) {
        const TypeDef* styp = smod->type_defs[i];
        if (!styp) {
            continue;
        }
        if (styp->kind == TYPE_DEF_STRUCT) {
            const StructDecl* s = styp->as.struct_decl;
            // Reuse an existing type def if already registered (e.g. by lower_type_internal
            // while processing an earlier struct's fields, or by a forward/partial definition
            // of the same name).  This lets a second definition add any missing fields.
            ILTypeDef* ityp = NULL;
            for (uint32_t k = 0; k < mod->type_def_count; k++) {
                if (mod->type_defs[k]->name && strcmp(mod->type_defs[k]->name, s->name) == 0) {
                    ityp = mod->type_defs[k];
                    break;
                }
            }
            if (!ityp) {
                ityp = il_type_def_struct_create(mod->next_type_def_id++, s->name, s->file_path, s->is_pub);
                ityp->is_generic = (s->type_param_count > 0);
                // Register before lowering fields so recursive field types (e.g. *mut Self)
                // find this entry and don't create a duplicate that gets leaked.
                il_mod_add_type_def(mod, ityp);
            }
            
            Substitution* head_subst = NULL;
            for (uint32_t j = 0; j < s->type_param_count; j++) {
                Substitution* n = calloc(1, sizeof(Substitution));
                if (n) {
                    n->name = s->type_params[j];
                    n->type = il_type_var(s->type_params[j]);
                    n->next = head_subst;
                    head_subst = n;
                }
            }

            for (uint32_t j = 0; j < s->field_count; j++) {
                il_type_def_add_field_pub(ityp, s->fields[j].name, lower_type(smod, mod, report, release_mode, s->fields[j].type, head_subst), s->fields[j].is_pub, false, 0);
            }
            
            while (head_subst) {
                Substitution* next = (Substitution*)head_subst->next;
                free(head_subst);
                head_subst = next;
            }
        } else if (styp->kind == TYPE_DEF_ENUM) {
            const EnumDecl* e = styp->as.enum_decl;
            // Same: reuse existing type def if already registered.
            ILTypeDef* ityp = NULL;
            for (uint32_t k = 0; k < mod->type_def_count; k++) {
                if (mod->type_defs[k]->name && strcmp(mod->type_defs[k]->name, e->name) == 0) {
                    ityp = mod->type_defs[k];
                    break;
                }
            }
            if (!ityp) {
                ityp = il_type_def_sum_create(mod->next_type_def_id++, e->name, e->file_path, e->is_pub);
                ityp->is_generic = (e->type_param_count > 0);
                // Same: register before lowering variant types.
                il_mod_add_type_def(mod, ityp);
            }
            
            Substitution* head_subst = NULL;
            for (uint32_t j = 0; j < e->type_param_count; j++) {
                Substitution* n = calloc(1, sizeof(Substitution));
                if (n) {
                    n->name = e->type_params[j];
                    n->type = il_type_var(e->type_params[j]);
                    n->next = head_subst;
                    head_subst = n;
                }
            }

            for (uint32_t j = 0; j < e->variant_count; j++) {
                il_type_def_add_field_pub(ityp, e->variants[j].name, lower_type(smod, mod, report, release_mode, e->variants[j].type, head_subst), e->variants[j].is_pub, e->variants[j].has_tag, e->variants[j].tag);
            }
            
            while (head_subst) {
                Substitution* next = (Substitution*)head_subst->next;
                free(head_subst);
                head_subst = next;
            }
        }
    }

    verify_no_type_cycles(mod, report);
    if (report && report->has_errors) {
        il_mod_free(mod);
        return NULL;
    }

    // Lower regular globals
    for (uint32_t i = 0; i < smod->global_count; i++) {
        // Skip if already lowered
        if (il_mod_get_global_by_name(mod, smod->globals[i]->name)) continue;
        lower_global_decl_internal(smod, mod, report, release_mode, smod->globals[i], NULL);
    }

    // Pre-register drop functions for all types so move-checks know which types are non-Copy
    for (uint32_t i = 0; i < smod->impl_count; i++) {
        const ImplDecl* impl = smod->impls[i];
        if (impl->trait_name && strcmp(impl->trait_name, "Drop") == 0) {
            for (uint32_t k = 0; k < mod->type_def_count; k++) {
                if (strcmp(mod->type_defs[k]->name, impl->target_name) == 0) {
                    char drop_mname[512];
                    snprintf(drop_mname, sizeof(drop_mname), "%s_drop", impl->target_name);
                    if (mod->type_defs[k]->drop_fn_name) free(mod->type_defs[k]->drop_fn_name);
                    mod->type_defs[k]->drop_fn_name = strdup(drop_mname);
                    break;
                }
            }
        }
    }

    // Lower associated globals in impl blocks
    for (uint32_t i = 0; i < smod->impl_count; i++) {
        const ImplDecl* impl = smod->impls[i];
        for (uint32_t j = 0; j < impl->global_count; j++) {
            char mname[512];
            snprintf(mname, sizeof(mname), "%s_%s", impl->target_name, impl->globals[j]->name);
            // Skip if already lowered
            if (il_mod_get_global_by_name(mod, mname)) {
                continue;
            }
            lower_global_decl_internal(smod, mod, report, release_mode, impl->globals[j], mname);
        }
    }

    // Create function skeletons for regular functions. A function the on-demand path
    // (`monomorphize_function`) already instantiated is reused rather than created a second time:
    // the drop-function discovery lowers `Drop` bodies before this pass, so their callees (across
    // modules) are already here, and a second IL function of the same name emits two definitions
    // of one symbol, which the assembler rejects.
    for (uint32_t i = 0; i < smod->function_count; i++) {
        const FunctionDecl* sfn = smod->functions[i];
        if (sfn->type_param_count > 0) continue;
        ILFunction* existing = (ILFunction*)il_mod_get_func_by_name(mod, sfn->name);
        if (existing) {
            ((FunctionDecl*)sfn)->il_function = existing;
            continue;
        }
        const ILType* ret_type = sfn->return_type ? lower_type(smod, mod, report, release_mode, sfn->return_type, NULL) : il_type_unit();
        ILFunction* ifn = il_func_create((uint32_t)(mod->function_count + 1), sfn->name, ret_type, sfn->is_pub, sfn->is_must_use, sfn->file_path);
        ifn->is_extern = sfn->is_extern;
        ifn->is_variadic = sfn->is_variadic;
        apply_sret_if_needed(mod, ifn);
        if (il_func_needs_env_ptr(ifn)) {
            il_func_add_param(ifn, il_type_ptr(il_type_unit(), REGION_STATIC, false));
        }
        for (uint32_t j = 0; j < sfn->param_count; j++) {
            const ILType* pty = lower_type(smod, mod, report, release_mode, sfn->params[j].type, NULL);
            if (!ifn->is_extern && requires_pass_by_ref(mod, pty)) {
                pty = il_type_ptr(pty, REGION_LOCAL, true);
            }
            il_func_add_param(ifn, pty);
        }        il_mod_add_func(mod, ifn);
        ((FunctionDecl*)sfn)->il_function = ifn;
    }

    for (uint32_t i = 0; i < smod->impl_count; i++) {
        const ImplDecl* impl = smod->impls[i];
        
        const ILType* resolved_target = lower_type(smod, mod, NULL, release_mode, impl->target_type, NULL);
        bool is_generic_impl = il_type_is_generic_mod(mod, resolved_target);
        if (is_generic_impl) continue;

        Substitution* impl_substs = derive_substs(smod, impl->target_type);

        // Enforce trait bounds for the trait itself (e.g. impl Derived<NotBase> for MyDerived)
        if (impl->trait_name) {
            const TraitDecl* trait = NULL;
            for (uint32_t ti = 0; ti < smod->trait_count; ti++) {
                const char* tname = smod->traits[ti]->name;
                bool trait_match = false;
                if (strcmp(tname, impl->trait_name) == 0) {
                    trait_match = true;
                } else {
                    const char* t_underscore = strchr(impl->trait_name, '_');
                    if (t_underscore) {
                        size_t base_len = (size_t)(t_underscore - impl->trait_name);
                        if (strncmp(impl->trait_name, tname, base_len) == 0 && tname[base_len] == '\0') {
                            trait_match = true;
                        }
                    }
                }
                if (trait_match) {
                    trait = smod->traits[ti];
                    break;
                }
            }

            if (trait && impl->trait_type && (impl->trait_type->kind == IL_TY_STRUCT || impl->trait_type->kind == IL_TY_SUM)) {
                for (uint32_t j = 0; j < trait->type_param_count && j < impl->trait_type->as.struct_sum.type_arg_count; j++) {
                    const char* bound = trait->type_bounds ? trait->type_bounds[j] : NULL;
                    const ILType* arg_ty = impl->trait_type->as.struct_sum.type_args[j];
                    if (bound && !type_implements_trait(smod, arg_ty, bound, NULL)) {
                        char type_buf[128];
                        il_type_print(arg_ty, type_buf, sizeof(type_buf));
                        diag_emit(report, DIAG_ERROR, (SourceLocation){.file_path = impl->file_path, .line = impl->line, .col = impl->col},
                            "Type '%s' does not implement trait '%s' required by trait '%s' parameter '%s'", 
                            type_buf, bound, trait->name, trait->type_params[j]);
                    }
                }
            }
        }

        for (uint32_t j = 0; j < impl->method_count; j++) {
            const FunctionDecl* sfn = impl->methods[j];
            char* mname = malloc(strlen(impl->target_name) + strlen(sfn->name) + 2);
            if (mname) sprintf(mname, "%s_%s", impl->target_name, sfn->name);
            
            // Skip if already lowered
            if (il_mod_get_func_by_name(mod, mname)) {
                free(mname);
                continue;
            }

            const ILType* ret_type = sfn->return_type ? lower_type(smod, mod, report, release_mode, sfn->return_type, impl_substs) : il_type_unit();
            bool is_pub = sfn->is_pub;
            if (impl->trait_name) {
                is_pub = true;
                ((FunctionDecl*)sfn)->is_pub = true;
            }
            ILFunction* ifn = il_func_create((uint32_t)(mod->function_count + 1), mname, ret_type, is_pub, sfn->is_must_use, sfn->file_path);
            ifn->is_variadic = sfn->is_variadic;
            free(mname);
            apply_sret_if_needed(mod, ifn);
            if (il_func_needs_env_ptr(ifn)) {
                il_func_add_param(ifn, il_type_ptr(il_type_unit(), REGION_STATIC, false));
            }
            for (uint32_t k = 0; k < sfn->param_count; k++) {
                const Param* sp = &sfn->params[k];
                const ILType* pty = NULL;
                if (sp->type == NULL && strcmp(sp->name, "self") == 0) {
                    pty = lower_type(smod, mod, report, release_mode, impl->target_type, impl_substs);
                } else {
                    pty = lower_type(smod, mod, report, release_mode, sp->type, impl_substs);
                }
                if (!ifn->is_extern && requires_pass_by_ref(mod, pty)) {
                    pty = il_type_ptr(pty, REGION_LOCAL, true);
                }
                il_func_add_param(ifn, pty);
            }
            il_mod_add_func(mod, ifn);
            ((ImplDecl*)impl)->il_methods[j] = ifn;

            if (impl->trait_name && strcmp(impl->trait_name, "Drop") == 0 && strcmp(sfn->name, "drop") == 0) {
                for (uint32_t k = 0; k < mod->type_def_count; k++) {
                    if (strcmp(mod->type_defs[k]->name, impl->target_name) == 0) {
                        if (mod->type_defs[k]->drop_fn_name) free(mod->type_defs[k]->drop_fn_name);
                        mod->type_defs[k]->drop_fn_name = strdup(ifn->name);
                        break;
                    }
                }
            }
        }
        while (impl_substs) {
            Substitution* next = (Substitution*)impl_substs->next;
            free(impl_substs);
            impl_substs = next;
        }
    }
    // Fix up function signatures (parameters and return types)
    for (uint32_t i = 0; i < mod->function_count; i++) {
        const ILFunction* ifn = mod->functions[i];
        il_type_fixup(mod, (ILType*)ifn->return_type);
        for (uint32_t j = 0; j < ifn->param_count; j++) {
            il_type_fixup(mod, ifn->param_types[j]);
        }
    }
    for (uint32_t i = 0; i < smod->function_count; i++) {
        const FunctionDecl* sfn = smod->functions[i];
        if (sfn->type_param_count > 0) continue;
        ILFunction* ifn = (ILFunction*)sfn->il_function;

        if (sfn->is_extern) continue;
        // The on-demand path lowers a body as soon as it instantiates the function, so a
        // declaration whose callee was reached first (a `Drop` method above all) already has its
        // blocks: lowering it again would emit a second set of blocks under the same labels.
        if (ifn->block_count > 0) continue;

        LowerContext ctx;
        memset(&ctx, 0, sizeof(LowerContext));
        ctx.release_mode = release_mode;
        ctx.current_func = ifn;
        ctx.current_surface_func = sfn;
        ctx.module = mod;
        ctx.surface_mod = smod;
        ctx.report = report;
        ctx.current_file = sfn->file_path;
        ctx.current_source = smod->source;
        ctx.next_value_id = ifn->param_count + 1;
        ctx.next_block_id = 1;
        
        uint32_t current_param_id = 1;
        if (ifn->is_sret) {
            ctx.sret_id = current_param_id++;
        }
        if (il_func_needs_env_ptr(ifn)) {
            const ILType* env_ty = il_type_ptr(il_type_unit(), REGION_STATIC, false);
            ctx.env_ptr = (ILValue){ .id = current_param_id++, .type = env_ty };
        }
        
        ILBasicBlock* entry = create_block(&ctx);
        ctx.current_block = entry;
        
        scope_push(&ctx);
        for (uint32_t j = 0; j < sfn->param_count; j++) {
            const ILType* orig_pty = lower_type(smod, mod, report, release_mode, sfn->params[j].type, NULL);
            const ILType* ptype = ifn->param_types[current_param_id - 1];
            ILValue pval = { .id = current_param_id++, .type = ptype };
            bool is_lvalue = !ifn->is_extern && requires_pass_by_ref(mod, orig_pty);
            if (sfn->params[j].is_mutable || (!is_lvalue && is_aggregate_type_layout(orig_pty))) {
                const ILType* ptr_ty = il_type_ptr(ptype, REGION_LOCAL, true);
                ILInstruction* alloc = il_build_alloc(REGION_LOCAL, ptype, ptr_ty, (ILValue){0});
                ILValue ptr = emit(&ctx, alloc);
                emit_void(&ctx, il_build_store(ptr, pval));
                symbol_add_ctx(&ctx, sfn->params[j].name, ptr, true);
            } else {
                symbol_add_ctx(&ctx, sfn->params[j].name, pval, is_lvalue);
            }
        }

        ILValue res = lower_block(&ctx, sfn->body, ifn->is_sret ? ifn->sret_type : ifn->return_type, (ILValue){0});
        uint32_t exempt_id = 0;
        if (res.type) {
            exempt_id = res.id;
        }
        run_all_defers(&ctx, exempt_id);

        // Pop the outer scope (contains parameters) BEFORE the return
        scope_pop(&ctx, exempt_id);

        if (!block_is_terminated(ctx.current_block)) {
            if (res.type) {
                emit_return(&ctx, res);
            } else {
                // Handle implicit unit return if not already returned
                ILValue unit_val = { .id = 0, .type = il_type_unit() };
                emit_return(&ctx, unit_val);
            }
        }
        
        lower_context_cleanup(&ctx);
    }

    for (uint32_t i = 0; i < smod->impl_count; i++) {
        const ImplDecl* impl = smod->impls[i];
        
        const ILType* resolved_target = lower_type(smod, mod, NULL, release_mode, impl->target_type, NULL);
        bool is_generic_impl = il_type_is_generic_mod(mod, resolved_target);
        if (is_generic_impl) continue;

        Substitution* impl_substs = derive_substs(smod, impl->target_type);

        for (uint32_t j = 0; j < impl->method_count; j++) {
            const FunctionDecl* sfn = impl->methods[j];
            ILFunction* ifn = (ILFunction*)impl->il_methods[j];
            if (!ifn) continue;
            
            LowerContext ctx;
            memset(&ctx, 0, sizeof(LowerContext));
            ctx.release_mode = release_mode;
            ctx.current_func = ifn;
            ctx.current_surface_func = sfn;
            ctx.current_surface_impl = impl;
            ctx.module = mod;
            ctx.surface_mod = smod;
            ctx.report = report;
            ctx.current_file = sfn->file_path;
        ctx.current_source = smod->source;
            ctx.current_substs = impl_substs;
            ctx.next_value_id = ifn->param_count + 1;
            ctx.next_block_id = 1;

            ILBasicBlock* entry = create_block(&ctx);
            ctx.current_block = entry;

            scope_push(&ctx);
            uint32_t current_param_id = 1;
            if (ifn->is_sret) {
                ctx.sret_id = current_param_id++;
            }
            if (il_func_needs_env_ptr(ifn)) {
                ctx.env_ptr = (ILValue){ .id = current_param_id++, .type = il_type_ptr(il_type_unit(), REGION_STATIC, false) };
            }
        for (uint32_t k = 0; k < sfn->param_count; k++) {
            const ILType* orig_pty = NULL;
            if (sfn->params[k].type == NULL && strcmp(sfn->params[k].name, "self") == 0) {
                orig_pty = lower_type(smod, mod, report, release_mode, impl->target_type, impl_substs);
            } else {
                orig_pty = lower_type(smod, mod, report, release_mode, sfn->params[k].type, impl_substs);
            }
            uint32_t idx = current_param_id - 1;
            const ILType* ptype = ifn->param_types[idx];
            ILValue pval = { .id = current_param_id++, .type = ptype };
            bool is_lvalue = !ifn->is_extern && requires_pass_by_ref(mod, orig_pty);
            if (sfn->params[k].is_mutable || (!is_lvalue && is_aggregate_type_layout(orig_pty))) {
                const ILType* ptr_ty = il_type_ptr(ptype, REGION_LOCAL, true);
                ILInstruction* alloc = il_build_alloc(REGION_LOCAL, ptype, ptr_ty, (ILValue){0});
                ILValue ptr = emit(&ctx, alloc);
                emit_void(&ctx, il_build_store(ptr, pval));
                symbol_add_ctx(&ctx, sfn->params[k].name, ptr, true);
            } else {
                symbol_add_ctx(&ctx, sfn->params[k].name, pval, is_lvalue);
            }
        }
            ILValue res = lower_block(&ctx, sfn->body, ifn->is_sret ? ifn->sret_type : ifn->return_type, (ILValue){0});

            if (impl->trait_name && strcmp(impl->trait_name, "Drop") == 0 && strcmp(sfn->name, "drop") == 0) {
                const Symbol* self_sym = symbol_lookup(ctx.current_scope, "self");
                if (self_sym) {
                    mark_moved(&ctx, self_sym->value.id);
                }
            }

            if (!block_is_terminated(ctx.current_block)) {
                if (res.type) {
                    const ILType* effective_ret = ifn->is_sret ? ifn->sret_type : ifn->return_type;
                    ILValue assigned = ensure_assignable(&ctx, res, effective_ret);
                    res = assigned;
                }
            }
            uint32_t exempt_id = 0;
            if (res.type) exempt_id = res.id;
            run_all_defers(&ctx, exempt_id);

            scope_pop(&ctx, exempt_id);
            if (!block_is_terminated(ctx.current_block)) {
                if (res.type) {
                    emit_return(&ctx, res);
                } else {
                    ILValue unit_val = { .id = 0, .type = il_type_unit() };
                    emit_return(&ctx, unit_val);
                }
            }
            
            // lower_context_cleanup will be called, but scope is already popped
            lower_context_cleanup(&ctx);
        }
        while (impl_substs) {
            Substitution* next = (Substitution*)impl_substs->next;
            free(impl_substs);
            impl_substs = next;
        }
    }
    
    return mod;
}
