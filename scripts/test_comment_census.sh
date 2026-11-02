#!/bin/sh
# scripts/test_comment_census.sh — tests for scripts/comment_census.sh: the budget ratchet, the
# slack that lets a few new lines through, the skipped row for a file the tree does not carry
# (an exported tree), and `--record`.
set -eu

cd "$(dirname "$0")/.."
CENSUS="$(pwd)/scripts/comment_census.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

errors=0
rc=0
out=""

run() { # run <dir> <args...>
    _d="$1"; shift
    rc=0
    out="$(COMMENT_BUDGET="$tmp/budget.tsv" sh "$CENSUS" "$@" "$_d" 2>&1)" || rc=$?
}

expect() { # expect <name> <expected exit> <expected substring or ''>
    if [ "$rc" -ne "$2" ]; then
        echo "[FAIL] $1: exit $rc, expected $2"
        printf '%s\n' "$out" | sed 's/^/       /'
        errors=$((errors + 1))
    elif [ -n "$3" ] && ! printf '%s\n' "$out" | grep -qF -- "$3"; then
        echo "[FAIL] $1: output lacks '$3'"
        printf '%s\n' "$out" | sed 's/^/       /'
        errors=$((errors + 1))
    else
        echo "[PASS] $1"
    fi
}

case_tree="$tmp/tree"
mkdir -p "$case_tree/src"

# 1. Record a budget from a tree: 20 comment lines (two 10-line blocks, longest 10), so the limit is 20 + 2 + 5 = 27.
awk 'BEGIN { for (i = 0; i < 10; i++) print "// comment " i; print "fn f() {}"; for (i = 10; i < 20; i++) print "// comment " i }' > "$case_tree/src/a.zrl"
run "$case_tree" --record
expect "record writes a budget" 0 "recorded 1 files"

# 2. The tree as recorded is within budget.
run "$case_tree" --check
expect "the recorded tree passes" 0 "1 file(s) within budget"

# 3. A few new comment lines are inside the slack (two 11/12-line blocks, longest 12 <= cap 12).
awk 'BEGIN { for (i = 0; i < 11; i++) print "// comment " i; print "fn f() {}"; for (i = 11; i < 23; i++) print "// comment " i }' > "$case_tree/src/a.zrl"
run "$case_tree" --check
expect "a 3-line growth passes" 0 "within budget"

# 4. A file far past its budget fails, naming both numbers (four 10-line blocks, each <= cap 12).
awk 'BEGIN { for (b = 0; b < 4; b++) { for (i = 0; i < 10; i++) print "// comment " (b*10+i); print "" } print "fn f() {}" }' > "$case_tree/src/a.zrl"
run "$case_tree" --check
expect "a 20-line growth fails" 1 "has 40 comment lines, budget 20"

# 5. A row for a file this tree does not carry is skipped, not failed: the exported tree does not
#    ship tools/oldtool.
printf 'tools/oldtool/src/gone.zrl\t100\t100\t5\t3\n' >> "$tmp/budget.tsv"
run "$case_tree" --check
expect "an absent file's row is skipped" 1 "has 40 comment lines"

# 6. Re-recording the tree it actually has makes the check pass again.
awk 'BEGIN { for (b = 0; b < 4; b++) { for (i = 0; i < 10; i++) print "// comment " (b*10+i); print "" } print "fn f() {}" }' > "$case_tree/src/a.zrl"
printf 'tools/oldtool/src/gone.zrl\t100\t100\t5\t3\n' > "$tmp/budget.tsv"
run "$case_tree" --record
expect "re-record after growth" 0 "recorded 1 files"
run "$case_tree" --check
expect "the re-recorded tree passes" 0 "within budget"

# 7. Proportional code growth: comments grow in step with code lines without failing.
# Record budget: 1 code line, 10 comments (limit for 1 code line is 10 + 1 + 5 = 16).
awk 'BEGIN { for (i = 0; i < 10; i++) print "// comment " i; print "fn f() {}" }' > "$case_tree/src/a.zrl"
run "$case_tree" --record
expect "record for proportional growth test" 0 "recorded 1 files"
# Now code grows to 10 lines and comments grow to 30 lines (3-line blocks before each fn, each <= cap 12).
# Ratio 10/1 = 10; expected = 10 * 10 = 100; limit = 100 + 10 + 5 = 115.
# 30 comments is well within 115 limit.
awk 'BEGIN { for (i = 0; i < 10; i++) { print "// comment " i "a"; print "// comment " i "b"; print "// comment " i "c"; print "fn f" i "() {}" } }' > "$case_tree/src/a.zrl"
run "$case_tree" --check
expect "proportional code growth allows comment growth" 0 "within budget"

# 8. Longest comment block cap: exceeding max(12, recorded longest) fails.
# Record budget with longest block = 6. Cap is max(12, 6) = 12.
awk 'BEGIN { for (i = 0; i < 6; i++) print "// comment " i; print "fn f() {}" }' > "$case_tree/src/a.zrl"
run "$case_tree" --record
expect "record for block cap test" 0 "recorded 1 files"
# Add a comment block of 13 lines (exceeds cap 12).
awk 'BEGIN { for (i = 0; i < 13; i++) print "// comment " i; print "fn f() {}" }' > "$case_tree/src/a.zrl"
run "$case_tree" --check
expect "a 13-line comment block fails when cap is 12" 1 "has a comment block of 13 lines (limit 12)"

# 9. Longest comment block cap for file with recorded longest > 12: cap is recorded longest.
# Record budget with longest block = 15. Cap is max(12, 15) = 15.
awk 'BEGIN { for (i = 0; i < 15; i++) print "// comment " i; print "fn f() {}" }' > "$case_tree/src/a.zrl"
run "$case_tree" --record
expect "record with longest 15" 0 "recorded 1 files"
# A block of 16 lines exceeds cap 15.
awk 'BEGIN { for (i = 0; i < 16; i++) print "// comment " i; print "fn f() {}" }' > "$case_tree/src/a.zrl"
run "$case_tree" --check
expect "a 16-line comment block fails when cap is 15" 1 "has a comment block of 16 lines (limit 15)"

# 10. The default (no flag) prints the census rather than checking it.
rc=0
out="$(COMMENT_BUDGET="$tmp/budget.tsv" sh "$CENSUS" "$case_tree" 2>&1)" || rc=$?
expect "no flag prints the census" 0 "src/a.zrl"

if [ "$errors" -ne 0 ]; then
    echo "[FAIL] $errors case(s) failed"
    exit 1
fi
echo "[PASS] comment_census.sh behaves as specified (14 cases)"
