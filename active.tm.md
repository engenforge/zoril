# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

## Now

## Next

- [ ] +bootstrap +audit +AI-D @main id:z0135 Z0 stage1 accepts modules in the `src/` closure and builds some of their paths wrong
    > **Created:** 2026-11-07
    > **Context:** by id:z0117's measurement.
    > **Branch:** `main`
    > **Before:** id:z0131, id:z0133 (they edit closure modules).

    - **Review (2026-11-11/12):** the header's **Before:** id:z0131 no longer holds: by the maintainer's decision on id:z0131 its syscalls go into `stdlib/proc.zrl`, which is outside the `src/` closure, so that task and id:z0132 start without this one. Whether id:z0133 needs it is asked on id:z0133. This task keeps its own reason: an edit to `src/` that reaches one of the paths stage1 builds wrong.

    - **Found (id:z0117, git:e932d51):** built by `build/zoril-stage1` and `build/zilc-stage1` (the `build/zilc-boot` pipeline, linked with `build/runtime.o` or `build/runtime-stage1.o`), `tests/stdlib/test_stdlib_fd.zrl` and `tests/stdlib/test_stdlib_io_result.zrl` segfault in `mem_raw.zrl`'s `zoril_allocator_alloc` (from `test_pipe_large_buffer`) and `arena_free` (from `Arena::drop` in `test_command_redirect_stdout`); built by `build/zoril` they exit 0. Separately, stage1 refuses a program in which two modules each define a private function of the same name (reproduction in id:z0117: `cannot access private function: helper`), which `build/zoril` accepts.
    - **Why it matters:** the stage1 constraint in `AGENTS.md` says the closure "may use only what the pinned stage1 accepts". Accepting is not enough if stage1 builds an accepted function wrong. The self-hosting fixpoint covers only what `src/` reaches; an edit to `src/` that starts reaching one of these paths would get a generation-1 compiler built wrong, found (if at all) only by the fixpoint differing.
    - **Do:** reduce each crash to a minimal program against stage1 (`AGENTS.md`: before blaming a seed compiler, reproduce against it), and name what stage1 does differently (a language rule that changed since the pin, such as a drop or layout rule, or a stage1 bug). Find whether any function `src/` reaches today takes the same route (`--emit-deps`, and the generation-1 compiler run over the stdlib tests). Then propose, for the maintainer: a rule added to the stage1 constraint and `doc/bootstrap/two_stage.md` (for example "no two modules in the closure share a private name", and the construct stage1 builds wrong), and whether a check can enforce it (build the closure modules' own tests through stage1 in a gate). Fixing stage1 itself is a re-pin or a recorded backport, the maintainer's decision: stop and ask.
    - **Checks:** the minimal reproductions recorded here, each run against stage1 and `build/zoril`.
    - **Filed (2026-11-07):** both issues are in `KNOWN_ISSUES.md` §1 (the two `stage1` entries), the crash with its cause marked unknown. When this task names the cause, replace that sentence with it, and add the rule it proposes to the entry's **Workaround**.

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
