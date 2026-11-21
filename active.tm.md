# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [ ] +zil +decision +AI-D @zil ZL1 Settle the slice form of string_const and the slice_ptr opcode, and check what the pinned stage1 feeds zilc id:m6vm3
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)

    - **Placed:** after the provenance series (`id:z0017`), before ZL2 to ZL6. Nothing in `testinfra` depends on it. ZL4 changes the per-file runner, which `testinfra` rewrites (id:z0139).

    - **Depends changed (2026-11-17, a review of the task list, the maintainer's request):** removed id:z0017. It stated the order (this series after the provenance series), which the task's position states already; nothing in ZL1 to ZL6 needs a provenance task's result, and the series is on a branch of its own off `main`. `tm next` still offers the provenance tasks first; `tm next @zil` now offers this task, so a second session can take the series while the provenance series runs, if the maintainer wants that. To hold it back instead, restore the line.
    - **Why:** `string_const` is to give a `Slice<u8, 'local>` everywhere, as the spec says (id:1kaye, decision 1). Hand-written ZIL then needs `slice_ptr` to get the data pointer back.
    - **Decide, and write into ZL2 to ZL5 as their **Do:** and numbered **Checks:**:** (a) What a slice-typed `string_const` lowers to in zilc's QBE output: a static `{ptr, len}` pair beside the bytes, whose address is the value, or another layout. It must match how the front end's slice slots are laid out (pointer at offset 0, `usize` length at 8, today's `v5` slot in `--emit-zil`). (b) How the front end uses it: copy the pair into the slot, or use the value directly. (c) `slice_ptr`'s syntax, typing and spec entry beside `slice_len` (`doc/spec/intermediate_language.md` §5), and whether the front end's cast-and-load idiom is replaced by it. (d) What the pinned stage1 feeds to which zilc: does any path pass ZIL written by `bootstrap/stage1/` to the new `build/zilc`, `zilc-boot` included? If one does, the new zilc must also accept the old form until a re-pin, which is the maintainer's. (e) Which recorded figures change (`corpus/zrl_whole_program_zil.sha256`, the safety figures) and how each is recomputed.
    - **Also place:** the statement, decided in id:ahd1c, that ZIL is not checked for memory safety (`doc/spec/intermediate_language.md` and `doc/spec/safety_model.md`: the claims cover programs compiled from Zoril source, and zilc catches the common mistakes listed by ZL6). Put it into one of ZL2 to ZL5, or into a task of its own.
    - **Checks:** C1: each of (a) to (e) answered here, with the command that showed it for (d). C2: ZL2 to ZL5 each have a **Do:** and numbered **Checks:**, with a take-out check.

- [ ] +zil +AI-G @zil ZL2 string_const gives a Slice in the front end and in zilc, read back with slice_ptr id:qpc8d
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:m6vm3

    - **Placed:** after ZL1, which settles it.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope: the front end emits the slice form, zilc lowers it, the type check and `src/verify.zrl` type it, `slice_ptr` is added, the spec matches, and `corpus/zil/15_io_syscall.zil` and `19_fd_io.zil` are rewritten to print exactly their strings.

- [ ] +zil +AI-G @zil ZL3 One spelling for cast: zilc refuses bitcast and the corpus is rewritten id:htrqb
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:qpc8d

    - **Placed:** after ZL2: the corpus files it rewrites are the ones ZL2 changes.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope: `tools/zilc/src/zil_parse.zrl` refuses `bitcast` with a diagnostic that names `cast`, and the six corpus files that use it (`02_comparison`, `12_enums_sum`, `13_slices`, `15_io_syscall`, `19_fd_io`, `24_tuples`) use `cast`. The spec's line 92 stays true.

- [ ] +zil +tests +AI-G @zil ZL4 Corpus and per-file tests check the program's output, not only its exit code id:ehh6m
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:htrqb

    - **Placed:** after ZL3.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope (decision 3): a per-file test can state its expected output (a header directive or a sibling file, chosen in ZL1, read by the one header reader, `tr_expectations`, or by its replacement in `ztest`). Every `corpus/zil/` program and every corpus program that prints states its output. A check plants the 4 KB over-read of id:1kaye and shows that the test fails.

- [ ] +zil +safety +AI-G @zil ZL5 zilc runs the ZIL verifier that the compiler runs id:egsdq
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:ehh6m

    - **Placed:** after ZL4, last in the series. A check-in follows it, added by ZL1 with the series' other check-ins.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope (decision 4, the small step): zilc runs `src/verify.zrl` on what it parses, as the compiler does after lowering, so hand-written ZIL gets the same ZIL-level checks (stack-address escape, constant arena allocations) that compiled programs get. Not a borrow checker; that question is id:ahd1c.

- [ ] +zil +review +AI-D @zil @checkin Check-in: review the ZIL +AI-G batch (qpc8d, htrqb, ehh6m, egsdq) id:rvjcz
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:qpc8d, id:htrqb, id:ehh6m, id:egsdq

    - **Placed:** directly after id:egsdq (ZL5), the last of the `@zil` `+AI-G` batch (ZL2..ZL5), by the check-in id:3nrvs (`AGENTS.md`, Check-ins, step 3).
    - **Review:** the steps of `AGENTS.md` Check-ins; re-run each task's numbered checks and probe the sibling routes.

- [ ] +zil +safety +audit +AI-D @zil ZL6 Which common mistakes in hand-written ZIL zilc can catch from what ZIL says id:0mbg3
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decision in id:ahd1c (`future.tm.md`)
    > **Branch:** `zil`
    > **Depends:** id:egsdq, id:rvjcz

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
