#ifndef QBE_EMIT_H
#define QBE_EMIT_H

#include <stdio.h>
#include "il_type.h"
#include "il_instr.h"
#include "il_cfg.h"

// Maps a Zoril IL type to its corresponding QBE type string.
// Returns NULL if the type cannot be mapped directly.
const char* qbe_map_type(const ILType* type);

// Generates a QBE temporary name for a Zoril SSA ID.
void qbe_map_ssa(uint32_t id, char* buf);

// Emits a QBE instruction for a Zoril IL instruction.
void qbe_emit_instr(const ILModule* mod, const ILFunction* func, const ILInstruction* instr, uint32_t current_block_id, FILE* out);

// Emits a QBE block.
void qbe_emit_block(const ILModule* mod, const ILFunction* func, const ILBasicBlock* block, FILE* out);

// Emits a full QBE function.
void qbe_emit_func(const ILModule* mod, const ILFunction* func, FILE* out);

// Emits a full QBE module.
void qbe_emit_module(const ILModule* mod, FILE* out);

#endif
