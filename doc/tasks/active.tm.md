---
project: zoril
status: Active
sprint: 2026-S1
date: 2026-11-03
---

# Current Sprint

Open work, most urgent first. Z-0001 to Z-0006 come from the first cloud session and its setup; Z-0007 to Z-0012 are the hardening series that closes the open soundness holes (each is a check-in: stop for review after it); Z-0013 to Z-0017 follow. Deferred work is in `future.tm.md`. Every `+safety` task follows the safety rules in `AGENTS.md`: the rejection differential for a change that accepts more, and nothing beyond what the task names in the same commit.

- [ ] +safety +review Z-0002 Review the fixes made in the first cloud session
    > **Created:** 2026-11-03

    - **What:** the commits that fixed the executable stack (`81e0340`: `.note.GNU-stack` in `rt/runtime.s` and its byte-identical copy `bootstrap/stage1/rt/runtime.s`, the check in `scripts/check_runtimes.sh`; `b6ab12d`: `tests/integration/external_stub.s`), the POSIX `scripts/marker_density.sh` and portability check 7b (`b372763`), the scdoc 1.11.5 minimum (`36adb90` and its `test_check_deps.sh` follow-up), and the runner's result-file race (`c100684`). The session that wrote them does not close this task.
    - **Re-run:** on Ubuntu 24.04 (binutils 2.42), `readelf -lW` on a program built with `build/zbuild` shows `GNU_STACK ... RW`; with the note removed from `rt/runtime.s` the new runtime check fails. `TR_TEST_ST_DELAY` with the `write_status` change reverted makes `scripts/test_result_file.sh` fail. The scdoc stubs in `scripts/test_scdoc_min.sh` fail with the version check removed.
    - **Status (2026-11-03):** not started. The session that wrote these fixes also worked this series, so it does not review them; a different model or session runs the re-runs above. Known from the first session, as input for the reviewer: `tests/integration/external_stub.s` and `rt/runtime.s` now carry the note; `bootstrap/stage0-c/lib/rt/runtime.s` and `sys_linux_x86_64.s` still do not (Z-0039); the flake's cause was the empty `N.st` window (`TR_TEST_ST_DELAY` reproduces it deterministically).
    - **Siblings to probe:** every other object the toolchain links that is not QBE output (hosted runtime, test fixtures, `bootstrap/stage0-c/lib/rt/`, see Z-0039 in `future.tm.md`); every other file `scripts/test.sh` creates in one process and reads in another (`.out`, `pool.pid`, the plan file); every other `#!/bin/sh` script using a bash-only `set` option.

- [ ] +bench +measurement Z-0004 Measure how far the benchmark gate's measures move between cloud sessions
    > **Created:** 2026-11-03

    - **Why:** `bench/cross_lang/thresholds.cfg` is not in the tree, so `scripts/bench_threshold_check.sh` records a baseline on its first run on a host. Every cloud session starts on a fresh VM, so there the gate compares a run with itself and cannot fail. Of its three measures, `runtime_ratio_vs_gcc_o2` is relative to gcc on the same host; `clean_throughput_loc_s` and `incremental_rebuild_ms` are absolute and depend on the VM.
    - **Do:** in three to five separate cloud sessions, run `sh scripts/bench_cross_lang.sh --check-thresholds` on the same commit and record each measure, the CPU model (`/proc/cpuinfo`) and the load. Report the spread of each measure against the gate's 15% tolerance. Delete the files the run writes under `bench/`; commit nothing but this task's text.
    - **Sample 1 (2026-11-03, commit `fdb0c55`):** `Intel(R) Xeon(R) Processor @ 2.30GHz`, 4 vCPUs, 1-minute load average 2.46 at the start (a `make test` had just finished, so the host was not quiet). `clean_throughput_loc_s` 10177 (the run's own spread 288..297 ms, +3.1%), `incremental_rebuild_ms` 22, `runtime_ratio_vs_gcc_o2` 4.182, `peak_rss_mb_per_kloc` 2.973; the run took 42 s. Earlier on this same VM, an unrelated preflight recorded `clean_throughput_loc_s` 10072, 1.0% below this sample. That is one VM twice, not a spread between sessions.
    - **Sample 2 (2026-11-03, commit `fdb0c55`):** the same conversation, but on a freshly booted VM (booted 14:49 UTC, after the setup script changed), so not the VM of sample 1. `Intel(R) Xeon(R) Processor @ 2.30GHz`, 4 vCPUs, 1-minute load average 0.36 at the start. Run in a scratch worktree of `fdb0c55` whose `build/zoril` was built from that commit's compiler source and which rebuilt its own `zilc` and `zbuild`. `clean_throughput_loc_s` 9705 (the run's own spread 302..330 ms, +9.3%), `incremental_rebuild_ms` 20, `runtime_ratio_vs_gcc_o2` 4.095, `peak_rss_mb_per_kloc` 2.973; the run took 56 s. Against sample 1: clean -4.6%, incremental -9.1%, ratio -2.1%, RSS unchanged, all inside 15%. The bench outputs were deleted with the worktree.
    - **Still to do:** one to three more samples, each from a new cloud session on this commit. This task stays open until they exist; two samples are not a spread.

- [ ] +bench +decision Z-0005 Decide the benchmark gate's behaviour on a host without a committed baseline
    > **Created:** 2026-11-03 **Depends:** Z-0004.

    - **Options, from the measurement:** commit a baseline for the measures whose spread stays inside the tolerance; make the gate print a `[SKIP]` naming the reason for those that do not; and when no committed baseline exists, have the gate say so instead of recording one and passing.
    - **Recommendation (2026-11-03, until Z-0004's spread data decides it):**
        1. A host with no committed baseline gets a statement, not a pass. The gate stops recording a baseline on a first run and then printing "All performance thresholds within tolerance"; it prints `[SKIP] bench-thresholds: no committed baseline for <axis> (<reason>)` per axis and exits 0. Recording stays an explicit act (`sh scripts/bench_cross_lang.sh --record`).
        2. Commit a baseline for `runtime_ratio_vs_gcc_o2` only (4.182 in Z-0004's sample 1): it is relative to gcc -O2 on the same host, so it moves with the compiler and not with the VM. It is committed once Z-0004's samples keep its spread inside the 15% tolerance; otherwise it gets the `[SKIP]` too.
        3. `clean_throughput_loc_s` and `incremental_rebuild_ms` stay host-local. A host that has recorded its own baseline (a developer's machine) still compares against it; anywhere else they print `[SKIP]` naming "absolute measure, no baseline for this host".
    - **Why:** on a fresh VM the present gate compares a run with itself, so it cannot fail, and it says "within tolerance" anyway. A committed absolute baseline would pass or fail with the VM's speed, which tests the VM. Z-0004's single sample says nothing yet about other VMs; rule 2 is the part its data can overturn.
    - **Not done here:** the change to `scripts/bench_threshold_check.sh` and its tests. It needs a task of its own once Z-0004 has its samples.
    - **Reopened (2026-11-03):** the decision depends on Z-0004's measurements, so the task stays open until they exist; the recommendation above is not a decision yet.

- [ ] +docs Z-0006 Publish the provenance design note, `doc/design/provenance.md`
    > **Created:** 2026-11-03 **Owner:** the maintainer supplies the text. **Blocks:** Z-0009 to Z-0012.

    - **Status (2026-11-03):** blocked on the maintainer's text; `doc/design/` does not exist yet and nothing was written in its place.
    - The design of one store-and-return rule over per-local origin sets, which Z-0009 to Z-0012 implement. Add it as supplied, then check it against `AGENTS.md`'s public-text rules (present tense, no history) and `make test` (`md-check`, `comment-noise`).

- [ ] +safety +fuzz +tests Z-0040 S1.3 The store grid gains carriers that bundle the arena itself
    > **Created:** 2026-11-03 **Split from:** Z-0008. **Before:** Z-0010.

    - **Add** to `scripts/fuzz/store_grid.lua`, each with a safe twin: a carrier that bundles the arena itself in a struct literal, and one that bundles it in a tuple, beside an external field (the destination's reference), so a view of the arena and the arena travel together. Add the values to `store_grid_classes.lua`'s axis lists too, or they never appear as classes.
    - The new accepted unsafe cells go into `bench/fuzz/store_grid_expected_failures.txt` and any new twin rejections into `store_grid_twin_rejections.txt`, through `sh scripts/check_store_grid.sh --record`; check that the diff adds only cells of the new values. **Verification:** `make store-grid`, `make test`.
    - **Done (2026-11-03):** carriers `arena_struct_bundle` and `arena_tuple_bundle`, for the `arena_vec` source only. The arena moves into `ArenaBundle { ext_tag: ext_tag, a: a }` or `(ext_tag, a)`, `ext_tag` being a new `i32` parameter of `escape_storer`; the vector is made in `&b.a` (`&b.1`), and the reset, drop and move invalidations act on the bundle (`b.a.reset()`, `@drop(b)`, `sink(b)`). The twin bundles the caller's `&Arena` instead.
    - **Departure from the text above:** the field beside the arena comes from a parameter, as in `gap_31_struct_literal_ext_field` (the probe this carrier is taken from), not from the destination's reference. Moving `out` into the bundle would make every destination write go through `b.ext`, and the text's parenthetical was a guess made when the task was split.
    - **Result:** 1248 new valid cells. 486 unsafe cells are accepted and joined the expected failures (8808 to 9294), all of the new carriers; no other cell moved. No new twin rejection (494 unchanged), 0 generator errors, and four new 2-axis classes: each bundle with `path=fn_val` and with `path=param_65` (43 to 47). The four sampled shapes are refused with a safety reason (region escape, dropping or moving the borrowed bundle) and their twins compile.
    - **Checks:** `sh scripts/check_store_grid.sh --record`: 9294 failing cells, 494 over-rejected twins, 47 classes, 0 generator errors; the diff adds only `arena_*_bundle` lines.

- [ ] +safety +fuzz +tests Z-0041 S1.4 The store grid gains carriers a call produced, and references to a carrier
    > **Created:** 2026-11-03 **Split from:** Z-0008. **Before:** Z-0010.

    - **Add**, each with a safe twin: carrier values for an aggregate a call produced (through a local, a method, an identity function, a closure), and a reference to a carrier reaching the callee directly, through a `let`, an identity call or a phi. Same recording and checks as Z-0040.

- [ ] +safety +fuzz +tests Z-0042 S1.5 A two-module mode for the store grid's summary cells
    > **Created:** 2026-11-03 **Split from:** Z-0008. **Before:** Z-0010, which is expected to close these cells.

    - **Do:** for the cells whose route crosses a call summary, compile the callee as its own module with `-c --write-interface` and the caller against its `.zri`, as `zbuild` does. `scripts/check_store_grid.sh` then builds such a cell in two steps; generate the callee and the caller as two files.
    - The new accepted unsafe cells go into the expected-failures file. **Verification:** `make store-grid`, `make test`.

- [ ] +tools +tests Z-0043 `make preflight-changed` checks a committed change, and builds the base of a stricter rule
    > **Created:** 2026-11-03

    - **Now, two ways the gate runs less than it says:**
        1. Once a change is committed and the branch has no upstream, or its upstream already holds the commits, the gate compares `HEAD` with itself: `mutation-check.sh --changed` prints "No mutation targets a changed file (no changes vs upstream / HEAD)" and the rejection differential prints `[SKIP] reject-diff: none of ... differs from HEAD`, and the gate still passes. Seen on Z-0007 (`1a02a61`).
        2. `scripts/check_reject_diff.sh` seeds the base worktree's `build/` with the working tree's `build/zoril` and rebuilds the base source with it. When the change adds a rule the base source breaks, that build fails ("check_reject_diff: building HEAD failed"): Z-0007's compiler rejects `main`'s `src/main.zrl` and `src/parser/decl.zrl`.
    - **Workaround used on Z-0007:** `git branch --set-upstream-to=origin/<parent branch>`, so `@{upstream}..HEAD` named the change's commits; a copy of the compiler from before the change kept as `build/zoril.base`; and `PREFLIGHT_REJECT_DIFF='sh wrapper.sh' make preflight-changed`, where `wrapper.sh` ran `cp build/zoril build/zoril.keep; cp build/zoril.base build/zoril; sh scripts/check_reject_diff.sh --change HEAD "$1"; rc=$?; cp build/zoril.keep build/zoril; exit $rc`. With the base compiler as the seed, both scratch trees build from their own source: the base compiler compiles both the base source and the change's.
    - **Do:** (1) with no base to compare against, say so as a failure or name the base to use (`PREFLIGHT_BASE=<commit>`), instead of passing; (2) seed the base build with a compiler built from the base: build it through stage1 as a fresh checkout does, or keep the previous `build/zoril`. Add a self-test for each in `scripts/test_preflight.sh`: a committed change with no upstream must not pass silently, and a change that rejects code in the base source must still produce a differential.
    - **Verification:** `scripts/test_preflight.sh`, `make test`, and a `make preflight-changed` on a stricter-rule change that runs its mutations and its differential without a wrapper.

- [ ] +safety +tests Z-0009 B1 Origin sets per local, and the store and return rules on them, behind a flag
    > **Created:** 2026-11-03 **Depends:** Z-0006. **Check-in:** stop for review after it. **Split here** if it outgrows a session (the sets, then the rules).

    - **Build:** in `src/check_zir.zrl`, a forward, flow-insensitive fixpoint computing for every local the origins of the addresses it holds and of the storage it owns (`Frame(L)`, `Param(i)`, `Static`, `Unknown`; field-insensitive), per the design note. Call results come from the existing summaries; a `fn`-value or summary-less call yields `Unknown`. Whether a type owns storage comes from its structure, not `is_collection_type_name`.
    - **Rules, under `--provenance` (off by default):** a destination with any non-`Frame` origin accepts no value with a `Frame` or `Unknown` origin; a return carries no `Frame` or `Unknown` origin. With the flag the old rule still runs too. A `--provenance=warn` mode reports what the new rule rejects and the old one accepts.
    - **Expected to close** (with the flag): `gap_11_dest_closure_capture_mut`, `gap_13_ref_local_enum_payload`, `gap_16_ref_local_fn_val`, `gap_18_elem_ref_enum_payload`, `gap_21_elem_ref_fn_val`, `gap_23_closure_local_enum_payload`, `gap_26_closure_local_fn_val`, `gap_29_dest_closure_call_returns_mut_ref`, `gap_32_byval_collection_param_store`, `gap_36_carrier_ref_enum_payload_match`; the measurement decides, so list what is left for Z-0010.
    - **Done when:** run warn mode over `src/`, `stdlib/`, `tools/` and `corpus/` and record each new rejection as a real escape, a leak, or an over-rejection, without changing that code. `make test` with the default unchanged, `make preflight-changed`.

- [ ] +safety +tests Z-0044 B0.1 A value stored into a local's field through a pointer to the local keeps its borrow
    > **Created:** 2026-11-03 **Check-in:** stop for review after it. **Closes:** `gap_37_local_mutref_field_reset`, `gap_38_param_field_reset`, `gap_39_method_self_field_reset`. **After:** Z-0007.
    > **Depends:** Z-0006.

    - **Now:** a slice written into a local struct's field through a local `&mut`, through a callee's `&mut` parameter, or through `self` in a `&mut self` method is not recorded as a borrow the struct holds, so `a.reset()` passes while the field is read. Z-0007's rule skips these writes (`place_writes_through_pointer`), because the store lands in the referent, not in the base local.
    - **Do:** carry the stored value's borrows to the local the pointer refers to: for a local `&mut`, through the reference's own borrow of that local; for a callee, through a summary edge from the stored argument to the pointer parameter's referent, applied at the call (`#[stores(..)]` is the declared form). Probe the sibling routes: a `&mut` held in a struct field, a reborrow, a closure capturing `&mut w`, and a trait method.
    - **Probes:** the three gap probes flip to `compile_reject`, with an accepted twin for each (the field is read before the reset). Check the over-rejection recorded on Z-0017 does not grow.
    - **Verification:** `make test`, `make preflight-changed`, the rejection differential; the fuzz record goes stale for `src/`.
    - **Placement (2026-11-03):** after Z-0009, because the provenance series (Z-0009 to Z-0012, designed in Z-0006) may subsume it; whoever reaches it decides whether it still stands alone.

- [ ] +safety +tests Z-0010 B2 One call summary from the origin sets, iterated over recursive calls, written to the `.zri`
    > **Created:** 2026-11-03 **Depends:** Z-0008, Z-0009. **Check-in:** stop for review after it.

    - **Build:** the summary is Z-0009's analysis with `Param(i)` seeded: which parameters reach the result, and which parameter's value is stored into which parameter's destination or a global, the same parameter included; parameter 63 and later share one bit in both directions; strongly connected components of the call graph iterate from empty to a fixpoint. Under `--provenance`, callers use it and the `.zri` records it.
    - **Expected to close:** `gap_07_path_same_param`, `gap_27_closure_local_param_65`, `gap_28_call_summary_mutual_recursion`, `gap_33_param_65_arena_slice_store`, the two-module cells of Z-0008, and whatever Z-0009 left.
    - **Verification:** `make test`, `make preflight-changed`, warn-mode measurement updated.

- [ ] +safety +tests Z-0011 B3 Declarations are checked against the body: `#[borrows(..)]`, `#[stores(..)]`, the `&self` default
    > **Created:** 2026-11-03 **Depends:** Z-0010. **Check-in:** stop for review after it.

    - **Rule:** a declaration may list more than the body proves (a wider public contract), never less. Result ties come from the body for every function with one; the `&self` elision default and `#[borrows(..)]` apply only to bodies the compiler cannot see (`extern`, imports) and are checked where it can. A narrowing the body contradicts is an error. Each existing `#[borrows()]` exemption becomes a body the checker can prove or an explicit, reviewed `unsafe` construct, listed with its decision in the commit. **Stop and report** before changing a `pub` stdlib signature.
    - **Probes:** an unannotated `&self` method passing a parameter's borrow through, the same through a trait, and a `#[borrows()]` function laundering one (`compile_reject` under `--provenance`; `gap_30_borrows_attribute_launder` stays rejected); accepted: a `&self` method returning a view of `self`. `make test`, `make preflight-changed`.

- [ ] +safety +tests Z-0012 B4 Make `--provenance` the default, delete the old classifiers, and fix what the measurement found
    > **Created:** 2026-11-03 **Depends:** Z-0011. **Check-in:** stop for review after it. **Split here** if the tree needs more than a session of changes.

    - **Do:** make the new rules the default; resolve every warn-mode rejection recorded in Z-0009 to Z-0011 (a real escape: fix the code; a common over-rejection: stop for a decision on field sensitivity; a leak through a by-value collection parameter: change the code); then delete `local_storage_external`, `local_is_external_target`, `rvalue_is_external_target`, `place_outlives_frame`, `rvalue_storage_external`, `storage_walk_zir`'s mask logic, the depth limits, `is_collection_type_name` and the same-parameter filters, keeping the ZIL stack check as an add-only net. Update `doc/SAFETY.md` §2.3 and §6, `doc/spec/surface_syntax.md` (`#[borrows]`/`#[stores]`), `KNOWN_ISSUES.md` and the store grid's expected-failures file.
    - **Done when:** every unsafe store-grid cell is rejected with the flag gone, no `known_gap` probe of this family is left, the self-hosting fixpoint holds, and `make test` and `make preflight` pass. Then a review round (Z-0013).

- [ ] +safety +research Z-0013 Review rounds: rotate reviewers over the compiler until the findings dwindle
    > **Created:** 2026-11-03 **Standing task;** a round reads and probes only, so it can run beside anything except a change to the area it reviews.

    - **A round:** one reviewer (a model or a prompt not used in the last round) takes one area - the type matcher and conversion sites, the borrow checker and its summaries, drop and move semantics, the stdlib's `unsafe` interiors against what safe code can reach, the FFI boundary, the runtime and `zilc` - probes what it suspects against `build/zoril`, and records each lead here as confirmed, refuted or unprobed, with its reproducer.
    - **Checklist:** every site that puts a value into an expected type (`let`, call argument, return, struct field, enum constructor, array literal and repeat, closure capture, method receiver, `match` arm, pattern binding); every type-matching and conversion function at depth above zero; every cast and what it lets safe code build; every place a size or length is narrowed; every check skipped for a special case (unit, `never`, zero length, constant operand); borrows of `static mut` held across a call or an assignment; the FFI boundary; the stdlib's `unsafe` blocks.
    - **Each confirmed hole** becomes a `known_gap` probe, a route class in `doc/spec/safety_model.md`, and a generator feature in `scripts/fuzz/gen.lua`; it is fixed by another session and fix-reviewed by a third before the next round. A fix states the rule it enforces in one sentence and defaults to the strict side for anything it cannot classify.
    - **Stopping rule:** rounds continue while a round with a fresh reviewer confirms a new hole; stop after two consecutive rounds from different reviewers confirm none.

- [ ] +tools Z-0014 `zilc` refuses text it does not recognise between declarations, and a file that is not ZIL
    > **Created:** 2026-11-03

    - **Now:** `zilc` exits 0 with no message on random bytes, and on `printf '\x01\x02 zz garbage\n'` it writes a stray global parsed out of the word `garbage`. `ZilParser.parse_module` (`tools/zilc/src/zil_parse.zrl`) dispatches on a declaration's first byte and skips any other byte, so text between declarations is dropped silently.
    - **Do:** at top level, after trivia, accept only the declaration forms of `doc/spec/intermediate_language.md` and report anything else as `zilc: line N: expected a declaration, found '<token>'` with exit 1; before parsing, refuse a NUL byte or invalid UTF-8 with one line. Keep the first-error behaviour.
    - **Tests:** a `tests/zilc/` case per refusal (a stray word between two functions, control bytes, a NUL byte), each failing before the change; take the check out and watch the stray-word case pass silently again. Remove or update the `KNOWN_ISSUES.md` entry. `make test`, `make preflight-changed`; the fuzz record goes stale for `tools/zilc/`.

- [ ] +diagnostics Z-0015 `zoril` stops after a bounded number of errors, and says when a file does not look like Zoril source
    > **Created:** 2026-11-03

    - **Now:** 300 KB of random bytes named `junk.zrl` gives about 139,000 error lines (12 MB); 160 KB of prose about 33,000. `zbuild` passes the same output through. Reproduce: `head -c 300000 /dev/urandom > junk.zrl; ./build/zoril -I stdlib=stdlib --emit-zil -o o.zil junk.zrl 2>&1 | wc -l`.
    - **Do:** count errors in `diag_start` (`src/diag.zrl`); past the limit (default 20) print one line naming `--error-limit N` (0 removes the limit) and exit 1. `zbuild --error-limit N` passes it to every `zoril -c`; both man pages and `--help` say so. Before lexing, refuse a NUL byte or invalid UTF-8 with one line; if the limit is reached before the first declaration, the stopping line says the file does not look like Zoril source. `src/diag.zrl` is in stage1's closure: use only what stage1 accepts (a `static mut` counter).
    - **Tests:** a NUL byte, invalid UTF-8, prose, and a program with 25 type errors (20 printed, then the stopping line; `--error-limit 0` prints all 25); the same through `zbuild` (`scripts/test_zbuild_errors.sh`). Check first that no existing error test expects more than 20 errors. Remove or update the `KNOWN_ISSUES.md` entry. `make test`, `make preflight-changed`.

- [ ] +tools Z-0016 `zbuild` builds a program written in ZIL, and refuses any other input with one line
    > **Created:** 2026-11-03

    - **Now:** `zbuild 01_arithmetic.zil` (from `corpus/zil/`) parses the ZIL as Zoril and prints about thirty `expected declaration` errors; the manual pipeline (`zilc`, `qbe`, `as`, `ld` with the runtime) works and exits 30.
    - **Do:** a root ending in `.zil` skips the module graph and the front end and runs `zilc`, `qbe`, `as` and the link with `zbuild`'s usual linker and runtime choice, honouring `-o` and the cache directory; `--checked` with a `.zil` root is refused with one line. A root ending in neither `.zrl` nor `.zil` is refused with one line naming both. Update `doc/man/zbuild.1.scd` (`make man`), `zbuild --help`, and "Starting from ZIL" in `doc/getting_started.md`.
    - **Tests:** with the installed `zbuild` (`scripts/test_user_paths.sh`), `corpus/zil/01_arithmetic.zil` exits 30 and every `corpus/zil/` file gives its expected exit code; the refusals for `foo.txt` and for `.zil` with `--checked`; `scripts/test_man_pages.sh`. Take the `.zil` branch out and watch the scenario fail. Remove or update the `KNOWN_ISSUES.md` entry. `make test`, `make preflight-changed`.

- [ ] +audit Z-0017 A3.5 Twelve safe store-grid twins are rejected
    > **Created:** 2026-11-03 **Fix with or after:** Z-0010 (the same analysis changes). Over-rejection, not a hole.

    - **Cells:** `{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{closure,param_65}__call_struct_mut__frame_ends`, for example `ref_local__struct_field__closure__call_struct_mut__frame_ends.twin.zrl` (`make store-grid` writes them under `build/rv_grid/`): a pointer from the caller's own parameter, passed through a closure identity or as a 65th argument, stored through `get_struct_slot(out).r`, rejected with "region escape: storing local stack pointer into caller memory".
    - **Do:** find which flow marks the closure (or 65th-argument) result as stack when its argument is a parameter; fix it without reopening any other probe, and add one of the twelve as an `accept` probe. `KNOWN_ISSUES.md` does not list this over-rejection yet: add it (section 5) in a commit of its own before the fix, and remove it with the fix.
    - **Over-rejection from Z-0007 (found in its review, 2026-11-03):** borrows are tracked per local, not per field, so a borrow stored into one field keeps the whole struct borrowed while another field is still used. Reproducer: `struct W { s: [i32], t: i32 }`; in `main`, `let mut v = Vec::<i32>.new_in(&a); v.push(42); let mut w = W { s: @slice(0 as *i32, 0), t: 3 }; w.s = v.as_slice(); let x = w.s[0]; a.reset(); return x - 42 + w.t - 3;`. It is safe (`w.s` is not read after the reset): `main`'s compiler accepts it and it exits 0; with Z-0007 it is refused with "cannot mutably borrow 'a' while it is already borrowed" at `a.reset()`, because `w` is live for `w.t`. A fix records the borrow on the field path rather than on the local. Z-0009's origin sets are field-insensitive by design, so decide this together with Z-0009 and Z-0012's field-sensitivity question.
    - **Exposed by Z-0008:** 96 more safe twins with a `ref_local` or `elem_ref` source and a field, tuple-slot or array-slot carrier, through `closure_call_mut` and the storing paths, are refused with the same region-escape error by `main`'s compiler and by Z-0007's (`bench/fuzz/store_grid_twin_rejections.txt`, 398 to 494).
