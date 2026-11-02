#!/bin/sh
# scripts/test_doc_snippets.sh [file.md...] — compile the Zoril code blocks in the docs.
#
# Every ```zoril block in the given Markdown files (default: the docs the public
# release exports) is compiled with zoril and lowered with zilc. A block that defines
# `fn main` is also linked and run from the repository root and must exit 0.
#
# The info string after `zoril` selects how a block is tested:
#   ```zoril               a complete module
#   ```zoril,wrap          statements; wrapped in `fn main() -> i32 { ... return 0; }`
#                          (leading import/use lines stay at module level), compiled only
#   ```zoril,compile-fail  must be rejected, with an error on the first line that has a
#                          `COMPILE ERROR` or `// error:` comment
#   ```zoril,no-test       not tested (grammar sketches, signatures, elided bodies)

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

COMPILER="${ZORIL_CC:-${ZORIL_BIN:-$REPO_ROOT/build/zoril}}"
ZILC="${ZILC_BIN:-$REPO_ROOT/build/zilc}"
RUNTIME="${RT_HOST:-${TR_RUNTIME:-$REPO_ROOT/build/runtime.o}}"
STDLIB="${STDLIB_DIR:-${ZORIL_STDLIB:-$REPO_ROOT/stdlib}}"
BACKEND="${BACKEND_BIN:-qbe}"
ASSEMBLER="${ASSEMBLER_BIN:-as}"
LINKER="${LINKER_BIN:-ld}"
TIMEOUT_DUR="${TR_TIMEOUT:-${TIMEOUT_SECS:-30}}"
case "$TIMEOUT_DUR" in
    *[smhd]) ;;
    *) TIMEOUT_DUR="${TIMEOUT_DUR}s" ;;
esac
TIMEOUT_CMD=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_CMD="timeout $TIMEOUT_DUR"

if [ $# -eq 0 ]; then
    set -- README.md CONTRIBUTING.md KNOWN_ISSUES.md doc/getting_started.md doc/tour.md \
        doc/STABILITY.md doc/zero_overhead.md doc/reproducible_builds.md doc/ROADMAP.md \
        doc/vision/why_zoril.md doc/language/*.md doc/spec/*.md doc/tools/*.md
fi

tmp="$(mktemp -d /tmp/zoril_doc_snippets_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT INT TERM

# Split the blocks into $tmp/b<N>.zrl; print "<N>\t<file>\t<line>\t<tags>" per block.
extract() {
    awk -v dir="$tmp" -v start="$2" '
        BEGIN { n = start }
        !in_block && /^ *```zoril([,a-zA-Z0-9._=-]*)?[ \t]*$/ {
            in_block = 1; n++
            match($0, /^ */); indent = RLENGTH
            tags = $0; sub(/^ *```zoril,?/, "", tags); sub(/[ \t]+$/, "", tags)
            printf "%d\t%s\t%d\t%s\n", n, FILENAME, FNR, tags
            out = dir "/b" n ".zrl"; printf "" > out
            next
        }
        in_block && /^ *```[ \t]*$/ { in_block = 0; close(out); next }
        in_block { print substr($0, 1, indent) ~ /^ *$/ ? substr($0, indent + 1) : $0 > out }
    ' "$1"
}

# Wrap a statement block in main, keeping its leading import/use lines at module level.
wrap() {
    awk '
        !body && /^(import|use)[ \t]/ { print; next }
        !body { body = 1; print "fn main() -> i32 {" }
        { print "    " $0 }
        END { if (!body) print "fn main() -> i32 {"; print "    return 0;"; print "}" }
    ' "$1"
}

: > "$tmp/index"
for f in "$@"; do
    [ -f "$f" ] || continue
    extract "$f" "$(wc -l < "$tmp/index")" >> "$tmp/index"
done

if [ ! -s "$tmp/index" ]; then
    echo "[FAIL] doc-snippets: no zoril code blocks found"
    exit 1
fi

failures=0
pass=0
skipped=0
fail() {
    echo "[FAIL] doc-snippets: $where: $1"
    sed "s|^|       |" "$2" | head -8
    failures=$((failures + 1))
}

tab="$(printf '\t')"
while IFS="$tab" read -r n file line tags; do
    where="$file:$line"
    src="$tmp/b$n.zrl"
    case ",$tags," in
        *,no-test,*) skipped=$((skipped + 1)); continue ;;
    esac
    case ",$tags," in
        *,wrap,*) wrap "$src" > "$tmp/w$n.zrl"; src="$tmp/w$n.zrl" ;;
    esac
    zil="$tmp/b$n.zil"
    if $TIMEOUT_CMD "$COMPILER" -I "stdlib=$STDLIB" -o "$zil" "$src" > "$tmp/log" 2>&1; then
        compiled=1
    else
        compiled=0
    fi
    case ",$tags," in
        *,compile-fail,*)
            # The error must be reported on the line the block marks, not anywhere.
            marked="$(grep -n -e 'COMPILE ERROR' -e '// error:' "$src" | cut -d: -f1 | head -1)"
            if [ $compiled -eq 1 ]; then
                echo "compiled, but the block is marked compile-fail" > "$tmp/log"
                fail "expected a compile error" "$tmp/log"
            elif [ -z "$marked" ]; then
                echo "mark the line that should fail with a 'COMPILE ERROR' or '// error:' comment" > "$tmp/log"
                fail "compile-fail block marks no line" "$tmp/log"
            elif ! grep -q ":$marked:[0-9]*: error" "$tmp/log"; then
                fail "no compile error on marked line $marked" "$tmp/log"
            else
                pass=$((pass + 1))
            fi
            continue
            ;;
    esac
    if [ $compiled -eq 0 ]; then
        fail "zoril failed" "$tmp/log"
        continue
    fi
    if ! $TIMEOUT_CMD "$ZILC" "$zil" "$tmp/b$n.ssa" > "$tmp/log" 2>&1; then
        fail "zilc failed" "$tmp/log"
        continue
    fi
    case ",$tags," in
        *,wrap,*) pass=$((pass + 1)); continue ;;
    esac
    if ! grep -q '^fn main(' "$src"; then
        pass=$((pass + 1))
        continue
    fi
    bin="$tmp/b$n"
    if ! { $TIMEOUT_CMD "$BACKEND" -o "$bin.s" "$tmp/b$n.ssa" &&
        $TIMEOUT_CMD "$ASSEMBLER" -o "$bin.o" "$bin.s" &&
        $TIMEOUT_CMD "$LINKER" -o "$bin" "$RUNTIME" "$bin.o"; } > "$tmp/log" 2>&1; then
        fail "build failed" "$tmp/log"
        continue
    fi
    rc=0
    $TIMEOUT_CMD "$bin" > "$tmp/log" 2>&1 < /dev/null || rc=$?
    if [ $rc -ne 0 ]; then
        fail "program exited with $rc" "$tmp/log"
        continue
    fi
    pass=$((pass + 1))
done < "$tmp/index"

if [ $failures -ne 0 ]; then
    echo "[FAIL] doc-snippets: $failures failed, $pass passed, $skipped not tested"
    exit 1
fi
echo "[PASS] doc-snippets: $pass blocks passed, $skipped not tested"
