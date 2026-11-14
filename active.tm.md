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
    > **Before:** id:z0140.
    > **Check-in:** it touches `rt/`.

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
    > **Placed:** directly after id:z0138, the task it reviews

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
    > **Placed:** directly after check-in id:bfhmm, the review of milestone Z2c

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
    > **Placed:** directly after id:z0139, the task it reviews

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
    > **Depends note:** a release cycle of `ztest` as the default with no disagreement.

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
    > **Placed:** directly after id:z0140, the task it reviews

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
    > **Placed:** directly after check-in id:jhcdc, the review of milestone Z2e

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
    > **Asked by:** the maintainer.

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
    > **After:** id:z0117 (written in the runner that stays).

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
