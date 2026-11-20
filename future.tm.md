# Planned Work

Deferred work, in the order it is expected to be taken up after `active.tm.md` empties. Move a task to `active.tm.md` before working on it.

## Deferred precision rules of the provenance series (from id:z0075)

Rules id:z0075 deferred: each root is seen today only in the tree's own code (changed at the sites instead) or in a few grid cells accepted as a precision bound. Take one up when user code, the grid or a test shows its class.

- [ ] +safety +tests +AI-D id:z0085 B1.9b A value copied out of a referenced collection is not an address into its buffer
    > **Created:** 2026-11-06
    > **Depends:** id:z0075
    > **Check-in:** stop for review after it.

    - **Found by:** id:z0064 (root (d2)).
    - **Deferred (2026-11-06, by id:z0075):** the root is seen only in `src`, at one site, which id:z0089 changes instead; none of the grid's or the tests' refusals is from it. Take this rule up when a user program, the grid or a test shows the class, with the reproducer below.

    - **Now:** a body summary's `ParamContents(i)` tie is mapped with `os_through_plus`, everything reached through the argument at any depth, including the buffer a referenced `Vec` owns. A function returning a `Vec` of elements copied out of `&rows` reads as returning addresses into `rows`'s buffer. In `src/lower_zir/exhaust.zrl`, `exh_expand_or` pushes `row` read out of `rows` and calls itself with `&out`, which makes its caller's result own fresh storage; in `exh_useful`, `rows`, `spec`, `def` and `same` then hold `Frame` and `Unknown`, and its summary becomes every parameter stored into every parameter and a global. 167 of `src`'s 195 warnings are "into a global" because of it.
    - **Reduction:** id:z0084's program with `if again { return self.expand(&out, false); }` added in `expand` before `return out;` (`build/z64/t/d3.zrl`): builds, exits 0, 7 warnings under `--provenance=warn`, with or without id:z0084's experiment. Twin: `expand` pushes a fresh copy (`let c = self.alloc(r.len); out.push(c);`): 0 warnings.
    - **Measured alone (id:z0064, a copy of `src/` with the same fresh copy at `exhaust.zrl:275`):** 195 to 185, and "into a global" 167 to 14; `exh_useful`'s summary becomes `ParamContents(0) -> Param(0) ParamContents(0)`.
    - **Decide first, then do:** a rule that adds knowledge (a tie by depth, or by type: a `[mut u32]` element cannot address a buffer of `[mut u32]` headers without `unsafe`), or the one-line code change at the site (id:z0075 says which route). A rule removes origins in effect, so the series rule and the rejection differential apply; probe a result that does point into the buffer (`fn first(v: &Vec<i32>) -> &i32 { return &v.as_slice()[0]; }`, then the `Vec` dropped or pushed to), which must keep it. `make test`, `make preflight-changed`, the store grid.

    - **From the check-in id:7kbpd (2026-11-18):** id:z0089 worked around this rule's absence with a copy in `ZirLowerer::exh_expand_or` (`1033c46`). When this rule lands, take the copy out again (`out.push(row)`) and check that `src/main.zrl` stays at 14 "into a global" warnings under `--provenance=warn`. The comment above the copy says "A row read out of a referenced Vec is an address into its buffer". That is how the rules read it, not what the program does (the row points into the lowerer's arena), so if the copy stays it should say "the provenance rules read ...".

- [ ] +safety +precision +AI-G @provenance H2 `#[unsafe(borrows(*self))]` declares a result tied only to what the referent holds; the interface carries it; Vec and String clones use it id:42ae2
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:bfd1z

    - **Placed:** after id:bfd1z, whose `ret_held` it sets by declaration; id:2sdmk's decision (4).
    - **Moved (2026-11-18, the maintainer's decision):** from directly after id:bfd1z to directly after id:z0044, with H3 and the check-in id:22qty. H3 cannot land before id:z0044 and id:kqp9n (P9 of id:2sdmk), and a trusted form and summary bit added before id:z0011 and id:z0012 are more for those to check and carry over. H2 stays tied to H3, so it moves with it. If id:bfd1z's count is small, the three move to `future.tm.md` instead.
    - **Stop and report first:** `Vec.empty_like` is a new `pub` stdlib method and `Clone for Vec<T>`'s body changes; both wait for the maintainer's approval of id:2sdmk.
    - **Scope:** the parser accepts `*self` (and `*p` for a reference parameter `p`) only inside `#[unsafe(borrows(..))]`, setting the parameter's `ret_held` bit as well as its `ret_ties` bit; the interface writers keep the form and write a `ret_held` `#[summary]` key; `scripts/check_safety_comments.sh` requires a `// SAFETY:` line above it as for the other `#[unsafe(..)]`; `doc/spec/surface_syntax.md` and `doc/spec/unsafe_policy.md` name it. Stdlib: `Vec.empty_like` with the declaration, `Clone for Vec<T>` rewritten on it with no `unsafe`, `Clone for String` with the declaration.
    - **Checks:** C1: `tests/error_reporting/` tests: `*self` in a plain `#[borrows(..)]` refused, `*x` for a by-value parameter refused. C2: `--emit-origins` on `build/2sdmk/shapes.zrl` shows a held bit for `cl` (`Vec<[u8]>`) and none for `Vec<S>.clone` (P2). C3: `tests/modular/iface_attrs/` case: the `.zri` of a module with the declaration has `ret_held`, and an importer reads it (the key removed from the `.zri` by hand: the importer's held bit is gone). C4: `make test`, `make preflight-changed`, rejection differential with no newly accepted program (the borrow checker does not read `ret_held` until H3).

    - **Deferred (2026-11-18, by the maintainer's decision recorded in id:2sdmk):** id:bfd1z counted 5 held sites among the 84 of `src/` and `tools/`, which is small, so H2, H3 and id:22qty move to `future.tm.md`, to resume after id:z0012.
    - **Start from id:bfd1z's patch:** the word and `ILFunction.os_ret_held` this task sets by declaration were not committed. Apply id:bfd1z's **Patch: the word** first, re-run its C1 to C4, and write the design note paragraph and the `unsafe` obligation that id:bfd1z's scope named. Also read its Findings A to C.

- [ ] +safety +precision +AI-G @provenance H3 A call tied to an argument only through what its referent holds borrows what the referent holds, not the referent, so probe 307 is accepted id:mqh84
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:42ae2, id:z0044, id:kqp9n

    - **Placed:** after id:42ae2; id:2sdmk's decision (2), and id:2sdmk's checks C1 to C3.
    - **Moved (2026-11-18, the maintainer's decision):** with id:42ae2, to after id:z0044; its blockers id:z0044 and id:kqp9n are now before it (see id:42ae2).
    - **Scope:** `inherit_rv_borrows`'s `Call` arm reads the callee's `ret_held`, as decision (2) says; P1 to P8 of id:2sdmk become tests (`tests/language/memory/` or probes) with their expected verdicts; probe 307 flipped to `accept`.
    - **Checks:** C1: probe 307 `accept`; gap_77, P1, P2, P3, P5, P6, P8 and P9 refused, each as a test. C2: with the copy of the referent's borrows taken out (the direct borrow dropped, nothing copied), P3 and P5 are accepted (the check sees the defect); restored, refused. C3: P7: `sh scripts/run_safety_matrix.sh` with 0 mismatches, and the `safety-matrix-zbuild` and `zbuild-diff` gates pass. C4: `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, every newly accepted program listed with its reason.
    - **Ends with a check-in:** the `@checkin` task after it reviews H2 and H3.

    - **Deferred (2026-11-18, by the maintainer's decision recorded in id:2sdmk):** id:bfd1z counted 5 held sites among the 84 of `src/` and `tools/`, which is small, so H2, H3 and id:22qty move to `future.tm.md`, to resume after id:z0012.
    - **Check to add:** id:bfd1z's Finding B, P9's class inside one body, beside P9.
    - **From id:sjqmy (2026-11-20, git:04be73c):** when this task lands, also have `os_call`'s tie arm read `ret_held` (using `os_through_split` into `O`, dropping `S` of the pointee) so P1–P4 (`return v.clone()` of local `Vec`/`String`, and `Vec<Vec<[u8]>>::resize`) are accepted alongside probe 307, and remove the `KNOWN_ISSUES.md` §5 bound.

- [ ] +safety +AI-D @provenance @checkin Check-in: review H2 and H3 (the trusted held declaration, and the caller rule that frees probe 307) id:22qty
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:42ae2, id:mqh84

    - **Placed:** directly after id:mqh84, the batch it reviews (H2, H3; H1 is `+AI-D` and closes itself).
    - **Moved (2026-11-18, the maintainer's decision):** with id:42ae2 and id:mqh84, to stay directly after the batch it reviews.
    - **Review:** re-run H3's C1 to C3 and P1 to P8 of id:2sdmk; probe the sibling routes: a held tie through a trait call resolved per instance, a `Box` receiver, a field receiver (`s.v.clone()`), a `match` binding receiver, and an import whose `.zri` has no `ret_held` key.

    - **Deferred (2026-11-18, by the maintainer's decision recorded in id:2sdmk):** id:bfd1z counted 5 held sites among the 84 of `src/` and `tools/`, which is small, so H2, H3 and id:22qty move to `future.tm.md`, to resume after id:z0012.

## The `Box` drop series (id:z0019 to id:z0028)

Today a `Box` is never freed and never runs its contents' `Drop` (`KNOWN_ISSUES.md` §5): a leak, which does not break memory safety. The series makes a `Box` free its allocation and drop its contents at scope end without ever shipping a free that some route can observe. **Invariants for every task in it:** (1) the leak stays the default until id:z0028; the freeing code is built behind an off-by-default option, `--box-free` (`zoril` and `zbuild`), so the tree is releasable after every task; (2) the routes that would observe a freed `Box` are closed first (id:z0019 to id:z0023), each a `+safety` change with probes, accepted twins and the rejection differential; (3) each task ends open with an `Awaiting review` bullet and is fix-reviewed by another model before the next starts; (4) the two drop predicates, `type_needs_drop_internal` (`src/lower_zir/utils.zrl`) and `zil_type_needs_drop` (`src/lower_zir_to_zil.zrl`), change together; (5) build warning-free under stage1 (`make preflight-changed`), keep the `if absent_type { return false; }` lines of both predicates textually intact (mutation anchors), add no `zoril_*` symbol in `src/` (`scripts/check_runtimes.sh`), and regenerate `corpus/zrl_whole_program_zil.sha256` in a commit of its own when output changes. **Order:** id:z0019 to id:z0023 in any order; then id:z0024 to id:z0028 in sequence.

- [ ] +types +AI-G id:z0018 A10.1 A method call or an index through a reference to a `Box` is refused
    > **Created:** 2026-11-03
    > **Context:** An over-rejection with a clean diagnostic in both build modes.

    - `impl Point { fn sum(self: &Point) -> i64 { ... } }` then `fn f(p: &Box<Point>) -> i64 { return p.sum(); }` gives "cannot move out of borrow" (likewise `p.bump()` with `p: &mut Box<Point>`); `fn f(p: &Box<[i64; 4]>) -> i64 { return p[2]; }` gives "cannot index `&Box<[i64; 4]>`". `b.sum()` on a `Box<Point>` works.
    - **Do:** the method receiver and the index base auto-dereference through every reference and `Box` layer, as field access does (`peel_field_base`), with read and write tests in both build modes and a fuzzer shape.

- [ ] +safety +tests +AI-G id:z0019 A11.1 A borrow derived from a `Box` ends with the `Box`
    > **Created:** 2026-11-03

    - **Series:** `Box` drop (above).

    - **Route:** `type_has_drop` (`src/check_zir.zrl`) answers false for a `Box`, so the scope-end rule does not treat a `Box` local as freeing anything, and a borrow derived from a `Box<Point>` can outlive the block that owns it. Harmless while a `Box` leaks; a use after free once it frees.
    - **Do:** reproduce first (a borrow kept past the `Box`'s block is accepted); make `type_has_drop` and its siblings in the scope-end rule (`local_type_has_drop`) count a `Box`. Probes: the escaping borrow (`compile_reject`); accepted twins for a borrow that ends inside the block and for a `Box` received as a parameter. `make test`, `make preflight-changed`, the rejection differential.

- [ ] +safety +tests +AI-G id:z0020 A11.2 A closure may not move out through a captured `Box`
    > **Created:** 2026-11-03

    - **Series:** `Box` drop.

    - **Route:** a capture alias with a projection (`*b`, `b.f` of a captured `Box`) is not refused as a move out of a capture, so a closure can take the value out of a `Box` its environment still owns.
    - **Do:** reproduce first; refuse the move, keeping reads and borrows through the capture legal. Probes: the move (`compile_reject`); twins for a read, a borrow and a `Copy` field copied out. Verification as id:z0019.

- [ ] +safety +tests +AI-G id:z0021 A11.3 A move out through a slice or an intermediate reference reports "cannot move out of borrow"
    > **Created:** 2026-11-03

    - **Series:** `Box` drop.

    - **Do:** reproduce each shape first (`let x = s[i]` with `s: &[Box<T>]`; `let x = *r.f` where `r.f` refers to an owning value); refuse with "cannot move out of borrow"; probes and `Copy` twins. Verification as id:z0019.
    - **Found (2026-11-15, the check-in id:3yasf):** the slice shape is open today for types other than `Box`. A value with a `Drop` impl read by value out of a slice or array element is dropped twice (`gap_90`; id:760hd in `active.tm.md` refuses it, with the message `cannot move out of an array or slice element`), and a `Vec` read twice out of a slice element gives two owners of one buffer (`gap_92`; whether that read is refused is the maintainer's decision, id:v0bwt, which names the `Box` shape of this task). What is left for this task after those two is `let x = *r.f` and whatever id:v0bwt leaves of `s[i]` for a `Box`.
    - **Found (2026-11-15, id:v0rsm):** its slice shape (`let x = s[i]` with `s: &[Box<T>]`) is refused by id:v0rsm's rule with the message `cannot move out of an array or slice element` (`tests/language/memory/element_move/slice_box_let.zrl`).

- [ ] +safety +tests +AI-G id:z0022 A11.4 A partial move is detected through `Box` dereferences and array indices
    > **Created:** 2026-11-03

    - **Series:** `Box` drop.

    - **Route:** `reject_partial_move` (`src/lower_zir/decl.zrl`) stops at a `Box` dereference or an array index, so moving a field out of `*b` or `a[i]` and then using or dropping the whole is not refused.
    - **Do:** reproduce first; make the walk follow `Box` dereferences and array indices; probes for each, twins for moving the whole value and for `Copy` fields. Verification as id:z0019.
    - **Found (2026-11-15, the check-in id:3yasf):** the array-index half is reproduced for a field that needs a drop (`let s = a[0].s;` with `a: [P]`, two drops) and is refused by id:760hd in `active.tm.md`, in `check_zir`'s `check_place_use` rather than in `reject_partial_move`. The `Box` dereference half is left for this task.

- [ ] +safety +tests +AI-G id:z0023 A11.4b A `Box` cannot be forged with `@ptr_cast` or `@ptr_from_int`
    > **Created:** 2026-11-03

    - **Series:** `Box` drop.
    - **Decided:** refuse, matching `as` (`p as Box<i64>` is already refused).

    - **Now:** `unsafe { @ptr_cast<Box<i64>>(&x as *i64) }` compiles. Once a `Box` frees, the compiler-emitted drop of a forged one would unmap a stack or arena page.
    - **Do:** both intrinsics reject a `Box` target (and a type containing one by value) with the wording `as` uses; probes for both (`compile_reject`), twins for a raw-pointer target. Check how `stdlib/local_mem.zrl`'s `arena_init` builds its `Box<ArenaHeader>`. Verification as id:z0019.

- [ ] +tests +AI-G id:z0024 A11.5 Lowering preparation for `Box` drops, with no change in behaviour
    > **Created:** 2026-11-03

    - **Series:** `Box` drop; after id:z0019 to id:z0023.

    - **Do (none changes output while `--box-free` is off):** (1) `find_drop_fn` (`src/lower_zir_to_zil.zrl`) stops peeling a `Box` as it peels a reference, and `Drop`/`DropIfLive` stop counting a `Box` as a plain pointer; (2) a `Box` temporary keeps its entry-block stack slot instead of being replaced by its SSA value, so a `Box` created in one branch dominates its scope-exit drop; (3) the `--box-free` option in `zoril` and `zbuild` (help, man pages, the toolchain stamp); (4) a way to run the suite with the option (a wrapper like `scripts/zoril-checked.sh`, or a variable the runner passes on), and a defined route for `--checked` together with it; (5) the option is part of every key the incremental build compares (the `.zri` and the ZIL hashes as well as the toolchain stamp).
    - **Verification:** `make test` with the corpus golden hashes unchanged, `make preflight-changed`.

- [ ] +safety +tests +AI-D id:z0025 A11.6 Under `--box-free`, a `Box` runs its contents' drop and frees its allocation
    > **Created:** 2026-11-03

    - **Series:** `Box` drop; after id:z0024.

    - **Do:** under the option only, both drop predicates count a `Box`; the drop glue for `Box<T>` is a translation-unit-private ZIL function per `T`, registered before its body is emitted so a recursive type (`corpus/zrl/25_linked_list.zrl`) is an ordinary call; it runs `T`'s drop glue when `T` needs drop, then frees. Not through a standard-library function (compiler-emitted code cannot assume one is linked): emit the `munmap` system call inline and trap on failure, and under `--checked` reuse `emit_checked_heap_release` so a second free traps. A zero-sized `T` allocates and frees nothing.
    - **Moving out of a `Box` is refused under the option until id:z0026**, with an explicit error; the option also refuses moving a `Box` field out of an aggregate and `[box x; n]` with `n > 1`. `stdlib/local_mem.zrl`'s `Box<ArenaHeader>`: check that the header page is not unmapped twice.
    - **Tests (with and without the option):** drop counts into a `static mut` for scope end, early return, `break`, a move into a call, overwrite by assignment, `Option<Box<D>>`, `Box<Box<D>>`, a field, an array, the recursive list; a bounded-memory loop (3,000 boxes of 1 MiB stays small; skipped without `/proc`); a mutant that removes the option gate. `make test`, `make test-checked` with the option, `make preflight-changed`, the rejection differential with the option on and off.

- [ ] +safety +tests +AI-D id:z0026 A11.7 Under `--box-free`, moving a value out of a `Box` copies it out before the allocation is freed
    > **Created:** 2026-11-03

    - **Series:** `Box` drop; after id:z0025.

    - **Do:** at every move site whose source is a `Box` dereference (`let`, assignment, struct, array, tuple and enum-variant construction, `box`, call arguments, receivers, `if`/`match` results, `return`, block tails), copy the value into an unnamed `let mut` local, free the allocation without dropping its contents, and clear the moved-from slot so its drop flag does not fire. Remove id:z0025's refusal.
    - **Tests:** each site with a drop-counted `T` and a `Copy` `T`, exiting with a value that is wrong if the copy or the free is wrong; `make test-checked` with the option. Verification as id:z0025.

- [ ] +fuzz +tests +AI-D id:z0027 A11.8 The fuzzer and the checked build exercise `Box` drops
    > **Created:** 2026-11-03

    - **Series:** `Box` drop; after id:z0026.

    - **Do:** a generator builder in `scripts/fuzz/gen.lua` that boxes the drop-counted type and moves the box around (into calls, out by `*b`, into `Option`, `Box<Box<_>>`, a struct field), and a fuzzer mode that builds with `--box-free`; `make fuzz-prove` mutants that remove the `Box` case from one drop predicate and that skip id:z0026's copy-out. A short session with the option must be clean.
    - **Also:** audit `stdlib/` for raw-pointer reads that create a second owner (a `Vec`, `HashMap`, `ByteVec`, `String` or iterator returning an element by value without removing it); decide each (a move that clears the source, a copy only for `Copy` types, or a documented obligation) before id:z0028.
    - **Verification:** `make fuzz-prove`, the session, `scripts/test_fuzz_tools.sh`, `make test`.

- [ ] +safety +release +AI-D id:z0028 A11.9 Make freeing the default, remove `--box-free`, and say in the documents that a `Box` is freed
    > **Created:** 2026-11-03

    - **Series:** `Box` drop; last.

    - **Do:** make the freeing unconditional and delete the option; regenerate the corpus golden hashes in a commit of their own; correct `doc/spec/surface_syntax.md` §3.3, `doc/tour.md` ("Heap Boxing"), `doc/language/walkthrough.md`, `doc/spec/safety_model.md` and `doc/SAFETY.md` §4.5; remove the `KNOWN_ISSUES.md` §5 entry; add a `CHANGELOG.md` line.
    - **Cost:** each `Box` is its own `mmap`, and the free is one `munmap` per drop; run the benchmarks before the flip and record the difference. A small-object allocator in the runtime is a separate task.
    - **Verification:** `make test`, `make test-checked`, `make preflight-changed`, the rejection differential, a short fuzz session; the fuzz record goes stale.

## Evidence and tooling

- [ ] +fuzz +safety +tests +AI-D id:z0029 The fuzzer's mutation score: which compiler mutants the fuzzer kills
    > **Created:** 2026-11-03

    - **Depends note:** a full release-bar fuzz run, recorded (the maintainer's).

    - **Why:** zero fuzz findings bounds the fault rate only for programs the generator writes. The direct measure is whether it finds bugs known to exist: the mutants of `scripts/mutation-check.sh`, each one line of `src/` changed and each killed by the test suite.
    - **Do:** generalise `scripts/fuzz/prove_oracle.sh` (or add a sibling sharing its scratch-build code) to run a fixed pilot with any mutant's compiler; a mutant is killed when the run reports a fault, candidate or accepted mismatch. Size the pilot from a trial; a survivor is re-run at a larger range once. A `make fuzz-mutation-score` target printing killed/survived per mutant with the oracle that killed it.
    - **The result is a list, not a fix:** each survivor gets one line of why in `bench/fuzz/README.md`; widening the generator for one is its own task. `make fuzz-prove`, `scripts/test_fuzz_tools.sh` on a one-mutant fixture, `scripts/check_fuzz_fresh.sh --strict`.

- [ ] +tests +AI-G id:z0030 H3 A golden for `zilc`'s output on `corpus/zil/`
    > **Created:** 2026-11-03

    - **Why:** the hand-written programs in `corpus/zil/` are checked by exit code only, so a change in what `zilc` emits that keeps the exit codes passes unseen; the front end's output on `corpus/zrl/` is pinned by `corpus/zrl_whole_program_zil.sha256`.
    - **Do:** a hash file beside it holding the SHA-256 of the SSA `build/zilc` writes for each `corpus/zil/*.zil`, checked where that file is checked (`scripts/test_incremental.sh`) and regenerated with `UPDATE_GOLDEN=1`; skip `// @skip:` files; fail on an empty golden; document it in `corpus/README.md`. Change one file's expected SSA and confirm the step names it. `make test`.

- [ ] +tests +portability +AI-G id:z0031 D1 The dependency matrix as a few scenarios instead of one full `make test` per tool
    > **Created:** 2026-11-03

    - **Why:** `scripts/test_dep_matrix.sh` runs a full `make test` per optional and per configurable tool, one after another.
    - **Scenarios:** required tools only (every optional tool removed at once; each gate it affects prints `[SKIP]` with its reason); a typical user (`git` and `lua` present, the rest absent); a relocated toolchain (every configurable tool reached only through its variable); the minimal gcc-free bootstrap; each required tool missing (per tool, each fails within seconds); clang for the C-facing tests (`CC=clang`, skipped when absent). Keep the per-tool matrix behind `make deps-matrix FULL=1`. Split the `ffi-callback` test so only its GNU `__asm__` cases need the extension.
    - **Verification:** the scenario matrix green with its wall time recorded; a planted fault that only scenario 2 catches.

- [ ] +tools +portability +deps +AI-D id:z0118 Build and test tooling without Lua: shell for glue, Zoril for everything larger
    > **Created:** 2026-10-15
    > **Context:** in the incubator repository this one spun out of; filed here 2026-11-06 by id:z0103, with its figures updated against this tree.
    > **Context:** an assessment of shell against Lua for the tooling, and how Hare splits its C and Hare tooling, reviewed 2026-10-15 in the incubator (the document was not carried over).

    - **Related:** id:z0117 (a test runner in Zoril), id:z0111 (git in the tests), id:z0031 (the dependency matrix).
    - **Decisions:** keep the direction, drop Lua from the repository. Its rule "move complex sed/awk work into Lua" is reversed: shell plus POSIX `awk` for small text work, Zoril for anything larger. C only on the seed side: tooling in the compiler repository must not add a C compiler to a side that otherwise needs only a previous Zoril, qbe, as and ld. The document's Hare and QBE specifics were unverified; the conclusion does not depend on them.
    - **Why Lua costs:** it is not in most BSD base systems, its binary name varies (`lua54`, `lua5.4`), and it is required by `make test` and `make preflight`, though not by `make` itself (the bootstrap and the compiler build never call it).

    - **The tree today (2026-11-06):** `rg -l '\blua\b' scripts Makefile` lists 24 files. The Lua sources are `bench/cross_lang/gen_multifile.lua` (546 lines), `scripts/fuzz/gen.lua` (3,666 lines, up from the incubator's 980), `scripts/fuzz/store_grid.lua` (843) and `scripts/fuzz/store_grid_classes.lua` (126). The last two are new since the incubator and sit on the preflight path: `scripts/check_reject_diff.sh` generates the 68,640-program grid with them, and `check_store_grid.sh` and `check_store_grid_modular.sh` use them too. `bench/zjson/gen_dataset.lua` no longer exists. `scripts/bench_cross_lang.sh` also writes its report with inline Lua (`lua - ... << 'EOF'`, near line 1408).
    - **Beyond Lua (from id:z0103's F4), the test path's other non-portable dependencies:** `flock`, `setsid`, `mkfifo`, `xargs -P` and `read -t` in `scripts/test.sh` (id:z0117 decides whether a Zoril runner replaces them), four bash scripts (`check_safety_model.sh`, `check_md_links.sh`, `fuzz_safe.sh`, `test_check_no_new_deps.sh`), and git (id:z0111). Each is either removed by a phase below or kept with its reason in `scripts/check_deps.sh`.
    - **Phase 1:** the `lua -e` one-liners become shell/awk, and no new Lua scripts are added (the id:z0103 series rule says the same for the test path).
    - **Phase 2: port the benchmark generator** `bench/cross_lang/gen_multifile.lua` to Zoril, for example as a `tools/gen/` program, and the report writer in `bench_cross_lang.sh` to `sh`/`awk` or Zoril. Pitfalls: (a) **output must be byte-identical** for the same arguments (diff a sweep of argument sets against the Lua version before deleting it); (b) `scripts/bench_cross_lang.sh` (the `CMP_KEY=` line, near line 670) hashes `gen_multifile.lua`'s *source* into the key that matches results to the committed baseline, so porting changes it. Plan for that first: hash the generator's output or the Zoril source, and record in the commit that the baseline key changed and why. (c) Build the generators with the trusted `build/zoril`, never with `ZORIL_CC`: `mutation-check.sh` runs the suite against mutated compilers, and a mutant must not be able to break a test's input generator. Callers: `scripts/test_incremental.sh` (test 18), `scripts/bench_link_floor.sh`, `scripts/bench_cross_lang.sh`, `bootstrap/scripts/bstest-bench.sh`.
    - **Phase 3: port the store grid** `scripts/fuzz/store_grid.lua` and `store_grid_classes.lua` to Zoril. Its output (the cell set and each cell's text) must be byte-identical: `scripts/check_store_grid.sh` and the differential compare against it, and id:z0114 keys its cache on the program set. After this phase the differential and `make test` need no Lua.
    - **Phase 4: port the fuzz generator** `scripts/fuzz/gen.lua`. It uses its own LCG, not `math.random`, so byte-identical output per `(--seed, --count, --mode)` is achievable, and required: the `fuzz-record` gate regenerates recorded findings from their seeds, so different output means re-recording every finding. Use that gate, plus a diff of a few thousand seeds in each mode, as the equivalence check. Expect stdlib gaps (tree building, string formatting): file them as tasks, since finding them is part of the value of the port. After this phase `make preflight` and the fuzz targets need no Lua.
    - **Phase 5:** remove `lua` from `scripts/check_deps.sh`'s profiles, the README and `doc/getting_started.md`. Add a `portability`-gate check that no shipped script calls `lua`.
    - **Phase 6 (with the repository split, `doc/ROADMAP.md` "Moving `bootstrap/` to its own repository"):** the seed repository (stage0-c and stage1) gets a pure `.POSIX` Makefile, cheap there because it is C plus shell. In the compiler repository, consider the Hare model: the Makefile builds just enough to get `zbuild`, and `zbuild` builds and tests the rest. Scope it as its own task when the split is scheduled.
    - **Each phase is its own task** when it is started, with an ID of its own; this task stays the plan.

- [ ] +testinfra +measurement +AI-G id:z0108 T4 Measure whether fewer, larger test files would be faster
    > **Created:** 2026-11-06
    > **Depends:** id:z0105

    - **Do:** from id:z0105's pipeline split, estimate the fixed cost per test (process spawns, stdlib parsing and lowering, link) and its total. Prototype on 50 run tests from one directory: (a) merged into one file of functions called from one `main`, (b) one compiler process for many inputs, if that mode is cheap to add. Report the time saved against what is lost: which test failed, independent `expected exit`, crash isolation. Record which kinds can never merge (`expected compile fail`, `EXPECT:`, `flags:`, `link:`). A decision, then an implementation task, follows only if the saving is large.
    - **Deferred by id:z0103 (2026-11-06):** a per-file test takes about 34 ms through the whole pipeline (`scripts/test.sh --verbose tests/functional/structs/stack_bloat_baseline.zrl`), so the 1283 of them are about 4 s of a 230 s run on 16 cores; merging them could save at most that, at the cost of failure isolation. Reopen it only if id:z0105's 4-job profile shows the per-file groups as a large share of CPU time.

- [ ] +testinfra +diagnosis +AI-D @testinfra Two stage0c gates race on `build/zoril-c` in `make test` (`mv: cannot stat build/zoril-c.tmp`) id:nf1fv
    > **Created:** 2026-11-13
    > **Context:** found while doing id:z0136, which it did not cause.

    - **Placed:** future file, under Evidence and tooling: not blocking, and not a one-session fix until the cause is known.

    - **Seen:** `./scripts/test.sh --gates` failed `stage0c-corpus` (and once `stage0c-error-locations`) with `exited 2 without reporting a failing item`, in two of five runs on one host. `build/gates/stage0c-corpus.log` ends `mv: cannot stat 'build/zoril-c.tmp': No such file or directory` and `make: *** [Makefile:122: build/zoril-c] Error 1`. Both gates run `make -C bootstrap/stage0-c test_*` at once, and both can decide `build/zoril-c` needs rebuilding.
    - **Next:** read `bootstrap/stage0-c/Makefile` around line 122 and find whether the rule writes `build/zoril-c.tmp` under one name for every make; a rebuilt-once step before the gates start (or a per-process temporary name) would end it. The stage0 compiler is frozen except for a blocking bug, but the freeze covers the compiler, not its Makefile; ask the maintainer if a change there is needed.

- [ ] +testinfra +portability +AI-G @testinfra The fuzz scenarios' skip line names `lua` and `timeout`, but the `fuzz` profile they test also needs `bash` id:043c1
    > **Created:** 2026-11-13
    > **Context:** found at check-in id:0f0vv while checking the dependency lists
    > **Branch:** `testinfra`

    - **Why:** `scripts/test_fuzz_jobs.sh`, `test_fuzz_mode_diff.sh` and `test_fuzz_tools.sh` skip when `scripts/check_deps.sh --required-only fuzz` fails, and print `[SKIP] <name>: fuzz dependencies (lua, timeout) not satisfied`. The `fuzz` profile also requires `bash`, for `scripts/fuzz_safe.sh`, so on a host with Lua and `timeout` but no `bash` the line names neither the tool that is missing nor the reason. `AGENTS.md` (Portability) says a skip names the missing tool.
    - **Do:** print the names `check_deps.sh` reports as missing (its `--required-only` output, or a `--missing` mode if it has none) in each of the three skip lines.
    - **Checks:**
      - C1: with a `PATH` shim that leaves out `bash` only (`path_without` from `scripts/lib/path_shim.sh`), each scenario prints a `[SKIP]` line naming `bash`; quote the three.
      - C2: `make test`; quote its `Total:` line.

- [ ] +testinfra +tests +AI-G @testinfra Z2b10 The header grammar refuses a near-miss directive in the header (a capitalised or misspelt directive word) instead of reading it as prose id:sryd4
    > **Created:** 2026-11-13
    > **Context:** found at check-in id:at0d6 (finding 3)

    - **Placed:** in the future file: no file in the tree has the shape, so nothing passes wrongly today. Promote it to `active.tm.md` (on branch `testinfra`) when the header series is next worked on.

    - **Why:** in the header, `tr_expectations` (`scripts/lib/test_runner.sh`) reads a comment whose text does not start with the exact words `expected `, `EXPECT`, `flags`, `link` or `@skip` as prose. So `// Expected exit 4` or `// expect exit 4` above a program that returns 0 leaves the file a plain `run` test, and it passes, though its header names exit 4 (id:at0d6 finding 3, probes `build/at0d6/h/k_case.zrl` and `o_typo_in_header.zrl`). The same lines after the header are ignored too, since the after-header rule is case-sensitive.
    - **Not settled yet (settle before starting, or re-tag `+AI-D`):** which near-miss words count. A first cut: a comment line, in the header or after it, matching case-insensitively `^[ \t]*//[ \t]*(expect(ed)?[ \t]+(exit|compile)|expect:|@?skip:|flags?:|links?:)` that is not exactly one of the forms is malformed. The control `prose` (`// expecting a slice`) must still pass. On 2026-11-13 this pattern matched only `tests/runner/fixtures/tests/bad_header.zrl` over the 1,215 non-`_lib` `*.zrl` files of `tests/` and `corpus/`.
    - **Checks (to write when settled):** malformed cases for `// Expected exit 4`, `// expect exit 4`, `// Flags: -O`, each at its line, through `scripts/test_test_headers.sh`; the `prose` and `body_comment` controls pass; a take-out; the survey; `make test`'s `Total:` line.

- [ ] +testinfra +tests +diagnosis +AI-D Why corpus/zil/15_io_syscall.zil writes about 4 KB of memory past its string, and whether zilc should refuse it id:1kaye
    > **Created:** 2026-11-13
    > **Context:** found by id:z0123: the only per-file test whose output differs between two `make test` runs for a reason other than a pid or a time

    - **Placed:** in the future file. It passes on its exit code, and no ZIL the front end emits has the shape (below), so nothing a user compiles reaches it. Promote it to `active.tm.md` (on branch `testinfra`) when ZIL hygiene is next worked on.

    - **Found:** `corpus/zil/15_io_syscall.zil` should print `IL Syscall\n` (11 bytes), but its `build/tests/corpus+zil+15_io_syscall.zil/output.log` is 4,008 bytes: the string, then memory after it (a stack-like address, `28 8c 7f 6e fe 7f`, among zeros), and those bytes differ from run to run. The file declares `v3: Slice<u8> = string_const "..."`, then `v4: Ptr<u8, 'static> = bitcast v3` and `v5: u64 = slice_len v3`. zilc lowers the `string_const` to the bare data address (`%v3 =l copy $S0` in `test.ssa`), and `slice_len` then loads 8 bytes at `$S0 + 8` as if `v3` were a slice pair: bytes of the string and what follows it, so `write` is asked for a huge length and stops at unmapped memory. The front end types `string_const` as `Ptr<u8, 'local>` (`build/zoril --emit-zil` on a program with a string literal prints `v6: Ptr<u8, 'local> = string_const "..."`), so compiled programs do not reach this. `bitcast` is also not an opcode by `doc/spec/intermediate_language.md` (line 92), but `tools/zilc/src/zil_parse.zrl` (line 2001) accepts it as `cast`. The spec's `string_const` syntax line (`vN: Slice<u8, 'local> = string_const "..."`) disagrees with what the front end emits, too.
    - **Also (2026-11-13):** `corpus/zil/19_fd_io.zil` has the same shape (`v6: Slice<u8> = string_const "fd_io test\n"`, `bitcast v6`, `slice_len v6`, lines 12 to 14). It writes to `/dev/null`, so its output hides it. `bitcast` appears in six corpus files: `02_comparison`, `12_enums_sum`, `13_slices`, `15_io_syscall`, `19_fd_io` and `24_tuples`.
    - **Decided (the maintainer, 2026-11-13):**
      1. The spec's intent is right: `string_const` gives a `Slice<u8, 'local>`. ZIL is meant to be writable by hand. The front end changes to emit that form, so `string_const` has one meaning, in compiled and in hand-written ZIL alike. Not a second, pointer-typed form.
      2. One spelling per opcode: `bitcast` goes, and `cast` stays (the spec's name). zilc refuses `bitcast`, and the six corpus files are rewritten.
      3. Corpus and per-file tests check more than the exit code: a program's output is checked too, so a program that prints memory past its data cannot pass.
      4. What the safety model covers: the maintainer's reading is that it covers programs compiled from Zoril source, not ZIL written by hand. A safety checker in zilc for hand-written ZIL is wanted, as a separate line of work, its order against the provenance series not yet decided.
    - **Found while recording it (the reviewing session):** fixing the type alone does not make the two corpus files right. Each `cast`s its `Slice` value to `Ptr<u8>` and passes that to `write` as the data pointer. Once `string_const` gives a slice, that pointer is the slice's own `{ptr, len}` pair, not the characters. The spec has `slice_construct` (a pointer and a length to a slice) and `slice_len`, but no way back to the data pointer: `slice_data` was removed (`doc/spec/intermediate_language.md` line 340). The front end gets it by casting the slice's address and loading the first word. So hand-written ZIL needs either a `slice_ptr` opcode or that cast-and-load idiom written out. **Open for the maintainer.**
    - **Settled (the maintainer, 2026-11-13):** a `slice_ptr` opcode, and a new branch `zil` off `main`, started after the current `testinfra` work. The work is the series ZL1 to ZL5 at the end of `active.tm.md`'s `## Next` (id:m6vm3, id:qpc8d, id:htrqb, id:ehh6m, id:egsdq). This task is closed when ZL2 lands, since ZL2 fixes the two corpus programs. The larger question, decision 4, is id:ahd1c.
    - **Decide:** which of the three is wrong: the spec's `Slice` type for `string_const`, zilc's lowering, or the corpus file. Then decide whether zilc's type check should refuse `slice_len` on a `string_const` value typed `Slice`, and whether `bitcast` stays an accepted spelling (AGENTS.md: an ambiguity in `doc/spec/` is fixed in the change that relies on the answer). The test should also check its output: `// expected exit code: 0` alone let this pass.

- [ ] +tests +bootstrap +AI-G @main The closure-private-names gate fails on a closure of zero modules instead of passing id:rp4q6
    > **Created:** 2026-11-14
    > **Branch:** `main`

    - **Placed:** in `future.tm.md`: found by check-in id:4374x; the default path already exits 2 when a closure cannot be listed, so only an empty listing reaches it.

    - **Found:** `scripts/check_closure_private_names.sh --list <missing file>` prints `awk: fatal: cannot open file ...` and then `[PASS] closure-private-names: <file>: 0 modules, no shared private name`, exit 0; an empty list file passes the same way. A check that reads nothing passes for the wrong reason.
    - **Do:** in `check_closure`, exit 2 with `[FAIL] closure-private-names: <label>: no modules listed` when the list is unreadable or names no module that exists.
    - **Checks:** C1 a missing and an empty `--list` file each print that line and exit 2. C2 the gate on the tree still prints both `[PASS]` lines. C3 `make test`, its `Total:` quoted.

- [ ] +docs +tests +AI-D @main The safety pages' probe and hole counts are checked against the tree id:594de
    > **Created:** 2026-11-14
    > **Context:** found while closing id:z0100.

    - **Placed:** in `future.tm.md`: documentation drift with no safety effect; no task depends on it.

    - **Found:** `scripts/check_safety_figures.sh` checks `doc/SAFETY.md` §5.3 and the density rows of `doc/spec/unsafe_policy.md`, but not the probe counts in `doc/SAFETY.md` §5 ("**366 `compile_reject`**, ... **46 `known_gap`**") and §6 ("tracked as 46 `known_gap` probes"), nor the open-hole count in `doc/spec/safety_model.md` ("the 18 holes still open"), nor `doc/STABILITY.md`'s "16 open soundness holes", "72 safety properties" and "79-row architecture matrix". At git:891b76e `gap_80` made 47 `known_gap` probes while both `doc/SAFETY.md` lines said 46; `doc/STABILITY.md`'s 16 and `safety_model.md`'s 19 (now 18) already disagree.
    - **Do:** decide which of these counts each page should state at all (a page can link to the table instead of repeating a number); recompute the ones kept from the probes' `// expected:` lines and the Known gaps table in `check_safety_figures.sh`, and fail on a mismatch; a planted wrong count shows the check fails.

- [ ] +bench +testinfra +AI-G @main `perf_gap.sh --gate-record NAME` keeps the other programs' baseline rows, and a failed recording leaves no `.tmp` file id:sgqxe
    > **Created:** 2026-11-15

    - **Found by:** the check-in id:a55tf.
    - **Placed:** under Evidence and tooling: a sharp edge of a maintainer's command, blocking nothing.

    - **Now (git:164ba45):** `sh scripts/perf_gap.sh --gate-record fib` writes the two comment lines and the `fib` row to `bench/perf_gap/gate_baseline.tsv.tmp` and moves it over `bench/perf_gap/gate_baseline.tsv`, so the other five programs' rows are gone and `--gate-check` then prints `[FAIL] <name> has no baseline` for each (seen in id:a55tf's review; restored from git). Since id:s72rr a recording whose count fails exits 1 before the move and leaves `gate_baseline.tsv.tmp` in the tree.
    - **Do:** with named programs, `--gate-record` rewrites only their rows and keeps the others in place; with none it records all, as today. The `.tmp` file is removed when the recording fails. Cases beside T9 on a scratch tree: a baseline of two programs, `--gate-record` of one, the other's row unchanged; the take-out check for each. Not ready to start: its **Checks:** are written when it is promoted.

- [ ] +testinfra +AI-D `fuzz-tools-git` fails when `FUZZ_STAGE` or `FUZZ_GEN` is inherited: decide whether the scenarios of the `git` group clear internal hand-off variables id:5q6tg
    > **Created:** 2026-11-17

    - **Found by:** the check-in id:kbv3f, planting the variables a preflight user could set into each scenario of the `git` group.
    - **Placed:** in `future.tm.md`: neither variable is named for users, so no documented use reaches it.

    - **Now (git:49f4654):** `FUZZ_STAGE=/nonexistent sh scripts/test_fuzz_tools_git.sh` and `FUZZ_GEN=/nonexistent sh scripts/test_fuzz_tools_git.sh` each exit 1 (`FAIL: check_fuzz_record.sh --release failed`; under `FUZZ_STAGE`: `[FAIL] an empty record is clean: exit 2, expected 0; no line matching 'holds no program'`); without them it exits 0. `FUZZ_STAGE` is `scripts/fuzz_jobs.sh`'s hand-off to its workers and `FUZZ_GEN` a test hook of `scripts/fuzz_safe.sh` (`rg -n 'FUZZ_STAGE|FUZZ_GEN' scripts`); neither is in a header's user options or in `doc/`.
    - **Inherited at id:kbv3f with no change of result** (each of `check_clean_tree.sh`, `test_test_changed.sh`, `test_build_info.sh`, `test_bench_records.sh`, `test_preflight.sh` exit 0 with all set): `TR_JOBS=1 TR_FILTER=zzznomatch TR_FAIL_FAST=1 TR_VERBOSE=1 TR_QUIET=1 TR_TIMEOUT=1 TR_EXCLUDE=zzz TR_WORK=<dir> BENCH_FORCE=1 BENCH_COMPILE_RUNS=1 BENCH_HOST_ID=planted RECORDS_SKIP=1 FUZZ_FINDINGS=/nonexistent FUZZ_STAGE=/nonexistent FUZZ_GEN=/nonexistent PREFLIGHT_BASE=HEAD~5`.
    - **To decide:** whether a scenario clears every variable its callees read that is not a user option (as `scripts/test_reject_diff.sh` now does for `REJECT_DIFF_`), or only the documented ones; the answer then becomes one `+AI-G` task per scenario.

- [ ] +testinfra +AI-G `preflight-selftest` case 15 asserts that its differential ran without the cache id:fe7z0
    > **Created:** 2026-11-17

    - **Found by:** the check-in id:7rfmj, taking the fix of id:9pnp4 out.
    - **Placed:** in `future.tm.md`: the fix of id:9pnp4 holds today; this only makes its loss visible. It needs a `**Branch:**` line (`main`) when it is promoted.

    - **Now (git:150ba73):** with `REJECT_DIFF_NO_CACHE=1` removed from case 15 of `scripts/test_preflight.sh`, the script still exits 0 with all 33 `[PASS]` lines, and the stand-ins' entry is back (`ls -A build/reject-diff-cache` -> `72ddac29dc6cfc9ca8acf06fc967dc3abb6529fe905cd271f5d2ea927404f65c`). Nothing in `make preflight-changed` sees the fix go.
    - **Settled:** in case 15, the condition `&& echo "$out" | grep -qF "[PASS] reject-diff: 0 newly accepted"; then` becomes `&& echo "$out" | grep -qF "[PASS] reject-diff: 0 newly accepted" \` followed by the line `        && echo "$out" | grep -qF "reject-diff: base verdicts: fresh (no cache)"; then` (`scripts/check_reject_diff.sh` prints that line when the cache is off). Nothing else changes.
    - **Checks:**
      - C1: before: `sh scripts/test_preflight.sh > build/fe7z0-before.log 2>&1; echo rc=$?; rg -c '^\[PASS\]' build/fe7z0-before.log`; quote `rc=0` and the count (33).
      - C2: after: the same command; quote `rc=0`, the same count, and `ls -A build/reject-diff-cache` showing no new entry.
      - C3: take `REJECT_DIFF_NO_CACHE=1` out of case 15 on a copy (`awk '{ sub(/out=\$\(REJECT_DIFF_NO_CACHE=1 /, "out=$(") ; print }' scripts/test_preflight.sh > scripts/.tp_fe7z0.sh; sh scripts/.tp_fe7z0.sh`); quote the `[FAIL]` line of case 15 and a non-zero exit; remove the copy and the entry it wrote.
      - C4: `make test-changed BASE=HEAD` and `TR_WORK=build/tests-git ./scripts/test.sh --quiet --group git`; quote each `Total:` line.

- [ ] +testinfra +AI-D The benchmark comparison cache replays a failed row without its `[FAIL]`, `array_loop.zig` does not compile under zig 0.17.1, and the `preflight-changed` time in the guide is the warm-cache one id:jak7k
    > **Created:** 2026-11-17

    - **Found by:** the check-in id:7rfmj, whose preflight ran in a worktree with no `build/bench/compare/`.
    - **Placed:** in `future.tm.md`: the threshold gate reads only Zoril's and gcc's rows, so no verdict is wrong.

    - **Now (git:150ba73, zig 0.17.1):** with nothing cached, the bench step of `make preflight-changed` prints `[FAIL] zig did not succeed (exit 1)` for `zig build-exe -O ReleaseFast ... bench/cross_lang/array_loop/array_loop.zig` (`array_loop.zig:2:34: error: binary operator '*' has whitespace on one side, but not the other`, at `var a: [4096]i32 = [_]i32{0} ** 4096;`), then `[WARN] comparison rows skipped (their steps failed, see the [FAIL] lines above): zig`, and still writes `build/bench/compare/<key>/complete` (`scripts/bench_cross_lang.sh`, "Cache this run's rows": `complete` asks only that the five tools are on `PATH`). The next run replays the failed row as `Zig (ReleaseFast)   : (cached) compile     -1 ms (RSS   0.0 MB) | run     -1 ms | bin       0 B` with neither the `[FAIL]` nor the `[WARN]` (the main checkout's `build/8wvxb/preflight.log`, line 187, against `build/kbv3f/preflight.log`, which has the `[FAIL]`).
    - **The time:** the bench step took 198 s with the cache cold (this review, `wall=488`; id:kbv3f's run, about 8.5 minutes); id:8wvxb's C1 gave `wall=384` with it warm. `doc/developer_guide.md` says ~6 minutes and does not say which.
    - **To decide:** (1) whether a run with a failed comparison row is stored as `complete`, or the failure is replayed with its `[WARN]`; a wrong skip here hides a broken benchmark source from whoever reads the comparison rows of a preflight (`--update-doc` and `--record` run in full and would show it). (2) The fix of `array_loop.zig` for zig 0.17, and which zig versions the sources are meant for. (3) Whether the guide gives both times. Each answer becomes an `+AI-G` task.

- [ ] +safety +AI-G @provenance The rejection differential also compares the verdicts of programs under `--provenance` id:bzkc0
    > **Created:** 2026-11-19
    > **Branch:** `provenance`

    - **Found by:** id:50y0m, whose change makes the checker accept more only under `--provenance`. `scripts/check_reject_diff.sh` does not read a program's `// flags:` line and compiles every program with the default rules, so its run on that change reported `0 newly accepted ... 0 newly refused, of 69168 programs`, and could not have reported anything else. id:50y0m ran a hand differential instead (its completion note: base and change compiled every `.zrl` under `tests/` and `bench/safety_matrix/probes/` with `--provenance`, and the base also read its own `stdlib/`).
    - **Placed:** in `future.tm.md` under Evidence and tooling: it blocks no open task. While the series changes the `--provenance` rules, the maintainer may want it sooner.
    - **Do:** in `check_reject_diff.sh`, compile every program a second time with `--provenance` (each compiler with its own `stdlib/`), and report newly accepted and newly refused programs of that pass on their own lines, beside the default pass's. Both passes go into the cache key.
    - **Checks:** C1: on id:50y0m's change (`PREFLIGHT_BASE=38860b3`, at git:7f5e508), `REJECT_DIFF_NO_CACHE=1 sh scripts/check_reject_diff.sh 38860b3` lists `borrows_trusted_lie_accepted.zrl` as newly accepted under `--provenance` (and `prov_accept_trusted_forward.zrl` if the program set includes `tests/modular/iface_attrs/`), and nothing else. C2: with the second pass taken out, C1 lists neither. C3: the default pass's line is unchanged on the same run. C4: `make test`.

## Types, diagnostics and the standard library

- [ ] +generics +types +AI-G id:z0032 G1 `impl<T: Copy> Source<T> for S` fails to bind `T` when it appears only in the trait's arguments
    > **Created:** 2026-11-03
    > **Context:** Rejected in both build modes.

    - **Reproducer:** `trait Source<T> { fn pull(self: &Self, fallback: T) -> T; } struct S { x: i32 } impl<T: Copy> Source<T> for S { fn pull(self: &S, fallback: T) -> T { return fallback; } } fn main() -> i32 { let s = S { x: 1 }; return s.pull(42) - 42; }` gives `type mismatch: expected &S, found bool`.
    - **Cause:** `impl_scope` (`src/mono.zrl`) binds an `impl`'s type parameters only by matching its target type. **Direction:** unify the trait's type arguments to bind the rest, mangle the bound arguments into the method name, and reject a parameter that appears in neither at the `impl` header.

- [ ] +generics +types +AI-D id:z0033 G2 User `impl` blocks on `Box<T>` resolve at the `impl` and fail method lookup at the call
    > **Created:** 2026-11-03
    > **Context:** Rejected in both build modes.

    - **Reproducer:** `trait Priv { fn q(self: &Self) -> i32; } impl<T> Priv for Box<T> { fn q(self: &Box<T>) -> i32 { return 5; } } fn main() -> i32 { let b = box 7; return b.q() - 5; }` gives `no field 'q' on '&Box<i32>'`.
    - **Cause:** `impl_applies` (`src/mono.zrl`) matches only user types and primitives, not `Box`. **Decide first:** forbid `impl ... for Box<..>` with a clear diagnostic at the header, or allow it for local traits (mono, mangling, interface printing and the spec, symmetrically with `[T]`).

- [ ] +stdlib +portability +AI-G id:z0034 F1 Portable random access to a file: `File.seek` and `File.read_at`
    > **Created:** 2026-11-03

    - **Now:** reading in pieces works (`Read::read` in a loop, `doc/tour.md` §7); random access is reachable only through `os_unix::lseek` (`stdlib/os/unix.zrl`), with a raw `i64` result and a numeric `whence`.
    - **Do:** `File.seek(pos: SeekFrom) -> Result<u64, Error>` with `enum SeekFrom { Start(u64), End(i64), Current(i64) }`, and `File.read_at(buf: [mut u8], offset: u64) -> Result<usize, Error>` (positional; `pread64` on Linux). Document them in `doc/spec/standard_library.md` and the man-page comments (`make man-gen`), and use them in `doc/tour.md` §7. Tests for each `SeekFrom` arm, `read_at` at 0, mid-file, at and past the end, a seek before 0, and the position left unchanged. `make test`, `make preflight-changed`.

- [ ] +audit +diagnostics +AI-G id:z0035 A7.12 Separate compilation names a private generic item as missing, not as private
    > **Created:** 2026-11-03
    > **Context:** Both build modes reject the access; only the wording differs.

    - **Reproducers:** a private `fn priv_gen<T>` used from another module (whole-program: "it is private"; `zbuild`: "the module defines no 'priv_gen'"); a private generic method called from another module (whole-program: "cannot access private method"; `zbuild`: "no field 'priv_m' on 'S'").
    - **Cause:** `is_private_signature_fn` and `method_is_written` (`src/interface_print.zrl`) skip generic items. **Direction:** write unreferenced private generic functions and methods into the `.zri` as bodiless signatures, and check the resolver rejects calling them before instantiation; then narrow the `KNOWN_ISSUES.md` §4 entry.

- [ ] +stdlib +docs +AI-G `proc.zrl`: say what a command given both `set_envp` and an `env_*` call passes to the child id:w8vmg
    > **Created:** 2026-11-13
    > **Context:** found at check-in id:mxt3d, reviewing id:z0132.

    - **Placed:** future file: a comment, not blocking anything.

    - **Seen:** `Command.spawn` (`stdlib/proc.zrl`) uses the environment `build_envp` builds whenever an `env_*` method ran, and then ignores the array `set_envp` set; neither doc comment says so. **Do:** say it in `env_set`'s and `set_envp`'s comments (or make `set_envp` clear the `env_*` state, which is a behaviour change to decide first), `make man-gen`, `sh scripts/test_man_pages.sh`.

- [ ] +modular +AI-G @main Two modules that each define a private const of the same name fail to assemble: the const's symbol is not qualified by its module id:5342d
    > **Created:** 2026-11-14
    > **Branch:** `main`

    - **Placed:** in `future.tm.md`: found by check-in id:9y3ke; a build failure on a correct program, not a soundness hole.

    - **Found (2026-11-14, `main` at git:b26ca47):** modules `ma.zrl` with `const LIM: i32 = 1;` and `mb.zrl` with `const LIM: i32 = 2;`, each read by a `pub fn`, imported by one `main`: `build/zoril` emits both as the symbol `z3LIME`, and the assembler fails with ``Error: symbol `z3LIME' is already defined`` (`build/z135/priv/const/`). Functions are qualified by their module (`z6stdlib3mem5Arena4dropE`); a const is not. The program is correct and should build.
    - **Do:** qualify a const's symbol by its module, as a function's is, in whole-program and separate compilation (the `.zri` names the symbol the importer references). Probe a `pub const` read from another module, a `static`, and a const of the same name in a module and in the program's root.
    - **Checks:** C1 the program above builds and exits 0, whole-program and through `zbuild` (a test under `tests/modular/`). C2 take the change out and watch C1 fail to assemble. C3 `make test` and `make preflight-changed`, each `Total:` quoted.

- [ ] +types +diagnostics +AI-G @main A call with turbofish checks the number of type arguments id:7sb2k
    > **Created:** 2026-11-14
    > **Context:** found by id:z0100's probes.

    - **Placed:** in `future.tm.md`: a diagnostic gap, not a soundness hole; no task depends on it.

    - **Found:** a call ignores a wrong number of type arguments: `id::<i32, i32>(3)` with `fn id<T>(x: T) -> T` and `g::<i32>(3)` with a non-generic `g` both compile and run (exit 0 for `return id::<i32, i32>(3) - 3;`), and `id::<>(3)` infers `T`. The value form refuses each since git:dc006a0 (`a generic function named as a value needs one type argument for each of its type parameters`, `type arguments given to a function that is not generic`). `direct_callee` in `src/lower_zir/expr.zrl` passes `type_args` to `instantiate_function` without comparing the count with `ff.type_params.len`; a method call (`instantiate_method`) is the twin to probe.
    - **Do:** refuse a count that is not zero and not the declaration's (zero still infers), and type arguments on a non-generic function, at the call as the value form does; an error test per form; `make test`, `make preflight-changed` (the differential lists the newly refused programs).

- [ ] +types +diagnostics +AI-D @main A pattern that moves several values out of a tuple or struct is accepted id:ts1jg
    > **Created:** 2026-11-14
    > **Context:** found by id:z0176's sibling probes.

    - **Placed:** in `future.tm.md`: a false refusal (the safe side), no task depends on it; after id:z0176's fix, whose arm-scope change it should be re-probed against.

    - **Found (`main` at git:8d4670b, `S: Drop`):** each is refused with `use of moved value`, though it moves each value once: `let (s, k) = t;` with `t: (S, i32)`, `let W { s: s, k: k } = w;` with `struct W { s: S, k: i32 }`, `match w { W { s: s, k: k } => .. }`, and `T.A((s, k))` for `enum T { A((S, i32)), B }` (`use of moved value 'the value of the expression at ..'`). Binding the aggregate whole (`T.A(t)`, `F.A(w)`) is accepted.
    - **Do:** find which move the checker sees twice (the destructured place, then a field of it), and accept a pattern whose bindings move disjoint parts; the rejection differential lists every newly accepted program, each read for a second owner.

- [ ] +tests +AI-D @main A by-value pattern that binds a part needing a drop beside any other part is refused with `use of moved value` id:2bx4a
    > **Created:** 2026-11-14
    > **Branch:** `main`

    - **Placed:** in `future.tm.md` by the check-in id:vvtam: a correct program refused, not a hole, and it predates that batch (stage1 refuses it too).

    - **Found (2026-11-14, id:vvtam, scratch `build/vvtam/p/`):** with `struct S { p: *mut u8 }` and `impl Drop for S`, each of these is refused, at the second binding, with `use of moved value 'w'` (or `'the value of the expression at L:C'` for a temporary scrutinee): `let w = (mk(fp), 1); let (x, z) = w;` (the second part is an `i32`), `let w = (mk(fp), mk(fp)); let (x, z) = w;`, `match w { (x, z) => {} }`, `match e { P.A(x, z) => {}, P.B => {} }`, `let W2 { a: x, b: z } = w;`, `let W2 { a: x, b: z } = W2 { .. };`. Binding one part and skipping the others (`let (x, _) = w;`, `P.A(s, _)`) is accepted and drops each value once (`tests/language/match/match_skipped_parts_dropped.zrl`). Without a `Drop` type in the aggregate (`(T, T)`, `T` a plain struct) it is accepted. `build/zoril` at git:7877894, the compiler at git:c161107 and `build/zoril-stage1` all refuse it, and no test in `tests/` binds two parts of an aggregate that needs a drop.
    - **Lead:** the first by-value binding seems to mark the scrutinee moved before the next sub-pattern reads its part. Compare `bind_pattern_name` (`src/lower_zir/lower_match.zrl`) with the borrow checker's view of `Let(x, Use(w.0))` followed by a read of `w.1`.
    - **Do:** diagnose (`+AI-D`: the cause is unknown), then settle the fix in this task's text and re-tag it `+AI-G` if it is mechanical. The fix must keep `match_skipped_parts_dropped.zrl` and `match_by_value_drops_once.zrl` passing and add the six programs above as drop-count cases (each part dropped once). It makes the checker accept more, so the rejection differential applies.

- [ ] +tests +AI-G @main An or-pattern whose alternatives bind different names is refused with a clear diagnostic id:vdgj4
    > **Created:** 2026-11-14
    > **Branch:** `main`

    - **Placed:** in `future.tm.md` by the check-in id:vvtam: a spec rule not enforced and a poor diagnostic, not a hole (a binding missing from the alternative that matched is caught as `use of uninitialized variable` when it is read).

    - **Found (2026-11-14, id:vvtam):** `doc/spec/surface_syntax.md` §"OR Patterns" says every alternative must bind the same set of names. `match x { I.A(n) | I.B(m) => { return 1; } }` (`enum I { A(i32), B(i32) }`) is accepted. `match x { O.A(s, _) | O.D => {}, _ => {} }` (`S: Drop`) is refused only as `use of uninitialized variable 'a temporary'`, at line 1 column 1 of the enclosing function, and `I.A(n) | I.B => { return n; }` is refused as `use of uninitialized variable 'n'`. The compiler at git:c161107 behaves the same.
    - **Do:** in `Pattern.Or` (`src/lower_zir/lower_match.zrl`), collect the names each alternative binds (the per-alternative symbol set `bind_pattern_name` defines). If one alternative's set differs from the first's, report `a binding in an or-pattern must appear in every alternative: '<name>' is missing from one` at the pattern's span, next to the existing `a binding in an or-pattern must have the same type in every alternative` check.
    - **Checks:**
      - C1: `tests/error_reporting/err_or_pattern_binding_missing.zrl` (`// expected compile fail`, `// EXPECT: a binding in an or-pattern must appear in every alternative`) passes under `./scripts/test.sh`. It holds the three programs above, one per function, and the direct `build/zoril --emit-zil` output shows the new error once for each.
      - C2: with the new check commented out, C1 fails (`I.A(n) | I.B(m)` compiles).
      - C3: `REJECT_DIFF_NO_CACHE=1 make preflight-changed` exits 0. Quote the `fresh (no cache)` line and list every newly refused program with its reason; any test in `tests/` that is newly refused is a finding to report, not one to rewrite.
      - C4: full `make test` passes; quote the `Total:` line.

- [ ] +types +AI-D @main A static or path call of a method in a generic impl, or of a generic method with no type arguments, fails with `unknown type T` id:7v42z
    > **Created:** 2026-11-14
    > **Branch:** `main`

    - **Placed:** in `future.tm.md` by id:z0175, where it was found: correct programs refused, not a hole, and older than that task (the compiler at git:7877894 behaves the same).

    - **Found (2026-11-14, id:z0175, scratch `build/z175/`):** with `struct W<T> { x: T }`, `impl<T: Copy> W<T> { fn make(x: T) -> W<T> { return W { x: x }; } }`, `fn main() -> i32 { let w = W.make(4); return w.x - 4; }` is refused with `error: unknown type 'T'` at the impl's target type (`mk.zrl:2:17`). So is `W::dup(&w)` for a method `dup(self: &W<T>)` of that impl (`path_ok.zrl`). A receiver call (`w.dup()`) works. With `struct V { x: i32 }` and `impl V { fn m<U: Copy>(u: &U) -> i32 }`, `V.m(&5)` and `V::m(&5)` are refused with `unknown type 'U'` (`st_ok.zrl`, `pa_ok.zrl`), while `V.m::<i32>(&5)` and `V::m::<i32>(&5)` compile.
    - **Lead:** the method-as-value and path routes (`SymbolKind.Method` in `direct_callee` and in the identifier lowering, `src/lower_zir/expr.zrl`) call `self.resolver.resolve_type(imp.target_ty)` outside the impl's scope, so the impl's own `T` is not defined. Static generic calls do not infer the method's type arguments from the arguments, as receiver calls do (`infer_method_type_args`).
    - **Do:** diagnose both and split into `+AI-G` tasks. Once the static and path routes work, add their `impl<T: Copy>` cases to `tests/error_reporting/err_impl_block_bound.zrl` (they reach id:z0175's bound check, `check_method_type_arg_bounds`).

- [ ] +diagnostics +AI-D @main A refused call does not cascade into `internal error: could not resolve the type of an operator operand` id:gsjhz
    > **Created:** 2026-11-14
    > **Branch:** `main`

    - **Placed:** in `future.tm.md` by id:z0175, where it was found: a misleading second diagnostic after a correct first one, older than that task.

    - **Found (2026-11-14, id:z0175):** `fn need<T: Copy>(x: &T) -> i32 { return 0; }` and `let a = need(&s); return a + 1;` with `S: Drop` report the bound (`type 'S' does not implement trait 'Copy'`), then `internal error: could not resolve the type of an operator operand` at `a`. That happens on the compiler at git:7877894 and for a refused method call alike (`build/z175/casc.zrl`).
    - **Why `+AI-D`:** the second message is deliberate. `check_operand_type_resolved` (`src/lower_zir/utils.zrl`) says an unresolved operand type "is an internal error, never a pass". Silencing it after an earlier error is a mechanism that decides what not to report: decide which unresolved operands may skip it (for example a local whose initializer reported an error, so its type was never set), name what a wrong skip would hide (a real internal error after an unrelated user error), and give a planted case for each before re-tagging `+AI-G`.

- [ ] +types +safety +audit +AI-D @main DN3 Audit: which generic paths the type checker does not visit, and whether every instantiated body is checked after monomorphisation id:dr805
    > **Created:** 2026-11-14
    > **Branch:** `main`

    - **Placed:** in `future.tm.md` under "Types, diagnostics and the standard library", beside id:7v42z and id:gsjhz: an audit with no task waiting for it, at the maintainer's request (2026-11-14, a review of the plan). Series DN, with DN1 (id:3rata) in `active.tm.md`.

    - **Why:** id:z0175 (a bound on an impl block or a method's type parameter was not checked) and the open `unknown type T` reports (id:7v42z, id:z0067, id:gsjhz's cascade) are paths the generic checker does not visit or cannot resolve. Where an unvisited path is accepted, the next unlisted path is a hole; the backstop is that every instantiated body is type-checked in full after monomorphisation, so an unvisited path fails there instead of reaching code generation.
    - **Not yet verified:** what `src/mono.zrl` and `src/il_typecheck.zrl` check of an instantiated body today; this is a question from the task history, not a finding.
    - **Do:** list the places a generic item is checked (the declaration, the call, the instantiation, the ZIL type check) and what each checks. For each of: a bound on a function, an impl block, a method, a trait's associated item; a type argument that is a reference, a slice, a `fn` value, a raw pointer; a generic body read back from a `.zri`: write the three-line program that violates it and record which place refuses it, or that none does. Say what the ZIL type check would catch if every earlier place were removed (a mutation per place).
    - **Checks:** C1 the table of violations against the place that refuses each is in this task. C2 each accepted violation is a probe (a `known_gap` if it is unsafe) and a task. C3 the same table under `zbuild` (separate compilation), since a `.zri` body is read back.

- [ ] +diagnostics +AI-G @main A refusal on a `return` expression is reported at the expression, not at the function's first column id:tcy7e
    > **Created:** 2026-11-15

    - **Found by:** the check-in id:qmms1, while probing id:760hd's element rule.
    - **Placed:** under this heading: a diagnostic's position, no safety effect, not scheduled.

    - **Reproducer:** `struct S { p: i32 }`, `impl Drop for S { fn drop(self: &mut S) {} }`, then `fn pick(r: &S) -> S {` on line 3 and `return *r;` on line 4: the compiler prints `3:1: error: cannot move out of borrow`, the function's first column, not `4:12`. `tests/language/memory/element_move/element_returned.zrl` shows the same for `return a[0];` (`8:1: error: cannot move out of an array or slice element`). The same refusals on a `let` are reported at the expression.
    - **Not settled:** where the position is lost (the `return` terminator's span in the lowering, or `check_place_use`'s caller in `src/check_zir.zrl`), and which other refusals on a returned value share it. A session that takes this up finds that first, then writes the numbered **Checks:** (a test that states the line and column, and the change taken out to watch it fail).

## Decisions and hygiene

- [ ] +safety +decision +AI-D id:z0102 Whether `unsafe fn` gets a `fn` type of its own, callable only in `unsafe`
    > **Created:** 2026-11-06

    - **Found by:** id:z0095's review.
    - **Owner:** the maintainer's decision.

    - **Background:** since id:z0095 an `unsafe fn` becomes a plain `fn` value only inside `unsafe`, and that block claims the function is safe to call with every argument the `fn` type admits (`unsafe_policy.md` §1), the obligation a safe wrapper or a closure calling it in `unsafe` already carries (`build/z95r/d_wrapper.zrl`, `d_closure.zrl`: both compile and fault the same way as the coercion). An `unsafe fn(..) -> R` type would let a value keep the precondition, so each call through it is marked, as Rust's `unsafe fn` pointers are. It is a language feature: the parser, the type checker, monomorphization, `.zri` interfaces, and the stage1 closure (`src/` cannot use it until a re-pin).
    - **Choices:** keep the id:z0095 rule alone; add the type beside it (the coercion to a plain `fn` stays, in `unsafe`); or add the type and refuse the coercion. Measure first how many `unsafe fn` values the tree and the tests make (none in `src/`, zilc or zbuild as of id:z0095).

- [ ] +release +portability +decision +AI-D id:z0036 R6 Make the toolchain's output identical on every Linux C library
    > **Created:** 2026-11-03

    - **Owner:** the maintainer's decision.

    - **Background:** `doc/reproducible_builds.md` ("Why the C Library, QBE and the Linker Matter"): QBE's `qsort` calls leave the order of equal elements to the C library, so QBE writes different, equivalent assembly under glibc and musl, and `ld` versions place `.note.gnu.property` differently. A tie-break on a stable key in QBE's three comparators plus `as -mx86-used-note=no` was measured to give byte-identical binaries on glibc and musl.
    - **Choices:** vendor QBE with the patch; send the tie-breaks upstream; or keep documenting that the published binaries reproduce on the release host only. The `as` flag (and `zbuild` passing it) is needed for either of the first two.

- [ ] +docs +research +AI-D id:z0037 DOC1 Documentation for three readers: an assessment, no decisions
    > **Created:** 2026-11-03

    - **Observation:** users, contributors and scripts read the same safety pages, and gates match sentences in the prose (`scripts/check_safety_figures.sh` in `doc/SAFETY.md`, `scripts/check_safety_model.sh` in `doc/spec/safety_model.md`), so every figure must appear verbatim, which is part of why the pages are dense.
    - **Output:** a short assessment with two or three options (a plain-language user page; a contributor reference; data for scripts kept as data, with tables generated), each with its scope, effort and effect on the gates, plus one rewritten section as a sample. Stop for the maintainer's decision.

- [ ] +refactor +AI-G id:z0038 H1 Remove the duplicate `import "io.zrl";` and `primitive_type_name` in `src/interface_print.zrl`
    > **Created:** 2026-11-03

    - `src/interface_print.zrl` imports `io.zrl` twice and defines a private `primitive_type_name` identical to `pub fn primitive_type_name` in `src/ast.zrl`, which it already imports. Delete the second import and the copy, and import `ast::primitive_type_name`. `make test`.

- [ ] +portability +AI-G id:z0039 stage0-c's runtimes have no `.note.GNU-stack` section
    > **Created:** 2026-11-03

    - **Deferred:** stage0-c is frozen and fixed only when a bug blocks building stage1 or its own suites.

    - `bootstrap/stage0-c/lib/rt/runtime.s` and `sys_linux_x86_64.s` lack the section, so on a linker that defaults to an executable stack (binutils 2.42 on Ubuntu 24.04) the programs `zoril-c` links itself warn and get one. Only stage0-c's own test programs link them; stage1 is linked with `bootstrap/stage1/rt/runtime.s`, which has the section. Take this up if the warning ever fails a stage0-c suite.

- [ ] +zil +safety +decision +AI-D Is ZIL checked for memory safety: a full safety checker in zilc, or ZIL stated to be unchecked like assembly id:ahd1c
    > **Created:** 2026-11-13
    > **Context:** id:1kaye, decision 4. The maintainer is weighing it; a full checker appeals only if it takes work off the compiler's checker, not if it duplicates it.

    - **Asked of:** the maintainer. It changes what the project claims.

    - **What ZIL carries today (measured 2026-11-13, `build/zoril --emit-zil` of `tests/stdlib/test_stdlib_bufio.zrl`, 30,483 lines):** 888 `move` and 255 `drop`, but no `borrow`, `borrow_mut`, `end_borrow`, `region_cast` or `bounds_check`. Of the region names, 18,337 are `'local` and 15 are `'s`. The spec's §6 describes a verifier over borrows, regions and dominating bounds checks. The compiler's checks of those happen on ZIR (`src/check_zir.zrl`, 5,381 lines), and the ZIL it emits no longer says what was borrowed or for how long. `src/verify.zrl` (2,645 lines) checks the little that ZIL still shows: stack-address escapes and constant arena sizes. zilc runs only the type check (`src/il_typecheck.zrl`), until id:egsdq (ZL5).
    - **The options:**
      - **(A) ZIL is unchecked, like assembly.** State it in `doc/spec/intermediate_language.md` and `doc/spec/safety_model.md`: the safety claims cover programs compiled from Zoril source, and hand-written ZIL is checked for types and by the ZIL verifier (after ZL5), not for memory safety. Cost: a few paragraphs. No second checker.
      - **(B) A second, full checker in zilc**, beside `check_zir`. The front end would have to emit the borrows and regions ZIL drops today, and the two checkers would have to be tested against each other on every program (AGENTS.md: two implementations of one thing). This is the redundant pair the maintainer does not want.
      - **(C) One checker, moved down to ZIL.** The front end emits a rich ZIL (borrows, regions, bounds checks, as §6 describes), and the one checker runs on ZIL, in both the compiler and zilc. `check_zir` retires. This is the only option that takes work off the compiler. Against it: ZIL is SSA over addresses, where ZIR has named places and field paths. The checker would have to rebuild what lowering threw away. Its precision would likely drop (more false refusals) or its analysis grow, its diagnostics would name temporaries instead of the user's variables, and the provenance series' rules (`future.tm.md`, the `provenance` section) are written against ZIR. It is a re-architecture of the proven checker, a series longer than provenance.
    - **The reviewing session's recommendation:** (A) now, written as part of the ZIL series; revisit (C) only if ZIL is to become a target for front ends other than Zoril's, and then after the provenance series. (B) not at all.
    - **Decide:** (A), (B) or (C), and for (C), its order against the provenance series.
    - **Decided (the maintainer, 2026-11-13):** (A), extended. ZIL is not checked for memory safety, and zilc is not meant to check as much as Zoril does: lowering removes what full checking needs. zilc should catch what is easy or straightforward to catch in ZIL as designed, aiming at the mistakes made most often. The list is ZL6 (id:0mbg3, after ZL5 in `active.tm.md`). The statement that ZIL is unchecked for memory safety goes into `doc/spec/intermediate_language.md` and `doc/spec/safety_model.md` in ZL1's series (ZL1 places it). A second checker (B) and moving the checker down (C) are not pursued. The maintainer's goal of readable, per-module ZIL is id:zs65k, and it is one more reason against (C): a ZIL rich enough for the full checker would be harder to read.
    - Close this task when ZL1 is in `active.tm.md` with the spec statement placed (move it to `active.tm.md` first; a task is never completed in `future.tm.md`).

- [ ] +zil +decision +AI-D Readable ZIL: zoril translates each module to one ZIL file that keeps its comments, names and order id:zs65k
    > **Created:** 2026-11-13
    > **Context:** the maintainer's goal for later, stated with id:ahd1c

    - **Asked of:** the maintainer, when it is scheduled.

    - **The goal (the maintainer):** `zoril` translates `.zrl` to `.zil` in a form a person reads. It keeps the source's comments where they were, defines each variable near where the source did, and keeps the module boundaries: N `.zrl` files give N `.zil` files, each with its own module's code, not one merged program.
    - **Where things stand (2026-11-13):** the parser keeps comments in the AST: `doc_comment` on functions, `module_doc` on a file, and `stmt_comments` with one entry per statement (`src/ast.zrl`). `--emit-zil` is whole-program today and prints source-line markers such as `// 347: let _t2 = Fd::from_unix_raw(_t1)`, not the user's comments. Compiler temporaries (`_t1`, `v13`) carry most of the values. `zbuild` already compiles module by module through zilc; whether the ZIL it passes per module is the module's own, and how one `.zil` refers to another's functions and types, is not yet checked.
    - **Decide, when scheduled:** what "readable" requires (comments carried, user names on values, the order of definitions), what cross-module references look like in ZIL, and whether the readable form is the form `zilc` compiles or a separate output. It bears on id:0mbg3's checks: a diagnostic on readable ZIL can name the user's variable.

- [ ] +safety +audit +AI-D @main DN2 Audit: is the `unsafe` boundary decided per operation or by operand type, and what a new expression form gets by default id:8wz0y
    > **Created:** 2026-11-14
    > **Branch:** `main`

    - **Placed:** in `future.tm.md` under "Decisions and hygiene", beside id:z0102: an audit with no task waiting for it, at the maintainer's request (2026-11-14, a review of the plan). Series DN, with DN1 (id:3rata) in `active.tm.md`.

    - **Why:** `doc/spec/unsafe_policy.md` §1 lists six operations that need `unsafe`, and the lowering checks `ZirLowerer.unsafe_depth` where each is lowered. If every site must remember to ask, an expression form nobody listed is allowed. The deny-by-default form decides by type: an operation with a raw-pointer operand is refused outside `unsafe` unless it is one of a short list of safe ones (a copy, a comparison, a cast to an integer, passing it on).
    - **Not yet verified:** how the check is written today; this is a question from the documents, not a finding.
    - **Do:** list every site that tests `unsafe_depth` and every expression and pattern form that can take a raw-pointer, integer-to-reference or `extern` operand (`rg -n unsafe_depth src`, the `Expr` and `Pattern` enums in `src/ast.zrl`); say for each form which site decides it, or that none does. Probe each form with no deciding site (a three-line program, built and run). Then say whether one type-directed check at a single place can replace the per-site ones, what it would newly refuse in the tree, and which mutation shows each site is tested.
    - **Checks:** C1 the table of forms against deciding sites is in this task. C2 each form with no site has its probe and result; an accepted unsafe operation is a `known_gap` probe and a task. C3 the decision (keep, or one check by type) is recorded with the count of what it would newly refuse.

## Compatibility matrix

Where Zoril has been tested, by operating system and architecture, recorded per release. **First priority:** Alpine Linux, Arch Linux and Debian (stable): between them they cover musl and glibc, and a `/bin/sh` that is BusyBox `ash`, `bash` and `dash`. **Second priority:** other systems (Ubuntu, Fedora, the BSDs once a port exists, other architectures once the runtime supports them), in an order revised as ports are prioritised. Today the runtime targets `x86_64` Linux only, so the architecture column has one value.

- [ ] +docs +portability +AI-G id:z0050 CM1 Define the compatibility matrix and record the hosts already tested
    > **Created:** 2026-11-03

    - **Group:** the compatibility matrix (CM1 to CM4).

    - **Do:** a page, `doc/compatibility.md`, linked from `README.md`: one table per release, one row per host. Columns: operating system and version, architecture, C library, what `/bin/sh` is, the toolchain (`cc`, `qbe`, `as`/`ld` versions), and one result column each for `make test`, the user paths (`make dist-check` with `scripts/dist_user_paths.sh`) and `make repro-check` (two bootstraps from scratch give identical results; with `HASHES=`, they also match a release's hashes). A result is `pass`, `fail` (naming the task that tracks it), `skipped` (naming the reason, for example a missing optional tool) or `not run`. For the comparison with a release's hashes, a mismatch on a host whose QBE, binutils or C library differs from the release host's is expected (`doc/reproducible_builds.md`, "Why the C Library, QBE and the Linker Matter"): record it as `differs (toolchain)`, naming the differing tool, not as `fail`.
    - **Priority:** the page states the two tiers above, and that a first-priority system is tested before each release.
    - **Rows to fill now,** for the current release, from runs repeated on its commit (not from memory): Arch Linux and Alpine Linux, plus Ubuntu 24.04 (the cloud environment), as a second-priority row.
    - **Keep the page true:** a row says which release it was tested at; a release with no row for a first-priority system does not claim it.
    - **Verification:** `make test` (`md-check`, the table width rule); every result in the table has a run behind it.

- [ ] +portability +tests +AI-G id:z0051 CM2 Test Debian (stable) and add its row
    > **Created:** 2026-11-03

    - **Depends note:** CM1.

    - **Do:** on Debian stable, x86_64: install the dependencies `scripts/check_deps.sh` names, then run `make test`, `make dist-check` and `make repro-check`, and record the row. `/bin/sh` is `dash`. Debian's packaged `scdoc` is older than the 1.11.5 the man-page check requires, so that check skips; record the skip and its reason.
    - **A failure** gets a task of its own, named in the row; this task records the result and does not fix it.
    - **Verification:** the row's three results, each from a run on the release commit.

- [ ] +portability +tests +AI-G id:z0052 CM3 A recipe for adding a host to the matrix
    > **Created:** 2026-11-03

    - **Depends note:** CM2.

    - **Do:** a short section in `doc/compatibility.md`: how to install the dependencies on the host, which three commands to run, what to record, and how to report a result (a pull request with the row, or an issue linking the logs). After CM1 and CM2 this is written from three systems' experience, so it can be followed on a fourth without asking.
    - **Verification:** follow the recipe on one second-priority system and add its row.

- [ ] +docs +release +AI-G id:z0053 CM4 The release checklist requires the first-priority rows
    > **Created:** 2026-11-03

    - **Depends note:** CM1.

    - **Do:** the release steps in `CONTRIBUTING.md` require a `make test` pass on each first-priority system (Alpine, Arch, Debian) at the release commit, and the matrix row for each, before the release is tagged. A system's failure blocks the release or is listed in `KNOWN_ISSUES.md` with its task.
    - **Verification:** `make test`; the checklist names the three systems and the page.

- [ ] +types +AI-D id:z0179 Every `Copy` type is `Clone`, as in Rust
    > **Created:** 2026-11-11
    > **Context:** by id:z0172.

    - **Now:** `Clone` needs an impl; `Copy` is the only bound satisfied structurally. So a `&T`, a `fn` pointer, a tuple or an array, all `Copy`, cannot call `.clone()`, satisfy `T: Clone`, or use `Vec.resize` / `Vec.extend_from_slice` once id:z0173 and id:z0174 make them clone (`gap_73` and `gap_74` are `compile_reject` for that reason).
    - **Do:** decide and implement Rust's rule: a structurally `Copy` type satisfies `Clone`, and its `.clone()` with no impl is the bitwise copy. A type-checker change: `src/` must build under the old rule and the new one, and `scripts/check_reject_diff.sh` lists every program newly accepted, each read for safety. Then `gap_73` and `gap_74` become `accept`.

- [ ] +stdlib +tests +AI-G id:z0182 `Vec.resize` shrinking and `Vec.clear` drop the elements they remove
    > **Created:** 2026-11-11
    > **Context:** by id:z0174.

    - **Now:** `resize(new_len, value)` with `new_len < len`, and `clear()`, only set `len`: the removed elements are never dropped. A leak, not a memory hole (nothing reads them again), but it breaks "drop exactly once" for a `T` with a `Drop`, as `truncate`/`clear` do in Rust.
    - **Do:** drop each removed element, last first, before setting `len`; probe a `Drop` counter through both, and an arena-backed `Vec` (whose `free` is a no-op).
    - **Checks:** C1 a run-time test counting one drop per removed element for both; C2 take the drop out and watch it count 0; C3 `make test`, its `Total:` quoted.

## `main` branch: standalone soundness fixes and general items (from `active.tm.md`, 2026-11-12)

Moved from the sprint, in their order there, when `active.tm.md` became one queue; the maintainer promotes from here. id:z0135, id:z0185, id:z0186, id:z0187 and id:z0188, also `main` tasks, stayed in the queue. On 2026-11-14 the six open soundness holes (id:z0183, id:z0180, id:z0100, id:z0101, id:z0176, id:z0175) moved back to `active.tm.md` at the maintainer's request. The section's notes as they stood:

Standalone tasks developed and committed directly on `main`:
1. Default-mode safety holes: id:z0101 (`extern fn` as `fn` value, `gap_67`), id:z0100 (generic instance as `fn` value, `gap_66`).
2. Bootstrap integrity: id:z0135 (stage1 closure module paths audit; runs before closure module edits in id:z0131/id:z0133).
3. Compiler quality & tools: id:z0013 (reviewer rotation), id:z0014 (`zilc` input validation), id:z0015 (`zoril` error bounds), id:z0016 (`zbuild` ZIL handling), id:z0067 (diagnostic source location), id:z0079 (generic interface roundtrip), id:z0080 (mutation list integrity).
4. Benchmarks: id:z0004 (cloud session variance measurement), id:z0005 (baseline decision).
5. Rules and dependencies (2026-11-12): since 2026-11-11 id:z0135 no longer gates id:z0131 (its syscalls stay in `proc.zrl`, outside the closure); whether it gates id:z0133 is an open question on that task. `AGENTS.md` rules from the series review, which every branch reads: id:z0187 (milestone merges), id:z0185 (the closure command), id:z0186 (a planted case in the design of anything that skips work). They are `main` tasks because `AGENTS.md` changes stand alone; `testinfra` gets them by its next merge from `main`.

- [ ] +diagnostics +modular +AI-G @main id:z0181 An error inside an imported generic body names the source's line under `zbuild`
    > **Created:** 2026-11-11
    > **Context:** by id:z0173.
    > **Branch:** `main`

    - **Branch note:** after the `vecclone` series merges (gap_76's `// zbuild:` line is git:27d1d48 on `vecclone`).

    - **Found (2026-11-11):** `bench/safety_matrix/probes/gap_76_vec_extend_from_slice_double_drop.zrl` (`Vec.extend_from_slice` on an `S` with no `Clone`) is refused by both builds with `error: no field 'clone' on 'S'`, but at `stdlib/vec.zrl:431:60` whole-program and `stdlib/vec.zrl:300:57` under `zbuild`; line 300 is the `slice[i].clone()` line of `vec.zri` (`build/man-gen/zri/vec.zri`), the interface the instantiating module reads the body from. The `safety-matrix-zbuild` gate reported it (`zbuild refuses it for another reason`). `KNOWN_ISSUES.md` §4 "An error inside an imported generic body names the interface's line under `zbuild`" describes it; the warning in the entry above it is suppressed for the same reason (`FnDecl.from_interface`).
    - **Do:** carry each generic body's source positions in the `.zri` (or map interface lines back to the source's), so the error names the source's line in both builds; the warning of the entry above can then be given too. A case for `tests/modular/iface_attrs/` (what the interface loses).
    - **Checks:** C1 gap_76 under `zbuild` names `stdlib/vec.zrl:431:60` (or wherever the whole-program build does); remove its `// zbuild:` line and the `KNOWN_ISSUES.md` entry, and `sh scripts/run_safety_matrix.sh --zbuild` (or the `safety-matrix-zbuild` gate) passes; C2 take the change out and watch the gate report `for another reason`; C3 `make test` and `make preflight-changed`, each `Total:` quoted.

- [ ] +diagnostics +AI-G @main id:z0177 `?` on an enum with `Some` and a payload-carrying `None` reports one error
    > **Created:** 2026-11-11
    > **Context:** by id:z0168's second review.
    > **Branch:** `main`

    - **Found:** `enum O { Some(i32), None(i64) }` and `x?` on an `O` is refused with ``error: `?` needs a `Result` or an `Option`, found `O` ``, then also `internal error: could not resolve the type of an operator operand`: a cascade from the refused `?`, not unsafe.
    - **Do:** after `try_success_variant` refuses the operand, `lower_try_expr` returns a place the caller does not report on again (as the other refusals do).
    - **Checks:** C1 a `tests/error_reporting/` test with that enum, its one `// EXPECT:` line, and no second error (the runner's diff shows none); C2 take the change out and watch the second line return; C3 `make test` and `make preflight-changed`, each `Total:` quoted.

- [ ] +tests +AI-G @main id:z0178 `?` on a `&Result` in a function returning `&Result` has a regression test
    > **Created:** 2026-11-11
    > **Context:** by id:z0168's second review.
    > **Branch:** `main`

    - **Found:** `fn g(r: &Result<i32, i64>) -> &Result<i32, i64> { r?; return r; }` is accepted and returns the right value (exit 7): `types_match` treats a reference and its pointee as matching, so `lower_try_early_return` returns `r` itself, which is the function's return type. Benign today: a `Copy` payload is returned correctly, and a non-`Copy` one is refused by the deref move check (id:z0168).
    - **Do:** a run-time test of that function on an `Ok` and an `Err` (each payload read back by the caller), and a refusal test of the same shape with a non-`Copy` `Err` (`cannot move out of borrow`), so a later change to `types_match` that breaks either is caught.
    - **Checks:** C1 both tests pass; C2 `make test`, its `Total:` quoted.

- [ ] +fuzz +safety +AI-G @main Fuzzer generator: add indirect closure, fn-value forwarding, and mutual-recursion route builders id:mskex
    > **Created:** 2026-11-20
    > **Branch:** `main`

    - **Placed:** before id:z0013 and the post-provenance fuzz renewal (id:a85sp item 3, generator debt).
    - **Do:** add compositional builders and feature tags to `scripts/fuzz/gen.lua` (with matching Rust twin emission) for: (1) closures capturing `&Holder` / `&&Holder` where `Holder` holds `&mut` (`gap_47`, `gap_48`); (2) a capturing closure passed to a `fn(...)` callee that invokes it (`gap_52`) or forwards a view through a closure parameter (`gap_55`); (3) mutually recursive helpers storing a view through a local (`gap_28`, `gap_54`).
    - **Checks:** C1 `lua scripts/fuzz/gen.lua --features` lists the new tags. C2 `make fuzz-short` runs cleanly with 0 `gen-bug`s and covers all new tags. C3 `make fuzz-calibrate` passes. C4 `make test-changed BASE=HEAD`, its `Total:` quoted.

- [ ] +fuzz +safety +AI-G @main Fuzzer generator: add release-tier liveness, inner-block callee store, and method-elision route builders id:4ngz8
    > **Created:** 2026-11-20
    > **Branch:** `main`

    - **Placed:** before id:z0013 and the post-provenance fuzz renewal (id:a85sp item 3, generator debt).
    - **Do:** add compositional builders and feature tags to `scripts/fuzz/gen.lua` (with matching Rust twin emission) for: (1) release-tier liveness: a view stored through a local `&mut`, `&mut` parameter, `self`, `Box`, or two-callee `put`+`kill` followed by `free`/`reset` (`gap_37`–`gap_39`, `gap_43`, `gap_87`, `gap_96`, `425`–`428`); (2) a callee (direct or `fn` value) storing an inner-block local reference into an outer-block struct (`430`–`433`, `id:nhk9n`); (3) a `&self` method returning a view from another parameter followed by `reset` (`gap_44`, `gap_99`–`gap_101`).
    - **Checks:** C1 `lua scripts/fuzz/gen.lua --features` lists the new tags. C2 `make fuzz-short` runs cleanly with 0 `gen-bug`s and covers all new tags. C3 `make fuzz-calibrate` passes. C4 `make test-changed BASE=HEAD`, its `Total:` quoted.

- [ ] +fuzz +safety +AI-G @main Fuzzer generator: add container-of-views, extend_from_slice/Clone, and by-value aggregate route builders id:r1shp
    > **Created:** 2026-11-20
    > **Branch:** `main`

    - **Placed:** before id:z0013 and the post-provenance fuzz renewal (id:a85sp item 3, generator debt).
    - **Do:** add compositional builders and feature tags to `scripts/fuzz/gen.lua` (with matching Rust twin emission) for: (1) `Vec::extend_from_slice` and `.clone()` copying views into an external container (`gap_56`, `gap_77`, `gap_78`, `gap_80`); (2) an owned `Vec` or struct holding frame views pushed or moved into a callee (`gap_59`–`gap_63`, `gap_79`); (3) a frame view read through a local reference to a local struct or passed in a by-value aggregate to a callee that stores it out (`gap_97`, `gap_98`).
    - **Checks:** C1 `lua scripts/fuzz/gen.lua --features` lists the new tags. C2 `make fuzz-short` runs cleanly with 0 `gen-bug`s and covers all new tags. C3 `make fuzz-calibrate` passes. C4 `make test-changed BASE=HEAD`, its `Total:` quoted.

- [ ] +safety +research +AI-D @main id:z0013 Review rounds: rotate reviewers over the compiler until the findings dwindle
    > **Created:** 2026-11-03
    > **Branch:** `main`

    - **Branch note:** **Standing task;** a round reads and probes only, so it can run beside anything except a change to the area it reviews.

    - **A round:** one reviewer (a model or a prompt not used in the last round) takes one area - the type matcher and conversion sites, the borrow checker and its summaries, drop and move semantics, the stdlib's `unsafe` interiors against what safe code can reach, the FFI boundary, the runtime and `zilc` - probes what it suspects against `build/zoril`, and records each lead here as confirmed, refuted or unprobed, with its reproducer.
    - **Checklist:** every site that puts a value into an expected type (`let`, call argument, return, struct field, enum constructor, array literal and repeat, closure capture, method receiver, `match` arm, pattern binding); every type-matching and conversion function at depth above zero; every cast and what it lets safe code build; every place a size or length is narrowed; every check skipped for a special case (unit, `never`, zero length, constant operand); borrows of `static mut` held across a call or an assignment; the FFI boundary; the stdlib's `unsafe` blocks.
    - **Each confirmed hole** becomes a `known_gap` probe, a route class in `doc/spec/safety_model.md`, and a generator feature in `scripts/fuzz/gen.lua`; it is fixed by another session and fix-reviewed by a third before the next round. A fix states the rule it enforces in one sentence and defaults to the strict side for anything it cannot classify.
    - **Stopping rule:** rounds continue while a round with a fresh reviewer confirms a new hole; stop after two consecutive rounds from different reviewers confirm none.
    - **Generator debt (2026-11-05):** route classes added in the hardening series without a `scripts/fuzz/gen.lua` feature (id:z0055 noted one for `gap_47`/`gap_48`); before the fuzz renewal after id:z0012 (id:z0003), list each `known_gap` route class added since the last record and whether the generator covers it, and add the missing features. At least: closures capturing a reference to a struct holding `&mut` (`gap_47`, `gap_48`), a closure passed to a callee that calls it (`gap_52`), a cycle storing through a local (`gap_54`), a closure parameter forwarding a view (`gap_55`), an element copy through an `extern` (id:z0060), a closure storing into a global through a callee (`gap_64`), and an `unsafe fn` made into a `fn` value at each conversion site (`gap_65`).

- [ ] +tools +AI-G @main id:z0014 `zilc` refuses text it does not recognise between declarations, and a file that is not ZIL
    > **Created:** 2026-11-03
    > **Branch:** `main`

    - **Now:** `zilc` exits 0 with no message on random bytes, and on `printf '\x01\x02 zz garbage\n'` it writes a stray global parsed out of the word `garbage`. `ZilParser.parse_module` (`tools/zilc/src/zil_parse.zrl`) dispatches on a declaration's first byte and skips any other byte, so text between declarations is dropped silently.
    - **Do:** at top level, after trivia, accept only the declaration forms of `doc/spec/intermediate_language.md` and report anything else as `zilc: line N: expected a declaration, found '<token>'` with exit 1; before parsing, refuse a NUL byte or invalid UTF-8 with one line. Keep the first-error behaviour.
    - **Checks:**
      - C1: before the change, `printf '\x01\x02 zz garbage\n' > build/z14/g.zil; timeout 10 build/zilc build/z14/g.zil -o build/z14/g.ssa; echo $?` and the `.ssa` it writes; quote both (exit 0 and a stray global today).
      - C2: one `tests/zilc/` case per refusal: a stray word between two functions, control bytes, a NUL byte, invalid UTF-8; each fails before the change (run the new tests against the old `build/zilc` and quote) and passes after.
      - C3: each refusal's message is the one in **Do** (`zilc: line N: expected a declaration, found '<token>'`, or the one-line NUL/UTF-8 refusal), with exit 1; quote each.
      - C4: every file in `corpus/zil/` still compiles and gives its expected exit (`./scripts/test.sh corpus/zil` or the scenario that runs them); quote its `Total:` line.
      - C5: take the top-level check out (a scratch edit) and watch the stray-word case pass silently again; restore.
      - C6: the `KNOWN_ISSUES.md` entry removed or updated; `make test` and `make preflight-changed`, each `Total:` line quoted; the completion note says the fuzz record is stale for `tools/zilc/`.

- [ ] +diagnostics +AI-G @main id:z0015 `zoril` stops after a bounded number of errors, and says when a file does not look like Zoril source
    > **Created:** 2026-11-03
    > **Branch:** `main`

    - **Now:** 300 KB of random bytes named `junk.zrl` gives about 139,000 error lines (12 MB); 160 KB of prose about 33,000. `zbuild` passes the same output through. Reproduce: `head -c 300000 /dev/urandom > junk.zrl; ./build/zoril -I stdlib=stdlib --emit-zil -o o.zil junk.zrl 2>&1 | wc -l`.
    - **Do:** count errors in `diag_start` (`src/diag.zrl`); past the limit (default 20) print one line naming `--error-limit N` (0 removes the limit) and exit 1. `zbuild --error-limit N` passes it to every `zoril -c`; both man pages and `--help` say so. Before lexing, refuse a NUL byte or invalid UTF-8 with one line; if the limit is reached before the first declaration, the stopping line says the file does not look like Zoril source. `src/diag.zrl` is in stage1's closure: use only what stage1 accepts (a `static mut` counter).
    - **Checks:**
      - C1: before the change, the reproducer in **Now**: the line count, quoted. And no existing error test expects more than 20 errors: `grep -c 'EXPECT:'` per file under `tests/`, the largest count quoted (if one is over 20, stop and report: the default changes).
      - C2: a program with 25 type errors: 20 error lines, then the stopping line naming `--error-limit N`, exit 1; with `--error-limit 0`, all 25; with `--error-limit 3`, 3; quote each count.
      - C3: a NUL byte, invalid UTF-8, and 160 KB of prose: one line each, the prose one saying the file does not look like Zoril source; the reproducer from **Now** prints at most 21 lines; quote each.
      - C4: the same through `zbuild --error-limit N` in `scripts/test_zbuild_errors.sh`, passing.
      - C5: `zoril --help`, `zbuild --help` and both man pages name `--error-limit` (`make man`, `sh scripts/test_man_pages.sh`).
      - C6: `rm build/zoril && make` (stage1 builds `src/diag.zrl`) and `make`, no warning.
      - C7: take the counter's check out (a scratch edit) and watch C2 fail; restore.
      - C8: the `KNOWN_ISSUES.md` entry removed or updated; `make test` and `make preflight-changed`, each `Total:` line quoted; the fuzz record is stale for `src/`.

- [ ] +tools +AI-G @main id:z0016 `zbuild` builds a program written in ZIL, and refuses any other input with one line
    > **Created:** 2026-11-03
    > **Branch:** `main`

    - **Now:** `zbuild 01_arithmetic.zil` (from `corpus/zil/`) parses the ZIL as Zoril and prints about thirty `expected declaration` errors; the manual pipeline (`zilc`, `qbe`, `as`, `ld` with the runtime) works and exits 30.
    - **Do:** a root ending in `.zil` skips the module graph and the front end and runs `zilc`, `qbe`, `as` and the link with `zbuild`'s usual linker and runtime choice, honouring `-o` and the cache directory; `--checked` with a `.zil` root is refused with one line. A root ending in neither `.zrl` nor `.zil` is refused with one line naming both. Update `doc/man/zbuild.1.scd` (`make man`), `zbuild --help`, and "Starting from ZIL" in `doc/getting_started.md`.
    - **Checks:**
      - C1: before the change, `build/zbuild corpus/zil/01_arithmetic.zil -o build/z16/a; echo $?` and the first three error lines, quoted.
      - C2: after, the same builds and `build/z16/a; echo $?` prints 30; every file in `corpus/zil/` gives its expected exit code (a loop in a new scenario, or in `scripts/test_user_paths.sh` with the installed `zbuild`); quote the loop's summary.
      - C3: `-o` and the cache directory are honoured: the binary lands at the `-o` path, and a second build of the same `.zil` reuses the cache (the scenario checks the cache directory's contents).
      - C4: `zbuild foo.txt` and `zbuild --checked x.zil`: one line each, exit nonzero; quote both.
      - C5: take the `.zil` branch out (a scratch edit) and watch C2's scenario fail; restore.
      - C6: `doc/man/zbuild.1.scd` (`make man`), `zbuild --help` and "Starting from ZIL" in `doc/getting_started.md` updated; `sh scripts/test_man_pages.sh` passes; the doc snippet scenario (`./scripts/test.sh --scenario getting-started`) passes.
      - C7: the `KNOWN_ISSUES.md` entry removed or updated; `make test` and `make preflight-changed`, each `Total:` line quoted; the fuzz record is stale for `tools/zbuild/`.

- [ ] +diagnostics +types +AI-G @main id:z0067 `v.push(Vec.new())` reports `unknown type 'T'` at a standard-library line under the user's file name
    > **Created:** 2026-11-05
    > **Branch:** `main`

    - **Found by:** id:z0049's review (correction 9). Default mode; not a safety issue.

    - **Now:** `import "vec.zrl"; use vec::Vec; fn main() -> i32 { let mut v: Vec<Vec<i32>> = Vec.new(); v.push(Vec.new()); return v.len() as i32 - 1; }` fails with `<file>.zrl:23:13: error: unknown type 'T'`: line 23 is `stdlib/vec.zrl`'s `impl<T> Vec<T>`, printed with the user's file name. `v.push(Vec::<i32>.new())` compiles, as does `let mut w: Vec<String> = Vec.new(); w.push(String.new());`.
    - **Two defects:** (1) the element type of a generic constructor in argument position is not inferred from the parameter's type (`T` of `push` is known from `v`); (2) a diagnostic raised inside an instantiated generic carries the instance's line with the caller's file. Fix (2) in any case; fix (1) if inference from the expected argument type is in the spec (`doc/spec/`), or else make the message say that the type argument must be written, and fix the spec if it is silent.
    - **Checks:**
      - C1: what `doc/spec/` says about inferring a constructor's type arguments from the parameter it is passed to: the section and the sentence quoted, or "silent" with the sections searched. This decides (1): fix it if the spec says so; otherwise word the message so it says to write the type argument, and add the rule to the spec in the same commit.
      - C2: the program in **Now** as a test: exit 0 after (1), or, if (1) is not fixed, an `// EXPECT:` with the new message naming the user's file and line.
      - C3: a test where an error is raised inside a generic instance: the diagnostic names `stdlib/vec.zrl` (or the instance's file) and its line, not the caller's file with the instance's line; it fails before the change (run against the old compiler and quote).
      - C4: `v.push(Vec::<i32>.new())` and the `String` form still compile (tests).
      - C5: take the file fix out (a scratch edit) and watch C3 fail; restore.
      - C6: `make test` and `make preflight-changed`, each `Total:` line quoted; the fuzz record is stale for `src/` if `src/` changed.

- [ ] +modular +tools +AI-G @main id:z0079 A generic body using a type-argument builtin cannot be read back from its interface
    > **Created:** 2026-11-05
    > **Branch:** `main`

    - **Found by:** id:z0078. Refuses more, never less: not a safety issue.

    - **Now:** the interface printer writes `@ptr_from_int<*mut T>(n)` in a generic body as `@ptr_from_int::<*mut T>(n)`, which the parser refuses when it reads the `.zri` (`expected (, but found ::`). Whole-program builds it; zbuild does not. Reproducer: `plib.zrl` = `pub fn at<T>(n: u64) -> *mut T { return @ptr_from_int<*mut T>(n); }`, `pmain.zrl` = `import "plib.zrl"; fn main() -> i32 { let p = plib::at::<i32>(64 as u64); return (p as u64 - 64 as u64) as i32; }`; `build/zoril` accepts `pmain.zrl`, `build/zbuild -o p pmain.zrl` fails in the cache's `plib.zri`. The same for `@ptr_cast`, `@int_cast` and `@alloca` (each probed, 2026-11-05).
    - **Do:** print a builtin's type argument as written (`@name<T>(..)`), or have the parser accept `::<` after a builtin; say which and why. A `tests/modular/iface_attrs/` fixture with one generic body per builtin, built whole-program and through zbuild. `make test`, `make preflight-changed`.
    - **Settled (review, 2026-11-07):** the printer writes `@name<T>(..)`, as the source does; the parser stays as it is, so the language accepts no new spelling.
    - **Checks:**
      - C1: the reproducer in **Now**, before the change: `build/zbuild -o build/z79/p pmain.zrl` fails with `expected (, but found ::`; quote it.
      - C2: after, it builds and `build/z79/p; echo $?` prints 0.
      - C3: a `tests/modular/iface_attrs/` fixture with one generic body each for `@ptr_from_int`, `@ptr_cast`, `@int_cast` and `@alloca`, built whole-program and through zbuild with the same exit code (`sh scripts/test_interface_attrs.sh` passes; quote it).
      - C4: the `.zri` written for the fixture contains `@ptr_from_int<` and no `@ptr_from_int::<` (`grep` on the cache's `.zri`; quote the line).
      - C5: take the printer change out (a scratch edit) and watch C3 fail; restore.
      - C6: `make test` and `make preflight-changed`, each `Total:` line quoted; the fuzz record is stale for `src/`.

- [ ] +tests +tools +AI-G @main id:z0080 The mutation harness's two lists exist, or its header stops claiming them
    > **Created:** 2026-11-05
    > **Branch:** `main`

    - **Found by:** id:z0078 (and its review).

    - **Now:** `scripts/mutation-check.sh`'s header says `scripts/mutation_uncovered.list` holds the mutations it deliberately does not run (M106, M107, M85, M112) and `scripts/mutation_incremental.list` the ids run against the incremental scenario (`-c` / `.zri`). Neither file exists: `incremental_list_path` returns a missing file, `incremental_mutation` is always false, so no mutant is ever run against the incremental scenario, and nothing records the deliberately unrun ones. `git log --all` shows neither file was ever committed. A mutant of the interface printer (id:z0078's `#[fresh]` printing) is caught only by `scripts/test_interface_attrs.sh`, a gate the harness does not run.
    - **Do:** find in git history whether the lists existed and were lost (`git log --all -- scripts/mutation_incremental.list`), then either restore them with their entries, or make the harness say plainly that it runs neither; and decide whether a mutant may name a gate (the interface gate) as its catcher. Add an interface-printer mutant (`if f.fresh {` -> `if false {` in `src/interface_print.zrl`) that the chosen route catches. `make test`, `sh scripts/test_mutation_check.sh`.
    - **Not ready for `+AI-G` (review, 2026-11-07):** **Do** leaves two decisions: whether the harness runs an incremental list at all, and whether a gate (`scripts/test_interface_attrs.sh`) may be a mutant's catcher, which adds its run time to every surviving mutant's evaluation (the harness already runs `perf-gate`, `fmt-check` and `static-image` that way). An `+AI-D` session, or the maintainer, settles both here first, with the gate's run time measured; then this task gets numbered checks: the new mutant reported caught by the chosen route, and that route taken out and the mutant reported SURVIVED.

- [ ] +bench +measurement +AI-G @main id:z0004 Measure how far the benchmark gate's measures move between cloud sessions
    > **Created:** 2026-11-03
    > **Branch:** `main`

    - **Session rule:** a new session records one sample only if asked to, so this task never starts a session.

    - **Why:** `bench/cross_lang/thresholds.cfg` is not in the tree, so `scripts/bench_threshold_check.sh` records a baseline on its first run on a host. Every cloud session starts on a fresh VM, so there the gate compares a run with itself and cannot fail. Of its three measures, `runtime_ratio_vs_gcc_o2` is relative to gcc on the same host; `clean_throughput_loc_s` and `incremental_rebuild_ms` are absolute and depend on the VM.
    - **Do:** in three to five separate cloud sessions, run `sh scripts/bench_cross_lang.sh --check-thresholds` on the same commit and record each measure, the CPU model (`/proc/cpuinfo`) and the load. Report the spread of each measure against the gate's 15% tolerance. Delete the files the run writes under `bench/`; commit nothing but this task's text.
    - **Changed (2026-11-15):** its "Delete the files the run writes under `bench/`" no longer holds: a cloud run's rows are committed like any other, and with id:nxrav the question it measures is answered from `bench/gate_history.tsv` (rows of the cloud VMs' `host_id`).
    - **Sample 1 (2026-11-03, commit `289bddb`):** `Intel(R) Xeon(R) Processor @ 2.30GHz`, 4 vCPUs, 1-minute load average 2.46 at the start (a `make test` had just finished, so the host was not quiet). `clean_throughput_loc_s` 10177 (the run's own spread 288..297 ms, +3.1%), `incremental_rebuild_ms` 22, `runtime_ratio_vs_gcc_o2` 4.182, `peak_rss_mb_per_kloc` 2.973; the run took 42 s. Earlier on this same VM, an unrelated preflight recorded `clean_throughput_loc_s` 10072, 1.0% below this sample. That is one VM twice, not a spread between sessions.
    - **Sample 2 (2026-11-03, commit `289bddb`):** the same conversation, but on a freshly booted VM (booted 14:49 UTC, after the setup script changed), so not the VM of sample 1. `Intel(R) Xeon(R) Processor @ 2.30GHz`, 4 vCPUs, 1-minute load average 0.36 at the start. Run in a scratch worktree of `289bddb` whose `build/zoril` was built from that commit's compiler source and which rebuilt its own `zilc` and `zbuild`. `clean_throughput_loc_s` 9705 (the run's own spread 302..330 ms, +9.3%), `incremental_rebuild_ms` 20, `runtime_ratio_vs_gcc_o2` 4.095, `peak_rss_mb_per_kloc` 2.973; the run took 56 s. Against sample 1: clean -4.6%, incremental -9.1%, ratio -2.1%, RSS unchanged, all inside 15%. The bench outputs were deleted with the worktree.
    - **Still to do:** one to three more samples, each from a new cloud session on this commit. This task stays open until they exist; two samples are not a spread.
    - **Checks (for each new sample):**
      - C1: the session is new: the VM's boot time (`uptime -s`) differs from every earlier sample's; quote it.
      - C2: the commit is `289bddb`, in a scratch worktree whose `build/zoril`, `build/zilc` and `build/zbuild` were built from it (as sample 2 did); quote `git -C <worktree> rev-parse --short HEAD`.
      - C3: the CPU model (`grep -m1 'model name' /proc/cpuinfo`), the vCPU count, and the 1-minute load average before the run; quote them.
      - C4: `sh scripts/bench_cross_lang.sh --check-thresholds`: the four measures and the run's own spread line, quoted as samples 1 and 2 are.
      - C5: `git status --short bench/` after deleting what the run wrote prints nothing.
      - C6: once three or more samples exist: a table of each measure's minimum, maximum and spread against the 15% tolerance.

- [ ] +bench +decision +AI-G @main id:z0005 Decide the benchmark gate's behaviour on a host without a committed baseline
    > **Created:** 2026-11-03
    > **Branch:** `main`
    > **Depends:** id:z0004

    - **Options, from the measurement:** commit a baseline for the measures whose spread stays inside the tolerance; make the gate print a `[SKIP]` naming the reason for those that do not; and when no committed baseline exists, have the gate say so instead of recording one and passing.
    - **Recommendation (2026-11-03, until id:z0004's spread data decides it):**
        1. A host with no committed baseline gets a statement, not a pass. The gate stops recording a baseline on a first run and then printing "All performance thresholds within tolerance"; it prints `[SKIP] bench-thresholds: no committed baseline for <axis> (<reason>)` per axis and exits 0. Recording stays an explicit act (`sh scripts/bench_cross_lang.sh --record`).
        2. Commit a baseline for `runtime_ratio_vs_gcc_o2` only (4.182 in id:z0004's sample 1): it is relative to gcc -O2 on the same host, so it moves with the compiler and not with the VM. It is committed once id:z0004's samples keep its spread inside the 15% tolerance; otherwise it gets the `[SKIP]` too.
        3. `clean_throughput_loc_s` and `incremental_rebuild_ms` stay host-local. A host that has recorded its own baseline (a developer's machine) still compares against it; anywhere else they print `[SKIP]` naming "absolute measure, no baseline for this host".
    - **Why:** on a fresh VM the present gate compares a run with itself, so it cannot fail, and it says "within tolerance" anyway. A committed absolute baseline would pass or fail with the VM's speed, which tests the VM. id:z0004's single sample says nothing yet about other VMs; rule 2 is the part its data can overturn.
    - **Not done here:** the change to `scripts/bench_threshold_check.sh` and its tests. It needs a task of its own once id:z0004 has its samples.
    - **Reopened (2026-11-03):** the decision depends on id:z0004's measurements, so the task stays open until they exist; the recommendation above is not a decision yet.
    - **Tag (review, 2026-11-07):** a decision is `+AI-D` work (`AGENTS.md`, "Model tags"): this task is taken by an `+AI-D` session or the maintainer, whatever its title line says. The implementation it names under **Not done here** becomes an `+AI-G` task with numbered checks when it is written.

- [ ] +safety +AI-G @main DN1b Mark parameter drop-flag locals with is_drop_flag = true in ZIR lowering id:1a4tv
    > **Created:** 2026-11-15
    > **Context:** by id:3rata (DN1).
    > **Branch:** `main`

    - **Placed:** in `future.tm.md` under `main` branch items as a follow-up to id:3rata; blocks DN1c (id:h1acv). Awaiting maintainer scheduling into `active.tm.md`.

    - **Found (2026-11-15, during id:3rata):** `define_params` in `src/lower_zir/decl.zrl:1019-1026` allocates parameter drop-flag locals via `self.define_local(0 as *mut Symbol, bool_ty, LOCAL_KIND_LETMUT)` and assigns `self.local_drop_flag[i] = flag`, without setting `self.locals[flag as usize - 1 as usize].is_drop_flag = true` (unlike `define_local` at `src/lower_zir/decl.zrl:658`). Every non-Copy parameter drop flag (including `Drop::drop(self: T)` in `stdlib/io.zrl`, `stdlib/mem.zrl`, `stdlib/fsys.zrl`) lacked `is_drop_flag = true`.
    - **Do:** in `src/lower_zir/decl.zrl` (`define_params`, right after line 1023), set `self.locals[flag as usize - 1 as usize].is_drop_flag = true;`. Add a unit/compiler test verifying that parameter drop-flag locals on a function taking a `Drop` struct by value have `is_drop_flag == true` in ZIR (or that a function taking a by-value `Drop` parameter passes the DN1 check / `--emit-zil` without treating its parameter drop flag as user storage).
    - **Checks:**
      - C1: new test verifying parameter `is_drop_flag = true` passes via `./scripts/test.sh <new_test>` (and fails when the line in `define_params` is taken out).
      - C2: `make test`, quoting `Total:`.
      - C3: `make preflight-changed`, quoting fixpoint, clean-tree build, mutations, and `Total:`.

- [ ] +safety +AI-G @main DN1c Add DN1 lowered-ZIR drop/move/destroy invariant verifier in check_zir.zrl id:h1acv
    > **Created:** 2026-11-15
    > **Context:** by id:3rata (DN1).
    > **Branch:** `main`
    > **Depends:** id:1a4tv

    - **Placed:** in `future.tm.md` under `main` branch items directly after DN1b (id:1a4tv), as the implementation decided by id:3rata. Awaiting maintainer scheduling into `active.tm.md`.

    - **Why (from id:3rata):** `ZirVerifier`'s ownership lattice checks source-level locals (`place.projections.len == 0`) but does not verify that `ZirStmt.Drop` / `DropIfLive` and drop flags emitted by `src/lower_zir/` drop or move every `!is_copy` / `needs_drop_flag` value on every CFG path.
    - **Do:** implement the static DN1 drop/move/destroy verifier in `src/check_zir.zrl` as an internal compiler error (diagnostic prefixed `[DN1 Inv-*]` naming the local) so `zoril` refuses any lowered ZIR violating:
      1. `[DN1 Inv-DoubleDrop]` — `Drop` on a non-live place (`DropIfLive` permitted only under synced live or `!flag_synced` guarding).
      2. `[DN1 Inv-DropLeak]` — any `!is_copy` local/place (with `Drop` / `DropIfLive` drop flag, excluding `variant_no_drop` / Copy variants) reaching `Ret` neither moved nor dropped.
      3. `[DN1 Inv-DropDecompose]` — moving or dropping a payload out of a value whose type implements `Drop`.
      4. `[DN1 Inv-DropBorrowed]` — `Drop` / `DropIfLive` on a place while an active borrow overlaps it (`state.borrows`).
      Include the five lowering-compatibility rules validated during id:3rata's prototype:
      - Track `variant_no_drop` (`VariantCheck` branch state + `dn_vcheck_nodrop`) so `lower_try_expr`'s `Assign(flag, 0)` on Copy variants and `Ret(x)` when `ret_ty == op_ty` pass cleanly.
      - Resolve nested enum payload roots in `dn_projection_root` through intermediate pointer temporaries (`tmp2 -> *tmp1 -> e`, depth < 8) without stopping early on `local_is_pointer(src.base)`.
      - Retire abandoned speculative `pending_src[k]` when `!self.is_live(k)` (and via `!live_out_of(pred_idx)` on `Branch(flag_e)`'s `else` edge when `flag_synced[owner]`).
      - Handle `PROJ_DEREF` move in `dn_on_place_move` when `flag == DM_DEAD_0`.
      - Keep `match *stmt` exhaustive (`ZirStmt.Intrinsic` / `ZirStmt.EndBorrow` explicit, zero wildcard warnings).
      Also add a planted/unit verifier test (or compiler self-test / unit test invoking a deliberately broken lowered pattern or verifying zero warnings and full-tree acceptance) and measure `src/main.zrl` compile time vs baseline (prototype overhead was `+0.409s` / `+12.9%`, `3.170s` -> `3.579s` median).
    - **Checks:**
      - C1: zero compiler build warnings on `make`; self-hosting fixpoint identical across two self-hosted generations (`make preflight-changed`).
      - C2: unit/regression test exercising the DN1 verifier passes (`./scripts/test.sh <test>`), and taking out each invariant or adding a deliberate lowered-ZIR violation triggers `[DN1 Inv-*]`.
      - C3: quote median compile time of `timeout -k 5s 30s ./build/zoril --emit-zil -o /dev/null src/main.zrl -I stdlib=stdlib -I src -I build/gen` over 3 runs before and after.
      - C4: `make test`, quoting `Total:`.
      - C5: `make preflight-changed`, quoting fixpoint, clean-tree build, mutations, and reject-diff.

- [ ] +diagnostics +AI-D A `match` of about a thousand arms aborts the compiler: the exhaustiveness checks take quadratic time and exhaust the 4 GiB arena id:1cgc9
    > **Created:** 2026-11-18

    - **Found by:** id:7kbpd, while measuring the cost of id:z0089's row copy (the copy changes neither figure: the compiler built from `1033c46~1` gives the same times and the same abort).
    - **Now:** a `match` over a `(E, E, E, E, E)` tuple, `E` a six-variant enum, with one arm per `(E.a, E.b, E.c, E.d, _)` and a final `_`, compiles in 189 ms at 200 arms, 726 ms at 400 and 2689 ms at 800. At all 1296 arms the compiler aborts (exit 134) after 5.8 s with `ArenaHeader overflow (capacity: 4294967296, offset: 4294962240, requested: 6484)`. With or-patterns in two columns (`(E.a, E.b | E.c, E.d, _, E.A | E.B | E.C)`), 800 arms already abort. A generated `match` (a lexer or opcode table) of this size is plausible, and the abort is not a diagnostic.
    - **Reproducer** (POSIX `sh`; `N` arms, then `timeout 300 build/zoril -I stdlib=stdlib -o /tmp/u.out /tmp/u.zrl`):
      ```
      N=1296; { echo 'enum E { A, B, C, D, F, G }'; echo 'fn f(x: (E, E, E, E, E)) -> i32 {'; echo '    match x {'
      i=0; for a in A B C D F G; do for b in A B C D F G; do for c in A B C D F G; do for d in A B C D F G; do
      [ $i -lt $N ] && echo "        (E.$a, E.$b, E.$c, E.$d, _) => 1,"; i=$((i+1)); done; done; done; done
      echo '        _ => 0,'; echo '    }'; echo '}'; echo 'fn main() -> i32 { return f((E.A, E.B, E.C, E.D, E.F)); }'; } > /tmp/u.zrl
      ```
    - **Lead, not yet verified:** `warn_unreachable_arms` runs `exh_useful` once per arm against every arm before it, and each call specialises (copies) every row at every level in `self.arena`, which is never reclaimed during a function's lowering. So both the time and the memory grow with arms² × columns. Diagnose first: measure where the arena goes (per pass: `warn_unreachable_arms`, `lint_wildcard_arm`, `check_match_exhaustiveness`), then decide between a scratch arena reset per arm, sharing unchanged row tails, and a size limit past which the check gives up quietly (as `depth > 32` already does). The provenance rules constrain `src/lower_zir/exhaust.zrl` (see id:z0089 and id:z0085).

## `testinfra` branch: the test runner in Zoril and test-path portability, paused (from `active.tm.md`, 2026-11-14)

Paused by the maintainer on 2026-11-14 in favour of open soundness holes. These tasks finish replacing `scripts/test.sh`'s parallel pool with `build/ztest` and remove the test path's last non-portable tools (`AGENTS.md`, Portability: `flock`, `mkfifo`, `setsid`, `xargs -P`, `read -t`), then make the runner more convenient. None of them fixes a bug. As paused, `make test` runs `test.sh`'s pool, and `make test RUNNER=ztest` runs the same plan one item at a time. Moved here in their order, with their check-ins and milestone merges.

- [ ] +safety +stdlib +tests +AI-D @testinfra id:z0133 Z1d Signals: the runtime records which arrived, and a stdlib module reads it
    > **Created:** 2026-11-07
    > **Context:** by id:z0117.
    > **Branch:** `testinfra`
    > **Depends:** id:z0135
    > **Check-in:** it touches `rt/`.

    - **Cross-branch dependency (2026-11-10):** id:z0135 is a `main` task. Start this one only once id:z0135's commit is on `testinfra` (`git merge-base --is-ancestor <sha> testinfra`); merging `main` into `testinfra` is the maintainer's decision.
    - **Review (2026-11-11), for the maintainer:** id:z0135's header gives "they edit closure modules" as the reason it comes before this task, but the **Do** below puts the new module outside the `src/` closure and edits `rt/runtime.s` (with its `bootstrap/stage1/rt/runtime.s` copy), which is not a closure module. If the handler adds symbols only and changes none that stage1 emits, this task may not need id:z0135 either; that is the maintainer's call, since the runtime is linked into the compiler stage1 builds. Until it is made, the dependency stands.

    - **Do:** in `rt/runtime.s`, a handler that sets a bit per signal number in a runtime word and returns (with the `sa_restorer` that Linux x86_64 `rt_sigaction` needs); nothing else runs in it. A stdlib module (new, outside the `src/` closure) with `watch(sig)` (install the handler), `ignore(sig)`, `default(sig)` and `take_pending() -> u64` (read and clear the bits atomically). `bootstrap/stage1/rt/runtime.s` stays a byte-identical copy of `rt/runtime.s` (the `runtimes` gate), and `rt/runtime.s` keeps every symbol the pinned stage1 can emit. State in `doc/spec/safety_model.md` what the module claims, if anything, with its test.
    - **Checks:** a test that watches SIGUSR1, sends it to itself, and reads it once from `take_pending` and not twice; a child that watches nothing still gets the default action. `scripts/run_safety_matrix.sh`. `make test`, `make preflight-changed`. Ends with **Awaiting review**.

- [ ] +stdlib +portability +tests +AI-D @testinfra id:z0134 Z1e The environment read from the startup stack, not `/proc/self/environ`
    > **Created:** 2026-11-07
    > **Context:** by id:z0117 (decision 5).
    > **Branch:** `testinfra`
    > **Check-in:** it touches `rt/`.

    - **Before:** id:z0140.

    - **Do:** `_start` in `rt/runtime.s` records `envp` beside argc and argv (the hosted entry likewise); `getenv` in `stdlib/fsys.zrl` reads it instead of `/proc/self/environ`, so it works where `/proc` is absent. `fsys.zrl` is in the `src/` closure: build through stage1 too. `bootstrap/stage1/rt/runtime.s` stays a copy.
    - **Checks:** a test whose parent sets one variable, sets another to the empty string and leaves a third unset, and that `getenv` returns the value, the empty value and none for them. Where `unshare` can mount a namespace without `/proc`, the same test passes there (skip, saying why, where it cannot). `make test`, `make preflight-changed`. Ends with **Awaiting review**.

- [ ] +testinfra +tests +AI-G @testinfra id:z0138 Z2c `ztest` runs N items at once and becomes the default
    > **Created:** 2026-11-07
    > **Context:** by id:z0117.
    > **Branch:** `testinfra`
    > **Depends:** id:z0131, id:z0133, id:z0137

    - **Do:** a pool of `--jobs` items (default `nproc_count`'s answer, passed in by the Makefile), each in its own process group (id:z0131), started slowest first from the last `timings.tsv`, printed in plan order as each finishes; fail-fast stops new items and kills the running groups; `SIGINT`/`SIGTERM` (id:z0133) kills every group and exits 130; a work-directory lock as `test.sh`'s (`fsys.zrl` `acquire_file_lock`). `make test` uses `ztest` by default; `RUNNER=sh` keeps `test.sh`.
    - **Added at check-in id:0f0vv (the reviewer, 2026-11-13):**
      - (1) The pool ends a group before it reaps the group's leader. It polls with `has_exited` (id:trx5h) and sends `kill_group` before `wait` on a timeout, on fail-fast and on SIGINT or SIGTERM. Otherwise, a member that ignores SIGTERM outlives its shell, which is the review's finding 3.
      - (2) The running items are one slice for `try_wait_any`, which after id:ppvzh reaps only what it is given. An error from it is not an ended item.
      - (3) The per-item timeout and its `[FAIL]` line stay as id:655rf made them.
      - (4) The Makefile's name for the old runner is `RUNNER=test.sh`, as id:z0137 made it, not `RUNNER=sh`.
      - (5) C6's before-figures for `test.sh`, at `testinfra` git:6122499: `Total: 3269 run, 3269 passed, 0 failed, 94 skipped (207.8s)` on `taskset -c 0-3` (with `TR_JOBS=4 MUTATION_JOBS=4`), about 115 s on all 16 threads, and 465 s for the serial `ztest`.
      - (6) Added at check-in id:drcga: the pool polls with `try_wait_any` (or `has_exited`), never `wait_any`. `wait_any` returns ECHILD on every call while any other child of the process (the planner, the stray-files script) has ended and is not reaped, even with pool items still running (id:rvn2w); `try_wait_any` waits by pid and is not affected.
    - **Checks:**
      - C1: full runs of both runners with `--results`; `sort` and `diff` of the two files prints nothing; quote both `Total:` lines.
      - C2: a scenario that starts `make test RUNNER=ztest` in the background, sends it SIGINT after 20 s, and then finds no process left whose command line names `build/zoril`, `build/zilc`, `qbe` or a test file (`ps -eo pid,args`); exit status 130; quote it.
      - C3: the same with SIGTERM.
      - C4: two runs on one `TR_WORK`: the second refuses with today's message (`another test run is using`); `sh scripts/test_test_lock.sh` passes against `ztest`.
      - C5: `--fail-fast` with a planted failing test early in the plan: no item starts after the failure is printed, and the running ones are killed (no process left, as in C2).
      - C6: wall time of `make test` with each runner, on all CPUs and with `taskset -c 0-3`; record the four figures here.
      - C7: take the process-group kill out (a scratch edit) and watch C2 fail; restore.
      - C8: `make test` and `make preflight-changed`, each `Total:` line quoted.

- [ ] +testinfra +review +AI-D @testinfra @checkin Review of Z2c (`ztest` runs N items at once and is the default) id:bfhmm
    > **Created:** 2026-11-13
    > **Context:** placed by the reviewer at check-in id:0f0vv
    > **Branch:** `testinfra`
    > **Depends:** id:z0138

    - **Placed:** directly after id:z0138, the task it reviews

    - **Review:**
      1. Re-run id:z0138 C2, C3, C5 and C7, the signal, fail-fast and take-out checks.
      2. Probe a SIGINT that arrives while the plan is being read and while an item's output is being printed. Probe an item that leaves a process running after it ends normally. Probe a pool child reaped by a `wait()` elsewhere (id:ppvzh).
      3. Re-run C1, the results of both runners. Record C6's four wall times in the sprint notes' **Speed so far**.
      4. Run `build/ztest` from a source tarball (`make dist-check`) and with stdin from `/dev/null`.
      5. Record the findings here as numbered bullets, add follow-up tasks, then `tm validate` and `tm done` this task. id:ehcd2, the merge of milestone Z2c, is next.

- [ ] +testinfra +merge +AI-D @testinfra Merge `testinfra` into `main` at milestone Z2c: `ztest` is the default runner id:ehcd2
    > **Created:** 2026-11-13
    > **Context:** placed by the reviewer at check-in id:0f0vv, at the maintainer's request for merge points
    > **Branch:** `testinfra` into `main`
    > **Depends:** id:bfhmm

    - **Placed:** directly after check-in id:bfhmm, the review of milestone Z2c

    - **Why:** Z2c makes `ztest`, which runs items in parallel, the default runner for every `make test`, with `RUNNER=sh` keeping `test.sh`. From then on every branch runs its tests through the Zoril runner, so `main` should have it as soon as it is reviewed: a runner that differs between branches makes their results hard to compare. id:z0187's list names this milestone: "then `ztest` as the default (id:z0138)".
    - **The merge is the maintainer's.** Prepare it with id:9nnvq's steps 1 to 4. On the merge commit, also run `make test RUNNER=sh` and quote its `Total:` line, so both runners are shown passing on `main`. The cloud VM figure in `AGENTS.md` ("Cloud sessions") is re-measured or marked as measured before the change.

- [ ] +testinfra +tests +AI-G @testinfra id:z0139 Z2d The per-file pipeline in `ztest`, compared file by file with the `sh` one
    > **Created:** 2026-11-07
    > **Context:** by id:z0117.
    > **Branch:** `testinfra`
    > **Depends:** id:z0138

    - **Do:** `ztest` reads each test's header directives (`// expected exit`, `// expected compile fail`, `// EXPECT:`, `// expected compile success`, `// flags:`, `// link:`, `// @skip:`) and runs zoril, zilc, qbe, as, ld and the program itself, with `ZORIL_CC` and the other tool variables honoured, instead of starting `sh` per file. The `sh` pipeline stays as the fallback.
    - **Added at check-in id:0f0vv (the reviewer, 2026-11-13):** id:bekxx's header grammar is the specification for the in-process pipeline: the same forms, conflicts and `[FAIL] FILE (malformed header, line N: TEXT)` line. The cases of `scripts/test_test_headers.sh` join C2, run through both pipelines.
    - **Checks:**
      - C1: the comparison mode runs both pipelines on every per-file test of `tests/` and `corpus/` and fails on any difference in verdict or detail lines; quote its summary (files compared, differences: 0).
      - C2: one planted fixture per header directive (`// expected exit`, `// expected compile fail`, `// EXPECT:`, `// expected compile success`, `// flags:`, `// link:`, `// @skip:`) whose expectation is wrong: both pipelines report it the same way; quote each pair.
      - C3: `ZORIL_CC`, `ZILC_BIN`, `BACKEND_BIN`, `ASSEMBLER_BIN` and `LINKER_BIN` each pointed at a wrapper that logs its calls: the log shows `ztest`'s pipeline used each.
      - C4: `sh scripts/test_mutation_check.sh` passes (it runs the suite with mutant compilers).
      - C5: the per-file groups' wall time before and after, on all CPUs and with `taskset -c 0-3`; record the figures.
      - C6: `make test` and `make preflight-changed`, each `Total:` line quoted.

- [ ] +testinfra +review +AI-D @testinfra @checkin Review of Z2d (the per-file pipeline in `ztest`) id:ayytb
    > **Created:** 2026-11-13
    > **Context:** placed by the reviewer at check-in id:0f0vv
    > **Branch:** `testinfra`
    > **Depends:** id:z0139

    - **Placed:** directly after id:z0139, the task it reviews

    - **Review:**
      1. Re-run id:z0139 C1 (the file-by-file comparison) and C2 (planted fixtures), including id:bekxx's malformed headers: the two pipelines must refuse the same headers with the same `[FAIL]` line.
      2. Probe the tool variables of C3 with a wrapper that fails, not one that only logs.
      3. Record C5's figures in the sprint notes' **Speed so far**.
      4. Record the findings here as numbered bullets, add follow-up tasks, then `tm validate` and `tm done` this task.

- [ ] +testinfra +portability +tests +AI-G @testinfra id:z0140 Z2e Retire `test.sh`'s pool: no `flock`, `mkfifo`, `setsid`, `xargs -P` or `read -t` on the test path
    > **Created:** 2026-11-07
    > **Context:** by id:z0117.
    > **Branch:** `testinfra`
    > **Depends:** id:z0138, id:z0139, id:z0134

    - **Depends note:** a release cycle of `ztest` as the default with no disagreement.

    - **Do:** remove the pool, the dispatcher and their dependency checks from `scripts/test.sh`, keeping `scripts/lib/test_runner.sh` and a serial fallback over `tests/smoke.list` (`make test-fallback`), which `make test` runs, saying so, when `build/ztest` cannot be built. Remove `flock`, `mkfifo` and `setsid` from `scripts/check_deps.sh`'s `test` set. Update `AGENTS.md` "Running tests" and `doc/developer_guide.md`.
    - **Added at check-in id:0f0vv (the reviewer, 2026-11-13):** two more dependency lists name the pool's tools: `README.md` (the note under "Build Commands", and the `make test` line) and `doc/dependencies.md`. This task updates them with the others, and C4 checks them too. id:356sn, the merge after check-in id:jhcdc, checks them again.
    - **Portability rule (the maintainer, 2026-11-07):** this task removes the pool's entries from the exceptions list in `AGENTS.md` (Portability) and `doc/developer_guide.md` §1, and id:z0145's gate then runs `make test` without `flock`, `mkfifo` and `setsid` on `PATH`. The reason for the series is recorded there: the harness reaches macOS and Windows through Zoril tools, not through more `sh`.
    - **Checks:**
      - C1: `grep -n 'flock\|mkfifo\|setsid\|xargs -P\|read -t' scripts/test.sh scripts/lib/test_runner.sh` prints nothing; quote it.
      - C2: `make test` with a `PATH` shim that leaves out `flock`, `mkfifo` and `setsid` (`path_without` from `scripts/lib/path_shim.sh`): passes; `Total:` line quoted.
      - C3: with `build/ztest` made unbuildable (a scratch syntax error in `tools/ztest/`), `make test` says it is falling back and runs `tests/smoke.list` serially; quote the line that says so and the `Total:` line; restore.
      - C4: `sh scripts/check_deps.sh test` no longer names `flock`, `mkfifo` or `setsid`; the exceptions list in `AGENTS.md` (Portability) and `doc/developer_guide.md` §1 no longer names the pool.
      - C5: `scripts/check_portability.sh` passes; `make test` and `make preflight-changed`, each `Total:` line quoted.

- [ ] +testinfra +review +AI-D @testinfra @checkin Review of Z2e (the pool retired) id:jhcdc
    > **Created:** 2026-11-13
    > **Context:** placed by the reviewer at check-in id:0f0vv
    > **Branch:** `testinfra`
    > **Depends:** id:z0140

    - **Placed:** directly after id:z0140, the task it reviews

    - **Review:**
      1. Re-run id:z0140 C2 and C3: the shim without `flock`, `mkfifo` and `setsid`, and the fallback.
      2. Run `make user-tools` and `make dist-check`.
      3. `grep -rn 'flock\|mkfifo\|setsid\|xargs' README.md doc/dependencies.md doc/developer_guide.md AGENTS.md scripts/check_deps.sh`: each line left names a use outside `make test`.
      4. Record the findings here as numbered bullets, add follow-up tasks, then `tm validate` and `tm done` this task. id:356sn, the merge of milestone Z2e, is next.

- [ ] +testinfra +merge +AI-D @testinfra Merge `testinfra` into `main` at milestone Z2e: the test path needs no `flock`, `mkfifo`, `setsid` or `xargs -P` id:356sn
    > **Created:** 2026-11-13
    > **Context:** placed by the reviewer at check-in id:0f0vv, at the maintainer's request for merge points
    > **Branch:** `testinfra` into `main`
    > **Depends:** id:jhcdc

    - **Placed:** directly after check-in id:jhcdc, the review of milestone Z2e

    - **Why:** Z2e is the portability milestone the `ztest` series was written for (id:z0117). After it, a user's `make test` needs nothing beyond the user role's tools (`AGENTS.md`, Portability): no `flock`, `mkfifo`, `setsid` or `xargs -P`. Before the merge, check that every list of what `make test` needs says so:
      - the exceptions list in `AGENTS.md` (Portability), and `doc/developer_guide.md` §1;
      - `README.md` (the note under "Build Commands" and the `make test` line), and `doc/dependencies.md`;
      - `scripts/check_deps.sh`'s `test` profile.
      - Also check that `make user-tools` (`scripts/check_user_tools.sh`) runs `make test` with those tools off `PATH`. id:z0187's list names this milestone: "then the pool retired (id:z0140)".
    - **The merge is the maintainer's.** Prepare it with id:9nnvq's steps 1 to 4, plus `make user-tools` on the tip being merged, its `[PASS]` lines quoted.

- [ ] +testinfra +tests +AI-G @testinfra id:z0109 T5 Run the serial parts in parallel, longest first
    > **Created:** 2026-11-06
    > **Branch:** `testinfra`
    > **Depends:** id:z0105

    - **Do:** from the profile, schedule items longest first using the last `timings.tsv`, keeping the display order. Run the stage0c `make` targets with `-j`. Run the preflight steps that share nothing at the same time; the bench step keeps its quiet-host rule. (The reject differential's caches are id:z0114.) Measure before and after on 16 cores and on 4.
    - **Narrowed by id:z0103 (2026-11-06):** the pool already dispatches the non-file items from the slow end of the plan first (F1), so longest-first saves little on 16 cores. What is left: the stage0c `make` targets with `-j`, and the preflight steps side by side. Any change to the pool itself waits for id:z0117 (the series' dependency rule).
    - **Review (2026-11-06):** depends on id:z0119 (it schedules from `timings.tsv`, which nested runs overwrite today). Measure "4" on a host pinned to 4 CPUs (`taskset -c 0-3`) or the cloud VM, not `-j 4` on 16 cores (id:z0120). Preflight steps side by side must keep the bench step's quiet-host rule and the order note above `CHECKED_CMD` in `scripts/preflight.sh`.
    - **Found (2026-11-06, the review):** `./scripts/test.sh --gates` run directly, with `bootstrap/stage0-c/build/zoril-c` out of date, fails `stage0c-unit`, `stage0c-docs`, `stage0c-error-locations` and `stage0c-functional` with `mv: cannot stat 'build/zoril-c.tmp': No such file or directory` / `make: *** [Makefile:122: build/zoril-c] Error 1`: each gate runs `make -C bootstrap/stage0-c <target>`, and they relink the same `$@.tmp` at once. `make test` hides it because `TEST_GATE_DEPS` builds stage0-c first. Running the stage0c targets with `-j` (this task) must build the binary once before the gates that share it, in `test.sh` as well as in the Makefile; a test runs the gates on a stale stage0-c binary and passes.
    - **Checks:**
      - C1: before the change, wall time of `make test` on all CPUs and with `taskset -c 0-3`, and of `make preflight-changed` on all CPUs; record the three figures.
      - C2: the stale-binary case: `touch bootstrap/stage0-c/src/main.c` (or the file the binary's rule depends on), then `./scripts/test.sh --gate stage0c-unit --gate stage0c-docs --gate stage0c-error-locations --gate stage0c-functional`: all pass, and the log has no `mv: cannot stat`; the same check is added as a scenario so `make test` runs it. Quote it.
      - C3: take the build-once step out (a scratch edit) and watch C2's scenario fail with the race; restore.
      - C4: the preflight steps run side by side, except the bench step: the timings file (`build/preflight-timings.tsv`) or the log's timestamps show no other step running while the bench step runs; `sh scripts/test_preflight.sh` passes.
      - C5: C1's figures again after the change; record them beside C1's.
      - C6: `make test`, `make preflight-changed` and `make preflight`, each `Total:` line quoted.

- [ ] +testinfra +tests +AI-G @testinfra id:z0110 T6 Test progress: what is running, a heartbeat, and grouped fast items
    > **Created:** 2026-11-06
    > **Branch:** `testinfra`

    - **Asked by:** the maintainer.

    - **Now:** a gate's lines appear only when it ends, and results print in plan order, so one slow item looks like a hang. This is worst on a slow host.
    - **Do:** on a terminal, print a line when a slow item starts (one that took over a few seconds last time, from `timings.tsv`, or any gate). Refresh one status line at least every 10 s: items done of total, the slowest still running and its elapsed time. Fold items that finish quickly into their group's count line. Off a terminal (a log, `make test 2>&1 | grep`), keep today's line-oriented output byte for byte, apart from optional start lines that the grep patterns in `AGENTS.md` ignore. POSIX `sh` only, no `tput` dependency beyond a plain `\r`. `scripts/test_runner_output.sh` covers both modes. `make test`.
    - **Waits for id:z0117 (id:z0103, 2026-11-06):** if a Zoril runner replaces `scripts/test.sh`, the progress output is written in it, once. If id:z0117 keeps `test.sh`, this task goes ahead as written. Either way it reads `timings.tsv`, so it follows id:z0119 (review, 2026-11-06).
    - **Settled (review, 2026-11-07):** id:z0117 chose the Zoril runner, so the progress output is written in `tools/ztest`, after id:z0140; `scripts/test.sh` does not get it.
    - **Checks:**
      - C1: off a terminal (`make test 2>&1 | cat > build/z110/plain.log`), `sh scripts/test_runner_output.sh` passes and every line of the log matches its grammar, apart from the start lines; quote the grammar check's result.
      - C2: `make test 2>&1 | grep -E '\[FAIL\]|^Total:'` lists the same lines as before the change, with a planted failing test; quote both.
      - C3: on a terminal (run under `script -q -c '<command>' build/z110/tty.log`, a contributor tool), with a planted test that sleeps 25 s: the status line is refreshed at least twice while it runs, and names it and its elapsed time; quote the refreshes from the log.
      - C4: a slow item (over 3 s last time, from `timings.tsv`) prints a start line on a terminal; a fast one does not.
      - C5: on a terminal, the fast items of a group are folded into its count line: count the `[PASS]` lines printed, fewer than off a terminal, and the count lines equal.
      - C6: `make test`, `Total:` line quoted.

- [ ] +testinfra +tests +AI-G @testinfra id:z0125 T14 `make retest-failed` reruns only the items that failed last time
    > **Created:** 2026-11-06
    > **Context:** by the review (id:z0103 listed it in its brainstorm, but neither ranked nor dropped it).
    > **Branch:** `testinfra`

    - **After:** id:z0117 (written in the runner that stays).

    - **Do:** read the last `--results` file, rerun its `FAIL` items (files by path, gates and scenarios by name) with fail-fast off, and print the usual contract. With no results file, or none failed, say so and exit 0.
    - **Settled (review, 2026-11-07):** the rerun writes its own results to `retest.results` beside the file it read and never overwrites that file, so a second `make retest-failed` reruns the same items.
    - **Checks:**
      - C1: a scenario that plants one failing and one passing test in a scratch directory, runs the suite over it with `--results`, then `make retest-failed`: exactly the failing test is rerun (`retest.results` has one line, naming it); quote it.
      - C2: the same with a failing gate (a fixture gate under `tests/runner/fixtures/`) and a failing scenario: each is rerun by name.
      - C3: no results file: the message says so and the exit status is 0; quote it.
      - C4: a results file with no failures: the message says so, exit 0.
      - C5: two `make retest-failed` in a row rerun the same items (the file read is unchanged; `cmp` before and after).
      - C6: `make test`, `Total:` line quoted.

- [ ] +testinfra +audit +AI-D @testinfra id:z0107 T3 Find redundant and obsolete tests
    > **Created:** 2026-11-06
    > **Branch:** `testinfra`
    > **Depends:** id:z0105

    - **Do:** list candidates, removing nothing yet. Look for: per-file tests whose normalised ZIL or diagnostic output equals another's; `stage0c-*` items that duplicate `make -C bootstrap/stage0-c` targets run elsewhere; tests of features or bugs whose code is gone (search each test's subject in `src/`); gates whose check another gate already makes. Also list the tests that only one person can say are needed, for the maintainer. Each candidate gets its evidence and what would be lost. Removals are a separate task, with `make test` totals before and after.
    - **Narrowed by id:z0103 (2026-11-06):** per-file tests cost about 34 ms each (F2), so duplicates among them save seconds. Look first at the gates, the 48 scenarios and the seven `stage0c-*` gates (about 400 items), whose times id:z0105 records. Per-file duplicates are still listed, but for clarity, not for time.

## Idiomatic Zoril in the compiler: an evaluation (requested by the maintainer, 2026-11-14)

The maintainer wants the compiler written in idiomatic Zoril as far as possible. Most of `src/` predates the features it could use: on 2026-11-14 it had 971 `unsafe`, 348 `@slice(` constructions, 72 lines of pointer arithmetic over arrays (`(args as usize + i * sizeof(Place)) as *mut Place`), 341 `0 as *mut` sentinels, and 581 `while` loops against 363 `for`. stage1 is not the main limit: of 12 idioms probed (id:z0135's follow-up, `build/z135/idiom/`), it accepted generic structs and `impl<T: Copy>`, traits with bounds, `?`, `if let`, `while let`, `for` over ranges and slices, `defer`, methods on enums and `Vec<T>` of a struct, and refused an expression-bodied closure (`|x: i32| x + k`) and a capturing closure passed as a `fn` value. Until id:jhy7v lands, the closure must also avoid moving a value with a destructor out of a `match` or through a by-value `self`. A re-pin to gain closures means porting all of `src/` to the stage0-C dialect by hand (`doc/bootstrap/two_stage.md` §3). The series is an evaluation first: it measures, pilots one module, and then the maintainer decides whether and how far to convert. A conversion, if decided, is its own series on its own branch.

- [ ] +idiomatic +audit +AI-D IZ1 Census: which low-level patterns src/ uses, where, and the idiom that would replace each id:d1zx4
    > **Created:** 2026-11-14
    > **Branch:** `main` (it reads and measures only; no code change)

    - **Placed:** first of the series: the census the pilot and the decision use.

    - **Do:** count, per file of `src/` and of the `stdlib/` modules in its closure (`--emit-deps`), each low-level pattern, and give for each the idiom that would replace it with one before-and-after example from the tree. Start from: pointer arithmetic over an array (`(p as usize + i * sizeof(T)) as *mut T`) where a `Vec<T>` or a slice index would do; `@slice(ptr, len)` built by hand; `0 as *mut T` as "none" where `Option<&T>` would do; integer tags and `u32` ids standing for an enum; `while` loops with a hand-kept index where `for` over a range or a slice would do; `unsafe` blocks, split into those a safe API would remove and those that are inherent (syscalls, the arena, the runtime ABI); and long `if`/`else if` chains over a tag where a `match` would do. Add any other pattern found while reading, such as hand-built strings where `fmt` would do.
    - **Also:** separate the code in hot paths from the rest, using one profile of `build/zoril` compiling `src/` (`perf` if the host has it, otherwise the `make preflight` benchmark's per-phase times), so the pilot can weigh speed where it matters.
    - **Checks:** C1 a table here: pattern, count, the files with the most, and one example each, with the commands that count them (POSIX `grep`/`awk`, recorded so they can be run again). C2 the hot-path list with the profile command and its output. C3 the patterns ranked by how much a rewrite would remove (`unsafe`, lines, marker density from `sh scripts/marker_density.sh`), with the reasoning.

- [ ] +idiomatic +audit +bootstrap +AI-D IZ2 Which idioms the pinned stage1 accepts and builds correctly, and what a re-pin would add id:b6rf9
    > **Created:** 2026-11-14
    > **Branch:** `main` (probes under `build/` only)
    > **Depends:** id:d1zx4

    - **Placed:** after IZ1: each idiom the census names is probed here.

    - **Already probed (2026-11-14, three-line programs through the stage1 pipeline `build/zoril-stage1` → `build/zilc-stage1` → qbe/as/ld, and through `build/zoril`):** accepted by both and correct: a generic struct with `impl<T: Copy>`, a trait with a generic bound and `for x in xs`, `?` on a `Result`, `if let`, `while let`, `for i in 0..5`, `defer`, a method on an enum with a `match` on `self`, and `Vec<P>` of a struct iterated with `for p in v.as_slice()`. Refused by stage1 and accepted by `build/zoril`: `let f = |x: i32| x + k;` (`error: expected {, but found identifier`; the block form `|x: i32| -> i32 { return x + k; }` is accepted) and a capturing closure passed as a `fn` argument (`capturing closure can only be bound with `let` or called directly`). Built wrongly by stage1: a value with a destructor moved out of a `match` or through a by-value `self` (id:z0135; fixed by id:jhy7v).
    - **Do:** probe every idiom IZ1 names, each on its own and in the shape IZ1's example has (a `Vec<T>` of the compiler's own structs, `Option<&T>` fields, a `match` over an enum of IR nodes), and for each record: accepted or refused by stage1, run result under both, and whether the ZIL stage1 emits is the same size within 10% (a fat lowering in generation 1 slows only the bootstrap; record it, it does not refuse an idiom). Then list what a re-pin would add (the refused idioms) and what it costs: a hand port of `src/` to the stage0-C dialect, about 47,000 lines today, against the complexity ceiling in `doc/bootstrap/two_stage.md` §4.
    - **Checks:** C1 each probe's program and both results here (the programs in the task text, under 10 lines each). C2 the re-pin answer: the idioms it adds, the code IZ1 counts that would use them, and an estimate of the port with its basis.

- [ ] +idiomatic +measurement +AI-D IZ3 Pilot: one module rewritten in idiomatic Zoril, measured against the original id:2pkz3
    > **Created:** 2026-11-14
    > **Branch:** a scratch branch off `main` (`idiomatic-pilot`), never merged: the pilot measures, it does not land
    > **Depends:** id:b6rf9

    - **Placed:** after IZ2: the pilot uses only idioms IZ2 shows stage1 builds correctly.

    - **Do:** pick one self-contained module of a few hundred lines that IZ1 ranks high (candidates: `src/pair_map.zrl`, `src/route_set.zrl`, `src/index_facts.zrl`, or one file of `src/fmt/`), and rewrite it in idiomatic Zoril with no change in behaviour. Measure before and after, on the same host, each the median of three runs: lines; `unsafe` count; `sh scripts/marker_density.sh <file>`; the time for `build/zoril` to build `src/` (generation 2) and for the stage1 pipeline to build it (generation 1); the size of `build/zoril`; the time for `build/zoril` to compile `corpus/` or the largest test program that reaches the module; `make test`'s `Total:` line. Note what the rewrite could not express and why (a stage1 refusal, a borrow rule, a missing stdlib API).
    - **Checks:** C1 the module, the reason it was picked, and the diff's size. C2 the before and after table with every command. C3 the fixpoint holds and `make test` passes on the pilot branch (`make preflight-changed PREFLIGHT_BASE=<main>`, its `Total:`, and `0 newly accepted` from the rejection differential with `REJECT_DIFF_NO_CACHE=1`). C4 the list of what could not be expressed.

- [ ] +idiomatic +decision +AI-D IZ4 The maintainer decides whether to convert src/, which patterns, in what order, and how each step is measured id:0v0fy
    > **Created:** 2026-11-14
    > **Branch:** `main`
    > **Depends:** id:2pkz3

    - **Placed:** after the pilot: the decision needs its figures.

    - **Do:** put IZ1 to IZ3's results to the maintainer in plain terms (what idiomatic code removes, what it costs in compile time and size, what stage1 cannot express), with a recommendation, and record the answers here: (1) convert or not; (2) which patterns, and which stay (hot paths, inherent `unsafe`); (3) in what order (by module, by pattern, or by what a change touches anyway); (4) what each step must show (the pilot's measures and their limits, such as "no more than N% slower"); (5) whether a re-pin is wanted for closures, given IZ2's cost; (6) the branch the conversion lives on and its milestones. If the answer is to convert, write the conversion series (one module or one pattern per task, each `+AI-G` with numbered **Checks:** including the pilot's measures and a take-out where a test can fail), and IZ5's checks.
    - **Checks:** C1 the six answers recorded with the maintainer's name and date. C2 the series written (or "none: the maintainer chose not to convert") and `tm validate` passing.

- [ ] +idiomatic +docs +AI-G IZ5 The compiler source style rules IZ4 settles, in doc/developer_guide.md, with a gate for each rule a script can check id:ap0hp
    > **Created:** 2026-11-14
    > **Branch:** `main`
    > **Depends:** id:0v0fy

    - **Placed:** after IZ4, which writes its checks; not ready until then.

    - **Do:** write the rules IZ4 settles into `doc/developer_guide.md` (a section on the compiler's own source: which idiom to use for each pattern, which `unsafe` is inherent, the stage1 limits that still apply), point to it from `AGENTS.md`'s **Editing** section in one sentence, and add a gate for each rule a POSIX script can check (for example a count that may only fall, recorded like `scripts/comment_budget.tsv`).
    - **Checks:** written by IZ4.
