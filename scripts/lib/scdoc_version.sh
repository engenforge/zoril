#!/bin/sh
# scripts/lib/scdoc_version.sh — the one scdoc version check, sourced by scripts/man_pages.sh,
# scripts/test_man_pages.sh and scripts/check_deps.sh. POSIX sh and awk only.
#
# The committed pages in doc/man/ are generated with scdoc 1.11.5. Other releases write other roff for
# the same source (paragraph macros, list markup, hyphen escapes), so a page can only be compared with
# a rendering made by 1.11.5 or newer; an older scdoc skips the comparison instead.

SCDOC_MIN=1.11.5

# scdoc_found — print the version `scdoc -v` reports ("1.11.2"), or "unknown" when it reports none a
# program can read; print nothing and fail when there is no scdoc on PATH.
scdoc_found() {
    command -v scdoc >/dev/null 2>&1 || return 1
    _sv=$(scdoc -v 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+(\.[0-9]+)*$/) { print $i; exit } }')
    printf '%s\n' "${_sv:-unknown}"
}

# scdoc_old VERSION — succeed when VERSION is older than SCDOC_MIN. An unknown version counts as older:
# a page cannot be compared with a rendering whose generator is not known.
scdoc_old() {
    case "$1" in unknown|'') return 0 ;; esac
    awk -v a="$1" -v b="$SCDOC_MIN" 'BEGIN {
        n = split(a, x, "."); m = split(b, y, ".")
        for (i = 1; i <= (n > m ? n : m); i++) {
            p = x[i] + 0; q = y[i] + 0
            if (p > q) exit 1
            if (p < q) exit 0
        }
        exit 1
    }'
}
