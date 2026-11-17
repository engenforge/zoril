#!/bin/sh
# scripts/record_figures.sh — append the tree's safety figures to bench/records/figures_history.tsv.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/scripts/env.sh"
. "$REPO_ROOT/scripts/lib/records.sh"

HISTORY="${HISTORY:-$REPO_ROOT/bench/records/figures_history.tsv}"
FIGURES_SCRIPT="${FIGURES_SCRIPT:-$REPO_ROOT/scripts/check_safety_figures.sh}"

records_check_target "$HISTORY" "$REPO_ROOT" || exit $?
if [ "${RECORDS_SKIP:-0}" -eq 1 ]; then
    exit 0
fi

COMMIT=$(records_repo_commit "$REPO_ROOT")
case "$COMMIT" in
    *-dirty) ;;
    *)
        if [ -f "$HISTORY" ]; then
            last_commit=$(awk -F'\t' '!/^#/ && NF >= 2 { c = $2 } END { print c }' "$HISTORY")
            if [ "$last_commit" = "$COMMIT" ]; then
                printf 'figures: %s is already recorded\n' "$COMMIT"
                exit 0
            fi
        fi
        ;;
esac

DATE=$(date -u '+%Y-%m-%d')
if [ -x "${ZORIL_BIN:-}" ]; then
    ZORIL_VER=$("$ZORIL_BIN" --version 2>/dev/null | awk '{print $2; exit}') || ZORIL_VER="unknown"
elif [ -x "$REPO_ROOT/build/zoril" ]; then
    ZORIL_VER=$("$REPO_ROOT/build/zoril" --version 2>/dev/null | awk '{print $2; exit}') || ZORIL_VER="unknown"
else
    ZORIL_VER="unknown"
fi
[ -n "$ZORIL_VER" ] || ZORIL_VER="unknown"

print_out=$(sh "$FIGURES_SCRIPT" --print)
density_out=$(sh "$FIGURES_SCRIPT" --density --print)
probes_out=$(sh "$FIGURES_SCRIPT" --probes --print)

val_of() {
    printf '%s\n' "$1" | awk -F'\t' -v k="$2" '$1 == k { print $2; exit }'
}

stdlib_modules=$(val_of "$print_out" 'stdlib modules')
stdlib_lines=$(val_of "$print_out" 'stdlib lines')
stdlib_unsafe_blocks=$(val_of "$print_out" 'stdlib `unsafe { }` blocks')
stdlib_unsafe_modules=$(val_of "$print_out" 'stdlib modules with such a block')
stdlib_unsafe_fns=$(val_of "$print_out" 'stdlib `unsafe fn` declarations')
stdlib_public_unsafe_fns=$(val_of "$print_out" 'of those, public')
compiler_modules=$(val_of "$print_out" 'compiler modules')
compiler_lines=$(val_of "$print_out" 'compiler lines')
compiler_unsafe_blocks=$(val_of "$print_out" 'compiler `unsafe { }` blocks')

src_density=$(val_of "$density_out" 'src density' | tr -d '*')
stdlib_density=$(val_of "$density_out" 'stdlib density' | tr -d '*')
line_counts_raw=$(val_of "$density_out" 'line counts' | tr -d ',')
set -- $(printf '%s\n' "$line_counts_raw" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) print $i }')
src_unsafe_lines="${1:-0}"
src_total_lines="${2:-0}"
stdlib_unsafe_lines="${3:-0}"
stdlib_total_lines="${4:-0}"

probes=$(val_of "$probes_out" 'probes')
compile_reject=$(val_of "$probes_out" 'compile_reject')
accept=$(val_of "$probes_out" 'accept')
runtime_trap=$(val_of "$probes_out" 'runtime_trap')
runtime_fault=$(val_of "$probes_out" 'runtime_fault')
known_gap=$(val_of "$probes_out" 'known_gap')

records_header "$HISTORY" "$(printf 'date\tcommit\tzoril_version\tstdlib_modules\tstdlib_lines\tstdlib_unsafe_blocks\tstdlib_unsafe_modules\tstdlib_unsafe_fns\tstdlib_public_unsafe_fns\tcompiler_modules\tcompiler_lines\tcompiler_unsafe_blocks\tsrc_density\tstdlib_density\tsrc_unsafe_lines\tsrc_total_lines\tstdlib_unsafe_lines\tstdlib_total_lines\tprobes\tcompile_reject\taccept\truntime_trap\truntime_fault\tknown_gap')" || exit 1

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$DATE" "$COMMIT" "$ZORIL_VER" \
    "$stdlib_modules" "$stdlib_lines" "$stdlib_unsafe_blocks" "$stdlib_unsafe_modules" \
    "$stdlib_unsafe_fns" "$stdlib_public_unsafe_fns" \
    "$compiler_modules" "$compiler_lines" "$compiler_unsafe_blocks" \
    "$src_density" "$stdlib_density" \
    "$src_unsafe_lines" "$src_total_lines" "$stdlib_unsafe_lines" "$stdlib_total_lines" \
    "$probes" "$compile_reject" "$accept" "$runtime_trap" "$runtime_fault" "$known_gap" >> "$HISTORY"

printf 'Figures @ %s (%s): %s probes, %s compiler lines, %s/%s density\n' \
    "$DATE" "$COMMIT" "$probes" "$compiler_lines" "$src_density" "$stdlib_density"
printf 'Appended to %s\n' "$HISTORY"

records_commit "$HISTORY" "$COMMIT: figures" "$REPO_ROOT" || exit $?
