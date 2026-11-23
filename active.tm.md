# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [x] +fuzz +safety +release +AI-D @main Renew the fuzz record (make fuzz-release) after the provenance and ZIL series id:v2f8h
    > **Created:** 2026-11-20
    > **Branch:** `main`
    > **Depends:** id:w3vde, id:0mbg3, id:mf9gq, id:rrgct, id:mskex, id:4ngz8, id:r1shp, id:rz4da
    > **Completed:** 2026-11-23 git:b8688c3

    - **Placed:** after the remaining `@zil` tasks (id:0mbg3) and the generator-debt tasks id:mskex, id:4ngz8 and id:r1shp, and before the release task (id:jtk00), per the maintainer's request (2026-11-20), so the renewed record covers the provenance route classes.
    - **Do:** on a clean `main` tree with `rustc` available, run the release-bar fuzz renewal (`make fuzz-release`, per `id:z0003` and `bench/fuzz/README.md`), triage any findings, update `bench/fuzz/README.md` with the renewed record and commit hashes, and verify `scripts/check_fuzz_fresh.sh` reports fresh for `src/`, `stdlib/`, `tools/zilc`, `tools/zbuild`, and `rt/`.
    - **Checks:** C1 `make fuzz-release` summary line quoted (0 faults, 0 unclassified candidates, 0 `knownblind`, all calibration rows in fixed state). C2 `sh scripts/check_fuzz_fresh.sh` reports fresh for all tracked components. C3 `make test-changed BASE=HEAD`, its `Total:` line quoted.
    - **Completion note:**
      - **C1 (`make fuzz-release`):** completed on `7400b3f` (`build/fuzz/release-20261122T012327Z/run.out`, 23h21m wall time, 104/104 features, 9,584,558 mode-diff builds with 0 disagreements): `fuzz-totals: progs=7056026 accepted=2528508 traps=39457 rejected=2465513 candidates=0 faults=0 inferdiff=6177 genbug=0 diffs=28087 expired=0 ran=2528508 mprogs=24 maccepted=0 mrej=21 mowning=13147646 mtotal=35534091 known=2062029 knownfault=0 knownfixed=24 knownskipped=1989943 knownblind=0 vchecked=5052233 vunchecked=239859 t134=32774 t136=6683 zbuilt=9584558 modediffs=0`. `make fuzz-calibrate`: `fuzz-calibrate: 26/26 calibration program(s) are in their fixed state (22 refused, 2 accepted with one drop)`. `./scripts/fuzz_safe.sh --reverify`: `fuzz: reverify - /home/esand/projects/22-public/zoril/bench/fuzz/findings holds no program; the record is empty`.
      - **C2 (`sh scripts/check_fuzz_fresh.sh --strict`):** `[PASS] fuzz-fresh: the release-bar record's fingerprint matches the code of src, stdlib, tools/zilc, tools/zbuild and rt in the working tree` and `[PASS] fuzz-fresh: every page that discusses the fuzz record quotes the release-bar record's 2,528,508 programs (1 page(s))`.
      - **C3 (`make test-changed BASE=HEAD`):** `Total: 1197 run, 1197 passed, 0 failed, 0 skipped (58.5s)`.

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
