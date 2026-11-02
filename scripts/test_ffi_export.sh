#!/bin/sh
# scripts/test_ffi_export.sh — Zoril functions that C can call (`extern "C" fn name() { body }`).
#
# tests/ffi_export/include/lib.zrl defines exported functions (one in an imported module) and has
# no main. A C main (main.c, no libc) calls them: linked with the runtime's _start, the process
# exits 0 when every result is right and 134 when an exported function traps. It also checks
# that a -c (separate compilation) build of the module defines the same unmangled symbols.
cd "$(dirname "$0")/.." || exit 2
. scripts/env.sh
ZORIL=${ZORIL_BIN:-./build/zoril}
ZILC=${ZILC_BIN:-./build/zilc}
RT=${RUNTIME_BIN:-./build/runtime.o}
CC_BIN=${CC:-cc}
for tool in "$BACKEND_BIN" "$ASSEMBLER_BIN" "$LINKER_BIN" nm "$CC_BIN"; do
    command -v "$tool" >/dev/null 2>&1 || { echo "[SKIP] ffi-export: $tool is not on PATH"; exit 0; }
done
dir=build/ffi-export
rm -rf "$dir"
mkdir -p "$dir"
src=tests/ffi_export/include

fail() { echo "[FAIL] ffi-export: $1"; [ -n "$2" ] && sed 's/^/       /' "$2"; exit 1; }

"$ZORIL" -I stdlib=stdlib -I "$src" --emit-zil -o "$dir/lib.zil" "$src/lib.zrl" > "$dir/zoril.log" 2>&1 \
    || fail "the Zoril library does not compile" "$dir/zoril.log"
"$ZILC" "$dir/lib.zil" "$dir/lib.ssa" > "$dir/zilc.log" 2>&1 || fail "zilc rejects the library" "$dir/zilc.log"
# The variadic marker separates the named arguments from the variadic ones. After the last
# argument QBE cannot tell the call is variadic and would not set the SysV %al count, so the
# position is part of the contract (not just the presence of `...`).
grep -q 'call \$c_sum_doubles(w %v[0-9]*, \.\.\., d %v' "$dir/lib.ssa" \
    || fail "the variadic marker is not before c_sum_doubles' variadic argument" "$dir/lib.ssa"
grep -q 'call \$c_sum_ints(w %v[0-9]*, \.\.\., w %v' "$dir/lib.ssa" \
    || fail "the variadic marker is not before c_sum_ints' variadic arguments" "$dir/lib.ssa"
"$BACKEND_BIN" -o "$dir/lib.s" "$dir/lib.ssa" && "$ASSEMBLER_BIN" -o "$dir/lib.o" "$dir/lib.s" || fail "the library does not assemble"

for sym in zoril_add zoril_twice zoril_index zoril_from_module zoril_helper_mul f0 f1 f2 f3 f4 f5; do
    nm "$dir/lib.o" | grep -q " T $sym\$" || fail "the symbol $sym is not exported unmangled" /dev/null
done

# The C objects link into the freestanding runtime, so GCC/clang need their hardening defaults
# switched off; cproc accepts none of these flags and needs none, so the set is probed rather than
# assumed (a compiler that rejects it compiles the same source without it).
CFLAGS_NO_LIBC=$(cc_no_libc_flags "$CC_BIN" "$dir")
"$CC_BIN" $CFLAGS_NO_LIBC -c -o "$dir/main.o" "$src/main.c" || fail "main.c does not compile"
"$CC_BIN" $CFLAGS_NO_LIBC -DTRAP -c -o "$dir/main_trap.o" "$src/main.c" || fail "main.c (trap) does not compile"
"$LINKER_BIN" -o "$dir/run" "$RT" "$dir/lib.o" "$dir/main.o" || fail "link failed"
"$LINKER_BIN" -o "$dir/run_trap" "$RT" "$dir/lib.o" "$dir/main_trap.o" || fail "link failed (trap)"

"$dir/run"; rc=$?
[ "$rc" -eq 0 ] || fail "the C main saw a wrong result (exit $rc)"
"$dir/run_trap"; rc=$?
[ "$rc" -eq 134 ] || fail "an exported function that traps exited $rc, expected 134"

# Separate compilation defines the same symbol.
"$ZORIL" -I stdlib=stdlib -I "$src" -c --emit-zil -o "$dir/lib_c.zil" "$src/lib.zrl" > "$dir/zoril_c.log" 2>&1 \
    || fail "-c does not compile the library" "$dir/zoril_c.log"
"$ZILC" "$dir/lib_c.zil" "$dir/lib_c.ssa" > "$dir/zilc_c.log" 2>&1 || fail "zilc rejects the -c output" "$dir/zilc_c.log"
"$BACKEND_BIN" -o "$dir/lib_c.s" "$dir/lib_c.ssa" && "$ASSEMBLER_BIN" -o "$dir/lib_c.o" "$dir/lib_c.s" || fail "the -c output does not assemble"
nm "$dir/lib_c.o" | grep -q " T zoril_add\$" || fail "-c does not define zoril_add unmangled"

# An importer built separately (zbuild reads the module's interface) calls it without unsafe.
ZBUILD=${ZBUILD_BIN:-./build/zbuild}
if [ -x "$ZBUILD" ]; then
    "$ZBUILD" -I stdlib=stdlib -o "$dir/project_run" tests/ffi_export/include/project/main.zrl > "$dir/zbuild.log" 2>&1 \
        || fail "zbuild rejects the importer of an exported function" "$dir/zbuild.log"
    "$dir/project_run"; rc=$?
    [ "$rc" -eq 42 ] || fail "the separately built importer exited $rc, expected 42"
fi

echo "[PASS] ffi-export: C calls the Zoril exports (one from an imported module, variadic arguments promoted), a trap exits 134, -c defines the same symbols, a separate build calls one safely"
