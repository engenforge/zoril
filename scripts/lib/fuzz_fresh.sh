# scripts/lib/fuzz_fresh.sh -- sourced by fuzz_safe.sh and fuzz_jobs.sh: which compiler did the run use?
#
# A run that records findings or a budget cites a commit, and the evidence is about the compiler that
# commit builds. The driver runs whatever `build/zoril` and `build/zilc` are on disk, and nothing used to
# check they came from that commit. Both embed it (`zoril 0.0.1-...-g<hash>`, `-dirty` on a modified
# tree, from scripts/version.sh), so the check reads it back.

# fuzz_version BIN -- the first line of `BIN --version`, or "unknown" (a stub compiler has none).
fuzz_version() {
    v=$("$1" --version 2>/dev/null | head -1)
    printf '%s\n' "${v:-unknown}"
}

# fuzz_require_fresh BIN... -- fail (status 1, reasons on stderr) unless the working tree is clean and
# every BIN reports the hash of HEAD without `-dirty`. `make fuzz-release` rebuilds both first.
fuzz_require_fresh() {
    _head=$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD 2>/dev/null) || {
        echo "fuzz: cannot read HEAD, so the binaries' commit cannot be checked" >&2; return 1; }
    _bad=0
    if [ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
        echo "fuzz: the working tree is not clean, so a record would cite a commit that is not what ran" >&2
        _bad=1
    fi
    for _bin in "$@"; do
        _ver=$(fuzz_version "$_bin")
        case "$_ver" in *-dirty) echo "fuzz: $_bin is $_ver: built from a modified tree" >&2; _bad=1; continue ;; esac
        _hash=$(printf '%s\n' "$_ver" | sed -n 's/.*-g\([0-9a-f][0-9a-f]*\)$/\1/p')
        if [ -z "$_hash" ]; then
            echo "fuzz: $_bin reports '$_ver', which carries no commit hash" >&2; _bad=1; continue
        fi
        case "$_head" in
            "$_hash"*) ;;
            *) echo "fuzz: $_bin was built from commit $_hash but HEAD is $_head (run make fuzz-release, which rebuilds it)" >&2
               _bad=1 ;;
        esac
    done
    return $_bad
}

# ── the fingerprint: which compiler *code* a record's figures describe ────────────────────────────
# Five directories, each hashed from its files minus Markdown. A document is not a compiler
# input: the record is about the compiler a run used, and a README-only change must not demand a
# 15-hour re-run. The hash moves when a code file is added, removed, renamed or edited, and stays put
# when only a page changes.
# One implementation, sourced by the harness that prints the line (fuzz_safe.sh), the gate that
# compares it (check_fuzz_fresh.sh) and the runner that records it (fuzz_jobs.sh, record_update.sh):
# a second copy is how the two drift apart.
# Requires sha256_of (lib/portability.sh) and tree_files (lib/tree_files.sh).

# fuzz_fingerprint_scope -- the directories whose code the record is about, in the record's order.
fuzz_fingerprint_scope() {
    printf '%s\n' "src stdlib tools/zilc tools/zbuild rt"
}

# fuzz_tree_code_hash REPO DIR -- SHA-256 of the directory's non-Markdown files, or
# nothing (status 1) when the directory cannot be read.
# Hashed stream: sorted path<TAB>sha256 lines (path relative to DIR).
fuzz_tree_code_hash() {
    _repo=$1; _dir=$2
    [ -d "$_repo/$_dir" ] || return 1
    _tmp=$(mktemp "${TMPDIR:-/tmp}/fuzz-code-hash.XXXXXX") || return 1
    (
        cd "$_repo/$_dir" || exit 1
        tree_files . \
            | grep -v '\.md$' \
            | (
                set --
                _count=0
                while IFS= read -r _f || [ -n "$_f" ]; do
                    set -- "$@" "$_f"
                    _count=$((_count + 1))
                    if [ "$_count" -ge 80 ]; then
                        sha256_of "$@"
                        set --
                        _count=0
                    fi
                done
                if [ "$_count" -gt 0 ]; then
                    sha256_of "$@"
                fi
            ) \
            | awk '{ printf "%s\t%s\n", substr($0, 67), substr($0, 1, 64) }'
    ) > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 1; }
    if [ ! -s "$_tmp" ]; then rm -f "$_tmp"; return 1; fi
    _sum=$(sha256_of "$_tmp" 2>/dev/null) || { rm -f "$_tmp"; return 1; }
    rm -f "$_tmp"
    printf '%s\n' "${_sum%% *}"
}

# fuzz_fingerprint REPO -- "src=<h> stdlib=<h> tools/zilc=<h> tools/zbuild=<h> rt=<h>", or nothing when
# any directory cannot be hashed. The hash describes the working tree.
fuzz_fingerprint() {
    _repo=$1
    _out=""
    for _d in $(fuzz_fingerprint_scope); do
        _h=$(fuzz_tree_code_hash "$_repo" "$_d") || { printf '\n'; return 0; }
        _out="$_out${_out:+ }$_d=$_h"
    done
    printf '%s\n' "$_out"
}

# fuzz_rustc -- the differential oracle's compiler: `FUZZ_RUSTC` when it is set (a path, or an empty
# value for "there is none", which the self-test uses), else `rustc` from PATH.
fuzz_rustc() {
    if [ -n "${FUZZ_RUSTC+set}" ]; then
        [ -n "$FUZZ_RUSTC" ] && printf '%s\n' "$FUZZ_RUSTC"
        return 0
    fi
    command -v rustc 2>/dev/null || true
}

# fuzz_require_rustc STRICT LABEL -- status 2 when the oracle is unusable or a run whose result will be
# cited has none. The differential oracle is the one that raised both findings so far, so a 15-hour
# `--release` run without it would be recorded for a sentence it cannot support. A run that records
# nothing keeps the old behaviour (`make fuzz-short` on a machine without Rust is still useful).
fuzz_require_rustc() {
    _strict=$1
    _label=$2
    _r=$(fuzz_rustc)
    if [ -n "$_r" ]; then
        [ -x "$_r" ] && return 0
        echo "fuzz: FUZZ_RUSTC=$_r is not an executable file" >&2
        return 2
    fi
    [ "$_strict" -eq 1 ] || return 0
    echo "Missing required tool: rustc (needed by: $_label; install it in your path using your OS package manager, or set FUZZ_RUSTC to its path)" >&2
    echo "fuzz: a result recorded without the differential oracle cannot be cited as one; run without --release (make fuzz-short) for a crash-oracle-only run" >&2
    return 2
}

# fuzz_zbuild_bin REPO_ROOT ZBUILD_OPT -- the `zbuild` a cited run must also check for freshness (it is part of the fuzzed
# pipeline and of the fingerprint), or nothing when the mode-diff reading is off. ZBUILD_OPT is 1 (--zbuild), 0 (--no-zbuild)
# or empty (on for this repository's own compilers).
fuzz_zbuild_bin() {
    if [ "${2:-}" = 1 ] || { [ "${2:-}" != 0 ] && fuzz_own_compilers "$1"; }; then
        printf '%s\n' "${ZBUILD_BIN:-$1/build/zbuild}"
    fi
}

# fuzz_own_compilers REPO_ROOT: 0 when the compiler the run uses is this repository's own build/zoril and build/zilc
# (ZORIL_BIN and ZILC_BIN unset, or `make` exporting those very paths), 1 when one names another compiler - the
# self-tests' stub, say, which has no install to stage. The mode-diff reading (Z1) is on by default only for the former.
fuzz_own_compilers() {
    _r=$1
    for _p in "${ZORIL_BIN:-}:build/zoril" "${ZILC_BIN:-}:build/zilc"; do
        _v=${_p%%:*}; _w=${_p#*:}
        [ -z "$_v" ] || [ "$_v" = "$_w" ] || [ "$_v" = "$_r/$_w" ] || return 1
    done
    return 0
}
