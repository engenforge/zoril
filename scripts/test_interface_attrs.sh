#!/bin/sh
# scripts/test_interface_attrs.sh — a declared contract survives a .zri.
#
# tests/modular/iface_attrs/lib.zrl carries every attribute on the items whose bodies an interface
# keeps (generic functions, generic methods, trait methods) and a private struct and alias. The test
#   1. emits lib's interface and requires each attribute and each visibility to be written;
#   2. builds the programs beside it with zbuild (the library arrives as an interface) and with the
#      whole-program compiler, and requires the same outcome from both: the header's, `expected exit`
#      or `expected compile fail`;
#   3. requires a warning-free build of a program that imports `vec` (a warning here once came from
#      the interface's copy of `Vec::push` having lost its #[stores]), and the rejection of
#      safety probe 194 (`Vec::clone_in`'s result borrows its arena), under zbuild.
cd "$(dirname "$0")/.." || exit 2
. scripts/env.sh
ZORIL=${ZORIL_BIN:-./build/zoril}
ZBUILD=${ZBUILD_BIN:-./build/zbuild}
src=tests/modular/iface_attrs
dir=build/interface-attrs
rm -rf "$dir"
mkdir -p "$dir"
fail() { echo "[FAIL] interface-attrs: $1"; [ -n "$2" ] && sed 's/^/       /' "$2"; exit 1; }
zb() { run_with_timeout -k 5s 120s "$ZBUILD" -I stdlib=stdlib --cache-dir "$dir/cache" "$@"; }

run_with_timeout -k 5s 60s "$ZORIL" -I stdlib=stdlib -c --emit-interface -o "$dir/lib.zri" "$src/lib.zrl" > "$dir/emit.log" 2>&1 \
    || fail "lib.zrl's interface was not written" "$dir/emit.log"

# has_attr ITEM ATTR: ATTR is among the attribute lines directly above `fn ITEM`.
has_attr() {
    awk -v item="$1" -v attr="$2" '
        /^[[:space:]]*#\[/ { s = $0; sub(/^[[:space:]]*/, "", s); seen[s] = 1; next }
        $0 ~ "fn " item "[(<]" { found = (attr in seen); exit }
        { delete seen }
        END { exit !found }' "$dir/lib.zri"
}
for want in \
    "gen_must_use|#[must_use]" "gen_borrows|#[borrows(b)]" "gen_stores|#[stores(val -> dst)]" \
    "impl_must_use|#[must_use]" "impl_borrows|#[borrows(self)]" "impl_stores|#[stores(val -> self)]" \
    "area|#[must_use]" "first|#[borrows(self)]"; do
    item=${want%%|*}; attr=${want#*|}
    has_attr "$item" "$attr" || fail "the interface lost $attr on $item" "$dir/lib.zri"
done
grep -q '^pub unsafe fn gen_unsafe<' "$dir/lib.zri" || fail "the interface lost 'unsafe' on gen_unsafe" "$dir/lib.zri"
grep -q 'pub unsafe fn impl_unsafe(' "$dir/lib.zri" || fail "the interface lost 'unsafe' on impl_unsafe" "$dir/lib.zri"
grep -q '^struct Hidden ' "$dir/lib.zri" || fail "the interface wrote a private struct as public" "$dir/lib.zri"
grep -q '^type HiddenAlias ' "$dir/lib.zri" || fail "the interface wrote a private alias as public" "$dir/lib.zri"
grep -q '^#\[must_use\]$' "$dir/lib.zri" && grep -A1 '^#\[must_use\]$' "$dir/lib.zri" | grep -q '^pub struct Token' \
    || fail "the interface lost #[must_use] on struct Token" "$dir/lib.zri"

for prog in "$src"/accept_*.zrl "$src"/reject_*.zrl "$src"/private_*.zrl; do
    [ -f "$prog" ] || continue
    name=$(basename "$prog" .zrl)
    expect_fail=0; grep -q '^// expected compile fail' "$prog" && expect_fail=1
    if run_with_timeout -k 5s 60s "$ZORIL" -I stdlib=stdlib --emit-zil -o "$dir/$name.zil" "$prog" > "$dir/$name.whole.log" 2>&1; then
        [ "$expect_fail" -eq 0 ] || fail "$name: the whole-program build accepted it" "$dir/$name.whole.log"
    else
        [ "$expect_fail" -eq 1 ] || fail "$name: the whole-program build rejected it" "$dir/$name.whole.log"
    fi
    if zb -o "$dir/$name.bin" "$prog" > "$dir/$name.zb.log" 2>&1; then
        if grep -q "warning:" "$dir/$name.zb.log" && ! grep -q "warning:" "$dir/$name.whole.log"; then
            fail "$name: zbuild warns where the whole-program build does not" "$dir/$name.zb.log"
        fi
        [ "$expect_fail" -eq 0 ] || fail "$name: zbuild accepted it" "$dir/$name.zb.log"
        want=$(sed -n 's|^// expected exit \([0-9]*\).*|\1|p' "$prog" | head -1)
        "$dir/$name.bin"; rc=$?
        [ "$rc" -eq "${want:-0}" ] || fail "$name: zbuild's program exited $rc, expected ${want:-0}"
    else
        [ "$expect_fail" -eq 1 ] || fail "$name: zbuild rejected it" "$dir/$name.zb.log"
    fi
done

zb -o "$dir/vec_string" corpus/zrl/33_vec_and_string.zrl > "$dir/vs.log" 2>&1 || fail "33_vec_and_string does not build under zbuild" "$dir/vs.log"
if grep -q 'warning:' "$dir/vs.log"; then fail "33_vec_and_string warns under zbuild" "$dir/vs.log"; fi

probe=bench/safety_matrix/probes/194_vec_clone_in_survive_arena_reset.zrl
if zb -o "$dir/p194" "$probe" > "$dir/p194.log" 2>&1; then fail "probe 194 is accepted under zbuild" "$dir/p194.log"; fi

# 4. Every attribute the standard library writes on a generic function, a method of a generic impl or a
# trait method is in that module's interface (the Vec::clone_in hole was this loss).
attrs_of() { # SOURCE -> "item|attribute" lines
    awk '
        /^impl</ { gen = 1 }
        /^trait|^pub trait/ { gen = 1 }
        /^}/ { gen = 0 }
        /^[[:space:]]*#\[(borrows|stores|must_use)/ { s = $0; sub(/^[[:space:]]*/, "", s); attrs[n++] = s; next }
        /^[[:space:]]*(pub )?(unsafe )?fn / {
            name = $0; sub(/^[[:space:]]*(pub )?(unsafe )?fn /, "", name); sub(/[(<].*/, "", name)
            if (n > 0 && (gen || $0 ~ ("fn " name "<"))) for (i = 0; i < n; i++) print name "|" attrs[i]
        }
        { n = 0 }' "$1"
}
has_attr_in() { # ZRI ITEM ATTR
    awk -v item="$2" -v attr="$3" '
        /^[[:space:]]*#\[/ { s = $0; sub(/^[[:space:]]*/, "", s); seen[s] = 1; next }
        $0 ~ ("fn " item "[(<]") { if (attr in seen) found = 1 }
        { delete seen }
        END { exit !found }' "$1"
}
checked=0
for mod in stdlib/*.zrl stdlib/os/*.zrl; do
    [ -f "$mod" ] || continue
    attrs_of "$mod" > "$dir/attrs.txt"
    [ -s "$dir/attrs.txt" ] || continue
    zri="$dir/$(basename "$mod" .zrl).zri"
    run_with_timeout -k 5s 60s "$ZORIL" -I stdlib=stdlib -c --emit-interface -o "$zri" "$mod" > "$dir/std.log" 2>&1 || fail "$mod: no interface" "$dir/std.log"
    while IFS='|' read -r item attr; do
        grep -q "fn $item[(<]" "$zri" || continue
        has_attr_in "$zri" "$item" "$attr" || fail "$mod: the interface lost $attr on $item" "$zri"
        checked=$((checked + 1))
    done < "$dir/attrs.txt"
done
[ "$checked" -gt 0 ] || fail "no standard-library attribute was checked: the extraction is broken"

# 5. What an interface says about private items and exports (A7): the diagnostics a whole-program build
# gives, from the repository root as the runner builds them.
for t in err_method_in_two_modules err_private_method_cross_module err_cross_module_private_fn \
         err_private_assoc_fn_cross_module err_private_assoc_const_cross_module err_extern_export_duplicate \
         err_extern_export_siblings err_method_twice_siblings; do
    tf="tests/error_reporting/$t.zrl"
    if zb -I tests -I tests/include -o "$dir/$t.bin" "$tf" > "$dir/$t.log" 2>&1; then
        fail "$t: zbuild accepted it" "$dir/$t.log"
    fi
    grep '^// EXPECT:' "$tf" | sed 's|^// EXPECT: *||' | while IFS= read -r want; do
        grep -qF -- "$want" "$dir/$t.log" || { echo "[FAIL] interface-attrs: $t: zbuild did not print: $want"; sed 's/^/       /' "$dir/$t.log"; exit 1; }
    done || exit 1
done

echo "[PASS] interface-attrs: attributes, visibility and unsafe survive a .zri; every generic or trait attribute of the standard library is in its interface; zbuild and the whole-program build agree on the fixtures and probe 194; private items, duplicate methods and exports are diagnosed as whole-program does"
