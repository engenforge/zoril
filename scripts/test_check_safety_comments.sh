#!/bin/sh
# scripts/test_check_safety_comments.sh — tests for scripts/check_safety_comments.sh on a fixture
# directory. The gate itself runs the check over the real stdlib/.
set -eu

cd "$(dirname "$0")/.."
CHECK="$(pwd)/scripts/check_safety_comments.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

errors=0
rc=0
out=""
run() {
    rc=0
    out="$("$CHECK" "$1" 2>&1)" || rc=$?
}
expect() { # expect <name> <expected exit status> <expected output substring or ''>
    if [ "$rc" -ne "$2" ]; then
        echo "[FAIL] $1: exit $rc, expected $2"
        printf '%s\n' "$out" | sed 's/^/       /'
        errors=$((errors + 1))
    elif [ -n "$3" ] && ! printf '%s\n' "$out" | grep -qF -- "$3"; then
        echo "[FAIL] $1: output lacks '$3'"
        printf '%s\n' "$out" | sed 's/^/       /'
        errors=$((errors + 1))
    else
        echo "[PASS] $1"
    fi
}

# 1. A block with a SAFETY comment above it passes.
mkdir -p "$tmp/ok"
cat > "$tmp/ok/a.zrl" <<'EOF'
pub fn f(p: *mut u8) -> u8 {
    // SAFETY: the caller promises p points at a live byte.
    return unsafe { *p };
}

pub fn g(p: *mut u8) {
    // SAFETY: as f.
    unsafe { *p = 1; }
}
EOF
run "$tmp/ok"
expect "commented blocks pass" 0 "all 2 stdlib unsafe blocks"

# 2. A multi-line SAFETY comment counts (the block is not directly under the marker line).
mkdir -p "$tmp/multi"
cat > "$tmp/multi/a.zrl" <<'EOF'
pub fn f(p: *mut u8) -> u8 {
    // SAFETY: the caller promises p points at a live byte, and the two lines below show why
    // that is enough here.
    return unsafe { *p };
}
EOF
run "$tmp/multi"
expect "multi-line SAFETY comment passes" 0 "all 1 stdlib unsafe blocks"

# 3. An uncommented block fails, naming the file and line.
mkdir -p "$tmp/bad"
cat > "$tmp/bad/b.zrl" <<'EOF'
pub fn f(p: *mut u8) -> u8 {
    return unsafe { *p };
}
EOF
run "$tmp/bad"
expect "uncommented block fails" 1 "b.zrl:2:"

# 4. A comment that does not say SAFETY does not count.
mkdir -p "$tmp/plain"
cat > "$tmp/plain/c.zrl" <<'EOF'
pub fn f(p: *mut u8) -> u8 {
    // The caller promises p points at a live byte.
    return unsafe { *p };
}
EOF
run "$tmp/plain"
expect "a non-SAFETY comment does not count" 1 "c.zrl:3:"

# 5. A blank line between the comment and the block breaks the run.
mkdir -p "$tmp/blank"
cat > "$tmp/blank/d.zrl" <<'EOF'
pub fn f(p: *mut u8) -> u8 {
    // SAFETY: the caller promises p points at a live byte.

    return unsafe { *p };
}
EOF
run "$tmp/blank"
expect "a blank line breaks the comment run" 1 "d.zrl:4:"

# 6. Blocks inside an `unsafe fn` are checked too (its body is an unsafe context, but the
#    invariants it assumes are still worth stating).
mkdir -p "$tmp/unsafefn"
cat > "$tmp/unsafefn/e.zrl" <<'EOF'
pub unsafe fn f(p: *mut u8) -> u8 {
    return unsafe { *p };
}
EOF
run "$tmp/unsafefn"
expect "a block inside an unsafe fn is checked" 1 "e.zrl:2:"

# 7. A file with no unsafe blocks passes.
mkdir -p "$tmp/clean"
cat > "$tmp/clean/f.zrl" <<'EOF'
pub fn f(x: u64) -> u64 {
    return x + 1 as u64;
}
EOF
run "$tmp/clean"
expect "a file with no unsafe blocks passes" 0 "all 0 stdlib unsafe blocks"

if [ "$errors" -ne 0 ]; then
    echo "FAIL: $errors case(s) failed."
    exit 1
fi
echo "PASS: check_safety_comments.sh behaves as specified."
