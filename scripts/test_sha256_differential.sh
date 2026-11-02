#!/bin/sh
# scripts/test_sha256_differential.sh — stdlib/sha256 must agree with the host's hashing tool
#
# Its artefacts live in a directory of their own per invocation. Two consumers run this script in
# the same `make test`: the stdlib group's `sha256-differential` scenario, and the
# `toolchain-offpath` gate, which runs it with qbe off PATH. A shared build directory let one
# consumer's qbe read an SSA the other was still writing - qbe reported "label, instruction or jump
# expected" part-way through the file, which is exactly what a truncated SSA produces. The rebuild
# this costs is about a tenth of a second.
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$REPO_ROOT/scripts/lib/portability.sh" ]; then
    . "$REPO_ROOT/scripts/lib/portability.sh"
fi
BACKEND_BIN="${BACKEND_BIN:-qbe}"
ASSEMBLER_BIN="${ASSEMBLER_BIN:-as}"
LINKER_BIN="${LINKER_BIN:-ld}"

# TR_WORK is the runner's work root and may be relative to the repository (its default is
# build/tests); the artefacts of this run go under it, named by the process, so no two runs share a
# file whichever order they start in.
BUILD_ROOT="${TR_WORK:-$REPO_ROOT/build/tests}"
case "$BUILD_ROOT" in
    /*) ;;
    *) BUILD_ROOT="$REPO_ROOT/$BUILD_ROOT" ;;
esac
BUILD_DIR="$BUILD_ROOT/sha256-differential.$$"
mkdir -p "$BUILD_DIR"
passed=0
cleanup() { if [ "$passed" -eq 1 ]; then rm -rf "$BUILD_DIR"; fi; return 0; }
trap cleanup EXIT INT TERM

cd "$REPO_ROOT"

echo "=== Differential testing stdlib/sha256 against sha256sum ==="

CLI_SRC="$REPO_ROOT/tests/stdlib/sha256_differential_cli.zrl"
CLI_BIN="$BUILD_DIR/sha256_differential_cli"

"$REPO_ROOT/build/zoril" -I "$REPO_ROOT/stdlib" -I "$REPO_ROOT/tests/stdlib" -I "$REPO_ROOT/src" --emit-zil -o "$BUILD_DIR/sha256_diff.zil" "$CLI_SRC"
"$REPO_ROOT/build/zilc" "$BUILD_DIR/sha256_diff.zil" "$BUILD_DIR/sha256_diff.ssa"
"$BACKEND_BIN" -o "$BUILD_DIR/sha256_diff.s" "$BUILD_DIR/sha256_diff.ssa"
"$ASSEMBLER_BIN" -o "$BUILD_DIR/sha256_diff.o" "$BUILD_DIR/sha256_diff.s"
"$LINKER_BIN" -o "$CLI_BIN" "$BUILD_DIR/sha256_diff.o" "$REPO_ROOT/build/runtime.o"

TMP_ZORIL="$BUILD_DIR/diff_zoril.txt"
TMP_HOST="$BUILD_DIR/diff_host.txt"

FILES=$(find "stdlib" -name "*.zrl" | sort)
COUNT=$(echo "$FILES" | wc -w)

"$CLI_BIN" $FILES > "$TMP_ZORIL"
sha256_of $FILES > "$TMP_HOST"

if diff -u "$TMP_ZORIL" "$TMP_HOST"; then
    echo "[PASS] stdlib/sha256 matches sha256sum for all $COUNT files in stdlib/"
    passed=1
    exit 0
else
    echo "[FAIL] stdlib/sha256 mismatch against sha256sum"
    echo "       build and outputs kept in $BUILD_DIR"
    exit 1
fi
