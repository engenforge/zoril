#!/bin/sh
# scripts/test_bench_contention.sh — tests for host contention detection in scripts/bench_cross_lang.sh.
set -eu

cd "$(dirname "$0")/.."
BENCH="$(pwd)/scripts/bench_cross_lang.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

errors=0
expect() { # expect <name> <expected exit status> <expected output substring or ''>
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

mkdir -p "$tmp/proc"

# Case 1: High load with decaying idle CPU proceeds (fake /proc)
echo "10.00 8.00 6.00 1/500 12345" > "$tmp/proc/loadavg"
cat << 'EOF' > "$tmp/proc/stat"
cpu  100 0 100 9800 0 0 0 0 0 0
cpu  200 0 200 19600 0 0 0 0 0 0
EOF
rc=0
out="$(PROC_DIR="$tmp/proc" HOST_CORES=16 "$BENCH" --check-contention 2>&1)" || rc=$?
expect "fake /proc high load with decaying idle CPU proceeds" 0 "1-min load still decaying, CPU idle"

# Case 2: High load with busy CPU fails (fake /proc)
cat << 'EOF' > "$tmp/proc/stat"
cpu  100 0 100 100 0 0 0 0 0 0
cpu  800 0 800 400 0 0 0 0 0 0
EOF
rc=0
out="$(PROC_DIR="$tmp/proc" HOST_CORES=16 "$BENCH" --check-contention 2>&1)" || rc=$?
expect "fake /proc high load with busy CPU fails" 1 "Host contention detected"

# Case 3: High load with initial idle CPU but busy re-sample fails (fake /proc)
cat << 'EOF' > "$tmp/proc/stat"
cpu  100 0 100 9800 0 0 0 0 0 0
cpu  200 0 200 19600 0 0 0 0 0 0
cpu  300 0 300 20100 0 0 0 0 0 0
cpu  800 0 800 20600 0 0 0 0 0 0
EOF
rc=0
out="$(PROC_DIR="$tmp/proc" HOST_CORES=16 "$BENCH" --check-contention 2>&1)" || rc=$?
expect "fake /proc high load with busy re-sample fails" 1 "Host contention detected"

# Case 4: Normal load with idle CPU proceeds cleanly (fake /proc)
echo "0.50 0.50 0.50 1/500 12345" > "$tmp/proc/loadavg"
cat << 'EOF' > "$tmp/proc/stat"
cpu  100 0 100 9800 0 0 0 0 0 0
cpu  200 0 200 19600 0 0 0 0 0 0
EOF
rc=0
out="$(PROC_DIR="$tmp/proc" HOST_CORES=16 "$BENCH" --check-contention 2>&1)" || rc=$?
expect "fake /proc normal load with idle CPU proceeds" 0 ""
if printf '%s\n' "$out" | grep -qF "still decaying"; then
    echo "[FAIL] fake /proc normal load should not report decaying load"
    errors=$((errors + 1))
fi

# Case 5: Normal load with busy CPU fails (fake /proc)
cat << 'EOF' > "$tmp/proc/stat"
cpu  100 0 100 100 0 0 0 0 0 0
cpu  800 0 800 400 0 0 0 0 0 0
EOF
rc=0
out="$(PROC_DIR="$tmp/proc" HOST_CORES=16 "$BENCH" --check-contention 2>&1)" || rc=$?
expect "fake /proc normal load with busy CPU fails" 1 "Host contention detected"

# Case 6: Injectable sampler override: high load with idle CPU proceeds
echo "10.00 8.00 6.00 1/500 12345" > "$tmp/proc/loadavg"
rc=0
out="$(PROC_LOADAVG="$tmp/proc/loadavg" SAMPLE_CPU_IDLE_OVERRIDE=95 HOST_CORES=16 "$BENCH" --check-contention 2>&1)" || rc=$?
expect "sampler override high load with idle CPU proceeds" 0 "1-min load still decaying, CPU idle"

# Case 7: Injectable sampler override: high load with busy CPU fails
rc=0
out="$(PROC_LOADAVG="$tmp/proc/loadavg" SAMPLE_CPU_IDLE_OVERRIDE=25 HOST_CORES=16 "$BENCH" --check-contention 2>&1)" || rc=$?
expect "sampler override high load with busy CPU fails" 1 "Host contention detected"

# Case 8: Injectable sampler command: sustained idle proceeds
cat << 'EOF' > "$tmp/sampler_idle.sh"
#!/bin/sh
if [ "$1" = "1.0" ]; then echo 95; else echo 92; fi
EOF
chmod +x "$tmp/sampler_idle.sh"
rc=0
out="$(PROC_LOADAVG="$tmp/proc/loadavg" SAMPLE_CPU_IDLE_CMD="$tmp/sampler_idle.sh" HOST_CORES=16 "$BENCH" --check-contention 2>&1)" || rc=$?
expect "sampler command sustained idle proceeds" 0 "1-min load still decaying, CPU idle"

# Case 9: Injectable sampler command: decaying re-sample fails when < 90%
cat << 'EOF' > "$tmp/sampler_busy_resample.sh"
#!/bin/sh
if [ "$1" = "1.0" ]; then echo 95; else echo 75; fi
EOF
chmod +x "$tmp/sampler_busy_resample.sh"
rc=0
out="$(PROC_LOADAVG="$tmp/proc/loadavg" SAMPLE_CPU_IDLE_CMD="$tmp/sampler_busy_resample.sh" HOST_CORES=16 "$BENCH" --check-contention 2>&1)" || rc=$?
expect "sampler command busy re-sample fails" 1 "Host contention detected"

# Case 10-12: The finish-state rule (sample_finish_host_state). A rise in the 1-minute load
# average counts as contention only when the CPU is also busy at the end: this run's own parallel
# builds raise the load, which used to mark every publishing run "contended" (a real one: start
# 1.33, end 2.84, idle 99%, threshold 4.80) and force it with --force.
echo "2.84 1.50 1.20 1/500 12345" > "$tmp/proc/loadavg"
rc=0
out="$(PROC_LOADAVG="$tmp/proc/loadavg" HOST_LOAD1M_START=1.33 SAMPLE_CPU_IDLE_OVERRIDE=99 HOST_CORES=16 CHECK_FINISH_STATE=1 "$BENCH" 2>&1)" || rc=$?
expect "finish: load rose but CPU idle is recorded ok" 0 "RUN_STATUS=ok"

rc=0
out="$(PROC_LOADAVG="$tmp/proc/loadavg" HOST_LOAD1M_START=1.33 SAMPLE_CPU_IDLE_OVERRIDE=25 HOST_CORES=16 CHECK_FINISH_STATE=1 "$BENCH" 2>&1)" || rc=$?
expect "finish: load rose and CPU busy is contended" 0 "RUN_STATUS=contended"

echo "0.50 0.50 0.50 1/500 12345" > "$tmp/proc/loadavg"
rc=0
out="$(PROC_LOADAVG="$tmp/proc/loadavg" HOST_LOAD1M_START=0.40 SAMPLE_CPU_IDLE_OVERRIDE=25 HOST_CORES=16 CHECK_FINISH_STATE=1 "$BENCH" 2>&1)" || rc=$?
expect "finish: no rise stays ok even with a busy CPU" 0 "RUN_STATUS=ok"

[ "$errors" -eq 0 ]
