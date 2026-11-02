#!/bin/sh
# scripts/check_fuzz_calibrate.sh — the fuzzer's calibration programs are fixed-state regression checks.
#
# The 23 calibration programs in `scripts/fuzz/gen.lua --mode calibration` were written while the
# 2026-10-18 holes were open, where each one ran and faulted. The five unified fixes closed them,
# so the same programs now must not run: 21 must be refused by the compiler, and the two drop-count
# programs must be accepted and exit 0 (exactly one drop). `scripts/fuzz_calibrate.sh` checks that
# against the table in `bench/fuzz/README.md`. This gate exists because that table drifted through a
# commit whose `preflight-changed` passed - nothing ran the calibration stream outside an on-demand
# target. It costs about two seconds once every program is refused.
#
# Usage: check_fuzz_calibrate.sh   (prints one [PASS]/[FAIL]/[SKIP] item)
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/scripts/lib/portability.sh" 2>/dev/null || true

for f in "$REPO_ROOT/build/zoril" "$REPO_ROOT/build/zilc" "$REPO_ROOT/build/runtime.o"; do
    if [ ! -e "$f" ]; then
        echo "[SKIP] fuzz-calibrate: $f is not built (run make)"
        exit 0
    fi
done
if ! command -v lua >/dev/null 2>&1 || ! lua -e "if not math.tointeger then os.exit(1) end" >/dev/null 2>&1; then
    echo "[SKIP] fuzz-calibrate: lua 5.3 or newer not found (needed by the fuzzer generator)"
    exit 0
fi

out=$("$REPO_ROOT/scripts/fuzz_calibrate.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)"
else
    echo "[FAIL] fuzz-calibrate: a calibration row is not in its fixed state"
    printf '%s\n' "$out" | sed 's/^/       /'
fi
exit "$rc"
