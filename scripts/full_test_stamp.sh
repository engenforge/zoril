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
. scripts/lib/tree_files.sh

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

# tree_hash computes a deterministic sha256 hash of all files listed by tree_files excluding doc/tasks/.
# Format of the hashed stream: sorted lines of path<TAB>sha256.
_hash_batch() {
    set --
    _count=0
    while IFS= read -r _f || [ -n "$_f" ]; do
        set -- "$@" "$_f"
        _count=$((_count + 1))
        if [ "$_count" -ge 80 ]; then
            sha256_of "$@"
            set --
            _count=0
        fi
    done
    if [ "$_count" -gt 0 ]; then
        sha256_of "$@"
    fi
}

tree_hash() {
    tree_files . \
        | grep -v '^doc/tasks/' \
        | _hash_batch \
        | awk '{ printf "%s\t%s\n", substr($0, 67), substr($0, 1, 64) }' \
        | sha256_of \
        | awk '{print $1}'
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
        cur_tree=$(tree_hash) || exit 0
        cur_compiler=$(compiler_hash)
        cur_toolchain=$(toolchain_fp)
        if git_checkout_usable .; then
            commit_full=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
            commit_short=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
            commit_date=$(git log -1 --format='%ci' HEAD 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S UTC')
            if ! git diff --quiet HEAD 2>/dev/null || [ -n "$(git status --porcelain -uall -- . ':!doc/tasks' ':!build' 2>/dev/null)" ]; then
                commit_short="${commit_short}+dirty"
            fi
        else
            commit_full="tarball"
            commit_short="tarball"
            commit_date=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
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
        # A snapshot must be recorded at run start; fail if none exists
        if [ ! -f "$_pending" ]; then
            echo "full_test_stamp: snapshot not found: $_pending" >&2
            exit 1
        fi
        {
            cat "$_pending"
            if [ -n "$_total_line" ]; then
                printf 'total:%s\n' "$_total_line"
            fi
        } > "$STAMP.tmp" && mv "$STAMP.tmp" "$STAMP"
        rm -f "$_pending" "$_pending.tmp"
        ;;
    check)
        [ -f "$STAMP" ] || { echo "no whole 'make test' has passed in this tree (no $STAMP): run make test" >&2; exit 1; }
        cur_tree=$(tree_hash) || { echo "full_test_stamp: cannot read tree" >&2; exit 1; }
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
