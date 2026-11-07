#!/bin/sh
# scripts/test_mutation_check.sh — the mutation harness's own self-test (a make test gate).
#
# Why this exists. For a time the harness staged a copy of `stdlib/` for every mutant, and every
# mutant's suite run failed `tests/language/modules/strict_name_errors.zrl` - a test the baseline
# passed - because that test's EXPECT pinned the *include root* in a diagnostic's path and the
# mutant compiled with `-I build/mutation/<id>/stdlib`. `NEW=$(comm -13 baseline/fails
# mutant/fails)` could therefore never come out empty: every mutation was reported as caught, and
# the harness's SURVIVED verdict - the one it exists to produce - was unreachable. Two rounds of
# "all mutations caught" under it were not evidence, and this gate is what keeps that from
# happening again quietly.
#
# It runs the harness against four canary mutations of its own (`scripts/mutation_selftest.list`),
# in its own stage and cache directory:
#
#   C1  a comment-only edit in `src/`, which changes no behaviour: must be reported SURVIVED
#   C2  one diagnostic's wording changed, which exactly one located error test pins: must be
#       reported caught by that test
#   C4  a comment-only edit in `src/`: control canary for incremental compilation (-c / .zri),
#       must survive
#   C5  an interface canary in `src/verify.zrl`: caught by the incremental scenario
#
# A harness that cannot produce either verdict fails here. Cost: four mutant builds and evaluations
# run in parallel, about a minute and a half on 16 cores - which is why this gate is last in
# scripts/test.sh's GATES_ALL, whose order is the display order.
set -u
cd "$(dirname "$0")/.." || exit 2

WORK=build/mutation_selftest
LIST=scripts/mutation_selftest.list
C1_CATCHER=""
C2_CATCHER="ec_bool_logical_int"   # the harness reports the catcher as a basename, no directory or extension

rm -rf "$WORK"
mkdir -p "$WORK"
report="$WORK/report.log"

canary_suite="$WORK/canary_suite.list"
cat tests/smoke.list > "$canary_suite"
echo "tests/error_reporting/ec_bool_logical_int.zrl" >> "$canary_suite"
echo "tests/interproc_summary/cross_module/global_stash_caller.zrl" >> "$canary_suite"

report_c1="$WORK/report_c1.log"
r1_rc=0
MUTATION_LIST="$LIST" MUTATION_STAGE="$WORK/stage_c1" MUTATION_CACHE="$WORK/cache" \
    ./scripts/mutation-check.sh C1 > "$report_c1" 2>&1 || r1_rc=$?

list_rest="$WORK/list_rest"
grep -v '^C1@@' "$LIST" > "$list_rest"
report_rest="$WORK/report_rest.log"
r2_rc=0
MUTATION_LIST="$list_rest" MUTATION_SUITE="$canary_suite" MUTATION_STAGE="$WORK/stage_rest" MUTATION_CACHE="$WORK/cache" \
    ./scripts/mutation-check.sh > "$report_rest" 2>&1 || r2_rc=$?

cat "$report_c1" "$report_rest" > "$report"
mkdir -p "$WORK/stage"
cat "$WORK/stage_c1/survivors" "$WORK/stage_rest/survivors" > "$WORK/stage/survivors" 2>/dev/null || true

rc=0
if [ $r1_rc -ne 0 ] && [ $r2_rc -ne 0 ]; then
    rc=1
fi

# block ID — the report's section for one mutation (its `ID  description` line up to the next).
block() {
    awk -v id="$1" '
        $0 ~ "^" id "  " { inside = 1; print; next }
        inside && /^[A-Z0-9]+  / { exit }
        inside { print }
    ' "$report"
}

fail=0
note() { echo "[FAIL] $*"; fail=1; }

if ! grep -q "^C1  " "$report"; then
    _tail=$(tail -n 10 "$report" | tr '\n' ' ' | sed 's/  */ /g')
    note "the harness never reported C1 (exit $rc): $_tail"
    sed 's/^/       /' "$report" | tail -n 20
    exit 1
fi

if block C1 | grep -q '\*\*\* SURVIVED \*\*\*'; then
    echo "[PASS] a no-op mutation is reported SURVIVED (the verdict the 2026-10-09..12 defect lost)"
else
    c1_caught=$(block C1 | grep 'caught by:' | sed 's/.*caught by: *//; s/ *$//')
    note "C1 (a comment-only edit, no behaviour change) was not reported SURVIVED (caught by: '${c1_caught:-unknown}'):"
    block C1 | sed 's/^/       /'
fi

c2=$(block C2 | grep 'caught by:' | sed 's/.*caught by: *//; s/ *$//')
if [ "$c2" = "$C2_CATCHER" ]; then
    echo "[PASS] a changed diagnostic is reported caught by $C2_CATCHER"
else
    note "C2 (a changed diagnostic) was not reported caught by $C2_CATCHER (got: '${c2:-nothing}')"
    block C2 | sed 's/^/       /'
fi

survivors=$(sed -n 's/@@.*//p' "$WORK/stage/survivors" 2>/dev/null | tr '\n' ' ')
if [ "$survivors" = "C1 C4 " ]; then
    echo "[PASS] exactly the no-op canary survived ($survivors)"
else
    note "the survivor list is '${survivors:-empty}', expected exactly 'C1 C4 '"
fi

# A malformed list must fail at once, with the line number, in `--changed` mode too. An orphaned
# continuation line used to be read as a mutation with an empty id and file, and `--changed` dropped it
# silently, so `preflight-changed` passed while the full gate went red.
bad="$WORK/bad.list"
{ echo "M9001@@src/main.zrl@@a@@b@@reason"; echo; echo "  orphaned continuation line"; } > "$bad"
if MUTATION_LIST="$bad" MUTATION_STAGE="$WORK/badstage" MUTATION_CACHE="$WORK/badcache" MUTATION_CHANGED="src/main.zrl" \
   "$(dirname "$0")/mutation-check.sh" --changed > "$WORK/bad.log" 2>&1; then
    note "a malformed list was accepted in --changed mode"
elif grep -q 'list line 3' "$WORK/bad.log"; then
    echo "[PASS] a malformed list fails at once, naming the line"
else
    note "a malformed list failed without naming the line: $(head -2 "$WORK/bad.log" | tr '\n' ' ')"
fi

# The incremental path's guard is the control canary C4 in the survivors set above: a scenario that
# never ran, or that failed for an unrelated reason, reports it caught. There is no positive canary for
# this path yet - see the note in scripts/mutation_incremental.list.

if grep -A2 '^C5' "$WORK/report.log" 2>/dev/null | grep -q 'caught by:'; then
    echo "[PASS] the interface canary C5 is caught by the incremental scenario"
else
    note "the interface canary C5 was not reported caught (see $WORK/report.log)"
fi

if [ $rc -eq 0 ]; then
    note "the harness exited 0 with a surviving canary: a survivor must fail the run"
fi

# A fixture stage with a wrong stamp is cleaned and restamped with the current toolchain stamp.
stale_stage="$WORK/stale_stage"
mkdir -p "$stale_stage"
echo "wrong_compiler_commit_12345" > "$stale_stage/stamp"
touch "$stale_stage/old_file_marker"

MUTATION_LIST=/dev/null MUTATION_STAGE="$stale_stage" MUTATION_CACHE="$WORK/cache" \
    "$(dirname "$0")/mutation-check.sh" > "$WORK/stale_stamp.log" 2>&1 || true

if [ -f "$stale_stage/old_file_marker" ]; then
    note "a fixture stage with a wrong stamp was not cleaned"
elif [ -f "$stale_stage/stamp" ] && grep -qv "wrong_compiler_commit_12345" "$stale_stage/stamp"; then
    echo "[PASS] a fixture stage with a wrong stamp is rebuilt and restamped"
else
    note "a fixture stage with a wrong stamp did not get restamped properly"
fi

# A list where every mutant breaks the compiler build must stop with "the mutation stage is stale or broken"
broken_list="$WORK/broken_build.list"
echo "B1@@src/main.zrl@@fn main@@SYNTAX ERROR IN COMPILER@@breaks compiler build" > "$broken_list"

broken_rc=0
MUTATION_LIST="$broken_list" MUTATION_STAGE="$WORK/broken_stage" MUTATION_CACHE="$WORK/cache" \
    "$(dirname "$0")/mutation-check.sh" > "$WORK/broken.log" 2>&1 || broken_rc=$?

if [ "$broken_rc" -eq 2 ] && grep -q 'the mutation stage is stale or broken' "$WORK/broken.log"; then
    echo "[PASS] a run where every mutant fails to build stops with 'the mutation stage is stale or broken'"
else
    note "a run where every mutant fails to build did not report the stale/broken stage message (rc $broken_rc): $(cat "$WORK/broken.log")"
fi

# A run following an early-exiting run with a surviving mutant resets result files and does not
# falsely report stale survivors (Z-0069).
stale_surv_stage="$WORK/stale_surv_stage"
rm -rf "$stale_surv_stage"
mkdir -p "$stale_surv_stage"

r1_rc=0
MUTATION_LIST="$LIST" MUTATION_SUITE="$canary_suite" MUTATION_STAGE="$stale_surv_stage" MUTATION_CACHE="$WORK/cache" \
    "$(dirname "$0")/mutation-check.sh" C1 > "$WORK/surv_run1.log" 2>&1 || r1_rc=$?

r2_rc=0
MUTATION_LIST="$LIST" MUTATION_SUITE="$canary_suite" MUTATION_STAGE="$stale_surv_stage" MUTATION_CACHE="$WORK/cache" \
    "$(dirname "$0")/mutation-check.sh" C2 > "$WORK/surv_run2.log" 2>&1 || r2_rc=$?

if [ "$r1_rc" -eq 1 ] && [ "$r2_rc" -eq 0 ]; then
    echo "[PASS] a run following a surviving mutant passes without reporting stale survivors"
else
    note "stale survivor leaked into next run: run1 rc=$r1_rc, run2 rc=$r2_rc (see $WORK/surv_run2.log)"
fi

[ $fail -eq 0 ] || exit 1
exit 0
