#!/bin/sh
# scripts/test_man_pages.sh — Verify that man pages build cleanly and do not drift.
#
# Asserts that:
#   0. Every zoril-<module>.3 page is exactly what `tools/zman` generates from a fresh interface
#      plus the module's comments (signatures, fields, visibility and descriptions all match), so
#      a stale page cannot pass. Regenerate with `make man-gen`.
#   1. scdoc compiles every page in doc/man/*.scd without errors or warnings, and every committed
#      roff page (doc/man/<page>.<n>) is what scdoc makes of its source (scripts/man_pages.sh check).
#   2. Tool pages (zoril.1, zilc.1, zbuild.1) document every option in <tool> --help,
#      and do not document nonexistent options.
#   3. zoril-stdlib.7 lists every module in stdlib/ (stdlib/*.zrl and stdlib/*/*.zrl).
#   4. Every stdlib module has a corresponding zoril-<module>.3 page.
#   5. The EXAMPLES sections in zoril(1) and zbuild(1) execute successfully end-to-end.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

COMPILER="${ZORIL_CC:-${ZORIL_BIN:-$REPO_ROOT/build/zoril}}"
case "$COMPILER" in /*) ;; *) COMPILER="$REPO_ROOT/$COMPILER" ;; esac
ZILC="${ZILC_BIN:-$REPO_ROOT/build/zilc}"
case "$ZILC" in /*) ;; *) ZILC="$REPO_ROOT/$ZILC" ;; esac
ZBUILD="${ZBUILD_BIN:-$REPO_ROOT/build/zbuild}"
case "$ZBUILD" in /*) ;; *) ZBUILD="$REPO_ROOT/$ZBUILD" ;; esac
RUNTIME="${RT_HOST:-${TR_RUNTIME:-$REPO_ROOT/build/runtime.o}}"
case "$RUNTIME" in /*) ;; *) RUNTIME="$REPO_ROOT/$RUNTIME" ;; esac
ZMAN="${ZMAN_BIN:-$REPO_ROOT/tools/zman/build/zman}"
case "$ZMAN" in /*) ;; *) ZMAN="$REPO_ROOT/$ZMAN" ;; esac
STDLIB_DIR="$REPO_ROOT/stdlib"
# The module a stdlib file names: its path below stdlib/, with / written as _ (os/unix.zrl is os_unix).
stdlib_module_id() { printf '%s\n' "${1#"$STDLIB_DIR"/}" | sed 's#/#_#g; s#\.zrl$##'; }

MAN_DIR="$REPO_ROOT/doc/man"

if [ ! -d "$MAN_DIR" ]; then
    echo "[FAIL] man-pages: $MAN_DIR directory does not exist"
    exit 1
fi

scd_count=$(find "$MAN_DIR" -name '*.scd' 2>/dev/null | wc -l)
if [ "$scd_count" -eq 0 ]; then
    echo "[FAIL] man-pages: no .scd files found in $MAN_DIR"
    exit 1
fi

TMP_DIR="$(mktemp -d /tmp/zoril_test_man_pages_XXXXXX)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

# 0. Regenerate every stdlib page into TMP_DIR and require doc/man to match byte for byte.
#    zman reads a fresh interface per module, so signatures, fields and visibility cannot drift,
#    and it reads the module's comments, so a description cannot drift either.
if [ ! -x "$ZMAN" ]; then
    if ! ( cd "$REPO_ROOT" && ${MAKE:-make} --no-print-directory tools/zman/build/zman ) \
            > "$TMP_DIR/zman_build.log" 2>&1; then
        echo "[FAIL] man-pages: cannot build $ZMAN"
        cat "$TMP_DIR/zman_build.log"
        exit 1
    fi
fi
mkdir -p "$TMP_DIR/zri" "$TMP_DIR/gen"
for mod_file in $(find "$STDLIB_DIR" -name '*.zrl' | LC_ALL=C sort); do
    mod="$(stdlib_module_id "$mod_file")"
    if ! "$COMPILER" --emit-interface -I "stdlib=$STDLIB_DIR" -o "$TMP_DIR/zri/$mod.zri" "$mod_file" \
            > "$TMP_DIR/zri/$mod.log" 2>&1; then
        echo "[FAIL] man-pages: failed to emit interface for $mod_file"
        cat "$TMP_DIR/zri/$mod.log"
        exit 1
    fi
done
if ! "$ZMAN" --zri "$TMP_DIR/zri" --out "$TMP_DIR/gen" $(find "$STDLIB_DIR" -name '*.zrl' | LC_ALL=C sort) \
        > "$TMP_DIR/zman.log" 2>&1; then
    echo "[FAIL] man-pages: zman could not generate the stdlib pages"
    cat "$TMP_DIR/zman.log"
    exit 1
fi
for generated in "$TMP_DIR/gen"/zoril-*.scd; do
    page="$(basename "$generated")"
    if [ ! -f "$MAN_DIR/$page" ]; then
        echo "[FAIL] man-pages: $MAN_DIR/$page is missing; run make man-gen"
        exit 1
    fi
    if ! diff -u "$MAN_DIR/$page" "$generated" > "$TMP_DIR/$page.diff" 2>&1; then
        echo "[FAIL] man-pages: $MAN_DIR/$page does not match the stdlib it documents; run make man-gen"
        sed -n '1,60p' "$TMP_DIR/$page.diff"
        exit 1
    fi
done

# scdoc is a development tool: a user verifying a build has the committed pages and needs none, and
# `make preflight` requires it, so a stale page cannot be merged.
. "$REPO_ROOT/scripts/lib/scdoc_version.sh"
if ! _found=$(scdoc_found); then
    echo "[SKIP] man-pages: scdoc not found on PATH; page generation checked, the committed roff pages not"
    exit 0
fi
if scdoc_old "$_found"; then
    echo "[SKIP] man-pages: scdoc $_found is older than $SCDOC_MIN; page generation checked, the committed roff pages not"
    exit 0
fi
if ! "$REPO_ROOT/scripts/man_pages.sh" check; then
    exit 1
fi

# 1. Verify scdoc builds every page with no errors or warnings, and check syntax quality
mkdir -p "$TMP_DIR/man_out"
for scd in "$MAN_DIR"/*.scd; do
    [ -f "$scd" ] || continue
    page="$(basename "$scd" .scd)"

    # Check for double semicolons (;;)
    if grep -n ';;' "$scd" > "$TMP_DIR/semi_err.log" 2>&1; then
        echo "[FAIL] man-pages: double semicolon ';;' found in $scd:"
        cat "$TMP_DIR/semi_err.log"
        exit 1
    fi

    # Check for unexpanded placeholder descriptions
    if grep -n -E "Provides [A-Za-z0-9_]+ implementation for|Internal primitive [A-Za-z0-9_]+" "$scd" > "$TMP_DIR/placeholder_err.log" 2>&1; then
        echo "[FAIL] man-pages: placeholder description found in $scd:"
        cat "$TMP_DIR/placeholder_err.log"
        exit 1
    fi

    err_log="$TMP_DIR/scdoc_err_$page.log"
    if ! scdoc < "$scd" > "$TMP_DIR/man_out/$page" 2> "$err_log"; then
        echo "[FAIL] man-pages: scdoc failed on $scd"
        cat "$err_log"
        exit 1
    fi
    if [ -s "$err_log" ]; then
        echo "[FAIL] man-pages: scdoc produced warnings on $scd"
        cat "$err_log"
        exit 1
    fi
done

# 2. Verify tool pages document every CLI option and environment variable from --help
check_tool_options() {
    tool_bin="$1"
    page_file="$MAN_DIR/$2"
    tool_name="$(basename "$tool_bin")"

    if [ ! -f "$tool_bin" ]; then
        echo "[FAIL] man-pages: binary $tool_bin not built"
        exit 1
    fi
    if [ ! -f "$page_file" ]; then
        echo "[FAIL] man-pages: expected $page_file missing"
        exit 1
    fi

    # Extract options from --help
    help_opts="$TMP_DIR/${tool_name}_help_opts.txt"
    "$tool_bin" --help | awk '
        {
            for (i = 1; i <= NF; i++) {
                word = $i
                # Strip trailing punctuation/commas
                sub(/[,|]$/, "", word)
                if (word ~ /^--[a-zA-Z0-9][-a-zA-Z0-9]*/) {
                    match(word, /^--[a-zA-Z0-9][-a-zA-Z0-9]*/)
                    print substr(word, RSTART, RLENGTH)
                } else if (word ~ /^-[a-zA-Z0-9]/ && word !~ /^-[0-9]+$/) {
                    match(word, /^-[a-zA-Z0-9]/)
                    print substr(word, RSTART, RLENGTH)
                }
            }
        }
    ' | sort -u > "$help_opts"

    # Extract options documented in page OPTIONS section
    page_opts="$TMP_DIR/${tool_name}_page_opts.txt"
    awk '
        BEGIN { in_opts = 0 }
        /^# OPTIONS/ { in_opts = 1; next }
        /^# [A-Z]/ && in_opts { in_opts = 0; next }
        in_opts {
            for (i = 1; i <= NF; i++) {
                word = $i
                gsub(/[*_`]/, "", word)
                sub(/[,|]$/, "", word)
                if (word ~ /^--[a-zA-Z0-9][-a-zA-Z0-9]*/) {
                    match(word, /^--[a-zA-Z0-9][-a-zA-Z0-9]*/)
                    print substr(word, RSTART, RLENGTH)
                } else if (word ~ /^-[a-zA-Z0-9]/ && word !~ /^-[0-9]+$/) {
                    match(word, /^-[a-zA-Z0-9]/)
                    print substr(word, RSTART, RLENGTH)
                }
            }
        }
    ' "$page_file" | sort -u > "$page_opts"

    # Every help option must appear in page_opts or somewhere in page_file
    while IFS= read -r opt; do
        [ -n "$opt" ] || continue
        if ! grep -qF -e "$opt" "$page_file"; then
            echo "[FAIL] man-pages: $page_file missing documentation for option $opt (listed in $tool_name --help)"
            exit 1
        fi
    done < "$help_opts"

    # Every option in page OPTIONS section must exist in --help
    while IFS= read -r opt; do
        [ -n "$opt" ] || continue
        if ! grep -qF -e "$opt" "$help_opts"; then
            echo "[FAIL] man-pages: $page_file documents option $opt in OPTIONS, but not in $tool_name --help"
            exit 1
        fi
    done < "$page_opts"

    # Check environment variables if --help or page has an ENVIRONMENT section
    help_env="$TMP_DIR/${tool_name}_help_env.txt"
    "$tool_bin" --help | awk '
        BEGIN { in_env = 0 }
        /^ENVIRONMENT:/ { in_env = 1; next }
        /^[A-Z]+:/ && in_env { in_env = 0; next }
        in_env {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[A-Z][A-Z0-9_]+$/) {
                    print $i
                }
            }
        }
    ' | sort -u > "$help_env"

    page_env="$TMP_DIR/${tool_name}_page_env.txt"
    awk '
        BEGIN { in_env = 0 }
        /^# ENVIRONMENT/ { in_env = 1; next }
        /^# [A-Z]/ && in_env { in_env = 0; next }
        in_env && /^\*[A-Z][A-Z0-9_]+\*$/ {
            name = substr($0, 2, length($0)-2)
            print name
        }
    ' "$page_file" | sort -u > "$page_env"

    # Every help env var must appear in page_env
    while IFS= read -r var; do
        [ -n "$var" ] || continue
        if ! grep -qFx -e "$var" "$page_env"; then
            echo "[FAIL] man-pages: $page_file missing documentation for environment variable $var (listed in $tool_name --help)"
            exit 1
        fi
    done < "$help_env"

    # Every env var in page ENVIRONMENT section must exist in --help
    while IFS= read -r var; do
        [ -n "$var" ] || continue
        if ! grep -qFx -e "$var" "$help_env"; then
            echo "[FAIL] man-pages: $page_file documents environment variable $var in ENVIRONMENT, but not in $tool_name --help"
            exit 1
        fi
    done < "$page_env"
}

check_tool_options "$COMPILER" "zoril.1.scd"
check_tool_options "$ZILC" "zilc.1.scd"
check_tool_options "$ZBUILD" "zbuild.1.scd"

# 3. Verify zoril-stdlib.7 mentions every stdlib module
stdlib_page="$MAN_DIR/zoril-stdlib.7.scd"
if [ ! -f "$stdlib_page" ]; then
    echo "[FAIL] man-pages: $stdlib_page does not exist"
    exit 1
fi

for mod_file in $(find "$STDLIB_DIR" -name '*.zrl' | LC_ALL=C sort); do
    mod="$(stdlib_module_id "$mod_file")"
    if ! grep -qE "(zoril-)?$mod" "$stdlib_page"; then
        echo "[FAIL] man-pages: $stdlib_page omits stdlib module '$mod'"
        exit 1
    fi
done

# 4. Every stdlib module has a page, and every module page belongs to a stdlib module
for mod_file in $(find "$STDLIB_DIR" -name '*.zrl' | LC_ALL=C sort); do
    mod="$(stdlib_module_id "$mod_file")"
    mod_page="$MAN_DIR/zoril-$mod.3.scd"
    if [ ! -f "$mod_page" ]; then
        echo "[FAIL] man-pages: missing man page for module '$mod': $mod_page"
        exit 1
    fi
done

# 5. Run the EXAMPLES in zoril(1) and zbuild(1) end-to-end
EXAMPLES_DIR="$TMP_DIR/examples_run"
mkdir -p "$EXAMPLES_DIR"

# Extract example shell commands from zoril(1) and run them
zoril_examples="$TMP_DIR/zoril_examples.sh"
awk '
    BEGIN { in_examples = 0; in_block = 0 }
    /^# EXAMPLES/ { in_examples = 1; next }
    /^# [A-Z]/ && in_examples { in_examples = 0; next }
    in_examples && /^```/ && !in_block { in_block = 1; next }
    in_examples && /^```/ && in_block { in_block = 0; next }
    in_block { print }
' "$MAN_DIR/zoril.1.scd" > "$zoril_examples"

if [ -s "$zoril_examples" ]; then
    backend="${BACKEND_BIN:-qbe}"
    assembler="${ASSEMBLER_BIN:-as}"
    linker="${LINKER_BIN:-ld}"
    sed "s|/usr/local/lib/zoril/runtime.o|$REPO_ROOT/build/runtime.o|g; s|/usr/local/share/zoril/stdlib|$REPO_ROOT/stdlib|g; s|^qbe |$backend |g; s|^as |$assembler |g; s|^ld |$linker |g" "$zoril_examples" > "$zoril_examples.tmp" && mv "$zoril_examples.tmp" "$zoril_examples"
    (
        set -e
        cd "$EXAMPLES_DIR"
        export PATH="$REPO_ROOT/build:$PATH"
        # Run zoril example script
        sh -e "$zoril_examples"
    ) || {
        echo "[FAIL] man-pages: EXAMPLES in zoril.1.scd failed"
        exit 1
    }
fi

# Extract example shell commands from zbuild(1) and run them
zbuild_examples="$TMP_DIR/zbuild_examples.sh"
awk '
    BEGIN { in_examples = 0; in_block = 0 }
    /^# EXAMPLES/ { in_examples = 1; next }
    /^# [A-Z]/ && in_examples { in_examples = 0; next }
    in_examples && /^```/ && !in_block { in_block = 1; next }
    in_examples && /^```/ && in_block { in_block = 0; next }
    in_block { print }
' "$MAN_DIR/zbuild.1.scd" > "$zbuild_examples"

if [ -s "$zbuild_examples" ]; then
    sed "s|/usr/local/lib/zoril/runtime.o|$REPO_ROOT/build/runtime.o|g; s|/usr/local/share/zoril/stdlib|$REPO_ROOT/stdlib|g; s|zbuild -o|zbuild -I $REPO_ROOT/stdlib --compiler $COMPILER --zilc $ZILC --runtime $RUNTIME -o|g" "$zbuild_examples" > "$zbuild_examples.tmp" && mv "$zbuild_examples.tmp" "$zbuild_examples"
    (
        set -e
        cd "$EXAMPLES_DIR"
        export PATH="$REPO_ROOT/build:$PATH"
        export BACKEND_BIN="${BACKEND_BIN:-qbe}"
        export ASSEMBLER_BIN="${ASSEMBLER_BIN:-as}"
        export LINKER_BIN="${LINKER_BIN:-ld}"
        # Run zbuild example script
        sh -e "$zbuild_examples"
    ) || {
        echo "[FAIL] man-pages: EXAMPLES in zbuild.1.scd failed"
        exit 1
    }
fi

echo "[PASS] man-pages: all pages build cleanly and match tools and stdlib"
exit 0
