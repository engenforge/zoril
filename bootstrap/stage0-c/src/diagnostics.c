#include "diagnostics.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

DiagnosticReport* diag_report_create(void) {
    DiagnosticReport* report = calloc(1, sizeof(DiagnosticReport));
    if (!report) return NULL;
    report->capacity = 8;
    report->diagnostics = calloc(report->capacity, sizeof(Diagnostic));
    if (!report->diagnostics) {
        free(report);
        return NULL;
    }
    report->source_buffer_capacity = 4;
    report->source_buffers = calloc(report->source_buffer_capacity, sizeof(SourceBuffer));
    if (!report->source_buffers) {
        free(report->diagnostics);
        free(report);
        return NULL;
    }
    return report;
}

void diag_report_destroy(DiagnosticReport* report) {
    if (!report) return;
    for (uint32_t i = 0; i < report->count; i++) {
        free(report->diagnostics[i].message);
    }
    for (uint32_t i = 0; i < report->source_buffer_count; i++) {
        free(report->source_buffers[i].path);
        free(report->source_buffers[i].buffer);
    }
    free(report->source_buffers);
    free(report->diagnostics);
    free(report);
}

const char* diag_get_source_for_path(const DiagnosticReport* report, const char* path) {
    if (!report || !path) return NULL;
    for (uint32_t i = 0; i < report->source_buffer_count; i++) {
        if (report->source_buffers[i].path && strcmp(report->source_buffers[i].path, path) == 0) {
            return report->source_buffers[i].buffer;
        }
    }
    return NULL;
}

uint32_t diag_calculate_offset(const char* source, uint32_t line, uint32_t col) {
    if (!source) return 0;
    uint32_t offset = 0;
    uint32_t current_line = 1;
    uint32_t current_col = 1;

    while (source[offset] != '\0') {
        if (current_line == line && current_col == col) {
            return offset;
        }
        if (source[offset] == '\n') {
            current_line++;
            current_col = 1;
        } else {
            current_col++;
        }
        offset++;
    }
    return offset;
}

void diag_add_source(DiagnosticReport* report, const char* path, char* source) {
    if (!report || !source) return;
    if (report->source_buffer_count >= report->source_buffer_capacity) {
        report->source_buffer_capacity *= 2;
        report->source_buffers = realloc(report->source_buffers, report->source_buffer_capacity * sizeof(SourceBuffer));
    }
    report->source_buffers[report->source_buffer_count].path = path ? strdup(path) : NULL;
    report->source_buffers[report->source_buffer_count].buffer = source;
    report->source_buffer_count++;
}

void diag_emit(DiagnosticReport* report, DiagnosticSeverity severity, SourceLocation loc, const char* fmt, ...) {
    if (!report) {
        va_list args;
        va_start(args, fmt);
        vprintf(fmt, args);
        va_end(args);
        printf("\n");
        return;
    }
    if (report->count >= report->capacity) {
        report->capacity = (report->capacity == 0) ? 8 : report->capacity * 2;
        report->diagnostics = realloc(report->diagnostics, report->capacity * sizeof(Diagnostic));
    }

    Diagnostic* diag = &report->diagnostics[report->count++];
    diag->severity = severity;
    diag->location = loc;

    va_list args;
    va_start(args, fmt);
    int size = 0;
    if (fmt) {
        size = vsnprintf(NULL, 0, fmt, args);
    }
    va_end(args);

    diag->message = malloc((size_t)size + 1);
    if (fmt) {
        va_start(args, fmt);
        vsnprintf(diag->message, (size_t)size + 1, fmt, args);
        va_end(args);
    } else {
        diag->message[0] = '\0';
    }

    if (severity >= DIAG_ERROR) {
        report->has_errors = true;
    }
}

void diag_report_print(const DiagnosticReport* report, FILE* stream) {
    (void)stream; // Terminal rendering always goes to stderr/stdout with colors for now
    diag_render_terminal(report);
}

static void print_highlighted_source(const SourceLocation* loc) {
    if (!loc->source) return;

    size_t source_len = strlen(loc->source);
    if (loc->offset >= source_len) return;

    // Find the start of the line
    uint32_t line_start = loc->offset;
    while (line_start > 0 && loc->source[line_start - 1] != '\n') {
        line_start--;
    }

    // Find the end of the line
    uint32_t line_end = loc->offset;
    while (line_end < source_len && loc->source[line_end] != '\n') {
        line_end++;
    }

    // Print line number
    fprintf(stderr, "%4u | ", loc->line);

    // Print the line
    for (uint32_t i = line_start; i < line_end; i++) {
        if (i >= loc->offset && i < loc->offset + loc->length) {
            // Highlight the token
            fprintf(stderr, "\033[1;31m%c\033[0m", loc->source[i]);
        } else {
            fprintf(stderr, "%c", loc->source[i]);
        }
    }
    fprintf(stderr, "\n");

    // Print the caret
    fprintf(stderr, "     | ");
    for (uint32_t i = line_start; i < loc->offset; i++) {
        fprintf(stderr, " ");
    }
    fprintf(stderr, "\033[1;31m^");
    for (uint32_t i = 1; i < loc->length; i++) {
        fprintf(stderr, "~");
    }
    fprintf(stderr, "\033[0m\n");
}

void diag_render_terminal(const DiagnosticReport* report) {
    for (uint32_t i = 0; i < report->count; i++) {
        const Diagnostic* diag = &report->diagnostics[i];
        
        const char* severity_str;
        const char* color;
        
        switch (diag->severity) {
            case DIAG_NOTE: severity_str = "note"; color = "\033[1;36m"; break;
            case DIAG_WARNING: severity_str = "warning"; color = "\033[1;33m"; break;
            case DIAG_ERROR: severity_str = "error"; color = "\033[1;31m"; break;
            case DIAG_FATAL: severity_str = "fatal error"; color = "\033[1;31m"; break;
            default: severity_str = "note"; color = "\033[1;36m"; break;
        }

        fprintf(stderr, "%s%s\033[0m: \033[1;37m%s\033[0m\n", color, severity_str, diag->message);
        fprintf(stderr, "  --> %s:%u:%u\n", diag->location.file_path ? diag->location.file_path : "<unknown>", diag->location.line, diag->location.col);
        
        print_highlighted_source(&diag->location);
        fprintf(stderr, "\n");
    }
}

void diag_render_json(const DiagnosticReport* report) {
    printf("[\n");
    for (uint32_t i = 0; i < report->count; i++) {
        const Diagnostic* diag = &report->diagnostics[i];
        printf("  {\n");
        printf("    \"severity\": \"%s\",\n", 
            diag->severity == DIAG_ERROR ? "error" : 
            diag->severity == DIAG_WARNING ? "warning" : "note");
        printf("    \"message\": \"%s\",\n", diag->message);
        printf("    \"location\": {\n");
        printf("      \"file\": \"%s\",\n", diag->location.file_path ? diag->location.file_path : "");
        printf("      \"line\": %u,\n", diag->location.line);
        printf("      \"column\": %u,\n", diag->location.col);
        printf("      \"offset\": %u,\n", diag->location.offset);
        printf("      \"length\": %u\n", diag->location.length);
        printf("    }\n");
        printf("  }%s\n", (i == report->count - 1) ? "" : ",");
    }
    printf("]\n");
}

void internal_compiler_error(const char* file, int line, const char* fmt, ...) {
    fprintf(stderr, "\033[1;31mInternal Compiler Error\033[0m at %s:%d: ", file, line);
    if (fmt) {
        va_list args;
        va_start(args, fmt);
        vfprintf(stderr, fmt, args);
        va_end(args);
    }
    fprintf(stderr, "\n");
    abort();
}
