#!/bin/sh
# scripts/test_build_info.sh — build-info.txt names the tree it was made from and the host, leaks no
# local path, and scripts/dist.sh warns when the host is not Alpine Linux.
cd "$(dirname "$0")/.." || exit 2
command -v git >/dev/null 2>&1 || { echo "[SKIP] build-info: no git"; exit 0; }
fail() { echo "[FAIL] build-info: $1"; exit 1; }
t=$(mktemp -d "${TMPDIR:-/tmp}/zoril_buildinfo_XXXXXX")
trap 'rm -rf "$t"' EXIT INT TERM
mkdir -p "$t/scripts/lib" "$t/stub"
cp scripts/generate_build_info.sh scripts/version.sh scripts/dist.sh "$t/scripts/"
cp scripts/lib/portability.sh "$t/scripts/lib/"
echo 9.9.9 > "$t/VERSION"
(cd "$t" && git init -q . && git config user.email a@b.invalid && git config user.name t && git config commit.gpgsign false && git add . && git commit -q -m one) || fail "cannot make a scratch repository"
head=$(git -C "$t" rev-parse HEAD)
tree=$(git -C "$t" rev-parse 'HEAD^{tree}')
gen() { (cd "$t" && env "$@" sh scripts/generate_build_info.sh > "$t/out.txt" 2> "$t/err.txt"); }
field() { sed -n "s/^$1: //p" "$t/out.txt"; }

gen OS_RELEASE=/nonexistent || fail "generate_build_info.sh failed: $(cat "$t/err.txt")"
[ "$(field commit)" = "$head" ] || fail "commit is '$(field commit)', HEAD is $head"
[ "$(field tree)" = "$tree" ] || fail "tree is '$(field tree)', HEAD's tree is $tree"
[ "$(field version)" = 9.9.9 ] || fail "version is '$(field version)'"
[ "$(field host_os)" = unknown ] || fail "host_os without an os-release is '$(field host_os)'"
if grep -q -e '/home/' -e '_path' "$t/out.txt"; then fail "build-info.txt names a local path"; fi

echo two > "$t/VERSION"
gen OS_RELEASE=/nonexistent
[ "$(field commit)" = "$head-dirty" ] || fail "a changed tracked file gives commit '$(field commit)', not $head-dirty"
(cd "$t" && git checkout -q -- VERSION)

gen OS_RELEASE=/nonexistent BUILD_COMMIT=abc BUILD_TREE=def
[ "$(field commit)" = abc ] && [ "$(field tree)" = def ] || fail "BUILD_COMMIT / BUILD_TREE are not used"

# A source tarball extracted inside another checkout describes itself, never the checkout around it.
mkdir -p "$t/sub/scripts/lib"
cp "$t/scripts/generate_build_info.sh" "$t/scripts/version.sh" "$t/sub/scripts/"
cp "$t/scripts/lib/portability.sh" "$t/sub/scripts/lib/"
(cd "$t/sub" && OS_RELEASE=/nonexistent sh scripts/generate_build_info.sh > "$t/out.txt" 2>&1) || fail "generate in a nested tree failed"
[ "$(field commit)" = unknown ] && [ "$(field tree)" = unknown ] || fail "a nested tree reports the enclosing repository: $(field commit)"

printf 'NAME="Alpine Linux"\nID=alpine\nPRETTY_NAME="Alpine Linux v3.99"\n' > "$t/alpine.release"
printf 'NAME="Arch Linux"\nID=arch\nPRETTY_NAME="Arch Linux"\n' > "$t/arch.release"
gen OS_RELEASE="$t/alpine.release"
[ "$(field host_os)" = "Alpine Linux v3.99" ] || fail "host_os is '$(field host_os)'"

# Package revisions come from the host's package manager.
printf '#!/bin/sh\ncase "$1" in -Qo) echo somepkg ;; -Q) echo "$2 9.9-1" ;; esac\n' > "$t/stub/pacman"
printf '#!/bin/sh\n:\n' > "$t/stub/apk"
chmod +x "$t/stub/pacman" "$t/stub/apk"
gen OS_RELEASE=/nonexistent PATH="$t/stub:$PATH"
[ "$(field binutils_pkg)" = 9.9-1 ] || fail "binutils_pkg is '$(field binutils_pkg)' with a pacman that answers 9.9-1"
[ "$(field qbe_pkg)" = 9.9-1 ] || fail "qbe_pkg is '$(field qbe_pkg)'"
printf '#!/bin/sh\nexit 1\n' > "$t/stub/pacman"
gen OS_RELEASE=/nonexistent PATH="$t/stub:$PATH"
[ "$(field binutils_pkg)" = unknown ] || fail "binutils_pkg is '$(field binutils_pkg)' for a binary no package owns"
[ "$(field qbe_pkg)" = unknown ] || fail "qbe_pkg is '$(field qbe_pkg)' for a binary no package owns"

# The QBE fingerprint: a hex string for a usable QBE, named when scripts/qbe_pins.tsv lists it, and
# unknown (never an error) for a QBE that cannot compile the fixtures or when the script is absent.
mkdir -p "$t/scripts/qbe_probe"
cp scripts/qbe_fingerprint.sh "$t/scripts/"
cp scripts/qbe_probe/*.ssa "$t/scripts/qbe_probe/"
printf '#!/bin/sh\nout=\nwhile [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift 2 ;; -t) shift 2 ;; *) shift ;; esac; done\nprintf alpha > "$out"\n' > "$t/stub/fakeqbe"
printf '#!/bin/sh\nexit 1\n' > "$t/stub/brokenqbe"
chmod +x "$t/stub/fakeqbe" "$t/stub/brokenqbe"
gen OS_RELEASE=/nonexistent BACKEND_BIN="$t/stub/fakeqbe"
fp=$(field qbe_fingerprint)
case "$fp" in *[!0-9a-f]*|"") fail "qbe_fingerprint is '$fp' for a usable QBE" ;; esac
[ "$(field qbe_known_as)" = none ] || fail "qbe_known_as is '$(field qbe_known_as)' with no pins table"
printf '%s\tthe fake QBE\n' "$fp" > "$t/scripts/qbe_pins.tsv"
gen OS_RELEASE=/nonexistent BACKEND_BIN="$t/stub/fakeqbe"
[ "$(field qbe_known_as)" = "the fake QBE" ] || fail "a pinned fingerprint is not named: '$(field qbe_known_as)'"
gen OS_RELEASE=/nonexistent BACKEND_BIN="$t/stub/brokenqbe" || fail "an unusable QBE made generate_build_info.sh fail"
[ "$(field qbe_fingerprint)" = unknown ] || fail "qbe_fingerprint is '$(field qbe_fingerprint)' for a QBE that cannot compile"
mv "$t/scripts/qbe_fingerprint.sh" "$t/scripts/qbe_fingerprint.sh.off"
gen OS_RELEASE=/nonexistent BACKEND_BIN="$t/stub/fakeqbe" || fail "generate_build_info.sh failed without qbe_fingerprint.sh"
[ "$(field qbe_fingerprint)" = unknown ] || fail "qbe_fingerprint is '$(field qbe_fingerprint)' without the script"
mv "$t/scripts/qbe_fingerprint.sh.off" "$t/scripts/qbe_fingerprint.sh"

# scripts/dist.sh: silent on Alpine, a warning elsewhere, an error with DIST_REQUIRE_ALPINE=1.
host() { (cd "$t" && env DIST_REQUIRE_ALPINE=0 "$@" sh scripts/dist.sh host > "$t/out.txt" 2> "$t/err.txt"); }
host OS_RELEASE="$t/alpine.release" || fail "dist.sh host failed on Alpine"
[ ! -s "$t/err.txt" ] || fail "dist.sh warns on Alpine: $(cat "$t/err.txt")"
host OS_RELEASE="$t/arch.release" || fail "dist.sh host failed on Arch without DIST_REQUIRE_ALPINE"
grep -q 'WARNING: building on Arch Linux' "$t/err.txt" || fail "no warning on Arch"
host OS_RELEASE="$t/arch.release" DIST_REQUIRE_ALPINE=1 && fail "DIST_REQUIRE_ALPINE=1 passed on Arch"
grep -q 'requires Alpine' "$t/err.txt" || fail "the refusal does not say why"
host OS_RELEASE=/nonexistent || fail "dist.sh host failed with no os-release"
grep -q 'unknown host' "$t/err.txt" || fail "no warning without an os-release"

# A real source archive: build-info.txt lands beside SHA256SUMS and lists the archive's hash.
if command -v bsdtar >/dev/null 2>&1; then
    (cd "$t" && OS_RELEASE="$t/alpine.release" DIST_OUT="$t/dist" sh scripts/dist.sh src > "$t/out.txt" 2>&1) || fail "dist.sh src failed: $(cat "$t/out.txt")"
    [ -f "$t/dist/build-info.txt" ] || fail "dist.sh src wrote no build-info.txt"
    grep -q "^commit: $head\$" "$t/dist/build-info.txt" || fail "build-info.txt has the wrong commit"
    want=$(sed 's/  */ /' "$t/dist/SHA256SUMS")
    [ "$(sed -n 's/^archive_sha256: //p' "$t/dist/build-info.txt")" = "$want" ] || fail "archive_sha256 does not match SHA256SUMS"
    if grep -q build-info "$t/dist/SHA256SUMS"; then fail "build-info.txt is in SHA256SUMS"; fi
else
    echo "[SKIP] build-info: no bsdtar, so no source archive was built"
fi
echo "[PASS] build-info: commit, host, package revisions, no local paths; dist.sh checks the host"
