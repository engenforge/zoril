#!/bin/sh
# scripts/check_fuzz_fresh.sh -- does the release-bar fuzz record describe the compiler in this tree?
#
# Why. `bench/fuzz/README.md` carries a release-bar record - a budget of generated programs that compiled
# and ran, with no fault - and that record describes the compiler sources it ran on: `src/`, `stdlib/`,
# `tools/zilc/`, `tools/zbuild/` and `rt/`. Nothing compared the two afterwards. On 2026-10-19 the record was found to name
# a record naming two commits while 54 commits had changed `src/`, `stdlib/` or `rt/` and more had
# changed `tools/zilc/`, and every one of them had passed every gate; the record kept looking current
# through two documentation sweeps. A record that describes a compiler nobody can build is not evidence.
#
# The fingerprint is five hashes, one per compiler-source directory, over that directory's tracked
# blobs _minus Markdown_ (`scripts/lib/fuzz_fresh.sh` computes them; the harness prints the same line):
#
#     fingerprint: src=<h> stdlib=<h> tools/zilc=<h> tools/zbuild=<h> rt=<h>
#
# They are content-addressed: the same code gives the same hashes in any repository, so
# `scripts/export_public_release.sh` can run this gate in either tree - it copies those five
# directories out of git unchanged, and the exported tree's fresh single-commit repository has the
# same five hashes as the private HEAD. A code change changes them, which is deliberate: a changed
# compiler needs a new run, or a recorded decision that it does not. A page is not a compiler input,
# so a documentation-only change does not stale the record; the page half below still requires every
# page that quotes the record's figure to carry it.
#
# Two strengths, because the two readers need different answers:
#   - `make test` reports. Every compiler commit would otherwise turn the suite red until a 15-hour run
#     lands, which would make the gate the reason to skip the gate.
#   - `--strict` fails. `scripts/export_public_release.sh --record` uses it: that is the release being
#     recorded, and a release cannot be recorded on a record for other sources. Without `--record` the
#     export only warns, so routine `--skip-build` verification keeps working.
# A record with no fingerprint line, and a page that discusses the run without quoting the record's
# figure, fail at both strengths: those are drifts a one-line edit fixes, not a 15-hour wait.
#
# The page half is the second thing the review found. `doc/SAFETY.md` §7 requires every page quoting the
# record's figure to move in the same commit as the record; nothing enforced it. So every tracked
# Markdown file that says "compiled and ran" (the record's own phrase for its headline) must contain the
# record's headline figure. `doc/tasks/` is exempt: those files are the history of the runs, not claims
# about this tree, and they quote figures from many dates on purpose.
#
# Usage: check_fuzz_fresh.sh [--strict] [--repo DIR] [--record FILE]   (prints [PASS]/[FAIL]/[SKIP] items)
#        check_fuzz_fresh.sh --selftest
# Exit status: 0 current (or stale without --strict), 1 stale with --strict or a malformed record or a
# disagreeing page, 2 usage.
set -u

SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
REPO=$(cd "$(dirname "$0")/.." && pwd)
RECORD=""
STRICT=0

die() { echo "usage: $0 [--strict] [--repo DIR] [--record FILE] | --selftest" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --strict) STRICT=1; shift ;;
        --repo) [ $# -ge 2 ] || die; REPO=$2; shift 2 ;;
        --record) [ $# -ge 2 ] || die; RECORD=$2; shift 2 ;;
        --selftest) SELFTEST=1; shift ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        *) die ;;
    esac
done

[ -n "$RECORD" ] || RECORD="$REPO/bench/fuzz/README.md"

# ── the fingerprint ────────────────────────────────────────────────────────────────────────────────────
# One implementation, in lib/fuzz_fresh.sh, shared with the harness that prints the line. Sourced from
# this script's own directory: --repo names the tree being checked, which need not carry the scripts.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SELF_DIR/lib/portability.sh"
. "$SELF_DIR/lib/fuzz_fresh.sh"
. "$SELF_DIR/lib/tree_files.sh"
SCOPE=$(fuzz_fingerprint_scope | tr '\n' ' ')

current_fingerprint() {   # prints "src=<h> stdlib=<h> tools/zilc=<h> tools/zbuild=<h> rt=<h>", or nothing outside a git repo
    fuzz_fingerprint "$REPO" HEAD
}

# A record holds one or two entries, each a `## ` section with its own `fingerprint:` and `headline:` lines:
# the release-bar run, and - when the code changed after it and the launch could not wait for a new one - a
# short `--release` session on the launched code, marked by an `entry: short-session` line in its section.
# A section without an `entry:` line is the release-bar entry. The short session, when there is one, is
# the current entry: it is the one that describes this code, so it is the one --strict compares and the
# one every page must quote; the release-bar entry stays as the run on the previous code.
entry_field() {   # KIND FIELD: the FIELD line (fingerprint or headline) of the KIND entry, without the prefix
    [ -f "$RECORD" ] || return 0
    awk -v kind="$1" -v field="$2" '
        /^## / { cur = "release-bar" }
        NR == 1 { cur = "release-bar" }
        /^entry: / { cur = $2 }
        index($0, field ": ") == 1 && cur == kind { v = substr($0, length(field) + 3) }
        END { if (v != "") print v }' "$RECORD"
}

current_entry() {   # short-session when the record carries one, else release-bar
    if [ -f "$RECORD" ] && grep -q '^entry: short-session$' "$RECORD"; then echo short-session; else echo release-bar; fi
}

recorded_fingerprint() {  # prints the current entry's `fingerprint:` line, without the prefix
    entry_field "$(current_entry)" fingerprint
}

# ── the headline figure and the pages that quote it ───────────────────────────────────────────────────
headline_digits() {   # prints the current entry's headline number, digits only
    entry_field "$(current_entry)" headline | awk '{print $1}' | tr -d ','
}

with_commas() {
    printf '%s' "$1" | awk '{
        n = $0; s = ""
        while (length(n) > 3) { s = "," substr(n, length(n) - 2) s; n = substr(n, 1, length(n) - 3) }
        print n s
    }'
}

# Every Markdown page except the record itself and the task records that quote runs by date.
pages() {
    tree_files "$REPO" | grep '\.md$' | grep -v '^doc/tasks/' | grep -v '^bench/fuzz/README\.md$'
}

# ── the selftest: the three shapes this gate has to tell apart ────────────────────────────────────────
if [ "${SELFTEST:-0}" = 1 ]; then
    GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_GLOBAL
    GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_SYSTEM
    GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_NOSYSTEM
    unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
    for _v in $(env 2>/dev/null | sed -n 's/^\(GIT_CONFIG_[KEY|VALUE].*\)=.*/\1/p'); do
        unset "$_v"
    done
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/fuzz-fresh.XXXXXX") || exit 2
    trap 'rm -rf "$tmp"' EXIT
    fail=0
    g() { git -C "$tmp/t" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
    mkdir -p "$tmp/t/src" "$tmp/t/stdlib" "$tmp/t/tools/zilc" "$tmp/t/tools/zbuild" "$tmp/t/rt" "$tmp/t/doc"
    printf 'compiler\n' > "$tmp/t/src/main.zrl"
    printf 'stdlib\n' > "$tmp/t/stdlib/io.zrl"
    printf 'il\n' > "$tmp/t/tools/zilc/main.zrl"
    printf 'zbuild\n' > "$tmp/t/tools/zbuild/main.zrl"
    printf 'runtime\n' > "$tmp/t/rt/runtime.s"
    printf '# Record\n\nThe release-bar run: 1,000 programs compiled and ran.\n\nheadline: 1000 programs compiled and ran\n' > "$tmp/t/bench-fuzz-README.md"
    mkdir -p "$tmp/t/bench/fuzz"
    mv "$tmp/t/bench-fuzz-README.md" "$tmp/t/bench/fuzz/README.md"
    printf '# A page\n\nThe release bar was 1,000 programs that compiled and ran.\n' > "$tmp/t/doc/PAGE.md"
    g init -q -b main .
    g add -A
    g commit -q -m one
    fp() { printf 'fingerprint: %s\n' "$(fuzz_fingerprint "$tmp/t" HEAD)"; }

    # 1. A matching fingerprint passes, and so does a page quoting the same figure.
    { printf '%s\n' "$(fp)"; echo; cat "$tmp/t/bench/fuzz/README.md"; } > "$tmp/rec.$$"
    mv "$tmp/rec.$$" "$tmp/t/bench/fuzz/README.md"
    g add -A; g commit -q -m "record"
    if out=$("$SELF" --repo "$tmp/t" 2>&1) && printf '%s' "$out" | grep -q '^\[PASS\] fuzz-fresh: the release-bar record'; then
        case "$out" in
            *'STALE'*) echo "[FAIL] selftest: a matching fingerprint was reported stale"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1 ;;
            *) : ;;
        esac
    else
        echo "[FAIL] selftest: a matching fingerprint was not accepted"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    fi

    # 2. A Markdown-only change in a compiler directory leaves the record fresh: a page is not a
    #    compiler input. Then a code change is reported stale, naming the directory, and fails only
    #    under --strict.
    printf '# Notes\n\nNot a compiler input.\n' > "$tmp/t/src/NOTES.md"
    g add -A; g commit -q -m "src note"
    if ! "$SELF" --repo "$tmp/t" > "$tmp/note.log" 2>&1; then
        echo "[FAIL] selftest: a Markdown-only change in src/ staled the record"; sed 's/^/       /' "$tmp/note.log"; fail=1
    fi
    printf 'stdlib changed\n' > "$tmp/t/stdlib/io.zrl"
    g add -A; g commit -q -m "change stdlib"
    out=$("$SELF" --repo "$tmp/t" 2>&1)
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "[FAIL] selftest: a stale record failed a reporting run (exit $rc)"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    elif ! printf '%s' "$out" | grep -q 'STALE'; then
        echo "[FAIL] selftest: a stale record was not reported as STALE"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    elif ! printf '%s' "$out" | grep -q 'stdlib'; then
        echo "[FAIL] selftest: a stale record did not name the directory that moved"; printf '%s\n' "$out" | sed 's/^/       /'; fail=1
    else
        : # reported, not fatal: that is the shape `make test` needs
    fi
    "$SELF" --repo "$tmp/t" --strict > "$tmp/strict.log" 2>&1
    if [ $? -eq 0 ]; then
        echo "[FAIL] selftest: --strict did not fail a stale record"; sed 's/^/       /' "$tmp/strict.log"; fail=1
    elif ! grep -q '^\[FAIL\] fuzz-fresh: STALE' "$tmp/strict.log"; then
        echo "[FAIL] selftest: --strict failed without a [FAIL] item naming STALE"; sed 's/^/       /' "$tmp/strict.log"; fail=1
    fi

    # 3. A record with no fingerprint fails at both strengths.
    printf '# Record\n\nThe release-bar run: 1,000 programs compiled and ran.\n\nheadline: 1000 programs compiled and ran\n' > "$tmp/t/bench/fuzz/README.md"
    g add -A; g commit -q -m "no fingerprint"
    "$SELF" --repo "$tmp/t" > "$tmp/nofp.log" 2>&1
    if [ $? -eq 0 ] || ! grep -q 'carries no' "$tmp/nofp.log"; then
        echo "[FAIL] selftest: a record without a fingerprint was not refused"; sed 's/^/       /' "$tmp/nofp.log"; fail=1
    fi

    # 4. A page quoting a different figure fails, and names the page.
    { printf '%s\n' "$(fp)"; echo; cat "$tmp/t/bench/fuzz/README.md"; } > "$tmp/rec2.$$"
    mv "$tmp/rec2.$$" "$tmp/t/bench/fuzz/README.md"
    printf '# A page\n\nThe release bar was 1,500 programs that compiled and ran.\n' > "$tmp/t/doc/PAGE.md"
    g add -A; g commit -q -m "stale page"
    "$SELF" --repo "$tmp/t" > "$tmp/page.log" 2>&1
    if [ $? -eq 0 ] || ! grep -q 'doc/PAGE.md' "$tmp/page.log"; then
        echo "[FAIL] selftest: a page quoting another figure was not refused"; sed 's/^/       /' "$tmp/page.log"; fail=1
    fi
    printf '# A page\n\nThe release bar was 1,000 programs that compiled and ran.\n' > "$tmp/t/doc/PAGE.md"
    g add -A; g commit -q -m "page agrees"
    if ! "$SELF" --repo "$tmp/t" > "$tmp/page2.log" 2>&1; then
        echo "[FAIL] selftest: a page quoting the record's figure was refused"; sed 's/^/       /' "$tmp/page2.log"; fail=1
    fi

    # 6. A dual record: the release-bar entry on other code, and a short session on this code. The short session
    #    is the current entry: --strict passes on it, and a page quoting only the release-bar figure is named.
    printf '# Record\n\n## The release-bar run\n\nfingerprint: src=0 stdlib=0 tools/zilc=0 tools/zbuild=0 rt=0\n\nheadline: 1000 programs compiled and ran\n\n## The short session on the launched code\n\nentry: short-session\n\n%s\n\nheadline: 500 programs compiled and ran\n' "$(fp)" > "$tmp/t/bench/fuzz/README.md"
    g add -A; g commit -q -m "dual record"
    "$SELF" --repo "$tmp/t" --strict > "$tmp/dual.log" 2>&1
    if [ $? -eq 0 ] || ! grep -q 'doc/PAGE.md' "$tmp/dual.log" || ! grep -q '^\[PASS\] fuzz-fresh: the short-session record' "$tmp/dual.log"; then
        echo "[FAIL] selftest: a dual record did not compare its short session, or let a page quote the release-bar run alone"; sed 's/^/       /' "$tmp/dual.log"; fail=1
    fi
    printf '# A page\n\nThe release bar, 1,000 programs that compiled and ran, was met on the previous code; on this code a short session ran 500.\n' > "$tmp/t/doc/PAGE.md"
    g add -A; g commit -q -m "page pairs the runs"
    if ! "$SELF" --repo "$tmp/t" --strict > "$tmp/dual2.log" 2>&1; then
        echo "[FAIL] selftest: a dual record whose page quotes both runs was refused"; sed 's/^/       /' "$tmp/dual2.log"; fail=1
    fi
    sed 's/^fingerprint: src=[0-9a-f]\{8,\}/fingerprint: src=1/' "$tmp/t/bench/fuzz/README.md" > "$tmp/rec3.$$" && mv "$tmp/rec3.$$" "$tmp/t/bench/fuzz/README.md"
    g add -A; g commit -q -m "stale short session"
    "$SELF" --repo "$tmp/t" --strict > "$tmp/dual3.log" 2>&1
    if [ $? -eq 0 ] || ! grep -q 'STALE - the short-session record' "$tmp/dual3.log"; then
        echo "[FAIL] selftest: a stale short session passed --strict"; sed 's/^/       /' "$tmp/dual3.log"; fail=1
    fi

    # 5. A directory inside another repository is refused, not answered about that repository.
    mkdir -p "$tmp/t/src/sub"
    "$SELF" --repo "$tmp/t/src/sub" > "$tmp/sub.log" 2>&1
    if [ $? -ne 0 ] || ! grep -q 'not the root of its own git repository' "$tmp/sub.log"; then
        echo "[FAIL] selftest: a directory inside another repository was not refused"; sed 's/^/       /' "$tmp/sub.log"; fail=1
    fi

    if [ "$fail" -ne 0 ]; then
        echo "FAIL: the fuzz-record freshness gate does not behave as its own documentation says."
        exit 1
    fi
    echo "[PASS] selftest: a match passes, a Markdown-only change stays fresh, a code change is reported stale naming its directory and fails only under --strict, a record without a fingerprint is refused, a page with another figure is named, a dual record is judged by its short session and a page may not quote the release-bar run alone, and a directory inside another repository is not answered for it"
    exit 0
fi

# ── the gate ──────────────────────────────────────────────────────────────────────────────────────────
# A directory inside some *other* repository would answer every question about that repository, not about
# this tree: a not-yet-initialised export directory is exactly that, and it once made this gate report
# "0 page(s)" and a fingerprint it had not read. Require $REPO to be the root of its own repository.
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    top=$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)
    if [ -z "$top" ] || [ "$(cd "$top" && pwd -P)" != "$(cd "$REPO" && pwd -P)" ]; then
        echo "[SKIP] fuzz-fresh: $REPO is not the root of its own git repository, so its compiler sources cannot be read unambiguously"
        exit 0
    fi
fi
if [ ! -f "$RECORD" ]; then
    echo "[FAIL] fuzz-fresh: $RECORD does not exist, so the release-bar record cannot be checked"
    exit 1
fi

ENTRY=$(current_entry)
recorded=$(recorded_fingerprint)
if [ -z "$recorded" ]; then
    echo "[FAIL] fuzz-fresh: the record's $ENTRY entry carries no 'fingerprint: src=<h> stdlib=<h> tools/zilc=<h> tools/zbuild=<h> rt=<h>' line, so nothing ties it to the compiler code it describes (add the five hashes from the run's 'fuzz: pipeline: fingerprint:' line)"
    exit 1
fi

current=$(current_fingerprint)
if [ -z "$current" ]; then
    echo "[SKIP] fuzz-fresh: this tree has no HEAD to read the compiler sources from"
    exit 0
fi

rc=0
stale=""
for d in $SCOPE; do
    have=$(printf '%s\n' "$current" | tr ' ' '\n' | sed -n "s|^$d=||p")
    had=$(printf '%s\n' "$recorded" | tr ' ' '\n' | sed -n "s|^$d=||p")
    [ "$have" = "$had" ] && continue
    if [ -z "$had" ]; then
        stale="$stale$d (the record names no hash for it); "
        continue
    fi
    stale="$stale$d (its code differs); "
done
stale=${stale%; }

head=$(git -C "$REPO" rev-parse --short=8 HEAD 2>/dev/null || echo tarball)
if [ -z "$stale" ]; then
    echo "[PASS] fuzz-fresh: the $ENTRY record's fingerprint matches the code of src, stdlib, tools/zilc, tools/zbuild and rt at $head"
else
    if [ "$STRICT" -eq 1 ]; then
        echo "[FAIL] fuzz-fresh: STALE - the $ENTRY record describes other code than HEAD $head: $stale. Re-run the release-bar budget before citing the record, or record why the change needs no run."
        rc=1
    else
        echo "[PASS] fuzz-fresh: STALE - the $ENTRY record describes other code than HEAD $head: $stale. A release-bar run is owed before the record is cited; this is reported here and fails only under --strict."
    fi
fi

digits=$(headline_digits)
if [ -z "$digits" ]; then
    echo "[FAIL] fuzz-fresh: the record's $ENTRY entry carries no 'headline: <n> programs compiled and ran' line, so the pages that quote it cannot be compared"
    exit 1
fi
formatted=$(with_commas "$digits")
bad=""
checked=0
for page in $(pages); do
    [ -f "$REPO/$page" ] || continue
    grep -qi 'compiled and ran' "$REPO/$page" || continue
    checked=$((checked + 1))
    if ! grep -qF "$formatted" "$REPO/$page" && ! grep -qF "$digits" "$REPO/$page"; then
        bad="$bad$page "
    fi
done
if [ -n "$bad" ]; then
    echo "[FAIL] fuzz-fresh: page(s) discuss the run but do not quote the $ENTRY record's $formatted programs: ${bad% } - update them in the same commit as the record (doc/SAFETY.md section 7); a page may quote the release-bar run on the previous code too, but never alone"
    rc=1
else
    echo "[PASS] fuzz-fresh: every page that discusses the fuzz record quotes the $ENTRY record's $formatted programs ($checked page(s))"
fi

exit $rc
