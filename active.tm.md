# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [x] +zil +safety +review +AI-D @zil @checkin Check-in: review ZL6 common-mistake checks (0r49n, epx51, djynw, pkcsy) id:mf9gq
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:0r49n, id:epx51, id:djynw, id:pkcsy
    > **Completed:** 2026-11-21 git:e8ff7c5

    - **Placed:** directly after `id:pkcsy` (ZL6d), the last of the ZL6 `+AI-G` batch, per `AGENTS.md` Check-ins.
    - **Review:** the steps of `AGENTS.md` Check-ins; re-run each task's numbered checks and probe sibling routes (e.g. `slice_load`/`slice_store` on non-slice, variadic call arity, `variant_match` undefined target, `alloc 'local` stored into global field via `field_addr`, `drop` in one branch vs sibling branch).
    - **Review findings (2026-11-21, commits `90862da`, `48a1568`, `78690b9`, `e8ff7c5`):**
      - Re-ran checks: `sh scripts/test_zilc_errors.sh` passed all 29 checks; `./scripts/test.sh corpus/zil` passed (`Total: 25 run, 25 passed, 0 failed, 0 skipped (0.2s)`).
      - **ZL6a (`id:0r49n`, `90862da`) — PASS:** reviewed diff (including `src/lower_zir_to_zil.zrl` emitting `SlicePtr` instead of `Load` on `ILTYPE_SLICE` casts). Probed sibling routes: `slice_load` and `slice_store` on `i64` rejected (`rc=1`), `load` on `Slice<u8, 'local>` rejected (`rc=1`), `syscall` with 6 args accepted (`rc=0`) and 7 args rejected (`rc=1`), non-variadic `call` with 3 args for 2 params rejected (`rc=1`), variadic `call` with 0 args for 1 fixed param rejected (`rc=1`), variadic `call` with 1 or 2 args accepted (`rc=0`).
      - **ZL6b (`id:epx51`, `48a1568`) — PASS:** reviewed diff; confirmed `VariantMatchInstr` in `src/il_instr.zrl:226` has no block targets. Probed sibling routes: empty block `@b0:` rejected (`rc=1`, `block ends without a terminator`), `branch` with undefined `then_block` or undefined `else_block` rejected (`rc=1`, `branch/jump target names no defined block`), `unreachable` terminator accepted (`rc=0`).
      - **ZL6c (`id:djynw`, `78690b9`) — PASS with sibling gaps:** probed `alloc 'local` stored into global via `field_addr`, `cast`, `add`, `slice_construct`, and `phi(borrow(alloc 'local))` — all rejected (`rc=1`, `region escape: storing a pointer to local stack storage into a global`). **Sibling gaps found:** `is_global_addr` is not propagated through `ILInstr.Phi` (`phi [@b1: v2_global, @b2: v3_global]; store v4, v1_local` exited `0`) or `ILInstr.RegionCast` (`region_cast 'local, v2_global; store v3, v1_local` exited `0`). Added to follow-up `id:4d7m6` (ZL6e).
      - **ZL6d (`id:pkcsy`, `e8ff7c5`) — TWO DEFECTS FOUND (follow-up `id:4d7m6` ZL6e):**
        1. **False positive on valid CFG sibling branches:** `src/verify.zrl` mutates a single linear `self.current_map` across blocks in block-list order (it does not clone `current_map` across branches). Probing `branch v0, @b1, @b2` with `drop v1` in `@b1` and `drop v1` (or `load v1; drop v1`) in mutually exclusive `@b2` falsely fails (`rc=1`, `double drop` / `use after drop`). Meanwhile `call`/`borrow`/`ret` after drop and `drop` of an outer `BoxMut` inside a loop are rejected (`rc=1`), and `alloc 'heap` + `drop` inside a loop body passes (`rc=0`).
        2. **False negative on `store` through dropped non-stack pointer:** `check_instr_operands` skipped `is_state_dropped` for all `ILInstr.Store(s)` pointers (and `mark_store` unconditionally resets `base` to `OwnerState.Owned`), so `v1: BoxMut<i32> = alloc 'heap, i32; drop v1; store v1, v2; load v1; drop v1` is silently accepted (`rc=0`). Only stack slots (`is_stack_slot[s.ptr]`) should allow reinitialization via `store`; storing through a dropped heap pointer must report `use after drop`.
        3. **Cleanup:** `is_state_owned` (`src/verify.zrl:233`) has no remaining callers after `dec_use` dropped its implicit `OwnerState.Dropped` transition; remove in `id:4d7m6`.
      - **Bookkeeping note:** in `doc/tasks/completed.tm.md`, `id:epx51` and `id:pkcsy` each carried a duplicated `Completion:` block from the preceding task (already swept; noted here).
      - **Plan update:** added `id:4d7m6` (ZL6e, `+AI-G`, `@zil`) and follow-up check-in `id:rrgct` (`+AI-D`, `@zil`, `@checkin`) directly below, and added `id:rrgct` to `id:v2f8h`'s `Depends:`.

- [ ] +zil +safety +AI-G @zil ZL6e Make drop tracking CFG-aware, reject store-after-drop on non-stack pointers, and propagate is_global_addr through Phi/RegionCast in src/verify.zrl id:4d7m6
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:mf9gq

    - **Placed:** directly after check-in `id:mf9gq`, fixing the two ZL6d defects and two ZL6c sibling gaps found during the ZL6 review.
    - **Do:**
      1. **CFG-aware drop tracking in `src/verify.zrl`:** during the `count_uses` scan in `verify_function`, record `has_drop: bool` (whether any instruction in `func` is `ILInstr.Drop(_)`); when `has_drop == false` (all Zoril-compiled functions), skip per-block drop snapshots for zero extra overhead. Add a per-function `is_dropped: [mut bool]` array (allocated/zeroed in `reset_ssa_tables` beside `is_global_addr`). When `has_drop == true`, allocate `block_dropped_out` (`func.blocks_len * ssa_count` bools, zeroed) and `block_visited` (`func.blocks_len` bools, zeroed); before each `check_block(block_ids[i])` call (both Pass 1 and Pass 2 `in_loop` blocks), clear `self.is_dropped[0..ssa_count]` to `false`, then for every block index `p` with `block_visited[p] == true` whose terminator (`ILInstr.Jmp(t)` or `ILInstr.Branch(br)`) targets `block_ids[i]`, OR `block_dropped_out[p * ssa_count + k]` into `self.is_dropped[k]`; after `check_block`, copy `self.is_dropped[0..ssa_count]` into `block_dropped_out[i * ssa_count .. (i + 1) * ssa_count]` and set `block_visited[i] = true`. In `check_instr`, whenever an instruction defines a result SSA (`self.has_result(ssa) && ssa < self.uses.len as u32`), clear `self.is_dropped[ssa as usize] = false`; on `ILInstr.Drop(ssa)`, check `self.is_dropped[ssa as usize]` for `double drop: value was already dropped` and set `self.is_dropped[ssa as usize] = true`; in `check_ssa_access`, check `self.is_dropped[ssa as usize]` for `use after drop: value was already dropped`.
      2. **Reject `store` through dropped non-stack pointer in `src/verify.zrl`:** in `check_instr_operands` for `ILInstr.Store(s)`, when `self.check_ssa_defined(s.ptr, span)` is true, if `s.ptr < self.uses.len as u32 && !self.is_stack_slot[s.ptr as usize] && self.is_dropped[s.ptr as usize]`, report `use after drop: value was already dropped` (still calling `self.dec_use(s.ptr)`). In `mark_store`, only clear `self.is_dropped[base as usize] = false` (and reset `OwnerState.Owned`) when `self.is_stack_slot[base as usize]` or `!self.is_dropped[base as usize]`, so storing through a dropped heap `BoxMut` does not revive it.
      3. **Propagate `is_global_addr` through `ILInstr.Phi` and `ILInstr.RegionCast` (and `points_to_stack` through `ILInstr.RegionCast`) in `src/verify.zrl`:** in `ILInstr.Phi(phi)`, if any `pr.val < self.uses.len as u32 && self.is_global_addr[pr.val as usize]`, set `self.is_global_addr[ssa as usize] = true`. Move `ILInstr.RegionCast(rc)` out of the default arm in `check_instr`, set `OwnerState.Owned`, propagate `points_to_stack` from `is_stack_slot[rc.val] || points_to_stack[rc.val]`, and propagate `is_global_addr` from `is_global_addr[rc.val]`.
      4. **Dead-code cleanup:** remove unused `is_state_owned` (`src/verify.zrl:233`).
      5. **Tests:** add negative ZIL tests under `tests/zilc/` (`store_after_drop_heap.zil`, `drop_join_use_after_drop.zil`, `stack_escape_global_phi.zil`, `stack_escape_global_region_cast.zil`) and verify the positive sibling-branch drop control (`drop v1` in `@b1`, `load v1; drop v1` in `@b2`) compiles with `build/zilc` exit `0`.
    - **Checks:**
      - C1 (before): run `timeout -k 5s 30s build/zilc <file> -o /dev/null` on `store_after_drop_heap.zil`, `stack_escape_global_phi.zil`, and `stack_escape_global_region_cast.zil` (all exit `0` today), and on the sibling-branch drop control (exits `1` today with `use after drop` / `double drop`); quote all four outputs.
      - C2 (after): rebuild `build/zoril` and `build/zilc`; `sh scripts/test_zilc_errors.sh` passes all checks including the 4 new negative tests (quote their `[PASS]` lines).
      - C3 (controls): sibling-branch drop (`@b1: drop v1`, `@b2: load v1; drop v1`) compiles with `exit=0`; `alloc 'heap` + `drop` inside a loop compiles with `exit=0`; outer `alloc 'heap` dropped inside a loop is rejected (`double drop`, `exit=1`); `./scripts/test.sh corpus/zil` passes all 24 tests (quote `Total:`).
      - C4 (take-out): temporarily revert the `ILInstr.Store` non-stack dropped check in `src/verify.zrl`, rebuild `build/zilc`, and show `sh scripts/test_zilc_errors.sh` fails on `store_after_drop_heap.zil`; restore and rebuild.
      - C5: `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed` pass on `zil` (quote `Total:` lines and `reject-diff: base verdicts: fresh (no cache)`; note fuzz record is stale for `src/` and `tools/zilc/`).
      - Ends with `**Awaiting review:**` bullet for check-in `id:rrgct`.

- [ ] +zil +safety +review +AI-D @zil @checkin Check-in: review ZL6e drop CFG-awareness, store-after-drop, and global_addr Phi/RegionCast fixes (4d7m6) id:rrgct
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:4d7m6

    - **Placed:** directly after `id:4d7m6` (ZL6e), per `AGENTS.md` Check-ins.
    - **Review:** the steps of `AGENTS.md` Check-ins; re-run `id:4d7m6`'s numbered checks and probe sibling routes (e.g. stack-slot reinit after drop `alloc 'local; drop; store; load`, nested diamond drop, `region_cast` of `alloc 'local` returned directly).

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
    > **Depends:** id:w3vde, id:0mbg3, id:mf9gq, id:rrgct, id:mskex, id:4ngz8, id:r1shp, id:rz4da

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
