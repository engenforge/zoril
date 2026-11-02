#!/bin/sh
# scripts/check_reborrow_probes.sh — the programs that must NOT compile.
#
# The reborrow rule (a reference handed on as a receiver or an argument reborrows its referent, so
# a view taken through it keeps the referent borrowed) is the compiler's default rule since task
# 2i.11, so `make` and `make test` enforce it on every piece of real code. What no ordinary build
# checks is the negative side: a program that must be *rejected*. Each probe below is compiled and
# must fail; one that compiles is a regression in the rule, not a passing test.
set -u
cd "$(dirname "$0")/.." || exit 2
ZORIL=${ZORIL_CC:-./build/zoril}
OUT=build/reborrow_probes
mkdir -p "$OUT"

TIMEOUT=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT="timeout -k 5s 300s"; fi

status=0
expect_reject() {   # $1 = label, $2 = include flags, $3 = program
    _label=$1; _inc=$2; _prog=$3
    if $TIMEOUT "$ZORIL" $_inc --emit-zil -o /dev/null "$_prog" > "$OUT/probe.log" 2>&1; then
        echo "[FAIL] reborrow-probes: accepted, but must be rejected: $_label"
        echo "       ($_prog)"
        status=1
    else
        echo "[PASS] reborrow-probes: $_label"
    fi
}

expect_reject "a view taken through a reborrowed reference keeps the referent borrowed" \
    "" tests/error_reporting/err_reborrow_projection.zrl


exit $status
