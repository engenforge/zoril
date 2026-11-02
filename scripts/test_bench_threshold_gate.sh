#!/bin/sh
# scripts/test_bench_threshold_gate.sh — tests for the runtime_ratio_vs_gcc_o2 noise retry and regression detection.
set -eu

cd "$(dirname "$0")/.."
BENCH="$(pwd)/scripts/bench_cross_lang.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

errors=0
expect() {
    _name="$1"
    _expected_rc="$2"
    _expected_substr="$3"
    if [ "$rc" -ne "$_expected_rc" ]; then
        echo "[FAIL] $_name: exit $rc, expected $_expected_rc"
        printf '%s\n' "$out" | sed 's/^/       /'
        errors=$((errors + 1))
    elif [ -n "$_expected_substr" ] && ! printf '%s\n' "$out" | grep -qF -- "$_expected_substr"; then
        echo "[FAIL] $_name: output lacks '$_expected_substr'"
        printf '%s\n' "$out" | sed 's/^/       /'
        errors=$((errors + 1))
    else
        echo "[PASS] $_name"
    fi
}

# Set up test environment
mkdir -p "$tmp/bench" "$tmp/work" "$tmp/metrics"

cat << 'EOF' > "$tmp/bench/thresholds.cfg"
runtime_ratio_vs_gcc_o2|3.867|15|lower_better
EOF

# Case 1: Normal ratio (~3.70) within tolerance (< 4.447) passes cleanly
cat << 'EOF' > "$tmp/metrics/metrics_pass.tsv"
runtime_ratio_vs_gcc_o2	3.720
EOF
rc=0
out="$(THRESHOLDS_FILE="$tmp/bench/thresholds.cfg" METRICS_FILE="$tmp/metrics/metrics_pass.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "normal ratio within tolerance passes" 0 "[OK]  runtime_ratio_vs_gcc_o2"

# Case 2: Deliberately slowed build (ratio 5.25) fails both runs and rejects with exit 1
# Note on real workload measurement (2026-10-24):
# Deliberately slowing bench/cross_lang/fib/fib.zrl with non-elidable operations produced
# real ratios 5.109 on initial measurement and 5.167 on confirmation (ceiling 4.447),
# confirming that real regressions survive the median of interleaved pairs and fail the gate.
# Create fake binaries where Zoril takes ~1.5s and gcc takes ~10ms (ratio ~150 > 4.447). The slow
# side is deliberately far above the ceiling: with a 0.25s sleep, per-run overhead of ~0.1s (a full
# `make test` runs this beside 16 other workers) compressed the confirmation ratio to 2.914 and the
# gate correctly called it noise, failing this case for the wrong reason (dependency matrix,
# 2026-10-27). At 1.5s the ratio stays over the ceiling for overhead below ~0.43s.
cat << 'EOF' > "$tmp/work/fib_zoril"
#!/bin/sh
sleep 1.5
EOF
chmod +x "$tmp/work/fib_zoril"

cat << 'EOF' > "$tmp/work/fib_gcc2"
#!/bin/sh
sleep 0.01
EOF
chmod +x "$tmp/work/fib_gcc2"

cat << 'EOF' > "$tmp/metrics/metrics_slow.tsv"
runtime_ratio_vs_gcc_o2	5.250
EOF

rc=0
out="$(RUNTIME_RUNS=3 TMP_DIR="$tmp/work" THRESHOLDS_FILE="$tmp/bench/thresholds.cfg" METRICS_FILE="$tmp/metrics/metrics_slow.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "deliberately slowed build fails the gate after confirmation" 1 "confirmation"

# Case 3: Transient noise spike (initial > 4.447, but confirmation measurement passes)
# Create binaries where Zoril takes ~200ms and gcc takes ~75ms (ratio ~2.7 < 4.447). The absolute
# times, not only the ratio, are what keeps this case stable: an additive scheduling overshoot moves
# a 35ms/10ms pair past the ceiling but barely moves this one.
cat << 'EOF' > "$tmp/work/fib_zoril_fast"
#!/bin/sh
sleep 0.2
EOF
chmod +x "$tmp/work/fib_zoril_fast"

cat << 'EOF' > "$tmp/work/fib_gcc2_fast"
#!/bin/sh
sleep 0.075
EOF
chmod +x "$tmp/work/fib_gcc2_fast"

cp "$tmp/work/fib_zoril_fast" "$tmp/work/fib_zoril"
cp "$tmp/work/fib_gcc2_fast" "$tmp/work/fib_gcc2"

# Initial metrics file says 4.600 (a transient noise spike)
cat << 'EOF' > "$tmp/metrics/metrics_spike.tsv"
runtime_ratio_vs_gcc_o2	4.600
EOF

rc=0
out="$(RUNTIME_RUNS=3 TMP_DIR="$tmp/work" THRESHOLDS_FILE="$tmp/bench/thresholds.cfg" METRICS_FILE="$tmp/metrics/metrics_spike.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "transient noise spike re-measured and passes gate" 0 "noise retry"

if [ "$errors" -eq 0 ]; then
    echo "All bench threshold gate tests passed."
    exit 0
else
    exit 1
fi
