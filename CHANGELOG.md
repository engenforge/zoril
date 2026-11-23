# Changelog

Each release lists the changes that can break a program written for the release before it: language rules, standard library names and signatures, and tool options. A changed API gets one line here in the change that makes it.

## v0.2.0

- **Unified provenance and borrow analysis:** Replaced legacy escape classifiers with origin-set provenance tracking and two-tier liveness, closing all open `known_gap` safety-matrix probes and adding `#[unsafe(borrows(*p))]` for held-tie contracts.
- **ZIL verification and IR hardening:** Added `zilc` IR type-checking and CFG drop/stack-escape verification, replaced `bitcast` with `cast`, added `slice_ptr` and `Slice<u8, 'local>` `string_const`, and enabled direct `.zil` root builds in `zbuild`.
- **Language, stdlib, and diagnostics:** Added `--error-limit` and UTF-8/NUL input validation, by-value struct/tuple destructuring, or-pattern binding consistency checks, turbofish arity checks, and `Vec.clear`/`Vec.resize` element dropping.
- **Verification and fuzzing:** Renewed the release-bar differential fuzzer record against `rustc` (2,528,508 programs compiled and run across whole-program and `zbuild` modes with 0 faults or mode-diffs) and expanded the safety matrix to 539 probes across 79 rows.

## v0.1.0-alpha

The first release.
