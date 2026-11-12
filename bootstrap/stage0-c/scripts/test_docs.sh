#!/bin/sh
# scripts/test_docs.sh
#
# Extracts code blocks from Markdown files and tests them with zoril.
# Supports ```zoril for surface language and ```zil for IL.
# Skips blocks marked with 'no-test'.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZORIL_BIN="${ZORIL_BIN:-$REPO_ROOT/build/zoril-c}"

if [ ! -f "$ZORIL_BIN" ]; then
    echo "Error: $ZORIL_BIN not found. Build the project first."
    exit 1
fi

FAILURES=0
TOTAL=0

# Timeouts
TIMEOUT_DUR="${TIMEOUT_DUR:-10s}"
KILL_DUR="${KILL_DUR:-2s}"
SIGXCPU_EXIT=152
TIMEOUT_FOREGROUND="${TIMEOUT_FOREGROUND:-$(command -v timeout >/dev/null 2>&1 && timeout --foreground 0 true 2>/dev/null && echo --foreground || true)}"
run_timed() {
    if command -v timeout >/dev/null 2>&1; then
        timeout $TIMEOUT_FOREGROUND -k "$KILL_DUR" "$TIMEOUT_DUR" "$@"
    else
        "$@"
    fi
}
is_timeout_exit() { [ "$1" -eq 124 ] || [ "$1" -eq 137 ] || [ "$1" -eq "$SIGXCPU_EXIT" ]; }

test_file() {
    file="$1"
    if [ "${QUIET:-0}" -ne 1 ]; then
        echo "Testing documentation file: $file"
    fi
    
    # Temporary files for extraction
    block_file=$(mktemp)
    
    in_block=0
    lang=""
    do_wrap=0
    line_num=0
    block_start_line=0

    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))

        case "$line" in
            '```'*)
                tag="${line#\`\`\`}"
                if [ "$in_block" -eq 0 ]; then
                    # Entering a block
                    case "$tag" in
                        zoril*|zil*)
                            case "$tag" in
                                *no-test*)
                                    in_block=2 # In a block but skipping
                                    ;;
                                *)
                                    in_block=1
                                    case "$tag" in
                                        zil*) lang="zil" ;;
                                        *) lang="zoril" ;;
                                    esac
                                    do_wrap=0
                                    case "$tag" in
                                        *wrap*) do_wrap=1 ;;
                                    esac
                                    block_start_line=$line_num
                                    : > "$block_file"
                                    ;;
                            esac
                            ;;
                    esac
                else
                    # Leaving a block
                    if [ "$in_block" -eq 1 ]; then
                        # Process the block
                        TOTAL=$((TOTAL + 1))

                        ext="zrl"
                        cmd_args="--verify"
                        if [ "$lang" = "zil" ]; then
                            ext="zil"
                            cmd_args="--verify --il"
                        else
                            cmd_args="--verify --surface"
                        fi

                        tmp_src=$(mktemp "/tmp/doc_test_XXXXXX")
                        mv "$tmp_src" "$tmp_src.$ext"
                        tmp_src="$tmp_src.$ext"
                        if [ "$do_wrap" -eq 1 ]; then
                            { printf 'fn _doc_test() {\n'; cat "$block_file"; printf '}\n'; } > "$tmp_src"
                        else
                            cp "$block_file" "$tmp_src"
                        fi
                        
                        res=0
                        run_timed "$ZORIL_BIN" $cmd_args "$tmp_src" > /dev/null 2>&1 || res=$?
                        
                        if [ "$res" -eq 0 ]; then
                            if [ "${QUIET:-0}" -ne 1 ]; then
                                echo "[PASS] $file:$block_start_line ($lang)"
                            fi
                        else
                            if is_timeout_exit "$res"; then
                                echo "[FAIL] $file:$block_start_line ($lang) (TIMEOUT)"
                            else
                                echo "[FAIL] $file:$block_start_line ($lang)"
                            fi
                            FAILURES=$((FAILURES + 1))
                            # Print the error message on failure (non-timed run to see output)
                            "$ZORIL_BIN" $cmd_args "$tmp_src" || true
                        fi
                        rm -f "$tmp_src"
                    fi
                    in_block=0
                fi
                continue
                ;;
        esac
        
        if [ "$in_block" -eq 1 ]; then
            echo "$line" >> "$block_file"
        fi
    done < "$file"
    
    rm -f "$block_file"
}

for arg in "$@"; do
    if [ -f "$arg" ]; then
        test_file "$arg"
    else
        echo "Warning: File not found: $arg"
    fi
done

if [ "$FAILURES" -eq 0 ]; then
    echo "test_docs: $TOTAL/$TOTAL passed"
else
    echo "test_docs: $((TOTAL - FAILURES))/$TOTAL passed"
fi
[ "$FAILURES" -eq 0 ]
