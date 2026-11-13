#!/bin/sh
# scripts/test.sh — the Zoril test runner.
#
# Usage:
#   scripts/test.sh [options]                  every group
#   scripts/test.sh [options] --gates          every gate, then every group (make test)
#   scripts/test.sh [options] --gate NAME ...  only the named gates (repeatable)
#   scripts/test.sh [options] --group G ...    only the named groups (repeatable)
#   scripts/test.sh [options] --scenario NAME ... only the named scenarios (repeatable)
#   scripts/test.sh [options] --suite S        suite: all, group, corpus, incremental, chain, or tests/<dir>
#   scripts/test.sh [options] PATH...          only these test files or directories
#   scripts/test.sh [options] --smoke          the smoke suite, tests/smoke.list (make test-fast)
#   scripts/test.sh --group-of PATH            print the group whose paths hold PATH (exit 1: none)
#   scripts/test.sh [options] --print-plan     print the options and items a run would use, for another runner
#   scripts/test.sh --item KIND NAME PREFIX    run one item of that plan, for another runner
#
# Groups: language, types, memory, stdlib, diagnostics, integration (--list-groups).
# Gates: the repository checks make test runs first (--list-gates).
#
# Output (grep for '^\[FAIL\]' and '^Total:'):
#   [PASS] name / [FAIL] name (reason) / [SKIP] name (reason)   one test, probe or check
#          indented lines                                        details of the line above
#   Gates / Tests                                                section headings
#     <suite>   N run   P passed   F failed   S skipped          one line per gate or group
#   Total: N run, P passed, F failed, S skipped (Xs)             the last line
# --quiet lists only [FAIL] items, the default lists every item, --verbose adds details.
# "run" counts the items that ran (passed + failed); skipped items did not run. A skip is
# something left to act on (a known bug, a documented gap), never "out of scope": what a
# suite is not meant to cover is left out of it, not reported as skipped.
# The last item is always "stray-files": it fails, naming them, when the run left a file in a
# tracked directory (anything outside build/, untracked and not ignored). The paths are recorded
# before the first item, so untracked work in progress that was already there does not count
# (scripts/check_stray_files.sh).
#
# Options:
#   --verbose, -v   also print every command, the full output and exit code of every
#                   test, the paths of its intermediate files, and every gate's log
#   --quiet, -q     list only failing items (the default under make)
#   --filter P      only tests whose path matches the extended regex P
#   --suite S       select a suite: all, a group name or alias, corpus, incremental,
#                   chain, or a tests/ subdirectory
#   --fail-fast     stop at the first failure
#   --timeout S     per-step timeout in seconds (default 30)
#   --results F     append "STATUS<TAB>name" for each test to F
#   --jobs N, -j N  run N items at a time (default: the number of CPUs)
#
# Per-file test headers (anywhere in the file):
#   // expected exit N | // expected exit code: N   run and require exit N (default 0)
#   // expected compile fail                          the compiler must reject it
#   // EXPECT: <text>                                 its diagnostics contain <text> (each line); without
#                                                     "expected compile fail", a warning:
#                                                     it must compile and is not run
#   // expected compile success                       compile and assemble only
#   // flags: <compiler flags>                        extra flags for the compiler
#   // link: <file.s>                                 assemble and link an extra object
#   // @skip: <reason>                                report as skipped, do not run
#
# Not tests: *_lib.zrl (imported modules) and include/, helpers/, lib/, incremental/,
# modular/ and zilc/ (inputs of scenario scripts), fixtures/ (the runner's own output test).
#
# Concurrency: one run per work directory. A run holds an exclusive lock on $TR_WORK/.lock
# (default build/tests) and exits non-zero at once if another run holds it, instead of racing
# over the shared $ITEMS directory and FIFO it recreates. Run two at once by giving each its
# own TR_WORK.

ulimit -s 65536 2>/dev/null
# Tests that crash on purpose (a null dereference, a forged pointer) must not write core dumps:
# a core_pattern that pipes to a handler makes each one slow enough to hit the test timeout.
ulimit -c 0 2>/dev/null
trap 'trap - INT TERM; kill 0 2>/dev/null; exit 130' INT TERM
case "$0" in */*) cd "${0%/*}/.." ;; *) cd .. ;; esac || exit 2

# Tests never sign commits or run user-configured Git hooks, and must not depend on user Git config.
GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_GLOBAL
GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_SYSTEM
GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_NOSYSTEM
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
for _v in $(env 2>/dev/null | sed -n 's/^\(GIT_CONFIG_[KEY|VALUE].*\)=.*/\1/p'); do
    unset "$_v"
done

. scripts/lib/test_runner.sh
. scripts/lib/layout.sh

GROUPS_ALL="language types memory stdlib diagnostics integration"

group_title() {
    case "$1" in
        language)    echo "Language & Syntax" ;;
        types)       echo "Types & Generics" ;;
        memory)      echo "Ownership & Memory Safety" ;;
        stdlib)      echo "Stdlib" ;;
        diagnostics) echo "Diagnostics" ;;
        integration) echo "Integration" ;;
        git)         echo "Git & Contributor Tools" ;;
    esac
}

# The plan - the gates, each group's per-file test roots and the scenarios - is the rows of
# scripts/test_plan.tsv, which documents its own format. A row that does not fit stops the runner
# with exit 2, so a typo cannot silently drop an item from a run.
PLAN_FILE=scripts/test_plan.tsv

plan_check() {
    [ -f "$PLAN_FILE" ] || { echo "test.sh: $PLAN_FILE not found" >&2; return 1; }
    awk -F'\t' -v f="$PLAN_FILE" -v groups="$GROUPS_ALL git" '
        function bad(msg) { printf "test.sh: %s:%d: %s\n", f, NR, msg > "/dev/stderr"; err = 1 }
        BEGIN { n = split(groups, a, " "); for (i = 1; i <= n; i++) known[a[i]] = 1 }
        /^[ \t]*(#|$)/ { next }
        {
            if (NF != 4) { bad("expected 4 tab-separated columns (kind, name, group, command), found " NF); next }
            if ($4 == "") { bad("empty command"); next }
            if ($1 == "gate" || $1 == "extra-gate") {
                if ($3 != "-") bad("a " $1 " row has \"-\" as its group, found \"" $3 "\"")
                if ($2 in gate) bad("duplicate gate \"" $2 "\" (first at line " gate[$2] ")")
                gate[$2] = NR
            } else if ($1 == "paths") {
                if ($2 != "-") bad("a paths row has \"-\" as its name, found \"" $2 "\"")
                if (!($3 in known)) bad("unknown group \"" $3 "\"")
            } else if ($1 == "scenario") {
                if ($2 == "-" || $2 == "") bad("a scenario row needs a name")
                if (!($3 in known)) bad("unknown group \"" $3 "\"")
                if ($2 in scen) bad("duplicate scenario \"" $2 "\" (first at line " scen[$2] ")")
                scen[$2] = NR
            } else bad("unknown kind \"" $1 "\" (gate, extra-gate, paths or scenario)")
        }
        END { exit err }' "$PLAN_FILE"
}
plan_check || exit 2

# group_paths G — the per-file test roots of group G. Every test belongs to exactly one.
group_paths() {
    awk -F'\t' -v g="$1" '$1 == "paths" && $3 == g { print $4 }' "$PLAN_FILE"
}

# The export-checks scenario is scripts/test_export_checks.sh: the guards it runs are
# private-only (scripts/export_public_release.sh does not ship them), so an exported tree lacks
# them by design; the wrapper reports the skip and passes, never fails.

# group_scenarios G — the multi-step scripts of group G, listed after its per-file tests.
group_scenarios() {
    awk -F'\t' -v g="$1" '$1 == "scenario" && $3 == g { print $2 }' "$PLAN_FILE"
}

scenario_group() {
    for _g in $GROUPS_ALL git; do
        for _s in $(group_scenarios "$_g"); do
            if [ "$_s" = "$1" ]; then
                echo "$_g"
                return 0
            fi
        done
    done
    return 1
}

scenario_run() {
    _sc_cmd=$(awk -F'\t' -v n="$1" '$1 == "scenario" && $2 == n { print $4; exit }' "$PLAN_FILE")
    # The command is a program and its arguments, split on blanks: no row quotes anything.
    [ -n "$_sc_cmd" ] && tr_run_scenario "$1" $_sc_cmd
}

# Legacy TSUITE names that select a group.
group_alias() {
    case "$1" in
        error|errors) echo diagnostics ;;
        *) echo "$1" ;;
    esac
}

# Gates: repository checks that are not per-file tests. Each prints one canonical item
# line per thing it checks ([PASS]/[FAIL]/[SKIP] at the start of the line); anything else
# it prints is detail and stays in build/gates/<name>.log.
# The rows of scripts/test_plan.tsv are in display order: results print in plan order, so one slow
# gate holds back every line after it, and the slowest gate is the last row.
GATES_ALL=$(awk -F'\t' '$1 == "gate" { printf "%s%s", sep, $2; sep = " " }' "$PLAN_FILE")

gate_command() {
    case "$1" in
        # Misbehaving gates for the runner's own output test (scripts/test_runner_output.sh).
        fixture-*)
            _fx="tests/runner/fixtures/gates/$(echo "${1#fixture-}" | tr - _).sh"
            [ -x "$_fx" ] && echo "$_fx" ;;
        *) awk -F'\t' -v n="$1" '($1 == "gate" || $1 == "extra-gate") && $2 == n { print $4; exit }' "$PLAN_FILE" ;;
    esac
}

# gate_run NAME — run a gate and report its items as "[STATUS] NAME: item". Sets the TR_*
# counters. A gate fails if it reports a [FAIL], prints a result line in any other format,
# exits non-zero without reporting why, or reports nothing.
gate_run() {
    _gname="$1"
    _glog="build/gates/$_gname.log"
    mkdir -p build/gates
    eval "QUIET=0 $(gate_command "$_gname")" > "$_glog" 2>&1
    _grc=$?
    [ $_grc -eq 130 ] && exit 130
    eval "$(awk -v g="$_gname" -v quiet="$TR_QUIET" -v out="$_glog.items" '
        BEGIN { printf "" > out }
        /^\[(PASS|FAIL|SKIP)\] ./ {
            st = substr($0, 2, 4); n[st]++
            if (st == "FAIL" || quiet != 1) print "[" st "] " g ": " substr($0, 8) >> out
            next
        }
        # Result lines in any other shape: "[ PASS ]", "[OK]", "[WEAK]", an unknown tag.
        /^\[/ || /^[ \t]*\[ (PASS|FAIL|SKIP) \]/ || /^[ \t]*\[(OK|WEAK)\]/ {
            bad++; print "[FAIL] " g ": result line not in the [PASS]/[FAIL]/[SKIP] format: " $0 >> out
        }
        END { printf "_gp=%d _gf=%d _gs=%d _gbad=%d\n", n["PASS"], n["FAIL"], n["SKIP"], bad }
    ' "$_glog")"
    cat "$_glog.items"; rm -f "$_glog.items"
    _gf=$((_gf + _gbad))
    if [ $_grc -ne 0 ] && [ $_gf -eq 0 ]; then
        echo "[FAIL] $_gname: exited $_grc without reporting a failing item"; _gf=1
    fi
    if [ $((_gp + _gf + _gs)) -eq 0 ]; then
        echo "[FAIL] $_gname: reported no results"; _gf=1
    fi
    [ $_gf -gt 0 ] && echo "       log: $_glog"
    [ "$TR_VERBOSE" -eq 1 ] && tr_detail < "$_glog"
    TR_PASSED=$_gp; TR_FAILED=$_gf; TR_SKIPPED=$_gs; TR_RUN=$((_gp + _gf))
}

# ------------------------------------------------------------------ worker
# run_item KIND NAME PREFIX — run one item: its report goes to PREFIX.out, its timing to
# PREFIX.time, and its counts are left in TR_RUN, TR_PASSED, TR_FAILED and TR_SKIPPED.
run_item() {
    TR_RESULTS=""
    _item_start_s=$(date +%s)
    tr_clock; _item_start_ms=$TR_NOW
    case "$1" in
        file)     tr_run_file "$2" > "$3.out" 2>&1 ;;
        scenario) scenario_run "$2" > "$3.out" 2>&1 ;;
        gate)     gate_run "$2" > "$3.out" 2>&1 ;;
    esac
    tr_clock; _item_ms=$(( TR_NOW - _item_start_ms ))
    case "$1" in
        gate)
            _dur_s=$(( $(date +%s) - _item_start_s ))
            printf '%d\t%d\n' "$_dur_s" "$_item_ms" > "$3.time"
            ;;
        *)
            _dur_sec=$(printf '%d.%03d' $(( _item_ms / 1000 )) $(( _item_ms % 1000 )))
            printf '%s\t%d\n' "$_dur_sec" "$_item_ms" > "$3.time"
            ;;
    esac
}

# scripts/test.sh --worker INDEX KIND NAME: run one item for the pool below. Its report
# goes to $ITEMS/INDEX.out, its counts to $ITEMS/INDEX.st, then INDEX to the FIFO.
if [ "$1" = "--worker" ]; then
    idx="$2"; kind="$3"; name="$4"
    # A worker must not outlive its dispatcher. SIGKILL cannot be trapped, so the dispatcher's
    # liveness is checked here - before the item, and again before reporting. The second check is
    # the load-bearing one: the FIFO write below, whose only reader was the dispatcher, is what
    # parked every worker of a killed run forever (kernel wchan `wait_for_partner`). Together the
    # two bound a killed run's pool to one item's time, so nothing is left holding the lock.
    dispatcher_alive() { [ -z "${TR_PARENT:-}" ] || kill -0 "$TR_PARENT" 2>/dev/null; }
    dispatcher_alive || exit 0
    # write_status LINE — record this item's counts for the dispatcher. TR_TEST_ST_DELAY is a hook for
    # scripts/test_result_file.sh and nothing else sets it: "IDX:SECONDS" holds the worker of item IDX
    # for SECONDS between opening the status file and writing it, which is the window a reader can
    # catch the file empty in. Unset, it costs nothing. The line goes to N.st.tmp and is renamed: the
    # dispatcher takes N.st to mean "the result is in", and a rename within one directory is atomic, so
    # it sees no file or the whole file, never the empty one a plain `> N.st` leaves until it is written.
    write_status() {
        {
            case "${TR_TEST_ST_DELAY:-}" in "$idx":*) sleep "${TR_TEST_ST_DELAY#*:}" ;; esac
            printf '%s\n' "$1"
        } > "$ITEMS/$idx.st.tmp" && mv -f "$ITEMS/$idx.st.tmp" "$ITEMS/$idx.st"
    }
    if [ -e "$ITEMS/stop" ]; then
        write_status STOPPED
    else
        run_item "$kind" "$name" "$ITEMS/$idx"
        # Every item reports the same four counts: run passed failed skipped.
        write_status "$TR_RUN $TR_PASSED $TR_FAILED $TR_SKIPPED"
        [ "$TR_FAILED" -gt 0 ] && [ "$TR_FAIL_FAST" -eq 1 ] && : > "$ITEMS/stop"
    fi
    dispatcher_alive || exit 0
    echo "$idx" > "$ITEMS/done.fifo"
    exit 0
fi

# scripts/test.sh --item KIND NAME PREFIX: run one item as a worker does, for another runner. It
# writes PREFIX.out, PREFIX.time and PREFIX.st (the four counts) and takes its settings from the
# environment, never from options.
if [ "$1" = "--item" ]; then
    [ "$#" -eq 4 ] || { echo "test.sh: --item takes KIND NAME PREFIX" >&2; exit 2; }
    run_item "$2" "$3" "$4"
    printf '%s\n' "$TR_RUN $TR_PASSED $TR_FAILED $TR_SKIPPED" > "$4.st.tmp" && mv -f "$4.st.tmp" "$4.st"
    exit 0
fi

# ------------------------------------------------------------------ pool
# scripts/test.sh --pool: the worker pool, which the dispatcher runs under `setsid` so that the
# pool and everything it starts (xargs, the workers, their test processes) are one process group
# that a single signal ends. It opens the FIFO read-write before dispatching, so this process is a
# reader for as long as the pool lives: neither a worker's report nor the `end` marker below can
# then block on a FIFO whose reader died with the dispatcher. It records its own pid, which is also
# its process group (it is a session leader), for the dispatcher to signal.
if [ "$1" = "--pool" ]; then
    exec 3<> "$ITEMS/done.fifo" || exit 2
    printf '%s\n' "$$" > "$ITEMS/pool.pid"
    # Dispatch order is free - the dispatcher prints in plan order - so the non-file items are
    # handed out from the tail of the plan backwards, and the file tests follow in plan order. The
    # plan is ordered cheapest-first (GATES_ALL puts the expensive gates last, for the display), so
    # this starts them at once instead of a slot later, and the slowest items overlap each other
    # rather than the end of the run. xargs keeps the queue in this order.
    awk '$2 != "file" { nf = NR " " $2 " " $3 "\n" nf }
         $2 == "file" { rest = rest NR " " $2 " " $3 "\n" }
         END { printf "%s%s", nf, rest }' "$PLAN" | xargs -n 3 -P "$TR_JOBS" "$PWD/scripts/test.sh" --worker
    echo end >&3
    exit 0
fi

groups=""
gates=""
paths=""
scenarios=""
label="Selected tests"
suite_incremental=0
print_plan=0
while [ "$#" -gt 0 ]; do
    tr_parse_flag "$1" "$2"; n=$?
    if [ $n -gt 0 ]; then shift $n; continue; fi
    case "$1" in
        --suite)
            _s="$2"
            shift 2
            case "$_s" in
                all)
                    gates="$GATES_ALL"
                    ;;
                corpus)
                    paths="$paths corpus"
                    ;;
                incremental)
                    suite_incremental=1
                    ;;
                chain)
                    echo "=== Testing zoril-zbs (zhex-bootstrap Stage 1 compiler) ==="
                    export ZORIL_CC="./build/zoril-zbs"
                    groups="$GROUPS_ALL"
                    ;;
                *)
                    _g=$(group_alias "$_s")
                    if [ -n "$(group_title "$_g")" ]; then
                        groups="$groups $_g"
                    elif [ -d "tests/$_s" ]; then
                        paths="$paths tests/$_s"
                    elif [ -d "$_s" ] && case "$_s" in tests/*) true ;; *) false ;; esac; then
                        paths="$paths $_s"
                    else
                        echo "test.sh: unknown suite or directory 'tests/$_s'" >&2
                        exit 2
                    fi
                    ;;
            esac
            ;;
        --group)
            g=$(group_alias "$2")
            [ -n "$(group_title "$g")" ] || { echo "test.sh: unknown group '$2' ($GROUPS_ALL)" >&2; exit 2; }
            groups="$groups $g"; shift 2 ;;
        --scenario)
            [ -n "${2:-}" ] || { echo "test.sh: --scenario requires an argument" >&2; exit 2; }
            _sc="$2"
            _sc_grp=$(scenario_group "$_sc")
            [ -n "$_sc_grp" ] || { echo "test.sh: unknown scenario '$_sc'" >&2; exit 2; }
            scenarios="$scenarios $_sc"; shift 2 ;;
        --gates) gates="$GATES_ALL"; shift ;;
        --print-plan) print_plan=1; shift ;;
        --gate)
            [ -n "$(gate_command "$2")" ] || { echo "test.sh: unknown gate '$2'" >&2; exit 2; }
            gates="$gates $2"; shift 2 ;;
        --list-gates) for g in $GATES_ALL; do echo "$g"; done; exit 0 ;;
        --smoke)
            smoke=$(sed 's/#.*//' tests/smoke.list)
            for f in $smoke; do
                [ -e "$f" ] || { echo "tests/smoke.list: $f does not exist" >&2; exit 2; }
            done
            paths="$paths $(echo $smoke)"; label="Smoke"; shift ;;
        --list-groups)
            for g in $GROUPS_ALL; do printf '%-12s %s\n' "$g" "$(group_title "$g")"; done
            exit 0 ;;
        --group-of)
            [ -n "${2:-}" ] || { echo "test.sh: --group-of requires a path" >&2; exit 2; }
            _q="${2#./}"
            for g in $GROUPS_ALL; do
                for _e in $(group_paths "$g"); do
                    case "$_q" in "$_e"|"$_e"/*) echo "$g"; exit 0 ;; esac
                    # A glob entry (tests/functional/*.zrl) lists only files that exist; a
                    # deleted or new file beside them is in the same group.
                    if [ -f "$_e" ] && [ "${_q%/*}" = "${_e%/*}" ]; then
                        case "$_q" in *.zrl) echo "$g"; exit 0 ;; esac
                    fi
                done
            done
            exit 1 ;;
        -h|--help) sed -n '2,/^[^#]/ { /^[^#]/d; s/^# \{0,1\}//; p; }' "$0"; exit 0 ;;
        -*) echo "test.sh: unknown option $1" >&2; exit 2 ;;
        *) paths="$paths $1"; shift ;;
    esac
done

if [ "$suite_incremental" -eq 1 ]; then
    if [ "$TR_QUIET" -eq 1 ]; then
        exec ./scripts/test_incremental.sh --quiet
    else
        exec ./scripts/test_incremental.sh
    fi
fi

mkdir -p "$TR_WORK"

# One run per work directory. $ITEMS and its FIFO are recreated at the start of every run, so a
# second concurrent run deletes the FIFO the first one is reading and that one then blocks
# forever ("the worker left no result"). Take an exclusive non-blocking lock and refuse to
# start instead of racing. The --worker children exit above and never reach this; they inherit
# the open descriptor, so the lock is held while any part of the run is alive. Two runs can
# still run side by side by giving each its own TR_WORK (scripts/test_runner_output.sh does).
# Check dependencies for test suite (build toolchain, flock, mkfifo, xargs). Required tools
# only: a "Skipping optional test items:" line for a missing optional tool is outside the output grammar above, and
# the gates report their own [SKIP] items. `make test` prints that notice before running this.
_deps_profiles="test"
case "$gates" in
    *stage0c-*) _deps_profiles="test seed" ;;
esac
./scripts/check_deps.sh --required-only $_deps_profiles || exit $?

if [ "$print_plan" -eq 0 ]; then
exec 9>> "$TR_WORK/.lock" || { echo "test.sh: cannot open $TR_WORK/.lock" >&2; exit 2; }
if ! command -v flock >/dev/null 2>&1; then
    echo "test.sh: flock is required but not found in PATH" >&2
    exit 2
fi
if ! flock -n 9; then
    holder=$(cat "$TR_WORK/.lock" 2>/dev/null)
    # A killed run whose dispatcher became a zombie (in a container whose PID 1 does not reap)
    # answers `kill -0` but holds no descriptor, so it must read as gone too - otherwise every run
    # after it is told a live run is using the tree.
    holder_state=$(ps -o stat= -p "$holder" 2>/dev/null | tr -d ' ')
    case "$holder_state" in Z*) holder_dead=1 ;; *) holder_dead=0 ;; esac
    if [ -n "$holder" ] && { ! kill -0 "$holder" 2>/dev/null || [ "$holder_dead" -eq 1 ]; }; then
        # The holder is gone but its descriptor is not: a pool or worker from a killed run still
        # has the lock open (a SIGKILL leaves no trap to run, which the worker's own liveness check
        # now covers). Say so, because the pid alone sends the reader looking for a live process.
        echo "another test run is using $TR_WORK (pid $holder, which no longer exists: a killed run's pool or workers still hold it; end them, or set TR_WORK to a different directory to run separately)" >&2
    elif [ -n "$holder" ]; then
        echo "another test run is using $TR_WORK (pid $holder); wait for it, or set TR_WORK to a different directory to run separately" >&2
    else
        echo "another test run is using $TR_WORK; wait for it, or set TR_WORK to a different directory to run separately" >&2
    fi
    exit 2
fi
printf '%s\n' "$$" > "$TR_WORK/.lock"

# Every item must keep its output under build/. Record the untracked paths now, and compare them
# after the last item starts (see the stray-files item at the end of this script): a file written
# into a tracked directory is a defect whether or not a .gitignore pattern hides it, and the next
# `git add -A` would commit it. Comparing against this snapshot keeps a developer's own untracked
# work in progress from failing the run, and ignored paths (build/) never enter the comparison.
stray_start="$TR_WORK/stray.start"
./scripts/check_stray_files.sh --record "$stray_start" 2>/dev/null || stray_start=""
fi

if [ ! -f "$TR_RUNTIME" ]; then
    case "$TR_RUNTIME" in */*) mkdir -p "${TR_RUNTIME%/*}" ;; esac
    "$TR_ASSEMBLER" -o "$TR_RUNTIME" rt/runtime.s || { echo "could not assemble rt/runtime.s" >&2; exit 2; }
fi

filtered() {
    if [ -n "$TR_FILTER" ]; then printf '%s\n' "$1" | grep -E -- "$TR_FILTER"; else printf '%s\n' "$1"; fi
}

# ------------------------------------------------------------------ plan
# One line per item, "SUITE KIND NAME", in the order results are printed. A suite is a
# group, a gate, or "-" for the tests named on the command line.
PLAN=$(mktemp)
claimed=$(mktemp)
ITEMS="$TR_WORK/items"
TIMINGS_FILE="${TR_TIMINGS:-$TR_WORK/timings.tsv}"
unset TR_TIMINGS
if [ "$print_plan" -eq 0 ]; then
    rm -rf "$ITEMS" && mkdir -p "$ITEMS"
    mkdir -p "$(dirname "$TIMINGS_FILE")"
    : > "$TIMINGS_FILE"
fi
cleanup() { rm -f "$PLAN" "$claimed"; }
trap 'cleanup; _tr_sig_handler' INT TERM
trap cleanup EXIT

for g in $gates; do echo "gate:$g gate $g" >> "$PLAN"; done

full_run=0
if [ -z "$paths" ] && [ -z "$groups" ] && [ -z "$scenarios" ]; then
    if [ -z "$gates" ] || [ "$gates" = "$GATES_ALL" ]; then
        groups="$GROUPS_ALL"
        [ -z "$TR_FILTER" ] && full_run=1
    fi
fi

if [ -n "$groups" ]; then
    for g in $groups; do
        all=$(tr_discover $(group_paths "$g"))
        printf '%s\n' "$all" >> "$claimed"
        filtered "$all" | sed "/^\$/d; s/^/$g file /" >> "$PLAN"
        # Scenarios have no single test path, so --filter leaves them out.
        if [ -z "$TR_FILTER" ]; then
            for sc in $(group_scenarios "$g"); do echo "$g scenario $sc" >> "$PLAN"; done
        fi
    done
fi

if [ -n "$paths" ]; then
    _disc=$(filtered "$(tr_discover $paths)")
    if [ -z "$_disc" ]; then
        echo "no tests found in$paths${TR_FILTER:+ matching '$TR_FILTER'}" >&2
        exit 1
    fi
    printf '%s\n' "$_disc" | while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        if ! grep -q " file $_p\$" "$PLAN" 2>/dev/null; then
            echo "- file $_p" >> "$PLAN"
        fi
    done
fi

if [ -n "$scenarios" ] && [ -z "$TR_FILTER" ]; then
    for sc in $scenarios; do
        _sc_grp=$(scenario_group "$sc")
        if ! grep -q " scenario $sc\$" "$PLAN" 2>/dev/null; then
            echo "$_sc_grp scenario $sc" >> "$PLAN"
        fi
    done
fi

if [ ! -s "$PLAN" ]; then
    if [ -n "$paths" ]; then
        echo "no tests found in$paths${TR_FILTER:+ matching '$TR_FILTER'}" >&2
    else
        echo "no tests matched${TR_FILTER:+ '$TR_FILTER'}" >&2
    fi
    exit 1
fi

# TR_EXCLUDE: space-separated test paths or scenario names this run leaves out, counted nowhere.
# scripts/test_checked.sh uses it for the items that assert the *unmarked* build's own behaviour
# (the arena tests that expect a reset to hand the same space out again) and for the gates, whose
# thresholds are calibrated on the unmarked code. It is applied to the plan, so an excluded item is
# neither run nor reported.
if [ -n "${TR_EXCLUDE:-}" ]; then
    keep=$(mktemp)
    while IFS= read -r _line; do
        _drop=0
        for _x in $TR_EXCLUDE; do
            case "$_line" in
                *" $_x"|*" $_x "*|*"=$_x") _drop=1 ;;
            esac
        done
        [ "$_drop" -eq 0 ] && printf '%s\n' "$_line" >> "$keep"
    done < "$PLAN"
    mv "$keep" "$PLAN"
fi

suite_title() {
    case "$1" in
        gate:*) echo "${1#gate:}" ;;
        -)      echo "$label" ;;
        *)      _title=$(group_title "$1"); echo "${_title:-$1}" ;;
    esac
}

# claim_lines — the [FAIL] lines for a test in two groups or in none, one per line.
claim_lines() {
    dups=$(grep -v '^$' "$claimed" | sort | uniq -d)
    lost=$(tr_discover tests corpus | grep -vxF -f "$claimed")
    for f in $dups; do echo "[FAIL] $f (in more than one group)"; done
    for f in $lost; do echo "[FAIL] $f (in no group; add it to a paths row of scripts/test_plan.tsv)"; done
}

# --print-plan: what a run with these options would do, as tab-separated rows. The claim rows are
# computed before the run, so a test file the run itself writes under tests/ is not among them.
if [ "$print_plan" -eq 1 ]; then
    printf 'plan\t1\n'
    printf 'option\tquiet\t%s\n' "$TR_QUIET"
    printf 'option\tverbose\t%s\n' "$TR_VERBOSE"
    printf 'option\tfail_fast\t%s\n' "$TR_FAIL_FAST"
    printf 'option\ttimeout\t%s\n' "$TR_TIMEOUT"
    printf 'option\tresults\t%s\n' "$TR_RESULTS"
    printf 'option\ttimings\t%s\n' "$TIMINGS_FILE"
    printf 'option\twork\t%s\n' "$TR_WORK"
    printf 'option\tfull_run\t%s\n' "$full_run"
    while read -r _s _k _n; do
        printf 'item\t%s\t%s\t%s\t%s\n' "$_s" "$_k" "$_n" "$(suite_title "$_s")"
    done < "$PLAN"
    if [ "$full_run" -eq 1 ]; then
        claim_lines | while IFS= read -r _l; do printf 'claim\t%s\n' "$_l"; done
    fi
    exit 0
fi

# ------------------------------------------------------------------ run
# Workers finish in any order; results print in plan order as soon as every earlier
# item is done, so output never interleaves and is the same at any --jobs.
export TR_VERBOSE TR_QUIET TR_FAIL_FAST TR_TIMEOUT TR_KILL TR_WORK TR_JOBS ITEMS PLAN
# The workers check this pid: a worker whose dispatcher is gone (SIGKILL cannot be trapped) stops
# instead of running another item and reporting into a FIFO nobody reads.
export TR_PARENT="$$"
export ZORIL_CC ZILC_BIN ZORIL_STDLIB TR_RUNTIME
export BACKEND_BIN="$TR_BACKEND" ASSEMBLER_BIN="$TR_ASSEMBLER" LINKER_BIN="$TR_LINKER"
mkfifo "$ITEMS/done.fifo"
ALL_START=$(tr_now_ms)
# Gates and scenarios are the longest items, so the pool dispatches them first.
# "end" follows the last worker, so an item whose worker died without a status cannot
# leave the loop below waiting forever.
if command -v setsid >/dev/null 2>&1; then
    setsid "$PWD/scripts/test.sh" --pool &
    _tr_has_setsid=1
else
    "$PWD/scripts/test.sh" --pool &
    _tr_has_setsid=0
fi
pool=$!
# Read-write, so the FIFO never reports end-of-file between two workers' writes.
exec 3<> "$ITEMS/done.fifo"

# End the pool by process group: under setsid it is a session leader, so one TERM reaches the
# workers and their test processes too, and nothing is left holding the lock. The signal path and
# the exit path both call this, so a Ctrl-C, a normal return and an error in the reporting loop all
# tear the pool down; the workers' own liveness check covers a SIGKILL, which no trap can see.
kill_pool() {
    _pool_pid=$(cat "$ITEMS/pool.pid" 2>/dev/null)
    if [ -n "$_pool_pid" ] && kill -0 "$_pool_pid" 2>/dev/null; then
        # Without setsid the pool shares this group, so signal just the pool process.
        if [ "${_tr_has_setsid:-0}" -eq 1 ]; then
            kill -15 "-$_pool_pid" 2>/dev/null || kill -TERM "$_pool_pid" 2>/dev/null
        else
            kill -TERM "$_pool_pid" 2>/dev/null
        fi
    fi
    rm -f "$ITEMS/pool.pid"
    return 0
}
# Is the pool still there? Its pid file holds the pid it recorded, which is also its group.
pool_alive() {
    kill -0 "$pool" 2>/dev/null && return 0
    _pa=$(cat "$ITEMS/pool.pid" 2>/dev/null)
    [ -n "$_pa" ] && kill -0 "$_pa" 2>/dev/null
}
# Probe for `read -t`, which bounds the wait for a pool message (this repo's /bin/sh is bash). A
# shell without it keeps the blocking read, which is correct for as long as the pool lives.
_probe_err=$( { read -r -t 1 _tr_probe </dev/null; } 2>&1 )
case "$_probe_err" in
    *llegal*|*nsupported*|*nvalid*) _tr_read_timeout=0 ;;
    *) _tr_read_timeout=1 ;;
esac
trap 'kill_pool; exit 130' INT TERM
trap 'kill_pool; cleanup' EXIT

tot_run=0; tot_passed=0; tot_failed=0; tot_skipped=0
s_run=0; s_passed=0; s_failed=0; s_skipped=0
cur_suite=""
cur_section=""
stopped=0
grp_ms=0

finish_suite_timing() {
    case "$cur_suite" in
        gate:*|-|stray-files|"") ;;
        *)
            _grp_sec=$(printf '%d.%03d' $(( grp_ms / 1000 )) $(( grp_ms % 1000 )))
            printf '%s\tgroup\t%s\n' "$_grp_sec" "$cur_suite" >> "$TIMINGS_FILE"
            ;;
    esac
}

suite_line() {
    printf '  %-28s %5d run %5d passed %5d failed %5d skipped\n' \
        "$(suite_title "$cur_suite")" "$s_run" "$s_passed" "$s_failed" "$s_skipped"
}

total=$(wc -l < "$PLAN")
next=1
pool_done=0
exec 4< "$PLAN"
while [ $next -le "$total" ]; do
    if [ ! -e "$ITEMS/$next.st" ] && [ $pool_done -eq 0 ]; then
        # Wait for the pool's next message - but never blindly. This process's own write end keeps
        # the FIFO from reporting end-of-file, so if the pool died without writing `end` (killed, or
        # it crashed) a blocking read parks this loop forever: a partial report on screen, no
        # timeout of its own, and a work directory still locked. With `read -t` the pool is
        # re-checked every second, and a dead one ends the run, which then reports the items nobody
        # collected instead of hanging.
        msg=
        if [ "$_tr_read_timeout" -eq 1 ]; then
            read -r -t 1 msg <&3
            if [ -z "$msg" ] && ! pool_alive; then pool_done=1; fi
        else
            read -r msg <&3 || break
        fi
        [ "$msg" = end ] && pool_done=1
        continue
    fi
    read -r suite kind name <&4
    counts=$(cat "$ITEMS/$next.st" 2>/dev/null)
    if [ -z "$counts" ]; then
        counts="1 0 1 0"
        # Appended, not written: the worker's own output is the best evidence of how far it got.
        echo "[FAIL] $name (the worker left no result)" >> "$ITEMS/$next.out"
    fi
    if [ "$suite" != "$cur_suite" ]; then
        if [ -n "$cur_suite" ] && [ $stopped -eq 0 ]; then
            suite_line
            finish_suite_timing
        fi
        cur_suite="$suite"
        s_run=0; s_passed=0; s_failed=0; s_skipped=0
        grp_ms=0
        case "$suite" in gate:*) section=Gates ;; *) section=Tests ;; esac
        if [ "$section" != "$cur_section" ] && [ $stopped -eq 0 ]; then
            echo "$section"; cur_section=$section
        fi
    fi
    if [ "$counts" != STOPPED ] && [ $stopped -eq 0 ]; then
        cat "$ITEMS/$next.out" 2>/dev/null
        set -- $counts
        s_run=$((s_run + $1)); s_passed=$((s_passed + $2)); s_failed=$((s_failed + $3)); s_skipped=$((s_skipped + $4))
        tot_run=$((tot_run + $1)); tot_passed=$((tot_passed + $2))
        tot_failed=$((tot_failed + $3)); tot_skipped=$((tot_skipped + $4))
        item_time_str="0"
        item_ms=0
        if [ -f "$ITEMS/$next.time" ]; then
            read -r item_time_str item_ms < "$ITEMS/$next.time"
        fi
        grp_ms=$(( grp_ms + item_ms ))
        case "$kind" in
            gate)     printf '%s\tgate\t%s\n' "$item_time_str" "$name" >> "$TIMINGS_FILE" ;;
            scenario) printf '%s\tscenario\t%s\n' "$item_time_str" "$name" >> "$TIMINGS_FILE" ;;
            file)     printf '%s\ttest\t%s\n' "$item_time_str" "$name" >> "$TIMINGS_FILE" ;;
        esac
        if [ -n "$TR_RESULTS" ]; then
            if [ "$3" -gt 0 ]; then st=FAIL; elif [ "$1" -eq 0 ]; then st=SKIP; else st=PASS; fi
            printf '%s\t%s\n' "$st" "$name" >> "$TR_RESULTS"
        fi
        if [ "$3" -gt 0 ] && [ "$TR_FAIL_FAST" -eq 1 ]; then
            suite_line
            finish_suite_timing
            stopped=1
            echo "Stopping at the first failure (--fail-fast)."
        fi
    fi
    next=$((next + 1))
done
exec 3<&- 4<&-
wait $pool
if [ -n "$cur_suite" ] && [ $stopped -eq 0 ]; then
    suite_line
    finish_suite_timing
fi

# Every test must belong to exactly one group, or the full run silently skips it.
if [ $full_run -eq 1 ] && [ $stopped -eq 0 ]; then
    _claims=$(claim_lines)
    if [ -n "$_claims" ]; then
        printf '%s\n' "$_claims"
        _nclaims=$(printf '%s\n' "$_claims" | wc -l)
        tot_run=$((tot_run + _nclaims)); tot_failed=$((tot_failed + _nclaims))
    fi
fi

# Nothing this run wrote may stay outside build/: the next `git add -A` would commit it, and a
# .gitignore pattern is not a fix. The snapshot was taken before the first item, so a developer's
# own untracked work does not count (scripts/check_stray_files.sh). It is reported as its own
# suite line, so the suite lines still add up to the Total.
cur_suite="stray-files"
s_run=0; s_passed=0; s_failed=0; s_skipped=0
if [ -z "$stray_start" ]; then
    tot_skipped=$((tot_skipped + 1)); s_skipped=$((s_skipped + 1))
    [ "$TR_QUIET" -eq 1 ] || echo "[SKIP] stray-files (the work directory is not writable)"
else
    _stray=$(./scripts/check_stray_files.sh --compare "$stray_start" 2>/dev/null)
    tot_run=$((tot_run + 1)); s_run=$((s_run + 1))
    if [ -n "$_stray" ]; then
        tot_failed=$((tot_failed + 1)); s_failed=$((s_failed + 1))
        printf '%s\n' "$_stray" | while IFS= read -r _f; do
            echo "[FAIL] stray-files: $_f (a test wrote it outside build/)"
        done
    else
        tot_passed=$((tot_passed + 1)); s_passed=$((s_passed + 1))
        [ "$TR_QUIET" -eq 1 ] || echo "[PASS] stray-files: nothing was written outside build/"
    fi
fi
[ $stopped -eq 0 ] && suite_line

secs=$(awk -v ms="$(( $(tr_now_ms) - ALL_START ))" 'BEGIN { printf "%.1f", ms / 1000 }')
_tot_line="Total: $tot_run run, $tot_passed passed, $tot_failed failed, $tot_skipped skipped (${secs}s)"
echo "$_tot_line"
[ $tot_failed -eq 0 ]
