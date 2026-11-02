#!/bin/sh
# scripts/bootstrap_zoril.sh — bootstrap and build the self-hosted Zoril compiler
set -eu

case "$0" in */*) cd "${0%/*}/.." ;; *) cd .. ;; esac || exit 2
. scripts/lib/portability.sh

TARGET="${TARGET:-build/zoril}"
ZILC="${ZILC:-build/zilc}"
BACKEND_BIN="${BACKEND_BIN:-qbe}"
ASSEMBLER_BIN="${ASSEMBLER_BIN:-as}"
LINKER_BIN="${LINKER_BIN:-ld}"
BOOTSTRAP_CC_TIMEOUT="${BOOTSTRAP_CC_TIMEOUT:-600s}"
BOOTSTRAP_BUILD_TIMEOUT="${BOOTSTRAP_BUILD_TIMEOUT:-300s}"
MAKE="${MAKE:-make}"

export TARGET ZILC BACKEND_BIN ASSEMBLER_BIN LINKER_BIN BOOTSTRAP_CC_TIMEOUT BOOTSTRAP_BUILD_TIMEOUT MAKE

mkdir -p build

resolve_modern_zilc() {
    zc="$ZILC"
    if [ ! -x "$zc" ]; then
        "$MAKE" --no-print-directory build/zilc-boot || exit 1
        zc=build/zilc-boot
    fi
}

if [ -n "${ZORIL_BUILDER:-}" ]; then
    cc="$ZORIL_BUILDER"
    zc="${ZILC_BUILDER:-$ZILC}"
    if [ ! -x "$zc" ] && [ -z "$(command -v "$zc" 2>/dev/null)" ]; then
        "$MAKE" --no-print-directory build/zilc-boot || exit 1
        zc=build/zilc-boot
    fi
elif [ -x "$TARGET" ] && [ ! -L "$TARGET" ]; then
    cc="./$TARGET"
    resolve_modern_zilc
else
    echo "No build/zoril yet: building src/ with the stage1 compiler..."
    "$MAKE" --no-print-directory build/zoril-stage1 build/zilc-stage1 || exit 1
    cc=build/zoril-stage1
    zc=build/zilc-stage1
fi

echo "Building build/zoril with $cc..."
./scripts/build_zrl.sh "$TARGET" src/main.zrl -I stdlib=stdlib -I src -I build/gen \
    --compiler "$cc" --zilc "$zc" --runtime-first

if [ "$cc" = "build/zoril-stage1" ]; then
    resolve_modern_zilc
    echo "Rebuilding build/zoril with itself..."
    ./scripts/build_zrl.sh "$TARGET" src/main.zrl -I stdlib=stdlib -I src -I build/gen \
        --compiler "./$TARGET" --zilc "$zc" --runtime-first

    # $TARGET.zil is src/ as compiled by the stage1-built compiler; compile src/ once more with
    # the compiler that ZIL became. Both compilers are built from src/, so a difference means
    # the compiler miscompiles itself. Moving the binary aside keeps the next `make` from
    # taking it for a good build/zoril.
    echo "Checking the self-hosted fixpoint (src/ compiled by itself emits identical ZIL)..."
    ulimit -s 262144 2>/dev/null || true
    run_with_timeout --foreground -k 5s "$BOOTSTRAP_CC_TIMEOUT" "./$TARGET" -I stdlib=stdlib -I src -I build/gen \
        --emit-zil -o "$TARGET.fixpoint.zil" src/main.zrl > "$TARGET.fixpoint.log" 2>&1 || {
        cat "$TARGET.fixpoint.log" >&2
        mv -f "$TARGET" "$TARGET.not-fixpoint"
        echo "$TARGET failed to compile its own source; moved it to $TARGET.not-fixpoint" >&2
        exit 1
    }
    if ! cmp -s "$TARGET.zil" "$TARGET.fixpoint.zil"; then
        mv -f "$TARGET" "$TARGET.not-fixpoint"
        echo "Not a fixpoint: $TARGET.zil and $TARGET.fixpoint.zil differ; moved $TARGET to $TARGET.not-fixpoint" >&2
        exit 1
    fi
    echo "Fixpoint reached: $(wc -c < "$TARGET.zil" | tr -d ' ') bytes of ZIL, identical across two self-hosted generations"
    rm -f "$TARGET.fixpoint.zil" "$TARGET.fixpoint.log"
fi
touch build/.rebuilt
