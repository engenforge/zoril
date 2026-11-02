#!/usr/bin/env bash

# test_wrapper.sh - Briefly reports test success or failure with detailed logs on failure.
#
# When CHECK_ALL=1 is set (by check-all.sh), failure details are saved to
# $TEST_RESULTS_DIR/$TEST_NAME.fail and suppressed from stdout so that
# check-all.sh can print them together at the end of the run.
# Without CHECK_ALL=1, failure details are printed inline (default behavior).

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <test_command> [args...]"
    exit 1
fi

COMMAND="$1"
shift

# Create a temporary file for the output
LOG_FILE=$(mktemp)

TEST_NAME=$(basename "$COMMAND")

if [ "$COMMAND" = "valgrind" ]; then
    for ARG in "$@"; do
        if [[ "$ARG" != -* ]]; then
            TEST_NAME="valgrind ($(basename "$ARG"))"
            break
        fi
    done
fi

# Record results if results dir is set
if [ -n "${TEST_RESULTS_DIR:-}" ]; then
    mkdir -p "$TEST_RESULTS_DIR"
    rm -f "$TEST_RESULTS_DIR/$TEST_NAME.pass" "$TEST_RESULTS_DIR/$TEST_NAME.fail" "$TEST_RESULTS_DIR/$TEST_NAME.skip"
fi

# Timeouts
TIMEOUT_DUR="${TIMEOUT_DUR:-10s}"
KILL_DUR="${KILL_DUR:-2s}"
SIGXCPU_EXIT=152
_TW_TIMED_PID=
_tw_cleanup() {
    trap - INT TERM
    [ -n "$_TW_TIMED_PID" ] && kill -TERM "$_TW_TIMED_PID" 2>/dev/null
    kill 0 2>/dev/null
    exit 130
}
trap '_tw_cleanup' INT TERM

run_timed() {
    if command -v timeout >/dev/null 2>&1; then
        timeout -k "$KILL_DUR" "$TIMEOUT_DUR" "$@" &
    else
        "$@" &
    fi
    _TW_TIMED_PID=$!
    wait "$_TW_TIMED_PID" 2>/dev/null
    _tw_rc=$?
    _TW_TIMED_PID=
    return $_tw_rc
}
is_timeout_exit() { [ "$1" -eq 124 ] || [ "$1" -eq 137 ] || [ "$1" -eq "$SIGXCPU_EXIT" ]; }

# Run the command and capture both stdout and stderr
run_timed "$COMMAND" "$@" > "$LOG_FILE" 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    if grep -q '^\[SKIP\]' "$LOG_FILE"; then
        REASON=$(sed -n 's/^\[SKIP\] [^ ]* (\(.*\))/\1/p' "$LOG_FILE" | head -n 1)
        if [ -z "$REASON" ]; then
            REASON=$(sed -n 's/^\[SKIP\] *\(.*\)/\1/p' "$LOG_FILE" | head -n 1)
        fi
        if [ "${QUIET:-0}" -ne 1 ]; then
            if [ -n "$REASON" ]; then
                echo "[SKIP] $TEST_NAME ($REASON)"
            else
                echo "[SKIP] $TEST_NAME"
            fi
        fi
        if [ -n "${TEST_RESULTS_DIR:-}" ]; then
            mkdir -p "$TEST_RESULTS_DIR"
            touch "$TEST_RESULTS_DIR/$TEST_NAME.skip"
        fi
    else
        # Success: brief output (unless QUIET is set)
        if [ "${QUIET:-0}" -ne 1 ]; then
            echo "[PASS] $TEST_NAME"
        fi
        # Record pass result if results dir is set
        if [ -n "${TEST_RESULTS_DIR:-}" ]; then
            mkdir -p "$TEST_RESULTS_DIR"
            touch "$TEST_RESULTS_DIR/$TEST_NAME.pass"
        fi
    fi
    rm "$LOG_FILE"
else
    if [ -n "${CHECK_ALL:-}" ] && [ -n "${TEST_RESULTS_DIR:-}" ]; then
        # Agentic/check-all mode: defer details to end-of-run summary
        mkdir -p "$TEST_RESULTS_DIR"
        cp "$LOG_FILE" "$TEST_RESULTS_DIR/$TEST_NAME.fail"
        echo "[FAIL] $TEST_NAME"
    else
        # Standalone mode: print details inline immediately
        if is_timeout_exit $EXIT_CODE; then
            echo "[FAIL] $TEST_NAME (TIMEOUT)"
        else
            echo "[FAIL] $TEST_NAME (Exit Code: $EXIT_CODE)"
        fi
        # Indented: the test's own [PASS]/[FAIL] lines are details, not suite results.
        sed 's/^/    /' "$LOG_FILE"
    fi
    rm "$LOG_FILE"
    exit $EXIT_CODE
fi
