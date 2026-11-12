#!/bin/sh
# scripts/check_md_tables.sh -- no Markdown table is wider than 140 characters (part of the md-check gate).
#
# Why. A wide table does not wrap: in a terminal, a diff or a review it scrolls sideways, and a 600-character
# row hides what it says. The rule is that a table fits in 140 characters; one that cannot be made to fit is
# written as an outline instead (a bullet per row, the other columns as sub-bullets), which wraps.
#
# Usage: check_md_tables.sh [--fix] [--limit N] [FILE...]   (default: every tracked *.md file)
#        check_md_tables.sh --selftest
#   no flag    report each table wider than the limit as "FILE:LINE: ..." and exit 1 if there is one.
#   --fix      rewrite those tables in place as outlines, then report what it did (exit 0).
# A table with a cell holding an odd number of backticks is reported too (and never rewritten): a literal
# pipe in a code span splits the cell unless it is written `\|`, and the row loses what follows it.
# A table inside a fenced code block is an example, not a table, and is left alone. The file
# doc/tasks/completed.tm.md is skipped: completed tasks are history and keep their text unchanged. So is
# bench/safety_matrix/matrix.md, whose table is parsed by check_safety_model.sh and check_route_coverage.sh: it needs
# those gates changed first (a task in doc/tasks/active.tm.md), not a rewrite.
#
# The outline, for a table with columns A | B | C and a row a | b | c:
#   two columns:    - **a**: b
#   three or more:  - **a**
#                     - B: b
#                     - C: c
# An empty cell is left out. `\|` in a cell becomes `|`. Check the rewritten text and fix the sentence
# around it: the tool changes the shape, not the prose.
set -u
LC_ALL=C.UTF-8
export LC_ALL
SELF=$0
LIMIT=140
FIX=0

# convert FILE LIMIT FIX -- print the (possibly rewritten) file on stdout; print one line per wide table on
# stderr as "LINE WIDTH ROWS".
convert() {
    awk -v LIMIT="$2" -v FIX="$3" -v NAME="$1" '
    function is_row(s)  { return s ~ /^[ ]*\|/ }
    function is_sep(s)  { return s ~ /^[ ]*\|[ :|-]*-[ :|-]*\|?[ ]*$/ }
    function trim(s)    { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    # split_row: cells of a table row into cell[1..n]; returns n. `\|` is a literal pipe.
    function split_row(s, cell,    n, i, ch, cur, len) {
        sub(/^[ ]*\|/, "", s)
        sub(/\|[ ]*$/, "", s)
        n = 1; cur = ""; len = length(s)
        for (i = 1; i <= len; i++) {
            ch = substr(s, i, 1)
            if (ch == "\\" && substr(s, i + 1, 1) == "|") { cur = cur "|"; i++ }
            else if (ch == "|") { cell[n] = trim(cur); n++; cur = "" }
            else cur = cur ch
        }
        cell[n] = trim(cur)
        return n
    }
    # broken(first, last): the first row of a table with a cell holding an odd number of backticks. A literal
    # pipe in a code span splits the cell unless it is written `\|`, and the rest of the row is then lost.
    function broken(first, last,    r, m, k, t, q, c) {
        for (r = first; r <= last; r++) {
            if (r == first + 1) continue
            m = split_row(lines[r], c)
            for (k = 1; k <= m; k++) { t = c[k]; q = gsub(/`/, "", t); if (q % 2 == 1) return r }
        }
        return 0
    }
    function plain(s) { gsub(/<br[ ]*\/?>/, " ", s); return s }
    function lead(s) {
        if (index(s, "**") > 0) return s
        return "**" s "**"
    }
    function emit(s) { out[++nout] = s }
    function rewrite(first, last, indent,    h, nh, c, nc, r, k, line) {
        nh = split_row(lines[first], h)
        if (nout > 0 && out[nout] != "") emit("")
        for (r = first + 2; r <= last; r++) {
            nc = split_row(lines[r], c)
            if (nc == 2 || nh == 2) {
                if (c[1] != "" && c[2] != "") line = indent "- " lead(plain(c[1])) ": " plain(c[2])
                else if (c[1] != "")          line = indent "- " lead(plain(c[1]))
                else                          line = indent "- " plain(c[2])
                emit(line)
            } else {
                if (c[1] != "") { emit(indent "- " lead(plain(c[1]))); k = 2 }
                else k = 1
                for (; k <= nc; k++) {
                    if (c[k] == "") continue
                    if (c[1] != "") emit(indent "  - " plain(h[k]) ": " plain(c[k]))
                    else if (h[k] != "") emit(indent "- " plain(h[k]) ": " plain(c[k]))
                    else emit(indent "- " plain(c[k]))
                }
            }
        }
        if (last < n && lines[last + 1] != "") emit("")
    }
    { lines[++n] = $0 }
    END {
        i = 1; fence = 0
        while (i <= n) {
            l = lines[i]
            if (l ~ /^[ ]*(```|~~~)/) { fence = !fence; emit(l); i++; continue }
            if (!fence && is_row(l) && i < n && is_sep(lines[i + 1])) {
                j = i; width = 0
                while (j <= n && is_row(lines[j])) { if (length(lines[j]) > width) width = length(lines[j]); j++ }
                last = j - 1
                bad = broken(i, last)
                if (bad) {
                    printf "!%d\n", bad > "/dev/stderr"
                    for (k = i; k <= last; k++) emit(lines[k])
                    i = j; continue
                }
                if (width > LIMIT) {
                    printf "%d %d %d\n", i, width, last - i - 1 > "/dev/stderr"
                    if (FIX) {
                        match(l, /^[ ]*/); rewrite(i, last, substr(l, 1, RLENGTH))
                        i = j; if (i <= n && lines[i] == "" && out[nout] == "") i++
                        continue
                    }
                }
                for (k = i; k <= last; k++) emit(lines[k])
                i = j; continue
            }
            emit(l); i++
        }
        for (k = 1; k <= nout; k++) print out[k]
    }' "$1"
}

selftest() {
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/mdtables.XXXXXX") || exit 2
    trap 'rm -rf "$tmp"' EXIT
    long=$(printf 'x%.0s' $(seq 1 90))
    {
        echo '# Doc'; echo; echo 'Before.'
        echo '| Name | Why |'; echo '| --- | --- |'; echo "| \`a\\|b\` | $long $long |"; echo 'After.'; echo
        echo '| A | B | C |'; echo '| - | - | - |'; echo "| one | two | $long $long |"; echo '| | only | |'; echo
        echo '| Fits | Fine |'; echo '| --- | --- |'; echo '| 1 | 2 |'; echo
        echo '```'; echo "| In | Fence |"; echo "| --- | --- |"; echo "| $long $long | z |"; echo '```'
    } > "$tmp/t.md"
    if out=$("$SELF" "$tmp/t.md" 2>&1); then echo "[FAIL] md-tables selftest: wide tables passed the check"; exit 1; fi
    printf '%s\n' "$out" | grep -q 't.md:4: table is 1[0-9][0-9] characters wide' || { echo "[FAIL] md-tables selftest: first table not reported: $out"; exit 1; }
    printf '%s\n' "$out" | grep -q 't.md:9:' || { echo "[FAIL] md-tables selftest: second table not reported: $out"; exit 1; }
    printf '%s\n' "$out" | grep -q 't.md:13:' && { echo "[FAIL] md-tables selftest: narrow table reported"; exit 1; }
    printf '%s\n' "$out" | grep -q 't.md:17:' && { echo "[FAIL] md-tables selftest: fenced table reported"; exit 1; }
    "$SELF" --fix "$tmp/t.md" > /dev/null 2>&1 || { echo "[FAIL] md-tables selftest: --fix failed"; exit 1; }
    "$SELF" "$tmp/t.md" > /dev/null 2>&1 || { echo "[FAIL] md-tables selftest: still wide after --fix"; exit 1; }
    grep -q "^- \*\*\`a|b\`\*\*: $long $long\$" "$tmp/t.md" || { echo "[FAIL] md-tables selftest: two-column outline wrong"; sed -n 1,12p "$tmp/t.md"; exit 1; }
    grep -q '^- \*\*one\*\*$' "$tmp/t.md" && grep -q '^  - C: x' "$tmp/t.md" && grep -q '^- B: only$' "$tmp/t.md" || { echo "[FAIL] md-tables selftest: three-column outline wrong"; exit 1; }
    grep -q '^| Fits | Fine |$' "$tmp/t.md" && grep -q "^| $long $long | z |\$" "$tmp/t.md" || { echo "[FAIL] md-tables selftest: touched a table it should not"; exit 1; }
    printf '| Item | Status |\n| --- | --- |\n| Closures `|x| body` | yes |\n' > "$tmp/u.md"
    out=$("$SELF" --fix "$tmp/u.md" 2>&1) && { echo "[FAIL] md-tables selftest: an unbalanced-backtick cell passed"; exit 1; }
    printf '%s\n' "$out" | grep -q 'u.md:3: a table cell has an unbalanced backtick' || { echo "[FAIL] md-tables selftest: broken cell not reported: $out"; exit 1; }
    echo "[PASS] md-tables selftest: wide tables are found and outlined by --fix; narrow and fenced ones are left alone; a split code span is reported"
}

files=
while [ $# -gt 0 ]; do
    case $1 in
        --fix) FIX=1 ;;
        --limit) LIMIT=$2; shift ;;
        --selftest) selftest; exit $? ;;
        -*) echo "usage: $0 [--fix] [--limit N] [FILE...] | --selftest" >&2; exit 2 ;;
        *) files="$files $1" ;;
    esac
    shift
done

cd "$(dirname "$0")/.." || exit 2
if [ -z "$files" ]; then
    . scripts/lib/tree_files.sh
    files=$(tree_files . | grep '\.md$' | grep -v -e '^doc/tasks/completed\.tm\.md$' -e '^bench/safety_matrix/matrix\.md$')
fi

bad=0
for f in $files; do
    [ -f "$f" ] || continue
    tmp=$(mktemp "${TMPDIR:-/tmp}/mdtables.out.XXXXXX") || exit 2
    found=$(convert "$f" "$LIMIT" "$FIX" 2>&1 >"$tmp")
    if [ -n "$found" ]; then
        printf '%s\n' "$found" | while read -r line width rows; do
            case $line in
                !*)
                    echo "[FAIL] $f:${line#!}: a table cell has an unbalanced backtick - write a literal | in a cell as \\| (the row is split at it otherwise, and the rest of the row is lost)"
                    continue ;;
            esac
            if [ "$FIX" -eq 1 ]; then
                echo "[FIXED] $f:$line: table ($rows rows, $width characters wide) is now an outline"
            else
                echo "[FAIL] $f:$line: table is $width characters wide (limit $LIMIT, $rows rows): shorten it, or run $SELF --fix $f to make it an outline"
            fi
        done
        if [ "$FIX" -eq 1 ]; then cat "$tmp" > "$f"; else bad=1; fi
        case $found in *'!'*) bad=1 ;; esac
    fi
    rm -f "$tmp"
done
if [ "$bad" -eq 0 ]; then
    [ "$FIX" -eq 1 ] || echo "[PASS] md-tables: no table is wider than $LIMIT characters"
fi
exit "$bad"
