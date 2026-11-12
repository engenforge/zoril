# scripts/lib/test_runner.sh — shared test-runner library. Source it; do not execute it.
#
# Provides:
#   tr_parse_flag "$1" "$2"   common flags; returns how many args it consumed (0, 1 or 2)
#   run_timed CMD...          run with the per-step timeout
#   is_timeout_exit CODE      true for timeout/kill exit codes
#   tr_now_ms                 milliseconds since the epoch
#   tr_report STATUS NAME DETAIL MS [OUTPUT_FILE]   one result line
#   tr_expectations FILE      sets T_KIND (run|compile_success|compile_fail|warning|skip),
#                             T_EXIT, T_EXPECT (diagnostic substrings, one per line), T_SKIP, T_LINK,
#                             T_FLAGS
#   tr_run_file FILE          compile, link and run one test per its header
#   tr_run_scenario NAME CMD...  run a multi-step test script as one result line
#   tr_discover PATH...       list the per-file tests under PATH
#
# Common flags (all runners): --verbose, --quiet, --filter PATTERN, --fail-fast,
# --timeout SECS, --results FILE (appends "STATUS<TAB>path" per test), --jobs N.

# Portability helpers
if [ -f "$(dirname "$0")/portability.sh" ]; then
    . "$(dirname "$0")/portability.sh"
elif [ -f "$(dirname "$0")/lib/portability.sh" ]; then
    . "$(dirname "$0")/lib/portability.sh"
fi

TR_VERBOSE=${TR_VERBOSE:-0}
TR_QUIET=${TR_QUIET:-0}
TR_FILTER=${TR_FILTER:-}
TR_FAIL_FAST=${TR_FAIL_FAST:-0}
TR_TIMEOUT=${TR_TIMEOUT:-${TIMEOUT_SECS:-30}}
TR_KILL=${KILL_DUR:-2s}
TR_RESULTS=${TR_RESULTS:-}
TR_JOBS=${TR_JOBS:-$(nproc_count 2>/dev/null || echo 1)}

TR_RUN=0
TR_PASSED=0
TR_FAILED=0
TR_SKIPPED=0
TR_START_MS=0

# Toolchain (the public pipeline: zoril -> zilc -> qbe -> as -> ld).
ZORIL_CC=${ZORIL_CC:-./build/zoril}
ZILC_BIN=${ZILC_BIN:-./build/zilc}
ZORIL_STDLIB=${ZORIL_STDLIB:-stdlib}
TR_BACKEND=${BACKEND_BIN:-qbe}
TR_ASSEMBLER=${ASSEMBLER_BIN:-as}
TR_LINKER=${LINKER_BIN:-ld}
TR_WORK=${TR_WORK:-build/tests}
TR_RUNTIME=${TR_RUNTIME:-build/runtime.o}

# Include roots shared by every per-file test.
TR_INCLUDES="-I stdlib=$ZORIL_STDLIB -I src -I tools/zilc/src -I tests -I tests/include -I tests/helpers"

tr_parse_flag() {
    case "$1" in
        --verbose|-v)  TR_VERBOSE=1; TR_QUIET=0; return 1 ;;
        --quiet|-q)    TR_QUIET=1; TR_VERBOSE=0; return 1 ;;
        --fail-fast)   TR_FAIL_FAST=1; return 1 ;;
        --filter)      TR_FILTER="$2"; return 2 ;;
        --timeout)     TR_TIMEOUT="$2"; return 2 ;;
        --results)     TR_RESULTS="$2"; return 2 ;;
        --jobs|-j)     TR_JOBS="$2"; return 2 ;;
    esac
    return 0
}

SIGXCPU_EXIT=152
# Run without --foreground so timeout sends signals to the whole process group
# on expiration, preventing orphaned grandchildren. Track the running timeout
# process so INT/TERM signals immediately clean up the child group on abort.
_TR_TIMED_PID=
_tr_sig_handler() {
    trap - INT TERM
    [ -n "$_TR_TIMED_PID" ] && kill -TERM "$_TR_TIMED_PID" 2>/dev/null
    kill 0 2>/dev/null
    exit 130
}
trap '_tr_sig_handler' INT TERM

run_timed() {
    run_with_timeout -k "$TR_KILL" "$TR_TIMEOUT" "$@" &
    _TR_TIMED_PID=$!
    wait "$_TR_TIMED_PID" 2>/dev/null
    _tr_rc=$?
    _TR_TIMED_PID=
    return $_tr_rc
}
is_timeout_exit() { [ "$1" -eq 124 ] || [ "$1" -eq 137 ] || [ "$1" -eq 143 ] || [ "$1" -eq "$SIGXCPU_EXIT" ]; }

# tr_clock — set TR_NOW to milliseconds since the epoch. bash's EPOCHREALTIME avoids a
# fork per reading; other shells fall back to date(1).
tr_clock() {
    case "${EPOCHREALTIME:-}" in
        *[.,]*)
            _us=${EPOCHREALTIME#*[.,]}
            TR_NOW=$(( ${EPOCHREALTIME%[.,]*} * 1000 + 1${_us%???} - 1000 )) ;;
        *)
            TR_NOW=$(now_ms) ;;
    esac
}
tr_now_ms() { tr_clock; echo "$TR_NOW"; }

# tr_detail — indent stdin as detail lines. Result tags inside them ("[FAIL]" in a log
# being shown) become "FAIL:", so every "[FAIL]" in the output is one failed item.
tr_detail() { sed -E 's/\[(PASS|FAIL|SKIP)\]/\1:/g; s/^/       /'; }

# tr_report STATUS NAME DETAIL MS [OUTPUT_FILE]
tr_report() {
    _st="$1"; _name="$2"; _detail="$3"; _ms="$4"; _out="$5"
    case "$_st" in
        PASS) TR_PASSED=$((TR_PASSED + 1)) ;;
        FAIL) TR_FAILED=$((TR_FAILED + 1)) ;;
        SKIP) TR_SKIPPED=$((TR_SKIPPED + 1)) ;;
    esac
    [ -n "$TR_RESULTS" ] && printf '%s\t%s\n' "$_st" "$_name" >> "$TR_RESULTS"
    if [ "$_st" != FAIL ] && [ "$TR_QUIET" -eq 1 ]; then return 0; fi
    _line="[$_st] $_name"
    [ -n "$_detail" ] && _line="$_line ($_detail)"
    [ -n "$_ms" ] && _line="$_line (${_ms}ms)"
    echo "$_line"
    if [ -n "$_out" ] && [ -s "$_out" ]; then
        if [ "$TR_VERBOSE" -eq 1 ]; then
            tr_detail < "$_out"
        elif [ "$_st" = FAIL ]; then
            grep -v '^PROGRESS:\|^Lowering function\|^Verifying function\|^Parsing file' "$_out" | head -n 5 | tr_detail
        fi
    fi
    # The expectation that failed, as a diff (set by tr_run_file).
    if [ "$_st" = FAIL ] && [ -n "$TR_EXPECTED" ]; then
        printf '       --- expected\n       +++ actual\n       -%s\n' "$TR_EXPECTED"
        printf '%s\n' "${TR_ACTUAL:-(nothing)}" | sed 's/^/       +/'
    fi
    TR_EXPECTED=""; TR_ACTUAL=""
}

# tr_expectations FILE — read the test's header conventions.
tr_expectations() {
    # One awk pass instead of a grep pipeline per header: process spawns, not the
    # toolchain, dominate the cost of a test.
    eval "$(awk '
        function q(v) { gsub(/\047/, "\047\\\047\047", v); return "\047" v "\047" }
        skip == "" && /^[ \t]*\/\/[ \t]*@skip:/ { v = $0; sub(/^[ \t]*\/\/[ \t]*@skip:[ \t]*/, "", v); skip = v }
        /^\/\/ EXPECT: / { v = $0; sub(/^\/\/ EXPECT: /, "", v); expect = expect (expect == "" ? "" : "\n") v }
        flags == "" && /^\/\/ flags: / { v = $0; sub(/^\/\/ flags: /, "", v); flags = v }
        /^\/\/ link: / { v = $0; sub(/^\/\/ link: /, "", v); link = link v " " }
        /expected compile fail/ { cfail = 1 }
        /expected compile success/ { csucc = 1 }
        ex == "" && match($0, /expected exit( code:)? [0-9]+/) { v = substr($0, RSTART, RLENGTH); sub(/.* /, "", v); ex = v }
        END {
            printf "T_SKIP=%s T_EXPECT=%s T_FLAGS=%s T_LINK=%s ", q(skip), q(expect), q(flags), q(link)
            printf "_cfail=%d _csucc=%d T_EXIT=%d\n", cfail, csucc, ex + 0
        }' "$1" 2>/dev/null)"
    if [ -n "$T_SKIP" ]; then T_KIND=skip
    elif [ "$_cfail" -eq 1 ]; then T_KIND=compile_fail
    elif [ -n "$T_EXPECT" ]; then
        # A diagnostic that is not an error: the file must compile and report it.
        T_KIND=warning
    elif [ "$_csucc" -eq 1 ]; then T_KIND=compile_success
    else T_KIND=run; fi
}

# _tr_step NAME CMD... — run one pipeline step, appending its output to $_log.
# Sets _why to a failure reason on failure.
_tr_step() {
    _stepname="$1"; shift
    [ "$TR_VERBOSE" -eq 1 ] && echo "\$ $*" >> "$_log"
    run_timed "$@" >> "$_log" 2>&1
    _rc=$?
    [ $_rc -eq 130 ] && exit 130
    [ $_rc -eq 0 ] && return 0
    if is_timeout_exit $_rc; then _why="TIMEOUT: $_stepname"
    elif [ $_rc -gt 128 ]; then _why="ICE: $_stepname crashed"
    else _why="$_stepname failed"; fi
    return 1
}

# _tr_done STATUS DETAIL [EXPECTED ACTUAL] — report the current test. Verbose mode adds
# the paths of the intermediate files to its output.
_tr_done() {
    TR_EXPECTED="$3"; TR_ACTUAL="$4"
    if [ "$TR_VERBOSE" -eq 1 ]; then
        for _a in test.zil test.ssa test.s test; do
            [ -f "$_dir/$_a" ] && echo "artifact: $_dir/$_a" >> "$_log"
        done
    fi
    tr_clock
    tr_report "$1" "$_file" "$2" "$(( TR_NOW - _t0 ))" "$_log"
}

# _tr_missing_expect — the first EXPECT line (T_EXPECT holds one per line) that the current
# log does not contain; fails when every one is there.
_tr_missing_expect() {
    printf '%s\n' "$T_EXPECT" | while IFS= read -r _want; do
        grep -Fq -- "$_want" "$_log" || { printf '%s\n' "$_want"; exit 0; }
    done | grep .
}

# _tr_diagnostics — the compiler's error and warning lines from the current log.
_tr_diagnostics() { grep -E 'error|warning' "$_log" | head -n 3; }

# tr_run_file FILE — run one test; reports exactly one result line.
tr_run_file() {
    _file="$1"
    tr_expectations "$_file"
    if [ "$T_KIND" = skip ]; then
        tr_report SKIP "$_file" "$T_SKIP" ""
        return 0
    fi
    TR_RUN=$((TR_RUN + 1))

    tr_clock; _t0=$TR_NOW
    _dir=$TR_WORK/$(printf '%s' "$_file" | tr / +)
    mkdir -p "$_dir"
    _log="$_dir/output.log"
    : > "$_log"
    _why=""
    _bin="$_dir/test"

    case "$_file" in
        *.zil) cp "$_file" "$_dir/test.zil"; _compiled=0 ;;
        *)
            [ "$TR_VERBOSE" -eq 1 ] && echo "\$ $ZORIL_CC $TR_INCLUDES -I $(dirname "$_file") --emit-zil -o $_dir/test.zil $T_FLAGS $_file" >> "$_log"
            run_timed "$ZORIL_CC" $TR_INCLUDES -I "$(dirname "$_file")" --emit-zil -o "$_dir/test.zil" $T_FLAGS "$_file" >> "$_log" 2>&1
            _compiled=$?
            [ $_compiled -eq 130 ] && exit 130
            ;;
    esac

    if [ "$T_KIND" = compile_fail ]; then
        if [ $_compiled -eq 0 ]; then
            _tr_done FAIL "expected compile fail, but it compiled" "compile fails${T_EXPECT:+: $T_EXPECT}" "compiled"
        elif is_timeout_exit $_compiled; then
            _tr_done FAIL "TIMEOUT: compiler"
        elif [ $_compiled -gt 128 ]; then
            _tr_done FAIL "ICE: compiler crashed"
        elif [ -n "$T_EXPECT" ] && _missing=$(_tr_missing_expect); then
            _tr_done FAIL "diagnostic mismatch" "$_missing" "$(_tr_diagnostics)"
        else
            _tr_done PASS ""
        fi
        return 0
    fi

    if [ "$T_KIND" = warning ] && [ $_compiled -eq 0 ]; then
        if _missing=$(_tr_missing_expect); then
            _tr_done FAIL "diagnostic missing" "$_missing" "$(_tr_diagnostics)"
        else
            _tr_done PASS ""
        fi
        return 0
    fi

    if [ $_compiled -ne 0 ]; then
        if is_timeout_exit $_compiled; then _why="TIMEOUT: compiler"
        elif [ $_compiled -gt 128 ]; then _why="ICE: compiler crashed"
        else _why="compile failed"; fi
    fi
    [ -z "$_why" ] && _tr_step zilc "$ZILC_BIN" "$_dir/test.zil" "$_dir/test.ssa"
    [ -z "$_why" ] && _tr_step backend "$TR_BACKEND" -o "$_dir/test.s" "$_dir/test.ssa"
    [ -z "$_why" ] && _tr_step assembler "$TR_ASSEMBLER" -o "$_dir/test.o" "$_dir/test.s"
    if [ -z "$_why" ] && [ "$T_KIND" = compile_success ]; then
        _tr_done PASS ""
        return 0
    fi
    _extra=""
    if [ -z "$_why" ] && [ -n "$T_LINK" ]; then
        _i=0
        for _src in $T_LINK; do
            _i=$((_i + 1))
            _tr_step assembler "$TR_ASSEMBLER" -o "$_dir/link$_i.o" "$_src" || break
            _extra="$_extra $_dir/link$_i.o"
        done
    fi
    [ -z "$_why" ] && _tr_step linker "$TR_LINKER" -o "$_bin" "$TR_RUNTIME" "$_dir/test.o" $_extra

    if [ -n "$_why" ]; then
        case "$_why" in
            "compile failed") _tr_done FAIL "$_why" "compiles" "$(_tr_diagnostics)" ;;
            *)                _tr_done FAIL "$_why" ;;
        esac
        return 0
    fi

    # The program's stdout and stderr follow this line in the log.
    [ "$TR_VERBOSE" -eq 1 ] && echo "\$ $_bin" >> "$_log"
    run_timed "$_bin" < /dev/null >> "$_log" 2>&1
    _rc=$?
    [ $_rc -eq 130 ] && exit 130
    [ "$TR_VERBOSE" -eq 1 ] && echo "exit code: $_rc" >> "$_log"
    if [ $_rc -eq "$T_EXIT" ]; then
        _tr_done PASS ""
    elif is_timeout_exit $_rc; then
        _tr_done FAIL "TIMEOUT: run"
    else
        _tr_done FAIL "wrong exit code" "exit $T_EXIT" "exit $_rc"
    fi
}

# Directories under a test root that hold helpers, scenario inputs or the runner's own
# fixtures (tests/runner/fixtures/, which fail on purpose), never tests.
TR_PRUNE='-name include -o -name test_include -o -name helpers -o -name lib -o -name incremental -o -name modular -o -name fixtures -o -name fmt'

# tr_discover PATH... — print test files: .zrl anywhere, .zil only under corpus/.
tr_discover() {
    for _p in "$@"; do
        if [ -f "$_p" ]; then echo "$_p"; continue; fi
        [ -d "$_p" ] || continue
        # A *_lib.zrl file is a module another test imports, and a *dot*file is tool scratch:
        # scripts/unsafe_scan.sh compiles a mutated copy of a test in the test's own directory as
        # `.unsafe_scan_<pid>.zrl` (it needs the directory for the test's relative imports), and a
        # run that discovered that copy would report it as a failing test - which is what the
        # mutation harness's self-test caught on 2026-10-12 when the two gates ran side by side.
        eval "find \"\$_p\" \\( $TR_PRUNE \\) -prune -o -type f -name '*.zrl' ! -name '*_lib.zrl' ! -name '.*' -print" 2>/dev/null
        case "$_p" in corpus*) find "$_p" -type f -name '*.zil' 2>/dev/null ;; esac
    done | sed 's|^\./||' | sort -u
}

# tr_run_logged KIND NAME LOG CMD... — run a command as one result line ("[PASS] KIND:
# NAME"). Its output goes to LOG; a failure shows the log's last lines (all of it with
# --verbose). Exit 77 (TR_EXIT_SKIP, the automake convention) reports it as skipped, with
# the reason from its last "[SKIP] ..." line: an exit 0 would count a check that did not run
# as passed.
TR_EXIT_SKIP=77
tr_run_logged() {
    _kind="$1"; _name="$2"; _log="$3"; shift 3
    TR_RUN=$((TR_RUN + 1))
    _t0=$(tr_now_ms)
    mkdir -p "$(dirname "$_log")"
    "$@" > "$_log" 2>&1
    _rc=$?
    [ $_rc -eq 130 ] && exit 130
    _ms=$(( $(tr_now_ms) - _t0 ))
    if [ $_rc -eq 0 ]; then
        tr_report PASS "$_kind: $_name" "" "$_ms" "$_log"
        return 0
    fi
    if [ $_rc -eq $TR_EXIT_SKIP ]; then
        TR_RUN=$((TR_RUN - 1))
        _why=$(sed -n 's/^.*\[SKIP\] *//p' "$_log" | tail -n 1)
        tr_report SKIP "$_kind: $_name" "${_why:-exit $TR_EXIT_SKIP, no reason given; log: $_log}" "$_ms"
        return 0
    fi
    tr_report FAIL "$_kind: $_name" "exit $_rc; log: $_log" "$_ms"
    if [ "$TR_VERBOSE" -eq 1 ]; then tr_detail < "$_log"; else tail -n 15 "$_log" | tr_detail; fi
    return 1
}

# tr_run_scenario NAME CMD... — a multi-step test script as one result line; its log is
# $TR_WORK/scenarios/NAME.log.
tr_run_scenario() {
    _sname="$1"; shift
    tr_run_logged scenario "$_sname" "$TR_WORK/scenarios/$_sname.log" "$@"
    return 0
}
