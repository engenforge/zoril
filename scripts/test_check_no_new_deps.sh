#!/bin/sh
# scripts/test_check_no_new_deps.sh — tests for scripts/check_no_new_deps.sh on fixture directories.
# The gate itself runs the check over the files this repository tracks.
set -eu

cd "$(dirname "$0")/.."
CHECK="$(pwd)/scripts/check_no_new_deps.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

errors=0
rc=0
out=""
run() {
    rc=0
    out="$("$CHECK" "$1" 2>&1)" || rc=$?
}
expect() { # expect <name> <expected exit status> <expected output substring or ''>
    if [ "$rc" -ne "$2" ]; then
        echo "[FAIL] $1: exit $rc, expected $2"
        printf '%s\n' "$out" | sed 's/^/       /'
        errors=$((errors + 1))
    elif [ -n "$3" ] && ! printf '%s\n' "$out" | grep -qF -- "$3"; then
        echo "[FAIL] $1: output lacks '$3'"
        printf '%s\n' "$out" | sed 's/^/       /'
        errors=$((errors + 1))
    else
        echo "[PASS] $1"
    fi
}

# 1. The runtimes this tree already depends on pass: shell scripts, a Zoril module, and the fuzz
#    generator's Lua.
mkdir -p "$tmp/ok"
cat > "$tmp/ok/tool.sh" <<'EOF'
#!/bin/sh
echo "[PASS] no-new-deps: nothing to see"
EOF
cat > "$tmp/ok/bash-tool" <<'EOF'
#!/usr/bin/env bash
echo ok
EOF
cat > "$tmp/ok/module.zrl" <<'EOF'
// A Zoril module.
pub fn f() -> i32 { return 0; }
EOF
cat > "$tmp/ok/gen.lua" <<'EOF'
-- The fuzz generator's language is a declared dependency.
return {}
EOF
run "$tmp/ok"
expect "a directory with only declared runtimes passes" 0 "no new runtime among 4 files"

# 2. A .py file fails and is named.
mkdir -p "$tmp/pyfile"
printf 'print("hi")\n' > "$tmp/pyfile/gen.py"
run "$tmp/pyfile"
expect "a .py file fails" 1 "gen.py needs 'Python'"

# 3. A python shebang in a file with no extension fails and is named.
mkdir -p "$tmp/shebang"
printf '#!/usr/bin/env python3\nprint("hi")\n' > "$tmp/shebang/gen"
run "$tmp/shebang"
expect "a python shebang fails" 1 "gen needs 'python3'"

# 4. A `python` interpreter path without `env` fails too.
mkdir -p "$tmp/shebang2"
printf '#!/usr/bin/python3.12\nprint("hi")\n' > "$tmp/shebang2/tool"
run "$tmp/shebang2"
expect "an absolute python shebang fails" 1 "tool needs 'python3.12'"

# 5. The other runtimes the name covers are caught the same way, whatever their spelling.
for pair in "perl#!/usr/bin/perl" "ruby#!/usr/bin/env ruby" "node#!/usr/bin/env node" "php#!/usr/bin/php"; do
    name=${pair%%#!*}
    line=${pair#*#!}
    mkdir -p "$tmp/$name"
    printf '#!/%s\n# tool\n' "$line" > "$tmp/$name/tool"
    run "$tmp/$name"
    expect "a $name shebang fails" 1 "tool needs '$name'"
done

# 6. An interpreted script's extension is a finding even without a shebang.
mkdir -p "$tmp/nested/deep/dir"
printf 'use strict;\n' > "$tmp/nested/deep/dir/late.pl"
run "$tmp/nested"
expect "a nested .pl file fails" 1 "late.pl needs 'Perl'"

# 7. The failure message says what to do instead.
run "$tmp/pyfile"
expect "the failure names the rule" 1 "write dev tools in Zoril"

if [ "$errors" -ne 0 ]; then
    echo "FAIL: $errors case(s) failed."
    exit 1
fi
echo "PASS: check_no_new_deps.sh behaves as specified."
