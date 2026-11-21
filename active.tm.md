# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [x] +zil +safety +AI-G @zil ZL6c Reject storing local stack pointers into globals and propagate points_to_stack through Phi in src/verify.zrl id:djynw
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:epx51
    > **Completed:** 2026-11-21 git:78690b9

    - **Placed:** after `id:epx51` (ZL6b), Rank 3 local stack-pointer escape checks in `src/verify.zrl`.
    - **Do:**
      1. In `src/verify.zrl`, add a per-function `is_global_addr: [mut bool]` array (allocated and zeroed beside `points_to_stack`). Set `is_global_addr[ssa] = true` on `ILInstr.GlobalAddr(_)`, and propagate it through `Cast`, `FieldAddr`, `Add`, `Move`, and `Borrow` (when the source has `is_global_addr`).
      2. In `src/verify.zrl` (`mark_store` / `ILInstr.Store(s)`): if `s.ptr < self.uses.len as u32 && self.is_global_addr[s.ptr as usize]` and `s.val < self.uses.len as u32 && (self.is_stack_slot[s.val as usize] || self.points_to_stack[s.val as usize])`, report `region escape: storing a pointer to local stack storage into a global`.
      3. In `src/verify.zrl` (`verify_instr` for `ILInstr.Phi(phi)`): if any predecessor `pr.val` has `is_stack_slot[pr.val] || points_to_stack[pr.val]`, set `points_to_stack[ssa] = true`.
      4. Add negative ZIL tests under `tests/zilc/` with `// EXPECT:` headers: `stack_escape_global.zil` and `stack_escape_phi.zil`.
      5. Ensure storing a `string_const` / `slice_ptr(string_const)` or heap pointer into a global remains accepted (control).
    - **Checks:**
      - C1 (before): run `timeout -k 5s 30s build/zilc <file> -o /dev/null` on `stack_escape_global.zil` and `stack_escape_phi.zil` before editing `src/verify.zrl`; quote exit code `0` for each.
      - C2 (after): rebuild `build/zoril` and `build/zilc`; `sh scripts/test_zilc_errors.sh` passes all checks including both new tests (quote both `[PASS]` lines).
      - C3 (control): a hand-written ZIL program storing `slice_ptr` of `string_const "ok"` into a global compiles with `build/zilc` (`exit=0`).
      - C4 (take-out): temporarily revert the `is_global_addr` store check in `src/verify.zrl`, rebuild `build/zilc`, and show `sh scripts/test_zilc_errors.sh` fails on `stack_escape_global.zil`; restore and rebuild.
      - C5: `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed` pass on `zil` (quote `Total:` lines and `reject-diff: base verdicts: fresh (no cache)`; note fuzz record is stale for `src/` and `tools/zilc/`).
      - Ends with `**Awaiting review:**` bullet for check-in `id:mf9gq`.
    - **Completion:**
      - Implemented in `src/verify.zrl` (`is_global_addr` allocated/zeroed beside `points_to_stack`, set on `GlobalAddr`, propagated through `Cast`/`FieldAddr`/`Add`/`Move`/`Borrow`, checked in `mark_store`, and `points_to_stack` propagated through `Phi` predecessors).
      - C1 (before): `for f in tests/zilc/stack_escape_global.zil tests/zilc/stack_escape_phi.zil; do timeout -k 5s 30s build/zilc "$f" -o /dev/null; echo "$f: exit=$?"; done` -> both exited `0`.
      - C2 (after): `sh scripts/test_zilc_errors.sh` -> `[PASS] tests/zilc/stack_escape_global.zil`, `[PASS] tests/zilc/stack_escape_phi.zil` (all 27 checks passed).
      - C3 (control): storing `slice_ptr` of `string_const "ok"` into a global compiled with `build/zilc` (`control exit=0`).
      - C4 (take-out): reverted `is_global_addr` store check in `src/verify.zrl`, rebuilt, `sh scripts/test_zilc_errors.sh` failed with `[FAIL] tests/zilc/stack_escape_global.zil: expected a failure with: region escape: storing a pointer to local stack storage into a global`; restored and rebuilt.
      - C5: `make test` (`build/zl6c_make_test.log`): `Total: 4130 run, 4130 passed, 0 failed, 2 skipped (148.2s)`. `REJECT_DIFF_NO_CACHE=1 make preflight-changed` (`build/zl6c_preflight.log`): `reject-diff: base verdicts: fresh (no cache); base front end 114 s`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69179 programs against 7c3b0071a628890b2812e9bbb51aaa79be938fb6`, `Total: 1562 run, 1562 passed, 0 failed, 0 skipped (108.0s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.3s)`. Fuzz record is stale for `src/` and `tools/zilc/`.
    - **Awaiting review:** check-in `id:mf9gq`.

- [ ] +zil +safety +AI-G @zil ZL6d Reject use-after-drop and double-drop in src/verify.zrl id:pkcsy
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:djynw

    - **Placed:** after `id:djynw` (ZL6c), Rank 4 `drop`-lifetime checks in `src/verify.zrl`.
    - **Do:**
      1. In `src/verify.zrl` (`verify_instr` for `ILInstr.Drop(ssa)`): before setting `OwnerState.Dropped`, check `self.current_map.get_state(ssa)`; if it is already `OwnerState.Dropped`, report `double drop: value was already dropped`.
      2. In `src/verify.zrl` (`check_ssa_access(ssa, span)` or on operand reads before `verify_instr`): if `self.current_map.get_state(ssa)` is `OwnerState.Dropped`, report `use after drop: value was already dropped` (avoid duplicate error when the instruction itself is `ILInstr.Drop(ssa)`, which reports `double drop`).
      3. Verify `ILInstr.Store` to a dropped stack slot still resets the slot to `OwnerState.Owned` in `mark_store`, and `corpus/zil/05_ownership_move.zil`, `06_ownership_drop.zil`, `13_slices.zil` still compile cleanly.
      4. Add negative ZIL tests under `tests/zilc/` with `// EXPECT:` headers: `use_after_drop.zil` and `double_drop.zil`.
    - **Checks:**
      - C1 (before): run `timeout -k 5s 30s build/zilc <file> -o /dev/null` on `use_after_drop.zil` and `double_drop.zil` before editing `src/verify.zrl`; quote exit code `0` for each.
      - C2 (after): rebuild `build/zoril` and `build/zilc`; `sh scripts/test_zilc_errors.sh` passes all checks including both new tests (quote both `[PASS]` lines).
      - C3 (control): `./scripts/test.sh corpus/zil` passes all 24 tests including `05_ownership_move.zil`, `06_ownership_drop.zil`, and `13_slices.zil` (quote `Total:`).
      - C4 (take-out): temporarily revert the `OwnerState.Dropped` check in `src/verify.zrl`, rebuild `build/zilc`, and show `sh scripts/test_zilc_errors.sh` fails on `use_after_drop.zil` and `double_drop.zil`; restore and rebuild.
      - C5: `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed` pass on `zil` (quote `Total:` lines and `reject-diff: base verdicts: fresh (no cache)`; note fuzz record is stale for `src/` and `tools/zilc/`).
      - Ends with `**Awaiting review:**` bullet for check-in `id:mf9gq`.
    - **Completion:**
      - Implemented in `src/verify.zrl` (`is_global_addr` allocated/zeroed beside `points_to_stack`, set on `GlobalAddr`, propagated through `Cast`/`FieldAddr`/`Add`/`Move`/`Borrow`, checked in `mark_store`, and `points_to_stack` propagated through `Phi` predecessors).
      - C1 (before): `for f in tests/zilc/stack_escape_global.zil tests/zilc/stack_escape_phi.zil; do timeout -k 5s 30s build/zilc "$f" -o /dev/null; echo "$f: exit=$?"; done` -> both exited `0`.
      - C2 (after): `sh scripts/test_zilc_errors.sh` -> `[PASS] tests/zilc/stack_escape_global.zil`, `[PASS] tests/zilc/stack_escape_phi.zil` (all 27 checks passed).
      - C3 (control): storing `slice_ptr` of `string_const "ok"` into a global compiled with `build/zilc` (`control exit=0`).
      - C4 (take-out): reverted `is_global_addr` store check in `src/verify.zrl`, rebuilt, `sh scripts/test_zilc_errors.sh` failed with `[FAIL] tests/zilc/stack_escape_global.zil: expected a failure with: region escape: storing a pointer to local stack storage into a global`; restored and rebuilt.
      - C5: `make test` (`build/zl6c_make_test.log`): `Total: 4130 run, 4130 passed, 0 failed, 2 skipped (148.2s)`. `REJECT_DIFF_NO_CACHE=1 make preflight-changed` (`build/zl6c_preflight.log`): `reject-diff: base verdicts: fresh (no cache); base front end 114 s`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69179 programs against 7c3b0071a628890b2812e9bbb51aaa79be938fb6`, `Total: 1562 run, 1562 passed, 0 failed, 0 skipped (108.0s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.3s)`. Fuzz record is stale for `src/` and `tools/zilc/`.
    - **Awaiting review:** check-in `id:mf9gq`.

- [ ] +zil +safety +review +AI-D @zil @checkin Check-in: review ZL6 common-mistake checks (0r49n, epx51, djynw, pkcsy) id:mf9gq
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:0r49n, id:epx51, id:djynw, id:pkcsy

    - **Placed:** directly after `id:pkcsy` (ZL6d), the last of the ZL6 `+AI-G` batch, per `AGENTS.md` Check-ins.
    - **Review:** the steps of `AGENTS.md` Check-ins; re-run each task's numbered checks and probe sibling routes (e.g. `slice_load`/`slice_store` on non-slice, variadic call arity, `variant_match` undefined target, `alloc 'local` stored into global field via `field_addr`, `drop` in one branch vs sibling branch).

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
    > **Depends:** id:w3vde, id:0mbg3, id:mf9gq, id:mskex, id:4ngz8, id:r1shp, id:rz4da

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
