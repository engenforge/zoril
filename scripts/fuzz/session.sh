#!/bin/sh
# scripts/fuzz/session.sh -- your own fuzz session: all cores, --mode mix, a live status line, output under
# build/fuzz/<NAME>/. Nothing is filed and nothing is cited unless --release (RELEASE=1) is given: a plain session is
# for finding out whether a change you made breaks something, not for a record. With --release the run refuses to
# start on a dirty tree, a stale build/zoril, build/zilc or build/zbuild, or without rustc, and counts a known
# fault as a failure (the short session a launch page cites; `make fuzz-release-start` is the full budget).
#
#   make fuzz-session SEEDS=1-20000 [JOBS=8] [NAME=mine] [RAN=n] [RELEASE=1]     foreground
#   make fuzz-start   SEEDS=1-20000 [JOBS=8] [NAME=mine] [RAN=n] [RELEASE=1]     the same, in the background
#
# Usage: session.sh [--background] --seeds A-B [--jobs N] [--name NAME] [--ran N] [--count N] [--release]
set -u
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO_ROOT/scripts/lib/portability.sh" 2>/dev/null || true
. "$REPO_ROOT/scripts/lib/fuzz_run.sh"

RELEASE=0; BG=0; SEEDS=""; JOBS=""; NAME=""; RAN=""; COUNT=8; PREFIX=""; EXTRA=""
while [ $# -gt 0 ]; do
    case "$1" in
        --background) BG=1; shift ;;
        --seeds) SEEDS=$2; shift 2 ;;
        --jobs) JOBS=$2; shift 2 ;;
        --name) NAME=$2; shift 2 ;;
        --ran) RAN=$2; shift 2 ;;
        --count) COUNT=$2; shift 2 ;;
        --prefix) PREFIX=$2; shift 2 ;;
        --extra) EXTRA=$2; shift 2 ;;
        --foreground) shift ;;
        --release) RELEASE=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "fuzz: unknown argument $1" >&2; exit 2 ;;
    esac
done
fuzz_seed_check "$SEEDS" || exit 2
[ "$RELEASE" -eq 0 ] || EXTRA="$EXTRA --release"
[ -n "$JOBS" ] || JOBS=$(fuzz_cores)
mkdir -p "$FUZZ_ROOT"
DIR=$(fuzz_new_dir "$PREFIX" "$NAME")

set -- --jobs "$JOBS" --seeds "$SEEDS" --count "$COUNT" --mode mix --out "$DIR" ${RAN:+--ran "$RAN"} $EXTRA
if [ "$BG" -eq 1 ]; then
    nohup "$REPO_ROOT/scripts/fuzz_jobs.sh" "$@" > "$DIR/run.out" 2>&1 &
    echo "fuzz: started in the background: $DIR"
    echo "fuzz:   watch it:  make fuzz-status RUN=$(basename "$DIR") WATCH=60"
    echo "fuzz:   stop it:   make fuzz-stop RUN=$(basename "$DIR")"
    echo "fuzz:   its totals: make fuzz-summary RUN=$(basename "$DIR")"
    exit 0
fi
"$REPO_ROOT/scripts/fuzz_jobs.sh" "$@" 2>&1 | tee "$DIR/run.out"
"$REPO_ROOT/scripts/fuzz/status.sh" --run "$DIR" --findings-only; frc=$?
echo
echo "fuzz: the run directory is $DIR"
echo "fuzz: a [FAULT] or [CANDIDATE] above is a program the compiler should have refused or got wrong:"
echo "fuzz:   reproduce one seed with   ./scripts/fuzz_safe.sh --seeds S-S --keep"
echo "fuzz:   then minimise it and file it as described in doc/developer_guide.md (Fuzzing)"
exit $frc
