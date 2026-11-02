#!/bin/sh
# scripts/check_no_new_deps.sh — Guard gate: no dev tool brings a runtime this repository does not have.
#
# The rule is about dependencies, and Python is its named case. A dev tool that needs more than a
# short POSIX sh/awk script is written in Zoril as `tools/<name>/`, so the language builds its own
# tooling and the dependency set stays what `scripts/check_deps.sh` names: a C compiler, qbe, as, ld,
# a POSIX shell, Lua for the fuzz generator, rustc for the differential oracle, and the document
# tools. Anything else is a new dependency, and a new dependency is a decision (a task, a line in
# check_deps.sh), never a file that appears because it was convenient. A script in another language
# drifts from the compiler it is supposed to document, so this gate makes it a build failure instead
# of a review finding.
#
# What it reads: every tracked file (every file on disk when git is absent, build/ and hidden
# directories skipped). A file is a finding when it is a script of an interpreted language this tree
# does not depend on - a `.py`, `.rb`, `.pl` or `.php` file - or when its first line names one of
# those interpreters (python, python2, python3, perl, ruby, node, nodejs, deno, bun, php). `.js` and
# `.ts` files are not findings by extension: a web asset is not a tool, and a JavaScript *tool* names
# node in its shebang.
#
# Usage:
#   check_no_new_deps.sh            check every file git tracks (every file on disk when git is absent)
#   check_no_new_deps.sh DIR        check every file under DIR (used by the selftest)
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEP=""

# new_runtime FILE — status 0 when FILE is written in an interpreted language this tree does not
# depend on, with the runtime's name in $DEP.
new_runtime() {
    case "$1" in
        *.py)  DEP="Python"; return 0 ;;
        *.rb)  DEP="Ruby";   return 0 ;;
        *.pl)  DEP="Perl";   return 0 ;;
        *.php) DEP="PHP";    return 0 ;;
    esac
    [ -f "$1" ] || return 1
    # tr drops the NUL bytes a binary file puts in the first line, which the shell would warn about.
    _line=$(head -n 1 "$1" 2>/dev/null | LC_ALL=C tr -d '\000')
    case "$_line" in
        '#!'*) ;;
        *) return 1 ;;
    esac
    # `#!/usr/bin/env python3` names the interpreter in its second word.
    _interp=$(printf '%s\n' "${_line#\#!}" | awk '{ if ($1 ~ /(^|\/)env$/) print $2; else print $1 }')
    _interp=${_interp##*/}
    case "$_interp" in
        python|python2|python3|python[0-9].*|perl|ruby|node|nodejs|deno|bun|php)
            DEP="$_interp"; return 0 ;;
    esac
    return 1
}

report() {
    echo "[FAIL] no-new-deps: $1 needs '$DEP', a runtime this repository does not depend on; write dev tools in Zoril (tools/<name>/) or in POSIX sh/awk"
}

if [ $# -ge 1 ]; then
    DIR="$1"
    if [ ! -d "$DIR" ]; then
        echo "[FAIL] no-new-deps: no such directory: $DIR"
        exit 1
    fi
    files="$(find "$DIR" -type f | sort)"
    count="$(printf '%s\n' "$files" | grep -c . || true)"
    bad=0
    for f in $files; do
        if new_runtime "$f"; then
            report "${f#"$REPO_ROOT"/}"
            bad=$((bad + 1))
        fi
    done
    [ "$bad" -eq 0 ] || exit 1
    echo "[PASS] no-new-deps: no new runtime among $count files under $DIR"
    exit 0
fi

# git is an optional tool (the dependency matrix's `git missing` row), and the export is also checked
# before its fresh history exists, so a tree without git or without a checkout still gets checked:
# every file on disk except build output and hidden state directories, which are not this
# repository's files.
if files="$(git -C "$REPO_ROOT" ls-files 2>/dev/null)"; then
    source="tracked files"
else
    files="$(cd "$REPO_ROOT" && find . \( -name build -o -name '.?*' \) -type d -prune -o -type f -print \
        | sed 's|^\./||' | LC_ALL=C sort)"
    source="files in the working tree (no git checkout; build/ and hidden directories skipped)"
fi
count=0
bad=0
for f in $files; do
    count=$((count + 1))
    if new_runtime "$REPO_ROOT/$f"; then
        report "$f"
        bad=$((bad + 1))
    fi
done
if [ "$bad" -ne 0 ]; then
    exit 1
fi
echo "[PASS] no-new-deps: no new runtime among $count $source (sh, bash and Lua are already dependencies)"
exit 0
