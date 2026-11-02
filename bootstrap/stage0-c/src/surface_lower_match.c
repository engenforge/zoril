#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "surface_lower_internal.h"
#include "il_instr.h"
#include "il_pass.h"
#include "il_print.h"
#include "il_ownership.h"

ILValue promote_to_lvalue_with_type(LowerContext* ctx, ILValue val, const ILType* type) {
    if (!val.type) return val;
    if (val.type->kind == IL_TY_PTR || val.type->kind == IL_TY_BOX) return val;
    
    const ILType* ptr_ty = il_type_ptr(type, REGION_LOCAL, true);
    ILInstruction* alloc = il_build_alloc(REGION_LOCAL, type, ptr_ty, (ILValue){0});
    ILValue ptr = emit(ctx, alloc);
    ILInstruction* store = il_build_store(ptr, val);
    emit_void(ctx, store);
    return ptr;
}

ILValue promote_to_lvalue(LowerContext* ctx, ILValue val) {
    return promote_to_lvalue_with_type(ctx, val, val.type);
}
typedef struct {
    uint32_t count;
    char**           names;
    const ILType**   types;
    ILPhiIncoming**  payloads;
    uint32_t*        payload_counts;
    bool*            is_lvalue;
} MatchArmState;

static void match_arm_state_free(MatchArmState* s) {
    if (s->payloads) {
        for (uint32_t b = 0; b < s->count; b++)
            if (s->payloads[b]) free(s->payloads[b]);
        free(s->payloads);
    }
    if (s->names)         free(s->names);
    if (s->types)         free(s->types);
    if (s->payload_counts) free(s->payload_counts);
    if (s->is_lvalue)     free(s->is_lvalue);
    *s = (MatchArmState){0};
}

/* Free all match-lowering heap allocations and return the zero ILValue sentinel.
 * Used on every error exit path inside lower_match_expr to avoid repeating four
 * free() calls. */
static ILValue match_lower_fail(MatchArmState* arms,
                                ILPhiIncoming* incoming,
                                bool* merged_state,
                                bool* orig_state) {
    match_arm_state_free(arms);
    free(incoming);
    free(merged_state);
    free(orig_state);
    return (ILValue){0};
}

static void check_match_exhaustiveness(LowerContext* ctx, const MatchExpr* expr,
                                       const ILType* subject_ty, const ILTypeDef* def) {
    bool is_exhaustive = false;
    for (uint32_t i = 0; i < expr->arm_count; i++) {
        Pattern* p = expr->arms[i]->pattern;
        while (p) {
            if (p->kind == PATTERN_WILD) { is_exhaustive = true; break; }
            p = p->next;
        }
        if (is_exhaustive) break;
    }

    if (!is_exhaustive) {
        if (subject_ty->kind == IL_TY_BOOL) {
            bool matched_true = false;
            bool matched_false = false;
            for (uint32_t i = 0; i < expr->arm_count; i++) {
                Pattern* p = expr->arms[i]->pattern;
                while (p) {
                    if (p->kind == PATTERN_BOOL) {
                        if (p->as.bool_val) matched_true = true;
                        else matched_false = true;
                    }
                    p = p->next;
                }
            }
            if (matched_true && matched_false) is_exhaustive = true;
        } else if (subject_ty->kind == IL_TY_SUM) {
            if (def) {
                bool* matched_variants = calloc(def->field_count, sizeof(bool));
                for (uint32_t i = 0; i < expr->arm_count; i++) {
                    Pattern* p = expr->arms[i]->pattern;
                    while (p) {
                        if (p->kind == PATTERN_VARIANT) {
                            const char* vname = p->as.variant.name;
                            const char* dot = strrchr(vname, '.');
                            if (dot) vname = dot + 1;
                            int v_idx = find_field_index(def, vname);
                            if (v_idx >= 0) matched_variants[v_idx] = true;
                        }
                        p = p->next;
                    }
                }
                is_exhaustive = true;
                for (uint32_t k = 0; k < def->field_count; k++)
                    if (!matched_variants[k]) { is_exhaustive = false; break; }
                free(matched_variants);
            }
        }
    }
    if (!is_exhaustive)
        emit_diag_at(ctx, DIAG_ERROR, expr->target, "Match is not exhaustive");
}

static void detect_is_some_pattern(const MatchExpr* expr, const ILType* subject_ty,
                                   const ILTypeDef* def, int* out_arm, int* out_vidx) {
    *out_arm = -1; *out_vidx = -1;
    if (subject_ty->kind != IL_TY_SUM || !def || def->field_count != 2 ||
        expr->arm_count != 2) return;
    int some_arm = -1, none_arm = -1, some_vidx = -1;
    bool ok = true;
    for (int arm_i = 0; arm_i < 2 && ok; arm_i++) {
        Pattern* pp = expr->arms[arm_i]->pattern;
        if (!pp || pp->next != NULL) { ok = false; break; }
        if (pp->kind == PATTERN_WILD) {
            if (none_arm >= 0) { ok = false; break; }
            none_arm = arm_i;
        } else if (pp->kind == PATTERN_VARIANT) {
            const char* vn = pp->as.variant.name;
            const char* d = strrchr(vn, '.');
            if (d) vn = d + 1;
            int vi = find_field_index(def, vn);
            if (vi < 0) { ok = false; break; }
            uint32_t vtag = def->fields[vi].has_tag
                            ? (uint32_t)def->fields[vi].tag
                            : (uint32_t)vi;
            if (vtag == 1) {
                if (some_arm >= 0) { ok = false; break; }
                some_arm = arm_i; some_vidx = vi;
            } else if (vtag == 0) {
                if (none_arm >= 0) { ok = false; break; }
                none_arm = arm_i;
            } else { ok = false; }
        } else { ok = false; }
    }
    if (ok && some_arm >= 0 && none_arm >= 0) {
        *out_arm  = some_arm;
        *out_vidx = some_vidx;
    }
}

ILValue lower_match_expr(LowerContext* ctx, const MatchExpr* expr, const ILType* expected_type, ILValue dest_ptr) {
    (void)dest_ptr;
    ILValue target = lower_expression_internal(ctx, expr->target, NULL, false, (ILValue){0}, false, false);
    if (!target.type) return (ILValue){0};
    
    il_type_fixup(ctx->module, target.type);
    
    const ILType* subject_ty = (target.type && target.type->kind == IL_TY_PTR) ? target.type->as.ptr.pointee : (target.type && target.type->kind == IL_TY_BOX ? target.type->as.box.pointee : target.type);
    if (!subject_ty) return (ILValue){0};
    
    // If the target is already a pointer (reference param with REGION_LOCAL, raw ptr, or Box),
    // treat the match as a borrow — use FIELD_ADDR to extract the payload by reference rather
    // than UNWRAP which would move out of the pointed-to memory.
    bool matched_on_borrow = target.type && (target.type->kind == IL_TY_PTR || target.type->kind == IL_TY_BOX);
    if (!matched_on_borrow) {
        target = promote_to_lvalue(ctx, target);
    }

    const ILTypeDef* def = NULL;
    if (subject_ty->kind == IL_TY_SUM || subject_ty->kind == IL_TY_STRUCT) {
        if (subject_ty->as.struct_sum.type_def_id != 0) {
            def = il_mod_get_type_def(ctx->module, subject_ty->as.struct_sum.type_def_id);
        }
    }
    if (!def && (subject_ty->kind == IL_TY_SUM || subject_ty->kind == IL_TY_STRUCT)) {
        def = find_type_def(ctx, subject_ty->as.struct_sum.name);
    }

    check_match_exhaustiveness(ctx, expr, subject_ty, def);

    int is_some_opt_arm = -1, is_some_opt_vidx = -1;
    detect_is_some_pattern(expr, subject_ty, def, &is_some_opt_arm, &is_some_opt_vidx);

    // --- Lowering ---
    // Create join block and temporary for result
    ILBasicBlock* join_blk = create_block(ctx);
    
    ILPhiIncoming* incoming = calloc(expr->arm_count + 1, sizeof(ILPhiIncoming));
    uint32_t incoming_count = 0;
    const ILType* res_type = expected_type ? expected_type : NULL;

    uint32_t orig_cap;
    bool* orig_state = save_moved_state(ctx, &orig_cap);
    bool* merged_state = calloc(orig_cap, sizeof(bool));
    if (merged_state && orig_state && orig_cap > 0) memcpy(merged_state, orig_state, orig_cap * sizeof(bool));
    uint32_t merged_cap = orig_cap;

    if (!res_type) {
        for (uint32_t i = 0; i < expr->arm_count; i++) {
            const ILType* g = guess_type(ctx, expr->arms[i]->body);
            if (g && g->kind != IL_TY_NEVER) {
                res_type = g;
                break;
            }
        }
    }
    
    for (uint32_t i = 0; i < expr->arm_count; i++) {
        const MatchArm* arm = expr->arms[i];
        ILBasicBlock* arm_blk = create_block(ctx);
        ILBasicBlock* next_arm_blk = create_block(ctx);
        bool arm_has_wildcard = false;

        MatchArmState arms = {0};

        Pattern* p = arm->pattern;
        bool first_variant = true;
        while (p) {            // When IS_SOME guarded the some-like arm (at index is_some_opt_arm),
            // any arm processed AFTER it is already in the guaranteed else branch —
            // skip the redundant tag load+compare, but only when the arm has no
            // payload bindings (a bound payload still needs UNWRAP/FIELD_ADDR).
            if (is_some_opt_arm >= 0 && (int)i > is_some_opt_arm &&
                p->kind == PATTERN_VARIANT && p->next == NULL &&
                p->as.variant.bind_count == 0) {
                add_jump(ctx, arm_blk);
                arm_has_wildcard = true;
                break;
            }
            if (p->kind == PATTERN_WILD) {
                add_jump(ctx, arm_blk);
                arm_has_wildcard = true;
                break;
            } else if (p->kind == PATTERN_VARIANT) {
                const char* vname = p->as.variant.name;
                const char* dot = strrchr(vname, '.');

                // Try to find if this is a constant first
                if (subject_ty->kind != IL_TY_SUM || !dot) {
                    char mangled_name[512];
                    if (dot) {
                        size_t prefix_len = (size_t)(dot - vname);
                        snprintf(mangled_name, sizeof(mangled_name), "%.*s_%s", (int)prefix_len, vname, dot + 1);
                    } else {
                        strncpy(mangled_name, vname, sizeof(mangled_name));
                        mangled_name[sizeof(mangled_name)-1] = '\0';
                    }
                    const ILGlobal* g = find_global(ctx->module, mangled_name);
                    if (g && g->is_const && g->init_data && g->data_len > 0) {
                        uint64_t val = 0;
                        memcpy(&val, g->init_data, g->data_len > 8 ? 8 : g->data_len);
                        
                        // If it's a constant pattern, the subject_ty might be the mangled monomorphized type.
                        // We must use that for the constant construction.
                        ILValue pat_val = emit(ctx, il_build_const(val, subject_ty));

                        ILValue subject_val = target;
                        if (target.type && (target.type->kind == IL_TY_PTR || target.type->kind == IL_TY_BOX)) {
                            subject_val = emit(ctx, il_build_load(target));
                        }
                        ILValue cmp = emit(ctx, il_build_cmp_eq(subject_val, pat_val, il_type_bool()));

                        ILBasicBlock* next_p_blk = create_block(ctx);
                        if (ctx->current_block) {
                            ILInstruction* br = il_build_branch(cmp, arm_blk->id, next_p_blk->id);
                            if (!br) {
                                if (ctx->report && ctx->report->has_errors) {
return match_lower_fail(&arms, incoming, merged_state, orig_state);
                                }
                                emit_diag_at(ctx, DIAG_ERROR, expr->target, "Failed to build branch for const pattern in match");
return match_lower_fail(&arms, incoming, merged_state, orig_state);
                            }
                            il_block_add_instr(ctx->current_block, br);
                            il_block_add_successor(ctx->current_block, arm_blk);
                            il_block_add_successor(ctx->current_block, next_p_blk);
                        }
                        ctx->current_block = next_p_blk;
                        p = p->next; continue;
                    }
                }

                if (subject_ty->kind != IL_TY_SUM) {
                    emit_diag_at(ctx, DIAG_ERROR, expr->target, "Enum pattern used on non-enum type");
                    p = p->next; continue;
                }
                if (!def) { p = p->next; continue; }

                if (dot) {
                    size_t prefix_len = (size_t)(dot - vname);
                    bool prefix_match = false;
                    if (strncmp(vname, def->name, prefix_len) == 0 && (def->name[prefix_len] == '\0' || def->name[prefix_len] == '_')) {
                        prefix_match = true;
                    }
                    if (!prefix_match) {
                        emit_diag_at(ctx, DIAG_ERROR, expr->target, "Variant prefix '%.*s' does not match type '%s'", (int)prefix_len, vname, def->name);
                    }
                    vname = dot + 1;
                }
                int v_idx = find_field_index(def, vname);
                if (v_idx < 0) {
                    emit_diag_at(ctx, DIAG_ERROR, expr->target, "Unknown variant '%s' for type '%s'", vname, def->name);
                    p = p->next; continue;
                }

                ILBasicBlock* next_p_blk = create_block(ctx);
                ILBasicBlock* extract_blk = create_block(ctx);
                if (ctx->current_block) {
                    bool do_is_some = (is_some_opt_arm >= 0 &&
                                       (int)i == is_some_opt_arm &&
                                       v_idx == is_some_opt_vidx);
                    ILInstruction* match_instr = NULL;
                    if (do_is_some) {
                        ILValue cond = emit(ctx, il_build_is_some(target, il_type_bool()));
                        if (cond.type) {
                            match_instr = il_build_branch(cond, extract_blk->id, next_p_blk->id);
                        }
                    } else {
                        match_instr = il_build_variant_match(target, (uint32_t)v_idx, extract_blk->id, next_p_blk->id);
                    }
                    if (!match_instr) {
                        if (ctx->report && ctx->report->has_errors) {
return match_lower_fail(&arms, incoming, merged_state, orig_state);
                        }
                        emit_diag_at(ctx, DIAG_ERROR, expr->target, "Failed to build variant_match instruction");
return match_lower_fail(&arms, incoming, merged_state, orig_state);
                    }
                    il_block_add_instr(ctx->current_block, match_instr);
                    il_block_add_successor(ctx->current_block, extract_blk);
                    il_block_add_successor(ctx->current_block, next_p_blk);
                }

                ctx->current_block = extract_blk;

                // Initialize or check consistency of variable bindings for this arm.
                if (first_variant) {
                    // First variant in the pattern chain for this arm
                    arms.count = p->as.variant.bind_count;
                    if (arms.count > 0) {
                        arms.names = calloc(arms.count, sizeof(char*));
                        arms.types = calloc(arms.count, sizeof(const ILType*));
                        arms.payloads = calloc(arms.count, sizeof(ILPhiIncoming*));
                        arms.payload_counts = calloc(arms.count, sizeof(uint32_t));
                        arms.is_lvalue = calloc(arms.count, sizeof(bool));
                        for (uint32_t b = 0; b < arms.count; b++) {
                            arms.names[b] = p->as.variant.bind_names[b];
                        }
                    }
                    first_variant = false;
                } else {
                    uint32_t max_b = (p->as.variant.bind_count > arms.count) ? p->as.variant.bind_count : arms.count;
                    for (uint32_t b = 0; b < max_b; b++) {
                        const char* arm_name = (b < arms.count) ? arms.names[b] : NULL;
                        const char* var_name = (b < p->as.variant.bind_count) ? p->as.variant.bind_names[b] : NULL;

                        if (arm_name != NULL && var_name != NULL) {
                            if (strcmp(arm_name, var_name) != 0) {
                                emit_diag_at(ctx, DIAG_ERROR, expr->target, "Variable bindings in multi-pattern match must have the same name in each variant");
                                break;
                            }
                        } else if (arm_name != NULL || var_name != NULL) {
                            emit_diag_at(ctx, DIAG_ERROR, expr->target, "All variants in a multi-pattern match must bind the same variables");
                            break;
                        }
                    }
                    // Update arms.count to the maximum number of bindings seen so far in this arm
                    if (p->as.variant.bind_count > arms.count) {
                        uint32_t old_count = arms.count;
                        arms.count = p->as.variant.bind_count;
                        arms.names = realloc(arms.names, arms.count * sizeof(char*));
                        arms.types = realloc(arms.types, arms.count * sizeof(const ILType*));
                        arms.payloads = realloc(arms.payloads, arms.count * sizeof(ILPhiIncoming*));
                        arms.payload_counts = realloc(arms.payload_counts, arms.count * sizeof(uint32_t));
                        arms.is_lvalue = realloc(arms.is_lvalue, arms.count * sizeof(bool));
                        for (uint32_t b = old_count; b < arms.count; b++) {
                            arms.names[b] = p->as.variant.bind_names[b];
                            arms.types[b] = NULL;
                            arms.payloads[b] = NULL;
                            arms.payload_counts[b] = 0;
                            arms.is_lvalue[b] = false;
                        }
                    }
                }
                if (p->as.variant.bind_count > 0) {
                    const ILType* variant_ty = def->fields[v_idx].type;
                    const ILType* orig_variant_ty = variant_ty;
                    if (def->is_generic && subject_ty->as.struct_sum.type_arg_count > 0) {
                         Substitution* match_substs = NULL;
                         const TypeDef* styp = NULL;
                         for (uint32_t j = 0; j < ctx->surface_mod->type_def_count; j++) {
                             const TypeDef* td = ctx->surface_mod->type_defs[j];
                             const char* sname = (td->kind == TYPE_DEF_STRUCT) ? td->as.struct_decl->name : td->as.enum_decl->name;
                             if (strcmp(sname, def->name) == 0) { styp = td; break; }
                         }
                         if (styp) {
                             uint32_t tpc = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_param_count : styp->as.enum_decl->type_param_count;
                             char** tparams = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_params : styp->as.enum_decl->type_params;
                             for (uint32_t k = 0; k < tpc && k < subject_ty->as.struct_sum.type_arg_count; k++) {
                                 Substitution* n = calloc(1, sizeof(Substitution));
                                 n->name = tparams[k];
                                 n->type = subject_ty->as.struct_sum.type_args[k];
                                 n->next = match_substs;
                                 match_substs = n;
                             }
                             variant_ty = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, variant_ty, match_substs);
                             orig_variant_ty = variant_ty;
                             while (match_substs) { Substitution* n = (Substitution*)match_substs->next; free(match_substs); match_substs = n; }
                         }
                    }

                    ILValue variant_val;
                    if (matched_on_borrow) {
                        variant_ty = il_type_ptr(variant_ty, get_region(target.type), is_mut_borrow(target.type));
                        variant_val = emit(ctx, il_build_field_addr(target, (uint32_t)v_idx, variant_ty));
                    } else {
                        variant_val = emit(ctx, il_build_unwrap(target, variant_ty));
                        if (is_aggregate_type_layout(variant_ty)) {
                            variant_val = promote_to_lvalue(ctx, variant_val);
                        }
                    }

                    // When borrowing, variant_ty is Ptr<InnerType>; use the inner type for tuple checks.
                    const ILType* inner_variant_ty = (matched_on_borrow && variant_ty->kind == IL_TY_PTR)
                        ? variant_ty->as.ptr.pointee
                        : variant_ty;

                    // Resolve the tuple payload typedef (if the payload is a concrete struct type).
                    // Tuple payloads are typically lowered to IL_TY_STRUCT; raw IL_TY_TUPLE also supported.
                    const ILTypeDef* tuple_payload_def = NULL;
                    uint32_t tuple_payload_field_count = 0;
                    if (inner_variant_ty->kind == IL_TY_TUPLE) {
                        tuple_payload_field_count = inner_variant_ty->as.tuple.count;
                    } else if ((inner_variant_ty->kind == IL_TY_STRUCT || inner_variant_ty->kind == IL_TY_SUM)
                               && inner_variant_ty->as.struct_sum.type_def_id != 0) {
                        tuple_payload_def = il_mod_get_type_def(ctx->module, inner_variant_ty->as.struct_sum.type_def_id);
                        if (tuple_payload_def) tuple_payload_field_count = tuple_payload_def->field_count;
                    }

                    for (uint32_t b = 0; b < arms.count && b < p->as.variant.bind_count; b++) {
                        bool current_is_wildcard = (p->as.variant.bind_names[b] == NULL);
                        if (current_is_wildcard) continue;

                        const ILType* field_ty = NULL;
                        ILValue field_val;
                        bool field_is_lv = false;
                        if (arms.count == 1) {
                            field_val = variant_val;
                            field_ty = field_val.type;
                            field_is_lv = matched_on_borrow || is_aggregate_type_layout(orig_variant_ty);
                        } else {
                            const ILType* elem_ty = NULL;
                            if (tuple_payload_field_count != p->as.variant.bind_count) {
                                // field count mismatch
                            } else if (inner_variant_ty->kind == IL_TY_TUPLE && b < inner_variant_ty->as.tuple.count) {
                                elem_ty = inner_variant_ty->as.tuple.elements[b];
                            } else if (tuple_payload_def && b < tuple_payload_def->field_count) {
                                elem_ty = tuple_payload_def->fields[b].type;
                            }

                            if (!elem_ty) {
                                field_ty = il_type_unit();
                                field_val = (ILValue){0};
                                field_is_lv = false;
                            } else if (matched_on_borrow) {
                                const ILType* ptr_elem_ty = il_type_ptr(elem_ty, get_region(variant_val.type), is_mut_borrow(target.type));
                                field_val = emit(ctx, il_build_field_addr(variant_val, b, ptr_elem_ty));
                                field_ty = ptr_elem_ty;
                                field_is_lv = true;
                            } else {
                                ILValue field_ptr = emit(ctx, il_build_field_addr(variant_val, b, il_type_ptr(elem_ty, get_region(variant_val.type), false)));
                                field_val = emit(ctx, il_build_load(field_ptr));
                                field_ty = field_val.type;
                                field_is_lv = is_aggregate_type_layout(elem_ty);
                                if (field_is_lv) {
                                    field_val = promote_to_lvalue(ctx, field_val);
                                    field_ty = field_val.type;
                                }
                            }
                        }

                        if (arms.types[b] == NULL) {
                            arms.types[b] = field_ty;
                            arms.is_lvalue[b] = field_is_lv;
                        } else if (!il_type_eq(arms.types[b], field_ty)) {
                            emit_diag_at(ctx, DIAG_ERROR, expr->target, "Variable bindings in multi-pattern match must have the same type in each variant");
                        }

                        arms.payloads[b] = realloc(arms.payloads[b], (arms.payload_counts[b] + 1) * sizeof(ILPhiIncoming));
                        arms.payloads[b][arms.payload_counts[b]].block_id = ctx->current_block->id;
                        arms.payloads[b][arms.payload_counts[b]].value_id = field_val.id;
                        arms.payload_counts[b]++;
                    }
                } else if (arms.count > 0) {
                    // Check if all existing bindings are wildcards
                    for (uint32_t b = 0; b < arms.count; b++) {
                        if (arms.names[b] != NULL) {
                            emit_diag_at(ctx, DIAG_ERROR, expr->target, "All variants in a multi-pattern match must bind the same variables");
                            break;
                        }
                    }
                }
                add_jump(ctx, arm_blk);
                ctx->current_block = next_p_blk;
            } else {                // Literal patterns (Int, Bool, Char)
                bool type_mismatch = false;
                if (p->kind == PATTERN_INT || p->kind == PATTERN_RANGE) {
                    if (!is_integral_type(subject_ty) && !is_float_type(subject_ty)) {
                        emit_diag_at(ctx, DIAG_ERROR, expr->target, "Numeric or range pattern used on incompatible type");
                        type_mismatch = true;
                    }
                } else if (p->kind == PATTERN_BOOL) {
                    if (subject_ty->kind != IL_TY_BOOL) {
                        emit_diag_at(ctx, DIAG_ERROR, expr->target, "Boolean pattern used on non-boolean type");
                        type_mismatch = true;
                    }
                }

                if (type_mismatch) {
                    p = p->next; continue;
                }

                ILValue subject_val = target;
                if (target.type && (target.type->kind == IL_TY_PTR || target.type->kind == IL_TY_BOX)) {
                    subject_val = emit(ctx, il_build_load(target));
                }

                ILValue cmp;
                if (p->kind == PATTERN_RANGE) {
                    ILValue start_val, end_val;
                    if (is_float_type(subject_ty)) {
                        start_val = emit(ctx, il_build_fconst((double)p->as.range.start, subject_ty));
                        end_val = emit(ctx, il_build_fconst((double)p->as.range.end, subject_ty));
                    } else {
                        start_val = emit(ctx, il_build_const(p->as.range.start, subject_ty));
                        end_val = emit(ctx, il_build_const(p->as.range.end, subject_ty));
                    }
                    
                    ILValue ge_start = emit(ctx, il_build_cmp_ge(subject_val, start_val, il_type_bool()));
                    ILValue le_end;
                    if (p->as.range.is_inclusive) {
                        le_end = emit(ctx, il_build_cmp_le(subject_val, end_val, il_type_bool()));
                    } else {
                        le_end = emit(ctx, il_build_cmp_lt(subject_val, end_val, il_type_bool()));
                    }
                    cmp = emit(ctx, il_build_and(ge_start, le_end));
                } else {
                    ILValue pat_val = {0};
                    if (p->kind == PATTERN_INT) {
                        if (is_float_type(subject_ty)) pat_val = emit(ctx, il_build_fconst((double)p->as.int_val, subject_ty));
                        else pat_val = emit(ctx, il_build_const(p->as.int_val, subject_ty));
                    } else if (p->kind == PATTERN_BOOL) {
                        pat_val = emit(ctx, il_build_const(p->as.bool_val ? 1 : 0, il_type_bool()));
                    }

                    if (!pat_val.type) { p = p->next; continue; }
                    cmp = emit(ctx, il_build_cmp_eq(subject_val, pat_val, il_type_bool()));
                }

                ILBasicBlock* next_p_blk = create_block(ctx);
                if (ctx->current_block) {
                    ILInstruction* br = il_build_branch(cmp, arm_blk->id, next_p_blk->id);
                    if (!br) {
                        if (ctx->report && ctx->report->has_errors) {
return match_lower_fail(&arms, incoming, merged_state, orig_state);
                        }
                        emit_diag_at(ctx, DIAG_ERROR, expr->target, "Failed to build branch for literal pattern in match");
return match_lower_fail(&arms, incoming, merged_state, orig_state);
                    }
                    il_block_add_instr(ctx->current_block, br);
                    il_block_add_successor(ctx->current_block, arm_blk);
                    il_block_add_successor(ctx->current_block, next_p_blk);
                }
                ctx->current_block = next_p_blk;
            }
            p = p->next;
        }

        // After all patterns in the arm, if none matched, we jump to next_arm_blk
        if (ctx->current_block) {
            add_jump(ctx, next_arm_blk);
        }

        if (i == expr->arm_count - 1 && !arm_has_wildcard) {
            // Unhandled variants fall through to panic (only if no wildcard)
            ctx->current_block = next_arm_blk;
            if (target.type && target.type->kind == IL_TY_BOX) {
                emit_void(ctx, il_build_drop(target));
            }
            
            ILBasicBlock* panic_blk = create_block(ctx);
            add_jump(ctx, panic_blk);
            ctx->current_block = panic_blk;
            
            const ILFunction* abort_fn = il_mod_get_func_by_name(ctx->module, "abort");
            if (abort_fn) {
                ILInstruction* call = il_build_call(abort_fn->id, NULL, 0, il_type_unit());
                emit_void(ctx, call);
            }
            const ILType* fn_ret = ctx->current_func->return_type;
            ILValue dummy_ret;
            if (fn_ret->kind == IL_TY_UNIT) {
                dummy_ret = (ILValue){ .id = 0, .type = il_type_unit() };
            } else {
                dummy_ret = emit(ctx, il_build_const(0, fn_ret));
            }
            il_block_add_instr(ctx->current_block, il_build_return(dummy_ret));
        }

        ctx->current_block = arm_blk;
        // Restore to original state for each arm
        restore_moved_state(ctx, NULL, 0); // Clear current state
        
        bool* copy_state = malloc(orig_cap > 0 ? orig_cap * sizeof(bool) : 1);
        if (copy_state) {
            if (orig_state && orig_cap > 0) memcpy(copy_state, orig_state, orig_cap * sizeof(bool));
            restore_moved_state(ctx, copy_state, orig_cap);
        }

        scope_push(ctx);
        
        if (arms.count > 0) {
            for (uint32_t b = 0; b < arms.count; b++) {
                if (arms.names[b] == NULL) continue; // Wildcard '_' in pattern
                
                ILValue bind_val;
                if (arms.payload_counts[b] == 1) {
                    bind_val = (ILValue){ .id = arms.payloads[b][0].value_id, .type = arms.types[b] };
                } else if (arms.payload_counts[b] > 1) {
                    ILInstruction* phi = il_build_phi(arms.payloads[b], arms.payload_counts[b], arms.types[b]);
                    bind_val = emit(ctx, phi);
                } else {
                    // This can happen if all variants used '_' for this position.
                    continue;
                }
                symbol_add_ctx(ctx, arms.names[b], bind_val, arms.is_lvalue[b]);
            }
        }
        match_arm_state_free(&arms);
        
        ILValue val = lower_expression(ctx, arm->body, res_type, dest_ptr);
        if (!block_is_terminated(ctx->current_block)) {
            if (val.type && val.type->kind != IL_TY_NEVER) {
                if (!res_type || res_type->kind == IL_TY_NEVER) {
                    res_type = val.type;
                }
            } else if (!res_type && val.type) {
                res_type = val.type;
            }
            
            ILValue assigned = ensure_assignable(ctx, val, res_type);

            incoming[incoming_count].block_id = ctx->current_block->id;
            incoming[incoming_count].value_id = assigned.id;
            incoming_count++;
            
            scope_pop(ctx, assigned.id);
            add_jump(ctx, join_blk);
        } else {
            scope_pop(ctx, 0);
        }
        
        // Merge arm exit state into merged_state
        if (ctx->value_moved_capacity > merged_cap) {
            bool* next_state = realloc(merged_state, ctx->value_moved_capacity * sizeof(bool));
            if (next_state) {
                merged_state = next_state;
                memset(merged_state + merged_cap, 0, (ctx->value_moved_capacity - merged_cap) * sizeof(bool));
                merged_cap = ctx->value_moved_capacity;
            }
        }
        if (merged_state) {
            for (uint32_t k = 0; k < ctx->value_moved_capacity && k < merged_cap; k++) {
                merged_state[k] = merged_state[k] || ctx->value_moved[k];
            }
        }

        ctx->current_block = next_arm_blk;
    }

    restore_moved_state(ctx, merged_state, merged_cap);
    free(orig_state);

    if (incoming_count == 0) {
        // All arms diverge (every arm uses return/break/continue).
        // Return the never type to signal divergence to the caller.
        free(incoming);
        // Mark join block as terminated since it's unreachable
        // (Actually, better to set current_block to NULL to signal unreachable)
        ctx->current_block = NULL;
        return (ILValue){ .id = 0, .type = il_type_never() };
    }

    // If some arms diverge, we must ensure all reachable arms are compatible.
    // (res_type was already updated during arm lowering).
    
    ctx->current_block = join_blk;
    
    ILValue result = {0};
    if (!res_type || res_type->kind == IL_TY_UNIT) {
        free(incoming);
        return (ILValue){ .id = 0, .type = il_type_unit() };
    }

    ILInstruction* phi = il_build_phi(incoming, incoming_count, res_type);
    result = emit(ctx, phi);
    
    free(incoming);
    return result;
}

Symbol* symbol_lookup_ctx(LowerContext* ctx, const char* name) {
    return symbol_lookup(ctx->current_scope, name);
}

