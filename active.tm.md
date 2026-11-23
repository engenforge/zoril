# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [ ] +release +AI-D @main Prepare v0.2.0 release (version bump, changelog, docs, make test and make preflight) id:jtk00
    > **Created:** 2026-11-20
    > **Branch:** `main`
    > **Depends:** id:v2f8h

    - **Placed:** after the fuzz renewal (id:v2f8h), per the maintainer's request (2026-11-20); split on 2026-11-23 so dist tarballs and final release commit/tag live in id:bmkh4.
    - **Do:** prepare the `v0.2.0` release on `main`:
      1. Bump `VERSION` to `0.2.0` and update `CHANGELOG.md` (brief, high-level changes, <= 20 lines of text), `README.md`, `KNOWN_ISSUES.md`, `doc/SAFETY.md`, and other release-versioned docs for `v0.2.0` and the provenance/ZIL series.
      2. Run `make test` and the full `make preflight` gate on `main` (commit `bench/records` updates).
      3. Verify `sh scripts/check_fuzz_fresh.sh` reports fresh.
    - **Checks:** C1 `VERSION` is `0.2.0`, `CHANGELOG.md` entry is <= 20 lines, and release docs are updated. C2 `make test` passes, quoting `Total:`. C3 `make preflight` passes end to end, quoting each `Total:` line and the store-grid summary. C4 `sh scripts/check_fuzz_fresh.sh` reports fresh.

- [ ] +release +AI-D @main Cut v0.2.0 release: build/verify dist tarballs, final release commit, and tag id:bmkh4
    > **Created:** 2026-11-23
    > **Branch:** `main`
    > **Depends:** id:jtk00

    - **Placed:** directly after id:jtk00 (split from id:jtk00 per the maintainer's request on 2026-11-23).
    - **Do:** finalize and publish the `v0.2.0` release on `main` (maintainer):
      1. Make any final release commit if needed.
      2. Build and verify the release source/binary tarballs (`make dist`, unpack into an empty directory, build and run `make test` from the tarball with no `.git` and `git` off `PATH`).
      3. Tag `v0.2.0` and publish the release (never push tags from an agent session).
    - **Checks:** C1 `make dist` produces the release tarball, and building + running `make test` from the unpacked tarball (with no `.git` and `git` off `PATH`) passes, quoting `Total:`. C2 `v0.2.0` release tag created and published by the maintainer.
