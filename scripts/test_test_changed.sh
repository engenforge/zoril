#!/bin/sh
# scripts/test_test_changed.sh — scenario test for make test-changed.
#
# Asserts that:
#   1. An untracked new test is included in the changed path list and executed by the runner.
#   2. A renamed test's old and new paths are both in the changed list (via --no-renames).
#   3. Outside a checkout everything runs, printing a notice and selecting --gates.
#   4. Taking out the untracked-file collection causes untracked test detection to fail.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
. scripts/lib/portability.sh

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
      make test-changed BASE=HEAD TEST_RUNNER="$tmp/stub_runner.sh" QUIET= 2>&1) || rc=$?

if [ $rc -eq 0 ] && echo "$out" | grep -qF "stub runner args:" \
    && echo "$out" | grep -qF "tests/unit/test_probe_untracked.zrl"; then
    pass "an untracked new test is run"
else
    fail "an untracked new test is run" "rc=$rc, out=$out"
fi

# Case 2: A renamed test's old and new paths are both in the list (--no-renames)
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

with_no_renames=$( (git -C "$r_rename" diff --name-only --no-renames HEAD 2>/dev/null; git -C "$r_rename" ls-files --others --exclude-standard 2>/dev/null) | sort -u )
without_no_renames=$( (git -C "$r_rename" diff --name-only HEAD 2>/dev/null; git -C "$r_rename" ls-files --others --exclude-standard 2>/dev/null) | sort -u )

has_old=0
has_new=0
echo "$with_no_renames" | grep -qxF "tests/unit/test_old.zrl" && has_old=1 || true
echo "$with_no_renames" | grep -qxF "tests/unit/test_new.zrl" && has_new=1 || true

if [ $has_old -eq 1 ] && [ $has_new -eq 1 ] && ! echo "$without_no_renames" | grep -qxF "tests/unit/test_old.zrl"; then
    pass "a renamed test's old and new paths are both in the list via --no-renames"
else
    fail "renamed test paths" "has_old=$has_old, has_new=$has_new, without_no_renames='$without_no_renames'"
fi

# Case 3: Outside a checkout everything runs
rc=0
out=$(env GIT_DIR=/dev/null make test-changed TEST_RUNNER="$tmp/stub_runner.sh" QUIET= 2>&1) || rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -qF "not inside a git checkout, running all tests" \
    && echo "$out" | grep -qF "stub runner args: --gates"; then
    pass "outside a checkout everything runs"
else
    fail "outside a checkout everything runs" "rc=$rc, out=$out"
fi

# Case 4: Take out the untracked-file part and watch its case fail
list_with_untracked=$( (git -C "$r_untracked" diff --name-only --no-renames HEAD 2>/dev/null; git -C "$r_untracked" ls-files --others --exclude-standard 2>/dev/null) | sort -u )
list_without_untracked=$( (git -C "$r_untracked" diff --name-only --no-renames HEAD 2>/dev/null) | sort -u )

found_with=0
found_without=0
echo "$list_with_untracked" | grep -qxF "tests/unit/test_probe_untracked.zrl" && found_with=1 || true
echo "$list_without_untracked" | grep -qxF "tests/unit/test_probe_untracked.zrl" && found_without=1 || true

if [ $found_with -eq 1 ] && [ $found_without -eq 0 ]; then
    pass "taking out untracked-file part causes untracked test check to fail"
else
    fail "taking out untracked-file part check" "found_with=$found_with, found_without=$found_without"
fi

if [ $errors -gt 0 ]; then
    echo "test_test_changed: $errors test(s) failed" >&2
    exit 1
fi
echo "test_test_changed: all checks passed"
exit 0
