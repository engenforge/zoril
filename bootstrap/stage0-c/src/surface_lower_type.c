#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include "surface_lower_internal.h"
#include "surface_parser_internal.h"
#include "il_type.h"
#include "il_instr.h"

Substitution* derive_substs(const SurfaceModule* smod, const ILType* target_type) {
    if (!target_type) return NULL;
    if (target_type->kind != IL_TY_STRUCT && target_type->kind != IL_TY_SUM) return NULL;
    
    uint32_t param_count = 0;
    char** params = NULL;

    const char* lookup_name = target_type->as.struct_sum.name;
    const TypeDef* found_styp = NULL;

    // Try exact match first
    for (uint32_t i = 0; i < smod->type_def_count; i++) {
        const TypeDef* styp = smod->type_defs[i];
        const char* sname = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->name : styp->as.enum_decl->name;
        if (strcmp(sname, lookup_name) == 0) {
            found_styp = styp;
            break;
        }
    }

    if (!found_styp) {
        char base_buf[128];
        const char* underscore = strchr(lookup_name, '_');
        if (underscore) {
            size_t len = (size_t)(underscore - lookup_name);
            if (len >= sizeof(base_buf)) len = sizeof(base_buf) - 1;
            strncpy(base_buf, lookup_name, len);
            base_buf[len] = '\0';
            lookup_name = base_buf;
        }

        for (uint32_t i = 0; i < smod->type_def_count; i++) {
            const TypeDef* styp = smod->type_defs[i];
            const char* sname = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->name : styp->as.enum_decl->name;
            if (strcmp(sname, lookup_name) == 0) {
                found_styp = styp;
                break;
            }
        }
    }

    if (found_styp) {
        param_count = (found_styp->kind == TYPE_DEF_STRUCT) ? found_styp->as.struct_decl->type_param_count : found_styp->as.enum_decl->type_param_count;
        params = (found_styp->kind == TYPE_DEF_STRUCT) ? found_styp->as.struct_decl->type_params : found_styp->as.enum_decl->type_params;
    }
    
    Substitution* head = NULL;
    for (uint32_t i = 0; i < target_type->as.struct_sum.type_arg_count && i < param_count; i++) {
        Substitution* s = calloc(1, sizeof(Substitution));
        if (!s) break;
        s->name = params[i];
        
        const ILType* arg = target_type->as.struct_sum.type_args[i];
        if ((arg->kind == IL_TY_STRUCT || arg->kind == IL_TY_SUM) && 
            arg->as.struct_sum.type_arg_count == 0 && 
            arg->as.struct_sum.name && 
            strcmp(arg->as.struct_sum.name, params[i]) == 0) {
            s->type = il_type_var(params[i]);
        } else {
            s->type = arg; // It's still owned by the target_type tree, but we use it as a reference or copy it.
            // Wait, derive_substs creates a Substitution where s->type points to the existing AST.
            // But if we create a new IL_TY_VAR, who frees it?
            // Let's copy it to be safe, because when deriving substs, we often don't free s->type.
            // Actually, in the original code: `s->type = target_type->as.struct_sum.type_args[i];`
            // So s->type was unowned! If we put a new allocated type here, it will leak unless we free it.
            // Wait! The old code didn't copy. We'll just leave it unowned for now and see if there are leaks.
        }
        
        s->next = head;
        head = s;
    }
    return head;
}

const ILType* resolve_type_aliases(const SurfaceModule* smod, const ILType* type, int depth) {
    if (!type || depth > 10) return type;

    if (type->kind == IL_TY_PTR) {
        const ILType* new_pointee = resolve_type_aliases(smod, type->as.ptr.pointee, depth + 1);
        if (new_pointee != type->as.ptr.pointee) {
            return il_type_ptr(new_pointee, type->as.ptr.region_id, type->as.ptr.is_mut);
        }
        return type;
    } else if (type->kind == IL_TY_BOX) {
        const ILType* new_pointee = resolve_type_aliases(smod, type->as.box.pointee, depth + 1);
        if (new_pointee != type->as.box.pointee) {
            return il_type_box(new_pointee, type->as.box.region_id, type->as.box.is_mut);
        }
        return type;
    } else if (type->kind == IL_TY_SLICE) {
        const ILType* new_elem = resolve_type_aliases(smod, type->as.slice.element, depth + 1);
        if (new_elem != type->as.slice.element) {
            return il_type_slice(new_elem, type->as.slice.region_id, type->as.slice.is_mut);
        }
        return type;
    } else if (type->kind == IL_TY_ARRAY) {
        const ILType* new_elem = resolve_type_aliases(smod, type->as.array.element, depth + 1);
        if (new_elem != type->as.array.element) {
            return il_type_array(new_elem, type->as.array.length);
        }
        return type;
    } else if (type->kind == IL_TY_STRUCT || type->kind == IL_TY_SUM) {
        if (type->as.struct_sum.name) {
            for (uint32_t i = 0; i < smod->type_alias_count; i++) {
                if (strcmp(smod->type_aliases[i]->name, type->as.struct_sum.name) == 0) {
                    const ILType* target = smod->type_aliases[i]->target;
                    if (target) {
                        return resolve_type_aliases(smod, target, depth + 1);
                    }
                }
            }
        }
        
        // Also resolve type aliases in type arguments
        bool changed = false;
        const ILType ** new_args = malloc(sizeof(const ILType*) * type->as.struct_sum.type_arg_count);
        for (uint32_t i = 0; i < type->as.struct_sum.type_arg_count; i++) {
            new_args[i] = resolve_type_aliases(smod, type->as.struct_sum.type_args[i], depth + 1);
            if (new_args[i] != type->as.struct_sum.type_args[i]) changed = true;
        }
        if (changed) {
            const ILType* res = (type->kind == IL_TY_STRUCT) ? 
                il_type_struct_gen(type->as.struct_sum.name, type->as.struct_sum.type_def_id, new_args, type->as.struct_sum.type_arg_count) :
                il_type_sum_gen(type->as.struct_sum.name, type->as.struct_sum.type_def_id, new_args, type->as.struct_sum.type_arg_count);
            free(new_args);
            return res;
        }
        free(new_args);
    } else if (type->kind == IL_TY_TUPLE) {
        bool changed = false;
        const ILType ** new_elems = malloc(sizeof(const ILType*) * type->as.tuple.count);
        for (uint32_t i = 0; i < type->as.tuple.count; i++) {
            new_elems[i] = resolve_type_aliases(smod, type->as.tuple.elements[i], depth + 1);
            if (new_elems[i] != type->as.tuple.elements[i]) changed = true;
        }
        if (changed) {
            const ILType* res = il_type_tuple(new_elems, type->as.tuple.count);
            free(new_elems);
            return res;
        }
        free(new_elems);
    } else if (type->kind == IL_TY_FN) {
        bool changed = false;
        const ILType* new_ret = resolve_type_aliases(smod, type->as.function.return_type, depth + 1);
        if (new_ret != type->as.function.return_type) changed = true;
        
        const ILType ** new_params = malloc(sizeof(const ILType*) * type->as.function.param_count);
        for (uint32_t i = 0; i < type->as.function.param_count; i++) {
            new_params[i] = resolve_type_aliases(smod, type->as.function.param_types[i], depth + 1);
            if (new_params[i] != type->as.function.param_types[i]) changed = true;
        }
        if (changed) {
            const ILType* res = il_type_fn(new_ret, new_params, type->as.function.param_count, type->as.function.is_variadic);
            free(new_params);
            return res;
        }
        free(new_params);
    }
    
    return type;
}

const ILType* get_closure_type(ILModule* ilmod, const ILType* fn_ty) {
    char* mangled = mangle_type(fn_ty);
    char name[256];
    snprintf(name, sizeof(name), "Closure_%s", mangled);
    free(mangled);
    
    ILTypeDef* def = NULL;
    for (uint32_t i = 0; i < ilmod->type_def_count; i++) {
        if (strcmp(ilmod->type_defs[i]->name, name) == 0) {
            def = ilmod->type_defs[i];
            break;
        }
    }
    
    if (!def) {
        def = il_type_def_struct_create((uint32_t)(ilmod->next_type_def_id++), name, NULL, false);
        il_mod_add_type_def(ilmod, def);
        il_type_def_add_field_pub(def, "code", fn_ty, false, false, 0);
        il_type_def_add_field_pub(def, "env", il_type_ptr(il_type_unit(), REGION_STATIC, false), false, false, 0);
    }
    
    const ILType* struct_ty = il_type_struct(name, def->id);
    if (!struct_ty) return NULL;
    
    const ILType* struct_ptr_ty = il_type_ptr(struct_ty, REGION_HEAP, false);
    return struct_ptr_ty;
}

static const ILType* substitute_type_depth(const ILType* type, const Substitution* substs, int depth);

const ILType* substitute_type(const ILType* type, const Substitution* substs) {
    return substitute_type_depth(type, substs, 0);
}

static const ILType* substitute_type_depth(const ILType* type, const Substitution* substs, int depth) {
    if (!type) return NULL;
    if (depth > 10) return type;
    
    const Substitution* s = substs;
    if (type->kind == IL_TY_VAR) {
        while (s) {
            if (type->as.var.name && strcmp(s->name, type->as.var.name) == 0) {
                return s->type;
            }
            s = s->next;
        }
    } else if (type->kind == IL_TY_STRUCT || type->kind == IL_TY_SUM) {
        while (s) {
            if (type->as.struct_sum.name && strcmp(s->name, type->as.struct_sum.name) == 0 && type->as.struct_sum.type_arg_count == 0) {
                return s->type;
            }
            s = s->next;
        }
    }

    if (type->kind == IL_TY_PTR) {
        const ILType* new_pointee = substitute_type_depth(type->as.ptr.pointee, substs, depth + 1);
        if (new_pointee != type->as.ptr.pointee) {
            return il_type_ptr(new_pointee, type->as.ptr.region_id, type->as.ptr.is_mut);
        }
        return type;
    } else if (type->kind == IL_TY_BOX) {
        const ILType* new_pointee = substitute_type_depth(type->as.box.pointee, substs, depth + 1);
        if (new_pointee != type->as.box.pointee) {
            return il_type_box(new_pointee, type->as.box.region_id, type->as.box.is_mut);
        }
        return type;
    } else if (type->kind == IL_TY_SLICE) {
        const ILType* new_elem = substitute_type_depth(type->as.slice.element, substs, depth + 1);
        if (new_elem != type->as.slice.element) {
            return il_type_slice(new_elem, type->as.slice.region_id, type->as.slice.is_mut);
        }
        return type;
    } else if (type->kind == IL_TY_ARRAY) {
        const ILType* new_elem = substitute_type_depth(type->as.array.element, substs, depth + 1);
        if (new_elem != type->as.array.element) {
            return il_type_array(new_elem, type->as.array.length);
        }
        return type;
    } else if (type->kind == IL_TY_TUPLE) {
        bool changed = false;
        const ILType ** new_elems = malloc(sizeof(const ILType*) * type->as.tuple.count);
        for (uint32_t i = 0; i < type->as.tuple.count; i++) {
            new_elems[i] = substitute_type_depth(type->as.tuple.elements[i], substs, depth + 1);
            if (new_elems[i] != type->as.tuple.elements[i]) changed = true;
        }
        if (changed) {
            const ILType* res = il_type_tuple(new_elems, type->as.tuple.count);
            free(new_elems);
            return res;
        }
        free(new_elems);
        return type;
    } else if (type->kind == IL_TY_STRUCT || type->kind == IL_TY_SUM) {
        const Substitution* s_inner = substs;
        while (s_inner) {
            if (type->as.struct_sum.name && strcmp(s_inner->name, type->as.struct_sum.name) == 0) {
                return s_inner->type;
            }
            s_inner = s_inner->next;
        }

        bool changed = false;
        const ILType ** new_args = malloc(sizeof(const ILType*) * type->as.struct_sum.type_arg_count);
        for (uint32_t i = 0; i < type->as.struct_sum.type_arg_count; i++) {
            new_args[i] = substitute_type_depth(type->as.struct_sum.type_args[i], substs, depth + 1);
            if (new_args[i] != type->as.struct_sum.type_args[i]) changed = true;
        }
        if (changed) {
             const ILType* res = (type->kind == IL_TY_STRUCT) ? 
                 il_type_struct_gen(type->as.struct_sum.name, 0, new_args, type->as.struct_sum.type_arg_count) :
                 il_type_sum_gen(type->as.struct_sum.name, 0, new_args, type->as.struct_sum.type_arg_count);
             free(new_args);
             return res;
        }
        free(new_args);
        return type;
    } else if (type->kind == IL_TY_FN) {
        bool changed = false;
        const ILType* new_ret = substitute_type_depth(type->as.function.return_type, substs, depth + 1);
        if (new_ret != type->as.function.return_type) changed = true;
        
        const ILType ** new_params = malloc(sizeof(const ILType*) * type->as.function.param_count);
        for (uint32_t i = 0; i < type->as.function.param_count; i++) {
            new_params[i] = substitute_type_depth(type->as.function.param_types[i], substs, depth + 1);
            if (new_params[i] != type->as.function.param_types[i]) changed = true;
        }
        if (changed) {
            const ILType* res = il_type_fn(new_ret, new_params, type->as.function.param_count, type->as.function.is_variadic);
            free(new_params);
            return res;
        }
        free(new_params);
        return type;
    }
    return type;
}

static void maybe_register_drop(const SurfaceModule* smod, ILModule* ilmod, DiagnosticReport* report, bool release_mode,
                                const char* styp_name, const char* mangled_name,
                                const ILType ** type_args, ILTypeDef* ityp) {
    for (uint32_t k = 0; k < smod->impl_count; k++) {
        const ImplDecl* simpl = smod->impls[k];
        if (!simpl->trait_name || strcmp(simpl->trait_name, "Drop") != 0) continue;
        bool match = (strcmp(simpl->target_name, styp_name) == 0);
        if (!match) {
            const char* underscore = strchr(simpl->target_name, '_');
            if (underscore) {
                size_t base_len = (size_t)(underscore - simpl->target_name);
                match = (strncmp(simpl->target_name, styp_name, base_len) == 0 && styp_name[base_len] == '\0');
            }
        }
        if (!match) continue;
        for (uint32_t m = 0; m < simpl->method_count; m++) {
            if (strcmp(simpl->methods[m]->name, "drop") == 0) {
                char drop_mname[512];
                snprintf(drop_mname, sizeof(drop_mname), "%s_drop", mangled_name);
                monomorphize_method(smod, ilmod, report, release_mode, simpl, simpl->methods[m], type_args, drop_mname);
                if (ityp->drop_fn_name) free(ityp->drop_fn_name);
                ityp->drop_fn_name = strdup(drop_mname);
                break;
            }
        }
    }
}

const ILType* lower_type_internal(const SurfaceModule* smod, ILModule* ilmod, DiagnosticReport* report, bool release_mode, const ILType* type, const Substitution* substs, int depth, const SourceLocation* loc_hint) {
    if (!type) return NULL;
    if (depth > 10) {
        if (report) diag_emit(report, DIAG_ERROR, loc_hint ? *loc_hint : (SourceLocation){.file_path = smod->file_path}, "Type recursion limit exceeded");
        return il_type_unit();
    }
    const ILType* substituted = substitute_type(type, substs);
    if (!substituted) return NULL;
    
    // Recursive monomorphization of type arguments
    if (substituted->kind == IL_TY_STRUCT || substituted->kind == IL_TY_SUM) {
        bool args_changed = false;
        const ILType** new_args = malloc(sizeof(const ILType*) * substituted->as.struct_sum.type_arg_count);
        for (uint32_t i = 0; i < substituted->as.struct_sum.type_arg_count; i++) {
            new_args[i] = lower_type_internal(smod, ilmod, report, release_mode, substituted->as.struct_sum.type_args[i], substs, depth + 1, loc_hint);
            if (new_args[i] != substituted->as.struct_sum.type_args[i]) args_changed = true;
        }
        if (args_changed) {
            substituted = (substituted->kind == IL_TY_STRUCT) 
                ? il_type_struct_gen(substituted->as.struct_sum.name, 0, new_args, substituted->as.struct_sum.type_arg_count)
                : il_type_sum_gen(substituted->as.struct_sum.name, 0, new_args, substituted->as.struct_sum.type_arg_count);
        }
        free(new_args);
    }



    substituted = resolve_type_aliases(smod, substituted, 0);



    if (ilmod) {
        if (substituted->kind == IL_TY_PTR) {
            const ILType* old_inner = substituted->as.ptr.pointee;
            const ILType* inner = lower_type_internal(smod, ilmod, report, release_mode, old_inner, substs, depth + 1, loc_hint);
            if (inner != old_inner) {
                substituted = il_type_ptr(inner, substituted->as.ptr.region_id, substituted->as.ptr.is_mut);
            }
        } else if (substituted->kind == IL_TY_BOX) {
            const ILType* old_inner = substituted->as.box.pointee;
            const ILType* inner = lower_type_internal(smod, ilmod, report, release_mode, old_inner, substs, depth + 1, loc_hint);
            if (inner != old_inner) {
                substituted = il_type_box(inner, substituted->as.box.region_id, substituted->as.box.is_mut);
            }
        } else if (substituted->kind == IL_TY_ARRAY) {
            const ILType* old_inner = substituted->as.array.element;
            const ILType* inner = lower_type_internal(smod, ilmod, report, release_mode, old_inner, substs, depth + 1, loc_hint);
            if (inner != old_inner) {
                substituted = il_type_array(inner, substituted->as.array.length);
            }
        } else if (substituted->kind == IL_TY_SLICE) {
            const ILType* old_inner = substituted->as.slice.element;
            const ILType* inner = lower_type_internal(smod, ilmod, report, release_mode, old_inner, substs, depth + 1, loc_hint);
            if (inner != old_inner) {
                substituted = il_type_slice(inner, substituted->as.slice.region_id, substituted->as.slice.is_mut);
            }
        } else if (substituted->kind == IL_TY_FN) {
            const ILType* inner_ret = lower_type_internal(smod, ilmod, report, release_mode, substituted->as.function.return_type, substs, depth + 1, loc_hint);
            bool changed = (inner_ret != substituted->as.function.return_type);
            
            const ILType ** new_params = malloc(sizeof(const ILType*) * substituted->as.function.param_count);
            for (uint32_t i = 0; i < substituted->as.function.param_count; i++) {
                new_params[i] = lower_type_internal(smod, ilmod, report, release_mode, substituted->as.function.param_types[i], substs, depth + 1, loc_hint);
                if (new_params[i] != substituted->as.function.param_types[i]) changed = true;
            }

            const ILType* base_fn_ty = substituted;
            if (changed) {
                base_fn_ty = il_type_fn(inner_ret, new_params, substituted->as.function.param_count, substituted->as.function.is_variadic);
            }
            free(new_params);

            // Check if it already has an environment pointer (idempotency)
            bool has_env = base_fn_ty->as.function.param_count > 0 && 
                           base_fn_ty->as.function.param_types[0]->kind == IL_TY_PTR &&
                           base_fn_ty->as.function.param_types[0]->as.ptr.pointee->kind == IL_TY_UNIT;

            if (!has_env) {
                // Add implicit env parameter as first arg
                const ILType ** with_env_params = malloc((base_fn_ty->as.function.param_count + 1) * sizeof(const ILType*));
                if (with_env_params) {
                    with_env_params[0] = il_type_ptr(il_type_unit(), REGION_STATIC, false);
                    for (uint32_t i = 0; i < base_fn_ty->as.function.param_count; i++) {
                        with_env_params[i + 1] = base_fn_ty->as.function.param_types[i];
                    }
                    base_fn_ty = il_type_fn(base_fn_ty->as.function.return_type, with_env_params, base_fn_ty->as.function.param_count + 1, base_fn_ty->as.function.is_variadic);
                    free(with_env_params);
                }
            }

            return get_closure_type(ilmod, base_fn_ty);
        }
    }

    if (ilmod && substituted->kind == IL_TY_TUPLE) {
        if (substituted->as.tuple.count == 0) {
            return il_type_unit();
        }
        char* mangled_name = mangle_type(substituted);
        ILTypeDef* def = NULL;
        for (uint32_t i = 0; i < ilmod->type_def_count; i++) {
            if (strcmp(ilmod->type_defs[i]->name, mangled_name) == 0) {
                def = ilmod->type_defs[i];
                break;
            }
        }
        if (!def) {
            def = il_type_def_struct_create((uint32_t)(ilmod->next_type_def_id++), mangled_name, NULL, false);
            il_mod_add_type_def(ilmod, def);
            for (uint32_t i = 0; i < substituted->as.tuple.count; i++) {
                char field_name[16];
                snprintf(field_name, sizeof(field_name), "%u", i);
                il_type_def_add_field_pub(def, field_name, lower_type_internal(smod, ilmod, report, release_mode, substituted->as.tuple.elements[i], substs, depth + 1, loc_hint), false, false, 0);
            }
        }
        const ILType* struct_ty = il_type_struct(mangled_name, def->id);
        free(mangled_name);
        return struct_ty;
    }

    // Monomorphization and type resolution
    if (ilmod && (substituted->kind == IL_TY_STRUCT || substituted->kind == IL_TY_SUM)) {
        // 'never' is a builtin bottom type, not a user-defined type.
        if (substituted->as.struct_sum.name && strcmp(substituted->as.struct_sum.name, "never") == 0) {
            return il_type_never();
        }
        
        bool has_generic_args = false;
        for (uint32_t a = 0; a < substituted->as.struct_sum.type_arg_count; a++) {
            if (il_type_is_generic_mod(ilmod, substituted->as.struct_sum.type_args[a])) {
                has_generic_args = true;
                break;
            }
        }

        if (substituted->as.struct_sum.type_def_id == 0 || (substituted->as.struct_sum.type_arg_count > 0 && !has_generic_args)) {
            char* mangled_name = (substituted->as.struct_sum.type_arg_count > 0 && !has_generic_args) 
                ? mangle_type(substituted) 
                : strdup(substituted->as.struct_sum.name);
            
            // Check if already monomorphized or already exists
            for (uint32_t i = 0; i < ilmod->type_def_count; i++) {
                if (strcmp(ilmod->type_defs[i]->name, mangled_name) == 0) {
                    ILTypeDef* existing = ilmod->type_defs[i];
                    
                    // Visibility check
                    if (!existing->is_pub && smod->file_path && existing->file_path) {
                        if (strcmp(smod->file_path, existing->file_path) != 0) {
                            diag_emit(report, DIAG_ERROR, loc_hint ? *loc_hint : (SourceLocation){.file_path = smod->file_path}, "Access to private type '%s'", substituted->as.struct_sum.name);
                        }
                    }

                    // Use existing->is_sum (not substituted->kind) because parse_type() always
                    // creates IL_TY_STRUCT for user-defined types, even enums.
                    const ILType* res = existing->is_sum ?
                        il_type_sum_gen(mangled_name, existing->id, substituted->as.struct_sum.type_args, substituted->as.struct_sum.type_arg_count) :
                        il_type_struct_gen(mangled_name, existing->id, substituted->as.struct_sum.type_args, substituted->as.struct_sum.type_arg_count);
                    
                    // Force resolution of variants if this is a specialized type and fields are not yet lowered
                    if (substituted->as.struct_sum.type_arg_count > 0 && existing->field_count == 0) {
                        const char* base_name = substituted->as.struct_sum.name;
                        const TypeDef* found_styp = NULL;
                        
                        // Try exact match first
                        for (uint32_t j = 0; j < smod->type_def_count; j++) {
                            const TypeDef* styp = smod->type_defs[j];
                            const char* styp_name = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->name : styp->as.enum_decl->name;
                            if (strcmp(styp_name, base_name) == 0) {
                                found_styp = styp;
                                break;
                            }
                        }

                        if (!found_styp) {
                            char base_buf[128];
                            const char* underscore = strchr(base_name, '_');
                            if (underscore) {
                                size_t len = (size_t)(underscore - base_name);
                                if (len >= sizeof(base_buf)) len = sizeof(base_buf) - 1;
                                strncpy(base_buf, base_name, len);
                                base_buf[len] = '\0';
                                base_name = base_buf;
                            }

                            for (uint32_t j = 0; j < smod->type_def_count; j++) {
                                const TypeDef* styp = smod->type_defs[j];
                                const char* styp_name = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->name : styp->as.enum_decl->name;
                                if (strcmp(styp_name, base_name) == 0) {
                                    found_styp = styp;
                                    break;
                                }
                            }
                        }

                        if (found_styp) {
                            const TypeDef* styp = found_styp;
                            Substitution* head_subst = NULL;
                            uint32_t param_count = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_param_count : styp->as.enum_decl->type_param_count;
                            char** params = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_params : styp->as.enum_decl->type_params;
                            char** bounds = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_bounds : styp->as.enum_decl->type_bounds;

                            for (uint32_t k = 0; k < param_count && k < substituted->as.struct_sum.type_arg_count; k++) {
                                const char* bound = bounds ? bounds[k] : NULL;
                                const ILType* arg_ty = substituted->as.struct_sum.type_args[k];

                                if (bound && !type_implements_trait(smod, arg_ty, bound, substs)) {
                                    char type_buf[128];
                                    il_type_print(arg_ty, type_buf, sizeof(type_buf));
                                    const char* found_styp_name = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->name : styp->as.enum_decl->name;
                                    if (report) diag_emit(report, DIAG_ERROR, loc_hint ? *loc_hint : (SourceLocation){.file_path = smod->file_path},
                                        "Type '%s' does not implement trait '%s' required by '%s' parameter '%s'", 
                                        type_buf, bound, found_styp_name, params[k]);
                                }

                                Substitution* n = calloc(1, sizeof(Substitution));
                                if (!n) break;
                                n->name = params[k];
                                n->bound = bound;
                                n->type = arg_ty;
                                n->next = head_subst;
                                head_subst = n;
                            }

                            if (styp->kind == TYPE_DEF_STRUCT) {
                                for (uint32_t k = 0; k < styp->as.struct_decl->field_count; k++) {
                                    il_type_def_add_field_pub(existing, styp->as.struct_decl->fields[k].name, lower_type_internal(smod, ilmod, report, release_mode, styp->as.struct_decl->fields[k].type, head_subst, depth + 1, loc_hint), styp->as.struct_decl->fields[k].is_pub, false, 0);
                                }
                            } else {
                                for (uint32_t k = 0; k < styp->as.enum_decl->variant_count; k++) {
                                    il_type_def_add_field_pub(existing, styp->as.enum_decl->variants[k].name, lower_type_internal(smod, ilmod, report, release_mode, styp->as.enum_decl->variants[k].type, head_subst, depth + 1, loc_hint), styp->as.enum_decl->variants[k].is_pub, styp->as.enum_decl->variants[k].has_tag, styp->as.enum_decl->variants[k].tag);
                                }
                            }
                            
                            while (head_subst) { Substitution* next = (Substitution*)head_subst->next; free(head_subst); head_subst = next; }
                        }
                    }
                    
                    free(mangled_name);
                    return res;
                }
            }

            // Not found, look up surface definition and monomorphize/resolve
            const TypeDef* styp = NULL;
            const char* lookup_name = substituted->as.struct_sum.name;
            
            // Try exact match first
            for (uint32_t i = 0; i < smod->type_def_count; i++) {
                const char* styp_name = (smod->type_defs[i]->kind == TYPE_DEF_STRUCT) ? smod->type_defs[i]->as.struct_decl->name : smod->type_defs[i]->as.enum_decl->name;
                if (strcmp(styp_name, lookup_name) == 0) {
                    styp = smod->type_defs[i];
                    break;
                }
            }

            if (!styp) {
                char base_buf[128];
                const char* underscore = strchr(lookup_name, '_');
                if (underscore) {
                    size_t len = (size_t)(underscore - lookup_name);
                    if (len >= sizeof(base_buf)) len = sizeof(base_buf) - 1;
                    strncpy(base_buf, lookup_name, len);
                    base_buf[len] = '\0';
                    lookup_name = base_buf;
                }

                for (uint32_t i = 0; i < smod->type_def_count; i++) {
                    const char* styp_name = (smod->type_defs[i]->kind == TYPE_DEF_STRUCT) ? smod->type_defs[i]->as.struct_decl->name : smod->type_defs[i]->as.enum_decl->name;
                    if (strcmp(styp_name, lookup_name) == 0) {
                        styp = smod->type_defs[i];
                        break;
                    }
                }
            }

            if (styp) {
                const char* styp_name = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->name : styp->as.enum_decl->name;
                // Visibility check
                if (!styp->is_pub && smod->file_path && styp->file_path) {
                    if (strcmp(smod->file_path, styp->file_path) != 0) {
                        diag_emit(report, DIAG_ERROR, loc_hint ? *loc_hint : (SourceLocation){.file_path = smod->file_path}, "Access to private type '%s'", styp_name);
                    }
                }
                
                Substitution* head_subst = NULL;
                if (substituted->as.struct_sum.type_arg_count > 0) {
                    uint32_t param_count = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_param_count : styp->as.enum_decl->type_param_count;
                    char** params = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_params : styp->as.enum_decl->type_params;
                    char** bounds = (styp->kind == TYPE_DEF_STRUCT) ? styp->as.struct_decl->type_bounds : styp->as.enum_decl->type_bounds;

                    for (uint32_t k = 0; k < param_count && k < substituted->as.struct_sum.type_arg_count; k++) {
                        const char* bound = bounds ? bounds[k] : NULL;
                        const ILType* arg_ty = substituted->as.struct_sum.type_args[k];

                        if (bound && !type_implements_trait(smod, arg_ty, bound, substs)) {
                            char type_buf[128];
                            il_type_print(arg_ty, type_buf, sizeof(type_buf));
                            if (report) diag_emit(report, DIAG_ERROR, loc_hint ? *loc_hint : (SourceLocation){.file_path = smod->file_path},
                                "Type '%s' does not implement trait '%s' required by '%s' parameter '%s'", 
                                type_buf, bound, styp_name, params[k]);
                        }

                        Substitution* n = calloc(1, sizeof(Substitution));
                        if (!n) break;
                        n->name = params[k];
                        n->bound = bound;
                        n->type = arg_ty;
                        n->next = head_subst;
                        head_subst = n;
                    }
                }
                

                ILTypeDef* ityp = (styp->kind == TYPE_DEF_STRUCT)
                    ? il_type_def_struct_create((uint32_t)(ilmod->next_type_def_id++), mangled_name, styp->file_path, styp->is_pub)
                    : il_type_def_sum_create((uint32_t)(ilmod->next_type_def_id++), mangled_name, styp->file_path, styp->is_pub);
                il_mod_add_type_def(ilmod, ityp);


                if (styp->kind == TYPE_DEF_STRUCT) {
                    for (uint32_t j = 0; j < styp->as.struct_decl->field_count; j++) {
                        il_type_def_add_field_pub(ityp, styp->as.struct_decl->fields[j].name, lower_type_internal(smod, ilmod, report, release_mode, styp->as.struct_decl->fields[j].type, head_subst, depth + 1, loc_hint), styp->as.struct_decl->fields[j].is_pub, false, 0);
                    }
                } else {
                    for (uint32_t j = 0; j < styp->as.enum_decl->variant_count; j++) {
                        il_type_def_add_field_pub(ityp, styp->as.enum_decl->variants[j].name, lower_type_internal(smod, ilmod, report, release_mode, styp->as.enum_decl->variants[j].type, head_subst, depth + 1, loc_hint), styp->as.enum_decl->variants[j].is_pub, styp->as.enum_decl->variants[j].has_tag, styp->as.enum_decl->variants[j].tag);
                    }
                }


                bool is_gen = false;
                for (uint32_t a = 0; a < substituted->as.struct_sum.type_arg_count; a++) {
                    if (il_type_is_generic_mod(ilmod, substituted->as.struct_sum.type_args[a])) {
                        is_gen = true;
                        break;
                    }
                }
                if (!is_gen) {
                    maybe_register_drop(smod, ilmod, report, release_mode, styp_name, mangled_name, substituted->as.struct_sum.type_args, ityp);
                }
                
                while (head_subst) {
                    Substitution* n = (Substitution*)head_subst->next;
                    free(head_subst);
                    head_subst = n;
                }

                const ILType* res = (styp->kind == TYPE_DEF_STRUCT) ? 
                    il_type_struct_gen(mangled_name, ityp->id, substituted->as.struct_sum.type_args, substituted->as.struct_sum.type_arg_count) :
                    il_type_sum_gen(mangled_name, ityp->id, substituted->as.struct_sum.type_args, substituted->as.struct_sum.type_arg_count);
                free(mangled_name);
                return res;
            }

            // Still not found? Check impl aliases or global aliases
            for (uint32_t i = 0; i < smod->impl_count; i++) {
                const ImplDecl* impl = smod->impls[i];
                if (!impl->target_name) continue;
                size_t tn_len = strlen(impl->target_name);
                if (strncmp(substituted->as.struct_sum.name, impl->target_name, tn_len) == 0 && substituted->as.struct_sum.name[tn_len] == '.') {
                    const char* alias_name = substituted->as.struct_sum.name + tn_len + 1;
                    for (uint32_t j = 0; j < impl->type_alias_count; j++) {
                        if (strcmp(impl->type_aliases[j]->name, alias_name) == 0) {
                            const ILType* resolved = lower_type_internal(smod, ilmod, report, release_mode, impl->type_aliases[j]->target, substs, depth + 1, loc_hint);
                            if (resolved) {
                                free(mangled_name);
                                return resolved;
                            }
                        }
                    }
                }
            }
            for (uint32_t i = 0; i < smod->type_alias_count; i++) {
                    if (strcmp(smod->type_aliases[i]->name, substituted->as.struct_sum.name) == 0) {
                        const ILType* resolved = lower_type_internal(smod, ilmod, report, release_mode, smod->type_aliases[i]->target, substs, depth + 1, loc_hint);
                        if (resolved) {
                            free(mangled_name);
                            return resolved;
                        }
                    }
            }
            
            // Final fallback: unresolved type.
            if (report) diag_emit(report, DIAG_ERROR, loc_hint ? *loc_hint : (SourceLocation){.file_path = smod->file_path}, "Unresolved type '%s'", substituted->as.struct_sum.name);
            free(mangled_name);
            return substituted;
        }
    }

    return substituted;
}

const ILType* lower_type(const SurfaceModule* smod, ILModule* ilmod, DiagnosticReport* report, bool release_mode, const ILType* type, const Substitution* substs) {
    return lower_type_internal(smod, ilmod, report, release_mode, type, substs, 0, NULL);
}

const ILType* lower_type_with_loc(const SurfaceModule* smod, ILModule* ilmod, DiagnosticReport* report, bool release_mode, const ILType* type, const Substitution* substs, SourceLocation loc) {
    return lower_type_internal(smod, ilmod, report, release_mode, type, substs, 0, &loc);
}

static void verify_type_no_cycles_rec(ILModule* mod, const ILType* type, uint32_t* path, uint32_t path_len, DiagnosticReport* report) {
    if (!type) return;
    if (type->kind == IL_TY_STRUCT || type->kind == IL_TY_SUM) {
        uint32_t id = type->as.struct_sum.type_def_id;
        if (id == 0) return;
        
        for (uint32_t i = 0; i < path_len; i++) {
            if (path[i] == id) {
                // Found a cycle!
                const ILTypeDef* def = il_mod_get_type_def(mod, id);
                if (report) {
                    diag_emit(report, DIAG_ERROR, (SourceLocation){.file_path = def ? def->file_path : NULL}, 
                        "Recursive type '%s' has infinite size (must use pointer or box for recursion)", 
                        def ? def->name : "unknown");
                }
                return;
            }
        }
        
        const ILTypeDef* def = il_mod_get_type_def(mod, id);
        if (!def) return;
        
        // Add to path and recurse into fields
        uint32_t* next_path = malloc(sizeof(uint32_t) * (path_len + 1));
        if (!next_path) return;
        memcpy(next_path, path, sizeof(uint32_t) * path_len);
        next_path[path_len] = id;
        
        for (uint32_t i = 0; i < def->field_count; i++) {
            verify_type_no_cycles_rec(mod, def->fields[i].type, next_path, path_len + 1, report);
        }
        free(next_path);
    } else if (type->kind == IL_TY_ARRAY) {
        verify_type_no_cycles_rec(mod, type->as.array.element, path, path_len, report);
    } else if (type->kind == IL_TY_TUPLE) {
        for (uint32_t i = 0; i < type->as.tuple.count; i++) {
            verify_type_no_cycles_rec(mod, type->as.tuple.elements[i], path, path_len, report);
        }
    }
    // Pointers, Boxes, etc terminate the recursion for size/layout.
}

void verify_no_type_cycles(ILModule* mod, DiagnosticReport* report) {
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        const ILTypeDef* def = mod->type_defs[i];
        for (uint32_t j = 0; j < def->field_count; j++) {
            uint32_t path[1] = { def->id };
            verify_type_no_cycles_rec(mod, def->fields[j].type, path, 1, report);
        }
    }
}
