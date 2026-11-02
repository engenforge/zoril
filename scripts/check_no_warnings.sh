#!/bin/sh
# scripts/check_no_warnings.sh — our own code compiles without a warning (a make test gate).
#
# Lints (wildcard-arm), unreachable match arms and unused #[must_use] results warn rather than
# fail a compile, so without this they would creep back into the compiler, its tools and the
# stdlib unnoticed. The compiler, zilc and zbuild are compiled whole; each stdlib module with
# -c, so that every function in it is lowered, not only the ones the tools call.
cd "$(dirname "$0")/.." || exit 2
ZORIL=${ZORIL_CC:-./build/zoril}
OUT=build/no_warnings
mkdir -p "$OUT"
status=0
check() {  # check NAME ARGS...: one compile, [PASS] if it printed no warning
    name=$1; shift
    if ! "$ZORIL" "$@" -o "$OUT/out.zil" > "$OUT/log" 2>&1; then
        echo "[FAIL] $name: compilation failed"
        cat "$OUT/log" | sed 's/^/       /'
        status=1
        return
    fi
    if grep -q ": warning: " "$OUT/log"; then
        echo "[FAIL] $name: $(grep -c ': warning: ' "$OUT/log") warning(s)"
        grep ": warning: " "$OUT/log" | sed 's/^/       /'
        status=1
    else
        echo "[PASS] $name"
    fi
}
check src/main.zrl -I stdlib=stdlib -I src -I tools/zilc/src -I build/gen src/main.zrl
check tools/zilc -I stdlib=stdlib -I src -I tools/zilc/src -I build/gen tools/zilc/src/main.zrl
check tools/zbuild -I stdlib=stdlib -I src -I tools/zbuild/src -I build/gen tools/zbuild/src/main.zrl
for f in stdlib/*.zrl stdlib/*/*.zrl; do
    check "$f" -I stdlib=stdlib -c "$f"
done
exit $status
