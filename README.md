![Zoril Banner](media/logo/logo-banner.png)

# Zoril

> [!NOTE]
> This is an early alpha stage compiler (`v0.1.0-alpha`). Although extensive testing and safety verification have been conducted, bugs likely exist. In addition, there may be breaking changes to the language, standard library, and ABI prior to the `v1.0.0` release. See [Stability Statement](doc/STABILITY.md) and [Known Issues](KNOWN_ISSUES.md).

**Zoril** (Zero Overhead Regional Inference Language) is a small, self-hosted systems programming language inspired by Rust that rejects many memory errors at compile time and traps known bounds errors at run time; [What Zoril Checks](doc/SAFETY.md) lists what is checked and what is left to the programmer. This repository holds the self-hosted Zoril compiler (written in Zoril) and its standard library.

The compiler provides robust checking for known issues, tracking ownership, moves, borrows, stack regions and arenas at compile time (a two-level ZIR/ZIL verification pipeline) and emitting runtime traps for known bounds errors it cannot prove. What is checked in checked code, what is checked only at run time, and what is the programmer's job is stated tier by tier in [What Zoril Checks](doc/SAFETY.md); the checks and the tests behind them are in [Safety Model](doc/spec/safety_model.md), and the stability policy is in [Stability Statement](doc/STABILITY.md).

See [Tour of Zoril](doc/tour.md) and [Getting Started](doc/getting_started.md).

## Why Zoril?

Systems languages and their toolchains make different, well-reasoned trade-offs. Rust and Zig, built on LLVM, offer broad language features, mature ecosystems, and highly optimized code. Small toolchains such as [cproc](https://sr.ht/~mcf/cproc/) and [Hare](https://harelang.org/), built on [QBE](https://c9x.me/compile/), show how much a compact, understandable compiler can do.

Zoril is an early experiment in a combination that has not been explored much: compile-time ownership tracking and mandatory bounds checking, in a small compiler (~42k lines of Zoril, not counting comment lines). It is an alpha-stage project, not a replacement for any of these languages, and it builds directly on their work: QBE is its backend, cproc is the reference point for its performance measurements and one way to build its bootstrap compiler, and its ownership model and syntax borrow heavily from Rust.

### Key Highlights

- **Small toolchain:** `zoril`, `zilc` and the `qbe` backend are about **1.5 MB** of stripped binaries, built from ~42k lines of Zoril and ~15k lines of C (QBE). See [Zero Overhead](doc/zero_overhead.md).
- **Memory safety checks in every build:** array and slice bounds are checked at run time (exit 134); ownership, moves, borrows, stack regions and arenas are checked at compile time; no check is compiled out. Each claim is backed by probes in the [78-row safety matrix](doc/spec/safety_model.md). No row is marked **GAP**; the open holes are listed as known gaps in [What Zoril Checks](doc/SAFETY.md), which also says what is checked, what is checked at run time and what is left to the programmer.
- **Fuzzed:** the release bar of 2,638,155 generated programs compiled and ran with no fault on the previous code, and a shorter session of 755,772 programs did the same on this code, each built whole-program and with `zbuild`; a full release-bar run on this code is planned. See [bench/fuzz/README.md](bench/fuzz/README.md).
- **No lifetime annotations:** ownership without lifetime parameters in signatures, using arenas and analysis of function bodies. See [Why Zoril](doc/vision/why_zoril.md).
- **No C runtime dependency:** executables link a small assembly runtime that makes Linux system calls directly: no libc and no dynamic linker.
- **Compact Native Binaries:** a program that only returns is **~10 KB** (**~8.5 KB** stripped), the getting-started hello world **~20 KB** (**~14 KB** stripped), and through `zbuild` **~32 KB** (**~23 KB** stripped). They are static Linux x86-64 ELF files.
- **Low abstraction overhead:** checked code runs at **1.05x (geometric mean)** of equivalent C compiled with cproc on the same backend. See [Zero Overhead](doc/zero_overhead.md).
- **Incremental rebuilds:** `zbuild` rebuilds in **12 ms** after a touch and **26 ms** after an edit on the 2,931-LOC benchmark project (AMD Ryzen 7 3700X). See [Language Comparison](doc/language/language_comparison.md).
- **Familiar to Rust developers:** `let`, `fn`, `match`, `struct`, `enum`, `impl` and `trait` follow Rust's syntax.

For more on Zoril's design goals and how it relates to Rust, Zig, Hare, and earlier research languages, see [Why Zoril](doc/vision/why_zoril.md).

## Example Code

Zoril aims to provide robust checking for known memory-safety issues and expressive types without lifetime parameter annotations; [What Zoril Checks](doc/SAFETY.md) states what it checks today and what it leaves to the programmer.

### Comparing Zoril and Rust: Fibonacci Sequence Generator

Here is a function that computes Fibonacci numbers directly into a caller-provided buffer and returns a view struct:

The Rust version is shown for comparison: Rust's lifetime annotations let it check this code from signatures alone, across separately compiled crates, which Zoril does not attempt.

#### Zoril

```zoril
// Zoril: Native slices and safe borrowing without lifetime syntax
import "core.zrl";

struct FibSequence {
    values: [u64], // Native slice fat-pointer (no lifetime syntax)
}

impl FibSequence {
    pub fn compute(buf: [mut u64]) -> FibSequence {
        let n = buf.len;
        if n > 0 { buf[0] = 0; }
        if n > 1 {
            buf[1] = 1;
            let mut i: usize = 2;
            while i < n {
                buf[i] = buf[i - 1] + buf[i - 2];
                i = i + 1;
            }
        }
        return FibSequence { values: buf };
    }

    pub fn last(self: &FibSequence) -> Option<u64> {
        if self.values.len == 0 { return Option.None; }
        return Option.Some(self.values[self.values.len - 1]);
    }
}
```

#### Rust

```rust
// Rust: Explicit lifetime annotations ('a) required across struct, impl, and method
struct FibSequence<'a> {
    values: &'a [u64], // Explicit lifetime parameter connects struct to source buffer
}

impl<'a> FibSequence<'a> {
    pub fn compute(buf: &'a mut [u64]) -> FibSequence<'a> {
        let n = buf.len();
        if n > 0 { buf[0] = 0; }
        if n > 1 {
            buf[1] = 1;
            let mut i = 2;
            while i < n {
                buf[i] = buf[i - 1] + buf[i - 2];
                i += 1;
            }
        }
        FibSequence { values: buf }
    }

    pub fn last(&self) -> Option<u64> {
        self.values.last().copied()
    }
}
```

### Deterministic Resource Management with `defer`

```zoril
import "io.zrl";
import "os/linux.zrl" as os_linux;
use io::{Error, close, read};
use os_linux::open;

// Reads the start of a file into buf; the descriptor is closed on every return path
fn read_header(path: [u8], buf: [mut u8]) -> Result<u64, Error> {
    let fd = match open(path, 0, 0) {
        Ok(fd) => fd,
        Err(e) => { return Result.Err(e); },
    };
    defer close(fd);

    let n = match read(fd, buf) {
        Ok(n) => n,
        Err(e) => { return Result.Err(e); },
    };
    return Result.Ok(n as u64); // close runs here, and on the Err return above
}
```

## Installing a Prebuilt Release (Linux x86-64)

Each release publishes an installable binary tarball named `zoril-<version>-linux-x86_64.tar.xz` located at `https://get.engenforge.com/zoril/<version>/`: the compiler, `zilc`, `zbuild`, the runtime, the standard library, the documentation and the man pages - what `make install` installs. The binaries are static and use no libc, so the archive runs on any x86-64 Linux distribution, and it is relocatable: the compiler finds its standard library and runtime relative to its own location, so it works wherever it is extracted.

You also need QBE 1.3 or newer and binutils (`as`, `ld`) on your `PATH`; [Dependencies](doc/dependencies.md) has package names.

Set `PREFIX` once; the examples below and in [Getting Started](doc/getting_started.md) use it. `$HOME/.local` installs for you alone; `/usr/local` installs for every user (run the `mkdir` and `tar` lines with `sudo`). Download the archive and the release's `SHA256SUMS`, check one against the other, and extract it into `$PREFIX`, which gives the same layout as `make install` (`bin/`, `lib/zoril/`, `share/`). Extracting needs `xz`, which most systems have, and `$PREFIX/bin` should be on your `PATH`:

```sh
PREFIX=$HOME/.local
v=<version>
curl -LO https://get.engenforge.com/zoril/$v/zoril-$v-linux-x86_64.tar.xz
curl -LO https://get.engenforge.com/zoril/$v/SHA256SUMS
grep linux-x86_64 SHA256SUMS | sha256sum -c -
mkdir -p "$PREFIX"
tar -xJf zoril-$v-linux-x86_64.tar.xz -C "$PREFIX" --strip-components=1
zoril --version
```

The binaries find their standard library and runtime relative to their own location, so the archive also works extracted anywhere else with its `bin/` on your `PATH`. To uninstall, remove the files the archive lists: `tar -tJf zoril-$v-linux-x86_64.tar.xz | sed 's|^[^/]*/||' | grep -v '/$' | (cd "$PREFIX" && xargs rm -f)`.

The same files are mirrored on each release's page at [GitLab](https://gitlab.com/engenforge/zoril/-/releases) and [GitHub](https://github.com/engenforge/zoril/releases); in the commands above, replace `https://get.engenforge.com/zoril/$v/` with `https://gitlab.com/engenforge/zoril/-/releases/v$v/downloads/` or `https://github.com/engenforge/zoril/releases/download/v$v/`.

Then continue with [Getting Started](doc/getting_started.md).

## Getting the Source

The project website is [git.engenforge.com/zoril](https://git.engenforge.com/zoril), and the primary repository is:

```sh
git clone https://git.engenforge.com/zoril.git
```

The repository is mirrored at `https://gitlab.com/engenforge/zoril.git` and `https://github.com/engenforge/zoril.git`. Each release's source archive is `https://get.engenforge.com/zoril/<version>/zoril-<version>.tar.xz`; the binary archive and the `SHA256SUMS` file are in the same directory. The release archives are byte-reproducible ([Reproducible Builds](doc/reproducible_builds.md)).

Note: the source archives that GitLab and GitHub generate automatically are not the release archives. They are not reproducible and will not match `SHA256SUMS`, so download the release archives from the links above and check them against `SHA256SUMS`.

## Building

Zoril supports two build pathways depending on whether you are bootstrapping from source or using an existing release binary:

### Option 1: Bootstrap from Scratch (Source-Only)

Builds the entire toolchain starting from the C99 bootstrap compiler (`bootstrap/stage0-c`), building the frozen compiler snapshot (`bootstrap/stage1`), and finally compiling the self-hosted compiler to fixpoint.

**Core Dependencies:**

- **C Compiler:** Any C99-compliant compiler (`gcc`, `clang`, or `cproc`) — needed only to compile the initial bootstrap seed
- **GNU Make:** GNU make 4.x (`make` on Linux, `gmake` on the BSDs)
- **QBE:** `qbe` backend compiler, **release 1.3 or newer** (older releases refuse the long symbols Zoril writes; `make` checks this and says so)
- **GNU binutils:** `as` (assembler) and `ld` (linker)
- **POSIX Shell & Utilities:** `awk`, `sed`

You can verify build dependencies on your machine before the first build by running:

```sh
./scripts/check_deps.sh build
```

Package names for these tools on common distributions are in [Dependencies](doc/dependencies.md).

_(Note: Running `make test` additionally requires `bash`, `flock` and `mkfifo` (standard in `util-linux` and `coreutils` on Linux) to coordinate the parallel test runner. Optional tools such as `lua` 5.3 or newer (used for multi-module incremental benchmarks and fuzzers), `rustc`, `zig`, or `hare` are skipped automatically when not installed; see the [Developer Guide](doc/developer_guide.md).)_

**Build Commands:**

```sh
# (Durations measured on a reference 8-core AMD Ryzen 7 3700X; times will vary by system)
make            # builds stage0-c, stage1, build/zoril, zilc, zbuild and the runtimes (~1 min)
make test       # standard verification suite (~3 mins; requires bash, flock and mkfifo)
sudo make install # install toolchain to /usr/local (see Installation below)
```

_(Note: `make test` reports 1 expected skip in the `stage0c-functional` gate (`repro_bootstrap_find_impl.zrl`). This tracks a known edge case in the frozen C99 bootstrap seed documented in [KNOWN_ISSUES.md](KNOWN_ISSUES.md) (Bug #14), where a local variable named `ast` misresolves when importing `ast.zrl`. It has zero impact on the bootstrap process or normal compilation.)_

`build/zoril` is built from `src/` by a two-stage bootstrap: the C compiler in `bootstrap/stage0-c/` builds the frozen compiler snapshot in `bootstrap/stage1/`, which builds `src/`. After that, `build/zoril` rebuilds `src/` itself to fixpoint. See [Getting Started](doc/getting_started.md).

**Minimal Bootstrap Stack (`cproc` + `mcpp` + `musl`):**

Zoril also optionally supports a minimal C bootstrap target (`minimal` in `bootstrap/stage0-c/`) using only:

- **`cproc`:** A small, fast C99 compiler targeting QBE.
- **`mcpp`:** A lightweight, standalone C preprocessor (alternatively `tcc -E` via `MINIMAL_CPP="tcc -E"`).
- **`musl`:** Minimal C standard library headers.

Package names for these tools are in [Dependencies](doc/dependencies.md). To build the bootstrap seed using this minimal toolchain:

```sh
make -C bootstrap/stage0-c minimal
make                                      # builds stage1 and self-hosted zoril using the minimal seed
```

### Option 2: Build Using Release Binaries (Fast Rebuild)

If you have pre-compiled `zoril` and `zilc` binaries - the `bin/` directory of the [prebuilt release](#installing-a-prebuilt-release-linux-x86-64) has both - you can build the self-hosted compiler directly in seconds without needing a C compiler.

**Dependencies:**

- **Pre-built Zoril Binaries:** `zoril` and `zilc` (available in `$PATH` or downloaded locally)
- **GNU Make:** GNU make 4.x (`make` on Linux, `gmake` on the BSDs)
- **QBE:** `qbe` backend compiler
- **GNU binutils:** `as` and `ld`
- _(No C compiler or libc build tools required!)_

**Build Commands:**

```sh
# If zoril and zilc are already installed on your system $PATH:
make SYSTEM_ZORIL=1

# Or point make to a directory containing downloaded seed binaries:
make ZORIL_SEED=/path/to/downloaded

# Or place downloaded binaries into build/ and complete the toolchain build:
mkdir -p build
cp /path/to/downloaded/zoril /path/to/downloaded/zilc build/
make            # builds the runtimes and zbuild with the copied binaries (seconds)
# Note: to rebuild src/ into build/zoril using those copied binaries, touch src/main.zrl first:
#   touch src/main.zrl && make

# The first two end by rebuilding zoril, zilc and zbuild with themselves and checking the results are
# identical; with binaries copied into build/ run that check yourself:
make selfhost-confirm

make test
sudo make install # install toolchain to /usr/local
```

The check builds the three tools with the binaries you have, then again with the tools it just built, and requires the two builds to match. If your binaries were made by another toolchain, the self-built ones replace them.

## Installation

Once the toolchain is built (via either bootstrap or release binaries), install `zoril`, `zilc`, `zbuild`, the runtime objects, and standard library to your system:

```sh
sudo make install
```

After installation, explore the command reference and standard library manual pages:

```sh
man zoril
man zbuild
man zoril-stdlib
```

### Installed Components

| Component          | Target Path               | Description                                                  |
| :----------------- | :------------------------ | :----------------------------------------------------------- |
| **`zoril`**        | `$BINDIR/zoril`           | Self-hosted Zoril compiler frontend                          |
| **`zilc`**         | `$BINDIR/zilc`            | Intermediate representation lowerer (ZIL &rarr; QBE SSA)     |
| **`zbuild`**       | `$BINDIR/zbuild`          | High-performance incremental compilation driver              |
| **`runtime.o`**    | `$LIBDIR/zoril/runtime.o` | Native assembly runtime object                               |
| **`runtime.s`**    | `$LIBDIR/zoril/runtime.s` | Runtime assembly source                                      |
| **`stdlib/*.zrl`** | `$DATADIR/zoril/stdlib/`  | Standard library module sources                              |
| **Documentation**  | `$DOCDIR/`                | Essential user documentation (`$DATADIR/doc/zoril/`)         |
| **Manual pages**   | `$MANDIR/man{1,3,7}/`     | System manual pages (committed; installing needs no `scdoc`) |

### Customizing Paths & Staging

The `Makefile` respects standard directory variables (`PREFIX`, `DESTDIR`, `BINDIR`, `LIBDIR`, `DATADIR`, `DOCDIR`, `MANDIR`):

```sh
# User-local installation (no root privileges required):
make install PREFIX=$HOME/.local

# Distribution packaging (staged installation into a temporary root):
make install DESTDIR=/tmp/pkg-root PREFIX=/usr

# Custom library, binary, documentation, or manual page locations:
make install PREFIX=/usr BINDIR=/usr/bin LIBDIR=/usr/lib64 DOCDIR=/usr/share/doc/zoril MANDIR=/usr/share/man
```

> [!NOTE]
> `zbuild` discovers installed runtime and standard library resources using relative paths from its executable location (`../lib/zoril/runtime.o` and `../share/zoril/stdlib`). If you install into non-standard relative layouts (such as `LIBDIR=/usr/lib64` with `BINDIR=/usr/bin`), specify `--runtime /usr/lib64/zoril/runtime.o` (or `-I` for non-standard stdlib locations) when invoking `zbuild`.

### Uninstallation

To remove all installed binaries, libraries, runtime files, standard library modules, and documentation:

```sh
sudo make uninstall

# Or matching your custom PREFIX:
make uninstall PREFIX=$HOME/.local
```

## Compile pipeline

### Using `zbuild` (Recommended)

`zbuild` automatically discovers the installed runtime and standard library relative to its executable (`exe/../lib/zoril/runtime.o` and `exe/../share/zoril/stdlib`). In standard installation layouts (`$PREFIX/bin`, `$PREFIX/lib/zoril`, `$PREFIX/share/zoril`), no extra path flags are needed:

```sh
zbuild main.zrl -o myprog
```

### Manual Compile Pipeline

A `.zrl` source compiles through these stages:

```text
zoril -I <stdlib>  --emit-zil  ->  zilc  ->  qbe  ->  as  ->  ld  (with runtime.o)
    (Zoril)            ZIL       (ZIL→SSA)  (host)  (host)  (host)
```

1. **Frontend:** `zoril -I $PREFIX/share/zoril/stdlib --emit-zil -o out.zil file.zrl`
2. **IL Lowering:** `zilc out.zil out.ssa`
3. **Backend:** `qbe -o out.s out.ssa`
4. **Assembler:** `as -o out.o out.s`
5. **Linker:** `ld -o myprog $PREFIX/lib/zoril/runtime.o out.o`

`PREFIX` is the directory holding `lib/zoril/` and `share/zoril/`: `/usr/local` after `sudo make install`, or the one you gave `make install PREFIX=...`.

## Repository layout

- `src/` — the self-hosted compiler frontend (`main.zrl`, lexer, parser, AST, ZIR, verification pass, ZIL emitter, formatter).
- `stdlib/` — the Zoril standard library (core primitives, I/O, collections, strings, iterators).
- `tools/` — auxiliary build utilities and compiler tools (`tools/zilc`, `tools/zbuild`).
- `rt/` — minimal assembly runtime (`rt/runtime.s`).
- `bootstrap/` — frozen seed compilers for a source bootstrap: the C99 compiler `bootstrap/stage0-c` (~25k lines of C) and the compiler snapshot `bootstrap/stage1` (~37k lines of Zoril, mostly a copy of `src/` and `stdlib/`). See [`bootstrap/README.md`](bootstrap/README.md).
- `tests/` & `corpus/` — comprehensive test suites and validation programs.
- `bench/` — cross-language benchmarks, performance regression gates, and safety-matrix probes.
- `doc/` — specifications (`doc/spec/`), getting-started guide, tour, stability statement, and zero-overhead claims.
- `media/` — logos and visual assets.

## Testing

- `make test` runs the standard verification suite: compiler unit tests, syntax checks, error-reporting tests, standard library safety assertions, runtime consistency, and the 487-probe safety matrix across 78 rows.
- For developer-specific pre-merge verification (`make preflight`, `make preflight-changed`), mutation testing, toolchain dependency matrix testing (`make deps-matrix`), and reproducible release validation (`make repro-check`), see the [Developer Guide](doc/developer_guide.md).

## Contributing and roadmap

See [Contributing](CONTRIBUTING.md) for how to send changes, the [Developer Guide](doc/developer_guide.md) for contributor workflows and pre-merge gates, and [Roadmap](doc/ROADMAP.md) for planned directions, including how the bootstrap is expected to evolve.

## AI Policy

The Zoril language was developed with significant AI assistance.

AI-assisted contributions are welcome, however contributions should be in small, focused changes.

## License

MIT License. Copyright (c) 2026 Engenforge LLC — see `LICENSE` and `NOTICE`.
