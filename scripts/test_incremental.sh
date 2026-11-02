#!/bin/sh
# Test runner for incremental compilation and translation-unit mode (-c / --compile-only)
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

. "$(dirname "$0")/env.sh"

BACKEND_BIN="${BACKEND_BIN:-qbe}"
ASSEMBLER_BIN="${ASSEMBLER_BIN:-as}"
LINKER_BIN="${LINKER_BIN:-ld}"

ZORIL_CC="${ZORIL_CC:-build/zoril}"
[ -x "$ZORIL_CC" ] || { echo "error: $ZORIL_CC not found or not executable"; exit 1; }
# An absolute ZORIL_CC is used as it is; a relative one is resolved against the repository, so a
# caller (the mutation harness) can hand over either.
case "$ZORIL_CC" in /*) ;; *) ZORIL_CC=$REPO/$ZORIL_CC ;; esac

# zbuild locates `build/zoril` beside itself unless told otherwise, so every call below passes the
# compiler under test explicitly: without it a scenario run under `ZORIL_CC=<mutant>` still builds with
# the good compiler, and the wiring would cover far less than it looks like.
ZBUILD_BIN="${ZBUILD_BIN:-build/zbuild}"
[ -x "$ZBUILD_BIN" ] || make build/zbuild
case "$ZBUILD_BIN" in /*) ;; *) ZBUILD_BIN=$REPO/$ZBUILD_BIN ;; esac

# The work directory is the caller's if it has one. A hard-coded path let a second run at the same
# moment read this one's files, or delete a subdirectory this one was mid-test on (test 48 removes the
# directory it works in), and the work-directory lock does not cover it. Callers that run this
# concurrently - the mutation harness, one mutant at a time - give each run its own `TR_WORK`.
WORK_DIR="${TR_WORK:-build/tests}/incremental"
# Absolute, like ZORIL_CC and ZBUILD_BIN above, so the steps that cd elsewhere can use it as it is.
case "$WORK_DIR" in /*) ;; *) WORK_DIR=$REPO/$WORK_DIR ;; esac
# Inside the repository: outside every root a module's identity is its bare file name, so the two
# programs of test 37 (each with a helper.zrl) share cache keys in their shared cache and the test
# cannot pass. Say so now rather than 37 tests in.
case "$WORK_DIR" in "$REPO"/*) ;; *) echo "error: TR_WORK must be inside the repository ($REPO); got ${TR_WORK}" >&2; exit 2 ;; esac
mkdir -p "$WORK_DIR"

echo "=== Incremental Compilation (-c / Translation-Unit Mode) Acceptance Tests ==="

# ── Test 1: Translation-unit mode produces definitions for target module only ──
echo "1. Testing TU mode: zoril -c mod0.zrl emits definitions for mod0 only, with imported functions as extern..."
"$ZORIL_CC" -c tests/incremental/mod0.zrl -o "$WORK_DIR/mod0.zil"

# Check module header
grep -q '^module mod0;' "$WORK_DIR/mod0.zil" || { echo "FAIL: missing 'module mod0;' header in mod0.zil"; exit 1; }

# Check function definition count (lines matching `f<id>: ... {`)
# mod0.zrl declares 2 functions: mod0_calc and mod0_main
fn_defs=$(grep -c '^[a-z0-9_]*f[0-9]\+:.*{' "$WORK_DIR/mod0.zil" || true)
if [ "$fn_defs" -ne 2 ]; then
    echo "FAIL: expected 2 function definitions in mod0.zil, got $fn_defs"
    exit 1
fi

# Check that helper_add and helper_sub from imported helper.zrl are present only as extern declarations
grep -q '^extern f[0-9]\+:.*helper_add' "$WORK_DIR/mod0.zil" || { echo "FAIL: helper_add not declared as extern in mod0.zil"; exit 1; }
grep -q '^extern f[0-9]\+:.*helper_sub' "$WORK_DIR/mod0.zil" || { echo "FAIL: helper_sub not declared as extern in mod0.zil"; exit 1; }

# Ensure no extern function has a body block
extern_with_body=$(grep -c '^extern f[0-9]\+:.*{' "$WORK_DIR/mod0.zil" || true)
if [ "$extern_with_body" -ne 0 ]; then
    echo "FAIL: found $extern_with_body extern function(s) with body block '{' in mod0.zil"
    exit 1
fi
echo "  [PASS] mod0.zil emits 2 definitions and imported functions as extern declarations without body"

# ── Test 2: Default output filename <module_name>.zil when -o omitted ─────────
echo "2. Testing default output path when -o is omitted with -c..."
(cd "$WORK_DIR" && rm -f mod0.zil && "$ZORIL_CC" -c "$REPO/tests/incremental/mod0.zrl")
[ -f "$WORK_DIR/mod0.zil" ] || { echo "FAIL: default mod0.zil not generated when -o omitted"; exit 1; }
grep -q '^module mod0;' "$WORK_DIR/mod0.zil" || { echo "FAIL: generated mod0.zil invalid"; exit 1; }
echo "  [PASS] default output filename <module_name>.zil created successfully"

# ── Test 3: Unresolvable import produces located diagnostic and fails ──────────
echo "3. Testing error test: unresolvable import produces located diagnostic..."
set +e
"$ZORIL_CC" -c tests/incremental/error_unresolvable_import.zrl -o "$WORK_DIR/bad.zil" 2> "$WORK_DIR/import_err.log"
ERR_CODE=$?
set -e

if [ "$ERR_CODE" -eq 0 ]; then
    echo "FAIL: expected zoril -c to fail on unresolvable import, but exited 0"
    exit 1
fi

# Diagnostic must be located (<file>:<line>:<col>: error: ...)
grep -E 'tests/incremental/error_unresolvable_import\.zrl:[0-9]+:[0-9]+: error: could not find imported file: non_existent_module_xyz123\.zrl' "$WORK_DIR/import_err.log" >/dev/null || {
    echo "FAIL: located diagnostic missing from compiler output:"
    cat "$WORK_DIR/import_err.log"
    exit 1
}
echo "  [PASS] unresolvable import failed with located diagnostic: $(grep -E 'tests/incremental/error_unresolvable_import\.zrl:[0-9]+:[0-9]+: error:' "$WORK_DIR/import_err.log")"

# ── Test 4: Whole-program output unchanged for corpus ─────────────────────────
echo "4. Testing whole-program .zil (without -c) against checked-in corpus hashes..."
# Golden: corpus/zrl_whole_program_zil.sha256. Regenerate with UPDATE_GOLDEN=1 in a dedicated
# commit whenever whole-program emission changes on purpose (e.g. an ABI/mangling flag day).
CORPUS_OUT="$WORK_DIR/corpus_zil"
rm -rf "$CORPUS_OUT"
mkdir -p "$CORPUS_OUT"
for src in corpus/zrl/*.zrl; do
    base=$(basename "$src" .zrl)
    grep -q '^// @skip:' "$src" && continue
    "$ZORIL_CC" -I stdlib=stdlib --emit-zil -o "$CORPUS_OUT/$base.zil" "$src" >/dev/null 2>&1 || {
        echo "FAIL: corpus file $src no longer compiles whole-program"
        exit 1
    }
done
(cd "$CORPUS_OUT" && sha256_of ./*.zil | sed 's| \./| |') > "$WORK_DIR/corpus_zil.sha256"
if [ "${UPDATE_GOLDEN:-0}" = "1" ]; then
    cp "$WORK_DIR/corpus_zil.sha256" corpus/zrl_whole_program_zil.sha256
    echo "  [UPDATED] corpus/zrl_whole_program_zil.sha256"
fi
compared=$(wc -l < corpus/zrl_whole_program_zil.sha256)
if [ "$compared" -eq 0 ]; then
    echo "FAIL: corpus golden is empty; nothing was compared"
    exit 1
fi
if ! (cd "$CORPUS_OUT" && sha256_check "$REPO/corpus/zrl_whole_program_zil.sha256" >"$WORK_DIR/corpus_cmp.log" 2>&1); then
    echo "FAIL: whole-program output changed for:"
    grep -v ': OK$' "$WORK_DIR/corpus_cmp.log" | head -n 20
    exit 1
fi
echo "  [PASS] whole-program output identical to golden across $compared corpus files"

# ── Test 5: Two-module linking and execution ──────────────────────────────────
echo "5. Testing two-module linking under host ld..."
ZILC_BIN="${ZILC_BIN:-build/zilc}"
case "$ZILC_BIN" in /*) ZILC_CC=$ZILC_BIN ;; *) ZILC_CC=$REPO/$ZILC_BIN ;; esac

"$ZORIL_CC" -c tests/incremental/helper.zrl -o "$WORK_DIR/helper.zil"
"$ZORIL_CC" -c tests/incremental/two_module_main.zrl -o "$WORK_DIR/two_module_main.zil"

# Verify ABI and mangled module qualification in emitted ZIL (a plain function takes no __env)
grep -q '^extern f[0-9]\+: i64 tests::incremental::helper::helper_add(a: i64, b: i64)' "$WORK_DIR/two_module_main.zil" || {
    echo "FAIL: expected tests::incremental::helper::helper_add with only its own parameters in two_module_main.zil:"
    grep 'helper_add' "$WORK_DIR/two_module_main.zil"
    exit 1
}

"$ZILC_BIN" "$WORK_DIR/helper.zil" -o "$WORK_DIR/helper.ssa"
"$ZILC_BIN" "$WORK_DIR/two_module_main.zil" -o "$WORK_DIR/two_module_main.ssa"

# Verify symbol mangling in QBE SSA
grep -q 'export function l \$z5tests11incremental6helper10helper_addE(' "$WORK_DIR/helper.ssa" || {
    echo "FAIL: helper.ssa did not export \$z5tests11incremental6helper10helper_addE:"
    cat "$WORK_DIR/helper.ssa"
    exit 1
}
grep -q 'call \$z5tests11incremental6helper10helper_addE(' "$WORK_DIR/two_module_main.ssa" || {
    echo "FAIL: two_module_main.ssa did not call \$z5tests11incremental6helper10helper_addE:"
    cat "$WORK_DIR/two_module_main.ssa"
    exit 1
}

"$BACKEND_BIN" -o "$WORK_DIR/helper.s" "$WORK_DIR/helper.ssa"
"$BACKEND_BIN" -o "$WORK_DIR/two_module_main.s" "$WORK_DIR/two_module_main.ssa"
"$ASSEMBLER_BIN" "$WORK_DIR/helper.s" -o "$WORK_DIR/helper.o"
"$ASSEMBLER_BIN" "$WORK_DIR/two_module_main.s" -o "$WORK_DIR/two_module_main.o"

# Link with host ld
"$LINKER_BIN" -o "$WORK_DIR/two_mod_ld" build/runtime.o "$WORK_DIR/two_module_main.o" "$WORK_DIR/helper.o"
"$WORK_DIR/two_mod_ld"
LD_EXIT=$?
if [ "$LD_EXIT" -ne 0 ]; then
    echo "FAIL: two-module binary linked with ld exited with $LD_EXIT, expected 0"
    exit 1
fi
echo "  [PASS] two-module program exits 0"

# ── Test 6: Closure-crossing test: whole-program parity across module boundary ──
echo "6. Testing closure-crossing across module boundaries vs whole-program..."
# 1) Whole-program compilation
"$ZORIL_CC" tests/incremental/closure_main.zrl -o "$WORK_DIR/closure_whole.zil"
"$ZILC_BIN" "$WORK_DIR/closure_whole.zil" -o "$WORK_DIR/closure_whole.ssa"
"$BACKEND_BIN" -o "$WORK_DIR/closure_whole.s" "$WORK_DIR/closure_whole.ssa"
"$ASSEMBLER_BIN" "$WORK_DIR/closure_whole.s" -o "$WORK_DIR/closure_whole.o"
"$LINKER_BIN" -o "$WORK_DIR/closure_whole_bin" build/runtime.o "$WORK_DIR/closure_whole.o"
"$WORK_DIR/closure_whole_bin"
WP_EXIT=$?

# 2) Modular compilation (-c)
"$ZORIL_CC" -c tests/incremental/closure_lib.zrl -o "$WORK_DIR/closure_lib.zil"
"$ZORIL_CC" -c tests/incremental/closure_main.zrl -o "$WORK_DIR/closure_main.zil"
"$ZILC_BIN" "$WORK_DIR/closure_lib.zil" -o "$WORK_DIR/closure_lib.ssa"
"$ZILC_BIN" "$WORK_DIR/closure_main.zil" -o "$WORK_DIR/closure_main.ssa"
"$BACKEND_BIN" -o "$WORK_DIR/closure_lib.s" "$WORK_DIR/closure_lib.ssa"
"$BACKEND_BIN" -o "$WORK_DIR/closure_main.s" "$WORK_DIR/closure_main.ssa"
"$ASSEMBLER_BIN" "$WORK_DIR/closure_lib.s" -o "$WORK_DIR/closure_lib.o"
"$ASSEMBLER_BIN" "$WORK_DIR/closure_main.s" -o "$WORK_DIR/closure_main.o"

# Link with ld
"$LINKER_BIN" -o "$WORK_DIR/closure_mod_ld" build/runtime.o "$WORK_DIR/closure_main.o" "$WORK_DIR/closure_lib.o"
"$WORK_DIR/closure_mod_ld"
MOD_LD_EXIT=$?

if [ "$WP_EXIT" -ne 0 ] || [ "$MOD_LD_EXIT" -ne "$WP_EXIT" ]; then
    echo "FAIL: closure crossing exit mismatch: WP=$WP_EXIT, MOD_LD=$MOD_LD_EXIT"
    exit 1
fi
echo "  [PASS] closure-crossing test produces same result ($WP_EXIT) whole-program and modular"

# ── Test 7: C FFI test: extern fn preserves C ABI, no __env, requires unsafe ───
echo "7. Testing C FFI: extern calls require unsafe, pass no __env, emit unmangled..."
cat << 'EOF' > "$WORK_DIR/c_ffi_lib.s"
.globl c_add
.type c_add, @function
c_add:
    movl %edi, %eax
    addl %esi, %eax
    ret
EOF
"$ASSEMBLER_BIN" "$WORK_DIR/c_ffi_lib.s" -o "$WORK_DIR/c_ffi_lib.o"
"$ZORIL_CC" -c tests/incremental/c_ffi_main.zrl -o "$WORK_DIR/c_ffi_main.zil"

# Verify in ZIL: no __env, no module qualification
grep -q '^extern f[0-9]\+: i32 c_add(a: i32, b: i32)' "$WORK_DIR/c_ffi_main.zil" || {
    echo "FAIL: c_add has unexpected signature in c_ffi_main.zil:"
    grep 'c_add' "$WORK_DIR/c_ffi_main.zil"
    exit 1
}

"$ZILC_BIN" "$WORK_DIR/c_ffi_main.zil" -o "$WORK_DIR/c_ffi_main.ssa"

# Verify in SSA: unmangled $c_add call with exactly 2 args (w, w) and no env
grep -q 'call \$c_add(w %v[0-9]\+, w %v[0-9]\+)' "$WORK_DIR/c_ffi_main.ssa" || {
    echo "FAIL: expected call \$c_add with 2 args without env in c_ffi_main.ssa:"
    cat "$WORK_DIR/c_ffi_main.ssa"
    exit 1
}

"$BACKEND_BIN" -o "$WORK_DIR/c_ffi_main.s" "$WORK_DIR/c_ffi_main.ssa"
"$ASSEMBLER_BIN" "$WORK_DIR/c_ffi_main.s" -o "$WORK_DIR/c_ffi_main.o"

# Link with ld
"$LINKER_BIN" -o "$WORK_DIR/c_ffi_ld" build/runtime.o "$WORK_DIR/c_ffi_main.o" "$WORK_DIR/c_ffi_lib.o"
"$WORK_DIR/c_ffi_ld"
CFFI_LD_EXIT=$?
if [ "$CFFI_LD_EXIT" -ne 0 ]; then
    echo "FAIL: c_ffi binary linked with ld exited with $CFFI_LD_EXIT, expected 0"
    exit 1
fi

# Verify unsafe requirement error test
set +e
"$ZORIL_CC" -c tests/incremental/c_ffi_unsafe_err.zrl -o "$WORK_DIR/c_ffi_bad.zil" 2> "$WORK_DIR/c_ffi_err.log"
UNSAFE_ERR=$?
set -e

if [ "$UNSAFE_ERR" -eq 0 ]; then
    echo "FAIL: expected c_ffi_unsafe_err.zrl to fail without unsafe block, but exited 0"
    exit 1
fi
grep -q 'error: call to extern function requires unsafe block' "$WORK_DIR/c_ffi_err.log" || {
    echo "FAIL: expected 'call to extern function requires unsafe block' in error log:"
    cat "$WORK_DIR/c_ffi_err.log"
    exit 1
}
echo "  [PASS] C FFI calls pass C ABI without __env, emit unmangled, link under ld, and enforce unsafe"

# ── Test 8: TU-local generic instantiation deduplication across modules ───────
echo "8. Testing generic specialization placement: duplicate instantiations link cleanly..."
"$ZORIL_CC" -c tests/incremental/dup_mod_a.zrl -I tests/incremental -o "$WORK_DIR/dup_mod_a.zil"
"$ZORIL_CC" -c tests/incremental/dup_mod_b.zrl -I tests/incremental -o "$WORK_DIR/dup_mod_b.zil"
"$ZORIL_CC" -c tests/incremental/dup_main.zrl -I tests/incremental -o "$WORK_DIR/dup_main.zil"

# Verify in ZIL: identity_Ti64 is emitted as local in both modules
grep -q '^local f[0-9]\+: i64 [a-z_:0-9]*identity_Ti64' "$WORK_DIR/dup_mod_a.zil" || {
    echo "FAIL: expected local identity_Ti64 in dup_mod_a.zil:"
    cat "$WORK_DIR/dup_mod_a.zil"
    exit 1
}
grep -q '^local f[0-9]\+: i64 [a-z_:0-9]*identity_Ti64' "$WORK_DIR/dup_mod_b.zil" || {
    echo "FAIL: expected local identity_Ti64 in dup_mod_b.zil:"
    cat "$WORK_DIR/dup_mod_b.zil"
    exit 1
}

"$ZILC_BIN" "$WORK_DIR/dup_mod_a.zil" -o "$WORK_DIR/dup_mod_a.ssa"
"$ZILC_BIN" "$WORK_DIR/dup_mod_b.zil" -o "$WORK_DIR/dup_mod_b.ssa"
"$ZILC_BIN" "$WORK_DIR/dup_main.zil" -o "$WORK_DIR/dup_main.ssa"

# Verify in SSA: unexported function in both modules
grep -q '^function l \$z[0-9a-zA-Z_]*identity_Ti64E' "$WORK_DIR/dup_mod_a.ssa" || {
    echo "FAIL: expected unexported function for identity_Ti64 in dup_mod_a.ssa:"
    cat "$WORK_DIR/dup_mod_a.ssa"
    exit 1
}
grep -q '^function l \$z[0-9a-zA-Z_]*identity_Ti64E' "$WORK_DIR/dup_mod_b.ssa" || {
    echo "FAIL: expected unexported function for identity_Ti64 in dup_mod_b.ssa:"
    cat "$WORK_DIR/dup_mod_b.ssa"
    exit 1
}

"$BACKEND_BIN" -o "$WORK_DIR/dup_mod_a.s" "$WORK_DIR/dup_mod_a.ssa"
"$BACKEND_BIN" -o "$WORK_DIR/dup_mod_b.s" "$WORK_DIR/dup_mod_b.ssa"
"$BACKEND_BIN" -o "$WORK_DIR/dup_main.s" "$WORK_DIR/dup_main.ssa"

"$ASSEMBLER_BIN" "$WORK_DIR/dup_mod_a.s" -o "$WORK_DIR/dup_mod_a.o"
"$ASSEMBLER_BIN" "$WORK_DIR/dup_mod_b.s" -o "$WORK_DIR/dup_mod_b.o"
"$ASSEMBLER_BIN" "$WORK_DIR/dup_main.s" -o "$WORK_DIR/dup_main.o"

# Verify in ELF objects: identity_Ti64 has LOCAL binding
readelf -W -s "$WORK_DIR/dup_mod_a.o" | grep -E 'LOCAL.*identity_Ti64' >/dev/null || {
    echo "FAIL: expected LOCAL binding for identity_Ti64 in dup_mod_a.o:"
    readelf -W -s "$WORK_DIR/dup_mod_a.o"
    exit 1
}
readelf -W -s "$WORK_DIR/dup_mod_b.o" | grep -E 'LOCAL.*identity_Ti64' >/dev/null || {
    echo "FAIL: expected LOCAL binding for identity_Ti64 in dup_mod_b.o:"
    readelf -W -s "$WORK_DIR/dup_mod_b.o"
    exit 1
}

# Link with ld
"$LINKER_BIN" -o "$WORK_DIR/dup_bin_ld" build/runtime.o "$WORK_DIR/dup_main.o" "$WORK_DIR/dup_mod_a.o" "$WORK_DIR/dup_mod_b.o"
"$WORK_DIR/dup_bin_ld"
DUP_LD_EXIT=$?
if [ "$DUP_LD_EXIT" -ne 0 ]; then
    echo "FAIL: dup_bin linked with ld exited with $DUP_LD_EXIT, expected 0"
    exit 1
fi

echo "  [PASS] duplicate generic specializations carry LOCAL binding and link without collision"

# ── Test 9: Generic in module A, instantiated in module B over type in module C ─
echo "9. Testing cross-module generic instantiation: fn in A, instantiated in B, over struct in C..."
"$ZORIL_CC" -c tests/incremental/generic_box_lib.zrl -I tests/incremental -o "$WORK_DIR/generic_box_lib.zil"
"$ZORIL_CC" -c tests/incremental/point_type_lib.zrl -I tests/incremental -o "$WORK_DIR/point_type_lib.zil"
"$ZORIL_CC" -c tests/incremental/cross_inst_main.zrl -I tests/incremental -o "$WORK_DIR/cross_inst_main.zil"

# Verify in ZIL: unwrap_box_TN5Point is emitted as local specialization in cross_inst_main
grep -q '^local f[0-9]\+:.*unwrap_box_TN5Point' "$WORK_DIR/cross_inst_main.zil" || {
    echo "FAIL: expected local unwrap_box_TN5Point in cross_inst_main.zil:"
    cat "$WORK_DIR/cross_inst_main.zil"
    exit 1
}

"$ZILC_BIN" "$WORK_DIR/generic_box_lib.zil" -o "$WORK_DIR/generic_box_lib.ssa"
"$ZILC_BIN" "$WORK_DIR/point_type_lib.zil" -o "$WORK_DIR/point_type_lib.ssa"
"$ZILC_BIN" "$WORK_DIR/cross_inst_main.zil" -o "$WORK_DIR/cross_inst_main.ssa"

"$BACKEND_BIN" -o "$WORK_DIR/generic_box_lib.s" "$WORK_DIR/generic_box_lib.ssa"
"$BACKEND_BIN" -o "$WORK_DIR/point_type_lib.s" "$WORK_DIR/point_type_lib.ssa"
"$BACKEND_BIN" -o "$WORK_DIR/cross_inst_main.s" "$WORK_DIR/cross_inst_main.ssa"

"$ASSEMBLER_BIN" "$WORK_DIR/generic_box_lib.s" -o "$WORK_DIR/generic_box_lib.o"
"$ASSEMBLER_BIN" "$WORK_DIR/point_type_lib.s" -o "$WORK_DIR/point_type_lib.o"
"$ASSEMBLER_BIN" "$WORK_DIR/cross_inst_main.s" -o "$WORK_DIR/cross_inst_main.o"

# Link with ld
"$LINKER_BIN" -o "$WORK_DIR/cross_bin_ld" build/runtime.o "$WORK_DIR/cross_inst_main.o" "$WORK_DIR/generic_box_lib.o" "$WORK_DIR/point_type_lib.o"
"$WORK_DIR/cross_bin_ld"
CROSS_LD_EXIT=$?
if [ "$CROSS_LD_EXIT" -ne 0 ]; then
    echo "FAIL: cross_bin linked with ld exited with $CROSS_LD_EXIT, expected 0"
    exit 1
fi

echo "  [PASS] generic in A over type in C instantiated in B executes correctly"

# ── Test 10: Module visibility: private functions are emitted local (t), pub functions global (T) ──
echo "10. Testing module linkage: nm shows private functions as 't' (local) and pub as 'T' (global)..."
"$ZORIL_CC" -c tests/incremental/visibility_mod.zrl -o "$WORK_DIR/visibility_mod.zil"
"$ZILC_BIN" "$WORK_DIR/visibility_mod.zil" -o "$WORK_DIR/visibility_mod.ssa"
"$BACKEND_BIN" -o "$WORK_DIR/visibility_mod.s" "$WORK_DIR/visibility_mod.ssa"
"$ASSEMBLER_BIN" "$WORK_DIR/visibility_mod.s" -o "$WORK_DIR/visibility_mod.o"

nm "$WORK_DIR/visibility_mod.o" > "$WORK_DIR/visibility_nm.txt"

grep -q ' t .*private_helper' "$WORK_DIR/visibility_nm.txt" || {
    echo "FAIL: expected private_helper to have 't' (local) symbol type in nm output:"
    cat "$WORK_DIR/visibility_nm.txt"
    exit 1
}

grep -q ' T .*public_entry' "$WORK_DIR/visibility_nm.txt" || {
    echo "FAIL: expected public_entry to have 'T' (global) symbol type in nm output:"
    cat "$WORK_DIR/visibility_nm.txt"
    exit 1
}

if grep -q ' T .*private_helper' "$WORK_DIR/visibility_nm.txt"; then
    echo "FAIL: private_helper must never be exported as 'T' (global):"
    cat "$WORK_DIR/visibility_nm.txt"
    exit 1
fi
echo "  [PASS] private function is local ('t') and public function is global ('T') in object file"

# ── Test 11: --emit-interface determinism across 10 consecutive runs ──────────
echo "11. Testing --emit-interface determinism: 10 consecutive runs produce byte-identical .zri..."
"$ZORIL_CC" --emit-interface tests/incremental/zri_math.zrl -o "$WORK_DIR/zri_run_0.zri"
for i in $(seq 1 10); do
    "$ZORIL_CC" --emit-interface tests/incremental/zri_math.zrl -o "$WORK_DIR/zri_run_$i.zri"
    cmp "$WORK_DIR/zri_run_0.zri" "$WORK_DIR/zri_run_$i.zri" || {
        echo "FAIL: run $i produced differing .zri output"
        exit 1
    }
done
echo "  [PASS] 10 consecutive runs produced byte-identical .zri output"

# ── Test 12: Early-cutoff property tests (both directions asserted) ────────────
echo "12. Testing early-cutoff property: private edits preserve .zri, public changes alter it..."
# The .zri records its source path, so every variant is emitted from the same path.
mkdir -p "$WORK_DIR/prop_src"
cat << 'EOF' > "$WORK_DIR/prop_src/m.zrl"
// Initial comment
fn private_a() -> i64 { return 1; }
fn private_b() -> i64 { return 2; }
pub struct Point { pub x: i64, pub y: i64, }
pub enum Status { Ok, Err(i32), }
pub fn compute(p: &Point) -> i64 { return p.x + p.y + private_a(); }
EOF
"$ZORIL_CC" --emit-interface "$WORK_DIR/prop_src/m.zrl" -o "$WORK_DIR/prop_base.zri"

# Edit non-pub function body -> byte-identical
cat << 'EOF' > "$WORK_DIR/prop_src/m.zrl"
// Initial comment
fn private_a() -> i64 { return 999999; }
fn private_b() -> i64 { return 2; }
pub struct Point { pub x: i64, pub y: i64, }
pub enum Status { Ok, Err(i32), }
pub fn compute(p: &Point) -> i64 { return p.x + p.y + private_a(); }
EOF
"$ZORIL_CC" --emit-interface "$WORK_DIR/prop_src/m.zrl" -o "$WORK_DIR/prop_edit_priv.zri"
cmp "$WORK_DIR/prop_base.zri" "$WORK_DIR/prop_edit_priv.zri" || {
    echo "FAIL: editing non-pub function body changed .zri"
    exit 1
}

# Reorder private declarations -> byte-identical
cat << 'EOF' > "$WORK_DIR/prop_src/m.zrl"
// Initial comment
fn private_b() -> i64 { return 2; }
fn private_a() -> i64 { return 1; }
pub struct Point { pub x: i64, pub y: i64, }
pub enum Status { Ok, Err(i32), }
pub fn compute(p: &Point) -> i64 { return p.x + p.y + private_a(); }
EOF
"$ZORIL_CC" --emit-interface "$WORK_DIR/prop_src/m.zrl" -o "$WORK_DIR/prop_reorder_priv.zri"
cmp "$WORK_DIR/prop_base.zri" "$WORK_DIR/prop_reorder_priv.zri" || {
    echo "FAIL: reordering private declarations changed .zri"
    exit 1
}

# Change comments -> byte-identical
cat << 'EOF' > "$WORK_DIR/prop_src/m.zrl"
// Modified top comment
/* Multi-line comment block */
fn private_a() -> i64 { /* comment inside */ return 1; }
fn private_b() -> i64 { return 2; }
// Comment before struct
pub struct Point {
    // Comment before field
    pub x: i64,
    pub y: i64,
}
// Comment before enum
pub enum Status { Ok, Err(i32), }
// Comment before fn
pub fn compute(p: &Point) -> i64 { return p.x + p.y + private_a(); }
EOF
"$ZORIL_CC" --emit-interface "$WORK_DIR/prop_src/m.zrl" -o "$WORK_DIR/prop_comments.zri"
cmp "$WORK_DIR/prop_base.zri" "$WORK_DIR/prop_comments.zri" || {
    echo "FAIL: changing comments changed .zri"
    exit 1
}

# Change public signature -> MUST change .zri
cat << 'EOF' > "$WORK_DIR/prop_src/m.zrl"
fn private_a() -> i64 { return 1; }
fn private_b() -> i64 { return 2; }
pub struct Point { pub x: i64, pub y: i64, }
pub enum Status { Ok, Err(i32), }
pub fn compute(p: &Point, extra: i64) -> i64 { return p.x + p.y + extra; }
EOF
"$ZORIL_CC" --emit-interface "$WORK_DIR/prop_src/m.zrl" -o "$WORK_DIR/prop_change_sig.zri"
if cmp -s "$WORK_DIR/prop_base.zri" "$WORK_DIR/prop_change_sig.zri"; then
    echo "FAIL: changing public signature did not change .zri"
    exit 1
fi

# Change field type -> MUST change .zri
cat << 'EOF' > "$WORK_DIR/prop_src/m.zrl"
fn private_a() -> i64 { return 1; }
fn private_b() -> i64 { return 2; }
pub struct Point { pub x: f64, pub y: i64, }
pub enum Status { Ok, Err(i32), }
pub fn compute(p: &Point) -> i64 { return 0; }
EOF
"$ZORIL_CC" --emit-interface "$WORK_DIR/prop_src/m.zrl" -o "$WORK_DIR/prop_change_field.zri"
if cmp -s "$WORK_DIR/prop_base.zri" "$WORK_DIR/prop_change_field.zri"; then
    echo "FAIL: changing field type did not change .zri"
    exit 1
fi

# Change enum variant -> MUST change .zri
cat << 'EOF' > "$WORK_DIR/prop_src/m.zrl"
fn private_a() -> i64 { return 1; }
fn private_b() -> i64 { return 2; }
pub struct Point { pub x: i64, pub y: i64, }
pub enum Status { Ok, Err(i32), ExtraVariant, }
pub fn compute(p: &Point) -> i64 { return 0; }
EOF
"$ZORIL_CC" --emit-interface "$WORK_DIR/prop_src/m.zrl" -o "$WORK_DIR/prop_change_enum.zri"
if cmp -s "$WORK_DIR/prop_base.zri" "$WORK_DIR/prop_change_enum.zri"; then
    echo "FAIL: changing enum variant did not change .zri"
    exit 1
fi
echo "  [PASS] private edits leave .zri byte-identical; signature/field/enum changes alter .zri"

# ── Test 13: Module consuming only .zri and generic instantiation through .zri ─
echo "13. Testing module consuming only .zri and generic instantiation without source access..."
mkdir -p "$WORK_DIR/iface_only"
"$ZORIL_CC" --emit-interface tests/incremental/zri_math.zrl -o "$WORK_DIR/iface_only/zri_math.zri"

"$ZORIL_CC" -c tests/incremental/zri_math.zrl -o "$WORK_DIR/zri_math.zil"
"$ZILC_BIN" "$WORK_DIR/zri_math.zil" -o "$WORK_DIR/zri_math.ssa"
"$BACKEND_BIN" -o "$WORK_DIR/zri_math.s" "$WORK_DIR/zri_math.ssa"
"$ASSEMBLER_BIN" "$WORK_DIR/zri_math.s" -o "$WORK_DIR/zri_math.o"

mkdir -p "$WORK_DIR/client_isolated"
cp tests/incremental/zri_client.zrl "$WORK_DIR/client_isolated/zri_client.zrl"

"$ZORIL_CC" -c "$WORK_DIR/client_isolated/zri_client.zrl" -I "$WORK_DIR/iface_only" -o "$WORK_DIR/zri_client.zil"
"$ZILC_BIN" "$WORK_DIR/zri_client.zil" -o "$WORK_DIR/zri_client.ssa"
"$BACKEND_BIN" -o "$WORK_DIR/zri_client.s" "$WORK_DIR/zri_client.ssa"
"$ASSEMBLER_BIN" "$WORK_DIR/zri_client.s" -o "$WORK_DIR/zri_client.o"

"$LINKER_BIN" -o "$WORK_DIR/zri_app_ld" build/runtime.o "$WORK_DIR/zri_client.o" "$WORK_DIR/zri_math.o"
"$WORK_DIR/zri_app_ld"
ZRI_LD_EXIT=$?
if [ "$ZRI_LD_EXIT" -ne 0 ]; then
    echo "FAIL: zri_app linked with ld exited with $ZRI_LD_EXIT, expected 0"
    exit 1
fi
echo "  [PASS] module consuming only .zri compiles and links, generic instantiating cleanly"

# ── Test 14: tools/zbuild marker density (0.00%) ─────────────────────────────
echo "14. Testing tools/zbuild raw-pointer marker density..."
zbuild_density=$(sh scripts/marker_density.sh tools/zbuild | awk '/line density:/{print $3}')
if [ "$zbuild_density" != "0.00%" ]; then
    echo "FAIL: tools/zbuild line density is $zbuild_density, expected 0.00%"
    exit 1
fi
echo "  [PASS] tools/zbuild line density is 0.00% (zero unsafe markers)"

# ── Test 15: tools/zbuild circular import detection and cycle path reporting ─
echo "15. Testing tools/zbuild circular import cycle rejection..."
mkdir -p "$WORK_DIR/cycle"
cat << 'EOF' > "$WORK_DIR/cycle/cycle_a.zrl"
import "cycle_b.zrl";
pub fn fa() -> i64 { return 1; }
EOF
cat << 'EOF' > "$WORK_DIR/cycle/cycle_b.zrl"
import "cycle_a.zrl";
pub fn fb() -> i64 { return 2; }
EOF

set +e
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$WORK_DIR/cycle/.cache" -o "$WORK_DIR/cycle/app" "$WORK_DIR/cycle/cycle_a.zrl" > "$WORK_DIR/cycle/out.log" 2> "$WORK_DIR/cycle/err.log"
CYCLE_STATUS=$?
set -e

if [ "$CYCLE_STATUS" -eq 0 ]; then
    echo "FAIL: expected circular import to fail, but exited 0"
    exit 1
fi
grep -q 'error: circular import detected:' "$WORK_DIR/cycle/err.log" || {
    echo "FAIL: missing 'error: circular import detected:' in output:"
    cat "$WORK_DIR/cycle/err.log"
    exit 1
}
echo "  [PASS] cycle rejection exited non-zero with diagnostic: $(cat "$WORK_DIR/cycle/err.log" | tr -d '\n')"

# ── Test 16: tools/zbuild child-process failure propagation ───────────────────
echo "16. Testing tools/zbuild child-process failure propagation..."
mkdir -p "$WORK_DIR/child_err"
cat << 'EOF' > "$WORK_DIR/child_err/bad.zrl"
fn main() -> i32 {
    let x: i32 = "type mismatch";
    return x;
}
EOF

set +e
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$WORK_DIR/child_err/.cache" -o "$WORK_DIR/child_err/app" "$WORK_DIR/child_err/bad.zrl" > "$WORK_DIR/child_err/out.log" 2> "$WORK_DIR/child_err/err.log"
CHILD_ERR_STATUS=$?
set -e

if [ "$CHILD_ERR_STATUS" -eq 0 ]; then
    echo "FAIL: expected build to fail on compiler error, but exited 0"
    exit 1
fi
grep -q 'error: type mismatch' "$WORK_DIR/child_err/err.log" || {
    echo "FAIL: child diagnostic not passed through:"
    cat "$WORK_DIR/child_err/err.log"
    exit 1
}
echo "  [PASS] child compilation failure aborted build with non-zero exit ($CHILD_ERR_STATUS) and diagnostic preserved"

# ── Test 17: Deep-chain early-cutoff test (A -> B -> C -> D) ──────────────────
echo "17. Testing tools/zbuild deep-chain early-cutoff (A -> B -> C -> D)..."
CHAIN_DIR="$WORK_DIR/deep_chain"
rm -rf "$CHAIN_DIR"
mkdir -p "$CHAIN_DIR"

cat << 'EOF' > "$CHAIN_DIR/d.zrl"
pub fn d_calc() -> i64 {
    return 42;
}
EOF

cat << 'EOF' > "$CHAIN_DIR/c.zrl"
import "d.zrl";
use d::d_calc;
pub fn c_calc() -> i64 {
    return d_calc() + 10;
}
EOF

cat << 'EOF' > "$CHAIN_DIR/b.zrl"
import "c.zrl";
use c::c_calc;
pub fn b_calc() -> i64 {
    return c_calc() + 100;
}
EOF

cat << 'EOF' > "$CHAIN_DIR/a.zrl"
import "b.zrl";
use b::b_calc;
pub fn main() -> i32 {
    let res = b_calc();
    if res == 152 { return 0 as i32; }
    return 1 as i32;
}
EOF

# 17a. Clean initial build: 4 compiles
out1=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$CHAIN_DIR/.cache" -o "$CHAIN_DIR/app" "$CHAIN_DIR/a.zrl")
"$CHAIN_DIR/app"
c1=$(echo "$out1" | grep -o 'compiled: [0-9]\+ modules' | awk '{print $2}')
if [ "$c1" -ne 4 ]; then
    echo "FAIL: expected 4 compiles on clean deep-chain build, got $c1"
    exit 1
fi

# 17b. No-op rebuild: 0 compiles
out2=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$CHAIN_DIR/.cache" -o "$CHAIN_DIR/app" "$CHAIN_DIR/a.zrl")
"$CHAIN_DIR/app"
c2=$(echo "$out2" | grep -o 'compiled: [0-9]\+ modules' | awk '{print $2}')
if [ "$c2" -ne 0 ]; then
    echo "FAIL: expected 0 compiles on deep-chain no-op rebuild, got $c2"
    exit 1
fi

# 17c. Body edit in D: rebuilds D only (early cutoff: C, B, A skipped) -> 1 compile
cat << 'EOF' > "$CHAIN_DIR/d.zrl"
pub fn d_calc() -> i64 {
    let mut x: i64 = 40;
    x = x + 2;
    return x;
}
EOF
out3=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" -v --cache-dir "$CHAIN_DIR/.cache" -o "$CHAIN_DIR/app" "$CHAIN_DIR/a.zrl")
"$CHAIN_DIR/app"
c3=$(echo "$out3" | grep -o 'compiled: [0-9]\+ modules' | awk '{print $2}')
if [ "$c3" -ne 1 ]; then
    echo "FAIL: expected 1 compile on body edit in D (early cutoff), got $c3"
    echo "$out3"
    exit 1
fi

# 17d. Public signature change in D: rebuilds all 4
cat << 'EOF' > "$CHAIN_DIR/d.zrl"
pub fn d_calc(extra: i64) -> i64 {
    return 42 + extra;
}
EOF
cat << 'EOF' > "$CHAIN_DIR/c.zrl"
import "d.zrl";
use d::d_calc;
pub fn c_calc(extra: i64) -> i64 {
    return d_calc(extra) + 10;
}
EOF
cat << 'EOF' > "$CHAIN_DIR/b.zrl"
import "c.zrl";
use c::c_calc;
pub fn b_calc(extra: i64) -> i64 {
    return c_calc(extra) + 100;
}
EOF
cat << 'EOF' > "$CHAIN_DIR/a.zrl"
import "b.zrl";
use b::b_calc;
pub fn main() -> i32 {
    let res = b_calc(0);
    if res == 152 { return 0 as i32; }
    return 1 as i32;
}
EOF
out4=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" -v --cache-dir "$CHAIN_DIR/.cache" -o "$CHAIN_DIR/app" "$CHAIN_DIR/a.zrl")
"$CHAIN_DIR/app"
c4=$(echo "$out4" | grep -o 'compiled: [0-9]\+ modules' | awk '{print $2}')
if [ "$c4" -ne 4 ]; then
    echo "FAIL: expected 4 compiles on signature change in D, got $c4"
    echo "$out4"
    exit 1
fi
echo "  [PASS] deep-chain early-cutoff: no-op -> 0 compiles, body edit -> 1 compile, signature change -> 4 compiles"

# ── Test 18: Instrumented 25-module project rebuild counts ────────────────────
if ! command -v lua >/dev/null 2>&1; then
    echo "18. [SKIP] Test 18: lua not found (needed by gen_multifile.lua)"
else
    echo "18. Testing tools/zbuild instrumented rebuild counts on 25-module project..."
    BENCH25_DIR="$WORK_DIR/bench25"
    rm -rf "$BENCH25_DIR"
    mkdir -p "$BENCH25_DIR"

    lua bench/cross_lang/gen_multifile.lua --out-dir "$BENCH25_DIR" --modules 25 --funcs 10 >/dev/null

    # 18a. Clean initial build: 26 compiles (25 modules + main)
    out_b1=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$BENCH25_DIR/.cache" -o "$BENCH25_DIR/app_ld" "$BENCH25_DIR/zoril/main.zrl")
    "$BENCH25_DIR/app_ld"
    cb1=$(echo "$out_b1" | grep -o 'compiled: [0-9]\+ modules' | awk '{print $2}')
    if [ "$cb1" -ne 26 ]; then
        echo "FAIL: expected 26 compiles on clean build, got $cb1"
        exit 1
    fi

    # 18b. No-op rebuild: 0 compiles
    out_b2=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$BENCH25_DIR/.cache" -o "$BENCH25_DIR/app_ld" "$BENCH25_DIR/zoril/main.zrl")
    "$BENCH25_DIR/app_ld"
    cb2=$(echo "$out_b2" | grep -o 'compiled: [0-9]\+ modules' | awk '{print $2}')
    if [ "$cb2" -ne 0 ]; then
        echo "FAIL: expected 0 compiles on no-op rebuild, got $cb2"
        exit 1
    fi

    # 18c. Body edit in mod7.zrl: exactly 1 compile
    sed 's/val + 800 as i64/val + 800 as i64 + 0 as i64/' "$BENCH25_DIR/zoril/mod7.zrl" > "$BENCH25_DIR/zoril/mod7.zrl.tmp" && mv "$BENCH25_DIR/zoril/mod7.zrl.tmp" "$BENCH25_DIR/zoril/mod7.zrl"
    out_b3=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$BENCH25_DIR/.cache" -o "$BENCH25_DIR/app_ld" "$BENCH25_DIR/zoril/main.zrl")
    "$BENCH25_DIR/app_ld"
    cb3=$(echo "$out_b3" | grep -o 'compiled: [0-9]\+ modules' | awk '{print $2}')
    if [ "$cb3" -ne 1 ]; then
        echo "FAIL: expected 1 compile on body edit in mod7, got $cb3"
        exit 1
    fi

    # 18d. Public signature change in mod7.zrl: exactly 2 compiles (mod7 + main)
    sed 's/pub fn calc_m7_f0(val: i64) -> i64/pub fn calc_m7_f0(val: i64, extra: i64) -> i64/' "$BENCH25_DIR/zoril/mod7.zrl" > "$BENCH25_DIR/zoril/mod7.zrl.tmp" && mv "$BENCH25_DIR/zoril/mod7.zrl.tmp" "$BENCH25_DIR/zoril/mod7.zrl"
    sed 's/calc_m7_f0(sum % 100 as i64)/calc_m7_f0(sum % 100 as i64, 0 as i64)/' "$BENCH25_DIR/zoril/main.zrl" > "$BENCH25_DIR/zoril/main.zrl.tmp" && mv "$BENCH25_DIR/zoril/main.zrl.tmp" "$BENCH25_DIR/zoril/main.zrl"
    out_b4=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$BENCH25_DIR/.cache" -o "$BENCH25_DIR/app_ld" "$BENCH25_DIR/zoril/main.zrl")
    "$BENCH25_DIR/app_ld"
    cb4=$(echo "$out_b4" | grep -o 'compiled: [0-9]\+ modules' | awk '{print $2}')
    if [ "$cb4" -ne 2 ]; then
        echo "FAIL: expected 2 compiles on mod7 signature change, got $cb4"
        exit 1
    fi

    # 18e. New module and import in main.zrl: exactly 2 compiles (mod25 + main)
    cat << 'EOF' > "$BENCH25_DIR/zoril/mod25.zrl"
pub fn calc_m25_f0(val: i64) -> i64 {
    return val + 1;
}
EOF
    ( printf 'import "mod25.zrl";\n' && cat "$BENCH25_DIR/zoril/main.zrl" ) > "$BENCH25_DIR/zoril/main.zrl.tmp" && mv "$BENCH25_DIR/zoril/main.zrl.tmp" "$BENCH25_DIR/zoril/main.zrl"
    awk '{gsub(/return sum as i32;/, "sum = sum + calc_m25_f0(0);\n    return sum as i32;"); print}' "$BENCH25_DIR/zoril/main.zrl" > "$BENCH25_DIR/zoril/main.zrl.tmp" && mv "$BENCH25_DIR/zoril/main.zrl.tmp" "$BENCH25_DIR/zoril/main.zrl"
    out_b5=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$BENCH25_DIR/.cache" -o "$BENCH25_DIR/app_ld" "$BENCH25_DIR/zoril/main.zrl")
    "$BENCH25_DIR/app_ld"
    cb5=$(echo "$out_b5" | grep -o 'compiled: [0-9]\+ modules' | awk '{print $2}')
    if [ "$cb5" -ne 2 ]; then
        echo "FAIL: expected 2 compiles on new module import, got $cb5"
        exit 1
    fi

    echo "  [PASS] 25-module project: clean -> 26, no-op -> 0, body edit -> 1, signature change -> 2, new import -> 2"
fi

# ── Test 19: Incremental vs clean build equivalence over edit sequence ───────
echo "19. Testing incremental vs clean build byte-identical equivalence over full edit sequence..."
ZORIL_CC="$ZORIL_CC" ZILC_BIN="$ZILC_CC" ZBUILD_BIN="$ZBUILD_BIN" TR_WORK="${TR_WORK:-build/tests}" \
    "$REPO/scripts/test_incremental_equivalence.sh"
echo "  [PASS] incremental output is byte-identical (cmp -s) to clean builds across all edits"

# ── Test 20: Multi-object linking ─────────────────────────────────────────────
echo "20. Testing multi-object linking and link-order invariance..."
MULTI_LINK_DIR="$WORK_DIR/multi_link"
mkdir -p "$MULTI_LINK_DIR"

# 20a. Compile all 4 modules with zoril -c, zilc, qbe, as
"$ZORIL_CC" -c tests/incremental/multi_link_types.zrl -o "$MULTI_LINK_DIR/types.zil"
"$ZORIL_CC" -c tests/incremental/multi_link_math.zrl -o "$MULTI_LINK_DIR/math.zil"
"$ZORIL_CC" -c tests/incremental/multi_link_generic.zrl -o "$MULTI_LINK_DIR/generic.zil"
"$ZORIL_CC" -c tests/incremental/multi_link_main.zrl -o "$MULTI_LINK_DIR/main.zil"

"$ZILC_BIN" "$MULTI_LINK_DIR/types.zil" -o "$MULTI_LINK_DIR/types.ssa"
"$ZILC_BIN" "$MULTI_LINK_DIR/math.zil" -o "$MULTI_LINK_DIR/math.ssa"
"$ZILC_BIN" "$MULTI_LINK_DIR/generic.zil" -o "$MULTI_LINK_DIR/generic.ssa"
"$ZILC_BIN" "$MULTI_LINK_DIR/main.zil" -o "$MULTI_LINK_DIR/main.ssa"

"$BACKEND_BIN" -o "$MULTI_LINK_DIR/types.s" "$MULTI_LINK_DIR/types.ssa"
"$BACKEND_BIN" -o "$MULTI_LINK_DIR/math.s" "$MULTI_LINK_DIR/math.ssa"
"$BACKEND_BIN" -o "$MULTI_LINK_DIR/generic.s" "$MULTI_LINK_DIR/generic.ssa"
"$BACKEND_BIN" -o "$MULTI_LINK_DIR/main.s" "$MULTI_LINK_DIR/main.ssa"

"$ASSEMBLER_BIN" "$MULTI_LINK_DIR/types.s" -o "$MULTI_LINK_DIR/types.o"
"$ASSEMBLER_BIN" "$MULTI_LINK_DIR/math.s" -o "$MULTI_LINK_DIR/math.o"
"$ASSEMBLER_BIN" "$MULTI_LINK_DIR/generic.s" -o "$MULTI_LINK_DIR/generic.o"
"$ASSEMBLER_BIN" "$MULTI_LINK_DIR/main.s" -o "$MULTI_LINK_DIR/main.o"

# 20b. Host ld link order invariance: canonical, reversed, runtime at end
"$LINKER_BIN" -o "$MULTI_LINK_DIR/app_ld1" build/runtime.o "$MULTI_LINK_DIR/main.o" "$MULTI_LINK_DIR/types.o" "$MULTI_LINK_DIR/math.o" "$MULTI_LINK_DIR/generic.o"
"$MULTI_LINK_DIR/app_ld1" || { echo "FAIL: multi_link app_ld1 exited $?"; exit 1; }

"$LINKER_BIN" -o "$MULTI_LINK_DIR/app_ld2" build/runtime.o "$MULTI_LINK_DIR/generic.o" "$MULTI_LINK_DIR/math.o" "$MULTI_LINK_DIR/types.o" "$MULTI_LINK_DIR/main.o"
"$MULTI_LINK_DIR/app_ld2" || { echo "FAIL: multi_link app_ld2 exited $?"; exit 1; }

"$LINKER_BIN" -o "$MULTI_LINK_DIR/app_ld3" "$MULTI_LINK_DIR/generic.o" "$MULTI_LINK_DIR/math.o" "$MULTI_LINK_DIR/types.o" "$MULTI_LINK_DIR/main.o" build/runtime.o
"$MULTI_LINK_DIR/app_ld3" || { echo "FAIL: multi_link app_ld3 exited $?"; exit 1; }

# 20d. Tools/zbuild end-to-end multi-module compilation
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$MULTI_LINK_DIR/.cache_ld" -o "$MULTI_LINK_DIR/zbuild_ld" tests/incremental/multi_link_main.zrl
"$MULTI_LINK_DIR/zbuild_ld" || { echo "FAIL: zbuild ld binary exited $?"; exit 1; }


# 20f. Check runtimes pairing gate
"$REPO/scripts/check_runtimes.sh" || { echo "FAIL: check_runtimes.sh failed"; exit 1; }

echo "  [PASS] multi-object linking: struct sharing, cross-module calls, globals, methods, generics; link order invariant; pairing verified"

# ── Test 21: Symbol grammar — canonical path, structured methods, one ABI across modes ──────────
echo "21. Testing mangling: canonical path, method components, -c vs whole-program symbol parity..."
MANGLE_DIR="$WORK_DIR/mangle"
rm -rf "$MANGLE_DIR"
mkdir -p "$MANGLE_DIR"
MANGLE_SRC=tests/incremental/mangle
compile_tu() {
    src="$1"; out="$2"
    "$ZORIL_CC" -c "$src" -o "$out.zil" >/dev/null 2>&1 || { echo "FAIL: zoril -c $src failed"; exit 1; }
    "$ZILC_BIN" "$out.zil" -o "$out.ssa"
    "$BACKEND_BIN" -o "$out.s" "$out.ssa"
    "$ASSEMBLER_BIN" "$out.s" -o "$out.o"
}
compile_tu "$MANGLE_SRC/a/util.zrl" "$MANGLE_DIR/a_util"
compile_tu "$MANGLE_SRC/b/util.zrl" "$MANGLE_DIR/b_util"
compile_tu "$MANGLE_SRC/main.zrl" "$MANGLE_DIR/main"

# 21a. Same basename in different directories yields distinct symbols over the full path.
nm "$MANGLE_DIR/a_util.o" | grep -q ' T z5tests11incremental6mangle1a4util5parseE$' || { echo "FAIL: a/util.zrl::parse not exported as z5tests11incremental6mangle1a4util5parseE"; nm "$MANGLE_DIR/a_util.o"; exit 1; }
nm "$MANGLE_DIR/b_util.o" | grep -q ' T z5tests11incremental6mangle1b4util5parseE$' || { echo "FAIL: b/util.zrl::parse not exported as z5tests11incremental6mangle1b4util5parseE"; nm "$MANGLE_DIR/b_util.o"; exit 1; }

# 21b. Methods are (path, type, method) components, not an underscore-joined name.
nm "$MANGLE_DIR/a_util.o" | grep -q ' T z5tests11incremental6mangle1a4util1P3getE$' || { echo "FAIL: method P.get not exported as ...1a4util1P3getE"; nm "$MANGLE_DIR/a_util.o"; exit 1; }
if nm "$MANGLE_DIR/a_util.o" | grep -q 'P_get'; then echo "FAIL: method symbol still underscore-joined"; exit 1; fi

# 21c. Both same-basename modules link into one program and the program runs.
"$LINKER_BIN" -o "$MANGLE_DIR/app" build/runtime.o "$MANGLE_DIR/main.o" "$MANGLE_DIR/a_util.o" "$MANGLE_DIR/b_util.o"
"$MANGLE_DIR/app" || { echo "FAIL: mangle app exited $?"; exit 1; }

# 21d. Whole-program and -c export the same names: every symbol the -c object defines also
# exists in the whole-program build of the same sources.
"$ZORIL_CC" --emit-zil -o "$MANGLE_DIR/whole.zil" "$MANGLE_SRC/main.zrl" >/dev/null 2>&1
"$ZILC_BIN" "$MANGLE_DIR/whole.zil" -o "$MANGLE_DIR/whole.ssa"
"$BACKEND_BIN" -o "$MANGLE_DIR/whole.s" "$MANGLE_DIR/whole.ssa"
"$ASSEMBLER_BIN" "$MANGLE_DIR/whole.s" -o "$MANGLE_DIR/whole.o"
nm "$MANGLE_DIR/a_util.o" | awk '$2=="T"{print $3}' | sort > "$MANGLE_DIR/tu_syms.txt"
nm "$MANGLE_DIR/whole.o" | awk '$2=="T"{print $3}' | sort > "$MANGLE_DIR/whole_syms.txt"
[ -s "$MANGLE_DIR/tu_syms.txt" ] || { echo "FAIL: no exported symbols in -c object"; exit 1; }
missing=$(comm -23 "$MANGLE_DIR/tu_syms.txt" "$MANGLE_DIR/whole_syms.txt")
if [ -n "$missing" ]; then
    echo "FAIL: -c exports symbols absent from the whole-program build (ABI fork):"
    echo "$missing"
    exit 1
fi
echo "  [PASS] full-path mangling, structured methods, and identical -c / whole-program symbols"

# ── Test 22: private helper reachable from a public generic body stays linkable ─────────────────
echo "22. Testing private functions used by public generic bodies link..."
GP_DIR="$WORK_DIR/generic_private"
rm -rf "$GP_DIR"
mkdir -p "$GP_DIR"
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$GP_DIR/.cache_ld" -o "$GP_DIR/app_ld" tests/incremental/generic_private/main.zrl >/dev/null
"$GP_DIR/app_ld" || { echo "FAIL: generic_private (ld) exited $?"; exit 1; }
lib_obj=$(ls "$GP_DIR"/.cache_ld/obj/*lib*.o)
nm "$lib_obj" | grep -q ' T z.*6helperE$' || { echo "FAIL: generic-reachable private helper is not global"; nm "$lib_obj"; exit 1; }
nm "$lib_obj" | grep -q ' T z.*4Box14bumpE$' || { echo "FAIL: generic-reachable private method is not global"; nm "$lib_obj"; exit 1; }
nm "$lib_obj" | grep -q ' t z.*9unrelatedE$' || { echo "FAIL: private function not reachable from a generic body must stay local"; nm "$lib_obj"; exit 1; }
echo "  [PASS] generic-reachable private helper exported and linked; unrelated private function stays local"

# ── Test 23: zbuild propagates a child's exit code and reports signals by tool name ─────────────
echo "23. Testing zbuild child exit-code and signal propagation..."
STUB_DIR="$WORK_DIR/child_stub"
rm -rf "$STUB_DIR"
mkdir -p "$STUB_DIR"
printf 'fn main() -> i32 { return 0; }\n' > "$STUB_DIR/m.zrl"
printf '#!/bin/sh\nexit 3\n' > "$STUB_DIR/exit3"
printf '#!/bin/sh\nkill -9 $$\n' > "$STUB_DIR/killed"
chmod +x "$STUB_DIR/exit3" "$STUB_DIR/killed"

set +e
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --compiler "$STUB_DIR/exit3" --cache-dir "$STUB_DIR/.c1" -o "$STUB_DIR/a1" "$STUB_DIR/m.zrl" >/dev/null 2>&1
code3=$?
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --compiler "$STUB_DIR/killed" --cache-dir "$STUB_DIR/.c2" -o "$STUB_DIR/a2" "$STUB_DIR/m.zrl" >/dev/null 2>"$STUB_DIR/kill.err"
code_kill=$?
set -e
[ "$code3" -eq 3 ] || { echo "FAIL: stub exiting 3 made zbuild exit $code3, expected 3"; exit 1; }
[ "$code_kill" -eq 137 ] || { echo "FAIL: SIGKILLed stub made zbuild exit $code_kill, expected 137"; exit 1; }
grep -q 'error: zoril --emit-deps killed by signal 9' "$STUB_DIR/kill.err" || { echo "FAIL: signal death not reported by tool name:"; cat "$STUB_DIR/kill.err"; exit 1; }
echo "  [PASS] child exit code 3 propagated; SIGKILL reported as 'zoril --emit-deps killed by signal 9' with exit 137"

# ── Test 24: cross-module safety summaries are enforced through zbuild ────────────────────────
echo "24. Testing cross-module escape summaries through zbuild..."
XS_DIR="$WORK_DIR/xmod_safety"
rm -rf "$XS_DIR"
mkdir -p "$XS_DIR"
cp tests/incremental/xmod_safety/*.zrl "$XS_DIR/"
set +e
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$XS_DIR/.c" -o "$XS_DIR/bad" "$XS_DIR/bad_caller.zrl" > "$XS_DIR/bad.out" 2> "$XS_DIR/bad.err"
bad_rc=$?
set -e
[ "$bad_rc" -ne 0 ] || { echo "FAIL: zbuild accepted a function returning a stack reference obtained across a module boundary"; exit 1; }
grep -q 'region escape: returning a pointer to local stack storage' "$XS_DIR/bad.err" || { echo "FAIL: expected the intra-module escape diagnostic through zbuild:"; cat "$XS_DIR/bad.err"; exit 1; }
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$XS_DIR/.g" -o "$XS_DIR/good" "$XS_DIR/good_caller.zrl" > /dev/null
set +e; "$XS_DIR/good"; good_rc=$?; set -e
[ "$good_rc" -eq 7 ] || { echo "FAIL: safe cross-module caller exited $good_rc, expected 7"; exit 1; }
grep -q 'summary(escape = 1,' "$XS_DIR/.g/iface/"*lib.zri || { echo "FAIL: lib interface lacks the escape summary (bit 0: its first parameter)"; exit 1; }
# A callee that stashes its argument in global memory is rejected the same way.
set +e
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$XS_DIR/.k" -o "$XS_DIR/keep" "$XS_DIR/keep_caller.zrl" > "$XS_DIR/keep.out" 2> "$XS_DIR/keep.err"
keep_rc=$?
set -e
[ "$keep_rc" -ne 0 ] || { echo "FAIL: zbuild accepted passing a stack pointer to a callee that stashes it globally"; exit 1; }
# The verifier's own store summary (stores/into) catches it first; the summary pass's check
# backs it up.
grep -Eq 'callee stores a pointer to local stack storage|callee stashes local stack pointer into global memory' "$XS_DIR/keep.err" || { echo "FAIL: expected the global-stash diagnostic through zbuild:"; cat "$XS_DIR/keep.err"; exit 1; }
echo "  [PASS] stack-escape and global-stash through an imported callee are rejected via zbuild; safe caller links and runs"

# ── Test 25: an imported function without a summary is treated conservatively ──────────────────
echo "25. Testing conservative default summary for imported functions without #[summary]..."
CONS_DIR="$WORK_DIR/conservative"
rm -rf "$CONS_DIR"
mkdir -p "$CONS_DIR/iface"
key="tests%2Fincremental%2Fconservative%2Flib"
printf '// zri-module: tests/incremental/conservative/lib.zrl\npub struct S {\n    pub a: i32,\n}\n\npub fn take(p: *mut S);\n' > "$CONS_DIR/iface/$key.zri"
set +e
"$ZORIL_CC" -c tests/incremental/conservative/caller.zrl --require-interface --iface-dir "$CONS_DIR/iface" --interproc-summary -o "$CONS_DIR/c.zil" > "$CONS_DIR/c.out" 2> "$CONS_DIR/c.err"
cons_rc=$?
set -e
[ "$cons_rc" -ne 0 ] || { echo "FAIL: passing a stack pointer to an imported function with no summary was accepted"; exit 1; }
grep -qE 'callee stashes local stack pointer|callee stores a pointer to local stack storage' "$CONS_DIR/c.err" || { echo "FAIL: expected the unknown-callee escape diagnostic:"; cat "$CONS_DIR/c.err"; exit 1; }
printf '// zri-module: tests/incremental/conservative/lib.zrl\npub struct S {\n    pub a: i32,\n}\n\n#[summary(escape = 0, stash = 0, ret_stack = false, alloc = 0, storage = 0, stores = 0, into = 0)]\npub fn take(p: *mut S);\n' > "$CONS_DIR/iface/$key.zri"
"$ZORIL_CC" -c tests/incremental/conservative/caller.zrl --require-interface --iface-dir "$CONS_DIR/iface" --interproc-summary -o "$CONS_DIR/c2.zil" > /dev/null 2>&1 || { echo "FAIL: caller rejected although the interface says the callee stashes nothing"; exit 1; }
echo "  [PASS] missing summary assumes the worst; an explicit clean summary lets the same caller compile"

# ── Test 26: dependency sources may be deleted after their first build ──────────────────────────
echo "26. Testing zbuild rebuilds a body-edited module with dependency sources deleted..."
DEL_DIR="$WORK_DIR/deleted_sources"
rm -rf "$DEL_DIR"
mkdir -p "$DEL_DIR"
printf 'pub fn math_val() -> i64 { return 20; }\n' > "$DEL_DIR/math.zrl"
printf 'import "math.zrl";\npub fn util_val() -> i64 { return math::math_val() + 1; }\n' > "$DEL_DIR/util.zrl"
write_del_main() { printf 'import "util.zrl";\npub fn main() -> i32 {\n    return (util::util_val() + %s) as i32;\n}\n' "$1" > "$DEL_DIR/main.zrl"; }
write_del_main 1
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$DEL_DIR/.c" -o "$DEL_DIR/app" "$DEL_DIR/main.zrl" > /dev/null
set +e; "$DEL_DIR/app"; rc1=$?; set -e
[ "$rc1" -eq 22 ] || { echo "FAIL: baseline exited $rc1, expected 22"; exit 1; }
rm -f "$DEL_DIR/util.zrl" "$DEL_DIR/math.zrl"
write_del_main 5
out=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$DEL_DIR/.c" -o "$DEL_DIR/app" "$DEL_DIR/main.zrl" 2>&1 | grep -o 'compiled: [0-9]\+ modules')
[ "$out" = "compiled: 1 modules" ] || { echo "FAIL: expected only main to recompile, got '$out'"; exit 1; }
set +e; "$DEL_DIR/app"; rc2=$?; set -e
[ "$rc2" -eq 26 ] || { echo "FAIL: rebuilt binary exited $rc2, expected 26"; exit 1; }
echo "  [PASS] body edit in main rebuilt against cached interfaces only (1 compile, correct result)"

# ── Test 27: the cache key covers every input that changes an object ───────────────────────────
echo "27. Testing zbuild cache-key completeness..."
CK_DIR="$WORK_DIR/cache_key"
rm -rf "$CK_DIR"
mkdir -p "$CK_DIR"
count_compiled() { grep -o 'compiled: [0-9]\+ modules' | awk '{print $2}'; }
write_m() { printf 'pub fn m_val() -> i64 { return %s; }\n' "$1" > "$CK_DIR/m.zrl"; }
printf 'import "m.zrl";\npub fn main() -> i32 { return m::m_val() as i32; }\n' > "$CK_DIR/main.zrl"
ZB_CK() { "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$CK_DIR/.c" -o "$CK_DIR/app" "$@" "$CK_DIR/main.zrl" 2>&1; }

# 27a. A different compiler binary invalidates every object.
cp build/zoril "$CK_DIR/zoril_copy"
write_m 3
n=$(ZB_CK --compiler "$CK_DIR/zoril_copy" | count_compiled)
[ "$n" -eq 2 ] || { echo "FAIL: clean build compiled $n modules, expected 2"; exit 1; }
n=$(ZB_CK --compiler "$CK_DIR/zoril_copy" | count_compiled)
[ "$n" -eq 0 ] || { echo "FAIL: no-op rebuild compiled $n modules"; exit 1; }
printf '\0' >> "$CK_DIR/zoril_copy"
n=$(ZB_CK --compiler "$CK_DIR/zoril_copy" | count_compiled)
[ "$n" -eq 2 ] || { echo "FAIL: rebuilt compiler reused old objects (compiled $n, expected 2)"; exit 1; }
echo "  [PASS] a changed compiler binary rebuilds everything"

# 27b. Same mtime, different size: size is part of the pre-filter.
touch -d '2001-01-01 00:00:00' "$CK_DIR/m.zrl"
ZB_CK --compiler "$CK_DIR/zoril_copy" > /dev/null
write_m 14
touch -d '2001-01-01 00:00:00' "$CK_DIR/m.zrl"
n=$(ZB_CK --compiler "$CK_DIR/zoril_copy" | count_compiled)
[ "$n" -ge 1 ] || { echo "FAIL: content edit with unchanged mtime (size differs) was not noticed"; exit 1; }
set +e; "$CK_DIR/app"; rc=$?; set -e
[ "$rc" -eq 14 ] || { echo "FAIL: stale binary after same-mtime edit (exit $rc, expected 14)"; exit 1; }
echo "  [PASS] same-mtime edit with a different size rebuilds"

# 27c. Racy timestamp: a source modified moments before the build is always re-hashed next time.
write_m 21
touch "$CK_DIR/m.zrl"
touch -r "$CK_DIR/m.zrl" "$CK_DIR/m.ref"
ZB_CK --compiler "$CK_DIR/zoril_copy" > /dev/null
write_m 22
touch -r "$CK_DIR/m.ref" "$CK_DIR/m.zrl"
n=$(ZB_CK --compiler "$CK_DIR/zoril_copy" | count_compiled)
[ "$n" -ge 1 ] || { echo "FAIL: same-size, same-mtime edit of a racy source was not noticed"; exit 1; }
set +e; "$CK_DIR/app"; rc=$?; set -e
[ "$rc" -eq 22 ] || { echo "FAIL: stale binary after racy edit (exit $rc, expected 22)"; exit 1; }
echo "  [PASS] racy same-size same-mtime edit rebuilds"

# 27d. A changed import resolution dirties the importer although its source is unchanged.
IR_DIR="$CK_DIR/ires"
mkdir -p "$IR_DIR/inc"
printf 'pub fn x_val() -> i64 { return 1; }\n' > "$IR_DIR/inc/x.zrl"
printf 'import "x.zrl";\npub fn main() -> i32 { return x::x_val() as i32; }\n' > "$IR_DIR/main.zrl"
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" -I "$IR_DIR/inc" --cache-dir "$IR_DIR/.c" -o "$IR_DIR/app" "$IR_DIR/main.zrl" > /dev/null
set +e; "$IR_DIR/app"; rc=$?; set -e
[ "$rc" -eq 1 ] || { echo "FAIL: baseline import resolution exited $rc, expected 1"; exit 1; }
printf 'pub fn x_val() -> i64 { return 2; }\n' > "$IR_DIR/x.zrl"
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" -I "$IR_DIR/inc" --cache-dir "$IR_DIR/.c" -o "$IR_DIR/app" "$IR_DIR/main.zrl" > /dev/null
set +e; "$IR_DIR/app"; rc=$?; set -e
[ "$rc" -eq 2 ] || { echo "FAIL: import now resolves to ./x.zrl but binary exited $rc, expected 2"; exit 1; }
echo "  [PASS] a file that changes what an unchanged import resolves to triggers a rebuild"

# 27e. a/b.zrl and a_b.zrl coexist (distinct cache names).
CL_DIR="$CK_DIR/collide"
mkdir -p "$CL_DIR/a"
printf 'pub fn ab_slash() -> i64 { return 10; }\n' > "$CL_DIR/a/b.zrl"
printf 'pub fn ab_under() -> i64 { return 5; }\n' > "$CL_DIR/a_b.zrl"
printf 'import "a/b.zrl";\nimport "a_b.zrl";\npub fn main() -> i32 { return (b::ab_slash() + a_b::ab_under()) as i32; }\n' > "$CL_DIR/main.zrl"
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$CL_DIR/.c" -o "$CL_DIR/app" "$CL_DIR/main.zrl" > /dev/null
set +e; "$CL_DIR/app"; rc=$?; set -e
[ "$rc" -eq 15 ] || { echo "FAIL: a/b.zrl + a_b.zrl program exited $rc, expected 15"; exit 1; }
[ "$(ls "$CL_DIR/.c/iface" | wc -l)" -eq 3 ] || { echo "FAIL: expected 3 distinct interfaces"; ls "$CL_DIR/.c/iface"; exit 1; }
echo "  [PASS] a/b.zrl and a_b.zrl keep separate interfaces and objects"

# 27f. The cache does not grow across repeated edits.
GC_DIR="$CK_DIR/gc"
mkdir -p "$GC_DIR"
printf 'import "m.zrl";\npub fn main() -> i32 { return m::m_val() as i32; }\n' > "$GC_DIR/main.zrl"
i=0
while [ "$i" -lt 20 ]; do
    printf 'pub fn m_val() -> i64 { return %s; }\n' "$i" > "$GC_DIR/m.zrl"
    "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$GC_DIR/.c" -o "$GC_DIR/app" "$GC_DIR/main.zrl" > /dev/null
    i=$((i + 1))
done
objs=$(ls "$GC_DIR/.c/obj" | wc -l)
ifaces=$(ls "$GC_DIR/.c/iface" | wc -l)
tmps=$(ls "$GC_DIR/.c/tmp" | wc -l)
[ "$objs" -eq 2 ] && [ "$ifaces" -eq 2 ] && [ "$tmps" -eq 0 ] || { echo "FAIL: cache grew: obj=$objs iface=$ifaces tmp=$tmps (expected 2/2/0)"; exit 1; }
echo "  [PASS] 20 toggling edits leave 2 objects, 2 interfaces, no intermediates"

# ── Test 28: the compiler is the single source of truth for imports ──────────────────────────
echo "28. Testing import discovery through the compiler (--emit-deps)..."
QD_DIR="$WORK_DIR/quote_import"
rm -rf "$QD_DIR"
mkdir -p "$QD_DIR"
printf 'pub fn util_val() -> i64 { return 1; }\n' > "$QD_DIR/util.zrl"
# A character literal containing a double quote precedes the import: a text scanner that does
# not lex char literals starts a phantom string here and loses the import.
cat << 'EOF' > "$QD_DIR/main.zrl"
fn quote() -> u8 { return '"' as u8; }
import "util.zrl";
pub fn main() -> i32 { return (util::util_val() as i32) + (quote() as i32); }
EOF
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$QD_DIR/.c" -o "$QD_DIR/app" "$QD_DIR/main.zrl" > /dev/null
set +e; "$QD_DIR/app"; rc=$?; set -e
[ "$rc" -eq 35 ] || { echo "FAIL: import after a '\"' char literal not honoured (exit $rc, expected 35)"; exit 1; }

# Differential: for every module of the compiler, stdlib and tools, the compiler's direct import
# edges match an independent scan of the file's `import "..."` lines.
checked=0
for f in src/*.zrl src/driver/*.zrl src/lower_zir/*.zrl src/parser/*.zrl stdlib/*.zrl stdlib/*/*.zrl tools/*/src/*.zrl; do
    "$ZORIL_CC" --emit-deps "$f" -I stdlib=stdlib -I src -I build/gen -o "$QD_DIR/edges.txt" > /dev/null 2>&1 || { echo "FAIL: --emit-deps failed on $f"; exit 1; }
    want=$(grep -o '^import "[^"]*"' "$f" | sed 's/^import "//; s/"$//' | sed 's|.*/||' | sort -u)
    got=$(awk -F'\t' -v f="$f" '$1==f {print $2}' "$QD_DIR/edges.txt" | sed 's|.*/||' | sort -u)
    if [ "$want" != "$got" ]; then
        echo "FAIL: import edges of $f differ from its import lines"
        echo "  scan:     $(echo "$want" | tr '\n' ' ')"
        echo "  compiler: $(echo "$got" | tr '\n' ' ')"
        exit 1
    fi
    checked=$((checked + 1))
done
[ "$checked" -gt 50 ] || { echo "FAIL: differential covered only $checked files"; exit 1; }
echo "  [PASS] '\"' char literal before an import resolves; compiler edges match import lines for $checked files"

# ── Test 29: summaries belong to their own declaration; alloc volume is a real dependency ──────
echo "29. Testing interface summary identity and alloc dependency..."
SI_DIR="$WORK_DIR/summary_identity"
rm -rf "$SI_DIR"
mkdir -p "$SI_DIR"
printf 'pub fn init(x: *mut i64) -> *mut i64 { return x; }\n' > "$SI_DIR/mod_a.zrl"
printf 'pub fn init(x: *mut i64) -> i64 { return 0; }\n' > "$SI_DIR/mod_b.zrl"
"$ZORIL_CC" --emit-interface "$SI_DIR/mod_a.zrl" -o "$SI_DIR/mod_a.zri" > /dev/null 2>&1
"$ZORIL_CC" --emit-interface "$SI_DIR/mod_b.zrl" -o "$SI_DIR/mod_b.zri" > /dev/null 2>&1
grep -q 'summary(escape = 1,' "$SI_DIR/mod_a.zri" || { echo "FAIL: mod_a init should report escape = 1 (bit 0: its first parameter)"; cat "$SI_DIR/mod_a.zri"; exit 1; }
grep -q 'summary(escape = 0' "$SI_DIR/mod_b.zri" || { echo "FAIL: mod_b init should report escape = 0"; cat "$SI_DIR/mod_b.zri"; exit 1; }

mkdir -p "$SI_DIR/alloc"
write_grab() { printf 'import "mem_raw.zrl";\npub unsafe fn grab(a: *mut mem_raw::ArenaHeader) -> *mut u8 { return mem_raw::zoril_allocator_alloc(a, %s as u64); }\n' "$1" > "$SI_DIR/alloc/g.zrl"; }
write_grab 64
"$ZORIL_CC" --emit-interface "$SI_DIR/alloc/g.zrl" -I stdlib=stdlib -o "$SI_DIR/alloc/g64.zri" > /dev/null 2>&1
write_grab 128
"$ZORIL_CC" --emit-interface "$SI_DIR/alloc/g.zrl" -I stdlib=stdlib -o "$SI_DIR/alloc/g128.zri" > /dev/null 2>&1
if cmp -s "$SI_DIR/alloc/g64.zri" "$SI_DIR/alloc/g128.zri"; then
    echo "FAIL: changing the constant allocation volume did not change the interface"
    exit 1
fi
diff "$SI_DIR/alloc/g64.zri" "$SI_DIR/alloc/g128.zri" | grep -q 'alloc = ' || { echo "FAIL: the interface difference is not the alloc summary"; exit 1; }
echo "  [PASS] each declaration carries its own summary; allocation volume (used by the interprocedural arena check) invalidates dependants"

# ── Test 30: methods and same-named free functions coexist ───────────────────
echo "30. Testing method and same-named free function coexistence..."
MFF_DIR="$WORK_DIR/method_free_fn"
rm -rf "$MFF_DIR"
mkdir -p "$MFF_DIR"
cat << 'EOF' > "$MFF_DIR/main.zrl"
struct P { x: i64 }
impl P {
    pub fn get(self: &P) -> i64 { return self.x; }
}
fn P_get(p: &P) -> i64 { return 100; }
pub fn main() -> i32 {
    let p = P { x: 5 };
    if p.get() != 5 as i64 { return 1; }
    if P::get(&p) != 5 as i64 { return 2; }
    if P_get(&p) != 100 as i64 { return 3; }
    return 0;
}
EOF
# Whole-program build
"$ZORIL_CC" --emit-zil -o "$MFF_DIR/main.zil" "$MFF_DIR/main.zrl" > /dev/null
"$ZILC_BIN" "$MFF_DIR/main.zil" "$MFF_DIR/main.ssa"
"$BACKEND_BIN" -o "$MFF_DIR/main.s" "$MFF_DIR/main.ssa"
"$ASSEMBLER_BIN" -o "$MFF_DIR/main.o" "$MFF_DIR/main.s"
"$LINKER_BIN" -o "$MFF_DIR/app_wp" build/runtime.o "$MFF_DIR/main.o"
set +e; "$MFF_DIR/app_wp"; rc=$?; set -e
[ "$rc" -eq 0 ] || { echo "FAIL: whole-program method and free function coexistence exited $rc, expected 0"; exit 1; }

# zbuild build
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$MFF_DIR/.c" -o "$MFF_DIR/app_zb" "$MFF_DIR/main.zrl" > /dev/null
set +e; "$MFF_DIR/app_zb"; rc=$?; set -e
[ "$rc" -eq 0 ] || { echo "FAIL: zbuild method and free function coexistence exited $rc, expected 0"; exit 1; }
echo "  [PASS] p.get(), P::get(&p), and P_get(&p) return their own values under whole-program and zbuild"

# ── Test 31: module identity is invariant to invocation directory and path spelling ───────────
echo "31. Testing 3-way invocation of helper.zrl yields identical symbols..."
H_DIR="$WORK_DIR/root_identity"
rm -rf "$H_DIR"
mkdir -p "$H_DIR"

# 1. From repo root
"$ZORIL_CC" -c tests/incremental/helper.zrl -o "$H_DIR/h1.zil" > /dev/null
"$ZILC_BIN" "$H_DIR/h1.zil" "$H_DIR/h1.ssa"
"$BACKEND_BIN" -o "$H_DIR/h1.s" "$H_DIR/h1.ssa"
"$ASSEMBLER_BIN" -o "$H_DIR/h1.o" "$H_DIR/h1.s"

# 2. From tests/
(cd tests && "$ZORIL_CC" -c incremental/helper.zrl -o "$H_DIR/h2.zil" > /dev/null)
"$ZILC_BIN" "$H_DIR/h2.zil" "$H_DIR/h2.ssa"
"$BACKEND_BIN" -o "$H_DIR/h2.s" "$H_DIR/h2.ssa"
"$ASSEMBLER_BIN" -o "$H_DIR/h2.o" "$H_DIR/h2.s"

# 3. By absolute path
"$ZORIL_CC" -c "$REPO/tests/incremental/helper.zrl" -o "$H_DIR/h3.zil" > /dev/null
"$ZILC_BIN" "$H_DIR/h3.zil" "$H_DIR/h3.ssa"
"$BACKEND_BIN" -o "$H_DIR/h3.s" "$H_DIR/h3.ssa"
"$ASSEMBLER_BIN" -o "$H_DIR/h3.o" "$H_DIR/h3.s"

nm "$H_DIR/h1.o" | awk '$2=="T"{print $3}' | sort > "$H_DIR/syms1.txt"
nm "$H_DIR/h2.o" | awk '$2=="T"{print $3}' | sort > "$H_DIR/syms2.txt"
nm "$H_DIR/h3.o" | awk '$2=="T"{print $3}' | sort > "$H_DIR/syms3.txt"

grep -q 'z5tests11incremental6helper10helper_addE' "$H_DIR/syms1.txt" || { echo "FAIL: expected canonical mangled symbol helper_add"; cat "$H_DIR/syms1.txt"; exit 1; }
cmp -s "$H_DIR/syms1.txt" "$H_DIR/syms2.txt" || { echo "FAIL: symbols differ between repo-root and tests/ invocations"; diff -u "$H_DIR/syms1.txt" "$H_DIR/syms2.txt"; exit 1; }
cmp -s "$H_DIR/syms1.txt" "$H_DIR/syms3.txt" || { echo "FAIL: symbols differ between relative and absolute invocations"; diff -u "$H_DIR/syms1.txt" "$H_DIR/syms3.txt"; exit 1; }
cmp -s "$H_DIR/h1.zil" "$H_DIR/h2.zil" || { echo "FAIL: ZIL differs between repo-root and tests/ invocations"; diff -u "$H_DIR/h1.zil" "$H_DIR/h2.zil"; exit 1; }
cmp -s "$H_DIR/h1.zil" "$H_DIR/h3.zil" || { echo "FAIL: ZIL differs between relative and absolute invocations"; diff -u "$H_DIR/h1.zil" "$H_DIR/h3.zil"; exit 1; }
echo "  [PASS] 3-way invocation (repo root, tests/, absolute path) emits identical symbols and byte-identical ZIL"

# ── Test 32: absolute -I and relative import map to one module and single static ─────────────
echo "32. Testing single object and shared static across absolute -I and relative import..."
INC_DIR="$WORK_DIR/shared_include"
rm -rf "$INC_DIR"
mkdir -p "$INC_DIR/lib"
touch "$INC_DIR/.zoril-root"

cat << 'EOF' > "$INC_DIR/lib/shared.zrl"
pub static mut COUNTER: i64 = 0;
pub fn bump() -> i64 {
    COUNTER = COUNTER + 1;
    return COUNTER;
}
EOF

cat << 'EOF' > "$INC_DIR/mod_rel.zrl"
import "lib/shared.zrl";
use shared::bump;
pub fn call_rel() -> i64 {
    return bump();
}
EOF

cat << 'EOF' > "$INC_DIR/mod_inc.zrl"
import "shared.zrl";
use shared::bump;
pub fn call_inc() -> i64 {
    return bump();
}
EOF

cat << 'EOF' > "$INC_DIR/main.zrl"
import "mod_rel.zrl";
import "mod_inc.zrl";
pub fn main() -> i32 {
    let a = mod_rel::call_rel();
    let b = mod_inc::call_inc();
    if a == 1 as i64 && b == 2 as i64 {
        return 0;
    }
    return 1;
}
EOF

"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" -I "$INC_DIR/lib" --cache-dir "$INC_DIR/.c" -o "$INC_DIR/app" "$INC_DIR/main.zrl" > /dev/null
set +e; "$INC_DIR/app"; rc=$?; set -e
[ "$rc" -eq 0 ] || { echo "FAIL: shared static program exited $rc, expected 0"; exit 1; }
objs=$(ls "$INC_DIR/.c/obj" | wc -l)
[ "$objs" -eq 4 ] || { echo "FAIL: expected 4 objects, found $objs"; ls "$INC_DIR/.c/obj"; exit 1; }
shared_objs=$(ls "$INC_DIR/.c/obj" | grep 'shared' | wc -l)
[ "$shared_objs" -eq 1 ] || { echo "FAIL: expected exactly 1 shared object, found $shared_objs"; ls "$INC_DIR/.c/obj"; exit 1; }
echo "  [PASS] file reached via absolute -I and relative import compiles once (1 object, shared static)"

# ── Test 33: import path resolving outside every root is rejected with located diagnostic ──────
echo "33. Testing import path resolving outside every root is rejected..."
OUT_DIR="$WORK_DIR/outside_root"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/proj" "$OUT_DIR/outside"
touch "$OUT_DIR/proj/.zoril-root"

cat << 'EOF' > "$OUT_DIR/outside/secret.zrl"
pub fn secret() -> i64 { return 42; }
EOF

cat << 'EOF' > "$OUT_DIR/proj/main.zrl"
import "../outside/secret.zrl";
pub fn main() -> i32 { return 0; }
EOF

set +e
"$ZORIL_CC" "$OUT_DIR/proj/main.zrl" > "$OUT_DIR/out" 2> "$OUT_DIR/err"
out_rc=$?
set -e
[ "$out_rc" -ne 0 ] || { echo "FAIL: import outside every root was accepted"; exit 1; }
grep -q ': error: path resolves outside every root: ' "$OUT_DIR/err" || { echo "FAIL: expected located 'path resolves outside every root' error:"; cat "$OUT_DIR/err"; exit 1; }
echo "  [PASS] path resolving outside every root rejected with located diagnostic"

# ── Test 34: multiple programs sharing one zbuild cache directory ─────────────────────────────
echo "34. Testing multiple programs sharing one cache directory..."
SC_DIR="$WORK_DIR/shared_cache"
rm -rf "$SC_DIR"
mkdir -p "$SC_DIR/clean_a" "$SC_DIR/clean_b" "$SC_DIR/shared"
touch "$SC_DIR/shared/.zoril-root" "$SC_DIR/clean_a/.zoril-root" "$SC_DIR/clean_b/.zoril-root"

cat << 'EOF' > "$SC_DIR/shared/lib.zrl"
pub fn shared_add(a: i64, b: i64) -> i64 {
    return a + b;
}
EOF

cat << 'EOF' > "$SC_DIR/shared/prog_a.zrl"
import "lib.zrl";
use lib::shared_add;
pub fn main() -> i32 {
    return (shared_add(10, 20) - 30) as i32;
}
EOF

cat << 'EOF' > "$SC_DIR/shared/prog_b.zrl"
import "lib.zrl";
use lib::shared_add;
pub fn main() -> i32 {
    return (shared_add(40, 50) - 90) as i32;
}
EOF

cp -r "$SC_DIR/shared"/* "$SC_DIR/clean_a/"
cp -r "$SC_DIR/shared"/* "$SC_DIR/clean_b/"

# Clean reference builds
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$SC_DIR/clean_a/.c" -o "$SC_DIR/clean_a/bin_a" "$SC_DIR/clean_a/prog_a.zrl" > /dev/null
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$SC_DIR/clean_b/.c" -o "$SC_DIR/clean_b/bin_b" "$SC_DIR/clean_b/prog_b.zrl" > /dev/null

CACHE="$SC_DIR/shared/.c"

# Round 1: Build A
out1=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$CACHE" -o "$SC_DIR/shared/bin_a" "$SC_DIR/shared/prog_a.zrl" 2>&1 | grep -o 'compiled: [0-9]\+ modules')
[ "$out1" = "compiled: 2 modules" ] || { echo "FAIL: round 1 expected 2 modules, got '$out1'"; exit 1; }
set +e; "$SC_DIR/shared/bin_a"; rc=$?; set -e
[ "$rc" -eq 0 ] || { echo "FAIL: round 1 bin_a exited $rc, expected 0"; exit 1; }

# Round 2: Build B (reuses lib.zrl from cache)
out2=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$CACHE" -o "$SC_DIR/shared/bin_b" "$SC_DIR/shared/prog_b.zrl" 2>&1 | grep -o 'compiled: [0-9]\+ modules')
[ "$out2" = "compiled: 1 modules" ] || { echo "FAIL: round 2 expected 1 module, got '$out2'"; exit 1; }
set +e; "$SC_DIR/shared/bin_b"; rc=$?; set -e
[ "$rc" -eq 0 ] || { echo "FAIL: round 2 bin_b exited $rc, expected 0"; exit 1; }

# Round 3: Build A (should compile 0 modules)
out3=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$CACHE" -o "$SC_DIR/shared/bin_a" "$SC_DIR/shared/prog_a.zrl" 2>&1 | grep -o 'compiled: [0-9]\+ modules')
[ "$out3" = "compiled: 0 modules" ] || { echo "FAIL: round 3 expected 0 modules, got '$out3'"; exit 1; }
set +e; "$SC_DIR/shared/bin_a"; rc=$?; set -e
[ "$rc" -eq 0 ] || { echo "FAIL: round 3 bin_a exited $rc, expected 0"; exit 1; }

# Round 4: Build B (should compile 0 modules)
out4=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$CACHE" -o "$SC_DIR/shared/bin_b" "$SC_DIR/shared/prog_b.zrl" 2>&1 | grep -o 'compiled: [0-9]\+ modules')
[ "$out4" = "compiled: 0 modules" ] || { echo "FAIL: round 4 expected 0 modules, got '$out4'"; exit 1; }
set +e; "$SC_DIR/shared/bin_b"; rc=$?; set -e
[ "$rc" -eq 0 ] || { echo "FAIL: round 4 bin_b exited $rc, expected 0"; exit 1; }

cmp -s "$SC_DIR/shared/bin_a" "$SC_DIR/clean_a/bin_a" || { echo "FAIL: bin_a differs from clean build"; exit 1; }
cmp -s "$SC_DIR/shared/bin_b" "$SC_DIR/clean_b/bin_b" || { echo "FAIL: bin_b differs from clean build"; exit 1; }

# 20 toggling edits of shared module: cache stays bounded
i=0
while [ "$i" -lt 20 ]; do
    cat << EOF > "$SC_DIR/shared/lib.zrl"
pub fn shared_add(a: i64, b: i64) -> i64 {
    return a + b + $i;
}
EOF
    "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$CACHE" -o "$SC_DIR/shared/bin_a" "$SC_DIR/shared/prog_a.zrl" > /dev/null
    "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --cache-dir "$CACHE" -o "$SC_DIR/shared/bin_b" "$SC_DIR/shared/prog_b.zrl" > /dev/null
    i=$((i + 1))
done

objs=$(ls "$CACHE/obj" | wc -l)
ifaces=$(ls "$CACHE/iface" | wc -l)
tmps=$(ls "$CACHE/tmp" | wc -l)
[ "$objs" -eq 3 ] && [ "$ifaces" -eq 3 ] && [ "$tmps" -eq 0 ] || { echo "FAIL: cache not bounded: obj=$objs iface=$ifaces tmp=$tmps (expected 3/3/0)"; exit 1; }
echo "  [PASS] alternating builds over shared cache compile 0 modules in rounds 3-4; cache stays bounded across 20 edits"

# ── Test 35: module identities decoupled from file paths in zbuild ───────────────
echo "35. Testing module identities decoupled from file paths in zbuild..."
EXT_DIR="$WORK_DIR/ext_repos"
rm -rf "$EXT_DIR"
mkdir -p "$EXT_DIR/project" "$EXT_DIR/ext_lib_a" "$EXT_DIR/ext_lib_b"

touch "$EXT_DIR/project/.zoril-root"

cat << 'EOF' > "$EXT_DIR/ext_lib_a/a.zrl"
pub fn ext_a_calc() -> i64 {
    return 100;
}
EOF

cat << 'EOF' > "$EXT_DIR/ext_lib_b/b.zrl"
import "a.zrl";
pub fn ext_b_calc() -> i64 {
    return a::ext_a_calc() + 20;
}
EOF

cat << 'EOF' > "$EXT_DIR/project/main.zrl"
import "core.zrl";
import "b.zrl";
pub fn main() -> i32 {
    let x: i64 = b::ext_b_calc();
    return (x - 78) as i32;
}
EOF

REPO_STDLIB="$(cd stdlib && pwd)"

# 35a. Build from inside the project directory using outside include dirs (including repo stdlib)
(cd "$EXT_DIR/project" && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --cache-dir "$EXT_DIR/project/.c" -I "stdlib=$REPO_STDLIB" -I "$EXT_DIR/ext_lib_a" -I "$EXT_DIR/ext_lib_b" -o "$EXT_DIR/project/app_inside" main.zrl > /dev/null)
set +e; "$EXT_DIR/project/app_inside"; rc=$?; set -e
[ "$rc" -eq 42 ] || { echo "FAIL: app_inside exited $rc, expected 42"; exit 1; }

# 35b. Build from an unrelated working directory (/tmp)
(cd /tmp && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --root "$EXT_DIR/project" --cache-dir "$EXT_DIR/project/.c" -I "stdlib=$REPO_STDLIB" -I "$EXT_DIR/ext_lib_a" -I "$EXT_DIR/ext_lib_b" -o "$EXT_DIR/project/app_outside" "$EXT_DIR/project/main.zrl" > /dev/null)
set +e; "$EXT_DIR/project/app_outside"; rc=$?; set -e
[ "$rc" -eq 42 ] || { echo "FAIL: app_outside exited $rc, expected 42"; exit 1; }

# 35c. No-op rebuild compiles 0 modules when run from unrelated working directory (/tmp)
out_noop=$(cd /tmp && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --root "$EXT_DIR/project" --cache-dir "$EXT_DIR/project/.c" -I "stdlib=$REPO_STDLIB" -I "$EXT_DIR/ext_lib_a" -I "$EXT_DIR/ext_lib_b" -o "$EXT_DIR/project/app_outside" "$EXT_DIR/project/main.zrl" 2>&1 | grep -o 'compiled: [0-9]\+ modules')
[ "$out_noop" = "compiled: 0 modules" ] || { echo "FAIL: no-op rebuild from outside expected 0 modules, got '$out_noop'"; exit 1; }

# 35d. Body edit in external library rebuilds properly
cat << 'EOF' > "$EXT_DIR/ext_lib_a/a.zrl"
pub fn ext_a_calc() -> i64 {
    return 105;
}
EOF
(cd /tmp && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --root "$EXT_DIR/project" --cache-dir "$EXT_DIR/project/.c" -I "stdlib=$REPO_STDLIB" -I "$EXT_DIR/ext_lib_a" -I "$EXT_DIR/ext_lib_b" -o "$EXT_DIR/project/app_outside" "$EXT_DIR/project/main.zrl" > /dev/null)
set +e; "$EXT_DIR/project/app_outside"; rc=$?; set -e
[ "$rc" -eq 47 ] || { echo "FAIL: edited app_outside exited $rc, expected 47"; exit 1; }

# 35e. Equivalence check: clean build in a separate directory matches byte-for-byte
mkdir -p "$EXT_DIR/clean_proj"
cp "$EXT_DIR/project/main.zrl" "$EXT_DIR/clean_proj/"
touch "$EXT_DIR/clean_proj/.zoril-root"
(cd /tmp && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --root "$EXT_DIR/clean_proj" --cache-dir "$EXT_DIR/clean_proj/.c" -I "stdlib=$REPO_STDLIB" -I "$EXT_DIR/ext_lib_a" -I "$EXT_DIR/ext_lib_b" -o "$EXT_DIR/clean_proj/app_clean" "$EXT_DIR/clean_proj/main.zrl" > /dev/null)
cmp -s "$EXT_DIR/project/app_outside" "$EXT_DIR/clean_proj/app_clean" || { echo "FAIL: incremental binary differs from clean binary"; exit 1; }
echo "  [PASS] project outside repo with external -I builds from CWD and /tmp, no-op compiles 0, matches clean build"

## ── Test 36: Collision-free identities for include-directory modules ──────────
# Files are placed in /tmp so they are genuinely outside the project root.
echo "36. Testing collision-free identities for -I modules..."
INC36_TMP="/tmp/zoril_inc_collision_$$"
rm -rf "$INC36_TMP"
mkdir -p "$INC36_TMP/x/lib" "$INC36_TMP/y/lib" "$INC36_TMP/project"
touch "$INC36_TMP/project/.zoril-root"

REPO_STDLIB="$(cd stdlib && pwd)"

# x/lib/s.zrl defines same1
cat << 'EOF' > "$INC36_TMP/x/lib/s.zrl"
pub fn same1() -> i64 {
    return 11;
}
EOF

# y/lib/s.zrl defines same2 (DISTINCT from same1)
cat << 'EOF' > "$INC36_TMP/y/lib/s.zrl"
pub fn same2() -> i64 {
    return 22;
}
EOF

# 36a. Bare -I with two directories sharing basename "lib" must be rejected.
# The project references both s.zrl files through two include roots that would collide.
cat << 'EOF' > "$INC36_TMP/project/main36a.zrl"
import "core.zrl";
import "s.zrl";
pub fn main() -> i32 {
    return s::same1() as i32;
}
EOF

set +e
"$ZORIL_CC" \
    --root "$INC36_TMP/project" \
    -I "$INC36_TMP/x/lib" \
    -I "$INC36_TMP/y/lib" \
    -I "stdlib=$REPO_STDLIB" \
    "$INC36_TMP/project/main36a.zrl" \
    -o "$INC36_TMP/project/bad_out" 2>"$INC36_TMP/conflict_err.log"
RC36A=$?
set -e
if [ "$RC36A" -eq 0 ]; then
    echo "FAIL (36a): expected conflict error for bare -I with duplicate basename 'lib', but compiler exited 0"
    exit 1
fi
grep -q "conflicting include root name 'lib'" "$INC36_TMP/conflict_err.log" || {
    echo "FAIL (36a): expected 'conflicting include root name' diagnostic, got:"
    cat "$INC36_TMP/conflict_err.log"
    exit 1
}
echo "  [PASS] 36a: bare -I with conflicting basenames rejected with located diagnostic"

# 36b. Explicit -I x_lib=<dir> -I y_lib=<dir> disambiguates.
# y/lib/b_named.zrl imports its sibling via the named prefix "y_lib/s.zrl".
cat << 'EOF' > "$INC36_TMP/y/lib/b_named.zrl"
import "y_lib/s.zrl";
pub fn b_named_calc() -> i64 {
    return s::same2();
}
EOF

cat << 'EOF' > "$INC36_TMP/project/main36b.zrl"
import "core.zrl";
import "x_lib/s.zrl";
import "y_lib/b_named.zrl";
pub fn main() -> i32 {
    return (s::same1() + b_named::b_named_calc() - 33) as i32;
}
EOF

"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" \
    --root "$INC36_TMP/project" \
    --cache-dir "$INC36_TMP/cache36b" \
    -I "x_lib=$INC36_TMP/x/lib" \
    -I "y_lib=$INC36_TMP/y/lib" \
    -I "stdlib=$REPO_STDLIB" \
    -o "$INC36_TMP/project/named_out" \
    "$INC36_TMP/project/main36b.zrl" > /dev/null 2>"$INC36_TMP/named_err.log" || {
    echo "FAIL (36b): named -I build failed:"
    cat "$INC36_TMP/named_err.log"
    exit 1
}
set +e; "$INC36_TMP/project/named_out"; RC36B_RUN=$?; set -e
[ "$RC36B_RUN" -eq 0 ] || {
    echo "FAIL (36b): named build ran and exited $RC36B_RUN, expected 0 (same1(11)+b_named_calc(22)-33=0)"
    exit 1
}
echo "  [PASS] 36b: explicit -I name=dir builds correctly (same1=11, b_named_calc=22, 11+22-33=0)"

# 36c. Standalone -c of x/lib/s.zrl and y/lib/s.zrl emit DISTINCT mangled symbols.
# With --root pointing to project (which neither lib dir is under), both files must
# pick up their module identity from the named include prefix.
"$ZORIL_CC" -c \
    --root "$INC36_TMP/project" \
    -I "x_lib=$INC36_TMP/x/lib" \
    -I "y_lib=$INC36_TMP/y/lib" \
    -I "stdlib=$REPO_STDLIB" \
    "$INC36_TMP/x/lib/s.zrl" \
    -o "$INC36_TMP/x_lib_s.zil" 2>/dev/null
"$ZORIL_CC" -c \
    --root "$INC36_TMP/project" \
    -I "x_lib=$INC36_TMP/x/lib" \
    -I "y_lib=$INC36_TMP/y/lib" \
    -I "stdlib=$REPO_STDLIB" \
    "$INC36_TMP/y/lib/s.zrl" \
    -o "$INC36_TMP/y_lib_s.zil" 2>/dev/null

# Extract the module-qualified function name from each .zil file.
# ZIL format: "f0: i64 <module>::<fn>(...)".
# Each file's identity is embedded in the function's fully-qualified path.
SYM_X=$(grep -oE '[a-z_][a-zA-Z0-9_]*(::s::same1)' "$INC36_TMP/x_lib_s.zil" | head -1)
SYM_Y=$(grep -oE '[a-z_][a-zA-Z0-9_]*(::s::same2)' "$INC36_TMP/y_lib_s.zil" | head -1)
[ -n "$SYM_X" ] || { echo "FAIL (36c): no qualified 'same1' found in x_lib_s.zil"; cat "$INC36_TMP/x_lib_s.zil"; exit 1; }
[ -n "$SYM_Y" ] || { echo "FAIL (36c): no qualified 'same2' found in y_lib_s.zil"; cat "$INC36_TMP/y_lib_s.zil"; exit 1; }
# The module prefix must differ: x_lib::s vs y_lib::s
PREFIX_X=$(echo "$SYM_X" | sed 's/::s::same1//')
PREFIX_Y=$(echo "$SYM_Y" | sed 's/::s::same2//')
if [ "$PREFIX_X" = "$PREFIX_Y" ]; then
    echo "FAIL (36c): x/lib/s.zrl and y/lib/s.zrl share the same module prefix: $PREFIX_X"
    exit 1
fi
echo "  [PASS] 36c: x/lib/s.zrl module prefix='$PREFIX_X', y/lib/s.zrl module prefix='$PREFIX_Y' (distinct identities)"

# 36d. Standalone -c with no project root: a *named* include root anchors the identity (xn::s vs
# yn::s) even though the fallback root is the file's own directory; an unnamed root keeps the
# directory-relative identity (s::), the documented unanchored case (spec §3.1.1).
"$ZORIL_CC" -c -I "xn=$INC36_TMP/x/lib" "$INC36_TMP/x/lib/s.zrl" -o "$INC36_TMP/x_named.zil" > /dev/null 2>&1
"$ZORIL_CC" -c -I "yn=$INC36_TMP/y/lib" "$INC36_TMP/y/lib/s.zrl" -o "$INC36_TMP/y_named.zil" > /dev/null 2>&1
grep -q 'xn::s::' "$INC36_TMP/x_named.zil" && grep -q 'yn::s::' "$INC36_TMP/y_named.zil" || { echo "FAIL (36d): named roots without --root did not give distinct identities"; exit 1; }
"$ZORIL_CC" -c -I "$INC36_TMP/x/lib" "$INC36_TMP/x/lib/s.zrl" -o "$INC36_TMP/x_unnamed.zil" > /dev/null 2>&1 || { echo "FAIL (36d): unanchored -c with an unnamed root must still compile"; exit 1; }
grep -q ' s::same' "$INC36_TMP/x_unnamed.zil" || { echo "FAIL (36d): unanchored identity is not directory-relative"; exit 1; }
echo "  [PASS] 36d: named roots anchor standalone identities (xn::s / yn::s); unanchored unnamed stays s::"

rm -rf "$INC36_TMP"

# -----------------------------------------------------------------------------
# 37. Cache locking: concurrent builds on one cache both succeed and keep entries
# -----------------------------------------------------------------------------
echo "37. Testing cache locking with concurrent zbuild runs..."
INC37_TMP="$WORK_DIR/concurrent_builds"
rm -rf "$INC37_TMP"
mkdir -p "$INC37_TMP/p1" "$INC37_TMP/p2" "$INC37_TMP/shared_cache"

# Program 1: p1_main imports p1_helper
cat << 'EOF' > "$INC37_TMP/p1/helper.zrl"
pub fn p1_val() -> i32 {
    return 11;
}
EOF

cat << 'EOF' > "$INC37_TMP/p1/main.zrl"
import "core.zrl";
import "helper.zrl";
use helper::p1_val;
pub fn main() -> i32 {
    let v = p1_val();
    if v == 11 { return 0 as i32; }
    return 1 as i32;
}
EOF

# Program 2: p2_main imports p2_helper
cat << 'EOF' > "$INC37_TMP/p2/helper.zrl"
pub fn p2_val() -> i32 {
    return 22;
}
EOF

cat << 'EOF' > "$INC37_TMP/p2/main.zrl"
import "core.zrl";
import "helper.zrl";
use helper::p2_val;
pub fn main() -> i32 {
    let v = p2_val();
    if v == 22 { return 0 as i32; }
    return 1 as i32;
}
EOF

# Launch both builds concurrently targeting the same cache directory
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" \
    --cache-dir "$INC37_TMP/shared_cache" \
    -I "stdlib=$REPO_STDLIB" \
    -o "$INC37_TMP/p1/app1" \
    "$INC37_TMP/p1/main.zrl" > "$INC37_TMP/p1_build.log" 2>&1 &
PID1=$!

"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" \
    --cache-dir "$INC37_TMP/shared_cache" \
    -I "stdlib=$REPO_STDLIB" \
    -o "$INC37_TMP/p2/app2" \
    "$INC37_TMP/p2/main.zrl" > "$INC37_TMP/p2_build.log" 2>&1 &
PID2=$!

wait "$PID1"
RC1=$?
wait "$PID2"
RC2=$?

if [ "$RC1" -ne 0 ]; then
    echo "FAIL (37): Program 1 concurrent build failed (exit $RC1):"
    cat "$INC37_TMP/p1_build.log"
    exit 1
fi

if [ "$RC2" -ne 0 ]; then
    echo "FAIL (37): Program 2 concurrent build failed (exit $RC2):"
    cat "$INC37_TMP/p2_build.log"
    exit 1
fi

# Verify both produced working executables
"$INC37_TMP/p1/app1" || { echo "FAIL (37): p1/app1 execution failed"; exit 1; }
"$INC37_TMP/p2/app2" || { echo "FAIL (37): p2/app2 execution failed"; exit 1; }

# Follow-up no-op build of Program 1: must compile 0 modules
OUT1_NOOP=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" \
    --cache-dir "$INC37_TMP/shared_cache" \
    -I "stdlib=$REPO_STDLIB" \
    -o "$INC37_TMP/p1/app1" \
    "$INC37_TMP/p1/main.zrl" 2>"$INC37_TMP/p1_noop.err")
C1_NOOP=$(echo "$OUT1_NOOP" | grep -o 'compiled: [0-9]\+ modules' | awk '{print $2}')
if [ "$C1_NOOP" -ne 0 ]; then
    echo "FAIL (37): expected 0 compiles on p1 no-op rebuild, got $C1_NOOP"
    echo "$OUT1_NOOP"
    cat "$INC37_TMP/p1_noop.err"
    exit 1
fi

# Follow-up no-op build of Program 2: must compile 0 modules
OUT2_NOOP=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" \
    --cache-dir "$INC37_TMP/shared_cache" \
    -I "stdlib=$REPO_STDLIB" \
    -o "$INC37_TMP/p2/app2" \
    "$INC37_TMP/p2/main.zrl" 2>"$INC37_TMP/p2_noop.err")
C2_NOOP=$(echo "$OUT2_NOOP" | grep -o 'compiled: [0-9]\+ modules' | awk '{print $2}')
if [ "$C2_NOOP" -ne 0 ]; then
    echo "FAIL (37): expected 0 compiles on p2 no-op rebuild, got $C2_NOOP"
    echo "$OUT2_NOOP"
    cat "$INC37_TMP/p2_noop.err"
    exit 1
fi

echo "  [PASS] 37: concurrent builds on one cache both succeed; subsequent no-op rebuilds compile 0 modules"
rm -rf "$INC37_TMP"

# ── Test 38: programs with different -I lists share one cache without evicting each other ──────
echo "38. Testing shared cache across programs with different -I lists..."
SI_DIR="$WORK_DIR/shared_inc"
rm -rf "$SI_DIR"
mkdir -p "$SI_DIR/lib1" "$SI_DIR/lib2" "$SI_DIR/proj"
touch "$SI_DIR/proj/.zoril-root"
printf 'pub fn one() -> i64 { return 1; }\n' > "$SI_DIR/lib1/x.zrl"
printf 'pub fn two() -> i64 { return 2; }\n' > "$SI_DIR/lib2/y.zrl"
printf 'pub fn common() -> i64 { return 10; }\n' > "$SI_DIR/proj/common.zrl"
printf 'import "common.zrl";\nimport "x.zrl";\npub fn main() -> i32 { return (common::common() + x::one()) as i32; }\n' > "$SI_DIR/proj/a.zrl"
printf 'import "common.zrl";\nimport "y.zrl";\npub fn main() -> i32 { return (common::common() + y::two()) as i32; }\n' > "$SI_DIR/proj/b.zrl"
SI_A() { "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" -I "$SI_DIR/lib1" --cache-dir "$SI_DIR/.c" -o "$SI_DIR/a.bin" "$SI_DIR/proj/a.zrl" 2>&1 | grep -o 'compiled: [0-9]* modules' | awk '{print $2}'; }
SI_B() { "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" -I "$SI_DIR/lib2" --cache-dir "$SI_DIR/.c" -o "$SI_DIR/b.bin" "$SI_DIR/proj/b.zrl" 2>&1 | grep -o 'compiled: [0-9]* modules' | awk '{print $2}'; }
r1=$(SI_A); r2=$(SI_B); r3=$(SI_A); r4=$(SI_B)
[ "$r3" -eq 0 ] && [ "$r4" -eq 0 ] || { echo "FAIL: alternating builds with different -I lists recompiled (rounds: $r1 $r2 $r3 $r4)"; exit 1; }
set +e; "$SI_DIR/a.bin"; ea=$?; "$SI_DIR/b.bin"; eb=$?; set -e
[ "$ea" -eq 11 ] && [ "$eb" -eq 12 ] || { echo "FAIL: shared-cache binaries exited $ea/$eb, expected 11/12"; exit 1; }
echo "  [PASS] different -I lists over one cache: rounds 3-4 compile 0 modules (rounds: $r1 $r2 $r3 $r4)"

# ── Test 39: rows for deleted modules are pruned; zbuild --gc sweeps without an entry ───────────
echo "39. Testing stale-row pruning and zbuild --gc..."
# 39a. Remove x.zrl from program A and delete it: its row and artifacts go once no program uses it.
printf 'import "common.zrl";\npub fn main() -> i32 { return common::common() as i32; }\n' > "$SI_DIR/proj/a.zrl"
rm -f "$SI_DIR/lib1/x.zrl"
SI_A > /dev/null
grep -q 'x\.zrl' "$SI_DIR/.c/manifest.tsv" && { echo "FAIL: row for deleted x.zrl survived"; exit 1; }
ls "$SI_DIR/.c/obj" "$SI_DIR/.c/iface" | grep -q 'x\.' && { echo "FAIL: artifacts of deleted x.zrl survived"; ls "$SI_DIR/.c/obj" "$SI_DIR/.c/iface"; exit 1; }
grep -q 'y\.zrl' "$SI_DIR/.c/manifest.tsv" || { echo "FAIL: program B's live row was evicted"; exit 1; }
# 39b. --gc without an entry: program B's sources disappear entirely.
rm -f "$SI_DIR/lib2/y.zrl" "$SI_DIR/proj/b.zrl"
gc_out=$("$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --compiler "$ZORIL_CC" --gc --cache-dir "$SI_DIR/.c" 2>&1)
echo "$gc_out" | grep -q 'gc: removed 2 stale rows' || { echo "FAIL: expected 2 stale rows removed, got: $gc_out"; exit 1; }
grep -q 'y\.zrl\|/b\.zrl' "$SI_DIR/.c/manifest.tsv" && { echo "FAIL: --gc left rows for deleted sources"; exit 1; }
n_obj=$(ls "$SI_DIR/.c/obj" | wc -l); n_iface=$(ls "$SI_DIR/.c/iface" | wc -l)
[ "$n_obj" -eq 2 ] && [ "$n_iface" -eq 2 ] || { echo "FAIL: after --gc expected 2 objects/interfaces (a, common), got $n_obj/$n_iface"; exit 1; }
n=$(SI_A); [ "$n" -eq 0 ] || { echo "FAIL: --gc evicted live program A's artifacts (recompiled $n)"; exit 1; }
echo "  [PASS] deleted modules' rows and artifacts pruned; --gc removed 2 stale rows and kept program A intact"

# ── Test 40: the cache is relocatable across working directories ───────────────────────────────
echo "40. Testing the cache from a different working directory..."
RL_DIR="$WORK_DIR/reloc"
rm -rf "$RL_DIR"
mkdir -p "$RL_DIR"
touch "$RL_DIR/.zoril-root"
printf 'pub fn m() -> i64 { return 7; }\n' > "$RL_DIR/m.zrl"
printf 'import "m.zrl";\npub fn main() -> i32 { return m::m() as i32; }\n' > "$RL_DIR/main.zrl"
(cd "$RL_DIR" && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --cache-dir .c -o bin1 main.zrl > /dev/null 2>&1)
n=$(cd / && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --cache-dir "$RL_DIR/.c" -o "$RL_DIR/bin2" "$RL_DIR/main.zrl" 2>&1 | grep -o 'compiled: [0-9]* modules' | awk '{print $2}')
[ "$n" -eq 0 ] || { echo "FAIL: same cache from another working directory recompiled $n modules"; exit 1; }
cmp -s "$RL_DIR/bin1" "$RL_DIR/bin2" || { echo "FAIL: binaries differ between working directories"; exit 1; }
grep -v '^#' "$RL_DIR/.c/manifest.tsv" | cut -f6 | grep -qv '^obj/' && { echo "FAIL: manifest stores object paths not relative to the cache"; exit 1; }
echo "  [PASS] relative cache built in the project dir is reused from / (0 compiles, identical binary)"

# ── Test 41: float literals survive the .zri of a generic function ─────────────────────────────
echo "41. Testing float literals in a generic function's interface..."
FL_DIR="$WORK_DIR/float_iface"
rm -rf "$FL_DIR"
mkdir -p "$FL_DIR"
touch "$FL_DIR/.zoril-root"
printf 'pub fn scaled<T>(t: T, x: f64) -> i32 { let z = 3.75f32; return (x * 0.5 + 1.25 + z as f64) as i32; }\n' > "$FL_DIR/lib.zrl"
printf 'import "lib.zrl";\npub fn main() -> i32 { return lib::scaled(0, 10.0); }\n' > "$FL_DIR/main.zrl"
(cd "$FL_DIR" && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --cache-dir .c -o bin main.zrl > build.log 2>&1) || { echo "FAIL: building the float interface program"; cat "$FL_DIR/build.log"; exit 1; }
rc=0; "$FL_DIR/bin" || rc=$?
[ "$rc" -eq 10 ] || { echo "FAIL: generic body from the .zri computed $rc, expected 10 (float literals lost)"; exit 1; }
grep -q '3.75f32' "$FL_DIR"/.c/iface/*.zri || { echo "FAIL: the .zri does not carry the literal 3.75f32"; exit 1; }
echo "  [PASS] 0.5, 1.25 and 3.75f32 reach the instantiating module exactly"

# ── Test 42: a generic body's expressions keep their meaning through the .zri ──────────────────
echo "42. Testing operator precedence, 1-tuples and closures in a generic function's interface..."
PR_DIR="$WORK_DIR/prec_iface"
rm -rf "$PR_DIR"
mkdir -p "$PR_DIR"
touch "$PR_DIR/.zoril-root"
cat > "$PR_DIR/lib.zrl" <<'EOF'
pub fn neg_cast<T>(a: u32, t: T) -> i64 { return -(a as i64); }
pub fn not_cast<T>(a: u8, t: T) -> bool { return !((a as i8) >= 0); }
pub fn tup1<T>(t: T) -> (T,) { return (t,); }
pub fn clos<T>(t: T) -> i64 { return (|x: i64| -> i64 { x + 1 })(4); }
EOF
cat > "$PR_DIR/main.zrl" <<'EOF'
import "lib.zrl";
use lib::{clos, neg_cast, not_cast, tup1};
pub fn main() -> i32 {
    if neg_cast(5 as u32, 0) != -5 { return 1; }
    if not_cast(0 as u8, 0) { return 2; }
    if tup1(11).0 != 11 { return 3; }
    if clos(0) != 5 { return 4; }
    return 0;
}
EOF
(cd "$PR_DIR" && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --cache-dir .c -o bin main.zrl > build.log 2>&1) || { echo "FAIL: building the precedence interface program"; cat "$PR_DIR/build.log"; exit 1; }
rc=0; "$PR_DIR/bin" || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: generic body from the .zri failed check $rc (an expression printed with another meaning)"; exit 1; }
echo "  [PASS] casts under unary operators, (T,) and a called closure keep their meaning"

# ── Test 43: trait default methods and associated types across modules, through the .zri ──────
echo "43. Testing a trait's default methods and associated types used from other modules..."
TD_DIR="$WORK_DIR/trait_defaults"
rm -rf "$TD_DIR"
mkdir -p "$TD_DIR"
touch "$TD_DIR/.zoril-root"
cat > "$TD_DIR/shape.zrl" <<'EOF'
pub trait Shape {
    type Unit;
    fn area(self: &Self) -> i32;
    fn unit(self: &Self) -> Self::Unit;
    fn double_area(self: &Self) -> i32 { return self.area() * 2; }
    fn scaled<T: Copy>(self: &Self, t: T) -> (i32, T) { return (self.double_area(), t); }
}
EOF
cat > "$TD_DIR/sq.zrl" <<'EOF'
import "shape.zrl";
use shape::Shape;
pub struct Sq { pub s: i32 }
impl Shape for Sq {
    type Unit = i64;
    fn area(self: &Sq) -> i32 { return self.s * self.s; }
    fn unit(self: &Sq) -> i64 { return 7 as i64; }
}
pub fn sq_double(q: &Sq) -> i32 { return q.double_area(); }
EOF
cat > "$TD_DIR/main.zrl" <<'EOF'
import "shape.zrl";
import "sq.zrl";
use shape::Shape;
use sq::{Sq, sq_double};
fn units<T: Shape>(t: &T) -> T::Unit { return t.unit(); }
pub fn main() -> i32 {
    let q = Sq { s: 3 };
    if q.double_area() != 18 { return 1; }
    if sq_double(&q) != 18 { return 2; }
    if units(&q) != 7 as i64 { return 3; }
    let p = q.scaled(true);
    if p.0 != 18 || !p.1 { return 4; }
    return 0;
}
EOF
(cd "$TD_DIR" && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --cache-dir .c -o bin main.zrl > build.log 2>&1) || { echo "FAIL: building the trait-defaults program"; cat "$TD_DIR/build.log"; exit 1; }
rc=0; "$TD_DIR/bin" || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: trait defaults across modules failed check $rc"; exit 1; }
SQ_ZRI=$(grep -rl "zri-module: sq" "$TD_DIR/.c")
grep -q "type Unit = i64;" $SQ_ZRI || { echo "FAIL: sq's interface lacks its associated type"; exit 1; }
if grep -q "fn double_area" $SQ_ZRI; then echo "FAIL: sq's interface repeats a default method"; exit 1; fi
echo "  [PASS] defaults are instantiated per TU and associated types travel through the .zri"

# ── Test 44: stdlib HashMap across modules through zbuild (primitive trait summaries in .zri) ──
echo "44. Testing HashMap insert and lookup across modules through zbuild..."
HM_DIR="$WORK_DIR/hashmap_xmod"
rm -rf "$HM_DIR"
mkdir -p "$HM_DIR"
touch "$HM_DIR/.zoril-root"
cat > "$HM_DIR/main.zrl" <<'EOF'
import "hashmap.zrl";
import "mem.zrl";
use hashmap::HashMap;
use mem::Arena;

pub fn main() -> i32 {
    let a = Arena.new(1 << 20).unwrap();
    let mut m = HashMap::<u64, u64>.new(&a);
    let key = 123456789 as u64;
    m.insert(key, 42 as u64);
    let val = match m.get(&key) {
        Some(v) => *v,
        None => 0 as u64,
    };
    if val != 42 as u64 { return 1; }
    return 0;
}
EOF
(cd "$HM_DIR" && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --cache-dir .c -I "stdlib=$REPO/stdlib" -o bin main.zrl > build.log 2>&1) || { echo "FAIL: building HashMap program via zbuild"; cat "$HM_DIR/build.log"; exit 1; }
rc=0; "$HM_DIR/bin" || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: HashMap across modules failed check $rc"; exit 1; }
CMP_ZRI=$(grep -rl "zri-module: stdlib/cmp" "$HM_DIR/.c")
grep -q "#\[summary(escape = 0, stash = 0" "$CMP_ZRI" || { echo "FAIL: cmp interface lacks primitive summary"; exit 1; }
echo "  [PASS] HashMap insert/get compiles via zbuild and primitive trait summaries travel through .zri"

# ── Test 45: escaping method on primitive type across modules through zbuild ──
echo "45. Testing escaping method on primitive type across modules through zbuild..."
SP_DIR="$WORK_DIR/stash_primitive_xmod"
rm -rf "$SP_DIR"
mkdir -p "$SP_DIR"
touch "$SP_DIR/.zoril-root"
cat > "$SP_DIR/lib.zrl" <<'EOF'
pub static mut KEEP: usize = 0 as usize;
pub trait Stash {
    fn stash(self: &Self);
}
impl Stash for u64 {
    fn stash(self: &u64) {
        KEEP = self as *u64 as usize;
    }
}
EOF
cat > "$SP_DIR/main.zrl" <<'EOF'
import "lib.zrl";
use lib::Stash;

pub fn main() -> i32 {
    let x: u64 = 5;
    x.stash();
    return 0;
}
EOF
set +e
(cd "$SP_DIR" && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --cache-dir .c -o bin main.zrl > build.log 2>&1)
sp_rc=$?
set -e
[ "$sp_rc" -ne 0 ] || { echo "FAIL: zbuild accepted an escaping method on a primitive type across modules"; exit 1; }
grep -q 'region escape: the callee stores a pointer to local stack storage where it outlives this function' "$SP_DIR/build.log" || { echo "FAIL: expected escape diagnostic for primitive method stash:"; cat "$SP_DIR/build.log"; exit 1; }
LIB_ZRI=$(grep -rl "zri-module: lib" "$SP_DIR/.c")
grep -q "#\[summary(escape = 0, stash = 1" "$LIB_ZRI" || { echo "FAIL: lib interface lacks stash=1 summary on primitive method"; exit 1; }
echo "  [PASS] escaping method on primitive type carries stash summary through .zri and is rejected across modules"

# ── Test 46: the block-scope storage summary travels through .zri across modules ──
echo "46. Testing the block-scope storage summary across modules through zbuild..."
BS_DIR="$WORK_DIR/block_scope_storage_xmod"
rm -rf "$BS_DIR"
mkdir -p "$BS_DIR"
touch "$BS_DIR/.zoril-root"
cat > "$BS_DIR/lib.zrl" <<'EOF'
fn inner(r: &i32) -> &i32 { return r; }
pub fn wrapper(r: &i32) -> &i32 { return inner(r); }
EOF
cat > "$BS_DIR/main.zrl" <<'EOF'
import "lib.zrl";
use lib::wrapper;

pub fn main() -> i32 {
    let mut r: &i32 = &0;
    {
        let x: i32 = 5;
        r = wrapper(&x);
    }
    return *r;
}
EOF
set +e
(cd "$BS_DIR" && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --cache-dir .c -o bin main.zrl > build.log 2>&1)
bs_rc=$?
set -e
[ "$bs_rc" -ne 0 ] || { echo "FAIL: zbuild accepted a wrapper that returns a reference into a local's storage across modules"; exit 1; }
grep -q "cannot let 'x' go out of scope while it is still borrowed" "$BS_DIR/build.log" || { echo "FAIL: expected block-scope diagnostic for the cross-module wrapper:"; cat "$BS_DIR/build.log"; exit 1; }
LIB_ZRI=$(grep -rl "zri-module: lib" "$BS_DIR/.c")
grep -q "storage = 1" "$LIB_ZRI" || { echo "FAIL: lib interface lacks storage=1 for the forwarding wrapper"; exit 1; }
echo "  [PASS] the forwarding wrapper's own-storage summary travels through .zri and is rejected across modules"

# ── Test 47: a .zri without the storage summary reads as unknown, not as "nothing escapes" ──
echo "47. Testing that a stale interface without #[summary] is treated as unknown..."
SI_DIR="$WORK_DIR/stale_iface"
rm -rf "$SI_DIR"
# `--iface-dir DIR` looks a module's interface up at `DIR/<encoded key>.zri`, where the key is the
# module's path relative to the project root with `/` written as `%2F` (src/module_path.zrl
# `encode_module_key`). Writing `DIR/lib.zri` instead meant the lookup missed and the compiler read the
# *source*, without a word - which is why this test and test 48 passed whichever interface they were
# given. The guard below is what makes that impossible to repeat.
key=$(printf '%s' "${SI_DIR#"$REPO/"}/lib" | sed 's|/|%2F|g')
mkdir -p "$SI_DIR/stale" "$SI_DIR/omit"
cat > "$SI_DIR/lib.zrl" <<'ZEOF'
pub fn id(r: &i32) -> &i32 {
    return r;
}
ZEOF
cat > "$SI_DIR/main.zrl" <<'ZEOF'
import "lib.zrl";
use lib::id;

fn leak() -> &i32 {
    let x = 5 as i32;
    return id(&x);
}

pub fn main() -> i32 { return *leak(); }
ZEOF
"$ZORIL_CC" -c -I "$SI_DIR" --write-interface "$SI_DIR/$key.zri" -o "$SI_DIR/lib.zil" "$SI_DIR/lib.zrl"
grep -q '^#\[summary(' "$SI_DIR/$key.zri" || { echo "FAIL: the fresh interface carries no #[summary] to strip"; cat "$SI_DIR/lib.zri"; exit 1; }
# A stale or hand-written interface: the storage masks are absent, so they are unknown.
grep -v '^#\[summary(' "$SI_DIR/$key.zri" > "$SI_DIR/stale/$key.zri"
# The interface is really read: an interface that omits the function the caller uses must fail. With the
# source fallback this compiles, so this guard fails the moment the lookup misses again.
printf '// zri-module: %s/lib.zrl\n' "$SI_DIR/lib" > "$SI_DIR/omit/$key.zri"
set +e
"$ZORIL_CC" -c -I "$SI_DIR" --require-interface --iface-dir "$SI_DIR/omit" -o "$SI_DIR/omit.zil" "$SI_DIR/main.zrl" > "$SI_DIR/omit.log" 2>&1
omit_rc=$?
set -e
[ "$omit_rc" -ne 0 ] || { echo "FAIL: an interface holding none of the caller's functions was accepted - the interface is not being read"; exit 1; }
set +e
"$ZORIL_CC" -c -I "$SI_DIR" --require-interface --iface-dir "$SI_DIR/stale" -o "$SI_DIR/main.zil" "$SI_DIR/main.zrl" > "$SI_DIR/stale.log" 2>&1
stale_rc=$?
set -e
[ "$stale_rc" -ne 0 ] || { echo "FAIL: a stale interface accepted a call that hands back a pointer into a local's storage (the unknown masks read as 'nothing escapes')"; exit 1; }
grep -q "region escape" "$SI_DIR/stale.log" || { echo "FAIL: expected a region-escape diagnostic for the stale interface:"; cat "$SI_DIR/stale.log"; exit 1; }
# The same caller against the real interface is rejected too, by the summary instead of the
# unknown fallback: the pair is what pins `storage_known`.
set +e
"$ZORIL_CC" -c -I "$SI_DIR" --require-interface --iface-dir "$SI_DIR" -o "$SI_DIR/main2.zil" "$SI_DIR/main.zrl" > "$SI_DIR/fresh.log" 2>&1
fresh_rc=$?
set -e
[ "$fresh_rc" -ne 0 ] || { echo "FAIL: the caller was accepted against its own fresh interface"; exit 1; }
echo "  [PASS] a .zri without the storage summary reads as unknown and is rejected (fresh: rejected, stale: rejected)"

# ── Test 48: an unknown storage mask is read as the argument's own storage (the ZIR side) ──
echo "48. Testing that an unknown storage mask is read as the argument's own storage..."
ZU_DIR="$WORK_DIR/unknown_own_storage"
zukey=$(printf '%s' "${ZU_DIR#"$REPO/"}/lib" | sed 's|/|%2F|g')
rm -rf "$ZU_DIR"
mkdir -p "$ZU_DIR/stale" "$ZU_DIR/omit"
cat > "$ZU_DIR/lib.zrl" <<'ZEOF'
pub fn same(r: &i32) -> &i32 {
    return r;
}
ZEOF
cat > "$ZU_DIR/main.zrl" <<'ZEOF'
import "lib.zrl";
use lib::same;

pub fn main() -> i32 {
    let mut out: Option<&i32> = Option.None;
    {
        let x: i32 = 7;
        out = same(&x);
    }
    return match out {
        Option.Some(r) => *r,
        Option.None => 0,
    };
}
ZEOF
"$ZORIL_CC" -c -I "$ZU_DIR" --write-interface "$ZU_DIR/$zukey.zri" -o "$ZU_DIR/lib.zil" "$ZU_DIR/lib.zrl"
printf '// zri-module: %s/lib.zrl\n' "$ZU_DIR/lib" > "$ZU_DIR/omit/$zukey.zri"
set +e
"$ZORIL_CC" -c -I "$ZU_DIR" --require-interface --iface-dir "$ZU_DIR/omit" -o "$ZU_DIR/omit.zil" "$ZU_DIR/main.zrl" > "$ZU_DIR/omit.log" 2>&1
omit_rc=$?
set -e
[ "$omit_rc" -ne 0 ] || { echo "FAIL: an interface holding none of the caller's functions was accepted - the interface is not being read"; exit 1; }
grep -q 'storage = 1' "$ZU_DIR/$zukey.zri" || { echo "FAIL: the fresh interface has no own-storage bit for the &i32 parameter"; cat "$ZU_DIR/lib.zri"; exit 1; }
grep -v '^#\[summary(' "$ZU_DIR/$zukey.zri" > "$ZU_DIR/stale/$zukey.zri"
set +e
"$ZORIL_CC" -c -I "$ZU_DIR" --require-interface --iface-dir "$ZU_DIR" -o "$ZU_DIR/fresh.zil" "$ZU_DIR/main.zrl" > "$ZU_DIR/fresh.log" 2>&1
zu_fresh=$?
"$ZORIL_CC" -c -I "$ZU_DIR" --require-interface --iface-dir "$ZU_DIR/stale" -o "$ZU_DIR/stale.zil" "$ZU_DIR/main.zrl" > "$ZU_DIR/stale.log" 2>&1
zu_stale=$?
set -e
[ "$zu_fresh" -ne 0 ] || { echo "FAIL: the caller was accepted against the complete interface (own storage not seen)"; exit 1; }
[ "$zu_stale" -ne 0 ] || { echo "FAIL: a stale interface accepted a borrow into a local's own storage outliving the local"; cat "$ZU_DIR/stale.log"; exit 1; }
echo "  [PASS] an unknown mask reads as own storage: the caller is rejected against both interfaces"


# ── Test 49: a pointer into this frame handed to an imported callee whose store mask is unknown ──
# The caught-side canary for the interface path, and the shape `scripts/mutation_incremental.list`
# records: the callee's *summary* says it stores nothing, so a caller that passes a pointer to its own
# stack storage is accepted; an interface without that summary leaves the mask unknown, the verifier
# assumes the callee stores every pointer it is handed into long-lived memory, and the same caller is
# rejected. A mutation that drops the unknown branch (an unknown callee assumed to store nothing)
# accepts the stale compile, which is what makes this test the canary.
echo "49. Testing that an unknown store mask warns about a stack pointer handed to an imported callee..."
CAN_DIR="$WORK_DIR/iface_canary"
rm -rf "$CAN_DIR"
cankey=$(printf '%s' "${CAN_DIR#"$REPO/"}/lib" | sed 's|/|%2F|g')
mkdir -p "$CAN_DIR/stale" "$CAN_DIR/omit"
cat > "$CAN_DIR/lib.zrl" <<'ZEOF'
pub fn look(p: *i32) -> i32 {
    return 7;
}
ZEOF
cat > "$CAN_DIR/main.zrl" <<'ZEOF'
import "lib.zrl";

fn main() -> i32 {
    let x: i32 = 5;
    let a = lib::look(&x as *i32);
    return a - 7;
}
ZEOF
"$ZORIL_CC" -c -I "$CAN_DIR" --write-interface "$CAN_DIR/$cankey.zri" -o "$CAN_DIR/lib.zil" "$CAN_DIR/lib.zrl"
grep -q '^#\[summary(' "$CAN_DIR/$cankey.zri" || { echo "FAIL: the fresh interface carries no #[summary] to strip"; exit 1; }
grep -v '^#\[summary(' "$CAN_DIR/$cankey.zri" > "$CAN_DIR/stale/$cankey.zri"
printf '// zri-module: %s/lib.zrl\n' "$CAN_DIR/lib" > "$CAN_DIR/omit/$cankey.zri"
set +e
"$ZORIL_CC" -c -I "$CAN_DIR" --require-interface --iface-dir "$CAN_DIR/omit" -o "$CAN_DIR/omit.zil" "$CAN_DIR/main.zrl" > "$CAN_DIR/omit.log" 2>&1
can_omit_rc=$?
"$ZORIL_CC" -c -I "$CAN_DIR" --require-interface --iface-dir "$CAN_DIR" -o "$CAN_DIR/fresh.zil" "$CAN_DIR/main.zrl" > "$CAN_DIR/fresh.log" 2>&1
can_fresh_rc=$?
"$ZORIL_CC" -c -I "$CAN_DIR" --require-interface --iface-dir "$CAN_DIR/stale" -o "$CAN_DIR/stale.zil" "$CAN_DIR/main.zrl" > "$CAN_DIR/stale.log" 2>&1
can_stale_rc=$?
set -e
[ "$can_omit_rc" -ne 0 ] || { echo "FAIL: an interface holding none of the caller's functions was accepted - the interface is not being read"; exit 1; }
[ "$can_fresh_rc" -eq 0 ] || { echo "FAIL: the caller was rejected against its own fresh interface"; exit 1; }
[ "$can_stale_rc" -ne 0 ] || { echo "FAIL: an unknown store mask accepted a pointer to this frame's stack storage"; exit 1; }
grep -qE 'region escape|stashes local stack pointer|stores a pointer to local stack storage' "$CAN_DIR/stale.log" || { echo "FAIL: expected a region-escape diagnostic for the stale interface"; exit 1; }
echo "  [PASS] an unknown store mask rejects a stack pointer the summary would have allowed (fresh: accepted, stale: rejected)"


# ── Test 50: --require-interface makes a missing interface an error, and -v says so ──
# The flag exists because the fallback is silent: with `--iface-dir DIR` and no interface at
# `DIR/<encoded key>.zri`, the compiler parses the source instead, so a test that means to compile against
# an interface can compile against the source and pass. Both halves are pinned here, including the path
# that was looked up, which is the part the generic "could not find module" would have hidden.
echo "50. Testing that --require-interface errors on a missing interface, and -v notes the fall back..."
RI_DIR="$WORK_DIR/require_iface"
rm -rf "$RI_DIR"
rikkey=$(printf '%s' "${RI_DIR#"$REPO/"}/lib" | sed 's|/|%2F|g')
mkdir -p "$RI_DIR/empty"
cat > "$RI_DIR/lib.zrl" <<'ZEOF'
pub fn look(p: *i32) -> i32 { return 7; }
ZEOF
cat > "$RI_DIR/main.zrl" <<'ZEOF'
import "lib.zrl";
fn main() -> i32 { let x: i32 = 5; return lib::look(&x as *i32) - 7; }
ZEOF
set +e
"$ZORIL_CC" -c -I "$RI_DIR" --require-interface --iface-dir "$RI_DIR/empty" -o "$RI_DIR/req.zil" "$RI_DIR/main.zrl" > "$RI_DIR/req.log" 2>&1
ri_req_rc=$?
"$ZORIL_CC" -c -I "$RI_DIR" -v --iface-dir "$RI_DIR/empty" -o "$RI_DIR/verb.zil" "$RI_DIR/main.zrl" > "$RI_DIR/verb.log" 2>&1
ri_verb_rc=$?
"$ZORIL_CC" -c -I "$RI_DIR" --write-interface "$RI_DIR/$rikkey.zri" -o "$RI_DIR/lib.zil" "$RI_DIR/lib.zrl" > "$RI_DIR/lib.log" 2>&1
"$ZORIL_CC" -c -I "$RI_DIR" --require-interface --iface-dir "$RI_DIR" -o "$RI_DIR/ok.zil" "$RI_DIR/main.zrl" > "$RI_DIR/ok.log" 2>&1
ri_ok_rc=$?
set -e
[ "$ri_req_rc" -ne 0 ] || { echo "FAIL: --require-interface accepted an import with no interface"; exit 1; }
grep -q "no interface for module" "$RI_DIR/req.log" || { echo "FAIL: expected a no-interface diagnostic"; exit 1; }
grep -q "$rikkey" "$RI_DIR/req.log" || { echo "FAIL: the diagnostic does not name the path that was looked up"; exit 1; }
[ "$ri_verb_rc" -eq 0 ] || { echo "FAIL: -v should note the fall back, not fail the compile"; exit 1; }
grep -q "note: no interface for module" "$RI_DIR/verb.log" || { echo "FAIL: -v printed no note about the fall back"; exit 1; }
grep -q "$rikkey" "$RI_DIR/verb.log" || { echo "FAIL: the -v note does not name the path that was looked up"; exit 1; }
[ "$ri_ok_rc" -eq 0 ] || { echo "FAIL: the caller was rejected with the interface present"; exit 1; }
echo "  [PASS] a missing interface errors under --require-interface (named path) and is only a note under -v"


# ── Test 51: a method whose impl is in a module this TU cannot import ──
# Methods go with their type, so a whole-program build finds `helper` in `provider.zrl`'s `impl S`.
# `-c` sees one module and its imports, and `decl.zrl` cannot import `provider.zrl` (which imports
# it), so the call is rejected - with a note that names the limit, because the bare "no field
# 'helper' on 'S'" reads as a misspelling and cost a session to place when it was `zbuild` failing
# on `src/driver/state.zrl`. Both halves are pinned: the whole-program build accepts the same three
# files. KNOWN_ISSUES.md §4 documents the limit; removing it (compilation groups) is planned.
echo "51. Testing that -c says why a method whose impl is outside the TU is not visible..."
IM_DIR="$WORK_DIR/impl_out_of_tu"
rm -rf "$IM_DIR"
mkdir -p "$IM_DIR"
cat > "$IM_DIR/decl.zrl" <<'ZEOF'
pub struct S { pub a: i32 }

impl S {
    pub fn local(self: &S) -> i32 { return self.helper(); }
}
ZEOF
cat > "$IM_DIR/provider.zrl" <<'ZEOF'
import "decl.zrl";
use decl::S;

impl S {
    pub fn helper(self: &S) -> i32 { return self.a + 1; }
}
ZEOF
cat > "$IM_DIR/main.zrl" <<'ZEOF'
import "decl.zrl";
import "provider.zrl";
use decl::S;

fn main() -> i32 {
    let s = S { a: 1 };
    return s.local() - 2;
}
ZEOF
"$ZORIL_CC" -I "$IM_DIR" --emit-zil -o "$IM_DIR/all.zil" "$IM_DIR/main.zrl" > "$IM_DIR/all.log" 2>&1 || { echo "FAIL: the whole-program build rejected the same three files"; cat "$IM_DIR/all.log"; exit 1; }
set +e
"$ZORIL_CC" -c -I "$IM_DIR" --emit-zil -o "$IM_DIR/decl.zil" "$IM_DIR/decl.zrl" > "$IM_DIR/decl.log" 2>&1
im_rc=$?
set -e
[ "$im_rc" -ne 0 ] || { echo "FAIL: -c accepted a call to a method whose impl is outside the TU"; exit 1; }
grep -q "error: no field 'helper' on '&S'" "$IM_DIR/decl.log" || { echo "FAIL: expected the unknown-field error for the out-of-TU method:"; cat "$IM_DIR/decl.log"; exit 1; }
grep -q 'note: under -c only the target module and the modules it imports are visible: an `impl S` in another module is not' "$IM_DIR/decl.log" || { echo "FAIL: the note explaining the limit is missing:"; cat "$IM_DIR/decl.log"; exit 1; }
echo "  [PASS] -c rejects an out-of-TU method with a note naming the limit, and the whole-program build accepts the same files"


# ── Test 52: an exported declaration may name a private type of its own module ──
# The reduced case of the interface bug: `entry.zrl` has a private `struct Entry`
# inside `pub struct Table`, and its interface names that type, so an importer resolves `Table`
# without being able to name `Entry`. It runs the fixture in
# tests/incremental/private_type_in_public_struct/, which stayed unwired while the task's own
# outcome was undecided; a whole-program build and zbuild must agree, so both are run here.
echo "52. Testing that an interface declares the private types its exported declarations name..."
PT_DIR="$WORK_DIR/private_type_in_struct"
rm -rf "$PT_DIR"
mkdir -p "$PT_DIR"
cp "$REPO"/tests/incremental/private_type_in_public_struct/*.zrl "$PT_DIR/"
"$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --cache-dir "$PT_DIR/.c" -I "stdlib=$REPO/stdlib" -o "$PT_DIR/app" "$PT_DIR/zmain.zrl" > "$PT_DIR/zbuild.log" 2>&1 || { echo "FAIL: zbuild rejected the fixture:"; cat "$PT_DIR/zbuild.log"; exit 1; }
set +e
"$PT_DIR/app"
pt_rc=$?
set -e
[ "$pt_rc" -eq 0 ] || { echo "FAIL: the zbuild-built fixture exited $pt_rc, expected 0"; exit 1; }
"$ZORIL_CC" -I "stdlib=$REPO/stdlib" -I "$PT_DIR" --emit-zil -o "$PT_DIR/all.zil" "$PT_DIR/zmain.zrl" > "$PT_DIR/all.log" 2>&1 || { echo "FAIL: the whole-program build rejected the same files:"; cat "$PT_DIR/all.log"; exit 1; }
echo "  [PASS] zbuild and the whole-program build both accept a public declaration naming a private type"


# ── Test 53: separate compilation against string.zri calling [u8] methods on a stack-array slice ──
echo "53. Testing separate compilation against string.zri calling [u8] methods on a stack-array slice..."
SI_DIR="$WORK_DIR/slice_zri_summary"
rm -rf "$SI_DIR"
mkdir -p "$SI_DIR/iface" "$SI_DIR/src"
"$ZORIL_CC" -c -I "stdlib=$REPO/stdlib" --emit-interface "$REPO/stdlib/string.zrl" -o "$SI_DIR/iface/stdlib%2Fstring.zri" > "$SI_DIR/string_zri.log" 2>&1 || { echo "FAIL: emitting string.zri failed:"; cat "$SI_DIR/string_zri.log"; exit 1; }
grep -q '#\[summary(' "$SI_DIR/iface/stdlib%2Fstring.zri" || { echo "FAIL: string.zri has no #[summary] annotations:"; cat "$SI_DIR/iface/stdlib%2Fstring.zri"; exit 1; }

cat > "$SI_DIR/src/consumer.zrl" <<'ZEOF'
import "string.zrl";

fn main() -> i32 {
    let mut buf: [u8; 5] = [104 as u8, 101 as u8, 108 as u8, 108 as u8, 111 as u8];
    let s: [u8] = &buf;
    if !s.starts_with("he") { return 1; }
    if !s.ends_with("lo") { return 2; }
    let sub = s.sub(1 as usize, 3 as usize);
    if sub.len != 3 as usize { return 3; }
    return 0;
}
ZEOF

"$ZORIL_CC" -c --iface-dir "$SI_DIR/iface" -I "stdlib=$REPO/stdlib" --interproc-summary --emit-zil -o "$SI_DIR/consumer.zil" "$SI_DIR/src/consumer.zrl" > "$SI_DIR/consumer.log" 2>&1 || { echo "FAIL: compiling consumer.zrl against string.zri failed:"; cat "$SI_DIR/consumer.log"; exit 1; }

# Borrow escape check: verify that attempting to escape the slice borrowed from stack array is caught even with .zri
cat > "$SI_DIR/src/escape.zrl" <<'ZEOF'
import "string.zrl";

fn main() -> i32 {
    let mut outer: [u8] = "";
    {
        let mut buf: [u8; 5] = [104 as u8, 101 as u8, 108 as u8, 108 as u8, 111 as u8];
        let s: [u8] = &buf;
        outer = s.sub(0 as usize, 2 as usize);
    }
    return outer.len as i32;
}
ZEOF

set +e
"$ZORIL_CC" -c --iface-dir "$SI_DIR/iface" -I "stdlib=$REPO/stdlib" --interproc-summary --emit-zil -o "$SI_DIR/escape.zil" "$SI_DIR/src/escape.zrl" > "$SI_DIR/escape.log" 2>&1
esc_rc=$?
set -e
[ "$esc_rc" -ne 0 ] || { echo "FAIL: expected escape of stack array slice through string.zri to fail borrow check"; exit 1; }
grep -q "error: cannot let 'buf' go out of scope while it is still borrowed" "$SI_DIR/escape.log" || { echo "FAIL: expected borrow escape error on buf:"; cat "$SI_DIR/escape.log"; exit 1; }

# Whole-program execution test to confirm runtime behavior
"$ZORIL_CC" -I "stdlib=$REPO/stdlib" --emit-zil -o "$SI_DIR/full.zil" "$SI_DIR/src/consumer.zrl" > "$SI_DIR/full.log" 2>&1 || { echo "FAIL: whole-program emit-zil failed:"; cat "$SI_DIR/full.log"; exit 1; }
"$ZILC_CC" "$SI_DIR/full.zil" "$SI_DIR/full.ssa"
"$BACKEND_BIN" -o "$SI_DIR/full.s" "$SI_DIR/full.ssa"
"$ASSEMBLER_BIN" -o "$SI_DIR/full.o" "$SI_DIR/full.s"
"$LINKER_BIN" -o "$SI_DIR/consumer_bin" build/runtime.o "$SI_DIR/full.o"
set +e
"$SI_DIR/consumer_bin"
app_rc=$?
set -e
[ "$app_rc" -eq 0 ] || { echo "FAIL: consumer_bin exited $app_rc, expected 0"; exit 1; }
echo "  [PASS] compiling against string.zri preserves [u8] method summaries, respects stack borrow bounds, and executes cleanly"


# ── Test 54: a project's own `stdlib/` directory is not the standard library ──
echo "54. Testing that standard-library identity is designated, not inferred from a directory name..."
# The arena epoch exemption is the standard library's own contract. A project used to get it for
# free by naming a directory `stdlib` - either a project root's `stdlib/` (the old
# `<project root>/stdlib/` rule) or a bare `-I <dir>/stdlib` root (the old basename rule). Both are
# ordinary directories now: only `-I stdlib=<dir>` (or the compiler's own installation) designates
# standard library code (doc/spec/modular_compilation.md). This is the separate-compilation path
# to the rule, so it covers the interface round trip as well: the fake module is compiled on its
# own and read back from the `.zri` zbuild wrote.
SD_DIR="$WORK_DIR/spoof_stdlib_dir"
rm -rf "$SD_DIR"
mkdir -p "$SD_DIR/project/stdlib" "$SD_DIR/project/lib"
# The fake module lives in the tree, so the shape this rejects is written down once:
# tests/error_reporting/include/fake_stdlib/stdlib/mylib.zrl is a `<project root>/stdlib/` tree
# holding a user `Arena`, exactly what the old basename rule trusted.
cp tests/error_reporting/include/fake_stdlib/stdlib/mylib.zrl "$SD_DIR/project/stdlib/mylib.zrl"
cp tests/error_reporting/include/fake_stdlib/stdlib/mylib.zrl "$SD_DIR/project/lib/mylib.zrl"
for variant in stdlib lib; do
    cat > "$SD_DIR/project/main_$variant.zrl" <<ZEOF
import "$variant/mylib.zrl";
import "vec.zrl";
use mylib::{Arena, ArenaMark};
use vec::Vec;

fn main() -> i32 {
    let mut a = Arena { v: Vec::<u64>.new() };
    let mut i = 0 as u64;
    while i < 64 { a.v.push(7); i = i + 1; }
    let s = a.v.as_slice();
    let m = a.mark();
    a.reset_to(m);
    let mut b = Vec::<u64>.new();
    let mut j = 0 as u64;
    while j < 64 { b.push(99); j = j + 1; }
    return s[0] as i32;
}
ZEOF
    set +e
    ( cd "$SD_DIR/project" && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --cache-dir "$SD_DIR/project/.c_$variant" --root . -I "stdlib=$REPO/stdlib" -o "$SD_DIR/project/app_$variant" "main_$variant.zrl" > "$SD_DIR/build_$variant.log" 2>&1 )
    sd_rc=$?
    set -e
    [ "$sd_rc" -ne 0 ] || { echo "FAIL (54): a $variant/ directory was trusted as the standard library:"; cat "$SD_DIR/build_$variant.log"; exit 1; }
    grep -q "cannot mutably borrow 'a' while it is already borrowed" "$SD_DIR/build_$variant.log" || { echo "FAIL (54): expected the fake reset_to to collide with the live slice ($variant variant):"; cat "$SD_DIR/build_$variant.log"; exit 1; }
done
# The interface the fake module's own compile wrote carries no standard-library provenance, which
# is what makes the consumer above reject it rather than re-deriving trust from `stdlib/mylib.zrl`.
"$ZORIL_CC" -c -I "stdlib=$REPO/stdlib" --emit-interface "$SD_DIR/project/stdlib/mylib.zrl" -o "$SD_DIR/mylib.zri" > "$SD_DIR/iface.log" 2>&1 || { echo "FAIL (54): emitting the fake module's interface failed:"; cat "$SD_DIR/iface.log"; exit 1; }
if grep -q '^// zri-stdlib: 1' "$SD_DIR/mylib.zri"; then
    echo "FAIL (54): a project module's interface claimed standard-library provenance:"; cat "$SD_DIR/mylib.zri"; exit 1
fi
# ... and the standard library's own interface does carry it, or a consumer of `stdlib/mem.zri`
# would lose the epoch exemption.
"$ZORIL_CC" -c -I "stdlib=$REPO/stdlib" --emit-interface "$REPO/stdlib/mem.zrl" -o "$SD_DIR/mem.zri" > "$SD_DIR/mem_iface.log" 2>&1 || { echo "FAIL (54): emitting mem.zri failed:"; cat "$SD_DIR/mem_iface.log"; exit 1; }
grep -q '^// zri-stdlib: 1' "$SD_DIR/mem.zri" || { echo "FAIL (54): stdlib/mem.zri does not record standard-library provenance:"; head -3 "$SD_DIR/mem.zri"; exit 1; }
echo "  [PASS] 54: a project's stdlib/ and lib/ directories are ordinary roots, and provenance travels with the interface"


# ── Test 55: a call through a value ties the result to its arguments' storage ──
# `storage_facts` used to answer an indirect call with nothing: no `ret_storage` bits, so the
# interface said the result points into no argument's own storage and an importer treated a
# borrow of a local as derived - exempt at that local's scope end. The ZIR side already reads a
# `CallPtr` as every argument's own storage (Unified Solution B); this is the `.zri` half, found
# while auditing the fail-closed inventory (doc/SAFETY.md §4.4).
echo "55. Testing that a call through a value ties the result to its arguments' storage..."
TI_DIR="$WORK_DIR/indirect_ret_ties"
rm -rf "$TI_DIR"
mkdir -p "$TI_DIR"
touch "$TI_DIR/.zoril-root"
cat > "$TI_DIR/lib.zrl" <<'ZEOF'
pub fn id(p: &i32) -> &i32 { return p; }
pub fn pick(f: fn(&i32) -> &i32, p: &i32) -> &i32 { return f(p); }
ZEOF
cat > "$TI_DIR/main.zrl" <<'ZEOF'
import "lib.zrl";
use lib::{id, pick};

pub fn main() -> i32 {
    let mut r: &i32 = &0;
    {
        let x: i32 = 5;
        r = pick(id, &x);
    }
    return *r;
}
ZEOF
set +e
(cd "$TI_DIR" && "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_CC" --cache-dir .c -o bin main.zrl > build.log 2>&1)
ti_rc=$?
set -e
[ "$ti_rc" -ne 0 ] || { echo "FAIL (55): an indirect call's result was read as pointing into nothing, so the local's scope end was accepted:"; cat "$TI_DIR/build.log"; exit 1; }
grep -q "cannot let 'x' go out of scope while it is still borrowed" "$TI_DIR/build.log" || { echo "FAIL (55): expected the block-scope diagnostic:"; cat "$TI_DIR/build.log"; exit 1; }
TI_ZRI=$(grep -rl "zri-module: lib" "$TI_DIR/.c")
# Both `f` and `p` can hold a reference and the body's only return is `f(p)`: the result may
# point into either argument's own storage, so the mask is both bits. Before the fix it was 0,
# which is the "nothing escapes" reading a missing summary must not produce.
grep -B1 "fn pick" "$TI_ZRI" | grep -q "storage = 3" || { echo "FAIL (55): pick's interface does not tie the indirect result to its arguments:"; grep -B1 "fn pick" "$TI_ZRI"; exit 1; }
echo "  [PASS] 55: an indirect call's result inherits its arguments' own storage across the interface"


echo "PASS: all incremental compilation tests passed."


