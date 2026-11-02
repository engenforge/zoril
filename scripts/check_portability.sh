#!/bin/sh
# scripts/check_portability.sh — Guard gate for shipped script portability.
#
# Scans shipped scripts, Makefile, and config.mk for GNU/Linux-only constructs:
#   1. sed -i (BSD sed requires an argument; must use temp file + mv)
#   2. stat -c (GNU-specific; must use wc -c < or file_perm)
#   3. date +%s%N / %3N / %N (GNU-specific; must use now_ms from scripts/lib/portability.sh)
#   4. nproc (GNU-specific; must use nproc_count from scripts/lib/portability.sh)
#   5. bare sha256sum (must use sha256_of / sha256_check from scripts/lib/portability.sh)
#   6. bare md5sum
#   7. bashisms in scripts declaring #!/bin/sh
#   8. /proc references outside allow-listed platform-bound scripts
#   9. grep --exclude-dir (GNU-only: BusyBox and OpenBSD grep lack it; walk with find, then grep each file)
#  10. scripts with a bash shebang run with sh, and bash missing from check_deps.sh
#  11. awk regexes and functions that BusyBox, mawk and POSIX awks reject (gawk-only features)
#  12. kill -SIG -- pid (dash's kill rejects "--")
#  13. diff output read by its "<" / ">" markers (BusyBox diff writes only unified format)
#
# Usage:
#   scripts/check_portability.sh             Run checks
#   scripts/check_portability.sh --selftest  Run checker selftest
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = "--selftest" ]; then
    tmp="${TMPDIR:-/tmp}/check_portability_selftest.$$"
    rm -rf "$tmp"
    mkdir -p "$tmp/scripts"
    printf '#!/bin/sh\nnow_ms\n' > "$tmp/scripts/good.sh"

    test_bad_construct() {
        _name="$1"
        _content="$2"
        printf '%s\n' "$_content" > "$tmp/scripts/bad.sh"
        if "$0" "$tmp" > "$tmp/out" 2>&1; then
            echo "[FAIL] selftest: $_name in bad.sh was not detected" >&2
            cat "$tmp/out" >&2
            rm -rf "$tmp"
            exit 1
        fi
        rm -f "$tmp/scripts/bad.sh"
    }

    test_good_construct() {
        _name="$1"
        _content="$2"
        printf '%s\n' "$_content" > "$tmp/scripts/good.sh"
        if ! "$0" "$tmp" > "$tmp/out" 2>&1; then
            echo "[FAIL] selftest: $_name in good.sh was rejected" >&2
            cat "$tmp/out" >&2
            rm -rf "$tmp"
            exit 1
        fi
        printf '#!/bin/sh\nnow_ms\n' > "$tmp/scripts/good.sh"
    }

    test_bad_construct "sed -i" '#!/bin/sh
sed -i "s/a/b/" file'
    test_bad_construct "stat -c" '#!/bin/sh
sz=$(stat -c %s file)'
    test_bad_construct "date %N" '#!/bin/sh
t=$(date +%s%N)'
    test_bad_construct "bare nproc" '#!/bin/sh
n=$(nproc)'
    test_bad_construct "bare sha256sum" '#!/bin/sh
h=$(sha256sum file)'
    test_bad_construct "bare md5sum" '#!/bin/sh
h=$(md5sum file)'
    test_bad_construct "bashism [[ ]]" '#!/bin/sh
if [[ "$a" = "$b" ]]; then true; fi'
    test_bad_construct "bashism <<<" '#!/bin/sh
cat <<< "string"'
    test_bad_construct "bashism \${v//}" '#!/bin/sh
x="${v//a/b}"'
    test_bad_construct "bashism function name" '#!/bin/sh
function foo() { true; }'
    test_bad_construct "bashism function name, no parens" '#!/bin/sh
function foo { true; }'
    test_bad_construct "bashism function name, bare" '#!/bin/sh
function foo'
    test_bad_construct "bashism declare" '#!/bin/sh
declare -i num=5'
    test_bad_construct "bashism == in [ ]" '#!/bin/sh
[ "$a" == "$b" ]'
    test_bad_construct "/proc access" '#!/bin/sh
cat /proc/cpuinfo'
    test_bad_construct "grep --exclude-dir" '#!/bin/sh
grep -rl needle dir --exclude-dir=.git'

    # An awk function definition (`function name(param, ...)`) is POSIX awk, not a
    # bashism; the bash form has no comma-separated parameter list.
    test_good_construct "awk function definition" '#!/bin/sh
awk "function strip(t, i) { return t }" file'
    test_good_construct "POSIX function definition" '#!/bin/sh
strip() { true; }'

    test_bad_construct "awk: / inside a bracket expression" '#!/bin/sh
awk "{ if ($0 ~ /tests\/[A-Za-z0-9_/]+/) print }" f'
    test_bad_construct "awk: \\] inside a bracket expression" '#!/bin/sh
awk "{ sub(/[.,;:)\\]]+$/, \"\"); print }" f'
    test_bad_construct "awk: 3-argument match" '#!/bin/sh
awk "{ if (match(\$0, /a(b)/, m)) print m[1] }" f'
    test_bad_construct "awk: gensub" '#!/bin/sh
awk "{ print gensub(/a/, \"b\", \"g\") }" f'
    test_bad_construct "diff output read by < / > markers" '#!/bin/sh
diff a b | grep "^[<>]"'
    test_good_construct "diff -u output read by - / + markers" '#!/bin/sh
diff -u a b | sed -n "s/^-/< /p"'
    test_bad_construct "kill -SIG -- pid" '#!/bin/sh
kill -TERM -- -$pid'
    test_good_construct "kill -15 -pid" '#!/bin/sh
kill -15 -$pid'
    test_bad_construct "awk: \\s in a regex" '#!/bin/sh
awk "in_obj && /^\\s*\\}/ { n++ }" f'
    test_bad_construct "awk: \\< word boundary" '#!/bin/sh
awk "{ if (\$0 ~ /\\<as\\>/) n++ }" f'
    test_bad_construct "awk: \\> word boundary in a gsub string" '#!/bin/sh
awk "{ gsub(\"x\\\\>\", \"\") }" f'
    test_good_construct "awk: POSIX regexes" '#!/bin/sh
awk "{ if (match(\$0, /[][a]+/)) print; if (\$0 ~ /\\[(PASS|FAIL)\\]/) print; sub(/[^\\/]+\$/, \"\") }" f'
    printf '#!/usr/bin/env bash\narr=(1 2)\n' > "$tmp/scripts/needs_bash.sh"
    test_bad_construct "a bash-shebang script run with sh" '#!/bin/sh
sh scripts/needs_bash.sh'
    rm -f "$tmp/scripts/needs_bash.sh"

    if ! "$0" "$tmp" > "$tmp/out" 2>&1; then
        echo "[FAIL] selftest: good script failed portability check" >&2
        cat "$tmp/out" >&2
        rm -rf "$tmp"
        exit 1
    fi
    rm -rf "$tmp"
    echo "[PASS] portability: selftest passed"
    exit 0
fi

TARGET_ROOT="${1:-$REPO_ROOT}"
fail=0

# Determine candidate scripts to check
# If export_public_release.sh exists, parse shipped scripts; otherwise check all scripts/*.sh
SHIPPED_SCRIPTS=""
if [ -f "$TARGET_ROOT/scripts/export_public_release.sh" ]; then
    SHIPPED_SCRIPTS=$(sed -n '/for s in /,/; do/p' "$TARGET_ROOT/scripts/export_public_release.sh" 2>/dev/null \
        | tr -d '\\;' | sed 's/for s in //' | tr ' ' '\n' | grep '\.sh$' | sort -u)
    _sc_count=$(printf '%s\n' "$SHIPPED_SCRIPTS" | grep -c '\.sh$' || true)
    if [ "$_sc_count" -lt 45 ]; then
        echo "[FAIL] portability: scraped only $_sc_count shipped scripts from export script (expected >= 45)"
        fail=1
    fi
fi

get_target_files() {
    if [ -n "$SHIPPED_SCRIPTS" ]; then
        for _s in $SHIPPED_SCRIPTS; do
            case "$_s" in
                check_portability.sh|portability.sh) continue ;;
            esac
            [ -f "$TARGET_ROOT/scripts/$_s" ] && echo "$TARGET_ROOT/scripts/$_s"
        done
        for _lib in "$TARGET_ROOT"/scripts/lib/*.sh; do
            case "$(basename "$_lib")" in
                check_portability.sh|portability.sh) continue ;;
            esac
            [ -f "$_lib" ] && echo "$_lib"
        done
    else
        for _f in "$TARGET_ROOT"/scripts/*.sh "$TARGET_ROOT"/scripts/lib/*.sh; do
            case "$(basename "$_f")" in
                check_portability.sh|portability.sh) continue ;;
            esac
            [ -f "$_f" ] && echo "$_f"
        done
    fi
    [ -f "$TARGET_ROOT/Makefile" ] && echo "$TARGET_ROOT/Makefile"
    [ -f "$TARGET_ROOT/config.mk" ] && echo "$TARGET_ROOT/config.mk"
}

FILES=$(get_target_files)

# 1. Check sed -i
sed_i_fail=0
for f in $FILES; do
    matches=$(grep -n -E '(^|[[:space:];`\(])sed[[:space:]]+-i' "$f" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
    if [ -n "$matches" ]; then
        echo "[FAIL] portability: $f contains non-portable 'sed -i':"
        printf '%s\n' "$matches" | sed 's/^/       /'
        sed_i_fail=1
        fail=1
    fi
done
if [ "$sed_i_fail" -eq 0 ]; then
    echo "[PASS] portability: no sed -i in shipped scripts"
fi

# 2. Check stat -c
stat_c_fail=0
for f in $FILES; do
    case "$(basename "$f")" in
        portability.sh) continue ;;
    esac
    matches=$(grep -n -E '(^|[[:space:];`\(])stat[[:space:]]+-c' "$f" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
    if [ -n "$matches" ]; then
        echo "[FAIL] portability: $f contains non-portable 'stat -c':"
        printf '%s\n' "$matches" | sed 's/^/       /'
        stat_c_fail=1
        fail=1
    fi
done
if [ "$stat_c_fail" -eq 0 ]; then
    echo "[PASS] portability: no stat -c in shipped scripts"
fi

# 3. Check date +%s%N / %3N
date_n_fail=0
for f in $FILES; do
    case "$(basename "$f")" in
        portability.sh) continue ;;
    esac
    matches=$(grep -n -E 'date[[:space:]]+.*\+.*%(s%N|3N|N)' "$f" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
    if [ -n "$matches" ]; then
        echo "[FAIL] portability: $f contains non-portable date %N formatting:"
        printf '%s\n' "$matches" | sed 's/^/       /'
        date_n_fail=1
        fail=1
    fi
done
if [ "$date_n_fail" -eq 0 ]; then
    echo "[PASS] portability: no date %N timing in shipped scripts"
fi

# 4. Check bare nproc
nproc_fail=0
for f in $FILES; do
    case "$(basename "$f")" in
        portability.sh) continue ;;
    esac
    matches=$(grep -n -E '(^|[[:space:];`\(])nproc([[:space:];`\)]|$)' "$f" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
    if [ -n "$matches" ]; then
        echo "[FAIL] portability: $f contains non-portable 'nproc':"
        printf '%s\n' "$matches" | sed 's/^/       /'
        nproc_fail=1
        fail=1
    fi
done
if [ "$nproc_fail" -eq 0 ]; then
    echo "[PASS] portability: no bare nproc in shipped scripts"
fi

# 5. Check bare sha256sum
sha_fail=0
for f in $FILES; do
    case "$(basename "$f")" in
        portability.sh) continue ;;
    esac
    # Filter out echo/print messages that mention sha256sum
    matches=$(grep -n -E '(^|[[:space:];`\|\(])sha256sum([[:space:];`\|\)]|$)' "$f" 2>/dev/null \
        | grep -v '^[[:space:]]*#' \
        | grep -v 'echo[[:space:]].*sha256sum' \
        | grep -v 'printf[[:space:]].*sha256sum' || true)
    if [ -n "$matches" ]; then
        echo "[FAIL] portability: $f contains bare 'sha256sum':"
        printf '%s\n' "$matches" | sed 's/^/       /'
        sha_fail=1
        fail=1
    fi
done
if [ "$sha_fail" -eq 0 ]; then
    echo "[PASS] portability: no bare sha256sum in shipped scripts"
fi

# 6. Check bare md5sum
md5_fail=0
for f in $FILES; do
    case "$(basename "$f")" in
        portability.sh) continue ;;
    esac
    matches=$(grep -n -E '(^|[[:space:];`\|\(])md5sum([[:space:];`\|\)]|$)' "$f" 2>/dev/null \
        | grep -v '^[[:space:]]*#' \
        | grep -v 'echo[[:space:]].*md5sum' \
        | grep -v 'printf[[:space:]].*md5sum' || true)
    if [ -n "$matches" ]; then
        echo "[FAIL] portability: $f contains bare 'md5sum':"
        printf '%s\n' "$matches" | sed 's/^/       /'
        md5_fail=1
        fail=1
    fi
done
if [ "$md5_fail" -eq 0 ]; then
    echo "[PASS] portability: no bare md5sum in shipped scripts"
fi

# 7. Check bashisms in #!/bin/sh scripts
bashism_fail=0
for f in $FILES; do
    [ -f "$f" ] || continue
    case "$f" in *.sh) ;; *) continue ;; esac
    _first_line=$(head -n 1 "$f" 2>/dev/null || true)
    case "$_first_line" in
        *bin/sh*|*bin/env[[:space:]]sh*) ;;
        *) continue ;;
    esac

    if command -v checkbashisms >/dev/null 2>&1; then
        _cb_out=$(checkbashisms -f -x "$f" 2>&1 || true)
        if [ -n "$_cb_out" ]; then
            echo "[FAIL] portability: $f contains bashism (checkbashisms):"
            printf '%s\n' "$_cb_out" | sed 's/^/       /'
            bashism_fail=1
            fail=1
        fi
    else
        matches=$(grep -n -E '(\[\[ |<<<|\$\{[a-zA-Z0-9_]+//|^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(\(\))?[[:space:]]*(\{|$|#)|^[[:space:]]*declare([[:space:]]|$)|\[[[:space:]]+.*[[:space:]]+==[[:space:]]+.*[[:space:]]+\])' "$f" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
        if [ -n "$matches" ]; then
            echo "[FAIL] portability: $f contains bashism under #!/bin/sh:"
            printf '%s\n' "$matches" | sed 's/^/       /'
            bashism_fail=1
            fail=1
        fi
    fi
done
if [ "$bashism_fail" -eq 0 ]; then
    echo "[PASS] portability: no bashisms in #!/bin/sh scripts"
fi

# 8. Check /proc usage
proc_fail=0
for f in $FILES; do
    base="$(basename "$f")"
    case "$base" in
        test_bench_contention.sh|bench_cross_lang.sh|check_runtimes.sh|mutation-check.sh)
            # Platform-bound allow-listed scripts
            continue
            ;;
    esac
    matches=$(grep -n -E '(^|[[:space:]"'\''`])/proc([/[:space:]"'\''`]|$)' "$f" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
    if [ -n "$matches" ]; then
        echo "[FAIL] portability: $f contains unexpected /proc access:"
        printf '%s\n' "$matches" | sed 's/^/       /'
        proc_fail=1
        fail=1
    fi
done
if [ "$proc_fail" -eq 0 ]; then
    echo "[PASS] portability: /proc references restricted to platform-bound scripts"
fi

# 8b. Check grep --exclude-dir
grep_dir_fail=0
for f in $FILES; do
    case "$(basename "$f")" in
        portability.sh|check_portability.sh) continue ;;
    esac
    matches=$(grep -n -E 'grep[^|]*--exclude-dir' "$f" 2>/dev/null | grep -v '^[[:space:]]*#' || true)
    if [ -n "$matches" ]; then
        echo "[FAIL] portability: $f uses 'grep --exclude-dir', which BusyBox and OpenBSD grep lack (find ... -prune, then grep each file):"
        printf '%s\n' "$matches" | sed 's/^/       /'
        grep_dir_fail=1
        fail=1
    fi
done
if [ "$grep_dir_fail" -eq 0 ]; then
    echo "[PASS] portability: no grep --exclude-dir in shipped scripts"
fi

# 10. Scripts that need bash: one with a bash shebang that another script runs as `sh <script>` fails
#     under BusyBox ash (Alpine's sh), and bash is not on a stock Alpine, so scripts/check_deps.sh must
#     say it is required (or the scripts become POSIX sh).
bash_scripts=""
for f in $FILES; do
    case "$f" in *.sh) ;; *) continue ;; esac
    case "$(head -n 1 "$f" 2>/dev/null || true)" in *bash*) bash_scripts="$bash_scripts $(basename "$f")" ;; esac
done
bash_fail=0
for b in $bash_scripts; do
    for f in $FILES; do
        matches=$(grep -n -E "(^|[^A-Za-z0-9_./-])sh[[:space:]]+(\./)?(scripts/)?$b" "$f" 2>/dev/null | grep -v '^[[:space:]]*[0-9]*:[[:space:]]*#' || true)
        if [ -n "$matches" ]; then
            echo "[FAIL] portability: $f runs $b, which has a bash shebang, with sh (BusyBox ash cannot run it):"
            printf '%s\n' "$matches" | sed 's/^/       /'
            bash_fail=1
            fail=1
        fi
    done
done
if [ -n "$bash_scripts" ] && [ -f "$TARGET_ROOT/scripts/check_deps.sh" ] && ! grep -q 'bash' "$TARGET_ROOT/scripts/check_deps.sh"; then
    echo "[FAIL] portability: these scripts need bash, but scripts/check_deps.sh does not check for it:$bash_scripts"
    bash_fail=1
    fail=1
fi
if [ "$bash_fail" -eq 0 ]; then
    echo "[PASS] portability: scripts with a bash shebang are run directly, and bash is a checked dependency"
fi

# 11. awk that BusyBox and other POSIX awks reject or read differently from gawk: a "/" inside a
#     bracket expression of a regex literal ends the literal there (write \/); "\]" inside a bracket
#     expression leaves the bracket open at that "]" (put "]" first: [][...]); gawk's 3-argument
#     match(), gensub, strftime, systime, asort, PROCINFO and IGNORECASE are not POSIX awk.
# The bootstrap seed's own scripts, wherever this tree's layout puts them (scripts/lib/layout.sh).
STAGE0_SCRIPTS=""
if [ -f "$TARGET_ROOT/scripts/lib/layout.sh" ]; then
    STAGE0_SCRIPTS=$(REPO_ROOT="$TARGET_ROOT"; . "$TARGET_ROOT/scripts/lib/layout.sh"; ls "$TARGET_ROOT/$STAGE0_DIR"/scripts/*.sh 2>/dev/null)
fi
awk_fail=0
for f in $FILES $STAGE0_SCRIPTS; do
    case "$f" in *.sh) ;; *) continue ;; esac
    slash=$(grep -n -E '(~ */|match\(|sub\(|split\().*\[[^]]*[^]\\]/[^]]*\]' "$f" 2>/dev/null | grep -v '^[0-9]*:[[:space:]]*#' || true)
    escaped=$(grep -n -E '(~ */|match\(|sub\(|split\().*(^|[^\\])\[[^]]*\\\]' "$f" 2>/dev/null | grep -v '^[0-9]*:[[:space:]]*#' || true)
    gawk_only=$(grep -n -E 'match\(.*/ *, *[A-Za-z_][A-Za-z0-9_]*\)|(^|[^A-Za-z_])(gensub|strftime|systime|asorti?|PROCINFO|IGNORECASE)([^A-Za-z_]|$)' "$f" 2>/dev/null | grep -v '^[0-9]*:[[:space:]]*#' || true)
    escapes=$(grep -n -E '(~ *|&& *|[|][|] *|^[[:space:]]*)/[^/]*\\[sSwWyB<>]|(gsub|sub|match|split)\(.*\\\\[<>]' "$f" 2>/dev/null | grep -v '^[0-9]*:[[:space:]]*#' || true)
    for kind in slash escaped gawk_only escapes; do
        eval "matches=\$$kind"
        [ -n "$matches" ] || continue
        case "$kind" in
            escapes) why="has a gawk regex escape (\\s \\w \\< \\> ...) that mawk reads as a plain character; use [[:space:]], [A-Za-z0-9_] and (^|[^A-Za-z0-9_])" ;;
            slash) why="has a '/' inside a bracket expression of an awk regex literal (BusyBox ends the literal there; write \\/)" ;;
            escaped) why="has '\\]' inside a bracket expression (POSIX ends the bracket there; put ']' first)" ;;
            *) why="uses an awk feature only gawk has" ;;
        esac
        echo "[FAIL] portability: $f $why:"
        printf '%s\n' "$matches" | sed 's/^/       /'
        awk_fail=1
        fail=1
    done
done
if [ "$awk_fail" -eq 0 ]; then
    echo "[PASS] portability: awk regexes and functions in shipped scripts are POSIX"
fi

# 12. `kill -SIG -- pid`: dash's kill builtin rejects "--" ("Illegal number: -"), and the signal never
#     arrives. Write `kill -15 -pid` (a signal number, then the pid).
kill_fail=0
for f in $FILES; do
    case "$f" in *.sh) ;; *) continue ;; esac
    matches=$(grep -n -E '(^|[^A-Za-z_/-])kill[[:space:]]+-[A-Za-z0-9"$]+[[:space:]]+--' "$f" 2>/dev/null | grep -v '^[0-9]*:[[:space:]]*#' || true)
    if [ -n "$matches" ]; then
        echo "[FAIL] portability: $f uses 'kill -SIG --', which dash's kill rejects (write kill -15 -pid):"
        printf '%s\n' "$matches" | sed 's/^/       /'
        kill_fail=1
        fail=1
    fi
done
if [ "$kill_fail" -eq 0 ]; then
    echo "[PASS] portability: no 'kill -SIG --' in shipped scripts"
fi

# 13. diff output read by its "<" / ">" markers: BusyBox diff writes only the unified format ("-" / "+"),
#     so a script that greps for the classic markers sees no difference at all. Use diff -u.
diffmark_fail=0
for f in $FILES; do
    case "$f" in *.sh) ;; *) continue ;; esac
    matches=$(grep -n -E '(^|[^A-Za-z_-])diff[[:space:]][^|]*\|[[:space:]]*grep[^|]*\^\[<>\]' "$f" 2>/dev/null | grep -v '^[0-9]*:[[:space:]]*#' || true)
    if [ -n "$matches" ]; then
        echo "[FAIL] portability: $f reads diff output by its '<' / '>' markers, which BusyBox diff does not write (use diff -u):"
        printf '%s\n' "$matches" | sed 's/^/       /'
        diffmark_fail=1
        fail=1
    fi
done
if [ "$diffmark_fail" -eq 0 ]; then
    echo "[PASS] portability: no script reads classic diff markers"
fi

# 9. Test portability and layout library helpers
if [ -x "$REPO_ROOT/scripts/test_portability_lib.sh" ]; then
    "$REPO_ROOT/scripts/test_portability_lib.sh" || fail=1
fi

exit "$fail"
