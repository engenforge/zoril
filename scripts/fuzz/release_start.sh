#!/bin/sh
# scripts/fuzz/release_start.sh -- the cited budget run, in the background.
#
#   make fuzz-release-start SEEDS=1-N RAN=2500000 [NAME=n] [JOBS=n]
#
# Pre-flight first (any [FAIL] refuses), then `--release` over SEEDS x 8 in --mode mix into
# build/fuzz/release-<NAME>/ with the log alongside (run.out). Watch it with make fuzz-status.
set -u
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO_ROOT/scripts/lib/fuzz_run.sh"
SEEDS=""; RAN=""; NAME=""; JOBS=""; SKIP_PRE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --seeds) SEEDS=$2; shift 2 ;;
        --ran) RAN=$2; shift 2 ;;
        --name) NAME=$2; shift 2 ;;
        --jobs) JOBS=$2; shift 2 ;;
        --skip-preflight) SKIP_PRE=1; shift ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "fuzz: unknown argument $1" >&2; exit 2 ;;
    esac
done
fuzz_seed_check "$SEEDS" || exit 2
[ -n "$RAN" ] || { echo "fuzz: RAN=<compiled-and-ran target> is required" >&2; exit 2; }
if [ "$SKIP_PRE" -eq 0 ]; then
    "$REPO_ROOT/scripts/fuzz/preflight.sh" || { echo "fuzz-release-start: refusing to start: pre-flight failed" >&2; exit 1; }
fi
mkdir -p "$FUZZ_ROOT"
exec "$REPO_ROOT/scripts/fuzz/session.sh" --background --seeds "$SEEDS" --ran "$RAN" --prefix release- \
    ${NAME:+--name "$NAME"} ${JOBS:+--jobs "$JOBS"} --extra "--release"
