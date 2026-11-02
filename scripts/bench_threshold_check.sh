#!/bin/sh
# scripts/bench_threshold_check.sh — run the cross-language benchmark and enforce
# the recorded performance regression thresholds.
#
# Wired into `make preflight`. The first run with no baseline auto-records the
# current measurement (so the gate is green on bootstrap); every later run fails
# if any axis regresses beyond its tolerance from the committed baseline.
#
# Re-record the baseline after an intentional performance change with:
#   sh scripts/bench_cross_lang.sh --record
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$REPO_ROOT/scripts/bench_cross_lang.sh" --check-thresholds "$@"
