# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

- [x] +docs +AI-G @main `AGENTS.md`: the queue is one ordered list, with no `## Now` and `## Next` headings id:m9hjt
    > **Created:** 2026-11-14
    > **Branch:** `main`
    > **Placed:** at the top of the queue: a rule fix of under a session with no dependency.
    > **Completed:** 2026-11-14 git:f7d5617

    - **Why (the maintainer, 2026-11-14):** the split between `## Now` (about ten tasks) and `## Next` was a cut by count. It says nothing position does not already say, and promoting a task from `## Next` became a step that blocked sessions. The queue becomes one list in `active.tm.md` ("scheduled, in this order"); `future.tm.md` keeps work that is paused or not scheduled. Who may reorder or promote is unchanged.
    - **Do, in `AGENTS.md` on `main` (one commit):**
      1. "The queue." bullet: replace `` `active.tm.md` is one ordered list: `## Now` (about ten tasks, ready or made ready by the tasks above them) and `## Next` (later, in order). `` with `` `active.tm.md` is one ordered list, top to bottom, under no headings but **Sprint notes** at its end. ``, and `` the first open task in `## Now` whose `` with `` the first open task whose ``.
      2. "Placing a new task." bullet: `` goes at the top of `## Now` `` becomes `` goes at the top of `active.tm.md` ``, and `` promoting from `## Next` or `future.tm.md` `` becomes `` promoting from `future.tm.md` ``.
      3. Nothing else: `rg -n 'Now|Next' AGENTS.md CONTRIBUTING.md doc/` afterwards names no queue heading.
    - **Do, on the `tasks` branch (a task commit of its own, after the code commit):** delete the `## Now` and `## Next` lines of `active.tm.md` and the blank line after each; move no task.
    - **Checks:** C1 `rg -n '## Now|## Next' AGENTS.md CONTRIBUTING.md doc/developer_guide.md` prints nothing, and `grep -c '^## ' doc/tasks/active.tm.md` prints `1` (Sprint notes). C2 `tm validate doc/tasks/*.tm.md` passes and `tm next` shows the same task before and after the heading deletion (quote both). C3 `git -C doc/tasks show --stat HEAD` changes only `active.tm.md`, with deletions only. C4 doc tier: `make test-changed BASE=HEAD~1`, its `Total:` quoted (no compiled code changes).
    - **Completion (generalist, 2026-11-14, git:f7d5617):** the "The queue." and "Placing a new task." bullets of `AGENTS.md` are reworded as the task says (one ordered list under no headings but Sprint notes; "the first open task whose"; "top of `active.tm.md`"; "promoting from `future.tm.md`"). The `## Now` and `## Next` lines and the blank line after each are deleted from `active.tm.md` in tasks commit a9530ae.
      - C1: `rg -n '## Now|## Next' AGENTS.md CONTRIBUTING.md doc/developer_guide.md` prints nothing; `grep -c '^## ' doc/tasks/active.tm.md` prints `1`. `rg -n 'Now|Next'` over the three files also names nothing.
      - C2: `tm validate *.tm.md` passes for all three files; `tm next` shows `[m9hjt]` before and after the deletion.
      - C3: not as stated. `git show --stat HEAD` of 96b8ec3 shows only `active.tm.md`, but with 11 insertions and 5 deletions, not deletions only. The 9 other inserted lines were the reviewing session's uncommitted edits in the shared worktree (the new task id:0m61c, and a changed line of the 2026-11-14 notes paragraph), which my `git add active.tm.md` committed with the heading deletion. Their content is intact; the commit just holds more than my change.
        - **Split (2026-11-14, the maintainer's request):** the old commit 96b8ec3, kept on the local branch `tasks-pre-split`, is now two: git:9e764f8 (the reviewing session's id:0m61c lines) and git:a9530ae (the heading deletion alone: `git show --numstat a9530ae` reports 0 lines added and 4 deleted). The rewritten tip's tree equals the old tip's (`git rev-parse HEAD^{tree} tasks-pre-split^{tree}` prints `e5d0d83` twice).
      - C4: `make test-changed BASE=HEAD` before the commit (the doc tier selected the whole suite): `Total: 3274 run, 3274 passed, 0 failed, 94 skipped (121.1s)`.
    - **Awaiting review:** re-run C1 to C3 (C3 as noted).

- [x] +docs +review +AI-D @main @checkin Review of the one-list queue rule in `AGENTS.md` id:kgv5s
    > **Created:** 2026-11-14
    > **Branch:** `main`
    > **Depends:** id:m9hjt
    > **Placed:** after id:m9hjt, the batch it reviews.
    > **Completed:** 2026-11-14 git:f7d5617

    - **Review:** re-run id:m9hjt C1 to C3; read the two `AGENTS.md` bullets whole for a sentence that still assumes two headings.
    - **Review (2026-11-14):** git:f7d5617 changes the two `AGENTS.md` bullets exactly as id:m9hjt's **Do** says (2 lines out, 2 in, nothing else in the commit); read whole, neither bullet still assumes two headings. Re-run: C1 `rg -n '## Now|## Next' AGENTS.md CONTRIBUTING.md doc/developer_guide.md` prints nothing, and `grep -c '^## ' doc/tasks/active.tm.md` prints `1`. C2 `tm validate *.tm.md`: three `[PASS]` lines; `tm next` shows `[kgv5s]`, the first open task. C3 holds after the split: `git show --numstat --format= a9530ae` prints `0    4    active.tm.md`. The commit that broke C3 was the reviewing session's edit in the shared worktree, not the task's; it is split (see id:m9hjt's C3). Nothing blocks.

- [x] +bootstrap +audit +AI-D @main id:z0135 Z0 stage1 accepts modules in the `src/` closure and builds some of their paths wrong
    > **Created:** 2026-11-07
    > **Context:** by id:z0117's measurement.
    > **Branch:** `main`
    > **Before:** id:z0131, id:z0133 (they edit closure modules).
    > **Completed:** 2026-11-14 git:e56548e

    - **Review (2026-11-11/12):** the header's **Before:** id:z0131 no longer holds: by the maintainer's decision on id:z0131 its syscalls go into `stdlib/proc.zrl`, which is outside the `src/` closure, so that task and id:z0132 start without this one. Whether id:z0133 needs it is asked on id:z0133. This task keeps its own reason: an edit to `src/` that reaches one of the paths stage1 builds wrong.

    - **Found (id:z0117, git:e932d51):** built by `build/zoril-stage1` and `build/zilc-stage1` (the `build/zilc-boot` pipeline, linked with `build/runtime.o` or `build/runtime-stage1.o`), `tests/stdlib/test_stdlib_fd.zrl` and `tests/stdlib/test_stdlib_io_result.zrl` segfault in `mem_raw.zrl`'s `zoril_allocator_alloc` (from `test_pipe_large_buffer`) and `arena_free` (from `Arena::drop` in `test_command_redirect_stdout`); built by `build/zoril` they exit 0. Separately, stage1 refuses a program in which two modules each define a private function of the same name (reproduction in id:z0117: `cannot access private function: helper`), which `build/zoril` accepts.
    - **Why it matters:** the stage1 constraint in `AGENTS.md` says the closure "may use only what the pinned stage1 accepts". Accepting is not enough if stage1 builds an accepted function wrong. The self-hosting fixpoint covers only what `src/` reaches; an edit to `src/` that starts reaching one of these paths would get a generation-1 compiler built wrong, found (if at all) only by the fixpoint differing.
    - **Do:** reduce each crash to a minimal program against stage1 (`AGENTS.md`: before blaming a seed compiler, reproduce against it), and name what stage1 does differently (a language rule that changed since the pin, such as a drop or layout rule, or a stage1 bug). Find whether any function `src/` reaches today takes the same route (`--emit-deps`, and the generation-1 compiler run over the stdlib tests). Then propose, for the maintainer: a rule added to the stage1 constraint and `doc/bootstrap/two_stage.md` (for example "no two modules in the closure share a private name", and the construct stage1 builds wrong), and whether a check can enforce it (build the closure modules' own tests through stage1 in a gate). Fixing stage1 itself is a re-pin or a recorded backport, the maintainer's decision: stop and ask.
    - **Checks:** the minimal reproductions recorded here, each run against stage1 and `build/zoril`.
    - **Filed (2026-11-07):** both issues are in `KNOWN_ISSUES.md` §1 (the two `stage1` entries), the crash with its cause marked unknown. When this task names the cause, replace that sentence with it, and add the rule it proposes to the entry's **Workaround**.
    - **Found (2026-11-14, `main` at git:f7d5617; scratch `build/z135/`):** both crashes have one cause, two moves stage1 does not record, so the moved-from value's destructor runs again. Neither is a rule changed since the pin: `build/zoril`'s code for both is in the v0.1.0-alpha commit, and the stage1 snapshot predates it (stage1 has `src/lower_zir/match.zrl` where the release has `lower_match.zrl`).
    - **A `match` arm does not mark a by-value scrutinee moved.** `src/lower_zir/lower_match.zrl` calls `consume_place_if_move(&scrut_place)` after the guard when the scrutinee's type is not a reference or a `Box` (`pattern_peels_pointer`); stage1's `match.zrl` has no such call, so the scrutinee's drop flag stays set and `match e { E.A(s) => s, .. }` drops the payload with `e` at the exit. Reproduction (`build/z135/m1.zrl`; `S` counts its drops; exit 1 is right):
    ```zoril
    struct S { p: *mut u8 }
    impl Drop for S { fn drop(self: S) { unsafe { *self.p = *self.p + 1 as u8; } } }
    enum E { A(S), B }
    fn take(e: E) -> S {
        return match e { E.A(s) => s, E.B => { return S { p: 0 as *mut u8 }; }, };
    }
    fn main() -> i32 {
        let mut n = 0 as u8;
        let np = &mut n as *mut u8;
        { let s = take(E.A(S { p: np })); }
        return n as i32;
    }
    ```
    - **Result:** stage1 pipeline (`build/zoril-stage1` → `build/zilc-stage1` → qbe/as/ld with `build/runtime.o`): exit 2; `build/zoril` → `build/zilc`, same steps: exit 1.
    - **A by-value `self` receiver is not marked moved.** With `struct W { s: S }`, `impl W { fn take(self: W) -> S { return self.s; } }` and `fn mk(p: *mut u8) -> W`, the same `main` shape gives, stage1 / `build/zoril`: `mk(np).take()` 2 / 1 (`m2`); `let w = mk(np); w.take()` 2 / 1 (`m4`); `free_take(mk(np))` with `fn free_take(w: W) -> S` 1 / 1 (`m3`); `let w = mk(np); free_take(w)` 1 / 1 (`m5`); `W.take(mk(np))` 1 / 1 (`m6`). Only the method-call receiver is missed.
    - **How the tests reach it:** `Result.unwrap` takes both routes: `Arena.new(65536).unwrap()` frees the `Arena` inside `unwrap` (route 1) and the caller frees it again (`gdb`, a breakpoint on `arena_free`: `Result_TArenaError6unwrapE` then `main`; `build/zoril`: `main` only). `test_command_redirect_stdout` then faults reading the unmapped header in `arena_free`; `test_pipe_large_buffer` allocates from the freed arena (`zoril_allocator_alloc`). `match Arena.new(65536) { Ok(a) => a, .. }` alone also crashes (`r5`).
    - **What `src/` reaches (the compiler stage1 builds):** built by the stage1 pipeline from `src/main.zrl` (`build/z135/gen1`, 36 s), it links three destructors with a body: `File` (`f45`), `Arena` (`f65`) and `FileLock` (`f1653`). `Arena`'s and `FileLock`'s are not called on these routes (`src/` names neither type; no type in the closure holds one; `acquire_file_lock` has no such `match`). `File`'s is, in `read_file_raw` (route 1, `match os_linux::open_file(..) { Ok(file) => file, .. }`), `write_file` and `append_file` (route 1 and route 2, `f.close()`), all in `stdlib/file.zrl`. Measured with `gdb` (`catch syscall close`, printing the result) while compiling a three-line program importing `core.zrl` and `vec.zrl`: generation 1 makes 29 closes that succeed and 9 that return `-9` (`EBADF`); `build/zoril` makes 29 and none. Harmless today only because nothing is opened between the two closes; one `open` between them would close an unrelated descriptor. The 277 `.unwrap()`/`.expect()`/`.ok()`/`.err()` calls in `src/` take route 2 too, on types with no destructor.
    - **Private-name refusal:** reproduced (`build/z135/priv/`, the id:z0117 shape): stage1 `mb.zrl:2:41: error: cannot access private function: helper`; `build/zoril` accepts, exit 0. No two modules of today's closure (66 files, `--emit-deps` into `build/closure.txt`) share a private top-level function name (`awk` over `^(unsafe )?fn` per file: 0 shared).
    - **A backport, tried (route 1 only):** in a scratch copy of `bootstrap/stage1/` (`build/z135/s1fix/`), after the guard in `src/lower_zir/match.zrl`'s arm loop:
    ```zoril
    let scrut_tag = self.get_type_tag(scrut_ty);
    if !(scrut_tag == ILTYPE_PTR || scrut_tag == ILTYPE_PTRMUT || scrut_tag == ILTYPE_BOXED || scrut_tag == ILTYPE_BOXEDMUT) {
        self.consume_place_if_move(&scrut_place);
    }
    ```
    - **Result:** built by stage0-c with no warning. With it: `m1` exit 1, `r5` 0, `test_stdlib_fd` 0; `r7` (`.unwrap()`) and `test_stdlib_io_result` still crash, now both frees in `main` (route 2). Route 2's patch is not written: the receiver path in stage1's `expr.zrl` is not the tuple-argument loop that consumes ordinary arguments.
    - **Proposal for the maintainer:** id:gsa2r.
    - **Completion:** the cause is named and both reproductions are recorded above with their results under stage1 and `build/zoril` (the task's one check). `KNOWN_ISSUES.md` §1's entry now names the cause, what `src/` reaches, and the rule as its **Workaround** (git:e56548e). Doc tier after the edit: `make test-changed BASE=HEAD`: `Total: 124 run, 124 passed, 0 failed, 0 skipped (15.3s)`. No compiled code changed, so no `make test` or `make preflight-changed`. Re-pinning or backporting is the maintainer's, asked in id:gsa2r; nothing in `bootstrap/stage1/` changed.

- [x] +bootstrap +decision +AI-D @main Stage1 drops a value twice after a match arm or a by-value self moves it: backport, re-pin, or keep the rule id:gsa2r
    > **Created:** 2026-11-14
    > **Branch:** `main`
    > **Placed:** after id:z0135, which found it. Blocks no task: today's closure takes the routes only on `File`, with a harmless second `close`.
    > **Completed:** 2026-11-14 git:e56548e

    - **What:** id:z0135 found two moves stage1 does not record (a `match` arm on a by-value scrutinee, and a by-value `self` method receiver), so a value moved either way is dropped twice in what stage1 builds. In the compiler stage1 builds from `src/`, this happens only on `File` (`read_file_raw`, `write_file`, `append_file`), as a second `close` that fails with `EBADF`. Details and reproductions are on id:z0135.
    - **Options:**
      - (a) A recorded backport (`doc/bootstrap/two_stage.md` §3) of both fixes. Route 1's is tried (7 lines in stage1's `src/lower_zir/match.zrl`, on id:z0135): it fixes `m1`, `r5` and `test_stdlib_fd`. Route 2's is not yet written. Done when every `tests/stdlib/` test of a closure module, and `test_stdlib_fd` and `test_stdlib_io_result`, exit 0 through the stage1 pipeline, and generation 1 makes no `EBADF` close.
      - (b) A re-pin of stage1 to a later `main`, which has both fixes. Larger: everything since the snapshot comes with it.
      - (c) Keep stage1 and make the rule part of the stage1 constraint (`AGENTS.md`, `doc/bootstrap/two_stage.md`): in the closure, a value whose type has a destructor is not moved out of an enum payload (`match`, `unwrap`, `expect`, `ok`, `err`) and gets no `x.method()` call with a by-value `self` (write `Type.method(x)`). Then rewrite the three `File` functions so they follow it.
    - **Either way:** add the private-name rule ("no two modules in the closure share a private top-level function name"; 0 shared today) to the stage1 constraint, with a check: a short POSIX `awk` script over `--emit-deps`'s list, run as a gate.
    - **Recommendation:** (a). Rule (c) is hard to check by machine (it depends on which types have destructors, through generics), and the hazard grows with every `Option`/`Result` of a type with a destructor that the closure gains. The backport is small, and stage0-c builds it without a warning.
    - **Who:** the maintainer decides. The rule text in `AGENTS.md` is a rule change, and a backport touches `bootstrap/stage1/`, which only a re-pin or a recorded backport may change.
    - **Decision (the maintainer, 2026-11-14):** (a), the backport: id:jhy7v, after the open soundness holes on `main`. The private-name rule and its gate: id:azqvx. The maintainer asked whether a re-pin (b) would let `src/` be written in more idiomatic Zoril; the answer is with the maintainer (2026-11-14) and decides nothing here.

- [x] +docs +bootstrap +AI-G @main doc/bootstrap/two_stage.md says the stage1 snapshot is the pinned release's src/, which it is not id:sydrz
    > **Created:** 2026-11-14
    > **Branch:** `main`
    > **Placed:** at the top of the queue: a documentation fix of under a session with no dependency.
    > **Completed:** 2026-11-14 git:f684eaf

    - **Completion:** C1 `diff -rq bootstrap/stage1/src build/z135/rel/src` gave 25 `differ` lines and 18 `Only in` lines; `.zrl` line counts 31434 and 46769. C2 the `rg -n` command printed nothing. C3 `make test-changed BASE=HEAD~1` (run after the last edit): `Total: 3274 run, 3274 passed, 0 failed, 94 skipped (120.2s)`. `bootstrap/stage1/README.md` was edited (prose); the gate run passed with it.

    - **Found (2026-11-14, a reviewing session):** `bootstrap/stage1/src/` is not the `src/` of the release `bootstrap/stage1/PIN` names. `git archive v0.1.0-alpha src | tar -x -C build/z135/rel` and `diff -rq bootstrap/stage1/src build/z135/rel/src` report 25 files that differ and 18 on one side only (stage1 has `lower/`, `lower.zrl`, `lower_all.zrl`, `lower_zir/match.zrl`; the release has `driver/`, `parser/`, `fmt/`, `lower_zir/lower_match.zrl`, `il_typecheck.zrl` and others); `cat` over the `.zrl` files: 31,434 lines against 46,769. The repository's history starts at the release commit, so no commit in it is the snapshot's source.
    - **Do:** correct the sentences that say otherwise, and nothing else: `AGENTS.md` (the **stage1** bullet: "a snapshot of `src/` ... at the commit in `bootstrap/stage1/PIN`"), `doc/bootstrap/two_stage.md` (§1 or wherever `PIN` is described, and §4's "the snapshot's source, which is today's `src/` and already complies"), and `bootstrap/stage1/README.md` if it says the same. Say what is true: the snapshot is an older `src/`, ported to the stage0-C dialect, that shipped with the release `PIN` names; it is not that release's `src/`. Editing `bootstrap/stage1/README.md` is prose, not the snapshot's code; if a gate treats the directory as frozen, leave that file and say so.
    - **Checks:** C1 the two `diff -rq` and line-count commands above reproduce `25` differing, `18` one-sided, `31434` and `46769` (quote them). C2 `rg -n 'commit in .bootstrap/stage1/PIN|today.s .src/. and already complies' AGENTS.md doc/bootstrap/` prints nothing. C3 doc tier: `make test-changed BASE=HEAD~1`, its `Total:` quoted.

- [x] +tests +bootstrap +AI-G @main A gate refuses two modules of the src/ closure that define a private function of the same name id:azqvx
    > **Created:** 2026-11-14
    > **Branch:** `main`
    > **Placed:** after id:sydrz: a rule check of under a session with no dependency. The maintainer agreed to the rule on 2026-11-14 (id:gsa2r).
    > **Completed:** 2026-11-14 git:b26ca47

    - **Completion:** C1 `sh scripts/check_closure_private_names.sh`: `[PASS] closure-private-names: 66 modules, no shared private function name`. C2 two scratch modules `build/z-azqvx/ma.zrl`, `mb.zrl` in a `--list` file: `[FAIL] closure-private-names: helper in build/z-azqvx/ma.zrl and build/z-azqvx/mb.zrl`, exit 1. C3 with the duplicate test changed to `count[n] > 99`, the same run printed `[PASS] closure-private-names: 2 modules, no shared private function name`. C4 with a logging `git` that exits 1 first on `PATH`, the gate printed `[PASS]` (66 modules) and the log file was never created. C5 `make test` (after the last edit): `Total: 3275 run, 3275 passed, 0 failed, 94 skipped (119.8s)`. The gate checks top-level column-0 `fn`/`unsafe fn` only (header comment says so). Also added a `scripts/test_tiers.tsv` row for the script.

    - **Why:** stage1 refuses a program in which two modules each define a private function of the same name (`cannot access private function: helper`; id:z0135), and `build/zoril` accepts it, so nothing in the default build notices until a fresh checkout fails to bootstrap. No two modules of today's closure share one (id:z0135: 0 of 66 files).
    - **Do:** `scripts/check_closure_private_names.sh`, POSIX `sh` and `awk`, no git: list the closure with `timeout -k 5s 30s build/zoril --emit-deps src/main.zrl -I stdlib=stdlib -I src -I build/gen -o <tmp>` (columns 1 and 2 of each line are module paths), or read the list from `--list FILE` (for C2). For each module, take the names of its top-level private functions (lines starting `fn ` or `unsafe fn `, not `pub`), and print `[FAIL] closure-private-names: <name> in <file> and <file>` for every name in two or more modules, then exit 1; otherwise `[PASS] closure-private-names: N modules, no shared private function name`. Add it as a gate in `scripts/test_plan.tsv`. Add one sentence to the stage1 constraint in `AGENTS.md`: no two modules in the closure define a private function of the same name, which the `closure-private-names` gate checks.
    - **Checks:** C1 the gate on the tree prints its `[PASS]` line (quote it). C2 planted: two scratch modules under `build/` (`ma.zrl`, `mb.zrl`, each with `fn helper(x: i32) -> bool`) in a `--list` file: the script prints one `[FAIL]` line naming both and exits 1. C3 take the duplicate test out of the `awk` and watch C2 print `[PASS]`. C4 with a `git` on `PATH` that logs its arguments and exits 1, the gate still passes and the log is empty. C5 `make test`, its `Total:` quoted.

- [ ] +review +AI-D @main @checkin Review of the stage1 documentation fix and the closure-private-names gate id:9y3ke
    > **Created:** 2026-11-14
    > **Branch:** `main`
    > **Depends:** id:sydrz, id:azqvx
    > **Placed:** after id:azqvx, the batch it reviews.

    - **Review:** re-run id:sydrz C1 to C2 and id:azqvx C1 to C4; read the new `AGENTS.md` sentence and the gate script whole (POSIX, no git, its header names what it does not check).

- [ ] +safety +tests +AI-D @main id:z0183 A struct holding a frame view is not pushed into the caller's `Vec`
    > **Created:** 2026-11-11
    > **Context:** by id:z0174's review.
    > **Branch:** `main`
    > **Check-in:** stop for review after it: a fix to a safety rule. Public by SECURITY.md's rule: the program has to take this shape (a public report, a `known_gap` probe).

    - **Found:** `out.push(H { s: s })` with `struct H { s: [u8] }` and `s` a view of a stack array of the callee is accepted, and the caller reads the dead frame (`bench/safety_matrix/probes/gap_79_struct_holding_frame_view_pushed.zrl`, `exit 77` where the frame held 42; recorded in git:cc612fe on `main`). The bare view, `out.push(s)` into a `Vec<[u8]>`, is refused (`region escape: a pointer to local stack storage is written to memory that outlives this function`). A `let h = H { s: s }; out.push(h);`, `resize(2, H { s: &buf })` and `extend_from_slice` of such a struct take the same route (probed on `vecclone` at git:ea007d4; `push` is independent of the `vecclone` series). `Option.Some(s)` pushed into a `Vec<Option<[u8]>>` also compiles (not read back).
    - **Route class:** a struct whose field is a frame view, moved into memory that outlives the frame; beside `gap_59`..`gap_61` and `gap_63` (class (K), owners holding frame views), which hold the views in a `Vec`.
    - **Do:** find why the push's store rule sees the bare slice and not the struct carrying it (`build/zoril -v` on `gap_79`, then the summary pass for a struct literal argument), and make the struct's field views count as the stored region; decide the same for an `Option`/enum payload (probe `Option.Some(s)` read back first). Flip `gap_79` to `compile_reject`, remove its Known gaps entry and its sentence in `doc/SAFETY.md` §6 (K); keep `gap_61`'s record as it is unless the fix reaches it.
    - **Checks:** C1 `gap_79` is `compile_reject` and `sh scripts/run_safety_matrix.sh` passes; C2 error tests under `tests/error_reporting/` for the struct push, the `let h` form, `resize` and `extend_from_slice` of the struct, and the enum payload if it is a hole, each with `// EXPECT:`; C3 take the fix out and watch them fail; C4 `scripts/check_reject_diff.sh` against the commit before the fix, every newly refused program listed with its reason, none newly accepted; C5 a program that pushes a struct holding a view of a caller-owned or arena buffer is still accepted; C6 `make test`, `make preflight-changed`, `rm build/zoril && make` without a warning, each `Total:` quoted.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md`, with the five other open soundness holes on `main`, ahead of the provenance and ZIL series: each is a program `main` accepts and should refuse (or a drop it skips), one session-sized fix. Order among them: the reads of a dead frame first (id:z0183, id:z0180), then the `fn`-value faults (id:z0100, id:z0101), then the skipped drop (id:z0176) and the unchecked bound (id:z0175). Any "after the `vecclone` series merges" note above is met: the series is on `main`, with gap_76 to gap_79 in `bench/safety_matrix/probes/`.

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md`, with the five other open soundness holes on `main`, ahead of the provenance and ZIL series: each is a program `main` accepts and should refuse (or a drop it skips), one session-sized fix. Order among them: the reads of a dead frame first (id:z0183, id:z0180), then the `fn`-value faults (id:z0100, id:z0101), then the skipped drop (id:z0176) and the unchecked bound (id:z0175). Any "after the `vecclone` series merges" note above is met: the series is on `main`, with gap_76 to gap_79 in `bench/safety_matrix/probes/`.

- [ ] +safety +tests +AI-D @main id:z0100 A generic instance made into a `fn` value is lowered, not dropped
    > **Created:** 2026-11-06
    > **Branch:** `main`
    > **Found by:** id:z0092's review (a sibling-route probe crashed).
    > **Check-in:** stop for review after it: a fix to a safety rule. Independent of the provenance series; a hole in the default mode, reachable from safe code, so it goes beside id:z0095.

    - **Now:** a generic function's instance named with type arguments and not called (`id::<i32>` with `fn id<T>(x: T) -> T`) type-checks as a `fn` value, but lowering emits nothing for it. `let f: fn(i32) -> i32 = id::<i32>; return f(3) - 3;` allocates `f`'s slot and never writes it (the ZIL has `alloc` and then the `call_ptr`, with no store between them), so the call jumps through stack garbage and faults (`bench/safety_matrix/probes/gap_66_generic_instance_as_fn_value_uninit.zrl`, exit 139). By site (`build/z92r/r_*.zrl`, `c3.zrl`, `c5.zrl`): a `let` with a `fn` type and a struct field (`H { f: id::<i32> }`) fault; an assignment (`f = id::<i32>;`) is dropped and `f` keeps its earlier closure (exit 43 where 3 was expected); an argument (`call(id::<i32>)`) gives "invalid ZIL (a compiler bug): an instruction names an operand that no value defines"; `return id::<i32>;` gives "control reaches end of non-void function without a return value"; `let f = id::<i32>;` gives "Failed to resolve callee". A non-generic `fn` item, a method value (`S::get`) and a generic instance chosen by the expected type are not this class: the last is refused, "unknown type `T`", at `let f: fn(i32) -> i32 = id;`.
    - **Do:** find where a turbofish path is lowered only as a callee (`build/zoril -v` on `gap_66`, then the lowering of a path expression with type arguments) and lower it as the instance's `FuncAddr` at every value site, through `ZirLowerer.fn_value` so id:z0095's check applies (a generic `unsafe fn` named with turbofish, `unsafe fn id<T>(p: T) -> T` as `id::<*i32>`, is accepted outside `unsafe` today only because the value is dropped: `build/z95r/b2.zrl`, from id:z0095's review), or refuse it in the type checker with a diagnostic if instantiating is out of scope; decide which and say why. Probe every site above, a generic method (`B.id::<i32>`, refused today: "type arguments are only accepted on a call or a struct literal here"), and the instance passed to a generic higher-order function. Flip `gap_66` to `accept` (exit 0) or `compile_reject`, and remove its Known gaps entry and the `doc/SAFETY.md` §6 class (L) (lettered (M) until id:z0095 closed the first (L)). `make test`, `make preflight-changed`, `sh scripts/run_safety_matrix.sh`.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md`, with the five other open soundness holes on `main`, ahead of the provenance and ZIL series: each is a program `main` accepts and should refuse (or a drop it skips), one session-sized fix. Order among them: the reads of a dead frame first (id:z0183, id:z0180), then the `fn`-value faults (id:z0100, id:z0101), then the skipped drop (id:z0176) and the unchecked bound (id:z0175). Any "after the `vecclone` series merges" note above is met: the series is on `main`, with gap_76 to gap_79 in `bench/safety_matrix/probes/`.

- [ ] +safety +tests +AI-D @main id:z0101 An `extern` function made into a `fn` value needs `unsafe`
    > **Created:** 2026-11-06
    > **Branch:** `main`
    > **Found by:** id:z0095 (its structural twin).
    > **Check-in:** stop for review after it: a fix to a safety rule. A hole in the default mode, reachable from safe code; beside id:z0095 and id:z0100.

    - **Now:** a bare `extern` declaration (`extern fn memset(p: *mut u8, c: i32, n: usize) -> *mut u8;`) named as a value converts to a plain `fn` type with no `unsafe`, and a call through the value is never marked, so safe code calls C with a forged pointer and faults (`bench/safety_matrix/probes/gap_67_extern_fn_as_fn_value.zrl`; `build/z95/x_extern_call.zrl`, exit 139). A direct call is refused ("call to extern function requires unsafe block"); id:z0095's check in `ZirLowerer.fn_value` does not reach it: a bare `extern` is not `is_unsafe` (an `unsafe extern fn` is, and is refused since id:z0095's review).
    - **Decide, then do:** refuse the conversion outside `unsafe` as id:z0095 does (one condition in `fn_value`), or refuse it everywhere: a plain `fn` value is called with the Zoril convention, two words and an environment argument, and an `extern` is a C symbol, which `extern "C" fn(..)` (the C function pointer, its call already `unsafe`) is the type for. Probe every conversion site, an exported (`is_export`) function, and an `extern` with `#[borrows]`/`#[stores]`; flip `gap_67` with its Known gaps entry and the `doc/SAFETY.md` §6 class (M) removed. `make test`, `make preflight-changed`, `sh scripts/run_safety_matrix.sh`.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md`, with the five other open soundness holes on `main`, ahead of the provenance and ZIL series: each is a program `main` accepts and should refuse (or a drop it skips), one session-sized fix. Order among them: the reads of a dead frame first (id:z0183, id:z0180), then the `fn`-value faults (id:z0100, id:z0101), then the skipped drop (id:z0176) and the unchecked bound (id:z0175). Any "after the `vecclone` series merges" note above is met: the series is on `main`, with gap_76 to gap_79 in `bench/safety_matrix/probes/`.

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md`, with the five other open soundness holes on `main`, ahead of the provenance and ZIL series: each is a program `main` accepts and should refuse (or a drop it skips), one session-sized fix. Order among them: the reads of a dead frame first (id:z0183, id:z0180), then the `fn`-value faults (id:z0100, id:z0101), then the skipped drop (id:z0176) and the unchecked bound (id:z0175). Any "after the `vecclone` series merges" note above is met: the series is on `main`, with gap_76 to gap_79 in `bench/safety_matrix/probes/`.

- [ ] +safety +types +AI-D @main id:z0175 A bound on an impl block or a method's type parameter is checked
    > **Created:** 2026-11-11
    > **Branch:** `main`
    > **After:** the `vecclone` series is merged (it may refuse programs the series' tests use).

    - **Found (2026-11-11, git:fc55a0a, scratch `build/p34/`):** `impl<T: Copy> W<T> { fn dup(self: &W<T>) -> i32 }` called on a `W<S>` with `S: Drop` compiles (`b_split_impl_drop.zrl`, exit 0), and so does `fn dup<U: Copy>(self: &W<T>, u: &U)` called with `&S` (`b_method_bound.zrl`). A free function's bound is checked, also through an unbounded generic caller (`b_fn_bound_drop.zrl`, `b_through_generic.zrl`: `error: type 'S' does not implement trait 'Copy'`).
    - **Do:** check both at the call as a free function's bound is checked; probe trait impls (`impl<T: Clone> Clone for Vec<T>` on a `Vec` of a non-`Clone` `T`) beside them. The rejection differential lists every program newly refused.
    - **Diagnostic (2026-11-11, id:z0173):** with the bound unchecked, `Vec.extend_from_slice` on a `T` with no `Clone` is refused only inside `vec.zrl` (`stdlib/vec.zrl:431:60: error: no field 'clone' on 'S'`). Once `impl<T: Clone>` bounds are checked at the call, move `extend_from_slice` and `resize` into such an impl so the user sees `type 'S' does not implement trait 'Clone'` at their call, and update `tests/error_reporting/err_extend_from_slice_no_clone.zrl`'s EXPECT.
    - **Checks:** C1 the two programs above refused with the free function's diagnostic (`tests/error_reporting/`, `// EXPECT:`); C2 take the check out and watch them compile; C3 `scripts/check_reject_diff.sh` against the base, every newly refused program listed with its reason; C4 `make test`, `make preflight-changed`, each `Total:` quoted.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md`, with the five other open soundness holes on `main`, ahead of the provenance and ZIL series: each is a program `main` accepts and should refuse (or a drop it skips), one session-sized fix. Order among them: the reads of a dead frame first (id:z0183, id:z0180), then the `fn`-value faults (id:z0100, id:z0101), then the skipped drop (id:z0176) and the unchecked bound (id:z0175). Any "after the `vecclone` series merges" note above is met: the series is on `main`, with gap_76 to gap_79 in `bench/safety_matrix/probes/`.

- [ ] +bootstrap +safety +AI-D @main Backport to stage1: a match arm and a by-value self receiver mark the value moved id:jhy7v
    > **Created:** 2026-11-14
    > **Branch:** `main`
    > **Placed:** after the open soundness holes on `main` (id:z0183 to id:z0175): the maintainer's decision (a) of id:gsa2r. Today's closure takes the routes only on `File`, with a harmless second `close`, so the holes go first.

    - **Do:** a recorded backport (`doc/bootstrap/two_stage.md` §3) of both fixes into `bootstrap/stage1/src/`. Route 1 is written and tried (id:z0135: seven lines after the guard in `lower_zir/match.zrl`). Route 2 is not: find where stage1's `lower_zir/expr.zrl` lowers a method call's receiver when the method takes `self` by value, and mark it moved as `src/` does (compare with `src/lower_zir/expr.zrl`'s method-call path, and with the tuple-argument loop that already consumes ordinary arguments). Both changes are the minimum in the stage0-C dialect. `bootstrap/stage1/PIN` is unchanged; record the backport in §3 beside the `.note.GNU-stack` entry, and remove the `KNOWN_ISSUES.md` §1 entry (git:e56548e).
    - **Checks:** C1 stage0-c builds the patched stage1 with no `warning:` (`make build/zoril-stage1` from a clean `build/`). C2 through the stage1 pipeline (id:z0135's `s1.sh`, recorded in the task text), `m1` and `m2`/`m4` exit 1 (one drop), and `tests/stdlib/test_stdlib_fd.zrl`, `tests/stdlib/test_stdlib_io_result.zrl` and every `tests/stdlib/` test of a closure module exit 0; quote each. C3 take each fix out and watch its reproduction exit 2. C4 the generation-1 compiler stage1 builds makes no `close` that returns `-9` while compiling id:z0135's three-line program (`gdb`, `catch syscall close`). C5 §3's verification: the candidate builds current `src/`, the fixpoint holds (`make preflight-changed`), `make test`, `make preflight`, each `Total:` quoted.

- [ ] +merge +AI-D @provenance Merge `main` into `provenance` before the series resumes id:0m61c
    > **Created:** 2026-11-14
    > **Branch:** `provenance`
    > **Depends:** id:z0175
    > **Placed:** before id:z0093, which it blocks: the series' first task starts from a branch that has `main`'s fixes.

    - **Decision (the maintainer, 2026-11-14):** `main` is merged into `provenance`, not the branch rebuilt on `main`: the branch is published (`hom/provenance`, `github/provenance` at git:a6bd53a) and the task files cite 14 of its 18 commits, so a rebuild would need a forced update and a sha remap for no gain. The merge waits for the six soundness fixes on `main` (id:z0183 to id:z0175 above), so it picks them up once.
    - **Do:** on `provenance`, `git merge main`. Resolve conflicts in recorded figures (`README.md`, `doc/SAFETY.md`, `doc/spec/unsafe_policy.md`, `corpus/zrl_whole_program_zil.sha256`) by recomputing them from the merged tree (`scripts/check_safety_figures.sh --density --print`, `scripts/check_safety_model.sh`, `UPDATE_GOLDEN=1 sh scripts/test_incremental.sh`), never by taking a side. A conflict in `src/` is resolved by reading both changes; list each in the completion note.
    - **Checks:** C1 `git merge-base --is-ancestor main provenance` succeeds and `git log -1 --format=%p provenance` names two parents. C2 `make test` on the merge commit, its `Total:` quoted. C3 `REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=<main at the merge>`, its `Total:`, `fresh (no cache)` and `reject-diff` lines quoted, and every newly accepted or refused program listed with its reason. C4 `sh scripts/run_safety_matrix.sh`: `Mismatches: 0`. C5 `git diff a6bd53a provenance --stat` against `git diff a6bd53a main --stat`: every file differing from `main`'s side is a conflict listed in the note.

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +safety +tests +AI-D @provenance id:z0096 A closure storing into a global, handed to a callee that calls it, is checked
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0092 (the store side of the rule's boundary).
    > **Check-in:** stop for review after it.
    > **After:** id:z0093, whose closure summary over `__env` gives the closure's store into a global an edge this task can carry through the callee.
    > **Before:** id:z0012, which deletes `check_fn_value`.

    - **Now:** `bench/safety_matrix/probes/gap_64_closure_global_store_via_fn_param.zrl`: `run(|| { G = r as *i32; })` with `fn run(f: fn()) { f(); }` and `r = &x` compiles with and without `--provenance`, and the global keeps a dead frame's address (exit 77). The closure body stores `Env` (not frame-bound) into a global; the unknown call through `f` in `run` records edges only into what its arguments reach, never a global, so `run`'s summary has none and the call to `run` checks nothing. The direct call `cl()` is refused by the old rules ("callee stashes local stack pointer via indirect call"); a `fn` item storing into a global cannot become a value (`check_fn_value` in `src/verify.zrl`), which id:z0012 has to carry over.
    - **Route class:** a closure passed as an argument to a callee that calls it (`gap_52`), here with a global destination. Probe the siblings: a `static mut` reached through a captured reference, a closure kept in a struct field, two levels of callers.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +precision +tests +AI-D @provenance id:z0097 An edge into a `fn` argument's environment does not make a `fn` item a global destination
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Found by:** id:z0092 (its accept probes).
    > **Depends:** id:z0092
    > **Before:** id:z0065: a higher-order function handed a local's address is common in user code. Accepts more: the rejection differential applies.

    - **Now:** an unknown call through a `fn` parameter `f` records store edges into `ParamContents(f)`, its environment (`os_unknown_call_effects`, the environment as argument K = ARGS.len). At a call that passes a `fn` item (`Static`, no environment), the edge's destination is the item's reach, `Static`, a global, so a frame address passed beside it is refused by the call store rule: `fn first(f: fn(&i32, &i32) -> &i32, a: &i32, b: &i32) -> &i32 { return f(a, b); }` called as `first(pick, &x, &y)` with locals, `walk(step, &x, n)`, `run(&m, &x)` with `m.f` a `fn` item (id:z0092's `build/z92/a_*.zrl`; the base compiler refuses them the same way). Inside the callee `os_unknown_arg` already reads a `Static` callee as adding no memory; the caller's edge mapping does not.
    - **Do:** decide whether an edge into the `ParamContents` of a `fn`-typed parameter maps, at the caller, to the environment of the value passed (`os_through` of its `O` without `Static`, as `os_unknown_arg` takes it) rather than to everything it reaches. A rule that removes destinations: the series rule's probes (a capturing closure passed in its place must still be refused, `gap_52`'s shapes), the store grid under `--provenance`, and `test_stdlib_iter.zrl`'s seven warnings read first to see whether they are this class.
    - **Found in id:z0092's review (2026-11-06):** the false global edge carries up through a summary. `fn apply<T>(f: fn(T) -> T, x: T) -> T { return f(x); }` and `fn via(p: &i32) -> &i32 { return apply::<&i32>(same, p); }`: `via`'s body is accepted, but its summary now stores `p` into a global (the edge into `ParamContents(f)` mapped to `same`, `Static`), so `main`'s `via(&x)` with a local is refused, "the callee stores an address of this frame into a global (call store rule)", one level above the `fn` item (`build/z92r/s_generic_hof.zrl`). A fix that maps the edge at the call must also keep it out of the caller's summary. The arena twins `f(&a, mk_vec, &mut v)` and `r(&a, mk_vec)` with a local arena are refused the same way (`build/z92r/s_param_vec.zrl`).
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

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
    > **Placed:** at the end of `## Next`: the maintainer starts the series after the current `testinfra` work. Nothing in `testinfra` depends on it. ZL4 changes the per-file runner, which `testinfra` rewrites (id:z0139), so the series waits for `testinfra` to merge into `main`.

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
