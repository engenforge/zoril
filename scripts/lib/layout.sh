#!/bin/sh
# scripts/lib/layout.sh — resolve bootstrap layout (private monorepo vs public release)
#
# Resolves the bootstrap compiler seeds' locations into canonical variables:
#   STAGE0_DIR: "bootstrap/stage0-c" in exported public tree, "stage0-C" in private tree
#   STAGE1_DIR: "bootstrap/stage1"   in exported public tree, "stage1"   in private tree
#
# Sourced by scripts that invoke or reference the bootstrap compiler seeds.

# Locate the root directory if REPO_ROOT is unset
if [ -n "${REPO_ROOT:-}" ]; then
    _layout_root="$REPO_ROOT"
elif [ -d "bootstrap/stage0-c" ] || [ -d "stage0-C" ]; then
    _layout_root="."
else
    _layout_root="."
    if [ -d "../bootstrap/stage0-c" ] || [ -d "../stage0-C" ]; then
        _layout_root=".."
    elif [ -d "../../bootstrap/stage0-c" ] || [ -d "../../stage0-C" ]; then
        _layout_root="../.."
    fi
fi

if [ -d "$_layout_root/bootstrap/stage0-c" ]; then
    STAGE0_DIR="bootstrap/stage0-c"
elif [ -d "$_layout_root/stage0-C" ]; then
    STAGE0_DIR="stage0-C"
else
    STAGE0_DIR="stage0-C"
fi

if [ -d "$_layout_root/bootstrap/stage1" ]; then
    STAGE1_DIR="bootstrap/stage1"
elif [ -d "$_layout_root/stage1" ]; then
    STAGE1_DIR="stage1"
else
    STAGE1_DIR="stage1"
fi

STAGE0_C_DIR="$STAGE0_DIR"
export STAGE0_DIR STAGE1_DIR STAGE0_C_DIR
unset _layout_root
