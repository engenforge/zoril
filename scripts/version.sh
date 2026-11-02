#!/bin/sh
# scripts/version.sh — Print version string for Zoril
#
# Derived from git describe restricted to release tags (without leading 'v'),
# or the contents of a root VERSION file, or 'unknown'.
set -eu

TARGET_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd -P)}"
VERSION=""

if [ -e "$TARGET_DIR/.git" ] && command -v git >/dev/null 2>&1; then
    _desc="$(git -C "$TARGET_DIR" describe --tags --match 'v[0-9]*' --dirty 2>/dev/null || true)"
    if [ -n "$_desc" ]; then
        VERSION="${_desc#v}"
    fi
fi

if [ -z "$VERSION" ] && [ -f "$TARGET_DIR/VERSION" ]; then
    VERSION="$(tr -d '\r\n' < "$TARGET_DIR/VERSION" | sed 's/^v//')"
fi

if [ -z "$VERSION" ]; then
    VERSION="unknown"
fi

printf "%s\n" "$VERSION"
