#!/bin/sh
# scripts/check_reject_diff.sh — the rejection differential (AGENTS.md, "A change that makes a checker
# accept more"): which programs does a change make the compiler accept or refuse that its base did not.
#
# Removing a false positive or making an analysis more precise turns some route that failed closed by
# accident into one that fails open (A3.1 and A3.2 each did, and each passed its own probes). This builds
# the base commit's compiler in a scratch worktree, runs it and the change's compiler over every
# store-grid cell and twin and every safety probe (front end only), and builds every probe with each side's
# `zbuild` too (a separate build checks less than a whole-program one, and A3.1's regression was zbuild's
# alone). It prints one line per difference:
#
#   NEWLY_ACCEPTED <program> (<expectation>)    the base refused it, the change accepts it
#   NEWLY_REJECTED <program> (<first error>)    the base accepted it, the change refuses it
#
# and exits 1 on a newly accepted program that must be refused - an unsafe grid cell, a `compile_reject`
# or `known_gap` probe - unless the line is listed, with a reason, in the --allow file (one
# `<program-name> <reason>` per line, the program by its file name). Newly rejected programs never fail the
# run: they are over-rejections, listed for the author to read.
#
# What it can see: the programs it runs are the store grid and the probes. Run on the parents of A3.1 and A3.2,
# every NEWLY_ACCEPTED line was a probe written after those regressions were found; the grid contributed
# none. So it catches a re-break of a known route, and a new loosening only where a probe or a grid cell
# already reaches it (the grid axes that would widen it are S1.2's).
#
# Usage: scripts/check_reject_diff.sh [--allow FILE] [--change COMMIT] [--jobs N] [--probes-only] [BASE-COMMIT]
#   BASE-COMMIT  the compiler to compare against (default HEAD)
#   --change     compare a commit instead of the working tree (built in a second scratch worktree)
#   --probes-only  skip the store grid (a quick run, and the test's)
#   --bins B C   (a test hook) use the directories B and C, each holding `zoril` and `zbuild` and a
#                `stdlib/`, instead of building anything
#
# The base side's front-end verdicts are cached in build/reject-diff-cache/ (REJECT_DIFF_CACHE names another
# directory, and is what turns the cache on under --bins; REJECT_DIFF_NO_CACHE=1 turns it off;
# REJECT_DIFF_SEED fixes the sample). On a hit the programs a stale verdict could hide are rerun fresh and
# must agree with it, so no blocking line comes from the cache alone: every line the run prints, and every
# block, rests on a fresh verdict. What a stale entry can still do is leave out a line that does not block
# (a newly refused program, or a newly accepted one that may be accepted), because a program where the
# cached base verdict agrees with the change side is rerun only if the sample picks it. An entry therefore
# serves at most 4 hits, so a stale one lasts at most 4 runs; a run that a completion note or a review
# cites is made with REJECT_DIFF_NO_CACHE=1.
#
# Each run works in its own build/reject-diff-<pid>/, so two runs at once (make test runs this script's
# self-test beside preflight's) do not clear each other's files. The scratch worktrees are removed on exit,
# and the directory too when the run passes; a failed run keeps its files (report.txt, front_*.txt) until
# the next run starts, which also removes what a killed run left. build/zoril is never touched:
# the base worktree's build/ is seeded with copies of it and rebuilt from the base source, or, when the
# seed refuses the base source, built through stage1 instead.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 2
. scripts/lib/portability.sh
PROBES_DIR="${REJECT_DIFF_PROBES_DIR:-$REPO_ROOT/bench/safety_matrix/probes}"

ALLOW=""
CHANGE=""
BASE="HEAD"
JOBS=$(nproc_count 2>/dev/null || echo 4)
BINS_BASE=""
BINS_CHANGE=""
PROBES_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --allow) ALLOW="$2"; shift 2 ;;
        --change) CHANGE="$2"; shift 2 ;;
        --jobs|-j) JOBS="$2"; shift 2 ;;
        --probes-only) PROBES_ONLY=1; shift ;;
        --bins) BINS_BASE="$2"; BINS_CHANGE="$3"; shift 3 ;;
        -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "check_reject_diff: unknown option $1" >&2; exit 2 ;;
        *) BASE="$1"; shift ;;
    esac
done

for old in "$REPO_ROOT"/build/reject-diff-*; do
    pid=${old##*-}
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null || rm -rf "$old"
done
git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1
WORK="$REPO_ROOT/build/reject-diff-$$"
rm -rf "$WORK"
mkdir -p "$WORK"
WORKTREES=""
CACHE_TMP=""
cleanup() {
    rc=$?
    if [ -n "$CACHE_TMP" ]; then rm -rf "$CACHE_TMP"; fi
    for wt in $WORKTREES; do
        git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
    done
    git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1
    if [ "$rc" -eq 0 ]; then
        rm -rf "$WORK"
    else
        echo "check_reject_diff: its files are kept in $WORK" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# REJECT_DIFF_MAKE replaces `make` in the scratch builds (a test hook: scripts/test_preflight.sh).
MAKE_CMD="${REJECT_DIFF_MAKE:-make}"

# A scratch tree of COMMIT with a compiler built from its source, seeded with the working tree's. When
# the change adds a rule the base source breaks, the working tree's compiler refuses to build the base
# (Z-0007's refused main's src/), so the seeded build fails; the tree's compiler is then built the way a
# fresh checkout builds it - through stage1, from COMMIT's own source - and the seed is not needed.
build_tree() { # build_tree COMMIT DIR
    git -C "$REPO_ROOT" worktree add -q --detach "$2" "$1" || { echo "check_reject_diff: cannot check out $1" >&2; exit 2; }
    WORKTREES="$WORKTREES $2"
    mkdir -p "$2/build"
    _log="$WORK/build_$(basename "$2").log"
    for f in zoril zilc runtime.o; do cp "$REPO_ROOT/build/$f" "$2/build/$f" || { echo "check_reject_diff: build/$f is missing; run make first" >&2; exit 2; }; done
    if (cd "$2" && $MAKE_CMD > "$_log" 2>&1 && $MAKE_CMD build/zbuild >> "$_log" 2>&1); then
        return 0
    fi
    echo "check_reject_diff: the seeded build of $1 failed; building its compiler through stage1 from its own source (see $_log)" >&2
    rm -f "$2/build/zoril" "$2/build/zilc" "$2/build/zbuild"
    if ! (cd "$2" && echo "--- rebuilt through stage1 ---" >> "$_log" && $MAKE_CMD >> "$_log" 2>&1 && $MAKE_CMD build/zbuild >> "$_log" 2>&1); then
        echo "check_reject_diff: building $1 failed, seeded and through stage1; see $_log" >&2
        exit 2
    fi
}

if [ -n "$BINS_BASE" ]; then
    BASE_DIR="$BINS_BASE"; CHANGE_DIR="$BINS_CHANGE"
else
    BASE_DIR="$WORK/base"
    build_tree "$BASE" "$BASE_DIR"
    if [ -n "$CHANGE" ]; then
        CHANGE_DIR="$WORK/change"
        build_tree "$CHANGE" "$CHANGE_DIR"
    else
        CHANGE_DIR="$REPO_ROOT"
    fi
fi

# The programs: every grid cell and twin, every safety probe.
if [ "$PROBES_ONLY" -eq 1 ]; then
    : > "$WORK/programs.txt"
else
    if [ -n "${REJECT_DIFF_GRID_DIR:-}" ]; then
        # A test hook: a small stand-in grid, so the test need not generate the 69,000 programs.
        mkdir -p "$WORK/grid" && cp -R "$REJECT_DIFF_GRID_DIR/." "$WORK/grid/"
    else
        lua scripts/fuzz/store_grid.lua --generate-all "$WORK/grid" > /dev/null || { echo "check_reject_diff: the grid did not generate" >&2; exit 2; }
    fi
    find "$WORK/grid" -name '*.zrl' | sort > "$WORK/programs.txt"
fi
ls "$PROBES_DIR"/*.zrl | sort > "$WORK/probes.txt"
cat "$WORK/probes.txt" >> "$WORK/programs.txt"

cat > "$WORK/run_front.sh" << 'EOF'
#!/bin/sh
. scripts/lib/portability.sh
# run_front.sh TREE FILE... -> "<file> <rc> <first error>"
tree="$1"; shift
d=$(mktemp -d)
out_file="$d/out"
for f in "$@"; do
    run_with_timeout -k 2s 60s "$tree/build/zoril" -I "stdlib=$tree/stdlib" --emit-zil -o /dev/null "$f" > "$out_file" 2>&1 < /dev/null
    rc=$?
    first=
    IFS= read -r first < "$out_file"
    err=${first#* }
    printf '%s %s %.90s\n' "$f" "$rc" "$err"
done
rm -rf "$d"
EOF
cat > "$WORK/run_zbuild.sh" << 'EOF'
#!/bin/sh
. scripts/lib/portability.sh
# run_zbuild.sh TREE SCRATCH FILE... -> "<file> <rc>"
tree="$1"; scratch="$2"; shift 2
for f in "$@"; do
    d=$(mktemp -d "$scratch/zb.XXXXXX")
    run_with_timeout -k 2s 120s "$tree/build/zbuild" -I "stdlib=$tree/stdlib" --cache-dir "$d/c" -o "$d/out" "$f" > /dev/null 2>&1 < /dev/null
    echo "$f $?"
    rm -rf "$d"
done
EOF
chmod +x "$WORK/run_front.sh" "$WORK/run_zbuild.sh"
mkdir -p "$WORK/scratch"

front_side() { # front_side TREE OUT [LIST]: the front end's verdict on each program of LIST (default: all)
    xargs -P "$JOBS" -n 40 "$WORK/run_front.sh" "$1" < "${3:-$WORK/programs.txt}" | sort > "$2"
}
zbuild_side() { # zbuild_side LABEL TREE
    xargs -P "$JOBS" -n 20 "$WORK/run_zbuild.sh" "$2" "$WORK/scratch" < "$WORK/probes.txt" | sort > "$WORK/zbuild_$1.txt"
}

# What each program is expected to do: an unsafe cell, a probe that must be refused or is a known gap
# (refuse), a twin or an accepted probe (accept).
expectation() { # expectation FILE
    case "$1" in
        *.unsafe.zrl) echo unsafe-cell ;;
        *.twin.zrl) echo safe-twin ;;
        *)
            e=$(sed -n 's|^// expected: *\([a-z_]*\).*|\1|p' "$1" | head -n 1)
            echo "probe-${e:-accept}"
            ;;
    esac
}

# The base side's front-end verdicts are the input that stays fixed while a change is iterated, so they are
# cached under a key made of content alone: the base compiler, its stdlib, every program of the set
# (the whole probes tree, which holds imported libraries too) and the runner script. A hit never decides a
# blocking line: the programs a verdict could hide (every must-refuse program the change accepts, every
# program the two sides disagree on) and a seeded sample of the rest are rerun fresh and must agree.
CACHE_FORMAT=1
CACHE_MAX_HITS=4
SAMPLE_RATE="${REJECT_DIFF_SAMPLE:-0.02}"
CACHE_DIR=""
if [ -z "${REJECT_DIFF_NO_CACHE:-}" ]; then
    if [ -n "${REJECT_DIFF_CACHE:-}" ]; then
        CACHE_DIR="$REJECT_DIFF_CACHE"
    elif [ -z "$BINS_BASE" ]; then
        CACHE_DIR="$REPO_ROOT/build/reject-diff-cache"
    fi
fi

dir_digest() { # dir_digest DIR: a hash of every file's relative path and content
    (cd "$1" && find . -type f | LC_ALL=C sort | xargs sh -c '. "$0/scripts/lib/portability.sh"; sha256_of "$@"' "$REPO_ROOT") \
        | LC_ALL=C sort | sha256_of | cut -d' ' -f1
}

# The grid lives under this run's scratch directory, so a stored verdict names it relative to a root that
# does not change between runs.
to_relative() {
    awk -v g="$WORK/grid/" -v p="$PROBES_DIR/" '{
        if (index($0, g) == 1) $0 = "grid/" substr($0, length(g) + 1)
        else if (index($0, p) == 1) $0 = "probes/" substr($0, length(p) + 1)
        print }'
}
to_absolute() {
    awk -v g="$WORK/grid/" -v p="$PROBES_DIR/" '{
        if (index($0, "grid/") == 1) $0 = g substr($0, 6)
        else if (index($0, "probes/") == 1) $0 = p substr($0, 8)
        print }'
}

CACHE_NOTE="base verdicts: fresh (no cache)"
CACHE_BAD=0
CACHE_TMP=""
if [ -n "$CACHE_DIR" ]; then
    mkdir -p "$CACHE_DIR"
    for old in "$CACHE_DIR"/.tmp-*; do
        pid=${old##*-}
        case "$pid" in ''|*[!0-9]*) continue ;; esac
        kill -0 "$pid" 2>/dev/null || rm -rf "$old"
    done
    CACHE_TMP="$CACHE_DIR/.tmp-$$"
    KEY=$(
        {
            echo "format $CACHE_FORMAT probes-only $PROBES_ONLY"
            sha256_of "$BASE_DIR/build/zoril" | cut -d' ' -f1
            dir_digest "$BASE_DIR/stdlib"
            if [ "$PROBES_ONLY" -eq 0 ]; then dir_digest "$WORK/grid"; fi
            dir_digest "$PROBES_DIR"
            sha256_of "$WORK/run_front.sh" | cut -d' ' -f1
        } | sha256_of | cut -d' ' -f1
    )
    ENTRY="$CACHE_DIR/$KEY"
fi

front_side "$CHANGE_DIR" "$WORK/front_change.txt"
BASE_FRONT_START=$(date +%s)

# An entry that has served its hits is deleted and the run is a miss, which stores a fresh one. A lost
# update under two runs at once costs one extra hit and nothing else.
if [ -n "$CACHE_DIR" ] && [ -f "$ENTRY/hits" ] && [ "$(cat "$ENTRY/hits")" -ge "$CACHE_MAX_HITS" ]; then
    rm -rf "$ENTRY"
fi

if [ -n "$CACHE_DIR" ] && [ -f "$ENTRY/front_base.txt" ] \
    && [ "$(wc -l < "$ENTRY/front_base.txt" | tr -d ' ')" = "$(wc -l < "$WORK/programs.txt" | tr -d ' ')" ]; then
    to_absolute < "$ENTRY/front_base.txt" | sort > "$WORK/front_cached.txt"
    grep '\.unsafe\.zrl$' "$WORK/programs.txt" > "$WORK/mustrefuse.txt" || true
    while read -r prog; do
        case "$(expectation "$prog")" in
            probe-compile_reject|probe-known_gap) printf '%s\n' "$prog" >> "$WORK/mustrefuse.txt" ;;
        esac
    done < "$WORK/probes.txt"
    SEED="${REJECT_DIFF_SEED:-$(date +%s)}"
    # Rerun fresh: (a) a must-refuse program the change accepts, (b) a program the two sides disagree on,
    # (c) a seeded sample of the rest.
    awk -v seed="$SEED" -v rate="$SAMPLE_RATE" '
        FILENAME == ARGV[1] { must[$1] = 1; next }
        FILENAME == ARGV[2] { b[$1] = $2; next }
        FILENAME == ARGV[3] { c[$1] = $2; next }
        { p = $1
          pick = ((p in must) && c[p] == 0) || ((b[p] != 0) != (c[p] != 0))
          if (!pick) { if (!seeded) { srand(seed); seeded = 1 } pick = (rand() < rate) }
          if (pick) print p }' \
        "$WORK/mustrefuse.txt" "$WORK/front_cached.txt" "$WORK/front_change.txt" "$WORK/programs.txt" > "$WORK/rerun.txt"
    front_side "$BASE_DIR" "$WORK/front_fresh.txt" "$WORK/rerun.txt"
    nfresh=$(wc -l < "$WORK/rerun.txt" | tr -d ' ')
    awk 'NR == FNR { rc[$1] = $2; next } ($1 in rc) && rc[$1] != $2 { print $1 }' \
        "$WORK/front_cached.txt" "$WORK/front_fresh.txt" > "$WORK/disagree.txt"
    if [ -s "$WORK/disagree.txt" ]; then
        echo "reject-diff: cache entry $KEY disagreed on $(head -n 1 "$WORK/disagree.txt") ($(wc -l < "$WORK/disagree.txt" | tr -d ' ') programs); the entry is deleted" >&2
        rm -rf "$ENTRY"
        CACHE_BAD=1
        CACHE_NOTE="base verdicts: cache $(echo "$KEY" | cut -c1-12) DISAGREED, rerun in full"
        front_side "$BASE_DIR" "$WORK/front_base.txt"
    else
        awk 'NR == FNR { line[$1] = $0; next } { print ($1 in line) ? line[$1] : $0 }' "$WORK/front_fresh.txt" "$WORK/front_cached.txt" | sort > "$WORK/front_base.txt"
        touch "$ENTRY"
        echo $(( $(cat "$ENTRY/hits" 2>/dev/null || echo 0) + 1 )) > "$ENTRY/hits.tmp-$$" && mv "$ENTRY/hits.tmp-$$" "$ENTRY/hits"
        CACHE_NOTE="base verdicts: cache $(echo "$KEY" | cut -c1-12), $nfresh rerun fresh, sample seed $SEED"
    fi
else
    front_side "$BASE_DIR" "$WORK/front_base.txt"
    if [ -n "$CACHE_DIR" ]; then
        # A timeout under load is not a verdict, and a killed run must leave no entry: the entry is
        # written under a temporary name and moved into place.
        if [ "$(wc -l < "$WORK/front_base.txt" | tr -d ' ')" = "$(wc -l < "$WORK/programs.txt" | tr -d ' ')" ] \
            && ! awk '$2 == 124 || $2 == 137 { found = 1 } END { exit !found }' "$WORK/front_base.txt"; then
            rm -rf "$CACHE_TMP"
            mkdir -p "$CACHE_TMP"
            to_relative < "$WORK/front_base.txt" > "$CACHE_TMP/front_base.txt"
            mv "$CACHE_TMP" "$ENTRY"
            CACHE_NOTE="base verdicts: fresh, stored as cache $(echo "$KEY" | cut -c1-12)"
            ls -t "$CACHE_DIR" | sed '1,4d' | while read -r stale; do rm -rf "$CACHE_DIR/$stale"; done
        else
            CACHE_NOTE="base verdicts: fresh, not stored (a verdict was missing or timed out)"
        fi
    fi
fi
CACHE_NOTE="$CACHE_NOTE; base front end $(( $(date +%s) - BASE_FRONT_START )) s"
zbuild_side base "$BASE_DIR"
zbuild_side change "$CHANGE_DIR"

: > "$WORK/report.txt"
: > "$WORK/blocking.txt"
compare() { # compare KIND FILE_BASE FILE_CHANGE
    awk 'NR==FNR { rc[$1] = $2; next } ($1 in rc) { print $1, rc[$1], $2 }' "$2" "$3" | while read -r prog b c; do
        if [ "$b" -ne 0 ] && [ "$c" -eq 0 ]; then
            ex=$(expectation "$prog")
            printf 'NEWLY_ACCEPTED %s (%s%s)\n' "$prog" "$ex" "$1" >> "$WORK/report.txt"
            case "$ex" in
                unsafe-cell|probe-compile_reject|probe-known_gap) printf '%s\n' "$prog" >> "$WORK/blocking.txt" ;;
            esac
        elif [ "$b" -eq 0 ] && [ "$c" -ne 0 ]; then
            err=$(grep -F "$prog " "$WORK/front_change.txt" | head -n 1 | cut -d' ' -f3-)
            [ "$1" = ", zbuild" ] && err="zbuild refused it"
            printf 'NEWLY_REJECTED %s (%s)\n' "$prog" "$err" >> "$WORK/report.txt"
        fi
    done
}
compare "" "$WORK/front_base.txt" "$WORK/front_change.txt"
compare ", zbuild" "$WORK/zbuild_base.txt" "$WORK/zbuild_change.txt"
sort -u "$WORK/report.txt" -o "$WORK/report.txt"
cat "$WORK/report.txt"

# A blocking line is excused by the allow file, which names the program's file name and a reason.
fail=0
while read -r prog; do
    name=$(basename "$prog")
    if [ -n "$ALLOW" ] && grep -q "^$name " "$ALLOW" 2>/dev/null; then continue; fi
    fail=1
done < "$WORK/blocking.txt"

acc=$(grep -c '^NEWLY_ACCEPTED' "$WORK/report.txt" || true)
rej=$(grep -c '^NEWLY_REJECTED' "$WORK/report.txt" || true)
total=$(wc -l < "$WORK/programs.txt" | tr -d ' ')
echo "reject-diff: $CACHE_NOTE"
if [ "$CACHE_BAD" -ne 0 ]; then
    echo "[FAIL] reject-diff: a cached base verdict disagreed with a fresh one (the entry is deleted; an input the key misses, or a nondeterministic front end)"
    exit 1
fi
if [ "$fail" -ne 0 ]; then
    echo "[FAIL] reject-diff: a program that must be refused is newly accepted ($acc accepted, $rej refused, of $total programs)"
    exit 1
fi
echo "[PASS] reject-diff: $acc newly accepted (none that must be refused, or all allowed), $rej newly refused, of $total programs against $BASE"
exit 0
