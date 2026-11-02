#!/bin/sh
# scripts/test_qbe_fingerprint.sh — qbe_fingerprint.sh names a QBE by its output: stable for one QBE,
# different for a QBE that writes something else, and unknown (exit 1) for one that cannot compile.
cd "$(dirname "$0")/.." || exit 2
fail() { echo "[FAIL] qbe-fingerprint: $1"; exit 1; }
t=$(mktemp -d "${TMPDIR:-/tmp}/zoril_qbefp_XXXXXX")
trap 'rm -rf "$t"' EXIT INT TERM

fixtures=$(ls scripts/qbe_probe/*.ssa 2>/dev/null | wc -l | tr -d ' ')
[ "$fixtures" -ge 3 ] || fail "only $fixtures fixture(s) in scripts/qbe_probe/"

fake() { # fake <name> <text it writes for every input>
    printf '#!/bin/sh\nout=\nwhile [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift 2 ;; -t) shift 2 ;; *) shift ;; esac; done\nprintf "%%s" "%s" > "$out"\n' "$2" > "$t/$1"
    chmod +x "$t/$1"
}
fake qbe_a "alpha"
fake qbe_b "beta"
printf '#!/bin/sh\necho "qbe: broken" >&2\nexit 1\n' > "$t/qbe_bad"; chmod +x "$t/qbe_bad"

a1=$(sh scripts/qbe_fingerprint.sh "$t/qbe_a") || fail "a QBE that compiles gave an error"
a2=$(sh scripts/qbe_fingerprint.sh "$t/qbe_a")
b=$(sh scripts/qbe_fingerprint.sh "$t/qbe_b")
case "$a1" in "qbe_fingerprint: "????????????????????????????????????????????????????????????????) ;; *) fail "not a 64-digit fingerprint line: $a1" ;; esac
[ "$a1" = "$a2" ] || fail "the same QBE gave two fingerprints"
[ "$a1" != "$b" ] || fail "two QBEs that write different assembly share a fingerprint"

out=$(sh scripts/qbe_fingerprint.sh "$t/qbe_bad") && fail "a QBE that cannot compile exited 0"
case "$out" in "qbe_fingerprint: unknown ("*"broken"*) ;; *) fail "no reason for an unusable QBE: $out" ;; esac
out=$(sh scripts/qbe_fingerprint.sh "$t/missing") && fail "a missing QBE exited 0"
case "$out" in "qbe_fingerprint: unknown ("*"not found"*) ;; *) fail "no reason for a missing QBE: $out" ;; esac

v=$(sh scripts/qbe_fingerprint.sh --verbose "$t/qbe_a")
[ "$(printf '%s\n' "$v" | grep -c '\.ssa ')" -eq "$fixtures" ] || fail "--verbose does not list every fixture"

# A tree without the fixtures says so, rather than blaming the QBE.
mkdir -p "$t/bare/scripts/lib" "$t/bare/scripts/qbe_probe"
cp scripts/qbe_fingerprint.sh "$t/bare/scripts/"; cp scripts/lib/portability.sh "$t/bare/scripts/lib/"
out=$(sh "$t/bare/scripts/qbe_fingerprint.sh" "$t/qbe_a") && fail "a tree with no fixtures exited 0"
case "$out" in "qbe_fingerprint: unknown (no fixtures"*) ;; *) fail "no reason for missing fixtures: $out" ;; esac

# The fixtures are in git, not only on disk: *.ssa is ignored elsewhere, and an ignored fixture is missing
# from every clone while this test still passes here.
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    for f in scripts/qbe_probe/*.ssa; do
        if git check-ignore --no-index -q "$f"; then fail "$f is matched by a .gitignore rule, so a fresh clone or an export lacks it"; fi
    done
fi

# Every row of the pins table is a 64-digit fingerprint and a name.
bad=$(grep -v '^#' scripts/qbe_pins.tsv | grep -v -E '^[0-9a-f]{64}	.+' || true)
[ -z "$bad" ] || fail "malformed row in scripts/qbe_pins.tsv: $bad"

echo "[PASS] qbe-fingerprint: stable per QBE, different for different output, unknown for an unusable QBE ($fixtures fixtures)"
