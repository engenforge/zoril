# Dependencies

What Zoril needs, and the package names on the distributions it is developed on. Building and running programs need only the first group; building the compiler from source adds the second.

## To compile Zoril programs

- **QBE, release 1.3 or newer.** Earlier releases refuse the long symbols Zoril writes (a symbol carries its module's whole path), and 1.0 lacks the `blit` copy Zoril uses. `make` and `scripts/check_deps.sh` check the version and say so.
- **GNU binutils:** `as` and `ld`.

## To build the compiler from source

- **A C99 compiler** (`gcc`, `clang` or `cproc`), needed only to build the bootstrap seed. With the prebuilt `zoril` and `zilc` binaries of a release, no C compiler is needed (`make SYSTEM_ZORIL=1`).
- **GNU make 4.x** (`make` on Linux, `gmake` on the BSDs).
- **POSIX shell and utilities**, including `awk` and `sed`.
- To run `make test`: `bash` (two of the checks are bash scripts; BusyBox-based systems such as Alpine need `apk add bash`), `flock` and `mkfifo` (in `util-linux` and `coreutils` on Linux). Optional: `lua` 5.3 or newer (the fuzzer and multi-module benchmarks; Lua 5.1 and LuaJIT are skipped as too old), `rustc`, `zig` and `hare` (the comparison benchmarks); they are skipped when absent.
- To build the release archives: `bsdtar` (libarchive).

`./scripts/check_deps.sh build` reports what is missing on your machine.

## Package names

| Distribution   | Compile Zoril programs          | Build the compiler from source                            |
| -------------- | ------------------------------- | --------------------------------------------------------- |
| Alpine         | `apk add qbe binutils`          | `apk add build-base qbe`                                  |
| Debian, Ubuntu | `sudo apt install qbe binutils` | `sudo apt update && sudo apt install build-essential qbe` |
| Arch Linux     | `sudo pacman -S qbe binutils`   | `sudo pacman -S base-devel qbe`                           |

Debian and Ubuntu releases that package QBE 1.0 to 1.2 need a newer QBE, built from <https://c9x.me/compile/>.

## The minimal bootstrap stack

The `minimal` target of `bootstrap/stage0-c/` builds the bootstrap seed with `cproc` (a small C99 compiler targeting QBE), `mcpp` (a standalone C preprocessor; `MINIMAL_CPP="tcc -E"` works instead) and the `musl` C library headers, so that compilation never touches glibc or gcc headers:

| Distribution   | Packages                                                              |
| -------------- | --------------------------------------------------------------------- |
| Alpine         | `apk add cproc mcpp musl-dev qbe binutils make`                       |
| Debian, Ubuntu | `sudo apt install cproc mcpp musl-tools musl-dev qbe binutils make`   |
| Arch Linux     | `sudo pacman -S mcpp musl qbe binutils make` (and `cproc`, see below) |

On Arch Linux `cproc` is not in the official repositories: take it from the AUR, or build it from source (`git clone https://git.sr.ht/~mcf/cproc`, then `./configure && make && sudo make install` in the clone).

Then `make -C bootstrap/stage0-c minimal && make`.

Other distributions: install the same tools under their own package names (QBE may need to be built from source); the package manager's search for `qbe`, `binutils` and `musl` finds them.
