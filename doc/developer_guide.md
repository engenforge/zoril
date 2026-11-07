# Zoril Developer and Contributor Guide

This guide is for developers and contributors working on the Zoril compiler toolchain, standard library, and runtime. If you are an end user looking to write and compile Zoril programs, see the [Getting Started Guide](getting_started.md) and the [Tour of Zoril](tour.md).

---

## 1. Developer Prerequisites

Compiling Zoril from source requires only a C compiler, GNU Make, QBE, and GNU binutils (as detailed in the [README](../README.md)). However, developing changes, running the full verification test suites, fuzzing, and executing pre-merge gates require additional tools.

Each tool belongs to the lowest role whose command needs it (`AGENTS.md`, Portability), and a change never moves a tool into a lower role:

- **User** (`make`, `make install`, `make test`, from a checkout or a source tarball): a C compiler, QBE, `as`, `ld`, GNU make, a POSIX shell and the POSIX utilities.
- **Contributor** (`make test-changed`, `make preflight-changed`, fuzzing, the documentation): the user's tools, plus git, Lua, scdoc, dprint, rustc and valgrind.
- **Maintainer** (`make preflight`, `make dist`, a release): the contributor's tools, plus bsdtar.

Today `make test` also needs `flock` and `mkfifo` for its parallel pool, `bash` for `scripts/check_md_links.sh`, `scripts/check_safety_model.sh` and the stage0-c suite scripts, and in a checkout one of its items still calls git when it is there; all are being removed (the `tools/ztest` series ending with Z-0140, Z-0152, and Z-0146 and Z-0147). The list below says what each tool is used for:

- **flock (`util-linux` or BusyBox):** Required for process synchronization in the parallel test runner.
- **Lua (5.3 or 5.4):** Required for the generative fuzzer (`scripts/fuzz/gen.lua`) and benchmark generators.
- **coreutils (`mkfifo`, `xargs`, `timeout`):** Required for parallel test runners and stage timeout enforcement.
- **git:** Required for self-hosting repository isolation checks, clean tree checks, and version stamping.
- **dprint:** Optional markdown formatting checker (used by `make md-check` and `make md-fmt`).
- **valgrind:** Optional memory profiling checker (used by `make perf-gate`).
- **rustc:** Optional differential oracle for fuzz testing (`make fuzz`).
- **scdoc 1.11.5 or newer:** Required for development: the roff man pages in `doc/man/` are committed, so building, installing and `make test` need no scdoc (`make test` skips the page check without it, and with a scdoc older than 1.11.5, the version the pages are generated with, because older releases write other roff for the same source), but `make preflight` and `make man` require 1.11.5 or newer and fails when a committed page does not match its `.scd` source. `make man` regenerates them.
- **bsdtar (libarchive):** Required only to build the release archives (`make dist`, `make dist-bin`, `make dist-check`): `libarchive-tools` on Alpine and Debian, part of `libarchive` on Arch, built in on FreeBSD and macOS.

You can verify all developer dependencies on your machine by running:

```sh
./scripts/check_deps.sh test
```

---

## 2. Contributor Verification Workflow

Before submitting changes, all contributions must pass rigorous verification suites.

### Verification Rules

- **Scoped Tier While Editing:** Run `make test-changed` while editing to run only what the tier table (`scripts/test_tiers.tsv`) selects for changed and untracked files. The base commit is chosen by `preflight_base` (the upstream branch or default branch merge base when unpushed commits exist, else HEAD for uncommitted working tree changes). Pass `BASE=HEAD` while editing to scope checks only to uncommitted changes, or `BASE=HEAD~1` after committing task or doc files to test only that commit and avoid running the tiers of unpushed commits. Use `make test-changed BASE=<commit>` to select changes against an arbitrary base commit. On a clean tree with no commit beyond the upstream or default branch there is nothing to compare, and it fails saying so; pass `BASE=` to name a base.
- **Code Changes:** Any task modifying `src/`, `stdlib/`, or `tools/` must pass both `make test` and `make preflight-changed` once, after the last change to compiled code.
- **Documentation or Task Only Changes:** If a passing whole test run has already run on the tree, a commit modifying only documentation or task files reruns only the doc tier (`make test-changed BASE=HEAD~1` or its gates).
- **Smoke Tests:** While editing, run `make test-fast` for sub-second feedback on core functionality (`make test-fast` alone is never enough for a code change).

```sh
# Fast smoke tests during development
make test-fast

# Scoped tier for changed files during development (defaults to upstream if unpushed commits exist)
make test-changed
# Scoped tier for uncommitted changes while editing
make test-changed BASE=HEAD
# Scoped tier for the latest commit (e.g. after committing doc or task files)
make test-changed BASE=HEAD~1
# Scoped tier against an arbitrary base commit
make test-changed BASE=main

# Full test suite
make test

# Fast pre-merge gate: 4-generation bootstrap fixpoint + mutation tests on changed files
make preflight-changed
```

---

## 3. Developer Gates and Tools

The repository includes several specialized developer tools and targets:

### Preflight Gates

- **`make preflight-changed`:** Runs self-hosting checks and targeted mutation testing for modified files in ~3 minutes.
- **`make preflight`:** Slower comprehensive pre-merge gate (~4 minutes). Verifies bit-for-bit compiler self-hosting fixpoint across 4 generations, executes full mutation checks, and runs performance benchmarks against calibrated thresholds.

### The Checked Build (`make test-checked`)

`make test-checked` runs the per-file suite, the corpus and the apps again with every program built by `zoril --checked`, an instrumented build for memory-safety testing, then asks the safety matrix which known holes that build detects:

```sh
make test-checked
```

Under `--checked` the emitted program poisons released arena space and never hands it out again, poisons a local's slot where its scope ends, poisons a dropped value and traps (exit 134) on a second drop of it, and marks a released heap block so a second release of it traps (exit 134) instead of unmapping whatever lives there now. A dangling read then finds the poison - exit 165 when the program compares the value, a fault when it follows it as an address - which is how a stack, arena or heap use-after-free that a release build hides becomes an observation. The flag is a test instrument, not a safety mode: it changes nothing about what the compiler accepts, a release build emits none of it, and `corpus/zrl_whole_program_zil.sha256` does not move. `zbuild --checked` builds a whole project the same way, and `scripts/zoril-checked.sh` is `build/zoril --checked` for anything that takes the compiler as one path. A test asserts what only the checked build does with `// flags: --checked` and `// expected exit <n>` (see `tests/language/memory/checked_build_*.zrl`).

### Dependency Matrix Testing

To verify how the build system and test harness behave when optional tools are missing or when toolchain binaries are relocated:

```sh
make deps-matrix
```

### Reproducible Builds Verification

To bootstrap the compiler from scratch twice in isolated directories and verify that the two builds are byte-identical (add `HASHES=file` to also compare with a release's binaries, which matches only on a host with the release host's toolchain):

```sh
make repro-check
```

See [Reproducible Builds](reproducible_builds.md) for details.

### Minimal Bootstrap Stack Testing

Zoril supports bootstrapping from a minimal C toolchain using `cproc`, `mcpp`, and `musl` without GCC or Clang dependencies:

```sh
# Build the stage0 bootstrap seed using cproc/mcpp
make -C bootstrap/stage0-c minimal

# Run stage0 self-contained unit and functional suites
make -C bootstrap/stage0-c test_all_minimal
```

The two seed compilers and how they fit together are described in [`bootstrap/bootstrap_layering.md`](bootstrap/bootstrap_layering.md); the re-pin procedure and backport policy are in [`bootstrap/two_stage.md`](bootstrap/two_stage.md).

### Fuzzing

The fuzzer generates programs from a grammar, compiles and runs them through the real pipeline, and checks them against several oracles (a crash, value canaries, drop accounting, a checked build, and `rustc` as a differential oracle). `bench/fuzz/README.md` is the reference: the oracles, the generator, the calibration table and the release-bar record. This section is the how-to. It needs `lua` and `timeout`; `rustc` turns the differential oracle on.

**1. A quick check before a commit.** Two targets, about a minute together:

```sh
make fuzz-short       # 25 seeds x 4 programs, every oracle
make fuzz-calibrate   # one program per known hole: each row must stay in its fixed state (26 rows)
```

**2. Your own session.** Foreground, all cores, output under `build/fuzz/<NAME>/`; nothing is filed and nothing is cited:

```sh
make fuzz-session SEEDS=1-20000                  # a status line every five minutes
make fuzz-start   SEEDS=1-200000 NAME=mine       # the same in the background; survives the terminal
make fuzz-status  RUN=mine WATCH=60              # banner, status line, workers, findings
make fuzz-summary RUN=mine                       # the figures, summed over the workers
make fuzz-stop    RUN=mine                       # stop it; the partial figures stay readable
```

A seed is eight programs (`--count 8`). Measured on 16 cores: 12.6 seeds a second, so `SEEDS=1-20000` is about 26 minutes. Liveness comes from files, not `ps`: each worker rewrites `w<k>.status` about once a minute, and a worker silent for three heartbeats is called stalled. Stop a run from the shell that started it: a container or sandbox has its own process IDs, so `make fuzz-stop` from another one cannot signal the run, sees its heartbeats, says so and changes nothing.

**3. Reading the result.**

- **`[FAULT]`** - a program Zoril accepted that ended in a signal other than the 134 trap, or a canary (exit 92), a drop count (91) or a poison read (165) went wrong, or a program that should terminate timed out. A finding.
- **`[CANDIDATE]`** - Zoril accepted a program `rustc` rejects, and the difference is not in `bench/fuzz/intended_differences.txt`. A finding.
- **`[DIFF]`** - the same, but the difference is listed (today only `E0503`, a write through a mutable reference). Counted, not a problem.
- **`[INFER-DIFF]`** - Zoril refused a program `rustc` accepts with a borrow diagnostic. A usability gap.
- **Known-hole rows** - the calibration programs. `still open` means a fixed hole has reopened, which is a finding; `faulted with the switch off` must be 0.
- **`[GEN-BUG]`** - the generator wrote a program with a type error. Fix the generator.

**4. You found something.** Reproduce one seed with `./scripts/fuzz_safe.sh --seeds S-S --keep`, minimise the program, and name its route class (an IR construct, a CFG shape, a call kind, a pattern form) before you fix it, and probe the rest of that class: a hole is rarely alone. File the pair under `bench/fuzz/findings/` (`make fuzz` does that for you) and name it in that directory's README. A fix to `src/`, `stdlib/`, `tools/zilc/` or `rt/` makes the release-bar record stale.

**5. The release-bar procedure.** Six targets, in order, from a clean tree:

```sh
make fuzz-preflight                              # every line [PASS]; the record shows stale until a new one
make fuzz-pilot                                  # 10,000 seeds x 8 (about 13 minutes on 16 cores), then its plan
make fuzz-plan RAN=2500000                       # the seed range for the target plus 5%, and the wall time
make fuzz-release-start SEEDS=1-N RAN=2500000    # the line fuzz-plan printed; ask first: it runs for hours
make fuzz-status WATCH=300                       # a finding stops the run: report it, fix, start again
make fuzz-summary                                # the target met, 0 faults, 0 candidates
make fuzz-record-update RUN=release-<name>       # numbers into bench/fuzz/README.md and the pages that quote them
```

`fuzz-record-update` refuses a run with a fault, a candidate, an open known hole, an unmet target or a fingerprint that is not the tree's; it rewrites numbers only, so the prose of the record (what changed, the classification of the listed differences) is yours, and it lists the paragraphs to re-read. Then `scripts/check_fuzz_fresh.sh --strict` must pass.

When the compiler changed after the release-bar run and a release cannot wait for a new one, a shorter session on the new code stands beside it: `make fuzz-session SEEDS=1-N RELEASE=1` (which refuses a dirty tree, stale binaries or a missing `rustc`), then `make fuzz-record-update SHORT=1 RUN=<its directory>`. That writes the section "The short session on the launched code" into the record, with its own fingerprint and headline. `check_fuzz_fresh.sh` then compares that entry with the tree, and requires every page that discusses the record to quote its figure; a page may quote the release-bar run as well, saying it was on the previous code, but never alone. The next full release-bar run, recorded without `SHORT`, removes the section.

**6. What it covers and does not.** The generator builds composed programs from 69 feature tags and checks the safe subset against the oracles above. It does not reach the runtime checks whose index is computed at run time, or miscompiles that change a value without a fault; `doc/SAFETY.md` §5.2 says what a clean run supports and what it does not.

---

## 4. Code Formatting and Documentation Standards

- **Zoril Formatting:** Format compiler and stdlib code with `build/zoril fmt`.
- **Markdown Formatting:** Format markdown documents with `dprint fmt` (or `make md-fmt`). The configuration in `.dprint.json`, at the repository root, sets how dprint formats Markdown.
- **Changelog:** a change to a language rule, a standard library name or signature, or a tool option gets one line in `CHANGELOG.md`, under the release it ships in, in the change that makes it. `KNOWN_ISSUES.md` lists only what is wrong in the current release.
- **Markdown Layout:** a paragraph or list item is one line and the editor wraps it; `dprint fmt` joins hard-wrapped lines, and `md-check` fails a file that has them. A page starts with its `#` title and carries no frontmatter: nothing reads it.
- **Markdown Tables:** a table is at most 140 characters wide, so it does not wrap or scroll sideways in a terminal or a diff. One that cannot be made to fit is written as an outline (a bullet per row, the other columns as sub-bullets). The `md-check` gate enforces it (`scripts/check_md_tables.sh`); `scripts/check_md_tables.sh --fix FILE` rewrites a wide table as an outline, and the prose around it is yours to adjust.
- **Reference access in compiler code:** access referenced data (AST nodes from `self.resolver.ast`, say) through a single named reference binding (`let ast: &AST = &*self.resolver.ast; let decl = &ast.decls[id as usize];`), not through a raw-pointer dodge (`&(*ast_ptr).decls[i]`), manual pointer arithmetic, or a nested dereference (`&(*(*self.resolver).ast).types()[i]`). The binding names the borrow, so diagnostics point at it, and it isolates the pointer-to-reference forge to one line. Write `r.field` for a reference (`&T` / `&mut T`) and `(*p).field` only for a raw pointer; `*r` stays for copying or moving the referent (`Option.Some(*p)`). The compiler accepts `(*r).field`, but the unsafe-marker density tooling and reviewers read `(*p)` as a raw-pointer dereference.
- **Documentation Snippets:** Code snippets in documentation are tested automatically by `make test-docs` (part of `make test`). A Zoril code block that defines `fn main` must compile and exit 0. Use `zoril,wrap` for statement snippets, `zoril,compile-fail` for compile-error demonstrations, or `zoril,no-test` for non-executable syntax sketches.
- **Source Comments:** a comment states _why_, never _what_ - an invariant, an ownership rule, an ABI or hardware constraint, a grammar production above a parser, a spec-section citation, or the reason a naive alternative was rejected (with the date when a measurement is the point). Delete anything else, or replace it with a better name or an extracted helper; history belongs in the commit log, not the source. The archive-style 1-2-line cap is deliberately relaxed here to 2-4 lines, because a lowering or borrow-checking decision often needs that much to say why; a block longer than about six lines has to earn the space with a constraint rather than a retelling of the incident. Marker lines a gate reads (`// SAFETY:`, `// exhaustive:`, probe `// expected:`/`// gap:`, the test directives, the corpus `// --- id:` banners) are load-bearing and are never deleted or reworded. In `stdlib/` a comment block above an item is that item's manual page, generated by `make man-gen`: trim the prose, keep the content. `make test` enforces the mechanical half as the `comment-noise` gate - scaffolding and step-narration phrases, comment paths the tree does not carry, and a per-file comment budget; whether a comment says _why_ stays a review judgement.
- **Manual Pages and API Drift Prevention:** Any change to tool options (`zoril`, `zilc`, `zbuild`) must update its page in `doc/man/*.scd` by hand, then run `make man` to regenerate the committed roff page beside it (a page keeps its `.TH` date until its content changes). The standard library pages (`doc/man/zoril-<module>.3.scd`) are not written by hand: `make man-gen` regenerates them, and their roff pages, with `tools/zman`, a Zoril tool that reads a fresh `zoril --emit-interface` output per module for signatures, fields, visibility and `#[must_use]`, and the module's own comment blocks for descriptions (the module's first comment paragraph is its summary; an item with no comment above it is an error naming it). `scripts/test_man_pages.sh` in `make test` regenerates every page into a temporary directory and diffs it against `doc/man`, so a signature, a field, a visibility change or a description that was not regenerated fails with the diff and "run make man-gen"; it also extracts the tool options from `--help` and fails if any documented option drifts or goes undocumented.

## 5. Rules for Changes

The rules a change follows, beyond the four in [CONTRIBUTING.md](../CONTRIBUTING.md) (small and focused, a failing test, `make test`, no unbacked safety wording). Safety rules get a probe under `bench/safety_matrix/probes/`; everything else a case under `tests/`.

- A **safety claim** names the test behind it, and states it precisely: what is checked at compile time, what is checked only when the program runs, and what is left to the programmer. The tiers, with a probe or test for each claim, are [What Zoril Checks](SAFETY.md), and the public pages link to it rather than restating it. Do not write "memory-safe", "guarantees memory safety", "provably" or "no dangling pointers" about Zoril without the tier and the test behind it, nor that it "eliminates" or "prevents" a memory-bug class. "Prevent" and "eliminate" in their ordinary sense ("eliminates a build race") are fine.
- A fix for a safety hole covers its whole class: name the route it came through (a conversion site, a pattern form, a call kind) and add a probe for every other construct of that kind, not only the spelling that was reported.
- Before 1.0 the standard library may change incompatibly: a renamed function loses its old name rather than keeping an alias, and the examples in the docs, `corpus/` and the man pages move in the same change (`make test-docs` and `make test-readme` check them). Each changed API gets one line in `CHANGELOG.md`.
- To fuzz your own change, see [Fuzzing](#fuzzing): `make fuzz-short` before a commit, `make fuzz-session SEEDS=1-20000` for a longer session.
- Format Zoril sources with `build/zoril fmt` and Markdown with `dprint fmt` (the `fmt-check` and `md-check` gates enforce both).
- Code blocks in the docs are compiled by `make test-docs` (part of `make test`): a `zoril` block must compile, and one that defines `main` must also run and exit 0. Use the info string `zoril,wrap` for statements outside a function, `zoril,compile-fail` for an example of a compile error (mark the failing line with a `// COMPILE ERROR` comment), or `zoril,no-test` for sketches that are not meant to compile.
- A change to a path a user takes (building, installing, `zbuild`, the release archives, an interface file) is tested on that path, with `zbuild` as well as whole-program: `make test` runs both against every runnable program, the safety matrix and the error tests, and `make dist-check` builds and uses the archives as README says. Names that come from users - file and module names with digits, punctuation, keywords - are part of the test.
- A change to `src/`, `stdlib/` or `tools/` must also pass `make preflight-changed`, because `make test` does not exercise the source bootstrap: it is where a construct the frozen stage1 compiler cannot parse is caught. Run the full `make preflight` before a release and periodically; §3 explains each.
- `make preflight` appends to the benchmark history files under `bench/`; commit those separately from the change ("bench: record the preflight run for ..."), so a reviewer can tell whether a baseline moved on purpose.
- Do not pipe a repo command into `tail` or `head`: a test worker or other grandchild that outlives the command keeps the pipe open, so the call looks hung. Redirect to a file under `build/` and read that (`make test > build/agent-logs/test.log 2>&1`).
- Run one test suite at a time per work directory: `scripts/test.sh` locks `$TR_WORK` (default `build/tests`) and refuses a second run; give a parallel run its own `TR_WORK`. Write long jobs' logs under `build/`, not `/tmp`, which some agent harnesses clear.
- Keep scripts and build files portable where it is cheap: POSIX `sh` under `#!/bin/sh`, no GNU-only flags (`sed -i`, `stat -c`, `date +%N`, `nproc`) where a portable form exists, and tools read from `config.mk`'s variables. Where something is genuinely Linux-only (the runtime, `/proc` measurements), make it skip or fail with a message saying so. The Makefiles need GNU make (`gmake` on the BSDs).

### Where the code lives

The compiler is `src/`, with `stdlib/`, `tools/zilc` and `tools/zbuild` around it; see "Repository layout" in the [README](../README.md).

`bootstrap/` holds the frozen seed compilers and accepts only narrow changes. `bootstrap/stage0-c/` takes correctness fixes, and small syntax or semantics alignments with `src/` that keep it able to build `bootstrap/stage1/` and pass its own suites, each with a regression test under `bootstrap/stage0-c/tests/fixed_bugs/` or in the functional suite. `bootstrap/stage1/` takes no hand edits, with two recorded exceptions: it changes by a re-pin (a newer snapshot that stage0-c can still build) or by a deliberate backport of a language feature the frozen compiler must parse, and `bootstrap/stage1/rt/runtime.s` follows `rt/runtime.s`, which the `runtimes` gate keeps byte-identical. Both directories contain a copy of most of `src/`, so make sure an edit lands outside them. See [`bootstrap/README.md`](../bootstrap/README.md).
