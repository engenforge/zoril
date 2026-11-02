#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "../include/surface_lexer.h"
#include "../include/surface_ast.h"
#include "../include/surface_parser.h"
#include "../include/surface_lower.h"
#include "../include/il_read.h"
#include "../include/verifier.h"
#include "../include/il_cfg.h"
#include "il_type.h"

int tests_run = 0;
int tests_passed = 0;

/* Test that the lexer tracks line and column numbers on tokens. */
static bool test_lexer_tracks_locations(void) {
    const char* src = "fn foo() {\n    return 42;\n}";
    Lexer lex = lexer_create(src);

    /* fn → line 1, col 1 */
    Token t = lexer_next(&lex);
    ASSERT(t.kind == TOK_FN, "Expected TOK_FN");
    ASSERT(t.line == 1, "fn should be on line 1");
    ASSERT(t.col == 1, "fn should start at col 1");

    /* foo → line 1, col 4 */
    t = lexer_next(&lex);
    ASSERT(t.kind == TOK_IDENT, "Expected TOK_IDENT for foo");
    ASSERT(t.line == 1, "foo should be on line 1");
    ASSERT(t.col == 4, "foo should start at col 4");
    lexer_token_free(t);

    /* ( → line 1, col 7 */
    t = lexer_next(&lex);
    ASSERT(t.kind == TOK_LPAREN, "Expected TOK_LPAREN");
    ASSERT(t.line == 1, "( should be on line 1");
    ASSERT(t.col == 7, "( should be at col 7");

    /* ) → line 1, col 8 */
    t = lexer_next(&lex);
    ASSERT(t.kind == TOK_RPAREN, "Expected TOK_RPAREN");
    ASSERT(t.line == 1, ") should be on line 1");
    ASSERT(t.col == 8, ") should be at col 8");

    /* { → line 1, col 10 */
    t = lexer_next(&lex);
    ASSERT(t.kind == TOK_LBRACE, "Expected TOK_LBRACE");
    ASSERT(t.line == 1, "{ should be on line 1");
    ASSERT(t.col == 10, "{ should be at col 10");

    /* return → line 2, col 5 */
    t = lexer_next(&lex);
    ASSERT(t.kind == TOK_RETURN, "Expected TOK_RETURN");
    ASSERT(t.line == 2, "return should be on line 2");
    ASSERT(t.col == 5, "return should start at col 5");

    /* 42 → line 2, col 12 */
    t = lexer_next(&lex);
    ASSERT(t.kind == TOK_INT, "Expected TOK_INT for 42");
    ASSERT(t.line == 2, "42 should be on line 2");
    ASSERT(t.col == 12, "42 should start at col 12");

    /* } → line 3, col 1 */
    lexer_token_free(lexer_next(&lex));  /* semicolon */
    t = lexer_next(&lex);  /* } */
    ASSERT(t.kind == TOK_RBRACE, "Expected TOK_RBRACE");
    ASSERT(t.line == 3, "} should be on line 3");
    ASSERT(t.col == 1, "} should be at col 1");

    lexer_destroy(&lex);
    return true;
}

/* Test that parsed AST nodes carry source locations. */
static bool test_ast_has_locations(void) {
    const char* src =
        "fn foo() -> i32 {\n"
        "    return 42;\n"
        "}";
    SurfaceModule* mod = surface_parse_module(src, "test.zrl", NULL);
    if (!mod) return false;
    
    bool success = true;
    if (mod->function_count != 1) { success = false; goto cleanup; }

    FunctionDecl* fn = mod->functions[0];
    if (fn->line != 1) { success = false; goto cleanup; }

    if (fn->body->stmt_count != 1) { success = false; goto cleanup; }
    const Statement* stmt = fn->body->statements[0];
    if (stmt->kind != STMT_RETURN) { success = false; goto cleanup; }
    if (stmt->line != 2) { success = false; goto cleanup; }
    if (stmt->col != 5) { success = false; goto cleanup; }

cleanup:
    surface_mod_free(mod);
    return success;
}

static bool test_lowered_instr_has_location(void) {
    const char* src =
        "fn foo() -> i32 {\n"
        "    return 42;\n"
        "}";
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", NULL);
    if (!smod) return false;

    ILModule* mod = surface_lower_module(smod, NULL, false);
    if (!mod) { surface_mod_free(smod); return false; }

    bool success = true;
    if (mod->function_count == 0) { success = false; goto cleanup; }
    ILFunction* fn = mod->functions[0];
    if (fn->block_count == 0) { success = false; goto cleanup; }

    bool found_return = false;
    for (uint32_t b = 0; b < fn->block_count; b++) {
        ILBasicBlock* blk = fn->blocks[b];
        for (uint32_t i = 0; i < blk->instr_count; i++) {
            const ILInstruction* instr = blk->instructions[i];
            if (instr->opcode == IL_OP_RETURN) {
                if (instr->line != 2 || instr->col != 12) {
                    printf("Failed: expected 2:12, got %u:%u\n", instr->line, instr->col);
                    success = false; goto cleanup;
                }
                found_return = true;
            }
        }
    }
    if (!found_return) success = false;

cleanup:
    il_mod_free(mod);
    surface_mod_free(smod);
    return success;
}

static bool test_verifier_error_has_location(void) {
    /* Line 4 is the instruction with the type mismatch. */
    const char* il_src =
        "f1: i32 bad() {\n"
        "  @b0:\n"
        "    v1: i32 = const 1\n"
        "    v2: i64 = const 2\n"
        "    v3: i32 = add v1, v2\n"
        "    ret v3\n"
        "}\n";

    ILModule* mod = il_read_module(il_src, NULL);
    if (!mod) return false;

    bool success = true;
    VerificationResult res = verify_function(mod, mod->functions[0]);
    if (res.is_safe) { success = false; goto cleanup; }
    if (res.error_count == 0) { success = false; goto cleanup; }

    bool found_located_error = false;
    for (uint32_t i = 0; i < res.error_count; i++) {
        if (res.errors[i].line > 0) found_located_error = true;
    }
    if (!found_located_error) success = false;

cleanup:
    verify_result_free(&res);
    il_mod_free(mod);
    return success;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);
    RUN_TEST(test_lexer_tracks_locations);
    RUN_TEST(test_ast_has_locations);
    RUN_TEST(test_lowered_instr_has_location);
    RUN_TEST(test_verifier_error_has_location);

    printf("\n%d/%d tests passed.\n", tests_passed, tests_run);
    il_ctx_destroy(&ctx);
    return (tests_passed == tests_run) ? 0 : 1;
}
