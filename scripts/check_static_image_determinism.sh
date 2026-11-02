#!/bin/sh
# scripts/check_static_image_determinism.sh — a global's data image is a function of its source.
#
# Every `static`'s and `const`'s bytes are written into a buffer zero-filled to the declared type's
# size, so the image a build emits is the constant's own bytes and nothing else. The path this
# replaced (extract_const_u64, until 2026-10-13) allocated 8 bytes and told the IL the data was the
# declared size, so a type wider than 8 bytes copied whatever followed those bytes in the compiler's
# heap into the object file: `struct Big { a: u64, b: u64, c: u64 } static B: Big = 7;` emitted 8
# bytes of 7 and then 16 bytes of heap addresses, and those bytes differed between a plain run and a
# `-v` one (measured 2026-10-13) - one unreproducible binary per such program.
#
# The check compiles one probe twice, with the compiler in two different heap states (verbose mode
# allocates as it reports, a plain run does not), and requires the two outputs to be identical. The
# probe covers every image shape, and its canary is the shape whose image is *only* partly written:
# an enum variant with no payload inside an enum that has one (`static MIXED: Mixed = Mixed.A`),
# whose payload and padding must come from the zero fill.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

ZORIL=${ZORIL_CC:-./build/zoril}
if [ ! -x "$ZORIL" ]; then
    echo "[FAIL] static-image: no compiler at $ZORIL (build it first)"
    exit 1
fi

WORK=${STATIC_IMAGE_WORK:-build/static-image}
rm -rf "$WORK"
mkdir -p "$WORK"

cat > "$WORK/probe.zrl" <<'ZRL'
enum Mixed { A = 3, B(u64) }
enum Maybe { Nothing, Something(u32) }

const NEG: i32 = -7;
const HALF: i32 = NEG / 2;
const MASK: u8 = !0;
const PI: f64 = 3.5;
const NAME: [u8; 5] = "hello";
static MIXED: Mixed = Mixed.A;
static NONE: Maybe = Maybe.Nothing;
static mut COUNTER: u64 = 1 + 2 * 3;
static FLAG: bool = true;

fn main() -> i32 { return 0; }
ZRL

fail=0
note() { echo "[FAIL] static-image: $*"; fail=1; }
ok()   { echo "[PASS] static-image: $*"; }

if ! "$ZORIL" -o "$WORK/plain.zil" "$WORK/probe.zrl" > "$WORK/plain.log" 2>&1; then
    note "the probe does not compile:"
    sed 's/^/       /' "$WORK/plain.log"
    exit 1
fi
if ! "$ZORIL" -v -o "$WORK/verbose.zil" "$WORK/probe.zrl" > "$WORK/verbose.log" 2>&1; then
    note "the probe does not compile with -v:"
    sed 's/^/       /' "$WORK/verbose.log"
    exit 1
fi

if cmp -s "$WORK/plain.zil" "$WORK/verbose.zil"; then
    n_globals=$(grep -c '^global' "$WORK/plain.zil")
    ok "the probe's $n_globals global images are the same in a plain and a -v run"
else
    note "the same source compiled twice gives different images (compiler heap in the output?):"
    diff "$WORK/plain.zil" "$WORK/verbose.zil" | sed 's/^/       /' | head -20
fi

# image_of FILE NAME — the emitted byte list of the global NAME, comma-separated.
image_of() {
    sed -n "s/.* $2 = {\(.*\)}$/\1/p" "$1" | head -n 1
}

# The partly-written image: the tag, then only zeros. A payload or padding byte that is not a zero
# is compiler memory that leaked into the data section.
mixed=$(image_of "$WORK/plain.zil" MIXED)
if [ -z "$mixed" ]; then
    note "no MIXED global in the output: the probe did not lower as expected"
else
    mixed_tail=$(printf '%s' "$mixed" | tr -d ' ' | sed 's/^3,//')
    case "$mixed_tail" in
    ''|*[!0,]*) note "MIXED's image is not the tag 3 followed by zeros: {$mixed}" ;;
    *)          ok "the partly-specified image (an enum's payload and padding) is zero-filled" ;;
    esac
fi

if [ "$fail" -ne 0 ]; then
    echo "FAIL: a global's image is not a function of its source."
    exit 1
fi
echo "PASS: a global's image is a function of its source."
