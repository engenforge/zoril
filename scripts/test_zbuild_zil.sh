#!/bin/sh
# scripts/test_zbuild_zil.sh — zbuild builds .zil roots, honours -o and --cache-dir, and
# refuses non-.zrl/.zil inputs and --checked on .zil inputs.
set -eu
cd "$(dirname "$0")/.." || exit 2
ZBUILD=${ZBUILD_BIN:-./build/zbuild}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

passed=0
total=0
for f in corpus/zil/*.zil; do
    total=$((total + 1))
    want=$(sed -n 's|^// expected exit code: ||p' "$f" | head -n 1)
    [ -n "$want" ] || { echo "[FAIL] $f: missing expected exit header"; exit 1; }
    out_bin="$WORK/prog"
    if ! "$ZBUILD" "$f" --cache-dir "$WORK/cache" -o "$out_bin" > "$WORK/build.log" 2>&1; then
        echo "[FAIL] zbuild failed on $f"
        cat "$WORK/build.log"
        exit 1
    fi
    set +e
    "$out_bin" > "$WORK/run.out" 2>&1
    rc=$?
    set -e
    if [ "$rc" -ne "$want" ]; then
        echo "[FAIL] $f: expected exit $want, got $rc"
        exit 1
    fi
    if [ -f "${f}.stdout" ] && ! diff -u "${f}.stdout" "$WORK/run.out"; then
        echo "[FAIL] $f: stdout mismatch"
        exit 1
    fi
    passed=$((passed + 1))
done
echo "[PASS] corpus/zil via zbuild: $passed/$total passed"

# C3: -o path and cache reuse on second build
"$ZBUILD" corpus/zil/01_arithmetic.zil --cache-dir "$WORK/cache2" -o "$WORK/custom_out" > "$WORK/b1.log" 2>&1
[ -x "$WORK/custom_out" ] || { echo "[FAIL] -o path not created"; exit 1; }
[ -f "$WORK/cache2/manifest.tsv" ] || { echo "[FAIL] cache manifest.tsv not created"; exit 1; }
b2_out=$("$ZBUILD" corpus/zil/01_arithmetic.zil --cache-dir "$WORK/cache2" -o "$WORK/custom_out" 2>&1)
printf '%s\n' "$b2_out" | grep -Fq "compiled: 0 modules" || {
    echo "[FAIL] second build did not reuse cache: $b2_out"
    exit 1
}
echo "[PASS] -o and cache reuse (compiled: 0 modules)"

# C4: non-.zrl/.zil root and --checked with .zil root
set +e
bad_ext=$("$ZBUILD" foo.txt 2>&1); bad_rc=$?
chk_zil=$("$ZBUILD" --checked x.zil 2>&1); chk_rc=$?
set -e
[ "$bad_rc" -ne 0 ] || { echo "[FAIL] foo.txt did not fail"; exit 1; }
printf '%s\n' "$bad_ext" | grep -Fq ".zrl" && printf '%s\n' "$bad_ext" | grep -Fq ".zil" || {
    echo "[FAIL] foo.txt error did not name both .zrl and .zil: $bad_ext"
    exit 1
}
[ "$chk_rc" -ne 0 ] || { echo "[FAIL] --checked x.zil did not fail"; exit 1; }
[ "$(printf '%s\n' "$chk_zil" | wc -l)" -eq 1 ] || {
    echo "[FAIL] --checked x.zil did not print one line: $chk_zil"
    exit 1
}
echo "[PASS] refusals: foo.txt and --checked x.zil"
