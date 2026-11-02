#!/bin/sh
# scripts/test_zbuild_errors.sh — the diagnostics tests/error_reporting/ expects, through an installed zbuild.
#
# The runner builds every `// expected compile fail` test with the whole-program compiler. A user who
# builds with zbuild reads the diagnostics of separate compilation, which lost a note in A0's measurement
# (a private method reported as "no field", a duplicate method accepted). This stages the toolchain
# (`make install DESTDIR=build/zbuild-errors/stage PREFIX=/usr`) and builds each such test with the staged
# zbuild from the repository root (relative paths, as the runner does, with the runner's include roots):
# it must fail and print every `// EXPECT:` line. A test whose zbuild result differs for a documented
# reason is listed in tests/zbuild_errors_allow.list as `<path> <reason> (KNOWN_ISSUES.md <entry>)`; an
# entry that now matches fails the gate. Tests that need compiler flags zbuild has no option for
# (`// flags:`) and the CLI tests are skipped, counted, and named in the log.
cd "$(dirname "$0")/.." || exit 2
. scripts/env.sh
. scripts/lib/portability.sh
ALLOW=tests/zbuild_errors_allow.list
WORK=build/zbuild-errors
STAGE="$WORK/stage"
JOBS=$(nproc_count 2>/dev/null || echo 4)
fail() { echo "[FAIL] zbuild-errors: $1"; [ -n "${2:-}" ] && sed 's/^/       /' "$2"; exit 1; }

start=$(date +%s)
rm -rf "$WORK"
mkdir -p "$WORK"
make install-files DESTDIR="$(pwd)/$STAGE" PREFIX=/usr > "$WORK/install.log" 2>&1 || fail "make install into the stage failed" "$WORK/install.log"
BIN="$(pwd)/$STAGE/usr/bin"
[ -x "$BIN/zbuild" ] || fail "the staged install lacks zbuild"
find tests/error_reporting -maxdepth 1 -type f -name '*.zrl' ! -name '.*' | sort > "$WORK/candidates.txt"

cat > "$WORK/worker.sh" << 'EOF'
#!/bin/sh
. scripts/lib/portability.sh
# worker.sh WORK BIN FILE... -> "OK|DIFF|SKIP <file> <why>" for each `expected compile fail` test
WORK="$1"; BIN="$2"; shift 2
INC="-I src -I tools/zilc/src -I tests -I tests/include -I tests/helpers"
for f in "$@"; do
    grep -q 'expected compile fail' "$f" || continue
    grep -q '^[ 	]*//[ 	]*@skip:' "$f" && continue
    flags=$(sed -n 's|^// flags: ||p' "$f" | head -n 1)
    if [ -n "$flags" ]; then echo "SKIP $f flags $flags"; continue; fi
    d="$WORK/p/$(basename "$f" .zrl)"
    mkdir -p "$d"
    if run_with_timeout -k 2s 60s "$BIN/zbuild" $INC -I "$(dirname "$f")" --cache-dir "$d/cache" -o "$d/bin" "$f" > "$d/log" 2>&1 < /dev/null; then
        echo "DIFF $f zbuild accepted it"
        continue
    fi
    missing=""
    while IFS= read -r want; do
        grep -Fq -- "$want" "$d/log" || { missing="$want"; break; }
    done << EXPECTS
$(sed -n 's|^// EXPECT: *||p' "$f")
EXPECTS
    if [ -n "$missing" ]; then echo "DIFF $f zbuild did not print: $missing"; else echo "OK $f"; fi
done
EOF
chmod +x "$WORK/worker.sh"
xargs -P "$JOBS" -n 8 "$WORK/worker.sh" "$(pwd)/$WORK" "$BIN" < "$WORK/candidates.txt" | sort > "$WORK/results.txt"

total=$(grep -c . "$WORK/results.txt"); ok=$(grep -c '^OK ' "$WORK/results.txt"); skipped=$(grep -c '^SKIP ' "$WORK/results.txt")
grep '^DIFF ' "$WORK/results.txt" | awk '{print $2}' | sort > "$WORK/diff_names.txt"
touch "$ALLOW"
grep -v '^[[:space:]]*#' "$ALLOW" | awk 'NF {print $1}' | sort > "$WORK/allowed_names.txt"
comm -23 "$WORK/diff_names.txt" "$WORK/allowed_names.txt" > "$WORK/unexpected.txt"
comm -13 "$WORK/diff_names.txt" "$WORK/allowed_names.txt" > "$WORK/stale.txt"
if [ -s "$WORK/unexpected.txt" ]; then
    echo "[FAIL] zbuild-errors: $(grep -c . "$WORK/unexpected.txt") test(s) give another diagnostic through zbuild:"
    while read -r p; do grep "^DIFF $p " "$WORK/results.txt" | head -n 1 | sed 's/^/       /'; done < "$WORK/unexpected.txt" | head -n 15
    exit 1
fi
if [ -s "$WORK/stale.txt" ]; then
    echo "[FAIL] zbuild-errors: $(grep -c . "$WORK/stale.txt") allowed test(s) now match; remove them from $ALLOW:"
    sed 's/^/       /' "$WORK/stale.txt" | head -n 15
    exit 1
fi
echo "[PASS] zbuild-errors: $ok of $total compile-fail tests give their expected diagnostics through the installed zbuild ($skipped skipped for compiler flags, $(grep -c . "$WORK/allowed_names.txt") allowed to differ) in $(( $(date +%s) - start )) s"
