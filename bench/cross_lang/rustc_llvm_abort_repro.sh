#!/bin/sh
# bench/cross_lang/rustc_llvm_abort_repro.sh — reproduce the released-rustc abort on the generated
# straight-line shape.
#
# Observed 2026-10-10 with rustc 1.99.0 (b940084d7 2026-09-28) (Arch Linux rust 1:1.99.0-1):
#
#   $ sh bench/cross_lang/rustc_llvm_abort_repro.sh
#   ...
#   /usr/lib/libLLVM.so.23.1(+0x21e0099) [0x7fd2a61cd099]
#   ### cycle encountered after 4 frames with period 6
#   cargo exit status: 101
#
# The input is the benchmark's generated multi-file project in its flat shape: one `main` that calls
# all 3,000 generated functions in one straight line, with inputs no optimizer can fold (see --shape
# in gen_multifile.lua). rustc's release profile aborts inside LLVM's stack-overflow handler on it.
#
# Reducing it: the same project at 40 modules x 30 functions (1,200 calls) does *not* abort, it
# finishes in 225 s, against 22 s at 600 calls, so the floor is somewhere between 1,200 and 3,000
# calls and the cost curve is what makes a full reduction slow (~4 minutes per attempt).
#
# What is specific to the abort: the release profile, and the flat shape. The dev profile compiles
# the full 3,000-call project in about 1.8 s, and the realistic "tree" shape (each module's driver
# calls its own functions, main calls the drivers) in 4.2 s under `--release`. The benchmark
# therefore measures Rust's release build on the tree shape (workload 3c) and the flat comparison
# unoptimized, rather than switching a mode silently.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${1:-$REPO_ROOT/build/bench/rustc_repro}"

lua "$REPO_ROOT/bench/cross_lang/gen_multifile.lua" --out-dir "$WORK" --shape flat \
    --rust-modules 100 --rust-funcs 30 \
    --zoril-modules 1 --zoril-funcs 1 --zig-modules 1 --zig-funcs 1 \
    --hare-modules 1 --hare-funcs 1 | tail -2

echo "rustc: $(rustc --version)"
echo "building $WORK/rust in the release profile (expected: abort inside LLVM, cargo exit 101)"
set +e
cargo build --release --manifest-path "$WORK/rust/Cargo.toml"
rc=$?
set -e
echo "cargo exit status: $rc (101 is the recorded abort)"
