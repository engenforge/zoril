#!/bin/sh
# scripts/test.sh — the Zoril test runner.
#
# Usage:
#   scripts/test.sh [options]                  every group
#   scripts/test.sh [options] --gates          every gate, then every group (make test)
#   scripts/test.sh [options] --gate NAME ...  only the named gates (repeatable)
#   scripts/test.sh [options] --group G ...    only the named groups (repeatable)
#   scripts/test.sh [options] --suite S        suite: all, group, corpus, incremental, chain, or tests/<dir>
#   scripts/test.sh [options] PATH...          only these test files or directories
#   scripts/test.sh [options] --smoke          the smoke suite, tests/smoke.list (make test-fast)
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
    esac
}

# group_paths G — the per-file test roots of group G. Every test belongs to exactly one.
group_paths() {
    case "$1" in
        language)    echo tests/language/basic tests/language/control_flow tests/language/match \
                          tests/language/other tests/language/modules tests/language/phi tests/language/slices \
                          tests/functional/basic tests/functional/control_flow tests/functional/phi \
                          tests/functional/codegen tests/functional/*.zrl \
                          tests/compiler tests/unit tests/benchmarks ;;
        types)       echo tests/language/enums tests/language/generics tests/language/structs \
                          tests/language/traits tests/functional/enums tests/functional/structs ;;
        memory)      echo tests/language/memory tests/language/pointers tests/language/closures \
                          tests/functional/pointers tests/interproc_summary ;;
        stdlib)      echo tests/stdlib tests/functional/stdlib ;;
        diagnostics) echo tests/error_reporting ;;
        integration) echo tests/integration tests/regressions tests/bootstrap corpus ;;
    esac
}

# scenario_export_checks_selftest is scripts/test_export_checks.sh: the guards it runs are
# private-only (scripts/export_public_release.sh does not ship them), so an exported tree lacks
# them by design; the wrapper reports the skip and passes, never fails.

# group_scenarios G — the multi-step scripts of group G, listed after its per-file tests.
group_scenarios() {
    case "$1" in
        memory)      echo cross-module-safety-matrix ;;
        stdlib)
            echo sha256-differential
            ;;
        integration)
            echo incremental fuzz-jobs fuzz-mode-diff fuzz-tools modular-mangling uncalled-method-emit runner-output readme-snippets doc-snippets getting-started struct-layout ffi-export ffi-callback zbuild-link module-names interface-attrs hosted platform-layer man-pages tool-versions md-links safety-comments-selftest no-new-deps-selftest comment-noise-selftest comment-census-selftest export-checks-selftest bench-contention bench-threshold-gate test-lock preflight-selftest check-deps-selftest result-file scdoc-min stray-files-selftest
            echo bench-step-failed reject-diff-selftest zbuild-errors zbuild-diff user-paths build-info qbe-arg-order qbe-fingerprint full-test-stamp deps-matrix-interrupt
            ;;
        diagnostics) echo zilc-errors ;;
    esac
}

scenario_run() {
    case "$1" in
        cross-module-safety-matrix) tr_run_scenario "$1" ./scripts/test_safety_matrix_cross_module.sh ;;
        sha256-differential)        tr_run_scenario "$1" ./scripts/test_sha256_differential.sh ;;
        incremental)                tr_run_scenario "$1" ./scripts/test_incremental.sh --quiet ;;
        fuzz-jobs)                  tr_run_scenario "$1" ./scripts/test_fuzz_jobs.sh --quiet ;;
        fuzz-mode-diff)             tr_run_scenario "$1" ./scripts/test_fuzz_mode_diff.sh ;;
        fuzz-tools)                 tr_run_scenario "$1" ./scripts/test_fuzz_tools.sh --quiet ;;
        modular-mangling)           tr_run_scenario "$1" ./scripts/test_modular_mangling.sh ;;
        uncalled-method-emit)       tr_run_scenario "$1" ./scripts/test_uncalled_method_emit.sh ;;
        runner-output)              tr_run_scenario "$1" ./scripts/test_runner_output.sh ;;
        readme-snippets)            tr_run_scenario "$1" ./scripts/test_readme_snippets.sh ;;
        doc-snippets)               tr_run_scenario "$1" ./scripts/test_doc_snippets.sh ;;
        getting-started)            tr_run_scenario "$1" ./scripts/test_getting_started.sh ;;
        struct-layout)              tr_run_scenario "$1" ./scripts/test_struct_layout.sh ;;
        ffi-export)                 tr_run_scenario "$1" ./scripts/test_ffi_export.sh ;;
        ffi-callback)               tr_run_scenario "$1" ./scripts/test_ffi_callback.sh ;;
        zbuild-link)                tr_run_scenario "$1" ./scripts/test_zbuild_link.sh ;;
        module-names)               tr_run_scenario "$1" ./scripts/test_module_names.sh ;;
        interface-attrs)            tr_run_scenario "$1" ./scripts/test_interface_attrs.sh ;;
        hosted)                     tr_run_scenario "$1" ./scripts/test_hosted.sh ;;
        platform-layer)             tr_run_scenario "$1" ./scripts/test_platform_layer.sh ;;
        man-pages)                  tr_run_scenario "$1" ./scripts/test_man_pages.sh ;;
        tool-versions)              tr_run_scenario "$1" ./scripts/test_tool_versions.sh ;;
        md-links)                   tr_run_scenario "$1" ./scripts/test_check_md_links.sh ;;
        safety-comments-selftest)   tr_run_scenario "$1" ./scripts/test_check_safety_comments.sh ;;
        no-new-deps-selftest)         tr_run_scenario "$1" ./scripts/test_check_no_new_deps.sh ;;
        comment-noise-selftest)     tr_run_scenario "$1" ./scripts/test_check_comment_noise.sh ;;
        comment-census-selftest)    tr_run_scenario "$1" ./scripts/test_comment_census.sh ;;
        export-checks-selftest)     tr_run_scenario "$1" ./scripts/test_export_checks.sh ;;
        bench-contention)           tr_run_scenario "$1" ./scripts/test_bench_contention.sh ;;
        bench-threshold-gate)       tr_run_scenario "$1" ./scripts/test_bench_threshold_gate.sh ;;
        test-lock)                  tr_run_scenario "$1" ./scripts/test_test_lock.sh ;;
        preflight-selftest)         tr_run_scenario "$1" ./scripts/test_preflight.sh ;;
        check-deps-selftest)        tr_run_scenario "$1" ./scripts/test_check_deps.sh ;;
        result-file)                tr_run_scenario "$1" ./scripts/test_result_file.sh ;;
        scdoc-min)                  tr_run_scenario "$1" ./scripts/test_scdoc_min.sh ;;
        stray-files-selftest)       tr_run_scenario "$1" ./scripts/check_stray_files.sh --selftest ;;
        bench-step-failed)          tr_run_scenario "$1" ./scripts/test_bench_step_failed.sh ;;
        reject-diff-selftest)       tr_run_scenario "$1" ./scripts/test_reject_diff.sh ;;
        zbuild-errors)              tr_run_scenario "$1" ./scripts/test_zbuild_errors.sh ;;
        zbuild-diff)                tr_run_scenario "$1" ./scripts/test_zbuild_diff.sh ;;
        user-paths)                 tr_run_scenario "$1" ./scripts/test_user_paths.sh ;;
        build-info)                 tr_run_scenario "$1" ./scripts/test_build_info.sh ;;
        qbe-arg-order)              tr_run_scenario "$1" ./scripts/test_qbe_arg_order.sh ;;
        qbe-fingerprint)            tr_run_scenario "$1" ./scripts/test_qbe_fingerprint.sh ;;
        full-test-stamp)            tr_run_scenario "$1" ./scripts/test_full_test_stamp.sh ;;
        deps-matrix-interrupt)  tr_run_scenario "$1" ./scripts/test_dep_matrix.sh --selftest ;;
        zilc-errors)                tr_run_scenario "$1" ./scripts/test_zilc_errors.sh ;;
    esac
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
# This list is also the display order: results print in plan order, so one slow gate holds back
# every line after it. The slowest is last for that reason - mutation-self-test builds four mutant
# compilers (about a minute and a half), and it used to sit in the middle, freezing the count lines
# of the twenty gates that had already finished.
GATES_ALL="fmt-check md-check no-new-deps binary-sizes no-warnings test-strength fuzz-record fuzz-fresh safety-matrix safety-matrix-zbuild safety-model safety-comments safety-figures comment-noise reborrow-probes exhaustive route-coverage temp-names unsafe-scan runtimes static-image perf-gate toolchain portability clean-tree toolchain-offpath stage0c-fixed-bugs stage0c-unit
           stage0c-corpus stage0c-docs stage0c-error-locations stage0c-functional stage0c-minimal mutation-self-test"

gate_command() {
    case "$1" in
        fmt-check)               echo ./scripts/check_fmt.sh ;;
        mutation-self-test)      echo ./scripts/test_mutation_check.sh ;;
        md-check)                echo ./scripts/check_md_fmt.sh ;;
        no-new-deps)               echo ./scripts/check_no_new_deps.sh ;;
        binary-sizes)            echo ./scripts/check_binary_sizes.sh ;;
        no-warnings)             echo ./scripts/check_no_warnings.sh ;;
        test-strength)           echo ./scripts/check_test_strength.sh ;;
        fuzz-record)             echo ./scripts/check_fuzz_record.sh ;;
        fuzz-fresh)              echo ./scripts/check_fuzz_fresh.sh ;;
        safety-matrix)           echo ./scripts/run_safety_matrix.sh ;;
        safety-matrix-zbuild)    echo ./scripts/run_safety_matrix.sh --zbuild ;;
        safety-model)            echo ./scripts/check_safety_model.sh ;;
        safety-comments)         echo ./scripts/check_safety_comments.sh ;;
        safety-figures)          echo "./scripts/check_safety_figures.sh --all" ;;
        comment-noise)           echo ./scripts/check_comment_noise.sh ;;
        reborrow-probes)         echo ./scripts/check_reborrow_probes.sh ;;
        store-grid)              echo ./scripts/check_store_grid.sh ;;
        exhaustive)              echo "./scripts/check_exhaustive.sh --selftest && ./scripts/check_exhaustive.sh" ;;
        route-coverage)          echo ./scripts/check_route_coverage.sh ;;
        temp-names)              echo ./scripts/check_temp_names.sh ;;
        unsafe-scan)             echo ./scripts/unsafe_scan.sh ;;
        runtimes)                echo ./scripts/check_runtimes.sh ;;
        static-image)            echo ./scripts/check_static_image_determinism.sh ;;
        perf-gate)               echo "./scripts/perf_gap.sh --gate-check" ;;
        toolchain)               echo ./scripts/check_toolchain.sh ;;
        portability)             echo ./scripts/check_portability.sh ;;
        clean-tree)              echo ./scripts/check_clean_tree.sh ;;
        toolchain-offpath)       echo ./scripts/check_toolchain_offpath.sh ;;
        stage0c-fixed-bugs)      echo "./$STAGE0_DIR/scripts/test_fixed_bugs.sh" ;;
        stage0c-unit)            echo "${MAKE:-make} --no-print-directory -C $STAGE0_DIR test_unit" ;;
        stage0c-corpus)          echo "${MAKE:-make} --no-print-directory -C $STAGE0_DIR test_corpus" ;;
        stage0c-docs)            echo "${MAKE:-make} --no-print-directory -C $STAGE0_DIR test_docs" ;;
        stage0c-error-locations) echo "${MAKE:-make} --no-print-directory -C $STAGE0_DIR test_error_locations" ;;
        stage0c-functional)      echo "${MAKE:-make} --no-print-directory -C $STAGE0_DIR test_functional" ;;
        stage0c-minimal)         echo ./scripts/check_stage0c_minimal.sh ;;
        # Misbehaving gates for the runner's own output test (scripts/test_runner_output.sh).
        fixture-*)
            _fx="tests/runner/fixtures/gates/$(echo "${1#fixture-}" | tr - _).sh"
            [ -x "$_fx" ] && echo "$_fx" ;;
    esac
}

# gate_run NAME — run a gate and report its items as "[STATUS] NAME: item". Sets the TR_*
# counters. A gate fails if it reports a [FAIL], prints a result line in any other format,
# exits non-zero without reporting why, or reports nothing.
gate_run() {
    _gname="$1"
    _glog="build/gates/$_gname.log"
    mkdir -p build/gates
    QUIET=0 $(gate_command "$_gname") > "$_glog" 2>&1
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
        TR_RESULTS=""
        case "$kind" in
            file)     tr_run_file "$name" > "$ITEMS/$idx.out" 2>&1 ;;
            scenario) scenario_run "$name" > "$ITEMS/$idx.out" 2>&1 ;;
            gate)     gate_run "$name" > "$ITEMS/$idx.out" 2>&1 ;;
        esac
        # Every item reports the same four counts: run passed failed skipped.
        write_status "$TR_RUN $TR_PASSED $TR_FAILED $TR_SKIPPED"
        [ "$TR_FAILED" -gt 0 ] && [ "$TR_FAIL_FAST" -eq 1 ] && : > "$ITEMS/stop"
    fi
    dispatcher_alive || exit 0
    echo "$idx" > "$ITEMS/done.fifo"
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
label="Selected tests"
suite_incremental=0
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
        --gates) gates="$GATES_ALL"; shift ;;
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
rm -rf "$ITEMS" && mkdir -p "$ITEMS"
cleanup() { rm -f "$PLAN" "$claimed"; }
trap 'cleanup; _tr_sig_handler' INT TERM
trap cleanup EXIT

for g in $gates; do echo "gate:$g gate $g" >> "$PLAN"; done

full_run=0
if [ -n "$paths" ]; then
    filtered "$(tr_discover $paths)" | sed '/^$/d; s/^/- file /' >> "$PLAN"
    if ! grep -q ' file ' "$PLAN"; then
        echo "no tests found in$paths${TR_FILTER:+ matching '$TR_FILTER'}" >&2
        exit 1
    fi
elif [ -n "$groups" ] || [ -z "$gates" ] || [ "$gates" = "$GATES_ALL" ]; then
    if [ -z "$groups" ]; then
        groups="$GROUPS_ALL"
        [ -z "$TR_FILTER" ] && full_run=1
    fi
    for g in $groups; do
        all=$(tr_discover $(group_paths "$g"))
        printf '%s\n' "$all" >> "$claimed"
        filtered "$all" | sed "/^\$/d; s/^/$g file /" >> "$PLAN"
        # Scenarios have no single test path, so --filter leaves them out.
        if [ -z "$TR_FILTER" ]; then
            for sc in $(group_scenarios "$g"); do echo "$g scenario $sc" >> "$PLAN"; done
        fi
    done
    if [ ! -s "$PLAN" ]; then
        echo "no tests matched${TR_FILTER:+ '$TR_FILTER'}" >&2
        exit 1
    fi
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
        [ -n "$cur_suite" ] && [ $stopped -eq 0 ] && suite_line
        cur_suite="$suite"
        s_run=0; s_passed=0; s_failed=0; s_skipped=0
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
        if [ -n "$TR_RESULTS" ]; then
            if [ "$3" -gt 0 ]; then st=FAIL; elif [ "$1" -eq 0 ]; then st=SKIP; else st=PASS; fi
            printf '%s\t%s\n' "$st" "$name" >> "$TR_RESULTS"
        fi
        if [ "$3" -gt 0 ] && [ "$TR_FAIL_FAST" -eq 1 ]; then
            suite_line
            stopped=1
            echo "Stopping at the first failure (--fail-fast)."
        fi
    fi
    next=$((next + 1))
done
exec 3<&- 4<&-
wait $pool
[ -n "$cur_suite" ] && [ $stopped -eq 0 ] && suite_line

# Every test must belong to exactly one group, or the full run silently skips it.
if [ $full_run -eq 1 ] && [ $stopped -eq 0 ]; then
    dups=$(grep -v '^$' "$claimed" | sort | uniq -d)
    lost=$(tr_discover tests corpus | grep -vxF -f "$claimed")
    for f in $dups; do echo "[FAIL] $f (in more than one group)"; tot_run=$((tot_run + 1)); tot_failed=$((tot_failed + 1)); done
    for f in $lost; do echo "[FAIL] $f (in no group; add it to group_paths in scripts/test.sh)"; tot_run=$((tot_run + 1)); tot_failed=$((tot_failed + 1)); done
fi

# Nothing this run wrote may stay outside build/: the next `git add -A` would commit it, and a
# .gitignore pattern is not a fix. The snapshot was taken before the first item, so a developer's
# own untracked work does not count (scripts/check_stray_files.sh). It is reported as its own
# suite line, so the suite lines still add up to the Total.
cur_suite="stray-files"
s_run=0; s_passed=0; s_failed=0; s_skipped=0
if [ -z "$stray_start" ]; then
    tot_skipped=$((tot_skipped + 1)); s_skipped=$((s_skipped + 1))
    [ "$TR_QUIET" -eq 1 ] || echo "[SKIP] stray-files (this tree is not a git checkout, or the work directory is not writable)"
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
echo "Total: $tot_run run, $tot_passed passed, $tot_failed failed, $tot_skipped skipped (${secs}s)"
# A whole run (every gate and group, no filter) that passes leaves a stamp naming the tree it tested:
# scripts/export_public_release.sh refuses to export a tree that has changed since (A0: an export was
# made from a tree whose `make test` had not run after the last change).
if [ $tot_failed -eq 0 ] && [ "${full_run:-0}" = 1 ] && [ -z "$paths" ] && [ -z "$TR_FILTER" ] \
    && [ "$(echo $gates)" = "$(echo $GATES_ALL)" ] && [ -z "${TR_EXCLUDE:-}" ]; then
    ./scripts/full_test_stamp.sh write 2> /dev/null || true
fi
[ $tot_failed -eq 0 ]
