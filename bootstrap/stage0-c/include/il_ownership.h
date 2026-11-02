#ifndef IL_OWNERSHIP_H
#define IL_OWNERSHIP_H

#include "il_cfg.h"
#include <stdbool.h>

typedef enum {
    VAL_UNDEFINED,
    VAL_AVAILABLE,
    VAL_MOVED
} ValueStatus;

typedef struct OwnershipState {
    uint32_t count;
    uint8_t packed_status[]; // Flexible array member
} OwnershipState;

size_t ownership_state_size(uint32_t count);
void ownership_state_init(OwnershipState* state, uint32_t count);
OwnershipState* ownership_state_create(uint32_t count);
void ownership_state_free(OwnershipState* state);
OwnershipState* ownership_state_copy(const OwnershipState* state);
void ownership_state_copy_to(OwnershipState* dest, const OwnershipState* src);
bool ownership_state_merge(OwnershipState* target, const OwnershipState* source);

ValueStatus ownership_get(const OwnershipState* state, uint32_t id);
void ownership_set(OwnershipState* state, uint32_t id, ValueStatus status);

uint32_t il_func_get_max_ssa_id(const ILFunction* func);

typedef struct {
    OwnershipState** states;
    const ILType ** types;
    uint32_t ssa_count;
} OwnershipAnalysisResult;

OwnershipAnalysisResult il_func_analyze_ownership(const void* mod, const ILFunction* func);
void il_func_ownership_result_free(OwnershipAnalysisResult res, uint32_t block_count);

void ownership_update_for_instr(OwnershipState* state, const void* mod, const ILFunction* func, const ILInstruction* instr, const ILType** types);

#endif
