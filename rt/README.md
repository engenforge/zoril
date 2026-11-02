# rt/ — the runtime

Every Zoril program links the runtime: `_start`, the `__zoril_syscall_0..6` stubs, the allocation helpers (`zoril_allocator_alloc`), `memcpy` / `memset` / `memcmp`, the process-argument accessors (`zoril_argc` / `zoril_argv`), the file-descriptor and async helpers, and `zoril_abort`. That one interface exists in four files. This directory holds the copy the self-hosted compiler uses; the other three are the stage0-C runtime and the frozen twin of this one.

Paths below are from the repository root. In the public export the frozen copies live under `bootstrap/`; the development tree keeps the same files at the paths in parentheses.

- `rt/runtime.s` — the canonical source (GNU `as`, AT&T syntax). Host `as` assembles it into `build/runtime.o`, which every program the self-hosted compiler produces links.
- `bootstrap/stage1/rt/runtime.s` (in the development tree, stage1/rt/runtime.s) — the byte-identical twin of it, linked into the stage1 binaries (`build/zoril-stage1`, `build/zilc-stage1`).
- `bootstrap/stage0-c/lib/rt/runtime.c` (in the development tree, stage0-C/lib/rt/runtime.c) — the same runtime in C, with an inline-asm `_start`. It is linked with `bootstrap/stage0-c/lib/rt/sys_linux_x86_64.s` (its syscall stubs and weak allocator helpers) and is the copy `zoril-c` prefers.
- `bootstrap/stage0-c/lib/rt/runtime.s` (in the development tree, stage0-C/lib/rt/runtime.s) — the same runtime in assembly, for when a program's `--stdlib` directory has no `runtime.c` beside it.

## Adding a symbol

Add it to all four files. `make runtimes` (`scripts/check_runtimes.sh`, a gate inside `make test`) compares the copies mechanically: the twin byte for byte, the two stage0-C copies symbol for symbol, every copy against the `extern fn` declarations in `stdlib/` and the `zoril_*` names the codegen of the compiler that links it can emit, the `__zoril_syscall_N` family across all four, and it links a probe that calls those names against each copy. `zoril_argc` / `zoril_argv` were added to all four by hand under the rule "every runtime copy moves together"; the stage0-C C runtime was the copy that failed first (`undefined reference to zoril_argc`), and that failure is why the gate exists.

A change to `rt/runtime.s` is a backport into the frozen `bootstrap/stage1/` snapshot rather than an ordinary edit: `bootstrap/stage1/` is never appended to, and `doc/bootstrap/two_stage.md` §3 gives the re-pin and backport policy.

## Removing a symbol

Because the twin must stay byte-identical, a removal moves both `rt/runtime.s` and `bootstrap/stage1/rt/runtime.s` at once, so the symbol has to have stopped being emitted by both compilers. The current runtime must keep every symbol the pinned stage1 can emit (`doc/bootstrap/two_stage.md` §1): if the frozen stage1's own code still calls one, the stage1 link fails in `make preflight` (`scripts/selfhost-check.sh`).

## The hosted build

`rt/runtime.s` has a second shape, `as --defsym HOSTED=1`, built as `build/runtime_hosted.o` for `zoril --hosted`: it drops `_start` and every name libc owns (`memcpy`, `memset`, `memcmp`, `write`, `abort`, `malloc`, `free`, `realloc`, `fd_open`, `fd_close`) and defines the `main(argc, argv)` that C startup code calls, which tail-calls the program's `zoril_main`. `scripts/check_runtimes.sh` assembles both shapes and checks each defines what it must.
