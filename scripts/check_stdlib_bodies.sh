#!/bin/sh
# scripts/check_stdlib_bodies.sh — every stdlib function body is lowered and checked somewhere.
#
# A whole-program build lowers an imported stdlib function only when the program reaches it
# (Driver.lowers_on_demand in src/driver/module.zrl), so an error in a stdlib function no test
# reaches would appear in no build at all. This compiles one root that imports every stdlib module
# and reaches none of it, with `--lower-all`: every imported function and method is lowered and
# checked, as every whole-program build did before. Generic bodies are checked where they are
# instantiated, as before.
#
# The same root without `--lower-all` must lower fewer functions: a root is always lowered in
# full, so only an import shows whether the flag still does its job.
#
# Usage: check_stdlib_bodies.sh   (ZORIL_CC, default build/zoril; ZORIL_STDLIB, default stdlib)
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 2
. scripts/lib/portability.sh

CC="${ZORIL_CC:-build/zoril}"
STDLIB="${ZORIL_STDLIB:-stdlib}"
[ -x "$CC" ] || { echo "[FAIL] stdlib-bodies: $CC is missing; run make first"; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/stdlib-bodies.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

count=0
for f in $(cd "$STDLIB" && find . -name '*.zrl' | LC_ALL=C sort); do
    count=$((count + 1))
    printf 'import "%s";\n' "${f#./}"
done > "$tmp/all.zrl"
echo 'fn main() -> i32 { return 0; }' >> "$tmp/all.zrl"
if [ "$count" -eq 0 ]; then
    echo "[FAIL] stdlib-bodies: no module found under $STDLIB"
    exit 1
fi

# lower FLAG OUT: compile the root, printing the first lines of any error.
lower() {
    if ! out=$(run_with_timeout -k 5s 60s "$CC" -I "stdlib=$STDLIB" $1 --emit-zil -o "$2" "$tmp/all.zrl" 2>&1 < /dev/null); then
        echo "[FAIL] stdlib-bodies: a root importing all $count stdlib modules does not compile${1:+ with $1}:"
        printf '%s\n' "$out" | head -n 5 | sed 's/^/       /'
        exit 1
    fi
}
lower --lower-all "$tmp/all.zil"
lower "" "$tmp/reached.zil"

# A ZIL function definition starts its line with its id: `f12: bool name(...)`.
all=$(grep -c '^f[0-9]*:' "$tmp/all.zil")
reached=$(grep -c '^f[0-9]*:' "$tmp/reached.zil")
if [ "$all" -le "$reached" ]; then
    echo "[FAIL] stdlib-bodies: --lower-all lowered $all functions, no more than the $reached a default build lowers"
    exit 1
fi
echo "[PASS] stdlib-bodies: all $count stdlib modules compile with every function lowered ($all functions; $reached without --lower-all)"
