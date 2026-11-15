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
printf 'clean_throughput_loc_s|15|higher_better\nincremental_rebuild_ms|15|lower_better\nruntime_ratio_vs_gcc_o2|15|lower_better\n' > "$tmp/tol_legacy.cfg"

# Case 1: Normal ratio (~3.720) within tolerance (< 4.447) passes cleanly and appends run/pass
write_header "$tmp/bench/gate_c1.tsv"
append_row "$tmp/bench/gate_c1.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.867" "10.0"
write_metrics "$tmp/metrics/metrics_pass.tsv" "10000" "100" "3.720" "10.0"
rc=0
out="$(TOLERANCES_FILE="$tmp/tol_legacy.cfg" BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_c1.tsv" METRICS_FILE="$tmp/metrics/metrics_pass.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
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
out="$(TOLERANCES_FILE="$tmp/tol_legacy.cfg" RUNTIME_RUNS=3 TMP_DIR="$tmp/work" BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_c2.tsv" METRICS_FILE="$tmp/metrics/metrics_slow.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
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
out="$(TOLERANCES_FILE="$tmp/tol_legacy.cfg" RUNTIME_RUNS=3 TMP_DIR="$tmp/work" BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_c3.tsv" METRICS_FILE="$tmp/metrics/metrics_spike.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
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

# R6: four concurrent --force --check-thresholds-only runs against one scratch records worktree
r6="$tmp/r6"
setup_scratch_repo "$r6" with_git
git -C "$r6" worktree add -q --orphan -b records "$r6/bench/records"
git -C "$r6/bench/records" config user.email "test@example.com"
git -C "$r6/bench/records" config user.name "Test"
printf 'init\n' > "$r6/bench/records/README.md"
git -C "$r6/bench/records" add README.md
git -C "$r6/bench/records" commit -q -m "records init"
_r6_pids=""
for _r6_i in 1 2 3 4; do
    BENCH_HOST_ID=aaaaaaaaaaaa "$r6/scripts/bench_cross_lang.sh" --force --check-thresholds-only > "$tmp/r6_out_$_r6_i" 2>&1 &
    _r6_pids="$_r6_pids $!"
done
_r6_fail=0
for _r6_p in $_r6_pids; do
    _r6_rc=0
    wait "$_r6_p" || _r6_rc=$?
    [ "$_r6_rc" -eq 0 ] || _r6_fail=1
done
_r6_rows=$(awk -F'\t' 'NR > 1 && NF == 18 { c++ } END { print c + 0 }' "$r6/bench/records/gate_history.tsv" 2>/dev/null || echo 0)
_r6_st=$(git -C "$r6/bench/records" status --porcelain)
if [ "$_r6_fail" -eq 0 ] && [ "$_r6_rows" -eq 4 ] && [ -z "$_r6_st" ]; then
    echo "[PASS] R6: four concurrent record commits all exit 0 with 4 rows and clean status"
else
    echo "[FAIL] R6: concurrent record commits failed (fail=$_r6_fail rows=$_r6_rows status='$_r6_st')"
    errors=$((errors + 1))
fi

# R7: a lock that stays still fails with "appended ... but not committed" after retries
r7="$tmp/r7"
setup_scratch_repo "$r7" with_git
git -C "$r7" worktree add -q --orphan -b records "$r7/bench/records"
git -C "$r7/bench/records" config user.email "test@example.com"
git -C "$r7/bench/records" config user.name "Test"
printf 'init\n' > "$r7/bench/records/README.md"
git -C "$r7/bench/records" add README.md
git -C "$r7/bench/records" commit -q -m "records init"
_r7_gitdir=$(git -C "$r7/bench/records" rev-parse --git-dir)
touch "$_r7_gitdir/index.lock"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa "$r7/scripts/bench_cross_lang.sh" --force --check-thresholds-only 2>&1)" || rc=$?
rm -f "$_r7_gitdir/index.lock"
expect "R7: persistent lock fails with appended but not committed" 1 "but not committed"

# F1-F3: scripts/record_figures.sh in scratch repositories
cat > "$tmp/stub_figures.sh" << 'EOF'
#!/bin/sh
case "${1:-}" in
    --print)
        printf 'stdlib modules\t30\nstdlib lines\t6734\nstdlib `unsafe { }` blocks\t187\nstdlib modules with such a block\t23\nstdlib `unsafe fn` declarations\t65\nof those, public\t60\ncompiler modules\t50\ncompiler lines\t47930\ncompiler `unsafe { }` blocks\t852\n'
        ;;
    --density)
        printf 'src density\t**4.66%%**\nstdlib density\t**10.96%%**\nline counts\t1,943 of 41,660 lines in `src/`, 531 of 4,845 in `stdlib/`\n'
        ;;
    --probes)
        printf 'probes\t519\ncompile_reject\t377\naccept\t77\nruntime_trap\t8\nruntime_fault\t11\nknown_gap\t46\n'
        ;;
esac
EOF
chmod +x "$tmp/stub_figures.sh"

REC_FIG="$(pwd)/scripts/record_figures.sh"

# F1: clean commit appends header + 1 row with matching field count and commits it
f1="$tmp/f1"
setup_scratch_repo "$f1" with_git
cp "$REC_FIG" "$f1/scripts/record_figures.sh"
git -C "$f1" add scripts/record_figures.sh
git -C "$f1" commit -q -m "add record_figures"
git -C "$f1" worktree add -q --orphan -b records "$f1/bench/records"
git -C "$f1/bench/records" config user.email "test@example.com"
git -C "$f1/bench/records" config user.name "Test"
printf 'init\n' > "$f1/bench/records/README.md"
git -C "$f1/bench/records" add README.md
git -C "$f1/bench/records" commit -q -m "records init"
rc=0
out="$(FIGURES_SCRIPT="$tmp/stub_figures.sh" "$f1/scripts/record_figures.sh" 2>&1)" || rc=$?
_f1_hdr=$(awk -F'\t' 'NR == 1 { print NF }' "$f1/bench/records/figures_history.tsv" 2>/dev/null || echo 0)
_f1_row=$(awk -F'\t' 'NR == 2 { print NF }' "$f1/bench/records/figures_history.tsv" 2>/dev/null || echo 0)
_f1_lines=$(wc -l < "$f1/bench/records/figures_history.tsv" 2>/dev/null || echo 0)
if [ "$rc" -eq 0 ] && [ "$_f1_lines" -eq 2 ] && [ "$_f1_hdr" -gt 0 ] && [ "$_f1_hdr" -eq "$_f1_row" ] && \
   [ "$(git -C "$f1/bench/records" rev-list --count HEAD)" -eq 2 ] && \
   git -C "$f1/bench/records" log -1 --pretty=%s | grep -q ': figures$'; then
    echo "[PASS] F1: record_figures appends row with matching field count ($_f1_row) and commits"
else
    echo "[FAIL] F1: record_figures failed (rc=$rc lines=$_f1_lines hdr=$_f1_hdr row=$_f1_row)"
    errors=$((errors + 1))
fi

# F2: second run on same clean commit adds nothing and says "already recorded"
rc=0
out="$(FIGURES_SCRIPT="$tmp/stub_figures.sh" "$f1/scripts/record_figures.sh" 2>&1)" || rc=$?
_f2_lines=$(wc -l < "$f1/bench/records/figures_history.tsv" 2>/dev/null || echo 0)
if [ "$rc" -eq 0 ] && [ "$_f2_lines" -eq 2 ] && \
   [ "$(git -C "$f1/bench/records" rev-list --count HEAD)" -eq 2 ] && \
   printf '%s\n' "$out" | grep -q 'is already recorded'; then
    echo "[PASS] F2: second run on same clean commit adds nothing and says already recorded"
else
    echo "[FAIL] F2: second run on same clean commit failed (rc=$rc lines=$_f2_lines out=$out)"
    errors=$((errors + 1))
fi

# F3: dirty tree adds a row marked -dirty, and so does the next run
printf '# dirty\n' >> "$f1/bench/cross_lang/tolerances.cfg"
rc=0
out="$(FIGURES_SCRIPT="$tmp/stub_figures.sh" "$f1/scripts/record_figures.sh" 2>&1)" || rc=$?
rc2=0
out2="$(FIGURES_SCRIPT="$tmp/stub_figures.sh" "$f1/scripts/record_figures.sh" 2>&1)" || rc2=$?
_f3_lines=$(wc -l < "$f1/bench/records/figures_history.tsv" 2>/dev/null || echo 0)
_f3_c3=$(awk -F'\t' 'NR == 3 { print $2 }' "$f1/bench/records/figures_history.tsv" 2>/dev/null || echo "")
_f3_c4=$(awk -F'\t' 'NR == 4 { print $2 }' "$f1/bench/records/figures_history.tsv" 2>/dev/null || echo "")
case "$rc|$rc2|$_f3_lines|$_f3_c3|$_f3_c4" in
    0\|0\|4\|*-dirty\|*-dirty)
        echo "[PASS] F3: dirty tree appends -dirty row each run ($_f3_c3, $_f3_c4)"
        ;;
    *)
        echo "[FAIL] F3: dirty tree test failed (rc=$rc rc2=$rc2 lines=$_f3_lines c3=$_f3_c3 c4=$_f3_c4)"
        errors=$((errors + 1))
        ;;
esac

# F4: figures row's third field (zoril_version) has no space (second word of --version)
cat > "$tmp/stub_zoril.sh" << 'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
    echo "zoril 0.1.0-alpha-176-g50b1e8f"
fi
EOF
chmod +x "$tmp/stub_zoril.sh"
f4="$tmp/f4"
setup_scratch_repo "$f4" with_git
cp "$REC_FIG" "$f4/scripts/record_figures.sh"
git -C "$f4" add scripts/record_figures.sh
git -C "$f4" commit -q -m "add record_figures"
git -C "$f4" worktree add -q --orphan -b records "$f4/bench/records"
git -C "$f4/bench/records" config user.email "test@example.com"
git -C "$f4/bench/records" config user.name "Test"
printf 'init\n' > "$f4/bench/records/README.md"
git -C "$f4/bench/records" add README.md
git -C "$f4/bench/records" commit -q -m "records init"
rc=0
out="$(ZORIL_BIN="$tmp/stub_zoril.sh" FIGURES_SCRIPT="$tmp/stub_figures.sh" "$f4/scripts/record_figures.sh" 2>&1)" || rc=$?
_f4_ver=$(awk -F'\t' 'NR == 2 { print $3 }' "$f4/bench/records/figures_history.tsv" 2>/dev/null || echo "")
case "$rc|$_f4_ver" in
    0\|*" "*) echo "[FAIL] F4: zoril_version contains a space: '$_f4_ver'"; errors=$((errors + 1)) ;;
    0\|0.1.0-alpha-176-g50b1e8f) echo "[PASS] F4: figures row third field is bare version ($_f4_ver)" ;;
    *) echo "[FAIL] F4: unexpected rc=$rc ver='$_f4_ver'"; errors=$((errors + 1)) ;;
esac

# T1-T7: scripts/perf_gap.sh --record-run and runtime_geomean_vs_gcc_o2 gate
PERF_GAP="$(pwd)/scripts/perf_gap.sh"

setup_pg_scratch() {
    _pg="$1"
    shift
    _pg_workloads="$*"
    setup_scratch_repo "$_pg" with_git
    cp "$PERF_GAP" "$_pg/scripts/perf_gap.sh"
    mkdir -p "$_pg/bench/perf_gap" "$_pg/build" "$_pg/stub_bin"
    for _w in $_pg_workloads; do
        printf 'const SCALE: i32 = 10; // gate: 5\n' > "$_pg/bench/perf_gap/$_w.zrl"
        printf 'int main(void) { return 0; }\n' > "$_pg/bench/perf_gap/$_w.c"
    done
    cat > "$_pg/build/zoril" << 'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then echo "zoril 0.1.0-test"; exit 0; fi
out=""
while [ $# -gt 0 ]; do
    case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] && printf '%s\n' "$1" > "$out"
EOF
    cat > "$_pg/build/zilc" << 'EOF'
#!/bin/sh
printf 'zil\n' > "$2"
EOF
    : > "$_pg/build/runtime.o"
    chmod +x "$_pg/build/zoril" "$_pg/build/zilc"

    cat > "$_pg/stub_bin/qbe" << 'EOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
    case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] && printf 'asm\n' > "$out"
EOF
    cat > "$_pg/stub_bin/as" << 'EOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
    case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] && printf 'obj\n' > "$out"
EOF
    cat > "$_pg/stub_bin/ld" << 'EOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
    case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
printf '#!/bin/sh\nexit "${STUB_ZORIL_EXIT:-0}"\n' > "$out"
chmod +x "$out"
EOF
    cat > "$_pg/stub_bin/cproc" << 'EOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
    case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
printf '#!/bin/sh\nexit "${STUB_CPROC_EXIT:-0}"\n' > "$out"
chmod +x "$out"
EOF
    cat > "$_pg/stub_bin/gcc" << 'EOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
    case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
printf '#!/bin/sh\nexit "${STUB_GCC_EXIT:-0}"\n' > "$out"
chmod +x "$out"
EOF
    cat > "$_pg/stub_bin/valgrind" << 'EOF'
#!/bin/sh
echo "==123== Collected : 9999" >&2
exec "$4"
EOF
    chmod +x "$_pg/stub_bin/qbe" "$_pg/stub_bin/as" "$_pg/stub_bin/ld" "$_pg/stub_bin/cproc" "$_pg/stub_bin/gcc" "$_pg/stub_bin/valgrind"

    git -C "$_pg" add scripts/perf_gap.sh bench/perf_gap
    git -C "$_pg" commit -q -m "add perf_gap"
    git -C "$_pg" worktree add -q --orphan -b records "$_pg/bench/records"
    git -C "$_pg/bench/records" config user.email "test@example.com"
    git -C "$_pg/bench/records" config user.name "Test"
    printf 'init\n' > "$_pg/bench/records/README.md"
    git -C "$_pg/bench/records" add README.md
    git -C "$_pg/bench/records" commit -q -m "records init"
}

make_clean_bin() {
    _mcb_dst="$1"; _mcb_skip="$2"
    mkdir -p "$_mcb_dst"
    _mcb_oldifs="$IFS"; IFS=":"
    for _mcb_d in $PATH; do
        [ -d "$_mcb_d" ] || continue
        for _mcb_f in "$_mcb_d"/*; do
            [ -e "$_mcb_f" ] || continue
            _mcb_b="${_mcb_f##*/}"
            case " $_mcb_skip " in *" $_mcb_b "*) continue ;; esac
            [ -e "$_mcb_dst/$_mcb_b" ] || ln -s "$_mcb_f" "$_mcb_dst/$_mcb_b" 2>/dev/null || true
        done
    done
    IFS="$_mcb_oldifs"
}

# T1: a run appends six rows of 13 fields and one commit
t1="$tmp/t1"
setup_pg_scratch "$t1" array_loop fib particles qsort sha vm
rc=0
out="$(PATH="$t1/stub_bin:$PATH" BENCH_HOST_ID=aaaaaaaaaaaa sh "$t1/scripts/perf_gap.sh" -n 1 --record-run 2>&1)" || rc=$?
_t1_rows=$(awk -F'\t' 'NR > 1 && NF == 13 { c++ } END { print c + 0 }' "$t1/bench/records/runtime_history.tsv" 2>/dev/null || echo 0)
_t1_commits=$(git -C "$t1/bench/records" rev-list --count HEAD)
if [ "$rc" -eq 0 ] && [ "$_t1_rows" -eq 6 ] && [ "$_t1_commits" -eq 2 ] && \
   git -C "$t1/bench/records" log -1 --pretty=%s | grep -q ': runtime$'; then
    echo "[PASS] T1: record-run appends 6 rows of 13 fields and 1 commit"
else
    echo "[FAIL] T1: rc=$rc rows=$_t1_rows commits=$_t1_commits out=$out"
    errors=$((errors + 1))
fi

# T2: printed geometric mean equals the one computed from the rows (ratios 2.000 and 8.000 -> 4.000)
t2="$tmp/t2"
setup_pg_scratch "$t2" p1 p2
cat >> "$t2/scripts/lib/portability.sh" << 'EOF'
_t2_n=0
now_ms() {
    _t2_f="${PERF_GAP_OUT}/t2_cnt"
    _t2_n=0
    [ -f "$_t2_f" ] && read -r _t2_n < "$_t2_f"
    _t2_n=$((_t2_n + 1))
    printf '%s\n' "$_t2_n" > "$_t2_f"
    case "$_t2_n" in
        1) echo 0 ;; 2) echo 200 ;;
        3) echo 0 ;; 4) echo 100 ;;
        5) echo 0 ;; 6) echo 150 ;;
        7) echo 0 ;; 8) echo 800 ;;
        9) echo 0 ;; 10) echo 100 ;;
        11) echo 0 ;; 12) echo 400 ;;
        *) echo 0 ;;
    esac
}
EOF
rc=0
out="$(PERF_GAP_OUT="$t2/out" PATH="$t2/stub_bin:$PATH" BENCH_HOST_ID=aaaaaaaaaaaa sh "$t2/scripts/perf_gap.sh" -n 1 --record-run 2>&1)" || rc=$?
_t2_last=$(printf '%s\n' "$out" | tail -n 1)
_t2_r1=$(awk -F'\t' 'NR == 2 { print $12 }' "$t2/bench/records/runtime_history.tsv" 2>/dev/null || echo "")
_t2_r2=$(awk -F'\t' 'NR == 3 { print $12 }' "$t2/bench/records/runtime_history.tsv" 2>/dev/null || echo "")
if [ "$rc" -eq 0 ] && [ "$_t2_r1" = "2.000" ] && [ "$_t2_r2" = "8.000" ] && \
   [ "$_t2_last" = "$(printf 'runtime_geomean_vs_gcc_o2\t4.000')" ]; then
    echo "[PASS] T2: geometric mean of 2.000 and 8.000 is 4.000"
else
    echo "[FAIL] T2: rc=$rc r1=$_t2_r1 r2=$_t2_r2 last='$_t2_last'"
    errors=$((errors + 1))
fi

# T3: without valgrind on PATH, instructions field is empty and run passes
t3="$tmp/t3"
setup_pg_scratch "$t3" fib
make_clean_bin "$tmp/t3_sysbin" "valgrind"
_t3_sb="$tmp/t3_sb"; mkdir -p "$_t3_sb"
for _b in qbe as ld cproc gcc; do cp "$t3/stub_bin/$_b" "$_t3_sb/$_b"; done
rc=0
out="$(PATH="$_t3_sb:$tmp/t3_sysbin" BENCH_HOST_ID=aaaaaaaaaaaa sh "$t3/scripts/perf_gap.sh" -n 1 --record-run 2>&1)" || rc=$?
_t3_nf=$(awk -F'\t' 'NR == 2 { print NF }' "$t3/bench/records/runtime_history.tsv" 2>/dev/null || echo 0)
_t3_ir=$(awk -F'\t' 'NR == 2 { print $13 }' "$t3/bench/records/runtime_history.tsv" 2>/dev/null || echo "X")
if [ "$rc" -eq 0 ] && [ "$_t3_nf" -eq 13 ] && [ -z "$_t3_ir" ]; then
    echo "[PASS] T3: without valgrind, instructions is empty and run passes"
else
    echo "[FAIL] T3: rc=$rc nf=$_t3_nf ir='$_t3_ir' out=$out"
    errors=$((errors + 1))
fi

# T4: without cproc on PATH, cproc_ms field is empty and run passes
t4="$tmp/t4"
setup_pg_scratch "$t4" fib
make_clean_bin "$tmp/t4_sysbin" "cproc"
_t4_sb="$tmp/t4_sb"; mkdir -p "$_t4_sb"
for _b in qbe as ld gcc valgrind; do cp "$t4/stub_bin/$_b" "$_t4_sb/$_b"; done
rc=0
out="$(PATH="$_t4_sb:$tmp/t4_sysbin" BENCH_HOST_ID=aaaaaaaaaaaa sh "$t4/scripts/perf_gap.sh" -n 1 --record-run 2>&1)" || rc=$?
_t4_nf=$(awk -F'\t' 'NR == 2 { print NF }' "$t4/bench/records/runtime_history.tsv" 2>/dev/null || echo 0)
_t4_cm=$(awk -F'\t' 'NR == 2 { print $10 }' "$t4/bench/records/runtime_history.tsv" 2>/dev/null || echo "X")
if [ "$rc" -eq 0 ] && [ "$_t4_nf" -eq 13 ] && [ -z "$_t4_cm" ]; then
    echo "[PASS] T4: without cproc, cproc_ms is empty and run passes"
else
    echo "[FAIL] T4: rc=$rc nf=$_t4_nf cm='$_t4_cm' out=$out"
    errors=$((errors + 1))
fi

# T5: the gate: baseline 2.000, run 2.400 fails, run 2.200 passes
write_header_18() {
    printf 'date\tcommit\tzoril_version\thost_id\thost_os\thost_arch\tcpu_model\tcores\tram_gb\tgovernor\tstatus\tkind\tverdict\tclean_throughput_loc_s\tincremental_rebuild_ms\truntime_ratio_vs_gcc_o2\tpeak_rss_mb_per_kloc\truntime_geomean_vs_gcc_o2\n' > "$1"
}
write_header_18 "$tmp/bench/gate_t5.tsv"
printf '2026-11-01-00-00-00\tabc1234\t0.1.0\taaaaaaaaaaaa\tLinux 6.1.0\tx86_64\tTestCPU\t4\t16\tperformance\tok\tbaseline\tbaseline\t10000\t100\t3.000\t10.0\t2.000\n' >> "$tmp/bench/gate_t5.tsv"
printf 'clean_throughput_loc_s\t10000\nincremental_rebuild_ms\t100\nruntime_ratio_vs_gcc_o2\t3.000\npeak_rss_mb_per_kloc\t10.0\nruntime_geomean_vs_gcc_o2\t2.400\n' > "$tmp/metrics/metrics_t5_fail.tsv"
printf 'clean_throughput_loc_s\t10000\nincremental_rebuild_ms\t100\nruntime_ratio_vs_gcc_o2\t3.000\npeak_rss_mb_per_kloc\t10.0\nruntime_geomean_vs_gcc_o2\t2.200\n' > "$tmp/metrics/metrics_t5_pass.tsv"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_t5.tsv" METRICS_FILE="$tmp/metrics/metrics_t5_fail.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
rc2=0
out2="$(BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_t5.tsv" METRICS_FILE="$tmp/metrics/metrics_t5_pass.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc2=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF '[FAIL] runtime_geomean_vs_gcc_o2' && \
   [ "$rc2" -eq 0 ] && printf '%s\n' "$out2" | grep -qF '[OK]  runtime_geomean_vs_gcc_o2'; then
    echo "[PASS] T5: runtime_geomean_vs_gcc_o2 gate fails at 2.400 and passes at 2.200 vs 2.000"
else
    echo "[FAIL] T5: rc=$rc rc2=$rc2"
    errors=$((errors + 1))
fi

# T6: a 17-field baseline prints [NEW] and passes
write_header "$tmp/bench/gate_t6.tsv"
append_row "$tmp/bench/gate_t6.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_t6.tsv" METRICS_FILE="$tmp/metrics/metrics_t5_fail.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "T6: 17-field baseline prints [NEW] and passes" 0 "[NEW]  runtime_geomean_vs_gcc_o2"

# T7: three builds that exit differently: no row is written and run fails
t7="$tmp/t7"
setup_pg_scratch "$t7" fib
rc=0
out="$(PATH="$t7/stub_bin:$PATH" STUB_GCC_EXIT=1 BENCH_HOST_ID=aaaaaaaaaaaa sh "$t7/scripts/perf_gap.sh" -n 1 --record-run 2>&1)" || rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$t7/bench/records/runtime_history.tsv" ] && \
   printf '%s\n' "$out" | grep -qF 'exit codes differ'; then
    echo "[PASS] T7: differing exit codes write no row and fail"
else
    echo "[FAIL] T7: rc=$rc exists=$(test -e "$t7/bench/records/runtime_history.tsv" && echo yes || echo no) out=$out"
    errors=$((errors + 1))
fi

if [ "$errors" -eq 0 ]; then
    echo "All bench threshold gate tests passed."
    exit 0
else
    exit 1
fi