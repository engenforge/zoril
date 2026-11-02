#!/bin/sh
# scripts/test_full_test_stamp.sh — scripts/full_test_stamp.sh ties the stamp to the tree it was written on.
cd "$(dirname "$0")/.." || exit 2
command -v git >/dev/null 2>&1 || { echo "[SKIP] full-test-stamp: no git"; exit 0; }
fail() { echo "[FAIL] full-test-stamp: $1"; exit 1; }
t=$(mktemp -d "${TMPDIR:-/tmp}/zoril_stamp_XXXXXX")
trap 'rm -rf "$t"' EXIT INT TERM
mkdir -p "$t/scripts/lib"
cp scripts/full_test_stamp.sh "$t/scripts/"
cp scripts/lib/portability.sh "$t/scripts/lib/"
(cd "$t" && git init -q . && git config user.email a@b.invalid && git config user.name t && git config commit.gpgsign false && echo one > f && git add . && git commit -q -m one) || fail "cannot make a scratch repository"
stamp() { (cd "$t" && sh scripts/full_test_stamp.sh "$1" > "$t/out.txt" 2>&1); }
stamp check && fail "a tree with no stamp passed the check"
grep -q "no whole 'make test'" "$t/out.txt" || fail "the missing stamp is not explained"
stamp write || fail "write failed"
stamp check || fail "a fresh stamp did not pass"
echo two > "$t/f"
stamp check && fail "a tracked change since the stamp passed"
grep -q "changed since" "$t/out.txt" || fail "the changed tree is not explained"
stamp write; stamp check || fail "a stamp written on the changed tree did not pass"
(cd "$t" && git commit -q -am two)
stamp check && fail "a new commit since the stamp passed"
echo "[PASS] full-test-stamp: the stamp passes only for the tree it was written on"
