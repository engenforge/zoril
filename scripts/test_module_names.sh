#!/bin/sh
# scripts/test_module_names.sh — which file names a module may have (doc/spec/surface_syntax.md §11).
#
# The root program may have any file name, and builds with zbuild under it. An imported module's
# file stem must be one identifier token: any other is rejected at the `import`, in the whole-program
# front end and in separate compilation, with a diagnostic that names the stem.
cd "$(dirname "$0")/.." || exit 2
. scripts/env.sh
ZORIL=${ZORIL_BIN:-./build/zoril}
ZBUILD=${ZBUILD_BIN:-./build/zbuild}
dir=build/module-names
rm -rf "$dir"
mkdir -p "$dir"
fail() { echo "[FAIL] module-names: $1"; [ -n "$2" ] && sed 's/^/       /' "$2"; exit 1; }
zb() { run_with_timeout -k 5s 120s "$ZBUILD" -I stdlib=stdlib --cache-dir "$dir/cache" "$@"; }
count=0

# name TAB root-ok TAB import-ok
names="1lead|y|n
34_drop_trait|y|n
my-mod|y|n
a.b|y|n
fn|y|n
match|y|n
sp ace|y|n
é|y|n
_x|y|y
Upper|y|y
main|y|y
vec|y|y
io|y|y
a1|y|y"

echo "$names" | while IFS='|' read -r name root_ok import_ok; do
    n=$(echo "$name" | tr ' ' '_')
    work="$dir/w_$n"
    mkdir -p "$work"
    printf 'struct P { v: i32 }\nimpl P { fn get(self: &P) -> i32 { return self.v; } }\nimpl Drop for P { fn drop(self: &mut P) { } }\nfn helper() -> i32 { let p = P { v: 3 }; return p.get(); }\nfn main() -> i32 { return helper(); }\n' > "$work/$name.zrl"
    if zb -o "$work/root_bin" "$work/$name.zrl" > "$work/root.log" 2>&1; then got=y; else got=n; fi
    [ "$got" = "$root_ok" ] || fail "'$name' as the root program: built=$got, expected $root_ok" "$work/root.log"
    if [ "$got" = y ]; then
        "$work/root_bin"; rc=$?
        [ "$rc" -eq 3 ] || fail "'$name' as the root program exited $rc, expected 3"
    fi

    mkdir -p "$work/imp"
    printf 'pub fn helper() -> i32 { return 4; }\n' > "$work/imp/$name.zrl"
    printf 'import "%s.zrl";\nfn main() -> i32 { return 0; }\n' "$name" > "$work/imp/main_prog.zrl"
    if run_with_timeout -k 5s 60s "$ZORIL" --emit-zil -o "$work/whole.zil" "$work/imp/main_prog.zrl" > "$work/whole.log" 2>&1; then got=y; else got=n; fi
    [ "$got" = "$import_ok" ] || fail "'$name' imported (whole program): accepted=$got, expected $import_ok" "$work/whole.log"
    if zb -o "$work/imp_bin" "$work/imp/main_prog.zrl" > "$work/sep.log" 2>&1; then got=y; else got=n; fi
    [ "$got" = "$import_ok" ] || fail "'$name' imported (zbuild): accepted=$got, expected $import_ok" "$work/sep.log"
    if [ "$import_ok" = n ]; then
        for log in whole sep; do
            grep -q "module name '$name' is not an identifier; rename the file" "$work/$log.log" \
                || fail "'$name' imported ($log): the diagnostic does not name the stem" "$work/$log.log"
        done
    fi
done || exit 1
# Two modules whose names the symbol mangling writes alike are refused, in both build modes, naming both
# files (A1.1): the root `1a` and an import `_1a`, the root `my-mod` and an import `my_mod`.
check_clash() { # check_clash ROOT IMPORT
    cdir="$dir/clash_$(echo "$1" | tr -c 'A-Za-z0-9\n' '_')"
    mkdir -p "$cdir"
    printf 'pub fn helper() -> i32 { return 7; }\n' > "$cdir/$2.zrl"
    stem=${2%.*}
    printf 'import "%s.zrl";\nfn helper() -> i32 { return 3; }\nfn main() -> i32 { return %s::helper() + helper(); }\n' "$2" "$2" > "$cdir/$1.zrl"
    if run_with_timeout -k 5s 60s "$ZORIL" --emit-zil -o "$cdir/w.zil" "$cdir/$1.zrl" > "$cdir/whole.log" 2>&1; then
        fail "root '$1' with import '$2': the whole-program build accepted it" "$cdir/whole.log"
    fi
    if zb -o "$cdir/bin" "$cdir/$1.zrl" > "$cdir/sep.log" 2>&1; then
        fail "root '$1' with import '$2': zbuild accepted it" "$cdir/sep.log"
    fi
    for log in whole sep; do
        grep -q "have one symbol prefix" "$cdir/$log.log" && grep -q "$1.zrl" "$cdir/$log.log" && grep -q "$2.zrl" "$cdir/$log.log" \
            || fail "root '$1' with import '$2' ($log): the diagnostic does not name both files" "$cdir/$log.log"
    done
}
check_clash 1a _1a
check_clash my-mod my_mod

echo "[PASS] module-names: any root file name builds; an imported module's name must be an identifier, in both build modes; two names with one symbol prefix are refused"
