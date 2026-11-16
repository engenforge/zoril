#!/bin/sh
# scripts/test_bench_threshold_gate.sh — tests for per-host gate history and tolerances.
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

mkdir -p "$tmp/bench" "$tmp/metrics"

# Case 1: Normal run within tolerance passes cleanly and appends run/pass
write_header "$tmp/bench/gate_c1.tsv"
append_row "$tmp/bench/gate_c1.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.867" "10.0"
write_metrics "$tmp/metrics/metrics_pass.tsv" "10000" "100" "3.720" "10.0"
rc=0
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_c1.tsv" METRICS_FILE="$tmp/metrics/metrics_pass.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "normal run within tolerance passes" 0 "[OK]  clean_throughput_loc_s"
if [ "$(awk -F'\t' 'END {print $12 "|" $13}' "$tmp/bench/gate_c1.tsv")" != "run|pass" ]; then
    echo "[FAIL] normal run case did not append run/pass row"
    errors=$((errors + 1))
fi

# P1: Only another host's baseline (bbbbbbbbbbbb, twice as good) -> new host aaaaaaaaaaaa, exit 0, appends baseline
write_header "$tmp/bench/gate_p1.tsv"
append_row "$tmp/bench/gate_p1.tsv" "2026-11-01-00-00-00" "bbbbbbbbbbbb" "Linux 6.1.0" "performance" "baseline" "baseline" "20000" "50" "1.500" "5.0"
write_metrics "$tmp/metrics/metrics_p1.tsv" "10000" "100" "3.000" "10.0"
rc=0
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p1.tsv" METRICS_FILE="$tmp/metrics/metrics_p1.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
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
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p2.tsv" METRICS_FILE="$tmp/metrics/metrics_p2.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
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
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p3.tsv" METRICS_FILE="$tmp/metrics/metrics_p3.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P3: ignores newer baseline of other host and fails against own" 1 "[FAIL] clean_throughput_loc_s"

# P4: This host's older baseline that passes, then newer baseline of bbbbbbbbbbbb that fails -> exit 0
write_header "$tmp/bench/gate_p4.tsv"
append_row "$tmp/bench/gate_p4.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
append_row "$tmp/bench/gate_p4.tsv" "2026-11-02-00-00-00" "bbbbbbbbbbbb" "Linux 6.1.0" "performance" "baseline" "baseline" "20000" "50" "1.000" "5.0"
write_metrics "$tmp/metrics/metrics_p4.tsv" "10000" "100" "3.000" "10.0"
rc=0
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p4.tsv" METRICS_FILE="$tmp/metrics/metrics_p4.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P4: ignores newer baseline of other host and passes against own" 0 "[OK]  clean_throughput_loc_s"

# P5: Drift check: baseline 10000, run 9000, current 8200 (within 15% of 9000, 18% under 10000) -> exit 1
write_header "$tmp/bench/gate_p5.tsv"
append_row "$tmp/bench/gate_p5.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
append_row "$tmp/bench/gate_p5.tsv" "2026-11-02-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "run" "pass" "9000" "100" "3.000" "10.0"
write_metrics "$tmp/metrics/metrics_p5.tsv" "8200" "100" "3.000" "10.0"
rc=0
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p5.tsv" METRICS_FILE="$tmp/metrics/metrics_p5.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P5: drift against baseline fails even when within 15% of last run" 1 "[FAIL] clean_throughput_loc_s"

# P6: Two baselines of this host: later one is used (passes later, fails earlier) -> exit 0, names later date
write_header "$tmp/bench/gate_p6.tsv"
append_row "$tmp/bench/gate_p6.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "20000" "100" "3.000" "10.0"
append_row "$tmp/bench/gate_p6.tsv" "2026-11-05-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
write_metrics "$tmp/metrics/metrics_p6.tsv" "10000" "100" "3.000" "10.0"
rc=0
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p6.tsv" METRICS_FILE="$tmp/metrics/metrics_p6.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P6: later baseline of same host is used" 0 "2026-11-05-00-00-00"

# P7: Baseline row with another kernel release in host_os and another governor -> used, exit 0, governor note printed
write_header "$tmp/bench/gate_p7.tsv"
append_row "$tmp/bench/gate_p7.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 5.15.0-old" "other_governor_xyz" "baseline" "baseline" "10000" "100" "3.000" "10.0"
write_metrics "$tmp/metrics/metrics_p7.tsv" "10000" "100" "3.000" "10.0"
rc=0
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p7.tsv" METRICS_FILE="$tmp/metrics/metrics_p7.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "P7: baseline with different kernel and governor is used with note" 0 "CPU governor differs from baseline"

# P8: Comment line, empty line, and row with too few fields before this host's baseline -> ignored, exit 0
write_header "$tmp/bench/gate_p8.tsv"
printf '# comment line\n\ntoo\tfew\tfields\n' >> "$tmp/bench/gate_p8.tsv"
append_row "$tmp/bench/gate_p8.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
write_metrics "$tmp/metrics/metrics_p8.tsv" "10000" "100" "3.000" "10.0"
rc=0
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_p8.tsv" METRICS_FILE="$tmp/metrics/metrics_p8.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
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
}

# R3: no git checkout -> [SKIP] bench records and exit 0
r3="$tmp/r3"
setup_scratch_repo "$r3" no_git
rc=0
out="$(BENCH_HOST_ID=aaaaaaaaaaaa "$r3/scripts/bench_cross_lang.sh" --force --check-thresholds-only 2>&1)" || rc=$?
expect "R3: no git checkout skips recording and exits 0" 0 "[SKIP] bench records: no git checkout"

# T2-T9: scripts/perf_gap.sh --record-run and runtime_geomean_vs_gcc_o2 gate (git-free)
PERF_GAP="$(pwd)/scripts/perf_gap.sh"

setup_pg_scratch() {
    _pg="$1"
    shift
    _pg_workloads="$*"
    setup_scratch_repo "$_pg" no_git
    cp "$PERF_GAP" "$_pg/scripts/perf_gap.sh"
    mkdir -p "$_pg/bench/perf_gap" "$_pg/build" "$_pg/stub_bin" "$_pg/out"
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
out="$(ZORIL_COMMIT=abc1234 PERF_GAP_OUT="$t2/out" RUNTIME_HISTORY="$t2/out/runtime_history.tsv" PATH="$t2/stub_bin:$PATH" BENCH_HOST_ID=aaaaaaaaaaaa sh "$t2/scripts/perf_gap.sh" -n 1 --record-run 2>&1)" || rc=$?
_t2_last=$(printf '%s\n' "$out" | tail -n 1)
_t2_r1=$(awk -F'\t' 'NR == 2 { print $12 }' "$t2/out/runtime_history.tsv" 2>/dev/null || echo "")
_t2_r2=$(awk -F'\t' 'NR == 3 { print $12 }' "$t2/out/runtime_history.tsv" 2>/dev/null || echo "")
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
out="$(ZORIL_COMMIT=abc1234 RUNTIME_HISTORY="$t3/out/runtime_history.tsv" PATH="$_t3_sb:$tmp/t3_sysbin" BENCH_HOST_ID=aaaaaaaaaaaa sh "$t3/scripts/perf_gap.sh" -n 1 --record-run 2>&1)" || rc=$?
_t3_nf=$(awk -F'\t' 'NR == 2 { print NF }' "$t3/out/runtime_history.tsv" 2>/dev/null || echo 0)
_t3_ir=$(awk -F'\t' 'NR == 2 { print $13 }' "$t3/out/runtime_history.tsv" 2>/dev/null || echo "X")
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
out="$(ZORIL_COMMIT=abc1234 RUNTIME_HISTORY="$t4/out/runtime_history.tsv" PATH="$_t4_sb:$tmp/t4_sysbin" BENCH_HOST_ID=aaaaaaaaaaaa sh "$t4/scripts/perf_gap.sh" -n 1 --record-run 2>&1)" || rc=$?
_t4_nf=$(awk -F'\t' 'NR == 2 { print NF }' "$t4/out/runtime_history.tsv" 2>/dev/null || echo 0)
_t4_cm=$(awk -F'\t' 'NR == 2 { print $10 }' "$t4/out/runtime_history.tsv" 2>/dev/null || echo "X")
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
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_t5.tsv" METRICS_FILE="$tmp/metrics/metrics_t5_fail.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
rc2=0
out2="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_t5.tsv" METRICS_FILE="$tmp/metrics/metrics_t5_pass.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc2=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF '[FAIL] runtime_geomean_vs_gcc_o2' && \
   [ "$rc2" -eq 0 ] && printf '%s\n' "$out2" | grep -qF '[OK]  runtime_geomean_vs_gcc_o2'; then
    echo "[PASS] T5: runtime_geomean_vs_gcc_o2 gate fails at 2.400 and passes at 2.200 vs 2.000"
else
    echo "[FAIL] T5: rc=$rc rc2=$rc2"
    errors=$((errors + 1))
fi

# T10: vs last line shows runtime_geomean_vs_gcc_o2 2.200 (was 2.000) for an 18-field row
write_header_18 "$tmp/bench/gate_t10.tsv"
printf '2026-11-01-00-00-00\tabc1234\t0.1.0\taaaaaaaaaaaa\tLinux 6.1.0\tx86_64\tTestCPU\t4\t16\tperformance\tok\tbaseline\tbaseline\t10000\t100\t3.000\t10.0\t2.000\n' >> "$tmp/bench/gate_t10.tsv"
rc=0
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_t10.tsv" METRICS_FILE="$tmp/metrics/metrics_t5_pass.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "T10: vs last line prints runtime_geomean_vs_gcc_o2 2.200 (was 2.000)" 0 "runtime_geomean_vs_gcc_o2 2.200 (was 2.000)"

# T11: vs last line shows runtime_geomean_vs_gcc_o2 2.200 (was -) when last row has 17 fields
write_header "$tmp/bench/gate_t11.tsv"
append_row "$tmp/bench/gate_t11.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
rc=0
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_t11.tsv" METRICS_FILE="$tmp/metrics/metrics_t5_pass.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "T11: vs last line prints runtime_geomean_vs_gcc_o2 2.200 (was -) for 17-field row" 0 "runtime_geomean_vs_gcc_o2 2.200 (was -)"

# T12: runtime_ratio_vs_gcc_o2 in a tolerance file is ignored (not gated)
printf 'runtime_ratio_vs_gcc_o2|15|lower_better\n' > "$tmp/tol_t12.cfg"
write_header "$tmp/bench/gate_t12.tsv"
append_row "$tmp/bench/gate_t12.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.867" "10.0"
write_metrics "$tmp/metrics/metrics_t12.tsv" "10000" "100" "5.250" "10.0"
rc=0
out="$(ZORIL_COMMIT=abc1234 TOLERANCES_FILE="$tmp/tol_t12.cfg" BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_t12.tsv" METRICS_FILE="$tmp/metrics/metrics_t12.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -qE '^ *\[[A-Z]+\] +runtime_ratio_vs_gcc_o2'; then
    echo "[PASS] T12: runtime_ratio_vs_gcc_o2 in tolerance file is ignored"
else
    echo "[FAIL] T12: rc=$rc out=$out"
    errors=$((errors + 1))
fi

# H1: records_header writes header when file does not exist and leaves no temp file
mkdir -p "$tmp/h1"
( . "$(pwd)/scripts/lib/records.sh"; records_header "$tmp/h1/x.tsv" "a$(printf '\t')b" )
_h1_exp="$(printf 'a\tb')"
_h1_got="$(cat "$tmp/h1/x.tsv" 2>/dev/null || true)"
_h1_n="$(ls -A "$tmp/h1" | wc -l)"
if [ "$_h1_got" = "$_h1_exp" ] && [ "$_h1_n" -eq 1 ]; then
    echo "[PASS] H1: records_header creates new file with header and no temp files"
else
    echo "[FAIL] H1: got='$_h1_got' files=$_h1_n"
    errors=$((errors + 1))
fi

# H2: records_header leaves an existing non-empty file untouched
mkdir -p "$tmp/h2"
printf 'a\tb\n1\t2\n' > "$tmp/h2/x.tsv"
cp "$tmp/h2/x.tsv" "$tmp/h2_orig.tsv"
( . "$(pwd)/scripts/lib/records.sh"; records_header "$tmp/h2/x.tsv" "c$(printf '\t')d" )
if cmp -s "$tmp/h2/x.tsv" "$tmp/h2_orig.tsv"; then
    echo "[PASS] H2: records_header preserves existing non-empty file"
else
    echo "[FAIL] H2: existing file modified"
    errors=$((errors + 1))
fi

# H3: records_header does not truncate a row appended concurrently before ln
mkdir -p "$tmp/h3" "$tmp/h3_bin"
_real_ln="$(command -v ln)"
cat > "$tmp/h3_bin/ln" << EOF
#!/bin/sh
_last=""
for _a in "\$@"; do _last="\$_a"; done
printf 'a\tb\nlate row\n' > "\$_last"
exec "$_real_ln" "\$@"
EOF
chmod +x "$tmp/h3_bin/ln"
( PATH="$tmp/h3_bin:$PATH"; . "$(pwd)/scripts/lib/records.sh"; records_header "$tmp/h3/x.tsv" "a$(printf '\t')b" )
_h3_lines="$(wc -l < "$tmp/h3/x.tsv" 2>/dev/null || echo 0)"
_h3_line2="$(sed -n '2p' "$tmp/h3/x.tsv" 2>/dev/null || true)"
if [ "$_h3_lines" -eq 2 ] && [ "$_h3_line2" = "late row" ]; then
    echo "[PASS] H3: records_header does not truncate concurrent row"
else
    echo "[FAIL] H3: lines=$_h3_lines line2='$_h3_line2'"
    errors=$((errors + 1))
fi

# T6: a 17-field baseline prints [NEW] and passes
write_header "$tmp/bench/gate_t6.tsv"
append_row "$tmp/bench/gate_t6.tsv" "2026-11-01-00-00-00" "aaaaaaaaaaaa" "Linux 6.1.0" "performance" "baseline" "baseline" "10000" "100" "3.000" "10.0"
rc=0
out="$(ZORIL_COMMIT=abc1234 BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY="$tmp/bench/gate_t6.tsv" METRICS_FILE="$tmp/metrics/metrics_t5_fail.tsv" "$BENCH" --force --check-thresholds-only 2>&1)" || rc=$?
expect "T6: 17-field baseline prints [NEW] and passes" 0 "[NEW]  runtime_geomean_vs_gcc_o2"

# T7: three builds that exit differently: no row is written and run fails
t7="$tmp/t7"
setup_pg_scratch "$t7" fib
rc=0
out="$(ZORIL_COMMIT=abc1234 RUNTIME_HISTORY="$t7/out/runtime_history.tsv" PATH="$t7/stub_bin:$PATH" STUB_GCC_EXIT=1 BENCH_HOST_ID=aaaaaaaaaaaa sh "$t7/scripts/perf_gap.sh" -n 1 --record-run 2>&1)" || rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$t7/out/runtime_history.tsv" ] && \
   printf '%s\n' "$out" | grep -qF 'exit codes differ'; then
    echo "[PASS] T7: differing exit codes write no row and fail"
else
    echo "[FAIL] T7: rc=$rc exists=$(test -e "$t7/out/runtime_history.tsv" && echo yes || echo no) out=$out"
    errors=$((errors + 1))
fi

# T8: valgrind stub that prints nothing to stderr and exits 2 fails --record-run with no row written
t8="$tmp/t8"
setup_pg_scratch "$t8" fib
cat > "$t8/stub_bin/valgrind" << 'EOF'
#!/bin/sh
exit 2
EOF
chmod +x "$t8/stub_bin/valgrind"
rc=0
out="$(cd "$t8" && ZORIL_COMMIT=abc1234 RUNTIME_HISTORY="$t8/out/runtime_history.tsv" PATH="$t8/stub_bin:$PATH" BENCH_HOST_ID=aaaaaaaaaaaa sh "$t8/scripts/perf_gap.sh" -n 1 --record-run fib 2>&1)" || rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$t8/out/runtime_history.tsv" ] && \
   printf '%s\n' "$out" | grep -qF 'callgrind reported no instruction count'; then
    echo "[PASS] T8: failed instruction count stops --record-run with no row"
else
    echo "[FAIL] T8: rc=$rc exists=$(test -e "$t8/out/runtime_history.tsv" && echo yes || echo no) out=$out"
    errors=$((errors + 1))
fi

# T9: same stub with --gate-record leaves gate_baseline.tsv unchanged and exits non-zero
t9="$tmp/t9"
setup_pg_scratch "$t9" fib
cat > "$t9/stub_bin/valgrind" << 'EOF'
#!/bin/sh
exit 2
EOF
chmod +x "$t9/stub_bin/valgrind"
printf 'fib\t1\t0\n' > "$t9/bench/perf_gap/gate_baseline.tsv"
rc=0
out="$(cd "$t9" && ZORIL_COMMIT=abc1234 PATH="$t9/stub_bin:$PATH" sh "$t9/scripts/perf_gap.sh" --gate-record fib 2>&1)" || rc=$?
_t9_base="$(cat "$t9/bench/perf_gap/gate_baseline.tsv")"
_t9_exp="$(printf 'fib\t1\t0')"
if [ "$rc" -ne 0 ] && [ "$_t9_base" = "$_t9_exp" ]; then
    echo "[PASS] T9: failed instruction count stops --gate-record and preserves baseline"
else
    echo "[FAIL] T9: rc=$rc base='$_t9_base' out=$out"
    errors=$((errors + 1))
fi

# G1: the whole scenario runs without calling git
if [ "${_GATE_NO_GIT_CHECK:-0}" -eq 0 ]; then
    _g1_bin="$tmp/g1_bin"
    _g1_log="$tmp/g1_git.log"
    mkdir -p "$_g1_bin"
    cat > "$_g1_bin/git" << EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$_g1_log"
exit 127
EOF
    chmod +x "$_g1_bin/git"
    _g1_rc=0
    _g1_out="$(PATH="$_g1_bin:$PATH" _GATE_NO_GIT_CHECK=1 sh "$0" 2>&1)" || _g1_rc=$?
    if [ "$_g1_rc" -eq 0 ] && [ ! -e "$_g1_log" ]; then
        echo "[PASS] G1: bench-threshold-gate runs without calling git"
    else
        _g1_calls=""
        [ -f "$_g1_log" ] && _g1_calls="$(cat "$_g1_log")"
        echo "[FAIL] G1: rc=$_g1_rc git_log='$_g1_calls'"
        errors=$((errors + 1))
    fi
fi

if [ "$errors" -eq 0 ]; then
    echo "All bench threshold gate tests passed."
    exit 0
else
    exit 1
fi