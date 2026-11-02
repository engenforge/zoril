# Zoril Roadmap

This document describes where Zoril is expected to go after `v0.1.0-alpha`. It lists intentions, not commitments: there are no dates, and priorities will change with what users run into. Known problems in the current release are in [Known Issues](../KNOWN_ISSUES.md), and the versioning policy is in the [Stability Statement](STABILITY.md).

## Guiding constraints

Whatever is added should stay true to Zoril's goals:

- **A small compiler.** Small is measured, not felt: the compiler is about 47,000 lines of Zoril, comments included (counted by [What Zoril Checks](SAFETY.md) §5.3), builds from source, the whole bootstrap from the C seed, in about a minute on an 8-core desktop (57-58 s for a plain `make` from a fresh clone on an AMD Ryzen 7 3700X), and `zoril`, `zilc` and `qbe` together are about 1.5 MB of stripped binaries (1,506,024 bytes with the three stripped). Each is roughly an order of magnitude below an LLVM-based toolchain: rustc alone is several hundred thousand lines before LLVM's millions, and an LLVM-based toolchain installs as hundreds of megabytes. A change that moves one of these by a large factor needs a reason.
- Safety checks are never compiled out, and every safety claim stays backed by a probe in the safety matrix.
- Builds stay bit-for-bit reproducible, including from a source bootstrap.
- Dependencies stay minimal: a C compiler (only for the bootstrap), QBE and binutils.

## Release and distribution

- **Binaries for more targets.** Each release publishes `zoril`, `zilc`, `zbuild` and the runtime for `x86_64-linux`; publish them for each target as its port lands.
- **Benchmarks per release.** Run the cross-language benchmarks for every tagged release and publish the results with it.
- **CI across targets.** Run the test gates in public CI, adding operating systems and CPUs as the ports below land.

## Bootstrap

The repository builds from source with only a C compiler (GCC, Clang, or `cproc` with `mcpp` and the `musl` headers; see [Dependencies](dependencies.md) and [Reproducible Builds](reproducible_builds.md)).

- **Moving `bootstrap/` to its own repository.** The seed compilers may move to a separate `zoril-bootstrap` repository, as Zig keeps `zig-bootstrap`: once release binaries are how most people get a toolchain, packagers ask for a small seed repository to pin, or the seeds and the compiler change on different schedules. `make repro-check` would keep covering the source bootstrap.

## Language

- **Foreign function interface.** Linux x86-64 has scalars and raw pointers across `extern` signatures, `extern "C" fn` definitions C can call, a thin C function-pointer type, the C struct layout, `ffi` type aliases, `zbuild` link inputs and a hosted link mode (libc, libm and shared libraries, or static libraries where they exist); the safety boundary is in the [unsafe policy](spec/unsafe_policy.md). Planned, each an addition that breaks no program:
  - structs, slices and references across the boundary;
  - a nullable callback type;
  - a binding generator;
  - callbacks from other threads, once there is a concurrency model.
- **Concurrency.** Message passing in the style of Go channels or Erlang processes, built on the runtime's asynchronous I/O. Zoril has no threads today, and a callback from C must arrive on the thread that called into Zoril. A concurrency model adds rules for new code and may reject some `static mut` uses, which is a known pre-1.0 change.
- **Asynchronous I/O in the surface language.** The intermediate language has an abstract `async_context` type, which the runtime implements with `io_uring`; expose it through language-level intrinsics.
- **First-class arenas.** A safe arena API in which a region is an ordinary value, rather than relying on conventions.
- **Traits.** Allow two traits to declare a method with the same name on one type, with explicit disambiguation.
- **Debug information.** Emit DWARF so that standard debuggers can step through Zoril code.
- **Linear capabilities in the standard library.** The linear descriptor types (`fd<r>`, `fd<w>`, `fd<rw>`) exist for `extern` declarations; the standard library's own file API uses the typed `Fd` handle. Using the linear types in the standard library is left for after 1.0.
- **Research.** Tracking pointer provenance through values stored in aggregates, to prove more accesses safe at compile time and remove the runtime checks they need now.

## Tooling

- **Benchmarks in the language.** First-class benchmark functions and a runner, like Go's `testing.B`.
- **A fuzzer that uses debug information.** Once DWARF is emitted, a fuzzer can report a failure at its source line.
- **Machine-readable diagnostics.** A `--json-errors` flag for editors and tools.

## Portability

Zoril targets only `x86_64-linux` today. Planned targets, in priority order:

1. Operating systems: Linux (every distribution), the BSDs (OpenBSD, FreeBSD, NetBSD), macOS, Windows, Android, iOS.
2. Architectures: x86-64, arm64 (including Apple's M-series), riscv64.

The BSDs are one milestone, reached through the hosted mode (the system C library; OpenBSD permits system calls only from its libc) and tested on each of the three, OpenBSD first as the strictest. macOS and Windows have no stable raw system-call interface, so they run over their C library the same way.

How portability is achieved:

- **The portable standard library is the API a port keeps.** Its modules (`file`, `fsys`, `proc`, `time`, `io`, `args`, `core` and the collections) name nothing Linux-specific; Linux and Unix facts live in `os/linux.zrl` and `os/unix.zrl`. A program that imports only portable modules is meant to recompile unchanged on each target; code that imports `os/linux.zrl` or `os/unix.zrl`, or makes raw system calls, is platform code.
- **Per-target shims under those modules.** System calls move behind per-target runtime shims, so that the compiler and standard library do not assume Linux; a port adds an implementation underneath and changes no public signature.
- **Hosted runtimes** for the targets that offer only a C library.
- **Portable asynchronous I/O.** The intermediate language's `async_context` is implemented with `kqueue` on the BSDs, alongside `io_uring` on Linux.

## Backends

QBE with the system assembler and linker is the default, bootstrap and first-class backend on every target it reaches, and it never comes to need LLVM. QBE 1.3 already generates code for the platforms above, including Windows and macOS (Intel and Apple silicon).

- **LLVM backend** (planned): faster generated code, debug information, and targets QBE lacks (Windows on ARM, WebAssembly). The compiler emits its own intermediate language (ZIL) and only `zilc` targets QBE, so this is a new lowerer, not a compiler rewrite.
- **C backend** (possible): for toolchains with only a C compiler.

## A wider user base

Before 1.0 the language needs more programs than its author's to exercise it and mature it: more users, more libraries, and more platforms running real work. The author's own projects are the first users; the plan is to write several in Zoril and fix what they find.

## Optimizing the compiler

Improve compile speed, the speed of generated code and the compiler's memory use, and look for opportunities to refactor toward simpler code. The size of the compiler may grow with features; simplifying where possible is a goal in its own right.

## Toward 1.0

1.0 will mean committing to backward compatibility for the syntax and standard library, as described in the [Stability Statement](STABILITY.md). Before then, breaking changes are grouped into minor releases with migration notes.
