# The checked-program fuzzer

## What it is for

The fuzzer looks for programs that Zoril accepts but should not: a checked-code program that faults, miscompiles, or is accepted by Zoril while `rustc` rejects its Rust twin (the same program written in the syntax of the subset Zoril and Rust share). Its evidence has the form "a fixed budget of generated programs compiled and ran with none of these"; that supports the claims in [What Zoril Checks](../../doc/SAFETY.md) and does not prove them.

**How it is designed.** A Lua grammar builds a tree of types, places, expressions and statements, respecting types as it goes, so most programs can be written in both languages. The Rust twin is a separate translation of the same tree, not a file both compilers read. Lifetimes are deliberately not respected: two general rules (hand any address-like value to an address-taking helper, and let a borrow or a capturing closure outlive the block its referent lives in) produce the boundary shapes where holes arise. Each program is generated from a seed, so a finding reproduces and becomes a regression test. Each program carries tags for the features it uses, and a run reports which declared features it never generated.

**What it cannot reach.** The programs are small (about 30 lines), come from the subset Zoril and Rust share, use little of the standard library, never write `defer`, have `id<T>` as their only generic, use `i32` for every integer, and contain no `unsafe`, so the `unsafe` boundary is not fuzzed. [What Zoril Checks](../../doc/SAFETY.md) §5.2 states the limits in full.

**The records** below are the release-bar run, a shorter session on the released code, and the findings. The fuzz-record gates (`make test` runs them) check that the records describe the code in the tree.

## How a program is judged

`scripts/fuzz_safe.sh` generates programs from a grammar of the subset Zoril and Rust share, compiles and runs them through the real pipeline - the repository's `build/zoril` and `build/zilc`, then the **host** `qbe`, `as` and `ld`, which is what `config.mk`'s `BACKEND_BIN`/`ASSEMBLER_BIN`/`LINKER_BIN` name and what the released toolchain uses - and reads the result seven ways:

- **crash oracle** - any signal other than the `134` trap is a soundness bug. `134` is the deliberate `zoril_user_trap`; exit `0` is the expected outcome. A `zilc`/`qbe`/`as`/`ld` failure after the front end accepted the program counts too.
- **value canaries** - a generated program writes a known value into a stack slot or an arena allocation (`7 + i * 92` on loop iteration `i`, and a fresh `99` allocation after every `reset`/`reset_to`) and checks the value it reads back through a reference, slice or closure. A dangling read reads the _next_ occupant (99) instead of the value it was created with (7), and the program exits `92`. The page is still mapped, so the crash oracle alone can never see this.
- **drop accounting** - a value with a `Drop` impl increments `DROPS`, every construction increments `CONSTRUCTED`, and `main` exits `91` when they differ. A shallow copy dropped twice (a closure capture invoked twice, a `let` pattern that does not consume its source) is then a fault rather than a program that exits 0.
- **expected values** - the generator holds the tree it printed and evaluates it (Zoril's wrapping `i32`, the order the statements run in): every value the program reads through a reference, a holder, a tuple, an option or an array is folded into `chk = chk * 31 + v`, and the program exits `93` when `chk` is not the number computed here. That is a miscompile with no fault - a lost write, a wrong load, a wrong field offset - which neither the crash oracle nor the canaries can see. A program the interpreter cannot follow (a statement kind it has no rule for) carries no check; the manifest says `checked` or `unchecked:<why>`, and the totals count both (`vchecked`, `vunchecked`). The Rust twin is not changed. `make fuzz-prove` breaks a scratch compiler on purpose (unary minus lowered as bitwise not) and requires the oracle to report `value-fault 93` while the real compiler stays clean over the same seeds.
- **expected traps** - an index, a divisor or a shift count the program computes from its own values (`(a * 1 + b * 5 + ... + 5)`), after the checksum and the drop count. The generator knows whether it is out of range or zero, so the manifest says `trap=134` (an index out of range, a shift count of 32 or more) or `trap=136` (division or remainder by zero, `INT_MIN / -1`) or `trap=none`. The driver requires exactly that exit code: exit 0 or the other code is a `trap-fault` (a missing bounds check is one). The operand is read afterwards, because QBE removes a pure division nobody uses, and the trap with it.\n- **swarm testing** - each program enables a random half of the builders (the hole builders keep their own share of the stream); the manifest says `swarm=off:<names>` or `swarm=all`. `--swarm 0` on the generator draws from all of them again.\n- **the checked build** (`--checked`, on by default; `--no-checked` turns it off) - every program the unmarked build accepts is rebuilt through `zoril --checked` and run again. Its poison (`165`), double-drop trap (`134`) and faults (`139`) are faults too. The canaries stay: a scalar canary is the only signal for a hole whose write went to _live_ memory (probes 200/201), where the poison has nothing to find.
- **mode-diff** - the same program is also built the way a user builds it, with an installed `zbuild` (one staged `make install` per run, one cache per worker), and the two builds must agree: both refuse it with the same first diagnostic, or both accept it and the program exits with the same status and prints the same stdout (with `--checked`, the `zbuild` leg is checked too). A disagreement is a `[MODE-DIFF]` finding, filed like a fault, because one of the two modes is wrong. About a third of the compositional programs are written as several modules - their helpers, types and statics in an imported library module, whose name is drawn from every legal shape (`_lib`, `Lib`, `lib2`, a standard-library module's name) - and the fixed shapes of a type in one module with its `impl` in another, a private item named across modules, and a module whose name is not an identifier are in the mismatch stream and the templates; the Rust twin of such a program stays one file. It is on for the repository's own compilers and costs about twice the time per program (`--no-zbuild` turns it off).
- **differential oracle** - the same program is also emitted as Rust, and `rustc --emit=metadata` must accept it. A program Zoril _accepts_ that `rustc` rejects is a candidate unsoundness: Rust's borrow checker is the reference for the shared subset. `rustc` is optional; without it the runtime oracles still run. Arena programs use a lifetime shim (`ArenaVec<'a, T>` holds `&'a Arena`), so `rustc` rejects using an arena-tied value after `reset`; `reset_to` cannot be modelled that way, and a program marked `// fuzz: no-rustc-diff` is not sent to `rustc`.
- **the opposite disagreement**, logged rather than judged: a program Zoril _rejects_ that `rustc` accepts. When Zoril's complaint is one of its borrow/region messages the program is an **infer-diff** - the running measure of how much Zoril's borrow inference cannot express without annotations. When the complaint is a plain type error it is a **gen-bug**: the generator's own fault, and it should stay at zero.

The fuzzer compiles through the shipping pipeline (QBE, `as`, `ld`) unless `QBE_BIN` is pointed at another QBE. Every run prints the pipeline it will use (`fuzz: pipeline: ...`), so a log says which components produced it, and the `fuzz-record` gate fails a default that is not the shipping one.

## The generator

`scripts/fuzz/gen.lua`, in Lua because that is what the repo's other generators are written in (`bench/*.lua`) and nothing else here needs Python. It builds a _tree_ - types, places, expressions, statements, reference-forwarding helpers, generic `id`, structs with reference fields, `Option<&T>`, `Box`, arrays, slices, arenas, closures, function pointers, `while`, `match`/`if let`, pattern destructuring - and prints both languages from it. `--mode calibration` emits one self-contained program per known hole. Every hole is also an ordinary builder, with random values, indices, loop counts and fresh names, sampled by the same grammar as everything else; a program that carries one is marked `// fuzz: calibration <id>` and reported under that hole's row rather than filed as a finding. `--holes 1` makes a `mix` run emit the fixed calibration stream once, in its own `calibration/` directory, instead of appending a hole to every generated program.

Every hole snippet is wrapped in `if hole_switch { ... }`; `hole_switch` is `argc > 1` in the Zoril program and `std::env::args().count() > 1` in the Rust twin. The driver runs a marked program twice, once with `hole-on` and once without: only a fault that disappears with the switch off belongs to the hole.

Types are respected as the tree is built, so the corpus is mostly programs both compilers can talk about. Lifetimes are _not_ guaranteed: that is the point. Two general rules produce the boundary shapes, and neither names a hole:

- the **loose operand** rule hands any address-like value in scope (reference, `Box`, raw pointer) to an address-taking helper, which is how a borrow/box/raw confusion arises from composition;
- the **boundary composition** rule lets a borrow or a capturing closure outlive the block its referent lives in.

Ten hand-written templates form a fixed seed set (`--mode templates`, or `both` to mix). Deterministic from `(--seed, --count)` through a small LCG, not `math.random`, so a finding reproduces on any Lua version and can become a regression test.

Every program prints one manifest line of feature tags; the driver turns them into a coverage report and lists what was never generated. `--features` prints the list the report is measured against.

    make fuzz-short     # 100 programs, in the preflight gate
    make fuzz-calibrate # one program per known hole; prints the oracle table below
    make fuzz           # 3200 programs, on demand; files findings in bench/fuzz/findings/
    make fuzz-session SEEDS=1-20000   # your own session; see "Fuzzing" in doc/developer_guide.md (also fuzz-start, -status, -stop, -summary, and the release-bar targets)
    ./scripts/fuzz_safe.sh --seeds 1-40 --count 6 --mode both --keep   # --keep: leave the run's log, its
                                                                      # coverage and any finding in place
    ./scripts/fuzz_safe.sh --reverify      # what the record holds, and what each pair is now

A program's scratch is deleted as soon as it has been classified, and a seed's directory with it unless that seed raised a finding, whose pair of sources is copied out of it at the end. `--keep` therefore keeps the run's log, its merged coverage and the pair of any finding - not one artifact per program, which is what a budget run of millions of programs would drown the filesystem in.

A run whose result will be cited - `--record-findings` or `--release` - refuses to start unless `build/zoril` and `build/zilc` both report the hash of `HEAD` (no `-dirty`), the working tree is clean, and `rustc` is present for the differential oracle: that oracle raised two of the findings below, so a budget recorded without it would not support the sentence it is cited for. (`FUZZ_RUSTC` names the oracle's path, or an empty value for "there is none"; otherwise `rustc` is looked up on `PATH`.) A run that records nothing keeps the old behaviour - no `rustc` prints `[SKIP] fuzz: rustc not found - running the crash oracle only` and the runtime oracles still run, which is what keeps `make fuzz-short` useful on a machine without Rust. Every run prints its pipeline and the oracles that were on (`fuzz: pipeline:` lines: the two compilers' `--version` strings, then the `rustc` path and version, the checked build, the canaries and the drop accounting), so a log says what produced it. `make fuzz-release FUZZ_ARGS='--jobs 16 --seeds 1-N --count 8 --mode mix --out build/fuzz/release-bar'` rebuilds both compilers first and then runs with `--release`; a budget run is launched through it.

A `--release` run also **refuses a calibration row that is `still open`** - exit status 1, with the row named. Known-hole faults are reported apart from the search and never touch the exit status by design; that is what lets a run pass while a row is open and fail on anything new. But every calibration row has been fixed, so a marked program that faults with its hole switched on and is accepted with it off is a regression rather than a known state. The message points at `make fuzz-calibrate` and at the working rule for a new hole, and it is raised after the run's totals line so a parallel worker still contributes its numbers.

A **fault**, in the terms the summary counts, is any of: a signal; exit `91` (the drops did not match the constructions), `92` (a canary read dead storage) or `165` (the checked build's poison); a `134` **from the checked build** (its double-drop trap); a marked program that faults with its hole switched off (`knownblind`, which must be 0); a `zilc`/`qbe`/`as`/`ld` failure after the front end accepted the program; or a `[CANDIDATE]`. A `134` from the unmarked build is the expected bounds or allocation trap, and is not a fault.

A run files its candidates in `bench/fuzz/findings/` - one minimised pair per finding, each pair named in that directory's README - only when it is told where the record is: `--record-findings`, `--findings DIR`, or `FUZZ_FINDINGS` in the environment. Without one of those it copies nothing and says where the pair stayed, which is what keeps a test run's own scratch out of the record; the `fuzz-record` gate (`make test`) checks exactly that, along with the classification below.

A candidate is classified through `intended_differences.txt`: a line `<rustc code> <feature tag> <expiry YYYY-MM-DD>` for a difference that has been _decided_, with the reason in comments. Anything unclassified fails the run; an entry without an expiry fails it too; an entry past its expiry fails it louder, because a difference nobody has decided is not a difference, it is an open finding.

## Two process rules for findings

1. **Re-verify before recording.** A finding is minimised by deleting lines _and re-running both oracles_ until it is small, and only then written down: the program quoted in a task must still reproduce. A minimisation that drops the line that mattered leaves a program the compiler rejects for another reason. `--reverify` re-runs every pair in the record against both oracles and reports what each one is now: **still open** (Zoril takes it or traps it, `rustc` rejects the twin), **fixed** (Zoril refuses it now - delete the pair and name the test that pins the fix in the README), **never a disagreement** (`rustc` accepts the twin too), or **to look at** (half a pair, or the toolchain broke on it). It fails on a pair that is still open, a pair it cannot classify, and a pair the record's README does not name; it passes over the fixed ones, which are a to-do rather than a hole. Reporting only what Zoril still accepts is what let 30 pairs that were never findings sit in the record while this check said "0 recorded finding(s) still open", so every pair gets a line. 1b. **Clear a shape on an owning type, never on a `Copy` type alone.** Two holes in a row looked harmless when measured with an `i32` and turned out to be use after free with an `Arena` or a `Box` - ownership is where the damage is, and a `Copy` value cannot show it. Every candidate is checked with a value that owns a resource (a `Box`, an `Arena`, a struct with a `Drop` field) before it is called benign.
2. **Never allowlist an undecided candidate.** An entry is a decision with a reason and an expiry. If nobody has decided, the gate fails - that is the only thing that keeps a hole from being filed as a curiosity. If the decision really has to wait, quarantine it with a date and the reason it is waiting, and decide or fix it when the date comes.

## Blind calibration

Blind calibration measures whether the _grammar_ alone reaches a known hole. With the fix reverted and no template or rule aimed at the hole, it counts programs in the order a run reaches them (`--seeds 1-60 --count 8`):

- **A borrow where an owned `Box` is expected**
  - First found at program: **22** (seed 3, program 5)
  - How it showed: `[CANDIDATE]`, `rustc` `E0308`; one program later in the run segfaulted (`signal 139`)
- **A closure capture outliving its referent's block**
  - First found at program: **73** (seed 10, program 0)
  - How it showed: `[CANDIDATE]`, `rustc` rejects; 22 of 31 closure-escape programs were accepted by the reverted Zoril
- **Either, on the current tree**
  - First found at program: never
  - How it showed: 0 unclassified candidates, 22/22 features covered

Reproducing the closure hole needs the whole-tree revert, not only `src/check_zir.zrl`. Its shapes can be masked by programs that trip Zoril's aliasing rule first, which is why the generator stays off a place while a live `&mut` points at it.

## Calibration against the known holes

The calibration stream has 26 rows: 22 checked-code holes grouped into five mechanisms (Solutions A-E), two further routes of Solution C (`&arr[0]` and `&t.0` in `mark_ref_place`), and the buffer-escape and `fn`-value store routes. `lua scripts/fuzz/gen.lua --mode calibration` emits one self-contained program per hole: nothing else is in the program, so a hole cannot be masked by another builder, and each program writes the value canary or increments the drop counter that makes a silent memory error observable. `make fuzz-calibrate` runs all 26 with the `hole-on` switch and prints which oracle saw each one.

The same shapes are part of the ordinary grammar (`--mode grammar` and `--mode both`) as randomized builders, and `--mode mix` additionally emits the 26 fixed calibration programs once per run. Every program carrying one is marked `// fuzz: calibration <id>`, and the driver runs it twice: with the guarded hole switched on (`hole-on`) and off. A fault with the switch on that disappears with it off is reported under the hole's row (`[KNOWN-HOLE] <id>: still open (...)`, `not reached (...)`, `not reproduced (...)`, or `fixed (...)` for a refused _calibration_ program), counted apart from the search, and never filed as a finding. A fault that survives the switch being off is **not** the hole: it is a finding, counted in `knownblind` (which must stay 0) and filed like any other. A fault in an unmarked program is a finding too, and fails the run. `make fuzz-short` therefore passes while only known holes fault, and fails on anything new. A refused random program that happens to carry a hole marker is `not reached`, not `fixed`: an earlier statement can make the program invalid before the hole runs, and only a refused calibration program is evidence that the mechanism landed.

**The fixed state.** Every calibration row is closed, and the calibration stream is now a regression check rather than a measurement of open holes: `make fuzz-calibrate` requires each row to be in the state tabled below - refused by the compiler, or accepted and exiting 0 after exactly one drop. A program that stops being refused is a reopened hole (`[REOPENED]`); one that exits non-zero again is a regression in closure or pattern ownership (`[CHANGED]` / `[CHECKED]`). The Rust twin is read as before: `reject` for the refused programs and `accept` for the two drop-count ones.

| #  | Calibration id                  | Probe | Fixed state (regression check) | `rustc` twin | Fixed by              |
| -- | ------------------------------- | ----- | ------------------------------ | ------------ | --------------------- |
| 1  | `index_mut_borrow`              | 201   | `compile_reject`               | reject       | Solution A            |
| 2  | `slice_index_mut_borrow`        | 200   | `compile_reject`               | reject       | Solution A            |
| 3  | `index_compound_assign`         | -     | `compile_reject`               | reject       | Solution A            |
| 4  | `arena_index_reset`             | 202   | `compile_reject`               | reject       | Solution A            |
| 5  | `arena_branch_reset`            | 203   | `compile_reject`               | reject       | Solution B            |
| 6  | `arena_loop_mark_reset_to`      | 204   | `compile_reject`               | reject       | Solution B            |
| 7  | `branch_reassign_loop`          | 205   | `compile_reject`               | reject       | Solution B            |
| 8  | `arena_box_slice_reset`         | 206   | `compile_reject`               | reject       | Solution B            |
| 9  | `arena_callptr_reset_to`        | 207   | `compile_reject`               | reject       | Solution B            |
| 10 | `arena_closure_ret_reset`       | 208   | `compile_reject`               | reject       | Solution B            |
| 11 | `enum_payload_block_escape`     | 209   | `compile_reject`               | reject       | Solution B            |
| 12 | `arena_repeat_reset`            | 210   | `compile_reject`               | reject       | Solution B            |
| 13 | `ret_storage_local_alias`       | 211   | `compile_reject`               | reject       | Solution C            |
| 14 | `ret_storage_struct_wrap`       | 212   | `compile_reject`               | reject       | Solution C            |
| 15 | `same_type_borrow_loop_escape`  | 220   | `compile_reject`               | reject       | Solution C            |
| 16 | `closure_capture_multiple_drop` | 213   | accept, exit 0 (one drop)      | **accept**   | Solution D            |
| 17 | `loop_closure_env_escape`       | 214   | `compile_reject`               | reject       | Solution D            |
| 18 | `let_destructure_double_drop`   | 215   | accept, exit 0 (one drop)      | **accept**   | Solution E            |
| 19 | `premark_byvalue_reset_to`      | 219   | `compile_reject`               | reject       | Solution B            |
| 20 | `raw_tuple_pattern_deref`       | 217   | `compile_reject`               | reject       | Solution E            |
| 21 | `raw_enum_pattern_deref`        | 216   | `compile_reject`               | reject       | Solution E            |
| 22 | `owning_move_before_borrow_use` | 408   | `compile_reject`               | reject       | operand move order    |
| 23 | `ret_storage_index_ref`         | -     | `compile_reject`               | reject       | Solution C            |
| 24 | `ret_storage_tuple_field_ref`   | -     | `compile_reject`               | reject       | Solution C            |
| 25 | `local_buffer_view_drop`        | 283   | `compile_reject`               | reject       | buffer-escape rule    |
| 26 | `fn_value_store_stack`          | 293   | `compile_reject`               | reject       | `fn`-value store rule |

Rows 16 and 18 were _valid Rust programs_ all along: their defect was a drop count, not a borrow, so `rustc` accepting the twin is the correct answer and the runtime oracle (one drop, exit 0) is the regression check. A checked-build column is not repeated here: with the fixes, `--checked` refuses the same programs and exits 0 for rows 16 and 18, so it has no poison or trap left to record.

When a fix changes a row, update this table and `scripts/fuzz_calibrate.sh` together; a row whose state differs from the table fails `make fuzz-calibrate`, which `make test` and `make preflight` run.

## The release-bar run (2026-10-26/27)

The release bar is a fixed budget of programs that **compiled and ran** (the crash oracle's sample): **2,500,000**, a budget the project set for the alpha. The run used the compositional generator in `--mode mix` (the main stream, the fixed calibration programs and the mismatch stream) on the compiler sources named by the fingerprint below, through the shipping pipeline (`build/zoril` -> `build/zilc` -> `qbe` -> `as` -> `ld`), with every oracle on: the `rustc` differential oracle, the checked build, the value canaries, the drop accounting, the expected-value oracle and runtime trap checks.

Two machine-readable lines make the record checkable rather than remembered. The **fingerprint** is one content hash per compiler-source directory (`src/`, `stdlib/`, `tools/zilc/`, `tools/zbuild/`, `rt/`; `zbuild` is part of the fuzzed pipeline, so a record that covers it carries all five; the release-bar record below names four, because its run did not use `zbuild`, and `scripts/check_fuzz_fresh.sh` reports it as naming no hash for `tools/zbuild`. A record with the fifth hash covers whole-program and separate compilation, of single-module and multi-module programs), taken over that directory's files **excluding Markdown** (`scripts/lib/fuzz_fresh.sh` computes it; the run prints the same line). A document is not a compiler input, so editing `rt/README.md`, `tools/zilc/README.md` or any other page leaves the record fresh, while adding, removing, renaming or editing a code file changes its directory's hash. `scripts/check_fuzz_fresh.sh` compares the record's hashes with the working tree and names the directory whose code differs, while the recording step of a release runs the same check with `--strict`, which refuses while they differ. The **headline** is the figure every page that cites this record must quote, and the same gate checks that they do (`doc/SAFETY.md` §7 requires it in the same commit as the record).

fingerprint: src=04b389ba8541f70f8cfc02413aec882b15208d2ce68cc35577242b44fc26e170 stdlib=3a2baf7989471d2e670e476c9ff00579a1f0e9f127aaa75abaaad50e11f293e2 tools/zilc=6cb7e9022111c38a4bebe6b55605b1053672bcd2b34ff75c015b9b3e12e80ef8 rt=e73757dc5dda9d36520c45fd2f06a36755f9c71bb7b43d1e5379f71b5ca7ce31

It was taken with the earlier `git ls-tree` hash and cannot be recomputed in this repository; the next release-bar run replaces both records.

headline: 2638155 programs compiled and ran

Launched as `make fuzz-release-start SEEDS=1-882000 RAN=2500000` on the sources the fingerprint below names, from 2026-10-26T13:29:53Z to 2026-10-27T07:00:56Z.

- **Compiler:** the release build of those sources, through the shipping pipeline
- **Oracles:** `rustc` 1.99.1, checked build, canaries, drop accounting, expected-value oracle, runtime trap checks, all on
- **Seeds:** 1 - 882,000 (x 8), over 16 workers
- **Programs generated:** **7,056,025** in the main stream
- **Compiled and ran:** **2,638,155** (37.4%), 5.5% over the bar
- **Rejected by Zoril:** 1,967,783
- **Traps:** 48,239 (39,748 exit 134, 8,491 exit 136)
- **Faults:** **0** (no signal other than expected traps, no canary or drop-count mismatch, no poison read, no value checksum mismatch, no timeout)
- **`rustc` candidates:** **0**
- **Generator bugs (`[GEN-BUG]`):** 0
- **Expired allowlist entries:** 0
- **Mismatch stream:** 17 programs, in worker 0: 15 refused, 2 known-hole programs (`raw_tuple_pattern_deref`, `raw_enum_pattern_deref`), refused and counted under known holes; **0 accepted**
- **Known holes (reported apart from the search):** 2,450,089 marked programs: **0 still open**, 23 fixed, 2,344,839 not reached, **0 faulted with the switch off**
- **Expected-value oracle:** 4,960,253 programs carried a checksum (exit 93 on a mismatch), 332,180 could not be followed by the generator's interpreter; 0 mismatches
- **Listed differences (`[DIFF]`):** **33,141**, all `E0503`
- **Audited `[DIFF]` sample:** **1,005/1,005** decided shape
- **Infer-diffs (`[INFER-DIFF]`):** 8,949
- **Value mix:** 15,165,311 of 41,655,480 values own something (36%)
- **Feature coverage:** **80/80 features**
- **Wall time:** **17 h 31 min** (16 workers; about 111 generated and 41 compiled-and-ran programs a second)

Notes on the record:

- **Zero faults and zero candidates:** no checked-code crash, signal other than expected traps, or oracle mismatch occurred across the 2,638,155 programs that compiled and ran, and no program Zoril accepted was flagged as an unclassified candidate by the `rustc` differential oracle.
- **Listed differences:** exactly one entry was active in `intended_differences.txt`: `E0503 write-through-mut-ref 2027-01-12`, and every `[DIFF]` line names only `E0503`. An audit sample of every 33rd `[DIFF]` program - 1,005 of them, 60 to 66 from each of the 16 workers, seeds 48 to 881,695 - was regenerated from the worker logs' seeds with the run's generator: each one is accepted by Zoril (exiting 0 or with the expected runtime trap), and its twin carries exactly one `rustc` error, `E0503`, on a `*rmN = x;` line with `rmN` unused afterwards. The sample found no masked error.
- **Runtime traps:** 48,239 programs trapped on bounds checks (39,748 exit 134) or division/modulo by zero (8,491 exit 136), exactly matching the exit codes predicted by the generator's trap analyzer.
- **Expected-value oracle:** 4,960,253 programs carried a checksum evaluated ahead of time by the generator's interpreter; zero value-faults occurred. 332,180 programs had constructs the interpreter could not evaluate (unfolded loops, etc.) and were recorded as unchecked.
- **Coverage report:** all 80 declared generator features were generated during the run.
- **Infer-diffs:** Zoril's borrow check rejected 8,949 programs `rustc` accepts; a rejection is a usability gap, not a safety finding, and the classes were not analysed.

## The short session on the launched code

The release bar above was met on earlier code: its fingerprint differs from this one. This shorter `--release` session ran on the code released here, with every oracle of the release-bar run and the mode-diff reading on. It is a short session, not the release bar; a full release-bar run on this code is planned soon, and when it is recorded it replaces this section.

entry: short-session

fingerprint: src=739469d75be0826ba7b5655a44353b7c44b0da2a25d413f94fa4f702b6fdadfd stdlib=680bd150220da9d2dad342a370dd920038dbee90f2a37e4efc8bd2a7240940e0 tools/zilc=25ab204e8ac8478c685cccb1c82bb7e3ad73b97a5e839381fdf7af80b6b73c4f tools/zbuild=5664b1d790a3a42c2d7f55e2a31791d948a61a291f94e85e39c543c882d8da2b rt=de1a3469762ab9ba50a0918cac4f6fa5f6807aeeecd9f47595bcab8aa82b4afb

headline: 755772 programs compiled and ran

Launched as `make fuzz-session SEEDS=1-247000 RELEASE=1`.

- **Seeds:** 1 - 247,000 (x 8), over 16 workers
- **Programs generated:** **1,976,026** in the main stream
- **Compiled and ran:** **755,772** (38.2%)
- **Rejected by Zoril:** 533,501
- **Traps:** 13,540 (11,237 with exit 134, 2,303 with exit 136)
- **Faults:** **0**
- **`rustc` candidates:** **0**
- **Generator bugs (`[GEN-BUG]`):** 0
- **Expired allowlist entries:** 0
- **Mismatch stream:** 24 programs, 21 refused, **0 accepted**
- **Known holes (reported apart from the search):** 686,756 marked programs: **0 still open**, 24 fixed, 656,980 not reached, **0 faulted with the switch off**
- **Expected-value oracle:** 1,388,126 programs carried a checksum (exit 93 on a mismatch), 93,833 could not be followed by the generator's interpreter
- **Mode-diff (whole-program vs `zbuild`):** 2,731,822 builds compared, **0 disagreements**
- **Listed differences (`[DIFF]`):** **8,898**
- **Infer-diffs (`[INFER-DIFF]`):** 2,446
- **Value mix:** 4,182,336 of 11,485,453 values own something (36%)
- **Feature coverage:** **94/94 features**
- **Wall time:** **7h14m** (16 workers; about 75 generated and 28 compiled-and-ran programs a second)

## Findings

A minimised pair is filed in `bench/fuzz/findings/` and named in that directory's README while it is open; `--reverify` fails on a pair the README does not name. Every finding so far is fixed with the program pinned as a test, so the record holds nothing but its README:

- **blind calibration program 22**
  - Outcome: A borrow accepted where an owned `Box` is expected; the callee frees memory the caller owns (`must_munmap`, exit 134)
  - Where it stands: Fixed; pinned by `tests/error_reporting/err_box_{borrow_passed_as_owned,moved_into_borrow,arena_consumed_as_borrow}.zrl`, probe 178 and mutation M118
- **a write through a `&mut` that ended its own borrow**
  - Outcome: A write through a `&mut` ended that reference's own borrow, so a shared borrow aliased it: Zoril accepted, `rustc` refused (`E0502`/`E0503`); with a `Drop` value the program segfaulted (exit 139)
  - Where it stands: **Fixed**: the guard in `check_assign`, four error tests, an accepted twin, probe 179 and mutation M119. Its allowlist entries are removed.
- **grammar seed 23 program 4**
  - Outcome: A bare block statement followed by `*r = 5` parsed as `({ }) * r = 5`; unit times a pointer lowered with `NO_SSA` as an operand and the store went through a wild address (exit 139).
  - Where it stands: **Fixed**: a bare block statement ends at its `}`, assignment targets must be places, operator operands must be numbers, and both IL readers reject an undefined operand or a non-pointer store address. Pinned by `tests/language/memory/write_through_mut_after_inner_block{,_drop}.zrl`, probes 221-228 and `tests/zilc/{undefined_operand,store_non_pointer_address}.zil`.

- **a bare read through a `&mut` to the same place**
  - Outcome: `*rm = x`, where that write is the `&mut`'s last use, is accepted, and Rust refuses it (`E0503`)
  - Where it stands: Decided, not open: the read happens before the write and no borrow is live afterwards to observe it (with the `&mut` live afterwards the read is refused). The measurement and the reason are in `intended_differences.txt`, entry `E0503 write-through-mut-ref`, which is re-measured before it expires.

## What the generator reaches, and where it is biased

Owning types are where the damage is, so the generator biases toward them: a `Box`, an arena handle and a struct with a `Drop` field are in the value mix as much as `i32`.

It reaches arrays, slices, indexing (`&arr[i]`, `&mut arr[i]`, `arr[i] += v`), `[expr; N]`, arena `push`/`as_slice`/`reset`/`mark`/`reset_to`, branch-conditional and loop-carried borrows, reference-returning helpers (alias, struct wrap, nested `Link`), closures that capture owning values and return captures, function-pointer calls, pattern destructuring and borrowed-enum payloads. All known holes except `owning_move_before_borrow_use` (a calibration row only) are ordinary builders, so `--mode grammar` alone reaches most of the declared feature list and `--mode mix` reaches all of it with the fixed calibration stream; `--features` prints the list a run is measured against.

The remaining bias is the shape of the _values_: all integers are `i32`, so a hole that only shows up with a wider or signed element type is out of reach. The allowlist stays short: one entry per difference someone has read.
