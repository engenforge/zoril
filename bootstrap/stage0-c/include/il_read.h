#ifndef IL_READ_H
#define IL_READ_H

#include "il_type.h"
#include "il_cfg.h"

// il_read_type parses a type from a string.
// Returns a pointer to a new ILType on success, or NULL on failure.
// If end is not NULL, it is set to the first character not consumed.
const ILType* il_read_type(const char* src, const char** end);
ILInstruction* il_read_instr(const char* src, const char** end);
ILFunction* il_read_func(const char* src, const char** end);
ILModule* il_read_module(const char* src, const char** end);

#endif
