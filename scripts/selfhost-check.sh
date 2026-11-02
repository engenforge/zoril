#!/bin/sh
# scripts/selfhost-check.sh — the two-stage bootstrap and self-hosting gate.
#
# Answers two questions (see README.md two-stage bootstrap):
#
#   1. Does the stage1 path still work? stage0-C builds the frozen snapshot
#      compiler into build/zoril-stage1 and build/zilc-stage1, and stage1 then
#      compiles src/. This is what keeps src/, and the stdlib modules it imports,
#      within what the pinned stage1 accepts. On 2026-09-10 a stdlib edit broke the
#      bootstrap and went unnoticed for days because no gate ran it.
#
#   2. Is the compiler built from src/ a fixpoint? Two consecutive self-hosted
#      generations built from src/ must emit byte-identical ZIL. That catches a
#      compiler that miscompiles itself.
#
# The FULL gate answers both in a CLEAN COPY OF THE TREE, through the Makefile's default
# rules: a copy with no build/ in it, so no build/zoril and no build/zilc -- the path `make`
# takes in a fresh checkout or a fresh export, which no other gate ever takes (they all start
# from an existing build/zoril). It broke on 2026-10-13: the default rule fed src/'s ZIL,
# which has written Phase D's `RawPtr<T>`/`RawPtrMut<T>` since 2026-10-12, to the frozen
# build/zilc-stage1, which knows neither spelling -- it read the name as a var type, left the
# arguments behind, and then spun in its parse_module until BOOTSTRAP_BUILD_TIMEOUT. A fresh
# checkout hits that on its first `make`, and nothing reported it. Measured on this machine
# (2026-10-13, 16 cores): the whole fresh path is about 45s, against the 39s of the fixpoint
# alone (the old gate), so covering the fresh path costs the pre-merge gates about 15s.
#
# The copy is the WORKING TREE, not HEAD: a pre-merge gate must judge what is about to be
# merged. Nothing here writes to this tree's build/zoril, build/zilc or build/selfhost -- the
# copy has its own build/, and every artifact of the run (copy, logs, scratch, generations)
# is under $WORK, with TMPDIR and TR_WORK pointed into it.
#
# Generations, all inside the copy: gen1 = build/zoril-stage1 (stage0-C-built stage1). gen2 =
# src/ compiled by gen1 (the copy's build/zoril, assembled by build/zilc-stage1). gen3 = src/
# compiled by gen2, assembled by the copy's build/zilc. gen4's ZIL = src/ compiled by gen3.
# The fixpoint is gen3.zil == gen4.zil: both are produced by compilers built from src/.
# gen2.zil (stage1's output) legitimately differs once src/ diverges from the snapshot, so it
# is not compared.
#
# Usage:
#   scripts/selfhost-check.sh              # both questions, in a clean copy
#   scripts/selfhost-check.sh --build-only # question 1 only, in this tree (~30s)
#   scripts/selfhost-check.sh --keep       # leave the copy and the generations to inspect
#
# Exit 0 = both hold. Non-zero = one does not, the message says which, and the copy and its
# logs are left under $WORK for inspection.

set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$REPO"
cd "$REPO"
unset MAKEFLAGS MAKEOVERRIDES MFLAGS MAKELEVEL

BUILD_ONLY=0
KEEP=0
for arg in "$@"; do
    case "$arg" in
        --build-only) BUILD_ONLY=1 ;;
        --keep)       KEEP=1 ;;
        -h|--help)    awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
        *)            echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# Backend: zilc, then the HOST qbe/as/ld -- the same backend the Makefile uses.
# The SH_ prefix avoids inheriting the Makefile's exported toolchain variables,
# which name the same roles but are set for a different step.
. "$(dirname "$0")/env.sh"
. "$(dirname "$0")/lib/layout.sh"
SH_ZILC="${SH_ZILC:-build/zilc}"
SH_QBE="${SH_QBE:-${BACKEND_BIN:-qbe}}"
SH_AS="${SH_AS:-${ASSEMBLER_BIN:-as}}"
SH_LD="${SH_LD:-${LINKER_BIN:-ld}}"

# Where the full gate puts the clean copy, its logs and its scratch. build/ is gitignored, so
# this never touches a tracked file -- and it is a subdirectory of build/, never build/
# itself, so the build/zoril and build/zilc of the everyday loop are untouched.
WORK="${FRESH_BOOTSTRAP_WORK:-$REPO/build/fresh-bootstrap}"
case "$WORK" in
    "$REPO"/build/*) ;;
    *) echo "FRESH_BOOTSTRAP_WORK must be under $REPO/build (got '$WORK'): this script removes it" >&2; exit 2 ;;
esac
# --build-only runs in this tree and keeps its own artifacts where it always has.
BW="$REPO/build/selfhost"
# Wall-clock bound on the whole fresh path. The Makefile bounds each step it runs
# (BOOTSTRAP_BUILD_TIMEOUT); this bounds the run, so a hang no step's timeout covers still
# fails the gate. Measured 43s on 2026-10-13; the gate runs beside mutation-check, on a
# loaded machine, so leave it room.
FRESH_TIMEOUT="${FRESH_BOOTSTRAP_TIMEOUT:-900s}"
TIMEOUT_BIN="${TIMEOUT_BIN:-timeout $TIMEOUT_FOREGROUND}"

STEP=0
_T0=0
step() { STEP=$((STEP + 1)); printf '\n[%d] %s\n' "$STEP" "$1"; _T0=$(date +%s); }
secs() { printf '%ss' "$(( $(date +%s) - _T0 ))"; }
fail() { printf '\nFAIL: %s\n' "$1" >&2; exit 1; }

# The chain-built binaries need a large stack on multi-MB inputs (Makefile:110).
ulimit -s 262144 2>/dev/null || true

# QBE stores a 64-bit constant to memory as two 32-bit halves (movl $val, ...; movl $val>>32, ...).
# When val is 0x8000000000000000, GAS warns: "Warning: 0x8000000000000000 shortened to 0x0".
# The truncation is benign (the low half of 0x8000000000000000 is 0), but clean builds must
# print no warnings. We filter exactly this warning when followed by QBE's >>32 half, and
# fail on any other assembler warning.
filter_as_warning() {
    _s="$1"
    _log="$2"
    [ -s "$_log" ] || { rm -f "$_log"; return 0; }
    _unexpected=$(grep -v "Assembler messages:" "$_log" | grep -v "Warning: 0x8000000000000000 shortened to 0x0" || true)
    if [ -n "$_unexpected" ]; then
        cat "$_log" >&2
        rm -f "$_log"
        return 1
    fi
    _lines=$(sed -n 's/.*:\([0-9][0-9]*\): Warning: 0x8000000000000000 shortened to 0x0/\1/p' "$_log")
    for _ln in $_lines; do
        _next=$(sed -n "$((_ln + 1))p" "$_s" 2>/dev/null || true)
        case "$_next" in
            *">>32"*) ;;
            *) cat "$_log" >&2; rm -f "$_log"; return 1 ;;
        esac
    done
    rm -f "$_log"
    return 0
}

# Compile src/ with $1, emitting ZIL to $2, then link a binary at $3 using the zilc
# in $4 (default $SH_ZILC). stage1's ZIL goes through build/zilc-stage1, the zilc
# of the same vintage.
# Splitting emit from link matters: the fixpoint compares the ZIL text, which
# is what architecture.md's zoril fixpoint has always compared.
# Runs in the current directory, so the include roots and build/runtime.o are the caller's.
generation() {
    _cc="$1"; _zil="$2"; _bin="$3"; _zc="${4:-$SH_ZILC}"
    "$_cc" -I stdlib=stdlib -I src -I build/gen --emit-zil -o "$_zil" src/main.zrl \
        >"$_zil.log" 2>&1 || { tail -20 "$_zil.log" >&2; fail "$_cc could not compile src/ — see $_zil.log"; }
    [ -n "$_bin" ] || return 0
    "$_zc" "$_zil" "$_bin.ssa"                      || fail "zilc failed on $_zil"
    "$SH_QBE" -o "$_bin.s" "$_bin.ssa"              || fail "qbe failed on $_bin.ssa"
    _as_log="$_bin.as.log"
    if ! "$SH_AS" -o "$_bin.o" "$_bin.s" >"$_as_log" 2>&1; then
        cat "$_as_log" >&2; rm -f "$_as_log"; fail "as failed on $_bin.s"
    fi
    filter_as_warning "$_bin.s" "$_as_log" || fail "unexpected assembler warning assembling $_bin.s"
    "$SH_LD" -o "$_bin" "$_bin.o" build/runtime.o   || fail "ld failed on $_bin.o"
    chmod +x "$_bin"
}

# ------------------------------------------------- question 1, this tree (--build-only)
if [ "$BUILD_ONLY" -eq 1 ]; then
    step "bootstrap seed builds stage1 compiler (build/zoril-stage1, build/zilc-stage1)"
    mkdir -p "$(dirname "$BW")"
    rm -f build/zoril-stage1 build/zilc-stage1
    make build/gen/version.zrl build/zoril-stage1 build/zilc-stage1 >"$BW.build.log" 2>&1 || {
        tail -30 "$BW.build.log" >&2
        fail "bootstrap seed can no longer build stage1 compiler — see $BW.build.log

Either $STAGE0_DIR changed (every $STAGE0_DIR change must keep building stage1; fix it
and add a $STAGE0_DIR/tests/fixed_bugs/ test), or, during a re-pin, the candidate uses
forms outside the bootstrap dialect)."
    }
    echo "    ok"

    for t in "$SH_ZILC" "$SH_QBE" "$SH_AS" "$SH_LD"; do
        [ -x "$t" ] || command -v "$t" >/dev/null 2>&1 || fail "missing backend binary: $t
Need build/zilc (from 'make build/zilc') plus host qbe, as and ld.
Override with SH_ZILC / SH_QBE / SH_AS / SH_LD."
    done
    [ -f build/runtime.o ] || "$SH_AS" -o build/runtime.o rt/runtime.s || \
        fail "could not assemble build/runtime.o from rt/runtime.s"

    step "generation 2 — stage1 compiles src/"
    generation ./build/zoril-stage1 "$BW.gen2.zil" "$BW.gen2" build/zilc-stage1
    echo "    ok — $(wc -l <"$BW.gen2.zil") lines"

    printf '\nPASS (build only — fixpoint not checked)\n'
    exit 0
fi

# ------------------------------------------------- question 1, a clean copy of the tree
step "a clean copy of the tree (no build/, no .git/) builds with the default rules"
rm -rf "$WORK"
mkdir -p "$WORK/tree" "$WORK/tmp" "$WORK/tr"
# A fresh checkout is a copy with no build/ at all. `bootstrap/` is left out only in THIS tree,
# where it is the 1 GB hex-chain incubator that the source bootstrap does not need; in the
# exported tree bootstrap/ IS the source bootstrap (bootstrap/stage0-c, bootstrap/stage1) and
# is copied like everything else. The copy is the working tree, so uncommitted changes count.
_exclude_bootstrap=""
if [ "$STAGE0_DIR" != "bootstrap/stage0-c" ]; then _exclude_bootstrap="--exclude=bootstrap"; fi
tar -c --exclude=build --exclude=.git --exclude=.zoril-cache $_exclude_bootstrap . \
    | tar -x -C "$WORK/tree"
if [ -e "$WORK/tree/build/zoril" ]; then
    fail "the copy is not clean: it already has build/zoril"
fi
# TMPDIR and TR_WORK point into $WORK: nothing in this run may share scratch, a test lock or
# a log with the everyday loop. The Makefile bounds its own steps; $FRESH_TIMEOUT bounds the
# run, and a timeout here is a gate failure, not a slow machine that "should pass".
( cd "$WORK/tree" && TMPDIR="$WORK/tmp" TR_WORK="$WORK/tr" \
    $TIMEOUT_BIN -k 5s "$FRESH_TIMEOUT" make build/zoril build/zilc ) >"$WORK/fresh-build.log" 2>&1 || {
    _st=$?
    sed 's/^/       /' "$WORK/fresh-build.log" | tail -30 >&2
    _why="the fresh path failed"
    if [ "$_st" -eq 124 ] || [ "$_st" -eq 137 ]; then
        _why="the fresh path did not finish within $FRESH_TIMEOUT"
    fi
    if grep -q "failed to build" "$WORK/fresh-build.log"; then
        fail "bootstrap seed can no longer build stage1 compiler in a clean copy — see $WORK/fresh-build.log

Either $STAGE0_DIR changed (every $STAGE0_DIR change must keep building stage1; fix it
and add a $STAGE0_DIR/tests/fixed_bugs/ test), or, during a re-pin, the candidate uses
forms outside the bootstrap dialect)."
    fi
    fail "$_why — see $WORK/fresh-build.log

A clean checkout takes this path on its first \`make\`: no build/zoril and no build/zilc, so
the Makefile builds the bootstrap compilers and bootstraps its own zilc on the way. The
copy is left in $WORK/tree, with the failed build's log beside it."
}
for f in build/zoril build/zilc; do
    [ -x "$WORK/tree/$f" ] || fail "the fresh build did not produce $f (see $WORK/fresh-build.log)"
done
if grep -E "(Assembler messages|Warning:)" "$WORK/fresh-build.log"; then
    fail "unexpected assembler warning in fresh build — see $WORK/fresh-build.log"
fi
if [ -e "$WORK/tree/a.out" ]; then
    fail "the fresh build left an a.out in the root"
fi
"$REPO_ROOT/scripts/check_clean_tree.sh" "$WORK/tree" >"$WORK/clean-tree.log" 2>&1 || {
    cat "$WORK/clean-tree.log" >&2
    fail "the fresh build left stray build artifacts outside build/ — see $WORK/clean-tree.log"
}
echo "    ok — $(secs)"

# A one-line program through the toolchain the fresh path just built: the build above proves
# the two binaries run, this proves they agree end to end. It is deliberately small; the real
# functional check is generation 3/4 below, which is built by them.
step "the freshly built compiler and zilc compile and run a program"
cat >"$WORK/smoke.zrl" <<'SMOKE'
fn main() -> i32 { return 42; }
SMOKE
( cd "$WORK/tree" \
    && ./build/zoril --emit-zil -o "$WORK/smoke.zil" "$WORK/smoke.zrl" \
    && ./build/zilc "$WORK/smoke.zil" "$WORK/smoke.ssa" \
    && "$SH_QBE" -o "$WORK/smoke.s" "$WORK/smoke.ssa" \
    && "$SH_AS" -o "$WORK/smoke.o" "$WORK/smoke.s" \
    && "$SH_LD" -o "$WORK/smoke" "$WORK/smoke.o" build/runtime.o ) >"$WORK/smoke.log" 2>&1 || {
    sed 's/^/       /' "$WORK/smoke.log" | tail -20 >&2
    fail "the freshly built toolchain could not compile a one-line program — see $WORK/smoke.log"
}
chmod +x "$WORK/smoke" 2>/dev/null || true
_rc=0
"$WORK/smoke" || _rc=$?
[ "$_rc" -eq 42 ] || fail "the freshly built compiler's program exited $_rc, not 42"
echo "    ok"

# ------------------------------------------------- question 2, the fixpoint (in the copy)
cd "$WORK/tree"

step "generation 3 — the fresh build/zoril compiles src/ (assembled by the fresh build/zilc)"
generation ./build/zoril "$WORK.gen3.zil" "$WORK.gen3" ./build/zilc
echo "    ok — $(wc -l <"$WORK.gen3.zil") lines"

step "generation 4 — gen3 compiles src/"
generation "$WORK.gen3" "$WORK.gen4.zil" ""
echo "    ok — $(wc -l <"$WORK.gen4.zil") lines"

step "fixpoint — gen3.zil vs gen4.zil must be identical"
if cmp -s "$WORK.gen3.zil" "$WORK.gen4.zil"; then
    echo "    ok — identical"
else
    cmp "$WORK.gen3.zil" "$WORK.gen4.zil" >&2 || true
    echo "" >&2
    diff "$WORK.gen3.zil" "$WORK.gen4.zil" 2>/dev/null | head -40 >&2 || true
    fail "self-hosting fixpoint does not hold.

Two consecutive self-hosted generations emitted different ZIL. The compiler
miscompiles itself: gen3 and gen4 are built from the same source, so any
difference is the compiler behaving differently depending on which compiler
built it. Generations left in $WORK.* for inspection."
fi

if [ "$KEEP" -eq 1 ]; then
    printf '\nPASS — the copy and the generations are kept in %s\n' "$WORK"
else
    cd "$REPO"
    rm -rf "$WORK"
    printf '\nPASS — a clean copy of the tree builds with the default rules, and the compiler reproduces itself.\n'
fi
