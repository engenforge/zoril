#ifndef DIAGNOSTICS_H
#define DIAGNOSTICS_H

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

typedef enum {
    DIAG_NOTE,
    DIAG_WARNING,
    DIAG_ERROR,
    DIAG_FATAL
} DiagnosticSeverity;

typedef struct {
    const char* file_path;
    const char* source;
    uint32_t line;
    uint32_t col;
    uint32_t offset;
    uint32_t length;
} SourceLocation;

typedef struct {
    DiagnosticSeverity severity;
    SourceLocation location;
    char* message;
} Diagnostic;

typedef struct {
    char* path;
    char* buffer;
} SourceBuffer;

typedef struct {
    Diagnostic* diagnostics;
    uint32_t count;
    uint32_t capacity;
    bool has_errors;

    SourceBuffer* source_buffers;
    uint32_t source_buffer_count;
    uint32_t source_buffer_capacity;
} DiagnosticReport;

#include "compiler_compat.h"

DiagnosticReport* diag_report_create(void);
void diag_report_destroy(DiagnosticReport* report);

void diag_emit(DiagnosticReport* report, DiagnosticSeverity severity, SourceLocation loc, const char* fmt, ...) PRINTF_FORMAT(4, 5);
void diag_add_source(DiagnosticReport* report, const char* path, char* source);

const char* diag_get_source_for_path(const DiagnosticReport* report, const char* path);
uint32_t diag_calculate_offset(const char* source, uint32_t line, uint32_t col);

void diag_render_terminal(const DiagnosticReport* report);
void diag_render_json(const DiagnosticReport* report);
void diag_report_print(const DiagnosticReport* report, FILE* stream);

void internal_compiler_error(const char* file, int line, const char* fmt, ...) NORETURN PRINTF_FORMAT(3, 4);

#define ICE(...) internal_compiler_error(__FILE__, __LINE__, __VA_ARGS__)

#endif
