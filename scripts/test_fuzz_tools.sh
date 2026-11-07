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
#   - fuzz-preflight fails on a dirty tree and passes on a clean one;
#   - fuzz-record-update writes a clean run's numbers into a fixture record and page and then
#     check_fuzz_fresh.sh --strict passes; it refuses a faulty run, a run for other sources, and a run
#     that missed its target, and writes nothing then. A short --release session is recorded beside the release-bar
#     entry, judged by --strict as the current one, and replaced by a later full run.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# Tests never sign commits or run user-configured Git hooks, and must not depend on user Git config.
GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_GLOBAL
GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_SYSTEM
GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_NOSYSTEM
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
for _v in $(env 2>/dev/null | sed -n 's/^\(GIT_CONFIG_[KEY|VALUE].*\)=.*/\1/p'); do
    unset "$_v"
done

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
# git is optional: the fingerprints, fuzz-preflight's tree check and the record-update fixtures all
# need a checkout to compare against, so those checks report [SKIP] rather than failing here.
have_git=0
git_checkout_usable "$REPO" && have_git=1
# rustc is optional too: a [CANDIDATE] in the grammar stream is a program zoril accepts and rustc
# refuses, so without the oracle there is nothing to produce one from.
have_rustc=0
command -v rustc >/dev/null 2>&1 && have_rustc=1
TMP=$(mktemp -d "${TMPDIR:-/tmp}/zfuzz.tools.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
FUZZ_FINDINGS="$TMP/findings"; export FUZZ_FINDINGS; mkdir -p "$FUZZ_FINDINGS"
fails=0
# Fixture repositories are scratch: no hooks, a fixed identity.
gitq() { _r=$1; shift; git -C "$_r" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
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
if [ "$have_git" -eq 1 ]; then
    grep -q '^fingerprint: src=' "$TMP/r1.record" && ok "the record format carries the run's fingerprint" || bad "no fingerprint in the record format" "$TMP/r1.record"
else
    echo "[SKIP] fuzz-tools: the record's fingerprint is five code hashes over the five directories, and git is not available here"
fi

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

# ── 7. fuzz-preflight fails on a dirty tree, passes on a clean one ────────────────────────────────────
if [ "$have_git" -eq 0 ]; then
    echo "[SKIP] fuzz-tools: fuzz-preflight's tree check needs a git checkout to be clean or dirty"
else
mkdir -p "$TMP/pre"
cp -R "$REPO/scripts" "$TMP/pre/scripts"
gitq "$TMP/pre" init -q -b main .; gitq "$TMP/pre" add -A; gitq "$TMP/pre" commit -q -m one
"$TMP/pre/scripts/fuzz/preflight.sh" --check tree > "$TMP/pre-clean.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "fuzz-preflight passes the tree check on a clean tree" || bad "fuzz-preflight failed a clean tree" "$TMP/pre-clean.out"
echo dirt > "$TMP/pre/dirty.txt"
"$TMP/pre/scripts/fuzz/preflight.sh" --check tree > "$TMP/pre-dirty.out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q '^\[FAIL\] the working tree is not clean' "$TMP/pre-dirty.out" && ok "fuzz-preflight fails on a dirty tree" || bad "fuzz-preflight exit $rc on a dirty tree" "$TMP/pre-dirty.out"
fi

# ── 7b. a cited run also requires zbuild to report the clean HEAD ───────────────────────────────────
if [ "$have_git" -eq 1 ]; then
fr="$TMP/fresh"; mkdir -p "$fr/build"
printf 'x\n' > "$fr/f.txt"; gitq "$fr" init -q -b main .; printf 'build/\n' > "$fr/.git/info/exclude"; gitq "$fr" add -A; gitq "$fr" commit -q -m one
head=$(git -C "$fr" rev-parse --short=12 HEAD)
stub() { printf '#!/bin/sh\necho "%s 0.0.1-g%s"\n' "$2" "$3" > "$1"; chmod +x "$1"; }
stub "$fr/build/zoril" zoril "$head"; stub "$fr/build/zilc" zilc "$head"; stub "$fr/build/zbuild" zbuild deadbeef
zb=$(REPO_ROOT=$fr; ZORIL_BIN=; ZILC_BIN=; fuzz_zbuild_bin "$fr" "")
[ "$zb" = "$fr/build/zbuild" ] && ok "the zbuild a cited run checks is build/zbuild when the mode-diff reading is on" || bad "fuzz_zbuild_bin named '$zb'"
[ -z "$(fuzz_zbuild_bin "$fr" 0)" ] && ok "no zbuild is checked under --no-zbuild" || bad "fuzz_zbuild_bin named a zbuild under --no-zbuild"
( REPO_ROOT=$fr; fuzz_require_fresh "$fr/build/zoril" "$fr/build/zilc" "$fr/build/zbuild" ) > "$TMP/fresh-stale.out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && grep -q 'build/zbuild was built from commit deadbeef' "$TMP/fresh-stale.out" && ok "a stale build/zbuild fails the freshness check" || bad "a stale zbuild passed the freshness check (rc $rc)" "$TMP/fresh-stale.out"
stub "$fr/build/zbuild" zbuild "$head"
( REPO_ROOT=$fr; fuzz_require_fresh "$fr/build/zoril" "$fr/build/zilc" "$fr/build/zbuild" ) > "$TMP/fresh-ok.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "a build/zbuild at HEAD passes the freshness check" || bad "a fresh zbuild failed the freshness check" "$TMP/fresh-ok.out"
rm -f "$fr/build/zbuild"
( REPO_ROOT=$fr; fuzz_require_fresh "$fr/build/zoril" "$fr/build/zilc" "$fr/build/zbuild" ) > "$TMP/fresh-missing.out" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "a missing build/zbuild fails the freshness check" || bad "a missing zbuild passed the freshness check" "$TMP/fresh-missing.out"
grep -q -- '--release) RELEASE=1' "$REPO/scripts/fuzz/session.sh" && grep -q 'release' "$REPO/Makefile" && ok "fuzz-session takes --release and RELEASE=1" || bad "fuzz-session has no --release"
fi

# ── 8. fuzz-record-update on a fixture repository ─────────────────────────────────────────────────────
# The fixture is a git repository: the update compares five code hashes and restores a page with
# `git checkout`, so without git there is nothing to update against.
if [ "$have_git" -eq 0 ]; then
    echo "[SKIP] fuzz-tools: fuzz-record-update needs a git repository (fingerprints and page restore)"
else
mkfixture() { # dir
    d=$1; mkdir -p "$d/src" "$d/stdlib" "$d/tools/zilc" "$d/tools/zbuild" "$d/rt" "$d/doc" "$d/bench/fuzz"
    printf 'compiler\n' > "$d/src/main.zrl"; printf 'stdlib\n' > "$d/stdlib/io.zrl"
    printf 'zbuild\n' > "$d/tools/zbuild/main.zrl"; printf 'il\n' > "$d/tools/zilc/main.zrl"; printf 'runtime\n' > "$d/rt/runtime.s"
    printf '# A page\n\nThe release bar was 1,000 programs that compiled and ran.\n' > "$d/doc/PAGE.md"
    cat > "$d/bench/fuzz/README.md" <<'REC'
# Fuzz

## The release-bar run (2026-01-01)

fingerprint: src=0 stdlib=0 tools/zilc=0 tools/zbuild=0 rt=0

headline: 1000 programs compiled and ran

- **Commit:** `aaaaaaaa` (`v`)
- **Seeds:** 1 - 10 (x 2), over 2 workers
- **Programs generated:** **2,000** in the main stream
- **Compiled and ran:** **1,000** (50.0%), 0.0% over the bar
- **Faults:** **0**
- **`rustc` candidates:** **0**
- **Wall time:** **1 h 00 min**

- **Mismatch stream:** prose that stays.
REC
    gitq "$d" init -q -b main .; gitq "$d" add -A; gitq "$d" commit -q -m one
}
mkrunfix() { # dir repo faults ran
    d=$1; mkdir -p "$d"
    fp=$(fuzz_fingerprint "$2")
    printf 'state=finished\nstart=1000\nend=4600\npid=1\njobs=2\nfirst=1\nlastseed=10\ncount=8\nhb=60\nmode=mix\nran_target=1500\nrelease=1\nend=4600\n' > "$d/run.status"
    { echo "fuzz: pipeline: /x/zoril -> /x/zilc -> qbe -> as -> ld"; echo "fuzz: pipeline: zoril 0.0.1-g1234567; zilc 0.0.1-g1234567"
      echo "fuzz: pipeline: fingerprint: $fp"
      echo "fuzz-totals: progs=100 accepted=60 traps=0 rejected=40 candidates=0 faults=$3 inferdiff=0 genbug=0 diffs=2 expired=0 ran=$4 mprogs=0 maccepted=0 mrej=0 mowning=5 mtotal=10 known=4 knownfault=0 knownfixed=2 knownskipped=2 knownblind=0"; } > "$d/w0.log"
    cp "$d/w0.log" "$d/w1.log"
    printf 'pid=1 from=1 seed=5 last=5 progs=100 ran=%s faults=%s candidates=0 genbug=0 knownopen=0 t=4600\n state=finished\n' "$4" "$3" > "$d/w0.status"
    cp "$d/w0.status" "$d/w1.status"
}
mkfixture "$TMP/fx"
mkrunfix "$TMP/fxrun" "$TMP/fx" 0 900
cp "$TMP/fx/bench/fuzz/README.md" "$TMP/fx.before"
"$HERE/fuzz/record_update.sh" --run "$TMP/fxrun" --repo "$TMP/fx" --record "$TMP/fx/bench/fuzz/README.md" > "$TMP/fx.out" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^headline: 1800 programs compiled and ran' "$TMP/fx/bench/fuzz/README.md" \
   && grep -q '1,800' "$TMP/fx/doc/PAGE.md" && grep -q 'prose that stays' "$TMP/fx/bench/fuzz/README.md" \
   && grep -q '^- \*\*Compiled and ran:\*\* \*\*1,800\*\*' "$TMP/fx/bench/fuzz/README.md"; then
    ok "fuzz-record-update writes the numbers into the record and the page, keeps the prose, and check_fuzz_fresh --strict passes"
else
    bad "fuzz-record-update on the fixture (exit $rc)" "$TMP/fx.out"; cat "$TMP/fx/bench/fuzz/README.md" | head -16 | sed 's/^/       /'
fi
refuse_case() { # name, expected-text, run dir, repo
    cp "$TMP/fx.before" "$4/bench/fuzz/README.md"; ( cd "$4" && git checkout -q -- doc/PAGE.md )
    "$HERE/fuzz/record_update.sh" --run "$3" --repo "$4" --record "$4/bench/fuzz/README.md" > "$TMP/refuse.out" 2>&1; rc=$?
    if [ "$rc" -eq 1 ] && grep -q "refusing: .*$2" "$TMP/refuse.out" && cmp -s "$TMP/fx.before" "$4/bench/fuzz/README.md"; then ok "fuzz-record-update refuses $1 and writes nothing"
    else bad "fuzz-record-update on $1: exit $rc" "$TMP/refuse.out"; fi
}
mkrunfix "$TMP/fxfault" "$TMP/fx" 1 900
refuse_case "a run with a fault" "faults" "$TMP/fxfault" "$TMP/fx"
mkrunfix "$TMP/fxshort" "$TMP/fx" 0 700
refuse_case "a run under its compiled-and-ran target" "under its target" "$TMP/fxshort" "$TMP/fx"
mkrunfix "$TMP/fxold" "$TMP/fx" 0 900
printf 'compiler moved\n' >> "$TMP/fx/src/main.zrl"
gitq "$TMP/fx" add -A; gitq "$TMP/fx" commit -q -m "compiler moved"
cp "$TMP/fx/bench/fuzz/README.md" "$TMP/fx.before"
refuse_case "a run for sources that moved" "sources moved" "$TMP/fxold" "$TMP/fx"
# A short --release session on the moved code, beside the release-bar run on the old code (L5's dual record).
mkrunfix "$TMP/fxsess" "$TMP/fx" 0 120
"$HERE/fuzz/record_update.sh" --short-session --no-strict --run "$TMP/fxsess" --repo "$TMP/fx" --record "$TMP/fx/bench/fuzz/README.md" > "$TMP/fxs.out" 2>&1; rc=$?
rec="$TMP/fx/bench/fuzz/README.md"
if [ "$rc" -eq 0 ] && grep -q '^entry: short-session$' "$rec" && grep -q '^headline: 240 programs compiled and ran' "$rec" \
   && grep -q '^headline: 1000 programs compiled and ran' "$rec" && ! sed -n "/^## The short session/,\$p" "$rec" | grep -q "Commit:" \
   && grep -q 'RELEASE=1' "$rec"; then
    ok "fuzz-record-update --short-session adds the session beside the release-bar entry, without a commit hash"
else
    bad "fuzz-record-update --short-session (exit $rc)" "$TMP/fxs.out"; sed 's/^/       /' "$rec"
fi
"$HERE/check_fuzz_fresh.sh" --repo "$TMP/fx" --record "$rec" --strict > "$TMP/fxs1.out" 2>&1; rc1=$?
printf '# A page\n\nThe release bar, 1,000 programs that compiled and ran, was met on the previous code; on this code a short session compiled and ran 240.\n' > "$TMP/fx/doc/PAGE.md"
"$HERE/check_fuzz_fresh.sh" --repo "$TMP/fx" --record "$rec" --strict > "$TMP/fxs2.out" 2>&1; rc2=$?
if [ "$rc1" -ne 0 ] && grep -q 'doc/PAGE.md' "$TMP/fxs1.out" && [ "$rc2" -eq 0 ]; then
    ok "with a short session, --strict passes on its fingerprint, refuses a page quoting only the release-bar run and accepts one quoting both"
else
    bad "the dual record under --strict (exit $rc1, then $rc2)" "$TMP/fxs2.out"
fi
"$HERE/fuzz/record_update.sh" --short-session --no-strict --run "$TMP/fxsess" --repo "$TMP/fx" --record "$rec" > /dev/null 2>&1
[ "$(grep -c '^entry: short-session$' "$rec")" -eq 1 ] && ok "recording a short session again replaces its section" || bad "a second short session added a second section" "$rec"
mkrunfix "$TMP/fxnorel" "$TMP/fx" 0 120
sed 's/^release=1$/release=0/' "$TMP/fxnorel/run.status" > "$TMP/fxnorel/rs" && mv "$TMP/fxnorel/rs" "$TMP/fxnorel/run.status"
cp "$rec" "$TMP/fx.before2"
"$HERE/fuzz/record_update.sh" --short-session --run "$TMP/fxnorel" --repo "$TMP/fx" --record "$rec" > "$TMP/fxnr.out" 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q 'not run with --release' "$TMP/fxnr.out" && cmp -s "$rec" "$TMP/fx.before2" && ok "fuzz-record-update --short-session refuses a session run without --release and writes nothing" || bad "a session without --release was recorded (exit $rc)" "$TMP/fxnr.out"
mkrunfix "$TMP/fxfull" "$TMP/fx" 0 1600
"$HERE/fuzz/record_update.sh" --no-strict --run "$TMP/fxfull" --repo "$TMP/fx" --record "$rec" > "$TMP/fxf.out" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^entry: short-session' "$rec" && grep -q '^headline: 3200 programs compiled and ran' "$rec" && [ "$(grep -c '^headline: ' "$rec")" -eq 1 ]; then
    ok "a full release-bar run recorded afterwards replaces the short session"
else
    bad "the full run after a short session (exit $rc)" "$TMP/fxf.out"; sed 's/^/       /' "$rec"
fi
fi

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

# ── 10. fuzz-record release refusal checks (requires git and timeout) ─────────────────────────────────
if [ "$have_git" -eq 1 ] && command -v timeout >/dev/null 2>&1; then
    if "$HERE/check_fuzz_record.sh" --release > "$TMP/fuzz_rec_rel.log" 2>&1; then
        ok "check_fuzz_record.sh --release passes"
    else
        bad "check_fuzz_record.sh --release failed" "$TMP/fuzz_rec_rel.log"
    fi
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: fuzz-tools: $fails check(s) failed"; exit 1; fi
echo "[PASS] fuzz-tools: banner, [STATUS], findings in the main log, status/stop/summary/plan/preflight/record-update on fixtures"
