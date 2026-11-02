#!/usr/bin/env bash
# scripts/check_safety_model.sh — verify the safety matrix (bench/safety_matrix/matrix.md): its "Proven by"
# column is truthful, that the GAP count in the prose of doc/spec/safety_model.md matches the rows
# actually marked **GAP**, and that the readable entries on that page equal the rows.
#
# The "Proven by" column is what makes every safety claim in that document
# falsifiable. Nothing verified it until now: 20 relative links were once broken
# in a single commit, and two rows cited a §11.2.5 that had never been written.
# The third time this drifts, the build should catch it. This script is pure
# grep-and-exit-code work against files that already exist (no compiler run), so
# it belongs in `make test` rather than `make preflight`.
#
# It fails when:
#   - a row has no "Proven by" citation (except the one legitimately marked N/A)
#   - a cited path does not exist
#   - a cited test is not a real test file (does not resolve to a .zrl under
#     tests/ or bench/safety_matrix/probes/)
#   - a cited §x.y.z has no matching section in doc/spec/surface_syntax.md
#   - the GAP count in the prose disagrees with the number of rows marked **GAP**,
#     or the prose's GAP name list does not match the marked rows
#   - any relative Markdown link in safety_model.md does not resolve
#
# Live pass/fail of the cited tests is enforced by the test suite itself
# (`make test` runs those tests directly); this script guarantees only that each
# citation points at a real, resolvable artifact — i.e. that the claim is
# checkable at all.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail=0
note() { echo "[FAIL] $*"; fail=1; }
ok()   { echo "[PASS] $*"; }

resolve_path() {
    if [ -d "$1" ]; then
        (cd "$1" && pwd -P)
    elif [ -e "$1" ]; then
        printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"
    fi
}

extract_links() {
    awk '
        /^ *(```|~~~)/ { in_fence = !in_fence; next }
        in_fence { next }
        {
            line = $0
            gsub(/`[^`]*`/, "", line)
            if (match(line, /^ *\[[^]]+\]:[ \t]+/)) {
                emit(substr(line, RSTART + RLENGTH))
                next
            }
            while (match(line, /\]\([^)]*\)/)) {
                emit(substr(line, RSTART + 2, RLENGTH - 3))
                line = substr(line, RSTART + RLENGTH)
            }
        }
        function emit(t) {
            sub(/^[ \t]+/, "", t)
            if (substr(t, 1, 1) == "<") {
                t = substr(t, 2)
                sub(/>.*/, "", t)
            } else {
                sub(/[ \t].*/, "", t)
            }
            sub(/#.*/, "", t)
            if (t == "" || t ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) return
            printf "%d\t%s\n", FNR, t
        }
    ' "$1"
}

check_doc_links() {
    doc_path="$1"
    check_root="${2:-$REPO_ROOT}"
    doc_file_dir="$(dirname "$doc_path")"
    case "$doc_path" in
        "$check_root"/*) doc_display="$(printf '%s' "$doc_path" | sed "s|^$check_root/||")" ;;
        *) doc_display="$(basename "$doc_path")" ;;
    esac

    LINKS="$(mktemp)"
    extract_links "$doc_path" > "$LINKS"
    broken=0
    while IFS='	' read -r line target; do
        [ -z "$line" ] && continue
        case "$target" in
            /*) target_path="$check_root$target" ;;
            *) target_path="$doc_file_dir/$target" ;;
        esac
        real="$(resolve_path "$target_path")"
        case "$real" in
            "$check_root" | "$check_root"/*) ;;
            *)
                note "$doc_display:$line: broken relative link: $target"
                broken=$((broken + 1))
                ;;
        esac
    done < "$LINKS"
    rm -f "$LINKS"
    if [ "$broken" -eq 0 ]; then
        ok "all relative links in $doc_display resolve"
    fi
}

check_normative_sentences() {
    target_file="$1"
    target_root="${2:-$REPO_ROOT}"
    case "$target_file" in
        "$target_root"/*) file_display="$(printf '%s' "$target_file" | sed "s|^$target_root/||")" ;;
        *) file_display="$(basename "$target_file")" ;;
    esac
    if [ ! -f "$target_file" ]; then
        note "normative sentence check: $target_file not found"
        return
    fi

    AWK_OUT="$(mktemp)"
    awk '
        BEGIN {
            count = 0; missing = 0;
        }
        /^ *(```|~~~)/ { in_fence = !in_fence; next }
        in_fence { next }
        /^#/ { next }
        # A readable entry mirrors a matrix row (check_entries_match), whose Proven by cell carries the citation.
        /^- \*\*.*\[side: [^]]*; evidence: [^]]*; probes: ([0-9]+|n\/a)\]\(\.\.\/\.\.\/bench\/safety_matrix\/matrix\.md\)$/ { flush_item(); next }

        /^[ \t]*$/ {
            flush_item()
            next
        }
        /^[ \t]*[-*][ \t]+/ || /^[ \t]*[0-9]+\.[ \t]+/ {
            flush_item()
            item = $0
            start_line = FNR
            next
        }
        {
            if (item == "") {
                item = $0
                start_line = FNR
            } else {
                item = item " " $0
            }
        }
        END {
            flush_item()
            print "TOTAL\t" count "\t" missing
        }

        function flush_item() {
            if (item == "") return
            check_item(item, start_line)
            item = ""
        }

        function check_item(raw, lno) {
            s = raw
            gsub(/\.zrl/, "@ZRL@", s)
            gsub(/\.md/, "@MD@", s)
            gsub(/\.\./, "@DOTS@", s)
            gsub(/e\.g\./, "e@EG@", s)
            gsub(/i\.e\./, "i@IE@", s)
            while (match(s, /[0-9]\.[0-9]/)) {
                s = substr(s, 1, RSTART) "@NUM@" substr(s, RSTART + 2)
            }

            if (raw ~ /^[ \t]*\|/) {
                check_sentence(raw, lno)
                return
            }

            n = split(s, parts, /[.!?][ \t]+/)
            for (i = 1; i <= n; i++) {
                sent = parts[i]
                gsub(/@ZRL@/, ".zrl", sent)
                gsub(/@MD@/, ".md", sent)
                gsub(/@DOTS@/, "..", sent)
                gsub(/e@EG@/, "e.g.", sent)
                gsub(/i@IE@/, "i.e.", sent)
                gsub(/@NUM@/, ".", sent)
                check_sentence(sent, lno)
            }
        }

        function check_sentence(sent, lno) {
            if (sent ~ /(only through [`"]?unsafe[`"]?|(^|[^A-Za-z0-9_])rejected([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_])non-null([^A-Za-z0-9_]|$))/) {
                count++
                has_test = (sent ~ /(\.zrl|(^|[^A-Za-z0-9_])tests\/[A-Za-z0-9_\/]+|(^|[^A-Za-z0-9_])probe[s]?[ \/][0-9]+)/)
                if (!has_test) {
                    missing++
                    printf "FAIL\t%d\t%s\n", lno, substr(sent, 1, 90)
                }
            }
        }
    ' "$target_file" > "$AWK_OUT" || { note "$file_display: awk could not scan the normative sentences"; rm -f "$AWK_OUT"; return; }

    file_missing=0
    file_total=0
    while IFS='	' read -r status arg1 arg2; do
        if [ "$status" = "FAIL" ]; then
            note "$file_display:$arg1: normative sentence has no test citation: $arg2"
            file_missing=1
        elif [ "$status" = "TOTAL" ]; then
            file_total="$arg1"
        fi
    done < "$AWK_OUT"
    rm -f "$AWK_OUT"

    if [ "$file_missing" -eq 0 ]; then
        ok "all normative safety sentences in $file_display cite tests ($file_total checked)"
    fi
}

list_normative_citations() {
    target_file="$1"
    target_root="${2:-$REPO_ROOT}"
    case "$target_file" in
        "$target_root"/*) file_display="$(printf '%s' "$target_file" | sed "s|^$target_root/||")" ;;
        *) file_display="$(basename "$target_file")" ;;
    esac
    if [ ! -f "$target_file" ]; then
        echo "normative sentence check: $target_file not found" >&2
        return
    fi

    AWK_OUT="$(mktemp)"
    awk '
        /^ *(```|~~~)/ { in_fence = !in_fence; next }
        in_fence { next }
        /^#/ { next }

        /^[ \t]*$/ {
            flush_item()
            next
        }
        /^[ \t]*[-*][ \t]+/ || /^[ \t]*[0-9]+\.[ \t]+/ {
            flush_item()
            item = $0
            start_line = FNR
            next
        }
        {
            if (item == "") {
                item = $0
                start_line = FNR
            } else {
                item = item " " $0
            }
        }
        END {
            flush_item()
        }

        function flush_item() {
            if (item == "") return
            check_item(item, start_line)
            item = ""
        }

        function check_item(raw, lno) {
            s = raw
            gsub(/\.zrl/, "@ZRL@", s)
            gsub(/\.md/, "@MD@", s)
            gsub(/\.\./, "@DOTS@", s)
            gsub(/e\.g\./, "e@EG@", s)
            gsub(/i\.e\./, "i@IE@", s)
            while (match(s, /[0-9]\.[0-9]/)) {
                s = substr(s, 1, RSTART) "@NUM@" substr(s, RSTART + 2)
            }

            if (raw ~ /^[ \t]*\|/) {
                check_sentence(raw, lno)
                return
            }

            n = split(s, parts, /[.!?][ \t]+/)
            for (i = 1; i <= n; i++) {
                sent = parts[i]
                gsub(/@ZRL@/, ".zrl", sent)
                gsub(/@MD@/, ".md", sent)
                gsub(/@DOTS@/, "..", sent)
                gsub(/e@EG@/, "e.g.", sent)
                gsub(/i@IE@/, "i.e.", sent)
                gsub(/@NUM@/, ".", sent)
                check_sentence(sent, lno)
            }
        }

        function check_sentence(sent, lno) {
            if (sent ~ /(only through [`"]?unsafe[`"]?|(^|[^A-Za-z0-9_])rejected([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_])non-null([^A-Za-z0-9_]|$))/) {
                printf "%d\t%s\n", lno, sent
            }
        }
    ' "$target_file" > "$AWK_OUT" || { echo "normative sentence check: awk could not scan $file_display" >&2; rm -f "$AWK_OUT"; return; }

    while IFS='	' read -r lno sent; do
        [ -n "$lno" ] || continue
        probes=$(printf '%s\n' "$sent" | grep -oE '[0-9]+_[A-Za-z0-9_]+\.zrl' | awk '!seen[$0]++' || true)
        if [ -n "$probes" ]; then
            echo "$file_display:$lno: $sent"
            for p in $probes; do
                probe_path="$REPO_ROOT/bench/safety_matrix/probes/$p"
                if [ -f "$probe_path" ]; then
                    name=$(grep '^// name:' "$probe_path" | head -n1 | sed 's|^// name:[[:space:]]*||')
                    echo "    probe: $p — $name"
                else
                    echo "    probe: $p (not found in probes/)"
                fi
            done
            echo ""
        fi
    done < "$AWK_OUT"
    rm -f "$AWK_OUT"
}

# ── banned safety phrases ──────────────────────────────────────────────────────
# Wording rules (doc/SAFETY.md, CONTRIBUTING.md): do not write "memory-safe", "guarantees memory
# safety", "eliminates", "prevents", "provably" or "no dangling pointers" without the tier and the
# test behind the claim. Every form of each word is matched (prevent/prevented/preventing, ...);
# the noun "memory safety" is not banned. Code spans, fenced blocks, link targets and quoted
# text ("...") are skipped, since a rule that names the words has to quote them. A line that must
# keep a phrase - another language's property, a defined category name - carries an explicit
# `<!-- allow-phrase: <reason> -->` on the line itself or on the line before; nothing is skipped
# by file or by topic, so a new claim cannot hide on a line that also names Rust.
#
# phrase_violations <file> <display name>: one "<display>:<line>: <text>" per violation.
phrase_violations() {
    awk -v file_disp="$2" '
        /^ *(```|~~~)/ { in_fence = !in_fence; prev_allow = 0; next }
        in_fence { next }
        {
            allow = prev_allow || ($0 ~ /<!--[ \t]*allow-phrase/)
            prev_allow = ($0 ~ /^[ \t]*<!--[ \t]*allow-phrase/)
            if (allow) next
            line = $0
            gsub(/`[^`]*`/, "", line)
            gsub(/\]\([^)]*\)/, "]", line)
            gsub(/"[^"]*"/, "", line)
            lower = tolower(line)
            if (lower ~ /memory[- ]safe([^t]|$)|guarantee[sd]? memory safety|eliminat(e|es|ed|ing)([^a-z]|$)|prevent(s|ed|ing)?([^a-z]|$)|provabl[ey]|no dangling pointer/)
                print file_disp ":" FNR ": " $0
        }
    ' "$1"
}

# phrases_selftest: the matcher on known lines, so a weakened pattern fails the gate itself.
phrases_selftest() {
    st_dir=$(mktemp -d "${TMPDIR:-/tmp}/zoril_phrases_selftest.XXXXXX") || return 2
    st_fail=0
    # Each of these must be reported (the first three were missed by the gate's first version).
    for bad in 'Unlike Rust, Zoril is memory-safe with no annotations.' \
               'Escape analysis is used to prevent local addresses from escaping.' \
               'Use-after-free bugs are eliminated at compile time.' \
               'Zoril provably rejects every dangling reference.' \
               'Zoril eliminates use-after-free.' \
               'The compiler guarantees memory safety.' \
               'There are no dangling pointers in safe code.'; do
        printf '%s\n' "$bad" > "$st_dir/doc.md"
        if [ -z "$(phrase_violations "$st_dir/doc.md" doc.md)" ]; then
            echo "[FAIL] phrases selftest: not reported: $bad"; st_fail=1
        fi
    done
    # Each of these must pass: the noun, a quoted rule, a code span, a fenced block, both marker forms.
    printf '%s\n' '## Memory safety' 'Zoril checks memory safety at compile time where it can.' \
        'Do not write "memory-safe" or "prevents" about Zoril.' 'The `eliminated` flag.' \
        '```' 'prevents' '```' 'Rust is memory-safe. <!-- allow-phrase: another language -->' \
        '<!-- allow-phrase: another language -->' 'Cyclone was a memory-safe dialect of C.' > "$st_dir/doc.md"
    out=$(phrase_violations "$st_dir/doc.md" doc.md)
    if [ -n "$out" ]; then echo "[FAIL] phrases selftest: false positive: $out"; st_fail=1; fi
    rm -rf "$st_dir"
    if [ "$st_fail" -eq 0 ]; then echo "[PASS] phrases selftest: 7 claims reported, 0 false positives"; fi
    return "$st_fail"
}

# Scope: the export set of Markdown files (scripts/export_public_release.sh --list-markdown).
check_banned_safety_phrases() {
    if [ -f "$REPO_ROOT/scripts/export_public_release.sh" ]; then
        md_files="$("$REPO_ROOT/scripts/export_public_release.sh" --list-markdown)"
    else
        md_files="$(cd "$REPO_ROOT" && find . -name .git -prune -o -name build -prune -o -name '*.md' -type f -print | sed 's|^\./||')"
    fi
    banned_violations=0
    for rel_path in $md_files; do
        [ -f "$REPO_ROOT/$rel_path" ] || continue
        while IFS= read -r vline; do
            [ -n "$vline" ] || continue
            note "banned safety phrase without the tier and test behind it (reword, or mark the line <!-- allow-phrase: reason -->): $vline"
            banned_violations=$((banned_violations + 1))
        done <<VIOLATIONS
$(phrase_violations "$REPO_ROOT/$rel_path" "$rel_path")
VIOLATIONS
    done
    if [ "$banned_violations" -eq 0 ]; then
        ok "no banned safety phrases across $(printf '%s\n' "$md_files" | wc -l | tr -d ' ') exported Markdown documents"
    fi
}

# ── The readable entries equal the matrix rows ────────────────────────────────
# doc/spec/safety_model.md lists every row as `- <property>: <claim> [side: ..; evidence: ..; probes: N](matrix link)`;
# the table itself is bench/safety_matrix/matrix.md. entries_expected writes the entry each row implies,
# entries_actual reads the entries from the page, and any difference (a row added, removed or edited on one
# side only) fails the gate.
entries_expected() {
    awk -F'|' '/^\| \*\*/ {
        for (i = 2; i <= 10; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i)
        n = 0; rest = $8; delete seen
        while (match(rest, /\]\([^)]*\)/)) {
            l = substr(rest, RSTART + 2, RLENGTH - 3); sub(/#.*/, "", l)
            if (!(l in seen)) { seen[l] = 1; n++ }
            rest = substr(rest, RSTART + RLENGTH)
        }
        # The page names the side plainly and drops the note in the cell, except (unchecked): that one marks a GAP row.
        side = $7; gsub(/\*\*/, "", side)
        if (side !~ /\(unchecked\)/) sub(/ \(.*\)/, "", side)
        ev = $10; probes = n
        if ($8 == "N/A") { ev = "n/a"; probes = "n/a" }
        prop = $2; sub(/\(§/, "(surface_syntax.md §", prop)
        printf "- %s: %s [side: %s; evidence: %s; probes: %s](../../bench/safety_matrix/matrix.md)\n", prop, $3, side, ev, probes
    }' "$1"
}
entries_actual() { grep -E '^- \*\*.*\[side: [^]]*; evidence: [^]]*; probes: ([0-9]+|n/a)\]\(\.\./\.\./bench/safety_matrix/matrix\.md\)$' "$1" || true; }
# BusyBox diff writes only the unified format, so read that: "< " is a line of $2 (the matrix) alone, "> " one of $1 (the page).
entries_diff() {
    ed_a=$(mktemp "${TMPDIR:-/tmp}/zoril_entries.XXXXXX") || return 2
    ed_b=$(mktemp "${TMPDIR:-/tmp}/zoril_entries.XXXXXX") || { rm -f "$ed_a"; return 2; }
    entries_expected "$2" > "$ed_a"
    entries_actual "$1" > "$ed_b"
    if [ ! -s "$ed_a" ]; then echo "< no rows read from $2"; fi
    diff -u "$ed_a" "$ed_b" | sed -n -e "/^--- /d" -e "/^+++ /d" -e "s/^-/< /p" -e "s/^+/> /p" | cut -c1-200
    rm -f "$ed_a" "$ed_b"
    return 0
}
check_entries_match() {
    ce_out=$(entries_diff "$1" "$2")
    if [ -z "$ce_out" ]; then
        ok "the readable entries equal the matrix rows ($(entries_actual "$1" | grep -c .))"
    else
        note "the readable entries differ from the matrix rows (< matrix, > page):"
        printf '%s\n' "$ce_out" | sed 's/^/    /'
    fi
}
# entries_selftest: a row edited in the matrix, a row dropped from the page, and an untouched pair.
entries_selftest() {
    es_dir=$(mktemp -d "${TMPDIR:-/tmp}/zoril_entries_selftest.XXXXXX") || return 2
    es_fail=0
    printf '%s\n' '| Property | Claim | M | L | B | Side | Proven by | Routes | Evidence |' \
        '| --- | --- | --- | --- | --- | --- | --- | --- | --- |' \
        '| **One** | claim one | m | l | b | safe | [`a.zrl`](../../a.zrl), [`b.zrl`](../../b.zrl) | - | example |' \
        '| **Two** | claim two | m | l | b | unsafe | [`c.zrl`](../../c.zrl) | - | routes |' \
        '| **Three** | claim three | m | l | b | safe (unchecked) | [`d.zrl`](../../d.zrl) | - | example |' > "$es_dir/matrix.md"
    printf '%s\n' '- **One**: claim one [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)' \
        '- **Two**: claim two [side: unsafe; evidence: routes; probes: 1](../../bench/safety_matrix/matrix.md)' \
        '- **Three**: claim three [side: safe (unchecked); evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)' > "$es_dir/page.md"
    [ -z "$(entries_diff "$es_dir/page.md" "$es_dir/matrix.md")" ] || { echo "[FAIL] entries selftest: a matching pair is reported"; es_fail=1; }
    sed 's/| routes |/| example |/' "$es_dir/matrix.md" > "$es_dir/edited.md"
    [ -n "$(entries_diff "$es_dir/page.md" "$es_dir/edited.md")" ] || { echo "[FAIL] entries selftest: an edited row is not reported"; es_fail=1; }
    sed '2d' "$es_dir/page.md" > "$es_dir/short.md"
    [ -n "$(entries_diff "$es_dir/short.md" "$es_dir/matrix.md")" ] || { echo "[FAIL] entries selftest: a dropped entry is not reported"; es_fail=1; }
    rm -rf "$es_dir"
    if [ "$es_fail" -eq 0 ]; then echo "[PASS] entries selftest: edited and dropped rows are reported, a matching pair (a GAP side kept) is not"; else fail=1; fi
}

if [ "${1:-}" = "--selftest" ]; then
    phrases_selftest || fail=1
    entries_selftest
    exit $fail
fi

if [ "${1:-}" = "--check-links-only" ]; then
    if [ $# -lt 2 ] || [ ! -f "$2" ]; then
        echo "usage: $0 --check-links-only <file> [root]" >&2
        exit 2
    fi
    target_doc="$2"
    target_root="${3:-$(dirname "$target_doc")}"
    check_doc_links "$target_doc" "$target_root"
    if [ "$fail" -ne 0 ]; then
        exit 1
    fi
    exit 0
fi

if [ "${1:-}" = "--check-normative-only" ]; then
    if [ $# -lt 2 ] || [ ! -f "$2" ]; then
        echo "usage: $0 --check-normative-only <file> [root]" >&2
        exit 2
    fi
    target_doc="$2"
    target_root="${3:-$(dirname "$target_doc")}"
    check_normative_sentences "$target_doc" "$target_root"
    if [ "$fail" -ne 0 ]; then
        exit 1
    fi
    exit 0
fi

if [ "${1:-}" = "--list-citations" ]; then
    if [ $# -ge 2 ] && [ -f "$2" ]; then
        list_normative_citations "$2" "${3:-$REPO_ROOT}"
    else
        list_normative_citations "$REPO_ROOT/doc/spec/safety_model.md" "$REPO_ROOT"
        list_normative_citations "$REPO_ROOT/bench/safety_matrix/matrix.md" "$REPO_ROOT"
        if [ -f "$REPO_ROOT/doc/spec/unsafe_policy.md" ]; then
            list_normative_citations "$REPO_ROOT/doc/spec/unsafe_policy.md" "$REPO_ROOT"
        fi
        if [ -f "$REPO_ROOT/doc/spec/surface_syntax.md" ]; then
            list_normative_citations "$REPO_ROOT/doc/spec/surface_syntax.md" "$REPO_ROOT"
        fi
    fi
    exit 0
fi

DOC="${1:-$REPO_ROOT/doc/spec/safety_model.md}"
MATRIX="${2:-$REPO_ROOT/bench/safety_matrix/matrix.md}"
SPEC="$REPO_ROOT/doc/spec/surface_syntax.md"
POLICY="$REPO_ROOT/doc/spec/unsafe_policy.md"

if [ ! -f "$DOC" ] || [ ! -f "$MATRIX" ]; then
    echo "Error: $DOC or $MATRIX not found." >&2
    exit 1
fi

# ── Parse the matrix rows ──────────────────────────────────────────────────────
# Data rows start with "| **". The columns are: property=$2, side=$7, proven by=$8,
# routes=$9, evidence=$10. The Side column was added 2026-09-27 when the safe/unsafe
# boundary landed; Routes and Evidence were added 2026-10-19 for the route-coverage
# evidence (bench/safety_matrix/matrix.md "Routes: what each row's evidence walks").
ROWS="$(mktemp)"
awk -F'|' '/^\| \*\*/ {
    prop=$2; pb=$8; routes=$9; ev=$10;
    gsub(/^[ \t]+|[ \t]+$/, "", prop);
    gsub(/^[ \t]+|[ \t]+$/, "", pb);
    gsub(/^[ \t]+|[ \t]+$/, "", routes);
    gsub(/^[ \t]+|[ \t]+$/, "", ev);
    print prop "\t" pb "\t" routes "\t" ev;
}' "$MATRIX" > "$ROWS"

total=0
gap=0
nacount=0
routes_rows=0
level_example=0
level_routes=0
level_fuzzed=0
level_argued=0
while IFS='	' read -r prop pb routes ev; do
    total=$((total + 1))
    is_gap=0
    case "$prop" in *"**GAP**"*) is_gap=1; gap=$((gap + 1)) ;; esac
    row=$(printf '%s' "$prop" | sed 's/ — \*\*GAP\*\*//; s/\*//g')
    fail_before=$fail
    fail=0

    # Evidence level vocabulary and its consistency with the Routes column.
    case "$ev" in
        example) level_example=$((level_example + 1)) ;;
        routes)  level_routes=$((level_routes + 1)) ;;
        fuzzed)  level_fuzzed=$((level_fuzzed + 1)) ;;
        argued)  level_argued=$((level_argued + 1)) ;;
        *) note "row '$prop' has unknown evidence level '$ev' (example|routes|fuzzed|argued)" ;;
    esac
    if [ "$ev" != "example" ] && { [ -z "$routes" ] || [ "$routes" = "-" ]; }; then
        note "row '$prop' claims evidence '$ev' but has no Routes list"
    fi
    if [ "$ev" = "example" ] && [ -n "$routes" ] && [ "$routes" != "-" ]; then
        note "row '$prop' lists routes but its evidence level is 'example'"
    fi
    if [ -n "$routes" ] && [ "$routes" != "-" ]; then routes_rows=$((routes_rows + 1)); fi

    # N/A is the one legitimate non-citation (Data Races: not applicable).
    if [ "$is_gap" -eq 0 ] && [ "$pb" = "N/A" ]; then
        # Not applicable: nothing to prove or to act on, so not an item.
        nacount=$((nacount + 1))
        fail=$fail_before
        continue
    fi
    if [ -z "$pb" ]; then
        note "row '$prop' has no Proven by citation"
        continue
    fi
    # Every citation must resolve to a real test artifact.
    links=$(printf '%s\n' "$pb" | grep -oE '\]\(([^)]+)\)' | sed -E 's/\]\(([^)]+)\)/\1/')
    if [ -z "$links" ]; then
        note "row '$prop' Proven by has no link: $pb"
        continue
    fi
    echo "$links" | sed -E 's|^\.\./\.\./|'"$REPO_ROOT"'/|; s|:[0-9]+(-[0-9]+)?$||' > "${ROWS}.links"
    gap_probe=0
    while read -r path; do
        if [ ! -f "$path" ]; then
            note "row '$prop' cites missing path: $path"
        elif ! printf '%s' "$path" | grep -qE '/(tests|bench/safety_matrix/probes)/.*\.zrl$'; then
            note "row '$prop' cites non-test file: $path"
        elif grep -q '^// expected: known_gap' "$path"; then
            gap_probe=1
        fi
    done < "${ROWS}.links"
    rm -f "${ROWS}.links"
    # A GAP row is recorded by a known_gap probe, which the safety matrix reports as a
    # skip; the row itself is a consistency check, so each gap is skipped once.
    if [ "$is_gap" -eq 1 ] && [ "$gap_probe" -eq 0 ]; then
        note "GAP row '$row' cites no known_gap probe"
    fi
    if [ "$fail" -eq 0 ]; then
        if [ "$is_gap" -eq 1 ]; then
            echo "[PASS] row '$row' (documented gap, recorded by its known_gap probe)"
        else
            echo "[PASS] row '$row' (proven by its cited tests)"
        fi
    fi
    [ "$fail_before" -eq 1 ] && fail=1
done < "$ROWS"

proven=$((total - gap - nacount))
printf '\nsafety model: %d rows — %d proven, %d GAP' "$total" "$proven" "$gap"
[ "$nacount" -gt 0 ] && printf ' (%d N/A)' "$nacount"
printf '\n'

# ── §x.y.z citations must have a matching section in surface_syntax.md ─────────
if [ -f "$SPEC" ]; then
    # Collect every heading number (e.g. "11.2.1") in surface_syntax.md.
    sections="$(grep -oE '^#{2,4}[ \t]+[0-9]+(\.[0-9]+)+' "$SPEC" | grep -oE '[0-9]+(\.[0-9]+)+' | sort -u)"
    missing=0
    for ref in $(grep -ohE '§[0-9]+\.[0-9]+(\.[0-9]+)?' "$DOC" "$MATRIX" | sed 's/§//' | sort -u); do
        if ! printf '%s\n' "$sections" | grep -qx "$ref"; then
            note "cited §$ref has no matching section in surface_syntax.md"
            missing=1
        fi
    done
    [ "$missing" -eq 0 ] && ok "all cited §x.y.z sections exist in surface_syntax.md"
else
    note "surface_syntax.md not found; skipping § checks"
fi

# ── GAP count in prose must match the marked rows ──────────────────────────────
# Prose: "Six rows above are marked **GAP**." and
#        "All six (null dereference, ..., stack exhaustion) are either ..."
word2num() {
    case "$1" in
        no|zero) echo 0 ;; one) echo 1 ;; two) echo 2 ;; three) echo 3 ;; four) echo 4 ;;
        five) echo 5 ;; six) echo 6 ;; seven) echo 7 ;; eight) echo 8 ;;
        nine) echo 9 ;; ten) echo 10 ;; eleven) echo 11 ;; twelve) echo 12 ;;
        *) echo "$1" ;;
    esac
}
prose_line=$(grep -iE '[0-9A-Za-z]+ rows? above (is|are) marked \*\*GAP\*\*' "$DOC" | head -n1 || true)
if [ -n "$prose_line" ]; then
    prose_word=$(printf '%s\n' "$prose_line" | tr 'A-Z' 'a-z' | grep -oE '^[0-9a-z]+' | head -n1)
    prose_count=$(word2num "$prose_word")
    if [ "$prose_count" != "$gap" ]; then
        note "prose says $prose_count GAP rows but $gap rows are marked **GAP**"
    else
        ok "GAP count in prose ($prose_count) matches marked rows"
    fi

    # The prose also names the GAP rows; verify they match the marked property
    # names. This reads a dedicated marker line rather than guessing at prose
    # shape. It used to key on "All <word> (...)", which meant that rewording the
    # summary -- to "Both (...)" for two rows, then to a single-row sentence --
    # silently skipped this check instead of failing it. A check that can be
    # turned off by an edit to the text it is checking is not a check.
    list_raw=$(grep -oE '^> \*\*GAP rows:\*\* .*' "$DOC" | head -n1 | sed -E 's/^> \*\*GAP rows:\*\* //' || true)
    if [ -z "$list_raw" ] && [ "$gap" -gt 0 ]; then
        note "no '> **GAP rows:** ...' line found, but $gap rows are marked **GAP**"
    elif [ -n "$list_raw" ]; then
        prose_list=$(printf '%s\n' "$list_raw" | tr 'A-Z' 'a-z' | tr ',' '\n' | sed -E 's/^[ \t]+|[ \t]+$//' | grep -v '^$')
        marked_list=$(awk -F'|' '/^\| \*\*.*GAP\*\*/ {
            prop=$2; gsub(/^[ \t]+|[ \t]+$/, "", prop);
            gsub(/—[ \t]*\*\*GAP\*\*.*/, "", prop);
            gsub(/\*\*/, "", prop);
            gsub(/^[ \t]+|[ \t]+$/, "", prop);
            print tolower(prop);
        }' "$MATRIX" | sort)
        prose_sorted=$(printf '%s\n' "$prose_list" | sort)
        if [ "$prose_sorted" != "$marked_list" ]; then
            note "GAP rows line does not match the rows marked **GAP**"
            echo "    listed:  $(echo "$prose_sorted" | tr '\n' ' ')"
            echo "    marked:  $(echo "$marked_list" | tr '\n' ' ')"
        else
            ok "GAP rows line matches the marked rows"
        fi
    fi
else
    note "could not find the 'N rows marked GAP' prose line"
fi

# ── Probe headers use the vocabulary the runner reads ─────────────────────────
# scripts/run_safety_matrix.sh understands four header lines: `// expected:` (one of five words), `// zbuild:` (a different outcome under an installed zbuild, with its reason),
# `// gap:` (a known_gap's reason) and `// observed:` (how an open hole shows itself: the fault
# itself, or the exit status a probe that returns the value it read ends with). A fourth spelling
# would be read as nothing at all, and the probe would quietly stop checking what it says it does -
# so the vocabulary is validated here rather than trusted.
probes_bad=0
for p in "$REPO_ROOT"/bench/safety_matrix/probes/*.zrl; do
    [ -f "$p" ] || continue
    pname=$(basename "$p")
    exp=$(sed -n 's|^// expected:[[:space:]]*||p' "$p" | head -n 1)
    case "$exp" in
        compile_reject|runtime_trap|runtime_fault|accept|known_gap) ;;
        *) note "probe $pname has no recognised '// expected:' header (found '${exp}')"; probes_bad=1 ;;
    esac
    obs=$(sed -n 's|^// observed:[[:space:]]*||p' "$p" | head -n 1)
    if [ -n "$obs" ]; then
        case "$obs" in
            runtime_fault) ;;
            exit\ [0-9]*) ;;
            *) note "probe $pname declares an unknown '// observed:' form '$obs' (runtime_fault, or 'exit <n>')"; probes_bad=1 ;;
        esac
        [ "$exp" = known_gap ] || { note "probe $pname declares '// observed:' but is not a known_gap"; probes_bad=1; }
    fi
    zb=$(sed -n 's|^// zbuild:[[:space:]]*||p' "$p" | head -n 1)
    if [ -n "$zb" ]; then
        case "$zb" in
            "compile_reject ("*")"|"accept ("*")"|"runtime_trap ("*")"|"runtime_fault ("*")") ;;
            *) note "probe $pname declares an unknown '// zbuild:' form '$zb' (<outcome> (<reason>))"; probes_bad=1 ;;
        esac
    fi
    if [ "$exp" = known_gap ] && ! grep -q '^// gap:' "$p"; then
        note "known_gap probe $pname has no '// gap:' reason"
        probes_bad=1
    fi
done
[ "$probes_bad" -eq 0 ] && ok "every probe header uses the vocabulary the safety-matrix runner reads"

# ── The Known gaps table lists exactly the known_gap probes ────────────────────
listed=$(awk '/^### Known gaps/ { on = 1; next } on && /^#/ { on = 0 } on' "$DOC" \
    | grep -oE 'bench/safety_matrix/probes/[A-Za-z0-9_]+\.zrl' | xargs -n1 basename 2>/dev/null | sort -u)
marked=$(grep -l '^// expected: known_gap' "$REPO_ROOT"/bench/safety_matrix/probes/*.zrl 2>/dev/null \
    | xargs -n1 basename 2>/dev/null | sort -u)
if [ "$listed" = "$marked" ]; then
    ok "Known gaps lists exactly the $(printf '%s\n' "$marked" | grep -c .) known_gap probes"
else
    for f in $(printf '%s\n' "$marked" | grep -vxF "$listed"); do note "known_gap probe $f is not listed under Known gaps"; done
    for f in $(printf '%s\n' "$listed" | grep -vxF "$marked"); do note "Known gaps lists $f, which is not a known_gap probe"; done
fi

# ── Test citations in why_zoril.md must exist ─────────────────────────────────
WHY="$REPO_ROOT/doc/vision/why_zoril.md"
if [ -f "$WHY" ]; then
    why_missing=0
    for t in $(grep -oE 'tests/[A-Za-z0-9_/]+\.zrl' "$WHY"); do
        if [ ! -f "$REPO_ROOT/$t" ]; then
            note "why_zoril.md cites nonexistent test: $t"
            why_missing=1
        fi
    done
    [ "$why_missing" -eq 0 ] && ok "all test citations in why_zoril.md exist"
fi

# ── All relative links in specification documents must resolve ───────────────
check_doc_links "$DOC" "$REPO_ROOT"
check_doc_links "$MATRIX" "$REPO_ROOT"
check_entries_match "$DOC" "$MATRIX"
if [ -f "$POLICY" ]; then
    check_doc_links "$POLICY" "$REPO_ROOT"
fi
if [ -f "$SPEC" ]; then
    check_doc_links "$SPEC" "$REPO_ROOT"
fi

# ── Normative safety sentences must cite tests ───────────────────────────────
check_normative_sentences "$DOC" "$REPO_ROOT"
check_normative_sentences "$MATRIX" "$REPO_ROOT"
if [ -f "$POLICY" ]; then
    check_normative_sentences "$POLICY" "$REPO_ROOT"
fi
if [ -f "$SPEC" ]; then
    check_normative_sentences "$SPEC" "$REPO_ROOT"
fi

# ── No public safe stdlib function takes a raw pointer it dereferences ────────
check_stdlib_raw_ptr_deref() {
    stdlib_dir="$REPO_ROOT/stdlib"
    if [ ! -d "$stdlib_dir" ]; then
        return
    fi
    violations=$(awk '
BEGIN { violations = 0 }
/^[ \t]*pub[ \t]+(unsafe[ \t]+)?fn[ \t]+/ {
    is_unsafe = ($0 ~ /^[ \t]*pub[ \t]+unsafe[ \t]+fn/)
    sig = $0
    sig_start_line = FNR
    while (sig !~ /\{/) {
        if ((getline next_line) <= 0) break
        sig = sig " " next_line
    }
    if (is_unsafe) next

    fn_name = ""
    if (match(sig, /fn[ \t]+[a-zA-Z0-9_]+/)) {
        fn_name = substr(sig, RSTART, RLENGTH)
        sub(/^fn[ \t]+/, "", fn_name)
    }
    if (fn_name ~ /^zoril_allocator_/) next

    p_start = index(sig, "(")
    p_end = index(sig, ")")
    if (p_start == 0 || p_end == 0 || p_end < p_start) next
    params_str = substr(sig, p_start + 1, p_end - p_start - 1)

    delete raw_params
    num_raw = 0
    n = split(params_str, p_list, ",")
    for (i = 1; i <= n; i++) {
        p = p_list[i]
        c_idx = index(p, ":")
        if (c_idx > 0) {
            pname = substr(p, 1, c_idx - 1)
            ptype = substr(p, c_idx + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", pname)
            gsub(/^[ \t]+|[ \t]+$/, "", ptype)
            if (ptype ~ /\*/) {
                raw_params[++num_raw] = pname
            }
        }
    }
    if (num_raw == 0) next

    brace_depth = 0
    brace_part = substr(sig, index(sig, "{"))
    for (c = 1; c <= length(brace_part); c++) {
        ch = substr(brace_part, c, 1)
        if (ch == "{") brace_depth++
        else if (ch == "}") brace_depth--
    }

    while (brace_depth > 0) {
        if ((getline body_line) <= 0) break
        for (c = 1; c <= length(body_line); c++) {
            ch = substr(body_line, c, 1)
            if (ch == "{") brace_depth++
            else if (ch == "}") brace_depth--
        }
        for (r = 1; r <= num_raw; r++) {
            param = raw_params[r]
            re1 = "(^|[^a-zA-Z0-9_])\\*[ \t]*" param "([^a-zA-Z0-9_]|$)"
            re2 = "(^|[^a-zA-Z0-9_])" param "\\.[a-zA-Z0-9_]"
            if (body_line ~ re1 || body_line ~ re2) {
                print FILENAME ":" FNR ": pub safe fn " fn_name " dereferences raw pointer param " param
                violations++
            }
        }
    }
}
END {
    if (violations > 0) exit 1
}
' "$stdlib_dir"/*.zrl)
    if [ $? -ne 0 ]; then
        note "public safe stdlib function dereferences raw pointer argument:"
        printf '%s\n' "$violations"
    else
        ok "no public safe stdlib function takes a raw pointer it dereferences"
    fi
}
check_stdlib_raw_ptr_deref

# ── the counts the documents state must match the matrix ───────────────────────
# README.md, doc/STABILITY.md and doc/vision/why_zoril.md each state a row count, the README also
# states a probe count, and the README says whether any row is marked **GAP**. Those are the numbers a
# reader sees first, and the reason this check exists is that "four open gaps" outlived two of the
# holes it counted: a count that drifts is invisible until someone reads it next to the matrix.
check_document_counts() {
    probe_files=$(ls "$REPO_ROOT"/bench/safety_matrix/probes/*.zrl 2>/dev/null | wc -l | tr -d ' ')
    readme="$REPO_ROOT/README.md"
    stab="$REPO_ROOT/doc/STABILITY.md"
    vision="$REPO_ROOT/doc/vision/why_zoril.md"

    n=$(grep -oE '[0-9]+-row safety matrix' "$readme" | head -n1 | grep -oE '^[0-9]+' || true)
    if [ "$n" = "$total" ]; then ok "README row count ($n) matches the matrix"
    else note "README says $n rows; the matrix has $total"; fi

    n=$(grep -oE '[0-9]+-probe safety matrix' "$readme" | head -n1 | grep -oE '^[0-9]+' || true)
    if [ "$n" = "$probe_files" ]; then ok "README probe count ($n) matches bench/safety_matrix/probes/"
    else note "README says $n probes; the probe directory holds $probe_files"; fi

    # The gap statement, in both directions: a closed gap must not still be claimed, and an open one
    # must not be hidden behind a stale sentence.
    if grep -qF 'No row is marked **GAP**' "$readme"; then
        if [ "$gap" -eq 0 ]; then ok "README states no row is marked **GAP**, and none is"
        else note "README says no row is marked **GAP**, but $gap row(s) are"; fi
    elif [ "$gap" -eq 0 ]; then
        note "no row is marked **GAP**, but the README does not say so"
    fi

    n=$(grep -oE 'All [0-9]+ rows are under continuous' "$stab" | grep -oE '[0-9]+' || true)
    if [ "$n" = "$total" ]; then ok "STABILITY row count ($n) matches the matrix"
    else note "STABILITY says $n rows; the matrix has $total"; fi

    n=$(grep -oE '\([0-9]+ rows at the time of writing' "$vision" | grep -oE '[0-9]+' || true)
    if [ "$n" = "$total" ]; then ok "why_zoril row count ($n) matches the matrix"
    else note "why_zoril says $n rows; the matrix has $total"; fi
}
check_document_counts

# ── verify public documents do not contain banned safety phrases ───────────────
phrases_selftest || fail=1
entries_selftest
check_banned_safety_phrases

# ── Evidence levels ────────────────────────────────────────────────────────────
# `routes` and above claim that step 3's gate passes for the row. `example` claims only
# that the cited probes fire the mechanism. The count is reported so a reader can see how
# much of the matrix rests on route evidence rather than on examples.
if [ "$routes_rows" -gt 0 ]; then
    if [ -x "$REPO_ROOT/scripts/check_route_coverage.sh" ]; then
        if "$REPO_ROOT/scripts/check_route_coverage.sh" > "$ROWS.routecov" 2>&1; then
            ok "route coverage passes for $routes_rows row(s) at level routes or higher"
        else
            note "route coverage failed for a row at level routes or higher:"
            grep '^\[FAIL\]' "$ROWS.routecov" | sed 's/^/    /'
        fi
        rm -f "$ROWS.routecov"
    else
        note "scripts/check_route_coverage.sh is missing; cannot verify the routes level"
    fi
fi
printf 'Evidence levels: %d routes, %d example, %d fuzzed, %d argued\n' \
    "$level_routes" "$level_example" "$level_fuzzed" "$level_argued"

rm -f "$ROWS"

if [ "$fail" -ne 0 ]; then
    echo "FAIL: safety_model.md is not self-consistent." >&2
    exit 1
fi
echo "PASS: safety_model.md is self-consistent."
