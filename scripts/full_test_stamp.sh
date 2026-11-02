#!/bin/sh
# scripts/full_test_stamp.sh write|check — which tree the last whole `make test` passed on.
#
#   write   record the current HEAD and the hash of the tracked changes on top of it in
#           build/full-test.stamp (scripts/test.sh calls this after a whole run that passed)
#   check   exit 0 when the stamp matches the tree as it is now; otherwise print why and exit 1
#
# The export (scripts/export_public_release.sh) checks it: a tree changed since its last whole run is
# a tree whose gates have not seen the change.
cd "$(dirname "$0")/.." || exit 2
. scripts/lib/portability.sh
STAMP=build/full-test.stamp
tree_state() {
    git rev-parse HEAD 2> /dev/null || return 1
    git diff HEAD --binary 2> /dev/null | sha256_of | awk '{print $1}'
}
case "${1:-}" in
    write)
        mkdir -p build
        state=$(tree_state) || exit 0
        printf '%s\n' "$state" > "$STAMP"
        ;;
    check)
        [ -f "$STAMP" ] || { echo "no whole 'make test' has passed in this tree (no $STAMP): run make test" >&2; exit 1; }
        state=$(tree_state) || { echo "full_test_stamp: this is not a git tree" >&2; exit 1; }
        [ "$state" = "$(cat "$STAMP")" ] || { echo "the tree has changed since the last whole 'make test' that passed (HEAD or tracked changes differ): run make test" >&2; exit 1; }
        ;;
    *) echo "usage: full_test_stamp.sh write|check" >&2; exit 2 ;;
esac
