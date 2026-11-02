#!/bin/sh
# scripts/fuzz/stub_zoril.sh — a compiler that accepts everything, for the driver's own tests.
#
# `ZORIL_BIN=scripts/fuzz/stub_zoril.sh FUZZ_STUB_ZIL=<zil>` compiles whatever program it is handed into
# that ZIL and exits 0, so the run goes on through the backend and every generated program is *accepted*
# and runs. Two things need that and neither can have a compiler hole to hand:
#   - the mismatch stream's rule: one of its shapes is valid Rust, so an accepted mismatch has to be a
#     finding whatever `rustc` says about the twin (`scripts/test_fuzz_jobs.sh`);
#   - a candidate on demand, to check where a run is allowed to put one (`scripts/check_fuzz_record.sh`).
#
# It has to honour `-o`. A stub that writes the ZIL to stdout instead leaves the driver's `t.zil` missing,
# and then every program comes out as a `toolchain zilc` *fault*: a test that only requires "the run
# failed" still passes, for a reason that has nothing to do with the rule it means to pin. That is what the
# inline stub in `scripts/test_fuzz_jobs.sh` did until 2026-10-13, and why it is a file now.
set -u
ZIL=${FUZZ_STUB_ZIL:?FUZZ_STUB_ZIL must name the ZIL this stub emits}
[ -f "$ZIL" ] || { echo "stub_zoril: no such ZIL: $ZIL" >&2; exit 2; }
out=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-o" ] && [ $# -ge 2 ]; then out=$2; shift; fi
    shift
done
[ -n "$out" ] || { echo "stub_zoril: called without -o" >&2; exit 2; }
cat "$ZIL" > "$out"
