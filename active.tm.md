# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

- [ ] +refactor +AI-G @main The compiler, zbuild and zman read a non-`Copy` slice element through a reference, not by value id:pex09
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Placed:** after id:cx46y, which measured these sites; before id:v0rsm, which it blocks.
    > **Check-in:** reviewed in id:48h1s.

    - **Why:** id:v0rsm refuses a by-value read of an array or slice element that is not `Copy` (the maintainer's decision, id:v0bwt). id:cx46y measured every such read in the tree: twelve, listed here. They are rewritten first, in a commit that builds under today's rule, so that the compiler that carries the new rule can build the tree. No behaviour changes.
    - **The sites and their rewrite** (measured and built in id:cx46y; the same diff is `build/cx46y/rewrites.patch` on the host that ran it, `git apply` it if it is there, otherwise make these edits by hand):
      - `src/check_zir.zrl`: in the call of `merge_states`, the argument `preds[bj],` becomes `&preds[bj],`; in `fn merge_states`, the parameter `predecessors: Vec<u32>,` becomes `predecessors: &Vec<u32>,`. The body is unchanged.
      - `tools/zman/src/render.zrl`: the five `let item = all[i];` and the one `let method = all[j];` become `let item = &all[i];` and `let method = &all[j];`; every `is_internal(&item)` becomes `is_internal(item)`, `is_internal(&method)` becomes `is_internal(method)`, and the two `put_declaration(out, &item, ..)` become `put_declaration(out, item, ..)`.
      - `tools/zbuild/src/manifest.zrl`: `pub fn find_entry(m: &Manifest, path: [u8]) -> Option<Entry>` returns `Option<&Entry>`; both `let e = m.entries.as_slice()[i];` (in `find_entry` and in the function that writes the manifest) become `let e = &m.entries.as_slice()[i];`.
      - `tools/zbuild/src/build.zrl`: `reuse_frozen`'s parameter `prev: Option<Entry>` becomes `prev: Option<&Entry>`; in it, the comment line `` // `deps` owns storage, so it moves last: a partial move marks the whole `e` moved. `` is deleted and `out.deps = e.deps;` becomes `out.deps = unsafe { e.deps.clone_in_raw(ctx.arena) };`; `source_state`'s parameter `prev: &Option<Entry>,` becomes `prev: &Option<&Entry>,`; `let dr = results.as_slice()[dep_idxs.as_slice()[i]];` becomes `let dr = &results.as_slice()[dep_idxs.as_slice()[i]];`; `let e = manifest.entries.as_slice()[i];` becomes `let e = &manifest.entries.as_slice()[i];`.
      - `tools/zbuild/src/main.zrl`, `load_manifest`: the loop that copied each entry into a second `Vec` edits the entries in place. `let mut fixed = unsafe { Vec::<Entry>.new_in_raw(arena) };` becomes `let entries = m.entries.as_mut_slice();`; `while i < m.entries.len() {` becomes `while i < entries.len {`; `let mut e = m.entries.as_slice()[i];` becomes `let object = entries[i].object;`; the condition reads `object.len > 0 && object[0] != '/' as u8`; the assignment becomes `entries[i].object = join_path(cache_dir, object, arena);`; `fixed.push(e);` and `m.entries = fixed;` are deleted.
    - **Measured in id:cx46y with exactly these edits on git:1cc65c1:** the tree builds with today's compiler and through stage1 (`rm build/zoril` in a scratch worktree, then `make`), and `make test` there gave `Total: 3409 run, 3409 passed, 0 failed, 96 skipped (122.2s)` (one test short of the tree's count: a file of the scratch tree was moved aside by mistake during that run; nothing failed).
    - **Checks:**
      - C1: `make` after the edits, no warning; quote its last line.
      - C2: `git diff --stat HEAD` names these five files and no other; quote it.
      - C3: no by-value read is left at the sites: `grep -n 'let item = all\[\|let method = all\[\|as_slice()\[i\];\|as_slice()\[dep_idxs' tools/zman/src/render.zrl tools/zbuild/src/*.zrl` prints only lines that begin the right-hand side with `&` (quote the output), and `grep -n 'preds\[bj\],' src/check_zir.zrl` prints the `&preds[bj],` line.
      - C4: `make test`, then `make preflight-changed`; quote each `Total:` line. A failure in the `zbuild` tests or scenarios: stop and report, do not change a test to fit.
      - C5: commit on `main` (the note says the fuzz record is stale for `src/` and `tools/zbuild/`), add `**Awaiting review:**` with C1 to C4, `tm done`. There is no take-out check here: the change is a refactor, and id:v0rsm's C4 is the check that fails without it.

- [ ] +safety +tests +AI-G @main A value that is not `Copy` is not read by value out of an array or slice element (gap_92, gap_93) id:v0rsm
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Placed:** after id:pex09, which it needs; written by id:cx46y from the maintainer's decision id:v0bwt.
    > **Depends:** id:pex09
    > **Depends note:** with this rule the compiler refuses the twelve sites id:pex09 rewrites, so the tree does not build without it.
    > **Check-in:** a fix to a safety rule; reviewed in id:48h1s.

    - **Probes:** `bench/safety_matrix/probes/gap_92_vec_duplicated_out_of_slice_element.zrl` (`known_gap`, a fault) and `gap_93_mut_ref_duplicated_out_of_slice_element.zrl` (`known_gap`, exit 77, git:8aff926).
    - **Decided (the maintainer, id:v0bwt):** a by-value read of a slice element that is not `Copy` is refused.
    - **Settled in id:cx46y:**
      - The rule is id:760hd's with its `type_has_drop` condition removed: any by-value read of a place with an index step whose type is not `Copy` is refused, with id:760hd's message `cannot move out of an array or slice element`. One rule and one message for a value that needs a drop and one that does not.
      - It covers a local array as well as a slice. Today `let x = a[0];` on a local array of `Vec`s moves the whole array (a second read is `use of moved value 'a'`); `doc/spec/` does not say what that read does, no program in `src/`, `stdlib/`, `tools/` or `tests/` relies on it (measured, below), and id:760hd already refuses it for a value that needs a drop. The maintainer was told of this choice when id:cx46y was reported; if the maintainer objects, stop and report instead of starting.
      - Measured on a prototype of exactly this change over git:1cc65c1 with id:pex09's rewrites: `make test` failed only on `gap_92` (`known gap closed? compile error now`, whole-program and `zbuild`) and the two line-count figures (`Total: 3413 run, 3409 passed, 4 failed, 94 skipped (122.6s)`); `REJECT_DIFF_NO_CACHE=1 sh scripts/check_reject_diff.sh HEAD` gave `reject-diff: base verdicts: fresh (no cache); base front end 110 s` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 2 newly refused, of 69158 programs against HEAD`, both `gap_92` (`gap_93` did not exist yet in that tree).
    - **Settled change, `src/check_zir.zrl`, `check_place_use` only:** delete the line `&& self.type_has_drop(self.get_place_type(place, locals), 0 as usize) {` in two places and close the condition on the line before it, so that the two blocks read:

    ```diff
    -            if why == 3 as u32
    -                && self.type_has_drop(self.get_place_type(place, locals), 0 as usize) {
    +            if why == 3 as u32 {
                     self.report_error("cannot move out of an array or slice element", span);
    ```

    - and

    ```diff
    -        if self.place_has_index(place)
    -            && self.type_has_drop(self.get_place_type(place, locals), 0 as usize) {
    +        if self.place_has_index(place) {
                 self.report_error("cannot move out of an array or slice element", span);
    ```

    - Nothing else in the checker or the lowering changes. `type_has_drop` keeps its other callers.
    - **Do, with the change:**
      - Flip both probes: `// expected: compile_reject`, `// EXPECT: cannot move out of an array or slice element`, with the `// gap:` and `// observed:` lines removed.
      - `doc/spec/safety_model.md`: remove the two Known gaps entries; "the 20 holes" becomes "the 18 holes"; in the **Use After Move (Linear/Owned)** row, before ` [side: safe;`, add `; reading a value that is not `Copy` by value out of an array or slice element (`let v = a[0];`) is rejected, since the array or slice still holds it`. Keep `bench/safety_matrix/matrix.md` in step with the row (`make md-fmt`; the `safety-model` gate compares them).
      - `doc/SAFETY.md`: remove the class (N) bullet of §6; `classes (M) and (N), which are liveness and ownership holes and need rules of their own` becomes `class (M), which is a liveness hole and needs a rule of its own`; `compile_reject` 375 to 377 and `known_gap` 48 to 46 (the count sentence of §5.1 and the sentence above the class list); the compiler line count, and `doc/spec/unsafe_policy.md`'s, as `sh scripts/check_safety_figures.sh --all` asks.
      - `doc/spec/surface_syntax.md` §7.1, a new paragraph after `Use-after-move is a compile-time error.`: `A value that is not `Copy` cannot be read by value out of an array or slice element: `let v = a[i];`, a pattern, `if let` or `?` that binds part of `a[i]` by value, and `a[i]` as an argument, a returned value, an assigned value or a field of a literal are rejected (`cannot move out of an array or slice element`; `tests/language/memory/element_move/`). The array or slice still holds the element, so the read would leave two owners of it. Read it through a reference (`&a[i]`), use it in place (`a[i].push(1)`, `a[i].n`), or `clone()` it.`
      - Tests, twenty new files in `tests/language/memory/element_move/`. They are in `build/cx46y/newtests/` on the host that ran id:cx46y (copy them if they are there). Otherwise write them: nineteen with `// expected compile fail` and `// EXPECT: cannot move out of an array or slice element`, each a `main` that builds the array and calls `g`, with `import "vec.zrl"; use vec::Vec;` where a `Vec` is used and, where named, `struct N { v: Vec<i32>, n: i32 }`, `enum V { Some(Vec<i32>), None }`, `enum O { Some(Box<i32>), None }`, `enum Result<T, E> { Ok(T), Err(E) }`:
      - `slice_vec_let.zrl`: `fn g(a: [Vec<i32>]) { let v1 = a[0]; }`
      - `mut_slice_vec_let.zrl`: `fn g(a: [mut Vec<i32>]) { let v1 = a[0]; }`
      - `array_vec_let.zrl`: in `main`, `let mut a = [v]; let v1 = a[0]; return 0;` (no later use of `a`, so that it builds before the change)
      - `slice_box_let.zrl`: `fn g(a: [Box<i32>]) -> i32 { let b = a[0]; return *b; }`, called with `[box 5]`
      - `slice_mut_ref_let.zrl`: `fn g(a: [mut &mut i32]) { let r = a[0]; *r = 2; }`, called with `&mut a` where `let mut a = [&mut n];`
      - `slice_vec_struct_let.zrl`: `fn g(a: [N]) { let x = a[0]; }`
      - `slice_vec_field_of_element.zrl`: `fn g(a: [N]) { let x = a[0].v; }`
      - `slice_vec_match_payload.zrl`: `fn g(a: [V]) { match a[0] { V.Some(x) => {}, _ => {} } }`
      - `slice_box_if_let.zrl`: `fn g(a: [O]) -> i32 { if let O.Some(b) = a[0] { return *b; } return 0; }`
      - `slice_vec_try.zrl`: `fn g(a: [Result<Vec<i32>, i32>]) -> Result<i32, i32> { let x = a[0]?; return Result.Ok(1); }`
      - `slice_vec_tuple_pattern.zrl`: `fn g(a: [(Vec<i32>, i32)]) { let (x, n) = a[0]; }`
      - `slice_vec_as_argument.zrl`: `fn sink(x: Vec<i32>) {}`, `fn g(a: [Vec<i32>]) { sink(a[0]); }`
      - `slice_vec_returned.zrl`: `fn g(a: [Vec<i32>]) -> Vec<i32> { return a[0]; }`
      - `slice_vec_in_struct_literal.zrl`: `fn g(a: [Vec<i32>]) { let s = N { v: a[0], n: 1 }; }`
      - `slice_vec_assigned.zrl`: `fn g(a: [Vec<i32>]) { let mut x = Vec::<i32>.new(); x = a[0]; }`
      - `slice_vec_element_to_element.zrl`: `fn g(a: [mut Vec<i32>]) { a[1] = a[0]; }`
      - `slice_vec_by_value_self.zrl`: `impl N { fn eat(self: N) {} }`, `fn g(a: [N]) { a[0].eat(); }`
      - `slice_vec_generic.zrl`: `fn first<T>(a: [T]) -> T { return a[0]; }`, `let x = first::<Vec<i32>>(&a);` in `main`
      - `vec_of_vec_element.zrl`: in `main`, `let mut outer = Vec::<Vec<i32>>.new(); outer.push(inner); let x = outer[0];`
      - `element_non_copy_read_without_move.zrl` (`// expected exit 0`), the reads that stay accepted, each checked for its value: `let x = &a[0]; return x.as_slice()[0];` on `[Vec<i32>]`; `a[0].push(4); return a[0].len() as i32;` on `[mut Vec<i32>]`; `let n = a[0].n;` on `[N]`; `a[0].free(); a[0] = w;` on `[mut Vec<i32>]`; `match &a[0] { V.Some(x) => { return x.len() as i32; }, V.None => { return 9; } }`; `match a[0] { V.None => { return 9; }, V.Some(_) => { return 0; } }`; `let s = a[0]; return s[0];` on `[[i32]]`; `let r = a[0]; return *r;` on `[&i32]`. If any is refused, stop and report.
      - In `doc/tasks/future.tm.md`, a **Found** bullet on id:z0021 saying that its slice shape (`let x = s[i]` with `s: &[Box<T>]`) is refused by this task's rule with the message `cannot move out of an array or slice element`, with the test `slice_box_let.zrl`; leave the task where it is.
    - **Checks:** (`R <file>` is `mkdir -p build/v0rsm && timeout -k 5s 60s build/zbuild -I stdlib=stdlib --cache-dir build/v0rsm/cache -o build/v0rsm/p.bin <file> && { build/v0rsm/p.bin; echo "exit $?"; }`: it prints the first `error:` line of a refused program, or `exit N` of one that built.)
      - C1: before the change, `R` on `gap_92` (a fault, `exit 139`), on `gap_93` (`exit 77`), on the nineteen reject tests (each `exit 0`: measured in id:cx46y) and on the accept test (`exit 0`); quote each line.
      - C2: after the change and `make` (no warning), `./scripts/test.sh tests/language/memory/element_move`; quote its `Total:` line (the forty tests of the directory pass).
      - C3: take each hunk out alone (put its `&& self.type_has_drop(..)` line back), `make`, rerun C2 and quote which tests fail (expected without the first: tests that bind a payload by value, such as `slice_vec_match_payload`, `slice_box_if_let`, `slice_vec_try`; without the second: the others; record what is seen, and a hunk whose removal fails no test is reported). Restore, `make`, rerun C2.
      - C4: the rewrites of id:pex09 are needed: in `src/check_zir.zrl` put `preds[bj],` back for `&preds[bj],` and `predecessors: Vec<u32>,` back, run `timeout -k 5s 120s build/zoril src/main.zrl -I stdlib=stdlib -I src -I build/gen -o build/v0rsm/main.zil` and quote its error line (expected: `src/check_zir.zrl:` with `cannot move out of an array or slice element`). Restore both lines and `make`.
      - C5: `sh scripts/run_safety_matrix.sh` (`Mismatches: 0`), `sh scripts/check_safety_figures.sh --all`, `sh scripts/check_safety_model.sh`; quote each verdict line.
      - C6: `make test`, then `REJECT_DIFF_NO_CACHE=1 make preflight-changed`; quote each `Total:` line and the `reject-diff:` lines, and list every newly refused program (expected: `gap_92` and `gap_93`, each whole-program and under `zbuild`). Any other: stop and report, with the program; do not change it to fit.
      - C7: commit on `main` (the note says the fuzz record is stale for `src/`), add `**Awaiting review:**` with C2 to C6, `tm done`.

- [ ] +docs +AI-G @main The spec says a closure may not move a part out of a capture, and names the tests id:025c3
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Placed:** after id:v0rsm, in the batch the check-in id:48h1s reviews; found by the check-in id:qmms1 (finding 1). It depends on nothing.

    - **Why:** id:613zw made the compiler refuse a move of any part of a closure capture. `doc/spec/surface_syntax.md` §5.2 (_What a closure captures, and how_, the bullet **An owning value is moved**) still gives whole-value examples only, and does not cite the tests.
    - **Do:** in that bullet, replace `so moving out of a capture (`return v;`, `let w = v;`) or explicitly dropping it (`@drop(v);`) inside the closure is rejected (`cannot move out of a closure capture`; `err_closure_capture_move_out.zrl`, `err_closure_capture_drop_box.zrl`, `err_closure_capture_drop_vec.zrl`)` by `so moving a capture or any part of it out (`return v;`, `let w = v;`, a field or tuple part as in `let s = w.s;`, a payload bound by value by `match`, `if let`, a `let` pattern or `?`) or explicitly dropping it (`@drop(v);`) inside the closure is rejected (`cannot move out of a closure capture`; `err_closure_capture_move_out.zrl`, `err_closure_capture_drop_box.zrl`, `err_closure_capture_drop_vec.zrl`, and `closure_capture_field_moved.zrl`, `closure_capture_tuple_part_moved.zrl`, `closure_capture_struct_pattern_moved.zrl`, `closure_capture_match_payload_moved.zrl`, `closure_capture_if_let_payload_moved.zrl`, `closure_capture_let_pattern_payload_moved.zrl` and `closure_capture_try_payload_moved.zrl` under `tests/language/closures/`)`. Directly after that sentence's closing clause (`: doing so inside one call would leave the environment dangling for the next.`) add `The same holds for a captured value with a `Drop` impl, or a struct, enum or tuple holding one: reading it, matching it by reference and reading its `Copy` parts stay allowed (`tests/language/closures/closure_capture_read_without_move.zrl`).` No other file changes.
    - **Checks:**
      - C1: each test the new text names exists: `ls tests/language/closures/closure_capture_field_moved.zrl tests/language/closures/closure_capture_tuple_part_moved.zrl tests/language/closures/closure_capture_struct_pattern_moved.zrl tests/language/closures/closure_capture_match_payload_moved.zrl tests/language/closures/closure_capture_if_let_payload_moved.zrl tests/language/closures/closure_capture_let_pattern_payload_moved.zrl tests/language/closures/closure_capture_try_payload_moved.zrl tests/language/closures/closure_capture_read_without_move.zrl` lists eight files; and `./scripts/test.sh tests/language/closures/closure_capture_*.zrl` passes (quote its `Total:` line).
      - C2: `git diff --stat HEAD` names `doc/spec/surface_syntax.md` only.
      - C3: `make test-changed BASE=HEAD` before the commit; quote its `Total:` line.
      - C4: commit on `main`, add `**Awaiting review:**` with C1 to C3, `tm done`, and stop at the check-in id:48h1s.

- [ ] +safety +review +AI-D @main @checkin Review of the element rewrites, the non-`Copy` element rule (gap_92, gap_93) and the capture spec text id:48h1s
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Depends:** id:pex09, id:v0rsm, id:025c3
    > **Placed:** directly after the batch it reviews (a refactor the rule needs, a fix to a safety rule, and a spec change), by id:cx46y.

    - **Checks:**
      - Re-read the queue and `git log -p` on `main` since git:8aff926.
      - Re-run what each **Awaiting review:** bullet names. One uncached differential over the batch: `REJECT_DIFF_NO_CACHE=1 sh scripts/check_reject_diff.sh 8aff926`; expected newly refused: `gap_92` and `gap_93`, each twice, and nothing else; nothing newly accepted (id:pex09 changes no rule).
      - id:pex09 changes no behaviour of `zbuild`: a build, a second build that reuses every module, a build after one source is deleted (the `[frozen]` path, whose `deps` are now cloned), and `zbuild --gc`, compared with the binary of git:8aff926.
      - The id:cx46y probe programs (`build/cx46y/p/*.zrl` on the host that ran it): each `e*` and `b*` program that built is refused, and each `k*` program still exits 0.
      - Sibling routes not yet probed: a non-`Copy` element read through a raw pointer index in `unsafe` (still allowed, and said so in the spec text?); an element of a `HashMap` or another stdlib container returned by value by its accessor; `for` over a `Vec` by value; a range index (`a[0..1]`) of non-`Copy` elements; a `[mut &mut T]` element reborrowed (`&mut *a[0]`) twice.
      - The new §7.1 paragraph and the **Use After Move (Linear/Owned)** row say what the compiler does; `doc/SAFETY.md` has no class (N) and its counts match the tree.

- [ ] +safety +tests +AI-D @provenance id:z0093 B1.9a2 A closure body's summary is stated over its `__env` parameter
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0088 (why experiment A was unsound).
    > **Depends:** id:z0088, id:0m61c, id:z0180, id:n177h, id:3yasf
    > **Depends changed (2026-11-15):** added id:3yasf, the check-in of id:0tv49, since the next task after a batch waits for its review.
    > **Check-in:** stop for review after it. **Split here** if the design note and the implementation take more than a session: the design (§3 text and probes) first.

    - **Now:** inside a closure body every capture is read as the `Env` flag (`out O={Env}`), which `os_note_edges` turns into an `Unknown` value stored into a global: `|| { *out = routed; }` has the summary `store Unknown -> global`. An owned capture (moved into the environment) is also marked as storage of the body's own frame (`os_stmt`, "an owned capture's storage dies with the closure"), so a view of it cannot leave the body, but a store *into* it is a store into this frame and records no summary edge. A caller applying such a summary sees no store at all: id:z0088's experiment A did, and accepted 1490 unsafe grid cells (all `closure_owned_capture`, e.g. `arena_vec__arena_struct_bundle__direct__closure_owned_capture__frame_ends`, where the closure owns `h` and stores the view `routed` into it).
    - **Do:** summarise a closure body over its `__env` parameter (the last one, `lower_rv_call_ptr`): a capture is what `__env` reaches (`ParamContents(env)`); a store into a capture is an edge into it; an owned capture is storage the environment owns, so a store into it is an edge into `ParamContents(env)`, while a view of it that leaves the body (returned, stored outside the environment) is still refused. State it in the design note §3 (_Closure environments_), with the routes: by-reference and by-value captures, an owned capture, a nested closure, a closure capturing another closure, and `move` of the environment.
    - **Checks:** the store grid's 1490 cells refused by the body's own rules, not by the unknown-call rule (run the grid with id:z0094's pre-scan applied on top, as id:z0088 built it in `build/z88/esrc_ab`, and count 0 unsafe accepted); `closure_env_safe_twin.zrl` accepted; the owned-capture tests (`closure_captures_owning_and_other`, `closure_mutates_owning_capture`, `closure_owned_capture`; reduced in `build/z88/c1.zrl`: a closure that owns a `Vec` and pushes to it) measured. `make test`, `make preflight-changed`, the rejection differential, `sh scripts/run_safety_matrix.sh`.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +safety +tests +AI-D @provenance id:z0094 B1.9a3 A call through a local bound to one known function uses that function's summary
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0088 (option 1, experiment A).
    > **Depends:** id:z0093
    > **Check-in:** stop for review after it. Accepts more: the rejection differential applies.

    - **Now:** a closure or a `fn` item bound to a local and called in the same body (`let mut cl = || { *out = routed; }; cl();`, `let f_ptr: fn(..) = forward_fn_target; f_ptr(x)`) is an unknown call. Every closure and `fn`-value shape in the store grid is of this kind. After id:z0092, the unknown-call store rule still refuses the cells where the closure itself stores, since it must assume any frame-bound argument may go into any memory another reaches: `closure_capture_mut` 1708, `closure_call_mut` 2534 and `closure_owned_capture` 3300 safe twins (id:z0088, experiment B; id:z0092's grid run refuses the same set, `build/z92/grid/twin_rejections.txt`).
    - **Do:** before the passes, find each local assigned exactly one `FuncAddr` in the body (directly or by a plain copy of such a local; never through a `&mut`, a projection or two different functions); at a `CallPtr` through it, apply that function's summary with `os_call`, the callee value as `__env` (the last argument). id:z0088's version is in `build/z88/esrc_a/check_zir.zrl` (`z88_scan`, `z88_try_known`): a measurement aid, not a rule; rewrite it without the `static mut` state. A callee whose summary is not known yet (a recursive cycle) is handled as `os_call` handles it.
    - **Checks:** the store grid under `--provenance` (0 unsafe accepted, the 1490 cells of id:z0093 included; the closure destinations' twins counted by axis), and the 672 test programs (17 with warnings before id:z0092, 14 after it, as measured; `build/z92/measure.sh`). Probes: a local assigned two closures on two branches (stays unknown), a closure local passed by `&mut` to a callee that reassigns it, a closure called after the variable it captured was moved. `make test`, `make preflight-changed`, the rejection differential.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +safety +tests +AI-D @provenance id:z0096 A closure storing into a global, handed to a callee that calls it, is checked
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0092 (the store side of the rule's boundary).
    > **Depends:** id:z0093
    > **Check-in:** stop for review after it.

    - **Now:** `bench/safety_matrix/probes/gap_64_closure_global_store_via_fn_param.zrl`: `run(|| { G = r as *i32; })` with `fn run(f: fn()) { f(); }` and `r = &x` compiles with and without `--provenance`, and the global keeps a dead frame's address (exit 77). The closure body stores `Env` (not frame-bound) into a global; the unknown call through `f` in `run` records edges only into what its arguments reach, never a global, so `run`'s summary has none and the call to `run` checks nothing. The direct call `cl()` is refused by the old rules ("callee stashes local stack pointer via indirect call"); a `fn` item storing into a global cannot become a value (`check_fn_value` in `src/verify.zrl`), which id:z0012 has to carry over.
    - **Route class:** a closure passed as an argument to a callee that calls it (`gap_52`), here with a global destination. Probe the siblings: a `static mut` reached through a captured reference, a closure kept in a struct field, two levels of callers.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +precision +tests +AI-D @provenance id:z0097 An edge into a `fn` argument's environment does not make a `fn` item a global destination
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0092 (its accept probes).
    > **Depends:** id:z0092, id:0m61c

    - **Now:** an unknown call through a `fn` parameter `f` records store edges into `ParamContents(f)`, its environment (`os_unknown_call_effects`, the environment as argument K = ARGS.len). At a call that passes a `fn` item (`Static`, no environment), the edge's destination is the item's reach, `Static`, a global, so a frame address passed beside it is refused by the call store rule: `fn first(f: fn(&i32, &i32) -> &i32, a: &i32, b: &i32) -> &i32 { return f(a, b); }` called as `first(pick, &x, &y)` with locals, `walk(step, &x, n)`, `run(&m, &x)` with `m.f` a `fn` item (id:z0092's `build/z92/a_*.zrl`; the base compiler refuses them the same way). Inside the callee `os_unknown_arg` already reads a `Static` callee as adding no memory; the caller's edge mapping does not.
    - **Do:** decide whether an edge into the `ParamContents` of a `fn`-typed parameter maps, at the caller, to the environment of the value passed (`os_through` of its `O` without `Static`, as `os_unknown_arg` takes it) rather than to everything it reaches. A rule that removes destinations: the series rule's probes (a capturing closure passed in its place must still be refused, `gap_52`'s shapes), the store grid under `--provenance`, and `test_stdlib_iter.zrl`'s seven warnings read first to see whether they are this class.
    - **Found in id:z0092's review (2026-11-06):** the false global edge carries up through a summary. `fn apply<T>(f: fn(T) -> T, x: T) -> T { return f(x); }` and `fn via(p: &i32) -> &i32 { return apply::<&i32>(same, p); }`: `via`'s body is accepted, but its summary now stores `p` into a global (the edge into `ParamContents(f)` mapped to `same`, `Static`), so `main`'s `via(&x)` with a local is refused, "the callee stores an address of this frame into a global (call store rule)", one level above the `fn` item (`build/z92r/s_generic_hof.zrl`). A fix that maps the edge at the call must also keep it out of the caller's summary. The arena twins `f(&a, mk_vec, &mut v)` and `r(&a, mk_vec)` with a local arena are refused the same way (`build/z92r/s_param_vec.zrl`).
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +safety +tests +AI-D @provenance id:z0087 B1.9c An integer popped from a collection carries no address
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0064 (root (f)).
    > **Depends:** id:z0075, id:z0094, id:0m61c
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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +safety +tests +AI-D @provenance id:z0086 B1.9e A literal held by a value does not make what the value reaches a global destination
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0064 (root (e)).
    > **Depends:** id:z0087, id:0m61c
    > **Check-in:** stop for review after it.
    > **Routed (2026-11-06, by id:z0075):** a rule. id:z0084's rule is deferred, so this one must cover the lowerer's literals without it: `exh_missing` writes literals into a `ByteVec` in `self.arena`, which the call rule names `Param(0)` (`*self`), so the `Static` lands in `*self` and not only in the arena.

    - **Now:** a local that holds `Static` (a string literal in one of its fields, or written into memory it reaches) makes every later store into what it reaches have `Static` among its targets, and the call store rule reads `Static` as a global. In the driver, `ZirLowerer::lower_function`'s summary has `store Static -> Param(0)` (a dozen lowering functions write a literal into `*self`, the first in lowering order `exh_missing`), so `Driver::run_body_passes_in_scratch`'s local `zir_low` holds `Static`; it is the first function in lowering order with a store into a global. That carries the last 8 of `src`'s warnings (`src/driver/module.zrl:666`, `:713`, `:1141`, `:1188`, `:1475`, `:1603` into a global; `:1362`, `:1386` outlives), and the class covers id:z0064's three `arena_raw` test programs (`test_stdlib_string_arena`, `accept_slice_receiver`, `test_empty_compile_and_tool_errors`).
    - **Reduction** (`build/z64/t/e3.zrl`; builds, exits 0, accepted by default; "into a global" at the call in `main` under `--provenance=warn`; twin with `name: s` gives no warning): `struct W { name: [u8], items: &mut Vec<[u8]> }`, `impl W { fn add(self: &mut W, s: [u8]) { self.items.push(s); } }`, `fn inner(out: &mut Vec<[u8]>, s: [u8]) { let mut w = W { name: "lit", items: out }; w.add(s); }`, and `main` calls `inner(&mut v, &data)` with a local array `data` and a `Vec<[u8]>` `v`, returning `v[0][1] as i32 - 2`.
    - **Not yet measured alone:** replacing `ZirLowerer.new`'s `file_path: ""` changes none of the 8 (the other sites still write literals), and id:z0084's experiment alone does not remove them either. Find each site's route first (`--emit-origins` with the target-file filter in `src/driver/module.zrl` removed, as id:z0064's debug compiler did).
    - **Do:** decide whether a `Static` origin reached through a value may be dropped from store targets (a literal is read-only, so storing through it needs `unsafe`), or whether the sites change. A rule removes origins, so the series rule applies, with probes of a `static mut` reached through a value (which must stay a global destination) and a literal beside a `&mut` in one struct. `make test`, `make preflight-changed`, the rejection differential.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **id:z0084 promoted (2026-11-15, the check-in id:n177h):** it now runs directly after this task, so the routing above still holds: this task's rule must not rely on id:z0084's.

- [ ] +safety +tests +AI-D @provenance id:z0084 B1.9d Arena storage is named by the arena an argument reaches, not by the argument's address
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0064 (root (d1)).
    > **Depends:** id:z0075
    > **Depends note:** (it decides whether over-rejections are fixed by rules).
    > **Check-in:** stop for review after it. Accepts more: the rejection differential and the series rule apply.
    > **Deferred (2026-11-06, by id:z0075):** the root is seen only in code that uses a raw arena (zbuild's manifest parsing, the compiler), which is `unsafe` already; id:z0090 changes zbuild's sites instead, and none of the grid's or the tests' refusals is from it. Take this rule up when safe user code shows the class, with the reproducer below.
    > **Promoted (2026-11-15, the check-in id:n177h):** safe user code now shows the class (the reproducers in **Safe user code** below), so the deferral's condition is met. Placed before id:z0089 and id:z0090: it blocks id:z0065 (the default flip would refuse these safe programs, and id:z0065 asks that each over-rejection have its own task done first), and it may make id:z0090's zbuild changes unnecessary (its measurement alone took zbuild from 25 warnings to 0), so it runs before that `+AI-G` batch rather than after it.

    - **Safe user code (2026-11-15, the check-in id:n177h, `provenance` at git:913bf05, `build/zoril --provenance -I stdlib=stdlib -o /dev/null`):** each compiles in the default mode and is refused under `--provenance`; none uses `unsafe`.
      - P1, returning a clone of a local `Vec<u8>` (no view anywhere): `fn mk() -> Vec<u8> { let mut v = Vec::<u8>.new(); v.push(1 as u8); return v.clone(); }` -> `error: provenance: the returned value holds an address of this frame (return rule)`. `--emit-origins` shows the clone's result `_8 O={Frame(_1)} S={Frame(v)}`: its storage is named by `&v`'s own origin, `Frame(v)`, the `arena_store = tao` of **Now**.
      - P2, the same with `Vec<[u8]>` holding a parameter's view (`fn mk(b: [u8]) -> Vec<[u8]> { let mut v = Vec::<[u8]>.new(); v.push(b); return v.clone(); }`): same error.
      - P3, a `String` (`let mut s = String.new(); s.push_str("hi"); return s.clone();`): same error.
      - P4, `Vec<Vec<T>>.resize` with a value holding only a parameter's view (`fn f(out: &mut Vec<Vec<[u8]>>, b: [u8]) { let mut v = Vec::<[u8]>.new(); v.push(b); out.resize(1 as usize, v); }`): refused twice, once inside the standard library: `stdlib/vec.zrl:399:22: error: provenance: a value holding an address of this frame is stored into memory that outlives it (store rule)` (`value.clone()` in `resize`, where `value` is a by-value parameter) and at the call (`call store rule`).
      - P5, pushing into a clone of a parameter's `Vec`: `fn f(v: &Vec<[u8]>) -> Vec<[u8]> { let buf = [42 as u8; 16]; let mut c = v.clone(); c.push(&buf); return c; }` gets a `call store rule` error at `c.push(&buf)` as well as the expected `return rule` error: the push is refused because `c`'s storage is named `Param(0)`.
    - **Consequence for id:z0180's test:** `tests/language/memory/provenance/vec_clone_frame_views_returned_refused.zrl` is refused for P1's reason, not for the view it holds: take `v.push(&buf)` out and it is still refused. So it does not yet show that a `Vec` clone keeps its elements' origins. `option_clone_frame_view_returned_refused.zrl` does discriminate (its twin `clone_opt_view` is accepted).
    - **Checks to add when this task is settled:** P1 to P5 accepted (P5 still refused at `return c`, by the return rule only), added as functions of `tests/language/memory/provenance/clone_returned_accepted.zrl` (P5 as a refused test of its own); `vec_clone_frame_views_returned_refused.zrl` still refused, and refused no more with `v.push(&buf)` taken out (quote both); id:z0090's `W | grep -c 'warning: provenance'` before and after this task, quoted, so id:z0090 knows what is left for it.

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

- [ ] +refactor +tests +AI-G @provenance id:z0089 B1.9f `exh_expand_or` pushes a fresh copy of each row it keeps
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0064 (root (d2)).
    > **Depends:** id:0m61c
    > **Routed by:** id:z0075, to a code change at the site; the rule is deferred (id:z0085 in `future.tm.md`).

    - **Now:** `src/lower_zir/exhaust.zrl`, `ZirLowerer::exh_expand_or`: `if !is_or { out.push(row); }` pushes the row slice read out of `rows`. The new rules read a value copied out of a referenced `Vec` as an address into its buffer, and with the function's self-recursion (`return self.exh_expand_or(&out)`) that turns `exh_useful`'s summary into every parameter stored into every parameter and a global: 153 of `src/main.zrl`'s 167 "into a global" warnings under `--provenance=warn`.
    - **Do:** push a fresh copy of the row (`let copy = self.alloc_u32s(row.len);`, copy the elements, `out.push(copy);`), as the or-pattern branch a few lines above does. The rows are read-only pattern lists, so behaviour is unchanged; the cost is one scratch-arena allocation per kept row. A one-line comment says why the copy is there (the origin rules), without a task ID. Plain code: `src/` must build under the pinned stage1.
    - **Checks:** (`W` below is `timeout -k 5 180 build/zoril -I stdlib=stdlib -I src -I build/gen --provenance=warn --emit-zil -o /dev/null src/main.zrl 2>&1`.)
      - C1: before the change, `W | grep -c 'warning: provenance'` and `W | grep -c 'into a global'`; quote both (expected 195 and 167; if they differ, record the figures and go on, the change is what is measured).
      - C2: after the change and `make`, the same two counts; quote both (expected 185 and 14). A drop smaller than 10 and 150 means the copy is not at the site the warnings name: stop and report.
      - C3: the copy is the only change: `git diff --stat` names only `src/lower_zir/exhaust.zrl`, and its diff is the copy loop and the one comment.
      - C4: `rm build/zoril && make` (the build through stage1) and `make` again, neither with a warning; quote the last line of each.
      - C5: `./scripts/test.sh --filter 'exhaust|unreachable' tests` passes; quote its `Total:` line.
      - C6: `make test` and `make preflight-changed`, each `Total:` line quoted; the completion note says the fuzz record is stale for `src/`.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +tools +tests +AI-G @provenance id:z0090 B1.9g zbuild's manifest parsing gives no warning under `--provenance`
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0064 (root (d1)).
    > **Depends:** id:0m61c
    > **Routed by:** id:z0075, to code changes at zbuild's sites; the rule was deferred (id:z0084, promoted 2026-11-15 and placed before this task).

    - **Now:** `tools/zbuild` gives 25 warnings under `--provenance=warn` (18 and 4 call store rule, 2 return rule, 1 store rule), all in manifest parsing (`parse_manifest`, `parse_entry`, `write_manifest`, `load_manifest` in `tools/zbuild/src/manifest.zrl`). `parse_entry(&cols, arena)` takes the column `Vec` by reference, and because a `Vec` holds a raw arena pointer, the call rule names its result's arena storage by `&cols`'s address (`Frame(cols)`); what is read out of the result is then an address of this frame.
    - **Do:** change the sites so that no argument whose only tie to the arena is the `Vec`'s pointer names the result's storage. First try passing `cols.as_slice()` (a `[[u8]]`, which reaches no `ArenaHeader`) to `parse_entry`, then the sites the remaining warnings name. Keep the manifest format and behaviour unchanged. If a site cannot be changed without `unsafe`, stop and report: id:z0084's rule comes back instead.
    - **Checks:** (`W` below is `timeout -k 5 180 build/zoril -I stdlib=stdlib -I tools/zbuild/src -I src -I build/gen --provenance=warn --emit-zil -o /dev/null tools/zbuild/src/main.zrl 2>&1`.)
      - C1: before the change, `W | grep 'warning: provenance'`: the count and each line's location, quoted (expected 25).
      - C2: after each site's change, `W | grep -c 'warning: provenance'`, recorded per site; at the end 0. A site that needs `unsafe` to reach 0: stop and report, as **Do** says.
      - C3: `git diff | grep '^+.*unsafe'` prints nothing.
      - C4: the manifest is unchanged: build `tests/integration` or the `zbuild-link` scenario's project with the old and the new `build/zbuild`, and `cmp` the two manifest files it writes; quote the result.
      - C5: `./scripts/test.sh --gate zbuild-diff --gate safety-matrix-zbuild --scenario zbuild-errors --scenario zbuild-link` passes; quote it.
      - C6: `make test` and `make preflight-changed`, each `Total:` line quoted; the completion note says the fuzz record is stale for `tools/zbuild/`.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **After id:z0084 (2026-11-15, the check-in id:n177h):** id:z0084's rule is no longer deferred; it now runs before this task, and its record quotes C1's count after it. Take C1 from the tree as it is then, not the 25 above. If C1 is 0, change no code: complete the task with C1's output, answer C2 to C5 `not run: no warning left to remove`, and run only `make test-changed` for C6. If it is above 0, do **Do** for the sites that are left.

- [ ] +safety +review +AI-D @provenance @checkin Review of `exh_expand_or`'s row copy and zbuild's manifest warnings (id:z0089, id:z0090) id:7kbpd
    > **Created:** 2026-11-15
    > **Branch:** `provenance`
    > **Depends:** id:z0089, id:z0090
    > **Placed:** after id:z0090 by the check-in id:n177h, to review the `+AI-G` batch id:z0089 and id:z0090 before the next task (id:z0073) starts.

    - **Checks:**
      - Re-read the queue and `git log -p` since the commit of the last `+AI-D` task before id:z0089.
      - id:z0089: re-run its C1 and C2 (the two warning counts over `src/main.zrl`) and read the diff (the copy loop and one comment only; `src/` still builds through stage1, `rm build/zoril && make`).
      - id:z0090: re-run its C1 after id:z0084; if it changed code, its C3 (no new `unsafe`) and C4 (the manifest unchanged, `cmp`).
      - Probe the sibling sites: the other `out.push(row)`-style pushes of a row read out of a referenced `Vec` in `src/lower_zir/`, and any warning left in `tools/zbuild` under `--provenance=warn`.

- [ ] +safety +decision +AI-D @provenance id:z0073 B1.8b Decide whether storing a raw pointer into a by-value owner's buffer, then dropping the owner, is refused
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Found by:** the review of id:z0071.
    > **Depends:** id:0m61c, id:7kbpd
    > **Note:** Decision first; the fix or the probe is the next step it names.

    - **The case:** `struct Buf { data: *mut u8 }` with `Drop` freeing a heap block; `fn keep(out: &mut *mut u8, b: Buf) { *out = b.data; }` and `fn f(out: &mut *mut u8) { let b = Buf.new(); keep(out, b); }` (`tests/language/memory/provenance/addr_edge_by_value_owner_refused.zrl` at `403a092`), and the twin storing `BothPtr { own_v: Vec::<i32>.new(), p: b.data }` (`build/z71r/c2.zrl`). Accepted by the old rules and by `--provenance` at `a1ea096`; the caller's pointer is left dangling once `keep` drops `b`. Only `403a092` refused the first form, through the edge kinds id:z0072 removes.
    - **Question:** the stored value is a raw pointer, dereferenced only in `unsafe`. id:z0063 decided that the new rules check a raw pointer's origins (`Raw` is exempt only as a value). Does that make this a hole (a `known_gap` probe now, a fix that tells a moved owner from an address read out of it without per-store kinds), or is a dangling raw pointer outside the guarantee (record it in `doc/spec/safety_model.md` and `doc/spec/unsafe_policy.md`, with a test showing the accept)?
    - **Removed in `403a092` (id:z0072), until this is decided:** the test's full text is in `git show 403a092:tests/language/memory/provenance/addr_edge_by_value_owner_refused.zrl`; at `403a092` it compiles under `--provenance` and in the default mode.
    - **A sibling route (found in id:z0076, 2026-11-05):** an owner holding a raw pointer to memory outside the frame, whose safe method stores an argument through it (`put(self: &mut G, r: &i32) { unsafe { *self.p = r; } }` called with `&x`), is accepted in both modes: the destination reach does not follow a `*mut` an owner holds (`os_type_has` answers no for `RawPtrMut(x)` under `OS_Q_HANDLE`). Program in id:z0076's text (`build/z76/cx.zrl`). Decide it with this case: a raw pointer's target is the `unsafe` author's claim, or the call rule follows it.
    - **Two more sibling routes (found in id:z0076, 2026-11-06):** a frame address stored through the result of a `#[fresh]` function (`tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`) or through a heap block from `zoril_allocator_alloc(null, ..)` (`heap_block_store_through_old_rule_refused.zrl`), the pointer then returned, or the block put into a global (`heap_block_into_global_old_rule_refused.zrl`): any destination of the pointer. Since id:z0076 the new rules accept all three: the result has no origins, so a store through it reaches nothing they follow, as with a raw pointer an owner holds. The old region rule refuses all three in every mode today. Decide them with the case above: if a dangling raw pointer is outside the guarantee, say so in `doc/spec/safety_model.md`; if not, the store through a raw pointer with no origins needs a target (the fresh storage of the local holding it, say) before id:z0012 removes the old rule.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **Decided (the maintainer, 2026-11-14, in a review of the plan):** the three cases are decided apart. **A** (a raw pointer value left dangling: `keep(out, b)` copies `b.data` out and `b`'s `Drop` frees the block; the `BothPtr` twin): outside the guarantee. A raw pointer in checked code carries no promise about what it points to; the dereference is in `unsafe`, where the programmer checks, and the checker cannot know that an owner owns what its raw pointer field points to. **B** (a safe function whose `unsafe` block stores an argument through a raw pointer an owner holds: `put(self: &mut G, r: &i32) { unsafe { *self.p = r; } }`): outside the guarantee as to inference, but the store may not go undeclared: such a function must carry `#[stores(..)]`, and its callers are then checked by the call rule. That rule is written into id:z0011, with the bare-`extern` rule already proposed there. **C** (a frame address stored through a `#[fresh]` result or a heap block that then leaves the frame): decided by a measurement, id:71a06, before id:z0012 deletes the old rule that refuses it today.
    - **Left to do in this task:** state case A in `doc/spec/safety_model.md` and `doc/spec/unsafe_policy.md` (a raw pointer value may dangle; what is checked is the value side of id:z0063 and the dereference), with `addr_edge_by_value_owner_refused.zrl` (`git show 403a092:tests/language/memory/provenance/addr_edge_by_value_owner_refused.zrl`) restored as a test of the accept under a name that says so, and the `BothPtr` twin beside it. C1 both tests pass in the default mode and under `--provenance`; quote them. C2 `sh scripts/check_safety_model.sh` passes. C3 `make test-changed`, its `Total:` quoted.

- [ ] +safety +tests +AI-D @provenance id:z0011 B3 Declarations are checked against the body: `#[borrows(..)]`, `#[stores(..)]`, the `&self` default
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0049, id:z0064, id:0m61c
    > **Check-in:** stop for review after it.

    - **Rule (Decision 1):** a declaration may list more than the body proves (a wider public contract), never less. For a function with a body the effective ties and stores are the union of what the body proves and any declaration (id:z0010 already sums them); a declaration that claims less than the body is a compile error, the narrowing rule of `CHANGELOG.md`'s pre-1.0 note. The `&self` elision default and the declarations apply as written to bodyless items (`extern`, trait signatures, `.zri` imports). Each of the tree's 82 `#[borrows()]` declarations (such as `Lexer.text_from`) is either proved unnecessary by id:z0010's `ParamAddr`/`ParamContents` summary and removed, or converted into an explicit, reviewed `unsafe` interior with a `// SAFETY:` comment, listed with its decision in the commit. **Stop and report** before changing a `pub` stdlib signature.
    - **Test expectation note:** `tests/error_reporting/err_stores_attribute_false.zrl` currently expects a wider `#[stores]` contract than the body performs to fail; under the wider-contract rule that test changes (stop and document the test change per `AGENTS.md`).
    - **Probes:** an unannotated `&self` method passing a parameter's borrow through, the same through a trait, and safe-code `#[borrows()]` laundering (`gap_30_borrows_attribute_launder` stays rejected; `gap_44_borrows_attr_reset` is rejected once checked declarations refuse the narrowing `#[borrows()]` (it is accepted, exit 77, under `--provenance` at `c323b0e`: a reset hole, not an escape, so the store rules do not see it)); accepted: a `&self` method returning a view of `self` and a wider `#[borrows]`/`#[stores]` public contract. `make test`, `make preflight-changed`. Stop for review.
    - **Blind spot not covered by this check (from id:z0049's review, 2026-11-05):** a body that copies through a bare `extern` proves no store, so a declaration can never be "narrower than the body" there (id:z0060's `extend_from_slice` route). Add a rule here or in a task of its own: a safe function that passes a pointer derived from a parameter to an `extern` with no declared effect must declare its own `#[stores]`/`#[borrows]` (or the `extern` declares its effect). Probe it with id:z0060's reproducer with id:z0060's fix taken out.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **Added by id:z0073's decision (the maintainer, 2026-11-14):** case B there. A safe function whose `unsafe` block writes a value that can hold a reference or a slice through a raw pointer (one it was given, or one an argument holds: `unsafe { *self.p = r; }`) must declare `#[stores(..)]` naming the argument stored and the one it is stored into, or it is a compile error; the declaration is then a trusted claim (`doc/SAFETY.md` §4.2) and the caller applies the call store rule to it. It is one rule with the bare-`extern` rule of the **Blind spot** bullet above: a safe function may not hide a store behind an operation the checker cannot read. Probe: `put` with and without the declaration (`build/z76/cx.zrl` in id:z0076's text), a caller passing `&x` of a local with `g` reaching outside the frame (refused once declared), the same store of a plain integer (no declaration needed), and the count of functions in `stdlib/`, `src/` and `tools/` that newly need a declaration, measured before the rule is made an error. If that count makes this task more than a session, split the rule into a task of its own directly after this one.

- [ ] +safety +design +AI-D @provenance L1 A liveness model: what holds a borrow when no local does, stated as the design note states origins id:dhded
    > **Created:** 2026-11-14
    > **Branch:** `provenance`
    > **Depends:** id:0m61c
    > **Placed:** before id:z0044, which it blocks: id:z0044 extends the per-local borrow set, and this task decides whether that set is the model. Found in a review of the plan (the maintainer's request, 2026-11-14). Order suspected wrong: id:z0044's **Depends:** does not name this task (an agent does not edit it); the maintainer may add it.
    > **Check-in:** none of its own (`+AI-D`); the maintainer reads the design before L2 starts.

    - **Why:** `doc/design/provenance.md` gives the escape half one model (origins, `Unknown` rejects, one summary, a fixpoint) and says of the other half "**Liveness** stays where it is": the flow-sensitive `ActiveBorrow` set, a borrower *local* and a borrowed place. Where no local holds the view, nothing holds the borrow: `gap_87` (git:172c77e), and the routes of `gap_37` to `gap_39`, `gap_43` and `gap_44` are the same family seen from the caller. The escape rules had the same shape before the series (a shape the classifier does not know is allowed, §2 "Unknown means allowed"); this task asks the same question of liveness.
    - **Do:** write a section of the design note (a "Liveness" section beside §3) that states:
      1. What can hold a borrow besides a local: memory a parameter reaches, a global, a closure environment, a call result. Proposed starting rule, to confirm or replace: *a view stored into memory that outlives the frame is live until the frame returns*, so after `*out = v.as_slice()` the referent of `v` stays borrowed for the rest of the body; and at the caller the callee's `i -> j` store edge (id:z0010) makes argument `j` hold a borrow of argument `i` (id:z0044's half).
      2. What invalidates: `free`, `reset`, `reset_to`, `@drop`, a move, a `&mut` use, and a call whose summary says the callee invalidates what a parameter reaches. Say whether a summary needs a new fact ("invalidates `Param(i)`") or whether "takes `&mut`" is enough, as it is for a local today.
      3. What the checker answers when it cannot tell which storage a stored view points into: it must refuse (the liveness counterpart of `Unknown`). List every place `check_zir.zrl` skips a write or a borrow today (`place_writes_through_pointer` is one; find the others with a mutation or a census, not by reading alone) and say what each answers under the model.
      4. Bodyless items (`extern`, a trait signature, a `fn` value, a `.zri` import): what is assumed.
      5. Every open liveness gap against the model, as §4 does for escapes: `gap_37`, `gap_38`, `gap_39`, `gap_43`, `gap_44`, `gap_87`, and the `Box` drop series' routes (id:z0019 to id:z0022 in `future.tm.md`), each with "caught by".
      6. What it will newly refuse, to measure: the count over `src/`, `stdlib/`, `tools/` and `tests/` of a store through a parameter followed by a `&mut` use of the source in the same body (a scratch warning, as `--provenance=warn` was).
    - **Probe before writing** (each a program under 20 lines, built and run, the result quoted here): the store into a global through `unsafe`; into a closure's captured `&mut`; a returned struct holding the view, then the free in the caller of the caller; a trait method; `push` in place of `free` (a reallocation: `build/review/p1b.zrl` of the review returned 42, so find a size at which the old buffer is reused); `Arena.reset` through a `&mut Arena` parameter with a view stored through another parameter; the same with the view stored *before* the callee and the callee only invalidating (`fn kill(v: &mut Vec<i32>) { v.free(); }` called while the caller's `out` parameter holds a view).
    - **Then:** rewrite L2 (id:kqp9n) and id:z0044 as the implementation steps of the model, each with its numbered **Checks:**, or say that they stand. A grid like the store grid (holder of the view × how it got there × what invalidates × where) is a task of its own if the design shows the routes multiply.
    - **Checks:** C1 each probe above has its program and observed result in this task. C2 the design note section answers 1 to 6, and §4's table has a row per liveness gap. C3 the measurement of 6 is quoted with its command. C4 L2 and id:z0044 each have **Do:** and numbered **Checks:** that follow the design, with a take-out check.

- [ ] +safety +tests +AI-D @provenance L2 A view stored through a parameter keeps what it views borrowed for the rest of the body (gap_87) id:kqp9n
    > **Created:** 2026-11-14
    > **Branch:** `provenance`
    > **Depends:** id:dhded
    > **Placed:** after L1 (id:dhded), which settles its rule, and before id:z0044, its caller-side twin.
    > **Check-in:** stop for review after it: a fix to a safety rule.
    > **Closes:** `gap_87_view_stored_through_param_outlives_free`.

    - **Found (2026-11-14, a review of the plan; probe in git:172c77e on `main`):** `fn k2(out: &mut [i32], v: &mut Vec<i32>) { *out = v.as_slice(); v.free(); }` is accepted by `build/zoril` at git:a662fda (built with `scripts/build_zrl.sh`, run: exit 77 where the buffer held 42) and compiles under `--provenance` on `provenance` at git:92bb15f (`build/zoril --provenance --emit-zil`, rc 0, not run). Accepted the same way, exit 77 on `main`:
      - `fn k2(out: &mut Vec<[i32]>, v: &mut Vec<i32>) { out.push(v.as_slice()); v.free(); }`
      - two callees: `fn fill(h: &mut H, v: &mut Vec<i32>) { h.s = v.as_slice(); }`, `fn kill(v: &mut Vec<i32>) { v.free(); }`, `fn both(h: &mut H, v: &mut Vec<i32>) { fill(h, v); kill(v); }`
      - one parameter: `struct P { a: Vec<i32>, s: [i32] }`, `fn poison(p: &mut P) { p.s = p.a.as_slice(); p.a.free(); }`
    - **Refused today (the twins to keep refused):** the one-parameter form on a local (`p.s = p.a.as_slice(); p.a.free();` in `main`: `cannot mutably borrow 'p.a' while it is already borrowed`), and `let s = v.as_slice(); v.free(); return s[0];`.
    - **Not shown:** `v.push(..)` in place of `v.free()` compiles and the run returned 42 (the old buffer was not reused), so the reallocation route is accepted but not demonstrated; L1 probes it.
    - **Route class:** a view of what a parameter reaches, stored into what a parameter reaches, then invalidated in the same body. id:z0044 does not close it as written: it carries the borrow "to the local the pointer refers to", and here there is none.
    - **Not ready:** L1 writes this task's **Do:** and numbered **Checks:**. They include: `gap_87` flipped to `compile_reject` with its Known gaps entry and `doc/SAFETY.md` §6 class (M) removed; the three sibling forms above as `compile_reject` probes; an accepted twin for each (the store with no later invalidation; the invalidation before the store); the fix taken out and `gap_87` watched to run (exit 77); the rejection differential with every newly refused program listed; `make test` and `make preflight-changed`, each `Total:` quoted.

- [ ] +safety +tests +AI-D @provenance id:z0044 B0.1 A value stored into a local's field through a pointer to the local keeps its borrow
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Check-in:** stop for review after it.
    > **Closes:** `gap_37_local_mutref_field_reset`, `gap_38_param_field_reset`, `gap_39_method_self_field_reset`, `gap_43_box_field_reset`.
    > **Depends:** id:z0010, id:z0011, id:dhded
    > **Depends changed (2026-11-14, the maintainer, in a review of the plan):** added id:dhded (L1), the liveness model: L1 decides whether this task's per-local borrow is the rule and rewrites its **Do:** and **Checks:**.

    - **Scope (narrowed to intra-frame liveness, 2026-11-03):** the frame-escape siblings (`gap_40`–`gap_42` and `gap_45`) are handled by id:z0048/id:z0012's origin sets. This task fixes intra-frame `Arena::reset` / `free` / `@drop` liveness (`ActiveBorrow` in `src/check_zir.zrl`), where a slice written into a local struct's field or a `Box`'s contents through a local `&mut`, through a callee's `&mut` parameter, through `self` in a `&mut self` method, or through `*b` on a `Box` is skipped today (`place_writes_through_pointer`), letting `a.reset()` pass while the field is read afterwards.
    - **Do:** carry the stored value's borrows to the local (or `Box` local) the pointer refers to: for a local `&mut` or `Box` deref, through the pointer's borrow/ownership of that local; for a callee, through id:z0010's pairwise `i -> j` store summary (`#[stores(..)]` checked in id:z0011). Probe the sibling routes: a `&mut` held in a struct field, a reborrow, a closure capturing `&mut w` across `a.reset()`, and a trait method; also verify `gap_44_borrows_attr_reset` is rejected once checked `#[borrows()]` is active.
    - **Found by id:z0047 (pre-existing over-rejection):** `fn f(view: [i32]) -> i32 { let mut w = ...; let r = &mut w; r.s = view; ... }` called with stack `f(&data)` is refused today by `src/summary_pass.zrl`; confirm id:z0012's retirement of `summary_pass.zrl` removes that refusal without reopening any reset hole.
    - **Probes:** `gap_37`, `gap_38`, `gap_39` and `gap_43` flip to `compile_reject`, with an accepted twin for each (the field is read before `a.reset()`). Check the over-rejection recorded on id:z0017 does not grow.
    - **Verification:** `make test`, `make preflight-changed`, the rejection differential; `bench/fuzz/README.md` stays stale for `src/`. Stop for review.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +diagnostics +AI-G @provenance id:z0066 B3.9 Provenance diagnostics name the origin they found, once per site
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Found by:** id:z0049's review (correction 8).
    > **Depends:** id:0m61c

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +safety +tests +AI-D @provenance id:z0065 B4a The new rules on by default, beside the old ones
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Split from:** id:z0012.
    > **Depends:** id:z0064, id:z0075, id:z0088, id:z0092, id:z0180, id:z0093, id:z0094, id:z0097, id:z0087, id:z0086, id:z0084, id:z0089, id:z0090, id:z0011, id:z0044, id:z0066
    > **Depends changed (2026-11-15, the check-in id:n177h):** id:z0084 added: it is the over-rejection of safe user code (a clone of a local `Vec` or `String` returned, `Vec<Vec<T>>.resize`) that this task requires to have its own task done first.
    > **Check-in:** stop for review after it.
    > **Ordering note:** this task only refuses more, and depends in substance only on id:z0064 (the tree must be clean); the maintainer may move it ahead of id:z0011 and id:z0044 to close the escape holes for users sooner. (id:z0084, id:z0085 and id:z0091 are deferred to `future.tm.md`, and id:z0095 and id:z0096 are holes in both modes, not dependencies.)

    - **Do:** make the rules of `--provenance` run by default **in addition to** the old rules (nothing is deleted here; the old rules still run). Keep `--provenance=warn` as a developer option or retire it; decide and record. Resolve whatever the default build of `src/`, `stdlib/`, `tools/` and `tests/` now refuses, per id:z0064's classification (a real escape: fix the code; an over-rejection: it should already have its own task done).
    - **Code changes id:z0064 left here (2026-11-06):** `Driver::lower_fn_body` pushes `OsPending { zir: zir_func }` into `self.os_pending` (`src/driver/module.zrl`, 2 warnings): `zir_func`'s slices are tied to the local `zir_low` though they live in the driver's scratch arena; change the code or route it to id:z0084's rule. `Driver::set_ice_context` stores an arena-built note into a global through `set_ice_note`'s `#[stores(note -> static)]` (`src/driver/module.zrl:864`): a true store, safe only because the arena lives as long as the program, and no warning of its own once the other roots are gone; if the default build refuses it, an explicit `unsafe` with a `// SAFETY:` comment naming that invariant, not a rule.
    - **Probes:** every `known_gap` probe the new rules refuse flips to `compile_reject` (at id:z0059: all escape gaps except the liveness ones `gap_37`, `gap_38`, `gap_39`, `gap_43`, `gap_44`; since id:z0060 also `gap_56`, since id:z0061 `gap_57` and `gap_58`, since id:z0062 `gap_59` to `gap_62`, since id:z0072 `gap_63`; re-check each), with its Known gaps entry in `doc/spec/safety_model.md` and line in `doc/SAFETY.md` §6 removed. Accept probes newly refused: none allowed without a task.
    - **Store grid:** re-record `bench/fuzz/store_grid_expected_failures.txt` and `store_grid_twin_rejections.txt` (and the modular pair) under the new default; list in the completion note every twin newly refused, by axis.
    - **Accepted refusal (id:z0075, 2026-11-06):** the 18 safe twins refused because an assignment to a local's field keeps the field's old origins (`{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{same_param,store_param_65}__{deref_out,field_out}__frame_ends`) stay refused: add a `KNOWN_ISSUES.md` §5 entry with the reduced program from id:z0091 (`future.tm.md`), the fix that would remove it, and how to rewrite: give the field its final value when the local is built (`let carrier_tup = (src_val, 10);` in place of `(&seed, 10)` then `carrier_tup.0 = src_val;`: no warning, checked on id:z0064's compiler). Any other twin newly refused here needs a task, per the rule above.
    - **Verification:** `make test`, `make preflight-changed` (the differential must show 0 newly accepted; list the newly refused programs), `sh scripts/check_store_grid.sh`, the self-hosting fixpoint. The fuzz record goes stale for `src/`. Stop for review.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **When the rules become the default (2026-11-14):** flip the `main` probes the provenance rules close and the old rules do not: `gap_79` and `gap_80` (id:z0183), `gap_77` and `gap_78` (id:z0180), each with its Known gaps entry and `doc/SAFETY.md` §6 sentence, and check the class (K) and (F) probes `gap_59` to `gap_63`, which a by-value-aggregate fix in the old rules closed in part (id:z0183's **Tried** bullet).

- [ ] +safety +tests +AI-D @provenance id:z0074 B4b List every program the old rules refuse and the new rules accept, and read each
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Found by:** the review of id:z0071.
    > **Depends:** id:z0065

    - **Why:** `leak_vec` (id:z0071) was refused by neither differential the series runs: the rejection differential compares two compilers in the default mode, and `build/rv/provdiff.sh` compares `--provenance` before and after a change over the existing probes. A reviewer found it by hand. id:z0012 deletes the old rules, so every program only they refuse is accepted after it; that list is not computed anywhere.
    - **Do:** run the new rules alone (a scratch compiler with the old rules' refusals off, as `check_reject_diff.sh` builds its base in a scratch worktree, or a developer flag if one is cheaper; say which) and the default compiler over the rejection differential's program set (69,122 at id:z0071, `tests/`, the safety probes, the store grid twins). List every program refused by the default and accepted by the new rules alone, and read each: a real escape gets a fix or a `known_gap` probe before id:z0012; a safe program is recorded as id:z0012's intended acceptance.
    - **Make it a gate** if it is cheap enough: id:z0012's completion note then lists the same set, empty of unsafe programs.
    - **Known members (from id:z0076, 2026-11-06):** `tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`, `heap_block_store_through_old_rule_refused.zrl` and `heap_block_into_global_old_rule_refused.zrl` are refused by the old region rule only: a frame address stored through a `#[fresh]` result or a heap block, the pointer then returned or put into a global. Their expected diagnostic names the old rule, so they fail when it goes; id:z0073 decides what replaces it.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +safety +measurement +AI-D @provenance B1.8c Measure: a store through a local raw pointer adds the stored value's origins to that local, so a heap block holding a frame address cannot leave the frame id:71a06
    > **Created:** 2026-11-14
    > **Branch:** `provenance`
    > **Depends:** id:z0073, id:0m61c
    > **Placed:** before id:z0012, which it blocks: id:z0012 deletes the old region rule, the only rule that refuses case C of id:z0073 today.
    > **Check-in:** stop for review after it if the rule is kept: it changes a safety rule.

    - **Why (the maintainer's decision in id:z0073, 2026-11-14):** case C (a frame address stored, inside `unsafe`, through the result of a `#[fresh]` function or a block from `zoril_allocator_alloc(null, ..)`, the pointer then returned or put into a global) is decided by measurement. The three programs are `tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`, `heap_block_store_through_old_rule_refused.zrl` and `heap_block_into_global_old_rule_refused.zrl`: refused by the old region rule only, accepted by the new rules since id:z0076 (the pointer has no origins, so a store through it reaches nothing they follow).
    - **Candidate rule (not tried; from the review, 2026-11-14):** a store through a raw pointer held by a local `p` (`*p = v`, `p[i] = v`, a field through it) does `O(p) |= O(v)`, as a write into a projection of a local does. `p` then holds `Frame` when `v` does, and the return rule and the store rule refuse `p` leaving the frame. Say first whether the transfer already does this for a raw pointer with origins, and why a pointer with none is skipped.
    - **Measure:** build a scratch compiler with the candidate (under `build/`, never replacing `build/zoril`), with the old rules off as id:z0074 builds it or under `--provenance` alone: 1. the three programs above: refused or not, and by which rule. 2. `--provenance=warn` over `src/main.zrl`, `tools/zbuild/src/main.zrl`, `tools/zilc` and the test programs (`build/z92/measure.sh`, 672 programs at id:z0092): the warning count before and after, and each new warning read (a real escape, or a safe program refused). 3. the store grid under `--provenance`: no unsafe cell newly accepted, the safe twins newly refused counted by axis. Probe the siblings: the pointer copied to a second local before the store; the pointer held in a struct field of a local; the store made by a callee given the pointer; a pointer from `@ptr_from_int` (`Raw`, exempt as a value by id:z0063: say whether it stays exempt as a carrier).
    - **Then decide, by the maintainer's rule:** if the candidate refuses the three and adds no refusal in the tree (or only real escapes), keep it: commit it with the three tests' `EXPECT:` lines naming the new rule, and say so here. If it refuses safe programs in the tree, do not keep it: case C is outside the guarantee, recorded in `doc/spec/safety_model.md` and `doc/spec/unsafe_policy.md` beside case A, and the three tests become tests of the accept (their expected result changes: stop and report, as `AGENTS.md` asks for a changed expectation).
    - **Checks:** C1 the three programs' results before and after, each quoted. C2 the warning counts before and after with their command, and every new warning listed with its reading. C3 the store grid's summary, quoted. C4 each sibling probe's program and result. C5 the decision recorded here with the figure that made it; if kept, the candidate taken out and the three tests watched to fail; `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, each `Total:` and the `fresh (no cache)` line quoted.

- [ ] +safety +tests +AI-D @provenance id:z0012 B4 Make `--provenance` the default, delete the old classifiers, and fix what the measurement found
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0011, id:z0044, id:z0065, id:z0063, id:z0073, id:z0074, id:z0075, id:z0096, id:71a06
    > **Depends changed (2026-11-14, the maintainer, by id:z0073's decision):** added id:71a06, which decides case C before the old region rule is deleted.
    > **Check-in:** stop for review after it. **Split here** if the tree needs more than a session of changes.
    > **Split (2026-11-05, from id:z0049's review):** turning the rules on by default beside the old ones is id:z0065 (it only refuses more); this task is now the half that accepts more: delete the old rules and `src/summary_pass.zrl`, with the rejection differential, and the docs and twin lists. The fixes of the measurement are id:z0060 to id:z0063, and the `unsafe fn` exemption item moved to id:z0063, which narrowed it to `Raw`.

    - **Do:** make the new rules the default and remove `--provenance`; resolve every warn-mode rejection recorded in id:z0049 and id:z0011 (a real escape: fix the code; a common over-rejection: apply the decided fix; a leak through a by-value collection parameter: change the code); then delete `local_storage_external`, `local_is_external_target`, `rvalue_is_external_target`, `place_outlives_frame`, `rvalue_storage_external`, `storage_walk_zir`'s mask logic, `note_call_stores_zir`, the depth limits, `is_collection_type_name`, the same-parameter filters, and `src/summary_pass.zrl` (keeping `src/verify.zrl`'s stack-address check as an add-only second net).
    - **Flip probes and twin lists (including id:z0045's):** flip all closed `known_gap` probes (`gap_07`, `gap_11`, `gap_13`, `gap_16`, `gap_18`, `gap_21`, `gap_23`, `gap_26`, `gap_27`, `gap_28`, `gap_29`, `gap_32`, `gap_33`, `gap_36`, `gap_40`, `gap_41`, `gap_42`, `gap_44`, `gap_45`, `gap_47`, `gap_48`, `gap_49`, `gap_50`, `gap_51`, `gap_52`, `gap_53`, `gap_54`, `gap_55`) to `compile_reject` and remove their Known gaps entries in `doc/spec/safety_model.md` and `doc/SAFETY.md` §6. Fold in id:z0045: remove the 3402 `ref_{let,identity,phi}` twins (and any id:z0017 twins newly accepted when `summary_pass.zrl` is retired) from `bench/fuzz/store_grid_twin_rejections.txt`, flip `read_through_{ref,identity,phi}.zrl` from `expected compile fail` to running tests, add an `accept` probe for `id:z0045` and a regression test returning `s.as_slice()` from `String.with_capacity(a, cap)` (`a: &Arena`). Because retiring `summary_pass.zrl` and `local_storage_external` accepts more safe programs, run `scripts/check_reject_diff.sh <base>` and list every newly accepted program class in the completion note (none may be unsafe). Update `doc/SAFETY.md` §2.3 and §5–§6, `doc/spec/surface_syntax.md` (`#[borrows]`/`#[stores]`), `README.md`, `KNOWN_ISSUES.md` and `bench/fuzz/store_grid_expected_failures.txt`.
    - **End criterion of the series (the maintainer, 2026-11-06, at id:z0075):** zero unsafe programs accepted is the hard requirement (the grid, the safety probes, the rejection differential). Zero safe programs refused is not reachable by any checker that accepts no unsafe one; the target is that no remaining refusal is common in user code (the tests as its stand-in), each is a documented class in `KNOWN_ISSUES.md` §5 with a reason and a rewrite (id:z0017 audits them), and its diagnostic says what was found (id:z0066).
    - **Done when:** every unsafe store-grid cell (whole-program and modular) is rejected, no `known_gap` probe of this family remains, the self-hosting fixpoint holds, and `make test` and `make preflight` pass. Stop for review, then close id:z0045 (citing this commit on `main`) and start id:z0017 and id:z0013 (and renew the fuzz record per id:z0003).
    - **From id:z0092 (2026-11-06):** the old rules refuse making a `fn` item that stores into a global or another parameter into a value (`check_fn_value` in `src/verify.zrl`); the new rules have no counterpart, since a call through a `fn` value records no store into a global (design note §3, _Calls through a `fn` value_). Carry it over before deleting the old rules: id:z0096 is the closure half of the same route. **Depends also:** id:z0096.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +audit +AI-D @provenance id:z0017 A3.5 Twelve safe store-grid twins are rejected
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0012
    > **Depends note:** (do not debug `src/summary_pass.zrl` before id:z0012 deletes it). Over-rejection audit, not a hole.

    - **Cells (before id:z0012):** `{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{closure,param_65}__call_struct_mut__frame_ends` (12 cells) plus 96 cells exposed by id:z0008 in `bench/fuzz/store_grid_twin_rejections.txt`, rejected today by `src/summary_pass.zrl` ("region escape: storing local stack pointer into caller memory"). Also note the sibling found in id:z0047's review: passing a local struct `RefHolder { r: &c }` by value to `take_holder(h)` retains `Frame(c)` (`os_reach_all`).
    - **Over-rejection from id:z0007 (found in its review, 2026-11-03):** liveness borrows are tracked per local, not per field, so `w.s = v.as_slice(); let x = w.s[0]; a.reset(); return x - 42 + w.t - 3;` is refused at `a.reset()` because `w` stays live for `w.t`.
    - **Do (after id:z0012):** inspect every twin still listed in `bench/fuzz/store_grid_twin_rejections.txt` once `summary_pass.zrl` is gone (`param_65` twins should be accepted via the overflow bit; `closure`/`fn`-value twins: Decision 3 is decided (id:z0088), so any still refused after id:z0092 to id:z0094 is a finding, not a bound by design). Fix any unintended over-rejection without reopening any probe, add an `accept` probe for any fixed class, and document any deliberate precision bound (such as field-insensitive borrows) in `KNOWN_ISSUES.md` §5. `make test`, `make preflight-changed`, the rejection differential.
    - **Done when (2026-11-06, the series' end criterion, recorded on id:z0012):** every safe twin still in `bench/fuzz/store_grid_twin_rejections.txt` (and the modular list) is in a class `KNOWN_ISSUES.md` §5 names, with its reason and a rewrite, and none is common in the tests. `closure`/`fn`-value twins follow id:z0088's decision, not the note above.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +zil +decision +AI-D @zil ZL1 Settle the slice form of string_const and the slice_ptr opcode, and check what the pinned stage1 feeds zilc id:m6vm3
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:z0017
    > **Placed:** after the provenance series (`id:z0017`), before ZL2 to ZL6. Nothing in `testinfra` depends on it. ZL4 changes the per-file runner, which `testinfra` rewrites (id:z0139).

    - **Why:** `string_const` is to give a `Slice<u8, 'local>` everywhere, as the spec says (id:1kaye, decision 1). Hand-written ZIL then needs `slice_ptr` to get the data pointer back.
    - **Decide, and write into ZL2 to ZL5 as their **Do:** and numbered **Checks:**:** (a) What a slice-typed `string_const` lowers to in zilc's QBE output: a static `{ptr, len}` pair beside the bytes, whose address is the value, or another layout. It must match how the front end's slice slots are laid out (pointer at offset 0, `usize` length at 8, today's `v5` slot in `--emit-zil`). (b) How the front end uses it: copy the pair into the slot, or use the value directly. (c) `slice_ptr`'s syntax, typing and spec entry beside `slice_len` (`doc/spec/intermediate_language.md` §5), and whether the front end's cast-and-load idiom is replaced by it. (d) What the pinned stage1 feeds to which zilc: does any path pass ZIL written by `bootstrap/stage1/` to the new `build/zilc`, `zilc-boot` included? If one does, the new zilc must also accept the old form until a re-pin, which is the maintainer's. (e) Which recorded figures change (`corpus/zrl_whole_program_zil.sha256`, the safety figures) and how each is recomputed.
    - **Also place:** the statement, decided in id:ahd1c, that ZIL is not checked for memory safety (`doc/spec/intermediate_language.md` and `doc/spec/safety_model.md`: the claims cover programs compiled from Zoril source, and zilc catches the common mistakes listed by ZL6). Put it into one of ZL2 to ZL5, or into a task of its own.
    - **Checks:** C1: each of (a) to (e) answered here, with the command that showed it for (d). C2: ZL2 to ZL5 each have a **Do:** and numbered **Checks:**, with a take-out check.

- [ ] +zil +AI-G @zil ZL2 string_const gives a Slice in the front end and in zilc, read back with slice_ptr id:qpc8d
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:m6vm3
    > **Placed:** after ZL1, which settles it.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope: the front end emits the slice form, zilc lowers it, the type check and `src/verify.zrl` type it, `slice_ptr` is added, the spec matches, and `corpus/zil/15_io_syscall.zil` and `19_fd_io.zil` are rewritten to print exactly their strings.

- [ ] +zil +AI-G @zil ZL3 One spelling for cast: zilc refuses bitcast and the corpus is rewritten id:htrqb
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:qpc8d
    > **Placed:** after ZL2: the corpus files it rewrites are the ones ZL2 changes.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope: `tools/zilc/src/zil_parse.zrl` refuses `bitcast` with a diagnostic that names `cast`, and the six corpus files that use it (`02_comparison`, `12_enums_sum`, `13_slices`, `15_io_syscall`, `19_fd_io`, `24_tuples`) use `cast`. The spec's line 92 stays true.

- [ ] +zil +tests +AI-G @zil ZL4 Corpus and per-file tests check the program's output, not only its exit code id:ehh6m
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:htrqb
    > **Placed:** after ZL3.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope (decision 3): a per-file test can state its expected output (a header directive or a sibling file, chosen in ZL1, read by the one header reader, `tr_expectations`, or by its replacement in `ztest`). Every `corpus/zil/` program and every corpus program that prints states its output. A check plants the 4 KB over-read of id:1kaye and shows that the test fails.

- [ ] +zil +safety +AI-G @zil ZL5 zilc runs the ZIL verifier that the compiler runs id:egsdq
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:ehh6m
    > **Placed:** after ZL4, last in the series. A check-in follows it, added by ZL1 with the series' other check-ins.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope (decision 4, the small step): zilc runs `src/verify.zrl` on what it parses, as the compiler does after lowering, so hand-written ZIL gets the same ZIL-level checks (stack-address escape, constant arena allocations) that compiled programs get. Not a borrow checker; that question is id:ahd1c.

- [ ] +zil +safety +audit +AI-D @zil ZL6 Which common mistakes in hand-written ZIL zilc can catch from what ZIL says id:0mbg3
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decision in id:ahd1c (`future.tm.md`)
    > **Branch:** `zil`
    > **Depends:** id:egsdq
    > **Placed:** after ZL5, which gives zilc the ZIL verifier this task extends.

    - **Why:** ZIL is not checked for memory safety, but zilc should catch the mistakes that are easy to see in ZIL as designed and that happen most often (the maintainer, id:ahd1c).
    - **Do:** list candidate checks, each with a three-line ZIL program that shows the mistake, and say for each whether ZIL as written carries what the check needs. Candidates to start from: a value used after a `move` or `drop` in the same function, a `drop` twice, a `slice_load`/`slice_store` with no dominating `bounds_check` (spec §6.3), the address of an `alloc 'local` returned or stored into a global, a `slice_len` or `slice_ptr` on a value that is not a slice, a `syscall` with an argument count its stub does not take, and a block with no terminator. Corpus mistakes count as evidence of what is common: id:1kaye's string over-read is one. Rank them by how often they would fire and how simple they are, and split each chosen check into an `+AI-G` task with its own numbered **Checks:** and a take-out.
    - **Checks:** C1: every candidate has its program and its answer here, with the zilc output today (`timeout -k 5s 30s build/zilc <file>`). C2: the chosen checks are tasks, placed after this one, with a check-in after them.

## Sprint notes

Dated decisions and records, oldest first. Statements of order in them are history (see **How to read this file**). The notes of the `main` and `provenance` sections moved to `future.tm.md` with their tasks on 2026-11-12.

**Branches (2026-11-09, the maintainer, id:z0163):**
The history after `v0.1.0-alpha` is split by line of work:
1. `testinfra`: the test-efficiency series (`+testinfra`, id:z0103 to id:z0125, id:z0145 to id:z0153), `tools/ztest` and `proc.zrl` (id:z0130 to id:z0140), and id:z0157 follow-ups (id:z0158 to id:z0161).
2. `main`: standalone work, known-gap probes, and default-mode safety fixes (id:z0100, id:z0101, id:z0135, and generic tools/diagnostics/benchmarks).
3. `provenance`: the provenance and liveness hardening series (`+safety` tasks numbered B1 to B4, id:z0047 onward, and precision tasks that serve it).
Both code branches (`testinfra`, `provenance`) stay open until their respective series is reviewed before merging into `main`.

**Priority (2026-11-06, the maintainer):**
The provenance hardening series is paused for the test-efficiency series (`+testinfra`), which goes first because every later task pays for testing on 4-vCPU machines. Critical default-mode drop-glue safety fixes on `main` (id:z0162 and id:z0165) are completed and archived in `completed.tm.md`. Active execution proceeds in the `+testinfra` series starting at id:z0158. Model tags (`+AI-D`, `+AI-G`) and commit conventions follow `AGENTS.md`.

**The `testinfra` section's notes (its heading until 2026-11-12: "`testinfra` Branch: Test Efficiency & Runner Series (Active Priority)"):**

Active priority series to reduce verification runtimes. Order of execution:
1. Differential optimizations: id:z0158 (front-end loop forks), id:z0159 (on-demand stdlib drop lowering), id:z0160 (lowering drop flag), id:z0161 (generic fn enum variant member), id:z0114 (rejection differential caching).
2. Harness portability and bash removal: id:z0151, id:z0152, id:z0153, id:z0146, id:z0147, id:z0145.
3. Process management and runner: id:z0130 to id:z0140 (`proc.zrl`, `ztest`, retiring `test.sh` pool).
4. Result caching, parallel execution, and test reduction: id:z0123, id:z0113, id:z0109, id:z0110, id:z0107, id:z0125.

**Tier selection frozen (the maintainer, 2026-11-07):** the tier selection is frozen as it is: no new rows or rules; a reported miss is fixed by widening a row, and a path it does not list keeps selecting everything. A selection miss costs time only, since `make test` before a commit is the backstop; nearly every defect the series found was in code that decides what not to run.

**`main` merged in (the maintainer, 2026-11-10):** `main` up to git:97df9b6 (id:z0162's drop lookup, id:z0165, the branch rule in `AGENTS.md`) is merged into `testinfra` in git:4ce794e. id:z0135, a `main` task, is not on this branch until it lands and is merged again; id:z0131 and id:z0133 depend on it. Before starting a task that needs a `main` commit, check `git merge-base --is-ancestor <sha> testinfra`; if the commit is missing, stop and ask the maintainer for another merge.

**`main` merged in again (the maintainer, 2026-11-10):** `main` up to git:215ff53 (the `tm sweep`/`tm sync` and `.taskmarkrc` wording in `AGENTS.md`) is merged into `testinfra` in git:d483b03.

**What `make preflight-changed` measures on this branch (the maintainer, 2026-11-10):** with no `PREFLIGHT_BASE`, its base is the merge base with `main` (id:z0166), so a run covers the whole series, not one task: at git:fa097e0, 47 mutations and a 408 s differential, against 5 and 279 s for one task's commit. Every such run reports `2 newly refused`: probe `422_generic_null_cast_param_named_struct.zrl`, once whole-program and once under zbuild, the hole git:8ff8720 closed on this branch (id:z0157, B2). That is expected until the series merges into `main`, where the hole is still open; the maintainer chose to close it there by that merge, not by a port. A completion note cites it as such; a newly *accepted* program is still listed, whichever task it comes from. To measure one task alone, name the commit before it: `make preflight-changed PREFLIGHT_BASE=<sha>`.

**Status (review, 2026-11-11, `testinfra` at git:acc583d):** of the order of execution above, step 1 is done except id:z0114's follow-up (its checks D1 to D7, then a review), and step 2 is done (id:z0144 to id:z0147, id:z0151 to id:z0153). Step 3 has id:z0130 done; id:z0136 is ready (no dependency); id:z0131 and id:z0133 wait for id:z0135, a `main` task with no commit yet, and through them id:z0138 to id:z0140. Step 4 has id:z0123 ready; id:z0113 follows it; id:z0109, id:z0110 and id:z0125 are written in `ztest` after id:z0138 (id:z0117, decision 6). "Starting at id:z0158" in **Priority** above is history: the next tasks are id:z0114's follow-up, id:z0136 and id:z0123. `testinfra` is 43 commits ahead of `main` and lacks 12 of its commits (`git log testinfra..main`: the `?` and `defer` lowering fixes, the vecclone series, the `SECURITY.md` rule in `AGENTS.md`); another merge is the maintainer's decision. Not pushed from this machine (`hom` unreachable): `testinfra` git:acc583d and the `tasks` commits after `hom/tasks`.

**Order from here (review, 2026-11-11, agreed by the maintainer):** what the series has learned is that the work made cheaper pays on every run and cannot go stale (id:z0157 and id:z0158 took each side of the differential from 305 s to 127 s), while each mechanism that decides what not to run has had defects (the stamp: four fixes, then removed; the tiers: frozen; id:z0114's cache: R4). So: (1) id:z0114's follow-up (D1 to D7) and its review; (2) id:z0184, the measurement of the front end's remaining per-program cost, before any further cache; (3) id:z0136, then id:z0131 and id:z0132, which no longer wait for id:z0135 (their syscalls stay in `proc.zrl`, outside the `src/` closure), then id:z0137; (4) id:z0123, then id:z0113, decided with id:z0184's answer in hand; (5) id:z0133 and id:z0134, the two `rt/` check-ins, then id:z0138 to id:z0140; (6) id:z0109, id:z0110 and id:z0125 in `ztest`; id:z0107 last. `testinfra` merges into `main` at milestones, not only at the series' end: every branch pays for testing, and a fix made here (probe 422's hole) otherwise stays open on `main`. The first such merge takes the branch up to git:3bfec60; id:z0114's cache (git:acc583d) follows when its follow-up is reviewed.

**`testinfra` merged into `main`, first part (2026-11-12, asked by the maintainer):** git:906265f on `main` merges the branch up to git:3bfec60 (id:z0104 to id:z0161 as far as they are done, id:z0144 to id:z0147, id:z0151 to id:z0153, id:z0130). The seven per-script stage0-c `#!/bin/sh` commits of id:z0146 are squashed into git:c29d500, and the three commits after them were replayed, so five shas changed: `113209a` to `c29d500`, `b1bc937` to `578fa80`, `33fffd1` to `62dc3fc`, `575dfe7` to `3bfec60`, and id:z0114's cache `5a05bbb` to `cb6f3e4`; the task files now cite the new ones, and the tree at git:3bfec60 is identical to the old tip's (`git rev-parse 3bfec60^{tree}` equals the old `575dfe7^{tree}`). The old history is kept at the local branch `testinfra-pre-squash`. Conflicts were in recorded figures only (line, `unsafe` and probe counts in `README.md`, `doc/SAFETY.md` and `doc/spec/unsafe_policy.md`; seven corpus ZIL hashes that changed on both sides) and were recomputed from the merged tree. Checked on git:906265f: `make test`: `Total: 3263 run, 3263 passed, 0 failed, 94 skipped (115.8s)`; `make preflight-changed PREFLIGHT_BASE=cc932fe`: rc 0, `All mutations caught.`, `PASS — a clean copy of the tree builds with the default rules, and the compiler reproduces itself.`, `Total: 1189 run, 1189 passed, 0 failed, 0 skipped (44.7s)`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 2 newly refused, of 69145 programs against cc932fe0d83ae102a2eff77757582c6b3a0cd074` (probe 422, whole-program and zbuild: the hole this merge closes on `main`). `testinfra` is now `main` plus git:acc583d, so the **Status** paragraph's "43 commits ahead" and "lacks 12" are history, and so is the note under **What `make preflight-changed` measures** that every run reports `2 newly refused`: against the new `main` it reports none. `hom/testinfra` still holds the old history: publishing the branch needs a forced update, which is the maintainer's.

**Speed so far (review, 2026-11-13, at the maintainer's request; `testinfra` at git:6122499; AMD Ryzen 7 3700X, 16 threads; "4 CPUs" is `taskset -c 0-3` with `TR_JOBS=4 MUTATION_JOBS=4`):** before is id:z0120's profile (2026-11-07, git:fa097e0's era) unless named.

| What                                         | Before            | Now                                   |
| -------------------------------------------- | ----------------- | ------------------------------------- |
| `make test`, 16 threads                      | 230–238 s         | 114.6–117.6 s (about 2×)              |
| `make test`, 4 CPUs                          | 437.6 s           | 207.8 s (2.1×)                        |
| `mutation-self-test`, 4 CPUs                 | 358.7 s           | 118.6 s (id:z0156)                    |
| `preflight-changed`, a checker file changed  | 823 s             | 483 s, 16 threads (1.7×)              |
| the same, 4 CPUs                             | not measured      | 591 s                                 |
| its rejection differential                   | 625 s             | 252 s, 16 threads; 403 s, 4 CPUs      |
| `make test-changed`, a doc-only change       | the whole suite   | about 15 s (id:z0115, id:z0141)       |

**Commands:** `taskset -c 0-3 make test TR_JOBS=4 MUTATION_JOBS=4`: `Total: 3269 run, 3269 passed, 0 failed, 94 skipped (207.8s)`. The preflight runs are id:z0120's method: a scratch worktree (`build/rv/wt`) at git:6122499 with one comment line committed in `src/check_zir.zrl`, then `make`, then `REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=6122499` (and on 4 CPUs). Wall: 483 s and 591 s. `build/preflight-timings.tsv` on 4 CPUs: `reject-diff` 403, `mutation` 98, `selfhost` 98 (alongside mutation), `checked` 89, `calibrate` 1. The differential: `base verdicts: fresh (no cache); base front end 113 s` (185 s on 4 CPUs), `[PASS] reject-diff: 0 newly accepted ..., 0 newly refused, of 69145 programs`. Both runs exited 2, with two failures that do not change the times. `safety-figures` failed because the scratch comment adds a compiler line. `runner-output` failed in the checked suite because `preflight-changed` does not build `build/ztest`: check-in id:0f0vv finding 10, fixed by id:s6mg6. Every step still ran.

**Not comparable one-to-one:** `make test` ran 3,415 items then and 3,269 now; the tiers moved some items. 25 mutations targeted `check_zir.zrl` here; the number of z0120's run is not recorded.

**Expected from the rest of the series:** little more wall time from the runner itself. Z2c to Z2e (id:z0138 to id:z0140) are about portability, and should match `test.sh`'s times. id:z0139 saves about 10 ms of dispatch per per-file test (id:z0105), a few seconds a run. The rest is unmeasured: id:z0109 (scheduling and the preflight steps side by side), id:mrzb3 (the verifier's cost on `continue` in a match arm; the `stdlib` case is already taken by id:87kcw), id:z0113 (a result cache, undecided), and id:z0184's routes (a), about 28% of the differential's front end, and (c), under 17%, both to be re-measured. A cache hit for the differential's base side (id:z0114) saves 32–34% of a rerun on an unchanged base; the runs above were uncached.

**`testinfra` merged into `main` at milestone Z2b (2026-11-13, by the maintainer; prepared in id:9nnvq):** `main` was fast-forwarded from git:c907824 to git:0e9a752, the 14 commits of id:87kcw, id:z0136, id:z0131, id:z0132, id:q8rsf, id:pnx9h, id:655rf, id:z0137, id:0f0vv, id:bekxx, id:trx5h, id:ppvzh, id:dcxxy and id:s6mg6. Nothing was squashed and no sha changed, so the citations in the task files stand, and `testinfra` equals `main` with nothing to rebuild. Checked on git:0e9a752: `make test`: `Total: 3274 run, 3274 passed, 0 failed, 94 skipped (120.4s)` (id:s6mg6 C4, the same commit); `REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=c907824`: rc 0, `No mutation targets a changed file (14 commit(s) and the working tree since c907824).`, `PASS — a clean copy of the tree builds with the default rules, and the compiler reproduces itself.`, `reject-diff: base verdicts: fresh (no cache); base front end 132 s`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69145 programs against c9078246fabe77042603b14ec860a1238e3093a5`, `Total: 1195 run, 1195 passed, 0 failed, 0 skipped (46.3s)`. The host-specific `bench/` files the run wrote were deleted. The fuzz record (`bench/fuzz/README.md`) is stale on `main` (`stdlib/` and `tools/` changed). The default runner is still `test.sh`.

**Open soundness holes on `main`, then the provenance series (2026-11-14, the maintainer's request):** with the `testinfra` series paused into `future.tm.md` (its remaining tasks are the runner rewrite, test-path portability and conveniences, with no defect among them), the queue after id:z0135 is the six open soundness holes on `main` (id:z0183, id:z0180, id:z0100, id:z0101, id:z0176, id:z0175), then the whole provenance series, then the ZIL series. Each moved task's payload says why. The `provenance` branch (tip git:a6bd53a) is 18 commits ahead of `main` and 90 behind it; the maintainer chose to merge `main` into it (id:0m61c), not to rebuild it, after the six fixes land.

**The provenance series (its notes in `future.tm.md` until 2026-11-14, as they stood):**

Provenance and liveness hardening series (`+safety` B1 to B4). Paused until the test-efficiency series finishes:
1. Closure summaries and environments: id:z0093, id:z0094, id:z0096, id:z0097.
2. Value precision & compiler refactoring: id:z0087 (integers from collections), id:z0086 (literals), id:z0089 (`exh_expand_or`), id:z0090 (`zbuild` manifest).
3. Core provenance rules and diagnostics: id:z0073 (raw pointer decision), id:z0011 (borrows/stores decl check), id:z0044 (local field liveness), id:z0066 (diagnostics), id:z0065 (parallel checking), id:z0074 (differential review), id:z0012 (retirement of old passes).
4. Post-series audits: id:z0045 (reference carrier through phi/let), id:z0017 (safe store-grid twins).

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer). Stop for review after each `+safety` check-in.
