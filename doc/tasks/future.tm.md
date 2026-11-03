---
project: zoril
status: Planned
date: 2026-11-03
---

# Planned Work

Deferred work, in the order it is expected to be taken up after `active.tm.md` empties. Move a task to `active.tm.md` before working on it.

## The `Box` drop series (Z-0019 to Z-0028)

Today a `Box` is never freed and never runs its contents' `Drop` (`KNOWN_ISSUES.md` §5): a leak, which does not break memory safety. The series makes a `Box` free its allocation and drop its contents at scope end without ever shipping a free that some route can observe. **Invariants for every task in it:** (1) the leak stays the default until Z-0028; the freeing code is built behind an off-by-default option, `--box-free` (`zoril` and `zbuild`), so the tree is releasable after every task; (2) the routes that would observe a freed `Box` are closed first (Z-0019 to Z-0023), each a `+safety` change with probes, accepted twins and the rejection differential; (3) each task ends open with an `Awaiting review` bullet and is fix-reviewed by another model before the next starts; (4) the two drop predicates, `type_needs_drop_internal` (`src/lower_zir/utils.zrl`) and `zil_type_needs_drop` (`src/lower_zir_to_zil.zrl`), change together; (5) build warning-free under stage1 (`make preflight-changed`), keep the `if absent_type { return false; }` lines of both predicates textually intact (mutation anchors), add no `zoril_*` symbol in `src/` (`scripts/check_runtimes.sh`), and regenerate `corpus/zrl_whole_program_zil.sha256` in a commit of its own when output changes. **Order:** Z-0019 to Z-0023 in any order; then Z-0024 to Z-0028 in sequence.

- [ ] +types Z-0018 A10.1 A method call or an index through a reference to a `Box` is refused
    > **Created:** 2026-11-03 An over-rejection with a clean diagnostic in both build modes.

    - `impl Point { fn sum(self: &Point) -> i64 { ... } }` then `fn f(p: &Box<Point>) -> i64 { return p.sum(); }` gives "cannot move out of borrow" (likewise `p.bump()` with `p: &mut Box<Point>`); `fn f(p: &Box<[i64; 4]>) -> i64 { return p[2]; }` gives "cannot index `&Box<[i64; 4]>`". `b.sum()` on a `Box<Point>` works.
    - **Do:** the method receiver and the index base auto-dereference through every reference and `Box` layer, as field access does (`peel_field_base`), with read and write tests in both build modes and a fuzzer shape.

- [ ] +safety +tests Z-0019 A11.1 A borrow derived from a `Box` ends with the `Box`
    > **Created:** 2026-11-03 **Series:** `Box` drop (above).

    - **Route:** `type_has_drop` (`src/check_zir.zrl`) answers false for a `Box`, so the scope-end rule does not treat a `Box` local as freeing anything, and a borrow derived from a `Box<Point>` can outlive the block that owns it. Harmless while a `Box` leaks; a use after free once it frees.
    - **Do:** reproduce first (a borrow kept past the `Box`'s block is accepted); make `type_has_drop` and its siblings in the scope-end rule (`local_type_has_drop`) count a `Box`. Probes: the escaping borrow (`compile_reject`); accepted twins for a borrow that ends inside the block and for a `Box` received as a parameter. `make test`, `make preflight-changed`, the rejection differential.

- [ ] +safety +tests Z-0020 A11.2 A closure may not move out through a captured `Box`
    > **Created:** 2026-11-03 **Series:** `Box` drop.

    - **Route:** a capture alias with a projection (`*b`, `b.f` of a captured `Box`) is not refused as a move out of a capture, so a closure can take the value out of a `Box` its environment still owns.
    - **Do:** reproduce first; refuse the move, keeping reads and borrows through the capture legal. Probes: the move (`compile_reject`); twins for a read, a borrow and a `Copy` field copied out. Verification as Z-0019.

- [ ] +safety +tests Z-0021 A11.3 A move out through a slice or an intermediate reference reports "cannot move out of borrow"
    > **Created:** 2026-11-03 **Series:** `Box` drop.

    - **Do:** reproduce each shape first (`let x = s[i]` with `s: &[Box<T>]`; `let x = *r.f` where `r.f` refers to an owning value); refuse with "cannot move out of borrow"; probes and `Copy` twins. Verification as Z-0019.

- [ ] +safety +tests Z-0022 A11.4 A partial move is detected through `Box` dereferences and array indices
    > **Created:** 2026-11-03 **Series:** `Box` drop.

    - **Route:** `reject_partial_move` (`src/lower_zir/decl.zrl`) stops at a `Box` dereference or an array index, so moving a field out of `*b` or `a[i]` and then using or dropping the whole is not refused.
    - **Do:** reproduce first; make the walk follow `Box` dereferences and array indices; probes for each, twins for moving the whole value and for `Copy` fields. Verification as Z-0019.

- [ ] +safety +tests Z-0023 A11.4b A `Box` cannot be forged with `@ptr_cast` or `@ptr_from_int`
    > **Created:** 2026-11-03 **Series:** `Box` drop. **Decided:** refuse, matching `as` (`p as Box<i64>` is already refused).

    - **Now:** `unsafe { @ptr_cast<Box<i64>>(&x as *i64) }` compiles. Once a `Box` frees, the compiler-emitted drop of a forged one would unmap a stack or arena page.
    - **Do:** both intrinsics reject a `Box` target (and a type containing one by value) with the wording `as` uses; probes for both (`compile_reject`), twins for a raw-pointer target. Check how `stdlib/local_mem.zrl`'s `arena_init` builds its `Box<ArenaHeader>`. Verification as Z-0019.

- [ ] +tests Z-0024 A11.5 Lowering preparation for `Box` drops, with no change in behaviour
    > **Created:** 2026-11-03 **Series:** `Box` drop; after Z-0019 to Z-0023.

    - **Do (none changes output while `--box-free` is off):** (1) `find_drop_fn` (`src/lower_zir_to_zil.zrl`) stops peeling a `Box` as it peels a reference, and `Drop`/`DropIfLive` stop counting a `Box` as a plain pointer; (2) a `Box` temporary keeps its entry-block stack slot instead of being replaced by its SSA value, so a `Box` created in one branch dominates its scope-exit drop; (3) the `--box-free` option in `zoril` and `zbuild` (help, man pages, the toolchain stamp); (4) a way to run the suite with the option (a wrapper like `scripts/zoril-checked.sh`, or a variable the runner passes on), and a defined route for `--checked` together with it; (5) the option is part of every key the incremental build compares (the `.zri` and the ZIL hashes as well as the toolchain stamp).
    - **Verification:** `make test` with the corpus golden hashes unchanged, `make preflight-changed`.

- [ ] +safety +tests Z-0025 A11.6 Under `--box-free`, a `Box` runs its contents' drop and frees its allocation
    > **Created:** 2026-11-03 **Series:** `Box` drop; after Z-0024.

    - **Do:** under the option only, both drop predicates count a `Box`; the drop glue for `Box<T>` is a translation-unit-private ZIL function per `T`, registered before its body is emitted so a recursive type (`corpus/zrl/25_linked_list.zrl`) is an ordinary call; it runs `T`'s drop glue when `T` needs drop, then frees. Not through a standard-library function (compiler-emitted code cannot assume one is linked): emit the `munmap` system call inline and trap on failure, and under `--checked` reuse `emit_checked_heap_release` so a second free traps. A zero-sized `T` allocates and frees nothing.
    - **Moving out of a `Box` is refused under the option until Z-0026**, with an explicit error; the option also refuses moving a `Box` field out of an aggregate and `[box x; n]` with `n > 1`. `stdlib/local_mem.zrl`'s `Box<ArenaHeader>`: check that the header page is not unmapped twice.
    - **Tests (with and without the option):** drop counts into a `static mut` for scope end, early return, `break`, a move into a call, overwrite by assignment, `Option<Box<D>>`, `Box<Box<D>>`, a field, an array, the recursive list; a bounded-memory loop (3,000 boxes of 1 MiB stays small; skipped without `/proc`); a mutant that removes the option gate. `make test`, `make test-checked` with the option, `make preflight-changed`, the rejection differential with the option on and off.

- [ ] +safety +tests Z-0026 A11.7 Under `--box-free`, moving a value out of a `Box` copies it out before the allocation is freed
    > **Created:** 2026-11-03 **Series:** `Box` drop; after Z-0025.

    - **Do:** at every move site whose source is a `Box` dereference (`let`, assignment, struct, array, tuple and enum-variant construction, `box`, call arguments, receivers, `if`/`match` results, `return`, block tails), copy the value into an unnamed `let mut` local, free the allocation without dropping its contents, and clear the moved-from slot so its drop flag does not fire. Remove Z-0025's refusal.
    - **Tests:** each site with a drop-counted `T` and a `Copy` `T`, exiting with a value that is wrong if the copy or the free is wrong; `make test-checked` with the option. Verification as Z-0025.

- [ ] +fuzz +tests Z-0027 A11.8 The fuzzer and the checked build exercise `Box` drops
    > **Created:** 2026-11-03 **Series:** `Box` drop; after Z-0026.

    - **Do:** a generator builder in `scripts/fuzz/gen.lua` that boxes the drop-counted type and moves the box around (into calls, out by `*b`, into `Option`, `Box<Box<_>>`, a struct field), and a fuzzer mode that builds with `--box-free`; `make fuzz-prove` mutants that remove the `Box` case from one drop predicate and that skip Z-0026's copy-out. A short session with the option must be clean.
    - **Also:** audit `stdlib/` for raw-pointer reads that create a second owner (a `Vec`, `HashMap`, `ByteVec`, `String` or iterator returning an element by value without removing it); decide each (a move that clears the source, a copy only for `Copy` types, or a documented obligation) before Z-0028.
    - **Verification:** `make fuzz-prove`, the session, `scripts/test_fuzz_tools.sh`, `make test`.

- [ ] +safety +release Z-0028 A11.9 Make freeing the default, remove `--box-free`, and say in the documents that a `Box` is freed
    > **Created:** 2026-11-03 **Series:** `Box` drop; last.

    - **Do:** make the freeing unconditional and delete the option; regenerate the corpus golden hashes in a commit of their own; correct `doc/spec/surface_syntax.md` §3.3, `doc/tour.md` ("Heap Boxing"), `doc/language/walkthrough.md`, `doc/spec/safety_model.md` and `doc/SAFETY.md` §4.5; remove the `KNOWN_ISSUES.md` §5 entry; add a `CHANGELOG.md` line.
    - **Cost:** each `Box` is its own `mmap`, and the free is one `munmap` per drop; run the benchmarks before the flip and record the difference. A small-object allocator in the runtime is a separate task.
    - **Verification:** `make test`, `make test-checked`, `make preflight-changed`, the rejection differential, a short fuzz session; the fuzz record goes stale.

## Evidence and tooling

- [ ] +fuzz +safety +tests Z-0029 The fuzzer's mutation score: which compiler mutants the fuzzer kills
    > **Created:** 2026-11-03 **Depends:** a full release-bar fuzz run, recorded (the maintainer's).

    - **Why:** zero fuzz findings bounds the fault rate only for programs the generator writes. The direct measure is whether it finds bugs known to exist: the mutants of `scripts/mutation-check.sh`, each one line of `src/` changed and each killed by the test suite.
    - **Do:** generalise `scripts/fuzz/prove_oracle.sh` (or add a sibling sharing its scratch-build code) to run a fixed pilot with any mutant's compiler; a mutant is killed when the run reports a fault, candidate or accepted mismatch. Size the pilot from a trial; a survivor is re-run at a larger range once. A `make fuzz-mutation-score` target printing killed/survived per mutant with the oracle that killed it.
    - **The result is a list, not a fix:** each survivor gets one line of why in `bench/fuzz/README.md`; widening the generator for one is its own task. `make fuzz-prove`, `scripts/test_fuzz_tools.sh` on a one-mutant fixture, `scripts/check_fuzz_fresh.sh --strict`.

- [ ] +tests Z-0030 H3 A golden for `zilc`'s output on `corpus/zil/`
    > **Created:** 2026-11-03

    - **Why:** the hand-written programs in `corpus/zil/` are checked by exit code only, so a change in what `zilc` emits that keeps the exit codes passes unseen; the front end's output on `corpus/zrl/` is pinned by `corpus/zrl_whole_program_zil.sha256`.
    - **Do:** a hash file beside it holding the SHA-256 of the SSA `build/zilc` writes for each `corpus/zil/*.zil`, checked where that file is checked (`scripts/test_incremental.sh`) and regenerated with `UPDATE_GOLDEN=1`; skip `// @skip:` files; fail on an empty golden; document it in `corpus/README.md`. Change one file's expected SSA and confirm the step names it. `make test`.

- [ ] +tests +portability Z-0031 D1 The dependency matrix as a few scenarios instead of one full `make test` per tool
    > **Created:** 2026-11-03

    - **Why:** `scripts/test_dep_matrix.sh` runs a full `make test` per optional and per configurable tool, one after another.
    - **Scenarios:** required tools only (every optional tool removed at once; each gate it affects prints `[SKIP]` with its reason); a typical user (`git` and `lua` present, the rest absent); a relocated toolchain (every configurable tool reached only through its variable); the minimal gcc-free bootstrap; each required tool missing (per tool, each fails within seconds); clang for the C-facing tests (`CC=clang`, skipped when absent). Keep the per-tool matrix behind `make deps-matrix FULL=1`. Split the `ffi-callback` test so only its GNU `__asm__` cases need the extension.
    - **Verification:** the scenario matrix green with its wall time recorded; a planted fault that only scenario 2 catches.

## Types, diagnostics and the standard library

- [ ] +generics +types Z-0032 G1 `impl<T: Copy> Source<T> for S` fails to bind `T` when it appears only in the trait's arguments
    > **Created:** 2026-11-03 Rejected in both build modes.

    - **Reproducer:** `trait Source<T> { fn pull(self: &Self, fallback: T) -> T; } struct S { x: i32 } impl<T: Copy> Source<T> for S { fn pull(self: &S, fallback: T) -> T { return fallback; } } fn main() -> i32 { let s = S { x: 1 }; return s.pull(42) - 42; }` gives `type mismatch: expected &S, found bool`.
    - **Cause:** `impl_scope` (`src/mono.zrl`) binds an `impl`'s type parameters only by matching its target type. **Direction:** unify the trait's type arguments to bind the rest, mangle the bound arguments into the method name, and reject a parameter that appears in neither at the `impl` header.

- [ ] +generics +types Z-0033 G2 User `impl` blocks on `Box<T>` resolve at the `impl` and fail method lookup at the call
    > **Created:** 2026-11-03 Rejected in both build modes.

    - **Reproducer:** `trait Priv { fn q(self: &Self) -> i32; } impl<T> Priv for Box<T> { fn q(self: &Box<T>) -> i32 { return 5; } } fn main() -> i32 { let b = box 7; return b.q() - 5; }` gives `no field 'q' on '&Box<i32>'`.
    - **Cause:** `impl_applies` (`src/mono.zrl`) matches only user types and primitives, not `Box`. **Decide first:** forbid `impl ... for Box<..>` with a clear diagnostic at the header, or allow it for local traits (mono, mangling, interface printing and the spec, symmetrically with `[T]`).

- [ ] +stdlib +portability Z-0034 F1 Portable random access to a file: `File.seek` and `File.read_at`
    > **Created:** 2026-11-03

    - **Now:** reading in pieces works (`Read::read` in a loop, `doc/tour.md` §7); random access is reachable only through `os_unix::lseek` (`stdlib/os/unix.zrl`), with a raw `i64` result and a numeric `whence`.
    - **Do:** `File.seek(pos: SeekFrom) -> Result<u64, Error>` with `enum SeekFrom { Start(u64), End(i64), Current(i64) }`, and `File.read_at(buf: [mut u8], offset: u64) -> Result<usize, Error>` (positional; `pread64` on Linux). Document them in `doc/spec/standard_library.md` and the man-page comments (`make man-gen`), and use them in `doc/tour.md` §7. Tests for each `SeekFrom` arm, `read_at` at 0, mid-file, at and past the end, a seek before 0, and the position left unchanged. `make test`, `make preflight-changed`.

- [ ] +audit +diagnostics Z-0035 A7.12 Separate compilation names a private generic item as missing, not as private
    > **Created:** 2026-11-03 Both build modes reject the access; only the wording differs.

    - **Reproducers:** a private `fn priv_gen<T>` used from another module (whole-program: "it is private"; `zbuild`: "the module defines no 'priv_gen'"); a private generic method called from another module (whole-program: "cannot access private method"; `zbuild`: "no field 'priv_m' on 'S'").
    - **Cause:** `is_private_signature_fn` and `method_is_written` (`src/interface_print.zrl`) skip generic items. **Direction:** write unreferenced private generic functions and methods into the `.zri` as bodiless signatures, and check the resolver rejects calling them before instantiation; then narrow the `KNOWN_ISSUES.md` §4 entry.

## Decisions and hygiene

- [ ] +release +portability +decision Z-0036 R6 Make the toolchain's output identical on every Linux C library
    > **Created:** 2026-11-03 **Owner:** the maintainer's decision.

    - **Background:** `doc/reproducible_builds.md` ("Why the C Library, QBE and the Linker Matter"): QBE's `qsort` calls leave the order of equal elements to the C library, so QBE writes different, equivalent assembly under glibc and musl, and `ld` versions place `.note.gnu.property` differently. A tie-break on a stable key in QBE's three comparators plus `as -mx86-used-note=no` was measured to give byte-identical binaries on glibc and musl.
    - **Choices:** vendor QBE with the patch; send the tie-breaks upstream; or keep documenting that the published binaries reproduce on the release host only. The `as` flag (and `zbuild` passing it) is needed for either of the first two.

- [ ] +docs +research Z-0037 DOC1 Documentation for three readers: an assessment, no decisions
    > **Created:** 2026-11-03

    - **Observation:** users, contributors and scripts read the same safety pages, and gates match sentences in the prose (`scripts/check_safety_figures.sh` in `doc/SAFETY.md`, `scripts/check_safety_model.sh` in `doc/spec/safety_model.md`), so every figure must appear verbatim, which is part of why the pages are dense.
    - **Output:** a short assessment with two or three options (a plain-language user page; a contributor reference; data for scripts kept as data, with tables generated), each with its scope, effort and effect on the gates, plus one rewritten section as a sample. Stop for the maintainer's decision.

- [ ] +refactor Z-0038 H1 Remove the duplicate `import "io.zrl";` and `primitive_type_name` in `src/interface_print.zrl`
    > **Created:** 2026-11-03

    - `src/interface_print.zrl` imports `io.zrl` twice and defines a private `primitive_type_name` identical to `pub fn primitive_type_name` in `src/ast.zrl`, which it already imports. Delete the second import and the copy, and import `ast::primitive_type_name`. `make test`.

- [ ] +portability Z-0039 stage0-c's runtimes have no `.note.GNU-stack` section
    > **Created:** 2026-11-03 **Deferred:** stage0-c is frozen and fixed only when a bug blocks building stage1 or its own suites.

    - `bootstrap/stage0-c/lib/rt/runtime.s` and `sys_linux_x86_64.s` lack the section, so on a linker that defaults to an executable stack (binutils 2.42 on Ubuntu 24.04) the programs `zoril-c` links itself warn and get one. Only stage0-c's own test programs link them; stage1 is linked with `bootstrap/stage1/rt/runtime.s`, which has the section. Take this up if the warning ever fails a stage0-c suite.

## Compatibility matrix

Where Zoril has been tested, by operating system and architecture, recorded per release. **First priority:** Alpine Linux, Arch Linux and Debian (stable): between them they cover musl and glibc, and a `/bin/sh` that is BusyBox `ash`, `bash` and `dash`. **Second priority:** other systems (Ubuntu, Fedora, the BSDs once a port exists, other architectures once the runtime supports them), in an order revised as ports are prioritised. Today the runtime targets `x86_64` Linux only, so the architecture column has one value.

- [ ] +docs +portability Z-0050 CM1 Define the compatibility matrix and record the hosts already tested
    > **Created:** 2026-11-03 **Group:** the compatibility matrix (CM1 to CM4).

    - **Do:** a page, `doc/compatibility.md`, linked from `README.md`: one table per release, one row per host. Columns: operating system and version, architecture, C library, what `/bin/sh` is, the toolchain (`cc`, `qbe`, `as`/`ld` versions), and one result column each for `make test`, the user paths (`make dist-check` with `scripts/dist_user_paths.sh`) and `make repro-check` (two bootstraps from scratch give identical results; with `HASHES=`, they also match a release's hashes). A result is `pass`, `fail` (naming the task that tracks it), `skipped` (naming the reason, for example a missing optional tool) or `not run`. For the comparison with a release's hashes, a mismatch on a host whose QBE, binutils or C library differs from the release host's is expected (`doc/reproducible_builds.md`, "Why the C Library, QBE and the Linker Matter"): record it as `differs (toolchain)`, naming the differing tool, not as `fail`.
    - **Priority:** the page states the two tiers above, and that a first-priority system is tested before each release.
    - **Rows to fill now,** for the current release, from runs repeated on its commit (not from memory): Arch Linux and Alpine Linux, plus Ubuntu 24.04 (the cloud environment), as a second-priority row.
    - **Keep the page true:** a row says which release it was tested at; a release with no row for a first-priority system does not claim it.
    - **Verification:** `make test` (`md-check`, the table width rule); every result in the table has a run behind it.

- [ ] +portability +tests Z-0051 CM2 Test Debian (stable) and add its row
    > **Created:** 2026-11-03 **Depends:** CM1.

    - **Do:** on Debian stable, x86_64: install the dependencies `scripts/check_deps.sh` names, then run `make test`, `make dist-check` and `make repro-check`, and record the row. `/bin/sh` is `dash`. Debian's packaged `scdoc` is older than the 1.11.5 the man-page check requires, so that check skips; record the skip and its reason.
    - **A failure** gets a task of its own, named in the row; this task records the result and does not fix it.
    - **Verification:** the row's three results, each from a run on the release commit.

- [ ] +portability +tests Z-0052 CM3 A recipe for adding a host to the matrix
    > **Created:** 2026-11-03 **Depends:** CM2.

    - **Do:** a short section in `doc/compatibility.md`: how to install the dependencies on the host, which three commands to run, what to record, and how to report a result (a pull request with the row, or an issue linking the logs). After CM1 and CM2 this is written from three systems' experience, so it can be followed on a fourth without asking.
    - **Verification:** follow the recipe on one second-priority system and add its row.

- [ ] +docs +release Z-0053 CM4 The release checklist requires the first-priority rows
    > **Created:** 2026-11-03 **Depends:** CM1.

    - **Do:** the release steps in `CONTRIBUTING.md` require a `make test` pass on each first-priority system (Alpine, Arch, Debian) at the release commit, and the matrix row for each, before the release is tagged. A system's failure blocks the release or is listed in `KNOWN_ISSUES.md` with its task.
    - **Verification:** `make test`; the checklist names the three systems and the page.
