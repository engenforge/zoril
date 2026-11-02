#!/bin/sh
# scripts/fuzz/pilot.sh -- the standard pilot: pre-flight, then 10,000 seeds x 8 in --mode mix with the
# cited-run checks on, into build/fuzz/pilot-<NAME>/, then the plan for RAN. About 13 minutes with 16
# workers. Its measured ratio and rate are what size the budget run.
#
#   make fuzz-pilot [NAME=n] [RAN=2500000] [JOBS=n]
set -u
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO_ROOT/scripts/lib/fuzz_run.sh"
pilot_rc=0
NAME=""; RAN=2500000; JOBS=""; SEEDS=${PILOT_SEEDS:-1-10000}; SKIP_PRE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --name) NAME=$2; shift 2 ;;
        --ran) RAN=$2; shift 2 ;;
        --jobs) JOBS=$2; shift 2 ;;
        --seeds) SEEDS=$2; shift 2 ;;
        --skip-preflight) SKIP_PRE=1; shift ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "fuzz: unknown argument $1" >&2; exit 2 ;;
    esac
done
if [ "$SKIP_PRE" -eq 0 ]; then
    "$REPO_ROOT/scripts/fuzz/preflight.sh" || { echo "fuzz-pilot: refusing to start: pre-flight failed" >&2; exit 1; }
fi
mkdir -p "$FUZZ_ROOT"
"$REPO_ROOT/scripts/fuzz/session.sh" --seeds "$SEEDS" ${JOBS:+--jobs "$JOBS"} --prefix pilot- ${NAME:+--name "$NAME"} \
    --extra "--release" || pilot_rc=$?
DIR=$(cat "$FUZZ_ROOT/latest")
echo
"$REPO_ROOT/scripts/fuzz/plan.sh" --ran "$RAN" --run "$DIR"
# The pilot is judged by its findings: a fault or a candidate fails this target after the plan is printed.
exit $pilot_rc
