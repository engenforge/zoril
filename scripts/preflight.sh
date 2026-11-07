#!/bin/sh
# scripts/preflight.sh — full or fast pre-merge verification.
#
# Usage:
#   scripts/preflight.sh            full preflight (selfhost + mutation + bench + density + fuzz)
#   scripts/preflight.sh --changed  fast preflight for changed files (selfhost + mutation --changed + bench)
#
# Both pre-merge gates run selfhost-check (a clean copy of the tree builds with the DEFAULT
# rules — the fresh-checkout path — plus the self-hosting fixpoint) in the BACKGROUND,
# beside mutation-check, and WAIT for it before the bench step: the bench thresholds refuse a
# loaded host, so nothing else may still be running when they start.
set -u
cd "$(dirname "$0")/.." || exit 2
. scripts/lib/portability.sh
. scripts/lib/preflight_base.sh

changed=0
while [ $# -gt 0 ]; do
    case "$1" in
        --changed) changed=1; shift ;;
        -h|--help)
            sed -n '2,/^[^#]/ { /^[^#]/d; s/^# \{0,1\}//; p; }' "$0"
            exit 0
            ;;
        *)
            echo "preflight.sh: unknown option '$1'" >&2
            exit 2
            ;;
    esac
done

SELFHOST_CMD="${PREFLIGHT_SELFHOST:-./scripts/selfhost-check.sh}"
MUTATION_CMD="${PREFLIGHT_MUTATION:-./scripts/mutation-check.sh}"
CALIBRATE_CMD="${PREFLIGHT_CALIBRATE:-./scripts/check_fuzz_calibrate.sh}"
BENCH_CMD="${PREFLIGHT_BENCH:-./scripts/bench_threshold_check.sh}"
STORE_GRID_CMD="${PREFLIGHT_STORE_GRID:-./scripts/check_store_grid.sh}"
DENSITY_CMD="${PREFLIGHT_DENSITY:-./scripts/record_marker_density.sh}"
FUZZ_CMD="${PREFLIGHT_FUZZ:-./scripts/fuzz_safe.sh}"
GIT_CMD="${PREFLIGHT_GIT:-./scripts/test.sh --quiet --group git}"
LOG="${PREFLIGHT_LOG:-build/preflight-selfhost.log}"
TIMINGS="${PREFLIGHT_TIMINGS:-build/preflight-timings.tsv}"
unset PREFLIGHT_TIMINGS PREFLIGHT_LOG

# Check dependencies for preflight (test tools, timeout, git, bench thresholds, fuzzing)
./scripts/check_deps.sh preflight || exit $?

mkdir -p build "$(dirname "$LOG")" "$(dirname "$TIMINGS")"
: > "$TIMINGS"

record_step() {
    printf '%d\t%s\n' "$2" "$1" >> "$TIMINGS"
}

# A --changed run measures the change against a base (scripts/lib/preflight_base.sh). Without one,
# the mutations and the differential compare the tree with itself and find nothing, so the gate
# would pass having checked nothing: refuse instead, before anything starts.
PF_BASE=""
PF_BASE_WHY=""
if [ "$changed" -eq 1 ]; then
    if ! preflight_base; then
        echo "[FAIL] preflight-changed: no base to check the change against: $PF_BASE_ERR" >&2
        exit 1
    fi
    echo "preflight-changed: base $PF_BASE ($PF_BASE_WHY)"

    # A --changed run skips only when every changed file matches a doc-only tier row;
    # a script or test edit still runs the preflight steps that verify it (Z-0129).
    pf_flags=$( (git diff --name-only --no-renames "$PF_BASE" 2>/dev/null || true; git ls-files --others --exclude-standard 2>/dev/null || true) | sort -u | ./scripts/select_test_tier.sh --flags )
    if [ "$pf_flags" = "doc" ]; then
        echo "[SKIP] preflight-changed: only documentation changed since $PF_BASE ($PF_BASE_WHY)"
        exit 0
    fi
fi

# selfhost-check in the background
sh_start=$(date +%s)
$SELFHOST_CMD > "$LOG" 2>&1 &
selfhost=$!

# mutation-check in the foreground
mut_start=$(date +%s)
mutation=0
if [ "$changed" -eq 1 ]; then
    MUTATION_BASE="$PF_BASE" $MUTATION_CMD --changed || mutation=$?
else
    $MUTATION_CMD || mutation=$?
fi
record_step mutation $(( $(date +%s) - mut_start ))

wait $selfhost
status=$?
record_step selfhost $(( $(date +%s) - sh_start ))

echo
cat "$LOG"

prefix="preflight"
[ "$changed" -eq 1 ] && prefix="preflight-changed"

if [ $status -ne 0 ] || [ $mutation -ne 0 ]; then
    echo "$prefix: selfhost-check exit $status, mutation-check exit $mutation (log: $LOG)" >&2
    exit 1
fi

cal_start=$(date +%s)
$CALIBRATE_CMD
cal_rc=$?
record_step calibrate $(( $(date +%s) - cal_start ))
[ $cal_rc -eq 0 ] || exit $cal_rc

# The rejection differential (AGENTS.md): a change to what decides acceptance is compared with its base.
# The base is PREFLIGHT_REJECT_BASE if set; else, for --changed, the base chosen above; else (the full
# preflight) HEAD when the working tree differs from it, and the upstream branch otherwise. It builds the
# base compiler (about 4 min on 16 cores), so it is skipped, saying so, when none of the files that decide
# acceptance differs from the base: the checkers, what reaches them (the parser, the lowering, the
# driver, the interface printer, main), and stdlib (whose summaries affect what checkers refuse).
REJECT_DIFF_CMD="${PREFLIGHT_REJECT_DIFF:-./scripts/check_reject_diff.sh}"
REJECT_PATHS="src/summary_pass.zrl src/check_zir.zrl src/verify.zrl src/main.zrl src/interface_print.zrl src/driver src/lower_zir src/parser src/parser.zrl src/ast.zrl stdlib"
if [ -n "${PREFLIGHT_REJECT_BASE:-}" ]; then
    reject_base="$PREFLIGHT_REJECT_BASE"; reject_why="PREFLIGHT_REJECT_BASE"
elif [ -n "$PF_BASE" ]; then
    reject_base="$PF_BASE"; reject_why="$PF_BASE_WHY"
elif ! git diff --quiet HEAD 2>/dev/null; then
    reject_base=HEAD; reject_why="the working tree against HEAD"
elif git rev-parse --verify '@{upstream}' > /dev/null 2>&1; then
    reject_base='@{upstream}'; reject_why="HEAD against $(git rev-parse --abbrev-ref '@{upstream}')"
else
    reject_base=HEAD; reject_why="no upstream: the working tree against HEAD"
fi
# shellcheck disable=SC2086
if git diff --quiet "$reject_base" -- $REJECT_PATHS 2>/dev/null; then
    echo "[SKIP] reject-diff: none of $REJECT_PATHS differs from $reject_base ($reject_why; PREFLIGHT_REJECT_BASE=<commit> compares with another base)"
    record_step reject-diff 0
else
    echo "reject-diff: $reject_why"
    rd_start=$(date +%s)
    $REJECT_DIFF_CMD "$reject_base"
    rd_rc=$?
    rd_dur=$(( $(date +%s) - rd_start ))
    record_step reject-diff "$rd_dur"
    echo "reject-diff: $rd_dur s"
    [ $rd_rc -eq 0 ] || exit $rd_rc
fi

# The checked build and the git group run BEFORE the bench step on purpose. The bench step
# appends to bench/*_history.tsv and rewrites bench/cross_lang/last_zoril_metrics.tsv, which makes the
# working tree dirty; `tool-versions` compares each tool's stamped version against the tree as
# it is when the test runs, and `clean-tree` / `preflight-selftest` in the git group assert a clean
# tree. Nothing in the checked suite or git group depends on the bench.
CHECKED_CMD="${PREFLIGHT_CHECKED:-./scripts/test_checked.sh}"
chk_start=$(date +%s)
$CHECKED_CMD
chk_rc=$?
record_step checked $(( $(date +%s) - chk_start ))
[ $chk_rc -eq 0 ] || exit $chk_rc

if [ "$changed" -eq 0 ]; then
    git_start=$(date +%s)
    TR_WORK=build/tests-git $GIT_CMD
    git_rc=$?
    record_step git $(( $(date +%s) - git_start ))
    [ $git_rc -eq 0 ] || exit $git_rc
fi

bench_start=$(date +%s)
$BENCH_CMD
bench_rc=$?
record_step bench $(( $(date +%s) - bench_start ))
[ $bench_rc -eq 0 ] || exit $bench_rc

if [ "$changed" -eq 0 ]; then
    sg_start=$(date +%s)
    $STORE_GRID_CMD
    sg_rc=$?
    record_step store-grid $(( $(date +%s) - sg_start ))
    [ $sg_rc -eq 0 ] || exit $sg_rc

    den_start=$(date +%s)
    $DENSITY_CMD
    den_rc=$?
    record_step density $(( $(date +%s) - den_start ))
    [ $den_rc -eq 0 ] || exit $den_rc

    fuzz_findings=$(mktemp -d)
    fuzz_start=$(date +%s)
    FUZZ_FINDINGS="$fuzz_findings" $FUZZ_CMD --seeds 1-25 --count 4 --mode mix
    fuzz_rc=$?
    record_step fuzz $(( $(date +%s) - fuzz_start ))
    rm -rf "$fuzz_findings"
    [ $fuzz_rc -eq 0 ] || exit $fuzz_rc
fi
