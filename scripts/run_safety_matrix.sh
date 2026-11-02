#!/bin/sh
# scripts/run_safety_matrix.sh — Run safety conformance probes and regenerate comparison table.
#
# Probes Zoril against each bug class in the memory safety matrix,
# measures actual behavior (compile error, runtime trap, runtime fault, or accept),
# verifies expected behavior, and prints/regenerates the safety comparison table in
# doc/language/language_comparison.md.
#
# Probe headers:
#   // name: <bug class>
#   // expected: compile_reject | runtime_trap | runtime_fault | accept | known_gap
#   // gap: <why it is still open>          (known_gap only)
#   // observed: runtime_fault | exit <n>   (known_gap only, optional: how the open hole shows
#                                          itself. `runtime_fault` is a probe whose only
#                                          observation is the fault - a use-after-free touching
#                                          unmapped memory. `exit <n>` is the status a probe that
#                                          *returns the value it read* ends with, which is what
#                                          lets the checked run see the difference: a probe that
#                                          throws the value away cannot be observed at all.)
#
# `--checked` is the calibration run, not the gate: every probe is built and run twice, unmarked and
# with `zoril --checked`, and the table records both. A hole counts as DETECTED when the checked
# build turned it into a fault (exit 139), a trap (exit 134) or the poison value (exit 165) *and* the
# unmarked build did not already break the same way - a probe that segfaults on its own has not been
# detected by anything. A probe the checked build leaves alone is MISSED, and is either a hole the
# poison cannot see (the fuzzer's value canaries are the answer, bench/fuzz) or a gap in the checked
# build itself. The table goes in bench/safety_matrix/README.md.
# `--zbuild` runs the same gate through an installed `zbuild` (the README's recommended path): the
# toolchain is staged with `make install` into build/zbuild-matrix/stage, every probe is built there, and the
# outcome must be the one its header records. A `compile_reject` probe must also be refused with the
# same first error as the whole-program build (the message; the line too when both name one). A probe
# whose zbuild outcome differs for a documented reason says so in its header,
#   // zbuild: <accept|compile_reject|runtime_trap|runtime_fault> (<reason>)
# and is checked against that instead. A separate build checks less than a whole-program one
# (KNOWN_ISSUES.md section 4), and a regression of the summary pass appeared under zbuild first (A3.1).
# `accept` is behaviour that is correct by design. `known_gap` is a hole: the compiler
# accepts code it should not, and doc/spec/safety_model.md lists the probe under "Known
# gaps". A known gap is reported as [SKIP] while the compiler still accepts it, and as
# [FAIL] once it does not, so closing a gap means flipping its probe's expectation and
# removing its entry.

set -e
# Probes that crash on purpose must not write core dumps (see scripts/test.sh).
ulimit -c 0 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/scripts/env.sh"

PROBES_DIR="${PROBES_DIR:-$REPO_ROOT/bench/safety_matrix/probes}"
DOC_PATH="$REPO_ROOT/doc/language/language_comparison.md"
UPDATE_DOC=0
CHECKED=0
ZBUILD_MODE=0

for arg in "$@"; do
    case "$arg" in
        --update-doc) UPDATE_DOC=1 ;;
        --checked) CHECKED=1 ;;
        --zbuild) ZBUILD_MODE=1 ;;
        -h|--help)
            echo "usage: run_safety_matrix.sh [--update-doc | --checked | --zbuild]"
            exit 0
            ;;
        *)
            echo "run_safety_matrix.sh: unknown option '$arg'" >&2
            exit 2
            ;;
    esac
done

TMP_DIR="/tmp/safety_matrix_$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

ZORIL="${ZORIL:-$REPO_ROOT/build/zoril}"
ZILC="${ZILC:-$REPO_ROOT/build/zilc}"
RUNTIME_O="${RUNTIME_O:-$REPO_ROOT/build/runtime.o}"

if [ ! -f "$ZORIL" ] || [ ! -f "$ZILC" ]; then
    echo "Error: build/zoril and build/zilc must be built first. Run 'make' first." >&2
    exit 1
fi

TOTAL=0
PASSED=0
FAILS=0

if [ "$ZBUILD_MODE" -eq 1 ]; then
    if [ "$CHECKED" -eq 1 ] || [ "$UPDATE_DOC" -eq 1 ]; then
        echo "run_safety_matrix.sh: --zbuild goes with neither --checked nor --update-doc" >&2
        exit 2
    fi
    ZB_STAGE="$REPO_ROOT/build/zbuild-matrix/stage"
    rm -rf "$REPO_ROOT/build/zbuild-matrix"
    mkdir -p "$REPO_ROOT/build/zbuild-matrix"
    if ! (cd "$REPO_ROOT" && make install-files DESTDIR="$ZB_STAGE" PREFIX=/usr > build/zbuild-matrix/install.log 2>&1); then
        echo "Error: make install into the stage failed; see build/zbuild-matrix/install.log" >&2
        exit 1
    fi
    ZBUILD_BIN_STAGED="$ZB_STAGE/usr/bin/zbuild"
    ZORIL_STAGED="$ZB_STAGE/usr/bin/zoril"
fi

RESULT_FILE="$TMP_DIR/results.tsv"
CHECKED_FILE="$TMP_DIR/checked.tsv"
CHECKED_DETECTED=0
CHECKED_GAPS=0
CHECKED_MISSED_GAPS=0
CHECKED_FALSE_POSITIVES=0
printf '' > "$RESULT_FILE"
printf '' > "$CHECKED_FILE"

if [ "$ZBUILD_MODE" -eq 1 ]; then
    printf "Running safety matrix probes through the installed zbuild...\n"
else
    printf "Running safety matrix probes against build/zoril...\n"
fi

# probe_outcome PROBE STEM CHECKED
#
# Compiles one probe (with or without `--checked`) and runs it, printing the single outcome word the
# rest of the script compares against: "compile error", "zilc error", "qbe error", "as error",
# "ld error", "accept (exit 0)", "trap (134)", "fault (segv 139)", "poison (165)",
# "fault (signal N)" or "exit (N)". The two modes write to different files, so the calibration run keeps both binaries.
probe_outcome() {
    _probe=$1
    _stem=$2
    _mode=$3
    if [ "$_mode" -eq 1 ]; then _tag=".checked"; _flag="--checked"; else _tag=""; _flag=""; fi
    _zil="$TMP_DIR/${_stem}${_tag}.zil"
    _ssa="$TMP_DIR/${_stem}${_tag}.ssa"
    _s="$TMP_DIR/${_stem}${_tag}.s"
    _o="$TMP_DIR/${_stem}${_tag}.o"
    _bin="$TMP_DIR/${_stem}${_tag}.bin"
    if [ "$ZBUILD_MODE" -eq 1 ]; then
        # zbuild writes the program itself; a refused probe is a failed build.
        if ! "$ZBUILD_BIN_STAGED" --cache-dir "$TMP_DIR/${_stem}.cache" -o "$_bin" "$_probe" >"$TMP_DIR/${_stem}.zb.log" 2>&1; then
            echo "compile error"
            return 0
        fi
    else
    # shellcheck disable=SC2086
    if ! "$ZORIL" -I "stdlib=$REPO_ROOT/stdlib" $_flag --emit-zil -o "$_zil" "$_probe" >/dev/null 2>&1; then
        echo "compile error"
        return 0
    fi
    if ! "$ZILC" "$_zil" "$_ssa" >/dev/null 2>&1; then echo "zilc error"; return 0; fi
    if ! "$BACKEND_BIN" -o "$_s" "$_ssa" >/dev/null 2>&1; then echo "qbe error"; return 0; fi
    if ! "$ASSEMBLER_BIN" -o "$_o" "$_s" >/dev/null 2>&1; then echo "as error"; return 0; fi
    if ! "$LINKER_BIN" -o "$_bin" "$_o" "$RUNTIME_O" >/dev/null 2>&1; then echo "ld error"; return 0; fi
    fi
    _rc=0
    # Braces with stderr redirected: the shell otherwise reports each expected crash
    # ("Floating point exception", "Segmentation fault") on its own.
    { ( run_with_timeout $TIMEOUT_FOREGROUND -k 1s 5s "$_bin" >/dev/null 2>&1 ) ; } 2>/dev/null || _rc=$?
    # 165 is the checked build's poison byte (0xA5) as an exit status, and it is *above* 128, so it
    # has to be named before the signal rule: a program that compares the value it read exits 165
    # when that value was 0xA5A5A5A5A5A5A5A5, and the calibration run reads that as the poison.
    if [ "$_rc" -eq 0 ]; then
        echo "accept (exit 0)"
    elif [ "$_rc" -eq 134 ]; then
        echo "trap (134)"
    elif [ "$_rc" -eq 139 ]; then
        echo "fault (segv 139)"
    elif [ "$_rc" -eq 165 ]; then
        echo "poison (165)"
    elif [ "$_rc" -gt 128 ]; then
        echo "fault (signal $((_rc - 128)))"
    else
        echo "exit ($_rc)"
    fi
}

# Whether an outcome is the hole showing itself: a fault, a trap, or the checked build's poison
# byte (0xA5, exit 165).
is_flagged() {
    case "$1" in
        "trap (134)"|"fault (segv 139)"|"poison (165)") return 0 ;;
    esac
    return 1
}

# Whether an outcome is the program breaking on its own, without the checked build's help: the same
# three, minus the poison value, which only the checked build produces.
is_broken() {
    case "$1" in
        "trap (134)"|fault*) return 0 ;;
    esac
    return 1
}

for probe in "$PROBES_DIR"/*.zrl; do
    [ -f "$probe" ] || continue
    TOTAL=$((TOTAL + 1))
    stem="$(basename "$probe" .zrl)"

    # Extract name and expectation
    name="$(grep '^// name:' "$probe" | sed 's|^// name:[[:space:]]*||')"
    expected="$(grep '^// expected:' "$probe" | sed 's|^// expected:[[:space:]]*||')"
    gap="$(grep '^// gap:' "$probe" | sed 's|^// gap:[[:space:]]*||')"
    observed_hint="$(grep '^// observed:' "$probe" | sed 's|^// observed:[[:space:]]*||')"

    zbuild_hdr="$(grep '^// zbuild:' "$probe" | head -n 1 | sed 's|^// zbuild:[[:space:]]*||; s| (.*||')"
    if [ "$ZBUILD_MODE" -eq 1 ] && [ -n "$zbuild_hdr" ]; then expected="$zbuild_hdr"; fi
    observed="$(probe_outcome "$probe" "$stem" 0)"

    match=0
    case "$expected" in
        compile_reject)
            [ "$observed" = "compile error" ] && match=1
            ;;
        runtime_trap)
            [ "$observed" = "trap (134)" ] && match=1
            ;;
        runtime_fault)
            case "$observed" in
                fault*) match=1 ;;
            esac
            ;;
        accept)
            [ "$observed" = "accept (exit 0)" ] && match=1
            ;;
        known_gap)
            case "$observed_hint" in
                # A hole whose only observation is the fault itself (a use-after-free touching
                # unmapped memory) says so in its header.
                runtime_fault)
                    case "$observed" in
                        fault*) match=1 ;;
                    esac
                    ;;
                # A hole a program can see in a value: the probe returns what it read, so the
                # unmarked run ends with that value's exit status.
                exit\ *)
                    [ "$observed" = "exit (${observed_hint#exit })" ] && match=1
                    ;;
                *) [ "$observed" = "accept (exit 0)" ] && match=1 ;;
            esac
            ;;
    esac

    # Under zbuild a refused probe must be refused for the whole-program build's reason: the first error
    # without its location, and with its line when both name one.
    if [ "$ZBUILD_MODE" -eq 1 ] && [ "$expected" = compile_reject ] && [ "$match" -eq 1 ] && [ -z "$zbuild_hdr" ]; then
        whole_first="$("$ZORIL" -I "stdlib=$REPO_ROOT/stdlib" --emit-zil -o /dev/null "$probe" 2>&1 | grep -m1 'error' || true)"
        zb_first="$(grep -m1 'error' "$TMP_DIR/${stem}.zb.log" || true)"
        whole_kind="${whole_first#*error: }"; zb_kind="${zb_first#*error: }"
        whole_line="$(printf '%s' "$whole_first" | sed -n 's|^[^:]*:\([0-9]*\):[0-9]*: error.*|\1|p')"
        zb_line="$(printf '%s' "$zb_first" | sed -n 's|^[^:]*:\([0-9]*\):[0-9]*: error.*|\1|p')"
        if [ "$whole_kind" != "$zb_kind" ] || { [ -n "$zb_line" ] && [ -n "$whole_line" ] && [ "$zb_line" != "$whole_line" ]; }; then
            printf '[FAIL] %s (zbuild refuses it for another reason: whole-program "%s", zbuild "%s")\n' "$name" "$whole_first" "$zb_first"
            FAILS=$((FAILS + 1))
            printf '%s\t%s\n' "$name" "$observed" >> "$RESULT_FILE"
            continue
        fi
    fi

    if [ "$CHECKED" -eq 1 ]; then
        # The calibration run: what did the checked build make of this probe? The unmarked run above
        # is the baseline; only a difference between the two is evidence, because a probe that
        # crashes on its own proves nothing about the instrumentation.
        checked_obs="$(probe_outcome "$probe" "$stem" 1)"
        if [ "$expected" = known_gap ]; then
            verdict=MISSED
            if is_flagged "$checked_obs" && ! is_broken "$observed"; then
                verdict=DETECTED
            elif is_flagged "$checked_obs"; then
                # The unmarked build already faulted or trapped: the checked build agrees with
                # it, which is not a detection.
                verdict=NOT-A-DETECTION
            fi
            CHECKED_GAPS=$((CHECKED_GAPS + 1))
            [ "$verdict" = DETECTED ] && CHECKED_DETECTED=$((CHECKED_DETECTED + 1))
            [ "$verdict" = MISSED ] && CHECKED_MISSED_GAPS=$((CHECKED_MISSED_GAPS + 1))
            printf '[%s] %s (unmarked: %s; checked: %s)\n' "$verdict" "$name" "$observed" "$checked_obs"
            printf '%s\t%s\t%s\t%s\t%s\n' "$stem" "$observed_hint" "$observed" "$checked_obs" \
                "$verdict" >> "$CHECKED_FILE"
        elif [ "$expected" = accept ] && { is_flagged "$checked_obs" || [ "$checked_obs" != "$observed" ]; }; then
            printf '[FAIL] %s (checked build changed a correct program: %s, unmarked %s)\n' \
                "$name" "$checked_obs" "$observed"
            CHECKED_FALSE_POSITIVES=$((CHECKED_FALSE_POSITIVES + 1))
        fi
        continue
    fi

    if [ "$expected" = known_gap ]; then
        if [ -z "$gap" ]; then
            printf '[FAIL] %s (known_gap probe without a "// gap:" reason)\n' "$name"
            FAILS=$((FAILS + 1))
        elif [ "$match" -eq 1 ]; then
            printf '[SKIP] %s (known gap: %s)\n' "$name" "$gap"
        else
            printf '[FAIL] %s (known gap closed? %s now; flip the probe'"'"'s expectation and remove its Known gaps entry in safety_model.md)\n' "$name" "$observed"
            FAILS=$((FAILS + 1))
        fi
        printf '%s\t%s\n' "$name" "$observed" >> "$RESULT_FILE"
        continue
    fi

    if [ "$match" -eq 1 ]; then
        status="PASS"
        PASSED=$((PASSED + 1))
    else
        status="FAIL"
        FAILS=$((FAILS + 1))
    fi

    printf '[%s] %s (%s; expected %s)\n' "$status" "$name" "$observed" "$expected"
    printf '%s\t%s\n' "$name" "$observed" >> "$RESULT_FILE"
done

if [ "$CHECKED" -eq 1 ]; then
    printf '\nchecked build: %d known-gap probe(s), %d detected, %d missed, %d already broken unmarked; %d false positive(s)\n' \
        "$CHECKED_GAPS" "$CHECKED_DETECTED" "$CHECKED_MISSED_GAPS" \
        "$((CHECKED_GAPS - CHECKED_DETECTED - CHECKED_MISSED_GAPS))" "$CHECKED_FALSE_POSITIVES"
    printf '\n| Probe | Recorded | Unmarked | Checked | Verdict |\n'
    printf '| --- | --- | --- | --- | --- |\n'
    while IFS="$(printf '\t')" read -r stem hint obs checked_obs verdict; do
        [ -n "$stem" ] || continue
        [ -n "$hint" ] || hint="-"
        printf '| `%s` | %s | %s | %s | %s |\n' "$stem" "$hint" "$obs" "$checked_obs" "$verdict"
    done < "$CHECKED_FILE"
    # A missed known gap is information, not a failure: the checked build is a test instrument, and
    # a hole it cannot see is recorded in the README table. A false positive is a failure: it means
    # the instrumentation broke a program the compiler accepts.
    [ "$CHECKED_FALSE_POSITIVES" -eq 0 ] || exit 1
    exit 0
fi

printf '\nAll probes complete: %d/%d passed. Mismatches: %d\n' "$PASSED" "$TOTAL" "$FAILS"

if [ "$FAILS" -gt 0 ]; then
    echo "FAIL: $FAILS safety probe(s) did not match their documented expectation." >&2
    exit 1
fi
# The gate stops here; --update-doc goes on to regenerate the comparison table.
[ "$UPDATE_DOC" -eq 1 ] || exit 0

# Format the Markdown table using awk
TABLE_OUT="$TMP_DIR/table.md"
awk -F'\t' '
BEGIN {
    print "| Bug class | Zoril (unmarked code) | Rust (safe, debug) | Zig (Debug/ReleaseSafe) | Hare |"
    print "| --- | --- | --- | --- | --- |"

    rust["Use after move"] = "compile error"
    zig["Use after move"] = "n/a — no move checking"
    hare["Use after move"] = "n/a"

    rust["Use after move (POD)"] = "allowed only if `Copy`"
    zig["Use after move (POD)"] = "n/a"
    hare["Use after move (POD)"] = "n/a"

    rust["Double free / double drop"] = "compile error"
    zig["Double free / double drop"] = "runtime detect (GPA)"
    hare["Double free / double drop"] = "not prevented"

    rust["Use after drop"] = "compile error"
    zig["Use after drop"] = "runtime detect (GPA)"
    hare["Use after drop"] = "not prevented"

    rust["Dangling stack ptr — direct return"] = "compile error"
    zig["Dangling stack ptr — direct return"] = "not prevented"
    hare["Dangling stack ptr — direct return"] = "not prevented"

    rust["Dangling stack ptr — behind a cast"] = "compile error"
    zig["Dangling stack ptr — behind a cast"] = "not prevented"
    hare["Dangling stack ptr — behind a cast"] = "not prevented"

    rust["Dangling stack ptr — via callee"] = "compile error"
    zig["Dangling stack ptr — via callee"] = "not prevented"
    hare["Dangling stack ptr — via callee"] = "not prevented"

    rust["OOB array read"] = "panic"
    zig["OOB array read"] = "panic"
    hare["OOB array read"] = "trap"

    rust["OOB slice read"] = "panic"
    zig["OOB slice read"] = "panic"
    hare["OOB slice read"] = "trap"

    rust["OOB array write"] = "panic"
    zig["OOB array write"] = "panic"
    hare["OOB array write"] = "trap"

    rust["OOB slice write"] = "panic"
    zig["OOB slice write"] = "panic"
    hare["OOB slice write"] = "trap"

    rust["Raw-pointer indexing"] = "`unsafe` only"
    zig["Raw-pointer indexing"] = "unchecked"
    hare["Raw-pointer indexing"] = "unchecked"

    rust["Pointer forged from integer"] = "`unsafe` only"
    zig["Pointer forged from integer"] = "allowed"
    hare["Pointer forged from integer"] = "allowed"

    rust["Null dereference"] = "unrepresentable"
    zig["Null dereference"] = "unrepresentable (optionals)"
    hare["Null dereference"] = "nullable types, checked"

    rust["Signed integer overflow"] = "panics (debug)"
    zig["Signed integer overflow"] = "traps"
    hare["Signed integer overflow"] = "wraps"

    rust["Data races"] = "compile error"
    zig["Data races"] = "not prevented"
    hare["Data races"] = "not prevented"

    order[1] = "Use after move"
    order[2] = "Double free / double drop"
    order[3] = "Use after drop"
    order[4] = "Dangling stack ptr — direct return"
    order[5] = "Dangling stack ptr — behind a cast"
    order[6] = "Dangling stack ptr — via callee"
    order[7] = "OOB array read"
    order[8] = "OOB slice read"
    order[9] = "OOB array write"
    order[10] = "OOB slice write"
    order[11] = "Raw-pointer indexing"
    order[12] = "Pointer forged from integer"
    order[13] = "Null dereference"
    order[14] = "Signed integer overflow"
    order[15] = "Data races"
    order_len = 15
}
{
    obs[$1] = $2
}
END {
    obs["Data races"] = "n/a — no concurrency"

    for (i = 1; i <= order_len; i++) {
        k = order[i]
        o = obs[k]
        cell = o
        # A row whose operation stays available inside `unsafe { }` (a companion probe
        # accepts it there) is rejected only in unmarked code, which Rust calls "`unsafe` only".
        if (o ~ /compile error/ && k ~ /Raw-pointer|Pointer forged|Null dereference/) cell = "**`unsafe` only**"
        else if (o ~ /compile error/) cell = "**compile error**"
        else if (o ~ /trap \(134\)/) cell = "**trap (134)**"
        else if (o ~ /fault/) cell = "**not caught (segv)**"
        else if (o ~ /accept/) {
            if (k ~ /callee/) cell = "**not caught**"
            else if (k ~ /overflow/) cell = "wraps *(by design, v0.3.0)*"
            else if (k ~ /POD/) cell = "allowed — POD is Copy"
            else if (k ~ /Raw-pointer/) cell = "unchecked *(by design)*"
            else cell = "allowed"
        }
        print "| " k " | " cell " | " rust[k] " | " zig[k] " | " hare[k] " |"
    }
}
' "$RESULT_FILE" > "$TABLE_OUT"

printf "\nGenerated Table:\n\n"
cat "$TABLE_OUT"
printf "\n"

if [ "$UPDATE_DOC" -eq 1 ]; then
    printf "Updating %s...\n" "$DOC_PATH"
    DOC_TMP="$TMP_DIR/doc_update.tmp"
    awk -v tbl="$TABLE_OUT" '
    BEGIN { replaced = 0 }
    /^\|[ \t]*Bug class[ \t]*\|/ && !replaced {
        while ((getline line < tbl) > 0) {
            print line
        }
        close(tbl)
        in_table = 1
        replaced = 1
        next
    }
    in_table {
        if (/^\|/) {
            next
        } else {
            in_table = 0
        }
    }
    { print }
    END {
        if (!replaced) exit 1
    }
    ' "$DOC_PATH" > "$DOC_TMP" && mv "$DOC_TMP" "$DOC_PATH" && printf "Updated table in %s successfully.\n" "$DOC_PATH" || {
        rm -f "$DOC_TMP"
        printf "Warning: could not find table to replace in %s\n" "$DOC_PATH"
    }
fi
