#!/bin/sh
# scripts/test_hosted.sh — a Zoril program linked into a libc process (`zoril --hosted`).
#
# Hosted mode is opt-in. The program is entered from crt1's main through rt/runtime_hosted.o, the
# link goes through `cc`, and libc owns memcpy, memset, malloc, abort and exit. Checked here, each
# program built by the manual pipeline (zoril --hosted, zilc, qbe, as, cc):
#   printf and getenv work, argc reaches args(), the exit status is main's, and stdout buffered
#     by C is flushed at exit (libc's exit runs);
#   libc's qsort calls a Zoril `extern "C" fn` back;
#   a real shared library (zlib, -lz) links and runs;
#   a bounds trap ends the process with 134 and does not flush C stdio;
#   the same program built WITHOUT --hosted is unchanged: ZIL with main, no zoril_main.
# Skipped, with a reason, where there is no `cc` or no dynamic libc (and, for zlib, no libz).
cd "$(dirname "$0")/.." || exit 2
. scripts/env.sh
ZORIL=${ZORIL_BIN:-./build/zoril}
ZILC=${ZILC_BIN:-./build/zilc}
RTH=${RUNTIME_HOSTED_BIN:-./build/runtime_hosted.o}
CC_BIN=${CC:-cc}
dir=build/hosted
rm -rf "$dir"
mkdir -p "$dir"
src=tests/hosted/include
fail() { echo "[FAIL] hosted: $1"; [ -n "$2" ] && sed 's/^/       /' "$2"; exit 1; }

command -v "$CC_BIN" >/dev/null 2>&1 || { echo "[SKIP] hosted: no C compiler ($CC_BIN)"; exit 0; }
printf 'int main(void) { return 0; }\n' > "$dir/probe.c"
"$CC_BIN" -o "$dir/probe" "$dir/probe.c" >/dev/null 2>&1 && "$dir/probe" \
    || { echo "[SKIP] hosted: $CC_BIN cannot build and run a libc program here"; exit 0; }
[ -f "$RTH" ] || fail "$RTH is missing (make build/runtime_hosted.o)"

# build NAME [cc args]: NAME.zrl -> hosted executable
build() {
    n=$1; shift
    "$ZORIL" --hosted -I stdlib=stdlib --emit-zil -o "$dir/$n.zil" "$src/$n.zrl" > "$dir/$n.zoril.log" 2>&1 \
        || fail "$n does not compile with --hosted" "$dir/$n.zoril.log"
    "$ZILC" "$dir/$n.zil" "$dir/$n.ssa" > "$dir/$n.zilc.log" 2>&1 || fail "zilc rejects $n" "$dir/$n.zilc.log"
    "$BACKEND_BIN" -o "$dir/$n.s" "$dir/$n.ssa" && "$ASSEMBLER_BIN" -o "$dir/$n.o" "$dir/$n.s" \
        || fail "$n does not assemble"
    "$CC_BIN" -o "$dir/$n" "$dir/$n.o" "$RTH" "$@" > "$dir/$n.cc.log" 2>&1 || fail "$n does not link" "$dir/$n.cc.log"
}

# 1. printf, getenv, argc, the exit status and the flush at exit.
build printf_getenv
ZORIL_HOSTED_VAR=seen "$dir/printf_getenv" a b > "$dir/printf_getenv.out"; rc=$?
[ "$rc" -eq 3 ] || fail "printf_getenv exited $rc, expected main's 3"
[ "$(cat "$dir/printf_getenv.out")" = "args=3 var=seen
no newline, flushed at exit" ] || fail "printf_getenv printed the wrong text" "$dir/printf_getenv.out"

# 2. libc's qsort calls a Zoril callback.
build qsort_callback
out=$("$dir/qsort_callback") || fail "qsort_callback failed"
[ "$out" = "1 3 5 7 9" ] || fail "qsort_callback sorted wrong: $out"

# 3. A real shared library.
if build_out=$(printf 'int main(void){return 0;}\n' | "$CC_BIN" -x c -o "$dir/zprobe" - -lz 2>&1); then
    build zlib_crc -lz
    out=$("$dir/zlib_crc") || fail "zlib_crc failed"
    [ "$out" = "crc=3610a686" ] || fail "zlib's crc32 of hello was $out, expected crc=3610a686"
    ldd "$dir/zlib_crc" 2>/dev/null | grep -q 'libz' || fail "zlib_crc is not dynamically linked against libz"
else
    echo "       (zlib is not installed: the shared-library check is skipped)"
fi

# 4. A bounds trap: libc's abort, status 134, stdio not flushed.
build trap
"$dir/trap" > "$dir/trap.out" 2>/dev/null; rc=$?
[ "$rc" -eq 134 ] || fail "the trap exited $rc, expected 134"
[ ! -s "$dir/trap.out" ] || fail "a trap flushed C stdio: $(cat "$dir/trap.out")" 


# 5b. io::exit ends the process even while a C thread is running (exit_group, not exit).
if printf 'int main(void){return 0;}\n' | "$CC_BIN" -x c -pthread -o "$dir/pprobe" - >/dev/null 2>&1; then
    "$ZORIL" --hosted -I stdlib=stdlib --emit-zil -o "$dir/exit_threads.zil" "$src/exit_threads.zrl" > "$dir/et.log" 2>&1 \
        || fail "exit_threads does not compile" "$dir/et.log"
    "$ZILC" "$dir/exit_threads.zil" "$dir/exit_threads.ssa" > "$dir/et2.log" 2>&1 || fail "zilc rejects exit_threads" "$dir/et2.log"
    "$BACKEND_BIN" -o "$dir/exit_threads.s" "$dir/exit_threads.ssa" && "$ASSEMBLER_BIN" -o "$dir/exit_threads.o" "$dir/exit_threads.s" \
        || fail "exit_threads does not assemble"
    "$CC_BIN" -pthread -o "$dir/exit_threads" "$dir/exit_threads.o" "$RTH" "$src/threads.c" > "$dir/et3.log" 2>&1 \
        || fail "exit_threads does not link" "$dir/et3.log"
    t0=$(date +%s)
    "$dir/exit_threads"; rc=$?
    t1=$(date +%s)
    [ "$rc" -eq 3 ] || fail "io::exit(3) with a C thread running exited $rc, expected 3"
    [ $((t1 - t0)) -lt 4 ] || fail "io::exit(3) waited for the C thread ($((t1 - t0)) s)"
fi
# 5. Without --hosted nothing changes: main keeps its name.
"$ZORIL" -I stdlib=stdlib --emit-zil -o "$dir/default.zil" "$src/qsort_callback.zrl" > "$dir/default.log" 2>&1 \
    || fail "the default build of qsort_callback fails" "$dir/default.log"
grep -q ' main(' "$dir/default.zil" || fail "the default build lost main"
if grep -q 'zoril_main' "$dir/default.zil"; then fail "the default build mentions zoril_main"; fi
grep -q ' zoril_main(' "$dir/qsort_callback.zil" || fail "the hosted build does not name its entry zoril_main"


# 6. zbuild --hosted: the same through the build driver, linked with cc and runtime_hosted.o.
ZBUILD=${ZBUILD_BIN:-./build/zbuild}
if [ -x "$ZBUILD" ]; then
    # The driver links the hosted program with `cc` unless it is told which compiler the suite is
    # configured with; the dependency matrix's rows hide `cc` from PATH and pass it in CC.
    "$ZBUILD" --hosted --cc "$CC_BIN" -I stdlib=stdlib --cache-dir "$dir/zcache" --runtime "$RTH" -o "$dir/zb_printf" "$src/printf_getenv.zrl" \
        > "$dir/zb.log" 2>&1 || fail "zbuild --hosted does not build printf_getenv" "$dir/zb.log"
    ZORIL_HOSTED_VAR=zb "$dir/zb_printf" x > "$dir/zb.out"; rc=$?
    [ "$rc" -eq 3 ] || fail "the zbuild --hosted program exited $rc, expected 3"
    grep -q 'args=2 var=zb' "$dir/zb.out" || fail "the zbuild --hosted program printed the wrong text" "$dir/zb.out"
fi
echo "[PASS] hosted: printf/getenv/argc/exit flush, a qsort callback, zlib, a trap that exits 134 unflushed, and an unchanged default build"
