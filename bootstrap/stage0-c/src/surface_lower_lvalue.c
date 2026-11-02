#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "surface_lower_internal.h"
#include "il_instr.h"
#include "il_pass.h"
#include "il_print.h"
#include "il_ownership.h"

/* Move a just-emitted (alloc, store) promotion pair from the current block to directly after
 * the definition of value_id (the entry block for parameters), so the slot is initialized on
 * every path. Promoting where the address is first taken breaks when that is a conditional
 * block, e.g. the right-hand side of && / ||: other paths would read an unwritten slot. */
static void place_promotion_at_definition(LowerContext* ctx, uint32_t value_id,
                                          ILInstruction* alloc, ILInstruction* store) {
    ILBasicBlock* cur = ctx->current_block;
    ILFunction* fn = ctx->current_func;
    if (!cur || !fn || fn->block_count == 0 || cur->instr_count < 2) return;
    if (cur->instructions[cur->instr_count - 2] != alloc ||
        cur->instructions[cur->instr_count - 1] != store) return;

    ILBasicBlock* def_blk = fn->blocks[0];
    uint32_t pos = 0;
    for (uint32_t b = 0; b < fn->block_count; b++) {
        ILBasicBlock* blk = fn->blocks[b];
        for (uint32_t i = 0; i < blk->instr_count; i++) {
            if (blk->instructions[i]->result_id == value_id) {
                def_blk = blk;
                pos = i + 1;
                break;
            }
        }
        if (pos) break;
    }
    while (pos < def_blk->instr_count && def_blk->instructions[pos]->opcode == IL_OP_PHI) pos++;

    cur->instr_count -= 2;
    if (def_blk == cur && pos > cur->instr_count) pos = cur->instr_count;
    il_block_insert_instr(def_blk, pos, alloc);
    il_block_insert_instr(def_blk, pos + 1, store);
}

static ILValue lower_member_address_val(LowerContext* ctx, ILValue target, const MemberExpr* expr, bool is_mut) {
    if (!target.type) return (ILValue){0};
    
    il_type_fixup(ctx->module, target.type);

    // Auto-dereference through pointers/boxes
    while (target.type && (target.type->kind == IL_TY_PTR || target.type->kind == IL_TY_BOX)) {
        const ILType* pointee = (target.type->kind == IL_TY_PTR) ? target.type->as.ptr.pointee : target.type->as.box.pointee;
        if (pointee->kind == IL_TY_STRUCT || pointee->kind == IL_TY_TUPLE) {
             break;
        }
        if (pointee->kind == IL_TY_PTR || pointee->kind == IL_TY_BOX) {
             ILInstruction* load = il_build_load(target);
             if (!load || !load->result_type) {
                 break;
             }
             
             // If we are dereferencing into a Box, we are borrowing it.
             // Model this by typing the loaded pointer as a Ptr (copy type) instead of Box (owned).
             if (pointee->kind == IL_TY_BOX) {
                 uint32_t rid = (target.type->kind == IL_TY_PTR) ? target.type->as.ptr.region_id : target.type->as.box.region_id;
                 const ILType* borrowed_ty = il_type_ptr(pointee->as.box.pointee, rid, is_mut && pointee->as.box.is_mut);
                 load->result_type = borrowed_ty;
             } else if (pointee->kind == IL_TY_PTR) {
                 uint32_t rid = pointee->as.ptr.region_id;
                 const ILType* borrowed_ty = il_type_ptr(pointee->as.ptr.pointee, rid, is_mut && pointee->as.ptr.is_mut);
                 load->result_type = borrowed_ty;
             }
             
             ILValue next = emit(ctx, load);
             target = next;
        } else {
             break;
        }
    }
    
    if (target.type && (target.type->kind == IL_TY_STRUCT || target.type->kind == IL_TY_TUPLE)) {
        // Value to pointer conversion via temporary for field access
        // We MUST mark the original value as moved because we are accessing its fields,
        // which semantically consumes the value if it's non-Copy.
        if (!il_type_is_copy_mod(ctx->module, target.type)) {
            mark_moved(ctx, target.id);
        }
        const ILType* pty = il_type_ptr(target.type, REGION_LOCAL, true);
        ILInstruction* alc = il_build_alloc(REGION_LOCAL, target.type, pty, (ILValue){0, NULL});
        ILValue tmp = emit(ctx, alc);
        ILInstruction* sto = il_build_store(tmp, target);
        emit(ctx, sto);

        // Mark the temporary as moved because we are using it for field access.
        // It's a copy of the original value, and we don't want to drop this copy again.
        if (!il_type_is_copy_mod(ctx->module, target.type)) {
            mark_moved(ctx, tmp.id);
        }

        target = tmp;
    }

    const ILType* struct_ty = target.type;
    uint32_t region_id = 0;
    bool struct_ty_is_mut = false;

    if (target.type && target.type->kind == IL_TY_PTR) {
        struct_ty = target.type->as.ptr.pointee;
        region_id = target.type->as.ptr.region_id;
        struct_ty_is_mut = target.type->as.ptr.is_mut;
    } else if (target.type && target.type->kind == IL_TY_BOX) {
        struct_ty = target.type->as.box.pointee;
        region_id = target.type->as.box.region_id;
        struct_ty_is_mut = target.type->as.box.is_mut;
    }

    if (!struct_ty || (struct_ty->kind != IL_TY_STRUCT && struct_ty->kind != IL_TY_TUPLE && struct_ty->kind != IL_TY_SLICE)) {
        emit_diag_at(ctx, DIAG_ERROR, expr->object, "Cannot access member of non-struct/tuple/slice type");
        return (ILValue){0};
    }
    
    int idx = -1;
    const ILType* field_ty = NULL;
    const ILTypeDef* def = NULL;

    if (struct_ty->kind == IL_TY_TUPLE) {
        idx = atoi(expr->field_name);
        if (idx < 0 || (uint32_t)idx >= struct_ty->as.tuple.count) {
            emit_diag_at(ctx, DIAG_ERROR, expr->object, "Tuple index out of bounds: %s", expr->field_name);
            return (ILValue){0};
        }
        field_ty = struct_ty->as.tuple.elements[idx];
    } else if (struct_ty->kind == IL_TY_SLICE) {
        if (strcmp(expr->field_name, "ptr") == 0) {
            idx = 0;
            field_ty = il_type_ptr(struct_ty->as.slice.element, struct_ty->as.slice.region_id, struct_ty->as.slice.is_mut);
        } else if (strcmp(expr->field_name, "len") == 0) {
            idx = 1;
            field_ty = il_type_usize();
        } else {
            emit_diag_at(ctx, DIAG_ERROR, expr->object, "Slice has no member '%s'", expr->field_name);
            return (ILValue){0};
        }
    } else {
        def = il_mod_get_type_def(ctx->module, struct_ty->as.struct_sum.type_def_id);
        if (!def) {
            emit_diag_at(ctx, DIAG_ERROR, expr->object, "Failed to get type definition for '%s'", struct_ty->as.struct_sum.name);
            return (ILValue){0};
        }

        idx = find_field_index(def, expr->field_name);
        if (idx < 0) {
            emit_diag_at(ctx, DIAG_ERROR, expr->object, "Type '%s' has no field named '%s'", def->name, expr->field_name);
            return (ILValue){0};
        }
        field_ty = def->fields[idx].type;

        // Visibility check
        if (!def->fields[idx].is_pub && ctx->current_file && def->file_path) {
            if (strcmp(ctx->current_file, def->file_path) != 0) {
                emit_diag_at(ctx, DIAG_ERROR, expr->object, "Access to private field '%s' of type '%s'", expr->field_name, def->name);
            }
        }
    }
    
    const ILType* field_ptr_ty = il_type_ptr(field_ty, region_id, is_mut || struct_ty_is_mut);
    ILInstruction* faddr = il_build_field_addr(target, (uint32_t)idx, field_ptr_ty);
    // Link the field pointer to the struct pointer to track the borrow.
    if (faddr->result_type && faddr->result_type->kind == IL_TY_PTR && target.id != 0) {
        uint32_t rid = get_region(target.type);
        if (rid == REGION_LOCAL || rid == 0) rid = target.id;
        faddr->result_type = il_type_ptr(faddr->result_type->as.ptr.pointee, rid, faddr->result_type->as.ptr.is_mut);
    }
    ILValue faddr_res = emit(ctx, faddr);


    return faddr_res;
}

static ILValue lower_member_address(LowerContext* ctx, const MemberExpr* expr, bool is_mut) {
    ILValue target;
    if (expr->object->kind == EXPR_VAR || expr->object->kind == EXPR_MEMBER || expr->object->kind == EXPR_INDEX ||
        (expr->object->kind == EXPR_UNARY && strcmp(expr->object->as.unary.op, "*") == 0)) {
        target = lower_lvalue(ctx, expr->object, is_mut);
    } else {
        target = lower_expression(ctx, expr->object, NULL, (ILValue){0});
        if (is_aggregate_type_layout(target.type)) {
            target = promote_to_lvalue(ctx, target);
        }
    }
    return lower_member_address_val(ctx, target, expr, is_mut);
}


ILValue lower_lvalue(LowerContext* ctx, const Expression* expr, bool is_mut) {
    if (expr->kind == EXPR_VAR) {
        const Symbol* found_sym = symbol_lookup(ctx->current_scope, expr->as.var.name);
        
        if (found_sym) {
            const Scope* scope = NULL;
            // Find which scope it belongs to for capture analysis
            const Scope* s = ctx->current_scope;
            while (s) {
                const Symbol* sym = s->symbols;
                while (sym) {
                    if (sym == found_sym) { scope = s; break; }
                    sym = sym->next;
                }
                if (scope) break;
                s = s->parent;
            }

            bool is_capture = false;
            s = ctx->current_scope;
            while (s) {
                if (s == scope) break;
                if (s->owner_func == ctx->current_func) {
                    // Still in current func
                } else {
                    is_capture = true;
                    break;
                }
                s = s->parent;
            }

            if (is_capture) {
                return resolve_capture(ctx, found_sym);
            }

            if (is_moved(ctx, found_sym->value.id)) {
                emit_diag_at(ctx, DIAG_ERROR, expr, "use of moved value '%s'", expr->as.var.name);
            }

            ILValue val = { .id = found_sym->value.id, .type = found_sym->value.type };
            if (!val.type) return (ILValue){0};
            if (found_sym->is_lvalue) {
                return val;
            } else {
                // Promote to stack!
                const ILType* ptr_ty = il_type_ptr(val.type, REGION_LOCAL, true);
                ILInstruction* alloc = il_build_alloc(REGION_LOCAL, val.type, ptr_ty, (ILValue){0});
                ILValue ptr = emit(ctx, alloc);
                ILInstruction* store = il_build_store(ptr, val);

                bool was_moved = false;
                bool is_copy = il_type_is_copy_mod(ctx->module, val.type);
                if (!is_copy) {
                    was_moved = is_moved(ctx, val.id);
                    mark_moved(ctx, val.id);
                }
                emit_void(ctx, store);
                place_promotion_at_definition(ctx, val.id, alloc, store);

                // Shadow with the new location - symbol table takes its own copy
                ILValue shadow_val = { .id = ptr.id, .type = ptr.type };
                symbol_add_ctx(ctx, found_sym->name, shadow_val, true);

                if (was_moved) {
                    mark_moved(ctx, ptr.id);
                }

                if (!ptr.type || ptr.type->kind != IL_TY_PTR) return ptr;
                const ILType* final_ty = il_type_ptr(ptr.type->as.ptr.pointee, ptr.id, ptr.type->as.ptr.is_mut);
                ptr.type = final_ty;
                return ptr;
            }
        }
        
        const ILGlobal* g = find_global(ctx->module, expr->as.var.name);
        if (g) {
            // Visibility check
            if (!g->is_pub && ctx->current_file && g->file_path) {
                if (strcmp(ctx->current_file, g->file_path) != 0) {
                    emit_diag_at(ctx, DIAG_ERROR, expr, "Access to private global '%s'", expr->as.var.name);
                }
            }
            const ILType* g_ty_copy = g->type;
            const ILType* ptr_ty = il_type_ptr(g_ty_copy, REGION_STATIC, !g->is_const);
            ILValue g_target = emit(ctx, il_build_global_addr(g->id, ptr_ty));
            return g_target;
        }

        emit_diag_at(ctx, DIAG_ERROR, expr, "Unresolved symbol: %s (as lvalue)", expr->as.var.name);
        return (ILValue){0};
    } else if (expr->kind == EXPR_UNARY && strcmp(expr->as.unary.op, "*") == 0) {
        ILValue ptr = lower_expression_internal(ctx, expr->as.unary.expr, NULL, false, (ILValue){0}, false, false);
        if (ptr.id != 0 && ptr.type && (ptr.type->kind == IL_TY_PTR || ptr.type->kind == IL_TY_BOX)) {
            return ptr;
        }
        emit_diag_at(ctx, DIAG_ERROR, expr, "Cannot dereference non-pointer type");
        return (ILValue){0};
    } else if (expr->kind == EXPR_MEMBER) {
        return lower_member_address(ctx, &expr->as.member, is_mut);
    } else if (expr->kind == EXPR_INDEX) {
        ILValue left = lower_expression_internal(ctx, expr->as.index_expr.left, NULL, false, (ILValue){0}, false, false);
        if (!left.type) return (ILValue){0};

        bool is_vec = is_vec_type(left.type, NULL);
        if (left.type->kind == IL_TY_ARRAY || is_vec) {
            left = lower_lvalue(ctx, expr->as.index_expr.left, is_mut);
        }

        ILValue index = lower_expression_internal(ctx, expr->as.index_expr.index, NULL, true, (ILValue){0}, false, false);
        index = ensure_usize(ctx, index);
        if (!left.type || !index.type) {
            return (ILValue){0};
        }

        if (is_vec) {
            const ILType* vec_elem_ty = get_vec_element_type(ctx->module, left.type);
            if (vec_elem_ty) {
                const ILType* usize_ty = il_type_usize();
                if (usize_ty) {
                    const ILType* usize_ptr_ty = il_type_ptr(usize_ty, get_region(left.type), false);
                    ILValue len_addr = emit(ctx, il_build_field_addr(left, 1, usize_ptr_ty));
                    ILValue len = emit(ctx, il_build_load(len_addr));
                    emit_bounds_check(ctx, index, len);
                }
                uint32_t region_id = get_region(left.type);
                if ((region_id == REGION_LOCAL || region_id == 0) && left.id != 0) {
                    region_id = left.id;
                }
                bool base_is_mut = (left.type->kind == IL_TY_PTR) ? (is_mut || left.type->as.ptr.is_mut) : is_mut;
                const ILType* elem_ptr_ty = il_type_ptr(vec_elem_ty, region_id, base_is_mut);
                const ILType* data_ptr_ty = il_type_ptr(elem_ptr_ty, region_id, false);
                ILValue data_addr = emit(ctx, il_build_field_addr(left, 0, data_ptr_ty));
                ILValue data = emit(ctx, il_build_load(data_addr));
                ILValue res = emit(ctx, il_build_elem_addr(data, index, elem_ptr_ty));
                return res;
            }
        }

        if (!is_vec && left.type->kind == IL_TY_PTR && left.type->as.ptr.pointee->kind != IL_TY_ARRAY && left.type->as.ptr.pointee->kind != IL_TY_SLICE) {
            // Raw pointer indexing
            const ILType* elem_ptr_ty = il_type_ptr(left.type->as.ptr.pointee, left.type->as.ptr.region_id, left.type->as.ptr.is_mut);
            ILValue res = emit(ctx, il_build_elem_addr(left, index, elem_ptr_ty));
            return res;
        }

        const ILType* usize_ty = il_type_usize();
        if (usize_ty) {
            ILValue len;
            if (left.type->kind == IL_TY_PTR && left.type->as.ptr.pointee->kind == IL_TY_ARRAY) {
                len = emit(ctx, il_build_const(left.type->as.ptr.pointee->as.array.length, usize_ty));
            } else if (left.type->kind == IL_TY_SLICE) {
                len = emit(ctx, il_build_slice_len(left, usize_ty));
            } else {
                return (ILValue){0};
            }
            emit_bounds_check(ctx, index, len);
        }

        const ILType* elem_ty;
        uint32_t region_id;
        bool base_is_mut = false;
        if (left.type->kind == IL_TY_PTR) {
            elem_ty = left.type->as.ptr.pointee->as.array.element;
            region_id = left.type->as.ptr.region_id;
            base_is_mut = left.type->as.ptr.is_mut;
        } else {
            elem_ty = left.type->as.slice.element;
            region_id = left.type->as.slice.region_id;
            base_is_mut = left.type->as.slice.is_mut;
        }
        
        // If we are borrowing from an SSA value directly (like a Slice parameter),
        // and it doesn't have a specific SSA region already, track the borrow
        // using the base value's own ID.
        if ((region_id == REGION_LOCAL || region_id == 0) && left.id != 0) {
            region_id = left.id;
        }

        const ILType* res_ptr_ty = il_type_ptr(elem_ty, region_id, base_is_mut);
        ILValue res = emit(ctx, il_build_elem_addr(left, index, res_ptr_ty));
        return res;
    } else if (expr->kind == EXPR_UNARY && strcmp(expr->as.unary.op, "*") == 0) {
        return lower_expression(ctx, expr->as.unary.expr, NULL, (ILValue){0});
    }

    // Fallback: promote to stack if it's not already an lvalue
    ILValue val = lower_expression_internal(ctx, expr, NULL, false, (ILValue){0}, false, false);
    if (val.id == 0 || !val.type) return (ILValue){0};
    
    // Always use a mutable pointer for the initial allocation/store.
    const ILType* ptr_mut_ty = il_type_ptr(val.type, REGION_LOCAL, true);
    ILInstruction* alloc = il_build_alloc(REGION_LOCAL, val.type, ptr_mut_ty, (ILValue){0});
    ILValue ptr = emit(ctx, alloc);
    if (ptr.id == 0 || !ptr.type) return (ILValue){0};
    emit_void(ctx, il_build_store(ptr, val));
    
    const ILType* final_ty = il_type_ptr(ptr.type->as.ptr.pointee, ptr.id, is_mut);
    ptr.type = final_ty;
    return ptr;
}

ILValue lower_member_access(LowerContext* ctx, const MemberExpr* expr, const ILType* expected_type, bool is_move, bool allow_lvalue) {
    if (expr->object->kind == EXPR_VAR) {
        const ILTypeDef* def = NULL;
        
        // Prefer specialized definition from expected type or current module
        if (expected_type && (expected_type->kind == IL_TY_SUM || expected_type->kind == IL_TY_STRUCT) && expected_type->as.struct_sum.type_def_id != 0 && expected_type->as.struct_sum.name) {
            if (strncmp(expected_type->as.struct_sum.name, expr->object->as.var.name, strlen(expr->object->as.var.name)) == 0) {
                def = il_mod_get_type_def(ctx->module, expected_type->as.struct_sum.type_def_id);
            }
        }
        
        if (!def) {
            // Search module for existing monomorphized type starting with this name
            char prefix[256];
            snprintf(prefix, sizeof(prefix), "%s_", expr->object->as.var.name);
            size_t plen = strlen(prefix);
            for (uint32_t i = 0; i < ctx->module->type_def_count; i++) {
                if (strncmp(ctx->module->type_defs[i]->name, prefix, plen) == 0) {
                    def = ctx->module->type_defs[i];
                    break;
                }
            }
        }
        
        if (!def) {
            def = find_type_def(ctx, expr->object->as.var.name);
        }
        
                if (def && def->is_sum) {
                    int v_idx = find_field_index(def, expr->field_name);
                    if (v_idx >= 0) {
                        const ILType* unit_ty = il_build_unit_type();
                        ILValue payload = (ILValue){ .id = 0, .type = unit_ty };
                        
                        const ILType* sum_ty = il_type_sum(def->name, def->id);
                        if (sum_ty) {
                            // Copy type arguments from current monomorphized definition
                            const ILTypeDef* concrete_def = il_mod_get_type_def(ctx->module, def->id);
                            if (concrete_def && concrete_def->name) {
                                 // Already specialized, but we need to derive the ILType correctly
                            }

                            // Re-resolve to get correct monomorphized ID and variants
                            const ILType* resolved = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, sum_ty, ctx->current_substs);
                            if (resolved != sum_ty) {
                                sum_ty = resolved;
                            }

                            ILInstruction* construct = il_build_sum_construct(sum_ty->as.struct_sum.type_def_id, (uint32_t)v_idx, payload, sum_ty);
                            ILValue res = emit(ctx, construct);
                            return res;
                        }
                    }
                }
    }

    ILValue target;
    bool is_static_type_access = false;
    if (expr->object->kind == EXPR_VAR) {
        const ILTypeDef* def = find_type_def(ctx, expr->object->as.var.name);
        if (def) {
            is_static_type_access = true;
            target = (ILValue){ .id = 0, .type = il_type_ptr(il_type_unit(), REGION_STATIC, false) }; // Dummy for static access
        } else {
            target = lower_lvalue(ctx, expr->object, false);
        }
    } else {
        target = lower_lvalue(ctx, expr->object, false);
    }

    if (target.type) {
        if (is_static_type_access) {
            const ILTypeDef* def = find_type_def(ctx, expr->object->as.var.name);
            if (def) {
                char mname[512];
                snprintf(mname, sizeof(mname), "%s_%s", def->name, expr->field_name);
                const ILGlobal* g = find_global(ctx->module, mname);
                if (g) {
                    const ILType* ptr_ty = il_type_ptr(g->type, REGION_STATIC, false);
                    ILValue gaddr = emit(ctx, il_build_global_addr(g->id, ptr_ty));
                    ILValue res = emit(ctx, il_build_load(gaddr));
                    return res;
                }
                emit_diag_at(ctx, DIAG_ERROR, expr->object, "Type '%s' has no static member '%s'", def->name, expr->field_name);
                return (ILValue){0};
            }
        }
        const ILType* t = target.type;
        while (t && (t->kind == IL_TY_PTR || t->kind == IL_TY_BOX)) {
            const ILType* pointee = (t->kind == IL_TY_PTR) ? t->as.ptr.pointee : t->as.box.pointee;
            
            if (pointee->kind == IL_TY_STRUCT || pointee->kind == IL_TY_SUM || pointee->kind == IL_TY_SLICE || pointee->kind == IL_TY_ARRAY) {
                // Keep the pointer/box to the aggregate
                break;
            }
            
            ILInstruction* load = il_build_load(target);
            if (!load || !load->result_type) {
                break;
            }
            if (load->result_type->kind == IL_TY_BOX) {
                 const ILType* box_ty = load->result_type;
                 const ILType* ptr_ty = il_type_ptr(box_ty->as.box.pointee, target.id, false && box_ty->as.box.is_mut);
                 load->result_type = ptr_ty;
            } else if (load->result_type->kind == IL_TY_PTR) {
                 const ILType* ptr_ty_old = load->result_type;
                 const ILType* ptr_ty = il_type_ptr(ptr_ty_old->as.ptr.pointee, target.id, false && ptr_ty_old->as.ptr.is_mut);
                 load->result_type = ptr_ty;
            }
            ILValue next_target = emit(ctx, load);
            target = next_target;
            t = target.type;
        }

        t = target.type;
        const ILType* agg_ty = t;
        if (t && (t->kind == IL_TY_PTR || t->kind == IL_TY_BOX)) {
            agg_ty = (t->kind == IL_TY_PTR) ? t->as.ptr.pointee : t->as.box.pointee;
        }

        if (agg_ty && agg_ty->kind == IL_TY_SLICE) {
            // ... (keep existing slice logic)
            if (strcmp(expr->field_name, "len") == 0) {
                const ILType* usize_ty = il_type_usize();
                if (usize_ty) {
                    ILInstruction* slen = il_build_slice_len(target, usize_ty);
                    if (slen) {
                        ILValue res = emit(ctx, slen);
                        return res;
                    }
                }
            } else if (strcmp(expr->field_name, "ptr") == 0) {
                const ILType* slice_ty = agg_ty;
                const ILType* elem_ptr_ty = il_type_ptr(slice_ty->as.slice.element, slice_ty->as.slice.region_id, slice_ty->as.slice.is_mut);
                ILValue slice_ptr_val = target;

                if (target.type->kind == IL_TY_SLICE) {
                    // Need a pointer to the slice value
                    const ILType* slice_ptr_ty = il_type_ptr(target.type, REGION_LOCAL, true);
                    slice_ptr_val = emit(ctx, il_build_alloc(REGION_LOCAL, target.type, slice_ptr_ty, (ILValue){0}));
                    emit_void(ctx, il_build_store(slice_ptr_val, target));
                }
                
                // Bitcast Ptr<Slice> to Ptr<Ptr<T>> to read the first field (ptr): a slice is
                // {ptr, len}, and only the pointer is wanted here.
                const ILType* ptr_to_ptr_ty = il_type_ptr(elem_ptr_ty, REGION_LOCAL, false);
                ILValue casted_ptr = { .id = slice_ptr_val.id, .type = ptr_to_ptr_ty };
                
                ILInstruction* load_instr = il_build_load(casted_ptr);
                ILValue ptr_res = emit(ctx, load_instr);
                
                // Fix up the result type to be exactly what we want
                ptr_res.type = elem_ptr_ty; // Takes ownership
                
                return ptr_res;
            }
        } else if (agg_ty && agg_ty->kind == IL_TY_ARRAY) {
            if (strcmp(expr->field_name, "len") == 0) {
                return emit(ctx, il_build_const(agg_ty->as.array.length, il_type_usize()));
            } else if (strcmp(expr->field_name, "ptr") == 0) {
                ILValue arr_ptr = target;
                if (target.type->kind == IL_TY_ARRAY) {
                    arr_ptr = promote_to_lvalue(ctx, target);
                }
                const ILType* elem_ptr_ty = il_type_ptr(agg_ty->as.array.element, get_region(arr_ptr.type), is_mut_borrow(arr_ptr.type));
                return emit(ctx, il_build_bitcast(arr_ptr, elem_ptr_ty));
            }
        } else if (agg_ty && agg_ty->kind == IL_TY_STRUCT) {
            // Check for method only if it's NOT a field
            const ILTypeDef* def = il_mod_get_type_def(ctx->module, t->as.struct_sum.type_def_id);
            if (def) {
                if (find_field_index(def, expr->field_name) < 0) {
                    char mname[512];
                    snprintf(mname, sizeof(mname), "%s_%s", def->name, expr->field_name);
                    const ILFunction* mfunc = il_mod_get_func_by_name(ctx->module, mname);
                    if (mfunc) {
                        // It's a method! Return a dummy value that lower_call can use if needed,
                        // but usually lower_call handles expr->receiver directly.
                        return (ILValue){ .id = 0, .type = il_type_ptr(il_type_unit(), REGION_STATIC, false) };
                    }
                }
            }
        }
    }

    if (is_static_type_access) {
        // Static access (e.g., Vec2.new) - lower_call will resolve via method name
        return target;
    }

    ILValue addr = lower_member_address_val(ctx, target, expr, false);
    if (addr.id == 0) return (ILValue){0};
    
    if (allow_lvalue && addr.type && addr.type->kind == IL_TY_PTR && addr.type->as.ptr.pointee && is_vec_type(addr.type->as.ptr.pointee, NULL)) {
        return (ILValue){ .id = addr.id, .type = addr.type->as.ptr.pointee };
    }

    ILInstruction* load = il_build_load(addr);
    if (!load || !load->result_type) {
        return (ILValue){0};
    }

    if (!ctx->current_loop && load->result_type->kind == IL_TY_BOX) {
        const ILType* box_ty = load->result_type;
        const ILType* ptr_ty = il_type_ptr(box_ty->as.box.pointee, box_ty->as.box.region_id, box_ty->as.box.is_mut);

        load->result_type = ptr_ty;
    }

    ILValue res = emit(ctx, load);
    emit_void(ctx, il_build_drop(addr));
    mark_moved(ctx, addr.id);  // prevent double-drop from temporary cleanup

    // Moving a non-Copy field out of the base moves (part of) the base. Reading a Copy field
    // moves nothing: `let a = pair.0; let b = pair.0;` must not reject the second read.
    const ILType* field_ty = (addr.type && addr.type->kind == IL_TY_PTR) ? addr.type->as.ptr.pointee : NULL;
    if (is_move && !allow_lvalue && target.type && field_ty && !il_type_is_copy_mod(ctx->module, field_ty)) {
        const ILType* base_ty = target.type;
        if (base_ty->kind == IL_TY_PTR) base_ty = base_ty->as.ptr.pointee;
        else if (base_ty->kind == IL_TY_BOX) base_ty = base_ty->as.box.pointee;
        
        if (base_ty && !il_type_is_copy_mod(ctx->module, base_ty)) {
            mark_moved(ctx, target.id);
        }
    }

    return res;
}

