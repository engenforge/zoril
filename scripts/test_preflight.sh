#!/bin/sh
# scripts/test_preflight.sh — test scripts/preflight.sh error handling and concurrency.
#
# Asserts that:
#   1. Failing selfhost-check exits non-zero and reports both exit codes.
#   2. Failing mutation-check exits non-zero and reports both exit codes.
#   3. Dual failure under --changed reports preflight-changed prefix and both codes.
#   4. --changed passes the flag to mutation-check.
#   5. Concurrency: selfhost runs in background and is waited on before proceeding.
set -u
cd "$(dirname "$0")/.." || exit 2
. scripts/lib/portability.sh

if ! ./scripts/check_deps.sh --required-only preflight >/dev/null 2>&1; then
    echo "[SKIP] preflight-selftest: preflight dependencies not satisfied"
    exit 0
fi

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

# Create stub scripts
cat << 'EOF' > "$tmp/stub_pass.sh"
#!/bin/sh
echo "stub: selfhost ok"
exit 0
EOF

# Cases 1-9 are about other steps; a real rejection differential would build a second compiler.
export PREFLIGHT_REJECT_DIFF="$tmp/stub_pass.sh"

cat << 'EOF' > "$tmp/stub_fail_selfhost.sh"
#!/bin/sh
echo "stub: selfhost failed"
exit 42
EOF

cat << 'EOF' > "$tmp/stub_fail_mutation.sh"
#!/bin/sh
echo "stub: mutation failed"
exit 17
EOF

cat << 'EOF' > "$tmp/stub_verify_changed.sh"
#!/bin/sh
if [ "${1:-}" = "--changed" ]; then
    echo "stub: received --changed"
    exit 23
fi
echo "stub: missing --changed"
exit 99
EOF

cat << 'EOF' > "$tmp/stub_slow_selfhost.sh"
#!/bin/sh
sleep 0.2
echo "stub: slow selfhost done"
exit 0
EOF

cat << 'EOF' > "$tmp/stub_fast_mutation.sh"
#!/bin/sh
echo "stub: fast mutation done"
exit 1
EOF

cat << 'EOF' > "$tmp/stub_fail_bench.sh"
#!/bin/sh
echo "stub: bench failed"
exit 31
EOF

cat << 'EOF' > "$tmp/stub_fail_density.sh"
#!/bin/sh
echo "stub: density failed"
exit 32
EOF

cat << 'EOF' > "$tmp/stub_fail_fuzz.sh"
#!/bin/sh
echo "stub: fuzz failed"
exit 33
EOF

cat << 'EOF' > "$tmp/stub_track_density.sh"
#!/bin/sh
if [ -n "${PREFLIGHT_TEST_TRACE:-}" ]; then
    echo "density ran" >> "$PREFLIGHT_TEST_TRACE"
fi
exit 0
EOF

cat << 'EOF' > "$tmp/stub_track_fuzz.sh"
#!/bin/sh
if [ -n "${PREFLIGHT_TEST_TRACE:-}" ]; then
    echo "fuzz ran" >> "$PREFLIGHT_TEST_TRACE"
fi
exit 0
EOF

chmod +x "$tmp"/*.sh

status=0
fail() { echo "[FAIL] preflight-selftest: $1" >&2; status=1; }
pass() { echo "[PASS] preflight-selftest: $1"; }

# Preserve existing preflight log if present
saved_log=""
if [ -f build/preflight-selfhost.log ]; then
    saved_log="$(mktemp)"
    cp build/preflight-selfhost.log "$saved_log"
fi
restore_log() {
    if [ -n "$saved_log" ] && [ -f "$saved_log" ]; then
        cp "$saved_log" build/preflight-selfhost.log
        rm -f "$saved_log"
    fi
}
trap 'cleanup; restore_log' EXIT INT TERM

# Case 1: selfhost failure
rc=0
out=$(PREFLIGHT_SELFHOST="$tmp/stub_fail_selfhost.sh" PREFLIGHT_MUTATION="$tmp/stub_pass.sh" ./scripts/preflight.sh 2>&1) || rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -qF "preflight: selfhost-check exit 42, mutation-check exit 0"; then
    pass "reports failing selfhost exit code and aborts"
else
    fail "expected non-zero exit and selfhost exit 42 report (rc=$rc, out=$out)"
fi

# Case 2: mutation failure
rc=0
out=$(PREFLIGHT_SELFHOST="$tmp/stub_pass.sh" PREFLIGHT_MUTATION="$tmp/stub_fail_mutation.sh" ./scripts/preflight.sh 2>&1) || rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -qF "preflight: selfhost-check exit 0, mutation-check exit 17"; then
    pass "reports failing mutation exit code and aborts"
else
    fail "expected non-zero exit and mutation exit 17 report (rc=$rc, out=$out)"
fi

# Case 3: dual failure with --changed
rc=0
out=$(PREFLIGHT_SELFHOST="$tmp/stub_fail_selfhost.sh" PREFLIGHT_MUTATION="$tmp/stub_fail_mutation.sh" ./scripts/preflight.sh --changed 2>&1) || rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -qF "preflight-changed: selfhost-check exit 42, mutation-check exit 17"; then
    pass "reports preflight-changed prefix and dual failure codes"
else
    fail "expected non-zero exit and preflight-changed report (rc=$rc, out=$out)"
fi

# Case 4: --changed flag passed to mutation command
rc=0
out=$(PREFLIGHT_SELFHOST="$tmp/stub_pass.sh" PREFLIGHT_MUTATION="$tmp/stub_verify_changed.sh" ./scripts/preflight.sh --changed 2>&1) || rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -qF "preflight-changed: selfhost-check exit 0, mutation-check exit 23"; then
    pass "--changed flag correctly passed to mutation-check"
else
    fail "expected --changed passed to mutation command (rc=$rc, out=$out)"
fi

# Case 5: concurrency and wait
rc=0
out=$(PREFLIGHT_SELFHOST="$tmp/stub_slow_selfhost.sh" PREFLIGHT_MUTATION="$tmp/stub_fast_mutation.sh" ./scripts/preflight.sh 2>&1) || rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -qF "stub: slow selfhost done" && echo "$out" | grep -qF "preflight: selfhost-check exit 0, mutation-check exit 1"; then
    pass "selfhost runs concurrently in background and is waited upon"
else
    fail "expected background selfhost to complete before report (rc=$rc, out=$out)"
fi

# Case 6: bench failure in full mode aborts and suppresses density and fuzz
rc=0
trace_file="$tmp/trace_case6.log"
out=$(PREFLIGHT_SELFHOST="$tmp/stub_pass.sh" \
      PREFLIGHT_MUTATION="$tmp/stub_pass.sh" \
      PREFLIGHT_BENCH="$tmp/stub_fail_bench.sh" \
      PREFLIGHT_DENSITY="$tmp/stub_track_density.sh" \
      PREFLIGHT_FUZZ="$tmp/stub_track_fuzz.sh" \
      PREFLIGHT_TEST_TRACE="$trace_file" \
      ./scripts/preflight.sh 2>&1) || rc=$?
if [ $rc -ne 0 ]; then
    if [ ! -f "$trace_file" ]; then
        pass "bench failure in full mode aborts with non-zero exit and suppresses density/fuzz"
    else
        fail "bench failure in full mode executed subsequent steps: $(cat "$trace_file")"
    fi
else
    fail "expected non-zero exit on bench failure in full mode (rc=$rc, out=$out)"
fi

# Case 7: bench failure with --changed aborts
rc=0
out=$(PREFLIGHT_SELFHOST="$tmp/stub_pass.sh" \
      PREFLIGHT_MUTATION="$tmp/stub_pass.sh" \
      PREFLIGHT_BENCH="$tmp/stub_fail_bench.sh" \
      ./scripts/preflight.sh --changed 2>&1) || rc=$?
if [ $rc -ne 0 ]; then
    pass "bench failure in --changed mode aborts with non-zero exit"
else
    fail "expected non-zero exit on bench failure in --changed mode (rc=$rc, out=$out)"
fi

# Case 8: density failure in full mode aborts and suppresses fuzz
rc=0
trace_file="$tmp/trace_case8.log"
out=$(PREFLIGHT_SELFHOST="$tmp/stub_pass.sh" \
      PREFLIGHT_MUTATION="$tmp/stub_pass.sh" \
      PREFLIGHT_BENCH="$tmp/stub_pass.sh" \
      PREFLIGHT_DENSITY="$tmp/stub_fail_density.sh" \
      PREFLIGHT_FUZZ="$tmp/stub_track_fuzz.sh" \
      PREFLIGHT_TEST_TRACE="$trace_file" \
      ./scripts/preflight.sh 2>&1) || rc=$?
if [ $rc -ne 0 ]; then
    if [ ! -f "$trace_file" ]; then
        pass "density failure in full mode aborts with non-zero exit and suppresses fuzz"
    else
        fail "density failure in full mode executed fuzz: $(cat "$trace_file")"
    fi
else
    fail "expected non-zero exit on density failure in full mode (rc=$rc, out=$out)"
fi

# Case 9: fuzz failure in full mode aborts
rc=0
out=$(PREFLIGHT_SELFHOST="$tmp/stub_pass.sh" \
      PREFLIGHT_MUTATION="$tmp/stub_pass.sh" \
      PREFLIGHT_BENCH="$tmp/stub_pass.sh" \
      PREFLIGHT_DENSITY="$tmp/stub_pass.sh" \
      PREFLIGHT_FUZZ="$tmp/stub_fail_fuzz.sh" \
      ./scripts/preflight.sh 2>&1) || rc=$?
if [ $rc -ne 0 ]; then
    pass "fuzz failure in full mode aborts with non-zero exit"
else
    fail "expected non-zero exit on fuzz failure in full mode (rc=$rc, out=$out)"
fi

# Cases 10-11: the rejection differential runs when a checker differs from its base, fails the
# preflight when it fails, and is skipped (saying so) when none differs. The base is a commit whose
# checkers differ from this tree's, or this tree's own HEAD for the unchanged case.
cat << 'EOS' > "$tmp/stub_fail_reject_diff.sh"
#!/bin/sh
echo "stub: reject-diff failed"
exit 23
EOS
chmod +x "$tmp/stub_fail_reject_diff.sh"
older=$(git rev-parse --verify -q '2363209b^' 2>/dev/null || true)
if [ -n "$older" ]; then
    rc=0
    out=$(PREFLIGHT_SELFHOST="$tmp/stub_pass.sh" PREFLIGHT_MUTATION="$tmp/stub_pass.sh" \
          PREFLIGHT_REJECT_BASE="$older" PREFLIGHT_REJECT_DIFF="$tmp/stub_fail_reject_diff.sh" \
          ./scripts/preflight.sh --changed 2>&1) || rc=$?
    if [ $rc -eq 23 ] && echo "$out" | grep -qF "stub: reject-diff failed"; then
        pass "a failing rejection differential fails the preflight when a checker differs from its base"
    else
        fail "the rejection differential did not run or did not fail the preflight (rc=$rc, out=$out)"
    fi
else
    skip_case="no history to compare with"
    echo "[SKIP] preflight-selftest: case 10 needs git history ($skip_case)"
fi
rc=0
out=$(PREFLIGHT_SELFHOST="$tmp/stub_pass.sh" PREFLIGHT_MUTATION="$tmp/stub_pass.sh" \
      PREFLIGHT_REJECT_BASE=HEAD PREFLIGHT_REJECT_DIFF="$tmp/stub_fail_reject_diff.sh" \
      PREFLIGHT_BENCH="$tmp/stub_pass.sh" PREFLIGHT_CHECKED="$tmp/stub_pass.sh" PREFLIGHT_CALIBRATE="$tmp/stub_pass.sh" \
      ./scripts/preflight.sh --changed 2>&1) || rc=$?
if git diff --quiet HEAD -- src/summary_pass.zrl src/check_zir.zrl src/verify.zrl src/main.zrl src/interface_print.zrl src/driver src/lower_zir src/parser src/parser.zrl src/ast.zrl 2>/dev/null; then
    if [ $rc -eq 0 ] && echo "$out" | grep -qF "[SKIP] reject-diff"; then
        pass "the rejection differential is skipped, saying so, when no checker differs from its base"
    else
        fail "expected a [SKIP] reject-diff line and success (rc=$rc, out=$out)"
    fi
else
    echo "[SKIP] preflight-selftest: case 11 needs the checkers to equal HEAD's (the tree has uncommitted checker changes)"
fi

# Case 12: with no base given, the run says which base it chose (the working tree against HEAD when the
# tree differs from it, else the upstream branch), so a committed change is not silently compared with itself.
rc=0
out=$(env -u PREFLIGHT_REJECT_BASE PREFLIGHT_SELFHOST="$tmp/stub_pass.sh" PREFLIGHT_MUTATION="$tmp/stub_pass.sh" \
      PREFLIGHT_REJECT_DIFF="$tmp/stub_pass.sh" \
      PREFLIGHT_BENCH="$tmp/stub_pass.sh" PREFLIGHT_CHECKED="$tmp/stub_pass.sh" PREFLIGHT_CALIBRATE="$tmp/stub_pass.sh" \
      ./scripts/preflight.sh --changed 2>&1) || rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -E "reject-diff.*(against HEAD|against .*/|PREFLIGHT_REJECT_BASE)" > /dev/null; then
    pass "the rejection differential names the base it chose when none is given"
else
    fail "expected the chosen base to be named (rc=$rc, out=$out)"
fi

exit $status
