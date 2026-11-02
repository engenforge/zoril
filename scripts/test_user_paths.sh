#!/bin/sh
# scripts/test_user_paths.sh — the commands README gives a user, run against a staged install.
#
# scripts/test_getting_started.sh covers doc/getting_started.md. This covers README's own shell blocks:
#   1. `make install PREFIX=$HOME/.local`, a program built with what it installed, `make uninstall`
#      (nothing is left behind);
#   2. the prebuilt release: the install layout the binary tarball carries (`PREFIX=` relocatable),
#      put on PATH as README says, builds and runs a program, and its man pages are where MANPATH
#      points;
#   3. the system-wide recipe: the three tools linked by symlink into a directory on PATH still find the
#      standard library and the runtime (they look next to their own binary);
#   4. an include directory merely named `stdlib` (a project's own) does not hide the installed
#      standard library.
cd "$(dirname "$0")/.." || exit 2
. scripts/env.sh
WORK=build/user-paths
rm -rf "$WORK"
mkdir -p "$WORK"
ROOT=$(pwd)
fail() { echo "[FAIL] user-paths: $1"; [ -n "${2:-}" ] && sed 's/^/       /' "$2"; exit 1; }
start=$(date +%s)

hello() { # hello DIR -> writes DIR/hello.zrl
    mkdir -p "$1"
    cat > "$1/hello.zrl" << 'EOF'
import "io.zrl";
use io::println;
fn main() -> i32 {
    println("Hello, World!");
    return 0;
}
EOF
}
builds_and_runs() { # builds_and_runs LABEL DIR -- uses zbuild and zoril from PATH
    ( cd "$2" && zbuild -o hello hello.zrl > build.log 2>&1 ) || fail "$1: zbuild could not build hello world" "$2/build.log"
    [ "$("$2/hello")" = "Hello, World!" ] || fail "$1: hello world printed something else"
    ( cd "$2" && zoril --emit-zil -o hello.zil hello.zrl > whole.log 2>&1 && zilc hello.zil hello.ssa >> whole.log 2>&1 \
        && "${BACKEND_BIN:-qbe}" -o hello.s hello.ssa >> whole.log 2>&1 && "${ASSEMBLER_BIN:-as}" -o hello.o hello.s >> whole.log 2>&1 \
        && "${LINKER_BIN:-ld}" -o hello2 "$3/lib/zoril/runtime.o" hello.o >> whole.log 2>&1 ) || fail "$1: the manual pipeline failed" "$2/whole.log"
    [ "$("$2/hello2")" = "Hello, World!" ] || fail "$1: the manual pipeline's hello world printed something else"
}

# 1. make install PREFIX=$HOME/.local, then make uninstall.
home="$ROOT/$WORK/home"
mkdir -p "$home"
make install DESTDIR="$ROOT/$WORK/dest1" PREFIX="$home/.local" > "$WORK/install1.log" 2>&1 || fail "make install PREFIX=\$HOME/.local failed" "$WORK/install1.log"
inst="$ROOT/$WORK/dest1$home/.local"
[ -x "$inst/bin/zbuild" ] || fail "make install PREFIX=\$HOME/.local did not install bin/zbuild"
hello "$WORK/h1"
( PATH="$inst/bin:$PATH"; export PATH; builds_and_runs "installed under \$HOME/.local" "$ROOT/$WORK/h1" "$inst" ) || exit 1
make uninstall DESTDIR="$ROOT/$WORK/dest1" PREFIX="$home/.local" > "$WORK/uninstall1.log" 2>&1 || fail "make uninstall failed" "$WORK/uninstall1.log"
left=$(find "$ROOT/$WORK/dest1" -type f | head -n 5)
[ -z "$left" ] || { printf '%s\n' "$left" > "$WORK/left.txt"; fail "make uninstall left files behind" "$WORK/left.txt"; }

# 2. The prebuilt release's layout (what scripts/dist.sh bin archives), put on PATH as README says.
v=0.0.0-test
opt="$ROOT/$WORK/opt/zoril-$v-linux-x86_64"
make install DESTDIR="$opt" PREFIX= > "$WORK/install2.log" 2>&1 || fail "make install PREFIX= (the release layout) failed" "$WORK/install2.log"
hello "$WORK/h2"
( PATH="$opt/bin:$PATH"; MANPATH="$opt/share/man:${MANPATH:-}"; export PATH MANPATH
  [ "$(zoril --version | head -n 1 | cut -d' ' -f1)" = zoril ] || fail "zoril --version from the release layout"
  builds_and_runs "the release layout on PATH" "$ROOT/$WORK/h2" "$opt" ) || exit 1
[ -f "$opt/share/man/man1/zbuild.1" ] || fail "the release layout has no share/man/man1/zbuild.1 where MANPATH points"

# 3. The system-wide recipe: tools symlinked into a directory on PATH.
mkdir -p "$WORK/links"
for t in zoril zilc zbuild; do ln -s "$opt/bin/$t" "$WORK/links/$t"; done
hello "$WORK/h3"
( PATH="$ROOT/$WORK/links:$PATH"; export PATH; builds_and_runs "the tools symlinked into a PATH directory" "$ROOT/$WORK/h3" "$opt" ) || exit 1

# 4. A directory named stdlib that is a project's, not the standard library.
mkdir -p "$WORK/h4/stdlib"
printf 'pub fn answer() -> i32 { return 42; }\n' > "$WORK/h4/stdlib/answer.zrl"
cat > "$WORK/h4/main.zrl" << 'EOF'
import "io.zrl";
import "answer.zrl";
use io::println;
fn main() -> i32 {
    println("ok");
    return answer::answer() - 42;
}
EOF
( cd "$WORK/h4" && "$opt/bin/zbuild" -I stdlib -o prog main.zrl > build.log 2>&1 ) || fail "a project directory named stdlib hid the installed standard library (zbuild)" "$WORK/h4/build.log"
[ "$("$WORK/h4/prog")" = ok ] || fail "the program built beside a project 'stdlib' directory printed something else"
( cd "$WORK/h4" && "$opt/bin/zoril" -I stdlib --emit-zil -o prog.zil main.zrl > whole.log 2>&1 ) || fail "a project directory named stdlib hid the installed standard library (zoril)" "$WORK/h4/whole.log"
echo "[PASS] user-paths: README's install, release-layout, symlink and stdlib-named-directory recipes work against a staged install in $(( $(date +%s) - start )) s"
