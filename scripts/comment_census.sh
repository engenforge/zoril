#!/bin/sh
# scripts/comment_census.sh [--record|--check] — count the comments in this tree's Zoril sources
# and hold each file to its recorded budget.
#
# Why a budget at all. The comment policy (AGENTS.md, "Source Comments") is a review judgement:
# nothing mechanical can tell a paragraph of rationale from a paragraph of narration. What a
# machine can do is make the *volume* visible, so a file that grows a new essay shows up as a
# deliberate re-record instead of drifting in unnoticed. The budget lives in
# scripts/comment_budget.tsv.
#
# What it counts, per file: code lines (non-blank, non-comment), comment lines (a line whose
# first non-space characters are `//`), blocks (a maximal run of comment lines) and the longest block.
# `/* */` block comments are not counted: a string literal containing `/*` would fool a grep,
# and `.zrl` holds four real ones.
#
# The budget limits comments based on the file's recorded comment-to-code ratio times its
# current code lines, plus 10% + 5 lines of slack. Comments may grow in proportion to code.
# In addition, the longest comment block is capped at max(12, recorded longest).
#
# Scope: `src/`, `stdlib/`, `tools/*/src/`, `apps/*/src/` and `corpus/zrl/`. Out of scope, with
# the reason: `tests/` and `bench/safety_matrix/probes/` (their comments are directives a gate
# reads), `stage1/` (frozen snapshot), `bootstrap/` (incubator and generated flat files) and
# `stage0-C/` (C99, a separate sweep).
#
# --check skips a row whose file is absent, so the same budget file works in an exported tree,
# which does not carry the development tree's extra tools or `apps/`.
#
# Usage:
#   comment_census.sh            print the per-file census for this tree
#   comment_census.sh --record   rewrite scripts/comment_budget.tsv from this tree
#   comment_census.sh --check    fail a file that grew past its budget
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# ROOT is the tree to census: this repository, or a fixture directory for the selftest. BUDGET
# follows ROOT unless COMMENT_BUDGET names another table, which the selftest needs.
MODE=""
ROOT="$REPO_ROOT"
case "${1:-}" in
    --record|--check) MODE="$1"; ROOT="${2:-$REPO_ROOT}" ;;
    "") ;;
    *) ROOT="$1" ;;
esac
if [ ! -d "$ROOT" ]; then
    echo "usage: $0 [--record|--check] [DIR]" >&2
    exit 2
fi
BUDGET="${COMMENT_BUDGET:-$ROOT/scripts/comment_budget.tsv}"

# scope_files — every Zoril file this census covers, relative to the repository root, sorted.
scope_files() {
    cd "$ROOT" || return 2
    {
        find src stdlib corpus/zrl -name '*.zrl' -type f 2>/dev/null
        find tools apps -path '*/src/*' -name '*.zrl' -type f 2>/dev/null
    } | LC_ALL=C sort
}

# count_file FILE — "code lines blocks longest" for one file.
count_file() {
    awk '
        /^[ \t]*\/\// { comments++; run++; if (run > longest) longest = run; next }
        {
            if (run > 0) { blocks++; run = 0 }
            if ($0 !~ /^[ \t]*$/) code++
        }
        END {
            if (run > 0) blocks++;
            printf "%d %d %d %d\n", code + 0, comments + 0, blocks + 0, longest + 0
        }
    ' "$1"
}

case "$MODE" in
    --record)
        cd "$ROOT" || exit 2
        {
            printf 'path\tcode\tcomments\tblocks\tlongest\n'
            scope_files | while IFS= read -r f; do
                counts=$(count_file "$f")
                printf '%s\t%s\n' "$f" "$(printf '%s' "$counts" | awk '{print $1 "\t" $2 "\t" $3 "\t" $4}')"
            done
        } > "$BUDGET.tmp" && mv "$BUDGET.tmp" "$BUDGET"
        files=$(($(wc -l < "$BUDGET") - 1))
        total=$(awk 'NR > 1 { s += $3 } END { print s + 0 }' "$BUDGET")
        echo "[PASS] comment-census: recorded $files files, $total comment lines in $BUDGET"
        exit 0
        ;;
    --check)
        if [ ! -f "$BUDGET" ]; then
            echo "[FAIL] comment-census: no $BUDGET; run scripts/comment_census.sh --record"
            exit 1
        fi
        cd "$ROOT" || exit 2
        checked=0
        skipped=0
        grew=0
        while IFS='	' read -r path c2 c3 c4 c5; do
            case "$path" in
                path|'') continue ;;
            esac
            if [ ! -f "$ROOT/$path" ]; then
                skipped=$((skipped + 1))
                continue
            fi
            checked=$((checked + 1))
            if [ -n "$c5" ]; then
                budget_code="$c2"
                budget_comments="$c3"
                budget_longest="$c5"
            else
                budget_code=0
                budget_comments="$c2"
                budget_longest="$c4"
            fi
            set -- $(count_file "$path")
            act_code=$1
            act_comments=$2
            act_blocks=$3
            act_longest=$4

            if [ "$budget_code" -gt 0 ]; then
                expected=$(( (budget_comments * act_code + budget_code / 2) / budget_code ))
            else
                expected="$budget_comments"
            fi
            limit=$((expected + expected / 10 + 5))
            b_longest="${budget_longest:-0}"
            cap_longest=$((b_longest > 12 ? b_longest : 12))

            file_bad=0
            if [ "$act_comments" -gt "$limit" ]; then
                file_bad=1
                echo "[FAIL] comment-census: $path has $act_comments comment lines, budget $budget_comments (limit $limit for $act_code code lines)"
            fi
            if [ "$act_longest" -gt "$cap_longest" ]; then
                file_bad=1
                echo "[FAIL] comment-census: $path has a comment block of $act_longest lines (limit $cap_longest)"
            fi
            if [ "$file_bad" -gt 0 ]; then
                grew=$((grew + 1))
            fi
        done < "$BUDGET"
        if [ "$grew" -gt 0 ]; then
            echo "[FAIL] comment-census: $grew of $checked file(s) grew past their budget; trim the comments, or re-record with scripts/comment_census.sh --record in the same commit"
            exit 1
        fi
        echo "[PASS] comment-census: $checked file(s) within budget$([ "$skipped" -gt 0 ] && echo ", $skipped row(s) skipped (file not in this tree)")"
        exit 0
        ;;
    "")
        cd "$ROOT" || exit 2
        printf '%-48s %8s %8s %8s %8s\n' file code comments blocks longest
        scope_files | while IFS= read -r f; do
            count_file "$f" | awk -v f="$f" '{ printf "%-48s %8d %8d %8d %8d\n", f, $1, $2, $3, $4 }'
        done
        exit 0
        ;;
    *)
        echo "usage: $0 [--record|--check] [DIR]" >&2
        exit 2
        ;;
esac
