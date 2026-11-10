#!/bin/sh
# scripts/test_fuzz_tools_git.sh -- fuzz tooling tests that require git:
# sections 7, 7b, 8, 10.
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
    echo "[SKIP] fuzz-tools-git: fuzz dependencies (lua, timeout) not satisfied"
    exit 0
fi
QUIET=${1:-}
# git is optional: the fingerprints, fuzz-preflight's tree check and the record-update fixtures all
# need a checkout to compare against, so those checks report [SKIP] rather than failing here.
have_git=0
git_checkout_usable "$REPO" && have_git=1
TMP=$(mktemp -d "${TMPDIR:-/tmp}/zfuzz.tools_git.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
fails=0
# Fixture repositories are scratch: no hooks, a fixed identity.
gitq() { _r=$1; shift; git -C "$_r" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
ok() { [ -n "$QUIET" ] || echo "[PASS] $1"; }
bad() { echo "FAIL: $1"; fails=$((fails + 1)); [ -n "${2:-}" ] && sed 's/^/       /' "$2" | head -12; }

# ── 7. fuzz-preflight fails on a dirty tree, passes on a clean one ────────────────────────────────────
if [ "$have_git" -eq 0 ]; then
    echo "[SKIP] fuzz-tools-git: fuzz-preflight's tree check needs a git checkout to be clean or dirty"
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
    echo "[SKIP] fuzz-tools-git: fuzz-record-update needs a git repository (fingerprints and page restore)"
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

# ── 10. fuzz-record release refusal checks (requires git and timeout) ─────────────────────────────────
if [ "$have_git" -eq 1 ] && command -v timeout >/dev/null 2>&1; then
    if "$HERE/check_fuzz_record.sh" --release > "$TMP/fuzz_rec_rel.log" 2>&1; then
        ok "check_fuzz_record.sh --release passes"
    else
        bad "check_fuzz_record.sh --release failed" "$TMP/fuzz_rec_rel.log"
    fi
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: fuzz-tools-git: $fails check(s) failed"; exit 1; fi
echo "[PASS] fuzz-tools-git: preflight, freshness, record-update and release refusal on git fixtures"
