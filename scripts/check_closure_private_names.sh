#!/bin/sh
# scripts/check_closure_private_names.sh — refuse two modules of one stage1-built closure that
# define a private top-level item of the same name.
#
# The pinned stage1 compiler rejects two private functions of one name ("cannot access private
# function: NAME") and stops with an internal error on two private structs of one name, while
# build/zoril accepts both, so nothing in the default build notices until a fresh checkout fails
# to bootstrap. The closures stage1 builds are src/main.zrl's and tools/zilc/src/main.zrl's;
# each is checked on its own.
#
# Checked: top-level `fn`, `unsafe fn`, `struct`, `enum`, `trait` and `type` lines that start in
# column 0 and are not `pub`; each kind is its own namespace in the report. Not checked: methods
# (indented), `extern` declarations, private constants (a clash fails in build/zoril too), or an
# item declared on a line that does not start in column 0.
#
# Usage:
#   scripts/check_closure_private_names.sh             list both closures with build/zoril
#   scripts/check_closure_private_names.sh --list FILE check the module paths in FILE as one
#                                                      closure (columns 1 and 2 of each line)
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

TIMEOUT_CMD=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_CMD="timeout -k 5s 30s"

# check_closure LABEL LISTFILE: print [PASS]/[FAIL] lines; status 1 when a name is shared.
check_closure() {
    _label="$1"
    _list="$2"
    awk '{ print $1; if (NF > 1) print $2 }' "$_list" | sort -u >"$tmp/modules.txt"

    : >"$tmp/names.txt"
    while IFS= read -r _mod; do
        [ -f "$_mod" ] || continue
        awk -v file="$_mod" '
            /^(unsafe fn|fn|struct|enum|trait|type) [A-Za-z_]/ {
                kind = $1
                rest = $0
                if (kind == "unsafe") kind = "fn"
                sub(/^(unsafe fn|fn|struct|enum|trait|type) /, "", rest)
                sub(/[^A-Za-z0-9_].*$/, "", rest)
                print kind "\t" rest "\t" file
            }' "$_mod" >>"$tmp/names.txt"
    done <"$tmp/modules.txt"

    awk -F '\t' -v label="$_label" '
        {
            key = $1 " " $2
            files[key] = (key in files) ? files[key] " " $3 : $3
            count[key]++
        }
        END {
            for (k in count) if (count[k] > 1) {
                n = split(files[k], f, " ")
                list = f[1]
                for (i = 2; i <= n; i++) list = list (i == n ? " and " : ", ") f[i]
                printf "[FAIL] closure-private-names: %s in %s (%s)\n", k, list, label
            }
        }' "$tmp/names.txt" | sort >"$tmp/fail.txt"

    if [ -s "$tmp/fail.txt" ]; then
        cat "$tmp/fail.txt"
        return 1
    fi
    echo "[PASS] closure-private-names: $_label: $(wc -l <"$tmp/modules.txt" | tr -d ' ') modules, no shared private name"
}

emit() {
    _out="$1"
    shift
    # shellcheck disable=SC2086
    $TIMEOUT_CMD "${ZORIL:-build/zoril}" --emit-deps "$@" -I stdlib=stdlib -I build/gen -o "$_out" \
        >"$tmp/emit.log" 2>&1 || {
        echo "[FAIL] closure-private-names: cannot list the closure of $1 (needs a built tree)" >&2
        cat "$tmp/emit.log" >&2
        exit 2
    }
}

status=0
if [ -n "$list" ]; then
    check_closure "$list" "$list" || status=1
else
    emit "$tmp/src.txt" src/main.zrl -I src
    check_closure "src/main.zrl" "$tmp/src.txt" || status=1
    emit "$tmp/zilc.txt" tools/zilc/src/main.zrl -I src -I tools/zilc/src
    check_closure "tools/zilc/src/main.zrl" "$tmp/zilc.txt" || status=1
fi
exit $status
