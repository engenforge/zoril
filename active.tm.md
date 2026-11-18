# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [x] +testinfra +AI-G @provenance `make preflight` runs the milestone figures check again, and the preflight self-test stubs it id:837pd
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Completed:** 2026-11-18 git:5c44f2b

    - **Placed:** at the top of `active.tm.md` by the check-in id:7kbpd: a rule fix of under a session with no dependency.
    - **Found by:** id:7kbpd. `5d8c6a9` (`Task: id:z0089`, an `+AI-G` session) removed the `check_safety_figures.sh --milestone` step from `scripts/preflight.sh` and rewrote the `make preflight` bullet of `AGENTS.md`, the Makefile help line and `doc/developer_guide.md` §3. That reverses the maintainer's decision of 2026-11-15 recorded in id:141h5 ("`make figures-check` runs it; `make preflight` runs it (the release bar)"), and z0089's own finding of 2026-11-17 said to wait for the maintainer's answer first. The edit left `doc/developer_guide.md:201` saying that `make preflight` "also runs `make figures-check`".
    - **Cause of the failure z0089 hit:** `scripts/test_preflight.sh` stubs every preflight step (`PREFLIGHT_SELFHOST`, `PREFLIGHT_DENSITY`, `PREFLIGHT_FUZZ`, `PREFLIGHT_FIGURES_REC`, ...) except `PREFLIGHT_FIGURES`, which `0b45934` (id:141h5) added. So its full-preflight cases ran the real milestone check, which fails by design whenever the figures are stale between milestones. The defect is the missing stub, not the step.
    - **Do:** revert `5d8c6a9` (`git revert`), then in `scripts/test_preflight.sh` export `PREFLIGHT_FIGURES="$tmp/stub_pass.sh"` beside `PREFLIGHT_FIGURES_REC`. If the maintainer decides instead to keep `5d8c6a9`, this task becomes only the fix of `doc/developer_guide.md:201`.
    - **Checks:**
      - C1: before the change, `grep -c FIGURES_CMD scripts/preflight.sh` prints `0`.
      - C2: after the revert, `grep -n 'FIGURES_CMD' scripts/preflight.sh` names the default `./scripts/check_safety_figures.sh --milestone` and its call; `git diff 5d8c6a9~1 -- AGENTS.md Makefile doc/developer_guide.md scripts/preflight.sh` prints nothing.
      - C3: `sh scripts/test_preflight.sh` passes while `sh scripts/check_safety_figures.sh --milestone` fails on this tree (quote one `[FAIL] safety-figures:` line); take the new stub line out and `sh scripts/test_preflight.sh` fails; quote both.
      - C4: `./scripts/test.sh --scenario preflight-selftest` passes; quote its `Total:` line.
      - C5: the doc tier: `make test-changed BASE=HEAD~1`, `Total:` line quoted.

    - **Decision (2026-11-18, the maintainer):** agents never run the documentation-figures checks (line counts, density, probe counts); only the maintainer runs them right before a release or at their discretion. Functional checks may run in `make preflight` at any time. So `5d8c6a9` stays: the revert and the stub are not done. Only the `doc/developer_guide.md:201` fix remains, plus `AGENTS.md` naming `make figures-check` as the release step.
    - **Completion:** `9fe102e`. C1 to C4: not run: nothing reverted and no stub added. C5: `make test-changed BASE=HEAD`: `Total: 3828 run, 3828 passed, 0 failed, 102 skipped (138.2s)`.

- [x] +testinfra +review +AI-D @provenance @checkin Review of the restored preflight figures step (id:837pd) id:yf17t
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:837pd
    > **Completed:** 2026-11-18 git:c125594

    - **Placed:** after id:837pd by the check-in id:7kbpd, to review it before the queue goes on.
    - **Checks:** re-run id:837pd's C2 and C3 (including the run with the stub taken out), and check that every `PREFLIGHT_*` command variable in `scripts/preflight.sh` has a stub in `scripts/test_preflight.sh` (`grep -o 'PREFLIGHT_[A-Z_]*:-' scripts/preflight.sh` against `grep -o 'PREFLIGHT_[A-Z_]*=' scripts/test_preflight.sh`), so that the next step added cannot make the self-test run the real thing.

    - **Review (2026-11-18), tree at `c125594` (the branch with `main` merged):**
      - **Queue:** re-read. 837pd ended as the maintainer decided: documentation-figure checks are never run by agents or by preflight, only by the maintainer before a release. The branch's own `5d8c6a9` and `9fe102e` were dropped for `main`'s `5c44f2b` (id:xh0jq), which makes the same change and adds the stub; their citations were remapped to `5c44f2b`. 837pd's C1 to C4 (revert, stub, stub removal) no longer apply.
      - **Checks re-run:** `grep -c FIGURES_CMD scripts/preflight.sh` prints `0`; the only figures step left is `PREFLIGHT_FIGURES_REC` (a record, no comparison with the docs). Every `PREFLIGHT_*:-` variable of `preflight.sh` (14) appears as a `PREFLIGHT_*=` in `test_preflight.sh`: `comm -23` of the two lists is empty. `sh scripts/test_preflight.sh`: 0 `[FAIL]` lines. `./scripts/test.sh --scenario preflight-selftest`: `Total: 2 run, 2 passed, 0 failed, 0 skipped (5.5s)`. `make test` on the merge: `Total: 3828 run, 3828 passed, 0 failed, 102 skipped (138.6s)`.
      - **Not run:** the stub-removal run (no step is left unstubbed to remove). `make preflight-changed` on the merge commit.
      - **Plan:** unchanged. No task added, moved, re-tagged or re-prioritized.

- [x] +precision +tests +AI-D @provenance A known closure call tells one capture from another: the summary keeps per-capture bits, mapped at the call to the environment struct's fields id:w17jf
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Depends:** id:mr6jm
    > **Completed:** 2026-11-17 git:e7e4fa9

    - **Found by:** id:mr6jm (its store grid run).
    - **Placed:** directly after id:mr6jm, a follow-up to it. Not a soundness hole: every cell it names is refused by the base too, so the maintainer may move it later in the series. `+AI-D`: the mapping from capture bits to environment fields, and whether field-insensitive sets can give a per-field read there, are decisions.

    - **Now (git:98a1efc):** with id:mr6jm, the store grid under `--provenance` still refuses 780 `closure_owned_capture` safe twins (`build/provenance/build/mr6jm/grid/work/twin_rejections.txt`): the `closure_local`, `elem_ref` and `ref_local` carriers, every path. Example `ref_local__direct__direct__closure_owned_capture__frame_ends.twin`: `let mut h = OwnedHolder { s: &dummy_seed, .. }` is moved into the closure, which does `h = OwnedHolder { s: routed, .. }` with `routed` a view of a parameter. The body leaves `h`'s own contents out of the `env` edge, but the summary states every capture as one `ParamContents(__env)`, so at the call the caller checks all the environment holds, `Frame(dummy_seed)` included: "the callee stores an address of this frame into a global (call store rule)".
    - **Do (lead (a) of id:mr6jm):** keep a closure's capture bits (`OriginSets.cap_bit`, past `__env`) in its summary rather than folding them (`os_fold_env`), and at a known closure call map capture `i` to what the creating frame stored in the environment struct's field for it (the struct value the `FuncAddr`'s env local was built from), falling back to all of `ParamContents(__env)` where that cannot be read. Decide first how the field is read with field-insensitive sets, and which capture alias belongs to which field.
    - **Checks:** the store grid under `--provenance` (0 unsafe accepted; the 780 twins counted by carrier), the test programs by `build/mr6jm/measure.sh`, probes of a holder's own frame address with another capture's `Param` view stored into it (accepted), and of a frame view held by one capture stored into another owned capture (refused), `make test`, `make preflight-changed`, the rejection differential.

    - **Decided (2026-11-17):** the lowering builds the environment as `E = Tuple(c0, c1, ..)` of plain locals, then `P = Ref(E)`, then `FuncAddr(f, P)` (`build_closure_env`, `lower_closure_expr`); the body loads capture `j` from `(*__env).j` in the same order (`load_captures`, `pending_cap_names` is the same `captures` slice), and `os_cap_bits` gives the `j`-th capture alias bit `e + 1 + j`. So field `j` is read through its source local `cj`, not through a per-field set: (1) the summary keeps the capture bits (`os_fold_env` deleted); (2) a known closure call passes, after `__env`, arguments up to parameter 62, read by `os_arg`: argument `e + 1 + j` is `Frame(cj)` when the environment is read field by field, else the environment as a whole (`ParamContents(e)` as before); (3) the `__env` argument also names every `cj`, so a store into a slot (target `ParamContents(e)`, which does not say which capture) reaches every element local; (4) field by field only when `os_known_envs` finds `E` built once of plain locals, `P` taken once and made into one closure, and every local holding the closure used only as a callee or copied into another such local (any other use: an argument, a capture of another closure, a return, a projection). Flow-insensitivity makes `cj` a superset of field `j`.
    - **Implemented, uncommitted on `stream/provenance` above git:98a1efc** at the time of writing. Scratch under `build/mr6jm/` (probes `p/u*.zrl`, `p/e*.zrl`, `p/w1.zrl`) and `build/w17/` (grid, measure).
    - **Probes** (base git:98a1efc = `build/mr6jm/zoril.new`): `w1` (the 780 shape) refused → accepted; `u5` (a parameter view moved into an owned holder while another capture holds a frame address) refused → accepted; `u8` (closure returns the parameter capture beside a frame capture) refused by the provenance rules → accepted by them (still refused by the old `region escape` rule); a1–a9, b1, b2 and t1 keep their verdicts; `u6`, `u7` refused by both. Assignment to a `Copy` capture is refused by the language ("the closure holds a copy of 'h'"), so a slot store goes only into a non-`Copy` capture.
    - **Safeguards taken out:** `build/mr6jm/nofield` (`known_tuple` always 0): `known_callee_closure_captures_apart_accepted.zrl` is refused at both calls ("into a global (call store rule)"). `build/mr6jm/noelig` (`env_of` set whatever the scan found): `known_callee_closure_handed_out_refused.zrl` loses its `store rule` refusal at `*out = cl(false, p)` (`p/e4.zrl`). `build/mr6jm/noslot` (the `__env` argument names no element local): no program found that it changes. A slot store into an owned capture is refused by the `env` edge; one into a capture holding a `&mut` names the capture's own bit as a target, which reaches `cj` anyway (`p/e5.zrl`); a `Copy` capture cannot be assigned (`p/e6.zrl`). Kept as a guard, and said so in §3.
    - **Expected results changed (origin goldens only):** `closure_env_summary.zrl` `store ParamContents(0) -> ParamContents(0)` → `store ParamContents(2) -> ParamContents(1)`; `closure_owned_capture_push.zrl` `... -> ParamContents(1)` → `... -> ParamContents(1) ParamContents(2)`; `closure_owned_capture_store_other.zrl` `store ParamContents(0) -> ParamContents(0) env` → `store ParamContents(2) -> ParamContents(0) ParamContents(1) env`; `closure_env_gap45.zrl` `w O={Frame(_3), Frame(a), Frame(w)}` → `w O={Frame(_3), Frame(a)}` (the closure stores what `s` holds through `r`, no longer the whole environment, `r`'s `Frame(w)` included; `*out = w.s` still refused by the store rule). No `EXPECT` changed.
    - **stage1:** `build/zoril-stage1` compiles `src/` with this change (`--emit-zil`, rc=0).

    - **Completion (2026-11-17), the work commit git:e7e4fa9 on `stream/provenance`** (above git:98a1efc; not yet on `provenance` or pushed). The checks the task names:
        - _The store grid under `--provenance`_ (`build/w17/grid`, compiler `build/w17/zoril.new` = git:e7e4fa9): **0 unsafe cells accepted** (`work/actual_names.txt` empty). Safe twins refused 4822, against id:mr6jm's 6182: 1360 accepted again, 0 newly refused. By destination, id:mr6jm / now: `closure_call_mut` 132 / 132, `closure_capture_mut` 1180 / 60, `closure_owned_capture` 780 / 540. The 540 by carrier: `closure_local` 480, `elem_ref` 30, `ref_local` 30. The `closure_local` ones are another class: the holder's field is a `fn` value, the closure stores the `fn` item `twin_fn` into it (refused in the body, "a value holding an address of this frame is stored into memory that outlives it (store rule)") and calls `h.s()` (unknown-call store rule): see id:z0097's subject, not read further here. The 60 `elem_ref`/`ref_local` and the 60 `closure_capture_mut` left were not read one by one. The modular step stopped as on every `--provenance` grid run (`store-grid-modular: 125 entr(ies) ... no longer hold`).
        - _The test programs_ (`build/w17/measure.sh`): 721 compile by default (720 at id:mr6jm, plus the new accepted test); warning programs 14, warnings 91; roots `src/main.zrl` 199, zbuild 21, zilc 0, zman 0: unchanged.
        - _Probes:_ a holder's own frame address with another capture's `Param` view stored into it: accepted (`known_callee_closure_captures_apart_accepted.zrl`, `p/w1.zrl`); a frame view held by one capture stored into another owned capture: refused in the body (`p/a1.zrl`, `closure_owned_capture_view_into_capture_refused.zrl`); the others and the safeguards taken out as recorded above.
        - _`make test`_ (after the last edit, before the commit, same tree): `Total: 3728 run, 3728 passed, 0 failed, 94 skipped (136.2s)`.
        - _`make preflight-changed` and the rejection differential:_ `PREFLIGHT_FIGURES=true REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=98a1efc`, rc=0: "All mutations caught."; the gen3/gen4 fixpoint; `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`; `reject-diff: base verdicts: fresh (no cache)` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69159 programs` (the rule acts only under `--provenance`; there it newly accepts the grid's 1360 twins, generated safe programs, not read one by one, and the probes and test above, which were read: none stores or returns a frame address); checked build `Total: 1417 run, 1417 passed, 0 failed, 0 skipped (110.9s)`; git group `Total: 8 run, 8 passed, 0 failed, 0 skipped (99.8s)`; "All performance thresholds within tolerance of baseline."; the `[MISSED]`/`[DETECTED]` record identical to id:mr6jm's run.
        - _`sh scripts/run_safety_matrix.sh`:_ `All probes complete: 473/519 passed. Mismatches: 0`. Sibling routes: the 93 `gap_*` probes under `--provenance`, git:98a1efc and git:e7e4fa9: the same verdict each.
    - **Stale:** `bench/fuzz/README.md`'s fuzz record (a change to `src/`). Milestone figures not touched.
    - **Check-in:** none: an `+AI-D` task, reviewed by the session that did it, with the reproducers and sibling routes above. The slot-store guard has no program that needs it (above); a reviewer may want to look for one.

- [x] +safety +tests +AI-D @provenance id:z0096 A closure storing into a global, handed to a callee that calls it, is checked
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Depends:** id:z0093
    > **Check-in:** stop for review after it.
    > **Completed:** 2026-11-17 git:b722b67

    - **Found by:** id:z0092 (the store side of the rule's boundary).

    - **Now:** `bench/safety_matrix/probes/gap_64_closure_global_store_via_fn_param.zrl`: `run(|| { G = r as *i32; })` with `fn run(f: fn()) { f(); }` and `r = &x` compiles with and without `--provenance`, and the global keeps a dead frame's address (exit 77). The closure body stores `Env` (not frame-bound) into a global; the unknown call through `f` in `run` records edges only into what its arguments reach, never a global, so `run`'s summary has none and the call to `run` checks nothing. The direct call `cl()` is refused by the old rules ("callee stashes local stack pointer via indirect call"); a `fn` item storing into a global cannot become a value (`check_fn_value` in `src/verify.zrl`), which id:z0012 has to carry over.
    - **Route class:** a closure passed as an argument to a callee that calls it (`gap_52`), here with a global destination. Probe the siblings: a `static mut` reached through a captured reference, a closure kept in a struct field, two levels of callers.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

    - **Decided (2026-11-17):** checked where the closure is made. A `FuncAddr(f, P)` with an environment whose closure value is not confined to calls through locals of the making body (id:w17jf's `env_of` 0: handed to a callee, put in a struct field, captured by another closure) may be called where no caller knows its environment. So `os_check_closure_value` applies the closure's summary edges whose value is what the environment reaches (`ParamAddr(e)`, `ParamContents(e)`, the capture bits) to the environment `P` names, as one value, with the moved-storage drop of id:mr6jm: a frame-bound value into a global is refused ("the closure made here stores an address of this frame into a global when it is called (closure rule)"), or into external memory the environment reaches ("... into memory that outlives it ..."), and every such edge is recorded as the making body's own (all passes, not only the rule pass), since a call of the closure anywhere is a store that body caused. Edges valued by a declared parameter stay with the call sites: `run(|q| { G = q as *i32; }, &x)` is already refused at `run`'s call (`build/z96/p/s7.zrl`, and the `fn` item form `s8.zrl`). A closure with no summary yet where it is made is refused if its environment holds a frame address. The alternative, a global edge from every argument at each unknown call through a `fn` value, was rejected: it would refuse every `apply(f, &local)` (an iterator's `for_each` over a local `Vec`).
    - **Work commits** on `stream/provenance` above git:e7e4fa9: git:b722b67 (the rule, tests, design note §3 _A closure made into a value_, the `gap_64` entry of `safety_model.md`); git:4cff970 and git:b584f41 (the new hole's probe `gap_94`, below).
    - **Probes** (`build/z96/p/`, base git:e7e4fa9): `g64` (gap_64), `s1` (two callers), `s2` (struct field), `s4` (bound to a `let`, then handed over): accepted → refused by the closure rule; `s5` (the closure stores the maker's parameter): accepted → refused at `main`'s `stash(&y)` (the maker's summary now has the global edge); with a static (`stash(&K)`) accepted; `s6` (direct known call) refused by both; `s7`, `s8` refused by both. Tests: `closure_value_global_store_refused.zrl`, `..._two_callers_refused.zrl`, `..._struct_field_refused.zrl`, `..._param_caller_refused.zrl`, `..._param_accepted.zrl`.
    - **New hole (sibling "a static reached through a captured reference"):** `s3` / `s3k` (`*gp = r as *i32` through a captured `gp = &mut G as *mut *i32`, called directly or handed over) accepted by both rules, exit 77: `bench/safety_matrix/probes/gap_94_closure_store_through_captured_raw_ptr_to_global.zrl`, listed under Known gaps and in `doc/SAFETY.md` §6 (C); cause and leads in id:whak5, added after this task.
    - **Safeguards taken out:** `build/z96/nochk` (no check): `closure_value_global_store_refused.zrl` and `..._param_caller_refused.zrl` accepted; `build/z96/nonote` (the check without recording the edges): `..._param_caller_refused.zrl` accepted, the other still refused.
    - **The store grid under `--provenance`** (`build/z96/grid`, git:b722b67): 0 unsafe cells accepted; safe twins refused 4822, as at id:w17jf, 0 newly refused. **Test programs** (`build/z96/measure.sh`): 722 compile by default (one new accepted test), warning programs 14, warnings 91, roots unchanged (199, 21, 0, 0).
    - **Sibling routes:** the 94 `gap_*` probes under `--provenance`, git:e7e4fa9 and git:b722b67: one verdict changed, `gap_64` (accepted → refused); `gap_94` accepted by both.
    - **`make test`:** on git:4cff970 `Total: 3739 run, 3737 passed, 2 failed, 96 skipped (134.2s)`, the two `[FAIL] unsafe-scan` lines on the new probe (a redundant `unsafe` block, and the scan reading `unsafe {` in its `// gap:` line), fixed in git:b584f41; then `make test-changed BASE=HEAD` on that tree: `Total: 3738 run, 3738 passed, 0 failed, 96 skipped (135.7s)`.
    - **`make preflight-changed` and the rejection differential** (on git:4cff970's tree; git:b584f41 changes only the probe, rerun by the `make test-changed` above): `PREFLIGHT_FIGURES=true REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=e7e4fa9`, rc=0: "All mutations caught."; `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`; `reject-diff: base verdicts: fresh (no cache)` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69160 programs`; checked build `Total: 1422 run, 1422 passed, 0 failed, 0 skipped (110.8s)`; git group `Total: 8 run, 8 passed, 0 failed, 0 skipped (100.1s)`; "All performance thresholds within tolerance of baseline."; the safety record as at id:w17jf plus one line, `[DETECTED] A closure storing a frame address through a captured raw pointer to a global (unmarked: exit (77); checked: poison (165))`.
    - **`sh scripts/run_safety_matrix.sh`:** `All probes complete: 473/520 passed. Mismatches: 0`.
    - **Stale:** `bench/fuzz/README.md`'s fuzz record (a change to `src/`). Milestone figures, probe counts included, not touched.
    - **Check-in:** the header asks for one; AGENTS.md: an `+AI-D` task needs none of its own, the reproducers and sibling routes above are its review.

- [x] +safety +tests +AI-D @provenance A closure storing through a captured raw pointer is checked against what the pointer reaches (gap_94) id:whak5
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Completed:** 2026-11-17 git:84799b9

    - **Found by:** id:z0096 (its sibling probe of a global reached through a capture; probe git:4cff970).
    - **Placed:** directly after id:z0096, a follow-up to it. A soundness hole accepted by both rules; the maintainer may raise it.

    - **Now (git:b722b67):** `bench/safety_matrix/probes/gap_94_closure_store_through_captured_raw_ptr_to_global.zrl` (`let gp = &mut G as *mut *i32; let cl = || { unsafe { *gp = r as *i32; } }; cl();`, `r = &x`) compiles with and without `--provenance`, exit 77. In the body the store's target is the memory capture `gp` points to, `ParamContents` of `gp`'s capture bit; at the known call the caller maps it to `os_dest_reach` of `Frame(gp)` (id:w17jf's pseudo argument; before it, of the environment), which adds `O(L)` only when `L`'s type can hold a mutable handle (`OS_Q_HANDLE`), not for a raw pointer, so `Static` is never a target. Handed to `run` (`build/z96/p/s3.zrl`) it is accepted too, by id:z0096's closure rule for the same reason. Refused: the same store with no closure (`build/z96/p/s3d.zrl`, both rules), through a named function's raw pointer parameter (`s3f.zrl`: there the target is `ParamAddr`, `O(gp)` itself).
    - **Leads:** (a) at a known closure call and in the closure rule, a contents target of a capture is what that capture's value names, `os_dest_reach` of `os_through(Frame(cj))` (one read, then the reach), not of `Frame(cj)`; (b) count a raw mutable pointer as a mutable handle in `OS_Q_HANDLE` (wider: every destination reach of a local holding one). Measure each: the store grid, the test programs (`build/z96/measure.sh`), the rejection differential; probe a literal-holding capture (`Vec<[u8]>` with `"lit"` pushed) written through, which must stay accepted.
    - **Checks:** gap_94 flipped (expected and the Known gaps entry, the `doc/SAFETY.md` §6 bullet), its sibling handed to `run` refused, `make test`, `make preflight-changed`, the rejection differential.

    - **Decided (2026-11-17): lead (a).** A capture's bit as a store's target is the memory the capture's value names: at a known closure call (`os_edge_effects`, a contents target past `__env`) and in the closure rule (`os_check_closure_value`, a target bit past `e`), the target set is joined with one read through it (`os_add_read`) before `os_dest_reach`. Lead (b) (a raw pointer as a mutable handle) not taken: it would widen the destination reach of every local holding one, not only a capture's.
    - **Also fixed:** git:b722b67's closure rule took `e` as the IL parameter count, which for a closure counts `__env` too, so rows valued by `ParamContents(__env)` or `ParamAddr(__env)` were skipped and a target bit of the first capture was read as `__env`; `e` now leaves out a last parameter named `__env` (`s3.zrl` was still accepted by the read alone because of it). No test isolates the skipped rows (a capture past bit 62, or an owned capture's `Frame` stored elsewhere, which the body refuses first).
    - **Probes** (`build/z96/p/`): `gap_94`, `s3k` (direct call) and `s3` (handed to `run`) accepted → refused; `g64`, `s5` as at id:z0096. A captured `&mut` to a local `Vec<[u8]>` holding `"lit"`, a local view pushed through it (`l1.zrl`), and the same with `&a` in place of the literal (`l2.zrl`) are refused by the base already (git:e7e4fa9, the same lines; the closure rule adds its line on the statement the base refuses), so this change adds no refusal there; that over-refusal predates it.
    - **Safeguard taken out** (`build/z96/noread`, no `os_add_read`): `known_callee_closure_store_through_raw_ptr_refused.zrl` and `closure_value_store_through_raw_ptr_refused.zrl` are accepted.
    - **gap_94 stays `known_gap`:** the old rules still accept it, as `gap_64`; its Known gaps entry now names the `--provenance` test, and `doc/SAFETY.md` §6 is unchanged (the default build is still open).

    - **Completion (2026-11-17), the work commit git:84799b9 on `stream/provenance`** (above git:b584f41; not yet on `provenance` or pushed). The checks the task names:
        - _gap_94:_ refused under `--provenance` (`known_callee_closure_store_through_raw_ptr_refused.zrl`); not flipped, since the old rules still accept it (the default build exits 77, as recorded): its Known gaps entry names the `--provenance` test; `doc/SAFETY.md` §6 unchanged.
        - _Its sibling handed to `run`:_ refused by the closure rule (`closure_value_store_through_raw_ptr_refused.zrl`).
        - _The store grid under `--provenance`_ (`build/wh/grid`): 0 unsafe cells accepted; twins refused 4822, as at id:z0096, 0 newly refused. _Test programs_ (`build/wh/measure.sh`): 722, warning programs 14, warnings 91, roots unchanged.
        - _`make test`_ (the tree of git:84799b9): `Total: 3742 run, 3742 passed, 0 failed, 96 skipped (134.8s)`.
        - _`make preflight-changed` and the rejection differential:_ `PREFLIGHT_FIGURES=true REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=b584f41`, rc=0: "All mutations caught."; `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`; `reject-diff: base verdicts: fresh (no cache)` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69160 programs`; checked build `Total: 1424 run, 1424 passed, 0 failed, 0 skipped (107.7s)`; git group `Total: 8 run, 8 passed, 0 failed, 0 skipped (99.7s)`; "All performance thresholds within tolerance of baseline."; the safety record identical to id:z0096's run.
        - _`sh scripts/run_safety_matrix.sh`:_ `All probes complete: 473/520 passed. Mismatches: 0`. Sibling routes: the 94 `gap_*` probes under `--provenance`, git:b584f41 and git:84799b9: one verdict changed, `gap_94` (accepted → refused).
    - **Stale:** `bench/fuzz/README.md`'s fuzz record (a change to `src/`). Milestone figures not touched.
    - **Check-in:** none: an `+AI-D` task, reviewed by the session that did it, with the reproducers and sibling routes above.

- [x] +precision +tests +AI-D @provenance id:z0097 An edge into a `fn` argument's environment does not make a `fn` item a global destination
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Depends:** id:z0092, id:0m61c
    > **Completed:** 2026-11-17 git:3e34cc3

    - **Found by:** id:z0092 (its accept probes).

    - **Now:** an unknown call through a `fn` parameter `f` records store edges into `ParamContents(f)`, its environment (`os_unknown_call_effects`, the environment as argument K = ARGS.len). At a call that passes a `fn` item (`Static`, no environment), the edge's destination is the item's reach, `Static`, a global, so a frame address passed beside it is refused by the call store rule: `fn first(f: fn(&i32, &i32) -> &i32, a: &i32, b: &i32) -> &i32 { return f(a, b); }` called as `first(pick, &x, &y)` with locals, `walk(step, &x, n)`, `run(&m, &x)` with `m.f` a `fn` item (id:z0092's `build/z92/a_*.zrl`; the base compiler refuses them the same way). Inside the callee `os_unknown_arg` already reads a `Static` callee as adding no memory; the caller's edge mapping does not.
    - **Do:** decide whether an edge into the `ParamContents` of a `fn`-typed parameter maps, at the caller, to the environment of the value passed (`os_through` of its `O` without `Static`, as `os_unknown_arg` takes it) rather than to everything it reaches. A rule that removes destinations: the series rule's probes (a capturing closure passed in its place must still be refused, `gap_52`'s shapes), the store grid under `--provenance`, and `test_stdlib_iter.zrl`'s seven warnings read first to see whether they are this class.
    - **Found in id:z0092's review (2026-11-06):** the false global edge carries up through a summary. `fn apply<T>(f: fn(T) -> T, x: T) -> T { return f(x); }` and `fn via(p: &i32) -> &i32 { return apply::<&i32>(same, p); }`: `via`'s body is accepted, but its summary now stores `p` into a global (the edge into `ParamContents(f)` mapped to `same`, `Static`), so `main`'s `via(&x)` with a local is refused, "the callee stores an address of this frame into a global (call store rule)", one level above the `fn` item (`build/z92r/s_generic_hof.zrl`). A fix that maps the edge at the call must also keep it out of the caller's summary. The arena twins `f(&a, mk_vec, &mut v)` and `r(&a, mk_vec)` with a local arena are refused the same way (`build/z92r/s_param_vec.zrl`).
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

    - **Reproduced (2026-11-17, git:84799b9; scratch `build/z97/p/`):** `first(pick, &x, &y)` (`a1`, "into memory that outlives it (call store rule)"), `via(&x)` through `apply::<&i32>(same, p)` (`a2`, "into a global (call store rule)" at `main`: `via`'s summary had the false global edge), `run(&m, &x)` with `m.f = rd` (`a4`). The cause, at the caller (`os_edge_effects`): an edge into `ParamContents(f)` takes the destination reach of the value passed for `f`, and a `fn` item's value is `{Static}`; and for `a4` the destination reach of `m` follows `O(m)` (a `fn` type is a handle, `OS_Q_HANDLE`), which holds the item's `Static`.
    - **Decided:** a `fn` value names no memory but its environment, and a `fn` item's `Static` is its code. (1) At a call, a target named by a declared parameter of a `fn` type drops `Static` from the value passed (`os_fn_param`), keeping `Frame` (a closure's environment), `Raw` and `Unknown`. (2) `os_dest_reach` drops `Static` from what it follows of `O(L)` when `L`'s type holds no mutable handle but `fn` values and no raw `*mut` pointer (`OS_Q_REF_HANDLE`). Both remove destinations only there; the caller's summary then has no global edge (`a2`).
    - **Found on the way:** `r1` (`put(&s, &x)` with `struct S { p: *mut *i32 }` pointing at a global) is accepted by both rules, exit 77: a raw `*mut` pointer is no handle, so the destination reach never reaches the global. Probe `gap_95_callee_store_through_raw_ptr_field_to_global.zrl` (git:b892899), listed under Known gaps and in `doc/SAFETY.md` §6 (B). Counting a raw `*mut` as a handle (`OS_Q_HANDLE`) was tried and refused 13 tests (`vec_push_lit_no_static_s.zrl`, `dest_reach_vec_push_twin.zrl`, ...: a `Vec`'s buffer is a `*mut`, so every `Vec` followed what it holds), so it is not taken; follow-up task after this one. `r2` (the same with a `fn` field beside the pointer) was refused only because the `fn` field made `S` a handle; (2) would have accepted it, which is why `OS_Q_REF_HANDLE` answers yes for a raw `*mut`.
    - **Probes:** `a1`, `a2`, `a4` refused → accepted; `a3` (a capturing closure in the `fn` item's place, `gap_52`'s shape) refused by both; `r1` accepted by both; `r2` refused by both. Tests: `fn_item_arg_not_global_accepted.zrl`, `fn_item_arg_summary_not_global_accepted.zrl`, `fn_item_field_not_global_accepted.zrl`, `fn_field_beside_raw_ptr_refused.zrl`.
    - **Safeguards taken out:** `build/z97/nostrip` (no (1)): `fn_item_arg_not_global_accepted.zrl` and `..._summary_...` refused; `build/z97/nofnonly` (no (2)): `fn_item_field_not_global_accepted.zrl` refused; `build/z97/norawq` (`OS_Q_REF_HANDLE` without the raw `*mut`): `fn_field_beside_raw_ptr_refused.zrl` accepted.

    - **Completion (2026-11-17), the work commit git:3e34cc3 on `stream/provenance`** (above git:b892899, the `gap_95` probe; not yet on `provenance` or pushed). The checks the task names:
        - _The series rule's probes:_ a capturing closure in the `fn` item's place stays refused (`a3`; `closure_value_*`, `gap_52`); the 95 `gap_*` probes under `--provenance`, git:84799b9 and git:3e34cc3: the same verdict each.
        - _The store grid under `--provenance`_ (`build/z97/grid`): 0 unsafe cells accepted; twins refused 4822, as at id:whak5, 0 newly refused, 0 accepted again.
        - _`test_stdlib_iter.zrl`'s warnings, and the test programs_ (`build/z97/measure.sh`): 725 programs compile by default (722 plus the three new accepted tests); warning programs 14, warnings 91 → 28: `variant_several_args_drop_once.zrl` 10 → 1, `match_by_value_drops_once.zrl` 23 → 1, `match_skipped_parts_dropped.zrl` 32 → 1, `test_stdlib_iter.zrl` 7 → 6 (so one of its seven was this class; the six left were not read); roots unchanged (`src/main.zrl` 199, zbuild 21, zilc 0, zman 0).
        - _`make test`_ (the tree of git:3e34cc3, with the `gap_95` probe): `Total: 3750 run, 3750 passed, 0 failed, 98 skipped (134.7s)`.
        - _`make preflight-changed` and the rejection differential:_ `PREFLIGHT_FIGURES=true REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=84799b9`, rc=0: "All mutations caught."; `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`; `reject-diff: base verdicts: fresh (no cache)` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69161 programs` (the rule acts only under `--provenance`; there it newly accepts the probes and tests above, read: `a1`, `a2`, `a4` store no frame address anywhere, and the test programs whose warnings went, not read one by one beyond the four named); checked build `Total: 1428 run, 1428 passed, 0 failed, 0 skipped (107.4s)`; git group `Total: 8 run, 8 passed, 0 failed, 0 skipped (100.0s)`; "All performance thresholds within tolerance of baseline."; the safety record as at id:whak5 plus `[MISSED] A callee storing a frame address through a raw pointer to a global held in a struct field (unmarked: exit (77); checked: exit (77))` (`gap_95`).
        - _`sh scripts/run_safety_matrix.sh`:_ `All probes complete: 473/521 passed. Mismatches: 0`.
    - **Stale:** `bench/fuzz/README.md`'s fuzz record (a change to `src/`). Milestone figures not touched.
    - **Check-in:** none: an `+AI-D` task, reviewed by the session that did it, with the reproducers and sibling routes above.

- [x] +safety +tests +AI-D @provenance A store through a raw pointer a callee reaches in a struct field reaches the global it points to (gap_95) id:95w4z
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Depends:** id:z0086
    > **Completed:** 2026-11-17 git:94c0ed2

    - **Found by:** id:z0097 (probe git:b892899).
    - **Placed:** directly after id:z0097, a follow-up to it. A soundness hole accepted by both rules; the maintainer may raise it.
    - **Depends changed (2026-11-17):** added id:z0086, which separates a literal's origin from a mutable global's; this task's fix needs it (Measured, below).

    - **Now:** `bench/safety_matrix/probes/gap_95_callee_store_through_raw_ptr_field_to_global.zrl` compiles with and without `--provenance`, exit 77. `put`'s summary stores `Param(1)` into `ParamContents(0)`; at the caller, `os_dest_reach` of `Frame(s)` follows `O(s)` only when `S` can hold a mutable handle (`OS_Q_HANDLE`), and a raw `*mut` pointer is none, so `Static` (the global `s.p` points to) is never a target. id:whak5 fixed the closure-capture form by reading one level through a capture's local; a named callee's parameter reaching a struct has no such read.
    - **Ruled out:** counting a raw `*mut` as a handle in `OS_Q_HANDLE` refuses 13 tests (a `Vec`'s buffer is a `*mut`: every `Vec` then follows what it holds, the literal case `os_dest_reach`'s comment names).
    - **Leads:** (a) follow `O(L)` for a raw `*mut` field only into what the pointer itself holds (a per-field read is not available; perhaps keep `Static` and `Raw` only, not `Frame`); (b) treat `Vec`'s buffer apart (the standard library's owners as non-handles by name or by a declaration) and count other raw `*mut` pointers as handles. Measure each with the store grid, the test programs (`build/z97/measure.sh`) and the rejection differential.
    - **Checks:** gap_95 refused under `--provenance` with a test; `vec_push_lit_no_static_s.zrl` and `dest_reach_vec_push_twin.zrl` still accepted; `make test`, `make preflight-changed`.
    - **Decision (maintainer, 2026-11-17):** lead (a), done as a measure-first step: follow a raw `*mut` field only into what that pointer was set to point at, with no list of type names (lead (b) is ruled out, since a list of standard owners would refuse a user's own container and could open a hole of its own). More work is fine; a cost to usability is not. Measure before committing: gap_95 refused; the 13 tests that the `OS_Q_HANDLE` attempt refused, plus the two `Vec` twins above, stay accepted; the count of store-grid twins refused against 4822; the test-program warnings against 28 (`build/z97/measure.sh`). If raw pointers with unknown origins cost too many refusals, stop and report before choosing between refusing them and accepting them.
    - **Note (2026-11-17):** both gap_94 and gap_95 store inside an `unsafe` block, which is the boundary where Rust leaves soundness to the programmer. That makes this hole a candidate for "documented as the programmer's responsibility" if (a) turns out to cost usability.
    - **Measured (2026-11-17, base git:24a02fb, `build/w4z/`):** two forms of lead (a) in `os_dest_reach`, each run against gap_95 and `./scripts/test.sh tests/language` (481 tests, all passing at the base).
        - _Follow `O(L)` for a type that answers `OS_Q_REF_HANDLE` but not `OS_Q_HANDLE`_ (a raw `*mut`, Static kept): gap_95 refused ("the callee stores an address of this frame into memory that outlives it (call store rule)"), `Total: 481 run, 472 passed, 9 failed`. Cause: `O(L)` is one set for everything a local reaches, with no level between the raw pointer's own target and the values stored behind it. For a `Vec`, `O(v)` is its elements (`make_vec`: `v O={Param(0), ParamContents(0)}` after `v.push(s)`, `--emit-origins` of `tests/language/memory/origins/call_result_make_vec.zrl`), so following it makes every `push` a store into the pushed elements, here the caller's array. So the lead as the maintainer decided it (to what the pointer was set to point at) has no information to read; ruled out without a per-level origin.
        - _Add only `Static` from `O(L)` through such a type_ (the patch below): gap_95 refused, `Total: 481 run, 475 passed, 6 failed`. The six are `origins/vec_push_lit_no_static_s`, `provenance/arena_unwrap_literal_then_push_accepted`, `dest_reach_vec_push_twin`, `option_arena_unwrap_store_accepted`, `struct_view_pushed_accepted` and `vec_index_field_accepted`. Each holds a string literal in a `Vec` (`names.push("lit")`), whose `Static` is then read as the `Vec` pointing at a global. That is id:z0086's subject: a literal's `Static` and a mutable global's are one flag. With the two told apart, this form follows only the global part and the six stay accepted. The cost then left is a false refusal where a `Vec` holds pointers to a mutable global and a frame address is pushed into it, judged rare; to be measured on the grid then.
        - Patch (reverted; apply it by hand to measure again):

    ```diff
    @@ fn os_dest_reach
                 if os_has_frame(c, dst, id) {
                     if os_or(c, dst, c.nl + id) { more = true; }
                     let lty = os_local_ty(locals, id as u32);
    +                if !os_type_has(c, module, lty, OS_Q_HANDLE)
    +                    && os_type_has(c, module, lty, OS_Q_REF_HANDLE)
    +                    && c.buf[id * c.words + OS_W_FLAGS] & ORIGIN_STATIC != 0 as u64 {
    +                    os_add_flag(c, dst, ORIGIN_STATIC);
    +                }
                     if os_type_has(c, module, lty, OS_Q_HANDLE) {
    ```
    - **Blocked (2026-11-17):** on id:z0086, added to **Depends:**. Next step after it: apply the patch with `Static` replaced by z0086's global-only origin, then `./scripts/test.sh tests/language` (expect 481 passed), gap_95 refused, the store grid against 4822 twins, `build/z97/measure.sh` against 28 warnings, `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed`. No code is committed for this task yet.

    - **Unblocked (2026-11-17, id:z0086 at git:27a3d81):** literals and `fn` items are `Rodata` now, no destination. The recorded patch, applied in a scratch copy (`build/provenance/build/z86/z_95`), refuses gap_95 and newly refuses nothing in `tests/language`. Next: apply it on the branch and run this task's checks.

    - **Done as decided (lead (a), measure first), with what the measurements showed:** following all of `O(L)` through a raw `*mut` has no information to read (Measured, above). So `os_dest_reach` adds only the `Static` in `O(L)`, and only when `L` holds no mutable handle and holds a raw `*mut` that is not part of an owner. That is a new type query, `OS_Q_LOOSE_RAW`: a raw `*mut` held by value, not inside a standard collection or a `Drop` type, not behind a reference or a slice, and not a `*mut ArenaHeader`. Three findings shaped it:
        - _Literals:_ id:z0086 made them `Rodata`, which removed the 6 refusals the patch had.
        - _Ownership:_ testing ownership on the whole struct (`!os_owns`) let a raw pointer beside a `Vec` in one struct through (`build/provenance/build/w4z/sib/s_owner_beside.zrl`, accepted). With no ownership test at all, a `static`'s address pushed into one arena `Vec` puts `Static` in the arena's `O`, so every `Vec` in that arena became a global destination (`arena_unwrap_static_then_push_accepted.zrl` refused at 17:5 and 19:5). Hence a per-type query.
        - _The arena's raw form:_ zbuild's `BuildCtx { .., arena: *mut ArenaHeader }`, whose string fields hold `Static`, gave 3 new warnings (`tools/zbuild/src/main.zrl:224`, `:250`, `:252`, "the callee stores an address of this frame into memory that outlives it (call store rule)"). A `*mut ArenaHeader` points at an arena, so it is not loose. With that, zbuild is back to 21. Bound: a `*mut ArenaHeader` to a `static mut` arena header is not followed, which needs `unsafe` to build.
    - **gap_95 stays `known_gap`:** the default mode still accepts it, as with gap_94. Its Known gaps entry now says it is refused under `--provenance`, and `doc/SAFETY.md` §6.1 (kind 3 and the class (B) row) says so too. No probe count was touched.

    - **Completion:** git:94c0ed2 (one commit): `os_dest_reach` and `OS_Q_LOOSE_RAW` in `src/check_zir.zrl`; the design note's _Destination reach_; `doc/SAFETY.md`; `doc/spec/safety_model.md`; mutations M166 to M168. Five tests in `tests/language/memory/provenance/`: `callee_store_through_raw_ptr_field_refused` (gap_95's program), `callee_store_through_raw_ptr_beside_owner_refused`, `callee_store_through_nested_raw_ptr_field_refused`, `callee_store_through_raw_ptr_field_local_accepted` (the raw pointer names a local slot), and `arena_header_ptr_beside_static_accepted`.
    - **Checks** (this task's list):
        - gap_95 refused under `--provenance` with a test: "the callee stores an address of this frame into memory that outlives it (call store rule)" at 12:5.
        - `vec_push_lit_no_static_s.zrl` and `dest_reach_vec_push_twin.zrl` still accepted, in `./scripts/test.sh tests/language`: `Total: 490 run, 490 passed, 0 failed, 0 skipped (2.7s)`.
        - `make test`: `Total: 3770 run, 3770 passed, 0 failed, 100 skipped (136.7s)`.
        - `PREFLIGHT_FIGURES=true REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=27a3d81`, rc=0: "All mutations caught."; `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`; `reject-diff: base verdicts: fresh (no cache)`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69162 programs against 27a3d81...` (the rule acts under `--provenance` only); checked build `Total: 1438 run, 1438 passed, 0 failed, 0 skipped (107.7s)`; git group `Total: 8 run, 8 passed, 0 failed, 0 skipped (99.7s)`; "All performance thresholds within tolerance of baseline."; the safety record unchanged.
        - The store grid under `--provenance` (`build/provenance/build/w4z/run_all.sh`, git:94c0ed2's compiler): 0 unsafe cells accepted, twins refused 4694 as at id:z0086, 0 accepted again, 0 newly refused. `build/z97/measure.sh`: test-program warnings 17 (unchanged); roots `src/main.zrl` 199 (an identical list), zbuild 21, zilc 0, zman 0.
    - **Take-outs** (scratch copies `build/provenance/build/w4z/s_{nostep,noown}`): with the step removed, gap_95's test and the beside-owner test are accepted; with owners counted as loose, `arena_unwrap_static_then_push_accepted` is refused. Without the `ArenaHeader` exemption (the build before it, `build/w4z/zoril.new` of the first commit), `arena_header_ptr_beside_static_accepted` is refused at 28:5. M166, M167 and M168 are these three, all caught.
    - **Sibling routes probed:** nested struct (refused), raw pointer beside an owner (refused), raw pointer to a local slot (accepted), a summary whose stored value is a parameter passed `&K` (accepted, `build/w4z/sib/s_param_view_twin.zrl`). An earlier preflight run of the first commit failed `unsafe-scan` on two of the new tests (a redundant `unsafe` around `&mut G as *mut *i32`). They were fixed before this run.
    - `PREFLIGHT_FIGURES=true` stubs the milestone-figures check (id:xh0jq). The fuzz record `bench/fuzz/README.md` is stale after this `src/` change. **Check-in:** none (`+AI-D`); reproducers and siblings re-run above.

- [x] +audit +safety +measurement +AI-D @provenance Read, by root, the safe store-grid twins the new rules refuse and the default mode accepts id:nc3ym
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Depends:** id:w17jf
    > **Completed:** 2026-11-17 git:24a02fb

    - **Placed:** before id:z0065, which it blocks: id:z0065 allows no newly refused twin without a task, and expects each over-rejection to have its own task done first. Found in a review of the task list (the maintainer's request, 2026-11-17). It depends on id:w17jf so that it counts what is left after it.

    - **Moved (2026-11-17, the maintainer):** to directly after id:95w4z, before id:z0087. The grouping of the known gaps (`doc/SAFETY.md` §6.1, git:24a02fb) found the provenance rules refuse every escape probe; what decides whether they can become the default is their cost in safe programs refused, which this task reads. id:z0074 reads the other direction but depends on id:z0065, so it stays where it is.
    - **Now (git:98a1efc on `stream/provenance`):** the default mode's record `bench/fuzz/store_grid_twin_rejections.txt` has 3932 safe twins; id:mr6jm's grid run under `--provenance` (`build/provenance/build/mr6jm/grid/work/twin_rejections.txt`) refuses 6182. `comm` of the two sorted lists: every twin the default refuses the new rules refuse too (0 the other way), and 2250 are refused by the new rules only, so the default flip (id:z0065) would newly refuse them. By destination: `closure_capture_mut` 1180, `closure_owned_capture` 780 (id:w17jf), `deref_out` 130, `field_out` 124, and 6 each of `ten_copies`, `return_val`, `local_field_assigned_out`, `closure_call_mut`, `call_struct_mut`, `call_mut`.
    - **No task covers 1470 of them.** The 1180 `closure_capture_mut` twins: 118 on each of the ten paths; carriers `string` 640, `closure_local` 480, `elem_ref` 30, `ref_local` 30. The other 290: paths `same_param` 236, `fn_val` 42, `param_65` 6, `store_param_65` 6; carriers `string` 128, `closure_local` 96, `elem_ref` 33, `ref_local` 33; hazards `frame_ends` 130, `drop` 64, `move_owner` 64, `push_growth` 32. id:z0065's accepted refusal (id:z0091's class, 18 cells) matches at most 82 of them by name (`__(same_param|store_param_65)__(deref_out|field_out)__frame_ends`). id:z0075 read the newly refused twins by root on 2026-11-06; id:z0092 to id:z0094 and id:mr6jm changed the closure rules since, and nothing re-read them.
    - **Do:** after id:w17jf, run the store grid under `--provenance` again, take the twins refused there and absent from the default record, and group them by root (one reduced program and its `--emit-origins` line per root, as id:z0064 did for the tree's warnings). For each root: a real escape the twin generator got wrong (fix the generator); an over-rejection (a task placed before id:z0065, added to its **Depends:**, or the reason it is deferred to `future.tm.md` as a precision bound with a `KNOWN_ISSUES.md` §5 entry for id:z0065 to write); or id:z0091's class (already accepted). A fix is a task of its own, not done here.
    - **Checks:** C1 the two counts and the `comm` figures after id:w17jf, with the command. C2 every twin refused by the new rules only is assigned to a named root; the roots' counts sum to the total. C3 each root has its reduced program, the diagnostic and the default mode's verdict (built and run: exit 0), quoted here. C4 each root names its task or its recorded bound, and id:z0065's **Depends:** and **Accepted refusal** bullet agree with the list. C5 `tm validate doc/tasks/*.tm.md`.

    - **Findings (2026-11-17):** the 890 twins refused by the new rules only fall into three roots. Reproducers are in `build/provenance/build/nc/`: `only.txt` is the list, and `diag.tsv` has each twin's first error with the current `build/zoril --provenance`. All 890 reproduce.
        - _R1, 186 twins, a field assignment keeps the field's old origins:_ every `ref_local`/`elem_ref` twin, each in `array_slot`, `struct_field` or `tuple_slot`. The carrier is built with a placeholder (`let mut carrier_arr = [&seed];`) and then assigned (`carrier_arr[0] = src_val;`), so `carried` still holds `Frame(seed)`. The destinations are the 18 cells id:z0065 accepts, plus `closure_capture_mut` 60, `closure_owned_capture` 60, the `fn_val` path 54 and `closure_call_mut` 6. Representative `ref_local__array_slot__closure__closure_capture_mut__frame_ends`: "the callee stores an address of this frame into memory that outlives it (call store rule)"; the default build exits 42 (the twin's value). With `[src_val]` for `[&seed]` it is accepted (`r1b.zrl`), and so are the `closure_owned_capture` representative (`r1_init.zrl`) and the `fn_val` one (`r1c.zrl`). **Task:** id:z0091 (`future.tm.md`), measured there. **Recommendation:** promote id:z0091 before id:z0065 rather than widen the accepted bound to 186. A placeholder followed by an assignment is ordinary code, and the workaround (build the value in its final form) is the kind of awkward rewrite users should not be made to do. Promotion is the maintainer's decision, so this task does not move it.
        - _R2, 224 twins, one tuple parameter carrying both the destination and a read-only `Static`:_ path `same_param`, destinations `deref_out` and `field_out`; carriers `string` 128 and `closure_local` 96. `stash_pair((out, carried))` merges the two, and the literal `"hello"` (or the `fn` item `twin_fn`) lands among the store targets, read as a global. Representative `string__direct__same_param__deref_out__frame_ends`, line 14: "the callee stores an address of this frame into a global (call store rule)"; the default build exits 104 (`'h'`). With `*out` in place of the literal it is accepted (`r2_noliteral.zrl`). **Task:** id:z0086, already in id:z0065's **Depends:**, with the measurement appended, including that the rule should cover `fn` items. The 96 `closure_local` twins also need id:4by24: without the `fn` item they are refused at `return dest_val();` by the unknown-call store rule (`r2c.zrl`; default build of the original exits 42).
        - _R3, 480 twins, a call through a `fn` value:_ carrier `closure_local`, destination `closure_owned_capture`, all ten paths and every container. In the closure body, `h.s()` is an unknown call, which makes `h` hold `Frame(h)` and `Frame(_5)`, so the earlier `h = OwnedHolder { s: routed, .. }` (line 16) is refused: "a value holding an address of this frame is stored into memory that outlives it (store rule)". The default build exits 42. With `return 7;` for `return h.s();` it is accepted (`r3_nocall.zrl`). **Task:** id:4by24, new, placed before id:z0065 and added to its **Depends:**.
        - No twin is a real escape the generator got wrong. Every root has its own refusal, and in each representative removing the cause makes it accepted.

    - **Completion:** a measurement; no code changed. The store grid's last `--provenance` run is id:z0097's (`build/provenance/build/z97/run_all.sh`, `ZORIL_CC` = `zoril.new --provenance` at git:3e34cc3). `git diff --stat 3e34cc3 HEAD -- src stdlib tools rt scripts bench/fuzz` is empty at git:24a02fb, so that run measures the current compiler and was not repeated. It accepted 0 unsafe cells (`work/actual_names.txt` empty).
    - C1: `sort -u build/z97/grid/work/twin_rejections.txt` gives 4822 and `bench/fuzz/store_grid_twin_rejections.txt` gives 3932. `comm -12` gives 3932 and `comm -23` gives 0: every twin the default refuses, the new rules refuse too. `comm -13` gives **890** (`build/nc/only.txt`), down from 2250 when this task was written. By destination: `closure_owned_capture` 540, `deref_out` 130, `field_out` 124, `closure_capture_mut` 60, and 6 each of `ten_copies`, `return_val`, `local_field_assigned_out`, `closure_call_mut`, `call_struct_mut` and `call_mut`.
    - C2: R1 186 + R2 224 + R3 480 = 890. Each twin is assigned by its name pattern: R1 is the `(ref_local|elem_ref)__(array_slot|struct_field|tuple_slot)__` prefix (186 of the 186 `ref_local`/`elem_ref` twins), R2 is the `string` and `closure_local` twins on the `same_param` path, and R3 is the `closure_local` twins on `closure_owned_capture`. By diagnostic (`diag.tsv`): 522 store rule, 284 call store rule into a global, 78 call store rule outlives, 6 return rule.
    - C3: each root's representative, its diagnostic and its default-mode result are quoted under Findings. Each was built with `scripts/build_zrl.sh ... -I stdlib=stdlib --runtime-first` and run. All exit with the twin's own value, not 0: 42 for the `ref_local` and `closure_local` twins, and 104 for the string twin (`dest_val[0]`, `'h'`). That is the result the twin is written to give.
    - C4: R1 names id:z0091, with the decision between promoting it and widening the accepted bound recorded on id:z0065 for the maintainer. R2 names id:z0086, R3 names id:4by24, and the 96 twins that are in both name both. id:z0065's **Depends:** gains id:4by24 and already has id:z0086. Its **Accepted refusal** bullet still names R1's 18 cells, and the new bullet under it gives the other 168.
    - C5: `tm validate doc/tasks/*.tm.md`, three `[PASS]` lines.
    - Not run: `make test` and `make preflight-changed`, since no compiled code changed. The fuzz record is unaffected.

- [x] +safety +design +AI-D @provenance L1 A liveness model: what holds a borrow when no local does, stated as the design note states origins id:dhded
    > **Created:** 2026-11-14
    > **Branch:** `provenance`
    > **Depends:** id:0m61c
    > **Check-in:** none of its own (`+AI-D`); the maintainer reads the design before L2 starts.
    > **Completed:** 2026-11-17 git:bdfcac6

    - **Placed:** before id:z0044, which it blocks: id:z0044 extends the per-local borrow set, and this task decides whether that set is the model. Found in a review of the plan (the maintainer's request, 2026-11-14).

    - **Moved (2026-11-17, the maintainer):** to directly after id:nc3ym. The same grouping found the invalidation holes (the reset half of class G, classes H and M) are the only kind the provenance rules leave open besides gap_95, and this design is their single fix. It must weigh whether a static rule makes ordinary code awkward, against a run-time check or a rule left to the programmer.
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

    - **Probes (2026-11-17, `build/provenance/build/dh/`, compiler git:3e34cc3; "run" is the default build's exit, where 42 is the value the view should read and 77 is the reused memory):**
        - _p1, a store into a global through `unsafe`_ (`p1_global.zrl`: `unsafe { GP = v.as_slice().ptr; } v.free();` in a callee, `GP: *i32`). Refused by both rules: default "cannot store 'v' a reference into storage owned by this frame ... cannot outlive the frame"; `--provenance` "the callee stores an address of this frame into a global (call store rule)". A `static mut` cannot hold a view at all ("a static mut cannot hold a reference or slice (use a raw pointer)"). So the escape rules keep a view of frame-owned storage out of globals, and liveness never sees a global holder.
        - _p2, a store into a closure's captured `&mut`_ (`p2_closure.zrl`: `let r = &mut s; let mut c = || { *r = v.as_slice(); }; c();` then `v.free()`). Refused by both rules as an escape (default 7:40 "cannot store 'v' ..."; `--provenance` "a value holding an address of this frame is stored into memory that outlives it (store rule)"). A closure environment does not reach liveness either.
        - _p3, a returned struct holding the view, freed in the caller of the caller_ (`p3_ret_struct.zrl`: `mk` returns `H { s: v.as_slice() }`, `mid` returns `mk(v)`, `main` does `let h = mid(&v); v.free();`). Refused by both rules: 10:5 "cannot mutably borrow 'v' while it is already borrowed". A call result is a local, and the elision default ties it to the argument, so a call result already holds the borrow.
        - _p4, a trait method_ (`p4_trait.zrl`: `impl Put for S { fn put(self: &mut S, v: &mut Vec<i32>) { self.s = v.as_slice(); v.free(); } }`). **Accepted by both rules, runs 77.** It is gap_87's in-body shape with `self` as the parameter that receives the view; trait dispatch adds nothing.
        - _p5, `push` in place of `free`_ (`p5_push_N.zrl`, `*out = v.as_slice();` then `N` pushes, N = 1, 2, 4, 8, 16, 17, 32, 33, 64, 65). Accepted, and every N runs 42. `Vec.grow_to` (`stdlib/vec.zrl`) allocates a new buffer and never frees the old one, so a view kept across a growth reads stale but valid memory: a leak, not a use after free, and no buffer size reuses it. The model still counts `push` as invalidating (a `&mut` use), as it does for a local today (`q_local_push.zrl`: "cannot mutably borrow 'v' while it is already borrowed"). That way a growth that frees, as `free` does, needs no new rule.
        - _p6, `Arena.reset` through a `&mut Arena` parameter, with the view stored through another parameter_ (`p6_arena_param.zrl`). Refused at the caller: 11:15 "cannot mutably borrow 'a' while it is already borrowed", because `v` (made in `a`) holds a borrow of `a` across the call. So the caller of an invalidating callee is protected when a local still holds the source.
        - _p7, the view stored before the callee, and the callee only invalidating_ (`p7_kill_after.zrl`: `put(&mut s, &v)` with `fn put(out: &mut [i32], v: &Vec<i32>) { *out = v.as_slice(); }`, then `kill(&mut v)` with `fn kill(v: &mut Vec<i32>) { v.free(); }`, then `s[0]`). **Accepted by both rules, runs 77.** This is a new route: gap_38's shape (a callee writes through a `&mut` parameter, here into a local slice, not a field) with the view made inside the callee from another argument, and a free in place of a reset. It becomes probe gap_96.
        - _For comparison, locals today:_ `let s = v.as_slice(); v.push(1);`, `v.free()` in place of the push, and the same through a `&mut Vec` parameter (`q_param_free_local.zrl`) are all refused, "cannot mutably borrow 'v' while it is already borrowed". Any `&mut` use is the invalidation, so "takes `&mut`" is enough when the holder is known.

    - **Measurement (item 6, 2026-11-17):** the scratch rule is a copy of `src/` (`build/provenance/build/dh/srcx/`, a patch to `check_assign`'s second through-pointer arm and `borrow_counts`; not committed). A write through a parameter gives the stored value's borrows to that parameter, and `borrow_counts` keeps them live until return, under the strict tier. Built with `sh scripts/build_zrl.sh build/dh/zoril.scratch build/dh/srcx/main.zrl -I stdlib=stdlib -I build/dh/srcx -I build/gen --runtime-first`, measured with `sh build/dh/measure.sh` (every program of `tests/` and `stdlib/` the default `build/zoril` compiles, and the tool roots). Result: 755 programs, **0 refused**, apart from 9 `warning:` lines that matched the word "error" in their file names. `src/main.zrl`: 126 errors from 13 stores: `src/driver/types.zrl:864` (42), `src/verify.zrl:275` (27), `src/driver/module.zrl:692` (18), `src/resolve.zrl:720` (10), `src/verify.zrl:1441` (8), `src/check_zir.zrl:2082` (7, a raw pointer `live_row` result), and 7 more, 8 of the 13 being `self.file_path = self.intern_table.lookup(..)`. `tools/zilc`: 16 from `self.module_name = self.intern_table.lookup(m_id)` (`zil_parse.zrl:2106`). Each is "cannot mutably borrow 'self' while it is already borrowed" (121) or "cannot assign to .. because it is borrowed" (4), or a scope end (1). None of the 142 lines is a release (`grep -E '\.(free|reset|reset_to|destroy)\(|@drop'` over them: 0). `grep -rn -E '\.(free|reset|reset_to|destroy)\(' src tools/zilc/src` finds only a comment. That fixed the release tier.
    - **Census (item 3):** `build/dh/srcc/` instruments each site where a value that holds a borrow gets no holder (`CENSUS <site>` on stderr), built as `build/dh/zoril.census` and run over the same programs plus `src/main.zrl` (`build/dh/census/all.txt`). By program: write through a pointer (`check_assign`) 31 and 25; destination holds no reference 104; destination is a raw pointer 27. The liveness probes: `gap_37`, `gap_43`, `gap_87`, p4 and p7 fire the through-pointer sites; `gap_38`, `gap_39` and `gap_44` fire none (a call transfers no borrow, and `#[borrows()]` is trusted). What each answers under the model is in the design note §3.1, item 3.
    - **Plan edits:** added id:bfcvm (L2a, the `releases` fact) before id:kqp9n. id:kqp9n is now holders one and two, with **Do:** and C1 to C7. id:z0044 is now holder three, with **Do:** and C1 to C6; its Depends gain id:bfcvm and id:kqp9n and lose id:z0011, which only `gap_44` needed, and `gap_44` is id:z0011's. `gap_96` (git:bdfcac6) is closed by id:z0044.

    - **Completion:** the design is `doc/design/provenance.md` §3.1, with §4's rows for `gap_37`, `gap_38`, `gap_39`, `gap_43`, `gap_87` and `gap_96`, in git:bdfcac6. The same commit adds probe `gap_96`, with its Known gaps entry, its `doc/SAFETY.md` §6 class (G) text, and §6.1 updated to say the model is designed, not built. No compiled code changed: the scratch and census compilers are copies under `build/`.
    - C1: the seven probes and their results are under **Probes** above: p1, p2, p3 and p6 refused, p4 and p7 accepted and run 77, and p5 accepted and run 42 for every N.
    - C2: §3.1 answers items 1 to 6 in numbered paragraphs, and §4 has a row for each liveness gap: `gap_37`, `gap_38`, `gap_39` and `gap_43` in one row, then `gap_87`, `gap_96`, and `gap_44` (Z-0011's row, unchanged).
    - C3: quoted under **Measurement** above, with its commands.
    - C4: id:kqp9n and id:z0044 each have a **Do:** and numbered **Checks:** following §3.1, with take-out checks (id:kqp9n C6, id:z0044 C5). id:bfcvm has C1 to C5, with take-out check C4.
    - Checks run after the last edit: `make test-changed BASE=HEAD` (the doc and safety tiers, with the new probe untracked at the time) `Total: 3750 run, 3750 passed, 0 failed, 100 skipped (135.4s)`, and again after the last wording change `Total: 3750 run, 3750 passed, 0 failed, 100 skipped (135.6s)`. `sh scripts/run_safety_matrix.sh`: "All probes complete: 473/522 passed. Mismatches: 0" with `gap_96` in place. `sh scripts/check_safety_model.sh`: "PASS: safety_model.md is self-consistent." Not run: `make test` and `make preflight-changed`, since no `src/`, `stdlib/` or `tools/` file changed.
    - The maintainer reads the design before L2 starts (this task's **Check-in:** line).

- [x] +safety +tests +AI-D @provenance id:z0086 B1.9e A literal held by a value does not make what the value reaches a global destination
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Depends:** id:0m61c
    > **Check-in:** stop for review after it.
    > **Completed:** 2026-11-17 git:27a3d81

    - **Found by:** id:z0064 (root (e)).
    - **Routed (2026-11-06, by id:z0075):** a rule. id:z0084's rule is deferred, so this one must cover the lowerer's literals without it: `exh_missing` writes literals into a `ByteVec` in `self.arena`, which the call rule names `Param(0)` (`*self`), so the `Static` lands in `*self` and not only in the arena.

    - **Now:** a local that holds `Static` (a string literal in one of its fields, or written into memory it reaches) makes every later store into what it reaches have `Static` among its targets, and the call store rule reads `Static` as a global. In the driver, `ZirLowerer::lower_function`'s summary has `store Static -> Param(0)` (a dozen lowering functions write a literal into `*self`, the first in lowering order `exh_missing`), so `Driver::run_body_passes_in_scratch`'s local `zir_low` holds `Static`; it is the first function in lowering order with a store into a global. That carries the last 8 of `src`'s warnings (`src/driver/module.zrl:666`, `:713`, `:1141`, `:1188`, `:1475`, `:1603` into a global; `:1362`, `:1386` outlives), and the class covers id:z0064's three `arena_raw` test programs (`test_stdlib_string_arena`, `accept_slice_receiver`, `test_empty_compile_and_tool_errors`).
    - **Reduction** (`build/z64/t/e3.zrl`; builds, exits 0, accepted by default; "into a global" at the call in `main` under `--provenance=warn`; twin with `name: s` gives no warning): `struct W { name: [u8], items: &mut Vec<[u8]> }`, `impl W { fn add(self: &mut W, s: [u8]) { self.items.push(s); } }`, `fn inner(out: &mut Vec<[u8]>, s: [u8]) { let mut w = W { name: "lit", items: out }; w.add(s); }`, and `main` calls `inner(&mut v, &data)` with a local array `data` and a `Vec<[u8]>` `v`, returning `v[0][1] as i32 - 2`.
    - **Not yet measured alone:** replacing `ZirLowerer.new`'s `file_path: ""` changes none of the 8 (the other sites still write literals), and id:z0084's experiment alone does not remove them either. Find each site's route first (`--emit-origins` with the target-file filter in `src/driver/module.zrl` removed, as id:z0064's debug compiler did).
    - **Do:** decide whether a `Static` origin reached through a value may be dropped from store targets (a literal is read-only, so storing through it needs `unsafe`), or whether the sites change. A rule removes origins, so the series rule applies, with probes of a `static mut` reached through a value (which must stay a global destination) and a literal beside a `&mut` in one struct. `make test`, `make preflight-changed`, the rejection differential.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **id:z0084 promoted (2026-11-15, the check-in id:n177h):** it now runs directly after this task, so the routing above still holds: this task's rule must not rely on id:z0084's.
    - **Depends changed (2026-11-17, a review of the task list, the maintainer's request):** removed id:z0087. It is the task before this one in the queue, not a blocker: the two rules are separate (an integer result's tie; a `Static` origin among store targets), and the 8 warnings above are counted with id:z0087's change in, which the queue's order gives. Taken before id:z0087, the count to start from is 14, with the six `fmt/` warnings of id:z0087 left over.

    - **Measured by id:nc3ym (2026-11-17):** 128 safe store-grid twins (carrier `string`, path `same_param`, destinations `deref_out` and `field_out`) are refused under `--provenance` for this task's cause alone. `fn stash_pair(p: (&mut [u8], [u8])) { *p.0 = p.1; }` called with `(out, "hello")` puts the literal's `Static` among the targets, so `main`'s `escape_storer(&mut dest_val)` is refused, "the callee stores an address of this frame into a global (call store rule)". The default build runs it and exits 104. With the literal replaced by `*out` it is accepted (`build/provenance/build/nc/r2_noliteral.zrl`). Another 96 twins (carrier `closure_local`) have the same route with a `fn` item's `Static` (a function's code, read-only like a literal), so the rule should cover `fn` items too. Those 96 then still need id:4by24. id:95w4z also depends on this task.

    - **Moved (2026-11-17):** to directly after id:dhded. The order (2026-11-17, the maintainer delegated it: "the order that gives us the best perspective on reaching the conclusion of this provenance series"): id:dhded, id:z0086, id:4by24, id:z0091, then the rest. id:dhded comes first because it settles the largest open question for the series' end, whether the invalidation holes can be refused statically without awkward code. The three precision tasks after it remove all 890 of id:nc3ym's newly refused twins: id:z0086 first (224 twins, and it unblocks id:95w4z), then id:4by24 (480 twins, a soundness question still open), then id:z0091 (186 twins, a known technique). After them the store grid shows what id:z0065 really costs.

    - **Decision (2026-11-17):** a `Static` origin reached through a value cannot simply be dropped from store targets, because a `static mut` reached through a value must stay a global destination. That is gap_95 (id:95w4z), and dropping it would refuse nothing there. So `Static` is split instead: string literals and a `fn` item's code (a `FuncAddr` with no environment) get a new origin, `Rodata` (`ORIGIN_RODATA`). In a value it is outside the frame, as `Static` is; as memory it is no destination (`OS_FLAGS_MEMORY` masks it out in `os_external`, `os_note_edges` and `os_drop_self_store`). A summary keeps it apart: edge code 130 (`OS_EDGE_ROWS` 131) and the result flag. So a literal a callee stores is `Rodata` at the caller, and an old `.zri` stays readable. A `static`'s address (`GlobalAddr`) stays `Static`: it may be a `static mut`, and an immutable `static`'s address as `Rodata` is a later precision step, not needed here. Recorded in `doc/design/provenance.md` §3 (_Origins_).
    - **Not this task's class:** the "last 8 of `src`'s warnings" this task named do not change. `src/main.zrl` has 199 warnings with the base and with this change, identical lists. A debug build printing origins for every file (`build/provenance/build/z86/zoril.dbg`, both `target_source_file` filters removed in a copy of `src/`) shows `Driver::run_body_passes_in_scratch`'s `zir_low` now holds `Rodata`, no longer `Static`. It also holds `Unknown`, from ZirLowerer callees whose summaries store `Unknown -> Param(0)`: a local's address passed by reference, as in `ZirLowerer::check_initializer_value` (`_13 O={Frame(init_place)}`). That `Unknown` makes `*self` a global. It is another root, left to the tasks that read `src`'s warnings.
    - **Sibling probes:** a raw pointer to a `static mut` beside a literal in one struct, with a frame address stored through it, is still refused (`literal_beside_global_ptr_store_refused.zrl`). A literal beside a `&mut` (`W { name: "lit", out: out }; *w.out = data`) is accepted; the base refused it, "the callee stores an address of this frame into a global (call store rule)" (`literal_beside_mut_ref_accepted.zrl`). Its unsafe twin, a callee's own array view stored through that `&mut`, is refused (`literal_beside_mut_ref_local_view_refused.zrl`). The `fn` item form is accepted; the base refused it (`fn_item_beside_mut_ref_accepted.zrl`). Across a `.zri` (`build/provenance/build/z86/zri/`): `--emit-interface` writes `edge = 130` twice for a library storing literals, and a caller compiled with `-c --iface-dir` is accepted, as whole-program is; the base compiler refuses it whole-program. The task's reduction (`struct W { name: [u8], items: &mut Vec<[u8]> }` ...) now gives 0 warnings under `--provenance=warn`. The reduction file named above no longer existed (`build/z64/t/e3.zrl`), so it was rewritten from the text.
    - **Unblocks id:95w4z:** with this change, that task's recorded patch (`Static` only through a raw `*mut`-holding local, built in a scratch copy `build/provenance/build/z86/z_95`) refuses gap_95, and over `tests/language` it refuses nothing the current compiler accepts. The 6 literal tests that blocked it are accepted.

    - **Completion:** git:27a3d81 (one commit). It holds the `Rodata` origin; the design note; 5 tests (`literal_beside_global_ptr_store_refused`, `literal_beside_mut_ref_accepted`, `literal_beside_mut_ref_local_view_refused`, `fn_item_beside_mut_ref_accepted`, `arena_unwrap_static_then_push_accepted`); the 4 origin goldens updated; and `scripts/mutation-check.sh` (M141's pattern follows the widened result-flags line, M164 and M165 are new, M158 and M160 name the new test).
    - **Expected results changed (origin goldens only, no `EXPECT` or exit):** in `tests/language/memory/origins/`, `box_projected_write`, `call_result_tied_lit`, `field_write_through_ref` and `vec_push_lit_no_static_s`, `Static` becomes `Rodata` in the `ORIGINS:` line, each for a literal (`"lit"`, `""`), and in the comments naming it. `arena_unwrap_literal_then_push_accepted` stays as it was. It no longer catches M158 or M160 (its literal is no destination now), so the twin `arena_unwrap_static_then_push_accepted` (a `static`'s address) does: each mutant, built in a scratch copy, refuses it at 17:5, "the callee stores an address of this frame into memory that outlives it (call store rule)".
    - **Take-outs** (scratch copies `build/provenance/build/z86/s_{mask,lit,fn}`): with the memory mask removed from `os_note_edges`, `literal_beside_mut_ref_accepted` and `fn_item_beside_mut_ref_accepted` are refused; with literals back to `Static`, the literal test is refused and the `fn` test accepted; with `fn` items back to `Static`, the reverse.
    - **The store grid under `--provenance`** (`build/provenance/build/z86/run_all.sh`, compiler = git:640374f's `src/`, the same as git:27a3d81's): 0 unsafe cells accepted (`work/actual_names.txt` empty). Twins refused 4694, against 4822 at id:z0097: 128 accepted again, all `string__*__same_param__{deref_out,field_out}` (64 and 64, id:nc3ym's R2 string half), and 0 newly refused. The modular step stopped as on every `--provenance` grid run.
    - **Test programs** (`build/z97/measure.sh build/z86/zoril.new`): 727 compile by default; warnings 28 -> 17, none new. Gone: `closure_type_inference.zrl:29`, `accept_slice_receiver.zrl:11`, `test_stdlib_iter.zrl` (6), `test_stdlib_string_arena.zrl` (3). Roots: `src/main.zrl` 199, zbuild 21, zilc 0, zman 0, as before.
    - **Checks:** `./scripts/test.sh tests/language` `Total: 485 run, 485 passed, 0 failed, 0 skipped (2.8s)`. `make test` `Total: 3760 run, 3760 passed, 0 failed, 100 skipped (135.0s)`. `PREFLIGHT_FIGURES=true REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=bdfcac6`, rc=0: "All mutations caught."; `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`; `reject-diff: base verdicts: fresh (no cache)` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69162 programs against bdfcac6...` (the change acts under `--provenance` only; there it accepts the grid's 128 twins and the 2 base-refused tests above, all read); checked build `Total: 1433 run, 1433 passed, 0 failed, 0 skipped (107.5s)`; git group `Total: 8 run, 8 passed, 0 failed, 0 skipped (100.0s)`; "All performance thresholds within tolerance of baseline."; the safety record unchanged. An earlier run of the preflight failed on a stale M141 and then on M158 and M160 surviving; all three are fixed in this commit.
    - `PREFLIGHT_FIGURES=true` stubs the milestone-figures check, as before (id:xh0jq). The fuzz record `bench/fuzz/README.md` is stale after this `src/` change. **Check-in:** none of its own (`+AI-D`); the reproducers and sibling probes above were re-run before `tm done`.

- [x] +safety +tests +AI-D @provenance A call through a `fn` value stores only what its arguments and its own environment reach id:4by24
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Completed:** 2026-11-17 git:3da0668

    - **Found by:** id:nc3ym (root R3).
    - **Placed:** directly before id:z0065, which it blocks: id:z0065 newly refuses the safe twins below, and each over-rejection needs its own task done first.

    - **Now:** under `--provenance`, a call through a `fn` value with no summary (the unknown-call rule) is assumed to store anything the call can reach into anything it can reach, and the callee place itself counts as reached. Origin sets are per local for the whole body, so that also taints stores made earlier in the body. 480 safe store-grid twins are refused for this alone: carrier `closure_local`, destination `closure_owned_capture`, all ten paths and every container (`build/provenance/build/nc/only.txt`). The default mode accepts them, and they run correctly.
    - **Reduced program** (`build/provenance/build/z97/grid/work/closure_local__direct__direct__closure_owned_capture__frame_ends.twin.zrl`; default build exits 42, as the twin intends): `struct OwnedHolder { s: fn() -> i32, keep_non_copy: Vec<i32> }`; `let mut h = OwnedHolder { s: default_fn, .. }`, and a closure `c_owned` that owns `h` and either stores `h = OwnedHolder { s: routed, keep_non_copy: Vec::<i32>.new() }` (`routed` = the `fn` item `twin_fn`) or returns `h.s()`. Under `--provenance`, line 16 (the store) gives "a value holding an address of this frame is stored into memory that outlives it (store rule)". `--emit-origins` for `_closure_0`: `unknown-call <fn value>` and `h O={Env(h), Env(routed), Frame(h), Frame(_5), Static}`. Replacing `return h.s();` by `return 7;` makes it accepted (`build/provenance/build/nc/r3_nocall.zrl`).
    - **Also part of root R2 (id:nc3ym):** the 96 `closure_local` `same_param` twins stay refused once id:z0086 drops a `fn` item's `Static` from store targets. The tuple parameter makes `dest_val` appear to hold its own address, and `return dest_val();` is then refused by the unknown-call store rule (`build/provenance/build/nc/r2c.zrl`, line 15).
    - **Do:** decide whether an unknown call through a `fn` value can be limited to what its arguments reach, plus its own environment. A closure's environment is checked where the closure is made (the closure rule, id:z0096), and a `fn` item has none. If that is sound, then with no arguments the call cannot reach the caller's frame. Probe the sibling routes before relying on it: a closure capturing `&mut` to a local, stored into a `fn` field and then called; a `fn` value received as a parameter; a closure built in a loop; a `fn` value read from a global. A rule that removes refusals runs the rejection differential.
    - **Checks:** C1 the reduced program accepted under `--provenance`, with a test. C2 each sibling route above probed: refused where it is unsafe, with a test. C3 the store grid under `--provenance`: the 480 twins accepted, 0 unsafe cells accepted. C4 `make test`; `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, quoting the `fresh (no cache)` line.
    - **Cause (2026-11-17, compiler git:94c0ed2):** the rule was already "what the arguments and the environment reach"; the environment was read too wide. `os_unknown_arg` read the callee place with `os_read(.., ta, ta)`, so `h.s` brought `S(h)` too: the owned capture `h`'s `Vec` buffer, `Frame(h)` and `Frame(_5)`. The call then stored that frame-owned storage into what the environment reaches (`Env(h)`, external), which is the refusal at the call (now also reported, line 19, since id:z0086) and, through the flow-insensitive sets, the store rule at line 16. Reduced further (`build/provenance/build/4by24/a.zrl`): a closure owning `H { s: fn() -> i32, keep: Vec<i32> }` that only does `return h.s();` is refused; with `k: i32` for the `Vec` it is accepted. R2's `r2c.zrl` is the other half: `stash_pair`'s field-insensitive summary `store Param(0) -> Param(0)` gives `dest_val` `O={Frame(dest_val), Static, Rodata}`, and the environment of `dest_val()` is then `dest_val`'s own slot.
    - **Decided:** sound, in two parts. (1) The environment is read from what the callee value holds, not what its local owns (`S` dropped), as `os_read` through a pointer already drops a non-owning type's `S`. (2) Of the callee's `Frame` origins only a tuple local's is kept (`os_env_frames_only`): `build_closure_env` always makes the environment a tuple local `E` and the value `&E`, so another `Frame` is never where a `fn` value points; `Frame(E)` is still followed through, so the captures are reached. A `fn` value read from raw memory is the `unsafe` block's claim (design note §3). A local of unknown type keeps its `Frame`.
    - **Siblings probed** (`build/provenance/build/4by24/s*.zrl`, `provenance:` diagnostics counted with the base compiler `build/4by24/base/build/zoril`, git:94c0ed2, and with the change): a closure capturing a `&mut` parameter in a `fn` field called with a local's address (s1) 1/1; a closure capturing the parameter and a local's address in a field beside a scalar, called with no argument (s1b) 2/2; a `fn` value received as a parameter called with a local's address (s2) 1/1; a closure built in a loop over a reborrow (s3b) 2/2; a `fn` value read from raw memory behind a static (s4) 1/1, the refusal being `main`'s store of `&s` into the static; `*out` of a `&mut fn` parameter (s5) 2/2; a closure in a field taking `&mut [i32]` (s6) 1/1. Unchanged, all refused. A `static` cannot hold a `fn` value ("a static or constant cannot hold a function value"), so "a `fn` value read from a global" exists only through a raw pointer (s4). Tests: `fn_value_field_closure_stores_arg_refused.zrl` (s1), `fn_value_field_closure_stores_capture_refused.zrl` (s1b), `fn_value_loop_closure_refused.zrl` (s3b), `fn_value_param_frame_arg_stored_refused.zrl` (s2); raw memory is `fn_value_raw_slot_frame_arg_refused.zrl` already.
    - **Found, not this task's:** a `fn` item or a closure that stores its own parameter into a global, passed to `fn apply(f: fn(&i32), r: &i32) { f(r); }` with a local's address, is accepted by the new rules at base and after (s7, s8: 0/0); only the old rules refuse it. The design note claimed the closure form was refused at the call; corrected. New task id:4f0ew, placed before id:z0012 and added to its **Depends:**.
    - **Bound left:** `O` stays field-insensitive, so a `fn` field beside a `Vec` built in a parameter's arena (`H { s: read, keep: Vec.new_in(a) }`, then `(h.s)(&x)`) holds `Param(a)` and the call is still refused. Written in the design note; not seen in the grid or the tests.
    - The work is git:c4e1bb5 (the rule, six tests, the design note) and git:3da0668 (a seventh test, for the first half alone, and the design note's bound).
    - C1: `fn_value_owned_capture_field_call_accepted.zrl` (the reduced program, exit 42) and `fn_value_tuple_param_self_store_accepted.zrl` (R2's `r2c.zrl`, exit 42) pass; with the base compiler (git:94c0ed2) both are refused ("store rule" at line 17 and "unknown-call store rule" at 20; "unknown-call store rule" at 14). Each half taken out on its own: without (1) `fn_value_owned_tuple_capture_call_accepted.zrl` is refused (line 12:38, "unknown-call store rule") and the other two pass; without (2) `fn_value_tuple_param_self_store_accepted.zrl` is refused (14:12) and the other two pass.
    - C2: the siblings under **Siblings probed**, `provenance:` diagnostics base/new: s1 1/1, s1b 2/2, s2 1/1, s3b 2/2, s4 1/1, s5 2/2, s6 1/1; the four new `_refused` tests pass (`./scripts/test.sh tests/language/memory/provenance/fn_value_*.zrl`: `Total: 21 run, 21 passed, 0 failed, 0 skipped (0.2s)`).
    - C3: `ZORIL_CC=<zoril --provenance> sh scripts/check_store_grid.sh --dir build/4by24/grid/work ..` (copies of the records under `build/4by24/grid/`), with this change and with the base compiler (`build/4by24/gridb/`): `actual_names.txt` empty in both (0 unsafe cells accepted); twins refused 4694 (base) → 4118, 576 fewer and 0 more: the 480 `closure_local__*__closure_owned_capture__*` twins and the 96 `closure_local__*same_param*` twins (`build/4by24/removed_by_change.txt`). Against the default record (`bench/fuzz/store_grid_twin_rejections.txt`) 186 twins are refused by the new rules only, all `(ref_local|elem_ref)__(array_slot|struct_field|tuple_slot)__` (id:z0091). Both runs print `[FAIL] store-grid-modular: 125 entr(ies) of bench/fuzz/store_grid_modular_expected_failures.txt no longer hold`, the default-mode modular record read under `--provenance`, the same at base.
    - C4: `make test` at git:c4e1bb5's tree: `Total: 3782 run, 3782 passed, 0 failed, 100 skipped (252.3s)`. `PREFLIGHT_FIGURES=true REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=94c0ed2` at git:c4e1bb5, rc=0: "All mutations caught." (48 targeted); the gen3/gen4 fixpoint; `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`; `reject-diff: base verdicts: fresh (no cache); base front end 113 s` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69162 programs against 94c0ed2a482e7957f74a1120d0940d68442f85ed` (the rule acts only under `--provenance`; what it newly accepts there is the grid's 576 twins and the tests above, read); checked build `Total: 1444 run, 1444 passed, 0 failed, 0 skipped (107.7s)`; git group `Total: 8 run, 8 passed, 0 failed, 0 skipped (99.9s)`; "All performance thresholds within tolerance of baseline."; records committed on `records` (git:bcae77d, git:85308a6, git:14ace18, git:3e1bf51, local, not pushed). A first run without the `PREFLIGHT_FIGURES` stub (`PREFLIGHT_BASE` the merge base 150ba73) failed only `preflight-selftest` on the milestone figures (id:xh0jq's harness bug, fixed on `main`, not on this branch); its reject-diff also passed, 0/0 of 69162. After git:3da0668 (a test and the design note): `make test-changed BASE=HEAD` `Total: 3784 run, 3784 passed, 0 failed, 100 skipped (136.2s)`, before the commit.
    - `sh scripts/run_safety_matrix.sh`: `All probes complete: 473/522 passed. Mismatches: 0`.
    - **Stale:** `bench/fuzz/README.md`'s fuzz record (a change to `src/`). Milestone figures not touched.
    - **Check-in:** none: an `+AI-D` task, reviewed by the session that did it, with the reproducers and sibling routes above.

    - **Moved (2026-11-17):** to directly after id:z0086. The order (2026-11-17, the maintainer delegated it: "the order that gives us the best perspective on reaching the conclusion of this provenance series"): id:dhded, id:z0086, id:4by24, id:z0091, then the rest. id:dhded comes first because it settles the largest open question for the series' end, whether the invalidation holes can be refused statically without awkward code. The three precision tasks after it remove all 890 of id:nc3ym's newly refused twins: id:z0086 first (224 twins, and it unblocks id:95w4z), then id:4by24 (480 twins, a soundness question still open), then id:z0091 (186 twins, a known technique). After them the store grid shows what id:z0065 really costs.

- [x] +safety +tests +AI-D @provenance id:z0091 An assignment to a local's field replaces the origins the field held
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Check-in:** stop for review after it.
    > **Completed:** 2026-11-17 git:ff009df

    - **Found by:** id:z0075 (the grid's newly refused twins, read by root).
    - **Deferred (2026-11-06, by id:z0075):** accepted as a precision bound for now (id:z0065 records it in `KNOWN_ISSUES.md` §5); a removal rule, so it waits until the series' other rules are in.

    - **Now:** a direct assignment to a field of a local (`carrier_tup.0 = src_val`) adds the new value's origins to the local and keeps the old field's: no strong update. The store grid's safe twins `{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{same_param,store_param_65}__{deref_out,field_out}__frame_ends` (18 cells) are refused under `--provenance` by "the callee stores an address of this frame into memory that outlives it (call store rule)": in `ref_local__tuple_slot__same_param__deref_out__frame_ends.twin.zrl`, `let mut carrier_tup = (&seed, 10); carrier_tup.0 = src_val; let carried = carrier_tup.0;` leaves `carried O={Param(1), Frame(seed)}`, and `stash_pair((out, carried))` stores `Frame(seed)` into the caller's `*out`. The cells are written by `sh scripts/check_store_grid.sh --dir DIR` (as `DIR/<cell>.twin.zrl`); run it with `ZORIL_CC` set to a wrapper that adds `--provenance`, as id:z0064 did.
    - **Do:** a strong update for an assignment straight to a local's own field, array slot or tuple slot (no pointer on the path, no loop joining the old value back in), stated in the design note §3. It removes origins, so the series rule applies: probe the field assigned on one branch only, inside a loop, through a `&mut` to the local, through a reborrow, and an element of a local array indexed by a variable (which must stay a weak update). Then remove the 18 cells' refusal and the `KNOWN_ISSUES.md` §5 entry. `make test`, `make preflight-changed`, the rejection differential, the store grid.

    - **Measured by id:nc3ym (2026-11-17, compiler git:3e34cc3):** 186 safe store-grid twins are refused under `--provenance` for this cause, not only the 18 that id:z0065 accepts. All are `ref_local`/`elem_ref` carriers in `array_slot`, `struct_field` or `tuple_slot`, through `closure_capture_mut` (60), `closure_owned_capture` (60), the `fn_val` path (54), `closure_call_mut` (6) and the 18 already accepted. Representative: `ref_local__array_slot__closure__closure_capture_mut__frame_ends`; the default build exits 42. Giving the field its final value when the local is built (`[src_val]` for `[&seed]`) makes it accepted (`build/provenance/build/nc/r1b.zrl`), and the same goes for the `closure_owned_capture` and `fn_val` representatives (`r1_init.zrl`, `r1c.zrl`). The pattern (a placeholder value, then an assignment) is ordinary code, so id:nc3ym recommends promoting this task before id:z0065.

    - **Promoted (2026-11-17, the maintainer's decision on id:nc3ym's recommendation):** from `future.tm.md` to directly after id:4by24, with a **Branch:** line and the `@provenance` tag. The 186 twins are ordinary code (a placeholder, then an assignment), so they are fixed rather than accepted as a bound. Its 2026-11-06 deferral (a removal rule waits until the series' other rules are in) is kept by placing it after id:z0086 and id:4by24. The order (2026-11-17, the maintainer delegated it: "the order that gives us the best perspective on reaching the conclusion of this provenance series"): id:dhded, id:z0086, id:4by24, id:z0091, then the rest. id:dhded comes first because it settles the largest open question for the series' end, whether the invalidation holes can be refused statically without awkward code. The three precision tasks after it remove all 890 of id:nc3ym's newly refused twins: id:z0086 first (224 twins, and it unblocks id:95w4z), then id:4by24 (480 twins, a soundness question still open), then id:z0091 (186 twins, a known technique). After them the store grid shows what id:z0065 really costs.
    - **Decided (2026-11-17):** the sets stay flow-insensitive, so a strong update is stated as a dead element of the literal, not as a kill at the assignment: for a local `L` with one `Let` of a tuple, struct or array literal, an element that a later statement of the same block overwrites whole (`L.f`, `L.0`, `L[k]` with `k` a local only ever holding one constant, or `L` itself for all elements) before any statement reads `L`, takes its address or names it as an index (the assignment's own value included) is left out of the `Let` (`os_dead_inits`, `os_live_elements`). A local whose address is taken anywhere in the body keeps its literal whole: a raw pointer made on an earlier pass through a loop can read the placeholder in the window, which nothing else in the window names. The design note §3 states it (_An element overwritten before it is seen_). All 186 twins are this shape: `let mut carrier_tup = (&seed, 10); carrier_tup.0 = src_val;` straight after one another.
    - **Probes** (`build/provenance/build/z91/*.zrl`, `provenance:` diagnostics with the base compiler git:3da0668 / with the change; each is a test now, named in brackets): the field assigned on one branch only (u1, `placeholder_overwritten_on_one_branch_refused`) 1/1; inside a loop (u2, `..._in_loop_refused`) 1/1; read before the assignment (u3, `placeholder_read_before_overwrite_refused`) 1/1; copied whole before it (u4, `..._copied_before_overwrite_refused`) 1/1; an array element at a variable index (u5, `..._variable_index_overwrite_refused`) 1/1; one of two slots at a constant index (u12, `placeholder_other_slot_refused`; u6 with a literal index) 1/1; one of two fields (u8, `placeholder_other_field_refused`) 1/1; an assignment reading the placeholder slot (u7, `placeholder_overwrite_reads_itself_refused`) 1/1; read through a reborrow of a `&mut` to the tuple before the assignment (u10, `placeholder_read_through_reborrow_refused`) 1/1; a tuple built in a loop and stored out before its slot is overwritten (u13, `placeholder_read_in_loop_before_overwrite_refused`) 1/1; a nested struct, inner field untouched (u11) 1/1; read through a raw pointer to the previous iteration's tuple (u14, `placeholder_read_through_stale_raw_pointer_refused`) 1/1, and with the address-taken safeguard taken out it is accepted under `--provenance` (only the old rules' "region escape" remains), so the safeguard is what refuses it. Through a `&mut` to the local (u9, `let r = &mut t; r.0 = p;`) stays refused, a weak update as intended (safe at run time; a precision bound, no test). The accepted forms (a tuple slot, both fields, both array slots at constant indices, the whole tuple reassigned) are `placeholder_overwritten_accepted.zrl`, refused 4 times by the base compiler.
    - **Found, not this task's:** probing u10 without `--provenance` showed the default rules accept a frame view read through a local reference to a local aggregate and stored out or returned (`let s = S { v: &x }; let r = &s; *out = r.v;`, exit 77 after a clobber; also a tuple slot, an array element, a `&mut`, a reborrow, `&r`, a copy stored later, `return r.v`, and a callee storing `s.v` through its reference parameter: `build/z91/h1.zrl`-`h9.zrl`, `h5b.zrl`), all refused under `--provenance`. The same on `main` (git:8100386). A public-side hole (checked code the compiler wrongly accepts): `known_gap` probe `gap_97` with its Known gaps entry and class (N) in `doc/SAFETY.md` §6 (git:ff009df); id:z0065 flips it (bullet added there).
    - The work is git:5d0c6ea (the rule, thirteen tests, the design note); git:ff009df is the probe found on the way.
    - _Store grid_ (`ZORIL_CC=<zoril --provenance> sh scripts/check_store_grid.sh --dir build/z91/grid/work ..`, copies of the records under `build/z91/grid/`): `actual_names.txt` empty (0 unsafe cells accepted); twins refused 4118 (id:4by24's run) → 3932, 186 fewer and 0 more, all `(ref_local|elem_ref)__(array_slot|struct_field|tuple_slot)__`; `comm` against `bench/fuzz/store_grid_twin_rejections.txt` is 0 either way, so the new rules refuse exactly the default's twins. The `[FAIL] store-grid-modular: 125 entr(ies) ... no longer hold` line is the default-mode modular record read under `--provenance`, as at id:4by24's base.
    - _`KNOWN_ISSUES.md` §5:_ no entry for this class was ever written (id:z0065 did not run), so none is removed.
    - _`make test`_ at git:5d0c6ea's tree: `Total: 3808 run, 3808 passed, 0 failed, 100 skipped (136.4s)` (a first run failed `fmt-check` and so `mutation-self-test` on `src/check_zir.zrl`, fixed by `zoril fmt` before the commit). `sh scripts/run_safety_matrix.sh`: `All probes complete: 473/522 passed. Mismatches: 0`; after git:ff009df `473/523 ... Mismatches: 0`, `sh scripts/check_safety_model.sh` `PASS: safety_model.md is self-consistent.`, and `make test-changed BASE=HEAD` `Total: 3808 run, 3808 passed, 0 failed, 102 skipped (136.9s)` before that commit.
    - _`PREFLIGHT_FIGURES=true REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=3da0668`_ at git:5d0c6ea, rc=0: "All mutations caught." (48 targeted); the gen3/gen4 fixpoint; `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`; `reject-diff: base verdicts: fresh (no cache); base front end 114 s` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69162 programs against 3da0668d694bc843528ea2321f713d158c9e2ea0` (the rule acts only under `--provenance`; what it newly accepts there is the grid's 186 twins and the accepted test, read); checked build `Total: 1457 run, 1457 passed, 0 failed, 0 skipped (107.7s)`; git group `Total: 8 run, 8 passed, 0 failed, 0 skipped (100.0s)`; "All performance thresholds within tolerance of baseline."; records on `records` (git:e61ab09, git:8049cbf, git:cf53289, git:cb45e34, local, not pushed). The stub is for id:xh0jq's harness bug, as at id:4by24.
    - **Stale:** `bench/fuzz/README.md`'s fuzz record (a change to `src/`). Milestone figures not touched (the probe counts in `doc/SAFETY.md` §5.1, §6 and `README.md` were not updated for `gap_97`).
    - **Check-in:** none: an `+AI-D` task, reviewed by the session that did it, with the probes above.

- [x] +safety +tests +AI-D @provenance id:z0087 B1.9c An integer popped from a collection carries no address
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Depends:** id:z0075, id:z0094, id:0m61c
    > **Check-in:** stop for review after it.
    > **Completed:** 2026-11-17 git:0c3ea8c

    - **Found by:** id:z0064 (root (f)).
    - **Routed (2026-11-06, by id:z0075):** a rule, though only `src` shows the class (6 warnings): it adds a type fact (an integer holds no address), the cheapest of the rules to state, and the exemption for a primitive result exists already.

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
    - **Decided (2026-11-17):** the exemption is a type fact: a result type holding no pointer, slice, box or `fn` value at any depth (`os_holds_pointer`; an unknown type or a type variable counts as holding one) has a body summary's `ParamContents` ties dropped, as an integer result had; `ParamAddr` ties (`p as usize`) still count. Sound for the reason the integer case is: such a result can carry an address only as an integer, and making an address of an integer needs `unsafe`. Storing an integer derived from a frame address into a global was accepted before as well (`build/z87/q1.zrl`-`q3.zrl`: a `usize` result, an `Option<usize>` with a contents tie and one with an address tie, 0/0 `provenance:` diagnostics at base and after), the boundary id:z0071 decided.
    - **Probes** (`build/z87/`, `provenance:` diagnostics at base git:ff009df / after; each a test): the reduction `f1.zrl` 2/0 (`popped_integer_carries_no_address_accepted.zrl`, exit 0); a struct of counts read through `&(&x, 3)` (`a1`, `integer_struct_result_carries_no_address_accepted.zrl`, exit 3) 1/0; kept ties: an `Option<&i32>` popped from a `Vec<&i32>` holding `&x` (`p1`, `popped_reference_keeps_tie_refused.zrl`) 1/1, a struct with a slice field (`p2`, `struct_with_slice_result_keeps_tie_refused.zrl`) 1/1, a tuple `(usize, &i32)` (`p3`, `tuple_with_reference_result_keeps_tie_refused.zrl`) 1/1. Not covered, as the task says: a non-integer value popped and moved into a returned `Vec`.
    - **`src` under `--provenance=warn`** (`build/zoril -I stdlib=stdlib -I src -I build/gen src/main.zrl --provenance=warn --emit-zil -o /dev/null`): 199 → 193 warnings; the six gone are exactly `src/fmt/doc.zrl:111` (twice), `:151`, `src/fmt/fmt.zrl:76`, `:122`, `:131`. The 193 left are 168 "call store rule" into a global and 25 into memory that outlives the frame, 116 of them in `src/lower_zir/expr.zrl`; their cause was not read here.
    - _Store grid_ (`build/z87/grid/`, `--provenance`): `actual_names.txt` empty; twins refused 3932, identical to id:z0091's run (0 removed, 0 added).
    - _`make test`_ at git:0c3ea8c's tree: `Total: 3818 run, 3818 passed, 0 failed, 102 skipped (253.8s)`. `sh scripts/run_safety_matrix.sh`: `All probes complete: 473/523 passed. Mismatches: 0`. `build/zoril-stage1` compiles `src/main.zrl` (rc 0) and `zoril fmt --check src/check_zir.zrl` rc 0.
    - _`PREFLIGHT_FIGURES=true REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=ff009df`_ at git:0c3ea8c, rc=0: "All mutations caught." (48 targeted); the gen3/gen4 fixpoint; `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`; `reject-diff: base verdicts: fresh (no cache); base front end 114 s` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69163 programs against ff009df537f32a64505d767ac2a1b94f094fc043` (the rule acts only under `--provenance`; what it newly accepts there is the two accepted tests above and the six `src/fmt` sites, read); checked build `Total: 1462 run, 1462 passed, 0 failed, 0 skipped (107.8s)`; git group `Total: 8 run, 8 passed, 0 failed, 0 skipped (100.0s)`; "All performance thresholds within tolerance of baseline."; records on `records` (git:59f0075, git:e245d50, git:52f7516, git:4784c6e, local, not pushed).
    - **Stale:** `bench/fuzz/README.md`'s fuzz record (a change to `src/`). Milestone figures not touched.
    - **Check-in:** none: an `+AI-D` task, reviewed by the session that did it, with the probes above.

- [x] +safety +tests +AI-D @provenance id:z0084 B1.9d Arena storage is named by the arena an argument reaches, not by the argument's address
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Depends:** id:z0075
    > **Check-in:** stop for review after it. Accepts more: the rejection differential and the series rule apply.
    > **Completed:** 2026-11-17 git:dadd49e

    - **Found by:** id:z0064 (root (d1)).
    - **Depends note:** (it decides whether over-rejections are fixed by rules).
    - **Deferred (2026-11-06, by id:z0075):** the root is seen only in code that uses a raw arena (zbuild's manifest parsing, the compiler), which is `unsafe` already; id:z0090 changes zbuild's sites instead, and none of the grid's or the tests' refusals is from it. Take this rule up when safe user code shows the class, with the reproducer below.
    - **Promoted (2026-11-15, the check-in id:n177h):** safe user code now shows the class (the reproducers in **Safe user code** below), so the deferral's condition is met. Placed before id:z0089 and id:z0090: it blocks id:z0065 (the default flip would refuse these safe programs, and id:z0065 asks that each over-rejection have its own task done first), and it may make id:z0090's zbuild changes unnecessary (its measurement alone took zbuild from 25 warnings to 0), so it runs before that `+AI-G` batch rather than after it.

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
    - **Decided (2026-11-17):** a pointer argument names an arena's storage by the memory the arena lies in. The type gives the number of pointers from the argument to memory holding an `Arena` or `ArenaHeader` in place (`os_arena_depths`, a bit per depth): depth 1 (`&Arena`, `*mut ArenaHeader`, `&H` with `H { ar: Arena }`) keeps the argument's own origins, as before; depth k takes what the argument reaches through k - 1 more pointers (`os_arena_at_depths`): `&Vec<T>` is depth 2 (its `raw` field), `&H` with `H { a: &Arena }` depth 2, `&W` with `W { inner: &H }` depth 3. The pointers inside an arena (its C blocks) are not followed, which keeps id:z0082's rule (`arena_unwrap_static_then_push_accepted.zrl` failed until they were not). A type variable, an unknown type or a path past eight pointers takes everything the argument reaches. Sound because each step's sets over-approximate what the memory holds; the argument's own address was never where the arena is unless it is in place. Design note §3, _Details the transfer needs_.
    - **What it fixes:** id:z0090's `W | grep -c 'warning: provenance'` 21 → 0 (its record said 25; the tree had 21 at git:0c3ea8c, listed by site in this session's log `build/z84/`); the reduction `d5.zrl` 7 → 0 (`arena_named_through_vec_reference_accepted.zrl`, exit 0). `src/main.zrl` stays at 193.
    - **P1 to P5 are another root:** none changes with this rule. P1 to P3 are refused by the return rule on `O`, through the `Clone` summary's `ParamContents` tie, which the caller maps to the `Vec`'s buffer as well; P4 inside `Vec.resize` on a by-value parameter's clone; P5's push by its storage in the caller's arena. Diagnosis, a measurement and the decision to make are in the new task id:sjqmy, placed before id:z0065 and added to its **Depends:**. So the **Checks to add when this task is settled** move there: P1 to P5, `clone_returned_accepted.zrl`, and `vec_clone_frame_views_returned_refused.zrl` (still refused with `v.push(&buf)` taken out, so its refusal is still P1's).
    - **Siblings probed** (`build/z84/a1.zrl`-`a7.zrl`, `provenance:` diagnostics at base git:0c3ea8c / after, all 1/1, the default rules refuse each too): a `Vec` built by a callee in a local arena reached through an `&Arena` struct field (a1, test `arena_ref_in_struct_field_local_refused.zrl`), an arena held by value in a struct passed by reference (a2, `arena_in_struct_by_value_local_refused.zrl`), a clone of a local-arena `Vec` stored out (a3), a struct packing a view beside an `&Arena` (a4), a callee cloning a `Vec` built in a local arena (a5, `arena_vec_clone_local_refused.zrl`), a callee given `&Vec` beside a local `&Arena` (a6), two struct references to a local arena (a7, `arena_two_references_deep_local_refused.zrl`). `arena_reset` between the call and a read is the liveness class (id:dhded), which these rules do not check; not probed here. The safe twins in `build/z84/t1.zrl` (the same shapes over a parameter's arena) are refused by the default rules, so they are no `--provenance` test; under `--provenance` `ok` and `ok_v` are accepted after and refused before, `ok_w` is still refused, by id:sjqmy's root (`O` of the result holds `Frame(h)` through the tie).
    - _Store grid_ (`build/z84/grid/`, `--provenance`): `actual_names.txt` empty; twins refused 3932, identical to id:z0087's run.
    - _`make test`_ at git:dadd49e's tree: `Total: 3828 run, 3828 passed, 0 failed, 102 skipped (254.5s)` (a first run, before the arena's own pointers were left out, failed `arena_unwrap_static_then_push_accepted.zrl`, the `origins` scenario and so `mutation-self-test`). `sh scripts/test_origins.sh` rc 0. `sh scripts/run_safety_matrix.sh`: `All probes complete: 473/523 passed. Mismatches: 0`. `build/zoril-stage1` compiles `src/main.zrl` (rc 0); `zoril fmt --check src/check_zir.zrl` rc 0.
    - _`PREFLIGHT_FIGURES=true REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=0c3ea8c`_ at git:dadd49e, rc=0: "All mutations caught." (48 targeted); the gen3/gen4 fixpoint; `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`; `reject-diff: base verdicts: fresh (no cache); base front end 114 s` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69163 programs against 0c3ea8c0ff8d4647d8704ca8add6f87e56cd5933` (the rule acts only under `--provenance`; what it newly accepts there is zbuild's 21 sites, `d5.zrl` and `t1.zrl`'s `ok` and `ok_v`, read: each `Vec` is built in a parameter's arena); checked build `Total: 1467 run, 1467 passed, 0 failed, 0 skipped (107.7s)`; git group `Total: 8 run, 8 passed, 0 failed, 0 skipped (99.9s)`; "All performance thresholds within tolerance of baseline."; records on `records` (git:eee9a50, git:ae13a4e, git:772c259, git:e56f634, local, not pushed).
    - **Stale:** `bench/fuzz/README.md`'s fuzz record (a change to `src/`). Milestone figures not touched.
    - **Check-in:** none: an `+AI-D` task, reviewed by the session that did it, with the probes above.

- [x] +refactor +tests +AI-G @provenance id:z0089 B1.9f `exh_expand_or` pushes a fresh copy of each row it keeps
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Depends:** id:0m61c
    > **Completed:** 2026-11-17 git:5c44f2b

    - **Found by:** id:z0064 (root (d2)).
    - **Routed by:** id:z0075, to a code change at the site; the rule is deferred (id:z0085 in `future.tm.md`).

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

    - **Finding (2026-11-17):** change committed (see `git log --grep 'Task: id:z0089'`). C1: 193 and 168. C2: 183 and 14. C3, C4 (no warnings), C5 (`Total: 7 run, 7 passed, 0 failed, 0 skipped`) pass. `make test`: `Total: 3828 run, 3828 passed, 0 failed, 102 skipped (137.5s)`. `make preflight-changed`: `Total: 8 run, 7 passed, 1 failed` — the one failure is the `preflight-selftest` scenario, whose log shows only `safety-figures` mismatches (§5.3 rows, density, probe counts 519 vs 523 / 46 vs 50): milestone figures, not touched by this change. Not complete until the maintainer says whether to ignore or refresh them. Next: `make preflight-changed` again after that is settled.

    - **Completion:** code in `1033c46` (the copy) and `5d8c6a9` (preflight no longer runs the milestone figures check, which failed `preflight-selftest`; `make figures-check` stays the by-hand milestone check).
      - C1: 193 warnings, 168 `into a global` (expected 195/167). C2: 183 and 14 (expected 185/14; drops of 10 and 154). C3: `git diff --stat` named only `src/lower_zir/exhaust.zrl` (8 insertions, 1 deletion). C4: `rm build/zoril && make`, then `make`: no `warning:` lines. C5: `Total: 7 run, 7 passed, 0 failed, 0 skipped (0.1s)`.
      - C6: `make test`: `Total: 3828 run, 3828 passed, 0 failed, 102 skipped (138.3s)`. `make preflight-changed`: `Total: 8 run, 7... ` first run failed only on milestone figures; after `5d8c6a9`: `Total: 8 run, 8 passed, 0 failed, 0 skipped (100.2s)`, reject-diff base verdicts line was cached (not `REJECT_DIFF_NO_CACHE=1`).
      - The fuzz record (`bench/fuzz/README.md`) is stale for `src/`.

- [x] +tools +tests +AI-G @provenance id:z0090 B1.9g zbuild's manifest parsing gives no warning under `--provenance`
    > **Created:** 2026-11-06
    > **Branch:** `provenance`
    > **Depends:** id:0m61c, id:z0084
    > **Completed:** 2026-11-17 git:5c44f2b

    - **Found by:** id:z0064 (root (d1)).
    - **Routed by:** id:z0075, to code changes at zbuild's sites; the rule was deferred (id:z0084, promoted 2026-11-15 and placed before this task).

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

    - **Completion:** no code change (the task's own rule for C1 = 0, after id:z0084).
      - C1: `W | grep -c 'warning: provenance'` printed `0` (tree at `5d8c6a9`).
      - C2 to C5: not run: no warning left to remove.
      - C6: `make test-changed BASE=HEAD`: `Total: 3828 run, 3828 passed, 0 failed, 102 skipped (138.1s)`. `make preflight-changed` not run: no code changed.

- [x] +safety +review +AI-D @provenance @checkin Review of `exh_expand_or`'s row copy and zbuild's manifest warnings (id:z0089, id:z0090) id:7kbpd
    > **Created:** 2026-11-15
    > **Branch:** `provenance`
    > **Depends:** id:z0089, id:z0090
    > **Completed:** 2026-11-18 git:5c44f2b

    - **Placed:** after id:z0090 by the check-in id:n177h, to review the `+AI-G` batch id:z0089 and id:z0090 before the next task (id:z0073) starts.

    - **Checks:**
      - Re-read the queue and `git log -p` since the commit of the last `+AI-D` task before id:z0089.
      - id:z0089: re-run its C1 and C2 (the two warning counts over `src/main.zrl`) and read the diff (the copy loop and one comment only; `src/` still builds through stage1, `rm build/zoril && make`).
      - id:z0090: re-run its C1 after id:z0084; if it changed code, its C3 (no new `unsafe`) and C4 (the manifest unchanged, `cmp`).
      - Probe the sibling sites: the other `out.push(row)`-style pushes of a row read out of a referenced `Vec` in `src/lower_zir/`, and any warning left in `tools/zbuild` under `--provenance=warn`.

    - **Review (2026-11-18), tree at `5d8c6a9`:**
      - **Queue:** re-read. Since id:z0084 (`dadd49e`, the last `+AI-D` commit before the batch), the batch added `1033c46` and `5d8c6a9`, both `Task: id:z0089`; z0090 changed no code.
      - **id:z0089, the copy (`1033c46`): correct.** C1/C2 re-run: 183 `warning: provenance` and 14 `into a global` on `src/main.zrl`. With the copy taken out (a scratch copy of `src/` with `1033c46~1`'s `exhaust.zrl`, same compiler): 193 and 168, so the check can see the defect. The diff is the copy loop and one comment. `rm build/zoril && make`: 0 `warning:` lines, `Built: the toolchain is up to date in build/ ...`; then `make`: `Up to date: ...`. The compiler built from `1033c46~1` and `build/zoril` emit identical ZIL for `src/main.zrl` (`cmp`). Rejection differential, which z0089's note cited only from a cached run: `REJECT_DIFF_NO_CACHE=1 sh scripts/check_reject_diff.sh dadd49e` printed `reject-diff: base verdicts: fresh (no cache); base front end 114 s` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69163 programs against dadd49e`.
      - **The copy's cost:** none measurable. Old against new compiler: `src/main.zrl` takes 3.8 to 4.1 s for both; a 216-arm match with or-patterns takes 330 ms against 329 ms. It is an extra allocation per kept row at each usefulness node, on top of `exh_specialize`'s own per-row copy: a constant factor, not a new order. Measuring it found a blowup that both compilers share: id:1cgc9 (`future.tm.md`).
      - **The comment** reads the rules' imprecision as a fact about the program ("an address into its buffer"; the row points into the lowerer's arena). Not worth a commit of its own: recorded on id:z0085, together with taking the copy out when that rule lands.
      - **id:z0089, `5d8c6a9`: outside the task, and against a maintainer decision.** It removed `check_safety_figures.sh --milestone` from `make preflight` and rewrote `AGENTS.md`'s `make preflight` bullet. id:141h5 records the maintainer's decision of 2026-11-15 that "`make preflight` runs it (the release bar)", and z0089's own finding of 2026-11-17 said to wait for the maintainer. The cause of the failure was a missing `PREFLIGHT_FIGURES` stub in `scripts/test_preflight.sh`. The commit also left `doc/developer_guide.md:201` saying that preflight runs `make figures-check`. I have not reverted it (AGENTS.md: a conflicting change is reported, never silently reverted). The follow-up is id:837pd at the top of `active.tm.md`, with its check-in id:yf17t.
      - **id:z0090:** C1 re-run on the tree after id:z0084: `0`, so no code change, as its rule says; C3 and C4 do not apply.
      - **Sibling sites:** every other row push in `src/lower_zir/exhaust.zrl` (`exh_specialize`, `exh_default`, `exh_useful`'s literal branch, the arm rows) pushes a freshly allocated row, and no other `src/lower_zir/` function takes a `&Vec` of rows. `exhaust.zrl` has no provenance warning left; the 183 are in `lower_zir/expr.zrl` (116), `driver/module.zrl` (22), `lower_zir/stmt.zrl` (19), `lower_zir/lower_match.zrl` (17) and five others. Under `--provenance=warn`: `tools/zbuild`, `tools/zilc`, `tools/zman` and `tools/ztest` each give 0.
      - **Note gaps in the batch:** z0089's C6 cited a cached differential (made good above). z0090's C6 quotes `make test-changed BASE=HEAD` with a full-suite count (3828 run); not re-run, since no code changed.
      - **Plan edits:** added id:837pd (top of `active.tm.md`, `+AI-G`) and id:yf17t (its `@checkin`, after it); added id:1cgc9 to `future.tm.md` under the `main` heading; appended a bullet to id:z0085. Nothing moved, re-tagged or re-prioritized. The next `+AI-G` batch (id:z0066) already has its check-in (id:h1yk5).

- [x] +safety +decision +AI-D @provenance id:z0073 B1.8b Decide whether storing a raw pointer into a by-value owner's buffer, then dropping the owner, is refused
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Depends:** id:0m61c, id:7kbpd
    > **Completed:** 2026-11-18 git:5ca36fb

    - **Found by:** the review of id:z0071.
    - **Note:** Decision first; the fix or the probe is the next step it names.

    - **The case:** `struct Buf { data: *mut u8 }` with `Drop` freeing a heap block; `fn keep(out: &mut *mut u8, b: Buf) { *out = b.data; }` and `fn f(out: &mut *mut u8) { let b = Buf.new(); keep(out, b); }` (`tests/language/memory/provenance/addr_edge_by_value_owner_refused.zrl` at `403a092`), and the twin storing `BothPtr { own_v: Vec::<i32>.new(), p: b.data }` (`build/z71r/c2.zrl`). Accepted by the old rules and by `--provenance` at `a1ea096`; the caller's pointer is left dangling once `keep` drops `b`. Only `403a092` refused the first form, through the edge kinds id:z0072 removes.
    - **Question:** the stored value is a raw pointer, dereferenced only in `unsafe`. id:z0063 decided that the new rules check a raw pointer's origins (`Raw` is exempt only as a value). Does that make this a hole (a `known_gap` probe now, a fix that tells a moved owner from an address read out of it without per-store kinds), or is a dangling raw pointer outside the guarantee (record it in `doc/spec/safety_model.md` and `doc/spec/unsafe_policy.md`, with a test showing the accept)?
    - **Removed in `403a092` (id:z0072), until this is decided:** the test's full text is in `git show 403a092:tests/language/memory/provenance/addr_edge_by_value_owner_refused.zrl`; at `403a092` it compiles under `--provenance` and in the default mode.
    - **A sibling route (found in id:z0076, 2026-11-05):** an owner holding a raw pointer to memory outside the frame, whose safe method stores an argument through it (`put(self: &mut G, r: &i32) { unsafe { *self.p = r; } }` called with `&x`), is accepted in both modes: the destination reach does not follow a `*mut` an owner holds (`os_type_has` answers no for `RawPtrMut(x)` under `OS_Q_HANDLE`). Program in id:z0076's text (`build/z76/cx.zrl`). Decide it with this case: a raw pointer's target is the `unsafe` author's claim, or the call rule follows it.
    - **Two more sibling routes (found in id:z0076, 2026-11-06):** a frame address stored through the result of a `#[fresh]` function (`tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`) or through a heap block from `zoril_allocator_alloc(null, ..)` (`heap_block_store_through_old_rule_refused.zrl`), the pointer then returned, or the block put into a global (`heap_block_into_global_old_rule_refused.zrl`): any destination of the pointer. Since id:z0076 the new rules accept all three: the result has no origins, so a store through it reaches nothing they follow, as with a raw pointer an owner holds. The old region rule refuses all three in every mode today. Decide them with the case above: if a dangling raw pointer is outside the guarantee, say so in `doc/spec/safety_model.md`; if not, the store through a raw pointer with no origins needs a target (the fresh storage of the local holding it, say) before id:z0012 removes the old rule.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **Decided (the maintainer, 2026-11-14, in a review of the plan):** the three cases are decided apart. **A** (a raw pointer value left dangling: `keep(out, b)` copies `b.data` out and `b`'s `Drop` frees the block; the `BothPtr` twin): outside the guarantee. A raw pointer in checked code carries no promise about what it points to; the dereference is in `unsafe`, where the programmer checks, and the checker cannot know that an owner owns what its raw pointer field points to. **B** (a safe function whose `unsafe` block stores an argument through a raw pointer an owner holds: `put(self: &mut G, r: &i32) { unsafe { *self.p = r; } }`): outside the guarantee as to inference, but the store may not go undeclared: such a function must carry `#[stores(..)]`, and its callers are then checked by the call rule. That rule is written into id:z0011, with the bare-`extern` rule already proposed there. **C** (a frame address stored through a `#[fresh]` result or a heap block that then leaves the frame): decided by a measurement, id:71a06, before id:z0012 deletes the old rule that refuses it today.
    - **Left to do in this task:** state case A in `doc/spec/safety_model.md` and `doc/spec/unsafe_policy.md` (a raw pointer value may dangle; what is checked is the value side of id:z0063 and the dereference), with `addr_edge_by_value_owner_refused.zrl` (`git show 403a092:tests/language/memory/provenance/addr_edge_by_value_owner_refused.zrl`) restored as a test of the accept under a name that says so, and the `BothPtr` twin beside it. C1 both tests pass in the default mode and under `--provenance`; quote them. C2 `sh scripts/check_safety_model.sh` passes. C3 `make test-changed`, its `Total:` quoted.
    - **Done (2026-11-18, git:5ca36fb):** the test text was not at `403a092` (that commit removed it) but at `ad9045c`; restored as `tests/language/memory/provenance/raw_ptr_from_dropped_owner_accepted.zrl` (now `expected exit 0`, with a `main` that runs `f`), and the `BothPtr` twin (whose `build/z71r/c2.zrl` is gone; rebuilt from the archive's `keep_both` text with `Buf` freeing its block in `Drop`) as `raw_ptr_in_owner_from_dropped_owner_accepted.zrl`. Added the frame twin `raw_ptr_to_frame_from_by_value_owner_refused.zrl` (`Buf { data: &mut x as *mut u8 }` moved to `keep`): refused under `--provenance` by the call store rule, so the spec's line between the two (the address a raw pointer value carries is checked, the lifetime of the heap storage it points to is not) is pinned on both sides. Stated in `doc/spec/safety_model.md` (**A raw pointer value may dangle**, after "Raw pointers in checked code") and `doc/spec/unsafe_policy.md` §1.
    - **Found, not this task's (2026-11-18):** the frame twin is accepted by the default rules, and so is its reference form: `fn keep(out: &mut &i32, c: Carrier) { *out = c.v; }` called as `keep(out, Carrier { v: &x })`, exit 77 after a clobber; also a tuple, an array, a nested struct, a method's by-value `self`, a `let` copy or a destructuring pattern in the callee, and `*out = c` whole (`build/provenance/build/z73/s_*.zrl`, `r_*.zrl`, `gapA.zrl`). `*out = c.v` in the frame and a callee returning `c.v` (`gap_14`) are refused. The same on `main`'s `build/zoril` (main at git:a484d11). All refused under `--provenance`. A public-side hole: `known_gap` probe `gap_98` with its Known gaps entry and class (O) in `doc/SAFETY.md` §6 (git:43b8f17); id:z0065 flips it (bullet added there).
    - **Completion (2026-11-18):** the work is git:5ca36fb (tests and spec text); git:43b8f17 is the probe found on the way. C1: `./scripts/test.sh tests/language/memory/provenance/raw_ptr_*.zrl` (under the tests' `--provenance` flag) `Total: 5 run, 5 passed, 0 failed, 0 skipped (0.1s)`; the two accepted tests with their `// flags:` line removed (`build/z73/*_default.zrl`, the default mode) `Total: 3 run, 3 passed, 0 failed, 0 skipped (0.1s)`, each `[PASS]` at exit 0. C2: `sh scripts/check_safety_model.sh` `PASS: safety_model.md is self-consistent.`; `sh scripts/run_safety_matrix.sh` `All probes complete: 473/524 passed. Mismatches: 0` (`gap_98` reported `[SKIP]`, known gap). C3: `make test-changed BASE=HEAD~2` after both commits: `Total: 3834 run, 3834 passed, 0 failed, 104 skipped (137.7s)`. No compiled code changed (`src/`, `stdlib/`, `tools/` untouched), so `make test` and `make preflight-changed` were not run and the fuzz record is not made stale. Milestone figures not touched (the probe counts in `doc/SAFETY.md` §5.1, §6 and `README.md` are not updated for `gap_98`).

- [x] +safety +syntax +AI-D @provenance B3a0 `#[unsafe(borrows(..))]`: a trusted narrowing of a result's ties, marked at the point of trust id:akapm
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Completed:** 2026-11-18 git:e9726d2

    - **Decided by:** the maintainer, 2026-11-18 (recorded in `doc/design/provenance.md` §3, _Checked contracts_, tier 3). A plain `#[borrows(..)]` is a checked contract. `#[unsafe(borrows(..))]` is the only form the compiler trusts when it names less than the body returns. The function stays safe to call; the `unsafe` in the attribute is the marker. Making the function an `unsafe fn` instead was rejected because it would put `unsafe` on every caller.
    - **Placed:** before id:mztqb, whose `Args.get`/`Args.next` sites need it.
    - **Do:** parse `#[unsafe(borrows(..))]` (`src/parser/decl.zrl`'s attribute reader; stage1 must still parse `src/`, which this does not touch), carry it as `has_borrows` plus a `borrows_trusted` flag on `FnDecl` and `ILFunction`, write it into the `.zri` as written, count it in `scripts/marker_density.sh`, and make `scripts/check_safety_comments.sh` require a `// SAFETY:` line above it in `stdlib/`. Document it in `surface_syntax.md` §2.5/§7.2 and `unsafe_policy.md` (beside `#[borrows(..)]` and `#[fresh]` as a trusted claim).
    - **Checks:** C1: a program using it parses, and `--emit-interface` writes it back. C2: `scripts/test_interface_attrs.sh` asserts it survives a `.zri`. C3: `marker_density.sh` counts one per use; quote the before and after counts on a fixture. C4: `check_safety_comments.sh` fails on a stdlib copy with the comment removed. C5: `make test`, `make preflight-changed`.
    - **Done (2026-11-18, git:e9726d2):** `Parser.parse_unsafe_attribute` (`src/parser/decl.zrl`) reads `#[unsafe(borrows(..))]` into `has_borrows` plus `borrows_trusted`, carried on `FnDecl` and `ILFunction`; `unsafe(..)` around anything else is an error (`tests/error_reporting/err_unsafe_attr_not_borrows.zrl`). Both interface writers (`interface_print.zrl`: the summarized path from `ILFunction`, the generic-body path from `FnDecl`) write the `unsafe` form back. The compiler reads the flag nowhere else yet: the tier-2 body check (id:z0011) is what will exempt it. The visible lie (probe 93's shape) is still refused in the trusted form (`tests/error_reporting/err_unsafe_borrows_visible_lie.zrl`). `zoril fmt` keeps the attribute (normalizes `#[ unsafe( borrows( a ,b ) ) ]` to `#[unsafe(borrows(a, b))]`, checked by hand on `build/akapm/fmt2.zrl`). Documented in `surface_syntax.md` §2.5 and §7.2 and `unsafe_policy.md` (after `#[borrows(..)]`). `src/ast.zrl`'s comment-budget row was re-recorded (75 lines against a limit of 73, the new field's rationale), said in the commit.
    - **Found for id:mztqb:** `stdlib/args.zrl` is in neither `src/`'s nor zilc's closure (`build/zoril --emit-deps`), only zbuild's and ztest's, so stage1 never has to parse the attribute there. `core.zrl` and `file.zrl` are in `src/`'s closure; their edits only delete or widen a `#[borrows]`.
    - **Completion (2026-11-18):** C1: `tests/modular/iface_attrs/accept_trusted_borrows.zrl` (a summarized `&self` method `Picker.label` and a generic `gen_trusted`, both `#[unsafe(borrows())]`) compiles whole-program and under zbuild and exits 84; `--emit-interface` writes `#[unsafe(borrows())]` above `pub fn label(self: &Picker) -> [u8];` and above `pub fn gen_trusted<T>(a: &T) -> [u8] {`. With the attribute deleted from a scratch copy the program is refused (`cannot assign to 'p' because it is borrowed`; for `gen_trusted`, `cannot assign to 'n' because it is borrowed`), so the test sees the declaration. C2: `sh scripts/test_interface_attrs.sh` `[PASS] interface-attrs: ...` with the two new asserts (`label`, `gen_trusted`); before the build the fixture did not parse (`lib.zrl:25:10: error: expected declaration`). C3: `sh scripts/marker_density.sh tests/modular/iface_attrs/lib_ties.zrl tests/modular/iface_attrs/lib.zrl`: before, no such line (`#[borrows] claims: 3` only; the anchored `#[borrows(` pattern does not see the marked form); after, `#[unsafe(borrows)]: 2`, and `lib.zrl` alone `#[unsafe(borrows)]: 1`. C4: a stdlib copy (`build/akapm/std_c4`) with `Args.get` marked `#[unsafe(borrows())]` under a `// SAFETY:` line: `PASS: all 178 stdlib unsafe blocks state the invariant they rely on.`; with the comment removed: `[FAIL] build/akapm/std_c4/args.zrl: 1 of 5 unsafe block(s) have no // SAFETY: comment:` naming `args.zrl:45`. `scripts/test_check_safety_comments.sh` gains cases 8-10 (`PASS: check_safety_comments.sh behaves as specified.`); run against the old check, cases 8 and 9 fail (`FAIL: 2 case(s) failed.`). C5: `make test` `Total: 3854 run, 3854 passed, 0 failed, 106 skipped (140.7s)`; `REJECT_DIFF_NO_CACHE=1 make preflight-changed` passed (exit 0): fixpoint `PASS`, `All mutations caught.`, `reject-diff: base verdicts: fresh (no cache); base front end 111 s`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 2542 newly refused, of 69167 programs against a484d11487430a4f709006c069b68454b476b98a` (the refusals are the branch's earlier store-grid commits, against `main`'s merge base), checked build `Total: 1479 run, 1479 passed, 0 failed, 0 skipped (108.1s)`, all performance thresholds within tolerance. The change touches `src/` and `tools/zilc/`, so the fuzz record (`bench/fuzz/README.md`) is stale.

- [x] +safety +tests +AI-D @provenance B3a The standard library's `#[borrows(..)]` declarations and `&self` defaults that name less than the body returns are settled id:mztqb
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:akapm
    > **Check-in:** stop and report before changing a `pub` stdlib signature.
    > **Completed:** 2026-11-18 git:cd7e10d

    - **Split from:** id:z0011, by its measurement of 2026-11-18 (see **Measured** there): its check cannot land while the standard library's own declarations fail it, since every `--provenance` program that lowers one is refused.
    - **Placed:** before id:z0011, which it blocks.
    - **Sites (13):** listed under id:z0011's **Stdlib sites**. Three are open holes in the default build: `Clone for Vec<T>` (gap_77), `Clone for Option<T>` (gap_78) and `Clone for [T]` (gap_99).
    - **Do:** for each site, apply id:z0011's patch to a scratch compiler, then choose among: (a) remove the declaration, so the default or the body's ties hold; (b) widen it (`#[borrows(self, arena)]`); (c) keep the narrow result with an explicit, reviewed `unsafe` interior and a `// SAFETY:` comment. For each choice, count what it newly refuses in `src/`, `tools/` and `tests/` in the default build (the narrowed tie is what let those callers through), and put the counts and the proposed choice to the maintainer before any edit. `iter.zrl:26` (`map`, a by-value `Self`) is an over-report: decide whether `compute_ret_ties` should count a `Self` or type-parameter parameter as holding a reference, or whether the check skips it.
    - **Checks:** C1: per site, the default-build refusals in `src/`, `tools/`, `tests/` before and after the chosen edit. C2: `gap_77`, `gap_78`, `gap_99` refused by the default build once their impls are fixed (flip each probe, remove its Known gaps entry and its class text in `doc/SAFETY.md` §6). C3: `ZORIL_CC=<scratch> ./scripts/test.sh tests/language tests/stdlib` with id:z0011's patch applied has no failure caused by a stdlib site. C4: `make test`, `make preflight-changed` with the rejection differential (`REJECT_DIFF_NO_CACHE=1`).
    - **Measured (2026-11-18, C1; no stdlib file changed):** for each site, the one edit applied to a scratch copy of `stdlib/` (`build/z11/site.sh`), then every root (`src/`, zilc, zbuild, zman, ztest) and the 739 test programs that compile by default (`build/z11/m_base/tests_compiled.txt`) compiled by the default build (`build/zoril` at git:e14d03d). Default-build refusals per edit (base 0):
      - Free (0 refused), and the edit also clears id:z0011's check (`build/z11/zoril.new --provenance=warn` over the same tests with all of them applied: no stdlib site left among these): remove `#[borrows()]` from `Clone for String` (`clone.zrl:35`), `Clone for Option<T>` (`core.zrl:242`) and `Clone for [T]` (`core.zrl:258`); widen `read_to_end_sized_raw` to `#[borrows(arena)]` (`file.zrl:144`; removing it instead refuses 27, all at `file.zrl:209`, since `r` is then tied to the result: "cannot return 'f' ..."); add `#[borrows(inner)]` to both `with_capacity` (`bufio.zrl:36`, `:234`), `#[borrows(self, f)]` to `Iterator.map` (`iter.zrl:26`; `#[borrows(self)]` alone leaves out `f`), and `#[borrows(self, arena)]` to `String.clone_in_raw`, `split_raw` and `Vec.clone_in_raw` (`string.zrl:186`, `:326`, `vec.zrl:155`). The widened ones are what the body already returns, so callers keep the borrow they keep today in effect.
      - Costly: removing `Args.get`'s `#[borrows()]` (`args.zrl:46`) refuses 3: stdlib's own `Args.next` (`args.zrl:89`, "cannot assign to 'self.index' because it is borrowed"), so zbuild and 2 tests. Removing `Args.next`'s (`args.zrl:85`) refuses zbuild at `tools/zbuild/src/options.zrl:184` ("cannot borrow 'args' while it is mutably borrowed"). Removing `Vec.clone`'s (`clone.zrl:17`, gap_77) refuses zbuild at `tools/zbuild/src/main.zrl:110` ("cannot mutably borrow 'manifest' while it is already borrowed").
      - **The `Args` pair is an imprecision, not a narrowing:** `Args.get` builds its slice from an address it reads through the raw `self.argv` (process memory, outliving every `Args`), but pointer-width integers keep their origins, so the body summary ties the result to `self`. So a correct `#[borrows()]` is refused. This is the case the rule's "explicit, reviewed `unsafe` interior" is for, but no mechanism for it exists yet: an `unsafe` block does not drop origins, and only `@ptr_from_int` yields `Raw`. **Decision needed:** how an exemption is written (for example, the slice built with `@ptr_from_int`, or an `unsafe`-only attribute the check accepts with a `// SAFETY:` comment).
      - **`Vec.clone` (gap_77):** removing the declaration closes gap_77 in the default build ("cannot return 'v' a reference into storage owned by this frame") and costs one zbuild site, which would need a change in `tools/` (`collect_garbage(&ctx, &manifest)` while a clone of the manifest's data is live).
      - **Probes with the free edits** (`STD=build/z11/sites/combined build/z11/run.sh build/zoril ...`): `gap_99` is refused by the default build ("cannot mutably borrow 'a' while it is already borrowed"), so it can flip in this task. `gap_78` is still accepted (exit 7). The old return rule does not see the frame view through the call, while `--provenance` refuses it (the return rule) with or without the edit, so gap_78 flips with id:z0065, not here. `gap_44` (a user `#[borrows()]`) is unchanged, as expected.
      - **Proposal for the maintainer:** (1) apply the free edits (patch below; it changes `pub` stdlib contracts: three `Clone` impls lose `#[borrows()]`, and seven functions gain a wider `#[borrows(..)]`), and flip gap_99; (2) remove `Vec.clone`'s declaration and fix zbuild's `main.zrl:110` in the same change, closing gap_77; (3) settle the exemption mechanism for `Args.get`/`Args.next` first, as its own `+AI-D` decision.
      - **Patch for (1)** (`build/z11/mztqb-zero-cost.patch`, against git:e14d03d):
    ```diff
    --- a/stdlib/bufio.zrl
    +++ b/stdlib/bufio.zrl
    @@ -33,6 +33,7 @@
         }
     
         // Creates a new BufWriter wrapping inner with the specified buffer capacity.
    +    #[borrows(inner)]
         pub fn with_capacity(inner: W, cap: usize) -> BufWriter<W> {
             let mut buf = Vec::<u8>.with_capacity(cap);
             buf.resize(cap, 0 as u8);
    @@ -230,6 +231,7 @@
             return BufReader::<R>.with_capacity(inner, DEFAULT_BUF_READER_CAPACITY);
         }
     
    +    #[borrows(inner)]
         // Creates a new BufReader wrapping inner with the specified buffer capacity.
         pub fn with_capacity(inner: R, cap: usize) -> BufReader<R> {
             let mut buf = Vec::<u8>.with_capacity(cap);
    --- a/stdlib/clone.zrl
    +++ b/stdlib/clone.zrl
    @@ -31,7 +31,6 @@
     // String's own arena via the raw escape hatch (an `&Arena` is not available here).
     impl Clone for String {
         // Creates an explicit duplicate copy of the value.
    -    #[borrows()]
         fn clone(self: &String) -> String {
             // SAFETY: the pointer is the arena `self` (a live String) allocates from, and
             // `clone_in_raw` only records it.
    --- a/stdlib/core.zrl
    +++ b/stdlib/core.zrl
    @@ -238,7 +238,6 @@
     
     impl<T: Clone> Clone for Option<T> {
         // Creates an explicit duplicate copy of the value.
    -    #[borrows()]
         fn clone(self: &Option<T>) -> Option<T> {
             // Matched through the reference: `T` may own storage, so `match *self` would move it out
             // of the borrow. The ergonomic binding is `&T`, which `clone` copies.
    @@ -254,7 +253,6 @@
     // and a `Vec` clone then duplicates its elements rather than sharing them.
     impl<T: Clone> Clone for [T] {
         // Creates an explicit duplicate copy of the value.
    -    #[borrows()]
         fn clone(self: &[T]) -> [T] {
             return *self;
         }
    --- a/stdlib/file.zrl
    +++ b/stdlib/file.zrl
    @@ -140,7 +140,7 @@
     // CALLER OBLIGATION: arena must be valid and initialized.
     //
     // INTERNAL: unsafe raw-pointer escape hatch for bootstrap compiler and internal modules
    -#[borrows()]
    +#[borrows(arena)]
     pub unsafe fn read_to_end_sized_raw<R: Read>(
         r: &mut R,
         initial_cap: u64,
    --- a/stdlib/iter.zrl
    +++ b/stdlib/iter.zrl
    @@ -23,6 +23,7 @@
         fn next(self: &mut Self) -> Option<Self::Item>;
     
         // Returns an iterator adapter that applies f to each element.
    +    #[borrows(self, f)]
         fn map<U>(self: Self, f: fn(Self::Item) -> U) -> Map<Self, U> {
             return Map { inner: self, f: f };
         }
    --- a/stdlib/string.zrl
    +++ b/stdlib/string.zrl
    @@ -183,6 +183,7 @@
         // The same-arena clone the `Clone` impl in clone.zrl needs: it holds only the raw header the
         // String already allocates from, not an `&Arena`.
         // INTERNAL: unsafe raw-pointer escape hatch for bootstrap compiler and internal modules
    +    #[borrows(self, arena)]
         pub unsafe fn clone_in_raw(self: &String, arena: *mut ArenaHeader) -> String {
             return String { vec: self.vec.clone_in_raw(arena) };
         }
    @@ -322,6 +323,7 @@
         //
         // CALLER OBLIGATION: arena must be valid and initialized.
         //
    +    #[borrows(self, arena)]
         // INTERNAL: unsafe raw-pointer escape hatch for bootstrap compiler and internal modules
         pub unsafe fn split_raw(self: &[u8], delim: u8, arena: *mut ArenaHeader) -> Vec<[u8]> {
             let mut res = Vec::<[u8]>.new_in_raw(arena);
    --- a/stdlib/vec.zrl
    +++ b/stdlib/vec.zrl
    @@ -152,6 +152,7 @@
         // CALLER OBLIGATION: arena must be valid and initialized.
         //
         // INTERNAL: unsafe raw-pointer escape hatch for bootstrap compiler and internal modules
    +    #[borrows(self, arena)]
         pub unsafe fn clone_in_raw(self: &Vec<T>, arena: *mut ArenaHeader) -> Vec<T> {
             if self.len == 0 as usize { return Vec::<T>.new_in_raw(arena); }
             let bytes = size_of_n(self.len, sizeof(T));
    ```
    - **Revised by the decision of 2026-11-18** (id:z0011, **Decision**): the seven `&self`- or elision-default sites (`bufio.zrl:36`, `:234`, `iter.zrl:26`, `string.zrl:186`, `:326`, `vec.zrl:155`, and the generic `Self` of `map`) need no edit. Since git:21658fa their body's ties are inferred, so the seven added `#[borrows(..)]` lines of the patch above are dropped. What is left: delete `#[borrows()]` from `Clone for String`, `Option<T>` and `[T]` (free; closes gap_99); change `read_to_end_sized_raw`'s declaration to `#[borrows(arena)]` (a tier-2 contract equal to the body; free); delete `Vec.clone`'s and fix `tools/zbuild/src/main.zrl:110` (closes gap_77); mark `Args.get`/`Args.next` `#[unsafe(borrows())]` with a `// SAFETY:` line (id:akapm). Re-run C1 on these edits before asking the maintainer to approve the `pub` changes.
    - **Depends changed (2026-11-18):** added id:akapm, for the `Args` pair.

    - **Measurement scripts** (from id:z0011's session, 2026-11-18; `build/z11/` is scratch). Copy each into `build/` and run it from the repository root. `site.sh NAME FILE LINE EDIT` applies one edit to a scratch copy of `stdlib/` (`del` removes the `#[borrows()]` within two lines above LINE, `rep:<attr>` replaces it, any other text is inserted before LINE). Then it counts default-build refusals over the roots and the test programs that compile by default. `cost.sh ZORIL OUTDIR [STDLIB]` counts the same for a whole compiler. Both read `build/z11/m_base/tests_compiled.txt`. Regenerate that file with the `tests_compiled.txt` loop of `build/z97/measure.sh`: every `tests/**/*.zrl` that is not `*_lib.zrl`, has no `// @skip:`, and compiles with its `// flags:`.
    ```sh
    # cost.sh
    R=$(pwd); Z=$1; O=$2; S=${3:-stdlib}; mkdir -p $O; : > $O/refused.txt
    for root in src/main.zrl tools/zilc/src/main.zrl tools/zbuild/src/main.zrl tools/zman/src/main.zrl tools/ztest/src/main.zrl; do
      timeout -k 5 180 $Z -I stdlib=$S -I $(dirname $root) -I src -I build/gen --emit-zil -o /dev/null $root > $O/root.log 2>&1 || grep error $O/root.log | sed "s|^|ROOT $root: |" >> $O/refused.txt
    done
    while read -r tf; do
      fl=$(sed -n 's|^// flags: ||p' $tf | head -1)
      timeout -k 5 30 $Z -I stdlib=$S -I $(dirname $tf) $fl --emit-zil -o /dev/null $tf > /dev/null 2>$O/t.err || grep -m1 error $O/t.err | sed "s|^|$tf: |" >> $O/refused.txt
    done < build/z11/m_base/tests_compiled.txt
    echo "$O $(grep -c '' $O/refused.txt)"
    ```
    For one site: `cp -r stdlib build/z11/sites/N/stdlib`, make the edit there, then `sh build/cost.sh build/zoril build/z11/sites/N/out build/z11/sites/N/stdlib`.

    - **Re-measured (2026-11-18, on `stream/provenance` at git:e9726d2, which parses `#[unsafe(borrows(..))]`; no stdlib file changed):** the revised edits applied to scratch copies of `stdlib/` (`build/mztqb/stdlib`: the free edits; `stdlib_vec`: and `Vec.clone`'s declaration removed; `stdlib_args2`: and `Args.get`, `Args.next` marked; patch below). The test list is regenerated (`build/mztqb/m_base/tests_compiled.txt`, 743 programs, was 739), and counted by `build/mztqb/cost.sh` (id:z0011's `cost.sh`, with the list as an argument and an extra flags argument).
      - **C1, default-build refusals** (`build/zoril`, base 0): free edits 0; plus removing `Vec.clone`'s 1: `tools/zbuild/src/main.zrl:110:35: error: cannot mutably borrow 'manifest' while it is already borrowed`; plus the `Args` pair marked: still that 1, nothing more. **The zbuild fix:** `run_gc_only`'s `BuildCtx` takes `recs: manifest.tools.clone()`, which nothing on the gc path reads (`prune_manifest`, `save_manifest`, which writes `m_in`'s own tools, and `collect_garbage` read no `ctx.tools`). Giving it `recs: unsafe { Vec::<ToolRec>.new_in_raw(arena) }`, as the build path at `main.zrl:193` does, makes zbuild compile in the default build with every edit (`rc=0`).
      - **Tier-2 check (scratch):** id:z0011's patch no longer applies, so the check was written fresh as `os_check_declared_ties`, called from `os_infer_ties` for a function with `has_borrows` (patch below; `build/mztqb/zoril.t2`). It skips `borrows_trusted`, closures, `extern`s and imports, and does not check bodies in a recursive cycle. `--provenance=warn` over the roots and the 743 tests: 136 warnings with today's stdlib, at `args.zrl:46` (5), `:85` (3), `clone.zrl:17` (5), `:35` (1), `core.zrl:242` (2), `:258` (2), `file.zrl:144` (32), the rest in `src/` and `tools/`. With `stdlib_args2`, no warning is at a stdlib site; the 84 left are in the roots' own `src/`/`tools/` declarations (id:mrdtf). The seven elision-default sites of the first measurement (`bufio`, `iter`, `string`, `vec`) no longer appear: their ties are inferred since git:21658fa.
      - **Found: a trusted declaration does not reach its callers under `--provenance`.** With only `Args.get` marked, `Args.next` (which returns `self.get(..)`) is still reported: `args.zrl:87:9: warning: provenance: #[borrows(..)] leaves out 'self'`. `os_call` builds a call's result from the callee's body summary (`os_ret_addr`/`os_ret_contents`) when it has one, so the summary's tie to `self` passes through the trusted declaration. Marking `Args.next` too clears it (0 warnings for `tests/stdlib/test_stdlib_args_from_runtime.zrl`). id:z0011 should decide whether a `borrows_trusted` callee's result reads `ret_ties` instead of its body ties at the call (the design note's "the compiler trusts it" suggests so); until then each caller that forwards a trusted result needs its own mark.
      - **C2 (probes, default build, `build/z11/run.sh` with `STD=`):** today `gap_77` exit 7, `gap_78` exit 7, `gap_99` exit 77, `gap_44` exit 77; with `stdlib_args2`, `gap_77` refused (`cannot return 'v' a reference into storage owned by this frame (a collection, a box or an arena)`), `gap_99` refused (`cannot mutably borrow 'a' while it is already borrowed`), `gap_78` still exit 7 (it flips with id:z0065, as measured before), `gap_44` still exit 77 (a user declaration, as expected). Not flipped yet: no stdlib file has changed.
      - **C3:** `ZORIL_CC=build/mztqb/zoril.t2 ZORIL_STDLIB=build/mztqb/stdlib_args2 ./scripts/test.sh tests/language tests/stdlib tests/error_reporting`: `Total: 1077 run, 1075 passed, 2 failed, 0 skipped (8.0s)`. The two are the tests' own declarations, not stdlib sites: `arena_named_through_vec_reference_accepted.zrl:16:5` and `:20:5`, `popped_integer_carries_no_address_accepted.zrl:13:1` (id:z0011's, whose texts change; stop and report there). With today's stdlib: `Total: 1077 run, 1074 passed, 3 failed, 0 skipped (8.0s)`; the third, `clone_returned_accepted.zrl`, fails at `stdlib/clone.zrl:17:5`, `core.zrl:258:5`, `core.zrl:242:5`.
      - **Stage1:** `build/zoril-stage1 -I stdlib=build/mztqb/stdlib_args2 -I src -I build/gen --emit-zil src/main.zrl` exits 0 with the same diagnostics as against `stdlib/`. `args.zrl` is in neither `src/`'s nor zilc's closure, so stage1 never reads the new attribute; zbuild and ztest, which import it, are built by `build/zoril`.
      - **Proposal for the maintainer (each changes a `pub` contract):** (1) delete `#[borrows()]` from `Clone for String`, `Clone for Option<T>`, `Clone for [T]`, and write `read_to_end_sized_raw`'s as `#[borrows(arena)]`: no refusal, and flip `gap_99`. (2) Delete `Vec.clone`'s `#[borrows()]` with the zbuild gc fix above in the same commit: closes `gap_77`. (3) Mark `Args.get` and `Args.next` `#[unsafe(borrows())]`, each with a `// SAFETY:` line, as in the patch; `Args.next` needs its own mark until id:z0011 settles the finding above. The `// SAFETY:` line sits inside the doc-comment block above the attribute, so check `make man-gen` and `scripts/test_man_pages.sh` when the edit is made (and move it if the man page prints it).
      - **Stopped for the check-in (2026-11-18):** no stdlib file is changed; the three proposals above wait for the maintainer's approval of the `pub` changes.
      - **Stdlib edits** (`build/mztqb/edits.diff`, against git:e9726d2; the zbuild line is the one above):
    ```diff
    --- a/stdlib/args.zrl
    +++ b/stdlib/args.zrl
    @@ -42,7 +42,9 @@
         }
     
         // Returns the argument at index as a byte slice, or None if index is out of bounds.
    -    #[borrows()]
    +    // SAFETY: the slice is an argument string in process memory, read through argv, which outlives
    +    // every Args; the analysis ties it to self because the address is read through self.argv.
    +    #[unsafe(borrows())]
         pub fn get(self: &Args, index: usize) -> Option<[u8]> {
             // Compare in `usize`: `index as i32` truncated, so an index at or above 2^31 became a
             // small (or negative) i32, passed the guard and then read the wrong argument, or past the
    @@ -80,8 +82,10 @@
             return self.index < self.argc;
         }
     
    -    #[borrows()]
         // Yields the next argument as a byte slice, or None when all arguments have been consumed.
    +    // SAFETY: the result is what Args.get returns, an argument string in process memory that
    +    // outlives every Args.
    +    #[unsafe(borrows())]
         pub fn next(self: &mut Args) -> Option<[u8]> {
             if self.index >= self.argc {
                 return Option.None;
    --- a/stdlib/clone.zrl
    +++ b/stdlib/clone.zrl
    @@ -13,7 +13,6 @@
     // Clones each element into a new Vec on the same allocator.
     impl<T: Clone> Clone for Vec<T> {
         // Creates an explicit duplicate copy of the value.
    -    #[borrows()]
         fn clone(self: &Vec<T>) -> Vec<T> {
             // SAFETY: the pointer is the arena `self` (a live Vec) allocates from, and `new_in_raw`
             // only records it.
    @@ -31,7 +30,6 @@
     // String's own arena via the raw escape hatch (an `&Arena` is not available here).
     impl Clone for String {
         // Creates an explicit duplicate copy of the value.
    -    #[borrows()]
         fn clone(self: &String) -> String {
             // SAFETY: the pointer is the arena `self` (a live String) allocates from, and
             // `clone_in_raw` only records it.
    --- a/stdlib/core.zrl
    +++ b/stdlib/core.zrl
    @@ -238,7 +238,6 @@
     
     impl<T: Clone> Clone for Option<T> {
         // Creates an explicit duplicate copy of the value.
    -    #[borrows()]
         fn clone(self: &Option<T>) -> Option<T> {
             // Matched through the reference: `T` may own storage, so `match *self` would move it out
             // of the borrow. The ergonomic binding is `&T`, which `clone` copies.
    @@ -254,7 +253,6 @@
     // and a `Vec` clone then duplicates its elements rather than sharing them.
     impl<T: Clone> Clone for [T] {
         // Creates an explicit duplicate copy of the value.
    -    #[borrows()]
         fn clone(self: &[T]) -> [T] {
             return *self;
         }
    --- a/stdlib/file.zrl
    +++ b/stdlib/file.zrl
    @@ -140,7 +140,7 @@
     // CALLER OBLIGATION: arena must be valid and initialized.
     //
     // INTERNAL: unsafe raw-pointer escape hatch for bootstrap compiler and internal modules
    -#[borrows()]
    +#[borrows(arena)]
     pub unsafe fn read_to_end_sized_raw<R: Read>(
         r: &mut R,
         initial_cap: u64,
    ```
    - **Scratch tier-2 check** (`build/mztqb/mztqb-tier2-scratch.patch`, `diff -r` of `src/` at git:e9726d2; built with `build/zoril -I stdlib=stdlib -I src -I build/gen --emit-zil`, then `build/zilc`, `qbe`, `as`, `ld` with `build/runtime.o`):
    ```diff
    diff -r ../../src/check_zir.zrl src/check_zir.zrl
    8315a8316,8340
    > // Scratch tier-2 check (mztqb measurement only): a plain #[borrows(..)] narrower than the body.
    > fn os_check_declared_ties(c: &mut OriginSets, module: &ILModule, f: &ILFunction) {
    >     if c.rules == PROVENANCE_OFF || f.borrows_trusted || f.from_interface || f.is_extern { return; }
    >     if f.params_len > 0 as usize
    >         && type_name_is(c.table.lookup(f.param(f.params_len - 1 as usize).name), "__env") {
    >         return;
    >     }
    >     if f.ret_ty != 0 as u32 && !module.type_holds_reference(f.ret_ty, 0 as usize) { return; }
    >     let base = if f.params_len > 0 as usize && f.param(0).name == c.sret_name { 1 as usize } else { 0 as usize };
    >     let missing = os_body_ties(c, module, f) & !f.ret_ties;
    >     let mut i = 0 as usize;
    >     while i < 63 as usize {
    >         if (missing >> (i as u64)) & 1 as u64 != 0 as u64 && i + base < f.params_len
    >             && module.type_holds_reference(f.param(i + base).ty, 0 as usize) {
    >             diag_start(c.file, f.decl_span, if c.rules == PROVENANCE_WARN { "warning" } else { "error" });
    >             eprint("provenance: #[borrows(..)] leaves out '");
    >             eprint(c.table.lookup(f.param(i + base).name));
    >             eprint("', which the result may point into; a declaration may name more than the body returns, never less\n");
    >             c.errors = c.errors + 1 as u32;
    >             return;
    >         }
    >         i = i + 1 as usize;
    >     }
    > }
    > 
    8317a8343
    >     if f.has_borrows { os_check_declared_ties(c, module, &f); }
    diff -r ../../src/driver/module.zrl src/driver/module.zrl
    1278a1279
    >             if origins.errors > 0 as u32 && self.provenance == check_zir::PROVENANCE_ON { self.had_error = true; }
    1369a1371
    >             if origins.errors > 0 as u32 && self.provenance == check_zir::PROVENANCE_ON { self.had_error = true; }
    ```

    - **Approved (2026-11-18, the maintainer):** proposals (1), (2) and (3) above.
    - **Done in part (2026-11-18, git:4241f2c):** (1) and (3). `Clone for String`, `Option<T>`, `[T]` lose `#[borrows()]`; `read_to_end_sized_raw` declares `#[borrows(arena)]`; `Args.get` and `Args.next` are `#[unsafe(borrows())]`, each under a one-line `// SAFETY:` comment (a two-line one put its second line into `doc/man/zoril-args.3.scd`: `zman` drops the `// SAFETY:` line but keeps its continuation; `make man-gen` now changes only the page's date). `gap_99` flipped to `compile_reject`, its Known gaps entry and `doc/SAFETY.md` §6 (H) clause removed. `gap_78`'s reason corrected in the probe, its Known gaps entry and §6 (L): `Option.clone` is now tied to the local `o` by the `&self` default, but the default build's return rule does not follow that tie to the frame view `o` holds (`return o` refused, `--provenance` refuses the clone); it still flips with id:z0065. `doc/design/provenance.md` tier 2 lists what is settled.
    - **(2) held back, needs the maintainer (2026-11-18):** removing `Vec.clone`'s `#[borrows()]` also refuses safety probe `307_clone_is_independent.zrl` (`expected: accept`): `let mut v2 = v1.clone(); v1.push(2);` gives `307_clone_is_independent.zrl:13:5: error: cannot mutably borrow 'v1' while it is already borrowed`, since the `&self` default ties the clone to `v1` whatever `T` is. The C1 count missed it because it covered `src/`, `tools/` and `tests/`, not the probes. Flipping 307 changes a probe's expected result, and the refusal hits an ordinary pattern, so `Vec.clone` keeps its declaration and `gap_77` stays open; the zbuild gc fix was not committed (it is needed only with (2)). **Decide:** keep gap_77 open until the tie can depend on whether `T` holds a reference (a precision change: a `Vec<u8>` clone shares nothing with `self` but its arena), or accept the refusal and flip 307.
    - **Runs (git:4241f2c):** `sh scripts/run_safety_matrix.sh` `All probes complete: 476/527 passed. Mismatches: 0`; `sh scripts/check_safety_model.sh` `PASS: safety_model.md is self-consistent.`; `sh scripts/test_man_pages.sh` `[PASS] man-pages: all pages build cleanly and match tools and stdlib`; `make test` `Total: 3856 run, 3856 passed, 0 failed, 104 skipped (141.6s)` (run before an amend that only removed two untracked run artifacts, `gap_78_*.log` and `.zil`, from the commit); `REJECT_DIFF_NO_CACHE=1 make preflight-changed` passed: `All mutations caught.`, fixpoint `PASS`, `reject-diff: base verdicts: fresh (no cache); base front end 112 s`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 2544 newly refused, of 69167 programs against a484d11487430a4f709006c069b68454b476b98a`, checked build `Total: 1479 run, 1479 passed, 0 failed, 0 skipped (108.2s)`, performance within tolerance. Against id:akapm's run (2542), the two new refusals are `gap_99` whole-program and under zbuild, nothing else. The change touches `stdlib/`, so the fuzz record is stale.
    - **(2) landed after all (2026-11-18, git:cd7e10d):** the maintainer asked for the choice that agrees with the design principles (`doc/vision/why_zoril.md`). Keeping gap_77 open to spare probe 307 contradicts principle 1 (an unsafe program is never accepted to save a correct one), and a trusted narrowing on `Vec.clone` would be false (principle 3 allows trust only where it is true): the clone holds what the elements hold, and lives in the original's arena. So `Vec.clone`'s `#[borrows()]` is removed, zbuild's gc context starts with no tool rows (the gc path never reads them), gap_77 is flipped to `compile_reject` (Known gaps entry and `doc/SAFETY.md` §6 (L) text removed; gap_80's entry now names gap_78 as its class), and probe 307 is flipped from `accept` to `compile_reject` with the reason (a correct program refused while the tie is imprecise). The precision fix is id:2sdmk, placed after this task. `stdlib/clone.zrl`'s comment-budget row is re-recorded (15 lines, limit 14: the removed attributes shrank its code), said in the commit.
    - **Completion (2026-11-18):** the work is git:4241f2c ((1), (3)) and git:cd7e10d ((2)). C1: per site, the default-build refusals over `src/`, `tools/` and the 743 test programs under **Re-measured** above (free edits 0; `Vec.clone` 1, zbuild `main.zrl:110`, now fixed; the `Args` pair 0); the probes were not in that count, and `sh scripts/run_safety_matrix.sh` found probe 307 (handled in git:cd7e10d). C2: `gap_77` and `gap_99` are `compile_reject` and pass (`All probes complete: 477/527 passed. Mismatches: 0`); `gap_78` is not flipped: with its `#[borrows()]` gone the default return rule still accepts it (exit 7), and `--provenance` refuses it, so it flips with id:z0065 (its reason is corrected in the probe and the docs). C3: `ZORIL_CC=build/mztqb/zoril.t2 ZORIL_STDLIB=build/mztqb/stdlib_args2 ./scripts/test.sh tests/language tests/stdlib tests/error_reporting` `Total: 1077 run, 1075 passed, 2 failed, 0 skipped (8.0s)`, the two at the tests' own declarations, none at a stdlib site (`stdlib_args2` is the tree's stdlib as committed, but for the one comment line in `clone.zrl` and the two one-line SAFETY comments). C4 at git:cd7e10d: `make test` `Total: 3858 run, 3858 passed, 0 failed, 102 skipped (141.1s)`; `REJECT_DIFF_NO_CACHE=1 make preflight-changed` passed: `All mutations caught.`, fixpoint `PASS`, `reject-diff: base verdicts: fresh (no cache); base front end 111 s`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 2548 newly refused, of 69167 programs against a484d11487430a4f709006c069b68454b476b98a`, checked build `Total: 1479 run, 1479 passed, 0 failed, 0 skipped (108.2s)`, performance within tolerance. Against id:akapm's run (2542) the six new refusals are `gap_99`, `gap_77` and `307_clone_is_independent.zrl`, each whole-program and under zbuild. Also `sh scripts/check_safety_model.sh` `PASS: safety_model.md is self-consistent.` and `sh scripts/test_man_pages.sh` `[PASS] man-pages: ...`. The change touches `stdlib/` and `tools/zbuild/`, so the fuzz record is stale. Milestone figures (probe counts) not touched.

- [ ] +safety +precision +AI-D @provenance A clone is tied to what the original points into, not to the original itself, so probe 307 is accepted again id:2sdmk
    > **Created:** 2026-11-18
    > **Branch:** `provenance`

    - **Placed:** directly after id:mztqb, as its follow-up.
    - **Found by:** id:mztqb (git:cd7e10d). With `Clone for Vec<T>`'s `#[borrows()]` removed (closing gap_77), the `&self` default ties a clone to `self`, so `let mut v2 = v1.clone(); v1.push(2);` is refused (`bench/safety_matrix/probes/307_clone_is_independent.zrl:13:5: error: cannot mutably borrow 'v1' while it is already borrowed`). Probe 307 was flipped from `accept` to `compile_reject` with the reason, under design principle 1 (`doc/vision/why_zoril.md`: a correct program may be refused while the analysis is imprecise). A trusted `#[unsafe(borrows())]` is not a way out: the clone holds what the elements hold (gap_77) and lives in the original's arena, so it must keep that arena borrowed across a reset.
    - **Decide:** how a result is tied to what a parameter points into (`ParamContents`) without holding the parameter itself borrowed for mutation, for the borrow checker's ties (`inherit_rv_borrows`), and whether the same change frees other results of the same shape (a `String` clone, `Option` clone). Name what a wrong acceptance would hide (a clone outliving an arena reset, a clone of frame views returned: gap_77) and give a planted case for each.
    - **Checks:** C1: probe 307 flipped back to `accept`, gap_77 and an arena-reset twin (`let c = v.clone(); a.reset(); c.len()` with `v` in `a`) still refused. C2: `sh scripts/run_safety_matrix.sh` with 0 mismatches. C3: `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, every newly accepted program listed with its reason.
    - **Checks moved (2026-11-18):** the work is more than one session, so it is split into id:bfd1z (H1), id:42ae2 (H2) and id:mqh84 (H3), placed after this task, with a check-in after them. C1 to C3 are H3's checks, where they are numbered again. This task is the decision; it stays open until the maintainer approves it, because it adds a new form of a trusted attribute and a `pub` stdlib method (see **Decision**).
    - **Finding 1, `ParamContents` alone is not enough (2026-11-18, `build/zoril` at git:cd7e10d, `build/2sdmk/shapes.zrl`):** `--emit-origins` gives the same return set for a view into the Vec's own buffer, a clone, and a copy of a stored slice: `fn sl(v: &Vec<u8>) -> [u8] { return v.as_slice(); }` `return O={ParamContents(0)} S={}`; `fn cl(v: &Vec<[u8]>) -> Vec<[u8]> { return v.clone(); }` `return O={ParamContents(0)} S={ParamContents(0)}`; `fn hd(v: &[u8]) -> [u8] { return *v; }` `return O={ParamContents(0)} S={}`. A read through `ParamAddr` or `ParamContents` memory yields `ParamContents` whatever it reads (`os_through`), so the sets do not record whether the memory is *owned* by the referent (the Vec's buffer, reached through the raw `data`) or only *borrowed* by it (its arena, its elements' referents). So the obvious rule, "a `ParamContents`-only tie inherits what the referent holds, not the referent", accepts a use after free: P1 below.
    - **Finding 2, the answer depends on `T` (same build, `build/2sdmk/selfref.zrl`):** a safe `Clone` may return a value pointing into its source. `struct S { a: [u8; 4], v: [u8] }` with `fn clone(self: &S) -> S { return S { a: self.a, v: &self.a }; }` is accepted and runs (exit 5). So `Vec<S>.clone()` points into `v1`'s buffer, and a trusted narrowing on the generic `Clone for Vec<T>` would be false for that `T` (principle 3 allows trust only where it is true): P2 below. Summaries are per instance (`Vec_Tu8::clone` and `Vec_TSu8::clone` are separate functions in the ZIL), so the answer can be computed per `T`.
    - **Finding 3, the trust has to sit on the arena pointer:** `Vec.clone` reaches its arena only through `self.raw_arena()`, a raw pointer read, and no body analysis can tell a raw field that owns (`data`) from one that borrows (`raw`). That is unsafe-interior knowledge, so it is a trusted declaration, but on a `T`-independent function whose claim is true for every `T`, not on the generic clone.
    - **Decision (proposed 2026-11-18, awaiting the maintainer):**
      1. _A new summary fact, `ret_held` (a mask beside `ret_ties`):_ bit `i` says the result points into what argument `i`'s referent *holds*, and into nothing the referent is or owns.
      2. _The caller (H3):_ in `inherit_rv_borrows`, for a tied argument whose bit is in `ret_held` and not in `ret_storage`, each *direct* borrow the argument carries (the `&v1` of the call) is replaced by the borrows the borrowed place's local holds (borrower = that local), copied with their own flags. The argument's other borrows are kept as they are today. So `v2 = v1.clone()` holds what `v1` holds (its arena, the views pushed into it) and not `v1`. A referent the checker records nothing for (a parameter of the caller, a place behind a pointer) keeps today's rule. This relies on the invariant the push and store rules already keep: what a local points into, other than its own and its owned storage, is held by it as a borrow (a view of its own buffer pushed into itself is a borrow of itself: P5).
      3. _The body (H1):_ the origin sets get a word `OS_W_OWNED` beside `OS_W_CONTENTS`, `ParamOwned(i)` ⊆ `ParamContents(i)`: the address may point into the referent of argument `i` or into storage it owns. The existing rules never read it, so the store and return rules do not change. A read (`os_through`) of a value whose type can own (a raw pointer, a box, anything holding one or a type parameter not yet known) carries `ParamAddr | ParamOwned` of the memory into `ParamOwned`; a read of a reference or a slice carries none (what a borrowing value stored in the referent points to is held by the referent, by the invariant of 2). Every other write of `ParamContents` (an unknown call, an `extern`, a cast, a call whose tie is not held) also writes `ParamOwned`: the word starts conservative and is cleared only by those two rules and by a held call (a callee's `ret_held` bit gives the result what is reached through the argument, without `ParamOwned`). `ret_held` = the bits of `ParamContents` in `O(ret)` and `S(ret)` with no `ParamAddr` and no `ParamOwned` in either. Only a body with no `unsafe` block, not an `unsafe fn`, and no call to an `extern` of its own gets an inferred `ret_held`: a copy through a bare `extern` or a raw write would hide an owned pointer from the sets (id:f81f3's blind spots). A recursive cycle's open callee is read as not held, as for ties.
      4. _The trust (H2):_ `#[unsafe(borrows(*self))]`, read "the result borrows what `*self` borrows", sets `ret_held` for `self` on a function whose body the inference cannot read. Two uses: a new `pub fn empty_like(self: &Vec<T>) -> Vec<T>` (an empty Vec allocating from the same arena, true for every `T`), so that `Clone for Vec<T>` becomes a safe body (`empty_like` then `push(get(i).clone())`) that H1 infers per `T`; and `Clone for String` directly (its bytes hold nothing; the arena is held). A plain `#[borrows(*self)]` (a checked contract) is left to id:z0011. The `.zri` carries `ret_held` as a `#[summary]` key, so an importer that finds none reads no held bit (the strict side).
      5. _What it frees besides probe 307:_ `[T].clone` and `Option<T>.clone` are inferred (a slice read through `self`; `v.clone()` of a held `T`), and so is every safe accessor returning a stored view (`fn name(self: &Tok) -> [u8] { return self.text; }`), which no longer keeps the struct borrowed. The rejection differential lists them; the `src/` sites it frees are expected and are listed, not judged one by one.
      - _Alternative not taken:_ §3.1's release tier (`doc/design/provenance.md`) would also accept probe 307 (`push` releases nothing). But L1 decided a borrow a call result holds keeps today's rule, and the release tier does not exist yet; the decision above keeps that rule and changes only which place is borrowed.
    - **Planted cases** (each refused by `build/zoril` at git:cd7e10d; the reproducers are in `build/2sdmk/`, the text below). Each is a numbered check of H1 or H3, with its safeguard taken out to show it can fail:
      - P1, a view into the original's own buffer (hides a use after free from the author of `v.as_slice()`; safeguard: `ParamOwned` from a raw read): `let mut v = Vec::<u8>.new(); v.push(7); let s = v.as_slice(); v.free(); return s[0] as i32;` refused, "cannot mutably borrow 'v' while it is already borrowed".
      - P2, a clone whose `T.clone` points into its source (hides a use after free from a user with such a `T`; safeguard: per-instance inference, no trust on the generic clone): `S` as in Finding 2, `let e = [9 as u8; 4]; let mut v1 = Vec::<S>.new(); v1.push(S { a: [5 as u8; 4], v: &e }); let v2 = v1.clone(); v1.free(); return v2.get(0).unwrap().v[0] as i32;` refused, "cannot mutably borrow 'v1' while it is already borrowed".
      - P3, the arena reset (hides a read of a reset arena; safeguard: the caller copies the referent's borrows): `let mut a = Arena.new(4096).unwrap(); let mut v = Vec::<u8>.new_in(&a); v.push(7); let c = v.clone(); a.reset(); return c.len() as i32;` refused, "cannot mutably borrow 'a' while it is already borrowed".
      - P4, gap_77 (a clone of frame views returned; safeguard: the copied borrows keep the escape rule's view of `buf`): refused, "cannot return 'v' ...". With the change the refusal names `buf` instead.
      - P5, views into the struct's own buffer stored in the same struct (hides a free under a held accessor; safeguard: the self-borrow is among the borrows copied): `struct T { buf: Vec<u8>, names: Vec<[u8]> }`, `fn first(t: &T) -> [u8] { return *t.names.get(0).unwrap(); }`, `t.buf.push(7); t.names.push(t.buf.as_slice()); let n = first(&t); t.buf.free(); return n[0] as i32;` refused, "cannot mutably borrow 't.buf' while it is already borrowed". (Line 10, the self-borrowing push, is accepted today.)
      - P6, an owned pointer hidden behind a bare `extern` copy in a safe-looking body (safeguard: no inference for a body with `unsafe` or an `extern` call): a function `fn leak(v: &Vec<u8>) -> [u8]` that copies `v`'s buffer pointer into its result through `memcpy` in an `unsafe` block, then `v.free()` while the result lives: refused. To write in H1.
      - P7, separate compilation (hides P2 and P3 from a `zbuild` user; safeguard: the `.zri` key): P2, P3 and probe 307 under `zbuild` agree with whole-program (`safety-matrix-zbuild`, `zbuild-diff`).
      - P8, a receiver that is not a direct borrow (`v.get(0).unwrap().clone()` for a `Vec<Vec<u8>>`, then `v.free()`): refused (the derived borrow of `v` is kept).
      - P9, a view a callee stored into the referent without a recorded borrow (gap_96's class; hides a use after free from any caller of a held function; safeguard: H3 waits for holders one to three): `struct T { buf: Vec<u8>, names: Vec<[u8]> }`, `fn index(t: &mut T) { t.names.push(t.buf.as_slice()); }`, `fn first(t: &T) -> [u8] { return *t.names.get(0).unwrap(); }`, then `t.buf.push(7); index(&mut t); let n = first(&t); t.buf.free(); return n[0] as i32;` is refused today ("cannot mutably borrow 't.buf' while it is already borrowed", the borrow of `t` at `first(&t)`). Without `first`, reading `t.names` after the free is accepted and faults (`build/2sdmk/p9_direct.zrl`, exit 139): `t` records no borrow of `t.buf`. So decision (2), which copies only `t`'s recorded borrows, would accept the first program, a new route into gap_96's class.
    - **Checked against the design principles (2026-11-18, the maintainer's question):**
      - Principle 1, not met as first written. Decision (2) assumes every place a local points into is a borrow it holds, but the open liveness gaps break that (P9). Today the tie to the referent covers for them. Fix: H3 (id:mqh84) now depends on id:z0044 (holder three, which closes gap_96) and id:kqp9n (holders one and two, gap_87 and gap_37). Both are placed later in the queue, so H3 cannot start where it stands. Reordering is the maintainer's: either move H3 after them, or keep H1 and H2 here (they change no verdict) and move H3 alone. P9 is a check for H3.
      - Principle 4, partly met. The `#[unsafe(borrows(*self))]` trust is marked in the source. But decision (3)'s rule, that a reference or slice read from the referent points only into what it holds, is also an obligation on every `unsafe` block that writes a view into a value's own storage without a borrow. Fix for H1: write that obligation in `doc/spec/unsafe_policy.md` and `doc/SAFETY.md` §4, beside the raw-pointer rules, so a reviewer of an `unsafe` block can check it.
      - Principles 2 and 3 are met: users write nothing, and the one annotation is on two stdlib functions. Principle 5 is met: the `// SAFETY:` line is checked by a script, never read by the compiler. Principle 6 is met: the accepted programs are what Rust accepts for a clone, and the attribute follows Rust's `#[unsafe(..)]` form. Principle 7 is met: there is no run-time cost, and the analysis grows by one word per set and one mask per summary; that cost is H1's to measure (compile time in `make preflight-changed`).
    - **The maintainer's decision (2026-11-18), against the end of `doc/design/provenance.md`:** a short step back is taken for the plan's sake. Probe 307 stays `compile_reject` (principle 1: a correct program refused while the analysis is imprecise; it is not on the store grid, the plan's definition of done). The decision above stands as the design, with its order changed: H1 (id:bfd1z) becomes a measurement before id:mrdtf, counting how many of id:z0011's 97 sites a held tie would free by inference (`Lexer.text_from` is the held shape). H2 (id:42ae2), H3 (id:mqh84) and the check-in id:22qty move to directly after id:z0044, since H3 needs id:z0044 and id:kqp9n (P9), and a trusted form and summary bit added before id:z0011 and id:z0012 are more for those to check and carry over. If H1's count is small, those three move to `future.tm.md`, to resume after id:z0012. The approval of `Vec.empty_like` and the `*self` form stays with H2's **Stop and report first**.
    - **Completion (2026-11-18):** a decision task; no code changed, so there is no code commit and no test run. C1 to C3: not run here; they are H3's (id:mqh84) checks C1, C3 and C4, by the split above. The findings' figures were each run with `build/zoril` at git:cd7e10d, as quoted in Findings 1 and 2 and under **Planted cases** (P1 to P5, P9 refused today; `p9_direct.zrl` exit 139). `tm validate --strict doc/tasks/*.tm.md` passes.

- [ ] +safety +precision +AI-D @provenance H1 The origin sets track which parameter contents may be owned by the referent, and the count of id:z0011's sites a held tie would free decides where the series goes id:bfd1z
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:2sdmk

    - **Placed:** directly after id:2sdmk, whose decision (3) it implements, and before id:mrdtf (B3b), whose cost it may change. H2 and H3 were moved after id:z0044 (the maintainer's decision of 2026-11-18, recorded in id:2sdmk).
    - **Reframed as a measurement (the maintainer's decision, 2026-11-18):** `doc/design/provenance.md` §5 names the 82 `#[borrows()]` narrowings id:z0011 has to prove or make exemptions, such as `Lexer.text_from`, "a view of source text in the compilation's arena". That is the held shape: the result points into what the lexer holds (its stored slice), not into the lexer. So before id:mrdtf turns each such site into a reviewed `unsafe` exemption, this task counts how many of id:z0011's 97 sites (**Measured** in id:z0011, `build/z97/measure.sh`) a held tie would justify by inference. The count decides: if it is large, the maintainer may bring H2 and H3 forward, or have id:mrdtf wait for them; if it is small, the series (H2, H3, id:22qty) moves to `future.tm.md`, to resume after id:z0012. The word is committed only if the count justifies the series; otherwise its patch is saved in this task's text (AGENTS.md, "Measurements and local changes") and nothing lands.
    - **Why `+AI-D`:** every write of `OS_W_CONTENTS` in `src/check_zir.zrl` has to be read to decide whether it writes `OS_W_OWNED` too (an audit), and a missed one is a wrong acceptance in H3.
    - **Scope:** the word, the two clearing rules, the held call, `ILFunction.os_ret_held` and its `--emit-origins` line, and the design note's paragraph in `doc/design/provenance.md` §3, with the obligation on `unsafe` code in `doc/spec/unsafe_policy.md` and `doc/SAFETY.md` §4 (id:2sdmk, principle 4). The borrow checker does not read it yet, so no program changes verdict.
    - **Checks:** C1: `build/zoril --emit-origins build/2sdmk/shapes.zrl` prints a held line for `hd` and none for `sl` (P1's shape) or `cl` (the arena is a raw read until H2). C2: P2's `S::clone` has no held bit, `[T].clone` and `Option<u8>.clone` have one. C3: with the type test in `os_through` taken out (every read writes `ParamOwned`), C1's `hd` loses its bit; with the clear on a reference read written as a clear on every read, `sl` gains one (the check sees the defect). C4: P6 written as a test, and its body gets no held bit. C5: if the word is committed, `make test` unchanged (`Total:` with 0 failed), `make preflight-changed`, and the rejection differential 0 newly accepted and 0 newly refused; if not, `not run`, with the patch in the task text. C6: for each of id:z0011's 97 sites (by root: `src/main.zrl`, zbuild, zilc, zman, and the 13 stdlib sites), whether the body's result tie to the narrowed parameter is held (no `ParamAddr`, no `ParamOwned` in `O(ret)` or `S(ret)`), with the counts per root, the held sites listed by `file:line`, and a sample of five non-held sites with the reason (an `unsafe` body, a raw read, a non-held callee). The before-figure is id:z0011's: 97 distinct sites, 85 under `src/main.zrl`. C7: the recommendation that follows from C6, for the maintainer.

- [ ] +safety +tests +AI-D @provenance B3b The `#[borrows(..)]` declarations and `&self` defaults of `src/` and `tools/` that name less than the body returns are removed, widened or made explicit exemptions id:mrdtf
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:mztqb

    - **Split from:** id:z0011, by its measurement of 2026-11-18: 85 sites in `src/main.zrl`'s closure, and in `tools/` 11 for zbuild, 8 for zilc and 2 for zman (stdlib sites included in those counts). The 12 `&self`-default sites include `src/check_zir.zrl:83`, `src/fmt/doc.zrl:221`, `src/lower_zir/expr.zrl:176` and `:2678`, and `src/parser/decl.zrl:333`.
    - **Placed:** before id:z0011, which it blocks (the self-hosting compiler is checked by its own rules). Depends on id:mztqb because the stdlib choices change what `src/` callers are refused.
    - **Size:** likely more than one session. Before starting, split it by directory (`src/lower_zir/` has 33 sites, `src/mono.zrl` 9), each part with its own checks.
    - **Constraint:** `src/` must still build under the pinned stage1 and the previous `build/zoril`, so a widened declaration or an `unsafe` interior has to be accepted by both. A removed `#[borrows()]` usually makes callers keep a borrow they did not keep before, so measure each removal by the default-build refusals in `src/` first.
    - **Checks:** per part, `build/z97/measure.sh <scratch with id:z0011's patch>` shows that part's sites gone, with none added elsewhere; `make test`; `make preflight-changed`.

- [ ] +safety +tests +AI-D @provenance id:z0011 B3 Declarations are checked against the body: `#[borrows(..)]`, `#[stores(..)]`, the `&self` default
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0049, id:z0064, id:0m61c, id:mztqb, id:mrdtf, id:akapm
    > **Check-in:** stop for review after it.

    - **Rule (Decision 1):** a declaration may list more than the body proves (a wider public contract), never less. For a function with a body the effective ties and stores are the union of what the body proves and any declaration (id:z0010 already sums them); a declaration that claims less than the body is a compile error, the narrowing rule of `CHANGELOG.md`'s pre-1.0 note. The `&self` elision default and the declarations apply as written to bodyless items (`extern`, trait signatures, `.zri` imports). Each of the tree's 82 `#[borrows()]` declarations (such as `Lexer.text_from`) is either proved unnecessary by id:z0010's `ParamAddr`/`ParamContents` summary and removed, or converted into an explicit, reviewed `unsafe` interior with a `// SAFETY:` comment, listed with its decision in the commit. **Stop and report** before changing a `pub` stdlib signature.
    - **Test expectation note:** `tests/error_reporting/err_stores_attribute_false.zrl` currently expects a wider `#[stores]` contract than the body performs to fail; under the wider-contract rule that test changes (stop and document the test change per `AGENTS.md`).
    - **Probes:** an unannotated `&self` method passing a parameter's borrow through, the same through a trait, and safe-code `#[borrows()]` laundering (`gap_30_borrows_attribute_launder` stays rejected; `gap_44_borrows_attr_reset` is rejected once checked declarations refuse the narrowing `#[borrows()]` (it is accepted, exit 77, under `--provenance` at `c323b0e`: a reset hole, not an escape, so the store rules do not see it)); accepted: a `&self` method returning a view of `self` and a wider `#[borrows]`/`#[stores]` public contract. `make test`, `make preflight-changed`. Stop for review.
    - **Blind spot not covered by this check (from id:z0049's review, 2026-11-05):** a body that copies through a bare `extern` proves no store, so a declaration can never be "narrower than the body" there (id:z0060's `extend_from_slice` route). Add a rule here or in a task of its own: a safe function that passes a pointer derived from a parameter to an `extern` with no declared effect must declare its own `#[stores]`/`#[borrows]` (or the `extern` declares its effect). Probe it with id:z0060's reproducer with id:z0060's fix taken out.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **Added by id:z0073's decision (the maintainer, 2026-11-14):** case B there. A safe function whose `unsafe` block writes a value that can hold a reference or a slice through a raw pointer (one it was given, or one an argument holds: `unsafe { *self.p = r; }`) must declare `#[stores(..)]` naming the argument stored and the one it is stored into, or it is a compile error; the declaration is then a trusted claim (`doc/SAFETY.md` §4.2) and the caller applies the call store rule to it. It is one rule with the bare-`extern` rule of the **Blind spot** bullet above: a safe function may not hide a store behind an operation the checker cannot read. Probe: `put` with and without the declaration (`build/z76/cx.zrl` in id:z0076's text), a caller passing `&x` of a local with `g` reaching outside the frame (refused once declared), the same store of a plain integer (no declaration needed), and the count of functions in `stdlib/`, `src/` and `tools/` that newly need a declaration, measured before the rule is made an error. If that count makes this task more than a session, split the rule into a task of its own directly after this one.
    - **Measured (2026-11-18, on `stream/provenance` at git:5ca36fb):** the check below (`os_check_ties`, patch under **Patch**), built as `build/z11/zoril.new`, refuses under `--provenance` every function whose final body summary ties its result to a parameter `ret_ties` leaves out. The body ties are the ones `os_call` reads: `os_ret_addr`, plus `os_ret_contents` unless the result holds only integers (`os_holds_pointer`). Both sides are limited to types that can hold a reference (`ILModule.type_holds_reference`, raw pointers included), as `inherit_rv_borrows` is, so `grow_cap(cap: usize) -> usize` is not refused. Closures (a trailing `__env`), `extern` items and `.zri` imports are skipped. It runs after `store_origin_summary` for a body outside a cycle, and in `os_fixpoint`'s checking pass for one inside a cycle. `--provenance=warn` makes the refusal a warning.
      - Probes (`build/z11/run.sh`; default build, then `build/z11/zoril.new --provenance`): `gap_44` exit 77, then refused at its `text_from` ("#[borrows(..)] leaves out 'self' ..."); `gap_30` refused, then refused at `launder` by the new check; `selfpass` (unannotated `pick(self: &S, x: [u8]) -> [u8] { return x; }`, then an arena reset) exit 77, then refused ("the result may point into 'x', which the `&self` default does not tie it to"); the trait form `traitpass`, the same; `s.clone()` of a slice, then a reset, exit 77, then refused at `stdlib/core.zrl:258`. These three new holes are probes `gap_99`, `gap_100`, `gap_101` (git:e14d03d), and they stay `known_gap` until the rule is on by default (id:z0065, id:z0012). A generic `id<T>(x: T) -> T` and `v.iter().map(f)` are refused by the default build already.
      - **Counts (`build/z97/measure.sh`, `--provenance=warn`):** 97 distinct sites. Roots: `src/main.zrl` 85 (183 provenance warnings, 268 with the check); zbuild 11, zilc 8, zman 2 (stdlib sites counted again for each root). Test programs: 58 warnings, all at stdlib sites. 12 of the sites are the `&self` default (`src/check_zir.zrl:83`, `src/fmt/doc.zrl:221`, `src/lower_zir/expr.zrl:176` and `:2678`, `src/parser/decl.zrl:333`, and 7 in stdlib); the rest are `#[borrows(..)]` declarations.
      - **Stdlib sites (13; each changes a `pub` contract, so the maintainer decides first):** `args.zrl:46` `Args.get`, `:85` `Args.next`; `bufio.zrl:36` `BufWriter.with_capacity`, `:234` `BufReader.with_capacity` (`inner` by value, a type parameter); `clone.zrl:17` `Clone for Vec<T>` (gap_77), `:35` `Clone for String`; `core.zrl:242` `Clone for Option<T>` (gap_78), `:258` `Clone for [T]` (gap_99); `file.zrl:144` `read_to_end_sized_raw`; `iter.zrl:26` `Iterator.map` (by-value `Self`: an over-report, since the default build refuses that route); `string.zrl:186` `String.clone_in_raw`, `:326` `split_raw`; `vec.zrl:155` `Vec.clone_in_raw`. The last three are `unsafe fn`s whose result is tied to a raw `arena: *mut ArenaHeader` that the `&self` default leaves out.
      - **Tests the check breaks** (`ZORIL_CC=build/z11/zoril.new ./scripts/test.sh tests/language tests/stdlib tests/error_reporting`: `Total: 1068 run, 1063 passed, 5 failed, 0 skipped (7.9s)`), all `// flags: --provenance` tests under `tests/language/memory/provenance/`: `arena_named_through_vec_reference_accepted` (its own two `#[borrows()]`, lines 16 and 20), `clone_returned_accepted` (`core.zrl`, `clone.zrl`), `popped_integer_carries_no_address_accepted` (its own `#[borrows()] fn at0`, whose `Cmd` result holds `text`), `unsafe_fn_summary_accepted` and `unsafe_fn_summary_cycle_accepted` (`string.zrl:326`). So the check cannot land before the stdlib sites are settled, and the two tests' own declarations change their text (stop and report, per `AGENTS.md`).
      - **Not done in this session:** the `#[stores]` wider-contract change (`err_stores_attribute_false.zrl`), the bare-`extern` and raw-store rule (case B), and the 85 `src/` and the `tools/` sites. Split into tasks: id:mztqb, id:mrdtf before this one, and id:f81f3 after it.
      - **Patch** (`build/z11/z0011-check.patch`, against git:5ca36fb; apply with `git apply`):
    ```diff
    diff --git a/src/check_zir.zrl b/src/check_zir.zrl
    index 86da7c2..2d969a6 100644
    --- a/src/check_zir.zrl
    +++ b/src/check_zir.zrl
    @@ -8286,6 +8286,72 @@ pub fn store_origin_summary(
         return grew;
     }
     
    +// The parameters FUNC's result may point into by its final body summary, as a call reads them
    +// (os_call): its ParamAddr ties, and its ParamContents ties unless the result holds only integers.
    +fn os_body_ties(c: &mut OriginSets, module: &ILModule, f: &ILFunction) -> u64 {
    +    if f.ret_ty == 0 as u32 || !os_carries(c, module, f.ret_ty) { return 0 as u64; }
    +    if !os_holds_pointer(module, f.ret_ty, 0 as usize) { return f.os_ret_addr; }
    +    return f.os_ret_addr | f.os_ret_contents;
    +}
    +
    +// `#[borrows(..)]` and the `&self` default are checked against the body (§3, _Checked
    +// contracts_): a call's borrows (inherit_rv_borrows) and every importer read `ret_ties`, so a
    +// result tied in the body to a parameter `ret_ties` leaves out would end that borrow while the
    +// result still points into it. A declaration may be wider than the body, never narrower. A
    +// closure's ties are its environment's, which no declaration names. A rule of `--provenance`,
    +// beside the others until they are the default. Returns the refusals.
    +pub fn os_check_ties(c: &mut OriginSets, module: &ILModule, idx: usize, span: Span) -> u32 {
    +    let f = &module.functions[idx];
    +    if c.rules == PROVENANCE_OFF || f.from_interface || f.is_extern { return 0 as u32; }
    +    if f.params_len > 0 as usize
    +        && type_name_is(c.table.lookup(f.param(f.params_len - 1 as usize).name), "__env") {
    +        return 0 as u32;
    +    }
    +    // A borrow is held only by a value whose type can hold a reference (inherit_rv_borrows), so
    +    // an integer result or argument carries none, whatever address its bits may hold.
    +    if f.ret_ty != 0 as u32 && !module.type_holds_reference(f.ret_ty, 0 as usize) {
    +        return 0 as u32;
    +    }
    +    let missing = os_body_ties(c, module, f) & !f.ret_ties;
    +    if missing == 0 as u64 { return 0 as u32; }
    +    let base = if f.params_len > 0 as usize && f.param(0).name == c.sret_name {
    +        1 as usize
    +    } else {
    +        0 as usize
    +    };
    +    let mut i = 0 as usize;
    +    while i < 63 as usize {
    +        if (missing >> (i as u64)) & 1 as u64 != 0 as u64
    +            && i + base < f.params_len
    +            && module.type_holds_reference(f.param(i + base).ty, 0 as usize) {
    +            let name = c.table.lookup(f.param(i + base).name);
    +            diag_start(c.file, span, if c.rules == PROVENANCE_WARN { "warning" } else { "error" });
    +            eprint("provenance: ");
    +            if f.has_borrows {
    +                eprint("#[borrows(..)] leaves out '");
    +                eprint(name);
    +                eprint("', which the result may point into; ");
    +                eprint("a declaration may name more than the body returns, never less\n");
    +            } else if f.ret_ties == 1 as u64 && i != 0 as usize {
    +                eprint("the result may point into '");
    +                eprint(name);
    +                eprint("', which the `&self` default does not tie it to; add `#[borrows(self, ");
    +                eprint(name);
    +                eprint(")]`\n");
    +            } else {
    +                // A by-value `Self` or type parameter, whose declared type showed no reference.
    +                eprint("the result may point into '");
    +                eprint(name);
    +                eprint("', which the elision default does not tie it to; ");
    +                eprint("add `#[borrows(..)]` naming it\n");
    +            }
    +            return 1 as u32;
    +        }
    +        i = i + 1 as usize;
    +    }
    +    return 0 as u32;
    +}
    +
     // A direct call's result, into OS_T_VO and OS_T_VS, from the callee's summary: an argument in
     // `ret_storage` gives its own origins (the result points into it); one in `ret_ties` gives what is
     // reached through it when it is a reference, and itself and what it reaches otherwise. An owning
    diff --git a/src/driver/module.zrl b/src/driver/module.zrl
    index 9a602f3..d5e31b4 100644
    --- a/src/driver/module.zrl
    +++ b/src/driver/module.zrl
    @@ -1271,6 +1271,14 @@ impl Driver {
                 e.func_idx as usize,
                 &mut origins
             );
    +        if check {
    +            let span = self.module.functions[e.func_idx as usize].decl_span;
    +            let refused =
    +                check_zir::os_check_ties(&mut origins, self.module, e.func_idx as usize, span);
    +            if refused > 0 as u32 && self.provenance == check_zir::PROVENANCE_ON {
    +                self.had_error = true;
    +            }
    +        }
             if check && self.emit_origins && e.source_file == self.target_source_file {
                 check_zir::print_origins(&origins, &e.zir, self.module, self.intern_table);
             }
    @@ -1357,6 +1365,14 @@ impl Driver {
                 self.builder.current_func_idx as usize,
                 &mut origins
             );
    +        if !in_cycle {
    +            let idx = self.builder.current_func_idx as usize;
    +            let span = self.module.functions[idx].decl_span;
    +            let refused = check_zir::os_check_ties(&mut origins, self.module, idx, span);
    +            if refused > 0 as u32 && self.provenance == check_zir::PROVENANCE_ON {
    +                self.had_error = true;
    +            }
    +        }
             if in_cycle {
                 self.os_pending.push(OsPending {
                     func_idx: self.builder.current_func_idx as u32,
    ```
    - **Depends changed (2026-11-18, by this task's measurement):** added id:mztqb and id:mrdtf, the declarations the check refuses; it cannot land before them.
    - **Left here:** apply the patch; add tests under `tests/language/memory/provenance/` (a narrowing `#[borrows()]` refused, a wider one accepted, a `&self` method returning a view of `self` accepted, the `&self` default passing another parameter refused, its trait form refused); the `#[stores]` wider-contract change and the `err_stores_attribute_false.zrl` expectation (stop and report it); `make test`, `make preflight-changed` with the differential. `gap_44`, `gap_99`, `gap_100` and `gap_101` flip when the rule is on by default (id:z0065, id:z0012), not here.
    - **Decision (2026-11-18, the maintainer):** three tiers, recorded in `doc/design/provenance.md` §3, _Checked contracts_. (1) Inferred: with no declaration, the body's ties are added to the elision default (body plus default; body-only waits for id:f81f3 and the differential). (2) Checked: `#[borrows(..)]` may name more than the body returns, never less. (3) Trusted narrowing: `#[unsafe(borrows(..))]` (id:akapm). This replaces the earlier plan of refusing the `&self` default with "add `#[borrows(self, x)]`", which put the notation on every user.
    - **Landed: tier 1, git:21658fa.** `os_infer_ties` adds the body's ties (the same set `os_call` reads, over parameters whose type can hold a reference) to `ret_ties` for any function with a body and no declaration. `ILFunction.ties_inferred` makes the `.zri` write them as `#[borrows(..)]`. `ILFunction.os_in_cycle` with `os_depth` makes the borrow checker read a call into an unfinished recursive cycle as tied to every argument. The one `src/` refusal (`lower_zir/expr.zrl`, `lowered.set(ai, self.check_arg_against(lowered.as_slice()[ai], ..))`) writes the converted arguments into a second vector. gap_100 and gap_101 are flipped to `compile_reject`.
      - **Cost (`build/z11/cost.sh build/zoril`):** 0 default-build refusals over the five roots and the 739 test programs that compile by default. Variant B, which also widens explicit declarations (the union in default mode), refuses 934: `src/main.zrl` 900, zilc 30, zbuild 4. So the tree's narrowing declarations carry weight, and each needs its own decision (id:mztqb, id:mrdtf).
      - **Sibling routes** (`build/z11/p/`, base = git:e14d03d's compiler): `&mut self` (`mutself`), an aggregate result (`aggr`), self-recursion (`cycle_inner`) and mutual recursion (`cycle_mutual`) were accepted by the base (exit 77 or a use of a cleared Vec's view) and are refused now. A closure (`closure`), a generic identity and `iter().map(..)` were refused already. A call through a generic `via<T: Pick>(t: &T, x)` is refused by the free function's own default, so the trait test calls the impl directly.
      - **Across a `.zri`:** `tests/modular/iface_attrs/lib_ties.zrl` with `reject_ties_inferred.zrl` and `accept_ties_inferred_twin.zrl`; `scripts/test_interface_attrs.sh` checks that `pick` gets `#[borrows(self, x)]` and `view` gets none.
      - **Take-outs:** inference off (scratch `build/z11/src_t1`) fails `inferred_ties_self_method_other_param_refused`, `_mut_self_..`, `_aggregate_result_refused` and `_trait_method_..` (direct call). The cycle rule off (`build/z11/src_t2`) fails `inferred_ties_self_recursion_refused` and `_mutual_recursion_refused`. The interface line off fails `test_interface_attrs.sh` ("the interface lost the ties pick's body adds to the default"), and zbuild then accepts `reject_ties_inferred.zrl` while whole-program refuses it.
      - **Checks:** `make test` `Total: 3852 run, 3852 passed, 0 failed, 106 skipped (139.3s)`; `sh scripts/run_safety_matrix.sh` "All probes complete: 475/527 passed. Mismatches: 0"; `make preflight-changed` below.
      - **Preflight (2026-11-18, tree at git:3cf6b86):** `REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=e14d03d`, rc=0: "All mutations caught."; `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`; `reject-diff: base verdicts: fresh (no cache)` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 2542 newly refused, of 69167 programs against e14d03d9cbe8331d4dc753f8cd78d3d0c7f93c31` (2538 unsafe store-grid cells and gap_100/gap_101 whole-program and under zbuild; no safe twin); checked build `Total: 1477 run, 1477 passed, 0 failed, 0 skipped (108.2s)`; git group `Total: 8 run, 8 passed, 0 failed, 0 skipped (102.2s)`; "All performance thresholds within tolerance of baseline." An earlier run failed only in the `tool-versions` scenario, because docs were edited during it (the tree was dirty). `make test-changed BASE=21658fa` after the record and doc commits: `Total: 3852 run, 3852 passed, 0 failed, 106 skipped (139.2s)`.
      - **Store grid re-recorded:** git:4ef0cf0 removes exactly the 2538 cells the differential reported (class report 51 -> 35: the method, self_method and trait_method paths and the call_method carrier). git:1e1805c removes 106 entries of `store_grid_modular_prov_twin_rejections.txt` that were already stale before this change: recorded with e14d03d's compiler, which changes only that file. The fuzz record is stale after this `src/` change (`bench/fuzz/README.md`).
      - **A gap the design accepts, beside the cycle rule:** a body lowered while a cycle is open, which calls a member that has finished but is still waiting for the fixpoint, reads that member's ties through `os_in_cycle` (all arguments). The origin rules of such a body still read the member's partial summary. That predates this change, and is noted for id:z0065's measurement.
    - **Depends changed (2026-11-18):** added id:akapm, the tier-3 form the remaining narrowings need.
    - **Left here (tier 2):** a declaration narrower than the body is refused (the patch above, `os_check_ties`, reduced to the `has_borrows` branch); the `#[stores]` wider-contract change and the `err_stores_attribute_false.zrl` expectation (stop and report). These land after id:mztqb and id:mrdtf. gap_44 and gap_99 flip when the tree's narrowings are settled. The **Patch** above predates git:21658fa (it adds `os_check_ties` where `os_infer_ties` now stands), so it no longer applies: write the tier-2 check fresh as one more branch of `os_infer_ties` (a function with `has_borrows` whose body ties are not all in `ret_ties`), refusing under `--provenance` as the patch did.
    - **Found by id:mztqb (2026-11-18):** a `#[unsafe(borrows(..))]` callee's trust does not reach its callers under `--provenance`. `os_call` builds the call's result from the callee's body summary, so `Args.next`, which returns `self.get(..)` of a trusted `Args.get`, is still tied to `self` and needs a mark of its own. **Decide here:** whether the call reads a `borrows_trusted` callee's `ret_ties` instead of its body ties (reproducer and counts under id:mztqb's **Re-measured**).

- [ ] +safety +tests +AI-D @provenance B3c A safe function may not hide a store behind a bare `extern` or a raw-pointer write: it declares `#[stores(..)]` id:f81f3
    > **Created:** 2026-11-18
    > **Branch:** `provenance`

    - **Split from:** id:z0011, whose **Blind spot** bullet (id:z0049's review) and **Added by id:z0073's decision** bullet (case B, the maintainer, 2026-11-14) describe one rule: a safe function may not hide a store behind an operation the checker cannot read. Split off because id:z0011's ties check and its 13 + 85 sites fill a session already. The task text there allows this ("If that count makes this task more than a session, split the rule into a task of its own directly after this one").
    - **Placed:** directly after id:z0011, as that bullet asks.
    - **Rule:** a safe function that passes a pointer derived from a parameter to an `extern` that declares no effect, or whose `unsafe` block writes a value that can hold a reference or a slice through a raw pointer (one it was given, or one an argument holds: `unsafe { *self.p = r; }`), must declare `#[stores(..)]` (or `#[borrows(..)]`) naming what it stores and where, or it is a compile error. The declaration is then a trusted claim (`doc/SAFETY.md` §4.2), and the caller applies the call store rule to it.
    - **Probes:** id:z0060's reproducer with id:z0060's fix taken out; `put` with and without the declaration (`build/z76/cx.zrl` in id:z0076's text); a caller passing `&x` of a local where `g` reaches outside the frame (refused once declared); the same store of a plain integer (no declaration needed).
    - **Measure first:** count the functions in `stdlib/`, `src/` and `tools/` that newly need a declaration, with the rule as a warning, before making it an error.

- [ ] +safety +tests +AI-D @provenance L2a A call summary records which arguments the callee may release id:bfcvm
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Depends:** id:dhded
    > **Placed:** directly before id:kqp9n (L2), which it blocks: L2's release tier conflicts only with a release, and it learns of a release from this fact.

    - **Design:** `doc/design/provenance.md` §3.1, item 2 (git:bdfcac6). The summary gets one new fact, `releases i`: the callee may release storage argument `i` reaches. It is computed from bodies, as the store edges are. A body releases `i` when it calls a releasing primitive on memory whose origins include `ParamAddr(i)` or `ParamContents(i)`, or calls a function whose summary releases an argument carrying them. A call through a `fn` value with no known callee releases everything its arguments and environment reach.
    - **Decide first, and record here:** how the releasing primitives are marked. They are `zoril_allocator_free` (`stdlib/mem_raw.zrl`, the only call to it in `stdlib/` is `Vec.free`) and the arena's reset and free (`stdlib/mem.zrl`: find each body that ends an arena's allocations). Either a trusted attribute on those few bodyless or `unsafe` items, as `#[fresh]` is (§3, _Raw operations_), or something else the design note's rules allow; no list of names in the checker. An `extern` releases nothing unless it is marked.
    - **Do:** compute `releases` in the origin pass (every mode: `os_pass_pending` runs with the rules off by default), keep it through a recursive cycle's fixpoint, write it into the `.zri` beside the store edges, and print it with `--emit-origins` (`releases 0`). Nothing reads it yet, so no program's verdict changes.
    - **Checks:**
        - C1: golden tests under `tests/language/memory/origins/` whose `--emit-origins` shows `releases 0` for `Vec.free`, for each arena reset and free, for `fn kill(v: &mut Vec<i32>) { v.free(); }`, and for a two-level wrapper of `kill`; and no `releases` for `Vec.push` (growth keeps the old buffer: `Vec.grow_to` frees nothing), a getter, and `fn put(out: &mut [i32], v: &Vec<i32>) { *out = v.as_slice(); }`.
        - C2: a recursive pair, one member freeing its argument, where both members' summaries release it.
        - C3: a `.zri` round trip under `tests/modular/iface_attrs/`: a module's releasing function, imported, prints the same `releases` as when compiled whole-program.
        - C4: take the primitives' mark out and watch C1's `Vec.free` golden fail; take the cycle step out and watch C2 fail.
        - C5: no verdict changes: `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, quoting the `Total:` lines and `reject-diff: base verdicts: fresh (no cache)` with 0 newly accepted and 0 newly refused.

- [ ] +safety +tests +AI-D @provenance L2 A view stored through a parameter keeps what it views borrowed for the rest of the body (gap_87) id:kqp9n
    > **Created:** 2026-11-14
    > **Branch:** `provenance`
    > **Depends:** id:dhded, id:bfcvm
    > **Check-in:** stop for review after it: a fix to a safety rule.

    - **Placed:** after L1 (id:dhded), which settles its rule, and before id:z0044, its caller-side twin.
    - **Closes:** `gap_87_view_stored_through_param_outlives_free`.

    - **Found (2026-11-14, a review of the plan; probe in git:172c77e on `main`):** `fn k2(out: &mut [i32], v: &mut Vec<i32>) { *out = v.as_slice(); v.free(); }` is accepted by `build/zoril` at git:a662fda (built with `scripts/build_zrl.sh`, run: exit 77 where the buffer held 42) and compiles under `--provenance` on `provenance` at git:92bb15f (`build/zoril --provenance --emit-zil`, rc 0, not run). Accepted the same way, exit 77 on `main`:
      - `fn k2(out: &mut Vec<[i32]>, v: &mut Vec<i32>) { out.push(v.as_slice()); v.free(); }`
      - two callees: `fn fill(h: &mut H, v: &mut Vec<i32>) { h.s = v.as_slice(); }`, `fn kill(v: &mut Vec<i32>) { v.free(); }`, `fn both(h: &mut H, v: &mut Vec<i32>) { fill(h, v); kill(v); }`
      - one parameter: `struct P { a: Vec<i32>, s: [i32] }`, `fn poison(p: &mut P) { p.s = p.a.as_slice(); p.a.free(); }`
    - **Refused today (the twins to keep refused):** the one-parameter form on a local (`p.s = p.a.as_slice(); p.a.free();` in `main`: `cannot mutably borrow 'p.a' while it is already borrowed`), and `let s = v.as_slice(); v.free(); return s[0];`.
    - **Not shown:** `v.push(..)` in place of `v.free()` compiles and the run returned 42 (the old buffer was not reused), so the reallocation route is accepted but not demonstrated; L1 probes it.
    - **Route class:** a view of what a parameter reaches, stored into what a parameter reaches, then invalidated in the same body. id:z0044 does not close it as written: it carries the borrow "to the local the pointer refers to", and here there is none.
    - **Not ready:** L1 writes this task's **Do:** and numbered **Checks:**. They include: `gap_87` flipped to `compile_reject` with its Known gaps entry and `doc/SAFETY.md` §6 class (M) removed; the three sibling forms above as `compile_reject` probes; an accepted twin for each (the store with no later invalidation; the invalidation before the store); the fix taken out and `gap_87` watched to run (exit 77); the rejection differential with every newly refused program listed; `make test` and `make preflight-changed`, each `Total:` quoted.

    - **Ready (2026-11-17, L1 = id:dhded):** the **Not ready** bullet above is answered by `doc/design/provenance.md` §3.1 (git:bdfcac6). This task is holders one and two (the in-body half). id:z0044 is holder three (the caller's half).
    - **Closes (from L1):** `gap_87`, and from id:z0044's former list `gap_37` and `gap_43`, which are in-body (a local `&mut` and a `Box`).
    - **Do:**
        1. In `check_assign`'s two arms for a write through a pointer (`place_writes_through_pointer`; L1's census found no other in-body site), read the destination reach of the written place from the function's origin sets. The origin pass runs on every body in every mode (`os_pass_pending`), so the sets exist without `--provenance`; check that they are computed before the borrow checker runs on the body, and make them so if not.
        2. Holder one: for each `Frame(L)` in the reach, `L` receives the value's borrows, as `w.s = ..` gives them to `w` (the same propagation, `direct` false). These are strict-tier borrows: any `&mut` use of the borrowed place conflicts, as today.
        3. Holder two: a `Param`, `Static`, `Raw` or `Unknown` origin in the reach gives the value's borrows to the frame's outside holder, live until return. These are release-tier borrows: only a release conflicts. A release is a call whose summary releases an argument reaching the borrowed place (id:bfcvm), an `@drop`, or a move or whole overwrite of the owner. Mark the tier on the borrow (a field of `ActiveBorrow`), so that `borrow_counts` and the conflict checks can tell the two apart.
    - **Checks:**
        - C1: `gap_87` refused, with its expectation flipped to `compile_reject`, its Known gaps entry removed and class (M) removed from `doc/SAFETY.md` §6 and §6.1 (no probe count touched).
        - C2: `gap_37` and `gap_43` refused and flipped the same way; class (G)'s text keeps only the routes still open.
        - C3: `compile_reject` probes for L1's p4 (the trait method, `build/provenance/build/dh/p4_trait.zrl`), `out.push(v.as_slice()); v.free();`, and the one-parameter `p.s = p.a.as_slice(); p.a.free();`.
        - C4: accepted twins as tests, each built and run with its exit quoted. The store with no later release; the release before the store; `*out = v.as_slice(); v.push(1);` (release tier: growth is no release); and the field read before `a.reset()` for `gap_37` and `gap_43`. Plus a refused strict-tier twin: `let r = &mut w; r.s = v.as_slice(); v.push(1); w.s[0]`, refused as `w.s = v.as_slice()` is today.
        - C5: the compiler builds as before. `make` succeeds with `src/`'s and zilc's 14 intern-table stores accepted (`self.file_path = self.intern_table.lookup(..)`, which L1's strict scratch refused 142 times), and `build/z97/measure.sh` reports no new error in `tests/` or `stdlib/`.
        - C6: take holder two out and watch `gap_87` build and run 77. Take the tier out (count every borrow as strict) and watch C5's build fail on the first intern-table store.
        - C7: `make test`; `REJECT_DIFF_NO_CACHE=1 make preflight-changed` with `reject-diff: base verdicts: fresh (no cache)` quoted, and every newly refused program listed with its reason. This rule acts in the default mode too, so `main`'s behaviour changes when the branch merges; say so in the completion note.

- [ ] +safety +tests +AI-D @provenance id:z0044 B0.1 A value stored into a local's field through a pointer to the local keeps its borrow
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Check-in:** stop for review after it.
    > **Depends:** id:z0010, id:dhded, id:bfcvm, id:kqp9n

    - **Closes:** `gap_37_local_mutref_field_reset`, `gap_38_param_field_reset`, `gap_39_method_self_field_reset`, `gap_43_box_field_reset`.
    - **Depends changed (2026-11-14, the maintainer, in a review of the plan):** added id:dhded (L1), the liveness model: L1 decides whether this task's per-local borrow is the rule and rewrites its Do and Checks.

    - **Scope (narrowed to intra-frame liveness, 2026-11-03):** the frame-escape siblings (`gap_40`–`gap_42` and `gap_45`) are handled by id:z0048/id:z0012's origin sets. This task fixes intra-frame `Arena::reset` / `free` / `@drop` liveness (`ActiveBorrow` in `src/check_zir.zrl`), where a slice written into a local struct's field or a `Box`'s contents through a local `&mut`, through a callee's `&mut` parameter, through `self` in a `&mut self` method, or through `*b` on a `Box` is skipped today (`place_writes_through_pointer`), letting `a.reset()` pass while the field is read afterwards.
    - **Do:** carry the stored value's borrows to the local (or `Box` local) the pointer refers to: for a local `&mut` or `Box` deref, through the pointer's borrow/ownership of that local; for a callee, through id:z0010's pairwise `i -> j` store summary (`#[stores(..)]` checked in id:z0011). Probe the sibling routes: a `&mut` held in a struct field, a reborrow, a closure capturing `&mut w` across `a.reset()`, and a trait method; also verify `gap_44_borrows_attr_reset` is rejected once checked `#[borrows()]` is active.
    - **Found by id:z0047 (pre-existing over-rejection):** `fn f(view: [i32]) -> i32 { let mut w = ...; let r = &mut w; r.s = view; ... }` called with stack `f(&data)` is refused today by `src/summary_pass.zrl`; confirm id:z0012's retirement of `summary_pass.zrl` removes that refusal without reopening any reset hole.
    - **Probes:** `gap_37`, `gap_38`, `gap_39` and `gap_43` flip to `compile_reject`, with an accepted twin for each (the field is read before `a.reset()`). Check the over-rejection recorded on id:z0017 does not grow.
    - **Verification:** `make test`, `make preflight-changed`, the rejection differential; `bench/fuzz/README.md` stays stale for `src/`. Stop for review.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

    - **Rewritten by L1 (id:dhded, 2026-11-17; design `doc/design/provenance.md` §3.1, git:bdfcac6):** this task is now holder three, the caller's half. The in-body routes moved to L2 (id:kqp9n): `gap_37` (a local `&mut`) and `gap_43` (a `Box`). The **Do:** and **Probes:** above are superseded by the two bullets below, and the `summary_pass.zrl` note above stands.
    - **Closes (from L1):** `gap_38`, `gap_39`, `gap_96` (found by L1), and `gap_87`'s two-callee form (`fill(h, v); kill(v);`). `gap_44` is id:z0011's: the `#[borrows()]` it trusts is a declaration checked against the body, not a holder. So this task no longer depends on id:z0011 (**Depends changed** below).
    - **Do:** at a call, for each store edge `i -> j` of the callee's summary, every local whose `Frame` the destination reach of argument `j` has receives the borrows argument `i` carries. When the edge stores what `i` reaches, each also receives a borrow of the place argument `i` refers to. A target outside the caller's frame goes to the caller's outside holder (L2). All of these are release-tier borrows (L2's mark): they conflict only with a release, so a self-edge `i -> i` (`p.lex(); p.lex();`) is accepted, and `p.lex(); p.free_all();` with `p` still read is refused when `free_all` releases `p`. A call through a `fn` value with no known callee counts as storing every argument into every other, as the escape rules count it.
    - **Checks:**
        - C1: `gap_38`, `gap_39` and `gap_96` refused, each flipped to `compile_reject`, with its Known gaps entry removed and class (G)'s text in `doc/SAFETY.md` §6 and §6.1 updated (no probe count touched).
        - C2: `gap_87`'s two-callee form as a `compile_reject` probe (`fn both(h: &mut H, v: &mut Vec<i32>) { fill(h, v); kill(v); }`).
        - C3: accepted twins as tests, built and run with their exits quoted. `put(&mut s, &v); v.push(1); s[0]` (release tier); `put(&mut s, &v); kill(&mut v);` with `s` not read after; a method storing a view of `self`'s own `Vec` into `self`, called twice; and the reset before the call for `gap_38`.
        - C4: the measurement L1 left to this task: the programs of `tests/`, `stdlib/` and the four tool roots the base accepts and this refuses, read one by one in the completion note. The design's claim is that the release tier refuses none that are safe.
        - C5: take the summary step out and watch `gap_96` build and run 77; make the borrows strict and watch C3's method-called-twice twin be refused.
        - C6: `make test`; `REJECT_DIFF_NO_CACHE=1 make preflight-changed` with `reject-diff: base verdicts: fresh (no cache)` quoted and each newly refused program listed. This acts in the default mode, as L2 does.
    - **Depends changed (2026-11-17, L1):** added id:kqp9n (L2, for the outside holder and the tier mark) and id:bfcvm (`releases`). Removed id:z0011, which this task needed only for `gap_44`; `gap_44` is id:z0011's own.

- [ ] +safety +precision +AI-G @provenance H2 `#[unsafe(borrows(*self))]` declares a result tied only to what the referent holds; the interface carries it; Vec and String clones use it id:42ae2
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:bfd1z

    - **Placed:** after id:bfd1z, whose `ret_held` it sets by declaration; id:2sdmk's decision (4).
    - **Moved (2026-11-18, the maintainer's decision):** from directly after id:bfd1z to directly after id:z0044, with H3 and the check-in id:22qty. H3 cannot land before id:z0044 and id:kqp9n (P9 of id:2sdmk), and a trusted form and summary bit added before id:z0011 and id:z0012 are more for those to check and carry over. H2 stays tied to H3, so it moves with it. If id:bfd1z's count is small, the three move to `future.tm.md` instead.
    - **Stop and report first:** `Vec.empty_like` is a new `pub` stdlib method and `Clone for Vec<T>`'s body changes; both wait for the maintainer's approval of id:2sdmk.
    - **Scope:** the parser accepts `*self` (and `*p` for a reference parameter `p`) only inside `#[unsafe(borrows(..))]`, setting the parameter's `ret_held` bit as well as its `ret_ties` bit; the interface writers keep the form and write a `ret_held` `#[summary]` key; `scripts/check_safety_comments.sh` requires a `// SAFETY:` line above it as for the other `#[unsafe(..)]`; `doc/spec/surface_syntax.md` and `doc/spec/unsafe_policy.md` name it. Stdlib: `Vec.empty_like` with the declaration, `Clone for Vec<T>` rewritten on it with no `unsafe`, `Clone for String` with the declaration.
    - **Checks:** C1: `tests/error_reporting/` tests: `*self` in a plain `#[borrows(..)]` refused, `*x` for a by-value parameter refused. C2: `--emit-origins` on `build/2sdmk/shapes.zrl` shows a held bit for `cl` (`Vec<[u8]>`) and none for `Vec<S>.clone` (P2). C3: `tests/modular/iface_attrs/` case: the `.zri` of a module with the declaration has `ret_held`, and an importer reads it (the key removed from the `.zri` by hand: the importer's held bit is gone). C4: `make test`, `make preflight-changed`, rejection differential with no newly accepted program (the borrow checker does not read `ret_held` until H3).

- [ ] +safety +precision +AI-G @provenance H3 A call tied to an argument only through what its referent holds borrows what the referent holds, not the referent, so probe 307 is accepted id:mqh84
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:42ae2, id:z0044, id:kqp9n

    - **Placed:** after id:42ae2; id:2sdmk's decision (2), and id:2sdmk's checks C1 to C3.
    - **Moved (2026-11-18, the maintainer's decision):** with id:42ae2, to after id:z0044; its blockers id:z0044 and id:kqp9n are now before it (see id:42ae2).
    - **Scope:** `inherit_rv_borrows`'s `Call` arm reads the callee's `ret_held`, as decision (2) says; P1 to P8 of id:2sdmk become tests (`tests/language/memory/` or probes) with their expected verdicts; probe 307 flipped to `accept`.
    - **Checks:** C1: probe 307 `accept`; gap_77, P1, P2, P3, P5, P6, P8 and P9 refused, each as a test. C2: with the copy of the referent's borrows taken out (the direct borrow dropped, nothing copied), P3 and P5 are accepted (the check sees the defect); restored, refused. C3: P7: `sh scripts/run_safety_matrix.sh` with 0 mismatches, and the `safety-matrix-zbuild` and `zbuild-diff` gates pass. C4: `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, every newly accepted program listed with its reason.
    - **Ends with a check-in:** the `@checkin` task after it reviews H2 and H3.

- [ ] +safety +AI-D @provenance @checkin Check-in: review H2 and H3 (the trusted held declaration, and the caller rule that frees probe 307) id:22qty
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:42ae2, id:mqh84

    - **Placed:** directly after id:mqh84, the batch it reviews (H2, H3; H1 is `+AI-D` and closes itself).
    - **Moved (2026-11-18, the maintainer's decision):** with id:42ae2 and id:mqh84, to stay directly after the batch it reviews.
    - **Review:** re-run H3's C1 to C3 and P1 to P8 of id:2sdmk; probe the sibling routes: a held tie through a trait call resolved per instance, a `Box` receiver, a field receiver (`s.v.clone()`), a `match` binding receiver, and an import whose `.zri` has no `ret_held` key.

- [ ] +diagnostics +AI-G @provenance id:z0066 B3.9 Provenance diagnostics name the origin they found, once per site
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Depends:** id:0m61c

    - **Found by:** id:z0049's review (correction 8).

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

- [ ] +safety +review +AI-D @provenance @checkin Review of the provenance diagnostics wording and de-duplication (id:z0066) id:h1yk5
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Depends:** id:z0066

    - **Placed:** directly after id:z0066, the `+AI-G` batch it reviews (a review of the task list, the maintainer's request, 2026-11-17: id:z0066 had no check-in, and it changes the checker's diagnostics and the `EXPECT:` lines of provenance tests). id:z0065, the next task that builds on it, depends on this one.

    - **Checks:**
      - Re-read the queue and `git log -p` of id:z0066's commits.
      - Re-run id:z0066's C3 (one diagnostic per site and rule at the four sites) and C4 (two rules at one site print both).
      - No program is accepted that was refused: `REJECT_DIFF_NO_CACHE=1 make preflight-changed` shows 0 newly accepted, and the same count under `--provenance` over `tests/language/memory/provenance/` and the `gap_*` probes before and after (a de-duplication keyed too coarsely must not drop the only error of a function).
      - Every `EXPECT:` line changed is in the commit message's list (C5), and none changed from one rule's message to another rule's.

- [ ] +safety +measurement +AI-D @provenance B1.8c Measure: a store through a local raw pointer adds the stored value's origins to that local, so a heap block holding a frame address cannot leave the frame id:71a06
    > **Created:** 2026-11-14
    > **Branch:** `provenance`
    > **Depends:** id:z0073, id:0m61c
    > **Check-in:** stop for review after it if the rule is kept: it changes a safety rule.

    - **Placed:** before id:z0012, which it blocks: id:z0012 deletes the old region rule, the only rule that refuses case C of id:z0073 today.

    - **Why (the maintainer's decision in id:z0073, 2026-11-14):** case C (a frame address stored, inside `unsafe`, through the result of a `#[fresh]` function or a block from `zoril_allocator_alloc(null, ..)`, the pointer then returned or put into a global) is decided by measurement. The three programs are `tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`, `heap_block_store_through_old_rule_refused.zrl` and `heap_block_into_global_old_rule_refused.zrl`: refused by the old region rule only, accepted by the new rules since id:z0076 (the pointer has no origins, so a store through it reaches nothing they follow).
    - **Candidate rule (not tried; from the review, 2026-11-14):** a store through a raw pointer held by a local `p` (`*p = v`, `p[i] = v`, a field through it) does `O(p) |= O(v)`, as a write into a projection of a local does. `p` then holds `Frame` when `v` does, and the return rule and the store rule refuse `p` leaving the frame. Say first whether the transfer already does this for a raw pointer with origins, and why a pointer with none is skipped.
    - **Measure:** build a scratch compiler with the candidate (under `build/`, never replacing `build/zoril`), with the old rules off as id:z0074 builds it or under `--provenance` alone: 1. the three programs above: refused or not, and by which rule. 2. `--provenance=warn` over `src/main.zrl`, `tools/zbuild/src/main.zrl`, `tools/zilc` and the test programs (`build/z92/measure.sh`, 672 programs at id:z0092): the warning count before and after, and each new warning read (a real escape, or a safe program refused). 3. the store grid under `--provenance`: no unsafe cell newly accepted, the safe twins newly refused counted by axis. Probe the siblings: the pointer copied to a second local before the store; the pointer held in a struct field of a local; the store made by a callee given the pointer; a pointer from `@ptr_from_int` (`Raw`, exempt as a value by id:z0063: say whether it stays exempt as a carrier).
    - **Then decide, by the maintainer's rule:** if the candidate refuses the three and adds no refusal in the tree (or only real escapes), keep it: commit it with the three tests' `EXPECT:` lines naming the new rule, and say so here. If it refuses safe programs in the tree, do not keep it: case C is outside the guarantee, recorded in `doc/spec/safety_model.md` and `doc/spec/unsafe_policy.md` beside case A, and the three tests become tests of the accept (their expected result changes: stop and report, as `AGENTS.md` asks for a changed expectation).
    - **Checks:** C1 the three programs' results before and after, each quoted. C2 the warning counts before and after with their command, and every new warning listed with its reading. C3 the store grid's summary, quoted. C4 each sibling probe's program and result. C5 the decision recorded here with the figure that made it; if kept, the candidate taken out and the three tests watched to fail; `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, each `Total:` and the `fresh (no cache)` line quoted.

    - **Moved (2026-11-17, a review of the queue against `doc/design/provenance.md`, the maintainer's request):** from after id:z0074 to directly before id:z0065, and added to the **Depends:** of id:z0065 and id:z0074. If the candidate rule is kept, it refuses more under the new rules. So it has to land before id:z0065 makes those rules the default and re-records the store grid, and before id:z0074 lists what only the old rules refuse: its three known members (the `#[fresh]` and heap-block tests) are exactly this task's case C. Before, id:z0074 came first in the queue and would have read that list before the decision existed.

- [ ] +safety +design +AI-D @provenance A call result tied through a reference to an owner holds what the owner holds, not the storage it owns, unless its type can point there id:sjqmy
    > **Created:** 2026-11-17
    > **Branch:** `provenance`

    - **Found by:** id:z0084, reading the reproducers P1 to P5 that the check-in id:n177h placed on it (`build/provenance/build/z84/p1.zrl`-`p5.zrl`).
    - **Placed:** directly before id:z0065, which it blocks (P1 to P4 are safe user code the default flip would refuse), and added to its **Depends:**.
    - **Now (compiler git:dadd49e):** P1 (`return v.clone()` of a local `Vec<u8>`), P2 (`Vec<[u8]>` holding a parameter's view), P3 (`String`) are refused by the return rule, which reads only `O`: the clone's result is `_8 O={Frame(_1)}`, `_1` the local `Vec`'s buffer. `Clone for Vec` reads `self.raw` and the elements through `self`, so its summary ties the result to `ParamContents(0)`, and the caller maps that to everything `&v` reaches through (`os_through_plus`), which includes `S(v)`, the buffer. `v.as_slice()` has the same summary bit and must keep `S(v)` (`build/z84/u1.zrl`: `return v.as_slice()` of a local `Vec`). P4 (`out.resize(1, v)`) is refused inside `stdlib/vec.zrl`'s `resize` (`value.clone()` of a by-value parameter, whose storage is `Frame(value)`) and at the call.
    - **Measured (a scratch compiler, not a rule):** in `os_call`'s `in_ties` branch, reading the tie through one level and keeping only what the pointee holds (`os_through_split` into `O`, its `S` dropped) makes P1 to P4 accepted and leaves P5's `c.push(&buf)` refused; it also accepts `build/z84/u1.zrl`, so as it stands it is unsound. The field-insensitive summary cannot tell `self.raw` (what the owner holds) from `self.data` (the storage it owns).
    - **Decide:** how a summary or the caller tells the two apart. Candidates: (a) a summary bit per parameter for "the storage what the parameter reaches owns" beside `ParamContents` (a read of an owner's own raw pointer field through the parameter gives it; `.zri` and edges carry it); (b) at the caller, leave `S` of the pointee out of a tie when the result's type can hold no pointer to anything the pointee's owned storage holds in place (`Vec<u8>` cannot point at a `u8` buffer except through its own `data`, which points into its own storage; `Vec<&u8>` can); (c) accept P1 to P3 as a bound, with a rewrite. Probe each against `u1.zrl`, `vec_clone_frame_views_returned_refused.zrl` (refused today for this reason, not for its views: id:z0084's **Consequence** bullet), `fn wrap(v: &Vec<i32>) -> Vec<[i32]>` pushing `v.as_slice()`, and a `Vec<Arena>` whose arena lies in the buffer.
    - **P5** (`c = v.clone(); c.push(&buf); return c;` with `v: &Vec<[u8]>`): the push is refused by the call store rule because `c`'s storage is the caller's arena (`ParamContents(0)`), which the design treats as external (§3, _Calls through a `fn` value_: "a frame view pushed into such a `Vec` built from a parameter's `fn` value is refused"). The buffer is fresh, and only `c` reaches it, so the stored view is unreachable once `c` is gone; whether that is accepted is part of the decision (id:n177h expected only the return rule). The `return c` refusal stays.
    - **Checks:** C1 the decision and its reason in the design note §3. C2 P1 to P4 accepted (or the bound and its rewrite in `KNOWN_ISSUES.md` §5, written by id:z0065), `u1.zrl` and `vec_clone_frame_views_returned_refused.zrl` refused; with `v.push(&buf)` taken out of the latter, accepted. C3 the siblings above probed, each with a test. C4 the store grid under `--provenance`, `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed`.

- [ ] +safety +tests +AI-D @provenance id:z0065 B4a The new rules on by default, beside the old ones
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Depends:** id:z0064, id:z0075, id:z0088, id:z0092, id:z0180, id:z0093, id:z0094, id:z0097, id:z0087, id:z0086, id:z0084, id:z0089, id:z0090, id:7kbpd, id:z0066, id:h1yk5, id:w17jf, id:nc3ym, id:4by24, id:z0091, id:71a06, id:sjqmy
    > **Check-in:** stop for review after it.

    - **Split from:** id:z0012.
    - **Depends changed (2026-11-15, the check-in id:n177h):** id:z0084 added: it is the over-rejection of safe user code (a clone of a local `Vec` or `String` returned, `Vec<Vec<T>>.resize`) that this task requires to have its own task done first.
    - **Ordering note:** this task only refuses more, and depends in substance only on id:z0064 (the tree must be clean); the maintainer may move it ahead of id:z0011 and id:z0044 to close the escape holes for users sooner. (id:z0085 and id:z0091 are deferred to `future.tm.md`, and id:z0095 and id:z0096 are holes in both modes, not dependencies.)

    - **Do:** make the rules of `--provenance` run by default **in addition to** the old rules (nothing is deleted here; the old rules still run). Keep `--provenance=warn` as a developer option or retire it; decide and record. Resolve whatever the default build of `src/`, `stdlib/`, `tools/` and `tests/` now refuses, per id:z0064's classification (a real escape: fix the code; an over-rejection: it should already have its own task done).
    - **Code changes id:z0064 left here (2026-11-06):** `Driver::lower_fn_body` pushes `OsPending { zir: zir_func }` into `self.os_pending` (`src/driver/module.zrl`, 2 warnings): `zir_func`'s slices are tied to the local `zir_low` though they live in the driver's scratch arena; change the code or route it to id:z0084's rule. `Driver::set_ice_context` stores an arena-built note into a global through `set_ice_note`'s `#[stores(note -> static)]` (`src/driver/module.zrl:864`): a true store, safe only because the arena lives as long as the program, and no warning of its own once the other roots are gone; if the default build refuses it, an explicit `unsafe` with a `// SAFETY:` comment naming that invariant, not a rule.
    - **Probes:** every `known_gap` probe the new rules refuse flips to `compile_reject` (at id:z0059: all escape gaps except the liveness ones `gap_37`, `gap_38`, `gap_39`, `gap_43`, `gap_44`; since id:z0060 also `gap_56`, since id:z0061 `gap_57` and `gap_58`, since id:z0062 `gap_59` to `gap_62`, since id:z0072 `gap_63`; re-check each), with its Known gaps entry in `doc/spec/safety_model.md` and line in `doc/SAFETY.md` §6 removed. Accept probes newly refused: none allowed without a task.
    - **Store grid:** re-record `bench/fuzz/store_grid_expected_failures.txt` and `store_grid_twin_rejections.txt` (and the modular pair) under the new default; list in the completion note every twin newly refused, by axis.
    - **Accepted refusal (id:z0075, 2026-11-06):** the 18 safe twins refused because an assignment to a local's field keeps the field's old origins (`{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{same_param,store_param_65}__{deref_out,field_out}__frame_ends`) stay refused: add a `KNOWN_ISSUES.md` §5 entry with the reduced program from id:z0091 (`future.tm.md`), the fix that would remove it, and how to rewrite: give the field its final value when the local is built (`let carrier_tup = (src_val, 10);` in place of `(&seed, 10)` then `carrier_tup.0 = src_val;`: no warning, checked on id:z0064's compiler). Any other twin newly refused here needs a task, per the rule above.
    - **Verification:** `make test`, `make preflight-changed` (the differential must show 0 newly accepted; list the newly refused programs), `sh scripts/check_store_grid.sh`, the self-hosting fixpoint. The fuzz record goes stale for `src/`. Stop for review.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **Depends changed (2026-11-17, a review of the task list, the maintainer's request):** removed id:z0011 and id:z0044, which the **Ordering note** above already says are not blockers (this task flips no liveness probe and checks no declaration; its place after them in the queue is unchanged, and the maintainer may still move it). Added id:w17jf and id:nc3ym: the store grid's safe twins that the new rules refuse and the default accepts today (2250 at git:98a1efc, 780 of them id:w17jf's, figures in id:nc3ym) are over-rejections this task requires to have their tasks done first. Added id:h1yk5, the check-in of id:z0066.
    - **When the rules become the default (2026-11-14):** flip the `main` probes the provenance rules close and the old rules do not: `gap_79` and `gap_80` (id:z0183), `gap_77` and `gap_78` (id:z0180), each with its Known gaps entry and `doc/SAFETY.md` §6 sentence, and check the class (K) and (F) probes `gap_59` to `gap_63`, which a by-value-aggregate fix in the old rules closed in part (id:z0183's **Tried** bullet).

    - **Measured by id:nc3ym (2026-11-17, compiler git:3e34cc3):** this task would newly refuse 890 safe store-grid twins, in three roots: R1, a field assignment keeping the field's old origins (id:z0091's class), 186 twins; R2, one tuple parameter carrying both the destination and a read-only `Static` value, 224 twins (id:z0086, 96 of them also id:4by24); R3, a call through a `fn` value, 480 twins (id:4by24). The **Accepted refusal** bullet above names 18 of R1's 186 cells. The other 168 are the same cause through other destinations and paths (`closure_capture_mut`, `closure_owned_capture`, `closure_call_mut` and the `fn_val` path). id:z0091 is in `future.tm.md`. Whether to widen the accepted bound to all 186 or to promote id:z0091 before this task is the maintainer's decision; id:nc3ym recommends promoting it (see there).

    - **Accepted refusal superseded (2026-11-17, the maintainer):** R1's refusals, the 18 above included, are fixed by id:z0091 (promoted, added to **Depends:**) and not accepted as a bound, so no `KNOWN_ISSUES.md` §5 entry is written for them.

    - **Baseline of the probes (2026-11-17, `provenance` at git:94c0ed2, `build/zoril --provenance -I stdlib=stdlib` on each `known_gap` probe of `bench/safety_matrix/probes/`):** 42 of the 49 are refused and 7 are accepted. The 7 are liveness gaps, and each has its task ahead of this one: `gap_37`, `gap_43` and `gap_87` (id:kqp9n), `gap_38`, `gap_39` and `gap_96` (id:z0044), and `gap_44` (id:z0011). So this task flips every escape probe still `known_gap`, the 42 refused here, `gap_64`, `gap_94` and `gap_95` among them (the old rules still accept those three). Re-run the loop on the tree as it is when this task starts, and quote both counts.
    - **Since id:4by24 and id:z0091 (2026-11-17, compiler git:5d0c6ea):** under `--provenance` the store grid refuses exactly the default record's 3932 twins (`sort -u` of `build/provenance/build/z91/grid/work/twin_rejections.txt` against `bench/fuzz/store_grid_twin_rejections.txt`: 0 either way) and accepts no unsafe cell, so id:nc3ym's 890 newly refused twins are gone. One more probe flips here: `gap_97` (git:ff009df), a frame view read through a local reference to a local struct and stored out, accepted by the default rules and refused under `--provenance`, so 43 of the 50 `known_gap` probes are refused.
    - **One more since id:z0073 (2026-11-18):** `gap_98` (git:43b8f17), a frame view in an aggregate passed by value to a callee that stores it out (`keep(out, Carrier { v: &x })` with `*out = c.v`; also a tuple, an array, a nested struct, a by-value `self`, the whole struct, and a raw pointer to the frame in place of the reference), accepted by the default rules and refused under `--provenance` (the call store rule), so 44 of the 51 `known_gap` probes are refused. Flip it here, with its Known gaps entry and class (O) in `doc/SAFETY.md` §6.

- [ ] +safety +tests +AI-D @provenance id:z0074 B4b List every program the old rules refuse and the new rules accept, and read each
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Depends:** id:z0065, id:71a06

    - **Found by:** the review of id:z0071.

    - **Why:** `leak_vec` (id:z0071) was refused by neither differential the series runs: the rejection differential compares two compilers in the default mode, and `build/rv/provdiff.sh` compares `--provenance` before and after a change over the existing probes. A reviewer found it by hand. id:z0012 deletes the old rules, so every program only they refuse is accepted after it; that list is not computed anywhere.
    - **Do:** run the new rules alone (a scratch compiler with the old rules' refusals off, as `check_reject_diff.sh` builds its base in a scratch worktree, or a developer flag if one is cheaper; say which) and the default compiler over the rejection differential's program set (69,122 at id:z0071, `tests/`, the safety probes, the store grid twins). List every program refused by the default and accepted by the new rules alone, and read each: a real escape gets a fix or a `known_gap` probe before id:z0012; a safe program is recorded as id:z0012's intended acceptance.
    - **Make it a gate** if it is cheap enough: id:z0012's completion note then lists the same set, empty of unsafe programs.
    - **Known members (from id:z0076, 2026-11-06):** `tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`, `heap_block_store_through_old_rule_refused.zrl` and `heap_block_into_global_old_rule_refused.zrl` are refused by the old region rule only: a frame address stored through a `#[fresh]` result or a heap block, the pointer then returned or put into a global. Their expected diagnostic names the old rule, so they fail when it goes; id:z0073 decides what replaces it.
    - **Correction (2026-11-17, a review of the task list):** id:z0073's decision (2026-11-14) passed these three programs (its case C) to the measurement id:71a06, which comes after this task in the queue. Until it is done they are members of this task's list, recorded as "decided by id:71a06", not read again here.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +safety +tests +AI-D @provenance A `fn` item or closure that stores its own parameter into a global, made into a value, is refused by the new rules id:4f0ew
    > **Created:** 2026-11-17
    > **Branch:** `provenance`

    - **Found by:** id:4by24, probing the sibling routes of a call through a `fn` value (compiler git:94c0ed2, and the same with id:4by24's change).
    - **Placed:** directly before id:z0012, which it blocks: once the old rules are deleted, both programs below compile and leave a dangling pointer in `G`.
    - **Now:** under `--provenance` the new rules accept both of these; only the old rules refuse them ("region escape: the function stores a reference into memory that outlives a call through a `fn` value"). A call through a `fn` value checks each argument against what the other arguments and the environment reach, never against a global (design note §3, _Calls through a `fn` value_), and the closure rule (id:z0096) applies only the edges whose value is what the environment reaches. An edge whose value is a declared parameter is checked nowhere.
      - `static mut G: *i32 = 0 as *i32; fn stash(r: &i32) { unsafe { G = r as *i32; } } fn apply(f: fn(&i32), r: &i32) { f(r); } fn bad() -> i32 { let x = 1; apply(stash, &x); return 0; } fn main() -> i32 { let _ = bad(); return unsafe { *G }; }` (a `fn` item; id:z0012's **From id:z0092** bullet names this half).
      - The same with `apply(|q: &i32| { unsafe { G = q as *i32; } }, &x);` in `bad` (a closure). The design note §3 _A closure made into a value_ said this one "is refused at `run`'s call"; no test showed it, and it is not (id:4by24 corrected the sentence).
      - A `fn` item bound to a local and called through it is refused, by its summary (`let f: fn(&i32) = stash; let g = f; g(&x);`: "the callee stores an address of this frame into a global (call store rule)").
    - **Do:** decide where a parameter-to-global (or parameter-to-another-parameter) edge of a body made into a value is checked: where the value is made (refuse the edge outright, as `check_fn_value` does), or at every call through a `fn` value (a global destination for every argument, which refuses every frame address handed to a `fn` parameter). Then implement it, with the two programs above as tests, and probe the siblings: an `unsafe fn` value, a method value (`S::get`), a generic instance, a closure in a struct field, a `fn` value returned by a call.
    - **Also:** the header comment of `os_check_closure_value` (`src/check_zir.zrl`) says the same wrong thing as the design note did ("An edge whose value is a declared parameter is checked where the argument is passed"); correct it with the fix.
    - **Checks:** C1 both programs refused under `--provenance` by a `provenance:` diagnostic, with a test each. C2 each sibling probed, refused where unsafe, with a test. C3 the rejection differential (it removes no refusal unless the decision does), `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed`.

- [ ] +safety +tests +AI-D @provenance id:z0012 B4 Make `--provenance` the default, delete the old classifiers, and fix what the measurement found
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0011, id:z0044, id:z0065, id:z0063, id:z0073, id:z0074, id:z0075, id:z0096, id:71a06, id:4f0ew
    > **Check-in:** stop for review after it. **Split here** if the tree needs more than a session of changes.

    - **Depends changed (2026-11-14, the maintainer, by id:z0073's decision):** added id:71a06, which decides case C before the old region rule is deleted.
    - **Split (2026-11-05, from id:z0049's review):** turning the rules on by default beside the old ones is id:z0065 (it only refuses more); this task is now the half that accepts more: delete the old rules and `src/summary_pass.zrl`, with the rejection differential, and the docs and twin lists. The fixes of the measurement are id:z0060 to id:z0063, and the `unsafe fn` exemption item moved to id:z0063, which narrowed it to `Raw`.

    - **Do:** make the new rules the default and remove `--provenance`; resolve every warn-mode rejection recorded in id:z0049 and id:z0011 (a real escape: fix the code; a common over-rejection: apply the decided fix; a leak through a by-value collection parameter: change the code); then delete `local_storage_external`, `local_is_external_target`, `rvalue_is_external_target`, `place_outlives_frame`, `rvalue_storage_external`, `storage_walk_zir`'s mask logic, `note_call_stores_zir`, the depth limits, `is_collection_type_name`, the same-parameter filters, and `src/summary_pass.zrl` (keeping `src/verify.zrl`'s stack-address check as an add-only second net).
    - **Flip probes and twin lists (including id:z0045's):** flip all closed `known_gap` probes (`gap_07`, `gap_11`, `gap_13`, `gap_16`, `gap_18`, `gap_21`, `gap_23`, `gap_26`, `gap_27`, `gap_28`, `gap_29`, `gap_32`, `gap_33`, `gap_36`, `gap_40`, `gap_41`, `gap_42`, `gap_44`, `gap_45`, `gap_47`, `gap_48`, `gap_49`, `gap_50`, `gap_51`, `gap_52`, `gap_53`, `gap_54`, `gap_55`) to `compile_reject` and remove their Known gaps entries in `doc/spec/safety_model.md` and `doc/SAFETY.md` §6. Fold in id:z0045: remove the 3402 `ref_{let,identity,phi}` twins (and any id:z0017 twins newly accepted when `summary_pass.zrl` is retired) from `bench/fuzz/store_grid_twin_rejections.txt`, flip `read_through_{ref,identity,phi}.zrl` from `expected compile fail` to running tests, add an `accept` probe for `id:z0045` and a regression test returning `s.as_slice()` from `String.with_capacity(a, cap)` (`a: &Arena`). Because retiring `summary_pass.zrl` and `local_storage_external` accepts more safe programs, run `scripts/check_reject_diff.sh <base>` and list every newly accepted program class in the completion note (none may be unsafe). Update `doc/SAFETY.md` §2.3 and §5–§6, `doc/spec/surface_syntax.md` (`#[borrows]`/`#[stores]`), `README.md`, `KNOWN_ISSUES.md` and `bench/fuzz/store_grid_expected_failures.txt`.
    - **End criterion of the series (the maintainer, 2026-11-06, at id:z0075):** zero unsafe programs accepted is the hard requirement (the grid, the safety probes, the rejection differential). Zero safe programs refused is not reachable by any checker that accepts no unsafe one; the target is that no remaining refusal is common in user code (the tests as its stand-in), each is a documented class in `KNOWN_ISSUES.md` §5 with a reason and a rewrite (id:z0017 audits them), and its diagnostic says what was found (id:z0066).
    - **Done when:** every unsafe store-grid cell (whole-program and modular) is rejected, no `known_gap` probe of this family remains, the self-hosting fixpoint holds, and `make test` and `make preflight` pass. Stop for review, then close id:z0045 (citing this commit on `main`) and start id:z0017 and id:z0013 (and renew the fuzz record per id:z0003).
    - **From id:z0092 (2026-11-06):** the old rules refuse making a `fn` item that stores into a global or another parameter into a value (`check_fn_value` in `src/verify.zrl`); the new rules have no counterpart, since a call through a `fn` value records no store into a global (design note §3, _Calls through a `fn` value_). Carry it over before deleting the old rules: id:z0096 is the closure half of the same route. **Depends also:** id:z0096.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

    - **Flip list (2026-11-17, a review of the queue):** the probe list under **Flip probes and twin lists** dates from before the split. id:z0065 now flips every escape probe that the new rules refuse (its **Baseline of the probes**), and the liveness tasks ahead of it flip their own. So this task flips only what is still `known_gap` once the old rules are deleted. A probe the old rules alone refused, and that is accepted afterwards, is a hole: id:z0074 lists those, and this task needs that list empty of unsafe programs.

- [ ] +audit +safety +AI-G @provenance id:z0045 A reference to a local carrier passed through a `let`, an identity call or a phi is refused
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0012

    - **Depends note:** (do not edit `src/summary_pass.zrl` before id:z0012 retires it; close with id:z0012). Over-rejection, not a hole; related to id:z0017.

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

    - **Depends note:** (do not debug `src/summary_pass.zrl` before id:z0012 deletes it). Over-rejection audit, not a hole.

    - **Cells (before id:z0012):** `{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{closure,param_65}__call_struct_mut__frame_ends` (12 cells) plus 96 cells exposed by id:z0008 in `bench/fuzz/store_grid_twin_rejections.txt`, rejected today by `src/summary_pass.zrl` ("region escape: storing local stack pointer into caller memory"). Also note the sibling found in id:z0047's review: passing a local struct `RefHolder { r: &c }` by value to `take_holder(h)` retains `Frame(c)` (`os_reach_all`).
    - **Over-rejection from id:z0007 (found in its review, 2026-11-03):** liveness borrows are tracked per local, not per field, so `w.s = v.as_slice(); let x = w.s[0]; a.reset(); return x - 42 + w.t - 3;` is refused at `a.reset()` because `w` stays live for `w.t`.
    - **Do (after id:z0012):** inspect every twin still listed in `bench/fuzz/store_grid_twin_rejections.txt` once `summary_pass.zrl` is gone (`param_65` twins should be accepted via the overflow bit; `closure`/`fn`-value twins: Decision 3 is decided (id:z0088), so any still refused after id:z0092 to id:z0094 is a finding, not a bound by design). Fix any unintended over-rejection without reopening any probe, add an `accept` probe for any fixed class, and document any deliberate precision bound (such as field-insensitive borrows) in `KNOWN_ISSUES.md` §5. `make test`, `make preflight-changed`, the rejection differential.
    - **Done when (2026-11-06, the series' end criterion, recorded on id:z0012):** every safe twin still in `bench/fuzz/store_grid_twin_rejections.txt` (and the modular list) is in a class `KNOWN_ISSUES.md` §5 names, with its reason and a rewrite, and none is common in the tests. `closure`/`fn`-value twins follow id:z0088's decision, not the note above.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +safety +docs +AI-D @provenance Close the provenance series: the design note as built, the fuzz record renewed, and the series end criterion checked id:a85sp
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Depends:** id:z0012, id:z0045, id:z0017

    - **Placed:** directly after id:z0017, the last open task of the series. It was found in a review of the queue against `doc/design/provenance.md` (the maintainer's request, 2026-11-17): no open task brought the design note up to date with what was built, or started the fuzz renewal that id:z0003 decided would follow id:z0012.
    - **Why:** the design note says it is "the design that the hardening series implements". Its §4 still marks most rows open (`gap_11`, `gap_40` to `gap_42`, `gap_47`, `gap_48` and others), and its §5 lists what the model "will newly reject (to measure, not assumed)". §6 describes the flag that id:z0012 removes, and lists only the tasks up to id:z0012, not the precision, liveness and closure tasks that were added later. id:z0012 updates `doc/SAFETY.md`, `doc/spec/surface_syntax.md`, `README.md` and `KNOWN_ISSUES.md`, but not this note. The fuzz record has been stale for `src/` since early in the series. id:z0003 (confirmed by the maintainer on 2026-11-03) renews it once, after id:z0012, and id:z0013's generator debt is to be run in the same session.
    - **Do:**
      1. Bring `doc/design/provenance.md` up to date with the rules as built. In §4, give each row the probe that closed it and say whether it is closed. In §5, replace each "to measure" item with the figure that was measured, the task that measured it, and what was decided. In §6, describe the landing as it happened (the flag gone, the old classifiers deleted, the ZIL check kept add-only) and list every task of the series. §1 and §2 stay as history, marked "before the series".
      2. Check the series' end criterion (id:z0012, 2026-11-06). The grid accepts 0 unsafe cells, whole-program and modular; no `known_gap` probe of the escape or liveness families remains; and every safe twin still refused is in a class that `KNOWN_ISSUES.md` §5 names. Where one of these fails, add a task (placed by the AGENTS.md rule) rather than fixing it here.
      3. List each route class added in the series and whether `scripts/fuzz/gen.lua` covers it (id:z0013's **Generator debt**). Add a task for each missing generator feature, placed before the renewal.
      4. The fuzz renewal is the maintainer's: a session takes the machine for hours (id:z0003). Ask the maintainer to start it, and record the request here.
    - **Checks:** C1 every §4 row names its closing probe or its open task, and `rg -n '\(open\)' doc/design/provenance.md` prints only rows with an open task. C2 `sh scripts/check_store_grid.sh` summary quoted, with 0 unsafe accepted. C3 `rg -l 'expected: known_gap' bench/safety_matrix/probes` lists no escape or liveness probe, quoted. C4 the route-class list with its generator coverage, and the tasks it added. C5 `make test-changed`, its `Total:` line quoted. C6 `tm validate --strict doc/tasks/*.tm.md` prints no warning.

- [ ] +zil +decision +AI-D @zil ZL1 Settle the slice form of string_const and the slice_ptr opcode, and check what the pinned stage1 feeds zilc id:m6vm3
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)

    - **Placed:** after the provenance series (`id:z0017`), before ZL2 to ZL6. Nothing in `testinfra` depends on it. ZL4 changes the per-file runner, which `testinfra` rewrites (id:z0139).

    - **Depends changed (2026-11-17, a review of the task list, the maintainer's request):** removed id:z0017. It stated the order (this series after the provenance series), which the task's position states already; nothing in ZL1 to ZL6 needs a provenance task's result, and the series is on a branch of its own off `main`. `tm next` still offers the provenance tasks first; `tm next @zil` now offers this task, so a second session can take the series while the provenance series runs, if the maintainer wants that. To hold it back instead, restore the line.
    - **Why:** `string_const` is to give a `Slice<u8, 'local>` everywhere, as the spec says (id:1kaye, decision 1). Hand-written ZIL then needs `slice_ptr` to get the data pointer back.
    - **Decide, and write into ZL2 to ZL5 as their **Do:** and numbered **Checks:**:** (a) What a slice-typed `string_const` lowers to in zilc's QBE output: a static `{ptr, len}` pair beside the bytes, whose address is the value, or another layout. It must match how the front end's slice slots are laid out (pointer at offset 0, `usize` length at 8, today's `v5` slot in `--emit-zil`). (b) How the front end uses it: copy the pair into the slot, or use the value directly. (c) `slice_ptr`'s syntax, typing and spec entry beside `slice_len` (`doc/spec/intermediate_language.md` §5), and whether the front end's cast-and-load idiom is replaced by it. (d) What the pinned stage1 feeds to which zilc: does any path pass ZIL written by `bootstrap/stage1/` to the new `build/zilc`, `zilc-boot` included? If one does, the new zilc must also accept the old form until a re-pin, which is the maintainer's. (e) Which recorded figures change (`corpus/zrl_whole_program_zil.sha256`, the safety figures) and how each is recomputed.
    - **Also place:** the statement, decided in id:ahd1c, that ZIL is not checked for memory safety (`doc/spec/intermediate_language.md` and `doc/spec/safety_model.md`: the claims cover programs compiled from Zoril source, and zilc catches the common mistakes listed by ZL6). Put it into one of ZL2 to ZL5, or into a task of its own.
    - **Checks:** C1: each of (a) to (e) answered here, with the command that showed it for (d). C2: ZL2 to ZL5 each have a **Do:** and numbered **Checks:**, with a take-out check.

- [ ] +zil +AI-G @zil ZL2 string_const gives a Slice in the front end and in zilc, read back with slice_ptr id:qpc8d
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:m6vm3

    - **Placed:** after ZL1, which settles it.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope: the front end emits the slice form, zilc lowers it, the type check and `src/verify.zrl` type it, `slice_ptr` is added, the spec matches, and `corpus/zil/15_io_syscall.zil` and `19_fd_io.zil` are rewritten to print exactly their strings.

- [ ] +zil +AI-G @zil ZL3 One spelling for cast: zilc refuses bitcast and the corpus is rewritten id:htrqb
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:qpc8d

    - **Placed:** after ZL2: the corpus files it rewrites are the ones ZL2 changes.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope: `tools/zilc/src/zil_parse.zrl` refuses `bitcast` with a diagnostic that names `cast`, and the six corpus files that use it (`02_comparison`, `12_enums_sum`, `13_slices`, `15_io_syscall`, `19_fd_io`, `24_tuples`) use `cast`. The spec's line 92 stays true.

- [ ] +zil +tests +AI-G @zil ZL4 Corpus and per-file tests check the program's output, not only its exit code id:ehh6m
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:htrqb

    - **Placed:** after ZL3.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope (decision 3): a per-file test can state its expected output (a header directive or a sibling file, chosen in ZL1, read by the one header reader, `tr_expectations`, or by its replacement in `ztest`). Every `corpus/zil/` program and every corpus program that prints states its output. A check plants the 4 KB over-read of id:1kaye and shows that the test fails.

- [ ] +zil +safety +AI-G @zil ZL5 zilc runs the ZIL verifier that the compiler runs id:egsdq
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:ehh6m

    - **Placed:** after ZL4, last in the series. A check-in follows it, added by ZL1 with the series' other check-ins.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope (decision 4, the small step): zilc runs `src/verify.zrl` on what it parses, as the compiler does after lowering, so hand-written ZIL gets the same ZIL-level checks (stack-address escape, constant arena allocations) that compiled programs get. Not a borrow checker; that question is id:ahd1c.

- [ ] +zil +safety +audit +AI-D @zil ZL6 Which common mistakes in hand-written ZIL zilc can catch from what ZIL says id:0mbg3
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decision in id:ahd1c (`future.tm.md`)
    > **Branch:** `zil`
    > **Depends:** id:egsdq

    - **Placed:** after ZL5, which gives zilc the ZIL verifier this task extends.

    - **Why:** ZIL is not checked for memory safety, but zilc should catch the mistakes that are easy to see in ZIL as designed and that happen most often (the maintainer, id:ahd1c).
    - **Do:** list candidate checks, each with a three-line ZIL program that shows the mistake, and say for each whether ZIL as written carries what the check needs. Candidates to start from: a value used after a `move` or `drop` in the same function, a `drop` twice, a `slice_load`/`slice_store` with no dominating `bounds_check` (spec §6.3), the address of an `alloc 'local` returned or stored into a global, a `slice_len` or `slice_ptr` on a value that is not a slice, a `syscall` with an argument count its stub does not take, and a block with no terminator. Corpus mistakes count as evidence of what is common: id:1kaye's string over-read is one. Rank them by how often they would fire and how simple they are, and split each chosen check into an `+AI-G` task with its own numbered **Checks:** and a take-out.
    - **Checks:** C1: every candidate has its program and its answer here, with the zilc output today (`timeout -k 5s 30s build/zilc <file>`). C2: the chosen checks are tasks, placed after this one, with a check-in after them.
