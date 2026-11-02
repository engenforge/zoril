#!/bin/sh
# scripts/fuzz/plan.sh -- size a budget run from a pilot's measured rate.
#
#   make fuzz-plan RAN=2500000 [RUN=pilot-name] [MARGIN=5]
#
# From the pilot's ratio (compiled-and-ran per seed) and speed (seeds per second): the seed range for
# RAN plus MARGIN percent, rounded up to a thousand; the compiled-and-ran count and the wall time that
# range should give on this machine; and the exact `make fuzz-release-start` line to run. Size from the
# pilot, never from a previous run's range: the generator and the oracles change.
#
# Usage: plan.sh --ran N [--run RUN] [--margin PERCENT]
set -u
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO_ROOT/scripts/lib/fuzz_run.sh"
RAN=""; RUN=""; MARGIN=5
while [ $# -gt 0 ]; do
    case "$1" in
        --ran) RAN=$2; shift 2 ;;
        --run) RUN=$2; shift 2 ;;
        --margin) MARGIN=$2; shift 2 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "fuzz: unknown argument $1" >&2; exit 2 ;;
    esac
done
[ -n "$RAN" ] || { echo "fuzz: RAN=<compiled-and-ran target> is required" >&2; exit 2; }
if [ -z "$RUN" ]; then
    # The newest pilot, else the latest run.
    RUN=$(ls -d "$FUZZ_ROOT"/pilot-*/ 2>/dev/null | tail -n 1)
fi
DIR=$(fuzz_run_dir "$RUN") || { echo "fuzz: no pilot run to size from (run make fuzz-pilot, or pass RUN=)" >&2; exit 2; }
[ "$(run_state "$DIR")" = finished ] || { echo "fuzz: $DIR is $(run_state "$DIR"), not finished; its rate is not a measurement" >&2; exit 2; }
first=$(kv "$DIR/run.status" first); lastseed=$(kv "$DIR/run.status" lastseed); count=$(kv "$DIR/run.status" count)
jobs=$(kv "$DIR/run.status" jobs); start=$(kv "$DIR/run.status" start); end=$(kv "$DIR/run.status" end)
ran=$(sum_field "$DIR" ran); span=$((lastseed - first + 1)); wall=$((end - start)); [ "$wall" -lt 1 ] && wall=1
[ "$ran" -gt 0 ] || { echo "fuzz: the pilot compiled and ran nothing" >&2; exit 2; }
awk -v ran="$ran" -v span="$span" -v wall="$wall" -v target="$RAN" -v margin="$MARGIN" -v count="$count" -v jobs="$jobs" -v pilot="$DIR" '
function fmt(n,   s, o) { s = sprintf("%d", n); o = ""; while (length(s) > 3) { o = "," substr(s, length(s) - 2) o; s = substr(s, 1, length(s) - 3) } return s o }
function dur(t,   h, m) { h = int(t / 3600); m = int((t % 3600) / 60); return sprintf("%dh%02dm", h, m) }
BEGIN {
    per_seed = ran / span; seeds_per_s = span / wall
    need = target * (1 + margin / 100) / per_seed
    n = int((need + 999) / 1000) * 1000
    got = n * per_seed
    printf "pilot %s: %s seeds x %d, %s compiled and ran (%.4f per seed), %s, %.1f seeds/s with %d workers\n", pilot, fmt(span), count, fmt(ran), per_seed, dur(wall), seeds_per_s, jobs
    printf "for %s compiled and ran plus %d%% margin: seeds 1-%d (x %d), about %s compiled and ran, about %s on this machine\n", fmt(target), margin, n, count, fmt(got), dur(n / seeds_per_s)
    printf "run:  make fuzz-release-start SEEDS=1-%d RAN=%d\n", n, target
}'
