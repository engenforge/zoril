#!/bin/sh
# scripts/full_test_stamp.sh snapshot|write|check — which tree the last whole `make test` passed on.
#
#   snapshot [OUT]  record tree hash, compiler and toolchain fingerprint to a pending key file
#                   (scripts/test.sh calls this before the first item starts)
#   write [IN] [TOT] move pending key to build/full-test.stamp with passing Total: line
#                   (scripts/test.sh calls this after a whole run that passed)
#   check           exit 0 when stamp matches current tree; otherwise print why and exit 1
#
# make test checks this before running tests: on an identical tree and toolchain, it prints one line
# naming the earlier run and the earlier Total: line, then stops unless FORCE=1.
cd "$(dirname "$0")/.." || exit 2
. scripts/lib/portability.sh

# Tests and stamp checks isolate from user git configurations.
GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_GLOBAL
GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_SYSTEM
GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_NOSYSTEM
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS

STAMP=build/full-test.stamp

BACKEND_BIN="${BACKEND_BIN:-qbe}"
ASSEMBLER_BIN="${ASSEMBLER_BIN:-as}"
LINKER_BIN="${LINKER_BIN:-ld}"
LINK_CC="${LINK_CC:-${CC:-cc}}"

# tree_hash computes a deterministic hash of the working tree excluding doc/tasks/ and build/.
# Does not write loose objects to .git/objects: uses HEAD tree hash plus git status and
# git hash-object without -w for any modified or untracked files outside doc/tasks and build.
tree_hash() {
    git rev-parse --verify -q HEAD >/dev/null 2>&1 || return 1
    _head_tree=$(git rev-parse HEAD^{tree} 2>/dev/null) || return 1
    _status=$(git status --porcelain -uall -- . ':!doc/tasks' ':!build' 2>/dev/null) || return 1
    if [ -z "$_status" ]; then
        printf '%s\n' "$_head_tree"
        return 0
    fi
    (
        printf 'head:%s\n' "$_head_tree"
        printf '%s\n' "$_status" | while IFS= read -r _line; do
            [ -n "$_line" ] || continue
            _st=$(printf '%s' "$_line" | cut -c 1-2)
            _file=$(printf '%s' "$_line" | cut -c 4-)
            case "$_file" in
                *" -> "*) _file="${_file#* -> }" ;;
            esac
            if [ -e "$_file" ]; then
                _h=$(git hash-object "$_file" 2>/dev/null || echo "missing")
            else
                _h="deleted"
            fi
            printf '%s %s %s\n' "$_st" "$_file" "$_h"
        done
    ) | sha256_of | awk '{print $1}'
}

compiler_hash() {
    if [ -f build/zoril ]; then
        sha256_of build/zoril 2>/dev/null | awk '{print $1}'
    else
        echo "none"
    fi
}

toolchain_fp() {
    (
        if [ -f scripts/qbe_fingerprint.sh ]; then
            sh scripts/qbe_fingerprint.sh "$BACKEND_BIN" 2>/dev/null || echo "qbe: unknown"
        else
            echo "qbe: none"
        fi
        "$ASSEMBLER_BIN" --version 2>/dev/null | head -n1 || echo "as: none"
        "$LINKER_BIN" --version 2>/dev/null | head -n1 || echo "ld: none"
        "$LINK_CC" --version 2>/dev/null | head -n1 || echo "cc: none"
        if [ -f build/zilc ]; then
            sha256_of build/zilc 2>/dev/null | awk '{print "zilc: " $1}'
        fi
        if [ -f scripts/check_deps.sh ]; then
            sh scripts/check_deps.sh --fingerprint 2>/dev/null || echo "check_deps: error"
        fi
    ) | sha256_of | awk '{print $1}'
}

case "${1:-}" in
    snapshot)
        _target="${2:-${TR_WORK:-build/tests}/stamp.pending}"
        mkdir -p "$(dirname "$_target")"
        git_checkout_usable . || exit 0
        cur_tree=$(tree_hash) || exit 0
        cur_compiler=$(compiler_hash)
        cur_toolchain=$(toolchain_fp)
        commit_full=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        commit_short=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        commit_date=$(git log -1 --format='%ci' HEAD 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S UTC')
        if ! git diff --quiet HEAD 2>/dev/null || [ -n "$(git status --porcelain -uall -- . ':!doc/tasks' ':!build' 2>/dev/null)" ]; then
            commit_short="${commit_short}+dirty"
        fi
        {
            printf 'commit:%s\n' "$commit_full"
            printf 'short:%s\n' "$commit_short"
            printf 'date:%s\n' "$commit_date"
            printf 'tree:%s\n' "$cur_tree"
            printf 'compiler:%s\n' "$cur_compiler"
            printf 'toolchain:%s\n' "$cur_toolchain"
        } > "$_target.tmp" && mv "$_target.tmp" "$_target"
        ;;
    write)
        mkdir -p build
        _pending="${2:-${TR_WORK:-build/tests}/stamp.pending}"
        _total_line="${3:-}"
        # If pending file does not exist, compute snapshot directly
        if [ ! -f "$_pending" ]; then
            _pending="$STAMP.pending_direct"
            sh "$0" snapshot "$_pending" || exit 0
        fi
        if [ -f "$_pending" ]; then
            {
                cat "$_pending"
                if [ -n "$_total_line" ]; then
                    printf 'total:%s\n' "$_total_line"
                fi
            } > "$STAMP.tmp" && mv "$STAMP.tmp" "$STAMP"
            rm -f "$_pending" "$_pending.tmp"
        fi
        ;;
    check)
        [ -f "$STAMP" ] || { echo "no whole 'make test' has passed in this tree (no $STAMP): run make test" >&2; exit 1; }
        git_checkout_usable . || { echo "full_test_stamp: this is not a git tree" >&2; exit 1; }
        cur_tree=$(tree_hash) || { echo "full_test_stamp: cannot read git tree" >&2; exit 1; }
        cur_compiler=$(compiler_hash)
        cur_toolchain=$(toolchain_fp)
        stamp_commit=""
        stamp_short=""
        stamp_date=""
        stamp_tree=""
        stamp_compiler=""
        stamp_toolchain=""
        stamp_total=""
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                commit:*) stamp_commit="${line#commit:}" ;;
                short:*)  stamp_short="${line#short:}" ;;
                date:*)   stamp_date="${line#date:}" ;;
                tree:*)   stamp_tree="${line#tree:}" ;;
                compiler:*) stamp_compiler="${line#compiler:}" ;;
                toolchain:*) stamp_toolchain="${line#toolchain:}" ;;
                total:*)  stamp_total="${line#total:}" ;;
            esac
        done < "$STAMP"
        if [ -z "$stamp_tree" ] || [ -z "$stamp_compiler" ] || [ -z "$stamp_toolchain" ]; then
            echo "the stamp format has changed since the last whole 'make test' that passed: run make test" >&2
            exit 1
        fi
        if [ "$cur_tree" != "$stamp_tree" ]; then
            echo "the tree has changed since the last whole 'make test' that passed: run make test" >&2
            exit 1
        fi
        if [ "$cur_compiler" != "$stamp_compiler" ]; then
            echo "the compiler has changed since the last whole 'make test' that passed: run make test" >&2
            exit 1
        fi
        if [ "$cur_toolchain" != "$stamp_toolchain" ]; then
            echo "the toolchain fingerprint has changed since the last whole 'make test' that passed: run make test" >&2
            exit 1
        fi
        desc="git:${stamp_short:-unknown}"
        [ -n "$stamp_date" ] && desc="$desc, $stamp_date"
        printf 'make test: tree, compiler and toolchain fingerprint unchanged since earlier run (%s); stopping (FORCE=1 to run)\n' "$desc"
        if [ -n "$stamp_total" ]; then
            printf '%s\n' "$stamp_total"
        fi
        exit 0
        ;;
    *) echo "usage: full_test_stamp.sh snapshot|write|check" >&2; exit 2 ;;
esac
