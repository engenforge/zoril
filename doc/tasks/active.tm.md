---
project: zoril
status: Active
sprint: 2026-S1
date: 2026-11-03
---

# Current Sprint

Open work, in execution order from top to bottom, in five groups. (1) Landing the two reviewed branches and recording the newly confirmed holes: Z-0054 (merge `gap_40`–`gap_44` and add `gap_45`–`gap_46`), Z-0047 (rebase and merge the reviewed origin-sets branch `claude/gallant-feynman-kiu6ru`), Z-0055 (amend `doc/design/provenance.md` with the reviewed transfer rules and pre-1.0 decisions), and Z-0056 (fix the 1-based `locals[id]` lookup hole). (2) The provenance and liveness hardening series: Z-0048 (rules under `--provenance`), Z-0046 (two-module grid diagnosis), Z-0010 and Z-0057 (compact SCC call summaries with `ParamAddr`/`ParamContents`, then pairwise `.zri` edges), Z-0049 (tree-wide warn measurement, placed after Z-0010 so recursive `Unknown` spread does not swamp it), Z-0011 (checked `#[borrows]`/`#[stores]`/`&self`, narrowing forbidden), Z-0044 (intra-frame `Arena::reset` liveness through pointers, reusing Z-0010's summary), and Z-0012 (`--provenance` on by default, old classifiers and `summary_pass.zrl` retired). (3) Post-series twin audits and standing review rounds: Z-0045, Z-0017, Z-0013. (4) Tooling and diagnostics: Z-0014, Z-0015, Z-0016. (5) Z-0004 and Z-0005, the benchmark measurement and decision, last because a session never starts one unprompted. Each `+safety` implementation task in the hardening series is a check-in: stop for review after it. Finished tasks stay at the top until `tm sweep` rotates them. Deferred work is in `future.tm.md`. Every `+safety` task follows the safety rules in `AGENTS.md`: the rejection differential for a change that accepts more, and nothing beyond what the task names in the same commit.

- [x] +safety +tests Z-0054 Merge the `gap_40`–`gap_44` branch and add `known_gap` probes for the two newly confirmed escape holes
    > **Created:** 2026-11-03
    > **Completed:** 2026-11-04 git:e4d7dbe

    - **Branch disposition (`claude/gallant-feynman-kiu6ru-gaps-40-44`, commit `f23bf57`):** **merge into `main` (do not discard).** Verified in a scratch worktree: `f23bf57` sits cleanly on `main` (`977f1f4`), adds `gap_40_local_mutref_field_escape`, `gap_41_callee_field_escape`, `gap_42_box_field_escape`, `gap_43_box_field_reset` and `gap_44_borrows_attr_reset`, updates `doc/spec/safety_model.md`, `doc/SAFETY.md` and `README.md`, and passes `check_safety_model.sh`, `check_safety_figures.sh`, `check_comment_noise.sh` and `run_safety_matrix.sh` (all five report `[SKIP]`). Optional cleanup while touching them: drop the unused `fn set_s` helper copied into `gap_40` and `gap_42`.
    - **New hole 1 (`gap_45_closure_mutref_field_escape`):** confirmed during Z-0047's second-model review; add with a Known gaps entry in `doc/spec/safety_model.md` (widening `gap_40`–`gap_43`'s route class to include a closure capturing `&mut` to a local) and updated counts in `doc/SAFETY.md` and `README.md`:

    ```zoril
    import "mem.zrl";
    import "vec.zrl";
    use mem::Arena;
    use vec::Vec;
    struct W { s: [i32], t: i32 }
    fn mk_w() -> W { return W { s: @slice(0 as *i32, 0), t: 0 }; }
    fn f(out: &mut [i32]) {
        let a = match Arena.new(65536) { Result.Ok(a) => a, Result.Err(_) => { return; } };
        let mut v = Vec::<i32>.new_in(&a);
        v.push(42);
        let mut w = mk_w();
        {
            let s = v.as_slice();
            let r = &mut w;
            let mut cl = || { r.s = s; };
            cl();
        }
        *out = w.s;
    }
    fn main() -> i32 {
        let mut dest: [i32] = @slice(0 as *i32, 0);
        f(&mut dest);
        let a2 = match Arena.new(65536) { Result.Ok(a) => a, Result.Err(_) => { return 1; } };
        let mut v2 = Vec::<i32>.new_in(&a2);
        v2.push(77);
        return dest[0];
    }
    ```

    - **New hole 2 (`gap_46_call_ret_mutref_off_by_one`):** `storage_walk_zir` and `note_call_stores_zir` index 0-based `locals` with 1-based `Local.id`, so when `dst` is the last local, `pl_base_ty` reads out-of-bounds as `0`, `base_is_ref` is false, and `stash`'s store summary stays empty (exits 77 on `main`, whereas adding a dead `let _keep: &i32 = &n;` immediately after `dst` is refused):

    ```zoril
    import "mem.zrl";
    import "vec.zrl";
    use mem::Arena;
    use vec::Vec;
    struct Slot { out: &mut [i32] }
    fn unwrap_slot(h: Slot) -> &mut [i32] { return h.out; }
    fn stash(h: Slot, s: [i32]) {
        let dst = unwrap_slot(h);
        *dst = s;
    }
    fn f(out: &mut [i32]) {
        let a = match Arena.new(65536) { Result.Ok(a) => a, Result.Err(_) => { return; } };
        let mut v = Vec::<i32>.new_in(&a);
        v.push(42);
        stash(Slot { out: out }, v.as_slice());
    }
    fn main() -> i32 {
        let mut dest: [i32] = @slice(0 as *i32, 0);
        f(&mut dest);
        let a2 = match Arena.new(65536) { Result.Ok(a) => a, Result.Err(_) => { return 1; } };
        let mut v2 = Vec::<i32>.new_in(&a2);
        v2.push(77);
        return dest[0];
    }
    ```

    - **Verification:** `sh scripts/run_safety_matrix.sh` (all seven report `[SKIP]`), `sh scripts/check_safety_model.sh`, `sh scripts/check_safety_figures.sh`, `make test`.

    - **Done (2026-11-04):** `gap_40`–`gap_44` cherry-picked (`8f602d7`, `main` had moved past `977f1f4`), `gap_45` and `gap_46` added in `e4d7dbe` (both `known_gap`, exit 77), the unused `set_s` dropped from `gap_40`/`gap_42`; the figures are 460 probes, 24 `known_gap`. Checks: `sh scripts/run_safety_matrix.sh` 436/460 passed, 0 mismatches (24 `[SKIP]`), `check_safety_model.sh`, `check_safety_figures.sh` and `check_comment_noise.sh` pass; `make test` on the combined branch: 3215 run, 3215 passed, 0 failed, 52 skipped.

- [x] +safety +tests Z-0047 B1.1 Origin sets per local on ZIR, computed and dumped, with no rule using them
    > **Created:** 2026-11-03 **Split from:** Z-0009. **Depends:** Z-0006, Z-0054. **Check-in:** second-model review complete; ready to rebase and merge.
    > **Completed:** 2026-11-04 git:9efdac7

    - **Build:** in `src/check_zir.zrl`, beside the existing analyses and changing no accept/reject decision, a forward, flow-insensitive fixpoint giving every local `L` two origin sets (`doc/design/provenance.md` §3): `O(L)`, the origins of the addresses it holds, and `S(L)`, the origins of the storage it owns, over `Frame(L)`, `Param(i)` (bit 63 meaning "63 or later"), `Static` and `Unknown`; field-insensitive.
    - **Transfer:** every `ZirRvalue` form gets a rule, so an unhandled form fails the build (an `// exhaustive:` match). That covers `Use`, `Ref`, `RefMut`, `Call`, `CallPtr`, `StructLiteral`, `EnumVariant`, `EnumPayload`, `Tuple`, `Array`, `ArrayRepeat`, `Boxed`, `Cast`, `PtrFromInt`, `GlobalAddr`, `StringConst`, `FuncAddr` with its environment, `GetEnv`, `Syscall` and `Intrinsic`; the scalar forms yield nothing. Calls read the existing summaries (`ret_ties`, `ret_storage`, `storage_known`), and a `CallPtr` or summary-less call yields `Unknown`. A projected write `x.f = rv` (not through a dereference) adds to `x`.
    - **Ownership:** whether a type owns storage comes from its structure (it contains a `Box`, an owning raw pointer, or a type that does), never `is_collection_type_name`. By-value parameters are locals (`Frame`); the referent of a reference parameter is `Param(i)`.
    - **Settle the open question** of the design note §3, a read through a reference. The note suggests that a read through `r` yields `O(L)` for each `Frame(L)` in `O(r)`, and stays `Param` or `Unknown` otherwise. Decide it with probes, and say in `doc/design/provenance.md` which rule holds and what Z-0045's reproducer gives under it.
    - **Observe it:** a developer option, for example `--emit-origins`, prints each function's `O` and `S` per local, so the sets can be tested without a rule. Golden tests for the shapes the note names: a field write, a chain of ten copies, an enum payload and its `match` binding, a `fn`-value call, a closure capture, `Vec::new_in(&a)`, a by-value `Vec` parameter, a tuple-carried destination and value. Each golden test checks one local's sets, so a change shows as a diff.
    - **Constraints:** `src/` is compiled by stage1, so use only what the pinned stage1 accepts. Build warning-free. Measure the analysis's time on `src/`: it runs on every compile even with no rule reading it, so record the cost.
    - **Verification:** `make test`, `make preflight-changed`, and the golden tests. Nothing may be newly accepted or refused: the rejection differential shows 0 and 0.
    - **Built on branch `claude/gallant-feynman-kiu6ru` (2026-11-03, `e740616`..`e8fd27c`):** `compute_origins_zir` in `src/check_zir.zrl`, called from `run_body_passes_in_scratch` (`src/driver/module.zrl`) after `compute_ret_storage_zir`, read by no rule; `--emit-origins` option (`zoril --help`, `doc/man/zoril.1.scd`); 18 golden tests in `tests/language/memory/origins/` checked by `scripts/test_origins.sh`; open question settled in `doc/design/provenance.md` §3 (`os_through_plus` on tied reference arguments); median compile cost +68 ms (+2.8%) on `src/main.zrl` with byte-identical ZIL; `make test` (3215/3215) and `PREFLIGHT_BASE=705c037 make preflight-changed` green (31/31 mutations caught, reject-diff 0 newly accepted / 0 newly refused of 69,093 programs).
    - **Second-model review (2026-11-03, Argon on `e8fd27c`):**
        1. `scripts/test_origins.sh` and static gates confirmed. Both take-outs reproduced: reading tied references with `os_reach_all` fails all four `read_through_*` golden tests (`Frame(c)`/`Frame(v)`/`Frame(a), Frame(b)`); reading `EnumPayload` as `Use` fails `match_binding.zrl` (`item O={}`) and `vec_new_in_local.zrl`.
        2. Gap-probe sets confirmed (`gap_13`, `gap_16`, `gap_32`, plus `gap_40`–`gap_42` all carry `Frame` or `Unknown`), **except two refusal claims refuted:** `gap_07` stays open under Z-0048 because Z-0048 still reads `stash_pair`'s old `i != j` summary (closes in Z-0010), and `gap_11` is **not** closed by `{Env}` alone because `_closure_0` has `out O={Env}` and `routed O={Env}` (no `Frame` or `Unknown`), identical to the safe twin `fn safe(out: &mut [i32], view: [i32]) { let mut cl = || { *out = view; }; cl(); }`.
        3. Sibling routes: reborrow `&*r`, local `&c` method receiver (`r.view()` vs `r.field_ref()`), and direct/generic trait methods give clean `O={Param(0)}`; a by-value struct holding `&c` (`take_holder(h)`) over-conservatively retains `Frame(c)` (`os_reach_all`); `&&T` retains `Frame(c)` as required by a 1-bit `ret_ties` mask; and a zero-arg closure writing through a captured `&mut w` (`gap_45` in Z-0054) leaves `w O={}` because `CallPtr(_, args)` ignores `callee` and `FuncAddr(_, env)` adds `Frame(env_ptr)` instead of copying `O(env)`.
        4. Confirmed Claude's three flags and the `locals[id]` lead: (a) `os_owns` marks `Lexer` as an owner (`from_byval_lexer` gives `view O={Param(0), Frame(lex)}`, untied `Lexer` gives `O={Frame(_1)}`), assigned to step 1 of Z-0048; (b) recursive cycles leave `storage_known = false` and spread `Unknown` (14 sites in 7/22 functions of `src/main.zrl`), so Z-0049 moves after Z-0010/Z-0057; (c) 1-based `locals[id]` in `note_call_stores_zir` and `storage_walk_zir` is an active `exit 77` hole (`gap_46` in Z-0054), assigned to Z-0056.
    - **Branch disposition (`claude/gallant-feynman-kiu6ru`, `e8fd27c`):** **rebase onto `main` (after Z-0054) and merge without reworking `src/check_zir.zrl` first** (do not discard; no rule reads `O`/`S` yet, so merging preserves the verified 0/0 differential). During the rebase: (1) resolve `doc/tasks/active.tm.md` by keeping `main`'s updated task list with Z-0047 marked `[x]` complete (`> **Completed:** 2026-11-03 git:<sha>`), (2) reconcile `doc/SAFETY.md` §5 figures (`sh scripts/check_safety_figures.sh`) with §6 probe/gap counts from Z-0054, (3) correct the `gap_07`/`gap_11` bullet if carrying `e8fd27c`'s commit message text, (4) run `make test` (`bench/fuzz/README.md` goes stale for `src/`), merge, and run `tm sweep` in a commit of its own to rotate Z-0047 to `completed.tm.md`.
    - **Done (2026-11-04):** rebased onto `main` by cherry-picking `e740616` and `92be871` (`f76d2a8`, `9efdac7`); the two task-note commits were dropped because `main` already carries the review findings, and no `src/check_zir.zrl` rework was done. `doc/SAFETY.md` §5 figures match (`check_safety_figures.sh`). Checks: `make test` 3215 run, 3215 passed, 0 failed, 52 skipped; `make preflight-changed` exit 0 (mutations caught, fixpoint, 1170 run / 1170 passed). The rejection differential (`scripts/check_reject_diff.sh 6d0747b`) was still running when this was committed; its result is added below. `bench/fuzz/README.md` is stale for `src/`. The benchmark files the run wrote under `bench/` were deleted.

- [ ] +docs +safety Z-0055 B1.1b Amend `doc/design/provenance.md` with the reviewed transfer rules and pre-1.0 language decisions
    > **Created:** 2026-11-03 **Depends:** Z-0047. **Check-in:** second-model review before Z-0048 starts.

    - **Do:** update `doc/design/provenance.md` after Z-0047 merges so the note matches what Z-0048, Z-0010, Z-0057 and Z-0011 will implement:
        1. **Checked contracts (Decision 1):** `#[borrows(..)]`, `#[stores(..)]` and `&self` elision are checked against the body; listing wider ties/stores is legal, narrowing in safe code is a compile error.
        2. **Structural ownership (Decision 2):** a type owns storage iff it is `Box<T>`, implements `Drop` (`Arena`, `BufWriter`, `File`, `FileLock`), is one of the four stdlib collections designated until collection `Drop` lands (`Vec`, `String`, `ByteVec`, `HashMap`), or contains an owning type by value. Raw pointers (`*T`/`*mut T`) do not make `Lexer`, `Parser`, `ArenaMark` or `Args` owners.
        3. **Closures vs `fn` pointers (Decision 3):** defer splitting `fn` pointers from closures until Z-0049's post-fixpoint measurement; record that monomorphized `Fn` traits are rejected.
        4. **Closure environments at `FuncAddr` and `CallPtr` (`gap_11` and `gap_45`):** correct §4's `gap_11` row (`{Env}` inside `_closure_0` is identical on `gap_11` and its safe twin). `FuncAddr(_, env)` copies `O(env)` (`{Frame(env_struct)}`), and `CallPtr(callee, args)` treats `os_through(O(callee))` as an implicit read-write argument alongside `args` in both unknown-call store effects and the unknown-call store check.
        5. **Parameter split, compact summaries, and pairwise `.zri` (`Z-0010` / `Z-0057`):** split parameter seeding into `ParamAddr(i)` (the parameter's own slot, feeding `ret_storage`) and `ParamContents(i)` (what parameter `i` reaches, feeding `ret_ties`); iterate Tarjan SCCs over compact per-function transfer summaries rather than retaining every function's ZIR in memory; serialize pairwise `i -> j` store edges (with bit 63 overflow in both directions) and separate `ret_storage`/`ret_ties` masks in `.zri`.
        6. **Scalar, cast and `extern` boundary:** casts and pointer-width arithmetic (`usize`/`isize`/`u64`/`i64`, `Vec.get`) preserve origins; narrow scalars (`<= 32` bits, `bool`, `char`, `f32`) clear them; `PtrFromInt` adds `Unknown`; unannotated `extern "C"` calls yield `{Static}` while safe wrappers carry `#[borrows(..)]`.
    - **Verification:** `make test` (`md-check`, `safety-model`, `comment-noise`), then stop for second-model review.

- [ ] +safety +tests Z-0056 Fix 1-based `Local.id` lookup in `note_call_stores_zir` and `storage_walk_zir`
    > **Created:** 2026-11-03 **Depends:** Z-0054, Z-0047. **Check-in:** stop for review after it. **Closes:** `gap_46_call_ret_mutref_off_by_one`.

    - **Why its own task:** Z-0048 leaves default-mode behaviour unchanged (`0` newly accepted, `0` newly refused without `--provenance`), whereas fixing `locals[id]` in `note_call_stores_zir` (`src/check_zir.zrl:5009`) and `storage_walk_zir` (`src/check_zir.zrl:5241`) flips `gap_46` in default mode and gives Z-0048 accurate `stores_storage` inputs before Z-0010 replaces `storage_walk_zir`.
    - **Do:** look up `jb` and `pl.base` via `os_local_ty(locals, id)` (matching `locals[li].id == id`, 1-based) instead of indexing `locals[id]` directly; audit every other `locals[...]` index in `src/check_zir.zrl` as sibling sites. Flip `gap_46_call_ret_mutref_off_by_one` to `compile_reject`, remove its Known gaps entry and `doc/SAFETY.md` §6 count, and add an accepted twin (`stash(Slot { out: out }, param_view)`).
    - **Verification:** take the fix out and watch `gap_46` compile and exit 77 again; `sh scripts/run_safety_matrix.sh`, `make test`, `make preflight-changed`, the rejection differential; `bench/fuzz/README.md` stays stale for `src/`. Stop for review.

- [ ] +safety +tests Z-0048 B1.2 The store and return rules on the origin sets, under `--provenance`
    > **Created:** 2026-11-03 **Split from:** Z-0009. **Depends:** Z-0047, Z-0055, Z-0056. **Check-in:** stop for review after it.

    - **First, two transfer fixes from Z-0047's review (in `src/check_zir.zrl`):**
        1. **Structural `os_owns` (Decision 2):** count `ILType.Boxed`/`BoxedMut`, types implementing `Drop`, the four designated stdlib collections (`Vec`, `String`, `ByteVec`, `HashMap`), and aggregates containing an owning type by value; remove `ILType.RawPtr`/`RawPtrMut` from `os_owns`. Update `tests/language/memory/origins/box_cast.zrl` (`S={}`) and add a golden test showing a view read through `&Lexer` carries no `Frame(lex)`.
        2. **Closure environment at `FuncAddr` and `CallPtr`:** `FuncAddr(_, env)` copies `O(env)` (`{Frame(env_struct)}`), and `CallPtr(callee, args)` includes `os_through(O(callee))` alongside `args` in `os_unknown_call_effects` and in the unknown-call store check. Add golden/twin tests for `gap_11`, `gap_45` (`w` gains `Frame(a)` + `Unknown`), and the safe twin `fn safe(out: &mut [i32], view: [i32]) { let mut cl = || { *out = view; }; cl(); }` (accepted under `--provenance`).
    - **Rules** (design note §3): a store through a reference, into a closure capture or into a global, whose destination origins contain anything but this frame's `Frame` origins, accepts no value with a `Frame` or `Unknown` origin. A return carries no `Frame` or `Unknown` origin. A call applies the store rule to each `i -> j` of the callee's existing store summary, `j` equal to `i` included; an unknown call (`CallPtr` or `storage_known` false) checks every argument (plus `os_through(O(callee))` for `CallPtr`) against every other, itself included.
    - **Flag:** `--provenance` adds the rules to the old ones (it never removes a rejection), and `--provenance=warn` prints what the new rules refuse and the old ones accept, as warnings that do not fail the compile. It is off by default; plumb it like `--checked` (`src/main.zrl` `Options`) and through `zbuild`, and document it in `zoril --help` and the man page (`make man`).
    - **Probes:** run every safety probe with the flag. Record which open gaps close under `--provenance` (expected: `gap_11`, `gap_13`, `gap_16`, `gap_18`, `gap_21`, `gap_23`, `gap_26`, `gap_29`, `gap_32`, `gap_36`, `gap_40`, `gap_41`, `gap_42`, `gap_45`; their `known_gap` headers stay until Z-0012 makes the flag the default) and list what remains for Z-0010 (`gap_07`, `gap_27`, `gap_28`, `gap_33`). Run the store grid with the flag (`ZORIL_CC` wrapper) and record newly rejected unsafe cells and newly refused twins.
    - **Verification:** `make test` with the default unchanged (0 newly accepted and 0 newly refused without `--provenance`), `make preflight-changed`, the probes and the grid with the flag. Stop for review.

- [ ] +audit +safety Z-0046 Find why the interface build refuses 35 store-grid cells the whole-program build accepts
    > **Created:** 2026-11-03 **Diagnosis, not a fix.** Found by Z-0042's comparison. **Before:** Z-0010 and Z-0057, so the `.zri` summary design acts on the answer.

    - **Question:** when a callee is compiled to an interface (`-c --write-interface`) and its caller reads that interface (`--iface-dir`), 35 of the 318 two-module cells are refused that the whole-program build accepts. Is the interface path's behaviour the right one, which the whole-program build should share, or is it an over-rejection, or does it cover only a part of what the whole-program path covers? Answer it before anyone changes either path.
    - **The cells,** all with the `direct` carrier and the `frame_ends` invalidation (`<source>__direct__<path>__<destination>__frame_ends`): 30 with the `string` source, for each of the paths `helper`, `two_level_helper`, `fn_val`, `mutual_rec` and `param_65` and each of the destinations `call_struct_mut`, `closure_call_mut`, `closure_capture_mut`, `closure_owned_capture`, `local_field_assigned_out` and `ten_copies`; the `string` source with `deref_out` and each of `same_param`, `store_mutual_rec` and `store_param_65`; and `store_mutual_rec` into `deref_out` with the `arena_vec` and `local_vec` sources. The first to look at: `string__direct__fn_val__call_struct_mut__frame_ends`.
    - **Regenerate the list:** `lua scripts/fuzz/store_grid.lua --generate-modular build/z46`, then compile each cell both ways as `scripts/check_store_grid_modular.sh` does; the cells that are in `bench/fuzz/store_grid_expected_failures.txt` (whole-program accepts) and not in `bench/fuzz/store_grid_modular_expected_failures.txt` (two-module accepts) are the 35.
    - **First cell, both ways:** whole-program (`lua scripts/fuzz/store_grid.lua --emit string__direct__fn_val__call_struct_mut__frame_ends`, then `zoril --emit-zil`) compiles. Two-module (path functions in `pathmod.zrl` compiled with `-c --interproc-summary --write-interface`, the cell compiled with `-c --interproc-summary --iface-dir`) is refused: "region escape: callee stashes local stack pointer into global memory". The cell stores into `out` through `get_struct_slot(out)`, a local struct, not into global memory, so the message does not describe the cell.
    - **What running them shows:** 34 of the 35 cells, built whole-program, run and exit 42: the stored string or vector is still intact, because collections are not freed at scope end. Only `arena_vec__direct__store_mutual_rec__deref_out__frame_ends` reads clobbered memory (exit 77), the shape of `gap_28`. So for 34 cells the interface path refuses a program that works today, and would be the one that stays correct once the `Box` and collection drop series makes frees real.
    - **To establish:** (1) which summary field differs between the two paths for this cell (compare `pathmod`'s interface with what the whole-program pass computes for `forward_fn_target`); (2) whether an interface that omits a field reads as "unknown, so strict", which would explain a stricter result for any callee compiled separately; (3) why the `string` source is so prominent, when `arena_vec` and `local_vec` cells with the same paths are refused by both builds; (4) whether the one `arena_vec` cell is `gap_28` showing in one path only. Record each finding on this task as it is made.
    - **Done when:** the task states whether the interface path is right, over-strict, or incomplete, with the evidence, and names the task that acts on it (`Z-0010` or `Z-0057`). No compiler change in this task.

- [ ] +safety +tests Z-0010 B2 One call summary from the origin sets, iterated over recursive calls, written to the `.zri`
    > **Created:** 2026-11-03 **Depends:** Z-0008, Z-0048, Z-0046. **Check-in:** stop for review after it. **Split:** in-memory SCC summary here (B2.1); pairwise `.zri` serialization in Z-0057 (B2.2).

    - **Build (B2.1, in-memory summary and SCC fixpoint under `--provenance`):** split parameter seeding into `ParamAddr(i)` (the parameter's own slot, feeding `ret_storage`: e.g. `&c.n`) and `ParamContents(i)` (memory reached through parameter `i`, feeding `ret_ties`: e.g. `c.v` in `take_ref`), with bit 63 meaning "parameter 63 or later" in both directions, and pairwise store edges `i -> j` (`j` equal to `i` included, plus global/static). Because `run_body_passes_in_scratch` discards each function's ZIR after lowering, extract a compact per-function transfer summary during body lowering and iterate strongly connected components of the call graph from empty to a fixpoint before running `--provenance`'s call checks, removing the `storage_known = false` `Unknown` spread across recursive cycles.
    - **Expected to close (under `--provenance`, whole-program):** `gap_07_path_same_param`, `gap_27_closure_local_param_65`, `gap_28_call_summary_mutual_recursion`, `gap_33_param_65_arena_slice_store`, and any recursive-cycle `unknown-call` sites in `src/`.
    - **Verification:** `make test` with default unchanged, `make preflight-changed`, `--emit-origins src/main.zrl` showing 0 recursive-cycle `unknown-call` sites, and the safety probes and whole-program store grid under `--provenance`. Stop for review; this task stays open or closes once Z-0057 completes the `.zri` half.

- [ ] +safety +tests Z-0057 B2.2 Write and read pairwise store edges and separate return masks in `.zri` under `--provenance`
    > **Created:** 2026-11-03 **Split from:** Z-0010. **Depends:** Z-0010, Z-0046. **Check-in:** stop for review after it.

    - **Build:** extend `.zri` emission (`src/interface_print.zrl`) and `.zri` parsing so imported functions preserve Z-0010's pairwise `i -> j` store edges (not two flat `stores`/`into` masks whose Cartesian product conflates independent parameters), `Param(>=63)` overflow bits, and both `ret_storage` (`ParamAddr`) and `ret_ties` (`ParamContents`). Under `--provenance`, callers consume this summary directly and ZIL summary writers no longer overwrite it.
    - **Tests:** round-trip tests in `tests/modular/iface_attrs/` for pairwise `i -> j` vs independent `i -> j, k -> l`, `i -> i` same-parameter store, parameter 65, and `ret_storage` vs `ret_ties`; modular store grid (`scripts/check_store_grid_modular.sh`) under `--provenance` closing the two-module cells from Z-0008 and acting on Z-0046's diagnosis.
    - **Verification:** `make test` with default unchanged, `make preflight-changed`, whole-program vs `zbuild` parity under `--provenance`. Stop for review.

- [ ] +safety +tests Z-0049 B1.3 Measure what `--provenance` newly rejects in the tree
    > **Created:** 2026-11-03 **Split from:** Z-0009. **Depends:** Z-0048, Z-0010, Z-0057.
    > **Moved after Z-0010/Z-0057 (2026-11-03):** before Z-0010's SCC fixpoint, recursive cycles in `src/` leave `storage_known = false` and spread `Unknown` (14 calls in 7/22 functions of `src/main.zrl` alone), which would swamp the measurement.

    - **Do:** compile `src/`, `stdlib/`, `tools/` and `corpus/` with `--provenance=warn` and record every warning as a real escape, a leak (a by-value collection whose view outlives it: `gap_32`'s class), or an over-rejection (for example the field-insensitive struct case of design note §5, a struct-field reference carrier `take_holder(h)`, or `fn`-value/closure calls). Change none of that code. Each class with its count and one example goes on this task.
    - **Decisions this measurement feeds:** (1) whether field sensitivity on direct struct fields is needed before Z-0012; (2) the deferred Decision 3 question — how many over-rejections or remaining gaps come from `fn`-value/closure routes and whether downward-only closures are warranted. Over-rejections common enough to block Z-0012 get a task of their own before Z-0012.

- [ ] +safety +tests Z-0011 B3 Declarations are checked against the body: `#[borrows(..)]`, `#[stores(..)]`, the `&self` default
    > **Created:** 2026-11-03 **Depends:** Z-0049. **Check-in:** stop for review after it.

    - **Rule (Decision 1):** a declaration may list more than the body proves (a wider public contract), never less. Result ties and stores come from the body for every function with one; the `&self` elision default, `#[borrows(..)]` and `#[stores(..)]` apply to bodyless items (`extern`, trait signatures, `.zri` imports) and are checked wherever a body exists. Narrowing in safe code is a compile error (`CHANGELOG.md` pre-1.0 note). Each of the tree's 82 `#[borrows()]` declarations (such as `Lexer.text_from`) is either proved unnecessary by Z-0010's `ParamAddr`/`ParamContents` summary and removed, or converted into an explicit, reviewed `unsafe` interior with a `// SAFETY:` comment, listed with its decision in the commit. **Stop and report** before changing a `pub` stdlib signature.
    - **Test expectation note:** `tests/error_reporting/err_stores_attribute_false.zrl` currently expects a wider `#[stores]` contract than the body performs to fail; under the wider-contract rule that test changes (stop and document the test change per `AGENTS.md`).
    - **Probes:** an unannotated `&self` method passing a parameter's borrow through, the same through a trait, and safe-code `#[borrows()]` laundering (`gap_30_borrows_attribute_launder` stays rejected; `gap_44_borrows_attr_reset` is rejected at the attribute under `--provenance`); accepted: a `&self` method returning a view of `self` and a wider `#[borrows]`/`#[stores]` public contract. `make test`, `make preflight-changed`. Stop for review.

- [ ] +safety +tests Z-0044 B0.1 A value stored into a local's field through a pointer to the local keeps its borrow
    > **Created:** 2026-11-03 **Check-in:** stop for review after it. **Closes:** `gap_37_local_mutref_field_reset`, `gap_38_param_field_reset`, `gap_39_method_self_field_reset`, `gap_43_box_field_reset`.
    > **Depends:** Z-0010, Z-0011.

    - **Scope (narrowed to intra-frame liveness, 2026-11-03):** the frame-escape siblings (`gap_40`–`gap_42` and `gap_45`) are handled by Z-0048/Z-0012's origin sets. This task fixes intra-frame `Arena::reset` / `free` / `@drop` liveness (`ActiveBorrow` in `src/check_zir.zrl`), where a slice written into a local struct's field or a `Box`'s contents through a local `&mut`, through a callee's `&mut` parameter, through `self` in a `&mut self` method, or through `*b` on a `Box` is skipped today (`place_writes_through_pointer`), letting `a.reset()` pass while the field is read afterwards.
    - **Do:** carry the stored value's borrows to the local (or `Box` local) the pointer refers to: for a local `&mut` or `Box` deref, through the pointer's borrow/ownership of that local; for a callee, through Z-0010's pairwise `i -> j` store summary (`#[stores(..)]` checked in Z-0011). Probe the sibling routes: a `&mut` held in a struct field, a reborrow, a closure capturing `&mut w` across `a.reset()`, and a trait method; also verify `gap_44_borrows_attr_reset` is rejected once checked `#[borrows()]` is active.
    - **Found by Z-0047 (pre-existing over-rejection):** `fn f(view: [i32]) -> i32 { let mut w = ...; let r = &mut w; r.s = view; ... }` called with stack `f(&data)` is refused today by `src/summary_pass.zrl`; confirm Z-0012's retirement of `summary_pass.zrl` removes that refusal without reopening any reset hole.
    - **Probes:** `gap_37`, `gap_38`, `gap_39` and `gap_43` flip to `compile_reject`, with an accepted twin for each (the field is read before `a.reset()`). Check the over-rejection recorded on Z-0017 does not grow.
    - **Verification:** `make test`, `make preflight-changed`, the rejection differential; `bench/fuzz/README.md` stays stale for `src/`. Stop for review.

- [ ] +safety +tests Z-0012 B4 Make `--provenance` the default, delete the old classifiers, and fix what the measurement found
    > **Created:** 2026-11-03 **Depends:** Z-0011, Z-0044. **Check-in:** stop for review after it. **Split here** if the tree needs more than a session of changes.

    - **Do:** make the new rules the default and remove `--provenance`; resolve every warn-mode rejection recorded in Z-0049 and Z-0011 (a real escape: fix the code; a common over-rejection: apply the decided fix; a leak through a by-value collection parameter: change the code); then delete `local_storage_external`, `local_is_external_target`, `rvalue_is_external_target`, `place_outlives_frame`, `rvalue_storage_external`, `storage_walk_zir`'s mask logic, `note_call_stores_zir`, the depth limits, `is_collection_type_name`, the same-parameter filters, and `src/summary_pass.zrl` (keeping `src/verify.zrl`'s stack-address check as an add-only second net).
    - **Flip probes and twin lists (including Z-0045's):** flip all closed `known_gap` probes (`gap_07`, `gap_11`, `gap_13`, `gap_16`, `gap_18`, `gap_21`, `gap_23`, `gap_26`, `gap_27`, `gap_28`, `gap_29`, `gap_32`, `gap_33`, `gap_36`, `gap_40`, `gap_41`, `gap_42`, `gap_44`, `gap_45`) to `compile_reject` and remove their Known gaps entries in `doc/spec/safety_model.md` and `doc/SAFETY.md` §6. Fold in Z-0045: remove the 3402 `ref_{let,identity,phi}` twins (and any Z-0017 twins newly accepted when `summary_pass.zrl` is retired) from `bench/fuzz/store_grid_twin_rejections.txt`, flip `read_through_{ref,identity,phi}.zrl` from `expected compile fail` to running tests, add an `accept` probe for `Z-0045` and a regression test returning `s.as_slice()` from `String.with_capacity(a, cap)` (`a: &Arena`). Because retiring `summary_pass.zrl` and `local_storage_external` accepts more safe programs, run `scripts/check_reject_diff.sh <base>` and list every newly accepted program class in the completion note (none may be unsafe). Update `doc/SAFETY.md` §2.3 and §5–§6, `doc/spec/surface_syntax.md` (`#[borrows]`/`#[stores]`), `README.md`, `KNOWN_ISSUES.md` and `bench/fuzz/store_grid_expected_failures.txt`.
    - **Done when:** every unsafe store-grid cell (whole-program and modular) is rejected, no `known_gap` probe of this family remains, the self-hosting fixpoint holds, and `make test` and `make preflight` pass. Stop for review, then close Z-0045 (citing this commit on `main`) and start Z-0017 and Z-0013 (and renew the fuzz record per Z-0003).

- [ ] +audit +safety Z-0045 A reference to a local carrier passed through a `let`, an identity call or a phi is refused
    > **Created:** 2026-11-03 **Depends:** Z-0012 (do not edit `src/summary_pass.zrl` before Z-0012 retires it; close with Z-0012). Over-rejection, not a hole; related to Z-0017.

    - **Now:** a safe program that hands a callee a reference to a local struct, and stores what the callee returns, is accepted when the reference is written in the call (`take_ref(&c)`) and refused when it first goes through a `let`, an identity function or an `if`. The callee returns the view the struct holds (`c.v`), not a pointer into the struct; the checker reads the result as a pointer into the caller's stack frame. Error: "region escape: returning a pointer to local stack storage via sret".
    - **In the grid:** all 3402 safe twins of the `ref_let`, `ref_identity` and `ref_phi` carriers (1134 each; Z-0041) are refused, and every twin of `ref_direct` is accepted. They are in `bench/fuzz/store_grid_twin_rejections.txt`: `grep -E '__ref_(let|identity|phi)__' bench/fuzz/store_grid_twin_rejections.txt`.
    - **Reproducer** (checked on the compiler of this commit, and the compiler before Z-0007 refuses it too, so it is not caused by that change). With `let r = &c;` and `take_ref(r)` in `f`, it is refused; with `take_ref(&c)` and no `let`, it is accepted, builds with `scripts/build_zrl.sh`, and exits 0:

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
    - **Verification:** `make test`, `make preflight-changed`, `sh scripts/check_store_grid.sh`, the rejection differential.
    - **Finding (2026-11-03):** Z-0047's read-through rule (`os_through_plus` on reference arguments) already gives `got O={Param(1)} S={}` on all three forms (`tests/language/memory/origins/read_through_{ref,identity,phi}.zrl`), `src/verify.zrl` accepts them with zero errors, and the sole refusal (`src/summary_pass.zrl:716`, "region escape: returning a pointer to local stack storage via sret") comes from `InterprocSummaryPass`, which Z-0012 retires and deletes. Do not change `src/summary_pass.zrl` beforehand; close this task with Z-0012 once the 3402 twins leave `bench/fuzz/store_grid_twin_rejections.txt`, the `accept` probe is added, and the rejection differential is recorded, citing Z-0012's commit on `main`.

- [ ] +audit Z-0017 A3.5 Twelve safe store-grid twins are rejected
    > **Created:** 2026-11-03 **Depends:** Z-0012 (do not debug `src/summary_pass.zrl` before Z-0012 deletes it). Over-rejection audit, not a hole.

    - **Cells (before Z-0012):** `{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{closure,param_65}__call_struct_mut__frame_ends` (12 cells) plus 96 cells exposed by Z-0008 in `bench/fuzz/store_grid_twin_rejections.txt`, rejected today by `src/summary_pass.zrl` ("region escape: storing local stack pointer into caller memory"). Also note the sibling found in Z-0047's review: passing a local struct `RefHolder { r: &c }` by value to `take_holder(h)` retains `Frame(c)` (`os_reach_all`).
    - **Over-rejection from Z-0007 (found in its review, 2026-11-03):** liveness borrows are tracked per local, not per field, so `w.s = v.as_slice(); let x = w.s[0]; a.reset(); return x - 42 + w.t - 3;` is refused at `a.reset()` because `w` stays live for `w.t`.
    - **Do (after Z-0012):** inspect every twin still listed in `bench/fuzz/store_grid_twin_rejections.txt` once `summary_pass.zrl` is gone (`param_65` twins should be accepted via the overflow bit; `closure`/`fn`-value twins remain `Unknown` by design unless Decision 3 changes). Fix any unintended over-rejection without reopening any probe, add an `accept` probe for any fixed class, and document any deliberate precision bound (such as field-insensitive borrows or `Unknown` `fn`-value calls) in `KNOWN_ISSUES.md` §5. `make test`, `make preflight-changed`, the rejection differential.

- [ ] +safety +research Z-0013 Review rounds: rotate reviewers over the compiler until the findings dwindle
    > **Created:** 2026-11-03 **Standing task;** a round reads and probes only, so it can run beside anything except a change to the area it reviews.

    - **A round:** one reviewer (a model or a prompt not used in the last round) takes one area - the type matcher and conversion sites, the borrow checker and its summaries, drop and move semantics, the stdlib's `unsafe` interiors against what safe code can reach, the FFI boundary, the runtime and `zilc` - probes what it suspects against `build/zoril`, and records each lead here as confirmed, refuted or unprobed, with its reproducer.
    - **Checklist:** every site that puts a value into an expected type (`let`, call argument, return, struct field, enum constructor, array literal and repeat, closure capture, method receiver, `match` arm, pattern binding); every type-matching and conversion function at depth above zero; every cast and what it lets safe code build; every place a size or length is narrowed; every check skipped for a special case (unit, `never`, zero length, constant operand); borrows of `static mut` held across a call or an assignment; the FFI boundary; the stdlib's `unsafe` blocks.
    - **Each confirmed hole** becomes a `known_gap` probe, a route class in `doc/spec/safety_model.md`, and a generator feature in `scripts/fuzz/gen.lua`; it is fixed by another session and fix-reviewed by a third before the next round. A fix states the rule it enforces in one sentence and defaults to the strict side for anything it cannot classify.
    - **Stopping rule:** rounds continue while a round with a fresh reviewer confirms a new hole; stop after two consecutive rounds from different reviewers confirm none.

- [ ] +tools Z-0014 `zilc` refuses text it does not recognise between declarations, and a file that is not ZIL
    > **Created:** 2026-11-03

    - **Now:** `zilc` exits 0 with no message on random bytes, and on `printf '\x01\x02 zz garbage\n'` it writes a stray global parsed out of the word `garbage`. `ZilParser.parse_module` (`tools/zilc/src/zil_parse.zrl`) dispatches on a declaration's first byte and skips any other byte, so text between declarations is dropped silently.
    - **Do:** at top level, after trivia, accept only the declaration forms of `doc/spec/intermediate_language.md` and report anything else as `zilc: line N: expected a declaration, found '<token>'` with exit 1; before parsing, refuse a NUL byte or invalid UTF-8 with one line. Keep the first-error behaviour.
    - **Tests:** a `tests/zilc/` case per refusal (a stray word between two functions, control bytes, a NUL byte), each failing before the change; take the check out and watch the stray-word case pass silently again. Remove or update the `KNOWN_ISSUES.md` entry. `make test`, `make preflight-changed`; the fuzz record goes stale for `tools/zilc/`.

- [ ] +diagnostics Z-0015 `zoril` stops after a bounded number of errors, and says when a file does not look like Zoril source
    > **Created:** 2026-11-03

    - **Now:** 300 KB of random bytes named `junk.zrl` gives about 139,000 error lines (12 MB); 160 KB of prose about 33,000. `zbuild` passes the same output through. Reproduce: `head -c 300000 /dev/urandom > junk.zrl; ./build/zoril -I stdlib=stdlib --emit-zil -o o.zil junk.zrl 2>&1 | wc -l`.
    - **Do:** count errors in `diag_start` (`src/diag.zrl`); past the limit (default 20) print one line naming `--error-limit N` (0 removes the limit) and exit 1. `zbuild --error-limit N` passes it to every `zoril -c`; both man pages and `--help` say so. Before lexing, refuse a NUL byte or invalid UTF-8 with one line; if the limit is reached before the first declaration, the stopping line says the file does not look like Zoril source. `src/diag.zrl` is in stage1's closure: use only what stage1 accepts (a `static mut` counter).
    - **Tests:** a NUL byte, invalid UTF-8, prose, and a program with 25 type errors (20 printed, then the stopping line; `--error-limit 0` prints all 25); the same through `zbuild` (`scripts/test_zbuild_errors.sh`). Check first that no existing error test expects more than 20 errors. Remove or update the `KNOWN_ISSUES.md` entry. `make test`, `make preflight-changed`.

- [ ] +tools Z-0016 `zbuild` builds a program written in ZIL, and refuses any other input with one line
    > **Created:** 2026-11-03

    - **Now:** `zbuild 01_arithmetic.zil` (from `corpus/zil/`) parses the ZIL as Zoril and prints about thirty `expected declaration` errors; the manual pipeline (`zilc`, `qbe`, `as`, `ld` with the runtime) works and exits 30.
    - **Do:** a root ending in `.zil` skips the module graph and the front end and runs `zilc`, `qbe`, `as` and the link with `zbuild`'s usual linker and runtime choice, honouring `-o` and the cache directory; `--checked` with a `.zil` root is refused with one line. A root ending in neither `.zrl` nor `.zil` is refused with one line naming both. Update `doc/man/zbuild.1.scd` (`make man`), `zbuild --help`, and "Starting from ZIL" in `doc/getting_started.md`.
    - **Tests:** with the installed `zbuild` (`scripts/test_user_paths.sh`), `corpus/zil/01_arithmetic.zil` exits 30 and every `corpus/zil/` file gives its expected exit code; the refusals for `foo.txt` and for `.zil` with `--checked`; `scripts/test_man_pages.sh`. Take the `.zil` branch out and watch the scenario fail. Remove or update the `KNOWN_ISSUES.md` entry. `make test`, `make preflight-changed`.

- [ ] +bench +measurement Z-0004 Measure how far the benchmark gate's measures move between cloud sessions
    > **Created:** 2026-11-03
    > **Session rule:** a new session records one sample only if asked to, so this task never starts a session.

    - **Why:** `bench/cross_lang/thresholds.cfg` is not in the tree, so `scripts/bench_threshold_check.sh` records a baseline on its first run on a host. Every cloud session starts on a fresh VM, so there the gate compares a run with itself and cannot fail. Of its three measures, `runtime_ratio_vs_gcc_o2` is relative to gcc on the same host; `clean_throughput_loc_s` and `incremental_rebuild_ms` are absolute and depend on the VM.
    - **Do:** in three to five separate cloud sessions, run `sh scripts/bench_cross_lang.sh --check-thresholds` on the same commit and record each measure, the CPU model (`/proc/cpuinfo`) and the load. Report the spread of each measure against the gate's 15% tolerance. Delete the files the run writes under `bench/`; commit nothing but this task's text.
    - **Sample 1 (2026-11-03, commit `fdb0c55`):** `Intel(R) Xeon(R) Processor @ 2.30GHz`, 4 vCPUs, 1-minute load average 2.46 at the start (a `make test` had just finished, so the host was not quiet). `clean_throughput_loc_s` 10177 (the run's own spread 288..297 ms, +3.1%), `incremental_rebuild_ms` 22, `runtime_ratio_vs_gcc_o2` 4.182, `peak_rss_mb_per_kloc` 2.973; the run took 42 s. Earlier on this same VM, an unrelated preflight recorded `clean_throughput_loc_s` 10072, 1.0% below this sample. That is one VM twice, not a spread between sessions.
    - **Sample 2 (2026-11-03, commit `fdb0c55`):** the same conversation, but on a freshly booted VM (booted 14:49 UTC, after the setup script changed), so not the VM of sample 1. `Intel(R) Xeon(R) Processor @ 2.30GHz`, 4 vCPUs, 1-minute load average 0.36 at the start. Run in a scratch worktree of `fdb0c55` whose `build/zoril` was built from that commit's compiler source and which rebuilt its own `zilc` and `zbuild`. `clean_throughput_loc_s` 9705 (the run's own spread 302..330 ms, +9.3%), `incremental_rebuild_ms` 20, `runtime_ratio_vs_gcc_o2` 4.095, `peak_rss_mb_per_kloc` 2.973; the run took 56 s. Against sample 1: clean -4.6%, incremental -9.1%, ratio -2.1%, RSS unchanged, all inside 15%. The bench outputs were deleted with the worktree.
    - **Still to do:** one to three more samples, each from a new cloud session on this commit. This task stays open until they exist; two samples are not a spread.

- [ ] +bench +decision Z-0005 Decide the benchmark gate's behaviour on a host without a committed baseline
    > **Created:** 2026-11-03 **Depends:** Z-0004.

    - **Options, from the measurement:** commit a baseline for the measures whose spread stays inside the tolerance; make the gate print a `[SKIP]` naming the reason for those that do not; and when no committed baseline exists, have the gate say so instead of recording one and passing.
    - **Recommendation (2026-11-03, until Z-0004's spread data decides it):**
        1. A host with no committed baseline gets a statement, not a pass. The gate stops recording a baseline on a first run and then printing "All performance thresholds within tolerance"; it prints `[SKIP] bench-thresholds: no committed baseline for <axis> (<reason>)` per axis and exits 0. Recording stays an explicit act (`sh scripts/bench_cross_lang.sh --record`).
        2. Commit a baseline for `runtime_ratio_vs_gcc_o2` only (4.182 in Z-0004's sample 1): it is relative to gcc -O2 on the same host, so it moves with the compiler and not with the VM. It is committed once Z-0004's samples keep its spread inside the 15% tolerance; otherwise it gets the `[SKIP]` too.
        3. `clean_throughput_loc_s` and `incremental_rebuild_ms` stay host-local. A host that has recorded its own baseline (a developer's machine) still compares against it; anywhere else they print `[SKIP]` naming "absolute measure, no baseline for this host".
    - **Why:** on a fresh VM the present gate compares a run with itself, so it cannot fail, and it says "within tolerance" anyway. A committed absolute baseline would pass or fail with the VM's speed, which tests the VM. Z-0004's single sample says nothing yet about other VMs; rule 2 is the part its data can overturn.
    - **Not done here:** the change to `scripts/bench_threshold_check.sh` and its tests. It needs a task of its own once Z-0004 has its samples.
    - **Reopened (2026-11-03):** the decision depends on Z-0004's measurements, so the task stays open until they exist; the recommendation above is not a decision yet.
