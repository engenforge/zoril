#!/bin/sh
# scripts/zoril-checked.sh — build/zoril with `--checked`, for the checked test runs.
#
# A wrapper rather than a flag threaded through every caller: scripts/test.sh, the run-* scripts and
# zbuild all take the compiler as one path in $ZORIL_CC (or --compiler), so a checked run is that
# path. The compiler instruments the emitted program - released arena space stays poisoned and is
# never reused, a dead local's slot is poisoned where its scope ends, and a dropped value is
# poisoned and traps on a second drop - which turns a silent use-after-free into a fault.
#
# Usage: ZORIL_CC=scripts/zoril-checked.sh ./scripts/test.sh ...
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$REPO_ROOT/build/zoril" --checked "$@"
