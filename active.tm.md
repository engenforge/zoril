# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [x] +review +AI-D @main @checkin Check-in: review the pre-renewal main +AI-G batch (z0014, z0016, mskex, 4ngz8, r1shp) id:rz4da
    > **Created:** 2026-11-21
    > **Branch:** `main`
    > **Depends:** id:z0014, id:z0016, id:mskex, id:4ngz8, id:r1shp
    > **Completed:** 2026-11-22 git:4959869

    - **Placed:** directly after id:z0016, the last of the pre-renewal `@main` `+AI-G` batch, by the check-in id:3nrvs (`AGENTS.md`, Check-ins, step 3).
    - **Review:** the steps of `AGENTS.md` Check-ins; re-run each task's numbered checks and probe the sibling routes.
    - **Review recorded (2026-11-22, git:4959869):**
      1. **Queue and commits read:** reviewed `git show 835f299 53c8c67 5341f26 54077fa 4959869` (`id:mskex`, `id:4ngz8`, `id:r1shp`, `id:z0014`, `id:z0016`). No new tasks were added by the batch.
      2. **Re-ran batch checks and gates:** `lua scripts/fuzz/gen.lua --features` lists all 10 new generator tags; `make fuzz-calibrate` passed (`fuzz-calibrate: 26/26 calibration program(s) are in their fixed state (22 refused, 2 accepted with one drop)`); `make fuzz-short` passed (`fuzz-totals: progs=126 accepted=28 traps=0 rejected=61 candidates=0 faults=0 inferdiff=0 genbug=0 diffs=2 expired=0 ran=28 mprogs=24 maccepted=0 mrej=21 mowning=190 mtotal=464 known=61 knownfault=0 knownfixed=24 knownskipped=35 knownblind=0 vchecked=70 vunchecked=4 t134=0 t136=0 zbuilt=178 modediffs=0`, `fuzz: coverage 103/104 features`, all 10 new tags covered); `sh scripts/test_zilc_errors.sh` passed all 33 `tests/zilc/*.zil` + 4 CLI checks; `./scripts/test.sh corpus/zil` passed (`Total: 25 run, 25 passed, 0 failed, 0 skipped (0.2s)`); `sh scripts/test_zbuild_zil.sh` passed (`[PASS] corpus/zil via zbuild: 24/24 passed`, `[PASS] -o and cache reuse (compiled: 0 modules)`, `[PASS] refusals: foo.txt and --checked x.zil`); `sh scripts/test_man_pages.sh` passed (`[PASS] man-pages: all pages build cleanly and match tools and stdlib`); `./scripts/test.sh --scenario getting-started` passed (`Total: 2 run, 2 passed, 0 failed, 0 skipped (0.8s)`).
      3. **Sibling probes (`build/rz4da_probes/`):** `id:z0014` (`54077fa`): probed valid multi-byte UTF-8 in comments (`// café € 😀`, `rc=0`), overlong UTF-8 (`\xc0\xaf`, `rc=1`), UTF-16 surrogate (`\xed\xa0\x80`, `rc=1`), above-max codepoint (`\xf4\x90\x80\x80`, `rc=1`), truncated UTF-8 (`\xe2\x82`, `rc=1`), NUL in comment (`rc=1`), non-ASCII top-level (`é` -> `expected a declaration, found '\xc3'`), `module foo; garbage` (`rc=1`), `type garbage` (`rc=1`), `f0foo` (`rc=1`) — all behave as specified; found a sibling route where malformed declarations starting with a valid keyword (`local garbage`, `extern garbage`, `export garbage`, `f0 garbage`, `global garbage`, `const garbage`) exit `0` silently because `parse_function` / `parse_global` bail out without error after `parse_module` dispatches (filed `id:rzqcc` in `future.tm.md`). `id:z0016` (`4959869`): probed no-extension (`foo`), `.zrl.bak`, missing `.zil`, invalid `.zil` syntax (propagates `zilc` error), cache invalidation on `.zil` content edit (`exit=30` -> `exit=40`, `compiled: 1 modules`), default output path (`a.out`), and `--gc` with no entry file — all behave cleanly. Minor comment hygiene note (non-blocking): `scripts/fuzz/gen.lua` lines 94, 97, 99 mention task IDs in comments (`(id:mskex)`, `(id:4ngz8)`, `(id:r1shp)`).
      4. **Plan edits:** added follow-up `id:rzqcc` in `future.tm.md`. No further `@checkin` needed because the remaining open tasks (`id:v2f8h`, `id:jtk00`) are both `+AI-D`. No tasks moved, re-tagged, or re-prioritized.

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
