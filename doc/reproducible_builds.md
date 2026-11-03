# Reproducible Builds in Zoril

Zoril provides bit-for-bit reproducible builds for the compiler toolchain, runtime, and compiled user applications.

Given the same pinned backend tools, bootstrapping from source on `x86_64-linux` produces byte-identical binaries regardless of build directory path, locale, timezone, or seed C compiler.

"The same backend tools" includes the C library QBE runs against: QBE writes different, equivalent assembly under glibc and under musl, so the published binaries are reproducible on the release host (Alpine Linux, which uses musl) and are equivalent, not byte-identical, when built on a glibc distribution. [Why the C Library, QBE and the Linker Matter](#why-the-c-library-qbe-and-the-linker-matter) gives the measurements.

## What Is Reproducible

The following artifacts have been verified to reproduce bit-for-bit:

1. **Compiler Frontend (`build/zoril`):** The self-hosted compiler executable.
2. **IL Lowerer (`build/zilc`):** The intermediate representation translator (`ZIL` &rarr; QBE SSA).
3. **Build Driver (`build/zbuild`):** The incremental build engine.
4. **Native Runtime (`build/runtime.o`):** The freestanding native assembly runtime.
5. **Intermediate Representations:** `zoril-stage1.ssa`, `zoril.zil`, `zilc.zil`, `zbuild.zil`.
6. **User Programs:** Compiled programs produce byte-identical objects and binaries whether built via `zbuild` or the manual step-by-step pipeline, and across different working directory paths.

## Required Toolchain Versions

The final ELF binaries depend on the backend code generator and assembler/linker. Reproducing the exact published SHA-256 release hashes requires the same tools, on the same C library:

- **Target Architecture:** `x86_64-linux`
- **QBE:** Commit `c0818978acec60ebb6167fade60fb7012cbf20ca` (Release `v1.3`). Release 1.3 is also the oldest that works at all: 1.0 does not know `blit` and `hlt`, and 1.1 and 1.2 stop at "identifier too long" on a symbol of 80 bytes or more, which a project in a deep directory reaches. `check_deps.sh` refuses an older QBE. QBE has no version flag; `scripts/qbe_fingerprint.sh` identifies a build by what it writes (see below).
- **C library of the host QBE runs on:** musl on the release host. QBE built from the same source against glibc writes different assembly.
- **GNU Binutils:** Version `2.47` (`as` and `ld`) for the hashes measured here. The functional test suite also passes with 2.38 (Ubuntu 22.04's). `ld` 2.45.1 and 2.47 do not produce the same bytes (see below), so the binutils version is part of the pin.

Every release publishes these toolchain pins and tool hashes in a companion `build-info.txt` file next to the archives, including the host, the `binutils` version and package revision, and the `qbe_fingerprint`.

## How to Verify (`make repro-check`)

To check that your local toolchain builds Zoril reproducibly from scratch:

```sh
make repro-check
```

This automated verification target:

1. Creates two clean, isolated build workspaces (`build/repro-check/` and `build/repro-check-second/`) from a clean export of the repository source.
2. Invokes `make all zbuild build/runtime.o` in each, using its clean Makefile.
3. Requires `zoril`, `zilc`, `zbuild` and `runtime.o` to be byte-identical between the two builds, which shows the result does not depend on the directory it is built in.
4. Reports `[PASS]` or `[FAIL]` per artifact and exits with status 0 when the builds agree.

To also compare your build with the binaries of a release, extract the release's binary archive and list its hashes:

```sh
(cd zoril-<version>-linux-x86_64 && sha256sum bin/zoril bin/zilc bin/zbuild lib/zoril/runtime.o) > published.txt
./scripts/repro-check.sh --hashes published.txt
```

That comparison holds only when your host has the release host's C library, QBE, assembler and linker. When it does not, `repro-check` prints `[DIFF]` lines and your host's `binutils` version and QBE fingerprint to compare with the release's `build-info.txt`; the two-build check is the part that applies to every host.

To inspect the rebuilt artifacts without automatic cleanup:

```sh
make repro-check KEEP=1
# or: ./scripts/repro-check.sh --keep
```

The release archives can be verified directly: `SHA256SUMS`, published beside them, lists the archives' own hashes and then `build-info.txt`'s. Check the files you downloaded with `grep <file> SHA256SUMS | sha256sum -c -`, or download all three and run `sha256sum -c SHA256SUMS` (see [Published Release Assets](#published-release-assets)).

## Limits and Verification Matrix

A program built with `--hosted` links the system's libc through `cc`, so it is outside this claim: its bytes depend on the C library and linker found on the build machine. The default build, which links the assembly runtime with no libc, is what the hashes describe.

### The Bootstrap `zilc`

`zilc` lowers the ZIL that `zoril` writes into QBE SSA, so a first `zilc` has to exist before the compiler can rebuild itself. It is built through the frozen stage1 front end (`build/zilc-boot`) and is used only to bootstrap. The binaries in `build/` can come from the bootstrap chain, from a seed or system `zoril` (`ZORIL_SEED`, `SYSTEM_ZORIL=1`), or from a release's binaries copied in. A build that makes `build/zilc` therefore ends by rebuilding `zoril`, `zilc` and `zbuild` with `build/zoril` and `build/zilc` themselves and comparing each with the binary in `build/`. If all three are identical, they already are what the self-hosted tools produce. If some differ because other tools or another host's toolchain made them, the rebuilt tools rebuild all three once more and the two rebuilds must be identical, which shows the toolchain reproduces itself; the self-built binaries then replace the ones that differed. If the two rebuilds differ, the build fails and `build/zbuild` is moved aside, so the next `make` checks again. `make selfhost-confirm` runs the same check on demand, for binaries copied into `build/`, which `make` does not rebuild; it moves nothing aside when it fails.

### The Stage0-C Seed Binary

The initial C compiler seed binary (`zoril-c.release`) is built from C99 source by a host C compiler (GCC, Clang, or cproc). Different C compilers emit different machine code for C, so `zoril-c.release` itself is not identical across C compilers.

However, the seed compiler is merely a bootstrap vehicle: it only compiles the frozen Zoril source in the `stage1` snapshot. Because Zoril code generation and IR emission are fully deterministic, differing seed binaries emit byte-identical `zoril-stage1.ssa`, which assembles into byte-identical `zoril-stage1` binaries.

### Independent Verification Results

Verified against hashes recorded on the same host (Arch Linux, glibc; the four artifacts), using QBE 1.3 and GNU binutils 2.47 on `x86_64-linux`. Each run used `scripts/repro-check.sh`, which exports a clean release tree and builds it from the stage0-C seed:

| Seed C compiler | Work directory                      | Locale    | Timezone           | Result              |
| :-------------- | :---------------------------------- | :-------- | :----------------- | :------------------ |
| GCC 16.2.1      | `build/repro-check` (inside a repo) | default   | default            | 4/4 artifacts match |
| Clang 23.1.1    | an unrelated directory              | default   | default            | 4/4 artifacts match |
| cproc           | a nested directory path             | `C.UTF-8` | `Pacific/Honolulu` | 4/4 artifacts match |

The stage0-C seed binaries differ between C compilers, as expected, but every later stage — `zoril-stage1`, `runtime.o`, `zoril`, `zilc`, and `zbuild` — is byte-identical. Not yet tested: other QBE or binutils versions (expected to change the output), other CPUs and kernels, and different users or filesystems.

## Why the C Library, QBE and the Linker Matter

Zoril's own output is deterministic: building the same source on different hosts gives byte-identical ZIL and QBE SSA. The differences come from the backend tools that turn the SSA into a binary. They were measured by building the same source on Arch Linux (glibc, binutils 2.47) and on Alpine Linux (musl, binutils 2.45.1), with QBE 1.3 built from its release tarball on both.

- **QBE writes different assembly under glibc and musl.** QBE sorts with `qsort` in three places (`spill.c` for spill candidates, `load.c` for inserted instructions, `mem.c` for stack slots) and its comparisons leave equal keys in an unspecified order. glibc and musl order them differently, so which of two equal-cost values gets spilled to the stack differs. The assembly is equivalent and not identical. The C compiler does not matter: GCC at `-O0` to `-O3`, hardened build flags and Clang all gave the same output on glibc, so a distribution's QBE package matches a source build against the same C library. A different glibc version may order ties differently again, which is why the fingerprint below exists.
- **QBE has no version flag, so a build is identified by what it writes.** `scripts/qbe_fingerprint.sh` compiles a few small fixed SSA files and prints a hash of the output; `build-info.txt` records it as `qbe_fingerprint` (and `qbe_known_as` when `scripts/qbe_pins.tsv` lists it). Two QBE builds with the same fingerprint write the same assembly on these inputs.
- **`as` gave the same bytes on binutils 2.45.1 and 2.47** for the files compared. **`ld` did not:** the two versions place the `.note.gnu.property` section differently, and none of the linker options tried (`-z noseparate-code`, `--build-id=none`, `-z norelro`, `-z nognustack`, `--hash-style=sysv`) made them agree. Assembling with `-mx86-used-note=no`, so that the objects carry no such note, did.
- **Making the toolchain independent of the host was possible in testing.** With the three QBE comparisons given a tie-break on a stable key, and the assembler told not to emit that note, a clean build produced identical `zoril`, `zilc`, `zbuild` and `runtime.o` on the two hosts above. Zoril does not ship that today: the QBE and binutils a build uses are the host's own, and the published hashes describe the release host's.

What this means for a user:

- The release archives are built on one fixed host, Alpine Linux, and `build-info.txt` says which. Their hashes are what to check a downloaded archive against.
- A build on another host is as valid as a build of your own and passes the same tests, but its binaries can differ from the release's in bytes while behaving the same. Compare `build-info.txt` with your host (`host_os`, `binutils`, `qbe_fingerprint`) to see why.
- `make repro-check` always checks that two builds on your host agree, which holds on every host. It compares with a published release only on request, and says plainly that a difference is expected when the toolchain differs.

## Version Scheme and Release Hashes

Toolchain binaries (`zoril`, `zilc` and `zbuild`) embed a version string generated at compile time into `build/gen/version.zrl`. The single source of truth for the version string is `scripts/version.sh`.

### Version Format and Sources

The version string is derived in precedence order:

1. **Git Tags (a git checkout):** When `.git` is present and `git` is available, `scripts/version.sh` runs:
   ```sh
   git describe --tags --match 'v[0-9]*' --dirty
   ```
   The leading `v` is stripped (e.g., `v0.1.0-alpha` becomes `0.1.0-alpha`).
   - Tagged commit: `0.1.0-alpha`
   - Commits after tag: `0.1.0-alpha-5-gabc1234`
   - Uncommitted working tree changes append `-dirty`: `0.1.0-alpha-dirty`

2. **Root `VERSION` File (Public Releases & Tarballs):** When building without `.git` (such as in an exported release tree or release tarball), `scripts/version.sh` reads the repository root `VERSION` file (written during release export).

3. **Fallback:** If neither `.git` nor `VERSION` is present, the version string reports `unknown`.

### Effect on Binary Hashes and Reproducibility

Because the version string is compiled into the binary text segments:

- **Git Checkout vs. Release Tree:** A build performed inside a git checkout embeds a git-describe string (or `-dirty` suffix if files are modified), while a release tree or archive embeds the exact release tag string from `VERSION` (e.g. `0.1.0-alpha`). Consequently, checkout builds and release builds of identical source code differ in binary bytes.
- **Published hashes:** The official release hashes are always generated from a clean build of the release tree on the release host, not from a git checkout.
- **`make repro-check`:** `make repro-check` automatically tests against a clean exported tree with the release `VERSION` file, ensuring local verification compares apples to apples against published hashes.
- **Dirty Working Trees:** Any build with uncommitted modifications produces a version string ending in `-dirty` and will never match published release hashes.

## Published Release Assets

Each release publishes:

- **Source Archive:** `zoril-<version>.tar.xz` (`make dist`): the files of the release commit under `zoril-<version>/`, including the committed man pages, so building and installing from it needs no `scdoc`.
- **Binary Archive:** `zoril-<version>-linux-x86_64.tar.xz` (`make dist-bin`): what `make install` installs, under `bin/`, `lib/zoril/` and `share/`. The binaries are static and use no libc, so the archive runs on any x86-64 Linux kernel; it is relocatable (the compiler finds its standard library and runtime relative to itself), so it can be extracted anywhere and its `bin/` put on `PATH`. Compiling a program still needs `qbe`, `as` and `ld`. `make dist-bin` extracts the archive outside the tree and builds hello world with it before keeping it.
- **Archive Hashes:** `build/dist/SHA256SUMS`, written by `make dist` and `make dist-bin`, published beside the archives. It lists each archive, then `build-info.txt`, so a signature on `SHA256SUMS` covers every published file; a rebuild on another host compares the archive lines only. The repository carries no list of the binaries' own hashes, because those depend on the host's toolchain (see above); hash the files in the extracted binary archive instead.
- **Build Info:** `build/dist/build-info.txt`, written by `make dist` and `make dist-bin` beside `build/dist/SHA256SUMS`, describes the tree the archives were built from and the machine that built them: `version`, `commit` (with `-dirty` when tracked files differed), `tree`, `target`, `host_os`, the `as` and `ld` versions and SHA-256 hashes with the `binutils` version and package revision, the QBE version, package revision, commit and hash, and one `archive_sha256` line per archive. It names no local paths. It is listed last in `SHA256SUMS`, which vouches for the published copy, but it describes the build machine, so it is not reproducible: a rebuild elsewhere writes a different one, and `make dist-check` does not compare it. `QBE_VERSION` and `QBE_COMMIT` set the QBE lines for a QBE that was not installed from a package, since QBE has no `--version`.
- **Release Host:** the official archives are built on Alpine Linux: `make dist` and `make dist-bin` print a warning on any other host, and `DIST_REQUIRE_ALPINE=1` makes it an error. The archives built elsewhere are as valid as a build of your own, but `host_os` in `build-info.txt` says where they came from.

### Reproducible Archives (`make dist-check`)

The archives are written by `bsdtar` (libarchive) from an mtree manifest that fixes every entry: sorted order, mode `0755` or `0644`, owner `root` (0), and the release commit's time, in the ustar format, xz-compressed by `bsdtar` itself (liblzma, preset 9, one thread). Nothing about the checkout - umask, file times, owner, directory order - reaches the archive. `make dist-check` builds both archives twice and requires them to be identical.

- **The `.tar` is identical on any host** with `bsdtar`, for the same commit (and, for the binary archive, the same binaries - see above).
- **The `.tar.xz` also depends on the liblzma version,** and the `xz` command compresses the same `.tar` to different bytes than `bsdtar` does, so the published hash is matched by `make dist` on a host with the same liblzma. To check a published archive against a rebuild made elsewhere, compare the uncompressed archives: `xz -dc zoril-<version>.tar.xz | sha256sum`.
- **The source archive is the commit, not the working tree:** `make dist` refuses a tree with uncommitted changes to tracked files.
