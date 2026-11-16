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
    case "$_rc_file" in
        "$_rc_root/bench/records/"*) ;;
        *) return 0 ;;
    esac
    _rc_repo=$(cd "$_rc_root" 2>/dev/null && pwd -P) || return 0
    _rc_dir=$(cd "$(dirname "$_rc_file")" 2>/dev/null && pwd -P) || return 0
    command -v git >/dev/null 2>&1 || return 0
    _rc_top=$(git -C "$_rc_dir" rev-parse --show-toplevel 2>/dev/null) || return 0
    _rc_top=$(cd "$_rc_top" 2>/dev/null && pwd -P) || return 0
    [ "$_rc_top" = "$_rc_dir" ] || return 0
    [ "$_rc_top" != "$_rc_repo" ] || return 0

    _rc_base=$(basename "$_rc_file")
    _rc_err=""
    _rc_try=0
    while [ "$_rc_try" -lt 5 ]; do
        if _rc_st=$(git -C "$_rc_dir" status --porcelain -- "$_rc_base" 2>/dev/null) && [ -z "$_rc_st" ]; then
            return 0
        fi
        if _rc_err=$(git -C "$_rc_dir" add "$_rc_base" 2>&1) && \
           _rc_err=$(git -C "$_rc_dir" commit -m "$_rc_subj" 2>&1); then
            return 0
        fi
        _rc_try=$((_rc_try + 1))
        if [ "$_rc_try" -lt 5 ]; then
            sleep 1
        fi
    done
    if _rc_st=$(git -C "$_rc_dir" status --porcelain -- "$_rc_base" 2>/dev/null) && [ -z "$_rc_st" ]; then
        return 0
    fi
    printf '[FAIL] bench records: the row was appended to %s but not committed: %s\n' "$_rc_file" "$_rc_err" >&2
    return 1
}

# Write a header line to a history file only if it does not exist or is empty.
# Linked into place rather than written with > because a truncating write deletes
# a row appended by a concurrent run since the existence test. The link stays
# the only way the header is put in place, so a failing link fails the call
# rather than falling back to a truncating write.
# Accepted gap: an existing empty file is replaced, which two runs can still race
# on; nothing in the tree creates an empty history file.
records_header() {
    _rh_file="$1"
    mkdir -p "$(dirname "$_rh_file")"
    _rh_tmp="$_rh_file.hdr.$$"
    if [ -e "$_rh_file" ]; then
        [ ! -s "$_rh_file" ] || return 0
        printf '%s\n' "$2" > "$_rh_tmp"
        mv -f "$_rh_tmp" "$_rh_file"
    else
        printf '%s\n' "$2" > "$_rh_tmp"
        ln "$_rh_tmp" "$_rh_file" 2>/dev/null || true
        rm -f "$_rh_tmp"
        [ ! -e "$_rh_file" ] || return 0
        printf '[FAIL] bench records: cannot create %s with its header (linking a temporary file into place failed)\n' "$_rh_file" >&2
        return 1
    fi
}
