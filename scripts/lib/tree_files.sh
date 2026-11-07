#!/bin/sh
# scripts/lib/tree_files.sh — list source files in the tree without git
#
# Emits sorted relative paths of all non-hidden files in the tree,
# pruning build/ and hidden directories (.git, .gemini, etc.).
# Sourced by scripts or executed directly.

tree_files() {
    _tf_root="${1:-.}"
    (
        cd "$_tf_root" || exit 1
        find . \( -name build -o -name '.?*' \) -type d -prune -o -name .git -prune -o -type f -print \
            | sed 's|^\./||' \
            | LC_ALL=C sort
    )
}

if [ "${0##*/}" = "tree_files.sh" ]; then
    tree_files "$@"
fi
