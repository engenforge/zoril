#!/bin/sh
# scripts/test_fuzz_jobs.sh -- gate: `--jobs 1` and `--jobs 16` over the same seeds must report the same
# totals. The parallel mode sums one machine-readable totals line per worker, so if the seed split, the
# per-worker output directory or the single mismatch stream ever drifts, this is where it shows.
#
# The comparison is only meaningful if the run did something: equal zeros would pass, so the count is
# checked against the range as well. That is the shape of failure this gate exists for - a counting bug
# that silently reported less than the corpus.
#
# It also covers the driver's failure paths, because the happy path passes with all of them broken: an
# empty `--count` still testing the whole range, a worker that cannot run failing the run, arguments before
# `--jobs` reaching the workers, and the one rule that cannot be read off the twins - an accepted
# mismatch-stream program is a finding on its own, since one of that stream's fifteen twins is valid Rust.
# That last one needs a compiler that accepts everything (`scripts/fuzz/stub_zoril.sh`), and it is checked
# by the line it prints, not only by the exit status: a run that fails for any other reason exits non-zero
# too, which is how the check passed for a while without reaching the rule at all.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
if ! "$HERE/check_deps.sh" --required-only fuzz >/dev/null 2>&1; then
    echo "[SKIP] fuzz-jobs: fuzz dependencies (lua, timeout) not satisfied"
    exit 0
fi
QUIET=${1:-}
SEEDS="1-16"; COUNT=2; MODE=mix
# A test run's findings must never land in the repository: the stub compiler below accepts every mismatch
# shape on purpose, and every acceptance is a "finding" by design.
OUT=$(mktemp -d "${TMPDIR:-/tmp}/zfuzz.jobsgate.XXXXXX")

FUZZ_FINDINGS="$OUT/findings"; export FUZZ_FINDINGS; mkdir -p "$FUZZ_FINDINGS"
mkdir -p "$FUZZ_FINDINGS"
trap 'rm -rf "$OUT"' EXIT

"$HERE/fuzz_jobs.sh" --jobs 1  --seeds "$SEEDS" --count "$COUNT" --mode "$MODE" --out "$OUT/j1"  > "$OUT/j1.log"  2>&1
"$HERE/fuzz_jobs.sh" --jobs 16 --seeds "$SEEDS" --count "$COUNT" --mode "$MODE" --out "$OUT/j16" > "$OUT/j16.log" 2>&1


# ── the failure paths, because the happy path passes with all of them broken ──────────────────────────
fails=0
check() { # name, expected, rc
    if [ "$2" = "nonzero" ] && [ "$3" -eq 0 ]; then echo "FAIL: $1 exited 0"; fails=$((fails + 1))
    elif [ "$2" = "zero" ] && [ "$3" -ne 0 ]; then echo "FAIL: $1 exited $3"; fails=$((fails + 1))
    else [ -n "$QUIET" ] || echo "[PASS] $1"; fi
}

# An empty --count used to mean "test nothing, report clean".
"$HERE/fuzz_jobs.sh" --jobs 4 --seeds 1-4 --mode grammar --out "$OUT/nocount" > "$OUT/nocount.log" 2>&1
check "no --count still tests the whole range" zero $?
n=$(grep -h '^fuzz-totals: ' "$OUT/nocount.log" | tr ' ' '\n' | sed -n 's/^progs=//p' | head -1)
if [ "${n:-0}" -lt 12 ]; then echo "FAIL: no --count tested ${n:-0} programs, expected the default over 4 seeds"; fails=$((fails + 1)); fi

# A worker that cannot run at all used to drop its share silently.
ZORIL_BIN=/nonexistent/zoril "$HERE/fuzz_jobs.sh" --jobs 4 --seeds 1-4 --count 2 --mode grammar --out "$OUT/broken" > "$OUT/broken.log" 2>&1
check "a worker that cannot run at all fails the run" nonzero $?

# Arguments before --jobs must reach the workers.
if "$HERE/fuzz_safe.sh" --seeds 1-4 --count 2 --mode grammar --jobs 4 --out "$OUT/order" > "$OUT/order.log" 2>&1; then
    [ -n "$QUIET" ] || echo "[PASS] arguments before --jobs are forwarded"
else
    echo "FAIL: --seeds 1-4 --count 2 --jobs 4 was rejected"; fails=$((fails + 1))
fi

# An accepted mismatch-stream program is a finding whatever its twin does. The stub compiler accepts every
# shape, so all of them are accepted - and one of the fifteen twins is valid Rust, which is why the twin
# cannot be what decides. `scripts/fuzz/stub_zoril.sh` is that compiler; it emits the ZIL the run compiles,
# so what the run sees is an acceptance. It used to be an inline `cat` with no `-o`, which left the driver's
# `t.zil` missing: the shapes came out as `toolchain zilc` faults, and this check passed on the exit status
# alone while the rule it names was never reached. Hence the second check.
printf 'fn main() -> i32 { return 0; }\n' > "$OUT/trivial.zrl"
"$HERE/../build/zoril" -I "$HERE/../stdlib" --emit-zil -o "$OUT/trivial.zil" "$OUT/trivial.zrl" 2>/dev/null
FUZZ_STUB_ZIL="$OUT/trivial.zil" ZORIL_BIN="$HERE/fuzz/stub_zoril.sh" \
    "$HERE/fuzz_jobs.sh" --jobs 1 --seeds 1-1 --count 1 --mode mismatch --out "$OUT/mismatch" > "$OUT/mismatch.log" 2>&1
check "an accepted mismatch shape is a finding" nonzero $?
accepted_lines=$(grep -c 'accepted by zoril - a mismatch shape is supposed to be refused' "$OUT"/mismatch/w*.log)
maccepted=$(grep -h '^fuzz-totals: ' "$OUT"/mismatch/w*.log | head -1 | tr ' ' '\n' | sed -n 's/^maccepted=//p')
if [ "${maccepted:-0}" -gt 0 ] && [ "${accepted_lines:-0}" -eq "${maccepted:-0}" ]; then
    [ -n "$QUIET" ] || echo "[PASS] all ${maccepted} accepted shape(s) were findings on their own, not on their twin"
else
    echo "FAIL: ${accepted_lines:-0} accepted-mismatch line(s) for ${maccepted:-0} accepted shape(s) (a fault also exits non-zero)"
    grep -E '^\[' "$OUT/mismatch.log" | head -5 | sed 's/^/       /'
    fails=$((fails + 1))
fi

# A worker that *finds* something is not a worker that failed to run. The driver exits 1 when it reports a
# candidate, a fault or an expired entry, and that is how a finding leaves a worker; if the wrapper reads
# every non-zero worker as unusable it prints "N worker(s) exited non-zero" and no `fuzz-totals:` line at
# all, so the run's numbers are lost exactly when a finding makes them worth having. One worker reports
# here (the mismatch stream, which rides one seed, through the stub compiler) and the other does not
# (`--count 0`: it has nothing to test and exits 0), which is the pair of cases this has to tell apart.
FUZZ_STUB_ZIL="$OUT/trivial.zil" ZORIL_BIN="$HERE/fuzz/stub_zoril.sh" \
    "$HERE/fuzz_jobs.sh" --jobs 2 --seeds 1-2 --count 0 --mode mix --out "$OUT/found" > "$OUT/found.log" 2>&1
found_rc=$?
check "a worker whose exit is a finding still fails the run" nonzero $found_rc
found_problems=""
grep -q '^fuzz-totals: ' "$OUT/found.log" || found_problems="no fuzz-totals line (the run's numbers are gone)"
grep -q 'fuzz: mismatch stream: ' "$OUT/found.log" || found_problems="${found_problems:+$found_problems; }no summary line"
grep -q 'reported a finding' "$OUT/found.log" || found_problems="${found_problems:+$found_problems; }it did not say a worker reported a finding"
grep -q 'did not run' "$OUT/found.log" && found_problems="${found_problems:+$found_problems; }it called the finding a worker that did not run"
# The reporting worker's numbers have to be *in* the summed line, not merely printed somewhere: compare
# the wrapper's totals with what its worker logs hold, for a counter only the reporting worker contributes.
found_totals=$(grep '^fuzz-totals: ' "$OUT/found.log" | head -1)
for field in ran maccepted; do
    workers=$(grep -h '^fuzz-totals: ' "$OUT"/found/w*.log | tr ' ' '\n' |
        awk -F= -v k="$field" '$1 == k { s += $2 } END { print s + 0 }')
    wrapper=$(printf '%s\n' "$found_totals" | tr ' ' '\n' | sed -n "s/^$field=//p")
    if [ "${workers:-0}" -eq 0 ] || [ "${wrapper:-0}" -ne "${workers:-0}" ]; then
        found_problems="${found_problems:+$found_problems; }$field: the wrapper says ${wrapper:-nothing}, its workers total ${workers:-0} (the reporting worker's share is missing)"
    fi
done
if [ -n "$found_problems" ]; then
    echo "FAIL: a reported finding lost the run's totals: $found_problems"
    sed 's/^/       /' "$OUT/found.log" | head -8
    fails=$((fails + 1))
else
    [ -n "$QUIET" ] || echo "[PASS] a reported finding keeps its totals and the summary ($found_totals)"
fi

# ── a known hole is attributed only when switching it off removes the fault ───────────────────────────
# The driver's known-hole branch used to report *any* fault in a marked program as the hole. These two
# planted programs separate the cases: both carry the same marker and the same deliberate canary under
# the runtime switch, and the second also has an unrelated out-of-range read. With the switch on both
# exit 92; with it off the first exits 0 and the second traps (134). The first must be the known hole,
# the second a finding - a fault that survives the switch being off is not attributable to the hole.
cat << 'LUA' > "$OUT/planted_gen.lua"
if arg[1] == "--features" then
    print("array-value")
    print("immutable-index-write")
    print("index-mut-borrow")
    os.exit(0)
end
local out = "."
for i = 1, #arg do
    if arg[i] == "--out" then out = arg[i + 1] end
end
os.execute("mkdir -p '" .. out .. "'")
local function write(path, text)
    local f = assert(io.open(path, "w"))
    f:write(text)
    f:close()
end
local good = [=[// fuzz program: planted known hole
// fuzz: calibration index_mut_borrow
// fuzz: no-rustc-diff
fn main(argc: i32, _argv: **u8) -> i32 {
    let hole_switch: bool = argc > 1;
    if hole_switch {
        let x: i32 = 1;
        if x != 2 { return 92; }
    }
    return 0;
}
]=]
local blind = [=[// fuzz program: planted unrelated fault
// fuzz: calibration index_mut_borrow
// fuzz: no-rustc-diff
fn main(argc: i32, _argv: **u8) -> i32 {
    let hole_switch: bool = argc > 1;
    if hole_switch {
        let x: i32 = 1;
        if x != 2 { return 92; }
    }
    let b: [i32; 2] = [1, 2];
    let i: i32 = 5;
    let bad: i32 = b[i];
    return bad;
}
]=]
write(out .. "/p1_0_gen.zrl", good)
write(out .. "/p1_0_gen.rs", "fn main() {}\n")
write(out .. "/p1_1_gen.zrl", blind)
write(out .. "/p1_1_gen.rs", "fn main() {}\n")
print("array-value,immutable-index-write,index-mut-borrow " .. out .. "/p1_0_gen 0 0")
print("array-value,immutable-index-write,index-mut-borrow " .. out .. "/p1_1_gen 0 0")
LUA
FUZZ_GEN="$OUT/planted_gen.lua" "$HERE/fuzz_safe.sh" --seeds 1-1 --count 1 --mode grammar \
    --no-checked --no-coverage --out "$OUT/attrib" > "$OUT/attrib.log" 2>&1
check "a switch-off fault in a marked program is a finding" nonzero $?
if grep -qE '\[FAULT\].*p1_1_gen\.zrl hole switch off: trap' "$OUT/attrib.log"; then
    [ -n "$QUIET" ] || echo "[PASS] the unrelated fault is reported as a finding, not as the hole"
else
    echo "FAIL: the switch-off fault in p1_1_gen.zrl was not reported as a finding"
    sed 's/^/       /' "$OUT/attrib.log" | head -8
    fails=$((fails + 1))
fi
if grep -qE '\[KNOWN-HOLE\] index_mut_borrow: still open .*p1_0_gen\.zrl' "$OUT/attrib.log"; then
    [ -n "$QUIET" ] || echo "[PASS] the same marker with a clean switch-off run is still the known hole"
else
    echo "FAIL: the clean marked program was not reported as the known hole"
    sed 's/^/       /' "$OUT/attrib.log" | head -8
    fails=$((fails + 1))
fi
if grep -qE 'p1_1_gen\.zrl.*still open' "$OUT/attrib.log"; then
    echo "FAIL: the program with the unrelated fault was still attributed to the known hole"
    fails=$((fails + 1))
fi
attrib_totals=$(grep -h '^fuzz-totals: ' "$OUT/attrib.log" | head -1)
attrib_blind=$(printf '%s\n' "$attrib_totals" | tr ' ' '\n' | sed -n 's/^knownblind=//p')
attrib_faults=$(printf '%s\n' "$attrib_totals" | tr ' ' '\n' | sed -n 's/^faults=//p')
if [ "${attrib_blind:-0}" -eq 1 ] && [ "${attrib_faults:-0}" -eq 1 ]; then
    [ -n "$QUIET" ] || echo "[PASS] the totals name one switch-off fault (knownblind=1, faults=1)"
else
    echo "FAIL: expected knownblind=1 and faults=1, got knownblind=${attrib_blind:-?} faults=${attrib_faults:-?}"
    fails=$((fails + 1))
fi

# An undeclared feature tag emitted by the generator fails the run.
cat << 'EOF' > "$OUT/fake_gen.lua"
local here = os.getenv("REAL_GEN")
if arg[1] == "--features" then
    local p = io.popen("lua " .. here .. " --features")
    for line in p:lines() do
        if line ~= "capability-mismatch-raw-deref-through-a-container" then print(line) end
    end
    p:close()
    os.exit(0)
end
dofile(here)
EOF
REAL_GEN="$HERE/fuzz/gen.lua" FUZZ_GEN="$OUT/fake_gen.lua" \
    "$HERE/fuzz_jobs.sh" --jobs 1 --seeds 1-1 --count 2 --mode mix --out "$OUT/undec" > "$OUT/undec.log" 2>&1
check "an undeclared feature tag fails the run" nonzero $?
if grep -qF "undeclared feature tag(s): capability-mismatch-raw-deref-through-a-container" "$OUT/undec.log"; then
    [ -n "$QUIET" ] || echo "[PASS] undeclared tag was named in the failure"
else
    echo "FAIL: undeclared tag was not named in log"
    sed 's/^/       /' "$OUT/undec.log"
    fails=$((fails + 1))
fi

if [ "$fails" -gt 0 ]; then echo "fuzz-jobs: $fails failure(s)"; exit 1; fi

# ── the runtime limit is CPU time, not wall time ──────────────────────────────────────────────
# A wall-clock-only limit made two calibration programs time out under preflight load and come out
# as blind faults, so --jobs 1 and --jobs 16 disagreed (faults=2, knownskipped 14 vs 15). The
# planted pair below pins both halves of the fix: a plain program that spins is a finding named as
# a timeout, and a calibration program that spins is "not reached", never a blind fault.
cat << 'LUA' > "$OUT/spin_gen.lua"
if arg[1] == "--features" then
    print("spin")
    os.exit(0)
end
local out = "."
for i = 1, #arg do
    if arg[i] == "--out" then out = arg[i + 1] end
end
os.execute("mkdir -p '" .. out .. "'")
local function write(name, text)
    local f = assert(io.open(out .. "/" .. name, "w"))
    f:write(text)
    f:close()
end
local body = [=[
fn main(_argc: i32, _argv: **u8) -> i32 {
    let mut i: u64 = 0;
    while i >= 0 { i = i + 1; }
    return 0;
}
]=]
write("spin_0_gen.zrl", "// fuzz: no-rustc-diff\n" .. body)
write("spin_1_gen.zrl", "// fuzz: calibration index_mut_borrow\n// fuzz: no-rustc-diff\n" .. body)
print("spin " .. out .. "/spin_0_gen 0 0")
print("spin " .. out .. "/spin_1_gen 0 0")
LUA
FUZZ_GEN="$OUT/spin_gen.lua" "$HERE/fuzz_safe.sh" --seeds 1-1 --count 2 --mode grammar \
    --no-checked --no-coverage --timeout 1 --out "$OUT/spin" > "$OUT/spin.log" 2>&1
check "a program that spins past the CPU limit is a finding" nonzero $?
if grep -qF '[FAULT]' "$OUT/spin.log" && grep -qF 'timed out after 1s of CPU' "$OUT/spin.log"; then
    [ -n "$QUIET" ] || echo "[PASS] a timeout is named as a timeout, not as signal 124"
else
    echo "FAIL: the spinning program was not reported as a timeout"
    sed 's/^/       /' "$OUT/spin.log" | head -8
    fails=$((fails + 1))
fi
spin_totals=$(grep '^fuzz-totals: ' "$OUT/spin.log" | head -1)
spin_skipped=$(printf '%s\n' "$spin_totals" | tr ' ' '\n' | sed -n 's/^knownskipped=//p')
spin_blind=$(printf '%s\n' "$spin_totals" | tr ' ' '\n' | sed -n 's/^knownblind=//p')
if grep -qF 'not reached (timed out)' "$OUT/spin.log" && [ "${spin_skipped:-0}" -eq 1 ] && [ "${spin_blind:-0}" -eq 0 ]; then
    [ -n "$QUIET" ] || echo "[PASS] a timed-out calibration program is not reached, not a blind fault"
else
    echo "FAIL: a timed-out calibration program was not classified as not reached (knownskipped=${spin_skipped:-?}, knownblind=${spin_blind:-?})"
    sed 's/^/       /' "$OUT/spin.log" | head -8
    fails=$((fails + 1))
fi

if [ "$fails" -gt 0 ]; then echo "fuzz-jobs: $fails failure(s)"; exit 1; fi

a=$(grep '^fuzz-totals: ' "$OUT/j1.log" | head -1)
b=$(grep '^fuzz-totals: ' "$OUT/j16.log" | head -1)
[ -n "$a" ] && [ -n "$b" ] || { echo "FAIL: no totals line (see $OUT/j1.log, $OUT/j16.log)"; exit 1; }
if [ "$a" != "$b" ]; then
    echo "FAIL: --jobs 1 and --jobs 16 disagree over seeds $SEEDS"
    echo "   1: $a"
    echo "  16: $b"
    exit 1
fi
progs=$(printf '%s\n' "$a" | tr ' ' '\n' | sed -n 's/^progs=//p')
[ "${progs:-0}" -ge 32 ] || { echo "FAIL: ${progs:-0} programs in the main stream, expected the whole range"; exit 1; }
[ "$QUIET" = "--quiet" ] || echo "[PASS] --jobs 1 and --jobs 16 agree over seeds $SEEDS: $a"
exit 0
