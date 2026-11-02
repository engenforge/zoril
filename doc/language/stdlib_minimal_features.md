# Principles of Minimalist Standard Library Design

This document outlines the architectural principles behind Zoril's standard library (`stdlib/`), emphasizing zero-cost abstractions, predictable performance, and minimal footprint.

---

## 1. Core Objectives

A minimalist standard library for a systems language should provide only the essential building blocks required to build robust software, avoiding feature bloat and heavy runtime dependencies.

Key design criteria include:

- **No Hidden Allocations:** Functions that allocate dynamic memory must make that allocation explicit in their signatures or constructors.
- **Explicit Error Handling:** Replace exceptions with explicit algebraic return types (`Result<T, E>` or error code enums).
- **Zero-Cost Views:** Rely on slices and borrows rather than heap duplication for string and buffer manipulations.

---

## 2. Essential Primitives and Types

The core standard library comprises:

1. **Option and Result Types:** Explicit representation of presence/absence and success/failure without null pointers or exceptions.
2. **Slices and Buffer Views:**
   - Slices (`[T]`, `[mut T]`): Fat pointers containing a pointer and length, with bounds checking enforced at compile time or via deterministic runtime traps.
   - String slices: Validated UTF-8 views providing slicing and parsing without allocation.
3. **Core Collections:**
   - `Vec<T>`: A dynamically resizable array.
   - Simple linear and hash maps: Thin collections suitable for common systems workloads.
4. **I/O and File Systems:**
   - Minimal system call wrappers (`io`, `fsys`) supporting `read`, `write`, `open`, `close`.
   - Linear capabilities (`fd`) that require open file descriptors to be explicitly closed before returning.
5. **Memory Management:**
   - Regional arenas (`mem::Arena`) for bump-allocation patterns.
   - Owned heap boxing (`Box<T>`) for dynamic values with independent lifetimes.
