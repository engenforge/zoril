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
# The scratch worktrees are under build/reject-diff/ and are removed on exit. build/zoril is never touched:
# the base worktree's build/ is seeded with copies of it and rebuilt from the base source, or, when the
# seed refuses the base source, built through stage1 instead.
set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 2
. scripts/lib/portability.sh

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

WORK="$REPO_ROOT/build/reject-diff"
rm -rf "$WORK"
mkdir -p "$WORK"
WORKTREES=""
cleanup() {
    for wt in $WORKTREES; do
        git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
    done
    git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1
}
trap cleanup EXIT INT TERM

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
    lua scripts/fuzz/store_grid.lua --generate-all "$WORK/grid" > /dev/null || { echo "check_reject_diff: the grid did not generate" >&2; exit 2; }
    find "$WORK/grid" -name '*.zrl' | sort > "$WORK/programs.txt"
fi
ls "$REPO_ROOT"/bench/safety_matrix/probes/*.zrl | sort > "$WORK/probes.txt"
cat "$WORK/probes.txt" >> "$WORK/programs.txt"

cat > "$WORK/run_front.sh" << 'EOF'
#!/bin/sh
. scripts/lib/portability.sh
# run_front.sh TREE FILE... -> "<file> <rc> <first error>"
tree="$1"; shift
for f in "$@"; do
    out=$(run_with_timeout -k 2s 60s "$tree/build/zoril" -I "stdlib=$tree/stdlib" --emit-zil -o /dev/null "$f" 2>&1 < /dev/null)
    rc=$?
    echo "$f $rc $(printf '%s' "$out" | head -n 1 | sed 's/^[^ ]* //' | cut -c1-90)"
done
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

run_side() { # run_side LABEL TREE
    xargs -P "$JOBS" -n 40 "$WORK/run_front.sh" "$2" < "$WORK/programs.txt" | sort > "$WORK/front_$1.txt"
    xargs -P "$JOBS" -n 20 "$WORK/run_zbuild.sh" "$2" "$WORK/scratch" < "$WORK/probes.txt" | sort > "$WORK/zbuild_$1.txt"
}
run_side base "$BASE_DIR"
run_side change "$CHANGE_DIR"

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
if [ "$fail" -ne 0 ]; then
    echo "[FAIL] reject-diff: a program that must be refused is newly accepted ($acc accepted, $rej refused, of $total programs)"
    exit 1
fi
echo "[PASS] reject-diff: $acc newly accepted (none that must be refused, or all allowed), $rej newly refused, of $total programs against $BASE"
exit 0
