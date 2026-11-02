#!/bin/sh
# scripts/check_toolchain.sh — Guard gate for canonical toolchain variables.
#
# Asserts that:
#   1. config.mk defines canonical variables: BACKEND_BIN, ASSEMBLER_BIN, LINKER_BIN,
#      and avoids full-path lookup for QBE_BIN.
#   2. All scripts in scripts/ (excluding allow-listed benchmark tools)
#      use the canonical variables rather than non-canonical defaults or bare
#      qbe/as/ld command invocations.
#
# Usage:
#   scripts/check_toolchain.sh             Run checks
#   scripts/check_toolchain.sh --selftest  Run checker selftest
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = "--selftest" ]; then
    tmp="${TMPDIR:-/tmp}/check_toolchain_selftest.$$"
    rm -rf "$tmp"
    mkdir -p "$tmp/scripts"
    printf 'BACKEND_BIN ?= qbe\nASSEMBLER_BIN ?= as\nLINKER_BIN ?= ld\n' > "$tmp/config.mk"
    printf '#!/bin/sh\n"$BACKEND_BIN" -o out.s in.ssa\n' > "$tmp/scripts/good.sh"

    # Test 1: indented qbe
    printf '#!/bin/sh\n    qbe -o out.s in.ssa\n' > "$tmp/scripts/bad.sh"
    if "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: indented qbe was not detected"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 2: indented as
    printf '#!/bin/sh\n    as -o out.o out.s\n' > "$tmp/scripts/bad.sh"
    if "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: indented as was not detected"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 3: indented ld
    printf '#!/bin/sh\n    ld -o out.bin out.o\n' > "$tmp/scripts/bad.sh"
    if "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: indented ld was not detected"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 4: reading ${QBE_BIN outside allow-list
    printf '#!/bin/sh\nval="${QBE_BIN:-qbe}"\n' > "$tmp/scripts/bad.sh"
    if "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: \${QBE_BIN read was not detected"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 5: unlisted external tool invocation in script
    printf '#!/bin/sh\ncat data.json | jq .name\n' > "$tmp/scripts/bad.sh"
    if "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: unlisted external tool jq was not detected"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "unlisted external tool 'jq'" "$tmp/out"; then
        echo "[FAIL] selftest: jq was not named in error report"
        cat "$tmp/out"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 6: tool followed by echo on same line must still be reported
    printf '#!/bin/sh\njq .a f; echo done\n' > "$tmp/scripts/bad.sh"
    if "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: 'jq .a f; echo done' was not detected"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "unlisted external tool 'jq'" "$tmp/out"; then
        echo "[FAIL] selftest: jq was not named in error report for 'jq .a f; echo done'"
        cat "$tmp/out"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 7: v="$(jq .a f)" must be reported
    printf '#!/bin/sh\nv="$(jq .a f)"\n' > "$tmp/scripts/bad.sh"
    if "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: 'v=\"\$(jq .a f)\"' was not detected"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "unlisted external tool 'jq'" "$tmp/out"; then
        echo "[FAIL] selftest: jq was not named in error report for 'v=\"\$(jq .a f)\"'"
        cat "$tmp/out"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 8: sh -c "jq .a f" must be reported
    printf '#!/bin/sh\nsh -c "jq .a f"\n' > "$tmp/scripts/bad.sh"
    if "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: 'sh -c \"jq .a f\"' was not detected"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "unlisted external tool 'jq'" "$tmp/out"; then
        echo "[FAIL] selftest: jq was not named in error report for 'sh -c \"jq .a f\"'"
        cat "$tmp/out"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 9: if [ $# -gt 0 ]; then jq .a f; fi must be reported
    printf '#!/bin/sh\nif [ $# -gt 0 ]; then jq .a f; fi\n' > "$tmp/scripts/bad.sh"
    if "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: 'if [ \$# -gt 0 ]; then jq .a f; fi' was not detected"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "unlisted external tool 'jq'" "$tmp/out"; then
        echo "[FAIL] selftest: jq was not named in error report for 'if [ \$# -gt 0 ]; then jq .a f; fi'"
        cat "$tmp/out"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 10: echo "install jq", # jq, printf 'use jq\n', and x=1 # jq later must NOT be reported
    printf '#!/bin/sh\necho "install jq"\n# jq\nprintf '\''use jq\\n'\''\nx=1 # jq later\n' > "$tmp/scripts/bad.sh"
    if ! "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: quoted or commented jq was falsely detected"
        cat "$tmp/out"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 11: bare gcc invocation
    printf '#!/bin/sh\ngcc -O2 -o out.o in.c\n' > "$tmp/scripts/bad.sh"
    if "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: bare gcc was not detected"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "bare cc/gcc/clang command invocation" "$tmp/out"; then
        echo "[FAIL] selftest: bare gcc was not named in error report"
        cat "$tmp/out"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 12: bare tool in script outside scripts/

    # Test 13: unset BACKEND_BIN without re-providing
    printf '#!/bin/sh\nunset BACKEND_BIN\n' > "$tmp/scripts/bad.sh"
    if "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: unset BACKEND_BIN was not detected"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "unsets or strips toolchain variables" "$tmp/out"; then
        echo "[FAIL] selftest: unset BACKEND_BIN was not named in error report"
        cat "$tmp/out"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 14: env -i without BACKEND_BIN
    printf '#!/bin/sh\nenv -i PATH=/bin make\n' > "$tmp/scripts/bad.sh"
    if "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: env -i without BACKEND_BIN was not detected"
        rm -rf "$tmp"
        exit 1
    fi

    # Test 15: unset with _cfg_tool re-providing must be allowed
    printf '#!/bin/sh\n_cfg_tool qbe "$BACKEND_BIN"\nunset BACKEND_BIN\n' > "$tmp/scripts/bad.sh"
    if ! "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: unset with _cfg_tool was falsely rejected"
        cat "$tmp/out"
        rm -rf "$tmp"
        exit 1
    fi

    rm -f "$tmp/scripts/bad.sh"
    if ! "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: good script failed check"
        cat "$tmp/out"
        rm -rf "$tmp"
        exit 1
    fi
    rm -rf "$tmp"
    echo "[PASS] toolchain: selftest passed"
    exit 0
fi

TARGET_ROOT="${1:-$REPO_ROOT}"
fail=0

# 1. Check config.mk
if [ ! -f "$TARGET_ROOT/config.mk" ]; then
    echo "[FAIL] toolchain: config.mk not found in $TARGET_ROOT"
    fail=1
else
    cfg_ok=1
    for var in BACKEND_BIN ASSEMBLER_BIN LINKER_BIN; do
        if ! grep -q "^[[:space:]]*${var}[[:space:]]*?=" "$TARGET_ROOT/config.mk"; then
            echo "[FAIL] toolchain: config.mk missing canonical variable $var"
            cfg_ok=0
            fail=1
        fi
    done
    if grep -q "command -v qbe" "$TARGET_ROOT/config.mk"; then
        echo "[FAIL] toolchain: config.mk has full-path command -v qbe lookup"
        cfg_ok=0
        fail=1
    fi
    if [ "$cfg_ok" -eq 1 ]; then
        echo "[PASS] toolchain: config.mk defines canonical toolchain variables"
    fi
fi

# 2. Check scripts for bare tool invocations, non-canonical defaults, and toolchain stripping
script_fail=0
if [ -f "$TARGET_ROOT/scripts/lib/layout.sh" ]; then
    . "$TARGET_ROOT/scripts/lib/layout.sh"
elif [ -f "$REPO_ROOT/scripts/lib/layout.sh" ]; then
    . "$REPO_ROOT/scripts/lib/layout.sh"
fi
STAGE0_DIR="${STAGE0_DIR:-stage0-C}"
private_scripts=""
bad_default_re='(QBE_BIN="\$\{QBE:-qbe\}"|\$\{QBE_BIN)'
for s in "$TARGET_ROOT"/scripts/*.sh "$TARGET_ROOT"/scripts/lib/*.sh \
         "$TARGET_ROOT/$STAGE0_DIR"/scripts/test_fixed_bugs.sh $private_scripts; do
    [ -f "$s" ] || continue
    base="$(basename "$s")"
    case "$base" in
        check_tools.sh|bench_link_floor.sh|benchmark.sh|check_toolchain.sh|env.sh)
            continue
            ;;
    esac

    # Check non-canonical defaults and QBE_BIN reads: e.g. QBE_BIN="${QBE:-qbe}" or ${QBE_BIN...}
    bad_defs=$(grep -n -E "$bad_default_re" "$s" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
    if [ -n "$bad_defs" ]; then
        echo "[FAIL] toolchain: $s has non-canonical tool default or \${QBE_BIN read:"
        printf '%s\n' "$bad_defs" | sed 's/^/       /'
        script_fail=1
        fail=1
    fi

    # Check bare qbe invocations
    # Look for qbe invoked as a command with arguments: e.g. "qbe -o", "qbe $", "| qbe", "&& qbe"
    bare_qbe=$(grep -n -E '(^|[;&|`\(])[[:space:]]*qbe([[:space:]]+-[a-zA-Z0-9]|\$|[[:space:]]+"[^"]*")' "$s" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
    if [ -n "$bare_qbe" ]; then
        echo "[FAIL] toolchain: $s has bare qbe command invocation:"
        printf '%s\n' "$bare_qbe" | sed 's/^/       /'
        script_fail=1
        fail=1
    fi

    # Check bare as invocations (e.g. "as -o", "as $")
    bare_as=$(grep -n -E '(^|[;&|`\(])[[:space:]]*as([[:space:]]+-[a-zA-Z0-9])' "$s" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
    if [ -n "$bare_as" ]; then
        echo "[FAIL] toolchain: $s has bare as command invocation:"
        printf '%s\n' "$bare_as" | sed 's/^/       /'
        script_fail=1
        fail=1
    fi

    # Check bare ld invocations (e.g. "ld -o", "ld -r", "ld -m")
    bare_ld=$(grep -n -E '(^|[;&|`\(])[[:space:]]*ld([[:space:]]+-[a-zA-Z0-9])' "$s" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
    if [ -n "$bare_ld" ]; then
        echo "[FAIL] toolchain: $s has bare ld command invocation:"
        printf '%s\n' "$bare_ld" | sed 's/^/       /'
        script_fail=1
        fail=1
    fi

    # Check bare cc/gcc/clang invocations
    case "$base" in
        bench_cross_lang.sh|perf_gap.sh) ;;
        *)
            bare_cc=$(grep -n -E '(^|[;&|`\(])[[:space:]]*(cc|gcc|clang)([[:space:]]+-[a-zA-Z0-9]|\$|[[:space:]]+"[^"]*")' "$s" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
            if [ -n "$bare_cc" ]; then
                echo "[FAIL] toolchain: $s has bare cc/gcc/clang command invocation:"
                printf '%s\n' "$bare_cc" | sed 's/^/       /'
                script_fail=1
                fail=1
            fi
            ;;
    esac

    # Check for unset or env -i stripping toolchain variables without re-providing them
    bad_unsets=$(awk '
        /^[[:space:]]*#/ { next }
        /env[[:space:]]+-i/ && !/BACKEND_BIN/ {
            print NR ":" $0 " (env -i strips toolchain variables without re-providing them)"
        }
        /^[[:space:]]*unset[[:space:]]+.*(BACKEND_BIN|ASSEMBLER_BIN|LINKER_BIN|CC\b)/ {
            print NR ":" $0
        }
    ' "$s" 2>/dev/null || true)
    if [ -n "$bad_unsets" ]; then
        if ! grep -q '_cfg_tool' "$s" 2>/dev/null; then
            echo "[FAIL] toolchain: $s unsets or strips toolchain variables without re-providing them:"
            printf '%s\n' "$bad_unsets" | sed 's/^/       /'
            script_fail=1
            fail=1
        fi
    fi
done

if [ "$script_fail" -eq 0 ]; then
    echo "[PASS] toolchain: scripts use canonical toolchain variables and avoid bare tool invocations"
fi

# 3. Check external tools in shipped scripts against check_deps.sh table
ext_fail=0
CHECK_DEPS="$TARGET_ROOT/scripts/check_deps.sh"
[ -f "$CHECK_DEPS" ] || CHECK_DEPS="$REPO_ROOT/scripts/check_deps.sh"

KNOWN_TOOLS=$("$CHECK_DEPS" --list-tools 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
CANDIDATE_TOOLS="lua rustc cargo clang zig hare valgrind dprint flock setsid git tar podman perf hyperfine python3 jq curl wget"

UNLISTED_TOOLS=""
for ct in $CANDIDATE_TOOLS; do
    case " $KNOWN_TOOLS " in
        *" $ct "*) ;;
        *) UNLISTED_TOOLS="$UNLISTED_TOOLS $ct" ;;
    esac
done

SHIPPED_SCRIPTS=""
if [ -f "$TARGET_ROOT/scripts/export_public_release.sh" ]; then
    SHIPPED_SCRIPTS=$(sed -n '/for s in /,/; do/p' "$TARGET_ROOT/scripts/export_public_release.sh" 2>/dev/null \
        | tr -d '\\;' | sed 's/for s in //' | tr ' ' '\n' | grep '\.sh$' | sort -u)
fi

get_scanned_scripts() {
    if [ -n "$SHIPPED_SCRIPTS" ]; then
        for _s in $SHIPPED_SCRIPTS; do
            [ -f "$TARGET_ROOT/scripts/$_s" ] && echo "$TARGET_ROOT/scripts/$_s"
        done
        for _lib in "$TARGET_ROOT"/scripts/lib/*.sh; do
            [ -f "$_lib" ] && echo "$_lib"
        done
    else
        for _f in "$TARGET_ROOT"/scripts/*.sh "$TARGET_ROOT"/scripts/lib/*.sh; do
            [ -f "$_f" ] && echo "$_f"
        done
    fi
}

for s in $(get_scanned_scripts); do
    [ -f "$s" ] || continue
    base="$(basename "$s")"
    case "$base" in
        check_toolchain.sh) continue ;;
    esac

    for tool in $UNLISTED_TOOLS; do
        # Allow-list for tools guarded with command -v and [SKIP] or benchmark targets
        case "$base:$tool" in
            check_runtimes.sh:hare) continue ;;
            bench_cross_lang.sh:cargo|bench_cross_lang.sh:zig|bench_cross_lang.sh:hare|bench_cross_lang.sh:clang) continue ;;
        esac

        # Command-position regex: after start of line, pipe, semicolon, &&, ||, `, $(
        matches=$(awk -v tool="$tool" '
            BEGIN {} function strip_comment(s) {
                if (match(s, /^[[:space:]]*#/)) return ""
                if (match(s, /[[:space:]]+#/)) return substr(s, 1, RSTART - 1)
                return s
            } function check_cmd(s, tool, regex,    line) {
                line = strip_comment(s)
                if (line == "") return 0
                gsub(/"[^"]*"/, "", line)
                gsub(/\047[^\047]*\047/, "", line)
                return (line ~ regex) ? 1 : 0
            } function extract_subshells(line, cmds, n,    rem, p, depth, len, i, ch, body, in_sq, in_dq, b1, b2) {
                rem = line
                while ((p = match(rem, /\$\(/)) > 0) {
                    rem = substr(rem, p + 2)
                    depth = 1
                    len = length(rem)
                    body = ""
                    in_sq = 0
                    in_dq = 0
                    for (i = 1; i <= len; i++) {
                        ch = substr(rem, i, 1)
                        if (ch == "\\" && in_dq) { i++; continue }
                        if (ch == "\047" && !in_dq) { in_sq = !in_sq; continue }
                        if (ch == "\"" && !in_sq) { in_dq = !in_dq; continue }
                        if (!in_sq && !in_dq) {
                            if (ch == "(") depth++
                            else if (ch == ")") {
                                depth--
                                if (depth == 0) {
                                    body = substr(rem, 1, i - 1)
                                    rem = substr(rem, i + 1)
                                    break
                                }
                            }
                        }
                    }
                    if (depth == 0) {
                        n++
                        cmds[n] = body
                    } else {
                        break
                    }
                }
                rem = line
                while ((b1 = index(rem, "`")) > 0) {
                    rem = substr(rem, b1 + 1)
                    b2 = index(rem, "`")
                    if (b2 > 0) {
                        body = substr(rem, 1, b2 - 1)
                        rem = substr(rem, b2 + 1)
                        n++
                        cmds[n] = body
                    } else {
                        break
                    }
                }
                return n
            } function extract_sh_c(line, cmds, n,    rem, p, q, endq, body, len, i, ch) {
                rem = line
                while (match(rem, /(^|[|;&(`]|&&|\|\||[[:space:]])(sh|bash|"\$SHELL"|\$SHELL)[[:space:]]+(-[a-zA-Z0-9]+[[:space:]]+)*-c[[:space:]]+/)) {
                    rem = substr(rem, RSTART + RLENGTH)
                    q = substr(rem, 1, 1)
                    if (q == "\"" || q == "\047") {
                        rem = substr(rem, 2)
                        len = length(rem)
                        endq = 0
                        for (i = 1; i <= len; i++) {
                            ch = substr(rem, i, 1)
                            if (ch == "\\") { i++; continue }
                            if (ch == q) { endq = i; break }
                        }
                        if (endq > 0) {
                            body = substr(rem, 1, endq - 1)
                            rem = substr(rem, endq + 1)
                            n++
                            cmds[n] = body
                        } else {
                            break
                        }
                    } else {
                        break
                    }
                }
                return n
            } function line_matches_tool(line, tool, regex,    queue, qlen, k) {
                queue[1] = line
                qlen = 1
                for (k = 1; k <= qlen && k <= 20; k++) {
                    qlen = extract_subshells(queue[k], queue, qlen)
                    qlen = extract_sh_c(queue[k], queue, qlen)
                }
                for (k = 1; k <= qlen; k++) {
                    if (check_cmd(queue[k], tool, regex)) {
                        return 1
                    }
                }
                return 0
            }
            {
                regex = "(^[[:space:]]*|([|;&(`]|&&|\\|\\|)[[:space:]]*|(^|[[:space:]]+)(if|then|else|elif|do|time)[[:space:]]+)" tool "([[:space:]]+|$)"
                if (line_matches_tool($0, tool, regex)) {
                    print NR ":" $0
                }
            }
        ' "$s" 2>/dev/null || true)
        if [ -n "$matches" ]; then
            echo "[FAIL] toolchain: $s invokes unlisted external tool '$tool' (not in check_deps.sh):"
            printf '%s\n' "$matches" | sed 's/^/       /'
            ext_fail=1
            fail=1
        fi
    done
done

if [ "$ext_fail" -eq 0 ]; then
    echo "[PASS] toolchain: external tools in shipped scripts are covered by check_deps.sh or allow-listed"
fi

exit "$fail"
