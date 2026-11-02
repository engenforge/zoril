#!/bin/sh
# scripts/check_safety_comments.sh — every `unsafe { ... }` block in the stdlib states the
# invariant it relies on, in a `// SAFETY:` comment.
#
# The stdlib's `unsafe` interiors are the compiler's trusted base: each one assumes something the
# type system does not check - bounds arithmetic that cannot wrap, a pointer that is live for the
# access, a length that matches its allocation. Those assumptions used to be invisible, and the
# invariant audit (2026-10-11) found five places where safe code could break one. Requiring the
# comment makes each assumption reviewable at the line that depends on it, and turns a new
# `unsafe` block with no stated reason into a build failure rather than a habit.
#
# A block is satisfied when the line that opens it (`... unsafe {`) either carries the comment
# before the block on the same line, or is immediately preceded by a `// SAFETY:` line:
#
#     // SAFETY: <the invariant this block relies on>
#     let p = unsafe { @slice(base, len) };
#
# `unsafe fn` declarations are not checked here: their contract is the caller's, and the stdlib
# documents it in the prose above each one.
#
# Usage: check_safety_comments.sh [DIR]    (default: <repo>/stdlib)
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${1:-$REPO_ROOT/stdlib}"

if [ ! -d "$DIR" ]; then
    echo "[FAIL] no such directory: $DIR"
    exit 1
fi

fail=0
blocks=0
for f in "$DIR"/*.zrl; do
    [ -f "$f" ] || continue
    case "$f" in
        "$REPO_ROOT"/*) disp="${f#"$REPO_ROOT"/}" ;;
        *) disp="$f" ;;
    esac

    report="$(awk -v file="$disp" '
        /unsafe \{/ {
            seen = index($0, "// SAFETY:")
            open = index($0, "unsafe {")
            if (seen > 0 && seen < open) { n++; next }
            if (run) { n++; next }
            printf "%s:%d: %s\n", file, FNR, $0
            n++
            bad++
        }
        {
            # `run` is set while the comment block immediately above states the invariant; a
            # blank or non-comment line ends that run.
            if ($0 ~ /^[ \t]*\/\//) {
                if ($0 ~ /^[ \t]*\/\/ SAFETY:/) run = 1
            } else {
                run = 0
            }
        }
        END { printf "COUNT %d %d\n", n + 0, bad + 0 }
    ' "$f")"

    counts="$(printf '%s\n' "$report" | grep '^COUNT ' | tail -n 1)"
    bad="$(printf '%s\n' "$report" | grep -v '^COUNT ')"
    n="$(printf '%s' "$counts" | awk '{print $2}')"
    nb="$(printf '%s' "$counts" | awk '{print $3}')"
    blocks=$((blocks + n))

    if [ "${nb:-0}" -gt 0 ]; then
        echo "[FAIL] $disp: $nb of $n unsafe block(s) have no // SAFETY: comment:"
        printf '%s\n' "$bad" | sed 's/^/       /'
        fail=1
    else
        echo "[PASS] $disp: $n unsafe block(s), each with a // SAFETY: comment"
    fi
done

if [ "$fail" -ne 0 ]; then
    echo "FAIL: add a \`// SAFETY:\` line naming the invariant above each block listed."
    exit 1
fi
echo "PASS: all $blocks stdlib unsafe blocks state the invariant they rely on."
exit 0
