# Zoril Stage0-C Bootstrap Compiler

`stage0-c` is a portable C99 bootstrap compiler for Zoril.

Its sole purpose is bootstrapping the pinned compiler snapshot (`bootstrap/stage1/`), which in turn builds the self-hosted compiler from `src/`. Once `build/zoril` is built, it rebuilds itself to fixpoint.

## Building

```bash
make          # builds build/zoril-c
make release  # builds optimized release binary at build/zoril-c.release
make test     # runs stage0-C test suites
```

## Structure

- `src/` — C99 implementation of the Zoril frontend, typechecker, and QBE emitter.
- `include/` — Header files and AST/IL definitions.
- `lib/rt/` — Minimal runtime stubs for the bootstrap compiler.
- `tests/` — Test suites for stage0-C dialect verification and bug regressions.
- `scripts/` — Test runners and validation scripts.

## Changes

stage0-c is frozen. It accepts two kinds of change, each with a regression test under `tests/fixed_bugs/` or in the shared functional suite, and each recorded in the fix table of the seed's language-subset reference in the source repository (§5):

- **correctness fixes** — a wrong answer, a value dropped or silently zeroed, or a form it cannot evaluate that it used to guess at. Guessing is not acceptable: an aggregate static initializer it cannot evaluate is now a diagnostic (`tests/fixed_bugs/err_static_initializer_not_constant.zrl`).
- **small syntax or semantics alignments with `src/`** that keep stage0-c able to build the pinned `stage1` snapshot and to pass its own suites. `unsafe fn` is the example: stage0-c's gates compile the shared tests against the repository's `stdlib/`, whose `vec`, `mem`, `sys`, `args` and `proc` modules declare `unsafe fn`, so the seed has to parse the form to compile them at all. Its test is `tests/functional/pointers/unsafe_fn.zrl`.

An alignment is not a licence to track `src/`: the seed grows no language feature beyond what compiling the pinned snapshot and the shared tests needs, and the dialect limits that reference lists in its §3 stay as they are. See [`bootstrap/README.md`](../README.md) for how stage0-c fits into the bootstrap, and its "Changes accepted here" for `bootstrap/stage1/`.
