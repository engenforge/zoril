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

A key objective for Zoril is to catch memory-safety errors at compile time, so that safety costs as little as possible at run time; what cannot be checked at compile time is checked by lightweight runtime checks. Unlike languages where safety depends on build flags (e.g. debug vs release modes), **the checks Zoril performs are active in every build**: there is no "unsafe build mode" that disables bounds checks or borrow tracking. Which of them hold in checked code, which are checked only when the program runs, and what is left to the programmer is stated tier by tier in [What Zoril Checks](SAFETY.md); this section is the summary.

### Core Checks in Checked Code

1. **Spatial Safety (Bounds Checking):**
   - All indexing operations on fixed-size arrays and slices (both read and write) are validated.
   - If an access cannot be statically proven in-bounds at compile time, a runtime check is generated. Any out-of-bounds access immediately and deterministically terminates the process via `sys_exit_group(134)` (abort), so an out-of-bounds read or write never touches memory.
   - The status `134` is the Linux report of that stop (`128 + SIGABRT`). What every platform promises is the stop itself: the process ends at the failed check and nothing after it runs.
2. **Temporal Safety (Ownership & Borrowing):**
   - Values are governed by affine ownership and move tracking (`src/check_zir.zrl`).
   - Use-after-move, use-after-free, and double-free/double-drop are rejected at compile time.
   - Mutable borrows (`&mut`) enforce exclusive access, rejecting aliasing mutations in checked code.
3. **Region Safety (No Escaping Stack Pointers):**
   - Functions cannot return pointers or references to local stack frames (`src/verify.zrl`).
   - Provenance tracking tags derived values (`points_to_stack`) through arithmetic, casts, and memory slots, so a stack address cannot escape its activation record in checked code. The analysis is intraprocedural and conservative, and it rejects some programs that are in fact sound ([What Zoril Checks](SAFETY.md) §4.4).
4. **Type Safety:**
   - Casting between arbitrary memory representations is prohibited in checked code. Safe casts (`as`) only convert between compatible numeric types, between pointer types, or from references to raw pointers.

### What `unsafe` Gates

Zoril confines dangerous or unverified low-level operations behind explicit `unsafe { ... }` blocks. The `unsafe` keyword is a reachability gate, not an escape from compiler verification. The normative list is [`doc/spec/unsafe_policy.md`](spec/unsafe_policy.md) §1, six operations:

1. Dereferencing a raw pointer (`*p`, `&*p`, `p.field`, `p.0`, a method call through it), which includes indexing one (`p[i]`) and using it where a reference is expected.
2. Making a reference or a slice out of an integer or a raw pointer (`@ptr_cast<&T>`, `@ptr_from_int<&T>`, `@ptr_cast<[T]>`), including through a type parameter.
3. Synthesizing a slice from a pointer and a length (`@slice`), unless the length is a literal `0`.
4. Invoking foreign/external C functions (`extern fn`).
5. A raw system call (`@syscall`).
6. An uninitialized stack slot (`@alloca`).

Calling an **`unsafe fn`** is a seventh route: a function is declared `unsafe fn` when it requires a precondition the type system cannot prove, and calling one needs an enclosing `unsafe { }` block or an `unsafe fn` body. In `stdlib/` those are the interface contracts - `Args.new`, `Vec::new_in_raw`, `Vec::set_len`, the allocator primitives, `mmap_or_trap`, `mmap_anon`, `mmap_anon_or_trap`, `munmap_or_trap`, `sys_execve` and the other `*_raw` entry points.

_Creating_ a raw pointer is not one of them: `n as *T`, `@ptr_from_int<*T>`, `@ptr_cast<*T>` and `@int_cast<U>` are safe, because every _use_ of the pointer is gated on its type, and a marker on the creation would leave a fixed hardware address with no spelling in a `static`.

All other checks (such as type checks, SSA well-formedness, and must-use enforcement) remain active inside `unsafe` blocks. What `unsafe` leaves unchecked, item by item, is [What Zoril Checks](SAFETY.md) §4.1.

### Known Gaps

Zoril maintains an automated verification suite that links every claim in the safety model to concrete executable probes (`bench/safety_matrix/probes/`).

- For the complete matrix of **72** safety properties, each backed by its probes, refer directly to [`doc/spec/safety_model.md`](spec/safety_model.md); the tiers - what is checked at compile time, what only when the program runs, and what is the programmer's job - are in [What Zoril Checks](SAFETY.md).
- Any known gaps where the compiler accepts unverified constructs in checked code are tracked in [`doc/spec/safety_model.md#known-gaps`](spec/safety_model.md#known-gaps).
- **Evidence, not a proof:** a matrix entry says which checks were tested, not that every route to the operation is covered, so the release bar is a recorded fuzzing budget as well: **2,638,155** generated programs that compiled and ran (the bar is 2,500,000), over seeds **1-882000** (x 8) in **17 h 31 min** of wall time, with no fault (any signal other than expected traps) and no program the `rustc` differential oracle flagged, met on the previous code; on the code released here a shorter session compiled and ran **755,772** programs with no fault, no flagged program and no disagreement between whole-program and `zbuild` builds, and a full release-bar run on this code is planned soon. The record, the allowlist of intended differences and the coverage report are in [`bench/fuzz/README.md`](../bench/fuzz/README.md). A budget bounds what was tried; it does not bound the language.
- **Current Status (v0.1.0-alpha):** There are **no GAP rows** in the 78-row architecture matrix; the open soundness holes in checked code (where views of frame-owned storage escape through indirect routes) are tracked as `known_gap` probes in [`doc/spec/safety_model.md#known-gaps`](spec/safety_model.md#known-gaps) and documented in [`doc/SAFETY.md`](SAFETY.md) §6. All 78 rows are under continuous automated verification (`make safety-model` and `make safety-matrix`, running every probe).
