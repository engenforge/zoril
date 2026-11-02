#!/bin/sh
# scripts/test_fuzz_mode_diff.sh -- gate: the fuzzer's mode-diff reading (Z1) compares every program built
# whole-program with the same program built by an installed `zbuild`, and a disagreement is a finding.
#
# Three checks, because the first alone passes when the reading is not wired in at all:
#   1. a real run (the repository's compilers, a staged install) compares builds and finds no disagreement;
#   2. the generator writes multi-module programs (Z2);
#   3. the same run with a staged `zbuild` that refuses everything reports a [MODE-DIFF] for each accepted
#      program, counts it, and fails (exit 1).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/.." && pwd)
if ! "$HERE/check_deps.sh" --required-only fuzz >/dev/null 2>&1; then
    echo "[SKIP] fuzz-mode-diff: fuzz dependencies (lua, timeout) not satisfied"
    exit 0
fi
OUT=$(mktemp -d "${TMPDIR:-/tmp}/zfuzz.modediff.XXXXXX")
trap 'rm -rf "$OUT"' EXIT INT TERM
FUZZ_FINDINGS="$OUT/findings"; export FUZZ_FINDINGS; mkdir -p "$FUZZ_FINDINGS"
fail() { echo "[FAIL] fuzz-mode-diff: $1"; [ -n "${2:-}" ] && sed 's/^/       /' "$2" | head -20; exit 1; }

# make exports the repository's own compilers by their relative paths: that must not read as "another compiler".
ZORIL_BIN=build/zoril ZILC_BIN=build/zilc "$HERE/fuzz_safe.sh" --seeds 1-6 --count 3 --mode both --out "$OUT/real" --keep --no-coverage > "$OUT/real.log" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "a real run found something (exit $rc)" "$OUT/real.log"
line=$(grep '^fuzz: mode-diff' "$OUT/real.log")
compared=$(printf '%s\n' "$line" | sed -n 's/.*: \([0-9]*\) build(s) compared.*/\1/p')
[ "${compared:-0}" -gt 0 ] || fail "the real run compared no builds ($line)" "$OUT/real.log"
printf '%s\n' "$line" | grep -q ' 0 disagreement(s)' || fail "the real run reported a disagreement ($line)" "$OUT/real.log"

# The generator writes multi-module programs (Z2): a library module beside the program, an `impl` in a second
# module for a type of the first, and a private item used across modules in the mismatch stream.
GEN=${FUZZ_GEN:-$HERE/fuzz/gen.lua}
for sd in 1 2 3 4 5 6; do lua "$GEN" --seed "$sd" --count 8 --mode templates --out "$OUT/gen" > /dev/null || fail "the generator failed on seed $sd"; done
lua "$GEN" --seed 1 --count 12 --mode grammar --out "$OUT/gen" > /dev/null
ls -d "$OUT"/gen/*_gen.d > /dev/null 2>&1 || fail "no generated program has a library module"
for sd in 7 8 9 10 11 12; do lua "$GEN" --seed "$sd" --count 12 --mode grammar --out "$OUT/gen" > /dev/null; done
ls "$OUT"/gen/3_trait_*_gen.zrl > /dev/null 2>&1 || fail "no generated root is named after the A1 shape (a leading digit and the word trait)"
grep -l "fn lx_dhit" "$OUT"/gen/*_gen.d/*.zrl > /dev/null 2>&1 || fail "no generated library carries the user trait with a default method (Z2.1)"
names=$(ls "$OUT"/gen/*_gen.d/*.zrl | sed "s|.*/||" | sort -u | wc -l)
[ "$names" -ge 4 ] || fail "the generated library modules use $names distinct names (Z3 varies them)"ls "$OUT"/gen/*_tpl_xmod_impl.d/pt_impl.zrl > /dev/null 2>&1 || fail "no xmod_impl template was generated in seeds 1-6"
lua "$GEN" --seed 1 --count 0 --mode mismatch --out "$OUT/gen" > /dev/null
ls "$OUT"/gen/mismatch/*_private_item_across_modules.d/private_lib.zrl > /dev/null 2>&1 || fail "the private-item mismatch program is missing"
ls "$OUT"/gen/mismatch/*_stdlib_contract_clone_in.zrl > /dev/null 2>&1 || fail "the clone_in contract program (A2's calibration row) is missing"
ls "$OUT"/gen/mismatch/*_bad_module_name_9lib.d/9lib.zrl > /dev/null 2>&1 || fail "the bad-module-name mismatch programs are missing"

# A staged install whose zbuild refuses everything: every program the whole-program build accepts is a mode-diff.
mkdir -p "$OUT/fake/usr/bin"
printf '#!/bin/sh\necho "zbuild: refused (test stub)" >&2\nexit 1\n' > "$OUT/fake/usr/bin/zbuild"
chmod +x "$OUT/fake/usr/bin/zbuild"
FUZZ_STAGE="$OUT/fake" "$HERE/fuzz_safe.sh" --seeds 1-6 --count 3 --mode both --out "$OUT/fake_run" --keep --no-coverage --zbuild > "$OUT/fake.log" 2>&1
rc=$?
[ "$rc" -eq 1 ] || fail "a zbuild that refuses everything did not fail the run (exit $rc)" "$OUT/fake.log"
grep -q '^\[MODE-DIFF\] .*whole-program: accepted; zbuild: rejected' "$OUT/fake.log" || fail "no [MODE-DIFF] line for an accepted program" "$OUT/fake.log"
n=$(grep -c '^\[MODE-DIFF\]' "$OUT/fake.log")
counted=$(sed -n 's/^fuzz: mode-diff .*: [0-9]* build(s) compared, \([0-9]*\) disagreement.*/\1/p' "$OUT/fake.log")
[ "$counted" = "$n" ] && [ "$n" -gt 0 ] || fail "the summary counts $counted disagreement(s), the log has $n" "$OUT/fake.log"
echo "[PASS] fuzz-mode-diff: $compared builds compared with no disagreement; a zbuild that refuses everything is reported $n time(s) and fails the run"
