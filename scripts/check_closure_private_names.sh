#!/bin/sh
# scripts/check_closure_private_names.sh — refuse two modules of the src/ closure that define a
# private top-level function of the same name.
#
# The pinned stage1 compiler rejects such a program ("cannot access private function: NAME")
# and build/zoril accepts it, so nothing in the default build notices until a fresh checkout
# fails to bootstrap through stage1.
#
# Checked: top-level `fn` and `unsafe fn` lines that start in column 0 and are not `pub`.
# Not checked: methods (indented), `extern` declarations, generic names that differ only by
# their type arguments, or a function declared on a line that does not start in column 0.
#
# Usage:
#   scripts/check_closure_private_names.sh             list the closure with build/zoril
#   scripts/check_closure_private_names.sh --list FILE read the module paths from FILE instead
#                                                      (columns 1 and 2 of each line)
#
# Exit status: 0 no shared name, 1 a name is shared, 2 usage error or no closure.
set -u

case "$0" in
    /*) _self="$0" ;;
    */*) _self="$PWD/$0" ;;
    *) _self="$(command -v -- "$0" 2>/dev/null || echo "$0")" ;;
esac
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$_self")/.." && pwd)}"
cd "$REPO_ROOT" || exit 2

list=""
case "${1:-}" in
    --list)
        [ $# -eq 2 ] || { echo "usage: $0 [--list FILE]" >&2; exit 2; }
        list="$2" ;;
    "") ;;
    *) echo "usage: $0 [--list FILE]" >&2; exit 2 ;;
esac

tmp="${TMPDIR:-/tmp}/closure_private_names.$$"
mkdir -p "$tmp" || exit 2
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

if [ -z "$list" ]; then
    list="$tmp/closure.txt"
    timeout -k 5s 30s "${ZORIL:-build/zoril}" --emit-deps src/main.zrl \
        -I stdlib=stdlib -I src -I build/gen -o "$list" >"$tmp/emit.log" 2>&1 || {
        echo "[FAIL] closure-private-names: cannot list the closure (needs a built tree)" >&2
        cat "$tmp/emit.log" >&2
        exit 2
    }
fi

awk '{ print $1; if (NF > 1) print $2 }' "$list" | sort -u >"$tmp/modules.txt"

: >"$tmp/names.txt"
while IFS= read -r mod; do
    [ -f "$mod" ] || continue
    awk -v file="$mod" '
        /^(unsafe )?fn [A-Za-z_]/ {
            s = $0
            sub(/^(unsafe )?fn /, "", s)
            sub(/[^A-Za-z0-9_].*$/, "", s)
            print s "\t" file
        }' "$mod" >>"$tmp/names.txt"
done <"$tmp/modules.txt"

modules=$(wc -l <"$tmp/modules.txt" | tr -d ' ')

awk -F '\t' '
    { files[$1] = ($1 in files) ? files[$1] " " $2 : $2; count[$1]++ }
    END {
        for (n in count) if (count[n] > 1) {
            split(files[n], f, " ")
            printf "[FAIL] closure-private-names: %s in %s and %s\n", n, f[1], f[2]
        }
    }' "$tmp/names.txt" | sort >"$tmp/fail.txt"

if [ -s "$tmp/fail.txt" ]; then
    cat "$tmp/fail.txt"
    exit 1
fi
echo "[PASS] closure-private-names: $modules modules, no shared private function name"
