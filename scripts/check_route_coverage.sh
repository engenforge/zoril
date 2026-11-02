#!/bin/sh
# scripts/check_route_coverage.sh — every route a safety-matrix row lists is a route a rejection
# travelled through.
#
# A row's claim is universal ("safe code cannot do X"), but its "Proven by" probes are examples.
# A route (a ZIR construct, a CFG shape) that no rejection reaches is a hole the examples cannot
# see: the 2026-10-18 holes were exactly the routes nobody had thought to write a probe for, and
# every one of them appeared in a program the compiler *accepted*. "The construct is in a
# rejected program" is not enough either - a rejected census that contains every construct
# proves nothing about any of them.
#
# `zoril --emit-zir-stats` prints, on its `reject-via` line, the routes a reported rejection
# travelled through: the rvalue that created the borrow, every step that carried it, the
# statement or terminator that reported the error, and whether it crossed a join or a
# back-edge. This script counts those routes, and only from a cited probe that declares
# `// expected: compile_reject` and that the compiler actually rejects. Accepted probes,
# `runtime_trap` probes (there is no compile-time rejection to attribute), `known_gap` probes,
# runtime-fault probes and cited tests without a probe header are not evidence.
#
# A row may also list only a route a borrow can travel through into a reported error: the
# carrying vocabulary `src/route_set.zrl` defines and the compiler prints on its `carry` line.
# `term:Jmp` and the other terminators are excluded by definition - the checker reports a
# borrow conflict at a statement or rvalue, never at a jump - and so are the rvalues whose
# result cannot hold a reference. A cell naming one is refused before coverage is looked at,
# because no probe could ever support it.
#
# bench/safety_matrix/probes/232_reference_route_census.zrl is a lowering smoke test: it must
# stay accepted and lower at least one function, but its routes are not a row's evidence.
#
# The last line reports what was checked (rows that list routes, routes, rejected probes), so a
# pass with an empty matrix cannot read like a pass with a full one.
#
# Usage: check_route_coverage.sh [--list]
#   --list: print the route set each row's cited probes reach, then exit.
#
# POSIX sh and awk only.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="${ROUTE_COVERAGE_MODEL:-$REPO_ROOT/bench/safety_matrix/matrix.md}"
ZORIL="${ZORIL:-$REPO_ROOT/build/zoril}"
CENSUS="${ROUTE_COVERAGE_CENSUS:-$REPO_ROOT/bench/safety_matrix/probes/232_reference_route_census.zrl}"
WORK="${TR_WORK:-$REPO_ROOT/build}/route_coverage"
LIST=0
[ "${1:-}" = "--list" ] && LIST=1

if [ ! -f "$MODEL" ]; then
    echo "[FAIL] no such file: $MODEL"
    exit 1
fi
if [ ! -x "$ZORIL" ]; then
    echo "[FAIL] compiler not built: $ZORIL"
    exit 1
fi
# A probe is compiled at most once per run. The cache is cleared first: a changed probe or
# compiler must not be answered from the previous run's stats.
rm -rf "$WORK"
mkdir -p "$WORK"

# The carrying vocabulary: the routes a borrow can travel through into a reported error, and so
# the only routes a row's `Routes` cell may list. It comes from the compiler, which prints it on
# its `carry` line from `src/route_set.zrl`, so a route the checker stops carrying cannot stay
# in the gate's list, and the gate cannot drift from the checker. Any program answers it: this
# one is the smallest that lowers.
cat > "$WORK/carry_vocabulary.zrl" <<'ZRL'
fn main() -> i32 {
    return 0;
}
ZRL
"$ZORIL" --emit-zir-stats -I "stdlib=$REPO_ROOT/stdlib" "$WORK/carry_vocabulary.zrl" \
    > "$WORK/carry.stats" 2> "$WORK/carry.log" || true
CARRY_VOCAB=$(awk '$1 == "carry" { for (i = 2; i <= NF; i++) printf "%s ", $i }' "$WORK/carry.stats")
if [ -z "$CARRY_VOCAB" ]; then
    echo "[FAIL] ./${ZORIL#$REPO_ROOT/} --emit-zir-stats printed no 'carry' line, so the carrying"
    echo "       vocabulary is unknown and no Routes cell can be judged."
    exit 1
fi

# Resolve a citation relative to doc/spec (where the table lives).
resolve_probe() {
    _p="$1"
    case "$_p" in
        /*) printf '%s\n' "$_p" ;;
        *)
            ( cd "$(dirname "$MODEL")" 2>/dev/null || exit 1
              _d=$(dirname "$_p")
              _b=$(basename "$_p")
              cd "$_d" 2>/dev/null || exit 1
              printf '%s/%s\n' "$(pwd -P)" "$_b" )
            ;;
    esac
}

# The probe's declared expectation, from its `// expected:` header.
probe_expected() {
    sed -n 's|^// expected:[[:space:]]*||p' "$1" | head -n 1
}

# Compile one probe and cache its census. Writes five lines:
#   ROUTES <space-separated route tokens the program lowers to>
#   VIA <space-separated routes a reported rejection travelled through>
#   VERDICT <accept|reject|none>
#   EXPECTED <word>
#   FUNCTIONS <count>
# A lowering error may print only what lowered; the verdict is still on the last stdout line.
probe_census() {
    _probe="$1"
    _key=$(printf '%s' "$_probe" | tr '/ ' '__')
    _stats="$WORK/$_key.stats"
    _log="$WORK/$_key.log"
    _meta="$WORK/$_key.meta"
    if [ ! -f "$_meta" ]; then
        _expected=$(probe_expected "$_probe")
        # A rejection exits nonzero but still prints the census; the exit status is not the
        # verdict (a lowering error and a failed check both end in `verdict reject`).
        "$ZORIL" --emit-zir-stats -I "stdlib=$REPO_ROOT/stdlib" "$_probe" > "$_stats" 2> "$_log" || true
        _routes=$(awk '
            $1 == "rv" && $3 + 0 > 0 { printf "rv:%s ", $2 }
            $1 == "stmt" && $3 + 0 > 0 { printf "stmt:%s ", $2 }
            $1 == "term" && $3 + 0 > 0 { printf "term:%s ", $2 }
            $1 == "cfg" && $3 + 0 > 0 { printf "cfg:%s ", $2 }
        ' "$_stats")
        # The routes the checker's reported rejections actually travelled through. Only a
        # rejection that involved a route can make that route evidence for a row.
        _via=$(awk '$1 == "reject-via" { for (i = 2; i <= NF; i++) printf "%s ", $i }' "$_stats")
        _verdict=$(awk '$1 == "verdict" { v = $2 } END { print (v == "" ? "none" : v) }' "$_stats")
        _functions=$(awk '$1 == "functions" { v = $2 } END { print (v == "" ? 0 : v) }' "$_stats")
        printf 'ROUTES %s\nVIA %s\nVERDICT %s\nEXPECTED %s\nFUNCTIONS %s\n' \
            "$_routes" "$_via" "$_verdict" "${_expected:-none}" "$_functions" > "$_meta"
    fi
    cat "$_meta"
}

meta_field() {
    printf '%s\n' "$1" | awk -v key="$2" '$1 == key { $1 = ""; sub(/^ /, ""); print; exit }'
}

# The population rule is the whole point of this gate, so it has a planted pair: a row citing a
# probe that contains `box` but is rejected for an unrelated use after move must fail naming
# rv:Boxed, and the same row citing 206_arena_box_slice_reset.zrl (rejected while the boxed
# value's borrow is live) must pass. Both runs use a scratch model, so the real matrix is
# untouched. The 206 case is also the checker's own unit case: its reject-via must contain
# rv:Boxed.
if [ "${1:-}" = "--selftest" ]; then
    st_dir=$(mktemp -d "${TMPDIR:-/tmp}/zoril_route_selftest.XXXXXX") || exit 1
    cat > "$st_dir/box_unrelated.zrl" <<'ZRL'
// name: Planted box with an unrelated rejection
// expected: compile_reject
// The box is present, but the error is a use after move in a different local: no borrow
// travels through `Boxed`, so rv:Boxed must not become route evidence.
fn main() -> i32 {
    let bx = box 7;
    let moved = box 3;
    let taken = moved;
    let _ = *moved;
    let _ = bx;
    let _ = taken;
    return 0;
}
ZRL
    box_probe="$REPO_ROOT/bench/safety_matrix/probes/206_arena_box_slice_reset.zrl"
    st_fail=0

    # The checker's unit case: probe 206's rejection travelled through the box.
    case " $(meta_field "$(probe_census "$box_probe")" VIA) " in
        *" rv:Boxed "*) ;;
        *)
            echo "[FAIL] selftest: probe 206's reject-via does not contain rv:Boxed" >&2
            st_fail=1
            ;;
    esac

    run_planted() {
        _probe="$1"
        printf '# planted\n\n| **Planted row** | claim | mech | level | boundary | side | [probe](%s) | rv:Boxed | routes |\n' \
            "$_probe" > "$st_dir/model.md"
        ROUTE_COVERAGE_MODEL="$st_dir/model.md" ROUTE_COVERAGE_CENSUS="$st_dir/none.zrl" \
            TR_WORK="$st_dir/work" "$0" > "$st_dir/out" 2>&1
    }

    # The same, with the Routes cell chosen by the caller: the two rules this script enforces
    # are independent (a route must be able to carry a borrow, and a cited rejection must have
    # travelled through it), so each needs its own planted case.
    run_planted_cell() {
        _probe="$1"
        _cell="$2"
        printf '# planted\n\n| **Planted row** | claim | mech | level | boundary | side | [probe](%s) | %s | routes |\n' \
            "$_probe" "$_cell" > "$st_dir/model.md"
        ROUTE_COVERAGE_MODEL="$st_dir/model.md" ROUTE_COVERAGE_CENSUS="$st_dir/none.zrl" \
            TR_WORK="$st_dir/work" "$0" > "$st_dir/out" 2>&1
    }

    if run_planted "$st_dir/box_unrelated.zrl"; then
        echo "[FAIL] selftest: a row whose rejection never used rv:Boxed passed" >&2
        st_fail=1
    elif ! grep -q 'rv:Boxed' "$st_dir/out"; then
        echo "[FAIL] selftest: the planted failure did not name rv:Boxed" >&2
        cat "$st_dir/out" >&2
        st_fail=1
    fi
    if ! run_planted "$box_probe"; then
        echo "[FAIL] selftest: probe 206 did not cover rv:Boxed" >&2
        cat "$st_dir/out" >&2
        st_fail=1
    fi

    # A route outside the carrying vocabulary cannot be evidence, however many rejected probes
    # the row cites: `term:Jmp` is not a place where the checker reports a conflict. Probe 206
    # covers rv:Boxed, so this row is refused for the route alone.
    if run_planted_cell "$box_probe" 'term:Jmp'; then
        echo "[FAIL] selftest: a Routes cell naming the non-carrying route term:Jmp passed" >&2
        st_fail=1
    elif ! grep -q 'cannot travel through.*term:Jmp' "$st_dir/out"; then
        echo "[FAIL] selftest: a cell naming term:Jmp was not refused as a non-carrying route" >&2
        cat "$st_dir/out" >&2
        st_fail=1
    fi

    # rv:Cast does carry a borrow, so it is a legal cell; the row still fails when no cited
    # rejection travelled through a cast (this probe's error is a use after move).
    if run_planted_cell "$st_dir/box_unrelated.zrl" 'rv:Cast'; then
        echo "[FAIL] selftest: a row listing rv:Cast with no rejected probe through it passed" >&2
        st_fail=1
    elif ! grep -q 'no rejected probe:.*rv:Cast' "$st_dir/out"; then
        echo "[FAIL] selftest: the missing rv:Cast was not reported as uncovered" >&2
        cat "$st_dir/out" >&2
        st_fail=1
    fi
    # ... and passes from the probe whose slice cast carried the borrow.
    cast_probe="$REPO_ROOT/bench/safety_matrix/probes/233_slice_cast_carries_borrow.zrl"
    if [ -f "$cast_probe" ]; then
        if ! run_planted_cell "$cast_probe" 'rv:Cast'; then
            echo "[FAIL] selftest: probe 233 did not cover rv:Cast" >&2
            cat "$st_dir/out" >&2
            st_fail=1
        fi
    else
        echo "[FAIL] selftest: probe 233_slice_cast_carries_borrow.zrl is missing" >&2
        st_fail=1
    fi
    rm -rf "$st_dir"
    if [ "$st_fail" -eq 0 ]; then
        echo "[PASS] route-coverage selftest: reject-via population, planted rv:Boxed failure, probe 206 passes, term:Jmp refused as non-carrying, uncovered rv:Cast refused, probe 233 covers rv:Cast"
    fi
    exit "$st_fail"
fi

# Rows: one line per data row, TAB-separated: index, property, routes, citations.
rows="$(awk -F'|' '
    /^\| \*\*/ {
        n++
        property = $2
        gsub(/^[ \t]+|[ \t]+$/, "", property)
        routes = $9
        gsub(/^[ \t]+|[ \t]+$/, "", routes)
        if (routes == "" || routes == "-") next
        # Markdown links in the Proven by cell (column 8).
        cited = ""
        rest = $8
        while (match(rest, /\]\([^)]*\)/)) {
            link = substr(rest, RSTART + 2, RLENGTH - 3)
            sub(/#.*/, "", link)
            if (link ~ /\.zrl$/) cited = cited " " link
            rest = substr(rest, RSTART + RLENGTH)
        }
        printf "%d\t%s\t%s\t%s\n", n, property, routes, cited
    }
' "$MODEL")"

fail=0
checked=0
total_rows=$(awk '/^\| \*\*/ { n++ } END { print n + 0 }' "$MODEL")
report="$WORK/report"
totals="$WORK/totals"
: > "$report"
: > "$totals"

printf '%s\n' "$rows" | while IFS='	' read -r idx property routes cited; do
    [ -n "${property:-}" ] || continue
    checked=$((checked + 1))
    probes=""
    for link in $cited; do
        p=$(resolve_probe "$link")
        if [ -n "$p" ] && [ -f "$p" ]; then probes="$probes $p"; fi
    done
    reached=" "
    used=0
    skipped=0
    for p in $probes; do
        [ -f "$p" ] || continue
        meta=$(probe_census "$p")
        expected=$(meta_field "$meta" EXPECTED)
        verdict=$(meta_field "$meta" VERDICT)
        # The routes the rejection travelled through, not the routes the program contains.
        r=$(meta_field "$meta" VIA)
        case "$expected" in
            compile_reject) ;;
            *)
                # Accepted, runtime-trap, known-gap, runtime-fault, or a cited test with no
                # probe header: only a compile-time rejection can name the routes it went
                # through, so none of these is this row's route evidence.
                skipped=$((skipped + 1))
                continue
                ;;
        esac
        # The probe's header and the compiler's verdict must agree before its routes count.
        if [ "$verdict" != "reject" ]; then
            printf '[FAIL] %s: probe %s expects compile_reject, but the compiler said %s\n' \
                "$property" "$(basename "$p")" "$verdict" >> "$report"
            continue
        fi
        used=$((used + 1))
        for tok in $r; do
            case "$reached" in *" $tok "*) ;; *) reached="$reached$tok " ;; esac
        done
    done
    # Check the row's list: every token must be a route a borrow can travel through, and one
    # that a cited rejection did travel through. The two failures are reported apart, because
    # they call for different work - a different route, or a different probe.
    uncarryable=""
    missing=""
    count=0
    old_ifs=$IFS
    IFS=','
    for tok in $routes; do
        IFS=$old_ifs
        tok=$(printf '%s' "$tok" | sed 's/^[ \t]*//; s/[ \t]*$//')
        [ -n "$tok" ] || continue
        count=$((count + 1))
        case " $CARRY_VOCAB " in
            *" $tok "*) ;;
            *) uncarryable="$uncarryable $tok" ;;
        esac
        case "$reached" in
            *" $tok "*) ;;
            *) missing="$missing $tok" ;;
        esac
    done
    IFS=$old_ifs
    if [ -n "$uncarryable" ]; then
        printf '[FAIL] %s: route(s) a borrow cannot travel through:%s\n' \
            "$property" "$uncarryable" >> "$report"
        printf '       a Routes cell may list only:%s\n' "$CARRY_VOCAB" >> "$report"
    fi
    if [ -n "$missing" ]; then
        printf '[FAIL] %s: route(s) with no rejected probe:%s\n' "$property" "$missing" >> "$report"
        printf '       cited probes: %s\n' "${probes:-none}" >> "$report"
        printf '       rejected probes counted: %d, not evidence: %d\n' "$used" "$skipped" >> "$report"
    fi
    if [ -z "$uncarryable" ] && [ -z "$missing" ]; then
        printf '[PASS] %s: %d route(s), %d rejected probe(s)%s\n' "$property" "$count" "$used" \
            "$( [ "$skipped" -gt 0 ] && printf ' (%d not evidence)' "$skipped" )" >> "$report"
    fi
    printf '%d\t%d\n' "$count" "$used" >> "$totals"
done

# The census is a lowering smoke test, not a row's evidence: it must keep accepting and lower
# at least one body, so a construct the lowerer stops emitting is noticed here.
if [ -f "$CENSUS" ]; then
    meta=$(probe_census "$CENSUS")
    cv=$(meta_field "$meta" VERDICT)
    cf=$(meta_field "$meta" FUNCTIONS)
    if [ "$cv" = "accept" ] && [ "${cf:-0}" -gt 0 ]; then
        printf '[PASS] census: %s accepts and lowers %s function(s) (not evidence)\n' \
            "$(basename "$CENSUS")" "$cf" >> "$report"
    else
        printf '[FAIL] census: %s verdict=%s functions=%s\n' \
            "$(basename "$CENSUS")" "$cv" "$cf" >> "$report"
    fi
fi

cat "$report"

# How much was actually checked. A gate that passes with nothing to look at is the failure this
# count exists to make visible: "PASS: every listed route ..." with no route listed reads the
# same as a real pass.
listed_rows=$(awk 'END { print NR + 0 }' "$totals")
listed_routes=$(awk '{ n += $1 } END { print n + 0 }' "$totals")
listed_probes=$(awk '{ n += $2 } END { print n + 0 }' "$totals")
printf 'route coverage: %d of %d row(s) list %d route(s), walked by %d cited rejected probe(s); %d row(s) list none\n' \
    "$listed_rows" "$total_rows" "$listed_routes" "$listed_probes" \
    "$((total_rows - listed_rows))"

if [ "$LIST" -eq 1 ]; then
    exit 0
fi
if grep -q '^\[FAIL\]' "$report"; then
    echo "FAIL: add a rejected probe that walks the missing route, or remove the route from the row;"
    echo "      a route outside the carrying vocabulary is not one a rejection can reach at all."
    exit 1
fi
if [ "$listed_rows" -eq 0 ]; then
    echo "PASS: no row lists a route, so there is nothing to check (0 of $total_rows rows)."
    exit 0
fi
echo "PASS: every listed route can carry a borrow and is walked by a cited program the mechanism rejects."
exit 0
