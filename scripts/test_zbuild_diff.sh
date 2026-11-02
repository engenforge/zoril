#!/bin/sh
# scripts/test_zbuild_diff.sh — the suite's programs, built the way a user builds them, agree.
#
# Every gate before this one built programs with the whole-program compiler from the repository, which
# is what developers run. A user runs an installed `zbuild` (README recommends it), and the two paths
# disagreed in ways no gate saw: a module whose name starts with a digit, an interface that lost a
# `#[borrows]`, a static copied into the importer. This installs the toolchain into a scratch prefix
# (`make install DESTDIR=build/zbuild-diff/stage PREFIX=/usr`) and, for every runnable program of
# tests/ and corpus/zrl/, builds it twice - the installed `zoril`/`zilc`/`qbe`/`as`/`ld` pipeline and the
# installed `zbuild`, each from a scratch directory, stdin from /dev/null - and requires
#   (a) the header's exit status from both,
#   (b) the same stdout from both,
#   (c) no warning from zbuild that the whole-program build does not print.
# A program allowed to differ is listed in tests/zbuild_diff_allow.list with its reason and the
# KNOWN_ISSUES.md entry that documents it; an entry that no longer differs fails the gate, as a closed
# gap fails the safety matrix. The include roots are the ones the runner passes; the test's own
# directory is left out when it is named `stdlib`, which would hide the installed standard library
# (a directory merely named so is U5's question).
cd "$(dirname "$0")/.." || exit 2
. scripts/env.sh
. scripts/lib/portability.sh
ALLOW=tests/zbuild_diff_allow.list
WORK=build/zbuild-diff
STAGE="$WORK/stage"
JOBS=$(nproc_count 2>/dev/null || echo 4)
BACKEND=${BACKEND_BIN:-qbe}
ASM=${ASSEMBLER_BIN:-as}
LINK=${LINKER_BIN:-ld}
fail() { echo "[FAIL] zbuild-diff: $1"; [ -n "${2:-}" ] && sed 's/^/       /' "$2"; exit 1; }

start=$(date +%s)
rm -rf "$WORK"
mkdir -p "$WORK"
make install-files DESTDIR="$(pwd)/$STAGE" PREFIX=/usr > "$WORK/install.log" 2>&1 || fail "make install into the stage failed" "$WORK/install.log"
BIN="$(pwd)/$STAGE/usr/bin"
RT="$(pwd)/$STAGE/usr/lib/zoril/runtime.o"
[ -x "$BIN/zbuild" ] && [ -f "$RT" ] || fail "the staged install lacks zbuild or the runtime"

find tests corpus/zrl -type f -name '*.zrl' ! -name '*_lib.zrl' ! -name '.*' \
    ! -path '*/include/*' ! -path '*/test_include/*' ! -path '*/helpers/*' ! -path '*/lib/*' \
    ! -path '*/incremental/*' ! -path '*/modular/*' ! -path '*/fixtures/*' ! -path '*/fmt/*' \
    ! -path 'tests/error_reporting/*' | sort > "$WORK/candidates.txt"

cat > "$WORK/worker.sh" << 'EOF'
#!/bin/sh
. scripts/lib/portability.sh
# worker.sh WORK BIN RT BACKEND ASM LINK FILE... -> one line per runnable program: "OK|DIFF|SKIP <file> <why>"
WORK="$1"; BIN="$2"; RT="$3"; BACKEND="$4"; ASM="$5"; LINK="$6"; shift 6
INC="-I src -I tools/zilc/src -I tests -I tests/include -I tests/helpers"
for f in "$@"; do
    eval "$(awk '
        function q(v) { gsub(/\047/, "\047\\\047\047", v); return "\047" v "\047" }
        /^[ \t]*\/\/[ \t]*@skip:/ { skip = 1 }
        flags == "" && /^\/\/ flags: / { v = $0; sub(/^\/\/ flags: /, "", v); flags = v }
        /^\/\/ link: / { v = $0; sub(/^\/\/ link: /, "", v); link = link v " " }
        /expected compile fail/ { cfail = 1 }
        /expected compile success/ { csucc = 1 }
        /^\/\/ EXPECT: / { ex_diag = 1 }
        ex == "" && match($0, /expected exit( code:)? [0-9]+/) { v = substr($0, RSTART, RLENGTH); sub(/.* /, "", v); ex = v }
        END { printf "h_skip=%d h_flags=%s h_link=%s h_cfail=%d h_csucc=%d h_diag=%d h_exit=%s\n", skip, q(flags), q(link), cfail, csucc, ex_diag, q(ex) }' "$f")"
    [ "$h_skip" -eq 0 ] && [ "$h_cfail" -eq 0 ] && [ "$h_csucc" -eq 0 ] && [ "$h_diag" -eq 0 ] || continue
    h_exit=${h_exit:-0}   # no header: a run test that expects 0, as the runner reads it
    d="$WORK/p/$(printf '%s' "$f" | tr / +)"
    mkdir -p "$d"
    zflags=""
    for fl in $h_flags; do
        case "$fl" in
            --checked|--hosted) zflags="$zflags $fl" ;;
            *) echo "SKIP $f flag $fl is not a zbuild option"; continue 2 ;;
        esac
    done
    case "$zflags" in *--hosted*) echo "SKIP $f --hosted needs cc and the hosted runtime"; continue ;; esac
    case "$(basename "$(dirname "$f")")" in stdlib) own="" ;; *) own="-I $(dirname "$f")" ;; esac
    extra=""; zlink=""; n=0
    for s in $h_link; do
        n=$((n + 1))
        "$ASM" -o "$d/link$n.o" "$s" || { echo "DIFF $f cannot assemble $s"; continue 2; }
        extra="$extra $d/link$n.o"; zlink="$zlink --link-object $d/link$n.o"
    done
    # The whole-program pipeline, from the installed tools.
    if "$BIN/zoril" $INC $own --emit-zil -o "$d/w.zil" $h_flags "$f" > "$d/w.log" 2>&1 \
       && "$BIN/zilc" "$d/w.zil" "$d/w.ssa" >> "$d/w.log" 2>&1 \
       && "$BACKEND" -o "$d/w.s" "$d/w.ssa" >> "$d/w.log" 2>&1 \
       && "$ASM" -o "$d/w.o" "$d/w.s" >> "$d/w.log" 2>&1 \
       && "$LINK" -o "$d/w.bin" "$RT" "$d/w.o" $extra >> "$d/w.log" 2>&1; then
        { run_with_timeout -k 2s 30s "$d/w.bin" < /dev/null > "$d/w.out" 2> /dev/null; } 2> /dev/null; wrc=$?
    else
        echo "DIFF $f the whole-program build failed"; continue
    fi
    if "$BIN/zbuild" $INC $own --cache-dir "$d/cache" -o "$d/z.bin" $zflags $zlink "$f" > "$d/z.log" 2>&1; then
        { run_with_timeout -k 2s 30s "$d/z.bin" < /dev/null > "$d/z.out" 2> /dev/null; } 2> /dev/null; zrc=$?
    else
        echo "DIFF $f zbuild failed: $(grep -m1 -E 'error|ld:' "$d/z.log" | cut -c1-120)"; continue
    fi
    why=""
    [ "$wrc" -eq "$h_exit" ] || why="the whole-program build exits $wrc, the header says $h_exit"
    [ -z "$why" ] && [ "$zrc" -ne "$h_exit" ] && why="zbuild's program exits $zrc, the header says $h_exit"
    [ -z "$why" ] && ! cmp -s "$d/w.out" "$d/z.out" && why="stdout differs"
    if [ -z "$why" ]; then
        grep 'warning:' "$d/w.log" | sort -u > "$d/w.warn"
        grep 'warning:' "$d/z.log" | sort -u > "$d/z.warn"
        extra_warn=$(comm -13 "$d/w.warn" "$d/z.warn" | head -n 1)
        [ -n "$extra_warn" ] && why="zbuild warns where the whole-program build does not: $extra_warn"
    fi
    if [ -n "$why" ]; then echo "DIFF $f $why"; else echo "OK $f"; fi
done
EOF
chmod +x "$WORK/worker.sh"
xargs -P "$JOBS" -n 6 "$WORK/worker.sh" "$(pwd)/$WORK" "$BIN" "$RT" "$BACKEND" "$ASM" "$LINK" < "$WORK/candidates.txt" | sort > "$WORK/results.txt"

total=$(grep -c . "$WORK/results.txt"); ok=$(grep -c '^OK ' "$WORK/results.txt"); skipped=$(grep -c '^SKIP ' "$WORK/results.txt")
grep '^DIFF ' "$WORK/results.txt" | awk '{print $2}' | sort > "$WORK/diff_names.txt"
touch "$ALLOW"
grep -v '^[[:space:]]*#' "$ALLOW" | awk 'NF {print $1}' | sort > "$WORK/allowed_names.txt"
comm -23 "$WORK/diff_names.txt" "$WORK/allowed_names.txt" > "$WORK/unexpected.txt"
comm -13 "$WORK/diff_names.txt" "$WORK/allowed_names.txt" > "$WORK/stale.txt"
if [ -s "$WORK/unexpected.txt" ]; then
    echo "[FAIL] zbuild-diff: $(grep -c . "$WORK/unexpected.txt") program(s) differ between the whole-program build and zbuild:"
    while read -r p; do grep "^DIFF $p " "$WORK/results.txt" | head -n 1 | sed 's/^/       /'; done < "$WORK/unexpected.txt" | head -n 15
    exit 1
fi
if [ -s "$WORK/stale.txt" ]; then
    echo "[FAIL] zbuild-diff: $(grep -c . "$WORK/stale.txt") allowed program(s) no longer differ; remove them from $ALLOW:"
    sed 's/^/       /' "$WORK/stale.txt" | head -n 15
    exit 1
fi
echo "[PASS] zbuild-diff: $ok of $total programs agree between the whole-program build and the installed zbuild ($skipped skipped, $(grep -c . "$WORK/allowed_names.txt") allowed to differ) in $(( $(date +%s) - start )) s"
