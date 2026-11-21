# Zoril Safety Model

Normative. This document specifies Zoril's safety verification architecture, the properties enforced in checked code across each language domain, the evidence model behind the safety matrix, the raw-pointer rules, and the runtime trap and exit-code conventions.

The per-row probe table lives in [`bench/safety_matrix/matrix.md`](../../bench/safety_matrix/matrix.md). The machine-checked probe inventory, readable row summaries, open `known_gap` catalogue, trusted-base census, and ZIR/ZIL route reachability audit live in [`bench/safety_matrix/README.md`](../../bench/safety_matrix/README.md). User-facing tiers and known-gap explanations are summarized in [`doc/SAFETY.md`](../SAFETY.md).

---

## 1. Verification Architecture

Zoril's memory-safety guarantees cover programs compiled from Zoril source (`.zrl`). Hand-written ZIL (`.zil`) is checked by `zilc` for operand types and ZIL-level verification (stack-address escapes, constant arena bounds, and common-mistake checks), not for full memory safety.

Zoril checks memory and type safety through a **three-level pipeline** whose checks remain active in every build configuration:

```text
Source Code (.zrl)
       │
       ▼
   AST / Semantics (surface_syntax.md)
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. ZIR Level: Named Place Verification                      │
│    - Ownership & move tracking (Uninitialized/Owned/Moved)  │
│    - Active borrow conflicts (& vs &mut) & reborrowing      │
│    - Drop-once invariants & linear resource consumption     │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. ZIL Level: SSA Verification                              │
│    - SSA type safety & local stack-slot origin tracking     │
│    - Region escapes (stack/owned-storage addresses)         │
│    - Constant-size arena capacity checks (intra & inter)    │
│    - Must-use discard diagnostics                           │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Runtime Trap Generation                                  │
│    - Fixed-size array & dynamic slice bounds checks         │
│    - Variable shift-count range checks                      │
│    - Checked stdlib arithmetic & allocation traps           │
└─────────────────────────────────────────────────────────────┘
```

### Visibility of Levels

ZIR, the mid-level representation over named places, is internal to the compiler. ZIL, the low-level SSA representation, is inspectable via `zoril --emit-zil` and specified in [`intermediate_language.md`](intermediate_language.md). Under modular compilation ([`modular_compilation.md`](modular_compilation.md)), `.zri` interface files carry the inter-procedural summaries needed to enforce borrow, region, and arena checks across module boundaries.

### Level 1: ZIR (Named-Place Verification)

Runs on each function's ZIR after AST lowering and before ZIL emission. It tracks place initialization and ownership states across basic blocks, branches, loops, and `defer` scopes; enforces affine usage of non-`Copy` values; rejects use-after-move, double-drop, and moves out of borrows; and checks exclusive mutable borrowing (`&mut`) and strict reborrowing.

### Level 2: ZIL (SSA Verification)

Runs on the lowered SSA module (`ILModule`). It verifies SSA type invariants, tracks stack-slot origins and provenance through copies, offsets, casts, slices, and slot loads/stores, rejects addresses of local frames or dropped owned storage leaving their scope, and checks constant-size arena budgets within and across direct calls.

### Level 3: Runtime Trapping

Inserted during ZIR-to-ZIL lowering and in standard-library primitives. Indexing on arrays and slices emits unsigned length comparisons on both read and write paths, branching on failure to trap blocks that exit with status `134`.

### The Safe / Unsafe Reachability Boundary

Cutting across all three levels is the `unsafe` reachability gate, specified normatively in [`unsafe_policy.md`](unsafe_policy.md) §1. `unsafe { ... }` (or an `unsafe fn` body) permits a fixed set of operations the compiler cannot statically verify: dereferencing or indexing a raw pointer (explicitly or implicitly), converting a raw pointer or integer into a reference or slice, forging a non-zero-length slice with `@slice`, calling an `extern` function or an `unsafe fn` (or converting an `unsafe fn` into a plain `fn` value), invoking `@syscall`, allocating an uninitialized stack slot with `@alloca`, accessing non-scalar `static mut` items, and casting numbers to `bool` or `char`. Creating a raw pointer (`n as *T`, `@ptr_from_int<*T>`, `@ptr_cast<*T>`) is allowed in checked code because every dereference or reference conversion of the resulting pointer remains gated on its raw type.

Crucially, `unsafe` is a reachability boundary, **not** a verification bypass: ZIR ownership/borrow checking, ZIL region checking, immutability rules, and runtime bounds checks remain fully active inside every `unsafe` block.

---

## 2. Safety Properties by Domain

The safety matrix ([`bench/safety_matrix/matrix.md`](../../bench/safety_matrix/matrix.md)) groups Zoril's verified guarantees across the domains below.

### 2.1 Spatial Bounds and Layout

- **Array and slice bounds (`surface_syntax.md` §11.2.3):** Out-of-bounds reads and writes on `[T; N]` and `[T]` / `[mut T]` trap at run time with exit status `134`. Constant out-of-bounds array indices are rejected at compile time.
- **Indexing through references:** A reference is indexable only when its referent is an array, slice, or `Vec<T>`; indexing a reference to a scalar or unrelated struct is rejected at compile time.
- **Length and size ceilings:** Declared array lengths and repeat counts must fit in 32 bits, and type sizes must not exceed `isize::MAX`, ensuring element offset arithmetic cannot wrap across the signed 64-bit address range.
- **Slice header integrity:** A `[T]` or `[mut T]` place always holds a valid `{ptr, len}` pair; raw `[T; N]` values do not coerce implicitly to slices without borrowing (`&arr` / `&mut arr`), and forging a slice with non-zero length via `@slice` requires `unsafe`.
- **Raw-pointer indexing:** Indexing `*T` or `*mut T` performs unchecked pointer arithmetic and is reachable only inside `unsafe`.

### 2.2 Temporal Ownership, Moves, and Drops

- **Affine moves (`surface_syntax.md` §7.1):** Types that are not structurally `Copy` (such as `Box<T>`, `Drop` types, `Vec<T>`, `String`, `ByteVec`, `HashMap`, and linear resources) move on assignment, parameter passing, return, or closure capture. Reading, writing, or mutating through a moved binding is rejected at compile time.
- **Structural `Copy`:** Primitive values and structs/enums whose fields are all `Copy` and which do not implement `Drop` remain usable after assignment.
- **Drop-once invariants (`surface_syntax.md` §7.3, §8.4):** Values with destructors run `drop` once on every normal control-flow path (scope exit, early return, loop break, reassignment, and conditional moves). Double drops via `@drop`, use-after-drop, partial moves of fields out of `Drop` aggregates, and moving non-`Copy` elements out of arrays or slices by value are rejected at compile time.
- **`defer` ordering and move checking:** `defer` blocks run in LIFO order on normal scope exit and return; moving a value used by a `defer` (or using a previously moved value in a `defer`) is rejected. Runtime traps (`134`) exit immediately without running `defer` blocks.
- **Linear resources (`surface_syntax.md` §3.12, §9.4):** Linear capabilities (`fd`, `ioring`) must be explicitly consumed on every path (including early returns and branches); implicit drops, leaks inside structs/tuples/arrays/enums/boxes, duplicates, double closes, and capability mismatches (`fd<r>` vs. `fd<w>`) are rejected at compile time.

### 2.3 Borrowing, Immutability, and Two-Tier Liveness

- **Exclusive mutability (`surface_syntax.md` §7.2):** `&mut T` excludes all other active borrows of the same place while live. Borrows extend through projected reborrows (`&r.f`), `match`/`if let`/`while let` payload bindings on references, and closure reference captures.
- **Read-only shared references (`unsafe_policy.md` §7):** `&T` and `*T` share the read-only `Ptr` IL class; Zoril provides no `UnsafeCell` interior mutability. Assigning through `&T`, calling `&mut self` methods through `&T`, or passing `&T` where `&mut T` is expected is rejected at compile time regardless of how the `&T` was obtained.
- **Strict reborrowing:** Views extracted from collections (`Vec.get`, `Vec.as_slice`, `Option.unwrap`) and `&mut` references passed through reference variables or parameters keep their source borrowed across `&mut self` calls.
- **Returned-reference contracts:** Call results that may hold references retain borrows over the arguments named in the function's `#[borrows(..)]` contract (or its Rust-like default). `#[borrows(..)]` rejects visible contradictions where the body returns an address from an unlisted parameter; `#[unsafe(borrows(..))]` is a trusted narrowing checked only against visible contradictions (`unsafe_policy.md` §1).
- **Two-tier liveness:** A view held in a local keeps its source borrowed across mutations; a view stored outside the frame or returned across calls is governed by storage-release liveness, distinguishing operations that free or reset backing memory from operations (such as bump-arena `Vec` growth) that leave prior buffers valid.

### 2.4 Region and Frame Outlives

- **Stack and local-storage escape (`surface_syntax.md` §11.2.4):** Returning a reference, slice, capturing closure, or raw pointer pointing into the current function's stack frame, or into an owned `Box` dropped on return, or into storage owned by a local collection, is rejected at compile time.
- **External stores and callee summaries:** Writing a stack or owned-local address into memory that outlives the frame (through a pointer parameter, into a global, or into a heap allocation) is rejected using inter-procedural summaries (`ret_storage`, `stores_storage`, `store_targets`) carried in `.zri` interfaces, together with `#[stores(..)]` / `#[unsafe(stores(..))]` contracts on `extern` declarations.
- **Block-scoped borrow outlives:** Any value leaving scope while still borrowed by an outer binding is rejected at its scope boundary.
- **Globals and `static mut`:** Immutable `static` items cannot be assigned or mutably borrowed. Mutable statics (`static mut`) cannot hold reference types, slice types, or structs containing references. Accessing non-scalar `static mut` items requires `unsafe`; scalar `static mut` access is permitted in checked code under Zoril's single-threaded execution model.

### 2.5 Arenas

- **Arena-tied handles (`surface_syntax.md` §11.2.1):** Collections and views allocated through `&Arena` (`Vec::new_in(&arena)`, `String::new_in(&arena)`, `HashMap.new(&arena)`, `read_file`) borrow the arena handle; calling `reset`, `reset_to`, or `arena_free` while a tied value is live, or moving a tied value out of the arena's owning block, is rejected at compile time.
- **Constant-capacity verification (`surface_syntax.md` §11.2.1, §11.2.2):** Constant-size allocations against constant-capacity arenas are checked statically both within a function and across direct calls; dynamic allocations are bounds-checked against arena capacity at run time (trapping with exit `134`).
- **Raw arena primitives:** The `*_raw` entry points accept raw pointers and require `unsafe`, placing region liveness under the caller's responsibility.

### 2.6 Type, Cast, and Implicit-Conversion Rules

- **Explicit narrowing and checked casts (`surface_syntax.md` §11.2.6):** Implicit conversions never discard bits; narrowing integer conversions require explicit `as`. Casting integers to `bool` or `char` requires `unsafe` (except `u8` widening to `char`). Casting an integer or raw pointer to a reference, slice, enum, array, tuple, struct, `Box`, or generic type parameter in checked code is rejected.
- **Exact mutability behind mutable handles:** Types behind `&mut`, `*mut`, `BoxMut`, and `[mut T]` must match exactly rather than implicitly converting. Function types compare contravariantly on parameter types and covariantly on return types.
- **FFI and C function pointers (`surface_syntax.md` §9.1):** `extern` signatures accept only C-compatible primitive and raw-pointer types (`bool`, sized integers, `usize`/`isize`, floats, raw pointers, `extern "C" fn`). C function pointers cannot be forged from integers or ordinary Zoril function values, and calling one requires `unsafe`.
- **Match exhaustiveness and variant stability (`surface_syntax.md` §5.3):** `match` expressions must cover all enum variants, `bool` values, or include a wildcard arm (guarded arms do not count toward unconditional exhaustiveness). Reassigning an enum under an active payload binding is rejected, and or-pattern alternatives must bind identical names with identical types.
- **Encapsulation (`surface_syntax.md` §11.1.1, §11.1.2):** Private methods, associated functions, associated constants, and private struct fields (including stdlib collection internals) are accessible only within their defining module, protecting module-level `unsafe` invariants from checked callers.
- **Control-flow and return completeness:** Non-unit functions must return on every reachable path, and `?` early returns must match the enclosing function's `Result` or `Option` return type.

### 2.7 Runtime Traps, Arithmetic, and Faults

- **Wrapping integer arithmetic (`surface_syntax.md` §11.2.6):** Signed and unsigned integer `+`, `-`, `*` wrap modulo $2^N$ in every build; sub-word types (`u8`, `i8`, `u16`, `i16`) mask intermediate results to their declared width.
- **Checked shift counts:** Constant out-of-range shift counts fail at compile time; variable shift counts outside `[0, width)` trap with exit `134` unless `@shl_wrap` / `@shr_wrap` is used explicitly.
- **Deterministic faults:** Integer division/modulo by zero and `INT_MIN / -1` raise `SIGFPE`, and unbounded recursion or oversized stack frames touch the guard page and raise `SIGSEGV`.

---

## 3. Evidence Levels and Raw-Pointer Rules

### 3.1 Verification Evidence Levels

Every row in [`bench/safety_matrix/matrix.md`](../../bench/safety_matrix/matrix.md) records which side of the `unsafe` boundary it occupies (`safe`, `unsafe`, `safe / unsafe alias`, or `n/a`) and one of four evidence levels:

- **`example`:** The cited probes and tests fire the mechanism on the listed cases.
- **`routes`:** Every IR/CFG route listed in the row's `Routes` column is exercised by a cited `compile_reject` probe (`scripts/check_route_coverage.sh`).
- **`fuzzed`:** `routes`, plus differential fuzzing (`bench/fuzz/README.md`) generates the row's routes and agrees between the semantic oracle and `--checked` instrumentation.
- **`argued`:** `fuzzed`, plus a documented argument covering every route in the class.

A **GAP** row (or open `known_gap` probe) records an accepted construct that violates a safety property in checked code. A GAP closes only when: (1) its motivating probes fail to compile unchanged, (2) its `Routes` list reaches at least `routes` coverage, and (3) the compiler mutations disabling that check are killed by the row's own probes. See [`bench/safety_matrix/README.md`](../../bench/safety_matrix/README.md) for the live `known_gap` inventory and route-class breakdown.

### 3.2 Raw-Pointer Creation, Preservation, and Dangling Values

- **Creation is safe; use is gated:** Forming `*T` or `*mut T` from an integer or reference does not read or write memory and needs no `unsafe`. Every dereference, field/tuple projection, index, method call, or reference conversion through a raw pointer requires `unsafe`.
- **Type preservation across routes:** Raw pointers retain `RawPtr` / `RawPtrMut` types across type parameters, monomorphization, tuples, structs, arrays, enums, pattern bindings, closure captures, and module interfaces; no route implicitly converts a raw pointer into a checked reference.
- **Raw pointer values may dangle:** A raw pointer copied out of an owning type whose `Drop` frees its backing storage is accepted in checked code because the type system does not associate raw pointer fields with ownership. What remains checked is the address itself: a raw pointer holding a frame-local stack address cannot be returned or stored out of the frame. Dereferencing any raw pointer happens inside `unsafe`, where the programmer must ensure the target storage is live and aligned.
- **Stores through untracked raw heap pointers:** Storing a frame-local address inside `unsafe` through a raw pointer with no tracked origin — such as the result of a `#[fresh]` function or a raw block from `zoril_allocator_alloc(null, ..)` — and then returning that pointer or placing it into a global is outside the provenance guarantee. Both the write through the raw pointer and any later read through it require `unsafe`, and those `unsafe` blocks answer for the stored addresses remaining valid, as in Rust.

### 3.3 Conservative Fallbacks

Where a static analysis encounters an unresolvable or resource-bounded state (such as recursion limits or unknown callee summaries), it fails closed by rejecting the program rather than accepting potentially unsound code (`doc/SAFETY.md` §4.4).

---

## 4. Runtime Trap and Exit-Code Conventions

Zoril separates deterministic safety traps from program panics and hardware faults so tests and callers can distinguish them reliably:

- **Exit `134` (`128 + SIGABRT`) — Deterministic runtime safety trap (`zoril_user_trap`):** array/slice out-of-bounds read or write, variable shift count outside `[0, width)`, dynamic arena capacity exhaustion, `mmap` allocation failure, stdlib size/capacity overflow traps, and `Vec::set_len` above `cap`.
- **Exit `1` — Controlled program panic or unreachable abort (`zoril_abort`):** `Option::unwrap` on `None`, `Result::unwrap` on `Err`, `io` print helpers on I/O failure, and unreachable `match` fall-through.
- **Exit `136` (`SIGFPE`) — Arithmetic exception:** integer division or modulo by zero and `INT_MIN / -1`.
- **Exit `139` (`SIGSEGV`) — Hardware memory fault:** stack exhaustion against the guard page, oversized single stack frame, and unchecked null/dangling dereference or null function pointer call inside `unsafe`.

Exit status `134` is intentionally distinct from `1` so a bounds or allocation trap cannot be confused with a program returning exit code `1`. Statuses `134`, `136`, and `139` reflect Linux `128 + signal` reporting; on all platforms, a trap terminates the process immediately without executing subsequent statements or `defer` blocks.
