#!/usr/bin/env bash
# scripts/verify_test_failure.sh
# Verifies that our test infrastructure correctly detects and reports failures.
# This prevents "silent masking" of ASan/UBSan/Valgrind or logic errors.

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
SCRIPTS_DIR="$REPO_ROOT/scripts"
TEST_WRAPPER="$SCRIPTS_DIR/test_wrapper.sh"
TEMP_DIR=$(mktemp -d)

# Use same compiler as the build; fall back to gcc for valgrind
LEAK_CC="${CC:-gcc}"

trap 'rm -rf "$TEMP_DIR"' EXIT

echo "=== Verifying Test Infrastructure Integrity ==="

# 1. Test basic exit code detection
echo "Checking: Basic exit code detection..."
cat << 'EOF' > "$TEMP_DIR/fail.sh"
#!/bin/sh
exit 42
EOF
chmod +x "$TEMP_DIR/fail.sh"

# Capture output and exit code
# We expect the wrapper to return the command's exit code
set +e
OUTPUT=$("$TEST_WRAPPER" "$TEMP_DIR/fail.sh" 2>&1)
EXIT_VAL=$?
set -e

if [ $EXIT_VAL -eq 42 ] && echo "$OUTPUT" | grep -q "FAIL"; then
    echo "  [ OK ] Detected exit code 42"
else
    echo "  [ ERROR ] Failed to detect basic exit code (Got: $EXIT_VAL)!"
    exit 1
fi

# 2. Test Valgrind detection
if command -v valgrind > /dev/null; then
    echo "Checking: Valgrind leak detection..."
    cat << 'EOF' > "$TEMP_DIR/leak.c"
#include <stdlib.h>
int main(void) {
    void* p = malloc(10);
    (void)p; // Leak
    return 0;
}
EOF
    "$LEAK_CC" -Werror -o "$TEMP_DIR/leak" "$TEMP_DIR/leak.c"

    # We use --error-exitcode=1 in our makefiles
    set +e
    "$TEST_WRAPPER" valgrind --leak-check=full --error-exitcode=1 --quiet "$TEMP_DIR/leak" > "$TEMP_DIR/valgrind_out" 2>&1
    RET=$?
    set -e
    if [ $RET -ne 0 ] && grep -q "FAIL" "$TEMP_DIR/valgrind_out"; then
        echo "  [ OK ] Detected Valgrind leak"
    else
        echo "  [ ERROR ] Valgrind leak was masked!"
        exit 1
    fi
fi

echo "=== All Infrastructure Integrity Checks Passed ==="
exit 0
