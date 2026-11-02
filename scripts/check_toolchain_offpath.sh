#!/bin/sh
# scripts/check_toolchain_offpath.sh — Gate: toolchain pipelines work with qbe off PATH.
#
# Builds a PATH with every directory holding a `qbe` executable removed,
# sets BACKEND_BIN to the real backend binary, and runs a fast representative set:
#   1. One scripts/test.sh per-file case (tests/language/basic/test_arithmetic.zrl)
#   2. scripts/test_sha256_differential.sh
#   3. One compile-and-run safety-matrix probe (02_use_after_move_pod)
#   4. The cross-module scenario's first probe (probe 02)
#   5. One stage0-C e2e unit test (test_e2e)
#   6. scripts/fuzz_safe.sh --seeds 1-2
#
# Fails on any command failure or exit 127 / command not found.
#
# Usage:
#   scripts/check_toolchain_offpath.sh             Run checks
#   scripts/check_toolchain_offpath.sh --selftest  Run checker selftest
set -eu

# build_offpath <source_path> <work_dir>
# Shadows any directory containing a `qbe` executable by creating symlinks
# for all other tools in that directory except `qbe`. Returns the stripped PATH.
build_offpath() {
    _src_path="$1"
    _work_dir="$2"
    _res_path=""
    _saved_ifs="$IFS"
    IFS=':'
    _idx=0
    _seen_reals=""
    for _d in $_src_path; do
        [ -n "$_d" ] || continue
        [ -d "$_d" ] || continue
        _d_real="$(cd -P "$_d" 2>/dev/null && pwd)"
        if [ -x "$_d/qbe" ]; then
            case " $_seen_reals " in
                *" $_d_real "*)
                    continue
                    ;;
            esac
            _seen_reals="${_seen_reals} $_d_real"
            _shadow="$_work_dir/shadow_$_idx"
            _idx=$((_idx + 1))
            mkdir -p "$_shadow"
            for _f in "$_d_real"/*; do
                [ -e "$_f" ] || continue
                if [ "$(basename "$_f")" != "qbe" ]; then
                    ln -s "$_f" "$_shadow/" 2>/dev/null || true
                fi
            done
            _res_path="${_res_path:+${_res_path}:}$_shadow"
        else
            _res_path="${_res_path:+${_res_path}:}$_d"
        fi
    done
    IFS="$_saved_ifs"
    printf '%s' "$_res_path"
}

if [ "${1:-}" = "--selftest" ]; then
    _st_tmp="${TMPDIR:-/tmp}/toolchain_offpath_selftest.$$"
    rm -rf "$_st_tmp"
    mkdir -p "$_st_tmp/bin1" "$_st_tmp/bin2" "$_st_tmp/work"
    printf '#!/bin/sh\nexit 0\n' > "$_st_tmp/bin1/qbe"
    chmod +x "$_st_tmp/bin1/qbe"
    printf '#!/bin/sh\nexit 0\n' > "$_st_tmp/bin1/other1"
    chmod +x "$_st_tmp/bin1/other1"
    printf '#!/bin/sh\nexit 0\n' > "$_st_tmp/bin2/other2"
    chmod +x "$_st_tmp/bin2/other2"

    _test_path="$_st_tmp/bin1:$_st_tmp/bin2"
    _stripped_path="$(build_offpath "$_test_path" "$_st_tmp/work")"

    if PATH="$_stripped_path" command -v qbe >/dev/null 2>&1; then
        echo "[FAIL] selftest: qbe still found in stripped path" >&2
        rm -rf "$_st_tmp"
        exit 1
    fi

    if ! PATH="$_stripped_path" command -v other1 >/dev/null 2>&1; then
        echo "[FAIL] selftest: other1 in shadowed directory not found in stripped path" >&2
        rm -rf "$_st_tmp"
        exit 1
    fi

    if ! PATH="$_stripped_path" command -v other2 >/dev/null 2>&1; then
        echo "[FAIL] selftest: other2 not found in stripped path" >&2
        rm -rf "$_st_tmp"
        exit 1
    fi

    # Negative case: bare qbe in pipeline step must fail under stripped PATH
    printf 'data $msg = { b "hi", b 0 }\n' > "$_st_tmp/test.ssa"
    _bare_backend="qbe"
    if ( PATH="$_stripped_path"; "$_bare_backend" -o "$_st_tmp/test.s" "$_st_tmp/test.ssa" ) >/dev/null 2>&1; then
        echo "[FAIL] selftest: pipeline step with bare qbe unexpectedly succeeded under stripped PATH" >&2
        rm -rf "$_st_tmp"
        exit 1
    fi

    # Positive case: same pipeline step with explicit BACKEND_BIN pointing to real binary succeeds
    if ! ( PATH="$_stripped_path"; "$_st_tmp/bin1/qbe" -o "$_st_tmp/test.s" "$_st_tmp/test.ssa" ) >/dev/null 2>&1; then
        echo "[FAIL] selftest: pipeline step with explicit backend failed" >&2
        rm -rf "$_st_tmp"
        exit 1
    fi

    rm -rf "$_st_tmp"
    echo "[PASS] toolchain-offpath: selftest passed"
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

. "$REPO_ROOT/scripts/lib/layout.sh"
. "$REPO_ROOT/scripts/lib/portability.sh"

# 1. Resolve real backend binary
REAL_BACKEND="${BACKEND_BIN:-}"
if [ -z "$REAL_BACKEND" ]; then
    REAL_BACKEND="$(command -v qbe 2>/dev/null || true)"
fi
if [ -z "$REAL_BACKEND" ] || [ ! -x "$REAL_BACKEND" ]; then
    _which="$(command -v "$REAL_BACKEND" 2>/dev/null || true)"
    if [ -n "$_which" ] && [ -x "$_which" ]; then
        REAL_BACKEND="$_which"
    fi
fi

if [ -z "$REAL_BACKEND" ] || [ ! -x "$REAL_BACKEND" ]; then
    echo "[SKIP] toolchain-offpath: backend (qbe) not found or not executable"
    exit 0
fi

REAL_BACKEND="$(cd "$(dirname "$REAL_BACKEND")" 2>/dev/null && pwd)/$(basename "$REAL_BACKEND")"

WORK="$REPO_ROOT/build/toolchain_offpath"
rm -rf "$WORK"
mkdir -p "$WORK"

# 2. Build a PATH with qbe removed (shadowing directories that contain qbe)
OFF_PATH="$(build_offpath "$PATH" "$WORK")"

if PATH="$OFF_PATH" command -v qbe >/dev/null 2>&1; then
    echo "[FAIL] toolchain-offpath: qbe is still on stripped PATH ($OFF_PATH)" >&2
    exit 1
fi

ZORIL="$REPO_ROOT/build/zoril"
ZILC="$REPO_ROOT/build/zilc"
RUNTIME_O="$REPO_ROOT/build/runtime.o"
ASSEMBLER_BIN="${ASSEMBLER_BIN:-as}"
LINKER_BIN="${LINKER_BIN:-ld}"

export PATH="$OFF_PATH"
export BACKEND_BIN="$REAL_BACKEND"
export ASSEMBLER_BIN
export LINKER_BIN

# Case 1: One scripts/test.sh per-file case
if ! TR_WORK="$WORK/tr_work" ./scripts/test.sh tests/language/basic/test_arithmetic.zrl > "$WORK/case1.log" 2>&1; then
    echo "[FAIL] toolchain-offpath: per-file test failed with qbe off PATH:" >&2
    cat "$WORK/case1.log" >&2
    exit 1
fi

# Case 2: scripts/test_sha256_differential.sh
if ! ./scripts/test_sha256_differential.sh > "$WORK/case2.log" 2>&1; then
    echo "[FAIL] toolchain-offpath: test_sha256_differential.sh failed with qbe off PATH:" >&2
    cat "$WORK/case2.log" >&2
    exit 1
fi

# Case 3: One compile-and-run safety-matrix probe (02_use_after_move_pod)
probe_src="$REPO_ROOT/bench/safety_matrix/probes/02_use_after_move_pod.zrl"
if [ -f "$probe_src" ]; then
    if ! "$ZORIL" -I "$REPO_ROOT/stdlib" --emit-zil -o "$WORK/probe02.zil" "$probe_src" > "$WORK/case3.log" 2>&1 || \
       ! "$ZILC" "$WORK/probe02.zil" "$WORK/probe02.ssa" >> "$WORK/case3.log" 2>&1 || \
       ! "$REAL_BACKEND" -o "$WORK/probe02.s" "$WORK/probe02.ssa" >> "$WORK/case3.log" 2>&1 || \
       ! "$ASSEMBLER_BIN" -o "$WORK/probe02.o" "$WORK/probe02.s" >> "$WORK/case3.log" 2>&1 || \
       ! "$LINKER_BIN" -o "$WORK/probe02.bin" "$WORK/probe02.o" "$RUNTIME_O" >> "$WORK/case3.log" 2>&1 || \
       ! "$WORK/probe02.bin" >> "$WORK/case3.log" 2>&1; then
        echo "[FAIL] toolchain-offpath: safety-matrix probe 02 failed with qbe off PATH:" >&2
        cat "$WORK/case3.log" >&2
        exit 1
    fi
fi

# Case 4: The cross-module scenario's first probe (copied from scripts/test_safety_matrix_cross_module.sh: probe 02 "Use after move (POD) across module boundary")
cat > "$WORK/cm_lib.zrl" << 'EOF'
pub struct Point { pub x: i32, pub y: i32 }
pub fn take_point(p: Point) -> i32 { return p.x; }
EOF
cat > "$WORK/cm_caller.zrl" << 'EOF'
import "cm_lib.zrl";
use cm_lib::{Point, take_point};
fn main() -> i32 {
    let p = Point { x: 1, y: 2 };
    let a = take_point(p);
    return p.y - 2;
}
EOF
if ! "$ZORIL" --emit-interface -o "$WORK/cm_lib.zri" "$WORK/cm_lib.zrl" > "$WORK/case4.log" 2>&1 || \
   ! "$ZORIL" -c -o "$WORK/cm_lib.zil" "$WORK/cm_lib.zrl" >> "$WORK/case4.log" 2>&1 || \
   ! "$ZILC" "$WORK/cm_lib.zil" "$WORK/cm_lib.ssa" >> "$WORK/case4.log" 2>&1 || \
   ! "$REAL_BACKEND" -o "$WORK/cm_lib.s" "$WORK/cm_lib.ssa" >> "$WORK/case4.log" 2>&1 || \
   ! "$ASSEMBLER_BIN" -o "$WORK/cm_lib.o" "$WORK/cm_lib.s" >> "$WORK/case4.log" 2>&1 || \
   ! "$ZORIL" -c -I "$WORK" --emit-zil -o "$WORK/cm_caller.zil" "$WORK/cm_caller.zrl" >> "$WORK/case4.log" 2>&1 || \
   ! "$ZILC" "$WORK/cm_caller.zil" "$WORK/cm_caller.ssa" >> "$WORK/case4.log" 2>&1 || \
   ! "$REAL_BACKEND" -o "$WORK/cm_caller.s" "$WORK/cm_caller.ssa" >> "$WORK/case4.log" 2>&1 || \
   ! "$ASSEMBLER_BIN" -o "$WORK/cm_caller.o" "$WORK/cm_caller.s" >> "$WORK/case4.log" 2>&1 || \
   ! "$LINKER_BIN" -o "$WORK/cm_bin" "$WORK/cm_caller.o" "$WORK/cm_lib.o" "$RUNTIME_O" >> "$WORK/case4.log" 2>&1 || \
   ! "$WORK/cm_bin" >> "$WORK/case4.log" 2>&1; then
    echo "[FAIL] toolchain-offpath: cross-module probe 02 failed with qbe off PATH:" >&2
    cat "$WORK/case4.log" >&2
    exit 1
fi

# Case 5: One stage0-C e2e unit test (test_e2e)
# Its own PURPOSE: the stage0c-unit gate builds the same test from the same sources under the default
# PURPOSE while this gate runs beside it, and the tests Makefile keys every object, binary and result
# directory on PURPOSE. Without it the two writes collide and test_e2e can link a half-written
# verifier.o ("undefined reference to verify_module", seen in the dependency matrix's cc row).
# A qbe-backed C compiler (cproc) cannot build anything with qbe off PATH: its own codegen step spawns
# `qbe` by name, and BACKEND_BIN is Zoril's setting, not cproc's. Zoril's pipeline is still checked.
_cc_name=$(basename "${CC:-cc}" 2>/dev/null || echo cc)
cases_run=4
case "$_cc_name" in
    cproc*) echo "[SKIP] toolchain-offpath: stage0-C test_e2e is C compiled by $_cc_name, which emits through qbe and needs it on PATH" ;;
    *)
        if [ -d "$REPO_ROOT/$STAGE0_DIR/tests" ]; then
            if ! ${MAKE:-make} --no-print-directory -C "$REPO_ROOT/$STAGE0_DIR/tests" PURPOSE=toolchain_offpath run-test_e2e > "$WORK/case5.log" 2>&1; then
                echo "[FAIL] toolchain-offpath: stage0-C test_e2e failed with qbe off PATH:" >&2
                cat "$WORK/case5.log" >&2
                exit 1
            fi
            cases_run=5
        fi ;;
esac

# Case 6: scripts/fuzz_safe.sh --seeds 1-2
if command -v timeout >/dev/null 2>&1 && command -v lua >/dev/null 2>&1; then
    if ! ./scripts/fuzz_safe.sh --seeds 1-2 > "$WORK/case6.log" 2>&1; then
        echo "[FAIL] toolchain-offpath: fuzz_safe.sh --seeds 1-2 failed with qbe off PATH:" >&2
        cat "$WORK/case6.log" >&2
        exit 1
    fi
    cases_run=$((cases_run + 1))
fi

rm -rf "$WORK"
echo "[PASS] toolchain-offpath: $cases_run representative cases passed with qbe off PATH"
exit 0
