---
project: zoril
status: Active
sprint: 2026-S1
date: 2026-11-03
---

# Current Sprint

Open work, in execution order from top to bottom, in four groups. (1) The provenance and liveness hardening series: Z-0060 (the `extend_from_slice` hole Z-0049 found), Z-0061, Z-0062, Z-0063 and Z-0068 (the over-rejection classes Z-0049 measured, the origins of raw operations, and indexing in the origin walk), Z-0064 (the re-measurement that gates the default flip), Z-0011 (checked `#[borrows]`/`#[stores]`/`&self`, narrowing forbidden), Z-0044 (intra-frame `Arena::reset` liveness through pointers), Z-0066 (provenance diagnostics, before users see them), Z-0065 (the new rules on by default beside the old ones: refuses only more) and Z-0012 (old classifiers and `summary_pass.zrl` retired: accepts more, with the differential). (2) Post-series twin audits and standing review rounds: Z-0045, Z-0017, Z-0013. (3) Tooling and diagnostics: Z-0014, Z-0015, Z-0016, Z-0067. (4) Z-0004 and Z-0005, the benchmark measurement and decision, last because a session never starts one unprompted. Each `+safety` implementation task in the hardening series is a check-in: stop for review after it. Model tags: `+AI-D` marks tasks needing a deep-thinking model and `+AI-G` tasks suited to a general-purpose model; every `+safety` check-in review uses `+AI-D`. Finished tasks stay at the top until `tm sweep` rotates them. Deferred work is in `future.tm.md`. Every `+safety` task follows the safety rules in `AGENTS.md`: the rejection differential for a change that accepts more, and nothing beyond what the task names in the same commit.

- [ ] +safety +tests +AI-D Z-0062 B1.6 `Vec.push` of an element type that owns storage summarises a store of `Unknown`
    > **Created:** 2026-11-05 **Found by:** Z-0049 (class 2, about 480 warnings, mostly cascades). **Check-in:** stop for review after it. Over-rejection under `--provenance` only.

    - **Now:** pushing an owning element (`Vec<Vec<u32>>`, `Vec<String>`, `Vec<B>` with `B` holding a `Vec`) into memory reached through a parameter summarises `store Unknown -> Param(0)` and is refused by the call store rule. `Vec<[u8]>.push([u8])` and `Vec<u32>.push(u32)` are clean. The raw arena of Z-0049's first diagnosis is incidental: `self.w.push(Vec::<u32>.new())` warns with no arena (`build/z49/t/d.zrl`, `q3`). Must-accept reproducer (exits 0 by default, refused under `--provenance`):

    ```zoril
    import "vec.zrl";
    import "string.zrl";
    use vec::Vec;
    use string::String;
    fn add(v: &mut Vec<Vec<i32>>) { v.push(Vec::<i32>.new()); }
    fn adds(v: &mut Vec<String>) { v.push(String.new()); }
    fn main() -> i32 { let mut v: Vec<Vec<i32>> = Vec.new(); add(&mut v); let mut w: Vec<String> = Vec.new(); adds(&mut w); return (v.len() + w.len()) as i32 - 2; }
    ```

    - **Diagnose first:** find where the `Unknown` enters `push`'s instance for an owning `T` (its grow path, an `unsafe fn` callee that writes no summary, or the owner's `S` passed as a stored value). `--emit-origins` prints no generic instances: copy the instance into a non-generic test function, or widen the dump in a scratch build. Record the cause on this task before fixing.
    - **Do:** fix the cause, not `push`'s declaration. Must still be refused: pushing a `Vec<[i32]>` holding a frame view into a caller's `Vec<Vec<[i32]>>`. Golden test for the summary edge; the `add`/`adds` program as a provenance-group test; a mutant.
    - **Verification:** as Z-0061, plus the warn-mode count on `src/main.zrl`, `tools/zbuild`, `tools/zman` (expected: the `lower_expr`, `new_block`, `parse_expr` cascades go). Stop for review.

- [ ] +safety +tests +AI-D Z-0063 B1.7 Origins of raw operations: `@syscall` results, `@ptr_from_int` in safe code, and the `unsafe fn` exemption
    > **Created:** 2026-11-05 **Found by:** Z-0049 (class 3, the `local_mem.zrl` warning) and Z-0048's review (Finding 2, moved here from Z-0012). **Check-in:** stop for review after it.

    - **Now:** (1) `stdlib/os/linux.zrl:54` returns `@syscall(2, (&buf[0]) as *u8 as u64, ..) as i64`; the integer result carries the address argument's `Frame(buf)` and is refused by the return rule. (2) `stdlib/local_mem.zrl:36` returns a `box` holding `@ptr_from_int`'s `Unknown` and is refused (`fn mk3(n: u64) -> Box<H> { let p = @ptr_from_int<*u8>(n); return box H { p: p, n: n }; }`). (3) `stdlib/hashmap.zrl:184`, unless Z-0061 fixed it. (4) Z-0048 skips the new rules for every `unsafe fn` body (`src/driver/module.zrl`, `rules = PROVENANCE_OFF` when `is_unsafe`), because `mmap_or_trap` and `arena_init_result` return `@ptr_from_int`; once Z-0012 deletes the old rules, nothing would check those bodies.
    - **Do:** decide and write into design note §3 what a raw operation's result carries: a `@syscall` result does not carry its arguments' origins; the `Unknown` that `@ptr_from_int` makes is exempt from the return and store rules (a raw pointer the programmer vouched for), while every other origin in the same body is checked. Replace the body-wide `unsafe fn` exemption with that narrow one. Probe: a `gap_47`-shaped `unsafe fn` (exit 77 under `--provenance` with today's exemption) must be refused; `mmap_or_trap`, `arena_init_result`, `arena_init` and `open` must compile.
    - **Verification:** the three warnings gone, the probe refused, `make test`, `make preflight-changed` (default 0/0). Stop for review.
    - **Narrowed (2026-11-05, from Z-0061):** item (3), `stdlib/hashmap.zrl:184`, is not a raw-operation origin: its `Unknown` is `os_walk` losing the type at an `Index` on a raw pointer followed by a field. It moved to Z-0068; this task keeps (1), (2) and (4).

- [ ] +safety +tests +AI-D Z-0068 B1.7b An index into a `Vec` or a raw pointer followed by a field read keeps its type in the origin walk
    > **Created:** 2026-11-05 **Found by:** Z-0061 (the two class 1 sites it did not fix). **Check-in:** stop for review after it. Over-rejection under `--provenance` only.

    - **Now:** `os_walk` (`src/check_zir.zrl`) gives a `Projection.Index` on a type that is neither an array nor a slice type 0. As the last projection that loses nothing, but a projection after it takes the lost-type branch and adds `Unknown` to the memory read. Reproducers under `--provenance=warn --emit-origins`: with `struct Md { types: Vec<D> }`, `struct D { id: u32, def: T }` and `fn g(self: &mut Mo, i: usize) -> T` (`Mo { module: &mut Md }`), `return self.module.types[i];` gives `return O={ParamContents(0)}` and `return self.module.types[i].def;` gives `ParamContents(0), Unknown`; with `struct H { e: *mut S }`, `&self.e[i]` is clean and `&self.e[i].v` gives `Unknown` and a return-rule warning. Tree sites: `Monomorphizer.instance_type_args` (`src/mono.zrl:1057`) and `stdlib/hashmap.zrl:184` (`Option.Some(&self.entries[idx].value)`).
    - **Do:** find what type and memory codegen gives an `Index` on a `Vec` place and on a raw pointer, and make `os_walk` do the same: the element type, reached through the buffer pointer (for a `Vec`, the storage the collection owns; for a raw pointer, what it points at, as `steps_in` does for a slice). Unknown types must still add `Unknown`. Golden tests for both reproducers, a must-reject sibling (an index then field read of a local `Vec<S>` whose field holds a frame view, returned), and a mutant.
    - **Verification:** the two warnings gone, `sh scripts/test_origins.sh`, the provenance group, `make test`, `make preflight-changed` (default 0/0). Stop for review.

- [ ] +safety +tests +measurement +AI-D Z-0064 B1.8 Re-measure `--provenance` after the precision fixes, and read every remaining warning
    > **Created:** 2026-11-05 **Depends:** Z-0060, Z-0061, Z-0062, Z-0063. **Blocks:** Z-0065. Measurement only: change no code.
    > **Depends also (2026-11-05):** Z-0068.

    - **Do:** repeat Z-0049's measurement (`--provenance=warn` over `src/main.zrl`, `tools/{zilc,zbuild,zman}/src/main.zrl`, `corpus/zrl/*.zrl`) and add what Z-0049 missed: the six `stdlib/` modules no root imports (`bufio`, `ffi`, `local_mem`, `softfp`, `time`, `unicode`, with `-c`), and every test program under `tests/` that compiles by default (the best stand-in for user code). **Read every remaining warning** and classify it as a real escape, a leak or an over-rejection with a reproducer; a real escape gets a `known_gap` probe and stops this task.
    - **Store grid under the flag** (`ZORIL_CC` wrapper `exec build/zoril --provenance "$@"`, as Z-0048 ran it, with copies of the record files): unsafe cells still accepted and twins refused, by axis. This answers Decision 3 (how many over-rejections come from `fn`-value and closure routes, and whether downward-only closures are warranted), and tells Z-0065 what the default flip refuses that users write.
    - **Gate gap found in Z-0060:** `make preflight-changed` skips the rejection differential when only `stdlib/` changed (its trigger list names `src/` files only), although a stdlib function's summary changes what the checkers refuse. Run `scripts/check_reject_diff.sh` by hand for Z-0060 to Z-0063's stdlib changes, and file a task to add `stdlib/` to the trigger list.
    - **Decides:** whether the tree, `tests/` and the grid's twins are clean enough for Z-0065. An over-rejection class common in `tests/` or the twins gets a task of its own before Z-0065.

- [ ] +safety +tests +AI-D Z-0011 B3 Declarations are checked against the body: `#[borrows(..)]`, `#[stores(..)]`, the `&self` default
    > **Created:** 2026-11-03 **Depends:** Z-0049. **Check-in:** stop for review after it.
    > **Depends also (2026-11-05):** Z-0064 (its re-measurement comes first).

    - **Rule (Decision 1):** a declaration may list more than the body proves (a wider public contract), never less. For a function with a body the effective ties and stores are the union of what the body proves and any declaration (Z-0010 already sums them); a declaration that claims less than the body is a compile error, the narrowing rule of `CHANGELOG.md`'s pre-1.0 note. The `&self` elision default and the declarations apply as written to bodyless items (`extern`, trait signatures, `.zri` imports). Each of the tree's 82 `#[borrows()]` declarations (such as `Lexer.text_from`) is either proved unnecessary by Z-0010's `ParamAddr`/`ParamContents` summary and removed, or converted into an explicit, reviewed `unsafe` interior with a `// SAFETY:` comment, listed with its decision in the commit. **Stop and report** before changing a `pub` stdlib signature.
    - **Test expectation note:** `tests/error_reporting/err_stores_attribute_false.zrl` currently expects a wider `#[stores]` contract than the body performs to fail; under the wider-contract rule that test changes (stop and document the test change per `AGENTS.md`).
    - **Probes:** an unannotated `&self` method passing a parameter's borrow through, the same through a trait, and safe-code `#[borrows()]` laundering (`gap_30_borrows_attribute_launder` stays rejected; `gap_44_borrows_attr_reset` is rejected once checked declarations refuse the narrowing `#[borrows()]` (it is accepted, exit 77, under `--provenance` at `0fcd8cd`: a reset hole, not an escape, so the store rules do not see it)); accepted: a `&self` method returning a view of `self` and a wider `#[borrows]`/`#[stores]` public contract. `make test`, `make preflight-changed`. Stop for review.
    - **Blind spot not covered by this check (from Z-0049's review, 2026-11-05):** a body that copies through a bare `extern` proves no store, so a declaration can never be "narrower than the body" there (Z-0060's `extend_from_slice` route). Add a rule here or in a task of its own: a safe function that passes a pointer derived from a parameter to an `extern` with no declared effect must declare its own `#[stores]`/`#[borrows]` (or the `extern` declares its effect). Probe it with Z-0060's reproducer with Z-0060's fix taken out.

- [ ] +safety +tests +AI-D Z-0044 B0.1 A value stored into a local's field through a pointer to the local keeps its borrow
    > **Created:** 2026-11-03 **Check-in:** stop for review after it. **Closes:** `gap_37_local_mutref_field_reset`, `gap_38_param_field_reset`, `gap_39_method_self_field_reset`, `gap_43_box_field_reset`.
    > **Depends:** Z-0010, Z-0011.

    - **Scope (narrowed to intra-frame liveness, 2026-11-03):** the frame-escape siblings (`gap_40`–`gap_42` and `gap_45`) are handled by Z-0048/Z-0012's origin sets. This task fixes intra-frame `Arena::reset` / `free` / `@drop` liveness (`ActiveBorrow` in `src/check_zir.zrl`), where a slice written into a local struct's field or a `Box`'s contents through a local `&mut`, through a callee's `&mut` parameter, through `self` in a `&mut self` method, or through `*b` on a `Box` is skipped today (`place_writes_through_pointer`), letting `a.reset()` pass while the field is read afterwards.
    - **Do:** carry the stored value's borrows to the local (or `Box` local) the pointer refers to: for a local `&mut` or `Box` deref, through the pointer's borrow/ownership of that local; for a callee, through Z-0010's pairwise `i -> j` store summary (`#[stores(..)]` checked in Z-0011). Probe the sibling routes: a `&mut` held in a struct field, a reborrow, a closure capturing `&mut w` across `a.reset()`, and a trait method; also verify `gap_44_borrows_attr_reset` is rejected once checked `#[borrows()]` is active.
    - **Found by Z-0047 (pre-existing over-rejection):** `fn f(view: [i32]) -> i32 { let mut w = ...; let r = &mut w; r.s = view; ... }` called with stack `f(&data)` is refused today by `src/summary_pass.zrl`; confirm Z-0012's retirement of `summary_pass.zrl` removes that refusal without reopening any reset hole.
    - **Probes:** `gap_37`, `gap_38`, `gap_39` and `gap_43` flip to `compile_reject`, with an accepted twin for each (the field is read before `a.reset()`). Check the over-rejection recorded on Z-0017 does not grow.
    - **Verification:** `make test`, `make preflight-changed`, the rejection differential; `bench/fuzz/README.md` stays stale for `src/`. Stop for review.

- [ ] +diagnostics +AI-G Z-0066 B3.9 Provenance diagnostics name the origin they found, once per site
    > **Created:** 2026-11-05 **Found by:** Z-0049's review (correction 8). **Before:** Z-0065, which makes these messages users' errors.

    - **Now:** the return rule says "the returned value holds an address of this frame" when the returned origins are only `Unknown` (`fn mk3(n: u64) -> Box<H> { let p = @ptr_from_int<*u8>(n); return box H { p: p, n: n }; }` under `--provenance=warn`), and the call store rule often prints the same error twice at one location (`fn add(v: &mut Vec<Vec<i32>>) { v.push(Vec::<i32>.new()); }` under `--provenance`).
    - **Do:** word each rule's message by the origin that triggered it (`Frame`: an address of this frame; `Unknown`: an address the compiler cannot trace), and print one diagnostic per site and rule. Update the `EXPECT:` lines of the provenance tests that change, and say so in the commit message.
    - **Verification:** a test per wording and one for the duplicate; `make test`, `make preflight-changed`.

- [ ] +safety +tests +AI-D Z-0065 B4a The new rules on by default, beside the old ones
    > **Created:** 2026-11-05 **Split from:** Z-0012. **Depends:** Z-0064, Z-0011, Z-0044, Z-0066. **Check-in:** stop for review after it.
    > **Ordering note:** this task only refuses more, and depends in substance only on Z-0064 (the tree must be clean); the maintainer may move it ahead of Z-0011 and Z-0044 to close the escape holes for users sooner.

    - **Do:** make the rules of `--provenance` run by default **in addition to** the old rules (nothing is deleted here; the old rules still run). Keep `--provenance=warn` as a developer option or retire it; decide and record. Resolve whatever the default build of `src/`, `stdlib/`, `tools/` and `tests/` now refuses, per Z-0064's classification (a real escape: fix the code; an over-rejection: it should already have its own task done).
    - **Probes:** every `known_gap` probe the new rules refuse flips to `compile_reject` (at Z-0059: all escape gaps except the liveness ones `gap_37`, `gap_38`, `gap_39`, `gap_43`, `gap_44`; since Z-0060 also `gap_56`, since Z-0061 `gap_57` and `gap_58`; re-check each), with its Known gaps entry in `doc/spec/safety_model.md` and line in `doc/SAFETY.md` §6 removed. Accept probes newly refused: none allowed without a task.
    - **Store grid:** re-record `bench/fuzz/store_grid_expected_failures.txt` and `store_grid_twin_rejections.txt` (and the modular pair) under the new default; list in the completion note every twin newly refused, by axis.
    - **Verification:** `make test`, `make preflight-changed` (the differential must show 0 newly accepted; list the newly refused programs), `sh scripts/check_store_grid.sh`, the self-hosting fixpoint. The fuzz record goes stale for `src/`. Stop for review.

- [ ] +safety +tests +AI-D Z-0012 B4 Make `--provenance` the default, delete the old classifiers, and fix what the measurement found
    > **Created:** 2026-11-03 **Depends:** Z-0011, Z-0044. **Check-in:** stop for review after it. **Split here** if the tree needs more than a session of changes.
    > **Split (2026-11-05, from Z-0049's review):** turning the rules on by default beside the old ones is Z-0065 (it only refuses more); this task is now the half that accepts more: delete the old rules and `src/summary_pass.zrl`, with the rejection differential, and the docs and twin lists. The fixes of the measurement are Z-0060 to Z-0063, and the `unsafe fn` exemption item below moved to Z-0063. **Depends also:** Z-0065, Z-0063.

    - **Do:** make the new rules the default and remove `--provenance`; resolve every warn-mode rejection recorded in Z-0049 and Z-0011 (a real escape: fix the code; a common over-rejection: apply the decided fix; a leak through a by-value collection parameter: change the code); then delete `local_storage_external`, `local_is_external_target`, `rvalue_is_external_target`, `place_outlives_frame`, `rvalue_storage_external`, `storage_walk_zir`'s mask logic, `note_call_stores_zir`, the depth limits, `is_collection_type_name`, the same-parameter filters, and `src/summary_pass.zrl` (keeping `src/verify.zrl`'s stack-address check as an add-only second net).
    - **Flip probes and twin lists (including Z-0045's):** flip all closed `known_gap` probes (`gap_07`, `gap_11`, `gap_13`, `gap_16`, `gap_18`, `gap_21`, `gap_23`, `gap_26`, `gap_27`, `gap_28`, `gap_29`, `gap_32`, `gap_33`, `gap_36`, `gap_40`, `gap_41`, `gap_42`, `gap_44`, `gap_45`, `gap_47`, `gap_48`, `gap_49`, `gap_50`, `gap_51`, `gap_52`, `gap_53`, `gap_54`, `gap_55`) to `compile_reject` and remove their Known gaps entries in `doc/spec/safety_model.md` and `doc/SAFETY.md` §6. Fold in Z-0045: remove the 3402 `ref_{let,identity,phi}` twins (and any Z-0017 twins newly accepted when `summary_pass.zrl` is retired) from `bench/fuzz/store_grid_twin_rejections.txt`, flip `read_through_{ref,identity,phi}.zrl` from `expected compile fail` to running tests, add an `accept` probe for `Z-0045` and a regression test returning `s.as_slice()` from `String.with_capacity(a, cap)` (`a: &Arena`). Because retiring `summary_pass.zrl` and `local_storage_external` accepts more safe programs, run `scripts/check_reject_diff.sh <base>` and list every newly accepted program class in the completion note (none may be unsafe). Update `doc/SAFETY.md` §2.3 and §5–§6, `doc/spec/surface_syntax.md` (`#[borrows]`/`#[stores]`), `README.md`, `KNOWN_ISSUES.md` and `bench/fuzz/store_grid_expected_failures.txt`.
    - **Done when:** every unsafe store-grid cell (whole-program and modular) is rejected, no `known_gap` probe of this family remains, the self-hosting fixpoint holds, and `make test` and `make preflight` pass. Stop for review, then close Z-0045 (citing this commit on `main`) and start Z-0017 and Z-0013 (and renew the fuzz record per Z-0003).
    - **From Z-0048's review (Finding 2):** Z-0048 does not apply the new rules to an `unsafe fn` body (`src/driver/module.zrl`, `rules = PROVENANCE_OFF` when `is_unsafe`), while the old rules do check those bodies. Before the old rules are deleted, replace the body-wide exemption with a narrow one: only the `Unknown` that a raw operation makes (`@ptr_from_int`, as in `mmap_or_trap` and `arena_init_result`) is exempt, and every other store and return in an `unsafe fn` is checked. Probe: a `gap_47`-shaped `unsafe fn` (exit 77 under `--provenance` with the exemption) must be refused.

- [ ] +audit +safety +AI-G Z-0045 A reference to a local carrier passed through a `let`, an identity call or a phi is refused
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

- [ ] +audit +AI-D Z-0017 A3.5 Twelve safe store-grid twins are rejected
    > **Created:** 2026-11-03 **Depends:** Z-0012 (do not debug `src/summary_pass.zrl` before Z-0012 deletes it). Over-rejection audit, not a hole.

    - **Cells (before Z-0012):** `{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{closure,param_65}__call_struct_mut__frame_ends` (12 cells) plus 96 cells exposed by Z-0008 in `bench/fuzz/store_grid_twin_rejections.txt`, rejected today by `src/summary_pass.zrl` ("region escape: storing local stack pointer into caller memory"). Also note the sibling found in Z-0047's review: passing a local struct `RefHolder { r: &c }` by value to `take_holder(h)` retains `Frame(c)` (`os_reach_all`).
    - **Over-rejection from Z-0007 (found in its review, 2026-11-03):** liveness borrows are tracked per local, not per field, so `w.s = v.as_slice(); let x = w.s[0]; a.reset(); return x - 42 + w.t - 3;` is refused at `a.reset()` because `w` stays live for `w.t`.
    - **Do (after Z-0012):** inspect every twin still listed in `bench/fuzz/store_grid_twin_rejections.txt` once `summary_pass.zrl` is gone (`param_65` twins should be accepted via the overflow bit; `closure`/`fn`-value twins remain `Unknown` by design unless Decision 3 changes). Fix any unintended over-rejection without reopening any probe, add an `accept` probe for any fixed class, and document any deliberate precision bound (such as field-insensitive borrows or `Unknown` `fn`-value calls) in `KNOWN_ISSUES.md` §5. `make test`, `make preflight-changed`, the rejection differential.

- [ ] +safety +research +AI-D Z-0013 Review rounds: rotate reviewers over the compiler until the findings dwindle
    > **Created:** 2026-11-03 **Standing task;** a round reads and probes only, so it can run beside anything except a change to the area it reviews.

    - **A round:** one reviewer (a model or a prompt not used in the last round) takes one area - the type matcher and conversion sites, the borrow checker and its summaries, drop and move semantics, the stdlib's `unsafe` interiors against what safe code can reach, the FFI boundary, the runtime and `zilc` - probes what it suspects against `build/zoril`, and records each lead here as confirmed, refuted or unprobed, with its reproducer.
    - **Checklist:** every site that puts a value into an expected type (`let`, call argument, return, struct field, enum constructor, array literal and repeat, closure capture, method receiver, `match` arm, pattern binding); every type-matching and conversion function at depth above zero; every cast and what it lets safe code build; every place a size or length is narrowed; every check skipped for a special case (unit, `never`, zero length, constant operand); borrows of `static mut` held across a call or an assignment; the FFI boundary; the stdlib's `unsafe` blocks.
    - **Each confirmed hole** becomes a `known_gap` probe, a route class in `doc/spec/safety_model.md`, and a generator feature in `scripts/fuzz/gen.lua`; it is fixed by another session and fix-reviewed by a third before the next round. A fix states the rule it enforces in one sentence and defaults to the strict side for anything it cannot classify.
    - **Stopping rule:** rounds continue while a round with a fresh reviewer confirms a new hole; stop after two consecutive rounds from different reviewers confirm none.
    - **Generator debt (2026-11-05):** route classes added in the hardening series without a `scripts/fuzz/gen.lua` feature (Z-0055 noted one for `gap_47`/`gap_48`); before the fuzz renewal after Z-0012 (Z-0003), list each `known_gap` route class added since the last record and whether the generator covers it, and add the missing features. At least: closures capturing a reference to a struct holding `&mut` (`gap_47`, `gap_48`), a closure passed to a callee that calls it (`gap_52`), a cycle storing through a local (`gap_54`), a closure parameter forwarding a view (`gap_55`), and an element copy through an `extern` (Z-0060).

- [ ] +tools +AI-G Z-0014 `zilc` refuses text it does not recognise between declarations, and a file that is not ZIL
    > **Created:** 2026-11-03

    - **Now:** `zilc` exits 0 with no message on random bytes, and on `printf '\x01\x02 zz garbage\n'` it writes a stray global parsed out of the word `garbage`. `ZilParser.parse_module` (`tools/zilc/src/zil_parse.zrl`) dispatches on a declaration's first byte and skips any other byte, so text between declarations is dropped silently.
    - **Do:** at top level, after trivia, accept only the declaration forms of `doc/spec/intermediate_language.md` and report anything else as `zilc: line N: expected a declaration, found '<token>'` with exit 1; before parsing, refuse a NUL byte or invalid UTF-8 with one line. Keep the first-error behaviour.
    - **Tests:** a `tests/zilc/` case per refusal (a stray word between two functions, control bytes, a NUL byte), each failing before the change; take the check out and watch the stray-word case pass silently again. Remove or update the `KNOWN_ISSUES.md` entry. `make test`, `make preflight-changed`; the fuzz record goes stale for `tools/zilc/`.

- [ ] +diagnostics +AI-G Z-0015 `zoril` stops after a bounded number of errors, and says when a file does not look like Zoril source
    > **Created:** 2026-11-03

    - **Now:** 300 KB of random bytes named `junk.zrl` gives about 139,000 error lines (12 MB); 160 KB of prose about 33,000. `zbuild` passes the same output through. Reproduce: `head -c 300000 /dev/urandom > junk.zrl; ./build/zoril -I stdlib=stdlib --emit-zil -o o.zil junk.zrl 2>&1 | wc -l`.
    - **Do:** count errors in `diag_start` (`src/diag.zrl`); past the limit (default 20) print one line naming `--error-limit N` (0 removes the limit) and exit 1. `zbuild --error-limit N` passes it to every `zoril -c`; both man pages and `--help` say so. Before lexing, refuse a NUL byte or invalid UTF-8 with one line; if the limit is reached before the first declaration, the stopping line says the file does not look like Zoril source. `src/diag.zrl` is in stage1's closure: use only what stage1 accepts (a `static mut` counter).
    - **Tests:** a NUL byte, invalid UTF-8, prose, and a program with 25 type errors (20 printed, then the stopping line; `--error-limit 0` prints all 25); the same through `zbuild` (`scripts/test_zbuild_errors.sh`). Check first that no existing error test expects more than 20 errors. Remove or update the `KNOWN_ISSUES.md` entry. `make test`, `make preflight-changed`.

- [ ] +tools +AI-G Z-0016 `zbuild` builds a program written in ZIL, and refuses any other input with one line
    > **Created:** 2026-11-03

    - **Now:** `zbuild 01_arithmetic.zil` (from `corpus/zil/`) parses the ZIL as Zoril and prints about thirty `expected declaration` errors; the manual pipeline (`zilc`, `qbe`, `as`, `ld` with the runtime) works and exits 30.
    - **Do:** a root ending in `.zil` skips the module graph and the front end and runs `zilc`, `qbe`, `as` and the link with `zbuild`'s usual linker and runtime choice, honouring `-o` and the cache directory; `--checked` with a `.zil` root is refused with one line. A root ending in neither `.zrl` nor `.zil` is refused with one line naming both. Update `doc/man/zbuild.1.scd` (`make man`), `zbuild --help`, and "Starting from ZIL" in `doc/getting_started.md`.
    - **Tests:** with the installed `zbuild` (`scripts/test_user_paths.sh`), `corpus/zil/01_arithmetic.zil` exits 30 and every `corpus/zil/` file gives its expected exit code; the refusals for `foo.txt` and for `.zil` with `--checked`; `scripts/test_man_pages.sh`. Take the `.zil` branch out and watch the scenario fail. Remove or update the `KNOWN_ISSUES.md` entry. `make test`, `make preflight-changed`.

- [ ] +diagnostics +types +AI-G Z-0067 `v.push(Vec.new())` reports `unknown type 'T'` at a standard-library line under the user's file name
    > **Created:** 2026-11-05 **Found by:** Z-0049's review (correction 9). Default mode; not a safety issue.

    - **Now:** `import "vec.zrl"; use vec::Vec; fn main() -> i32 { let mut v: Vec<Vec<i32>> = Vec.new(); v.push(Vec.new()); return v.len() as i32 - 1; }` fails with `<file>.zrl:23:13: error: unknown type 'T'`: line 23 is `stdlib/vec.zrl`'s `impl<T> Vec<T>`, printed with the user's file name. `v.push(Vec::<i32>.new())` compiles, as does `let mut w: Vec<String> = Vec.new(); w.push(String.new());`.
    - **Two defects:** (1) the element type of a generic constructor in argument position is not inferred from the parameter's type (`T` of `push` is known from `v`); (2) a diagnostic raised inside an instantiated generic carries the instance's line with the caller's file. Fix (2) in any case; fix (1) if inference from the expected argument type is in the spec (`doc/spec/`), or else make the message say that the type argument must be written, and fix the spec if it is silent.
    - **Tests:** the program above (exit 0 after (1), or the improved message), and a test that an error inside an instance names the right file and line. `make test`, `make preflight-changed`.

- [ ] +bench +measurement +AI-G Z-0004 Measure how far the benchmark gate's measures move between cloud sessions
    > **Created:** 2026-11-03
    > **Session rule:** a new session records one sample only if asked to, so this task never starts a session.

    - **Why:** `bench/cross_lang/thresholds.cfg` is not in the tree, so `scripts/bench_threshold_check.sh` records a baseline on its first run on a host. Every cloud session starts on a fresh VM, so there the gate compares a run with itself and cannot fail. Of its three measures, `runtime_ratio_vs_gcc_o2` is relative to gcc on the same host; `clean_throughput_loc_s` and `incremental_rebuild_ms` are absolute and depend on the VM.
    - **Do:** in three to five separate cloud sessions, run `sh scripts/bench_cross_lang.sh --check-thresholds` on the same commit and record each measure, the CPU model (`/proc/cpuinfo`) and the load. Report the spread of each measure against the gate's 15% tolerance. Delete the files the run writes under `bench/`; commit nothing but this task's text.
    - **Sample 1 (2026-11-03, commit `fdb0c55`):** `Intel(R) Xeon(R) Processor @ 2.30GHz`, 4 vCPUs, 1-minute load average 2.46 at the start (a `make test` had just finished, so the host was not quiet). `clean_throughput_loc_s` 10177 (the run's own spread 288..297 ms, +3.1%), `incremental_rebuild_ms` 22, `runtime_ratio_vs_gcc_o2` 4.182, `peak_rss_mb_per_kloc` 2.973; the run took 42 s. Earlier on this same VM, an unrelated preflight recorded `clean_throughput_loc_s` 10072, 1.0% below this sample. That is one VM twice, not a spread between sessions.
    - **Sample 2 (2026-11-03, commit `fdb0c55`):** the same conversation, but on a freshly booted VM (booted 14:49 UTC, after the setup script changed), so not the VM of sample 1. `Intel(R) Xeon(R) Processor @ 2.30GHz`, 4 vCPUs, 1-minute load average 0.36 at the start. Run in a scratch worktree of `fdb0c55` whose `build/zoril` was built from that commit's compiler source and which rebuilt its own `zilc` and `zbuild`. `clean_throughput_loc_s` 9705 (the run's own spread 302..330 ms, +9.3%), `incremental_rebuild_ms` 20, `runtime_ratio_vs_gcc_o2` 4.095, `peak_rss_mb_per_kloc` 2.973; the run took 56 s. Against sample 1: clean -4.6%, incremental -9.1%, ratio -2.1%, RSS unchanged, all inside 15%. The bench outputs were deleted with the worktree.
    - **Still to do:** one to three more samples, each from a new cloud session on this commit. This task stays open until they exist; two samples are not a spread.

- [ ] +bench +decision +AI-G Z-0005 Decide the benchmark gate's behaviour on a host without a committed baseline
    > **Created:** 2026-11-03 **Depends:** Z-0004.

    - **Options, from the measurement:** commit a baseline for the measures whose spread stays inside the tolerance; make the gate print a `[SKIP]` naming the reason for those that do not; and when no committed baseline exists, have the gate say so instead of recording one and passing.
    - **Recommendation (2026-11-03, until Z-0004's spread data decides it):**
        1. A host with no committed baseline gets a statement, not a pass. The gate stops recording a baseline on a first run and then printing "All performance thresholds within tolerance"; it prints `[SKIP] bench-thresholds: no committed baseline for <axis> (<reason>)` per axis and exits 0. Recording stays an explicit act (`sh scripts/bench_cross_lang.sh --record`).
        2. Commit a baseline for `runtime_ratio_vs_gcc_o2` only (4.182 in Z-0004's sample 1): it is relative to gcc -O2 on the same host, so it moves with the compiler and not with the VM. It is committed once Z-0004's samples keep its spread inside the 15% tolerance; otherwise it gets the `[SKIP]` too.
        3. `clean_throughput_loc_s` and `incremental_rebuild_ms` stay host-local. A host that has recorded its own baseline (a developer's machine) still compares against it; anywhere else they print `[SKIP]` naming "absolute measure, no baseline for this host".
    - **Why:** on a fresh VM the present gate compares a run with itself, so it cannot fail, and it says "within tolerance" anyway. A committed absolute baseline would pass or fail with the VM's speed, which tests the VM. Z-0004's single sample says nothing yet about other VMs; rule 2 is the part its data can overturn.
    - **Not done here:** the change to `scripts/bench_threshold_check.sh` and its tests. It needs a task of its own once Z-0004 has its samples.
    - **Reopened (2026-11-03):** the decision depends on Z-0004's measurements, so the task stays open until they exist; the recommendation above is not a decision yet.
