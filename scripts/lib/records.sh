#!/bin/sh
# scripts/lib/records.sh — helpers for committing append-only records to the `records` worktree.
#
# Expects scripts/lib/portability.sh (git_checkout_usable) to be sourced already.

RECORDS_SKIP=0

records_repo_commit() {
    _rrc_root="${1:-$REPO_ROOT}"
    if git_checkout_usable "$_rrc_root"; then
        _rrc_c=$(git -C "$_rrc_root" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        if [ "$_rrc_c" != "unknown" ] && [ -n "$(git -C "$_rrc_root" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
            _rrc_c="${_rrc_c}-dirty"
        fi
        printf '%s\n' "$_rrc_c"
    else
        printf 'unknown\n'
    fi
}

records_check_target() {
    _rct_file="$1"
    _rct_root="${2:-$REPO_ROOT}"
    RECORDS_SKIP=0
    case "$_rct_file" in
        "$_rct_root/bench/records/"*) ;;
        *) return 0 ;;
    esac
    if ! git_checkout_usable "$_rct_root"; then
        printf '[SKIP] bench records: no git checkout, so this run is compared with nothing and recorded nowhere\n'
        RECORDS_SKIP=1
        return 0
    fi
    _rct_dir="$_rct_root/bench/records"
    _rct_repo=$(cd "$_rct_root" 2>/dev/null && pwd -P)
    _rct_abs=$(cd "$_rct_dir" 2>/dev/null && pwd -P) || _rct_abs=""
    _rct_top=""
    if [ -n "$_rct_abs" ]; then
        _rct_top=$(git -C "$_rct_abs" rev-parse --show-toplevel 2>/dev/null) || _rct_top=""
        [ -n "$_rct_top" ] && _rct_top=$(cd "$_rct_top" 2>/dev/null && pwd -P)
    fi
    if [ -z "$_rct_abs" ] || [ "$_rct_top" != "$_rct_abs" ] || [ "$_rct_top" = "$_rct_repo" ]; then
        printf '[FAIL] bench records: the records branch is not mounted at bench/records; run: git fetch origin records && git worktree add bench/records records (or, in a clone that has no such branch: git worktree add --orphan -b records bench/records)\n' >&2
        return 1
    fi
    return 0
}

records_commit() {
    _rc_file="$1"
    _rc_subj="$2"
    _rc_root="${3:-$REPO_ROOT}"
    [ "${RECORDS_SKIP:-0}" -eq 0 ] || return 0
    _rc_repo=$(cd "$_rc_root" 2>/dev/null && pwd -P) || return 0
    _rc_dir=$(cd "$(dirname "$_rc_file")" 2>/dev/null && pwd -P) || return 0
    command -v git >/dev/null 2>&1 || return 0
    _rc_top=$(git -C "$_rc_dir" rev-parse --show-toplevel 2>/dev/null) || return 0
    _rc_top=$(cd "$_rc_top" 2>/dev/null && pwd -P) || return 0
    [ "$_rc_top" = "$_rc_dir" ] || return 0
    [ "$_rc_top" != "$_rc_repo" ] || return 0

    _rc_err=""
    if ! _rc_err=$(git -C "$_rc_dir" add "$(basename "$_rc_file")" 2>&1); then
        printf '[FAIL] bench records: the row was appended to %s but not committed: %s\n' "$_rc_file" "$_rc_err" >&2
        return 1
    fi
    if ! _rc_err=$(git -C "$_rc_dir" commit -m "$_rc_subj" 2>&1); then
        printf '[FAIL] bench records: the row was appended to %s but not committed: %s\n' "$_rc_file" "$_rc_err" >&2
        return 1
    fi
    return 0
}
