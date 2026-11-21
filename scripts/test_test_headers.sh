#!/bin/sh
# scripts/test_test_headers.sh — the per-file runner reads one header grammar, from the header only.
#
# A directive it does not recognise used to be ignored, so `// expected exit banana` left a test at
# the default (run, expect exit 0) and it could pass for the wrong reason. Each malformed case here
# must fail with the offending line named and each control must pass, so a reader that has gone
# lenient again, or strict about a form the tree uses, fails here.
#
# Usage: scripts/test_test_headers.sh
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || exit 1

DIR=build/test-headers
rm -rf "$DIR"
mkdir -p "$DIR/cases"

errors=0
fail() { echo "[FAIL] $1"; errors=$((errors + 1)); }

# case NAME EXPECTED_LINE_FRAGMENT BODY — BODY is the file's text, printf-escaped.
# The runner's output for the file must contain the fragment.
check() {
    name="$1"; want="$2"; body="$3"
    file="$DIR/cases/$name.zrl"
    printf "$body" > "$file"
    out="$DIR/$name.out"
    TR_WORK="$DIR/work" ./scripts/test.sh --verbose "$file" > "$out" 2>&1
    if grep -Fq -- "$want" "$out"; then
        echo "[PASS] $name: $want"
    else
        fail "$name: expected \`$want\`, got: $(grep -F "$file" "$out" | head -n 1)"
    fi
}

P="$DIR/cases"
MAIN='fn main() -> i32 { return 0; }\n'
MAIN3='fn main() -> i32 { return 3; }\n'

bad() { check "$1" "[FAIL] $P/$1.zrl (malformed header, line $2: $3)" "$4"; }
good() { check "$1" "[PASS] $P/$1.zrl" "$2"; }

bad exit_word 1 '// expected exit banana' "// expected exit banana\n$MAIN"
bad exit_letter 1 '// expected exit 1O' "// expected exit 1O\n$MAIN"
bad exit_range 1 '// expected exit 256' "// expected exit 256\n$MAIN"
bad exit_trailing 1 '// expected exit 3 4' "// expected exit 3 4\n$MAIN"
bad exit_typo 1 '// expected exitt 3' "// expected exitt 3\n$MAIN"
bad expect_nospace 1 '//EXPECT: x' "//EXPECT: x\n$MAIN"
bad flags_nospace 1 '// flags:-O' "// flags:-O\n$MAIN"
bad exit_twice 2 '// expected exit 4' "// expected exit 3\n// expected exit 4\n$MAIN3"
bad exit_and_fail 2 '// expected compile fail' "// expected exit 0\n// expected compile fail\n$MAIN"
bad flags_twice 2 '// flags: -O' "// flags: -O\n// flags: -O\n$MAIN"
bad fail_and_success 2 '// expected compile success' "// expected compile fail\n// expected compile success\n$MAIN"
bad skip_hides_nothing 2 '// expected exit banana' "// @skip: not today\n// expected exit banana\n$MAIN"

# A well-formed header whose text is only in the command line --verbose logs must still fail.
check expect_in_cmdline "[FAIL] $P/expect_in_cmdline.zrl (diagnostic missing)" "// EXPECT: --emit-zil\n$MAIN"

bad expect_and_exit 2 '// expected exit 3' "// EXPECT: x\n// expected exit 3\n$MAIN3"
bad expect_and_success 2 '// expected compile success' "// EXPECT: x\n// expected compile success\n$MAIN"
bad skip_empty 1 '// @skip:' "// @skip:\n$MAIN3"

bad expect_empty 1 '// EXPECT: ' "// EXPECT: \n// expected compile fail\nfn main() -> i32 { return 0 }\n"
bad expect_empty_alone 1 '// EXPECT: ' "// EXPECT: \n$MAIN"
bad directive_after_code 2 '// expected exit 3' "$MAIN3// expected exit 3\n"

good body_comment "// expected exit 0\nfn main() -> i32 {\n    // expected output: none\n    return 0;\n}\n"
good exit_ok "// expected exit 3\n$MAIN3"
good exit_code_ok "// expected exit code: 0\n$MAIN"
good compile_fail_expect "// expected compile fail\n// EXPECT: expected\nfn main() -> i32 { return 0 }\n"
good expect_with_fail "// expected compile fail\n// EXPECT: expected\nfn main() -> i32 { return 0 }\n"
good prose "// expecting a slice\n$MAIN"

# Sibling .stdout fixture checks: exact match passes; mismatch (including trailing bytes) fails.
printf 'ok\n' > "$P/stdout_ok.zrl.stdout"
good stdout_ok "// expected exit 0\nfn main() -> i32 { let s = \"ok\\n\"; unsafe { let _ = @syscall(1, 1, s.ptr as u64, s.len as u64); } return 0; }\n"

printf 'ok\n' > "$P/stdout_mismatch.zrl.stdout"
check stdout_mismatch "[FAIL] $P/stdout_mismatch.zrl (output mismatch)" "// expected exit 0\nfn main() -> i32 { let s = \"ok\\nextra\"; unsafe { let _ = @syscall(1, 1, s.ptr as u64, s.len as u64); } return 0; }\n"

[ "$errors" -eq 0 ] || exit 1
echo "[PASS] test headers: every malformed case failed, every control passed"
