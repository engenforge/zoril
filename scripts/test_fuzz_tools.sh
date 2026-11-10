#!/bin/sh
# scripts/test_fuzz_tools.sh -- the fuzz-session plumbing: scripts/fuzz/*.sh and the live progress of
# scripts/fuzz_jobs.sh, on tiny seed ranges (seconds, not 15 hours) and on hand-made run directories.
#
#   - a short run, with the intervals shortened by environment variables: a banner, a [STATUS] line and
#     the final summary with the compiled-and-ran verdict in its log;
#   - a finding in one worker reaches the main log before the run ends;
#   - fuzz-status on a finished, a running, a killed and a stalled-worker run directory, a run with a
#     finding (exit 1) and no run at all (exit 2);
#   - fuzz-summary equals the sum of the workers' totals;
#   - fuzz-stop stops a run it can signal, marks a dead one killed, and leaves alone a live one whose
#     wrapper it cannot see (another PID namespace); fuzz-status ages heartbeats against the clock;
#   - fuzz-plan on a recorded pilot gives the expected range;
#   - the expected-value oracle: exit 93 is a fault, and the manifest says what was checked;
#   - swarm testing: a pure function of the seed, recorded in the manifest, and switchable;
#   - every target the guide names exists.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)

# The same fingerprint implementation the harness and the gate use, so a fixture run's line is the
# line a real run would print.
. "$HERE/lib/portability.sh"
. "$HERE/lib/tree_files.sh"
. "$HERE/lib/fuzz_fresh.sh"
if ! "$HERE/check_deps.sh" --required-only fuzz >/dev/null 2>&1; then
    echo "[SKIP] fuzz-tools: fuzz dependencies (lua, timeout) not satisfied"
    exit 0
fi
QUIET=${1:-}
# rustc is optional: a [CANDIDATE] in the grammar stream is a program zoril accepts and rustc
# refuses, so without the oracle there is nothing to produce one from.
have_rustc=0
command -v rustc >/dev/null 2>&1 && have_rustc=1
TMP=$(mktemp -d "${TMPDIR:-/tmp}/zfuzz.tools.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
FUZZ_FINDINGS="$TMP/findings"; export FUZZ_FINDINGS; mkdir -p "$FUZZ_FINDINGS"
fails=0
ok() { [ -n "$QUIET" ] || echo "[PASS] $1"; }
bad() { echo "FAIL: $1"; fails=$((fails + 1)); [ -n "${2:-}" ] && sed 's/^/       /' "$2" | head -12; }

# ── 1. a short run: banner, [STATUS], summary and the RAN verdict ─────────────────────────────────────
FUZZ_STATUS_SECS=1 FUZZ_MONITOR_TICK=1 FUZZ_HEARTBEAT_SECS=1 "$HERE/fuzz_jobs.sh" --jobs 2 --seeds 1-16 --count 2 \
    --mode grammar --ran 3 --out "$TMP/r1" > "$TMP/r1.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "a short run exits 0" || bad "a short run exited $rc" "$TMP/r1.out"
grep -q '^fuzz: run directory ' "$TMP/r1.out" && grep -q '^fuzz: seeds 1-16 x 2, mode grammar, 2 worker(s), target 3 compiled and ran' "$TMP/r1.out" \
    && ok "the main log opens with a banner" || bad "no banner in the main log" "$TMP/r1.out"
grep -q '^\[STATUS\] ' "$TMP/r1.out" && ok "the main log has a [STATUS] line" || bad "no [STATUS] line in the main log" "$TMP/r1.out"
grep -q '^fuzz: target 3 compiled and ran: MET' "$TMP/r1.out" && grep -q '^fuzz: wall time ' "$TMP/r1.out" \
    && ok "the final summary has the wall time and the RAN verdict" || bad "the final summary lacks the wall time or the RAN verdict" "$TMP/r1.out"
[ "$(sed -n 's/^state=//p' "$TMP/r1/run.status")" = finished ] && ok "run.status says finished" || bad "run.status is not finished" "$TMP/r1/run.status"
[ -s "$TMP/r1/w0.status" ] && [ -s "$TMP/r1/w1.status" ] && ok "every worker left a heartbeat file" || bad "a worker left no heartbeat file"

# --ran reaches the wrapper even with one worker (a release run refuses itself when the target is missed).
"$HERE/fuzz_safe.sh" --seeds 1-3 --count 1 --mode grammar --ran 1 --out "$TMP/single" > "$TMP/single.out" 2>&1
grep -q '^fuzz: target 1 compiled and ran: ' "$TMP/single.out" && ok "--ran without --jobs is honoured, not ignored" || bad "--ran without --jobs was ignored" "$TMP/single.out"

# ── 2. fuzz-summary equals the sum of the workers' totals ─────────────────────────────────────────────
want=$(grep -h '^fuzz-totals: ' "$TMP"/r1/w*.log | tr ' ' '\n' | sed -n 's/^progs=//p' | awk '{ s += $1 } END { print s }')
wantran=$(grep -h '^fuzz-totals: ' "$TMP"/r1/w*.log | tr ' ' '\n' | sed -n 's/^ran=//p' | awk '{ s += $1 } END { print s }')
"$HERE/fuzz/summary.sh" --run "$TMP/r1" --format record > "$TMP/r1.record" 2>&1
got=$(sed -n 's/^- \*\*Programs generated:\*\* \*\*\([0-9,]*\)\*\*.*/\1/p' "$TMP/r1.record" | tr -d ',')
gotran=$(sed -n 's/^headline: \([0-9]*\) programs compiled and ran/\1/p' "$TMP/r1.record")
if [ "$got" = "$want" ] && [ "$gotran" = "$wantran" ] && [ "${want:-0}" -gt 0 ]; then ok "fuzz-summary totals equal the per-worker sums ($want generated, $wantran compiled and ran)"
else bad "fuzz-summary says $got/$gotran, the workers say $want/$wantran" "$TMP/r1.record"; fi
    grep -q '^fingerprint: src=' "$TMP/r1.record" && ok "the record format carries the run's fingerprint" || bad "no fingerprint in the record format" "$TMP/r1.record"

# ── 3. a finding reaches the main log before the run ends ────────────────────────────────────────────
printf 'fn main() -> i32 { return 0; }\n' > "$TMP/trivial.zrl"
"$REPO/build/zoril" -I "$REPO/stdlib" --emit-zil -o "$TMP/trivial.zil" "$TMP/trivial.zrl" 2>/dev/null
FUZZ_STUB_ZIL="$TMP/trivial.zil" ZORIL_BIN="$HERE/fuzz/stub_zoril.sh" FUZZ_STATUS_SECS=1 FUZZ_MONITOR_TICK=1 FUZZ_HEARTBEAT_SECS=1 \
    "$HERE/fuzz_jobs.sh" --jobs 2 --seeds 1-12 --count 2 --mode grammar --out "$TMP/r3" > "$TMP/r3.out" 2>&1
if [ "$have_rustc" -eq 0 ]; then
    echo "[SKIP] fuzz-tools: a [CANDIDATE] in the main log is read off the rustc oracle, which is not available here"
else
nfind=$(grep -c '^w[0-9]*: \[CANDIDATE\]' "$TMP/r3.out")
first=$(grep -n '^w[0-9]*: \[CANDIDATE\]' "$TMP/r3.out" | head -1 | cut -d: -f1)
wall=$(grep -n '^fuzz: wall time' "$TMP/r3.out" | head -1 | cut -d: -f1)
if [ "${nfind:-0}" -gt 0 ] && [ -n "$wall" ] && [ "$first" -lt "$wall" ]; then ok "a worker's finding is copied into the main log, prefixed with the worker, before the summary"
else bad "no [CANDIDATE] line was copied into the main log ahead of the summary (found ${nfind:-0})" "$TMP/r3.out"; fi
fi
"$HERE/fuzz/status.sh" --run "$TMP/r3" > "$TMP/r3.status" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q 'findings so far:' "$TMP/r3.status" && ok "fuzz-status exits 1 on a run with findings" || bad "fuzz-status exited $rc on a run with findings" "$TMP/r3.status"

# ── 4. fuzz-status on hand-made run directories ───────────────────────────────────────────────────────
now=$(date +%s)
mkrun() { # dir state hb_age_w0 hb_age_w1 [worker_state]
    d=$1; mkdir -p "$d"
    printf 'state=%s\nstart=%s\npid=999999\njobs=2\nfirst=1\nlastseed=100\ncount=8\nhb=10\nmode=mix\nran_target=0\nrelease=0\n' "$2" "$((now - 600))" > "$d/run.status"
    [ "$2" != running ] && echo "end=$((now - 10))" >> "$d/run.status"
    printf 'pid=1 from=1 seed=40 last=50 progs=300 ran=120 faults=0 candidates=0 genbug=0 knownopen=0 t=%s\n' "$((now - $3))" > "$d/w0.status"
    printf 'pid=2 from=51 seed=90 last=100 progs=300 ran=120 faults=0 candidates=0 genbug=0 knownopen=0 t=%s\n' "$((now - $4))" > "$d/w1.status"
    if [ -n "${5:-}" ]; then echo " state=$5" >> "$d/w0.status"; echo " state=$5" >> "$d/w1.status"; fi
    : > "$d/w0.log"; : > "$d/w1.log"
}
mkrun "$TMP/fin" finished 20 20 finished
mkrun "$TMP/run" running 3 4
mkrun "$TMP/kil" killed 30 30 killed
mkrun "$TMP/stall" running 2 500
for pair in "fin:finished:finished" "run:running:running" "kil:killed:killed" "stall:running:stalled"; do
    n=${pair%%:*}; rest=${pair#*:}; st=${rest%%:*}; wst=${rest#*:}
    "$HERE/fuzz/status.sh" --run "$TMP/$n" > "$TMP/$n.status" 2>&1; rc=$?
    if [ "$rc" -eq 0 ] && grep -q "^run .*: $st\$" "$TMP/$n.status" && grep -q " $wst\$" "$TMP/$n.status"; then ok "fuzz-status reads a $n run directory (run $st, a worker $wst, exit 0)"
    else bad "fuzz-status on the $n directory: exit $rc, wanted run $st and a worker $wst" "$TMP/$n.status"; fi
done
grep -q 'of 100 seeds (' "$TMP/stall.status" && ok "the status line counts seeds of the range, not programs" || bad "the status line does not count seeds" "$TMP/stall.status"
grep -q 'stalled' "$TMP/stall.status" && grep -q '(stalled: w1)' "$TMP/stall.status" && ok "a stalled worker is named in the status line" || bad "the stalled worker w1 is not named" "$TMP/stall.status"
"$HERE/fuzz/status.sh" --run "$TMP/does-not-exist" > "$TMP/none.status" 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "fuzz-status exits 2 for no such run" || bad "fuzz-status exited $rc for no such run"
echo '[FAULT] s7/p1.zrl signal 11 (tags: x)' >> "$TMP/fin/w1.log"
"$HERE/fuzz/status.sh" --run "$TMP/fin" > "$TMP/fin2.status" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q 'w1: \[FAULT\]' "$TMP/fin2.status" && ok "fuzz-status lists a finding and exits 1" || bad "fuzz-status exit $rc with a [FAULT] in a worker log" "$TMP/fin2.status"

# ── 5. fuzz-stop: what it may mark killed ────────────────────────────────────────────────────────────
# A dead run (wrapper gone, heartbeats stale) is marked killed.
mkrun "$TMP/stop" running 500 500
FUZZ_STOP_WAIT=1 "$HERE/fuzz/stop.sh" "$TMP/stop" > "$TMP/stop.out" 2>&1
[ "$(sed -n 's/^state=//p' "$TMP/stop/run.status")" = killed ] && grep -q 'state=killed' "$TMP/stop/w0.status" && ok "fuzz-stop marks a dead run and its workers killed" || bad "fuzz-stop left a dead run as it was" "$TMP/stop.out"
# A live run whose wrapper this shell cannot see (pid 999999) is left running, with the reason.
mkrun "$TMP/stopns" running 3 3
FUZZ_STOP_WAIT=1 "$HERE/fuzz/stop.sh" "$TMP/stopns" > "$TMP/stopns.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && [ "$(sed -n 's/^state=//p' "$TMP/stopns/run.status")" = running ] && grep -q 'another PID namespace' "$TMP/stopns.out"; then
    ok "fuzz-stop leaves a live run it cannot signal as it is and says where to stop it"
else bad "fuzz-stop on a live run in another namespace: exit $rc" "$TMP/stopns.out"; fi
# A run marked killed by such a stop, whose wrapper this shell can see, is still stopped.
mkrun "$TMP/stopre" killed 3 3
sleep 300 & spid=$!
sed "s/^pid=999999\$/pid=$spid/" "$TMP/stopre/run.status" > "$TMP/stopre/run.new" && mv "$TMP/stopre/run.new" "$TMP/stopre/run.status"
FUZZ_STOP_WAIT=3 "$HERE/fuzz/stop.sh" "$TMP/stopre" > "$TMP/stopre.out" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && ! kill -0 "$spid" 2>/dev/null && grep -q 'stopped' "$TMP/stopre.out"; then
    ok "fuzz-stop signals a wrapper it can see even when the run is already marked killed"
else kill "$spid" 2>/dev/null; bad "fuzz-stop did not stop a visible wrapper of a run marked killed: exit $rc" "$TMP/stopre.out"; fi
# fuzz-status on a stopped run ages the heartbeats against the clock, not the run's end.
# (The fixture ended 10 s ago and its heartbeats are 30 s old: measured against the end they would read 20 s.)
mkrun "$TMP/agek" killed 30 30
"$HERE/fuzz/status.sh" --run "$TMP/agek" > "$TMP/agek.status" 2>&1
grep -Eq ' (3[0-9]|[4-9][0-9])s ago ' "$TMP/agek.status" && ok "fuzz-status ages a stopped run's heartbeats against the clock" || bad "fuzz-status heartbeat ages of a stopped run" "$TMP/agek.status"
"$HERE/fuzz/summary.sh" --run "$TMP/stop" > "$TMP/stop.sum" 2>&1 && grep -q 'partial' "$TMP/stop.sum" && ok "fuzz-summary of a stopped run is the partial figures" || bad "fuzz-summary of a stopped run" "$TMP/stop.sum"

# ── 6. fuzz-plan on a recorded pilot ──────────────────────────────────────────────────────────────────
mkdir -p "$TMP/pilot"
printf 'state=finished\nstart=1000\nend=1100\npid=1\njobs=4\nfirst=1\nlastseed=100\ncount=8\nhb=10\nmode=mix\nran_target=0\nrelease=1\n' > "$TMP/pilot/run.status"
printf 'pid=1 from=1 seed=100 last=100 progs=800 ran=250 faults=0 candidates=0 genbug=0 knownopen=0 t=1100\n state=finished\n' > "$TMP/pilot/w0.status"
printf 'fuzz-totals: progs=800 ran=250 faults=0\n' > "$TMP/pilot/w0.log"
"$HERE/fuzz/plan.sh" --ran 1000 --run "$TMP/pilot" > "$TMP/plan.out" 2>&1
if grep -q 'make fuzz-release-start SEEDS=1-1000 RAN=1000' "$TMP/plan.out"; then ok "fuzz-plan sizes the range from the pilot's ratio (2.5 per seed: 1-1000 for 1000 plus 5%)"
else bad "fuzz-plan gave the wrong range" "$TMP/plan.out"; fi

# ── 8b. the expected-value oracle: exit 93 is a fault, and the manifest says what was checked ─────────
cat > "$TMP/fake_gen.lua" <<'LUA'
local out, seed
for i = 1, #arg do
    if arg[i] == "--out" then out = arg[i + 1] elseif arg[i] == "--seed" then seed = arg[i + 1] end
end
os.execute("mkdir -p " .. out)
local function w(p, t) local f = io.open(p, "w"); f:write(t); f:close() end
w(out .. "/p" .. seed .. "_0_gen.zrl", "fn main() -> i32 { return 93; }\n")
w(out .. "/p" .. seed .. "_0_gen.rs", "fn main() {}\n")
print("dereference " .. out .. "/p" .. seed .. "_0_gen 1 1 checked")
w(out .. "/p" .. seed .. "_1_gen.zrl", "fn main() -> i32 { return 0; }\n")
w(out .. "/p" .. seed .. "_1_gen.rs", "fn main() {}\n")
print("dereference " .. out .. "/p" .. seed .. "_1_gen 1 1 unchecked:a_helper")
LUA
FUZZ_GEN="$TMP/fake_gen.lua" "$HERE/fuzz_safe.sh" --seeds 1-1 --count 2 --mode grammar --no-coverage --no-checked --out "$TMP/f93" > "$TMP/f93.out" 2>&1; rc=$?
if [ "$rc" -eq 1 ] && grep -q '^\[FAULT\] .*value-fault 93' "$TMP/f93.out" && grep -q 'vchecked=1 vunchecked=1' "$TMP/f93.out"; then
    ok "exit 93 is a [FAULT] (value-fault), and the totals count one checked and one unchecked program"
else
    bad "the expected-value oracle: exit $rc, wanted a value-fault 93 and vchecked=1 vunchecked=1" "$TMP/f93.out"
fi
# A program that must trap: the expected code is a fault when the program exits 0 or with the other code, and
# the matching trap is the expected outcome (counted as a trap, not a fault).
cat > "$TMP/fake_gen2.lua" <<'LUA'
local out, seed
for i = 1, #arg do
    if arg[i] == "--out" then out = arg[i + 1] elseif arg[i] == "--seed" then seed = arg[i + 1] end
end
os.execute("mkdir -p " .. out)
local function w(p, t) local f = io.open(p, "w"); f:write(t); f:close() end
local function prog(n, zrl, code)
    w(out .. "/p" .. seed .. "_" .. n .. "_gen.zrl", zrl); w(out .. "/p" .. seed .. "_" .. n .. "_gen.rs", "fn main() {}\n")
    print("dereference " .. out .. "/p" .. seed .. "_" .. n .. "_gen 1 1 checked trap=" .. code)
end
prog(0, "fn main(argc: i32, _a: **u8) -> i32 { let a: [i32; 4] = [1, 2, 3, 4]; let i: usize = (argc as usize) + 6; return a[i]; }\n", 134)
prog(1, "fn main() -> i32 { return 0; }\n", 134)
prog(2, "fn main() -> i32 { return 7; }\n", 136)
-- Marked "none", yet it traps: an unpredicted trap, counted by its real exit code (134).
prog(3, "fn main(argc: i32, _a: **u8) -> i32 { let a: [i32; 4] = [1, 2, 3, 4]; let i: usize = (argc as usize) + 6; return a[i]; }\n", "none")
LUA
FUZZ_GEN="$TMP/fake_gen2.lua" "$HERE/fuzz_safe.sh" --seeds 1-1 --count 4 --mode grammar --no-coverage --no-checked --out "$TMP/ftrap" > "$TMP/ftrap.out" 2>&1
nf=$(grep -c '^\[FAULT\] .*trap-fault expected exit' "$TMP/ftrap.out")
if [ "$nf" -eq 2 ] && grep -q 'trap-fault expected exit 134, got 0' "$TMP/ftrap.out" && grep -q 'trap-fault expected exit 136, got 7' "$TMP/ftrap.out" && grep -q 'traps=2 ' "$TMP/ftrap.out" && grep -q ' t134=2 t136=0' "$TMP/ftrap.out"; then
    ok "a program that must trap: the right code is a trap, exit 0 and the wrong code are trap-faults, and an unpredicted trap is counted by its exit code so the split sums to the total"
else
    bad "the expected-trap check found $nf trap-fault(s), wanted exactly the two wrong ones, traps=2 and t134=2 (the predicted trap plus the unpredicted one)" "$TMP/ftrap.out"
fi

lua "$HERE/fuzz/gen.lua" --seed 3 --count 12 --mode grammar --out "$TMP/gen3" > "$TMP/gen3.manifest" 2>&1
if grep -q ' checked trap=' "$TMP/gen3.manifest" && grep -ql 'if chk != .* { return 93; }' "$TMP/gen3"/*_gen.zrl; then
    ok "the generator emits a checksum and says so in the manifest"
else
    bad "the generator emitted no checked program over 12" "$TMP/gen3.manifest"
fi
if grep -l 'chk' "$TMP/gen3"/*_gen.rs >/dev/null 2>&1; then bad "the Rust twin carries the checksum (it is type-checked only and stays as it was)"; fi

# ── 8c. swarm testing: a pure function of the seed, recorded in the manifest, and switchable ─────────
lua "$HERE/fuzz/gen.lua" --seed 11 --count 6 --mode grammar --out "$TMP/swa" > "$TMP/swa.manifest" 2>&1
lua "$HERE/fuzz/gen.lua" --seed 11 --count 6 --mode grammar --out "$TMP/swb" > "$TMP/swb.manifest" 2>&1
lua "$HERE/fuzz/gen.lua" --seed 11 --count 6 --mode grammar --swarm 0 --out "$TMP/swc" > "$TMP/swc.manifest" 2>&1
sed "s#$TMP/swa#X#" "$TMP/swa.manifest" > "$TMP/swa.n"; sed "s#$TMP/swb#X#" "$TMP/swb.manifest" > "$TMP/swb.n"
if cmp -s "$TMP/swa.n" "$TMP/swb.n" && cmp -s "$(ls $TMP/swa/*_11_0_gen.zrl)" "$(ls $TMP/swb/*_11_0_gen.zrl)"; then ok "the same seed gives the same swarm and the same program"; else bad "swarm testing is not a function of the seed" "$TMP/swa.n"; fi
if grep -q ' swarm=off:' "$TMP/swa.manifest" && grep -q ' swarm=all$' "$TMP/swc.manifest"; then ok "the manifest records what the swarm switched off (and swarm=all with --swarm 0)"; else bad "the swarm field is missing from the manifest" "$TMP/swa.manifest"; fi

# ── 9. every target the guide names exists ────────────────────────────────────────────────────────────
for t in fuzz-session fuzz-start fuzz-status fuzz-stop fuzz-summary fuzz-preflight fuzz-pilot fuzz-plan fuzz-release-start fuzz-record-update fuzz-short fuzz-calibrate; do
    ( cd "$REPO" && make -n "$t" SEEDS=1-2 RAN=1 >/dev/null 2>&1 ) && continue
    bad "make -n $t fails: the target does not exist"
done
ok "every fuzz target exists (make -n)"

if [ "$fails" -ne 0 ]; then echo "FAIL: fuzz-tools: $fails check(s) failed"; exit 1; fi
echo "[PASS] fuzz-tools: banner, [STATUS], findings in the main log, status/stop/summary/plan/oracle/swarm on fixtures"
