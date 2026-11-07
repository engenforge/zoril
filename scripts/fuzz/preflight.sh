#!/bin/sh
# scripts/fuzz/preflight.sh -- everything a cited fuzz run needs, one [PASS]/[FAIL] line each.
#
#   make fuzz-preflight
#
# The tree is clean; build/zoril and build/zilc (rebuilt first) report the hash of HEAD with no -dirty;
# rustc is there (the differential oracle is what raised both findings so far); the calibration programs
# are in their fixed state; a short fuzz run is clean; no other fuzz or test run is going (a loaded host
# starves a 15-hour run and spoils its timing); and check_fuzz_fresh.sh's verdict on the current record,
# which is expected to say stale until a new run is recorded. Exit status 1 if any line is [FAIL].
#
# Usage: preflight.sh [--check tree|build|rustc|calibration|short|busy|record]   (one check, for the tests)
set -u
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO_ROOT" || exit 2
. "$REPO_ROOT/scripts/lib/portability.sh"
. "$REPO_ROOT/scripts/lib/tree_files.sh"
. "$REPO_ROOT/scripts/lib/fuzz_run.sh"
. "$REPO_ROOT/scripts/lib/fuzz_fresh.sh"
ONLY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) ONLY=$2; shift 2 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "fuzz: unknown argument $1" >&2; exit 2 ;;
    esac
done
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }
bad=0
pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; bad=1; }
mkdir -p "$FUZZ_ROOT"

if want tree; then
    if [ -z "$(git status --porcelain 2>/dev/null)" ]; then pass "the working tree is clean"
    else fail "the working tree is not clean (git status)"; fi
fi

if want build; then
    [ -f Makefile ] && make --no-print-directory build/zoril build/zilc build/runtime.o build/zbuild > "$FUZZ_ROOT/preflight-build.log" 2>&1
    if fuzz_require_fresh "$REPO_ROOT/build/zoril" "$REPO_ROOT/build/zilc" "$REPO_ROOT/build/zbuild" 2> "$FUZZ_ROOT/preflight-fresh.log"; then
        pass "build/zoril, build/zilc and build/zbuild report the hash of HEAD ($(fuzz_version "$REPO_ROOT/build/zoril"))"
    else
        fail "the compilers do not report a clean HEAD: $(tr '\n' ' ' < "$FUZZ_ROOT/preflight-fresh.log")"
    fi
fi

if want rustc; then
    _r=$(fuzz_rustc)
    if [ -n "$_r" ] && [ -x "$_r" ]; then pass "rustc is present, so the differential oracle is on ($("$_r" --version 2>/dev/null | head -1))"
    else fail "rustc is missing: a cited run without the differential oracle is not recorded"; fi
fi

if want calibration; then
    if ./scripts/check_fuzz_calibrate.sh > "$FUZZ_ROOT/preflight-cal.log" 2>&1 && grep -q '^\[PASS\]' "$FUZZ_ROOT/preflight-cal.log"; then
        pass "make fuzz-calibrate: $(sed 's/^\[PASS\] fuzz-calibrate: //' "$FUZZ_ROOT/preflight-cal.log" | head -1)"
    else
        fail "make fuzz-calibrate does not pass (see $FUZZ_ROOT/preflight-cal.log)"
    fi
fi

if want short; then
    _fd=$(mktemp -d "${TMPDIR:-/tmp}/zfuzz.pre.XXXXXX")
    if FUZZ_FINDINGS="$_fd" ./scripts/fuzz_safe.sh --seeds 1-25 --count 4 --mode mix --checked > "$FUZZ_ROOT/preflight-short.log" 2>&1; then
        pass "make fuzz-short is clean"
    else
        fail "make fuzz-short is not clean (see $FUZZ_ROOT/preflight-short.log)"
    fi
    rm -rf "$_fd"
fi

if want busy; then
    _now=$(date +%s); _busy=""
    for _d in "$FUZZ_ROOT"/*/; do
        [ -f "$_d/run.status" ] || continue
        [ "$(run_state "$_d")" = running ] || continue
        _hb=$(kv "$_d/run.status" hb); _t=$(kv "$_d/w0.status" t)
        if [ -n "$_t" ] && [ $((_now - _t)) -le $((3 * ${_hb:-60})) ]; then _busy="$_busy $(basename "$_d")"; fi
    done
    if [ -n "$_busy" ]; then fail "another fuzz run is going:$_busy"; else pass "no other fuzz run is going"; fi
    if command -v flock >/dev/null 2>&1 && [ -f build/tests/.lock ] && ! flock -n build/tests/.lock true 2>/dev/null; then
        fail "a test run holds build/tests/.lock (wait for it, or it will starve the fuzz run)"
    else
        pass "no test run holds the test lock"
    fi
fi

if want record; then
    _v=$(./scripts/check_fuzz_fresh.sh 2>&1 | head -1)
    echo "[INFO] the current record: ${_v#\[PASS\] }"
fi
if [ "$bad" -ne 0 ]; then echo "fuzz-preflight: FAILED"; exit 1; fi
echo "fuzz-preflight: every check passed"
