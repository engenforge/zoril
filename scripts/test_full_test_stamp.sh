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
t=$(mktemp -d "${TMPDIR:-/tmp}/zoril_stamp_XXXXXX")
trap 'rm -rf "$t"' EXIT INT TERM
mkdir -p "$t/scripts/lib" "$t/build"
cp scripts/full_test_stamp.sh "$t/scripts/"
cp scripts/lib/portability.sh "$t/scripts/lib/"

(
    cd "$t" && git init -q . && \
    git config user.email a@b.invalid && git config user.name t && \
    git config commit.gpgsign false && git config tag.gpgsign false && \
    git config core.hooksPath /dev/null && \
    echo "build/" > .gitignore && \
    echo one > f && git add . && git commit -q -m one
) || fail "cannot make a scratch repository"

stamp() { (cd "$t" && sh scripts/full_test_stamp.sh "$1" > "$t/build/out.txt" 2>&1); }

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
stamp_nc() { (cd "$t" && sh scripts/full_test_stamp_no_compiler.sh "$1" > "$t/build/out.txt" 2>&1); }

printf "compiler-v1" > "$t/build/zoril"
stamp_nc write || fail "write failed with no-compiler stamp"
printf "x" >> "$t/build/zoril"
stamp_nc check || fail "negative test: taking compiler hash out of key was expected to let compiler change pass undetected"
grep -q "stopping (FORCE=1 to run)" "$t/build/out.txt" || fail "no-compiler stamp did not stop when it should have failed"

# 9. Makefile scenario: unchanged tree stops, FORCE=1 reruns, and changes rerun
cat << 'MAKE_EOF' > "$t/Makefile"
test:
	@if [ "$(FORCE)" != "1" ] && ./scripts/full_test_stamp.sh check 2>/dev/null; then \
		exit 0; \
	else \
		echo "RUNNING FULL TEST"; \
	fi
MAKE_EOF
(cd "$t" && git add Makefile && git commit -q -m "Makefile") || fail "cannot commit Makefile"

stamp write || fail "write failed before Makefile scenario"
(cd "$t" && make -f Makefile test FORCE= > "$t/build/make.out" 2>&1) || fail "make test failed on unchanged tree"
grep -q "stopping (FORCE=1 to run)" "$t/build/make.out" || fail "make test on unchanged tree did not stop"
grep -q "RUNNING FULL TEST" "$t/build/make.out" && fail "make test on unchanged tree ran full test"

(cd "$t" && make -f Makefile test FORCE=1 > "$t/build/make.out" 2>&1) || fail "make test FORCE=1 failed"
grep -q "RUNNING FULL TEST" "$t/build/make.out" || fail "make test FORCE=1 did not rerun"

printf "y" >> "$t/tests/t.zrl"
(cd "$t" && make -f Makefile test FORCE= > "$t/build/make.out" 2>&1) || fail "make test after test change failed"
grep -q "RUNNING FULL TEST" "$t/build/make.out" || fail "make test after test change did not rerun"
(cd "$t" && git add -A tests/t.zrl && git commit -q -m "t") || fail "cannot commit t"
stamp write || fail "stamp write after t commit failed"

printf "z" >> "$t/build/zoril"
(cd "$t" && make -f Makefile test FORCE= > "$t/build/make.out" 2>&1) || fail "make test after compiler change failed"
grep -q "RUNNING FULL TEST" "$t/build/make.out" || fail "make test after compiler change did not rerun"
stamp write || fail "stamp write after compiler change failed"

printf "w" >> "$t/scripts/helper.sh"
(cd "$t" && make -f Makefile test FORCE= > "$t/build/make.out" 2>&1) || fail "make test after script change failed"
grep -q "RUNNING FULL TEST" "$t/build/make.out" || fail "make test after script change did not rerun"

echo "[PASS] full-test-stamp: the stamp stops rerun on an unchanged tree and reruns on tree, compiler or script changes (FORCE=1 forces rerun)"
