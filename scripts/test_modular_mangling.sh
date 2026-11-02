#!/bin/sh
# Test runner for modular compilation and Phase 2 mangling acceptance tests:
# 1. Negative test: two modules each declaring `fn init()` compile and link without a duplicate-symbol error.
# 2. Ambiguity regression test: modules `mod0` (fn `calc_x`) and `mod0_calc` (fn `x`) link cleanly,
#    each function is reachable and returns its own distinct value.
# 3. CLI --module / -m argument propagation to QBEEmitter.
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

. "$(dirname "$0")/env.sh"

ZILC_BIN="${ZILC_BIN:-build/zilc}"
BACKEND_BIN="${BACKEND_BIN:-qbe}"
ASSEMBLER_BIN="${ASSEMBLER_BIN:-as}"
LINKER_BIN="${LINKER_BIN:-ld}"
RT_HOST="build/runtime.o"

[ -x "$ZILC_BIN" ] || { echo "error: $ZILC_BIN not found or not executable"; exit 1; }
[ -f "$RT_HOST" ] || "$ASSEMBLER_BIN" -o "$RT_HOST" rt/runtime.s

WORK_DIR="build/tests/modular_mangling"
mkdir -p "$WORK_DIR"

echo "=== Modular Mangling Acceptance Tests ==="

# ── Test 1: Negative test (two modules declaring `fn init()`) ───────────────
echo "1. Negative test: duplicate symbol collision avoidance (init in mod_a and mod_b)..."
"$ZILC_BIN" tests/modular/negative_init/mod_a.zil "$WORK_DIR/mod_a.ssa"
"$ZILC_BIN" tests/modular/negative_init/mod_b.zil "$WORK_DIR/mod_b.ssa"
"$ZILC_BIN" tests/modular/negative_init/main.zil "$WORK_DIR/main_init.ssa"

"$BACKEND_BIN" -o "$WORK_DIR/mod_a.s" "$WORK_DIR/mod_a.ssa"
"$ASSEMBLER_BIN" -o "$WORK_DIR/mod_a.o" "$WORK_DIR/mod_a.s"

"$BACKEND_BIN" -o "$WORK_DIR/mod_b.s" "$WORK_DIR/mod_b.ssa"
"$ASSEMBLER_BIN" -o "$WORK_DIR/mod_b.o" "$WORK_DIR/mod_b.s"

"$BACKEND_BIN" -o "$WORK_DIR/main_init.s" "$WORK_DIR/main_init.ssa"
"$ASSEMBLER_BIN" -o "$WORK_DIR/main_init.o" "$WORK_DIR/main_init.s"

"$LINKER_BIN" -o "$WORK_DIR/test_init" "$WORK_DIR/mod_a.o" "$WORK_DIR/mod_b.o" "$WORK_DIR/main_init.o" "$RT_HOST"
"$WORK_DIR/test_init"

nm "$WORK_DIR/test_init" | grep -q "z5mod_a4initE" || { echo "FAIL: z5mod_a4initE symbol missing"; exit 1; }
nm "$WORK_DIR/test_init" | grep -q "z5mod_b4initE" || { echo "FAIL: z5mod_b4initE symbol missing"; exit 1; }
echo "  [PASS] mod_a::init and mod_b::init link without collision and run cleanly"

# ── Test 2: Ambiguity regression test (mod0::calc_x vs mod0_calc::x) ────────
echo "2. Ambiguity test: mod0::calc_x vs mod0_calc::x distinction..."
"$ZILC_BIN" tests/modular/ambiguity/mod0.zil "$WORK_DIR/mod0.ssa"
"$ZILC_BIN" tests/modular/ambiguity/mod0_calc.zil "$WORK_DIR/mod0_calc.ssa"
"$ZILC_BIN" tests/modular/ambiguity/main.zil "$WORK_DIR/main_ambig.ssa"

"$BACKEND_BIN" -o "$WORK_DIR/mod0.s" "$WORK_DIR/mod0.ssa"
"$ASSEMBLER_BIN" -o "$WORK_DIR/mod0.o" "$WORK_DIR/mod0.s"

"$BACKEND_BIN" -o "$WORK_DIR/mod0_calc.s" "$WORK_DIR/mod0_calc.ssa"
"$ASSEMBLER_BIN" -o "$WORK_DIR/mod0_calc.o" "$WORK_DIR/mod0_calc.s"

"$BACKEND_BIN" -o "$WORK_DIR/main_ambig.s" "$WORK_DIR/main_ambig.ssa"
"$ASSEMBLER_BIN" -o "$WORK_DIR/main_ambig.o" "$WORK_DIR/main_ambig.s"

"$LINKER_BIN" -o "$WORK_DIR/test_ambig" "$WORK_DIR/mod0.o" "$WORK_DIR/mod0_calc.o" "$WORK_DIR/main_ambig.o" "$RT_HOST"
"$WORK_DIR/test_ambig"

nm "$WORK_DIR/test_ambig" | grep -q "z4mod06calc_xE" || { echo "FAIL: z4mod06calc_xE symbol missing"; exit 1; }
nm "$WORK_DIR/test_ambig" | grep -q "z9mod0_calc1xE" || { echo "FAIL: z9mod0_calc1xE symbol missing"; exit 1; }
echo "  [PASS] mod0::calc_x and mod0_calc::x symbols are distinct and callable"

# ── Test 3: CLI --module / -m argument propagation ──────────────────────────
echo "3. CLI --module / -m flag tests..."
"$ZILC_BIN" -m cli_mod tools/zilc/test/02_no_doc_header.zil "$WORK_DIR/cli_mod.ssa"
grep -q "\$z7cli_mod7get_twoE" "$WORK_DIR/cli_mod.ssa" || { echo "FAIL: -m cli_mod mangling failed"; exit 1; }

"$ZILC_BIN" --module=cli_mod2 tools/zilc/test/02_no_doc_header.zil "$WORK_DIR/cli_mod2.ssa"
grep -q "\$z8cli_mod27get_twoE" "$WORK_DIR/cli_mod2.ssa" || { echo "FAIL: --module=cli_mod2 mangling failed"; exit 1; }
echo "  [PASS] -m and --module CLI flags propagate module prefix correctly"

echo "PASS: all modular mangling acceptance tests passed."
