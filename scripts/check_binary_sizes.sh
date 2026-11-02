#!/bin/sh
# scripts/check_binary_sizes.sh — README's compact-binary figures, measured against this tree
#
# Why. The README said "static executables start at ~17 KB (~13-15 KB stripped for a minimal
# executable)", and a reader found it wrong in both directions: a program that only returns was
# ~10 KB, and the getting-started hello world was ~20 KB whole-program and ~32 KB through zbuild.
# A published figure that nothing measures rots the same way, so this gate is the measure.
#
# What it reads: README.md's "Compact Native Binaries" bullet, whose six `**~N KB**` figures are, in
# the order it states them, the do-nothing program as linked and stripped, the getting-started hello
# world as linked and stripped, and the same hello world through `zbuild` as linked and stripped.
# It builds those three the way the guides do (zoril -> zilc -> qbe -> as -> ld, and `zbuild` for the
# third), measures the bytes, and fails when a measured size is more than 10% from its figure. A
# figure whose text cannot be found is a failure too: a gate that silently checks nothing is worse
# than none.
#
# Platform: the figures are Linux x86-64 static ELF from this tree's QBE, as and ld, so anywhere else
# the gate reports [SKIP] naming the platform. Portability work will need a figure per platform (and
# a per-platform comparison here) rather than one 10% band across all of them.
#
# Usage: check_binary_sizes.sh             check (the `binary-sizes` gate in make test)
#        check_binary_sizes.sh --report    print the measured sizes without comparing
#        check_binary_sizes.sh --selftest
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
README="$REPO_ROOT/README.md"
TOLERANCE=10     # percent

# figures_of — the `**~N KB**` numbers in the Compact Native Binaries bullet, one per line, in order.
figures_of() {
    awk '/^- \*\*Compact Native Binaries:\*\*/ { on = 1 }
         on && /^- \*\*/ && $0 !~ /Compact Native Binaries/ { exit }
         on { print }' "$1" \
        | grep -oE '\*\*~[0-9]+(\.[0-9]+)? KB\*\*' \
        | sed 's/^\*\*~//; s/ KB\*\*$//'
}

# check_figure LABEL DOCUMENTED_KB MEASURED_BYTES — print the result line, status 0 within TOLERANCE.
check_figure() {
    awk -v label="$1" -v kb="$2" -v got="$3" -v tol="$TOLERANCE" 'BEGIN {
        doc = kb * 1024
        diff = got - doc
        if (diff < 0) diff = -diff
        pct = (doc > 0) ? diff * 100 / doc : 100
        if (pct <= tol)
            printf "[PASS] binary-sizes: %s is %d B (%s KB), figure ~%s KB - %.1f%% away\n", label, got, sprintf("%.1f", got / 1024), kb, pct
        else
            printf "[FAIL] binary-sizes: %s is %d B (%s KB), figure ~%s KB - %.1f%% away, more than %d%%: update README.md\n", label, got, sprintf("%.1f", got / 1024), kb, pct, tol
        exit(pct <= tol ? 0 : 1)
    }'
}

if [ "${1:-}" = "--selftest" ]; then
    tmp="${TMPDIR:-/tmp}/check_binary_sizes_selftest.$$"
    mkdir -p "$tmp" || exit 2
    fail=0

    # A bullet with six figures parses to six, in order; one with five is reported as short.
    cat > "$tmp/six.md" <<'EOF'
- **Compact Native Binaries:** is **~10 KB** (**~8.5 KB** stripped), then **~20 KB** (**~14 KB** stripped), then **~32 KB** (**~23 KB** stripped).
- **Next Bullet:** not part of it, **~99 KB**.
EOF
    n=$(figures_of "$tmp/six.md" | wc -l | tr -d ' ')
    [ "$n" -eq 6 ] || { echo "[FAIL] selftest: parsed $n figures, expected 6"; fail=1; }
    first=$(figures_of "$tmp/six.md" | head -1)
    [ "$first" = "10" ] || { echo "[FAIL] selftest: first figure is '$first', expected 10"; fail=1; }
    last=$(figures_of "$tmp/six.md" | tail -1)
    [ "$last" = "23" ] || { echo "[FAIL] selftest: last figure is '$last', expected 23"; fail=1; }
    printf -- '- **Compact Native Binaries:** **~10 KB** **~8.5 KB** **~20 KB** **~14 KB** **~32 KB**\n' > "$tmp/five.md"
    n=$(figures_of "$tmp/five.md" | wc -l | tr -d ' ')
    [ "$n" -eq 5 ] || { echo "[FAIL] selftest: a five-figure bullet parsed to $n"; fail=1; }

    # The band: exactly 10% away passes, a bit past it fails.
    check_figure "selftest-at-band" 10 11264 > "$tmp/at.log" 2>&1 || fail=1
    grep -q '^\[PASS\]' "$tmp/at.log" || { echo "[FAIL] selftest: 10% away was not accepted"; cat "$tmp/at.log"; fail=1; }
    check_figure "selftest-past-band" 10 11265 > "$tmp/past.log" 2>&1 && fail=1
    grep -q '^\[FAIL\]' "$tmp/past.log" || { echo "[FAIL] selftest: past 10% was not refused"; cat "$tmp/past.log"; fail=1; }
    check_figure "selftest-exact" 8.5 8704 > "$tmp/exact.log" 2>&1 || fail=1
    grep -q '^\[PASS\]' "$tmp/exact.log" || { echo "[FAIL] selftest: an exact figure was not accepted"; cat "$tmp/exact.log"; fail=1; }

    rm -rf "$tmp"
    [ "$fail" -eq 0 ] || exit 1
    echo "[PASS] binary-sizes: selftest passed"
    exit 0
fi

# Linux x86-64 is where the figures were measured; elsewhere a different figure is needed, not a
# looser band.
os=$(uname -s 2>/dev/null || echo unknown)
arch=$(uname -m 2>/dev/null || echo unknown)
if [ "$os" != "Linux" ] || [ "$arch" != "x86_64" ]; then
    echo "[SKIP] binary-sizes: the figures describe Linux x86-64 static ELF (this is $os $arch); they need a per-platform figure"
    exit 0
fi
[ -f "$README" ] || { echo "[FAIL] binary-sizes: $README is missing"; exit 1; }
ZORIL="$REPO_ROOT/build/zoril"
ZILC="$REPO_ROOT/build/zilc"
ZBUILD="$REPO_ROOT/build/zbuild"
RUNTIME="$REPO_ROOT/build/runtime.o"
BACKEND=${BACKEND_BIN:-qbe}
ASM=${ASSEMBLER_BIN:-as}
LNK=${LINKER_BIN:-ld}
STRIP=${STRIP:-strip}
for t in "$ZORIL" "$ZILC" "$ZBUILD" "$RUNTIME"; do
    [ -e "$t" ] || { echo "[FAIL] binary-sizes: $t is missing (run make)"; exit 1; }
done
if ! command -v "$STRIP" >/dev/null 2>&1; then
    echo "[SKIP] binary-sizes: no strip(1), so the stripped figures cannot be measured"
    exit 0
fi

W="$REPO_ROOT/build/tests/binary-sizes.$$"
mkdir -p "$W" || exit 1
ok=0
cleanup() { if [ "$ok" -eq 1 ]; then rm -rf "$W"; fi; return 0; }
trap cleanup EXIT INT TERM

# The two programs: the guide's hello world (extracted, so the figure describes the program the
# README names) and a do-nothing program.
awk '/^```zoril,file=hello\.zrl$/ { on = 1; next } on && /^```$/ { exit } on { print }' \
    "$REPO_ROOT/doc/getting_started.md" > "$W/hello.zrl"
[ -s "$W/hello.zrl" ] || { echo "[FAIL] binary-sizes: the hello world snippet was not found in doc/getting_started.md"; exit 1; }
printf 'fn main() -> i32 { return 42; }\n' > "$W/bare.zrl"

build() { # build NAME SRC
    "$ZORIL" -I stdlib=stdlib --emit-zil -o "$W/$1.zil" "$2" &&
    "$ZILC" "$W/$1.zil" "$W/$1.ssa" &&
    "$BACKEND" -o "$W/$1.s" "$W/$1.ssa" &&
    "$ASM" -o "$W/$1.o" "$W/$1.s" &&
    "$LNK" -o "$W/$1" "$W/$1.o" "$RUNTIME"
}
build bare "$W/bare.zrl" || { echo "[FAIL] binary-sizes: the do-nothing program did not build"; exit 1; }
build hello "$W/hello.zrl" || { echo "[FAIL] binary-sizes: the hello world did not build"; exit 1; }
"$ZBUILD" -I stdlib=stdlib --runtime "$RUNTIME" -o "$W/hello_zbuild" "$W/hello.zrl" > "$W/zbuild.log" 2>&1 \
    || { echo "[FAIL] binary-sizes: zbuild did not build the hello world:"; sed 's/^/       /' "$W/zbuild.log"; exit 1; }

size_of() { wc -c < "$1" | tr -d ' '; }
for f in bare hello hello_zbuild; do
    cp "$W/$f" "$W/$f.stripped" && "$STRIP" "$W/$f.stripped" \
        || { echo "[FAIL] binary-sizes: $STRIP failed on $f"; exit 1; }
done
got_bare=$(size_of "$W/bare")
got_bare_s=$(size_of "$W/bare.stripped")
got_hello=$(size_of "$W/hello")
got_hello_s=$(size_of "$W/hello.stripped")
got_zbuild=$(size_of "$W/hello_zbuild")
got_zbuild_s=$(size_of "$W/hello_zbuild.stripped")

if [ "${1:-}" = "--report" ]; then
    printf 'bare as linked:        %s B\nbare stripped:         %s B\nhello as linked:       %s B\nhello stripped:        %s B\nhello via zbuild:      %s B\nhello zbuild stripped: %s B\n' \
        "$got_bare" "$got_bare_s" "$got_hello" "$got_hello_s" "$got_zbuild" "$got_zbuild_s"
    exit 0
fi

figures=$(figures_of "$README")
count=$(printf '%s\n' "$figures" | grep -c . || true)
if [ "$count" -ne 6 ]; then
    echo "[FAIL] binary-sizes: README.md's Compact Native Binaries bullet carries $count of the six ~N KB figures it needs (do-nothing as linked and stripped, hello world as linked and stripped, hello world through zbuild as linked and stripped)"
    exit 1
fi
f1=$(printf '%s\n' "$figures" | sed -n 1p)
f2=$(printf '%s\n' "$figures" | sed -n 2p)
f3=$(printf '%s\n' "$figures" | sed -n 3p)
f4=$(printf '%s\n' "$figures" | sed -n 4p)
f5=$(printf '%s\n' "$figures" | sed -n 5p)
f6=$(printf '%s\n' "$figures" | sed -n 6p)

bad=0
check_figure "the do-nothing program, as linked" "$f1" "$got_bare" || bad=$((bad + 1))
check_figure "the do-nothing program, stripped" "$f2" "$got_bare_s" || bad=$((bad + 1))
check_figure "the hello world, as linked" "$f3" "$got_hello" || bad=$((bad + 1))
check_figure "the hello world, stripped" "$f4" "$got_hello_s" || bad=$((bad + 1))
check_figure "the hello world through zbuild, as linked" "$f5" "$got_zbuild" || bad=$((bad + 1))
check_figure "the hello world through zbuild, stripped" "$f6" "$got_zbuild_s" || bad=$((bad + 1))

if [ "$bad" -ne 0 ]; then
    echo "       measured in $W; 'scripts/check_binary_sizes.sh --report' prints the sizes to paste in"
    exit 1
fi
ok=1
exit 0
