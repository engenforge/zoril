#!/bin/sh
# scripts/fuzz/record_update.sh -- after a clean budget run, write its numbers into the record.
#
#   make fuzz-record-update RUN=release-<name>
#
# Rewrites the numbers only: the `fingerprint:` and `headline:` lines and the figure bullets of the
# release-bar section of bench/fuzz/README.md, and the old headline figure on every page that quotes it
# (the pages scripts/check_fuzz_fresh.sh knows). Then runs `check_fuzz_fresh.sh --strict` and prints the
# diff. The prose - what changed since the last record, the classification of the listed differences,
# the launch line, the notes - stays a person's job, and this lists the paragraphs to re-read.
#
# It refuses, writing nothing, unless the run is a clean finished one (no fault, candidate, generator
# bug, expired entry, open known hole, or known hole faulting with its switch off; its compiled-and-ran
# target met) and unless the code it ran on is the code in this tree: a run's fingerprint that
# check_fuzz_fresh.sh calls stale is a run for another compiler, and recording it would put a claim in
# the record that this tree does not support.
#
# `--short-session` records a finished `--release` session (`make fuzz-session ... RELEASE=1`, no target) on the
# code being launched, beside the release-bar run that was met on earlier code: it writes, or replaces, the
# section "The short session on the launched code" (`entry: short-session`, its own fingerprint and headline),
# which `check_fuzz_fresh.sh` then treats as the current entry. The release-bar section is not touched, and
# the pages are left to a person, because each must say which run and which code a figure describes. A later
# full release-bar run, recorded without the flag, removes that section again.
#
# Usage: record_update.sh [--run RUN] [--short-session] [--record FILE] [--repo DIR] [--no-strict]
set -u
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO_ROOT/scripts/lib/fuzz_run.sh"
RUN=""; RECORD="$REPO_ROOT/bench/fuzz/README.md"; REPO="$REPO_ROOT"; STRICT=1; SHORT=0
SHORT_HEADING="## The short session on the launched code"
while [ $# -gt 0 ]; do
    case "$1" in
        --run) RUN=$2; shift 2 ;;
        --record) RECORD=$2; shift 2 ;;
        --repo) REPO=$2; shift 2 ;;
        --no-strict) STRICT=0; shift ;;
        --short-session) SHORT=1; shift ;;
        -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
        *) echo "fuzz: unknown argument $1" >&2; exit 2 ;;
    esac
done
refuse() { echo "fuzz-record-update: refusing: $1" >&2; exit 1; }
if [ -z "$RUN" ] && [ "$SHORT" -eq 0 ]; then RUN=$(ls -d "$FUZZ_ROOT"/release-*/ 2>/dev/null | tail -n 1); fi
DIR=$(fuzz_run_dir "$RUN") || { echo "fuzz: no such run (pass RUN=release-<name>)" >&2; exit 2; }
[ -f "$RECORD" ] || { echo "fuzz: no record at $RECORD" >&2; exit 2; }

[ "$(run_state "$DIR")" = finished ] || refuse "$DIR is $(run_state "$DIR"), not a finished run"
if [ "$SHORT" -eq 1 ]; then
    [ "$(kv "$DIR/run.status" release)" = 1 ] || refuse "$DIR was not run with --release (RELEASE=1), so nothing checked its tree, binaries or rustc"
fi
SUMMARY=$("$REPO_ROOT/scripts/fuzz/summary.sh" --run "$DIR" --format record)
case "$SUMMARY" in "<!-- partial"*) refuse "$DIR has no totals lines (a stopped run is never recorded)" ;; esac
field() { printf '%s\n' "$SUMMARY" | awk -v lab="- **$1:** " 'index($0, lab) == 1 { print substr($0, length(lab) + 1); exit }'; }
num() { printf '%s\n' "$1" | sed 's/\*//g' | grep -o '[0-9][0-9,]*' | head -1 | tr -d ','; }
[ "$(num "$(field 'Faults')")" = 0 ] || refuse "the run has faults"
[ "$(num "$(field '`rustc` candidates')")" = 0 ] || refuse "the run has rustc candidates"
[ "$(num "$(field 'Generator bugs (`[GEN-BUG]`)')")" = 0 ] || refuse "the run has generator bugs"
[ "$(num "$(field 'Expired allowlist entries')")" = 0 ] || refuse "the run has expired allowlist entries"
printf '%s\n' "$SUMMARY" | grep -q 'MET\|^- \*\*Known holes.*\*\*0 still open\*\*' || true
printf '%s\n' "$SUMMARY" | grep -q '\*\*0 still open\*\*' || refuse "a known hole is still open"
printf '%s\n' "$SUMMARY" | grep -q '\*\*0 faulted with the switch off\*\*' || refuse "a known hole faulted with its switch off"
target=$(kv "$DIR/run.status" ran_target); ran=$(printf '%s\n' "$SUMMARY" | sed -n 's/^headline: \([0-9]*\) programs.*/\1/p')
if [ "$SHORT" -eq 0 ]; then
    [ -n "$target" ] && [ "$target" -gt 0 ] || refuse "the run set no compiled-and-ran target"
    [ "$ran" -ge "$target" ] || refuse "the run compiled and ran $ran, under its target $target"
fi

# The run's sources against this tree: check_fuzz_fresh.sh's own verdict on a record that carries the run's
# fingerprint.
fp=$(printf '%s\n' "$SUMMARY" | sed -n 's/^fingerprint: //p' | head -1)
[ -n "$fp" ] && [ "$fp" != unavailable ] || refuse "the run recorded no fingerprint"
tmp=$(mktemp "${TMPDIR:-/tmp}/zfuzz.rec.XXXXXX")
printf 'fingerprint: %s\n\nheadline: %s programs compiled and ran\n' "$fp" "$ran" > "$tmp"
verdict=$("$REPO_ROOT/scripts/check_fuzz_fresh.sh" --repo "$REPO" --record "$tmp" 2>&1 | grep -i 'STALE\|fingerprint' | head -1)
rm -f "$tmp"
case "$verdict" in *STALE*) refuse "the sources moved since the run: $verdict" ;; esac

# drop_short FILE -- FILE without the short-session section (its heading up to the next `## ` heading).
drop_short() {
    awk -v h="$SHORT_HEADING" '$0 == h { skip = 1; next } skip && /^## / { skip = 0 } !skip { print }' "$1"
}

if [ "$SHORT" -eq 1 ]; then
    first=$(kv "$DIR/run.status" first); last=$(kv "$DIR/run.status" lastseed)
    tmps=$(mktemp "${TMPDIR:-/tmp}/zfuzz.short.XXXXXX")
    {
        echo "$SHORT_HEADING"
        echo
        echo "The release bar above was met on earlier code: its fingerprint differs from this one. This shorter \`--release\` session ran on the code released here, with every oracle of the release-bar run and the mode-diff reading on. It is a short session, not the release bar; a full release-bar run on this code is planned soon, and when it is recorded it replaces this section."
        echo
        echo "entry: short-session"
        echo
        printf '%s\n' "$SUMMARY" | sed -n '/^fingerprint: /p'
        echo
        printf '%s\n' "$SUMMARY" | sed -n '/^headline: /p'
        echo
        echo "Launched as \`make fuzz-session SEEDS=$first-$last RELEASE=1\`."
        echo
        printf '%s\n' "$SUMMARY" | sed -n '/^- \*\*/p'
        echo
    } > "$tmps"
    tmpr=$(mktemp "${TMPDIR:-/tmp}/zfuzz.rec3.XXXXXX")
    drop_short "$RECORD" | awk -v sec="$tmps" '
        /^## Findings$/ && !done { while ((getline l < sec) > 0) print l; done = 1 }
        { print }
        END { if (!done) { print ""; while ((getline l < sec) > 0) print l } }' > "$tmpr"
    cp "$tmpr" "$RECORD"; rm -f "$tmpr" "$tmps"
    echo "fuzz-record-update: wrote $(basename "$DIR") into $RECORD as the short session on the launched code"
    git -C "$REPO" diff --stat -- bench/fuzz/README.md 2>/dev/null | tail -n 3
    echo
    echo "fuzz-record-update: the pages are yours: each one that quotes the release-bar figure must now quote this"
    echo "  session's $(fmt_num "$ran") as well, and say which run and which code each figure describes"
    echo "  (doc/SAFETY.md section 5.2, README's fuzzing sentence); check_fuzz_fresh.sh names any it misses."
    if [ "$STRICT" -eq 1 ]; then
        "$REPO_ROOT/scripts/check_fuzz_fresh.sh" --repo "$REPO" --record "$RECORD" --strict || {
            echo "fuzz-record-update: check_fuzz_fresh.sh --strict does not pass yet (see above)" >&2; exit 1; }
    fi
    exit 0
fi

# A full release-bar run replaces a short session: its section goes, and its headline is the one the pages
# quoted.
old=$(sed -n 's/^headline: \([0-9]*\) programs compiled and ran.*/\1/p' "$RECORD" | tail -1)
tmpd=$(mktemp "${TMPDIR:-/tmp}/zfuzz.rec4.XXXXXX")
drop_short "$RECORD" > "$tmpd"; cp "$tmpd" "$RECORD"; rm -f "$tmpd"
fmt() { fmt_num "$1"; }
tmpr=$(mktemp "${TMPDIR:-/tmp}/zfuzz.rec2.XXXXXX")
awk -v summary="$SUMMARY" '
function newnum(label,   i, n, lines, l, v) {
    n = split(summary, lines, "\n")
    for (i = 1; i <= n; i++) { l = lines[i]; if (index(l, "- **" label ":**") == 1) { sub(/^- \*\*[^:]*:\*\* /, "", l); return l } }
    return ""
}
function firstnum(s) { if (match(s, /[0-9][0-9,]*/)) return substr(s, RSTART, RLENGTH); return "" }
function replace_first_number(line, label,   v, pre, post, m) {
    v = firstnum(newnum(label)); if (v == "") return line
    m = index(line, ":**"); pre = substr(line, 1, m + 2); post = substr(line, m + 3)
    if (match(post, /[0-9][0-9,]*/)) post = substr(post, 1, RSTART - 1) v substr(post, RSTART + RLENGTH)
    return pre post
}
/^fingerprint: / { n = split(summary, L, "\n"); for (i = 1; i <= n; i++) if (L[i] ~ /^fingerprint: /) { print L[i]; next } }
/^headline: / { n = split(summary, L, "\n"); for (i = 1; i <= n; i++) if (L[i] ~ /^headline: /) { print L[i]; next } }
/^- \*\*Seeds:\*\*/ || /^- \*\*Wall time:\*\*/ {
    split($0, a, ":\\*\\*"); lab = a[1]; sub(/^- \*\*/, "", lab)
    v = newnum(lab); if (v != "") { print "- **" lab ":** " v; next }
}
/^- \*\*Programs generated:\*\*/ { print replace_first_number($0, "Programs generated"); next }
/^- \*\*Compiled and ran:\*\*/ { line = replace_first_number($0, "Compiled and ran"); p = newnum("Compiled and ran"); if (match(p, /\([0-9.]+%\)/)) { pp = substr(p, RSTART, RLENGTH); sub(/\([0-9.]+%\)/, pp, line) } print line; next }
/^- \*\*Rejected by Zoril:\*\*/ { print replace_first_number($0, "Rejected by Zoril"); next }
/^- \*\*Traps/ { v = newnum("Traps"); if (v != "") { print "- **Traps:** " v; next } }
/^- \*\*Faults:\*\*/ { print replace_first_number($0, "Faults"); next }
/^- \*\*`rustc` candidates:\*\*/ { print replace_first_number($0, "`rustc` candidates"); next }
/^- \*\*Generator bugs/ { print replace_first_number($0, "Generator bugs (`[GEN-BUG]`)"); next }
/^- \*\*Expired allowlist entries:\*\*/ { print replace_first_number($0, "Expired allowlist entries"); next }
/^- \*\*Listed differences/ { print replace_first_number($0, "Listed differences (`[DIFF]`)"); next }
/^- \*\*Infer-diffs/ { print replace_first_number($0, "Infer-diffs (`[INFER-DIFF]`)"); next }
/^- \*\*Feature coverage:\*\*/ { v = newnum("Feature coverage"); if (v != "") { print "- **Feature coverage:** " v; next } }
{ print }
' "$RECORD" > "$tmpr"
cp "$tmpr" "$RECORD"; rm -f "$tmpr"

# Every other page that quotes the old headline.
pages=""
if [ -n "$old" ] && [ "$old" != "$ran" ]; then
    for f in $(git -C "$REPO" ls-files '*.md' | grep -v '^doc/tasks/'); do
        [ -f "$REPO/$f" ] || continue
        [ "$REPO/$f" = "$RECORD" ] && continue
        if grep -q "$(fmt "$old")\|$old" "$REPO/$f" 2>/dev/null; then
            replace_number "$REPO/$f" "$(fmt "$old")" "$(fmt "$ran")"
            replace_number "$REPO/$f" "$old" "$ran"
            pages="$pages $f"
        fi
    done
fi
echo "fuzz-record-update: wrote the numbers of $(basename "$DIR") into $RECORD"
[ -n "$pages" ] && echo "fuzz-record-update: moved the headline figure on:$pages"
git -C "$REPO" diff --stat -- bench/fuzz/README.md $pages 2>/dev/null | tail -n 12
echo
echo "fuzz-record-update: re-read these by hand (they hold prose, not just numbers):"
echo "  - the section heading's date and the paragraph that says how the run was launched and when"
echo "  - 'Oracles', 'Mismatch stream', 'Known holes', 'Audited [DIFF] sample' and every 'Notes on the record' bullet"
echo "  - doc/SAFETY.md section 5.2, and the percent-over-the-bar figure in the Compiled and ran bullet"
if [ "$STRICT" -eq 1 ]; then
    "$REPO_ROOT/scripts/check_fuzz_fresh.sh" --repo "$REPO" --record "$RECORD" --strict || {
        echo "fuzz-record-update: check_fuzz_fresh.sh --strict does not pass yet (see above)" >&2; exit 1; }
fi
