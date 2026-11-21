# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [x] +tools +AI-G @main id:z0016 `zbuild` builds a program written in ZIL, and refuses any other input with one line
    > **Created:** 2026-11-03
    > **Branch:** `main`
    > **Depends:** id:z0014
    > **Completed:** 2026-11-21 git:4959869

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
    - **Completed note:** added `str_ends_with` in `tools/zbuild/src/util.zrl`, `.zrl`/`.zil` validation and `--checked` refusal for `.zil` in `tools/zbuild/src/main.zrl`, and `.zil` direct `zilc -> qbe -> as -> link` caching in `tools/zbuild/src/build.zrl`; added `scripts/test_zbuild_zil.sh` (`zbuild-zil` scenario in `scripts/test_plan.tsv` and `scripts/test_tiers.tsv`). C1: before the change, `build/zbuild corpus/zil/01_arithmetic.zil -o build/z16/a` exited 1 with `/home/esand/projects/22-public/zoril/corpus/zil/01_arithmetic.zil:4:1: error: expected declaration (fn, struct, enum, etc.)` (and `:4:3:`, `:4:5:`). C2: `build/zbuild corpus/zil/01_arithmetic.zil --cache-dir build/z16/c -o build/z16/a` printed `compiled: 1 modules` and `build/z16/a` exited `30`; `sh scripts/test_zbuild_zil.sh` printed `[PASS] corpus/zil via zbuild: 24/24 passed`. C3: `scripts/test_zbuild_zil.sh` verified `-o` path creation, `manifest.tsv` in `--cache-dir`, and `compiled: 0 modules` on second build (`[PASS] -o and cache reuse (compiled: 0 modules)`). C4: `build/zbuild foo.txt` printed `error: entry file must end in .zrl or .zil` (`exit=1`); `build/zbuild --checked x.zil` printed `error: --checked is not supported for .zil inputs` (`exit=1`). C5: scratch-removing `is_zil` from `main.zrl` caused `./scripts/test.sh --scenario zbuild-zil` to fail (`[FAIL] scenario: zbuild-zil (exit 1)`), restored. C6: updated `tools/zbuild/src/options.zrl` (`--help`), `doc/man/zbuild.1.scd` (`make man` wrote `doc/man/zbuild.1`), and `doc/getting_started.md`; `sh scripts/test_man_pages.sh` printed `[PASS] man-pages: all pages build cleanly and match tools and stdlib`; `./scripts/test.sh --scenario getting-started` passed (`Total: 2 run, 2 passed, 0 failed, 0 skipped (0.7s)`). C7: `KNOWN_ISSUES.md` entry removed; `make test` exited 0 (`Total: 4131 run, 4131 passed, 0 failed, 2 skipped (146.0s)`); `make preflight-changed` exited 0 (`Total: 1563 run, 1563 passed, 0 failed, 0 skipped (111.1s)` checked, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.1s)` git scenarios); the fuzz record is stale for `tools/zbuild/`.

- [ ] +review +AI-D @main @checkin Check-in: review the pre-renewal main +AI-G batch (z0014, z0016, mskex, 4ngz8, r1shp) id:rz4da
    > **Created:** 2026-11-21
    > **Branch:** `main`
    > **Depends:** id:z0014, id:z0016, id:mskex, id:4ngz8, id:r1shp

    - **Placed:** directly after id:z0016, the last of the pre-renewal `@main` `+AI-G` batch, by the check-in id:3nrvs (`AGENTS.md`, Check-ins, step 3).
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
