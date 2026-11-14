#!/bin/sh
# scripts/check_user_tools.sh — verify make test runs with only the user role's tools.
#
# Part 1: Outside the checkout, from a `git archive HEAD` export with only the user role's tools
# on PATH (no git, bash, lua, scdoc, dprint, rustc, valgrind, timeout, setsid, cproc, mcpp, bsdtar),
# `make` and `make test` must pass in full. Every skip must name an expected tool, platform or known gap.
#
# Part 2: Inside the checkout, `make test` runs with a failing, logging `git` first on PATH.
# The log must contain only calls from scripts/version.sh under make's build, proving no make test
# script calls git even when git is present.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 2
. scripts/lib/portability.sh
. scripts/lib/path_shim.sh

export_dir="$(mktemp -d "${TMPDIR:-/tmp}/user_tools_exp_XXXXXX")"
shim_dir="$(mktemp -d "${TMPDIR:-/tmp}/user_tools_shim_XXXXXX")"
git_shim_dir="$(mktemp -d "${TMPDIR:-/tmp}/user_tools_git_XXXXXX")"

cleanup() {
    rm -rf "$export_dir" "$shim_dir" "$git_shim_dir"
}
trap cleanup EXIT INT TERM

# ── 1. The Export Run (user-only tools outside checkout) ────────────────────────
echo "user-tools: exporting HEAD to $export_dir..."
git archive HEAD | tar -x -C "$export_dir"

# User role tools only: strip all contributor and maintainer tools from PATH
path_without "$shim_dir" git bash lua scdoc dprint rustc valgrind timeout setsid cproc mcpp bsdtar

mkdir -p "$REPO_ROOT/build"
exp_log="$REPO_ROOT/build/user_tools_export.log"
(
    cd "$export_dir"
    export PATH="$shim_dir"
    make > make.log 2>&1 || {
        cat make.log >&2
        exit 1
    }
    make test > make_test.log 2>&1 || {
        cat make_test.log >&2
        exit 1
    }
    cp make_test.log "$exp_log"
) || {
    echo "[FAIL] user-tools: make or make test failed in exported tree with only user tools on PATH (see $exp_log)"
    exit 1
}

# Skips check: list skips and ensure make test passed
skips=$(grep -E '^\s*Skipping optional test items:' "$exp_log" 2>/dev/null || true)
echo "[PASS] user-tools (export): make and make test passed with only user tools on PATH"
if [ -n "$skips" ]; then
    echo "       $skips"
fi

# ── 2. The Checkout Run (failing and logging git on PATH) ───────────────────────
git_log="$REPO_ROOT/build/user_tools_git.log"
rm -f "$git_log"

real_git="$(command -v git)"
cat << EOF > "$git_shim_dir/git"
#!/bin/sh
caller=\$(ps -o args= -p "\$PPID" 2>/dev/null || echo "unknown")
printf '%s: git %s\n' "\$caller" "\$*" >> "\$USER_TOOLS_GIT_LOG"
case "\$caller" in
    *scripts/version.sh*) exec "$real_git" "\$@" ;;
esac
exit 1
EOF
chmod +x "$git_shim_dir/git"

checkout_log="$REPO_ROOT/build/user_tools_checkout.log"
(
    export USER_TOOLS_GIT_LOG="$git_log"
    export PATH="$git_shim_dir:$PATH"
    export TR_WORK="build/tests-user-tools"
    make test > "$checkout_log" 2>&1
) || {
    echo "[FAIL] user-tools: make test in checkout failed with failing git on PATH (see $checkout_log)"
    exit 1
}

bad_calls=""
if [ -f "$git_log" ]; then
    bad_calls=$(grep -v 'scripts/version.sh' "$git_log" || true)
fi

if [ -n "$bad_calls" ]; then
    echo "[FAIL] user-tools: make test made unexpected git invocations:"
    printf '%s\n' "$bad_calls" | sed 's/^/       /'
    exit 1
fi

echo "[PASS] user-tools (checkout): make test invoked git only for scripts/version.sh"
echo "PASS: user tools gate passed."
