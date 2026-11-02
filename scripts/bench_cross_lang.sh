#!/bin/sh
# scripts/bench_cross_lang.sh — Cross-language benchmarking harness in POSIX sh & Lua.
#
# Measures Zoril, Zig, Rust, Hare, and C (GCC/Clang) across four axes:
#   1. Compile wall time (ms)
#   2. Compile peak RSS (KB: the largest single process the build ran, from getrusage - see
#      bench/cross_lang/children_maxrss.c)
#   3. Executable run time (ms, best of 3 runs)
#   4. Binary size (bytes)
#
# Workloads:
#   - fib(38) × 3 (call-heavy recursion, runtime ~0.3s - 1.8s)
#   - 4096-element array loop × 500000 (memory access loop, runtime ~0.15s - 0.8s)
#   - Multi-file project: the same program shape for every language (100 modules x 30 functions by
#     default), so the compilers are compared on the same work; the regression gate pins its own,
#     documented size in bench/cross_lang/thresholds.cfg
#       a) Clean full build (measures compile throughput: LOC/s and RSS)
#       b) Incremental touch-one-module-and-rebuild
#   - Scaling sweep: the same shapes at two more sizes, reporting how each compiler's clean build,
#     rebuild and peak memory grow (full-data runs only)
#
# Duration: --update-doc and --record do the whole run (the gate measures only Zoril at its pinned
# size and takes tens of seconds), which is roughly a hundred clean builds. The script prints that
# count and the last run's measured duration when it starts, and records this run's own duration
# under build/bench/ (gitignored), so the estimate stays a measurement rather than a guess.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/scripts/env.sh"

BENCH_DIR="$REPO_ROOT/bench/cross_lang"
SPEED_HISTORY="$REPO_ROOT/bench/speed_history.tsv"
DOC_PATH="$REPO_ROOT/doc/language/language_comparison.md"

UPDATE_DOC=0
CHECK_THRESHOLDS=0
RECORD_BASELINE=0
FORCE_RUN=0
COMPILE_RUNS="${BENCH_COMPILE_RUNS:-3}"
# Scaling-sweep points, defined here so a publishing run can say up front what it is about to do:
# "tag:modules:funcs:who" with who = all | zoril. The sweep section below explains them and why the
# ~100k point is not a default. Override to check the sweep quickly, e.g. MF_SWEEP_POINTS="3k:5:2:all".
MF_SWEEP_POINTS="${MF_SWEEP_POINTS:-3k:25:10:all 30k:100:30:all}"
# Zig's build mode for the multi-file and sweep workloads: Debug, the like-for-like baseline mode.
# Every language in that comparison is measured unoptimized - Rust in its dev profile, Zoril and Hare
# through QBE, which has no optimizer - so measuring only Zig at an optimizing level compared
# different work. The optimizing modes are measured in workload 3c instead, on a realistic call tree,
# where an optimizer has the work a program would give it.
# These figures are why that table cannot simply be built at ReleaseFast: at 30k LOC on the
# straight-line shape, one clean build each, Debug 2,147 ms and ReleaseSmall 19,553 ms, with
# ReleaseFast and ReleaseSafe still running at their 30-minute cap; and with a constant seed
# ReleaseFast did finish, in 259,925 ms (118 LOC/s against 1,296 at 3k), all of it folding
# arithmetic over constants, which is why the generated program's inputs are opaque now.
# MF_ZIG_MODE=ReleaseSmall (or ReleaseFast) measures that other comparison instead.
MF_ZIG_MODE="${MF_ZIG_MODE:-Debug}"
# Rust's profile for the multi-file and sweep workloads: dev, not release. With the opaque input the
# 30k program crashes rustc's LLVM in the release profile - its stack-overflow handler prints "cycle
# encountered after 4 frames with period 6" and cargo exits 101 - while dev compiles the same program
# in about a second. MF_RUST_PROFILE=release asks for the optimizing profile, which worked while the
# generated inputs were constants because LLVM could then fold the call graph away.
MF_RUST_PROFILE="${MF_RUST_PROFILE:-dev}"
RUST_PROFILE_ARGS=""
if [ "$MF_RUST_PROFILE" = "release" ]; then RUST_PROFILE_ARGS="--release"; fi
CHECK_CONTENTION_ONLY=0
CHECK_THRESHOLDS_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --update-doc) UPDATE_DOC=1; shift ;;
        --check-thresholds) CHECK_THRESHOLDS=1; shift ;;
        --check-thresholds-only) CHECK_THRESHOLDS=1; CHECK_THRESHOLDS_ONLY=1; shift ;;
        --record) RECORD_BASELINE=1; shift ;;
        --force) FORCE_RUN=1; shift ;;
        --compile-runs) COMPILE_RUNS="$2"; shift 2 ;;
        --compile-runs=*) COMPILE_RUNS="${1#*=}"; shift ;;
        --check-contention) CHECK_CONTENTION_ONLY=1; shift ;;
        *) shift ;;
    esac
done

# Persisted Zoril-only metrics (machine-readable) for threshold gating.
METRICS_FILE="${METRICS_FILE:-$REPO_ROOT/bench/cross_lang/last_zoril_metrics.tsv}"
THRESHOLDS_FILE="${THRESHOLDS_FILE:-$REPO_ROOT/bench/cross_lang/thresholds.cfg}"

CUSTOM_TMP_DIR=0
if [ -n "${TMP_DIR:-}" ]; then CUSTOM_TMP_DIR=1; fi
TMP_DIR="${TMP_DIR:-/tmp/cross_bench_$$}"
mkdir -p "$TMP_DIR"
if [ "$CUSTOM_TMP_DIR" -eq 0 ]; then
    trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
fi

# ── Host identity & load discovery ───────────────────────────────────────────
HOST_OS="$(uname -s) $(uname -r)"
HOST_CPU="$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed -e 's/[ \t]\+/ /g' -e 's/^ //' -e 's/ $//' || echo "unknown")"
HOST_CORES="${HOST_CORES:-$(nproc_count)}"
HOST_RAM="$(awk '/MemTotal/ {printf "%.1fGB", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "unknown")"
HOST_GOVERNOR="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "n/a")"

sample_cpu_idle() {
    local dur="${1:-1.0}"
    if [ -n "$SAMPLE_CPU_IDLE_OVERRIDE" ]; then
        echo "$SAMPLE_CPU_IDLE_OVERRIDE"
        return
    fi
    if [ -n "$SAMPLE_CPU_IDLE_CMD" ]; then
        $SAMPLE_CPU_IDLE_CMD "$dur"
        return
    fi
    local stat_file="${PROC_STAT:-${PROC_DIR:-/proc}/stat}"
    if [ -r "$stat_file" ]; then
        local u1 n1 s1 i1 w1 q1 sq1 u2 n2 s2 i2 w2 q2 sq2
        if [ "$stat_file" != "/proc/stat" ] && [ "$(wc -l < "$stat_file" 2>/dev/null || echo 0)" -ge 2 ]; then
            # Mock stat file with two pre-recorded stat snapshots
            read -r _ u1 n1 s1 i1 w1 q1 sq1 _ < "$stat_file"
            local line2
            line2=$(sed -n '2p' "$stat_file")
            set -- $line2
            u2=$2; n2=$3; s2=$4; i2=$5; w2=$6; q2=$7; sq2=$8
            if [ "$(wc -l < "$stat_file" 2>/dev/null || echo 0)" -gt 2 ]; then
                sed '1,2d' "$stat_file" > "${stat_file}.tmp" && mv "${stat_file}.tmp" "$stat_file"
            fi
        else
            read -r _ u1 n1 s1 i1 w1 q1 sq1 _ < "$stat_file"
            sleep "$dur"
            read -r _ u2 n2 s2 i2 w2 q2 sq2 _ < "$stat_file"
        fi
        local t1=$((u1 + n1 + s1 + i1 + w1 + q1 + sq1))
        local t2=$((u2 + n2 + s2 + i2 + w2 + q2 + sq2))
        local dt=$((t2 - t1))
        local di=$((i2 - i1))
        if [ "$dt" -gt 0 ]; then
            echo $(( (di * 100) / dt ))
            return
        fi
    fi
    echo "100"
}

check_host_contention() {
    if [ ! -e /proc ] && [ -z "$PROC_DIR" ] && [ -z "$PROC_LOADAVG" ]; then
        echo "[SKIP] host load monitoring needs /proc (Linux)"
        return
    fi
    local load1m="0.0"
    local loadavg_file="${PROC_LOADAVG:-${PROC_DIR:-/proc}/loadavg}"
    if [ -r "$loadavg_file" ]; then
        read -r load1m _ _ _ < "$loadavg_file"
    fi
    local idle_pct
    idle_pct=$(sample_cpu_idle 1.0)

    HOST_LOAD1M="$load1m"
    HOST_LOAD1M_START="$load1m"
    HOST_IDLE_CPU_START="${idle_pct}%"
    HOST_IDLE_CPU="$HOST_IDLE_CPU_START"
    HOST_LOAD_DECAYING=0

    # Threshold: per-core load threshold 0.30 per core (min 1.0) OR idle CPU < 40%
    local max_load
    max_load=$(awk "BEGIN { l = $HOST_CORES * 0.30; if (l < 1.0) l = 1.0; printf \"%.2f\", l }")
    local load_high=0
    awk "BEGIN { if ($load1m > $max_load) exit 1; exit 0 }" || load_high=1
    local is_loaded=0
    if [ "$idle_pct" -lt 40 ]; then
        is_loaded=1
    elif [ "$load_high" -eq 1 ]; then
        # 1-min load average lags behind actual CPU usage (e.g. right after a parallel build).
        # Re-sample idle CPU over a longer window (~3s) to see if load is just decaying.
        local idle_resample
        idle_resample=$(sample_cpu_idle 3.0)
        HOST_IDLE_CPU_START="${idle_resample}%"
        HOST_IDLE_CPU="$HOST_IDLE_CPU_START"
        if [ "$idle_resample" -ge 90 ]; then
            printf "Note: 1-min load still decaying, CPU idle (%s%% >= 90%%, 1-min load: %s, threshold: %s); proceeding.\n" \
                "$idle_resample" "$load1m" "$max_load"
            HOST_LOAD_DECAYING=1
            is_loaded=0
        else
            is_loaded=1
        fi
    fi

    if [ "$is_loaded" -eq 1 ]; then
        if [ "$FORCE_RUN" -eq 1 ] || [ "${BENCH_FORCE:-0}" -eq 1 ]; then
            printf "WARNING: Host contention detected, but continuing due to --force / BENCH_FORCE=1:\n" >&2
            printf "  1-min load: %s (threshold: %s across %s cores)\n" "$load1m" "$max_load" "$HOST_CORES" >&2
            printf "  Idle CPU:   %s (threshold: >= 40%%)\n\n" "$HOST_IDLE_CPU_START" >&2
        else
            printf "ERROR: Host contention detected. Refusing to run benchmarks on a loaded machine:\n" >&2
            printf "  1-min load: %s (threshold: %s across %s cores)\n" "$load1m" "$max_load" "$HOST_CORES" >&2
            printf "  Idle CPU:   %s (threshold: >= 40%%)\n" "$HOST_IDLE_CPU_START" >&2
            printf "Competing processes will corrupt compile-time and runtime measurements.\n" >&2
            printf "Wait for background load to finish, or pass --force to run anyway.\n" >&2
            exit 1
        fi
    fi
}

sample_finish_host_state() {
    local load1m_end="0.0"
    local loadavg_file="${PROC_LOADAVG:-${PROC_DIR:-/proc}/loadavg}"
    if [ -r "$loadavg_file" ]; then
        read -r load1m_end _ _ _ < "$loadavg_file"
    fi
    local idle_end
    idle_end=$(sample_cpu_idle 1.0)
    HOST_LOAD1M_END="$load1m_end"
    HOST_IDLE_CPU_END="${idle_end}%"

    RUN_STATUS="ok"
    local max_load
    max_load=$(awk "BEGIN { l = $HOST_CORES * 0.30; if (l < 1.0) l = 1.0; printf \"%.2f\", l }")
    local diverged=0
    if [ "${HOST_LOAD_DECAYING:-0}" -eq 1 ]; then
        awk "BEGIN { if ($load1m_end - $HOST_LOAD1M_START > 1.5) exit 1; exit 0 }" || diverged=1
    else
        awk "BEGIN { if ($load1m_end - $HOST_LOAD1M_START > 1.5 || $load1m_end > $max_load) exit 1; exit 0 }" || diverged=1
    fi

    # A rise in the 1-minute load average is not contention by itself: this run's own parallel
    # builds raise it, and the average lags them. It only means the host was busy if the CPU was
    # also busy at the end - the same refinement the start check makes. Without
    # this, a successful publishing run on an otherwise idle host was marked "contended" (start
    # load 1.33, end 2.84, idle 99%, threshold 4.80) and its documentation update had to be forced.
    if [ "$diverged" -eq 1 ] && [ "$idle_end" -ge 40 ]; then
        printf "Note: 1-min load rose during the run (%s -> %s) but the CPU is idle (%s%% >= 40%%);\n" \
            "$HOST_LOAD1M_START" "$load1m_end" "$idle_end"
        printf "      the run's own builds raised it, so the run is recorded as ok.\n"
        diverged=0
    fi

    if [ "$diverged" -eq 1 ]; then
        RUN_STATUS="contended"
        printf "\n======================================================================\n" >&2
        printf "WARNING: Host contention rose materially during execution!\n" >&2
        printf "  Start 1m load: %s (idle %s)\n" "$HOST_LOAD1M_START" "$HOST_IDLE_CPU_START" >&2
        printf "  End 1m load:   %s (idle %s, threshold %s)\n" "$HOST_LOAD1M_END" "$HOST_IDLE_CPU_END" "$max_load" >&2
        printf "  Measurements may have been contaminated mid-run.\n" >&2
        printf "  Rows will be recorded in history with status: contended\n" >&2
        printf "======================================================================\n\n" >&2
    fi
}

# Test-only: exercise the finish-state rule on its own, with the start state injected. A real run
# only reaches sample_finish_host_state at the very end (after every measurement), so this is the
# only way to test what it decides; scripts/test_bench_contention.sh uses it. It runs before the
# start check so that an injected busy CPU does not make that check refuse first. RUN_STATUS is
# what the history rows and the --update-doc guard read.
if [ "${CHECK_FINISH_STATE:-0}" -eq 1 ]; then
    HOST_LOAD1M_START="${HOST_LOAD1M_START:-0.00}"
    HOST_IDLE_CPU_START="${HOST_IDLE_CPU_START:-99}%"
    HOST_LOAD_DECAYING="${HOST_LOAD_DECAYING:-0}"
    HOST_LOAD1M="$HOST_LOAD1M_START"
    HOST_IDLE_CPU="$HOST_IDLE_CPU_START"
    RUN_STATUS="ok"
    sample_finish_host_state
    printf 'RUN_STATUS=%s\n' "$RUN_STATUS"
    exit 0
fi

check_host_contention
if [ "${CHECK_CONTENTION_ONLY:-0}" -eq 1 ]; then
    exit 0
fi

# What a publishing run is about to do, and how long the last one took. The duration is recorded
# under build/ (gitignored) rather than guessed, so the estimate is this run's build count plus the
# last run's measured duration; a fresh checkout has no number to quote.
LAST_PUBLISH_FILE="$REPO_ROOT/build/bench/last_publish_seconds"
RUN_START_MS=$(now_ms)
if [ "$UPDATE_DOC" -eq 1 ] || [ "$RECORD_BASELINE" -eq 1 ]; then
    sweep_points=0
    for _p in $MF_SWEEP_POINTS; do sweep_points=$((sweep_points + 1)); done
    runs=$((COMPILE_RUNS + 1))
    last_run="no publishing run recorded yet"
    if [ -r "$LAST_PUBLISH_FILE" ]; then
        last_run="the last one took $(awk -v s="$(cat "$LAST_PUBLISH_FILE")" 'BEGIN { printf "%.1f", s / 60 }') min"
    fi
    printf 'Publishing run: %d clean builds of the same shape for every language (%d micro-benchmarks, %d multi-file at the equal size, %d over %d sweep points); %s.\n' \
        "$((7 * runs * 2 + 4 * runs + sweep_points * 4 * runs))" \
        "$((7 * runs * 2))" "$((4 * runs))" "$((sweep_points * 4 * runs))" "$sweep_points" "$last_run"
fi

# ── Version discovery ──────────────────────────────────────────────────────────
ZORIL_COMMIT=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
ZIG_VER=$(zig version 2>/dev/null || echo "n/a")
RUST_VER=$(rustc --version 2>/dev/null | awk '{print $2}' || echo "n/a")
HARE_VER=$(hare version 2>/dev/null | awk '{print $2}' || echo "n/a")
GCC_VER=$(gcc -dumpversion 2>/dev/null || echo "n/a")
CLANG_VER=$(clang --version 2>/dev/null | head -n 1 | awk '{print $3}' || echo "n/a")

printf "Detected Host:\n"
printf "  OS / kernel : %s\n" "$HOST_OS"
printf "  CPU model   : %s (%s cores)\n" "$HOST_CPU" "$HOST_CORES"
printf "  RAM         : %s\n" "$HOST_RAM"
printf "  Governor    : %s\n" "$HOST_GOVERNOR"
printf "  Load (1m)   : %s (idle %s)\n" "$HOST_LOAD1M" "$HOST_IDLE_CPU"
printf "  Compile runs: %d (best-of-N with 1 discarded warm-up)\n" "$COMPILE_RUNS"
printf "\n"

printf "Detected Toolchains:\n"
printf "  zoril   : %s\n" "$ZORIL_COMMIT"
printf "  zig     : %s\n" "$ZIG_VER"
printf "  rust    : %s\n" "$RUST_VER"
printf "  hare    : %s\n" "$HARE_VER"
printf "  gcc     : %s\n" "$GCC_VER"
printf "  clang   : %s\n" "$CLANG_VER"
printf "\n"

# ── Measurement helpers ───────────────────────────────────────────────────────

# time_and_rss_cmd CMD...
# Sets globals: BENCH_ELAPSED_MS, BENCH_PEAK_KB, BENCH_RC
# BENCH_PEAK_KB is the largest single process anywhere in the command's tree (a fresh subshell
# runs it, then execs the helper, which reads the subshell's RUSAGE_CHILDREN).
time_and_rss_cmd() {
    local t0 t1 rc=0
    : > "$BENCH_ERRLOG"
    rm -f "$BENCH_RSS_FILE"
    t0=$(now_ms)
    ( set +e; "$@" >/dev/null 2>"$BENCH_ERRLOG"; exec "$BENCH_MAXRSS" "$?" "$BENCH_RSS_FILE" ) || rc=$?
    t1=$(now_ms)
    BENCH_ELAPSED_MS=$((t1 - t0))
    BENCH_PEAK_KB=$(cat "$BENCH_RSS_FILE" 2>/dev/null || echo 0)
    BENCH_RC=$rc
    if [ "$rc" -ne 0 ]; then
        bench_step_failed "$rc" "$@"
    fi
}

# Stderr of the step that last ran, kept so a failing compiler can be reported with its own
# message instead of being swallowed.
BENCH_ERRLOG="$TMP_DIR/step.stderr"

# Peak memory comes from getrusage(RUSAGE_CHILDREN), not from polling /proc/<pid>: polling saw only
# the process the harness started, so a build driver's compilers (zbuild's zoril/zilc/qbe, cargo's
# rustc, hare's harec/qbe) were never measured and the drivers' few MB were published as the
# compilers' memory. The helper is built once per run with the host C compiler.
BENCH_MAXRSS="$TMP_DIR/children_maxrss"
BENCH_RSS_FILE="$TMP_DIR/step.maxrss"
${CC:-cc} -O2 -o "$BENCH_MAXRSS" "$REPO_ROOT/bench/cross_lang/children_maxrss.c" || {
    echo "bench_cross_lang: cannot build bench/cross_lang/children_maxrss.c with ${CC:-cc}" >&2
    exit 2
}

# A compile or link step did not succeed. Its stderr used to go to /dev/null, and the only
# symptom was a later `stat` on the binary it never wrote - which, under the `set -e` that
# scripts/bench_threshold_check.sh runs with, aborted the whole run *before* the threshold
# check, so a broken toolchain read as an unrelated bench failure with nothing to act on
# (found 2026-10-10, a `hare` step on this host that fails in the bench and works by hand).
#
# A Zoril step is fatal: it is the thing being measured, so its numbers are meaningless and
# must not be recorded or published. A comparison language is reported and skipped instead -
# the run continues, so a host with one broken toolchain can still gate (the gate reads only
# Zoril and gcc) and can still regenerate the docs, with the failure stated loudly here and the
# affected row left out.
bench_step_failed() {
    local rc="$1"
    shift
    printf '\n[FAIL] %s did not succeed (exit %s)\n' "$1" "$rc" >&2
    printf '       command: %s\n' "$*" >&2
    if [ -s "$BENCH_ERRLOG" ]; then
        printf '       its output:\n' >&2
        tail -n 20 "$BENCH_ERRLOG" | sed -e 's/^/       | /' >&2
    fi
    # A step of the Zoril measurement is told by its words, each taken whole: the program (or the shell
    # function `zbuild_exec` that wraps zbuild), a path into `build/` of one of Zoril's tools anywhere in
    # a `sh -c` string, or the backend, assembler or linker as a word of its own. A tool name as a
    # substring of some other word (`as` in `ReleaseFast`) made a failing zig step read as part of the
    # measurement and stop the run.
    for step_word in "$@"; do
        case "${step_word##*/}" in
            zbuild|zoril|zilc|zbuild_exec|"${BACKEND_BIN##*/}"|"${ASSEMBLER_BIN##*/}"|"${LINKER_BIN##*/}") step_is_zoril=1 ;;
        esac
        case "$step_word" in
            */build/zbuild*|*/build/zoril*|*/build/zilc*) step_is_zoril=1 ;;
        esac
    done
    if [ "${step_is_zoril:-0}" = 1 ]; then
        printf '       this step is part of the Zoril measurement: stopping.\n' >&2
        exit 1
    fi
    BENCH_SKIPPED="$BENCH_SKIPPED $1"
    printf '       %s is a comparison language: skipping its row and continuing.\n' "$1" >&2
}

# Comparison languages whose steps failed, reported once before the metrics.
BENCH_SKIPPED=""

# Byte size of a binary, or 0 when it is not there: a step that succeeded but wrote nothing must
# show up as a 0-byte row rather than aborting the run at a `stat`.
bench_sz() {
    if [ -f "$1" ]; then wc -c < "$1" | tr -d ' \t'; else echo 0; fi
}

# measure_compile PRE_RUN_CMD CMD...
# Runs 1 discarded warm-up run, then COMPILE_RUNS measured runs.
# Takes the MINIMUM elapsed time among successful runs, and the corresponding peak RSS.
# If PRE_RUN_CMD is non-empty, it is evaluated before EACH run (warm-up and measured)
# to re-clean build directories or re-touch target files.
# PRE_RUN_CMD is evaluated in a subshell: it exists to reset filesystem state (remove a cache,
# touch a file), and evaluating it in this shell let a `cd` inside it (`cargo clean`) move the
# whole run's working directory for every later step, which is not what a pre-command is for.
measure_compile() {
    local pre_cmd="$1"
    shift
    local best_ms=999999999
    local best_kb=0
    local rc=0

    # 1. Warm-up run (discarded)
    if [ -n "$pre_cmd" ]; then
        ( eval "$pre_cmd" )
    fi
    "$@"
    rc=$BENCH_RC
    if [ "$rc" -ne 0 ]; then
        BENCH_ELAPSED_MS=-1
        BENCH_PEAK_KB=0
        BENCH_RC=$rc
        return
    fi

    # 2. Best-of-N measured runs
    local iter=0
    local max_ms=0
    while [ "$iter" -lt "$COMPILE_RUNS" ]; do
        if [ -n "$pre_cmd" ]; then
            ( eval "$pre_cmd" )
        fi
        "$@"
        rc=$BENCH_RC
        if [ "$rc" -ne 0 ]; then
            BENCH_ELAPSED_MS=-1
            BENCH_PEAK_KB=0
            BENCH_RC=$rc
            return
        fi
        if [ "$BENCH_ELAPSED_MS" -lt "$best_ms" ]; then
            best_ms=$BENCH_ELAPSED_MS
            best_kb=$BENCH_PEAK_KB
        fi
        if [ "$BENCH_ELAPSED_MS" -gt "$max_ms" ]; then
            max_ms=$BENCH_ELAPSED_MS
        fi
        iter=$((iter + 1))
    done

    BENCH_ELAPSED_MS=$best_ms
    BENCH_PEAK_KB=$best_kb
    BENCH_MIN_MS=$best_ms
    BENCH_MAX_MS=$max_ms
    BENCH_SPREAD_MS=$((max_ms - best_ms))
    BENCH_SPREAD_PCT=$(awk "BEGIN { if ($best_ms > 0) printf \"%.1f\", (($max_ms - $best_ms) / $best_ms) * 100; else print \"0.0\" }")
    BENCH_RC=0
}

# measure_runtime BINARY [RUNS=3]
# Outputs best-of-N run time in ms to stdout
measure_runtime() {
    local bin="$1"
    local runs="${2:-3}"
    local best=999999999
    local i=0
    while [ "$i" -lt "$runs" ]; do
        local t0 t1 el
        t0=$(now_ms)
        if ! "$bin" >/dev/null 2>&1; then
            echo "-1"
            return
        fi
        t1=$(now_ms)
        el=$((t1 - t0))
        [ "$el" -lt "$best" ] && best=$el
        i=$((i + 1))
    done
    echo "$best"
}

# "min median max" of the numbers given, for a measurement's samples.
stats_of() {
    printf '%s\n' "$@" | sort -n | awk '{ a[NR] = $1 } END { printf "%d %d %d", a[1], a[int((NR + 1) / 2)], a[NR] }'
}

# RUNTIME_RUNS: measured runs per side in measure_runtime_pair (7 gives a stable median of
# pairwise ratios with ~1.5% spread).
RUNTIME_RUNS="${RUNTIME_RUNS:-7}"

# Time two binaries in one interleaved window, for the Zoril/gcc ratio. Measured 2026-10-10:
# timing each side separately with best-of-3 (minutes apart, other work in between) made the
# ratio itself swing 14.5% across ten gate runs while each side's own numbers stayed within
# ~7%, because a frequency-governor ramp or a background burst slows one side and not the
# other. Alternating the two sides after a discarded warm-up run each makes the same drift hit
# both alike. Sets RT_A/RT_B (ms, median of RUNTIME_RUNS samples), RT_MIN_A/RT_MAX_A and
# RT_MIN_B/RT_MAX_B, and RT_PAIR_RATIO (median of pairwise ratios), or -1 in all of them if either binary will not run.
measure_runtime_pair() {
    local bin_a="$1"
    local bin_b="$2"
    RT_A=-1; RT_B=-1; RT_MIN_A=-1; RT_MAX_A=-1; RT_MIN_B=-1; RT_MAX_B=-1; RT_PAIR_RATIO=""
    if [ ! -x "$bin_a" ] || [ ! -x "$bin_b" ]; then
        return
    fi
    # The warm-up run also decides whether the binaries run at all (a failure echoes -1).
    if [ "$(measure_runtime "$bin_a" 1)" = "-1" ] || [ "$(measure_runtime "$bin_b" 1)" = "-1" ]; then
        return
    fi
    local samples_a=""
    local samples_b=""
    local pair_ratios=""
    local i=0 ta tb r
    while [ "$i" -lt "$RUNTIME_RUNS" ]; do
        ta=$(measure_runtime "$bin_a" 1)
        tb=$(measure_runtime "$bin_b" 1)
        if [ "$ta" = "-1" ] || [ "$tb" = "-1" ]; then
            RT_A=-1; RT_B=-1; RT_PAIR_RATIO=""
            return
        fi
        samples_a="$samples_a $ta"
        samples_b="$samples_b $tb"
        if [ "$tb" -gt 0 ]; then
            r=$(awk "BEGIN { printf \"%.3f\", $ta / $tb }")
            pair_ratios="$pair_ratios $r"
        fi
        i=$((i + 1))
    done
    set -- $(stats_of $samples_a)
    RT_MIN_A=$1; RT_A=$2; RT_MAX_A=$3
    set -- $(stats_of $samples_b)
    RT_MIN_B=$1; RT_B=$2; RT_MAX_B=$3
    if [ -n "$pair_ratios" ]; then
        RT_PAIR_RATIO=$(printf '%s\n' $pair_ratios | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }')
    fi
}

check_thresholds_gate() {
    if [ ! -f "$THRESHOLDS_FILE" ]; then
        if [ "$RUN_STATUS" = "contended" ] && [ "$FORCE_RUN" -eq 0 ]; then
            printf '\nERROR: Cannot record baseline on a contended host (status: %s). Re-run on a quiet host or pass --force.\n' "$RUN_STATUS" >&2
            exit 1
        fi
        printf '\nNo threshold baseline at %s; recording current measurement as baseline.\n' "$THRESHOLDS_FILE"
        RECORD_BASELINE=1
        {
            printf '# Stable cross-language baseline thresholds (best-of-N with warm-up discard on quiet host)\n'
            printf '# axis|baseline|tolerance_pct|direction\n'
            printf 'clean_throughput_loc_s|%d|15|higher_better\n' "$tp_loc_z"
            printf 'incremental_rebuild_ms|%d|15|lower_better\n' "$c_ms_z_edit"
            printf 'runtime_ratio_vs_gcc_o2|%s|15|lower_better\n' "$z_runtime_ratio"
        } > "$THRESHOLDS_FILE"
    fi
    local gate_fail=0
    local cur b c t ok cur2 c2 ok2
    while IFS='|' read -r axis baseline tol dir; do
        [ -z "$axis" ] && continue
        case "$axis" in \#*) continue ;; esac
        cur=$(awk -F'\t' -v a="$axis" '$1==a {print $2}' "$METRICS_FILE")
        [ -z "$cur" ] && { printf '  ! no measurement for %s\n' "$axis"; continue; }
        b=$(awk "BEGIN {print $baseline}")
        c=$(awk "BEGIN {print $cur}")
        t=$(awk "BEGIN {print $tol/100.0}")
        ok=1
        if [ "$dir" = "higher_better" ]; then
            awk "BEGIN { if ($c < $b*(1-$t)) exit 1; exit 0 }" || ok=0
        else
            awk "BEGIN { if ($c > $b*(1+$t)) exit 1; exit 0 }" || ok=0
        fi
        if [ "$ok" -eq 0 ] && [ "$axis" = "runtime_ratio_vs_gcc_o2" ] && [ -x "${TMP_DIR:-}/fib_zoril" ] && [ -x "${TMP_DIR:-}/fib_gcc2" ]; then
            printf '  [RETEST] %-24s %s exceeded limit; running confirmation measurement...\n' "$axis" "$cur"
            measure_runtime_pair "$TMP_DIR/fib_zoril" "$TMP_DIR/fib_gcc2"
            cur2="${RT_PAIR_RATIO:-$(awk "BEGIN { if ($RT_B > 0) printf \"%.3f\", ($RT_A / $RT_B); else print 0 }")}"
            c2=$(awk "BEGIN {print $cur2}")
            ok2=1
            awk "BEGIN { if ($c2 > $b*(1+$t)) exit 1; exit 0 }" || ok2=0
            if [ "$ok2" -eq 1 ]; then
                printf '  [OK]  %-26s %s (baseline %s, tol %s%%) [noise retry: first was %s]\n' "$axis" "$cur2" "$baseline" "$tol" "$cur"
                ok=1
                cur="$cur2"
            else
                printf '  [FAIL] %-26s confirmation %s also regressed past baseline %s (first was %s)\n' "$axis" "$cur2" "$baseline" "$cur"
                gate_fail=1
            fi
        elif [ "$ok" -eq 1 ]; then
            printf '  [OK]  %-26s %s (baseline %s, tol %s%%)\n' "$axis" "$cur" "$baseline" "$tol"
        else
            printf '  [FAIL] %-26s %s regressed past baseline %s (%s, tol %s%%)\n' "$axis" "$cur" "$baseline" "$dir" "$tol"
            gate_fail=1
        fi
    done < "$THRESHOLDS_FILE"
    if [ "$gate_fail" -ne 0 ]; then
        echo "FAIL: performance regression detected against recorded baseline." >&2
        return 1
    fi
    printf '\nAll performance thresholds within tolerance of baseline.\n'
    return 0
}

if [ "${CHECK_THRESHOLDS_ONLY:-0}" -eq 1 ]; then
    check_thresholds_gate
    exit $?
fi

# Compile Zoril pipeline: zoril -> zilc -> qbe -> as -> ld
# Sets globals: BENCH_ELAPSED_MS, BENCH_PEAK_KB, BENCH_RC
compile_zoril_pipeline() {
    local src="$1" out_bin="$2" inc_dir="$3"
    local stem
    stem="$(basename "$src" .zrl)"
    local zil="$TMP_DIR/${stem}.zil"
    local ssa="$TMP_DIR/${stem}.ssa"
    local s="$TMP_DIR/${stem}.s"
    local o="$TMP_DIR/${stem}.o"

    local t0 t1 total_ms=0 max_rss=0

    # Step 1: Zoril
    local inc_args=""
    [ -n "$inc_dir" ] && inc_args="-I $inc_dir"
    time_and_rss_cmd "$REPO_ROOT/build/zoril" -I "stdlib=$REPO_ROOT/stdlib" $inc_args --emit-zil -o "$zil" "$src"
    [ "$BENCH_RC" -ne 0 ] && return
    total_ms=$((total_ms + BENCH_ELAPSED_MS))
    [ "$BENCH_PEAK_KB" -gt "$max_rss" ] && max_rss=$BENCH_PEAK_KB

    # Step 2: Zilc
    time_and_rss_cmd "$REPO_ROOT/build/zilc" "$zil" "$ssa"
    [ "$BENCH_RC" -ne 0 ] && return
    total_ms=$((total_ms + BENCH_ELAPSED_MS))
    [ "$BENCH_PEAK_KB" -gt "$max_rss" ] && max_rss=$BENCH_PEAK_KB

    # Step 3: QBE
    time_and_rss_cmd "$BACKEND_BIN" -o "$s" "$ssa"
    [ "$BENCH_RC" -ne 0 ] && return
    total_ms=$((total_ms + BENCH_ELAPSED_MS))
    [ "$BENCH_PEAK_KB" -gt "$max_rss" ] && max_rss=$BENCH_PEAK_KB

    # Step 4: as
    time_and_rss_cmd "$ASSEMBLER_BIN" -o "$o" "$s"
    [ "$BENCH_RC" -ne 0 ] && return
    total_ms=$((total_ms + BENCH_ELAPSED_MS))
    [ "$BENCH_PEAK_KB" -gt "$max_rss" ] && max_rss=$BENCH_PEAK_KB

    # Step 5: ld
    time_and_rss_cmd "$LINKER_BIN" -o "$out_bin" "$o" "$REPO_ROOT/build/runtime.o"
    [ "$BENCH_RC" -ne 0 ] && return
    total_ms=$((total_ms + BENCH_ELAPSED_MS))
    [ "$BENCH_PEAK_KB" -gt "$max_rss" ] && max_rss=$BENCH_PEAK_KB

    BENCH_ELAPSED_MS=$total_ms
    BENCH_PEAK_KB=$max_rss
    BENCH_RC=0
}

# TSV data collector
DATA_FIB="$TMP_DIR/fib.tsv"
DATA_ARR="$TMP_DIR/arr.tsv"
DATA_MF="$TMP_DIR/mf.tsv"
printf '' > "$DATA_FIB"
printf '' > "$DATA_ARR"
printf '' > "$DATA_MF"
DATA_SWEEP="$TMP_DIR/sweep.tsv"
: > "$DATA_SWEEP"

# ── Comparison cache ─────────────────────────────────────────────────────────
# The other languages' numbers change only with the benchmark sources, their
# toolchains or the host, and the threshold gate reads none of them (only Zoril's
# and gcc's). So --check-thresholds reuses their last measurement from
# build/bench/compare/<key>/ and measures only Zoril and gcc, unless --update-doc
# or --record asks for a full run or nothing is cached yet.
CMP_KEY=$( { cat "$BENCH_DIR"/fib/* "$BENCH_DIR"/array_loop/* "$BENCH_DIR"/gen_multifile.lua
             echo "$ZIG_VER|$RUST_VER|$HARE_VER|$CLANG_VER|$HOST_CPU|$COMPILE_RUNS"
             env | grep '^MF_' | sort; } | cksum | cut -d' ' -f1)
CMP_CACHE="$REPO_ROOT/build/bench/compare/$CMP_KEY"
USE_CMP_CACHE=0
if [ "$UPDATE_DOC" -eq 0 ] && [ "$RECORD_BASELINE" -eq 0 ] && [ -f "$CMP_CACHE/complete" ]; then
    USE_CMP_CACHE=1
fi

# measure_others — true when the non-gating languages must be measured this run.
# When checking thresholds (and not updating docs or recording baselines), only
# Zoril and gcc are needed for the gate; other languages are skipped or replayed from cache.
# When --update-doc or --record is set, USE_CMP_CACHE is 0, forcing a full fresh measurement.
measure_others() {
    [ "$USE_CMP_CACHE" -eq 0 ]
}

# replay_others WORKLOAD DATA_FILE — append the cached rows and print them.
replay_others() {
    [ -f "$CMP_CACHE/$1.tsv" ] || return 0
    cat "$CMP_CACHE/$1.tsv" >> "$2"
    if [ "$1" = mf ]; then
        awk -F'\t' '{ printf "  %-22s: (cached) Clean %6d ms | Touch %5d ms | Edit %5d ms | Bin %7d B\n", $1, $4, $6, $7, $8 }' "$CMP_CACHE/$1.tsv"
    else
        awk -F'\t' '{ printf "  %-20s: (cached) compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n", $1, $3, $4 / 1024, $5, $6 }' "$CMP_CACHE/$1.tsv"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# 1. fib(38) × 3
# ──────────────────────────────────────────────────────────────────────────────
printf "=== Workload 1: fib(38) × 3 ===\n"
FIB_DIR="$BENCH_DIR/fib"

# Zoril
measure_compile "" compile_zoril_pipeline "$FIB_DIR/fib.zrl" "$TMP_DIR/fib_zoril" ""
z_fib_compile_ms=$BENCH_ELAPSED_MS
z_fib_peak_kb=$BENCH_PEAK_KB
z_fib_sz=$(bench_sz "$TMP_DIR/fib_zoril")

# gcc -O0
measure_compile "" time_and_rss_cmd gcc -O0 -o "$TMP_DIR/fib_gcc0" "$FIB_DIR/fib.c"
c0_fib_compile_ms=$BENCH_ELAPSED_MS
c0_fib_peak_kb=$BENCH_PEAK_KB
c0_fib_sz=$(bench_sz "$TMP_DIR/fib_gcc0")

# gcc -O2
measure_compile "" time_and_rss_cmd gcc -O2 -o "$TMP_DIR/fib_gcc2" "$FIB_DIR/fib.c"
c2_fib_compile_ms=$BENCH_ELAPSED_MS
c2_fib_peak_kb=$BENCH_PEAK_KB
c2_fib_sz=$(bench_sz "$TMP_DIR/fib_gcc2")

# The ratio's two sides, timed in one interleaved window (see measure_runtime_pair). Both
# binaries are built first so the window has nothing between the two sides but each other.
measure_runtime_pair "$TMP_DIR/fib_zoril" "$TMP_DIR/fib_gcc2"
if [ "$RT_A" -lt 0 ] || [ "$RT_B" -lt 0 ]; then
    r_ms_zoril_fib=$(measure_runtime "$TMP_DIR/fib_zoril")
    r_ms_gcc2_fib=$(measure_runtime "$TMP_DIR/fib_gcc2")
    r_ms_pair_ratio=""
else
    r_ms_zoril_fib=$RT_A
    r_ms_gcc2_fib=$RT_B
    r_ms_pair_ratio=$RT_PAIR_RATIO
fi
r_ms_gcc0_fib=$(measure_runtime "$TMP_DIR/fib_gcc0")

# Printed and recorded in the same order as before, with the measured run times.
r_ms=$r_ms_zoril_fib
printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
    "Zoril" "$z_fib_compile_ms" "$(awk "BEGIN {print $z_fib_peak_kb/1024}")" "$r_ms" "$z_fib_sz"
printf 'Zoril\tzoril\t%d\t%d\t%d\t%d\n' "$z_fib_compile_ms" "$z_fib_peak_kb" "$r_ms" "$z_fib_sz" >> "$DATA_FIB"

r_ms=$r_ms_gcc0_fib
printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
    "gcc -O0" "$c0_fib_compile_ms" "$(awk "BEGIN {print $c0_fib_peak_kb/1024}")" "$r_ms" "$c0_fib_sz"
printf 'gcc -O0\tgcc\t%d\t%d\t%d\t%d\n' "$c0_fib_compile_ms" "$c0_fib_peak_kb" "$r_ms" "$c0_fib_sz" >> "$DATA_FIB"

r_ms=$r_ms_gcc2_fib
printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
    "gcc -O2" "$c2_fib_compile_ms" "$(awk "BEGIN {print $c2_fib_peak_kb/1024}")" "$r_ms" "$c2_fib_sz"
printf 'gcc -O2\tgcc\t%d\t%d\t%d\t%d\n' "$c2_fib_compile_ms" "$c2_fib_peak_kb" "$r_ms" "$c2_fib_sz" >> "$DATA_FIB"

if measure_others; then
# clang -O2
if command -v clang >/dev/null 2>&1; then
    measure_compile "" time_and_rss_cmd clang -O2 -o "$TMP_DIR/fib_clang2" "$FIB_DIR/fib.c"
    r_ms=$(measure_runtime "$TMP_DIR/fib_clang2")
    sz=$(bench_sz "$TMP_DIR/fib_clang2")
    printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
        "clang -O2" "$BENCH_ELAPSED_MS" "$(awk "BEGIN {print $BENCH_PEAK_KB/1024}")" "$r_ms" "$sz"
    printf 'clang -O2\tclang\t%d\t%d\t%d\t%d\n' "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" "$r_ms" "$sz" >> "$DATA_FIB"
fi

# Zig (ReleaseFast)
if command -v zig >/dev/null 2>&1; then
    measure_compile "" time_and_rss_cmd zig build-exe -O ReleaseFast -femit-bin="$TMP_DIR/fib_zig" "$FIB_DIR/fib.zig"
    r_ms=$(measure_runtime "$TMP_DIR/fib_zig")
    sz=$(bench_sz "$TMP_DIR/fib_zig")
    printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
        "Zig (ReleaseFast)" "$BENCH_ELAPSED_MS" "$(awk "BEGIN {print $BENCH_PEAK_KB/1024}")" "$r_ms" "$sz"
    printf 'Zig (ReleaseFast)\tzig\t%d\t%d\t%d\t%d\n' "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" "$r_ms" "$sz" >> "$DATA_FIB"
fi

# Rust (-O)
if command -v rustc >/dev/null 2>&1; then
    measure_compile "" time_and_rss_cmd rustc -O -o "$TMP_DIR/fib_rust" "$FIB_DIR/fib.rs"
    r_ms=$(measure_runtime "$TMP_DIR/fib_rust")
    sz=$(bench_sz "$TMP_DIR/fib_rust")
    printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
        "Rust (-O)" "$BENCH_ELAPSED_MS" "$(awk "BEGIN {print $BENCH_PEAK_KB/1024}")" "$r_ms" "$sz"
    printf 'Rust (-O)\trust\t%d\t%d\t%d\t%d\n' "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" "$r_ms" "$sz" >> "$DATA_FIB"
fi

# Hare
if command -v hare >/dev/null 2>&1; then
    measure_compile "" time_and_rss_cmd hare build -o "$TMP_DIR/fib_hare" "$FIB_DIR/fib.ha"
    r_ms=$(measure_runtime "$TMP_DIR/fib_hare")
    sz=$(bench_sz "$TMP_DIR/fib_hare")
    printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
        "Hare" "$BENCH_ELAPSED_MS" "$(awk "BEGIN {print $BENCH_PEAK_KB/1024}")" "$r_ms" "$sz"
    printf 'Hare\thare\t%d\t%d\t%d\t%d\n' "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" "$r_ms" "$sz" >> "$DATA_FIB"
fi
else
    replay_others fib "$DATA_FIB"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 2. Array loop
# ──────────────────────────────────────────────────────────────────────────────
printf "\n=== Workload 2: 4096-element array loop × 500000 ===\n"
ARR_DIR="$BENCH_DIR/array_loop"

# Zoril
measure_compile "" compile_zoril_pipeline "$ARR_DIR/array_loop.zrl" "$TMP_DIR/arr_zoril" ""
r_ms=$(measure_runtime "$TMP_DIR/arr_zoril" 5)
sz=$(bench_sz "$TMP_DIR/arr_zoril")
printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
    "Zoril" "$BENCH_ELAPSED_MS" "$(awk "BEGIN {print $BENCH_PEAK_KB/1024}")" "$r_ms" "$sz"
printf 'Zoril\tzoril\t%d\t%d\t%d\t%d\n' "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" "$r_ms" "$sz" >> "$DATA_ARR"

# Zoril (raw ptr)
measure_compile "" compile_zoril_pipeline "$ARR_DIR/array_loop_ptr.zrl" "$TMP_DIR/arr_zoril_ptr" ""
r_ptr_ms=$(measure_runtime "$TMP_DIR/arr_zoril_ptr" 5)
sz_ptr=$(bench_sz "$TMP_DIR/arr_zoril_ptr")
printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
    "Zoril (raw ptr)" "$BENCH_ELAPSED_MS" "$(awk "BEGIN {print $BENCH_PEAK_KB/1024}")" "$r_ptr_ms" "$sz_ptr"
printf 'Zoril (raw ptr)\tzoril_ptr\t%d\t%d\t%d\t%d\n' "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" "$r_ptr_ms" "$sz_ptr" >> "$DATA_ARR"

ASM_IDENTICAL=0
if cmp -s "$TMP_DIR/array_loop.s" "$TMP_DIR/array_loop_ptr.s"; then
    ASM_IDENTICAL=1
    printf '  ✓ array_loop.zrl and array_loop_ptr.zrl compile to BYTE-IDENTICAL assembly\n'
fi

# gcc -O0
measure_compile "" time_and_rss_cmd gcc -O0 -o "$TMP_DIR/arr_gcc0" "$ARR_DIR/array_loop.c"
r_ms=$(measure_runtime "$TMP_DIR/arr_gcc0")
sz=$(bench_sz "$TMP_DIR/arr_gcc0")
printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
    "gcc -O0" "$BENCH_ELAPSED_MS" "$(awk "BEGIN {print $BENCH_PEAK_KB/1024}")" "$r_ms" "$sz"
printf 'gcc -O0\tgcc\t%d\t%d\t%d\t%d\n' "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" "$r_ms" "$sz" >> "$DATA_ARR"

# gcc -O2
measure_compile "" time_and_rss_cmd gcc -O2 -o "$TMP_DIR/arr_gcc2" "$ARR_DIR/array_loop.c"
r_ms=$(measure_runtime "$TMP_DIR/arr_gcc2")
sz=$(bench_sz "$TMP_DIR/arr_gcc2")
printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
    "gcc -O2" "$BENCH_ELAPSED_MS" "$(awk "BEGIN {print $BENCH_PEAK_KB/1024}")" "$r_ms" "$sz"
printf 'gcc -O2\tgcc\t%d\t%d\t%d\t%d\n' "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" "$r_ms" "$sz" >> "$DATA_ARR"

if measure_others; then
# clang -O2
if command -v clang >/dev/null 2>&1; then
    measure_compile "" time_and_rss_cmd clang -O2 -o "$TMP_DIR/arr_clang2" "$ARR_DIR/array_loop.c"
    r_ms=$(measure_runtime "$TMP_DIR/arr_clang2")
    sz=$(bench_sz "$TMP_DIR/arr_clang2")
    printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
        "clang -O2" "$BENCH_ELAPSED_MS" "$(awk "BEGIN {print $BENCH_PEAK_KB/1024}")" "$r_ms" "$sz"
    printf 'clang -O2\tclang\t%d\t%d\t%d\t%d\n' "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" "$r_ms" "$sz" >> "$DATA_ARR"
fi

# Zig (ReleaseFast)
if command -v zig >/dev/null 2>&1; then
    measure_compile "" time_and_rss_cmd zig build-exe -O ReleaseFast -femit-bin="$TMP_DIR/arr_zig" "$ARR_DIR/array_loop.zig"
    r_ms=$(measure_runtime "$TMP_DIR/arr_zig")
    sz=$(bench_sz "$TMP_DIR/arr_zig")
    printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
        "Zig (ReleaseFast)" "$BENCH_ELAPSED_MS" "$(awk "BEGIN {print $BENCH_PEAK_KB/1024}")" "$r_ms" "$sz"
    printf 'Zig (ReleaseFast)\tzig\t%d\t%d\t%d\t%d\n' "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" "$r_ms" "$sz" >> "$DATA_ARR"
fi

# Rust (-O)
if command -v rustc >/dev/null 2>&1; then
    measure_compile "" time_and_rss_cmd rustc -O -o "$TMP_DIR/arr_rust" "$ARR_DIR/array_loop.rs"
    r_ms=$(measure_runtime "$TMP_DIR/arr_rust")
    sz=$(bench_sz "$TMP_DIR/arr_rust")
    printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
        "Rust (-O)" "$BENCH_ELAPSED_MS" "$(awk "BEGIN {print $BENCH_PEAK_KB/1024}")" "$r_ms" "$sz"
    printf 'Rust (-O)\trust\t%d\t%d\t%d\t%d\n' "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" "$r_ms" "$sz" >> "$DATA_ARR"
fi

# Hare
if command -v hare >/dev/null 2>&1; then
    measure_compile "" time_and_rss_cmd hare build -o "$TMP_DIR/arr_hare" "$ARR_DIR/array_loop.ha"
    r_ms=$(measure_runtime "$TMP_DIR/arr_hare")
    sz=$(bench_sz "$TMP_DIR/arr_hare")
    printf '  %-20s: compile %6d ms (RSS %5.1f MB) | run %6d ms | bin %7d B\n' \
        "Hare" "$BENCH_ELAPSED_MS" "$(awk "BEGIN {print $BENCH_PEAK_KB/1024}")" "$r_ms" "$sz"
    printf 'Hare\thare\t%d\t%d\t%d\t%d\n' "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" "$r_ms" "$sz" >> "$DATA_ARR"
fi
else
    replay_others arr "$DATA_ARR"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 3. Multi-file project: clean build & touch-one-file rebuild
#    Source is generated procedurally by bench/cross_lang/gen_multifile.lua into
#    build/bench/multifile — nothing stored in the repo.
#
#    Cross-language comparison: one equal program shape for every language (the
#    generator's default, 100 modules x 30 funcs, ~30k LOC), so the clean,
#    rebuild and memory numbers are comparable between compilers.
#
#    Regression gate: the four threshold axes are Zoril's and gcc's only, and their
#    baselines were recorded on a small project, so a gate run pins Zoril to
#    MF_GATE_MODULES x MF_GATE_FUNCS (2,931 LOC — recorded in
#    bench/cross_lang/thresholds.cfg) and takes the other languages' rows from the
#    compare cache rather than rebuilding them.
#
#    Override any language with MF_<LANG>_MODULES / MF_<LANG>_FUNCS.
# ──────────────────────────────────────────────────────────────────────────────
printf "\n=== Workload 3: Multi-file Project (Full vs Incremental Rebuild) ===\n"
MF_DIR="$REPO_ROOT/build/bench/multifile"

# The size the regression gate measures Zoril at, so its baselines stay comparable.
MF_GATE_MODULES=25
MF_GATE_FUNCS=10

# Project sizes for this run. Every language gets the same shape (the generator's equal
# default); a run whose purpose includes the gated axes (the preflight gate, or --record, which
# writes their baselines) pins Zoril to MF_GATE_MODULES x MF_GATE_FUNCS instead, so those
# baselines stay comparable. The two purposes need different sizes, so one run cannot do both.
# The counts are passed explicitly rather than left to the Lua defaults, so the numbers this
# script publishes (fns/s, and the size stated beside every table) are exactly what it generated.
mf_zoril_modules=100; mf_zoril_funcs=30
mf_zig_modules=100;   mf_zig_funcs=30
mf_rust_modules=100;  mf_rust_funcs=30
mf_hare_modules=100;  mf_hare_funcs=30
mf_pins_gate=0
[ "$CHECK_THRESHOLDS" -eq 1 ] && mf_pins_gate=1
if [ "$RECORD_BASELINE" -eq 1 ]; then
    if [ "$UPDATE_DOC" -eq 1 ]; then
        printf 'ERROR: --record and --update-doc run the multi-file project at different sizes:\n' >&2
        printf '       --record writes the gated axes, which are pinned to the gate size, while\n' >&2
        printf '       --update-doc publishes the equal-size cross-language comparison. Run them separately.\n' >&2
        exit 2
    fi
    mf_pins_gate=1
fi
if [ "$mf_pins_gate" -eq 1 ]; then
    mf_zoril_modules=$MF_GATE_MODULES
    mf_zoril_funcs=$MF_GATE_FUNCS
fi
[ -n "$MF_ZORIL_MODULES" ] && mf_zoril_modules="$MF_ZORIL_MODULES"
[ -n "$MF_ZORIL_FUNCS"   ] && mf_zoril_funcs="$MF_ZORIL_FUNCS"
[ -n "$MF_ZIG_MODULES"   ] && mf_zig_modules="$MF_ZIG_MODULES"
[ -n "$MF_ZIG_FUNCS"     ] && mf_zig_funcs="$MF_ZIG_FUNCS"
[ -n "$MF_RUST_MODULES"  ] && mf_rust_modules="$MF_RUST_MODULES"
[ -n "$MF_RUST_FUNCS"    ] && mf_rust_funcs="$MF_RUST_FUNCS"
[ -n "$MF_HARE_MODULES"  ] && mf_hare_modules="$MF_HARE_MODULES"
[ -n "$MF_HARE_FUNCS"    ] && mf_hare_funcs="$MF_HARE_FUNCS"

mf_extra="--zoril-modules $mf_zoril_modules --zoril-funcs $mf_zoril_funcs"
mf_extra="$mf_extra --zig-modules $mf_zig_modules --zig-funcs $mf_zig_funcs"
mf_extra="$mf_extra --rust-modules $mf_rust_modules --rust-funcs $mf_rust_funcs"
mf_extra="$mf_extra --hare-modules $mf_hare_modules --hare-funcs $mf_hare_funcs"

printf "  Generating per-language projects into %s (Zoril %sx%s) ...\n" \
    "$MF_DIR" "$mf_zoril_modules" "$mf_zoril_funcs"
rm -rf "$MF_DIR"
# shellcheck disable=SC2086
lua "$REPO_ROOT/bench/cross_lang/gen_multifile.lua" --out-dir "$MF_DIR" $mf_extra

# Zoril
if [ ! -x "$REPO_ROOT/build/zbuild" ]; then
    make -C "$REPO_ROOT" build/zbuild
fi
z_dir="$MF_DIR/zoril"
fns_z=$((mf_zoril_modules * mf_zoril_funcs))
loc_z=$(wc -l "$z_dir"/*.zrl | awk 'END{print $1}')
zbuild_exec() {
    "$REPO_ROOT/build/zbuild" -o "$TMP_DIR/mf_zoril" \
        -I "stdlib=$REPO_ROOT/stdlib" -I "$z_dir" \
        --cache-dir "$z_dir/.zoril-cache" \
        --compiler "$REPO_ROOT/build/zoril" \
        --zilc "$REPO_ROOT/build/zilc" \
        --qbe "$BACKEND_BIN" \
        "$z_dir/main.zrl"
}

# 1. Clean build
measure_compile "rm -rf '$z_dir/.zoril-cache' '$TMP_DIR/mf_zoril'" \
    time_and_rss_cmd zbuild_exec
c_ms_z_clean=$BENCH_ELAPSED_MS
c_min_z_clean=$BENCH_MIN_MS
c_max_z_clean=$BENCH_MAX_MS
c_spread_z_clean=$BENCH_SPREAD_PCT
rss_z_clean=$BENCH_PEAK_KB
sz_z=$(bench_sz "$TMP_DIR/mf_zoril")
tp_loc_z=$(awk "BEGIN {printf \"%d\", ($loc_z * 1000) / $c_ms_z_clean}")
tp_fns_z=$(awk "BEGIN {printf \"%d\", ($fns_z * 1000) / $c_ms_z_clean}")

# 2. Touch rebuild (mtime only)
measure_compile "touch '$z_dir/mod0.zrl'" \
    time_and_rss_cmd zbuild_exec
c_ms_z_touch=$BENCH_ELAPSED_MS
rss_z_touch=$BENCH_PEAK_KB

# 3. Content edit rebuild (body edit)
measure_compile "lua '$REPO_ROOT/bench/cross_lang/gen_multifile.lua' --out-dir '$MF_DIR' --toggle-body zoril" \
    time_and_rss_cmd zbuild_exec
c_ms_z_edit=$BENCH_ELAPSED_MS
rss_z_edit=$BENCH_PEAK_KB
lua "$REPO_ROOT/bench/cross_lang/gen_multifile.lua" --out-dir "$MF_DIR" --revert zoril
zbuild_exec >/dev/null 2>&1 || true

# 4. Signature change rebuild (1 module + dependants)
measure_compile "lua '$REPO_ROOT/bench/cross_lang/gen_multifile.lua' --out-dir '$MF_DIR' --toggle-sig zoril" \
    time_and_rss_cmd zbuild_exec
c_ms_z_sig=$BENCH_ELAPSED_MS
lua "$REPO_ROOT/bench/cross_lang/gen_multifile.lua" --out-dir "$MF_DIR" --revert zoril
zbuild_exec >/dev/null 2>&1 || true

speedup_z=$(awk "BEGIN {printf \"%.1f\", (($c_ms_z_clean - $c_ms_z_edit) / $c_ms_z_clean) * 100}")
printf '  %-22s: %5d LOC (%4d fns) | Clean %6d ms [spread: %d..%d ms, +%s%%] (%5d LOC/s, %3d fns/s) | Touch %5d ms | Edit %5d ms (%s%%) | Bin %7d B\n' \
    "Zoril" "$loc_z" "$fns_z" "$c_ms_z_clean" "$c_min_z_clean" "$c_max_z_clean" "$c_spread_z_clean" "$tp_loc_z" "$tp_fns_z" "$c_ms_z_touch" "$c_ms_z_edit" "$speedup_z" "$sz_z"
printf '    ↳ Signature change rebuild (1 mod + dependants): %d ms\n' "$c_ms_z_sig"
printf 'Zoril\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n' "$fns_z" "$loc_z" "$c_ms_z_clean" "$rss_z_clean" "$c_ms_z_touch" "$c_ms_z_edit" "$sz_z" "$c_ms_z_sig" >> "$DATA_MF"

if measure_others; then
# Zig (using zig build with modular build.zig)
if command -v zig >/dev/null 2>&1; then
    zig_dir="$MF_DIR/zig"
    fns_zig=$((mf_zig_modules * mf_zig_funcs))
    loc_zig=$(wc -l "$zig_dir"/*.zig | awk 'END{print $1}')
    measure_compile "rm -rf '$zig_dir/.zig-cache' '$zig_dir/zig-out'" \
        time_and_rss_cmd sh -c "cd '$zig_dir' && zig build -Doptimize=$MF_ZIG_MODE"
    c_ms_zig_clean=$BENCH_ELAPSED_MS
    c_min_zig_clean=$BENCH_MIN_MS
    c_max_zig_clean=$BENCH_MAX_MS
    c_spread_zig_clean=$BENCH_SPREAD_PCT
    rss_zig_clean=$BENCH_PEAK_KB
    sz_zig=$(bench_sz "$zig_dir/zig-out/bin/mf_zig")
    tp_loc_zig=$(awk "BEGIN {printf \"%d\", ($loc_zig * 1000) / $c_ms_zig_clean}")
    tp_fns_zig=$(awk "BEGIN {printf \"%d\", ($fns_zig * 1000) / $c_ms_zig_clean}")

    measure_compile "touch '$zig_dir/mod0.zig'" \
        time_and_rss_cmd sh -c "cd '$zig_dir' && zig build -Doptimize=$MF_ZIG_MODE"
    c_ms_zig_touch=$BENCH_ELAPSED_MS
    rss_zig_touch=$BENCH_PEAK_KB

    measure_compile "lua '$REPO_ROOT/bench/cross_lang/gen_multifile.lua' --out-dir '$MF_DIR' --toggle-body zig" \
        time_and_rss_cmd sh -c "cd '$zig_dir' && zig build -Doptimize=$MF_ZIG_MODE"
    c_ms_zig_edit=$BENCH_ELAPSED_MS
    rss_zig_edit=$BENCH_PEAK_KB
    lua "$REPO_ROOT/bench/cross_lang/gen_multifile.lua" --out-dir "$MF_DIR" --revert zig
    sh -c "cd '$zig_dir' && zig build -Doptimize=$MF_ZIG_MODE" >/dev/null 2>&1 || true

    speedup_zig=$(awk "BEGIN {printf \"%.1f\", (($c_ms_zig_clean - $c_ms_zig_edit) / $c_ms_zig_clean) * 100}")
    printf '  %-22s: %5d LOC (%4d fns) | Clean %6d ms [spread: %d..%d ms, +%s%%] (%5d LOC/s, %3d fns/s) | Touch %5d ms | Edit %5d ms (%s%%) | Bin %7d B\n' \
        "Zig ($MF_ZIG_MODE)" "$loc_zig" "$fns_zig" "$c_ms_zig_clean" "$c_min_zig_clean" "$c_max_zig_clean" "$c_spread_zig_clean" "$tp_loc_zig" "$tp_fns_zig" "$c_ms_zig_touch" "$c_ms_zig_edit" "$speedup_zig" "$sz_zig"
    printf 'Zig (%s)\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t0\n' "$MF_ZIG_MODE" "$fns_zig" "$loc_zig" "$c_ms_zig_clean" "$rss_zig_clean" "$c_ms_zig_touch" "$c_ms_zig_edit" "$sz_zig" >> "$DATA_MF"
fi

# Rust (cargo)
if command -v cargo >/dev/null 2>&1; then
    rust_dir="$MF_DIR/rust"
    fns_rust=$((mf_rust_modules * mf_rust_funcs))
    loc_rust=$(wc -l "$rust_dir"/src/*.rs | awk 'END{print $1}')
    measure_compile "cd '$rust_dir' && cargo clean >/dev/null 2>&1" \
        time_and_rss_cmd cargo build $RUST_PROFILE_ARGS --manifest-path "$rust_dir/Cargo.toml"
    c_ms_rust_clean=$BENCH_ELAPSED_MS
    c_min_rust_clean=$BENCH_MIN_MS
    c_max_rust_clean=$BENCH_MAX_MS
    c_spread_rust_clean=$BENCH_SPREAD_PCT
    rss_rust_clean=$BENCH_PEAK_KB
    # cargo names its target directory after the profile (dev -> target/debug).
    rust_target="release"
    if [ "$MF_RUST_PROFILE" = "dev" ]; then rust_target="debug"; fi
    sz_rust=$(bench_sz "$rust_dir/target/$rust_target/multifile_bench")
    tp_loc_rust=$(awk "BEGIN {printf \"%d\", ($loc_rust * 1000) / $c_ms_rust_clean}")
    tp_fns_rust=$(awk "BEGIN {printf \"%d\", ($fns_rust * 1000) / $c_ms_rust_clean}")

    measure_compile "touch '$rust_dir/src/mod0.rs'" \
        time_and_rss_cmd cargo build $RUST_PROFILE_ARGS --manifest-path "$rust_dir/Cargo.toml"
    c_ms_rust_touch=$BENCH_ELAPSED_MS
    rss_rust_touch=$BENCH_PEAK_KB

    measure_compile "lua '$REPO_ROOT/bench/cross_lang/gen_multifile.lua' --out-dir '$MF_DIR' --toggle-body rust" \
        time_and_rss_cmd cargo build $RUST_PROFILE_ARGS --manifest-path "$rust_dir/Cargo.toml"
    c_ms_rust_edit=$BENCH_ELAPSED_MS
    rss_rust_edit=$BENCH_PEAK_KB
    lua "$REPO_ROOT/bench/cross_lang/gen_multifile.lua" --out-dir "$MF_DIR" --revert rust
    cargo build $RUST_PROFILE_ARGS --manifest-path "$rust_dir/Cargo.toml" >/dev/null 2>&1 || true

    speedup_rust=$(awk "BEGIN {printf \"%.1f\", (($c_ms_rust_clean - $c_ms_rust_edit) / $c_ms_rust_clean) * 100}")
    printf '  %-22s: %5d LOC (%4d fns) | Clean %6d ms [spread: %d..%d ms, +%s%%] (%5d LOC/s, %3d fns/s) | Touch %5d ms | Edit %5d ms (%s%%) | Bin %7d B\n' \
        "Rust (Cargo $MF_RUST_PROFILE)" "$loc_rust" "$fns_rust" "$c_ms_rust_clean" "$c_min_rust_clean" "$c_max_rust_clean" "$c_spread_rust_clean" "$tp_loc_rust" "$tp_fns_rust" "$c_ms_rust_touch" "$c_ms_rust_edit" "$speedup_rust" "$sz_rust"
    printf 'Rust (Cargo %s)\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t0\n' "$MF_RUST_PROFILE" "$fns_rust" "$loc_rust" "$c_ms_rust_clean" "$rss_rust_clean" "$c_ms_rust_touch" "$c_ms_rust_edit" "$sz_rust" >> "$DATA_MF"
fi

# Hare (modules live in hare/modN/modN.ha subdirectories — Hare's module layout)
# Must cd into the directory: hare resolves submodule dirs relative to CWD.
if command -v hare >/dev/null 2>&1; then
    hare_dir="$MF_DIR/hare"
    fns_hare=$((mf_hare_modules * mf_hare_funcs))
    loc_hare=$(find "$hare_dir" -name '*.ha' | xargs wc -l | awk 'END{print $1}')
    HARE_CACHE_DIR="$TMP_DIR/harecache"
    measure_compile "rm -rf '$HARE_CACHE_DIR'" \
        time_and_rss_cmd sh -c "cd '$hare_dir' && HARECACHE='$HARE_CACHE_DIR' hare build -o '$TMP_DIR/mf_hare' ."
    c_ms_hare_clean=$BENCH_ELAPSED_MS
    c_min_hare_clean=$BENCH_MIN_MS
    c_max_hare_clean=$BENCH_MAX_MS
    c_spread_hare_clean=$BENCH_SPREAD_PCT
    rss_hare_clean=$BENCH_PEAK_KB
    sz_hare=$(bench_sz "$TMP_DIR/mf_hare")
    tp_loc_hare=$(awk "BEGIN {printf \"%d\", ($loc_hare * 1000) / $c_ms_hare_clean}")
    tp_fns_hare=$(awk "BEGIN {printf \"%d\", ($fns_hare * 1000) / $c_ms_hare_clean}")

    measure_compile "touch '$hare_dir/mod0/mod0.ha'" \
        time_and_rss_cmd sh -c "cd '$hare_dir' && HARECACHE='$HARE_CACHE_DIR' hare build -o '$TMP_DIR/mf_hare' ."
    c_ms_hare_touch=$BENCH_ELAPSED_MS
    rss_hare_touch=$BENCH_PEAK_KB

    measure_compile "lua '$REPO_ROOT/bench/cross_lang/gen_multifile.lua' --out-dir '$MF_DIR' --toggle-body hare" \
        time_and_rss_cmd sh -c "cd '$hare_dir' && HARECACHE='$HARE_CACHE_DIR' hare build -o '$TMP_DIR/mf_hare' ."
    c_ms_hare_edit=$BENCH_ELAPSED_MS
    rss_hare_edit=$BENCH_PEAK_KB
    lua "$REPO_ROOT/bench/cross_lang/gen_multifile.lua" --out-dir "$MF_DIR" --revert hare
    sh -c "cd '$hare_dir' && HARECACHE='$HARE_CACHE_DIR' hare build -o '$TMP_DIR/mf_hare' ." >/dev/null 2>&1 || true

    speedup_hare=$(awk "BEGIN {printf \"%.1f\", (($c_ms_hare_clean - $c_ms_hare_edit) / $c_ms_hare_clean) * 100}")
    printf '  %-22s: %5d LOC (%4d fns) | Clean %6d ms [spread: %d..%d ms, +%s%%] (%5d LOC/s, %3d fns/s) | Touch %5d ms | Edit %5d ms (%s%%) | Bin %7d B\n' \
        "Hare" "$loc_hare" "$fns_hare" "$c_ms_hare_clean" "$c_min_hare_clean" "$c_max_hare_clean" "$c_spread_hare_clean" "$tp_loc_hare" "$tp_fns_hare" "$c_ms_hare_touch" "$c_ms_hare_edit" "$speedup_hare" "$sz_hare"
    printf 'Hare\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t0\n' "$fns_hare" "$loc_hare" "$c_ms_hare_clean" "$rss_hare_clean" "$c_ms_hare_touch" "$c_ms_hare_edit" "$sz_hare" >> "$DATA_MF"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 3c. Optimized builds on a realistic shape (full-data runs only). Workload 3 compiles the flat
#     shape - main calls every generated function in one straight line - with each language's
#     unoptimized baseline mode, because that shape defeats whole-module optimization (Zig
#     ReleaseFast and ReleaseSafe pass 30 minutes on it; rustc's release profile aborts inside
#     LLVM). This pass compiles a call tree instead (each module's driver calls its own functions,
#     main calls the drivers) with the optimizing mode, at the same generated size: Zig
#     ReleaseFast and Rust --release. Zoril and Hare have no optimization level to raise, so their
#     rows in workload 3 are already their build of the realistic shape.
#     A build that does not finish within MF_OPT_TIMEOUT seconds is reported as such, not hidden
#     and not switched to another mode: Zig's whole-module pass over 3,000 generated functions
#     does not finish, on the tree shape any more than on the flat one (measured 2026-10-10).
# ──────────────────────────────────────────────────────────────────────────────
DATA_MFOPT="$TMP_DIR/mfopt.tsv"
MF_OPT_TIMEOUT="${MF_OPT_TIMEOUT:-300}"
MF_TREE_DIR="$REPO_ROOT/build/bench/multifile_tree"
if [ "$UPDATE_DOC" -eq 1 ] || [ "$RECORD_BASELINE" -eq 1 ]; then
    printf "\n=== Workload 3c: Optimized builds on a realistic shape ===\n"
    rm -rf "$MF_TREE_DIR"
    lua "$REPO_ROOT/bench/cross_lang/gen_multifile.lua" --out-dir "$MF_TREE_DIR" --shape tree \
        --zoril-modules "$mf_zoril_modules" --zoril-funcs "$mf_zoril_funcs" \
        --zig-modules "$mf_zig_modules" --zig-funcs "$mf_zig_funcs" \
        --rust-modules "$mf_rust_modules" --rust-funcs "$mf_rust_funcs" \
        --hare-modules "$mf_hare_modules" --hare-funcs "$mf_hare_funcs" > /dev/null
    : > "$DATA_MFOPT"

    # One capped attempt each: not finishing is a result of this pass, not a failed step, so it is
    # recorded rather than reported through the fatal/skip path workload 3 uses.
    tree_zig_fns=$((mf_zig_modules * mf_zig_funcs))
    tree_zig_loc=$(wc -l "$MF_TREE_DIR/zig"/*.zig | awk 'END{print $1}')
    tree_zig_ms=-1
    tree_zig_note="did not finish within ${MF_OPT_TIMEOUT}s"
    tree_zig_sz=0
    started=$(now_ms)
    if timeout -k 5s "$MF_OPT_TIMEOUT" sh -c "cd '$MF_TREE_DIR/zig' && zig build -Doptimize=ReleaseFast" > "$BENCH_ERRLOG" 2>&1; then
        tree_zig_ms=$(( $(now_ms) - started ))
        tree_zig_sz=$(bench_sz "$MF_TREE_DIR/zig/zig-out/bin/mf_zig")
        tree_zig_note="ok"
    fi
    printf '  %-22s: %5d LOC (%4d fns) | Clean %s | Bin %d B\n' \
        "Zig (ReleaseFast)" "$tree_zig_loc" "$tree_zig_fns" \
        "$([ "$tree_zig_ms" -gt 0 ] && echo "${tree_zig_ms} ms" || echo "$tree_zig_note")" "$tree_zig_sz"
    printf 'Zig (ReleaseFast)\t%s\t%s\t%s\t%s\t%s\n' \
        "$tree_zig_loc" "$tree_zig_fns" "$tree_zig_ms" "$tree_zig_sz" "$tree_zig_note" >> "$DATA_MFOPT"

    tree_rust_fns=$((mf_rust_modules * mf_rust_funcs))
    tree_rust_loc=$(wc -l "$MF_TREE_DIR/rust/src"/*.rs | awk 'END{print $1}')
    tree_rust_ms=-1
    tree_rust_note="did not finish within ${MF_OPT_TIMEOUT}s"
    tree_rust_sz=0
    started=$(now_ms)
    if timeout -k 5s "$MF_OPT_TIMEOUT" cargo build --release --manifest-path "$MF_TREE_DIR/rust/Cargo.toml" > "$BENCH_ERRLOG" 2>&1; then
        tree_rust_ms=$(( $(now_ms) - started ))
        tree_rust_sz=$(bench_sz "$MF_TREE_DIR/rust/target/release/multifile_bench")
        tree_rust_note="ok"
    fi
    printf '  %-22s: %5d LOC (%4d fns) | Clean %s | Bin %d B\n' \
        "Rust (Cargo release)" "$tree_rust_loc" "$tree_rust_fns" \
        "$([ "$tree_rust_ms" -gt 0 ] && echo "${tree_rust_ms} ms" || echo "$tree_rust_note")" "$tree_rust_sz"
    printf 'Rust (Cargo release)\t%s\t%s\t%s\t%s\t%s\n' \
        "$tree_rust_loc" "$tree_rust_fns" "$tree_rust_ms" "$tree_rust_sz" "$tree_rust_note" >> "$DATA_MFOPT"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 3b. Scaling sweep: how each compiler's clean build, rebuild and memory grow with
#     project size. Runs only in the full-data modes (--update-doc, --record): the
#     gate above measures the one pinned size. Every point uses the equal program
#     shape, so the points are comparable with each other and with workload 3.
#     Points come from MF_SWEEP_POINTS (set near the top, "tag:modules:funcs:who"). Two points are
#     the default: 3k to 30k already shows the growth shape, and Zoril's whole-program analysis
#     makes the ~100k point the slowest thing in the benchmark (tens of minutes for its four builds
#     alone), so ask for it explicitly when you want that end of the curve.
# ──────────────────────────────────────────────────────────────────────────────
if [ "$UPDATE_DOC" -eq 1 ] || [ "$RECORD_BASELINE" -eq 1 ]; then
    printf "\n=== Workload 3b: Scaling with project size ===\n"
    SWEEP_DIR="$REPO_ROOT/build/bench/sweep"
    DATA_SWEEP="$TMP_DIR/sweep.tsv"
    : > "$DATA_SWEEP"

    sweep_loc() {
        find "$1" \( -name '*.zrl' -o -name '*.zig' -o -name '*.rs' -o -name '*.ha' \) -exec cat {} + | wc -l
    }
    # One row per language per point: tag modules funcs loc language clean_ms peak_kb touch_ms
    sweep_row() { # sweep_row TAG MODS FUNCS LANG LOC CLEAN_MS PEAK_KB TOUCH_MS
        [ "$6" = "-1" ] && return   # its build failed and was reported already
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$DATA_SWEEP"
        printf '  %-5s %-19s %6d LOC | clean %6d ms (RSS %5.1f MB)%s\n' \
            "$1" "$5" "$4" "$6" "$(awk "BEGIN {print $7/1024}")" \
            "$([ "$8" -gt 0 ] && printf ' | touch %d ms' "$8")"
    }

    for sweep_point in $MF_SWEEP_POINTS; do
        s_tag=${sweep_point%%:*}; s_rest=${sweep_point#*:}
        s_mods=${s_rest%%:*}; s_rest=${s_rest#*:}
        s_funcs=${s_rest%%:*}; s_who=${s_rest#*:}
        s_dir="$SWEEP_DIR/$s_tag"
        rm -rf "$s_dir"
        lua "$REPO_ROOT/bench/cross_lang/gen_multifile.lua" --out-dir "$s_dir" \
            --modules "$s_mods" --funcs "$s_funcs" >/dev/null

        # Zoril, through zbuild like workload 3 (cache cleared by the command itself)
        s_zdir="$s_dir/zoril"
        s_zloc=$(sweep_loc "$s_zdir")
        measure_compile "" time_and_rss_cmd sh -c "
            rm -rf '$s_zdir/.zoril-cache' '$TMP_DIR/sweep_zoril'
            '$REPO_ROOT/build/zbuild' -o '$TMP_DIR/sweep_zoril' -I 'stdlib=$REPO_ROOT/stdlib' -I '$s_zdir' \
                --cache-dir '$s_zdir/.zoril-cache' --compiler '$REPO_ROOT/build/zoril' \
                --zilc '$REPO_ROOT/build/zilc' --qbe '$BACKEND_BIN' '$s_zdir/main.zrl'"
        s_clean=$BENCH_ELAPSED_MS
        s_peak=$BENCH_PEAK_KB
        measure_compile "touch '$s_zdir/mod0.zrl'" time_and_rss_cmd sh -c "
            '$REPO_ROOT/build/zbuild' -o '$TMP_DIR/sweep_zoril' -I 'stdlib=$REPO_ROOT/stdlib' -I '$s_zdir' \
                --cache-dir '$s_zdir/.zoril-cache' --compiler '$REPO_ROOT/build/zoril' \
                --zilc '$REPO_ROOT/build/zilc' --qbe '$BACKEND_BIN' '$s_zdir/main.zrl'"
        sweep_row "$s_tag" "$s_mods" "$s_funcs" "$s_zloc" "Zoril" "$s_clean" "$s_peak" "$BENCH_ELAPSED_MS"

        if [ "$s_who" = "all" ]; then
            if command -v zig >/dev/null 2>&1; then
                s_d="$s_dir/zig"
                measure_compile "rm -rf '$s_d/.zig-cache' '$s_d/zig-out'" \
                    time_and_rss_cmd sh -c "cd '$s_d' && zig build -Doptimize=$MF_ZIG_MODE"
                sweep_row "$s_tag" "$s_mods" "$s_funcs" "$(sweep_loc "$s_d")" "Zig ($MF_ZIG_MODE)" \
                    "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" 0
            fi
            if command -v cargo >/dev/null 2>&1; then
                s_d="$s_dir/rust"
                measure_compile "cd '$s_d' && cargo clean >/dev/null 2>&1" \
                    time_and_rss_cmd cargo build $RUST_PROFILE_ARGS --manifest-path "$s_d/Cargo.toml"
                sweep_row "$s_tag" "$s_mods" "$s_funcs" "$(sweep_loc "$s_d/src")" "Rust (Cargo $MF_RUST_PROFILE)" \
                    "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" 0
            fi
            if command -v hare >/dev/null 2>&1; then
                s_d="$s_dir/hare"
                s_hcache="$TMP_DIR/sweepharecache_$s_tag"
                measure_compile "rm -rf '$s_hcache'" \
                    time_and_rss_cmd sh -c "cd '$s_d' && HARECACHE='$s_hcache' hare build -o '$TMP_DIR/sweep_hare' ."
                sweep_row "$s_tag" "$s_mods" "$s_funcs" "$(sweep_loc "$s_d")" "Hare" \
                    "$BENCH_ELAPSED_MS" "$BENCH_PEAK_KB" 0
            fi
        fi
    done
fi

# Cache this run's rows for the languages the gate does not read.
mkdir -p "$CMP_CACHE"
awk -F'\t' '$2 ~ /^(clang|zig|rust|hare)$/' "$DATA_FIB" > "$CMP_CACHE/fib.tsv"
awk -F'\t' '$2 ~ /^(clang|zig|rust|hare)$/' "$DATA_ARR" > "$CMP_CACHE/arr.tsv"
awk -F'\t' '$1 ~ /^(Zig|Rust|Hare)/' "$DATA_MF" > "$CMP_CACHE/mf.tsv"
if command -v clang >/dev/null 2>&1 && command -v zig >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1 && command -v hare >/dev/null 2>&1; then
    : > "$CMP_CACHE/complete"
fi
else
    replay_others mf "$DATA_MF"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Append to speed_history.tsv
# ──────────────────────────────────────────────────────────────────────────────
sample_finish_host_state
RUN_TS=$(date +%Y-%m-%d-%H-%M-%S)
# History records what this run measured: replayed (cached) rows are left out.
HIST_FIB="$TMP_DIR/hist_fib.tsv"; HIST_ARR="$TMP_DIR/hist_arr.tsv"; HIST_MF="$TMP_DIR/hist_mf.tsv"
if [ "$USE_CMP_CACHE" -eq 1 ]; then
    grep -vxF -f "$CMP_CACHE/fib.tsv" "$DATA_FIB" > "$HIST_FIB" || true
    grep -vxF -f "$CMP_CACHE/arr.tsv" "$DATA_ARR" > "$HIST_ARR" || true
    grep -vxF -f "$CMP_CACHE/mf.tsv" "$DATA_MF" > "$HIST_MF" || true
else
    cp "$DATA_FIB" "$HIST_FIB"; cp "$DATA_ARR" "$HIST_ARR"; cp "$DATA_MF" "$HIST_MF"
fi
if [ ! -f "$SPEED_HISTORY" ]; then
    printf 'date\tcommit\tzoril_version\tzig_version\trust_version\thare_version\tbinary\ttoolchain\tworkload\telapsed_ms\tpeak_rss_kb\tstatus\thost_os\tcpu_model\tcores\tram\tgovernor\tload_1m_start\tload_1m_end\n' > "$SPEED_HISTORY"
fi

while IFS="$(printf '\t')" read -r label tc c_ms c_rss r_ms bin_sz; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tfib(38)x3\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$RUN_TS" "$ZORIL_COMMIT" "$ZORIL_COMMIT" "$ZIG_VER" "$RUST_VER" "$HARE_VER" "$label" "$tc" "$r_ms" "$c_rss" "$RUN_STATUS" \
        "$HOST_OS" "$HOST_CPU" "$HOST_CORES" "$HOST_RAM" "$HOST_GOVERNOR" "$HOST_LOAD1M_START" "$HOST_LOAD1M_END" \
        >> "$SPEED_HISTORY"
done < "$HIST_FIB"

while IFS="$(printf '\t')" read -r label tc c_ms c_rss r_ms bin_sz; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tarray_loop_500k\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$RUN_TS" "$ZORIL_COMMIT" "$ZORIL_COMMIT" "$ZIG_VER" "$RUST_VER" "$HARE_VER" "$label" "$tc" "$r_ms" "$c_rss" "$RUN_STATUS" \
        "$HOST_OS" "$HOST_CPU" "$HOST_CORES" "$HOST_RAM" "$HOST_GOVERNOR" "$HOST_LOAD1M_START" "$HOST_LOAD1M_END" \
        >> "$SPEED_HISTORY"
done < "$HIST_ARR"

while IFS="$(printf '\t')" read -r label fns loc c_ms c_rss touch_ms edit_ms bin_sz sig_ms; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s_clean\tcomp\tmultifile_clean\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$RUN_TS" "$ZORIL_COMMIT" "$ZORIL_COMMIT" "$ZIG_VER" "$RUST_VER" "$HARE_VER" "$label" "$c_ms" "$c_rss" "$RUN_STATUS" \
        "$HOST_OS" "$HOST_CPU" "$HOST_CORES" "$HOST_RAM" "$HOST_GOVERNOR" "$HOST_LOAD1M_START" "$HOST_LOAD1M_END" \
        >> "$SPEED_HISTORY"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s_touch\tcomp\tmultifile_touch\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$RUN_TS" "$ZORIL_COMMIT" "$ZORIL_COMMIT" "$ZIG_VER" "$RUST_VER" "$HARE_VER" "$label" "$touch_ms" "$c_rss" "$RUN_STATUS" \
        "$HOST_OS" "$HOST_CPU" "$HOST_CORES" "$HOST_RAM" "$HOST_GOVERNOR" "$HOST_LOAD1M_START" "$HOST_LOAD1M_END" \
        >> "$SPEED_HISTORY"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s_edit\tcomp\tmultifile_edit\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$RUN_TS" "$ZORIL_COMMIT" "$ZORIL_COMMIT" "$ZIG_VER" "$RUST_VER" "$HARE_VER" "$label" "$edit_ms" "$c_rss" "$RUN_STATUS" \
        "$HOST_OS" "$HOST_CPU" "$HOST_CORES" "$HOST_RAM" "$HOST_GOVERNOR" "$HOST_LOAD1M_START" "$HOST_LOAD1M_END" \
        >> "$SPEED_HISTORY"
    if [ -n "$sig_ms" ] && [ "$sig_ms" -gt 0 ]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s_sig\tcomp\tmultifile_sig\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$RUN_TS" "$ZORIL_COMMIT" "$ZORIL_COMMIT" "$ZIG_VER" "$RUST_VER" "$HARE_VER" "$label" "$sig_ms" "$c_rss" "$RUN_STATUS" \
            "$HOST_OS" "$HOST_CPU" "$HOST_CORES" "$HOST_RAM" "$HOST_GOVERNOR" "$HOST_LOAD1M_START" "$HOST_LOAD1M_END" \
            >> "$SPEED_HISTORY"
    fi
done < "$HIST_MF"

# ──────────────────────────────────────────────────────────────────────────────
# Zoril-only metrics + threshold gating (regression gates for `make preflight`)
# ──────────────────────────────────────────────────────────────────────────────
# Drop rows whose step did not run: a failed comparison language leaves -1 in every timing
# field of its row (measure_compile's failure sentinel), and the tables and regenerated docs
# must not show a measurement that did not happen. Its failure is reported above.
for bench_data in "$DATA_FIB" "$DATA_ARR" "$DATA_MF" "$DATA_SWEEP"; do
    [ -f "$bench_data" ] || continue
    awk -F'\t' '{ for (i = 1; i <= NF; i++) if ($i == "-1") next; print }' \
        "$bench_data" > "$bench_data.filtered" && mv "$bench_data.filtered" "$bench_data"
done

# A measurement that did not happen must not read as a good ratio: `measure_runtime` reports -1
# for a binary that will not run, and a ratio of 0 would pass this lower_better gate silently.
if [ -n "$BENCH_SKIPPED" ]; then
    printf '\n[WARN] comparison rows skipped (their steps failed, see the [FAIL] lines above): %s\n' \
        "$(printf '%s\n' $BENCH_SKIPPED | sort -u | tr '\n' ' ')" >&2
    printf '       the cross-language tables below and the regenerated docs are missing them.\n' >&2
fi
if [ "$r_ms_zoril_fib" -le 0 ] || [ "$r_ms_gcc2_fib" -le 0 ]; then
    printf '\n[FAIL] the fib measurement is missing (Zoril %s ms, gcc -O2 %s ms), so\n' "$r_ms_zoril_fib" "$r_ms_gcc2_fib" >&2
    printf '       runtime_ratio_vs_gcc_o2 is not measurable in this run.\n' >&2
    exit 1
fi
z_runtime_ratio="${r_ms_pair_ratio:-$(awk "BEGIN { if ($r_ms_gcc2_fib > 0) printf \"%.3f\", ($r_ms_zoril_fib / $r_ms_gcc2_fib); else print 0 }")}"
z_rss_mb_per_kloc=$(awk "BEGIN { if ($loc_z > 0) printf \"%.3f\", (($rss_z_clean / 1024.0) / ($loc_z / 1000.0)); else print 0 }")

printf '%s\t%s\t%s\t%s\t%s\t%s\truntime_ratio_vs_gcc_o2\tzoril_vs_gcc\tfib(38)x3\t%s\t0\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$RUN_TS" "$ZORIL_COMMIT" "$ZORIL_COMMIT" "$ZIG_VER" "$RUST_VER" "$HARE_VER" "$z_runtime_ratio" "$RUN_STATUS" \
    "$HOST_OS" "$HOST_CPU" "$HOST_CORES" "$HOST_RAM" "$HOST_GOVERNOR" "$HOST_LOAD1M_START" "$HOST_LOAD1M_END" \
    >> "$SPEED_HISTORY"

if [ ! -d "$(dirname "$METRICS_FILE")" ]; then
    mkdir -p "$(dirname "$METRICS_FILE")"
fi
{
    printf 'clean_throughput_loc_s\t%d\n' "$tp_loc_z"
    printf 'incremental_rebuild_ms\t%d\n' "$c_ms_z_edit"
    printf 'runtime_ratio_vs_gcc_o2\t%s\n' "$z_runtime_ratio"
    printf 'peak_rss_mb_per_kloc\t%s\n' "$z_rss_mb_per_kloc"
} > "$METRICS_FILE"
printf '\nZoril metrics written to %s:\n' "$METRICS_FILE"
printf '  clean_throughput_loc_s = %d\n' "$tp_loc_z"
printf '  incremental_rebuild_ms  = %d\n' "$c_ms_z_edit"
printf '  runtime_ratio_vs_gcc_o2= %s\n' "$z_runtime_ratio"
printf '  peak_rss_mb_per_kloc   = %s\n' "$z_rss_mb_per_kloc"
if [ "$HOST_GOVERNOR" = "powersave" ]; then
    printf '  note: the CPU governor is powersave, so runtime timings depend on how far the clock\n'
    printf '        has ramped up; runtime_ratio_vs_gcc_o2 measures its two sides interleaved for that.\n'
fi

# --record: store the current measurement as the regression baseline.
if [ "$RECORD_BASELINE" -eq 1 ]; then
    if [ "$RUN_STATUS" = "contended" ] && [ "$FORCE_RUN" -eq 0 ]; then
        printf '\nERROR: Cannot record baseline on a contended host (status: %s). Re-run on a quiet host or pass --force.\n' "$RUN_STATUS" >&2
        exit 1
    fi
    {
        printf '# Stable cross-language baseline thresholds (best-of-N with warm-up discard on quiet host)\n'
        printf '# axis|baseline|tolerance_pct|direction\n'
        printf 'clean_throughput_loc_s|%d|15|higher_better\n' "$tp_loc_z"
        printf 'incremental_rebuild_ms|%d|15|lower_better\n' "$c_ms_z_edit"
        printf 'runtime_ratio_vs_gcc_o2|%s|15|lower_better\n' "$z_runtime_ratio"
    } > "$THRESHOLDS_FILE"
    printf '\nRecorded baseline thresholds to %s\n' "$THRESHOLDS_FILE"
fi

# --check-thresholds: fail if any axis regressed beyond tolerance vs the baseline.
# First run with no baseline auto-records and passes, so the gate is green on
# bootstrap rather than red because nobody committed a baseline yet.
if [ "$CHECK_THRESHOLDS" -eq 1 ]; then
    check_thresholds_gate
fi

# ──────────────────────────────────────────────────────────────────────────────
# Update comparison doc via Lua
# ──────────────────────────────────────────────────────────────────────────────
if [ "$UPDATE_DOC" -eq 1 ]; then
    if [ "$RUN_STATUS" = "contended" ] && [ "$FORCE_RUN" -eq 0 ]; then
        printf '\nERROR: Cannot update documentation from a contended host run (status: %s). Re-run on a quiet host or pass --force.\n' "$RUN_STATUS" >&2
        exit 1
    fi
    printf "\nUpdating %s with measured benchmark tables...\n" "$DOC_PATH"
    lua - "$DOC_PATH" "$DATA_FIB" "$DATA_ARR" "$DATA_MF" "$ASM_IDENTICAL" "$DATA_SWEEP" "${DATA_MFOPT:-}" << 'EOF'
local doc_path = arg[1]
local fib_path = arg[2]
local arr_path = arg[3]
local mf_path = arg[4]
local asm_identical = arg[5] or "0"
local sweep_path = arg[6] or ""
local mfopt_path = arg[7] or ""

local function read_tsv(path)
    local rows = {}
    local f = assert(io.open(path, "r"))
    for line in f:lines() do
        local parts = {}
        for part in line:gmatch("[^\t]+") do
            table.insert(parts, part)
        end
        if #parts > 0 then
            table.insert(rows, parts)
        end
    end
    f:close()
    return rows
end

local fib_rows = read_tsv(fib_path)
local arr_rows = read_tsv(arr_path)
local mf_rows = read_tsv(mf_path)
local sweep_rows = sweep_path ~= "" and read_tsv(sweep_path) or {}

local fib_map = {}
for _, r in ipairs(fib_rows) do fib_map[r[1]] = r[5] end

local arr_map = {}
for _, r in ipairs(arr_rows) do arr_map[r[1]] = r[5] end

local speed_table = {
    "| Benchmark | Zoril | gcc -O0 | gcc -O2 | clang -O2 | Zig (ReleaseFast) | Rust (-O) | Hare |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
    string.format("| `fib(38)` ×3, call-heavy | **%s ms** | %s ms | %s ms | %s ms | %s ms | %s ms | %s ms |",
        fib_map["Zoril"] or "0", fib_map["gcc -O0"] or "0", fib_map["gcc -O2"] or "0", fib_map["clang -O2"] or "0",
        fib_map["Zig (ReleaseFast)"] or "0", fib_map["Rust (-O)"] or "0", fib_map["Hare"] or "0"),
    string.format("| 4096-elem array loop ×500000 | **%s ms** | %s ms | %s ms | %s ms | %s ms | %s ms | %s ms |",
        arr_map["Zoril"] or "0", arr_map["gcc -O0"] or "0", arr_map["gcc -O2"] or "0", arr_map["clang -O2"] or "0",
        arr_map["Zig (ReleaseFast)"] or "0", arr_map["Rust (-O)"] or "0", arr_map["Hare"] or "0")
}
local speed_table_md = table.concat(speed_table, "\n")

local covers = {
    ["Zoril"] = "zbuild DAG, incremental caching, translation-unit lowering, QBE SSA, as, ld",
    ["Zig"] = "build.zig modules, semantic analysis, comptime, LLVM backend, lld",
    ["Rust"] = "Cargo incremental, borrow checking, trait resolution, monomorphization, LLVM codegen",
    ["Hare"] = "hare module cache, type checker, QBE emission, as, ld",
}

local mf_table = {
    "| Language & Toolchain | Functions | Codebase LOC | Clean Compile | Compile Throughput | Clean Peak RSS | Touch Rebuild | Edit Rebuild | Rebuild Speedup | Binary Size | What compile covers |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
}
for _, r in ipairs(mf_rows) do
    local lang = r[1]
    local fns = tonumber(r[2]) or 0
    local loc = tonumber(r[3]) or 0
    local c_ms = tonumber(r[4]) or 0
    local c_rss = (tonumber(r[5]) or 0) / 1024
    local touch_ms = tonumber(r[6]) or 0
    local edit_ms = tonumber(r[7]) or 0
    local sz = r[8]
    local what = covers[(lang:gsub(" %(.*$", ""))] or ""
    local loc_per_sec = 0
    local fns_per_sec = 0
    if c_ms > 0 then
        loc_per_sec = math.floor((loc * 1000) / c_ms)
        fns_per_sec = math.floor((fns * 1000) / c_ms)
    end
    local speedup = 0
    if c_ms > 0 then
        speedup = ((c_ms - edit_ms) / c_ms) * 100
    end
    table.insert(mf_table, string.format("| **%s** | %d fns | %d LOC | %d ms | **%d LOC/s** (%d fns/s) | %.1f MB | %d ms | %d ms | **%.1f%%** | %s B | %s |",
        lang, fns, loc, c_ms, loc_per_sec, fns_per_sec, c_rss, touch_ms, edit_ms, speedup, sz, what))
end
local mf_table_md = table.concat(mf_table, "\n")

local f_doc = assert(io.open(doc_path, "r"))
local content = f_doc:read("*a")
f_doc:close()

-- Replace Executable speed table
local speed_pat = "(### Executable speed.-)(\n| Benchmark | Zoril |.-)(\n\nZoril lands between)"
local new_content = content:gsub(speed_pat, function(c1, c2, c3) return c1 .. "\n" .. speed_table_md .. c3 end, 1)
if new_content == content then
    local speed_pat2 = "(\n| Benchmark | Zoril |.-)(\n\nZoril lands between)"
    new_content = content:gsub(speed_pat2, function(c1, c2) return "\n" .. speed_table_md .. c2 end, 1)
end

local z_loc, z_ms, z_rss, z_touch, z_edit, z_speedup = 0, 0, 0, 0, 0, 0
local h_loc, h_ms, h_rss, h_touch, h_edit = 0, 0, 0, 0, 0
local zig_touch, zig_edit = 0, 0
local rust_touch, rust_edit = 0, 0
for _, r in ipairs(mf_rows) do
    local lang = r[1]
    local loc = tonumber(r[3]) or 0
    local c_ms = tonumber(r[4]) or 0
    local c_rss = (tonumber(r[5]) or 0) / 1024
    local touch_ms = tonumber(r[6]) or 0
    local edit_ms = tonumber(r[7]) or 0
    local sp = 0
    if c_ms > 0 then sp = ((c_ms - edit_ms) / c_ms) * 100 end
    if lang == "Zoril" then
        z_loc, z_ms, z_rss, z_touch, z_edit, z_speedup = loc, c_ms, c_rss, touch_ms, edit_ms, sp
    elseif lang == "Hare" then
        h_loc, h_ms, h_rss, h_touch, h_edit = loc, c_ms, c_rss, touch_ms, edit_ms
    elseif lang:find("Zig") then
        zig_touch, zig_edit = touch_ms, edit_ms
    elseif lang:find("Rust") then
        rust_touch, rust_edit = touch_ms, edit_ms
    end
end
local z_tp = z_ms > 0 and math.floor((z_loc * 1000) / z_ms) or 0
local h_tp = h_ms > 0 and math.floor((h_loc * 1000) / h_ms) or 0
local tp_ratio = z_tp > 0 and string.format("%.1f", h_tp / z_tp) or "0"
-- Memory per thousand lines, stated for both rather than as an "N x leaner" ratio, which assumed
-- the direction and printed 0x once the measurement counted the compilers a driver starts.
local z_mb_per_kloc = z_loc > 0 and (z_rss / (z_loc / 1000)) or 0
local h_mb_per_kloc = h_loc > 0 and (h_rss / (h_loc / 1000)) or 0

-- Scaling sweep table: tag modules funcs loc language clean_ms peak_kb touch_ms
local sweep_md = ""
if #sweep_rows > 0 then
    local points, by_point = {}, {}
    for _, r in ipairs(sweep_rows) do
        local tag = r[1]
        if not by_point[tag] then
            by_point[tag] = { mods = tonumber(r[2]) or 0, funcs = tonumber(r[3]) or 0,
                              langs = {}, order = {} }
            table.insert(points, tag)
        end
        -- Keep the row order (the bench writes Zoril first, then each comparison language) and take
        -- the language labels from the rows: a label names the build mode that was measured, so
        -- hard-coding them here would publish a mode this run may not have used.
        if not by_point[tag].langs[r[5]] then table.insert(by_point[tag].order, r[5]) end
        by_point[tag].langs[r[5]] = {
            loc = tonumber(r[4]) or 0,
            c_ms = tonumber(r[6]) or 0,
            rss = (tonumber(r[7]) or 0) / 1024,
            touch = tonumber(r[8]) or 0,
        }
    end
    sweep_md = "\n#### How the numbers scale with the project\n\n"
        .. "Each point is the same program shape for every language, so the rows are comparable with each "
        .. "other and with the table above. `LOC/s` is clean-build throughput; `touch` is Zoril's incremental "
        .. "no-op rebuild through `tools/zbuild`, the axis that shows what whole-program analysis costs as a "
        .. "project grows.\n\n"
        .. "| Point | Shape | LOC | Language | Clean | LOC/s | Peak RSS | Touch |\n"
        .. "| --- | --- | --- | --- | --- | --- | --- | --- |\n"
    for _, tag in ipairs(points) do
        local p = by_point[tag]
        for _, lang in ipairs(p.order) do
            local d = p.langs[lang]
            local tps = d.c_ms > 0 and math.floor((d.loc * 1000) / d.c_ms) or 0
            local touch = d.touch > 0 and (d.touch .. " ms") or "-"
            sweep_md = sweep_md .. string.format(
                "| `%s` | %d mods x %d funcs | %d | %s | %d ms | %d | %.1f MB | %s |\n",
                tag, p.mods, p.funcs, d.loc, lang, d.c_ms, tps, d.rss, touch)
        end
    end
    -- What the largest measured point shows, from the rows: which languages have a row there (a
    -- point can be Zoril-only, and the points are configurable) and which of those take minutes.
    -- The fixed sentence this replaces claimed the other three take minutes per build at the large
    -- point, which the numbers beside it contradicted (Rust 5.5 s, Hare 1.7 s, Zig 260 s at 30k).
    local last = by_point[points[#points]]
    local slow, quick = {}, {}
    for _, lang in ipairs(last.order) do
        local d = last.langs[lang]
        if d.c_ms >= 60000 then
            table.insert(slow, string.format("%s (%.0f s)", lang, d.c_ms / 1000))
        else
            table.insert(quick, string.format("%s (%.1f s)", lang, d.c_ms / 1000))
        end
    end
    local z_first, z_last = by_point[points[1]].langs["Zoril"], last.langs["Zoril"]
    local sentence = string.format("\nAt the largest point measured (`%s`, %d LOC), ",
        points[#points], z_last and z_last.loc or 0)
    if #slow > 0 then
        sentence = sentence .. table.concat(slow, ", ") .. " spend minutes in a clean build"
        if #quick > 0 then
            sentence = sentence .. ", while " .. table.concat(quick, ", ") .. " stay under a minute"
        end
        sentence = sentence .. "."
    else
        sentence = sentence .. "all " .. #quick .. " languages build in " .. table.concat(quick, ", ") .. "."
    end
    if #last.order < 4 then
        sentence = sentence .. " Not every language has a row there."
    end
    if z_first and z_last and z_first.c_ms > 0 and z_last.c_ms > 0 then
        sentence = sentence .. string.format(
            " Zoril's own clean time grows %.1fx from `%s` to `%s` while its line count grows %.1fx and peak memory %.1fx, which is the whole-program trade-off `doc/vision/why_zoril.md` describes.",
            z_last.c_ms / z_first.c_ms, points[1], points[#points],
            (z_first.loc > 0 and z_last.loc / z_first.loc or 0),
            (z_first.rss > 0 and z_last.rss / z_first.rss or 0))
    end
    sweep_md = sweep_md .. sentence .. "\n"
end

-- Optimized builds on the realistic shape (workload 3c): label loc fns clean_ms bin status.
-- A negative clean_ms means the build did not finish inside the bench's cap; the status column says
-- so, and the table prints that instead of a time rather than dropping the row.
local mfopt_md = ""
local mfopt_rows = read_tsv(mfopt_path)
if #mfopt_rows > 0 then
    mfopt_md = "\n#### Optimized builds on a realistic shape\n\n"
        .. "The same generated project as the table above, but compiled as a call tree (each module's driver calls its own functions, and `main` calls the drivers) with the optimizing mode: Zig ReleaseFast and Rust `--release`. This is where an optimizer has the work a real program gives it, and it is the comparison the unoptimized table cannot make. Zoril and Hare have no optimization level to raise, so their rows above are already their build of this shape.\n\n"
        .. "| Language | LOC | Functions | Clean | LOC/s | Binary |\n"
        .. "| --- | --- | --- | --- | --- | --- |\n"
    for _, r in ipairs(mfopt_rows) do
        local label = r[1]
        local loc = tonumber(r[2]) or 0
        local fns = tonumber(r[3]) or 0
        local ms = tonumber(r[4]) or -1
        local bin = tonumber(r[5]) or 0
        local status = r[6] or ""
        local clean = ms > 0 and (ms .. " ms") or status
        local tps = ms > 0 and math.floor((loc * 1000) / ms) or "-"
        local bins = bin > 0 and (bin .. " B") or "-"
        mfopt_md = mfopt_md .. string.format("| %s | %d | %d | %s | %s | %s |\n",
            label, loc, fns, clean, tps, bins)
    end
    mfopt_md = mfopt_md
        .. "\nZig's whole-module LLVM pass over 3,000 generated functions does not finish inside the five minutes this pass allows it, on the call tree any more than on the straight-line shape, so its cell says so instead of reporting a time. Rust's release profile aborts inside LLVM on the straight-line shape - \"cycle encountered after 4 frames with period 6\", cargo exit 101, rustc 1.99.0 (2026-09-28), reproduced by `bench/cross_lang/rustc_llvm_abort_repro.sh` - and finishes in seconds on this one, which is why the two tables measure different shapes rather than one shape at two modes.\n"
end

local mf_section = "\n### Multi-file project & incremental rebuild (Four Axes)\n\n"
    .. "To evaluate compiler throughput at scale, every language compiles the same generated multi-module computation: the module and function counts in the table's first columns are identical, and LOC differs by at most ~1.3x because a generated function is 9-12 lines depending on the language. Earlier revisions scaled each language to a ~10s clean build instead, which benchmarked Zoril on a project 4-26x smaller than the others; the size is equal now and stated beside every number. This displays the throughput hierarchy "
    .. "(LOC/sec) directly, and provides a clear baseline to test incremental touch-rebuild and content-edit rebuild behavior.\n\n"
    .. "The generated program reads a run-time value, so no optimizer can fold the whole computation away - the constant-seeded version let them, which turned the comparison into a measurement of each constant folder. Every row is measured in its unoptimized baseline mode (Zig Debug, Rust dev, Zoril and Hare through QBE, which has no optimizer) and names that mode in the row: comparing languages at different optimization levels compares different work. The optimizing modes are measured in the table below instead, on a realistic call tree, because on this straight-line shape they are not usable at all. The `fib` and `array_loop` tables above keep Zig ReleaseFast, whose cost is not a factor on programs that small.\n\n"
    .. "The touch and edit columns are not an equal measurement across languages: each is that toolchain's own incremental support, driven the same way (touch one module and rebuild; change one function body and rebuild), and only Zoril's goes through a tool this project owns, `tools/zbuild`. Zig's column is its build cache, Rust's is cargo's incremental profile, Hare's is its module cache - what a user of that language would get, not a like-for-like rebuild mechanism.\n\n"
    .. mf_table_md .. "\n\n"
    .. "_Peak RSS is the largest single process anywhere in the build - a compiler the build driver started, not only the driver - read exactly with `getrusage` ([`bench/cross_lang/children_maxrss.c`](../../bench/cross_lang/children_maxrss.c)). It is not the sum of processes that ran at the same time, so a parallel build can use more memory in total._\n\n"
    .. mfopt_md .. "\n"
    .. "> **The Key Takeaways:**\n"
    .. string.format("> 1. **Compiler Throughput Hierarchy:** Hare compiles at **%d LOC/s** — **%s× faster per line** than Zoril (%d LOC/s). Hare is Zoril's direct architectural peer (small, self-hosted, QBE backend). In memory, the largest process in Hare's build used **%.1f MB** for %dk LOC (%.1f MB per thousand lines) and in Zoril's **%.1f MB** for %.1fk LOC (%.1f MB per thousand lines).\n",
        h_tp, tp_ratio, z_tp, h_rss, math.floor(h_loc / 1000), h_mb_per_kloc, z_rss, z_loc / 1000, z_mb_per_kloc)
    .. string.format("> 2. **Incremental Rebuild:** With `tools/zbuild` modular compilation and incremental caching, Zoril achieves a **%.1f%% speedup** on body-edit rebuilds (%d ms vs %d ms clean), and near-instant touch no-ops (%d ms). In contrast, compilers with separate compilation and caching drop from clean ~10s down to sub-second rebuilds (Zig %d ms touch / %d ms edit, Hare %d ms touch / %d ms edit, Rust %d ms touch / %d ms edit).\n",
        z_speedup, z_edit, z_ms, z_touch, zig_touch, zig_edit, h_touch, h_edit, rust_touch, rust_edit)
    .. "> 3. **Process Startup vs Execution Time:** In microbenchmarks, runtimes under ~5 ms are dominated by OS process spawn/exit. Workloads 1 & 2 above provide execution-heavy measurements running in hundreds of milliseconds to seconds.\n"
    .. sweep_md

-- Replace Bounds checking sentence dynamically from measured Zoril vs Zoril (raw ptr)
local z_chk = tonumber(arr_map["Zoril"]) or 0
local z_ptr = tonumber(arr_map["Zoril (raw ptr)"]) or 0
local bounds_repl
if asm_identical == "1" then
    bounds_repl = string.format(
        "**Bounds checking is not what costs this.** The same array loop written with raw pointers (`bench/cross_lang/array_loop/array_loop_ptr.zrl`), which skips bounds checking entirely, compiles to **byte-identical machine code** (`cmp -s` confirms `array_loop.s` and `array_loop_ptr.s` are byte-identical). Any timing variation between them (%d ms checked vs %d ms raw pointer) is pure run-to-run system noise on identical binaries. Zoril's inductive condition analysis (`src/index_facts.zrl`) elides the bounds check because the loop guard `while i < 4096` dominates the array access, leaving literally **zero instructions** of checking overhead in the binary. Safety is not the bottleneck; QBE's codegen is.",
        z_chk, z_ptr)
else
    bounds_repl = string.format(
        "**Bounds checking is not what costs this.** The same array loop written with raw pointers (`bench/cross_lang/array_loop/array_loop_ptr.zrl`), which skips bounds checking entirely, ran in %d ms against the checked version's %d ms. Safety is not the bottleneck; QBE's optimizer is.",
        z_ptr, z_chk)
end

local bounds_pat = "%*%*Bounds checking is not what costs this%.%*%* [^\n]+"
new_content = new_content:gsub(bounds_pat, function() return bounds_repl end, 1)

-- Replace the whole multi-file section (heading included: mf_section re-emits it) up to the
-- next "## " heading. This used to name the *following* heading in its pattern, so once that
-- section was renamed the gsub matched nothing and the update silently did nothing at all.
local mf_replaced = false
new_content = new_content:gsub("### Multi%-file project & incremental rebuild[^\n]*\n.-(\n## )",
    function(nxt) mf_replaced = true; return mf_section .. nxt end, 1)
if not mf_replaced then
    new_content = new_content:gsub("(\n## [^\n]*\n)", function(h) return mf_section .. h end, 1)
end

local f_out = assert(io.open(doc_path, "w"))
f_out:write(new_content)
f_out:close()
print("Updated doc/language/language_comparison.md successfully.")
EOF
fi

if [ "$UPDATE_DOC" -eq 1 ] || [ "$RECORD_BASELINE" -eq 1 ]; then
    # Record this run's duration so the next publishing run can quote a measured estimate.
    elapsed_ms=$(( $(now_ms) - RUN_START_MS ))
    mkdir -p "$(dirname "$LAST_PUBLISH_FILE")"
    awk -v ms="$elapsed_ms" 'BEGIN { printf "%.0f\n", ms / 1000 }' > "$LAST_PUBLISH_FILE"
    printf 'Publishing run finished in %.1f min (recorded for the next run'"'"'s estimate).\n' \
        "$(awk -v ms="$elapsed_ms" 'BEGIN { printf "%.1f", ms / 60000 }')"
fi
