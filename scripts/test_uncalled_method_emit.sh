#!/bin/sh
# scripts/test_uncalled_method_emit.sh — the emission half of the uncalled-method rule.
#
# A method nothing calls is checked (tests/error_reporting/err_uncalled_method_checks.zrl,
# err_uncalled_method_borrow.zrl, err_uncalled_method_private_call.zrl,
# err_uncalled_specialization_method_checks.zrl), and the bodies nothing calls are dropped again
# before the ZIL is written, so a whole-program build emits what its *called* code lowers to. No
# per-file test can see the second half - a body that should not be there would still assemble and
# run - so this checks the ZIL text directly.
#
# The check is its own control: the same fixture with a call to the method must name it, so a
# grep that has gone stale (a renamed mangler, a fixture that stopped compiling the way it says)
# fails here instead of passing quietly. The same pair is run for a plain `impl` and for a concrete
# specialisation (`impl Counter<i32>`): a specialisation's method nothing calls is checked too, and
# "it is not in the ZIL" would otherwise pass just as well if the body had never been checked.
#
# Usage: scripts/test_uncalled_method_emit.sh
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

. "$(dirname "$0")/env.sh"

ZORIL_CC="${ZORIL_CC:-build/zoril}"
[ -x "$ZORIL_CC" ] || { echo "error: $ZORIL_CC not found or not executable (run make)"; exit 1; }

WORK="build/tests/uncalled_method_emit"
rm -rf "$WORK"
mkdir -p "$WORK"

# The fixture: a method nothing calls, whose body is easy to spot in the ZIL (it instantiates a
# generic - `Vec::<i32>::push` - so an emitted body would leave that instance's function and type
# behind as well).
fixture() {
    cat <<'ZRL'
import "vec.zrl";
use vec::Vec;

pub struct Counter { pub n: i32, pub step: i32 }

impl Counter {
    pub fn bump(self: &Counter) -> i32 { return self.n + self.step; }

    fn never_called(self: &Counter) -> usize {
        let mut v = Vec::<i32>.new();
        v.push(self.bump());
        return v.len();
    }
}

fn main() -> i32 {
    let c = Counter { n: 1, step: 2 };
    return c.bump() - 3;
}
ZRL
}

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# ── 1. the method nothing calls is not in the ZIL ─────────────────────────────────────────────
mkdir -p "$WORK/uncalled"
fixture > "$WORK/uncalled/emit_fixture.zrl"
"$ZORIL_CC" -I stdlib=stdlib -I src --emit-zil -o "$WORK/uncalled/emit_fixture.zil" \
    "$WORK/uncalled/emit_fixture.zrl" > "$WORK/uncalled/compile.log" 2>&1 ||
    { cat "$WORK/uncalled/compile.log" >&2; fail "the fixture with an uncalled method did not compile"; }
if grep -Fq 'Counter::never_called' "$WORK/uncalled/emit_fixture.zil"; then
    fail "the ZIL names Counter::never_called, a method nothing calls (ILModule.drop_check_only_code no longer drops it?
      see Driver.check_uncalled_methods in src/driver/module.zrl)"
fi
if grep -Fq 'Vec_Ti32::push' "$WORK/uncalled/emit_fixture.zil"; then
    fail "the ZIL carries Vec_Ti32::push, which only the uncalled method instantiates: the check phase's own
      instantiations are reaching the output"
fi
echo "1. a method nothing calls is checked and not emitted  ok"

# ── 2. the control: called, the same method IS in the ZIL ─────────────────────────────────────
mkdir -p "$WORK/called"
fixture | sed 's|return c.bump() - 3;|let _ = c.never_called(); return c.bump() - 3;|' \
    > "$WORK/called/emit_fixture.zrl"
"$ZORIL_CC" -I stdlib=stdlib -I src --emit-zil -o "$WORK/called/emit_fixture.zil" \
    "$WORK/called/emit_fixture.zrl" > "$WORK/called/compile.log" 2>&1 ||
    { cat "$WORK/called/compile.log" >&2; fail "the fixture with a call to the method did not compile"; }
grep -Fq 'Counter::never_called' "$WORK/called/emit_fixture.zil" ||
    fail "the control failed: the ZIL does not name Counter::never_called even though main calls it, so
      the check above can no longer tell an emitted method from an unemitted one"
grep -Fq 'Vec_Ti32::push' "$WORK/called/emit_fixture.zil" ||
    fail "the control failed: the ZIL carries no Vec_Ti32::push even though the called method instantiates
      it, so the instantiation check above can no longer tell one that is emitted from one that is not"
echo "2. the control (a called method is emitted)  ok"

# ── 3. the checking half, from outside a per-file test ────────────────────────────────────────
mkdir -p "$WORK/broken"
# The same fixture with a field error inside the method nothing calls (`v.push(self.nope)`), reached
# by no call: only the whole-program check phase can see it.
fixture | sed 's|v.push(self.bump());|v.push(self.nope);|' > "$WORK/broken/emit_fixture.zrl"
if "$ZORIL_CC" -I stdlib=stdlib -I src --emit-zil -o "$WORK/broken/emit_fixture.zil" \
        "$WORK/broken/emit_fixture.zrl" > "$WORK/broken/compile.log" 2>&1; then
    fail "a field error inside a method nothing calls was accepted; the whole-program check phase did not
      run (Driver.check_uncalled_methods)"
fi
grep -Fq "no field 'nope'" "$WORK/broken/compile.log" ||
    { cat "$WORK/broken/compile.log" >&2; fail "the broken fixture was rejected for another reason"; }
echo "3. an error in a method nothing calls is reported  ok"

# ── 4. a concrete specialisation: checked, and its body not emitted ───────────────────────────
# The target names one type - the type's parameter is bound by the target's argument - so `Self` is
# known with no instance and the method is checked like a plain impl's (`Monomorphizer.
# impl_target_is_concrete`). The uncalled method instantiates `Vec::<i32>::push`, which a leak
# would leave behind as well.
spec_fixture() {
    cat <<'ZRL'
import "vec.zrl";
use vec::Vec;

pub struct Counter<T> { pub n: i32, pub v: T }

impl Counter<i32> {
    pub fn bump(self: &Counter<i32>) -> i32 { return self.n + self.v; }

    fn never_called(self: &Counter<i32>) -> usize {
        let mut v = Vec::<i32>.new();
        v.push(self.bump());
        return v.len();
    }
}

fn main() -> i32 {
    let c = Counter { n: 1, v: 2 };
    return c.bump() - 3;
}
ZRL
}

mkdir -p "$WORK/spec"
spec_fixture > "$WORK/spec/emit_fixture.zrl"
"$ZORIL_CC" -I stdlib=stdlib -I src --emit-zil -o "$WORK/spec/emit_fixture.zil" \
    "$WORK/spec/emit_fixture.zrl" > "$WORK/spec/compile.log" 2>&1 ||
    { cat "$WORK/spec/compile.log" >&2; fail "the specialisation fixture did not compile"; }
if grep -Fq 'Counter_Ti32::never_called' "$WORK/spec/emit_fixture.zil"; then
    fail "the ZIL names Counter_Ti32::never_called, a method of a specialisation that nothing calls
      (Monomorphizer.impl_target_is_concrete should have had it checked, and ILModule.drop_check_only_code
      dropped it again)"
fi
if grep -Fq 'Vec_Ti32::push' "$WORK/spec/emit_fixture.zil"; then
    fail "the ZIL carries Vec_Ti32::push, which only the uncalled method of the specialisation
      instantiates: the check phase's own instantiations are reaching the output"
fi
# Not being emitted is also what a body that was never checked looks like, so the same fixture with
# an error inside that body must be rejected: this is the control for the greps above.
spec_fixture | sed 's|v.push(self.bump());|v.push(self.nope);|' > "$WORK/spec/broken_fixture.zrl"
if "$ZORIL_CC" -I stdlib=stdlib -I src --emit-zil -o "$WORK/spec/broken_fixture.zil" \
        "$WORK/spec/broken_fixture.zrl" > "$WORK/spec/broken_compile.log" 2>&1; then
    fail "a field error inside a method nothing calls of a concrete specialisation was accepted; the
      whole-program check phase skipped the impl (Monomorphizer.impl_target_is_concrete)"
fi
grep -Fq "no field 'nope'" "$WORK/spec/broken_compile.log" ||
    { cat "$WORK/spec/broken_compile.log" >&2; fail "the broken specialisation fixture was rejected for another reason"; }
echo "4. a specialisation's method nothing calls is checked and not emitted  ok"

# ── 5. the control for 4: called, the same method IS in the ZIL ───────────────────────────────
mkdir -p "$WORK/spec_called"
spec_fixture | sed 's|return c.bump() - 3;|let _ = c.never_called(); return c.bump() - 3;|' \
    > "$WORK/spec_called/emit_fixture.zrl"
"$ZORIL_CC" -I stdlib=stdlib -I src --emit-zil -o "$WORK/spec_called/emit_fixture.zil" \
    "$WORK/spec_called/emit_fixture.zrl" > "$WORK/spec_called/compile.log" 2>&1 ||
    { cat "$WORK/spec_called/compile.log" >&2; fail "the specialisation fixture with a call to the method did not compile"; }
grep -Fq 'Counter_Ti32::never_called' "$WORK/spec_called/emit_fixture.zil" ||
    fail "the control failed: the ZIL does not name Counter_Ti32::never_called even though main calls it, so
      the check above can no longer tell an emitted method from an unemitted one"
grep -Fq 'Vec_Ti32::push' "$WORK/spec_called/emit_fixture.zil" ||
    fail "the control failed: the ZIL carries no Vec_Ti32::push even though the called method instantiates
      it, so the instantiation check above can no longer tell one that is emitted from one that is not"
echo "5. the control (a called specialisation method is emitted)  ok"

printf '\nPASS — a method nothing calls is checked, and only what is called is emitted.\n'
