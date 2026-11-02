#!/bin/sh
# scripts/check_md_fmt.sh — markdown formatter test (a make test gate).
#
# Runs `dprint check` over the repository's markdown files according to
# .dprint.json. The one canonical style lives in .dprint.json so every
# contributor and AI session formats identically.
#
# Also enforces the table-width rule (scripts/check_md_tables.sh: no table wider than 140 characters) and the
# code-span rule (scripts/check_md_escapes.sh: no backslash-escaped backtick), which do not need dprint.
#
# Skips (rather than fails) when dprint is not installed, so the gate does
# not break environments that legitimately lack it. Run `make md-fmt` to
# reformat.

cd "$(dirname "$0")/.." || exit 2

# The table-width rule needs no formatter, so it runs even where dprint is not installed.
./scripts/check_md_tables.sh --selftest || exit 1
./scripts/check_md_tables.sh || exit 1
./scripts/check_md_escapes.sh --selftest || exit 1
./scripts/check_md_escapes.sh || exit 1

if ! command -v dprint >/dev/null 2>&1; then
    echo "[SKIP] dprint not installed; skipping markdown format check"
    exit 0
fi

out=$(dprint check 2>&1)
rc=$?
if [ $rc -eq 0 ]; then
    echo "[PASS] all markdown formatted"
    exit 0
elif printf '%s\n' "$out" | grep -qiE 'error downloading|failed to download|cannot download|could not download|error resolving plugin|network|dns error|connection refused'; then
    echo "[SKIP] dprint plugin download failed (network unavailable); skipping markdown format check"
    exit 0
else
    # The gate summary shows a failure's first line only, so the file names go on it; without them
    # the summary read "unformatted markdown files found:" followed by the log's path, as if the log
    # were the unformatted file.
    esc=$(printf '\033')
    files=$(printf '%s\n' "$out" | sed "s/${esc}\[[0-9;]*m//g" | sed -n 's|^from \(.*\):$|\1|p' \
        | sed "s|^$PWD/||" | tr '\n' ' ')
    echo "[FAIL] unformatted markdown: ${files:-see the diff below}(run make md-fmt)"
    printf '%s\n' "$out" | head -n 30 | sed 's/^/       /'
    exit 1
fi
