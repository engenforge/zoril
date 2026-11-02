#!/bin/sh
# scripts/check_safety_figures.sh -- produce the figures doc/SAFETY.md §5.3 quotes, and compare them with it.
#
# Why. §5 measures the trusted base - how much `unsafe` the standard library and the compiler carry - and
# its numbers had drifted from the tree twice: on 2026-10-19 it said 22 stdlib modules and 3,976 lines
# where the tree had 25 and 6,045, and 114 `unsafe { }` blocks where it had 163, with nothing to notice
# the move. Three different counting methods were in play (`wc -l` on a directory, `scripts/marker_density.sh`,
# and a hand count), and only one of them reproduced the figures the document was written with.
#
# The method, recovered by recounting the tree the document was last checked against, and
# stated beside the table in §5:
#
#   - every `.zrl` file, recursively, under the directory - subdirectories included;
#   - **lines**: physical lines, `wc -l` over the concatenated files (blank and comment lines count);
#   - **`unsafe { }` blocks**: occurrences of `unsafe` followed by `{` on the same line
#     (`unsafe[[:space:]]*{`), not lines, so two blocks on one line count twice; a block whose `{` is on
#     the next line is not counted, which is what the recovered `rg -o 'unsafe\s*\{'` did as well;
#   - **`unsafe fn` declarations**: lines that *start* with `unsafe fn` or `pub unsafe fn`, so a call to
#     one from inside a body is not counted (a plain text search gives 55 for the 52 the method finds);
#   - **modules**: files, not directories, so `src/driver/`'s parts each count.
#
# This is NOT what `scripts/marker_density.sh` counts: that script measures raw-pointer *dereferences*
# (`(*p)`, `&*p`) and prints a line density over non-comment LOC, which is 58 marker lines for `stdlib`
# and 264 for `src` - a different question (how much pointer work needs a boundary) from §5's (how many
# `unsafe` blocks exist). Both numbers are meaningful; they must not be compared with each other.
#
# Usage: check_safety_figures.sh [--print] [--repo DIR] [--doc FILE]
#        check_safety_figures.sh --density [--print] [--policy FILE]   (unsafe_policy.md §5 density rows)
#        check_safety_figures.sh --pages                                (example-application size, smoke-suite size)
#        check_safety_figures.sh --all                                  (selftest, §5, density, pages: the gate)
#        check_safety_figures.sh --selftest
# Exit: 0 every figure matches, 1 a figure differs or the table is missing, 2 usage.
set -u

SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
REPO=$(cd "$(dirname "$0")/.." && pwd)
DOC=""
PRINT=0
DENSITY=0
PAGES=0
POLICY=""
SELFTEST=0

die() { echo "usage: $0 [--print] [--repo DIR] [--doc FILE] | --selftest" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --print) PRINT=1; shift ;;
        --all) rc=0; for a in --selftest "" --density --pages; do "$0" $a || rc=1; done; exit $rc ;;
        --density) DENSITY=1; shift ;;
        --pages) PAGES=1; shift ;;
        --policy) [ $# -ge 2 ] || die; POLICY=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || die; REPO=$2; shift 2 ;;
        --doc) [ $# -ge 2 ] || die; DOC=$2; shift 2 ;;
        --selftest) SELFTEST=1; shift ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) die ;;
    esac
done
[ -n "$DOC" ] || DOC="$REPO/doc/SAFETY.md"

# A figure is checked where its source is in the tree. The public export carries neither the example
# application (not yet published) nor AGENTS.md, so those figures are not computed there instead of being
# computed from an absent directory and failing against a figure they cannot see.

# ── the counting method (stated above; §5 states the same in prose) ───────────────────────────────────
zrl_files() { find "$1" -type f -name '*.zrl' 2>/dev/null | LC_ALL=C sort; }
count_modules() { zrl_files "$1" | wc -l | tr -d ' '; }
count_lines() { zrl_files "$1" | while IFS= read -r f; do cat "$f"; done | wc -l | tr -d ' '; }
count_blocks() { zrl_files "$1" | while IFS= read -r f; do cat "$f"; done | grep -oE 'unsafe[[:space:]]*\{' | wc -l | tr -d ' '; }
count_block_modules() { zrl_files "$1" | while IFS= read -r f; do grep -qE 'unsafe[[:space:]]*\{' "$f" && echo "$f"; done | wc -l | tr -d ' '; }
count_unsafe_fn() { zrl_files "$1" | while IFS= read -r f; do cat "$f"; done | grep -cE '^[[:space:]]*(pub[[:space:]]+)?unsafe fn' | tr -d ' '; }
count_pub_unsafe_fn() { zrl_files "$1" | while IFS= read -r f; do cat "$f"; done | grep -cE '^[[:space:]]*pub[[:space:]]+unsafe fn' | tr -d ' '; }

# figures — one "label<TAB>value" line per row of the table in §5. The labels are the table's first
# column, so a label edit in the document has to be made here too (and the gate says which is missing).
figures() {
    printf 'stdlib modules\t%s\n'                  "$(count_modules "$REPO/stdlib")"
    printf 'stdlib lines\t%s\n'                    "$(count_lines "$REPO/stdlib")"
    printf 'stdlib `unsafe { }` blocks\t%s\n'      "$(count_blocks "$REPO/stdlib")"
    printf 'stdlib modules with such a block\t%s\n' "$(count_block_modules "$REPO/stdlib")"
    printf 'stdlib `unsafe fn` declarations\t%s\n' "$(count_unsafe_fn "$REPO/stdlib")"
    printf 'of those, public\t%s\n'                "$(count_pub_unsafe_fn "$REPO/stdlib")"
    printf 'compiler modules\t%s\n'                "$(count_modules "$REPO/src")"
    printf 'compiler lines\t%s\n'                  "$(count_lines "$REPO/src")"
    printf 'compiler `unsafe { }` blocks\t%s\n'    "$(count_blocks "$REPO/src")"
}

# ── the selftest: the three shapes the comparison has to tell apart ───────────────────────────────────
if [ "$SELFTEST" -eq 1 ]; then
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/safety-figures.XXXXXX") || exit 2
    trap 'rm -rf "$tmp"' EXIT
    fail=0
    mkdir -p "$tmp/t/src" "$tmp/t/stdlib" "$tmp/t/doc"
    printf 'fn a() {}\n' > "$tmp/t/stdlib/one.zrl"
    printf 'unsafe fn s() { unsafe { x(); } }\n' > "$tmp/t/stdlib/two.zrl"
    mkdir -p "$tmp/t/stdlib/sub"
    printf 'pub unsafe fn t() {}\n' > "$tmp/t/stdlib/sub/three.zrl"
    printf 'let a = unsafe { b() };\nlet c = unsafe { d() };\n' > "$tmp/t/src/main.zrl"
    wrote_table() {   # writes the document with the *current* figures of the fixture tree
        {
            echo '# Doc'
            echo
            echo '| Figure | Value |'
            echo '| --- | --- |'
            "$SELF" --repo "$tmp/t" --print | awk -F'\t' '{printf "| %s | %s |\n", $1, $2}'
            echo
        } > "$tmp/t/doc/SAFETY.md"
    }
    wrote_table
    if ! out=$("$SELF" --repo "$tmp/t" --doc "$tmp/t/doc/SAFETY.md" 2>&1); then
        echo "[FAIL] selftest: a matching table was refused"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi

    # One figure moving is reported as a mismatch, naming the row and both values.
    printf 'fn extra() {}\n' >> "$tmp/t/stdlib/one.zrl"
    out=$("$SELF" --repo "$tmp/t" --doc "$tmp/t/doc/SAFETY.md" 2>&1)
    if [ $? -eq 0 ]; then
        echo "[FAIL] selftest: a moved figure was accepted"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    elif ! printf '%s' "$out" | grep -q '^\[FAIL\].*stdlib lines'; then
        echo "[FAIL] selftest: a moved figure was not named"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi

    # A document with no table fails rather than passing vacuously.
    printf '# Doc\n\nNo table here.\n' > "$tmp/t/doc/SAFETY.md"
    if "$SELF" --repo "$tmp/t" --doc "$tmp/t/doc/SAFETY.md" > "$tmp/notable.log" 2>&1; then
        echo "[FAIL] selftest: a document with no figures table was accepted"; sed 's/^/       /' "$tmp/notable.log"; fail=1
    elif ! grep -q 'no `| Figure | Value |` table' "$tmp/notable.log"; then
        echo "[FAIL] selftest: the missing-table message did not say what to add"; sed 's/^/       /' "$tmp/notable.log"; fail=1
    fi

    # The counting method itself: two blocks on one line are two, and an `unsafe fn` call inside a body is
    # not a declaration.
    mkdir -p "$tmp/m/stdlib"
    printf 'let a = unsafe { b() }; let c = unsafe { d() };\n    unsafe_fn_call();\nunsafe fn real() {}\n' > "$tmp/m/stdlib/x.zrl"
    got=$("$SELF" --repo "$tmp/m" --print | grep -F 'stdlib `unsafe { }` blocks' | cut -f2)
    if [ "$got" != 2 ]; then
        echo "[FAIL] selftest: the block count is $got, expected 2 (two blocks on one line are two)"; fail=1
    fi
    got=$("$SELF" --repo "$tmp/m" --print | grep -F 'stdlib `unsafe fn` declarations' | cut -f2)
    if [ "$got" != 1 ]; then
        echo "[FAIL] selftest: the unsafe-fn count is $got, expected 1 (a call is not a declaration)"; fail=1
    fi

    # Density: the line holding `unsafe {`, the lines up to the matching `}`, and nothing else; comments and
    # blanks are not lines.
    mkdir -p "$tmp/d/src"
    printf '// c\n\nfn a() {\n    let x = unsafe { f() };\n    unsafe {\n        g(); // }\n        h();\n    }\n}\n' > "$tmp/d/src/a.zrl"
    got=$("$SELF" --repo "$tmp/d" --density --print | grep -F 'line counts' | cut -f2)
    case "$got" in
        "5 of 7 lines in \`src/\`"*) ;;
        *) echo "[FAIL] selftest: density counted \"$got\", expected 5 of 7 lines in \`src/\`"; fail=1 ;;
    esac

    if [ "$fail" -ne 0 ]; then
        echo "FAIL: the safety-figures check does not behave as its own documentation says."
        exit 1
    fi
    echo "[PASS] selftest: a matching table passes, a moved figure is named, a missing table fails, and the counting method counts occurrences and declarations"
    exit 0
fi

# ── density and the small pages (--density, --pages) ───────────────────────────────────────────────
# Density is a different instrument from the table above: *non-blank, non-comment lines that lie inside an
# `unsafe { }` block* (brace-matched, trailing `//` comments ignored, the line holding `unsafe {` and the
# line holding its closing `}` included), divided by non-blank, non-comment lines, over every `.zrl` file
# under the directory. It is the rule doc/spec/unsafe_policy.md §5 states. The Rust rows of that table were
# a one-time measurement and stay fixed; only the Zoril rows are recomputed.
density_awk() {
    awk '
        FNR == 1 { depth = 0; inb = 0 }
        {
            t = $0; sub(/^[ \t]+/, "", t)
            if (t == "" || t ~ /^\/\//) next
            total++
            line = $0; sub(/\/\/.*/, "", line)
            inside = inb
            n = length(line)
            for (i = 1; i <= n; i++) {
                if (!inb && substr(line, i) ~ /^unsafe[ \t]*\{/) {
                    inb = 1; depth = 1; inside = 1; i += index(substr(line, i), "{") - 1; continue
                }
                if (inb) {
                    c = substr(line, i, 1)
                    if (c == "{") depth++
                    else if (c == "}") { depth--; if (depth == 0) inb = 0 }
                }
            }
            if (inside) un++
        }
        END { printf "%d %d %.2f\n", un, total, (total ? 100 * un / total : 0) }'
}
fmt() { echo "$1" | awk '{ s = sprintf("%d", $1); out = ""; while (length(s) > 3) { out = "," substr(s, length(s) - 2) out; s = substr(s, 1, length(s) - 3) } print s out }'; }
density_row() {   # dir -> "U T PCT"
    zrl_files "$1" | tr '\n' '\0' | xargs -0 cat -- 2>/dev/null | density_awk
}
# --density prints "label<TAB>text" lines; each text must appear verbatim on the policy page.
density_figures() {
    s=$(density_row "$REPO/src"); l=$(density_row "$REPO/stdlib")
    set -- $s; su=$1; st=$2; sp=$3
    set -- $l; lu=$1; lt=$2; lp=$3
    printf 'src density\t**%s%%**\n' "$sp"
    printf 'stdlib density\t**%s%%**\n' "$lp"
    printf 'line counts\t%s of %s lines in `src/`, %s of %s in `stdlib/`\n' \
        "$(fmt $su)" "$(fmt $st)" "$(fmt $lu)" "$(fmt $lt)"
}
if [ "$DENSITY" -eq 1 ]; then
    if [ "$PRINT" -eq 1 ]; then density_figures; exit 0; fi
    POLICY=${POLICY:-$REPO/doc/spec/unsafe_policy.md}
    bad=0
    while IFS='	' read -r label text; do
        if ! grep -qF -- "$text" "$POLICY"; then
            echo "[FAIL] safety-figures: $POLICY does not carry \`$text\` ($label); run scripts/check_safety_figures.sh --density --print"
            bad=1
        fi
    done <<EOF
$(density_figures)
EOF
    [ "$bad" -ne 0 ] && exit 1
    echo "[PASS] safety-figures: the src/ and stdlib/ density rows of unsafe_policy.md §5 match the tree (Rust rows are a one-time measurement)"
    exit 0
fi
if [ "$PAGES" -eq 1 ]; then
    bad=0
    checked=""
    agent_file=""
    if [ -f "$REPO/AGENTS.md" ]; then
        agent_file="$REPO/AGENTS.md"
    elif [ -f "$REPO/CONTEXT.md" ]; then
        agent_file="$REPO/CONTEXT.md"
    fi
    if [ -n "$agent_file" ]; then
        smoke=$(grep -cvE '^[[:space:]]*(#|$)' "$REPO/tests/smoke.list")
        if ! grep -qF "(\`tests/smoke.list\`, $smoke tests" "$agent_file"; then
            echo "[FAIL] safety-figures: $(basename "$agent_file") does not say the smoke suite has $smoke tests"; bad=1
        fi
        checked="${checked:+$checked and }the smoke-suite size in $(basename "$agent_file")"
    else
        echo "[SKIP] safety-figures: this tree has no AGENTS.md/CONTEXT.md (it is not exported), so the smoke-suite size is not checked here"
    fi
    [ "$bad" -ne 0 ] && exit 1
    [ -z "$checked" ] || echo "[PASS] safety-figures: $checked match the tree"
    exit 0
fi

# ── print mode ───────────────────────────────────────────────────────────────────────────────────────
if [ "$PRINT" -eq 1 ]; then
    figures
    exit 0
fi

# ── the check ────────────────────────────────────────────────────────────────────────────────────────
if [ ! -f "$DOC" ]; then
    echo "[FAIL] safety-figures: $DOC does not exist, so the §5 figures cannot be checked"
    exit 1
fi
if ! grep -qE '^\| *Figure *\|' "$DOC"; then
    echo "[FAIL] safety-figures: $DOC has no \`| Figure | Value |\` table, so §5 quotes numbers no check can read"
    exit 1
fi

bad=0
checked=0
seen=""
while IFS='	' read -r label want; do
    seen="$seen$label
"
    checked=$((checked + 1))
    have=$(awk -v want="$label" -F'|' '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        trim($2) == want { print trim($3); exit }
    ' "$DOC")
    if [ -z "$have" ]; then
        echo "[FAIL] safety-figures: §5 has no row for '$label' (the script produces $want)"
        bad=1
        continue
    fi
    have_n=$(printf '%s' "$have" | tr -d ',')
    want_n=$(printf '%s' "$want" | tr -d ',')
    if [ "$have_n" != "$want_n" ]; then
        echo "[FAIL] safety-figures: §5 says $label is $have; the tree has $want"
        bad=1
    fi
done <<EOF
$(figures)
EOF

# A row in the table that the script does not produce is a figure with no source of record.
while IFS='|' read -r _ label _ rest; do
    label=$(printf '%s' "$label" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$label" in
        ''|'Figure'|*[!-]*) ;;   # blank, the header, or a real label
        *) continue ;;            # the | --- | --- | separator row
    esac
    [ -z "$label" ] && continue
    [ "$label" = "Figure" ] && continue
    if ! printf '%s' "$seen" | grep -qxF -- "$label"; then
        echo "[FAIL] safety-figures: §5's table has a row the script cannot produce: '$label' (add it to scripts/check_safety_figures.sh, or remove the row)"
        bad=1
    fi
done <<EOF
$(grep -E '^\| *[^|]+ *\|' "$DOC" | sed -n '/^| *Figure *|/,/^$/p')
EOF

if [ "$bad" -ne 0 ]; then
    echo "FAIL: doc/SAFETY.md §5.3 does not match the tree ($checked figure(s) compared)."
    exit 1
fi
echo "[PASS] safety-figures: all $checked §5 figure(s) match the tree (stdlib and src, .zrl files, physical lines, \`unsafe { }\` occurrences, \`unsafe fn\` declarations at line start)"
exit 0
