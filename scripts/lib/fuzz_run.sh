# scripts/lib/fuzz_run.sh -- sourced by the scripts/fuzz/ commands: which run directory, and the defaults
# every command shares. Needs REPO_ROOT; sources fuzz_progress.sh.
. "$REPO_ROOT/scripts/lib/fuzz_progress.sh"
FUZZ_ROOT="$REPO_ROOT/build/fuzz"

# fuzz_run_dir [RUN] -- the directory of RUN (a path, or a name under build/fuzz/), else the latest run
# (build/fuzz/latest names it). Prints nothing and returns 1 when there is no such run.
fuzz_run_dir() {
    _d=${1:-}
    if [ -z "$_d" ]; then [ -f "$FUZZ_ROOT/latest" ] && _d=$(cat "$FUZZ_ROOT/latest"); fi
    [ -n "$_d" ] || return 1
    if [ ! -d "$_d" ]; then _d="$FUZZ_ROOT/$_d"; fi
    [ -f "$_d/run.status" ] || return 1
    (cd "$_d" && pwd)
}

# fuzz_cores -- the number of CPUs, for the default of --jobs.
fuzz_cores() { nproc_count 2>/dev/null || echo 4; }

# fuzz_name -- a UTC timestamp, the default NAME of a run.
fuzz_name() { date -u +%Y%m%dT%H%M%SZ; }

# fuzz_new_dir PREFIX NAME -- creates build/fuzz/PREFIXNAME (NAME defaults to a timestamp), records it as
# the latest run and prints it.
fuzz_new_dir() {
    _n=${2:-$(fuzz_name)}
    _d="$FUZZ_ROOT/$1$_n"
    mkdir -p "$_d" && printf '%s\n' "$_d" > "$FUZZ_ROOT/latest"
    printf '%s\n' "$_d"
}

# fuzz_seed_check SEEDS -- usage error unless SEEDS looks like A-B.
fuzz_seed_check() {
    case "$1" in
        [0-9]*-[0-9]*) return 0 ;;
        *) echo "fuzz: SEEDS=A-B is required (for example SEEDS=1-20000)" >&2; return 1 ;;
    esac
}
