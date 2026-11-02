#!/bin/sh
# scripts/test_readme_snippets.sh — Test that all code snippets in README.md
# compile and run as expected for both Zoril and Rust.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README_PATH="$REPO_ROOT/README.md"

if [ ! -f "$README_PATH" ]; then
    echo "[FAIL] readme-snippets: README.md not found at $README_PATH"
    exit 1
fi

TMP_DIR="$(mktemp -d /tmp/zoril_readme_test_XXXXXX)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

ZORIL_CODE="$TMP_DIR/test_readme.zrl"
RUST_CODE="$TMP_DIR/test_readme.rs"

# Extract Zoril snippets
awk '
BEGIN { in_zoril = 0 }
/^```zoril/ { in_zoril = 1; next }
/^```/ && in_zoril { in_zoril = 0; print ""; next }
in_zoril { print }
' "$README_PATH" > "$ZORIL_CODE"

if [ ! -s "$ZORIL_CODE" ]; then
    echo "[FAIL] readme-snippets: no zoril code blocks found in README.md"
    exit 1
fi

cat << 'EOF' >> "$ZORIL_CODE"

fn main() -> i32 {
    let mut storage: [u64; 7] = [0, 0, 0, 0, 0, 0, 0];
    let fib = FibSequence.compute(&mut storage);
    if fib.values.len != 7 as usize { return 1; }
    if fib.last().unwrap() != 8 as u64 { return 2; }
    if fib.values[0] != 0 as u64 { return 3; }
    if fib.values[6] != 8 as u64 { return 4; }
    let mut no_storage: [u64; 0] = [0; 0];
    if FibSequence.compute(&mut no_storage).last().is_some() { return 5; }

    let mut header: [u8; 8] = [0, 0, 0, 0, 0, 0, 0, 0];
    let n = match read_header("README.md", &mut header) {
        Ok(n) => n,
        Err(_) => { return 6; },
    };
    if n != 8 as u64 || header[0] != 33 as u8 { return 7; } // README.md starts with "![Zoril"
    if read_header("no/such/file", &mut header).is_ok() { return 8; }

    return 0;
}
EOF

# Toolchain paths: prioritize ZORIL_CC as exported by test harness
COMPILER="${ZORIL_CC:-${ZORIL_BIN:-$REPO_ROOT/build/zoril}}"
ZILC="${ZILC_BIN:-$REPO_ROOT/build/zilc}"
RUNTIME="${RT_HOST:-${TR_RUNTIME:-$REPO_ROOT/build/runtime.o}}"
STDLIB="${STDLIB_DIR:-${ZORIL_STDLIB:-$REPO_ROOT/stdlib}}"
BACKEND="${BACKEND_BIN:-qbe}"
ASSEMBLER="${ASSEMBLER_BIN:-as}"
LINKER="${LINKER_BIN:-ld}"
TIMEOUT_DUR="${TR_TIMEOUT:-${TIMEOUT_SECS:-30}}"
case "$TIMEOUT_DUR" in
    *[smhd]) ;;
    *) TIMEOUT_DUR="${TIMEOUT_DUR}s" ;;
esac

TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout $TIMEOUT_DUR"
fi

ZIL_PATH="$TMP_DIR/test_readme.zil"
SSA_PATH="$TMP_DIR/test_readme.ssa"
S_PATH="$TMP_DIR/test_readme.s"
O_PATH="$TMP_DIR/test_readme.o"
BIN_PATH="$TMP_DIR/test_readme"

zoril_ok=1
if ! $TIMEOUT_CMD "$COMPILER" -I "stdlib=$STDLIB" -I "$TMP_DIR" --emit-zil -o "$ZIL_PATH" "$ZORIL_CODE" > "$TMP_DIR/zoril.log" 2>&1; then
    echo "[FAIL] readme-snippets: Zoril compilation failed:"
    cat "$TMP_DIR/zoril.log"
    zoril_ok=0
elif ! $TIMEOUT_CMD "$ZILC" "$ZIL_PATH" "$SSA_PATH" > "$TMP_DIR/zilc.log" 2>&1; then
    echo "[FAIL] readme-snippets: zilc lowering failed:"
    cat "$TMP_DIR/zilc.log"
    zoril_ok=0
elif ! $TIMEOUT_CMD "$BACKEND" -o "$S_PATH" "$SSA_PATH" > "$TMP_DIR/backend.log" 2>&1; then
    echo "[FAIL] readme-snippets: backend failed:"
    cat "$TMP_DIR/backend.log"
    zoril_ok=0
elif ! $TIMEOUT_CMD "$ASSEMBLER" -o "$O_PATH" "$S_PATH" > "$TMP_DIR/assembler.log" 2>&1; then
    echo "[FAIL] readme-snippets: assembler failed:"
    cat "$TMP_DIR/assembler.log"
    zoril_ok=0
elif ! $TIMEOUT_CMD "$LINKER" -o "$BIN_PATH" "$RUNTIME" "$O_PATH" > "$TMP_DIR/linker.log" 2>&1; then
    echo "[FAIL] readme-snippets: linker failed:"
    cat "$TMP_DIR/linker.log"
    zoril_ok=0
else
    set +e
    (cd "$REPO_ROOT" && $TIMEOUT_CMD "$BIN_PATH") > "$TMP_DIR/run.log" 2>&1
    rc=$?
    set -e
    if [ $rc -ne 0 ]; then
        echo "[FAIL] readme-snippets: Zoril executable returned exit code $rc"
        cat "$TMP_DIR/run.log"
        zoril_ok=0
    else
        echo "[PASS] readme-snippets: Zoril Fibonacci and defer snippets compiled and passed"
    fi
fi

# Extract Rust snippets
awk '
BEGIN { in_rust = 0 }
/^```rust/ { in_rust = 1; next }
/^```/ && in_rust { in_rust = 0; print ""; next }
in_rust { print }
' "$README_PATH" > "$RUST_CODE"

rust_ok=1
if [ ! -s "$RUST_CODE" ]; then
    echo "[FAIL] readme-snippets: no rust code blocks found in README.md"
    rust_ok=0
elif ! command -v "${RUSTC_BIN:-rustc}" >/dev/null 2>&1; then
    echo "[SKIP] readme-snippets: rustc compiler not found on PATH"
else
    cat << 'EOF' >> "$RUST_CODE"

fn main() {
    let mut storage: [u64; 7] = [0; 7];
    let fib = FibSequence::compute(&mut storage);
    assert_eq!(fib.values.len(), 7);
    assert_eq!(fib.last(), Some(8));
    assert_eq!(fib.values[0], 0);
    assert_eq!(fib.values[6], 8);
}
EOF

    RUST_BIN="$TMP_DIR/test_readme_rs"
    RUSTC="${RUSTC_BIN:-rustc}"
    _rustc_link_args=""
    if [ -n "$LINKER" ] && [ -x "$LINKER" ]; then
        _rustc_link_args="-C link-arg=-B$(dirname "$LINKER")"
    fi
    if ! $TIMEOUT_CMD "$RUSTC" $_rustc_link_args "$RUST_CODE" -o "$RUST_BIN" > "$TMP_DIR/rustc.log" 2>&1; then
        if grep -q "cannot find 'ld'" "$TMP_DIR/rustc.log" || grep -q "error: linker \`.*\` not found" "$TMP_DIR/rustc.log"; then
            echo "[SKIP] readme-snippets: rustc linker not available"
        else
            echo "[FAIL] readme-snippets: Rust compilation failed:"
            cat "$TMP_DIR/rustc.log"
            rust_ok=0
        fi
    else
        set +e
        $TIMEOUT_CMD "$RUST_BIN" > "$TMP_DIR/rust_run.log" 2>&1
        rc=$?
        set -e
        if [ $rc -ne 0 ]; then
            echo "[FAIL] readme-snippets: Rust executable returned exit code $rc"
            cat "$TMP_DIR/rust_run.log"
            rust_ok=0
        else
            echo "[PASS] readme-snippets: Rust Fibonacci snippet compiled and passed"
        fi
    fi
fi

if [ $zoril_ok -eq 1 ] && [ $rust_ok -eq 1 ]; then
    exit 0
else
    exit 1
fi
