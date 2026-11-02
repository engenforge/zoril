#!/bin/sh
# scripts/test_bench_step_failed.sh — which failed benchmark steps stop the run.
#
# A step of the Zoril measurement (zbuild, zoril, zilc, the backend, the assembler, the linker) stops
# the run; a comparison language's step is skipped with a note. The test pulls `bench_step_failed` out
# of scripts/bench_cross_lang.sh and calls it with stand-in commands. It once matched the tool names as
# substrings of the whole command line, so `other build-exe -O ReleaseFast` (`as` in `ReleaseFast`)
# stopped every preflight at a toolchain that only the comparison table uses (zig 0.17).
cd "$(dirname "$0")/.." || exit 2
fail() { echo "[FAIL] bench-step-failed: $1"; exit 1; }
fn=$(sed -n '/^bench_step_failed() {/,/^}/p' scripts/bench_cross_lang.sh)
[ -n "$fn" ] || fail "bench_step_failed not found in scripts/bench_cross_lang.sh"
run() { # run PROGRAM ARG... -> exit status of the step's handler
    ( REPO_ROOT=/repo BACKEND_BIN=qbe ASSEMBLER_BIN=as LINKER_BIN=ld BENCH_ERRLOG=/dev/null BENCH_SKIPPED=""
      eval "$fn"
      bench_step_failed 1 "$@" ) > /dev/null 2>&1
}
run other_lang build-exe -O ReleaseFast -femit-bin=/tmp/x /repo/bench/cross_lang/array_loop.zig
[ $? -eq 0 ] || fail "a failing comparison step stopped the run"
run /repo/build/zoril --emit-zil -o /tmp/x.zil /repo/src/main.zrl
[ $? -eq 1 ] || fail "a failing zoril step did not stop the run"
run qbe -o /tmp/x.s /tmp/x.ssa
[ $? -eq 1 ] || fail "a failing qbe step did not stop the run"
run /usr/bin/ld -o /tmp/x /tmp/x.o
[ $? -eq 1 ] || fail "a failing ld step did not stop the run"
run zbuild_exec
[ $? -eq 1 ] || fail "a failing zbuild_exec step (workload 3) did not stop the run"
run sh -c "cd /tmp && '/repo/build/zbuild' -o x y.zrl"
[ $? -eq 1 ] || fail "a failing sh -c zbuild step (the size sweep) did not stop the run"
run cc -O2 -o /tmp/x /repo/bench/cross_lang/assembler_notes.c
[ $? -eq 0 ] || fail "a failing cc step stopped the run"
echo "[PASS] bench-step-failed: Zoril's own steps stop the run; a comparison language's step is skipped"
