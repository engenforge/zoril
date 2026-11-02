#!/bin/sh
# scripts/test_qbe_arg_order.sh — QBE is given its options before the input file.
#
# QBE reads its options with the C library's getopt. glibc's reorders arguments, so `qbe in.ssa -o out.s`
# works there; musl's (Alpine) stops at the first non-option and reads `-o` as a second input file.
# POSIXLY_CORRECT=1 makes glibc stop the same way, so a QBE run under it fails on the order a musl host
# would reject. zbuild builds hello world with such a QBE; no shell script may put -o after the input.
cd "$(dirname "$0")/.." || exit 2
. scripts/env.sh
ZBUILD=${ZBUILD_BIN:-./build/zbuild}
dir=build/qbe-arg-order
rm -rf "$dir"
mkdir -p "$dir"
fail() { echo "[FAIL] qbe-arg-order: $1"; [ -n "$2" ] && sed 's/^/       /' "$2"; exit 1; }

qbe=$(command -v "${BACKEND_BIN:-qbe}") || { echo "[SKIP] qbe-arg-order: no qbe"; exit 0; }
printf '#!/bin/sh\nPOSIXLY_CORRECT=1 exec "%s" "$@"\n' "$qbe" > "$dir/qbe_posix"
chmod +x "$dir/qbe_posix"

# The wrapper must reject the wrong order, or the build below proves nothing.
printf 'export function w $main() {\n@s\n\tret 0\n}\n' > "$dir/t.ssa"
if "$dir/qbe_posix" "$dir/t.ssa" -o "$dir/t.s" > /dev/null 2>&1; then
    echo "[SKIP] qbe-arg-order: this QBE accepts options after the input even under POSIXLY_CORRECT"
    exit 0
fi

cat > "$dir/hello.zrl" << 'ZRL'
fn main() -> i32 {
    return 0;
}
ZRL
if ! run_with_timeout -k 5s 120s "$ZBUILD" -I stdlib=stdlib --cache-dir "$dir/cache" --qbe "$dir/qbe_posix" -o "$dir/hello" "$dir/hello.zrl" > "$dir/build.log" 2>&1; then
    fail "zbuild did not build a program with a QBE that reads its options POSIX-style" "$dir/build.log"
fi
"$dir/hello" || fail "the program built with the POSIX-style QBE did not run"

# A shell script that runs QBE with an option after the input fails on a musl host.
bad=$(grep -nE '(BACKEND_BIN|QBE_BIN|\$QBE|\$\{QBE\})"? +"?[^-" ][^ ]* +-o ' scripts/*.sh | grep -v 'test_qbe_arg_order.sh' || true)
[ -z "$bad" ] || fail "QBE is given an option after its input file:
$bad"
echo "[PASS] qbe-arg-order: zbuild builds with a POSIX-style QBE, and no script puts -o after the input"
