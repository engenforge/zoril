#!/usr/bin/env bash
# scripts/test_functional.sh
#
# Compiles and runs all tests in the tests/functional/ and tests/bootstrap/ directories.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d "$REPO_ROOT/../../stdlib" ]; then
    TOP_DIR="$(cd "$REPO_ROOT/../.." && pwd)"
else
    TOP_DIR="$(cd "$REPO_ROOT/.." && pwd)"
fi
# The stdlib stage0-C actually builds the compiler against (the repository's stdlib/).
STDLIB_DIR="${ZORIL_STDLIB_DIR:-$TOP_DIR/stdlib}"
. "$REPO_ROOT/scripts/outside_dialect.sh"
ZORIL_BIN="${ZORIL_BIN:-$REPO_ROOT/build/zoril-c}"

if [ ! -f "$ZORIL_BIN" ]; then
    echo "Error: $ZORIL_BIN not found. Build the project first."
    exit 1
fi

FAILURES=0
TOTAL=0

# Timeouts
TIMEOUT_DUR="${TIMEOUT_DUR:-10s}"
KILL_DUR="${KILL_DUR:-2s}"
SIGXCPU_EXIT=152
TIMEOUT_FOREGROUND="${TIMEOUT_FOREGROUND:-$(command -v timeout >/dev/null 2>&1 && timeout --foreground 0 true 2>/dev/null && echo --foreground || true)}"
run_timed() {
    if command -v timeout >/dev/null 2>&1; then
        timeout $TIMEOUT_FOREGROUND -k "$KILL_DUR" "$TIMEOUT_DUR" "$@"
    else
        "$@"
    fi
}
is_timeout_exit() { [ "$1" -eq 124 ] || [ "$1" -eq 137 ] || [ "$1" -eq "$SIGXCPU_EXIT" ]; }

# Ensure output directory exists for intermediate files
mkdir -p "$REPO_ROOT/build/functional"

if [ "${QUIET:-0}" -ne 1 ]; then
    echo "Running E2E tests (functional & bootstrap)..."
fi

# The skip lists themselves: a stale entry would silently stop a test from running.
lists_result=$(check_skip_lists)
TOTAL=$((TOTAL + 1))
case "$lists_result" in
    "[FAIL]"*) FAILURES=$((FAILURES + 1)); echo "$lists_result" ;;
    *) [ "${QUIET:-0}" -eq 1 ] || echo "$lists_result" ;;
esac

# Find all test files recursively in the relevant directories
TEST_FILES=$(find "$TOP_DIR/tests/functional" "$TOP_DIR/tests/bootstrap" "$REPO_ROOT/tests/bootstrap" -type f \( -name "*.zrl" -o -name "*.zil" \) 2>/dev/null)

for f in $TEST_FILES; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    [[ "$name" == .* ]] && continue
    # Out of scope for stage0-C (tests/outside_dialect.txt): not run, not counted.
    is_outside_dialect "$f" && continue
    reason=$(known_bug_reason "$f")
    if [ -n "$reason" ]; then
        if [ "${QUIET:-0}" -ne 1 ]; then echo "[SKIP] $name (known stage0-C $reason)"; fi
        continue
    fi
    TOTAL=$((TOTAL + 1))

    # Parse expectations from file header
    # 0 = expect 0 (default)
    # N = expect N
    # -1 = expect compile fail (verifier error or parser error)
    # -2 = expect compile success, do not run
    
    EXPECTED_CODE=0
    if grep -q "expected compile fail" "$f"; then
        EXPECTED_CODE=-1
    elif grep -q "expected compile success" "$f"; then
        EXPECTED_CODE=-2
    elif grep -qE "^// expected exit (code: *)?[0-9]+$" "$f"; then
        # Both header spellings in use: "// expected exit N" and "// expected exit code: N".
        EXPECTED_CODE=$(grep -E "^// expected exit (code: *)?[0-9]+$" "$f" | sed -E 's/.*expected exit (code: *)?([0-9]+).*/\2/' | head -n 1)
    fi

    tmpdir=$(mktemp -d)
    outbin="$tmpdir/test_bin"

    # Use --keep-ssa if requested via environment
    KEEP_SSA_FLAG=""
    if [ "${KEEP_SSA:-0}" -eq 1 ]; then
        KEEP_SSA_FLAG="--keep-ssa"
    fi

    # Determine extra flags based on extension
    EXTRA_FLAGS="-I $STDLIB_DIR -I $TOP_DIR/src -I $TOP_DIR/tests/include"  # same include roots as the self-hosted runner
    if [[ "$f" == *.zil ]]; then
        EXTRA_FLAGS="$EXTRA_FLAGS --il"
    fi

    # Compile the file
    COMPILE_RES=0
    EMIT_IR_FLAG=""
    if [ "$EXPECTED_CODE" -eq -2 ]; then
        EMIT_IR_FLAG="--emit-ir"
    fi
    ZORIL_CMD=("$ZORIL_BIN" $EXTRA_FLAGS -I "$(dirname "$f")" -I "$TOP_DIR/tests/helpers" "$f" $KEEP_SSA_FLAG $EMIT_IR_FLAG -o "$outbin")
    ASAN_OPTIONS=detect_leaks=0 run_timed "${ZORIL_CMD[@]}" > "$tmpdir/compile.log" 2>&1 || COMPILE_RES=$?

    if [ "$EXPECTED_CODE" -eq -1 ]; then
        if is_timeout_exit "$COMPILE_RES"; then
            echo "[FAIL] $name (TIMEOUT during compilation)"
            FAILURES=$((FAILURES + 1))
        elif [ "$COMPILE_RES" -ne 0 ]; then
            if [ "${QUIET:-0}" -ne 1 ]; then echo "[PASS] $name (compile failed as expected)"; fi
        else
            echo "[FAIL] $name (expected compile fail, but it succeeded)"
            FAILURES=$((FAILURES + 1))
        fi
    elif [ "$EXPECTED_CODE" -eq -2 ]; then
        if is_timeout_exit "$COMPILE_RES"; then
            echo "[FAIL] $name (TIMEOUT during compilation)"
            FAILURES=$((FAILURES + 1))
        elif [ "$COMPILE_RES" -eq 0 ]; then
            if [ "${QUIET:-0}" -ne 1 ]; then echo "[PASS] $name (compile succeeded as expected)"; fi
        else
            echo "[FAIL] $name (expected compile success, but it failed)"
            cat "$tmpdir/compile.log"
            FAILURES=$((FAILURES + 1))
        fi
    else
        # Expect successful compile followed by specific exit code
        if is_timeout_exit "$COMPILE_RES"; then
            echo "[FAIL] $name (TIMEOUT during compilation)"
            FAILURES=$((FAILURES + 1))
        elif [ "$COMPILE_RES" -eq 0 ]; then
            # Run the binary in its own scratch directory, not in the caller's: a test that opens a
            # relative path must not write into the source tree.
            ( cd "$tmpdir" && run_timed ./test_bin ) < /dev/null > "$tmpdir/run.log" 2>&1
            ACTUAL_CODE=$?
            if is_timeout_exit "$ACTUAL_CODE"; then
                echo "[FAIL] $name (TIMEOUT during execution)"
                FAILURES=$((FAILURES + 1))
            elif [ "$ACTUAL_CODE" -eq "$EXPECTED_CODE" ]; then
                if [ "${QUIET:-0}" -ne 1 ]; then
                    echo "[PASS] $name"
                fi
            else
                echo "[FAIL] $name (execution failed with $ACTUAL_CODE, expected $EXPECTED_CODE)"
                FAILURES=$((FAILURES + 1))
            fi
        else
            echo "[FAIL] $name (compilation failed)"
            FAILURES=$((FAILURES + 1))
        fi
    fi

    rm -rf "$tmpdir"
done

if [ "$FAILURES" -eq 0 ]; then
    echo "test_functional: $TOTAL/$TOTAL passed"
else
    echo "test_functional: $((TOTAL - FAILURES))/$TOTAL passed"
fi
[ "$FAILURES" -eq 0 ]
