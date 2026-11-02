#!/bin/sh
# scripts/check_fmt.sh — formatter test and repository format check (a make test gate).
#
# Formats tests/fmt/layout.zrl and requires it to match tests/fmt/layout.expected.zrl,
# tests idempotency, and verifies with `zoril fmt --check` that src/, stdlib/ and
# tools/ are fully formatted.

cd "$(dirname "$0")/.." || exit 2
. scripts/lib/portability.sh 2>/dev/null || true
ZORIL=${ZORIL_CC:-./build/zoril}
OUT=${FMT_CHECK_OUT:-build/fmt_check}
mkdir -p "$OUT"
status=0

# 1. Test layout rules: format tests/fmt/layout.zrl and compare to layout.expected.zrl
cp tests/fmt/layout.zrl "$OUT/layout.zrl"
"$ZORIL" fmt "$OUT/layout.zrl" > "$OUT/layout.log" 2>&1
if cmp -s "$OUT/layout.zrl" tests/fmt/layout.expected.zrl; then
    echo "[PASS] fmt: layout rules match expected"
else
    echo "[FAIL] fmt: layout.zrl does not match layout.expected.zrl"
    diff -u tests/fmt/layout.expected.zrl "$OUT/layout.zrl" | head -n 30 | sed 's/^/       /'
    status=1
fi

# 2. Idempotency test: formatting layout.expected.zrl produces identical output
cp tests/fmt/layout.expected.zrl "$OUT/idempotent.zrl"
"$ZORIL" fmt "$OUT/idempotent.zrl" > "$OUT/idempotent.log" 2>&1
if cmp -s "$OUT/idempotent.zrl" tests/fmt/layout.expected.zrl; then
    echo "[PASS] fmt: layout idempotency"
else
    echo "[FAIL] fmt: layout.expected.zrl is not idempotent"
    status=1
fi

# 3. Test --check exit codes
check_out=$("$ZORIL" fmt --check tests/fmt/layout.expected.zrl 2>&1)
check_rc=$?
if [ $check_rc -eq 0 ] && [ -z "$check_out" ]; then
    echo "[PASS] fmt: --check exits 0 on formatted file"
else
    echo "[FAIL] fmt: --check failed on formatted file (rc=$check_rc, out=$check_out)"
    status=1
fi

check_out=$("$ZORIL" fmt --check tests/fmt/layout.zrl 2>&1)
check_rc=$?
if [ $check_rc -eq 1 ] && [ "$check_out" = "tests/fmt/layout.zrl" ]; then
    echo "[PASS] fmt: --check exits 1 on unformatted file"
else
    echo "[FAIL] fmt: --check failed on unformatted file (rc=$check_rc, out=$check_out)"
    status=1
fi

# 4. Test empty file handling
touch "$OUT/empty.zrl"
"$ZORIL" fmt "$OUT/empty.zrl" > "$OUT/empty.log" 2>&1
fmt_rc=$?
if [ $fmt_rc -eq 0 ] && [ ! -s "$OUT/empty.zrl" ]; then
    echo "[PASS] fmt: empty file formats to empty file"
else
    echo "[FAIL] fmt: formatting empty file failed (rc=$fmt_rc)"
    status=1
fi

check_out=$("$ZORIL" fmt --check "$OUT/empty.zrl" 2>&1)
check_rc=$?
if [ $check_rc -eq 0 ] && [ -z "$check_out" ]; then
    echo "[PASS] fmt: --check on empty file exits 0"
else
    echo "[FAIL] fmt: --check on empty file failed (rc=$check_rc, out=$check_out)"
    status=1
fi

# 5. Test syntax error / unparseable file
printf 'fn broken( {\n' > "$OUT/syntax_error.zrl"
printf 'fn broken( {\n' > "$OUT/syntax_error.orig.zrl"
"$ZORIL" fmt "$OUT/syntax_error.zrl" > "$OUT/syntax_error.log" 2>&1
fmt_rc=$?
if [ $fmt_rc -eq 1 ] && cmp -s "$OUT/syntax_error.zrl" "$OUT/syntax_error.orig.zrl"; then
    echo "[PASS] fmt: syntax error exits 1 and leaves file intact"
else
    echo "[FAIL] fmt: syntax error handling failed (rc=$fmt_rc)"
    status=1
fi

check_out=$("$ZORIL" fmt --check "$OUT/syntax_error.zrl" > "$OUT/syntax_check.log" 2>&1)
check_rc=$?
if [ $check_rc -eq 1 ]; then
    echo "[PASS] fmt: --check on syntax error exits 1"
else
    echo "[FAIL] fmt: --check on syntax error failed (rc=$check_rc)"
    status=1
fi

# 6. Test CLI usage errors
"$ZORIL" fmt --invalid-opt > /dev/null 2>&1
if [ $? -eq 2 ]; then
    echo "[PASS] fmt: unknown option exits 2"
else
    echo "[FAIL] fmt: unknown option did not exit 2"
    status=1
fi

"$ZORIL" fmt > /dev/null 2>&1
if [ $? -eq 2 ]; then
    echo "[PASS] fmt: missing arguments exits 2"
else
    echo "[FAIL] fmt: missing arguments did not exit 2"
    status=1
fi

# 7. Test permissions and symlink preservation
printf 'fn foo() -> i32 {  return 42; }\n' > "$OUT/perm.zrl"
chmod 755 "$OUT/perm.zrl"
"$ZORIL" fmt "$OUT/perm.zrl" > /dev/null 2>&1
perm=$(file_perm "$OUT/perm.zrl")
if [ "$perm" = "755" ] && grep -q 'return 42;' "$OUT/perm.zrl" && ! grep -q '  return' "$OUT/perm.zrl"; then
    echo "[PASS] fmt: file permissions preserved (755)"
else
    echo "[FAIL] fmt: file permissions not preserved (got $perm, expected 755)"
    status=1
fi

printf 'fn bar() -> i32 {  return 1; }\n' > "$OUT/sym_target.zrl"
ln -sf sym_target.zrl "$OUT/sym_link.zrl"
"$ZORIL" fmt "$OUT/sym_link.zrl" > /dev/null 2>&1
if [ -L "$OUT/sym_link.zrl" ] && grep -q 'return 1;' "$OUT/sym_target.zrl" && ! grep -q '  return' "$OUT/sym_target.zrl"; then
    echo "[PASS] fmt: symlink preserved and target formatted"
else
    echo "[FAIL] fmt: symlink replaced or target not formatted"
    status=1
fi

# 8. Check repository files: src/, stdlib/, tools/
files=$(find src stdlib tools -type f -name '*.zrl' | sort)
unformatted=$("$ZORIL" fmt --check $files 2>&1)
if [ $? -eq 0 ] && [ -z "$unformatted" ]; then
    echo "[PASS] fmt: src/, stdlib/, tools/ are formatted"
else
    echo "[FAIL] fmt: unformatted files found:"
    echo "$unformatted" | head -n 30 | sed 's/^/       /'
    status=1
fi

exit $status



