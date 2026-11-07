#!/bin/sh
# scripts/check_fuzz_record.sh — `bench/fuzz/findings/` says what it holds, and `--reverify` says it out.
#
# The record is one minimised program pair per candidate the fuzzer raised, and the README beside it is
# where each pair is named. Nothing enforced either half, and both halves were wrong at once: the
# self-tests' stub compiler accepts every mismatch shape on purpose, so a run that could not choose its
# findings directory copied 30 pairs that were never findings into the repository's record, under a
# README that said "None are stored" — and `--reverify` reported "0 recorded finding(s) still open",
# because its loop only looked at the programs zoril still accepts and skipped everything else without a
# word. A record that cannot be told from scratch is not a record.
#
# What this gate checks, in the two shapes it fails in:
#   - the classification, on fixtures in a temporary record, so that "fixed", "still open", "never a
#     disagreement", "half a pair" and "not named in the README" are each seen to come out of `--reverify`
#     with the exit status the release gate needs (open, half and unnamed fail; fixed and never-a-
#     disagreement are reported and do not, because they are a to-do and a decision rather than a hole);
#   - the repository's own record, which is the part `make test` is here to keep honest;
#   - that a run saying nothing writes nothing: the mismatch stream through the stub compiler, with no
#     findings directory named, must leave `bench/fuzz/findings/` byte-for-byte as it was. That is the
#     incident itself, as one item;
#   - that a `--release` run can support the sentence it is cited for: it refuses to start without `rustc`
#     (the differential oracle) before generating a program, and it fails when a calibration row is
#     `still open`, naming the row and pointing at `make fuzz-calibrate`. A third item pins the behaviour
#     that existed: a marked program faulting with its hole switched off is a finding, not the hole.
#
# Usage: check_fuzz_record.sh [--release]   (prints [PASS]/[FAIL]/[SKIP] per item)
set -u

CHECK_RELEASE=0
for arg in "$@"; do
    case "$arg" in
        --release) CHECK_RELEASE=1 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/scripts/lib/portability.sh" 2>/dev/null || true
DRIVER="$REPO_ROOT/scripts/fuzz_safe.sh"
RECORD="$REPO_ROOT/bench/fuzz/findings"
ZORIL=${ZORIL_CC:-$REPO_ROOT/build/zoril}

for f in "$ZORIL" "$REPO_ROOT/build/zilc" "$REPO_ROOT/build/runtime.o"; do
    if [ ! -e "$f" ]; then
        echo "[SKIP] fuzz-record: $f is not built, so the record cannot be re-verified here"
        exit 0
    fi
done

if ! command -v lua >/dev/null 2>&1 || ! lua -e "if not math.tointeger then os.exit(1) end" >/dev/null 2>&1; then
    echo "[SKIP] fuzz-record: lua 5.3 or newer not found (needed by fuzzer generator and driver)"
    exit 0
fi

have_rustc=0
command -v rustc >/dev/null 2>&1 && have_rustc=1

WORK=$(mktemp -d "${TMPDIR:-/tmp}/zfuzz.record.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
FIX="$WORK/fixtures"
fail=0

# case_check SLUG NAME EXPECTED RECORD PATTERN — run `--reverify` over RECORD and require the exit status
# and the one line that says what the check concluded. EXPECTED is zero or nonzero; SLUG names the log.
case_check() {
    slug=$1; name=$2; want=$3; rec=$4; pat=$5
    "$DRIVER" --reverify --findings "$rec" > "$WORK/$slug.log" 2>&1
    rc=$?
    bad=""
    if [ "$want" = zero ] && [ "$rc" -ne 0 ]; then bad="exit $rc, expected 0"; fi
    if [ "$want" = nonzero ] && [ "$rc" -eq 0 ]; then bad="exit 0, expected non-zero"; fi
    if [ -n "$pat" ] && ! grep -qF "$pat" "$WORK/$slug.log"; then
        bad="${bad:+$bad; }no line matching '$pat'"
    fi
    if [ -n "$bad" ]; then
        echo "[FAIL] $name: $bad"
        sed 's/^/       /' "$WORK/$slug.log"
        fail=1
    else
        echo "[PASS] $name"
    fi
}

newrecord() { mkdir -p "$FIX/$1"; echo "$FIX/$1"; }

# ── the fixtures ───────────────────────────────────────────────────────────────────────────────────────
# A program zoril takes (so the run reaches the twin comparison) and one it refuses (so the pair is what a
# fixed finding looks like): the box-borrow shape the first finding was, in the small.
accepting() { printf 'fn main() -> i32 { return 0; }\n' > "$1"; }
refused()   { printf 'fn take(b: Box<i32>) -> i32 { return *b; }\nfn main() -> i32 { let x: i32 = 7; return take(&x); }\n' > "$1"; }

rec=$(newrecord empty)
printf 'The record.\n\nNone are stored.\n' > "$rec/README.md"
case_check empty "an empty record is clean" zero "$rec" "holds no program"

rec=$(newrecord fixed)
refused "$rec/box_borrow.zrl"
printf 'fn take(b: Box<i32>) -> i32 { *b }\nfn main() { let x = 7; take(&x); }\n' > "$rec/box_borrow.rs"
printf 'The record.\n\n- `box_borrow.zrl` - a borrow where an owned `Box` is expected, taken by zoril once.\n' > "$rec/README.md"
case_check fixed "a pair zoril refuses now is reported as fixed" zero "$rec" "box_borrow.zrl is fixed"

rec=$(newrecord unlisted)
refused "$rec/box_borrow.zrl"
printf 'fn main() {}\n' > "$rec/box_borrow.rs"
printf 'The record.\n\nNone are stored.\n' > "$rec/README.md"
case_check unlisted "a pair the README does not name fails" nonzero "$rec" "box_borrow.zrl is recorded but"

rec=$(newrecord half)
refused "$rec/box_borrow.zrl"
printf 'The record.\n\n- `box_borrow.zrl` - the program, whose twin is missing.\n' > "$rec/README.md"
printf 'fn main() {}\n' > "$rec/stray.rs"
case_check half "half a pair is a fault, not a finding" nonzero "$rec" "box_borrow.rs is missing"
if grep -qF "stray.rs has no .zrl program" "$WORK/half.log"; then
    echo "[PASS] a twin with no program beside it is a fault"
else
    echo "[FAIL] a twin with no program beside it is a fault: no such line"
    sed 's/^/       /' "$WORK/half.log"
    fail=1
fi

if [ "$have_rustc" -eq 1 ]; then
    rec=$(newrecord open)
    accepting "$rec/still_open.zrl"
    printf 'fn main() { let x: i32 = "not an i32"; }\n' > "$rec/still_open.rs"
    printf 'The record.\n\n- `still_open.zrl` - the program half of a pair rustc refuses.\n' > "$rec/README.md"
    case_check open "a pair zoril takes and rustc refuses is still open" nonzero "$rec" "still_open.zrl is still open"

    rec=$(newrecord never)
    accepting "$rec/never.zrl"
    printf 'fn main() {}\n' > "$rec/never.rs"
    printf 'The record.\n\n- `never.zrl` - a pair whose twin rustc accepts too.\n' > "$rec/README.md"
    case_check never "a pair rustc accepts too is reported as no disagreement" zero "$rec" "never.zrl was never a disagreement"
else
    echo "[SKIP] a still-open pair: no rustc to ask about the twin"
    echo "[SKIP] a pair rustc accepts too: no rustc to ask about the twin"
fi

# ── the repository's own record ────────────────────────────────────────────────────────────────────────
case_check record "the repository's record classifies clean" zero "$RECORD" ""

# ── the pipeline the run compiles through ──────────────────────────────────────────────────────────────
# Every run prints its pipeline, and the default has to be the one that ships: a budget spent on another
# backend is not evidence about the compiler that ships, so a run started by hand from the fuzz README's own
# examples must name the host qbe, and any other backend must be asked for out loud.
pipeline_line=$(grep -h '^fuzz: pipeline: ' "$WORK/record.log" | head -1)
case "$pipeline_line" in
    *qbe*) ;;
    *) echo "[FAIL] the default pipeline does not name qbe: ${pipeline_line:-no pipeline line in the run's log}"; fail=1 ;;
esac
case "$pipeline_line" in
    "") ;;
    *) echo "[PASS] the default pipeline is the shipping one: ${pipeline_line#fuzz: pipeline: }" ;;
esac

# ── a run that records must say which compiler it ran ──────────────────────────────────────────────────
# `--release` (and `--record-findings`) refuse a binary built from another commit or a modified tree, and
# the refusal names both hashes. Run only when --release is passed (release verification).
if [ "$CHECK_RELEASE" -eq 1 ]; then
head_hash=unknown
git_checkout_usable "$REPO_ROOT" && head_hash=$(git -C "$REPO_ROOT" rev-parse --short=8 HEAD 2>/dev/null || echo unknown)
if ! command -v git >/dev/null 2>&1 || [ "$head_hash" = "unknown" ]; then
    echo "[SKIP] fuzz-record: git not available for --release commit check"
elif ! command -v timeout >/dev/null 2>&1; then
    echo "[SKIP] fuzz-record: timeout not available for --release commit check"
else
    fakebin() { printf '#!/bin/sh\necho "zoril 0.0.1-test-1-g%s"\n' "$1" > "$WORK/$2"; chmod +x "$WORK/$2"; }
    fakebin 0123abcd stale-zoril
    ZORIL_BIN="$WORK/stale-zoril" "$DRIVER" --release --seeds 1-1 --count 1 --out "$WORK/stale-out" > "$WORK/stale.log" 2>&1
    stale_rc=$?
    if [ "$stale_rc" -ne 0 ] && grep -F "0123abcd" "$WORK/stale.log" | grep -qF "HEAD is $head_hash"; then
        echo "[PASS] a recording run with a compiler from another commit fails, naming both hashes"
    else
        echo "[FAIL] a stale compiler did not stop a --release run (exit $stale_rc, HEAD $head_hash)"
        sed 's/^/       /' "$WORK/stale.log"
        fail=1
    fi
    printf '#!/bin/sh\necho "zoril 0.0.1-test-1-g%s-dirty"\n' "$head_hash" > "$WORK/dirty-zoril"; chmod +x "$WORK/dirty-zoril"
    ZORIL_BIN="$WORK/dirty-zoril" "$DRIVER" --release --seeds 1-1 --count 1 --out "$WORK/dirty-out" > "$WORK/dirty.log" 2>&1
    if [ $? -ne 0 ] && grep -qF "built from a modified tree" "$WORK/dirty.log"; then
        echo "[PASS] a -dirty compiler fails a --release run"
    else
        echo "[FAIL] a -dirty compiler did not stop a --release run"
        sed 's/^/       /' "$WORK/dirty.log"
        fail=1
    fi
fi

# ── a --release run has to be able to support the sentence it is cited for ─────────────────────────────
# Two ways a `--release` run could finish with exit 0 and still not support the sentence it is recorded
# for, both found by the review of 2026-10-19:
#   (a) it could start without `rustc`, the differential oracle that produced both findings so far, and
#       run 15 hours with that oracle off;
#   (b) it could pass while a calibration hole was open: by design a known-hole fault is reported apart
#       from the search and does not touch the exit status, and since `fd37a98e` every row is fixed, so a
#       `still open` row is now a regression the exit status did not show.
# The third case pins the behaviour that already existed - a marked program whose fault survives its
# switch being off is a finding, not the hole - because the `still open` count above rests on it.
# The compiler here is a script that answers `--version` with this tree's commit (fuzz_require_fresh reads
# it back) and otherwise hands over to scripts/fuzz/stub_zoril.sh, so a hole can be reproduced on demand.
if ! command -v timeout >/dev/null 2>&1; then
    echo "[SKIP] fuzz-record: timeout not available for the --release refusal cases"
elif [ "$head_hash" = "unknown" ]; then
    echo "[SKIP] fuzz-record: no git commit for the --release refusal cases"
else
    printf '#!/bin/sh\ncase "$1" in --version) echo "zoril 0.0.1-test-1-g%s" ;; *) exec "%s" "$@" ;; esac\n' \
        "$head_hash" "$REPO_ROOT/scripts/fuzz/stub_zoril.sh" > "$WORK/stub-compiler"
    chmod +x "$WORK/stub-compiler"
    # A stub program that faults only when the driver passes the hole switch (`hole-on`) - what a
    # reopened calibration hole looks like - and one that faults whichever way the switch is set.
    printf 'fn main(argc: i32, _argv: **u8) -> i32 {\n    if argc > 1 { return 91; }\n    return 0;\n}\n' > "$WORK/hole_on.zrl"
    printf 'fn main(argc: i32, _argv: **u8) -> i32 {\n    return 91;\n}\n' > "$WORK/always_fault.zrl"
    for _p in hole_on always_fault; do
        "$ZORIL" -I "stdlib=$REPO_ROOT/stdlib" --emit-zil -o "$WORK/$_p.zil" "$WORK/$_p.zrl" 2>/dev/null || {
            echo "[FAIL] could not compile the stub program $WORK/$_p.zrl with $ZORIL"; fail=1; }
    done

    # FUZZ_FRESH_CHECKED=1 says the freshness check was already made, which is the hook the parallel
    # wrapper uses: the cases below are about the oracle and the holes, and they must not depend on the
    # tree being clean (a developer runs this gate with edits in it, as the two cases above already show).
    # The freshness refusal itself is pinned by those cases.
    # (a) no rustc under --release: refuse before a single program is generated.
    FUZZ_FRESH_CHECKED=1 FUZZ_RUSTC=/nonexistent/rustc FUZZ_STUB_ZIL="$WORK/hole_on.zil" ZORIL_BIN="$WORK/stub-compiler" \
        "$DRIVER" --release --mode calibration --seeds 1-1 --count 1 --no-checked \
        --out "$WORK/norustc-out" > "$WORK/norustc.log" 2>&1
    norustc_rc=$?
    if [ "$norustc_rc" -ne 2 ]; then
        echo "[FAIL] a --release run without rustc: exit $norustc_rc, expected 2"
        sed 's/^/       /' "$WORK/norustc.log"; fail=1
    elif ! grep -q 'rustc' "$WORK/norustc.log"; then
        echo "[FAIL] a --release run without rustc refused, but its message does not name rustc"
        sed 's/^/       /' "$WORK/norustc.log"; fail=1
    elif grep -q '^fuzz-totals: ' "$WORK/norustc.log"; then
        echo "[FAIL] a --release run without rustc generated programs before refusing"
        fail=1
    else
        echo "[PASS] a --release run without rustc refuses (exit 2) before generating a program, and names rustc"
    fi

    # (b) a calibration hole reproduces under --release: exit non-zero, name the row, point at the gate.
    # (b) and (b2) are strict runs, so the driver requires the host's rustc before it starts (case (a)
    # pins that refusal); without it there is no run whose behaviour they could check.
    if [ "$have_rustc" -eq 0 ]; then
        echo "[SKIP] a --release run with a calibration hole open: no rustc, and a cited run requires the differential oracle"
        echo "[SKIP] a --record-findings run with a hole open: no rustc, and a cited run requires the differential oracle"
    else
    FUZZ_FRESH_CHECKED=1 FUZZ_STUB_ZIL="$WORK/hole_on.zil" ZORIL_BIN="$WORK/stub-compiler" \
        "$DRIVER" --release --mode calibration --seeds 1-1 --count 1 --no-checked \
        --out "$WORK/still-open-out" > "$WORK/still-open.log" 2>&1
    open_rc=$?
    if [ "$open_rc" -eq 0 ]; then
        echo "[FAIL] a --release run with a calibration hole open exited 0"
        sed 's/^/       /' "$WORK/still-open.log"; fail=1
    elif ! grep -q 'still open' "$WORK/still-open.log"; then
        echo "[FAIL] a --release run with a hole open failed without saying a hole is still open"
        sed 's/^/       /' "$WORK/still-open.log"; fail=1
    elif ! grep -q 'index_mut_borrow' "$WORK/still-open.log"; then
        echo "[FAIL] a --release run with a hole open did not name the calibration row"
        sed 's/^/       /' "$WORK/still-open.log"; fail=1
    elif ! grep -q 'make fuzz-calibrate' "$WORK/still-open.log"; then
        echo "[FAIL] a --release run with a hole open did not point at make fuzz-calibrate"
        sed 's/^/       /' "$WORK/still-open.log"; fail=1
    else
        echo "[PASS] a --release run with a calibration hole open fails, names the row and points at make fuzz-calibrate"
    fi

    # (b2) the same run under --record-findings keeps the old behaviour: an open row is reported, not
    # fatal. That mode files findings into a repository whose rows may be known open, which is what
    # `make fuzz` does, so only the release-bar run refuses.
    mkdir -p "$WORK/records"
    FUZZ_FRESH_CHECKED=1 FUZZ_STUB_ZIL="$WORK/hole_on.zil" ZORIL_BIN="$WORK/stub-compiler" \
        "$DRIVER" --record-findings --findings "$WORK/records" --mode calibration --seeds 1-1 --count 1 --no-checked \
        --out "$WORK/record-out" > "$WORK/record.log" 2>&1
    rec_rc=$?
    if [ "$rec_rc" -ne 0 ]; then
        echo "[FAIL] a --record-findings run with a calibration hole open: exit $rec_rc, expected 0 (reported, not fatal)"
        sed 's/^/       /' "$WORK/record.log"; fail=1
    elif ! grep -q 'still open' "$WORK/record.log"; then
        echo "[FAIL] a --record-findings run did not report the open calibration row"
        sed 's/^/       /' "$WORK/record.log"; fail=1
    else
        echo "[PASS] a --record-findings run reports an open row without failing (only --release refuses one)"
    fi
    fi

    # (c) a marked program that faults with its switch off is a finding (the behaviour that existed).
    FUZZ_STUB_ZIL="$WORK/always_fault.zil" ZORIL_BIN="$WORK/stub-compiler" \
        "$DRIVER" --mode calibration --seeds 1-1 --count 1 --no-checked \
        --out "$WORK/blind-out" > "$WORK/blind.log" 2>&1
    blind_rc=$?
    blind_totals=$(grep -h '^fuzz-totals: ' "$WORK/blind.log" | head -1)
    blind_off=$(printf '%s\n' "$blind_totals" | tr ' ' '\n' | sed -n 's/^knownblind=//p')
    if [ "$blind_rc" -ne 1 ] || [ "${blind_off:-0}" -eq 0 ] || ! grep -q 'hole switch off' "$WORK/blind.log"; then
        echo "[FAIL] a known-hole program that faults with its switch off: exit $blind_rc, knownblind=${blind_off:-?}"
        sed 's/^/       /' "$WORK/blind.log"; fail=1
    else
        echo "[PASS] a known-hole program that faults with its switch off is a finding (exit 1, knownblind=$blind_off)"
    fi
fi

# ── a run that says nothing writes nothing ─────────────────────────────────────────────────────────────
# The stub compiler accepts every shape, so the mismatch stream is all candidates and the run reaches the
# copy. It must not copy into the repository: with no `--findings`, no `--record-findings` and no
# `FUZZ_FINDINGS` there is nowhere for scratch to go, which is what the 30 pairs needed to stay out of the
# tree. The first item is that the stub really accepted them - a run that faults reaches the copy too, and
# would let the rest of this pass for a reason that has nothing to do with the record.
if ! command -v timeout >/dev/null 2>&1; then
    echo "[SKIP] fuzz-record: timeout not available for stub driver run"
else
    record_state() { (cd "$RECORD" 2>/dev/null && find . -type f | LC_ALL=C sort | while IFS= read -r _f; do sha256_of "$_f"; done) | sha256_of; }
    before=$(record_state)
    accepting "$WORK/stub.zrl"
    "$ZORIL" -I "stdlib=$REPO_ROOT/stdlib" --emit-zil -o "$WORK/stub.zil" "$WORK/stub.zrl" 2>/dev/null
    ( unset FUZZ_FINDINGS 2>/dev/null; \
      FUZZ_STUB_ZIL="$WORK/stub.zil" ZORIL_BIN="$REPO_ROOT/scripts/fuzz/stub_zoril.sh" \
      "$DRIVER" --seeds 1-1 --count 1 --mode mismatch --out "$WORK/stub-out" ) \
        > "$WORK/stub.log" 2>&1
    stub_rc=$?
    after=$(record_state)

    stub_totals=$(grep -h '^fuzz-totals: ' "$WORK/stub.log" | head -1)
    stub_maccepted=$(printf '%s\n' "$stub_totals" | tr ' ' '\n' | sed -n 's/^maccepted=//p')
    stub_faults=$(printf '%s\n' "$stub_totals" | tr ' ' '\n' | sed -n 's/^faults=//p')
    if [ "${stub_maccepted:-0}" -gt 0 ] && [ "${stub_faults:-1}" -eq 0 ]; then
        echo "[PASS] the stub run accepted $stub_maccepted shape(s), so a candidate is what the copy path sees"
    else
        echo "[FAIL] the stub run accepted ${stub_maccepted:-0} shape(s) with ${stub_faults:-?} fault(s): a fault reaches the copy path too, so this would pass for the wrong reason"
        grep -E '^\[' "$WORK/stub.log" | head -5 | sed 's/^/       /'
        fail=1
    fi
    if [ "$stub_rc" -eq 0 ]; then
        echo "[FAIL] a run with no findings directory: exit 0, but the stub accepts every mismatch shape"
        sed 's/^/       /' "$WORK/stub.log"
        fail=1
    else
        echo "[PASS] a run with no findings directory reports the candidate and fails"
    fi
    if ! grep -qF "findings left in" "$WORK/stub.log"; then
        echo "[FAIL] that run should say where the candidate stayed"
        sed 's/^/       /' "$WORK/stub.log"
        fail=1
    else
        echo "[PASS] it says the candidate stayed in the run's own output directory"
    fi
    if [ "$before" != "$after" ]; then
        echo "[FAIL] that run wrote into $RECORD (a test run's scratch belongs in its own output directory)"
        fail=1
    else
        echo "[PASS] $RECORD is unchanged by it"
    fi
fi
fi

if [ "$fail" -ne 0 ]; then
    echo "FAIL: the findings record and the check that reads it disagree (see the items above)."
    exit 1
fi
echo "PASS: --reverify classifies every pair, and a run only records where it was told to."
exit 0
