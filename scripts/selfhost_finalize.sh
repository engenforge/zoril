#!/bin/sh
# scripts/selfhost_finalize.sh [--force] — Confirm that zoril, zilc and zbuild reproduce themselves.
#
# The binaries in build/ may have been made by other tools: the bootstrap zilc and the frozen stage1 compiler, a
# seed or system zoril, or a release's binaries copied into build/. This rebuilds build/zoril, build/zilc and
# build/zbuild with build/zoril and build/zilc themselves (generation 1) and compares each with the binary in
# build/. If all three are identical, the kept binaries already are what the self-hosted tools produce.
#
# If some differ (made by other tools, or by another host's toolchain), the generation 1 tools rebuild all three again
# (generation 2), and generation 2 must equal generation 1: the toolchain reproduces itself. The generation 1 binaries
# then replace the ones that differed, so what is left was built by itself. If generation 2 differs, nothing is
# replaced. In the automatic mode build/zbuild is then moved to build/zbuild.not-selfhosted, so the next make builds it
# and runs this again instead of trusting the tools; with --force nothing is moved.
#
# The Makefile leaves build/.selfhost-unverified when it first builds build/zilc and runs this after build/zbuild;
# `make selfhost-confirm` runs it with --force (binaries copied into build/ are otherwise never rebuilt).
set -eu

case "$0" in */*) cd "${0%/*}/.." ;; *) cd .. ;; esac || exit 2
. scripts/lib/portability.sh

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1
MARKER=build/.selfhost-unverified
TARGET="${TARGET:-build/zoril}"
ZILC="${ZILC:-build/zilc}"
ZBUILD=build/zbuild

if [ "$FORCE" -eq 0 ]; then
    [ -f "$MARKER" ] || exit 0
fi
for _t in "$TARGET" "$ZILC" "$ZBUILD"; do
    if [ ! -x "$_t" ]; then
        [ "$FORCE" -eq 0 ] && exit 0
        echo "$_t is not built; run make first" >&2
        exit 1
    fi
done

tmp="$(mktemp -d "${TMPDIR:-/tmp}/zoril_finalize_XXXXXX")"
trap 'rm -rf "$tmp"' EXIT INT TERM
ulimit -s 262144 2>/dev/null || true

# Each side build has the tool's own file name in another directory: ld records the object's name in the binary.
FINAL_DIR=build/final
A="$FINAL_DIR/gen1"
B="$FINAL_DIR/gen2"
clean() { rm -f "$A"/* "$B"/*; rmdir "$A" "$B" "$FINAL_DIR" 2>/dev/null || true; }
trap 'clean; rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$A" "$B"

# generation DIR ZORIL ZILC: build the three tools into DIR with the given compiler and zilc.
generation() {
    _dir="$1"
    _cc="$2"
    _zc="$3"
    for _spec in "zoril src/main.zrl -I src --runtime-first" "zilc tools/zilc/src/main.zrl -I src -I tools/zilc/src" \
                 "zbuild tools/zbuild/src/main.zrl -I src -I tools/zbuild/src"; do
        # shellcheck disable=SC2086
        set -- $_spec
        _name="$1"
        _src="$2"
        shift 2
        if ! ./scripts/build_zrl.sh "$_dir/$_name" "$_src" -I stdlib=stdlib "$@" -I build/gen --compiler "$_cc" --zilc "$_zc" > "$tmp/gen.log" 2>&1; then
            tail -40 "$tmp/gen.log" >&2
            echo "$_name: the rebuild failed" >&2
            return 1
        fi
    done
}

give_up() {
    echo "$1" >&2
    if [ "$FORCE" -eq 0 ]; then
        mv -f "$ZBUILD" "$ZBUILD.not-selfhosted"
        echo "moved $ZBUILD to $ZBUILD.not-selfhosted; the next make builds it and checks again" >&2
    fi
    exit 1
}

echo "Rebuilding zoril, zilc and zbuild with the finished toolchain to confirm they are identical..."
generation "$A" "./$TARGET" "./$ZILC" || give_up "the rebuild with the finished toolchain failed"

differ=""
for _name in zoril zilc zbuild; do
    case "$_name" in zoril) _bin="$TARGET" ;; zilc) _bin="$ZILC" ;; zbuild) _bin="$ZBUILD" ;; esac
    if cmp -s "$_bin" "$A/$_name"; then
        echo "  $_bin: identical"
    else
        differ="$differ $_name"
    fi
done

if [ -z "$differ" ]; then
    rm -f "$MARKER"
    exit 0
fi

echo "  made by other tools:$differ; checking that the rebuilt tools reproduce themselves..."
generation "$B" "./$A/zoril" "./$A/zilc" || give_up "the second rebuild, with the rebuilt tools, failed"

bad=""
for _name in zoril zilc zbuild; do
    cmp -s "$A/$_name" "$B/$_name" || bad="$bad $_name"
done
[ -z "$bad" ] || give_up "the rebuilt$bad differs between the first and the second rebuild: the toolchain does not reproduce itself"

for _name in $differ; do
    case "$_name" in zoril) _bin="$TARGET" ;; zilc) _bin="$ZILC" ;; zbuild) _bin="$ZBUILD" ;; esac
    mv -f "$A/$_name" "$_bin"
    echo "  $_bin: replaced by the one built by itself"
done
rm -f "$MARKER"
