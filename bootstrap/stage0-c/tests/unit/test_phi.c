#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test_harness.h"
#include "surface_parser.h"
#include "surface_lower.h"
#include "qbe_emit.h"
#include "il_type.h"
#include "il_instr.h"
#include "il_cfg.h"
#include "il_pass.h"
#include "il_pass.h"

int tests_run = 0;
int tests_passed = 0;

static bool test_aggregate_phi_lowering(void) {
    const char* src = 
        "struct Data { x: i64, y: i64, z: i64 }\n"
        "fn check(b: bool) -> Data {\n"
        "    let d = if b {\n"
        "        Data { x: 1, y: 2, z: 3 }\n"
        "    } else {\n"
        "        Data { x: 4, y: 5, z: 6 }\n"
        "    };\n"
        "    return d;\n"
        "}\n";


    DiagnosticReport report = {0};
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", &report);
    ASSERT(smod != NULL, "Failed to parse module");
    ASSERT(!report.has_errors, "Parsing had errors");

    ILModule* mod = surface_lower_module(smod, &report, false);
    ASSERT(mod != NULL, "Failed to lower module");
    ASSERT(!report.has_errors, "Lowering had errors");

    for (uint32_t i = 0; i < mod->function_count; i++) {
        il_func_populate_types(mod, mod->functions[i]);
    }

    FILE* tmp = tmpfile();
    ASSERT(tmp != NULL, "Failed to create temp file");
    qbe_emit_module(mod, tmp);
    
    long size = ftell(tmp);
    rewind(tmp);
    char* ssa = malloc((size_t)size + 1);
    ASSERT(fread(ssa, 1, (size_t)size, tmp) == (size_t)size, "Failed to read back SSA");
    ssa[size] = '\0';
    fclose(tmp);
    
    // QBE has no aggregate-typed phi. The two struct values must be merged through their
    // addresses (an `=l` pointer phi, or a phi_slot), never as an aggregate-typed phi.
    bool merged_by_address = strstr(ssa, "=l phi @b") != NULL || strstr(ssa, "phi_slot") != NULL;
    ASSERT(merged_by_address, "Aggregate Phi should be merged through addresses");
    bool aggregate_phi = false;
    for (char* line = ssa; line && *line; ) {
        char* end = strchr(line, '\n');
        if (end) *end = '\0';
        if (strstr(line, " phi ") && strstr(line, "=:")) aggregate_phi = true;
        line = end ? end + 1 : NULL;
    }
    ASSERT(!aggregate_phi, "Should not use an aggregate-typed QBE phi");

    free(ssa);
    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

static bool test_phi_interleaving_order(void) {
    ILModule* mod = il_mod_create();
    ILFunction* func = il_func_create_synthetic(1, "test_interleave", il_type_i32());
    il_mod_add_func(mod, func);
    
    ILBasicBlock* b1 = il_block_create(1); // entry
    ILBasicBlock* b2 = il_block_create(2); // pred
    ILBasicBlock* b3 = il_block_create(3); // join
    
    il_func_add_block(func, b1);
    func->entry_block = b1;
    il_func_add_block(func, b2);
    il_func_add_block(func, b3);
    
    il_block_add_instr(b1, il_build_jump(b3->id));
    il_block_add_instr(b2, il_build_jump(b3->id));
    
    uint32_t num_incoming = 35;
    ILPhiIncoming* incoming_large = calloc(num_incoming, sizeof(ILPhiIncoming));
    for(uint32_t i=0; i<num_incoming; i++) {
        incoming_large[i].block_id = b1->id;
        incoming_large[i].value_id = 10;
    }
    ILInstruction* phi_large = il_build_phi(incoming_large, num_incoming, il_type_i32());
    il_block_add_instr(b3, phi_large);
    
    ILPhiIncoming incoming_std[1];
    incoming_std[0].block_id = b1->id;
    incoming_std[0].value_id = 20;
    ILInstruction* phi_std = il_build_phi(incoming_std, 1, il_type_i32());
    il_block_add_instr(b3, phi_std);
    
    il_block_add_instr(b3, il_build_return((ILValue){ .id = phi_std->result_id, .type = il_type_i32() }));

    FILE* tmp = tmpfile();
    ASSERT(tmp != NULL, "Failed to create temp file");
    qbe_emit_module(mod, tmp);
    
    long size = ftell(tmp);
    rewind(tmp);
    char* ssa = malloc((size_t)size + 1);
    ASSERT(fread(ssa, 1, (size_t)size, tmp) == (size_t)size, "Failed to read back SSA");
    ssa[size] = '\0';
    fclose(tmp);
    
    char* pos_load = strstr(ssa, "load");
    char* pos_phi = strstr(ssa, " phi "); 
    
    ASSERT(pos_load != NULL, "Should have load for large Phi");
    ASSERT(pos_phi != NULL, "Should have QBE phi for standard Phi");
    
    if (pos_load < pos_phi) {
        fprintf(stderr, "[RED] Found 'load' before 'phi' in QBE output (Buggy interleaving)\n");
        free(ssa);
        free(incoming_large);
        il_mod_free(mod);
        return false;
    }

    free(ssa);
    free(incoming_large);
    il_mod_free(mod);
    return true;
}

static bool test_large_phi_load_suffix(void) {
    const char* src = 
        "enum Large { V0, V1, V2, V3, V4, V5, V6, V7, V8, V9, "
        "V10, V11, V12, V13, V14, V15, V16, V17, V18, V19, "
        "V20, V21, V22, V23, V24, V25, V26, V27, V28, V29, "
        "V30, V31, V32, V33, V34 }\n"
        "fn check(l: Large) -> i32 {\n"
        "    match l {\n"
        "        Large.V0 => 0, Large.V1 => 1, Large.V2 => 2, Large.V3 => 3, Large.V4 => 4, "
        "        Large.V5 => 5, Large.V6 => 6, Large.V7 => 7, Large.V8 => 8, Large.V9 => 9, "
        "        Large.V10 => 10, Large.V11 => 11, Large.V12 => 12, Large.V13 => 13, Large.V14 => 14, "
        "        Large.V15 => 15, Large.V16 => 16, Large.V17 => 17, Large.V18 => 18, Large.V19 => 19, "
        "        Large.V20 => 20, Large.V21 => 21, Large.V22 => 22, Large.V23 => 23, Large.V24 => 24, "
        "        Large.V25 => 25, Large.V26 => 26, Large.V27 => 27, Large.V28 => 28, Large.V29 => 29, "
        "        Large.V30 => 30, Large.V31 => 31, Large.V32 => 32, Large.V33 => 33, Large.V34 => 34, "
    "    }\n"
    "}\n";

    DiagnosticReport report = {0};
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", &report);
    ASSERT(smod != NULL, "Failed to parse module");
    ASSERT(!report.has_errors, "Parsing had errors");

    ILModule* mod = surface_lower_module(smod, &report, false);
    ASSERT(mod != NULL, "Failed to lower module");
    ASSERT(!report.has_errors, "Lowering had errors");

    for (uint32_t i = 0; i < mod->function_count; i++) {
        il_func_populate_types(mod, mod->functions[i]);
    }

    FILE* tmp = tmpfile();
    ASSERT(tmp != NULL, "Failed to create temp file");
    qbe_emit_module(mod, tmp);
    
    long size = ftell(tmp);
    rewind(tmp);
    char* ssa = malloc((size_t)size + 1);
    ASSERT(fread(ssa, 1, (size_t)size, tmp) == (size_t)size, "Failed to read back SSA");
    ssa[size] = '\0';
    fclose(tmp);
    
    ASSERT(strstr(ssa, "loadw %phi_slot") != NULL, "Should use loadw for large phi load");
    ASSERT(strstr(ssa, "=w load %phi_slot") == NULL, "Should not use suffixless load");

    free(ssa);
    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

static bool test_match_sret_phi_stores(void) {
    // Regression: match expression returning large struct (sret) via arm that calls
    // another sret function. The phi_slot store must use memcpy (not storel of the
    // sret pointer address) so the phi slot holds the actual aggregate data.
    const char* src =
        "struct Big { a: u64, b: u64, c: u64, d: u64 }\n"
        "fn make_big(x: u64) -> Big {\n"
        "    return Big { a: x, b: x + 1, c: x + 2, d: x + 3 };\n"
        "}\n"
        "fn pick(c: u8) -> Big {\n"
        "    return match c {\n"
        "        1 => make_big(10),\n"
        "        _ => make_big(20),\n"
        "    };\n"
        "}\n";

    DiagnosticReport report = {0};
    SurfaceModule* smod = surface_parse_module(src, "test.zrl", &report);
    ASSERT(smod != NULL, "Failed to parse module");
    ASSERT(!report.has_errors, "Parsing had errors");

    ILModule* mod = surface_lower_module(smod, &report, false);
    ASSERT(mod != NULL, "Failed to lower module");
    ASSERT(!report.has_errors, "Lowering had errors");

    for (uint32_t i = 0; i < mod->function_count; i++) {
        il_func_populate_types(mod, mod->functions[i]);
    }

    FILE* tmp = tmpfile();
    ASSERT(tmp != NULL, "Failed to create temp file");
    qbe_emit_module(mod, tmp);

    long size = ftell(tmp);
    rewind(tmp);
    char* ssa = malloc((size_t)size + 1);
    ASSERT(fread(ssa, 1, (size_t)size, tmp) == (size_t)size, "Failed to read back SSA");
    ssa[size] = '\0';
    fclose(tmp);

    // The phi_slot must be written via memcpy, never via storel of the sret pointer.
    // A store instruction writing TO phi_slot_* is the bug pattern.
    const char* hay = ssa;
    bool bad_store_found = false;
    while ((hay = strstr(hay, ", %phi_slot_")) != NULL) {
        // Walk back to find the opcode on this line
        const char* line_start = hay;
        while (line_start > ssa && line_start[-1] != '\n') line_start--;
        if (strncmp(line_start, "\tstore", 6) == 0) {
            bad_store_found = true;
            break;
        }
        hay++;
    }
    if (bad_store_found) {
        fprintf(stderr, "[BUG] storel to phi_slot found — sret ptr stored as value instead of memcpy:\n%s\n", ssa);
    }
    ASSERT(!bad_store_found, "phi_slot written via store (sret pointer) instead of memcpy");

    free(ssa);
    il_mod_free(mod);
    surface_mod_free(smod);
    return true;
}

int main(void) {
    ILContext ctx;
    il_ctx_init(&ctx);

    RUN_TEST(test_aggregate_phi_lowering);
    RUN_TEST(test_phi_interleaving_order);
    RUN_TEST(test_large_phi_load_suffix);
    RUN_TEST(test_match_sret_phi_stores);

    il_ctx_destroy(&ctx);
    return (tests_run == tests_passed) ? 0 : 1;
}
