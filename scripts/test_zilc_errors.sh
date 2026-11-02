#!/bin/sh
# scripts/test_zilc_errors.sh — zilc rejects bad ZIL with the expected message.
# Each tests/zilc/*.zil names the message it must produce on a `// EXPECT:` line; zilc must
# exit non-zero and print it.
cd "$(dirname "$0")/.." || exit 2
ZILC=${ZILC_BIN:-./build/zilc}
errors=0
for f in tests/zilc/*.zil; do
    want=$(sed -n 's|^// EXPECT: ||p' "$f" | head -n 1)
    out=$("$ZILC" "$f" /tmp/zilc_errors.$$.ssa 2>&1); rc=$?
    if [ $rc -ne 0 ] && printf '%s\n' "$out" | grep -Fq -- "$want"; then
        echo "[PASS] $f"
    else
        echo "[FAIL] $f: expected a failure with: $want"
        printf '%s\n' "$out" | head -n 3 | sed 's/^/       /'
        errors=$((errors + 1))
    fi
done
# CLI argument tests
# 1. Output flag -o
out=$("$ZILC" -o /tmp/zilc_errors.$$.ssa tools/zilc/test/01_doc_header.zil 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -s /tmp/zilc_errors.$$.ssa ]; then
    echo "[PASS] zilc -o flag"
else
    echo "[FAIL] zilc -o flag failed"
    errors=$((errors + 1))
fi

# 2. Missing argument to -o
out=$("$ZILC" -o 2>&1); rc=$?
if [ $rc -ne 0 ] && printf '%s\n' "$out" | grep -Fq "missing argument to -o"; then
    echo "[PASS] zilc -o missing argument"
else
    echo "[FAIL] zilc -o missing argument did not report error"
    errors=$((errors + 1))
fi

# 3. Unrecognized flag
out=$("$ZILC" --unknown-flag-xyz 2>&1); rc=$?
if [ $rc -ne 0 ] && printf '%s\n' "$out" | grep -Fq "unrecognized flag"; then
    echo "[PASS] zilc unrecognized flag rejection"
else
    echo "[FAIL] zilc unrecognized flag was not rejected"
    errors=$((errors + 1))
fi

# 4. Help output
out=$("$ZILC" --help 2>&1); rc=$?
if [ $rc -eq 0 ] && printf '%s\n' "$out" | grep -Fq "usage: zilc"; then
    echo "[PASS] zilc --help flag"
else
    echo "[FAIL] zilc --help failed"
    errors=$((errors + 1))
fi

rm -f /tmp/zilc_errors.$$.ssa
[ $errors -eq 0 ]
