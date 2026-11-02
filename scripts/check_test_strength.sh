#!/bin/sh
# scripts/check_test_strength.sh — reject tests that cannot fail.
#
# A test that runs, defines functions, and whose main() never calls any of them
# proves exactly one thing: the program compiles. It passes whether or not the
# feature under test works. On 2026-09-12 that gap let a real miscompile through
# a fully green suite: repro_linked_list_head.zrl's main is `return 0`, so a
# change that made `match l { Cons(v) => v }` on a &L return 132 instead of 7
# passed 471/471 unit tests AND the self-hosting fixpoint. A fixpoint cannot help
# here -- a deterministic miscompile reproduces itself perfectly.
#
# The rule: a test that RUNS must exercise what it defines. A test may opt out in
# exactly one of two ways, both explicit:
#
#   1. Declare a compile-outcome expectation -- "expected compile fail" or
#      "expected compile success". Then the compile IS the assertion and main's
#      contents do not matter.
#   2. Mark itself "// compile-only: <reason>" when it must run but genuinely
#      cannot assert a value. The reason is required so the next reader can
#      judge it.
#
# Anything else is flagged. Exit 0 = clean, 1 = weak tests found.
#
# Deliberately a heuristic, not a proof. It cannot tell a strong assertion from a
# weak one; it only catches the specific shape that provably cannot fail. Real
# assurance is a value-checking test, which is what this exists to push toward.

set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

ROOTS="tests/language tests/functional tests/regressions tests/stdlib tests/integration tests/compiler tests/incremental"
QUIET=0
[ "$1" = "--quiet" ] && QUIET=1

WEAK=0
SCANNED=0

for root in $ROOTS; do
    [ -d "$root" ] || continue
    # shellcheck disable=SC2044
    for f in $(find "$root" \( -name include -o -name helpers -o -name lib -o -name test_include \) -prune -o -type f -name '*.zrl' -print); do
        sed 's/"[^"]*"/""/g' "$f" | grep -q '^[[:space:]]*\(pub[[:space:]]\+\)\?fn[[:space:]]\+main[[:space:]]*(' || continue
        SCANNED=$((SCANNED + 1))

        # Explicit opt-outs.
        if grep -q 'expected compile fail\|expected compile success\|compile-only:' "$f"; then
            echo "[PASS] $f"; continue
        fi

        # Functions defined in this file, excluding main.
        fns=$(sed 's/"[^"]*"/""/g' "$f" \
              | sed -n 's/^[[:space:]]*\(pub[[:space:]]\+\)\?fn[[:space:]]\+\([A-Za-z_][A-Za-z0-9_]*\).*/\2/p' \
              | grep -v '^main$' | sort -u)
        [ -n "$fns" ] || { echo "[PASS] $f"; continue; }

        # main()'s body, by brace matching from the `fn main` line.
        #
        # String literals are blanked first. Without that, a test whose source
        # under test happens to contain `fn main(` inside a string -- which
        # tests/compiler/test_frontend.zrl does, lexing `"fn main() { ... }"` --
        # is matched inside the literal and mis-flagged. That was a real false
        # positive on this gate's first run.
        body=$(awk '
            { gsub(/"[^"]*"/, "\"\"") }
            /(^|[[:space:]])fn[[:space:]]+main[[:space:]]*\(/ { inmain = 1 }
            inmain {
                line = $0
                n = split(line, ch, "")
                for (i = 1; i <= n; i++) {
                    if (ch[i] == "{") { depth++; started = 1 }
                    else if (ch[i] == "}") { depth-- }
                    if (started && depth > 0) printf "%s", ch[i]
                }
                printf "\n"
                if (started && depth <= 0) exit
            }' "$f")

        # Control flow means the test at least branches on something.
        if echo "$body" | grep -q '\bif\b\|\bwhile\b\|\bloop\b\|\bmatch\b'; then
            echo "[PASS] $f"; continue
        fi

        # Does main call anything the file defines?
        calls=0
        for fn in $fns; do
            # `::<...>` may sit between the name and the paren (turbofish).
            # Without allowing it, `identity::<i32>(0)` reads as "never called" --
            # a real false positive on this gate's second run.
            if echo "$body" | grep -q "[^A-Za-z0-9_]${fn}[[:space:]]*\(::<[^>]*>\)\{0,1\}[[:space:]]*(\|^${fn}[[:space:]]*\(::<[^>]*>\)\{0,1\}[[:space:]]*("; then
                calls=1
                break
            fi
        done
        if [ "$calls" -eq 1 ]; then echo "[PASS] $f"; continue; fi

        WEAK=$((WEAK + 1))
        printf '[FAIL] %s (defines %s; main() calls none of them and does not branch)\n' \
            "$f" "$(echo "$fns" | tr '\n' ' ' | sed 's/ $//')"
    done
done

if [ "$WEAK" -gt 0 ]; then
    printf '\n%d of %d test programs cannot fail.\n\n' "$WEAK" "$SCANNED"
    cat <<'MSG'
Each one runs, returns a constant, and would pass even if the feature it names
were miscompiled. Fix by making main() assert something it computes:

    fn main() -> i32 { if head(&n) != 7 { return 1; } return 0; }

Or, if the test genuinely cannot assert a value, say so explicitly:

    // expected compile fail          -- the rejection is the assertion
    // expected compile success       -- the acceptance is the assertion
    // compile-only: <why it cannot assert a value>
MSG
    exit 1
fi

[ "$QUIET" -eq 0 ] && printf 'All %d test programs either assert something or declare why they do not.\n' "$SCANNED"
exit 0
