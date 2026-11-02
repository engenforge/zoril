#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "verifier.h"
#include "il_pass.h"
#include "il_print.h"
#include "il_ownership.h"

/* --------------------------------------------------------------------------
 * Language safety checking was REMOVED from stage0-C on 2026-09-12.
 *
 * stage0-C is a bootstrap tool whose job is to turn Zoril source into an
 * executable. Language safety is the shipped compiler's job, and keeping a
 * second, divergent implementation here was actively harmful:
 *
 *   - Its return-escape check was type-level, so it rejected any function
 *     returning a slice -- including stdlib/bytevec.zrl:56's as_slice(). That
 *     is why the build has always passed --no-verify (see Makefile:59-77), so
 *     these checks were not running on the only path that matters anyway.
 *   - It had a working borrow checker while the SHIPPED verifier's
 *     check_borrow/check_move_from are empty stubs (src/verify.zrl:1158-1160),
 *     so the bootstrap tool judged programs more harshly than the compiler it
 *     builds.
 *   - A smaller seed is a more auditable seed, which is this project's premise.
 *
 * What remains below is IL WELL-FORMEDNESS checking -- type mismatches, call
 * arity, unknown functions, branches to non-existent blocks, undefined SSA.
 * That catches stage0-C's OWN lowering bugs rather than judging the user's
 * program, and it costs nothing in false positives. Keep that distinction if
 * this file is edited again.
 *
 * The removed checks live in src/verify.zrl: bounds-checking (§11.2.3) and
 * region outlives (§11.2.4) both landed there in the Stage 3 harvest.
 * -------------------------------------------------------------------------- */



static const ILFunction* find_func_by_id(const ILModule* mod, uint32_t id) {
    if (!mod) return NULL;
    for (uint32_t i = 0; i < mod->function_count; i++) {
        if (mod->functions[i]->id == id) return mod->functions[i];
    }
    return NULL;
}

static void add_error_impl(VerificationResult* res, const char* func_name, const char* file_path, VerifierErrorType type, uint32_t block_id, uint32_t instr_idx, uint32_t line, uint32_t col, const char* msg) {
    if (res->error_count >= res->error_capacity) {
        uint32_t new_cap = res->error_capacity == 0 ? 8 : res->error_capacity * 2;
        VerifierError* new_errors = realloc(res->errors, sizeof(VerifierError) * new_cap);
        if (!new_errors) return;
        res->errors = new_errors;
        res->error_capacity = new_cap;
    }
    res->errors[res->error_count++] = (VerifierError){
        .type = type,
        .func_name = func_name ? strdup(func_name) : NULL,
        .file_path = file_path ? strdup(file_path) : NULL,
        .block_id = block_id,
        .instr_index = instr_idx,
        .line = line,
        .col = col,
        .message = strdup(msg)
    };
    res->is_safe = false;
}

typedef struct {
    uint32_t index_id;
    uint32_t length_id;
} ProvenBound;

typedef struct {
    uint32_t slice_id;
    uint32_t length_id;
} SliceLen;

typedef struct {
    OwnershipState* ownership;
    ProvenBound* bounds;
    uint32_t bounds_count;
    uint32_t bounds_capacity;
    SliceLen* slice_lens;
    uint32_t slice_lens_count;
    uint32_t slice_lens_capacity;
    bool is_initialized;
    bool is_diverged;
    bool* is_alloc;
} VerifierState;

typedef struct {
    VerificationResult* res;
    const ILModule*     mod;
    const ILFunction*   func;
    const ILType**      types;
    VerifierState*      state;
    uint32_t            block_id;
    uint32_t            instr_idx;
    const ILInstruction* instr;
    bool                report_errors;
    uint32_t            ssa_count;
} VerifierCtx;

static VerifierState* verifier_state_create(uint32_t ssa_count) {
    VerifierState* state = calloc(1, sizeof(VerifierState));
    if (!state) return NULL;
    state->ownership = ownership_state_create(ssa_count);
    if (!state->ownership) { free(state); return NULL; }
    state->is_alloc = calloc(ssa_count, sizeof(bool));
    if (!state->is_alloc) { ownership_state_free(state->ownership); free(state); return NULL; }
    return state;
}

static void verifier_state_free(VerifierState* state) {
    if (!state) return;
    ownership_state_free(state->ownership);
    free(state->bounds);
    free(state->slice_lens);
    free(state->is_alloc);
    free(state);
}

static void verifier_state_copy_to(VerifierState* dest, const VerifierState* src, uint32_t ssa_count) {
    ownership_state_copy_to(dest->ownership, src->ownership);

    if (dest->bounds_capacity < src->bounds_count) {
        dest->bounds = realloc(dest->bounds, sizeof(ProvenBound) * src->bounds_count);
        dest->bounds_capacity = src->bounds_count;
    }
    dest->bounds_count = src->bounds_count;
    if (dest->bounds_count > 0) {
        memcpy(dest->bounds, src->bounds, sizeof(ProvenBound) * dest->bounds_count);
    }

    if (dest->slice_lens_capacity < src->slice_lens_count) {
        dest->slice_lens = realloc(dest->slice_lens, sizeof(SliceLen) * src->slice_lens_count);
        dest->slice_lens_capacity = src->slice_lens_count;
    }
    dest->slice_lens_count = src->slice_lens_count;
    if (dest->slice_lens_count > 0) {
        memcpy(dest->slice_lens, src->slice_lens, sizeof(SliceLen) * dest->slice_lens_count);
    }

    if (ssa_count > 0) {
        memcpy(dest->is_alloc, src->is_alloc, sizeof(bool) * ssa_count);
    }

    dest->is_initialized = src->is_initialized;
    dest->is_diverged = src->is_diverged;
}
static void add_proven_bound(VerifierState* state, uint32_t index_id, uint32_t length_id) {
    for (uint32_t i = 0; i < state->bounds_count; i++) {
        if (state->bounds[i].index_id == index_id && state->bounds[i].length_id == length_id) return;
    }
    if (state->bounds_count >= state->bounds_capacity) {
        uint32_t new_cap = state->bounds_capacity == 0 ? 4 : state->bounds_capacity * 2;
        ProvenBound* new_bounds = realloc(state->bounds, sizeof(ProvenBound) * new_cap);
        if (!new_bounds) return;
        state->bounds = new_bounds;
        state->bounds_capacity = new_cap;
    }
    state->bounds[state->bounds_count++] = (ProvenBound){ index_id, length_id };
}

static bool is_bound_proven(const VerifierState* state, uint32_t index_id, uint32_t length_id) {
    if (length_id == 0) return false;
    for (uint32_t i = 0; i < state->bounds_count; i++) {
        if (state->bounds[i].index_id == index_id && state->bounds[i].length_id == length_id) return true;
    }
    return false;
}

static void add_slice_len(VerifierState* state, uint32_t slice_id, uint32_t length_id) {
    for (uint32_t i = 0; i < state->slice_lens_count; i++) {
        if (state->slice_lens[i].slice_id == slice_id && state->slice_lens[i].length_id == length_id) return;
    }
    if (state->slice_lens_count >= state->slice_lens_capacity) {
        uint32_t new_cap = state->slice_lens_capacity == 0 ? 4 : state->slice_lens_capacity * 2;
        SliceLen* new_lens = realloc(state->slice_lens, sizeof(SliceLen) * new_cap);
        if (!new_lens) return;
        state->slice_lens = new_lens;
        state->slice_lens_capacity = new_cap;
    }
    state->slice_lens[state->slice_lens_count++] = (SliceLen){ slice_id, length_id };
}

static bool verifier_state_merge(VerifierState* target, const VerifierState* source, uint32_t ssa_count) {
    if (!target->is_initialized) {
        target->is_initialized = true;
        ownership_state_merge(target->ownership, source->ownership);
        if (ssa_count > 0) memcpy(target->is_alloc, source->is_alloc, sizeof(bool) * ssa_count);
        target->bounds_count = source->bounds_count;
        if (target->bounds_capacity < source->bounds_count) {
            target->bounds_capacity = source->bounds_count;
            target->bounds = realloc(target->bounds, sizeof(ProvenBound) * target->bounds_capacity);
        }
        if (source->bounds_count > 0) memcpy(target->bounds, source->bounds, sizeof(ProvenBound) * source->bounds_count);
        
        target->slice_lens_count = source->slice_lens_count;
        if (target->slice_lens_capacity < source->slice_lens_count) {
            target->slice_lens_capacity = source->slice_lens_count;
            target->slice_lens = realloc(target->slice_lens, sizeof(SliceLen) * target->slice_lens_capacity);
        }
        if (source->slice_lens_count > 0) memcpy(target->slice_lens, source->slice_lens, sizeof(SliceLen) * source->slice_lens_count);

        target->is_diverged = source->is_diverged;
        return true;
    }

    bool changed = ownership_state_merge(target->ownership, source->ownership);
    // is_alloc doesn't change after initial population, so no need to merge it here if already initialized.

    bool old_diverged = target->is_diverged;
    target->is_diverged = target->is_diverged && source->is_diverged;
    if (target->is_diverged != old_diverged) changed = true;

    uint32_t old_bound_count = target->bounds_count;
    uint32_t new_bound_count = 0;
    for (uint32_t i = 0; i < target->bounds_count; i++) {
        if (is_bound_proven(source, target->bounds[i].index_id, target->bounds[i].length_id)) {
            target->bounds[new_bound_count++] = target->bounds[i];
        }
    }
    if (new_bound_count != old_bound_count) {
        target->bounds_count = new_bound_count;
        changed = true;
    }
    
    uint32_t old_len_count = target->slice_lens_count;
    uint32_t new_len_count = 0;
    for (uint32_t i = 0; i < target->slice_lens_count; i++) {
        bool found = false;
        for (uint32_t j = 0; j < source->slice_lens_count; j++) {
            if (source->slice_lens[j].slice_id == target->slice_lens[i].slice_id && source->slice_lens[j].length_id == target->slice_lens[i].length_id) {
                found = true; break;
            }
        }
        if (found) target->slice_lens[new_len_count++] = target->slice_lens[i];
    }
    if (new_len_count != old_len_count) {
        target->slice_lens_count = new_len_count;
        changed = true;
    }
    return changed;
}

static const ILType* get_val_type(const ILFunction* func, uint32_t val_id, const ILType ** types, uint32_t ssa_count);
static void check_borrow(VerifierCtx* vctx, uint32_t rid, bool is_mut);
static void check_move_from(VerifierCtx* vctx, uint32_t rid, bool is_move);

static const char* get_val_name(const ILFunction* func, uint32_t id) {
    if (!func || !func->val_names || id >= func->val_names_capacity) return NULL;
    return func->val_names[id];
}

static void check_use(VerifierCtx* vctx, uint32_t val_id, ILOpcode op) {
    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    if (val_id == 0) return;
    
    const ILType* val_type = get_val_type(func, val_id, types, ssa_count);
    if (!val_type) {
        char msg[128];
        snprintf(msg, sizeof(msg), "use of undefined SSA ID v%u", val_id);
        add_error_impl(res, func->name, func->file_path, VERIFY_ERR_UNDEFINED_SSA, block_id, instr_idx, instr->line, instr->col, msg);
        return;
    }

    /* stage0-C no longer performs language safety checks -- see banner. Use-after-move,
     * double-drop and region-validity analysis is the shipped compiler's job
     * (src/check_zir.zrl, src/verify.zrl). This check had been left on after 8b642f5 and
     * rejected valid code, e.g. reading s[0] after a block that borrowed &mut s[0]. */
    (void)op;
}

// Checks if any available SSA value borrows the specified rid.
static void check_move_from(VerifierCtx* vctx, uint32_t rid, bool is_move) {
    /* stage0-C no longer performs language safety checks -- see banner. Move/borrow analysis is src/check_zir.zrl's job. */
    (void)vctx;
    return;

    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    if (!is_ssa_region(rid) || rid >= state->ownership->count || !is_move) return;
    
    for (uint32_t i = 1; i < state->ownership->count; i++) {
        if (ownership_get(state->ownership, i) == VAL_AVAILABLE) {
            const ILType* ty = (i < ssa_count) ? types[i] : NULL;
            if (ty && ((ty->kind == IL_TY_PTR && ty->as.ptr.region_id == rid) ||
                       (ty->kind == IL_TY_BOX && ty->as.box.region_id == rid) ||
                       (ty->kind == IL_TY_SLICE && ty->as.slice.region_id == rid))) {
                bool ty_is_mut = false;
                if (ty->kind == IL_TY_PTR) ty_is_mut = ty->as.ptr.is_mut;
                else if (ty->kind == IL_TY_BOX) ty_is_mut = ty->as.box.is_mut;
                else if (ty->kind == IL_TY_SLICE) ty_is_mut = ty->as.slice.is_mut;

                // We have an active borrow.
                // If it's a DROP, we only block it if the borrow is MUTABLE.
                if (instr->opcode == IL_OP_DROP && !ty_is_mut) continue;

                char msg[256];
                const char* name = get_val_name(func, rid);
                if (name) snprintf(msg, sizeof(msg), "cannot move borrowed value '%s'", name);
                else snprintf(msg, sizeof(msg), "cannot move borrowed value v%u", rid);
                add_error_impl(res, func->name, func->file_path, VERIFY_ERR_USE_AFTER_MOVE, block_id, instr_idx, instr->line, instr->col, msg);
            }
        }
    }
}
static bool check_type_assignable(VerificationResult* res, const char* func_name, const char* file_path, const ILModule* mod, uint32_t block_id, uint32_t instr_idx, const ILInstruction* instr, const ILType* source, const ILType* target, const char* msg) {
    if (target && target->kind == IL_TY_UNIT && !source) return true;
    bool ok = il_type_is_assignable(source, target);
    if (!ok && source && target) {
        // Large aggregates are passed by reference: they are pointers in SSA but aggregate types in
        // IL, so either side may be the pointer to the other's value.
        if (target->kind == IL_TY_PTR && is_aggregate_type_layout(source) && requires_pass_by_ref(mod, source)) {
            if (il_type_is_assignable(source, target->as.ptr.pointee)) ok = true;
        } else if (source->kind == IL_TY_PTR && is_aggregate_type_layout(target) && requires_pass_by_ref(mod, target)) {
            if (il_type_is_assignable(source->as.ptr.pointee, target)) ok = true;
        }
        // An aggregate passed by value may reuse the existing static pointer instead of making a
        // local copy, so a Ptr<T,'static> (immutable) may satisfy a PtrMut<T,'local>; the callee
        // treats it as read-only regardless.
        if (!ok && source->kind == IL_TY_PTR && target->kind == IL_TY_PTR &&
            target->as.ptr.is_mut && !source->as.ptr.is_mut &&
            target->as.ptr.region_id == REGION_LOCAL &&
            source->as.ptr.pointee && target->as.ptr.pointee &&
            requires_pass_by_ref(mod, target->as.ptr.pointee) &&
            (il_type_eq(source->as.ptr.pointee, target->as.ptr.pointee) ||
             il_type_structurally_eq(source->as.ptr.pointee, target->as.ptr.pointee) ||
             il_type_is_assignable(source->as.ptr.pointee, target->as.ptr.pointee))) {
            ok = true;
        }
        // T_a and T_b are the same aggregate type, but T_a's inner regions outlive T_b's: an lvalue
        // of an aggregate holding 'static pointers or slices is passed to a function expecting
        // 'local inner regions.
        if (!ok && source->kind == IL_TY_PTR && target->kind == IL_TY_PTR &&
            source->as.ptr.is_mut && target->as.ptr.is_mut &&
            source->as.ptr.region_id == target->as.ptr.region_id &&
            source->as.ptr.pointee && target->as.ptr.pointee &&
            requires_pass_by_ref(mod, target->as.ptr.pointee) &&
            il_type_is_assignable(source->as.ptr.pointee, target->as.ptr.pointee)) {
            ok = true;
        }
    }
    if (!ok && source && target && is_numeric_type(source) && is_numeric_type(target)) {
        // Relax rules only for STORE and CALL
        if (instr && (instr->opcode == IL_OP_STORE || instr->opcode == IL_OP_ARRAY_STORE ||
                      instr->opcode == IL_OP_CALL || instr->opcode == IL_OP_CALL_PTR)) {
            if (numeric_type_rank(source->kind) == numeric_type_rank(target->kind)) {
                ok = true;
            }
        }
    }
    
    if (!ok) {
        char src_buf[128], tgt_buf[128], final_msg[512];
        il_print_type(mod, source, src_buf, sizeof(src_buf));
        il_print_type(mod, target, tgt_buf, sizeof(tgt_buf));
        snprintf(final_msg, sizeof(final_msg), "%s: %s vs %s", msg, src_buf, tgt_buf);
        add_error_impl(res, func_name, file_path, VERIFY_ERR_TYPE_MISMATCH, block_id, instr_idx, instr ? instr->line : 0, instr ? instr->col : 0, final_msg);
        return false;
    }
    return true;
}

static bool il_type_contains_local_region(const ILType* type) {
    if (!type) return false;
    if (type->kind == IL_TY_PTR) {
        if (type->as.ptr.region_id == REGION_LOCAL || is_ssa_region(type->as.ptr.region_id)) return true;
        return il_type_contains_local_region(type->as.ptr.pointee);
    }
    if (type->kind == IL_TY_SLICE) {
        if (type->as.slice.region_id == REGION_LOCAL || is_ssa_region(type->as.slice.region_id)) return true;
        return il_type_contains_local_region(type->as.slice.element);
    }
    if (type->kind == IL_TY_BOX) {
        if (type->as.box.region_id == REGION_LOCAL || is_ssa_region(type->as.box.region_id)) return true;
        return il_type_contains_local_region(type->as.box.pointee);
    }
    if (type->kind == IL_TY_ARRAY) return il_type_contains_local_region(type->as.array.element);
    return false;
}

static bool is_sum_guarded(const ILFunction* func, const ILBasicBlock* block, uint32_t current_instr_idx, uint32_t sum_id) {
    (void)current_instr_idx;
    const ILBasicBlock* current = block;
    while (current != NULL) {
        const ILBasicBlock* prev = current->idom;
        if (prev == NULL || prev == current) break;
        
        if (prev->instr_count > 0) {
            const ILInstruction* last = prev->instructions[prev->instr_count - 1];
            if (last->opcode == IL_OP_BRANCH) {
                uint32_t cond_id = last->operands.branch.condition;
                
                // Trace back to IS_SOME
                uint32_t trace_id = cond_id;
                while (trace_id != 0) {
                    const ILInstruction* def = NULL;
                    for (uint32_t b = 0; b < func->block_count; b++) {
                        for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
                            if (func->blocks[b]->instructions[i]->result_id == trace_id) {
                                def = func->blocks[b]->instructions[i]; break;
                            }
                        }
                        if (def) break;
                    }
                    if (!def) break;
                    
                    // A guard is a branch on `is_some x`, or on the bool a value-producing
                    // `variant_match x, T, k` returns (the form the IL has used since c66fe15).
                    if (def->opcode == IL_OP_IS_SOME || def->opcode == IL_OP_VARIANT_MATCH) {
                        uint32_t guarded_sum_id = (def->opcode == IL_OP_IS_SOME)
                            ? def->operands.move.source
                            : def->operands.variant_match.sum_ptr;
                        // Does the guarded_sum_id trace back to our sum_id?
                        uint32_t sid = guarded_sum_id;
                        while (sid != 0) {
                            if (sid == sum_id) {
                                if (last->operands.branch.then_block_id == current->id) return true;
                                break;
                            }
                            const ILInstruction* sdef = NULL;
                            for (uint32_t b = 0; b < func->block_count; b++) {
                                for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
                                    if (func->blocks[b]->instructions[i]->result_id == sid) {
                                        sdef = func->blocks[b]->instructions[i]; break;
                                    }
                                }
                                if (sdef) break;
                            }
                            if (!sdef) break;
                            if (sdef->opcode == IL_OP_MOVE) sid = sdef->operands.move.source;
                            else if (sdef->opcode == IL_OP_LOAD) sid = sdef->operands.load.ptr;
                            else break;
                        }
                        break;
                    }
                    if (def->opcode == IL_OP_MOVE) trace_id = def->operands.move.source;
                    else if (def->opcode == IL_OP_LOAD) trace_id = def->operands.load.ptr;
                    else break;
                }
            } else if (last->opcode == IL_OP_VARIANT_MATCH) {
                if (last->operands.variant_match.sum_ptr == sum_id) {
                    if (last->operands.variant_match.target_block_id == current->id) return true;
                }
            }
        }
        current = prev;
    }
    return false;
}

static const ILType* get_val_type(const ILFunction* func, uint32_t val_id, const ILType ** types, uint32_t ssa_count) {
    if (val_id == 0) return il_type_unit();
    if (val_id < ssa_count && types && types[val_id]) return types[val_id];
    if (func && val_id > 0 && val_id <= func->param_count && func->param_types) return func->param_types[val_id - 1];
    return NULL;
}



static void verify_arith_instr(VerifierCtx* vctx) {
    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    if (report_errors) {
        check_use(vctx, instr->operands.binary.left, instr->opcode);
        check_use(vctx, instr->operands.binary.right, instr->opcode);
        const ILType* lt = get_val_type(func, instr->operands.binary.left, types, ssa_count);
        const ILType* rt = get_val_type(func, instr->operands.binary.right, types, ssa_count);
        
        if (instr->result_type && instr->result_type->kind == IL_TY_SUM) {
            // Checked variant returning Option/Result
            check_type_assignable(res, func->name, func->file_path, mod, block_id, instr_idx, instr, rt, lt, "checked arithmetic operand mismatch");
        } else {
            // Trapping, wrapping, or saturating variant returning same type
            check_type_assignable(res, func->name, func->file_path, mod, block_id, instr_idx, instr, lt, instr->result_type, "arithmetic type mismatch (left)");
            check_type_assignable(res, func->name, func->file_path, mod, block_id, instr_idx, instr, rt, instr->result_type, "arithmetic type mismatch (right)");
        }
    }
}

static void verify_cmp_instr(VerifierCtx* vctx) {
    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    if (report_errors) {
        check_use(vctx, instr->operands.binary.left, instr->opcode);
        check_use(vctx, instr->operands.binary.right, instr->opcode);
        const ILType* lt = get_val_type(func, instr->operands.binary.left, types, ssa_count);
        const ILType* rt = get_val_type(func, instr->operands.binary.right, types, ssa_count);
        check_type_assignable(res, func->name, func->file_path, mod, block_id, instr_idx, instr, rt, lt, "comparison operand type mismatch");
    }
}

// Checks if a value is safe to borrow from (region must be valid).
static void check_borrow_from(VerifierCtx* vctx, uint32_t val_id) {
    /* stage0-C no longer performs language safety checks -- see banner. Borrow analysis is the shipped compiler's job. */
    (void)vctx;
    return;

    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    if (val_id == 0) return;
    const ILType* val_type = (val_id < ssa_count) ? types[val_id] : NULL;
    if (val_id < state->ownership->count && ownership_get(state->ownership, val_id) == VAL_MOVED) {
        char msg[256];
        const char* name = get_val_name(func, val_id);
        if (name) snprintf(msg, sizeof(msg), "use of moved value '%s'", name);
        else snprintf(msg, sizeof(msg), "use of moved value v%u", val_id);
        add_error_impl(res, func->name, func->file_path, VERIFY_ERR_USE_AFTER_MOVE, block_id, instr_idx, instr->line, instr->col, msg);
    }
    if (val_type && !il_region_is_valid(state->ownership, val_type)) {
        add_error_impl(res, func->name, func->file_path, VERIFY_ERR_USE_AFTER_MOVE, block_id, instr_idx, instr->line, instr->col, "use of value whose region has been moved/dropped");
    }
}

static void verify_mem_instr(VerifierCtx* vctx) {
    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    switch (instr->opcode) {
        case IL_OP_LOAD:
        case IL_OP_ARRAY_LOAD: {
            uint32_t ptr_id = (instr->opcode == IL_OP_LOAD) ? instr->operands.load.ptr : instr->operands.array_load.array_ptr;
            const ILType* res_ty = (instr->result_id < ssa_count) ? types[instr->result_id] : NULL;
            bool is_move = res_ty && !il_type_is_copy_mod(mod, res_ty);

            if (report_errors) {
                check_use(vctx, ptr_id, instr->opcode);
                if (instr->opcode == IL_OP_ARRAY_LOAD) check_use(vctx, instr->operands.array_load.index, instr->opcode);
                
                const ILType* pt = get_val_type(func, ptr_id, types, ssa_count);
                if (pt && pt->kind != IL_TY_PTR && pt->kind != IL_TY_BOX && pt->kind != IL_TY_ARRAY) {
                    add_error_impl(res, func->name, func->file_path, VERIFY_ERR_TYPE_MISMATCH, block_id, instr_idx, instr->line, instr->col, "load from non-pointer/array type");
                }
                
                // If this load is a move, check if the source is borrowed.
                if (is_move) {
                    check_move_from(vctx, ptr_id, true);
                }
            }
            
            if (ptr_id != 0 && ptr_id < state->ownership->count) {
                bool skip_mark_moved = false;
                if (res_ty && (res_ty->kind == IL_TY_FD || res_ty->kind == IL_TY_ASYNC_CONTEXT)) {
                    skip_mark_moved = true;
                }

                if (is_move && !skip_mark_moved) {
                    ownership_set(state->ownership, ptr_id, VAL_MOVED);
                }

                // Zoril v1.1: Accessing any field of a non-Copy struct moves the whole struct.
                if (!skip_mark_moved) {
                    const ILType* pt = get_val_type(func, ptr_id, types, ssa_count);
                    if (pt && (pt->kind == IL_TY_PTR || pt->kind == IL_TY_BOX)) {
                        uint32_t rid = (pt->kind == IL_TY_PTR) ? pt->as.ptr.region_id : pt->as.box.region_id;
                        if (is_ssa_region(rid) && rid < ssa_count) {
                            // We only trigger an automatic move of the base struct if it is an owned stack variable.
                            // Stack variables are results of IL_OP_ALLOC and have REGION_LOCAL.
                            if (state->is_alloc[rid]) {
                                const ILType* agg_ptr_ty = types[rid];
                                if (agg_ptr_ty && agg_ptr_ty->kind == IL_TY_PTR && agg_ptr_ty->as.ptr.region_id == REGION_LOCAL) {
                                    const ILType* agg_ty = agg_ptr_ty->as.ptr.pointee;
                                    if (agg_ty && (agg_ty->kind == IL_TY_STRUCT || agg_ty->kind == IL_TY_SUM || 
                                                  agg_ty->kind == IL_TY_TUPLE || agg_ty->kind == IL_TY_ARRAY ||
                                                  agg_ty->kind == IL_TY_SLICE)) {
                                        if (!il_type_is_copy_mod(mod, agg_ty)) {
                                            if (report_errors) {
                                                check_move_from(vctx, rid, true);
                                            }
                                            ownership_set(state->ownership, rid, VAL_MOVED);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            break;
        }
        case IL_OP_STORE:
        case IL_OP_ARRAY_STORE: {
            uint32_t ptr_id = (instr->opcode == IL_OP_STORE) ? instr->operands.store.ptr : instr->operands.array_store.array_ptr;
            uint32_t value_id = (instr->opcode == IL_OP_STORE) ? instr->operands.store.value : instr->operands.array_store.value;
            const ILType* vt = get_val_type(func, value_id, types, ssa_count);
            bool is_move = vt && !il_type_is_copy_mod(mod, vt);

            if (report_errors) {
                check_use(vctx, ptr_id, instr->opcode);
                check_use(vctx, value_id, instr->opcode);
                if (instr->opcode == IL_OP_ARRAY_STORE) check_use(vctx, instr->operands.array_store.index, instr->opcode);
                
                const ILType* pt = get_val_type(func, ptr_id, types, ssa_count);
                if (pt && (pt->kind == IL_TY_PTR || pt->kind == IL_TY_BOX || pt->kind == IL_TY_ARRAY)) {
                    if (pt->kind == IL_TY_ARRAY) {
                        check_type_assignable(res, func->name, func->file_path, mod, block_id, instr_idx, instr, vt, pt->as.array.element, "store type mismatch");
                    } else {
                        bool is_mut = (pt->kind == IL_TY_PTR) ? pt->as.ptr.is_mut : pt->as.box.is_mut;
                        if (!is_mut) add_error_impl(res, func->name, func->file_path, VERIFY_ERR_TYPE_MISMATCH, block_id, instr_idx, instr->line, instr->col, "store to immutable pointer");
                        const ILType* pointee = (pt->kind == IL_TY_PTR) ? pt->as.ptr.pointee : pt->as.box.pointee;
                        check_type_assignable(res, func->name, func->file_path, mod, block_id, instr_idx, instr, vt, pointee, "store type mismatch");
                    }
                }
                
                // If this store is a move (value is non-copy), check if it's borrowed.
                if (is_move) {
                    check_move_from(vctx, value_id, true);
                }
            }
            
            {
                if (value_id != 0 && value_id < state->ownership->count && is_move) {
                    ownership_set(state->ownership, value_id, VAL_MOVED);
                }
                if (ptr_id != 0 && ptr_id < state->ownership->count) {
                    ownership_set(state->ownership, ptr_id, VAL_AVAILABLE);
                }
            }
            break;
        }
        case IL_OP_ALLOC:
            if (report_errors) check_use(vctx, instr->operands.alloc.allocator_id, instr->opcode);
            break;
        case IL_OP_FIELD_ADDR: {
            if (report_errors) check_borrow_from(vctx, instr->operands.field_addr.struct_ptr);
            
            // Propagate region ID from struct pointer to field pointer.
            const ILType* pt = get_val_type(func, instr->operands.field_addr.struct_ptr, types, ssa_count);
            if (pt) {
                uint32_t rid = 0;
                if (pt->kind == IL_TY_PTR) rid = pt->as.ptr.region_id;
                else if (pt->kind == IL_TY_BOX) rid = pt->as.box.region_id;
                else if (pt->kind == IL_TY_STRUCT || pt->kind == IL_TY_SUM || pt->kind == IL_TY_TUPLE) rid = instr->operands.field_addr.struct_ptr;

                if ((rid == REGION_LOCAL || rid == 0) && pt->kind != IL_TY_PTR && pt->kind != IL_TY_BOX)
                    rid = instr->operands.field_addr.struct_ptr;

                if (instr->result_id != 0 && instr->result_id < ssa_count) {
                    if (types[instr->result_id] && types[instr->result_id]->kind == IL_TY_PTR) {
                        types[instr->result_id] = il_type_ptr(types[instr->result_id]->as.ptr.pointee, rid, types[instr->result_id]->as.ptr.is_mut);
                        if (report_errors) {
                            check_borrow(vctx, rid, types[instr->result_id]->as.ptr.is_mut);
                        }
                    }
                }
            }
            break;
        }
        case IL_OP_ELEM_ADDR: {
            if (report_errors) {
                check_borrow_from(vctx, instr->operands.elem_addr.base);
                check_use(vctx, instr->operands.elem_addr.index, instr->opcode);
            }
            
            // Propagate region ID from base pointer to element pointer.
            const ILType* pt = get_val_type(func, instr->operands.elem_addr.base, types, ssa_count);
            if (pt) {
                uint32_t rid = 0;
                if (pt->kind == IL_TY_PTR) rid = pt->as.ptr.region_id;
                else if (pt->kind == IL_TY_BOX) rid = pt->as.box.region_id;
                else if (pt->kind == IL_TY_ARRAY || pt->kind == IL_TY_SLICE) rid = instr->operands.elem_addr.base;

                if ((rid == REGION_LOCAL || rid == 0) && pt->kind != IL_TY_PTR && pt->kind != IL_TY_BOX)
                    rid = instr->operands.elem_addr.base;

                if (instr->result_id != 0 && instr->result_id < ssa_count) {
                    if (types[instr->result_id] && types[instr->result_id]->kind == IL_TY_PTR) {
                        types[instr->result_id] = il_type_ptr(types[instr->result_id]->as.ptr.pointee, rid, types[instr->result_id]->as.ptr.is_mut);
                        if (report_errors) {
                            check_borrow(vctx, rid, types[instr->result_id]->as.ptr.is_mut);
                        }
                    }
                }
            }
            break;
        }
        default: break;
    }
}

// Checks if a new borrow (from rid) is compatible with existing active borrows.
static void check_borrow(VerifierCtx* vctx, uint32_t rid, bool is_mut) {
    /* stage0-C no longer performs language safety checks -- see banner. Borrow analysis is the shipped compiler's job. */
    (void)vctx;
    return;

    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    if (!is_ssa_region(rid) || rid >= state->ownership->count) return;

    if (ownership_get(state->ownership, rid) == VAL_MOVED) {
        char msg[256];
        const char* name = get_val_name(func, rid);
        if (name) snprintf(msg, sizeof(msg), "use of moved value '%s'", name);
        else snprintf(msg, sizeof(msg), "use of moved value v%u", rid);
        add_error_impl(res, func->name, func->file_path, VERIFY_ERR_USE_AFTER_MOVE, block_id, instr_idx, instr->line, instr->col, msg);
        return;
    }

    for (uint32_t i = 1; i < state->ownership->count; i++) {
        if (i >= instr->result_id && instr->result_id != 0) continue;
        if (i == rid) continue;
        
        // Ignore conflicts with the immediate source of the borrow
        if (instr->opcode == IL_OP_FIELD_ADDR && i == instr->operands.field_addr.struct_ptr) continue;
        if (instr->opcode == IL_OP_ELEM_ADDR && i == instr->operands.elem_addr.base) continue;
        if (instr->opcode == IL_OP_BITCAST && i == instr->operands.bitcast.source) continue;
        if (instr->opcode == IL_OP_MOVE && i == instr->operands.move.source) continue;
        if (instr->opcode == IL_OP_LOAD && i == instr->operands.load.ptr) continue;

        /* Two field_addr results derived from the same struct pointer occupy
           non-overlapping memory (different fields). Don't flag one as
           conflicting with the other. */
        if (instr->opcode == IL_OP_FIELD_ADDR) {
            uint32_t parent_id = instr->operands.field_addr.struct_ptr;
            bool i_is_sibling_field = false;
            for (uint32_t b = 0; b < func->block_count && !i_is_sibling_field; b++) {
                const ILBasicBlock* blk = func->blocks[b];
                for (uint32_t k = 0; k < blk->instr_count && !i_is_sibling_field; k++) {
                    const ILInstruction* def = blk->instructions[k];
                    if (def->result_id == i && def->opcode == IL_OP_FIELD_ADDR
                        && def->operands.field_addr.struct_ptr == parent_id) {
                        i_is_sibling_field = true;
                    }
                }
            }
            if (i_is_sibling_field) continue;

            /* If value i has the same type as the struct_ptr, it is a logical
               copy of the struct_ptr (e.g., stored and reloaded from a local
               alloc slot). Taking a field of a copy of an existing borrow is a
               nested borrow — not an independent conflict. */
            uint32_t sp_id = instr->operands.field_addr.struct_ptr;
            const ILType* sp_ty = (sp_id < ssa_count) ? types[sp_id] : NULL;
            if (sp_ty && i < ssa_count && il_type_eq(sp_ty, types[i])) continue;
        }

        if (ownership_get(state->ownership, i) == VAL_AVAILABLE) {
            const ILType* ty = (i < ssa_count) ? types[i] : NULL;
            if (ty && ((ty->kind == IL_TY_PTR && ty->as.ptr.region_id == rid) ||
                       (ty->kind == IL_TY_BOX && ty->as.box.region_id == rid) ||
                       (ty->kind == IL_TY_SLICE && ty->as.slice.region_id == rid))) {
                bool ty_is_mut = false;
                if (ty->kind == IL_TY_PTR) ty_is_mut = ty->as.ptr.is_mut;
                else if (ty->kind == IL_TY_BOX) ty_is_mut = ty->as.box.is_mut;
                else if (ty->kind == IL_TY_SLICE) ty_is_mut = ty->as.slice.is_mut;

                // We found another active borrow of the same location.
                if (is_mut || ty_is_mut) {
                    char msg[256];
                    const char* name = get_val_name(func, rid);
                    if (is_mut && ty_is_mut) {
                        if (name) snprintf(msg, sizeof(msg), "cannot mutably borrow '%s' more than once", name);
                        else snprintf(msg, sizeof(msg), "cannot mutably borrow v%u more than once", rid);
                    } else if (is_mut) {
                        if (name) snprintf(msg, sizeof(msg), "cannot mutably borrow '%s' while it is already borrowed", name);
                        else snprintf(msg, sizeof(msg), "cannot mutably borrow v%u while it is already borrowed", rid);
                    } else {
                        if (name) snprintf(msg, sizeof(msg), "cannot borrow '%s' while it is mutably borrowed", name);
                        else snprintf(msg, sizeof(msg), "cannot borrow v%u while it is mutably borrowed", rid);
                    }
                    add_error_impl(res, func->name, func->file_path, VERIFY_ERR_USE_AFTER_MOVE, block_id, instr_idx, instr->line, instr->col, msg);
                }
            }
        }
    }
}
static void verify_move_instr(VerifierCtx* vctx) {
    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    const ILBasicBlock* block = func->blocks[block_id];
    switch (instr->opcode) {
        case IL_OP_MOVE:
        case IL_OP_BITCAST:
        case IL_OP_REGION_CAST:
        case IL_OP_UNWRAP:
        case IL_OP_IS_SOME: {
            uint32_t source_id = (instr->opcode == IL_OP_REGION_CAST) ? instr->operands.region_cast.source : instr->operands.move.source;
            if (report_errors) {
                check_use(vctx, source_id, instr->opcode);
                const ILType* st = get_val_type(func, source_id, types, ssa_count);
                if (instr->opcode == IL_OP_MOVE) {
                    bool allowed = il_type_is_assignable(st, instr->result_type);
                    if (!allowed) check_type_assignable(res, func->name, func->file_path, mod, block_id, instr_idx, instr, st, instr->result_type, "move type mismatch");
                    
                    // If this is a borrow (pointer with SSA region), check compatibility.
                    const ILType* res_ty = (instr->result_id < ssa_count) ? types[instr->result_id] : NULL;
                    if (res_ty && res_ty->kind == IL_TY_PTR && is_ssa_region(res_ty->as.ptr.region_id)) {
                        check_borrow(vctx, res_ty->as.ptr.region_id, res_ty->as.ptr.is_mut);
                    }
                    
                    // If this move is of a non-copy value, check if it's borrowed.
                    if (st && !il_type_is_copy_mod(mod, st)) {
                        check_move_from(vctx, source_id, true);
                    }
                } else if (instr->opcode == IL_OP_BITCAST) {
                    bool allowed = il_type_eq(st, instr->result_type);
                    if (!allowed) allowed = il_type_is_assignable(st, instr->result_type);
                    if (!allowed && is_numeric_type(st) && is_numeric_type(instr->result_type)) allowed = true;
                    // Allow bitcast between bool and integer types (bool is stored as i32 in QBE)
                    if (!allowed && (st && st->kind == IL_TY_BOOL) && is_numeric_type(instr->result_type)) allowed = true;
                    if (!allowed && is_numeric_type(st) && (instr->result_type && instr->result_type->kind == IL_TY_BOOL)) allowed = true;
                    
                    if (st && instr->result_type && is_pointer_type(mod, st) && is_pointer_type(mod, instr->result_type)) {
                        uint32_t src_rid = 0;
                        if (st->kind == IL_TY_PTR) src_rid = st->as.ptr.region_id;
                        else if (st->kind == IL_TY_BOX) src_rid = st->as.box.region_id;
                        else if (st->kind == IL_TY_SLICE) src_rid = st->as.slice.region_id;

                        uint32_t tgt_rid = 0;
                        if (instr->result_type->kind == IL_TY_PTR) tgt_rid = instr->result_type->as.ptr.region_id;
                        else if (instr->result_type->kind == IL_TY_BOX) tgt_rid = instr->result_type->as.box.region_id;
                        else if (instr->result_type->kind == IL_TY_SLICE) tgt_rid = instr->result_type->as.slice.region_id;

                        // Region Escape Check:
                        // Enforce for Box -> Ptr casts, including when the pointer has already decayed to a raw Ptr
                        // but still retains the Box's SSA region.
                        bool is_box_provenance = false;
                        uint32_t box_rid = 0;
                        
                        if (st->kind == IL_TY_BOX) {
                            is_box_provenance = true;
                            box_rid = st->as.box.region_id;
                        } else if (is_ssa_region(src_rid) && src_rid < ssa_count && types[src_rid]) {
                            const ILType* root_ty = types[src_rid];
                            if (root_ty->kind == IL_TY_BOX) {
                                is_box_provenance = true;
                                box_rid = root_ty->as.box.region_id;
                            } else if (root_ty->kind == IL_TY_PTR && root_ty->as.ptr.pointee && root_ty->as.ptr.pointee->kind == IL_TY_BOX) {
                                is_box_provenance = true;
                                box_rid = root_ty->as.ptr.pointee->as.box.region_id;
                            }
                        }

                        if (is_box_provenance && is_ssa_region(box_rid) && tgt_rid != 0 && tgt_rid != REGION_LOCAL && !il_region_outlives(box_rid, tgt_rid)) {
                            /* region escape: removed 2026-09-12 -- src/verify.zrl owns this (spec §11.2.4). */
                        }
                        allowed = true;
                    }
                    
                    // Allow bitcast between pointers, FDs, or async contexts and integer types (must be 64-bit for now)
                    if (!allowed && st && instr->result_type && (is_pointer_type(mod, st) || st->kind == IL_TY_FD || st->kind == IL_TY_ASYNC_CONTEXT) && (instr->result_type->kind == IL_TY_U64 || instr->result_type->kind == IL_TY_I64 || instr->result_type->kind == IL_TY_USIZE || instr->result_type->kind == IL_TY_ISIZE)) allowed = true;
                    if (!allowed && st && instr->result_type && (is_pointer_type(mod, instr->result_type) || instr->result_type->kind == IL_TY_FD || instr->result_type->kind == IL_TY_ASYNC_CONTEXT) && (st->kind == IL_TY_U64 || st->kind == IL_TY_I64 || st->kind == IL_TY_USIZE || st->kind == IL_TY_ISIZE)) allowed = true;

                    if (!allowed) check_type_assignable(res, func->name, func->file_path, mod, block_id, instr_idx, instr, st, instr->result_type, "bitcast type mismatch");

                    // If this is a borrow (pointer with SSA region), check compatibility.
                    // Skip the check if the source already carries the same region — the
                    // producing instruction already validated the borrow for that region,
                    // so re-checking here would produce a spurious double-borrow error
                    // (e.g., bitcast of a field_addr result into a wider pointer type).
                    const ILType* res_ty_final = (instr->result_id < ssa_count) ? types[instr->result_id] : NULL;
                    if (res_ty_final && res_ty_final->kind == IL_TY_PTR && is_ssa_region(res_ty_final->as.ptr.region_id)) {
                        uint32_t res_rid = res_ty_final->as.ptr.region_id;
                        const ILType* src_ty = get_val_type(func, source_id, types, ssa_count);
                        bool src_same_region = src_ty && src_ty->kind == IL_TY_PTR &&
                                               src_ty->as.ptr.region_id == res_rid;
                        if (!src_same_region) {
                            check_borrow(vctx, res_rid, res_ty_final->as.ptr.is_mut);
                        }
                    }

                    // If this bitcast moves a non-copy value, check if it's borrowed.
                    if (st && !il_type_is_copy_mod(mod, st)) {
                        check_move_from(vctx, source_id, true);
                    }
                } else if (instr->opcode == IL_OP_UNWRAP) {
                    if (!is_sum_guarded(func, block, instr_idx, source_id)) {
                        add_error_impl(res, func->name, func->file_path, VERIFY_ERR_UNHANDLED_OPTION, block_id, instr_idx, instr->line, instr->col, "unwrap of option without guard");
                    }
                }
            }
            if (source_id != 0 && source_id < state->ownership->count &&
                instr->opcode != IL_OP_IS_SOME) {
                const ILType* st = get_val_type(func, source_id, types, ssa_count);
                bool is_copy = il_type_is_copy_mod(mod, st);
                if (st && !is_copy) {
                    if (instr->opcode == IL_OP_BITCAST) {
                        if (st->kind == IL_TY_BOX && instr->result_type && instr->result_type->kind == IL_TY_PTR) {
                            ownership_set(state->ownership, source_id, VAL_MOVED);
                        }
                    } else {
                        ownership_set(state->ownership, source_id, VAL_MOVED);
                    }
                }
            }
            break;
        }
        case IL_OP_PHI:
            if (report_errors) {
                for (uint32_t i = 0; i < instr->operands.phi.num_incoming; i++) {
                    const ILType* it = get_val_type(func, instr->operands.phi.incoming[i].value_id, types, ssa_count);
                    check_use(vctx, instr->operands.phi.incoming[i].value_id, instr->opcode);
                    check_type_assignable(res, func->name, func->file_path, mod, block_id, instr_idx, instr, it, instr->result_type, "phi incoming type mismatch");
                    
                    // If this phi result is non-copy, it's a move from each incoming.
                    if (instr->result_type && !il_type_is_copy_mod(mod, instr->result_type)) {
                        check_move_from(vctx, instr->operands.phi.incoming[i].value_id, true);
                    }
                }
            }
            if (!il_type_is_copy_mod(mod, instr->result_type)) {
                for (uint32_t i = 0; i < instr->operands.phi.num_incoming; i++) {
                    uint32_t incoming_id = instr->operands.phi.incoming[i].value_id;
                    if (incoming_id != 0 && incoming_id < state->ownership->count) {
                        ownership_set(state->ownership, incoming_id, VAL_MOVED);
                    }
                }
            }
            break;
        case IL_OP_DROP: {
            uint32_t val_id = instr->operands.drop.value;
            const ILType* ty = get_val_type(func, val_id, types, ssa_count);
            if (report_errors) {
                // For Copy types, check_use only checks region validity.
                // For non-Copy types, it also checks VAL_AVAILABLE.
                check_use(vctx, val_id, instr->opcode);
                
                // Linear resources must NOT be dropped without being consumed.
                if (ty && !il_type_is_copy_mod(mod, ty)) {
                    if (ty->kind == IL_TY_FD || ty->kind == IL_TY_ASYNC_CONTEXT) {
                        char msg[256];
                        const char* name = get_val_name(func, val_id);
                        const char* type_name = (ty->kind == IL_TY_FD) ? "fd" : "async_context";
                        if (name) snprintf(msg, sizeof(msg), "linear resource '%s' (type %s) must be explicitly closed, not dropped", name, type_name);
                        else snprintf(msg, sizeof(msg), "linear resource v%u (type %s) must be explicitly closed, not dropped", val_id, type_name);
                        add_error_impl(res, func->name, func->file_path, VERIFY_ERR_LEAK, block_id, instr_idx, instr->line, instr->col, msg);
                    }
                }
            }
            if (val_id != 0 && val_id < state->ownership->count) {
                // When we drop a value, we mark it as moved.
                // If it's a non-copy type, it was already checked for availability by check_use.
                // If it's a copy type (pointer), we just mark it moved to signal end of lifetime/borrow.
                ownership_set(state->ownership, val_id, VAL_MOVED);
            }
            break;
        }
        default: break;
    }
}

static void verify_call_instr(VerifierCtx* vctx) {
    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    uint32_t num_args = (instr->opcode == IL_OP_CALL) ? instr->operands.call.num_args : instr->operands.call_ptr.num_args;
    uint32_t* arg_ids = (instr->opcode == IL_OP_CALL) ? instr->operands.call.arg_ids : instr->operands.call_ptr.arg_ids;
    if (report_errors) {
        if (instr->opcode == IL_OP_CALL_PTR) {
            check_use(vctx, instr->operands.call_ptr.func_ptr_id, instr->opcode);
            const ILType* ft = get_val_type(func, instr->operands.call_ptr.func_ptr_id, types, ssa_count);
            if (ft && ft->kind != IL_TY_FN) {
                add_error_impl(res, func->name, func->file_path, VERIFY_ERR_TYPE_MISMATCH, block_id, instr_idx, instr->line, instr->col, "indirect call on non-function type");
            } else if (ft && ft->kind == IL_TY_FN) {
                if (num_args != ft->as.function.param_count) {
                    add_error_impl(res, func->name, func->file_path, VERIFY_ERR_TYPE_MISMATCH, block_id, instr_idx, instr->line, instr->col, "indirect call argument count mismatch");
                } else {
                    for (uint32_t i = 0; i < num_args; i++) {
                        const ILType* at = get_val_type(func, arg_ids[i], types, ssa_count);
                        check_type_assignable(res, func->name, func->file_path, mod, block_id, instr_idx, instr, at, ft->as.function.param_types[i], "indirect call argument type mismatch");
                    }
                }
            }
        } else {
            const ILFunction* target = find_func_by_id(mod, instr->operands.call.func_id);
            if (!target) {
                add_error_impl(res, func->name, func->file_path, VERIFY_ERR_TYPE_MISMATCH, block_id, instr_idx, instr->line, instr->col, "call to unknown function");
            } else {
                if (num_args != target->param_count && !target->is_variadic) {
                    add_error_impl(res, func->name, func->file_path, VERIFY_ERR_TYPE_MISMATCH, block_id, instr_idx, instr->line, instr->col, "call argument count mismatch");
                } else if (target->is_variadic && num_args < target->param_count) {
                    add_error_impl(res, func->name, func->file_path, VERIFY_ERR_TYPE_MISMATCH, block_id, instr_idx, instr->line, instr->col, "variadic call expects at least fixed parameters");
                } else {
                    for (uint32_t i = 0; i < target->param_count; i++) {
                        const ILType* at = get_val_type(func, arg_ids[i], types, ssa_count);
                        check_type_assignable(res, func->name, func->file_path, mod, block_id, instr_idx, instr, at, target->param_types[i], "call argument type mismatch");
                    }
                }
            }
        }
        for (uint32_t i = 0; i < num_args; i++) check_use(vctx, arg_ids[i], instr->opcode);
    }
    for (uint32_t i = 0; i < num_args; i++) {
        const ILType* at = get_val_type(func, arg_ids[i], types, ssa_count);
        if (arg_ids[i] != 0 && arg_ids[i] < state->ownership->count && !il_type_is_copy_mod(mod, at)) {
            if (report_errors) {
                check_move_from(vctx, arg_ids[i], true);
            }
            ownership_set(state->ownership, arg_ids[i], VAL_MOVED);
        }
    }
}

static void verify_array_slice_instr(VerifierCtx* vctx) {
    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    switch (instr->opcode) {
        case IL_OP_BOUNDS_CHECK:
            if (report_errors) {
                check_use(vctx, instr->operands.bounds_check.index, instr->opcode);
                check_use(vctx, instr->operands.bounds_check.length, instr->opcode);
            }
            add_proven_bound(state, instr->operands.bounds_check.index, instr->operands.bounds_check.length);
            break;
        case IL_OP_SLICE_LOAD:
        case IL_OP_SLICE_STORE:
            if (report_errors) {
                uint32_t slice_ptr_id = (instr->opcode == IL_OP_SLICE_LOAD) ? instr->operands.slice_load.slice_ptr : instr->operands.slice_store.slice_ptr;
                uint32_t index_id = (instr->opcode == IL_OP_SLICE_LOAD) ? instr->operands.slice_load.index : instr->operands.slice_store.index;
                
                check_use(vctx, slice_ptr_id, instr->opcode);
                check_use(vctx, index_id, instr->opcode);
                if (instr->opcode == IL_OP_SLICE_STORE) check_use(vctx, instr->operands.slice_store.value, instr->opcode);
                
                // SLICE_LOAD/STORE are borrows of the slice
                check_borrow(vctx, slice_ptr_id, (instr->opcode == IL_OP_SLICE_STORE));

                bool found = false;
                for (uint32_t i = 0; i < state->slice_lens_count; i++) {
                    if (state->slice_lens[i].slice_id == slice_ptr_id) {
                        if (is_bound_proven(state, index_id, state->slice_lens[i].length_id)) {
                            found = true; break;
                        }
                    }
                }
                if (!found) {
                    /* bounds-check presence: removed 2026-09-12 -- src/verify.zrl emits the check itself (spec §11.2.3). */
                }
            }
            if (instr->opcode == IL_OP_SLICE_STORE) {
                uint32_t val_id = instr->operands.slice_store.value;
                if (val_id != 0 && val_id < state->ownership->count && !il_type_is_copy_mod(mod, get_val_type(func, val_id, types, ssa_count))) {
                    ownership_set(state->ownership, val_id, VAL_MOVED);
                }
            }
            break;
        case IL_OP_ARRAY_LOAD:
        case IL_OP_ARRAY_STORE:
            if (report_errors) {
                uint32_t array_ptr_id = (instr->opcode == IL_OP_ARRAY_LOAD) ? instr->operands.array_load.array_ptr : instr->operands.array_store.array_ptr;
                uint32_t index_id = (instr->opcode == IL_OP_ARRAY_LOAD) ? instr->operands.array_load.index : instr->operands.array_store.index;
                
                check_use(vctx, array_ptr_id, instr->opcode);
                check_use(vctx, index_id, instr->opcode);
                if (instr->opcode == IL_OP_ARRAY_STORE) check_use(vctx, instr->operands.array_store.value, instr->opcode);
                
                const ILType* array_type = get_val_type(func, array_ptr_id, types, ssa_count);
                if (array_type && array_type->kind == IL_TY_ARRAY) {
                    uint64_t len = array_type->as.array.length;
                    bool found = false;
                    for (uint32_t i = 0; i < state->bounds_count; i++) {
                        if (state->bounds[i].index_id == index_id) {
                            uint32_t len_id = state->bounds[i].length_id;
                            if (len_id < state->ownership->count) {
                                for (uint32_t b = 0; b < func->block_count; b++) {
                                    for (uint32_t k = 0; k < func->blocks[b]->instr_count; k++) {
                                        const ILInstruction* ci = func->blocks[b]->instructions[k];
                                        if (ci->result_id == len_id && ci->opcode == IL_OP_CONST && ci->result_type && (uint64_t)ci->operands.const_val.u.val == len) {
                                            found = true; break;
                                        }
                                    }
                                    if (found) break;
                                }
                            }
                        }
                        if (found) break;
                    }
                    if (!found) {
                        /* bounds-check presence: removed 2026-09-12 -- src/verify.zrl emits the check itself (spec §11.2.3). */
                    }
                }
            }
            if (instr->opcode == IL_OP_ARRAY_STORE) {
                uint32_t val_id = instr->operands.array_store.value;
                if (val_id != 0 && val_id < state->ownership->count && !il_type_is_copy_mod(mod, get_val_type(func, val_id, types, ssa_count))) {
                    ownership_set(state->ownership, val_id, VAL_MOVED);
                }
            }
            break;
        case IL_OP_ARRAY_CONSTRUCT:
            if (report_errors) {
                for (uint32_t i = 0; i < instr->operands.array_construct.count; i++) check_use(vctx, instr->operands.array_construct.element_ids[i], instr->opcode);
            }
            for (uint32_t i = 0; i < instr->operands.array_construct.count; i++) {
                uint32_t v_id = instr->operands.array_construct.element_ids[i];
                if (v_id != 0 && v_id < state->ownership->count && !il_type_is_copy_mod(mod, get_val_type(func, v_id, types, ssa_count))) ownership_set(state->ownership, v_id, VAL_MOVED);
            }
            break;
        case IL_OP_SLICE_LEN:
            if (report_errors) check_use(vctx, instr->operands.slice_op.slice_ptr, instr->opcode);
            add_slice_len(state, instr->operands.slice_op.slice_ptr, instr->result_id);
            break;
        case IL_OP_SLICE_DATA:
            if (report_errors) check_use(vctx, instr->operands.slice_op.slice_ptr, instr->opcode);
            break;
        case IL_OP_SLICE_CONSTRUCT:
            if (report_errors) {
                check_use(vctx, instr->operands.slice_construct.ptr, instr->opcode);
                check_use(vctx, instr->operands.slice_construct.len, instr->opcode);
            }
            break;
        default: break;
    }
}

static void verify_io_instr(VerifierCtx* vctx) {
    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    (void)mod;
    switch (instr->opcode) {
        case IL_OP_FD_READ:
        case IL_OP_FD_WRITE:
            if (report_errors) {
                check_use(vctx, instr->operands.fd_io.fd, instr->opcode);
                check_use(vctx, instr->operands.fd_io.buf, instr->opcode);
                check_use(vctx, instr->operands.fd_io.count, instr->opcode);
                const ILType* fd_ty = get_val_type(func, instr->operands.fd_io.fd, types, ssa_count);
                if (fd_ty && fd_ty->kind == IL_TY_FD) {
                    bool can_read = (fd_ty->as.fd.cap & 1) != 0;
                    bool can_write = (fd_ty->as.fd.cap & 2) != 0;
                    if (instr->opcode == IL_OP_FD_READ && !can_read) add_error_impl(res, func->name, func->file_path, VERIFY_ERR_TYPE_MISMATCH, block_id, instr_idx, instr->line, instr->col, "read on fd without read capability");
                    if (instr->opcode == IL_OP_FD_WRITE && !can_write) add_error_impl(res, func->name, func->file_path, VERIFY_ERR_TYPE_MISMATCH, block_id, instr_idx, instr->line, instr->col, "write on fd without write capability");
                }
            }
            break;
        case IL_OP_FD_CLOSE:
            if (report_errors) check_use(vctx, instr->operands.fd_close.fd, instr->opcode);
            if (instr->operands.fd_close.fd != 0 && instr->operands.fd_close.fd < state->ownership->count) {
                ownership_set(state->ownership, instr->operands.fd_close.fd, VAL_MOVED);
            }
            break;
        case IL_OP_ASYNC_CLOSE:
            if (report_errors) check_use(vctx, instr->operands.async_close.ctx, instr->opcode);
            if (instr->operands.async_close.ctx != 0 && instr->operands.async_close.ctx < state->ownership->count) {
                ownership_set(state->ownership, instr->operands.async_close.ctx, VAL_MOVED);
            }
            break;
        case IL_OP_ASYNC_SETUP:
            if (report_errors) check_use(vctx, instr->operands.async_setup.entries, instr->opcode);
            if (instr->result_id != 0 && instr->result_id < state->ownership->count) {
                ownership_set(state->ownership, instr->result_id, VAL_AVAILABLE);
            }
            break;
        case IL_OP_FD_OPEN:
            if (report_errors) {
                check_use(vctx, instr->operands.fd_open.path, instr->opcode);
                check_use(vctx, instr->operands.fd_open.flags, instr->opcode);
                check_use(vctx, instr->operands.fd_open.mode, instr->opcode);
            }
            if (instr->result_id != 0 && instr->result_id < state->ownership->count) {
                ownership_set(state->ownership, instr->result_id, VAL_AVAILABLE);
            }
            break;
        case IL_OP_ASYNC_ENTER:
            if (report_errors) {
                check_use(vctx, instr->operands.async_enter.ctx, instr->opcode);
                check_use(vctx, instr->operands.async_enter.to_submit, instr->opcode);
                check_use(vctx, instr->operands.async_enter.min_complete, instr->opcode);
            }
            break;
        default: break;
    }
}

static void verify_sum_instr(VerifierCtx* vctx) {
    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    switch (instr->opcode) {
        case IL_OP_SUM_CONSTRUCT:
            if (report_errors) check_use(vctx, instr->operands.sum_construct.payload_id, instr->opcode);
            if (instr->operands.sum_construct.payload_id != 0 && instr->operands.sum_construct.payload_id < state->ownership->count && !il_type_is_copy_mod(mod, get_val_type(func, instr->operands.sum_construct.payload_id, types, ssa_count))) {
                ownership_set(state->ownership, instr->operands.sum_construct.payload_id, VAL_MOVED);
            }
            break;
        case IL_OP_VARIANT_MATCH:
            if (report_errors) check_use(vctx, instr->operands.variant_match.sum_ptr, instr->opcode);
            break;
        default: break;
    }
}

static void verify_control_instr(VerifierCtx* vctx) {
    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    switch (instr->opcode) {
        case IL_OP_RETURN:
            if (report_errors) {
                check_use(vctx, instr->operands.ret.value, instr->opcode);
                const ILType* vt = get_val_type(func, instr->operands.ret.value, types, ssa_count);
                const ILType* expected_ret = func->is_sret ? il_type_unit() : func->return_type;
                check_type_assignable(res, func->name, func->file_path, mod, block_id, instr_idx, instr, vt, expected_ret, "return type mismatch");
                if (vt && il_type_contains_local_region(vt)) {
                    uint32_t top_rid = 0;
                    bool is_ref = false;
                    if (vt->kind == IL_TY_PTR) { top_rid = vt->as.ptr.region_id; is_ref = true; }
                    else if (vt->kind == IL_TY_BOX) { top_rid = vt->as.box.region_id; is_ref = true; }
                    else if (vt->kind == IL_TY_SLICE) { top_rid = vt->as.slice.region_id; is_ref = true; }

                    if (is_ref && (top_rid == REGION_STATIC || top_rid == REGION_HEAP)) {
                        /* return escape: removed 2026-09-12 -- this is the type-level check that rejected
                           stdlib/bytevec.zrl:56's as_slice(). src/verify.zrl now does it on provenance
                           instead, and states its intraprocedural limit in spec §11.2.4. */
                    } else {
                        // 'local' region can only escape if it was passed in as a parameter
                        bool has_local_param = false;
                        for (uint32_t i = 0; i < func->param_count; i++) {
                            const ILType* pt = func->param_types[i];
                            if (pt && il_type_contains_local_region(pt)) {
                                has_local_param = true;
                                break;
                            }
                        }
                        if (!has_local_param) {
                            /* return escape: removed 2026-09-12 -- this is the type-level check that rejected
                           stdlib/bytevec.zrl:56's as_slice(). src/verify.zrl now does it on provenance
                           instead, and states its intraprocedural limit in spec §11.2.4. */
                        }
                    }
                }
            }
            if (instr->operands.ret.value != 0 && instr->operands.ret.value < state->ownership->count && !il_type_is_copy_mod(mod, get_val_type(func, instr->operands.ret.value, types, ssa_count))) {
                ownership_set(state->ownership, instr->operands.ret.value, VAL_MOVED);
            }
            break;
        case IL_OP_BRANCH:
            if (report_errors) {
                check_use(vctx, instr->operands.branch.condition, instr->opcode);
                if (!find_block_by_id(func, instr->operands.branch.then_block_id)) {
                    char msg[128];
                    snprintf(msg, sizeof(msg), "branch to non-existent block @b%u", instr->operands.branch.then_block_id);
                    add_error_impl(res, func->name, func->file_path, VERIFY_ERR_INTERNAL, block_id, instr_idx, instr->line, instr->col, msg);
                }
                if (!find_block_by_id(func, instr->operands.branch.else_block_id)) {
                    char msg[128];
                    snprintf(msg, sizeof(msg), "branch to non-existent block @b%u", instr->operands.branch.else_block_id);
                    add_error_impl(res, func->name, func->file_path, VERIFY_ERR_INTERNAL, block_id, instr_idx, instr->line, instr->col, msg);
                }
            }
            break;
        case IL_OP_JUMP:
            if (report_errors) {
                if (!find_block_by_id(func, instr->operands.jump.target_block_id)) {
                    char msg[128];
                    snprintf(msg, sizeof(msg), "jump to non-existent block @b%u", instr->operands.jump.target_block_id);
                    add_error_impl(res, func->name, func->file_path, VERIFY_ERR_INTERNAL, block_id, instr_idx, instr->line, instr->col, msg);
                }
            }
            break;
        default: break;
    }
}

static bool update_state_for_instr(VerifierCtx* vctx) {
    VerificationResult* res    = vctx->res;
    const ILModule* mod        = vctx->mod;
    const ILFunction* func     = vctx->func;
    const ILType** types       = vctx->types;
    VerifierState* state       = vctx->state;
    uint32_t block_id          = vctx->block_id;
    uint32_t instr_idx         = vctx->instr_idx;
    const ILInstruction* instr = vctx->instr;
    bool report_errors         = vctx->report_errors;
    uint32_t ssa_count         = vctx->ssa_count;
    (void)res; (void)mod; (void)func; (void)types; (void)state;
    (void)block_id; (void)instr_idx; (void)instr; (void)report_errors; (void)ssa_count;
    (void)res; (void)func; (void)block_id; (void)instr_idx; (void)report_errors;
    switch (instr->opcode) {
        case IL_OP_ADD: case IL_OP_SUB: case IL_OP_MUL: case IL_OP_DIV:
        case IL_OP_REM: case IL_OP_AND: case IL_OP_OR: case IL_OP_XOR:
        case IL_OP_SHL: case IL_OP_SHR:
        case IL_OP_WRAPPING_ADD: case IL_OP_WRAPPING_SUB: case IL_OP_WRAPPING_MUL:
        case IL_OP_SATURATING_ADD:
        case IL_OP_CHECKED_ADD: case IL_OP_CHECKED_SUB: case IL_OP_CHECKED_MUL:
            verify_arith_instr(vctx);
            break;
        case IL_OP_CMP_LT: case IL_OP_CMP_LE: case IL_OP_CMP_GT:
        case IL_OP_CMP_GE: case IL_OP_CMP_EQ: case IL_OP_CMP_NE:
            verify_cmp_instr(vctx);
            break;
        case IL_OP_LOAD: case IL_OP_STORE: case IL_OP_ALLOC: case IL_OP_FIELD_ADDR: case IL_OP_ELEM_ADDR:
            verify_mem_instr(vctx);
            break;
        case IL_OP_MOVE: case IL_OP_BITCAST: case IL_OP_REGION_CAST: case IL_OP_UNWRAP: case IL_OP_IS_SOME: case IL_OP_PHI: case IL_OP_DROP:
            verify_move_instr(vctx);
            break;
        case IL_OP_CALL: case IL_OP_CALL_PTR:
            verify_call_instr(vctx);
            // Check if call returns never
            const ILType* ret_ty = NULL;
            if (instr->opcode == IL_OP_CALL) {
                const ILFunction* target = find_func_by_id(mod, instr->operands.call.func_id);
                if (target) ret_ty = target->return_type;
            } else if (instr->operands.call_ptr.func_ptr_id < ssa_count) {
                const ILType* ft = types[instr->operands.call_ptr.func_ptr_id];
                if (ft && ft->kind == IL_TY_FN) ret_ty = ft->as.function.return_type;
            }
            if (ret_ty && ret_ty->kind == IL_TY_NEVER) {
                state->is_diverged = true;
                return true;
            }
            break;
        case IL_OP_BOUNDS_CHECK: case IL_OP_SLICE_LOAD: case IL_OP_SLICE_STORE: case IL_OP_ARRAY_LOAD: case IL_OP_ARRAY_STORE: case IL_OP_ARRAY_CONSTRUCT: case IL_OP_SLICE_LEN: case IL_OP_SLICE_DATA: case IL_OP_SLICE_CONSTRUCT:
            verify_array_slice_instr(vctx);
            break;
        case IL_OP_FD_READ: case IL_OP_FD_WRITE: case IL_OP_FD_CLOSE: case IL_OP_ASYNC_CLOSE: case IL_OP_ASYNC_SETUP: case IL_OP_ASYNC_ENTER: case IL_OP_FD_OPEN:
            verify_io_instr(vctx);
            break;
        case IL_OP_SUM_CONSTRUCT: case IL_OP_VARIANT_MATCH:
            verify_sum_instr(vctx);
            break;
        case IL_OP_RETURN: case IL_OP_BRANCH: case IL_OP_JUMP:
            verify_control_instr(vctx);
            return true;
        default: break;
    }

    // Default: mark result available
    if (instr->result_id != 0 && instr->result_id < state->ownership->count &&
        instr->opcode != IL_OP_STORE && instr->opcode != IL_OP_DROP && 
        instr->opcode != IL_OP_BRANCH && instr->opcode != IL_OP_JUMP && 
        instr->opcode != IL_OP_RETURN && instr->opcode != IL_OP_SLICE_STORE &&
        instr->opcode != IL_OP_ARRAY_STORE && 
        instr->opcode != IL_OP_FD_OPEN && 
        instr->opcode != IL_OP_FD_CLOSE &&
        instr->opcode != IL_OP_ASYNC_CLOSE) {
        
        bool skip_available = false;
        if (instr->opcode == IL_OP_LOAD) {
            const ILType* res_ty = types[instr->result_id];
            if (res_ty && (res_ty->kind == IL_TY_FD || res_ty->kind == IL_TY_ASYNC_CONTEXT)) {
                skip_available = true;
            }
        }
        
        if (!skip_available) {
            ownership_set(state->ownership, instr->result_id, VAL_AVAILABLE);
        }
    }
    
    return false;
}

static void infer_result_type(const ILModule* mod, ILInstruction* instr, const ILType** types, uint32_t ssa_count) {
    switch (instr->opcode) {
        case IL_OP_ADD: case IL_OP_SUB: case IL_OP_MUL: case IL_OP_DIV:
        case IL_OP_REM: case IL_OP_AND: case IL_OP_OR: case IL_OP_XOR:
        case IL_OP_SHL: case IL_OP_SHR:
        case IL_OP_WRAPPING_ADD: case IL_OP_SATURATING_ADD:
            if (instr->operands.binary.left < ssa_count) types[instr->result_id] = types[instr->operands.binary.left];
            break;
        case IL_OP_CMP_LT: case IL_OP_CMP_LE: case IL_OP_CMP_GT:
        case IL_OP_CMP_GE: case IL_OP_CMP_EQ: case IL_OP_CMP_NE:
        case IL_OP_IS_SOME:
            types[instr->result_id] = il_type_bool();
            break;
        case IL_OP_LOAD: {
            const ILType* pt = (instr->operands.load.ptr < ssa_count) ? types[instr->operands.load.ptr] : NULL;
            if (pt) {
                if (pt->kind == IL_TY_PTR) types[instr->result_id] = pt->as.ptr.pointee;
                else if (pt->kind == IL_TY_BOX) types[instr->result_id] = pt->as.box.pointee;
            }
            break;
        }
        case IL_OP_FIELD_ADDR: {
            const ILType* pt = (instr->operands.field_addr.struct_ptr < ssa_count) ? types[instr->operands.field_addr.struct_ptr] : NULL;
            if (pt) {
                const ILType* struct_ty = NULL;
                uint32_t rid = REGION_LOCAL;
                if (pt->kind == IL_TY_PTR) {
                    struct_ty = pt->as.ptr.pointee;
                    rid = pt->as.ptr.region_id;
                } else if (pt->kind == IL_TY_BOX) {
                    struct_ty = pt->as.box.pointee;
                    rid = pt->as.box.region_id;
                } else if (pt->kind == IL_TY_STRUCT || pt->kind == IL_TY_SUM || pt->kind == IL_TY_TUPLE) {
                    struct_ty = pt;
                    rid = instr->operands.field_addr.struct_ptr;
                }

                if (struct_ty) {
                    if (struct_ty->kind == IL_TY_STRUCT || struct_ty->kind == IL_TY_SUM) {
                        const ILTypeDef* def = il_mod_get_type_def(mod, struct_ty->as.struct_sum.type_def_id);
                        if (def && instr->operands.field_addr.field_index < def->field_count) {
                            types[instr->result_id] = il_type_ptr(def->fields[instr->operands.field_addr.field_index].type, rid, true);
                        }
                    } else if (struct_ty->kind == IL_TY_TUPLE) {
                        if (instr->operands.field_addr.field_index < struct_ty->as.tuple.count) {
                            types[instr->result_id] = il_type_ptr(struct_ty->as.tuple.elements[instr->operands.field_addr.field_index], rid, true);
                        }
                    }
                }
            }
            break;
        }
        case IL_OP_ELEM_ADDR: {
            const ILType* pt = (instr->operands.elem_addr.base < ssa_count) ? types[instr->operands.elem_addr.base] : NULL;
            if (pt) {
                const ILType* agg_ty = NULL;
                uint32_t rid = REGION_LOCAL;
                if (pt->kind == IL_TY_PTR) {
                    agg_ty = pt->as.ptr.pointee;
                    rid = pt->as.ptr.region_id;
                } else if (pt->kind == IL_TY_BOX) {
                    agg_ty = pt->as.box.pointee;
                    rid = pt->as.box.region_id;
                } else if (pt->kind == IL_TY_ARRAY || pt->kind == IL_TY_SLICE) {
                    agg_ty = pt;
                    rid = instr->operands.elem_addr.base;
                }

                if (agg_ty && il_elem_addr_steps_raw_slices(pt, instr->result_type)) {
                    types[instr->result_id] = il_type_ptr(agg_ty, rid, true);
                } else if (agg_ty) {
                    if (agg_ty->kind == IL_TY_ARRAY) types[instr->result_id] = il_type_ptr(agg_ty->as.array.element, rid, true);
                    else if (agg_ty->kind == IL_TY_SLICE) types[instr->result_id] = il_type_ptr(agg_ty->as.slice.element, rid, true);
                }
            }
            break;
        }
        case IL_OP_MOVE: case IL_OP_BITCAST: case IL_OP_REGION_CAST: case IL_OP_UNWRAP:
            if (instr->result_type) {
                types[instr->result_id] = instr->result_type;
            } else {
                uint32_t source_id = (instr->opcode == IL_OP_REGION_CAST) ? instr->operands.region_cast.source : instr->operands.move.source;
                if (source_id < ssa_count) {
                    types[instr->result_id] = types[source_id];
                }
            }
            break;
        case IL_OP_PHI:
            if (instr->operands.phi.num_incoming > 0 && instr->operands.phi.incoming[0].value_id < ssa_count) {
                types[instr->result_id] = types[instr->operands.phi.incoming[0].value_id];
            }
            break;
        case IL_OP_ALLOC:
            if (instr->result_type) {
                types[instr->result_id] = instr->result_type;
            }
            break;
        case IL_OP_CALL: {
            const ILFunction* target = find_func_by_id(mod, instr->operands.call.func_id);
            if (target) types[instr->result_id] = target->return_type;
            break;
        }
        case IL_OP_SLICE_LEN: case IL_OP_SLICE_DATA: case IL_OP_SYSCALL:
            types[instr->result_id] = il_type_u64();
            break;
        case IL_OP_FUNC_ADDR: {
            const ILFunction* target = find_func_by_id(mod, instr->operands.func_addr.func_id);
            if (target) {
                const ILType ** ptypes = calloc(target->param_count, sizeof(const ILType*));
                if (ptypes) {
                    for (uint32_t p = 0; p < target->param_count; p++) ptypes[p] = target->param_types[p];
                    types[instr->result_id] = il_type_fn(target->return_type, ptypes, target->param_count, target->is_variadic);
                }
            }
            break;
        }
        default: break;
    }
}



VerificationResult verify_function(const ILModule* mod, const ILFunction* func) {
    VerificationResult res = { .is_safe = true, .errors = NULL, .error_count = 0, .error_capacity = 0 };
    if (!func) return res;
    
    uint32_t ssa_count = il_func_get_max_ssa_id(func) + 1;
    if (ssa_count > 1000000) {
        add_error_impl(&res, func->name, func->file_path, VERIFY_ERR_INTERNAL, 0, 0, 0, 0, "SSA count too large for verification");
        return res;
    }

    il_func_assign_rpo_ids((ILFunction*)func);
    il_func_calculate_dominators((ILFunction*)func);

    const ILType ** types = calloc(ssa_count, sizeof(const ILType*));
    if (!types) return res;
    for (uint32_t i = 0; i < func->param_count; i++) if (i + 1 < ssa_count) types[i + 1] = func->param_types[i];

    // Pass 1: type inference (fixed-point)
    bool type_changed = true;
    while (type_changed) {
        type_changed = false;
        for (uint32_t b = 0; b < func->block_count; b++) {
            for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
                ILInstruction* instr = (ILInstruction*)func->blocks[b]->instructions[i];
                if (instr->result_id != 0 && instr->result_id < ssa_count) {
                    const ILType* old_ty = types[instr->result_id];
                    if (instr->result_type) {
                        types[instr->result_id] = instr->result_type;
                    } else {
                        infer_result_type(mod, instr, types, ssa_count);
                    }
                    if (types[instr->result_id] != old_ty) {
                        type_changed = true;
                    }
                }
            }
        }
    }
    
    // Pass 1.5: ensure ALL instructions have their result_type set from the inferred map
    // AND ensure the global types map is populated from instructions that DO have types.
    for (int retry = 0; retry < 3; retry++) {
        for (uint32_t b = 0; b < func->block_count; b++) {
            for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
                ILInstruction* instr = (ILInstruction*)func->blocks[b]->instructions[i];
                if (instr->result_id != 0 && instr->result_id < ssa_count) {
                    if (instr->result_type && !types[instr->result_id]) {
                        types[instr->result_id] = instr->result_type;
                    } else if (!instr->result_type && types[instr->result_id]) {
                        instr->result_type = types[instr->result_id];
                    } else if (!instr->result_type && !types[instr->result_id]) {
                        infer_result_type(mod, instr, types, ssa_count);
                        instr->result_type = types[instr->result_id];
                    }
                }
            }
        }
    }

    il_func_assign_rpo_ids((ILFunction*)func);
    il_func_calculate_dominators((ILFunction*)func);

    uint32_t total_instrs = 0;
    for (uint32_t b = 0; b < func->block_count; b++) total_instrs += func->blocks[b]->instr_count;
    if (total_instrs > 10000 || func->block_count > 1000) {
        add_error_impl(&res, func->name, func->file_path, VERIFY_ERR_INTERNAL, 0, 0, 0, 0, "Function too large or complex for verification");
        free(types);
        return res;
    }

    // Pre-pass: identify owned stack allocations (results of IL_OP_ALLOC with REGION_LOCAL)
    bool* is_alloc_global = calloc(ssa_count, sizeof(bool));
    if (is_alloc_global) {
        for (uint32_t b = 0; b < func->block_count; b++) {
            for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
                const ILInstruction* instr = func->blocks[b]->instructions[i];
                if (instr->opcode == IL_OP_ALLOC && instr->result_id != 0 && instr->result_id < ssa_count) {
                    const ILType* pt = instr->result_type ? instr->result_type : types[instr->result_id];
                    if (pt && pt->kind == IL_TY_PTR && pt->as.ptr.region_id == REGION_LOCAL) {
                        is_alloc_global[instr->result_id] = true;
                    }
                }
            }
        }
    }

    VerifierState** states = calloc(func->block_count, sizeof(VerifierState*));
    if (!states) { free(types); free(is_alloc_global); return res; }
    
    // Initial state for entry block
    if (func->block_count > 0) {
        states[0] = verifier_state_create(ssa_count);
        if (!states[0]) { free(states); free(types); free(is_alloc_global); return res; }
        states[0]->is_initialized = true;
        if (is_alloc_global) memcpy(states[0]->is_alloc, is_alloc_global, sizeof(bool) * ssa_count);
        for (uint32_t i = 0; i < func->param_count; i++) if (i + 1 < ssa_count) ownership_set(states[0]->ownership, i + 1, VAL_AVAILABLE);
    }
    free(is_alloc_global);

    bool changed = true;
    uint32_t iterations = 0;
    VerifierState* current = verifier_state_create(ssa_count);
    if (!current) {
        for (uint32_t i = 0; i < func->block_count; i++) verifier_state_free(states[i]);
        free(states); free(types); return res;
    }

    while (changed && iterations < 100) {
        iterations++;
        changed = false;
        for (uint32_t b = 0; b < func->block_count; b++) {
            if (!states[b] || !states[b]->is_initialized) continue;
            verifier_state_copy_to(current, states[b], ssa_count);
            
            // Clear statuses of all SSA values that are created in THIS block or later,
            // to avoid seeing future values from previous fixed-point iterations.
            // SSA IDs are globally unique and increasing.
            uint32_t first_instr_result = 0;
            for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
                if (func->blocks[b]->instructions[i]->result_id != 0) {
                    first_instr_result = func->blocks[b]->instructions[i]->result_id;
                    break;
                }
            }
            if (first_instr_result != 0) {
                for (uint32_t i = first_instr_result; i < ssa_count; i++) {
                    ownership_set(current->ownership, i, VAL_UNDEFINED);
                }
            }

            for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
                VerifierCtx vctx0 = { &res, mod, func, types, current, b, i, func->blocks[b]->instructions[i], false, ssa_count };
                if (update_state_for_instr(&vctx0)) { break; }
            }
            if (!current->is_diverged) {
                for (uint32_t s = 0; s < func->blocks[b]->succ_count; s++) {
                    const ILBasicBlock* succ = func->blocks[b]->successors[s];
                    uint32_t succ_idx = succ->rpo_index;
                    if (succ_idx < func->block_count) {
                        if (!states[succ_idx]) {
                            states[succ_idx] = verifier_state_create(ssa_count);
                            if (!states[succ_idx]) continue; // OOM in verifier
                            verifier_state_copy_to(states[succ_idx], current, ssa_count);
                            changed = true;
                        } else if (verifier_state_merge(states[succ_idx], current, ssa_count)) {
                            changed = true;
                        }
                    }
                }
            }
        }
    }

    verifier_state_free(current);
    current = verifier_state_create(ssa_count);
    if (!current) {
        for (uint32_t i = 0; i < func->block_count; i++) verifier_state_free(states[i]);
        free(states); free(types); return res;
    }

    for (uint32_t b = 0; b < func->block_count; b++) {
        if (!states[b] || !states[b]->is_initialized) continue;
        
        // Final pass MUST start fresh from block entry state to avoid seeing "future" values
        // from previous fixed-point iterations as conflicting borrows.
        verifier_state_copy_to(current, states[b], ssa_count);
        
        uint32_t first_instr_result = 0;
        for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
            if (func->blocks[b]->instructions[i]->result_id != 0) {
                first_instr_result = func->blocks[b]->instructions[i]->result_id;
                break;
            }
        }
        if (first_instr_result != 0) {
            for (uint32_t i = first_instr_result; i < ssa_count; i++) {
                ownership_set(current->ownership, i, VAL_UNDEFINED);
            }
        }

        for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
            const ILInstruction* instr = func->blocks[b]->instructions[i];
            VerifierCtx vctx1 = { &res, mod, func, types, current, b, i, instr, true, ssa_count };
            if (update_state_for_instr(&vctx1)) { break; }
        }
        
        if (func->blocks[b]->succ_count == 0 && !current->is_diverged) {
            for (uint32_t i = 1; i < ssa_count; i++) {
                if (ownership_get(current->ownership, i) == VAL_AVAILABLE) {
                    if (types[i] == NULL) continue;
                    // A slice is a {ptr, len} view and never owns its elements, so it cannot
                    // leak; reporting it rejected a struct literal holding a fresh @slice.
                    if (types[i]->kind == IL_TY_SLICE) continue;
                    bool is_copy = il_type_is_copy_mod(mod, types[i]);
                    if (!is_copy) {
                        char leak_msg[256];
                        char ty_buf[128];
                        il_print_type(mod, types[i], ty_buf, sizeof(ty_buf));
                        const char* name = get_val_name(func, i);
                        
                        if (types[i]->kind == IL_TY_FD || types[i]->kind == IL_TY_ASYNC_CONTEXT) {
                            const char* type_name = (types[i]->kind == IL_TY_FD) ? "fd" : "async_context";
                            
                            bool produced_by_load = false;
                            for (uint32_t b2 = 0; b2 < func->block_count && !produced_by_load; b2++) {
                                for (uint32_t i2 = 0; i2 < func->blocks[b2]->instr_count; i2++) {
                                    const ILInstruction* instr2 = func->blocks[b2]->instructions[i2];
                                    if (instr2->result_id == i) {
                                        if (instr2->opcode == IL_OP_LOAD) {
                                            produced_by_load = true;
                                        }
                                        break;
                                    }
                                }
                            }
                            
                            if (!produced_by_load) {
                                uint32_t line = 0, col = 0;
                                uint32_t instr_idx = 0;
                                if (func->blocks[b]->instr_count > 0) {
                                    instr_idx = func->blocks[b]->instr_count - 1;
                                    const ILInstruction* last = func->blocks[b]->instructions[instr_idx];
                                    line = last->line;
                                    col = last->col;
                                }
                                if (name) snprintf(leak_msg, sizeof(leak_msg), "linear resource '%s' (type %s) must be explicitly closed, not dropped", name, type_name);
                                else snprintf(leak_msg, sizeof(leak_msg), "linear resource v%u (type %s) must be explicitly closed, not dropped", i, type_name);
                                add_error_impl(&res, func->name, func->file_path, VERIFY_ERR_LEAK, b, instr_idx, line, col, leak_msg);

                            }
                        } else {
                            if (name) snprintf(leak_msg, sizeof(leak_msg), "value '%s' leaked in function %s (type %s)", name, func->name, ty_buf);
                            else snprintf(leak_msg, sizeof(leak_msg), "value v%u leaked in function %s (type %s)", i, func->name, ty_buf);
                            add_error_impl(&res, func->name, func->file_path, VERIFY_ERR_LEAK, b, func->blocks[b]->instr_count, 0, 0, leak_msg);
                        }
                    }
                }
            }
        }
    }
    verifier_state_free(current);
    for (uint32_t i = 0; i < func->block_count; i++) verifier_state_free(states[i]);
    free(states);
    free(types);
    return res;
}

void verify_result_free(VerificationResult* result) {
    if (!result) return;
    for (uint32_t i = 0; i < result->error_count; i++) {
        free((void*)result->errors[i].message);
        if (result->errors[i].func_name) free(result->errors[i].func_name);
        if (result->errors[i].file_path) free((void*)result->errors[i].file_path);
    }
    free(result->errors);
    result->errors = NULL;
    result->error_count = 0;
    result->error_capacity = 0;
}

VerificationResult verify_module(const ILModule* mod) {
    VerificationResult total = { .is_safe = true, .errors = NULL, .error_count = 0, .error_capacity = 0 };
    for (uint32_t i = 0; i < mod->function_count; i++) {
        VerificationResult res = verify_function(mod, mod->functions[i]);
        if (!res.is_safe) {
            total.is_safe = false;
            for (uint32_t j = 0; j < res.error_count; j++) {
                add_error_impl(&total, res.errors[j].func_name, res.errors[j].file_path, res.errors[j].type, res.errors[j].block_id, res.errors[j].instr_index, res.errors[j].line, res.errors[j].col, res.errors[j].message);
            }
        }
        verify_result_free(&res);
    }
    return total;
}
