#!/bin/sh
# scripts/test_export_checks.sh — run the selftest of every export guard present in this tree.
#
# The export guards (`check_export_docs.sh`, `check_export_layout.sh`, `check_export_scripts.sh`,
# `check_export_history.sh`) are private-only: `scripts/export_public_release.sh` does not ship them,
# because each one describes this tree's export layout. This wrapper is what ships instead, so
# `make test` runs the same scenario in both trees. It runs the guards this tree carries and reports `[SKIP]` for the
# ones it does not - in an exported tree that is all of them - so an absent guard is never read as
# a failure. The guards are found by glob, which also keeps `scripts/check_export_scripts.sh` from
# demanding that they ship: it scans the Makefile and scripts/test.sh for script names.
#
# Usage: test_export_checks.sh        exit 0 when every present guard's selftest passes
set -u

cd "$(dirname "$0")/.." || exit 2

rc=0
found=0
for check in scripts/check_export_*.sh; do
    [ -f "$check" ] || continue
    found=$((found + 1))
    sh "$check" --selftest || rc=1
done

if [ "$found" -eq 0 ]; then
    echo "[SKIP] no export guard script is present in this tree (they are private-only)"
fi
exit "$rc"
