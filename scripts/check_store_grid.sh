#!/bin/sh
# scripts/check_store_grid.sh — Gate: check the store-rule combinatorial grid
#
# Generates all source x carrier x path x destination x invalidation cells,
# runs the unsafe cells (which must be compile_reject) and safe twins (which must compile),
# verifies unsafe rejections are for safety reasons (zero generator errors),
# computes the soundness hole class report,
# verifies actual failing cells match bench/fuzz/store_grid_expected_failures.txt,
# and reports cell counts, class count, and status.
#
# Usage:
#   scripts/check_store_grid.sh [--jobs N] [--record] [--dir DIR] [--expected FILE] [--classes FILE]

set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/scripts/env.sh"
. "$REPO_ROOT/scripts/lib/portability.sh"

ZORIL=${ZORIL_CC:-$REPO_ROOT/build/zoril}
ZILC=${ZILC_BIN:-$REPO_ROOT/build/zilc}
BACKEND=${BACKEND_BIN:-qbe}
ASSEMBLER=${ASSEMBLER_BIN:-as}
LINKER=${LINKER_BIN:-ld}
RUNTIME=${TR_RUNTIME:-$REPO_ROOT/build/runtime.o}

JOBS=$(nproc_count 2>/dev/null || echo 4)
RECORD=0
WORK_DIR="$REPO_ROOT/build/store_grid"
EXPECTED_FILE="$REPO_ROOT/bench/fuzz/store_grid_expected_failures.txt"
TWINS_FILE="$REPO_ROOT/bench/fuzz/store_grid_twin_rejections.txt"
CLASSES_FILE="$REPO_ROOT/bench/fuzz/store_grid_classes.txt"

while [ $# -gt 0 ]; do
    case "$1" in
        --record) RECORD=1; shift ;;
        --jobs|-j) JOBS="$2"; shift 2 ;;
        --dir) WORK_DIR="$2"; shift 2 ;;
        --expected) EXPECTED_FILE="$2"; shift 2 ;;
        --classes) CLASSES_FILE="$2"; shift 2 ;;
        --twins) TWINS_FILE="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--jobs N] [--record] [--dir DIR] [--expected FILE] [--classes FILE] [--twins FILE]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

mkdir -p "$WORK_DIR"
mkdir -p "$(dirname "$EXPECTED_FILE")"
mkdir -p "$(dirname "$CLASSES_FILE")" "$(dirname "$TWINS_FILE")"

# Probes that crash on purpose must not write core dumps.
ulimit -c 0 2>/dev/null || true

START_TIME=$(date +%s)

# Step 1: Generate all grid cells and twins
lua "$REPO_ROOT/scripts/fuzz/store_grid.lua" --generate-all "$WORK_DIR" >/dev/null

MANIFEST="$WORK_DIR/manifest.txt"
if [ ! -f "$MANIFEST" ]; then
    echo "[FAIL] store-grid: failed to generate grid manifest"
    exit 1
fi

TOTAL_VALID=$(wc -l < "$MANIFEST" | tr -d ' ')
SUMMARY_TEXT=$(lua "$REPO_ROOT/scripts/fuzz/store_grid.lua" --summary)

# Step 2: Combined parallel check of unsafe cells and safe twins with right-reason oracle
# Safety diagnostic patterns (compiler store/escape and borrow-checker rejections)
SAFETY_REGEX="cannot store|cannot return|region escape|cannot mutably borrow|cannot borrow|while it is .*borrowed|use of moved value|use of dropped value|cannot move out of|cannot assign to .* borrowed|storage owned by this frame|cannot outlive the frame|cannot drop value|cannot move borrowed value"

WORKER_SCRIPT="$WORK_DIR/check_worker.sh"
cat << 'EOF' > "$WORKER_SCRIPT"
#!/bin/sh
ZORIL="$1"
WORK_DIR="$2"
SAFETY_REGEX="$3"
shift 3

for cell in "$@"; do
    # 1. Unsafe cell check
    u_file="$WORK_DIR/$cell.unsafe.zrl"
    if out=$("$ZORIL" -I stdlib=stdlib --emit-zil -o /dev/null "$u_file" 2>&1); then
        # Unsafe cell compiled without error -> failing unsafe cell (hole)
        echo "UNSAFE_FAIL $cell"
    else
        # Compile failed -> verify it is a safety diagnostic
        if ! echo "$out" | grep -q -E "$SAFETY_REGEX"; then
            # Not a safety rejection -> generator error
            echo "GEN_ERR unsafe $cell: $out"
        fi
    fi

    # 2. Safe twin check
    t_file="$WORK_DIR/$cell.twin.zrl"
    if out=$("$ZORIL" -I stdlib=stdlib --emit-zil -o /dev/null "$t_file" 2>&1); then
        : # Twin compiled cleanly -> pass
    else
        # Twin compile failed -> check if safety diagnostic (over-rejection) or generator error
        if echo "$out" | grep -q -E "$SAFETY_REGEX"; then
            echo "TWIN_REJECT $cell"
        else
            echo "GEN_ERR twin $cell: $out"
        fi
    fi
done
EOF
chmod +x "$WORKER_SCRIPT"

RESULTS="$WORK_DIR/worker_results.raw"
: > "$RESULTS"

xargs -P "$JOBS" -n 50 "$WORKER_SCRIPT" "$ZORIL" "$WORK_DIR" "$SAFETY_REGEX" < "$MANIFEST" > "$RESULTS"

# Extract results
grep '^UNSAFE_FAIL ' "$RESULTS" | awk '{print $2}' | sort > "$WORK_DIR/actual_names.txt"
grep '^TWIN_REJECT ' "$RESULTS" | awk '{print $2}' | sort > "$WORK_DIR/twin_rejections.txt"
grep '^GEN_ERR ' "$RESULTS" > "$WORK_DIR/generator_errors.txt"

FAILING_UNSAFE_COUNT=$(wc -l < "$WORK_DIR/actual_names.txt" | tr -d ' ')
OVER_REJECTED_TWINS_COUNT=$(wc -l < "$WORK_DIR/twin_rejections.txt" | tr -d ' ')
GENERATOR_ERROR_COUNT=$(wc -l < "$WORK_DIR/generator_errors.txt" | tr -d ' ')

# Step 3: Check for generator errors (target: 0)
if [ "$GENERATOR_ERROR_COUNT" -gt 0 ]; then
    echo "[FAIL] store-grid: $GENERATOR_ERROR_COUNT generator error(s) detected (must be 0):"
    head -n 15 "$WORK_DIR/generator_errors.txt" | sed 's/^/       /'
    exit 1
fi

# Step 4: Generate Class Report. A tracked file is written only under --record: the report of a plain
# run goes to the work directory.
if [ "$RECORD" -eq 1 ]; then
    CLASSES_OUT="$CLASSES_FILE"
else
    CLASSES_OUT="$WORK_DIR/classes.txt"
fi
lua "$REPO_ROOT/scripts/fuzz/store_grid_classes.lua" "$WORK_DIR/actual_names.txt" "$CLASSES_OUT" > "$WORK_DIR/class_report.txt"
CLASSES_COUNT=$(grep -c '^[a-z]' "$CLASSES_OUT" || true)

# Step 5: Differences against expected failures
if [ ! -f "$EXPECTED_FILE" ] && [ "$RECORD" -eq 0 ]; then
    echo "[FAIL] store-grid: expected failures file not found: $EXPECTED_FILE (run with --record to create)"
    exit 1
fi

if [ "$RECORD" -eq 1 ]; then
    OBSERVE_WORKER="$WORK_DIR/observe_worker.sh"
    cat << 'EOF' > "$OBSERVE_WORKER"
#!/bin/sh
ZORIL="$1"
ZILC="$2"
BACKEND="$3"
ASSEMBLER="$4"
LINKER="$5"
RUNTIME="$6"
WORK_DIR="$7"
shift 7

for cell in "$@"; do
    zrl="$WORK_DIR/$cell.unsafe.zrl"
    zil="$WORK_DIR/$cell.unsafe.zil"
    ssa="$WORK_DIR/$cell.unsafe.ssa"
    s="$WORK_DIR/$cell.unsafe.s"
    o="$WORK_DIR/$cell.unsafe.o"
    bin="$WORK_DIR/$cell.unsafe.bin"

    exit_code="unknown"
    if "$ZORIL" -I stdlib=stdlib --emit-zil -o "$zil" "$zrl" >/dev/null 2>&1 && \
       "$ZILC" "$zil" "$ssa" >/dev/null 2>&1 && \
       "$BACKEND" -o "$s" "$ssa" >/dev/null 2>&1 && \
       "$ASSEMBLER" -o "$o" "$s" >/dev/null 2>&1 && \
       "$LINKER" -o "$bin" "$RUNTIME" "$o" >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            (timeout -k 2s 5s "$bin" >/dev/null 2>&1) 2>/dev/null
            exit_code=$?
        else
            ("$bin" >/dev/null 2>&1) 2>/dev/null
            exit_code=$?
        fi
    fi
    echo "$cell (exit $exit_code)"
done
EOF
    chmod +x "$OBSERVE_WORKER"

    ACTUAL_FAILURES="$WORK_DIR/actual_failures.txt"
    xargs -P "$JOBS" -n 25 "$OBSERVE_WORKER" \
        "$ZORIL" "$ZILC" "$BACKEND" "$ASSEMBLER" "$LINKER" "$RUNTIME" "$WORK_DIR" \
        < "$WORK_DIR/actual_names.txt" | sort > "$ACTUAL_FAILURES"
    cp "$ACTUAL_FAILURES" "$EXPECTED_FILE"
    cp "$WORK_DIR/twin_rejections.txt" "$TWINS_FILE"
    echo "[RECORD] Recorded $OVER_REJECTED_TWINS_COUNT over-rejected safe twins to $TWINS_FILE"
    echo "[RECORD] Recorded $FAILING_UNSAFE_COUNT expected failing cells to $EXPECTED_FILE"
    echo "[RECORD] Recorded $CLASSES_COUNT soundness hole classes to $CLASSES_FILE"
    echo "Summary: $SUMMARY_TEXT"
    echo "Failing unsafe cells: $FAILING_UNSAFE_COUNT, Over-rejected twins: $OVER_REJECTED_TWINS_COUNT, Generator errors: 0"
    cat "$WORK_DIR/class_report.txt"
    exit 0
fi

UNEXPECTED_FAILS="$WORK_DIR/unexpected_failures.txt"
UNEXPECTED_PASSES="$WORK_DIR/unexpected_passes.txt"

awk '{print $1}' "$EXPECTED_FILE" | sort > "$WORK_DIR/expected_names.txt"

comm -23 "$WORK_DIR/actual_names.txt" "$WORK_DIR/expected_names.txt" > "$UNEXPECTED_FAILS"
comm -13 "$WORK_DIR/actual_names.txt" "$WORK_DIR/expected_names.txt" > "$UNEXPECTED_PASSES"

UNEXP_FAIL_COUNT=$(wc -l < "$UNEXPECTED_FAILS" | tr -d ' ')
UNEXP_PASS_COUNT=$(wc -l < "$UNEXPECTED_PASSES" | tr -d ' ')

if [ "$UNEXP_FAIL_COUNT" -gt 0 ]; then
    echo "[FAIL] store-grid: $UNEXP_FAIL_COUNT unexpected unsafe cell(s) accepted (regression):"
    head -n 10 "$UNEXPECTED_FAILS" | sed 's/^/       /'
    exit 1
fi

if [ "$UNEXP_PASS_COUNT" -gt 0 ]; then
    echo "[FAIL] store-grid: $UNEXP_PASS_COUNT cell(s) now pass; remove them from $EXPECTED_FILE:"
    head -n 10 "$UNEXPECTED_PASSES" | sed 's/^/       /'
    exit 1
fi

# Over-rejections: a safe twin the compiler refuses. They do not block as a count, but a twin that is
# newly refused is a change somebody has to have meant, and one that is newly accepted leaves the record
# stale, so both fail until the record is updated (--record) in a commit that says which twins moved.
if [ ! -f "$TWINS_FILE" ]; then
    echo "[FAIL] store-grid: twin rejection record not found: $TWINS_FILE (run with --record to create)"
    exit 1
fi
sort "$TWINS_FILE" > "$WORK_DIR/expected_twins.txt"
comm -23 "$WORK_DIR/twin_rejections.txt" "$WORK_DIR/expected_twins.txt" > "$WORK_DIR/new_twin_rejections.txt"
comm -13 "$WORK_DIR/twin_rejections.txt" "$WORK_DIR/expected_twins.txt" > "$WORK_DIR/gone_twin_rejections.txt"
if [ -s "$WORK_DIR/new_twin_rejections.txt" ]; then
    echo "[FAIL] store-grid: $(wc -l < "$WORK_DIR/new_twin_rejections.txt" | tr -d ' ') safe twin(s) newly refused (an over-rejection the change added):"
    head -n 10 "$WORK_DIR/new_twin_rejections.txt" | sed 's/^/       /'
    exit 1
fi
if [ -s "$WORK_DIR/gone_twin_rejections.txt" ]; then
    echo "[FAIL] store-grid: $(wc -l < "$WORK_DIR/gone_twin_rejections.txt" | tr -d ' ') safe twin(s) now accepted; remove them from $TWINS_FILE:"
    head -n 10 "$WORK_DIR/gone_twin_rejections.txt" | sed 's/^/       /'
    exit 1
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo "--- Soundness Hole Classes ($CLASSES_COUNT total) ---"
cat "$WORK_DIR/class_report.txt"
echo "----------------------------------------------------"
echo "[PASS] store-grid: all $FAILING_UNSAFE_COUNT expected failing cells match ($TOTAL_VALID valid cells, $OVER_REJECTED_TWINS_COUNT over-rejected twins, $CLASSES_COUNT hole classes, 0 generator errors in ${ELAPSED}s)"
exit 0
