#!/bin/sh
# scripts/perf_gap.sh — where generated code loses to C (doc/performance/zero_overhead_gap.md).
#
# Each workload in bench/perf_gap/ exists as NAME.zrl and an equivalent NAME.c (the same
# algorithm written the same way). Three builds of each:
#   zoril   NAME.zrl -> zoril -> zilc -> qbe -> as/ld
#   cproc   NAME.c   -> cproc (C front end on the same QBE backend)
#   gcc     NAME.c   -> gcc -O2
# zoril vs cproc is what Zoril's front end and lowering cost; cproc vs gcc is what the QBE
# backend costs. All three must exit with the same code (the workloads compute a checksum),
# so a miscompile cannot pass as a speedup.
#
# Usage: scripts/perf_gap.sh [-n RUNS] [WORKLOAD...]     (default: every workload, 5 runs)
# Prints one line per workload: median run time of each build in ms and the two ratios.
# With --tsv, prints `workload<TAB>zoril_ms<TAB>cproc_ms<TAB>gcc_ms` lines instead.
# With --record-run [--kind KIND], measures each workload (timing and gate-size instruction
# count when valgrind is present), appends rows to bench/records/runtime_history.tsv (or
# $RUNTIME_HISTORY), commits on `records`, and prints `runtime_geomean_vs_gcc_o2<TAB><val>` last.
#
# The gate (`make perf-gate`, part of `make test` in `scripts/test_plan.tsv`):
#   scripts/perf_gap.sh --gate-check    fail if a workload's Zoril build executes more
#                                       instructions than bench/perf_gap/gate_baseline.tsv
#                                       allows (GATE_TOLERANCE_PCT, default 2)
#   scripts/perf_gap.sh --gate-record   re-record the baseline after an intended change
# Wall-clock time on a shared machine varies 5-20% between runs, too much to gate on, so
# the gate counts instructions (callgrind), which are exact, takes seconds, and names the
# commit that made generated code worse. It builds each workload at its gate size (the
# `// gate: N` on its `const SCALE` line).
# One blind spot: callgrind counts a `rep movsb` (the runtime memcpy) as one instruction
# however many bytes it copies, so replacing such a call with inline loads and stores reads
# as growth. When a change trades one for the other, judge it by the timing above, then
# re-record.

cd "$(dirname "$0")/.." || exit 2
REPO_ROOT="$(pwd)"
if [ -f "scripts/lib/portability.sh" ]; then
    . "scripts/lib/portability.sh"
fi
if [ -f "scripts/lib/records.sh" ]; then
    . "scripts/lib/records.sh"
fi
RUNS=5
TSV=0
STAT=${PERF_GAP_STAT:-median}
GATE=
RECORD_RUN=0
KIND=run
while [ $# -gt 0 ]; do
    case "$1" in
        -n) RUNS="$2"; shift 2 ;;
        --tsv) TSV=1; shift ;;
        --gate-check) GATE=check; shift ;;
        --gate-record) GATE=record; shift ;;
        --record-run) RECORD_RUN=1; shift ;;
        --kind) KIND="$2"; shift 2 ;;
        *) break ;;
    esac
done
WORKLOADS="$*"
[ -n "$WORKLOADS" ] || WORKLOADS=$(ls bench/perf_gap/*.zrl | sed 's|.*/||; s|\.zrl$||')

ZORIL=${ZORIL_CC:-./build/zoril}
ZILC=${ZILC_BIN:-./build/zilc}
BACKEND_BIN=${BACKEND_BIN:-qbe}
ASSEMBLER_BIN=${ASSEMBLER_BIN:-as}
LINKER_BIN=${LINKER_BIN:-ld}
QBE=$BACKEND_BIN
OUT=${PERF_GAP_OUT:-build/perf_gap}
mkdir -p "$OUT"
ulimit -s unlimited 2>/dev/null || ulimit -s 262144 2>/dev/null

fail() { echo "perf_gap: $*" >&2; exit 1; }
if [ "$RECORD_RUN" -eq 1 ] && ! command -v gcc >/dev/null 2>&1; then
    echo "[SKIP] runtime record: gcc is not installed"
    exit 0
fi
for t in "$ZORIL" "$ZILC" build/runtime.o; do [ -e "$t" ] || fail "$t is missing; run make first"; done
if [ -n "$GATE" ]; then
    TOOLS="$QBE"
elif [ "$RECORD_RUN" -eq 1 ]; then
    TOOLS="$QBE gcc"
else
    TOOLS="$QBE cproc gcc"
fi
for t in $TOOLS; do command -v "$t" >/dev/null 2>&1 || fail "$t is not installed"; done

build() {  # build NAME [with_cproc]
    n=$1; with_cproc=${2:-1}; s=bench/perf_gap/$n
    "$ZORIL" -I stdlib=stdlib --emit-zil -o "$OUT/$n.zil" "$s.zrl" > "$OUT/$n.log" 2>&1 || fail "$n: zoril failed (see $OUT/$n.log)"
    "$ZILC" "$OUT/$n.zil" "$OUT/$n.ssa" >> "$OUT/$n.log" 2>&1 || fail "$n: zilc failed"
    "$QBE" -o "$OUT/$n.s" "$OUT/$n.ssa" || fail "$n: qbe failed"
    "$ASSEMBLER_BIN" -o "$OUT/$n.o" "$OUT/$n.s" && "$LINKER_BIN" -o "$OUT/$n.zoril" build/runtime.o "$OUT/$n.o" || fail "$n: link failed"
    if [ "$with_cproc" -eq 1 ]; then
        cproc -o "$OUT/$n.cproc" "$s.c" || fail "$n: cproc failed"
    fi
    gcc -O2 -o "$OUT/$n.gcc" "$s.c" || fail "$n: gcc failed"
}

# Median wall time of RUNS runs in ms; sets MED_MS and RC.
median_ms() {
    ts=""
    i=0
    while [ $i -lt "$RUNS" ]; do
        s=$(now_ms); "$1" > /dev/null 2>&1; RC=$?; e=$(now_ms)
        ts="$ts $(( e - s ))"
        i=$((i + 1))
    done
    if [ "$STAT" = min ]; then
        MED_MS=$(echo $ts | tr ' ' '\n' | sort -n | head -n 1)
    else
        MED_MS=$(echo $ts | tr ' ' '\n' | sort -n | sed -n "$(( (RUNS + 1) / 2 ))p")
    fi
}

# ── Gate: instruction counts of the Zoril builds at gate size ────────────────────────
BASELINE=bench/perf_gap/gate_baseline.tsv
gate_count() {  # gate_count NAME: prints "instructions exit_code" for the gate-size Zoril build
    n=$1; g=$OUT/gate; mkdir -p "$g"
    sed 's|^\(const SCALE: [^=]*= \)[0-9]*; // gate: \([0-9]*\)$|\1\2;|' "bench/perf_gap/$n.zrl" > "$g/$n.zrl"
    grep -q '// gate:' "$g/$n.zrl" && fail "$n: its const SCALE line has no usable // gate: size"
    "$ZORIL" -I stdlib=stdlib -I bench/perf_gap --emit-zil -o "$g/$n.zil" "$g/$n.zrl" > "$g/$n.log" 2>&1 || fail "$n: zoril failed at gate size"
    "$ZILC" "$g/$n.zil" "$g/$n.ssa" >> "$g/$n.log" 2>&1 && "$QBE" -o "$g/$n.s" "$g/$n.ssa" \
        && "$ASSEMBLER_BIN" -o "$g/$n.o" "$g/$n.s" && "$LINKER_BIN" -o "$g/$n" build/runtime.o "$g/$n.o" || fail "$n: gate build failed"
    # Run from the build directory: a crashing workload (a broken compiler under
    # mutation-check.sh) leaves its vgcore.PID there, not in the repository root.
    (cd "$g" && valgrind --tool=callgrind --callgrind-out-file=/dev/null "./$n") > /dev/null 2> "$g/$n.vg"
    rc=$?
    ir=$(sed -n 's/.*Collected : \([0-9]*\).*/\1/p' "$g/$n.vg")
    [ -n "$ir" ] || fail "$n: callgrind reported no instruction count (see $g/$n.vg)"
    echo "$ir $rc"
}
if [ -n "$GATE" ]; then
    if ! command -v valgrind >/dev/null 2>&1; then
        echo "[SKIP] generated-code speed: install valgrind (the gate counts instructions with callgrind)"
        exit 0
    fi
    TOL=${GATE_TOLERANCE_PCT:-2}
    if [ "$GATE" = record ]; then
        printf '# Instructions executed by each workload'"'"'s Zoril build at gate size (scripts/perf_gap.sh).\n# Re-record after an intended change: scripts/perf_gap.sh --gate-record\n' > "$BASELINE.tmp"
        for n in $WORKLOADS; do
            _gc=$(gate_count "$n") || exit 1
            set -- $_gc
            printf '%s\t%s\t%s\n' "$n" "$1" "$2" >> "$BASELINE.tmp"
            echo "recorded $n: $1 instructions, exit $2"
        done
        mv "$BASELINE.tmp" "$BASELINE"
        exit 0
    fi
    [ -f "$BASELINE" ] || fail "no $BASELINE; record one with scripts/perf_gap.sh --gate-record"
    errors=0
    for n in $WORKLOADS; do
        base=$(awk -v n="$n" '$1 == n { print $2 " " $3 }' "$BASELINE")
        if [ -z "$base" ]; then
            echo "[FAIL] $n has no baseline (scripts/perf_gap.sh --gate-record)"; errors=$((errors + 1)); continue
        fi
        set -- $base; bir=$1; brc=$2
        _gc=$(gate_count "$n") || exit 1
        set -- $_gc
        ir=$1; rc=$2
        pct=$(awk -v a="$ir" -v b="$bir" 'BEGIN { printf "%+.1f", (a - b) * 100 / b }')
        if [ "$rc" != "$brc" ]; then
            echo "[FAIL] $n exits $rc, baseline $brc (a miscompile, or the workload changed)"; errors=$((errors + 1))
        elif awk -v a="$ir" -v b="$bir" -v t="$TOL" 'BEGIN { exit !(a > b * (1 + t / 100)) }'; then
            echo "[FAIL] $n executes $pct% instructions ($ir vs $bir; tolerance ${TOL}%)"; errors=$((errors + 1))
        elif awk -v a="$ir" -v b="$bir" -v t="$TOL" 'BEGIN { exit !(a < b * (1 - t / 100)) }'; then
            echo "[PASS] $n $pct% instructions; faster than the baseline, re-record it"
        else
            echo "[PASS] $n $pct% instructions"
        fi
    done
    [ $errors -eq 0 ]
    exit $?
fi

if [ "$RECORD_RUN" -eq 1 ]; then
    RUNTIME_HISTORY="${RUNTIME_HISTORY:-$REPO_ROOT/bench/records/runtime_history.tsv}"
    records_check_target "$RUNTIME_HISTORY" "$REPO_ROOT" || exit 1
    DATE="${RUN_TS:-$(date +%Y-%m-%d-%H-%M-%S)}"
    COMMIT="${ZORIL_COMMIT:-$(records_repo_commit "$REPO_ROOT")}"
    ZORIL_VER="${ZORIL_VERSION:-$("$ZORIL" --version 2>/dev/null | awk '{print $2; exit}')}"
    [ -n "$ZORIL_VER" ] || ZORIL_VER="unknown"
    HID="${HOST_ID:-}"
    if [ -z "$HID" ]; then
        HID="$(BENCH_HOST_ID="${BENCH_HOST_ID:-}" sh "$REPO_ROOT/scripts/bench_cross_lang.sh" --print-host-id 2>/dev/null || echo "unknown")"
    fi
    GOV="${HOST_GOVERNOR:-$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "n/a")}"
    STATUS="${RUN_STATUS:-ok}"
    HAS_CPROC=0
    command -v cproc >/dev/null 2>&1 && HAS_CPROC=1
    HAS_VALGRIND=0
    command -v valgrind >/dev/null 2>&1 && HAS_VALGRIND=1

    rows_file="$OUT/runtime_rows.tmp"
    : > "$rows_file"
    for n in $WORKLOADS; do
        [ -f "bench/perf_gap/$n.zrl" ] || fail "no workload $n"
        build "$n" "$HAS_CPROC"
        median_ms "$OUT/$n.zoril"; z=$MED_MS; zrc=$RC
        median_ms "$OUT/$n.gcc"; g=$MED_MS; grc=$RC
        if [ "$HAS_CPROC" -eq 1 ]; then
            median_ms "$OUT/$n.cproc"; c=$MED_MS; crc=$RC
            [ "$zrc" = "$crc" ] && [ "$crc" = "$grc" ] || fail "$n: exit codes differ (zoril $zrc, cproc $crc, gcc $grc)"
        else
            c=""
            [ "$zrc" = "$grc" ] || fail "$n: exit codes differ (zoril $zrc, gcc $grc)"
        fi
        ratio=$(awk -v a="$z" -v b="$g" 'BEGIN { printf "%.3f", a / (b > 0 ? b : 1) }')
        if [ "$HAS_VALGRIND" -eq 1 ]; then
            _gc=$(gate_count "$n") || exit 1
            set -- $_gc
            ir=$1
        else
            ir=""
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$DATE" "$COMMIT" "$ZORIL_VER" "$HID" "$GOV" "$STATUS" "$KIND" "$n" \
            "$z" "$c" "$g" "$ratio" "$ir" >> "$rows_file"
    done
    if [ "${RECORDS_SKIP:-0}" -eq 0 ]; then
        records_header "$RUNTIME_HISTORY" "$(printf 'date\tcommit\tzoril_version\thost_id\tgovernor\tstatus\tkind\tworkload\tzoril_ms\tcproc_ms\tgcc_ms\tratio_vs_gcc\tinstructions')" || exit 1
        cat "$rows_file" >> "$RUNTIME_HISTORY"
        records_commit "$RUNTIME_HISTORY" "$HID $COMMIT: runtime" "$REPO_ROOT" || exit 1
    fi
    geomean=$(awk -F'\t' '{ r = $12 + 0; if (r <= 0) r = 0.001; sum += log(r); n++ } END { printf "%.3f", (n > 0 ? exp(sum / n) : 0) }' "$rows_file")
    rm -f "$rows_file"
    printf 'runtime_geomean_vs_gcc_o2\t%s\n' "$geomean"
    exit 0
fi

[ $TSV -eq 1 ] || printf '%-12s %9s %9s %9s %12s %12s\n' workload zoril_ms cproc_ms gcc_ms zoril/cproc cproc/gcc
for n in $WORKLOADS; do
    [ -f "bench/perf_gap/$n.zrl" ] || fail "no workload $n"
    build "$n"
    median_ms "$OUT/$n.zoril"; z=$MED_MS; zrc=$RC
    median_ms "$OUT/$n.cproc"; c=$MED_MS; crc=$RC
    median_ms "$OUT/$n.gcc"; g=$MED_MS; grc=$RC
    [ "$zrc" = "$crc" ] && [ "$crc" = "$grc" ] || fail "$n: exit codes differ (zoril $zrc, cproc $crc, gcc $grc)"
    if [ $TSV -eq 1 ]; then
        printf '%s\t%s\t%s\t%s\n' "$n" "$z" "$c" "$g"
    else
        printf '%-12s %9d %9d %9d %12s %12s\n' "$n" "$z" "$c" "$g" \
            "$(awk -v a="$z" -v b="$c" 'BEGIN { printf "%.2fx", a / (b ? b : 1) }')" \
            "$(awk -v a="$c" -v b="$g" 'BEGIN { printf "%.2fx", a / (b ? b : 1) }')"
    fi
done
