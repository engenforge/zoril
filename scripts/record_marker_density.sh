#!/bin/sh
# scripts/record_marker_density.sh — append compiler-wide raw-pointer marker
# density to bench/marker_density_history.tsv, keyed by date and commit.
#
# The safe/unsafe migration is a multi-sprint effort measured in exactly these
# numbers (deref line density sizes `unsafe { }` blocks; per-fn density sizes
# `unsafe fn`; ptr-cast/ref-forge are the two counts a step-4 boundary design
# actually gates — see scripts/marker_density.sh's header for why all four are
# tracked rather than just the deref pair). Without a series nobody can tell
# progress from noise, so this keeps a running history the way
# bench/speed_history.tsv does for speed.
#
# Wired into `make preflight`. Per-file detail still comes from
# scripts/marker_density.sh <file.zrl>.
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HISTORY="$REPO_ROOT/bench/marker_density_history.tsv"

if [ ! -x "$REPO_ROOT/scripts/marker_density.sh" ]; then
    echo "Error: scripts/marker_density.sh not found." >&2
    exit 1
fi

DATE="$(date +%Y-%m-%d)"
COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

# Compiler source files that legitimately carry unsafe code.
FILES=""
for d in src tools; do
    [ -d "$REPO_ROOT/$d" ] && FILES="$FILES $(find "$REPO_ROOT/$d" -name '*.zrl')"
done

tot_loc=0; tot_marker=0; tot_fn=0; tot_fnw=0; tot_ptrcast=0; tot_reforge=0
for f in $FILES; do
    out="$("$REPO_ROOT/scripts/marker_density.sh" "$f" 2>/dev/null || true)"
    loc=$(printf '%s\n' "$out"  | awk -F': *' '/^non-comment LOC:/{print $2}'   | awk '{print $1}')
    mk=$(printf '%s\n' "$out"   | awk -F': *' '/^marker lines:/{print $2}'      | awk '{print $1}')
    fn=$(printf '%s\n' "$out"   | awk -F': *' '/^functions:/{print $2}'         | awk '{print $1}')
    fnw=$(printf '%s\n' "$out"  | awk -F': *' '/^fns w\/ marker:/{print $2}'    | awk '{print $1}')
    pc=$(printf '%s\n' "$out"   | awk -F': *' '/^ptr-cast lines:/{print $2}'    | awk '{print $1}')
    rf=$(printf '%s\n' "$out"   | awk -F': *' '/^ref-forge lines:/{print $2}'   | awk '{print $1}')
    [ -n "$loc" ]  && tot_loc=$((tot_loc + loc))
    [ -n "$mk"  ]  && tot_marker=$((tot_marker + mk))
    [ -n "$fn"  ]  && tot_fn=$((tot_fn + fn))
    [ -n "$fnw" ]  && tot_fnw=$((tot_fnw + fnw))
    [ -n "$pc"  ]  && tot_ptrcast=$((tot_ptrcast + pc))
    [ -n "$rf"  ]  && tot_reforge=$((tot_reforge + rf))
done

line_density=$(awk "BEGIN { if ($tot_loc>0) printf \"%.2f\", $tot_marker*100/$tot_loc; else print 0 }")
fn_density=$(awk "BEGIN { if ($tot_fn>0) printf \"%.2f\", $tot_fnw*100/$tot_fn; else print 0 }")

if [ ! -f "$HISTORY" ]; then
    printf 'date\tcommit\tfiles\tloc\tmarker_lines\tline_density_pct\tfunctions\tfns_with_marker\tper_fn_density_pct\tptr_cast_sites\tref_forge_sites\n' > "$HISTORY"
fi

printf '%s\t%s\t%d\t%d\t%d\t%s\t%d\t%d\t%s\t%d\t%d\n' \
    "$DATE" "$COMMIT" "$(echo $FILES | wc -w)" "$tot_loc" "$tot_marker" "$line_density" \
    "$tot_fn" "$tot_fnw" "$fn_density" "$tot_ptrcast" "$tot_reforge" >> "$HISTORY"

printf 'Marker density @ %s (%s): line %.2f%% (%d/%d), per-fn %.2f%% (%d/%d), ptr-cast %d, ref-forge %d\n' \
    "$DATE" "$COMMIT" "$line_density" "$tot_marker" "$tot_loc" "$fn_density" "$tot_fnw" "$tot_fn" "$tot_ptrcast" "$tot_reforge"
printf 'Appended to %s\n' "$HISTORY"
