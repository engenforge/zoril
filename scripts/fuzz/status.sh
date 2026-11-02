#!/bin/sh
# scripts/fuzz/status.sh -- where is a fuzz run? Read from the files it leaves (run.status, the workers'
# heartbeats, their logs), never from `ps`: a run is often watched from another shell or PID namespace.
#
#   make fuzz-status [RUN=name-or-path] [WATCH=60]
#
# Prints the banner, the status line, a table of workers (seed reached of the range, compiled and ran,
# heartbeat age, state) and every finding so far. Exit status: 0 no findings, 1 findings, 2 no such run.
# WATCH=N repeats every N seconds until the run is no longer running.
#
# Usage: status.sh [--run RUN] [--watch SECONDS] [--findings-only]
set -u
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO_ROOT/scripts/lib/fuzz_run.sh"
RUN=""; WATCH=""; ONLYF=0
while [ $# -gt 0 ]; do
    case "$1" in
        --run) RUN=$2; shift 2 ;;
        --watch) WATCH=$2; shift 2 ;;
        --findings-only) ONLYF=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "fuzz: unknown argument $1" >&2; exit 2 ;;
    esac
done

DIR=$(fuzz_run_dir "$RUN") || { echo "fuzz: no such run (looked for ${RUN:-the latest run} under build/fuzz/)" >&2; exit 2; }

# The findings so far, one line each, from the worker logs.
findings() {
    for _l in "$DIR"/w*.log; do
        [ -f "$_l" ] || continue
        _w=$(basename "$_l" .log)
        grep -E '^\[(FAULT|CANDIDATE|GEN-BUG|EXPIRED)\]|^\[KNOWN-HOLE\].*still open' "$_l" | sed "s/^/$_w: /"
    done
}

report() {
    _now=$(date +%s)
    _state=$(run_state "$DIR")
    _start=$(kv "$DIR/run.status" start); _jobs=$(kv "$DIR/run.status" jobs); _hb=$(kv "$DIR/run.status" hb)
    _first=$(kv "$DIR/run.status" first); _lastseed=$(kv "$DIR/run.status" lastseed)
    echo "run $DIR: $_state"
    if [ "$_state" != running ]; then
        _live=$(live_workers "$DIR")
        [ -n "$_live" ] && echo "warning: the run is marked $_state, but workers are still sending heartbeats:$_live (stop them with make fuzz-stop from the shell that started the run)"
    fi
    echo "seeds $_first-$_lastseed x $(kv "$DIR/run.status" count), mode $(kv "$DIR/run.status" mode), $_jobs worker(s), started $(date -u -d "@$_start" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    status_line "$DIR" "$([ "$_state" = running ] && echo "$_now" || echo "$(kv "$DIR/run.status" end)")"
    echo
    printf '%-4s %-18s %12s %-10s %s\n' worker "seed (of range)" "compiled+ran" heartbeat state
    _k=0
    while [ "$_k" -lt "$_jobs" ]; do
        _f="$DIR/w$_k.status"
        _from=$(kv "$_f" from); _seed=$(kv "$_f" seed); _wl=$(kv "$_f" last); _ran=$(kv "$_f" ran); _t=$(kv "$_f" t)
        _age="-"; [ -n "$_t" ] && _age="$((_now - _t))s ago"
        printf '%-4s %-18s %12s %-10s %s\n' "w$_k" "${_seed:--} of $_from-$_wl" "$(fmt_num "${_ran:-0}")" "$_age" "$(worker_state "$DIR" "$_k" "$_now" "$_hb")"
        _k=$((_k + 1))
    done
    echo
    _f=$(findings)
    if [ -n "$_f" ]; then echo "findings so far:"; printf '%s\n' "$_f" | sed 's/^/  /'; else echo "findings so far: none"; fi
}

if [ "$ONLYF" -eq 1 ]; then
    [ -n "$(findings)" ] && exit 1
    exit 0
fi
if [ -n "$WATCH" ]; then
    while :; do
        [ -t 1 ] && printf '\033[2J\033[H'
        report
        [ "$(run_state "$DIR")" = running ] || break
        sleep "$WATCH"
    done
else
    report
fi
[ -n "$(findings)" ] && exit 1
exit 0
