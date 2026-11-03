#!/bin/sh
# scripts/check_store_grid_modular.sh — the store grid's two-module cells (run by check_store_grid.sh).
#
# A call summary is read from the callee's source in a whole-program build and from its interface (.zri)
# in a separate one, and the two can disagree: a separately compiled callee once recorded an empty store
# summary. So the cells whose path goes through a free function are also built the way zbuild builds
# them: `store_grid.lua --generate-modular` puts the path's functions in a module of their own,
# pathmod.zrl; it is compiled with `-c --write-interface`, and the cell with `-c --iface-dir`, reading
# that interface instead of the source. The cells are the direct carrier with the frame_ends
# invalidation, over every source and destination (store_grid.lua says why).
#
# Each cell is judged as in the whole-program grid: an unsafe cell that compiles is a failing cell, a
# twin refused for a safety reason is an over-rejection, any other refusal is a generator error. The
# failing cells and the refused twins must match bench/fuzz/store_grid_modular_expected_failures.txt and
# store_grid_modular_twin_rejections.txt; --record rewrites both.
#
# The interface is looked up at `<iface-dir>/<key>.zri`, the key being the module's path from the
# repository root with `/` as `%2F`. A key that misses makes the compiler read the source without a word,
# which would turn this whole gate into a second whole-program run; so the first cell is also compiled
# against an empty interface, which must fail.
#
# Usage: check_store_grid_modular.sh [--record] [--jobs N]
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 2
. scripts/lib/portability.sh

ZORIL=${ZORIL_CC:-$REPO_ROOT/build/zoril}
JOBS=$(nproc_count 2>/dev/null || echo 4)
RECORD=0
WORK_DIR=build/store_grid_modular
EXPECTED_FILE=bench/fuzz/store_grid_modular_expected_failures.txt
TWINS_FILE=bench/fuzz/store_grid_modular_twin_rejections.txt
while [ $# -gt 0 ]; do
    case "$1" in
        --record) RECORD=1; shift ;;
        --jobs|-j) JOBS="$2"; shift 2 ;;
        *) echo "Usage: $0 [--record] [--jobs N]" >&2; exit 2 ;;
    esac
done
# One list of safety diagnostics for both grids: check_store_grid.sh passes it, or it is read from there.
SAFETY_REGEX=${STORE_GRID_SAFETY_REGEX:-$(sed -n 's/^SAFETY_REGEX="\(.*\)"$/\1/p' scripts/check_store_grid.sh)}
if [ -z "$SAFETY_REGEX" ]; then
    echo "[FAIL] store-grid-modular: no safety diagnostic list (SAFETY_REGEX in scripts/check_store_grid.sh)"
    exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
lua scripts/fuzz/store_grid.lua --generate-modular "$WORK_DIR" > /dev/null
MANIFEST="$WORK_DIR/manifest.txt"
if [ ! -s "$MANIFEST" ]; then
    echo "[FAIL] store-grid-modular: the generator wrote no two-module cells"
    exit 1
fi
TOTAL=$(wc -l < "$MANIFEST" | tr -d ' ')

# key DIR — the interface file name the compiler looks pathmod up by.
key() { printf '%s' "$1/pathmod" | sed 's|/|%2F|g'; }

first=$(head -n 1 "$MANIFEST")
d="$WORK_DIR/$first"
k=$(key "$d")
mkdir -p "$d/empty"
printf '// zri-module: %s/pathmod.zrl\n' "$d/pathmod" > "$d/empty/$k.zri"
guard_fn=$(sed -n 's/^pub fn \([A-Za-z0-9_]*\).*/\1/p' "$d/pathmod.zrl" | head -n 1)
if guard_out=$(run_with_timeout -k 2s 60s "$ZORIL" -c -I stdlib=stdlib -I "$d" --interproc-summary --iface-dir "$d/empty" \
        -o /dev/null "$d/twin.zrl" 2>&1 < /dev/null); then
    echo "[FAIL] store-grid-modular: $first compiled against an empty interface - the interface is not being read"
    exit 1
fi
# Refusing is not enough: the refusal must be the one an interface that lacks the function gives, naming
# that function, or the guard would pass on any unrelated error (a bad path, a crashed compiler).
if [ -z "$guard_fn" ] || ! printf '%s\n' "$guard_out" | grep -F "defines no" | grep -qF "$guard_fn"; then
    echo "[FAIL] store-grid-modular: the empty-interface guard for $first was refused for another reason (expected 'the module defines no $guard_fn'):"
    printf '%s\n' "$guard_out" | head -n 3 | cut -c1-200 | sed 's/^/       /'
    exit 1
fi

WORKER="$WORK_DIR/worker.sh"
cat << 'EOF' > "$WORKER"
#!/bin/sh
. scripts/lib/portability.sh
ZORIL="$1"; WORK_DIR="$2"; SAFETY_REGEX="$3"; shift 3
for cell in "$@"; do
    d="$WORK_DIR/$cell"
    k=$(printf '%s' "$d/pathmod" | sed 's|/|%2F|g')
    mkdir -p "$d/iface"
    if ! out=$(run_with_timeout -k 2s 60s "$ZORIL" -c -I stdlib=stdlib -I "$d" --interproc-summary \
            --write-interface "$d/iface/$k.zri" -o "$d/pathmod.zil" "$d/pathmod.zrl" 2>&1 < /dev/null); then
        echo "GEN_ERR callee $cell: $out" | head -n 1
        continue
    fi
    for side in unsafe twin; do
        if out=$(run_with_timeout -k 2s 60s "$ZORIL" -c -I stdlib=stdlib -I "$d" --interproc-summary \
                --iface-dir "$d/iface" -o /dev/null "$d/$side.zrl" 2>&1 < /dev/null); then
            [ "$side" = unsafe ] && echo "UNSAFE_FAIL $cell"
        elif printf '%s\n' "$out" | grep -q -E "$SAFETY_REGEX"; then
            [ "$side" = twin ] && echo "TWIN_REJECT $cell"
        else
            echo "GEN_ERR $side $cell: $(printf '%s' "$out" | head -n 1)"
        fi
    done
done
EOF
chmod +x "$WORKER"
xargs -P "$JOBS" -n 10 "$WORKER" "$ZORIL" "$WORK_DIR" "$SAFETY_REGEX" < "$MANIFEST" > "$WORK_DIR/results.raw"
grep '^UNSAFE_FAIL ' "$WORK_DIR/results.raw" | awk '{print $2}' | sort > "$WORK_DIR/failing.txt"
grep '^TWIN_REJECT ' "$WORK_DIR/results.raw" | awk '{print $2}' | sort > "$WORK_DIR/twins.txt"
grep '^GEN_ERR ' "$WORK_DIR/results.raw" > "$WORK_DIR/generator_errors.txt"
FAILING=$(wc -l < "$WORK_DIR/failing.txt" | tr -d ' ')
TWINS=$(wc -l < "$WORK_DIR/twins.txt" | tr -d ' ')
GEN_ERRS=$(wc -l < "$WORK_DIR/generator_errors.txt" | tr -d ' ')

if [ "$GEN_ERRS" -gt 0 ]; then
    echo "[FAIL] store-grid-modular: $GEN_ERRS generator error(s) detected (must be 0):"
    head -n 10 "$WORK_DIR/generator_errors.txt" | cut -c1-200 | sed 's/^/       /'
    exit 1
fi

if [ "$RECORD" -eq 1 ]; then
    cp "$WORK_DIR/failing.txt" "$EXPECTED_FILE"
    cp "$WORK_DIR/twins.txt" "$TWINS_FILE"
    echo "[RECORD] store-grid-modular: $FAILING failing cells to $EXPECTED_FILE, $TWINS over-rejected twins to $TWINS_FILE ($TOTAL two-module cells)"
    exit 0
fi

for f in "$EXPECTED_FILE" "$TWINS_FILE"; do
    if [ ! -f "$f" ]; then
        echo "[FAIL] store-grid-modular: $f not found (run check_store_grid.sh --record to create it)"
        exit 1
    fi
done
# compare LABEL ACTUAL EXPECTED — fail on a difference in either direction.
compare() {
    sort "$3" > "$WORK_DIR/expected.sorted"
    comm -23 "$2" "$WORK_DIR/expected.sorted" > "$WORK_DIR/new.txt"
    comm -13 "$2" "$WORK_DIR/expected.sorted" > "$WORK_DIR/gone.txt"
    if [ -s "$WORK_DIR/new.txt" ]; then
        echo "[FAIL] store-grid-modular: $(wc -l < "$WORK_DIR/new.txt" | tr -d ' ') $1 not in $3:"
        head -n 10 "$WORK_DIR/new.txt" | sed 's/^/       /'
        return 1
    fi
    if [ -s "$WORK_DIR/gone.txt" ]; then
        echo "[FAIL] store-grid-modular: $(wc -l < "$WORK_DIR/gone.txt" | tr -d ' ') entr(ies) of $3 no longer hold; remove them:"
        head -n 10 "$WORK_DIR/gone.txt" | sed 's/^/       /'
        return 1
    fi
    return 0
}
compare "unsafe cell(s) accepted" "$WORK_DIR/failing.txt" "$EXPECTED_FILE" || exit 1
compare "safe twin(s) refused" "$WORK_DIR/twins.txt" "$TWINS_FILE" || exit 1
echo "[PASS] store-grid-modular: all $FAILING expected failing cells match ($TOTAL two-module cells, $TWINS over-rejected twins, 0 generator errors)"
exit 0
