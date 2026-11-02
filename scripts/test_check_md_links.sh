#!/bin/sh
# scripts/test_check_md_links.sh — tests for scripts/check_md_links.sh on a fixture tree.
set -eu

cd "$(dirname "$0")/.."
CHECK="$(pwd)/scripts/check_md_links.sh"
CHECK_SAFETY="$(pwd)/scripts/check_safety_model.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

errors=0
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
run() { rc=0; out="$("$CHECK" "$tmp/tree" 2>&1)" || rc=$?; }

mkdir -p "$tmp/tree/doc/sub" "$tmp/tree/media"
: > "$tmp/tree/media/logo.png"
: > "$tmp/tree/LICENSE"
cat > "$tmp/tree/README.md" << 'EOF'
# Title

[doc](doc/guide.md), [section](doc/guide.md#usage), [here](#title), [web](https://example.com/x.md)
![logo](media/logo.png) [license](LICENSE "the license") [dir](doc/sub/) [angle](<doc/guide.md>)
[mail](mailto:someone@example.com)

[ref]: doc/guide.md

`[code](missing-inline.md)`

```text
[fenced](missing-fenced.md)
```

~~~
[tilde](missing-tilde.md)
~~~
EOF
cat > "$tmp/tree/doc/guide.md" << 'EOF'
Back to the [README](../README.md); see the [sibling](sub/../guide.md).
EOF
run
expect "valid links pass" 0 "[PASS]"

printf '\nA [broken](doc/nope.md) link.\n' >> "$tmp/tree/README.md"
run
expect "broken inline link fails" 1 "README.md:19: doc/nope.md"

printf '[up](../../outside.md)\n' > "$tmp/tree/doc/sub/up.md"
run
expect "link escaping the tree fails" 1 "doc/sub/up.md:1: ../../outside.md"

printf '[gone]: missing-ref.md\n' > "$tmp/tree/doc/sub/up.md"
run
expect "broken reference definition fails" 1 "doc/sub/up.md:1: missing-ref.md"

printf '![img](missing.png)\n' > "$tmp/tree/doc/sub/up.md"
run
expect "broken image fails" 1 "doc/sub/up.md:1: missing.png"

rc=0
out="$("$CHECK" "$tmp/no-such-dir" 2>&1)" || rc=$?
expect "missing tree is a usage error" 2 ""

# ── check_safety_model.sh relative link checking fixtures ─────────────────────
mkdir -p "$tmp/sm"
touch "$tmp/sm/probe.zrl"
cat > "$tmp/sm/safety_fixture.md" << 'EOF'
# Threat Model Fixture

Here is a [valid probe citation](probe.zrl).
EOF

run_sm() { rc=0; out="$("$CHECK_SAFETY" --check-links-only "$@" 2>&1)" || rc=$?; }

run_sm "$tmp/sm/safety_fixture.md" "$tmp/sm"
expect "check_safety_model: valid relative link passes" 0 "[PASS] all relative links in safety_fixture.md resolve"

printf '\nA [missing probe citation](probe_missing.zrl).\n' >> "$tmp/sm/safety_fixture.md"
run_sm "$tmp/sm/safety_fixture.md" "$tmp/sm"
expect "check_safety_model: broken relative link fails with file, line, target" 1 "safety_fixture.md:5: broken relative link: probe_missing.zrl"

printf '[escapes](../../outside.md)\n' > "$tmp/sm/safety_fixture.md"
run_sm "$tmp/sm/safety_fixture.md" "$tmp/sm"
expect "check_safety_model: link escaping root fails" 1 "safety_fixture.md:1: broken relative link: ../../outside.md"

# ── check_safety_model.sh normative sentence tracing fixtures ────────────────
cat > "$tmp/sm/normative_fixture.md" << 'EOF'
# Normative Safety Fixture

Returning a local stack pointer is rejected (probe 05).
EOF

run_sn() { rc=0; out="$("$CHECK_SAFETY" --check-normative-only "$@" 2>&1)" || rc=$?; }

run_sn "$tmp/sm/normative_fixture.md" "$tmp/sm"
expect "check_safety_model: normative sentence with citation passes" 0 "[PASS] all normative safety sentences in normative_fixture.md cite tests (1 checked)"

printf '\nReturning a dangling pointer is rejected at compile time.\n' >> "$tmp/sm/normative_fixture.md"
run_sn "$tmp/sm/normative_fixture.md" "$tmp/sm"
expect "check_safety_model: uncited normative sentence fails with file and line" 1 "normative_fixture.md:5: normative sentence has no test citation: Returning a dangling pointer is rejected at compile time"

[ "$errors" -eq 0 ]
