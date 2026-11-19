# Zoril Stability Statement and What Zoril Checks

This document outlines the stability commitments, versioning policies, and public safety claims for Zoril `v0.1.0-alpha`.

---

## 1. Stability Policy for `v0.1.0-alpha`

Zoril is currently in early alpha (`v0.1.0-alpha`). Although we try to avoid changes that would break user code, **no stability promises are made regarding surface syntax, standard library APIs, intermediate representations, or binary ABIs**:

- **Surface Syntax:** Keywords, operators, precedence rules, and syntax structures may evolve between minor versions as language ergonomics and features are refined.
- **Standard Library:** Module organization, function signatures, trait definitions, and types in `stdlib/` are subject to reorganization or breaking adjustments.
- **ABI & Object File Stability:** Object layouts, name mangling schemes, and calling conventions are not guaranteed to remain stable across compiler builds or versions.
- **Intermediate Representation (ZIL & SSA):** The text format and binary structures of ZIL and SSA IR are internal to the toolchain and may change.

### Versioning Scheme

Zoril follows [Semantic Versioning 2.0.0](https://semver.org/) with pre-1.0 rules:

- **`0.MAJOR.PATCH` (Pre-1.0):**
  - **Minor Version Increments (`0.x.0`):** May introduce breaking changes to language syntax, compiler flags, or standard library APIs.
  - **Patch Version Increments (`0.x.y`):** Reserved for bug fixes, performance optimizations, documentation improvements, and backwards-compatible additions within that minor release track.
- **Transition to 1.0:** A `1.0.0` release will denote commitment to long-term syntax and standard library backwards compatibility. Self-hosting fixpoints alone do not imply a 1.0 guarantee.

### Breaking Change Announcements

When breaking changes are introduced:

1. They will be documented in release notes with explicit before/after code migration guides.
2. Where practical, compiler diagnostics will detect obsolete syntax and suggest the updated idiom.
3. Breaking changes will be grouped into scheduled minor version bumps (`0.2.0`, `0.3.0`, etc.) rather than ad-hoc patch updates.

### FFI rules: restrict now, relax later

The rules at the C boundary take the stricter side, because tightening one after users depend on it breaks their code and loosening one breaks nobody. An `extern` signature may carry only integers, `bool`, floats and raw pointers (and `extern "C" fn` pointers); a struct travels as a pointer. A C function pointer comes only from an `extern "C" fn` defined in Zoril and cannot be forged from a number or dereferenced; calling one needs `unsafe`. Hosted mode (`--hosted`) is opt-in and Linux x86_64 only. Each of these may be relaxed in a later release (structs by value, references, a nullable callback); none will be tightened.

### Names, promises and contracts: keep future features additive

Pre-1.0 the syntax may still change, but a feature that is coming is prepared for by keeping the _names and the extension points_ stable rather than by promising the syntax:

- **Reserved words.** `async`, `await`, `dyn`, `move`, `where`, `yield`, `macro`, `union` and `super` are reserved (`doc/spec/surface_syntax.md` §2.1): using one as an identifier is a compile error that says it is reserved for a future feature. Reserving them now means the feature that needs one can arrive without breaking a program that had used the word as a name. The set can grow before 1.0 and never shrinks; each addition is listed in `KNOWN_ISSUES.md`.
- **The scalar `static mut` promise is a single-thread promise.** Safe access to a scalar (`i32`, `f64`, `bool`, `char`, a raw pointer) `static mut` holds because the runtime is single-threaded: there is no other thread to race with (`doc/SAFETY.md` §4.6). When threads arrive this changes - per-thread statics by default, `unsafe` from a spawned thread, or atomics, decided by the concurrency design tracked on the [roadmap](ROADMAP.md) - and that release will say so. A non-scalar `static mut` already needs `unsafe`.
- **Attributes are the only extension point for borrow contracts.** The language has no lifetime annotations, and a quote already starts a character literal. So a borrow or region contract is spelled as an attribute on the function - `#[borrows(..)]` today, and `#[stores(..)]` for a declared store contract - never as a `'a`-style parameter or argument. A future contract extends that set; it does not add a lifetime syntax.

One part of the ABI is promised: a `struct` **whose fields all have a C layout** has the C layout. That covers the primitives (`bool`, the sized integers, `f32`, `f64`), raw pointers, references (a pointer at this level), arrays of those, nested such structs, and zero-sized fields, which contribute nothing (C has no equivalent member). Fields sit in declaration order, each at its natural alignment, and the size is padded to the alignment of the largest field (`doc/spec/abi.md` §2.1). `scripts/test_struct_layout.sh` compares size, alignment and every field offset with the host C compiler's, including nested structs, arrays in structs, an array of structs and a zero-sized field. A struct with an `enum`, tuple, slice or `Box` field inherits the absence of a promise: measured, `struct WithEnum { a: u8, k: Kind, b: u8 }` with `enum Kind { A, B(u64) }` is 32 bytes with `k` at offset 8, where a C `int` field would make it 12 bytes with `k` at 4. **No other type carries a layout promise**: enums, tuples, slices, `Box` and closures may change. There is no `#[repr(C)]` because there is no other struct layout; if a reordering default is ever wanted, that is a language change with a migration note. Use the `ffi` module's aliases (`c_int`, `c_long`, ...) to spell C types, so a port changes the aliases and not your code.

---

## 2. Published Safety Claims

Zoril's compile-time checks (affine ownership, move tracking, borrow aliasing, and stack/arena region escape analysis) and runtime checks (array/slice bounds traps and checked shift counts) run in **every build configuration**: there is no release flag that compiles bounds or borrow checks out.

For the full breakdown of what is checked and what is left to the programmer, see:

- **[What Zoril Checks](SAFETY.md):** the user-facing three-tier safety guide (compile-time checks, runtime traps, `unsafe` boundary, and open gap families).
- **[Safety Model](spec/safety_model.md) and [Unsafe Boundary Policy](spec/unsafe_policy.md):** the normative verification architecture, property domain specifications, and `unsafe` contract rules.
- **[Safety Verification Ledger](../bench/safety_matrix/README.md) and [Fuzzing Record](../bench/fuzz/README.md):** the live safety-matrix row and probe counts, open `known_gap` inventory, trusted-base census, and differential fuzzing budgets.
