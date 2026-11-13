#!/bin/sh
# scripts/test_reject_diff.sh — scripts/check_reject_diff.sh reports and blocks as it says.
#
# Two stand-in trees (a `zoril` and a `zbuild` that refuse the programs named in a list) are compared
# over the safety probes: a probe that must be refused and is newly accepted blocks (exit 1) unless the
# --allow file names it; a probe that is merely accepted by design does not; a newly refused program is
# listed and does not block. The real differential (a build of the base commit) runs from preflight.
cd "$(dirname "$0")/.." || exit 2
fail() { echo "[FAIL] reject-diff-selftest: $1"; exit 1; }
t=build/reject-diff-selftest
# The variant copies of the script (cases 7 and 10) sit in scripts/ because the script finds the repository
# from its own path; a failing case must not leave one in the source tree.
trap 'rm -f scripts/.check_reject_diff_variant.sh' EXIT
rm -rf "$t"
for side in base change; do
    mkdir -p "$t/$side/build" "$t/$side/stdlib"
    for tool in zoril zbuild; do
        cat > "$t/$side/build/$tool" << 'EOF'
#!/bin/sh
# Refuses the file named last (zoril) or in the argument list (zbuild) when its name is in ../refuse.list.
dir=$(dirname "$0")/..
for a in "$@"; do last=$a; done
for a in "$@"; do case "$a" in *.zrl) last=$a ;; esac; done
name=$(basename "$last")
if grep -qx "$name" "$dir/timeout.list" 2>/dev/null; then exit 124; fi
if grep -qx "$name" "$dir/slow.list" 2>/dev/null; then sleep 20; fi
if grep -qx "$name" "$dir/refuse.list" 2>/dev/null; then echo "$last:1:1: error: region escape: stand-in" >&2; exit 1; fi
exit 0
EOF
        chmod +x "$t/$side/build/$tool"
    done
done
reject=$(ls bench/safety_matrix/probes/ | grep '^194_')
accept=$(ls bench/safety_matrix/probes/ | grep '^405_')
other=$(ls bench/safety_matrix/probes/ | grep '^100_')
run() { sh scripts/check_reject_diff.sh --probes-only --jobs 4 "$@" --bins "$t/base" "$t/change" > "$t/out.txt" 2>&1; }

# 1. A probe that must be refused is accepted by the change only.
printf '%s\n' "$reject" > "$t/base/refuse.list"; : > "$t/change/refuse.list"
run; rc=$?
[ "$rc" -eq 1 ] || fail "a newly accepted compile_reject probe did not block (exit $rc)"
grep -q "^NEWLY_ACCEPTED .*$reject (probe-compile_reject)" "$t/out.txt" || fail "no NEWLY_ACCEPTED line for $reject" "$t/out.txt"
# A failed run keeps its files for reading; the next run removes them.
kept=$(sed -n 's/^check_reject_diff: its files are kept in //p' "$t/out.txt")
[ -n "$kept" ] && grep -q "^NEWLY_ACCEPTED .*$reject" "$kept/report.txt" || fail "a failed run did not keep its report (kept: '$kept')"

# 2. The same, listed in the allow file.
printf '%s the reason it is excused\n' "$reject" > "$t/allow.txt"
run --allow "$t/allow.txt"; rc=$?
[ "$rc" -eq 0 ] || fail "an allowed newly accepted probe still blocked (exit $rc)"
grep -q "^NEWLY_ACCEPTED" "$t/out.txt" || fail "an allowed line is still printed" "$t/out.txt"
[ ! -e "$kept" ] || fail "the next run did not remove the failed run's files ($kept)"
! grep -q 'its files are kept' "$t/out.txt" || fail "a passing run kept its files" "$t/out.txt"

# 3. A probe that is accepted by design, newly accepted.
printf '%s\n' "$accept" > "$t/base/refuse.list"; : > "$t/change/refuse.list"
run; rc=$?
[ "$rc" -eq 0 ] || fail "a newly accepted accept-probe blocked (exit $rc)"
grep -q "^NEWLY_ACCEPTED .*$accept (probe-accept)" "$t/out.txt" || fail "no line for the accepted probe" "$t/out.txt"

# 4. A program the change refuses and the base accepted.
: > "$t/base/refuse.list"; printf '%s\n' "$other" > "$t/change/refuse.list"
run; rc=$?
[ "$rc" -eq 0 ] || fail "a newly refused probe blocked (exit $rc)"
grep -q "^NEWLY_REJECTED .*$other" "$t/out.txt" || fail "no NEWLY_REJECTED line for $other" "$t/out.txt"

# 5. Nothing changed.
: > "$t/base/refuse.list"; : > "$t/change/refuse.list"
run; rc=$?
[ "$rc" -eq 0 ] && ! grep -q '^NEWLY' "$t/out.txt" || fail "an unchanged pair reported a difference" "$t/out.txt"

# The base side's verdict cache. A scratch copy of the probes tree and a small stand-in grid, so
# each key input can be changed without touching the repository.
mkdir -p "$t/probes"
cp -R bench/safety_matrix/probes/mylib_fake_mem "$t/probes/"
for p in $(ls bench/safety_matrix/probes | grep '\.zrl$' | awk 'NR <= 40 || /^(194|405|100)_/'); do
    cp "bench/safety_matrix/probes/$p" "$t/probes/$p"
done
mkdir -p "$t/grid/g1"
: > "$t/grid/g1/c1.unsafe.zrl"; : > "$t/grid/g1/c2.unsafe.zrl"; : > "$t/grid/g1/c1.twin.zrl"
: > "$t/base/refuse.list"; : > "$t/change/refuse.list"
rm -f "$t/base/timeout.list" "$t/base/slow.list"
:
crun() { # crun [ENV=VALUE...]: a run over the scratch probes and grid, with the cache in $t/cache
    env REJECT_DIFF_CACHE="$t/cache" REJECT_DIFF_GRID_DIR="$t/grid" REJECT_DIFF_PROBES_DIR="$t/probes" \
        REJECT_DIFF_SEED=1 "$@" sh "${SCRIPT:-scripts/check_reject_diff.sh}" --jobs 4 --bins "$t/base" "$t/change" > "$t/cout.txt" 2>&1
}
note() { sed -n 's/^reject-diff: base verdicts: //p' "$t/cout.txt"; }
entries() { ls "$t/cache" 2>/dev/null | grep -vc '^\.' ; }
rm -rf "$t/cache"

# 6. Cold run stores an entry; a second run hits it. A cached and an uncached run print the same report.
printf '%s\n' "$reject" > "$t/base/refuse.list"; printf '%s\n%s\n' "$reject" "$other" > "$t/change/refuse.list"
printf '%s\n' "$accept" > "$t/base/timeout.list"; rm "$t/base/timeout.list"
crun; rc_cold=$?
note | grep -q '^fresh, stored as cache' || fail "a cold run did not store an entry: $(note)"
[ "$(entries)" -eq 1 ] || fail "a cold run left $(entries) entries"
crun; rc_warm=$?
note | grep -q '^cache [0-9a-f]\{12\}, [0-9]* rerun fresh, sample seed 1; base front end [0-9]* s$' || fail "the second run did not hit the cache: $(note)"
grep -v '^reject-diff: base verdicts' "$t/cout.txt" > "$t/warm.out"
crun REJECT_DIFF_NO_CACHE=1; rc_plain=$?
grep -v '^reject-diff: base verdicts' "$t/cout.txt" > "$t/plain.out"
[ "$rc_cold" -eq "$rc_warm" ] && [ "$rc_warm" -eq "$rc_plain" ] || fail "exit codes differ: cold $rc_cold warm $rc_warm uncached $rc_plain"
cmp -s "$t/warm.out" "$t/plain.out" || fail "a cached and an uncached run print different reports"
grep -q "^NEWLY_REJECTED .*$other" "$t/warm.out" || fail "the comparison run lost a line"

# 7. Each key input changed in turn gives a new key (a miss that stores a second entry).
keyed() { # keyed LABEL: after a change to one input, the next run must miss
    crun; note | grep -q '^fresh, stored as cache' || fail "changing $1 did not change the key: $(note)"
    echo "key ($1): $(note)"
}
echo '// changed' >> "$t/probes/$accept"; keyed "a probe's text"
mkdir -p "$t/probes/mylib_x"; echo 'x' > "$t/probes/mylib_x/lib.zrl"; keyed "a file under the probes tree"
echo '// changed' > "$t/base/stdlib/core.zrl"; keyed "a stdlib file"
echo '# changed' >> "$t/base/build/zoril"; keyed "the zoril binary"
echo '// changed' >> "$t/grid/g1/c2.unsafe.zrl"; keyed "a grid file"
# The runner script's text is in the key: a copy of the script whose runner differs by one character.
SCRIPT=scripts/.check_reject_diff_variant.sh
awk '{ print } /^# run_front.sh TREE FILE/ { print "# variant" }' scripts/check_reject_diff.sh > "$SCRIPT"
keyed "run_front.sh"
rm -f "$SCRIPT"; unset SCRIPT

# 8. A stale entry is caught. The base now refuses the probe the change accepts, the entry says the base
# accepted it: set (a) reruns it and the disagreement deletes the entry and fails the run.
rm -rf "$t/cache"
printf '%s\n' "$reject" > "$t/base/refuse.list"; printf '%s\n' "$reject" > "$t/change/refuse.list"
crun || fail "the clean cold run failed"
entry=$(ls -d "$t/cache"/*/ | head -n 1)
awk -v p="probes/$reject" '$1 == p { $2 = 0 } { print }' "$entry/front_base.txt" > "$t/stale.txt"
cmp -s "$t/stale.txt" "$entry/front_base.txt" && fail "the planted entry did not change"
cat "$t/stale.txt" > "$entry/front_base.txt"
: > "$t/change/refuse.list"
crun; rc=$?
[ "$rc" -eq 1 ] && grep -q "cache entry .* disagreed on .*$reject" "$t/cout.txt" || fail "a planted stale set (a) entry was not caught (exit $rc)"
[ ! -d "$entry" ] || fail "the disagreeing entry was kept"
echo "planted (a): $(grep 'disagreed' "$t/cout.txt" | head -n 1)"
# The same stale entry without the plant is an ordinary blocking line.
rm -rf "$t/cache"; crun; crun; rc=$?
[ "$rc" -eq 1 ] && grep -q "^NEWLY_ACCEPTED .*$reject (probe-compile_reject)" "$t/cout.txt" && ! grep -q disagreed "$t/cout.txt" \
    || fail "a true blocking line did not block from a good entry (exit $rc)"

# 9. A stale entry hidden from sets (a) and (b): the base refuses a probe that is accepted by design, the
# change accepts it, and the entry says the base accepted it. Only the sample reruns it.
rm -rf "$t/cache"
printf '%s\n' "$accept" > "$t/base/refuse.list"; printf '%s\n' "$accept" > "$t/change/refuse.list"
crun || fail "the second clean cold run failed"
entry=$(ls -d "$t/cache"/*/ | head -n 1)
awk -v p="probes/$accept" '$1 == p { $2 = 0 } { print }' "$entry/front_base.txt" > "$t/stale.txt"
cat "$t/stale.txt" > "$entry/front_base.txt"
: > "$t/change/refuse.list"
crun REJECT_DIFF_SAMPLE=1; rc=$?
[ "$rc" -eq 1 ] && grep -q "disagreed on .*$accept" "$t/cout.txt" || fail "a planted stale sample entry was not caught (exit $rc)"
echo "planted (sample): $(grep 'disagreed' "$t/cout.txt" | head -n 1)"

# 10. Without set (a) a stale entry for a must-refuse program passes wrongly: the check is what catches it.
rm -rf "$t/cache"
printf '%s\n' "$reject" > "$t/base/refuse.list"; printf '%s\n' "$reject" > "$t/change/refuse.list"
crun; entry=$(ls -d "$t/cache"/*/ | head -n 1)
awk -v p="probes/$reject" '$1 == p { $2 = 0 } { print }' "$entry/front_base.txt" > "$t/stale.txt"; cat "$t/stale.txt" > "$entry/front_base.txt"
: > "$t/change/refuse.list"
SCRIPT=scripts/.check_reject_diff_variant.sh
awk '{ sub(/\(\(p in must\) && c\[p\] == 0\) \|\| /, "") ; print }' scripts/check_reject_diff.sh > "$SCRIPT"
cmp -s "$SCRIPT" scripts/check_reject_diff.sh && fail "the set (a) edit did not apply"
# The sample is off here: it would catch this program by chance, which is not what set (a) is for.
crun REJECT_DIFF_SAMPLE=0; rc=$?
rm -f "$SCRIPT"; unset SCRIPT
# The zbuild side always runs fresh and still reports the probe; the front-end line is what the stale
# entry hides.
! grep -q disagreed "$t/cout.txt" && ! grep "^NEWLY_ACCEPTED .*$reject" "$t/cout.txt" | grep -qv zbuild \
    || fail "without set (a) the stale front-end entry was still caught: the check cannot see it"

# 11. A base side with a timed-out verdict, and a killed run, leave no entry.
rm -rf "$t/cache"; : > "$t/base/refuse.list"; : > "$t/change/refuse.list"
printf '%s\n' "$other" > "$t/base/timeout.list"
crun
[ "$(entries)" -eq 0 ] && note | grep -q '^fresh, not stored' || fail "a timed-out verdict was stored: $(note)"
rm "$t/base/timeout.list"
printf '%s\n' "$other" > "$t/base/slow.list"
env REJECT_DIFF_CACHE="$t/cache" REJECT_DIFF_GRID_DIR="$t/grid" REJECT_DIFF_PROBES_DIR="$t/probes" \
    sh scripts/check_reject_diff.sh --jobs 4 --bins "$t/base" "$t/change" > "$t/kill.txt" 2>&1 &
pid=$!
sleep 4; kill -TERM "$pid"; wait "$pid" 2>/dev/null
[ -z "$(ls -A "$t/cache" 2>/dev/null)" ] || fail "a killed run left $(ls -A "$t/cache")"
rm -f "$t/base/slow.list"

# 12. An entry serves 4 hits and is then replaced: six runs on one key give fresh, 4 hits, fresh.
rm -rf "$t/cache"; : > "$t/base/refuse.list"; : > "$t/change/refuse.list"
for n in 1 2 3 4 5 6; do
    crun; echo "run $n: $(note)"
    case $n in
        1|6) note | grep -q '^fresh, stored as cache' || fail "run $n of the hit limit was not a fresh store: $(note)" ;;
        *) note | grep -q '^cache [0-9a-f]\{12\}, ' || fail "run $n of the hit limit was not a hit: $(note)" ;;
    esac
done
echo "[PASS] reject-diff-selftest: a newly accepted must-refuse probe blocks unless allowed; accepted-by-design and newly refused programs are listed only; the base verdict cache keys on every input, catches a planted stale entry and stores nothing from a timed-out or killed run"
