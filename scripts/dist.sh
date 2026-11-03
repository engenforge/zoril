#!/bin/sh
# scripts/dist.sh — Build the release tarballs into build/dist/, reproducibly.
#
#   scripts/dist.sh src     zoril-<version>.tar.xz: the files of the HEAD commit, under zoril-<version>/
#   scripts/dist.sh bin     zoril-<version>-linux-x86_64.tar.xz: what `make install` installs (bin/,
#                           lib/zoril/, share/), relocatable; extracted and smoke-tested before it is kept
#   scripts/dist.sh check   build both twice and require identical archives
#
#   scripts/dist.sh host    only the host check below (used by the tests)
#
# Each run rewrites build/dist/SHA256SUMS for the tarballs present, and build/dist/build-info.txt
# (scripts/generate_build_info.sh: the commit, the host and the toolchain that made them, then the
# archive hashes). SHA256SUMS ends with build-info.txt's own hash, so a signature on SHA256SUMS covers
# every published file. build-info.txt names the machine, so it is not reproducible: a rebuild compares
# the archive lines, and `check` does not compare it.
#
# The release archives are built on Alpine Linux. On any other host, src and bin print a warning (the
# build-info.txt says which host); DIST_REQUIRE_ALPINE=1 makes it an error. OS_RELEASE names the
# os-release file to read (default /etc/os-release).
#
# Reproducible: the archive is written by bsdtar (libarchive) from an mtree manifest that fixes every
# entry's order (sorted), mode (0755 or 0644), owner (root, 0) and time (the HEAD commit's), in the
# ustar format, and xz-compressed by bsdtar (liblzma, preset 9, one thread). The .tar inside is
# byte-identical on any host; the .tar.xz also depends on the liblzma version, and differs from what
# the xz command makes of the same .tar. See doc/reproducible_builds.md.
#
# The source tarball is the commit, not the working tree, so a tree with uncommitted changes to
# tracked files is refused (its version would say -dirty and the tarball would not); set
# DIST_ALLOW_DIRTY=1 to build anyway.

set -eu

case "$0" in */*) cd "${0%/*}/.." ;; *) cd .. ;; esac || exit 2
REPO_ROOT="$(pwd)"
. scripts/lib/portability.sh

MODE="${1:-}"
case "$MODE" in
    src|bin|check|host) ;;
    *) echo "usage: scripts/dist.sh src|bin|check|host" >&2; exit 2 ;;
esac

# The release archives are built on Alpine Linux: warn on any other host, or refuse with
# DIST_REQUIRE_ALPINE=1. `check` compares two builds on one host, so it does not depend on which.
check_release_host() {
    _osr="${OS_RELEASE:-/etc/os-release}"
    _id=""
    _pretty=""
    if [ -r "$_osr" ]; then
        _id="$(sed -n 's/^ID=//p' "$_osr" | head -n1 | tr -d '"')"
        _pretty="$(sed -n 's/^PRETTY_NAME=//p' "$_osr" | head -n1 | tr -d '"')"
    fi
    [ "$_id" = alpine ] && return 0
    [ -z "$_pretty" ] && _pretty="an unknown host (no $_osr)"
    if [ "${DIST_REQUIRE_ALPINE:-0}" = 1 ]; then
        echo "dist: this host is $_pretty; DIST_REQUIRE_ALPINE=1 requires Alpine Linux for the release archives" >&2
        exit 1
    fi
    echo "dist: WARNING: building on $_pretty; the release archives are built on Alpine Linux (doc/reproducible_builds.md)" >&2
}
case "$MODE" in
    src|bin|host) check_release_host ;;
esac
[ "$MODE" = host ] && exit 0

for tool in bsdtar git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "dist: $tool not found on PATH (bsdtar is libarchive's tar: libarchive-tools on Alpine and Debian, built in on FreeBSD and macOS)" >&2
        exit 1
    fi
done

if [ "${DIST_ALLOW_DIRTY:-0}" != 1 ] && ! git diff --quiet HEAD --; then
    echo "dist: the tree has uncommitted changes to tracked files; commit them, or set DIST_ALLOW_DIRTY=1" >&2
    git diff --stat HEAD -- >&2
    exit 1
fi

VERSION="$(./scripts/version.sh)"
EPOCH="$(git log -1 --format=%ct HEAD)"
OUT="${DIST_OUT:-$REPO_ROOT/build/dist}"
mkdir -p "$OUT"
WORK="$(mktemp -d "$OUT/.work.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

# An mtree manifest for the tree at $1, named $2 inside the archive. Paths are limited to characters
# mtree writes unescaped; anything else is refused rather than escaped.
manifest() {
    _dir="$1"
    _name="$2"
    _attrs="uid=0 gid=0 uname=root gname=root time=$EPOCH.0"
    echo "#mtree"
    echo "$_name type=dir mode=0755 $_attrs"
    (cd "$_dir" && find . -mindepth 1 | LC_ALL=C sort) | while IFS= read -r _p; do
        _p="${_p#./}"
        case "$_p" in
            *[!A-Za-z0-9._/+-]*) echo "dist: unsupported character in path: $_p" >&2; return 1 ;;
        esac
        if [ -L "$_dir/$_p" ]; then
            echo "dist: symbolic links are not archived: $_p" >&2
            return 1
        elif [ -d "$_dir/$_p" ]; then
            echo "$_name/$_p type=dir mode=0755 $_attrs"
        elif [ -x "$_dir/$_p" ]; then
            echo "$_name/$_p type=file mode=0755 $_attrs contents=$_dir/$_p"
        else
            echo "$_name/$_p type=file mode=0644 $_attrs contents=$_dir/$_p"
        fi
    done
}

# Archive the tree at $1 as $2 inside the archive, into the tarball $3.
archive() {
    manifest "$1" "$2" > "$WORK/$2.mtree"
    bsdtar -c --format ustar -J --options xz:compression-level=9 \
        -f "$3.tmp" "@$WORK/$2.mtree"
    mv -f "$3.tmp" "$3"
}

build_src() {
    _name="zoril-$VERSION"
    _dir="$WORK/src/$_name"
    rm -rf "$WORK/src"
    mkdir -p "$_dir"
    git archive HEAD | bsdtar -x -f - -C "$_dir"
    # A tree with no VERSION file (the private checkout) would build a compiler that reports "unknown".
    printf "%s\n" "$VERSION" > "$_dir/VERSION"
    archive "$_dir" "$_name" "$1/$_name.tar.xz"
    echo "$1/$_name.tar.xz"
}

build_bin() {
    case "$(uname -s)/$(uname -m)" in
        Linux/x86_64) ;;
        *) echo "dist: the binary tarball is built on x86-64 Linux; this host is $(uname -s)/$(uname -m)" >&2; return 1 ;;
    esac
    _name="zoril-$VERSION-linux-x86_64"
    _dir="$WORK/bin/$_name"
    rm -rf "$WORK/bin"
    mkdir -p "$_dir"
    ${MAKE:-make} --no-print-directory install DESTDIR="$_dir" PREFIX= > "$WORK/install.log" 2>&1 || {
        cat "$WORK/install.log" >&2
        echo "dist: make install into the staging tree failed" >&2
        return 1
    }
    archive "$_dir" "$_name" "$1/$_name.tar.xz"
    smoke_test "$1/$_name.tar.xz" "$_name"
    echo "$1/$_name.tar.xz"
}

# Extract the binary tarball somewhere else and build hello world with only what it holds: the
# compiler must find its standard library and runtime relative to itself.
smoke_test() {
    # Outside the repository, so nothing in it can be found by searching upward from the program.
    _x="$(mktemp -d "${TMPDIR:-/tmp}/zoril_dist_smoke_XXXXXX")"
    mkdir -p "$_x/prog"
    bsdtar -x -f "$1" -C "$_x"
    cat > "$_x/prog/hello.zrl" << 'EOF'
import "io.zrl";
use io::println;

fn main() -> i32 {
    println("Hello, World!");
    return 0;
}
EOF
    _got="$(cd "$_x/prog" && PATH="$_x/$2/bin:$PATH" zbuild -o hello hello.zrl > build.log 2>&1 && ./hello)" || {
        cat "$_x/prog/build.log" >&2 2>/dev/null || true
        echo "dist: the extracted binary tarball could not build and run hello world" >&2
        rm -rf "$_x"
        return 1
    }
    rm -rf "$_x"
    if [ "$_got" != "Hello, World!" ]; then
        echo "dist: hello world from the extracted binary tarball printed: $_got" >&2
        return 1
    fi
}

write_sums() {
    (cd "$OUT" && for f in zoril-*.tar.xz; do [ -f "$f" ] && sha256_of "$f"; done) > "$OUT/SHA256SUMS.tmp"
    mv -f "$OUT/SHA256SUMS.tmp" "$OUT/SHA256SUMS"
}

# build/dist/build-info.txt: what this tree is and what built it, then the hashes of the archives
# present (the ones write_sums put in SHA256SUMS). Its own hash is then appended to SHA256SUMS.
write_build_info() {
    {
        ./scripts/generate_build_info.sh "$REPO_ROOT"
        while read -r _h _f; do
            echo "archive_sha256: $_h $_f"
        done < "$OUT/SHA256SUMS"
    } > "$OUT/build-info.txt.tmp"
    mv -f "$OUT/build-info.txt.tmp" "$OUT/build-info.txt"
    (cd "$OUT" && sha256_of build-info.txt) >> "$OUT/SHA256SUMS"
}

case "$MODE" in
    src) build_src "$OUT"; write_sums; write_build_info ;;
    bin) build_bin "$OUT"; write_sums; write_build_info ;;
    check)
        mkdir -p "$WORK/a" "$WORK/b"
        for kind in src bin; do
            first="$("build_$kind" "$WORK/a")"
            second="$("build_$kind" "$WORK/b")"
            if ! cmp -s "$first" "$second"; then
                echo "[FAIL] dist: two builds of $(basename "$first") differ" >&2
                exit 1
            fi
            echo "[PASS] dist: $(basename "$first") is reproducible ($(wc -c < "$first" | tr -d " ") bytes)"
            eval "first_$kind=\$first"
        done
        # The archives a release would publish are then used the way README says (scripts/dist_user_paths.sh).
        "$REPO_ROOT/scripts/dist_user_paths.sh" "$first_src" "$first_bin" || exit 1
        ;;
esac
