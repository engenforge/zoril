#!/bin/sh
# scripts/check_deps.sh — Check dependencies up front before long operations run.
#
# Enforces the rule: a long command checks what its last stage needs before its
# first stage starts. Checks the names make actually uses (BACKEND_BIN, ASSEMBLER_BIN,
# LINKER_BIN, CC) rather than hard-coded assumptions.
#
# Profiles:
#   seed      - C compiler (needed only for initial stage0-C seed compiler)
#   build     - backend, assembler, linker, awk, sed (optional: timeout, git)
#   install   - build (the man pages are committed, so installing needs no scdoc)
#   test      - build + bash, flock, mkfifo, xargs (optional: lua, setsid, valgrind, dprint, rustc, scdoc)
#   preflight - test + git, timeout, scdoc
#   fuzz      - bash, lua, timeout (optional: rustc)
#   repro     - git, tar, sha256sum/shasum/sha256
#   man       - scdoc 1.11.5 or newer (required; an older one is skipped by `test`, an error here and in preflight)
#   dist      - build + git, bsdtar, sha256sum/shasum/sha256 (the release tarballs)
#
# Options:
#   --list-tools     Print list of all tracked external tools and their profile
#   --required-only  Print nothing on success (no "Skipping optional test items:" line); for callers whose
#                    output has a fixed format, such as scripts/test.sh
#
# Exit status:
#   0: all required tools present
#   1: one or more required tools missing (prints install hints)
#   2: usage / invalid profile

set -u

case "$0" in
    /*) _d="${0%/*}" ;;
    */*) _d="$PWD/${0%/*}" ;;
    *) _d="$PWD" ;;
esac
REPO_ROOT="$(cd "$_d/.." 2>/dev/null && pwd)"
if [ -f "$REPO_ROOT/scripts/lib/portability.sh" ]; then
    . "$REPO_ROOT/scripts/lib/portability.sh"
elif [ -f "$_d/lib/portability.sh" ]; then
    . "$_d/lib/portability.sh"
fi
if [ -f "$REPO_ROOT/scripts/lib/scdoc_version.sh" ]; then
    . "$REPO_ROOT/scripts/lib/scdoc_version.sh"
elif [ -f "$_d/lib/scdoc_version.sh" ]; then
    . "$_d/lib/scdoc_version.sh"
fi

REQUIRED_ONLY=0
if [ "${1:-}" = "--required-only" ]; then
    REQUIRED_ONLY=1
    shift
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 [--required-only] PROFILE... (seed, build, install, test, preflight, fuzz, repro, man, dist)" >&2
    exit 2
fi

# Tool name resolution from environment or defaults
CC_BIN="${CC:-cc}"
LINK_CC_BIN="${LINK_CC:-cc}"
BACKEND_BIN="${BACKEND_BIN:-qbe}"
ASSEMBLER_BIN="${ASSEMBLER_BIN:-as}"
LINKER_BIN="${LINKER_BIN:-ld}"
CPROC_BIN="${CPROC:-cproc}"
MINIMAL_CPP_BIN="${MINIMAL_CPP:-mcpp}"
BTYPE="${BTYPE:-local}"

MISSING_REQ=""
REQ_ERRORS=""
MISSING_OPT=""
OPT_SKIPS=""
CURRENT_PROFILE=""
LIST_TOOLS_MODE=0

# The fuzzer's generator needs Lua 5.3 or newer: it draws its random stream from 64-bit integer
# arithmetic and calls math.tointeger, and Lua 5.1 and LuaJIT, which have only doubles, produce other
# programs from the same seeds. math.tointeger exists exactly from 5.3.
lua_too_old() {
    ! "$1" -e 'if not math.tointeger then os.exit(1) end' >/dev/null 2>&1
}

check_required() {
    _id="$1"
    _cmd="$2"
    _purpose="$3"

    # Extract first word of command in case flags or options were passed
    _bin="${_cmd%% *}"
    _tool_name="$_id"
    case "$_id" in
        backend)   _tool_name="$_bin" ;;
        assembler) _tool_name="$_bin" ;;
        linker)    _tool_name="$_bin" ;;
        link_cc)   _tool_name="$_bin" ;;
    esac

    if [ "$LIST_TOOLS_MODE" -eq 1 ]; then
        echo "$_tool_name $CURRENT_PROFILE required"
        return 0
    fi

    case " $MISSING_REQ " in
        *" $_id "*) return 0 ;;
    esac

    if ! command -v "$_bin" >/dev/null 2>&1; then
        MISSING_REQ="$MISSING_REQ $_id"
        _var=""
        case "$_id" in
            backend)   _var="BACKEND_BIN" ;;
            assembler) _var="ASSEMBLER_BIN" ;;
            linker)    _var="LINKER_BIN" ;;
            cc)        _var="CC" ;;
            link_cc)   _var="LINK_CC" ;;
        esac

        _header=""
        _tilda=""
        if [ -n "$_var" ]; then
            _header="Missing required tool: $_cmd ($_var=$_cmd; needed by: $_purpose; either install it in your path using your OS package manager, or set $_var in config.local.mk with the correct path)"
            case "$_cmd" in
                '~'*)
                    _tilda="  $_var starts with '~', which make does not expand; use \$(HOME)/... instead
"
                    ;;
            esac
        else
            _header="Missing required tool: $_cmd (needed by: $_purpose; install it in your path using your OS package manager)"
        fi

        _hints=""
        case "$_bin" in
            */*)
                _hints="  not found or not executable: $_cmd
"
                ;;
        esac

        REQ_ERRORS="${REQ_ERRORS}${_header}
${_tilda}${_hints}"
    elif [ "$_id" = backend ]; then
        case " $MISSING_REQ " in
            *" backend_version "*) ;;
            *) check_backend_version "$_bin" ;;
        esac
    elif [ "$_id" = scdoc ] && _sv=$(scdoc_found) && scdoc_old "$_sv"; then
        MISSING_REQ="$MISSING_REQ scdoc"
        REQ_ERRORS="${REQ_ERRORS}Unsupported scdoc: $(command -v "$_bin") is version $_sv; $SCDOC_MIN or newer is required (needed by: $_purpose; the committed man pages are generated with $SCDOC_MIN, and older releases write other roff for the same source; install scdoc $SCDOC_MIN or newer and put it first on PATH)
"
    elif [ "$_id" = lua ] && lua_too_old "$_bin"; then
        MISSING_REQ="$MISSING_REQ lua"
        REQ_ERRORS="${REQ_ERRORS}Unsupported Lua: $(command -v "$_bin") is older than 5.3 (needed by: $_purpose; Lua 5.3 or newer is required: Lua 5.1 and LuaJIT produce other programs from the same seeds; install lua5.4 or lua5.3 with your OS package manager)
"
    fi
}

# QBE has no --version. Releases before 1.3 refuse an identifier of 80 bytes or more ("identifier too
# long"), and the symbols zilc writes carry a module's whole path, so ordinary projects reach that;
# 1.0 also lacks `blit` and `hlt`. A one-function probe with a 120-byte symbol stands in for the
# version: only QBE's own refusal fails it (a stand-in that prints nothing, as the test suite's fake
# tools do, passes).
check_backend_version() {
    _qbe="$1"
    _long="zoril_probe_$(printf '%0120d' 0)"
    _probe="$(printf 'export function $%s(l %%a, l %%b) {\n@s\n\tblit %%a, %%b, 8\n\thlt\n}\n' "$_long" | "$_qbe" -o /dev/null - 2>&1)" || true
    case "$_probe" in
        *"identifier too long"*|*"unknown keyword"*)
            _where="$(command -v "$_qbe" 2>/dev/null || echo "$_qbe")"
            REQ_ERRORS="${REQ_ERRORS}Unsupported QBE: $_where is older than 1.3. QBE 1.3 or newer is required: earlier releases refuse the long symbols Zoril writes (this one said: \"$_probe\"). Install a newer one from https://c9x.me/compile/ and put it first on PATH, or set BACKEND_BIN to it.
"
            MISSING_REQ="$MISSING_REQ backend_version"
            ;;
    esac
}

check_required_sha256() {
    if [ "$LIST_TOOLS_MODE" -eq 1 ]; then
        echo "sha256 $CURRENT_PROFILE required"
        return 0
    fi

    case " $MISSING_REQ " in
        *" sha256 "*) return 0 ;;
    esac

    if ! sha256_of /dev/null >/dev/null 2>&1; then
        MISSING_REQ="$MISSING_REQ sha256"
        REQ_ERRORS="${REQ_ERRORS}Missing required tool: sha256 tool (needed by: checksum verification; install it in your path using your OS package manager)
"
    fi
}

check_optional() {
    _tool="$1"
    _skip_desc="$2"
    _var="${3:-}"
    _cmd="${4:-$_tool}"

    _bin="${_cmd%% *}"
    _tool_name="$_tool"

    if [ "$LIST_TOOLS_MODE" -eq 1 ]; then
        echo "$_tool_name $CURRENT_PROFILE optional"
        return 0
    fi

    case " $MISSING_OPT " in
        *" $_tool "*) return 0 ;;
    esac

    if ! command -v "$_bin" >/dev/null 2>&1; then
        MISSING_OPT="$MISSING_OPT $_tool"
        _display_name="$_tool"
        if [ -n "$_var" ]; then
            _display_name="$_cmd ($_var=$_cmd)"
        fi
        if [ -n "$OPT_SKIPS" ]; then
            OPT_SKIPS="$OPT_SKIPS, $_skip_desc ($_display_name)"
        else
            OPT_SKIPS="$_skip_desc ($_display_name)"
        fi
    elif [ "$_tool" = scdoc ] && _sv=$(scdoc_found) && scdoc_old "$_sv"; then
        MISSING_OPT="$MISSING_OPT $_tool"
        if [ -n "$OPT_SKIPS" ]; then
            OPT_SKIPS="$OPT_SKIPS, $_skip_desc (scdoc $_sv is older than $SCDOC_MIN)"
        else
            OPT_SKIPS="$_skip_desc (scdoc $_sv is older than $SCDOC_MIN)"
        fi
    elif [ "$_tool" = lua ] && lua_too_old "$_bin"; then
        MISSING_OPT="$MISSING_OPT $_tool"
        if [ -n "$OPT_SKIPS" ]; then
            OPT_SKIPS="$OPT_SKIPS, $_skip_desc (lua 5.3 or newer; $(command -v "$_bin") is older)"
        else
            OPT_SKIPS="$_skip_desc (lua 5.3 or newer; $(command -v "$_bin") is older)"
        fi
    fi
}

add_profile_seed() {
    check_required "cc" "$CC_BIN" "C bootstrap compiler"
}

add_profile_build() {
    check_required "backend" "$BACKEND_BIN" "Zoril backend compiler"
    check_required "assembler" "$ASSEMBLER_BIN" "system assembler"
    check_required "linker" "$LINKER_BIN" "system linker"
    check_required "awk" "awk" "build scripts and code generation"
    check_required "sed" "sed" "build scripts and string manipulation"
    check_optional "timeout" "build timeouts"
    check_optional "git" "git versioning"
}

add_profile_install() {
    add_profile_build
}

add_profile_man() {
    check_required "scdoc" "scdoc" "man page generation"
}

add_profile_test() {
    add_profile_build
    check_required "bash" "bash" "the safety-model and Markdown link checks (check_safety_model.sh, check_md_links.sh)"
    check_required "flock" "flock" "test runner concurrency locking"
    check_optional "lua" "fuzzer and benchmark test generator"
    check_required "mkfifo" "mkfifo" "parallel test runner IPC"
    check_required "xargs" "xargs" "parallel test runner"
    check_optional "setsid" "process isolation"
    check_optional "valgrind" "perf-gate"
    check_optional "dprint" "md-check"
    check_optional "rustc" "readme snippets, fuzz-record"
    check_optional "scdoc" "committed man pages vs their sources"
    check_optional "cproc" "stage0c-minimal" "CPROC" "$CPROC_BIN"
    check_optional "mcpp" "stage0c-minimal" "MINIMAL_CPP" "$MINIMAL_CPP_BIN"
}

add_profile_preflight() {
    add_profile_test
    check_required "git" "git" "clean tree and selfhost checks"
    check_required "timeout" "timeout" "per-stage test and benchmark timeouts"
    check_required "scdoc" "scdoc" "checking the committed man pages against their sources"
}

add_profile_fuzz() {
    check_required "bash" "bash" "the fuzzer driver (fuzz_safe.sh)"
    check_required "lua" "lua" "fuzzer program generator (scripts/fuzz/gen.lua)"
    check_required "timeout" "timeout" "fuzzer timeout execution"
    check_optional "rustc" "differential oracle"
}

add_profile_dist() {
    add_profile_build
    check_required "git" "git" "the source tarball is the HEAD commit"
    check_required "bsdtar" "bsdtar" "reproducible release tarballs (libarchive)"
    check_required_sha256
}

add_profile_repro() {
    check_required "git" "git" "clean source tree extraction"
    check_required "tar" "tar" "clean tree archive extraction"
    check_required_sha256
}

if [ "${1:-}" = "--list-tools" ]; then
    LIST_TOOLS_MODE=1
    for p in seed build install test preflight fuzz repro man dist; do
        CURRENT_PROFILE="$p"
        "add_profile_$p"
    done | awk '{
        key = $1 " " $2
        if ($3 == "required" || !(key in seen)) {
            val[key] = $3
            seen[key] = 1
        }
    }
    END {
        for (k in val) {
            print k " " val[k]
        }
    }' | sort
    exit 0
fi

for profile in "$@"; do
    CURRENT_PROFILE="$profile"
    case "$profile" in
        seed)      add_profile_seed ;;
        build)     add_profile_build ;;
        install)   add_profile_install ;;
        test)      add_profile_test ;;
        preflight) add_profile_preflight ;;
        fuzz)      add_profile_fuzz ;;
        repro)     add_profile_repro ;;
        man)       add_profile_man ;;
        dist)      add_profile_dist ;;
        *)
            echo "check_deps.sh: unknown profile '$profile'" >&2
            exit 2
            ;;
    esac
done

if [ -n "$REQ_ERRORS" ]; then
    printf '%s' "$REQ_ERRORS" >&2
    exit 1
fi

if [ -n "$OPT_SKIPS" ] && [ "$REQUIRED_ONLY" -eq 0 ]; then
    printf 'Skipping optional test items: %s\n' "$OPT_SKIPS"
fi

exit 0
