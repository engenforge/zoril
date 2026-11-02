# scripts/lib/fuzz_progress.sh -- sourced by fuzz_jobs.sh and the scripts/fuzz/ commands: read a fuzz run
# from the files it leaves, never from `ps`.
#
# A run directory holds `run.status` (the wrapper: state, start, arguments), one `w<k>.status` per worker
# (its heartbeat, see fuzz_safe.sh) and one `w<k>.log`. A long run is watched from another shell, often
# from another PID namespace, so liveness is the age of the heartbeat and nothing else.

# fmt_num N -- 1234567 as 1,234,567.
fmt_num() {
    awk -v n="${1:-0}" 'BEGIN { s = sprintf("%d", n); out = ""; while (length(s) > 3) { out = "," substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) } print s out }'
}

# fmt_dur SECONDS -- 38340 as 10h39m, 125 as 2m05s, 9 as 9s.
fmt_dur() {
    awk -v t="${1:-0}" 'BEGIN { t = int(t); h = int(t / 3600); m = int((t % 3600) / 60); s = t % 60;
        if (h > 0) printf "%dh%02dm", h, m; else if (m > 0) printf "%dm%02ds", m, s; else printf "%ds", s }'
}

# fmt_clock EPOCH -- 13:15Z (UTC).
fmt_clock() { date -u -d "@$1" +%H:%MZ 2>/dev/null || date -u -r "$1" +%H:%MZ 2>/dev/null || echo "?"; }

# kv FILE KEY -- the value of KEY in a key=value file (the last line that has it), or empty.
kv() { [ -f "$1" ] || return 0; tr ' ' '\n' < "$1" | sed -n "s/^$2=//p" | tail -n 1; }

# run_state DIR -- running | finished | failed | killed | unknown, from run.status.
run_state() { s=$(kv "$1/run.status" state); echo "${s:-unknown}"; }

# worker_state DIR K NOW HB -- running | stalled | finished | failed | killed | starting.
# A worker is stalled when its heartbeat is older than three intervals.
worker_state() {
    _f="$1/w$2.status"
    [ -f "$_f" ] || { echo starting; return; }
    _st=$(kv "$_f" state)
    case "$_st" in finished|failed|killed) echo "$_st"; return ;; esac
    _t=$(kv "$_f" t)
    if [ -n "$_t" ] && [ $(($3 - _t)) -gt $((3 * $4)) ]; then echo stalled; else echo running; fi
}

# sum_field DIR KEY -- the sum of KEY over the workers: a worker that has printed its totals line counts
# those (exact), one that is still running counts its latest heartbeat. The totals line calls the open
# known-hole count `knownfault`; the heartbeat calls it `knownopen`.
sum_field() {
    _tk=$2; [ "$2" = knownopen ] && _tk=knownfault
    for _f in "$1"/w*.status; do
        [ -f "$_f" ] || continue
        _log="${_f%.status}.log"
        _line=$(grep -h '^fuzz-totals: ' "$_log" 2>/dev/null | head -1)
        if [ -n "$_line" ]; then
            printf '%s\n' "$_line" | tr ' ' '\n' | sed -n "s/^$_tk=//p"
        else
            kv "$_f" "$2"
        fi
    done | awk '{ s += $1 } END { printf "%d\n", s }'
}

# seeds_done DIR -- seeds the workers have finished: seed-from for a running worker, the whole share
# for one that has finished.
seeds_done() {
    for _f in "$1"/w*.status; do
        [ -f "$_f" ] || continue
        _from=$(kv "$_f" from); _seed=$(kv "$_f" seed); _last=$(kv "$_f" last); _st=$(kv "$_f" state)
        [ -n "$_from" ] || continue
        case "$_st" in finished) echo $((_last - _from + 1)) ;; *) echo $((_seed - _from)) ;; esac
    done | awk '{ s += $1 } END { printf "%d\n", s }'
}

# live_workers DIR -- prints " wK" for each worker whose heartbeat is younger than three intervals,
# whatever the run's own state says (a worker's heartbeat rewrites its status file, dropping a `killed`
# mark that a stop from another shell appended): a heartbeat is the only sign of life a shell in another PID
# namespace can see.
live_workers() {
    _lw_now=$(date +%s); _lw_hb=$(kv "$1/run.status" hb); _lw_hb=${_lw_hb:-60}
    for _lw_f in "$1"/w*.status; do
        [ -f "$_lw_f" ] || continue
        case "$(kv "$_lw_f" state)" in finished|failed|killed) continue ;; esac
        _lw_t=$(kv "$_lw_f" t)
        [ -n "$_lw_t" ] && [ $((_lw_now - _lw_t)) -le $((3 * _lw_hb)) ] && printf ' %s' "$(basename "$_lw_f" .status)"
    done
}

# status_line DIR NOW -- the one-line summary. Needs run.status keys start, seeds, count, jobs, hb and
# (optionally) ran_target. Its clock is _sl_now, not _now: sh has no locals, and a caller that passes the
# end of a stopped run as NOW keeps its own _now for the heartbeat ages.
status_line() {
    _d=$1; _sl_now=$2
    _start=$(kv "$_d/run.status" start); _count=$(kv "$_d/run.status" count)
    _first=$(kv "$_d/run.status" first); _lastseed=$(kv "$_d/run.status" lastseed)
    _jobs=$(kv "$_d/run.status" jobs); _hb=$(kv "$_d/run.status" hb); _target=$(kv "$_d/run.status" ran_target)
    _span=$((_lastseed - _first + 1)); _total=$((_span * _count))
    _progs=$(sum_field "$_d" progs); _ran=$(sum_field "$_d" ran)
    _faults=$(sum_field "$_d" faults); _cands=$(sum_field "$_d" candidates)
    _gen=$(sum_field "$_d" genbug); _open=$(sum_field "$_d" knownopen)
    _done=$(seeds_done "$_d"); _el=$((_sl_now - _start)); [ "$_el" -lt 1 ] && _el=1
    _alive=0; _stalled=""; _k=0
    while [ "$_k" -lt "$_jobs" ]; do
        case $(worker_state "$_d" "$_k" "$_sl_now" "$_hb") in
            running|starting|finished) _alive=$((_alive + 1)) ;;
            stalled) _stalled="$_stalled w$_k" ;;
        esac
        _k=$((_k + 1))
    done
    # Progress is seeds finished over seeds in the range: a mix run generates more programs than
    # seeds times count (the calibration and mismatch extras), so programs over that product overshoots.
    _pct=0; [ "$_span" -gt 0 ] && _pct=$((_done * 100 / _span))
    _rate=$(awk -v p="$_progs" -v e="$_el" 'BEGIN { printf "%d", p / e }')
    _eta="?"
    if [ "$_done" -gt 0 ]; then
        _eta=$(fmt_clock $((_sl_now + _el * (_span - _done) / _done)))
    fi
    _ranpart="$(fmt_num "$_ran") compiled and ran"
    [ -n "$_target" ] && [ "$_target" -gt 0 ] && _ranpart="$_ranpart ($((_ran * 100 / _target))% of $(fmt_num "$_target"))"
    printf '[STATUS] %s elapsed %s: %s generated, %s of %s seeds (%s%%), %s, %s faults, %s candidates, %s gen-bugs, known holes %s still open, %s/%s workers alive%s, %s programs/s, ETA %s\n' \
        "$(fmt_clock "$_sl_now")" "$(fmt_dur "$_el")" "$(fmt_num "$_progs")" "$(fmt_num "$_done")" "$(fmt_num "$_span")" "$_pct" \
        "$_ranpart" "$_faults" "$_cands" "$_gen" "$_open" "$_alive" "$_jobs" \
        "${_stalled:+ (stalled:$_stalled)}" "$_rate" "$_eta"
}

# set_key FILE KEY VALUE -- replace the line KEY=... of a key=value file (portable, by way of a temporary file).
set_key() {
    awk -v k="$2" -v v="$3" 'BEGIN { FS = "=" } $1 == k { print k "=" v; next } { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# replace_number FILE OLD NEW -- replace every OLD that is a whole number (not part of a longer run of
# digits or commas) with NEW, in place by way of a temporary file. OLD and NEW are plain text.
replace_number() {
    awk -v old="$2" -v new="$3" '
    {
        line = $0; out = ""
        while ((i = index(line, old)) > 0) {
            before = (i > 1) ? substr(line, i - 1, 1) : ""
            after = substr(line, i + length(old), 1)
            if (before ~ /[0-9,]/ || after ~ /[0-9]/ || (after == "," && substr(line, i + length(old) + 1, 1) ~ /[0-9]/)) {
                out = out substr(line, 1, i + length(old) - 1)
            } else {
                out = out substr(line, 1, i - 1) new
            }
            line = substr(line, i + length(old))
        }
        print out line
    }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
