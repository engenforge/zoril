# Sourced by the stage0-C test runners, which reuse the repository's shared tests.
#
#   is_outside_dialect FILE  true when FILE is listed in tests/outside_dialect.txt: correct
#                            Zoril that stage0-C is not meant to compile. Out of scope, like
#                            a file outside the suite's directory: not run, not counted.
#   known_bug_reason FILE    the reason recorded in tests/known_bugs.txt, or nothing. These
#                            are reported as [SKIP]: a skip is something to act on.
#   check_skip_lists         one item line: both lists name only existing files, and no
#                            file is in both.
OUTSIDE_DIALECT_LIST="$REPO_ROOT/tests/outside_dialect.txt"
KNOWN_BUGS_LIST="$REPO_ROOT/tests/known_bugs.txt"
if [ -d "$REPO_ROOT/../../stdlib" ]; then
    OUTSIDE_DIALECT_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"
else
    OUTSIDE_DIALECT_ROOT="$(cd "$REPO_ROOT/.." && pwd)"
fi

# _skip_list_reason LIST FILE — the reason for FILE in LIST, or nothing.
_skip_list_reason() {
    _od_full="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
    _od_rel="${_od_full#"$OUTSIDE_DIALECT_ROOT"/}"
    grep -v '^#' "$1" 2>/dev/null | grep -F "$_od_rel:" | head -n 1 | sed -E 's/^[^:]+:[[:space:]]*//'
}

is_outside_dialect() { [ -n "$(_skip_list_reason "$OUTSIDE_DIALECT_LIST" "$1")" ]; }
known_bug_reason() { _skip_list_reason "$KNOWN_BUGS_LIST" "$1"; }

check_skip_lists() {
    _problems=$(
        for _list in "$OUTSIDE_DIALECT_LIST" "$KNOWN_BUGS_LIST"; do
            grep -v '^#' "$_list" | grep -E '^[^[:space:]]+:' | cut -d: -f1 | while read -r _p; do
                [ -e "$OUTSIDE_DIALECT_ROOT/$_p" ] || echo "$(basename "$_list") lists missing file $_p"
            done
        done
        { grep -v '^#' "$OUTSIDE_DIALECT_LIST"; grep -v '^#' "$KNOWN_BUGS_LIST"; } \
            | grep -E '^[^[:space:]]+:' | cut -d: -f1 | sort | uniq -d | sed 's/$/ is in both lists/')
    if [ -z "$_problems" ]; then
        echo "[PASS] skip lists name existing tests, each in one list"
    else
        echo "[FAIL] skip lists ($(echo "$_problems" | head -n 1))"
    fi
}
