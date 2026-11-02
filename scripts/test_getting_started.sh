#!/bin/sh
# scripts/test_getting_started.sh — End-to-end verification of doc/getting_started.md.
#
# Asserts that every walkthrough step in doc/getting_started.md works as documented:
#   1. Stages a clean install (make install DESTDIR=<tmp> PREFIX=/usr/local).
#   2. Extracts code blocks tagged with `file=<name>` directly from the guide.
#   3. Runs "Compiling The Easy Way" (zbuild hello.zrl -> 4 modules, -o hello -> 0 modules, executes binary).
#   4. Runs "Compiling the Manual Way" (5-step pipeline: zoril -> zilc -> qbe -> as -> ld).
#   5. Runs "Creating and Using Modules" (math_utils.zrl, app.zrl, and zbuild -I lib).
#   6. Runs module aliasing (import "..." as m).
#   7. Runs "Calling C Libraries (FFI)" (compiles C object, Zoril FFI caller, links without -lc, executes binary).

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MD_FILE="$REPO_ROOT/doc/getting_started.md"

if [ ! -f "$MD_FILE" ]; then
    echo "[FAIL] test-getting-started: $MD_FILE not found"
    exit 1
fi

TMP_DIR="$(mktemp -d /tmp/zoril_getting_started_XXXXXX)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

# Extract code blocks tagged with `file=<filename>`
EXTRACT_DIR="$TMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"

awk '
/^ *```.*file=/ {
    match($0, /file=[^ \t,`]+/);
    fname = substr($0, RSTART + 5, RLENGTH - 5);
    in_file = 1;
    out = out_dir "/" fname;
    printf "" > out;
    next;
}
/^ *```/ && in_file {
    in_file = 0;
    close(out);
    next;
}
in_file {
    print > out;
}
' out_dir="$EXTRACT_DIR" "$MD_FILE"

# Stage installation
STAGE_DIR="$TMP_DIR/staged"
PREFIX="/usr/local"
make --no-print-directory -C "$REPO_ROOT" install-files DESTDIR="$STAGE_DIR" PREFIX="$PREFIX" > "$TMP_DIR/install.log" 2>&1 || {
    echo "[FAIL] test-getting-started: make install failed"
    cat "$TMP_DIR/install.log"
    exit 1
}

STAGED_BIN="$STAGE_DIR$PREFIX/bin"
STAGED_STDLIB="$STAGE_DIR$PREFIX/share/zoril/stdlib"
STAGED_RT="$STAGE_DIR$PREFIX/lib/zoril/runtime.o"

if [ ! -x "$STAGED_BIN/zoril" ] || [ ! -x "$STAGED_BIN/zilc" ] || [ ! -x "$STAGED_BIN/zbuild" ]; then
    echo "[FAIL] test-getting-started: installed binaries missing from $STAGED_BIN"
    exit 1
fi

if [ ! -f "$STAGED_RT" ]; then
    echo "[FAIL] test-getting-started: runtime.o missing at $STAGED_RT"
    exit 1
fi

if [ ! -f "$STAGED_STDLIB/core0.zrl" ]; then
    echo "[FAIL] test-getting-started: stdlib missing at $STAGED_STDLIB"
    exit 1
fi

STAGED_DOC="$STAGE_DIR$PREFIX/share/doc/zoril"
if [ ! -f "$STAGED_DOC/README.md" ] || [ ! -f "$STAGED_DOC/LICENSE" ] || [ ! -f "$STAGED_DOC/NOTICE" ] || [ ! -f "$STAGED_DOC/doc/getting_started.md" ]; then
    echo "[FAIL] test-getting-started: installed docs missing from $STAGED_DOC"
    exit 1
fi

# Verify every relative link in installed docs resolves inside STAGED_DOC or is intentionally external in repo
find "$STAGED_DOC" -type f -name "*.md" | while read -r md_file; do
    rel_md="${md_file#$STAGED_DOC/}"
    md_dir="$(dirname "$md_file")"
    repo_md_dir="$(dirname "$REPO_ROOT/$rel_md")"

    awk '{ s = $0; while (match(s, /\]\([^)]+\)/)) { print substr(s, RSTART + 2, RLENGTH - 3); s = substr(s, RSTART + RLENGTH) } }' "$md_file" | while read -r link; do
        case "$link" in
            http://*|https://*|\#*|mailto:*) continue ;;
        esac
        target="${link%%\#*}"
        [ -z "$target" ] && continue

        # Resolves within installed doc tree
        if [ -e "$md_dir/$target" ]; then
            continue
        fi

        # Check if intentionally external in repo root
        if [ -e "$repo_md_dir/$target" ]; then
            rel_repo="$(cd "$repo_md_dir" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
            rel_repo="${rel_repo#$REPO_ROOT/}"
            case "$rel_repo" in
                tests/*|bench/*|scripts/*|doc/spec/*|doc/language/*|doc/vision/*|doc/bootstrap/*|bootstrap/*|media/*|Makefile)
                    continue
                    ;;
            esac
        fi
        echo "[FAIL] test-getting-started: unresolved link in installed doc $rel_md: $link"
        exit 1
    done || exit 1
done || exit 1

export PATH="$STAGED_BIN:$PATH"

# 1. Hello World with zbuild
T1_DIR="$TMP_DIR/t1_hello"
mkdir -p "$T1_DIR"
cp "$EXTRACT_DIR/hello.zrl" "$T1_DIR/"

(
    cd "$T1_DIR"
    out1=$(zbuild hello.zrl 2>&1)
    if ! echo "$out1" | grep -q "compiled: 4 modules"; then
        echo "[FAIL] test-getting-started: zbuild hello.zrl expected 'compiled: 4 modules', got: $out1"
        exit 1
    fi
    if [ ! -x "./a.out" ]; then
        echo "[FAIL] test-getting-started: ./a.out not created"
        exit 1
    fi
    run1=$(./a.out)
    if [ "$run1" != "Hello, World!" ]; then
        echo "[FAIL] test-getting-started: unexpected ./a.out output '$run1'"
        exit 1
    fi

    out2=$(zbuild -o hello hello.zrl 2>&1)
    if ! echo "$out2" | grep -q "compiled: 0 modules"; then
        echo "[FAIL] test-getting-started: zbuild -o hello expected 'compiled: 0 modules', got: $out2"
        exit 1
    fi
    if [ ! -x "./hello" ]; then
        echo "[FAIL] test-getting-started: ./hello not created"
        exit 1
    fi
    run2=$(./hello)
    if [ "$run2" != "Hello, World!" ]; then
        echo "[FAIL] test-getting-started: unexpected ./hello output '$run2'"
        exit 1
    fi
)

# 2. Manual 5-step compilation pipeline
T2_DIR="$TMP_DIR/t2_manual"
mkdir -p "$T2_DIR"
cp "$EXTRACT_DIR/hello.zrl" "$T2_DIR/"

BACKEND="${BACKEND_BIN:-qbe}"
ASSEMBLER="${ASSEMBLER_BIN:-as}"
LINKER="${LINKER_BIN:-ld}"

(
    cd "$T2_DIR"
    zoril -I "$STAGED_STDLIB" --emit-zil -o hello.zil hello.zrl
    zilc hello.zil hello.ssa
    "$BACKEND" -o hello.s hello.ssa
    "$ASSEMBLER" -o hello.o hello.s
    "$LINKER" -o hello "$STAGED_RT" hello.o
    run=$(./hello)
    if [ "$run" != "Hello, World!" ]; then
        echo "[FAIL] test-getting-started: manual pipeline unexpected output '$run'"
        exit 1
    fi
)

# 3. Modules: math_utils.zrl and app.zrl
T3_DIR="$TMP_DIR/t3_modules"
mkdir -p "$T3_DIR"
cp "$EXTRACT_DIR/math_utils.zrl" "$EXTRACT_DIR/app.zrl" "$T3_DIR/"

(
    cd "$T3_DIR"
    zbuild -o app app.zrl >/dev/null 2>&1
    if [ ! -x "./app" ]; then
        echo "[FAIL] test-getting-started: module build failed to produce ./app"
        exit 1
    fi
    ./app
)

# 3b. Modules in lib/ subdirectory with -I lib
T3B_DIR="$TMP_DIR/t3b_modules_lib"
mkdir -p "$T3B_DIR/lib"
cp "$EXTRACT_DIR/math_utils.zrl" "$T3B_DIR/lib/"
cp "$EXTRACT_DIR/app.zrl" "$T3B_DIR/"

(
    cd "$T3B_DIR"
    zbuild -I lib -o app app.zrl >/dev/null 2>&1
    if [ ! -x "./app" ]; then
        echo "[FAIL] test-getting-started: module with -I lib failed to produce ./app"
        exit 1
    fi
    ./app
)

# 4. Module alias: import ... as m
T4_DIR="$TMP_DIR/t4_alias"
mkdir -p "$T4_DIR"
cp "$EXTRACT_DIR/math_utils.zrl" "$EXTRACT_DIR/app_alias.zrl" "$T4_DIR/"

(
    cd "$T4_DIR"
    zbuild -o app_alias app_alias.zrl >/dev/null 2>&1
    if [ ! -x "./app_alias" ]; then
        echo "[FAIL] test-getting-started: module alias failed to produce ./app_alias"
        exit 1
    fi
    ./app_alias
)

# 5. C FFI
T5_DIR="$TMP_DIR/t5_ffi"
mkdir -p "$T5_DIR"
cp "$EXTRACT_DIR/mylib.c" "$EXTRACT_DIR/app_ffi.zrl" "$EXTRACT_DIR/build_ffi.sh" "$T5_DIR/"

# Find C compiler (or skip if not found)
C_COMPILER=""
_cc_bin="${CC%% *}"
_link_cc_bin="${LINK_CC%% *}"
if [ -n "$CC" ] && command -v "$_cc_bin" >/dev/null 2>&1; then
    C_COMPILER="$CC"
elif [ -n "$LINK_CC" ] && command -v "$_link_cc_bin" >/dev/null 2>&1; then
    C_COMPILER="$LINK_CC"
elif command -v cc >/dev/null 2>&1; then
    C_COMPILER="cc"
elif command -v cproc >/dev/null 2>&1; then
    C_COMPILER="cproc"
elif command -v gcc >/dev/null 2>&1; then
    C_COMPILER="gcc"
elif command -v clang >/dev/null 2>&1; then
    C_COMPILER="clang"
fi

if [ -n "$C_COMPILER" ] && [ -n "$ASSEMBLER" ] && [ -x "$ASSEMBLER" ]; then
    case "$C_COMPILER" in
        *-B*) ;;
        *)
            _as_d="$(dirname "$ASSEMBLER")"
            case "$_as_d" in
                /*) C_COMPILER="$C_COMPILER -B$_as_d" ;;
            esac
            ;;
    esac
fi

if [ -z "$C_COMPILER" ]; then
    echo "[SKIP] test-getting-started: no C compiler found for FFI test"
else
    (
        cd "$T5_DIR"
        # Adapt extracted build script to staged installation prefix and configured C/toolchain tools
        sed -e 's|\$PREFIX|'"$STAGE_DIR$PREFIX"'|g' \
            -e "s|^cc |$C_COMPILER |g" \
            -e "s|^qbe |$BACKEND |g" \
            -e "s|^as |$ASSEMBLER |g" \
            -e "s|^ld |$LINKER |g" \
            build_ffi.sh > run_build.sh
        sh run_build.sh > build.log 2>&1 || {
            echo "[FAIL] test-getting-started: FFI build failed"
            cat build.log
            exit 1
        }
        if [ ! -x "./app_ffi" ]; then
            echo "[FAIL] test-getting-started: FFI binary ./app_ffi not found"
            exit 1
        fi
        ./app_ffi > run.log 2>&1 || {
            rc=$?
            echo "[FAIL] test-getting-started: FFI binary execution failed (exit $rc)"
            cat run.log
            exit 1
        }
    )
fi

echo "[PASS] test-getting-started: all walkthrough examples compiled and ran successfully"
exit 0
