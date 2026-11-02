#!/bin/sh
# scripts/check_temp_names.sh — no committed expectation may name a compiler temporary by id.
#
# A diagnostic on a compiler-generated local used to read `use of moved value 'variable (id: 3)'`.
# That id is not something a reader of the source can act on. `src/check_zir.zrl` names the
# temporary by the expression that produced it ("the value of the expression at L:C"), so a
# committed expectation that still says `variable (id:` either pins the old fallback or is a
# test that stopped exercising the named form. This gate is cheap and needs no compiler.
#
# Usage: check_temp_names.sh [DIR]   (default: tests/error_reporting)
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${1:-$REPO_ROOT/tests/error_reporting}"

fail=0
count=0
for f in "$DIR"/*.zrl; do
    [ -f "$f" ] || continue
    count=$((count + 1))
    matches=$(grep -n '^// EXPECT: .*variable (id:' "$f" 2>/dev/null || true)
    if [ -n "$matches" ]; then
        echo "[FAIL] temp-names: $f expects an internal temporary id:"
        printf '%s\n' "$matches" | sed 's/^/       /'
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "[PASS] temp-names: no expected diagnostic names a temporary by id ($count files)"
fi
exit "$fail"
