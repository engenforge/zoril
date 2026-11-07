#!/bin/sh
# scripts/test_full_test_stamp.sh — scripts/full_test_stamp.sh ties the stamp to the tree it was written on.
cd "$(dirname "$0")/.." || exit 2

# Tests never sign commits or run user-configured Git hooks, and must not depend on user Git config.
GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_GLOBAL
GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_SYSTEM
GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_NOSYSTEM
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS FORCE
for _v in $(env 2>/dev/null | sed -n 's/^\(GIT_CONFIG_[KEY|VALUE].*\)=.*/\1/p'); do
    unset "$_v"
done

command -v git >/dev/null 2>&1 || { echo "[SKIP] full-test-stamp: no git"; exit 0; }
fail() { echo "[FAIL] full-test-stamp: $1"; exit 1; }
pass() { echo "  [PASS] full-test-stamp: $1"; }

t=$(mktemp -d "${TMPDIR:-/tmp}/zoril_stamp_XXXXXX")
mock_bin=$(mktemp -d "${TMPDIR:-/tmp}/mock_bin_XXXXXX")
trap 'rm -rf "$t" "$mock_bin"' EXIT INT TERM
mkdir -p "$t/scripts/lib" "$t/build"
cp scripts/full_test_stamp.sh "$t/scripts/"
cp scripts/check_deps.sh "$t/scripts/"
cp scripts/lib/portability.sh "$t/scripts/lib/"
cp scripts/lib/scdoc_version.sh "$t/scripts/lib/"

(
    cd "$t" && git init -q . && \
    git config user.email a@b.invalid && git config user.name t && \
    git config commit.gpgsign false && git config tag.gpgsign false && \
    git config core.hooksPath /dev/null && \
    echo "build/" > .gitignore && \
    echo one > f && git add . && git commit -q -m one
) || fail "cannot make a scratch repository"

stamp() { (cd "$t" && sh scripts/full_test_stamp.sh "$@" > "$t/build/out.txt" 2>&1); }

# 1. Missing stamp check fails
stamp check && fail "a tree with no stamp passed the check"
grep -q "no whole 'make test'" "$t/build/out.txt" || fail "the missing stamp is not explained"

# 2. Fresh stamp passes and outputs the stop message naming earlier run
stamp write || fail "write failed"
stamp check || fail "a fresh stamp did not pass"
grep -q "unchanged since earlier run" "$t/build/out.txt" || fail "stop message did not name earlier run"
grep -q "stopping (FORCE=1 to run)" "$t/build/out.txt" || fail "stop message did not mention FORCE=1"

# 3. Second run on an unchanged tree stops
stamp check || fail "second check on unchanged tree did not pass"
grep -q "stopping (FORCE=1 to run)" "$t/build/out.txt" || fail "second check did not output stop message"

# 4. Changes in doc/tasks/ do not invalidate the stamp
mkdir -p "$t/doc/tasks"
echo "task tracking" > "$t/doc/tasks/active.tm.md"
stamp check || fail "change in doc/tasks/ invalidated stamp"
grep -q "stopping (FORCE=1 to run)" "$t/build/out.txt" || fail "doc/tasks change did not output stop message"
rm -rf "$t/doc/tasks"

# 5. One-byte change to a test file reruns
mkdir -p "$t/tests"
echo "test" > "$t/tests/t.zrl"
stamp check && fail "untracked test file did not invalidate stamp"
grep -q "changed since" "$t/build/out.txt" || fail "untracked test file did not explain why stamp failed"
stamp write || fail "stamp write failed with test file"
stamp check || fail "stamp check failed after write"
printf "x" >> "$t/tests/t.zrl"
stamp check && fail "one-byte change to test file did not invalidate stamp"
grep -q "changed since" "$t/build/out.txt" || fail "one-byte change to test did not explain why stamp failed"
(cd "$t" && git add -A tests && git commit -q -m "tests") || fail "cannot commit tests"
stamp write || fail "stamp write failed after commit"
stamp check || fail "stamp check failed after commit write"

# 6. One-byte change to a script reruns
mkdir -p "$t/scripts"
printf "#!/bin/sh\nexit 0\n" > "$t/scripts/helper.sh"
stamp check && fail "untracked script did not invalidate stamp"
stamp write || fail "stamp write failed with script"
stamp check || fail "stamp check failed after script write"
printf " " >> "$t/scripts/helper.sh"
stamp check && fail "one-byte change to script did not invalidate stamp"
grep -q "changed since" "$t/build/out.txt" || fail "one-byte script change did not explain why stamp failed"
(cd "$t" && git add -A scripts/helper.sh && git commit -q -m "helper") || fail "cannot commit helper"
stamp write || fail "stamp write failed after script commit"
stamp check || fail "stamp check failed after script commit"

# 7. One-byte change to build/zoril reruns
printf "compiler-v1" > "$t/build/zoril"
stamp check && fail "new compiler build did not invalidate stamp"
stamp write || fail "stamp write failed with compiler"
stamp check || fail "stamp check failed after compiler write"
printf "x" >> "$t/build/zoril"
stamp check && fail "one-byte change to build/zoril did not invalidate stamp"
grep -q "changed since" "$t/build/out.txt" || fail "one-byte compiler change did not explain why stamp failed"

# 8. Negative test: taking compiler hash out of key causes compiler change to pass undetected
awk '{ gsub(/compiler_hash\(\) \{/, "compiler_hash() { echo \"ignored\"; return 0; }\n_old_compiler_hash() {"); print }' \
    "$t/scripts/full_test_stamp.sh" > "$t/scripts/full_test_stamp_no_compiler.sh"
chmod +x "$t/scripts/full_test_stamp_no_compiler.sh"
stamp_nc() { (cd "$t" && sh scripts/full_test_stamp_no_compiler.sh "$@" > "$t/build/out.txt" 2>&1); }

printf "compiler-v1" > "$t/build/zoril"
stamp_nc write || fail "write failed with no-compiler stamp"
printf "x" >> "$t/build/zoril"
stamp_nc check || fail "negative test: taking compiler hash out of key was expected to let compiler change pass undetected"
grep -q "stopping (FORCE=1 to run)" "$t/build/out.txt" || fail "no-compiler stamp did not stop when it should have failed"

# 9. Loose objects: tree_hash does not write loose objects into .git/objects on dirty working tree
mkdir -p "$t/tests"
echo "dirty test" > "$t/tests/dirty.zrl"
echo "untracked test" > "$t/tests/untracked.zrl"
obj_before=$(find "$t/.git/objects" -type f | wc -l)
stamp snapshot "$t/build/obj_test.pending" || fail "snapshot failed"
stamp check >/dev/null 2>&1 || true
obj_after=$(find "$t/.git/objects" -type f | wc -l)
[ "$obj_before" -eq "$obj_after" ] || fail "tree_hash wrote loose objects into .git/objects (before=$obj_before, after=$obj_after)"
rm -f "$t/tests/dirty.zrl" "$t/tests/untracked.zrl" "$t/build/obj_test.pending"

# 10. Snapshot vs Write: editing a test file between snapshot and write reruns
(cd "$t" && git add -A && git commit -q -m "clean") || fail "clean commit failed"
stamp snapshot "$t/build/stamp.pending" || fail "snapshot failed"
printf "modified-during-run" >> "$t/tests/t.zrl"
# Write using the pending snapshot taken before the edit
stamp write "$t/build/stamp.pending" "Total: 10 run, 10 passed, 0 failed, 0 skipped (1.0s)" || fail "write with snapshot failed"
# Stamp check must detect that the working tree changed since the snapshot
stamp check && fail "edit between snapshot and write was not caught by check"
grep -q "changed since" "$t/build/out.txt" || fail "edit between snapshot and write did not explain why stamp failed"

# Negative test: taking snapshot out (hashing at write time) passes undetected
stamp write "" "Total: 10 run, 10 passed, 0 failed, 0 skipped (1.0s)" || fail "direct write failed"
stamp check || fail "negative test: direct write at write time should have passed undetected"

# 11. Toolchain fingerprint tracks tool absence / presence
(cd "$t" && git add -A && git commit -q -m "clean2") || fail "clean2 commit failed"
# Initially optional_probe_tool is absent
out_absent=$(cd "$t" && env CPROC=optional_probe_tool sh scripts/check_deps.sh --fingerprint 2>/dev/null)
echo "$out_absent" | grep -q "optional_probe_tool: absent" || fail "probe tool was not detected as absent"

(cd "$t" && env CPROC=optional_probe_tool sh scripts/full_test_stamp.sh write "" "Total: 10 run, 10 passed, 0 failed, 0 skipped (1.0s)") || fail "write failed"
(cd "$t" && env CPROC=optional_probe_tool sh scripts/full_test_stamp.sh check) || fail "clean check failed"

# Introduce the tool in PATH (absent -> present)
cat << 'EOF' > "$mock_bin/optional_probe_tool"
#!/bin/sh
echo "probe-1.0"
EOF
chmod +x "$mock_bin/optional_probe_tool"

out_tool=$(cd "$t" && env PATH="$mock_bin:$PATH" CPROC=optional_probe_tool sh scripts/full_test_stamp.sh check 2>&1) && fail "tool going from absent to present did not fail check"
echo "$out_tool" | grep -q "toolchain fingerprint has changed" || fail "tool presence did not cite toolchain fingerprint change: '$out_tool'"

# Writing stamp with the tool present passes
(cd "$t" && env PATH="$mock_bin:$PATH" CPROC=optional_probe_tool sh scripts/full_test_stamp.sh write "" "Total: 10 run, 10 passed, 0 failed, 0 skipped (1.0s)") || fail "write with tool present failed"
(cd "$t" && env PATH="$mock_bin:$PATH" CPROC=optional_probe_tool sh scripts/full_test_stamp.sh check) || fail "check with tool present failed"

# Removing the tool fails again (present -> absent)
rm -f "$mock_bin/optional_probe_tool"
out_tool_absent=$(cd "$t" && env PATH="$mock_bin:$PATH" CPROC=optional_probe_tool sh scripts/full_test_stamp.sh check 2>&1) && fail "tool going from present to absent did not fail check"
echo "$out_tool_absent" | grep -q "toolchain fingerprint has changed" || fail "tool absence did not cite toolchain fingerprint change"

# 12. Real Makefile scenario: unchanged tree stops and prints Total:, FORCE=1 reruns, T= reruns, TSUITE= reruns
stub_runner="$t/stub_runner.sh"
cat << 'EOF' > "$stub_runner"
#!/bin/sh
echo "stub runner args: $*"
exit 0
EOF
chmod +x "$stub_runner"

# Save pre-existing stamp in real repository if present
_saved_stamp="$t/pre_existing.stamp"
rm -f "$_saved_stamp"
[ -f build/full-test.stamp ] && cp build/full-test.stamp "$_saved_stamp" || true

# Write fresh stamp for the real repository state
./scripts/full_test_stamp.sh write "" "Total: 3417 run, 3417 passed, 0 failed, 88 skipped (238.0s)" || fail "write stamp failed in real repo"

# Unchanged tree stops and prints stop message plus Total: line
out_make=$(make test TEST_DEPS= TEST_RUNNER="$stub_runner" FORCE= 2>&1) || fail "make test failed on unchanged tree"
echo "$out_make" | grep -q "stopping (FORCE=1 to run)" || fail "make test on unchanged tree did not print stop line"
echo "$out_make" | grep -q "^Total: 3417 run, 3417 passed, 0 failed, 88 skipped (238.0s)" || fail "make test stop did not print Total: line"
echo "$out_make" | grep -q "stub runner args:" && fail "make test on unchanged tree ran stub runner"

# FORCE=1 reruns
out_force=$(make test TEST_DEPS= TEST_RUNNER="$stub_runner" FORCE=1 2>&1) || fail "make test FORCE=1 failed"
echo "$out_force" | grep -q "stub runner args: --quiet --suite all" || fail "make test FORCE=1 did not rerun suite all"

# T=... reruns
out_t=$(make test TEST_DEPS= TEST_RUNNER="$stub_runner" FORCE= T=arena_basic 2>&1) || fail "make test T=... failed"
echo "$out_t" | grep -q "stub runner args: --verbose --filter arena_basic tests corpus" || fail "make test T=... did not pass filter to runner: '$out_t'"

# TSUITE=language reruns
out_tsuite=$(make test TEST_DEPS= TEST_RUNNER="$stub_runner" FORCE= TSUITE=language 2>&1) || fail "make test TSUITE=language failed"
echo "$out_tsuite" | grep -q "stub runner args: --quiet --suite language" || fail "make test TSUITE=language did not pass suite to runner"

# Negative test: taking stamp check out of Makefile causes make test on unchanged tree to rerun stub runner
sed 's/full_test_stamp\.sh check/false/' Makefile > "$t/Makefile.no_stamp"
out_no_stamp=$(make -f "$t/Makefile.no_stamp" test TEST_DEPS= TEST_RUNNER="$stub_runner" FORCE= 2>&1) || fail "make -f Makefile.no_stamp failed"
echo "$out_no_stamp" | grep -q "stub runner args:" || fail "taking stamp check out of Makefile was expected to rerun runner"

# Restore pre-existing stamp if it existed, otherwise remove temporary stamp
rm -f build/full-test.stamp
[ -f "$_saved_stamp" ] && mv "$_saved_stamp" build/full-test.stamp || true

echo "[PASS] full-test-stamp: the stamp stops rerun on an unchanged tree and reruns on tree, compiler, script or tool changes (FORCE=1 forces rerun)"
exit 0
