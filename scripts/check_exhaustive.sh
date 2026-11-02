#!/bin/sh
# scripts/check_exhaustive.sh — a transfer function marked `// exhaustive:` must name every
# construct it handles, with no `_ =>` arm.
#
# The checkers answer one question per construct: what does this rvalue, statement or
# terminator do to ownership, borrows and epochs? A `_ =>` arm answers "nothing", so when a
# new construct is added the checker silently keeps compiling and the construct goes
# unchecked. Several past holes were exactly that shape (tuple and array literals were once
# absent from check_rvalue_use, and the `Boxed`/`ArrayRepeat`/`Cast` borrow cases were dropped
# by a wildcard until 2026-10-18). Marking the function makes adding a construct a build
# failure until every marked function says what the construct does.
#
# The marker is a comment line immediately above the declaration:
#
#     // exhaustive: every rvalue must say what its operand use does.
#     fn check_rvalue_use(...)
#
# A marked function fails the gate when its body contains a wildcard match arm (`_ =>`).
# The script also fails on a marker that is not immediately above a `fn`, and (in the default
# repository mode) when a file that should carry markers has none.
#
# Usage: check_exhaustive.sh [--selftest] [FILE...]
#   No FILE: check src/check_zir.zrl and src/verify.zrl, and require at least 7 marked
#   functions between them. FILE...: check just those files (used by the self-test).
#
# POSIX sh and awk only.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Extract the marked functions and report each wildcard arm. Output records:
#   FUN   <file> <name>      a marked function
#   BAD   <file> <line> <name> <text>
#   MARK  <file> <line>      a marker with no fn directly below it
#   END   <file> <count>     marked functions in the file
scan_file() {
    awk -v file="$1" '
        function strip(t,    i, c, out, q, prev) {
            out = ""
            q = 0
            prev = ""
            for (i = 1; i <= length(t); i++) {
                c = substr(t, i, 1)
                if (q) {
                    if (c == "\"") q = 0
                    out = out " "
                    continue
                }
                if (c == "\"") { q = 1; out = out " "; continue }
                if (c == "/" && prev == "/") {
                    # The whole rest is a comment.
                    return out
                }
                out = out c
                prev = c
            }
            return out
        }
        BEGIN { in_fun = 0; depth = 0; started = 0; above_marker = 0; count = 0 }
        {
            raw = $0
            line = strip(raw)

            if (!in_fun) {
                # A run of comment lines directly above a `fn` carries the marker. The marker
                # may be followed by more comment lines (a wrapped explanation), but a blank
                # line or any other statement ends the run.
                if (raw ~ /^[ \t]*\/\//) {
                    if (raw ~ /^[ \t]*\/\/ exhaustive:/) { above_marker = 1 }
                    next
                }
                if (line ~ /^[ \t]*(pub[ \t]+)?fn[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/) {
                    if (above_marker) {
                        name = line
                        sub(/^[ \t]*(pub[ \t]+)?fn[ \t]+/, "", name)
                        sub(/[^A-Za-z0-9_].*$/, "", name)
                        in_fun = 1
                        depth = 0
                        started = 0
                        count++
                        printf "FUN\t%s\t%s\n", file, name
                    }
                    above_marker = 0
                } else {
                    if (above_marker) { printf "MARK\t%s\t%d\n", file, NR }
                    above_marker = 0
                }
            }

            if (in_fun) {
                if (index(line, "_") > 0 && line ~ /(^|[|,])[ \t]*_[ \t]*=>/) {
                    printf "BAD\t%s\t%d\t%s\t%s\n", file, NR, name, raw
                }
                n = length(line)
                for (i = 1; i <= n; i++) {
                    c = substr(line, i, 1)
                    if (c == "{") { depth++; started = 1 }
                    else if (c == "}") { depth-- }
                }
                if (started && depth <= 0) {
                    in_fun = 0
                    started = 0
                }
            }
        }
        END { printf "END\t%s\t%d\n", file, count + 0 }
    ' "$1"
}

# Check the files; print one [PASS]/[FAIL] line per file and return non-zero on any failure.
check_files() {
    _fail=0
    _total=0
    for f in "$@"; do
        if [ ! -f "$f" ]; then
            echo "[FAIL] $f: no such file"
            _fail=1
            continue
        fi
        case "$f" in
            "$REPO_ROOT"/*) disp="${f#"$REPO_ROOT"/}" ;;
            *) disp="$f" ;;
        esac
        report="$(scan_file "$f")"
        bad="$(printf '%s\n' "$report" | grep '^BAD')"
        mark="$(printf '%s\n' "$report" | grep '^MARK')"
        n="$(printf '%s\n' "$report" | grep '^END' | awk -F'\t' '{print $3}')"
        n="${n:-0}"
        _total=$((_total + n))
        if [ -n "$bad" ]; then
            echo "[FAIL] $disp: marked transfer function has a wildcard arm:"
            printf '%s\n' "$bad" | awk -F'\t' '{ printf "       %s:%s: %s: %s\n", $2, $3, $4, $5 }'
            _fail=1
        elif [ -n "$mark" ]; then
            echo "[FAIL] $disp: // exhaustive: is not immediately above a fn:"
            printf '%s\n' "$mark" | awk -F'\t' '{ printf "       %s:%s\n", $2, $3 }'
            _fail=1
        elif [ "$n" -eq 0 ]; then
            echo "[SKIP] $disp: no // exhaustive: function marked"
        else
            echo "[PASS] $disp: $n marked function(s), no wildcard arm"
        fi
    done
    TOTAL="$(( ${TOTAL:-0} + _total ))"
    return $_fail
}

# A planted wildcard must fail, and an unmarked wildcard must not: the gate claims to catch
# exactly the marked functions, and a gate whose detector never fires is not a gate.
selftest() {
    _tmp="$(mktemp -d "${TMPDIR:-/tmp}/check_exhaustive.XXXXXX")" || {
        echo "[FAIL] selftest: cannot create a temporary directory"
        return 1
    }
    trap 'rm -rf "$_tmp"' EXIT INT TERM
    cat > "$_tmp/clean.zrl" <<'EOF'
fn helper(x: u32) -> u32 {
    match x {
        A => 1,
        B => 2,
    }
}

// exhaustive: every construct is named.
fn transfer(x: u32) -> u32 {
    match x {
        A => 1,
        B => 2,
    }
}
EOF
    cat > "$_tmp/wildcard.zrl" <<'EOF'
// exhaustive: every construct must be named.
fn transfer(x: u32) -> u32 {
    match x {
        A => 1,
        _ => 0,
    }
}
EOF
    cat > "$_tmp/unmarked.zrl" <<'EOF'
fn helper(x: u32) -> u32 {
    match x {
        A => 1,
        _ => 0,
    }
}
EOF
    cat > "$_tmp/detached.zrl" <<'EOF'
// exhaustive: this marker has drifted.

fn transfer(x: u32) -> u32 {
    match x { A => 1 }
}
EOF

    _sfail=0
    _out="$(check_files "$_tmp/clean.zrl")" || {
        echo "[FAIL] selftest: a marked function without a wildcard was rejected:"
        printf '%s\n' "$_out" | sed 's/^/       /'
        _sfail=1
    }
    _out="$(check_files "$_tmp/wildcard.zrl")" && {
        echo "[FAIL] selftest: a planted wildcard arm was accepted"
        _sfail=1
    }
    _out="$(check_files "$_tmp/unmarked.zrl")" || {
        echo "[FAIL] selftest: an unmarked function was checked"
        printf '%s\n' "$_out" | sed 's/^/       /'
        _sfail=1
    }
    _out="$(check_files "$_tmp/detached.zrl")" && {
        echo "[FAIL] selftest: a detached marker was accepted"
        _sfail=1
    }
    if [ "$_sfail" -ne 0 ]; then
        echo "[FAIL] selftest: the detector does not behave as documented"
        return 1
    fi
    echo "[PASS] selftest: planted wildcard rejected, unmarked wildcard ignored, detached marker rejected"
    return 0
}

if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi

if [ "$#" -gt 0 ]; then
    check_files "$@"
    exit $?
fi

TOTAL=0
check_files "$REPO_ROOT/src/check_zir.zrl" "$REPO_ROOT/src/verify.zrl"
rc=$?
# The repository mode also guards the gate itself: losing the markers must fail the build,
# not silently turn the gate into a no-op.
if [ "$TOTAL" -lt 7 ]; then
    echo "[FAIL] repository: only $TOTAL // exhaustive: function(s) marked (expected at least 7)"
    rc=1
elif [ "$rc" -eq 0 ]; then
    echo "PASS: $TOTAL transfer function(s) name every construct; add // exhaustive: to a new one."
fi
exit $rc
