# Zoril Policy on the `unsafe` Boundary

Normative. This document states what Zoril's safe/unsafe boundary is _for_, so the marker is built against a policy rather than designed from the syntax outward. It is Zoril's own position, derived from a survey of prior art recorded in `doc/language/best_practices_for_unsafe_keyword.md`.

**The policy in one sentence:** `unsafe` marks operations the compiler cannot verify, so that everything _not_ marked can be trusted — and application code should never need to write it.

## 1. What the marker enables — and what it does not

**`unsafe` enables a fixed, enumerated set of operations. It does not disable verification.**

Inside an `unsafe` region Zoril keeps every check it enforces outside: region outlives, ownership and move tracking, borrow aliasing, immutability, and runtime bounds checking. The marker only permits operations that are otherwise rejected (probes [`14_null_deref.zrl`](../../bench/safety_matrix/probes/14_null_deref.zrl), [`33_forged_pointer_unsafe.zrl`](../../bench/safety_matrix/probes/33_forged_pointer_unsafe.zrl), [`140_extern_call_outside_unsafe.zrl`](../../bench/safety_matrix/probes/140_extern_call_outside_unsafe.zrl), [`129_syscall_outside_unsafe.zrl`](../../bench/safety_matrix/probes/129_syscall_outside_unsafe.zrl), [`131_alloca_outside_unsafe.zrl`](../../bench/safety_matrix/probes/131_alloca_outside_unsafe.zrl), [`63_slice_forged_from_reference.zrl`](../../bench/safety_matrix/probes/63_slice_forged_from_reference.zrl)). Rust works the same way: `unsafe` there enables a few specific operations and leaves the borrow checker active. A marker that disabled region and ownership checking would reopen every known gap inside every block.

The operations `unsafe` enables:

- **Dereferencing a raw pointer** (`*p`, `&*p`, `p[i]`), including implicitly: `p.field`, `p.0`, a method call through it, a call returning a raw pointer (`*f()`), and using it where a reference is expected ([`14_null_deref.zrl`](../../bench/safety_matrix/probes/14_null_deref.zrl), [`120_raw_pointer_field_access.zrl`](../../bench/safety_matrix/probes/120_raw_pointer_field_access.zrl)).
- **Making a reference or a slice** out of an integer, a pointer or a type parameter (`@ptr_cast<&T>`, `@ptr_from_int<&T>`, `@ptr_cast<[T]>`), because nothing would check the null-ness or the borrow ([`tests/error_reporting/err_ptr_cast_to_reference_or_slice.zrl`](../../tests/error_reporting/err_ptr_cast_to_reference_or_slice.zrl)). Creating a raw pointer is not in this list: `n as *T`, `@ptr_from_int<*T>` and `@ptr_cast<*T>` are safe, because every _use_ of a raw pointer needs `unsafe` from the pointer's own type, and this leaves a fixed hardware address a spelling in a `static`.
- **Calling an `extern` function** ([`140_extern_call_outside_unsafe.zrl`](../../bench/safety_matrix/probes/140_extern_call_outside_unsafe.zrl)).
- **A system call** (`@syscall`): the kernel takes addresses as plain integers, so `read`, `mmap`, `munmap` and the rest can write or unmap any memory ([`129_syscall_outside_unsafe.zrl`](../../bench/safety_matrix/probes/129_syscall_outside_unsafe.zrl)).
- **An uninitialized stack slot** (`@alloca<T>(1)`): reading it before writing it reads a stale value, a wild pointer if `T` is a reference ([`131_alloca_outside_unsafe.zrl`](../../bench/safety_matrix/probes/131_alloca_outside_unsafe.zrl)).
- **Forging a slice** from a pointer and a length (`@slice(p, n)`), except where the length is a literal `0`; from a reference as much as from a raw pointer, since a reference vouches for one element, not `n` of them ([`63_slice_forged_from_reference.zrl`](../../bench/safety_matrix/probes/63_slice_forged_from_reference.zrl)). If `n` is wrong, every later `s[i]` is a memory-safety bug that reads as ordinary checked code; Rust draws the line in the same place (`slice::from_raw_parts` is `unsafe`, indexing the result is not). A zero-length slice permits no access, so gating it would gate nothing.
- **Casting a number to `bool` or `char`** (`5 as bool`, `0xD800 as char`). Checked code cannot forge either value: a `bool` is 0 or 1 (`match` and `!` rely on it) and a `char` is a Unicode scalar value (`Str`'s UTF-8 invariant assumes it); a `u8` is the one source that already stands for a `char`. Inside `unsafe` both casts are the escape hatch: `unicode::char_from_u32` uses the `char` one after its own range check, and a forged `bool` costs a deterministic `zoril_abort` (exit 1) at the first two-armed `match`, not memory safety.

One more construct is a trusted claim without being an operation: **`#[borrows(..)]`** on a function (`surface_syntax.md` §7.2). It narrows which arguments a returned reference keeps borrowed, typically to say the result lives in an arena. The compiler rejects the visible contradiction (returning an address computed from an unlisted parameter; probe [`93_borrows_attribute_lie.zrl`](../../bench/safety_matrix/probes/93_borrows_attribute_lie.zrl)); whether a pointer _loaded_ through a parameter really outlives that parameter is the author's promise, as with `unsafe`. The marker-density report counts these claims.

## 2. The standard library owes callers a safe API

Following the safe-abstraction model: primitives _use_ unsafe internally and _expose_ safe interfaces. A caller who triggers memory unsafety without writing `unsafe` themselves has found a bug in the library, not made a mistake.

`Vec` is the canonical example of a structure that is unsafe inside and safe outside:

```zoril,no-test
pub fn get(self: &Vec<T>, index: usize) -> Option<&T>
pub fn get_mut(self: &mut Vec<T>, index: usize) -> Option<&mut T>
```

Public stdlib functions return raw pointers (`*T` or `*mut T`) only when the pointer _is_ the abstraction on offer — the **allocator primitives** (`arena_init`, `zoril_allocator_alloc`, `zoril_allocator_realloc`, `heap_alloc`, `mmap_or_trap`), where a reference would misstate ownership. Every other public API returns references, `Option`, `Result`, or owned values.

**Acceptance for this clause is mechanical:** no public stdlib function returns a raw pointer _except_ the allocator primitives above, and that exemption is listed explicitly rather than left to judgement. Returning `Option<&T>` also avoids the null-sentinel idiom and spares callers from writing `(*p)`.

## 3. Legitimate uses

`unsafe` is a necessary tool, not an admission of defeat. Expected uses:

- **FFI** — `extern` calls cross into code Zoril cannot analyse.
- **Allocators and raw memory** — arena implementations, `memcpy`/`memset`, anything that manufactures storage.
- **Core data structures** — `Vec`, `ByteVec`, intern tables: unsafe inside, safe outside.
- **Conservative-inference escapes** — Zoril's region inference is a static analysis and will reject some valid programs. Using the marker where the programmer can prove what the analysis cannot is _correct use_, not a workaround. This will happen; anticipate it rather than treating the first instance as an analysis bug.
- **Measured optimisation** — bypassing a check in a profiled hot path. Rare, and requires the profile.

## 4. Expectation: zero in application code

An application built on Zoril's standard library should contain **no** `unsafe` at all. Its appearance in ordinary application logic is a review finding, and the first question should be whether a safe abstraction already exists or should.

The division of labour is deliberate: the compiler, the standard library, and the runtime carry the unsafe code; everything above them consumes safe APIs.

## 5. Measuring conformance — and the trap in it

`scripts/marker_density.sh` reports two figures per file. Read them for different decisions:

- **line density** sizes `unsafe { }` blocks
- **per-function density** sizes `unsafe fn`, measuring how many functions expose or encapsulate unsafe boundaries

Fine-grained `unsafe { }` is viable: even the most pointer-dense module in the compiler (`src/lower_zir_to_zil.zrl`) reaches a line density of about 2.5% once its APIs return references rather than raw pointers. Marking every function that contains an unsafe operation as `unsafe fn` is not: markers are **sparse but spread**, so per-function density stays high (about 40%) even when line density is low. Zoril therefore uses fine-grained block granularity inside function bodies.

`unsafe fn` is reserved for interface contracts: a function must be declared `unsafe fn` when it requires caller-guaranteed preconditions that the type system cannot prove — specifically, any public function that accepts a raw pointer that it dereferences (such as allocator and low-level syscall wrappers like `arena_free`, `arena_reset`, `mmap_or_trap`, `munmap_or_trap`, `sys_execve`). Calling an `unsafe fn` requires an enclosing `unsafe` block or `unsafe fn` body.

### Calibration against Rust

It is tempting to expect a compiler to carry unsafe code in the same way Rust's `Vec` and `String` do. The analogy holds for the standard library and fails for the compiler. Measured on the Rust source tree (a one-time measurement), counting lines inside `unsafe { }` blocks against non-comment LOC:

| codebase                                 | layer            | line density            |
| ---------------------------------------- | ---------------- | ----------------------- |
| rustc `compiler/` (663k LOC)             | compiler         | **0.61%**               |
| Rust `library/core` + `alloc` (109k LOC) | stdlib / runtime | **6.03%**               |
| Zoril `src/` (39k non-comment LOC)       | compiler         | **4.71%** (725 blocks)  |
| Zoril `stdlib/` (4.4k non-comment LOC)   | stdlib           | **10.94%** (170 blocks) |
| Zoril example JSON tool (1.9k LOC)       | application      | **0.00%** (0 blocks)    |

The Rust rows are a one-time measurement of the Rust source tree; the Zoril rows are recomputed by `scripts/check_safety_figures.sh --density` (part of `make test`): lines inside `unsafe { }` blocks, brace-matched, divided by non-blank, non-comment lines (Zoril: 1,916 of 40,717 lines in `src/`, 492 of 4,498 in `stdlib/`, 0 of 1,992 in the example JSON tool). The example tool is not yet published, so a tree that does not carry its sources reports that row as skipped rather than checking it against nothing. The count of blocks is §5 of [`doc/SAFETY.md`](../SAFETY.md).

rustc is essentially unsafe-free because it consumes safe abstractions; the unsafe is concentrated in the standard library, which is exactly the division of labour §2 and §4 describe. **Zoril's compiler is roughly 8× rustc's density and now below Rust's standard library's**, and Zoril's own standard library is 1.8× Rust's.

Most of that density is a missing-abstraction problem rather than inherent low-level work: it falls sharply when API signatures return references instead of raw pointers. That is what the `src/` figure has done - 10.76% at 22,000 non-comment lines, 5.13% at 37,000 - because the arena and collection APIs moved from raw pointers to `&Arena` and to `Result`. Work that is genuinely low-level does not disappear when a signature changes.

**The target for `src/` is ~2–3%** — between rustc and Rust's standard library, defensible for a self-hosted compiler that also carries its own allocator and IL machinery.

_The comparison is approximate:_ Rust's `unsafe` blocks also cover FFI and union access that Zoril's metric does not count, and Zoril counts dereferences Rust would not need at all. The gap to rustc survives that imprecision; the near-parity with Rust's standard library does not, so stop leaning on the ordering once Zoril is near 2%.

**Application validation:** The policy's expectation - "application code writes no unsafe" (§4) - is validated by an example application written in Zoril, not yet published: a CLI JSON query, format, and schema validation tool of 1,992 non-comment LOC across 9 modules. Across all modules, `scripts/marker_density.sh` reports:

- **0.00% line density** (0 marker lines / 1,992 LOC)
- **0.00% per-function density** (0 / 51 functions)
- **0 ptr-cast lines** (`as *T`)
- **0 ref-forge lines** (`&*p`)

and the app holds **no `unsafe { }` block at all** (0 of 1,992 non-comment lines; `scripts/check_safety_figures.sh --density` recomputes it, and the application's test suite fails if one returns). It obtains its arena with `Arena.new`, builds `Vec` and `String` with `new_in(&Arena)` and reads input through the `Result`-returning I/O calls, so it consumes safe abstractions and marks nothing.

_Expressiveness of the safe subset:_ the example tool is written with idiomatic sum types, pattern matching, and `Result` rather than struct tags and sentinel values:

1. **Payload enums (`JsonValue`, `QueryStep`):** `JsonNode` carries a tagged union `JsonValue` (`Null`, `Bool(bool)`, `Int(i64)`, `Float([u8])`, `Str([u8])`, `Array`, `Object`), and `QueryStep` uses variant payloads (`Field([u8])`, `Index(i64)`, `Wildcard`, `FilterEq(FilterCond)`, etc.). This keeps node memory small (20,000-record DOM peak RSS 30.1 MB, parse+query 103 ms).
2. **`Result<T, E>` error propagation:** `Parser` returns `Result<u32, ParseError>` and `Validator` returns `Result<(), [u8]>`. Error propagation uses explicit `match` blocks (e.g. `match self.parse_value(doc) { Result.Ok(id) => ..., Result.Err(e) => return Result.Err(e) }`), which makes failure handling exhaustive and avoids silent error swallowing.
3. **Pattern matching exhaustiveness:** Exhaustiveness checking is exercised across 51 functions. When matching on payload enums in targeted helpers, wildcard arms (`_ => ...`) are required for non-exhaustive subsets.
4. **Match pattern bindings and marker heuristics:** Zoril auto-dereferences reference types (`&T` / `&mut T`), allowing direct access such as `node.field`. Writing an explicit C-style dereference `(*node).field` on a reference binding introduced by a pattern arm triggers a false-positive in `scripts/marker_density.sh`, because its heuristic cannot see the binding's type. Idiomatic auto-deref (`node.field`) avoids this and preserves the true 0.00% marker density.

_Metric limits:_ `scripts/marker_density.sh` counts raw dereferences, pointer casts, and reference forgeries within function bodies and statements. It does **not** count `unsafe { }` blocks - the table above and `doc/SAFETY.md` §5.3 do, by a different method - and it does not inspect struct field types. An interface leaking a raw pointer field (e.g. `pub argv: **u8`) would not trigger marker density without a dereference. Enforcing §2 safe abstraction boundaries therefore requires type-level encapsulation (making raw pointer fields private) alongside syntactic marker counting.

## 6. Where Zoril differs from its peers

Different toolchains handle the balance between runtime checks and optimized execution differently: `rustc -O` disables integer overflow panics in release builds by default, and Zig's `ReleaseFast` mode disables runtime bounds checking for maximum throughput (see `doc/language/language_comparison.md`).

**Zoril maintains uniform safety checks across all builds.** Bounds checks remain active and identical across all configurations. This aligns code-level safety boundaries (`unsafe` blocks) with consistent build-level verification.

The corollary is that any limitation in Zoril's checks applies equally across all builds: without alternative build modes, compiler soundness must be maintained consistently.

## 7. Reference and raw-pointer mutability

`&T` means read-only, enforced through writes, `&mut self` calls, and call arguments, not just through the binding it was assigned to. The rule is drawn on the **declared IL type**, not on where a value came from:

- **`Ptr`** (the IL tag both `&T` and non-mut `*T` erase to — the two are indistinguishable once lowered) — **read-only**. Assigning through it, or using it to satisfy a `&mut T`/`*mut T` parameter or method receiver, is a compile error.
- **`PtrMut`** (both `&mut T` and `*mut T` erase to this) — the only writable pointer type.

This is Rust's own split: `&T` and `*const T` both reject writes; `&mut T` and `*mut T` both permit them. `unsafe { *p = v; }` on a `*const T` in Rust is `error[E0594]`, requiring a cast to `*mut T` first — Zoril requires the same `as *mut T` cast, which makes it the single writable raw-pointer spelling.

**The escape hatch is unaffected.** A `*mut T` value read _out of_ a `&T` — e.g. a `*mut Inner` field on a struct reached through `&Outer` — stays writable. `&T`'s read-only-ness governs writes that land in `&T`'s own referent; it says nothing about a different, unchecked pointer merely stored there. This is what keeps raw pointers the documented unsafe boundary rather than something `&T`'s reach could shut off by accident. Pinned by [`tests/functional/pointers/mut_ptr_field_through_shared_ref.zrl`](../../tests/functional/pointers/mut_ptr_field_through_shared_ref.zrl).

**Where this is stricter than Rust:** Rust's `UnsafeCell<T>` grants interior mutability through a `&T` — the one sanctioned way to write behind a shared reference. Zoril has no equivalent today, so this rule has no such exception. That costs nothing yet because nothing in Zoril depends on it, but it means the rule above is not quite "Zoril does what Rust does" — it is stricter by exactly the `UnsafeCell` gap, and that asymmetry is recorded here rather than left to be rediscovered.

The rule is a type check, not a dataflow one, so it covers a `&T` reached through a parameter, a struct field, a returned reference or an indexed place, not only a locally-initialized `let r: &T = &expr;`.
