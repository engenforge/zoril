#!/bin/sh
# scripts/full_test_stamp.sh write|check — which tree the last whole `make test` passed on.
#
#   write   record the current tree, compiler and toolchain fingerprint in
#           build/full-test.stamp (scripts/test.sh calls this after a whole run that passed)
#   check   exit 0 when the stamp matches the tree as it is now; otherwise print why and exit 1
#
# make test checks this before running tests: on an identical tree and toolchain, it prints one line
# naming the earlier run and stops unless FORCE=1.
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

# tree_hash computes the git tree hash of the working tree excluding doc/tasks/ and build/.
# Taskmark tracking files in doc/tasks/ are updated on every task iteration and do
# not affect compiler, stdlib, tooling, or test outcomes. build/ holds generated artifacts
# including full-test.stamp and build/zoril (tracked separately via compiler_hash).
tree_hash() {
    git rev-parse --verify -q HEAD >/dev/null 2>&1 || return 1
    _tmp="$(mktemp -d "${TMPDIR:-/tmp}/zoril_tree_hash.XXXXXX")" || return 1
    _idx="$_tmp/idx"
    if ! GIT_INDEX_FILE="$_idx" git read-tree HEAD 2>/dev/null; then
        rm -rf "$_tmp"
        return 1
    fi
    if ! GIT_INDEX_FILE="$_idx" git add -A -- . ':!doc/tasks' 2>/dev/null; then
        rm -rf "$_tmp"
        return 1
    fi
    GIT_INDEX_FILE="$_idx" git rm -r -q --cached doc/tasks build 2>/dev/null || true
    _tree=$(GIT_INDEX_FILE="$_idx" git write-tree 2>/dev/null) || { rm -rf "$_tmp"; return 1; }
    rm -rf "$_tmp"
    printf '%s\n' "$_tree"
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
    ) | sha256_of | awk '{print $1}'
}

case "${1:-}" in
    write)
        mkdir -p build
        git_checkout_usable . || exit 0
        cur_tree=$(tree_hash) || exit 0
        cur_compiler=$(compiler_hash)
        cur_toolchain=$(toolchain_fp)
        commit_full=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        commit_short=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        commit_date=$(git log -1 --format='%ci' HEAD 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S UTC')
        if ! git diff --quiet HEAD 2>/dev/null || [ -n "$(git status --porcelain -- . ':!doc/tasks' 2>/dev/null)" ]; then
            commit_short="${commit_short}+dirty"
        fi
        {
            printf 'commit:%s\n' "$commit_full"
            printf 'short:%s\n' "$commit_short"
            printf 'date:%s\n' "$commit_date"
            printf 'tree:%s\n' "$cur_tree"
            printf 'compiler:%s\n' "$cur_compiler"
            printf 'toolchain:%s\n' "$cur_toolchain"
        } > "$STAMP.tmp" && mv "$STAMP.tmp" "$STAMP"
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
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                commit:*) stamp_commit="${line#commit:}" ;;
                short:*)  stamp_short="${line#short:}" ;;
                date:*)   stamp_date="${line#date:}" ;;
                tree:*)   stamp_tree="${line#tree:}" ;;
                compiler:*) stamp_compiler="${line#compiler:}" ;;
                toolchain:*) stamp_toolchain="${line#toolchain:}" ;;
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
        exit 0
        ;;
    *) echo "usage: full_test_stamp.sh write|check" >&2; exit 2 ;;
esac
