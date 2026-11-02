#!/bin/sh
# scripts/test_dep_matrix.sh — Test tool dependency matrix.
#
# Validates Zoril's dependency contracts per check_deps.sh --list-tools:
#   1. Optional tool missing: make test exits 0, its 'Skipping optional test items:' line names the tool,
#      and affected gates report [SKIP] with a reason.
#   2. Configurable tool off PATH: default name absent from PATH, variable points at real tool,
#      make test passes in full.
#   3. Required tool missing: make test fails within seconds before building/running anything,
#      naming the tool.

set -u

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR" || exit 2

# Clean environment if invoked under make (e.g. make deps-matrix)
unset MAKEFLAGS MAKEOVERRIDES MFLAGS MAKELEVEL REPO_ROOT

# Save configured tools before unsetting, so configurable rows can test them
_cfg_tool() {
    command -v "${1%% *}" 2>/dev/null || true
}
real_qbe=$(_cfg_tool "${BACKEND_BIN:-qbe}")
real_as=$(_cfg_tool "${ASSEMBLER_BIN:-as}")
real_ld=$(_cfg_tool "${LINKER_BIN:-ld}")
_cc_raw="${CC:-cc}"
real_cc=$(_cfg_tool "$_cc_raw")
_link_cc_raw="${LINK_CC:-cc}"
real_link_cc=$(_cfg_tool "$_link_cc_raw")
_cproc_raw="${CPROC:-cproc}"
real_cproc=$(_cfg_tool "$_cproc_raw")
_minimal_cpp_raw="${MINIMAL_CPP:-mcpp}"
real_minimal_cpp=$(_cfg_tool "$_minimal_cpp_raw")
real_tcc=$(_cfg_tool "tcc")
unset BACKEND_BIN ASSEMBLER_BIN LINKER_BIN CC LINK_CC CPROC MINIMAL_CPP

. scripts/lib/portability.sh
. scripts/lib/path_shim.sh
. scripts/lib/layout.sh

FILTER="$*"

# --selftest: Ctrl-C ends the matrix. A fake `make` that sleeps stands in for `make test` (the shims
# mirror PATH, so it is the one every row runs); SIGINT goes to the whole group, as the terminal
# sends it, and the matrix must exit non-zero at once, run no second row and leave nothing behind.
if [ "$FILTER" = "--selftest" ]; then
    st="$(mktemp -d "${TMPDIR:-/tmp}/dep_matrix_selftest_XXXXXX")"
    trap 'rm -rf "$st"' EXIT
    mkdir -p "$st/bin" "$st/tmp" "$st/work"
    # Job control: a background job of a script without it ignores SIGINT, which a trap cannot undo.
    # Where the shell cannot have it (BusyBox ash without a terminal), setsid gives the matrix its own group.
    launcher=""
    set -m 2>/dev/null
    case $- in
        *m*) ;;
        *)  if command -v setsid >/dev/null 2>&1; then launcher=setsid
            else echo "[SKIP] deps-matrix-interrupt: this shell has no job control here and there is no setsid"; exit 0; fi ;;
    esac
    # The test runner starts its items with SIGINT ignored, and the matrix cannot trap what it inherits
    # ignored: there the same handler is exercised through SIGTERM.
    sig=INT; signum=2
    [ "$($launcher sh -c 'kill -INT $$; echo alive' 2>/dev/null & wait)" = alive ] && { sig=TERM; signum=15; }
    printf '#!/bin/sh\nsleep 60\n' > "$st/bin/make"
    chmod +x "$st/bin/make"
    PATH="$st/bin:$PATH" TMPDIR="$st/tmp" TR_WORK="$st/work" DEP_MATRIX_DIR="$st/logs" $launcher "$0" "optional: " > "$st/out" 2>&1 &
    pid=$!
    sleep 3
    kill -"$signum" "-$pid" 2>/dev/null
    _i=0
    while kill -0 "$pid" 2>/dev/null && [ "$_i" -lt 150 ]; do sleep 0.1; _i=$((_i + 1)); done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "-$pid" 2>/dev/null
        echo "[FAIL] deps-matrix-interrupt: still running 15 s after SIG$sig"; sed 's/^/       /' "$st/out"; exit 1
    fi
    wait "$pid"; rc=$?
    rows=$(grep -c '^\[' "$st/out")
    left=$(ls "$st/tmp" | grep -c dep_matrix_)
    [ "$rc" -ne 0 ] || { echo "[FAIL] deps-matrix-interrupt: exit 0 after Ctrl-C"; exit 1; }
    [ "$rows" -le 1 ] || { echo "[FAIL] deps-matrix-interrupt: $rows rows reported after Ctrl-C"; sed 's/^/       /' "$st/out"; exit 1; }
    [ "$left" -eq 0 ] || { echo "[FAIL] deps-matrix-interrupt: the temporary directory was left behind"; exit 1; }
    echo "[PASS] deps-matrix-interrupt: SIG$sig ends the matrix (exit $rc), runs no second row and leaves no temporary directory"
    exit 0
fi

# Refuse to run when a config.local.mk exists that sets a toolchain variable,
# since its assignment would override the test row environment.
if [ -f "config.local.mk" ]; then
    if grep -E '^[[:space:]]*(BACKEND_BIN|ASSEMBLER_BIN|LINKER_BIN|CC|LINK_CC|CPROC|MINIMAL_CPP)[[:space:]]*[?:=]' config.local.mk >/dev/null 2>&1; then
        echo "deps-matrix: config.local.mk sets toolchain variable(s); remove or rename config.local.mk before running make deps-matrix" >&2
        exit 2
    fi
fi

MATRIX_DIR="${DEP_MATRIX_DIR:-$REPO_DIR/build/deps-matrix}"
mkdir -p "$MATRIX_DIR"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/dep_matrix_XXXXXX")"
cleanup() {
    rm -rf "$tmp"
}
# A killed `make test` leaves its pool and workers holding the work directory's lock for up to one
# test's time; the next run would be refused ("another test run is using ..."), so wait for it.
wait_for_test_lock() {
    command -v flock >/dev/null 2>&1 || return 0
    _lock="${TR_WORK:-build/tests}/.lock"
    [ -e "$_lock" ] || return 0
    _w=0
    while [ "$_w" -lt 300 ]; do
        flock -n "$_lock" -c true 2>/dev/null && return 0
        sleep 0.1
        _w=$((_w + 1))
    done
}
# A signal ends the matrix. A handler that only cleaned up let the loop go on to the next row, with
# the PATH shims already deleted, so every later row failed for a reason that was not its own.
trap cleanup EXIT
trap 'cleanup; wait_for_test_lock; exit 130' INT
trap 'cleanup; wait_for_test_lock; exit 143' TERM

passed=0
failed=0
skipped=0
total_start=$(now_ms)

matches_filter() {
    [ -z "$FILTER" ] && return 0
    case "$1" in
        *"$FILTER"*) return 0 ;;
        *) return 1 ;;
    esac
}

calc_dur() {
    _start="$1"
    _end=$(now_ms)
    echo $(( (_end - _start) / 1000 ))
}

# -----------------------------------------------------------------------------
# Row Loop 1: Optional tools missing
# -----------------------------------------------------------------------------
# For build/test profiles: git, timeout, setsid, valgrind, dprint, rustc, cproc, mcpp, lua, scdoc
for opt_tool in git timeout setsid valgrind dprint rustc cproc mcpp lua scdoc; do
    row_name="optional: $opt_tool missing"
    matches_filter "$row_name" || continue

    shim="$tmp/shim_opt_$opt_tool"
    path_without "$shim" "$opt_tool"
    log="$MATRIX_DIR/optional-$opt_tool.log"
    row_start=$(now_ms)
    rc=0
    PATH="$shim" make test > "$log" 2>&1 || rc=$?
    dur=$(calc_dur "$row_start")

    # Contract: exits 0, Skipping optional test items names tool
    if [ $rc -eq 0 ] && grep -qF "Skipping optional test items:" "$log" && grep -qF "$opt_tool" "$log"; then
        echo "[PASS] $row_name (${dur}s)"
        passed=$((passed + 1))
    else
        echo "[FAIL] $row_name (exit $rc, see build/deps-matrix/optional-$opt_tool.log)"
        failed=$((failed + 1))
    fi
done

# -----------------------------------------------------------------------------
# Row Loop 2: Configurable tools off PATH
# -----------------------------------------------------------------------------

# 2a: qbe via BACKEND_BIN
row_name="configurable: qbe via BACKEND_BIN off PATH"
if matches_filter "$row_name"; then
    if [ -n "$real_qbe" ] && [ -x "$real_qbe" ]; then
        shim="$tmp/shim_cfg_qbe"
        path_without "$shim" qbe
        log="$MATRIX_DIR/configurable-qbe.log"
        row_start=$(now_ms)
        rc=0
        BACKEND_BIN="$real_qbe" PATH="$shim" make test > "$log" 2>&1 || rc=$?
        dur=$(calc_dur "$row_start")
        if [ $rc -eq 0 ]; then
            echo "[PASS] $row_name (${dur}s)"
            passed=$((passed + 1))
        else
            echo "[FAIL] $row_name (exit $rc, see build/deps-matrix/configurable-qbe.log)"
            failed=$((failed + 1))
        fi
    else
        echo "[SKIP] $row_name: qbe not found on host"
        skipped=$((skipped + 1))
    fi
fi

# 2b: as via ASSEMBLER_BIN
row_name="configurable: as via ASSEMBLER_BIN off PATH"
if matches_filter "$row_name"; then
    if [ -n "$real_as" ] && [ -x "$real_as" ]; then
        as_dir="$(dirname "$real_as")"
        shim="$tmp/shim_cfg_as"
        path_without "$shim" as
        log="$MATRIX_DIR/configurable-as.log"
        row_start=$(now_ms)
        rc=0
        CC="$real_cc -B$as_dir" ASSEMBLER_BIN="$real_as" PATH="$shim" make test > "$log" 2>&1 || rc=$?
        dur=$(calc_dur "$row_start")
        if [ $rc -eq 0 ]; then
            echo "[PASS] $row_name (${dur}s)"
            passed=$((passed + 1))
        else
            echo "[FAIL] $row_name (exit $rc, see build/deps-matrix/configurable-as.log)"
            failed=$((failed + 1))
        fi
    else
        echo "[SKIP] $row_name: as not found on host"
        skipped=$((skipped + 1))
    fi
fi

# 2c: ld via LINKER_BIN
row_name="configurable: ld via LINKER_BIN off PATH"
if matches_filter "$row_name"; then
    if [ -n "$real_ld" ] && [ -x "$real_ld" ]; then
        ld_dir="$(dirname "$real_ld")"
        shim="$tmp/shim_cfg_ld"
        path_without "$shim" ld
        log="$MATRIX_DIR/configurable-ld.log"
        row_start=$(now_ms)
        rc=0
        CC="$real_cc -B$ld_dir" LINKER_BIN="$real_ld" PATH="$shim" make test > "$log" 2>&1 || rc=$?
        dur=$(calc_dur "$row_start")
        if [ $rc -eq 0 ]; then
            echo "[PASS] $row_name (${dur}s)"
            passed=$((passed + 1))
        else
            echo "[FAIL] $row_name (exit $rc, see build/deps-matrix/configurable-ld.log)"
            failed=$((failed + 1))
        fi
    else
        echo "[SKIP] $row_name: ld not found on host"
        skipped=$((skipped + 1))
    fi
fi

# 2d: cc via CC
row_name="configurable: cc via CC off PATH"
if matches_filter "$row_name"; then
    if [ -n "$real_cc" ] && [ -x "$real_cc" ]; then
        shim="$tmp/shim_cfg_cc"
        path_without "$shim" cc
        log="$MATRIX_DIR/configurable-cc.log"
        row_start=$(now_ms)
        rc=0
        CC="$real_cc" PATH="$shim" make test > "$log" 2>&1 || rc=$?
        dur=$(calc_dur "$row_start")
        if [ $rc -eq 0 ]; then
            echo "[PASS] $row_name (${dur}s)"
            passed=$((passed + 1))
        else
            echo "[FAIL] $row_name (exit $rc, see build/deps-matrix/configurable-cc.log)"
            failed=$((failed + 1))
        fi
    else
        echo "[SKIP] $row_name: cc/gcc not found on host"
        skipped=$((skipped + 1))
    fi
fi

# 2e: cc via LINK_CC off PATH
row_name="configurable: cc via LINK_CC off PATH"
if matches_filter "$row_name"; then
    if [ -n "$real_link_cc" ] && [ -x "$real_link_cc" ] && [ -n "$real_cc" ] && [ -x "$real_cc" ]; then
        shim="$tmp/shim_cfg_link_cc"
        path_without "$shim" cc
        log="$MATRIX_DIR/configurable-link-cc.log"
        row_start=$(now_ms)
        rc=0
        CC="$real_cc" LINK_CC="$real_link_cc" PATH="$shim" make test > "$log" 2>&1 || rc=$?
        dur=$(calc_dur "$row_start")
        if [ $rc -eq 0 ]; then
            echo "[PASS] $row_name (${dur}s)"
            passed=$((passed + 1))
        else
            echo "[FAIL] $row_name (exit $rc, see build/deps-matrix/configurable-link-cc.log)"
            failed=$((failed + 1))
        fi
    else
        echo "[SKIP] $row_name: cc not found on host"
        skipped=$((skipped + 1))
    fi
fi

# 2f: minimal stack: cproc + mcpp (zero GCC/Clang)
row_name="minimal stack: cproc + mcpp (zero GCC/Clang)"
if matches_filter "$row_name"; then
    if [ -n "$real_cproc" ] && [ -x "$real_cproc" ] && [ -n "$real_minimal_cpp" ] && [ -x "$real_minimal_cpp" ]; then
        shim="$tmp/shim_min_stack"
        path_without "$shim" cc
        log="$MATRIX_DIR/minimal-stack.log"
        row_start=$(now_ms)
        rc=0
        PATH="$shim" ./scripts/check_stage0c_minimal.sh > "$log" 2>&1 || rc=$?
        dur=$(calc_dur "$row_start")
        if [ $rc -eq 0 ] && grep -qF "[PASS] stage0c-minimal" "$log"; then
            echo "[PASS] $row_name (${dur}s)"
            passed=$((passed + 1))
        elif [ $rc -eq 0 ] && grep -qF "[SKIP] stage0c-minimal" "$log"; then
            reason=$(grep -F "[SKIP] stage0c-minimal" "$log" | head -n1)
            echo "[SKIP] $row_name: $reason"
            skipped=$((skipped + 1))
        else
            echo "[FAIL] $row_name (exit $rc, see build/deps-matrix/minimal-stack.log)"
            failed=$((failed + 1))
        fi
    else
        echo "[SKIP] $row_name: cproc or mcpp not found on host"
        skipped=$((skipped + 1))
    fi
fi

# 2g: configurable: MINIMAL_CPP='tcc -E'
row_name="configurable: MINIMAL_CPP='tcc -E'"
if matches_filter "$row_name"; then
    if [ -n "$real_tcc" ] && [ -x "$real_tcc" ] && [ -n "$real_cproc" ] && [ -x "$real_cproc" ]; then
        log="$MATRIX_DIR/configurable-tcc-e.log"
        row_start=$(now_ms)
        rc=0
        MINIMAL_CPP="tcc -E" ./scripts/check_stage0c_minimal.sh > "$log" 2>&1 || rc=$?
        dur=$(calc_dur "$row_start")
        if [ $rc -eq 0 ] && grep -qF "[PASS] stage0c-minimal" "$log"; then
            echo "[PASS] $row_name (${dur}s)"
            passed=$((passed + 1))
        elif [ $rc -eq 0 ] && grep -qF "[SKIP] stage0c-minimal" "$log"; then
            reason=$(grep -F "[SKIP] stage0c-minimal" "$log" | head -n1)
            echo "[SKIP] $row_name: $reason"
            skipped=$((skipped + 1))
        else
            echo "[FAIL] $row_name (exit $rc, see build/deps-matrix/configurable-tcc-e.log)"
            failed=$((failed + 1))
        fi
    else
        echo "[SKIP] $row_name: tcc not found on host"
        skipped=$((skipped + 1))
    fi
fi

# 2h: minimal route: make after stage0 minimal without cc
row_name="minimal route: make after stage0 minimal without cc"
if matches_filter "$row_name"; then
    if [ -n "$real_cproc" ] && [ -x "$real_cproc" ] && [ -n "$real_minimal_cpp" ] && [ -x "$real_minimal_cpp" ]; then
        shim="$tmp/shim_min_route"
        path_without "$shim" cc
        log="$MATRIX_DIR/minimal-route.log"
        row_start=$(now_ms)
        rc=0
        (
            make -C "$STAGE0_DIR" clean >/dev/null 2>&1 && \
            PATH="$shim" make -C "$STAGE0_DIR" minimal > "$log" 2>&1 && \
            PATH="$shim" make >> "$log" 2>&1
        ) || rc=$?
        dur=$(calc_dur "$row_start")
        if [ $rc -eq 0 ]; then
            echo "[PASS] $row_name (${dur}s)"
            passed=$((passed + 1))
        else
            echo "[FAIL] $row_name (exit $rc, see build/deps-matrix/minimal-route.log)"
            failed=$((failed + 1))
        fi
    else
        echo "[SKIP] $row_name: cproc or mcpp not found on host"
        skipped=$((skipped + 1))
    fi
fi

# 2i: gcc-free machine: CC=cproc without GCC/Clang driver
row_name="gcc-free machine: CC=cproc without GCC/Clang driver"
if matches_filter "$row_name"; then
    if [ -n "$real_cproc" ] && [ -x "$real_cproc" ]; then
        shim="$tmp/shim_gcc_free"
        path_without "$shim" cc tcc
        log="$MATRIX_DIR/gcc-free-machine.log"
        row_start=$(now_ms)
        rc=0
        PATH="$shim" CC=cproc make test > "$log" 2>&1 || rc=$?
        dur=$(calc_dur "$row_start")
        if [ $rc -eq 0 ]; then
            echo "[PASS] $row_name (${dur}s)"
            passed=$((passed + 1))
        else
            echo "[FAIL] $row_name (exit $rc, see build/deps-matrix/gcc-free-machine.log)"
            failed=$((failed + 1))
        fi
    else
        echo "[SKIP] $row_name: cproc not found on host"
        skipped=$((skipped + 1))
    fi
fi

# 2j: configurable: cc on make command line off PATH
row_name="configurable: cc on command line off PATH"
if matches_filter "$row_name"; then
    if [ -n "$real_cc" ] && [ -x "$real_cc" ]; then
        shim="$tmp/shim_cfg_cc_cmdline"
        path_without "$shim" cc
        log="$MATRIX_DIR/configurable-cc-cmdline.log"
        row_start=$(now_ms)
        rc=0
        PATH="$shim" make test CC="$real_cc" > "$log" 2>&1 || rc=$?
        dur=$(calc_dur "$row_start")
        if [ $rc -eq 0 ]; then
            echo "[PASS] $row_name (${dur}s)"
            passed=$((passed + 1))
        else
            echo "[FAIL] $row_name (exit $rc, see build/deps-matrix/configurable-cc-cmdline.log)"
            failed=$((failed + 1))
        fi
    else
        echo "[SKIP] $row_name: cc/gcc not found on host"
        skipped=$((skipped + 1))
    fi
fi

# -----------------------------------------------------------------------------
# Row Loop 3: Required tools missing
# -----------------------------------------------------------------------------
# Contract: fails within seconds before building/running anything, names tool.
for req_tool in awk sed flock mkfifo xargs qbe as ld cc; do
    row_name="required: $req_tool missing"
    matches_filter "$row_name" || continue

    shim="$tmp/shim_req_$req_tool"
    path_without "$shim" "$req_tool"
    log="$MATRIX_DIR/required-$req_tool.log"
    row_start=$(now_ms)
    rc=0
    PATH="$shim" run_with_timeout 15 make test > "$log" 2>&1 || rc=$?
    dur=$(calc_dur "$row_start")

    # Tool name to search in output
    search_name="$req_tool"
    case "$req_tool" in
        cc) search_name="cc" ;;
    esac

    if [ $rc -ne 0 ] && grep -qiE "Missing required tool: $search_name|C bootstrap compiler" "$log"; then
        echo "[PASS] $row_name (aborts upfront in ${dur}s)"
        passed=$((passed + 1))
    else
        echo "[FAIL] $row_name (rc=$rc, see build/deps-matrix/required-$req_tool.log)"
        failed=$((failed + 1))
    fi
done

total_dur=$(calc_dur "$total_start")
total_min=$((total_dur / 60))
total_sec=$((total_dur % 60))

echo ""
if [ "$skipped" -gt 0 ]; then
    echo "deps-matrix: $passed passed, $failed failed, $skipped skipped (${total_min}m ${total_sec}s)."
else
    echo "deps-matrix: $passed passed, $failed failed (${total_min}m ${total_sec}s)."
fi

[ "$failed" -eq 0 ]
