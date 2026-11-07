#!/bin/sh
# scripts/env.sh — Central path resolution and environment setup for Zoril tooling.
#
# Source this file in any shell script to locate external compilers, tools,
# and clone repositories (QBE, Hare, Zig, Rust, etc.).
#
# To override any path locally, create config.local.sh in the repository root.

# Locate repository root
if [ -z "${ZORIL_REPO_ROOT:-}" ]; then
    if [ -f "$(pwd)/src/main.zrl" ]; then
        ZORIL_REPO_ROOT="$(pwd)"
    elif [ -f "$(dirname "$0")/../src/main.zrl" ]; then
        ZORIL_REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    elif [ -f "$(dirname "$0")/../../src/main.zrl" ]; then
        ZORIL_REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
    else
        ZORIL_REPO_ROOT="$(pwd)"
    fi
fi

# Locate external language clones directory (optional)
if [ -z "${CLONE_LANG_DIR:-}" ]; then
    if [ -d "$ZORIL_REPO_ROOT/.." ]; then
        CLONE_LANG_DIR="$(cd "$ZORIL_REPO_ROOT/.." && pwd)"
    else
        CLONE_LANG_DIR=""
    fi
fi

# Source portability helpers
if [ -f "$ZORIL_REPO_ROOT/scripts/lib/portability.sh" ]; then
    . "$ZORIL_REPO_ROOT/scripts/lib/portability.sh"
elif [ -f "$(dirname "$0")/lib/portability.sh" ]; then
    . "$(dirname "$0")/lib/portability.sh"
fi

# Locate external tools (one variable per tool, matching config.mk)
BACKEND_BIN="${BACKEND_BIN:-qbe}"
ASSEMBLER_BIN="${ASSEMBLER_BIN:-as}"
LINKER_BIN="${LINKER_BIN:-ld}"

# cc_no_libc_flags CC PROBE_DIR -- the flags CC accepts for a C object that links into the
# freestanding runtime: no libc, no stack protector, no position-independent code. GCC and clang
# default to a stack protector and PIE on some distributions, while cproc (the minimal-stack
# compiler) rejects all three flags and needs none of them. Prints the accepted set, or nothing
# when the compiler rejects it. PROBE_DIR must exist; it holds the probe source and object.
cc_no_libc_flags() {
    _cc=$1
    _probe_dir=$2
    _probe_flags="-ffreestanding -fno-stack-protector -fno-pic"
    printf 'int zoril_cc_probe(void) { return 0; }\n' > "$_probe_dir/cc-probe.c"
    # The flag string has to reach the compiler as separate arguments.
    if "$_cc" $_probe_flags -c -o "$_probe_dir/cc-probe.o" "$_probe_dir/cc-probe.c" >/dev/null 2>&1; then
        printf '%s' "$_probe_flags"
    fi
}

QBE_BIN="${QBE_BIN:-$BACKEND_BIN}"

# Locate Hare standard library path
if [ -z "${HAREPATH:-}" ]; then
    if [ -n "${CLONE_LANG_DIR:-}" ] && [ -d "$CLONE_LANG_DIR/hare" ]; then
        HAREPATH="$CLONE_LANG_DIR/hare"
    elif [ -d "$ZORIL_REPO_ROOT/../hare" ]; then
        HAREPATH="$ZORIL_REPO_ROOT/../hare"
    else
        # Hare treats a set-but-empty HAREPATH as "no search path" and fails with
        # "rt: Module not found" (it falls back to its own default only when the variable is
        # unset), so leave it unset rather than empty. Exporting "" broke every bench hare step
        # on a host with no Hare checkout (found 2026-10-10).
        unset HAREPATH
    fi
fi

# Probe --foreground support for timeout (for leaf binaries only)
if [ -z "${TIMEOUT_FOREGROUND+x}" ]; then
    TIMEOUT_FOREGROUND=$(command -v timeout >/dev/null 2>&1 && timeout --foreground 0 true 2>/dev/null && echo --foreground || true)
fi

# Optional local overrides (gitignored)
if [ -f "$ZORIL_REPO_ROOT/config.local.sh" ]; then
    . "$ZORIL_REPO_ROOT/config.local.sh"
fi

export ZORIL_REPO_ROOT
export CLONE_LANG_DIR
export BACKEND_BIN
export ASSEMBLER_BIN
export LINKER_BIN
export QBE_BIN
[ -n "${HAREPATH:-}" ] && export HAREPATH
export TIMEOUT_FOREGROUND
export PATH
