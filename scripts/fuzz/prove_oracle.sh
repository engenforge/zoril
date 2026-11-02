#!/bin/sh
# scripts/fuzz/prove_oracle.sh -- prove an oracle can fail: break the compiler on a scratch copy, run the
# fuzzer with that compiler, and require the oracle to report it - and require the unbroken compiler to be
# clean over the same seeds. An oracle never seen to fire is a guess.
#
#   make fuzz-prove [ORACLE=value|bounds|box|mode|all]
#
# value:  the expected-value oracle (exit 93). A mutant that computes a wrong value and faults nowhere:
#         unary minus lowered as bitwise not (every negative literal is off by one).
# bounds: the runtime-check traps. A mutant with the array and slice bounds check removed must make a
#         program that indexes out of range exit 0 where the generator computed the 134 trap, which the
#         driver reports as a `trap-fault` (the same mutant is M1 of scripts/mutation-check.sh).
#
# box:    the expected-value and crash oracles on a field reached through a reference to a `Box`. Two mutants:
#         one whose field access dereferences only one layer of `&Box<S>` (refused by the ZIL `field_addr` rule),
#         and one that also removes that ZIL rule (in both `zoril` and `zilc`) so the miscompile runs and the
#         `box_point` builder's checksum (exit 93), canaries or crash oracle must report it.
#
# mode:   the mode-diff reading (whole-program build against an installed `zbuild`). Four mutants put back
#         defects the user-path work fixed, each of which only the separate-compilation path showed:
#           - a `.zri` that drops the `#[borrows]`/`#[stores]` of a generic body it keeps (A2);
#           - a digit-led module stem written raw into the ZIL (A1: a root named `3_trait_5_0_gen`, a digit-led
#             name holding the word `trait`, with a function or a type of its own);
#           - a trait's default method bodies left out of the names an interface must carry (A7.3: a library
#             whose default method names a private function or `static`);
#           - a private trait left out of an interface that carries an impl of it (A7.4: `unknown trait`);
#           - the A7.5-A7.11 routes, one mutant each: the allocator of `box(allocator)` dropped from an interface,
#             a generic impl's type parameters ignored when its private items are collected (slice target), a
#             trait impl's methods left out of that collection (`Drop`), the private generic helpers behind a
#             public generic body not scanned, a specialization's bodies not written, and a struct literal in a
#             head not parenthesized.
#         Each is built into its own staged install (the mutant `zoril` beside the repository's `zbuild`), and
#         the run must report a [MODE-DIFF]; the unbroken pair must not.
#
# The scratch copy is built the way scripts/mutation-check.sh builds a mutant: the repository's src/ with
# one line changed, compiled by build/zoril, linked with build/runtime.o. Nothing in the tree is touched.
#
# Usage: prove_oracle.sh [value|bounds|box|mode|all] [--seeds A-B]
set -u
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO_ROOT" || exit 2
. scripts/env.sh
ORACLE=all; SEEDS=1-120
while [ $# -gt 0 ]; do
    case "$1" in
        value|bounds|box|mode|all) ORACLE=$1; shift ;;
        --seeds) SEEDS=$2; shift 2 ;;
        -h|--help) sed -n '2,39p' "$0"; exit 0 ;;
        *) echo "usage: $0 [value|bounds|box|mode|all] [--seeds A-B]" >&2; exit 2 ;;
    esac
done
STAGE=build/fuzz-prove
rm -rf "$STAGE"; mkdir -p "$STAGE"
fails=0
say() { echo "$*"; }

# stage NAME -- a scratch copy of src/ for the mutant NAME.
stage() { d="$STAGE/$1"; mkdir -p "$d"; cp -R src "$d/src"; }

# mutate NAME FILE FIND REPL -- replace FIND by REPL in FILE of the scratch copy; a replacement that finds
# nothing is an error, because a mutant that was never applied proves nothing.
mutate() {
    d="$STAGE/$1"
    find_=$(printf '%s' "$3" | sed 's/[][\.*^$#&]/\\&/g')
    repl_=$(printf '%s' "$4" | sed 's/[#&\\]/\\&/g')
    cp "$d/$2" "$d/$2.orig"
    sed "s#${find_}#${repl_}#" "$d/$2.orig" > "$d/$2"
    if cmp -s "$d/$2" "$d/$2.orig"; then echo "[FAIL] prove: the mutation of $1 did not apply (the source moved)"; return 1; fi
}

# compile NAME -- build the mutant compiler the way scripts/mutation-check.sh builds one.
compile() {
    d="$STAGE/$1"
    ( ulimit -s 262144 2>/dev/null
      build/zoril -I stdlib=stdlib -I "$d/src" -I build/gen --emit-zil -o "$d/zoril.zil" "$d/src/main.zrl" &&
      build/zilc "$d/zoril.zil" "$d/zoril.ssa" && "$BACKEND_BIN" -o "$d/zoril.s" "$d/zoril.ssa" &&
      "$ASSEMBLER_BIN" -o "$d/zoril.o" "$d/zoril.s" && "$LINKER_BIN" -o "$d/zoril" build/runtime.o "$d/zoril.o" ) > "$d/build.log" 2>&1 \
        || { echo "[FAIL] prove: the mutant $1 does not build (see $d/build.log)"; return 1; }
}

# compile_zilc NAME -- build zilc against the mutant's src/ when the mutation touches ZIL checking.
compile_zilc() {
    d="$STAGE/$1"
    ( ulimit -s 262144 2>/dev/null
      build/zoril -I stdlib=stdlib -I "$d/src" -I tools/zilc/src -I build/gen --emit-zil -o "$d/zilc.zil" tools/zilc/src/main.zrl &&
      build/zilc "$d/zilc.zil" "$d/zilc.ssa" && "$BACKEND_BIN" -o "$d/zilc.s" "$d/zilc.ssa" &&
      "$ASSEMBLER_BIN" -o "$d/zilc.o" "$d/zilc.s" && "$LINKER_BIN" -o "$d/zilc" build/runtime.o "$d/zilc.o" ) > "$d/build-zilc.log" 2>&1 \
        || { echo "[FAIL] prove: the mutant zilc for $1 does not build (see $d/build-zilc.log)"; return 1; }
}

build_mutant() { stage "$1" && mutate "$1" "$2" "$3" "$4" && compile "$1"; }

# fuzz_with COMPILER OUTDIR -- the fuzzer over the seeds with that compiler; prints its log path.
fuzz_with() {
    ZORIL_BIN=$1 FUZZ_FINDINGS="$STAGE/findings" ./scripts/fuzz_safe.sh --seeds "$SEEDS" --count 4 --mode grammar \
        --no-checked --out "$2" > "$2.log" 2>&1
}

# prove NAME FAULT-WORD -- the mutant's run must name FAULT-WORD in a [FAULT] line; the good compiler's must not.
prove() {
    name=$1; word=$2
    fuzz_with "$STAGE/$name/zoril" "$STAGE/run-$name"
    if grep -q "^\[FAULT\].*$word" "$STAGE/run-$name.log"; then
        n=$(grep -c "^\[FAULT\].*$word" "$STAGE/run-$name.log")
        say "[PASS] prove: the $name mutant is reported ($n program(s) with $word)"
    else
        say "[FAIL] prove: the $name mutant was not reported as $word over seeds $SEEDS"; tail -n 5 "$STAGE/run-$name.log" | sed 's/^/       /'; fails=$((fails + 1))
    fi
}
good() {
    fuzz_with build/zoril "$STAGE/run-good-$1"
    if grep -q "^\[FAULT\]" "$STAGE/run-good-$1.log"; then
        say "[FAIL] prove: the unbroken compiler reported a fault over seeds $SEEDS"; grep "^\[FAULT\]" "$STAGE/run-good-$1.log" | head -3 | sed 's/^/       /'; fails=$((fails + 1))
    else
        say "[PASS] prove: the unbroken compiler is clean over seeds $SEEDS"
    fi
}

if [ "$ORACLE" = value ] || [ "$ORACLE" = all ]; then
    build_mutant neg-as-not src/lower_zir_to_zil.zrl '(*self.builder).emit_with_type(ILInstr.Neg(val), res_ty),' '(*self.builder).emit_with_type(ILInstr.Not(val), res_ty),' && prove neg-as-not "value-fault 93" || fails=$((fails + 1))
    good value
fi
if [ "$ORACLE" = bounds ] || [ "$ORACLE" = all ]; then
    stage no-bounds-check && mutate no-bounds-check src/builder.zrl 'self.emit_bounds_check_against(idx_ssa, len_ssa, usize_ty, bool_ty, u64_ty, i64_ty);' 'return;' \
        && compile no-bounds-check && prove no-bounds-check "trap-fault expected exit 134, got 0" || fails=$((fails + 1))
    good bounds
fi
if [ "$ORACLE" = box ] || [ "$ORACLE" = all ]; then
    # First mutant: the ZIL check on `field_addr` (src/il_typecheck.zrl) refuses what the broken lowering emits,
    # so the run reports the programs as generator bugs ("invalid ZIL (a compiler bug)").
    if build_mutant box-one-layer src/lower_zir_to_zil.zrl 'while cur_ty != 0 as u32 && depth < 16 as usize {' 'while cur_ty != 0 as u32 && depth < 1 as usize {'; then
        fuzz_with "$STAGE/box-one-layer/zoril" "$STAGE/run-box-one-layer" || true
        if grep -q '^\[FAULT\]\|^\[GEN-BUG\].*field_addr' "$STAGE/run-box-one-layer.log"; then
            say "[PASS] prove: the box-one-layer mutant is reported ($(grep -c '^\[FAULT\]\|^\[GEN-BUG\].*field_addr' "$STAGE/run-box-one-layer.log") program(s))"
        else
            say "[FAIL] prove: the box-one-layer mutant was not reported over seeds $SEEDS"; fails=$((fails + 1))
        fi
    else
        fails=$((fails + 1))
    fi
    # Second mutant: remove the ZIL `field_addr` check as well (in both `zoril` and `zilc`) so the broken
    # lowering compiles and runs; the expected-value (exit 93), canary or crash oracle must report it directly.
    if stage box-no-zil-rule \
        && mutate box-no-zil-rule src/lower_zir_to_zil.zrl 'while cur_ty != 0 as u32 && depth < 16 as usize {' 'while cur_ty != 0 as u32 && depth < 1 as usize {' \
        && mutate box-no-zil-rule src/il_typecheck.zrl 'if base != 0 as u32 && !field_base_ok(m, base, fa.field_idx) {' 'if false {' \
        && compile box-no-zil-rule && compile_zilc box-no-zil-rule; then
        ZILC_BIN="$STAGE/box-no-zil-rule/zilc" fuzz_with "$STAGE/box-no-zil-rule/zoril" "$STAGE/run-box-no-zil-rule" || true
        if grep -Eq '^\[FAULT\].*(value-fault 93|canary-fault 92|signal )' "$STAGE/run-box-no-zil-rule.log"; then
            say "[PASS] prove: the box-no-zil-rule mutant is reported by value/crash oracle ($(grep -cE '^\[FAULT\].*(value-fault 93|canary-fault 92|signal )' "$STAGE/run-box-no-zil-rule.log") program(s))"
        else
            say "[FAIL] prove: the box-no-zil-rule mutant was not reported by value/crash oracle over seeds $SEEDS"; tail -n 5 "$STAGE/run-box-no-zil-rule.log" | sed 's/^/       /'; fails=$((fails + 1))
        fi
    else
        fails=$((fails + 1))
    fi
    good box
fi
# prove_mode NAME -- the fuzzer with the mutant NAME as the compiler of both legs and as the `zoril` of a staged
# install must report a [MODE-DIFF]. The run is `mix`, whose random hole programs are what depend on a contract.
prove_mode() {
    name=$1; d="$STAGE/$name"; st="$PWD/$STAGE/stage-$name"
    make install-files DESTDIR="$st" PREFIX=/usr > "$STAGE/install-$name.log" 2>&1 \
        || { echo "[FAIL] prove: cannot stage an install for the $name mutant"; fails=$((fails + 1)); return; }
    cp "$d/zoril" "$st/usr/bin/zoril"
    ZORIL_BIN="$PWD/$d/zoril" FUZZ_STAGE="$st" FUZZ_FINDINGS="$STAGE/findings" ./scripts/fuzz_safe.sh --seeds "$SEEDS" --count 4 --mode mix \
        --no-checked --zbuild --out "$STAGE/run-$name" > "$STAGE/run-$name.log" 2>&1
    if grep -q '^\[MODE-DIFF\]' "$STAGE/run-$name.log"; then
        n=$(grep -c '^\[MODE-DIFF\]' "$STAGE/run-$name.log")
        say "[PASS] prove: the $name mutant is reported ($n mode-diff(s))"
    else
        say "[FAIL] prove: the $name mutant raised no [MODE-DIFF] over seeds $SEEDS"; tail -n 5 "$STAGE/run-$name.log" | sed 's/^/       /'; fails=$((fails + 1))
    fi
}
good_mode() {
    ./scripts/fuzz_safe.sh --seeds "$SEEDS" --count 4 --mode mix --no-checked --zbuild --out "$STAGE/run-good-mode" > "$STAGE/run-good-mode.log" 2>&1
    if grep -q '^\[MODE-DIFF\]' "$STAGE/run-good-mode.log"; then
        say "[FAIL] prove: the unbroken compiler raised a mode-diff over seeds $SEEDS"; grep '^\[MODE-DIFF\]' "$STAGE/run-good-mode.log" | head -3 | sed 's/^/       /'; fails=$((fails + 1))
    else
        say "[PASS] prove: the unbroken compiler has no mode-diff over seeds $SEEDS"
    fi
}
if [ "$ORACLE" = mode ] || [ "$ORACLE" = all ]; then
    stage zri-drops-contracts && mutate zri-drops-contracts src/interface_print.zrl 'if f.has_borrows {' 'if f.has_borrows && false {' \
        && mutate zri-drops-contracts src/interface_print.zrl 'if f.has_stores {' 'if f.has_stores && false {' \
        && compile zri-drops-contracts && prove_mode zri-drops-contracts || fails=$((fails + 1))
    stage digit-stem-raw && mutate digit-stem-raw src/il_cfg.zrl "if path[seg_start] >= '0' as u8 && path[seg_start] <= '9' as u8 {" 'if false {' \
        && compile digit-stem-raw && prove_mode digit-stem-raw || fails=$((fails + 1))
    stage default-bodies-uncounted && mutate default-bodies-uncounted src/ast.zrl 'if t.source_file == target_sf {' 'if false {' \
        && compile default-bodies-uncounted && prove_mode default-bodies-uncounted || fails=$((fails + 1))
    stage private-trait-unwritten && mutate private-trait-unwritten src/interface_print.zrl 'if t.is_pub { self.write("pub "); }' 'if !t.is_pub { return; } self.write("pub ");' \
        && compile private-trait-unwritten && prove_mode private-trait-unwritten || fails=$((fails + 1))
    stage box-allocator-dropped && mutate box-allocator-dropped src/interface_print.zrl 'if bx.allocator != 0 as ExprId {' 'if false {' \
        && compile box-allocator-dropped && prove_mode box-allocator-dropped || fails=$((fails + 1))
    stage generic-impl-params-ignored && mutate generic-impl-params-ignored src/ast.zrl 'if imp.type_params.len > 0 as usize { return true; }' 'if false { return true; }' \
        && compile generic-impl-params-ignored && prove_mode generic-impl-params-ignored || fails=$((fails + 1))
    stage trait-impl-methods-unscanned && mutate trait-impl-methods-unscanned src/ast.zrl 'if (m.is_pub || imp.trait_name != 0 as u32)' 'if (m.is_pub)' \
        && compile trait-impl-methods-unscanned && prove_mode trait-impl-methods-unscanned || fails=$((fails + 1))
    stage private-helpers-unscanned && mutate private-helpers-unscanned src/ast.zrl 'self.scan_private_generic_helpers(target_sf, out);' 'if false { self.scan_private_generic_helpers(target_sf, out); }' \
        && compile private-helpers-unscanned && prove_mode private-helpers-unscanned || fails=$((fails + 1))
    stage specialization-bodies-unwritten && mutate specialization-bodies-unwritten src/interface_print.zrl 'let is_gen = m.type_params.len > 0 as usize || self.ast.impl_is_generic(im);' 'let is_gen = m.type_params.len > 0 as usize || im.type_params.len > 0 as usize;' \
        && compile specialization-bodies-unwritten && prove_mode specialization-bodies-unwritten || fails=$((fails + 1))
    stage struct-literal-unparenthesized && mutate struct-literal-unparenthesized src/interface_print.zrl 'if min_prec > 0 as u32 { self.write("("); }' 'if false { self.write("("); }' \
        && compile struct-literal-unparenthesized && prove_mode struct-literal-unparenthesized || fails=$((fails + 1))
    good_mode
fi
[ "$fails" -eq 0 ] && { echo "fuzz-prove: every oracle fired on its mutant and stayed quiet on the real compiler"; exit 0; }
echo "fuzz-prove: $fails proof(s) failed"; exit 1
