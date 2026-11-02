#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "surface_lower_internal.h"
#include "il_type.h"
#include "il_instr.h"

// Forward declarations for functions defined here
ILValue lower_block(LowerContext* ctx, const BlockExpr* block, const ILType* expected_type, ILValue dest_ptr);
void lower_statement(LowerContext* ctx, const Statement* stmt);
void run_all_defers(LowerContext* ctx, uint32_t exempt_id);
void run_defers_in_scope(LowerContext* ctx, Scope* scope);
void scope_emit_drops(LowerContext* ctx, Scope* scope, uint32_t exempt_id);

void run_defers_in_scope(LowerContext* ctx, Scope* scope) {
    if (!scope) return;
    DeferNode* node = scope->defers;
    // Clear the defers list before running to prevent infinite recursion
    // if a defer block itself contains a return statement.
    scope->defers = NULL;
    while (node) {
        lower_block(ctx, node->block, il_type_unit(), (ILValue){0});
        DeferNode* next = node->next;
        free(node);
        node = next;
    }
}

void run_defers_up_to(LowerContext* ctx, const Scope* limit, uint32_t exempt_id) {
    /* Snapshot the scope chain first so that any scope_pop calls made
     * during defer execution cannot alias with our iteration pointer. */
    Scope* chain[64];
    uint32_t chain_len = 0;
    for (Scope* s = ctx->current_scope; s && s != limit && chain_len < 64; s = s->parent) {
        chain[chain_len++] = s;
    }
    for (uint32_t i = 0; i < chain_len; i++) {
        run_defers_in_scope(ctx, chain[i]);
        scope_emit_drops(ctx, chain[i], exempt_id);
    }
}

void run_all_defers(LowerContext* ctx, uint32_t exempt_id) {
    run_defers_up_to(ctx, NULL, exempt_id);
}

void emit_drop_dispatch(LowerContext* ctx, ILValue val) {
    if (val.type && (val.type->kind == IL_TY_STRUCT || val.type->kind == IL_TY_SUM)) {
        const ILTypeDef* def = il_mod_get_type_def(ctx->module, val.type->as.struct_sum.type_def_id);
        if (def && def->drop_fn_name) {
            if (ctx->current_func && ctx->current_func->name && strcmp(ctx->current_func->name, def->drop_fn_name) == 0) {
                return;
            }
            const ILFunction* drop_fn = il_mod_get_func_by_name(ctx->module, def->drop_fn_name);
            if (drop_fn) {
                if (ctx->current_func == drop_fn) {
                    return;
                }
                uint32_t arg_count = 1;
                if (!drop_fn->is_extern && strcmp(drop_fn->name, "main") != 0) arg_count++;
                ILValue* args = malloc(sizeof(ILValue) * arg_count);
                if (args) {
                    const ILType* env_ty = il_type_ptr(il_type_unit(), REGION_STATIC, false);
                    if (arg_count > 1) {
                        ILValue env = ctx->env_ptr;
                        if (env.id == 0) {
                            // If no environment pointer is available (e.g. in main), emit a constant 0
                            env = emit(ctx, il_build_const(0, env_ty));
                        }
                        args[0] = env;
                        args[1] = val;
                    } else {
                        args[0] = val;
                    }
                    const ILType* unit_ty = il_type_unit();
                    emit_void(ctx, il_build_call(drop_fn->id, args, arg_count, unit_ty));
                    
                    free(args);
                    return;
                }
            }
        }
    }
    // Note: linear resources (fd, async_context) are SKIPPED here when called from scope_emit_drops,
    // because we want to enforce manual closing.
    if (val.type && (val.type->kind == IL_TY_FD || val.type->kind == IL_TY_ASYNC_CONTEXT)) {
        return;
    }
    emit_void(ctx, il_build_drop(val));
}

void scope_emit_drops(LowerContext* ctx, Scope* scope, uint32_t exempt_id) {
    if (!scope || !ctx->current_block || block_is_terminated(ctx->current_block)) return;
    Symbol* sym = scope->symbols;
    while (sym) {
        if (sym->value.id != 0 && sym->value.id != exempt_id && !is_moved(ctx, sym->value.id)) {
            const ILType* effective_type = sym->value.type;
            if (sym->is_lvalue && effective_type && effective_type->kind == IL_TY_PTR) {
                effective_type = effective_type->as.ptr.pointee;
            }

            if (effective_type && (!il_type_is_copy_mod(ctx->module, effective_type) ||
                                   (effective_type->kind == IL_TY_PTR && is_ssa_region(effective_type->as.ptr.region_id)) ||
                                   (effective_type->kind == IL_TY_SLICE && is_ssa_region(effective_type->as.slice.region_id)))) {                if (sym->is_lvalue) {
                    ILValue val = emit(ctx, il_build_load(sym->value));
                    if (val.id != 0) {
                        if (ctx->current_func && sym->name) {
                            il_func_set_val_name(ctx->current_func, val.id, sym->name);
                        }
                        emit_drop_dispatch(ctx, val);
                        
                        bool should_skip_mark_moved = (val.type && (val.type->kind == IL_TY_FD || val.type->kind == IL_TY_ASYNC_CONTEXT));

                        if (val.id != exempt_id && !should_skip_mark_moved) {
                            mark_moved(ctx, val.id);
                        }
                        // Mark the symbol storage as moved.
                        if (!should_skip_mark_moved) {
                            mark_moved(ctx, sym->value.id);
                        }
                    }
                } else {
                    emit_drop_dispatch(ctx, sym->value);
                    bool should_skip_mark_moved = (sym->value.type && (sym->value.type->kind == IL_TY_FD || sym->value.type->kind == IL_TY_ASYNC_CONTEXT));
                    if (sym->value.id != exempt_id && !should_skip_mark_moved) {
                        mark_moved(ctx, sym->value.id);
                    }
                }
            }
        }
        sym = sym->next;
    }
}

static void scope_emit_temporary_drops(LowerContext* ctx, const Scope* scope, uint32_t exempt_id) {
    if (!ctx->current_block || block_is_terminated(ctx->current_block)) return;
    uint32_t end_count = ctx->temporary_count;
    for (uint32_t i = end_count; i > scope->temporary_start; i--) {
        ILValue val = ctx->temporaries[i - 1];
        if (val.id != 0 && val.id != exempt_id && !is_moved(ctx, val.id)) {
            if (val.type && (val.type->kind == IL_TY_FD || val.type->kind == IL_TY_ASYNC_CONTEXT)) {
                // skip linear resources
                continue;
            }
            emit_drop_dispatch(ctx, val);
            if (!(val.type && (val.type->kind == IL_TY_FD || val.type->kind == IL_TY_ASYNC_CONTEXT))) {
                mark_moved(ctx, val.id);
            }
        }
    }
}

void scope_pop(LowerContext* ctx, uint32_t exempt_id) {
    Scope* scope = ctx->current_scope;
    if (!scope) return;
    
    scope_emit_drops(ctx, scope, exempt_id);
    scope_emit_temporary_drops(ctx, scope, exempt_id);
    for (uint32_t i = scope->temporary_start; i < ctx->temporary_count; i++) {
        ctx->temporaries[i].type = NULL;
    }
    ctx->temporary_count = scope->temporary_start;
    
    // Run any remaining defers
    run_defers_in_scope(ctx, scope);

    ctx->current_scope = scope->parent;
    scope_free(scope);
}

static void emit_statement_temporary_drops(LowerContext* ctx, uint32_t start_count, uint32_t exempt_id) {
    if (!ctx->current_block || block_is_terminated(ctx->current_block)) {
        // Even if terminated, we must free the types of the temporaries
        // so we don't leak memory, but we don't emit IL instructions.
        for (uint32_t i = start_count; i < ctx->temporary_count; i++) {
            ctx->temporaries[i].type = NULL;
        }
        ctx->temporary_count = start_count;
        return;
    }
    uint32_t end_count = ctx->temporary_count;
    for (uint32_t i = end_count; i > start_count; i--) {
        ILValue val = ctx->temporaries[i - 1];
        if (val.id != 0 && val.id != exempt_id && !is_moved(ctx, val.id)) {
            if (val.type && (val.type->kind == IL_TY_FD || val.type->kind == IL_TY_ASYNC_CONTEXT)) {
                // skip
                continue;
            }
            emit_drop_dispatch(ctx, val);
            if (!(val.type && (val.type->kind == IL_TY_FD || val.type->kind == IL_TY_ASYNC_CONTEXT))) {
                mark_moved(ctx, val.id);
            }
        }
    }
    for (uint32_t i = start_count; i < ctx->temporary_count; i++) {
        ctx->temporaries[i].type = NULL;
    }
    ctx->temporary_count = start_count;
}

void lower_statement(LowerContext* ctx, const Statement* stmt) {
    if (!stmt || !ctx->current_block) return;
    ctx->current_file = stmt->file_path;
    ctx->current_source = stmt->source;
    ctx->current_line = stmt->line;
    ctx->current_col = stmt->col;
    ctx->current_offset = stmt->offset;

    uint32_t stmt_temp_start = ctx->temporary_count;
    uint32_t exempt_id = 0;

    switch (stmt->kind) {
        case STMT_RESERVED: break;
        case STMT_RETURN: {
            const ILType* expected = ctx->current_func->is_sret ? ctx->current_func->sret_type : ctx->current_func->return_type;
            ILValue dest = {0};
            if (ctx->current_func->is_sret) {
                // sret pointer is always ID 1.
                const ILType* ptr_ty = il_type_ptr(ctx->current_func->sret_type, REGION_LOCAL, true);
                dest = (ILValue){ .id = 1, .type = ptr_ty };
            }
            ILValue raw_val = lower_expression_move(ctx, stmt->as.ret, expected, dest);

            // Drop temporaries created during the evaluation of the return expression
            // BEFORE we drop local variables, to release any borrows.
            emit_statement_temporary_drops(ctx, stmt_temp_start, raw_val.id);

            // If lowering the return expression itself terminated the block (e.g. a match where
            // all arms return), we are now in unreachable code -- skip the redundant return.
            if (!block_is_terminated(ctx->current_block)) {
                run_all_defers(ctx, raw_val.id);
                emit_return(ctx, raw_val);
            }
            
            ctx->current_block = NULL;
            break;
        }
        case STMT_EXPR: {
            lower_expression_move(ctx, stmt->as.expr, NULL, (ILValue){0});
            if (block_is_terminated(ctx->current_block)) {
                ctx->current_block = NULL;
            }
            break;
        }
        case STMT_LET: {
            bool is_wildcard = (strcmp(stmt->as.let.name, "_") == 0);
            SourceLocation stmt_loc = { .file_path = stmt->file_path, .source = stmt->source, .line = stmt->line, .col = stmt->col, .offset = stmt->offset };
            const ILType* expected = lower_type_with_loc(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, stmt->as.let.type, ctx->current_substs, stmt_loc);
            
            if (!expected) {
                expected = guess_type(ctx, stmt->as.let.init);
            }

            // Optimization: pre-allocate stack slot for aggregates to enable dest_ptr elision.
            ILValue slot_ptr = {0};
            bool force_stack = false;
            if (expected) {
                if (stmt->as.let.is_mutable || is_aggregate_type_layout(expected)) {
                    force_stack = true;
                } else if (!il_type_is_copy_mod(ctx->module, expected)) {
                    // Linear primitives (fd, async_context) can stay in registers.
                    // Other non-copy types (Box, Slice, etc. and type variables) generally go to stack
                    // to support address-of and Drop.
                    if (expected->kind != IL_TY_FD && expected->kind != IL_TY_ASYNC_CONTEXT) {
                        force_stack = true;
                    }
                }
            }
            
            if (force_stack) {
                const ILType* ptr_ty_mut = il_type_ptr(expected, REGION_LOCAL, true);
                slot_ptr = emit(ctx, il_build_alloc(REGION_LOCAL, expected, ptr_ty_mut, (ILValue){0}));
            }

            ILValue init = lower_expression_move(ctx, stmt->as.let.init, expected, slot_ptr);
            
            if (is_wildcard) {
                if (init.id != 0 && slot_ptr.id == 0) {
                    emit(ctx, il_build_move(init));
                    if (!il_type_is_copy_mod(ctx->module, init.type)) {
                        mark_moved(ctx, init.id);
                    }
                }
                break;
            }

            bool is_lv = stmt->as.let.is_mutable;
            if (init.id != 0 && slot_ptr.id != 0) {
                if (init.id != slot_ptr.id) {
                    emit_void(ctx, il_build_store(slot_ptr, init));
                    if (!il_type_is_copy_mod(ctx->module, init.type)) {
                        mark_moved(ctx, init.id);
                    }
                }
                const ILType* final_ptr_ty = il_type_ptr(expected, REGION_LOCAL, stmt->as.let.is_mutable);
                init = (ILValue){ .id = slot_ptr.id, .type = final_ptr_ty };
                is_lv = true;
            } else if (init.id != 0 && (is_lv || is_aggregate_type_layout(init.type) || (!il_type_is_copy_mod(ctx->module, init.type) && init.type->kind != IL_TY_FD && init.type->kind != IL_TY_ASYNC_CONTEXT))) {
                const ILType* ptr_ty_mut = il_type_ptr(init.type, REGION_LOCAL, true);
                const ILType* ptr_ty = il_type_ptr(init.type, REGION_LOCAL, stmt->as.let.is_mutable);
                ILValue ptr = emit(ctx, il_build_alloc(REGION_LOCAL, init.type, ptr_ty_mut, (ILValue){0}));
                emit_void(ctx, il_build_store(ptr, init));
                if (!il_type_is_copy_mod(ctx->module, init.type)) {
                    mark_moved(ctx, init.id);
                }
                ptr.type = ptr_ty;
                init = ptr;
                is_lv = true;
            }
            symbol_add_ctx(ctx, stmt->as.let.name, init, is_lv);
            exempt_id = init.id;
            
            // Task 101: If the initialization expression created a temporary entry for this ID,
            // we must ensure its type copy is freed because we just took another copy for the symbol.
            if (exempt_id != 0) {
                for (uint32_t i = stmt_temp_start; i < ctx->temporary_count; i++) {
                    if (ctx->temporaries[i].id == exempt_id) {
                        ctx->temporaries[i].type = NULL;
                    }
                }
            }
            break;
        }
        case STMT_FOR: {
            ILValue raw_start = lower_expression(ctx, stmt->as.for_loop.start, NULL, (ILValue){0});
            ILValue raw_end = lower_expression(ctx, stmt->as.for_loop.end, raw_start.type, (ILValue){0});
            
            const ILType* loop_ty = unify_numeric_types(raw_start.type, raw_end.type);
            if (!loop_ty) loop_ty = il_type_u64();

            ILValue start_val = ensure_assignable(ctx, raw_start, loop_ty);
            ILValue end_val = ensure_assignable(ctx, raw_end, loop_ty);

            uint32_t entry_block_id = ctx->current_block->id;

            ILBasicBlock* header = create_block(ctx);
            ILBasicBlock* body = create_block(ctx);
            ILBasicBlock* increment = create_block(ctx);
            ILBasicBlock* loop_exit = create_block(ctx);

            add_jump(ctx, header);
            ctx->current_block = header;

            // Create a placeholder PHI node for the loop counter
            ILPhiIncoming incoming[2];
            incoming[0].block_id = entry_block_id;
            incoming[0].value_id = start_val.id;
            // Temporary placeholder for the back-edge value
            incoming[1].block_id = increment->id;
            incoming[1].value_id = start_val.id;

            ILInstruction* phi_instr = il_build_phi(incoming, 2, loop_ty);
            ILValue i_val = emit(ctx, phi_instr);
            symbol_add_ctx(ctx, stmt->as.for_loop.var_name, (ILValue){.id = i_val.id, .type = i_val.type}, false);

            const ILType* bool_ty = il_type_bool();
            ILInstruction* cmp = il_build_cmp_lt(i_val, end_val, bool_ty);
            ILValue cmp_res = emit(ctx, cmp);
            ILInstruction* br = il_build_branch(cmp_res, body->id, loop_exit->id);
            if (br) {
                il_block_add_instr(ctx->current_block, br);
                il_block_add_successor(ctx->current_block, body);
                il_block_add_successor(ctx->current_block, loop_exit);
            }

            LoopInfo* loop = malloc(sizeof(LoopInfo));
            if (!loop) { perror("malloc"); exit(1); }
            *loop = (LoopInfo){ .header = increment, .exit = loop_exit, .loop_scope = ctx->current_scope, .break_count = 0, .parent = ctx->current_loop };
            ctx->current_loop = loop;

            ctx->current_block = body;
            lower_block(ctx, stmt->as.for_loop.body, il_type_unit(), (ILValue){0});

            if (ctx->current_block) {
                add_jump(ctx, increment);
            }

            ctx->current_loop = loop->parent;
            free(loop);

            ctx->current_block = increment;
            ILInstruction* c1 = il_build_const(1, loop_ty);
            ILValue c1_res = emit(ctx, c1);

            ILInstruction* add = il_build_add(i_val, c1_res);
            ILValue add_res = emit(ctx, add);
            
            // Patch the back-edge in the PHI instruction
            phi_instr->operands.phi.incoming[1].value_id = add_res.id;

            add_jump(ctx, header);
            ctx->current_block = loop_exit;
            break;
        }
        case STMT_BREAK: {
            if (ctx->current_loop) {
                ctx->current_loop->break_count++;
                run_defers_up_to(ctx, ctx->current_loop->loop_scope, 0);
                add_jump(ctx, ctx->current_loop->exit);
                ctx->current_block = NULL;
            }
            break;
        }
        case STMT_CONTINUE: {
            if (ctx->current_loop) {
                run_defers_up_to(ctx, ctx->current_loop->loop_scope, 0);
                add_jump(ctx, ctx->current_loop->header);
                ctx->current_block = NULL;
            }
            break;
        }
        case STMT_DEFER: {
            if (!ctx->current_scope) break;
            DeferNode* node = calloc(1, sizeof(DeferNode));
            if (node) {
                node->block = stmt->as.defer_block;
                node->next = ctx->current_scope->defers;
                ctx->current_scope->defers = node;
            }
            break;
        default: ICE("Unhandled statement kind: %d", stmt->kind);
        }
    }

    emit_statement_temporary_drops(ctx, stmt_temp_start, exempt_id);
}

bool block_is_terminated(ILBasicBlock* block) {
    if (!block) return true;
    if (block->instr_count == 0) return false;
    const ILInstruction* last = block->instructions[block->instr_count - 1];
    ILOpcode last_op = last->opcode;
    if (last_op == IL_OP_RETURN || last_op == IL_OP_BRANCH || last_op == IL_OP_JUMP || last_op == IL_OP_VARIANT_MATCH) {
        return true;
    }
    
    // If it's a call, check if it returns never.
    if (last_op == IL_OP_CALL || last_op == IL_OP_CALL_PTR) {
        if (last->result_type && last->result_type->kind == IL_TY_NEVER) return true;
    }
    
    return false;
}

ILValue lower_block(LowerContext* ctx, const BlockExpr* block, const ILType* expected_type, ILValue dest_ptr) {
    if (!block) return (ILValue){0};
    scope_push(ctx);
    for (uint32_t i = 0; i < block->stmt_count; i++) {
        lower_statement(ctx, block->statements[i]);
        if (block_is_terminated(ctx->current_block)) break;
    }
    ILValue result = {0};
    if (block->result && ctx->current_block && !block_is_terminated(ctx->current_block)) {
        result = lower_expression(ctx, block->result, expected_type, dest_ptr);
    }
    scope_pop(ctx, result.id);

    if (!result.type) {
        if (!ctx->current_block || block_is_terminated(ctx->current_block)) {
            result.id = 0;
            result.type = il_type_never();
        } else {
            result.id = 0;
            result.type = il_type_unit();
        }
    }

    if (expected_type && result.type && !il_type_eq(result.type, expected_type)) {
        result = ensure_assignable(ctx, result, expected_type);
    }

    return result;
}

