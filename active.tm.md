# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

## Now

- [x] +testinfra +tests +AI-G @testinfra Z2b6 A test's `// EXPECT:` text is matched against the compiler's output only, not the command line `--verbose` logs id:r85jb
    > **Created:** 2026-11-13
    > **Context:** found at check-in id:drcga (finding 2), settled by the reviewer for an `+AI-G` session; older than the batch it was found in
    > **Branch:** `testinfra`
    > **Depends:** id:drcga
    > **Placed:** after id:9nnvq, first of the batch that fixes what check-in id:drcga found. It is not a hole of the batch under review, so it does not hold up the merge; the maintainer may move it ahead of the merge.
    > **Completed:** 2026-11-13 git:4ea969c

    - **Why:** with `--verbose`, `tr_run_file` (`scripts/lib/test_runner.sh`) writes the compile command (`$ ./build/zoril ... FILE`) into `$_log`, and `_tr_missing_expect` greps `$_log`. So an `EXPECT` substring that occurs in the command line (the file's path, an include root, `--emit-zil`) is found there, and a test that fails without `--verbose` passes with it. The review's probe, a program that compiles cleanly with the header `// EXPECT: --emit-zil`: `./scripts/test.sh build/drcga/h2/w.zrl` gives `[FAIL] ... (diagnostic missing)`, and `./scripts/test.sh --verbose` on the same file gives `[PASS]`. In the tree, `tests/modular/iface_attrs/private_trait.zrl` (`// EXPECT: private`, a path that holds `private_trait`) is the one header whose text is in its own command line. That directory is in no per-file group, so no recorded result changes. `_tr_diagnostics` has the same fault: for a path under `tests/error_reporting/` it picks the command line as an `error` line.
    - **Do (`scripts/lib/test_runner.sh`, POSIX `sh`):**
      1. In `tr_run_file`, the compile step's output goes to `$_dir/compile.out` (truncated first, and created empty for a `.zil` test that is not compiled), and is then appended to `$_log`, so the verbose output keeps its order: command, then its output.
      2. `_tr_missing_expect` and `_tr_diagnostics` read `$_dir/compile.out`, not `$_log`. Every caller of the two is in a branch that follows the compile step (`compile_fail`, `warning`, `compile failed`), so nothing they need is in another file.
      3. `scripts/test_test_headers.sh` gains the review's case, through its `check` function (a well-formed header whose test must fail): `expect_in_cmdline`, the header `// EXPECT: --emit-zil` on `fn main() -> i32 { return 0; }`, whose line is `[FAIL] $P/expect_in_cmdline.zrl (diagnostic missing)`. The scenario already runs `test.sh --verbose`, so it covers the route.
    - **Checks:**
      - C1: `sh scripts/test_test_headers.sh`: quote the `expect_in_cmdline` line and the last line.
      - C2: take-out. Point `_tr_missing_expect` back at `$_log` (a scratch edit) and watch C1's case fail; quote it, then restore.
      - C3: `./scripts/test.sh --verbose tests/error_reporting/` and the same without `--verbose` give the same `Total:` line; quote both.
      - C4: `sh scripts/test_runner_output.sh --both` passes; quote its last line for each runner (`ztest` runs each file through `test.sh --item`).
      - C5: scripts only, so no `make preflight-changed`. `make test` after the last edit; quote its `Total:` line.
    - **Completion (generalist, 2026-11-13, git:4ea969c):** `tr_run_file` writes the compiler's output to `$_dir/compile.out` (empty for a `.zil` test) and appends it to `$_log` after the command; `_tr_missing_expect` and `_tr_diagnostics` read `compile.out`. `scripts/test_test_headers.sh` has the case `expect_in_cmdline`.
      - C1: `sh scripts/test_test_headers.sh`: `[PASS] expect_in_cmdline: [FAIL] build/test-headers/cases/expect_in_cmdline.zrl (diagnostic missing)`; last line `[PASS] test headers: every malformed case failed, every control passed`.
      - C2: take-out (`_tr_missing_expect` back on `$_log`): `[FAIL] expect_in_cmdline: expected ..., got: [PASS] build/test-headers/cases/expect_in_cmdline.zrl (14ms)`; restored.
      - C3: `./scripts/test.sh --verbose tests/error_reporting/` and the same without `--verbose` both print `Total: 458 run, 458 passed, 0 failed, 0 skipped (2.0s)`.
      - C4: `sh scripts/test_runner_output.sh --both` last line `[PASS] opts_hidden output follows the grammar and its counts agree (build/ztest)`; `sh scripts/test_runner_output.sh` last line `[PASS] a scenario exiting 77 is reported as skipped, with its reason`; no `[FAIL]`.
      - C5: `make test` after the last edit: `Total: 3274 run, 3274 passed, 0 failed, 94 skipped (119.6s)`. Scripts only; no `make preflight-changed`.

- [x] +testinfra +tests +AI-G @testinfra Z2b7 The header grammar refuses `expected exit` beside a warning test's `EXPECT`, and an `@skip:` with no reason id:haf6g
    > **Created:** 2026-11-13
    > **Context:** found at check-in id:drcga (finding 1), settled by the reviewer for an `+AI-G` session
    > **Branch:** `testinfra`
    > **Depends:** id:drcga
    > **Placed:** after id:r85jb, in the batch that fixes what check-in id:drcga found
    > **Completed:** 2026-11-13 git:4075934

    - **Why:** two header shapes that id:bekxx's grammar accepts still make a test mean something other than it says. The review's probes (`./scripts/test.sh --verbose` on scratch files):
      - `// EXPECT: x` then `// expected exit 3` on a program that returns 3: `[PASS]`. An `EXPECT` without `expected compile fail` makes the test a warning test, which only compiles, so the `expected exit` is never checked. The pass came through id:r85jb's fault, the `x` in the file's path, but without that fault the exit is still dropped.
      - `// @skip:` with nothing after it, on a program that returns 3: `[FAIL] ... (wrong exit code)`. The empty reason leaves `skip` empty, so the test runs instead of being skipped.
      - Neither shape is in the tree today (the review's survey of the headers of `tests/` and `corpus/`), so no test changes kind.
    - **Do (`scripts/lib/test_runner.sh`, the awk in `tr_expectations`):**
      1. A header with an `// EXPECT:` line and an `expected exit` line, and no `expected compile fail`, is malformed; the offending line is the second of the pair. So is one with an `// EXPECT:` line and `expected compile success` (a warning test does not assemble, so `compile success` would be dropped the same way). The survey found neither in the tree.
      2. `// @skip:` followed by nothing but blanks is malformed.
      3. `tests/incremental/error_unresolvable_import.zrl`'s first line, `// expected compile fail: unresolvable import`, is one the grammar refuses. That file is compiled only by `scripts/test_incremental.sh`, which reads no header, so this does not fail today, but it reads as a directive. Rewrite it as `// expected compile fail` followed by `// An import of a module that does not exist.` Then `scripts/test_incremental.sh` and its `[PASS] unresolvable import failed with located diagnostic` line are unchanged.
      4. `scripts/test_test_headers.sh` gains the malformed cases `expect_and_exit` (line 2), `expect_and_success` (line 2) and `skip_empty` (line 1), and a control `expect_with_fail`: `// expected compile fail` + `// EXPECT: ` + a diagnostic on a program that fails to compile, which still passes.
    - **Checks:**
      - C1: `sh scripts/test_test_headers.sh`: quote the four new lines and the last line.
      - C2: take-out. Remove step 1's and step 2's rules (a scratch edit) and watch the three malformed cases fail; quote them, then restore.
      - C3: the survey: `. scripts/lib/test_runner.sh` and `tr_expectations` over every `*.zrl` of `tests/` and `corpus/` that is not a `*_lib.zrl`. Only `tests/runner/fixtures/tests/bad_header.zrl` is malformed; quote the command's output.
      - C4: `sh scripts/test_incremental.sh --quiet` passes; quote its last line.
      - C5: scripts and one test comment only, so no `make preflight-changed`. `make test` after the last edit; quote its `Total:` line.
    - **Completion (generalist, 2026-11-13, git:4075934):** in `tr_expectations`' awk: an `// EXPECT:` line after `expected exit` or `compile success`, or an `expected exit` / `compile success` line after an `EXPECT` (with no `compile fail` before), is malformed at the second line of the pair; an empty `// @skip:` is malformed. `tests/incremental/error_unresolvable_import.zrl` now starts `// expected compile fail` then `// An import of a module that does not exist.`.
      - C1: `sh scripts/test_test_headers.sh`: `[PASS] expect_and_exit: [FAIL] ... (malformed header, line 2: // expected exit 3)`, `[PASS] expect_and_success: [FAIL] ... (malformed header, line 2: // expected compile success)`, `[PASS] skip_empty: [FAIL] ... (malformed header, line 1: // @skip:)`, `[PASS] expect_with_fail: [PASS] build/test-headers/cases/expect_with_fail.zrl`; last line `[PASS] test headers: every malformed case failed, every control passed`.
      - C2: take-out of the three rules: `[FAIL] expect_and_exit`, `[FAIL] expect_and_success`, `[FAIL] skip_empty`, and only those; restored.
      - C3: the survey (`tr_expectations` over every `*.zrl` of `tests/` and `corpus/` except `*_lib.zrl`, in `build/bekxx/survey.sh`) printed only `tests/runner/fixtures/tests/bad_header.zrl: 1: // expected exit banana`.
      - C4: `sh scripts/test_incremental.sh --quiet`: `PASS: all incremental compilation tests passed.`, with the `unresolvable import` line unchanged in the run.
      - C5: `make test` after the last edit: `Total: 3274 run, 3274 passed, 0 failed, 94 skipped (119.6s)`. No `make preflight-changed` (scripts and a test comment).

- [x] +testinfra +tests +AI-G @testinfra Z2b8 zbuild-diff and the interface-attribute check read test headers with the runner's reader id:f6tfj
    > **Created:** 2026-11-13
    > **Context:** found at check-in id:drcga (finding 3), settled by the reviewer for an `+AI-G` session
    > **Branch:** `testinfra`
    > **Depends:** id:drcga
    > **Placed:** after id:haf6g, in the batch that fixes what check-in id:drcga found; after it so both readers take id:haf6g's grammar at once
    > **Completed:** 2026-11-13 git:681e1ab

    - **Why:** id:bekxx gave the per-file runner one header grammar, read from the header only. Two other scripts that decide how to build and judge the same test files keep their own readers, which are the old lax ones. `scripts/test_zbuild_diff.sh`'s generated `worker.sh` matches `expected compile fail`, `expected exit N` and the rest anywhere in the file and ignores what it does not recognise. `scripts/test_interface_attrs.sh` uses `grep -q '^// expected compile fail'` and a `sed` for `expected exit`. So a header that the runner reads one way can be read another way by these two, and `AGENTS.md` ("Two implementations of one thing are tested against each other") means these gates must judge a test as its header says.
    - **Do (POSIX `sh`):**
      1. `scripts/test_zbuild_diff.sh`, `worker.sh`: replace the `awk` header reader with `. scripts/lib/test_runner.sh` (once, after `portability.sh`) and `tr_expectations "$f"` per file. The mapping: `T_KIND` `skip`, `compile_fail`, `compile_success` and `warning` are left out as today (`continue`); `run` uses `T_EXIT`, `T_FLAGS` and `T_LINK`; `malformed` prints `DIFF $f malformed header, line $T_MALFORMED`, so the gate fails on it as the runner does. Check that sourcing the library in the worker defines nothing the worker uses under another meaning (its variables are `T_*`, `TR_*` and `_tr*`).
      2. `scripts/test_interface_attrs.sh`: the same, for `expect_fail` (`T_KIND` is `compile_fail`) and `want` (`T_EXIT`); a malformed header is a `fail`.
      3. The scripts' header comments say they read headers with `tr_expectations`.
    - **Checks:**
      - C1: before the edit, `grep -c 'expected compile fail' scripts/test_zbuild_diff.sh scripts/test_interface_attrs.sh` (quote it); after, `rg -n 'tr_expectations' scripts/test_zbuild_diff.sh scripts/test_interface_attrs.sh` shows one call in each.
      - C2: the `zbuild-diff` gate's `OK`/`DIFF`/`SKIP` counts before and after the edit are equal (from `build/gates/zbuild-diff.log` of two `make test` runs, or `sh scripts/test_zbuild_diff.sh` twice); quote both.
      - C3: planted case. Copy a runnable test that `zbuild-diff` builds to a scratch name under `tests/` with its first line changed to `// expected exit banana`, run `sh scripts/test_zbuild_diff.sh`, and watch it report `DIFF <file> malformed header, line 1: // expected exit banana`; then delete the copy. Take-out: with step 1's `malformed` branch removed (a scratch edit), the same run reports the copy as `OK`; restore.
      - C4: `sh scripts/test_interface_attrs.sh` passes; quote its last line.
      - C5: scripts only, so no `make preflight-changed`. `make test` after the last edit; quote its `Total:` line.
    - **Completion (generalist, 2026-11-13, git:681e1ab):** `worker.sh` of `scripts/test_zbuild_diff.sh` sources `scripts/lib/test_runner.sh` and calls `tr_expectations`: `malformed` prints `DIFF $f malformed header, line N: TEXT`, `run` takes `T_EXIT`, `T_FLAGS`, `T_LINK`, every other kind is left out as before. `scripts/test_interface_attrs.sh` does the same (`expect_fail` is `T_KIND = compile_fail`, `want` is `T_EXIT`, malformed is a `fail`). Both header comments say so.
      - C1: before, `grep -c 'expected compile fail'` gave `scripts/test_interface_attrs.sh:2` and `scripts/test_zbuild_diff.sh:1`. After, `rg -n tr_expectations` shows the call at `test_zbuild_diff.sh:54` and `test_interface_attrs.sh:53` (each file also names it in its header comment).
      - C2: `sh scripts/test_zbuild_diff.sh` before and after: `[PASS] zbuild-diff: 591 of 594 programs agree between the whole-program build and the installed zbuild (1 skipped, 2 allowed to differ) in 11 s` both times.
      - C3: planted copy `tests/stdlib/zz_planted.zrl` (a runnable test with first line `// expected exit banana`): `[FAIL] zbuild-diff: 1 program(s) differ ...` and `DIFF tests/stdlib/zz_planted.zrl malformed header, line 1: // expected exit banana`. Take-out (`malformed) ;;`): `[PASS] zbuild-diff: 592 of 595 programs agree ...`, the copy counted as OK. Restored, copy deleted.
      - C4: `sh scripts/test_interface_attrs.sh` last line `[PASS] interface-attrs: attributes, visibility and unsafe survive a .zri; ... diagnosed as whole-program does`.
      - C5: `make test` after the last edit: `Total: 3274 run, 3274 passed, 0 failed, 94 skipped (119.9s)`. No `make preflight-changed` (scripts only).

- [x] +testinfra +stdlib +docs +AI-G @testinfra Z1i `wait_any`'s doc and spec line say when it returns ECHILD for a child it was not given id:rvn2w
    > **Created:** 2026-11-13
    > **Context:** found at check-in id:drcga (finding 4), settled by the reviewer for an `+AI-G` session
    > **Branch:** `testinfra`
    > **Depends:** id:drcga
    > **Placed:** after id:f6tfj, in the batch that fixes what check-in id:drcga found
    > **Completed:** 2026-11-13 git:09824a9

    - **Why:** after id:ppvzh, `wait_any`'s doc comment (`stdlib/proc.zrl`) and `doc/spec/standard_library.md` §4.4 say it returns ECHILD when a child it was not given "ends first". The review's probe shows more: while any child outside the slice has ended and is not reaped, `wait_any` returns ECHILD at once, even if that child ended before the call and a child in the slice is still running, and it does so on every call until that child's own handle waits for it. After that `wait_any` blocks for the slice as it should. (`try_wait_any` is not affected: it waits by pid.) The behaviour is the one id:ppvzh specified, so only the words change; an ambiguity in `doc/spec/` is a bug (`AGENTS.md`).
    - **Do:**
      1. `stdlib/proc.zrl`, `wait_any`'s comment: replace its last sentence with: "A child the call was not given is never reaped. While one of those has ended and is not yet reaped, the result is ECHILD, at once and on every call, even if a child in `children` is still running; wait for it with its own handle first. `try_wait_any` waits for each given child by pid, and is not affected."
      2. `doc/spec/standard_library.md` §4.4, the `wait_any` line: the same rule in one sentence, in place of "and `wait_any` returns ECHILD when such a child ends first".
      3. `make man-gen` (the man page follows the comment).
      4. The review's probe becomes a test: add to `tests/stdlib/test_proc_wait_any_own.zrl`, after its existing cases, a case where B (`/bin/true`, not in the slice) has ended (wait for `Z` as the file already does) while A (`sleep 1`, in the slice) still runs. `wait_any([A])` is an error twice in a row; after `b.wait()`, `wait_any([A])` returns A's index.
    - **Checks:**
      - C1: `./scripts/test.sh --verbose tests/stdlib/test_proc_wait_any_own.zrl`: `exit code: 0`; quote it.
      - C2: take-out. In a scratch edit make `wait_any` loop back to `waitid` instead of returning ECHILD after the second pass (it then spins, so run C1 under `timeout 10`); watch the new case fail or time out, quote it, restore.
      - C3: `make man-gen` and `sh scripts/test_man_pages.sh` pass; `scripts/check_safety_figures.sh --all` shows no FAIL (re-record the figures in the same commit if a comment line moved one).
      - C4: `grep -c proc.zrl build/closure.txt` prints `0`.
      - C5: `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, each `Total:` line quoted. The completion note says the fuzz record is stale.
    - **Completion (generalist, 2026-11-13, git:09824a9):** the doc comment of `wait_any` and `doc/spec/standard_library.md` §4.4 now say it, in the reviewer's words; the man page follows; `tests/stdlib/test_proc_wait_any_own.zrl` has the new case (a zombie B outside the slice, `sleep 2` A inside: `wait_any` errors with ECHILD twice, then returns index 0 after `b.wait()`).
      - C1: `timeout 60 ./scripts/test.sh --verbose tests/stdlib/test_proc_wait_any_own.zrl`: `[PASS] tests/stdlib/test_proc_wait_any_own.zrl (3142ms)`, `exit code: 0`.
      - C2: take-out (`wait_any` ends in `return wait_any(children);`): `[FAIL] tests/stdlib/test_proc_wait_any_own.zrl (wrong exit code) (423ms)`, `exit code: 139` (the recursion overflows the stack, which the older ECHILD case also hits first, so this shows the test fails, not that the new case alone does); restored.
      - C3: `make man-gen` wrote `doc/man/zoril-proc.3`; `[PASS] man-pages: all pages build cleanly and match tools and stdlib`; the comment added two lines, so `doc/SAFETY.md` §5.3 stdlib lines are 6,730 (the density row is unchanged, comment lines not counted); `check_safety_figures.sh --all` shows no FAIL.
      - C4: `grep -c proc.zrl build/closure.txt` prints `0`.
      - C5: `make test`: `Total: 3274 run, 3274 passed, 0 failed, 94 skipped (120.8s)`; `REJECT_DIFF_NO_CACHE=1 make preflight-changed`: rc 0, `0 newly accepted ... 0 newly refused, of 69145 programs`, `Total: 1195 run, 1195 passed, 0 failed, 0 skipped (44.8s)`. The fuzz record is stale (`stdlib/` changed). Host-specific `bench/` files deleted.

- [x] +testinfra +review +AI-D @testinfra @checkin Review of the Z2b6, Z2b7, Z2b8 and Z1i batch (EXPECT read from the compiler's output, two more malformed shapes, one header reader, the ECHILD rule in words) id:zmcty
    > **Created:** 2026-11-13
    > **Context:** placed by the reviewer at check-in id:drcga
    > **Branch:** `testinfra`
    > **Depends:** id:r85jb, id:haf6g, id:f6tfj, id:rvn2w
    > **Placed:** directly after the batch it reviews

    - **Review:**
      1. Re-run each take-out: id:r85jb C2, id:haf6g C2, id:f6tfj C3, id:rvn2w C2.
      2. Rerun the header survey, and write three malformed headers of the reviewer's own. Run each through `test.sh`, `test.sh --verbose`, `build/ztest` and the `zbuild-diff` worker, and check that all four agree.
      3. Record the findings here as numbered bullets, add follow-up tasks, then `tm validate` and `tm done` this task.
    - **Findings (the reviewer, 2026-11-13, `testinfra` at git:09824a9; scratch files under `build/zmcty/`, every scratch edit restored, `git status --short scripts stdlib tests` empty after):**
      1. The four commits (git:4ea969c, git:4075934, git:681e1ab, git:09824a9) match their tasks' **Do**, and each completion note answers every check.
      2. Take-outs rerun. id:r85jb C2 (`_tr_missing_expect` back on `$_log`): `[FAIL] expect_in_cmdline: expected ... (diagnostic missing)`, got `[PASS] ...`. id:haf6g C2 (the four new `bad()` calls taken out): `[FAIL] expect_and_exit` and `[FAIL] expect_and_success` (each got `diagnostic missing`), `[FAIL] skip_empty` (got `wrong exit code`), and no other `[FAIL]`. id:f6tfj C3, with a planted copy of `b_exit_then_expect.zrl` (below) as `tests/stdlib/zz_rev_b.zrl`: with the worker's `malformed` branch made `malformed) ;;`, `[PASS] zbuild-diff: 592 of 595 programs agree ...`; restored, `DIFF tests/stdlib/zz_rev_b.zrl malformed header, line 2: // EXPECT: x`.
      3. id:rvn2w C2 as written does not isolate the new case, as its note says. The new case (exits 10 to 14) has the older case's shape (5 to 8), plus a second ECHILD in a row. A take-out aimed at that: `wait_any` returns ECHILD once, then waits on its own slice (a `static mut` flag, and a `reap_listed` loop in place of the final `return`). `./scripts/test.sh --verbose tests/stdlib/test_proc_wait_any_own.zrl`: `[FAIL] ... (wrong exit code)`, `exit code: 11`. The older case still passed, and the new case caught it. Restored: `[PASS] tests/stdlib/test_proc_wait_any_own.zrl (3140ms)`.
      4. Headers of the reviewer's own, through `tr_expectations` and then, as planted copies under `tests/stdlib/`, through `./scripts/test.sh`, `./scripts/test.sh --verbose`, `build/ztest` and `sh scripts/test_zbuild_diff.sh`. All four agree on every file. `// expected exit 3` / `// EXPECT: x` / `// expected compile fail`: malformed at line 2 in all four. `// @skip:` with a tab after it: malformed at line 1 in all four. `//expected exit 3` with no space after `//` reads as `run`, exit 3, which is what it says. **Not caught (finding):** `// EXPECT: ` with nothing after it is accepted with no text. Beside `expected compile fail` it checks no diagnostic (`[PASS]` in all four); alone, on a program that returns 0, the file becomes a plain `run` test (`[PASS]`), though its header names a diagnostic. **Not caught (finding):** a directive after the header (`fn main() -> i32 { return 3; }` then `// expected exit 3`) is ignored, since the reader stops at the first line of code, and the file runs as `exit 0`. Neither shape is in the tree. The survey, over the 1,215 `*.zrl` of `tests/` and `corpus/` that are not `*_lib.zrl`, found no `// EXPECT:` with empty text and no line matching `^[ \t]*//[ \t]*(expected (exit|compile)|EXPECT:|@skip:|flags:|link:)` after a header. Both are id:vmg4z, below.
      5. Note, not a task: id:rvn2w's C5 quotes the differential's verdict line but not its `reject-diff: base verdicts: fresh (no cache)` line, as `AGENTS.md` asks. The run's log was not kept under `build/`. The change is a doc comment and a test, so no verdict could move. A cited preflight keeps its log (`> build/<task>/preflight.log 2>&1`) so that the line can be quoted.
      6. Batch outcome: nothing blocks. The next batch is id:vmg4z, ending at check-in id:at0d6. id:mrzb3 and id:z0123 (`+AI-D`, the reviewer's) follow it.

    > **Completed:** 2026-11-13 git:09824a9

- [ ] +testinfra +tests +AI-G @testinfra Z2b9 The header grammar refuses an empty `// EXPECT:` text and a directive line after the header id:vmg4z
    > **Created:** 2026-11-13
    > **Context:** found at check-in id:zmcty (finding 4), settled by the reviewer for an `+AI-G` session
    > **Branch:** `testinfra`
    > **Depends:** id:zmcty
    > **Placed:** directly after check-in id:zmcty, which found it

    - **Why:** two header shapes still make a test mean something other than it says (id:zmcty finding 4). `// EXPECT: ` with no text checks no diagnostic, and alone it turns the file into a plain `run` test. A directive after the first line of code is ignored, so the file runs with the default expectation. Neither is in the tree, so no test changes kind. The four readers (`test.sh`, `--verbose`, `ztest`, `zbuild-diff`, and also `test_interface_attrs.sh`) all use `tr_expectations`, so one edit covers them.
    - **Do (`scripts/lib/test_runner.sh`, the awk in `tr_expectations`, POSIX awk):**
      1. An `// EXPECT: ` line whose text, after the prefix, is empty or only blanks is malformed (`bad()`), at that line.
      2. The reader no longer stops at the first line that is neither blank nor a comment. It marks the header as ended there and reads on. After the header, a line matching `^[ \t]*\/\/[ \t]*(expected (exit|compile)|EXPECT:|@skip:|flags:|link:)` is malformed, at that line. No other line after the header is read as a directive, so a body comment such as `// expected output: none` is still allowed. Update the comment above the awk to say that directives after the header are refused, not ignored.
      3. `scripts/test_test_headers.sh` gains the malformed cases `expect_empty` (line 1 `// EXPECT: `, line 2 `// expected compile fail`, a program that fails to compile), `expect_empty_alone` (line 1 `// EXPECT: `, `fn main() -> i32 { return 0; }`) and `directive_after_code` (line 1 `fn main() -> i32 { return 3; }`, line 2 `// expected exit 3`), each expected as `[FAIL] ... (malformed header, line N: ...)` with N 1, 1 and 2. It also gains a control `body_comment` (line 1 `// expected exit 0`, then `fn main() -> i32 {`, `    // expected output: none`, `    return 0;`, `}`), which passes.
    - **Checks:**
      - C1: `sh scripts/test_test_headers.sh`: quote the four new lines and the last line.
      - C2: take-out. Remove step 1's rule and step 2's after-header rule (a scratch edit) and watch the three malformed cases fail; quote them, then restore.
      - C3: the survey, as id:haf6g C3 did it (`tr_expectations` over every `*.zrl` of `tests/` and `corpus/` that is not a `*_lib.zrl`): only `tests/runner/fixtures/tests/bad_header.zrl` is malformed; quote the output.
      - C4: `sh scripts/test_zbuild_diff.sh` prints the same `[PASS] zbuild-diff: 591 of 594 ...` line as before the edit, and `sh scripts/test_interface_attrs.sh` passes; quote both.
      - C5: scripts only, so no `make preflight-changed`. `make test` after the last edit; quote its `Total:` line, which has the same counts as before plus the new cases.

- [ ] +testinfra +review +AI-D @testinfra @checkin Review of Z2b9 (an empty EXPECT and a directive after the header are malformed) id:at0d6
    > **Created:** 2026-11-13
    > **Context:** placed by the reviewer at check-in id:zmcty
    > **Branch:** `testinfra`
    > **Depends:** id:vmg4z
    > **Placed:** directly after the task it reviews. id:mrzb3, the first task after it, depends on it.

    - **Review:**
      1. Re-run id:vmg4z C2's take-out.
      2. Run the five reviewer headers in `build/zmcty/h/` (if they are gone, those in id:zmcty finding 4) through the four readers: `a_empty_expect` and `e_empty_expect_alone` are now malformed at line 1, `d_directive_after_code` at line 2, and the others are unchanged.
      3. Write two headers of the reviewer's own that are near the after-header rule's edge (a directive-like comment inside a string literal, or one indented in a block), and check how they are read.
      4. Record the findings here, add follow-ups, `tm validate`, `tm done`.

- [ ] +testinfra +diagnosis +AI-D @testinfra Z3b Why the ZIR verifier spends about 2 ms on a `continue` from a match arm inside a loop id:mrzb3
    > **Created:** 2026-11-13
    > **Context:** found by id:z0184
    > **Branch:** `testinfra`
    > **Depends:** id:0f0vv, id:at0d6

    - **Why:** id:z0184's scratch timers (its **Measured** bullets) put the cost in `ZirVerifier.verify` (`src/driver/module.zrl`, `run_body_passes_in_scratch`): `fn with_continue` 2.2 ms, `fn without_continue` 0.18 ms, the same loop written two ways (`build/z184/bis3.zrl`, also in id:z0184's text). A `continue` in a plain `if` costs nothing measurable. id:87kcw removes the shape from `io.zrl`, but any user program with it pays the same, and `stdlib/bufio.zrl` (lines 124, 178, 319, 396) and `stdlib/file.zrl` (174) have `continue`s still to classify.
    - **Do:** find which check inside `ZirVerifier.verify` takes the time on this CFG shape (timers around each of its passes, as id:z0184's patch does for the driver's), and why: an iteration count, a per-block copy, a revisit per back edge. Record the cause, a reproducer and the figure here. A fix is a new task. A fix that would change which programs are accepted is out of scope here and goes to the maintainer.
    - **Checks:**
      - C1: the per-pass split of `verify` for `with_continue` and `without_continue`, with the patch recorded here.
      - C2: the cause, shown by a measurement (for example, an iteration count that grows with the shape), not by reading the code.
      - C3: the five `continue` sites in `bufio.zrl` and `file.zrl`, each with its verifier time.
      - C4: no file under `src/`, `stdlib/` or `scripts/` is changed (`git status --short` empty).

- [ ] +testinfra +measurement +AI-D @testinfra id:z0123 T9a Is a build and a test result the same from the same inputs?
    > **Created:** 2026-11-06
    > **Context:** split from id:z0113 by the review.
    > **Branch:** `testinfra`
    > **Depends:** id:mxt3d
    > **Before:** id:z0113.

    - **Do:** id:z0113's **Measure first** bullet: is `build/zoril` byte-identical when built from one commit in two checkouts (through stage1 and through `build/zoril`)? Do two `make test` runs on one tree give the same `--results` and the same output digests per item (list every item that differs, and why)? Record the commands and the answers here, and in id:z0113.

## Next

- [ ] +testinfra +decision +AI-D @testinfra id:z0113 T9 One verification record for the author and the reviewer: a result cache keyed by inputs
    > **Created:** 2026-11-06
    > **Branch:** `testinfra`
    > **Asked by:** the maintainer.
    > **Before:** id:z0112 (the review rule it changes), id:z0114.

    - **The stamp's record (the maintainer, 2026-11-07):** a cache keyed by inputs decides what not to run, as the unchanged-tree stamp did. The stamp needed four fixes (id:z0142, id:z0143, id:z0144, id:z0150) and was removed (id:z0154), because a defect in it reports a pass for code that was not tested. Before recommending a cache, say what in its design keeps it from failing the same ways (a key that misses an input, a record taken at the wrong moment, a lookup that depends on git), and how a reviewer sees a wrong hit.

    - **Now:** the check-in rule ("the model that wrote a fix does not close it") has the reviewer rerun everything itself, rightly: it does not take the author's word. So every safety task pays for `make test` and `make preflight-changed` twice on the same tree: about 4 min for each `make test`, and 13 to 15 min for each preflight with the differential. Having the author skip the suites would hand over unverified work, and a failed review costs more than a run.
    - **Idea:** a result is a function of its inputs, not of who ran it. Key each item (per-file test, probe, gate, scenario, differential program) by a hash of everything it reads: the test file and its imports, `build/zoril`, `build/zilc`, `build/zbuild`, the runtime objects, the toolchain fingerprint (`scripts/test_qbe_fingerprint.sh`'s), its flags, and the runner and gate scripts. Store the verdict and a digest of its output under `build/cache/`. Each side builds the compiler from the commit itself, so the reviewer computes every key independently. A key that matches means the same inputs, and the reviewer takes only the verdict from the cache.
    - **What keeps the reviewer honest:** in review mode (`REVIEW=1` or `make review`) the cache serves hits, but these items rerun in full: a random sample (10%, with its seed printed), every item whose inputs the change touched, every failure and skip, and the task's reproducers and sibling probes. A sampled item that disagrees with its cached verdict invalidates the whole cache, forces a full run, and is a finding: a nondeterministic test or a stale key.
    - **Decide:** the key's inputs for each item kind, and how an undeclared input is caught. A gate reads files a test file does not, so gates may need a list of their inputs, or stay uncached. Also decide where the cache lives, so a reviewer in another worktree or a cloud session can use it (a directory under `build/`, or an exported tarball of keys and verdicts), and how the completion note cites a run (tree hash, cache key set, sample seed).
    - **Measure first:** is `build/zoril` byte-identical when built from the same commit in two checkouts (the stage1 path and the `build/zoril` path)? Is the test output deterministic across runs? The static-image and repro gates already check part of this. If the builds are not identical, the key uses the compiler's source hash and the test proves that the source hash determines the binary. Then implementation tasks: the per-file cache, the reviewer sampling, the gate cache.
    - **Order (id:z0103, 2026-11-06):** after the tiers (id:z0115) and the differential's caches (id:z0114), which take most of the saving with fewer inputs to declare. Its implementation goes in the runner, if id:z0117 decides on one. Its keys and verdicts are kept as plain files under `build/` (the series rule), so a `sh` script and a Zoril runner can read the same cache.
    - **Review (2026-11-06):** the header's **Before:** id:z0112, id:z0114 is stale: by the bullet above and id:z0112's own order bullet, this task follows id:z0114 and id:z0115, and id:z0112 precedes it. The **Measure first** bullet is id:z0123, done first; this task decides from its answers.
    - **Order (review, 2026-11-11):** also after id:z0184. If the stdlib's share of each compile (about 85% of 14 ms) can be cut for every run, the saving left for a result cache shrinks, and this task weighs it against the record of the mechanisms that skip work (the stamp, the tiers, id:z0114's R4).

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
