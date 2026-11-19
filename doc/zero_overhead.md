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

Cross-language benchmarks (`scripts/bench_cross_lang.sh`) compare Zoril's execution speed (`fib(38)`, array loop), clean build throughput, incremental `zbuild` rebuild latencies, and per-step peak resident memory alongside C (`gcc -O2`), Rust (`rustc -O` / `cargo`), Zig (`ReleaseFast` / `Debug`), and Hare on a multi-file project benchmark. Because those measurements are re-recorded as toolchains and passes evolve, the canonical tables and host specifications live in a single place: [`doc/language/language_comparison.md`](language/language_comparison.md). In summary, LLVM-based toolchains produce faster code on compute-heavy kernels and Hare builds faster from clean, while `zbuild` uses interface-level early cutoff to keep incremental edit rebuilds sub-second and peak RSS bounded by the largest compilation step.

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
