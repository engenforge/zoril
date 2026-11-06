#!/bin/sh
# scripts/dist_user_paths.sh SOURCE-TARBALL BINARY-TARBALL — the release archives, used the way README says.
#
# `make dist-check` proves the archives reproducible; this proves they work, because nothing else had
# unpacked one (A0 found `make test` red in the source tarball, `zoril unknown` in its binaries, and a
# red `check-deps-selftest` for a tree unpacked inside another git repository). It runs, each from a
# scratch directory outside this tree:
#   1. the source tarball extracted with no git: `make` and `make test`;
#   2. the same tarball extracted inside a throwaway git repository with one commit (a user who unpacks
#      into a dotfiles repository or a projects directory), with VERSION written: `make` and `make test`;
#   3. README's three "Option 2" recipes, each on a fresh extraction of the source tarball, with the
#      binaries of the binary tarball as the seed: `make ZORIL_SEED=<its bin>`, `make SYSTEM_ZORIL=1` with
#      that bin on PATH, and the binaries copied into build/ then `make` (after `touch src/main.zrl`).
#      None may bootstrap from stage0-C (no build/zoril-stage1, no stage0-C build log), and each must
#      leave a compiler that passes `make test-fast`.
#   4. README's "Installing a Prebuilt Release" commands (all but the download) on the binary tarball, into a scratch
#      PREFIX: `zoril --version`, a hello program built and run with the installed `zbuild`, then the
#      uninstall line, after which nothing of the archive may be left.
# Each step's time is printed; the log of a failing one is shown.
set -u
# Run from `make dist-check`, this inherits the Makefile's exported builder variables (ZORIL_BUILDER=build/zoril ...),
# which a user's shell does not have and which beat `make ZORIL_SEED=...` (`?=`): the recipes would bootstrap from stage0-C.
unset ZORIL_BUILDER ZILC_BUILDER ZILC_BIN BOOTSTRAP_CC_TIMEOUT BOOTSTRAP_BUILD_TIMEOUT TARGET ZILC MAKEFLAGS MAKELEVEL MFLAGS
GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_GLOBAL
GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_SYSTEM
GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_NOSYSTEM
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
for _v in $(env 2>/dev/null | sed -n 's/^\(GIT_CONFIG_[KEY|VALUE].*\)=.*/\1/p'); do
    unset "$_v"
done
if [ $# -ne 2 ]; then echo "usage: dist_user_paths.sh SOURCE-TARBALL BINARY-TARBALL" >&2; exit 2; fi
SRC=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
BINTAR=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
KEEP="$(cd "$(dirname "$0")/.." && pwd)/build/dist-user-paths"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/zoril_dist_user_XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
# A failing step's whole log is kept under build/dist-user-paths/ (the scratch tree is removed on exit).
fail() {
    echo "[FAIL] dist-user-paths: $1" >&2
    if [ -n "${2:-}" ] && [ -f "$2" ]; then
        mkdir -p "$KEEP" && cp "$2" "$KEEP/" 2> /dev/null
        grep -E '^\[FAIL\]|FAIL:|Error' "$2" | head -n 15 | sed 's/^/       /' >&2
        tail -n 8 "$2" | sed 's/^/       /' >&2
        echo "       full log: $KEEP/$(basename "$2")" >&2
    fi
    exit 1
}
now() { date +%s; }
step() { # step NAME LOG CMD... — run a command in the current directory, print its time
    _name=$1; _log=$2; shift 2
    _t=$(now)
    "$@" > "$_log" 2>&1 || fail "$_name failed" "$_log"
    echo "  $_name: $(( $(now) - _t )) s"
}
extract() { mkdir -p "$2" && bsdtar -x -f "$1" -C "$2" && ls -d "$2"/zoril-* | head -n 1; }

total=$(now)
# 1. No git.
tree=$(extract "$SRC" "$WORK/plain")
[ ! -e "$tree/.git" ] || fail "the source tarball carries a .git"
(cd "$tree" && step "no git: make" "$WORK/plain.make.log" make && step "no git: make test" "$WORK/plain.test.log" make test) || exit 1
rm -rf "$WORK/plain"

# 2. Inside another repository.
mkdir -p "$WORK/outer"
(cd "$WORK/outer" && git init -q . && git config user.email dist@example.invalid && git config user.name dist && git config commit.gpgsign false && git config tag.gpgsign false && git config core.hooksPath /dev/null \
    && echo outer > file && git add file && git commit -q -m outer) || fail "cannot make a scratch repository"
tree=$(extract "$SRC" "$WORK/outer/sub")
[ -f "$tree/VERSION" ] || fail "the source tarball has no VERSION"
(cd "$tree" && step "inside a git repository: make" "$WORK/nested.make.log" make && step "inside a git repository: make test" "$WORK/nested.test.log" make test) || exit 1
rm -rf "$WORK/outer"

# 3. README's Option 2 recipes.
binpkg=$(extract "$BINTAR" "$WORK/binpkg")
seed="$binpkg/bin"
[ -x "$seed/zoril" ] && [ -x "$seed/zilc" ] || fail "the binary tarball has no bin/zoril and bin/zilc"
not_bootstrapped() { # not_bootstrapped LABEL
    [ ! -e build/zoril-stage1 ] || fail "$1 bootstrapped from stage0-C (build/zoril-stage1 exists)"
    [ ! -e build/stage0c-build.log ] || fail "$1 bootstrapped from stage0-C (build/stage0c-build.log exists)"
    [ -x build/zoril ] || fail "$1 left no build/zoril"
}
recipe() { # recipe LABEL CMD... — on a fresh extraction
    _label=$1; shift
    _t=$(extract "$SRC" "$WORK/opt2")
    ( cd "$_t" && "$@" && not_bootstrapped "$_label" && step "$_label: make test-fast" "$WORK/opt2.fast.log" make test-fast ) || exit 1
    rm -rf "$WORK/opt2"
}
recipe_a() { step "ZORIL_SEED" "$WORK/opt2.a.log" make ZORIL_SEED="$seed"; }
recipe_b() { ( PATH="$seed:$PATH"; export PATH; step "SYSTEM_ZORIL=1" "$WORK/opt2.b.log" make SYSTEM_ZORIL=1 ); }
recipe_c() {
    mkdir -p build && cp "$seed/zoril" "$seed/zilc" build/ || return 1
    step "copied into build/: make" "$WORK/opt2.c1.log" make || return 1
    touch src/main.zrl
    step "copied into build/: touch src/main.zrl && make" "$WORK/opt2.c2.log" make
}
recipe "recipe 1 (ZORIL_SEED)" recipe_a
recipe "recipe 2 (SYSTEM_ZORIL=1)" recipe_b
recipe "recipe 3 (binaries copied into build/)" recipe_c
# 4. README's prebuilt-release recipe: extract into $PREFIX, use, uninstall.
PREFIX="$WORK/prefix"
v=$(basename "$BINTAR" | sed 's/^zoril-//; s/-linux-x86_64\.tar\.xz$//')
mkdir -p "$PREFIX" && tar -xJf "$BINTAR" -C "$PREFIX" --strip-components=1 || fail "the binary tarball does not extract into a prefix with --strip-components=1"
[ -x "$PREFIX/bin/zoril" ] && [ -x "$PREFIX/bin/zbuild" ] || fail "after extracting with --strip-components=1, $PREFIX/bin has no zoril and zbuild (member names carry an extra leading component?)"
mkdir -p "$WORK/hello" && printf 'fn main() -> i32 {\n    return 42;\n}\n' > "$WORK/hello/hello.zrl"
got=$(PATH="$PREFIX/bin:$PATH"; cd "$WORK/hello" && zoril --version > "$WORK/prefix.version" 2>&1 && zbuild hello.zrl -o hello > "$WORK/prefix.build.log" 2>&1 && ./hello; echo $?)
[ "$got" = 42 ] || fail "a program built with the zbuild installed under a scratch PREFIX did not run (exit $got)" "$WORK/prefix.build.log"
tar -tJf "$BINTAR" | sed 's|^[^/]*/||' | grep -v '/$' | (cd "$PREFIX" && xargs rm -f)
left=$(find "$PREFIX" -type f | head -n 3)
[ -z "$left" ] || fail "the uninstall line left files behind: $left"
rm -rf "$PREFIX"

echo "[PASS] dist-user-paths: the source tarball builds and passes make test with no git and inside another repository, and README's three Option 2 recipes build without stage0-C and its prebuilt-release recipe installs, runs and uninstalls cleanly ($(( $(now) - total )) s)"
