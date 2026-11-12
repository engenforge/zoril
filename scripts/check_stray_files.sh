#!/bin/sh
# scripts/check_stray_files.sh — record the untracked paths a test run starts with, and report
# the ones the run added.
#
# A test run keeps its output under build/. A file it writes into a tracked directory is a
# defect whether or not a .gitignore pattern hides it: the next `git add -A` would commit it.
# scripts/test.sh records the untracked paths before its first item and compares them after its
# last one, so a developer's own work in progress (untracked files that were there already)
# never fails the run, and nothing is added to .gitignore to hide the defect.
#
# Only untracked paths count: ignored paths (build/, *.ssa, tests/**/*.out, ...) never appear
# in `git status --untracked-files=all`, and a tracked file a run edits shows as ` M`, not `??`.
#
# Usage:
#   scripts/check_stray_files.sh --record FILE   write the current untracked paths to FILE
#   scripts/check_stray_files.sh --compare FILE  print the untracked paths added since FILE
#   scripts/check_stray_files.sh --selftest      check the recorder and the comparison
#
# Exit status: 0 clean or selftest passed, 1 paths were added (or the selftest failed),
# 2 usage error or not a git checkout.
set -u

case "$0" in
    /*) _self="$0" ;;
    */*) _self="$PWD/$0" ;;
    *) _self="$(command -v -- "$0" 2>/dev/null || echo "$0")" ;;
esac
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$_self")/.." && pwd)}"

. "$(dirname "$_self")/lib/portability.sh"
. "$(dirname "$_self")/lib/tree_files.sh"

# Files in the tree, one per line (build/ and hidden directories pruned).
snapshot() {
    [ -d "$REPO_ROOT" ] || return 1
    tree_files "$REPO_ROOT"
}

record() {
    _out="$1"
    [ -d "$REPO_ROOT" ] || return 2
    snapshot > "$_out.tmp" || { rm -f "$_out.tmp"; return 2; }
    mv -f "$_out.tmp" "$_out"
}

compare() {
    _start="$1"
    [ -f "$_start" ] || return 2
    [ -d "$REPO_ROOT" ] || return 2
    _now="$(mktemp "${TMPDIR:-/tmp}/stray_files.XXXXXX")" || return 2
    if ! snapshot > "$_now"; then rm -f "$_now"; return 2; fi
    comm -13 "$_start" "$_now"
    _rc=$?
    rm -f "$_now"
    return $_rc
}

selftest() {
    _tmp="$(mktemp -d "${TMPDIR:-/tmp}/stray_files_selftest.XXXXXX")" || return 1
    trap 'rm -rf "$_tmp"' EXIT INT TERM
    _repo="$_tmp/repo"
    _n=0

    _pass() { _n=$((_n + 1)); }
    _fail() {
        echo "[FAIL] check_stray_files: $*"
        return 1
    }

    mkdir -p "$_repo/src" "$_repo/build"
    printf '// main\n' > "$_repo/src/main.zrl"

    _run() {
        REPO_ROOT="$_repo" "$_self" "$@"
    }

    # 1. A run that writes nothing new is clean.
    if ! _run --record "$_tmp/start" >/dev/null; then
        _fail "--record failed in scratch directory" || return 1
    fi
    _out="$(_run --compare "$_tmp/start")"
    [ -z "$_out" ] || _fail "an unchanged tree was reported as stray: $_out" || return 1
    _pass

    # 2. Ignored output (build/) is not reported.
    printf 'x\n' > "$_repo/build/obj.o"
    _out="$(_run --compare "$_tmp/start")"
    [ -z "$_out" ] || _fail "ignored build/ output was reported as stray: $_out" || return 1
    _pass

    # 3. A file planted outside build/ fails and is named.
    printf 'x\n' > "$_repo/src/stray.o"
    if _out="$(_run --compare "$_tmp/start")"; then
        _fail "a file planted outside build/ was not detected" || return 1
    fi
    case "$_out" in
        *src/stray.o*) ;;
        *) _fail "the failure did not name src/stray.o: $_out" || return 1 ;;
    esac
    _pass

    # 4. A file that was already untracked at record time (work in progress) is not reported.
    printf 'x\n' > "$_repo/src/wip.zrl"
    _run --record "$_tmp/start2" >/dev/null
    _out="$(_run --compare "$_tmp/start2")"
    [ -z "$_out" ] || _fail "untracked work in progress was reported as stray: $_out" || return 1
    _pass

    # 5. Nothing added since the second record is clean again, once the planted file is gone.
    rm -f "$_repo/src/stray.o"
    _out="$(_run --compare "$_tmp/start2")"
    [ -z "$_out" ] || _fail "tree not clean after removing the planted file: $_out" || return 1
    _pass

    # 6. A nonexistent directory declines.
    if REPO_ROOT="$_tmp/nonexistent" "$_self" --record "$_tmp/start3" >/dev/null 2>&1; then
        _fail "a nonexistent directory was recorded" || return 1
    fi
    _pass

    # 7. A missing record file is a usage error, not a pass.
    if _run --compare "$_tmp/absent" >/dev/null 2>&1; then
        _fail "an absent record file was accepted" || return 1
    fi
    _pass

    echo "[PASS] check_stray_files: selftest passed ($_n checks)"
    rm -rf "$_tmp"
    trap - EXIT INT TERM
    return 0
}

case "${1:-}" in
    --selftest)
        selftest
        exit $?
        ;;
    --record)
        [ "$#" -eq 2 ] || { echo "usage: $0 --record FILE" >&2; exit 2; }
        record "$2"
        exit $?
        ;;
    --compare)
        [ "$#" -eq 2 ] || { echo "usage: $0 --compare FILE" >&2; exit 2; }
        _added="$(compare "$2")"
        _rc=$?
        if [ $_rc -eq 2 ]; then
            echo "check_stray_files: cannot compare against '$2' (missing file, or invalid directory)" >&2
            exit 2
        fi
        [ -n "$_added" ] || exit 0
        printf '%s\n' "$_added"
        exit 1
        ;;
    *)
        sed -n '2,/^set -u$/ { /^set -u$/d; s/^# \{0,1\}//; p; }' "$_self"
        exit 2
        ;;
esac
