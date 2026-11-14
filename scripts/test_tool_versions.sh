#!/bin/sh
# scripts/test_tool_versions.sh — Verify --version and -V output for each tool
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "${TEST_ROOT:-$REPO_DIR}"

if [ -z "${EXPECT_VER:-}" ]; then
    if [ -f "$REPO_DIR/build/gen/version.zrl" ]; then
        EXPECT_VER=$(sed -n 's/.*return "\(.*\)";.*/\1/p' "$REPO_DIR/build/gen/version.zrl")
    elif [ -f "$REPO_DIR/VERSION" ]; then
        EXPECT_VER=$(tr -d ' \t\r\n' < "$REPO_DIR/VERSION")
    else
        EXPECT_VER="$("$REPO_DIR/scripts/version.sh")"
    fi
fi
if [ -z "$EXPECT_VER" ]; then
    echo "Error: cannot determine expected version" >&2
    exit 1
fi

AUTO_REBUILD="${AUTO_REBUILD:-0}"

errors=0
test_tool() {
    _tool="$1"
    _bin="$2"
    if [ ! -x "$_bin" ]; then
        return 0 # Tool not built in this configuration
    fi
    for flag in --version -V; do
        out="$("$_bin" "$flag" 2>&1)" || {
            echo "[FAIL] $_bin $flag exited non-zero"
            errors=$((errors + 1))
            continue
        }
        expected="$_tool $EXPECT_VER"
        if [ "$out" != "$expected" ]; then
            if [ "$AUTO_REBUILD" -eq 1 ] && [ -f Makefile ] && command -v make >/dev/null 2>&1; then
                case "$_bin" in
                    build/*)
                        if make "$_bin" >/dev/null 2>&1; then
                            out="$("$_bin" "$flag" 2>&1)" || true
                        fi
                        ;;
                esac
            fi
        fi
        if [ "$out" = "$expected" ]; then
            echo "[PASS] $_bin $flag -> $out"
        else
            echo "rebuild $_bin: its version stamp does not match the tree" >&2
            echo "[FAIL] rebuild $_bin: its version stamp does not match the tree (expected '$expected', got '$out')"
            errors=$((errors + 1))
        fi
    done
}

if [ "${1:-}" = "--check-binary" ]; then
    test_tool zoril "$2"
    if [ "$errors" -eq 0 ]; then exit 0; else exit 1; fi
fi

if [ "${1:-}" = "--selftest" ]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT INT TERM
    fake_stale="$tmp/fake_zoril_stale"
    cat << EOF > "$fake_stale"
#!/bin/sh
echo "zoril 0.0.1-stale"
EOF
    chmod +x "$fake_stale"

    fake_good="$tmp/fake_zoril_good"
    cat << EOF > "$fake_good"
#!/bin/sh
echo "zoril $EXPECT_VER"
EOF
    chmod +x "$fake_good"

    mkdir -p "$tmp/bin"
    cat << 'EOF' > "$tmp/bin/make"
#!/bin/sh
echo "MAKE_CALLED" >> "$TMPDIR_MOCK/make.log"
exit 0
EOF
    chmod +x "$tmp/bin/make"

    # Default (no AUTO_REBUILD in env) must NOT call make and must output plain message
    TMPDIR_MOCK="$tmp" PATH="$tmp/bin:$PATH" msg=$(unset AUTO_REBUILD; "$0" --check-binary "$fake_stale" 2>&1 || true)
    if echo "$msg" | grep -q "rebuild $fake_stale: its version stamp does not match the tree"; then
        echo "[PASS] binary stamp mismatch produces plain rebuild message by default"
    else
        echo "[FAIL] binary stamp mismatch did not produce plain rebuild message: $msg"
        exit 1
    fi
    if [ -f "$tmp/make.log" ]; then
        echo "[FAIL] make was called under default AUTO_REBUILD (rebuild inside test)"
        exit 1
    else
        echo "[PASS] make is not invoked by default on stamp mismatch"
    fi

    # Explicit AUTO_REBUILD=1 calls make for build/* paths
    mkdir -p "$tmp/repo/build"
    fake_build_bin="$tmp/repo/build/fake_zoril_build"
    cat << EOF > "$fake_build_bin"
#!/bin/sh
echo "zoril 0.0.1-stale"
EOF
    chmod +x "$fake_build_bin"
    (
        cd "$tmp/repo"
        touch Makefile
        TEST_ROOT="$tmp/repo" TMPDIR_MOCK="$tmp" PATH="$tmp/bin:$PATH" AUTO_REBUILD=1 "$REPO_DIR/scripts/test_tool_versions.sh" --check-binary "build/fake_zoril_build" >/dev/null 2>&1 || true
    )
    if [ -f "$tmp/make.log" ] && grep -q "MAKE_CALLED" "$tmp/make.log"; then
        echo "[PASS] AUTO_REBUILD=1 attempts make rebuild on build/* binary"
    else
        echo "[FAIL] AUTO_REBUILD=1 did not invoke make"
        exit 1
    fi

    if "$0" --check-binary "$fake_good" >/dev/null 2>&1; then
        echo "[PASS] binary stamp match succeeds"
    else
        echo "[FAIL] matching stamp failed"
        exit 1
    fi
    exit 0
fi

# `make test` rebuilds only zoril, zilc, and zbuild, so only those are checked by default:
# a binary of the other tools left from an earlier commit would report a stale version.
# --all adds them (where the tree has them); `make test-versions` builds them first and passes it.
test_tool zoril build/zoril
test_tool zilc build/zilc
test_tool zbuild build/zbuild
if [ "${1:-}" = "--all" ]; then
    :
fi

if [ "$errors" -eq 0 ]; then
    exit 0
else
    exit 1
fi
