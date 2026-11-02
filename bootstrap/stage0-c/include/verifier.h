#ifndef VERIFIER_H
#define VERIFIER_H

#include <stdbool.h>
#include <stdint.h>
#include "il_cfg.h"

typedef enum {
    VERIFY_ERR_TYPE_MISMATCH,
    VERIFY_ERR_MISSING_BOUNDS_CHECK,
    VERIFY_ERR_UNHANDLED_OPTION,
    VERIFY_ERR_USE_AFTER_MOVE,
    VERIFY_ERR_DOUBLE_DROP,
    VERIFY_ERR_REFERENCE_ESCAPE,
    VERIFY_ERR_LEAK,
    VERIFY_ERR_UNDEFINED_SSA,
    VERIFY_ERR_INTERNAL
} VerifierErrorType;

typedef struct {
    VerifierErrorType type;
    char* func_name;
    const char* file_path;
    uint32_t block_id;
    uint32_t instr_index;
    uint32_t line;
    uint32_t col;
    const char* message;
} VerifierError;

typedef struct {
    bool is_safe;
    VerifierError* errors;
    uint32_t error_count;
    uint32_t error_capacity;
} VerificationResult;

void verify_result_free(VerificationResult* result);

VerificationResult verify_function(const ILModule* mod, const ILFunction* func);
VerificationResult verify_module(const ILModule* mod);

#endif
