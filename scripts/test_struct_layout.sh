#!/bin/sh
# scripts/test_struct_layout.sh — struct layout is the C layout.
#
# tests/layout/include/layout.zrl and tests/layout/include/layout.c define the same structs (mixed widths, a
# double, a pointer, nesting, trailing padding) and print sizeof, alignof and the offset of each
# field. The two outputs must match byte for byte: that is the promise of doc/spec/abi.md §2.1
# and doc/STABILITY.md, pinned against the host C compiler.
cd "$(dirname "$0")/.." || exit 2
ZBUILD=${ZBUILD_BIN:-./build/zbuild}
CC_BIN=${CC:-cc}
if ! command -v "$CC_BIN" >/dev/null 2>&1; then
    echo "[SKIP] struct-layout: no C compiler ($CC_BIN) on PATH"
    exit 0
fi
dir=build/struct-layout
rm -rf "$dir"
mkdir -p "$dir"
if ! "$CC_BIN" -std=c11 -o "$dir/layout_c" tests/layout/include/layout.c 2> "$dir/cc.log"; then
    echo "[FAIL] struct-layout: the C twin does not compile"
    sed 's/^/       /' "$dir/cc.log"
    exit 1
fi
if ! "$ZBUILD" -I stdlib=stdlib -o "$dir/layout_zrl" tests/layout/include/layout.zrl > "$dir/zbuild.log" 2>&1; then
    echo "[FAIL] struct-layout: the Zoril twin does not compile"
    sed 's/^/       /' "$dir/zbuild.log"
    exit 1
fi
"$dir/layout_c" > "$dir/c.out"
"$dir/layout_zrl" > "$dir/zrl.out"
if ! diff -u "$dir/c.out" "$dir/zrl.out" > "$dir/diff.log"; then
    echo "[FAIL] struct-layout: a Zoril struct does not have the C layout (left: C, right: Zoril)"
    sed 's/^/       /' "$dir/diff.log"
    exit 1
fi
echo "[PASS] struct-layout: $(wc -l < "$dir/c.out" | tr -d ' ') structs have the same size, alignment and field offsets as their C twins"
