#!/bin/sh
# scripts/qbe_fingerprint.sh — Identify a QBE by what it writes, since it has no version flag.
#
#   scripts/qbe_fingerprint.sh [--verbose] [QBE]     QBE defaults to $BACKEND_BIN, then qbe
#
# Compiles the fixed SSA files in scripts/qbe_probe/ for amd64_sysv and prints one line,
#   qbe_fingerprint: <sha256>
# a hash over the SHA-256 of each output. QBE is deterministic, so two builds of the same source give the
# same line whatever compiled them or which distribution packaged them, and two builds whose register
# allocation or instruction selection differ give different lines. --verbose adds one line per fixture,
# which says where two QBEs part ways. scripts/qbe_pins.tsv names the fingerprints seen so far.
#
# The fixtures are small static files, so a change to the compiler never moves a fingerprint, only a
# different QBE does. diff_*.ssa are the smallest programs found on which two QBE builds already part
# ways (six values live across a call: the builds spill a different one); diff_driver.ssa is the same
# thing cut down from a real function. shape_*.ssa cover other instruction groups, on which the known
# builds agree, so that a build that differs there is told apart too.
#
# Exit 0 with a fingerprint, 1 when the QBE cannot compile a fixture (the line then says unknown).
set -eu

case "$0" in */*) cd "${0%/*}/.." ;; *) cd .. ;; esac || exit 2
. scripts/lib/portability.sh

VERBOSE=0
if [ "${1:-}" = "--verbose" ]; then VERBOSE=1; shift; fi
QBE="${1:-${BACKEND_BIN:-qbe}}"

if ! command -v "$QBE" >/dev/null 2>&1; then
    echo "qbe_fingerprint: unknown ($QBE not found)"
    exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/qbe_fingerprint_XXXXXX")"
trap 'rm -rf "$tmp"' EXIT INT TERM

: > "$tmp/lines"
set -- scripts/qbe_probe/*.ssa
if [ ! -f "$1" ]; then
    echo "qbe_fingerprint: unknown (no fixtures in scripts/qbe_probe/ of $(pwd))"
    exit 1
fi
for fixture in "$@"; do
    name="${fixture##*/}"
    if ! "$QBE" -t amd64_sysv -o "$tmp/out.s" "$fixture" > "$tmp/err" 2>&1; then
        echo "qbe_fingerprint: unknown ($QBE could not compile $name: $(head -n1 "$tmp/err"))"
        exit 1
    fi
    printf '%s %s\n' "$name" "$(sha256_of "$tmp/out.s" | awk '{print $1}')" >> "$tmp/lines"
done

echo "qbe_fingerprint: $(sha256_of "$tmp/lines" | awk '{print $1}')"
if [ "$VERBOSE" -eq 1 ]; then
    sed 's/^/  /' "$tmp/lines"
fi
