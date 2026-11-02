#!/bin/sh
# scripts/repro-check.sh — Rebuild the toolchain from scratch, twice, and check the two builds agree
#
# Rebuilds the release via the Makefile in two isolated directories and requires identical zoril, zilc,
# zbuild and runtime.o: the build does not depend on the directory it runs in. With --hashes FILE the first
# build is also compared with a published list of binary hashes. That match holds only on a host with the
# same C library, QBE, assembler and linker as the release host (doc/reproducible_builds.md), so a
# mismatch is reported together with this host's toolchain, not as a defect of the release.
#
# Usage:
#   scripts/repro-check.sh                # two builds must agree
#   scripts/repro-check.sh --keep         # keep rebuilt artifacts in build/repro-check
#   scripts/repro-check.sh --hashes FILE  # also compare the first build with a published hashes file
#   scripts/repro-check.sh --work-dir DIR # use custom work directory
#
# Exit 0 = the builds agree (and match FILE, if given). Non-zero = mismatch or build failure.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$REPO_ROOT"
. "$REPO_ROOT/scripts/lib/layout.sh"
. "$REPO_ROOT/scripts/lib/portability.sh"

HASHES_FILE="${HASHES_FILE:-}"
WORK_DIR="${WORK_DIR:-$REPO_ROOT/build/repro-check}"
KEEP="${KEEP:-0}"

# 1. Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --keep)
            KEEP=1
            shift
            ;;
        --hashes)
            if [ $# -lt 2 ]; then echo "Error: --hashes requires an argument" >&2; exit 2; fi
            HASHES_FILE="$2"
            shift 2
            ;;
        --hashes=*)
            HASHES_FILE="${1#*=}"
            shift
            ;;
        --work-dir)
            if [ $# -lt 2 ]; then echo "Error: --work-dir requires an argument" >&2; exit 2; fi
            WORK_DIR="$2"
            shift 2
            ;;
        --work-dir=*)
            WORK_DIR="${1#*=}"
            shift
            ;;
        -h|--help)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

# 2. Hardened safety check on WORK_DIR
_resolve_abs_path() {
    _p="$1"
    if command -v realpath >/dev/null 2>&1; then
        _res="$(realpath -m "$_p" 2>/dev/null)" && [ -n "$_res" ] && { echo "$_res"; return 0; }
    fi
    if command -v readlink >/dev/null 2>&1; then
        _res="$(readlink -m "$_p" 2>/dev/null)" && [ -n "$_res" ] && { echo "$_res"; return 0; }
    fi
    _cur="$_p"
    _tail=""
    case "$_cur" in /*) ;; *) _cur="$PWD/$_cur" ;; esac
    while [ ! -d "$_cur" ] && [ "$_cur" != "/" ] && [ "$_cur" != "." ]; do
        _base="$(basename "$_cur")"
        _tail="$_base${_tail:+/$_tail}"
        _cur="$(dirname "$_cur")"
    done
    _abs_base="$(cd "$_cur" 2>/dev/null && pwd -P)" || _abs_base=""
    echo "$_abs_base${_tail:+/$_tail}"
}

_abs_work="$(_resolve_abs_path "$WORK_DIR")"
if [ -z "$_abs_work" ] || [ "$_abs_work" = "/" ] || [ "$_abs_work" = "." ] || [ "$_abs_work" = ".." ]; then
    echo "Error: dangerous or invalid WORK_DIR: '$WORK_DIR'" >&2
    exit 1
fi

case "$_abs_work" in
    /*/*) ;;
    *) echo "Error: dangerous WORK_DIR: '$WORK_DIR' (refusing top-level path '$_abs_work')" >&2; exit 1 ;;
esac

if [ -n "${HOME:-}" ]; then
    _abs_home="$(_resolve_abs_path "$HOME")"
    if [ "$_abs_work" = "$_abs_home" ]; then
        echo "Error: dangerous WORK_DIR: '$WORK_DIR' (matches HOME)" >&2
        exit 1
    fi
    case "$_abs_home" in
        "$_abs_work"/*)
            echo "Error: dangerous WORK_DIR: '$WORK_DIR' (parent of HOME '$_abs_work')" >&2
            exit 1
            ;;
    esac
fi

_abs_repo="$(_resolve_abs_path "$REPO_ROOT")"
if [ "$_abs_work" = "$_abs_repo" ]; then
    echo "Error: dangerous WORK_DIR: '$WORK_DIR' (matches repo root)" >&2
    exit 1
fi

case "$_abs_repo" in
    "$_abs_work"/*)
        echo "Error: dangerous WORK_DIR: '$WORK_DIR' (parent of repo root '$_abs_work')" >&2
        exit 1
        ;;
esac

case "$_abs_work" in
    "$_abs_repo"/build/*)
        ;;
    "$_abs_repo"/*)
        echo "Error: WORK_DIR inside repository must be under build/: '$WORK_DIR'" >&2
        exit 1
        ;;
esac

WORK_DIR="$_abs_work"

# 3. Check the hashes file, when one was given
if [ -n "$HASHES_FILE" ]; then
    if [ ! -f "$HASHES_FILE" ]; then
        echo "Error: hashes file not found: $HASHES_FILE" >&2
        exit 1
    fi
    HASHES_FILE="$(_resolve_abs_path "$HASHES_FILE")"
fi
WORK_DIR2="$WORK_DIR-second"

# 4. Check dependencies for repro verification (build toolchain, git, tar, sha256)
"$REPO_ROOT/scripts/check_deps.sh" build repro || exit $?

printf "=== Reproducible Build Verification ===\n"
printf "  Hashes file: %s\n" "${HASHES_FILE:-(none: the two builds are compared with each other)}"
printf "  Working dirs: %s and %s\n" "$WORK_DIR" "$WORK_DIR2"
printf "\n"

# 5. Clean and prepare isolated workspace
rm -rf "$WORK_DIR" "$WORK_DIR2"
mkdir -p "$WORK_DIR"

# 6. Extract/prepare clean tree
if [ "$STAGE0_DIR" != "bootstrap/stage0-c" ] && [ -f "$REPO_ROOT/scripts/export_public_release.sh" ]; then
    printf "[1/4] Exporting clean public release tree to workspace...\n"
    "$REPO_ROOT/scripts/export_public_release.sh" --skip-build "$WORK_DIR" >/dev/null
elif [ -d "$REPO_ROOT/.git" ]; then
    printf "[1/4] Extracting clean git tree to workspace...\n"
    (cd "$REPO_ROOT" && git archive HEAD | tar -x -C "$WORK_DIR")
else
    printf "[1/4] Copying clean source tree to workspace...\n"
    for item in "$REPO_ROOT"/*; do
        [ -e "$item" ] || continue
        _base="$(basename "$item")"
        case "$_base" in
            build|.git|.zoril-cache) continue ;;
            *) cp -a "$item" "$WORK_DIR/" ;;
        esac
    done
fi

# The second build starts from the same clean tree in a directory of another name.
cp -a "$WORK_DIR" "$WORK_DIR2"

# 7. Run clean rebuilds via each workspace Makefile
rebuild() {
    (
        unset STAGE0_DIR STAGE1_DIR STAGE0_C_DIR MAKEFLAGS MAKEOVERRIDES MFLAGS MAKELEVEL
        make -C "$1" all zbuild build/runtime.o
    ) > "$1/repro-build.log" 2>&1 || {
        tail -40 "$1/repro-build.log" >&2
        echo "Error: build in $1 failed — see $1/repro-build.log" >&2
        exit 1
    }
}
printf "[2/4] Rebuilding toolchain from scratch via Makefile...\n"
rebuild "$WORK_DIR"
printf "[3/4] Rebuilding it again in %s...\n" "$WORK_DIR2"
rebuild "$WORK_DIR2"

hash_of() { sha256_of "$1" | awk '{print $1}'; }
FAILED=0

# 8. The two builds must agree
printf "[4/4] Comparing the two builds%s...\n\n" "${HASHES_FILE:+ and the first with $(basename "$HASHES_FILE")}"
for _artifact in zoril zilc zbuild runtime.o; do
    if [ ! -f "$WORK_DIR/build/$_artifact" ] || [ ! -f "$WORK_DIR2/build/$_artifact" ]; then
        printf "[FAIL] %s: file not built\n" "$_artifact"
        FAILED=$((FAILED + 1))
    elif [ "$(hash_of "$WORK_DIR/build/$_artifact")" = "$(hash_of "$WORK_DIR2/build/$_artifact")" ]; then
        printf "[PASS] %s: both builds are identical (%s)\n" "$_artifact" "$(hash_of "$WORK_DIR/build/$_artifact")"
    else
        printf "[FAIL] %s: the two builds differ\n" "$_artifact"
        FAILED=$((FAILED + 1))
    fi
done

# 9. Optionally compare the first build with a published hashes file. A difference here is expected when this
# host's C library, QBE, assembler or linker is not the release host's (doc/reproducible_builds.md).
MISMATCHED=0
if [ -n "$HASHES_FILE" ]; then
    printf "\n"
    for _artifact in zoril zilc zbuild runtime.o; do
        _expected="$(grep -E "( |/)$_artifact\$" "$HASHES_FILE" | head -n1 | awk '{print $1}' || true)"
        _actual="$(hash_of "$WORK_DIR/build/$_artifact")"
        if [ -z "$_expected" ]; then
            printf "[FAIL] %s: no hash entry found in %s\n" "$_artifact" "$HASHES_FILE"
            MISMATCHED=$((MISMATCHED + 1))
        elif [ "$_actual" = "$_expected" ]; then
            printf "[PASS] %s matches the published hash (%s)\n" "$_artifact" "$_actual"
        else
            printf "[DIFF] %s\n       published: %s\n       this host: %s\n" "$_artifact" "$_expected" "$_actual"
            MISMATCHED=$((MISMATCHED + 1))
        fi
    done
    if [ "$MISMATCHED" -gt 0 ]; then
        printf "\nThe hashes differ from the published ones. That is expected unless this host builds with the release\n"
        printf "host's C library, QBE, assembler and linker; this host has:\n"
        printf "  %s\n" "$(sh "$REPO_ROOT/scripts/generate_build_info.sh" 2>/dev/null | grep -E '^(host_os|binutils|qbe_fingerprint|qbe_known_as):' | tr '\n' ';' | sed 's/;/; /g')"
        printf "Compare these with the release's build-info.txt (doc/reproducible_builds.md).\n"
    fi
fi

printf "\n"
if [ "$FAILED" -eq 0 ]; then
    printf "The two builds are identical.\n"
fi

if [ "$KEEP" -eq 0 ] && [ "$FAILED" -eq 0 ]; then
    rm -rf "$WORK_DIR" "$WORK_DIR2"
elif [ "$KEEP" -eq 1 ]; then
    printf "Rebuilt artifacts preserved in %s and %s\n" "$WORK_DIR" "$WORK_DIR2"
fi

if [ "$FAILED" -eq 0 ] && [ "$MISMATCHED" -eq 0 ]; then
    exit 0
else
    exit 1
fi
