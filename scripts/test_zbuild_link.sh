#!/bin/sh
# scripts/test_zbuild_link.sh — zbuild links C objects, libraries and linker arguments.
#
# tests/zbuild_link/include/main.zrl calls c_add, defined in cadd.c. The test builds it with
#   --link-object FILE      an object file
#   -L DIR -l NAME          a static library found by the linker
#   --link-arg ARG          an argument passed to ld as it is
# and checks that changing a link input relinks without recompiling any module, and that a
# missing object is a clear error and no program.
cd "$(dirname "$0")/.." || exit 2
. scripts/env.sh
ZBUILD=${ZBUILD_BIN:-./build/zbuild}
CC_BIN=${CC:-cc}
AR_BIN=${AR:-ar}
command -v "$CC_BIN" >/dev/null 2>&1 || { echo "[SKIP] zbuild-link: no C compiler ($CC_BIN)"; exit 0; }
dir=build/zbuild-link
rm -rf "$dir"
mkdir -p "$dir"
src=tests/zbuild_link/include
fail() { echo "[FAIL] zbuild-link: $1"; [ -n "$2" ] && sed 's/^/       /' "$2"; exit 1; }

CFLAGS_NO_LIBC=$(cc_no_libc_flags "$CC_BIN" "$dir")
"$CC_BIN" $CFLAGS_NO_LIBC -c -o "$dir/cadd.o" "$src/cadd.c" || fail "cadd.c does not compile"
zb() { "$ZBUILD" -I stdlib=stdlib --cache-dir "$dir/cache" "$@"; }

# 1. An object file.
zb -o "$dir/with_object" --link-object "$dir/cadd.o" "$src/main.zrl" > "$dir/o.log" 2>&1 \
    || fail "--link-object build failed" "$dir/o.log"
"$dir/with_object"; rc=$?
[ "$rc" -eq 0 ] || fail "the program linked with --link-object exited $rc, expected 0"

# 2. A library found with -L and -l (both spellings).
if command -v "$AR_BIN" >/dev/null 2>&1; then
    mkdir -p "$dir/lib"
    "$AR_BIN" rcs "$dir/lib/libcadd.a" "$dir/cadd.o" || fail "ar failed"
    zb -o "$dir/with_lib" -L "$dir/lib" -l cadd "$src/main.zrl" > "$dir/l.log" 2>&1 \
        || fail "-L/-l build failed" "$dir/l.log"
    "$dir/with_lib"; rc=$?
    [ "$rc" -eq 0 ] || fail "the program linked with -L/-l exited $rc, expected 0"
    zb -o "$dir/with_lib2" -L"$dir/lib" -lcadd "$src/main.zrl" > "$dir/l2.log" 2>&1 \
        || fail "-L<dir>/-l<name> build failed" "$dir/l2.log"
    "$dir/with_lib2" || fail "the -L<dir>/-l<name> program failed"
else
    echo "[SKIP] zbuild-link: no ar ($AR_BIN); -L/-l not checked"
fi

# 3. A linker argument reaches ld, and changing it relinks with no module rebuilt.
zb -v -o "$dir/arg1" --link-object "$dir/cadd.o" --link-arg "-Map=$dir/one.map" "$src/main.zrl" > "$dir/a1.log" 2>&1 \
    || fail "--link-arg build failed" "$dir/a1.log"
[ -s "$dir/one.map" ] || fail "--link-arg -Map=... did not reach the linker (no map file)"
zb -v -o "$dir/arg2" --link-object "$dir/cadd.o" --link-arg "-Map=$dir/two.map" "$src/main.zrl" > "$dir/a2.log" 2>&1 \
    || fail "second --link-arg build failed" "$dir/a2.log"
[ -s "$dir/two.map" ] || fail "changing --link-arg did not relink (no second map file)"
grep -q 'compiled: [1-9]' "$dir/o.log" || fail "the first build compiled nothing, so the relink check proves nothing" "$dir/o.log"
grep -q 'compiled: 0 modules' "$dir/a2.log" || fail "changing --link-arg rebuilt a module: it must only relink" "$dir/a2.log"

# 4. A missing object file is a clear error, and no program is left behind.
rm -f "$dir/none"
if zb -o "$dir/none" --link-object "$dir/does_not_exist.o" "$src/main.zrl" > "$dir/m.log" 2>&1; then
    fail "a missing --link-object was accepted" "$dir/m.log"
fi
grep -q 'does_not_exist.o' "$dir/m.log" || fail "the error does not name the missing object" "$dir/m.log"
[ ! -e "$dir/none" ] || fail "a program was left behind after a link input was missing"

# 5. A QBE older than 1.3 is refused up front, in words, before anything is compiled with it.
printf '#!/bin/sh\necho "qbe:probe:1: identifier too long" >&2\nexit 1\n' > "$dir/old_qbe"
chmod +x "$dir/old_qbe"
if "$ZBUILD" -I stdlib=stdlib --cache-dir "$dir/cache_old_qbe" --qbe "$dir/old_qbe" -o "$dir/old_qbe_prog" "$src/main.zrl" --link-object "$dir/cadd.o" > "$dir/q.log" 2>&1; then
    fail "an old QBE was accepted" "$dir/q.log"
fi
grep -q 'QBE 1.3 or newer is required' "$dir/q.log" || fail "the refusal of an old QBE does not say which version is needed" "$dir/q.log"
[ ! -e "$dir/old_qbe_prog" ] || fail "a program was built with an old QBE"

# A QBE that fails for another reason is not called "too old"; its own words are shown.
printf '#!/bin/sh\necho "exec format error" >&2\nexit 126\n' > "$dir/broken_qbe"
chmod +x "$dir/broken_qbe"
if "$ZBUILD" -I stdlib=stdlib --cache-dir "$dir/cache_broken_qbe" --qbe "$dir/broken_qbe" -o "$dir/broken_qbe_prog" "$src/main.zrl" --link-object "$dir/cadd.o" > "$dir/b.log" 2>&1; then
    fail "a broken QBE was accepted" "$dir/b.log"
fi
grep -q 'exec format error' "$dir/b.log" || fail "the refusal of a broken QBE does not show what it printed" "$dir/b.log"
if grep -q 'too old' "$dir/b.log"; then fail "a broken QBE was called too old" "$dir/b.log"; fi

# The probe's answer is kept under the QBE's hash: a second build with the same QBE does not ask again.
real_qbe=$(command -v "${BACKEND_BIN:-qbe}")
printf '#!/bin/sh\necho x >> "%s/qbe_calls"\nexec "%s" "$@"\n' "$dir" "$real_qbe" > "$dir/counting_qbe"
chmod +x "$dir/counting_qbe"
zb --qbe "$dir/counting_qbe" -o "$dir/counted1" --link-object "$dir/cadd.o" "$src/main.zrl" > "$dir/c1.log" 2>&1 || fail "the first build with a counting QBE failed" "$dir/c1.log"
first=$(wc -l < "$dir/qbe_calls")
zb --qbe "$dir/counting_qbe" -o "$dir/counted2" --link-object "$dir/cadd.o" "$src/main.zrl" > "$dir/c2.log" 2>&1 || fail "the second build with a counting QBE failed" "$dir/c2.log"
second=$(wc -l < "$dir/qbe_calls")
[ "$first" -gt 0 ] || fail "the counting QBE was never called"
[ "$second" -eq "$first" ] || fail "an unchanged build called QBE $((second - first)) more time(s): the probe ran again"

echo "[PASS] zbuild-link: objects, libraries (-L/-l) and --link-arg link; a changed link input only relinks; a missing object is an error; a QBE older than 1.3 is refused, another failure is shown as it is, and the probe runs once per QBE"
