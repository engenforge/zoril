#!/usr/bin/env bash
#
# Phase B's safe-program fuzzer: generate well-typed programs with no `unsafe`, compile and run
# them, and compare the outcome with `rustc`'s on the Rust twin.
#
# Six readings of every program:
#   crash        any signal other than the 134 trap is a soundness bug. 134 is the deliberate
#                `zoril_user_trap`; exit 0 is the expected outcome. A zilc/qbe/as/ld failure after
#                the front end accepted the program counts too.
#   canary       a generated program writes a known value into a stack slot or an arena allocation
#                and checks what it reads back through a reference, slice or closure. Exit 92 means
#                it read the next occupant of dead storage (a use after free whose page is still
#                mapped - the crash oracle cannot see it), and exit 91 means the number of drops did
#                not match the number of constructions (a double drop or a missing one). Both are
#                faults.
#   checked      with `--checked`, an accepted program is compiled a second time through the
#                instrumented build. Its poison (165), double-drop trap (134) or fault (139) is a
#                fault too; a correct program exits 0. The unmarked canaries stay, because a scalar
#                read through a non-zero check is the only signal for some stack holes.
#   candidate    Zoril *accepts* a program `rustc` rejects: a candidate unsoundness. Rust's borrow
#                checker is the reference for the subset both languages share. A program marked
#                `// fuzz: no-rustc-diff` is skipped (arena `reset_to` cannot be modelled by the
#                Rust lifetime shim).
#   mode-diff    the program is also built with a staged `zbuild`, the way a user builds it, and the two builds
#                must agree on acceptance, the first diagnostic of a refused program, and the exit status and
#                stdout of an accepted one. A disagreement is a finding: one of the two modes is wrong. On for
#                the repository's own compilers (`--no-zbuild` turns it off).
#   infer-diff   Zoril *rejects* a program `rustc` accepts, with a borrow or region diagnostic: not a
#                safety bug, but the running measure of how much Zoril's borrow inference cannot
#                express without annotations. (`gen-bug` is the same comparison where Zoril's
#                complaint is a plain type error instead - that is the generator's own fault.)
#
# A program carrying a `// fuzz: calibration <id>` marker is a *known* hole: it is run with the hole's
# runtime switch on and off, its fault is reported under that hole's row ([KNOWN-HOLE]) and counted
# apart from the search, and it is never filed as a finding. A fault that survives the switch being off
# is *not* the hole: it is a finding, counted in `knownblind` (which must stay 0). That is what lets a
# run pass while the calibration holes are still open, and fail on anything new. The calibration
# stream (and `mix`'s copy of it) writes the marker, as do the random hole builders.
#
# A run whose result is cited refuses to start when it could not support that citation. `--release` and
# `--record-findings` already require a clean tree and both compilers reporting `HEAD`
# (`lib/fuzz_fresh.sh`); both now also require `rustc`, the differential oracle that raised both findings
# so far. And a `--release` run refuses a calibration row that is `still open`: every one of the 23 rows is
# fixed, so an open row is a regression, not the expected state. A run that records
# nothing keeps the old behaviour - no `rustc` is a `[SKIP]`, still open rows are reported, not fatal.
#
# The generator is `scripts/fuzz/gen.lua` (the repo's generator language), deterministic from
# (--seed, --count): a finding reproduces, which is what lets it become a regression test. Each
# program prints a manifest line of feature tags, which becomes the run's coverage report.
#
# Usage: scripts/fuzz_safe.sh [--seeds A-B] [--count K] [--mode grammar|templates|both|mix|mismatch|calibration]
#                             [--out DIR] [--checked|--no-checked] [--zbuild|--no-zbuild] [--keep] [--timeout S]
#                             [--record-findings] [--release] [--findings DIR]
# `--timeout S` is a CPU-time budget for a generated program, not a wall-clock limit, so the same
# program gets the same verdict whether it runs alone or in a loaded 16-worker preflight.
# Exit status: 0 with no finding, 1 with a fault or candidate (or a `still open` row under `--release`),
# 2 if the toolchain is not built or a cited run has no `rustc`.
set -u
# A fuzzed program that faults must not write a core dump (see scripts/test.sh).
ulimit -c 0 2>/dev/null || true

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ -f "$REPO_ROOT/scripts/lib/portability.sh" ]; then
    . "$REPO_ROOT/scripts/lib/portability.sh"
fi
ZORIL=${ZORIL_BIN:-$REPO_ROOT/build/zoril}
ZILC=${ZILC_BIN:-$REPO_ROOT/build/zilc}
# The backend, assembler and linker are the HOST ones - what `config.mk` calls BACKEND_BIN/ASSEMBLER_BIN/
# LINKER_BIN, what the everyday pipeline uses, and what the release evidence is about. Everything the driver
# runs is read from the environment and printed, so a run's log says which pipeline produced it, whether the
# run was started through `make` or by hand. Point BACKEND_BIN (and
# ASSEMBLER_BIN/LINKER_BIN) to exercise an alternate pipeline on purpose.
QBE=${BACKEND_BIN:-$(command -v qbe 2>/dev/null || echo qbe)}
AS=${ASSEMBLER_BIN:-$(command -v as 2>/dev/null || echo as)}
LD=${LINKER_BIN:-$(command -v ld 2>/dev/null || echo ld)}
RUNTIME_O=${RUNTIME_O:-$REPO_ROOT/build/runtime.o}
# The record of findings: `bench/fuzz/findings/`, one minimised program pair per candidate the fuzzer
# raised, each pair named in that directory's README. A run only writes there when it says so -
# `--record-findings`, `--findings DIR` or `FUZZ_FINDINGS` - because a run that cannot choose its
# directory fills the record with whatever it generated: the self-tests' stub compiler accepts every
# mismatch shape on purpose, so 30 pairs that were never findings were once copied in here by a test run,
# under a README that said "None are stored". Without one of those three the candidates stay in the run's
# own output directory, which is kept when there is one. `--reverify` reads the record.
FINDINGS=$REPO_ROOT/bench/fuzz/findings
FINDINGS_OPT=""
RECORD=0
# STRICT: this run's result will be cited (`--record-findings`, `--release`), so the compiler it ran must be
# the one HEAD builds. FUZZ_FINDINGS alone does not set it: `make test` fuzzes into a scratch directory.
STRICT=0
# RELEASE: this is the release-bar run itself (`--release`), as opposed to a run that only files findings.
# Only a release refuses a reopened calibration hole: a `--record-findings` run has to be able to record
# into a repository whose rows are known to be open, which is what `make fuzz` does.
RELEASE=0
RECORD_FLAG=0
DIFFS=$REPO_ROOT/bench/fuzz/intended_differences.txt
GEN=${FUZZ_GEN:-$REPO_ROOT/scripts/fuzz/gen.lua}

SEEDS=1-8
COUNT=3
TIMEOUT=5
MODE=grammar
KEEP=0
REVERIFY=0
# The mode-diff reading (Z1): every program is also built with a staged `zbuild`, the way a user builds it, and
# the two builds must agree. On by default for the repository's own compilers; off when # ZILC_BIN names another one (the self-tests' stub compiler has no install to stage), unless --zbuild asks.
ZBUILD_OPT=""
# The instrumented build is the second half of the runtime oracle. It is on unless `--no-checked`
# says otherwise: every program the unmarked build accepts is rebuilt with `--checked`, so a hole
# that leaves the process at exit 0 is still seen when the poison or a drop trap fires.
CHECKED=1
OUT=""
COVERAGE=1
JOBS_ARG=""
RAN_ARG=""
STATUS_ARG=""
HERE=$(cd "$(dirname "$0")" && pwd)

while [ $# -gt 0 ]; do
    case "$1" in
        --seeds) SEEDS=$2; shift 2 ;;
        --count) COUNT=$2; shift 2 ;;
        --mode) MODE=$2; shift 2 ;;
        --out) OUT=$2; shift 2 ;;
        --timeout) TIMEOUT=$2; shift 2 ;;
        --no-coverage) COVERAGE=0; shift ;;
        --keep) KEEP=1; shift ;;
        --checked) CHECKED=1; shift ;;
        --no-checked) CHECKED=0; shift ;;
        --zbuild) ZBUILD_OPT=1; shift ;;
        --no-zbuild) ZBUILD_OPT=0; shift ;;
        --reverify) REVERIFY=1; shift ;;
        --record-findings) RECORD=1; RECORD_FLAG=1; STRICT=1; shift ;;
        --release) STRICT=1; RELEASE=1; shift ;;
        --findings) FINDINGS_OPT=$2; shift 2 ;;
        --ran) RAN_ARG=$2; shift 2 ;;
        --status-every) STATUS_ARG=$2; shift 2 ;;
        --jobs) case "$2" in ''|*[!0-9]*) echo "fuzz: --jobs needs a number" >&2; exit 2 ;; esac
            JOBS_ARG=$2; shift 2 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "fuzz: unknown argument $1" >&2; exit 2 ;;
    esac
done

# The calibration holes ride the `mix` stream only. `grammar` and `both` are the clean streams the
# parallel-driver self-test uses (its runs must exit 0), and `mismatch`/`calibration` carry their own
# fixed sets. The generator's `--holes` flag is what carries this, independently of the `mix`-to-
# `both` downgrade below that puts the mismatch checklist on one seed.
HOLES=0
[ "$MODE" = "mix" ] && HOLES=1

# Which directory this run writes to. An explicit flag wins over the environment; either one is what turns
# writing on. Saying neither leaves `$FINDINGS` at the repository's record, which is where `--reverify`
# reads - the flag decides whether this run *adds* to it, not where the record is.
if [ -n "${FUZZ_FINDINGS:-}" ]; then FINDINGS=$FUZZ_FINDINGS; RECORD=1; fi
if [ -n "$FINDINGS_OPT" ]; then FINDINGS=$FINDINGS_OPT; RECORD=1; fi

# `--jobs N` with N > 1 is parallelized *outside* this script: scripts/fuzz_jobs.sh starts N ordinary runs
# over disjoint seed ranges and sums one totals line per worker, so no counter crosses a process boundary.
# The whole invocation is forwarded from the parsed values, which is why arguments before `--jobs` work.
# --ran and --status-every belong to the wrapper, so asking for one routes even a single worker through it
# (a release run refuses itself when its target is not met; silently ignoring the flag would defeat that).
if { [ -n "$JOBS_ARG" ] && [ "$JOBS_ARG" -gt 1 ]; } || [ -n "$RAN_ARG" ] || [ -n "$STATUS_ARG" ]; then
    exec "$HERE/fuzz_jobs.sh" --jobs "${JOBS_ARG:-1}" --seeds "$SEEDS" --count "$COUNT" --mode "$MODE" \
        ${OUT:+--out "$OUT"} ${TIMEOUT:+--timeout "$TIMEOUT"} ${KEEP:+--keep} \
        ${FINDINGS_OPT:+--findings "$FINDINGS_OPT"} $([ "$RECORD_FLAG" -eq 1 ] && echo --record-findings) $([ "$RELEASE" -eq 1 ] && echo --release) \
        $([ "$REVERIFY" -eq 1 ] && echo --reverify) $([ "$COVERAGE" -eq 0 ] && echo --no-coverage) \
        ${RAN_ARG:+--ran "$RAN_ARG"} ${STATUS_ARG:+--status-every "$STATUS_ARG"} \
        $([ "$CHECKED" -eq 1 ] && echo --checked || echo --no-checked) \
        ${ZBUILD_OPT:+$([ "$ZBUILD_OPT" = 1 ] && echo --zbuild || echo --no-zbuild)}
fi

# Check dependencies for fuzzing (lua generator, timeout, optional rustc oracle)
if [ "$REVERIFY" -eq 0 ]; then
    "$HERE/check_deps.sh" fuzz || exit $?

    if ! command -v timeout >/dev/null 2>&1; then
        echo "fuzz: cannot run without timeout(1)" >&2
        exit 2
    fi
fi

# Every component is either a path into this tree (`build/zoril`) or a name on PATH - `config.mk` exports
# the *names* for the assembler and linker (`ASSEMBLER_BIN ?= as`), so testing the value itself with `-e` is
# false for exactly those and a `make`-driven run came out as "missing as": check the right one.
for f in "$ZORIL" "$ZILC" "$QBE" "$AS" "$LD" "$RUNTIME_O"; do
    case "$f" in
        */*) [ -e "$f" ] || { echo "fuzz: missing $f - build the repo's tools (make)" >&2; exit 2; } ;;
        *) command -v "$f" >/dev/null 2>&1 || { echo "fuzz: $f is not on PATH - install it, or point its role variable at a path" >&2; exit 2; } ;;
    esac
done
# Which pipeline this run uses, in its own log: a run's evidence is only as good as the components it names,
# and the backend is the one that varies.
. "$HERE/lib/tree_files.sh"
. "$HERE/lib/fuzz_fresh.sh"
echo "fuzz: pipeline: $ZORIL -> $ZILC -> $QBE -> $AS -> $LD"
echo "fuzz: pipeline: $(fuzz_version "$ZORIL"); $(fuzz_version "$ZILC")"
# The compiler code this run is about: four content hashes over the tracked blobs of each directory
# minus Markdown, so the record can say which code its figures describe and a later commit can be
# compared against them (scripts/check_fuzz_fresh.sh reads the same four, from lib/fuzz_fresh.sh).
# One line, in the form the record quotes.
_fp=$(fuzz_fingerprint "$REPO_ROOT")
if [ -n "${_fp:-}" ]; then
    echo "fuzz: pipeline: fingerprint: $_fp"
else
    echo "fuzz: pipeline: fingerprint: unavailable (not a git checkout with HEAD)"
fi
# The parallel wrapper has already checked, once, before its workers started: a finding copied into the
# record by an early worker would make the tree dirty for a later one.
if [ "$STRICT" -eq 1 ] && [ -z "${FUZZ_FRESH_CHECKED:-}" ]; then
    fuzz_require_fresh "$ZORIL" "$ZILC" $(fuzz_zbuild_bin "$REPO_ROOT" "$ZBUILD_OPT") || exit 2
fi
if ! command -v lua >/dev/null 2>&1; then
    echo "fuzz: lua is needed by the generator (the repo's bench generators use it too)" >&2
    exit 2
fi
# The differential oracle. A run whose result will be cited (`--release`, `--record-findings`) must have
# it - it is the oracle that raised both findings so far - while a run that records nothing may go
# without it: `make fuzz-short` on a machine without Rust is still useful.
fuzz_require_rustc "$STRICT" "the --release differential oracle" || exit 2
RUSTC=$(fuzz_rustc)
if [ -z "$RUSTC" ]; then
    echo "[SKIP] fuzz: rustc not found - running the crash oracle only"
fi
# Which oracles this run has on, beside the pipeline in the run's own header, so the record can quote
# them from the log rather than from memory: the differential oracle that raised both findings (and its
# version), the checked build, and the two runtime oracles every generated program carries (value
# canaries and drop accounting). This is a `fuzz: pipeline:` line so that a log says what produced it.
if [ -n "$RUSTC" ]; then
    _rustc_ver=$("$RUSTC" --version 2>/dev/null | head -1)
    _rustc_desc="$RUSTC (${_rustc_ver:-no --version output})"
else
    _rustc_desc="none - the differential oracle is OFF"
fi
ZBUILD_ON=0
if [ "$ZBUILD_OPT" = 1 ] || { [ "$ZBUILD_OPT" != 0 ] && fuzz_own_compilers "$REPO_ROOT"; }; then ZBUILD_ON=1; fi
echo "fuzz: pipeline: oracles: rustc=$_rustc_desc; checked build=$([ "$CHECKED" -eq 1 ] && echo on || echo off); mode-diff (zbuild)=$([ "$ZBUILD_ON" -eq 1 ] && echo on || echo off); canaries=on; drop accounting=on"

if [ -z "$OUT" ]; then
    OUT=$(mktemp -d "${TMPDIR:-/tmp}/zfuzz.XXXXXX")
    KEEP=0
fi
# Absolute: the whole-program build prints a path as it was given and zbuild prints it absolute, so a relative --out made
# every refused program a mode-diff on the path alone.
case "$OUT" in /*) ;; *) OUT="$(pwd)/$OUT" ;; esac
mkdir -p "$OUT" "$OUT/cov"
# The mode-diff leg uses an installed `zbuild`: one staged install per run (the parallel wrapper makes it once and
# hands it to its workers through FUZZ_STAGE), one cache per worker.
ZBUILD=""; ZB_CACHE="$OUT/zbcache"
if [ "$ZBUILD_ON" -eq 1 ]; then
    STAGE=${FUZZ_STAGE:-$OUT/stage}
    if [ -z "${FUZZ_STAGE:-}" ]; then
        make -C "$REPO_ROOT" install-files DESTDIR="$STAGE" PREFIX=/usr > "$OUT/stage.log" 2>&1 \
            || { echo "fuzz: cannot stage an install for the mode-diff reading:" >&2; tail -5 "$OUT/stage.log" >&2; exit 2; }
    fi
    ZBUILD="$STAGE/usr/bin/zbuild"
    [ -x "$ZBUILD" ] || { echo "fuzz: no zbuild in the staged install ($STAGE)" >&2; exit 2; }
    mkdir -p "$ZB_CACHE" "$ZB_CACHE.checked"
fi
[ "$RECORD" -eq 1 ] && mkdir -p "$FINDINGS"

first=${SEEDS%-*}
last=${SEEDS#*-}
progs=0 accepted=0 traps=0 rejected=0 candidates=0 faults=0 inferdiff=0 genbug=0 diffs=0 expired=0
ran=0 mprogs=0 maccepted=0 mrej=0 mowning=0 mtotal=0
known=0 knownfault=0 knownfixed=0 knownskipped=0 knownblind=0
vchecked=0 vunchecked=0
modediffs=0 zbuilt=0
t134=0 t136=0
KNOWN_LOG="$OUT/known.log"
: > "$KNOWN_LOG"
found=""

# Is a Zoril diagnostic one of the borrow/lifetime ones (as opposed to a plain type error)?
is_borrow_diag() {
    grep -qE "out of scope while it is still borrowed|region escape|mutable borrow|cannot borrow|borrowed|use of moved value" "$1"
}

# The holes a program carries, from its own marker lines (`// fuzz: calibration <id>[,<id>...]`). A
# program with one is a *known* hole: its fault is reported under the hole's row and never filed as a
# finding, which is what lets a run with holes open still fail on something new. The calibration
# stream, the `mix` hole programs and the random hole builders all write the marker.
calibration_ids() {
    sed -n 's|^// fuzz: calibration \(.*\)$|\1|p' "$1" 2>/dev/null | tr '\n' ',' | sed 's/,$//'
}

classify() {   # prints: rejected | accepted | trap | timeout | drop-fault 91 | canary-fault 92 | value-fault 93 | poison-fault 165 | signal N | toolchain <step>
    # `switch` is `hole-on` for the run that enables a marked program's guarded hole; empty for the
    # ordinary run and for the switch-off run, which must be clean if the hole is the only fault.
    local prog="$1" dir="$2" checked="${3:-}" switch="${4:-}" rc=0 zflag=""
    [ "$checked" = "checked" ] && zflag="--checked"
    if ! "$ZORIL" $zflag -I "stdlib=$REPO_ROOT/stdlib" --emit-zil -o "$dir/t.zil" "$prog" >"$dir/zoril.log" 2>&1; then
        echo "rejected"; return
    fi
    if ! "$ZILC" "$dir/t.zil" "$dir/t.ssa" >"$dir/zilc.log" 2>&1; then echo "toolchain zilc"; return; fi
    if ! "$QBE" -o "$dir/t.s" "$dir/t.ssa" >/dev/null 2>&1; then echo "toolchain qbe"; return; fi
    if ! "$AS" -o "$dir/t.o" "$dir/t.s" 2>/dev/null; then echo "toolchain as"; return; fi
    if ! "$LD" -o "$dir/t.bin" "$dir/t.o" "$RUNTIME_O" 2>/dev/null; then echo "toolchain ld"; return; fi
    run_bin "$dir/t.bin" "$dir/t.out" "$switch"
}

# classify_zb PROG DIR [checked]: the same program built the way a user builds it, with the staged `zbuild`
# (one cache per worker and per build kind, kept across programs so the standard library is compiled once), and run the same
# way. Prints the same verdicts as classify; the stdout is left in DIR/z.out and the build's log in DIR/zb.log.
classify_zb() {
    local prog="$1" dir="$2" checked="${3:-}" zflag=""
    [ "$checked" = "checked" ] && zflag="--checked"
    if ! "$ZBUILD" $zflag --cache-dir "$ZB_CACHE${checked:+.checked}" -o "$dir/z.bin" "$prog" >"$dir/zb.log" 2>&1; then
        echo "rejected"; return
    fi
    run_bin "$dir/z.bin" "$dir/z.out" ""
}

# run_bin BIN OUT [SWITCH]: run a built program under the CPU-time limit and print its verdict; its stdout is
# left in OUT, which is what the mode-diff reading compares.
run_bin() {
    local bin="$1" out="$2" switch="${3:-}" rc=0 wall
    # The limit that decides an outcome is CPU time, not wall time. Under preflight load the same
    # program takes longer in wall time but consumes the same CPU seconds, so the verdict does not
    # depend on how many workers or test suites are competing; a wall-clock-only limit once made
    # two calibration programs time out in a 16-worker run and come out as blind faults, so
    # `--jobs 1` and `--jobs 16` disagreed. The wall limit stays as a backstop for a program that
    # blocks rather than computes. `timeout` exits 124 when its wall limit fires; `-k` adds 137,
    # and SIGXCPU from `ulimit -t` is 152.
    wall=$((TIMEOUT * 12))
    # Braces with the shell's own job report redirected: the shell otherwise prints "Segmentation
    # fault" for each expected crash on its own line.
    { ( ulimit -t "$TIMEOUT" 2>/dev/null; run_with_timeout -k 1s "$wall" "$bin" ${switch:+"$switch"} >"$out" 2>/dev/null </dev/null ) ; } 2>/dev/null || rc=$?
    case "$rc" in
        0)   echo "accepted" ;;
        134) echo "trap" ;;
        91)  echo "drop-fault 91" ;;
        92)  echo "canary-fault 92" ;;
        93)  echo "value-fault 93" ;;
        165) echo "poison-fault 165" ;;
        124|137|152) echo "timeout" ;;
        *)   echo "signal $rc" ;;
    esac
}

# first_error LOG: the first error line of a build log, which is what two builds of a refused program must agree on.
first_error() { grep -m1 ' error: ' "$1" 2>/dev/null; }

# same_diagnostic PROG W1 Z1: whether two first diagnostics agree. An error inside a generic body of an imported
# module is reported by `zbuild` at the line of the interface it reads, not of the source, so the A7.10 program
# (`box(allocator)` in an imported generic function) is compared by message and file; every other program, by line too.
same_diagnostic() {
    case "$1" in
        *_box_allocator_in_interface*)
            [ "$(printf '%s' "$2" | sed 's/\.zrl:[0-9]*:[0-9]*:/.zrl:/')" = "$(printf '%s' "$3" | sed 's/\.zrl:[0-9]*:[0-9]*:/.zrl:/')" ] ;;
        *) [ "$2" = "$3" ] ;;
    esac
}

# mode_diff WHOLE-VERDICT PROG DIR [checked]: builds PROG with the staged zbuild and prints how it differs from the
# whole-program build's verdict (already in DIR: zoril.log, t.out), or nothing when the two agree: both refuse it
# with the same first diagnostic, or both accept it and run to the same exit status and stdout. One of the two
# modes is wrong whenever they disagree.
mode_diff() {
    [ "$ZBUILD_ON" -eq 1 ] || return 0
    local whole="$1" prog="$2" dir="$3" checked="${4:-}" zv w1 z1
    zv=$(classify_zb "$prog" "$dir" "$checked")
    if [ "$zv" != "$whole" ]; then echo "whole-program: $whole; zbuild: $zv"; return; fi
    case "$whole" in
        rejected)
            w1=$(first_error "$dir/zoril.log"); z1=$(first_error "$dir/zb.log")
            same_diagnostic "$prog" "$w1" "$z1" || echo "the first diagnostic differs - whole-program: ${w1:-none}; zbuild: ${z1:-none}" ;;
        toolchain*|timeout) ;;
        *) cmp -s "$dir/t.out" "$dir/z.out" || echo "stdout differs (whole-program $(wc -c < "$dir/t.out") bytes, zbuild $(wc -c < "$dir/z.out") bytes)" ;;
    esac
}

# mode_build_diff WHOLE-VERDICT PROG DIR: the same comparison for a program that is not expected to run alike (a marked
# known hole is run with its switch on in one build only): whether the two builds accept it, and for a refused one
# whether they give the same first diagnostic. A hole the whole-program build refuses must be refused under zbuild as
# well, and the reverse; this is how a `.zri` that loses a contract shows (the hole programs are what depend on one).
mode_build_diff() {
    [ "$ZBUILD_ON" -eq 1 ] || return 0
    local whole="$1" prog="$2" dir="$3" w1 z1
    if "$ZBUILD" --cache-dir "$ZB_CACHE" -o "$dir/z.bin" "$prog" >"$dir/zb.log" 2>&1; then
        [ "$whole" != rejected ] || echo "whole-program: rejected; zbuild: built it"
    else
        if [ "$whole" != rejected ]; then echo "whole-program: built it ($whole); zbuild: rejected"; return; fi
        w1=$(first_error "$dir/zoril.log"); z1=$(first_error "$dir/zb.log")
        same_diagnostic "$prog" "$w1" "$z1" || echo "the first diagnostic differs - whole-program: ${w1:-none}; zbuild: ${z1:-none}"
    fi
}

# norm_trap VERDICT EXPECTED -- a program that must trap: the expected exit is `accepted` for the rest of the
# checks, anything else becomes a trap-fault naming both codes.
norm_trap() {
    local g
    case "$1" in
        trap) g=134 ;;
        "signal "*) g=${1#signal } ;;
        accepted) g=0 ;;
        *) echo "$1"; return ;;
    esac
    if [ "$g" = "$2" ]; then echo accepted; else echo "trap-fault expected exit $2, got $g"; fi
}

rustc_accepts() {   # 0 if the twin compiles (borrow-checked, no binary emitted)
    [ -n "$RUSTC" ] || return 1
    "$RUSTC" --edition 2021 --crate-type bin --emit=metadata -o "$1/twin.rmeta" "$2" >"$1/rustc.log" 2>&1
}

# Every program's feature tags are appended to one file per worker, which the wrapper merges at the end by
# sorting everything and keeping what is unique. Appending without ever compacting is fine for a run of
# thousands and not for a budget: measured, the tags of one program cost 147 bytes of that file, so a
# release-bar-sized run of a few million programs would leave gigabytes per run to sort at the end - for a
# universe of a few dozen features. Rewriting the file unique as it grows keeps it a few kilobytes instead:
# 500 programs between compactions is ~7,500 lines to sort, about once every 30 seconds of a worker's life.
cov_since=0
record_cov() {   # $1 = comma-separated tags, unique per program
    local IFS=,
    for t in $1; do
        [ -n "$t" ] && printf '%s\n' "$t" >> "$OUT/cov/seen"
    done
    cov_since=$((cov_since + 1))
    if [ "$cov_since" -ge 500 ]; then
        sort -u -o "$OUT/cov/seen" "$OUT/cov/seen"
        cov_since=0
    fi
}

# --reverify: the record half of the driver, and it runs before the seed loop because it generates nothing:
# every pair in the record is re-run against BOTH oracles and reported as what it is now. A reverify run
# that went on to fuzz a default seed range would spend its time on programs nobody asked for and drop any
# candidate it raised, since the copy at the end of this script is never reached from here.
# Process rule this encodes: a finding is minimised and re-run against both oracles before it is recorded,
# and it stops the gate until it is fixed. What it must not do is stay quiet about a pair it cannot
# classify as open - reporting only the ones zoril still accepts is how 30 pairs that were never findings
# sat in the record while this check said "0 recorded finding(s) still open". So:
#   open        zoril takes it (or it traps, or it faults) and rustc still rejects the twin - the
#               disagreement stands, and the run fails.
#   fixed       zoril refuses it now - the compiler was fixed, and the pair should leave the record once
#               the test that pins the fix is named in the README.
#   never       rustc accepts the twin too: the pair was never a disagreement and means nothing here.
#   to look at  neither: the toolchain broke on it (the crash oracle counts that as a fault), the pair is
#               not a pair, or there is no rustc to ask. Nothing there is a decision, so it fails.
# A pair the README does not name fails as well: this directory is a record, and the README is where a
# record is written down - the whole point is that a reader of the README and a reader of `ls` agree.
if [ "$REVERIFY" -eq 1 ]; then
    open=0; fixed=0; never=0; odd=0; unlisted=0; pairs=0
    readme="$FINDINGS/README.md"
    for prog in "$FINDINGS"/*.zrl; do
        [ -e "$prog" ] || continue
        pairs=$((pairs + 1))
        base=$(basename "$prog")
        if ! grep -qF "$base" "$readme" 2>/dev/null; then
            echo "[REVERIFY] $base is recorded but $readme does not name it - name it there or delete the pair"
            unlisted=$((unlisted + 1))
        fi
        if [ ! -f "${prog%.zrl}.rs" ]; then
            echo "[REVERIFY] ${base%.zrl}.rs is missing - a recorded finding is a program and its twin"
            odd=$((odd + 1))
            continue
        fi
        d=$(mktemp -d "${TMPDIR:-/tmp}/zfuzz.reverify.XXXXXX")
        verdict=$(classify "$prog" "$d")
        case "$verdict" in
            accepted|trap|signal*)
                if [ -z "$RUSTC" ]; then
                    echo "[REVERIFY] $base: zoril says $verdict, and there is no rustc here to ask about the twin"
                    odd=$((odd + 1))
                elif rustc_accepts "$d" "${prog%.zrl}.rs"; then
                    echo "[REVERIFY] $base was never a disagreement: zoril says $verdict, rustc accepts the twin - delete it, or say in $readme why it is kept"
                    never=$((never + 1))
                else
                    echo "[REVERIFY] $base is still open: zoril says $verdict, rustc rejects the twin"
                    open=$((open + 1))
                fi
                ;;
            rejected)
                echo "[REVERIFY] $base is fixed: zoril rejects it now - delete the pair and name the test that pins the fix in $readme"
                fixed=$((fixed + 1))
                ;;
            *)
                echo "[REVERIFY] $base is to look at: $verdict after zoril took it, which is a fault before it is a decision"
                odd=$((odd + 1))
                ;;
        esac
        rm -rf "$d"
    done
    for twin in "$FINDINGS"/*.rs; do
        [ -e "$twin" ] || continue
        [ -f "${twin%.rs}.zrl" ] || { echo "[REVERIFY] $(basename "$twin") has no .zrl program beside it"; odd=$((odd + 1)); }
    done
    if [ "$pairs" -eq 0 ]; then
        echo "fuzz: reverify - $FINDINGS holds no program; the record is empty"
    else
        echo "fuzz: reverify - $pairs pair(s) in $FINDINGS: $open open, $fixed fixed, $never never a disagreement, $odd to look at, $unlisted not named in its README"
    fi
    # Nothing was generated, so the output directory this run created for a fuzz pass is empty: drop it
    # unless `--keep` asked for it, the way the run's own end does.
    [ "$KEEP" -eq 1 ] || rm -rf "$OUT"
    if [ "$open" -gt 0 ] || [ "$odd" -gt 0 ] || [ "$unlisted" -gt 0 ]; then exit 1; fi
    exit 0
fi

# A worker started by scripts/fuzz_jobs.sh writes its progress to FUZZ_HEARTBEAT_FILE at least every
# FUZZ_HEARTBEAT_SECS (default 60): one line of key=value, replaced atomically, so a reader can tell a
# worker that is busy from one that has hung without `ps` (a container has its own PID namespace) and
# can compute a rate and an ETA from the data. Nothing is written when the file is not named.
HB_LAST=0
heartbeat() {
    [ -n "${FUZZ_HEARTBEAT_FILE:-}" ] || return 0
    _now=$(date +%s)
    [ "$_now" -ge $((HB_LAST + ${FUZZ_HEARTBEAT_SECS:-60})) ] || [ "${1:-}" = force ] || return 0
    HB_LAST=$_now
    printf 'pid=%s from=%s seed=%s last=%s progs=%s ran=%s faults=%s candidates=%s genbug=%s knownopen=%s t=%s\n' \
        "$$" "$first" "$seed" "$last" "$progs" "$ran" "$faults" "$candidates" "$genbug" "$knownfault" "$_now" \
        > "$FUZZ_HEARTBEAT_FILE.tmp" && mv "$FUZZ_HEARTBEAT_FILE.tmp" "$FUZZ_HEARTBEAT_FILE"
}
seed=$first
heartbeat force
while [ "$seed" -le "$last" ]; do
    rm -rf "$OUT/s$seed"
    mkdir -p "$OUT/s$seed"
    # `mix` is the main stream plus the mismatch stream, and the mismatch stream is a fixed checklist
    # of shapes rather than a sample, so it rides the first seed instead of being regenerated for every
    # one: same loop, same classification, one copy of each shape per run.
    seed_mode="$MODE"
    # The mismatch stream is a fixed checklist that rides one seed, so a parallel run puts it in exactly
    # one worker and the totals do not depend on how the range was split. `MISMATCH_ON_FIRST=0` is what
    # the wrapper sets on every worker but the first.
    if [ "$MODE" = "mix" ] && { [ "$seed" != "$first" ] || [ "${MISMATCH_ON_FIRST:-1}" != "1" ]; }; then
        seed_mode="both"
    fi
    while read -r tags stem owning total expect trapexp swarmexp; do
        [ -n "${stem:-}" ] || continue
        # Two streams: the main one (grammar and templates) and the mismatch stream, which the
        # generator emits one shape per program into `mismatch/`. A mismatch program is expected to be
        # refused, so its outcomes are counted and reported apart from the main stream's.
        in_mismatch=0
        case "$stem" in */mismatch/*) in_mismatch=1 ;; esac
        if [ "$in_mismatch" -eq 1 ]; then mprogs=$((mprogs + 1)); else progs=$((progs + 1)); fi
        # The manifest's last two fields are the program's values: how many own something, and how many
        # there are. Their sum is the share the value-mix item asks to state.
        if [ -n "${owning:-}" ] && [ -n "${total:-}" ]; then
            mowning=$((mowning + owning)); mtotal=$((mtotal + total))
        fi
        record_cov "$tags"
        # The expected-value oracle: a program the generator could evaluate carries a checksum and
        # exits 93 when it differs (a miscompile with no fault). The manifest says which programs have
        # one; the rest say why not, and the totals count both so a record states how many were checked.
        case "${expect:-none}" in
            checked) [ "$in_mismatch" -eq 0 ] && vchecked=$((vchecked + 1)) ;;
            unchecked:*) [ "$in_mismatch" -eq 0 ] && vunchecked=$((vunchecked + 1)) ;;
        esac
        # A program whose Rust twin cannot model the rule says so in its own source: arena `reset_to`
        # is the case (Zoril accepts an untouched pre-mark container across it, the lifetime shim
        # cannot), and asking rustc about it would flood the candidate stream with a modelling gap.
        nodiff=0
        grep -q '// fuzz: no-rustc-diff' "$stem.zrl" 2>/dev/null && nodiff=1
        # Known holes are apart from the search, and attributed only when switching the hole off makes
        # the fault go away. Each marked program is run twice: with the guarded hole enabled
        # (`hole-on`) and with it disabled. A fault with the switch off survives the hole, so it is
        # unrelated and is a finding; only a fault that disappears belongs to the hole. Everything
        # below this branch is a program nobody has convicted yet, and any fault there is a finding.
        calib=$(calibration_ids "$stem.zrl")
        if [ -n "$calib" ]; then
            known=$((known + 1))
            mkdir -p "$OUT/s$seed/on" "$OUT/s$seed/off"
            on_verdict=$(classify "$stem.zrl" "$OUT/s$seed/on" "" hole-on)
            off_verdict=$(classify "$stem.zrl" "$OUT/s$seed/off" "")
            if [ "$ZBUILD_ON" -eq 1 ]; then
                zbuilt=$((zbuilt + 1))
                md=$(mode_build_diff "$off_verdict" "$stem.zrl" "$OUT/s$seed/off")
                if [ -n "$md" ]; then
                    modediffs=$((modediffs + 1)); faults=$((faults + 1))
                    echo "[MODE-DIFF] ${stem#$OUT/}.zrl (a known-hole program, builds compared): $md (hole: $calib)"
                    found="$found$stem.zrl "
                fi
            fi
            if [ "$off_verdict" != "accepted" ] && [ "$off_verdict" != "rejected" ] && [ "$off_verdict" != "timeout" ]; then
                knownblind=$((knownblind + 1))
                faults=$((faults + 1))
                echo "[FAULT] ${stem#$OUT/}.zrl hole switch off: $off_verdict (hole: $calib; switch on: $on_verdict) - the fault survives the hole and is not attributable to it"
                found="$found$stem.zrl "
                continue
            fi
            if [ "$off_verdict" = "timeout" ]; then
                # The runtime limit fired, so the switch-off outcome was not observed. That is not
                # evidence the hole survives: count it as not reached, never as a blind fault.
                state="not reached (timed out)"
                knownskipped=$((knownskipped + 1))
            elif [ "$off_verdict" = "rejected" ]; then
                # A refused *calibration* program is evidence the mechanism was fixed; a refused
                # random program that happens to carry a hole construct was not reached (some earlier
                # statement made it invalid), so it says nothing about the hole.
                case "$stem" in
                    */calibration/*) state="fixed (zoril refuses the calibration program)"; knownfixed=$((knownfixed + 1)) ;;
                    *) state="not reached (zoril refuses the program)"; knownskipped=$((knownskipped + 1)) ;;
                esac
            else
                hole_faulted=0
                case "$on_verdict" in
                    accepted) state="not reproduced (accepted with the hole switched on)" ;;
                    rejected) state="not reached (zoril refuses the program)"; knownskipped=$((knownskipped + 1)) ;;
                    timeout) state="not reached (timed out)"; knownskipped=$((knownskipped + 1)) ;;
                    *) state="still open (switch on: $on_verdict; switch off: accepted)"; hole_faulted=1 ;;
                esac
                # The checked build is a second runtime oracle. Both switch positions are needed: a
                # checked-build fault that remains with the switch off is a finding too.
                if [ "$CHECKED" -eq 1 ] && [ "$in_mismatch" -eq 0 ]; then
                    mkdir -p "$OUT/s$seed/con" "$OUT/s$seed/coff"
                    con_verdict=$(classify "$stem.zrl" "$OUT/s$seed/con" checked hole-on)
                    coff_verdict=$(classify "$stem.zrl" "$OUT/s$seed/coff" checked "")
                    if [ "$coff_verdict" = "timeout" ] || [ "$con_verdict" = "timeout" ]; then
                        # A run that hit the limit says nothing about the hole; attributing it
                        # would make the verdict a function of machine load.
                        state="$state; checked build: not reached (timed out)"
                    else
                        if [ "$coff_verdict" != "accepted" ]; then
                            knownblind=$((knownblind + 1))
                            faults=$((faults + 1))
                            echo "[FAULT] ${stem#$OUT/}.zrl checked build, hole switch off: $coff_verdict (hole: $calib; checked switch on: $con_verdict) - the fault survives the hole and is not attributable to it"
                            found="$found$stem.zrl "
                            continue
                        fi
                        case "$con_verdict" in
                            accepted) ;;
                            *) state="$state; checked build: $con_verdict"; hole_faulted=1 ;;
                        esac
                    fi
                fi
                [ "$hole_faulted" -eq 1 ] && knownfault=$((knownfault + 1))
            fi
            for id in ${calib//,/ }; do
                echo "[KNOWN-HOLE] $id: $state (${stem#$OUT/}.zrl)"
                printf '%s\t%s\n' "$id" "$state" >> "$KNOWN_LOG"
            done
            continue
        fi
        verdict=$(classify "$stem.zrl" "$OUT/s$seed")
        if [ "$ZBUILD_ON" -eq 1 ]; then
            zbuilt=$((zbuilt + 1))
            md=$(mode_diff "$verdict" "$stem.zrl" "$OUT/s$seed")
            if [ -n "$md" ]; then
                modediffs=$((modediffs + 1)); faults=$((faults + 1))
                echo "[MODE-DIFF] ${stem#$OUT/}.zrl: $md (tags: $tags)"
                found="$found$stem.zrl "
            fi
        fi
        # A program whose operand the generator computed must trap with the code it computed (134, or
        # 136 for the divide faults). The trap is the expected outcome, so it goes on through the rest
        # of the checks as an accepted program; exit 0 or the other code is a fault. `none` and an
        # unmarked program are judged as before.
        texp=${trapexp#trap=}
        if [ -n "$texp" ] && [ "$texp" != none ] && [ "$in_mismatch" -eq 0 ]; then
            verdict=$(norm_trap "$verdict" "$texp")
            if [ "$verdict" = accepted ]; then
                traps=$((traps + 1))
                case "$texp" in 134) t134=$((t134 + 1)) ;; 136) t136=$((t136 + 1)) ;; esac
            fi
        fi
        case "$verdict" in
            accepted)
                ran=$((ran + 1))
                accepted=$((accepted + 1))
                faulted=0
                # The instrumented build is the second runtime oracle. It is asked only about a
                # program the unmarked build accepted (a program already faulting needs no second
                # opinion) and only for the main stream (a mismatch shape is expected to be refused).
                if [ "$CHECKED" -eq 1 ] && [ "$in_mismatch" -eq 0 ]; then
                    mkdir -p "$OUT/s$seed/c"
                    cverdict=$(classify "$stem.zrl" "$OUT/s$seed/c" checked)
                    if [ "$ZBUILD_ON" -eq 1 ]; then
                        zbuilt=$((zbuilt + 1))
                        md=$(mode_diff "$cverdict" "$stem.zrl" "$OUT/s$seed/c" checked)
                        if [ -n "$md" ]; then
                            modediffs=$((modediffs + 1)); faults=$((faults + 1))
                            echo "[MODE-DIFF] ${stem#$OUT/}.zrl (checked): $md (tags: $tags)"
                            found="$found$stem.zrl "
                        fi
                    fi
                    if [ -n "$texp" ] && [ "$texp" != none ]; then cverdict=$(norm_trap "$cverdict" "$texp"); fi
                    case "$cverdict" in
                        accepted) ;;
                        134)
                            faulted=1; faults=$((faults + 1))
                            echo "[FAULT] ${stem#$OUT/}.zrl checked build: double-drop trap (134) (tags: $tags)"
                            found="$found$stem.zrl "
                            ;;
                        *)
                            faulted=1; faults=$((faults + 1))
                            echo "[FAULT] ${stem#$OUT/}.zrl checked build: $cverdict (tags: $tags)"
                            found="$found$stem.zrl "
                            ;;
                    esac
                fi
                if [ "$faulted" -eq 0 ] && [ "$in_mismatch" -eq 1 ]; then
                    # A mismatch shape is supposed to be refused. This stream's point is the shape, not the
                    # twin, and one of the fifteen twins is valid Rust - so an accepted one is a finding
                    # whatever rustc says about the other file.
                    maccepted=$((maccepted + 1))
                    candidates=$((candidates + 1))
                    echo "[CANDIDATE] ${stem#$OUT/}.zrl accepted by zoril - a mismatch shape is supposed to be refused (tags: $tags)"
                    found="$found$stem.zrl "
                fi
                if [ "$faulted" -eq 0 ] && [ "$in_mismatch" -eq 0 ] && [ "$nodiff" -eq 0 ] && [ -n "$RUSTC" ] && ! rustc_accepts "$OUT/s$seed" "$stem.rs"; then
                    codes=$(grep -oE 'error\[E[0-9]+\]' "$OUT/s$seed/rustc.log" | sort -u | tr '\n' ' ')
                    classified=""
                    for code in $codes; do
                        bare=$(printf '%s' "$code" | sed -E 's/.*\[(E[0-9]+)\].*/\1/')
                        for t in ${tags//,/ }; do
                            if grep -qE "^${bare} ${t} [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$DIFFS"; then
                                exp=$(grep -E "^${bare} ${t} " "$DIFFS" | awk '{print $3}' | head -1)
                                if [[ "$exp" < "$(date +%F)" ]]; then
                                    echo "[EXPIRED] ${stem#$OUT/}.zrl: the '${bare} ${t}' entry expired on $exp - decide it (fix, probe, or reason) instead of moving the date"
                                    expired=$((expired + 1))
                                else
                                    classified="yes"
                                fi
                            elif grep -qE "^${bare} ${t}( |$)" "$DIFFS"; then
                                echo "[UNCLASSIFIED] ${stem#$OUT/}.zrl: the '${bare} ${t}' entry has no expiry - undecided differences fail the run"
                            fi
                        done
                    done
                    if [ -n "$classified" ]; then
                        diffs=$((diffs + 1))
                        echo "[DIFF] ${stem#$OUT/}.zrl accepted by zoril, rejected by rustc (${codes}) - classified in intended_differences.txt"
                    else
                        candidates=$((candidates + 1))
                        echo "[CANDIDATE] ${stem#$OUT/}.zrl accepted by zoril, rejected by rustc: ${codes:-see log} (tags: $tags)"
                        found="$found$stem.zrl "
                    fi
                fi
                ;;
            trap)  traps=$((traps + 1)); t134=$((t134 + 1)); ran=$((ran + 1)) ;;
            drop-fault*|canary-fault*|value-fault*|poison-fault*|trap-fault*)
                faults=$((faults + 1)); ran=$((ran + 1))
                echo "[FAULT] ${stem#$OUT/}.zrl $verdict (tags: $tags)"
                found="$found$stem.zrl "
                ;;
            rejected)
                if [ "$in_mismatch" -eq 1 ]; then mrej=$((mrej + 1)); fi
                rejected=$((rejected + 1))
                # Only the main stream's refusals say anything about the generator: a mismatch-stream
                # program is expected to be refused, and its twin is a valid program, so "zoril refuses,
                # rustc accepts" is that stream working as designed rather than a generator bug.
                if [ "$in_mismatch" -eq 0 ] && [ "$nodiff" -eq 0 ] && [ -n "$RUSTC" ] && rustc_accepts "$OUT/s$seed" "$stem.rs"; then
                    if is_borrow_diag "$OUT/s$seed/zoril.log"; then
                        inferdiff=$((inferdiff + 1))
                        [ $((inferdiff % 5)) -eq 1 ] && \
                            echo "[INFER-DIFF] ${stem#$OUT/}.zrl rejected by zoril, accepted by rustc: $(head -1 "$OUT/s$seed/zoril.log")"
                    else
                        genbug=$((genbug + 1))
                        [ $((genbug % 5)) -eq 1 ] && \
                            echo "[GEN-BUG] ${stem#$OUT/}.zrl rejected by zoril (type error), accepted by rustc: $(head -1 "$OUT/s$seed/zoril.log")"
                    fi
                fi
                ;;
            toolchain*)
                faults=$((faults + 1))
                echo "[FAULT] $verdict after the front end accepted ${stem#$OUT/}.zrl (tags: $tags)"
                found="$found$stem.zrl "
                ;;
            signal*)
                faults=$((faults + 1)); ran=$((ran + 1))
                echo "[FAULT] ${stem#$OUT/}.zrl $verdict (anything but the 134 trap is a finding) (tags: $tags)"
                found="$found$stem.zrl "
                ;;
            timeout)
                # The CPU-time limit fired. That is deterministic with respect to load (see
                # classify), and a generated program that computes for the whole budget is a
                # finding: the generator is supposed to emit terminating programs. It is not
                # counted in `ran`, which is "compiled and ran to completion".
                faults=$((faults + 1))
                echo "[FAULT] ${stem#$OUT/}.zrl timed out after ${TIMEOUT}s of CPU (tags: $tags)"
                found="$found$stem.zrl "
                ;;
        esac
    done < <(lua "$GEN" --seed "$seed" --count "$COUNT" --mode "$seed_mode" --holes "$HOLES" --out "$OUT/s$seed")
    # Nobody looks at a program's scratch again. What a finding needs is its pair of sources, and that is
    # copied out of here at the end of the run; everything else in this seed's directory - the sources and
    # logs of `$COUNT` programs, and the artifacts each program reused - is exactly what the next seed
    # overwrites. So it goes now, unless this seed raised a finding. Measured on this tree: one program
    # leaves 3.1 files and 76 KiB behind, so a release-bar-sized run of a few million generated programs
    # would end at hundreds of gigabytes and tens of millions of files, against the 153 GB of disk and 26
    # million free inodes here - a budget run that fills the filesystem is not a run. What is left behind
    # now is a worker's merged coverage and its log.
    case " $found " in
        *"$OUT/s$seed/"*) ;;    # this seed raised a finding: its pair is copied out at the end
        *) rm -rf "$OUT/s$seed" ;;
    esac
    # A budget run is hours long, and this is the only window into it while it runs: without a heartbeat a
    # log that is not growing cannot be told from a worker that has hung. Once every 1000 seeds is about a
    # quarter of an hour of one worker, so a run of the tens of seeds the tests and `fuzz-short` use prints
    # none of these at all.
    if [ $((seed % 1000)) -eq 0 ] && [ "$seed" -lt "$last" ]; then
        echo "[PROGRESS] seed $seed of $last: $progs program(s) generated, $ran compiled and ran, $candidates candidate(s), $faults fault(s)"
    fi
    heartbeat
    seed=$((seed + 1))
done


echo "fuzz: $progs program(s) in the main stream, $ran compiled and ran, $((accepted - maccepted)) accepted, $traps trap(134), $((rejected - mrej)) rejected by zoril, $faults fault(s), $candidates rustc candidate(s)"
if [ "$known" -gt 0 ]; then
    echo "fuzz: known holes (apart from the search): $known program(s), $knownfault still open, $knownfixed fixed, $knownskipped not reached, $knownblind faulted with the switch off (must be 0), $((known - knownfault - knownfixed - knownskipped - knownblind)) not reproduced in this run"
    sort "$KNOWN_LOG" | uniq -c | while read -r n id state; do
        printf 'fuzz: known hole %s: %s (%s program(s))\n' "$id" "$state" "$n"
    done
fi
echo "fuzz: mismatch stream: $mprogs program(s), $mrej refused (the expected outcome), $maccepted accepted - an accepted mismatch is a finding"
echo "fuzz: disagreements - $inferdiff zoril-rejects/rustc-accepts with a borrow diagnostic, $genbug generator type error(s)"
if [ "$mtotal" -gt 0 ]; then
    echo "fuzz: value mix: $mowning of $mtotal values own something ($((mowning * 100 / mtotal))%)"
fi
echo "fuzz: $diffs accepted-with-a-listed-difference (bench/fuzz/intended_differences.txt)"
echo "fuzz: traps by exit code (an unpredicted trap is always 134; 136 only when the generator computed it): $t134 with exit 134, $t136 with exit 136"
echo "fuzz: expected-value oracle: $vchecked program(s) carried a checksum, $vunchecked could not be followed by the generator's interpreter"
echo "fuzz: mode-diff (whole-program vs staged zbuild): $zbuilt build(s) compared, $modediffs disagreement(s) - each is a finding"

# One machine-readable line per run. `scripts/fuzz_jobs.sh` starts several ordinary runs and sums these
# with awk, so no counter ever crosses a process boundary: summing in the parent is where an earlier
# in-driver attempt went wrong, reading zero for every counter while the coverage (merged through a
# file) came out right.
printf 'fuzz-totals: progs=%s accepted=%s traps=%s rejected=%s candidates=%s faults=%s inferdiff=%s genbug=%s diffs=%s expired=%s ran=%s mprogs=%s maccepted=%s mrej=%s mowning=%s mtotal=%s known=%s knownfault=%s knownfixed=%s knownskipped=%s knownblind=%s vchecked=%s vunchecked=%s t134=%s t136=%s zbuilt=%s modediffs=%s\n' \
    "$progs" "$accepted" "$traps" "$rejected" "$candidates" "$faults" "$inferdiff" "$genbug" "$diffs" \
    "$expired" "$ran" "$mprogs" "$maccepted" "$mrej" "$mowning" "$mtotal" \
    "$known" "$knownfault" "$knownfixed" "$knownskipped" "$knownblind" "$vchecked" "$vunchecked" "$t134" "$t136" "$zbuilt" "$modediffs"

cov_bad=0
if [ "$COVERAGE" -eq 1 ]; then
    sort -u "$OUT/cov/seen" > "$OUT/cov/seen.uniq"
    lua "$GEN" --features > "$OUT/cov/declared"
    total=$(wc -l < "$OUT/cov/declared" | tr -d ' ')
    hit=$(grep -xF -f "$OUT/cov/declared" "$OUT/cov/seen.uniq" | wc -l | tr -d ' ')
    echo "fuzz: coverage $hit/$total features"
    missing=$(grep -vxF -f "$OUT/cov/seen.uniq" "$OUT/cov/declared" | tr '\n' ' ')
    [ -n "$missing" ] && echo "fuzz: never generated: $missing"
    undeclared=$(grep -vxF -f "$OUT/cov/declared" "$OUT/cov/seen.uniq" | tr '\n' ' ')
    if [ -n "$undeclared" ]; then
        echo "fuzz: undeclared feature tag(s): $undeclared" >&2
        cov_bad=1
    fi
fi

if [ "$expired" -gt 0 ]; then
    echo "fuzz: $expired expired allowlist entry(ies) - an undecided difference is an open finding"
    exit 1
fi
if [ -n "$found" ]; then
    if [ "$RECORD" -eq 1 ]; then
        for p in $found; do
            [ -f "$p" ] && cp -f "$p" "${p%.zrl}.rs" "$FINDINGS/" 2>/dev/null; [ -d "${p%.zrl}.d" ] && cp -R "${p%.zrl}.d" "$FINDINGS/"
        done
        echo "fuzz: findings recorded in $FINDINGS - name each pair in $FINDINGS/README.md"
        echo "fuzz: --reverify classifies every recorded pair and fails on one still open"
    else
        echo "fuzz: findings left in $OUT (this run was not told where to record them)"
        echo "fuzz: re-run with --record-findings to file a minimised pair in $FINDINGS"
    fi
    [ "$KEEP" -eq 1 ] || echo "fuzz: scratch in $OUT"
    exit 1
fi
if [ "$cov_bad" -ne 0 ]; then
    [ "$KEEP" -eq 1 ] || echo "fuzz: scratch in $OUT"
    exit 1
fi
# A release-bar run is cited for the compiler it ran on, so it refuses while a calibration hole is open.
# By design a known-hole fault is reported under its row and never touches the exit status - that is what
# lets a run pass on known holes and fail on anything new - but every one of the 23 rows has been fixed
# so `still open` is a regression now, not the expected state. Two deliberate
# placements: after the totals line, because scripts/fuzz_jobs.sh reads a worker with no totals as one
# that did not run and losing a whole run's numbers is worse than the finding; and after the `found`
# block, so a real finding has already been copied out before the run is refused for the reopened row.
if [ "$RELEASE" -eq 1 ] && [ "$knownfault" -gt 0 ]; then
    echo "fuzz: --release refuses this run: $knownfault known-hole program(s) are 'still open' (they fault with the hole switched on and are accepted with it off), which is a reopened hole rather than a known one" >&2
    awk -F'\t' '$2 ~ /^still open/ { print "fuzz:   row: " $1 }' "$KNOWN_LOG" | sort -u >&2
    echo "fuzz: run make fuzz-calibrate - it names each row against the fixed-state table in bench/fuzz/README.md - then follow the working rule 'When a hole is found, name the route class' before recording a run" >&2
    [ "$KEEP" -eq 1 ] || echo "fuzz: scratch in $OUT"
    exit 1
fi
[ "$KEEP" -eq 1 ] || rm -rf "$OUT"
exit 0
