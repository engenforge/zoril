# Planned Work

Deferred work, in the order it is expected to be taken up after `active.tm.md` empties. Move a task to `active.tm.md` before working on it.

## Deferred precision rules of the provenance series (from id:z0075)

Rules id:z0075 deferred: each root is seen today only in the tree's own code (changed at the sites instead) or in a few grid cells accepted as a precision bound. Take one up when user code, the grid or a test shows its class.

- [ ] +safety +tests +AI-D id:z0085 B1.9b A value copied out of a referenced collection is not an address into its buffer
    > **Created:** 2026-11-06
    > **Found by:** id:z0064 (root (d2)).
    > **Depends:** id:z0075
    > **Check-in:** stop for review after it.
    > **Deferred (2026-11-06, by id:z0075):** the root is seen only in `src`, at one site, which id:z0089 changes instead; none of the grid's or the tests' refusals is from it. Take this rule up when a user program, the grid or a test shows the class, with the reproducer below.

    - **Now:** a body summary's `ParamContents(i)` tie is mapped with `os_through_plus`, everything reached through the argument at any depth, including the buffer a referenced `Vec` owns. A function returning a `Vec` of elements copied out of `&rows` reads as returning addresses into `rows`'s buffer. In `src/lower_zir/exhaust.zrl`, `exh_expand_or` pushes `row` read out of `rows` and calls itself with `&out`, which makes its caller's result own fresh storage; in `exh_useful`, `rows`, `spec`, `def` and `same` then hold `Frame` and `Unknown`, and its summary becomes every parameter stored into every parameter and a global. 167 of `src`'s 195 warnings are "into a global" because of it.
    - **Reduction:** id:z0084's program with `if again { return self.expand(&out, false); }` added in `expand` before `return out;` (`build/z64/t/d3.zrl`): builds, exits 0, 7 warnings under `--provenance=warn`, with or without id:z0084's experiment. Twin: `expand` pushes a fresh copy (`let c = self.alloc(r.len); out.push(c);`): 0 warnings.
    - **Measured alone (id:z0064, a copy of `src/` with the same fresh copy at `exhaust.zrl:275`):** 195 to 185, and "into a global" 167 to 14; `exh_useful`'s summary becomes `ParamContents(0) -> Param(0) ParamContents(0)`.
    - **Decide first, then do:** a rule that adds knowledge (a tie by depth, or by type: a `[mut u32]` element cannot address a buffer of `[mut u32]` headers without `unsafe`), or the one-line code change at the site (id:z0075 says which route). A rule removes origins in effect, so the series rule and the rejection differential apply; probe a result that does point into the buffer (`fn first(v: &Vec<i32>) -> &i32 { return &v.as_slice()[0]; }`, then the `Vec` dropped or pushed to), which must keep it. `make test`, `make preflight-changed`, the store grid.

- [ ] +safety +tests +AI-D id:z0084 B1.9d Arena storage is named by the arena an argument reaches, not by the argument's address
    > **Created:** 2026-11-06
    > **Found by:** id:z0064 (root (d1)).
    > **Depends:** id:z0075
    > **Depends note:** (it decides whether over-rejections are fixed by rules).
    > **Check-in:** stop for review after it. Accepts more: the rejection differential and the series rule apply.
    > **Deferred (2026-11-06, by id:z0075):** the root is seen only in code that uses a raw arena (zbuild's manifest parsing, the compiler), which is `unsafe` already; id:z0090 changes zbuild's sites instead, and none of the grid's or the tests' refusals is from it. Take this rule up when safe user code shows the class, with the reproducer below.

    - **Now:** `os_call` (`src/check_zir.zrl`) names the storage of an arena-tied result by the arena argument's own origins (`arena_store = tao`), and `os_type_has(.., OS_Q_ARENA_REF)` answers yes for any reference that reaches an `ArenaHeader` through a field: `&mut ZirLowerer` (`arena: *mut ArenaHeader`), `&Vec<..>` (`raw`). So `self.f(&rows)` returning a Vec in `*self.arena` owns `Param(0)` (the struct `self` points at) and `Frame(rows)` (the local Vec). In zbuild, `parse_entry(&cols, arena)`'s result owns `Frame(cols)` (`tools/zbuild/src/manifest.zrl`), which gives all 25 of zbuild's warnings.
    - **Reduction** (`build/z64/t/d5.zrl`; builds, exits 0; 7 warnings under `--provenance=warn`, 0 with the experiment below):

    ```zoril
    import "vec.zrl";
    import "mem_raw.zrl";
    use vec::Vec;
    use mem_raw::{ArenaHeader, arena_init, zoril_allocator_alloc};

    struct Z { arena: *mut ArenaHeader }

    impl Z {
        #[borrows()]
        fn alloc(self: &mut Z, n: usize) -> [mut u32] {
            return unsafe { @slice(zoril_allocator_alloc(self.arena, ((n + 1 as usize) * 4) as u64) as *mut u32, n) };
        }
        #[borrows()]
        fn expand(self: &mut Z, rows: &Vec<[mut u32]>, again: bool) -> Vec<[mut u32]> {
            let mut out = unsafe { Vec::<[mut u32]>.new_in_raw(self.arena) };
            for r in rows.as_slice() { out.push(*r); }
            return out;
        }
        fn walk(self: &mut Z, rows_in: &Vec<[mut u32]>, depth: usize) -> bool {
            if depth > 3 as usize { return rows_in.len() == 0 as usize; }
            let rows = self.expand(rows_in, true);
            let mut same = unsafe { Vec::<[mut u32]>.new_in_raw(self.arena) };
            for r in rows.as_slice() {
                let nr = self.alloc(r.len);
                same.push(nr);
            }
            let spec = self.expand(&rows, false);
            if self.walk(&spec, depth + 1 as usize) { return true; }
            return self.walk(&same, depth + 1 as usize);
        }
        fn top(self: &mut Z) -> bool {
            let mut rows = unsafe { Vec::<[mut u32]>.new_in_raw(self.arena) };
            let row = self.alloc(1 as usize);
            rows.push(row);
            return self.walk(&rows, 0 as usize);
        }
    }

    fn main() -> i32 {
        let mut z = Z { arena: unsafe { arena_init(65536 as u64) } };
        if z.top() { return 1; }
        return 0;
    }
    ```

    - **Measured alone (id:z0064, a scratch compiler: in `os_call`'s `in_ties` branch under a body summary, `vs |= arena_store` only when the argument's type is a pointer straight to an `Arena` or `ArenaHeader`, else `vs |= tr`, what the argument reaches):** zbuild 25 to 0; `src` unchanged alone (id:z0085's root keeps its cascade going). A measurement, not a proposed rule: not probed for soundness.
    - **Do:** state the rule (an arena's storage is what the reference reaches, at the depth where the `Arena`/`ArenaHeader` is) in the design note §3, implement it, and probe the sibling routes per the series rule: the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer, an `&Arena` held in a struct field, an `Arena` held by value in a struct passed by reference, and `arena_reset` between the call and a read. `make test`, `make preflight-changed`, the rejection differential, the store grid.

- [ ] +safety +tests +AI-D id:z0091 An assignment to a local's field replaces the origins the field held
    > **Created:** 2026-11-06
    > **Found by:** id:z0075 (the grid's newly refused twins, read by root).
    > **Deferred (2026-11-06, by id:z0075):** accepted as a precision bound for now (id:z0065 records it in `KNOWN_ISSUES.md` §5); a removal rule, so it waits until the series' other rules are in.
    > **Check-in:** stop for review after it.

    - **Now:** a direct assignment to a field of a local (`carrier_tup.0 = src_val`) adds the new value's origins to the local and keeps the old field's: no strong update. The store grid's safe twins `{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{same_param,store_param_65}__{deref_out,field_out}__frame_ends` (18 cells) are refused under `--provenance` by "the callee stores an address of this frame into memory that outlives it (call store rule)": in `ref_local__tuple_slot__same_param__deref_out__frame_ends.twin.zrl`, `let mut carrier_tup = (&seed, 10); carrier_tup.0 = src_val; let carried = carrier_tup.0;` leaves `carried O={Param(1), Frame(seed)}`, and `stash_pair((out, carried))` stores `Frame(seed)` into the caller's `*out`. The cells are written by `sh scripts/check_store_grid.sh --dir DIR` (as `DIR/<cell>.twin.zrl`); run it with `ZORIL_CC` set to a wrapper that adds `--provenance`, as id:z0064 did.
    - **Do:** a strong update for an assignment straight to a local's own field, array slot or tuple slot (no pointer on the path, no loop joining the old value back in), stated in the design note §3. It removes origins, so the series rule applies: probe the field assigned on one branch only, inside a loop, through a `&mut` to the local, through a reborrow, and an element of a local array indexed by a variable (which must stay a weak update). Then remove the 18 cells' refusal and the `KNOWN_ISSUES.md` §5 entry. `make test`, `make preflight-changed`, the rejection differential, the store grid.

## The `Box` drop series (id:z0019 to id:z0028)

Today a `Box` is never freed and never runs its contents' `Drop` (`KNOWN_ISSUES.md` §5): a leak, which does not break memory safety. The series makes a `Box` free its allocation and drop its contents at scope end without ever shipping a free that some route can observe. **Invariants for every task in it:** (1) the leak stays the default until id:z0028; the freeing code is built behind an off-by-default option, `--box-free` (`zoril` and `zbuild`), so the tree is releasable after every task; (2) the routes that would observe a freed `Box` are closed first (id:z0019 to id:z0023), each a `+safety` change with probes, accepted twins and the rejection differential; (3) each task ends open with an `Awaiting review` bullet and is fix-reviewed by another model before the next starts; (4) the two drop predicates, `type_needs_drop_internal` (`src/lower_zir/utils.zrl`) and `zil_type_needs_drop` (`src/lower_zir_to_zil.zrl`), change together; (5) build warning-free under stage1 (`make preflight-changed`), keep the `if absent_type { return false; }` lines of both predicates textually intact (mutation anchors), add no `zoril_*` symbol in `src/` (`scripts/check_runtimes.sh`), and regenerate `corpus/zrl_whole_program_zil.sha256` in a commit of its own when output changes. **Order:** id:z0019 to id:z0023 in any order; then id:z0024 to id:z0028 in sequence.

- [ ] +types id:z0018 A10.1 A method call or an index through a reference to a `Box` is refused
    > **Created:** 2026-11-03
    > **Context:** An over-rejection with a clean diagnostic in both build modes.

    - `impl Point { fn sum(self: &Point) -> i64 { ... } }` then `fn f(p: &Box<Point>) -> i64 { return p.sum(); }` gives "cannot move out of borrow" (likewise `p.bump()` with `p: &mut Box<Point>`); `fn f(p: &Box<[i64; 4]>) -> i64 { return p[2]; }` gives "cannot index `&Box<[i64; 4]>`". `b.sum()` on a `Box<Point>` works.
    - **Do:** the method receiver and the index base auto-dereference through every reference and `Box` layer, as field access does (`peel_field_base`), with read and write tests in both build modes and a fuzzer shape.

- [ ] +safety +tests id:z0019 A11.1 A borrow derived from a `Box` ends with the `Box`
    > **Created:** 2026-11-03
    > **Series:** `Box` drop (above).

    - **Route:** `type_has_drop` (`src/check_zir.zrl`) answers false for a `Box`, so the scope-end rule does not treat a `Box` local as freeing anything, and a borrow derived from a `Box<Point>` can outlive the block that owns it. Harmless while a `Box` leaks; a use after free once it frees.
    - **Do:** reproduce first (a borrow kept past the `Box`'s block is accepted); make `type_has_drop` and its siblings in the scope-end rule (`local_type_has_drop`) count a `Box`. Probes: the escaping borrow (`compile_reject`); accepted twins for a borrow that ends inside the block and for a `Box` received as a parameter. `make test`, `make preflight-changed`, the rejection differential.

- [ ] +safety +tests id:z0020 A11.2 A closure may not move out through a captured `Box`
    > **Created:** 2026-11-03
    > **Series:** `Box` drop.

    - **Route:** a capture alias with a projection (`*b`, `b.f` of a captured `Box`) is not refused as a move out of a capture, so a closure can take the value out of a `Box` its environment still owns.
    - **Do:** reproduce first; refuse the move, keeping reads and borrows through the capture legal. Probes: the move (`compile_reject`); twins for a read, a borrow and a `Copy` field copied out. Verification as id:z0019.

- [ ] +safety +tests id:z0021 A11.3 A move out through a slice or an intermediate reference reports "cannot move out of borrow"
    > **Created:** 2026-11-03
    > **Series:** `Box` drop.

    - **Do:** reproduce each shape first (`let x = s[i]` with `s: &[Box<T>]`; `let x = *r.f` where `r.f` refers to an owning value); refuse with "cannot move out of borrow"; probes and `Copy` twins. Verification as id:z0019.

- [ ] +safety +tests id:z0022 A11.4 A partial move is detected through `Box` dereferences and array indices
    > **Created:** 2026-11-03
    > **Series:** `Box` drop.

    - **Route:** `reject_partial_move` (`src/lower_zir/decl.zrl`) stops at a `Box` dereference or an array index, so moving a field out of `*b` or `a[i]` and then using or dropping the whole is not refused.
    - **Do:** reproduce first; make the walk follow `Box` dereferences and array indices; probes for each, twins for moving the whole value and for `Copy` fields. Verification as id:z0019.

- [ ] +safety +tests id:z0023 A11.4b A `Box` cannot be forged with `@ptr_cast` or `@ptr_from_int`
    > **Created:** 2026-11-03
    > **Series:** `Box` drop.
    > **Decided:** refuse, matching `as` (`p as Box<i64>` is already refused).

    - **Now:** `unsafe { @ptr_cast<Box<i64>>(&x as *i64) }` compiles. Once a `Box` frees, the compiler-emitted drop of a forged one would unmap a stack or arena page.
    - **Do:** both intrinsics reject a `Box` target (and a type containing one by value) with the wording `as` uses; probes for both (`compile_reject`), twins for a raw-pointer target. Check how `stdlib/local_mem.zrl`'s `arena_init` builds its `Box<ArenaHeader>`. Verification as id:z0019.

- [ ] +tests id:z0024 A11.5 Lowering preparation for `Box` drops, with no change in behaviour
    > **Created:** 2026-11-03
    > **Series:** `Box` drop; after id:z0019 to id:z0023.

    - **Do (none changes output while `--box-free` is off):** (1) `find_drop_fn` (`src/lower_zir_to_zil.zrl`) stops peeling a `Box` as it peels a reference, and `Drop`/`DropIfLive` stop counting a `Box` as a plain pointer; (2) a `Box` temporary keeps its entry-block stack slot instead of being replaced by its SSA value, so a `Box` created in one branch dominates its scope-exit drop; (3) the `--box-free` option in `zoril` and `zbuild` (help, man pages, the toolchain stamp); (4) a way to run the suite with the option (a wrapper like `scripts/zoril-checked.sh`, or a variable the runner passes on), and a defined route for `--checked` together with it; (5) the option is part of every key the incremental build compares (the `.zri` and the ZIL hashes as well as the toolchain stamp).
    - **Verification:** `make test` with the corpus golden hashes unchanged, `make preflight-changed`.

- [ ] +safety +tests id:z0025 A11.6 Under `--box-free`, a `Box` runs its contents' drop and frees its allocation
    > **Created:** 2026-11-03
    > **Series:** `Box` drop; after id:z0024.

    - **Do:** under the option only, both drop predicates count a `Box`; the drop glue for `Box<T>` is a translation-unit-private ZIL function per `T`, registered before its body is emitted so a recursive type (`corpus/zrl/25_linked_list.zrl`) is an ordinary call; it runs `T`'s drop glue when `T` needs drop, then frees. Not through a standard-library function (compiler-emitted code cannot assume one is linked): emit the `munmap` system call inline and trap on failure, and under `--checked` reuse `emit_checked_heap_release` so a second free traps. A zero-sized `T` allocates and frees nothing.
    - **Moving out of a `Box` is refused under the option until id:z0026**, with an explicit error; the option also refuses moving a `Box` field out of an aggregate and `[box x; n]` with `n > 1`. `stdlib/local_mem.zrl`'s `Box<ArenaHeader>`: check that the header page is not unmapped twice.
    - **Tests (with and without the option):** drop counts into a `static mut` for scope end, early return, `break`, a move into a call, overwrite by assignment, `Option<Box<D>>`, `Box<Box<D>>`, a field, an array, the recursive list; a bounded-memory loop (3,000 boxes of 1 MiB stays small; skipped without `/proc`); a mutant that removes the option gate. `make test`, `make test-checked` with the option, `make preflight-changed`, the rejection differential with the option on and off.

- [ ] +safety +tests id:z0026 A11.7 Under `--box-free`, moving a value out of a `Box` copies it out before the allocation is freed
    > **Created:** 2026-11-03
    > **Series:** `Box` drop; after id:z0025.

    - **Do:** at every move site whose source is a `Box` dereference (`let`, assignment, struct, array, tuple and enum-variant construction, `box`, call arguments, receivers, `if`/`match` results, `return`, block tails), copy the value into an unnamed `let mut` local, free the allocation without dropping its contents, and clear the moved-from slot so its drop flag does not fire. Remove id:z0025's refusal.
    - **Tests:** each site with a drop-counted `T` and a `Copy` `T`, exiting with a value that is wrong if the copy or the free is wrong; `make test-checked` with the option. Verification as id:z0025.

- [ ] +fuzz +tests id:z0027 A11.8 The fuzzer and the checked build exercise `Box` drops
    > **Created:** 2026-11-03
    > **Series:** `Box` drop; after id:z0026.

    - **Do:** a generator builder in `scripts/fuzz/gen.lua` that boxes the drop-counted type and moves the box around (into calls, out by `*b`, into `Option`, `Box<Box<_>>`, a struct field), and a fuzzer mode that builds with `--box-free`; `make fuzz-prove` mutants that remove the `Box` case from one drop predicate and that skip id:z0026's copy-out. A short session with the option must be clean.
    - **Also:** audit `stdlib/` for raw-pointer reads that create a second owner (a `Vec`, `HashMap`, `ByteVec`, `String` or iterator returning an element by value without removing it); decide each (a move that clears the source, a copy only for `Copy` types, or a documented obligation) before id:z0028.
    - **Verification:** `make fuzz-prove`, the session, `scripts/test_fuzz_tools.sh`, `make test`.

- [ ] +safety +release id:z0028 A11.9 Make freeing the default, remove `--box-free`, and say in the documents that a `Box` is freed
    > **Created:** 2026-11-03
    > **Series:** `Box` drop; last.

    - **Do:** make the freeing unconditional and delete the option; regenerate the corpus golden hashes in a commit of their own; correct `doc/spec/surface_syntax.md` §3.3, `doc/tour.md` ("Heap Boxing"), `doc/language/walkthrough.md`, `doc/spec/safety_model.md` and `doc/SAFETY.md` §4.5; remove the `KNOWN_ISSUES.md` §5 entry; add a `CHANGELOG.md` line.
    - **Cost:** each `Box` is its own `mmap`, and the free is one `munmap` per drop; run the benchmarks before the flip and record the difference. A small-object allocator in the runtime is a separate task.
    - **Verification:** `make test`, `make test-checked`, `make preflight-changed`, the rejection differential, a short fuzz session; the fuzz record goes stale.

## Evidence and tooling

- [ ] +fuzz +safety +tests id:z0029 The fuzzer's mutation score: which compiler mutants the fuzzer kills
    > **Created:** 2026-11-03
    > **Depends note:** a full release-bar fuzz run, recorded (the maintainer's).

    - **Why:** zero fuzz findings bounds the fault rate only for programs the generator writes. The direct measure is whether it finds bugs known to exist: the mutants of `scripts/mutation-check.sh`, each one line of `src/` changed and each killed by the test suite.
    - **Do:** generalise `scripts/fuzz/prove_oracle.sh` (or add a sibling sharing its scratch-build code) to run a fixed pilot with any mutant's compiler; a mutant is killed when the run reports a fault, candidate or accepted mismatch. Size the pilot from a trial; a survivor is re-run at a larger range once. A `make fuzz-mutation-score` target printing killed/survived per mutant with the oracle that killed it.
    - **The result is a list, not a fix:** each survivor gets one line of why in `bench/fuzz/README.md`; widening the generator for one is its own task. `make fuzz-prove`, `scripts/test_fuzz_tools.sh` on a one-mutant fixture, `scripts/check_fuzz_fresh.sh --strict`.

- [ ] +tests id:z0030 H3 A golden for `zilc`'s output on `corpus/zil/`
    > **Created:** 2026-11-03

    - **Why:** the hand-written programs in `corpus/zil/` are checked by exit code only, so a change in what `zilc` emits that keeps the exit codes passes unseen; the front end's output on `corpus/zrl/` is pinned by `corpus/zrl_whole_program_zil.sha256`.
    - **Do:** a hash file beside it holding the SHA-256 of the SSA `build/zilc` writes for each `corpus/zil/*.zil`, checked where that file is checked (`scripts/test_incremental.sh`) and regenerated with `UPDATE_GOLDEN=1`; skip `// @skip:` files; fail on an empty golden; document it in `corpus/README.md`. Change one file's expected SSA and confirm the step names it. `make test`.

- [ ] +tests +portability id:z0031 D1 The dependency matrix as a few scenarios instead of one full `make test` per tool
    > **Created:** 2026-11-03

    - **Why:** `scripts/test_dep_matrix.sh` runs a full `make test` per optional and per configurable tool, one after another.
    - **Scenarios:** required tools only (every optional tool removed at once; each gate it affects prints `[SKIP]` with its reason); a typical user (`git` and `lua` present, the rest absent); a relocated toolchain (every configurable tool reached only through its variable); the minimal gcc-free bootstrap; each required tool missing (per tool, each fails within seconds); clang for the C-facing tests (`CC=clang`, skipped when absent). Keep the per-tool matrix behind `make deps-matrix FULL=1`. Split the `ffi-callback` test so only its GNU `__asm__` cases need the extension.
    - **Verification:** the scenario matrix green with its wall time recorded; a planted fault that only scenario 2 catches.

- [ ] +tools +portability +deps id:z0118 Build and test tooling without Lua: shell for glue, Zoril for everything larger
    > **Created:** 2026-10-15
    > **Context:** in the incubator repository this one spun out of; filed here 2026-11-06 by id:z0103, with its figures updated against this tree.
    > **Related:** id:z0117 (a test runner in Zoril), id:z0111 (git in the tests), id:z0031 (the dependency matrix).
    > **Context:** an assessment of shell against Lua for the tooling, and how Hare splits its C and Hare tooling, reviewed 2026-10-15 in the incubator (the document was not carried over).
    > **Decisions:** keep the direction, drop Lua from the repository. Its rule "move complex sed/awk work into Lua" is reversed: shell plus POSIX `awk` for small text work, Zoril for anything larger. C only on the seed side: tooling in the compiler repository must not add a C compiler to a side that otherwise needs only a previous Zoril, qbe, as and ld. The document's Hare and QBE specifics were unverified; the conclusion does not depend on them.
    > **Why Lua costs:** it is not in most BSD base systems, its binary name varies (`lua54`, `lua5.4`), and it is required by `make test` and `make preflight`, though not by `make` itself (the bootstrap and the compiler build never call it).

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
    > **Placed:** future file, under Evidence and tooling: not blocking, and not a one-session fix until the cause is known.

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

## Types, diagnostics and the standard library

- [ ] +generics +types id:z0032 G1 `impl<T: Copy> Source<T> for S` fails to bind `T` when it appears only in the trait's arguments
    > **Created:** 2026-11-03
    > **Context:** Rejected in both build modes.

    - **Reproducer:** `trait Source<T> { fn pull(self: &Self, fallback: T) -> T; } struct S { x: i32 } impl<T: Copy> Source<T> for S { fn pull(self: &S, fallback: T) -> T { return fallback; } } fn main() -> i32 { let s = S { x: 1 }; return s.pull(42) - 42; }` gives `type mismatch: expected &S, found bool`.
    - **Cause:** `impl_scope` (`src/mono.zrl`) binds an `impl`'s type parameters only by matching its target type. **Direction:** unify the trait's type arguments to bind the rest, mangle the bound arguments into the method name, and reject a parameter that appears in neither at the `impl` header.

- [ ] +generics +types id:z0033 G2 User `impl` blocks on `Box<T>` resolve at the `impl` and fail method lookup at the call
    > **Created:** 2026-11-03
    > **Context:** Rejected in both build modes.

    - **Reproducer:** `trait Priv { fn q(self: &Self) -> i32; } impl<T> Priv for Box<T> { fn q(self: &Box<T>) -> i32 { return 5; } } fn main() -> i32 { let b = box 7; return b.q() - 5; }` gives `no field 'q' on '&Box<i32>'`.
    - **Cause:** `impl_applies` (`src/mono.zrl`) matches only user types and primitives, not `Box`. **Decide first:** forbid `impl ... for Box<..>` with a clear diagnostic at the header, or allow it for local traits (mono, mangling, interface printing and the spec, symmetrically with `[T]`).

- [ ] +stdlib +portability id:z0034 F1 Portable random access to a file: `File.seek` and `File.read_at`
    > **Created:** 2026-11-03

    - **Now:** reading in pieces works (`Read::read` in a loop, `doc/tour.md` §7); random access is reachable only through `os_unix::lseek` (`stdlib/os/unix.zrl`), with a raw `i64` result and a numeric `whence`.
    - **Do:** `File.seek(pos: SeekFrom) -> Result<u64, Error>` with `enum SeekFrom { Start(u64), End(i64), Current(i64) }`, and `File.read_at(buf: [mut u8], offset: u64) -> Result<usize, Error>` (positional; `pread64` on Linux). Document them in `doc/spec/standard_library.md` and the man-page comments (`make man-gen`), and use them in `doc/tour.md` §7. Tests for each `SeekFrom` arm, `read_at` at 0, mid-file, at and past the end, a seek before 0, and the position left unchanged. `make test`, `make preflight-changed`.

- [ ] +audit +diagnostics id:z0035 A7.12 Separate compilation names a private generic item as missing, not as private
    > **Created:** 2026-11-03
    > **Context:** Both build modes reject the access; only the wording differs.

    - **Reproducers:** a private `fn priv_gen<T>` used from another module (whole-program: "it is private"; `zbuild`: "the module defines no 'priv_gen'"); a private generic method called from another module (whole-program: "cannot access private method"; `zbuild`: "no field 'priv_m' on 'S'").
    - **Cause:** `is_private_signature_fn` and `method_is_written` (`src/interface_print.zrl`) skip generic items. **Direction:** write unreferenced private generic functions and methods into the `.zri` as bodiless signatures, and check the resolver rejects calling them before instantiation; then narrow the `KNOWN_ISSUES.md` §4 entry.

- [ ] +stdlib +docs `proc.zrl`: say what a command given both `set_envp` and an `env_*` call passes to the child id:w8vmg
    > **Created:** 2026-11-13
    > **Context:** found at check-in id:mxt3d, reviewing id:z0132.
    > **Placed:** future file: a comment, not blocking anything.

    - **Seen:** `Command.spawn` (`stdlib/proc.zrl`) uses the environment `build_envp` builds whenever an `env_*` method ran, and then ignores the array `set_envp` set; neither doc comment says so. **Do:** say it in `env_set`'s and `set_envp`'s comments (or make `set_envp` clear the `env_*` state, which is a behaviour change to decide first), `make man-gen`, `sh scripts/test_man_pages.sh`.

## Decisions and hygiene

- [ ] +safety +decision +AI-D id:z0102 Whether `unsafe fn` gets a `fn` type of its own, callable only in `unsafe`
    > **Created:** 2026-11-06
    > **Found by:** id:z0095's review.
    > **Owner:** the maintainer's decision.

    - **Background:** since id:z0095 an `unsafe fn` becomes a plain `fn` value only inside `unsafe`, and that block claims the function is safe to call with every argument the `fn` type admits (`unsafe_policy.md` §1), the obligation a safe wrapper or a closure calling it in `unsafe` already carries (`build/z95r/d_wrapper.zrl`, `d_closure.zrl`: both compile and fault the same way as the coercion). An `unsafe fn(..) -> R` type would let a value keep the precondition, so each call through it is marked, as Rust's `unsafe fn` pointers are. It is a language feature: the parser, the type checker, monomorphization, `.zri` interfaces, and the stage1 closure (`src/` cannot use it until a re-pin).
    - **Choices:** keep the id:z0095 rule alone; add the type beside it (the coercion to a plain `fn` stays, in `unsafe`); or add the type and refuse the coercion. Measure first how many `unsafe fn` values the tree and the tests make (none in `src/`, zilc or zbuild as of id:z0095).

- [ ] +release +portability +decision id:z0036 R6 Make the toolchain's output identical on every Linux C library
    > **Created:** 2026-11-03
    > **Owner:** the maintainer's decision.

    - **Background:** `doc/reproducible_builds.md` ("Why the C Library, QBE and the Linker Matter"): QBE's `qsort` calls leave the order of equal elements to the C library, so QBE writes different, equivalent assembly under glibc and musl, and `ld` versions place `.note.gnu.property` differently. A tie-break on a stable key in QBE's three comparators plus `as -mx86-used-note=no` was measured to give byte-identical binaries on glibc and musl.
    - **Choices:** vendor QBE with the patch; send the tie-breaks upstream; or keep documenting that the published binaries reproduce on the release host only. The `as` flag (and `zbuild` passing it) is needed for either of the first two.

- [ ] +docs +research id:z0037 DOC1 Documentation for three readers: an assessment, no decisions
    > **Created:** 2026-11-03

    - **Observation:** users, contributors and scripts read the same safety pages, and gates match sentences in the prose (`scripts/check_safety_figures.sh` in `doc/SAFETY.md`, `scripts/check_safety_model.sh` in `doc/spec/safety_model.md`), so every figure must appear verbatim, which is part of why the pages are dense.
    - **Output:** a short assessment with two or three options (a plain-language user page; a contributor reference; data for scripts kept as data, with tables generated), each with its scope, effort and effect on the gates, plus one rewritten section as a sample. Stop for the maintainer's decision.

- [ ] +refactor id:z0038 H1 Remove the duplicate `import "io.zrl";` and `primitive_type_name` in `src/interface_print.zrl`
    > **Created:** 2026-11-03

    - `src/interface_print.zrl` imports `io.zrl` twice and defines a private `primitive_type_name` identical to `pub fn primitive_type_name` in `src/ast.zrl`, which it already imports. Delete the second import and the copy, and import `ast::primitive_type_name`. `make test`.

- [ ] +portability id:z0039 stage0-c's runtimes have no `.note.GNU-stack` section
    > **Created:** 2026-11-03
    > **Deferred:** stage0-c is frozen and fixed only when a bug blocks building stage1 or its own suites.

    - `bootstrap/stage0-c/lib/rt/runtime.s` and `sys_linux_x86_64.s` lack the section, so on a linker that defaults to an executable stack (binutils 2.42 on Ubuntu 24.04) the programs `zoril-c` links itself warn and get one. Only stage0-c's own test programs link them; stage1 is linked with `bootstrap/stage1/rt/runtime.s`, which has the section. Take this up if the warning ever fails a stage0-c suite.

## Compatibility matrix

Where Zoril has been tested, by operating system and architecture, recorded per release. **First priority:** Alpine Linux, Arch Linux and Debian (stable): between them they cover musl and glibc, and a `/bin/sh` that is BusyBox `ash`, `bash` and `dash`. **Second priority:** other systems (Ubuntu, Fedora, the BSDs once a port exists, other architectures once the runtime supports them), in an order revised as ports are prioritised. Today the runtime targets `x86_64` Linux only, so the architecture column has one value.

- [ ] +docs +portability id:z0050 CM1 Define the compatibility matrix and record the hosts already tested
    > **Created:** 2026-11-03
    > **Group:** the compatibility matrix (CM1 to CM4).

    - **Do:** a page, `doc/compatibility.md`, linked from `README.md`: one table per release, one row per host. Columns: operating system and version, architecture, C library, what `/bin/sh` is, the toolchain (`cc`, `qbe`, `as`/`ld` versions), and one result column each for `make test`, the user paths (`make dist-check` with `scripts/dist_user_paths.sh`) and `make repro-check` (two bootstraps from scratch give identical results; with `HASHES=`, they also match a release's hashes). A result is `pass`, `fail` (naming the task that tracks it), `skipped` (naming the reason, for example a missing optional tool) or `not run`. For the comparison with a release's hashes, a mismatch on a host whose QBE, binutils or C library differs from the release host's is expected (`doc/reproducible_builds.md`, "Why the C Library, QBE and the Linker Matter"): record it as `differs (toolchain)`, naming the differing tool, not as `fail`.
    - **Priority:** the page states the two tiers above, and that a first-priority system is tested before each release.
    - **Rows to fill now,** for the current release, from runs repeated on its commit (not from memory): Arch Linux and Alpine Linux, plus Ubuntu 24.04 (the cloud environment), as a second-priority row.
    - **Keep the page true:** a row says which release it was tested at; a release with no row for a first-priority system does not claim it.
    - **Verification:** `make test` (`md-check`, the table width rule); every result in the table has a run behind it.

- [ ] +portability +tests id:z0051 CM2 Test Debian (stable) and add its row
    > **Created:** 2026-11-03
    > **Depends note:** CM1.

    - **Do:** on Debian stable, x86_64: install the dependencies `scripts/check_deps.sh` names, then run `make test`, `make dist-check` and `make repro-check`, and record the row. `/bin/sh` is `dash`. Debian's packaged `scdoc` is older than the 1.11.5 the man-page check requires, so that check skips; record the skip and its reason.
    - **A failure** gets a task of its own, named in the row; this task records the result and does not fix it.
    - **Verification:** the row's three results, each from a run on the release commit.

- [ ] +portability +tests id:z0052 CM3 A recipe for adding a host to the matrix
    > **Created:** 2026-11-03
    > **Depends note:** CM2.

    - **Do:** a short section in `doc/compatibility.md`: how to install the dependencies on the host, which three commands to run, what to record, and how to report a result (a pull request with the row, or an issue linking the logs). After CM1 and CM2 this is written from three systems' experience, so it can be followed on a fourth without asking.
    - **Verification:** follow the recipe on one second-priority system and add its row.

- [ ] +docs +release id:z0053 CM4 The release checklist requires the first-priority rows
    > **Created:** 2026-11-03
    > **Depends note:** CM1.

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

Moved from the sprint, in their order there, when `active.tm.md` became one queue; the maintainer promotes from here. id:z0135, id:z0185, id:z0186, id:z0187 and id:z0188, also `main` tasks, stayed in the queue. The section's notes as they stood:

Standalone tasks developed and committed directly on `main`:
1. Default-mode safety holes: id:z0101 (`extern fn` as `fn` value, `gap_67`), id:z0100 (generic instance as `fn` value, `gap_66`).
2. Bootstrap integrity: id:z0135 (stage1 closure module paths audit; runs before closure module edits in id:z0131/id:z0133).
3. Compiler quality & tools: id:z0013 (reviewer rotation), id:z0014 (`zilc` input validation), id:z0015 (`zoril` error bounds), id:z0016 (`zbuild` ZIL handling), id:z0067 (diagnostic source location), id:z0079 (generic interface roundtrip), id:z0080 (mutation list integrity).
4. Benchmarks: id:z0004 (cloud session variance measurement), id:z0005 (baseline decision).
5. Rules and dependencies (2026-11-12): since 2026-11-11 id:z0135 no longer gates id:z0131 (its syscalls stay in `proc.zrl`, outside the closure); whether it gates id:z0133 is an open question on that task. `AGENTS.md` rules from the series review, which every branch reads: id:z0187 (milestone merges), id:z0185 (the closure command), id:z0186 (a planted case in the design of anything that skips work). They are `main` tasks because `AGENTS.md` changes stand alone; `testinfra` gets them by its next merge from `main`.

- [ ] +safety +tests +AI-D @main id:z0180 A generic `Clone` impl's result keeps the borrows of what it clones
    > **Created:** 2026-11-11
    > **Context:** by id:z0173.
    > **Branch:** `main`
    > **Branch note:** after the `vecclone` series merges (its probes are git:e7b4d6c on `vecclone`).
    > **Check-in:** stop for review after it: a fix to a safety rule.

    - **Found (2026-11-11, on `vecclone`; also on its base's stdlib):** `impl<T: Clone> Clone for Vec<T>` and `impl<T: Clone> Clone for Option<T>` declare `#[borrows()]`, so a clone holds no borrow: `return v.clone();` of a local `Vec<[u8]>` holding a view of a stack array, and `return o.clone();` of `Some(s)`, are accepted and read the dead frame (gap_77, gap_78, recorded in git:e7b4d6c: `exit 7` where the frame held 42). Returning `v` itself is refused (`cannot return 'v' a reference into storage owned by this frame`), and so are `s.clone()` of a slice directly (`region escape`), `clone_in`, and a `#[derive(Clone)]` struct holding the view (`region escape: returning a pointer to local stack storage via sret`). The same attribute hid the store from `extend_from_slice`'s summary once it cloned each element (probe 418 accepted); id:z0173 declares `#[stores(slice -> self)]` there instead.
    - **Route class:** a generic `#[borrows()]` impl whose result is built from a `T` that may be a view. Probe every generic `#[borrows()]` function in `stdlib/` (`rg -B3 '#\[borrows\(\)\]' stdlib`), not only `Clone`.
    - **Do:** decide what the result of a generic `#[borrows()]` function holds when `T` carries a borrow (Rust: the lifetime inside `T` stays in the result), and implement it; or drop the attribute from these impls if the default rule refuses no correct program the tests hold (the differential says). Flip gap_77 and gap_78.
    - **Checks:** C1 gap_77 and gap_78 `compile_reject`, and a `Vec<u8>` / `Option<i32>` clone returned from a function still accepted; C2 take the change out and watch them run (`exit 7`); C3 `scripts/check_reject_diff.sh` against the base, every newly refused program listed; C4 `make test`, `make preflight-changed`, each `Total:` quoted.

- [ ] +diagnostics +modular +AI-G @main id:z0181 An error inside an imported generic body names the source's line under `zbuild`
    > **Created:** 2026-11-11
    > **Context:** by id:z0173.
    > **Branch:** `main`
    > **Branch note:** after the `vecclone` series merges (gap_76's `// zbuild:` line is git:27d1d48 on `vecclone`).

    - **Found (2026-11-11):** `bench/safety_matrix/probes/gap_76_vec_extend_from_slice_double_drop.zrl` (`Vec.extend_from_slice` on an `S` with no `Clone`) is refused by both builds with `error: no field 'clone' on 'S'`, but at `stdlib/vec.zrl:431:60` whole-program and `stdlib/vec.zrl:300:57` under `zbuild`; line 300 is the `slice[i].clone()` line of `vec.zri` (`build/man-gen/zri/vec.zri`), the interface the instantiating module reads the body from. The `safety-matrix-zbuild` gate reported it (`zbuild refuses it for another reason`). `KNOWN_ISSUES.md` §4 "An error inside an imported generic body names the interface's line under `zbuild`" describes it; the warning in the entry above it is suppressed for the same reason (`FnDecl.from_interface`).
    - **Do:** carry each generic body's source positions in the `.zri` (or map interface lines back to the source's), so the error names the source's line in both builds; the warning of the entry above can then be given too. A case for `tests/modular/iface_attrs/` (what the interface loses).
    - **Checks:** C1 gap_76 under `zbuild` names `stdlib/vec.zrl:431:60` (or wherever the whole-program build does); remove its `// zbuild:` line and the `KNOWN_ISSUES.md` entry, and `sh scripts/run_safety_matrix.sh --zbuild` (or the `safety-matrix-zbuild` gate) passes; C2 take the change out and watch the gate report `for another reason`; C3 `make test` and `make preflight-changed`, each `Total:` quoted.

- [ ] +safety +types +AI-D @main id:z0175 A bound on an impl block or a method's type parameter is checked
    > **Created:** 2026-11-11
    > **Branch:** `main`
    > **After:** the `vecclone` series is merged (it may refuse programs the series' tests use).

    - **Found (2026-11-11, git:fc55a0a, scratch `build/p34/`):** `impl<T: Copy> W<T> { fn dup(self: &W<T>) -> i32 }` called on a `W<S>` with `S: Drop` compiles (`b_split_impl_drop.zrl`, exit 0), and so does `fn dup<U: Copy>(self: &W<T>, u: &U)` called with `&S` (`b_method_bound.zrl`). A free function's bound is checked, also through an unbounded generic caller (`b_fn_bound_drop.zrl`, `b_through_generic.zrl`: `error: type 'S' does not implement trait 'Copy'`).
    - **Do:** check both at the call as a free function's bound is checked; probe trait impls (`impl<T: Clone> Clone for Vec<T>` on a `Vec` of a non-`Clone` `T`) beside them. The rejection differential lists every program newly refused.
    - **Diagnostic (2026-11-11, id:z0173):** with the bound unchecked, `Vec.extend_from_slice` on a `T` with no `Clone` is refused only inside `vec.zrl` (`stdlib/vec.zrl:431:60: error: no field 'clone' on 'S'`). Once `impl<T: Clone>` bounds are checked at the call, move `extend_from_slice` and `resize` into such an impl so the user sees `type 'S' does not implement trait 'Clone'` at their call, and update `tests/error_reporting/err_extend_from_slice_no_clone.zrl`'s EXPECT.
    - **Checks:** C1 the two programs above refused with the free function's diagnostic (`tests/error_reporting/`, `// EXPECT:`); C2 take the check out and watch them compile; C3 `scripts/check_reject_diff.sh` against the base, every newly refused program listed with its reason; C4 `make test`, `make preflight-changed`, each `Total:` quoted.

- [ ] +safety +tests +AI-D @main id:z0176 A value bound by value out of an enum payload in a `match` is dropped exactly once
    > **Created:** 2026-11-11
    > **Branch:** `main`
    > **Branch note:** Reclassified public under `SECURITY.md` (it needs the program to take the shape).

    - **Found (2026-11-09, git:6ad43a6, while working on id:z0162):** `match e { E.A(s) => { let n = 1; }, E.B => {}, }` moves the payload into `s`, and neither `s` nor `e` is dropped: the destructor never runs. A leak on its own, but it breaks "drop exactly once" (`doc/spec/safety_model.md`), and a guard that is never released (a lock, an fd, an `Arena` reset) can be a correctness hole. Reproducer (`S` counts its drops into `*p`; exits 0, should exit 1):

    ```zoril
    struct S { p: *mut u8 }
    impl Drop for S { fn drop(self: &mut S) { unsafe { *self.p = *self.p + 1 as u8; } } }
    enum E { A(S), B }
    fn main() -> i32 {
        let mut flag = 0 as u8;
        let fp = &mut flag as *mut u8;
        {
            let e = E.A(S { p: fp });
            match e { E.A(s) => { let n = 1; }, E.B => {}, }
        }
        return flag as i32;
    }
    ```

    - **Do, first:** probe the siblings on the current tree and count the drops each makes (0, 1 or 2): the payload used (`consume(s)`, one drop in `consume`), a `_` arm, a nested pattern, `if let`, a struct payload, a tuple payload. Record each count here; a 0 is a `known_gap` probe (with the Known gaps entry and a `doc/SAFETY.md` §6 class), a 2 a `known_gap` probe that also stops this task for the maintainer before the fix. Then fix in the same session only if it is one mechanism; otherwise split.
    - **Checks:** C1 each sibling's drop count quoted; C2 the probes recorded and `sh scripts/run_safety_matrix.sh` `Mismatches: 0`; C3 `make test`, its `Total:` quoted.

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

- [ ] +safety +tests +AI-D @main id:z0183 A struct holding a frame view is not pushed into the caller's `Vec`
    > **Created:** 2026-11-11
    > **Context:** by id:z0174's review.
    > **Branch:** `main`
    > **Check-in:** stop for review after it: a fix to a safety rule. Public by SECURITY.md's rule: the program has to take this shape (a public report, a `known_gap` probe).

    - **Found:** `out.push(H { s: s })` with `struct H { s: [u8] }` and `s` a view of a stack array of the callee is accepted, and the caller reads the dead frame (`bench/safety_matrix/probes/gap_79_struct_holding_frame_view_pushed.zrl`, `exit 77` where the frame held 42; recorded in git:cc612fe on `main`). The bare view, `out.push(s)` into a `Vec<[u8]>`, is refused (`region escape: a pointer to local stack storage is written to memory that outlives this function`). A `let h = H { s: s }; out.push(h);`, `resize(2, H { s: &buf })` and `extend_from_slice` of such a struct take the same route (probed on `vecclone` at git:ea007d4; `push` is independent of the `vecclone` series). `Option.Some(s)` pushed into a `Vec<Option<[u8]>>` also compiles (not read back).
    - **Route class:** a struct whose field is a frame view, moved into memory that outlives the frame; beside `gap_59`..`gap_61` and `gap_63` (class (K), owners holding frame views), which hold the views in a `Vec`.
    - **Do:** find why the push's store rule sees the bare slice and not the struct carrying it (`build/zoril -v` on `gap_79`, then the summary pass for a struct literal argument), and make the struct's field views count as the stored region; decide the same for an `Option`/enum payload (probe `Option.Some(s)` read back first). Flip `gap_79` to `compile_reject`, remove its Known gaps entry and its sentence in `doc/SAFETY.md` §6 (K); keep `gap_61`'s record as it is unless the fix reaches it.
    - **Checks:** C1 `gap_79` is `compile_reject` and `sh scripts/run_safety_matrix.sh` passes; C2 error tests under `tests/error_reporting/` for the struct push, the `let h` form, `resize` and `extend_from_slice` of the struct, and the enum payload if it is a hole, each with `// EXPECT:`; C3 take the fix out and watch them fail; C4 `scripts/check_reject_diff.sh` against the commit before the fix, every newly refused program listed with its reason, none newly accepted; C5 a program that pushes a struct holding a view of a caller-owned or arena buffer is still accepted; C6 `make test`, `make preflight-changed`, `rm build/zoril && make` without a warning, each `Total:` quoted.

- [ ] +safety +tests +AI-D @main id:z0101 An `extern` function made into a `fn` value needs `unsafe`
    > **Created:** 2026-11-06
    > **Branch:** `main`
    > **Found by:** id:z0095 (its structural twin).
    > **Check-in:** stop for review after it: a fix to a safety rule. A hole in the default mode, reachable from safe code; beside id:z0095 and id:z0100.

    - **Now:** a bare `extern` declaration (`extern fn memset(p: *mut u8, c: i32, n: usize) -> *mut u8;`) named as a value converts to a plain `fn` type with no `unsafe`, and a call through the value is never marked, so safe code calls C with a forged pointer and faults (`bench/safety_matrix/probes/gap_67_extern_fn_as_fn_value.zrl`; `build/z95/x_extern_call.zrl`, exit 139). A direct call is refused ("call to extern function requires unsafe block"); id:z0095's check in `ZirLowerer.fn_value` does not reach it: a bare `extern` is not `is_unsafe` (an `unsafe extern fn` is, and is refused since id:z0095's review).
    - **Decide, then do:** refuse the conversion outside `unsafe` as id:z0095 does (one condition in `fn_value`), or refuse it everywhere: a plain `fn` value is called with the Zoril convention, two words and an environment argument, and an `extern` is a C symbol, which `extern "C" fn(..)` (the C function pointer, its call already `unsafe`) is the type for. Probe every conversion site, an exported (`is_export`) function, and an `extern` with `#[borrows]`/`#[stores]`; flip `gap_67` with its Known gaps entry and the `doc/SAFETY.md` §6 class (M) removed. `make test`, `make preflight-changed`, `sh scripts/run_safety_matrix.sh`.

- [ ] +safety +tests +AI-D @main id:z0100 A generic instance made into a `fn` value is lowered, not dropped
    > **Created:** 2026-11-06
    > **Branch:** `main`
    > **Found by:** id:z0092's review (a sibling-route probe crashed).
    > **Check-in:** stop for review after it: a fix to a safety rule. Independent of the provenance series; a hole in the default mode, reachable from safe code, so it goes beside id:z0095.

    - **Now:** a generic function's instance named with type arguments and not called (`id::<i32>` with `fn id<T>(x: T) -> T`) type-checks as a `fn` value, but lowering emits nothing for it. `let f: fn(i32) -> i32 = id::<i32>; return f(3) - 3;` allocates `f`'s slot and never writes it (the ZIL has `alloc` and then the `call_ptr`, with no store between them), so the call jumps through stack garbage and faults (`bench/safety_matrix/probes/gap_66_generic_instance_as_fn_value_uninit.zrl`, exit 139). By site (`build/z92r/r_*.zrl`, `c3.zrl`, `c5.zrl`): a `let` with a `fn` type and a struct field (`H { f: id::<i32> }`) fault; an assignment (`f = id::<i32>;`) is dropped and `f` keeps its earlier closure (exit 43 where 3 was expected); an argument (`call(id::<i32>)`) gives "invalid ZIL (a compiler bug): an instruction names an operand that no value defines"; `return id::<i32>;` gives "control reaches end of non-void function without a return value"; `let f = id::<i32>;` gives "Failed to resolve callee". A non-generic `fn` item, a method value (`S::get`) and a generic instance chosen by the expected type are not this class: the last is refused, "unknown type `T`", at `let f: fn(i32) -> i32 = id;`.
    - **Do:** find where a turbofish path is lowered only as a callee (`build/zoril -v` on `gap_66`, then the lowering of a path expression with type arguments) and lower it as the instance's `FuncAddr` at every value site, through `ZirLowerer.fn_value` so id:z0095's check applies (a generic `unsafe fn` named with turbofish, `unsafe fn id<T>(p: T) -> T` as `id::<*i32>`, is accepted outside `unsafe` today only because the value is dropped: `build/z95r/b2.zrl`, from id:z0095's review), or refuse it in the type checker with a diagnostic if instantiating is out of scope; decide which and say why. Probe every site above, a generic method (`B.id::<i32>`, refused today: "type arguments are only accepted on a call or a struct literal here"), and the instance passed to a generic higher-order function. Flip `gap_66` to `accept` (exit 0) or `compile_reject`, and remove its Known gaps entry and the `doc/SAFETY.md` §6 class (L) (lettered (M) until id:z0095 closed the first (L)). `make test`, `make preflight-changed`, `sh scripts/run_safety_matrix.sh`.

- [ ] +safety +research +AI-D @main id:z0013 Review rounds: rotate reviewers over the compiler until the findings dwindle
    > **Created:** 2026-11-03
    > **Branch:** `main`
    > **Branch note:** **Standing task;** a round reads and probes only, so it can run beside anything except a change to the area it reviews.

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
    > **Found by:** id:z0049's review (correction 9). Default mode; not a safety issue.

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
    > **Found by:** id:z0078. Refuses more, never less: not a safety issue.

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
    > **Found by:** id:z0078 (and its review).

    - **Now:** `scripts/mutation-check.sh`'s header says `scripts/mutation_uncovered.list` holds the mutations it deliberately does not run (M106, M107, M85, M112) and `scripts/mutation_incremental.list` the ids run against the incremental scenario (`-c` / `.zri`). Neither file exists: `incremental_list_path` returns a missing file, `incremental_mutation` is always false, so no mutant is ever run against the incremental scenario, and nothing records the deliberately unrun ones. `git log --all` shows neither file was ever committed. A mutant of the interface printer (id:z0078's `#[fresh]` printing) is caught only by `scripts/test_interface_attrs.sh`, a gate the harness does not run.
    - **Do:** find in git history whether the lists existed and were lost (`git log --all -- scripts/mutation_incremental.list`), then either restore them with their entries, or make the harness say plainly that it runs neither; and decide whether a mutant may name a gate (the interface gate) as its catcher. Add an interface-printer mutant (`if f.fresh {` -> `if false {` in `src/interface_print.zrl`) that the chosen route catches. `make test`, `sh scripts/test_mutation_check.sh`.
    - **Not ready for `+AI-G` (review, 2026-11-07):** **Do** leaves two decisions: whether the harness runs an incremental list at all, and whether a gate (`scripts/test_interface_attrs.sh`) may be a mutant's catcher, which adds its run time to every surviving mutant's evaluation (the harness already runs `perf-gate`, `fmt-check` and `static-image` that way). An `+AI-D` session, or the maintainer, settles both here first, with the gate's run time measured; then this task gets numbered checks: the new mutant reported caught by the chosen route, and that route taken out and the mutant reported SURVIVED.

- [ ] +bench +measurement +AI-G @main id:z0004 Measure how far the benchmark gate's measures move between cloud sessions
    > **Created:** 2026-11-03
    > **Branch:** `main`
    > **Session rule:** a new session records one sample only if asked to, so this task never starts a session.

    - **Why:** `bench/cross_lang/thresholds.cfg` is not in the tree, so `scripts/bench_threshold_check.sh` records a baseline on its first run on a host. Every cloud session starts on a fresh VM, so there the gate compares a run with itself and cannot fail. Of its three measures, `runtime_ratio_vs_gcc_o2` is relative to gcc on the same host; `clean_throughput_loc_s` and `incremental_rebuild_ms` are absolute and depend on the VM.
    - **Do:** in three to five separate cloud sessions, run `sh scripts/bench_cross_lang.sh --check-thresholds` on the same commit and record each measure, the CPU model (`/proc/cpuinfo`) and the load. Report the spread of each measure against the gate's 15% tolerance. Delete the files the run writes under `bench/`; commit nothing but this task's text.
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

## `provenance` branch: hardening and precision series, paused (from `active.tm.md`, 2026-11-12)

Moved from the sprint, in their order there. The section's notes as they stood:

Provenance and liveness hardening series (`+safety` B1 to B4). Paused until the test-efficiency series finishes:
1. Closure summaries and environments: id:z0093, id:z0094, id:z0096, id:z0097.
2. Value precision & compiler refactoring: id:z0087 (integers from collections), id:z0086 (literals), id:z0089 (`exh_expand_or`), id:z0090 (`zbuild` manifest).
3. Core provenance rules and diagnostics: id:z0073 (raw pointer decision), id:z0011 (borrows/stores decl check), id:z0044 (local field liveness), id:z0066 (diagnostics), id:z0065 (parallel checking), id:z0074 (differential review), id:z0012 (retirement of old passes).
4. Post-series audits: id:z0045 (reference carrier through phi/let), id:z0017 (safe store-grid twins).

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer). Stop for review after each `+safety` check-in.

- [ ] +safety +tests +AI-D @provenance id:z0093 B1.9a2 A closure body's summary is stated over its `__env` parameter
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0088 (why experiment A was unsound).
    > **Depends:** id:z0088
    > **After:** id:z0092.
    > **Before:** id:z0094, id:z0065.
    > **Check-in:** stop for review after it. **Split here** if the design note and the implementation take more than a session: the design (§3 text and probes) first.

    - **Now:** inside a closure body every capture is read as the `Env` flag (`out O={Env}`), which `os_note_edges` turns into an `Unknown` value stored into a global: `|| { *out = routed; }` has the summary `store Unknown -> global`. An owned capture (moved into the environment) is also marked as storage of the body's own frame (`os_stmt`, "an owned capture's storage dies with the closure"), so a view of it cannot leave the body, but a store *into* it is a store into this frame and records no summary edge. A caller applying such a summary sees no store at all: id:z0088's experiment A did, and accepted 1490 unsafe grid cells (all `closure_owned_capture`, e.g. `arena_vec__arena_struct_bundle__direct__closure_owned_capture__frame_ends`, where the closure owns `h` and stores the view `routed` into it).
    - **Do:** summarise a closure body over its `__env` parameter (the last one, `lower_rv_call_ptr`): a capture is what `__env` reaches (`ParamContents(env)`); a store into a capture is an edge into it; an owned capture is storage the environment owns, so a store into it is an edge into `ParamContents(env)`, while a view of it that leaves the body (returned, stored outside the environment) is still refused. State it in the design note §3 (_Closure environments_), with the routes: by-reference and by-value captures, an owned capture, a nested closure, a closure capturing another closure, and `move` of the environment.
    - **Checks:** the store grid's 1490 cells refused by the body's own rules, not by the unknown-call rule (run the grid with id:z0094's pre-scan applied on top, as id:z0088 built it in `build/z88/esrc_ab`, and count 0 unsafe accepted); `closure_env_safe_twin.zrl` accepted; the owned-capture tests (`closure_captures_owning_and_other`, `closure_mutates_owning_capture`, `closure_owned_capture`; reduced in `build/z88/c1.zrl`: a closure that owns a `Vec` and pushes to it) measured. `make test`, `make preflight-changed`, the rejection differential, `sh scripts/run_safety_matrix.sh`.

- [ ] +safety +tests +AI-D @provenance id:z0094 B1.9a3 A call through a local bound to one known function uses that function's summary
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0088 (option 1, experiment A).
    > **Depends:** id:z0093
    > **Before:** id:z0065.
    > **Check-in:** stop for review after it. Accepts more: the rejection differential applies.

    - **Now:** a closure or a `fn` item bound to a local and called in the same body (`let mut cl = || { *out = routed; }; cl();`, `let f_ptr: fn(..) = forward_fn_target; f_ptr(x)`) is an unknown call. Every closure and `fn`-value shape in the store grid is of this kind. After id:z0092, the unknown-call store rule still refuses the cells where the closure itself stores, since it must assume any frame-bound argument may go into any memory another reaches: `closure_capture_mut` 1708, `closure_call_mut` 2534 and `closure_owned_capture` 3300 safe twins (id:z0088, experiment B; id:z0092's grid run refuses the same set, `build/z92/grid/twin_rejections.txt`).
    - **Do:** before the passes, find each local assigned exactly one `FuncAddr` in the body (directly or by a plain copy of such a local; never through a `&mut`, a projection or two different functions); at a `CallPtr` through it, apply that function's summary with `os_call`, the callee value as `__env` (the last argument). id:z0088's version is in `build/z88/esrc_a/check_zir.zrl` (`z88_scan`, `z88_try_known`): a measurement aid, not a rule; rewrite it without the `static mut` state. A callee whose summary is not known yet (a recursive cycle) is handled as `os_call` handles it.
    - **Checks:** the store grid under `--provenance` (0 unsafe accepted, the 1490 cells of id:z0093 included; the closure destinations' twins counted by axis), and the 672 test programs (17 with warnings before id:z0092, 14 after it, as measured; `build/z92/measure.sh`). Probes: a local assigned two closures on two branches (stays unknown), a closure local passed by `&mut` to a callee that reassigns it, a closure called after the variable it captured was moved. `make test`, `make preflight-changed`, the rejection differential.

- [ ] +safety +tests +AI-D @provenance id:z0096 A closure storing into a global, handed to a callee that calls it, is checked
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0092 (the store side of the rule's boundary).
    > **Check-in:** stop for review after it.
    > **After:** id:z0093, whose closure summary over `__env` gives the closure's store into a global an edge this task can carry through the callee.
    > **Before:** id:z0012, which deletes `check_fn_value`.

    - **Now:** `bench/safety_matrix/probes/gap_64_closure_global_store_via_fn_param.zrl`: `run(|| { G = r as *i32; })` with `fn run(f: fn()) { f(); }` and `r = &x` compiles with and without `--provenance`, and the global keeps a dead frame's address (exit 77). The closure body stores `Env` (not frame-bound) into a global; the unknown call through `f` in `run` records edges only into what its arguments reach, never a global, so `run`'s summary has none and the call to `run` checks nothing. The direct call `cl()` is refused by the old rules ("callee stashes local stack pointer via indirect call"); a `fn` item storing into a global cannot become a value (`check_fn_value` in `src/verify.zrl`), which id:z0012 has to carry over.
    - **Route class:** a closure passed as an argument to a callee that calls it (`gap_52`), here with a global destination. Probe the siblings: a `static mut` reached through a captured reference, a closure kept in a struct field, two levels of callers.

- [ ] +precision +tests +AI-D @provenance id:z0097 An edge into a `fn` argument's environment does not make a `fn` item a global destination
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0092 (its accept probes).
    > **Depends:** id:z0092
    > **Before:** id:z0065: a higher-order function handed a local's address is common in user code. Accepts more: the rejection differential applies.

    - **Now:** an unknown call through a `fn` parameter `f` records store edges into `ParamContents(f)`, its environment (`os_unknown_call_effects`, the environment as argument K = ARGS.len). At a call that passes a `fn` item (`Static`, no environment), the edge's destination is the item's reach, `Static`, a global, so a frame address passed beside it is refused by the call store rule: `fn first(f: fn(&i32, &i32) -> &i32, a: &i32, b: &i32) -> &i32 { return f(a, b); }` called as `first(pick, &x, &y)` with locals, `walk(step, &x, n)`, `run(&m, &x)` with `m.f` a `fn` item (id:z0092's `build/z92/a_*.zrl`; the base compiler refuses them the same way). Inside the callee `os_unknown_arg` already reads a `Static` callee as adding no memory; the caller's edge mapping does not.
    - **Do:** decide whether an edge into the `ParamContents` of a `fn`-typed parameter maps, at the caller, to the environment of the value passed (`os_through` of its `O` without `Static`, as `os_unknown_arg` takes it) rather than to everything it reaches. A rule that removes destinations: the series rule's probes (a capturing closure passed in its place must still be refused, `gap_52`'s shapes), the store grid under `--provenance`, and `test_stdlib_iter.zrl`'s seven warnings read first to see whether they are this class.
    - **Found in id:z0092's review (2026-11-06):** the false global edge carries up through a summary. `fn apply<T>(f: fn(T) -> T, x: T) -> T { return f(x); }` and `fn via(p: &i32) -> &i32 { return apply::<&i32>(same, p); }`: `via`'s body is accepted, but its summary now stores `p` into a global (the edge into `ParamContents(f)` mapped to `same`, `Static`), so `main`'s `via(&x)` with a local is refused, "the callee stores an address of this frame into a global (call store rule)", one level above the `fn` item (`build/z92r/s_generic_hof.zrl`). A fix that maps the edge at the call must also keep it out of the caller's summary. The arena twins `f(&a, mk_vec, &mut v)` and `r(&a, mk_vec)` with a local arena are refused the same way (`build/z92r/s_param_vec.zrl`).

- [ ] +safety +tests +AI-D @provenance id:z0087 B1.9c An integer popped from a collection carries no address
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0064 (root (f)).
    > **Depends:** id:z0075
    > **Check-in:** stop for review after it.
    > **Routed (2026-11-06, by id:z0075):** a rule, though only `src` shows the class (6 warnings): it adds a type fact (an integer holds no address), the cheapest of the rules to state, and the exemption for a primitive result exists already.

    - **Now:** `os_call` drops a body summary's `ParamContents` ties for a primitive result only, so `Vec<usize>.pop()` (`Option<usize>`) is tied to the `Vec`'s storage; the integer then carries `Frame(widths)` into whatever it is written into. In `src/fmt/doc.zrl` (`Doc::measure`) this gives all six `fmt/` warnings (`doc.zrl:111`, `:151`, `fmt.zrl:76`, `:122`, `:131`, the cascade through `render`, `file` and `format_source`).
    - **Reduction** (`build/z64/t/f1.zrl`; builds, exits 0, accepted by default; two warnings at the `set` under `--provenance=warn`, id:z0066's duplicate; twin `let w = widths.as_slice()[0];` gives none):

    ```zoril
    import "vec.zrl";
    use vec::Vec;

    struct Cmd { text: [u8], width: usize }

    #[borrows()]
    fn at0(cmds: &Vec<Cmd>) -> Cmd { let r = cmds.as_slice()[0]; return Cmd { text: r.text, width: r.width }; }

    fn measure(cmds: &mut Vec<Cmd>) {
        let mut widths = Vec::<usize>.new();
        widths.push(3 as usize);
        let w = match widths.pop() { Option.Some(x) => x, Option.None => 0 as usize };
        let mut c = at0(cmds);
        c.width = w;
        cmds.set(0 as usize, c);
    }

    fn main() -> i32 {
        let mut cmds: Vec<Cmd> = Vec.new();
        cmds.push(Cmd { text: "ab", width: 0 as usize });
        measure(&mut cmds);
        return cmds.as_slice()[0].width as i32 - 3;
    }
    ```

    - **Measured alone (id:z0064, a copy of `src/` on top of the earlier experiments, both pops in `Doc::measure` replaced by an index read and a discarded pop):** 14 to 8, every `fmt/` warning gone.
    - **Do:** extend the exemption to a result type that holds no pointer at any depth (an `Option<usize>`, a struct of integers; `os_carries` is the place to check), and probe that a type holding a pointer anywhere (an `Option<&i32>`, a struct with a `[u8]` field) keeps its tie. It removes ties, so the rejection differential applies. Relates to the `Vec.pop` class id:z0064 recorded (a non-integer value popped and moved into a returned `Vec`, `git show 403a092:tests/language/memory/origins/own_contents_edge.zrl`), which this does not cover. `make test`, `make preflight-changed`.

- [ ] +safety +tests +AI-D @provenance id:z0086 B1.9e A literal held by a value does not make what the value reaches a global destination
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0064 (root (e)).
    > **Depends:** id:z0075
    > **Check-in:** stop for review after it.
    > **Routed (2026-11-06, by id:z0075):** a rule. id:z0084's rule is deferred, so this one must cover the lowerer's literals without it: `exh_missing` writes literals into a `ByteVec` in `self.arena`, which the call rule names `Param(0)` (`*self`), so the `Static` lands in `*self` and not only in the arena.

    - **Now:** a local that holds `Static` (a string literal in one of its fields, or written into memory it reaches) makes every later store into what it reaches have `Static` among its targets, and the call store rule reads `Static` as a global. In the driver, `ZirLowerer::lower_function`'s summary has `store Static -> Param(0)` (a dozen lowering functions write a literal into `*self`, the first in lowering order `exh_missing`), so `Driver::run_body_passes_in_scratch`'s local `zir_low` holds `Static`; it is the first function in lowering order with a store into a global. That carries the last 8 of `src`'s warnings (`src/driver/module.zrl:666`, `:713`, `:1141`, `:1188`, `:1475`, `:1603` into a global; `:1362`, `:1386` outlives), and the class covers id:z0064's three `arena_raw` test programs (`test_stdlib_string_arena`, `accept_slice_receiver`, `test_empty_compile_and_tool_errors`).
    - **Reduction** (`build/z64/t/e3.zrl`; builds, exits 0, accepted by default; "into a global" at the call in `main` under `--provenance=warn`; twin with `name: s` gives no warning): `struct W { name: [u8], items: &mut Vec<[u8]> }`, `impl W { fn add(self: &mut W, s: [u8]) { self.items.push(s); } }`, `fn inner(out: &mut Vec<[u8]>, s: [u8]) { let mut w = W { name: "lit", items: out }; w.add(s); }`, and `main` calls `inner(&mut v, &data)` with a local array `data` and a `Vec<[u8]>` `v`, returning `v[0][1] as i32 - 2`.
    - **Not yet measured alone:** replacing `ZirLowerer.new`'s `file_path: ""` changes none of the 8 (the other sites still write literals), and id:z0084's experiment alone does not remove them either. Find each site's route first (`--emit-origins` with the target-file filter in `src/driver/module.zrl` removed, as id:z0064's debug compiler did).
    - **Do:** decide whether a `Static` origin reached through a value may be dropped from store targets (a literal is read-only, so storing through it needs `unsafe`), or whether the sites change. A rule removes origins, so the series rule applies, with probes of a `static mut` reached through a value (which must stay a global destination) and a literal beside a `&mut` in one struct. `make test`, `make preflight-changed`, the rejection differential.

- [ ] +refactor +tests +AI-G @provenance id:z0089 B1.9f `exh_expand_or` pushes a fresh copy of each row it keeps
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0064 (root (d2)).
    > **Routed by:** id:z0075, to a code change at the site; the rule is deferred (id:z0085 in `future.tm.md`).
    > **Before:** id:z0065.

    - **Now:** `src/lower_zir/exhaust.zrl`, `ZirLowerer::exh_expand_or`: `if !is_or { out.push(row); }` pushes the row slice read out of `rows`. The new rules read a value copied out of a referenced `Vec` as an address into its buffer, and with the function's self-recursion (`return self.exh_expand_or(&out)`) that turns `exh_useful`'s summary into every parameter stored into every parameter and a global: 153 of `src/main.zrl`'s 167 "into a global" warnings under `--provenance=warn`.
    - **Do:** push a fresh copy of the row (`let copy = self.alloc_u32s(row.len);`, copy the elements, `out.push(copy);`), as the or-pattern branch a few lines above does. The rows are read-only pattern lists, so behaviour is unchanged; the cost is one scratch-arena allocation per kept row. A one-line comment says why the copy is there (the origin rules), without a task ID. Plain code: `src/` must build under the pinned stage1.
    - **Checks:** (`W` below is `timeout -k 5 180 build/zoril -I stdlib=stdlib -I src -I build/gen --provenance=warn --emit-zil -o /dev/null src/main.zrl 2>&1`.)
      - C1: before the change, `W | grep -c 'warning: provenance'` and `W | grep -c 'into a global'`; quote both (expected 195 and 167; if they differ, record the figures and go on, the change is what is measured).
      - C2: after the change and `make`, the same two counts; quote both (expected 185 and 14). A drop smaller than 10 and 150 means the copy is not at the site the warnings name: stop and report.
      - C3: the copy is the only change: `git diff --stat` names only `src/lower_zir/exhaust.zrl`, and its diff is the copy loop and the one comment.
      - C4: `rm build/zoril && make` (the build through stage1) and `make` again, neither with a warning; quote the last line of each.
      - C5: `./scripts/test.sh --filter 'exhaust|unreachable' tests` passes; quote its `Total:` line.
      - C6: `make test` and `make preflight-changed`, each `Total:` line quoted; the completion note says the fuzz record is stale for `src/`.

- [ ] +tools +tests +AI-G @provenance id:z0090 B1.9g zbuild's manifest parsing gives no warning under `--provenance`
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0064 (root (d1)).
    > **Routed by:** id:z0075, to code changes at zbuild's sites; the rule is deferred (id:z0084 in `future.tm.md`).
    > **Before:** id:z0065.

    - **Now:** `tools/zbuild` gives 25 warnings under `--provenance=warn` (18 and 4 call store rule, 2 return rule, 1 store rule), all in manifest parsing (`parse_manifest`, `parse_entry`, `write_manifest`, `load_manifest` in `tools/zbuild/src/manifest.zrl`). `parse_entry(&cols, arena)` takes the column `Vec` by reference, and because a `Vec` holds a raw arena pointer, the call rule names its result's arena storage by `&cols`'s address (`Frame(cols)`); what is read out of the result is then an address of this frame.
    - **Do:** change the sites so that no argument whose only tie to the arena is the `Vec`'s pointer names the result's storage. First try passing `cols.as_slice()` (a `[[u8]]`, which reaches no `ArenaHeader`) to `parse_entry`, then the sites the remaining warnings name. Keep the manifest format and behaviour unchanged. If a site cannot be changed without `unsafe`, stop and report: id:z0084's rule comes back instead.
    - **Checks:** (`W` below is `timeout -k 5 180 build/zoril -I stdlib=stdlib -I tools/zbuild/src -I src -I build/gen --provenance=warn --emit-zil -o /dev/null tools/zbuild/src/main.zrl 2>&1`.)
      - C1: before the change, `W | grep 'warning: provenance'`: the count and each line's location, quoted (expected 25).
      - C2: after each site's change, `W | grep -c 'warning: provenance'`, recorded per site; at the end 0. A site that needs `unsafe` to reach 0: stop and report, as **Do** says.
      - C3: `git diff | grep '^+.*unsafe'` prints nothing.
      - C4: the manifest is unchanged: build `tests/integration` or the `zbuild-link` scenario's project with the old and the new `build/zbuild`, and `cmp` the two manifest files it writes; quote the result.
      - C5: `./scripts/test.sh --gate zbuild-diff --gate safety-matrix-zbuild --scenario zbuild-errors --scenario zbuild-link` passes; quote it.
      - C6: `make test` and `make preflight-changed`, each `Total:` line quoted; the completion note says the fuzz record is stale for `tools/zbuild/`.

- [ ] +safety +decision +AI-D @provenance id:z0073 B1.8b Decide whether storing a raw pointer into a by-value owner's buffer, then dropping the owner, is refused
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Found by:** the review of id:z0071.
    > **Before:** id:z0012. Decision first; the fix or the probe is the next step it names.

    - **The case:** `struct Buf { data: *mut u8 }` with `Drop` freeing a heap block; `fn keep(out: &mut *mut u8, b: Buf) { *out = b.data; }` and `fn f(out: &mut *mut u8) { let b = Buf.new(); keep(out, b); }` (`tests/language/memory/provenance/addr_edge_by_value_owner_refused.zrl` at `403a092`), and the twin storing `BothPtr { own_v: Vec::<i32>.new(), p: b.data }` (`build/z71r/c2.zrl`). Accepted by the old rules and by `--provenance` at `a1ea096`; the caller's pointer is left dangling once `keep` drops `b`. Only `403a092` refused the first form, through the edge kinds id:z0072 removes.
    - **Question:** the stored value is a raw pointer, dereferenced only in `unsafe`. id:z0063 decided that the new rules check a raw pointer's origins (`Raw` is exempt only as a value). Does that make this a hole (a `known_gap` probe now, a fix that tells a moved owner from an address read out of it without per-store kinds), or is a dangling raw pointer outside the guarantee (record it in `doc/spec/safety_model.md` and `doc/spec/unsafe_policy.md`, with a test showing the accept)?
    - **Removed in `403a092` (id:z0072), until this is decided:** the test's full text is in `git show 403a092:tests/language/memory/provenance/addr_edge_by_value_owner_refused.zrl`; at `403a092` it compiles under `--provenance` and in the default mode.
    - **A sibling route (found in id:z0076, 2026-11-05):** an owner holding a raw pointer to memory outside the frame, whose safe method stores an argument through it (`put(self: &mut G, r: &i32) { unsafe { *self.p = r; } }` called with `&x`), is accepted in both modes: the destination reach does not follow a `*mut` an owner holds (`os_type_has` answers no for `RawPtrMut(x)` under `OS_Q_HANDLE`). Program in id:z0076's text (`build/z76/cx.zrl`). Decide it with this case: a raw pointer's target is the `unsafe` author's claim, or the call rule follows it.
    - **Two more sibling routes (found in id:z0076, 2026-11-06):** a frame address stored through the result of a `#[fresh]` function (`tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`) or through a heap block from `zoril_allocator_alloc(null, ..)` (`heap_block_store_through_old_rule_refused.zrl`), the pointer then returned, or the block put into a global (`heap_block_into_global_old_rule_refused.zrl`): any destination of the pointer. Since id:z0076 the new rules accept all three: the result has no origins, so a store through it reaches nothing they follow, as with a raw pointer an owner holds. The old region rule refuses all three in every mode today. Decide them with the case above: if a dangling raw pointer is outside the guarantee, say so in `doc/spec/safety_model.md`; if not, the store through a raw pointer with no origins needs a target (the fresh storage of the local holding it, say) before id:z0012 removes the old rule.

- [ ] +safety +tests +AI-D @provenance id:z0011 B3 Declarations are checked against the body: `#[borrows(..)]`, `#[stores(..)]`, the `&self` default
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0049
    > **Check-in:** stop for review after it.
    > **Depends also (2026-11-05):** id:z0064 (its re-measurement comes first).

    - **Rule (Decision 1):** a declaration may list more than the body proves (a wider public contract), never less. For a function with a body the effective ties and stores are the union of what the body proves and any declaration (id:z0010 already sums them); a declaration that claims less than the body is a compile error, the narrowing rule of `CHANGELOG.md`'s pre-1.0 note. The `&self` elision default and the declarations apply as written to bodyless items (`extern`, trait signatures, `.zri` imports). Each of the tree's 82 `#[borrows()]` declarations (such as `Lexer.text_from`) is either proved unnecessary by id:z0010's `ParamAddr`/`ParamContents` summary and removed, or converted into an explicit, reviewed `unsafe` interior with a `// SAFETY:` comment, listed with its decision in the commit. **Stop and report** before changing a `pub` stdlib signature.
    - **Test expectation note:** `tests/error_reporting/err_stores_attribute_false.zrl` currently expects a wider `#[stores]` contract than the body performs to fail; under the wider-contract rule that test changes (stop and document the test change per `AGENTS.md`).
    - **Probes:** an unannotated `&self` method passing a parameter's borrow through, the same through a trait, and safe-code `#[borrows()]` laundering (`gap_30_borrows_attribute_launder` stays rejected; `gap_44_borrows_attr_reset` is rejected once checked declarations refuse the narrowing `#[borrows()]` (it is accepted, exit 77, under `--provenance` at `c323b0e`: a reset hole, not an escape, so the store rules do not see it)); accepted: a `&self` method returning a view of `self` and a wider `#[borrows]`/`#[stores]` public contract. `make test`, `make preflight-changed`. Stop for review.
    - **Blind spot not covered by this check (from id:z0049's review, 2026-11-05):** a body that copies through a bare `extern` proves no store, so a declaration can never be "narrower than the body" there (id:z0060's `extend_from_slice` route). Add a rule here or in a task of its own: a safe function that passes a pointer derived from a parameter to an `extern` with no declared effect must declare its own `#[stores]`/`#[borrows]` (or the `extern` declares its effect). Probe it with id:z0060's reproducer with id:z0060's fix taken out.

- [ ] +safety +tests +AI-D @provenance id:z0044 B0.1 A value stored into a local's field through a pointer to the local keeps its borrow
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Check-in:** stop for review after it.
    > **Closes:** `gap_37_local_mutref_field_reset`, `gap_38_param_field_reset`, `gap_39_method_self_field_reset`, `gap_43_box_field_reset`.
    > **Depends:** id:z0010, id:z0011

    - **Scope (narrowed to intra-frame liveness, 2026-11-03):** the frame-escape siblings (`gap_40`–`gap_42` and `gap_45`) are handled by id:z0048/id:z0012's origin sets. This task fixes intra-frame `Arena::reset` / `free` / `@drop` liveness (`ActiveBorrow` in `src/check_zir.zrl`), where a slice written into a local struct's field or a `Box`'s contents through a local `&mut`, through a callee's `&mut` parameter, through `self` in a `&mut self` method, or through `*b` on a `Box` is skipped today (`place_writes_through_pointer`), letting `a.reset()` pass while the field is read afterwards.
    - **Do:** carry the stored value's borrows to the local (or `Box` local) the pointer refers to: for a local `&mut` or `Box` deref, through the pointer's borrow/ownership of that local; for a callee, through id:z0010's pairwise `i -> j` store summary (`#[stores(..)]` checked in id:z0011). Probe the sibling routes: a `&mut` held in a struct field, a reborrow, a closure capturing `&mut w` across `a.reset()`, and a trait method; also verify `gap_44_borrows_attr_reset` is rejected once checked `#[borrows()]` is active.
    - **Found by id:z0047 (pre-existing over-rejection):** `fn f(view: [i32]) -> i32 { let mut w = ...; let r = &mut w; r.s = view; ... }` called with stack `f(&data)` is refused today by `src/summary_pass.zrl`; confirm id:z0012's retirement of `summary_pass.zrl` removes that refusal without reopening any reset hole.
    - **Probes:** `gap_37`, `gap_38`, `gap_39` and `gap_43` flip to `compile_reject`, with an accepted twin for each (the field is read before `a.reset()`). Check the over-rejection recorded on id:z0017 does not grow.
    - **Verification:** `make test`, `make preflight-changed`, the rejection differential; `bench/fuzz/README.md` stays stale for `src/`. Stop for review.

- [ ] +diagnostics +AI-G @provenance id:z0066 B3.9 Provenance diagnostics name the origin they found, once per site
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Found by:** id:z0049's review (correction 8).
    > **Before:** id:z0065, which makes these messages users' errors.

    - **Now:** the return rule says "the returned value holds an address of this frame" also when the returned origins are only `Unknown`, and the call store rule often prints the same warning twice at one location: under `--provenance=warn`, `src/fmt/doc.zrl:111:21`, `src/driver/module.zrl:1338:13`, `tools/zbuild/src/build.zrl:580:17`, `tests/unit/test_empty_compile_and_tool_errors.zrl:65:5` (re-checked 2026-11-06 after id:z0092).
    - **Stale examples (2026-11-06):** the `Unknown`-only return was `fn mk3(n: u64) -> Box<H> { let p = @ptr_from_int<*u8>(n); return box H { p: p, n: n }; }`, now accepted (`@ptr_from_int` gives `Raw` since id:z0063), and the duplicate was `fn add(v: &mut Vec<Vec<i32>>) { v.push(Vec::<i32>.new()); }`, now accepted. Find a current `Unknown`-only return first: the sources left are a summary-less call (a `.zri` import with no summary) and an index the walk cannot type.
    - **Do:** word each rule's message by the origin that triggered it (`Frame`: an address of this frame; `Unknown`: an address the compiler cannot trace), and print one diagnostic per site and rule. Update the `EXPECT:` lines of the provenance tests that change, and say so in the commit message.
    - **Checks:**
      - C1: a current `Unknown`-only return, as a program under 15 lines, recorded in this task with the message it gets today (quoted). If none is found in the session, stop and report what was tried: the wording change waits for one.
      - C2: one test per wording (`Frame`, `Unknown`), each with an `// EXPECT:` line for its new message, under `tests/language/memory/provenance/`; both pass.
      - C3: under `--provenance=warn`, each of the four sites in **Now** prints one diagnostic per rule: for each, `grep -c '<file>:<line>:<col>'` on the compiler's output is 1 (or 0 if the site is now accepted); quote the four counts.
      - C4: a test with two different rules at one site prints both (one each), so the de-duplication is per rule, not per site.
      - C5: every `EXPECT:` line changed, listed in the commit message (`git diff --stat -- tests` matches the list).
      - C6: `make test` and `make preflight-changed`, each `Total:` line quoted.

- [ ] +safety +tests +AI-D @provenance id:z0065 B4a The new rules on by default, beside the old ones
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Split from:** id:z0012.
    > **Depends:** id:z0064, id:z0011, id:z0044, id:z0066
    > **Check-in:** stop for review after it.
    > **Ordering note:** this task only refuses more, and depends in substance only on id:z0064 (the tree must be clean); the maintainer may move it ahead of id:z0011 and id:z0044 to close the escape holes for users sooner.
    > **Depends also (2026-11-06, from id:z0064):** id:z0075, and id:z0084 to id:z0088 as id:z0075 routes them (a task it routes to "accepted refusal" or "code change" is done here instead).
    > **Depends also (2026-11-06, as id:z0075 routed them):** id:z0088, id:z0087, id:z0086 (rules), id:z0089, id:z0090 (code changes at the sites). id:z0084, id:z0085 and id:z0091 are deferred to `future.tm.md` and are not dependencies.
    > **Depends also (2026-11-06, as id:z0088 decided):** id:z0092, id:z0093, id:z0094.
    > **Depends also (2026-11-06, from id:z0092):** id:z0097 (an over-refusal of higher-order calls). id:z0095 and id:z0096 are holes in both modes, not dependencies.

    - **Do:** make the rules of `--provenance` run by default **in addition to** the old rules (nothing is deleted here; the old rules still run). Keep `--provenance=warn` as a developer option or retire it; decide and record. Resolve whatever the default build of `src/`, `stdlib/`, `tools/` and `tests/` now refuses, per id:z0064's classification (a real escape: fix the code; an over-rejection: it should already have its own task done).
    - **Code changes id:z0064 left here (2026-11-06):** `Driver::lower_fn_body` pushes `OsPending { zir: zir_func }` into `self.os_pending` (`src/driver/module.zrl`, 2 warnings): `zir_func`'s slices are tied to the local `zir_low` though they live in the driver's scratch arena; change the code or route it to id:z0084's rule. `Driver::set_ice_context` stores an arena-built note into a global through `set_ice_note`'s `#[stores(note -> static)]` (`src/driver/module.zrl:864`): a true store, safe only because the arena lives as long as the program, and no warning of its own once the other roots are gone; if the default build refuses it, an explicit `unsafe` with a `// SAFETY:` comment naming that invariant, not a rule.
    - **Probes:** every `known_gap` probe the new rules refuse flips to `compile_reject` (at id:z0059: all escape gaps except the liveness ones `gap_37`, `gap_38`, `gap_39`, `gap_43`, `gap_44`; since id:z0060 also `gap_56`, since id:z0061 `gap_57` and `gap_58`, since id:z0062 `gap_59` to `gap_62`, since id:z0072 `gap_63`; re-check each), with its Known gaps entry in `doc/spec/safety_model.md` and line in `doc/SAFETY.md` §6 removed. Accept probes newly refused: none allowed without a task.
    - **Store grid:** re-record `bench/fuzz/store_grid_expected_failures.txt` and `store_grid_twin_rejections.txt` (and the modular pair) under the new default; list in the completion note every twin newly refused, by axis.
    - **Accepted refusal (id:z0075, 2026-11-06):** the 18 safe twins refused because an assignment to a local's field keeps the field's old origins (`{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{same_param,store_param_65}__{deref_out,field_out}__frame_ends`) stay refused: add a `KNOWN_ISSUES.md` §5 entry with the reduced program from id:z0091 (`future.tm.md`), the fix that would remove it, and how to rewrite: give the field its final value when the local is built (`let carrier_tup = (src_val, 10);` in place of `(&seed, 10)` then `carrier_tup.0 = src_val;`: no warning, checked on id:z0064's compiler). Any other twin newly refused here needs a task, per the rule above.
    - **Verification:** `make test`, `make preflight-changed` (the differential must show 0 newly accepted; list the newly refused programs), `sh scripts/check_store_grid.sh`, the self-hosting fixpoint. The fuzz record goes stale for `src/`. Stop for review.

- [ ] +safety +tests +AI-D @provenance id:z0074 B4b List every program the old rules refuse and the new rules accept, and read each
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Found by:** the review of id:z0071.
    > **Depends:** id:z0065
    > **Blocks:** id:z0012, which is the change that accepts them.

    - **Why:** `leak_vec` (id:z0071) was refused by neither differential the series runs: the rejection differential compares two compilers in the default mode, and `build/rv/provdiff.sh` compares `--provenance` before and after a change over the existing probes. A reviewer found it by hand. id:z0012 deletes the old rules, so every program only they refuse is accepted after it; that list is not computed anywhere.
    - **Do:** run the new rules alone (a scratch compiler with the old rules' refusals off, as `check_reject_diff.sh` builds its base in a scratch worktree, or a developer flag if one is cheaper; say which) and the default compiler over the rejection differential's program set (69,122 at id:z0071, `tests/`, the safety probes, the store grid twins). List every program refused by the default and accepted by the new rules alone, and read each: a real escape gets a fix or a `known_gap` probe before id:z0012; a safe program is recorded as id:z0012's intended acceptance.
    - **Make it a gate** if it is cheap enough: id:z0012's completion note then lists the same set, empty of unsafe programs.
    - **Known members (from id:z0076, 2026-11-06):** `tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`, `heap_block_store_through_old_rule_refused.zrl` and `heap_block_into_global_old_rule_refused.zrl` are refused by the old region rule only: a frame address stored through a `#[fresh]` result or a heap block, the pointer then returned or put into a global. Their expected diagnostic names the old rule, so they fail when it goes; id:z0073 decides what replaces it.

- [ ] +safety +tests +AI-D @provenance id:z0012 B4 Make `--provenance` the default, delete the old classifiers, and fix what the measurement found
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0011, id:z0044
    > **Check-in:** stop for review after it. **Split here** if the tree needs more than a session of changes.
    > **Split (2026-11-05, from id:z0049's review):** turning the rules on by default beside the old ones is id:z0065 (it only refuses more); this task is now the half that accepts more: delete the old rules and `src/summary_pass.zrl`, with the rejection differential, and the docs and twin lists. The fixes of the measurement are id:z0060 to id:z0063, and the `unsafe fn` exemption item moved to id:z0063, which narrowed it to `Raw`.
    > **Depends also:** id:z0065, id:z0063.
    > **Depends also (2026-11-05):** id:z0074 (the old-refuses, new-accepts list), id:z0073 (the raw-pointer decision), id:z0075 (the checkpoint).

    - **Do:** make the new rules the default and remove `--provenance`; resolve every warn-mode rejection recorded in id:z0049 and id:z0011 (a real escape: fix the code; a common over-rejection: apply the decided fix; a leak through a by-value collection parameter: change the code); then delete `local_storage_external`, `local_is_external_target`, `rvalue_is_external_target`, `place_outlives_frame`, `rvalue_storage_external`, `storage_walk_zir`'s mask logic, `note_call_stores_zir`, the depth limits, `is_collection_type_name`, the same-parameter filters, and `src/summary_pass.zrl` (keeping `src/verify.zrl`'s stack-address check as an add-only second net).
    - **Flip probes and twin lists (including id:z0045's):** flip all closed `known_gap` probes (`gap_07`, `gap_11`, `gap_13`, `gap_16`, `gap_18`, `gap_21`, `gap_23`, `gap_26`, `gap_27`, `gap_28`, `gap_29`, `gap_32`, `gap_33`, `gap_36`, `gap_40`, `gap_41`, `gap_42`, `gap_44`, `gap_45`, `gap_47`, `gap_48`, `gap_49`, `gap_50`, `gap_51`, `gap_52`, `gap_53`, `gap_54`, `gap_55`) to `compile_reject` and remove their Known gaps entries in `doc/spec/safety_model.md` and `doc/SAFETY.md` §6. Fold in id:z0045: remove the 3402 `ref_{let,identity,phi}` twins (and any id:z0017 twins newly accepted when `summary_pass.zrl` is retired) from `bench/fuzz/store_grid_twin_rejections.txt`, flip `read_through_{ref,identity,phi}.zrl` from `expected compile fail` to running tests, add an `accept` probe for `id:z0045` and a regression test returning `s.as_slice()` from `String.with_capacity(a, cap)` (`a: &Arena`). Because retiring `summary_pass.zrl` and `local_storage_external` accepts more safe programs, run `scripts/check_reject_diff.sh <base>` and list every newly accepted program class in the completion note (none may be unsafe). Update `doc/SAFETY.md` §2.3 and §5–§6, `doc/spec/surface_syntax.md` (`#[borrows]`/`#[stores]`), `README.md`, `KNOWN_ISSUES.md` and `bench/fuzz/store_grid_expected_failures.txt`.
    - **End criterion of the series (the maintainer, 2026-11-06, at id:z0075):** zero unsafe programs accepted is the hard requirement (the grid, the safety probes, the rejection differential). Zero safe programs refused is not reachable by any checker that accepts no unsafe one; the target is that no remaining refusal is common in user code (the tests as its stand-in), each is a documented class in `KNOWN_ISSUES.md` §5 with a reason and a rewrite (id:z0017 audits them), and its diagnostic says what was found (id:z0066).
    - **Done when:** every unsafe store-grid cell (whole-program and modular) is rejected, no `known_gap` probe of this family remains, the self-hosting fixpoint holds, and `make test` and `make preflight` pass. Stop for review, then close id:z0045 (citing this commit on `main`) and start id:z0017 and id:z0013 (and renew the fuzz record per id:z0003).
    - **From id:z0092 (2026-11-06):** the old rules refuse making a `fn` item that stores into a global or another parameter into a value (`check_fn_value` in `src/verify.zrl`); the new rules have no counterpart, since a call through a `fn` value records no store into a global (design note §3, _Calls through a `fn` value_). Carry it over before deleting the old rules: id:z0096 is the closure half of the same route. **Depends also:** id:z0096.

- [ ] +audit +safety +AI-G @provenance id:z0045 A reference to a local carrier passed through a `let`, an identity call or a phi is refused
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0012
    > **Depends note:** (do not edit `src/summary_pass.zrl` before id:z0012 retires it; close with id:z0012). Over-rejection, not a hole; related to id:z0017.

    - **Now:** a safe program that hands a callee a reference to a local struct, and stores what the callee returns, is accepted when the reference is written in the call (`take_ref(&c)`) and refused when it first goes through a `let`, an identity function or an `if`. The callee returns the view the struct holds (`c.v`), not a pointer into the struct; the checker reads the result as a pointer into the caller's stack frame. Error: "region escape: returning a pointer to local stack storage via sret".
    - **In the grid:** all 3402 safe twins of the `ref_let`, `ref_identity` and `ref_phi` carriers (1134 each; id:z0041) are refused, and every twin of `ref_direct` is accepted. They are in `bench/fuzz/store_grid_twin_rejections.txt`: `grep -E '__ref_(let|identity|phi)__' bench/fuzz/store_grid_twin_rejections.txt`.
    - **Reproducer** (checked on the compiler of this commit, and the compiler before id:z0007 refuses it too, so it is not caused by that change). With `let r = &c;` and `take_ref(r)` in `f`, it is refused; with `take_ref(&c)` and no `let`, it is accepted, builds with `scripts/build_zrl.sh`, and exits 0:

    ```zoril
    struct Carrier { v: [i32] }
    fn take_ref(c: &Carrier) -> [i32] { return c.v; }

    fn f(out: &mut [i32], view: [i32]) {
        let c = Carrier { v: view };
        let r = &c;
        *out = take_ref(r);
    }

    fn main() -> i32 {
        let data = [42, 0];
        let mut dest: [i32] = @slice(0 as *i32, 0);
        f(&mut dest, &data);
        return dest[0] - 42;
    }
    ```

    - **Same refusal, other forms:** `take_ref(id_ref(&c))` with `fn id_ref(c: &Carrier) -> &Carrier { return c; }`, and `let r = if pick() > 0 { &a } else { &b }; take_ref(r)` with two carriers `a` and `b` and `fn pick() -> i32 { return 1; }`.
    - **Do:** find where a reference that passed through a `let`, a call or a join stops being read as "the reference to `c`" and becomes "a pointer into `c`'s storage", so that the callee's result is tied to the whole frame. Fix it so `take_ref` is tied to what `c.v` points at, not to `c`. This makes the checker accept more, so run the rejection differential (`scripts/check_reject_diff.sh <base>`) and list every program the base rejects and the change accepts; none of the store grid's unsafe cells may become accepted. Move the three carriers' twins out of the twin record in the same commit, and add one of the forms above as an `accept` probe.
    - **Checks:** (this task makes a checker accept more and closes with id:z0012, so its review is `+AI-D`, as for every `+safety` check-in.)
      - C1: the three forms above (`let`, identity call, `if` join), each built with `scripts/build_zrl.sh` and run: exit 0; quote each.
      - C2: `grep -cE '__ref_(let|identity|phi)__' bench/fuzz/store_grid_twin_rejections.txt` is 0 after the change (3402 before); quote both.
      - C3: `sh scripts/check_store_grid.sh`: no unsafe cell accepted; quote its summary.
      - C4: the rejection differential (`scripts/check_reject_diff.sh <base>`): every program the base rejects and the change accepts, listed in the completion note with its reason; none unsafe.
      - C5: the `accept` probe under `bench/safety_matrix/probes/`, and `sh scripts/run_safety_matrix.sh` passing; quote its summary.
      - C6: `make test` and `make preflight-changed`, each `Total:` line quoted, citing id:z0012's commit on `main`.
    - **Finding (2026-11-03):** id:z0047's read-through rule (`os_through_plus` on reference arguments) already gives `got O={Param(1)} S={}` on all three forms (`tests/language/memory/origins/read_through_{ref,identity,phi}.zrl`), `src/verify.zrl` accepts them with zero errors, and the sole refusal (`src/summary_pass.zrl:716`, "region escape: returning a pointer to local stack storage via sret") comes from `InterprocSummaryPass`, which id:z0012 retires and deletes. Do not change `src/summary_pass.zrl` beforehand; close this task with id:z0012 once the 3402 twins leave `bench/fuzz/store_grid_twin_rejections.txt`, the `accept` probe is added, and the rejection differential is recorded, citing id:z0012's commit on `main`.

- [ ] +audit +AI-D @provenance id:z0017 A3.5 Twelve safe store-grid twins are rejected
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0012
    > **Depends note:** (do not debug `src/summary_pass.zrl` before id:z0012 deletes it). Over-rejection audit, not a hole.

    - **Cells (before id:z0012):** `{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{closure,param_65}__call_struct_mut__frame_ends` (12 cells) plus 96 cells exposed by id:z0008 in `bench/fuzz/store_grid_twin_rejections.txt`, rejected today by `src/summary_pass.zrl` ("region escape: storing local stack pointer into caller memory"). Also note the sibling found in id:z0047's review: passing a local struct `RefHolder { r: &c }` by value to `take_holder(h)` retains `Frame(c)` (`os_reach_all`).
    - **Over-rejection from id:z0007 (found in its review, 2026-11-03):** liveness borrows are tracked per local, not per field, so `w.s = v.as_slice(); let x = w.s[0]; a.reset(); return x - 42 + w.t - 3;` is refused at `a.reset()` because `w` stays live for `w.t`.
    - **Do (after id:z0012):** inspect every twin still listed in `bench/fuzz/store_grid_twin_rejections.txt` once `summary_pass.zrl` is gone (`param_65` twins should be accepted via the overflow bit; `closure`/`fn`-value twins: Decision 3 is decided (id:z0088), so any still refused after id:z0092 to id:z0094 is a finding, not a bound by design). Fix any unintended over-rejection without reopening any probe, add an `accept` probe for any fixed class, and document any deliberate precision bound (such as field-insensitive borrows) in `KNOWN_ISSUES.md` §5. `make test`, `make preflight-changed`, the rejection differential.
    - **Done when (2026-11-06, the series' end criterion, recorded on id:z0012):** every safe twin still in `bench/fuzz/store_grid_twin_rejections.txt` (and the modular list) is in a class `KNOWN_ISSUES.md` §5 names, with its reason and a rewrite, and none is common in the tests. `closure`/`fn`-value twins follow id:z0088's decision, not the note above.
