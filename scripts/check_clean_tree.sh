#!/bin/sh
# scripts/check_clean_tree.sh — Guard gate: no stray build artifacts in root or source dirs.
#
# Asserts that neither the repository root nor any tracked source directory
# (src/, stdlib/, rt/, tools/, tests/, bench/, bootstrap seeds) contains stray build artifacts
# (such as a.out, *.o, *.s, *.ssa). All build output belongs under build/ (or mktemp dirs).
#
# Usage:
#   scripts/check_clean_tree.sh             Run checks on current repository
#   scripts/check_clean_tree.sh <dir>       Run checks on target directory
#   scripts/check_clean_tree.sh --selftest  Run checker selftest
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = "--selftest" ]; then
    GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_GLOBAL
    GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_SYSTEM
    GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_NOSYSTEM
    unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
    for _v in $(env 2>/dev/null | sed -n 's/^\(GIT_CONFIG_[KEY|VALUE].*\)=.*/\1/p'); do
        unset "$_v"
    done

    tmp="${TMPDIR:-/tmp}/check_clean_tree_selftest.$$"
    rm -rf "$tmp"
    mkdir -p "$tmp/repo"
    
    if ! git init -q "$tmp/repo" 2>/dev/null; then
        echo "[SKIP] clean-tree: git not available for selftest"
        rm -rf "$tmp"
        exit 0
    fi
    git -C "$tmp/repo" config user.email "test@example.com" 2>/dev/null || true
    git -C "$tmp/repo" config user.name "Test" 2>/dev/null || true
    git -C "$tmp/repo" config commit.gpgsign false 2>/dev/null || true
    git -C "$tmp/repo" config tag.gpgsign false 2>/dev/null || true
    git -C "$tmp/repo" config core.hooksPath /dev/null 2>/dev/null || true
    
    mkdir -p "$tmp/repo/src" "$tmp/repo/build"
    printf 'build/\n*.o\n*.s\n*.ssa\n' > "$tmp/repo/.gitignore"
    printf '// main\n' > "$tmp/repo/src/main.zrl"
    git -C "$tmp/repo" add . >/dev/null 2>&1
    git -C "$tmp/repo" -c commit.gpgsign=false commit -q -m "initial" >/dev/null 2>&1
    
    # 1. Clean repo should pass
    if ! "$0" "$tmp/repo" > "$tmp/clean.log" 2>&1; then
        echo "[FAIL] selftest: clean repo failed check:"
        cat "$tmp/clean.log"
        rm -rf "$tmp"
        exit 1
    fi

    # 2. Untracked source/notes files (ordinary work in progress) must pass
    touch "$tmp/repo/src/new.zrl" "$tmp/repo/NOTES.md"
    if ! "$0" "$tmp/repo" > "$tmp/untracked.log" 2>&1; then
        echo "[FAIL] selftest: untracked files in work-in-progress erroneously failed check:"
        cat "$tmp/untracked.log"
        rm -rf "$tmp"
        exit 1
    fi
    rm -f "$tmp/repo/src/new.zrl" "$tmp/repo/NOTES.md"
    
    # 3. Stray ignored artifact in root should fail and name the path
    touch "$tmp/repo/stray.o"
    if "$0" "$tmp/repo" > "$tmp/root_obj.log" 2>&1; then
        echo "[FAIL] selftest: stray ignored artifact in root was not detected"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "root: stray\.o" "$tmp/root_obj.log"; then
        echo "[FAIL] selftest: failure log did not name root: stray.o:"
        cat "$tmp/root_obj.log"
        rm -rf "$tmp"
        exit 1
    fi
    rm -f "$tmp/repo/stray.o"
    
    # 4. Stray .o in tracked source directory should fail
    touch "$tmp/repo/src/temp.o"
    if "$0" "$tmp/repo" > "$tmp/obj.log" 2>&1; then
        echo "[FAIL] selftest: stray src/temp.o was not detected"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "src/temp\.o" "$tmp/obj.log"; then
        echo "[FAIL] selftest: failure log did not name src/temp.o:"
        cat "$tmp/obj.log"
        rm -rf "$tmp"
        exit 1
    fi
    rm -f "$tmp/repo/src/temp.o"

    # 5. Nested stray in source directory should fail
    mkdir -p "$tmp/repo/src/sub/nested"
    touch "$tmp/repo/src/sub/nested/deep.o"
    if "$0" "$tmp/repo" > "$tmp/nested.log" 2>&1; then
        echo "[FAIL] selftest: nested stray in src/sub/nested/deep.o was not detected"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "src/sub/nested/deep\.o" "$tmp/nested.log"; then
        echo "[FAIL] selftest: failure log did not name src/sub/nested/deep.o:"
        cat "$tmp/nested.log"
        rm -rf "$tmp"
        exit 1
    fi
    rm -rf "$tmp/repo/src/sub"

    # 6. Stray in tests/ and bench/ should fail
    mkdir -p "$tmp/repo/tests" "$tmp/repo/bench"
    touch "$tmp/repo/tests/stray.o"
    if "$0" "$tmp/repo" > "$tmp/test_obj.log" 2>&1; then
        echo "[FAIL] selftest: stray in tests/stray.o was not detected"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "tests/stray\.o" "$tmp/test_obj.log"; then
        echo "[FAIL] selftest: failure log did not name tests/stray.o:"
        cat "$tmp/test_obj.log"
        rm -rf "$tmp"
        exit 1
    fi
    rm -f "$tmp/repo/tests/stray.o"

    touch "$tmp/repo/bench/stray.o"
    if "$0" "$tmp/repo" > "$tmp/bench_obj.log" 2>&1; then
        echo "[FAIL] selftest: stray in bench/stray.o was not detected"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "bench/stray\.o" "$tmp/bench_obj.log"; then
        echo "[FAIL] selftest: failure log did not name bench/stray.o:"
        cat "$tmp/bench_obj.log"
        rm -rf "$tmp"
        exit 1
    fi
    rm -f "$tmp/repo/bench/stray.o"
    
    # 7. config.local.mk in root is allowed and should pass
    touch "$tmp/repo/config.local.mk"
    if ! "$0" "$tmp/repo" > "$tmp/localmk.log" 2>&1; then
        echo "[FAIL] selftest: config.local.mk in root was erroneously flagged as stray"
        cat "$tmp/localmk.log"
        rm -rf "$tmp"
        exit 1
    fi
    rm -f "$tmp/repo/config.local.mk"

    # 8. Copy-under-a-repository: non-git directory inside a git repo should use filesystem check
    mkdir -p "$tmp/repo/build/fresh-bootstrap/tree/src/sub"
    touch "$tmp/repo/build/fresh-bootstrap/tree/a.out"
    touch "$tmp/repo/build/fresh-bootstrap/tree/src/sub/stray.o"
    if "$0" "$tmp/repo/build/fresh-bootstrap/tree" > "$tmp/copy_repo.log" 2>&1; then
        echo "[FAIL] selftest: copy-under-a-repository with stray artifacts was erroneously passed"
        rm -rf "$tmp"
        exit 1
    fi
    if ! grep -q "root: a\.out" "$tmp/copy_repo.log" || ! grep -q "src/sub/stray\.o" "$tmp/copy_repo.log"; then
        echo "[FAIL] selftest: copy-under-a-repository log did not name both root: a.out and src/sub/stray.o:"
        cat "$tmp/copy_repo.log"
        rm -rf "$tmp"
        exit 1
    fi
    rm -rf "$tmp/repo/build/fresh-bootstrap"

    # 9. Clean repo passes again
    if ! "$0" "$tmp/repo" > /dev/null 2>&1; then
        echo "[FAIL] selftest: repo not clean after removing test files"
        rm -rf "$tmp"
        exit 1
    fi
    
    rm -rf "$tmp"
    echo "[PASS] clean-tree: selftest passed"
    exit 0
fi

TARGET_ROOT="${1:-$REPO_ROOT}"
fail=0

STAGE0_DIR=""
STAGE1_DIR=""
if [ -f "$(dirname "$0")/lib/layout.sh" ]; then
    REPO_ROOT="$TARGET_ROOT"
    . "$(dirname "$0")/lib/layout.sh"
fi
STAGE0_DIR="${STAGE0_DIR:-bootstrap/stage0-c}"
STAGE1_DIR="${STAGE1_DIR:-bootstrap/stage1}"

check_git_status() {
    _dir="$1"
    _status=$(git -C "$_dir" status --ignored --porcelain 2>/dev/null || true)
    [ -n "$_status" ] || return 0
    
    _violations=""
    _saved_ifs="$IFS"
    IFS='
'
    for _line in $_status; do
        [ -n "$_line" ] || continue
        case "$_line" in
            \!\!\ *) ;;
            *) continue ;;
        esac
        
        _raw="${_line#???}"
        # Strip surrounding quotes if path contains special characters/spaces
        _path="${_raw#\"}"
        _path="${_path%\"}"
        
        # Allowed exceptions (only specific ignored patterns, not whole directory trees):
        case "$_path" in
            build/*|build|*/build/*|*/build) continue ;;
            vendor/*|vendor|*/vendor/*|*/vendor) continue ;;
            config.local.mk) continue ;;
            .git/*|.git) continue ;;
            .DS_Store|*/.DS_Store|*~|*.swp|*/*.swp|vgcore.*|*/vgcore.*) continue ;;
            .aiauto/*|.aiauto|*/.aiauto/*|*/.aiauto) continue ;;
            .agent-data/*|.agent-data|*/.agent-data/*|*/.agent-data) continue ;;
            .claude/*|.claude|*/.claude/*|*/.claude) continue ;;
            .antigravitycli/*|.antigravitycli|*/.antigravitycli/*|*/.antigravitycli) continue ;;
            .agx/*|.agx|*/.agx/*|*/.agx) continue ;;
            .reasonix/*|.reasonix|*/.reasonix/*|*/.reasonix) continue ;;
            .agx_handoff.md|.agy_handoff.md|reasonix.toml) continue ;;
            .zoril-cache/*|.zoril-cache|*/.zoril-cache/*|*/.zoril-cache) continue ;;
            perf.data|perf.data.old|*/perf.data|*/perf.data.old) continue ;;
            scratch/*|scratch|*/scratch/*|*/scratch) continue ;;
            # Specific test expectations / fixtures
            tests/*.out|tests/*/*.out|tests/*/*/*.out|*/tests/*.out|*/tests/*/*.out|*/tests/*/*/*.out) continue ;;
            rt/runtime.s|*/rt/runtime.s) continue ;;
            tools/*/test/*.ssa|*/tools/*/test/*.ssa) continue ;;
            tools/*/test/fixtures/*.s|*/tools/*/test/fixtures/*.s) continue ;;
            bootstrap/*/tests/fixtures/*.ssa|*/bootstrap/*/tests/fixtures/*.ssa) continue ;;
            tests/integration/external_stub.s|*/tests/integration/external_stub.s) continue ;;
            */lib/rt/*.s|lib/rt/*.s) continue ;;
            # Specific bootstrap patterns from .gitignore
            bootstrap/_*|*/bootstrap/_*) continue ;;
            bootstrap/tools_chain/*|bootstrap/tools_chain|*/bootstrap/tools_chain/*|*/bootstrap/tools_chain) continue ;;
            bootstrap/*/proof/*|bootstrap/*/proof|*/bootstrap/*/proof/*|*/bootstrap/*/proof) continue ;;
            bootstrap/zoril_flat/proof/*|*/bootstrap/zoril_flat/proof/*) continue ;;
            # Specific bench patterns from .gitignore
            bench/20*|*/bench/20*) continue ;;
            bench/cross_lang/*/target/*|bench/cross_lang/*/target|*/bench/cross_lang/*/target/*|*/bench/cross_lang/*/target) continue ;;
        esac
        
        # If git collapsed an unexempt ignored directory, expand to individual files
        case "$_path" in
            */)
                if [ -d "$_dir/$_path" ]; then
                    _subfiles=$(find "$_dir/$_path" -type f 2>/dev/null || true)
                    for _sf in $_subfiles; do
                        _rel="${_sf#$_dir/}"
                        case "$_rel" in
                            src/*|stdlib/*|rt/*|tools/*|tests/*|bench/*|"$STAGE0_DIR"/*|"$STAGE1_DIR"/*|bootstrap/*)
                                _violations="${_violations}source: ${_rel}
"
                                ;;
                        esac
                    done
                fi
                continue
                ;;
        esac

        # Check if file is directly in repository root (no slash in path)
        case "$_path" in
            */*) ;;
            *)
                _violations="${_violations}root: ${_path}
"
                continue
                ;;
        esac
        
        # Check if inside a checked directory
        case "$_path" in
            src/*|stdlib/*|rt/*|tools/*|tests/*|bench/*|"$STAGE0_DIR"/*|"$STAGE1_DIR"/*|bootstrap/*)
                _violations="${_violations}source: ${_path}
"
                ;;
        esac
    done
    IFS="$_saved_ifs"
    
    if [ -n "$_violations" ]; then
        echo "$_violations"
        return 1
    fi
    return 0
}

check_nongit_dir() {
    _dir="$1"
    _violations=""
    # Check root for stray build artifacts
    for _pattern in "a.out" "*.o" "*.s" "*.ssa"; do
        for _f in "$_dir"/$_pattern; do
            [ -e "$_f" ] 2>/dev/null || continue
            case "${_f#$_dir/}" in
                config.local.mk) continue ;;
                *) _violations="${_violations}root: ${_f#$_dir/}
" ;;
            esac
        done
    done

    # Check source, test, bench, and bootstrap directories recursively
    for _sdir in src stdlib rt tools tests bench "$STAGE0_DIR" "$STAGE1_DIR" bootstrap; do
        [ -d "$_dir/$_sdir" ] || continue
        _found=$(find "$_dir/$_sdir" -type f \( -name '*.o' -o -name '*.s' -o -name '*.ssa' -o -name a.out \) 2>/dev/null || true)
        [ -n "$_found" ] || continue
        _saved_ifs="$IFS"
        IFS='
'
        for _f in $_found; do
            [ -n "$_f" ] || continue
            [ -e "$_f" ] 2>/dev/null || continue
            _rel="${_f#$_dir/}"
            case "$_rel" in
                build/*|*/build/*) continue ;;
                vendor/*|*/vendor/*) continue ;;
                rt/runtime.s|*/rt/runtime.s) continue ;;
                tools/*/test/*.ssa|*/tools/*/test/*.ssa) continue ;;
                tools/*/test/fixtures/*.s|*/tools/*/test/fixtures/*.s) continue ;;
                bootstrap/*/tests/fixtures/*.ssa|*/bootstrap/*/tests/fixtures/*.ssa) continue ;;
                tests/integration/external_stub.s|*/tests/integration/external_stub.s) continue ;;
                */lib/rt/*.s|lib/rt/*.s) continue ;;
                bootstrap/*/src/*.ssa|*/bootstrap/*/src/*.ssa|bootstrap/*/stage0/*.ssa|*/bootstrap/*/stage0/*.ssa) continue ;;
                bootstrap/*/proof/*|*/bootstrap/*/proof/*) continue ;;
                bootstrap/tools_chain/*|*/bootstrap/tools_chain/*) continue ;;
                *)
                    _violations="${_violations}source: ${_rel}
"
                    ;;
            esac
        done
        IFS="$_saved_ifs"
    done

    if [ -n "$_violations" ]; then
        echo "$_violations"
        return 1
    fi
    return 0
}

# Use git status only when the directory is itself the top-level root of a repository.
# A non-git directory inside another repository (e.g. build/fresh-bootstrap/tree) must
# use the filesystem scanner so outer-repository ignore rules do not hide stray files.
_toplevel=$(git -C "$TARGET_ROOT" rev-parse --show-toplevel 2>/dev/null || true)
_target_abs=$(cd "$TARGET_ROOT" 2>/dev/null && pwd -P || true)

if [ -n "$_toplevel" ] && [ -n "$_target_abs" ] && [ "$_toplevel" = "$_target_abs" ]; then
    violations=$(check_git_status "$TARGET_ROOT")
else
    violations=$(check_nongit_dir "$TARGET_ROOT")
fi

if [ -n "$violations" ]; then
    fail=1
    echo "[FAIL] clean-tree: found stray build output outside build/:"
    printf '%s\n' "$violations" | sed 's/^/       /'
fi

if [ "$fail" -eq 0 ]; then
    echo "[PASS] clean-tree: repository root and tracked source directories are clean of build artifacts"
fi

exit "$fail"
