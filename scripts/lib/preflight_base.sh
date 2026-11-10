#!/bin/sh
# scripts/lib/preflight_base.sh — the commit a `make preflight-changed` run compares the tree with.
#
# The mutations of the changed files and the rejection differential both need a base: what the change
# is measured against. Comparing a committed change with HEAD measures nothing, and the gate used to pass
# that way (no upstream, or an upstream that already held the commits): "No mutation targets a changed
# file" and "[SKIP] reject-diff", exit 0. So the base is, in order:
#
#   1. PREFLIGHT_BASE, when set (taken as given, even if nothing differs from it);
#   2. the upstream branch, when HEAD has commits it does not;
#   3. the merge base with a default branch (each remote's HEAD, main or master, origin's first, then
#      the local main or master), when HEAD has commits it does not - the usual feature branch, pushed
#      or not; of several, the merge base nearest HEAD;
#   4. HEAD, when the working tree differs from it (an uncommitted change);
#
# and otherwise there is no change to check, which is an error the caller reports. A base from 2 or 3
# covers the uncommitted part too: `git diff BASE` compares BASE with the working tree.
#
# preflight_base sets PF_BASE (a commit) and PF_BASE_WHY (how it was chosen) and returns 0, or sets
# PF_BASE_ERR and returns 1. It reads only git; run it from inside the repository.

# The refs that may be the default branch, origin's first: each remote's HEAD, main and master, then
# the local main and master. Full names, so a local branch called `hom/main` is not taken for a remote.
_pf_default_candidates() {
    for _pf_r in origin $(git remote 2> /dev/null); do
        git symbolic-ref -q "refs/remotes/$_pf_r/HEAD" 2> /dev/null || true
        for _pf_n in main master; do
            git rev-parse --verify -q "refs/remotes/$_pf_r/$_pf_n" > /dev/null 2>&1 && echo "refs/remotes/$_pf_r/$_pf_n"
        done
    done
    for _pf_n in main master; do
        git rev-parse --verify -q "refs/heads/$_pf_n" > /dev/null 2>&1 && echo "refs/heads/$_pf_n"
    done
    return 0
}

preflight_base() {
    PF_BASE=""
    PF_BASE_WHY=""
    PF_BASE_ERR=""
    if [ -n "${PREFLIGHT_BASE:-}" ]; then
        if ! git rev-parse --verify -q "${PREFLIGHT_BASE}^{commit}" > /dev/null 2>&1; then
            PF_BASE_ERR="PREFLIGHT_BASE=$PREFLIGHT_BASE does not name a commit"
            return 1
        fi
        PF_BASE=$(git rev-parse "${PREFLIGHT_BASE}^{commit}")
        PF_BASE_WHY="PREFLIGHT_BASE=$PREFLIGHT_BASE"
        return 0
    fi
    _pf_head=$(git rev-parse -q --verify HEAD 2> /dev/null) || {
        PF_BASE_ERR="this is not a git checkout with a HEAD commit"
        return 1
    }
    if git rev-parse --verify -q '@{upstream}' > /dev/null 2>&1; then
        _pf_ahead=$(git rev-list --count '@{upstream}..HEAD' 2> /dev/null || echo 0)
        if [ "$_pf_ahead" -gt 0 ]; then
            PF_BASE=$(git rev-parse '@{upstream}')
            PF_BASE_WHY="HEAD against $(git rev-parse --abbrev-ref '@{upstream}') ($_pf_ahead commit(s) ahead)"
            return 0
        fi
    fi
    # A clone's remote need not be called origin, and a remote's default branch can lag a local one
    # that was merged in since: of every candidate's merge base, the nearest to HEAD excludes the
    # most commits that are not this branch's.
    _pf_default=""
    _pf_count=""
    for _pf_b in $(_pf_default_candidates); do
        _pf_mb=$(git merge-base HEAD "$_pf_b" 2> /dev/null || true)
        [ -n "$_pf_mb" ] && [ "$_pf_mb" != "$_pf_head" ] || continue
        _pf_n=$(git rev-list --count "$_pf_mb..HEAD" 2> /dev/null || echo "")
        [ -n "$_pf_n" ] || continue
        if [ -z "$_pf_count" ] || [ "$_pf_n" -lt "$_pf_count" ]; then
            _pf_count=$_pf_n
            _pf_default=$_pf_b
            PF_BASE=$_pf_mb
        fi
    done
    if [ -n "$_pf_default" ]; then
        _pf_default=${_pf_default#refs/heads/}
        _pf_default=${_pf_default#refs/remotes/}
        PF_BASE_WHY="HEAD against its merge base with $_pf_default ($_pf_count commit(s) ahead)"
        return 0
    fi
    if ! git diff --quiet HEAD 2> /dev/null || [ -n "$(git ls-files --others --exclude-standard 2> /dev/null)" ]; then
        PF_BASE=$_pf_head
        PF_BASE_WHY="the working tree against HEAD"
        return 0
    fi
    PF_BASE_ERR="nothing to compare: the working tree equals HEAD, and HEAD has no commit beyond its upstream or a default branch (a remote's HEAD, main or master, or the local main or master); set PREFLIGHT_BASE=<commit> to name the base"
    return 1
}
