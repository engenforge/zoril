# Agent instructions

Guidance for any AI agent working on Zoril. Read this, `CONTRIBUTING.md` and `doc/developer_guide.md` before changing anything. This file is the single, tool-neutral source of agent guidance: do not add files specific to one AI tool or one forge.

## Compilers, runtimes and dialects

- **stage0-c** (`bootstrap/stage0-c/`, built by a C compiler): the permanent bootstrap anchor. It builds only the frozen `bootstrap/stage1/` snapshot, never `src/` directly (`doc/bootstrap/two_stage.md`). It links its own executables with `bootstrap/stage0-c/lib/rt/`.
- **stage1** (`bootstrap/stage1/`): a snapshot of `src/`, the `stdlib/` modules it imports, zilc and the runtime, at the commit in `bootstrap/stage1/PIN`. **Never edit it by hand.** It changes only by a re-pin or a recorded backport (`doc/bootstrap/two_stage.md` §3); the one routine exception is `bootstrap/stage1/rt/runtime.s`, which the `runtimes` gate requires to stay a byte-identical copy of `rt/runtime.s`. A re-pin is the maintainer's decision: stop and ask.
- **zoril** (`build/zoril`, built from `src/`): with no `build/zoril`, `make` builds it through stage1 (about a minute, once); afterwards `build/zoril` rebuilds `src/` itself. If a change breaks the compiler, delete `build/zoril` to rebuild through stage1. Its runtime is `rt/runtime.s`, which must keep every runtime symbol the pinned stage1 can emit.
- **zilc** (`build/zilc`) is built by `build/zoril`; with no `build/zilc` yet, `build/zilc-boot` assembles the ZIL it is built from.

| Code | Compiled by | May use |
| --- | --- | --- |
| `bootstrap/stage0-c/` | a C compiler | C99 |
| `bootstrap/stage1/` | stage0-c | frozen; never edited by hand |
| `src/` and the `stdlib/` modules it imports | stage1 and `build/zoril` | only what the pinned stage1 accepts |
| other `stdlib/`, `tools/`, tests | `build/zoril` | the full current language |

**The stage1 constraint.** Every `stdlib/` module that `src/` imports, directly or through another module, may use only what the pinned stage1 accepts; list that closure with `build/zoril --emit-deps src/main.zrl` before planning a change. A new language feature can be used only outside that closure. A type-checker change is also compiled by the previous `build/zoril`, so `src/` must build under both the old rule and the new one.

**The seeds are frozen.** stage0-c is fixed only when a bug blocks building stage1 or its own suites, with a minimal reproduction first and a regression test under `bootstrap/stage0-c/tests/fixed_bugs/`. A construct stage1 cannot parse is kept out of the modules it compiles. Before blaming a seed compiler, reproduce the bug against it.

**An ambiguity or contradiction in `doc/spec/` is a bug too**: fix the spec in the same change that relies on the answer.

## Build warnings

Zero tolerance. Every warning from any compiler build is resolved before a task is done; the `Makefile` fails a build whose compiler output contains `warning:`. Fix the cause; never suppress a warning.

## Running tests

Run `make test-fast` while editing, `make test` before committing (with `make preflight-changed` when `src/`, `stdlib/` or `tools/` changed), and `make preflight` before a release.

- `make test-fast` — the smoke suite (`tests/smoke.list`, 51 tests across every group, a few seconds). No substitute for `make test`.
- `make test` — everything, run by `scripts/test.sh --gates` in parallel: first the gates, then the test groups. Output shape (`scripts/test.sh --help`): a `[FAIL] name (reason)` line per failing item with indented detail lines, one count line per gate or group, and last `Total: N run, P passed, F failed, S skipped (Xs)`. So `make test 2>&1 | grep -E '\[FAIL\]|^Total:'` lists every failure and the verdict. A gate's full output is in `build/gates/<name>.log`, a scenario's in `build/tests/scenarios/<name>.log`. Narrow with `TSUITE=<group>` or `T=<regex>` (verbose: commands, outputs, artifact paths, expected-vs-actual diff).
- `make preflight-changed` — the pre-merge gate for a change: a clean-tree build, the self-hosting fixpoint, the mutations of the changed files, and the rejection differential when the checkers changed. A preflight that stops early has not run: every step after the failing one did not run. Fix the step, or make it skip what the host cannot do and name the reason (`[SKIP] ... needs /proc (Linux)`), and rerun.
- `make preflight` — the slow gate: the above plus the full mutation set, the cross-language benchmark thresholds and the store grid.
- `make safety-matrix` runs the safety probes alone; `./scripts/test.sh [--verbose] [--filter REGEX] [--fail-fast] [-j N] [PATH...]` is the runner itself. Every test file belongs to exactly one group (`group_paths` in the script).
- Test expectations are header comments: `// expected exit <N>`, `// expected compile fail`, `// EXPECT: <diagnostic text>`, `// expected compile success`, `// flags: <compiler flags>`, `// link: <file.s>`, `// @skip: <reason>`. `*_lib.zrl` files are imported modules, not tests.
- **Wrap every direct `zoril`, `zilc` or `zbuild` invocation in `timeout`** (`timeout -k 5s 30s ./build/zoril ...`): a miscompiled compiler usually hangs at full CPU rather than crashing. The Makefile already does this.
- **Do not poll a background job.** Start a long command with its log under `build/`, then do other work that does not touch what it uses (never edit `src/`/`stdlib/` or rebuild `build/zoril` while it runs), or end the turn and read the log when it finishes. If there is no completion notice, run it in the foreground with a timeout.

## Cloud sessions

The cloud environment is configured outside the repository (its setup script installs QBE 1.3, Lua 5.4, scdoc 1.11.5 and `tm`). In a session:

- Check the environment before relying on it: `sh scripts/check_deps.sh test`, `qbe -h`, `lua -v`, `scdoc -v`, `tm version`. Report what is missing; do not work around it silently.
- The VM has 4 vCPUs: `make test` takes about five minutes and `make preflight-changed` longer. Run them in the background with a log under `build/`.
- `make preflight` writes host-specific benchmark files under `bench/` (`bench/cross_lang/thresholds.cfg`, `bench/cross_lang/last_zoril_metrics.tsv`, `bench/speed_history.tsv`). They describe the VM, not the project: never commit them; delete them when the run is done.
- Never push tags; releases and their tags are the maintainer's.
- Downloaded archives are untrusted: extract each into its own empty directory and read its build files before running them.

## Working on tasks (`doc/tasks/`)

Work is tracked in Taskmark files (SPEC-TASKMARK-03, `https://github.com/engenforge/taskmark`): `doc/tasks/active.tm.md` holds open work and is read at the start of every session, `future.tm.md` deferred work, `completed.tm.md` the archive. Each task's detail lives in a payload block indented exactly 4 spaces beneath it. Run `tm validate doc/tasks/*.tm.md` after every edit.

- **IDs.** Every task title starts with a permanent ID (`Z-0001`), never reused. Commit messages name the ID they work on. Issues on any forge are intake: triage one into a task that links it, and write decisions made in an issue thread back into the task.
- **One task, one session-sized piece of work.** A piece that takes longer is split into several tasks, each with its own checkbox and ID, kept together by a shared tag (`+safety`) and a numbered title prefix (`B1`, `B2`). A decision, a measurement and an implementation are separate tasks.
- **Move a task to `active.tm.md` before working on it**; never complete a task in `future.tm.md`.
- **Add a task by inserting new text**; never replace an existing task's header lines while editing nearby.
- **Record a finding on the task as it is made**, as a new bullet: the fixed cause and how it was verified, the leads ruled out and why, the current failure verbatim, and the next step as a command. A session's context is finite; a diagnosis that lives only in the conversation is lost. Reproducers go into the task text or a test, not only into `/tmp`.
- **A completion note** (`> **Completed:** YYYY-MM-DD git:<sha>`, then a bullet) records which checks ran (`make test`, `make preflight-changed`, ...) and their totals. A change to `src/`, `stdlib/` or `tools/` runs both `make test` and `make preflight-changed`; `make test-fast` is never enough on its own.
- **Rotate completed tasks to `completed.tm.md` with their text unchanged, in a commit of their own** (`tm sweep`).
- **Check-ins.** A task that says it ends with a check-in, or a fix to a safety rule, ends with its fix committed, a bullet `**Awaiting review:** <what the reviewer re-runs>`, and its checkbox still open. Do not close it and do not start the next task; stop and report. **The model that wrote a fix does not close it**: a reviewer (another model or session) re-runs the reproducers and probes the sibling routes. Also stop and report if a task needs more than one session (split it in the task file first), changes or removes a test's expected result, rebuilds files under `build/` from inside a test or gate, or turns a checked borrow into a raw pointer to get past a rule.

## Safety claims and evidence

A safety claim written down before it is probed is this project's most expensive recurring mistake. So:

- **Probe, do not read.** Before stating any safety property, compile a three-line program and run it. Test counts cover what someone thought to check, not what the spec claims.
- **`doc/spec/safety_model.md` is the source of truth** for what Zoril guarantees. Every row names a mechanism, a boundary and a test under `Proven by`; a row that cannot name a test is untested or unfounded and is not added.
- **`sh scripts/run_safety_matrix.sh`** runs `bench/safety_matrix/probes/` and fails on any mismatch with the recorded expectation. Run it after touching the checkers, the lowering or codegen.
- **Known holes carry probes that assert the unsafe behaviour on purpose**: `// expected: known_gap` with a `// gap:` reason, listed under "Known gaps" in `safety_model.md` (`scripts/check_safety_model.sh` enforces the match), reported as `[SKIP]` in `make test`. Closing a hole breaks its probe on purpose: flip the expectation, remove the Known gaps entry and the line in `doc/SAFETY.md` §6. A newly found hole gets a `known_gap` probe the same way.
- **When a hole is found, name its route class** (an IR construct, a CFG shape, a call kind, a pattern form, a conversion site), add it to the affected rows' Routes, and probe every other construct in that class. **When one row changes, check its structural twins** (reads and writes, references and function pointers).
- **A change that makes a checker accept more needs the rejection differential.** Run `scripts/check_reject_diff.sh <base-commit>` (it builds the base compiler in a scratch worktree under `build/`; never replace `build/zoril`) and list in the completion note every program the base rejects and the change accepts, with its reason. An unsafe one blocks the commit. `make preflight-changed` runs it when the checkers or what reaches them changed.
- **Fix what the task names, and stop at anything more.** A fix that also flips other probes or changes other accepted programs puts them in a commit of their own, with the differential, and stops for review.
- **`sh scripts/marker_density.sh <file.zrl>`** reports raw-pointer marker density; `doc/spec/unsafe_policy.md` is normative for the marker. Compiler density is not a claim about the language (`unsafe_policy.md` §5).
- **The fuzz record describes the code it ran on.** A change to `src/`, `stdlib/`, `tools/zilc/`, `tools/zbuild/` or `rt/` makes `bench/fuzz/README.md` (quoted in `doc/SAFETY.md` §5) stale; say so in the completion note. `scripts/check_fuzz_fresh.sh` reports it (`--strict` fails).

## Test the path the user takes

Every gate that runs only the repository's own `build/zoril`, whole-program, in a git checkout misses what a user runs. When a change touches a user path, check it the way a user does:

- Whole-program and `zbuild`; `build/`, an installed prefix and the binary archive; a git checkout and the source tarball; from outside the repository, stdin from `/dev/null`. The gates: `zbuild-diff`, `safety-matrix-zbuild`, `zbuild-errors`, `make dist-check` with `scripts/dist_user_paths.sh`, `scripts/test_user_paths.sh`.
- **Two implementations of one thing are tested against each other**: whole-program against separate compilation, the safety matrix in every build mode. The fuzzer reports a disagreement as `[MODE-DIFF]`.
- **Anything written out and read back is tested for what it loses** (a `.zri`, the ZIL); such cases go in `tests/modular/iface_attrs/`.
- **Names come from users**: digits, punctuation, keywords, upper case, standard-library module names (`scripts/test_module_names.sh`).
- **Take the fix out and watch the test fail.** A check that cannot see the defect it was written for passes for the wrong reason.

## Language gotchas

- `&`, `^` and `|` bind tighter than comparisons (Rust-style): `x & MASK != 0` is `(x & MASK) != 0`. Mixing bool and non-bool operands is a type error, comparisons are non-associative, assignment yields no value, and `if`/`while` conditions must be bool.

## Editing

- **Small, verifiable edits**: one function, match arm or helper at a time, checked before the next.
- **No `sed -i` or line-number edits on source files**; edit exact text you have just read.
- **Check the edit, then build**: `make` after a change to `src/`, `stdlib/` or `tools/`, and commit each verified unit.
- **A refactor preserves behaviour**; the tests that cover the code are the check.

## Source comments

Comments state why, never what: an invariant, a memory-ownership rule, an ABI or hardware constraint, a grammar production above a parser, a spec section reference, or the reason a naive alternative was rejected. Anything else is deleted or replaced by a better name.

- **Never**: narration, restatement of the next line, commented-out code, scaffolding (`TODO`, `FIXME`), a docblock on an obvious private function, or a bug claim no reproduction backs.
- **Short, but not artificially so**: 2-4 lines of rationale are normal in a lowering pass; history belongs in git and the task files.
- **Marker lines are load-bearing; never delete, move or reword one**: `// SAFETY:` (`scripts/check_safety_comments.sh`), `// exhaustive:` (`scripts/check_exhaustive.sh`), `// expected:`/`// gap:` in the safety probes, the test directives above, and the corpus `// --- id:` banners.
- **`stdlib/` comment blocks are the man pages** (`tools/zman`, `make man-gen`): a module's first paragraph is its summary, and an item without a comment is an error. Run `make man-gen` and `scripts/test_man_pages.sh` after changing one.
- **The `comment-noise` gate** (`scripts/check_comment_noise.sh`) fails on scaffolding phrases, on a comment naming a path the tree does not carry, and on a file over its comment budget (`scripts/comment_budget.tsv`). If a file goes over because of comments the change needs (an invariant, a `// SAFETY:` line), re-record only that file's row (`scripts/comment_census.sh --record`, then keep that row) and say why in the commit message. Never delete a rationale to fit the budget, and never re-record the whole table.

## Debugging discipline

- **Minimal reproduction before any workaround.** A claimed compiler or codegen bug is shown by a small test against the toolchain blamed before a workaround is written. If the reproduction passes, the claim is wrong.
- **Bisect, don't revert proven work**; never disable committed, equivalence-proven functionality to route around a failure.
- **No speculative claims in comments or docs**; a workaround's comment links its reproduction test.
- **Commit each proven fix before the next long verification run.**

## No new dependencies

No dev tool brings a runtime this repository does not already depend on. The `no-new-deps` gate (`scripts/check_no_new_deps.sh`) fails on `.py`, `.rb`, `.pl` or `.php` files and on python, perl, ruby, node, deno, bun or php shebangs. Accepted: what `scripts/check_deps.sh` names (a C compiler, qbe, `as`, `ld`, a POSIX shell, Lua for the fuzz generator, `rustc` for the differential oracle, the document tools). A tool that needs more than a short POSIX `sh`/`awk` script is written in Zoril under `tools/<name>/`.

## Portability

Portability to the BSDs and other targets is a goal, so no non-portable construct is added where a portable one is cheap.

- **QBE with the system assembler and linker is the first-class backend**: the default, the bootstrap path, and what the tests and the fuzz record cover. Other backends may be added beside it, never in its place, and the QBE path must not come to need LLVM or more of a C toolchain than it needs today.
- **Scripts are POSIX `sh`**: no `[[ ]]`, `${x//a/b}`, `<( )`, `declare`, `set -o pipefail` under `#!/bin/sh`; no `sed -i` (write a temp file and `mv`), `stat -c` (`wc -c <`), `date +%s%N`, `nproc` (`getconf _NPROCESSORS_ONLN`), or bare `sha256sum` (use the shared helper). awk programs are POSIX awk (no `\<`, no gawk functions, no `/` or `\]` inside a bracket expression). Read tools from `config.mk` (`BACKEND_BIN`, `ASSEMBLER_BIN`, `LINKER_BIN`), never a hard-coded `qbe`/`as`/`ld`. Pass QBE its options before the input file.
- **Platform-bound code fails or skips clearly**, naming the platform. Platform-bound today: the runtime (Linux x86_64 syscalls, ELF), `/proc` measurements, and the Makefiles (GNU make).
- A GNU-only or bash-only construct where a portable one was easy is a review finding; the `portability` gate (`scripts/check_portability.sh`) catches the common ones.
