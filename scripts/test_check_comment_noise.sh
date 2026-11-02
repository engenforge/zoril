#!/bin/sh
# scripts/test_check_comment_noise.sh — tests for scripts/check_comment_noise.sh on fixture trees.
# The gate itself runs the check over the real sources; this pins the rules both ways, including
# the three false positives the 2026-10-19 measurement found, so a future "improvement" that
# starts flagging prose fails here first.
set -eu

cd "$(dirname "$0")/.."
CHECK="$(pwd)/scripts/check_comment_noise.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

errors=0
rc=0
out=""

# tree CASE — a fresh fixture tree with src/ ready.
tree() {
    rm -rf "$tmp/$1"
    mkdir -p "$tmp/$1/src"
    printf '%s\n' "$tmp/$1"
}

run() { # run <dir>
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

# 1. Scaffolding: a TODO-first comment is a finding.
d=$(tree todo)
printf '// TODO: teach the parser about this later\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a TODO-first comment fails" 1 "TODO"

# 2. Plain step narration.
d=$(tree step)
printf '// Step 2: lower the operand\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a Step N: comment fails" 1 "step-narration"

# 3. The same narration behind banner decoration is still narration.
d=$(tree step_banner)
printf '// ── Step 2: allocate interval tracking arrays ─────────────────\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a decorated step banner fails" 1 "step-narration"

# 4. Conversational narration.
d=$(tree here_we)
printf '// Here we walk the blocks in reverse.\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a Here we comment fails" 1 "Here we"

# 5. A path the tree does not carry.
d=$(tree gone)
printf '// The reader lives in src/gone.zrl.\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a missing src/ path fails" 1 "src/gone.zrl"

# 6. The same reference, with the file present.
d=$(tree present)
printf '// The reader lives in src/present.zrl.\nfn f() {}\n' > "$d/src/a.zrl"
printf 'fn g() {}\n' > "$d/src/present.zrl"
run "$d"
expect "an existing path passes" 0 "no scaffolding"

# 7. Prose that starts with a keyword is not commented-out code (the 100%-false-positive rule
#    that kept this class out of the gate).
d=$(tree prose)
printf '// for i in 0..len { arr[i] = val } is the loop this lowers to.\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "prose starting with 'for' passes" 0 "no scaffolding"

# 8. A quoted path is an example input, not a reference.
d=$(tree quoted)
printf '// An import of "a/util.zrl" is an ordinary module.\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a double-quoted path passes" 0 "no scaffolding"

# 9. A module-relative reference resolves against the citing file's source root.
d=$(tree relative)
mkdir -p "$d/src/parser"
printf 'fn g() {}\n' > "$d/src/parser/module.zrl"
printf '// Mirrors parser/module.zrl for the interface path.\nfn f() {}\n' > "$d/src/check.zrl"
run "$d"
expect "a module-relative path resolves in src/" 0 "no scaffolding"

# 10. Marker lines a gate reads are never phrase-checked.
d=$(tree markers)
cat > "$d/src/a.zrl" <<'EOF'
// SAFETY: the caller promises p is live.
// exhaustive: every construct is named.
// expected: compile_reject
// --- id:044: write through single pointer dereference ---
fn f() {}
EOF
run "$d"
expect "marker lines pass" 0 "no scaffolding"

# 11. The allowlist covers a hypothetical path, and only that path.
d=$(tree allowed)
printf '// A project module stdlib/mylib.zrl sits under no designated root.\nfn f() {}\n' > "$d/src/parser.zrl"
run "$d"
expect "an allowlisted hypothetical path passes" 0 "no scaffolding"

# 12. A clean tree passes and reports how many files it read.
d=$(tree clean)
printf '// The block list is rebuilt per call; the arena owns it.\nfn f() {}\n' > "$d/src/a.zrl"
printf 'pub fn g() {}\n' > "$d/src/b.zrl"
run "$d"
expect "a clean tree passes" 0 "2 files"

# 13. A path token split across two comment lines is one token: the first line ends in `/`, so
#     the next line's first word completes it and the joined path is checked.
d=$(tree wrapped_gone)
printf '// A note about doc/gone/\n// x.md lives where the reader expects it.\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a path wrapped across two comment lines fails" 1 "doc/gone/x.md"

# 14. The same join, with the file present: a wrapped path that resolves is not a finding.
d=$(tree wrapped_present)
mkdir -p "$d/src/parser"
printf 'fn g() {}\n' > "$d/src/parser/module.zrl"
printf '// The reader lives in src/parser/\n// module.zrl and mirrors the interface.\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a wrapped path that resolves passes" 0 "no scaffolding"

# 15. A private document directory is a finding with no file after it: nothing under doc/tasks,
#     doc/performance, doc/release or doc/archive is ever exported.
d=$(tree private_dir)
printf '// The rule came from a decision (doc/tasks, recorded there).\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a bare private document directory fails" 1 "doc/tasks"

# 16. A bare task record is a finding whatever its prefix.
d=$(tree private_record)
printf '// See future.tm.md for why the walk is finite.\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a bare .tm.md token fails" 1 "future.tm.md"

# 17. The private-document rule does not consult the tree: a file this tree carries is still
#     absent from the export, so pointing at it is the same leak.
d=$(tree private_exists)
mkdir -p "$d/doc/tasks"
printf '# Active\n' > "$d/doc/tasks/active.tm.md"
printf '// The task is recorded in doc/tasks/active.tm.md.\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a private document fails even when the tree carries it" 1 "doc/tasks/active.tm.md"

# 18. A quoted example is not a reference, and the quote that opens it must not become part of the
#     finding. Before 2026-10-19 this failed and named `doc/tasks"`: the rule's boundary character
#     was the opening quote, so the count before the token was even.
d=$(tree quoted_private)
printf '// "doc/tasks" is an example of a name, never a reference.\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a quoted private-document name passes" 0 "no scaffolding"

# 19. Two paths inside one quoted example: the quote count runs from the start of the line, so the
#     second token is inside the quotes too (it used to be counted from zero and reported).
d=$(tree quoted_pair)
printf '// An import of "a/gone.zrl or b/gone.zrl" is a shape, not a file.\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "two paths inside one quoted example pass" 0 "no scaffolding"

# 20. Quoted example, then a real reference on the same line: the finding names the reference and
#     carries no stray quote.
d=$(tree quote_then_bare)
printf '// "x" is the shape; the task is doc/tasks.\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a quoted token then a bare private document fails" 1 "the private document 'doc/tasks', which"

# 21. doc/design and doc/stage0-C are private in every tree like the other four directories, so the
#     private-tree run catches them before the export has to.
d=$(tree private_design)
printf '// The rationale is in doc/design, which the release leaves out.\nfn f() {}\n' > "$d/src/a.zrl"
run "$d"
expect "a bare doc/design directory fails" 1 "doc/design"

if [ "$errors" -ne 0 ]; then
    echo "[FAIL] $errors case(s) failed"
    exit 1
fi
echo "[PASS] check_comment_noise.sh behaves as specified (21 cases)"
