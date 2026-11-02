#!/bin/sh
# Measure raw-pointer "marker" density in a Zoril source file.
#
# Reports FOUR site counts, because they answer different questions and can
# move in opposite directions under the same refactor (see the 2026-09-18
# review that added ptr_cast/ref_forge: a `*mut T` -> `&mut T` field migration
# fell from 10.45% to 6.01% deref density while `&*`/`&mut *` reforge sites
# rose 124 -> 199 over the same five commits — the deref meter alone read
# that as unambiguous progress, which it was not):
#
#   - deref lines:      (*p) / p[i]   where p is a raw pointer (*T / *mut T)
#                        -> what a future unsafe-boundary's *dereference* gate
#                           would have to scope
#   - ptr-cast lines:    `as *T` / `as *mut T`
#                        -> gated by the `@ptr_cast`-mandatory design, so these
#                           need counting regardless of which unsafe-boundary
#                           design ships
#   - ref-forge lines:   `&*p` / `&mut *p` where `p` (or the expression it
#                        derefs) is a raw pointer, not an already-reference value
#                        -> THE number a `pointer-creation-site` unsafe boundary
#                           actually wraps (the step-4 payload's chosen design,
#                           2026-09-17): "the marker should scope
#                           pointer-creation sites rather than every deref".
#                           A `*mut T` -> `&mut T` migration is *supposed* to
#                           concentrate N derefs into one `&mut *p` at the
#                           boundary — collapsing this number is the actual
#                           signal that a migration produced a boundary worth
#                           drawing, rather than merely moved the spelling.
#
# IMPORTANT — why deref counting is not a plain `(*` grep:
#   Zoril spells REFERENCE dereference with the same syntax as POINTER
#   dereference. `(*self.builder)` where `builder: &mut ILBuilder` is safe and
#   needs no marker. An earlier version of this script counted both, which made
#   a *successful* `*mut T` -> `&mut T` migration register as almost no
#   improvement: migrating the field does not change the `(*x)` spelling. On
#   src/lower_zir_to_zil.zrl that understated the result as 23.89% when the
#   real figure was 9.67%.
#
#   So this script first learns which identifiers are reference-typed, from
#   their declarations in the same file (struct fields, `let` bindings, fn
#   params), and excludes dereferences *and reforges* of those. `&mut
#   *self.mono` where `mono: &mut Monomorphizer` is a safe reborrow between two
#   already-checked reference types and is excluded from ref-forge the same
#   way `(*self.mono)` is excluded from deref; `&*self.resolver.ast` where
#   `ast: *mut AST` is a genuine forge from a raw pointer and is counted.
#
#   DEPENDENCY: this exclusion pass trusts DECLARED types, so both the deref
#   and ref-forge numbers are only as meaningful as the guarantee that `&T`
#   actually behaves read-only and isn't just a raw pointer with a nicer
#   spelling. That guarantee is enforced by `src/check_zir.zrl`
#   (`base_is_readonly_pointer` / `place_last_deref_is_readonly`, landed
#   2026-09-23) — before that landed, this script's exclusions were counting
#   an unenforced annotation, not a checked one.
#
# LIMITATION: this is a textual heuristic, not type inference. Identifiers whose
# reference-ness is only knowable from another file (e.g. a local bound from a
# function returning `&T`), or from a call expression rather than a bare
# identifier (`&mut *MonoRegistry.new(arena)`), are still counted as
# ref-forge/deref sites even when the callee happens to be safe. So all four
# numbers are UPPER BOUNDS on the true count, never under-counts.
#
# Five metrics are reported; the two per-fn/line derefs decide granularity,
# and ref-forge decides whether a migration concentrated unsafety or just
# relocated it:
#   - deref line density:    marker lines / non-comment LOC   -> sizes `unsafe { }`
#   - deref per-fn density:  fraction of fn bodies with >=1 marker line -> sizes `unsafe fn`
#     A single marker line anywhere in a function forces that whole function
#     behind a coarse boundary, so per-fn density stays high even when line
#     density falls. Measured 2026-09-17: 9.67% line vs 74.47% per-fn.
#   - ptr-cast lines, ref-forge lines: reported as raw counts (see above),
#     not percentages — there is no natural "total" to divide either by that
#     isn't itself LOC, and LOC-normalizing them was not asked for by the
#     design they gate (`@ptr_cast`-mandatory; pointer-creation-site boundary).
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: marker_density.sh <file.zrl | directory> [file2.zrl ...]" >&2
  exit 1
fi

files=""
nfiles=0
add_file() {
  files="$files$1
"
  nfiles=$((nfiles + 1))
}

found_list="$(mktemp)"
trap 'rm -f "$found_list"' EXIT INT TERM
for arg in "$@"; do
  if [ -d "$arg" ]; then
    find "$arg" -type f -name "*.zrl" | sort > "$found_list"
    if [ ! -s "$found_list" ]; then
      echo "error: no .zrl files found in directory '$arg'" >&2
      exit 1
    fi
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      add_file "$f"
    done < "$found_list"
  elif [ -f "$arg" ]; then
    case "$arg" in
      *.zrl) add_file "$arg" ;;
      *) echo "error: '$arg' is not a .zrl file" >&2; exit 1 ;;
    esac
  else
    echo "error: '$arg' does not exist or matches no files" >&2
    exit 1
  fi
done

if [ "$nfiles" -eq 0 ]; then
  echo "error: no .zrl files found" >&2
  exit 1
fi

tot_ref=0
tot_loc=0
tot_marker=0
tot_fn=0
tot_fnw=0
tot_ptrcast=0
tot_reforge=0

while IFS= read -r f; do
  [ -n "$f" ] || continue
  metrics=$(awk '
# ---- pass 1: collect identifiers declared as references ----
NR==FNR {
  raw=$0; sub(/\/\/.*/, "", raw)
  is_let = (raw ~ /^[[:space:]]*let[[:space:]]/)
  if (!is_let) {
    tmp=raw
    while (match(tmp, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*&(mut[[:space:]]+)?[A-Za-z_]/)) {
      mstart=RSTART; mlen=RLENGTH
      seg=substr(tmp, mstart, mlen)
      if (match(seg, /^[A-Za-z_][A-Za-z0-9_]*/)) { nm=substr(seg, RSTART, RLENGTH); isfield[nm]=1; isref[nm]=1 }
      tmp=substr(tmp, mstart+mlen)
    }
  }
  if (is_let && match(raw, /let[[:space:]]+(mut[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*&/)) {
    seg=substr(raw, RSTART, RLENGTH)
    if (match(seg, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:/)) {
      nm=substr(seg, RSTART, RLENGTH); sub(/[[:space:]]*:/, "", nm); isref[nm]=1
    }
  }
  next
}
# ---- pass 2: count deref / ptr-cast / ref-forge lines ----
{
  raw=$0; sub(/\/\/.*/, "", raw)
  if (raw ~ /^[[:space:]]*$/) next
  loc++
  line=raw
  if (line ~ /^[[:space:]]*(pub[[:space:]]+)?fn[[:space:]]/ && line !~ /;[[:space:]]*$/) {
    if (infn) { fncount++; if (fnhas) fnwith++ }
    infn=1; depth=0; fnhas=0
  }
  n=split($0, ch, ""); d=0
  for (i=1; i<=n; i++) { if (ch[i]=="{") d++; if (ch[i]=="}") d-- }
  depth+=d

  # blank out dereferences of known reference-typed identifiers
  probe=line
  for (nm in isref) {
    gsub("\\(\\*self\\." nm "\\)", "", probe)
    gsub("\\(\\*" nm "\\)", "", probe)
  }
  # A word end is marked with \001 after each identifier: awk has no portable \> (mawk reads it as ">").
  gsub(/[A-Za-z0-9_]+/, "&\001", probe)
  for (nm in isref) {
    gsub("&\\*" nm "\001", "", probe)
  }
  if (probe ~ /\(\*/ || probe ~ /&\*/) { marker++; if (infn) fnhas=1 }

  # ptr-cast lines: `as *T` / `as *mut T`
  if (line ~ /(^|[^A-Za-z0-9_])as[[:space:]]+\*/) { ptrcast++ }

  # ref-forge lines: `&*p` / `&mut *p` where `p` is not a known reference
  fprobe=line
  gsub(/[A-Za-z0-9_]+/, "&\001", fprobe)
  for (nm in isfield) {
    gsub("&[[:space:]]*mut\001[[:space:]]*\\*[[:space:]]*self\001\\." nm "\001", "", fprobe)
    gsub("&\\*[[:space:]]*self\001\\." nm "\001", "", fprobe)
  }
  gsub(/\001/, "", fprobe)
  for (nm in isref) {
    gsub("&[[:space:]]*mut[[:space:]]*\\*[[:space:]]*" nm "([^.A-Za-z0-9_]|$)", "", fprobe)
    gsub("&\\*[[:space:]]*" nm "([^.A-Za-z0-9_]|$)", "", fprobe)
  }
  if (fprobe ~ /&\*/ || fprobe ~ /&[[:space:]]*mut[[:space:]]*\*/) { reforge++ }

  if (infn && depth<=0 && d<0) { fncount++; if (fnhas) fnwith++; infn=0 }
}
END {
  if (infn) { fncount++; if (fnhas) fnwith++ }
  nref=0; for (nm in isref) nref++
  printf "%d %d %d %d %d %d %d\n", nref, loc, marker, fncount, fnwith, ptrcast, reforge
}' "$f" "$f")

  read -r r l m fc fw pc rf <<EOM
$metrics
EOM
  tot_ref=$((tot_ref + r))
  tot_loc=$((tot_loc + l))
  tot_marker=$((tot_marker + m))
  tot_fn=$((tot_fn + fc))
  tot_fnw=$((tot_fnw + fw))
  tot_ptrcast=$((tot_ptrcast + pc))
  tot_reforge=$((tot_reforge + rf))
done <<EOF
$files
EOF

if [ "$#" -eq 1 ]; then
  target_label="$1"
else
  target_label="$* ($nfiles files)"
fi

line_pct=$(awk "BEGIN { if ($tot_loc > 0) printf \"%.2f\", $tot_marker * 100 / $tot_loc; else print \"0.00\" }")
fn_pct=$(awk "BEGIN { if ($tot_fn > 0) printf \"%.2f\", $tot_fnw * 100 / $tot_fn; else print \"0.00\" }")

printf "file: %s\n" "$target_label"
printf "reference-typed idents excluded: %d\n" "$tot_ref"
printf "non-comment LOC: %d\n" "$tot_loc"
printf "marker lines:     %d\n" "$tot_marker"
printf "line density:     %s%%   (sizes \`unsafe { }\`)\n" "$line_pct"
printf "functions:        %d\n" "$tot_fn"
printf "fns w/ marker:    %d\n" "$tot_fnw"
printf "per-fn density:   %s%%   (sizes \`unsafe fn\` — the granularity metric)\n" "$fn_pct"
printf "ptr-cast lines:   %d      (\`as *T\` / \`as *mut T\` — gated by @ptr_cast-mandatory)\n" "$tot_ptrcast"
# #[borrows(..)] is a trusted claim (doc/spec/unsafe_policy.md): count it with the markers.
borrows_claims=$(printf "%s" "$files" | while IFS= read -r f; do if [ -n "$f" ]; then cat "$f"; fi; done 2>/dev/null | grep -c "^[[:space:]]*#\[borrows(" || true)
printf "#[borrows] claims: %d      (trusted beyond the visible case; see unsafe_policy.md)\n" "$borrows_claims"
printf "ref-forge lines:  %d      (\`&*p\` / \`&mut *p\` from a raw pointer — what a pointer-creation-site boundary wraps)\n" "$tot_reforge"

