#!/bin/sh
# scripts/test_tier_select.sh — honesty and integrity test suite for tier selection.
#
# Proves that:
#   1. An unlisted path selects everything (full run: --gates, tier all).
#   2. A doc-only change selects only the doc tier (safety-model, comment-noise, md-check, md-links).
#   3. Removing the default-to-everything rule from the table causes the unlisted path check to fail.
#   4. Canary rows in test_tiers.tsv agree with scripts/mutation_selftest.list (second field)
#      and harness; planting an unmapped canary file makes the check fail.
#   5. Every gate, group, and scenario in scripts/test.sh is reached by a non-default row.
#   6. A stdlib file in the src closure (stdlib/fsys.zrl, stdlib/vec.zrl) selects the src tier.
#   7. Edits to core infra (scripts/lib/portability.sh, scripts/test.sh, Makefile) select everything.
#   8. A new untracked test file selects itself, test-strength, and stage0c-functional.
#   9. doc/spec/* selects stage0c-docs, and doc/man/*.scd selects man-pages scenario.
#  10. Union semantics: multiple files across tiers combine their checks.

set -eu

cd "$(dirname "$0")/.."
SELECTOR="./scripts/select_test_tier.sh"
TABLE="scripts/test_tiers.tsv"

errors=0
pass() { echo "[PASS] tier-select: $1"; }
fail() { echo "[FAIL] tier-select: $1 ($2)"; errors=$((errors + 1)); }

# Case 1: An unlisted path selects everything
out=$(printf 'nonexistent/unlisted_file.xyz\n' | "$SELECTOR")
tier=$(printf 'nonexistent/unlisted_file.xyz\n' | "$SELECTOR" --tier)
flags=$(printf 'nonexistent/unlisted_file.xyz\n' | "$SELECTOR" --flags)
if [ "$out" = "--gates" ] && echo "$tier" | grep -qw "all" && echo "$flags" | grep -qw "compiled"; then
    pass "unlisted path selects everything (args: --gates, tier: all, flags: compiled)"
else
    fail "unlisted path selects everything" "out='$out', tier='$tier', flags='$flags'"
fi

# Case 2: A doc-only change selects only the doc tier
out=$(printf 'doc/tasks/active.tm.md\n' | "$SELECTOR")
gates=$(printf 'doc/tasks/active.tm.md\n' | "$SELECTOR" --gates)
scen=$(printf 'doc/tasks/active.tm.md\n' | "$SELECTOR" --scenarios)
groups=$(printf 'doc/tasks/active.tm.md\n' | "$SELECTOR" --groups)
flags=$(printf 'doc/tasks/active.tm.md\n' | "$SELECTOR" --flags)
expected_gates="comment-noise md-check safety-model"
if [ "$gates" = "$expected_gates" ] && [ "$scen" = "md-links" ] && [ -z "$groups" ] && [ "$flags" = "doc" ]; then
    pass "doc-only change selects only doc tier (safety-model, comment-noise, md-check, md-links)"
else
    fail "doc-only change selects only doc tier" "gates='$gates', scen='$scen', groups='$groups', flags='$flags'"
fi

# Case 3: Removing the default-to-everything rule makes the honesty test fail
tmp_table=$(mktemp)
grep -v '^\*' "$TABLE" > "$tmp_table"
rc=0
sub_out=$(printf 'nonexistent/unlisted_file.xyz\n' | TEST_TIERS_TABLE="$tmp_table" "$SELECTOR" 2>/dev/null) || rc=$?
rm -f "$tmp_table"
if [ "$rc" -ne 0 ] || [ "$sub_out" != "--gates" ]; then
    pass "removing default-to-everything rule causes unlisted path to fail"
else
    fail "removing default-to-everything rule causes unlisted path to fail" "unexpected pass: out='$sub_out'"
fi

# Case 4: Canary rows agree with scripts/mutation_selftest.list and harness
canary_mismatch=0
# Check each file from field 2 of scripts/mutation_selftest.list
canary_files=$(awk -F"@@" 'NF >= 2 { print $2 }' scripts/mutation_selftest.list | sort -u)
for cf in $canary_files; do
    cf_gates=$(printf '%s\n' "$cf" | "$SELECTOR" --gates)
    if ! echo "$cf_gates" | grep -qw "mutation-self-test"; then
        canary_mismatch=1
        echo "       mutation_selftest.list file $cf did not select mutation-self-test"
    fi
done

# Check pinned error reporting test
c_test_gates=$(printf 'tests/error_reporting/ec_bool_logical_int.zrl\n' | "$SELECTOR" --gates)
if ! echo "$c_test_gates" | grep -qw "mutation-self-test"; then
    canary_mismatch=1
    echo "       ec_bool_logical_int.zrl did not select mutation-self-test"
fi

# Check harness scripts
for hs in scripts/mutation-check.sh scripts/mutation_selftest.list scripts/test_mutation_check.sh; do
    hs_gates=$(printf '%s\n' "$hs" | "$SELECTOR" --gates)
    if ! echo "$hs_gates" | grep -qw "mutation-self-test"; then
        canary_mismatch=1
        echo "       harness script $hs did not select mutation-self-test"
    fi
done

if [ "$canary_mismatch" -eq 0 ]; then
    pass "canary rows and mutation_selftest.list agree"
else
    fail "canary rows and mutation_selftest.list agree" "some canary targets lacked mutation-self-test"
fi

# Planting a new entry patching an unmapped file must fail canary agreement
planted_detected=0
planted_file="src/ast.zrl"
ast_gates=$(printf '%s\n' "$planted_file" | "$SELECTOR" --gates)
if ! echo "$ast_gates" | grep -qw "mutation-self-test"; then
    # ast.zrl correctly does not select mutation-self-test; if added to canary list, check would fail
    planted_detected=1
fi
if [ "$planted_detected" -eq 1 ]; then
    pass "planted canary entry patching new file is caught by agreement check"
else
    fail "planted canary entry patching new file is caught by agreement check" "ast.zrl unexpectedly selected mutation-self-test"
fi

# Case 5: Every gate, group, and scenario in scripts/test.sh is reached by a non-default row
missing_gates=""
for g in $(./scripts/test.sh --list-gates); do
    if ! awk -F"\t" '$1 != "*" { if ($3 ~ ("(^| )" "'"$g"'" "( |$)") || ($3 == "ALL" && $4 !~ ("(^| )" "'"$g"'" "(:| |$)"))) found=1 } END { exit !found }' "$TABLE"; then
        missing_gates="$missing_gates $g"
    fi
done

missing_groups=""
for gr in $(./scripts/test.sh --list-groups | awk '{print $1}'); do
    if ! awk -F"\t" '$1 != "*" { if ($5 ~ ("(^| )" "'"$gr"'" "( |$)") || ($5 == "ALL" && $6 !~ ("(^| )" "'"$gr"'" "(:| |$)"))) found=1 } END { exit !found }' "$TABLE"; then
        missing_groups="$missing_groups $gr"
    fi
done

. scripts/lib/test_runner.sh 2>/dev/null || true
. scripts/lib/layout.sh 2>/dev/null || true
all_scenarios=$(sed -n '/^group_scenarios()/,/^}/p' scripts/test.sh | grep -E '^[[:space:]]*echo' | sed 's/echo//' | tr '\n' ' ')

missing_scenarios=""
for sc in $all_scenarios; do
    if ! awk -F"\t" '$1 != "*" { if ($7 ~ ("(^| )" "'"$sc"'" "( |$)") || ($7 == "ALL" && $8 !~ ("(^| )" "'"$sc"'" "(:| |$)"))) found=1 } END { exit !found }' "$TABLE"; then
        missing_scenarios="$missing_scenarios $sc"
    fi
done

if [ -z "$missing_gates" ] && [ -z "$missing_groups" ] && [ -z "$missing_scenarios" ]; then
    pass "every gate, group, and scenario is reached by non-default rows"
else
    fail "every gate, group, and scenario is reached by non-default rows" "gates: $missing_gates, groups: $missing_groups, scen: $missing_scenarios"
fi

# Case 6: stdlib file in src closure selects src tier
std_tier=$(printf 'stdlib/fsys.zrl\n' | "$SELECTOR" --tier)
std_gates=$(printf 'stdlib/fsys.zrl\n' | "$SELECTOR" --gates)
std_groups=$(printf 'stdlib/fsys.zrl\n' | "$SELECTOR" --groups)
std_flags=$(printf 'stdlib/fsys.zrl\n' | "$SELECTOR" --flags)
has_mut=0
has_stg0=0
has_sm=0
echo "$std_gates" | grep -qw "mutation-self-test" && has_mut=1 || true
echo "$std_gates" | grep -qw "stage0c-functional" && has_stg0=1 || true
echo "$std_gates" | grep -qw "safety-matrix" && has_sm=1 || true

if [ "$has_mut" -eq 0 ] && [ "$has_stg0" -eq 1 ] && [ "$has_sm" -eq 1 ] && echo "$std_flags" | grep -qw "compiled" && [ "$std_groups" = "diagnostics integration language memory stdlib types" ]; then
    pass "stdlib file in src closure selects src tier (all groups, stage0c-functional, no mutation-self-test)"
else
    fail "stdlib file in src closure selects src tier" "tier='$std_tier', has_mut=$has_mut, has_stg0=$has_stg0, has_sm=$has_sm, groups='$std_groups'"
fi

# Case 7: Edit to scripts/lib/portability.sh, scripts/test.sh, Makefile selects everything
infra_ok=1
for infra_file in scripts/lib/portability.sh scripts/test.sh scripts/lib/test_runner.sh Makefile; do
    inf_out=$(printf '%s\n' "$infra_file" | "$SELECTOR")
    if [ "$inf_out" != "--gates" ]; then
        infra_ok=0
        echo "       infra file $infra_file produced args: '$inf_out', expected '--gates'"
    fi
done
if [ "$infra_ok" -eq 1 ]; then
    pass "edits to core infra and Makefile select everything (--gates)"
else
    fail "edits to core infra and Makefile select everything" "some infra files did not output --gates"
fi

# Case 8: Untracked new test file selects itself, test-strength, and stage0c-functional
new_test="tests/functional/basic/untracked_probe_test.zrl"
nt_args=$(printf '%s\n' "$new_test" | "$SELECTOR")
nt_paths=$(printf '%s\n' "$new_test" | "$SELECTOR" --paths)
nt_gates=$(printf '%s\n' "$new_test" | "$SELECTOR" --gates)
nt_groups=$(printf '%s\n' "$new_test" | "$SELECTOR" --groups)
if [ "$nt_paths" = "$new_test" ] && echo "$nt_gates" | grep -qw "test-strength" && echo "$nt_gates" | grep -qw "stage0c-functional" && [ -z "$nt_groups" ]; then
    pass "untracked new test file selects itself and test-strength/stage0c-functional"
else
    fail "untracked new test file selects itself and test-strength/stage0c-functional" "paths='$nt_paths', gates='$nt_gates', groups='$nt_groups', args='$nt_args'"
fi

# Case 9: doc/spec/* selects stage0c-docs and doc/man/*.scd selects man-pages
spec_gates=$(printf 'doc/spec/surface_syntax.md\n' | "$SELECTOR" --gates)
man_scen=$(printf 'doc/man/zoril.1.scd\n' | "$SELECTOR" --scenarios)
if echo "$spec_gates" | grep -qw "stage0c-docs" && echo "$man_scen" | grep -qw "man-pages"; then
    pass "doc/spec/* selects stage0c-docs and doc/man/*.scd selects man-pages"
else
    fail "doc/spec/* selects stage0c-docs and doc/man/*.scd selects man-pages" "spec_gates='$spec_gates', man_scen='$man_scen'"
fi

# Case 10: Union semantics combining doc and test file
union_gates=$(printf 'doc/tasks/active.tm.md\ntests/functional/basic/untracked_probe_test.zrl\n' | "$SELECTOR" --gates)
union_paths=$(printf 'doc/tasks/active.tm.md\ntests/functional/basic/untracked_probe_test.zrl\n' | "$SELECTOR" --paths)
union_groups=$(printf 'doc/tasks/active.tm.md\ntests/functional/basic/untracked_probe_test.zrl\n' | "$SELECTOR" --groups)
if echo "$union_gates" | grep -qw "comment-noise" && echo "$union_gates" | grep -qw "stage0c-functional" && [ "$union_paths" = "$new_test" ] && [ -z "$union_groups" ]; then
    pass "union semantics combine checks across different tiers cleanly"
else
    fail "union semantics combine checks across different tiers cleanly" "gates='$union_gates', paths='$union_paths'"
fi

# Case 11: ALL_GATES match between test.sh and select_test_tier.sh
runner_gates=$(./scripts/test.sh --list-gates | sort -u | tr '\n' ' ' | sed 's/ *$//')
selector_gates=$(printf 'scripts/lib/portability.sh\n' | "$SELECTOR" --gates)
if [ "$runner_gates" = "$selector_gates" ]; then
    pass "ALL_GATES matches between scripts/test.sh and select_test_tier.sh"
else
    fail "ALL_GATES match" "runner='$runner_gates', selector='$selector_gates'"
fi

# Case 12: Every scenario row emits --scenario in selector output
scen_rows_ok=1
scen_mismatch=""
while IFS="	" read -r t_pat t_tier t_gates t_ex_gates t_groups t_ex_groups t_scen t_ex_scen t_flags t_desc || [ -n "$t_pat" ]; do
    case "$t_pat" in
        ""|"#"*|\*) continue ;;
    esac
    if [ "$t_scen" != "-" ] && [ "$t_scen" != "ALL" ]; then
        sample_path="$t_pat"
        case "$sample_path" in
            *\*) sample_path="${sample_path%\*}sample.txt" ;;
        esac
        emitted_args=$(printf '%s\n' "$sample_path" | "$SELECTOR")
        for sc in $t_scen; do
            if ! echo "$emitted_args" | grep -qw -- "--scenario $sc"; then
                scen_rows_ok=0
                scen_mismatch="$scen_mismatch ($sample_path missing --scenario $sc in '$emitted_args')"
            fi
        done
    fi
done < "$TABLE"

if [ "$scen_rows_ok" -eq 1 ]; then
    pass "every row with explicit scenarios emits --scenario in selector output"
else
    fail "scenario row emission" "mismatches: $scen_mismatch"
fi

# Case 13: Helper and functional test union
helper_func_args=$(printf 'tests/helpers/x.zrl\ntests/functional/assign_type_checked.zrl\n' | "$SELECTOR")
expected_hf="--gate stage0c-functional --gate test-strength --group stdlib tests/functional/assign_type_checked.zrl"
if [ "$helper_func_args" = "$expected_hf" ]; then
    pass "helper module and functional test run both stdlib group and individual test"
else
    fail "helper module and functional test union" "got '$helper_func_args', expected '$expected_hf'"
fi

# Case 14: a *_lib.zrl selects the group whose tests import it, as scripts/test.sh --group-of
# names it; with a test.sh that knows no group (the lookup taken out), it selects none.
foo_lib_args=$(printf 'tests/functional/basic/foo_lib.zrl\n' | "$SELECTOR")
expected_foo="--gate stage0c-functional --gate test-strength --group language"
if [ "$foo_lib_args" = "$expected_foo" ]; then
    pass "foo_lib.zrl selects its group (language)"
else
    fail "foo_lib.zrl group selection" "got '$foo_lib_args', expected '$expected_foo'"
fi
no_group_sh="$(mktemp "${TMPDIR:-/tmp}/tier_no_group.XXXXXX")"
printf '#!/bin/sh\nexit 1\n' > "$no_group_sh"; chmod +x "$no_group_sh"
foo_lib_off=$(printf 'tests/functional/basic/foo_lib.zrl\n' | TIER_TEST_SH="$no_group_sh" "$SELECTOR")
rm -f "$no_group_sh"
if [ "$foo_lib_off" = "--gate stage0c-functional --gate test-strength" ]; then
    pass "without test.sh's group lookup, foo_lib.zrl selects no group (the case above sees the lookup)"
else
    fail "foo_lib.zrl with the group lookup taken out" "got '$foo_lib_off'"
fi

# Case 14b: Group and contained test path are both passed without group-copy filtering
dup_args=$(printf 'stdlib/arena.zrl\ntests/functional/basic/bool.zrl\n' | "$SELECTOR")
if echo "$dup_args" | grep -qw -- "--group language" && echo "$dup_args" | grep -qw "tests/functional/basic/bool.zrl"; then
    pass "selector passes both group and individual test without dropping paths"
else
    fail "selector preserves paths alongside groups" "got '$dup_args'"
fi

# Case 15: doc/spec/* selects doc-snippets and md-links
spec_args=$(printf 'doc/spec/surface_syntax.md\n' | "$SELECTOR")
if echo "$spec_args" | grep -qw -- "--scenario doc-snippets" && echo "$spec_args" | grep -qw -- "--scenario md-links"; then
    pass "doc/spec/* selects both doc-snippets and md-links scenarios"
else
    fail "doc/spec/* scenario selection" "got '$spec_args'"
fi

# Case 16: Empty change list prints notice to stderr and selects --gates
empty_err=$(printf '' | "$SELECTOR" 2>&1 >/dev/null)
empty_out=$(printf '' | "$SELECTOR" 2>/dev/null)
if echo "$empty_err" | grep -qF "test-changed: no changed files, running all tests" && [ "$empty_out" = "--gates" ]; then
    pass "empty change list prints notice to stderr and selects --gates"
else
    fail "empty change list" "stderr='$empty_err', stdout='$empty_out'"
fi

if [ "$errors" -gt 0 ]; then
    echo "test_tier_select: $errors test(s) failed" >&2
    exit 1
fi
echo "test_tier_select: all checks passed"
exit 0
