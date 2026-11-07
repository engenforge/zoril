#!/bin/sh
# scripts/test_portability_lib.sh — Tests for scripts/lib/portability.sh and scripts/lib/layout.sh
#
# Verifies:
#   1. scripts/lib/portability.sh functions (now_ms, nproc_count, sha256_of, sha256_check, file_perm)
#   2. scripts/lib/layout.sh resolution (private, public, relative)
#   3. Library sourcing preservation of caller positional arguments (no early exit on --selftest)
#
# Usage:
#   ./scripts/test_portability_lib.sh
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORTABILITY_LIB="$REPO_ROOT/scripts/lib/portability.sh"
LAYOUT_LIB="$REPO_ROOT/scripts/lib/layout.sh"

tmp="${TMPDIR:-/tmp}/test_portability_lib.$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT INT TERM

errors=0
fail() { echo "[FAIL] $1" >&2; errors=$((errors + 1)); }
pass() { echo "[PASS] $1"; }

# 1. Test scripts/lib/portability.sh
. "$PORTABILITY_LIB"

# Test now_ms
t=$(now_ms)
case "$t" in
    *[!0-9]*|"") fail "portability-lib: now_ms returned non-integer '$t'" ;;
    *) ;;
esac

# Test nproc_count
np=$(nproc_count)
if [ "$np" -lt 1 ]; then
    fail "portability-lib: nproc_count returned $np < 1"
fi

# Test nproc_count honours affinity mask under taskset (Z-0127, Z-0128)
if command -v taskset >/dev/null 2>&1; then
    first_cpu=$(taskset -c -p $$ 2>/dev/null | sed -n 's/.*affinity list: *\([0-9][0-9]*\).*/\1/p')
    if [ -n "$first_cpu" ]; then
        np_taskset=$(taskset -c "$first_cpu" sh -c ". \"$PORTABILITY_LIB\"; nproc_count" 2>/dev/null) || np_taskset=""
        if [ "$np_taskset" != "1" ]; then
            fail "portability-lib: nproc_count under taskset -c $first_cpu returned '$np_taskset' (expected 1)"
        fi
    else
        echo "[SKIP] portability-lib: taskset affinity test could not determine current CPU mask"
    fi
else
    echo "[SKIP] portability-lib: taskset affinity test needs taskset (Linux)"
fi

# Test nproc_count ignores OMP_NUM_THREADS and OMP_THREAD_LIMIT (Z-0128)
np_omp=$(OMP_NUM_THREADS=1 sh -c ". \"$PORTABILITY_LIB\"; nproc_count")
if [ "$np_omp" != "$np" ]; then
    fail "portability-lib: OMP_NUM_THREADS=1 changed nproc_count from $np to $np_omp"
fi

# Test sha256_of and sha256_check
printf 'hello\n' > "$tmp/good.txt"
printf 'world\n' > "$tmp/bad.txt"
good_hash=$(sha256_of "$tmp/good.txt" | awk '{print $1}')

# Matching hash list
printf '%s  good.txt\n' "$good_hash" > "$tmp/good.sha256"
if ! (cd "$tmp" && sha256_check good.sha256 > "$tmp/out.log" 2>&1) || ! grep -q "good.txt: OK" "$tmp/out.log"; then
    fail "portability-lib: sha256_check failed on matching hash"
fi

# Mismatched hash list
printf '%s  good.txt\n0000000000000000000000000000000000000000000000000000000000000000  bad.txt\n' "$good_hash" > "$tmp/mixed.sha256"
if (cd "$tmp" && sha256_check mixed.sha256 > "$tmp/mixed.log" 2>&1); then
    fail "portability-lib: sha256_check succeeded on mismatched hash"
elif ! grep -q "good.txt: OK" "$tmp/mixed.log" || ! grep -q "bad.txt: FAILED" "$tmp/mixed.log"; then
    fail "portability-lib: sha256_check output unexpected for mixed list"
fi

# Test file_perm
touch "$tmp/perm_test.txt"
chmod 755 "$tmp/perm_test.txt"
p=$(file_perm "$tmp/perm_test.txt")
if [ "$p" != "755" ]; then
    fail "portability-lib: file_perm returned '$p' (expected 755)"
fi

if [ "$errors" -eq 0 ]; then
    pass "portability-lib: now_ms, nproc, sha256_of, sha256_check, file_perm passed"
fi

# 2. Test scripts/lib/layout.sh
# Test private layout
mkdir -p "$tmp/private/stage0-C" "$tmp/private/stage1"
(
    REPO_ROOT="$tmp/private"
    . "$LAYOUT_LIB"
    if [ "$STAGE0_DIR" != "stage0-C" ] || [ "$STAGE1_DIR" != "stage1" ]; then
        exit 1
    fi
) || fail "layout-lib: private layout detection failed"

# Test public export layout
mkdir -p "$tmp/public/bootstrap/stage0-c" "$tmp/public/bootstrap/stage1"
(
    REPO_ROOT="$tmp/public"
    . "$LAYOUT_LIB"
    if [ "$STAGE0_DIR" != "bootstrap/stage0-c" ] || [ "$STAGE1_DIR" != "bootstrap/stage1" ]; then
        exit 1
    fi
) || fail "layout-lib: public layout detection failed"

# Test relative layout when REPO_ROOT is unset
(
    unset REPO_ROOT
    cd "$tmp/public"
    . "$LAYOUT_LIB"
    if [ "$STAGE0_DIR" != "bootstrap/stage0-c" ] || [ "$STAGE1_DIR" != "bootstrap/stage1" ]; then
        exit 1
    fi
) || fail "layout-lib: relative layout detection failed"

if [ "$errors" -eq 0 ]; then
    pass "layout-lib: private, public, and relative layouts passed"
fi

# 3. Test that sourcing libraries with caller arguments (e.g. --selftest) does not exit caller
res=$(sh -c '. '"$PORTABILITY_LIB"'; echo "caller continues"' sh --selftest 2>/dev/null || true)
if [ "$res" != "caller continues" ]; then
    fail "lib-sourcing: portability.sh intercepted caller arguments (got '$res')"
fi

res=$(sh -c '. '"$LAYOUT_LIB"'; echo "caller continues"' sh --selftest 2>/dev/null || true)
if [ "$res" != "caller continues" ]; then
    fail "lib-sourcing: layout.sh intercepted caller arguments (got '$res')"
fi

if [ "$errors" -eq 0 ]; then
    pass "lib-sourcing: caller arguments preserved without early exit"
fi

# 4. Test run_with_timeout process group killing vs --foreground opt-in
# Without --foreground, child processes must be killed on expiration (no orphan)
sh -c '. '"$PORTABILITY_LIB"'; run_with_timeout -k 1 1 sh -c "sleep 77 & wait"' >/dev/null 2>&1 || true
sleep 1.5
if pgrep -fx 'sleep 77' >/dev/null 2>&1; then
    kill -9 $(pgrep -fx 'sleep 77') 2>/dev/null || true
    fail "run_with_timeout: child process was orphaned after timeout without --foreground"
fi

# With --foreground, caller PGID is kept (terminal Ctrl-C signal propagation)
my_pgid=$(ps -o pgid= -p $$ | tr -d ' ')
child_pgid=$(. "$PORTABILITY_LIB"; run_with_timeout --foreground 5 sh -c 'ps -o pgid= -p $$' | tr -d ' ')
if [ "$my_pgid" != "$child_pgid" ]; then
    fail "run_with_timeout: caller pgid ($my_pgid) not kept with --foreground (got $child_pgid)"
fi

if [ "$errors" -eq 0 ]; then
    pass "run_with_timeout: process group killed without --foreground, pgid preserved with --foreground"
fi

[ "$errors" -eq 0 ] || exit 1
exit 0
