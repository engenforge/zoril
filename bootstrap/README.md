# bootstrap/ — seed compilers

This directory holds the two seed compilers that build Zoril from source with only a C compiler, QBE and binutils. Neither is the Zoril compiler you work on: that is `src/` at the top of the repository.

```text
bootstrap/stage0-c/  (C99)  --builds-->  bootstrap/stage1/  (frozen Zoril)
bootstrap/stage1/           --builds-->  src/  ->  build/zoril  (rebuilds itself to fixpoint)
```

- **`stage0-c/`** is a C99 compiler for a subset of Zoril (~25k lines of C). Its only job is to compile `stage1/`. Its known issues and dialect limits are listed in [KNOWN_ISSUES.md](../KNOWN_ISSUES.md).
- **`stage1/`** is a frozen snapshot of the compiler, the standard library modules it imports, `zilc` and the runtime (~37k lines of Zoril), written in the dialect stage0-c accepts. `stage1/PIN` names the release it was pinned for.

Both are frozen, and neither is counted in the compiler's line count in the [README](../README.md). They also duplicate much of `src/` and `stdlib/`, so expect search results from here when you grep the repository; edit the copies outside `bootstrap/`.

## When you need this

Only for a source bootstrap: `make` on a fresh checkout. If you already have a Zoril toolchain, `make SYSTEM_ZORIL=1` (or `make ZORIL_SEED=<dir>`) skips this directory entirely.

## Changes accepted here

- **`stage0-c/`:** correctness fixes, and small syntax or semantics alignments with `src/` that keep it able to build `stage1/` and pass its own suites — each with a regression test under `stage0-c/tests/fixed_bugs/` or in the functional suite, and each recorded in the seed's language-subset reference. `unsafe fn` is the example. No language feature beyond that: stage0-c's job is to compile `stage1/` and the shared tests, not to track `src/`.
- **`stage1/`:** no hand edits, with two recorded exceptions. It changes when it is **re-pinned**: the whole snapshot is replaced by a newer compiler that stage0-c can still build, and the re-pin verifies that it builds current `src/` to the same fixpoint (`stage1/PIN` names the release). It may also carry a deliberate **backport** of a language feature the frozen compiler must parse (the `use`/`ns::item` syntax, `unsafe fn`), made through the re-pin procedure and recorded in the commit that carries it. Its runtime is the second exception: `stage1/rt/runtime.s` must stay byte-identical to `rt/runtime.s`, which the `runtimes` gate enforces, so a runtime fix moves both copies together.

`make stage0c-suites` and `make stage0c-fixed-bugs` run stage0-c's tests. `make repro-check` runs the whole chain from scratch twice and requires the two builds to agree (see [Reproducible Builds](../doc/reproducible_builds.md)).

This directory may move to its own repository once release binaries are the usual way to get a Zoril toolchain; see the [Roadmap](../doc/ROADMAP.md).
