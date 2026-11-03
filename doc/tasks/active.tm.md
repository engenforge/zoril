---
project: zoril
status: Active
sprint: 2026-S1
date: 2026-11-03
---

# Current Sprint

Open work, most urgent first. Z-0001 to Z-0006 come from the first cloud session and its setup; Z-0007 to Z-0012 are the hardening series that closes the open soundness holes (each is a check-in: stop for review after it); Z-0013 to Z-0017 follow. Deferred work is in `future.tm.md`. Every `+safety` task follows the safety rules in `AGENTS.md`: the rejection differential for a change that accepts more, and nothing beyond what the task names in the same commit.

- [ ] +tests +docs Z-0001 The comment gate accepts source comments that name `doc/tasks`, `doc/design` and `.tm.md` files
    > **Created:** 2026-11-03

    - **Why:** rule 2b of `scripts/check_comment_noise.sh` fails a source comment naming `doc/tasks`, `doc/design` or any `.tm.md` file as a private document. Those paths are now part of the tree, so the first comment that cites a task turns `make test` red.
    - **Do:** remove `doc/tasks`, `doc/design` and `.tm.md` from rule 2b; the rule that a named path must exist in the tree still applies to them. Keep the directories the tree still does not carry (`doc/performance`, `doc/release`, `doc/archive`, `doc/stage0-C`). Update the self-tests in `scripts/test_check_comment_noise.sh` that assert the old behaviour (items 15-21); this changes what those tests expect, so say so in the commit message. Also update the comments elsewhere in `scripts/` that call these paths private (`check_md_tables.sh`, `check_fuzz_fresh.sh`, `test.sh`) where they now say something untrue.
    - **Verification:** a scratch comment naming `doc/tasks/active.tm.md` passes the gate, one naming a missing file still fails; `make test`.

- [ ] +safety +review Z-0002 Review the fixes made in the first cloud session
    > **Created:** 2026-11-03

    - **What:** the commits that fixed the executable stack (`81e0340`: `.note.GNU-stack` in `rt/runtime.s` and its byte-identical copy `bootstrap/stage1/rt/runtime.s`, the check in `scripts/check_runtimes.sh`; `b6ab12d`: `tests/integration/external_stub.s`), the POSIX `scripts/marker_density.sh` and portability check 7b (`b372763`), the scdoc 1.11.5 minimum (`36adb90` and its `test_check_deps.sh` follow-up), and the runner's result-file race (`c100684`). The session that wrote them does not close this task.
    - **Re-run:** on Ubuntu 24.04 (binutils 2.42), `readelf -lW` on a program built with `build/zbuild` shows `GNU_STACK ... RW`; with the note removed from `rt/runtime.s` the new runtime check fails. `TR_TEST_ST_DELAY` with the `write_status` change reverted makes `scripts/test_result_file.sh` fail. The scdoc stubs in `scripts/test_scdoc_min.sh` fail with the version check removed.
    - **Siblings to probe:** every other object the toolchain links that is not QBE output (hosted runtime, test fixtures, `bootstrap/stage0-c/lib/rt/`, see Z-0039 in `future.tm.md`); every other file `scripts/test.sh` creates in one process and reads in another (`.out`, `pool.pid`, the plan file); every other `#!/bin/sh` script using a bash-only `set` option.

- [ ] +fuzz +decision Z-0003 Decide when to renew the fuzz record, now that `rt/` changed
    > **Created:** 2026-11-03 **Owner:** the maintainer (a fuzz session takes the whole machine for hours).

    - **State:** `scripts/check_fuzz_fresh.sh` reports the record stale for `rt/` since `81e0340`. The pages that quote the record (`README.md`, `doc/SAFETY.md` §5, `doc/STABILITY.md`) describe the launched code and stay true while they say so. Z-0007 to Z-0012 will change `src/` several times.
    - **Options:** a short session now; or one after the hardening series (Z-0012), with the pages saying which code the current record describes until then. Record the decision here.

- [ ] +bench +measurement Z-0004 Measure how far the benchmark gate's measures move between cloud sessions
    > **Created:** 2026-11-03

    - **Why:** `bench/cross_lang/thresholds.cfg` is not in the tree, so `scripts/bench_threshold_check.sh` records a baseline on its first run on a host. Every cloud session starts on a fresh VM, so there the gate compares a run with itself and cannot fail. Of its three measures, `runtime_ratio_vs_gcc_o2` is relative to gcc on the same host; `clean_throughput_loc_s` and `incremental_rebuild_ms` are absolute and depend on the VM.
    - **Do:** in three to five separate cloud sessions, run `sh scripts/bench_cross_lang.sh --check-thresholds` on the same commit and record each measure, the CPU model (`/proc/cpuinfo`) and the load. Report the spread of each measure against the gate's 15% tolerance. Delete the files the run writes under `bench/`; commit nothing but this task's text.

- [ ] +bench +decision Z-0005 Decide the benchmark gate's behaviour on a host without a committed baseline
    > **Created:** 2026-11-03 **Depends:** Z-0004.

    - **Options, from the measurement:** commit a baseline for the measures whose spread stays inside the tolerance; make the gate print a `[SKIP]` naming the reason for those that do not; and when no committed baseline exists, have the gate say so instead of recording one and passing.

- [ ] +docs Z-0006 Publish the provenance design note, `doc/design/provenance.md`
    > **Created:** 2026-11-03 **Owner:** the maintainer supplies the text. **Blocks:** Z-0009 to Z-0012.

    - The design of one store-and-return rule over per-local origin sets, which Z-0009 to Z-0012 implement. Add it as supplied, then check it against `AGENTS.md`'s public-text rules (present tense, no history) and `make test` (`md-check`, `comment-noise`).

- [ ] +safety +tests Z-0007 B0 A write into a field, element or tuple slot of a local keeps the borrow it stores
    > **Created:** 2026-11-03 **Check-in:** stop for review after it. **Closes:** `gap_34_field_assigned_slice_reset`, `gap_35_inner_block_arena_field_assigned_ref`.

    - **Rule:** `check_assign` (`src/check_zir.zrl`) records the right-hand side's borrows on the base local for any write not through a dereference: `x = ..`, `x.f = ..`, `x.0 = ..` and `x[i] = ..` alike. A projected write adds to what `x` already holds; it does not end `x`'s other borrows. Today `inherit_rv_borrows` and `propagate_borrow` run only for whole-local assignments, while `end_rv_temp_borrows` always runs.
    - **Probes:** the two gap probes flip to `compile_reject`; add probes for an array slot, a nested field and an `Option` field, and an accepted twin (the same field reassigned and read before any invalidation). Record whether the change also rejects a store or return that escapes through a field write (that is Z-0009's).
    - **Verification:** `make test`, `make preflight-changed`, the rejection differential; the fuzz record goes stale for `src/`.

- [ ] +safety +fuzz +tests Z-0008 S1.2 The store grid gains the routes it does not cover yet
    > **Created:** 2026-11-03 **Before:** Z-0010, whose summary work these cells measure.

    - **Add** to `scripts/check_store_grid.sh`'s generator, each with a safe twin: path values whose callee stores rather than forwards (inside mutual recursion; into a 65th parameter); a carrier that bundles the arena itself in a struct literal or tuple beside an external field; a destination returned by a closure call; carrier values for an aggregate a call produced (through a local, a method, an identity function, a closure) and a reference to a carrier reaching the callee directly, through a `let`, an identity call or a phi; a `static mut` destination; and a two-module mode for the summary cells (the callee compiled with `-c --write-interface`, the caller importing its `.zri`).
    - The new failing cells go into the expected-failures file. **Verification:** `make store-grid`, `make preflight`.

- [ ] +safety +tests Z-0009 B1 Origin sets per local, and the store and return rules on them, behind a flag
    > **Created:** 2026-11-03 **Depends:** Z-0006. **Check-in:** stop for review after it. **Split here** if it outgrows a session (the sets, then the rules).

    - **Build:** in `src/check_zir.zrl`, a forward, flow-insensitive fixpoint computing for every local the origins of the addresses it holds and of the storage it owns (`Frame(L)`, `Param(i)`, `Static`, `Unknown`; field-insensitive), per the design note. Call results come from the existing summaries; a `fn`-value or summary-less call yields `Unknown`. Whether a type owns storage comes from its structure, not `is_collection_type_name`.
    - **Rules, under `--provenance` (off by default):** a destination with any non-`Frame` origin accepts no value with a `Frame` or `Unknown` origin; a return carries no `Frame` or `Unknown` origin. With the flag the old rule still runs too. A `--provenance=warn` mode reports what the new rule rejects and the old one accepts.
    - **Expected to close** (with the flag): `gap_11_dest_closure_capture_mut`, `gap_13_ref_local_enum_payload`, `gap_16_ref_local_fn_val`, `gap_18_elem_ref_enum_payload`, `gap_21_elem_ref_fn_val`, `gap_23_closure_local_enum_payload`, `gap_26_closure_local_fn_val`, `gap_29_dest_closure_call_returns_mut_ref`, `gap_32_byval_collection_param_store`, `gap_36_carrier_ref_enum_payload_match`; the measurement decides, so list what is left for Z-0010.
    - **Done when:** run warn mode over `src/`, `stdlib/`, `tools/` and `corpus/` and record each new rejection as a real escape, a leak, or an over-rejection, without changing that code. `make test` with the default unchanged, `make preflight-changed`.

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
