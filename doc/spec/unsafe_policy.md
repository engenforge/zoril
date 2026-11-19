# Zoril Policy on the `unsafe` Boundary

Normative. This document states what Zoril's safe/unsafe boundary is _for_, so the marker is built against a policy rather than designed from the syntax outward. It is Zoril's own position.

**The policy in one sentence:** `unsafe` marks operations the compiler cannot verify, so that everything _not_ marked can be trusted — and application code should never need to write it.

## 1. What the marker enables — and what it does not

**`unsafe` enables a fixed, enumerated set of operations. It does not disable verification.**

Inside an `unsafe` region Zoril keeps every check it enforces outside: region outlives, ownership and move tracking, borrow aliasing, immutability, and runtime bounds checking. The marker only permits operations that are otherwise rejected (verified in [`bench/safety_matrix/README.md`](../../bench/safety_matrix/README.md)). Rust works the same way: `unsafe` there enables a few specific operations and leaves the borrow checker active. A marker that disabled region and ownership checking would reopen every known gap inside every block.

The operations `unsafe` enables:

- **Dereferencing a raw pointer** (`*p`, `&*p`, `p[i]`), including implicitly: `p.field`, `p.0`, a method call through it, a call returning a raw pointer (`*f()`), and using it where a reference is expected.
- **Making a reference or a slice** out of an integer, a pointer or a type parameter (`@ptr_cast<&T>`, `@ptr_from_int<&T>`, `@ptr_cast<[T]>`), because nothing would check the null-ness or the borrow. Creating a raw pointer is not in this list: `n as *T`, `@ptr_from_int<*T>` and `@ptr_cast<*T>` are safe, because every _use_ of a raw pointer needs `unsafe` from the pointer's own type, and this leaves a fixed hardware address a spelling in a `static`.
- **Calling an `extern` function**.
- **Calling an `unsafe fn`, or making one into a `fn` value** (`let f: fn(*i32) -> i32 = unsafe { rd };`, and as an argument, a struct field, an assignment or a return; a method, and an `unsafe extern` declaration, as much as a function). A call through a `fn` value is never marked, and the value can reach code its maker never sees, so the block that makes it claims the function is safe to call with every argument the plain `fn` type admits: the same obligation as a safe wrapper whose body calls it (`fn wrap(p: *i32) -> i32 { return unsafe { rd(p) }; }`) or a closure that does (`|p: *i32| -> i32 { return unsafe { rd(p) }; }`), both of which make the same value. If the function has a precondition its arguments can break, the value is not safe to make. Reading a `fn` value from raw memory is the same claim.
- **A system call** (`@syscall`): the kernel takes addresses as plain integers, so `read`, `mmap`, `munmap` and the rest can write or unmap any memory.
- **An uninitialized stack slot** (`@alloca<T>(1)`): reading it before writing it reads a stale value, a wild pointer if `T` is a reference.
- **Forging a slice** from a pointer and a length (`@slice(p, n)`), except where the length is a literal `0`; from a reference as much as from a raw pointer, since a reference vouches for one element, not `n` of them. If `n` is wrong, every later `s[i]` is a memory-safety bug that reads as ordinary checked code; Rust draws the line in the same place (`slice::from_raw_parts` is `unsafe`, indexing the result is not). A zero-length slice permits no access, so gating it would gate nothing.
- **Casting a number to `bool` or `char`** (`5 as bool`, `0xD800 as char`). Checked code cannot forge either value: a `bool` is 0 or 1 (`match` and `!` rely on it) and a `char` is a Unicode scalar value (`Str`'s UTF-8 invariant assumes it); a `u8` is the one source that already stands for a `char`. Inside `unsafe` both casts are the escape hatch: `unicode::char_from_u32` uses the `char` one after its own range check, and a forged `bool` costs a deterministic `zoril_abort` (exit 1) at the first two-armed `match`, not memory safety.

Trusted attribute claims, which establish contracts without being executable operations:

- **`#[borrows(..)]`** on a function ([`surface_syntax.md`](surface_syntax.md) §7.2) narrows which arguments a returned reference keeps borrowed, typically to say the result lives in an arena. The compiler rejects the visible contradiction (returning an address computed from an unlisted parameter); whether a pointer _loaded_ through a parameter really outlives that parameter is the author's promise, as with `unsafe`.
- **`#[unsafe(borrows(..))]`** is the marked form the compiler trusts where it names fewer parameters than the body returns a view of ([`doc/design/provenance.md`](../design/provenance.md) §3, _Checked contracts_, tier 3): the author knows where the result points and the analysis does not (`Args.get`'s slice of process memory, read through a raw pointer that the analysis ties to `self`). The function stays safe to call, so the trust is marked at the attribute rather than on every caller. Visible contradictions are refused in this form too, and each use in `stdlib/` carries a `// SAFETY:` comment.
- **`#[unsafe(stores(..))]`** declares a store effect on an `extern` declaration (`#[unsafe(stores(src -> dest))]` or `#[unsafe(stores(none))]`, [`surface_syntax.md`](surface_syntax.md) §9.1) when foreign code writes a pointer-carrying argument into another parameter or into external memory.
- **`#[fresh]`** ([`surface_syntax.md`](surface_syntax.md) §2.5) on an `unsafe fn` returning a raw pointer is the author's promise that each call returns memory no other live pointer reaches, owned by the caller (an allocator's anonymous `mmap`). The compiler refuses it anywhere else; whether the memory is fresh is not checked.

**What a raw pointer points to is the dereferencing block's to check.** A raw pointer value may dangle: checked code may copy one out of an owner and then drop the owner, freeing the block it points to, and the compiler accepts it, because nothing tells it that the owner owns what its raw pointer field points to. Two things stay checked: the address the value carries, so a raw pointer holding an address of the frame may not leave the frame ([`doc/spec/safety_model.md`](safety_model.md) §3.2), and the dereference, which needs `unsafe`. The block that dereferences the pointer answers for the storage being live, as it answers for the pointer not being null.

## 2. The standard library owes callers a safe API

Following the safe-abstraction model: primitives _use_ unsafe internally and _expose_ safe interfaces. A caller who triggers memory unsafety without writing `unsafe` themselves has found a bug in the library, not made a mistake.

`Vec` is the canonical example of a structure that is unsafe inside and safe outside:

```zoril,no-test
pub fn get(self: &Vec<T>, index: usize) -> Option<&T>
pub fn get_mut(self: &mut Vec<T>, index: usize) -> Option<&mut T>
```

Public stdlib functions return raw pointers (`*T` or `*mut T`) only when the pointer _is_ the abstraction on offer — the **allocator primitives** (`arena_init`, `zoril_allocator_alloc`, `zoril_allocator_realloc`, `heap_alloc`, `mmap_or_trap`, `mmap_anon`, `mmap_anon_or_trap`), where a reference would misstate ownership. Every other public API returns references, `Option`, `Result`, or owned values.

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

Fine-grained `unsafe { }` is viable: even pointer-dense compiler lowering modules stay low in line density once internal APIs return references rather than raw pointers. Marking every function that contains an unsafe operation as `unsafe fn` is not: markers are **sparse but spread**, so per-function density stays high even when line density is low. Zoril therefore uses fine-grained block granularity inside function bodies.

`unsafe fn` is reserved for interface contracts: a function must be declared `unsafe fn` when it requires caller-guaranteed preconditions that the type system cannot prove — specifically, any public function that accepts a raw pointer that it dereferences (such as allocator and low-level syscall wrappers like `arena_free`, `arena_reset`, `mmap_or_trap`, `munmap_or_trap`, `sys_execve`). Calling an `unsafe fn` requires an enclosing `unsafe` block or `unsafe fn` body.

### Calibration against Rust and Metric Definitions

Line density is defined as non-blank, non-comment lines lying inside brace-matched `unsafe { }` blocks divided by total non-blank, non-comment lines (`scripts/check_safety_figures.sh --density`). A one-time measurement of the Rust source tree provides reference baselines (`rustc` `compiler/` at 0.61% across 663k LOC; Rust `library/core` + `alloc` at 6.03% across 109k LOC). Live Zoril density figures and block counts for `src/`, `stdlib/`, and the example JSON application are tracked in [`bench/safety_matrix/README.md`](../../bench/safety_matrix/README.md).

Most compiler `unsafe` density is a missing-abstraction problem rather than inherent low-level work: it falls sharply when API signatures return references instead of raw pointers (`&Arena`, `Result`). **The target for `src/` is ~2–3%** — between `rustc` and Rust's standard library, defensible for a self-hosted compiler that also carries its own allocator and IL machinery. _The comparison is approximate:_ Rust's `unsafe` blocks also cover FFI and union access that Zoril's metric does not count, and Zoril counts dereferences Rust would not need at all.

**Application validation and metric limits:** The policy's expectation — zero `unsafe` in application code (§4) — is checked by measuring real applications (such as the example CLI JSON tool, validated at 0.00% marker density and 0 `unsafe { }` blocks). `scripts/marker_density.sh` counts raw dereferences, pointer casts, and reference forgeries within function bodies rather than `unsafe { }` blocks, and does not inspect struct field types; enforcing §2 safe abstraction boundaries therefore requires making raw pointer fields private alongside syntactic marker counting. Writing idiomatic auto-deref (`node.field`) rather than explicit `(*node).field` on pattern-matched references avoids false positives in syntactic marker heuristics.

## 6. Where Zoril differs from its peers

Different toolchains handle the balance between runtime checks and optimized execution differently: `rustc -O` disables integer overflow panics in release builds by default, and Zig's `ReleaseFast` mode disables runtime bounds checking for maximum throughput (see [`language_comparison.md`](../language/language_comparison.md)).

**Zoril maintains uniform safety checks across all builds.** Bounds checks remain active and identical across all configurations. This aligns code-level safety boundaries (`unsafe` blocks) with consistent build-level verification.

The corollary is that any limitation in Zoril's checks applies equally across all builds: without alternative build modes, compiler soundness must be maintained consistently.

## 7. Reference and raw-pointer mutability

`&T` means read-only, enforced through writes, `&mut self` calls, and call arguments, not just through the binding it was assigned to. The rule is drawn on the **declared IL type**, not on where a value came from:

- **`Ptr`** (the IL tag both `&T` and non-mut `*T` erase to — the two are indistinguishable once lowered) — **read-only**. Assigning through it, or using it to satisfy a `&mut T`/`*mut T` parameter or method receiver, is a compile error.
- **`PtrMut`** (both `&mut T` and `*mut T` erase to this) — the only writable pointer type.

This is Rust's own split: `&T` and `*const T` both reject writes; `&mut T` and `*mut T` both permit them. `unsafe { *p = v; }` on a `*const T` in Rust is `error[E0594]`, requiring a cast to `*mut T` first — Zoril requires the same `as *mut T` cast, which makes it the single writable raw-pointer spelling.

**The escape hatch is unaffected.** A `*mut T` value read _out of_ a `&T` — e.g. a `*mut Inner` field on a struct reached through `&Outer` — stays writable. `&T`'s read-only-ness governs writes that land in `&T`'s own referent; it says nothing about a different, unchecked pointer merely stored there. This is what keeps raw pointers the documented unsafe boundary rather than something `&T`'s reach could shut off by accident.

**Where this is stricter than Rust:** Rust's `UnsafeCell<T>` grants interior mutability through a `&T` — the one sanctioned way to write behind a shared reference. Zoril has no equivalent today, so this rule has no such exception. That costs nothing yet because nothing in Zoril depends on it, but it means the rule above is not quite "Zoril does what Rust does" — it is stricter by exactly the `UnsafeCell` gap, and that asymmetry is recorded here rather than left to be rediscovered.

The rule is a type check, not a dataflow one, so it covers a `&T` reached through a parameter, a struct field, a returned reference or an indexed place, not only a locally-initialized `let r: &T = &expr;`.
