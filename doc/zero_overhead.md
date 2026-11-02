# The Zoril Zero-Overhead Claim

This document states what "zero overhead" means for the Zoril programming language, defines the claim with sufficient precision to be falsified, provides empirical measurements isolating abstraction costs from backend codegen, and honestly enumerates the remaining costs.

---

## 1. What "Zero Overhead" Means for Zoril

The principle of zero overhead in Zoril is defined as follows:

> **The Zero-Overhead Claim:** In checked Zoril code, the language's abstractions—including static type enforcement, monomorphized generics, slice descriptors, function values and closures, and bounds checking where the compiler can prove the index in range—incur **no run-time penalty** over idiomatic, hand-written C compiled using the **same backend pipeline**.

### Falsification Criteria

This claim is falsified if, on identical algorithms and workloads targeting the same backend (`qbe`):

1. A zero-cost abstraction (such as generics or safe slice passes) requires dynamic heap allocation, runtime type inspection (RTTI), or indirect dispatch that handwritten C does not require.
2. Safe bounds-checked loops whose index expressions are statically dominated by loop conditions produce more machine instructions or execute slower than the equivalent unchecked pointer loops.
3. The geometric mean execution time of idiomatic Zoril code across the benchmark suite exceeds equivalent C compiled on the same backend by more than 10%.

---

## 2. Isolating Abstraction Cost from Backend Codegen

To evaluate zero-overhead claims accurately, one must separate the **language and lowering overhead** from the **backend code-generator overhead**.

Production optimizing compilers like GCC, Clang, and LLVM (used by Rust and Zig) perform extensive optimization passes: loop vectorization, cross-function inlining, polyhedral loop transformations, and instruction scheduling. Zoril emits code targeting **QBE**, a deliberately simple, fast, ~10,000-line compiler backend that prioritizes fast compilation and auditability over heavy optimization.

To isolate these factors, the benchmark harness (`scripts/perf_gap.sh`) compares three builds of identical algorithms across six representative workloads:

1. **Zoril**: `zoril` → `zilc` → `qbe`
2. **cproc (C on QBE)**: `cproc` → `qbe` (isolates frontend and language lowering)
3. **gcc -O2**: `gcc -O2` (shows the impact of backend optimization)

### Measured Results (Medians of 11 runs)

| Workload           | Zoril (ms) | cproc (ms) | gcc -O2 (ms) | Zoril / cproc (Frontend Ratio) | cproc / gcc (Backend Ratio) |
| ------------------ | ---------- | ---------- | ------------ | ------------------------------ | --------------------------- |
| `array_loop`       | 786        | 842        | 137          | **0.93x**                      | 6.15x                       |
| `fib`              | 714        | 702        | 193          | **1.02x**                      | 3.64x                       |
| `particles`        | 628        | 628        | 240          | **1.00x**                      | 2.62x                       |
| `qsort`            | 462        | 421        | 361          | **1.10x**                      | 1.17x                       |
| `sha`              | 237        | 233        | 141          | **1.02x**                      | 1.65x                       |
| `vm`               | 421        | 333        | 331          | **1.26x**                      | 1.01x                       |
| **Geometric Mean** | —          | —          | —            | **1.05x**                      | **2.28x**                   |

### Key Findings

1. **Frontend Parity (1.05x Geometric Mean):** Zoril runs at **1.05x** of equivalent C code on the same backend. On compute- and loop-heavy code (`array_loop`, `particles`, `fib`, `sha`), Zoril is effectively at parity (0.93x–1.02x).
2. **Backend Accounts for the GCC Gap:** The 2.39x geometric-mean execution time difference between Zoril and `gcc -O2` on these six workloads (1.05 x 2.28) is dominated by the backend: handwritten C compiled through QBE (`cproc`) is already **2.28x** slower than `gcc -O2`.
3. **Zero-Cost Bounds Checking in Dominant Loops:** In `array_loop` (`bench/cross_lang/array_loop/`), an array iteration guarded by `while i < 4096` was benchmarked against an unchecked raw-pointer version (`array_loop_ptr.zrl`). Comparison of emitted assembly (`cmp -s array_loop.s array_loop_ptr.s`) confirms that the generated assembly is **byte-identical**. The compiler's inductive condition analysis (`src/index_facts.zrl`) proves the loop index in-bounds at compile time and elides the bounds check, leaving **zero checking instructions** in the loop body.

---

## 3. Measurements Alongside Rust, Zig, and Hare

Cross-language benchmarks (`scripts/bench_cross_lang.sh`, documented in `doc/language/language_comparison.md`) measure Zoril alongside other systems languages. They are context for Zoril's trade-offs, not a ranking: the LLVM-based toolchains produce much faster code, and Hare's compiler is faster on clean builds.

### Execution Speed (Workloads)

_Best of 3 runs, on the same host as the build table below._

| Language / Toolchain  | `fib(38)` x3 (ms) | 4096-element array loop (ms) | Notes                                        |
| --------------------- | ----------------- | ---------------------------- | -------------------------------------------- |
| **Zoril**             | 732               | 726                          | Safe language, mandatory checks, QBE backend |
| **C (gcc -O2)**       | 187               | 145                          | Production optimizing C compiler             |
| **Zig (ReleaseFast)** | 130               | 537                          | LLVM backend, bounds checking disabled       |
| **Rust (-O)**         | 132               | 133                          | LLVM backend, overflow checking disabled     |
| **Hare**              | 690               | 959                          | QBE backend peer                             |

### Build Throughput & Incremental Compilation

_Measured on Linux (AMD Ryzen 7 3700X, 16 threads, powersave governor) across all toolchains on the multi-file project benchmark (100 modules × 30 functions = 3,000 functions, ~28k–34k LOC, baseline unoptimized modes)._

| Language             | Codebase LOC | Clean Compile Throughput | Incremental Touch Rebuild | Incremental Edit Rebuild |
| -------------------- | ------------ | ------------------------ | ------------------------- | ------------------------ |
| **Zoril (`zbuild`)** | 33,706 LOC   | 3,912 LOC/s (8,614 ms)   | 63 ms                     | 92 ms (98.9% speedup)    |
| **Hare**             | 27,709 LOC   | 14,094 LOC/s (1,966 ms)  | 167 ms                    | 169 ms (91.4% speedup)   |
| **Rust (Cargo dev)** | 27,905 LOC   | 16,443 LOC/s (1,697 ms)  | 481 ms                    | 504 ms (70.3% speedup)   |
| **Zig (Debug)**      | 30,735 LOC   | 15,609 LOC/s (1,969 ms)  | 71 ms                     | 657 ms (66.6% speedup)   |

On a smaller project (25 modules × 10 functions, 2,931 LOC), `tools/zbuild` achieves 6,498 LOC/s clean throughput (451 ms), with a 12 ms touch rebuild and 26 ms edit rebuild (94.2% speedup).

In modular compilation (`tools/zbuild`), peak resident memory is bounded by the largest module compilation step in the build tree: ~15 MB peak RSS on the 2,931-LOC project, and ~192 MB on the 33,706-LOC project, where the largest step is the generated `main.zrl` (3,106 lines calling all 3,000 functions; an ordinary module takes ~11 MB). Measured the same way on the same 3,000-function project - the largest single process in each build, read with `getrusage` - Hare's build peaks at 167 MB, Zig's at 213 MB and Rust's (`cargo` dev) at 320 MB ([`doc/language/language_comparison.md`](language/language_comparison.md)). In whole-program mode, `zoril` holds the complete program AST, IL, and interprocedural summaries in memory, taking ~10–12 MB/kLOC (~33 MB for the 2,931-LOC project, ~445 MB for the ~39k-LOC compiler itself). The generated projects differ in size between languages by up to 1.2x, so the rebuild columns are close to, but not exactly, head-to-head figures.

---

## 4. Remaining Costs and Honest Boundaries

In the spirit of Zoril's verifiable safety matrix, the non-zero costs that remain in the current compiler are explicitly documented below:

1. **Non-Elided Bounds Checks:** When an array or slice indexing expression cannot be statically proven in-bounds by dominating condition facts (`src/index_facts.zrl`), Zoril emits a bounds check instruction. While failed paths branch to a deterministic runtime trap (exit code 134, SIGABRT), executing the comparison and conditional jump costs approximately 2–8% on irregular indexing patterns (e.g. `qsort` or bytecode interpreters).
2. **Sequential Enum Tag Dispatch:** QBE currently lacks native jump tables. As a result, `match` statements across enums with many variants lower to linear comparison chains. On workloads like `vm`, this tag dispatch chain accounts for the remaining 1.26x difference relative to C.
3. **Drop Flags and Cleanup Blocks:** Types with linear resources or non-trivial drops may require runtime tracking flags if moved conditionally inside branches, ensuring resources are freed exactly once.
4. **Aggregate Value Construction:** While values bound by `let` are constructed directly in-place in their destination slots, complex chained temporary projections may introduce intermediate stack copies if not fully elided by mem2reg.

---

## 5. Summary

On the measured workloads, Zoril meets its zero-overhead goal for its language features: safe regions, move semantics, monomorphized generics, and slice indexing whose bounds the compiler can prove add little overhead (1.05x geometric mean) over equivalent C on the same backend. While Zoril targets respectable execution speed, programs requiring aggressive optimization passes of GCC, Clang, or LLVM-based languages today are better served by those toolchains; further backend optimization in Zoril is an area for future work. This document is about cost, not coverage: what Zoril checks, and what it leaves to the programmer, is [What Zoril Checks](SAFETY.md).
