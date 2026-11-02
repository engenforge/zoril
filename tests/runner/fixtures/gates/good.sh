#!/bin/sh
# A well-behaved gate: canonical items, plus detail lines the runner keeps in the log.
echo "checking things..."
echo "[PASS] first check"
echo "[SKIP] second check (not applicable here)"
echo "  an indented detail line, [FAIL] inside it is not a result"
echo "[PASS] third check"
