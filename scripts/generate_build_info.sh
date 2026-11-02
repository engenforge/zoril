#!/bin/sh
# scripts/generate_build_info.sh — Print the build info of a Zoril tree: what it is and what built it.
#
#   scripts/generate_build_info.sh [DIR]     DIR defaults to the repository this script is in
#
# Written by `make dist` and `make dist-bin` to build/dist/build-info.txt (scripts/dist.sh appends the
# archive hashes). It describes DIR and the machine it runs on, nothing else: the commit and tree come
# from DIR's own git checkout, and a DIR that is not one (a source tarball) says `unknown` unless
# BUILD_COMMIT / BUILD_TREE are set. It never reads an enclosing repository.
#
# Environment: BUILD_COMMIT, BUILD_TREE (for a tree with no .git), TARGET_TRIPLE, RELEASE_TAG (adds a
# release_tag line), BACKEND_BIN / ASSEMBLER_BIN / LINKER_BIN (the tools to describe), QBE_VERSION and
# QBE_COMMIT (QBE has no --version, so a hand-installed one reads `unknown` unless these are set),
# OS_RELEASE (default /etc/os-release).
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TARGET_DIR="${1:-$REPO_ROOT}"

. "$REPO_ROOT/scripts/lib/portability.sh"

TARGET_TRIPLE="${TARGET_TRIPLE:-$(uname -m)-$(uname -s | tr '[:upper:]' '[:lower:]')}"

# Release version, as `zoril --version` reports it.
VERSION="$("$REPO_ROOT/scripts/version.sh" "$TARGET_DIR")"

# Commit and tree of DIR's own checkout.
COMMIT="${BUILD_COMMIT:-}"
TREE_HASH="${BUILD_TREE:-}"
if git_checkout_usable "$TARGET_DIR"; then
    if [ -z "$COMMIT" ]; then
        COMMIT="$(git -C "$TARGET_DIR" rev-parse HEAD 2>/dev/null || true)"
        if [ -n "$COMMIT" ] && ! git -C "$TARGET_DIR" diff --quiet HEAD -- 2>/dev/null; then
            COMMIT="$COMMIT-dirty"
        fi
    fi
    if [ -z "$TREE_HASH" ]; then
        TREE_HASH="$(git -C "$TARGET_DIR" rev-parse 'HEAD^{tree}' 2>/dev/null || true)"
    fi
fi
[ -z "$COMMIT" ] && COMMIT="unknown"
[ -z "$TREE_HASH" ] && TREE_HASH="unknown"

# The machine: PRETTY_NAME from os-release ("Alpine Linux v3.22").
HOST_OS=""
if [ -r "${OS_RELEASE:-/etc/os-release}" ]; then
    HOST_OS="$(sed -n 's/^PRETTY_NAME=//p' "${OS_RELEASE:-/etc/os-release}" | head -n1 | tr -d '"')"
fi
[ -z "$HOST_OS" ] && HOST_OS="unknown"

# The installed package revision ("2.47-r0") of the package that owns the file $1, from whichever
# package manager the host has; unknown for a file no package owns (a tool built from source). A
# distribution patches its tools, so the upstream version alone does not identify them. $2 is the
# package name, used only where the host cannot tell which package owns a file (dpkg).
pkg_version() {
    _pv=""
    _own=""
    if command -v pacman >/dev/null 2>&1; then
        [ -n "$1" ] && _own="$(pacman -Qo -q "$1" 2>/dev/null || true)"
        [ -n "$_own" ] && _pv="$(pacman -Q "$_own" 2>/dev/null | awk '{print $2}' || true)"
    elif command -v apk >/dev/null 2>&1; then
        [ -n "$1" ] && _own="$(apk info -W "$1" 2>/dev/null | sed -n 's/.* is owned by //p' || true)"
        [ -n "$_own" ] && _pv="$(printf '%s\n' "$_own" | sed -n -E 's/^.*-([0-9][^-]*-r[0-9]+)$/\1/p' || true)"
    elif command -v dpkg-query >/dev/null 2>&1; then
        _pv="$(dpkg-query -W -f='${Version}' "$2" 2>/dev/null || true)"
    fi
    [ -z "$_pv" ] && _pv="unknown"
    printf "%s\n" "$_pv"
}

# SHA-256 of the file $1, or unknown.
hash_or_unknown() {
    if [ -n "$1" ] && [ -f "$1" ]; then
        sha256_of "$1" 2>/dev/null | awk '{print $1}' || echo "unknown"
    else
        echo "unknown"
    fi
}

# QBE has no --version flag.
BACKEND_BIN="${BACKEND_BIN:-qbe}"
QBE_PATH="$(command -v "$BACKEND_BIN" 2>/dev/null || echo "")"
QBE_SHA256="$(hash_or_unknown "$QBE_PATH")"
QBE_PKG="$(pkg_version "$QBE_PATH" qbe)"
QBE_VERSION="${QBE_VERSION:-}"
if [ -z "$QBE_VERSION" ] && [ "$QBE_PKG" != "unknown" ]; then
    QBE_VERSION="${QBE_PKG%%-*}"
fi
[ -z "$QBE_VERSION" ] && QBE_VERSION="unknown"
QBE_COMMIT="${QBE_COMMIT:-unknown}"

# What QBE writes identifies it better than a version it does not report (scripts/qbe_fingerprint.sh);
# scripts/qbe_pins.tsv names the fingerprints seen.
QBE_FINGERPRINT="unknown"
QBE_KNOWN_AS="none"
if [ -n "$QBE_PATH" ] && [ -f "$REPO_ROOT/scripts/qbe_fingerprint.sh" ]; then
    _fp="$(sh "$REPO_ROOT/scripts/qbe_fingerprint.sh" "$QBE_PATH" 2>/dev/null || true)"
    case "${_fp#qbe_fingerprint: }" in
        *[!0-9a-f]*|"") ;;
        *) QBE_FINGERPRINT="${_fp#qbe_fingerprint: }" ;;
    esac
fi
if [ "$QBE_FINGERPRINT" != "unknown" ] && [ -f "$REPO_ROOT/scripts/qbe_pins.tsv" ]; then
    _known="$(awk -F'\t' -v fp="$QBE_FINGERPRINT" '$1 == fp { print $2; exit }' "$REPO_ROOT/scripts/qbe_pins.tsv")"
    [ -n "$_known" ] && QBE_KNOWN_AS="$_known"
fi

# Binutils (as and ld).
ASSEMBLER_BIN="${ASSEMBLER_BIN:-${AS_BIN:-as}}"
LINKER_BIN="${LINKER_BIN:-${LD_BIN:-ld}}"
AS_PATH="$(command -v "$ASSEMBLER_BIN" 2>/dev/null || echo "")"
LD_PATH="$(command -v "$LINKER_BIN" 2>/dev/null || echo "")"

AS_VERSION="$("$ASSEMBLER_BIN" --version 2>/dev/null | head -n1 || echo "unknown")"
LD_VERSION="$("$LINKER_BIN" --version 2>/dev/null | head -n1 || echo "unknown")"
[ -z "$AS_VERSION" ] && AS_VERSION="unknown"
[ -z "$LD_VERSION" ] && LD_VERSION="unknown"
BINUTILS_VERSION="$(printf "%s\n" "$AS_VERSION" | sed -E 's/^[^0-9]*([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')"
BINUTILS_PKG="$(pkg_version "$AS_PATH" binutils)"

AS_SHA256="$(hash_or_unknown "$AS_PATH")"
LD_SHA256="$(hash_or_unknown "$LD_PATH")"

echo "version: $VERSION"
[ -n "${RELEASE_TAG:-}" ] && echo "release_tag: $RELEASE_TAG"
cat <<EOF
commit: $COMMIT
tree: $TREE_HASH
target: $TARGET_TRIPLE
host_os: $HOST_OS
binutils: $BINUTILS_VERSION
binutils_pkg: $BINUTILS_PKG
as: $AS_VERSION
as_sha256: $AS_SHA256
ld: $LD_VERSION
ld_sha256: $LD_SHA256
qbe_version: $QBE_VERSION
qbe_pkg: $QBE_PKG
qbe_commit: $QBE_COMMIT
qbe_fingerprint: $QBE_FINGERPRINT
qbe_known_as: $QBE_KNOWN_AS
qbe_sha256: $QBE_SHA256
EOF
