#ifndef IL_PRINT_H
#define IL_PRINT_H

#include <stddef.h>
#include "il_type.h"
#include "il_instr.h"

#include "il_cfg.h"

#include <stdio.h>

void il_print_type(const ILModule* mod, const ILType* type, char* buffer, size_t max_len);
void il_print_type_def(const ILModule* mod, const ILTypeDef* def, char* buffer, size_t max_len);
void il_print_instr(const ILModule* mod, const ILInstruction* instr, char* buffer, size_t max_len);
void il_print_func(const ILModule* mod, const ILFunction* func, char* buffer, size_t max_len);
void il_print_module(const ILModule* mod, char* buffer, size_t max_len);

void il_func_print(const ILModule* mod, const ILFunction* func, FILE* out);
void il_mod_print(const ILModule* mod, FILE* out);

#endif
