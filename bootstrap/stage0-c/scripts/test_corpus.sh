#!/usr/bin/env bash
# scripts/test_corpus.sh
#
# Compiles and runs all examples in the zoril corpus using the current build.
# Prioritizes the local zoril-c/corpus/ directory for repository isolation.
# Each corpus program is expected to exit with status 0 unless the source
# contains a comment "// expected exit code: N".

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

# Prioritize the parent corpus/ directory
if [ -d "$TOP_DIR/corpus" ]; then
    CORPUS_DIR="$TOP_DIR/corpus"
else
    CORPUS_DIR="${CORPUS_DIR:-$TOP_DIR/corpus}"
fi

if [ ! -f "$ZORIL_BIN" ]; then
    echo "Error: $ZORIL_BIN not found. Build the project first."
    exit 1
fi

if [ ! -d "$CORPUS_DIR" ]; then
    echo "Error: Corpus directory $CORPUS_DIR not found."
    exit 1
fi

FAILURES=0
TOTAL=0

# Ensure output directory exists for intermediate files
mkdir -p "$REPO_ROOT/build/corpus"

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

if [ "${QUIET:-0}" -ne 1 ]; then
    echo "Running corpus tests..."
fi

for f in "$CORPUS_DIR"/zrl/*.zrl "$CORPUS_DIR"/zil/*.zil; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    # Out of scope for stage0-C (tests/outside_dialect.txt): not run, not counted.
    is_outside_dialect "$f" && continue
    reason=$(known_bug_reason "$f")
    if [ -n "$reason" ]; then
        if [ "${QUIET:-0}" -ne 1 ]; then echo "[SKIP] $name (known stage0-C $reason)"; fi
        continue
    fi
    TOTAL=$((TOTAL + 1))

    # Extract expected exit code from comments if present, default to 0
    # Note: Using sed instead of rg to match the specific format
    EXPECTED_CODE=0
    code_line=$(grep "expected exit code:" "$f" | sed -E 's/.*expected exit code: ([0-9]+).*/\1/' || true)
    if [ -n "$code_line" ]; then
        EXPECTED_CODE="$code_line"
    fi

    tmpdir=$(mktemp -d)
    outbin="$tmpdir/test_bin"

    # Use --keep-ssa if requested via environment
    KEEP_SSA_FLAG=""
    if [ "${KEEP_SSA:-0}" -eq 1 ]; then
        KEEP_SSA_FLAG="--keep-ssa"
    fi

    # Determine extra flags based on extension
    EXTRA_FLAGS="-I $STDLIB_DIR"
    if [[ "$f" == *.zil ]]; then
        EXTRA_FLAGS="$EXTRA_FLAGS --il"
    fi

    if ASAN_OPTIONS=detect_leaks=0 run_timed "$ZORIL_BIN" "$f" $KEEP_SSA_FLAG $EXTRA_FLAGS -o "$outbin" > "$tmpdir/compile.log" 2>&1; then
        COMPILE_RES=$?
        # Run the binary in its own scratch directory, not in the caller's: a corpus program that
        # opens a relative path must not write into the source tree. (On 2026-10-18 a miscompiled
        # fd_open wrote a stray `@0@` into stage0-C/ this way; see known_bugs.txt.)
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
        COMPILE_RES=$?
        if is_timeout_exit "$COMPILE_RES"; then
            echo "[FAIL] $name (TIMEOUT during compilation)"
        else
            echo "[FAIL] $name (compilation failed)"
        fi
        # cat "$tmpdir/compile.log" # Debug
        FAILURES=$((FAILURES + 1))
    fi

    rm -rf "$tmpdir"
done

if [ "$FAILURES" -eq 0 ]; then
    echo "test_corpus: $TOTAL/$TOTAL passed"
else
    echo "test_corpus: $((TOTAL - FAILURES))/$TOTAL passed"
fi
[ "$FAILURES" -eq 0 ]
