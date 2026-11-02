# Zoril and Rust: Architecture and Comparison

> [!NOTE]
> Zoril does **not** adopt Rust's full lifetime system: Zoril does not feature lifetime annotations (`'a`), a generalized cross-type borrow checker, or an `UnsafeCell`-style interior mutability model. Zoril's ownership model and syntax borrow heavily from Rust. Instead of lifetimes, Zoril relies on affine move tracking, non-lexical borrows (ending at last use), and region inference with compile-time stack escape analysis.

---

## Authoritative Documentation & Accurate Comparison

For accurate, empirically verified information regarding Zoril's safety guarantees, positioning, and relationship to Rust, refer to the following documents:

1. **[`doc/tour.md`](../tour.md)** An introductory tour of Zoril syntax, ownership, affine move tracking, and linear capabilities.
2. **[`doc/language/language_comparison.md`](language_comparison.md)** Reproducible empirical benchmarks measuring executable speed, compile throughput, clean peak RSS, and multi-file project scaling alongside Rust, Zig, Hare, and C.
3. **[`doc/spec/safety_model.md`](../spec/safety_model.md)** The 72-row safety matrix, detailing exactly what Zoril rejects at compile time (affine move-checking, stack region escape), what it traps at runtime (mandatory bounds checks on reads and writes), and what is unchecked - with the tiers, and what is left to the programmer, in [`doc/SAFETY.md`](../SAFETY.md).
4. **[`doc/spec/unsafe_policy.md`](../spec/unsafe_policy.md)** The house unsafe boundary policy, demonstrating how unsafe raw pointer manipulation is strictly sequestered inside allocator and runtime primitives, while application code achieves 0.00% marker density.
5. **[`doc/zero_overhead.md`](../zero_overhead.md)** Analysis of abstraction costs and code generation overhead comparing Zoril with C, Rust, and Zig.
