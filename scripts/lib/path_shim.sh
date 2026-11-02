#!/bin/sh
# scripts/lib/path_shim.sh — Shared helper to build PATH shims with specific tools hidden.
#
# Builds a directory that mirrors PATH (first occurrence of each command wins),
# then removes the named tools. Run with PATH=$DIR.
# Works without root or Linux namespaces on Linux and BSDs.

tool_patterns() {
    case "$1" in
        cc) echo "cc gcc clang c99 c89" ;;
        link_cc) echo "cc gcc clang c99 c89" ;;
        as) echo "as gas" ;;
        ld) echo "ld ld.bfd ld.gold ld.lld" ;;
        awk) echo "awk gawk mawk nawk" ;;
        lua) echo "lua lua5.4 lua5.3 lua5.2 lua5.1 luajit" ;;
        tar) echo "tar bsdtar" ;;
        sha256) echo "sha256 sha256sum shasum" ;;
        *) echo "$1" ;;
    esac
}

path_without() {
    _dest="$1"
    shift
    rm -rf "$_dest"
    mkdir -p "$_dest"
    _saved_ifs="$IFS"
    IFS=:
    for _d in $PATH; do
        [ -d "$_d" ] || continue
        ln -s "$_d"/* "$_dest"/ 2>/dev/null || true
    done
    IFS="$_saved_ifs"

    for _t in "$@"; do
        for _p in $(tool_patterns "$_t"); do
            rm -f "$_dest"/$_p 2>/dev/null || true
        done
    done
}
