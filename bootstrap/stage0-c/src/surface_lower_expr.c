#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "surface_lower_internal.h"
#include "surface_parser_internal.h"
#include "il_type.h"
#include "il_instr.h"
#include "il_print.h"

// Forward declarations for static helpers defined in this file
static ILValue lower_struct_literal(LowerContext* ctx, const StructExpr* expr, ILValue dest_ptr);
static ILValue lower_struct_literal_typed(LowerContext* ctx, const StructExpr* expr, ILValue dest_ptr, const ILType* expected_type);
static ILValue lower_index_expr(LowerContext* ctx, const IndexExpr* expr, bool allow_lvalue);
static ILValue lower_assignment(LowerContext* ctx, const Expression* expr, const char* base_op);
static ILValue lower_binary(LowerContext* ctx, const Expression* expr);
static ILValue lower_logical(LowerContext* ctx, const BinaryExpr* binary);
static ILValue lower_box(LowerContext* ctx, const Expression* expr);
static ILValue lower_array_literal(LowerContext* ctx, const Expression* expr, const ILType* expected_type);
static ILValue lower_tuple_literal(LowerContext* ctx, const Expression* expr, const ILType* expected_type, ILValue dest_ptr);
static ILValue lower_cast(LowerContext* ctx, const Expression* expr, const ILType* target_type);
static ILValue lower_try_expr(LowerContext* ctx, const Expression* inner);
static ILValue lower_return_expr(LowerContext* ctx, const Expression* inner);
static ILValue lower_closure_expr(LowerContext* ctx, const ClosureExpr* expr, const ILType* expected_type);
static ILValue lower_slice_comparison(LowerContext* ctx, const char* op, ILValue left, ILValue right);
ILValue lower_expression(LowerContext* ctx, const Expression* expr, const ILType* expected_type, ILValue dest_ptr) {
    return lower_expression_internal(ctx, expr, expected_type, false, dest_ptr, false, false);
}

ILValue lower_expression_move(LowerContext* ctx, const Expression* expr, const ILType* expected_type, ILValue dest_ptr) {
    return lower_expression_internal(ctx, expr, expected_type, true, dest_ptr, false, false);
}

/* 
 * Adds a jump to the target block if the current block is not already terminated.
 * target is not const because it is passed to il_block_add_successor which
 * modifies its predecessor list.
 */
// cppcheck-suppress constParameterPointer
void add_jump(LowerContext* ctx, ILBasicBlock* target) {
    if (!ctx || !ctx->current_block || block_is_terminated(ctx->current_block)) return;
    il_block_add_instr(ctx->current_block, il_build_jump(target->id));
    il_block_add_successor(ctx->current_block, target);
}
static ILValue lower_struct_literal_typed(LowerContext* ctx, const StructExpr* expr, ILValue dest_ptr, const ILType* expected_type);

static ILValue lower_struct_literal(LowerContext* ctx, const StructExpr* expr, ILValue dest_ptr) {
    return lower_struct_literal_typed(ctx, expr, dest_ptr, NULL);
}

static ILValue lower_struct_literal_typed(LowerContext* ctx, const StructExpr* expr, ILValue dest_ptr, const ILType* expected_type) {
    const ILTypeDef* def = NULL;
    const ILType* struct_ty = NULL;

    // Prefer specialized definition from expected type if it matches the name (including mangled generic names)
    if (expected_type && expected_type->kind == IL_TY_STRUCT && expected_type->as.struct_sum.type_def_id != 0 && expected_type->as.struct_sum.name) {
        if (strncmp(expected_type->as.struct_sum.name, expr->name, strlen(expr->name)) == 0) {
            def = il_mod_get_type_def(ctx->module, expected_type->as.struct_sum.type_def_id);
            struct_ty = expected_type;
        }
    }

    if (!def) {
        def = find_type_def(ctx, expr->name);
    }

    if (!def) return (ILValue){0};

    // If it's a generic struct and we don't have an expected type yet, try to infer type args from fields
    if (def->is_generic && (!expected_type || expected_type->kind != IL_TY_STRUCT || expected_type->as.struct_sum.type_def_id == 0)) {
        const TypeDef* styp = NULL;
        for (uint32_t i = 0; i < ctx->surface_mod->type_def_count; i++) {
            const char* sname = (ctx->surface_mod->type_defs[i]->kind == TYPE_DEF_STRUCT) ? ctx->surface_mod->type_defs[i]->as.struct_decl->name : ctx->surface_mod->type_defs[i]->as.enum_decl->name;
            if (strcmp(sname, expr->name) == 0) {
                styp = ctx->surface_mod->type_defs[i];
                break;
            }
        }

        if (styp && styp->kind == TYPE_DEF_STRUCT && styp->as.struct_decl->type_param_count > 0) {
            uint32_t tpc = styp->as.struct_decl->type_param_count;
            const ILType ** lowered_args = NULL;
            
            if (expr->type_arg_count > 0) {
                // Explicit type arguments provided
                lowered_args = calloc(expr->type_arg_count, sizeof(const ILType*));
                if (lowered_args) {
                    for (uint32_t j = 0; j < expr->type_arg_count; j++) {
                        lowered_args[j] = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, expr->type_args[j], ctx->current_substs);
                    }
                    tpc = expr->type_arg_count; // Just in case
                }
            } else {
                // Infer from fields
                lowered_args = calloc(tpc, sizeof(const ILType*));
                if (lowered_args) {
                    for (uint32_t k = 0; k < tpc; k++) {
                        for (uint32_t i = 0; i < expr->field_count; i++) {
                            int idx = find_field_index(def, expr->field_names[i]);
                            if (idx >= 0 && def->fields) {
                                const ILType* gty = guess_type_internal(ctx, expr->field_values[i], NULL);
                                if (gty) {
                                    if (match_type_param(ctx, def->fields[idx].type, gty, styp->as.struct_decl->type_params[k], &lowered_args[k])) {
                                         break;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if (lowered_args) {
                // Create a specialized type using explicit or inferred arguments
                const ILType* t = il_type_struct_gen(styp->as.struct_decl->name, 0, lowered_args, tpc);
                free(lowered_args);

                const ILType* resolved = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, t, ctx->current_substs);
                if (resolved && resolved->kind == IL_TY_STRUCT && resolved->as.struct_sum.type_def_id != 0) {
                    struct_ty = resolved;
                    def = il_mod_get_type_def(ctx->module, resolved->as.struct_sum.type_def_id);
                }
            }
        }
    }

    if (!def) return (ILValue){0};
    
    if (!struct_ty) {
        struct_ty = il_type_struct(def->name, def->id);
    }
    if (!struct_ty) {
        ICE("Failed to create struct type for %s", def->name);
    }
    
    const ILType* ptr_ty = il_type_ptr(struct_ty, REGION_LOCAL, true); // local region
    
    ILValue ptr;
    if (dest_ptr.type != NULL) {
        ptr = dest_ptr;
    } else {
        ILInstruction* alloc = il_build_alloc(REGION_LOCAL, struct_ty, ptr_ty, (ILValue){0});
        ptr = emit(ctx, alloc);
    }
    
    for (uint32_t i = 0; i < expr->field_count; i++) {
        int idx = find_field_index(def, expr->field_names[i]);
        if (idx < 0) continue;
        
        if (!def->fields) continue;
        const ILType* field_type = def->fields[idx].type;

        const ILType* field_ptr_ty = il_type_ptr(field_type, REGION_LOCAL, true);
        ILInstruction* faddr = il_build_field_addr(ptr, (uint32_t)idx, field_ptr_ty);
        ILValue faddr_res = emit(ctx, faddr);

        ILValue field_val = lower_expression_move(ctx, expr->field_values[i], field_type, faddr_res);

        if (field_val.id != faddr_res.id) {
            ILInstruction* store = il_build_store(faddr_res, field_val);
            il_block_add_instr(ctx->current_block, store);
            
            // If field value is non-copy, mark it as moved.
            if (field_val.type && !il_type_is_copy_mod(ctx->module, field_val.type)) {
                mark_moved(ctx, field_val.id);
            }
        }
    }
    
    if (dest_ptr.id == 0) {
        if (requires_pass_by_ref(ctx->module, struct_ty)) {
            // Large aggregates must remain as pointers
            return ptr;
        }
        ILInstruction* load = il_build_load(ptr);
        ILValue val = emit(ctx, load);
        return val;
    }
    // Return the dest_ptr but with the aggregate type to signal it's already in place
    return (ILValue){ .id = ptr.id, .type = struct_ty };
}


void emit_bounds_check(LowerContext* ctx, ILValue index, ILValue length) {
    ILBasicBlock* ok_blk = create_block(ctx);
    
    const ILType * bool_ty = il_type_bool();
    ILInstruction* cmp = il_build_cmp_lt(index, length, bool_ty);
    if (!cmp) return;
    ILValue cmp_res = emit(ctx, cmp);
    
    // Find or create the global panic block for this function
    ILBasicBlock* func_panic = NULL;
    for (uint32_t i = 0; i < ctx->current_func->block_count; i++) {
        if (ctx->current_func->blocks[i]->id == 999) {
            func_panic = ctx->current_func->blocks[i];
            break;
        }
    }
    if (!func_panic) {
        func_panic = il_block_create(999);
        il_func_add_block(ctx->current_func, func_panic);
        ILBasicBlock* saved = ctx->current_block;
        ctx->current_block = func_panic;
        
        // Emit a syscall for exit(134) (128 + SIGABRT) to ensure it doesn't return
        const ILType * i64_ty = il_type_i64();
        ILValue exit_code = emit(ctx, il_build_const(134, i64_ty));
        
        ILValue* args = calloc(1, sizeof(ILValue));
        if (args) {
            args[0] = exit_code;
            ILInstruction* sys_exit = il_build_syscall(60, args, 1, i64_ty);
            emit_void(ctx, sys_exit);
        }

        // Block MUST still be terminated for IL CFG validity.
        // We use a dummy constant 0 of the correct type to avoid return type mismatch.
        // For sret functions, return_type is unit, so il_build_const(0, unit) might not work.
        ILValue dummy_ret;
        if (ctx->current_func->return_type->kind == IL_TY_UNIT) {
            dummy_ret = (ILValue){ .id = 0, .type = il_type_unit() };
        } else {
            dummy_ret = emit(ctx, il_build_const(0, ctx->current_func->return_type));
        }
        il_block_add_instr(func_panic, il_build_return(dummy_ret));
        
        free(args);
        
        ctx->current_block = saved;
    }

    ILInstruction* br = il_build_branch(cmp_res, ok_blk->id, func_panic->id);
    il_block_add_instr(ctx->current_block, br);
    il_block_add_successor(ctx->current_block, ok_blk);
    il_block_add_successor(ctx->current_block, func_panic);
    
    ctx->current_block = ok_blk;
    // Emit the marker instruction for the verifier
    emit(ctx, il_build_bounds_check(index, length));
}

ILValue ensure_usize(LowerContext* ctx, ILValue val) {
    if (!val.type) return val;
    if (val.type->kind == IL_TY_USIZE) return val;
    if (val.type->kind != IL_TY_I64 && val.type->kind != IL_TY_U64 && 
        val.type->kind != IL_TY_ISIZE &&
        val.type->kind != IL_TY_U32 && 
        val.type->kind != IL_TY_I32 && val.type->kind != IL_TY_U16 && 
        val.type->kind != IL_TY_I16 && val.type->kind != IL_TY_U8 && 
        val.type->kind != IL_TY_I8 && val.type->kind != IL_TY_FD &&
        val.type->kind != IL_TY_ASYNC_CONTEXT) {
        return val;
    }
    const ILType* target_ty = il_type_usize();
    if (!target_ty) return val;
    ILInstruction* instr = il_build_bitcast(val, target_ty);
    if (instr) {
        ILValue res = emit(ctx, instr);
        return res;
    }
    return val;
}

/* An aggregate element read with allow_lvalue is returned as its address, typed as the
 * element. Not a slice element: indexing it again (`v[i][j]`) takes a slice-typed value to
 * be the slice itself, so it is read as a value (a 16-byte copy). */
static bool index_yields_address(const ILType* elem_ty) {
    return is_aggregate_type_layout(elem_ty) && elem_ty->kind != IL_TY_SLICE;
}

static ILValue lower_index_expr(LowerContext* ctx, const IndexExpr* expr, bool allow_lvalue) {
    ILValue left;
    // For EXPR_VAR lvalues whose stack slot holds a (non-copy) slice, use the
    // pointer-to-slice directly.  Loading the slice value first would mark the
    // pointer as MOVED in the verifier, making the end-of-scope drop invalid.
    bool left_is_slice_ptr = false;
    if (expr->left->kind == EXPR_VAR) {
        const Symbol* sym = symbol_lookup(ctx->current_scope, expr->left->as.var.name);
        if (sym && sym->is_lvalue && sym->value.type &&
                sym->value.type->kind == IL_TY_PTR &&
                sym->value.type->as.ptr.pointee &&
                (sym->value.type->as.ptr.pointee->kind == IL_TY_SLICE ||
                 is_vec_type(sym->value.type->as.ptr.pointee, NULL))) {
            left = (ILValue){ .id = sym->value.id, .type = sym->value.type };
            left_is_slice_ptr = true;
        }
    }
    if (!left_is_slice_ptr) {
        left = lower_expression_internal(ctx, expr->left, NULL, false, (ILValue){0}, true, false);
    }
    ILValue index = lower_expression(ctx, expr->index, NULL, (ILValue){0});
    index = ensure_usize(ctx, index);

    if (!left.type || !index.type) {
        return (ILValue){0};
    }

    if (left.type->kind == IL_TY_ARRAY || (left.type->kind == IL_TY_PTR && left.type->as.ptr.pointee->kind == IL_TY_ARRAY)) {
        const ILType* array_ty = (left.type->kind == IL_TY_ARRAY) ? left.type : left.type->as.ptr.pointee;
        const ILType* usize_ty = il_type_usize();
        if (usize_ty) {
            ILValue len = emit(ctx, il_build_const(array_ty->as.array.length, usize_ty));
            emit_bounds_check(ctx, index, len);

            const ILType* elem_ty_copy = array_ty->as.array.element;
            if (allow_lvalue && index_yields_address(elem_ty_copy)) {
                const ILType* elem_ptr_ty = il_type_ptr(elem_ty_copy, get_region(left.type), is_mut_borrow(left.type));
                ILValue res = emit(ctx, il_build_elem_addr(left, index, elem_ptr_ty));
                return (ILValue){ .id = res.id, .type = elem_ty_copy };
            }
            ILValue res = emit(ctx, il_build_array_load(left, index, elem_ty_copy));
            return res;
        }
    } else if (left.type->kind == IL_TY_SLICE || (left.type->kind == IL_TY_PTR && left.type->as.ptr.pointee->kind == IL_TY_SLICE)) {
        ILValue slice_ptr = left;
        if (left.type->kind == IL_TY_SLICE) {
            // Need a pointer to the slice
            const ILType* ptr_ty = il_type_ptr(left.type, REGION_LOCAL, true);
            slice_ptr = emit(ctx, il_build_alloc(REGION_LOCAL, left.type, ptr_ty, (ILValue){0}));
            emit_void(ctx, il_build_store(slice_ptr, left));
            if (!il_type_is_copy_mod(ctx->module, left.type)) {
                mark_moved(ctx, left.id);
            }
        }
        
        const ILType* usize_ty = il_type_usize();
        if (!usize_ty) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "Failed to get usize type");
            return (ILValue){0};
        }
        ILValue len = emit(ctx, il_build_slice_len(slice_ptr, usize_ty));
        emit_bounds_check(ctx, index, len);

        const ILType* elem_ty_copy = (left.type->kind == IL_TY_SLICE) ? left.type->as.slice.element : left.type->as.ptr.pointee->as.slice.element;
        if (allow_lvalue && index_yields_address(elem_ty_copy)) {
            const ILType* elem_ptr_ty = il_type_ptr(elem_ty_copy, get_region(left.type), is_mut_borrow(left.type));
            ILInstruction* elem_addr = il_build_elem_addr(left, index, elem_ptr_ty);
            if (elem_addr) {
                ILValue res = emit(ctx, elem_addr);
                return (ILValue){ .id = res.id, .type = elem_ty_copy };
            }
            emit_diag_at(ctx, DIAG_ERROR, expr->left, "Failed to build element address");
            return (ILValue){0};
        }
        ILInstruction* slice_load = il_build_slice_load(slice_ptr, index);
        if (slice_load) return emit(ctx, slice_load);
        
        emit_diag_at(ctx, DIAG_ERROR, expr->left, "Failed to build slice load");
        return (ILValue){0};
    } else if (left_is_slice_ptr || is_vec_type(left.type, NULL)) {
        const ILType* elem_ty = get_vec_element_type(ctx->module, (left_is_slice_ptr ? left.type->as.ptr.pointee : left.type));
        ILValue vec_ptr = left;
        if (left.type->kind == IL_TY_STRUCT) {
            vec_ptr = lower_lvalue(ctx, expr->left, false);
            if (vec_ptr.id == 0) {
                const ILType* ptr_ty = il_type_ptr(left.type, REGION_LOCAL, true);
                vec_ptr = emit(ctx, il_build_alloc(REGION_LOCAL, left.type, ptr_ty, (ILValue){0}));
                emit_void(ctx, il_build_store(vec_ptr, left));
                if (!il_type_is_copy_mod(ctx->module, left.type)) {
                    mark_moved(ctx, left.id);
                }
            }
        }

        const ILType* usize_ty = il_type_usize();
        if (!usize_ty) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "Failed to get usize type");
            return (ILValue){0};
        }
        const ILType* usize_ptr_ty = il_type_ptr(usize_ty, get_region(vec_ptr.type), false);
        ILValue len_addr = emit(ctx, il_build_field_addr(vec_ptr, 1, usize_ptr_ty));
        ILValue len = emit(ctx, il_build_load(len_addr));
        emit_bounds_check(ctx, index, len);

        const ILType* elem_ptr_ty = il_type_ptr(elem_ty, get_region(vec_ptr.type), is_mut_borrow(vec_ptr.type));
        const ILType* data_ptr_ty = il_type_ptr(elem_ptr_ty, get_region(vec_ptr.type), false);
        ILValue data_addr = emit(ctx, il_build_field_addr(vec_ptr, 0, data_ptr_ty));
        ILValue data = emit(ctx, il_build_load(data_addr));
        ILInstruction* elem_addr_instr = il_build_elem_addr(data, index, elem_ptr_ty);
        if (elem_addr_instr) {
            ILValue elem_addr = emit(ctx, elem_addr_instr);
            if (allow_lvalue && index_yields_address(elem_ty)) {
                return (ILValue){ .id = elem_addr.id, .type = elem_ty };
            }
            ILInstruction* load = il_build_load(elem_addr);
            if (load) return emit(ctx, load);
        }
        emit_diag_at(ctx, DIAG_ERROR, expr->left, "Failed to build vec element load");
        return (ILValue){0};
    } else if (left.type->kind == IL_TY_PTR) {
        // Raw pointer indexing
        const ILType* elem_ptr_ty = il_type_ptr(left.type->as.ptr.pointee, left.type->as.ptr.region_id, left.type->as.ptr.is_mut);
        ILInstruction* elem_addr_instr = il_build_elem_addr(left, index, elem_ptr_ty);
        if (elem_addr_instr) {
            ILValue elem_addr = emit(ctx, elem_addr_instr);
            ILInstruction* load = il_build_load(elem_addr);
            if (load) return emit(ctx, load);
        }
        emit_diag_at(ctx, DIAG_ERROR, expr->left, "Failed to build pointer index load");
        return (ILValue){0};
    }

    emit_diag_at(ctx, DIAG_ERROR, expr->left, "Cannot index into type '%s'", il_type_kind_str(left.type->kind));
    return (ILValue){0};
}

static ILValue lower_unary(LowerContext* ctx, const UnaryExpr* expr, const ILType* expected_type) {
    ILInstruction* instr = NULL;
    if (strcmp(expr->op, "*") == 0) {
        ILValue operand = lower_expression_internal(ctx, expr->expr, NULL, false, (ILValue){0}, false, false);
        if (!operand.type) return (ILValue){0};
        // Bug 3 fix: if expected type is Ptr<T> and operand is Box<T> or Ptr<T> with
        // the same inner type, reinterpret the pointer instead of loading the value.
        if (expected_type && expected_type->kind == IL_TY_PTR &&
            (operand.type->kind == IL_TY_BOX || operand.type->kind == IL_TY_PTR)) {
            const ILType* inner = (operand.type->kind == IL_TY_BOX)
                ? operand.type->as.box.pointee
                : operand.type->as.ptr.pointee;
            if (il_type_eq(inner, expected_type->as.ptr.pointee)) {
                ILValue res;
                res.id = operand.id;
                uint32_t region_id = expected_type->as.ptr.region_id;
                if (region_id == 0) region_id = REGION_LOCAL; // Default to local if anonymous
                res.type = il_type_ptr(inner, region_id, expected_type->as.ptr.is_mut);
                return res;
            }
        }
        if (operand.type->kind == IL_TY_PTR || operand.type->kind == IL_TY_BOX) {
            instr = il_build_load(operand);
        }
        if (instr) {
            ILValue res = emit(ctx, instr);
            return res;
        }
    } else if (strcmp(expr->op, "&") == 0) {
        ILValue addr = lower_lvalue(ctx, expr->expr, expr->is_mut);
        if (addr.id == 0) {
            emit_diag_at(ctx, DIAG_ERROR, expr->expr, "Cannot take address of this expression");
            return (ILValue){0};
        }

        if (expected_type && expected_type->kind == IL_TY_PTR) {
            // Check if we took the address of a Box or Ptr, and we actually want to borrow its pointee.
            // addr is a Ptr<Box<T>> or Ptr<Ptr<T>>.
            const ILType* t = addr.type;
            if (t && t->kind == IL_TY_PTR) {
                const ILType* pointee = t->as.ptr.pointee;
                if (pointee->kind == IL_TY_BOX) {
                    const ILType* inner = pointee->as.box.pointee;
                    // id:1000 fix: ONLY auto-deref if the target expected type is NOT a double pointer.
                    // If target is Ptr<Ptr<T>>, then the user likely wanted &box.
                    // If target is Ptr<T>, then they wanted a borrow of the box's content.
                    bool target_is_double_ptr = expected_type->as.ptr.pointee->kind == IL_TY_PTR || expected_type->as.ptr.pointee->kind == IL_TY_BOX;
                    
                    if (il_type_eq(inner, expected_type->as.ptr.pointee) && !target_is_double_ptr) {
                        ILInstruction* load = il_build_load(addr);
                        if (load && load->result_type) {
                            const ILType* box_ty = load->result_type;
                            const ILType* ptr_ty = il_type_ptr(box_ty->as.box.pointee, box_ty->as.box.region_id, box_ty->as.box.is_mut);
                            load->result_type = ptr_ty;
                            
                            if (load->result_type && load->result_type->kind == IL_TY_PTR && addr.id != 0) {
                                load->result_type = il_type_ptr(load->result_type->as.ptr.pointee, addr.id, expr->is_mut);
                            }

                            return emit(ctx, load);
                        }
                    }
                }
            }
        }
        
        // Use addr directly, but ensure its type has the correct mutability.
        if (addr.type && addr.type->kind == IL_TY_PTR) {
            uint32_t rid = addr.type->as.ptr.region_id;
            // Link to the SSA ID of the owner if it's a local allocation or parameter.
            if (rid == REGION_LOCAL || rid == 0) {
                rid = addr.id;
            }
            const ILType* borrow_ty = il_type_ptr(addr.type->as.ptr.pointee, rid, expr->is_mut);
            // Always emit a bitcast to give the borrow its own SSA ID.
            // This ensures that dropping the borrow does not mark the owner as moved.
            ILInstruction* cast = il_build_bitcast(addr, borrow_ty);
            if (cast) return emit(ctx, cast);
            return addr;
        }
        return addr;
    } else if (strcmp(expr->op, "-") == 0) {
        ILValue operand = lower_expression(ctx, expr->expr, NULL, (ILValue){0});
        if (!operand.type) return (ILValue){0};
        
        if (!is_numeric_type(operand.type)) {
            emit_diag_at(ctx, DIAG_ERROR, expr->expr, "Operator '-' cannot be applied to type '%s'", il_type_kind_str(operand.type->kind));
            return (ILValue){0};
        }

        ILValue zero;
        if (operand.type->kind == IL_TY_F32 || operand.type->kind == IL_TY_F64) {
            zero = emit(ctx, il_build_fconst(0.0, operand.type));
        } else {
            zero = emit(ctx, il_build_const(0, operand.type));
        }
        instr = il_build_sub(zero, operand);
    } else if (strcmp(expr->op, "!") == 0) {
        ILValue operand = lower_expression(ctx, expr->expr, NULL, (ILValue){0});
        if (!operand.type) return (ILValue){0};

        if (!is_numeric_type(operand.type)) {
            emit_diag_at(ctx, DIAG_ERROR, expr->expr, "Operator '!' cannot be applied to type '%s'", il_type_kind_str(operand.type->kind));
            return (ILValue){0};
        }

        if (operand.type->kind == IL_TY_BOOL) {
            // Logical NOT for booleans: !true = false, !false = true → XOR with 1
            ILValue one = emit(ctx, il_build_const(1, operand.type));
            instr = il_build_xor(operand, one);
        } else {
            // Bitwise NOT for integer types: flip all bits → XOR with all-ones
            ILValue all_ones = emit(ctx, il_build_const((uint64_t)-1, operand.type));
            instr = il_build_xor(operand, all_ones);
        }
    }
    
    if (instr) {
        ILValue res = emit(ctx, instr);
        return res;
    }
    
    return (ILValue){0};
}

bool block_ends_with_jump_to(ILBasicBlock* block, uint32_t target_id) {
    if (!block || block->instr_count == 0) return false;
    const ILInstruction* last = block->instructions[block->instr_count - 1];
    if (last->opcode == IL_OP_BRANCH) {
        if (last->operands.branch.then_block_id == target_id || 
            last->operands.branch.else_block_id == target_id) {
            return true;
        }
    } else if (last->opcode == IL_OP_JUMP) {
        if (last->operands.jump.target_block_id == target_id) {
            return true;
        }
    }
    return false;
}

/* == and != lower to one word comparison: meaningful for scalars, pointers and fieldless enums
 * (compared by discriminant), but on any other aggregate it would compare an address or only the
 * tag. Mirrors check_equality_operands in src/lower_zir/utils.zrl. */
static bool is_word_comparable(LowerContext* ctx, const ILType* ty) {
    if (!ty) return true;
    if (ty->kind == IL_TY_SUM) {
        const ILTypeDef* def = il_mod_get_type_def(ctx->module, ty->as.struct_sum.type_def_id);
        if (!def) return false;
        for (uint32_t i = 0; i < def->field_count; i++) {
            const ILType* payload = def->fields[i].type;
            if (payload && payload->kind != IL_TY_UNIT) return false;
        }
        return true;
    }
    return !is_aggregate_type_layout(ty);
}

static ILValue lower_logical(LowerContext* ctx, const BinaryExpr* binary) {
    bool is_and = strcmp(binary->op, "&&") == 0;

    ILValue left = lower_expression(ctx, binary->left, il_type_bool(), (ILValue){0});
    ILBasicBlock* first_blk = ctx->current_block;
    ILBasicBlock* second_blk = create_block(ctx);
    ILBasicBlock* join_blk = create_block(ctx);

    ILInstruction* br;
    if (is_and) {
        br = il_build_branch(left, second_blk->id, join_blk->id);
    } else {
        br = il_build_branch(left, join_blk->id, second_blk->id);
    }
    if (!br) {
        if (ctx->report && ctx->report->has_errors) return (ILValue){0};
        emit_diag_at(ctx, DIAG_ERROR, binary->left, "Failed to build branch instruction for logical operator");
        return (ILValue){0};
    }
    il_block_add_instr(first_blk, br);
    il_block_add_successor(first_blk, second_blk);
    il_block_add_successor(first_blk, join_blk);

    ctx->current_block = second_blk;
    ILValue right = lower_expression(ctx, binary->right, il_type_bool(), (ILValue){0});
    
    ILBasicBlock* second_exit_blk = ctx->current_block;
    add_jump(ctx, join_blk);
    
    ctx->current_block = join_blk;
    const ILType* bool_ty = il_type_bool();
    if (!bool_ty) abort();
    
    ILPhiIncoming incoming[2];
    uint32_t num_incoming = 0;
    if (block_ends_with_jump_to(first_blk, join_blk->id)) {
        incoming[num_incoming].block_id = first_blk->id;
        incoming[num_incoming].value_id = left.id;
        num_incoming++;
    }
    if (block_ends_with_jump_to(second_exit_blk, join_blk->id)) {
        incoming[num_incoming].block_id = second_exit_blk->id;
        incoming[num_incoming].value_id = right.id;
        num_incoming++;
    }

    if (num_incoming == 0) {
        return (ILValue){0};
    } else if (num_incoming == 1) {
        ILValue res = { .id = incoming[0].value_id, .type = bool_ty };
        return res;
    }
    
    ILInstruction* phi = il_build_phi(incoming, num_incoming, bool_ty);
    if (phi) {
        ILValue res = emit(ctx, phi);
        return res;
    }
    
    return (ILValue){0};
}

typedef ILInstruction* (*ArithFn)(LowerContext*, ILValue, ILValue);
typedef ILInstruction* (*CmpFn)(ILValue, ILValue, const ILType*);

static ILInstruction* build_add(LowerContext* ctx, ILValue l, ILValue r) {
    if (l.type && (l.type->kind == IL_TY_F32 || l.type->kind == IL_TY_F64)) return il_build_add(l, r);
    if (l.type && l.type->kind == IL_TY_PTR) {
        ILValue idx = ensure_usize(ctx, r);
        return il_build_elem_addr(l, idx, l.type);
    }
    if (r.type && r.type->kind == IL_TY_PTR) {
        ILValue idx = ensure_usize(ctx, l);
        return il_build_elem_addr(r, idx, r.type);
    }
    if (ctx->release_mode) return il_build_wrapping_add(l, r);
    return il_build_checked_add(l, r, NULL);
}

static ILInstruction* build_sub(LowerContext* ctx, ILValue l, ILValue r) {
    if (l.type && (l.type->kind == IL_TY_F32 || l.type->kind == IL_TY_F64)) return il_build_sub(l, r);
    if (l.type && l.type->kind == IL_TY_PTR) {
        if (r.type && r.type->kind == IL_TY_PTR) {
            // ptr - ptr -> isize
            const ILType* isize_ty = il_type_isize();
            ILValue diff = emit(ctx, il_build_sub(l, r));
            ILValue elem_size = emit(ctx, il_build_const(il_type_size(ctx->module, l.type->as.ptr.pointee), isize_ty));
            return il_build_div(diff, elem_size);
        }
        // Pointer subtraction (ptr - offset): ptr + (-offset)
        ILValue zero = emit(ctx, il_build_const(0, r.type));
        ILValue neg_r = emit(ctx, il_build_wrapping_sub(zero, r));
        ILValue idx = ensure_usize(ctx, neg_r);
        return il_build_elem_addr(l, idx, l.type);
    }
    if (ctx->release_mode) return il_build_wrapping_sub(l, r);
    return il_build_checked_sub(l, r, NULL);
}

static ILInstruction* build_mul(LowerContext* ctx, ILValue l, ILValue r) {
    if (l.type && (l.type->kind == IL_TY_F32 || l.type->kind == IL_TY_F64)) return il_build_mul(l, r);
    if (ctx->release_mode) return il_build_wrapping_mul(l, r);
    return il_build_checked_mul(l, r, NULL);
}

static ILInstruction* wrap_add(LowerContext* ctx, ILValue l, ILValue r) { (void)ctx; return il_build_wrapping_add(l, r); }
static ILInstruction* wrap_sub(LowerContext* ctx, ILValue l, ILValue r) { (void)ctx; return il_build_wrapping_sub(l, r); }
static ILInstruction* wrap_mul(LowerContext* ctx, ILValue l, ILValue r) { (void)ctx; return il_build_wrapping_mul(l, r); }
static ILInstruction* build_div(LowerContext* ctx, ILValue l, ILValue r) { (void)ctx; return il_build_div(l, r); }
static ILInstruction* build_rem(LowerContext* ctx, ILValue l, ILValue r) { (void)ctx; return il_build_rem(l, r); }
static ILInstruction* build_and(LowerContext* ctx, ILValue l, ILValue r) { (void)ctx; return il_build_and(l, r); }
static ILInstruction* build_or(LowerContext* ctx, ILValue l, ILValue r) { (void)ctx; return il_build_or(l, r); }
static ILInstruction* build_xor(LowerContext* ctx, ILValue l, ILValue r) { (void)ctx; return il_build_xor(l, r); }
static ILInstruction* build_shl(LowerContext* ctx, ILValue l, ILValue r) { (void)ctx; return il_build_shl(l, r); }
static ILInstruction* build_shr(LowerContext* ctx, ILValue l, ILValue r) { (void)ctx; return il_build_shr(l, r); }

static const struct { const char* op; ArithFn fn; } arith_ops[] = {
    { "+",  build_add },
    { "-",  build_sub },
    { "*",  build_mul },
    { "+%", wrap_add },
    { "-%", wrap_sub },
    { "*%", wrap_mul },
    { "/",  build_div },
    { "%",  build_rem },
    { "&",  build_and },
    { "|",  build_or  },
    { "^",  build_xor },
    { "<<", build_shl },
    { ">>", build_shr },
};

static const struct { const char* op; CmpFn fn; } cmp_ops[] = {
    { "<",  il_build_cmp_lt },
    { "<=", il_build_cmp_le },
    { ">",  il_build_cmp_gt },
    { ">=", il_build_cmp_ge },
    { "==", il_build_cmp_eq },
    { "!=", il_build_cmp_ne },
};

static ILValue lower_slice_comparison(LowerContext* ctx, const char* op, ILValue left, ILValue right) {
    const ILType* usize_ty = il_type_usize();
    const ILType* bool_ty = il_type_bool();
    const ILType* i32_ty = il_type_i32();
    const ILType* unit_ptr_ty = il_type_ptr(il_type_unit(), REGION_STATIC, false);

    // 1. Compare lengths
    ILInstruction* left_len_instr = il_build_slice_len(left, usize_ty);
    if (!left_len_instr) return (ILValue){0};
    ILValue left_len = emit(ctx, left_len_instr);

    ILInstruction* right_len_instr = il_build_slice_len(right, usize_ty);
    if (!right_len_instr) return (ILValue){0};
    ILValue right_len = emit(ctx, right_len_instr);

    ILInstruction* len_eq_instr = il_build_cmp_eq(left_len, right_len, bool_ty);
    if (!len_eq_instr) return (ILValue){0};
    ILValue len_eq = emit(ctx, len_eq_instr);

    ILBasicBlock* len_match_blk = create_block(ctx);
    ILBasicBlock* false_blk = create_block(ctx);
    ILBasicBlock* join_blk = create_block(ctx);

    emit_void(ctx, il_build_branch(len_eq, len_match_blk->id, false_blk->id));
    il_block_add_successor(ctx->current_block, len_match_blk);
    il_block_add_successor(ctx->current_block, false_blk);

    // 2. If lengths match, call memcmp
    ctx->current_block = len_match_blk;
    ILInstruction* left_data_instr = il_build_slice_data(left, unit_ptr_ty);
    if (!left_data_instr) { add_jump(ctx, join_blk); return (ILValue){0}; }
    ILValue left_data = emit(ctx, left_data_instr);

    ILInstruction* right_data_instr = il_build_slice_data(right, unit_ptr_ty);
    if (!right_data_instr) { add_jump(ctx, join_blk); return (ILValue){0}; }
    ILValue right_data = emit(ctx, right_data_instr);

    ILFunction* memcmp_fn = (ILFunction*)il_mod_get_func_by_name(ctx->module, "memcmp");
    if (!memcmp_fn) {
        uint32_t max_id = 0;
        for (uint32_t i = 0; i < ctx->module->function_count; i++) {
            if (ctx->module->functions[i]->id > max_id) max_id = ctx->module->functions[i]->id;
        }
        memcmp_fn = il_func_create_synthetic(max_id + 1, "memcmp", i32_ty);
        memcmp_fn->is_extern = true;
        il_func_add_param(memcmp_fn, unit_ptr_ty);
        il_func_add_param(memcmp_fn, unit_ptr_ty);
        il_func_add_param(memcmp_fn, usize_ty);
        il_mod_add_func(ctx->module, memcmp_fn);
    }

    ILValue args[3] = {
        { .id = left_data.id, .type = unit_ptr_ty },
        { .id = right_data.id, .type = unit_ptr_ty },
        { .id = left_len.id, .type = usize_ty }
    };
    ILInstruction* memcmp_call = il_build_call(memcmp_fn->id, args, 3, i32_ty);
    if (!memcmp_call) { add_jump(ctx, join_blk); return (ILValue){0}; }
    ILValue memcmp_res = emit(ctx, memcmp_call);

    ILInstruction* zero_instr = il_build_const(0, i32_ty);
    if (!zero_instr) { add_jump(ctx, join_blk); return (ILValue){0}; }
    ILValue zero = emit(ctx, zero_instr);

    ILInstruction* cmp_res_instr = il_build_cmp_eq(memcmp_res, zero, bool_ty);
    if (!cmp_res_instr) { add_jump(ctx, join_blk); return (ILValue){0}; }
    ILValue cmp_res = emit(ctx, cmp_res_instr);
    
    const ILBasicBlock* memcmp_exit_blk = ctx->current_block;
    add_jump(ctx, join_blk);

    // 3. False branch (lengths mismatch)
    ctx->current_block = false_blk;
    ILValue const_false = emit(ctx, il_build_const(0, bool_ty));
    add_jump(ctx, join_blk);

    // 4. Join and PHI
    ctx->current_block = join_blk;
    ILPhiIncoming incoming[2] = {
        { .block_id = memcmp_exit_blk->id, .value_id = cmp_res.id },
        { .block_id = false_blk->id, .value_id = const_false.id }
    };
    ILValue final_bool = emit(ctx, il_build_phi(incoming, 2, bool_ty));

    if (strcmp(op, "!=") == 0) {
        ILValue one = emit(ctx, il_build_const(1, bool_ty));
        final_bool = emit(ctx, il_build_xor(final_bool, one));
    }

    return final_bool;
}


static ILValue lower_assignment(LowerContext* ctx, const Expression* expr, const char* base_op) {
    const BinaryExpr* binary = &expr->as.binary;
    const ILType* expected_type = NULL;
    ILValue left_arr = {0};
    ILValue index = {0};
    bool needs_store = true;

    // 1. Determine expected type from LHS. For `base[i] = v` the base is lowered exactly once,
    //    here, and as an address when it is a place: lowering an array-typed place as a value
    //    yields a copy, so the store would land in a temporary (s.data[i] = v through a pointer).
    if (binary->left->kind == EXPR_INDEX) {
        const Expression* base = binary->left->as.index_expr.left;
        bool base_is_place = base->kind == EXPR_VAR || base->kind == EXPR_MEMBER || base->kind == EXPR_INDEX ||
                             (base->kind == EXPR_UNARY && strcmp(base->as.unary.op, "*") == 0);
        const ILType* base_ty = base_is_place ? guess_type(ctx, base) : NULL;
        ILValue la = (base_ty && base_ty->kind == IL_TY_ARRAY)
            ? lower_lvalue(ctx, base, true)
            : lower_expression_internal(ctx, base, NULL, false, (ILValue){0}, true, false);
        left_arr = la;
        if (la.type) {
            const ILType* vec_elem = NULL;
            if (is_vec_type(la.type, &vec_elem)) expected_type = vec_elem;
            else if (la.type->kind == IL_TY_ARRAY) expected_type = la.type->as.array.element;
            else if (la.type->kind == IL_TY_SLICE) expected_type = la.type->as.slice.element;
            else if (la.type->kind == IL_TY_PTR && la.type->as.ptr.pointee->kind == IL_TY_ARRAY) expected_type = la.type->as.ptr.pointee->as.array.element;
            else if (la.type->kind == IL_TY_PTR && la.type->as.ptr.pointee->kind == IL_TY_SLICE) expected_type = la.type->as.ptr.pointee->as.slice.element;
            else if (la.type->kind == IL_TY_PTR) expected_type = la.type->as.ptr.pointee;
        }
    } else if (binary->left->kind == EXPR_MEMBER) {
        expected_type = guess_type(ctx, binary->left);
    } else if (binary->left->kind == EXPR_UNARY && strcmp(binary->left->as.unary.op, "*") == 0) {
        expected_type = guess_type(ctx, binary->left);
    } else if (binary->left->kind == EXPR_VAR) {
        const Symbol* sym = symbol_lookup_ctx(ctx, binary->left->as.var.name);
        if (sym) {
            if (sym->is_lvalue && sym->value.type && sym->value.type->kind == IL_TY_PTR) {
                expected_type = sym->value.type->as.ptr.pointee;
            } else {
                expected_type = sym->value.type;
            }
            if (!sym->is_lvalue) needs_store = false;
        }
    }

    // 2. Evaluate components of complex LHS (like array index)
    if (binary->left->kind == EXPR_INDEX) {
        index = lower_expression(ctx, binary->left->as.index_expr.index, NULL, (ILValue){0});
        index = ensure_usize(ctx, index);
    }

    // 3. Evaluate LHS address if needed
    ILValue lhs_addr = {0};
    if (needs_store && binary->left->kind != EXPR_INDEX) {
        lhs_addr = lower_lvalue(ctx, binary->left, true);
    }

    // 4. Evaluate RHS. If aggregate and we have an LHS address, use it as dest_ptr.
    ILValue dest_ptr = (ILValue){0};
    if (expected_type && is_aggregate_type_layout(expected_type) && lhs_addr.id != 0 && !base_op) {
        dest_ptr = lhs_addr;
    }
    ILValue right = lower_expression_move(ctx, binary->right, expected_type, dest_ptr);
    if (!right.type) {
        return (ILValue){0};
    }

    if (expected_type) {
        right = ensure_assignable(ctx, right, expected_type);
    }

    // 5. Perform the store/assignment
    if (binary->left->kind == EXPR_INDEX) {
        if (!left_arr.type || !index.type) {
            return (ILValue){0};
        }

        const ILType* usize_ty = il_type_usize();
        if (!usize_ty) return (ILValue){0};

        if (left_arr.type->kind == IL_TY_ARRAY) {
            ILValue len = emit(ctx, il_build_const(left_arr.type->as.array.length, usize_ty));
            emit_bounds_check(ctx, index, len);            
            ILValue new_val = right;
            if (base_op) {
                ILValue old_val = emit(ctx, il_build_array_load(left_arr, index, left_arr.type->as.array.element));
                ILInstruction* instr = NULL;
                for (size_t i = 0; i < sizeof(arith_ops) / sizeof(arith_ops[0]); i++) {
                    if (strcmp(base_op, arith_ops[i].op) == 0) {
                        instr = arith_ops[i].fn(ctx, old_val, right);
                        break;
                    }
                }
                if (instr) new_val = emit(ctx, instr);
            }

            emit_void(ctx, il_build_array_store(left_arr, index, new_val));
            return (ILValue){ .id = 0, .type = il_type_unit() };

        } else if (left_arr.type->kind == IL_TY_SLICE || (left_arr.type->kind == IL_TY_PTR && left_arr.type->as.ptr.pointee->kind == IL_TY_SLICE)) {
            ILValue len = emit(ctx, il_build_slice_len(left_arr, usize_ty));
            emit_bounds_check(ctx, index, len);

            ILValue new_val = right;
            if (base_op) {
                ILValue old_val = emit(ctx, il_build_slice_load(left_arr, index));
                ILInstruction* instr = NULL;
                for (size_t i = 0; i < sizeof(arith_ops) / sizeof(arith_ops[0]); i++) {
                    if (strcmp(base_op, arith_ops[i].op) == 0) {
                        instr = arith_ops[i].fn(ctx, old_val, right);
                        break;
                    }
                }
                if (instr) new_val = emit(ctx, instr);
            }

            emit_void(ctx, il_build_slice_store(left_arr, index, new_val));
            return (ILValue){ .id = 0, .type = il_type_unit() };

        } else if (left_arr.type->kind == IL_TY_PTR && left_arr.type->as.ptr.pointee->kind == IL_TY_ARRAY) {
            ILValue len = emit(ctx, il_build_const(left_arr.type->as.ptr.pointee->as.array.length, usize_ty));
            emit_bounds_check(ctx, index, len);

            ILValue new_val = right;
            if (base_op) {
                ILValue old_val = emit(ctx, il_build_array_load(left_arr, index, left_arr.type->as.ptr.pointee->as.array.element));
                ILInstruction* instr = NULL;
                for (size_t i = 0; i < sizeof(arith_ops) / sizeof(arith_ops[0]); i++) {
                    if (strcmp(base_op, arith_ops[i].op) == 0) {
                        instr = arith_ops[i].fn(ctx, old_val, right);
                        break;
                    }
                }
                if (instr) new_val = emit(ctx, instr);
            }

            emit_void(ctx, il_build_array_store(left_arr, index, new_val));
            return (ILValue){ .id = 0, .type = il_type_unit() };
        } else if (is_vec_type(left_arr.type, NULL)) {
            const ILType* vec_elem = get_vec_element_type(ctx->module, left_arr.type);
            ILValue vec_ptr = left_arr;
            if (left_arr.type->kind == IL_TY_STRUCT) {
                vec_ptr = lower_lvalue(ctx, binary->left->as.index_expr.left, true);
            }
            const ILType* usize_ptr_ty = il_type_ptr(usize_ty, get_region(vec_ptr.type), false);
            ILValue len_addr = emit(ctx, il_build_field_addr(vec_ptr, 1, usize_ptr_ty));
            ILValue len = emit(ctx, il_build_load(len_addr));
            emit_bounds_check(ctx, index, len);

            const ILType* elem_ptr_ty = il_type_ptr(vec_elem, get_region(vec_ptr.type), true);
            const ILType* data_ptr_ty = il_type_ptr(elem_ptr_ty, get_region(vec_ptr.type), false);
            ILValue data_addr = emit(ctx, il_build_field_addr(vec_ptr, 0, data_ptr_ty));
            ILValue data = emit(ctx, il_build_load(data_addr));
            ILValue elem_addr = emit(ctx, il_build_elem_addr(data, index, elem_ptr_ty));

            ILValue new_val = right;
            if (base_op) {
                ILValue old_val = emit(ctx, il_build_load(elem_addr));
                ILInstruction* instr = NULL;
                for (size_t i = 0; i < sizeof(arith_ops) / sizeof(arith_ops[0]); i++) {
                    if (strcmp(base_op, arith_ops[i].op) == 0) {
                        instr = arith_ops[i].fn(ctx, old_val, right);
                        break;
                    }
                }
                if (instr) new_val = emit(ctx, instr);
            }

            emit_void(ctx, il_build_store(elem_addr, new_val));
            return (ILValue){ .id = 0, .type = il_type_unit() };
        } else if (left_arr.type->kind == IL_TY_PTR) {
            // Raw pointer indexing
            const ILType* elem_ptr_ty = il_type_ptr(left_arr.type->as.ptr.pointee, left_arr.type->as.ptr.region_id, left_arr.type->as.ptr.is_mut);
            ILValue elem_addr = emit(ctx, il_build_elem_addr(left_arr, index, elem_ptr_ty));

            ILValue new_val = right;
            if (base_op) {
                ILValue old_val = emit(ctx, il_build_load(elem_addr));
                ILInstruction* instr = NULL;
                for (size_t i = 0; i < sizeof(arith_ops) / sizeof(arith_ops[0]); i++) {
                    if (strcmp(base_op, arith_ops[i].op) == 0) {
                        instr = arith_ops[i].fn(ctx, old_val, right);
                        break;
                    }
                }
                if (instr) new_val = emit(ctx, instr);
            }

            emit_void(ctx, il_build_store(elem_addr, new_val));
            return (ILValue){ .id = 0, .type = il_type_unit() };
        }
        return (ILValue){0};
    }

    if (lhs_addr.id != 0) {
        ILValue new_val = right;
        if (base_op) {
            ILValue old_val = emit(ctx, il_build_load(lhs_addr));
            ILInstruction* instr = NULL;
            for (size_t i = 0; i < sizeof(arith_ops) / sizeof(arith_ops[0]); i++) {
                if (strcmp(base_op, arith_ops[i].op) == 0) {
                    instr = arith_ops[i].fn(ctx, old_val, right);
                    break;
                }
            }
            if (instr) new_val = emit(ctx, instr);
        }

        if (new_val.id != lhs_addr.id) {
            ILInstruction* store = il_build_store(lhs_addr, new_val);
            if (!store) {
                emit_diag_at(ctx, DIAG_ERROR, expr, "Internal error: IL instruction construction failed");
                return (ILValue){0};
            }
            emit_void(ctx, store);
            if (new_val.type && !il_type_is_copy_mod(ctx->module, new_val.type)) {
                mark_moved(ctx, new_val.id);
            }
        }
        return (ILValue){ .id = 0, .type = il_type_unit() };
    }

    if (!needs_store && binary->left->kind == EXPR_VAR) {
        ILValue new_val = right;
        if (base_op) {
            ILValue old_val = lower_expression(ctx, binary->left, NULL, (ILValue){0});
            ILInstruction* instr = NULL;
            for (size_t i = 0; i < sizeof(arith_ops) / sizeof(arith_ops[0]); i++) {
                if (strcmp(base_op, arith_ops[i].op) == 0) {
                    instr = arith_ops[i].fn(ctx, old_val, right);
                    break;
                }
            }
            if (instr) new_val = emit(ctx, instr);
        }
        symbol_add_ctx(ctx, binary->left->as.var.name, (ILValue){ .id = new_val.id, .type = new_val.type }, false);
        return (ILValue){ .id = 0, .type = il_type_unit() };
    }

    return (ILValue){0};
}

static ILValue lower_binary(LowerContext* ctx, const Expression* expr) {
    const BinaryExpr* binary = &expr->as.binary;
    if (strcmp(binary->op, "&&") == 0 || strcmp(binary->op, "||") == 0) {
        return lower_logical(ctx, binary);
    }

    bool is_assign = false;
    const char* base_op = NULL;
    char bop[16] = {0};
    if (strcmp(binary->op, "=") == 0) {
        is_assign = true;
    } else {
        size_t len = strlen(binary->op);
        if (len > 1 && len < sizeof(bop) && binary->op[len - 1] == '=') {
            if (strcmp(binary->op, "==") != 0 && strcmp(binary->op, "!=") != 0 && strcmp(binary->op, "<=") != 0 && strcmp(binary->op, ">=") != 0) {
                is_assign = true;
                memcpy(bop, binary->op, len - 1);
                bop[len - 1] = '\0';
                base_op = bop;
            }
        }
    }

    if (is_assign) {
        return lower_assignment(ctx, expr, base_op);
    }


    ILValue left = lower_expression(ctx, binary->left, NULL, (ILValue){0});
    ILValue right = lower_expression(ctx, binary->right, left.type, (ILValue){0});
    if (left.type && right.type) {
        ILValue assigned = ensure_assignable(ctx, right, left.type);
        right = assigned;
    }

    if (left.type && left.type->kind == IL_TY_SLICE && (strcmp(binary->op, "==") == 0 || strcmp(binary->op, "!=") == 0)) {
        ILValue res = lower_slice_comparison(ctx, binary->op, left, right);
        return res;
    }

    if ((strcmp(binary->op, "==") == 0 || strcmp(binary->op, "!=") == 0) &&
        (!is_word_comparable(ctx, left.type) || !is_word_comparable(ctx, right.type))) {
        emit_diag_at(ctx, DIAG_ERROR, binary->left,
            "cannot compare structs, tuples, arrays, slices or payload-carrying enums with == or != (match on them or compare fields instead)");
        return (ILValue){0};
    }

    if (left.type && left.type->kind == IL_TY_SUM &&
        right.type && right.type->kind == IL_TY_SUM &&
        (strcmp(binary->op, "==") == 0 || strcmp(binary->op, "!=") == 0)) {
        ILValue left_ptr = promote_to_lvalue(ctx, left);
        ILValue right_ptr = promote_to_lvalue(ctx, right);
        const ILType* u32_ptr_ty = il_type_ptr(il_type_u32(), REGION_LOCAL, false);
        ILValue left_tag_ptr = emit(ctx, il_build_bitcast(left_ptr, u32_ptr_ty));
        ILValue right_tag_ptr = emit(ctx, il_build_bitcast(right_ptr, u32_ptr_ty));
        ILValue left_tag = emit(ctx, il_build_load(left_tag_ptr));
        ILValue right_tag = emit(ctx, il_build_load(right_tag_ptr));
        const ILType* bool_ty = il_type_bool();
        ILInstruction* cmp = (strcmp(binary->op, "==") == 0)
            ? il_build_cmp_eq(left_tag, right_tag, bool_ty)
            : il_build_cmp_ne(left_tag, right_tag, bool_ty);
        return emit(ctx, cmp);
    }

    ILInstruction* instr = NULL;
    const ILType * bool_ty = il_type_bool();

    // Whether the operator is one we know at all, as opposed to one we know but could not build for
    // these operand types. Conflating the two made this diagnostic misleading: it reported
    // "Unsupported operator: *" for a multiply whose operands did not line up, and with no span it
    // printed at whatever location happened to be current.
    bool op_known = false;

    for (size_t i = 0; i < sizeof(arith_ops) / sizeof(arith_ops[0]); i++) {
        if (strcmp(binary->op, arith_ops[i].op) == 0) {
            op_known = true;
            instr = arith_ops[i].fn(ctx, left, right);
            break;
        }
    }
    if (!instr) {
        for (size_t i = 0; i < sizeof(cmp_ops) / sizeof(cmp_ops[0]); i++) {
            if (strcmp(binary->op, cmp_ops[i].op) == 0) {
                op_known = true;
                instr = cmp_ops[i].fn(left, right, bool_ty);
                break;
            }
        }
    }

    if (instr) {
        return emit(ctx, instr);
    }

    if (op_known) {
        char lt[128] = "<unknown>";
        char rt[128] = "<unknown>";
        if (left.type) il_type_print(left.type, lt, sizeof(lt));
        if (right.type) il_type_print(right.type, rt, sizeof(rt));
        emit_diag_at(ctx, DIAG_ERROR, expr, "operator `%s` is not defined for these operand types: %s %s %s",
                     binary->op, lt, binary->op, rt);
    } else {
        emit_diag_at(ctx, DIAG_ERROR, expr, "Unsupported operator: %s", binary->op);
    }
    return (ILValue){0};
}

static ILValue lower_box(LowerContext* ctx, const Expression* expr) {
    const Expression* inner = expr->as.box_expr.inner;
    
    ILValue allocator = {0};
    if (expr->as.box_expr.allocator) {
        allocator = lower_expression_internal(ctx, expr->as.box_expr.allocator, NULL, false, (ILValue){0}, false, false);
    }
    
    uint32_t region_id = REGION_HEAP;
    if (allocator.id != 0 && allocator.type) {
        if (allocator.type->kind == IL_TY_PTR) region_id = allocator.type->as.ptr.region_id;
        else if (allocator.type->kind == IL_TY_BOX) region_id = allocator.type->as.box.region_id;
        else region_id = allocator.id;
    }
    
    if (inner->kind == EXPR_STRUCT) {
        const ILTypeDef* def = find_type_def(ctx, inner->as.struct_expr.name);
        if (def) {
            const ILType* struct_ty = il_type_struct(def->name, def->id);
            if (!struct_ty) {
                return (ILValue){0};
            }
            
            const ILType* box_ty = il_type_box(struct_ty, region_id, true);
            ILInstruction* alloc = il_build_alloc(region_id, struct_ty, box_ty, allocator);
            ILValue ptr = emit(ctx, alloc);
            lower_struct_literal(ctx, &inner->as.struct_expr, ptr);


            return ptr;
            }
            }
    ILValue val = lower_expression_move(ctx, inner, NULL, (ILValue){0});
    if (!val.type) {
        return (ILValue){0};
    }
    
    const ILType* box_ty = il_type_box(val.type, region_id, true);
    
    // alloc region, T, Box<T>, allocator
    ILInstruction* alloc = il_build_alloc(region_id, val.type, box_ty, allocator);
    ILValue ptr = emit(ctx, alloc);
    
    // store value into the allocated box
    ILInstruction* store = il_build_store(ptr, val);
    emit_void(ctx, store);
    
    // If boxed value is non-copy, mark it as moved.
    if (!il_type_is_copy_mod(ctx->module, val.type)) {
        mark_moved(ctx, val.id);
    }
    
    return ptr;
}

static ILValue lower_array_literal(LowerContext* ctx, const Expression* expr, const ILType* expected_type) {
    const ILType* elem_type = NULL;
    if (expected_type) {
        if (expected_type->kind == IL_TY_ARRAY) {
            elem_type = expected_type->as.array.element;
        } else if (expected_type->kind == IL_TY_SLICE) {
            elem_type = expected_type->as.slice.element;
        }
    }
    
    uint32_t count = 0;
    ILValue* elements = NULL;

    if (expr->as.array_expr.fill_count) {
        if (expr->as.array_expr.fill_count->kind == EXPR_INT) {
            count = (uint32_t)expr->as.array_expr.fill_count->as.int_val;
        } else {
            diag_emit(ctx->report, DIAG_ERROR, (SourceLocation){.file_path = ctx->current_file, .line = expr->as.array_expr.fill_count->line, .col = expr->as.array_expr.fill_count->col}, "Array fill count must be a constant integer literal");
            return (ILValue){0};
        }
        
        if (count > 0) {
            ILValue val = lower_expression(ctx, expr->as.array_expr.elements[0], elem_type, (ILValue){0});
            if (!elem_type) elem_type = val.type;
            
            elements = calloc(count, sizeof(ILValue));
            if (!elements) return (ILValue){0};
            for (uint32_t i = 0; i < count; i++) {
                elements[i] = val;
            }
            
            // If the element is non-copy, we can only fill if count is 1 or it is somehow safe.
            // But usually [val; count] is for Copy types.
            if (count > 1 && val.type && !il_type_is_copy_mod(ctx->module, val.type)) {
                char tbuf[128];
                il_print_type(ctx->module, val.type, tbuf, sizeof(tbuf));
                diag_emit(ctx->report, DIAG_ERROR, (SourceLocation){.file_path = ctx->current_file, .line = expr->line, .col = expr->col}, "Cannot use [val; count] with non-Copy type '%s'", tbuf);
            }
        }
    } else {
        count = expr->as.array_expr.count;
        if (count > 0) {
            elements = calloc(count, sizeof(ILValue));
            if (!elements) return (ILValue){0};
            for (uint32_t i = 0; i < count; i++) {
                elements[i] = lower_expression(ctx, expr->as.array_expr.elements[i], elem_type, (ILValue){0});
                if (!elem_type && elements[i].type) {
                    elem_type = elements[i].type;
                }
            }
        }
    }

    if (!ctx || !ctx->current_block) {
        if (elements) free(elements);
        return (ILValue){ .id = 0, .type = il_type_never() };
    }

    const ILType* i32_ty = NULL;
    if (!elem_type) {
        i32_ty = il_type_i32();
        if (!i32_ty) {
            if (elements) {
                free(elements);
            }
            return (ILValue){0};
        }
        elem_type = i32_ty;
    }

    const ILType* array_type = il_type_array(elem_type, count);
    

    if (!array_type) {
        if (elements) {
            free(elements);
        }
        return (ILValue){0};
    }
    
    ILInstruction* instr = il_build_array_construct(elements, count, array_type);
    ILValue array_val = emit(ctx, instr);

    // If any element is non-copy, it was moved into the array.
    for (uint32_t i = 0; i < count; i++) {
        if (elements[i].type && !il_type_is_copy_mod(ctx->module, elements[i].type)) {
            mark_moved(ctx, elements[i].id);
        }
    }

    ILValue result;
    if (expected_type && expected_type->kind == IL_TY_SLICE) {
        const ILType* usize_ty = il_type_usize();
        if (!usize_ty) {
            if (elements) {
                free(elements);
            }
            return (ILValue){0};
        }
        ILValue len_val = emit(ctx, il_build_const(count, usize_ty));
        
        result = emit(ctx, il_build_slice_construct(array_val, len_val, expected_type));
    } else {
        result = array_val;
    }

    if (elements) {
        free(elements);
    }
    return result;
}

static ILValue lower_cast(LowerContext* ctx, const Expression* expr, const ILType* target_type) {
    SourceLocation cast_loc = { .file_path = ctx->current_file, .source = ctx->current_source, .line = (uint16_t)ctx->current_line, .col = (uint16_t)ctx->current_col, .offset = ctx->current_offset };
    const ILType* resolved_target = lower_type_with_loc(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, target_type, ctx->current_substs, cast_loc);

    // For explicit casts, we pass the target type as a hint only if it's a literal.
    // This ensures that `0 as u64` or `0 as *u8` gets the correct 64-bit size.
    // For variables or calls, we pass NULL to avoid premature type mismatches in lower_expression_internal.
    const ILType* hint = (expr->kind == EXPR_INT || expr->kind == EXPR_FLOAT) ? resolved_target : NULL;
    ILValue val = lower_expression_internal(ctx, expr, hint, false, (ILValue){0}, false, false);
    if (!val.type) {
        return (ILValue){0};
    }

    ILValue res;
    bool src_scalar = is_numeric_type(val.type) || is_pointer_type(ctx->module, val.type) || requires_pass_by_ref(ctx->module, val.type);
    bool tgt_scalar = is_numeric_type(resolved_target) || is_pointer_type(ctx->module, resolved_target) || requires_pass_by_ref(ctx->module, resolved_target);

    if (src_scalar && tgt_scalar) {
        // Explicit `as` cast between scalar types always uses a bitcast (reinterpret).
        if (il_type_eq(val.type, resolved_target)) {
            res = (ILValue){ .id = val.id, .type = resolved_target };
        } else {
            // Preserve region ID when casting between pointers
            if (is_pointer_type(ctx->module, resolved_target) && is_pointer_type(ctx->module, val.type)) {
                uint32_t rid = 0;
                if (val.type->kind == IL_TY_PTR) rid = val.type->as.ptr.region_id;
                else if (val.type->kind == IL_TY_BOX) rid = val.type->as.box.region_id;
                else if (val.type->kind == IL_TY_SLICE) rid = val.type->as.slice.region_id;

                // Preserve region ID when casting between pointers.
                if (rid != 0) {
                    if (resolved_target->kind == IL_TY_PTR) {
                        // Casting to a raw pointer: never propagate SSA borrow regions.
                        // Box→ptr or borrow-of-Box→ptr: use REGION_HEAP (box memory is heap-allocated).
                        // Raw pointers are Copy and must not be tracked as borrows.
                        uint32_t effective_rid = (val.type->kind == IL_TY_BOX || is_ssa_region(rid)) ? REGION_HEAP : rid;
                        if (resolved_target->as.ptr.region_id == REGION_STATIC || resolved_target->as.ptr.region_id == REGION_LOCAL || resolved_target->as.ptr.region_id == 0)
                            resolved_target = il_type_ptr(resolved_target->as.ptr.pointee, effective_rid, resolved_target->as.ptr.is_mut);
                    } else if (resolved_target->kind == IL_TY_BOX) {
                        if (resolved_target->as.box.region_id == REGION_STATIC || resolved_target->as.box.region_id == REGION_LOCAL || resolved_target->as.box.region_id == 0)
                            resolved_target = il_type_box(resolved_target->as.box.pointee, rid, resolved_target->as.box.is_mut);
                    } else if (resolved_target->kind == IL_TY_SLICE) {
                        if (resolved_target->as.slice.region_id == REGION_STATIC || resolved_target->as.slice.region_id == REGION_LOCAL || resolved_target->as.slice.region_id == 0)
                            resolved_target = il_type_slice(resolved_target->as.slice.element, rid, resolved_target->as.slice.is_mut);
                    }
                }
            }

            if (val.type->kind == IL_TY_BOX && resolved_target->kind == IL_TY_PTR) {
                mark_moved(ctx, val.id);
            }

            const ILType* actual_tgt = resolved_target;
            
            // If both sides are pass-by-reference aggregates/vars, they are actually pointers in IL.
            // Ensure the IL BITCAST instruction reflects this.
            if (requires_pass_by_ref(ctx->module, val.type) && requires_pass_by_ref(ctx->module, resolved_target)) {
                // If the source is already a pointer, we can bitcast it directly.
                // If it's not (which shouldn't happen for pass-by-ref args), we promote it.
                if (val.type->kind != IL_TY_PTR && val.type->kind != IL_TY_BOX) {
                    val = promote_to_lvalue(ctx, val);
                }
                actual_tgt = il_type_ptr(resolved_target, REGION_LOCAL, true);
            }

            ILInstruction* bitcast = il_build_bitcast(val, actual_tgt);
            res = emit(ctx, bitcast);
            res.type = resolved_target;
        }
    } else if (val.type->kind == IL_TY_SUM && is_numeric_type(resolved_target)) {
        // Casting an enum (sum type) to a numeric type: load the 32-bit tag.
        val = promote_to_lvalue(ctx, val);
        ILValue tag_ptr = emit(ctx, il_build_bitcast(val, il_type_ptr(il_type_u32(), REGION_LOCAL, false)));
        ILValue tag = emit(ctx, il_build_load(tag_ptr));
        res = ensure_assignable(ctx, tag, resolved_target);
    } else {
        res = ensure_assignable(ctx, val, resolved_target);
    }

    return res;
}

/* Lower the `?` (try) operator.
 * Desugars `expr?` into a variant_match: the Ok arm evaluates to the unwrapped
 * payload; the Err arm constructs a wrapped error and returns early. */
static ILValue lower_try_expr(LowerContext* ctx, const Expression* inner) {
    ILValue src = lower_expression(ctx, inner, NULL, (ILValue){0});
    if (!src.type) return (ILValue){0};

    il_type_fixup(ctx->module, src.type);
    src = promote_to_lvalue(ctx, src);

    const ILType* sum_ty = (src.type && src.type->kind == IL_TY_PTR) ? src.type->as.ptr.pointee : NULL;
    if (!sum_ty || sum_ty->kind != IL_TY_SUM) {
        return (ILValue){0};
    }

    const ILTypeDef* def = il_mod_get_type_def(ctx->module, sum_ty->as.struct_sum.type_def_id);
    if (!def || !def->is_sum || def->field_count < 2) {
        return (ILValue){0};
    }

    /* Find the Ok and Err variant indices by name */
    int ok_idx = -1, err_idx = -1;
    for (uint32_t i = 0; i < def->field_count; i++) {
        if (strcmp(def->fields[i].name, "Ok") == 0) ok_idx = (int)i;
        else if (err_idx < 0)                       err_idx = (int)i;
    }
    if (ok_idx < 0 || err_idx < 0) {
        return (ILValue){0};
    }

    ILBasicBlock* ok_blk  = create_block(ctx);
    ILBasicBlock* err_blk = create_block(ctx);
    ILBasicBlock* join_blk = create_block(ctx);

    /* Branch on variant */
    ILInstruction* match = il_build_variant_match(src, (uint32_t)ok_idx, ok_blk->id, err_blk->id);
    il_block_add_instr(ctx->current_block, match);
    il_block_add_successor(ctx->current_block, ok_blk);
    il_block_add_successor(ctx->current_block, err_blk);

    /* Ok arm: unwrap the payload, jump to join */
    ctx->current_block = ok_blk;
    const ILType* ok_ty = def->fields[ok_idx].type;
    ILInstruction* unwrap_ok = il_build_unwrap(src, ok_ty);
    if (!unwrap_ok) {  return (ILValue){0}; }
    ILValue ok_val = emit(ctx, unwrap_ok);
    add_jump(ctx, join_blk);

    /* Err arm: src is already a Result, return it directly to propagate the error */
    ctx->current_block = err_blk;
    uint32_t saved_cap = 0;
    bool* saved_state = save_moved_state(ctx, &saved_cap);
    run_all_defers(ctx, 0);
    emit_return(ctx, src);
    restore_moved_state(ctx, saved_state, saved_cap);
    ctx->current_block = NULL;

    /* Join block: phi merges only the Ok path (Err returns early) */
    ctx->current_block = join_blk;
    ILPhiIncoming incoming = { .block_id = ok_blk->id, .value_id = ok_val.id };
    
    const ILType* phi_ty = ok_val.type;
    ILInstruction* phi = il_build_phi(&incoming, 1, phi_ty);
    if (!phi) return (ILValue){0};
    return emit(ctx, phi);
}

static ILValue lower_return_expr(LowerContext* ctx, const Expression* inner) {
    const ILType* ret_ty = ctx->current_func->return_type;
    ILValue val;
    if (inner) {
        ILValue dest_ptr = {0};
        if (ctx->current_func->is_sret && ctx->sret_id != 0) {
            dest_ptr = (ILValue){ .id = ctx->sret_id, .type = il_type_ptr(ctx->current_func->sret_type, REGION_LOCAL, true) };
        }
        val = lower_expression(ctx, inner, ctx->current_func->is_sret ? ctx->current_func->sret_type : ret_ty, dest_ptr);
    } else {
        val = (ILValue){ .id = 0, .type = il_type_unit() };
    }
    
    run_all_defers(ctx, val.id);
    emit_return(ctx, val);
    
    // Setting current_block to NULL signals to the lowerer that following code in this block is unreachable.
    ctx->current_block = NULL;
    
    // Return a 'never' value so callers know this expression diverges.
    return (ILValue){ .id = 0, .type = il_type_never() };
}

ILValue resolve_capture(LowerContext* ctx, const Symbol* sym) {
    if (ctx->env_ptr.id == 0 || !sym->value.type) return (ILValue){0};

    // 1. Find or add to captures list
    Capture* cap = ctx->captures;
    uint32_t index = 0;
    while (cap) {
        if (strcmp(cap->name, sym->name) == 0) break;
        cap = cap->next;
        index++;
    }
    if (!cap) {
        cap = calloc(1, sizeof(Capture));
        if (!cap) return (ILValue){0};
        cap->name = strdup(sym->name);
        // We MUST use the original type from the symbol to correctly handle non-copy captures (like Box).
        // If the variable was promoted to the stack, its value in the symbol table is a pointer,
        // but we want to capture the value it points to if we're moving it into the closure.
        // Actually, the symbol table entry for a stack variable has sym->is_lvalue = true.
        // If it's an lvalue, we want the pointee type.
        if (sym->is_lvalue && sym->value.type && (sym->value.type->kind == IL_TY_PTR || sym->value.type->kind == IL_TY_BOX)) {
            cap->type = sym->value.type->as.ptr.pointee;
        } else {
            cap->type = sym->value.type;
        }
        cap->original_value = sym->value;
        cap->is_lvalue = sym->is_lvalue;
        Capture** p = &ctx->captures;
        while (*p) p = &((*p)->next);
        *p = cap;

        // Mark as moved in outer scope if not copy
        if (!il_type_is_copy_mod(ctx->module, cap->type)) {
            if (ctx->parent_ctx) {
                mark_moved(ctx->parent_ctx, sym->value.id);
            }
        }

        // Also add to the environment struct definition
        const ILType* struct_ty = ctx->env_ptr.type->as.ptr.pointee;
        ILTypeDef* env_def = il_mod_get_type_def(ctx->module, struct_ty->as.struct_sum.type_def_id);
        il_type_def_add_field(env_def, cap->name, cap->type);
    }

    // 2. Return address of field in environment
    // Field 0 is fn ptr, Field 1 is env ptr, so captures start at field 2.
    const ILType* field_ptr_ty = il_type_ptr(cap->type, ctx->env_ptr.id, false);
    ILInstruction* faddr_instr = il_build_field_addr(ctx->env_ptr, index + 2, field_ptr_ty);
    ILValue addr = emit(ctx, faddr_instr);

    return addr;
}

static ILValue lower_closure_expr(LowerContext* ctx, const ClosureExpr* expr, const ILType* expected_type) {
    (void)expected_type;
    // 1. Generate unique function name
    char closure_name[64];
    static uint32_t closure_id = 0;
    snprintf(closure_name, sizeof(closure_name), "__closure_%u", closure_id++);

    // 2. Determine return type
    const ILType* ret_ty = expr->return_type ? lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, expr->return_type, ctx->current_substs) : il_type_unit();

    // 3. Create IL function
    ILFunction* ifn = il_func_create((uint32_t)(ctx->module->function_count + 1), closure_name, ret_ty, false, false, ctx->current_file);
    if (requires_pass_by_ref(ctx->module, ret_ty)) {
        ifn->is_sret = true;
        ifn->sret_type = ret_ty;
        ifn->return_type = il_type_unit();
        il_func_add_param(ifn, il_type_ptr(ret_ty, REGION_LOCAL, true));
    }
    il_mod_add_func(ctx->module, ifn);

    // 4. Create environment struct definition EARLY so we can use it during lowering
    char struct_name[64];
    snprintf(struct_name, sizeof(struct_name), "Env_%u", closure_id-1);
    ILTypeDef* env_def = il_type_def_struct_create(ctx->module->type_def_count, struct_name, ctx->current_file, false);
    il_mod_add_type_def(ctx->module, env_def);

    const ILType* struct_ty = il_type_struct(struct_name, env_def->id);
    if (!struct_ty) return (ILValue){0};
    
    // 5. Add implicit environment pointer as NEXT argument (MUST be Ptr<unit> for unified CC)
    const ILType* unit_ptr_ty = il_type_ptr(il_type_unit(), REGION_STATIC, false);
    if (!unit_ptr_ty) {
        return (ILValue){0};
    }
    il_func_add_param(ifn, unit_ptr_ty);

    // 6. Add original parameters
    for (uint32_t i = 0; i < expr->param_count; i++) {
        const ILType* pty = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, expr->params[i].type, ctx->current_substs);
        il_func_add_param(ifn, pty);
    }

    // Field 0 of environment is the function pointer
    const ILType* fn_ptr_ty = il_type_fn(ifn->return_type, ifn->param_types, ifn->param_count, ifn->is_variadic);
    if (!fn_ptr_ty) {
        return (ILValue){0};
    }
    il_type_def_add_field(env_def, "code", fn_ptr_ty);
    il_type_def_add_field(env_def, "env", il_type_ptr(il_type_unit(), REGION_STATIC, false));

    // 7. Lower body in a new context
    LowerContext cctx;
    memset(&cctx, 0, sizeof(LowerContext));
    cctx.parent_ctx = ctx;
    cctx.current_file = ctx->current_file;
    cctx.release_mode = ctx->release_mode;
    cctx.current_func = ifn;
    cctx.module = ctx->module;
    cctx.surface_mod = ctx->surface_mod;
    cctx.report = ctx->report;
    cctx.next_value_id = 1;
    cctx.next_block_id = 1;
    cctx.current_substs = ctx->current_substs;
    
    scope_push(&cctx);
    if (!cctx.current_scope) {
        return (ILValue){0};
    }
    Scope* closure_base_scope = cctx.current_scope;
    closure_base_scope->parent = ctx->current_scope;

    if (ifn->is_sret) {
        cctx.sret_id = cctx.next_value_id++;
    }
    
    // Parameter 0: The generic environment pointer (implicit)
    ILValue raw_env_ptr = (ILValue){ .id = cctx.next_value_id++, .type = unit_ptr_ty };
    
    // Parameter 1..N: Original parameters
    for (uint32_t i = 0; i < expr->param_count; i++) {
        const ILType* pty = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, expr->params[i].type, ctx->current_substs);
        ILValue pval = { .id = cctx.next_value_id++, .type = pty };
        symbol_add_ctx(&cctx, expr->params[i].name, pval, false);
    }

    ILBasicBlock* entry = create_block(&cctx);
    cctx.current_block = entry;
    
    // Now handle mutable parameters by allocating and storing
    for (uint32_t i = 0; i < expr->param_count; i++) {
        if (expr->params[i].is_mutable) {
            const Symbol* sym = symbol_lookup_ctx(&cctx, expr->params[i].name);
            ILValue pval = sym->value;
            const ILType* ptr_ty = il_type_ptr(pval.type, REGION_LOCAL, true);
            ILInstruction* alloc = il_build_alloc(REGION_LOCAL, pval.type, ptr_ty, (ILValue){0});
            ILValue ptr = emit(&cctx, alloc);
            ILInstruction* store = il_build_store(ptr, pval);
            emit(&cctx, store);
            // Update symbol to point to the allocation
            ILValue final_ptr = (ILValue){ .id = ptr.id, .type = ptr.type };
            symbol_add_ctx(&cctx, expr->params[i].name, final_ptr, true);
        }
    }

    // Cast the generic environment pointer to our specific struct type
    const ILType* struct_ptr_ty = il_type_ptr(struct_ty, REGION_LOCAL, false);
    cctx.env_ptr = emit(&cctx, il_build_bitcast(raw_env_ptr, struct_ptr_ty));

    // The environment pointer (implicit)
    {
        ILValue self_val = { .id = cctx.env_ptr.id, .type = cctx.env_ptr.type };
        symbol_add_ctx(&cctx, "self", self_val, false);
    }

    ILValue body_res = lower_block(&cctx, expr->body, ret_ty, (ILValue){0});
    
    // IMPORTANT: Unlink from outer scope BEFORE popping/cleanup
    closure_base_scope->parent = NULL;

    if (body_res.type) {
        run_all_defers(&cctx, body_res.id);
        if (!block_is_terminated(cctx.current_block)) {
            emit_return(&cctx, body_res);
        }
    } else {
        run_all_defers(&cctx, 0);
        if (!block_is_terminated(cctx.current_block)) {
            ILValue unit_val = { .id = 0, .type = il_type_unit() };
            emit_return(&cctx, unit_val);
        }
    }
    
    // 8. Allocate and populate in outer function
    const ILType* closure_ptr_ty = il_type_ptr(struct_ty, REGION_HEAP, false);
    ILInstruction* alloc_instr = il_build_alloc(REGION_HEAP, struct_ty, closure_ptr_ty, (ILValue){0});
    ILValue closure_ptr = emit(ctx, alloc_instr);

    // Field 0: function pointer
    const ILType* fn_ptr_ptr_ty = il_type_ptr(fn_ptr_ty, REGION_LOCAL, true);
    ILValue faddr = emit(ctx, il_build_field_addr(closure_ptr, 0, fn_ptr_ptr_ty));
    ILInstruction* faddr_instr = il_build_func_addr(ifn->id, fn_ptr_ty);
    ILValue fval = emit(ctx, faddr_instr);
    il_block_add_instr(ctx->current_block, il_build_store(faddr, fval));

    // Field 1: environment pointer (points to self)
    const ILType* env_ty = il_type_ptr(il_type_unit(), REGION_STATIC, false);
    const ILType* env_ptr_ptr_ty = il_type_ptr(env_ty, REGION_LOCAL, true);
    ILValue eaddr = emit(ctx, il_build_field_addr(closure_ptr, 1, env_ptr_ptr_ty));
    ILValue eval = emit(ctx, il_build_bitcast(closure_ptr, env_ty));
    il_block_add_instr(ctx->current_block, il_build_store(eaddr, eval));

    const Capture* cap = cctx.captures;
    uint32_t idx = 2; // Captures start at field 2
    while (cap) {
        const ILType* cptr_ty = il_type_ptr(cap->type, REGION_LOCAL, true);
        ILValue caddr = emit(ctx, il_build_field_addr(closure_ptr, idx, cptr_ty));
        
        ILValue capture_val = cap->original_value;
        bool owned = false;
        if (cap->is_lvalue) {
            // If it's an lvalue (stack variable), we need to load its current value to capture it
            capture_val = emit(ctx, il_build_load(capture_val));
            owned = true;
        }

        if (!il_type_is_copy_mod(ctx->module, cap->type)) {
            // Emitting a MOVE here will mark the original value as moved in the IL
            ILInstruction* move = il_build_move(capture_val);
            ILValue moved_val = emit(ctx, move);

            capture_val = moved_val;
        } else if (!owned) {
            capture_val = il_value_copy_type(capture_val);
        }

        il_block_add_instr(ctx->current_block, il_build_store(caddr, capture_val));
        
        
        cap = cap->next;
        idx++;
    }

    
    ILValue res = { .id = closure_ptr.id, .type = closure_ptr.type };
    
    // Use lower_context_cleanup to free everything in cctx
    lower_context_cleanup(&cctx);

    return res;
}

static ILValue lower_tuple_literal(LowerContext* ctx, const Expression* expr, const ILType* expected_type, ILValue dest_ptr) {
    if (expr->kind != EXPR_TUPLE) return (ILValue){0};
    if (expr->as.tuple_expr.count == 0) return (ILValue){ .id = 0, .type = il_type_unit() };
    
    ILValue* elements = calloc(expr->as.tuple_expr.count, sizeof(ILValue));
    
    // 1. Lower all elements first to get their values and types.
    for (uint32_t i = 0; i < expr->as.tuple_expr.count; i++) {
        const ILType* expected_elem_ty = NULL;
        if (expected_type && expected_type->kind == IL_TY_STRUCT && expected_type->as.struct_sum.type_def_id != 0) {
            const ILTypeDef* def = il_mod_get_type_def(ctx->module, expected_type->as.struct_sum.type_def_id);
            if (def && i < def->field_count) {
                expected_elem_ty = def->fields[i].type;
            }
        }
        elements[i] = lower_expression_move(ctx, expr->as.tuple_expr.elements[i], expected_elem_ty, (ILValue){0});
    }

    if (!ctx || !ctx->current_block) {
        free(elements);
        return (ILValue){ .id = 0, .type = il_type_never() };
    }

    const ILType* tuple_ty = NULL;
    if (expected_type && expected_type->kind == IL_TY_STRUCT && expected_type->as.struct_sum.type_def_id != 0) {
         tuple_ty = expected_type;
    } else {
         ILType raw_tuple;
         raw_tuple.kind = IL_TY_TUPLE;
         raw_tuple.as.tuple.count = expr->as.tuple_expr.count;
         raw_tuple.as.tuple.elements = calloc(raw_tuple.as.tuple.count, sizeof(const ILType*));
         for (uint32_t i = 0; i < raw_tuple.as.tuple.count; i++) {
             // If we failed to lower an element, use unit so it doesn't crash
             raw_tuple.as.tuple.elements[i] = elements[i].type ? elements[i].type : il_type_unit();
         }
         tuple_ty = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, &raw_tuple, ctx->current_substs);
         free(raw_tuple.as.tuple.elements);
    }
    
    if (!tuple_ty) {
        free(elements);
        return (ILValue){0};
    }

    // 2. ALLOC the struct
    ILValue struct_ptr;
    const ILType* ptr_ty = NULL;
    if (dest_ptr.id != 0) {
        struct_ptr = dest_ptr;
    } else {
        ptr_ty = il_type_ptr(tuple_ty, REGION_LOCAL, true);
        ILInstruction* alloc = il_build_alloc(REGION_LOCAL, tuple_ty, ptr_ty, (ILValue){0, NULL});
        struct_ptr = emit(ctx, alloc);
    }
    
    // 3. STORE each element
    const ILTypeDef* def = il_mod_get_type_def(ctx->module, tuple_ty->as.struct_sum.type_def_id);
    if (!def) {
        if (dest_ptr.id == 0) {
        }
        free(elements);
        return (ILValue){0};
    }
    
    for (uint32_t i = 0; i < expr->as.tuple_expr.count; i++) {
        ILValue val = elements[i];
        
        const ILType* field_val_ty_copy = val.type;
        uint32_t rid = (struct_ptr.type->kind == IL_TY_PTR) ? struct_ptr.type->as.ptr.region_id : REGION_LOCAL;
        const ILType* field_ptr_ty = il_type_ptr(field_val_ty_copy, rid, true);
        
        ILInstruction* faddr = il_build_field_addr(struct_ptr, i, field_ptr_ty);
        ILValue field_ptr = emit(ctx, faddr);
        
        ILInstruction* store = il_build_store(field_ptr, val);
        emit_void(ctx, store);

        // If field value is non-copy, mark it as moved.
        if (val.type && !il_type_is_copy_mod(ctx->module, val.type)) {
            mark_moved(ctx, val.id);
        }

    }

    free(elements);
    
    if (dest_ptr.id != 0) {
        return (ILValue){ .id = struct_ptr.id, .type = tuple_ty };
    } else {
        // 4. LOAD the result
        ILInstruction* load = il_build_load(struct_ptr);
        ILValue res = emit(ctx, load);
        return res;
    }
}

ILValue ensure_value(LowerContext* ctx, ILValue val, const ILType* expected) {
    if (!expected || !val.type) return val;
    if (expected->kind != IL_TY_PTR && expected->kind != IL_TY_BOX &&
        (val.type->kind == IL_TY_PTR || val.type->kind == IL_TY_BOX)) {
        
        // ABI: Large aggregates are passed by reference, so they should remain pointers.
        if (requires_pass_by_ref(ctx->module, expected)) {
            val.type = expected;
            return val;
        }

        if (il_type_eq(val.type->kind == IL_TY_PTR ? val.type->as.ptr.pointee : val.type->as.box.pointee, expected)) {
            ILValue res = emit(ctx, il_build_load(val));
            res.type = expected;
            return res;
        }
    }
    return val;
}

ILValue lower_expression_internal(LowerContext* ctx, const Expression* expr, const ILType* expected_type, bool is_move, ILValue dest_ptr, bool allow_lvalue, bool force_value) {
    (void)dest_ptr;
    if (!expr) {
        if (expected_type && expected_type->kind == IL_TY_UNIT) {
            return (ILValue){ .id = 0, .type = il_type_unit() };
        }
        return (ILValue){0};
    }
    
    ctx->current_file = expr->file_path;
    ctx->current_source = expr->source;
    ctx->current_line = expr->line;
    ctx->current_col = expr->col;
    ctx->current_offset = expr->offset;
    
    ILValue res = {0};
    switch (expr->kind) {
        case EXPR_INT: {
            const ILType* type = NULL;
            if (expected_type && (is_numeric_type(expected_type) || is_pointer_type(ctx->module, expected_type))) {
                type = expected_type;
            } else if (expr->type) {
                type = expr->type;
            } else {
                type = il_type_i32();
            }
            ILInstruction* instr = il_build_const(expr->as.int_val, type);
            if (instr) {
                res = emit(ctx, instr);
                break;
            }
            res = (ILValue){0};
            break;
        }

        case EXPR_FLOAT: {
            const ILType* type = NULL;
            if (expected_type && (is_numeric_type(expected_type) || is_pointer_type(ctx->module, expected_type))) {
                type = expected_type;
            } else {
                type = il_type_f64();
            }
            ILInstruction* instr = il_build_fconst(expr->as.float_val, type);
            if (instr) {
                res = emit(ctx, instr);
                break;
            }
            res = (ILValue){0};
            break;
        }
        case EXPR_BOOL: {
            const ILType* type = il_type_bool();
            if (!type) { res = (ILValue){0}; break; }
            ILInstruction* instr = il_build_const(expr->as.bool_val ? 1 : 0, type);
            if (instr) {
                res = emit(ctx, instr);
                break;
            }
            res = (ILValue){0};
            break;
        }

        case EXPR_SIZEOF:
        case EXPR_ALIGNOF: {
            SourceLocation expr_loc = { .file_path = expr->file_path, .source = expr->source, .line = expr->line, .col = expr->col, .offset = expr->offset, .length = expr->length };
            const ILType* target = lower_type_with_loc(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, expr->as.type_expr, ctx->current_substs, expr_loc);
            if (!target) { res = (ILValue){0}; break; }
            il_type_fixup(ctx->module, target);
            size_t val = (expr->kind == EXPR_SIZEOF) ? il_type_size(ctx->module, target) : il_type_align(ctx->module, target);

            const ILType* res_ty = il_type_usize();
            if (!res_ty) { res = (ILValue){0}; break; }
            ILInstruction* instr = il_build_const(val, res_ty);
            res = emit(ctx, instr);
            break;        }
        case EXPR_VAR: {
            const Symbol* found_sym = symbol_lookup_ctx(ctx, expr->as.var.name);
            if (found_sym) {
                bool is_capture = false;

                // Find which scope it belongs to for capture analysis
                const Scope* scope = NULL;
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
                if (scope && scope->owner_func != ctx->current_func) {
                    is_capture = true;
                }

                ILValue val;
                if (is_capture) {
                    val = resolve_capture(ctx, found_sym);
                    if (!found_sym->is_lvalue) {
                        // Capture was by value, but resolve_capture returned the address in the env struct. Load it!
                        ILInstruction* load = il_build_load(val);
                        ILValue loaded_val = emit(ctx, load);
                        val = loaded_val;
                    }
                    // Check if this specific capture instance was already moved in this closure call
                    if (is_moved(ctx, val.id)) {
                        emit_diag_at(ctx, DIAG_ERROR, expr, "use of moved capture '%s'", expr->as.var.name);
                    }
                } else {
                    val = (ILValue){ .id = found_sym->value.id, .type = found_sym->value.type };
                }

                if (found_sym->is_lvalue) {
                    if (allow_lvalue && val.type && val.type->kind == IL_TY_PTR && val.type->as.ptr.pointee && is_aggregate_type_layout(val.type->as.ptr.pointee)) {
                        res = (ILValue){ .id = val.id, .type = val.type->as.ptr.pointee };
                        break;
                    }

                    ILInstruction* load = il_build_load(val);
                    if (!load || !load->result_type) {
                        res = (ILValue){0};
                        break;
                    }

                    // If we are borrowing (is_move=false) and it's a Box, load it as Ptr instead of Box
                    // to avoid marking the source as moved in the verifier.
                    if (!is_move && load->result_type->kind == IL_TY_BOX) {
                        const ILType* box_ty = load->result_type;
                        const ILType* ptr_ty = il_type_ptr(box_ty->as.box.pointee, val.id, box_ty->as.box.is_mut);
                        load->result_type = ptr_ty;
                    }

                    // Link the loaded pointer to its storage location if it's in the local region.
                    if (load->result_type->kind == IL_TY_PTR && (load->result_type->as.ptr.region_id == REGION_LOCAL || load->result_type->as.ptr.region_id == 0)) {
                        load->result_type = il_type_ptr(load->result_type->as.ptr.pointee, val.id, load->result_type->as.ptr.is_mut);
                    }

                    res = emit(ctx, load);
                    if (is_move && !il_type_is_copy_mod(ctx->module, res.type)) {
                        mark_moved(ctx, val.id);
                        mark_moved(ctx, res.id);
                    } else if (!is_move && res.type && (res.type->kind == IL_TY_FD || res.type->kind == IL_TY_ASYNC_CONTEXT)) {
                        // Linear resources borrowed as values from lvalues.
                        // No mark_moved here.
                    }
                    break;
                } else {
                    if (is_move && !il_type_is_copy_mod(ctx->module, val.type)) {
                        mark_moved(ctx, val.id);
                    } else if (!is_move && val.type && (val.type->kind == IL_TY_FD || val.type->kind == IL_TY_ASYNC_CONTEXT)) {
                        // Linear resources borrowed as values from SSA IDs.
                        // No mark_moved here.
                    }
                    res = (ILValue){ .id = val.id, .type = val.type };
                    break;
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
                    const ILType* ptr_ty = il_type_ptr(g->type, REGION_STATIC, true);
                    if (!ptr_ty) { res = (ILValue){0}; break; }
                    ILInstruction* gaddr = il_build_global_addr(g->id, ptr_ty);
                    if (!gaddr) {
                        res = (ILValue){0};
                        break;
                    }
                    ILValue gaddr_res = emit(ctx, gaddr);
                    ILInstruction* load = il_build_load(gaddr_res);

                    if (!load) {
                        res = (ILValue){0};
                        break;
                    }

                    res = emit(ctx, load);
                    break;
            }

            // Try to resolve as function pointer
            const ILFunction* target_fn = il_mod_get_func_by_name(ctx->module, expr->as.var.name);
            if (target_fn) {
                // Visibility check
                if (!target_fn->is_pub && ctx->current_file && target_fn->file_path) {
                    if (strcmp(ctx->current_file, target_fn->file_path) != 0) {
                        emit_diag_at(ctx, DIAG_ERROR, expr, "Access to private function '%s'", target_fn->name);
                    }
                }
            }
            if (!target_fn) {
                for (uint32_t i = 0; i < ctx->surface_mod->function_count; i++) {
                    const FunctionDecl* sfn = ctx->surface_mod->functions[i];
                        if (sfn->name && strcmp(sfn->name, expr->as.var.name) == 0) {
                            // Visibility check
                            if (!sfn->is_pub && ctx->current_file && sfn->file_path) {
                                if (strcmp(ctx->current_file, sfn->file_path) != 0) {
                                    emit_diag_at(ctx, DIAG_ERROR, expr, "Access to private function '%s'", sfn->name);
                                }
                            }
                            if (sfn->type_param_count > 0 && expr->as.var.type_arg_count > 0) {
                            char* mname = mangle_generic_name(sfn->name, expr->as.var.type_arg_count, (const ILType **)expr->as.var.type_args);
                            target_fn = il_mod_get_func_by_name(ctx->module, mname);
                            if (!target_fn) {
                                target_fn = monomorphize_function(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, sfn, (const ILType **)expr->as.var.type_args, mname, NULL);
                            }
                            free(mname);
                            break;
                        } else if (sfn->type_param_count == 0) {
                            // Visibility check
                            if (!sfn->is_pub && ctx->current_file && sfn->file_path) {
                                if (strcmp(ctx->current_file, sfn->file_path) != 0) {
                                    emit_diag_at(ctx, DIAG_ERROR, expr, "Access to private function '%s'", sfn->name);
                                }
                            }
                            // Non-generic function that hasn't been lowered yet
                            // (though typically it should have been)
                            target_fn = monomorphize_function(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, sfn, NULL, sfn->name, NULL);
                            break;
                        }
                    }
                }
            }

            if (target_fn) {
                const ILType* fn_ty = il_type_fn(target_fn->return_type, target_fn->param_types, target_fn->param_count, target_fn->is_variadic);
                
                // Get the consistent mangled closure type for this signature
                const ILType* closure_ptr_ty = get_closure_type(ctx->module, fn_ty);
                const ILType* struct_ty = closure_ptr_ty->as.ptr.pointee;
                
                ILInstruction* alloc_instr = il_build_alloc(REGION_HEAP, struct_ty, closure_ptr_ty, (ILValue){0});
                ILValue desc = emit(ctx, alloc_instr);
                
                // Store function pointer at offset 0
                const ILType* fptr_ptr_ty = il_type_ptr(fn_ty, REGION_LOCAL, true);
                ILValue fptr_addr = emit(ctx, il_build_field_addr(desc, 0, fptr_ptr_ty));
                ILInstruction* faddr_instr = il_build_func_addr(target_fn->id, fn_ty);
                ILValue faddr = emit(ctx, faddr_instr);
                il_block_add_instr(ctx->current_block, il_build_store(fptr_addr, faddr));
                
                // Store NULL environment at offset 8 (field 1)
                const ILType* inner_env_ty = il_type_ptr(il_type_unit(), REGION_STATIC, false);
                const ILType* env_ptr_ty = il_type_ptr(inner_env_ty, REGION_LOCAL, true);
                ILValue env_ptr_addr = emit(ctx, il_build_field_addr(desc, 1, env_ptr_ty));
                
                ILValue null_val = emit(ctx, il_build_const(0, inner_env_ty));
                il_block_add_instr(ctx->current_block, il_build_store(env_ptr_addr, null_val));
                
                
                ILValue fres = { .id = desc.id, .type = closure_ptr_ty };
                res = fres;
                break;
            }

            // If not a function, check if it's a type name
            const ILTypeDef* def = find_type_def(ctx, expr->as.var.name);
            if (def) {
                const ILType* t = NULL;
                if (expr->as.var.type_arg_count > 0) {
                    const ILType ** lowered_args = malloc(sizeof(const ILType*) * expr->as.var.type_arg_count);
                    for (uint32_t j = 0; j < expr->as.var.type_arg_count; j++) {
                        lowered_args[j] = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, expr->as.var.type_args[j], ctx->current_substs);
                    }
                    t = (def->is_sum) 
                        ? il_type_sum_gen(def->name, 0, lowered_args, expr->as.var.type_arg_count) 
                        : il_type_struct_gen(def->name, 0, lowered_args, expr->as.var.type_arg_count);
                    free(lowered_args);
                } else {
                    t = (def->is_sum) 
                        ? il_type_sum(def->name, def->id) 
                        : il_type_struct(def->name, def->id);
                }
                if (!t) { res = (ILValue){0}; break; }
                
                const ILType* resolved = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, t, ctx->current_substs);
                res = (ILValue){ .id = 0, .type = resolved };
                break;
            }

            emit_diag_at(ctx, DIAG_ERROR, expr, "Unresolved symbol: %s", expr->as.var.name);
            res = (ILValue){0};
            break;
        }
        case EXPR_STRING: {
            const ILType* u8_ty = il_type_u8();
            if (!u8_ty) { res = (ILValue){0}; break; }
            
            const ILType* ptr_ty = il_type_ptr(u8_ty, REGION_STATIC, false);
            if (!ptr_ty) {  res = (ILValue){0}; break; }

            uint32_t gid = ctx->module->global_count;
            ILGlobal* global = il_global_create(gid, "string_lit", u8_ty, true, true, NULL);
            il_global_set_init_data(global, (const uint8_t*)expr->as.string_val.val, (uint32_t)expr->as.string_val.len + 1);
            il_mod_add_global(ctx->module, global);

            ILInstruction* instr = il_build_global_addr(gid, ptr_ty);
            ILValue ptr = emit(ctx, instr);

            if (expected_type && expected_type->kind == IL_TY_PTR && expected_type->as.ptr.pointee->kind == IL_TY_U8) {
                res = ptr;
                break;
            }

            const ILType* usize_ty = il_type_usize();
            if (!usize_ty) {    res = (ILValue){0}; break; }
            ILInstruction* len = il_build_const(expr->as.string_val.len, usize_ty);
            ILValue len_val = emit(ctx, len);

            const ILType* slice_ty = il_type_slice(u8_ty, REGION_STATIC, false);
            if (!slice_ty) {     res = (ILValue){0}; break; }

            ILInstruction* slice = il_build_slice_construct(ptr, len_val, slice_ty);
            res = emit(ctx, slice);
            break;
        }
        case EXPR_BINARY:
            res = lower_binary(ctx, expr);
            break;
        case EXPR_UNARY:
            res = lower_unary(ctx, &expr->as.unary, expected_type);
            break;
        case EXPR_CALL:
            res = lower_call(ctx, expr, expected_type, dest_ptr);
            break;
        case EXPR_BLOCK:
            res = lower_block(ctx, expr->as.block, expected_type, dest_ptr);
            break;
        case EXPR_IF:
            res = lower_if_expr(ctx, expr->as.if_expr, expected_type, dest_ptr);
            break;
        case EXPR_WHILE:
            res = lower_while_expr(ctx, &expr->as.while_expr, expected_type, dest_ptr);
            break;
        case EXPR_STRUCT:
            res = lower_struct_literal_typed(ctx, &expr->as.struct_expr, dest_ptr, expected_type);
            break;
        case EXPR_CLOSURE:
            res = lower_closure_expr(ctx, &expr->as.closure, expected_type);
            break;
        case EXPR_MEMBER:
            res = lower_member_access(ctx, &expr->as.member, expected_type, is_move, allow_lvalue);
            break;
        case EXPR_INDEX:
            res = lower_index_expr(ctx, &expr->as.index_expr, allow_lvalue);
            break;
        case EXPR_MATCH:
            res = lower_match_expr(ctx, &expr->as.match_expr, expected_type, dest_ptr);
            break;

        case EXPR_BOX:
            res = lower_box(ctx, expr);
            break;
        case EXPR_CAST:
            res = lower_cast(ctx, expr->as.cast_expr.expr, expr->as.cast_expr.target_type);
            break;
        case EXPR_ARRAY:
            res = lower_array_literal(ctx, expr, expected_type);
            break;
        case EXPR_TUPLE:
            res = lower_tuple_literal(ctx, expr, expected_type, dest_ptr);
            break;
        case EXPR_TRY:
            res = lower_try_expr(ctx, expr->as.try_expr);
            break;
        case EXPR_RETURN:
            res = lower_return_expr(ctx, expr->as.ret_expr);
            break;
        default:
            ICE("Unhandled expression kind in lowerer: %d", expr->kind);
            break;
    }

    if (expected_type && res.type) {
        ILValue assigned = ensure_assignable(ctx, res, expected_type);
        res = assigned;
    }

    if (!allow_lvalue || force_value) {
        res = ensure_value(ctx, res, expected_type);
    }

    return res;
}

ILValue lower_if_expr(LowerContext* ctx, const IfExpr* if_expr, const ILType* expected_type, ILValue dest_ptr) {
    ILValue cond = lower_expression(ctx, if_expr->condition, il_type_bool(), (ILValue){0});
    ILBasicBlock* then_blk = create_block(ctx);
    ILBasicBlock* else_blk = create_block(ctx);
    ILBasicBlock* join_blk = create_block(ctx);
    
    ILInstruction* br = il_build_branch(cond, then_blk->id, else_blk->id);
    if (!br) {
        if (ctx->report && ctx->report->has_errors) return (ILValue){0};
        emit_diag_at(ctx, DIAG_ERROR, if_expr->condition, "Failed to build branch instruction (condition must be boolean)");
        return (ILValue){0};
    }
    il_block_add_instr(ctx->current_block, br);
    il_block_add_successor(ctx->current_block, then_blk);
    il_block_add_successor(ctx->current_block, else_blk);
    
    uint32_t orig_cap;
    bool* orig_state = save_moved_state(ctx, &orig_cap);

    ctx->current_block = then_blk;
    /* Forward dest_ptr into the branches: this allows in-place initialization
     * of aggregates (like struct literals) directly into the target destination,
     * avoiding redundant copies/stores that can trigger bootstrap compiler bugs. */
    ILValue then_val = lower_block(ctx, if_expr->then_block, expected_type, dest_ptr);
    ILBasicBlock* then_exit_blk = ctx->current_block;
    bool then_terminated = block_is_terminated(then_exit_blk);

    uint32_t then_exit_cap;
    bool* then_exit_state = save_moved_state(ctx, &then_exit_cap);

    restore_moved_state(ctx, orig_state, orig_cap);

    ctx->current_block = else_blk;
    ILValue else_val = {0};
    ILBasicBlock* else_exit_blk = else_blk;
    bool else_terminated = false;
    if (if_expr->else_block) {
        else_val = lower_block(ctx, if_expr->else_block, expected_type, dest_ptr);
        else_exit_blk = ctx->current_block;
        else_terminated = block_is_terminated(else_exit_blk);
    } else {
        else_val = (ILValue){ .id = 0, .type = il_type_unit() };
    }

    // Determine result type
    const ILType* res_type = NULL;
    if (expected_type) {
        res_type = expected_type;
    } else {
        if (then_val.type && !then_terminated && then_val.type->kind != IL_TY_NEVER) {
            res_type = then_val.type;
        } else if (else_val.type && !else_terminated && else_val.type->kind != IL_TY_NEVER) {
            res_type = else_val.type;
        } else if (then_val.type && !then_terminated) {
            res_type = then_val.type;
        } else if (else_val.type && !else_terminated) {
            res_type = else_val.type;
        }
    }

    ILValue final_then = then_val;
    if (res_type && then_val.type && !then_terminated && !il_type_eq(then_val.type, res_type)) {
        ctx->current_block = then_exit_blk;
        final_then = ensure_assignable(ctx, then_val, res_type);
        then_exit_blk = ctx->current_block;
    }
    if (!then_terminated) {
        ctx->current_block = then_exit_blk;
        add_jump(ctx, join_blk);
    }

    ILValue final_else = else_val;
    if (res_type && else_val.type && !else_terminated && !il_type_eq(else_val.type, res_type)) {
        ctx->current_block = else_exit_blk;
        final_else = ensure_assignable(ctx, else_val, res_type);
        else_exit_blk = ctx->current_block;
    }
    if (!else_terminated) {
        ctx->current_block = else_exit_blk;
        add_jump(ctx, join_blk);
    }

    // Merge moved states for the join block.
    if (!then_terminated && !else_terminated) {
        for (uint32_t i = 0; i < ctx->value_moved_capacity && i < then_exit_cap; i++) {
            ctx->value_moved[i] = ctx->value_moved[i] || then_exit_state[i];
        }
    } else if (!then_terminated && else_terminated) {
        if (ctx->value_moved_capacity < then_exit_cap) {
            bool* expanded = realloc(ctx->value_moved, then_exit_cap * sizeof(bool));
            if (expanded) {
                memset(expanded + ctx->value_moved_capacity, 0,
                       (then_exit_cap - ctx->value_moved_capacity) * sizeof(bool));
                ctx->value_moved = expanded;
                ctx->value_moved_capacity = then_exit_cap;
            }
        }
        for (uint32_t i = 0; i < then_exit_cap && i < ctx->value_moved_capacity; i++) {
            ctx->value_moved[i] = then_exit_state[i];
        }
    }
    free(then_exit_state);

    ctx->current_block = join_blk;

    if (res_type && res_type->kind != IL_TY_UNIT && then_val.type && else_val.type && !then_terminated && !else_terminated) {
        ILPhiIncoming incoming[2] = {
            { .block_id = then_exit_blk->id, .value_id = final_then.id },
            { .block_id = else_exit_blk->id, .value_id = final_else.id }
        };
        ILInstruction* phi = il_build_phi(incoming, 2, res_type);
        ILValue phi_res = (ILValue){0};
        if (phi) {
            phi_res = emit(ctx, phi);
        }
        return phi_res;
    } else if (res_type && then_val.type && !then_terminated) {
        return final_then;
    } else if (res_type && else_val.type && !else_terminated) {
        return final_else;
    }
    
    if (then_terminated && else_terminated) {
        // Both branches diverge -- return never type to signal divergence to the caller.
        ctx->current_block = NULL;
        return (ILValue){ .id = 0, .type = il_type_never() };
    }

    return (ILValue){ .id = 0, .type = il_type_unit() };
}

ILValue lower_while_expr(LowerContext* ctx, const WhileExpr* expr, const ILType* expected_type, ILValue dest_ptr) {
    (void)expected_type;
    (void)dest_ptr;
    
    ILBasicBlock* header = create_block(ctx);
    ILBasicBlock* body = create_block(ctx);
    ILBasicBlock* exit = create_block(ctx);
    
    add_jump(ctx, header);
    ctx->current_block = header;
    
    ILValue cond = lower_expression(ctx, expr->condition, il_type_bool(), (ILValue){0});
    ILInstruction* br = il_build_branch(cond, body->id, exit->id);
    if (!br) {
        if (ctx->report && ctx->report->has_errors) return (ILValue){0};
        emit_diag_at(ctx, DIAG_ERROR, expr->condition, "Failed to build branch instruction (condition must be boolean)");
        return (ILValue){0};
    }
    il_block_add_instr(ctx->current_block, br);
    il_block_add_successor(ctx->current_block, body);
    il_block_add_successor(ctx->current_block, exit);
    
    LoopInfo* loop = malloc(sizeof(LoopInfo));
    *loop = (LoopInfo){ .header = header, .exit = exit, .loop_scope = ctx->current_scope, .break_count = 0, .parent = ctx->current_loop };
    ctx->current_loop = loop;

    ctx->current_block = body;
    lower_block(ctx, expr->body, il_type_unit(), (ILValue){0});
    if (ctx->current_block) {
        add_jump(ctx, header);
    }

    uint32_t break_count = loop->break_count;
    ctx->current_loop = loop->parent;
    free(loop);

    // Divergence check: if condition is constant true and no breaks exist, code after is unreachable.
    bool infinite = (expr->condition->kind == EXPR_BOOL && expr->condition->as.bool_val == true);

    ctx->current_block = exit;
    if (infinite && break_count == 0) {
        ctx->current_block = NULL;
        // If the loop is an infinite loop (loop {}) without breaks, it has type 'never'
        return (ILValue){ .id = 0, .type = il_type_never() };
    }
    
    return (ILValue){ .id = 0, .type = il_type_unit() };
}
