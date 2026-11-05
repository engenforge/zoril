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
echo "[PASS] reject-diff-selftest: a newly accepted must-refuse probe blocks unless allowed; accepted-by-design and newly refused programs are listed only"
