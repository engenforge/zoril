#!/bin/sh
# scripts/test_origins.sh — the origin sets of doc/design/provenance.md §3, one local at a time.
#
# Each tests/language/memory/origins/*.zrl names one function and one of its locals on a line
#
#     // ORIGINS: <function> <local> O={...} S={...}
#
# and `zoril --emit-origins` must print exactly that line for that local (the first local of that
# name in that function). The rules read the sets only under `--provenance` (Z-0048), so by default
# a change to the analysis shows only here, as a diff of the line. The same files also run as
# ordinary tests in the memory group (with their `// flags:`), so each one's verdict and exit code
# are checked there.
cd "$(dirname "$0")/.." || exit 2
. scripts/lib/portability.sh
ZORIL=${ZORIL_BIN:-./build/zoril}
DIR=tests/language/memory/origins
WORK=build/origins
mkdir -p "$WORK"
errors=0
count=0
for f in "$DIR"/*.zrl; do
    [ -f "$f" ] || continue
    directives=$(sed -n 's|^// ORIGINS: ||p' "$f")
    if [ -z "$directives" ]; then
        echo "[FAIL] $f: no // ORIGINS: line"
        errors=$((errors + 1))
        continue
    fi
    count=$((count + 1))
    out="$WORK/$(basename "$f" .zrl).out"
    run_with_timeout -k 5s 30s "$ZORIL" -I stdlib=stdlib --emit-origins "$f" > "$out" 2>&1 < /dev/null
    file_ok=1
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        fn=${line%% *}
        want=${line#* }
        loc=${want%% *}
        case "$loc" in
            !*)
                key=${loc#!}
                got=$(awk -v fn="$fn" -v loc="$key" '
                    /^origins / { on = ($2 == fn); if (on) seen = 1; next }
                    on && $1 == loc { sub(/^  /, ""); print; exit }
                    END { if (!seen) print "(no origins block for " fn ")" }' "$out")
                if [ -n "$got" ]; then
                    echo "[FAIL] $f: $fn"
                    echo "       expected: $want"
                    echo "       actual:   $got"
                    file_ok=0
                fi
                ;;
            *)
                got=$(awk -v fn="$fn" -v loc="$loc" '
                    /^origins / { on = ($2 == fn); next }
                    on && $1 == loc { sub(/^  /, ""); print; exit }' "$out")
                if [ "$got" != "$want" ]; then
                    echo "[FAIL] $f: $fn"
                    echo "       expected: $want"
                    echo "       actual:   ${got:-(no line for $loc; output in $out)}"
                    file_ok=0
                fi
                ;;
        esac
    done <<EOF
$directives
EOF
    if [ "$file_ok" -eq 1 ]; then
        echo "[PASS] $f"
    else
        errors=$((errors + 1))
    fi
done
if [ "$count" -eq 0 ]; then
    echo "[FAIL] no golden tests under $DIR"
    exit 1
fi
[ "$errors" -eq 0 ]
