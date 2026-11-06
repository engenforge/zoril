#!/bin/sh
# scripts/test_checked.sh — the whole test suite under `zoril --checked`.
#
# The per-file tests, the corpus and the apps are the programs the compiler already knows how to
# build and run; running them again through scripts/zoril-checked.sh is what makes every one of them
# a memory-safety test, because the checked build turns a dangling arena read, a dead local's slot
# read and a second drop of one storage into a fault, a trap or 0xA5. Expected results are the same
# as the normal build, with one addition: a test may ask for the checked build itself with
# `// flags: --checked` and assert what only that build does (tests/language/memory/checked_build_*).
#
# Then the safety matrix is asked the question it exists for: which of the known memory-safety holes
# does the checked build detect? Its report is recorded in bench/safety_matrix/README.md.
#
# Usage: scripts/test_checked.sh [PATH...]   (make test-checked)
set -u
# Tests that crash on purpose must not write core dumps (see scripts/test.sh).
ulimit -c 0 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 2
. scripts/lib/portability.sh 2>/dev/null || true

ZORIL_CC="$REPO_ROOT/scripts/zoril-checked.sh"
export ZORIL_CC

TR_WORK=build/tests-checked
export TR_WORK

if [ ! -x "$REPO_ROOT/build/zoril" ] || [ ! -x "$REPO_ROOT/build/zilc" ]; then
    echo "[FAIL] checked: build/zoril and build/zilc must be built first (run make)" >&2
    exit 1
fi

status=0

# Items this run leaves out, and why:
#   - the gates: their thresholds (perf-gate's instruction counts above all) are calibrated on the
#     unmarked code, and an instrumented build is not what they measure. `make test` runs them.
#   - the incremental scenario: it compares whole-program ZIL against corpus/zrl_whole_program_zil.sha256,
#     the *release* golden, which a checked build does not and should not reproduce.
#   - tests/compiler/test_arena.zrl and tests/stdlib/test_stdlib_arena_new_result.zrl: they assert
#     the unmarked arena's behaviour (a reset hands the same space out again, the capacity is exactly
#     what was asked for). The checked build deliberately breaks both, and `make test` still checks
#     them on the unmarked build.
TR_EXCLUDE="fmt-check md-check no-new-deps no-warnings test-strength fuzz-record mutation-self-test \
safety-matrix safety-matrix-zbuild safety-model safety-comments unsafe-scan runtimes static-image perf-gate toolchain \
portability clean-tree toolchain-offpath stage0c-fixed-bugs stage0c-unit stage0c-corpus stage0c-docs \
stage0c-error-locations stage0c-functional stage0c-minimal incremental \
tests/compiler/test_arena.zrl tests/stdlib/test_stdlib_arena_new_result.zrl"
export TR_EXCLUDE

echo "Checked build: per-file tests, corpus and apps"
if [ $# -gt 0 ]; then
    ./scripts/test.sh --quiet "$@" || status=1
elif ./scripts/test.sh --quiet --suite all; then
    echo "[PASS] checked: the test suite passes with every program built by --checked"
else
    echo "[FAIL] checked: the test suite does not pass under --checked"
    status=1
fi

if [ $# -eq 0 ]; then
    echo
    echo "Checked build: which known memory-safety holes does it detect?"
    ./scripts/run_safety_matrix.sh --checked || status=1
fi

exit $status
