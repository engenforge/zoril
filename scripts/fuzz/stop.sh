#!/bin/sh
# scripts/fuzz/stop.sh -- stop a background fuzz run cleanly and mark it `killed`, so its partial figures
# stay readable (`make fuzz-summary` falls back to the heartbeats).
#
#   make fuzz-stop [RUN=name-or-path]
#
# The run is marked killed only once it is known to have stopped: its wrapper answered the signal, or
# its wrapper is gone and no worker has sent a heartbeat for three intervals. A run whose wrapper this
# shell cannot see (another PID namespace, such as a container's) while its workers still send
# heartbeats is left as it is, with the shell to stop it from - marking it killed from here would leave
# it running and make the right shell's `make fuzz-stop` refuse.
set -u
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$REPO_ROOT/scripts/lib/fuzz_run.sh"
DIR=$(fuzz_run_dir "${1:-}") || { echo "fuzz: no such run" >&2; exit 2; }

state=$(run_state "$DIR")
live=$(live_workers "$DIR")
if [ "$state" != running ] && [ -z "$live" ]; then echo "fuzz: $DIR is $state; nothing to stop"; exit 0; fi
pid=$(kv "$DIR/run.status" pid)
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null
    # The wrapper's trap kills its workers and marks the run; give it a few seconds.
    n=0
    while [ "$n" -lt "${FUZZ_STOP_WAIT:-10}" ] && kill -0 "$pid" 2>/dev/null; do sleep 1; n=$((n + 1)); done
    if kill -0 "$pid" 2>/dev/null; then
        echo "fuzz: the wrapper (pid $pid) did not stop within ${FUZZ_STOP_WAIT:-10}s; $DIR is left as it is" >&2
        exit 1
    fi
elif [ -n "$live" ]; then
    echo "fuzz: $DIR is still sending heartbeats (workers:$live), but its wrapper (pid ${pid:-?}) is not visible from this shell." >&2
    echo "fuzz: it was probably started in another PID namespace (a container or sandbox): run make fuzz-stop there. Nothing was changed." >&2
    exit 1
fi
# Stopped (or dead without saying so): make sure the record says killed.
if [ "$(run_state "$DIR")" = running ]; then
    set_key "$DIR/run.status" state killed
    echo "end=$(date +%s)" >> "$DIR/run.status"
fi
for f in "$DIR"/w*.status; do [ -f "$f" ] && ! grep -q 'state=' "$f" && echo " state=killed" >> "$f"; done
echo "fuzz: $DIR stopped"
