#ifndef IL_CFG_H
#define IL_CFG_H

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include "il_instr.h"
#include "il_type.h"
#include "string_table.h"

typedef struct ILBasicBlock ILBasicBlock;

/* A (index_id, length_id) pair representing a satisfied bounds_check. */
typedef struct {
    uint32_t index_id;
    uint32_t length_id;
} BoundsPair;

struct ILBasicBlock {
    uint32_t id;
    uint32_t rpo_index;
    bool visited; // For graph traversals

    ILInstruction** instructions;
    uint32_t instr_count;
    uint32_t instr_capacity;

    ILBasicBlock** successors;
    uint32_t succ_count;
    uint32_t succ_capacity;

    ILBasicBlock** predecessors;
    uint32_t pred_count;
    uint32_t pred_capacity;

    struct ILBasicBlock* idom;

    /* Precomputed checked-pair set (populated by il_func_precompute_bounds).
     * Contains all (index_id, length_id) pairs from bounds_check instructions
     * in this block and all blocks that dominate it. */
    BoundsPair* checked_pairs;
    uint32_t    checked_pair_count;
    uint32_t    checked_pair_capacity;
};

typedef struct {
    uint32_t id;
    const char* name;

    const ILType ** param_types;
    uint32_t param_count;
    const ILType* return_type;

    ILBasicBlock** blocks;
    uint32_t block_count;
    uint32_t block_capacity;

    ILBasicBlock* entry_block;
    bool is_extern;
    bool is_variadic;
    bool is_sret;
    bool is_pub;
    bool is_must_use;
    const char* file_path;
    const ILType* sret_type;
    char** val_names;
    uint32_t val_names_capacity;
} ILFunction;

typedef struct {
    uint32_t id;
    const char* name;
    const ILType* type;
    uint8_t* init_data;
    uint32_t data_len;
    bool is_const;
    bool is_pub;
    const char* file_path;
} ILGlobal;

typedef struct {
    const char* name;
    const ILType* type;
    uint64_t tag;
    bool has_tag;
    bool is_pub;
} ILField;

typedef struct {
    uint32_t id;
    const char* name;
    ILField* fields;
    uint32_t field_count;
    uint32_t field_capacity;
    bool is_sum;
    bool is_pub;
    bool is_generic;
    char* drop_fn_name;
    const char* file_path;
} ILTypeDef;

typedef struct ILModule {
    ILFunction** functions;
    uint32_t function_count;
    uint32_t function_capacity;

    ILGlobal** globals;
    uint32_t global_count;
    uint32_t global_capacity;

    ILTypeDef** type_defs;
    uint32_t type_def_count;
    uint32_t type_def_capacity;

    StringTable* region_table;
    uint32_t next_label_id;
    uint32_t next_type_def_id;
} ILModule;

/* Returns true if fn receives an implicit context/environment pointer parameter
 * (every non-extern, non-main Zoril function does — see ABI spec §7.1). */
static inline bool il_func_needs_env_ptr(const ILFunction* fn) {
    return !fn->is_extern && fn->name && strcmp(fn->name, "main") != 0;
}

/* Returns the index of the first user-declared parameter, accounting for the
 * implicit sret pointer (if any) and the implicit context pointer (if any). */
static inline uint32_t il_func_user_param_offset(const ILFunction* fn) {
    return (fn->is_sret ? 1u : 0u) + (il_func_needs_env_ptr(fn) ? 1u : 0u);
}

// Global functions
ILGlobal* il_global_create(uint32_t id, const char* name, const ILType* type, bool is_const, bool is_pub, const char* file_path);
ILGlobal* il_global_create_synthetic(uint32_t id, const char* name, const ILType* type, bool is_const);
void il_global_set_init_data(ILGlobal* global, const uint8_t* data, uint32_t len);
void il_global_free(ILGlobal* global);

// Type definition functions
ILTypeDef* il_type_def_struct_create(uint32_t id, const char* name, const char* file_path, bool is_pub);
ILTypeDef* il_type_def_sum_create(uint32_t id, const char* name, const char* file_path, bool is_pub);
void il_type_def_add_field(ILTypeDef* def, const char* name, const ILType* type);
void il_type_def_add_field_pub(ILTypeDef* def, const char* name, const ILType* type, bool is_pub, bool has_tag, uint64_t tag);
void il_type_def_free(ILTypeDef* def);

// Basic Block functions
ILBasicBlock* il_block_create(uint32_t id);
void il_block_add_instr(ILBasicBlock* block, ILInstruction* instr);
void il_block_insert_instr(ILBasicBlock* block, uint32_t index, ILInstruction* instr);
void il_block_add_successor(ILBasicBlock* block, ILBasicBlock* succ);
void il_block_free(ILBasicBlock* block);

// Function functions
ILFunction* il_func_create(uint32_t id, const char* name, const ILType* return_type, bool is_pub, bool is_must_use, const char* file_path);
ILFunction* il_func_create_synthetic(uint32_t id, const char* name, const ILType* ret_ty);
ILFunction* il_func_create_synthetic_with_params(uint32_t id, const ILType** param_types, uint32_t param_count, const char* name, const ILType* ret_ty);
void il_func_add_param(ILFunction* func, const ILType* type);
void il_func_add_block(ILFunction* func, ILBasicBlock* block);
void il_func_resolve_successors(ILFunction* func);
ILBasicBlock* find_block_by_id(const ILFunction* func, uint32_t id);
void il_func_assign_rpo_ids(ILFunction* func);
void il_func_calculate_dominators(ILFunction* func);
void il_func_precompute_bounds(ILFunction* func);
bool il_block_dominates(const ILBasicBlock* a, const ILBasicBlock* b);
void il_func_free(ILFunction* func);
void il_func_set_val_name(ILFunction* func, uint32_t ssa_id, const char* name);

// Module functions
ILModule* il_mod_create(void);
void il_mod_add_func(ILModule* mod, ILFunction* func);
ILFunction* il_mod_get_func_by_name(const ILModule* mod, const char* name);
ILTypeDef* il_mod_get_type_def_by_name(const ILModule* mod, const char* name);
ILGlobal* il_mod_get_global_by_name(const ILModule* mod, const char* name);
void il_mod_add_global(ILModule* mod, ILGlobal* global);
void il_mod_add_type_def(ILModule* mod, ILTypeDef* def);
ILTypeDef* il_mod_get_type_def(const ILModule* mod, uint32_t id);
void il_mod_fixup_types(ILModule* mod);
void il_mod_free(ILModule* mod);

/* Type size and layout — implementations live in il_type.c */
size_t il_type_size(const ILModule* mod, const ILType* type);
size_t il_type_align(const ILModule* mod, const ILType* type);
size_t il_type_def_size(const ILModule* mod, const ILTypeDef* def);
size_t il_type_def_tag_size(const ILTypeDef* def);
size_t il_type_def_get_field_offset(const ILModule* mod, const ILTypeDef* def, uint32_t field_index);
size_t il_type_get_tuple_field_offset(const ILModule* mod, const ILType* type, uint32_t field_index);


#endif
