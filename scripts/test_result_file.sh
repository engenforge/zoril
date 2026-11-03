#!/bin/sh
# scripts/test_result_file.sh — the runner reads a worker's result only once it is whole, and keeps the
# worker's output when a result really is missing.
#
# scripts/test.sh runs each item in a worker that writes $ITEMS/N.out and then $ITEMS/N.st (its four
# counts) and tells the dispatcher over a FIFO. The dispatcher decides an item is done when N.st
# *exists*. The worker used to create N.st with `echo ... > N.st`, which makes the file empty before it
# writes it, so a dispatcher that looked in between read an empty result and reported a passing item as
# "the worker left no result" - a different test on each run, more often on a loaded host. A rename within
# one directory is atomic: the worker now writes N.st.tmp and renames it, so the dispatcher sees no file
# or the whole file.
#
# The race is a gap of microseconds, so this does not wait for it. TR_TEST_ST_DELAY=IDX:SECONDS is a hook
# in the worker's status write (scripts/test.sh, write_status) that holds item IDX for SECONDS between
# opening the status file and writing it; nothing but this test sets it. With it:
#
#   1. three tests at two jobs, item 1 held for 3 s: item 2's report wakes the dispatcher while item 1's
#      status file is open and empty. Every item must pass and nothing may be "left no result".
#   2. a worker killed while held (a result that is really missing) is reported as "left no result", and
#      the item's .out keeps what the worker wrote before the line is added.
#
# Usage: test_result_file.sh      (no arguments)
cd "$(dirname "$0")/.." || exit 2

# Its own work directory and settings: this usually runs inside another test.sh run, whose exported
# options would otherwise leak in.
export TR_WORK=build/tests-result-file TR_QUIET=0 TR_VERBOSE=0 TR_FAIL_FAST=0 TR_FILTER= TR_RESULTS=
rm -rf "$TR_WORK"
mkdir -p "$TR_WORK"
unset TR_TEST_ST_DELAY

TESTS="tests/language/basic/bool_int_strict.zrl tests/language/basic/comparison_operators.zrl tests/language/basic/float_comparisons.zrl"
errors=0
fail() { echo "[FAIL] result-file: $1"; errors=$((errors + 1)); }
pass() { echo "[PASS] result-file: $1"; }

# 1. a held write must not be read half done
out="$TR_WORK/held.out"
TR_TEST_ST_DELAY=1:3 timeout 120 ./scripts/test.sh -j 2 $TESTS > "$out" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && ! grep -qF "left no result" "$out" && grep -qE '^Total: [0-9]+ run, [0-9]+ passed, 0 failed' "$out"; then
    pass "a status file held open and empty for 3 s is not read: every test passes, none is \"left no result\""
else
    fail "with item 1's status write held (exit $rc), the runner should pass every test:"
    sed 's/^/       /' "$out"
fi

# 2. a result that is really missing keeps the worker's output and gets the line appended
out="$TR_WORK/killed.out"
rm -rf "$TR_WORK/items"    # the first run's items, or the wait below would see its 1.out
TR_TEST_ST_DELAY=1:4 timeout 120 ./scripts/test.sh -j 1 tests/language/basic/bool_int_strict.zrl > "$out" 2>&1 &
run=$!
i=0
while [ ! -s "$TR_WORK/items/1.out" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
worker=$(ps -eo pid=,args= | awk '/test\.sh --worker 1 / { print $1; exit }')
if [ -n "$worker" ]; then kill -KILL "$worker" 2>/dev/null; fi
wait "$run"
if [ -z "$worker" ]; then
    fail "could not find the held worker to kill"
elif [ "$(sed -n 1p "$TR_WORK/items/1.out")" = "$(grep -m1 '^\[PASS\] tests/language/basic/bool_int_strict.zrl' "$TR_WORK/items/1.out")" ] \
     && grep -qF "[PASS] tests/language/basic/bool_int_strict.zrl" "$TR_WORK/items/1.out" \
     && grep -qF "(the worker left no result)" "$TR_WORK/items/1.out" \
     && grep -qF "(the worker left no result)" "$out"; then
    pass "a worker killed before its status exists is \"left no result\", and its own output is kept in the item's .out"
else
    fail "the killed worker's .out should hold its [PASS] line and then the \"left no result\" line:"
    sed 's/^/       /' "$TR_WORK/items/1.out"
fi

if [ "$errors" -ne 0 ]; then
    echo "FAIL: the runner's result files are not read safely."
    exit 1
fi
rm -rf "$TR_WORK"
echo "PASS: the runner reads a result only once it is whole."
