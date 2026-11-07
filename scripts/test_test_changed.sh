#!/bin/sh
# scripts/test_test_changed.sh — scenario test for make test-changed.
#
# Asserts that:
#   1. An untracked new test is included in the changed path list and executed by the runner.
#   2. A renamed test's old and new paths are both passed to the runner (via --no-renames).
#   3. Outside a checkout everything runs, printing a notice and selecting --gates.
#   4. Taking --no-renames out of the Makefile causes renamed old path detection to fail.
#   5. Taking git ls-files out of the Makefile causes untracked test detection to fail.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
. scripts/lib/portability.sh

if ! command -v git >/dev/null 2>&1; then
    echo "[SKIP] test-changed: git is not installed"
    exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[SKIP] test-changed: not inside a git checkout"
    exit 0
fi

tmp="$(mktemp -d)"

cleanup() {
    rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

errors=0
pass() { echo "[PASS] test-changed: $1"; }
fail() { echo "[FAIL] test-changed: $1 ($2)"; errors=$((errors + 1)); }

# Create stub runner that logs what arguments it received
cat << 'EOF' > "$tmp/stub_runner.sh"
#!/bin/sh
echo "stub runner args: $*"
exit 0
EOF
chmod +x "$tmp/stub_runner.sh"

# Setup scratch repository for untracked test testing
r_untracked="$tmp/repo_untracked"
mkdir -p "$r_untracked/tests/unit"
(
    cd "$r_untracked"
    git -c init.defaultBranch=main init -q
    git -c user.name=t -c user.email=t config user.name t
    git -c user.name=t -c user.email=t config user.email t
    git -c commit.gpgsign=false commit --allow-empty -qm "initial commit"
)

cat << 'EOF' > "$r_untracked/tests/unit/test_probe_untracked.zrl"
// expected exit 0
fn main() -> i32 {
    return 0;
}
EOF

# Case 1: An untracked new test is run
rc=0
out=$(env GIT_DIR="$r_untracked/.git" GIT_WORK_TREE="$r_untracked" \
      make test-changed TEST_CHANGED_DEPS= BASE=HEAD TEST_RUNNER="$tmp/stub_runner.sh" QUIET= 2>&1) || rc=$?

if [ $rc -eq 0 ] && echo "$out" | grep -qF "stub runner args:" \
    && echo "$out" | grep -qF "tests/unit/test_probe_untracked.zrl"; then
    pass "an untracked new test is run"
else
    fail "an untracked new test is run" "rc=$rc, out=$out"
fi

# Case 2: A renamed test's old and new paths are both passed to the runner via --no-renames
r_rename="$tmp/repo_rename"
mkdir -p "$r_rename/tests/unit"
(
    cd "$r_rename"
    git -c init.defaultBranch=main init -q
    git -c user.name=t -c user.email=t config user.name t
    git -c user.name=t -c user.email=t config user.email t
    echo "// old test" > tests/unit/test_old.zrl
    git add tests/unit/test_old.zrl
    git -c commit.gpgsign=false commit -qm "initial commit"
    git mv tests/unit/test_old.zrl tests/unit/test_new.zrl
)

rc=0
out=$(env GIT_DIR="$r_rename/.git" GIT_WORK_TREE="$r_rename" \
      make test-changed TEST_CHANGED_DEPS= BASE=HEAD TEST_RUNNER="$tmp/stub_runner.sh" QUIET= 2>&1) || rc=$?

has_old=0
has_new=0
if echo "$out" | grep -qF "tests/unit/test_old.zrl"; then has_old=1; fi
if echo "$out" | grep -qF "tests/unit/test_new.zrl"; then has_new=1; fi

if [ $rc -eq 0 ] && [ $has_old -eq 1 ] && [ $has_new -eq 1 ]; then
    pass "a renamed test's old and new paths are both in the list via --no-renames"
else
    fail "renamed test paths" "rc=$rc, has_old=$has_old, has_new=$has_new, out=$out"
fi

# Case 3: Outside a checkout everything runs
rc=0
out=$(env GIT_DIR=/dev/null make test-changed TEST_CHANGED_DEPS= TEST_RUNNER="$tmp/stub_runner.sh" QUIET= 2>&1) || rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -qF "not inside a git checkout, running all tests" \
    && echo "$out" | grep -qF "stub runner args: --gates"; then
    pass "outside a checkout everything runs"
else
    fail "outside a checkout everything runs" "rc=$rc, out=$out"
fi

# Case 4: Negative test — taking --no-renames out of the Makefile drops the renamed old path
sed 's/--no-renames//' Makefile > "$tmp/Makefile.no_renames"
rc=0
out=$(env GIT_DIR="$r_rename/.git" GIT_WORK_TREE="$r_rename" \
      make -f "$tmp/Makefile.no_renames" test-changed TEST_CHANGED_DEPS= BASE=HEAD TEST_RUNNER="$tmp/stub_runner.sh" QUIET= 2>&1) || rc=$?

if [ $rc -eq 0 ] && ! echo "$out" | grep -qF "tests/unit/test_old.zrl"; then
    pass "taking out --no-renames drops the old path as expected"
else
    fail "taking out --no-renames check" "rc=$rc, out=$out"
fi

# Case 5: Negative test — taking git ls-files out of the Makefile drops untracked tests
sed 's/git ls-files[^;)]*//' Makefile > "$tmp/Makefile.no_ls_files"
rc=0
out=$(env GIT_DIR="$r_untracked/.git" GIT_WORK_TREE="$r_untracked" \
      make -f "$tmp/Makefile.no_ls_files" test-changed TEST_CHANGED_DEPS= BASE=HEAD TEST_RUNNER="$tmp/stub_runner.sh" QUIET= 2>&1) || rc=$?

if [ $rc -eq 0 ] && ! echo "$out" | grep -qF "tests/unit/test_probe_untracked.zrl"; then
    pass "taking out git ls-files drops untracked test as expected"
else
    fail "taking out git ls-files check" "rc=$rc, out=$out"
fi

if [ $errors -gt 0 ]; then
    echo "test_test_changed: $errors test(s) failed" >&2
    exit 1
fi
echo "test_test_changed: all checks passed"
exit 0
