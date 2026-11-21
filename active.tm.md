# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [x] +zil +safety +AI-G @zil ZL5b Propagate stack-pointer and borrows storage flow through ILInstr.SlicePtr in src/verify.zrl id:1dwwz
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:rvjcz
    > **Completed:** 2026-11-21 git:ad3b8c8

    - **Found by:** check-in `id:rvjcz` probing ZL5 (`id:egsdq`) sibling routes.
    - **Placed:** directly after `id:rvjcz` and before `id:0mbg3` (ZL6), so `src/verify.zrl` catches stack-pointer escapes through `slice_ptr` before ZL6 audits `zilc`'s remaining checks.
    - **Do:**
      1. In `src/verify.zrl`, move `ILInstr.SlicePtr(src)` out of the no-op arm in the storage-flow analysis (lines 720–721, removing both duplicate entries) and add `ILInstr.SlicePtr(src) => { from = src; },` beside `ILInstr.SliceConstruct(sc) => { from = sc.ptr; },` (line 638).
      2. In `src/verify.zrl`, move `ILInstr.SlicePtr(src)` out of the no-op arm in `verify_instr` (line 1652) and propagate `self.is_stack_slot[src] || self.points_to_stack[src]` to `self.points_to_stack[ssa]` beside `ILInstr.SliceConstruct` (line 1612), setting `OwnerState.Owned` on `ssa`.
      3. Add `tests/zilc/slice_ptr_stack_escape.zil` (returning `slice_ptr` of `slice_construct` over `alloc 'local`) with `// EXPECT: region escape: returning a pointer to local stack storage`, verified by `scripts/test_zilc_errors.sh`.
      4. Ensure returning `string_const` and `slice_ptr(string_const)` remain accepted by `zilc` (neither is a stack slot).
    - **Checks:**
      - C1 (before): run `timeout -k 5s 30s build/zilc tests/zilc/slice_ptr_stack_escape.zil -o /dev/null` before editing `src/verify.zrl` and quote exit code `0`.
      - C2 (after): rebuild `build/zoril` and `build/zilc`; `timeout -k 5s 30s build/zilc tests/zilc/slice_ptr_stack_escape.zil -o /dev/null` exits 1 with `region escape: returning a pointer to local stack storage`; `sh scripts/test_zilc_errors.sh` passes all checks.
      - C3 (control): a hand-written ZIL function returning `slice_ptr` of `string_const "hello"` still compiles with `build/zilc` (exit 0).
      - C4 (take-out): revert the `points_to_stack` propagation for `ILInstr.SlicePtr` in `src/verify.zrl`, rebuild `build/zilc`, and show `sh scripts/test_zilc_errors.sh` fails on `tests/zilc/slice_ptr_stack_escape.zil`; restore and rebuild.
      - C5: `make test` and `make preflight-changed` pass on `zil` (quoting `Total:` lines; note fuzz record is stale for `src/` and `tools/zilc/`).
      - Ends with `**Awaiting review:**` bullet for check-in `id:ks44a`.
    - **Completed note (2026-11-21):**
      - C1 (before): `timeout -k 5s 30s build/zilc tests/zilc/slice_ptr_stack_escape.zil -o /dev/null` exited `0`.
      - C2 (after): rebuilt `build/zoril` and `build/zilc`; `timeout -k 5s 30s build/zilc tests/zilc/slice_ptr_stack_escape.zil -o /dev/null` exited `1` with `tests/zilc/slice_ptr_stack_escape.zil:12:5: error: region escape: returning a pointer to local stack storage`; `sh scripts/test_zilc_errors.sh` passed all 18 checks.
      - C3 (control): hand-written ZIL returning `slice_ptr` of `string_const "hello"` compiled with `build/zilc` (`exit=0`).
      - C4 (take-out): reverted `points_to_stack` propagation for `ILInstr.SlicePtr` in `src/verify.zrl` and rebuilt `build/zilc`; `sh scripts/test_zilc_errors.sh` failed with `[FAIL] tests/zilc/slice_ptr_stack_escape.zil: expected a failure with: region escape: returning a pointer to local stack storage`; restored and rebuilt (`[PASS] tests/zilc/slice_ptr_stack_escape.zil`).
      - C5: `make test` passed (`Total: 4130 run, 4130 passed, 0 failed, 2 skipped (147.0s)`); `REJECT_DIFF_NO_CACHE=1 make preflight-changed` passed (`reject-diff: base verdicts: fresh (no cache); base front end 114 s`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69179 programs against 7c3b0071a628890b2812e9bbb51aaa79be938fb6`, `Total: 1562 run, 1562 passed, 0 failed, 0 skipped (108.1s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.1s)`). Fuzz record (`bench/fuzz/README.md`) is stale for `src/` and `tools/zilc/`.
    - **Awaiting review:** check-in `id:ks44a` — re-run `tests/zilc/slice_ptr_stack_escape.zil`, `sh scripts/test_zilc_errors.sh`, and probe sibling routes (`slice_ptr` through `phi`, `cast`, or stored into a global/out-param).

- [x] +zil +safety +review +AI-D @zil @checkin Check-in: review ZL5b SlicePtr verifier fix (1dwwz) id:ks44a
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:1dwwz
    > **Completed:** 2026-11-21 git:ad3b8c8

    - **Placed:** directly after `id:1dwwz` (`+safety` `+AI-G` fix) and before `id:0mbg3`, per `AGENTS.md` Check-ins.
    - **Review:** the steps of `AGENTS.md` Check-ins; re-run `id:1dwwz`'s numbered checks and probe sibling routes (e.g. `slice_ptr` through `phi`, `cast`, or stored into a global/out-param).
    - **Review findings (2026-11-21, commit `ad3b8c8`):**
      - Reviewed `git show ad3b8c8`: `ILInstr.SlicePtr(src)` now propagates storage flow (`from = src`) and `points_to_stack` in `src/verify.zrl` at parity with `ILInstr.SliceConstruct`, and the duplicate `ILInstr.SlicePtr(_)` arm is removed.
      - Re-ran checks: `timeout -k 5s 30s build/zilc tests/zilc/slice_ptr_stack_escape.zil -o /dev/null` exits `1` with `tests/zilc/slice_ptr_stack_escape.zil:12:5: error: region escape: returning a pointer to local stack storage`; `sh scripts/test_zilc_errors.sh` passes all 18 checks.
      - Probed sibling routes: `slice_ptr` of `string_const "hello"` returns cleanly (`exit=0`); `slice_ptr` through `cast` to `Ptr<u8, 'local>` is rejected (`exit=1`, `region escape: returning a pointer to local stack storage`).
      - Sibling routes accepted today (`exit=0`): `slice_ptr` through `phi`, through `struct_construct`, or stored into a `global_addr` / out-param — these are general `verify.zrl` scope limits (not specific to `SlicePtr`) and are audited in `id:0mbg3` (ZL6) directly following this check-in. No new tasks needed before ZL6.

- [ ] +zil +safety +audit +AI-D @zil ZL6 Which common mistakes in hand-written ZIL zilc can catch from what ZIL says id:0mbg3
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decision in id:ahd1c (`future.tm.md`)
    > **Branch:** `zil`
    > **Depends:** id:egsdq, id:rvjcz, id:1dwwz, id:ks44a

    - **Placed:** after ZL5, which gives zilc the ZIL verifier this task extends.

    - **Why:** ZIL is not checked for memory safety, but zilc should catch the mistakes that are easy to see in ZIL as designed and that happen most often (the maintainer, id:ahd1c).
    - **Do:** list candidate checks, each with a three-line ZIL program that shows the mistake, and say for each whether ZIL as written carries what the check needs. Candidates to start from: a value used after a `move` or `drop` in the same function, a `drop` twice, a `slice_load`/`slice_store` with no dominating `bounds_check` (spec §6.3), the address of an `alloc 'local` returned or stored into a global, a `slice_len` or `slice_ptr` on a value that is not a slice, a `syscall` with an argument count its stub does not take, and a block with no terminator. Corpus mistakes count as evidence of what is common: id:1kaye's string over-read is one. Rank them by how often they would fire and how simple they are, and split each chosen check into an `+AI-G` task with its own numbered **Checks:** and a take-out.
    - **Checks:** C1: every candidate has its program and its answer here, with the zilc output today (`timeout -k 5s 30s build/zilc <file>`). C2: the chosen checks are tasks, placed after this one, with a check-in after them.

- [ ] +tools +AI-G @main id:z0014 `zilc` refuses text it does not recognise between declarations, and a file that is not ZIL
    > **Created:** 2026-11-03
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, after id:0mbg3 (the `@zil` series), not before: ZL2 and ZL3 edit `tools/zilc/src/zil_parse.zrl` and the `corpus/zil/` files this task's checks run on, and a later edit of the same parser avoids a conflict.
    - **Now:** `zilc` exits 0 with no message on random bytes, and on `printf '\x01\x02 zz garbage\n'` it writes a stray global parsed out of the word `garbage`. `ZilParser.parse_module` (`tools/zilc/src/zil_parse.zrl`) dispatches on a declaration's first byte and skips any other byte, so text between declarations is dropped silently.
    - **Do:** at top level, after trivia, accept only the declaration forms of `doc/spec/intermediate_language.md` and report anything else as `zilc: line N: expected a declaration, found '<token>'` with exit 1; before parsing, refuse a NUL byte or invalid UTF-8 with one line. Keep the first-error behaviour.
    - **Checks:**
      - C1: before the change, `printf '\x01\x02 zz garbage\n' > build/z14/g.zil; timeout 10 build/zilc build/z14/g.zil -o build/z14/g.ssa; echo $?` and the `.ssa` it writes; quote both (exit 0 and a stray global today).
      - C2: one `tests/zilc/` case per refusal: a stray word between two functions, control bytes, a NUL byte, invalid UTF-8; each fails before the change (run the new tests against the old `build/zilc` and quote) and passes after.
      - C3: each refusal's message is the one in **Do** (`zilc: line N: expected a declaration, found '<token>'`, or the one-line NUL/UTF-8 refusal), with exit 1; quote each.
      - C4: every file in `corpus/zil/` still compiles and gives its expected exit (`./scripts/test.sh corpus/zil` or the scenario that runs them); quote its `Total:` line.
      - C5: take the top-level check out (a scratch edit) and watch the stray-word case pass silently again; restore.
      - C6: the `KNOWN_ISSUES.md` entry removed or updated; `make test` and `make preflight-changed`, each `Total:` line quoted; the completion note says the fuzz record is stale for `tools/zilc/`.

- [ ] +tools +AI-G @main id:z0016 `zbuild` builds a program written in ZIL, and refuses any other input with one line
    > **Created:** 2026-11-03
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, after id:z0014, in the `+AI-G` group before the fuzz renewal; it builds `.zil` files through the slice form ZL2 settles.
    - **Now:** `zbuild 01_arithmetic.zil` (from `corpus/zil/`) parses the ZIL as Zoril and prints about thirty `expected declaration` errors; the manual pipeline (`zilc`, `qbe`, `as`, `ld` with the runtime) works and exits 30.
    - **Do:** a root ending in `.zil` skips the module graph and the front end and runs `zilc`, `qbe`, `as` and the link with `zbuild`'s usual linker and runtime choice, honouring `-o` and the cache directory; `--checked` with a `.zil` root is refused with one line. A root ending in neither `.zrl` nor `.zil` is refused with one line naming both. Update `doc/man/zbuild.1.scd` (`make man`), `zbuild --help`, and "Starting from ZIL" in `doc/getting_started.md`.
    - **Checks:**
      - C1: before the change, `build/zbuild corpus/zil/01_arithmetic.zil -o build/z16/a; echo $?` and the first three error lines, quoted.
      - C2: after, the same builds and `build/z16/a; echo $?` prints 30; every file in `corpus/zil/` gives its expected exit code (a loop in a new scenario, or in `scripts/test_user_paths.sh` with the installed `zbuild`); quote the loop's summary.
      - C3: `-o` and the cache directory are honoured: the binary lands at the `-o` path, and a second build of the same `.zil` reuses the cache (the scenario checks the cache directory's contents).
      - C4: `zbuild foo.txt` and `zbuild --checked x.zil`: one line each, exit nonzero; quote both.
      - C5: take the `.zil` branch out (a scratch edit) and watch C2's scenario fail; restore.
      - C6: `doc/man/zbuild.1.scd` (`make man`), `zbuild --help` and "Starting from ZIL" in `doc/getting_started.md` updated; `sh scripts/test_man_pages.sh` passes; the doc snippet scenario (`./scripts/test.sh --scenario getting-started`) passes.
      - C7: the `KNOWN_ISSUES.md` entry removed or updated; `make test` and `make preflight-changed`, each `Total:` line quoted; the fuzz record is stale for `tools/zbuild/`.

- [ ] +fuzz +safety +AI-G @main Fuzzer generator: add indirect closure, fn-value forwarding, and mutual-recursion route builders id:mskex
    > **Created:** 2026-11-20
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, in the generator group before the fuzz renewal id:v2f8h, which depends on it.
    - **Placed:** before id:z0013 and the post-provenance fuzz renewal (id:a85sp item 3, generator debt).
    - **Do:** add compositional builders and feature tags to `scripts/fuzz/gen.lua` (with matching Rust twin emission) for: (1) closures capturing `&Holder` / `&&Holder` where `Holder` holds `&mut` (`gap_47`, `gap_48`); (2) a capturing closure passed to a `fn(...)` callee that invokes it (`gap_52`) or forwards a view through a closure parameter (`gap_55`); (3) mutually recursive helpers storing a view through a local (`gap_28`, `gap_54`).
    - **Checks:** C1 `lua scripts/fuzz/gen.lua --features` lists the new tags. C2 `make fuzz-short` runs cleanly with 0 `gen-bug`s and covers all new tags. C3 `make fuzz-calibrate` passes. C4 `make test-changed BASE=HEAD`, its `Total:` quoted.

- [ ] +fuzz +safety +AI-G @main Fuzzer generator: add release-tier liveness, inner-block callee store, and method-elision route builders id:4ngz8
    > **Created:** 2026-11-20
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, in the generator group before the fuzz renewal id:v2f8h, which depends on it.
    - **Placed:** before id:z0013 and the post-provenance fuzz renewal (id:a85sp item 3, generator debt).
    - **Do:** add compositional builders and feature tags to `scripts/fuzz/gen.lua` (with matching Rust twin emission) for: (1) release-tier liveness: a view stored through a local `&mut`, `&mut` parameter, `self`, `Box`, or two-callee `put`+`kill` followed by `free`/`reset` (`gap_37`–`gap_39`, `gap_43`, `gap_87`, `gap_96`, `425`–`428`); (2) a callee (direct or `fn` value) storing an inner-block local reference into an outer-block struct (`430`–`433`, `id:nhk9n`); (3) a `&self` method returning a view from another parameter followed by `reset` (`gap_44`, `gap_99`–`gap_101`).
    - **Checks:** C1 `lua scripts/fuzz/gen.lua --features` lists the new tags. C2 `make fuzz-short` runs cleanly with 0 `gen-bug`s and covers all new tags. C3 `make fuzz-calibrate` passes. C4 `make test-changed BASE=HEAD`, its `Total:` quoted.

- [ ] +fuzz +safety +AI-G @main Fuzzer generator: add container-of-views, extend_from_slice/Clone, and by-value aggregate route builders id:r1shp
    > **Created:** 2026-11-20
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, in the generator group before the fuzz renewal id:v2f8h, which depends on it.
    - **Placed:** before id:z0013 and the post-provenance fuzz renewal (id:a85sp item 3, generator debt).
    - **Do:** add compositional builders and feature tags to `scripts/fuzz/gen.lua` (with matching Rust twin emission) for: (1) `Vec::extend_from_slice` and `.clone()` copying views into an external container (`gap_56`, `gap_77`, `gap_78`, `gap_80`); (2) an owned `Vec` or struct holding frame views pushed or moved into a callee (`gap_59`–`gap_63`, `gap_79`); (3) a frame view read through a local reference to a local struct or passed in a by-value aggregate to a callee that stores it out (`gap_97`, `gap_98`).
    - **Checks:** C1 `lua scripts/fuzz/gen.lua --features` lists the new tags. C2 `make fuzz-short` runs cleanly with 0 `gen-bug`s and covers all new tags. C3 `make fuzz-calibrate` passes. C4 `make test-changed BASE=HEAD`, its `Total:` quoted.

- [ ] +review +AI-D @main @checkin Check-in: review the pre-renewal main +AI-G batch (z0014, z0016, mskex, 4ngz8, r1shp) id:rz4da
    > **Created:** 2026-11-21
    > **Branch:** `main`
    > **Depends:** id:z0014, id:z0016, id:mskex, id:4ngz8, id:r1shp

    - **Placed:** directly after id:r1shp, the last of the pre-renewal `@main` `+AI-G` batch, by the check-in id:3nrvs (`AGENTS.md`, Check-ins, step 3).
    - **Review:** the steps of `AGENTS.md` Check-ins; re-run each task's numbered checks and probe the sibling routes.

- [ ] +fuzz +safety +release +AI-D @main Renew the fuzz record (make fuzz-release) after the provenance and ZIL series id:v2f8h
    > **Created:** 2026-11-20
    > **Branch:** `main`
    > **Depends:** id:w3vde, id:0mbg3, id:mskex, id:4ngz8, id:r1shp, id:rz4da

    - **Placed:** after the remaining `@zil` tasks (id:0mbg3) and the generator-debt tasks id:mskex, id:4ngz8 and id:r1shp, and before the release task (id:jtk00), per the maintainer's request (2026-11-20), so the renewed record covers the provenance route classes.
    - **Do:** on a clean `main` tree with `rustc` available, run the release-bar fuzz renewal (`make fuzz-release`, per `id:z0003` and `bench/fuzz/README.md`), triage any findings, update `bench/fuzz/README.md` with the renewed record and commit hashes, and verify `scripts/check_fuzz_fresh.sh` reports fresh for `src/`, `stdlib/`, `tools/zilc`, `tools/zbuild`, and `rt/`.
    - **Checks:** C1 `make fuzz-release` summary line quoted (0 faults, 0 unclassified candidates, 0 `knownblind`, all calibration rows in fixed state). C2 `sh scripts/check_fuzz_fresh.sh` reports fresh for all tracked components. C3 `make test-changed BASE=HEAD`, its `Total:` line quoted.

- [ ] +release +AI-D @main Cut the new release (version bump, changelog, make preflight, tarballs, and tag) id:jtk00
    > **Created:** 2026-11-20
    > **Branch:** `main`
    > **Depends:** id:v2f8h

    - **Placed:** after the fuzz renewal (id:v2f8h), per the maintainer's request (2026-11-20).
    - **Do:** prepare and cut the next Zoril release on `main`:
      1. Bump the version, update `CHANGELOG.md`, `README.md`, `KNOWN_ISSUES.md`, and `doc/SAFETY.md` / release notes for the provenance and ZIL series.
      2. Run the full `make preflight` gate on `main` (and push `bench/records`).
      3. Build and verify the release source tarballs (`make dist`, unpack into an empty directory, build and run `make test` from the tarball with `git` off `PATH`).
      4. Maintainer tags and publishes the release (never push tags from an agent session).
    - **Checks:** C1 `make preflight` passes end to end, quoting each `Total:` line and the store-grid summary. C2 `make dist` produces the release tarball, and building + running `make test` from the unpacked tarball (with no `.git` and `git` off `PATH`) passes, quoting `Total:`. C3 `sh scripts/check_fuzz_fresh.sh` reports fresh. C4 release tag created by the maintainer.
