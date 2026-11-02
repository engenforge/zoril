#!/bin/sh
# scripts/test_platform_layer.sh — the FFI sprint's exit criterion: a C platform layer driven from
# Zoril, end to end, in hosted mode.
#
# tests/platform_layer/include/platform.c is a headless stand-in for a native UI toolkit
# (create_window, set_frame_callback, blit_rgba, run, destroy). platform.zrl wraps it in a safe
# Display handle with Drop; app.zrl hands a closure to run(), receives frames, fills an
# RGBA buffer from the monotonic clock and exits cleanly. Checked: the program exits 0, and all the
# `extern` declarations live in platform.zrl, none in the application.
cd "$(dirname "$0")/.." || exit 2
. scripts/env.sh
ZORIL=${ZORIL_BIN:-./build/zoril}
ZILC=${ZILC_BIN:-./build/zilc}
RTH=${RUNTIME_HOSTED_BIN:-./build/runtime_hosted.o}
CC_BIN=${CC:-cc}
dir=build/platform-layer
rm -rf "$dir"
mkdir -p "$dir"
src=tests/platform_layer/include
fail() { echo "[FAIL] platform-layer: $1"; [ -n "$2" ] && sed 's/^/       /' "$2"; exit 1; }

command -v "$CC_BIN" >/dev/null 2>&1 || { echo "[SKIP] platform-layer: no C compiler ($CC_BIN)"; exit 0; }
printf 'int main(void) { return 0; }\n' > "$dir/probe.c"
"$CC_BIN" -o "$dir/probe" "$dir/probe.c" >/dev/null 2>&1 && "$dir/probe" \
    || { echo "[SKIP] platform-layer: $CC_BIN cannot build and run a libc program here"; exit 0; }
[ -f "$RTH" ] || fail "$RTH is missing (make build/runtime_hosted.o)"

"$ZORIL" --hosted -I stdlib=stdlib -I "$src" --emit-zil -o "$dir/app.zil" "$src/app.zrl" > "$dir/zoril.log" 2>&1 \
    || fail "the application does not compile" "$dir/zoril.log"
"$ZILC" "$dir/app.zil" "$dir/app.ssa" > "$dir/zilc.log" 2>&1 || fail "zilc rejects it" "$dir/zilc.log"
"$BACKEND_BIN" -o "$dir/app.s" "$dir/app.ssa" && "$ASSEMBLER_BIN" -o "$dir/app.o" "$dir/app.s" || fail "it does not assemble"
"$CC_BIN" -o "$dir/app" "$dir/app.o" "$RTH" "$src/platform.c" > "$dir/cc.log" 2>&1 || fail "it does not link" "$dir/cc.log"
"$dir/app"; rc=$?
[ "$rc" -eq 0 ] || fail "the application exited $rc (see app.zrl: each status is one check)"

# The boundary is one module: no extern declaration and no unsafe in the application at all (the
# handler is a closure that carries its state), and run() clears the callback before it returns.
if grep -q '^extern fn' "$src/app.zrl"; then fail "app.zrl declares an extern function; it belongs in platform.zrl"; fi
if grep -Eq 'unsafe[[:space:]]*(\{|fn)' "$src/app.zrl"; then fail "app.zrl uses unsafe; the template's point is that the application needs none"; fi
grep -q 'clear_frame_callback(self.win)' "$src/platform.zrl" || fail "platform.zrl's run() does not clear the callback"

echo "[PASS] platform-layer: a headless C platform layer driven from Zoril through a safe Display handle, callbacks with userdata, hosted mode"
