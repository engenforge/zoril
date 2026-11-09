#!/bin/sh
# scripts/check_comment_noise.sh — no source comment in this tree may be scaffolding, step
# narration, or a pointer to a path the tree does not carry.
#
# The comment policy is AGENTS.md's "Source Comments" section; doc/developer_guide.md §4 has the
# review checklist. This gate is only the part a machine can decide, and it is deliberately a
# closed list of phrases rather than a classifier: measured on 2026-10-19, a "restates the next
# line" heuristic hit 19 blocks of which nearly all were grammar productions above parser
# functions (which the policy keeps), a "commented-out code" heuristic hit 30 lines that were all
# prose starting with `for`/`while`/`if`, and a narrative-opener heuristic hit 48 `// This is ...`
# explanations. Those judgements stay with the reviewer; the phrases below have no false positives
# on this tree.
#
# Rule 1 - scaffolding and step narration. A comment whose first word (after any banner decoration
# such as `--`, `==` or `*`) is TODO, FIXME, XXX or HACK; a comment containing "rest of the
# implementation", "omitted for brevity" or "left as an exercise"; and step narration (`Step <N>:`,
# `Here we`, `Now we`, `First,`, `Then,`, `Next,`, `Finally,`), so decorating a line cannot dodge
# the rule.
#
# Rule 2 - stale path reference. A path-shaped token in a comment (`dir/file.ext`) must name a file
# the tree carries: it resolves against the repository root, or against the source root of the
# citing file (`src/` for `src/**`, `tools/<name>/src/` for a tool, `stdlib/`, `corpus/zrl/`),
# because the compiler's comments name modules relative to `src/`. A token split across two comment
# lines - the first ending in `/`, the second starting with the rest - is joined before matching,
# so wrapping a path cannot hide it. `stage0-C/` and `stage1/` are resolved through
# `scripts/lib/layout.sh`, so the check works in the exported tree where they live under
# `bootstrap/`. Tokens inside a double-quoted string are examples, not references, and the count
# runs from the start of the line to the token, opening quote included, so a second path in the
# same quoted example is inside it too; build outputs (`build/`, `.zoril-cache/`) are not source.
#
# Rule 2b - private documents. `doc/performance`, `doc/release`, `doc/archive` and `doc/stage0-C`
# name a document no tree exports, so naming one fails with no existence check: the private tree
# may carry it and the export still never will. It is the same leak `check_export_docs.sh` closes
# for Markdown. `doc/design` is carried by the tree, and `doc/tasks` (the `.tm.md` files) is the
# `tasks` branch where it is mounted; both are held only to Rule 2a: a comment may cite
# `doc/tasks/active.tm.md` while that file exists, and a citation of one that does not fails as any
# stale path does, so a tree without the mount refuses a source comment that cites a task file.
# A document that exists here but is dropped from the curated export (`doc/spec/bootstrap_subset.md`,
# the `doc/language/debugging-*` notes) cannot be listed here - Rule 2a resolves it - which is why
# `scripts/export_public_release.sh` runs this gate on the exported tree as well.
# A path that ships (`doc/spec/safety_model.md`) is Rule 2a's business, not this one.
#
# Rule 3 - the census ratchet. `scripts/comment_census.sh --check` holds each file to the budget in
# `scripts/comment_budget.tsv`; this gate runs it, so a new essay is a deliberate re-record.
#
# Never flagged: the marker lines a gate reads (`// SAFETY:`, `// exhaustive:`, `// expected:`,
# `// gap:`, the test directives, the corpus `// --- id:` banners), `tests/`, `bench/` probes,
# `stage1/` (frozen), `bootstrap/` (incubator and generated files) and `stage0-C/` (C99, swept
# separately). `/* */` block comments are not phrase-checked: a string literal containing `/*`
# would fool a grep, and `.zrl` holds four real ones. Only a whole-line `//` comment is read, so a
# trailing comment (`code; // TODO`, or a path named after code) escapes Rules 1 and 2: telling one
# from a string literal containing `//` needs a lexer, which `awk` is not. Measured on 2026-10-19
# that blind spot holds one trailing path reference (`src/check_zir.zrl`, `is_implicit_aggregate_ptr`,
# which resolves) and no trailing scaffolding.
#
# Exceptions are explicit, never a pattern: `scripts/comment_noise_allow.txt` is
# `<path>|<text the finding contains>|<why>`, and every entry names the change that removes it.
#
# Usage: check_comment_noise.sh [DIR]    (default: this repository)
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${1:-$REPO_ROOT}"
ALLOW="$REPO_ROOT/scripts/comment_noise_allow.txt"
CENSUS="$REPO_ROOT/scripts/comment_census.sh"

if [ ! -d "$DIR" ]; then
    echo "[FAIL] comment-noise: no such directory: $DIR"
    exit 1
fi

# The two bootstrap seeds sit at the root of this tree and under bootstrap/ in the export.
# layout.sh answers where, and a comment names them by their own directory name, so a token's
# first component is matched against each seed directory's basename (case-insensitively) and the
# rest is resolved under that directory. Nothing here spells the private layout, which
# scripts/check_export_layout.sh refuses to ship.
STAGE0_DIR=""
STAGE1_DIR=""
if [ -f "$REPO_ROOT/scripts/lib/layout.sh" ]; then
    _saved=$(pwd)
    cd "$REPO_ROOT" 2>/dev/null && . scripts/lib/layout.sh 2>/dev/null || true
    cd "$_saved" 2>/dev/null || true
fi

# lower TEXT — ASCII lowercase, for the case-insensitive seed-name comparison.
lower() {
    printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
}

# seed_resolves TOKEN — a seed-relative token resolves under whichever directory holds that seed.
seed_resolves() {
    _first=${1%%/*}
    _rest=${1#*/}
    [ "$_rest" = "$1" ] && return 1
    _want=$(lower "$_first")
    for _seed in "$STAGE0_DIR" "$STAGE1_DIR"; do
        [ -n "$_seed" ] || continue
        [ "$_want" = "$(lower "$(basename "$_seed")")" ] || continue
        if [ -e "$DIR/$_seed/$_rest" ] || [ -e "$(source_root "$2")/$_seed/$_rest" ]; then
            return 0
        fi
    done
    return 1
}

# scope_files — the Zoril files this gate reads, relative to DIR.
scope_files() {
    cd "$DIR" || return 2
    {
        find src stdlib corpus/zrl -name '*.zrl' -type f 2>/dev/null
        find tools apps -path '*/src/*' -name '*.zrl' -type f 2>/dev/null
    } | LC_ALL=C sort
}

# findings — one line per finding: file<TAB>line<TAB>kind<TAB>text.
findings() {
    scope_files | while IFS= read -r f; do
        awk -v file="$f" '
            /^[ \t]*\/\// {
                body = $0
                sub(/^[ \t]*\/\/[ \t]?/, "", body)
                # A marker line is read by a gate, not by a reader: never phrased-check it.
                if (body ~ /^(SAFETY:|exhaustive:|expected:|expected exit|expected compile|EXPECT:|flags:|link:|gap:|@skip:|COMPILE ERROR|--- id:)/) next
                text = body
                gsub(/^[ \t]*[-─=*#~_]+[ \t]*/, "", text)
                if (text ~ /^(TODO|FIXME|XXX|HACK)([^A-Za-z0-9_]|$)/) {
                    printf "%s\t%d\t%s\t%s\n", file, FNR, "scaffolding", text
                } else if (text ~ /^(Step [0-9]+:|Here we|Now we|First,|Then,|Next,|Finally,)/) {
                    printf "%s\t%d\t%s\t%s\n", file, FNR, "step-narration", text
                } else if (text ~ /(rest of the implementation|omitted for brevity|left as an exercise)/) {
                    printf "%s\t%d\t%s\t%s\n", file, FNR, "scaffolding", text
                }
                # A path token may be split across two comment lines, which no single-line regex
                # can see: carry a line ending in `/` into the first word of the next line.
                scan = body
                if (carry != "") {
                    scan = carry body
                    carry = ""
                }
                # Rule 2b: a document that is private in every tree. No existence check - this
                # tree may carry it and the export still never will. Quotes are counted from the
                # start of the scanned line with the match boundary character included, because
                # that character is what makes a token an example rather than a reference; the
                # trailing boundary is left for the next token so a closing quote still counts.
                off = 1
                r = scan
                while (match(r, /(^|[^A-Za-z0-9_-])doc\/(performance|release|archive|stage0-C)([^A-Za-z0-9_-]|$)/)) {
                    tok = substr(r, RSTART, RLENGTH)
                    start = off + RSTART - 1
                    off = start + RLENGTH - 1
                    r = substr(r, RSTART + RLENGTH - 1)
                    q = substr(scan, 1, start)
                    if (gsub(/"/, "x", q) % 2 == 1) continue
                    sub(/^[^A-Za-z0-9_-]/, "", tok)
                    # The trailing boundary may be a quote (`doc/release"`): keep it out of the finding.
                    sub(/[.,;:)" \t]+$/, "", tok)
                    sub(/\/$/, "", tok)
                    printf "%s\t%d\t%s\t%s\n", file, FNR, "private-doc", tok
                }
                # Rule 2a: a path-shaped token must name a file this tree carries.
                off = 1
                rest = scan
                while (match(rest, /[A-Za-z0-9_.-]+(\/[A-Za-z0-9_.-]+)+\.(zrl|zri|md|c|h|s|sh|scd|tsv|txt|lua)/)) {
                    tok = substr(rest, RSTART, RLENGTH)
                    start = off + RSTART - 1
                    off = start + RLENGTH
                    rest = substr(rest, RSTART + RLENGTH)
                    # An odd number of quotes before the token means it sits inside a quoted
                    # string, which is an example rather than a reference.
                    q = substr(scan, 1, start)
                    if (gsub(/"/, "x", q) % 2 == 1) continue
                    if (tok ~ /^(build|\.zoril-cache)\//) continue
                    printf "%s\t%d\t%s\t%s\n", file, FNR, "path", tok
                }
                # Hold the trailing word when the line ends in `/`, so the next comment line
                # completes the path; a non-comment line drops it.
                tail = body
                sub(/[ \t]+$/, "", tail)
                if (tail ~ /\/$/) {
                    carry = tail
                    sub(/^.*[ \t]/, "", carry)
                }
            }
            !/^[ \t]*\/\// { carry = "" }
        ' "$DIR/$f"
    done
}

# source_root FILE — the directory a module-relative reference in FILE resolves against.
source_root() {
    case "$1" in
        src/*)          printf '%s\n' "$DIR/src" ;;
        stdlib/*)       printf '%s\n' "$DIR/stdlib" ;;
        tools/*/src/*)  printf '%s\n' "$DIR/${1%%/src/*}/src" ;;
        apps/*/src/*)   printf '%s\n' "$DIR/${1%%/src/*}/src" ;;
        corpus/zrl/*)   printf '%s\n' "$DIR/corpus/zrl" ;;
        *)              printf '%s\n' "$DIR" ;;
    esac
}

# resolves FILE TOKEN — true when the token names something this tree carries.
resolves() {
    if [ -e "$DIR/$2" ] || [ -e "$(source_root "$1")/$2" ]; then
        return 0
    fi
    seed_resolves "$2" "$1" && return 0
    return 1
}

# unshipped TOKEN — a reference into a directory the public export does not carry. Only skipped
# when the directory is genuinely absent, so a typo in this tree is still a finding.
unshipped() {
    case "$1" in
        apps/*)      [ ! -d "$DIR/apps" ] && return 0 ;;
    esac
    return 1
}

# allowlisted FILE TEXT — an explicit, reasoned exception.
allowlisted() {
    [ -f "$ALLOW" ] || return 1
    while IFS='|' read -r _path _needle _why; do
        case "$_path" in ''|'#'*) continue ;; esac
        [ "$_path" = "$1" ] || continue
        case "$2" in *"$_needle"*) return 0 ;; esac
    done < "$ALLOW"
    return 1
}

tmp="${TMPDIR:-/tmp}/check_comment_noise.$$"
trap 'rm -f "$tmp"' EXIT INT TERM
findings > "$tmp"

TAB=$(printf '\t')
files=0
bad=0
while IFS="$TAB" read -r file line kind text; do
    [ -n "${file:-}" ] || continue
    case "$kind" in
        private-doc)
            allowlisted "$file" "$text" && continue
            echo "[FAIL] comment-noise: $file:$line points at the private document '$text', which the export never carries"
            bad=$((bad + 1))
            ;;
        path)
            unshipped "$text" && continue
            resolves "$file" "$text" && continue
            allowlisted "$file" "$text" && continue
            echo "[FAIL] comment-noise: $file:$line references '$text', which the tree does not carry"
            bad=$((bad + 1))
            ;;
        *)
            allowlisted "$file" "$text" && continue
            echo "[FAIL] comment-noise: $file:$line is $kind: $text"
            bad=$((bad + 1))
            ;;
    esac
done < "$tmp"

files=$(scope_files | wc -l | tr -d ' ')
if [ "$bad" -gt 0 ]; then
    echo "[FAIL] comment-noise: $bad comment(s) in $files files break the policy (AGENTS.md, Source Comments)"
    exit 1
fi
echo "[PASS] comment-noise: $files files carry no scaffolding, step narration or stale path reference"

# Rule 3: the volume ratchet. Kept in the gate so one command covers the whole policy's
# mechanical half. Only this tree has a budget: a fixture directory is the selftest's, which
# checks the ratchet on its own.
if [ "$DIR" = "$REPO_ROOT" ] && [ -f "$CENSUS" ]; then
    sh "$CENSUS" --check "$DIR"
elif [ "$DIR" = "$REPO_ROOT" ]; then
    echo "[SKIP] comment-noise: scripts/comment_census.sh is not in this tree"
fi
