#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "il_cfg.h"

ILBasicBlock* il_block_create(uint32_t id) {
    ILBasicBlock* block = calloc(1, sizeof(ILBasicBlock));
    if (block) {
        block->id = id;
    }
    return block;
}

void il_block_add_instr(ILBasicBlock* block, ILInstruction* instr) {
    if (!block || !instr) return;
    if (block->instr_count >= block->instr_capacity) {
        uint32_t new_cap = block->instr_capacity == 0 ? 8 : block->instr_capacity * 2;
        ILInstruction** new_instrs = realloc(block->instructions, sizeof(ILInstruction*) * new_cap);
        if (!new_instrs) return;
        block->instructions = new_instrs;
        block->instr_capacity = new_cap;
    }
    block->instructions[block->instr_count++] = instr;
}

void il_block_insert_instr(ILBasicBlock* block, uint32_t index, ILInstruction* instr) {
    if (!block || !instr || index > block->instr_count) return;
    il_block_add_instr(block, instr);
    if (block->instructions[block->instr_count - 1] != instr) return;
    memmove(&block->instructions[index + 1], &block->instructions[index],
            sizeof(ILInstruction*) * (block->instr_count - 1 - index));
    block->instructions[index] = instr;
}

void il_block_add_successor(ILBasicBlock* block, ILBasicBlock* succ) {
    if (!block || !succ) return;
    if (block->succ_count >= block->succ_capacity) {
        uint32_t new_cap = block->succ_capacity == 0 ? 4 : block->succ_capacity * 2;
        ILBasicBlock** new_succs = realloc(block->successors, sizeof(ILBasicBlock*) * new_cap);
        if (!new_succs) return;
        block->successors = new_succs;
        block->succ_capacity = new_cap;
    }
    block->successors[block->succ_count++] = succ;

    // Also add to predecessor list of successor
    if (succ->pred_count >= succ->pred_capacity) {
        uint32_t new_cap = succ->pred_capacity == 0 ? 4 : succ->pred_capacity * 2;
        ILBasicBlock** new_preds = realloc(succ->predecessors, sizeof(ILBasicBlock*) * new_cap);
        if (!new_preds) return;
        succ->predecessors = new_preds;
        succ->pred_capacity = new_cap;
    }
    succ->predecessors[succ->pred_count++] = block;
}

void il_block_free(ILBasicBlock* block) {
    if (!block) return;
    for (uint32_t i = 0; i < block->instr_count; i++) {
        il_instr_free(block->instructions[i]);
    }
    free(block->instructions);
    free(block->successors);
    free(block->predecessors);
    free(block->checked_pairs);
    free(block);
}

ILFunction* il_func_create(uint32_t id, const char* name, const ILType* return_type, bool is_pub, bool is_must_use, const char* file_path) {
    ILFunction* func = calloc(1, sizeof(ILFunction));
    if (func) {
        func->id = id;
        func->name = name ? strdup(name) : NULL;
        func->return_type = return_type;
        func->is_pub = is_pub;
        func->is_must_use = is_must_use;
        func->file_path = file_path ? strdup(file_path) : NULL;
    }
    return func;
}

ILFunction* il_func_create_synthetic(uint32_t id, const char* name, const ILType* return_type) {
    return il_func_create_synthetic_with_params(id, NULL, 0, name, return_type);
}

ILFunction* il_func_create_synthetic_with_params(uint32_t id, const ILType** param_types, uint32_t param_count, const char* name, const ILType* return_type) {
    ILFunction* func = il_func_create(id, name, return_type, true, false, NULL);
    if (!func) return NULL;
    for (uint32_t i = 0; i < param_count; i++) {
        il_func_add_param(func, param_types[i]);
    }
    return func;
}

void il_func_add_param(ILFunction* func, const ILType* type) {
    const ILType ** new_params = realloc(func->param_types, sizeof(const ILType*) * (func->param_count + 1));
    if (!new_params) return;
    func->param_types = new_params;
    func->param_types[func->param_count++] = type;
}

void il_func_add_block(ILFunction* func, ILBasicBlock* block) {
    if (func->block_count >= func->block_capacity) {
        uint32_t new_cap = func->block_capacity == 0 ? 4 : func->block_capacity * 2;
        ILBasicBlock** new_blocks = realloc(func->blocks, sizeof(ILBasicBlock*) * new_cap);
        if (!new_blocks) return;
        func->blocks = new_blocks;
        func->block_capacity = new_cap;
    }
    if (func->block_count == 0) {
        func->entry_block = block;
    }
    func->blocks[func->block_count++] = block;
}

void il_func_free(ILFunction* func) {
    if (!func) return;
    free((void*)func->name);
    
    free((void*)func->file_path);
    for (uint32_t i = 0; i < func->param_count; i++) {
    }
    free(func->param_types);
    if (func->val_names) {
        for (uint32_t i = 0; i < func->val_names_capacity; i++) {
            if (func->val_names[i]) free(func->val_names[i]);
        }
        free(func->val_names);
    }
    for (uint32_t i = 0; i < func->block_count; i++) {
        il_block_free(func->blocks[i]);
    }
    free(func->blocks);
    free(func);
}

void il_func_set_val_name(ILFunction* func, uint32_t ssa_id, const char* name) {
    if (!func || !name) return;
    if (ssa_id >= func->val_names_capacity) {
        uint32_t old_cap = func->val_names_capacity;
        uint32_t new_cap = old_cap == 0 ? 64 : old_cap * 2;
        while (ssa_id >= new_cap) new_cap *= 2;
        func->val_names = realloc(func->val_names, new_cap * sizeof(char*));
        memset(func->val_names + old_cap, 0, (new_cap - old_cap) * sizeof(char*));
        func->val_names_capacity = new_cap;
    }
    if (func->val_names[ssa_id]) {
        free(func->val_names[ssa_id]);
    }
    func->val_names[ssa_id] = strdup(name);
}

ILModule* il_mod_create(void) {
    ILModule* mod = calloc(1, sizeof(ILModule));
    if (mod) {
        mod->region_table = string_table_create();
        mod->next_label_id = 1;
        mod->next_type_def_id = 1;
    }
    return mod;
}

void il_mod_add_func(ILModule* mod, ILFunction* func) {
    if (mod->function_count >= mod->function_capacity) {
        uint32_t new_cap = mod->function_capacity == 0 ? 4 : mod->function_capacity * 2;
        ILFunction** new_funcs = realloc(mod->functions, sizeof(ILFunction*) * new_cap);
        if (!new_funcs) return;
        mod->functions = new_funcs;
        mod->function_capacity = new_cap;
    }
    mod->functions[mod->function_count++] = func;
}

ILFunction* il_mod_get_func_by_name(const ILModule* mod, const char* name) {
    if (!mod || !name) return NULL;
    for (uint32_t i = 0; i < mod->function_count; i++) {
        if (mod->functions[i]->name && strcmp(mod->functions[i]->name, name) == 0) {
            return mod->functions[i];
        }
    }
    return NULL;
}

ILTypeDef* il_mod_get_type_def_by_name(const ILModule* mod, const char* name) {
    if (!mod || !name) return NULL;
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        if (mod->type_defs[i]->name && strcmp(mod->type_defs[i]->name, name) == 0) {
            return mod->type_defs[i];
        }
    }
    return NULL;
}

ILGlobal* il_mod_get_global_by_name(const ILModule* mod, const char* name) {
    if (!mod || !name) return NULL;
    for (uint32_t i = 0; i < mod->global_count; i++) {
        if (mod->globals[i]->name && strcmp(mod->globals[i]->name, name) == 0) {
            return mod->globals[i];
        }
    }
    return NULL;
}

void il_mod_add_global(ILModule* mod, ILGlobal* global) {
    if (!mod || !global) return;
    if (mod->global_count >= mod->global_capacity) {
        uint32_t new_cap = mod->global_capacity == 0 ? 4 : mod->global_capacity * 2;
        ILGlobal** new_globals = realloc(mod->globals, sizeof(ILGlobal*) * new_cap);
        if (!new_globals) return;
        mod->globals = new_globals;
        mod->global_capacity = new_cap;
    }
    mod->globals[mod->global_count++] = global;
}

ILGlobal* il_global_create(uint32_t id, const char* name, const ILType* type, bool is_const, bool is_pub, const char* file_path) {
    ILGlobal* global = calloc(1, sizeof(ILGlobal));
    if (global) {
        global->id = id;
        global->name = name ? strdup(name) : NULL;
        global->type = type;
        global->is_const = is_const;
        global->is_pub = is_pub;
        global->file_path = file_path ? strdup(file_path) : NULL;
    }
    return global;
}

ILGlobal* il_global_create_synthetic(uint32_t id, const char* name, const ILType* type, bool is_const) {
    return il_global_create(id, name, type, is_const, true, NULL);
}

void il_global_set_init_data(ILGlobal* global, const uint8_t* data, uint32_t len) {
    if (!global) return;
    free(global->init_data);
    global->init_data = malloc(len);
    if (global->init_data) {
        memcpy(global->init_data, data, len);
        global->data_len = len;
    }
}

void il_global_free(ILGlobal* global) {
    if (!global) return;
    free((void*)global->name);
    free(global->init_data);
    free((void*)global->file_path);
    free(global);
}

ILTypeDef* il_type_def_struct_create(uint32_t id, const char* name, const char* file_path, bool is_pub) {
    ILTypeDef* def = calloc(1, sizeof(ILTypeDef));
    if (def) {
        def->id = id;
        def->name = name ? strdup(name) : NULL;
        def->is_sum = false;
        def->is_pub = is_pub;
        def->file_path = file_path ? strdup(file_path) : NULL;
    }
    return def;
}

ILTypeDef* il_type_def_sum_create(uint32_t id, const char* name, const char* file_path, bool is_pub) {
    ILTypeDef* def = calloc(1, sizeof(ILTypeDef));
    if (def) {
        def->id = id;
        def->name = name ? strdup(name) : NULL;
        def->is_sum = true;
        def->is_pub = is_pub;
        def->file_path = file_path ? strdup(file_path) : NULL;
    }
    return def;
}

void il_type_def_add_field_pub(ILTypeDef* def, const char* name, const ILType* type, bool is_pub, bool has_tag, uint64_t tag) {
    if (!def || !type) return;
    
    // Prevent duplicate fields by name
    if (name) {
        for (uint32_t i = 0; i < def->field_count; i++) {
            if (def->fields[i].name && strcmp(def->fields[i].name, name) == 0) {
                // If the field already exists, we still consume the new type handle.
                return;
            }
        }
    }

    if (def->field_count >= def->field_capacity) {
        uint32_t new_cap = def->field_capacity == 0 ? 4 : def->field_capacity * 2;
        ILField* new_fields = realloc(def->fields, sizeof(ILField) * new_cap);
        if (!new_fields) {
             // Consume on failure
            return;
        }
        def->fields = new_fields;
        def->field_capacity = new_cap;
    }
    def->fields[def->field_count].name = name ? strdup(name) : NULL;
    def->fields[def->field_count].type = type; // Takes ownership
    def->fields[def->field_count].is_pub = is_pub;
    def->fields[def->field_count].has_tag = has_tag;
    def->fields[def->field_count].tag = tag;
    def->field_count++;
}

void il_type_def_add_field(ILTypeDef* def, const char* name, const ILType* type) {
    il_type_def_add_field_pub(def, name, type, true, false, 0); // Default to public for tests/synthetic
}

void il_type_def_free(ILTypeDef* def) {
    if (!def) return;
    free((void*)def->name);
    free(def->drop_fn_name);
    free((void*)def->file_path);
    for (uint32_t i = 0; i < def->field_count; i++) {
        free((void*)def->fields[i].name);
    }
    free(def->fields);
    free(def);
}

void il_mod_add_type_def(ILModule* mod, ILTypeDef* def) {
    if (!mod || !def) return;
    
    // Prevent duplicates by name
    if (def->name) {
        for (uint32_t i = 0; i < mod->type_def_count; i++) {
            if (mod->type_defs[i]->name && strcmp(mod->type_defs[i]->name, def->name) == 0) {
                // If they are different pointers, it's a bug in the caller, but we must not add it.
                if (mod->type_defs[i] != def) {
                    // Note: we can't easily free 'def' here because it might be partially owned.
                    // But we must stop the duplicate.
                }
                return;
            }
        }
    }

    if (mod->type_def_count >= mod->type_def_capacity) {
        uint32_t new_cap = mod->type_def_capacity == 0 ? 4 : mod->type_def_capacity * 2;
        ILTypeDef** new_defs = realloc(mod->type_defs, sizeof(ILTypeDef*) * new_cap);
        if (!new_defs) return;
        mod->type_defs = new_defs;
        mod->type_def_capacity = new_cap;
    }
    mod->type_defs[mod->type_def_count++] = def;
}

ILTypeDef* il_mod_get_type_def(const ILModule* mod, uint32_t id) {
    if (!mod) return NULL;
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        if (mod->type_defs[i]->id == id) return mod->type_defs[i];
    }
    return NULL;
}

void il_mod_free(ILModule* mod) {
    if (!mod) return;
    for (uint32_t i = 0; i < mod->function_count; i++) {
        il_func_free(mod->functions[i]);
    }
    free(mod->functions);
    for (uint32_t i = 0; i < mod->global_count; i++) {
        il_global_free(mod->globals[i]);
    }
    free(mod->globals);
    for (uint32_t i = 0; i < mod->type_def_count; i++) {
        il_type_def_free(mod->type_defs[i]);
    }
    free(mod->type_defs);
    string_table_free(mod->region_table);
    free(mod);
}

static void dfs_postorder(ILBasicBlock* block, uint32_t* current_rpo) {
    if (!block) return;
    block->visited = true;

    for (uint32_t i = 0; i < block->succ_count; ++i) {
        ILBasicBlock* succ = block->successors[i];
        if (!succ->visited) {
            dfs_postorder(succ, current_rpo);
        }
    }

    // Assign RPO index
    block->rpo_index = (*current_rpo)--;
}

static int compare_blocks_by_rpo(const void* a, const void* b) {
    const ILBasicBlock* const* block_a = (const ILBasicBlock* const*)a;
    const ILBasicBlock* const* block_b = (const ILBasicBlock* const*)b;
    if ((*block_a)->rpo_index < (*block_b)->rpo_index) return -1;
    if ((*block_a)->rpo_index > (*block_b)->rpo_index) return 1;
    return 0;
}

void il_func_assign_rpo_ids(ILFunction* func) {
    if (!func || func->block_count == 0 || !func->entry_block) return;

    for (uint32_t i = 0; i < func->block_count; ++i) {
        func->blocks[i]->visited = false;
        // Reset RPO index
        func->blocks[i]->rpo_index = 0xFFFFFFFF;
    }

    uint32_t current_rpo = func->block_count - 1;
    dfs_postorder(func->entry_block, &current_rpo);

    // Any unreachable blocks will still have rpo_index = 0xFFFFFFFF
    qsort(func->blocks, func->block_count, sizeof(ILBasicBlock*), compare_blocks_by_rpo);

    // Adjust unreachable blocks if any (they are at the end)
    if (current_rpo != 0xFFFFFFFF && current_rpo < func->block_count - 1) {
        uint32_t offset = current_rpo + 1;
        for (uint32_t i = 0; i < func->block_count; i++) {
            if (func->blocks[i]->rpo_index != 0xFFFFFFFF) {
                func->blocks[i]->rpo_index -= offset;
            }
        }
    }
}

static ILBasicBlock* intersect_idoms(const ILBasicBlock* b1, const ILBasicBlock* b2) {
    const ILBasicBlock* f1 = b1;
    const ILBasicBlock* f2 = b2;
    if (!f1) return (ILBasicBlock*)(uintptr_t)f2;
    if (!f2) return (ILBasicBlock*)(uintptr_t)f1;
    
    while (f1 != f2) {
        while (f1 != NULL && f2 != NULL && f1->rpo_index > f2->rpo_index) {
            f1 = f1->idom;
        }
        while (f2 != NULL && f1 != NULL && f2->rpo_index > f1->rpo_index) {
            f2 = f2->idom;
        }
        if (!f1 || !f2) break;
    }
    return (ILBasicBlock*)(uintptr_t)(f1 ? f1 : f2);
}

void il_func_calculate_dominators(ILFunction* func) {
    if (!func || func->block_count == 0 || !func->entry_block) return;
    
    // Ensure successors and RPO IDs are up-to-date
    il_func_resolve_successors(func);
    il_func_assign_rpo_ids(func);

    ILBasicBlock* entry = func->entry_block;
    entry->idom = entry;

    bool changed = true;
    uint32_t iterations = 0;
    while (changed && iterations < 1000) {
        iterations++;
        changed = false;
        for (uint32_t i = 0; i < func->block_count; i++) {
            ILBasicBlock* b = func->blocks[i];
            if (b == entry || b->rpo_index == 0xFFFFFFFF) continue;

            ILBasicBlock* new_idom = NULL;
            for (uint32_t p = 0; p < b->pred_count; p++) {
                ILBasicBlock* pred = b->predecessors[p];
                if (pred->idom != NULL) {
                    new_idom = pred;
                    break;
                }
            }

            if (new_idom != NULL) {
                for (uint32_t p = 0; p < b->pred_count; p++) {
                    const ILBasicBlock* pred = b->predecessors[p];
                    if (pred != new_idom && pred->idom != NULL) {
                        new_idom = intersect_idoms(pred, new_idom);
                    }
                }
            }

            if (b->idom != new_idom) {
                b->idom = new_idom;
                changed = true;
            }
        }
    }
    entry->idom = NULL;
}

bool il_block_dominates(const ILBasicBlock* a, const ILBasicBlock* b) {
    if (a == b) return true;
    const ILBasicBlock* curr = b->idom;
    while (curr) {
        if (curr == a) return true;
        curr = curr->idom;
    }
    return false;
}

ILBasicBlock* find_block_by_id(const ILFunction* func, uint32_t id) {
    for (uint32_t i = 0; i < func->block_count; i++) {
        if (func->blocks[i]->id == id) return func->blocks[i];
    }
    return NULL;
}

void il_func_resolve_successors(ILFunction* func) {
    if (!func) return;
    for (uint32_t b = 0; b < func->block_count; b++) {
        ILBasicBlock* block = func->blocks[b];
        // Clear old successors
        block->succ_count = 0;
        
        for (uint32_t i = 0; i < block->instr_count; i++) {
            const ILInstruction* instr = block->instructions[i];
            if (instr->opcode == IL_OP_BRANCH) {
                ILBasicBlock* t = find_block_by_id(func, instr->operands.branch.then_block_id);
                ILBasicBlock* e = find_block_by_id(func, instr->operands.branch.else_block_id);
                if (t) il_block_add_successor(block, t);
                if (e) il_block_add_successor(block, e);
            } else if (instr->opcode == IL_OP_JUMP) {
                ILBasicBlock* t = find_block_by_id(func, instr->operands.jump.target_block_id);
                if (t) il_block_add_successor(block, t);
            } else if (instr->opcode == IL_OP_VARIANT_MATCH) {
                ILBasicBlock* t = find_block_by_id(func, instr->operands.variant_match.target_block_id);
                ILBasicBlock* n = find_block_by_id(func, instr->operands.variant_match.next_block_id);
                if (t) il_block_add_successor(block, t);
                if (n) il_block_add_successor(block, n);
            }
        }
    }
}

const ILType* il_type_fixup(const void* vmod, const ILType* type) {
    if (!type || !vmod) return type;
    const ILModule* mod = (const ILModule*)vmod;

    if (type->kind == IL_TY_PTR) {
        const ILType* fixed = il_type_fixup(mod, type->as.ptr.pointee);
        if (fixed != type->as.ptr.pointee) return il_type_ptr(fixed, type->as.ptr.region_id, type->as.ptr.is_mut);
    } else if (type->kind == IL_TY_BOX) {
        const ILType* fixed = il_type_fixup(mod, type->as.box.pointee);
        if (fixed != type->as.box.pointee) return il_type_box(fixed, type->as.box.region_id, type->as.box.is_mut);
    } else if (type->kind == IL_TY_SLICE) {
        const ILType* fixed = il_type_fixup(mod, type->as.slice.element);
        if (fixed != type->as.slice.element) return il_type_slice(fixed, type->as.slice.region_id, type->as.slice.is_mut);
    } else if (type->kind == IL_TY_ARRAY) {
        const ILType* fixed = il_type_fixup(mod, type->as.array.element);
        if (fixed != type->as.array.element) return il_type_array(fixed, type->as.array.length);
    } else if (type->kind == IL_TY_TUPLE) {
        bool changed = false;
        const ILType ** elements = malloc(sizeof(const ILType*) * type->as.tuple.count);
        if (!elements) { perror("malloc"); exit(1); }
        for (uint32_t i = 0; i < type->as.tuple.count; i++) {
            elements[i] = il_type_fixup(mod, type->as.tuple.elements[i]);
            if (elements[i] != type->as.tuple.elements[i]) changed = true;
        }
        if (changed) {
            const ILType* res = il_type_tuple(elements, type->as.tuple.count);
            free(elements);
            return res;
        }
        free(elements);
    } else if (type->kind == IL_TY_STRUCT || type->kind == IL_TY_SUM) {
        uint32_t type_def_id = type->as.struct_sum.type_def_id;
        if (type->as.struct_sum.name && type_def_id == 0) {
            for (uint32_t i = 0; i < mod->type_def_count; i++) {
                if (strcmp(mod->type_defs[i]->name, type->as.struct_sum.name) == 0) {
                    type_def_id = mod->type_defs[i]->id;
                    break;
                }
            }
        }
        if (type_def_id != type->as.struct_sum.type_def_id) {
            if (type->kind == IL_TY_SUM)
                return il_type_sum_gen(type->as.struct_sum.name, type_def_id, type->as.struct_sum.type_args, type->as.struct_sum.type_arg_count);
            else
                return il_type_struct_gen(type->as.struct_sum.name, type_def_id, type->as.struct_sum.type_args, type->as.struct_sum.type_arg_count);
        }
    }
    return type;
}

void il_mod_fixup_types(ILModule* mod) {
    if (!mod) return;
    for (uint32_t f = 0; f < mod->function_count; f++) {
        ILFunction* func = mod->functions[f];
        for (uint32_t i = 0; i < func->param_count; i++) func->param_types[i] = il_type_fixup(mod, func->param_types[i]);
        func->return_type = il_type_fixup(mod, func->return_type);
        for (uint32_t b = 0; b < func->block_count; b++) {
            for (uint32_t i = 0; i < func->blocks[b]->instr_count; i++) {
                ILInstruction* instr = func->blocks[b]->instructions[i];
                instr->result_type = il_type_fixup(mod, instr->result_type);
            }
        }
    }
}

/* Add a (index_id, length_id) pair to a block's checked_pairs set, if not already
 * present.  Returns false on allocation failure. */
static bool block_add_checked_pair(ILBasicBlock* block, uint32_t index_id, uint32_t length_id) {
    for (uint32_t i = 0; i < block->checked_pair_count; i++) {
        if (block->checked_pairs[i].index_id == index_id &&
            block->checked_pairs[i].length_id == length_id) {
            return true; /* already present */
        }
    }
    if (block->checked_pair_count >= block->checked_pair_capacity) {
        uint32_t new_cap = block->checked_pair_capacity ? block->checked_pair_capacity * 2 : 4;
        BoundsPair* np = realloc(block->checked_pairs, new_cap * sizeof(BoundsPair));
        if (!np) return false;
        block->checked_pairs = np;
        block->checked_pair_capacity = new_cap;
    }
    block->checked_pairs[block->checked_pair_count].index_id  = index_id;
    block->checked_pairs[block->checked_pair_count].length_id = length_id;
    block->checked_pair_count++;
    return true;
}

/* Precompute checked-pair sets for every block in the function.
 *
 * Must be called after il_func_assign_rpo_ids and il_func_calculate_dominators.
 * Walks blocks in RPO order (dominators before dominated) and for each block:
 *   1. Copies all pairs from the immediate dominator.
 *   2. Appends pairs from bounds_check instructions within this block.
 *
 * After this call, il_block_is_bounds_checked() is O(n) in the number of
 * checked pairs (typically small and bounded by function size), vs the previous
 * O(B * I) dominator-scan per access. */

void il_func_precompute_bounds(ILFunction* func) {
    if (!func) return;
    /* Reset existing sets */
    for (uint32_t b = 0; b < func->block_count; b++) {
        ILBasicBlock* block = func->blocks[b];
        free(block->checked_pairs);
        block->checked_pairs = NULL;
        block->checked_pair_count = 0;
        block->checked_pair_capacity = 0;
    }
    /* Walk in RPO order: blocks are already sorted by rpo_index ascending,
     * so func->blocks[0] is the entry and each block's idom has a lower RPO. */
    for (uint32_t b = 0; b < func->block_count; b++) {
        ILBasicBlock* block = func->blocks[b];
        /* Inherit pairs from immediate dominator (idom points to itself for entry) */
        const ILBasicBlock* idom = block->idom;
        if (idom && idom != block) {
            for (uint32_t p = 0; p < idom->checked_pair_count; p++) {
                block_add_checked_pair(block,
                    idom->checked_pairs[p].index_id,
                    idom->checked_pairs[p].length_id);
            }
        }
        /* Add pairs from bounds_check instructions in this block */
        for (uint32_t i = 0; i < block->instr_count; i++) {
            const ILInstruction* instr = block->instructions[i];
            if (instr->opcode == IL_OP_BOUNDS_CHECK) {
                block_add_checked_pair(block,
                    instr->operands.bounds_check.index,
                    instr->operands.bounds_check.length);
            }
        }
    }
}
