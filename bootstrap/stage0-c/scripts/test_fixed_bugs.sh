#!/bin/sh
# Regression gate for fixed stage0-C bugs: every .zrl (Zoril) and .zil (IL, compiled with --il)
# file in tests/fixed_bugs/ must behave as its header says under the release compiler. Headers:
#   // expected exit N         compile, run, and require exit code N
#   // expected compile fail   require a compile error; a following "// EXPECT: msg" line
#                              must appear in the diagnostics
# Add a test here whenever a stage0-C bug is fixed. The broader functional suite has
# long-standing failures, so it cannot serve as this gate.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZORIL_BIN="${ZORIL_BIN:-$REPO_ROOT/build/zoril-c.release}"
if [ -d "$REPO_ROOT/../../stdlib" ]; then
    TOP_DIR="$(cd "$REPO_ROOT/../.." && pwd)"
else
    TOP_DIR="$(cd "$REPO_ROOT/.." && pwd)"
fi
STDLIB_DIR="${ZORIL_STDLIB_DIR:-$TOP_DIR/stdlib}"
. "$REPO_ROOT/scripts/outside_dialect.sh"
WORK="$REPO_ROOT/build/fixed_bugs"
mkdir -p "$WORK"

[ -x "$ZORIL_BIN" ] || { echo "Error: $ZORIL_BIN not found. Run 'make release' first." >&2; exit 1; }

total=0
failed=0
TIMEOUT_FOREGROUND="${TIMEOUT_FOREGROUND:-$(command -v timeout >/dev/null 2>&1 && timeout --foreground 0 true 2>/dev/null && echo --foreground || true)}"
run_timed() {
    if command -v timeout >/dev/null 2>&1; then
        timeout $TIMEOUT_FOREGROUND "$@"
    else
        while [ $# -gt 0 ]; do
            case "$1" in
                -k) shift 2 ;;
                [0-9]*s|[0-9]*) shift; break ;;
                *) break ;;
            esac
        done
        "$@"
    fi
}
for f in "$REPO_ROOT"/tests/fixed_bugs/*.zrl "$REPO_ROOT"/tests/fixed_bugs/*.zil; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    # A fixed-bug regression test blocked by a known stage0-C bug (not a quick fix) is
    # reported as [SKIP], like the other stage0-C suites, so a skip is something to act on.
    reason=$(known_bug_reason "$f")
    if [ -n "$reason" ]; then
        total=$((total + 1))
        [ "${QUIET:-0}" -eq 1 ] || echo "[SKIP] $name (known stage0-C $reason)"
        continue
    fi
    il_flag=""
    case "$f" in *.zil) il_flag="--il" ;; esac
    total=$((total + 1))
    bin="$WORK/$name"
    # `// repeat N` compiles (and runs) the test N times, requiring the same outcome each time:
    # a bug that a lowering order decided (a declaration reached on demand in one run, by its own
    # module's pass in another) does not fail on every single run.
    repeat=$(sed -n 's|^// repeat \([0-9][0-9]*\)$|\1|p' "$f" | head -n 1)
    [ -n "$repeat" ] || repeat=1
    is_compile_fail=0
    grep -q '^// expected compile fail' "$f" && is_compile_fail=1
    expect=$(sed -n 's|^// EXPECT: ||p' "$f" | head -n 1)
    expected=$(sed -n 's|^// expected exit \([0-9][0-9]*\)$|\1|p' "$f" | head -n 1)
    if [ "$is_compile_fail" -eq 0 ] && [ -z "$expected" ]; then
        echo "[FAIL] $name (no '// expected exit N' or '// expected compile fail' header)"
        failed=$((failed + 1))
        continue
    fi
    bad=""
    iteration=1
    while [ "$iteration" -le "$repeat" ]; do
        run_timed -k 2s 30s "$ZORIL_BIN" $il_flag -I "$STDLIB_DIR" "$f" -o "$bin" > "$WORK/$name.log" 2>&1
        compile_res=$?
        if [ "$is_compile_fail" -eq 1 ]; then
            if [ "$compile_res" -eq 0 ]; then
                bad="expected compile fail, but it compiled"
            elif [ -n "$expect" ] && ! grep -qF -- "$expect" "$WORK/$name.log"; then
                bad="compile failed without: $expect"
            fi
        elif [ "$compile_res" -ne 0 ]; then
            bad="compilation failed (see $WORK/$name.log)"
        else
            run_timed -k 2s 10s "$bin" > /dev/null 2>&1
            actual=$?
            if [ "$actual" -ne "$expected" ]; then
                bad="exit $actual, expected $expected"
            fi
        fi
        [ -n "$bad" ] && break
        iteration=$((iteration + 1))
    done
    if [ -n "$bad" ]; then
        if [ "$repeat" -gt 1 ]; then
            echo "[FAIL] $name ($bad; iteration $iteration of $repeat)"
        else
            echo "[FAIL] $name ($bad)"
        fi
        failed=$((failed + 1))
    else
        [ "${QUIET:-0}" -eq 1 ] || echo "[PASS] $name"
    fi
done

echo "stage0-C fixed-bug regressions: $((total - failed))/$total passed"
[ "$failed" -eq 0 ]
