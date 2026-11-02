#!/bin/sh
# scripts/test_ffi_callback.sh — C calls back into Zoril through `extern "C" fn(..)` pointers.
#
# tests/ffi_callback/include/cb.zrl passes Zoril functions to a C library (callbacks.c, no libc)
# as callback pointers with userdata, as a struct of callbacks, and re-entrantly (Zoril -> C ->
# Zoril -> C -> Zoril). The program exits 0 when every callback ran and saw its userdata.
cd "$(dirname "$0")/.." || exit 2
. scripts/env.sh
ZORIL=${ZORIL_BIN:-./build/zoril}
ZILC=${ZILC_BIN:-./build/zilc}
RT=${RUNTIME_BIN:-./build/runtime.o}
CC_BIN=${CC:-cc}
for tool in "$BACKEND_BIN" "$ASSEMBLER_BIN" "$LINKER_BIN" "$CC_BIN"; do
    command -v "$tool" >/dev/null 2>&1 || { echo "[SKIP] ffi-callback: $tool is not on PATH"; exit 0; }
done
dir=build/ffi-callback
rm -rf "$dir"
mkdir -p "$dir"
src=tests/ffi_callback/include
fail() { echo "[FAIL] ffi-callback: $1"; [ -n "$2" ] && sed 's/^/       /' "$2"; exit 1; }

"$ZORIL" -I stdlib=stdlib --emit-zil -o "$dir/cb.zil" "$src/cb.zrl" > "$dir/zoril.log" 2>&1 \
    || fail "the Zoril program does not compile" "$dir/zoril.log"
"$ZILC" "$dir/cb.zil" "$dir/cb.ssa" > "$dir/zilc.log" 2>&1 || fail "zilc rejects the program" "$dir/zilc.log"
"$BACKEND_BIN" -o "$dir/cb.s" "$dir/cb.ssa" && "$ASSEMBLER_BIN" -o "$dir/cb.o" "$dir/cb.s" \
    || fail "the program does not assemble"
CFLAGS_NO_LIBC=$(cc_no_libc_flags "$CC_BIN" "$dir")
# The dirty-return helpers are written with the GNU __asm__ extension: no portable C returns with
# garbage in the upper bits of a return register, which is the ABI behaviour this test is about
# ("a caller must extend them itself"). A compiler without the extension (cproc, the minimal-stack
# compiler) cannot express the test, so it is skipped with that reason rather than failed.
printf '__asm__(".globl zoril_asm_probe\\nzoril_asm_probe:\\n  ret\\n");\n' > "$dir/asm-probe.c"
"$CC_BIN" -c -o "$dir/asm-probe.o" "$dir/asm-probe.c" >/dev/null 2>&1 \
    || { echo "[SKIP] ffi-callback: $CC_BIN has no __asm__ extension, and the dirty return registers are defined with it"; exit 0; }
"$CC_BIN" $CFLAGS_NO_LIBC -c -o "$dir/callbacks.o" "$src/callbacks.c" \
    || fail "callbacks.c does not compile"
"$LINKER_BIN" -o "$dir/run" "$RT" "$dir/cb.o" "$dir/callbacks.o" || fail "link failed"
"$dir/run"; rc=$?
[ "$rc" -eq 0 ] || fail "the program exited $rc (see tests/ffi_callback/include/cb.zrl for the check behind that status)"
echo "[PASS] ffi-callback: a callback with userdata, a struct of callbacks and a re-entrant call all ran"
