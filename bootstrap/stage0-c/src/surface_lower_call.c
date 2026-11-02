#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "surface_lower_internal.h"
#include "surface_parser_internal.h"
#include "il_instr.h"
#include "il_pass.h"
#include "il_print.h"
#include "il_ownership.h"

bool match_type_param(LowerContext* ctx, const ILType* param_type, const ILType* arg_type, const char* param_name, const ILType ** out_arg) {
    if (!param_type || !arg_type) return false;

    bool is_param_var = (param_type->kind == IL_TY_VAR && param_type->as.var.name && strcmp(param_type->as.var.name, param_name) == 0) ||
                        ((param_type->kind == IL_TY_STRUCT || param_type->kind == IL_TY_SUM) && 
                         param_type->as.struct_sum.type_arg_count == 0 &&
                         param_type->as.struct_sum.name && strcmp(param_type->as.struct_sum.name, param_name) == 0);

    // Auto-deref arg_type if param_type is not a pointer but arg_type is.
    // This happens frequently with pass-by-ref ABI for aggregates.
    // id:1000 fix: DO NOT auto-deref if param_type is the variable we are matching, as we want to match the pointer type itself.
    if (arg_type->kind == IL_TY_PTR && param_type->kind != IL_TY_PTR && !is_param_var) {
        return match_type_param(ctx, param_type, arg_type->as.ptr.pointee, param_name, out_arg);
    }
    // Also handle the reverse just in case, though less common for inference.
    if (param_type->kind == IL_TY_PTR && arg_type->kind != IL_TY_PTR && !is_param_var) {
        return match_type_param(ctx, param_type->as.ptr.pointee, arg_type, param_name, out_arg);
    }

    if ((param_type->kind == IL_TY_STRUCT || param_type->kind == IL_TY_SUM) && param_type->as.struct_sum.type_arg_count == 0) {
        if (param_type->as.struct_sum.name && strcmp(param_type->as.struct_sum.name, param_name) == 0) {
            if (!*out_arg) {
                *out_arg = arg_type;
            }
            return true;
        }
    }
    
    // If param_type is a variable we are looking for, match it!
    if (param_type->kind == IL_TY_VAR) {
        if (param_type->as.var.name && strcmp(param_type->as.var.name, param_name) == 0) {
            if (!*out_arg) *out_arg = arg_type;
            return true;
        }
        
        // Check if this variable is already bound in our context
        const Substitution* s = ctx->current_substs;
        while (s) {
            if (param_type->as.var.name && strcmp(s->name, param_type->as.var.name) == 0) {
                if (s->type->kind != IL_TY_VAR || (s->type->as.var.name && strcmp(s->type->as.var.name, s->name) != 0)) {
                    return match_type_param(ctx, s->type, arg_type, param_name, out_arg);
                }
            }
            s = s->next;
        }
    }

    if (param_type->kind == IL_TY_PTR && arg_type->kind == IL_TY_PTR) {
        return match_type_param(ctx, param_type->as.ptr.pointee, arg_type->as.ptr.pointee, param_name, out_arg);
    }
    if (param_type->kind == IL_TY_BOX && arg_type->kind == IL_TY_BOX) {
        return match_type_param(ctx, param_type->as.box.pointee, arg_type->as.box.pointee, param_name, out_arg);
    }
    if (param_type->kind == IL_TY_SLICE && arg_type->kind == IL_TY_SLICE) {
        return match_type_param(ctx, param_type->as.slice.element, arg_type->as.slice.element, param_name, out_arg);
    }
    if (param_type->kind == IL_TY_ARRAY && arg_type->kind == IL_TY_ARRAY) {
        return match_type_param(ctx, param_type->as.array.element, arg_type->as.array.element, param_name, out_arg);
    }
    if (param_type->kind == IL_TY_TUPLE && arg_type->kind == IL_TY_TUPLE) {
        if (param_type->as.tuple.count != arg_type->as.tuple.count) return false;
        bool matched = false;
        for (uint32_t i = 0; i < param_type->as.tuple.count; i++) {
            if (match_type_param(ctx, param_type->as.tuple.elements[i], arg_type->as.tuple.elements[i], param_name, out_arg)) matched = true;
        }
        return matched;
    }

    if ((param_type->kind == IL_TY_STRUCT || param_type->kind == IL_TY_SUM) &&
        (arg_type->kind == IL_TY_STRUCT || arg_type->kind == IL_TY_SUM)) {
        
        const char* p_name = param_type->as.struct_sum.name;
        const char* a_name = arg_type->as.struct_sum.name;
        if (!p_name || !a_name) return false;

        bool name_match = (strcmp(p_name, a_name) == 0);
        const char* base_name = p_name;
        if (!name_match) {
            size_t plen = strlen(p_name);
            size_t alen = strlen(a_name);
            if (plen < alen && strncmp(a_name, p_name, plen) == 0 && a_name[plen] == '_') {
                name_match = true;
            } else if (alen < plen && strncmp(p_name, a_name, alen) == 0 && p_name[alen] == '_') {
                name_match = true;
                base_name = a_name;
            }
        }

        if (name_match) {
            uint32_t p_tpc = param_type->as.struct_sum.type_arg_count;
            uint32_t a_tpc = arg_type->as.struct_sum.type_arg_count;
            const ILType** p_args = param_type->as.struct_sum.type_args;
            const ILType** a_args = arg_type->as.struct_sum.type_args;

            if (p_tpc > 0 && a_tpc == p_tpc) {
                bool matched = false;
                for (uint32_t i = 0; i < p_tpc; i++) {
                    if (match_type_param(ctx, p_args[i], a_args[i], param_name, out_arg)) matched = true;
                }
                return matched;
            }

            if (a_tpc > 0) {
                 const TypeDef* styp = NULL;
                 for (uint32_t i = 0; i < ctx->surface_mod->type_def_count; i++) {
                     const TypeDef* td = ctx->surface_mod->type_defs[i];
                     const char* sname = (td->kind == TYPE_DEF_STRUCT) ? td->as.struct_decl->name : td->as.enum_decl->name;
                     if (strcmp(sname, base_name) == 0) { styp = td; break; }
                 }
                 if (!styp) {
                     for (uint32_t i = 0; i < ctx->surface_mod->type_alias_count; i++) {
                         if (strcmp(ctx->surface_mod->type_aliases[i]->name, base_name) == 0) {
                             const ILType* target = resolve_type_aliases(ctx->surface_mod, ctx->surface_mod->type_aliases[i]->target, 0);
                             if (target && (target->kind == IL_TY_STRUCT || target->kind == IL_TY_SUM)) {
                                 base_name = target->as.struct_sum.name;
                                 for (uint32_t j = 0; j < ctx->surface_mod->type_def_count; j++) {
                                     const TypeDef* td = ctx->surface_mod->type_defs[j];
                                     const char* sname = (td->kind == TYPE_DEF_STRUCT) ? td->as.struct_decl->name : td->as.enum_decl->name;
                                     if (strcmp(sname, base_name) == 0) { styp = td; break; }
                                 }
                             }
                             break;
                         }
                     }
                 }
                 if (styp) {
                     uint32_t tpc = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_param_count : styp->as.enum_decl->type_param_count;
                     char** tparams = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_params : styp->as.enum_decl->type_params;
                     if (tpc == a_tpc) {
                         for (uint32_t i = 0; i < tpc; i++) {
                             if (strcmp(tparams[i], param_name) == 0) {
                                 if (!*out_arg) *out_arg = a_args[i];
                                 return true;
                             }
                             if (match_type_param(ctx, il_type_var(tparams[i]), a_args[i], param_name, out_arg)) return true;
                         }
                     }
                 }
                 if (strcmp(base_name, param_name) == 0) {
                     if (!*out_arg) *out_arg = arg_type;
                     return true;
                 }
            }
        }
    }
    
    return false;
}

static const ILType* guess_generic_call_return_type(LowerContext* ctx, const FunctionDecl* sfn, const CallExpr* call) {
    const ILType ** type_args = calloc(sfn->type_param_count, sizeof(const ILType*));
    if (!type_args) return NULL;
    for (uint32_t k = 0; k < sfn->type_param_count; k++) {
        if (call->type_arg_count > k) {
            type_args[k] = call->type_args[k];
        } else {
            for (uint32_t j = 0; j < sfn->param_count && j < call->arg_count; j++) {
                const ILType* gty = guess_type_internal(ctx, call->args[j], NULL);
                if (gty) {
                    if (match_type_param(ctx, sfn->params[j].type, gty, sfn->type_params[k], &type_args[k])) {
                        break;
                    }
                }
            }
        }
        if (!type_args[k]) type_args[k] = il_type_unit();
    }
    Substitution* head = NULL;
    for (uint32_t j = 0; j < sfn->type_param_count; j++) {
        if (type_args[j]) {
            Substitution* n = calloc(1, sizeof(Substitution));
            if (n) {
                n->name = sfn->type_params[j];
                n->type = type_args[j];
                n->next = head;
                head = n;
            }
        }
    }
    const ILType* ret = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, sfn->return_type, head);
    while (head) { Substitution* n = (Substitution*)head->next; free(head); head = n; }
    free(type_args);
    return ret;
}

static ILFunction* infer_and_monomorphize_method(LowerContext* ctx, const ImplDecl* simpl, const FunctionDecl* method_sfn, const TypeDef* styp, const char* type_name, const char* method_name, const Expression** args, uint32_t arg_count) {
    uint32_t tpc = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_param_count : styp->as.enum_decl->type_param_count;
    if (tpc == 0) return NULL;
    const ILType ** inferred_args = calloc(tpc, sizeof(const ILType*));
    if (!inferred_args) return NULL;
    for (uint32_t k = 0; k < tpc; k++) {
        const char* p_name = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_params[k] : styp->as.enum_decl->type_params[k];
        for (uint32_t j = 0; j < method_sfn->param_count && j < arg_count; j++) {
            const ILType* gty = guess_type_internal(ctx, args[j], NULL);
            if (gty) {
                if (match_type_param(ctx, method_sfn->params[j].type, gty, p_name, &inferred_args[k])) {
                    break;
                }
            }
        }
        if (!inferred_args[k]) inferred_args[k] = il_type_unit();
    }
    char* mangled = mangle_generic_name(type_name, tpc, inferred_args);
    char full_mname[512];
    snprintf(full_mname, sizeof(full_mname), "%s_%s", mangled, method_name);
    ILFunction* target_fn = il_mod_get_func_by_name(ctx->module, full_mname);
    if (!target_fn) target_fn = monomorphize_method(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, simpl, method_sfn, inferred_args, full_mname);
    free(mangled);
    free(inferred_args);
    return target_fn;
}

// Does `vname` actually name a variant of enum `type_name`? guess_variant_type() answers "what type
// does Enum.X(...) produce" without asking, so for a non-generic enum it returns the enum type for
// *any* X - wrong for `Enum.method(...)`: an accessor like ILType.get_tag(&x) returns u32, but an
// un-annotated `let` got a slot typed ILType and the store failed. The get_tag()/get_Payload()
// accessor idiom is built entirely out of such calls.
static int enum_has_variant(LowerContext* ctx, const char* type_name, const char* vname) {
    for (uint32_t i = 0; i < ctx->surface_mod->type_def_count; i++) {
        const TypeDef* td = ctx->surface_mod->type_defs[i];
        if (td->kind != TYPE_DEF_ENUM) continue;
        if (strcmp(td->as.enum_decl->name, type_name) != 0) continue;
        for (uint32_t v = 0; v < td->as.enum_decl->variant_count; v++) {
            if (strcmp(td->as.enum_decl->variants[v].name, vname) == 0) return 1;
        }
        return 0;
    }
    return 0;
}

// Return type of a non-generic static method `type_name.method_name`, or NULL.
// Variants win over methods: this is only consulted once enum_has_variant() says
// the name is not a variant, so no existing resolution changes meaning.
static const ILType* guess_static_method_type(LowerContext* ctx, const char* type_name, const char* method_name) {
    if (enum_has_variant(ctx, type_name, method_name)) return NULL;
    const ImplDecl* impl = NULL;
    const FunctionDecl* sfn = find_method_decl(ctx->surface_mod, type_name, method_name, &impl);
    if (!sfn || !impl || sfn->type_param_count != 0 || !sfn->return_type) return NULL;
    return lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, sfn->return_type, ctx->current_substs);
}

static const ILType* guess_variant_type(LowerContext* ctx, const char* name, const Expression** args, uint32_t arg_count, const ILType* expected_type, const ILType** type_args, uint32_t type_arg_count) {
    char type_name[128];
    const char* dot = strchr(name, '.');
    if (!dot) return NULL;
    size_t len = (size_t)(dot - name);
    if (len >= sizeof(type_name)) len = sizeof(type_name) - 1;
    strncpy(type_name, name, len);
    type_name[len] = '\0';
    const char* vname = dot + 1;

    const ILTypeDef* def = find_type_def(ctx, type_name);
    if (!def || !def->is_sum) return NULL;

    // Find surface TypeDef to get type parameters
    const TypeDef* styp = NULL;
    for (uint32_t i = 0; i < ctx->surface_mod->type_def_count; i++) {
        const TypeDef* td = ctx->surface_mod->type_defs[i];
        const char* sname = (td->kind == TYPE_DEF_STRUCT) ? td->as.struct_decl->name : td->as.enum_decl->name;
        if (strcmp(sname, type_name) == 0) { styp = td; break; }
    }
    if (!styp || styp->kind != TYPE_DEF_ENUM) return NULL;

    if (styp->as.enum_decl->type_param_count == 0) {
        return il_type_sum(type_name, def->id);
    }

    uint32_t tpc = styp->as.enum_decl->type_param_count;
    const ILType** inferred_args = calloc(tpc, sizeof(const ILType*));
    
    for (uint32_t i = 0; i < type_arg_count && i < tpc; i++) {
        inferred_args[i] = type_args[i];
    }
    
    // 1. Infer from expected type
    const ILType* exp = expected_type;
    if (exp && exp->kind == IL_TY_PTR) exp = exp->as.ptr.pointee;
    if (exp && (exp->kind == IL_TY_SUM || exp->kind == IL_TY_STRUCT)) {
        for (uint32_t k = 0; k < tpc; k++) {
            match_type_param(ctx, il_type_sum(type_name, 0), exp, styp->as.enum_decl->type_params[k], &inferred_args[k]);
        }
    }

    // 2. Infer from args
    int v_idx = -1;
    for (uint32_t i = 0; i < styp->as.enum_decl->variant_count; i++) {
        if (strcmp(styp->as.enum_decl->variants[i].name, vname) == 0) { v_idx = (int)i; break; }
    }

    if (v_idx >= 0) {
        const ILType* payload_ty = styp->as.enum_decl->variants[v_idx].type;
        for (uint32_t k = 0; k < tpc; k++) {
            if (inferred_args[k]) continue;
            if (arg_count > 1 && payload_ty && payload_ty->kind == IL_TY_TUPLE) {
                for (uint32_t j = 0; j < payload_ty->as.tuple.count && j < arg_count; j++) {
                    const ILType* gty = guess_type_internal(ctx, args[j], NULL);
                    if (match_type_param(ctx, payload_ty->as.tuple.elements[j], gty, styp->as.enum_decl->type_params[k], &inferred_args[k])) break;
                }
            } else if (arg_count == 1) {
                const ILType* gty = guess_type_internal(ctx, args[0], NULL);
                match_type_param(ctx, payload_ty, gty, styp->as.enum_decl->type_params[k], &inferred_args[k]);
            }
        }
    }

    for (uint32_t i = 0; i < tpc; i++) if (!inferred_args[i]) inferred_args[i] = il_type_unit();
    const ILType* res = il_type_sum_gen(type_name, 0, inferred_args, tpc);
    free(inferred_args);
    return lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, res, ctx->current_substs);
}

const ILType* guess_type_internal(LowerContext* ctx, const Expression* expr, const ILType* expected_type) {
    if (!expr) return NULL;
    switch (expr->kind) {
        case EXPR_INT: {
            if (expr->type) return expr->type;
            return il_type_i32();
        }
        case EXPR_FLOAT: {
            if (expr->type) return expr->type;
            return il_type_f64();
        }
        case EXPR_BOOL: {
            return il_type_bool();
        }
        case EXPR_STRING: {
            const ILType* u8_ty = il_type_u8();
            if (!u8_ty) return NULL;
            return il_type_slice(u8_ty, REGION_STATIC, false);
        }
        case EXPR_STRUCT: {
            const ILTypeDef* def = find_type_def(ctx, expr->as.struct_expr.name);
            if (!def || def->is_generic) return NULL;
            return il_type_struct(expr->as.struct_expr.name, def->id);
        }
        case EXPR_UNARY: {
            if (strcmp(expr->as.unary.op, "&") == 0) {
                const ILType* inner = guess_type_internal(ctx, expr->as.unary.expr, (expected_type && expected_type->kind == IL_TY_PTR) ? expected_type->as.ptr.pointee : NULL);
                if (inner) {
                    const ILType* ty = il_type_ptr(inner, REGION_LOCAL, expr->as.unary.is_mut);
                    return ty;
                }
            } else if (strcmp(expr->as.unary.op, "*") == 0) {
                const ILType* inner = guess_type_internal(ctx, expr->as.unary.expr, NULL);
                if (inner && (inner->kind == IL_TY_PTR || inner->kind == IL_TY_BOX)) {
                    return (inner->kind == IL_TY_PTR) ? inner->as.ptr.pointee : inner->as.box.pointee;
                }
            }
            break;
        }
        case EXPR_CALL: {
            if (expr->as.call.receiver && expr->as.call.receiver->kind == EXPR_VAR) {
                // Could be a variant constructor like MyOption.Some
                const char* type_name = expr->as.call.receiver->as.var.name;
                const ILTypeDef* def = find_type_def(ctx, type_name);
                if (def && def->is_sum) {
                    const ILType* m_ty = guess_static_method_type(ctx, type_name, expr->as.call.name);
                    if (m_ty) return m_ty;
                    char full_name[256];
                    snprintf(full_name, sizeof(full_name), "%s.%s", type_name, expr->as.call.name);
                    const ILType ** v_type_args = NULL;
                    if (expr->as.call.receiver->as.var.type_arg_count > 0) {
                        v_type_args = calloc(expr->as.call.receiver->as.var.type_arg_count, sizeof(const ILType*));
                        for (uint32_t j = 0; j < expr->as.call.receiver->as.var.type_arg_count; j++) {
                            v_type_args[j] = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, (const ILType*)expr->as.call.receiver->as.var.type_args[j], ctx->current_substs);
                        }
                    } else if (expr->as.call.type_arg_count > 0) {
                        v_type_args = calloc(expr->as.call.type_arg_count, sizeof(const ILType*));
                        for (uint32_t j = 0; j < expr->as.call.type_arg_count; j++) {
                            v_type_args[j] = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, (const ILType*)expr->as.call.type_args[j], ctx->current_substs);
                        }
                    }
                    uint32_t v_type_arg_count = (expr->as.call.receiver->as.var.type_arg_count > 0) ? expr->as.call.receiver->as.var.type_arg_count : expr->as.call.type_arg_count;
                    const ILType* res = guess_variant_type(ctx, full_name, (const Expression**)expr->as.call.args, expr->as.call.arg_count, expected_type, v_type_args, v_type_arg_count);
                    if (v_type_args) free((void*)v_type_args);
                    return res;
                }
            }
            if (expr->as.call.name) {
                if (strcmp(expr->as.call.name, "@syscall") == 0) return il_type_i64();
                if (strcmp(expr->as.call.name, "@slice") == 0) {
                    const ILType* ptr_ty = guess_type_internal(ctx, expr->as.call.args[0], NULL);
                    if (ptr_ty && ptr_ty->kind == IL_TY_PTR) {
                        return il_type_slice(ptr_ty->as.ptr.pointee, ptr_ty->as.ptr.region_id, ptr_ty->as.ptr.is_mut);
                    }
                }
                
                const char* dot = strchr(expr->as.call.name, '.');
                if (dot) {
                    // Could be variant constructor or static method
                    char type_name[128];
                    size_t len = (size_t)(dot - expr->as.call.name);
                    if (len >= sizeof(type_name)) len = sizeof(type_name) - 1;
                    strncpy(type_name, expr->as.call.name, len);
                    type_name[len] = '\0';
                    const ILTypeDef* def = find_type_def(ctx, type_name);
                    if (def && def->is_sum) {
                        const ILType* m_ty = guess_static_method_type(ctx, type_name, dot + 1);
                        if (m_ty) return m_ty;
                        return guess_variant_type(ctx, expr->as.call.name, (const Expression**)expr->as.call.args, expr->as.call.arg_count, expected_type, NULL, 0);
                    }
                }

                for (uint32_t i = 0; i < ctx->surface_mod->function_count; i++) {
                    const FunctionDecl* sfn = ctx->surface_mod->functions[i];
                    if (sfn->name && strcmp(sfn->name, expr->as.call.name) == 0) {
                        if (sfn->type_param_count == 0) {
                            return lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, sfn->return_type, NULL);
                        } else {
                            return guess_generic_call_return_type(ctx, sfn, &expr->as.call);
                        }
                    }
                }
            }
            break;
        }
        case EXPR_INDEX: {
            const ILType* left_ty = guess_type_internal(ctx, expr->as.index_expr.left, NULL);
            if (left_ty) {
                const ILType* vec_elem = NULL;
                if (is_vec_type(left_ty, &vec_elem)) return vec_elem;
                if (left_ty->kind == IL_TY_ARRAY) return left_ty->as.array.element;
                if (left_ty->kind == IL_TY_SLICE) return left_ty->as.slice.element;
                if (left_ty->kind == IL_TY_PTR && left_ty->as.ptr.pointee) {
                    if (left_ty->as.ptr.pointee->kind == IL_TY_ARRAY) return left_ty->as.ptr.pointee->as.array.element;
                    if (left_ty->as.ptr.pointee->kind == IL_TY_SLICE) return left_ty->as.ptr.pointee->as.slice.element;
                    return left_ty->as.ptr.pointee;
                }
            }
            break;
        }
        case EXPR_CAST: {
            SourceLocation cast_loc = { .file_path = ctx->current_file, .source = ctx->current_source, .line = (uint16_t)ctx->current_line, .col = (uint16_t)ctx->current_col, .offset = ctx->current_offset };
            return lower_type_with_loc(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, expr->as.cast_expr.target_type, ctx->current_substs, cast_loc);
        }
        case EXPR_VAR: {
            const Symbol* sym = symbol_lookup_ctx(ctx, expr->as.var.name);
            if (sym) {
                if (sym->is_lvalue && sym->value.type && (sym->value.type->kind == IL_TY_PTR || sym->value.type->kind == IL_TY_BOX)) {
                    return sym->value.type->as.ptr.pointee;
                }
                return sym->value.type;
            }
            // If not a symbol, check if it's a type name or a variant constructor
            if (strchr(expr->as.var.name, '.')) {
                return guess_variant_type(ctx, expr->as.var.name, NULL, 0, expected_type, NULL, 0);
            }

            for (uint32_t i = 0; i < ctx->surface_mod->type_def_count; i++) {
                const TypeDef* styp = ctx->surface_mod->type_defs[i];
                const char* sname = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->name : styp->as.enum_decl->name;
                if (strcmp(sname, expr->as.var.name) == 0) {
                    const ILType ** type_args = NULL;
                    if (expr->as.var.type_arg_count > 0) {
                        type_args = calloc(expr->as.var.type_arg_count, sizeof(const ILType*));
                        if (type_args) {
                            for (uint32_t j = 0; j < expr->as.var.type_arg_count; j++) {
                                type_args[j] = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, expr->as.var.type_args[j], ctx->current_substs);
                            }
                        }
                    }

                    const ILType* t = (styp->kind == TYPE_DEF_STRUCT) 
                        ? il_type_struct_gen(sname, 0, type_args, expr->as.var.type_arg_count) 
                        : il_type_sum_gen(sname, 0, type_args, expr->as.var.type_arg_count);
                    
                    if (type_args) free(type_args);
                    if (!t) break;
                    
                    const ILType* resolved = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, t, ctx->current_substs);
                    if (resolved != t) {
                        return resolved;
                    }
                    return t;
                }
            }
            break;
        }
        case EXPR_MEMBER: {
            // Resolve the field type for compound assignments like `self.len += 1`.
            const ILType* obj_ty = guess_type_internal(ctx, expr->as.member.object, NULL);
            if (obj_ty) {
                const ILType* struct_ty = obj_ty;
                if (obj_ty->kind == IL_TY_PTR) struct_ty = obj_ty->as.ptr.pointee;
                else if (obj_ty->kind == IL_TY_BOX) struct_ty = obj_ty->as.box.pointee;
                if (struct_ty && struct_ty->kind == IL_TY_STRUCT) {
                    const ILTypeDef* def = il_mod_get_type_def(ctx->module, struct_ty->as.struct_sum.type_def_id);
                    if (def) {
                        int idx = find_field_index(def, expr->as.member.field_name);
                        if (idx >= 0) return def->fields[idx].type;
                    }
                }
            }
            break;
        }
        default: break;
    }
    return NULL;
}

const ILType* guess_type(LowerContext* ctx, const Expression* expr) {
    return guess_type_internal(ctx, expr, NULL);
}

static ILValue lower_builtin_call(LowerContext* ctx, const CallExpr* expr, ILValue dest_ptr) {
    (void)dest_ptr;
    if (strcmp(expr->name, "@alloca") == 0) {
        if (expr->type_arg_count < 1) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@alloca expects 1 type argument");
            return (ILValue){0};
        }
        const ILType* ty = expr->type_args[0];
        // For @alloca, we return a pointer to the allocated type.
        // We use the 'local region.
        const ILType* ptr_ty = il_type_ptr(ty, REGION_LOCAL, true);
        return emit(ctx, il_build_alloc(REGION_LOCAL, ty, ptr_ty, (ILValue){0}));
    }
    if (strcmp(expr->name, "@drop") == 0) {
        if (expr->arg_count < 1) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@drop expects 1 argument");
            return (ILValue){0};
        }
        ILValue val = lower_expression(ctx, expr->args[0], NULL, (ILValue){0});
        emit_drop_dispatch(ctx, val);
        mark_moved(ctx, val.id);
        return (ILValue){ .id = 0, .type = il_type_unit() };
    }
    if (strcmp(expr->name, "@syscall") == 0) {
        if (expr->arg_count < 1) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@syscall expects at least 1 argument (syscall number)");
            return (ILValue){0};
        }
        uint32_t sys_num = 0;
        uint64_t cval = 0;
        if (eval_const_int(ctx->surface_mod, expr->args[0], &cval)) {
            sys_num = (uint32_t)cval;
        } else if (expr->args[0]->kind == EXPR_VAR) {
            for (uint32_t i = 0; i < ctx->surface_mod->global_count; i++) {
                const GlobalDecl* g = ctx->surface_mod->globals[i];
                if (g->is_const && g->name && strcmp(g->name, expr->args[0]->as.var.name) == 0) {
                    if (g->init && eval_const_int(ctx->surface_mod, g->init, &cval)) {
                        sys_num = (uint32_t)cval;
                        break;
                    }
                }
            }
        }
        uint32_t arg_count = expr->arg_count - 1;
        ILValue* args = NULL;
        if (arg_count > 0) {
            args = calloc(arg_count, sizeof(ILValue));
            if (!args) abort();
            for (uint32_t i = 0; i < arg_count; i++) args[i] = lower_expression(ctx, expr->args[i + 1], NULL, (ILValue){0});
        }
        const ILType * i64_ty = il_type_i64();
        ILValue res = emit(ctx, il_build_syscall(sys_num, args, arg_count, i64_ty));
        free(args);
        return res;
    }
    if (strcmp(expr->name, "@slice") == 0) {
        if (expr->arg_count < 2) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@slice expects 2 arguments (ptr, len)");
            return (ILValue){0};
        }
        ILValue ptr = lower_expression(ctx, expr->args[0], NULL, (ILValue){0});
        ILValue len = lower_expression(ctx, expr->args[1], NULL, (ILValue){0});
        len = ensure_usize(ctx, len);

        if (!ptr.type || ptr.type->kind != IL_TY_PTR) {
            emit_diag_at(ctx, DIAG_ERROR, expr->args[0], "@slice expects first argument to be a pointer");
            return (ILValue){0};
        }

        const ILType* slice_ty = il_type_slice(ptr.type->as.ptr.pointee, ptr.type->as.ptr.region_id, ptr.type->as.ptr.is_mut);
        ILValue res = emit(ctx, il_build_slice_construct(ptr, len, slice_ty));
        return res;
    }
    if (strcmp(expr->name, "@likely") == 0 || strcmp(expr->name, "@unlikely") == 0) {
        if (expr->arg_count < 1) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "%s expects 1 argument", expr->name);
            return (ILValue){0};
        }
        return lower_expression(ctx, expr->args[0], NULL, (ILValue){0});
    }
    if (strcmp(expr->name, "@saturating_add") == 0) {
        if (expr->arg_count != 2) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@saturating_add expects 2 arguments");
            return (ILValue){0};
        }
        ILValue left = lower_expression(ctx, expr->args[0], NULL, (ILValue){0});
        ILValue right = lower_expression(ctx, expr->args[1], NULL, (ILValue){0});
        if (!left.type || !right.type) return (ILValue){0};
        return emit(ctx, il_build_saturating_add(left, right));
    }
    if (strcmp(expr->name, "@region_cast") == 0) {
        if (expr->arg_count != 1) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@region_cast expects 1 argument");
            return (ILValue){0};
        }
        if (expr->type_arg_count != 1) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@region_cast expects 1 type argument (e.g. @region_cast<Ptr<u8, 'static>>)");
            return (ILValue){0};
        }
        const ILType* target_ty = expr->type_args[0];
        target_ty = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, target_ty, ctx->current_substs);
        if (!target_ty) return (ILValue){0};

        ILValue val = lower_expression(ctx, expr->args[0], target_ty, (ILValue){0});
        if (!val.type) return (ILValue){0};

        if (val.type->kind != IL_TY_PTR || target_ty->kind != IL_TY_PTR) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@region_cast can only be used on raw/borrow pointers");
            return (ILValue){0};
        }
        
        uint32_t target_region = target_ty->as.ptr.region_id;
        ILValue res = emit(ctx, il_build_region_cast(val, target_region));
        res.type = target_ty;
        return res;
    }
    if (strcmp(expr->name, "@fd_open") == 0) {
        if (expr->arg_count != 3) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@fd_open expects 3 arguments: path, flags, mode");
            return (ILValue){0};
        }
        ILValue path = lower_expression(ctx, expr->args[0], NULL, (ILValue){0});
        ILValue flags_val = lower_expression(ctx, expr->args[1], NULL, (ILValue){0});
        ILValue mode_val = lower_expression(ctx, expr->args[2], NULL, (ILValue){0});
        
        uint64_t const_flags = 0;
        uint8_t caps = 3; // default: read/write
        if (eval_const_int(ctx->surface_mod, expr->args[1], &const_flags)) {
            if ((const_flags & 3) == 0) caps = 1; // O_RDONLY
            else if ((const_flags & 3) == 1) caps = 2; // O_WRONLY
        }
        
        const ILType* fd_ty = il_type_fd(caps);
        
        return emit(ctx, il_build_fd_open(path, flags_val, mode_val, fd_ty));
    }
    if (strcmp(expr->name, "@fd_close") == 0) {
        if (expr->arg_count != 1) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@fd_close expects 1 argument: fd");
            return (ILValue){0};
        }
        ILValue fd = lower_expression_move(ctx, expr->args[0], NULL, (ILValue){0});
        if (!fd.type) return (ILValue){0};
        
        emit(ctx, il_build_fd_close(fd));
        return (ILValue){ .id = 0, .type = il_type_unit() };
    }
    if (strcmp(expr->name, "@fd_read") == 0) {
        if (expr->arg_count != 3) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@fd_read expects 3 arguments: fd, buf, count");
            return (ILValue){0};
        }
        ILValue fd = lower_expression_internal(ctx, expr->args[0], NULL, false, (ILValue){0}, false, false);
        ILValue buf = lower_expression(ctx, expr->args[1], NULL, (ILValue){0});
        ILValue count = lower_expression(ctx, expr->args[2], NULL, (ILValue){0});
        if (!fd.type || !buf.type || !count.type) return (ILValue){0};
        
        return emit(ctx, il_build_fd_read(fd, buf, count, il_type_i64()));
    }
    if (strcmp(expr->name, "@fd_write") == 0) {
        if (expr->arg_count != 3) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@fd_write expects 3 arguments: fd, buf, count");
            return (ILValue){0};
        }
        ILValue fd = lower_expression_internal(ctx, expr->args[0], NULL, false, (ILValue){0}, false, false);
        ILValue buf = lower_expression(ctx, expr->args[1], NULL, (ILValue){0});
        ILValue count = lower_expression(ctx, expr->args[2], NULL, (ILValue){0});
        if (!fd.type || !buf.type || !count.type) return (ILValue){0};
        
        return emit(ctx, il_build_fd_write(fd, buf, count, il_type_i64()));
    }
    if (strcmp(expr->name, "@fd_from_raw") == 0) {
        if (expr->arg_count != 1) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@fd_from_raw expects 1 argument: fd_val");
            return (ILValue){0};
        }
        ILValue val = lower_expression(ctx, expr->args[0], NULL, (ILValue){0});
        if (!val.type) return (ILValue){0};
        
        return emit(ctx, il_build_bitcast(val, il_type_fd(IL_CAP_RW)));
    }
    if (strcmp(expr->name, "@async_setup") == 0) {
        if (expr->arg_count != 1) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@async_setup expects 1 argument: entries");
            return (ILValue){0};
        }
        ILValue entries = lower_expression(ctx, expr->args[0], NULL, (ILValue){0});
        if (!entries.type) return (ILValue){0};
        return emit(ctx, il_build_async_setup(entries, il_type_async_context()));
    }
    if (strcmp(expr->name, "@async_enter") == 0) {
        if (expr->arg_count != 3) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@async_enter expects 3 arguments: ctx, to_submit, min_complete");
            return (ILValue){0};
        }
        ILValue async_ctx = lower_expression_internal(ctx, expr->args[0], NULL, false, (ILValue){0}, false, false);
        ILValue to_submit = lower_expression(ctx, expr->args[1], NULL, (ILValue){0});
        ILValue min_complete = lower_expression(ctx, expr->args[2], NULL, (ILValue){0});
        if (!async_ctx.type || !to_submit.type || !min_complete.type) return (ILValue){0};
        return emit(ctx, il_build_async_enter(async_ctx, to_submit, min_complete, il_type_i64()));
    }
    if (strcmp(expr->name, "@async_close") == 0) {
        if (expr->arg_count != 1) {
            emit_diag_at(ctx, DIAG_ERROR, NULL, "@async_close expects 1 argument: ctx");
            return (ILValue){0};
        }
        ILValue async_ctx = lower_expression_move(ctx, expr->args[0], NULL, (ILValue){0});
        if (!async_ctx.type) return (ILValue){0};
        emit(ctx, il_build_async_close(async_ctx));
        return (ILValue){ .id = 0, .type = il_type_unit() };
    }
    emit_diag_at(ctx, DIAG_ERROR, NULL, "Unknown built-in: %s", expr->name);
    return (ILValue){0};
}

static ILValue lower_closure_call(LowerContext* ctx, const CallExpr* expr, ILValue callee_val, ILValue dest_ptr) {
    const ILType* pointee = NULL;
    if (callee_val.type->kind == IL_TY_FN) {
        pointee = callee_val.type;
    } else if (callee_val.type->kind == IL_TY_PTR || callee_val.type->kind == IL_TY_BOX) {
        pointee = (callee_val.type->kind == IL_TY_PTR) ? callee_val.type->as.ptr.pointee : callee_val.type->as.box.pointee;
    }

    if (!pointee) return (ILValue){0};

    const ILType* fn_ty = NULL;
    if (pointee->kind == IL_TY_FN) {
        fn_ty = pointee;
    } else if (pointee->kind == IL_TY_STRUCT || pointee->kind == IL_TY_SUM) {
        const ILTypeDef* def = il_mod_get_type_def(ctx->module, pointee->as.struct_sum.type_def_id);
        if (def && def->field_count > 0) {
            fn_ty = def->fields[0].type;
        }
    }

    if (!fn_ty || fn_ty->kind != IL_TY_FN) return (ILValue){0};

    ILValue fn_ptr_val;
    if (callee_val.type->kind == IL_TY_FN) {
        fn_ptr_val = (ILValue){ .id = callee_val.id, .type = callee_val.type };
    } else {
        bool is_mut = (callee_val.type->kind == IL_TY_PTR) ? callee_val.type->as.ptr.is_mut : callee_val.type->as.box.is_mut;
        const ILType* fn_ptr_ptr_ty = il_type_ptr(fn_ty, REGION_LOCAL, is_mut);
        ILValue fn_ptr_addr = emit(ctx, il_build_field_addr(callee_val, 0, fn_ptr_ptr_ty));
        fn_ptr_val = emit(ctx, il_build_load(fn_ptr_addr));
    }

    bool is_sret = requires_pass_by_ref(ctx->module, fn_ty->as.function.return_type);
    uint32_t total_args = expr->arg_count + 1 + (is_sret ? 1 : 0);
    ILValue* args = calloc(total_args, sizeof(ILValue));
    if (!args && total_args > 0) abort();
    
    uint32_t arg_idx = 0;
    ILValue sret_ptr = {0};
    if (is_sret) {
        if (dest_ptr.id != 0) {
            sret_ptr = dest_ptr;
        } else {
            const ILType* ret_ty = fn_ty->as.function.return_type;
            const ILType* ptr_ty = il_type_ptr(ret_ty, REGION_LOCAL, true);
            sret_ptr = emit(ctx, il_build_alloc(REGION_LOCAL, ret_ty, ptr_ty, (ILValue){0}));
        }
        args[arg_idx++] = (ILValue){ .id = sret_ptr.id, .type = sret_ptr.type };
    }

    args[arg_idx++] = (ILValue){ .id = callee_val.id, .type = il_type_ptr(il_type_unit(), REGION_STATIC, false) };
    
    for (uint32_t i = 0; i < expr->arg_count; i++) {
        uint32_t cur_idx = arg_idx++;
        const ILType* target_arg_ty = (i + 1 < fn_ty->as.function.param_count) ? fn_ty->as.function.param_types[i + 1] : NULL;
        args[cur_idx] = lower_expression(ctx, expr->args[i], target_arg_ty, (ILValue){0});
        if (target_arg_ty) {
            ILValue assigned = ensure_assignable(ctx, args[cur_idx], target_arg_ty);
            if (assigned.id != args[cur_idx].id || assigned.type != args[cur_idx].type) {
            }
            args[cur_idx] = assigned;
        }
    }

    ILInstruction* call = il_build_call_ptr(fn_ptr_val, args, total_args, is_sret ? il_type_unit() : fn_ty->as.function.return_type);
    ILValue call_res = emit(ctx, call);

    // If the closure moves a capture, it can only be called once.
    // Check the function signature for any non-copy captures (passed by value).
    // The environment struct fields 2..N correspond to captures.
    bool moves_capture = false;
    const ILType* env_pointee = NULL;
    if (callee_val.type->kind == IL_TY_PTR || callee_val.type->kind == IL_TY_BOX) {
        env_pointee = (callee_val.type->kind == IL_TY_PTR) ? callee_val.type->as.ptr.pointee : callee_val.type->as.box.pointee;
        if (env_pointee && env_pointee->kind == IL_TY_STRUCT) {
            const ILTypeDef* def = il_mod_get_type_def(ctx->module, env_pointee->as.struct_sum.type_def_id);
            if (def) {
                for (uint32_t i = 2; i < def->field_count; i++) {
                    if (!il_type_is_copy_mod(ctx->module, def->fields[i].type)) {
                        moves_capture = true;
                        break;
                    }
                }
            }
        }
    }
    
    if (moves_capture && callee_val.id != 0) {
        mark_moved(ctx, callee_val.id);
    }

    ILValue res;
    if (is_sret) {
        if (dest_ptr.id != 0) {
            res = (ILValue){ .id = sret_ptr.id, .type = fn_ty->as.function.return_type };
        } else {
            res = emit(ctx, il_build_load(sret_ptr));
        }
    } else {
        res = call_res;
    }

    free(args);    return res;
}

// Construct a tuple value in memory from multiple argument expressions.
// Returns the loaded tuple ILValue, or {0} on failure.
static ILValue lower_tuple_from_args(LowerContext* ctx, const Expression** args, uint32_t arg_count, const ILType* payload_ty) {
    const ILType* tuple_ty = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, payload_ty, ctx->current_substs);
    if (!tuple_ty || tuple_ty->as.struct_sum.type_def_id == 0) return (ILValue){0};
    const ILTypeDef* tuple_def = il_mod_get_type_def(ctx->module, tuple_ty->as.struct_sum.type_def_id);
    if (!tuple_def) return (ILValue){0};

    const ILType* ptr_ty = il_type_ptr(tuple_ty, REGION_LOCAL, true);
    ILValue tuple_ptr = emit(ctx, il_build_alloc(REGION_LOCAL, tuple_ty, ptr_ty, (ILValue){0}));
    for (uint32_t i = 0; i < arg_count && i < tuple_def->field_count; i++) {
        const ILType* field_ty = tuple_def->fields[i].type;
        ILValue elem = lower_expression_move(ctx, args[i], field_ty, (ILValue){0});
        if (!elem.type) continue;
        ILValue stored = ensure_assignable(ctx, elem, field_ty);
        const ILType* field_ptr_ty = il_type_ptr(field_ty, REGION_LOCAL, true);
        ILValue field_ptr = emit(ctx, il_build_field_addr(tuple_ptr, i, field_ptr_ty));
        emit_void(ctx, il_build_store(field_ptr, stored));
    }
    return emit(ctx, il_build_load(tuple_ptr));
}

static ILValue lower_variant_construct(LowerContext* ctx, const ILTypeDef* def, const char* variant_name, const Expression** args, uint32_t arg_count, const ILType ** type_args, uint32_t type_arg_count, const ILType* expected_type, ILValue dest_ptr) {
    (void)dest_ptr;
    if (!def) return (ILValue){0};
    const Expression* arg = (arg_count > 0) ? args[0] : NULL;

    const ILType* sum_ty = NULL;
    const ILType** inferred_args = NULL;

    // If generic, ensure we use the monomorphized definition so fields have concrete types
    if (def->is_generic) {
        // Find surface TypeDef to get type parameters
        const TypeDef* styp = NULL;
        for (uint32_t i = 0; i < ctx->surface_mod->type_def_count; i++) {
            const TypeDef* td = ctx->surface_mod->type_defs[i];
            const char* sname = (td->kind == TYPE_DEF_STRUCT) ? td->as.struct_decl->name : td->as.enum_decl->name;
            if (strcmp(sname, def->name) == 0) { styp = td; break; }
        }
        
        if (styp && styp->kind == TYPE_DEF_ENUM) {
            uint32_t tpc = styp->as.enum_decl->type_param_count;
            inferred_args = calloc(tpc, sizeof(const ILType*));
            
            // 1. Copy provided type args
            for (uint32_t i = 0; i < type_arg_count && i < tpc; i++) {
                inferred_args[i] = type_args[i];
            }
            
            // 2. Infer from expected type
            const ILType* exp = expected_type;
            if (exp && exp->kind == IL_TY_PTR) exp = exp->as.ptr.pointee;
            
            if (exp && (exp->kind == IL_TY_SUM || exp->kind == IL_TY_STRUCT)) {
                 const ILType* concrete_exp = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, (const ILType*)exp, ctx->current_substs);
                 if (concrete_exp && (concrete_exp->kind == IL_TY_SUM || concrete_exp->kind == IL_TY_STRUCT) && concrete_exp->as.struct_sum.name) {
                     // Check if it matches our enum name (either base or mangled)
                     const char* exp_name = concrete_exp->as.struct_sum.name;
                     bool name_match = (strcmp(exp_name, def->name) == 0);
                     if (!name_match && strncmp(exp_name, def->name, strlen(def->name)) == 0 && exp_name[strlen(def->name)] == '_') {
                         name_match = true;
                     }
                     
                     if (name_match && concrete_exp->as.struct_sum.type_arg_count == tpc) {
                         for (uint32_t i = 0; i < tpc; i++) {
                             if (!inferred_args[i]) inferred_args[i] = concrete_exp->as.struct_sum.type_args[i];
                         }
                     }
                 }
            }
            
            // 3. Infer from arguments
            int v_idx = -1;
            for (uint32_t i = 0; i < styp->as.enum_decl->variant_count; i++) {
                if (strcmp(styp->as.enum_decl->variants[i].name, variant_name) == 0) { v_idx = (int)i; break; }
            }
            if (v_idx >= 0) {
                const ILType* variant_payload_ty = styp->as.enum_decl->variants[v_idx].type;
                for (uint32_t k = 0; k < tpc; k++) {
                    if (inferred_args[k]) continue;
                    if (arg_count > 1 && variant_payload_ty && variant_payload_ty->kind == IL_TY_TUPLE) {
                        for (uint32_t j = 0; j < variant_payload_ty->as.tuple.count && j < arg_count; j++) {
                            const ILType* gty = guess_type_internal(ctx, args[j], NULL);
                            if (match_type_param(ctx, variant_payload_ty->as.tuple.elements[j], gty, styp->as.enum_decl->type_params[k], &inferred_args[k])) break;
                        }
                    } else if (arg) {
                        const ILType* gty = guess_type_internal(ctx, arg, NULL);
                        match_type_param(ctx, variant_payload_ty, gty, styp->as.enum_decl->type_params[k], &inferred_args[k]);
                    }
                }
            }
            
            // 4. Fallback to unit
            for (uint32_t i = 0; i < tpc; i++) if (!inferred_args[i]) inferred_args[i] = il_type_unit();
            
            sum_ty = il_type_sum_gen(def->name, 0, inferred_args, tpc);
            const ILType* resolved = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, sum_ty, ctx->current_substs);
            if (resolved && (resolved->kind == IL_TY_SUM || resolved->kind == IL_TY_STRUCT) && resolved->as.struct_sum.type_def_id != 0) {
                sum_ty = resolved;
                def = il_mod_get_type_def(ctx->module, resolved->as.struct_sum.type_def_id);
            }
        }
    } else {
        sum_ty = il_type_sum_gen(def->name, def->id, type_args, type_arg_count);
    }

    if (!def || !sum_ty) { if (inferred_args) free(inferred_args); return (ILValue){0}; }

    int v_idx = find_field_index(def, variant_name);
    if (v_idx < 0) { if (inferred_args) free(inferred_args); return (ILValue){0}; }

    ILValue payload = {0};
    if (arg_count > 1) {
        payload = lower_tuple_from_args(ctx, args, arg_count, def->fields[v_idx].type);
    } else if (arg) {
        payload = lower_expression_move(ctx, arg, def->fields[v_idx].type, (ILValue){0});
    } else {
        payload = (ILValue){ .id = 0, .type = il_build_unit_type() };
    }

    ILInstruction* construct = il_build_sum_construct(def->id, (uint32_t)v_idx, payload, sum_ty);
    ILValue res = emit(ctx, construct);
    if (payload.type && !il_type_is_copy_mod(ctx->module, payload.type)) mark_moved(ctx, payload.id);

    if (dest_ptr.id != 0) {
        emit_void(ctx, il_build_store(dest_ptr, res));
        if (!il_type_is_copy_mod(ctx->module, res.type)) mark_moved(ctx, res.id);
        res = (ILValue){ .id = dest_ptr.id, .type = sum_ty };
    }

    if (inferred_args) free(inferred_args);
    return res;
}

static bool is_lvalue_receiver(const Expression* expr) {
    if (!expr) return false;
    if (expr->kind == EXPR_VAR || expr->kind == EXPR_MEMBER || expr->kind == EXPR_INDEX) {
        return true;
    }
    if (expr->kind == EXPR_UNARY && strcmp(expr->as.unary.op, "*") == 0) {
        return true;
    }
    return false;
}

static ILValue prepare_self_arg(LowerContext* ctx, ILValue self_val, const ILType* expected_self_ty) {
    if (!expected_self_ty || !self_val.type) return self_val;

    // 0. Box to Pointer conversion: Zoril automatically dereferences boxes for method calls.
    if (self_val.type->kind == IL_TY_BOX && expected_self_ty->kind != IL_TY_BOX) {
        const ILType* inner_ty = self_val.type->as.box.pointee;
        const ILType* ptr_ty = il_type_ptr(inner_ty, self_val.type->as.box.region_id, self_val.type->as.box.is_mut);
        ILValue ptr = emit(ctx, il_build_bitcast(self_val, ptr_ty));
        self_val = ptr;
    }

    // 1. Double indirection: we have Ptr<Ptr<T>> but need Ptr<T> (or similar with Box).
    // This happens when the receiver is an lvalue variable whose type is already a pointer.
    if (expected_self_ty->kind == IL_TY_PTR) {
        while (self_val.type->kind == IL_TY_PTR && self_val.type->as.ptr.pointee->kind == IL_TY_PTR) {
            if (il_type_is_assignable(self_val.type, expected_self_ty)) break;
            
            ILValue loaded = emit(ctx, il_build_load(self_val));
            self_val = loaded;
        }
    }

    // 2. Promotion to stack: we have T but need Ptr<T>
    if (expected_self_ty->kind == IL_TY_PTR &&
            self_val.type->kind != IL_TY_PTR && self_val.type->kind != IL_TY_BOX) {
        
        uint32_t target_region = expected_self_ty->as.ptr.region_id;
        const ILType* ptr_ty = il_type_ptr(self_val.type, target_region, true);
        ILValue tmp = emit(ctx, il_build_alloc(target_region, self_val.type, ptr_ty, (ILValue){0}));
        emit_void(ctx, il_build_store(tmp, self_val));
        self_val = tmp;
    }

    // 3. Pass by value: we have Ptr<T> but need T
    if (expected_self_ty->kind != IL_TY_PTR && expected_self_ty->kind != IL_TY_BOX &&
        (self_val.type->kind == IL_TY_PTR || self_val.type->kind == IL_TY_BOX)) {
        if (il_type_eq(self_val.type->kind == IL_TY_PTR ? self_val.type->as.ptr.pointee : self_val.type->as.box.pointee, expected_self_ty)) {
            self_val = emit(ctx, il_build_load(self_val));
        }
    }

    return self_val;
}


bool is_mut_borrow(const ILType* t) {
    if (!t) return false;
    if (t->kind == IL_TY_PTR) return t->as.ptr.is_mut;
    if (t->kind == IL_TY_BOX) return t->as.box.is_mut;
    if (t->kind == IL_TY_SLICE) return t->as.slice.is_mut;
    return false;
}

static const ILTypeDef* lower_method_trait_match(LowerContext* ctx, const ILType* struct_ty, const CallExpr* expr, const ILFunction** out_target_fn, char* mname, size_t mname_len) {
    const ILTypeDef* def = NULL;
    if (struct_ty && (struct_ty->kind == IL_TY_STRUCT || struct_ty->kind == IL_TY_SUM)) {
        if (struct_ty->as.struct_sum.type_def_id != 0) {
            def = il_mod_get_type_def(ctx->module, struct_ty->as.struct_sum.type_def_id);
        } else {
            // It's a generic parameter! Look up its bound.
            const char* param_name = struct_ty->as.struct_sum.name;
            const char* bound_trait = NULL;
            const ILType* concrete_ty = NULL;
            
            const Substitution* s = ctx->current_substs;
            while (s) {
                if (strcmp(s->name, param_name) == 0) {
                    bound_trait = s->bound;
                    concrete_ty = s->type;
                    break;
                }
                s = s->next;
            }
            
            if (!bound_trait && ctx->current_surface_func) {
                for (uint32_t i = 0; i < ctx->current_surface_func->type_param_count; i++) {
                    if (strcmp(ctx->current_surface_func->type_params[i], param_name) == 0) {
                        bound_trait = ctx->current_surface_func->type_bounds[i];
                        break;
                    }
                }
            }
            
            if (bound_trait) {
                if (concrete_ty) {
                    // We have a concrete type, so we can look up Trait_Type_Method
                    const char* type_suffix = type_to_suffix(concrete_ty);
                    snprintf(mname, mname_len, "%s_%s_%s", bound_trait, type_suffix, expr->name);
                    const ILFunction* target_fn = il_mod_get_func_by_name(ctx->module, mname);
                    if (target_fn) {
                        *out_target_fn = target_fn;
                        return NULL;
                    }
                }
                def = find_type_def(ctx, bound_trait);
            }
        }
    }
    return def;
}

static ILValue lower_method_call(LowerContext* ctx, const CallExpr* expr, const ILType* expected_type, ILValue dest_ptr) {
    (void)dest_ptr;
    const ILTypeDef* static_def = NULL;
    const ILType* struct_ty = NULL;
    char mname[512];
    const ILFunction* target_fn = NULL;
    const ILType ** type_args = NULL;
    uint32_t type_arg_count = 0;
    bool needs_free_type_args = false;
    const ILType ** method_type_args = NULL;
    uint32_t method_type_arg_count = 0;

    if (expr->receiver->kind == EXPR_VAR) {
        if (expected_type && (expected_type->kind == IL_TY_SUM || expected_type->kind == IL_TY_STRUCT) && expected_type->as.struct_sum.type_def_id != 0) {
            const char* exp_name = expected_type->as.struct_sum.name;
            const char* rec_name = expr->receiver->as.var.name;
            const ILTypeDef* exp_def = il_mod_get_type_def(ctx->module, expected_type->as.struct_sum.type_def_id);
            
            bool match = false;
            if (exp_def && strcmp(exp_def->name, rec_name) == 0) match = true;
            else if (exp_name) {
                const char* underscore = strchr(exp_name, '_');
                if (underscore) {
                    size_t base_len = (size_t)(underscore - exp_name);
                    if (strncmp(exp_name, rec_name, base_len) == 0 && rec_name[base_len] == '\0') {
                        match = true;
                    }
                }
            }

            if (match) {
                static_def = il_mod_get_type_def(ctx->module, expected_type->as.struct_sum.type_def_id);
                struct_ty = expected_type;
                type_args = expected_type->as.struct_sum.type_args;
                type_arg_count = expected_type->as.struct_sum.type_arg_count;
            }
        }
        if (!static_def) static_def = find_type_def(ctx, expr->receiver->as.var.name);
    } else if (expr->receiver->kind == EXPR_MEMBER) {
        if (expr->receiver->as.member.type_arg_count > 0) {
            type_arg_count = expr->receiver->as.member.type_arg_count;
            type_args = calloc(type_arg_count, sizeof(const ILType*));
            if (type_args) {
                for (uint32_t i = 0; i < type_arg_count; i++) {
                    type_args[i] = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, expr->receiver->as.member.type_args[i], ctx->current_substs);
                }
                needs_free_type_args = true;
            }
        }
    }
    
    ILValue receiver_val = {0};
    if (!static_def) {
        if (is_lvalue_receiver(expr->receiver)) {
            receiver_val = lower_lvalue(ctx, expr->receiver, true);
        } else {
            receiver_val = lower_expression_internal(ctx, expr->receiver, NULL, false, (ILValue){0}, false, false);
        }
    }

    if (!static_def && !receiver_val.type) {
        if (needs_free_type_args) {
            free(type_args);        }
        return (ILValue){0};
    }

    const ILTypeDef* def = NULL;
    if (static_def) {
        def = static_def;
    } else {
        struct_ty = receiver_val.type;
        while (struct_ty && (struct_ty->kind == IL_TY_PTR || struct_ty->kind == IL_TY_BOX)) {
            // Try matching method on the current pointer/box type itself first (e.g. for methods on Box<T>)
            const ILTypeDef* trait_def = lower_method_trait_match(ctx, struct_ty, expr, &target_fn, mname, sizeof(mname));
            if (target_fn) {
                def = trait_def;
                goto dispatch;
            }

            if (struct_ty->kind == IL_TY_PTR) struct_ty = struct_ty->as.ptr.pointee;
            else struct_ty = struct_ty->as.box.pointee;
        }
        def = lower_method_trait_match(ctx, struct_ty, expr, &target_fn, mname, sizeof(mname));
        if (target_fn) goto dispatch;
    }

    uint32_t struct_param_count = 0;
    const TypeDef* surface_def = NULL;
    if (def) {
        // Find the surface TypeDef to get the actual number of type parameters
        const char* base_name = def->name;
        const char* underscore = strchr(base_name, '_');
        char base_buf[128];
        if (underscore) {
            size_t len = (size_t)(underscore - base_name);
            if (len >= sizeof(base_buf)) len = sizeof(base_buf) - 1;
            strncpy(base_buf, base_name, len);
            base_buf[len] = '\0';
            base_name = base_buf;
        }
        
        for (uint32_t i = 0; i < ctx->surface_mod->type_def_count; i++) {
            const char* name = (ctx->surface_mod->type_defs[i]->kind == TYPE_DEF_STRUCT) ? 
                                ctx->surface_mod->type_defs[i]->as.struct_decl->name : 
                                ctx->surface_mod->type_defs[i]->as.enum_decl->name;
            if (strcmp(name, base_name) == 0) {
                surface_def = ctx->surface_mod->type_defs[i];
                break;
            }
        }
        
        if (surface_def) {
            struct_param_count = (surface_def->kind == TYPE_DEF_STRUCT) ? 
                                 surface_def->as.struct_decl->type_param_count : 
                                 surface_def->as.enum_decl->type_param_count;
        }
    }

    uint32_t struct_type_arg_count = 0;
    const ILType ** struct_type_args = NULL;
    bool needs_free_struct_args = false;
    if (def) {
        if (struct_ty && (struct_ty->kind == IL_TY_STRUCT || struct_ty->kind == IL_TY_SUM) && struct_ty->as.struct_sum.type_arg_count > 0) {
            struct_type_args = struct_ty->as.struct_sum.type_args;
            struct_type_arg_count = struct_ty->as.struct_sum.type_arg_count;
        } else if (static_def && expr->receiver->kind == EXPR_VAR && expr->receiver->as.var.type_arg_count > 0) {
            struct_type_arg_count = expr->receiver->as.var.type_arg_count;
            struct_type_args = calloc(struct_type_arg_count, sizeof(const ILType*));
            for (uint32_t i = 0; i < struct_type_arg_count; i++) {
                struct_type_args[i] = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, expr->receiver->as.var.type_args[i], ctx->current_substs);
            }
            needs_free_struct_args = true;
        } else if (static_def && expr->receiver->kind == EXPR_MEMBER && expr->receiver->as.member.type_arg_count > 0) {
            struct_type_arg_count = expr->receiver->as.member.type_arg_count;
            struct_type_args = calloc(struct_type_arg_count, sizeof(const ILType*));
            for (uint32_t i = 0; i < struct_type_arg_count; i++) {
                struct_type_args[i] = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, expr->receiver->as.member.type_args[i], ctx->current_substs);
            }
            needs_free_struct_args = true;
        } else if (static_def && (static_def->id != 0) && (expected_type && (expected_type->kind == IL_TY_STRUCT || expected_type->kind == IL_TY_SUM) && expected_type->as.struct_sum.type_arg_count > 0)) {
            // Static call to a monomorphized type
            struct_type_args = expected_type->as.struct_sum.type_args;
            struct_type_arg_count = expected_type->as.struct_sum.type_arg_count;
        }
    }

    // Merge struct and method type arguments
    if (expr->type_arg_count > 0) {
        method_type_arg_count = expr->type_arg_count;
        method_type_args = calloc(method_type_arg_count, sizeof(const ILType*));
        if (method_type_args) {
            for (uint32_t i = 0; i < method_type_arg_count; i++) {
                method_type_args[i] = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, expr->type_args[i], ctx->current_substs);
            }
        }
    }

    if (def && def->is_sum) {
        int v_idx = find_field_index(def, expr->name);
        if (v_idx >= 0) {
            // Variant constructors use the enum's type args. 
            // If parsed as `MyOption.None<i32>()`, the args are on the method. Move them to the struct.
            if (method_type_arg_count > 0) {
                if (struct_type_arg_count == 0) {
                    struct_type_arg_count = method_type_arg_count;
                    struct_type_args = method_type_args;
                    method_type_arg_count = 0;
                    method_type_args = NULL;
                    needs_free_struct_args = true;
                } else if (struct_type_arg_count + method_type_arg_count > struct_param_count) {
                    // Redundant turbofish on a variant construct where we already have enough args.
                    // This happens with `MyOption.None<i32>()` when MyOption_i32 was already inferred.
                    method_type_arg_count = 0;
                }
            }
        }
    }

    if (struct_param_count > 0 || method_type_arg_count > 0) {
        type_arg_count = struct_param_count + method_type_arg_count;
        type_args = calloc(type_arg_count, sizeof(const ILType*));

        uint32_t current_idx = 0;
        // Struct args
        for (uint32_t i = 0; i < struct_type_arg_count && i < struct_param_count; i++) {
            if (struct_type_args) type_args[current_idx++] = struct_type_args[i];
        }
        // Skip filling with unit here; lower_variant_construct or monomorphize will handle defaults if needed.
        current_idx = struct_param_count; 

        // Method args
        if (method_type_args) {
            for (uint32_t i = 0; i < method_type_arg_count; i++) {
                type_args[current_idx++] = method_type_args[i];
            }
        }

        needs_free_type_args = true;
    }

    if (needs_free_struct_args) {
        free(struct_type_args);
    }

    if (def && def->is_sum) {
        ILValue res = lower_variant_construct(ctx, def, expr->name, (const Expression**)expr->args, expr->arg_count, type_args, type_arg_count, expected_type, dest_ptr);
        if (res.type) {
            
            if (needs_free_type_args) {
                free(type_args);            }
            if (method_type_args) free(method_type_args);
            return res;
        }
    }

    // For primitive types (i32, u64, etc.) with trait impl methods, try TypeName_method lookup.
    if (!def && struct_ty) {
        char* prim_name = mangle_type(struct_ty);
        if (prim_name) {
            snprintf(mname, sizeof(mname), "%s_%s", prim_name, expr->name);
            free(prim_name);
            target_fn = il_mod_get_func_by_name(ctx->module, mname);
            if (target_fn) goto dispatch;
        }
    }

    if (!def) {
        
        if (needs_free_type_args) {
            free(type_args);        }
        if (method_type_args) free(method_type_args);
        return (ILValue){0};
    }

    // Get the base name of the type (e.g., "Vec" from "Vec_u8")
    {
        const char* base_name = def->name;
        const char* underscore = strchr(base_name, '_');
        char base_name_buf[128];
        if (underscore) {
            size_t len = (size_t)(underscore - base_name);
            if (len >= sizeof(base_name_buf)) len = sizeof(base_name_buf) - 1;
            strncpy(base_name_buf, base_name, len);
            base_name_buf[len] = '\0';
            base_name = base_name_buf;
        }

        if (type_arg_count > 0) {
            // Mangle BOTH struct and method params into the name
            char* struct_mangled = mangle_generic_name(base_name, struct_param_count, type_args);
            if (method_type_arg_count > 0) {
                char* method_mangled = mangle_generic_name(expr->name, method_type_arg_count, type_args + struct_param_count);
                snprintf(mname, sizeof(mname), "%s_%s", struct_mangled, method_mangled);
                free(method_mangled);
            } else {
                snprintf(mname, sizeof(mname), "%s_%s", struct_mangled, expr->name);
            }
            target_fn = il_mod_get_func_by_name(ctx->module, mname);
            if (!target_fn) {
                const ImplDecl* simpl = NULL;
                const FunctionDecl* sfn = find_method_decl(ctx->surface_mod, base_name, expr->name, &simpl);
                if (sfn && simpl) {
                    // Visibility check
                    if (!sfn->is_pub && ctx->current_file && sfn->file_path) {
                        if (strcmp(ctx->current_file, sfn->file_path) != 0) {
                            emit_diag_at(ctx, DIAG_ERROR, expr->receiver, "Access to private method '%s' of type '%s'", expr->name, base_name);
                        }
                    }

                    // Handle trait type arguments if present
                    if (simpl->trait_name) {
                        const TraitDecl* trait = NULL;
                        for (uint32_t i = 0; i < ctx->surface_mod->trait_count; i++) {
                            const char* tname = ctx->surface_mod->traits[i]->name;
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
                                trait = ctx->surface_mod->traits[i];
                                break;
                            }
                        }
                        if (trait && trait->type_param_count > 0) {
                            uint32_t total_expected = struct_param_count + trait->type_param_count + sfn->type_param_count;
                            if (type_arg_count < total_expected) {
                                const ILType ** new_args = calloc(total_expected, sizeof(const ILType*));
                                // Struct args already there
                                for (uint32_t i = 0; i < struct_param_count; i++) new_args[i] = type_args[i];
                                
                                for (uint32_t i = 0; i < method_type_arg_count && method_type_args; i++) {
                                    new_args[struct_param_count + i] = method_type_args[i];
                                }
                                // Fill rest with unit
                                for (uint32_t i = struct_param_count + method_type_arg_count; i < total_expected; i++) {
                                    new_args[i] = il_type_unit();
                                }
                                if (needs_free_type_args) free(type_args);
                                type_args = new_args;
                                needs_free_type_args = true;
                            }
                        }
                    }

                    target_fn = monomorphize_method(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, simpl, sfn, type_args, mname);
                }
            }
            free(struct_mangled);
        }
    }

    if (!target_fn) {
        const ImplDecl* simpl = NULL;
        const FunctionDecl* sfn = find_method_decl(ctx->surface_mod, def->name, expr->name, &simpl);
        if (sfn && simpl) {
            // Visibility check
            if (!sfn->is_pub && ctx->current_file && sfn->file_path) {
                if (strcmp(ctx->current_file, sfn->file_path) != 0) {
                    emit_diag_at(ctx, DIAG_ERROR, expr->receiver, "Access to private method '%s' of type '%s'", expr->name, def->name);
                }
            }
        }
        snprintf(mname, sizeof(mname), "%s_%s", def->name, expr->name);
        target_fn = il_mod_get_func_by_name(ctx->module, mname);
    }
    if (!target_fn) {
        char pattern[512];
        snprintf(pattern, sizeof(pattern), "%s_", def->name);
        size_t plen = strlen(pattern);
        for (uint32_t i = 0; i < ctx->module->function_count; i++) {
            const ILFunction* f = ctx->module->functions[i];
            if (strncmp(f->name, pattern, plen) == 0) {
                const char* suffix = strrchr(f->name, '_');
                if (suffix && expr->name && strcmp(suffix + 1, expr->name) == 0) {
                    target_fn = f;
                    break;
                }
            }
        }
    }

dispatch:
    (void)def;
    if (!target_fn) {
        if (needs_free_type_args) {
            free(type_args);
        }
        if (method_type_args) free(method_type_args);
        return (ILValue){0};
    }

    uint32_t total_args = expr->arg_count + (static_def ? 0 : 1) + il_func_user_param_offset(target_fn);
    ILValue* args = calloc(total_args, sizeof(ILValue));
    if (!args) abort();
    uint32_t arg_idx = 0;

    ILValue sret_ptr = {0};
    if (target_fn->is_sret) {
        if (dest_ptr.id != 0) {
            sret_ptr = dest_ptr;
        } else {
            const ILType* ret_ty = target_fn->sret_type;
            const ILType* ptr_ty = il_type_ptr(ret_ty, REGION_LOCAL, true);
            sret_ptr = emit(ctx, il_build_alloc(REGION_LOCAL, ret_ty, ptr_ty, (ILValue){0}));
        }
        args[arg_idx++] = (ILValue){ .id = sret_ptr.id, .type = sret_ptr.type };
    }

    if (il_func_needs_env_ptr(target_fn)) {
        const ILType* env_ty = il_type_ptr(il_type_unit(), REGION_STATIC, false);
        args[arg_idx++] = emit(ctx, il_build_const(0, env_ty)); 
    }

    if (!static_def) {
        uint32_t self_idx = arg_idx++;
        const ILType* expected_self_ty = (self_idx < target_fn->param_count) ? target_fn->param_types[self_idx] : NULL;
        ILValue self_val = prepare_self_arg(ctx, receiver_val, expected_self_ty);
        self_val = ensure_value(ctx, self_val, expected_self_ty);
        args[self_idx] = ensure_assignable(ctx, self_val, expected_self_ty);
        if (args[self_idx].id != self_val.id || args[self_idx].type != self_val.type) {
        }
        
        // If 'self' is passed by value and is non-copy, mark it as moved.
        if (!is_borrow_type(expected_self_ty) && args[self_idx].type && !il_type_is_copy_mod(ctx->module, args[self_idx].type)) {
            mark_moved(ctx, args[self_idx].id);
            if (receiver_val.id != 0 && receiver_val.id != args[self_idx].id) {
                mark_moved(ctx, receiver_val.id);
            }
        }
    }

    for (uint32_t i = 0; i < expr->arg_count; i++) {
        uint32_t current_idx = arg_idx++;
        const ILType* expected_arg = (current_idx < target_fn->param_count) ? target_fn->param_types[current_idx] : NULL;
        bool is_move = !is_borrow_type(expected_arg);
        
        bool pass_by_ref = requires_pass_by_ref(ctx->module, expected_arg);
        // Internal functions: pointer-to-aggregate params (already transformed by requires_pass_by_ref
        // in function definition) need pass-by-ref treatment at call sites too.
        if (!pass_by_ref && !target_fn->is_extern && expected_arg &&
            expected_arg->kind == IL_TY_PTR &&
            requires_pass_by_ref(ctx->module, expected_arg->as.ptr.pointee)) {
            pass_by_ref = true;
        }

        bool allow_lvalue = pass_by_ref;
        ILValue arg_dest = {0};
        if (expected_arg && pass_by_ref) {
            // Only pre-allocate a slot for non-lvalue expressions (literals, constructors, etc.).
            // For variables/members/indices, allow_lvalue=true will return their address directly.
            if (expr->args[i]->kind != EXPR_VAR && expr->args[i]->kind != EXPR_MEMBER && expr->args[i]->kind != EXPR_INDEX) {
                const ILType* slot_ty = (expected_arg->kind == IL_TY_PTR) ? expected_arg->as.ptr.pointee : expected_arg;
                const ILType* ptr_ty = il_type_ptr(slot_ty, REGION_LOCAL, true);
                arg_dest = emit(ctx, il_build_alloc(REGION_LOCAL, slot_ty, ptr_ty, (ILValue){0}));
            }
        }

        ILValue arg_val = lower_expression_internal(ctx, expr->args[i], expected_arg, is_move, arg_dest, allow_lvalue, !pass_by_ref);
        if (!ctx->current_block || (arg_val.type && arg_val.type->kind == IL_TY_NEVER)) {
             if (needs_free_type_args) free(type_args);
             free(args);
             return (ILValue){ .id = 0, .type = il_type_never() };
        }

        ILValue assigned = ensure_assignable(ctx, arg_val, expected_arg);
        args[current_idx] = ensure_value(ctx, assigned, expected_arg);

        // ABI: if the argument is still an aggregate value but expected_arg is *mut/const Aggregate,
        // wrap it in a stack slot now.
        if (args[current_idx].type && is_aggregate_type_layout(args[current_idx].type) &&
            expected_arg && expected_arg->kind == IL_TY_PTR &&
            requires_pass_by_ref(ctx->module, expected_arg->as.ptr.pointee)) {
            const ILType* slot_ty = args[current_idx].type;
            const ILType* ptr_ty_mut = il_type_ptr(slot_ty, REGION_LOCAL, true);
            ILValue slot = emit(ctx, il_build_alloc(REGION_LOCAL, slot_ty, ptr_ty_mut, (ILValue){0}));
            emit_void(ctx, il_build_store(slot, args[current_idx]));
            if (!il_type_eq(slot.type, expected_arg)) {
                slot = emit(ctx, il_build_bitcast(slot, expected_arg));
            }
            args[current_idx] = slot;
        }

        // If argument is moved and non-copy, mark the original SSA ID as moved.
        if (is_move && arg_val.type && !il_type_is_copy_mod(ctx->module, arg_val.type)) {
            mark_moved(ctx, arg_val.id);
        }
    }

    if (target_fn->return_type) {
    }
    ILInstruction* call = il_build_call(target_fn->id, args, total_args, target_fn->is_sret ? il_type_unit() : target_fn->return_type);

    ILValue call_res = emit(ctx, call);
    ILValue res;
    if (target_fn->is_sret) {
        if (dest_ptr.id != 0) {
            res = (ILValue){ .id = sret_ptr.id, .type = target_fn->sret_type };
        } else {
            res = emit(ctx, il_build_load(sret_ptr));
        }
    } else {
        res = call_res; res.type = target_fn->return_type;
    }
    
    if (needs_free_type_args) {
        free(type_args);
    }
    free(args);

    if (expected_type && res.type && !il_type_eq(res.type, expected_type) && il_type_is_assignable(res.type, expected_type)) {
        ILValue assigned = ensure_assignable(ctx, res, expected_type);
        if (assigned.id != res.id || assigned.type != res.type) {
            res = assigned;
        }
    }
    if (method_type_args) free(method_type_args);
    return res;
}

static ILValue lower_function_call(LowerContext* ctx, const Expression* e, const ILType* expected_type, ILValue dest_ptr) {
    if (!ctx) return (ILValue){0};
    const CallExpr* expr = &e->as.call;
    const FunctionDecl* sfn = NULL;
    for (uint32_t i = 0; i < ctx->surface_mod->function_count; i++) {
        if (ctx->surface_mod->functions[i]->name && strcmp(ctx->surface_mod->functions[i]->name, expr->name) == 0) {
            sfn = ctx->surface_mod->functions[i];
            break;
        }
    }

    if (sfn) {
        // Visibility check
        if (!sfn->is_pub && ctx->current_file && sfn->file_path) {
            if (strcmp(ctx->current_file, sfn->file_path) != 0) {
                emit_diag_at(ctx, DIAG_ERROR, e, "Access to private function '%s'", expr->name);
            }
        }
    }

    const ILType ** type_args = NULL;
    uint32_t type_arg_count = 0;
    bool needs_free_type_args = false;
    if (sfn && sfn->type_param_count > 0) {
        if (expr->type_arg_count > 0) {
            type_args = calloc(expr->type_arg_count, sizeof(const ILType*));
            for (uint32_t j = 0; j < expr->type_arg_count; j++) {
                type_args[j] = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, (const ILType*)expr->type_args[j], ctx->current_substs);
            }
            type_arg_count = expr->type_arg_count;
            needs_free_type_args = true;
        } else {
            type_arg_count = sfn->type_param_count;
            type_args = calloc(type_arg_count, sizeof(const ILType*));
            if (!type_args) abort();
            needs_free_type_args = true;
            for (uint32_t k = 0; k < type_arg_count; k++) {
                if (!type_args[k]) {
                    for (uint32_t j = 0; j < sfn->param_count && j < expr->arg_count; j++) {
                        const ILType* gty = guess_type_internal(ctx, expr->args[j], NULL);
                        
                        if (gty) {
                            if (match_type_param(ctx, sfn->params[j].type, gty, sfn->type_params[k], &type_args[k])) {
                                 break;
                            }
                        }
                    }
                }
                if (!type_args[k] && expected_type) {
                    match_type_param(ctx, sfn->return_type, expected_type, sfn->type_params[k], &type_args[k]);
                }
                if (!type_args[k]) type_args[k] = il_type_unit();
            }
        }
    }

    ILFunction* target_fn = NULL;
    if (sfn && sfn->type_param_count > 0) {
        char* mangled = mangle_generic_name(expr->name, type_arg_count, type_args);
        target_fn = il_mod_get_func_by_name(ctx->module, mangled);
        if (!target_fn) target_fn = monomorphize_function(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, sfn, type_args, mangled, NULL);
        free(mangled);
    } else {
        target_fn = (ILFunction*)il_mod_get_func_by_name(ctx->module, expr->name);
    }

    if (!target_fn && sfn && sfn->type_param_count == 0) {
        target_fn = monomorphize_function(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, sfn, NULL, expr->name, NULL);
    }

    if (!target_fn) {
        char* dot = strchr(expr->name, '.');
        if (dot) {
            char type_name[128];
            size_t type_len = (size_t)(dot - expr->name);
            if (type_len >= sizeof(type_name)) type_len = sizeof(type_name) - 1;
            strncpy(type_name, expr->name, type_len); type_name[type_len] = '\0';
            
            const ILType* base_ty = NULL;
            const Substitution* s = ctx->current_substs;
            while (s) {
                if (strcmp(s->name, type_name) == 0) { base_ty = s->type; break; }
                s = s->next;
            }
            
            const ILTypeDef* def = NULL;
            if (base_ty && (base_ty->kind == IL_TY_STRUCT || base_ty->kind == IL_TY_SUM)) {
                def = il_mod_get_type_def(ctx->module, base_ty->as.struct_sum.type_def_id);
            }
            if (!def) def = find_type_def(ctx, type_name);
            if (def && def->id == 0 && expected_type && (expected_type->kind == IL_TY_SUM || expected_type->kind == IL_TY_STRUCT)) {
                const ILTypeDef* concrete = il_mod_get_type_def(ctx->module, expected_type->as.struct_sum.type_def_id);
                if (concrete) def = concrete;
            }
            if (def) {
                const char* method_name = dot + 1;
                if (def->is_sum) {
                    const ILType ** v_type_args = NULL;
                    if (expr->type_arg_count > 0) {
                        v_type_args = calloc(expr->type_arg_count, sizeof(const ILType*));
                        for (uint32_t j = 0; j < expr->type_arg_count; j++) {
                            v_type_args[j] = lower_type(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, (const ILType*)expr->type_args[j], ctx->current_substs);
                        }
                    }
                    ILValue res = lower_variant_construct(ctx, def, method_name, (const Expression**)expr->args, expr->arg_count, v_type_args, expr->type_arg_count, expected_type, dest_ptr);
                    if (v_type_args) free(v_type_args);
                    if (res.type) {
                        return res;
                    }
                }
                char mname[512];
                snprintf(mname, sizeof(mname), "%s_%s", def->name, method_name);
                target_fn = (ILFunction*)il_mod_get_func_by_name(ctx->module, mname);

                if (!target_fn) {
                    const ImplDecl* simpl = NULL;
                    const FunctionDecl* method_sfn = find_method_decl(ctx->surface_mod, def->name, method_name, &simpl);
                    if (method_sfn && simpl) {
                        const TypeDef* styp = NULL;
                        for (uint32_t i = 0; i < ctx->surface_mod->type_def_count; i++) {
                            const char* sname = (ctx->surface_mod->type_defs[i]->kind == TYPE_DEF_STRUCT) ? ctx->surface_mod->type_defs[i]->as.struct_decl->name : ctx->surface_mod->type_defs[i]->as.enum_decl->name;
                            if (strcmp(sname, def->name) == 0) { styp = ctx->surface_mod->type_defs[i]; break; }
                        }

                        if (styp) {
                            target_fn = infer_and_monomorphize_method(ctx, simpl, method_sfn, styp, def->name, method_name, (const Expression**)expr->args, expr->arg_count);
                        }
                    }
                }
            }
        }
    }

    if (!target_fn) {
        char* underscore = strrchr(expr->name, '_');
        if (underscore) {
            char type_name[128];
            size_t type_len = (size_t)(underscore - expr->name);
            if (type_len >= sizeof(type_name)) type_len = sizeof(type_name) - 1;
            strncpy(type_name, expr->name, type_len); type_name[type_len] = '\0';
            const char* method_name = underscore + 1;
            
            const ImplDecl* simpl = NULL;
            const FunctionDecl* method_sfn = find_method_decl(ctx->surface_mod, type_name, method_name, &simpl);
            if (method_sfn && simpl) {
                // Try to resolve as a method call
                const TypeDef* styp = NULL;
                for (uint32_t i = 0; i < ctx->surface_mod->type_def_count; i++) {
                    const char* sname = (ctx->surface_mod->type_defs[i]->kind == TYPE_DEF_STRUCT) ? ctx->surface_mod->type_defs[i]->as.struct_decl->name : ctx->surface_mod->type_defs[i]->as.enum_decl->name;
                    if (strcmp(sname, type_name) == 0) {
                        styp = ctx->surface_mod->type_defs[i];
                        break;
                    }
                }

                ILFunction* inferred_fn = NULL;
                if (styp) {
                    inferred_fn = infer_and_monomorphize_method(ctx, simpl, method_sfn, styp, type_name, method_name, (const Expression**)expr->args, expr->arg_count);
                }
                if (inferred_fn) {
                    target_fn = inferred_fn;
                } else {
                    char full_mname[512];
                    snprintf(full_mname, sizeof(full_mname), "%s_%s", type_name, method_name);
                    target_fn = (ILFunction*)il_mod_get_func_by_name(ctx->module, full_mname);
                    if (!target_fn) target_fn = monomorphize_method(ctx->surface_mod, ctx->module, ctx->report, ctx->release_mode, simpl, method_sfn, NULL, full_mname);
                }
            }
        }
    }

    if (!target_fn) {
        if (sfn && sfn->type_param_count > 0 && expr->type_arg_count == 0) {
            free(type_args);
        }
        return (ILValue){0};
    }
    
    uint32_t total_args = expr->arg_count;
    if (target_fn->is_sret) total_args++;
    if (il_func_needs_env_ptr(target_fn)) total_args++;
    
    uint32_t arg_idx = 0;
    ILValue sret_ptr = {0};
    if (target_fn->is_sret) {
        arg_idx++;
    }
    if (il_func_needs_env_ptr(target_fn)) {
        arg_idx++;
    }

    uint32_t expected_explicit = target_fn->param_count - arg_idx;
    const char* fn_name = target_fn->name ? target_fn->name : "anonymous";
    if (target_fn->is_variadic) {
        if (expr->arg_count < expected_explicit) {
            emit_diag_at(ctx, DIAG_ERROR, e, "wrong number of arguments (expected %u, got %u)", expected_explicit, expr->arg_count);
            return (ILValue){0};
        }
    } else if (expr->arg_count != expected_explicit) {
        emit_diag_at(ctx, DIAG_ERROR, e, "function '%s' expects %u arguments, but %u were provided", fn_name, expected_explicit, expr->arg_count);
        return (ILValue){0};
    }

    // Allocate at least 1 to ensure a non-null pointer for scan-build, 
    // even if total_args is 0.
    ILValue* args = calloc(total_args > 0 ? total_args : 1, sizeof(ILValue));
    if (!args) abort();

    arg_idx = 0;
    if (target_fn->is_sret) {
        if (dest_ptr.id != 0) {
            sret_ptr = dest_ptr;
        } else {
            const ILType* ret_ty = target_fn->sret_type;
            const ILType* ptr_ty = il_type_ptr(ret_ty, REGION_LOCAL, true);
            sret_ptr = emit(ctx, il_build_alloc(REGION_LOCAL, ret_ty, ptr_ty, (ILValue){0}));
        }
        args[arg_idx++] = (ILValue){ .id = sret_ptr.id, .type = sret_ptr.type };
    }
    if (il_func_needs_env_ptr(target_fn)) {
        const ILType* env_ty = il_type_ptr(il_type_unit(), REGION_STATIC, false);
        args[arg_idx++] = emit(ctx, il_build_const(0, env_ty)); 
    }
    for (uint32_t i = 0; i < expr->arg_count; i++) {
        uint32_t cur_idx = arg_idx++;
        const ILType* target_arg_ty = (cur_idx < target_fn->param_count) ? target_fn->param_types[cur_idx] : NULL;
        bool is_move = !is_borrow_type(target_arg_ty);
        
        bool pass_by_ref = requires_pass_by_ref(ctx->module, target_arg_ty);
        // Internal functions: pointer-to-large-aggregate params need pass-by-ref treatment
        // so the caller can pass lvalue addresses directly without loading.
        if (!pass_by_ref && !target_fn->is_extern && target_arg_ty &&
            target_arg_ty->kind == IL_TY_PTR &&
            requires_pass_by_ref(ctx->module, target_arg_ty->as.ptr.pointee)) {
            pass_by_ref = true;
        }

        ILValue arg_dest = {0};
        // Optimization: if it is an aggregate, try to get its address directly instead of loading and copying it.
        // We can now do this for both borrows AND moves safely.
        bool allow_lvalue = pass_by_ref;

        // If it's a pass-by-ref aggregate and NOT a variable/member/index (which are lvalues),
        // we pre-allocate a slot to allow in-place initialization.
        if (target_arg_ty && pass_by_ref) {
             if (expr->args[i]->kind != EXPR_VAR && expr->args[i]->kind != EXPR_MEMBER && expr->args[i]->kind != EXPR_INDEX) {
                 const ILType* slot_ty = (target_arg_ty->kind == IL_TY_PTR) ? target_arg_ty->as.ptr.pointee : target_arg_ty;
                 const ILType* ptr_ty = il_type_ptr(slot_ty, REGION_LOCAL, true);
                 arg_dest = emit(ctx, il_build_alloc(REGION_LOCAL, slot_ty, ptr_ty, (ILValue){0}));
             }
        }

        ILValue arg_val = lower_expression_internal(ctx, expr->args[i], target_arg_ty, is_move, arg_dest, allow_lvalue, !pass_by_ref);
        if (!ctx->current_block || (arg_val.type && arg_val.type->kind == IL_TY_NEVER)) {
            if (type_args && needs_free_type_args) free(type_args);
            free(args);
            return (ILValue){ .id = 0, .type = il_type_never() };
        }
        
        if (target_arg_ty) {
            args[cur_idx] = ensure_assignable(ctx, arg_val, target_arg_ty);
            args[cur_idx] = ensure_value(ctx, args[cur_idx], target_arg_ty);
        } else {
            args[cur_idx] = arg_val;
        }

        // ABI: if the argument is still an aggregate value but expected_arg is *mut/const Aggregate,
        // wrap it in a stack slot now.
        if (args[cur_idx].id != 0 && args[cur_idx].type && is_aggregate_type_layout(args[cur_idx].type) &&
            target_arg_ty && target_arg_ty->kind == IL_TY_PTR &&
            requires_pass_by_ref(ctx->module, target_arg_ty->as.ptr.pointee)) {
            
            // Optimization: if it's already a pointer (e.g. result of an EXPR_VAR lvalue, member, or index),
            // just pass the pointer directly.
            if (expr->args[i]->kind == EXPR_VAR || expr->args[i]->kind == EXPR_MEMBER || expr->args[i]->kind == EXPR_INDEX) {
                args[cur_idx].type = target_arg_ty;
            } else {
                const ILType* slot_ty = args[cur_idx].type;
                const ILType* ptr_ty_mut = il_type_ptr(slot_ty, REGION_LOCAL, true);
                ILValue slot = emit(ctx, il_build_alloc(REGION_LOCAL, slot_ty, ptr_ty_mut, (ILValue){0}));
                emit_void(ctx, il_build_store(slot, args[cur_idx]));
                if (!il_type_eq(slot.type, target_arg_ty)) {
                    slot = emit(ctx, il_build_bitcast(slot, target_arg_ty));
                }
                args[cur_idx] = slot;
            }
        }

        // If this is a non-copy move, mark the original argument SSA ID as moved.
        if (is_move && arg_val.type && !il_type_is_copy_mod(ctx->module, arg_val.type)) {
            mark_moved(ctx, arg_val.id);
        }
    }
    ILValue call_res = emit(ctx, il_build_call(target_fn->id, args, total_args, target_fn->is_sret ? il_type_unit() : target_fn->return_type));
    ILValue res;
    if (target_fn->is_sret) {
        if (dest_ptr.id != 0) {
            res = (ILValue){ .id = sret_ptr.id, .type = target_fn->sret_type };
        } else {
            res = emit(ctx, il_build_load(sret_ptr));
        }
    } else {

        res = call_res;
    }
    
    free(args);    
    if (type_args && needs_free_type_args) {
        free(type_args);
    }
    return res;
}

ILValue lower_call(LowerContext* ctx, const Expression* e, const ILType* expected_type, ILValue dest_ptr) {
    const CallExpr* expr = &e->as.call;
    
    // 1. Built-in functions (@drop, @syscall)
    if (expr->name && expr->name[0] == '@') {
        ILValue res = lower_builtin_call(ctx, expr, dest_ptr);
        if (res.type) return res;
    }

    // 2. Closure call (callee is an expression)
    if (expr->callee || expr->name) {
        ILValue callee_val = {0};
        if (expr->callee) {
            callee_val = lower_expression_internal(ctx, expr->callee, NULL, false, (ILValue){0}, false, false);
        } else {
            const Symbol* sym = symbol_lookup_ctx(ctx, expr->name);
            if (sym) {
                if (is_moved(ctx, sym->value.id)) {
                    emit_diag_at(ctx, DIAG_ERROR, e, "use of moved value '%s'", expr->name);
                }
                callee_val = (ILValue){ .id = sym->value.id, .type = sym->value.type };
                if (sym->is_lvalue) {
                    ILValue val = emit(ctx, il_build_load(callee_val));
                    callee_val = val;
                }
            }
        }

        if (callee_val.type) {
            ILValue res = lower_closure_call(ctx, expr, callee_val, dest_ptr);
            if (res.type) {  return res; }
        }
    }

    // 3. Method call (receiver exists)
    if (expr->receiver) {
        ILValue res = lower_method_call(ctx, expr, expected_type, dest_ptr);
        if (res.type) return res;
        emit_diag_at(ctx, DIAG_ERROR, expr->receiver, "Unresolved method or variant: %s", expr->name);
        return (ILValue){0};
    }

    // 4. Regular function call or static variant construct
    if (expr->name) {
        uint32_t old_count = (ctx && ctx->report) ? ctx->report->count : 0;
        ILValue res = lower_function_call(ctx, e, expected_type, dest_ptr);
        if (res.type) return res;
        if (!ctx || !ctx->report || ctx->report->count == old_count) {
            emit_diag_at(ctx, DIAG_ERROR, e, "Unresolved function or variant: %s", expr->name);
        }
        return (ILValue){0};
    }

    return (ILValue){0};
}
