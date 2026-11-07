#!/bin/sh
# scripts/lib/portability.sh — Portable helpers for zoril tooling and test scripts.
#
# Provides portable alternatives for GNU/Linux-specific utilities:
#   now_ms           - Milliseconds since epoch (date +%s%N / EPOCHREALTIME fallback)
#   sha256_of        - SHA-256 calculation (sha256sum / shasum -a 256 / sha256 -q)
#   sha256_check     - SHA-256 verification (sha256sum -c / shasum -c / sha256 -c)
#   nproc_count      - Number of available CPU cores (nproc / getconf _NPROCESSORS_ONLN)
#   run_with_timeout - Timeout runner that falls back gracefully if timeout is missing
#   git_checkout_usable - Whether DIR is the top of a git checkout with a HEAD (a source tarball is not)

# True when DIR (default: the current directory) is itself the top of a git working tree that has a
# commit. `command -v git` is not the question: git is on the host of a source tarball too, and a
# tarball extracted inside some other checkout would otherwise find that one.
git_checkout_usable() {
    _gcu_dir="$(cd "${1:-.}" 2>/dev/null && pwd -P)" || return 1
    command -v git >/dev/null 2>&1 || return 1
    _gcu_top="$(git -C "$_gcu_dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [ "$(cd "$_gcu_top" 2>/dev/null && pwd -P)" = "$_gcu_dir" ] || return 1
    git -C "$_gcu_dir" rev-parse --verify -q HEAD >/dev/null 2>&1
}

now_ms() {
    case "${EPOCHREALTIME:-}" in
        *[.,]*)
            _us=${EPOCHREALTIME#*[.,]}
            echo $(( ${EPOCHREALTIME%[.,]*} * 1000 + 1${_us%???} - 1000 ))
            ;;
        *)
            _n=$(date +%s%N 2>/dev/null)
            case "$_n" in
                *N*|"") echo $(( $(date +%s) * 1000 )) ;;
                *)      echo $(( _n / 1000000 )) ;;
            esac
            ;;
    esac
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$@"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$@"
    elif command -v sha256 >/dev/null 2>&1; then
        if [ $# -eq 0 ]; then
            printf '%s  -\n' "$(sha256 -q)"
        else
            for _f in "$@"; do
                printf '%s  %s\n' "$(sha256 -q "$_f")" "$_f"
            done
        fi
    else
        echo "sha256_of: error: no sha256 tool found (need sha256sum, shasum, or sha256)" >&2
        return 1
    fi
}

sha256_check() {
    _status_only=0
    _files=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --status|-s) _status_only=1; shift ;;
            -c|--check) shift ;;
            -*) shift ;;
            *) _files="${_files} $1"; shift ;;
        esac
    done

    _check_file_line() {
        _rc=0
        while IFS= read -r _line || [ -n "$_line" ]; do
            [ -z "$_line" ] && continue
            case "$_line" in
                \#*) continue ;;
            esac
            _exp_hash=$(printf '%s' "$_line" | awk '{print $1}')
            _target=$(printf '%s' "$_line" | sed 's/^[^ ]*[ ]*//')
            _target="${_target#\*}"
            [ -n "$_target" ] || continue

            if [ ! -f "$_target" ]; then
                [ "$_status_only" -eq 0 ] && printf '%s: FAILED (file not found)\n' "$_target"
                _rc=1
                continue
            fi

            _act_hash=$(sha256_of "$_target" 2>/dev/null | awk '{print $1}')
            if [ "$_act_hash" = "$_exp_hash" ]; then
                [ "$_status_only" -eq 0 ] && printf '%s: OK\n' "$_target"
            else
                [ "$_status_only" -eq 0 ] && printf '%s: FAILED\n' "$_target"
                _rc=1
            fi
        done
        return "$_rc"
    }

    _global_rc=0
    if [ -z "$_files" ]; then
        _check_file_line || _global_rc=1
    else
        for _f in $_files; do
            if [ "$_f" = "-" ]; then
                _check_file_line || _global_rc=1
            elif [ -f "$_f" ]; then
                _check_file_line < "$_f" || _global_rc=1
            else
                echo "sha256_check: $_f: No such file or directory" >&2
                _global_rc=1
            fi
        done
    fi
    return "$_global_rc"
}

nproc_count() {
    _np_res=$((unset OMP_NUM_THREADS OMP_THREAD_LIMIT; nproc) 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    # Check cgroup root CPU quota where present (Linux cgroup v2 / v1, e.g. podman / docker --cpus).
    # Note: reads root cgroup (/sys/fs/cgroup); nested host cgroups without their own namespace are unread.
    if [ -f /sys/fs/cgroup/cpu.max ]; then
        read -r _cg_quota _cg_period 2>/dev/null < /sys/fs/cgroup/cpu.max || _cg_quota="max"
        if [ "$_cg_quota" != "max" ] && [ -n "${_cg_period:-}" ] && [ "$_cg_period" -gt 0 ] 2>/dev/null; then
            _cg_cpus=$(( _cg_quota / _cg_period ))
            [ "$_cg_cpus" -lt 1 ] && _cg_cpus=1
            if [ "$_cg_cpus" -lt "$_np_res" ]; then
                _np_res=$_cg_cpus
            fi
        fi
    elif [ -f /sys/fs/cgroup/cpu/cpu.cfs_quota_us ] && [ -f /sys/fs/cgroup/cpu/cpu.cfs_period_us ]; then
        _cg_quota=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null || echo -1)
        _cg_period=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us 2>/dev/null || echo 0)
        if [ "$_cg_quota" -gt 0 ] && [ "$_cg_period" -gt 0 ] 2>/dev/null; then
            _cg_cpus=$(( _cg_quota / _cg_period ))
            [ "$_cg_cpus" -lt 1 ] && _cg_cpus=1
            if [ "$_cg_cpus" -lt "$_np_res" ]; then
                _np_res=$_cg_cpus
            fi
        fi
    fi
    printf '%s\n' "$_np_res"
}

_TIMEOUT_HAS_FOREGROUND=""

# run_with_timeout: run command with timeout if available.
#
# Rule for --foreground:
# --foreground is strictly opt-in. Callers that want terminal Ctrl-C to reach
# their child process pass --foreground explicitly (e.g. scripts/build_zrl.sh).
# Callers that time out child processes and want the entire process group
# killed on expiration to prevent orphaned grandchildren (e.g. scripts/lib/test_runner.sh,
# scripts/fuzz_safe.sh, test_check_deps.sh) do NOT pass --foreground.
run_with_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        if [ -z "$_TIMEOUT_HAS_FOREGROUND" ]; then
            if timeout --foreground 0 true >/dev/null 2>&1; then
                _TIMEOUT_HAS_FOREGROUND=1
            else
                _TIMEOUT_HAS_FOREGROUND=0
            fi
        fi
        if [ "${1:-}" = "--foreground" ]; then
            if [ "$_TIMEOUT_HAS_FOREGROUND" -eq 1 ]; then
                timeout "$@"
            else
                shift
                timeout "$@"
            fi
        else
            timeout "$@"
        fi
    else
        if [ -z "${_WARNED_NO_TIMEOUT:-}" ]; then
            echo "no timeout(1): runs are not time-limited" >&2
            _WARNED_NO_TIMEOUT=1
        fi
        # Strip timeout options to execute the command directly
        while [ $# -gt 0 ]; do
            case "$1" in
                --foreground|-v) shift ;;
                -k|-s|--kill-after|--signal) shift 2 ;;
                -*) shift ;;
                *)
                    # The first non-option argument is the timeout duration
                    shift
                    break
                    ;;
            esac
        done
        "$@"
    fi
}

file_perm() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || {
        ls -ld "$1" | awk '{
            m = substr($1, 2);
            u = (substr(m,1,1)=="r"?4:0) + (substr(m,2,1)=="w"?2:0) + (substr(m,3,1)=="x"?1:0);
            g = (substr(m,4,1)=="r"?4:0) + (substr(m,5,1)=="w"?2:0) + (substr(m,6,1)=="x"?1:0);
            o = (substr(m,7,1)=="r"?4:0) + (substr(m,8,1)=="w"?2:0) + (substr(m,9,1)=="x"?1:0);
            printf "%d%d%d\n", u, g, o;
        }'
    }
}
