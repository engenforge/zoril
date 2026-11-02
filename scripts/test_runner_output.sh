#!/bin/sh
# scripts/test_runner_output.sh — test the test runner's output format.
#
# People and AIs read `make test` by grepping for '[FAIL]' and 'Total:'. That only works
# while every line has one of a few shapes, so this runs scripts/test.sh over fixtures that
# pass, fail and skip (tests/runner/fixtures/), including gates that misbehave, in each
# output mode, and checks:
#   - every line matches the grammar documented in scripts/test.sh;
#   - exactly one Total line, and it is the last line;
#   - one [FAIL] line per failed item, and no other line contains "[FAIL]" (so an unanchored
#     grep counts failures); in the default mode one [PASS]/[SKIP] line per
#     passed/skipped item; --quiet prints no [PASS] or [SKIP] lines;
#   - the suite lines add up to the Total, and the Total and exit status are as expected.
# Gate scripts themselves are held to the item format on every run by scripts/test.sh.

cd "$(dirname "$0")/.." || exit 2
. scripts/lib/path_shim.sh
. scripts/lib/portability.sh

# Its own work directory and settings: this usually runs inside another test.sh run,
# whose exported options would otherwise leak in.
export TR_WORK=build/tests-runner-output TR_QUIET=0 TR_VERBOSE=0 TR_FAIL_FAST=0 TR_FILTER= TR_RESULTS=
FIXTURES="tests/runner/fixtures/tests --gate fixture-good --gate fixture-fails
          --gate fixture-bad-format --gate fixture-silent-failure --gate fixture-empty"
# 13 fixture items, plus the run's own "stray-files" item, which needs git: with git hidden from
# PATH (opts_hidden), or absent on the host, it is reported as [SKIP] instead of [PASS].
EXPECTED_TOTAL="Total: 14 run, 7 passed, 7 failed, 2 skipped"
EXPECTED_TOTAL_NO_GIT="Total: 13 run, 6 passed, 7 failed, 3 skipped"

errors=0
fail() { echo "[FAIL] $1"; errors=$((errors + 1)); }

check_mode() {
    mode="$1"
    out="$TR_WORK/output.$mode"
    expected="$EXPECTED_TOTAL"
    # git is optional; without it on the host the stray-files item skips in every mode, which is the
    # total opts_hidden pins with git explicitly hidden.
    git_checkout_usable . || expected="$EXPECTED_TOTAL_NO_GIT"
    mkdir -p "$TR_WORK"
    case "$mode" in
        quiet)   ./scripts/test.sh --quiet $FIXTURES > "$out" 2>&1 ;;
        default) ./scripts/test.sh $FIXTURES > "$out" 2>&1 ;;
        verbose) ./scripts/test.sh --verbose $FIXTURES > "$out" 2>&1 ;;
        opts_hidden)
            shim="$TR_WORK/shim_opts"
            path_without "$shim" git timeout setsid valgrind dprint rustc
            expected="$EXPECTED_TOTAL_NO_GIT"
            PATH="$shim" ./scripts/test.sh $FIXTURES > "$out" 2>&1
            ;;
    esac
    rc=$?
    [ $rc -eq 1 ] || fail "$mode: exit status $rc, expected 1 (there are failing fixtures)"

    # Every line has one of the documented shapes.
    bad=$(awk '
        /^\[(PASS|FAIL|SKIP)\] [^ ]/ { next }                       # item
        /^       / { next }                                         # detail of the item above
        /^(Gates|Tests)$/ { next }                                  # section heading
        /^  [^ \[].* +[0-9]+ run +[0-9]+ passed +[0-9]+ failed +[0-9]+ skipped$/ { next }
        /^Total: [0-9]+ run, [0-9]+ passed, [0-9]+ failed, [0-9]+ skipped \([0-9.]+s\)$/ { next }
        { printf "line %d: %s\n", NR, $0 }' "$out")
    [ -z "$bad" ] || fail "$mode: lines outside the output grammar:
$(echo "$bad" | head -n 5 | sed 's/^/       /')"

    totals=$(grep -c '^Total: ' "$out")
    [ "$totals" -eq 1 ] || fail "$mode: $totals Total lines, expected 1"
    tail -n 1 "$out" | grep -q '^Total: ' || fail "$mode: the last line is not the Total"
    case "$(grep '^Total: ' "$out")" in
        "$expected"*) ;;
        *) fail "$mode: $(grep '^Total: ' "$out"), expected $expected" ;;
    esac

    # One line per item, and the suites add up to the Total.
    eval "$(sed -n 's/^Total: \([0-9]*\) run, \([0-9]*\) passed, \([0-9]*\) failed, \([0-9]*\) skipped.*/run=\1 passed=\2 failed=\3 skipped=\4/p' "$out")"
    n_fail=$(grep -c '^\[FAIL\] ' "$out")
    # Unanchored too: a plain `grep '[FAIL]'` must count failures, not log text in details.
    n_any=$(grep -c '\[FAIL\]' "$out")
    [ "$n_any" -eq "$n_fail" ] || fail "$mode: $n_any lines contain [FAIL] but only $n_fail are failed items"
    n_pass=$(grep -c '^\[PASS\] ' "$out")
    n_skip=$(grep -c '^\[SKIP\] ' "$out")
    [ "$n_fail" -eq "${failed:-x}" ] || fail "$mode: $n_fail [FAIL] lines for $failed failed items"
    if [ "$mode" = quiet ]; then
        [ "$n_pass" -eq 0 ] && [ "$n_skip" -eq 0 ] || fail "$mode: --quiet printed [PASS] or [SKIP] lines"
    else
        [ "$n_pass" -eq "${passed:-x}" ] || fail "$mode: $n_pass [PASS] lines for $passed passed items"
        [ "$n_skip" -eq "${skipped:-x}" ] || fail "$mode: $n_skip [SKIP] lines for $skipped skipped items"
    fi
    sums=$(awk '/^  [^ ].* run .* skipped$/ { r += $(NF-7); p += $(NF-5); f += $(NF-3); s += $(NF-1) }
                END { printf "%d %d %d %d", r, p, f, s }' "$out")
    [ "$sums" = "$run $passed $failed $skipped" ] || fail "$mode: suite lines sum to $sums, Total says $run $passed $failed $skipped"

}

for mode in quiet default verbose opts_hidden; do
    before=$errors
    check_mode "$mode"
    if [ $errors -eq $before ]; then
        echo "[PASS] $mode output follows the grammar and its counts agree"
    else
        echo "       output: $TR_WORK/output.$mode"
    fi
done
[ $errors -eq 0 ]
