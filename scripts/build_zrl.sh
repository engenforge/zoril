#!/bin/sh
# scripts/build_zrl.sh — Compile and link a Zoril binary through the 5-step pipeline.
#
# Usage:
#   scripts/build_zrl.sh OUT MAIN.zrl [-I DIR ...] [--compiler CC] [--zilc ZC] \
#                        [--runtime OBJ] [--runtime-first] [--toolchain-stamp]
#
# Pipeline:
#   1. $COMPILER $INCLUDES --emit-zil -o $STEM.zil $MAIN  (log: $STEM.compile.log)
#   2. $ZILC_BIN $STEM.zil $STEM.ssa                      (log: $STEM.zilc.log)
#   3. $BACKEND_BIN -o $STEM.s $STEM.ssa                  (log: $STEM.backend.log)
#   4. $ASSEMBLER_BIN -o $STEM.o $STEM.s                  (log: $STEM.as.log, with GAS filter)
#   5. $LINKER_BIN -o $STEM.tmp [$RUNTIME] $STEM.o ...    (log: $STEM.ld.log)
#      mv -f $STEM.tmp $OUT && chmod +x $OUT
#
# Applies ulimit -s 262144, step timeouts, and GAS warning verification.

set -eu

case "$0" in */*) cd "${0%/*}/.." ;; *) cd .. ;; esac || exit 2
. scripts/lib/portability.sh

# Toolchain defaults from environment
BACKEND_BIN="${BACKEND_BIN:-qbe}"
ASSEMBLER_BIN="${ASSEMBLER_BIN:-as}"
LINKER_BIN="${LINKER_BIN:-ld}"
BOOTSTRAP_CC_TIMEOUT="${BOOTSTRAP_CC_TIMEOUT:-600s}"
BOOTSTRAP_BUILD_TIMEOUT="${BOOTSTRAP_BUILD_TIMEOUT:-300s}"
MAKE="${MAKE:-make}"

OUT=""
MAIN=""
INCLUDES=""
COMPILER=""
ZILC_BIN=""
RUNTIME=""
RUNTIME_FIRST=0
TOOLCHAIN_STAMP=0

show_help() {
    cat << 'EOF'
Usage: scripts/build_zrl.sh OUT MAIN.zrl [-I DIR ...] [options]

Arguments:
  OUT                 Destination path for the compiled binary
  MAIN.zrl            Root Zoril source file

Options:
  -I DIR              Add include directory (may be repeated)
  --compiler CC       Zoril compiler binary (default: $BOOTSTRAP_CC or ./build/zoril)
  --zilc ZC           ZIL compiler binary (default: resolved ./build/zilc or ./build/zilc-boot)
  --runtime OBJ       Runtime object file (default: build/runtime.o)
  --runtime-first     Link runtime object first (required for build/zoril)
  --toolchain-stamp   Write $OUT.toolchain metadata stamp and touch build/.rebuilt
  -h, --help          Show this help message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -I)
            [ $# -ge 2 ] || { echo "Error: -I requires an argument" >&2; exit 2; }
            INCLUDES="$INCLUDES -I $2"
            shift 2
            ;;
        -I*)
            INCLUDES="$INCLUDES $1"
            shift
            ;;
        --compiler)
            [ $# -ge 2 ] || { echo "Error: --compiler requires an argument" >&2; exit 2; }
            COMPILER="$2"
            shift 2
            ;;
        --compiler=*)
            COMPILER="${1#*=}"
            shift
            ;;
        --zilc)
            [ $# -ge 2 ] || { echo "Error: --zilc requires an argument" >&2; exit 2; }
            ZILC_BIN="$2"
            shift 2
            ;;
        --zilc=*)
            ZILC_BIN="${1#*=}"
            shift
            ;;
        --runtime)
            [ $# -ge 2 ] || { echo "Error: --runtime requires an argument" >&2; exit 2; }
            RUNTIME="$2"
            shift 2
            ;;
        --runtime=*)
            RUNTIME="${1#*=}"
            shift
            ;;
        --runtime-first)
            RUNTIME_FIRST=1
            shift
            ;;
        --toolchain-stamp)
            TOOLCHAIN_STAMP=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "Error: unknown option $1" >&2
            exit 2
            ;;
        *)
            if [ -z "$OUT" ]; then
                OUT="$1"
            elif [ -z "$MAIN" ]; then
                MAIN="$1"
            else
                echo "Error: unexpected argument: $1" >&2
                exit 2
            fi
            shift
            ;;
    esac
done

if [ -z "$OUT" ] || [ -z "$MAIN" ]; then
    show_help >&2
    exit 2
fi

# Derive stem and ensure destination directory exists
STEM="$OUT"
case "$STEM" in
    */*) mkdir -p "${STEM%/*}" ;;
esac

# Resolve defaults
if [ -z "$RUNTIME" ]; then
    RUNTIME="${RT_HOST:-build/runtime.o}"
fi

if [ -z "$COMPILER" ]; then
    if [ -n "${BOOTSTRAP_CC:-}" ]; then
        COMPILER="$BOOTSTRAP_CC"
    elif [ -n "${TARGET:-}" ]; then
        COMPILER="$TARGET"
    else
        COMPILER="./build/zoril"
    fi
fi

if [ -z "$ZILC_BIN" ]; then
    if [ -n "${ZILC_BUILDER:-}" ] && [ ! -x ./build/zilc ]; then
        ZILC_BIN="$ZILC_BUILDER"
    elif [ "${SYSTEM_ZORIL:-0}" = "1" ] && [ ! -x ./build/zilc ]; then
        ZILC_BIN=zilc
    elif [ -x ./build/zilc ]; then
        ZILC_BIN=./build/zilc
    elif [ -x ./build/zilc-boot ]; then
        echo "using the bootstrap zilc (build/zilc-boot)..."
        ZILC_BIN=./build/zilc-boot
    else
        echo "building a bootstrap zilc (build/zilc-boot) with the stage1 front end..."
        "$MAKE" --no-print-directory build/zilc-boot || exit 1
        ZILC_BIN=./build/zilc-boot
    fi
fi

# Enforce chain-built stack requirements
ulimit -s 262144 2>/dev/null || true

# Step 1: zoril front-end compilation to ZIL
run_with_timeout --foreground -k 5s "$BOOTSTRAP_CC_TIMEOUT" "$COMPILER" $INCLUDES --emit-zil -o "$STEM.zil" "$MAIN" > "$STEM.compile.log" 2>&1 || {
    cat "$STEM.compile.log" >&2
    echo "$OUT: compilation failed" >&2
    exit 1
}
cp -f "$STEM.compile.log" "$STEM.log" 2>/dev/null || true

# Step 2: zilc translation from ZIL to QBE IL (.ssa)
run_with_timeout --foreground -k 5s "$BOOTSTRAP_BUILD_TIMEOUT" "$ZILC_BIN" "$STEM.zil" "$STEM.ssa" > "$STEM.zilc.log" 2>&1 || {
    cat "$STEM.zilc.log" >&2
    echo "$OUT: zilc failed" >&2
    exit 1
}

# Step 3: backend code generation (.ssa to .s)
run_with_timeout --foreground -k 5s "$BOOTSTRAP_BUILD_TIMEOUT" "$BACKEND_BIN" -o "$STEM.s" "$STEM.ssa" > "$STEM.backend.log" 2>&1 || {
    cat "$STEM.backend.log" >&2
    echo "$OUT: backend failed" >&2
    exit 1
}

# Step 4: assembly (.s to .o) with strict GAS warning filter
run_with_timeout --foreground -k 5s 60s "$ASSEMBLER_BIN" -o "$STEM.o" "$STEM.s" > "$STEM.as.log" 2>&1 || {
    cat "$STEM.as.log" >&2
    echo "$OUT: assembler failed" >&2
    exit 1
}

if [ -s "$STEM.as.log" ]; then
    _unexp=$(grep -v "Assembler messages:" "$STEM.as.log" | grep -v "Warning: 0x8000000000000000 shortened to 0x0" || true)
    if [ -n "$_unexp" ]; then
        cat "$STEM.as.log" >&2
        echo "$OUT: unexpected assembler warning" >&2
        exit 1
    fi
    _lines=$(sed -n 's/.*:\([0-9][0-9]*\): Warning: 0x8000000000000000 shortened to 0x0/\1/p' "$STEM.as.log")
    for _ln in $_lines; do
        _next=$(sed -n "$((_ln + 1))p" "$STEM.s" 2>/dev/null || true)
        case "$_next" in
            *">>32"*) ;;
            *)
                cat "$STEM.as.log" >&2
                echo "$OUT: unverified assembler warning" >&2
                exit 1
                ;;
        esac
    done
fi

# Step 5: linking (.o to executable binary)
if [ "$RUNTIME_FIRST" -eq 1 ]; then
    run_with_timeout --foreground -k 5s 30s "$LINKER_BIN" -o "$STEM.tmp" "$RUNTIME" "$STEM.o" > "$STEM.ld.log" 2>&1 || {
        cat "$STEM.ld.log" >&2
        echo "$OUT: linker failed" >&2
        exit 1
    }
else
    run_with_timeout --foreground -k 5s 30s "$LINKER_BIN" -o "$STEM.tmp" "$STEM.o" "$RUNTIME" > "$STEM.ld.log" 2>&1 || {
        cat "$STEM.ld.log" >&2
        echo "$OUT: linker failed" >&2
        exit 1
    }
fi

rm -f "$OUT"
mv "$STEM.tmp" "$OUT"
chmod +x "$OUT"

if [ "$TOOLCHAIN_STAMP" -eq 1 ]; then
    _backend_base="${BACKEND_BIN##*/}"
    _assembler_base="${ASSEMBLER_BIN##*/}"
    printf '%s+%s\n' "$_backend_base" "$_assembler_base" > "$OUT.toolchain"
    touch build/.rebuilt
fi
