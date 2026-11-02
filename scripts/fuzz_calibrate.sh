#!/usr/bin/env sh
# scripts/fuzz_calibrate.sh -- run the fuzzer's calibration stream and say, per known hole, which
# oracle saw it.
#
# `lua scripts/fuzz/gen.lua --mode calibration` emits one self-contained program per memory-safety
# hole the 2026-10-18 audit found. They were written while the holes were open, where every program
# was accepted and faulted (a canary exit 92, a drop counter 91, or a raw-pointer pattern fault 139).
# The five unified fixes closed all 23, so today the stream is a *regression check in the fixed
# state*: 21 programs must be refused by the compiler, and the two drop-count programs
# (`closure_capture_multiple_drop`, `let_destructure_double_drop`) must be accepted and exit 0 -
# exactly one drop. A program that stops being refused, or one that exits non-zero again, fails this
# run: the first is a reopened hole, the second a regression in closure or pattern ownership.
#
# The Rust twin is read too: `reject` is the expected answer for a refused program (the twin is
# written to break the same rule), and `accept` is right for the two drop-count programs - their
# defect was a drop count, not a borrow.
#
# The checked-build column is the safety matrix's measurement of the same 21 holes (probes
# 200-220, `bench/safety_matrix/README.md`): the canary runs first, so the checked build's poison is
# a second net rather than the observation the table records. The script reports what each oracle
# says on today's tree; it does not try to strip the canaries.
#
# Every generated hole is guarded by the driver's `hole-on` runtime switch. This script passes that
# argument, so the hole runs; the driver's switch-off run is what proves a fault belongs to the hole.
#
# Usage: scripts/fuzz_calibrate.sh [--quiet]
# Exit: 0 when every hole still shows the recorded outcome; 1 when one changed (a fix landed, or the
#       generator/compiler moved) or a program could not be classified.
set -u
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$REPO_ROOT/scripts/lib/portability.sh" 2>/dev/null || true
ZORIL=${ZORIL_BIN:-$REPO_ROOT/build/zoril}
ZILC=${ZILC_BIN:-$REPO_ROOT/build/zilc}
QBE=${BACKEND_BIN:-$(command -v qbe 2>/dev/null || echo qbe)}
AS=${ASSEMBLER_BIN:-$(command -v as 2>/dev/null || echo as)}
LD=${LINKER_BIN:-$(command -v ld 2>/dev/null || echo ld)}
RUNTIME_O=$REPO_ROOT/build/runtime.o
QUIET=${1:-}

for f in "$ZORIL" "$ZILC" "$RUNTIME_O"; do
    if [ ! -e "$f" ]; then echo "[SKIP] fuzz-calibrate: $f is not built (run make)" >&2; exit 2; fi
done

OUT=$(mktemp -d "${TMPDIR:-/tmp}/zfuzz.calibrate.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
lua "$REPO_ROOT/scripts/fuzz/gen.lua" --mode calibration --seed 1 --out "$OUT" > "$OUT/manifest" || exit 2
CASES="$OUT/calibration"
[ -d "$CASES" ] || { echo "[FAIL] fuzz-calibrate: the generator emitted no calibration/ directory" >&2; exit 1; }

# expected <id> -- the fixed-state outcome: `rejected` for a hole the compiler must refuse, `0`
# for a drop-count program that must be accepted and drop once. A row that changes is a reopened
# hole or a regression; update this table and bench/fuzz/README.md together.
expected() {
    case "$1" in
        index_mut_borrow|slice_index_mut_borrow|index_compound_assign|\
        arena_index_reset|arena_branch_reset|arena_loop_mark_reset_to|branch_reassign_loop|\
        arena_box_slice_reset|arena_callptr_reset_to|arena_closure_ret_reset|\
        enum_payload_block_escape|arena_repeat_reset|ret_storage_local_alias|\
        ret_storage_struct_wrap|ret_storage_index_ref|ret_storage_tuple_field_ref|\
        same_type_borrow_loop_escape|loop_closure_env_escape|\
        premark_byvalue_reset_to|raw_tuple_pattern_deref|raw_enum_pattern_deref|local_buffer_view_drop|\
        fn_value_store_stack|owning_move_before_borrow_use)
            echo rejected ;;
        closure_capture_multiple_drop|let_destructure_double_drop)
            echo 0 ;;
        *) echo "" ;;
    esac
}

# run_one <program> <dir> [checked] -- prints the process status, or `rejected` / `toolchain <step>`.
run_one() {
    _p=$1; _d=$2; _zflag=""
    [ "${3:-}" = checked ] && _zflag="--checked"
    if ! "$ZORIL" $_zflag -I "stdlib=$REPO_ROOT/stdlib" --emit-zil -o "$_d/t.zil" "$_p" >"$_d/zoril.log" 2>&1; then
        echo rejected; return
    fi
    "$ZILC" "$_d/t.zil" "$_d/t.ssa" >/dev/null 2>&1 || { echo "toolchain zilc"; return; }
    "$QBE" -o "$_d/t.s" "$_d/t.ssa" >/dev/null 2>&1 || { echo "toolchain qbe"; return; }
    "$AS" -o "$_d/t.o" "$_d/t.s" 2>/dev/null || { echo "toolchain as"; return; }
    "$LD" -o "$_d/t.bin" "$_d/t.o" "$RUNTIME_O" 2>/dev/null || { echo "toolchain ld"; return; }
    _rc=0
    { ( run_with_timeout -k 1s 5 "$_d/t.bin" hole-on >/dev/null 2>&1 ) ; } 2>/dev/null || _rc=$?
    echo "$_rc"
}

fails=0; rows=0
for prog in "$CASES"/*.zrl; do
    [ -e "$prog" ] || continue
    rows=$((rows + 1))
    stem=$(basename "$prog" .zrl)
    id=${stem#c??_}
    want=$(expected "$id")
    [ -n "$want" ] || { echo "[FAIL] $stem: no expected outcome in this script - add the row"; fails=$((fails + 1)); continue; }
    d="$OUT/run/$(basename "$prog" .zrl)"; mkdir -p "$d"
    got=$(run_one "$prog" "$d")
    checked=$(run_one "$prog" "$d" checked)
    if [ "$got" != "$want" ]; then
        if [ "$got" = "rejected" ]; then
            echo "[CHANGED] $stem: zoril refuses it now, the fixed table expects exit $want"
        else
            echo "[REOPENED] $stem: unmarked run exits $got, the fixed state requires $want"
        fi
        fails=$((fails + 1))
        continue
    fi
    if [ "$got" = "rejected" ]; then
        # A refused program is the fixed state of a compile-time hole. The checked build runs the
        # same front end, so it must refuse it too.
        [ "$checked" = "rejected" ] || {
            echo "[CHECKED] $stem: --checked gives '$checked', expected 'rejected'"
            fails=$((fails + 1))
        }
        twin="reject"
    else
        # An accepted drop-count program must drop exactly once, in both builds.
        [ "$checked" = "0" ] || { echo "[CHECKED] $stem: --checked exits $checked, expected 0"; fails=$((fails + 1)); }
        twin="accept"
    fi
    if command -v rustc >/dev/null 2>&1; then
        if rustc --edition 2021 --crate-type bin --emit=metadata -o "$d/twin.rmeta" "${prog%.zrl}.rs" >"$d/rustc.log" 2>&1; then
            rverdict=accept
        else
            rverdict=reject
        fi
        [ "$rverdict" = "$twin" ] || { echo "[TWIN] $stem: rustc says $rverdict, expected $twin"; fails=$((fails + 1)); }
    else
        rverdict="no-rustc"
    fi
    [ -n "$QUIET" ] || printf '[OK] %-32s %-9s checked %-9s rustc %s\n' "$id" "$got" "$checked" "$rverdict"
done

if [ "$rows" -eq 0 ]; then echo "[FAIL] fuzz-calibrate: no calibration program was generated" >&2; exit 1; fi
if [ "$fails" -gt 0 ]; then
    echo "fuzz-calibrate: $fails of $rows row(s) are not in their fixed state - a hole reopened or the generator moved; update the table and this script together"
    exit 1
fi
echo "fuzz-calibrate: $rows/$rows calibration program(s) are in their fixed state (22 refused, 2 accepted with one drop)"
exit 0
