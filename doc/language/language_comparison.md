# Zoril alongside Rust, Zig, and Hare — measurements and context

This document presents measured execution speed, compile throughput, and safety properties for Zoril alongside Rust, Zig, Hare, and C. These languages have different goals and very different maturity — Zoril is an early alpha — so the tables describe current trade-offs, not a ranking.

## How to read this

This document separates empirical measurements from language specification facts:

- **Measured** — executable wall-times, compile times, peak RSS, and safety probes were compiled and executed on this machine on Linux x86_64 across all installed toolchains (Zoril, Zig 0.16.0, Rustc 1.99.0 / Cargo, Hare 0.26.0.1, GCC 16, Clang 22.1.8). Every cell in the performance and throughput tables below is an empirical measurement produced by `scripts/bench_cross_lang.sh`.
- **Stated** — semantic and type-system guarantees summarized from the other languages' documentation (e.g. Rust borrow-checker semantics, Zig GPA runtime tracking, Hare nullable types). In the safety table below, Zoril cells are backed by probe tests in this repository; the other cells are our summary of each language's documented behaviour.

## Memory safety

Zoril column is measured; the rest is stated. "Trap" means the process aborts deterministically rather than corrupting memory. The other columns summarize each language's documented model as we understand it and may lag behind recent releases; corrections are welcome. Where a language leaves something unchecked, that is usually a deliberate design choice (for example, manual memory management in Hare), not an oversight.

What the Zoril column does not carry is the rest of the boundary. Each row says what happens to a program without `unsafe`; what is checked at compile time, what only when the program runs, and what is left to the programmer is stated tier by tier in [What Zoril Checks](../SAFETY.md), and every row here is backed by a probe or test named in [`doc/spec/safety_model.md`](../spec/safety_model.md).

- **Use after move**
  - Zoril (code without `unsafe`): compile error
  - Rust (safe, debug): compile error
  - Zig (Debug/ReleaseSafe): n/a — no move checking
  - Hare: n/a
- **Double free / double drop**
  - Zoril (code without `unsafe`): compile error
  - Rust (safe, debug): compile error
  - Zig (Debug/ReleaseSafe): runtime detect (GPA)
  - Hare: not checked
- **Use after drop**
  - Zoril (code without `unsafe`): compile error
  - Rust (safe, debug): compile error
  - Zig (Debug/ReleaseSafe): runtime detect (GPA)
  - Hare: not checked
- **Dangling stack ptr — direct return**
  - Zoril (code without `unsafe`): compile error
  - Rust (safe, debug): compile error
  - Zig (Debug/ReleaseSafe): not checked
  - Hare: not checked
- **Dangling stack ptr — behind a cast**
  - Zoril (code without `unsafe`): compile error
  - Rust (safe, debug): compile error
  - Zig (Debug/ReleaseSafe): not checked
  - Hare: not checked
- **Dangling stack ptr — via callee**
  - Zoril (code without `unsafe`): compile error
  - Rust (safe, debug): compile error
  - Zig (Debug/ReleaseSafe): not checked
  - Hare: not checked
- **OOB array read**
  - Zoril (code without `unsafe`): trap (134)
  - Rust (safe, debug): panic
  - Zig (Debug/ReleaseSafe): panic
  - Hare: trap
- **OOB slice read**
  - Zoril (code without `unsafe`): trap (134)
  - Rust (safe, debug): panic
  - Zig (Debug/ReleaseSafe): panic
  - Hare: trap
- **OOB array write**
  - Zoril (code without `unsafe`): trap (134)
  - Rust (safe, debug): panic
  - Zig (Debug/ReleaseSafe): panic
  - Hare: trap
- **OOB slice write**
  - Zoril (code without `unsafe`): trap (134)
  - Rust (safe, debug): panic
  - Zig (Debug/ReleaseSafe): panic
  - Hare: trap
- **Raw-pointer indexing**
  - Zoril (code without `unsafe`): `unsafe` only
  - Rust (safe, debug): `unsafe` only
  - Zig (Debug/ReleaseSafe): unchecked
  - Hare: unchecked
- **Pointer forged from integer**
  - Zoril (code without `unsafe`): `unsafe` only
  - Rust (safe, debug): `unsafe` only
  - Zig (Debug/ReleaseSafe): allowed
  - Hare: allowed
- **Null dereference**
  - Zoril (code without `unsafe`): `unsafe` only
  - Rust (safe, debug): unrepresentable
  - Zig (Debug/ReleaseSafe): unrepresentable (optionals)
  - Hare: nullable types, checked
- **Signed integer overflow**
  - Zoril (code without `unsafe`): wraps _(by design)_
  - Rust (safe, debug): panics (debug)
  - Zig (Debug/ReleaseSafe): traps
  - Hare: wraps
- **Data races**
  - Zoril (code without `unsafe`): n/a — no concurrency
  - Rust (safe, debug): compile error
  - Zig (Debug/ReleaseSafe): not checked
  - Hare: not checked

### Understanding Build Configurations Across Languages

**The safety table above and the performance tables below reflect different build configurations across languages.** Each compiler makes deliberate design trade-offs between compile-time checks, runtime verification, and execution performance:

- **Rust**
  - Safe configuration: `rustc` debug — overflow panics (exit 101)
  - Optimized / shipping configuration: `rustc -O` — overflow wraps, printed `-2147483648`, exit 0
  - Measured difference: overflow checking is disabled in release
- **Zig**
  - Safe configuration: Debug / ReleaseSafe — OOB read traps (134)
  - Optimized / shipping configuration: ReleaseFast — OOB read succeeds, exit 0
  - Measured difference: bounds checking is disabled in ReleaseFast
- **Hare**
  - Safe configuration: one configuration
  - Optimized / shipping configuration: same
  - Measured difference: bounds checks active either way (134)

The safety column for Rust reflects its debug behavior, while the executable-speed and throughput tables benchmark `rustc -O`. Similarly, the safety column for Zig reflects Debug/ReleaseSafe, while the benchmarks use ReleaseFast.

**Zoril maintains a uniform safety profile across all builds.** Bounds checks on arrays and slices remain permanent and active across all configurations. As measured elsewhere in this document, Zoril's bounds checks compile to _byte-identical machine code_ to the unchecked equivalent when the loop guard dominates the index - a throughput cost of zero in the shapes measured so far, not a claim that every check is free.

The corollary for Zoril's own gaps is that they are equally unconditional: without alternative build modes, language and compiler soundness must be maintained rigorously.

### Mandatory Bounds Checking on Assignment and Cast Operations

Zoril enforces bounds checking uniformly across both read and write projections:

```zoril,wrap
let mut a: [i64; 4] = [0 as i64; 4];
let i: usize = 100;
a[i] = 1234 as i64;   // traps (exit 134)
return a[i] as i32;   // traps (exit 134)
```

Assignment targets retain their `Index` projection to route through `resolve_place_addr`, and `IndexAddr` rvalues emit bounds checks. Both array and slice stores out of bounds deterministically trap with exit code 134 (§11.2.3). Similarly, region escape analysis tracks stack provenance (`points_to_stack`) through `Cast`, `Move`, `Add`, and slice instructions: the compiler rejects any reference to a local that outlives its frame ([`05_dangling_stack_direct.zrl`](../../bench/safety_matrix/probes/05_dangling_stack_direct.zrl), [`06_dangling_stack_cast.zrl`](../../bench/safety_matrix/probes/06_dangling_stack_cast.zrl), [`07_dangling_stack_callee.zrl`](../../bench/safety_matrix/probes/07_dangling_stack_callee.zrl)).

## Performance

Measured on this machine (`scripts/bench_cross_lang.sh --update-doc`). C reference points included because they bracket the achievable range: gcc `-O0` is roughly "no optimizer", gcc/clang `-O2` is production codegen.

### Executable speed

Best of 3 runs.

| Benchmark                    | Zoril      | gcc -O0 | gcc -O2 | clang -O2 | Zig (ReleaseFast) | Rust (-O) | Hare   |
| ---------------------------- | ---------- | ------- | ------- | --------- | ----------------- | --------- | ------ |
| `fib(38)` ×3, call-heavy     | **732 ms** | 749 ms  | 187 ms  | 148 ms    | 130 ms            | 132 ms    | 690 ms |
| 4096-elem array loop ×500000 | **726 ms** | 4210 ms | 145 ms  | 133 ms    | 537 ms            | 133 ms    | 959 ms |

Zoril runs at gcc `-O0`'s speed on call-heavy code and well ahead of it on the loop: **3.9× (`fib`) to 5.0× (array loop) slower than gcc `-O2`** here, and 3.8-3.9× on the regression gate's interleaved measurement. That gap comes from the backend, not from safety checks: QBE deliberately keeps its optimizer small (it aims for roughly 70% of the performance of an industrial optimizing compiler in 10% of the code), and Zoril inherits that trade-off.

[`doc/zero_overhead.md`](../zero_overhead.md) splits the gap over six workloads by also compiling the C through cproc, a C compiler on the same QBE backend: C on QBE is already 2.28x gcc -O2 (geometric mean), and Zoril's own lowering is within 1.05x of C on QBE.

**Bounds checking is not what costs this.** The same array loop written with raw pointers (`bench/cross_lang/array_loop/array_loop_ptr.zrl`), which skips bounds checking entirely, compiles to **byte-identical machine code** (`cmp -s` confirms `array_loop.s` and `array_loop_ptr.s` are byte-identical). Any timing variation between them (726 ms checked vs 770 ms raw pointer) is pure run-to-run system noise on identical binaries. Zoril's inductive condition analysis (`src/index_facts.zrl`) elides the bounds check because the loop guard `while i < 4096` dominates the array access, leaving literally **zero instructions** of checking overhead in the binary. Safety is not the bottleneck; QBE's codegen is.

### Compile time and memory

- **`build/zoril` compiling its own source → ZIL**
  - Time: **2.02 s**
  - Peak RSS: **445.0 MB** (~11.4 MB/kLOC on 39,144 LOC; median of 5)
- **Full self-host rebuild pipeline (`zoril` + `zilc` + `qbe` + `as` + `ld`)**
  - Time: **~10–15 s**
  - Peak RSS: —

In whole-program compilation mode, all source files merge into a single `ILModule`, scaling at ~10–12 MB/kLOC (~33 MB for a 2,931-LOC project, ~445 MB for the ~39k-LOC compiler itself). To support fast local development loops, Zoril provides `tools/zbuild`, which implements modular separate compilation and interface hashing to deliver sub-100ms incremental builds (**12 ms** touch rebuild, **26 ms** edit rebuild on the 2,931-LOC benchmark project; **63 ms** touch, **92 ms** edit on the 33,706-LOC project), with peak memory bounded by the largest single-module compilation step (~15 MB peak RSS at 2,931 LOC, ~192 MB at 33,706 LOC).

### Application Performance: an Example JSON Tool

As part of validating the safety model against real-world application code outside the compiler ([`unsafe_policy.md` §4](../spec/unsafe_policy.md#4-the-application-boundary)), an example CLI JSON tool written in Zoril (not yet published) provides an end-to-end benchmark for non-compiler workloads (RFC 8259 lexing, recursive descent DOM construction, JSONPath queries, schema validation, and formatting). All figures below come from its benchmark script, run on deterministic generated test datasets.

| Metric                             | Measurement                   | Context                                                           |
| ---------------------------------- | ----------------------------- | ----------------------------------------------------------------- |
| **Application non-comment LOC**    | **1,992 LOC** (9 modules)     | RFC 8259 parser, query engine, schema validator, stream processor |
| **Marker density**                 | **0.00%**                     | Zero `unsafe { }` blocks (gated)                                  |
| **Clean compiler compile time**    | **537 ms** (36.6 MB peak RSS) | Front-end compile: `src/*.zrl` → textual ZIL                      |
| **Full binary build pipeline**     | **4780 ms**                   | Full toolchain: zoril + zilc + qbe + as + ld                      |
| **DOM Parsing & Query Throughput** | **103 ms** (30.1 MB peak RSS) | 1.8 MB document, 20,000 nested records parsed + query evaluated   |

### Multi-file project & incremental rebuild (Four Axes)

To evaluate compiler throughput at scale, every language compiles the same generated multi-module computation: the module and function counts in the table's first columns are identical, and LOC differs by at most 1.3x because a generated function is 9-12 lines depending on the language. Earlier revisions scaled each language to a ~10s clean build instead, which benchmarked Zoril on a project 4-26x smaller than the others; the size is equal now and stated beside every number. This displays the throughput hierarchy (LOC/sec) directly, and provides a clear baseline to test incremental touch-rebuild and content-edit rebuild behavior.

The generated program reads a run-time value, so no optimizer can fold the whole computation away - the constant-seeded version let them, which turned the comparison into a measurement of each constant folder. Every row is measured in its unoptimized baseline mode (Zig Debug, Rust dev, Zoril and Hare through QBE, which has no optimizer) and names that mode in the row: comparing languages at different optimization levels compares different work. The optimizing modes are measured in the table below instead, on a realistic call tree, because on this straight-line shape they are not usable at all. The `fib` and `array_loop` tables above keep Zig ReleaseFast, whose cost is not a factor on programs that small.

The touch and edit columns are not an equal measurement across languages: each is that toolchain's own incremental support, driven the same way (touch one module and rebuild; change one function body and rebuild), and only Zoril's goes through a tool this project owns, `tools/zbuild`. Zig's column is its build cache, Rust's is cargo's incremental profile, Hare's is its module cache - what a user of that language would get, not a like-for-like rebuild mechanism.

- **Zoril**
  - Functions: 3000 fns
  - Codebase LOC: 33706 LOC
  - Clean Compile: 8614 ms
  - Compile Throughput: **3912 LOC/s** (348 fns/s)
  - Clean Peak RSS: 191.7 MB
  - Touch Rebuild: 63 ms
  - Edit Rebuild: 92 ms
  - Rebuild Speedup: **98.9%**
  - Binary Size: 544984 B
  - What compile covers: zbuild DAG, incremental caching, translation-unit lowering, QBE SSA, as, ld
- **Zig (Debug)**
  - Functions: 3000 fns
  - Codebase LOC: 30735 LOC
  - Clean Compile: 1969 ms
  - Compile Throughput: **15609 LOC/s** (1523 fns/s)
  - Clean Peak RSS: 213.1 MB
  - Touch Rebuild: 71 ms
  - Edit Rebuild: 657 ms
  - Rebuild Speedup: **66.6%**
  - Binary Size: 18832610 B
  - What compile covers: build.zig modules, semantic analysis, comptime, LLVM backend, lld
- **Rust (Cargo dev)**
  - Functions: 3000 fns
  - Codebase LOC: 27905 LOC
  - Clean Compile: 1697 ms
  - Compile Throughput: **16443 LOC/s** (1767 fns/s)
  - Clean Peak RSS: 320.2 MB
  - Touch Rebuild: 481 ms
  - Edit Rebuild: 504 ms
  - Rebuild Speedup: **70.3%**
  - Binary Size: 3688528 B
  - What compile covers: Cargo incremental, borrow checking, trait resolution, monomorphization, LLVM codegen
- **Hare**
  - Functions: 3000 fns
  - Codebase LOC: 27709 LOC
  - Clean Compile: 1966 ms
  - Compile Throughput: **14094 LOC/s** (1525 fns/s)
  - Clean Peak RSS: 167.3 MB
  - Touch Rebuild: 167 ms
  - Edit Rebuild: 169 ms
  - Rebuild Speedup: **91.4%**
  - Binary Size: 1516864 B
  - What compile covers: hare module cache, type checker, QBE emission, as, ld

_Peak RSS is the largest single process anywhere in the build - a compiler the build driver started, not only the driver - read exactly with `getrusage` ([`bench/cross_lang/children_maxrss.c`](../../bench/cross_lang/children_maxrss.c)). It is not the sum of processes that ran at the same time, so a parallel build can use more memory in total._

#### Optimized builds on a realistic shape

The same generated project as the table above, but compiled as a call tree (each module's driver calls its own functions, and `main` calls the drivers) with the optimizing mode: Zig ReleaseFast and Rust `--release`. This is where an optimizer has the work a real program gives it, and it is the comparison the unoptimized table cannot make. Zoril and Hare have no optimization level to raise, so their rows above are already their build of this shape.

| Language             | LOC   | Functions | Clean                      | LOC/s | Binary    |
| -------------------- | ----- | --------- | -------------------------- | ----- | --------- |
| Zig (ReleaseFast)    | 31335 | 3000      | did not finish within 300s | -     | -         |
| Rust (Cargo release) | 28505 | 3000      | 4141 ms                    | 6883  | 2456496 B |

Zig's whole-module LLVM pass over 3,000 generated functions does not finish inside the five minutes this pass allows it, on the call tree any more than on the straight-line shape, so its cell says so instead of reporting a time. Rust's release profile aborts inside LLVM on the straight-line shape - "cycle encountered after 4 frames with period 6", cargo exit 101, rustc 1.99.0 (2026-09-28), reproduced by `bench/cross_lang/rustc_llvm_abort_repro.sh` - and finishes in seconds on this one, which is why the two tables measure different shapes rather than one shape at two modes.

> **The Key Takeaways:**
>
> 1. **Compiler Throughput Hierarchy:** Hare compiles at **14094 LOC/s** — **3.6× faster per line** than Zoril (3912 LOC/s). Hare is Zoril's direct architectural peer (small, self-hosted, QBE backend). In memory, the largest process in Hare's build used **167.3 MB** for 27k LOC (6.0 MB per thousand lines) and in Zoril's **191.7 MB** for 33,706 LOC (5.7 MB per thousand lines).
> 2. **Incremental Rebuild:** With `tools/zbuild` modular compilation and incremental caching, Zoril achieves a **98.9% speedup** on body-edit rebuilds (92 ms vs 8614 ms clean), and near-instant touch no-ops (63 ms). In contrast, compilers with separate compilation and caching drop from clean ~10s down to sub-second rebuilds (Zig 71 ms touch / 657 ms edit, Hare 167 ms touch / 169 ms edit, Rust 481 ms touch / 504 ms edit).
> 3. **Process Startup vs Execution Time:** In microbenchmarks, runtimes under ~5 ms are dominated by OS process spawn/exit. Workloads 1 & 2 above provide execution-heavy measurements running in hundreds of milliseconds to seconds.

#### How the numbers scale with the project

Each point is the same program shape for every language, so the rows are comparable with each other and with the table above. `LOC/s` is clean-build throughput; `touch` is Zoril's incremental no-op rebuild through `tools/zbuild`, the axis that shows what whole-program analysis costs as a project grows.

| Point | Shape               | LOC   | Language         | Clean   | LOC/s | Peak RSS | Touch |
| ----- | ------------------- | ----- | ---------------- | ------- | ----- | -------- | ----- |
| `3k`  | 25 mods x 10 funcs  | 2931  | Zoril            | 459 ms  | 6385  | 14.7 MB  | 14 ms |
| `3k`  | 25 mods x 10 funcs  | 2712  | Zig (Debug)      | 1641 ms | 1652  | 209.3 MB | -     |
| `3k`  | 25 mods x 10 funcs  | 2480  | Rust (Cargo dev) | 270 ms  | 9185  | 171.9 MB | -     |
| `3k`  | 25 mods x 10 funcs  | 2434  | Hare             | 787 ms  | 3092  | 53.0 MB  | -     |
| `30k` | 100 mods x 30 funcs | 33706 | Zoril            | 8718 ms | 3866  | 193.7 MB | 66 ms |
| `30k` | 100 mods x 30 funcs | 30737 | Zig (Debug)      | 2005 ms | 15330 | 213.2 MB | -     |
| `30k` | 100 mods x 30 funcs | 27905 | Rust (Cargo dev) | 1710 ms | 16318 | 319.3 MB | -     |
| `30k` | 100 mods x 30 funcs | 27709 | Hare             | 2010 ms | 13785 | 165.7 MB | -     |

At the largest point measured (`30k`, 33706 LOC), all 4 languages build in Zoril (8.7 s), Zig (Debug) (2.0 s), Rust (Cargo dev) (1.7 s), Hare (2.0 s). Zoril's own clean time grows 19.0x from `3k` to `30k` while its line count grows 11.5x and peak memory 13.2x, which is the whole-program trade-off `doc/vision/why_zoril.md` describes.

## Evaluating the Architecture: Trade-offs of Whole-Program Analysis

An architectural evaluation of Zoril's verification model highlights three key areas:

### 1. Whole-Program Visibility vs. Modular Signature Annotations

Rust uses lifetime annotations in function signatures because it is a **modular** compiler: it type-checks each function against its callees' signatures alone, without examining their bodies. Under that modular contract, annotations are necessary to propagate lifetime relationships across function boundaries.

Zoril explores a **whole-program** compilation model. It holds function bodies in memory in an `ILModule` when running verification. This makes it possible to compute interprocedural summaries by direct analysis, without asking the programmer for lifetime annotations. This represents a distinct architectural trade-off: exchanging modular compilation boundaries for reduced annotation overhead on data structures.

Austral and Vale show that the memory safety design space holds several good answers (linear types, generational references). Zoril's inference-based approach explores another point in that space.

### 2. Engineering Trade-offs: Analysis Cost, Precision, and Indirect Calls

**Analysis Scalability:** Points-to analysis over aggregate storage scales superlinearly. In a whole-program compiler without separate compilation, interprocedural analysis costs must be managed carefully so they do not compromise compiler turnaround times.

**Precision Over Aggregate Storage:** Distinguishing "this slot holds a pointer" from "this pointer points into the local frame" is a central challenge in static analysis. Achieving soundness without rejecting valid code requires an accurate storage model.

**Indirect Calls and Over-Approximation:** Direct function calls map to a known summary, whereas indirect calls require considering the signature-matched address-taken set. In Zoril:

- **No dynamic loading** (no `dlopen`/`dlsym`). The address-taken set is a sound and complete over-approximation.
- **No pervasive dynamic dispatch.** Traits are monomorphized without vtables or trait objects; function pointers are opt-in and lexically visible, allowing analysis cost to scale with actual usage.

### 3. Verification Discipline and Empirical Testing

Memory safety claims require empirical verification. Specifications must not only define intended behavior, but be backed by rigorous test suites that validate both positive and negative cases (e.g. testing both array reads and writes, valid ownership moves and rejected use-after-move).

In Zoril, this discipline is enforced by continuous automated safety probes (`bench/safety_matrix/probes/`) that verify the safety matrix directly against the compiler's actual behavior on every change.

## Summary

On today's measured tree:

- **Hare** — the closest architectural relative: both are small, self-hosted, and QBE-backed, and both bounds-check array and slice reads and writes. Hare deliberately keeps memory management manual and explicit and has the faster compiler; Zoril experiments with adding compile-time move checking (use-after-move, double-free) to a similarly small toolchain.
- **Zig** — a mature systems language with a rich standard library, `comptime` metaprogramming, per-mode control over safety checks, and allocator-based runtime detection of memory errors in safe modes, with much faster generated code than Zoril today. Zoril tries compile-time move tracking and stack escape analysis instead, with bounds checks in every build.
- **Rust** — the established memory-safe systems language, with comprehensive, modular memory safety through its borrow checker and lifetime annotations, much faster generated code, and a large ecosystem. Zoril explores a different design — bump arenas, affine moves, and whole-program escape analysis — to see how far safety can go without lifetime annotations. <!-- allow-phrase: about another language -->

## Benchmark Status & Harness

The cross-language benchmarks are automated in `scripts/bench_cross_lang.sh` (POSIX shell & Lua), measuring Zoril alongside release binaries of Zig, Rust, Hare, and GCC/Clang across all four axes (compile time, compile peak RSS, runtime, and binary size). Results from each run are appended to `bench/speed_history.tsv` with compiler version tracking (use `--record` or `--update-doc` to force re-measuring comparison toolchains and updating the document tables). Run `scripts/bench_cross_lang.sh --update-doc` to refresh the measured tables above.
