#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "diagnostics.h"
#include "il_type.h"
#include "surface_parser.h"
#include "surface_ast.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_diag_lifecycle(void) {
    DiagnosticReport* report = diag_report_create();
    ASSERT(report != NULL, "Report creation failed");
    ASSERT(report->count == 0, "Initial count should be 0");
    ASSERT(report->has_errors == false, "Initial errors flag should be false");

    SourceLocation loc = { .file_path = "test.zrl", .line = 1, .col = 1 };
    diag_emit(report, DIAG_ERROR, loc, "Test error: %d", 42);
    ASSERT(report->count == 1, "Count should be 1 after emit");
    ASSERT(report->has_errors == true, "Errors flag should be true after error emit");
    ASSERT(strcmp(report->diagnostics[0].message, "Test error: 42") == 0, "Message mismatch");

    diag_report_destroy(report);
    return true;
}

static bool test_diag_render(void) {
    DiagnosticReport* report = diag_report_create();
    SourceLocation loc = { .file_path = "test.zrl", .line = 10, .col = 5, .source = "fn main() {", .offset = 0, .length = 2 };
    diag_emit(report, DIAG_WARNING, loc, "Sample warning");

    // Redirect stdout to a buffer or just check it doesn't crash
    printf("--- Terminal Render Output ---\n");
    diag_render_terminal(report);
    printf("--- JSON Render Output ---\n");
    diag_render_json(report);
    printf("--- End of Render Output ---\n");

    diag_report_destroy(report);
    return true;
}

static bool test_diag_line_offset_sync(void) {
    const char* src = 
        "fn main() {\n"     // Line 1
        "    let x = 1;\n"  // Line 2
        "    let y = 2;\n"  // Line 3
        "}\n";              // Line 4
    
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", report);
    ASSERT(mod != NULL, "Module parsing failed");
    
    FunctionDecl* fn = mod->functions[0];
    Statement* s2 = fn->body->statements[1]; // let y = 2;
    
    // The bug was that s2->source was src + offset, which caused double-offsetting.
    ASSERT(s2->source == src, "Source pointer must point to start of file");
    
    surface_mod_free(mod);
    diag_report_destroy(report);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_diag_lifecycle);
    RUN_TEST(test_diag_render);
    RUN_TEST(test_diag_line_offset_sync);
    printf("[%2d/%2d] Diagnostic manager and error reporting\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return tests_passed == tests_run ? 0 : 1;
}
