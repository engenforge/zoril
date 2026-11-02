#!/bin/sh
# scripts/fuzz/summary.sh -- the figures a record needs, summed over a run's workers.
#
#   make fuzz-summary [RUN=name-or-path] [FORMAT=record]
#
# Generated, compiled and ran, faults, candidates, listed differences, known-hole rows, coverage, wall
# time and rate, the pipeline lines (versions, fingerprint, oracles), and whether the run's compiled-and-ran
# target was met and by how much. The record format names the code by its fingerprint, not by a commit: the
# record is a public page, and a commit hash of this repository means nothing to its reader.
# On a run that was stopped there are no totals lines
# yet, so the heartbeats stand in and the output says it is partial. `--format record` prints the
# figures as the bullets and the two machine-readable lines of bench/fuzz/README.md.
#
# Usage: summary.sh [--run RUN] [--format text|record]
set -u
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO_ROOT/scripts/lib/fuzz_run.sh"
RUN=""; FORMAT=text
while [ $# -gt 0 ]; do
    case "$1" in
        --run) RUN=$2; shift 2 ;;
        --format) FORMAT=$2; shift 2 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "fuzz: unknown argument $1" >&2; exit 2 ;;
    esac
done
DIR=$(fuzz_run_dir "$RUN") || { echo "fuzz: no such run" >&2; exit 2; }

sums=$(grep -h '^fuzz-totals: ' "$DIR"/w*.log 2>/dev/null | sed 's/^fuzz-totals: //' | tr ' ' '\n' |
    awk -F= '{ s[$1] += $2 } END { for (k in s) printf "%s=%d\n", k, s[k] }')
val() { printf '%s\n' "$sums" | grep "^$1=" | cut -d= -f2; }
PARTIAL=0
if [ -z "$sums" ]; then
    PARTIAL=1
    progs=$(sum_field "$DIR" progs); ran=$(sum_field "$DIR" ran); faults=$(sum_field "$DIR" faults)
    candidates=$(sum_field "$DIR" candidates); genbug=$(sum_field "$DIR" genbug)
    rejected=0; traps=0; expired=0; diffs=0; inferdiff=0; known=0; knownfault=$(sum_field "$DIR" knownopen)
    knownfixed=0; knownskipped=0; knownblind=0; mprogs=0; maccepted=0; mrej=0; mowning=0; mtotal=0
    vchecked=0; vunchecked=0; t134=0; t136=0; zbuilt=0; modediffs=0
else
    for k in progs ran rejected traps faults candidates genbug expired diffs inferdiff known knownfault knownfixed knownskipped knownblind mprogs maccepted mrej mowning mtotal vchecked vunchecked t134 t136 zbuilt modediffs; do
        eval "$k=\$(val $k); : \${$k:=0}"
    done
fi
start=$(kv "$DIR/run.status" start); end=$(kv "$DIR/run.status" end); state=$(run_state "$DIR")
[ -n "$end" ] || end=$(date +%s)
wall=$((end - start)); [ "$wall" -lt 1 ] && wall=1
first=$(kv "$DIR/run.status" first); lastseed=$(kv "$DIR/run.status" lastseed)
count=$(kv "$DIR/run.status" count); jobs=$(kv "$DIR/run.status" jobs); target=$(kv "$DIR/run.status" ran_target)
cov_hit=""; cov_total=""
if [ -f "$DIR/cov/declared" ] && [ -f "$DIR/cov/seen" ]; then
    cov_total=$(wc -l < "$DIR/cov/declared" | tr -d ' ')
    cov_hit=$(grep -xF -f "$DIR/cov/declared" "$DIR/cov/seen" | wc -l | tr -d ' ')
fi
pipeline=$(grep -h '^fuzz: pipeline:' "$DIR/w0.log" 2>/dev/null | head -5)
fingerprint=$(printf '%s\n' "$pipeline" | sed -n 's/^fuzz: pipeline: fingerprint: //p' | head -1)
version=$(printf '%s\n' "$pipeline" | sed -n 's/^fuzz: pipeline: zoril \([^;]*\);.*/\1/p' | head -1)
commit=$(printf '%s\n' "$version" | sed -n 's/.*-g\([0-9a-f]*\).*/\1/p')
main_rejected=$((rejected - mrej))

verdict="no compiled-and-ran target was set"
if [ -n "$target" ] && [ "$target" -gt 0 ]; then
    if [ "$ran" -ge "$target" ]; then
        verdict="target $(fmt_num "$target") MET with $(fmt_num "$ran") ($(awk -v r="$ran" -v t="$target" 'BEGIN { printf "%.1f", (r - t) * 100 / t }')% over)"
    else
        verdict="target $(fmt_num "$target") NOT MET ($(fmt_num "$ran"))"
    fi
fi
pct=$(awk -v r="$ran" -v p="$progs" 'BEGIN { if (p > 0) printf "%.1f", r * 100 / p; else print "0.0" }')

if [ "$FORMAT" = record ]; then
    [ "$PARTIAL" -eq 1 ] && echo "<!-- partial: the run has no totals lines yet -->"
    echo "fingerprint: ${fingerprint:-unavailable}"
    echo
    echo "headline: $ran programs compiled and ran"
    echo
    echo "- **Seeds:** $(fmt_num "$first") - $(fmt_num "$lastseed") (x $count), over $jobs workers"
    echo "- **Programs generated:** **$(fmt_num "$progs")** in the main stream"
    echo "- **Compiled and ran:** **$(fmt_num "$ran")** ($pct%)"
    echo "- **Rejected by Zoril:** $(fmt_num "$main_rejected")"
    echo "- **Traps:** $(fmt_num "$traps") ($(fmt_num "$t134") with exit 134, $(fmt_num "$t136") with exit 136)"
    echo "- **Faults:** **$faults**"
    echo "- **\`rustc\` candidates:** **$candidates**"
    echo "- **Generator bugs (\`[GEN-BUG]\`):** $genbug"
    echo "- **Expired allowlist entries:** $expired"
    echo "- **Mismatch stream:** $mprogs programs, $mrej refused, **$maccepted accepted**"
    echo "- **Known holes (reported apart from the search):** $(fmt_num "$known") marked programs: **$knownfault still open**, $knownfixed fixed, $(fmt_num "$knownskipped") not reached, **$knownblind faulted with the switch off**"
    echo "- **Expected-value oracle:** $(fmt_num "$vchecked") programs carried a checksum (exit 93 on a mismatch), $(fmt_num "$vunchecked") could not be followed by the generator's interpreter"
    echo "- **Mode-diff (whole-program vs \`zbuild\`):** $(fmt_num "$zbuilt") builds compared, **$modediffs disagreements**"
    echo "- **Listed differences (\`[DIFF]\`):** **$(fmt_num "$diffs")**"
    echo "- **Infer-diffs (\`[INFER-DIFF]\`):** $(fmt_num "$inferdiff")"
    [ "$mtotal" -gt 0 ] && echo "- **Value mix:** $(fmt_num "$mowning") of $(fmt_num "$mtotal") values own something ($((mowning * 100 / mtotal))%)"
    [ -n "$cov_total" ] && echo "- **Feature coverage:** **$cov_hit/$cov_total features**"
    echo "- **Wall time:** **$(fmt_dur "$wall")** ($jobs workers; about $((progs / wall)) generated and $((ran / wall)) compiled-and-ran programs a second)"
    exit 0
fi
echo "run $DIR: $state$([ "$PARTIAL" -eq 1 ] && echo ' (partial: heartbeats only)')"
echo "$pipeline"
echo "seeds $first-$lastseed x $count, $jobs workers, wall time $(fmt_dur "$wall") ($((progs / wall)) generated, $((ran / wall)) compiled-and-ran a second)"
echo "generated $(fmt_num "$progs"), compiled and ran $(fmt_num "$ran") ($pct%), rejected by Zoril $(fmt_num "$main_rejected"), traps $traps ($t134 exit 134, $t136 exit 136)"
echo "faults $faults, rustc candidates $candidates, generator bugs $genbug, expired entries $expired"
echo "mismatch stream $mprogs programs, $mrej refused, $maccepted accepted"
echo "known holes: $(fmt_num "$known") programs, $knownfault still open, $knownfixed fixed, $knownblind faulted with the switch off"
echo "expected-value oracle: $(fmt_num "$vchecked") checked, $(fmt_num "$vunchecked") unchecked"
echo "mode-diff: $(fmt_num "$zbuilt") zbuild builds compared, $modediffs disagreements"
echo "listed differences $(fmt_num "$diffs"), infer-diffs $(fmt_num "$inferdiff")"
[ -n "$cov_total" ] && echo "coverage $cov_hit/$cov_total features"
echo "commit ${commit:-unknown}; $verdict"
exit 0
