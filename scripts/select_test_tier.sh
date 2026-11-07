#!/bin/sh
# scripts/select_test_tier.sh — test tier selector from changed paths.
#
# Reads repository-relative paths from arguments or stdin (one per line).
# Maps paths to gates, groups, scenarios, and test paths using scripts/test_tiers.tsv.
# Applies union semantics across all matched rows: any unlisted path selects
# the default fallback row ('*'), selecting all gates, groups, and scenarios.
#
# Options:
#   --table FILE    use custom tier mapping table (default: scripts/test_tiers.tsv)
#   --print-args    print command-line arguments for scripts/test.sh (default)
#   --tier          print selected tier name(s)
#   --gates         print space-separated list of selected gate names
#   --groups        print space-separated list of selected group names
#   --scenarios     print space-separated list of selected scenario names
#   --paths         print space-separated list of selected test file paths
#   --flags         print space-separated list of selected flags
#   --run           execute scripts/test.sh with computed arguments
#
# Usage:
#   scripts/select_test_tier.sh < path_list
#   scripts/select_test_tier.sh --flags < path_list
#   git diff --name-only <base> | scripts/select_test_tier.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TIERS_TABLE="${TEST_TIERS_TABLE:-scripts/test_tiers.tsv}"
MODE="args"

ALL_GATES="fmt-check md-check no-new-deps binary-sizes no-warnings test-strength fuzz-record fuzz-fresh safety-matrix safety-matrix-zbuild safety-model safety-comments safety-figures comment-noise reborrow-probes exhaustive route-coverage temp-names unsafe-scan runtimes static-image perf-gate toolchain portability clean-tree toolchain-offpath stage0c-fixed-bugs stage0c-unit stage0c-corpus stage0c-docs stage0c-error-locations stage0c-functional stage0c-minimal mutation-self-test"
ALL_GROUPS="language types memory stdlib diagnostics integration"

# Parse command line flags
PATHS_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --table)
            TIERS_TABLE="$2"
            shift 2
            ;;
        --print-args)
            MODE="args"
            shift
            ;;
        --tier)
            MODE="tier"
            shift
            ;;
        --gates)
            MODE="gates"
            shift
            ;;
        --groups)
            MODE="groups"
            shift
            ;;
        --scenarios)
            MODE="scenarios"
            shift
            ;;
        --paths)
            MODE="paths"
            shift
            ;;
        --flags)
            MODE="flags"
            shift
            ;;
        --run)
            MODE="run"
            shift
            ;;
        -h|--help)
            sed -n '2,/^[^#]/ { /^[^#]/d; s/^# \{0,1\}//; p; }' "$0"
            exit 0
            ;;
        -*)
            echo "select_test_tier.sh: unknown option $1" >&2
            exit 2
            ;;
        *)
            PATHS_ARG="$PATHS_ARG $1"
            shift
            ;;
    esac
done

if [ ! -f "$TIERS_TABLE" ]; then
    echo "select_test_tier.sh: tier table '$TIERS_TABLE' not found" >&2
    exit 2
fi

# Collect input paths from arguments or stdin
INPUT_PATHS=""
if [ -n "$PATHS_ARG" ]; then
    INPUT_PATHS="$PATHS_ARG"
else
    # Read non-empty lines from stdin
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            ""|"#"*) continue ;;
            *) INPUT_PATHS="$INPUT_PATHS $_line" ;;
        esac
    done
fi

# Trim leading/trailing whitespace
INPUT_PATHS=$(printf '%s\n' "$INPUT_PATHS" | tr '\t\r\n' ' ' | sed 's/^ *//; s/ *$//')

# If no paths were given at all, default to full run (outside git checkout / unknown tree)
if [ -z "$INPUT_PATHS" ]; then
    INPUT_PATHS="__EMPTY_INPUT_RUN_ALL__"
fi

# Sets to accumulate (space-separated lists)
SEL_GATES=""
SEL_GROUPS=""
SEL_SCENARIOS=""
SEL_PATHS=""
SEL_FLAGS=""
SEL_TIERS=""
ALL_RUN=0

# Helper to check if a word is in a list
has_word() {
    _w="$1"; _lst="$2"
    for _item in $_lst; do
        if [ "$_item" = "$_w" ]; then return 0; fi
    done
    return 1
}

# Helper to check if a gate is in exclude_gates list (gate:reason tokens)
is_excluded_gate() {
    _g="$1"; _ex_list="$2"
    for _ex in $_ex_list; do
        _ex_name="${_ex%%:*}"
        if [ "$_ex_name" = "$_g" ]; then return 0; fi
    done
    return 1
}

# Helper to check if a path matches a pattern
path_matches() {
    _p="$1"; _pat="$2"
    case "$_pat" in
        \*) return 0 ;;
        *"/*")
            _pdir="${_pat%/*}"
            case "$_p" in
                "$_pdir"/*) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        */*)
            _pdir="${_pat%/*}"
            _pfile="${_pat##*/}"
            case "$_p" in
                "$_pdir"/*/*) return 1 ;;
                "$_pdir"/*)
                    _fname="${_p##*/}"
                    case "$_fname" in
                        $_pfile) return 0 ;;
                        *) return 1 ;;
                    esac
                    ;;
                *) return 1 ;;
            esac
            ;;
        *)
            case "$_p" in
                */*) return 1 ;;
                $_pat) return 0 ;;
                *) return 1 ;;
            esac
            ;;
    esac
}

# Helper to check if a path is a runnable test file
is_test_file() {
    _tp="$1"
    case "$_tp" in
        tests/*.zrl|tests/*/*.zrl|tests/*/*/*.zrl|tests/*/*/*/*.zrl)
            case "$_tp" in
                *_lib.zrl) return 1 ;;
                */include/*|*/helpers/*|*/lib/*|*/incremental/*|*/modular/*|*/zilc/*|*/fixtures/*|*/runner/*|*/layout/*|*/ffi_export/*|*/ffi_callback/*|*/fmt/*|*/hosted/*|*/platform_layer/*|*/zbuild_link/*)
                    return 1 ;;
                *) return 0 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

# Process each input path
for path in $INPUT_PATHS; do
    if [ "$path" = "__EMPTY_INPUT_RUN_ALL__" ]; then
        ALL_RUN=1
        SEL_TIERS="$SEL_TIERS all"
        SEL_FLAGS="$SEL_FLAGS compiled"
        break
    fi

    # Clean path (strip leading ./ if present)
    case "$path" in
        ./*) path="${path#./}" ;;
    esac

    path_matched=0

    # Read table and match non-fallback rows
    # Columns: pattern tier gates exclude_gates groups exclude_groups scenarios exclude_scenarios flags description
    while IFS="	" read -r t_pat t_tier t_gates t_ex_gates t_groups t_ex_groups t_scen t_ex_scen t_flags t_desc || [ -n "$t_pat" ]; do
        case "$t_pat" in
            ""|"#"*) continue ;;
            \*) continue ;; # Handle fallback separately
        esac

        match=0
        if path_matches "$path" "$t_pat"; then match=1; fi

        if [ "$match" -eq 1 ]; then
            path_matched=1
            has_word "$t_tier" "$SEL_TIERS" || SEL_TIERS="$SEL_TIERS $t_tier"

            # Add flags
            for fl in $t_flags; do
                if [ "$fl" != "-" ] && ! has_word "$fl" "$SEL_FLAGS"; then
                    SEL_FLAGS="$SEL_FLAGS $fl"
                fi
            done

            # Accumulate gates
            if [ "$t_gates" = "ALL" ]; then
                for g in $ALL_GATES; do
                    if ! is_excluded_gate "$g" "$t_ex_gates"; then
                        has_word "$g" "$SEL_GATES" || SEL_GATES="$SEL_GATES $g"
                    fi
                done
            elif [ "$t_gates" != "-" ]; then
                for g in $t_gates; do
                    has_word "$g" "$SEL_GATES" || SEL_GATES="$SEL_GATES $g"
                done
            fi

            # Accumulate groups
            if [ "$t_groups" = "ALL" ]; then
                for gr in $ALL_GROUPS; do
                    if ! is_excluded_gate "$gr" "$t_ex_groups"; then
                        has_word "$gr" "$SEL_GROUPS" || SEL_GROUPS="$SEL_GROUPS $gr"
                    fi
                done
            elif [ "$t_groups" != "-" ]; then
                for gr in $t_groups; do
                    has_word "$gr" "$SEL_GROUPS" || SEL_GROUPS="$SEL_GROUPS $gr"
                done
            fi

            # Accumulate scenarios
            if [ "$t_scen" = "ALL" ]; then
                # Flag to run all scenarios of selected groups
                for gr in $ALL_GROUPS; do
                    has_word "$gr" "$SEL_GROUPS" || SEL_GROUPS="$SEL_GROUPS $gr"
                done
            elif [ "$t_scen" != "-" ]; then
                for sc in $t_scen; do
                    has_word "$sc" "$SEL_SCENARIOS" || SEL_SCENARIOS="$SEL_SCENARIOS $sc"
                done
            fi

            # If core_infra was matched, mark full run
            if [ "$t_tier" = "core_infra" ]; then
                ALL_RUN=1
            fi
        fi
    done < "$TIERS_TABLE"

    # If this path matched no non-fallback row, match fallback row '*'
    if [ "$path_matched" -eq 0 ]; then
        fallback_found=0
        while IFS="	" read -r t_pat t_tier t_gates t_ex_gates t_groups t_ex_groups t_scen t_ex_scen t_flags t_desc || [ -n "$t_pat" ]; do
            case "$t_pat" in
                \*)
                    fallback_found=1
                    has_word "$t_tier" "$SEL_TIERS" || SEL_TIERS="$SEL_TIERS $t_tier"
                    for fl in $t_flags; do
                        [ "$fl" != "-" ] && ! has_word "$fl" "$SEL_FLAGS" && SEL_FLAGS="$SEL_FLAGS $fl"
                    done
                    ALL_RUN=1
                    ;;
            esac
        done < "$TIERS_TABLE"

        # If no fallback row existed in the table, the unlisted path remains unmatched
        if [ "$fallback_found" -eq 0 ]; then
            # Table has no fallback rule; nothing selected for this path
            true
        fi
    fi

    # If the path is a runnable test file, record it in SEL_PATHS
    if is_test_file "$path"; then
        has_word "$path" "$SEL_PATHS" || SEL_PATHS="$SEL_PATHS $path"
    fi
done

# If all gates and all groups are selected, mark full run
if [ "$ALL_RUN" -eq 1 ]; then
    SEL_GATES="$ALL_GATES"
    SEL_GROUPS="$ALL_GROUPS"
    has_word "compiled" "$SEL_FLAGS" || SEL_FLAGS="$SEL_FLAGS compiled"
    has_word "all" "$SEL_TIERS" || SEL_TIERS="all $SEL_TIERS"
fi

# Sort and deduplicate outputs
sort_words() {
    printf '%s\n' $1 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ *$//'
}

SEL_GATES=$(sort_words "$SEL_GATES")
SEL_GROUPS=$(sort_words "$SEL_GROUPS")
SEL_SCENARIOS=$(sort_words "$SEL_SCENARIOS")
SEL_PATHS=$(sort_words "$SEL_PATHS")
SEL_FLAGS=$(sort_words "$SEL_FLAGS")
SEL_TIERS=$(sort_words "$SEL_TIERS")

# Produce output according to requested mode
case "$MODE" in
    tier)
        echo "$SEL_TIERS"
        exit 0
        ;;
    gates)
        echo "$SEL_GATES"
        exit 0
        ;;
    groups)
        echo "$SEL_GROUPS"
        exit 0
        ;;
    scenarios)
        echo "$SEL_SCENARIOS"
        exit 0
        ;;
    paths)
        echo "$SEL_PATHS"
        exit 0
        ;;
    flags)
        echo "$SEL_FLAGS"
        exit 0
        ;;
    args)
        # If nothing was selected (e.g. table without fallback and unlisted path)
        if [ -z "$SEL_GATES" ] && [ -z "$SEL_GROUPS" ] && [ -z "$SEL_PATHS" ]; then
            exit 1
        fi

        # If full run is selected (all gates and all groups)
        if [ "$ALL_RUN" -eq 1 ] || { [ "$SEL_GATES" = "$ALL_GATES" ] && [ "$SEL_GROUPS" = "$ALL_GROUPS" ]; }; then
            echo "--gates"
            exit 0
        fi

        ARGS=""
        for g in $SEL_GATES; do
            ARGS="$ARGS --gate $g"
        done

        if [ -n "$SEL_GROUPS" ]; then
            for gr in $SEL_GROUPS; do
                ARGS="$ARGS --group $gr"
            done
        elif [ -n "$SEL_PATHS" ]; then
            for tp in $SEL_PATHS; do
                ARGS="$ARGS $tp"
            done
        fi

        printf '%s\n' "$ARGS" | sed 's/^ *//; s/ *$//'
        exit 0
        ;;
    run)
        if [ "$ALL_RUN" -eq 1 ] || { [ "$SEL_GATES" = "$ALL_GATES" ] && [ "$SEL_GROUPS" = "$ALL_GROUPS" ]; }; then
            exec ./scripts/test.sh --gates
        fi

        ARGS=""
        for g in $SEL_GATES; do
            ARGS="$ARGS --gate $g"
        done

        if [ -n "$SEL_GROUPS" ]; then
            for gr in $SEL_GROUPS; do
                ARGS="$ARGS --group $gr"
            done
        elif [ -n "$SEL_PATHS" ]; then
            for tp in $SEL_PATHS; do
                ARGS="$ARGS $tp"
            done
        fi

        # If doc-only tier has scenarios (like md-links) and no groups were selected
        if [ -z "$SEL_GROUPS" ] && [ -n "$SEL_SCENARIOS" ]; then
            # Run test.sh with gates first
            if [ -n "$ARGS" ]; then
                eval "./scripts/test.sh $ARGS" || exit $?
            fi
            # Run standalone scenarios
            for sc in $SEL_SCENARIOS; do
                case "$sc" in
                    md-links) ./scripts/test_check_md_links.sh || exit $? ;;
                    man-pages) ./scripts/test_man_pages.sh || exit $? ;;
                    *) ./scripts/test.sh --group integration || exit $? ;;
                esac
            done
            exit 0
        fi

        eval "exec ./scripts/test.sh $ARGS"
        ;;
esac
