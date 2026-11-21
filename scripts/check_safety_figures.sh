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
#        check_safety_figures.sh --probes [--print]                     (safety matrix probe counts)
#        check_safety_figures.sh --stamp [--doc FILE]                   (doc/SAFETY.md §5 "as of" stamp)
#        check_safety_figures.sh --pages                                (smoke-suite size)
#        check_safety_figures.sh --all                                  (selftest, stamp, pages: the make test gate)
#        check_safety_figures.sh --milestone                            (selftest, stamp, §5, density, probes, pages: release check)
#        check_safety_figures.sh --selftest
# Exit: 0 every figure matches, 1 a figure differs or the table is missing, 2 usage.
set -u

SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
REPO=$(cd "$(dirname "$0")/.." && pwd)
REPO_ARG=""
DOC=""
DOC_ARG=""
PRINT=0
DENSITY=0
PAGES=0
PROBES=0
STAMP=0
ALL=0
MILESTONE=0
POLICY=""
SELFTEST=0

die() { echo "usage: $0 [--print] [--repo DIR] [--doc FILE] | --all | --milestone | --selftest" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --print) PRINT=1; shift ;;
        --all) ALL=1; shift ;;
        --milestone) MILESTONE=1; shift ;;
        --stamp) STAMP=1; shift ;;
        --probes) PROBES=1; shift ;;
        --density) DENSITY=1; shift ;;
        --pages) PAGES=1; shift ;;
        --policy) [ $# -ge 2 ] || die; POLICY=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || die; REPO=$2; REPO_ARG="$2"; shift 2 ;;
        --doc) [ $# -ge 2 ] || die; DOC=$2; DOC_ARG="$2"; shift 2 ;;
        --selftest) SELFTEST=1; shift ;;
        -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
        *) die ;;
    esac
done
[ -n "$DOC" ] || DOC="$REPO/bench/safety_matrix/README.md"

run_sub() {
    if [ -n "$REPO_ARG" ] && [ -n "$DOC_ARG" ]; then
        "$0" --repo "$REPO_ARG" --doc "$DOC_ARG" "$@"
    elif [ -n "$REPO_ARG" ]; then
        "$0" --repo "$REPO_ARG" "$@"
    elif [ -n "$DOC_ARG" ]; then
        "$0" --doc "$DOC_ARG" "$@"
    else
        "$0" "$@"
    fi
}

if [ "$ALL" -eq 1 ]; then
    rc=0
    if [ "${SAFETY_FIGURES_IN_SELFTEST:-0}" -eq 0 ]; then
        run_sub --selftest || rc=1
    fi
    run_sub --stamp || rc=1
    run_sub --pages || rc=1
    exit $rc
fi

if [ "$MILESTONE" -eq 1 ]; then
    rc=0
    if [ "${SAFETY_FIGURES_IN_SELFTEST:-0}" -eq 0 ]; then
        run_sub --selftest || rc=1
    fi
    run_sub --stamp || rc=1
    run_sub || rc=1
    run_sub --density || rc=1
    run_sub --probes || rc=1
    run_sub --pages || rc=1
    exit $rc
fi

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
    mkdir -p "$tmp/t/src" "$tmp/t/stdlib" "$tmp/t/bench/safety_matrix"
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
        } > "$tmp/t/bench/safety_matrix/README.md"
    }
    wrote_table
    if ! out=$("$SELF" --repo "$tmp/t" --doc "$tmp/t/bench/safety_matrix/README.md" 2>&1); then
        echo "[FAIL] selftest: a matching table was refused"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi

    # One figure moving is reported as a mismatch, naming the row and both values.
    printf 'fn extra() {}\n' >> "$tmp/t/stdlib/one.zrl"
    out=$("$SELF" --repo "$tmp/t" --doc "$tmp/t/bench/safety_matrix/README.md" 2>&1)
    if [ $? -eq 0 ]; then
        echo "[FAIL] selftest: a moved figure was accepted"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    elif ! printf '%s' "$out" | grep -q '^\[FAIL\].*stdlib lines'; then
        echo "[FAIL] selftest: a moved figure was not named"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi

    # A document with no table fails rather than passing vacuously.
    printf '# Doc\n\nNo table here.\n' > "$tmp/t/bench/safety_matrix/README.md"
    if "$SELF" --repo "$tmp/t" --doc "$tmp/t/bench/safety_matrix/README.md" > "$tmp/notable.log" 2>&1; then
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

    # M1-M5: milestone figures, stamp, probe counts, and §5.3 prose sentences.
    mkdir -p "$tmp/m1/src" "$tmp/m1/stdlib" "$tmp/m1/bench/safety_matrix/probes" "$tmp/m1/tests"
    printf 'fn a() {}\n' > "$tmp/m1/stdlib/one.zrl"
    printf 'unsafe fn s() { unsafe { x(); } }\n' > "$tmp/m1/stdlib/two.zrl"
    printf 'let a = unsafe { b() };\n' > "$tmp/m1/src/main.zrl"
    printf '// expected: compile_reject\nfn f() {}\n' > "$tmp/m1/bench/safety_matrix/probes/p1.zrl"
    printf '// expected: accept\nfn g() {}\n' > "$tmp/m1/bench/safety_matrix/probes/p2.zrl"
    printf '// expected: known_gap\nfn h() {}\n' > "$tmp/m1/bench/safety_matrix/probes/p3.zrl"
    printf 'tests/a.zrl\n' > "$tmp/m1/tests/smoke.list"
    printf '(`tests/smoke.list`, 1 tests\n' > "$tmp/m1/AGENTS.md"
    printf 'and the 3-probe safety matrix across 1 rows.\n' > "$tmp/m1/README.md"
    write_m1_doc() {
        {
            echo '# Ledger'
            echo
            echo '## 1. Snapshot and Probe Counts'
            echo
            echo 'The counts in this ledger and the density rows are as of **0.1.0** (2026-11-15); they are refreshed at each release.'
            echo
            echo 'The repository keeps 3 probes in `bench/safety_matrix/probes/` (a 3-probe safety matrix), each recording its expectation in its first lines: **1 `compile_reject`**, **1 `accept`**, **0 `runtime_trap`**, **0 `runtime_fault`**, and **1 `known_gap`**.'
            echo
            echo '| Figure | Value |'
            echo '| --- | --- |'
            "$SELF" --repo "$tmp/m1" --print | awk -F'\t' '{printf "| %s | %s |\n", $1, $2}'
            echo
            echo '- **The standard library** holds 1 `unsafe { }` blocks in 1 of its 2 modules.'
            echo '- **The compiler** is 1 modules of Zoril, with 1 `unsafe { }` blocks.'
            echo
            "$SELF" --repo "$tmp/m1" --density --print | cut -f2
            echo
            echo '## 2. Known gaps'
            echo
            echo 'tracked as 1 `known_gap` probes'
        } > "$tmp/m1/bench/safety_matrix/README.md"
    }
    write_m1_doc
    if ! out=$(SAFETY_FIGURES_IN_SELFTEST=1 "$SELF" --repo "$tmp/m1" --milestone 2>&1); then
        echo "[FAIL] selftest: matching milestone fixture failed"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi

    # M1: a table figure that differs from the fixture tree: --all passes, --milestone fails and names the figure.
    printf 'fn added() {}\n' >> "$tmp/m1/src/main.zrl"
    if ! out=$(SAFETY_FIGURES_IN_SELFTEST=1 "$SELF" --repo "$tmp/m1" --all 2>&1); then
        echo "[FAIL] selftest M1: --all failed on moved table figure"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi
    out=$(SAFETY_FIGURES_IN_SELFTEST=1 "$SELF" --repo "$tmp/m1" --milestone 2>&1)
    if [ $? -eq 0 ] || ! printf '%s' "$out" | grep -q 'compiler lines'; then
        echo "[FAIL] selftest M1: --milestone did not fail naming compiler lines"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi
    write_m1_doc

    # M2: no stamp line -> --all fails with exact message.
    grep -v 'as of \*\*' "$tmp/m1/bench/safety_matrix/README.md" > "$tmp/m1/bench/safety_matrix/README.md.nostamp"
    mv "$tmp/m1/bench/safety_matrix/README.md.nostamp" "$tmp/m1/bench/safety_matrix/README.md"
    out=$(SAFETY_FIGURES_IN_SELFTEST=1 "$SELF" --repo "$tmp/m1" --all 2>&1)
    if [ $? -eq 0 ] || ! printf '%s' "$out" | grep -qF '[FAIL] safety-figures: bench/safety_matrix/README.md has no "as of" line'; then
        echo "[FAIL] selftest M2: missing stamp did not fail with expected message"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi

    # M3: stamp with no date -> same failure.
    write_m1_doc
    sed 's/ (2026-11-15)//' "$tmp/m1/bench/safety_matrix/README.md" > "$tmp/m1/bench/safety_matrix/README.md.nodate"
    mv "$tmp/m1/bench/safety_matrix/README.md.nodate" "$tmp/m1/bench/safety_matrix/README.md"
    out=$(SAFETY_FIGURES_IN_SELFTEST=1 "$SELF" --repo "$tmp/m1" --all 2>&1)
    if [ $? -eq 0 ] || ! printf '%s' "$out" | grep -qF '[FAIL] safety-figures: bench/safety_matrix/README.md has no "as of" line'; then
        echo "[FAIL] selftest M3: stamp without date did not fail with expected message"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi
    write_m1_doc

    # M4: a probe count by expectation that differs -> --milestone fails and names the kind.
    printf '// expected: accept\nfn g2() {}\n' > "$tmp/m1/bench/safety_matrix/probes/p4.zrl"
    out=$(SAFETY_FIGURES_IN_SELFTEST=1 "$SELF" --repo "$tmp/m1" --milestone 2>&1)
    if [ $? -eq 0 ] || ! printf '%s' "$out" | grep -q 'accept'; then
        echo "[FAIL] selftest M4: --milestone did not fail naming accept"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi
    rm -f "$tmp/m1/bench/safety_matrix/probes/p4.zrl"

    # M5: a §5.3 sentence that differs from its table row -> --milestone fails.
    sed 's/holds 1 `unsafe { }` blocks/holds 99 `unsafe { }` blocks/' "$tmp/m1/bench/safety_matrix/README.md" > "$tmp/m1/bench/safety_matrix/README.md.bad"
    mv "$tmp/m1/bench/safety_matrix/README.md.bad" "$tmp/m1/bench/safety_matrix/README.md"
    out=$(SAFETY_FIGURES_IN_SELFTEST=1 "$SELF" --repo "$tmp/m1" --milestone 2>&1)
    if [ $? -eq 0 ] || ! printf '%s' "$out" | grep -q '§5\.3'; then
        echo "[FAIL] selftest M5: --milestone did not fail on mismatched §5.3 sentence"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi
    write_m1_doc

    # M6: when known_gap is 0 ("No `known_gap` probes remain open"), --probes passes, and fails if a known_gap probe exists.
    sed 's/tracked as 1 `known_gap` probes/No `known_gap` probes remain open/' "$tmp/m1/bench/safety_matrix/README.md" > "$tmp/m1/bench/safety_matrix/README.md.zero"
    mv "$tmp/m1/bench/safety_matrix/README.md.zero" "$tmp/m1/bench/safety_matrix/README.md"
    out=$(SAFETY_FIGURES_IN_SELFTEST=1 "$SELF" --repo "$tmp/m1" --probes 2>&1)
    if [ $? -eq 0 ] || ! printf '%s' "$out" | grep -q '§6 says tracked as 0 known_gap probes; the tree has 1'; then
        echo "[FAIL] selftest M6: --probes did not fail when Known gaps says 0 but tree has 1"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi
    rm -f "$tmp/m1/bench/safety_matrix/probes/p3.zrl"
    sed 's/keeps 3 probes/keeps 2 probes/; s/3-probe safety matrix/2-probe safety matrix/; s/\*\*1 `known_gap`\*\*/\*\*0 `known_gap`\*\*/' "$tmp/m1/bench/safety_matrix/README.md" > "$tmp/m1/bench/safety_matrix/README.md.zero2"
    mv "$tmp/m1/bench/safety_matrix/README.md.zero2" "$tmp/m1/bench/safety_matrix/README.md"
    if ! out=$(SAFETY_FIGURES_IN_SELFTEST=1 "$SELF" --repo "$tmp/m1" --probes 2>&1); then
        echo "[FAIL] selftest M6: --probes failed when Known gaps says 0 and tree has 0"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi

    if [ "$fail" -ne 0 ]; then
        echo "FAIL: the safety-figures check does not behave as its own documentation says."
        exit 1
    fi
    echo "[PASS] selftest: a matching table passes, a moved figure is named, a missing table fails, the counting method counts occurrences and declarations, and M1-M5 pass"
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
    POLICY=${POLICY:-$REPO/bench/safety_matrix/README.md}
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
    echo "[PASS] safety-figures: the src/ and stdlib/ density rows of bench/safety_matrix/README.md match the tree (Rust rows are a one-time measurement)"
    exit 0
fi
if [ "$STAMP" -eq 1 ]; then
    if [ ! -f "$DOC" ]; then
        echo "[FAIL] safety-figures: $DOC does not exist"
        exit 1
    fi
    if ! grep -Eq 'as of \*\*[^*]+\*\* \([0-9]{4}-[0-9]{2}-[0-9]{2}\)' "$DOC"; then
        echo '[FAIL] safety-figures: bench/safety_matrix/README.md has no "as of" line'
        exit 1
    fi
    echo '[PASS] safety-figures: bench/safety_matrix/README.md carries an "as of" stamp'
    exit 0
fi

probe_counts() {
    _pdir="$REPO/bench/safety_matrix/probes"
    _tot=$(find "$_pdir" -maxdepth 1 -type f -name '*.zrl' 2>/dev/null | wc -l | tr -d ' ')
    _cr=0; _acc=0; _rt=0; _rf=0; _kg=0
    if [ "$_tot" -gt 0 ]; then
        eval "$(awk '/^\/\/ expected:/ { c[$3]++ } END {
            printf "_cr=%d _acc=%d _rt=%d _rf=%d _kg=%d\n",
                c["compile_reject"]+0, c["accept"]+0, c["runtime_trap"]+0, c["runtime_fault"]+0, c["known_gap"]+0
        }' "$_pdir"/*.zrl)"
    fi
    printf 'probes\t%s\n' "$_tot"
    printf 'compile_reject\t%s\n' "$_cr"
    printf 'accept\t%s\n' "$_acc"
    printf 'runtime_trap\t%s\n' "$_rt"
    printf 'runtime_fault\t%s\n' "$_rf"
    printf 'known_gap\t%s\n' "$_kg"
}

if [ "$PROBES" -eq 1 ]; then
    if [ "$PRINT" -eq 1 ]; then probe_counts; exit 0; fi
    bad=0
    eval "$(probe_counts | awk -F'\t' '{printf "p_%s=%s\n", $1, $2}')"
    if [ ! -f "$DOC" ]; then
        echo "[FAIL] safety-figures: $DOC does not exist"
        exit 1
    fi
    have=$(grep -oE 'keeps [0-9]+ probes' "$DOC" | head -n1 | grep -oE '[0-9]+' || true)
    if [ "$have" != "$p_probes" ]; then
        echo "[FAIL] safety-figures: §5.1 says keeps ${have:-missing} probes; the tree has $p_probes"
        bad=1
    fi
    for kind_pair in "compile_reject:$p_compile_reject" "accept:$p_accept" "runtime_trap:$p_runtime_trap" "runtime_fault:$p_runtime_fault" "known_gap:$p_known_gap"; do
        kind=${kind_pair%%:*}
        want=${kind_pair#*:}
        have=$(grep -oE "\*\*[0-9]+ \`$kind\`\*\*" "$DOC" | head -n1 | grep -oE '[0-9]+' || true)
        if [ "$have" != "$want" ]; then
            echo "[FAIL] safety-figures: §5.1 says ${have:-missing} $kind probes; the tree has $want"
            bad=1
        fi
    done
    have=$(grep -oE 'tracked as [0-9]+ `known_gap` probes' "$DOC" | head -n1 | grep -oE '[0-9]+' || true)
    if [ -z "$have" ] && grep -qF 'No `known_gap` probes remain open' "$DOC"; then
        have=0
    fi
    if [ "$have" != "$p_known_gap" ]; then
        echo "[FAIL] safety-figures: §6 says tracked as ${have:-missing} known_gap probes; the tree has $p_known_gap"
        bad=1
    fi
    have=$(grep -oE '[0-9]+-probe safety matrix' "$DOC" | head -n1 | grep -oE '^[0-9]+' || true)
    if [ "$have" != "$p_probes" ]; then
        echo "[FAIL] safety-figures: $DOC says ${have:-missing}-probe safety matrix; the tree has $p_probes"
        bad=1
    fi
    [ "$bad" -ne 0 ] && exit 1
    echo "[PASS] safety-figures: all probe counts in bench/safety_matrix/README.md match the tree ($p_probes probes)"
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
$(sed -n '/^| *Figure *|/,/^[[:space:]]*$/p' "$DOC" | grep -E '^\| *[^|]+ *\|')
EOF

# Check the two §5.3 prose sentences against the table's rows when present.
tbl_val() {
    awk -v want="$1" -F'|' '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        trim($2) == want { v = trim($3); gsub(/,/, "", v); print v; exit }
    ' "$DOC"
}
if grep -qF -- '**The standard library** holds ' "$DOC"; then
    s_line=$(grep -F -- '**The standard library** holds ' "$DOC" | head -n1)
    s_nums=$(printf '%s\n' "$s_line" | sed -n 's/.*holds \([0-9][0-9]*\) `unsafe { }` blocks in \([0-9][0-9]*\) of its \([0-9][0-9]*\) modules.*/\1 \2 \3/p')
    t_b=$(tbl_val 'stdlib `unsafe { }` blocks')
    t_bm=$(tbl_val 'stdlib modules with such a block')
    t_m=$(tbl_val 'stdlib modules')
    if [ "$s_nums" != "$t_b $t_bm $t_m" ]; then
        echo "[FAIL] safety-figures: §5.3 stdlib prose says ($s_nums); table has ($t_b $t_bm $t_m)"
        bad=1
    fi
fi
if grep -qF -- '**The compiler** is ' "$DOC"; then
    c_line=$(grep -F -- '**The compiler** is ' "$DOC" | head -n1)
    c_nums=$(printf '%s\n' "$c_line" | sed -n 's/.*is \([0-9][0-9]*\) modules of Zoril, with \([0-9][0-9]*\) `unsafe { }` blocks.*/\1 \2/p')
    t_cm=$(tbl_val 'compiler modules')
    t_cb=$(tbl_val 'compiler `unsafe { }` blocks')
    if [ "$c_nums" != "$t_cm $t_cb" ]; then
        echo "[FAIL] safety-figures: §5.3 compiler prose says ($c_nums); table has ($t_cm $t_cb)"
        bad=1
    fi
fi

if [ "$bad" -ne 0 ]; then
    echo "FAIL: bench/safety_matrix/README.md §3 does not match the tree ($checked figure(s) compared)."
    exit 1
fi
echo "[PASS] safety-figures: all $checked §5 figure(s) match the tree (stdlib and src, .zrl files, physical lines, \`unsafe { }\` occurrences, \`unsafe fn\` declarations at line start)"
exit 0
