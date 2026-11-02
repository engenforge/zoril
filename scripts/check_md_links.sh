#!/usr/bin/env bash
# scripts/check_md_links.sh <tree> — fail on relative Markdown links that do not resolve.
#
# Checks inline links, images and reference definitions in every *.md under <tree>:
# each relative target must exist and stay inside <tree>. URLs (scheme:...), pure
# #anchor links and anything in code (fenced blocks, inline code spans) are skipped;
# anchors are not checked. A leading / is taken relative to <tree>, as GitHub does.
#
# The export runs this on the public tree, whose layout differs from the private
# repository's (stage0-C -> bootstrap/stage0-c, ...), so links in exported docs
# can only be checked there. Exit status: 0 all resolve, 1 broken links, 2 usage.

if [ $# -ne 1 ] || [ ! -d "$1" ]; then
    echo "usage: $0 <tree>" >&2
    exit 2
fi
root="$(cd "$1" && pwd -P)"

# Print "<file>\t<line>\t<target>" for every link target outside code.
extract() {
    awk '
        /^ *(```|~~~)/ { in_fence = !in_fence; next }
        in_fence { next }
        {
            line = $0
            gsub(/`[^`]*`/, "", line)
            if (match(line, /^ *\[[^]]+\]:[ \t]+/)) {
                emit(substr(line, RSTART + RLENGTH))
                next
            }
            while (match(line, /\]\([^)]*\)/)) {
                emit(substr(line, RSTART + 2, RLENGTH - 3))
                line = substr(line, RSTART + RLENGTH)
            }
        }
        function emit(t) {
            sub(/^[ \t]+/, "", t)
            if (substr(t, 1, 1) == "<") {
                t = substr(t, 2)
                sub(/>.*/, "", t)
            } else {
                sub(/[ \t].*/, "", t)
            }
            sub(/#.*/, "", t)
            if (t == "" || t ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) return
            printf "%s\t%d\t%s\n", FILENAME, FNR, t
        }
    ' "$@"
}

# resolve <path> — canonical absolute path, or nothing if it does not exist.
resolve() {
    if [ -d "$1" ]; then
        (cd "$1" && pwd -P)
    elif [ -e "$1" ]; then
        printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"
    fi
}

broken=0
tab="$(printf '\t')"
list="$(mktemp)"
trap 'rm -f "$list"' EXIT
(cd "$root" && find . -name .git -prune -o -name '*.md' -type f -print | sed 's|^\./||' | sort) > "$list"

while IFS= read -r md; do
    (cd "$root" && extract "$md")
done < "$list" | {
    while IFS="$tab" read -r file line target; do
        case "$target" in
            /*) path="$root$target" ;;
            *) path="$root/$(dirname "$file")/$target" ;;
        esac
        real="$(resolve "$path")"
        case "$real" in
            "$root" | "$root"/*) ;;
            *)
                echo "[FAIL] $file:$line: $target"
                broken=$((broken + 1))
                ;;
        esac
    done
    if [ "$broken" -eq 0 ]; then
        echo "[PASS] all relative markdown links resolve"
        exit 0
    fi
    echo "$broken broken relative link(s)" >&2
    exit 1
}
