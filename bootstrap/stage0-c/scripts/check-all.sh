#!/usr/bin/env bash
# scripts/check-all.sh
#
# Robust, parallel test orchestrator.
# Prints one "SUITE: P/T passed" total per suite, and [FAIL] lines for failures.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
SCRIPTS="$REPO_ROOT/scripts"
TESTS_SRC="$REPO_ROOT/tests"

CC="${CC:-cc}"
MAKE_CMD="${MAKE:-make}"
OVERALL_RESULT=0

# Clean start for a full check
mkdir -p "$BUILD_DIR"

# Helper to wait for a background suite and print its total, "SUITE: P/T passed".
# Its [FAIL] lines (and the full log) are printed when it fails.
# wait_bg PID LOG_FILE SUITE_NAME FALLBACK_TOTAL
wait_bg() {
    local pid="$1"
    local log="$2"
    local name="$3"
    local fallback_total="$4"

    wait "$pid"
    local status=$?

    # We use grep -a to handle potential non-text output from tools
    local summary
    summary=$(grep -aE "^[a-z_]+: [0-9]+/[0-9]+ passed" "$log" | tail -n 1 || true)
    if [ -z "$summary" ]; then
        if [ $status -eq 0 ]; then
            summary="$name: $fallback_total/$fallback_total passed"
        else
            summary="$name: 0/$fallback_total passed"
        fi
    fi
    printf -- "%s\n" "$summary"

    local counts passed total
    counts=$(printf '%s' "$summary" | grep -oE '[0-9]+/[0-9]+')
    passed=${counts%/*}; total=${counts#*/}
    if [ $status -ne 0 ] || [ "$passed" -ne "$total" ]; then
        OVERALL_RESULT=1
        printf -- "[FAIL] %s (%s)\n" "$name" "$summary"
        printf -- "\n--- Details for %s ---\n" "$name"
        sed 's/^/    /' -- "$log"
        printf -- "----------------------\n\n"
    fi
    rm -f "$log"
}

echo "=== Starting Parallel Test Pipeline (Compiler: $CC) ==="

# 1. Build the compiler first (essential for all other tests)
printf "Building compiler... "
# We build sequentially to avoid race conditions on shared object files
for target in all release build-valgrind; do
    if ! $MAKE_CMD --no-print-directory "$target" > "$BUILD_DIR/build_$target.log" 2>&1; then
        printf "FAILED ($target)\n"
        cat "$BUILD_DIR/build_$target.log"
        exit 1
    fi
done
printf "Done\n"

# 2. Launch long-running or independent tasks in the background
# We isolate RESULTS_BASE for any task that runs make -C tests
rm -rf "$BUILD_DIR/tests/results_unit" "$BUILD_DIR/tests/results_val"

# Unit Tests
UNIT_LOG=$(mktemp)
( $MAKE_CMD --no-print-directory test_unit QUIET=1 RESULTS_BASE="$BUILD_DIR/tests/results_unit" > "$UNIT_LOG" 2>&1 ) &
UNIT_PID=$!

# Valgrind Suite
VAL_LOG=$(mktemp)
( $MAKE_CMD --no-print-directory test_valgrind_suite QUIET=1 RESULTS_BASE="$BUILD_DIR/tests/results_val" > "$VAL_LOG" 2>&1 ) &
VAL_PID=$!

# Corpus Tests
CORPUS_LOG=$(mktemp)
( $MAKE_CMD --no-print-directory test_corpus QUIET=1 > "$CORPUS_LOG" 2>&1 ) &
CORPUS_PID=$!

# Documentation Tests
DOCS_LOG=$(mktemp)
( $MAKE_CMD --no-print-directory test_docs QUIET=1 > "$DOCS_LOG" 2>&1 ) &
DOCS_PID=$!

# Error Location Tests
ERROR_LOG=$(mktemp)
( $MAKE_CMD --no-print-directory test_error_locations QUIET=1 > "$ERROR_LOG" 2>&1 ) &
ERROR_PID=$!

# Static Analysis (scan-build)
SCAN_LOG=$(mktemp)
( $MAKE_CMD --no-print-directory test_static_scanbuild QUIET=1 > "$SCAN_LOG" 2>&1 ) &
SCAN_PID=$!

# Static Analysis (cppcheck)
CPP_LOG=$(mktemp)
( $MAKE_CMD --no-print-directory test_static_cppcheck QUIET=1 > "$CPP_LOG" 2>&1 ) &
CPP_PID=$!

# 3. Collect Results as they finish
wait_bg "$UNIT_PID" "$UNIT_LOG" "test_unit" "88"
wait_bg "$VAL_PID" "$VAL_LOG" "test_valgrind_suite" "6"
wait_bg "$CORPUS_PID" "$CORPUS_LOG" "test_corpus" "39"
wait_bg "$DOCS_PID" "$DOCS_LOG" "test_docs" "22"
wait_bg "$ERROR_PID" "$ERROR_LOG" "test_error_locations" "16"
wait_bg "$SCAN_PID" "$SCAN_LOG" "test_static_scanbuild" "1"
wait_bg "$CPP_PID" "$CPP_LOG" "test_static_cppcheck" "1"

# ── Final result ─────────────────────────────────────────────────────────────
if [ "$OVERALL_RESULT" -eq 0 ]; then
    echo "=== ALL CHECKS PASSED ==="
else
    echo "=== CHECKS FAILED (see [FAIL] lines above) ==="
    exit 1
fi
