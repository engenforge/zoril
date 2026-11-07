#!/bin/sh
# scripts/fuzz_jobs.sh -- run the fuzzer over disjoint seed ranges, N at a time, and sum the results.
#
# The serial driver stays serial. Each worker is an ordinary `fuzz_safe.sh` run with its own output
# directory and its own `TR_WORK`, and the only thing that crosses a process boundary is one
# machine-readable totals line per worker (`fuzz-totals:`), summed here with awk. That is why the
# parallelism lives outside the driver: an earlier in-driver attempt summed counters in the parent and
# read zero for every one of them while the coverage - merged through a file - came out right, and a
# fuzzer whose numbers cannot be trusted is worse than a slow one.
#
# A worker that *finds* something is not a worker that failed to run. The driver exits 1 when it reports a
# candidate, a fault or an expired entry, and 2 when it cannot run at all (no toolchain, no lua); only the
# second - or a worker that never printed its totals - stops the run on the spot. A reporting worker's
# totals are summed like any other's, the summary is printed, and the run then fails because of the
# finding. Telling those two apart is not a nicety: an exit status is all that crosses the process
# boundary here, so reading every non-zero one as a broken worker loses the run's numbers exactly when a
# finding makes them worth having.
#
#
# While it runs the wrapper keeps the run directory readable from outside: run.status (state, start,
# arguments), one w<k>.status heartbeat per worker, a banner, a [STATUS] line every --status-every minutes
# and every finding copied into this log as it appears (see scripts/lib/fuzz_progress.sh and
# `make fuzz-status`).
#
# Usage: scripts/fuzz_jobs.sh [--jobs N] [--ran N] [--status-every MIN] [whatever fuzz_safe.sh takes]
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/portability.sh" 2>/dev/null || true
. "$HERE/lib/tree_files.sh" 2>/dev/null || true
. "$HERE/lib/fuzz_progress.sh"
DRIVER="$HERE/fuzz_safe.sh"
GEN="${FUZZ_GEN:-$HERE/fuzz/gen.lua}"

JOBS=""; SEEDS=""; COUNT=""; MODE=""; OUT=""; TIMEOUT=""; KEEP=""; NOCOV=""; REVERIFY=""
ZBUILD_OPT=""
FINDINGS=""; RECORD=""; STRICT=""; RELEASE=""; CHECKED="--checked"; RAN_TARGET=""; STATUS_MIN=5
ORIG_ARGS="$*"
while [ $# -gt 0 ]; do
    case "$1" in
        --jobs) JOBS=$2; shift 2 ;;
        --seeds) SEEDS=$2; shift 2 ;;
        --count) COUNT=$2; shift 2 ;;
        --mode) MODE=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        --timeout) TIMEOUT=$2; shift 2 ;;
        --findings) FINDINGS=$2; shift 2 ;;
        --record-findings) RECORD=1; STRICT=1; shift ;;
        --release) STRICT=1; RELEASE=1; shift ;;
        --keep) KEEP=1; shift ;;
        --no-coverage) NOCOV=1; shift ;;
        --checked) CHECKED="--checked"; shift ;;
        --no-checked) CHECKED="--no-checked"; shift ;;
        --zbuild) ZBUILD_OPT=1; shift ;;
        --no-zbuild) ZBUILD_OPT=0; shift ;;
        --reverify) REVERIFY=1; shift ;;
        --ran) RAN_TARGET=$2; shift 2 ;;
        --status-every) STATUS_MIN=$2; shift 2 ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "fuzz: unknown argument $1" >&2; exit 2 ;;
    esac
done

# Reverify re-runs a handful of recorded programs, so there is nothing to spread.
if [ -n "$REVERIFY" ]; then exec "$DRIVER" --reverify ${FINDINGS:+--findings "$FINDINGS"}; fi
if [ -z "$JOBS" ]; then JOBS=$(nproc_count 2>/dev/null || echo 4); fi
case "$JOBS" in ''|*[!0-9]*) echo "fuzz: --jobs needs a number" >&2; exit 2 ;; esac
[ "$JOBS" -lt 1 ] && JOBS=1                      # `--jobs 0` would divide by zero below
[ -n "$COUNT" ] || COUNT=3                       # the driver's default; an empty one tested nothing

first=${SEEDS%-*}; last=${SEEDS#*-}
[ -n "$first" ] || { echo "fuzz: --seeds A-B is required" >&2; exit 2; }
[ -n "$MODE" ] || MODE=both

TMPOUT=0
if [ -z "$OUT" ]; then OUT=$(mktemp -d "${TMPDIR:-/tmp}/zfuzz.jobs.XXXXXX"); TMPOUT=1; fi
mkdir -p "$OUT"
rm -rf "$OUT"/w* "$OUT/cov" "$OUT"/*.log "$OUT/run.status" "$OUT/run.args" "$OUT"/.off*

# A run that will be cited checks its compiler and its oracles once, here, before any worker starts.
if [ -n "$STRICT" ]; then
    . "$HERE/lib/tree_files.sh"
    . "$HERE/lib/fuzz_fresh.sh"
    REPO_ROOT=$(cd "$HERE/.." && pwd)
    fuzz_require_fresh "${ZORIL_BIN:-$REPO_ROOT/build/zoril}" "${ZILC_BIN:-$REPO_ROOT/build/zilc}" $(fuzz_zbuild_bin "$REPO_ROOT" "$ZBUILD_OPT") || exit 2
    fuzz_require_rustc 1 "the --release differential oracle" || exit 2
fi

# The mode-diff reading builds every program with an installed `zbuild` as well: stage the install once here and
# give it to the workers (FUZZ_STAGE), so sixteen of them do not run `make install` over one another.
REPO_ROOT=${REPO_ROOT:-$(cd "$HERE/.." && pwd)}
. "$HERE/lib/tree_files.sh"
. "$HERE/lib/fuzz_fresh.sh"
if [ "$ZBUILD_OPT" = 1 ] || { [ "$ZBUILD_OPT" != 0 ] && fuzz_own_compilers "$REPO_ROOT"; }; then
    FUZZ_STAGE="$OUT/stage"
    make -C "$REPO_ROOT" install-files DESTDIR="$FUZZ_STAGE" PREFIX=/usr > "$OUT/stage.log" 2>&1 \
        || { echo "fuzz: cannot stage an install for the mode-diff reading:" >&2; tail -5 "$OUT/stage.log" >&2; exit 2; }
    export FUZZ_STAGE
fi
span=$((last - first + 1))
[ "$JOBS" -gt "$span" ] && JOBS=$span
per=$(( (span + JOBS - 1) / JOBS ))

# The run, readable from outside: run.status holds what a watcher needs (one key=value per line) and
# w<k>.status is each worker's heartbeat. Liveness is the age of a heartbeat, never `ps`.
HB=${FUZZ_HEARTBEAT_SECS:-60}
START=$(date +%s)
{
    echo "state=running"; echo "start=$START"; echo "pid=$$"; echo "jobs=$JOBS"; echo "first=$first"
    echo "lastseed=$last"; echo "count=$COUNT"; echo "hb=$HB"; echo "mode=$MODE"
    echo "ran_target=${RAN_TARGET:-0}"; echo "release=${RELEASE:-0}"
} > "$OUT/run.status"
printf '%s\n' "$ORIG_ARGS" > "$OUT/run.args"
echo "fuzz: run directory $OUT"
echo "fuzz: seeds $first-$last x $COUNT, mode $MODE, $JOBS worker(s)${RAN_TARGET:+, target $(fmt_num "$RAN_TARGET") compiled and ran}, started $(date -u +%Y-%m-%dT%H:%M:%SZ)"
. "$HERE/lib/tree_files.sh"
. "$HERE/lib/fuzz_fresh.sh"
REPO_ROOT=${REPO_ROOT:-$(cd "$HERE/.." && pwd)}
echo "fuzz: pipeline: $(fuzz_version "${ZORIL_BIN:-$REPO_ROOT/build/zoril}"); $(fuzz_version "${ZILC_BIN:-$REPO_ROOT/build/zilc}")"
set_run_state() {
    set_key "$OUT/run.status" state "$1"
    echo "end=$(date +%s)" >> "$OUT/run.status"
}
k=0; a=$first; pids=""
while [ "$k" -lt "$JOBS" ] && [ "$a" -le "$last" ]; do
    b=$((a + per - 1)); [ "$b" -gt "$last" ] && b=$last
    ms=0; [ "$a" -le "$first" ] && [ "$first" -le "$b" ] && ms=1
    mkdir -p "$OUT/w$k/tr"
    # shellcheck disable=SC2086
    # `--keep` is not optional here: a worker deletes its own output directory when it exits, which is
    # what an earlier in-driver attempt tripped over - the parent read zero for every counter because
    # the workers had already cleaned up, while the coverage it merged happened to be read first. The
    # wrapper's output directory is the one that gets cleaned, and only when it made it itself.
    ( FUZZ_GEN="$GEN" FUZZ_FRESH_CHECKED=${STRICT:+1} MISMATCH_ON_FIRST=$ms TR_WORK="$OUT/w$k/tr" \
        FUZZ_HEARTBEAT_FILE="$OUT/w$k.status" FUZZ_HEARTBEAT_SECS="$HB" "$DRIVER" \
        --seeds "$a-$b" --count "$COUNT" --mode "$MODE" --out "$OUT/w$k" --keep \
        ${TIMEOUT:+--timeout "$TIMEOUT"} ${NOCOV:+--no-coverage} "$CHECKED" \
        ${ZBUILD_OPT:+$([ "$ZBUILD_OPT" = 1 ] && echo --zbuild || echo --no-zbuild)} \
        ${FINDINGS:+--findings "$FINDINGS"} ${RECORD:+--record-findings} ${RELEASE:+--release} ) \
        > "$OUT/w$k.log" 2>&1 &
    pids="$pids $!"
    k=$((k + 1)); a=$((b + 1))
done
# The monitor: every tick it copies a worker's new finding lines into this log (prefixed with the
# worker), and every --status-every minutes it prints the status line (FUZZ_STATUS_SECS overrides the
# interval, for the tests). On a terminal the line is also redrawn in place between the printed ones.
STATUS_SECS=${FUZZ_STATUS_SECS:-$((STATUS_MIN * 60))}
TICK=${FUZZ_MONITOR_TICK:-5}
copy_findings() {
        _k=0
        while [ "$_k" -lt "$JOBS" ]; do
            _log="$OUT/w$_k.log"
            if [ -f "$_log" ]; then
                _seen=$(cat "$OUT/.off$_k" 2>/dev/null || echo 0)
                _have=$(wc -l < "$_log" | tr -d ' ')
                if [ "$_have" -gt "$_seen" ]; then
                    tail -n +$((_seen + 1)) "$_log" | head -n $((_have - _seen)) |
                        grep -E '^\[(FAULT|CANDIDATE|MODE-DIFF|GEN-BUG|EXPIRED|REVERIFY)\]|^\[KNOWN-HOLE\].*still open' |
                        sed "s/^/w$_k: /"
                    echo "$_have" > "$OUT/.off$_k"
                fi
            fi
            _k=$((_k + 1))
        done
}
monitor() {
    _last_status=$(date +%s)
    while :; do
        sleep "$TICK"
        _now=$(date +%s)
        copy_findings
        if [ $((_now - _last_status)) -ge "$STATUS_SECS" ]; then
            status_line "$OUT" "$_now"
            _last_status=$_now
        elif [ -t 1 ]; then
            printf '\r%s' "$(status_line "$OUT" "$_now")"
        fi
    done
}
monitor &
MONITOR_PID=$!
on_term() {
    kill $MONITOR_PID $pids 2>/dev/null
    k=0; while [ "$k" -lt "$JOBS" ]; do
        [ -f "$OUT/w$k.status" ] && ! grep -q 'state=' "$OUT/w$k.status" && echo " state=killed" >> "$OUT/w$k.status"
        k=$((k + 1))
    done
    set_run_state killed
    echo "fuzz: killed; the partial figures are in $OUT"
    exit 143
}
trap on_term TERM INT HUP

# A worker's non-zero exit is not a failure by itself. The driver exits 1 when it *reported* something - a
# candidate, a fault, an expired allowlist entry - and that status is how a finding leaves the worker; the
# totals line is what carries its numbers into this summary, and both are needed. Treating every non-zero
# worker as unusable is what once made a run print "N worker(s) exited non-zero" and no totals at all, so
# the numbers were lost exactly when they mattered. The two cases are told apart here: a worker that
# produced a totals line and exited 1 reported a finding (the run fails below, because of the finding),
# while a worker that produced no totals, or exited for any other reason - 2 is the driver's "toolchain is
# not built", and a kill is a kill - did not run, which this run still refuses.
failed=0; reported=0
k=0
for wp in $pids; do
    wrc=0; wait "$wp" || wrc=$?
    if [ "$wrc" -eq 0 ] || [ "$wrc" -eq 1 ]; then echo " state=finished rc=$wrc" >> "$OUT/w$k.status"; else echo " state=failed rc=$wrc" >> "$OUT/w$k.status"; fi
    if ! grep -q '^fuzz-totals: ' "$OUT/w$k.log" 2>/dev/null; then
        echo "fuzz: worker $k produced no totals (exit $wrc)" >&2
        failed=$((failed + 1))
    elif [ "$wrc" -eq 1 ]; then
        reported=$((reported + 1))
    elif [ "$wrc" -ne 0 ]; then
        echo "fuzz: worker $k exited $wrc after reporting totals" >&2
        failed=$((failed + 1))
    fi
    k=$((k + 1))
done

kill $MONITOR_PID 2>/dev/null; wait $MONITOR_PID 2>/dev/null
copy_findings   # what arrived after the monitor's last tick, so no finding is first seen in the summary
END=$(date +%s)
WALL=$((END - START)); [ "$WALL" -lt 1 ] && WALL=1

# Sum the totals lines. Every counter comes from exactly one worker's own arithmetic.
sums=$(grep -h '^fuzz-totals: ' "$OUT"/w*.log 2>/dev/null | sed 's/^fuzz-totals: //' | tr ' ' '\n' |
    awk -F= '{ s[$1] += $2 } END { for (k in s) printf "%s=%d\n", k, s[k] }')
val() { printf '%s\n' "$sums" | grep "^$1=" | cut -d= -f2 || true; }
[ -n "$(val progs)" ] || echo "fuzz: no worker produced totals" >&2

# A run that tested less than the seed range and --count imply is a failure, not a clean result. This is
# the shape of the counting bug the parallel mode exists to be immune to, and the same check catches a
# worker that never reported.
expected=$((span * COUNT))
tested=$(val progs); tested=${tested:-0}
shortfall=""
if [ "$tested" -lt "$expected" ]; then shortfall="$tested program(s) tested, the range and --count imply $expected"; fi
if [ "$failed" -gt 0 ]; then shortfall="$shortfall${shortfall:+; }$failed worker(s) did not run"; fi
if [ -n "$shortfall" ]; then
    set_run_state failed
    echo "fuzz: FAIL - $shortfall" >&2
    grep -hE '^\[|FAIL' "$OUT"/w*.log 2>/dev/null | head -20
    echo "fuzz: worker logs kept in $OUT/w*.log" >&2
    exit 1
fi

progs=$(val progs); ran=$(val ran); accepted=$(val accepted); traps=$(val traps)
rejected=$(val rejected); candidates=$(val candidates); faults=$(val faults)
inferdiff=$(val inferdiff); genbug=$(val genbug); diffs=$(val diffs); expired=$(val expired)
mprogs=$(val mprogs); mrej=$(val mrej); maccepted=$(val maccepted)
mowning=$(val mowning); mtotal=$(val mtotal)
known=$(val known); knownfault=$(val knownfault); knownfixed=$(val knownfixed); knownskipped=$(val knownskipped); knownblind=$(val knownblind)
vchecked=$(val vchecked); vunchecked=$(val vunchecked); t134=$(val t134); t136=$(val t136)
zbuilt=$(val zbuilt); modediffs=$(val modediffs)

grep -hE '^\[(CANDIDATE|FAULT|MODE-DIFF|REVERIFY|EXPIRED)\]' "$OUT"/w*.log 2>/dev/null | head -40
echo "fuzz: $JOBS worker(s) over seeds $first-$last, each with its own output directory and TR_WORK"
if [ "$reported" -gt 0 ]; then
    echo "fuzz: $reported of them reported a finding (exit 1) and every one of those totals is counted below: a finding is not a worker that failed to run"
fi
echo "fuzz: ${progs:-0} program(s) in the main stream, ${ran:-0} compiled and ran, $(( ${accepted:-0} - ${maccepted:-0} )) accepted, ${traps:-0} trap(134), $(( ${rejected:-0} - ${mrej:-0} )) rejected by zoril, ${faults:-0} fault(s), ${candidates:-0} rustc candidate(s)"
echo "fuzz: mismatch stream: ${mprogs:-0} program(s), ${mrej:-0} refused (the expected outcome), ${maccepted:-0} accepted - an accepted mismatch is a finding"
if [ "${known:-0}" -gt 0 ]; then
    echo "fuzz: known holes (apart from the search): ${known} program(s), ${knownfault:-0} still open, ${knownfixed:-0} fixed, ${knownskipped:-0} not reached, ${knownblind:-0} faulted with the switch off (must be 0), $(( ${known:-0} - ${knownfault:-0} - ${knownfixed:-0} - ${knownskipped:-0} - ${knownblind:-0} )) not reproduced in this run"
fi
echo "fuzz: disagreements - ${inferdiff:-0} zoril-rejects/rustc-accepts with a borrow diagnostic, ${genbug:-0} generator type error(s)"
if [ "${mtotal:-0}" -gt 0 ]; then
    echo "fuzz: value mix: ${mowning:-0} of ${mtotal} values own something ($(( ${mowning:-0} * 100 / mtotal ))%)"
fi
echo "fuzz: ${diffs:-0} accepted-with-a-listed-difference (bench/fuzz/intended_differences.txt)"
echo "fuzz: traps by exit code (an unpredicted trap is always 134; 136 only when the generator computed it): ${t134:-0} with exit 134, ${t136:-0} with exit 136"
echo "fuzz: expected-value oracle: ${vchecked:-0} program(s) carried a checksum, ${vunchecked:-0} could not be followed by the generator's interpreter"
echo "fuzz: mode-diff (whole-program vs staged zbuild): ${zbuilt:-0} build(s) compared, ${modediffs:-0} disagreement(s) - each is a finding"

set_run_state finished
echo "fuzz: wall time $(fmt_dur "$WALL"), $(awk -v p="${progs:-0}" -v r="${ran:-0}" -v w="$WALL" 'BEGIN { printf "%d generated and %d compiled-and-ran programs a second", p / w, r / w }')"
if [ -n "$RAN_TARGET" ] && [ "$RAN_TARGET" -gt 0 ]; then
    if [ "${ran:-0}" -ge "$RAN_TARGET" ]; then
        echo "fuzz: target $(fmt_num "$RAN_TARGET") compiled and ran: MET with $(fmt_num "${ran:-0}") ($(awk -v r="${ran:-0}" -v t="$RAN_TARGET" 'BEGIN { printf "%.1f", (r - t) * 100 / t }')% over)"
    else
        echo "fuzz: target $(fmt_num "$RAN_TARGET") compiled and ran: NOT MET ($(fmt_num "${ran:-0}"))" >&2
        RAN_SHORT=1
    fi
fi

cov_bad=0
if [ -z "$NOCOV" ]; then
    mkdir -p "$OUT/cov"
    cat "$OUT"/w*/cov/seen 2>/dev/null | sort -u > "$OUT/cov/seen"
    lua "$GEN" --features > "$OUT/cov/declared"
    total=$(wc -l < "$OUT/cov/declared" | tr -d ' ')
    hit=$(grep -xF -f "$OUT/cov/declared" "$OUT/cov/seen" | wc -l | tr -d ' ')
    echo "fuzz: coverage $hit/$total features"
    missing=$(grep -vxF -f "$OUT/cov/seen" "$OUT/cov/declared" | tr '\n' ' ')
    [ -n "$missing" ] && echo "fuzz: never generated: $missing"
    undeclared=$(grep -vxF -f "$OUT/cov/declared" "$OUT/cov/seen" | tr '\n' ' ')
    if [ -n "$undeclared" ]; then
        echo "fuzz: undeclared feature tag(s): $undeclared" >&2
        cov_bad=1
    fi
fi

# Same totals line, so a wrapper run is as machine-readable as a single one.
printf 'fuzz-totals: progs=%s accepted=%s traps=%s rejected=%s candidates=%s faults=%s inferdiff=%s genbug=%s diffs=%s expired=%s ran=%s mprogs=%s maccepted=%s mrej=%s mowning=%s mtotal=%s known=%s knownfault=%s knownfixed=%s knownskipped=%s knownblind=%s vchecked=%s vunchecked=%s t134=%s t136=%s zbuilt=%s modediffs=%s\n' \
    "${progs:-0}" "${accepted:-0}" "${traps:-0}" "${rejected:-0}" "${candidates:-0}" "${faults:-0}" \
    "${inferdiff:-0}" "${genbug:-0}" "${diffs:-0}" "${expired:-0}" "${ran:-0}" "${mprogs:-0}" \
    "${maccepted:-0}" "${mrej:-0}" "${mowning:-0}" "${mtotal:-0}" \
    "${known:-0}" "${knownfault:-0}" "${knownfixed:-0}" "${knownskipped:-0}" "${knownblind:-0}" "${vchecked:-0}" "${vunchecked:-0}" "${t134:-0}" "${t136:-0}" "${zbuilt:-0}" "${modediffs:-0}"

if [ -n "${RAN_SHORT:-}" ] && [ -n "$RELEASE" ]; then
    echo "fuzz: --release refuses this run: the compiled-and-ran target was not met" >&2
    exit 1
fi
if [ "${expired:-0}" -gt 0 ] || [ "${candidates:-0}" -gt 0 ] || [ "${faults:-0}" -gt 0 ] || [ "${knownblind:-0}" -gt 0 ] || [ "$reported" -gt 0 ] || [ "$cov_bad" -ne 0 ] \
   || { [ -n "$RELEASE" ] && [ "${knownfault:-0}" -gt 0 ]; }; then
    # The logs are the diagnostics, so a finding keeps its output directory rather than pointing at it.
    if [ -n "$RELEASE" ] && [ "${knownfault:-0}" -gt 0 ]; then
        echo "fuzz: --release refuses this run: ${knownfault} known-hole program(s) are still open - a reopened hole (see the worker logs)" >&2
    fi
    echo "fuzz: findings or expired differences above; worker logs kept in $OUT/w*.log" >&2
    exit 1
fi
if [ "$TMPOUT" -eq 1 ] && [ -z "$KEEP" ]; then rm -rf "$OUT"; fi
exit 0
