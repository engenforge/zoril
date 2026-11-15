#!/bin/sh
# scripts/test_bench_threshold_gate.sh — tests for per-host gate history, tolerances, and noise retry.
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

write_header() {
    printf 'date\tcommit\tzoril_version\thost_id\thost_os\thost_arch\tcpu_model\tcores\tram_gb\tgovernor\tstatus\tkind\tverdict\tclean_throughput_loc_s\tincremental_rebuild_ms\truntime_ratio_vs_gcc_o2\tpeak_rss_mb_per_kloc\n' > "$1"
}

append_row() {
    _file="$1" _date="$2" _hid="$3" _os="$4" _gov="$5" _kind="$6" _verdict="$7" _tp="$8" _inc="$9"
    shift 9
    _rat="$1" _rss="$2"
    printf '%s\tabc1234\t0.1.0\t%s\t%s\tx86_64\tTestCPU\t4\t16\t%s\tok\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$_date" "$_hid" "$_os" "$_gov" "$_kind" "$_verdict" "$_tp" "$_inc" "$_rat" "$_rss" >> "$_file"
}

write_metrics() {
    _file="$1" _tp="$2" _inc="$3" _rat="$4" _rss="$5"
    printf 'clean_throughput_loc_s\t%s\nincremental_rebuild_ms\t%s\nruntime_ratio_vs_gcc_o2\t%s\npeak_rss_mb_per_kloc\t%s\n' \
        "$_tp" "$_inc" "$_rat" "$_rss" > "$_file"
}

mkdir -p "$tmp/bench" "$tmp/work" "$tmp/metrics"

# Case 1: Normal ratio (~3.720) within tolerance (< 4.447) passes cleanly and appends run/pass
write_header "$tmp/bench/gate_c1.tsv"
append_row "$tmp/bench/gate_c1.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.867" "10.0"
write_metrics "$tmp/metrics/metrics_pass.tsv" "10000" "100" "3.720" "10.0"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_c1.tsv" METRICS_FILE="$tmp/metrics/metrics_pass.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "normal ratio within tolerance passes" 0 "[OK]  runtime_ratio_vs_gcc_o2"
if [ "$(awk -F'\t' 'END {print $12 "|" $13}' "$tmp/bench/gate_c1.tsv")" != "run|pass" ]; then
    echo "[FAIL] normal ratio case did not append run/pass row"
    errors=$((errors + 1))
fi

# Case 2: Deliberately slowed build (ratio 5.25) fails both runs and rejects with exit 1
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

write_header "$tmp/bench/gate_c2.tsv"
append_row "$tmp/bench/gate_c2.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.867" "10.0"
write_metrics "$tmp/metrics/metrics_slow.tsv" "10000" "100" "5.250" "10.0"
rc=0
out="$(RUNTIME_RUNS=3 TMP_DIR="$tmp/work" BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_c2.tsv" METRICS_FILE="$tmp/metrics/metrics_slow.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "deliberately slowed build fails the gate after confirmation" 1 "confirmation"

# Case 3: Transient noise spike (initial > 4.447, but confirmation measurement passes)
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

write_header "$tmp/bench/gate_c3.tsv"
append_row "$tmp/bench/gate_c3.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.867" "10.0"
write_metrics "$tmp/metrics/metrics_spike.tsv" "10000" "100" "4.600" "10.0"
rc=0
out="$(RUNTIME_RUNS=3 TMP_DIR="$tmp/work" BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_c3.tsv" METRICS_FILE="$tmp/metrics/metrics_spike.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "transient noise spike re-measured and passes gate" 0 "noise retry"

# P1: Only another host's baseline (bbbbbbbbbbbb, twice as good) -> new host aaaaaaaaaaaa, exit 0, appends baseline
write_header "$tmp/bench/gate_p1.tsv"
append_row "$tmp/bench/gate_p1.tsv" "2026-11-01-00-00-00" "bbbbbbbbbbbb" "Linux 6.1.0" "performance" "baseline" "baseline" "20000" "50" "1.500" "5.0"
write_metrics "$tmp/metrics/metrics_p1.tsv" "10000" "100" "3.000" "10.0"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p1.tsv" METRICS_FILE="$tmp/metrics/metrics_p1.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P1: only another host baseline records new host baseline" 0 "new host aaaaaaaaaaaa"
if [ "$(awk -F'\t' 'END {print $4 "|" $12}' "$tmp/bench/gate_p1.tsv")" != "aaaaaaaaaaaa|baseline" ]; then
    echo "[FAIL] P1: last row is not aaaaaaaaaaaa|baseline"
    errors=$((errors + 1))
fi

# P2: This host's baseline and a run 30% worse on clean_throughput_loc_s -> exit 1, last row run|fail
write_header "$tmp/bench/gate_p2.tsv"
append_row "$tmp/bench/gate_p2.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
write_metrics "$tmp/metrics/metrics_p2.tsv" "7000" "100" "3.000" "10.0"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p2.tsv" METRICS_FILE="$tmp/metrics/metrics_p2.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P2: 30% worse throughput fails" 1 "[FAIL] clean_throughput_loc_s"
if [ "$(awk -F'\t' 'END {print $12 "|" $13}' "$tmp/bench/gate_p2.tsv")" != "run|fail" ]; then
    echo "[FAIL] P2: last row is not run|fail"
    errors=$((errors + 1))
fi

# P3: This host's older baseline that fails, then newer baseline of bbbbbbbbbbbb that passes -> exit 1
write_header "$tmp/bench/gate_p3.tsv"
append_row "$tmp/bench/gate_p3.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
append_row "$tmp/bench/gate_p3.tsv" "2026-11-02-00-00-00" "bbbbbbbbbbbb" "Linux 6.1.0" "performance" "baseline" "baseline" "5000" "200" "5.000" "20.0"
write_metrics "$tmp/metrics/metrics_p3.tsv" "7000" "100" "3.000" "10.0"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p3.tsv" METRICS_FILE="$tmp/metrics/metrics_p3.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P3: ignores newer baseline of other host and fails against own" 1 "[FAIL] clean_throughput_loc_s"

# P4: This host's older baseline that passes, then newer baseline of bbbbbbbbbbbb that fails -> exit 0
write_header "$tmp/bench/gate_p4.tsv"
append_row "$tmp/bench/gate_p4.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
append_row "$tmp/bench/gate_p4.tsv" "2026-11-02-00-00-00" "bbbbbbbbbbbb" "Linux 6.1.0" "performance" "baseline" "baseline" "20000" "50" "1.000" "5.0"
write_metrics "$tmp/metrics/metrics_p4.tsv" "10000" "100" "3.000" "10.0"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p4.tsv" METRICS_FILE="$tmp/metrics/metrics_p4.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P4: ignores newer baseline of other host and passes against own" 0 "[OK]  clean_throughput_loc_s"

# P5: Drift check: baseline 10000, run 9000, current 8200 (within 15% of 9000, 18% under 10000) -> exit 1
write_header "$tmp/bench/gate_p5.tsv"
append_row "$tmp/bench/gate_p5.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
append_row "$tmp/bench/gate_p5.tsv" "2026-11-02-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "run" "pass" "9000" "100" "3.000" "10.0"
write_metrics "$tmp/metrics/metrics_p5.tsv" "8200" "100" "3.000" "10.0"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p5.tsv" METRICS_FILE="$tmp/metrics/metrics_p5.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P5: drift against baseline fails even when within 15% of last run" 1 "[FAIL] clean_throughput_loc_s"

# P6: Two baselines of this host: later one is used (passes later, fails earlier) -> exit 0, names later date
write_header "$tmp/bench/gate_p6.tsv"
append_row "$tmp/bench/gate_p6.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "20000" "100" "3.000" "10.0"
append_row "$tmp/bench/gate_p6.tsv" "2026-11-05-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
write_metrics "$tmp/metrics/metrics_p6.tsv" "10000" "100" "3.000" "10.0"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p6.tsv" METRICS_FILE="$tmp/metrics/metrics_p6.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P6: later baseline of same host is used" 0 "2026-11-05-00-00-00"

# P7: Baseline row with another kernel release in host_os and another governor -> used, exit 0, governor note printed
write_header "$tmp/bench/gate_p7.tsv"
append_row "$tmp/bench/gate_p7.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 5.15.0-old" "other_governor_xyz" "baseline" "baseline" "10000" "100" "3.000" "10.0"
write_metrics "$tmp/metrics/metrics_p7.tsv" "10000" "100" "3.000" "10.0"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p7.tsv" METRICS_FILE="$tmp/metrics/metrics_p7.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P7: baseline with different kernel and governor is used with note" 0 "CPU governor differs from baseline"

# P8: Comment line, empty line, and row with too few fields before this host's baseline -> ignored, exit 0
write_header "$tmp/bench/gate_p8.tsv"
printf '# comment line\n\ntoo\tfew\tfields\n' >> "$tmp/bench/gate_p8.tsv"
append_row "$tmp/bench/gate_p8.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
write_metrics "$tmp/metrics/metrics_p8.tsv" "10000" "100" "3.000" "10.0"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p8.tsv" METRICS_FILE="$tmp/metrics/metrics_p8.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P8: comment, empty line, and malformed row ignored" 0 "[OK]  clean_throughput_loc_s"

setup_scratch_repo() {
    _sr="$1"
    mkdir -p "$_sr/scripts/lib" "$_sr/bench/cross_lang" "$_sr/build/bench"
    cp "$BENCH" "$_sr/scripts/bench_cross_lang.sh"
    cp "$(pwd)/scripts/env.sh" "$_sr/scripts/env.sh"
    cp "$(pwd)/scripts/lib/portability.sh" "$_sr/scripts/lib/portability.sh"
    cp "$(pwd)/scripts/lib/records.sh" "$_sr/scripts/lib/records.sh"
    cp "$(pwd)/bench/cross_lang/tolerances.cfg" "$_sr/bench/cross_lang/tolerances.cfg"
    cp "$(pwd)/bench/cross_lang/children_maxrss.c" "$_sr/bench/cross_lang/children_maxrss.c"
    write_metrics "$_sr/build/bench/last_zoril_metrics.tsv" "10000" "100" "3.000" "10.0"
    if [ "${2:-with_git}" = "with_git" ]; then
        git -C "$_sr" init -q
        git -C "$_sr" config user.email "test@example.com"
        git -C "$_sr" config user.name "Test"
        git -C "$_sr" add scripts bench/cross_lang/tolerances.cfg bench/cross_lang/children_maxrss.c
        git -C "$_sr" commit -q -m "init"
    fi
}

# R1: mounted records worktree -> appends one row and commits on records
r1="$tmp/r1"
setup_scratch_repo "$r1" with_git
git -C "$r1" worktree add -q --orphan -b records "$r1/bench/records"
git -C "$r1/bench/records" config user.email "test@example.com"
git -C "$r1/bench/records" config user.name "Test"
printf 'init\n' > "$r1/bench/records/README.md"
git -C "$r1/bench/records" add README.md
git -C "$r1/bench/records" commit -q -m "records init"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa "$r1/scripts/bench_cross_lang.sh" --force --check-thresholds-only 2>&1)" || rc=$?
expect "R1: mounted records worktree commits row" 0 "new host aaaaaaaaaaaa"
if [ "$(git -C "$r1/bench/records" rev-list --count HEAD)" -ne 2 ] || \
   ! git -C "$r1/bench/records" log -1 --pretty=%s | grep -q '^aaaaaaaaaaaa ' || \
   [ -n "$(git -C "$r1/bench/records" status --porcelain)" ]; then
    echo "[FAIL] R1: records branch commit or status check failed"
    errors=$((errors + 1))
fi

# R2: not mounted in a git checkout -> exit 1, [FAIL] bench records, nothing written under bench/
r2="$tmp/r2"
setup_scratch_repo "$r2" with_git
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa "$r2/scripts/bench_cross_lang.sh" --force --check-thresholds-only 2>&1)" || rc=$?
expect "R2: unmounted records branch fails before measuring" 1 "[FAIL] bench records: the records branch is not mounted"
if [ -e "$r2/bench/records" ]; then
    echo "[FAIL] R2: bench/records should not exist"
    errors=$((errors + 1))
fi

# R3: no git checkout -> [SKIP] bench records and exit 0
r3="$tmp/r3"
setup_scratch_repo "$r3" no_git
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa "$r3/scripts/bench_cross_lang.sh" --force --check-thresholds-only 2>&1)" || rc=$?
expect "R3: no git checkout skips recording and exits 0" 0 "[SKIP] bench records: no git checkout"

# R4: commit fails (index.lock planted) -> exit 1 and "appended ... but not committed"
r4="$tmp/r4"
setup_scratch_repo "$r4" with_git
git -C "$r4" worktree add -q --orphan -b records "$r4/bench/records"
git -C "$r4/bench/records" config user.email "test@example.com"
git -C "$r4/bench/records" config user.name "Test"
printf 'init\n' > "$r4/bench/records/README.md"
git -C "$r4/bench/records" add README.md
git -C "$r4/bench/records" commit -q -m "records init"
_r4_gitdir=$(git -C "$r4/bench/records" rev-parse --git-dir)
touch "$_r4_gitdir/index.lock"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa "$r4/scripts/bench_cross_lang.sh" --force --check-thresholds-only 2>&1)" || rc=$?
rm -f "$_r4_gitdir/index.lock"
expect "R4: commit failure reports appended but not committed" 1 "but not committed"

# R5: commit column: untracked file -> no -dirty; modified tracked file -> -dirty
r5="$tmp/r5"
setup_scratch_repo "$r5" with_git
git -C "$r5" worktree add -q --orphan -b records "$r5/bench/records"
git -C "$r5/bench/records" config user.email "test@example.com"
git -C "$r5/bench/records" config user.name "Test"
printf 'init\n' > "$r5/bench/records/README.md"
git -C "$r5/bench/records" add README.md
git -C "$r5/bench/records" commit -q -m "records init"
printf 'untracked\n' > "$r5/untracked_note.txt"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa "$r5/scripts/bench_cross_lang.sh" --force --check-thresholds-only 2>&1)" || rc=$?
_r5_c1=$(awk -F'\t' 'END {print $2}' "$r5/bench/records/gate_history.tsv")
printf '# modified\n' >> "$r5/bench/cross_lang/tolerances.cfg"
out2="$(BENCH_HOST_ID=aaaaaaaaaaaa "$r5/scripts/bench_cross_lang.sh" --force --check-thresholds-only 2>&1)" || rc=$?
_r5_c2=$(awk -F'\t' 'END {print $2}' "$r5/bench/records/gate_history.tsv")
case "$_r5_c1|$_r5_c2" in
    *-dirty\|*) echo "[FAIL] R5: untracked file marked commit dirty: $_r5_c1"; errors=$((errors + 1)) ;;
    *\|*-dirty) echo "[PASS] R5: untracked file clean ($_r5_c1), modified tracked file dirty ($_r5_c2)" ;;
    *) echo "[FAIL] R5: modified tracked file not marked dirty: $_r5_c2"; errors=$((errors + 1)) ;;
esac

if [ "$errors" -eq 0 ]; then
    echo "All bench threshold gate tests passed."
    exit 0
else
    exit 1
fi