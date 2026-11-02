#include "surface_parser.h"
#include "surface_lexer.h"
#include "surface_lower.h"
#include "il_print.h"
#include "il_cfg.h"
#include "diagnostics.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "il_type.h"

#define RUN_TEST(test_func) \
    do { \
        if (test_func()) { \
            printf("[PASS] " #test_func "\n"); \
            tests_passed++; \
        } else { \
            printf("[FAIL] " #test_func "\n"); \
        } \
        tests_run++; \
    } while (0)

static int tests_passed = 0;
static int tests_run = 0;

static bool test_string_escapes(void) {
    const char* src = "fn test() { let s = \"Hello\\nWorld\\t!\\\\\\\"\\0\\x41\\r\\'\"; }";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_escapes.zil", report);
    
    bool ok = true;
    if (!mod) {
        printf("Failed to parse module. Errors:\n");
        for (uint32_t i = 0; i < report->count; i++) {
            printf("Error: %s\n", report->diagnostics[i].message);
        }
        ok = false;
    } else {
        if (mod->function_count == 1 && mod->functions[0]->body && mod->functions[0]->body->stmt_count > 0) {
            Statement* stmt = mod->functions[0]->body->statements[0];
            if (stmt->kind == STMT_LET && stmt->as.let.init->kind == EXPR_STRING) {
                const char* s = stmt->as.let.init->as.string_val.val;
                size_t len = stmt->as.let.init->as.string_val.len;
                // Expected: Hello\nWorld\t!\"\0A\r'
                // Len: 5 + 1 + 5 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 = 19
                if (len == 19 && 
                    s[0] == 'H' && 
                    s[5] == '\n' && 
                    s[11] == '\t' && 
                    s[13] == '\\' && 
                    s[14] == '"' && 
                    s[15] == '\0' && 
                    s[16] == 'A' &&
                    s[17] == '\r' &&
                    s[18] == '\'') {
                    ok = true; 
                } else {
                    printf("String escape failed: len=%zu, s[15]=%d, s[16]=%d, s[17]=%d, s[18]=%d\n", 
                           len, s[15], s[16], s[17], s[18]);
                    ok = false;
                }
            } else {
                printf("AST structure incorrect\n");
                ok = false;
            }
        } else {
            ok = false;
        }
        surface_mod_free(mod);
    }
    
    diag_report_destroy(report);
    return ok;
}

static bool test_hex_escapes_edge_cases(void) {
    // \x4 (single digit), \x (no digit), \x4G (hex then non-hex)
    const char* src = "fn test() { let s1 = \"\\x4\"; let s2 = \"\\x\"; let s3 = \"\\x4G\"; }";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_hex.zil", report);
    
    bool ok = true;
    if (!mod) {
        ok = false;
    } else {
        const FunctionDecl* f = mod->functions[0];
        // s1: "\x4" -> should be char 4
        const char* s1 = f->body->statements[0]->as.let.init->as.string_val.val;
        if (s1[0] != 4) ok = false;
        
        // s2: "\x" -> should be 'x' (fallback)
        const char* s2 = f->body->statements[1]->as.let.init->as.string_val.val;
        if (s2[0] != 'x') ok = false;

        // s3: "\x4G" -> should be char 4 followed by 'G'
        const char* s3 = f->body->statements[2]->as.let.init->as.string_val.val;
        if (s3[0] != 4 || s3[1] != 'G') ok = false;
        
        surface_mod_free(mod);
    }
    diag_report_destroy(report);
    return ok;
}

static bool test_raw_strings(void) {
    const char* src = "fn test() { let s = r\"C:\\path\\to\\nfile\"; }";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_raw.zil", report);
    
    bool ok = true;
    if (!mod) {
        ok = false;
    } else {
        const char* s = mod->functions[0]->body->statements[0]->as.let.init->as.string_val.val;
        if (strcmp(s, "C:\\path\\to\\nfile") != 0) ok = false;
        surface_mod_free(mod);
    }
    diag_report_destroy(report);
    return ok;
}

static bool test_line_continuation(void) {
    const char* src = "fn test() { let s = \"line1\\\nline2\"; }";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_cont.zil", report);
    
    bool ok = true;
    if (!mod) {
        ok = false;
    } else {
        const char* s = mod->functions[0]->body->statements[0]->as.let.init->as.string_val.val;
        if (strcmp(s, "line1line2") != 0) ok = false;
        surface_mod_free(mod);
    }
    diag_report_destroy(report);
    return ok;
}

static bool test_char_literal(void) {
    const char* src = "fn test() { let c: u8 = 'A'; let n = '\\n'; let x = '\\x42'; let q = '\\''; }";
    DiagnosticReport* report = diag_report_create();
    SurfaceModule* mod = surface_parse_module(src, "test_escapes_char.zil", report);
    
    bool ok = true;
    if (!mod) {
        printf("Failed to parse character literals. Errors:\n");
        for (uint32_t i = 0; i < report->count; i++) {
            printf("Error: %s\n", report->diagnostics[i].message);
        }
        ok = false;
    } else {
        if (mod->function_count == 1 && mod->functions[0]->body && mod->functions[0]->body->stmt_count == 4) {
            const Statement* s1 = mod->functions[0]->body->statements[0];
            const Statement* s2 = mod->functions[0]->body->statements[1];
            const Statement* s3 = mod->functions[0]->body->statements[2];
            const Statement* s4 = mod->functions[0]->body->statements[3];
            
            if (s1->as.let.init->kind != EXPR_INT || s1->as.let.init->as.int_val != 65) ok = false;
            if (s2->as.let.init->kind != EXPR_INT || s2->as.let.init->as.int_val != 10) ok = false;
            if (s3->as.let.init->kind != EXPR_INT || s3->as.let.init->as.int_val != 0x42) ok = false;
            if (s4->as.let.init->kind != EXPR_INT || s4->as.let.init->as.int_val != '\'') ok = false;
        } else {
            ok = false;
        }
        surface_mod_free(mod);
    }
    diag_report_destroy(report);
    return ok;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_string_escapes);
    RUN_TEST(test_hex_escapes_edge_cases);
    RUN_TEST(test_raw_strings);
    RUN_TEST(test_line_continuation);
    RUN_TEST(test_char_literal);
    printf("[%2d/%2d] String and Character Escapes\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return tests_passed == tests_run ? 0 : 1;
}
