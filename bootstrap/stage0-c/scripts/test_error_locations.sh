#!/usr/bin/env bash
# scripts/test_error_locations.sh
#
# Compiles each .zrl file in tests/error_cases/ with --json-errors and verifies
# that every // @error annotation in the source is matched by an actual diagnostic
# at the expected line, column (if specified), and message substring.
#
# Annotation format (placed on the line that should trigger the error):
#   // @error "message substring" :COL
#   // @error "message substring"        (column check skipped)
#
# The file is expected to fail compilation (exit code != 0).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d "$REPO_ROOT/../../stdlib" ]; then
    TOP_DIR="$(cd "$REPO_ROOT/../.." && pwd)"
else
    TOP_DIR="$(cd "$REPO_ROOT/.." && pwd)"
fi
. "$REPO_ROOT/scripts/outside_dialect.sh"
ZORIL_BIN="${ZORIL_BIN:-$REPO_ROOT/build/zoril-c}"
ERROR_CASES_DIR="$TOP_DIR/tests/error_reporting"

if [ ! -f "$ZORIL_BIN" ]; then
    echo "Error: $ZORIL_BIN not found. Build the project first." >&2
    exit 1
fi

if [ ! -d "$ERROR_CASES_DIR" ]; then
    echo "Error: $ERROR_CASES_DIR not found." >&2
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

if [ "${QUIET:-0}" -ne 1 ]; then
    echo "Running error location tests..."
fi

# check_error FILE LINE COL_OR_0 MESSAGE_SUBSTR
# Returns 0 if the JSON output from compiling FILE contains a matching error.
check_error() {
    local f="$1" lineno="$2" col="$3" msg="$4"
    local extra_flags=""
    if [[ "$f" == *.zil ]]; then
        extra_flags="--il"
    fi
    local json
    json=$(ASAN_OPTIONS=detect_leaks=0 run_timed "$ZORIL_BIN" $extra_flags --json-errors "$f" -o /dev/null 2>/dev/null || true)

    if [ -z "$json" ]; then
        return 1
    fi

    # Use awk to scan each JSON error object for matching line, col, and message.
    echo "$json" | awk -v lineno="$lineno" -v col="$col" -v msg="$msg" '
    BEGIN { in_obj=0; line_ok=0; col_ok=(col=="0"?1:0); msg_ok=0; found=0 }
    /"severity"/ { in_obj=1; line_ok=0; col_ok=(col=="0"?1:0); msg_ok=0 }
    in_obj && /"line":/ {
        gsub(/[^0-9]/, "", $2); if ($2+0 == lineno+0) line_ok=1
    }
    in_obj && /"column":/ {
        gsub(/[^0-9]/, "", $2); if (col!="0" && $2+0 == col+0) col_ok=1
    }
    in_obj && /"message":/ { if (index($0, msg) > 0) msg_ok=1 }
    in_obj && /^[ \t]*\}/ {
        if (line_ok && col_ok && msg_ok) found=1
        in_obj=0
    }
    END { exit (found ? 0 : 1) }
    '
}

for f in "$ERROR_CASES_DIR"/*.zrl "$ERROR_CASES_DIR"/*.zil; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    # Out of scope for stage0-C (tests/outside_dialect.txt): not run, not counted.
    is_outside_dialect "$f" && continue
    reason=$(known_bug_reason "$f")
    if [ -n "$reason" ]; then
        if [ "${QUIET:-0}" -ne 1 ]; then echo "[SKIP] $name (known stage0-C $reason)"; fi
        continue
    fi

    lineno=0
    while IFS= read -r line_text; do
        lineno=$((lineno + 1))

        # Skip lines without an @error annotation
        echo "$line_text" | grep -q '// @error' || continue

        # Extract message substring (between first pair of double-quotes after @error)
        msg=$(echo "$line_text" | sed -n 's/.*\/\/ @error "\([^"]*\)".*/\1/p')
        [ -z "$msg" ] && continue

        # Extract optional :COL after the closing quote; default to 0 (skip column check)
        col=$(echo "$line_text" | sed -n 's/.*\/\/ @error "[^"]*" *:\([0-9][0-9]*\).*/\1/p')
        [ -z "$col" ] && col=0

        TOTAL=$((TOTAL + 1))
        col_desc=""
        [ "$col" != "0" ] && col_desc=":$col"

        if check_error "$f" "$lineno" "$col" "$msg"; then
            if [ "${QUIET:-0}" -ne 1 ]; then
                echo "[PASS] $name line $lineno$col_desc: \"$msg\""
            fi
        else
            echo "[FAIL] $name line $lineno$col_desc: expected error \"$msg\""
            json=$(ASAN_OPTIONS=detect_leaks=0 "$ZORIL_BIN" --json-errors "$f" -o /dev/null 2>/dev/null || true)
            echo "         Actual JSON:"
            echo "$json" | sed 's/^/         /'
            FAILURES=$((FAILURES + 1))
        fi
    done < "$f"
done

if [ "$FAILURES" -eq 0 ]; then
    echo "test_error_locations: $TOTAL/$TOTAL passed"
else
    echo "test_error_locations: $((TOTAL - FAILURES))/$TOTAL passed"
fi
[ "$FAILURES" -eq 0 ]
