#ifndef IL_PASS_H
#define IL_PASS_H

#include "il_cfg.h"

// il_func_auto_drop inserts DROP instructions for any available non-copy values
// at all return points in the function.
void il_func_auto_drop(const void* mod, ILFunction* func);

// il_pass_const_fold performs simple constant folding on a function.
// All binary arithmetic and comparison instructions whose both operands are
// known compile-time constants are replaced by IL_OP_CONST instructions.
// The function must have had il_func_assign_rpo_ids called first.
void il_pass_const_fold(const void* mod, ILFunction* func);

// il_pass_must_use_check scans the function for calls to #[must_use] functions
// whose result is immediately dropped without being used.
#include "diagnostics.h"
void il_pass_must_use_check(const void* mod, ILFunction* func, DiagnosticReport* report);

// il_pass_arena_capacity_check verifies that allocations from arenas with known
// compile-time capacities do not exceed that capacity, emitting errors if they do.
void il_pass_arena_capacity_check(const void* mod, ILFunction* func, DiagnosticReport* report);

// il_func_populate_types ensures all operand and result types in a function's
// instructions are correctly set, inferring them from context if necessary.
void il_func_populate_types(const void* mod, ILFunction* func);

#endif
