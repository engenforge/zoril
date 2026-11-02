# Why Zoril

**Reviewed for `v0.1.0-alpha`.** Normative references: [`doc/spec/safety_model.md`](../spec/safety_model.md), [`doc/spec/unsafe_policy.md`](../spec/unsafe_policy.md), [`doc/language/language_comparison.md`](../language/language_comparison.md).

---

## The Name

**Zoril** stands for **Zero Overhead Regional Inference Language**:

- **Zero Overhead:** safety and abstraction should cost nothing (or close to nothing) at run time. Zoril has no garbage collector or reference counting; ownership, moves, and drops are checked at compile time, generics are monomorphized, and bounds checks are elided where the compiler can prove the index in range. How close the compiler gets to zero overhead is measured in [`doc/zero_overhead.md`](../zero_overhead.md).
- **Regional:** memory is organized by regions (`'local`, `'static`, `'heap`, and arenas), and a pointer may not outlive the region it points into. This is checked: for stack frames by the escape analysis, and for arenas by tying a value to the handle it was allocated from, so resetting, freeing or outliving the arena while a value from it is live is a compile error ([`128_arena_use_after_reset.zrl`](../../bench/safety_matrix/probes/128_arena_use_after_reset.zrl), [`159_arena_tied_collection_outlives_block.zrl`](../../bench/safety_matrix/probes/159_arena_tied_collection_outlives_block.zrl)).
- **Inference:** regions and escape behaviour are inferred, including across functions through interprocedural summaries, so programs carry no lifetime annotations.

---

## 1. What Zoril Is Exploring

Systems languages make different, well-reasoned trade-offs. Rust and Zig, built on LLVM, offer broad language features, mature ecosystems, and highly optimized code; the size of those toolchains reflects how much they do. Small toolchains such as cproc and Hare, built on QBE, show how much a compact, readable compiler can achieve.

Zoril is an early-alpha experiment in combining ideas from both: compile-time ownership tracking and mandatory bounds checking, implemented in a small compiler (~42k lines of Zoril, not counting comment lines). This combination has been explored less, and Zoril is one attempt at it.

Zoril is not a subset of Rust. It aims first at systems software: data-oriented, libc-free programs where a small, inspectable toolchain and deterministic checking matter as much as raw execution speed. Nothing in the language limits it to that. Typical application code is expected to need no `unsafe` (§2.C), and the standard library is written for it.

---

## 2. What Zoril Does Today

Every capability below is exercised by the running compiler (`build/zoril`) during `make test`, including the safety matrix in [`doc/spec/safety_model.md`](../spec/safety_model.md) (78 rows at the time of writing, with no row marked **GAP**).

### A. One Build Configuration

Languages with several build modes balance runtime checks against peak performance in different ways. Rust keeps bounds checks in release builds but, by default, turns integer-overflow panics into wrapping arithmetic. Zig checks bounds in `Debug` and `ReleaseSafe` and omits those checks in `ReleaseFast` for throughput. Both are deliberate choices that give programmers control.

**Zoril has a single build configuration.** Bounds checks on array and slice reads and writes (`surface_syntax.md` §11.2.3, tested by probes `bench/safety_matrix/probes/10_oob_array_write.zrl` and `11_oob_slice_write.zrl`) are always present, and no option turns a runtime trap into undefined behaviour.

Measurements in [`doc/language/language_comparison.md`](../language/language_comparison.md) show that this need not cost throughput in simple loops: when a loop guard dominates the index (`while i < 4096`), the compiler removes the bounds check, and the checked loop compiles to **byte-identical machine code** to an unchecked raw-pointer loop. Loops with irregular indexing still pay for their checks (see [`doc/zero_overhead.md`](../zero_overhead.md) §4).

### B. Compile-Time Move Checking and Region Escape Checking

Zoril enforces an affine type system at compile time:

- **Use-after-move and double-drop:** values of non-copy types (`Vec`, `String`, resources) move on assignment and function call. Reusing a moved binding or dropping a moved resource is a compile error (`tests/error_reporting/err_own_use_after_move.zrl`).
- **Dangling stack pointers:** returning a pointer to local stack storage, directly or behind a cast, is a compile error (`surface_syntax.md` §11.2.4, `tests/error_reporting/ec_region_escape_return_cast.zrl`).
- **Escape through calls:** each function is summarized by where its result may point and which of its parameters it stores into, so a stack pointer handed back by a callee, or stored by a callee into longer-lived memory or a global, is also rejected (safety matrix row "Region Escape: Through a Call").

> [!IMPORTANT]
> **Scope.** The interprocedural check relies on function summaries, which the compiler computes from function bodies and `zbuild` carries in each module's `.zri` interface. That is the price of checking without lifetime annotations, and it has three parts. It costs compile time, since every body is analysed. Where a summary cannot decide, the compiler answers conservatively, so it can reject a correct program that a signature with a lifetime annotation would have accepted. And an import with no `.zri` summary is trusted by its signature, and a call through a function pointer is not tied to its result. The limits are listed in the safety matrix rather than hidden.

### C. Application Code Without `unsafe`

Typical application code is not expected to use `unsafe`. The standard library is written so that applications do not need it: raw memory access stays in runtime primitives and allocator abstractions (`stdlib/mem.zrl`, `stdlib/file.zrl`, `stdlib/args.zrl`), as [`doc/spec/unsafe_policy.md`](../spec/unsafe_policy.md) §4 describes.

An example JSON tool written in Zoril (a CLI parser, query engine, and schema validator of about 2,000 non-comment lines, not yet published) contains no `unsafe { }` block (see `doc/SAFETY.md` §5.3). `scripts/marker_density.sh` reports 0.00% line density, no raw pointer casts (`as *T` / `as *mut T`) and no reference forgeries (`&*p` / `&mut *p`). It uses enums with payloads, exhaustive pattern matching, and `Result<T, E>` error propagation rather than raw pointers.

### D. A Small Compiler

The self-hosted compiler front end is **~42k lines** of Zoril, not counting comment lines (~56k including the standard library and the shipped build tools: `zilc`, `zbuild` and `zman`). For context, counted the same way, rustc is ~690k lines of Rust excluding LLVM (its `compiler/` directory, without the GCC and Cranelift backends), Zig's compiler ~500k lines of Zig (`src/`), and Clang/LLVM several million. Those toolchains do far more — many targets, extensive optimization, large standard libraries — so the comparison is about how much code a reviewer must read, not about merit.

The compiler uses a data-oriented design: it indexes dense arrays of AST and ZIR nodes through small integer handles (`ExprId`, `SSAId`) instead of pointer-heavy graphs, which keeps it compact and straightforward to inspect.

---

## 3. Related Languages

Zoril learns from many languages. Comparisons below are context for its design choices, not rankings; current measurements are in [`doc/language/language_comparison.md`](../language/language_comparison.md).

### A. Small QBE-Based Toolchains: cproc and Hare

- **Context:** small, self-hosted, minimal-dependency toolchains targeting QBE. Zoril shares their backend and their aim of a small toolchain.
- **Codebase sizes:** cproc ~9k lines of C; Hare's compiler, `harec`, ~23k lines of C, driven by the `hare` build tool; Zoril ~42k lines of Zoril; QBE ~15k lines of C.
- **Execution speed:** on call-heavy code (`fib(38)` ×3), Zoril (732 ms) and Hare (690 ms) are close, reflecting the shared backend.
- **Build speed:** Zoril compiles more slowly than Hare on clean builds (on the ~30k-LOC benchmark project, Hare compiles 14,094 lines a second, measured with `hare build`, and Zoril 3,912). The likely reasons are that Zoril checks more at compile time and that it is early alpha. `tools/zbuild` makes up for part of it by caching compiled modules, with interface-level early cutoff, to keep edit-rebuild cycles short (63 ms touch, 92 ms edit at 30k LOC; 12 ms touch, 26 ms edit on its 2,931-LOC benchmark project; the projects differ in size, so these are not head-to-head figures).
- **Design:** both languages check bounds on reads and writes. Hare deliberately keeps memory management manual and explicit; Zoril experiments with adding compile-time move checking and stack escape checking on top of a similarly small toolchain.

### B. Zig

- **Context:** a systems language built around explicit control, compile-time execution (`comptime`), and explicit allocators, with a mature standard library and growing ecosystem.
- **Design:** Zig gives programmers control over safety per build mode and detects double-free and use-after-free at run time with its General Purpose Allocator in safe modes. Zoril tries a different point: use-after-move and stack escape checks at compile time, and bounds checks in every build.
- **Performance:** Zig's LLVM backend produces considerably faster code than Zoril's QBE backend today (for example 130 ms against 732 ms on `fib`, and 537 ms against 726 ms on the array loop).

### C. Research Lineage: Cyclone, Vale, Austral

These languages explored memory safety without a Rust-style general borrow checker, and Zoril builds on their ideas ([`doc/language/arena_based_languages.md`](../language/arena_based_languages.md)):

- _Cyclone_ pioneered safe region-based memory management for C, including region-annotated pointers, and directly influenced Rust. Its annotations show how much a language must express when it checks regions across separately compiled code.
- _Austral_ uses linear types with capability tokens: every linear value is consumed exactly once.
- _Vale_ pairs references with generation counters checked at run time, and uses regions to remove many of those checks.

Zoril's point in this space pairs arena allocation with affine values and region escape analysis inferred from function bodies, so that programs need neither lifetime annotations nor runtime generation checks. The cost of that choice is compile time and some conservative rejections (§2.B): the compiler analyses function bodies and carries the results in module interfaces, instead of reading lifetimes from signatures. The arena half of that goal is not reached yet: until it is, arena handles are planned to carry a run-time generation check.

### D. Rust

Rust is a landmark in programming languages and the most widely used memory-safe systems language, with a rich type system, powerful macros, a general borrow checker, and an extensive ecosystem. Zoril's ownership model and syntax borrow heavily from it. <!-- allow-phrase: about another language -->

**Choose Rust** for production software, for whole-program borrow checking over arbitrary data structures, for its library ecosystem (crates.io), or where a certified or vendor-supported toolchain is needed. Zoril is an alpha-stage experiment and cannot offer any of these.

**What Zoril explores differently:**

1. **Toolchain size:** a compiler front end of ~42k lines, on a small backend. Rust's larger toolchain supports far more, and auditing it is correspondingly larger. The small backend is a lasting goal, not a stage: other backends may be added beside it, but it stays a first-class, supported way to build Zoril ([roadmap](../ROADMAP.md#backends)).
2. **One build configuration:** Zoril keeps all runtime checks in every build, including the check on a variable shift count that Rust's release profile drops by default. Arithmetic overflow is not one of them: Zoril's integer arithmetic wraps by design.
3. **No lifetime parameters:** Rust code often uses arenas and integer handles too, and Rust's lifetime annotations are what let it check borrows from signatures across crates. Zoril analyzes function bodies instead, so data structures built around arenas and handles (`ExprId`, `NodeId`) need no lifetime parameters, at the cost of that analysis at compile time.

---

## 4. Summary

Zoril is an early experiment, not an attempt to be everything to everyone. It is for systems programmers interested in:

- **The same runtime checks in every build**
- **Compile-time ownership and arena-based memory management without lifetime annotations**
- **Application code without `unsafe`, built on small, auditable runtime primitives**
- **A small toolchain that is easy to read, audit, and build from source**

For language subtleties and contrasts with C and Rust semantics, see [`doc/language/gotchas_and_subtleties.md`](../language/gotchas_and_subtleties.md).
