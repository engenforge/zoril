#!/bin/sh
# scripts/test_incremental_equivalence.sh — Prove incremental builds match clean builds
# Executes a randomized/scripted edit sequence over a multi-module fixture and asserts
# byte-identical binary parity (cmp -s) between incremental and clean builds at every step.
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

. "$(dirname "$0")/env.sh"

# The tools under test come from the caller (test_incremental.sh passes the compiler it was given, so a
# mutation run checks the mutant here too), and every path is absolute, so the steps that cd into a
# fixture can use them as they are.
ZORIL_CC="${ZORIL_CC:-build/zoril}"
ZILC_BIN="${ZILC_BIN:-build/zilc}"
ZBUILD_BIN="${ZBUILD_BIN:-build/zbuild}"
[ -x "$ZBUILD_BIN" ] || make build/zbuild
case "$ZORIL_CC" in /*) ;; *) ZORIL_CC=$REPO/$ZORIL_CC ;; esac
case "$ZILC_BIN" in /*) ;; *) ZILC_BIN=$REPO/$ZILC_BIN ;; esac
case "$ZBUILD_BIN" in /*) ;; *) ZBUILD_BIN=$REPO/$ZBUILD_BIN ;; esac

ZB() {
    "$ZBUILD_BIN" --compiler "$ZORIL_CC" --zilc "$ZILC_BIN" --qbe "$BACKEND_BIN" \
        --runtime "$REPO/build/runtime.o" "$@"
}

# Under the caller's TR_WORK, like test_incremental.sh, so concurrent runs do not share fixtures.
EQ_BASE="${TR_WORK:-build/tests}/incremental"
case "$EQ_BASE" in /*) ;; *) EQ_BASE=$REPO/$EQ_BASE ;; esac
EQ_DIR="$EQ_BASE/equivalence"
rm -rf "$EQ_DIR"
mkdir -p "$EQ_DIR/inc" "$EQ_DIR/clean"

echo "=== Incremental vs Clean Build Equivalence Suite ==="

# check_equiv <step> <fixture_dir> [zbuild flags for the incremental build]
# Builds <fixture_dir>/inc incrementally and a copy from scratch, then compares binaries and exit
# codes. Returns 0 when equivalent, 1 otherwise (never aborts, so fault injection can expect failure).
check_equiv() {
    step_name="$1"
    fx="$2"
    flags="$3"
    mkdir -p "$fx/clean"
    touch "$fx/inc/.zoril-root" "$fx/clean/.zoril-root"

    # Both builds run from their own directory so module paths (and the object names `as` embeds
    # as FILE symbols for local symbols) are identical between the incremental and clean trees.
    # shellcheck disable=SC2086
    (cd "$fx/inc" && ZB $flags --cache-dir .cache -o bin main.zrl >/dev/null) || {
        echo "FAIL: [$step_name] incremental build failed"; return 1; }

    rm -rf "$fx/clean/.cache" "$fx/clean/"*.zrl
    find "$fx/inc" -name '*.zrl' | while read -r f; do
        rel="${f#$fx/inc/}"
        mkdir -p "$fx/clean/$(dirname "$rel")"
        cp "$f" "$fx/clean/$rel"
    done
    (cd "$fx/clean" && ZB --cache-dir .cache -o bin main.zrl >/dev/null) || {
        echo "FAIL: [$step_name] clean build failed"; return 1; }

    if ! cmp -s "$fx/inc/bin" "$fx/clean/bin"; then
        echo "FAIL: [$step_name] incremental and clean binaries are NOT byte-identical!"
        nm "$fx/inc/bin" > "$fx/inc.nm" 2>&1
        nm "$fx/clean/bin" > "$fx/clean.nm" 2>&1
        diff -u "$fx/inc.nm" "$fx/clean.nm" | head -20
        return 1
    fi

    set +e
    "$fx/inc/bin"
    inc_exit=$?
    "$fx/clean/bin"
    clean_exit=$?
    set -e
    if [ "$inc_exit" -ne "$clean_exit" ]; then
        echo "FAIL: [$step_name] exit code mismatch: inc=$inc_exit, clean=$clean_exit"
        return 1
    fi

    echo "  [OK] $step_name: byte-identical (exit $inc_exit)"
    return 0
}

assert_identical() {
    check_equiv "$1" "$EQ_DIR" "" || exit 1
}

# ── Step 0: Baseline Initial Multi-Module Fixture ────────────────────────────
cat << 'EOF' > "$EQ_DIR/inc/math.zrl"
pub fn math_calc(x: i64) -> i64 {
    return x * 2;
}
EOF

cat << 'EOF' > "$EQ_DIR/inc/util.zrl"
import "math.zrl";
use math::math_calc;
pub fn util_func(x: i64) -> i64 {
    return math_calc(x) + 1;
}
EOF

cat << 'EOF' > "$EQ_DIR/inc/main.zrl"
import "util.zrl";
use util::util_func;
pub fn main() -> i32 {
    let r = util_func(10);
    if r == 21 { return 0 as i32; }
    return 1 as i32;
}
EOF

assert_identical "Step 0: baseline initial multi-module build"

# Save baseline binary for Step 8 revert comparison
cp "$EQ_DIR/inc/bin" "$EQ_DIR/baseline_bin"

# ── Step 1: Body Edit (math.zrl body changed, signature unchanged) ───────────
cat << 'EOF' > "$EQ_DIR/inc/math.zrl"
pub fn math_calc(x: i64) -> i64 {
    let mut val: i64 = x;
    val = val * 2;
    return val;
}
EOF
assert_identical "Step 1: body edit in dependency (early cutoff)"

# ── Step 2: Signature Change (math.zrl gains argument, callers updated) ──────
cat << 'EOF' > "$EQ_DIR/inc/math.zrl"
pub fn math_calc(x: i64, factor: i64) -> i64 {
    return x * factor;
}
EOF
cat << 'EOF' > "$EQ_DIR/inc/util.zrl"
import "math.zrl";
use math::math_calc;
pub fn util_func(x: i64) -> i64 {
    return math_calc(x, 2) + 1;
}
EOF
assert_identical "Step 2: signature change in dependency"

# ── Step 3: Add Declaration (new pub function in math.zrl, used by main) ─────
cat << 'EOF' > "$EQ_DIR/inc/math.zrl"
pub fn math_calc(x: i64, factor: i64) -> i64 {
    return x * factor;
}
pub fn math_bonus(a: i64) -> i64 {
    return a + 100;
}
EOF
cat << 'EOF' > "$EQ_DIR/inc/main.zrl"
import "util.zrl";
import "math.zrl";
use math::math_bonus;
use util::util_func;
pub fn main() -> i32 {
    let r = util_func(10) + math_bonus(0);
    if r == 121 { return 0 as i32; }
    return 1 as i32;
}
EOF
assert_identical "Step 3: add declaration and call site"

# ── Step 4: Remove Declaration (remove math_bonus, revert main) ──────────────
cat << 'EOF' > "$EQ_DIR/inc/math.zrl"
pub fn math_calc(x: i64, factor: i64) -> i64 {
    return x * factor;
}
EOF
cat << 'EOF' > "$EQ_DIR/inc/main.zrl"
import "util.zrl";
use util::util_func;
pub fn main() -> i32 {
    let r = util_func(10);
    if r == 21 { return 0 as i32; }
    return 1 as i32;
}
EOF
assert_identical "Step 4: remove declaration"

# ── Step 5: Add Import (new module extra.zrl imported by main) ────────────────
cat << 'EOF' > "$EQ_DIR/inc/extra.zrl"
pub fn extra_val() -> i64 {
    return 50;
}
EOF
cat << 'EOF' > "$EQ_DIR/inc/main.zrl"
import "util.zrl";
import "extra.zrl";
use extra::extra_val;
use util::util_func;
pub fn main() -> i32 {
    let r = util_func(10) + extra_val();
    if r == 71 { return 0 as i32; }
    return 1 as i32;
}
EOF
assert_identical "Step 5: add import and new module"

# ── Step 6: Remove Import (remove extra.zrl from main) ────────────────────────
rm -f "$EQ_DIR/inc/extra.zrl"
cat << 'EOF' > "$EQ_DIR/inc/main.zrl"
import "util.zrl";
use util::util_func;
pub fn main() -> i32 {
    let r = util_func(10);
    if r == 21 { return 0 as i32; }
    return 1 as i32;
}
EOF
assert_identical "Step 6: remove import and delete module"

# ── Step 7: Rename (rename util_func -> util_compute) ─────────────────────────
cat << 'EOF' > "$EQ_DIR/inc/util.zrl"
import "math.zrl";
use math::math_calc;
pub fn util_compute(x: i64) -> i64 {
    return math_calc(x, 2) + 1;
}
EOF
cat << 'EOF' > "$EQ_DIR/inc/main.zrl"
import "util.zrl";
use util::util_compute;
pub fn main() -> i32 {
    let r = util_compute(10);
    if r == 21 { return 0 as i32; }
    return 1 as i32;
}
EOF
assert_identical "Step 7: rename declaration and callers"

# ── Step 8: Revert (revert back to Step 0 state) ──────────────────────────────
cat << 'EOF' > "$EQ_DIR/inc/math.zrl"
pub fn math_calc(x: i64) -> i64 {
    return x * 2;
}
EOF
cat << 'EOF' > "$EQ_DIR/inc/util.zrl"
import "math.zrl";
use math::math_calc;
pub fn util_func(x: i64) -> i64 {
    return math_calc(x) + 1;
}
EOF
cat << 'EOF' > "$EQ_DIR/inc/main.zrl"
import "util.zrl";
use util::util_func;
pub fn main() -> i32 {
    let r = util_func(10);
    if r == 21 { return 0 as i32; }
    return 1 as i32;
}
EOF
assert_identical "Step 8: revert all files to baseline state"

if ! cmp -s "$EQ_DIR/inc/bin" "$EQ_DIR/baseline_bin"; then
    echo "FAIL: [Step 8 Revert] binary does not match baseline binary after full revert!"
    exit 1
fi
echo "  [OK] Step 8 revert: binary is byte-identical to baseline binary from Step 0"

# ── Step 9: Delete Cache Recovery ────────────────────────────────────────────
rm -rf "$EQ_DIR/inc/.cache"
assert_identical "Step 9: delete .cache directory and recover"

# ── Step 10: Corrupted Manifest Line Recovery ─────────────────────────────────
# Corrupt manifest line by inserting garbage into hashes
TAB="$(printf '\t')"
sed "s/^math.zrl.*/math.zrl${TAB}0${TAB}1${TAB}corrupted_hash${TAB}bad_iface${TAB}.cache\/obj\/bad.o${TAB}/" "$EQ_DIR/inc/.cache/manifest.tsv" > "$EQ_DIR/inc/.cache/manifest.tsv.tmp" && mv "$EQ_DIR/inc/.cache/manifest.tsv.tmp" "$EQ_DIR/inc/.cache/manifest.tsv"
grep -q corrupted_hash "$EQ_DIR/inc/.cache/manifest.tsv" || { echo "FAIL: test did not corrupt the manifest row"; exit 1; }
assert_identical "Step 10: corrupted manifest line recovered cleanly"

# ── Step 11: Missing Cached .o Recovery ───────────────────────────────────────
# Delete one cached object file
rm -f "$EQ_DIR/inc/.cache/obj/"*math*
assert_identical "Step 11: missing cached .o recovered cleanly"

# ── Step 11b: Missing Cached Interface Recovery ───────────────────────────────
rm -f "$EQ_DIR/inc/.cache/iface/"*math*
assert_identical "Step 11b: missing cached interface recovered cleanly"

# ── Transitive layout fixture: main -> b -> c; main reads a field of c's struct via b ──────────
# An interface change in c must reach main even though main never imports c directly.
write_transitive_fixture() {
    fx_dir="$1"
    cat << EOF > "$fx_dir/inc/c.zrl"
pub struct S {
$2
    pub b: i64,
}
pub fn make_s() -> S {
    return S { $3 b: 2 };
}
EOF
    cat << 'EOF' > "$fx_dir/inc/b.zrl"
import "c.zrl";
use c::{S, make_s};
pub fn make() -> S {
    return make_s();
}
EOF
    cat << 'EOF' > "$fx_dir/inc/main.zrl"
import "b.zrl";
use b::make;
pub fn main() -> i32 {
    let s = make();
    return s.b as i32;
}
EOF
}

TX_DIR="$EQ_BASE/transitive"
rm -rf "$TX_DIR"
mkdir -p "$TX_DIR/inc"
write_transitive_fixture "$TX_DIR" "" ""
check_equiv "Transitive 0: baseline" "$TX_DIR" "" || exit 1
write_transitive_fixture "$TX_DIR" "    pub a: i64," "a: 1,"
check_equiv "Transitive 1: leading field inserted in c (main must rebuild)" "$TX_DIR" "" || exit 1
cat << 'EOF' >> "$TX_DIR/inc/c.zrl"
fn unused_private() -> i64 { return 7; }
EOF
check_equiv "Transitive 2: private-only edit in c" "$TX_DIR" "" || exit 1

# ── Failed build, then revert: nothing written by the failed build may be reused ───────────────
# The failed build recompiles m (new layout) and n (against it) before main fails. After reverting,
# the cache must not serve n's new object or m's new interface under the old manifest rows.
FR_DIR="$EQ_BASE/failed_revert"
rm -rf "$FR_DIR"
mkdir -p "$FR_DIR/inc"
write_transitive_fixture "$FR_DIR" "" ""
check_equiv "FailedRevert 0: baseline" "$FR_DIR" "" || exit 1
cp "$FR_DIR/inc/main.zrl" "$FR_DIR/main.orig"
write_transitive_fixture "$FR_DIR" "    pub a: i64," "a: 1,"
echo 'garbage' >> "$FR_DIR/inc/main.zrl"
if (cd "$FR_DIR/inc" && ZB --cache-dir .cache -o bin main.zrl >/dev/null 2>&1); then
    echo "FAIL: the deliberately broken build succeeded"; exit 1
fi
write_transitive_fixture "$FR_DIR" "" ""
check_equiv "FailedRevert 1: revert after a build that failed part-way" "$FR_DIR" "" || exit 1

# ── Generic body calling a private helper (helper must stay linkable from main) ────────────────
GP_EQ="$EQ_BASE/gp_eq"
rm -rf "$GP_EQ"
mkdir -p "$GP_EQ/inc"
write_gp_fixture() {
    cat << EOF > "$GP_EQ/inc/lib.zrl"
fn helper(x: i64) -> i64 { return x + $1; }
pub fn wrap<T>(v: T, x: i64) -> i64 { return helper(x); }
EOF
    cat << 'EOF' > "$GP_EQ/inc/main.zrl"
import "lib.zrl";
use lib::wrap;
pub fn main() -> i32 {
    return wrap::<i64>(0, 40) as i32;
}
EOF
}
write_gp_fixture 1
check_equiv "GenericPrivate 0: baseline" "$GP_EQ" "" || exit 1
write_gp_fixture 2
check_equiv "GenericPrivate 1: private helper body edit" "$GP_EQ" "" || exit 1

# ── Same basename in different directories ─────────────────────────────────────────────────────
SB_EQ="$EQ_BASE/samebase_eq"
rm -rf "$SB_EQ"
mkdir -p "$SB_EQ/inc/a" "$SB_EQ/inc/b"
write_samebase_fixture() {
    cat << EOF > "$SB_EQ/inc/a/util.zrl"
pub fn a_val() -> i64 { return $1; }
EOF
    cat << EOF > "$SB_EQ/inc/b/util.zrl"
pub fn b_val() -> i64 { return $2; }
EOF
    cat << 'EOF' > "$SB_EQ/inc/main.zrl"
import "a/util.zrl";
import "b/util.zrl" as butil;
pub fn main() -> i32 {
    return (util::a_val() + butil::b_val()) as i32;
}
EOF
}
write_samebase_fixture 1 2
check_equiv "SameBasename 0: baseline" "$SB_EQ" "" || exit 1
write_samebase_fixture 5 2
check_equiv "SameBasename 1: edit a/util only" "$SB_EQ" "" || exit 1
write_samebase_fixture 5 9
check_equiv "SameBasename 2: edit b/util only" "$SB_EQ" "" || exit 1

# ── Step 12: Fault injection — the suite must fail when early cutoff is broken ─────────────────
FI_DIR="$EQ_BASE/fault"
rm -rf "$FI_DIR"
mkdir -p "$FI_DIR/inc"
write_transitive_fixture "$FI_DIR" "" ""
check_equiv "Fault 0: baseline" "$FI_DIR" "--test-break-cutoff" || exit 1
write_transitive_fixture "$FI_DIR" "    pub a: i64," "a: 1,"
if check_equiv "Fault 1: layout change with cutoff broken" "$FI_DIR" "--test-break-cutoff" >/dev/null 2>&1; then
    echo "FAIL: equivalence check did not detect a deliberately broken early cutoff"
    exit 1
fi
echo "  [OK] Step 12: deliberately broken early cutoff is detected by the equivalence check"

echo "PASS: all incremental build equivalence tests passed."
