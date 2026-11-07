#!/bin/sh
# scripts/check_md_escapes.sh -- no Markdown page writes a backslash-escaped backtick (part of the md-check gate).
#
# Why. A backslash does not escape a backtick inside a code span: `a \`fn\` value` is the span `a \`, the word fn,
# and the span ` value`. The line renders wrong, and dprint then reads the broken spans and normalises the spacing
# between them, which glues words together ("a`fn`value"). A span that holds a backtick is written with a longer
# delimiter instead: `` a `fn` value `` (two backticks, the content between them).
#
# What it reports: a backslash-backtick pair that opens a word (`\`` followed by a letter, digit or underscore),
# outside a fenced code block. The escape lists a page prints (`\n`, `\\`, `\"`) never have that shape.
#
# Usage: check_md_escapes.sh [FILE...]   (default: every tracked *.md file but the task records and archives)
#        check_md_escapes.sh --selftest
# Exit: 0 clean, 1 a pair found, 2 usage.
set -u
SELF=$0

scan() {   # FILE -> "LINE: text" for each offending line
    awk '
        /^[ \t]*(```|~~~)/ { fence = !fence; next }
        !fence && /\\`[A-Za-z0-9_]/ { print NR ": " substr($0, 1, 100) }
    ' "$1"
}

if [ "${1:-}" = "--selftest" ]; then
    tmp="${TMPDIR:-/tmp}/check_md_escapes_selftest.$$"
    rm -rf "$tmp"; mkdir -p "$tmp"
    printf 'A message `through a \\`fn\\` value` here.\n' > "$tmp/bad.md"
    printf 'Escapes: `\\n`, `\\\\`, `\\"` and `\\xHH`.\n\n```\nsh -c '"'"'echo \\`date\\`'"'"'\n```\n\nA span with a backtick: `` through a `fn` value ``.\n' > "$tmp/ok.md"
    if "$SELF" "$tmp/ok.md" > "$tmp/ok.log" 2>&1; then :; else
        echo "[FAIL] selftest: escape lists, a fenced block and a double-backtick span were reported:"; cat "$tmp/ok.log"; rm -rf "$tmp"; exit 1
    fi
    if "$SELF" "$tmp/bad.md" > "$tmp/bad.log" 2>&1; then
        echo "[FAIL] selftest: a backslash-backtick pair was not detected"; rm -rf "$tmp"; exit 1
    fi
    if ! grep -q 'bad.md:1' "$tmp/bad.log"; then
        echo "[FAIL] selftest: the report did not name the file and line:"; cat "$tmp/bad.log"; rm -rf "$tmp"; exit 1
    fi
    rm -rf "$tmp"
    echo "[PASS] check_md_escapes: selftest passed"
    exit 0
fi

case "${1:-}" in -h|--help) sed -n '2,15p' "$0"; exit 0 ;; esac
cd "$(dirname "$0")/.." || exit 2
files="$*"
if [ -z "$files" ]; then
    . scripts/lib/tree_files.sh
    files=$(tree_files . | grep '\.md$')
    files=$(printf '%s\n' "$files" | grep -v -e '^doc/tasks/' -e '^doc/archive/' -e '^stage0-C/' -e '^stage1/' -e '^bootstrap/')
fi

bad=0
n=0
for f in $files; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    hits=$(scan "$f")
    [ -n "$hits" ] || continue
    printf '%s\n' "$hits" | while IFS= read -r h; do
        echo "[FAIL] $f:$h  - a backslash does not escape a backtick in a code span; write the span with a double-backtick delimiter" >&2
    done
    bad=1
done
[ "$bad" -eq 0 ] || exit 1
echo "[PASS] $n Markdown file(s) carry no backslash-escaped backtick"
exit 0
