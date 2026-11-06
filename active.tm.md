---
project: zoril
status: Active
sprint: 2026-S1
date: 2026-11-03
---

# Current Sprint

Open work, in execution order from top to bottom, in four groups. (1) The provenance and liveness hardening series (its finished tasks, Z-0060 to Z-0064 and the precision fixes after them, are in `completed.tm.md`): Z-0075 (the checkpoint on Z-0064's re-measurement: continue the precision work or stop), then the roots of the over-rejections Z-0064 read, done as Z-0075 routes them, the rules that add knowledge first and those that remove origins last: Z-0088 (Decision 3: calls through closures and `fn` values, the largest class), Z-0085 (a value copied out of a referenced collection), Z-0087 (an integer popped from a collection), Z-0084 (arena storage named by an argument's address: all of zbuild's) and Z-0086 (a literal held by a value, after Z-0084); then Z-0073 (a raw-pointer decision), Z-0011 (checked `#[borrows]`/`#[stores]`/`&self`, narrowing forbidden), Z-0044 (intra-frame `Arena::reset` liveness through pointers), Z-0066 (provenance diagnostics, before users see them), Z-0065 (the new rules on by default beside the old ones: refuses only more), Z-0074 (every program the old rules refuse and the new ones accept, read before they are deleted) and Z-0012 (old classifiers and `summary_pass.zrl` retired: accepts more, with the differential). (2) Post-series twin audits and standing review rounds: Z-0045, Z-0017, Z-0013. (3) Tooling and diagnostics: Z-0014, Z-0015, Z-0016, Z-0067, Z-0079, Z-0080. (4) Z-0004 and Z-0005, the benchmark measurement and decision, last because a session never starts one unprompted. Each `+safety` implementation task in the hardening series is a check-in: stop for review after it. Model tags: `+AI-D` marks tasks needing a deep-thinking model and `+AI-G` tasks suited to a general-purpose model; every `+safety` check-in review uses `+AI-D`. Finished tasks stay at the top until `tm sweep` rotates them. Deferred work is in `future.tm.md`. Every `+safety` task follows the safety rules in `AGENTS.md`: the rejection differential for a change that accepts more, and nothing beyond what the task names in the same commit. **Series rule (2026-11-05, from Z-0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

- [ ] +safety +decision +AI-D Z-0075 B1.8a Checkpoint: is per-site precision still the route to the default flip?
    > **Created:** 2026-11-05 **Found by:** the review of Z-0071. **Depends:** Z-0064. **Blocks:** Z-0065. Decision only: change no code. **Check-in:** stop and report to the maintainer; the maintainer decides.

    - **Why:** the over-rejection fixes of B1.7 moved `--provenance=warn` on `src/main.zrl` from 221 to 196 over several tasks, and every soundness hole found in the series came from a rule that removes origins from a set (Z-0062's moved-storage drop: `addr_edge_by_value_owner_refused.zrl`; Z-0071's `own` split: `leak_vec`). Adding origins over-approximates and is safe; removing them needs a proof per route, and each such rule so far has needed review to find the route it missed.
    - **Read:** Z-0064's classification by kind of fix. **Decide** between (a) continue with precision rules, each measured alone first and probed on its sibling routes (the series rule), when the remaining over-rejections are few or need rules that add knowledge; (b) stop the precision work and accept the remaining over-rejections through annotations (`#[stores(..)]` checked by Z-0011) or code changes at the sites, when most would need more removal rules; (c) re-plan the flip (Z-0065, Z-0012), when user code in `tests/` or the grid's twins would be refused at a rate the maintainer will not ship. Record the choice, the counts it rests on, and what changes in the task list.
    - **Input from Z-0064 (2026-11-06; its full text is in `completed.tm.md`):** `src/main.zrl`'s 195 warnings come from six roots, counted in the order they were removed: closures and `fn` values 169 (Z-0088), a value copied out of a referenced `Vec` 10, though it alone makes 153 of the 167 "into a global" (Z-0085), an integer popped from a `Vec` 6 (Z-0087), a literal held by the driver's lowerer 8 (Z-0086), `os_pending.push` 2 (a code change, Z-0065), `set_ice_note` 0. zbuild's 25 are all arena storage named by an argument's address (Z-0084); zilc, zman, the corpus and `stdlib/` 0. `tests/`: 11 closures and `fn` values, 3 a literal in an arena (Z-0086's class), 1 real hole refused correctly (`byval_vec_param`), 2 expected. The grid: 13284 safe twins newly refused, mostly closures and `fn` values. By kind: rules that add knowledge (Z-0088, Z-0085, Z-0087) cover most of `src`; rules that remove origins are needed only for Z-0084 and Z-0086. Route each of Z-0084 to Z-0088 here: a rule, a code change at the site, or an accepted refusal.
    - **The grid's newly refused twins, by root (2026-11-06, from Z-0064's run: `build/z64/grid/twin_rejections.txt` against `bench/fuzz/store_grid_twin_rejections.txt`):** 34320 cells, each an unsafe program and a safe twin; the new rules refuse 17216 twins (50%), the default rules 3932 (11%), so 13284 newly. **13146 of the 13284 (99%) have a closure or `fn` value somewhere in the cell** (Z-0088). Of the other 138, 120 are Z-0086's class (`string__*__same_param__*`: the tuple `(out, carried)` holds a `&mut` and a literal, and `stash_pair`'s `*p.0 = p.1` reads, field-insensitively, as a store into what the tuple reaches, `Static` included: "into a global"), and 18 are a class no task covers: `{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{same_param,store_param_65}__{deref_out,field_out}__frame_ends`, where `carrier_tup.0 = src_val` overwrites a local's field but the local keeps the field's old origin (`carried O={Param(1), Frame(seed)}`: no strong update on a field assignment), "outlives". None of the 13284 is from Z-0084's, Z-0085's or Z-0087's root. The tests agree: of the 14 over-refused test programs, 11 are Z-0088's and 3 Z-0086's.
    - **Recommendation (for the maintainer; not decided):** (a), continue the precision work, but with each root routed by where it is seen, not only by its kind:
        1. **Z-0088 (closures and `fn` values): a rule; it decides the flip.** It is 99% of the grid's new refusals, 11 of 14 tests and 169 of `src`'s 195. Without it the flip refuses 39% of the grid's safe twins and 11 tests, (c)'s rate; if Z-0088 decides "no rule", come back here for (c).
        2. **Z-0086 (a literal beside a reference): a rule.** Seen in user-shaped code (120 twins, 3 tests) as well as `src` (8); it removes origins, so the series rule applies.
        3. **Z-0087 (an integer popped from a collection): a rule.** Seen only in `src` (6), but it adds a type fact (an integer holds no address; the exemption exists for primitive results already) and is the cheapest to state.
        4. **Z-0085 (a value copied out of a referenced collection): a code change at the site** (`src/lower_zir/exhaust.zrl:275`, a fresh copy of the row, measured in Z-0064), the rule deferred to `future.tm.md` with its reproducer. Seen only in `src`, at one site, and the rule (by depth or type) is the delicate kind.
        5. **Z-0084 (arena storage named by an argument's address): a code change at zbuild's sites** (`tools/zbuild/src/manifest.zrl`; whether passing `cols.as_slice()` instead of `&cols` removes the 25 is to be shown there), the rule deferred. Seen only in code using a raw arena (zbuild, the compiler), which is `unsafe` already. Z-0086's rule then has to cover the literals the lowerer writes into its `ByteVec`s without it (Z-0086 says so).
        6. **The 18 overwritten-field twins: an accepted refusal for now**, recorded in `KNOWN_ISSUES.md` §5 with Z-0017's other bounds, and a task in `future.tm.md` for a strong update on a direct assignment to a local's field (a removal rule).
        - **Why not (b):** the two classes users hit (Z-0088, Z-0086) are closures and literals beside references, which no annotation or site change in the tree removes from user code. **Why not (c) now:** the measured rate falls to about 0.4% of the grid's safe twins (138 of 34320, then 18) once Z-0088 and Z-0086 hold; (c) is the fallback if Z-0088 finds no rule.
        - **Task list if accepted:** Z-0088, Z-0086 and Z-0087 stay as rules (Z-0086 loses its "After: Z-0084"); Z-0085 and Z-0084 become code-change tasks (`+AI-G`), each with a deferred rule task in `future.tm.md`; a new `future.tm.md` task for the field strong update; Z-0065's dependencies follow.

- [ ] +safety +decision +AI-D Z-0088 B1.9a Decision 3: what the rules know about a call through a closure or a `fn` value
    > **Created:** 2026-11-06 **Found by:** Z-0064 (the largest over-rejection class; its text says the class needs a task of its own before Z-0065). **Depends:** Z-0075. **Blocks:** Z-0065, unless Z-0075 changes the route. Decision first: the implementation is a task of its own that this one names. **Check-in:** stop and report to the maintainer; the maintainer decides.

    - **Now:** a call through a `fn` value (`ZirRvalue.CallPtr`) or a closure is an unknown call (`os_unknown_call_effects` in `src/check_zir.zrl`): it may store any argument anywhere, and its result holds `Unknown`. Decision 3 (Z-0048) deferred the split of `fn` values from closures until a measurement; Z-0064 made it.
    - **Counts (Z-0064, under `--provenance`):** the store grid refuses 13284 safe twins it did not refuse by default, of which by path `fn_val` 3284 and `closure` 2822, by destination `closure_owned_capture` 3300, `closure_call_mut` 2694 and `closure_capture_mut` 1708, by carrier `call_closure` 2080 (example: `arena_vec__arena_struct_bundle__closure__call_mut__arena_reset`, an identity closure on the route). 11 of the 17 test programs that warn: `closure_mutates_owning_capture`, `closure_type_inference`, `infer_from_fn_type`, `closure_owned_capture` (origins), `trait_names`, `closure_captures_everywhere`, `flat_fn_ptr_call_result`, `closure_captures_owning_and_other`, `test_stdlib_iter`, `platform_layer/include/{app,platform}`. In `src`, `Monomorphizer::lower_fn` calls the driver through the `fn` value `self.lower_instance` (`src/mono.zrl`, `return lower(..)`); stubbing that call took 169 of the 185 warnings left once Z-0085's root was removed. The tree has 5 `fn`-value call sites (Z-0049).
    - **Decide between:** (1) a summary for a call whose possible callees are known (a `fn` item passed directly, a closure literal at the call site), joined over them; (2) downward-only closures and `fn` values (one that cannot escape stores only into what its caller passed or it captured); (3) declared effects on a `fn` type, checked where a function becomes the value; (4) no rule: change the compiler's one site, and record the grid's and the tests' refusals as a precision bound in `KNOWN_ISSUES.md` §5. For each, say what the grid and the 11 tests would accept (with a scratch compiler if cheap) and which rules it removes origins by (the series rule). Update Z-0017's note ("`closure`/`fn`-value twins remain `Unknown` by design unless Decision 3 changes") with the outcome.

- [ ] +safety +tests +AI-D Z-0085 B1.9b A value copied out of a referenced collection is not an address into its buffer
    > **Created:** 2026-11-06 **Found by:** Z-0064 (root (d2)). **Depends:** Z-0075. **Check-in:** stop for review after it.

    - **Now:** a body summary's `ParamContents(i)` tie is mapped with `os_through_plus`, everything reached through the argument at any depth, including the buffer a referenced `Vec` owns. A function returning a `Vec` of elements copied out of `&rows` reads as returning addresses into `rows`'s buffer. In `src/lower_zir/exhaust.zrl`, `exh_expand_or` pushes `row` read out of `rows` and calls itself with `&out`, which makes its caller's result own fresh storage; in `exh_useful`, `rows`, `spec`, `def` and `same` then hold `Frame` and `Unknown`, and its summary becomes every parameter stored into every parameter and a global. 167 of `src`'s 195 warnings are "into a global" because of it.
    - **Reduction:** Z-0084's program with `if again { return self.expand(&out, false); }` added in `expand` before `return out;` (`build/z64/t/d3.zrl`): builds, exits 0, 7 warnings under `--provenance=warn`, with or without Z-0084's experiment. Twin: `expand` pushes a fresh copy (`let c = self.alloc(r.len); out.push(c);`): 0 warnings.
    - **Measured alone (Z-0064, a copy of `src/` with the same fresh copy at `exhaust.zrl:275`):** 195 to 185, and "into a global" 167 to 14; `exh_useful`'s summary becomes `ParamContents(0) -> Param(0) ParamContents(0)`.
    - **Decide first, then do:** a rule that adds knowledge (a tie by depth, or by type: a `[mut u32]` element cannot address a buffer of `[mut u32]` headers without `unsafe`), or the one-line code change at the site (Z-0075 says which route). A rule removes origins in effect, so the series rule and the rejection differential apply; probe a result that does point into the buffer (`fn first(v: &Vec<i32>) -> &i32 { return &v.as_slice()[0]; }`, then the `Vec` dropped or pushed to), which must keep it. `make test`, `make preflight-changed`, the store grid.

- [ ] +safety +tests +AI-D Z-0087 B1.9c An integer popped from a collection carries no address
    > **Created:** 2026-11-06 **Found by:** Z-0064 (root (f)). **Depends:** Z-0075. **Check-in:** stop for review after it.

    - **Now:** `os_call` drops a body summary's `ParamContents` ties for a primitive result only, so `Vec<usize>.pop()` (`Option<usize>`) is tied to the `Vec`'s storage; the integer then carries `Frame(widths)` into whatever it is written into. In `src/fmt/doc.zrl` (`Doc::measure`) this gives all six `fmt/` warnings (`doc.zrl:111`, `:151`, `fmt.zrl:76`, `:122`, `:131`, the cascade through `render`, `file` and `format_source`).
    - **Reduction** (`build/z64/t/f1.zrl`; builds, exits 0, accepted by default; two warnings at the `set` under `--provenance=warn`, Z-0066's duplicate; twin `let w = widths.as_slice()[0];` gives none):

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

    - **Measured alone (Z-0064, a copy of `src/` on top of the earlier experiments, both pops in `Doc::measure` replaced by an index read and a discarded pop):** 14 to 8, every `fmt/` warning gone.
    - **Do:** extend the exemption to a result type that holds no pointer at any depth (an `Option<usize>`, a struct of integers; `os_carries` is the place to check), and probe that a type holding a pointer anywhere (an `Option<&i32>`, a struct with a `[u8]` field) keeps its tie. It removes ties, so the rejection differential applies. Relates to the `Vec.pop` class Z-0064 recorded (a non-integer value popped and moved into a returned `Vec`, `git show ad9045c:tests/language/memory/origins/own_contents_edge.zrl`), which this does not cover. `make test`, `make preflight-changed`.

- [ ] +safety +tests +AI-D Z-0084 B1.9d Arena storage is named by the arena an argument reaches, not by the argument's address
    > **Created:** 2026-11-06 **Found by:** Z-0064 (root (d1)). **Depends:** Z-0075 (it decides whether over-rejections are fixed by rules). **Check-in:** stop for review after it. Accepts more: the rejection differential and the series rule apply.

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

    - **Measured alone (Z-0064, a scratch compiler: in `os_call`'s `in_ties` branch under a body summary, `vs |= arena_store` only when the argument's type is a pointer straight to an `Arena` or `ArenaHeader`, else `vs |= tr`, what the argument reaches):** zbuild 25 to 0; `src` unchanged alone (Z-0085's root keeps its cascade going). A measurement, not a proposed rule: not probed for soundness.
    - **Do:** state the rule (an arena's storage is what the reference reaches, at the depth where the `Arena`/`ArenaHeader` is) in the design note §3, implement it, and probe the sibling routes per the series rule: the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer, an `&Arena` held in a struct field, an `Arena` held by value in a struct passed by reference, and `arena_reset` between the call and a read. `make test`, `make preflight-changed`, the rejection differential, the store grid.

- [ ] +safety +tests +AI-D Z-0086 B1.9e A literal held by a value does not make what the value reaches a global destination
    > **Created:** 2026-11-06 **Found by:** Z-0064 (root (e)). **Depends:** Z-0075. **After:** Z-0084 (part of the literals' route into the lowerer goes through its naming: `exh_missing` writes literals into a `ByteVec` in `self.arena`, which is named `Param(0)`). **Check-in:** stop for review after it.

    - **Now:** a local that holds `Static` (a string literal in one of its fields, or written into memory it reaches) makes every later store into what it reaches have `Static` among its targets, and the call store rule reads `Static` as a global. In the driver, `ZirLowerer::lower_function`'s summary has `store Static -> Param(0)` (a dozen lowering functions write a literal into `*self`, the first in lowering order `exh_missing`), so `Driver::run_body_passes_in_scratch`'s local `zir_low` holds `Static`; it is the first function in lowering order with a store into a global. That carries the last 8 of `src`'s warnings (`src/driver/module.zrl:666`, `:713`, `:1141`, `:1188`, `:1475`, `:1603` into a global; `:1362`, `:1386` outlives), and the class covers Z-0064's three `arena_raw` test programs (`test_stdlib_string_arena`, `accept_slice_receiver`, `test_empty_compile_and_tool_errors`).
    - **Reduction** (`build/z64/t/e3.zrl`; builds, exits 0, accepted by default; "into a global" at the call in `main` under `--provenance=warn`; twin with `name: s` gives no warning): `struct W { name: [u8], items: &mut Vec<[u8]> }`, `impl W { fn add(self: &mut W, s: [u8]) { self.items.push(s); } }`, `fn inner(out: &mut Vec<[u8]>, s: [u8]) { let mut w = W { name: "lit", items: out }; w.add(s); }`, and `main` calls `inner(&mut v, &data)` with a local array `data` and a `Vec<[u8]>` `v`, returning `v[0][1] as i32 - 2`.
    - **Not yet measured alone:** replacing `ZirLowerer.new`'s `file_path: ""` changes none of the 8 (the other sites still write literals), and Z-0084's experiment alone does not remove them either. Find each site's route first (`--emit-origins` with the target-file filter in `src/driver/module.zrl` removed, as Z-0064's debug compiler did).
    - **Do:** decide whether a `Static` origin reached through a value may be dropped from store targets (a literal is read-only, so storing through it needs `unsafe`), or whether the sites change. A rule removes origins, so the series rule applies, with probes of a `static mut` reached through a value (which must stay a global destination) and a literal beside a `&mut` in one struct. `make test`, `make preflight-changed`, the rejection differential.

- [ ] +safety +decision +AI-D Z-0073 B1.8b Decide whether storing a raw pointer into a by-value owner's buffer, then dropping the owner, is refused
    > **Created:** 2026-11-05 **Found by:** the review of Z-0071. **Before:** Z-0012. Decision first; the fix or the probe is the next step it names.

    - **The case:** `struct Buf { data: *mut u8 }` with `Drop` freeing a heap block; `fn keep(out: &mut *mut u8, b: Buf) { *out = b.data; }` and `fn f(out: &mut *mut u8) { let b = Buf.new(); keep(out, b); }` (`tests/language/memory/provenance/addr_edge_by_value_owner_refused.zrl` at `ad9045c`), and the twin storing `BothPtr { own_v: Vec::<i32>.new(), p: b.data }` (`build/z71r/c2.zrl`). Accepted by the old rules and by `--provenance` at `e09b409`; the caller's pointer is left dangling once `keep` drops `b`. Only `ad9045c` refused the first form, through the edge kinds Z-0072 removes.
    - **Question:** the stored value is a raw pointer, dereferenced only in `unsafe`. Z-0063 decided that the new rules check a raw pointer's origins (`Raw` is exempt only as a value). Does that make this a hole (a `known_gap` probe now, a fix that tells a moved owner from an address read out of it without per-store kinds), or is a dangling raw pointer outside the guarantee (record it in `doc/spec/safety_model.md` and `doc/spec/unsafe_policy.md`, with a test showing the accept)?
    - **Interim (Z-0072):** until decided, the test leaves `tests/` and the case is recorded here; Z-0072 says where it went.
    - **Removed in `6418164`:** the test's full text is in `git show ad9045c:tests/language/memory/provenance/addr_edge_by_value_owner_refused.zrl`; at `6418164` it compiles under `--provenance` and in the default mode.
    - **A sibling route (found in Z-0076, 2026-11-05):** an owner holding a raw pointer to memory outside the frame, whose safe method stores an argument through it (`put(self: &mut G, r: &i32) { unsafe { *self.p = r; } }` called with `&x`), is accepted in both modes: the destination reach does not follow a `*mut` an owner holds (`os_type_has` answers no for `RawPtrMut(x)` under `OS_Q_HANDLE`). Program in Z-0076's text (`build/z76/cx.zrl`). Decide it with this case: a raw pointer's target is the `unsafe` author's claim, or the call rule follows it.
    - **Two more sibling routes (found in Z-0076, 2026-11-06):** a frame address stored through the result of a `#[fresh]` function (`tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`) or through a heap block from `zoril_allocator_alloc(null, ..)` (`heap_block_store_through_old_rule_refused.zrl`), the pointer then returned, or the block put into a global (`heap_block_into_global_old_rule_refused.zrl`): any destination of the pointer. Since Z-0076 the new rules accept all three: the result has no origins, so a store through it reaches nothing they follow, as with a raw pointer an owner holds. The old region rule refuses all three in every mode today. Decide them with the case above: if a dangling raw pointer is outside the guarantee, say so in `doc/spec/safety_model.md`; if not, the store through a raw pointer with no origins needs a target (the fresh storage of the local holding it, say) before Z-0012 removes the old rule.

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
    > **Depends also (2026-11-06, from Z-0064):** Z-0075, and Z-0084 to Z-0088 as Z-0075 routes them (a task it routes to "accepted refusal" or "code change" is done here instead).

    - **Do:** make the rules of `--provenance` run by default **in addition to** the old rules (nothing is deleted here; the old rules still run). Keep `--provenance=warn` as a developer option or retire it; decide and record. Resolve whatever the default build of `src/`, `stdlib/`, `tools/` and `tests/` now refuses, per Z-0064's classification (a real escape: fix the code; an over-rejection: it should already have its own task done).
    - **Code changes Z-0064 left here (2026-11-06):** `Driver::lower_fn_body` pushes `OsPending { zir: zir_func }` into `self.os_pending` (`src/driver/module.zrl`, 2 warnings): `zir_func`'s slices are tied to the local `zir_low` though they live in the driver's scratch arena; change the code or route it to Z-0084's rule. `Driver::set_ice_context` stores an arena-built note into a global through `set_ice_note`'s `#[stores(note -> static)]` (`src/driver/module.zrl:864`): a true store, safe only because the arena lives as long as the program, and no warning of its own once the other roots are gone; if the default build refuses it, an explicit `unsafe` with a `// SAFETY:` comment naming that invariant, not a rule.
    - **Probes:** every `known_gap` probe the new rules refuse flips to `compile_reject` (at Z-0059: all escape gaps except the liveness ones `gap_37`, `gap_38`, `gap_39`, `gap_43`, `gap_44`; since Z-0060 also `gap_56`, since Z-0061 `gap_57` and `gap_58`, since Z-0062 `gap_59` to `gap_62`, since Z-0072 `gap_63`; re-check each), with its Known gaps entry in `doc/spec/safety_model.md` and line in `doc/SAFETY.md` §6 removed. Accept probes newly refused: none allowed without a task.
    - **Store grid:** re-record `bench/fuzz/store_grid_expected_failures.txt` and `store_grid_twin_rejections.txt` (and the modular pair) under the new default; list in the completion note every twin newly refused, by axis.
    - **Verification:** `make test`, `make preflight-changed` (the differential must show 0 newly accepted; list the newly refused programs), `sh scripts/check_store_grid.sh`, the self-hosting fixpoint. The fuzz record goes stale for `src/`. Stop for review.

- [ ] +safety +tests +AI-D Z-0074 B4b List every program the old rules refuse and the new rules accept, and read each
    > **Created:** 2026-11-05 **Found by:** the review of Z-0071. **Depends:** Z-0065. **Blocks:** Z-0012, which is the change that accepts them.

    - **Why:** `leak_vec` (Z-0071) was refused by neither differential the series runs: the rejection differential compares two compilers in the default mode, and `build/rv/provdiff.sh` compares `--provenance` before and after a change over the existing probes. A reviewer found it by hand. Z-0012 deletes the old rules, so every program only they refuse is accepted after it; that list is not computed anywhere.
    - **Do:** run the new rules alone (a scratch compiler with the old rules' refusals off, as `check_reject_diff.sh` builds its base in a scratch worktree, or a developer flag if one is cheaper; say which) and the default compiler over the rejection differential's program set (69,122 at Z-0071, `tests/`, the safety probes, the store grid twins). List every program refused by the default and accepted by the new rules alone, and read each: a real escape gets a fix or a `known_gap` probe before Z-0012; a safe program is recorded as Z-0012's intended acceptance.
    - **Make it a gate** if it is cheap enough: Z-0012's completion note then lists the same set, empty of unsafe programs.
    - **Known members (from Z-0076, 2026-11-06):** `tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`, `heap_block_store_through_old_rule_refused.zrl` and `heap_block_into_global_old_rule_refused.zrl` are refused by the old region rule only: a frame address stored through a `#[fresh]` result or a heap block, the pointer then returned or put into a global. Their expected diagnostic names the old rule, so they fail when it goes; Z-0073 decides what replaces it.

- [ ] +safety +tests +AI-D Z-0012 B4 Make `--provenance` the default, delete the old classifiers, and fix what the measurement found
    > **Created:** 2026-11-03 **Depends:** Z-0011, Z-0044. **Check-in:** stop for review after it. **Split here** if the tree needs more than a session of changes.
    > **Split (2026-11-05, from Z-0049's review):** turning the rules on by default beside the old ones is Z-0065 (it only refuses more); this task is now the half that accepts more: delete the old rules and `src/summary_pass.zrl`, with the rejection differential, and the docs and twin lists. The fixes of the measurement are Z-0060 to Z-0063, and the `unsafe fn` exemption item below moved to Z-0063. **Depends also:** Z-0065, Z-0063.
    > **Depends also (2026-11-05):** Z-0074 (the old-refuses, new-accepts list), Z-0073 (the raw-pointer decision), Z-0075 (the checkpoint).

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

- [ ] +modular +tools +AI-G Z-0079 A generic body using a type-argument builtin cannot be read back from its interface
    > **Created:** 2026-11-05 **Found by:** Z-0078. Refuses more, never less: not a safety issue.

    - **Now:** the interface printer writes `@ptr_from_int<*mut T>(n)` in a generic body as `@ptr_from_int::<*mut T>(n)`, which the parser refuses when it reads the `.zri` (`expected (, but found ::`). Whole-program builds it; zbuild does not. Reproducer: `plib.zrl` = `pub fn at<T>(n: u64) -> *mut T { return @ptr_from_int<*mut T>(n); }`, `pmain.zrl` = `import "plib.zrl"; fn main() -> i32 { let p = plib::at::<i32>(64 as u64); return (p as u64 - 64 as u64) as i32; }`; `build/zoril` accepts `pmain.zrl`, `build/zbuild -o p pmain.zrl` fails in the cache's `plib.zri`. The same for `@ptr_cast`, `@int_cast` and `@alloca` (each probed, 2026-11-05).
    - **Do:** print a builtin's type argument as written (`@name<T>(..)`), or have the parser accept `::<` after a builtin; say which and why. A `tests/modular/iface_attrs/` fixture with one generic body per builtin, built whole-program and through zbuild. `make test`, `make preflight-changed`.

- [ ] +tests +tools +AI-G Z-0080 The mutation harness's two lists exist, or its header stops claiming them
    > **Created:** 2026-11-05 **Found by:** Z-0078 (and its review).

    - **Now:** `scripts/mutation-check.sh`'s header says `scripts/mutation_uncovered.list` holds the mutations it deliberately does not run (M106, M107, M85, M112) and `scripts/mutation_incremental.list` the ids run against the incremental scenario (`-c` / `.zri`). Neither file exists: `incremental_list_path` returns a missing file, `incremental_mutation` is always false, so no mutant is ever run against the incremental scenario, and nothing records the deliberately unrun ones. `git log --all` shows neither file was ever committed. A mutant of the interface printer (Z-0078's `#[fresh]` printing) is caught only by `scripts/test_interface_attrs.sh`, a gate the harness does not run.
    - **Do:** find in git history whether the lists existed and were lost (`git log --all -- scripts/mutation_incremental.list`), then either restore them with their entries, or make the harness say plainly that it runs neither; and decide whether a mutant may name a gate (the interface gate) as its catcher. Add an interface-printer mutant (`if f.fresh {` -> `if false {` in `src/interface_print.zrl`) that the chosen route catches. `make test`, `sh scripts/test_mutation_check.sh`.

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
