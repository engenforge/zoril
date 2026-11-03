#!/bin/sh
# scripts/test_check_deps.sh — Acceptance test for upfront dependency checking.
#
# Asserts that:
#   1. For each required tool of each profile, check_deps.sh exits 1 within 10s
#      and names the missing tool along with install hints.
#   2. Missing optional tools exit 0 and print the 'Skipping optional test items:' line.
#   3. Full entry points (make, test.sh, preflight.sh) fail within 10s in a scratch copy
#      before performing any build or test step when a required tool is missing.

set -u
cd "$(dirname "$0")/.." || exit 2
. scripts/lib/portability.sh
. scripts/lib/path_shim.sh
. scripts/lib/layout.sh

tmp="$(mktemp -d /tmp/test_check_deps_XXXXXX)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

passed=0
failed=0
skipped=0

pass() {
    echo "[PASS] test_check_deps: $*"
    passed=$((passed + 1))
}

fail() {
    echo "[FAIL] test_check_deps: $*" >&2
    failed=$((failed + 1))
}

skip() {
    echo "[SKIP] test_check_deps: $*"
    skipped=$((skipped + 1))
}

# 1. Build a master shim directory of required tools from PATH
master_shim="$tmp/master_shim"
mkdir -p "$master_shim"

tools="sh bash make cc gcc clang qbe as gas ld ld.bfd ld.gold ld.lld awk gawk mawk nawk sed flock lua lua5.4 lua5.3 lua5.2 lua5.1 luajit mkfifo xargs scdoc timeout git tar bsdtar gzip curl ssh scp cmp podman valgrind dprint rustc setsid cproc mcpp grep cat rm cp ln mkdir touch chmod uname head tr mktemp sleep kill ps sort seq uniq diff date cut tee mv find comm wc true false test expr basename dirname"

for t in $tools; do
    # scdoc is stubbed below: the preflight profile refuses an scdoc older than 1.11.5, so these rows
    # must not depend on which scdoc (or whether any) the host has.
    [ "$t" = scdoc ] && continue
    p=$(command -v "$t" 2>/dev/null || true)
    if [ -n "$p" ] && [ -x "$p" ]; then
        ln -s "$p" "$master_shim/$t" 2>/dev/null || true
    fi
done
# An scdoc that reports 1.11.5, the minimum, and copies stdin to stdout otherwise.
printf '#!/bin/sh\nif [ "${1:-}" = -v ]; then echo "scdoc 1.11.5"; exit 0; fi\ncat\n' > "$master_shim/scdoc"
chmod +x "$master_shim/scdoc"

# Also check for sha256 tools
_sha="sha256""sum"
for s in "$_sha" shasum sha256; do
    p=$(command -v "$s" 2>/dev/null || true)
    if [ -n "$p" ] && [ -x "$p" ]; then
        ln -s "$p" "$master_shim/$s" 2>/dev/null || true
    fi
done

# The toolchain the caller configured: make exports BACKEND_BIN and the rest, and a config.local.mk
# may point them outside PATH. Offer each under its default name, then unset the variables, so that
# every case below controls what is visible through PATH alone. Without this, a qbe reachable only
# through config.local.mk looked missing to every case, and hiding qbe from PATH proved nothing.
_cfg_tool() {   # $1 = default name, $2 = configured command (its first word is the program)
    _p=$(command -v "${2%% *}" 2>/dev/null || true)
    if [ -n "$_p" ] && [ -x "$_p" ]; then
        ln -sf "$_p" "$master_shim/$1"
    fi
}
_cfg_tool qbe "${BACKEND_BIN:-qbe}"
_cfg_tool as "${ASSEMBLER_BIN:-as}"
_cfg_tool ld "${LINKER_BIN:-ld}"
_cfg_tool cc "${CC:-cc}"
_cfg_tool link_cc "${LINK_CC:-cc}"
_cfg_tool cproc "${CPROC:-cproc}"
_cfg_tool mcpp "${MINIMAL_CPP:-mcpp}"
unset BACKEND_BIN ASSEMBLER_BIN LINKER_BIN CC LINK_CC CPROC MINIMAL_CPP REPO_ROOT
unset MAKEFLAGS MAKEOVERRIDES MFLAGS MAKELEVEL

# Helper to create a sub-shim missing specified tool patterns
create_sub_shim() {
    _src="$1"
    _dest="$2"
    shift 2
    mkdir -p "$_dest"
    for item in "$_src"/*; do
        bname="${item##*/}"
        _exclude=0
        for pat in "$@"; do
            case "$bname" in
                $pat) _exclude=1; break ;;
            esac
        done
        if [ $_exclude -eq 0 ]; then
            ln -s "$item" "$_dest/$bname" 2>/dev/null || true
        fi
    done
}

## -----------------------------------------------------------------------------
# Part 1: Direct profile tests against check_deps.sh driven by --list-tools
# -----------------------------------------------------------------------------

# For Part 1 (acceptance testing of check_deps.sh in isolation):
# Ensure all tracked tools exist in deps_master_shim so that check_deps.sh
# tests each (tool, profile) in isolation without being derailed if an optional tool
# (or git/timeout/valgrind) is missing from the outer environment.
deps_master_shim="$tmp/deps_master_shim"
mkdir -p "$deps_master_shim"
for item in "$master_shim"/*; do
    [ -e "$item" ] || continue
    ln -s "$item" "$deps_master_shim/${item##*/}" 2>/dev/null || true
done

for t in $tools; do
    if [ ! -e "$deps_master_shim/$t" ]; then
        if [ "$t" = "timeout" ]; then
            cat << 'EOF' > "$deps_master_shim/timeout"
#!/bin/sh
while [ $# -gt 0 ]; do
    case "$1" in
        --foreground|-v) shift ;;
        -k|-s|--kill-after|--signal) shift 2 ;;
        -*) shift ;;
        *) shift; break ;;
    esac
done
exec "$@"
EOF
            chmod +x "$deps_master_shim/timeout"
        else
            printf '#!/bin/sh\nexit 0\n' > "$deps_master_shim/$t"
            chmod +x "$deps_master_shim/$t"
        fi
    fi
done

_has_sha=0
for s in "$_sha" shasum sha256; do
    if [ -x "$deps_master_shim/$s" ]; then
        _has_sha=1; break
    fi
done
if [ $_has_sha -eq 0 ]; then
    printf '#!/bin/sh\necho "0000000000000000000000000000000000000000000000000000000000000000  -"\n' > "$deps_master_shim/sha256sum"
    chmod +x "$deps_master_shim/sha256sum"
fi

# Drive per-profile loops dynamically from check_deps.sh --list-tools
# Single source of truth: any tool added to check_deps.sh is tested automatically
while read -r tool profile kind; do
    [ -n "$tool" ] || continue
    shim_dir="$tmp/shim_${profile}_${tool}"
    pats="$(tool_patterns "$tool") busybox"
    create_sub_shim "$deps_master_shim" "$shim_dir" $pats

    if [ "$kind" = "required" ]; then
        rc=0
        out=$(PATH="$shim_dir" run_with_timeout 10 ./scripts/check_deps.sh "$profile" 2>&1) || rc=$?
        if [ $rc -ne 0 ] && echo "$out" | grep -qF "Missing required tool: $tool"; then
            pass "profile $profile detects missing required $tool"
        else
            fail "profile $profile did not report missing required $tool properly (rc=$rc, out=$out)"
        fi
    elif [ "$kind" = "optional" ]; then
        rc=0
        out=$(PATH="$shim_dir" run_with_timeout 10 ./scripts/check_deps.sh "$profile" 2>&1) || rc=$?
        if [ $rc -eq 0 ] && echo "$out" | grep -qF "Skipping optional test items:" && echo "$out" | grep -qF "$tool"; then
            pass "profile $profile reports missing optional $tool in optional test items"
        else
            fail "profile $profile did not report missing optional $tool properly (rc=$rc, out=$out)"
        fi

        # Contract: --required-only prints nothing on success
        rc_req=0
        out_req=$(PATH="$shim_dir" run_with_timeout 10 ./scripts/check_deps.sh --required-only "$profile" 2>/dev/null) || rc_req=$?
        if [ $rc_req -eq 0 ] && [ -z "$out_req" ]; then
            pass "profile $profile --required-only prints nothing on success when optional $tool is missing"
        else
            fail "profile $profile --required-only printed output or failed (rc=$rc_req, out=$out_req)"
        fi
    fi
done << EOF
$(./scripts/check_deps.sh --list-tools)
EOF

# Test all optional tools together report "Skipping optional test items:" on a single line
shim_dir="$tmp/shim_test_all_opts"
create_sub_shim "$deps_master_shim" "$shim_dir" valgrind dprint rustc setsid git timeout
rc=0
out=$(PATH="$shim_dir" run_with_timeout 10 ./scripts/check_deps.sh test 2>&1) || rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -qF "Skipping optional test items:" && \
   echo "$out" | grep -qF "valgrind" && \
   echo "$out" | grep -qF "dprint" && \
   echo "$out" | grep -qF "rustc"; then
    pass "profile test reports optional skips on single line with exit 0"
else
    fail "profile test did not report optional skips properly (rc=$rc, out=$out)"
fi

# A QBE that is older than 1.3 is refused with the version it needs; one that prints
# nothing about them, like a stand-in, is not.
shim_dir="$tmp/shim_old_qbe"
create_sub_shim "$deps_master_shim" "$shim_dir" qbe
printf '#!/bin/sh\necho "qbe:-:3: identifier too long" >&2\nexit 1\n' > "$shim_dir/qbe"
chmod +x "$shim_dir/qbe"
rc=0
out=$(PATH="$shim_dir" run_with_timeout 10 ./scripts/check_deps.sh build 2>&1) || rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -qF "QBE 1.3 or newer is required"; then
    pass "profile build refuses a QBE older than 1.3"
else
    fail "profile build did not refuse an old QBE (rc=$rc, out=$out)"
fi
printf '#!/bin/sh\nexit 0\n' > "$shim_dir/qbe"
rc=0
out=$(PATH="$shim_dir" run_with_timeout 10 ./scripts/check_deps.sh build 2>&1) || rc=$?
if [ $rc -eq 0 ]; then
    pass "profile build accepts a QBE that reports no unknown keyword"
else
    fail "profile build refused a quiet QBE (rc=$rc, out=$out)"
fi

# A Lua older than 5.3 (no math.tointeger; the stand-in exits 1 for it) is refused for the fuzzer and
# skipped, with its reason, in the test profile.
shim_dir="$tmp/shim_old_lua"
create_sub_shim "$deps_master_shim" "$shim_dir" lua
printf '#!/bin/sh\nexit 1\n' > "$shim_dir/lua"
chmod +x "$shim_dir/lua"
rc=0
out=$(PATH="$shim_dir" run_with_timeout 10 ./scripts/check_deps.sh fuzz 2>&1) || rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -qF "older than 5.3"; then
    pass "profile fuzz refuses a Lua older than 5.3"
else
    fail "profile fuzz did not refuse an old Lua (rc=$rc, out=$out)"
fi
rc=0
out=$(PATH="$shim_dir" run_with_timeout 10 ./scripts/check_deps.sh test 2>&1) || rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -qF "lua 5.3 or newer"; then
    pass "profile test skips the Lua items, naming the version, for a Lua older than 5.3"
else
    fail "profile test did not skip for an old Lua (rc=$rc, out=$out)"
fi
printf '#!/bin/sh\nexit 0\n' > "$shim_dir/lua"
rc=0
out=$(PATH="$shim_dir" run_with_timeout 10 ./scripts/check_deps.sh --required-only fuzz 2>&1) || rc=$?
if [ $rc -eq 0 ]; then
    pass "profile fuzz accepts a Lua that has math.tointeger"
else
    fail "profile fuzz refused a Lua 5.3 stand-in (rc=$rc, out=$out)"
fi

# An scdoc older than 1.11.5, the version the committed man pages are generated with, is refused by
# the preflight profile, naming the version found and the minimum (the stub reports 1.11.2).
shim_dir="$tmp/shim_old_scdoc"
create_sub_shim "$deps_master_shim" "$shim_dir" scdoc
printf '#!/bin/sh\nif [ "${1:-}" = -v ]; then echo "scdoc 1.11.2"; exit 0; fi\ncat\n' > "$shim_dir/scdoc"
chmod +x "$shim_dir/scdoc"
rc=0
out=$(PATH="$shim_dir" run_with_timeout 10 ./scripts/check_deps.sh preflight 2>&1) || rc=$?
if [ $rc -eq 1 ] && echo "$out" | grep -qF "1.11.2" && echo "$out" | grep -qF "1.11.5"; then
    pass "profile preflight refuses an scdoc older than 1.11.5, naming 1.11.2 and 1.11.5"
else
    fail "profile preflight did not refuse an scdoc 1.11.2 (rc=$rc, out=$out)"
fi

# -----------------------------------------------------------------------------
# Part 2: Real entry points in scratch copy (make, test.sh, preflight.sh)
# -----------------------------------------------------------------------------
scratch="$tmp/scratch"
mkdir -p "$scratch"
if git_checkout_usable .; then
    git archive HEAD | tar -x -C "$scratch"
else
    tar --exclude="./build*" --exclude="build" --exclude="./.git*" --exclude=".git" --exclude="./scratch*" \
        --exclude="./.agx*" --exclude="./.aiauto*" --exclude="./.agent-data*" \
        --exclude="./.claude*" --exclude="./.antigravity*" --exclude="./.reasonix*" \
        -cf - . | (cd "$scratch" && tar -xf -)
fi
cp Makefile config.mk scripts/check_deps.sh scripts/test.sh scripts/preflight.sh "$scratch/" 2>/dev/null || true
cp scripts/check_deps.sh "$scratch/scripts/"
cp scripts/test.sh "$scratch/scripts/"
cp scripts/preflight.sh "$scratch/scripts/"
chmod +x "$scratch/scripts"/*.sh

# Entry point 0: make SYSTEM_ZORIL=1 CC=no-such-cc build/runtime.o exits 0 without cc
rc=0
out=$(cd "$scratch" && PATH="$master_shim" run_with_timeout 10 make SYSTEM_ZORIL=1 CC=no-such-cc build/runtime.o 2>&1) || rc=$?
if [ $rc -eq 0 ]; then
    pass "make with SYSTEM_ZORIL=1 CC=no-such-cc build/runtime.o succeeds without C compiler"
else
    fail "make SYSTEM_ZORIL=1 CC=no-such-cc build/runtime.o failed (rc=$rc, out=$out)"
fi

# Entry point 1a: make fresh path without cc fails upfront before bootstrap compiler build
rm -rf "$scratch/build" "$scratch/$STAGE0_DIR/build"
shim_cc="$tmp/shim_entry_cc"
create_sub_shim "$master_shim" "$shim_cc" cc gcc clang
rc=0
out=$(cd "$scratch" && PATH="$shim_cc" run_with_timeout 10 make 2>&1) || rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -qi "C bootstrap compiler" && [ ! -f "$scratch/build/zoril" ]; then
    pass "make fails upfront within 10s on missing cc before bootstrap compiler build"
else
    fail "make did not fail upfront properly on missing cc (rc=$rc, out=$out)"
fi

# Entry point 1b: make fails upfront before any build step when backend (qbe) is missing
shim_qbe="$tmp/shim_entry_qbe"
create_sub_shim "$master_shim" "$shim_qbe" qbe
rc=0
out=$(cd "$scratch" && PATH="$shim_qbe" run_with_timeout 10 make 2>&1) || rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -qF "Missing required tool: qbe" && [ ! -d "$scratch/build" ]; then
    pass "make fails upfront within 10s on missing qbe before build step"
elif [ $rc -ne 0 ] && echo "$out" | grep -qF "Missing required tool: qbe" && [ ! -f "$scratch/build/zoril" ]; then
    pass "make fails upfront within 10s on missing qbe before compiler build"
else
    fail "make did not fail upfront properly on missing qbe (rc=$rc, out=$out)"
fi

# Entry point 1c: config.local.mk BACKEND_BIN ?= override outside PATH takes effect
custom_qbe_dir="$tmp/custom_qbe"
mkdir -p "$custom_qbe_dir"
_real_qbe="$master_shim/qbe"
if [ -x "$_real_qbe" ]; then
    ln -sf "$_real_qbe" "$custom_qbe_dir/my_qbe"
    echo "BACKEND_BIN ?= $custom_qbe_dir/my_qbe" > "$scratch/config.local.mk"
    rc=0
    out=$(cd "$scratch" && PATH="$shim_qbe" run_with_timeout 10 make deps-build 2>&1) || rc=$?
    rm -f "$scratch/config.local.mk"
    if [ $rc -eq 0 ]; then
        pass "make deps-build succeeds with BACKEND_BIN ?= override in config.local.mk when qbe is not in PATH"
    else
        fail "make deps-build failed with config.local.mk override (rc=$rc, out=$out)"
    fi
else
    skip "config.local.mk override case needs a qbe (on PATH or configured) to point at"
fi

# Entry point 1d: BACKEND_BIN = ~/no/such/qbe fails and explains make does not expand ~
echo "BACKEND_BIN = ~/no/such/qbe" > "$scratch/config.local.mk"
rc=0
out=$(cd "$scratch" && PATH="$shim_qbe" run_with_timeout 10 make deps-build 2>&1) || rc=$?
rm -f "$scratch/config.local.mk"
if [ $rc -ne 0 ] && echo "$out" | grep -qF "BACKEND_BIN" && echo "$out" | grep -qF "does not expand"; then
    pass "make deps-build fails on ~ in BACKEND_BIN and explains make does not expand ~"
else
    fail "make deps-build did not report ~ expansion error properly (rc=$rc, out=$out)"
fi

# Entry point 1e: BACKEND_BIN = /no/such/qbe names path and contains no package install hints
echo "BACKEND_BIN = /no/such/qbe" > "$scratch/config.local.mk"
rc=0
out=$(cd "$scratch" && PATH="$shim_qbe" run_with_timeout 10 make deps-build 2>&1) || rc=$?
rm -f "$scratch/config.local.mk"
if [ $rc -ne 0 ] && echo "$out" | grep -qF "/no/such/qbe" && ! echo "$out" | grep -qF "apk add"; then
    pass "make deps-build with path BACKEND_BIN names path and contains no package install hints"
else
    fail "make deps-build did not report path error properly (rc=$rc, out=$out)"
fi

# Entry point 1f: CC in config.local.mk reaches deps-seed
echo "CC = no-such-cc" > "$scratch/config.local.mk"
rc=0
out=$(cd "$scratch" && run_with_timeout 10 make deps-seed 2>&1) || rc=$?
rm -f "$scratch/config.local.mk"
if [ $rc -ne 0 ] && echo "$out" | grep -qF "CC=no-such-cc"; then
    pass "make deps-seed fails when CC in config.local.mk is missing and names CC=no-such-cc"
else
    fail "make deps-seed did not report missing CC from config.local.mk properly (rc=$rc, out=$out)"
fi

# Entry point 1g: default CC works when config.local.mk is removed
_real_cc=$(command -v cc 2>/dev/null || true)
if [ -n "$_real_cc" ] && [ -x "$_real_cc" ]; then
    rc=0
    out=$(cd "$scratch" && run_with_timeout 10 make deps-seed 2>&1) || rc=$?
    if [ $rc -eq 0 ]; then
        pass "make deps-seed succeeds with default cc when config.local.mk is removed"
    else
        fail "make deps-seed failed with default cc (rc=$rc, out=$out)"
    fi
else
    skip "default cc case needs a cc on PATH"
fi

# Entry point 1h: make succeeds without cc when stage0 seed compiler is already built
mkdir -p "$scratch/$STAGE0_DIR/build"
touch "$scratch/$STAGE0_DIR/build/zoril-c.release"
rc=0
out=$(cd "$scratch" && PATH="$shim_cc" run_with_timeout 10 make -n 2>&1) || rc=$?
rm -rf "$scratch/$STAGE0_DIR/build"
if [ $rc -eq 0 ] && ! echo "$out" | grep -qi "Missing required tool: cc"; then
    pass "make succeeds without cc when stage0 seed is already built"
else
    fail "make failed without cc when stage0 seed was already built (rc=$rc, out=$out)"
fi

# Entry point 1i: make stage0-C seed with CC=cproc and cpp off PATH builds seed or gives actionable error
_real_cproc=$(command -v cproc 2>/dev/null || true)
if [ -n "$_real_cproc" ] && [ -x "$_real_cproc" ]; then
    shim_no_cpp="$tmp/shim_entry_no_cpp"
    create_sub_shim "$master_shim" "$shim_no_cpp" cpp
    echo "CC = $_real_cproc" > "$scratch/config.local.mk"
    rc=0
    out=$(cd "$scratch" && PATH="$shim_no_cpp" run_with_timeout 15 make "$STAGE0_DIR/build/zoril-c.release" 2>&1) || rc=$?
    rm -f "$scratch/config.local.mk"
    rm -rf "$scratch/$STAGE0_DIR/build"
    if echo "$out" | grep -q 'spawn "cpp"'; then
        fail "make with CC=cproc failed with bare spawn cpp error: $out"
    elif [ $rc -eq 0 ]; then
        pass "make with CC=cproc builds seed cleanly when cpp is off PATH"
    elif echo "$out" | grep -Eq "(mcpp not found|musl include headers not found)"; then
        pass "make with CC=cproc gives actionable preprocessor/musl error when missing"
    else
        fail "make with CC=cproc unexpected failure: rc=$rc, out=$out"
    fi
else
    skip "cproc not found on host"
fi

# Entry point 2: test.sh fails upfront before running tests when flock is missing
shim_flock="$tmp/shim_entry_flock"
create_sub_shim "$master_shim" "$shim_flock" flock busybox
rc=0
out=$(cd "$scratch" && TR_WORK="$tmp/tr_work_flock" PATH="$shim_flock" run_with_timeout 10 ./scripts/test.sh 2>&1) || rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -qF "Missing required tool: flock" && [ ! -f "$tmp/tr_work_flock/.lock" ]; then
    pass "test.sh fails upfront within 10s on missing flock before taking test lock"
else
    fail "test.sh did not fail upfront properly on missing flock (rc=$rc, out=$out)"
fi

# Entry point 3: test.sh fails upfront before running tests when mkfifo is missing
shim_mkfifo="$tmp/shim_entry_mkfifo"
create_sub_shim "$master_shim" "$shim_mkfifo" "mkfifo"
rc=0
out=$(cd "$scratch" && TR_WORK="$tmp/tr_work_mkfifo" PATH="$shim_mkfifo" run_with_timeout 10 ./scripts/test.sh 2>&1) || rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -qF "Missing required tool: mkfifo"; then
    pass "test.sh fails upfront within 10s on missing mkfifo before running tests"
else
    fail "test.sh did not fail upfront properly on missing mkfifo (rc=$rc, out=$out)"
fi

# Entry point 3b: test.sh --gate stage0c-unit fails upfront naming C compiler when cc is missing
rc=0
out=$(cd "$scratch" && TR_WORK="$tmp/tr_work_stage0c" PATH="$shim_cc" run_with_timeout 10 ./scripts/test.sh --gate stage0c-unit 2>&1) || rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -qi "C bootstrap compiler" && [ ! -d "$tmp/tr_work_stage0c/items" ]; then
    pass "test.sh --gate stage0c-unit fails upfront within 10s naming C compiler when cc is missing"
else
    fail "test.sh --gate stage0c-unit did not fail upfront properly on missing cc (rc=$rc, out=$out)"
fi

# Entry point 3c: test.sh --gate md-check succeeds without asking for C compiler when cc is missing
rc=0
out=$(cd "$scratch" && TR_WORK="$tmp/tr_work_md" PATH="$shim_cc" run_with_timeout 10 ./scripts/test.sh --gate md-check 2>&1) || rc=$?
if [ $rc -eq 0 ] && ! echo "$out" | grep -qi "C bootstrap compiler" && ! echo "$out" | grep -qi "seed"; then
    pass "test.sh --gate md-check succeeds without asking for C compiler when cc is missing"
else
    fail "test.sh --gate md-check failed or asked for C compiler when cc is missing (rc=$rc, out=$out)"
fi

# Entry point 4: preflight.sh fails upfront before starting selfhost when timeout is missing
shim_timeout="$tmp/shim_entry_timeout"
create_sub_shim "$master_shim" "$shim_timeout" timeout busybox
rc=0
out=$(cd "$scratch" && PATH="$shim_timeout" run_with_timeout 10 ./scripts/preflight.sh 2>&1) || rc=$?
if [ $rc -ne 0 ] && echo "$out" | grep -qF "Missing required tool: timeout" && [ ! -f "$scratch/build/preflight-selfhost.log" ]; then
    pass "preflight.sh fails upfront within 10s on missing timeout before launching selfhost"
else
    fail "preflight.sh did not fail upfront properly on missing timeout (rc=$rc, out=$out)"
fi

if [ "$skipped" -gt 0 ]; then
    echo "test_check_deps: $passed passed, $failed failed, $skipped skipped."
else
    echo "test_check_deps: $passed passed, $failed failed."
fi
[ "$failed" -eq 0 ]
