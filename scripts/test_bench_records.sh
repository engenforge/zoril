#!/bin/sh
# scripts/test_bench_records.sh — git-dependent tests for bench/records/ commits and record_figures.sh.
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

write_metrics() {
    _file="$1" _tp="$2" _inc="$3" _rat="$4" _rss="$5"
    printf 'clean_throughput_loc_s\t%s\nincremental_rebuild_ms\t%s\nruntime_ratio_vs_gcc_o2\t%s\npeak_rss_mb_per_kloc\t%s\n' \
        "$_tp" "$_inc" "$_rat" "$_rss" > "$_file"
}

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

# F1-F4: scripts/record_figures.sh in scratch repositories
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

# T1: scripts/perf_gap.sh --record-run appends six rows of 13 fields and one commit
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

if [ "$errors" -eq 0 ]; then
    echo "All bench records tests passed."
    exit 0
else
    exit 1
fi
