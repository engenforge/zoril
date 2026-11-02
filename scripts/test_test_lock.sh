#!/bin/sh
# scripts/test_test_lock.sh — one test run per work directory.
#
# A run recreates $TR_WORK/items and the FIFO inside it, so a second concurrent run on the same
# TR_WORK deletes the FIFO the first one is reading, and that one then blocks forever
# ("the worker left no result"). scripts/test.sh takes an exclusive non-blocking lock on
# $TR_WORK/.lock and exits non-zero at once instead. This checks:
#   - a held lock makes a run refuse at once, with the message and the holder's pid, without
#     touching the work directory;
#   - a second run refuses a real run that is holding the lock (frozen mid-run with SIGSTOP,
#     since a small suite finishes in well under a second), and that run then completes
#     normally and is not disturbed;
#   - two runs with different TR_WORK directories still run at the same time.
set -eu

cd "$(dirname "$0")/.."
. scripts/lib/portability.sh
TEST_SH="$(pwd)/scripts/test.sh"
WORKLOAD="tests/language/basic"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

errors=0
fail() { echo "[FAIL] $1"; errors=$((errors + 1)); }
pass() { echo "[PASS] $1"; }

LOCKED="another test run is using"

# The workload is 26 per-file tests plus the runner's own "stray-files" item, which needs git; a tree
# without git (an optional tool) reports that item as [SKIP], so the whole suite is one item fewer.
whole_suite() { # whole_suite LOG
    if git_checkout_usable .; then
        grep -q '^Total: 27 run, 27 passed' "$1"
    else
        grep -q '^Total: 26 run, 26 passed, 0 failed, 1 skipped' "$1"
    fi
}

# Wait for a background run to take the lock (it writes its pid there), up to ~10s.
wait_for_lock() { # wait_for_lock <work-dir> <pid>
    _i=0
    while [ "$_i" -lt 200 ]; do
        if [ -s "$1/.lock" ] && kill -0 "$2" 2>/dev/null; then return 0; fi
        sleep 0.05
        _i=$((_i + 1))
    done
    return 1
}

# --- case 1: a held lock refuses a run at once, leaving the work directory alone.
w1="$tmp/w1"
mkdir -p "$w1"
exec 8>> "$w1/.lock"
flock -n 8
printf '%s\n' "$$" > "$w1/.lock"
start=$(date +%s)
refused_rc=0
out="$(TR_WORK="$w1" "$TEST_SH" --quiet $WORKLOAD 2>&1)" || refused_rc=$?
elapsed=$(( $(date +%s) - start ))
if [ "$refused_rc" -eq 0 ]; then
    fail "case 1: a run started while the lock was held (exit 0)"
elif ! printf '%s\n' "$out" | grep -qF -- "$LOCKED"; then
    echo "[FAIL] case 1: the refusal does not say '$LOCKED'"
    printf '%s\n' "$out" | sed 's/^/       /'
    errors=$((errors + 1))
elif ! printf '%s\n' "$out" | grep -qF -- "pid $$"; then
    echo "[FAIL] case 1: the refusal does not name the holder (pid $$)"
    printf '%s\n' "$out" | sed 's/^/       /'
    errors=$((errors + 1))
elif [ "$elapsed" -gt 5 ]; then
    fail "case 1: took ${elapsed}s to refuse, expected under 5s"
elif [ -e "$w1/items" ]; then
    fail "case 1: the refused run created $w1/items before checking the lock"
else
    pass "case 1: refusal at once, with pid, without touching the work directory"
fi
exec 8>&-

# --- case 2: a real run holding the lock is left alone, and the second run refuses.
w2="$tmp/w2"
mkdir -p "$w2"
# exec, so $first is the runner itself and SIGSTOP freezes the process that holds the lock.
( exec env TR_WORK="$w2" "$TEST_SH" --quiet $WORKLOAD > "$tmp/first.out" 2>&1 ) &
first=$!
if ! wait_for_lock "$w2" "$first"; then
    kill -9 "$first" 2>/dev/null || true
    fail "case 2: the first run never took the lock"
else
    kill -STOP "$first"
    second_rc=0
    out="$(TR_WORK="$w2" "$TEST_SH" --quiet $WORKLOAD 2>&1)" || second_rc=$?
    kill -CONT "$first"
    if [ "$second_rc" -eq 0 ]; then
        fail "case 2: the second run was not refused (exit 0)"
    elif ! printf '%s\n' "$out" | grep -qF -- "$LOCKED"; then
        echo "[FAIL] case 2: the refusal does not say '$LOCKED'"
        printf '%s\n' "$out" | sed 's/^/       /'
        errors=$((errors + 1))
    fi
    first_rc=0
    wait "$first" || first_rc=$?
    if [ "$first_rc" -ne 0 ]; then
        echo "[FAIL] case 2: the first run exited $first_rc, expected 0 (it should be unaffected)"
        sed 's/^/       /' "$tmp/first.out"
        errors=$((errors + 1))
    elif ! whole_suite "$tmp/first.out"; then
        echo "[FAIL] case 2: the first run did not report its whole suite"
        sed 's/^/       /' "$tmp/first.out"
        errors=$((errors + 1))
    else
        pass "case 2: a real run keeps the lock, the second refuses, the first completes"
    fi
fi

# --- case 3: separate work directories run at the same time.
w3="$tmp/w3"; w4="$tmp/w4"
mkdir -p "$w3" "$w4"
( exec env TR_WORK="$w3" "$TEST_SH" --quiet $WORKLOAD > "$tmp/third.out" 2>&1 ) & third=$!
( exec env TR_WORK="$w4" "$TEST_SH" --quiet $WORKLOAD > "$tmp/fourth.out" 2>&1 ) & fourth=$!
third_rc=0; wait "$third" || third_rc=$?
fourth_rc=0; wait "$fourth" || fourth_rc=$?
if [ "$third_rc" -ne 0 ] || [ "$fourth_rc" -ne 0 ]; then
    echo "[FAIL] case 3: runs in separate work directories exited $third_rc and $fourth_rc, expected 0"
    sed 's/^/       /' "$tmp/third.out"
    sed 's/^/       /' "$tmp/fourth.out"
    errors=$((errors + 1))
else
    pass "case 3: two runs with different TR_WORK both complete"
fi

# --- case 4: a SIGKILLed dispatcher takes its pool with it and frees the lock.
# SIGKILL cannot be trapped, so this holds for two reasons: a worker checks that its dispatcher is
# alive before running an item and again before reporting, and the pool opens the FIFO read-write,
# so it is a reader for its own `end` write. Without them the pool survives forever - 17 workers in
# `open()` on the readerless FIFO (`wait_for_partner`), xargs waiting for them, the pool subshell
# waiting for xargs - and the work directory stays locked, refusing every later run.
w5="$tmp/w5"
mkdir -p "$w5"
( exec env TR_WORK="$w5" "$TEST_SH" --quiet $WORKLOAD > "$tmp/killed.out" 2>&1 ) &
victim=$!
if ! wait_for_lock "$w5" "$victim"; then
    kill -9 "$victim" 2>/dev/null || true
    fail "case 4: the run to kill never took the lock"
else
    sleep 0.2 # let the pool start, so the kill lands on a run in flight
    kill -9 "$victim" 2>/dev/null || true
    # Nobody intervenes: the pool has to notice by itself, within one item's time. The work
    # directory's lock is the oracle, and it has to be scoped to this run: the pool and every worker
    # inherit the lock descriptor, so the lock becoming free IS the proof that no worker survived.
    # (A `pgrep` for the script path would also match the run that is executing this very test, and
    # killing those processes wedges that run on its FIFO - the pool never writes `end` - which is
    # exactly the bug this file is about, so never signal anything but $w5's own processes here.)
    _i=0
    lock_free=0
    while [ "$_i" -lt 600 ]; do
        if flock -n "$w5/.lock" -c true 2>/dev/null; then lock_free=1; break; fi
        sleep 0.1
        _i=$((_i + 1))
    done
    if [ "$lock_free" -eq 0 ]; then
        fail "case 4: the killed run still holds the lock on $w5 after 60s (its pool survived)"
        # Unwedge this run's own work directory, so a failure here cannot block the suite that runs
        # this test: the pool records its pid, which is also its process group.
        if [ -e "$w5/items/pool.pid" ]; then
            _pp=$(cat "$w5/items/pool.pid" 2>/dev/null)
            [ -n "$_pp" ] && kill -9 "-$_pp" 2>/dev/null
        fi
    else
        again_rc=0
        TR_WORK="$w5" "$TEST_SH" --quiet $WORKLOAD > "$tmp/again.out" 2>&1 || again_rc=$?
        if [ "$again_rc" -ne 0 ]; then
            echo "[FAIL] case 4: a new run on the killed run's TR_WORK exited $again_rc, expected 0"
            sed 's/^/       /' "$tmp/again.out"
            errors=$((errors + 1))
        elif ! whole_suite "$tmp/again.out"; then
            echo "[FAIL] case 4: the new run did not report its whole suite"
            sed 's/^/       /' "$tmp/again.out"
            errors=$((errors + 1))
        else
            pass "case 4: a killed dispatcher takes its pool, and the work directory is reusable"
        fi
    fi
fi

[ "$errors" -eq 0 ]
