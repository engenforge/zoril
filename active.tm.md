# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

- [x] +bench +testinfra +AI-G @main A record commit that loses a race is retried, the figures row carries the bare version, and the rule names all four record files id:h1dj3
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Placed:** after id:tmydc, which runs one measurement at a time and does not need it; found by the check-in id:ev54n.
    > **Check-in:** reviewed in id:269a6.
    > **Completed:** 2026-11-15 git:35bc5f7

    - **Found by the check-in id:ev54n:**
      1. Four gate runs started together against one records work tree (a scratch one): all four rows were appended intact and one commit carried them all, but three runs ended with exit 1 and `[FAIL] bench records: the row was appended to ... but not committed: fatal: Unable to create '.../index.lock'` (or `cannot lock ref 'HEAD'`). Two sessions that run a preflight at the same time on one host would each see the bench step fail although nothing was lost.
      2. `bench/records/figures_history.tsv`'s `zoril_version` column holds `zoril 0.1.0-alpha-176-g50b1e8f`; the other record files hold the second word only (`0.1.0-alpha-176-g50b1e8f`).
      3. `AGENTS.md`'s bullet **Benchmark records are kept, on every host** and `doc/developer_guide.md` name three record files; `figures_history.tsv` is the fourth.
    - **Settled:**
      1. In `records_commit` (`scripts/lib/records.sh`): when `git add` or `git commit` fails, wait one second and try again, up to five times in all. Before each try, and after the last, the row counts as committed when `git -C <dir> status --porcelain -- <file>` prints nothing (another run's commit carried it): return 0 then. Only when the file is still modified after the fifth try is it the `[FAIL] ... appended ... but not committed` line, with git's last message.
      2. `scripts/record_figures.sh` writes the second word of `build/zoril --version`. The two rows already recorded stay as they are: a record is not rewritten.
      3. Both documents name `bench/records/figures_history.tsv` beside the other three.
    - **Tests** (cases beside R1 to R5): R6, four `--force --check-thresholds-only` runs started together (`&`, then `wait`) against one scratch records work tree: every run exits 0, the file has four rows of 17 fields, and `git status --porcelain` there prints nothing. R7, a lock that stays (R4's planted `index.lock`): still exit 1 with `appended ... but not committed`, after the tries. F4, the figures row's third field has no space.
    - **Checks:**
      - C1: before: R6 run by hand as the finding describes; quote the exit statuses (expected: one 0 and three 1).
      - C2: after: the test script; quote the `[PASS]` lines of R6, R7 and F4 and its last line. Take the retry out (one try) and quote R6 failing; take the "already committed" test out and quote what fails; restore.
      - C3: `rg -n 'figures_history' AGENTS.md doc/developer_guide.md`; quote the line numbers.
      - C4: `make test`; quote its `Total:` line. No `src/`, `stdlib/` or `tools/` file changes, so no preflight (`git diff --stat HEAD` shows it).
      - C5: commit on `main`, add `**Awaiting review:**` with C2 to C4, `tm done`, and stop at the check-in id:269a6.
    - **Awaiting review:** `sh scripts/test_bench_threshold_gate.sh`, `rg -n 'figures_history' AGENTS.md doc/developer_guide.md`, `make test`.
    - **Completion note:**
      - C1: before: four concurrent `--force --check-thresholds-only` runs against one scratch `records` worktree exited `1 0 1 1` (one succeeded; three failed with `cannot lock ref 'HEAD'` or `Unable to create '.../index.lock': File exists`).
      - C2: after: `sh scripts/test_bench_threshold_gate.sh` printed `[PASS] R6: four concurrent record commits all exit 0 with 4 rows and clean status`, `[PASS] R7: persistent lock fails with appended but not committed`, `[PASS] F4: figures row third field is bare version (0.1.0-alpha-176-g50b1e8f)`, and last line `All bench threshold gate tests passed.`. With retry removed (`-lt 1`), R6 failed: `[FAIL] R6: concurrent record commits failed (fail=1 rows=4 status='')`. With the "already committed" `status --porcelain` check removed, R6 failed: `[FAIL] R6: concurrent record commits failed (fail=1 rows=4 status='')`. Restored both.
      - C3: `rg -n 'figures_history' AGENTS.md doc/developer_guide.md` printed `AGENTS.md:38` and `doc/developer_guide.md:202`.
      - C4: `git diff --stat HEAD` changed only `AGENTS.md`, `doc/developer_guide.md`, `scripts/lib/records.sh`, `scripts/record_figures.sh`, `scripts/test_bench_threshold_gate.sh` (no `src/`, `stdlib/` or `tools/`). `make test`: `Total: 3453 run, 3453 passed, 0 failed, 94 skipped (123.4s)`.
      - C5: committed on `main` as git:35bc5f7.

- [x] +bench +testinfra +AI-G @main The runtime measure is six programs against `gcc -O2`, recorded per run and gated on their geometric mean id:9d99n
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Placed:** after id:h1dj3, in the batch the check-in id:269a6 reviews; the maintainer's request of 2026-11-15.
    > **Depends:** id:h1dj3
    > **Depends note:** it commits records through `records_commit`, which id:h1dj3 changes.
    > **Check-in:** reviewed in id:269a6.
    > **Completed:** 2026-11-15 git:03937b7

    - **Now:** the benchmark gate's one measure of generated code is `runtime_ratio_vs_gcc_o2`: `fib(38)` against gcc, a single recursive-call program. `scripts/perf_gap.sh` already times six programs (`bench/perf_gap/`: `array_loop`, `fib`, `particles`, `qsort`, `sha`, `vm`) as Zoril, cproc and `gcc -O2` builds and refuses a run whose three builds exit differently, but nothing records what it prints. Measured on this host at git:50b1e8f (median of 5, ms, Zoril / cproc / gcc): `array_loop` 815 / 840 / 142, `fib` 697 / 753 / 192, `particles` 628 / 626 / 224, `qsort` 440 / 420 / 357, `sha` 259 / 233 / 140, `vm` 432 / 329 / 331; the run took 40 s. Zoril to gcc: 5.74, 3.63, 2.80, 1.23, 1.85, 1.31, geometric mean 2.36.
    - **Decided (the maintainer, 2026-11-15):** the runtime measure takes in these six programs. The instruction-count gate (`perf-gate`) stays in `make test`: it is exact, takes two seconds, and names the commit that made generated code worse.
    - **Settled design (a reviewing session, 2026-11-15):**
      - **The record.** `bench/records/runtime_history.tsv`, one row per program per run, with a header: `date`, `commit`, `zoril_version`, `host_id`, `governor`, `status`, `kind` (`run`, `baseline` or `backfill`), `workload`, `zoril_ms`, `cproc_ms`, `gcc_ms`, `ratio_vs_gcc` (three decimals), `instructions` (the gate-size count of `--gate-check`'s method). `cproc_ms` is empty where cproc is not installed and `instructions` where valgrind is not; neither stops the run. Without gcc the step prints `[SKIP] runtime record: gcc is not installed` and records nothing.
      - **Who writes it.** `scripts/perf_gap.sh --record-run` measures (its timing mode and its instruction count) and appends the rows through `scripts/lib/records.sh`, committing them as `<host_id> <commit>: runtime`; `RUNTIME_HISTORY` in the environment names another file, and `--kind KIND` sets the kind (default `run`). It prints the geometric mean of the six `ratio_vs_gcc` as `runtime_geomean_vs_gcc_o2<TAB><value>` on its last line. `scripts/bench_cross_lang.sh` calls it in a `--check-thresholds` or `--record` run (not in `--check-thresholds-only`), after its own measurements, and writes the value into the metrics file.
      - **The gate.** `bench/records/gate_history.tsv` gets an 18th column, `runtime_geomean_vs_gcc_o2`; its header line is rewritten once to carry it (a header, not a row; the rows already recorded keep their 17 fields). `bench/cross_lang/tolerances.cfg` gets `runtime_geomean_vs_gcc_o2|15|lower_better` and loses `runtime_ratio_vs_gcc_o2`: the `fib` ratio is still measured and recorded in its column, no longer gated (its retry stays for the new measure only if it applies as it is; if it does not, the retry goes with the old gate, say so). A baseline row with no 18th field does not gate the new measure: the gate prints `[NEW]  runtime_geomean_vs_gcc_o2 <value>: this host's baseline has no value for it; re-record the baseline (sh scripts/bench_cross_lang.sh --record)` and passes that axis. The lookup that skips rows with fewer than 17 fields stays at 17.
      - **Contention.** The rows carry the run's `status`; a `baseline` is refused on a contended host as today.
      - **The header of `scripts/perf_gap.sh`** says the gate is "part of `make preflight`"; it is a gate of `make test` (`scripts/test_plan.tsv`). Say that, and why it is there (exact, seconds, names the commit).
      - **The rules.** `AGENTS.md` and `doc/developer_guide.md` name `runtime_history.tsv` with the other record files; the README of the `records` branch gets its line (a commit on `records`).
    - **Tests** (in the script that holds R1 to R7; `perf_gap.sh` is given stub programs through `PERF_GAP_OUT` or a scratch tree, never the real `bench/records`): T1 a run appends six rows of 13 fields and one commit; T2 the printed geometric mean equals the one computed from the rows (two programs of ratio 2.000 and 8.000 give 4.000); T3 without valgrind on `PATH` the `instructions` field is empty and the run passes; T4 without cproc the same for `cproc_ms`; T5 the gate: a baseline with 2.000 and a run with 2.400 fails, with 2.200 passes; T6 a 17-field baseline prints `[NEW]` and passes; T7 three builds that exit differently: no row is written and the run fails.
    - **Checks:**
      - C1: before: `sh scripts/perf_gap.sh` prints its table and `ls bench/records/runtime_history.tsv` fails; quote both.
      - C2: the test script; quote the `[PASS]` lines of T1 to T7 and its last line. Take out alone: the exit-code comparison in record mode (T7), the tolerance line (T5), the `[NEW]` branch (T6); quote what fails; restore.
      - C3: a real run, `sh scripts/bench_threshold_check.sh > build/runtime-run.log 2>&1`: quote the `[NEW]` line, the six rows it appended, the three commits on `records` (speed, runtime, gate), and `git status --short` of the code tree (nothing). Do not re-record the baseline: that is the next task's.
      - C4: `make test`, then `make preflight-changed`; quote each `Total:` line and the time of the bench step from `build/preflight-timings.tsv` before and after (expected: about 40 s more).
      - C5: commit on `main`, add `**Awaiting review:**` with C2 to C4, `tm done`, and stop at the check-in id:269a6.
    - **Awaiting review:** `sh scripts/test_bench_threshold_gate.sh`, `sh scripts/bench_threshold_check.sh`, `make test`, `make preflight-changed`.
    - **Completion note:**
      - Note on retry: the `fib` confirmation retry in `scripts/bench_cross_lang.sh` uses `TMP_DIR/fib_zoril` and `TMP_DIR/fib_gcc2` and does not apply as it is to the six-program geometric mean, so it stays with `runtime_ratio_vs_gcc_o2` (no longer in `bench/cross_lang/tolerances.cfg`). Also fixed `median_ms` in `scripts/perf_gap.sh` to set `MED_MS` and `RC` without a subshell so `zrc`/`crc`/`grc` are preserved for the exit-code check.
      - C1: before: `ls bench/records/runtime_history.tsv` failed (`ls: cannot access 'bench/records/runtime_history.tsv': No such file or directory`), and `sh scripts/perf_gap.sh` printed `array_loop 821/838/143`, `fib 699/742/192`, `particles 628/628/242`, `qsort 467/387/364`, `sha 246/249/140`, `vm 433/341/307`.
      - C2: `sh scripts/test_bench_threshold_gate.sh` printed `[PASS] T1: record-run appends 6 rows of 13 fields and 1 commit`, `[PASS] T2: geometric mean of 2.000 and 8.000 is 4.000`, `[PASS] T3: without valgrind, instructions is empty and run passes`, `[PASS] T4: without cproc, cproc_ms is empty and run passes`, `[PASS] T5: runtime_geomean_vs_gcc_o2 gate fails at 2.400 and passes at 2.200 vs 2.000`, `[PASS] T6: 17-field baseline prints [NEW] and passes`, `[PASS] T7: differing exit codes write no row and fail`, and last line `All bench threshold gate tests passed.`. Negative checks (each taken out alone and restored): without exit-code comparison in record mode, `[FAIL] T7: rc=0 exists=yes out=runtime_geomean_vs_gcc_o2 1.000`; without the tolerance line, `[FAIL] T5: rc=0 rc2=0`; without the `[NEW]` branch, `[FAIL] T6: 17-field baseline prints [NEW] and passes: exit 1, expected 0`.
      - C3: `sh scripts/bench_threshold_check.sh > build/runtime-run.log 2>&1` printed `  [NEW]  runtime_geomean_vs_gcc_o2  2.323: this host's baseline has no value for it; re-record the baseline (sh scripts/bench_cross_lang.sh --record)`, appended 6 rows to `bench/records/runtime_history.tsv` (`array_loop` 784/839/145/5.407/143420513, `fib` 697/757/192/3.630/7202391, `particles` 626/627/239/2.619/86149532, `qsort` 466/423/363/1.284/42994150, `sha` 254/256/140/1.814/71240882, `vm` 432/344/329/1.313/84900189), created 3 commits on `records` (`1c200e6` speed, `f1b717a` runtime, `883866c` gate pass; plus `ad085d5` for the header/README), and `git status --short` of the code tree was empty.
      - C4: `make test`: `Total: 3453 run, 3453 passed, 0 failed, 94 skipped (123.6s)`. `make preflight-changed`: passed (`Total: 1277 run, 1277 passed, 0 failed, 0 skipped (77.9s)` for checked build). `build/preflight-timings.tsv` `bench` step: `40` before, `81` after (+41s).
      - C5: committed on `main` as git:03937b7; stopping at check-in id:269a6.

- [x] +bench +review +AI-D @main @checkin Review of the record commit retry and the two small record fixes id:269a6
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Depends:** id:h1dj3, id:9d99n
    > **Depends changed (2026-11-15):** id:9d99n (the six-program runtime record) joined the batch.
    > **Placed:** directly after the task it reviews.
    > **Completed:** 2026-11-15 git:03937b7

    - **Checks:**
      - Re-read the queue and `git log -p` on `main` since git:50b1e8f; re-run what the **Awaiting review:** bullet names.
      - The retry hides no loss: a row that is appended and never committed (a lock that stays, a missing identity) still fails the run; a run whose row another run committed passes; eight runs at once.
      - id:9d99n: the six rows of a real run equal what `sh scripts/perf_gap.sh` prints within the noise of two runs; the geometric mean is the rows'; a program whose three builds disagree records nothing; what a wrong pass could hide: a slower program masked by the mean (plant one program 60% slower among six: the mean moves 8%, inside the tolerance; say whether a per-program limit is needed, with the spread of each program over five runs on this host).
    - **Review (2026-11-15), at git:03937b7:** both tasks do what their text settles; nothing of the batch is reverted. Two defects found, each with a task (id:s72rr, id:2msct), and three matters for the maintainer in `future.tm.md` (id:69svf, id:rdpmh, id:sx4a3).
      - **Re-run:** `sh scripts/test_bench_threshold_gate.sh` -> 29 `[PASS]` lines, R6, R7, F4 and T1 to T7 among them, last line `All bench threshold gate tests passed.`; `rg -n 'figures_history' AGENTS.md doc/developer_guide.md` -> `AGENTS.md:38`, `doc/developer_guide.md:202`; `make test` -> `Total: 3453 run, 3453 passed, 0 failed, 94 skipped (123.3s)`; `make preflight-changed` -> exit 0, `Total: 1277 run, 1277 passed, 0 failed, 0 skipped (77.8s)` for the checked build, no mutation targets a changed file, the rejection differential skipped (no checker file differs from git:e5087d4), and its bench step (which is `scripts/bench_threshold_check.sh`, the real run) printed `[NEW]  runtime_geomean_vs_gcc_o2  2.314: this host's baseline has no value for it; ...` and `All performance thresholds within tolerance of baseline.` `git status --short` of the code tree afterwards: only the untracked `.claude/`.
      - **The retry hides no loss (id:h1dj3)**, probed on scratch records work trees through `records_commit` itself. Eight runs at once: eight exits 0, all eight rows in `HEAD`, a clean status (one commit carried them). A lock that stays (`index.lock` planted): exit 1 after 4 s with `[FAIL] bench records: the row was appended to ... but not committed: fatal: Unable to create ... index.lock`, no row in `HEAD`. No identity (`user.useConfigOnly`, no global or environment configuration): exit 1 after 4 s with `... but not committed: Author identity unknown`, the file left staged. A row another commit already carried: exit 0 and no second commit. The four seconds are the cost of a real failure.
      - **The six-program record (id:9d99n).** Five runs of `sh scripts/perf_gap.sh --tsv` on a quiet host (load 1.1) against the three recorded runs: Zoril ms `array_loop` 773 to 826 (recorded 784, 810), `fib` 696 to 699, `particles` 614 to 627, `qsort` 461 to 465, `sha` 250 to 252 (recorded 254, 232), `vm` 431 to 434: the recorded rows are what the script prints. The gate row's mean is the rows': 2.323 and 2.362 recomputed from the two recorded runs' rows equal the 18th field of their gate rows. Disagreeing builds: with a `gcc` on `PATH` that builds the sixth program (`vm`) to exit 3, the run prints `perf_gap: vm: exit codes differ (zoril 165, cproc 165, gcc 3)`, exits 1 and writes no file, the five measured programs included (rows are appended only after the last program).
      - **What the mean hides, and the spread:** in id:69svf, with the figures. In short: the mean's noise over seven runs here is 2.3%; one program's ratio moves up to 16.1% (`array_loop`); one program 60% slower passes (`[OK]  runtime_geomean_vs_gcc_o2  2.537 (baseline 2.346, tol 15%)`, planted through the gate). Whether a limit for each program is added is the maintainer's (a new way for a preflight to fail); the recommendation there is yes at 30%, with the mean tightened to 8%.
      - **Found 1 (id:s72rr):** a failed instruction count is recorded as an empty field and the run passes; `set -- $(gate_count ...) || exit 1` cannot see the failure. `--gate-record` has the same shape. id:f0zzh does not wait for the fix: it checks its rows for an empty field.
      - **Found 2 (id:2msct):** `make test-changed` selects neither `bench-threshold-gate` nor `bench-contention` for a change to `scripts/perf_gap.sh` or `scripts/bench_cross_lang.sh`, the scripts those scenarios test.
      - **For the maintainer:** the `fib` confirmation retry is now reached only by two test cases with a tolerance file of their own (id:rdpmh); the scenario calls git inside `make test` and exits 127 without it, which dates from id:455bt (id:sx4a3).
      - **Small, no task:** the first recorded run's rows carry `0.1.0-alpha-177-g35bc5f7-dirty` as the version beside commit `03937b7` (the compiler was built before the commit and no compiled file changed; the row is kept as recorded).
      - **Order (decided here, delegated by the maintainer):** id:s72rr, id:2msct and their check-in id:a55tf are placed after id:f0zzh and not before it: id:f0zzh is a measurement for the deep-thinking session, depends on neither, and would otherwise wait a round for nothing.

- [x] +bench +measurement +AI-D @main Backfill the six-program runtime record and the instruction counts, and re-record this host's baseline id:f0zzh
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Depends:** id:269a6
    > **Placed:** after the check-in id:269a6: it uses id:9d99n's record mode. The maintainer's request of 2026-11-15.
    > **Completed:** 2026-11-15 git:03937b7

    - **Do:** with id:tmydc's driver (its text is in that task, in `completed.tm.md`), run id:9d99n's `scripts/perf_gap.sh --record-run --kind backfill` for the same 42 commits (git:7417fdc and the 41 first-parent commits up to git:e5087d4 that changed `src/`, `stdlib/`, `rt/`, `tools/zilc/` or `tools/zbuild/`), today's harness beside each commit's `build/` and `stdlib/`, one at a time on a quiet host, each commit's rows committed on `records` with the measured sha. The instruction counts are exact, so their series shows every commit that changed generated code; the times are today's measurement. Then `sh scripts/bench_cross_lang.sh --record` on `main`'s tip, so this host's baseline carries `runtime_geomean_vs_gcc_o2` and the new measure is gated.
    - **Report in the task:** each commit where a program's instruction count moved, with the count before and after; each step of more than 5% in a program's ratio to gcc; and whether `bench/perf_gap/gate_baseline.tsv`'s two re-recordings line up with the counts.
    - **Checks:** C1 the number of `backfill` rows in `bench/records/runtime_history.tsv` is 42 times 6, or the commits that failed are named with their error; C2 after `--record`, a `sh scripts/bench_threshold_check.sh` run prints `[OK]  runtime_geomean_vs_gcc_o2`, not `[NEW]`; C3 `git status --short` of the code tree is empty.
    - **Added by the check-in id:269a6 (2026-11-15):** C4 no `backfill` or `baseline` row has an empty `instructions` field (`awk -F'\t' '($7=="backfill"||$7=="baseline") && $13==""' bench/records/runtime_history.tsv | wc -l` prints 0): until id:s72rr a failed count is written as an empty field and the run passes. `scripts/perf_gap.sh --record-run` on its own makes no contention check (its `status` is `ok` unless `RUN_STATUS` says otherwise), so the driver reads the load before each commit and waits for a quiet host.

    - **The harness trial (2026-11-15):** `DRY=1 sh build/backfill/measure_rt.sh 7417fdc` (nothing recorded): today's `scripts/perf_gap.sh --record-run --kind backfill` runs unchanged beside the release's `build/` and `stdlib/` and gives six rows with a count each, in 107 s with the build: Zoril / cproc / gcc ms and instructions `array_loop` 803 / 780 / 144, 143420513; `fib` 697 / 747 / 192, 7202391; `particles` 626 / 627 / 240, 86149532; `qsort` 464 / 425 / 363, 42994150; `sha` 250 / 261 / 140, 71240882; `vm` 432 / 336 / 331, 84900189; geometric mean 2.323. The six counts equal those of git:03937b7's recorded runs. The series is the 42 commits of id:tmydc (`sort build/backfill/series.txt` equals the `commit` column of the 42 `backfill` rows of `bench/records/gate_history.tsv`). The worktrees are built four at a time first, then measured one at a time; before each measurement the driver waits for a 1-minute load under 1.5.
    - **The driver** (`build/backfill/measure_rt.sh <sha>`, run from the main tree, one commit at a time when measuring):

    ```sh
    #!/bin/sh
    # usage: measure_rt.sh <sha>   (run from the main tree's root; one at a time)
    # Builds <sha> in a scratch worktree if it is not built yet, then runs today's
    # scripts/perf_gap.sh --record-run --kind backfill (today's scripts/ and bench/perf_gap/ beside
    # that tree's build/ and stdlib/) and appends its six rows to bench/records/runtime_history.tsv,
    # one commit on `records` per measured commit.
    set -u
    sha=$1
    R=$(pwd)
    B=$R/build/backfill
    wt=$B/wt-$sha
    H=$B/h-$sha
    T=$B/t-$sha
    if [ ! -x "$wt/build/zilc" ] || [ ! -f "$wt/build/runtime.o" ]; then
        [ -d "$wt" ] || git worktree add --detach "$wt" "$sha" > "$B/$sha.wt.log" 2>&1 || { echo "$sha: worktree failed"; exit 1; }
        (cd "$wt" && make > "$B/$sha.make.log" 2>&1) || { echo "$sha: build failed (see $B/$sha.make.log)"; exit 1; }
    fi
    [ "${BUILD_ONLY:-0}" -eq 1 ] && { echo "$sha: built"; exit 0; }
    rm -rf "$H" "$T"; mkdir -p "$H/bench" "$T"
    cp -R "$R/scripts" "$H/scripts"
    cp -R "$R/bench/perf_gap" "$H/bench/perf_gap"
    for f in config.mk config.local.mk config.local.sh; do [ -f "$R/$f" ] && cp "$R/$f" "$H/$f"; done
    ln -s "$wt/build" "$H/build"
    ln -s "$wt/stdlib" "$H/stdlib"
    # a quiet host: wait (up to 5 min) for the 1-minute load to fall under 1.5
    i=0
    while [ $i -lt 60 ]; do
        l=$(cut -d' ' -f1 /proc/loadavg)
        awk -v l="$l" 'BEGIN { exit !(l < 1.5) }' && break
        sleep 5; i=$((i + 1))
    done
    [ $i -lt 60 ] || { echo "$sha: host not quiet (load $l)"; exit 1; }
    HOST_ID=a52c24a80e04 ZORIL_COMMIT=$sha RUNTIME_HISTORY=$T/r.tsv sh "$H/scripts/perf_gap.sh" --record-run --kind backfill > "$B/$sha.rt.log" 2>&1
    rc=$?
    n=$(awk -F'\t' 'NR>1 && NF==13 && $7=="backfill" && $13!=""' "$T/r.tsv" 2>/dev/null | wc -l)
    if [ $rc -ne 0 ] || [ "$n" -ne 6 ]; then echo "$sha: perf_gap failed rc=$rc rows=$n (see $B/$sha.rt.log)"; exit 1; fi
    if [ "${DRY:-0}" -eq 1 ]; then cut -f2,3,6-13 "$T/r.tsv"; tail -1 "$B/$sha.rt.log"; exit 0; fi
    awk 'NR>1' "$T/r.tsv" >> "$R/bench/records/runtime_history.tsv"
    git -C "$R/bench/records" add runtime_history.tsv && git -C "$R/bench/records" commit -q -m "a52c24a80e04 $sha: runtime backfill (measured $(date +%Y-%m-%d) with the harness of $(git -C "$R" rev-parse --short HEAD))" || { echo "$sha: records commit failed"; exit 1; }
    printf '%s load %s %s\n' "$sha" "$l" "$(tail -1 "$B/$sha.rt.log")"
    ```

    - **Result (2026-11-15):** the six-program runtime record of this host (`a52c24a80e04`) from the release to git:cb76bfa is on `records`: 252 `backfill` rows in `bench/records/runtime_history.tsv`, one commit there per measured commit, then a baseline measured on git:03937b7 that carries `runtime_geomean_vs_gcc_o2`. No file of `main` changed, so no test run is owed.
      - C1: `awk -F'\t' '$7=="backfill"' bench/records/runtime_history.tsv | wc -l` prints 252 (42 times 6), and `git -C bench/records log --oneline | grep -c 'runtime backfill'` prints 42: every commit built (`builds done: 42 built, 0 failed`) and ran; none failed. Each measurement started at a 1-minute load between 1.10 and 1.42.
      - **Instruction counts: none moved.** Each program's count is the same number in all 42 commits and in today's runs: `array_loop` 143420513, `fib` 7202391, `particles` 86149532, `qsort` 42994150, `sha` 71240882, `vm` 84900189. No commit between the release and git:cb76bfa changed how many instructions these six programs execute.
      - **`bench/perf_gap/gate_baseline.tsv`:** `git log --all -- bench/perf_gap/gate_baseline.tsv` shows one commit, the release (git:7417fdc); no re-recording after it is in the history, so there is nothing to line up. The file's counts differ from the measured ones, from the release on: four programs by 2 instructions (`array_loop` 143420511, `fib` 7202389, `particles` 86149530, `vm` 84900187) and `qsort` 42893691 (+0.23% measured), `sha` 71158539 (+0.12%). `sh scripts/perf_gap.sh --gate-check` today prints `+0.0%` four times, `[PASS] qsort +0.2% instructions`, `[PASS] sha +0.1% instructions`. So the baseline was recorded with a compiler or library slightly before the release's and has not been re-recorded since; it is inside the 2% tolerance and was left alone.
      - **Steps of more than 5% in a ratio: many, none of them a change.** Every program shows steps of 5% to 17% between neighbouring commits (`particles` 15, `array_loop` 17, `vm` 11, `sha` 11, `fib` 19, `qsort` 21), each undone one or two commits later, with the instruction count unchanged across it. They are two timing states of the host, not of the code: a program's time takes one of two values (`fib` 697 or about 640 ms; `particles` 626 or about 571; `qsort` 461 or about 424; gcc's `particles` 239 or about 223, gcc's `qsort` 359 or about 330, gcc's `vm` 330 or about 303), under the `powersave` governor on a quiet host. Ranges over the 42 commits: ratio `array_loop` 5.051 to 6.211 (23.0%), `fib` 3.231 to 3.960 (22.6%), `qsort` 1.167 to 1.407 (20.6%), `particles` 2.367 to 2.841 (20.0%), `vm` 1.213 to 1.439 (18.6%), `sha` 1.757 to 2.057 (17.1%); the geometric mean 2.260 to 2.428 (7.4%). The largest single steps: `array_loop` +17.4% at git:6a00117 (gcc 158 to 141 ms), `particles` +16.9% at git:8c10546, `qsort` -16.9% at git:58983a0. This is three times the spread the check-in id:269a6 saw in seven runs; id:69svf's recommendation is corrected with it.
      - The baseline: `sh scripts/bench_cross_lang.sh --record` on git:03937b7 at load 0.82 -> `Recorded baseline row to .../bench/records/gate_history.tsv (host a52c24a80e04)`, `runtime_geomean_vs_gcc_o2 = 2.385`, six `baseline` rows in `runtime_history.tsv` (`f3933fc`, `04b10be`, `dbc5145` on `records`; `40a5ca8` there says why it was re-recorded).
      - C2: `sh scripts/bench_threshold_check.sh` afterwards -> `Comparing against baseline of 2026-11-15-20-54-57, commit 03937b7 (host a52c24a80e04):` and `[OK]  runtime_geomean_vs_gcc_o2  2.325 (baseline 2.385, tol 15%)`, exit 0.
      - C3: `git status --short` of the code tree prints only the untracked `.claude/`, which this task did not write; `git -C bench/records status --short` prints nothing.
      - C4: `awk -F'\t' '($7=="backfill"||$7=="baseline") && $13==""' bench/records/runtime_history.tsv | wc -l` prints 0.
      - The scratch worktrees under `build/backfill/` were removed; the driver and each commit's logs are kept there.

- [x] +bench +testinfra +AI-G @main A failed instruction count stops `perf_gap.sh`'s record run and its baseline recording id:s72rr
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Found by:** the check-in id:269a6.
    > **Placed:** after id:f0zzh, which does not wait for it (ordered by the reviewing session of id:269a6): id:f0zzh checks its own rows for an empty `instructions` field on a host where valgrind works, so this fix blocks nothing.
    > **Check-in:** reviewed in id:a55tf.
    > **Completed:** 2026-11-15 git:3e05dc7

    - **Now:** `scripts/perf_gap.sh` reads an instruction count with `set -- $(gate_count "$n") || exit 1` at three places (`--gate-record`, `--gate-check`, `--record-run`). `gate_count` reports a failure with `fail`, which exits only the command substitution's subshell, and `set` then returns 0, so `|| exit 1` never runs (`sh -c 'f(){ exit 1; }; set -- $(f) || echo caught; echo "status=$?"'` prints `status=0`). Measured at git:03937b7 with a `valgrind` first on `PATH` that prints `valgrind: broken` and exits 2: `PERF_GAP_OUT=<scratch> RUNTIME_HISTORY=<scratch>/rt.tsv sh scripts/perf_gap.sh -n 1 --record-run fib` prints `perf_gap: fib: callgrind reported no instruction count (see ...)`, then `runtime_geomean_vs_gcc_o2 3.593`, exits 0, and the row it wrote ends in an empty `instructions` field. The record then reads as a host without valgrind (where an empty field is the design) although the count failed. `--gate-record` has the same shape: it would write a baseline row with two empty fields and move it over `bench/perf_gap/gate_baseline.tsv`. `--gate-check` fails already, by accident (`[FAIL] <name> exits , baseline <N>`).
    - **Settled:** at each of the three places, capture first and test the capture's status: `_gc=$(gate_count "$n") || exit 1`, then `set -- $_gc`. Nothing else changes: with no `valgrind` on `PATH` the record run still leaves the field empty and passes (T3).
    - **Tests** (in `scripts/test_bench_threshold_gate.sh`, beside T1 to T7, with `setup_pg_scratch`): T8, a `valgrind` stub that prints nothing to stderr and exits 2: `--record-run` exits non-zero, its output has `callgrind reported no instruction count`, and `bench/records/runtime_history.tsv` does not exist. T9, the same stub with `--gate-record` and a `bench/perf_gap/gate_baseline.tsv` holding one line `fib`, `1`, `0` (tab-separated): non-zero exit and the file still holds exactly that line.
    - **Checks:**
      - C1: before: the two commands of T8 and T9 by hand on a scratch tree; quote each exit status (expected 0 and 0), the row with its empty last field, and the baseline file's content after the run.
      - C2: after: `sh scripts/test_bench_threshold_gate.sh`; quote the `[PASS]` lines of T3, T8 and T9 and its last line. Put `set -- $(gate_count "$n") || exit 1` back at the `--record-run` place alone and quote T8 failing; the same at the `--gate-record` place for T9; restore.
      - C3: `sh scripts/perf_gap.sh --gate-check`; quote its six `[PASS]` lines (the real valgrind, nothing changed).
      - C4: `make test`; quote its `Total:` line. No `src/`, `stdlib/` or `tools/` file changes, so no preflight (`git diff --stat HEAD~1` shows it).
      - C5: commit on `main`, add `**Awaiting review:**` with C2 to C4, `tm done`.
    - **Awaiting review:** `sh scripts/test_bench_threshold_gate.sh`, `sh scripts/perf_gap.sh --gate-check`, `make test`.
    - **Completion note:**
      - C1: before: T8 exited 0 and wrote `2026-11-15-21-25-53\tb118adc\t0.1.0-test\tunknown\tpowersave\tok\trun\tfib\t2\t2\t2\t1.000\t`; T9 exited 0 and overwrote `gate_baseline.tsv` with `# Instructions executed...` / `# Re-record...` / `fib\t\t`.
      - C2: after: `sh scripts/test_bench_threshold_gate.sh` printed `[PASS] T3: without valgrind, instructions is empty and run passes`, `[PASS] T8: failed instruction count stops --record-run with no row`, `[PASS] T9: failed instruction count stops --gate-record and preserves baseline`, and last line `All bench threshold gate tests passed.`. Negative checks (each restored alone): `--record-run` printed `[FAIL] T8: rc=0 exists=yes out=perf_gap: fib: callgrind reported no instruction count (see build/perf_gap/gate/fib.vg)`; `--gate-record` printed `[FAIL] T9: rc=0 base='# Instructions executed by each workload's Zoril build at gate size (scripts/perf_gap.sh).`. Restored both.
      - C3: `sh scripts/perf_gap.sh --gate-check` printed `[PASS] array_loop +0.0% instructions`, `[PASS] fib +0.0% instructions`, `[PASS] particles +0.0% instructions`, `[PASS] qsort +0.2% instructions`, `[PASS] sha +0.1% instructions`, `[PASS] vm +0.0% instructions`.
      - C4: `git diff --stat HEAD~1` changed only `scripts/perf_gap.sh` and `scripts/test_bench_threshold_gate.sh` (no `src/`, `stdlib/` or `tools/`). `make test`: `Total: 3453 run, 3453 passed, 0 failed, 94 skipped (123.4s)`.
      - C5: committed on `main` as git:3e05dc7.

- [x] +testinfra +AI-G @main A change to `scripts/perf_gap.sh` or `scripts/bench_cross_lang.sh` selects the scenarios that test them id:2msct
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Found by:** the check-in id:269a6.
    > **Placed:** after id:s72rr, in the batch the check-in id:a55tf reviews.
    > **Check-in:** reviewed in id:a55tf.
    > **Completed:** 2026-11-15 git:164ba45

    - **Now:** `scripts/test_bench_threshold_gate.sh` (the `bench-threshold-gate` scenario) tests `scripts/bench_cross_lang.sh`'s gate and, since git:03937b7, `scripts/perf_gap.sh --record-run`; `scripts/test_bench_contention.sh` (`bench-contention`) tests `scripts/bench_cross_lang.sh` too. The tier table selects neither scenario for a change to those two scripts, so `make test-changed` on such a change runs none of their tests: `sh scripts/select_test_tier.sh --scenarios scripts/perf_gap.sh` and `... scripts/bench_cross_lang.sh` both print an empty line, while `... scripts/bench_threshold_check.sh` prints `bench-threshold-gate`. What the wrong skip hides: a broken gate or record mode, from the author who ran only the scoped tier (`make test` still runs both scenarios).
    - **Settled:** in `scripts/test_tiers.tsv`, the scenarios column (the seventh) of the `scripts/bench_cross_lang.sh` row becomes `bench-contention bench-threshold-gate` and that of the `scripts/perf_gap.sh` row `bench-threshold-gate`; each row's description names what it now selects. No other row changes.
    - **Checks:**
      - C1: before: the two `select_test_tier.sh --scenarios` commands above; quote both (empty) lines.
      - C2: after: the same two commands; quote `bench-contention bench-threshold-gate` and `bench-threshold-gate`. `sh scripts/select_test_tier.sh --gates scripts/perf_gap.sh` prints what it printed before the change (quote both).
      - C3: `sh scripts/test_tier_select.sh`; quote its last line. If it holds an expectation for either row, say which and what it was changed to.
      - C4: `make test-changed BASE=HEAD` with the table edit uncommitted, then `make test`; quote each `Total:` line.
      - C5: commit on `main`, add `**Awaiting review:**` with C2 to C4, `tm done`, and stop at the check-in id:a55tf.
    - **Awaiting review:** `sh scripts/select_test_tier.sh --scenarios scripts/perf_gap.sh`, `sh scripts/select_test_tier.sh --scenarios scripts/bench_cross_lang.sh`, `sh scripts/select_test_tier.sh --gates scripts/perf_gap.sh`, `sh scripts/test_tier_select.sh`, `make test-changed BASE=HEAD~1`, `make test`.
    - **Completion note:**
      - C1: before: `sh scripts/select_test_tier.sh --scenarios scripts/perf_gap.sh` printed `` (empty line); `sh scripts/select_test_tier.sh --scenarios scripts/bench_cross_lang.sh` printed `` (empty line).
      - C2: after: `sh scripts/select_test_tier.sh --scenarios scripts/perf_gap.sh` printed `bench-threshold-gate`; `sh scripts/select_test_tier.sh --scenarios scripts/bench_cross_lang.sh` printed `bench-contention bench-threshold-gate`. `sh scripts/select_test_tier.sh --gates scripts/perf_gap.sh` printed `no-new-deps perf-gate portability` both before and after.
      - C3: `sh scripts/test_tier_select.sh` last line: `test_tier_select: all checks passed` (it held no expectation for either row).
      - C4: `make test-changed BASE=HEAD` (uncommitted): `Total: 21 run, 21 passed, 0 failed, 0 skipped (8.9s)`. `make test`: `Total: 3453 run, 3453 passed, 0 failed, 94 skipped (123.9s)`.
      - C5: committed on `main` as git:164ba45; stopping at check-in id:a55tf.

- [x] +bench +review +AI-D @main @checkin Review of the instruction-count failure and the two tier rows id:a55tf
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Depends:** id:s72rr, id:2msct
    > **Placed:** directly after the batch it reviews.
    > **Completed:** 2026-11-15 git:164ba45

    - **Checks:**
      - Re-read the queue and `git log -p` on `main` since git:03937b7; re-run what each **Awaiting review:** bullet names.
      - id:s72rr: the three places are the only ones (`rg -n 'gate_count' scripts/`); a real `valgrind` that crashes midway (kill it) stops the record run with no row; a host without valgrind still records an empty field.
      - id:2msct: every script the two scenarios run (`rg -o 'scripts/[a-z_/]*\.sh' scripts/test_bench_threshold_gate.sh scripts/test_bench_contention.sh | sort -u`) selects its scenario, `scripts/record_figures.sh` among them.
    - **Review (2026-11-15), at git:164ba45:** both tasks do what their text settles; nothing is reverted. One observation went to `future.tm.md` (id:sgqxe).
      - **Re-run:** `sh scripts/test_bench_threshold_gate.sh` -> 31 `[PASS]` lines, T3, T8 and T9 among them, last line `All bench threshold gate tests passed.`; `sh scripts/perf_gap.sh --gate-check` -> six `[PASS]` lines (`+0.0%` four times, `qsort +0.2%`, `sha +0.1%`); the two `select_test_tier.sh --scenarios` commands -> `bench-threshold-gate` and `bench-contention bench-threshold-gate`, `--gates scripts/perf_gap.sh` -> `no-new-deps perf-gate portability`; `sh scripts/test_tier_select.sh` -> `test_tier_select: all checks passed`; `make test` -> `Total: 3453 run, 3453 passed, 0 failed, 94 skipped (123.6s)`.
      - **A run that does not count:** the first `make test` of this review gave `Total: 3446 run, 3445 passed, 1 failed` (`mutation-self-test`: `Baseline compiler has failing test(s); fix them first: perf-gate`). The cause was this review, not the batch: a probe of `--gate-record fib` with a `valgrind` meant to be killed finished instead and replaced `bench/perf_gap/gate_baseline.tsv` with a one-program file while the suite ran. The file was restored with `git checkout`, `--gate-check` printed its six `[PASS]` lines again, and the run quoted above was made afterwards with nothing else running.
      - **id:s72rr:** `rg -n 'gate_count' scripts/` shows the definition and the three call sites, all three in the captured form. A real `valgrind` killed at once (`kill -9` from a wrapper on `PATH`): `--record-run fib` prints `perf_gap: fib: callgrind reported no instruction count (see ...)`, exits 1 and writes no file. A host without valgrind still records an empty field (T3). `--gate-record` with a failing count was not probed on the real tree (it writes the tracked baseline); T9 covers it on a scratch tree.
      - **id:2msct:** of the scripts the two scenarios run, `bench_cross_lang.sh`, `perf_gap.sh` and the two test scripts select their scenario by their rows; `scripts/lib/portability.sh`, `scripts/lib/records.sh` and `scripts/record_figures.sh` select everything (`--tier` prints `all core_infra`, `all core_infra` and `all`); `scripts/env.sh` selects `clean-tree` only, and the scenarios merely source it.
      - **Seen, in `future.tm.md` (id:sgqxe):** `--gate-record NAME` writes a baseline holding only the named programs, dropping the others' rows (what the probe above did), and a recording that fails leaves `gate_baseline.tsv.tmp` behind.
      - **The maintainer's answers (2026-11-15)** to the questions of id:269a6 are recorded in id:69svf (no limit for each program) and id:rdpmh (the retry is removed; id:41rnk does it, reviewed in id:95cy3). id:sx4a3 is still open with the maintainer.

- [x] +bench +decision +AI-D @main Decide whether the runtime gate also limits each program's ratio, not only the geometric mean id:69svf
    > **Created:** 2026-11-15
    > **Found by:** the check-in id:269a6.
    > **Placed:** under Evidence and tooling: a decision for the maintainer, blocking nothing in the queue.
    > **Completed:** 2026-11-15 git:164ba45

    - **Measured (id:269a6, this host, git:03937b7):** seven runs of the six programs (five of `sh scripts/perf_gap.sh --tsv`, two recorded). The geometric mean of the Zoril to gcc ratios stayed within 2.313 to 2.366 (2.3%). Each program's ratio moved more: `array_loop` 5.406 to 6.279 (16.1%, from gcc's side: 129 to 145 ms), `fib` 3.598 to 3.966 (10.2%, one gcc run of 176 ms against 191 to 194), `particles` 2.558 to 2.758 (7.8%), `sha` 1.719 to 1.814 (5.5%), `qsort` 1.275 to 1.295 (1.6%), `vm` 1.308 to 1.320 (0.9%). The Zoril times alone: `array_loop` 773 to 826 ms (6.9%), `sha` 232 to 254 (9.5%), the other four within 2.3%.
    - **What the mean hides:** one program 60% slower moves the mean by 8.2% (1.6 to the power 1/6), inside the 15% tolerance: with `array_loop`'s time times 1.6 the gate prints `[OK]  runtime_geomean_vs_gcc_o2  2.537 (baseline 2.346, tol 15%)`. One program alone trips the gate only when it is 2.31 times slower (1.15 to the power 6). The instruction-count gate (`perf-gate`, 2% a program, in `make test`) sees such a change wherever it executes more instructions; it does not see one that costs time without instructions (cache behaviour, branch prediction) nor its own stated blind spot (`rep movsb` counted as one instruction), which `scripts/perf_gap.sh`'s header tells the author to "judge by the timing".
    - **Question for the maintainer:** does the timing gate get a limit for each program as well?
    - **Recommendation (the reviewing session's):** yes, a loose one, and tighten the mean. (a) Each program's `ratio_vs_gcc` against the same program's row of this host's last `baseline` in `bench/records/runtime_history.tsv`, tolerance 30%: above the 16% this host shows between quiet runs, below the 60% plant. (b) The mean's tolerance from 15% to 8%: its noise here is 2.3%, and at 8% one program 60% slower is at the limit. A limit of 15% a program would fail quiet runs here (`array_loop`). The cost: one more way a preflight fails on a loaded host; a confirmation re-run of the one program that exceeds its limit would cover that. Not decided: the two numbers, and whether the limit compares ratios (noise from gcc's side) or Zoril's times alone (no noise from gcc, but nothing cancels a slow host).
    - **Corrected by id:f0zzh (2026-11-15), 42 more runs on this host:** the noise is about three times what the seven runs above showed. Over the 42 backfill runs, in which no instruction count moved, a program's ratio ranges over 17% to 23% (`array_loop` 23.0%, `fib` 22.6%, `qsort` 20.6%, `particles` 20.0%, `vm` 18.6%, `sha` 17.1%), single steps reach 17%, and the geometric mean ranges over 7.4% (2.260 to 2.428). Each program's time takes one of two values under the `powersave` governor. So the recommendation above no longer holds as written: a mean tolerance of 8% would fail quiet runs, and a limit of 30% a program leaves little room over 23%. **Recommendation now:** leave the mean at 15%; if a limit for each program is wanted, first remove the two timing states (the `performance` governor for the run, or the minimum of the runs in place of the median: `PERF_GAP_STAT=min` exists), measure the spread again over the same 42 commits' worth of runs, and set the limit from that. Until then the instruction-count gate is the per-program check, and it saw nothing in 42 commits.
    - **Do, once answered:** settle the numbers in an `+AI-G` task (the limit, T-cases with a baseline of six rows and one program planted over its limit, the limit taken out to watch the case fail), after id:f0zzh, whose `--record` writes the `baseline` rows this compares with.
    - **Decided (the maintainer, 2026-11-15):** no limit for each program. The gate stays the geometric mean at 15%; the instruction-count gate is the check of each program. Nothing follows from this task.

- [x] +bench +decision +AI-D @main Decide whether the `fib` confirmation retry, which the gate no longer reaches, is removed id:rdpmh
    > **Created:** 2026-11-15
    > **Found by:** the check-in id:269a6.
    > **Placed:** under Evidence and tooling: a decision for the maintainer, blocking nothing in the queue.
    > **Completed:** 2026-11-15 git:164ba45

    - **Now (git:03937b7):** `bench/cross_lang/tolerances.cfg` no longer lists `runtime_ratio_vs_gcc_o2` (id:9d99n), so the confirmation re-measurement in `check_thresholds_gate` (`scripts/bench_cross_lang.sh`, the `[RETEST]` branch, which runs only for that axis) is reached by no real run. `scripts/test_bench_threshold_gate.sh` keeps its two cases passing (`deliberately slowed build fails the gate after confirmation`, `transient noise spike re-measured and passes gate`) by giving them a tolerance file of their own that still lists the axis (`tol_legacy.cfg`). id:9d99n's design said the retry "goes with the old gate" if it did not fit the new measure; the task kept it and said so.
    - **Also seen:** the `vs last` line of the gate still prints `runtime_ratio_vs_gcc_o2` and not the gated `runtime_geomean_vs_gcc_o2` (`l_geo` is read and never used); `bench/cross_lang/tolerances.cfg` gained an empty last line (harmless: the reader skips it).
    - **Question for the maintainer:** remove the retry and its two cases, or keep them for a host that puts the `fib` axis back into its tolerance file?
    - **Recommendation (the reviewing session's):** remove them: the new measure's noise on this host is 2.3% against a 15% tolerance, so it needs no retry, and code only a test's private configuration reaches reads as a safeguard the gate does not have. If id:69svf adds a limit for each program, its re-run of the one program is the retry's successor and is written there. The `fib` ratio stays measured and recorded.
    - **Decided (the maintainer, 2026-11-15):** the retry is removed, with its two test cases. id:41rnk carries it out (the settled edits are there), reviewed in id:95cy3.

- [x] +bench +testinfra +AI-G @main The gate no longer carries the `fib` confirmation retry, and its `vs last` line shows the gated mean id:41rnk
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Decided by:** the maintainer, 2026-11-15 (id:rdpmh): the retry is removed.
    > **Placed:** after id:rdpmh, the decision it carries out.
    > **Check-in:** reviewed in id:95cy3.
    > **Completed:** 2026-11-15 git:704a259

    - **Now (git:164ba45):** as id:rdpmh describes. `check_thresholds_gate` in `scripts/bench_cross_lang.sh` re-measures only the `runtime_ratio_vs_gcc_o2` axis (the `[RETEST]` branch), which `bench/cross_lang/tolerances.cfg` no longer lists; `scripts/test_bench_threshold_gate.sh` reaches it with `tol_legacy.cfg`. The gate's `vs last` line prints `runtime_ratio_vs_gcc_o2 <now> (was <last>)` and not the gated mean.
    - **Settled:**
      1. `scripts/bench_cross_lang.sh`, in `check_thresholds_gate`: the `[RETEST]` arm goes (the `if [ "$ok" -eq 0 ] && [ "$axis" = "runtime_ratio_vs_gcc_o2" ] ...` branch down to its `fi`-side `elif`, which becomes the `if`), and so does the case arm `runtime_ratio_vs_gcc_o2) baseline="$b_rat" ;;`: the axis is not gated, with any tolerance file (a line naming it is skipped like any unknown axis). `b_rat` is then unused: read that field into `_`. `measure_runtime_pair` stays: the `fib` ratio is still measured and written to the metrics file, the gate row and `speed_history.tsv` as today.
      2. The `vs last` line prints `runtime_geomean_vs_gcc_o2 %s (was %s)` in place of the `runtime_ratio_vs_gcc_o2` pair, from the run's value and the last row's 18th field, each `-` where it is empty.
      3. `scripts/test_bench_threshold_gate.sh`: cases 2 and 3 (`deliberately slowed build fails the gate after confirmation`, `transient noise spike re-measured and passes gate`) go with their stub programs under `$tmp/work`; case 1 keeps its name's sense with the shipped tolerances (no `TOLERANCES_FILE`) and expects `[OK]  clean_throughput_loc_s`, renamed `normal run within tolerance passes`; `tol_legacy.cfg` goes; the header comment no longer says "noise retry". The two removed cases are removed on the maintainer's decision: their subject no longer exists.
      4. `bench/cross_lang/tolerances.cfg` loses its empty last line.
    - **Tests:** T10, beside T5, with `write_header_18` and its 18-field baseline row (mean 2.000) and `metrics_t5_pass.tsv` (2.200) on a history file of its own: the output has `runtime_geomean_vs_gcc_o2 2.200 (was 2.000)`. T11, the same run against a history whose only row has 17 fields (`write_header`, `append_row`): the output has `runtime_geomean_vs_gcc_o2 2.200 (was -)`. T12, a tolerance file that lists `runtime_ratio_vs_gcc_o2|15|lower_better` and a metrics file whose ratio is 5.250 against a baseline of 3.867: exit 0 and no line of the output has `runtime_ratio_vs_gcc_o2` after `[FAIL]` or `[RETEST]`.
    - **Checks:**
      - C1: before: `sh scripts/test_bench_threshold_gate.sh | grep -c '^\[PASS\]'` (expected 31) and `rg -c 'RETEST|noise retry|tol_legacy' scripts/bench_cross_lang.sh scripts/test_bench_threshold_gate.sh`; quote both.
      - C2: after: the test script; quote the `[PASS]` lines of case 1, T10, T11 and T12, the count of `[PASS]` lines (expected 32: 31, less 2, plus 3) and the last line. `rg -n 'RETEST|noise retry|tol_legacy|b_rat' scripts/` prints nothing. Put the `runtime_ratio_vs_gcc_o2` pair back into the `vs last` line and quote T10 failing; put the case arm back and quote T12 failing; restore.
      - C3: a real run, `sh scripts/bench_threshold_check.sh > build/41rnk-run.log 2>&1`: quote its `vs last` line and its three `[OK]` lines; `git status --short` of the code tree shows only this task's files.
      - C4: `tail -c 1 bench/cross_lang/tolerances.cfg | od -c` shows one newline and `tail -n 1` prints the `runtime_geomean_vs_gcc_o2` line.
      - C5: `make test-changed BASE=HEAD` before the commit (quote that `bench-threshold-gate` and `bench-contention` ran, and its `Total:` line), then `make test`; quote its `Total:` line. No `src/`, `stdlib/` or `tools/` file changes, so no preflight; C3 is the run of the bench step.
      - C6: commit on `main`, add `**Awaiting review:**` with C2 to C5, `tm done`, and stop at the check-in id:95cy3.
    - **Awaiting review:** `sh scripts/test_bench_threshold_gate.sh`, `rg -n 'RETEST|noise retry|tol_legacy|b_rat' scripts/`, `sh scripts/bench_threshold_check.sh`, `tail -c 1 bench/cross_lang/tolerances.cfg | od -c`, `tail -n 1 bench/cross_lang/tolerances.cfg`, `make test-changed BASE=HEAD~1`, `make test`.
    - **Completion note:**
      - C1: before: `sh scripts/test_bench_threshold_gate.sh | grep -c '^\[PASS\]'` printed `31`; `rg -c 'RETEST|noise retry|tol_legacy' scripts/bench_cross_lang.sh scripts/test_bench_threshold_gate.sh` printed `scripts/test_bench_threshold_gate.sh:6` and `scripts/bench_cross_lang.sh:2`.
      - C2: after: `sh scripts/test_bench_threshold_gate.sh` printed `[PASS] normal run within tolerance passes`, `[PASS] T10: vs last line prints runtime_geomean_vs_gcc_o2 2.200 (was 2.000)`, `[PASS] T11: vs last line prints runtime_geomean_vs_gcc_o2 2.200 (was -) for 17-field row`, `[PASS] T12: runtime_ratio_vs_gcc_o2 in tolerance file is ignored`, `PASS_COUNT=32`, and last line `All bench threshold gate tests passed.`. `rg -n 'RETEST|noise retry|tol_legacy|b_rat' scripts/` printed nothing. Negative checks (each put back alone and restored): `runtime_ratio_vs_gcc_o2` in `vs last` failed T10 with `[FAIL] T10: vs last line prints runtime_geomean_vs_gcc_o2 2.200 (was 2.000): output lacks 'runtime_geomean_vs_gcc_o2 2.200 (was 2.000)'`; restoring the `runtime_ratio_vs_gcc_o2` case arm failed T12 with `[FAIL] T12: rc=1 out=Detected Host:`.
      - C3: `sh scripts/bench_threshold_check.sh > build/41rnk-run.log 2>&1` printed `  vs last run (2026-11-15-20-56-17): clean_throughput_loc_s 10320 (was 10212), incremental_rebuild_ms 21 (was 22), runtime_geomean_vs_gcc_o2 2.380 (was 2.325)`, `[OK]  clean_throughput_loc_s     10320 (baseline 10356, tol 15%)`, `[OK]  incremental_rebuild_ms     21 (baseline 22, tol 15%)`, `[OK]  runtime_geomean_vs_gcc_o2  2.380 (baseline 2.385, tol 15%)`; `git status --short` showed only `bench/cross_lang/tolerances.cfg`, `scripts/bench_cross_lang.sh`, and `scripts/test_bench_threshold_gate.sh`.
      - C4: `tail -c 1 bench/cross_lang/tolerances.cfg | od -c` printed `0000000  \n` / `0000001`; `tail -n 1 bench/cross_lang/tolerances.cfg` printed `runtime_geomean_vs_gcc_o2|15|lower_better`.
      - C5: `make test-changed BASE=HEAD` selected `bench-contention bench-threshold-gate` (`Integration  2 run  2 passed  0 failed  0 skipped`), `Total: 28 run, 28 passed, 0 failed, 0 skipped (42.0s)`. `make test`: `Total: 3453 run, 3453 passed, 0 failed, 94 skipped (123.6s)`.
      - C6: committed on `main` as git:704a259; stopping at check-in id:95cy3.

- [x] +bench +review +AI-D @main @checkin Review of the removal of the `fib` confirmation retry id:95cy3
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Depends:** id:41rnk
    > **Placed:** directly after the task it reviews.
    > **Completed:** 2026-11-15 git:704a259

    - **Checks:**
      - Re-read the queue and `git log -p` on `main` since git:164ba45; re-run what the **Awaiting review:** bullet names.
      - Nothing else went with the retry: a real `sh scripts/bench_threshold_check.sh` still writes `runtime_ratio_vs_gcc_o2` into the metrics file, the gate row's 16th field and `speed_history.tsv`; `measure_runtime_pair` is still called once.
      - The gate still fails where it should: T5 unchanged, and a planted run 20% over the baseline's mean through `--check-thresholds-only` exits 1.
    - **Review (2026-11-15), git:704a259, the one commit since git:164ba45:**
      - The four settled edits are as written: the `[RETEST]` arm and the `runtime_ratio_vs_gcc_o2` case arm are gone from `check_thresholds_gate`, the baseline's and the last row's 16th field are read into `_`, the `vs last` line prints the mean with `-` for an empty side, cases 2 and 3 with their stubs and `tol_legacy.cfg` are gone, and `bench/cross_lang/tolerances.cfg` ends at its last line. Nothing else changed in the three files.
      - **Awaiting review, re-run:** `rg -n 'RETEST|noise retry|tol_legacy|b_rat' scripts/` prints nothing. `tail -c 1 bench/cross_lang/tolerances.cfg | od -c` prints `0000000  \n`; `tail -n 1` prints `runtime_geomean_vs_gcc_o2|15|lower_better`. `sh scripts/bench_threshold_check.sh > build/95cy3-run.log 2>&1` exits 0: `  vs last run (2026-11-15-22-57-53): clean_throughput_loc_s 10393 (was 10320), incremental_rebuild_ms 22 (was 21), runtime_geomean_vs_gcc_o2 2.376 (was 2.380)`, `[OK]  clean_throughput_loc_s     10393 (baseline 10356, tol 15%)`, `[OK]  incremental_rebuild_ms     22 (baseline 22, tol 15%)`, `[OK]  runtime_geomean_vs_gcc_o2  2.376 (baseline 2.385, tol 15%)`. `make test-changed BASE=HEAD~1` selected everything (an untracked directory of this checkout is in its change set): `Total: 3453 run, 3453 passed, 0 failed, 94 skipped (123.5s)`. `make test`: `Total: 3453 run, 3453 passed, 0 failed, 94 skipped (124.0s)`.
      - **`sh scripts/test_bench_threshold_gate.sh`, run seven times:** six runs print 32 `[PASS]` lines and exit 0, with `[PASS] normal run within tolerance passes` and the `[PASS]` lines of T5, T10, T11 and T12. The first run printed 31 and `[FAIL] R6: concurrent record commits failed (fail=0 rows=3 status='')`, exit 1. That is not this batch's: the header of a new history file is written with a truncating `>`, which deletes a row another run appended since the test for the file (reproduced without git, 2 of 30 trials). id:at2k3 has the reproducer, the cause and the settled fix.
      - **Nothing else went with the retry:** the real run above prints `runtime_ratio_vs_gcc_o2= 3.909`, its row of `bench/records/gate_history.tsv` has `3.909` in the 16th field (`run pass 10393 22 3.909 5.119 2.376`, fields 12 to 18, the tabs written here as spaces), and `bench/records/speed_history.tsv` gained its `runtime_ratio_vs_gcc_o2 zoril_vs_gcc fib(38)x3 3.909` row; `rg -n 'measure_runtime_pair "' scripts/bench_cross_lang.sh` prints the one call. The three `records` commits were made (`704a259: speed`, `runtime`, `gate pass`).
      - **The gate still fails where it should:** T5 is untouched by the diff and passes. Planted through `--check-thresholds-only` with an 18-field baseline of mean 2.000 and a metrics file whose `fib` ratio is 9.000 (baseline 3.000): mean 2.400 prints `[FAIL] runtime_geomean_vs_gcc_o2  2.400 regressed past baseline 2.000 (lower_better, tol 15%)` and exits 1 with a `run fail` row; mean 2.290 prints three `[OK]` lines and exits 0. The tripled `fib` ratio alone fails nothing, as decided in id:rdpmh.
      - **Sibling routes:** no document or script outside the two edited ones names the retry (`rg -i 're-?measure|confirmation (run|measurement)|noise spike|RETEST'` over the tree finds only unrelated text in `doc/bootstrap/two_stage.md` and `bench/fuzz/`). `RT_PAIR_RATIO` and `m_rat` are still used (the measurement and the row).
      - **Findings:** (1) T12's pattern spells the removed tag in two halves (`RE''TEST`) so that C2's `rg` prints nothing: the settled text asked for both, and the split keeps the letter of one. id:at2k3 (settled 3) replaces it with a pattern that needs no tag name and is stronger (no verdict line of any tag names the axis). (2) The R6 failure above: id:at2k3. (3) T10 to T12 stand before T6 in the script; order only, nothing to do.
      - **Plan:** id:at2k3 added before id:sx4a3, which now depends on it; the check-in id:f5mbr reviews both. Nothing moved, re-tagged or re-prioritized. The pull of the `tasks` branch before these edits failed (the remote is not reachable from this machine); the local branch was 66 commits ahead and nothing was rebased.

- [x] +bench +testinfra +AI-G @main A history file gets its header without truncating a row a concurrent run has appended id:at2k3
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Depends:** id:95cy3
    > **Check-in:** reviewed in id:f5mbr.
    > **Found by:** the check-in id:95cy3 (the code dates from id:455bt and id:h1dj3; id:41rnk did not touch it).
    > **Placed:** before id:sx4a3, which it blocks: id:sx4a3's checks count the `[PASS]` lines of a scenario that this defect fails about one run in seven, and both edit the same scripts.
    > **Completed:** 2026-11-15 git:e97c4cd

    - **Now (git:704a259):** `sh scripts/test_bench_threshold_gate.sh` failed once in seven runs on this host, each time alone on the machine but for the last four: `[FAIL] R6: concurrent record commits failed (fail=0 rows=3 status='')`, 31 `[PASS]` lines, exit 1. The scenario is in `make test` (`bench-threshold-gate`), so `make test` fails at that rate.
    - **Cause (reproduced without git):** `append_gate_history_row` in `scripts/bench_cross_lang.sh` writes the header with `printf ... > "$GATE_HISTORY"` when `[ ! -f "$GATE_HISTORY" ] || [ ! -s "$GATE_HISTORY" ]`. Run A finds no file; run B creates it and appends its row; run A's `>` truncates the file and B's row is gone. The commit retry of id:h1dj3 is not involved (`status=''`, every run exits 0). Reproducer, which is C1:
    ```sh
    d=$(mktemp -d); printf 'clean_throughput_loc_s\t10000\nincremental_rebuild_ms\t100\nruntime_ratio_vs_gcc_o2\t3.0\npeak_rss_mb_per_kloc\t10.0\nruntime_geomean_vs_gcc_o2\t2.0\n' > $d/m.tsv
    bad=0; i=0; while [ $i -lt 100 ]; do i=$((i+1)); rm -f $d/h.tsv
      for j in 1 2 3 4; do BENCH_HOST_ID=aaaaaaaaaaaa GATE_HISTORY=$d/h.tsv METRICS_FILE=$d/m.tsv sh scripts/bench_cross_lang.sh --force --check-thresholds-only >/dev/null 2>&1 & done; wait
      n=$(awk -F'\t' 'NR>1 && NF==18{c++} END{print c+0}' $d/h.tsv); h=$(grep -c '^date' $d/h.tsv)
      [ "$n" -eq 4 ] && [ "$h" -eq 1 ] && [ "$(head -n 1 $d/h.tsv | cut -c1-4)" = date ] || { bad=$((bad+1)); echo "trial $i rows=$n headers=$h"; }
    done; echo "bad trials: $bad of 100"; rm -rf $d
    ```
    - **Measured:** at git:704a259 it printed `bad trials: 2 of 30` (30 trials; `trial 14 rows=3 headers=1`, `trial 16 rows=3 headers=1`). With the header written to `$GATE_HISTORY.hdr.$$` and linked into place (`ln`, which fails where the file exists), tried as a local change and taken out again: `bad trials: 0 of 100`.
    - **Who it reaches:** a history file that does not exist yet and two runs at once: a new clone's or a new host's first preflights, and every scratch repository of the tests. The real `bench/records/*.tsv` exist, so no recorded row was lost by this (`git -C bench/records log` shows no row removed: nobody rewrites one).
    - **The same write in four more places** (the route class: a header written with `>` after a test for the file): `scripts/bench_cross_lang.sh` for `$SPEED_HISTORY` (`if [ ! -f "$SPEED_HISTORY" ]`), `scripts/perf_gap.sh` for `$RUNTIME_HISTORY`, `scripts/record_figures.sh` and `scripts/record_marker_density.sh` for `$HISTORY`. Not reproduced for these four; the code has the same shape.
    - **Settled 1:** `scripts/lib/records.sh` gains `records_header <file> <header line>`, called by all five sites in place of their `if`/`printf ... >` (the `elif` of `append_gate_history_row` that adds a missing last newline stays, as an `if` of its own after the call). Each site passes its header as `"$(printf 'date\tcommit\t...')"` without the trailing `\n`, the field names unchanged.
    ```sh
    records_header() {
        _rh_file="$1"
        mkdir -p "$(dirname "$_rh_file")"
        _rh_tmp="$_rh_file.hdr.$$"
        if [ -e "$_rh_file" ]; then
            [ ! -s "$_rh_file" ] || return 0
            printf '%s\n' "$2" > "$_rh_tmp"
            mv -f "$_rh_tmp" "$_rh_file"
        else
            printf '%s\n' "$2" > "$_rh_tmp"
            ln "$_rh_tmp" "$_rh_file" 2>/dev/null || true
            rm -f "$_rh_tmp"
        fi
    }
    ```
    - **Settled 1, the order of its tests:** the test for the file comes first and the test for its content second, in that order: a file another run links in between has content, so it is never replaced. Its header comment says why the header is linked and not written (a truncating write deletes a row appended since the test), and names the accepted gap: a file that exists and is empty is replaced, which two runs can still race on; nothing in the tree creates an empty history file.
    - **Settled 2:** `scripts/test_bench_threshold_gate.sh`, cases H1 to H3 after T12, with no git (they stay in this script under id:sx4a3). Each sources `scripts/lib/records.sh` in a subshell and calls `records_header "$tmp/h/x.tsv" "a$(printf '\t')b"`. H1: no file before; after, the file is the one line `a<tab>b` and the directory holds no other file. H2: the file holds a header and a row before; after, `cmp` with a copy made before. H3, the planted race: a directory first on `PATH` with an `ln` that appends `late row` to its last argument's file after writing `a<tab>b` there, then runs the real `ln` with the same arguments (found with `command -v ln` before `PATH` changes) and exits with its status; after the call the file's second line is `late row` and its line count is 2.
    - **Settled 3:** T12's test for the absent lines becomes `grep -qE '^ *\[[A-Z]+\] +runtime_ratio_vs_gcc_o2'` (no verdict line of any tag names the axis), in place of the pattern that spells a removed tag in two halves.
    - **Settled 4:** `scripts/test_tiers.tsv`: the `scripts/record_figures.sh` and `scripts/record_marker_density.sh` rows keep what they select; nothing is added (a change to `scripts/lib/records.sh` selects everything already: C5 quotes that).
    - **Checks:**
      - C1: before: the reproducer above with 100 trials; quote its last line (expected: one or more bad trials; if none in 100, run it once more and quote both). And `sh scripts/test_bench_threshold_gate.sh | grep -c '^\[PASS\]'` (expected 32, or 31 with the R6 line: quote the line).
      - C2: after: the reproducer; quote `bad trials: 0 of 100`. `sh scripts/test_bench_threshold_gate.sh`: quote the `[PASS]` lines of H1, H2, H3, T12 and R6, the count (expected 35) and the last line. Run the script ten times in a loop and quote each run's count and exit status.
      - C3: take out alone, quote the failing line, restore: in `records_header`, the `ln` line replaced by `cat "$_rh_tmp" > "$_rh_file"` (H3 fails: the late row is gone); the `[ ! -s "$_rh_file" ] || return 0` line (H2 fails).
      - C4: `rg -n "> \"\\\$(GATE_HISTORY|SPEED_HISTORY|RUNTIME_HISTORY|HISTORY)\"" scripts/` prints nothing, and `rg -c 'records_header' scripts/bench_cross_lang.sh scripts/perf_gap.sh scripts/record_figures.sh scripts/record_marker_density.sh` prints 2, 1, 1, 1.
      - C5: `sh scripts/select_test_tier.sh --scenarios scripts/lib/records.sh`; quote the line. `make test-changed BASE=HEAD` before the commit and `make test`; quote each `Total:` line. A real `sh scripts/bench_threshold_check.sh > build/at2k3-run.log 2>&1`: quote its three `[OK]` lines, `git -C bench/records log --oneline | head -3`, and `git -C bench/records status --short` (empty: no `.hdr.` file left), and `head -n 1` of each of `bench/records/gate_history.tsv`, `speed_history.tsv` and `runtime_history.tsv` unchanged against `git -C bench/records show HEAD~3:<file> | head -n 1`. `sh scripts/record_figures.sh` and `sh scripts/record_marker_density.sh` are not run on the real records (they are the milestone's); F1 to F4 cover the first, and for the second quote a run with `HISTORY` naming a file under `build/` if the script takes one, or `not run` and why.
      - C6: commit on `main`, add `**Awaiting review:**` with C2 to C5, `tm done`. The next task is id:sx4a3; the check-in id:f5mbr reviews both.
    - **Awaiting review:** `sh scripts/test_bench_threshold_gate.sh`, `rg -c 'records_header' scripts/bench_cross_lang.sh scripts/perf_gap.sh scripts/record_figures.sh scripts/record_marker_density.sh`, `make test`, `sh scripts/bench_threshold_check.sh`.
    - **Completion note:**
      - C1: before: reproducer printed `bad trials: 9 of 100` (`trial 8 rows=2 headers=1`, `trial 28 rows=3 headers=1`, ...); `sh scripts/test_bench_threshold_gate.sh | grep -c '^\[PASS\]'` printed `32`.
      - C2: after: reproducer printed `bad trials: 0 of 100`. `sh scripts/test_bench_threshold_gate.sh` printed `[PASS] T12: runtime_ratio_vs_gcc_o2 in tolerance file is ignored`, `[PASS] H1: records_header creates new file with header and no temp files`, `[PASS] H2: records_header preserves existing non-empty file`, `[PASS] H3: records_header does not truncate concurrent row`, `[PASS] R6: four concurrent record commits all exit 0 with 4 rows and clean status`, count `35`, last line `All bench threshold gate tests passed.`. Ten runs in a loop: `run 1` through `run 10` all `count=35 rc=0`.
      - C3: negative checks (each taken out alone and restored): replacing `ln` with `cat "$_rh_tmp" > "$_rh_file"` failed H3 (`[FAIL] H3: lines=1 line2=''`); removing `[ ! -s "$_rh_file" ] || return 0` failed H2 (`[FAIL] H2: existing file modified`).
      - C4: `rg -n '[^>] > "\$(GATE_HISTORY|SPEED_HISTORY|RUNTIME_HISTORY|HISTORY)"' scripts/` prints nothing (note: `> "` without `[^> ]` matches `>>` append lines); `rg -c 'records_header' scripts/bench_cross_lang.sh scripts/perf_gap.sh scripts/record_figures.sh scripts/record_marker_density.sh` prints `bench_cross_lang.sh:2`, `perf_gap.sh:1`, `record_figures.sh:1`, `record_marker_density.sh:1`.
      - C5: `sh scripts/select_test_tier.sh --scenarios scripts/lib/records.sh` prints `` (empty line; `--tier` selects `all core_infra`). `make test-changed BASE=HEAD`: `Total: 3453 run, 3453 passed, 0 failed, 94 skipped (124.0s)`. `make test`: `Total: 3453 run, 3453 passed, 0 failed, 94 skipped (124.2s)`. Real `sh scripts/bench_threshold_check.sh > build/at2k3-run.log 2>&1`: `[OK]  clean_throughput_loc_s     10248 (baseline 10356, tol 15%)`, `[OK]  incremental_rebuild_ms     22 (baseline 22, tol 15%)`, `[OK]  runtime_geomean_vs_gcc_o2  2.388 (baseline 2.385, tol 15%)`; `git -C bench/records log --oneline | head -3`: `abe81fb` (`gate pass`), `400d48d` (`runtime`), `df45f2c` (`speed`); `git -C bench/records status --short` empty; `head -n 1` of `gate_history.tsv`, `speed_history.tsv`, `runtime_history.tsv` unchanged vs `HEAD~3`. `HISTORY=build/at2k3-density.tsv sh scripts/record_marker_density.sh` printed `Marker density @ 2026-11-15 (704a259-dirty): line 0.73% (362/49688), per-fn 7.99% (153/1915), ptr-cast 793, ref-forge 70` / `Appended to build/at2k3-density.tsv` (removed afterwards).
      - C6: committed on `main` as git:e97c4cd.

- [ ] +testinfra +portability +AI-G @main The `bench-threshold-gate` scenario of `make test` calls git and fails without it id:sx4a3
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Depends:** id:95cy3, id:at2k3
    > **Depends note:** it edits `scripts/test_bench_threshold_gate.sh`, which id:41rnk edits; the check-in id:95cy3 closes that batch. id:at2k3 (added by the check-in id:95cy3) edits the same scripts and stops the R6 case failing one run in seven, which this task's counts of `[PASS]` lines need.
    > **Check-in:** reviewed in id:f5mbr.
    > **Found by:** the check-in id:269a6 (the cases date from id:455bt; id:h1dj3 and id:9d99n added more of the same kind).
    > **Placed:** under Evidence and tooling: not this batch's defect; the maintainer decides when it is taken (it matters at the next `make dist-check`).

    - **Now (git:03937b7):** `scripts/test_bench_threshold_gate.sh` is the `bench-threshold-gate` scenario of `make test` (`scripts/test_plan.tsv`). Its cases R1, R2, R4 to R7, F4 and T1 to T7 build scratch repositories with `git init`, `git commit` and `git worktree add --orphan` (git 2.42 or later), and the earlier cases reach git through `scripts/bench_cross_lang.sh --check-thresholds-only`. With a `git` first on `PATH` that logs its arguments and exits 127, `sh scripts/test_bench_threshold_gate.sh` exits 127 after its P8 case, 23 git calls logged: under `set -eu` the first `git -C <scratch> init` ends the script. So `make test` from a source tarball on a machine without git fails this scenario, and in a checkout `make test` calls git, both against the rule "`make test` uses no git" (`AGENTS.md`, Portability).
    - **Not checked:** whether `make dist-check` reports it today (it was not run for this finding).
    - **Do (a design, then an `+AI-G` task):** the cases whose subject is the records commit (a script whose job is git) move to a script that `make preflight` and `make preflight-changed` run, as `scripts/test_preflight.sh` is; the cases that stay in `make test` (tolerances, per-host baseline lookup, the geometric mean and its gate from a metrics file) reach no git, shown by the logging `git` on `PATH`. Decide first whether `--check-thresholds-only` may call git at all when its history file is outside `bench/records/`.
    - **Decided (the maintainer, 2026-11-15):** a user who downloads a tarball runs `make test` without git; the cases that need git leave `make test`.
    - **Promoted and re-tagged (2026-11-15, the reviewing session of id:a55tf):** from `future.tm.md`, after the check-in id:95cy3 because it edits the test script id:41rnk edits; `+AI-D` became `+AI-G` because the design below settles what was open. **Branch:** `main`. **Depends:** id:95cy3 (hard: the same file). Reviewed in the check-in that follows it.
    - **Why the scenario calls git at all (read at git:164ba45).** Three different reasons, only the first a need:
      1. *Git is the subject.* R1, R2, R4, R5, R6, R7 test `records_commit`, the mount check and the `-dirty` mark of `scripts/lib/records.sh`; F1 to F4 test `scripts/record_figures.sh`, which commits its row; T1 counts the commit of `perf_gap.sh --record-run`. These cannot run without git.
      2. *Scaffolding.* T2, T3, T4, T7, T8 and T9 test what `perf_gap.sh` measures and writes, not the commit, but `setup_pg_scratch` gives each a repository and a `records` work tree because the rows go to `bench/records/` by default. With `RUNTIME_HISTORY` naming a plain file they need no repository.
      3. *The scripts under test ask git for things the case does not use.* `scripts/bench_cross_lang.sh` sets `ZORIL_COMMIT=$(records_repo_commit ...)` on every run, and `records_commit` asks `git rev-parse --show-toplevel` about any history file's directory before it finds there is nothing to commit. So Case 1, P1 to P8, T5 and T6, which only compare numbers in temporary files, call git in a checkout (the 23 logged calls of **Now**), and fall back quietly without it.
    - **What exists already:** the plan's group `git` (`scripts/test_plan.tsv`: "the group `git` holds the ones that need git") is run by `make preflight` and `make preflight-changed` (`scripts/preflight.sh`: `./scripts/test.sh --quiet --group git`) and not by `make test` (`GROUPS_ALL` in `scripts/test.sh`). `make user-tools` (`scripts/check_user_tools.sh`, part of `make preflight`) is the check of the rule: `make test` from an export without git, and in the checkout with a failing, logging `git` on `PATH`. It was not run for this finding; C1 runs it.
    - **Settled:**
      1. A new script `scripts/test_bench_records.sh` and a plan row `scenario bench-records git ./scripts/test_bench_records.sh` (tab-separated, beside the other `git` rows). The cases of reason 1 move there unchanged with the helpers they use (`setup_scratch_repo`, `expect`, the stubs of F1 to F4, `setup_pg_scratch` for T1). T1 stays whole there.
      2. `scripts/test_bench_threshold_gate.sh` keeps Case 1, P1 to P8, R3 (it is the no-git case), T2 to T9 and what id:41rnk added. Its `setup_pg_scratch` builds a plain directory (no `git init`, no work tree); each T case passes `RUNTIME_HISTORY="$dir/out/runtime_history.tsv"` and reads the rows there. T8 then checks that this file does not exist.
      3. `scripts/bench_cross_lang.sh`: `ZORIL_COMMIT="${ZORIL_COMMIT:-$(records_repo_commit "$REPO_ROOT")}"`, as `scripts/perf_gap.sh` has it. The cases that stay pass `ZORIL_COMMIT=abc1234`.
      4. `scripts/lib/records.sh`, `records_commit`: before any git call, return 0 when the file is not under `<root>/bench/records/` (the same `case` as `records_check_target`). R1 to R7 use `<scratch>/bench/records/`, so they are unaffected.
      5. `scripts/test_tiers.tsv`: a row for `scripts/test_bench_records.sh` selecting `bench-records`; the `scripts/bench_cross_lang.sh` and `scripts/perf_gap.sh` rows add `bench-records` to their scenarios. (`scripts/lib/records.sh` and `scripts/record_figures.sh` select everything already.)
      6. A case G1 at the end of `scripts/test_bench_threshold_gate.sh`: it runs the whole script again (guarded by an environment variable so it does not recurse) with a `git` first on `PATH` that appends its arguments to a log and exits 127, and passes when that run exits 0 and the log does not exist.
    - **Checks:**
      - C1: before: `make user-tools > build/sx4a3-user-tools-before.log 2>&1`; quote its exit status and the lines that name this scenario or git. And `sh scripts/test_bench_threshold_gate.sh` with the logging `git` of **Now** on `PATH`: quote the exit status (expected 127) and the number of logged calls.
      - C2: after: `sh scripts/test_bench_threshold_gate.sh`; quote the count of `[PASS]` lines, the `[PASS]` line of G1 and the last line. `sh scripts/test_bench_records.sh`; quote the count and the last line. The two counts add up to the count before the change plus one (G1); quote all three numbers.
      - C3: take out alone, quote G1 failing with the logged call, restore: the early return of `records_commit` (settled 4); the `ZORIL_COMMIT` default (settled 3) together with one case's `ZORIL_COMMIT=abc1234`.
      - C4: `sh scripts/select_test_tier.sh --scenarios scripts/bench_cross_lang.sh`, `... scripts/perf_gap.sh`, `... scripts/test_bench_records.sh`; quote the three lines. `sh scripts/test_tier_select.sh`; quote its last line.
      - C5: `./scripts/test.sh --quiet --group git`; quote the `bench-records` line and the `Total:` line.
      - C6: `make user-tools > build/sx4a3-user-tools.log 2>&1`; quote its exit status and last line. If it fails for a reason that is not this scenario, record the failure verbatim in this task and stop: that is another finding.
      - C7: `make test`, then `make preflight-changed` (it runs the `git` group and the bench step, which commits through the changed `records_commit`); quote each `Total:` line, and the three `records` commits of the bench step (`git -C bench/records log --oneline | head -4`).
      - C8: commit on `main`, add `**Awaiting review:**` with C2 to C7, `tm done`, and stop at the check-in.

- [ ] +testinfra +review +AI-D @main @checkin Review of the git-free `bench-threshold-gate` scenario and the `bench-records` scenario id:f5mbr
    > **Created:** 2026-11-15
    > **Branch:** `main`
    > **Depends:** id:at2k3, id:sx4a3
    > **Placed:** directly after the task it reviews.

    - **Checks:**
      - Re-read the queue and `git log -p` on `main` since id:95cy3's commit; re-run what the **Awaiting review:** bullet names, `make user-tools` among them.
      - No case was lost or weakened in the move: every case name of the script before the change appears in one of the two scripts after it, and each moved case's body is unchanged (`git diff` with `--color-moved`).
      - The scenario that stays calls no git by any route: the logging `git` over the whole of `make test` (part 2 of `scripts/check_user_tools.sh`), and from an export without git (part 1).
      - `records_commit`'s early return hides no real commit: a history file under `bench/records/` of a mounted work tree is still committed (R1), and a real `sh scripts/bench_threshold_check.sh` makes its three commits.
      - id:at2k3: its reproducer prints `bad trials: 0 of 100`, ten runs of `sh scripts/test_bench_threshold_gate.sh` (and of `sh scripts/test_bench_records.sh`, where R6 is after id:sx4a3) all pass, H1 to H3 are still in the scenario that stays and reach no git, and no `.hdr.` file is left in `bench/records/` after a real run. Read the four sites that were not reproduced (`$SPEED_HISTORY`, `$RUNTIME_HISTORY`, the two `$HISTORY`): the header text of each is unchanged, field for field.

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
    - **Waiting for the maintainer (2026-11-15):** `provenance` (git:913bf05) does not contain the ten commits `main` gained since git:e0febf3, among them git:67f87b0, the work of id:0tv49 whose check-in id:3yasf this task depends on (`git merge-base --is-ancestor 67f87b0 provenance` fails; `git rev-list --count provenance..main` prints 10). Those commits change `src/check_zir.zrl` and `tools/zbuild/`, and close `gap_88` to `gap_93`. **Question:** merge `main` (git:e5087d4) into `provenance` before this task starts? **Recommendation (a reviewing session's):** yes: the series is rebuilt on `main` after each merge anyway, the closure rules this task touches sit beside the capture checks of git:44ab3e6, and the recorded figures are recomputed from the merged tree as the branch rules say. The merge is the maintainer's; nothing was changed on `provenance`.
    - **Answered (2026-11-15):** the maintainer merged `main` (git:e5087d4) into `provenance` as git:ec0fc1d. The recorded figures in `doc/SAFETY.md` and `doc/spec/unsafe_policy.md` were recomputed from the merged tree; `make test` there gave `Total: 3694 run, 3694 passed, 0 failed, 94 skipped (135.3s)`, and `REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=e5087d4` passed: 80 mutations caught, the clean-tree build and fixpoint, `reject-diff: base verdicts: fresh (no cache)` with `0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69159 programs`, and `Total: 1400 run, 1400 passed, 0 failed, 0 skipped (46.7s)` for the checked build. Its benchmark step had no baseline to compare with (id:nxrav). This task is no longer waiting.

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
