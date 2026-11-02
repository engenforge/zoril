#!/bin/sh
# scripts/check_stage0c_minimal.sh — Gate: stage0-C minimal stack verification (cproc + mcpp/tcc).
set -u

case "$0" in
    /*) _d="${0%/*}" ;;
    */*) _d="$PWD/${0%/*}" ;;
    *) _d="$PWD" ;;
esac
REPO_ROOT="$(cd "$_d/.." 2>/dev/null && pwd)"
. "$REPO_ROOT/scripts/lib/layout.sh"

CPROC="${CPROC:-cproc}"
MINIMAL_CPP="${MINIMAL_CPP:-mcpp}"
_cpp_bin="${MINIMAL_CPP%% *}"

if ! command -v "$CPROC" >/dev/null 2>&1; then
    echo "[SKIP] stage0c-minimal: $CPROC (CPROC) not available"
    exit 0
fi

if ! command -v "$_cpp_bin" >/dev/null 2>&1; then
    echo "[SKIP] stage0c-minimal: $_cpp_bin (MINIMAL_CPP) not available"
    exit 0
fi

case "$MINIMAL_CPP" in
    *mcpp*)
        if [ ! -d /usr/lib/musl/include ] && [ ! -d /usr/include/musl ] && [ ! -d /usr/include/x86_64-linux-musl ]; then
            echo "[SKIP] stage0c-minimal: musl headers not found for mcpp"
            exit 0
        fi
        ;;
esac

if ${MAKE:-make} --no-print-directory -C "$STAGE0_DIR" test_all_minimal MINIMAL_LINK_SEED=0; then
    echo "[PASS] stage0c-minimal: minimal stack verified ($CPROC + $_cpp_bin)"
    exit 0
else
    echo "[FAIL] stage0c-minimal: minimal stack verification failed"
    exit 1
fi
