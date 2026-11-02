#!/bin/sh
# scripts/unsafe_scan.sh — find `unsafe` markers the compiler does not need.
#
# For each `unsafe {` in the programs (tests/, corpus/zrl/, the safety-matrix probes) and
# in stdlib/, remove that one marker and recompile. A block that still compiles either
# never needed its marker or holds an operation the compiler fails to gate; the second is
# a soundness hole in safe code (this is how `@syscall` and `@alloca` were found ungated).
#
# A stdlib block is checked through the programs that import its module, since the
# compiler lowers only the functions something uses: a block survives only if every
# importer still compiles, and one with no exercising caller is reported too.
#
# Known survivors are listed in scripts/unsafe_scan_allow.txt as `<path>|<line text>|<why>`.
# Exit 0 when every survivor is listed (and every entry still survives), 1 otherwise.

cd "$(dirname "$0")/.."
REPO="$(pwd)"
ZORIL="${ZORIL_CC:-$REPO/build/zoril}"
ALLOW="$REPO/scripts/unsafe_scan_allow.txt"

. "$REPO/scripts/lib/portability.sh"
JOBS="${UNSAFE_SCAN_JOBS:-$(nproc_count)}"

compiles() { # compiles <file> <stdlib dir> [the program's own directory]
    # The program's directory goes first, as the compiler searches it first for a file compiled in
    # place: tests/bootstrap/ has its own ast.zrl, which must shadow src/ast.zrl for a copy too. It
    # is a named root because roots are otherwise named after their directory, and
    # tests/functional/stdlib/ would clash with stdlib/.
    "$ZORIL" ${3:+-I "scanned_program=$3"} -I "$2" -I "$REPO/src" -I "$REPO/build/gen" -o /dev/null "$1" \
        > /dev/null 2>&1
}

# drop <file> <k>: print <file> with its k-th `unsafe {` marker (1-based) removed.
drop() {
    awk -v k="$2" '
        {
            line = $0; out = ""
            while (match(line, /(^|[^A-Za-z0-9_])unsafe[ \t]*\{/)) {
                pre = (RSTART > 1 || substr(line, RSTART, 1) != "u") ? 1 : 0
                n++
                cut = RSTART + pre - 1
                if (n == k) {
                    out = out substr(line, 1, cut) "      "
                } else {
                    out = out substr(line, 1, cut + 6)
                }
                line = substr(line, cut + 7)
            }
            print out line
        }' "$1"
}

# markers <file>: "<k>\t<line>" for each marker.
markers() {
    awk '
        {
            line = $0
            while (match(line, /(^|[^A-Za-z0-9_])unsafe[ \t]*\{/)) {
                n++; print n "\t" NR
                line = substr(line, RSTART + RLENGTH)
            }
        }' "$1"
}

if [ "$1" = "--worker-main" ]; then
    _tmp="$2"; _f="$3"
    _d=$(dirname "$_f")
    if compiles "$_f" "$REPO/stdlib" "$_d"; then
        printf '%s\n' "$_f" >> "$_tmp/mains"
    fi
    exit 0
fi

if [ "$1" = "--worker-prep-prog" ]; then
    _id="$2"; _f="$3"; _tmp="$4"
    _d=$(dirname "$_f")
    if compiles "$_f" "$REPO/stdlib" "$_d"; then
        _chk="$_tmp/chk_$_id.zrl"
        cp "$_f" "$_chk"
        if ! compiles "$_chk" "$REPO/stdlib" "$_d"; then
            echo "$_f" > "$_tmp/err_unmodified"
            rm -f "$_chk"
            exit 1
        fi
        rm -f "$_chk"
        markers "$_f" | while IFS="$(printf '\t')" read -r _k _ln; do
            printf '%s %s %s %s %s %s\n' "$_id-$_k" "$_k" "$_ln" "$_f" "$_d" "$_tmp"
        done > "$_tmp/ptasks_$_id"
    fi
    exit 0
fi

if [ "$1" = "--worker-program" ]; then
    _id="$2"; _k="$3"; _ln="$4"; _f="$5"; _d="$6"; _tmp="$7"
    _jobdir="$_tmp/prog_$_id"
    mkdir -p "$_jobdir"
    _mut="$_jobdir/mutant.zrl"
    drop "$_f" "$_k" > "$_mut"
    if compiles "$_mut" "$REPO/stdlib" "$_d"; then
        _text=$(sed -n "${_ln}p" "$_f" | sed 's/^[ \t]*//; s/[ \t]*$//')
        printf '%s|%s\n' "$_f" "$_text" > "$_tmp/surv_prog_$_id"
    fi
    rm -rf "$_jobdir"
    exit 0
fi

if [ "$1" = "--worker-stdlib" ]; then
    _id="$2"; _k="$3"; _ln="$4"; _lib="$5"; _tmp="$6"
    _name=${_lib#stdlib/}
    _jobdir="$_tmp/std_$_id"
    mkdir -p "$_jobdir/std"
    cp -R stdlib/. "$_jobdir/std/"
    drop "$_lib" "$_k" > "$_jobdir/std/$_name"
    if compiles "$_jobdir/std/$_name" "$_jobdir/std"; then
        _importers=$(xargs grep -l "\"$_name\"" < "$_tmp/mains" 2>/dev/null)
        _survived=1
        for _imp in $_importers; do
            if ! compiles "$_imp" "$_jobdir/std" "$(dirname "$_imp")"; then
                _survived=0
                break
            fi
        done
        if [ "$_survived" -eq 1 ]; then
            _text=$(sed -n "${_ln}p" "$_lib" | sed 's/^[ \t]*//; s/[ \t]*$//')
            printf '%s|%s\n' "$_lib" "$_text" > "$_tmp/surv_std_$_id"
        fi
    fi
    rm -rf "$_jobdir"
    exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/zoril_unsafe_scan_XXXXXX")"
trap 'rm -rf "$tmp"' EXIT INT TERM

programs=$(find tests corpus/zrl bench/safety_matrix/probes -name '*.zrl' | sort)

# ── Programs ─────────────────────────────────────────────────────────────────
: > "$tmp/raw_progs"
p_id=0
for f in $programs; do
    if grep -q 'unsafe[ \t]*{' "$f"; then
        p_id=$((p_id + 1))
        printf '%s %s %s\n' "$p_id" "$f" "$tmp" >> "$tmp/raw_progs"
    fi
done

if [ -s "$tmp/raw_progs" ]; then
    xargs -n 3 -P "$JOBS" "$0" --worker-prep-prog < "$tmp/raw_progs"
fi

if [ -f "$tmp/err_unmodified" ]; then
    bad_f=$(head -n 1 "$tmp/err_unmodified")
    echo "[FAIL] unsafe-scan: $bad_f compiles in place but not as a copy in $tmp; the scan cannot test it"
    exit 1
fi

: > "$tmp/prog_tasks"
for pt in "$tmp"/ptasks_*; do
    [ -f "$pt" ] && cat "$pt" >> "$tmp/prog_tasks"
done

if [ -s "$tmp/prog_tasks" ]; then
    xargs -n 6 -P "$JOBS" "$0" --worker-program < "$tmp/prog_tasks"
fi

# ── Stdlib, through its importers ────────────────────────────────────────────
: > "$tmp/mains"
raw_mains=$(grep -l '^fn main(' $programs 2>/dev/null || true)
if [ -n "$raw_mains" ]; then
    printf '%s\n' $raw_mains | xargs -n 1 -P "$JOBS" "$0" --worker-main "$tmp"
fi

: > "$tmp/std_tasks"
s_id=0
for lib in stdlib/*.zrl stdlib/*/*.zrl; do
    grep -q 'unsafe[ \t]*{' "$lib" || continue
    markers "$lib" > "$tmp/m"
    while IFS="$(printf '\t')" read -r k ln; do
        s_id=$((s_id + 1))
        printf '%s %s %s %s %s\n' "$s_id" "$k" "$ln" "$lib" "$tmp" >> "$tmp/std_tasks"
    done < "$tmp/m"
done

if [ -s "$tmp/std_tasks" ]; then
    xargs -n 5 -P "$JOBS" "$0" --worker-stdlib < "$tmp/std_tasks"
fi

# ── Collect survivors ────────────────────────────────────────────────────────
: > "$tmp/survivors"
for s in "$tmp"/surv_*; do
    [ -f "$s" ] && cat "$s" >> "$tmp/survivors"
done

# ── Compare against the allowlist ────────────────────────────────────────────
# As multisets: two survivors on identical lines (`unsafe {`) need two entries.
grep -v '^#' "$ALLOW" | grep -v '^[ \t]*$' | cut -d'|' -f1,2 | sort > "$tmp/allowed"
sort "$tmp/survivors" > "$tmp/found"
comm -23 "$tmp/found" "$tmp/allowed" > "$tmp/unlisted"
comm -13 "$tmp/found" "$tmp/allowed" > "$tmp/stale"
while IFS= read -r s; do
    echo "[FAIL] unsafe-scan: $s: the marker can be removed and it still compiles (an ungated operation, a redundant marker, or an unexercised stdlib function)"
done < "$tmp/unlisted"
while IFS= read -r a; do
    echo "[FAIL] unsafe-scan: $a: allowlisted but no longer a survivor; remove its entry"
done < "$tmp/stale"
[ -s "$tmp/unlisted" ] || [ -s "$tmp/stale" ] && exit 1
echo "[PASS] unsafe-scan: $(wc -l < "$tmp/found") removable markers, all allowlisted"
