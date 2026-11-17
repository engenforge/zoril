#!/bin/sh
# scripts/bench_threshold_check.sh — run the cross-language benchmark and enforce
# the recorded performance regression thresholds.
#
# Wired into `make preflight`. Each host compares against its own most recent
# baseline row in `bench/records/gate_history.tsv` using tolerances in
# `bench/cross_lang/tolerances.cfg`. The first run on a new host records its
# measurement as that host's baseline and passes; every later run on that host
# fails if any axis regresses beyond its tolerance from that baseline.
#
# Re-record a host's baseline after an intentional performance change with:
#   sh scripts/bench_cross_lang.sh --record
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$REPO_ROOT/scripts/bench_cross_lang.sh" --check-thresholds "$@"
