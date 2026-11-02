#!/bin/sh
# scripts/test_safety_matrix_cross_module.sh — Cross-Module Safety Matrix Verification
#
# Verifies that every memory-safety guarantee from the 28 safety matrix probes
# survives module boundaries (.zri interfaces and separate compilation).
#
# Probes that involve function calls are split into a library module (.zrl -> .zri + .o)
# and a caller module (.zrl consuming only .zri).
# Probes that cannot be split are documented with the technical reason.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/scripts/env.sh"

ZORIL="$REPO_ROOT/build/zoril"
ZILC="$REPO_ROOT/build/zilc"
RUNTIME_O="$REPO_ROOT/build/runtime.o"

if [ ! -f "$ZORIL" ] || [ ! -f "$ZILC" ]; then
    echo "Error: build/zoril and build/zilc must be built first." >&2
    exit 1
fi

TMP_DIR="$(mktemp -d /tmp/cross_module_safety_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

PASSED=0
TOTAL=0
TF="${TIMEOUT_FOREGROUND:-}"

check() {
    name="$1"
    observed="$2"
    expected="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$observed" = "$expected" ]; then
        printf '  [PASS] %-42s -> %-20s (expected: %s)\n' "$name" "$observed" "$expected"
        PASSED=$((PASSED + 1))
    else
        printf '  [FAIL] %-42s -> %-20s (expected: %s)\n' "$name" "$observed" "$expected"
    fi
}

echo "=== Running Cross-Module Safety Matrix Probes ==="

# ── Probe 02: Use after move (POD) across module boundary ────────────────────
cat > "$TMP_DIR/probe02_lib.zrl" << 'EOF'
pub struct Point { pub x: i32, pub y: i32 }
pub fn take_point(p: Point) -> i32 { return p.x; }
EOF
cat > "$TMP_DIR/probe02_caller.zrl" << 'EOF'
import "probe02_lib.zrl";
use probe02_lib::{Point, take_point};
fn main() -> i32 {
    let p = Point { x: 1, y: 2 };
    let a = take_point(p);
    return p.y - 2;
}
EOF
"$ZORIL" --emit-interface -o "$TMP_DIR/probe02_lib.zri" "$TMP_DIR/probe02_lib.zrl" >/dev/null 2>&1
"$ZORIL" -c -o "$TMP_DIR/probe02_lib.zil" "$TMP_DIR/probe02_lib.zrl" >/dev/null 2>&1
"$ZILC" "$TMP_DIR/probe02_lib.zil" "$TMP_DIR/probe02_lib.ssa" >/dev/null 2>&1
"$BACKEND_BIN" -o "$TMP_DIR/probe02_lib.s" "$TMP_DIR/probe02_lib.ssa" >/dev/null 2>&1
"$ASSEMBLER_BIN" -o "$TMP_DIR/probe02_lib.o" "$TMP_DIR/probe02_lib.s" >/dev/null 2>&1
rm -f "$TMP_DIR/probe02_lib.zrl"

res=0
"$ZORIL" -c -I "$TMP_DIR" --emit-zil -o "$TMP_DIR/probe02_caller.zil" "$TMP_DIR/probe02_caller.zrl" >/dev/null 2>&1 || res=$?
if [ $res -eq 0 ]; then
    "$ZILC" "$TMP_DIR/probe02_caller.zil" "$TMP_DIR/probe02_caller.ssa" >/dev/null 2>&1
    "$BACKEND_BIN" -o "$TMP_DIR/probe02_caller.s" "$TMP_DIR/probe02_caller.ssa" >/dev/null 2>&1
    "$ASSEMBLER_BIN" -o "$TMP_DIR/probe02_caller.o" "$TMP_DIR/probe02_caller.s" >/dev/null 2>&1
    "$LINKER_BIN" -o "$TMP_DIR/probe02_bin" "$TMP_DIR/probe02_caller.o" "$TMP_DIR/probe02_lib.o" "$RUNTIME_O" >/dev/null 2>&1
    rc=0; ( run_with_timeout $TF -k 1s 5s "$TMP_DIR/probe02_bin" >/dev/null 2>&1 ) || rc=$?
    obs="exit ($rc)"
    [ $rc -eq 0 ] && obs="accept (exit 0)"
else
    obs="compile error"
fi
check "Probe 02: Use after move (POD) [cross-mod]" "$obs" "accept (exit 0)"

# ── Probe 07: Dangling stack ptr — via callee (rejected: stash's signature ties its result to p) ─
cat > "$TMP_DIR/probe07_lib.zrl" << 'EOF'
pub struct S { pub a: i32 }
pub fn stash(p: *mut S) -> *mut S { return p; }
EOF
cat > "$TMP_DIR/probe07_caller.zrl" << 'EOF'
import "probe07_lib.zrl";
use probe07_lib::{S, stash};
fn leak() -> *mut S {
    let mut s = S { a: 42 };
    return stash(&mut s);
}
fn main() -> i32 {
    let p = leak();
    if unsafe { (*p).a } != 42 { return 1; }
    return 0;
}
EOF
"$ZORIL" --emit-interface -o "$TMP_DIR/probe07_lib.zri" "$TMP_DIR/probe07_lib.zrl" >/dev/null 2>&1
"$ZORIL" -c -o "$TMP_DIR/probe07_lib.zil" "$TMP_DIR/probe07_lib.zrl" >/dev/null 2>&1
"$ZILC" "$TMP_DIR/probe07_lib.zil" "$TMP_DIR/probe07_lib.ssa" >/dev/null 2>&1
"$BACKEND_BIN" -o "$TMP_DIR/probe07_lib.s" "$TMP_DIR/probe07_lib.ssa" >/dev/null 2>&1
"$ASSEMBLER_BIN" -o "$TMP_DIR/probe07_lib.o" "$TMP_DIR/probe07_lib.s" >/dev/null 2>&1
rm -f "$TMP_DIR/probe07_lib.zrl"

res=0
"$ZORIL" -c -I "$TMP_DIR" --emit-zil -o "$TMP_DIR/probe07_caller.zil" "$TMP_DIR/probe07_caller.zrl" >/dev/null 2>&1 || res=$?
if [ $res -eq 0 ]; then
    "$ZILC" "$TMP_DIR/probe07_caller.zil" "$TMP_DIR/probe07_caller.ssa" >/dev/null 2>&1
    "$BACKEND_BIN" -o "$TMP_DIR/probe07_caller.s" "$TMP_DIR/probe07_caller.ssa" >/dev/null 2>&1
    "$ASSEMBLER_BIN" -o "$TMP_DIR/probe07_caller.o" "$TMP_DIR/probe07_caller.s" >/dev/null 2>&1
    "$LINKER_BIN" -o "$TMP_DIR/probe07_bin" "$TMP_DIR/probe07_caller.o" "$TMP_DIR/probe07_lib.o" "$RUNTIME_O" >/dev/null 2>&1
    rc=0; ( run_with_timeout $TF -k 1s 5s "$TMP_DIR/probe07_bin" >/dev/null 2>&1 ) || rc=$?
    obs="exit ($rc)"
    [ $rc -eq 0 ] && obs="accept (exit 0)"
else
    obs="compile error"
fi
check "Probe 07: Dangling stack ptr (callee) [cross-mod]" "$obs" "compile error"

# ── Probe 07 (negative test): Dangling stack ptr rejected via --interproc-summary ───
output=$("$ZORIL" -I "$TMP_DIR" --interproc-summary --emit-zil -o /dev/null "$TMP_DIR/probe07_caller.zrl" 2>&1 || true)
if echo "$output" | grep -Fq "error: region escape: returning a pointer to local stack storage"; then
    obs="compile error"
else
    obs="accepted"
fi
check "Probe 07 [interproc-summary]: Dangling stack [cross-mod]" "$obs" "compile error"

# ── Probe 92: Reference into a local's storage returned through an imported method ─
# get's .zri summary says its result points into self's storage (storage = 1); at's does
# not (it points where self.data points), so only the first is a dangling return.
cat > "$TMP_DIR/probe92_lib.zrl" << 'EOF'
pub struct C { pub v: i32, pub data: *mut i32 }
impl C {
    pub fn get(self: &C) -> &i32 { return &self.v; }
    pub fn at(self: &C) -> &i32 { return unsafe { &*self.data }; }
}
EOF
cat > "$TMP_DIR/probe92_caller.zrl" << 'EOF'
import "probe92_lib.zrl";
use probe92_lib::C;
fn leak() -> &i32 { let c = C { v: 7, data: 0 as *mut i32 }; return c.get(); }
fn main() -> i32 { return *leak(); }
EOF
cat > "$TMP_DIR/probe92_buffer.zrl" << 'EOF'
import "probe92_lib.zrl";
use probe92_lib::C;
static mut CELL: i32 = 7;
fn through() -> &i32 { let c = C { v: 0, data: unsafe { &mut CELL as *mut i32 } }; return c.at(); }
fn main() -> i32 { return *through() - 7; }
EOF
"$ZORIL" --emit-interface -o "$TMP_DIR/probe92_lib.zri" "$TMP_DIR/probe92_lib.zrl" >/dev/null 2>&1
rm -f "$TMP_DIR/probe92_lib.zrl"
obs="accepted"
"$ZORIL" -c -I "$TMP_DIR" -o "$TMP_DIR/probe92_caller.zil" "$TMP_DIR/probe92_caller.zrl" >/dev/null 2>&1 || obs="compile error"
check "Probe 92: Ref into local's storage via imported method [cross-mod]" "$obs" "compile error"
obs="compile error"
"$ZORIL" -c -I "$TMP_DIR" -o "$TMP_DIR/probe92_buffer.zil" "$TMP_DIR/probe92_buffer.zrl" >/dev/null 2>&1 && obs="accepted"
check "Probe 92 (negative): Ref into a referenced buffer via imported method [cross-mod]" "$obs" "accepted"

# ── Probe 09: OOB slice read across module boundary ─────────────────────────
cat > "$TMP_DIR/probe09_lib.zrl" << 'EOF'
pub fn read_slice(s: [u8]) -> i32 { return s[10] as i32; }
EOF
cat > "$TMP_DIR/probe09_caller.zrl" << 'EOF'
import "probe09_lib.zrl";
use probe09_lib::read_slice;
fn main() -> i32 {
    let a = [1 as u8, 2 as u8, 3 as u8];
    return read_slice(&a);
}
EOF
"$ZORIL" --emit-interface -o "$TMP_DIR/probe09_lib.zri" "$TMP_DIR/probe09_lib.zrl" >/dev/null 2>&1
"$ZORIL" -c -o "$TMP_DIR/probe09_lib.zil" "$TMP_DIR/probe09_lib.zrl" >/dev/null 2>&1
"$ZILC" "$TMP_DIR/probe09_lib.zil" "$TMP_DIR/probe09_lib.ssa" >/dev/null 2>&1
"$BACKEND_BIN" -o "$TMP_DIR/probe09_lib.s" "$TMP_DIR/probe09_lib.ssa" >/dev/null 2>&1
"$ASSEMBLER_BIN" -o "$TMP_DIR/probe09_lib.o" "$TMP_DIR/probe09_lib.s" >/dev/null 2>&1
rm -f "$TMP_DIR/probe09_lib.zrl"

res=0
"$ZORIL" -c -I "$TMP_DIR" --emit-zil -o "$TMP_DIR/probe09_caller.zil" "$TMP_DIR/probe09_caller.zrl" >/dev/null 2>&1 || res=$?
if [ $res -eq 0 ]; then
    "$ZILC" "$TMP_DIR/probe09_caller.zil" "$TMP_DIR/probe09_caller.ssa" >/dev/null 2>&1
    "$BACKEND_BIN" -o "$TMP_DIR/probe09_caller.s" "$TMP_DIR/probe09_caller.ssa" >/dev/null 2>&1
    "$ASSEMBLER_BIN" -o "$TMP_DIR/probe09_caller.o" "$TMP_DIR/probe09_caller.s" >/dev/null 2>&1
    "$LINKER_BIN" -o "$TMP_DIR/probe09_bin" "$TMP_DIR/probe09_caller.o" "$TMP_DIR/probe09_lib.o" "$RUNTIME_O" >/dev/null 2>&1
    rc=0; ( run_with_timeout $TF -k 1s 5s "$TMP_DIR/probe09_bin" >/dev/null 2>&1 ) || rc=$?
    obs="exit ($rc)"
    [ $rc -eq 134 ] && obs="trap (134)"
else
    obs="compile error"
fi
check "Probe 09: OOB slice read [cross-mod]" "$obs" "trap (134)"

# ── Probe 11: OOB slice write across module boundary ────────────────────────
cat > "$TMP_DIR/probe11_lib.zrl" << 'EOF'
pub fn write_slice(s: [mut u8]) { s[10] = 99 as u8; }
EOF
cat > "$TMP_DIR/probe11_caller.zrl" << 'EOF'
import "probe11_lib.zrl";
use probe11_lib::write_slice;
fn main() -> i32 {
    let mut a = [1 as u8, 2 as u8, 3 as u8];
    write_slice(&mut a);
    return 0;
}
EOF
"$ZORIL" --emit-interface -o "$TMP_DIR/probe11_lib.zri" "$TMP_DIR/probe11_lib.zrl" >/dev/null 2>&1
"$ZORIL" -c -o "$TMP_DIR/probe11_lib.zil" "$TMP_DIR/probe11_lib.zrl" >/dev/null 2>&1
"$ZILC" "$TMP_DIR/probe11_lib.zil" "$TMP_DIR/probe11_lib.ssa" >/dev/null 2>&1
"$BACKEND_BIN" -o "$TMP_DIR/probe11_lib.s" "$TMP_DIR/probe11_lib.ssa" >/dev/null 2>&1
"$ASSEMBLER_BIN" -o "$TMP_DIR/probe11_lib.o" "$TMP_DIR/probe11_lib.s" >/dev/null 2>&1
rm -f "$TMP_DIR/probe11_lib.zrl"

res=0
"$ZORIL" -c -I "$TMP_DIR" --emit-zil -o "$TMP_DIR/probe11_caller.zil" "$TMP_DIR/probe11_caller.zrl" >/dev/null 2>&1 || res=$?
if [ $res -eq 0 ]; then
    "$ZILC" "$TMP_DIR/probe11_caller.zil" "$TMP_DIR/probe11_caller.ssa" >/dev/null 2>&1
    "$BACKEND_BIN" -o "$TMP_DIR/probe11_caller.s" "$TMP_DIR/probe11_caller.ssa" >/dev/null 2>&1
    "$ASSEMBLER_BIN" -o "$TMP_DIR/probe11_caller.o" "$TMP_DIR/probe11_caller.s" >/dev/null 2>&1
    "$LINKER_BIN" -o "$TMP_DIR/probe11_bin" "$TMP_DIR/probe11_caller.o" "$TMP_DIR/probe11_lib.o" "$RUNTIME_O" >/dev/null 2>&1
    rc=0; ( run_with_timeout $TF -k 1s 5s "$TMP_DIR/probe11_bin" >/dev/null 2>&1 ) || rc=$?
    obs="exit ($rc)"
    [ $rc -eq 134 ] && obs="trap (134)"
else
    obs="compile error"
fi
check "Probe 11: OOB slice write [cross-mod]" "$obs" "trap (134)"

# ── Probe 23: Missing return across module boundary ─────────────────────────
cat > "$TMP_DIR/probe23_lib.zrl" << 'EOF'
pub fn f(x: i32) -> i32 { if x > 0 { return 42; } }
EOF
res=0
"$ZORIL" --emit-interface -o "$TMP_DIR/probe23_lib.zri" "$TMP_DIR/probe23_lib.zrl" >/dev/null 2>&1 || res=$?
obs="accept"
[ $res -ne 0 ] && obs="compile error"
check "Probe 23: Missing return [cross-mod lib]" "$obs" "compile error"

# ── Probe 25: Stack overflow (recursion) across module boundary ─────────────
cat > "$TMP_DIR/probe25_lib.zrl" << 'EOF'
pub fn rec(n: i64) -> i64 {
    if n == 0 as i64 { return 0 as i64; }
    return rec(n + 1 as i64) + 1 as i64;
}
EOF
cat > "$TMP_DIR/probe25_caller.zrl" << 'EOF'
import "probe25_lib.zrl";
use probe25_lib::rec;
fn main() -> i32 {
    return rec(1 as i64) as i32;
}
EOF
"$ZORIL" --emit-interface -o "$TMP_DIR/probe25_lib.zri" "$TMP_DIR/probe25_lib.zrl" >/dev/null 2>&1
"$ZORIL" -c -o "$TMP_DIR/probe25_lib.zil" "$TMP_DIR/probe25_lib.zrl" >/dev/null 2>&1
"$ZILC" "$TMP_DIR/probe25_lib.zil" "$TMP_DIR/probe25_lib.ssa" >/dev/null 2>&1
"$BACKEND_BIN" -o "$TMP_DIR/probe25_lib.s" "$TMP_DIR/probe25_lib.ssa" >/dev/null 2>&1
"$ASSEMBLER_BIN" -o "$TMP_DIR/probe25_lib.o" "$TMP_DIR/probe25_lib.s" >/dev/null 2>&1
rm -f "$TMP_DIR/probe25_lib.zrl"

res=0
"$ZORIL" -c -I "$TMP_DIR" --emit-zil -o "$TMP_DIR/probe25_caller.zil" "$TMP_DIR/probe25_caller.zrl" >/dev/null 2>&1 || res=$?
if [ $res -eq 0 ]; then
    "$ZILC" "$TMP_DIR/probe25_caller.zil" "$TMP_DIR/probe25_caller.ssa" >/dev/null 2>&1
    "$BACKEND_BIN" -o "$TMP_DIR/probe25_caller.s" "$TMP_DIR/probe25_caller.ssa" >/dev/null 2>&1
    "$ASSEMBLER_BIN" -o "$TMP_DIR/probe25_caller.o" "$TMP_DIR/probe25_caller.s" >/dev/null 2>&1
    "$LINKER_BIN" -o "$TMP_DIR/probe25_bin" "$TMP_DIR/probe25_caller.o" "$TMP_DIR/probe25_lib.o" "$RUNTIME_O" >/dev/null 2>&1
    rc=0; ( run_with_timeout $TF -k 1s 5s "$TMP_DIR/probe25_bin" >/dev/null 2>&1 ) || rc=$?
    obs="exit ($rc)"
    [ $rc -eq 139 ] && obs="fault (segv 139)"
else
    obs="compile error"
fi
check "Probe 25: Stack overflow [cross-mod]" "$obs" "fault (segv 139)"

# ── Encapsulation: a method without `pub` stays inside its module ─────────────
# The rule is the module boundary's, not the type's: `impl Counter` in any module is found for
# `c.m(..)` (surface_syntax.md §11.1.1), but a method without `pub` is nameable only from the
# module that declares it (§11.1.2), so the route through a private invariant keeper is closed
# across a boundary - and open inside the module, which the second half shows still works.
cat > "$TMP_DIR/encap_lib.zrl" << 'EOF'
pub struct Counter { pub n: i32 }
impl Counter {
    fn bump(self: &Counter) -> i32 { return self.n + 1; }
    pub fn bumped(self: &Counter) -> i32 { return self.bump(); }
}
EOF
"$ZORIL" -c -o "$TMP_DIR/encap_lib.zil" "$TMP_DIR/encap_lib.zrl" >/dev/null 2>&1
"$ZILC" "$TMP_DIR/encap_lib.zil" "$TMP_DIR/encap_lib.ssa" >/dev/null 2>&1
"$BACKEND_BIN" -o "$TMP_DIR/encap_lib.s" "$TMP_DIR/encap_lib.ssa" >/dev/null 2>&1
"$ASSEMBLER_BIN" -o "$TMP_DIR/encap_lib.o" "$TMP_DIR/encap_lib.s" >/dev/null 2>&1

cat > "$TMP_DIR/encap_caller.zrl" << 'EOF'
import "encap_lib.zrl";
use encap_lib::Counter;
fn main() -> i32 {
    let c = Counter { n: 1 };
    return c.bump();
}
EOF
res=0
"$ZORIL" -c -I "$TMP_DIR" --emit-zil -o "$TMP_DIR/encap_caller.zil" "$TMP_DIR/encap_caller.zrl" >/dev/null 2>&1 || res=$?
if [ $res -eq 0 ]; then obs="accepted"; else obs="compile error"; fi
check "Probe 29: Private method across modules" "$obs" "compile error"

cat > "$TMP_DIR/encap_ok.zrl" << 'EOF'
import "encap_lib.zrl";
use encap_lib::Counter;
fn main() -> i32 {
    let c = Counter { n: 1 };
    return c.bumped() - 2;
}
EOF
res=0
"$ZORIL" -c -I "$TMP_DIR" --emit-zil -o "$TMP_DIR/encap_ok.zil" "$TMP_DIR/encap_ok.zrl" >/dev/null 2>&1 || res=$?
if [ $res -eq 0 ]; then
    "$ZILC" "$TMP_DIR/encap_ok.zil" "$TMP_DIR/encap_ok.ssa" >/dev/null 2>&1
    "$BACKEND_BIN" -o "$TMP_DIR/encap_ok.s" "$TMP_DIR/encap_ok.ssa" >/dev/null 2>&1
    "$ASSEMBLER_BIN" -o "$TMP_DIR/encap_ok.o" "$TMP_DIR/encap_ok.s" >/dev/null 2>&1
    "$LINKER_BIN" -o "$TMP_DIR/encap_ok_bin" "$TMP_DIR/encap_ok.o" "$TMP_DIR/encap_lib.o" "$RUNTIME_O" >/dev/null 2>&1
    rc=0; ( run_with_timeout $TF -k 1s 5s "$TMP_DIR/encap_ok_bin" >/dev/null 2>&1 ) || rc=$?
    obs="exit ($rc)"
else
    obs="compile error"
fi
check "Probe 29: The module's own public entry point" "$obs" "exit (0)"

# ── Non-splittable probes accounting ─────────────────────────────────────────
echo "--- Probes evaluated as intra-procedural (cannot be split) ---"
for p in \
    "Probe 01: Use after move (local linear variable inside main())" \
    "Probe 03: Double drop (local variable drop in main())" \
    "Probe 04: Use after drop (local variable drop in main())" \
    "Probe 05: Dangling stack direct return (local variable inside callee)" \
    "Probe 06: Dangling stack cast return (local variable inside callee)" \
    "Probe 08: OOB array read (fixed-size array stack allocation in main())" \
    "Probe 10: OOB array write (fixed-size array stack allocation in main())" \
    "Probe 12: Raw-pointer indexing (local pointer arithmetic outside unsafe)" \
    "Probe 13: Forged pointer (int-to-ptr cast outside unsafe in main())" \
    "Probe 14: Null dereference (null pointer dereference in main())" \
    "Probe 15: Signed integer overflow (arithmetic evaluation in main())" \
    "Probe 16: Division by zero (arithmetic division in main())" \
    "Probe 17: Modulo by zero (arithmetic modulo in main())" \
    "Probe 18: Signed division overflow (arithmetic division in main())" \
    "Probe 19: Shift overflow (shift operation in main())" \
    "Probe 20: Narrowing integer cast (primitive cast in main())" \
    "Probe 21: Invalid enum tag (discriminant cast in main())" \
    "Probe 22: Uninitialized local (local variable in main())" \
    "Probe 24: Unaligned access (unaligned store outside unsafe in main())" \
    "Probe 26: Null function pointer (struct field invocation in main())" \
    "Probe 27: Type confusion (pointer reinterpretation in main())" \
    "Probe 28: Immutable reassign (local let reassignment in main())"; do
    printf '  [SKIP] %s\n' "$p"
done

echo ""
echo "$PASSED/$TOTAL cross-module safety matrix probes passed."
[ "$PASSED" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]
