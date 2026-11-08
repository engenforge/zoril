# Zoril Safety Model and Verification Mechanisms

This document defines Zoril's concrete safety guarantees, the compiler mechanisms implementing each guarantee, the architectural boundaries where guarantees end, and the automated tests proving each claim.

Every claim in this document is backed by a runnable test in the repository.

---

## 1. Verification Architecture

Zoril checks memory safety with a **two-level verification pipeline** complemented by compiler-inserted runtime traps:

**Which levels you can see.** ZIR, the mid-level representation with named places, is internal to the compiler: there is no way to write it or to ask for it. ZIL, the low-level SSA representation, is visible: it is what `zoril --emit-zil` prints, `zilc` reads, and [`doc/spec/intermediate_language.md`](intermediate_language.md) specifies, and the `.zri` interface file that `zbuild` writes for each module carries the summaries the checks use across modules. A user meets the checks through their diagnostics; the mechanism names below (ZIR, `check_zir`, the verifier) matter to someone reading the compiler.

```
Source Code (.zrl)
       │
       ▼
   AST / Semantics
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. ZIR Level: Named Place Verification (src/check_zir.zrl)  │
│    - Ownership & Move tracking (Uninitialized/Owned/Moved)  │
│    - Active borrow conflicts (& vs &mut)                    │
│    - Drop semantics and linear resource leaks (fd, ioring)  │
└──────────────────────────────┬──────────────────────────────┘
                               │ lower_zir_to_zil.zrl
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. ZIL Level: SSA Verification (src/verify.zrl)             │
│    - SSA type safety & local stack slot tracking            │
│    - Region escapes (dangling stack pointer returns)        │
│    - Constant-size arena capacity checks (intra & inter)    │
│    - Must-use discard warnings                              │
└──────────────────────────────┬──────────────────────────────┘
                               │ lower_zir_to_zil.zrl
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Runtime Trap Generation (src/lower_zir_to_zil.zrl)       │
│    - Fixed-size array bounds checks (read & write)          │
│    - Dynamic slice bounds checks (read & write)             │
│    - Direct sys_exit_group(134) traps (128 + SIGABRT)       │
└─────────────────────────────────────────────────────────────┘
```

Cutting across all three levels is the **safe/unsafe boundary**, enforced during AST-to-ZIR lowering (`src/lower_zir/expr.zrl`, `src/lower_zir/utils.zrl`) against `ZirLowerer.unsafe_depth`. Six operations require an enclosing `unsafe { }` block, and `doc/spec/unsafe_policy.md` §1 is the normative list: dereferencing a raw pointer (including implicitly, through `p[i]`, `p.field`, `p.0`, a method call on it, or using it where a reference is expected); making a _reference or a slice_ out of an integer, a pointer or a type parameter; `@slice` from a raw pointer; calling an `extern` function; `@syscall`; and `@alloca`. Calling an `unsafe fn`, or making one into a `fn` value, requires a block or an `unsafe fn` body as well, since such a function's contract is the caller's and a call through the value is not marked: the block that makes the value takes that contract for every argument the plain `fn` type admits, as a safe wrapper around the call does (`unsafe_policy.md` §1). Creating a raw pointer — `n as *T`, `@ptr_from_int<*T>`, `@ptr_cast<*T>` — is **not** one of them: every _use_ of the pointer is gated on its own type, so the marker belongs on the use. It is a _reachability_ mechanism, not a verification level — the three levels above stay fully active inside a block, so `unsafe` widens what you may write, never what the compiler will check. `doc/spec/unsafe_policy.md` is normative.

### Level 1: ZIR (Mid-Level IR, Named Places)

Runs on each function's ZIR, between AST-to-ZIR and ZIR-to-ZIL lowering (`src/check_zir.zrl`, driven by `src/driver/module.zrl`), on named places before SSA conversion. Tracks place ownership states across basic blocks, branching, and loops. Enforces linear usage of non-`Copy` values, rejects use-after-move and double-drop, and rejects overlapping mutable borrows.

### Level 2: ZIL (Low-Level IR, SSA)

Runs whole-program on the complete `ILModule` in SSA form (`src/verify.zrl`, invoked from `src/main.zrl` `fn check_module`). Tracks SSA definitions, value provenance (`is_stack_slot`, `points_to_stack`), and constant values. Rejects returns of local stack addresses and statically validates constant arena allocations.

### Level 3: Runtime Trapping

Emitted during ZIR-to-ZIL lowering (`src/lower_zir_to_zil.zrl`). For indexing operations on arrays and slices (both read and write), the compiler emits unsigned comparisons against length and branches to trap blocks that invoke raw exit syscalls with exit code 134 (`SIGABRT`).

---

## 2. Safety Properties Matrix

### Origin and Methodology

This matrix is systematically derived from three external enumerations to ensure comprehensive coverage across low-level failure modes:

- **CWE memory-safety classes** — spatial (out-of-bounds), temporal (use-after-free, double-free), initialization, and type-confusion families.
- **Rust's undefined-behaviour list** — the set of things `unsafe` exists to permit: dangling and unaligned access, invalid values for a type (bad enum discriminants, invalid `bool`/`char`), aliasing violations, data races.
- **Zig's "Illegal Behavior" list** — the most explicitly enumerated of the three, and the origin of several rows here: shift overflow, division by zero, signed division overflow, cast truncation, invalid enum tags, reaching `unreachable`.

Every row's Zoril column is **measured**, not asserted, by a probe in `bench/safety_matrix/probes/`. A probe may also cover a hole that has no row of its own: the unknown field on a slice (`100_unknown_field_on_slice.zrl`) asserts that `s.nope` on a slice is rejected rather than read at a garbage offset. Mutation M126 guards the check. `scripts/run_safety_matrix.sh` runs all of them and fails on any mismatch between the recorded expectation and observed behaviour, so a row cannot silently drift from the implementation. `scripts/run_safety_matrix.sh --zbuild` runs them again through an installed `zbuild` (run by the `safety-matrix-zbuild` gate): every probe gives the outcome its header records there too, and a refused probe is refused with the whole-program build's first error, so the rows hold for both build modes. The one probe whose `zbuild` outcome differs (262: separate compilation checks only what something calls, `KNOWN_ISSUES.md` section 4) says so in its header. Rows marked **GAP** are known-unsafe and have a probe asserting the unsafe behaviour — that is deliberate, so that closing the gap fails the probe and forces this table to be updated.

> [!NOTE]
> **The safe/unsafe boundary.** Several guarantees below (null references, null function pointers, use-after-drop, invalid enum discriminant) depend on one mechanism: raw-pointer dereference. That mechanism is gated. `unsafe { … }` is a keyword, and a fixed list of operations requires it - the normative list is [`doc/spec/unsafe_policy.md`](unsafe_policy.md) §1: raw-pointer dereference (explicit `*p`, or implicit in `p.field` and in a raw pointer converted to a reference), raw-pointer indexing, making a reference or a slice out of an integer, a pointer or a type parameter (`@ptr_cast<&T>`, `@ptr_from_int<&T>`, `@ptr_cast<[T]>`), `@slice` from a raw pointer, extern calls, `@syscall`, and `@alloca`; calling an `unsafe fn` needs a block as well, since its contract is the caller's. Creating a raw pointer (`n as *T`, `@ptr_from_int<*T>`, `@ptr_cast<*T>`, and `@int_cast<U>`) is not one of them: the type of the pointer gates every use of it, so the marker sits on the use. Each of those rows is therefore **scoped** rather than closed: the operation is still unchecked, but it is unreachable from unmarked code and greppable everywhere it appears. `doc/spec/unsafe_policy.md` is normative for what the marker permits; note in particular that it does **not** disable verification — region, ownership, borrow, immutability and bounds checks all stay active inside a block.
>
> **The `Side` column records which side of that boundary each row sits on.** `safe` means the property holds in unmarked code. **`unsafe`** means the row describes an operation reachable only inside a block. `safe / **unsafe** alias` means the property holds for named places but a raw-pointer alias can still observe the unsafe behaviour — from inside a block. `safe (unchecked)` is the awkward case: reachable from ordinary code _and_ not checked, which is what a **GAP** row is.
>
> Each scoped row is pinned by a **pair** of probes, not one: the unmarked program expects `compile_reject`, and a companion with `unsafe { }` expects the documented unchecked behaviour. Asserting only that an operation "is unsafe" would leave the escape hatch untested, and a marker that quietly stopped permitting the operation would pass.

Each property is one entry: the claim, which side of the `unsafe` boundary it is on, how strong its evidence is, and how many probes and tests prove it. The full table (mechanism, compiler level, boundary, the probe links and the routes) is [bench/safety_matrix/matrix.md](../../bench/safety_matrix/matrix.md); `scripts/check_safety_model.sh` fails when an entry here differs from its row there.

- **Intra-procedural Arena Analysis** (surface_syntax.md §11.2.1): Constant-size allocations do not exceed constant-size arena capacities within a function [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Inter-procedural Arena Propagation** (surface_syntax.md §11.2.2): Allocation requirements propagate across function calls to verify arena safety across boundaries [side: safe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Array Length Fits**: A declared array length and an array repeat count that do not fit in 32 bits are compile errors, so the type an array has is the length the program wrote [side: safe; evidence: example; probes: 4](../../bench/safety_matrix/matrix.md)
- **Type Size Fits**: A type whose size exceeds `isize::MAX` is a compile error, so a size never wraps and an in-bounds element address cannot leave the signed 64-bit range [side: safe; evidence: example; probes: 4](../../bench/safety_matrix/matrix.md)
- **Array Bounds Check (Read)** (surface_syntax.md §11.2.3): Out-of-bounds read on fixed-size array traps with exit code 134; an index written as a constant is rejected at compile time [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Array Bounds Check (Write)** (surface_syntax.md §11.2.3): Out-of-bounds write to fixed-size array traps with exit code 134; an index written as a constant is rejected at compile time [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Slice Bounds Check (Read)** (surface_syntax.md §11.2.3): Out-of-bounds read on slice traps with exit code 134 [side: safe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Slice Bounds Check (Write)** (surface_syntax.md §11.2.3): Out-of-bounds write to slice traps with exit code 134 [side: safe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Raw-Pointer Indexing** (surface_syntax.md §11.2.3): Indexing a raw pointer (`*T`, `*mut T`) is unchecked, and reachable only through `unsafe`, whether read (`p[i]`) or borrowed (`&p[i]`) [side: unsafe; evidence: example; probes: 3](../../bench/safety_matrix/matrix.md)
- **Indexing Through a Reference** (surface_syntax.md §11.2.3): A reference is indexed as what it refers to: `&[T; N]`, `&[T]` and `&Vec<T>` index the array, slice or vector (bounds-checked as above); a reference to anything else cannot be indexed, so `x[1]` with `x: &u32` is rejected rather than read past `x` [side: safe; evidence: example; probes: 3](../../bench/safety_matrix/matrix.md)
- **Region Escape: Direct Return** (surface_syntax.md §11.2.4): Returning address of local stack variable is rejected at compile time [side: safe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Region Escape: Return via Cast / Ops** (surface_syntax.md §11.2.4): Returning local stack pointer behind casts, moves, or pointer arithmetic is rejected [side: safe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Region Escape: Through Locals and Aggregates** (surface_syntax.md §11.2.4): A stack address held in a local, or in a struct, tuple or slice (including a slice over a local array), cannot be returned [side: safe; evidence: example; probes: 7](../../bench/safety_matrix/matrix.md)
- **Region Escape: Stored Outside the Frame** (surface_syntax.md §11.2.4): A stack address cannot be written to memory that outlives the function: through a pointer parameter, into a global, or into a heap allocation [side: safe; evidence: example; probes: 51](../../bench/safety_matrix/matrix.md)
- **Region Escape: Through a Call** (surface_syntax.md §11.2.4): A stack pointer passed to a function cannot come back out of the frame through it: not handed back (`return stash(&mut s)` dangles like `return &mut s`), and not stored by the callee into memory that outlives the frame (`put(h, &x)` with `fn put(h: &mut H, p: &i32) { h.r = p; }`, or into a global) [side: safe; evidence: example; probes: 7](../../bench/safety_matrix/matrix.md)
- **Region Escape: Reference Returned Through a Call** (surface_syntax.md §11.2.4): A reference into a local's own storage, obtained through a call (`let c = C {..}; return c.get();`), is not returned, whether as `&T`, `Option<&T>` or a struct or slice holding it; nor a reference into a local array obtained through a slice argument (`first(&a)`) [side: safe; evidence: example; probes: 30](../../bench/safety_matrix/matrix.md)
- **Region Escape: Reference into an Owned Box Dropped at Return** (surface_syntax.md §11.2.4): An address derived through a `Box` the function owns and drops (a local box, a by-value parameter, or reached through one by field steps) cannot be returned as a reference or stored where it outlives the function [side: safe; evidence: example; probes: 7](../../bench/safety_matrix/matrix.md)
- **Use After Move (Linear/Owned)** (surface_syntax.md §7.1): Accessing a moved non-`Copy` value (e.g. `Box<T>`) is rejected at compile time; assignment through a moved base (dereference of a moved `Box`, field write through a moved struct that owns storage, write through moved `&mut`) is rejected [side: safe; evidence: example; probes: 16](../../bench/safety_matrix/matrix.md)
- **Use After Move (Copy/POD)** (surface_syntax.md §7.1): Primitive and structurally Copy values remain usable after assignment [side: safe; evidence: example; probes: 15](../../bench/safety_matrix/matrix.md)
- **Double Drop** (surface_syntax.md §7.3, §8.4): Dropping an already-dropped or unowned value via `@drop` is rejected [side: safe; evidence: example; probes: 13](../../bench/safety_matrix/matrix.md)
- **Drop Exactly Once** (surface_syntax.md §7.3, §8.4): Values that need dropping are dropped exactly once on every path: scope exit, early return, loop break, reassignment, and after a move that happens on only some paths; a by-value parameter is dropped by the callee; a value owned by an aggregate (struct field, enum payload of the active variant, tuple or array element) is dropped when the aggregate is, after the aggregate's own `drop` if it has one. Moving a field that needs dropping out of a value (`let x = w.d;`) is rejected, since partial moves are not tracked per field; so is `[v; n]` with n > 1 for such a `v` [side: safe; evidence: example; probes: 8](../../bench/safety_matrix/matrix.md)
- **Defer Use After Move** (surface_syntax.md §7.1, §8.4): A `defer` statement cannot use a value that has already been moved, nor can a value used by a `defer` be moved subsequently on any path [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Use After Drop** (surface_syntax.md §7.3, §8.4): Accessing a variable after `@drop` is rejected at compile time [side: safe / unsafe alias; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Move Out of a Borrow** (surface_syntax.md §7.1, §7.2): A non-`Copy` value cannot be moved out through a reference (`return b.r` with `b: &B`): the owner would still drop it [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Borrow Aliasing (Exclusive Mutable)** (surface_syntax.md §7.2): Mutable borrow `&mut x` forbids simultaneous active borrows of same place; pattern bindings through a reference (`if let`, `match`, `while let` on `&e`) keep the matched enum borrowed; projected reborrows (`&r.f`) inherit the base reference's borrows; propagating borrows preserves all borrows a value holds; strict reborrowing tracks views through reference variables, so a view through `&mut` keeps the referent borrowed across mutations and `&mut` cannot be copied [side: safe; evidence: routes; probes: 38](../../bench/safety_matrix/matrix.md)
- **Borrow Aliasing: Returned References** (surface_syntax.md §7.2): A value returned by a call that can hold a reference (a reference, slice, `Option<&T>`, or struct holding one) keeps borrowed what its arguments borrow, while the value is live: `c.get()` then `c.set(..)`, `v.get(i)` / `v.as_slice()` kept across `v.push(..)`, or generic `Option.unwrap()` unwrapping a borrowed reference, are rejected [side: safe; evidence: routes; probes: 11](../../bench/safety_matrix/matrix.md)
- **Slice Forging (`@slice`)** (surface_syntax.md §3.5): `@slice(ptr, len)` requires `unsafe` (unless `len` is a literal 0), whether `ptr` is a raw pointer or a reference: the length is what nothing checks [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Read-Only Slices** (surface_syntax.md §3.5): A `[T]` is a read-only view: its elements can be written only through a `[mut T]`. `&a` gives a `[T]`, `&mut a` a `[mut T]`; a string literal and `Vec.as_slice()` are `[T]`. A `[mut T]` converts to a `[T]`, never the reverse [side: safe; evidence: example; probes: 6](../../bench/safety_matrix/matrix.md)
- **Linear Resource Leakage** (surface_syntax.md §7.1): Linear types (`fd`, `ioring`) cannot be implicitly dropped: not directly, not inside a struct, tuple, enum, array or box, not by an early return, and not on one path of a branch; nor duplicated or closed twice [side: safe; evidence: example; probes: 11](../../bench/safety_matrix/matrix.md)
- **File Descriptor Capabilities** (surface_syntax.md §3.12, §9.4): An `fd<r>` cannot be written through, an `fd<w>` cannot be read through, and a capability cannot be widened or forged [side: safe; evidence: example; probes: 5](../../bench/safety_matrix/matrix.md)
- **Integer Overflow (Wrapping)**: Arithmetic overflow wraps modulo $2^N$ by design [side: safe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Pointer Forgery (Raw Pointers)**: A pointer forged from an integer is unchecked _when it is used_: the dereference or the conversion to a reference is what is gated (each on the pointer's own type), while the creation itself is safe [side: unsafe; evidence: example; probes: 9](../../bench/safety_matrix/matrix.md)
- **Null Dereference** (surface_syntax.md §11.2.5): A reference obtained without `unsafe` is non-null. `0 as &T` and generic `(0 as u64) as T` are rejected outright; forging one from a null raw pointer (`let r: &T = &*p;`) is a compile error unless it is inside `unsafe { }`, where it remains unchecked and faults [side: unsafe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Implicit Raw-Pointer Dereference**: `p.field`, `p.0` and `p.method()` on a raw pointer dereference it as `(*p).field` does, and are reachable only through `unsafe`; a slice's `.ptr` is a raw pointer like any other [side: unsafe; evidence: example; probes: 6](../../bench/safety_matrix/matrix.md)
- **System Call**: `@syscall` reaches the kernel with integers it treats as addresses (`read`, `mmap`, `munmap` write or unmap any memory), and is reachable only through `unsafe` [side: unsafe; evidence: example; probes: 3](../../bench/safety_matrix/matrix.md)
- **Extern Function Call**: Calling an `extern` function is unchecked, and reachable only through `unsafe` [side: unsafe; evidence: example; probes: 3](../../bench/safety_matrix/matrix.md)
- **Extern Signature Types**: An `extern` signature carries only what C can take: `bool`, the sized integers, `usize`/`isize`, the floats and raw pointers. A struct by value, a slice, a reference, a `Box`, a tuple, an array, an enum, a `char` or a `fn` value is a compile error that names the type and what to pass instead [side: safe; evidence: example; probes: 6](../../bench/safety_matrix/matrix.md)
- **C Function Pointers**: A C function pointer (`extern "C" fn(..)`) is a code address from an `extern "C" fn` or from C, never a number or a Zoril function value, and calling one is unchecked, so it needs `unsafe` [side: safe; evidence: example; probes: 5](../../bench/safety_matrix/matrix.md)
- **Implicit Conversions Are Exact Behind a Mutable Handle**: What a `&mut`, `*mut`, `BoxMut` or `[mut T]` points at must be the same type, not a convertible one; function parameters are compared in the opposite direction from results; `()` stands for nothing but a plain number; and a value put into an array element or an enum payload converts as an argument would, or is a mismatch [side: safe; evidence: example; probes: 10](../../bench/safety_matrix/matrix.md)
- **Uninitialized Stack Slot**: `@alloca<T>(1)` returns a `&mut T` to a slot nothing has written; reading it before a write reads a stale value (a wild pointer when `T` is a reference), so it is reachable only through `unsafe` [side: unsafe; evidence: example; probes: 3](../../bench/safety_matrix/matrix.md)
- **Raw Pointer Converted to a Reference**: A raw pointer used where a reference is expected becomes that reference, the same forge as `&*p`, and is reachable only through `unsafe`: as an argument, a `let` with a declared type, an assignment, a `return` or tail result, and a struct field [side: unsafe; evidence: example; probes: 9](../../bench/safety_matrix/matrix.md)
- **Raw Pointer Returned by a Function Call**: A raw pointer returned by a function call (`*mut T` or `*T`) retains its raw status, and dereferencing or writing through it is reachable only through `unsafe`: `let p = f(); *p` and `*f() = v` require `unsafe` [side: unsafe; evidence: example; probes: 3](../../bench/safety_matrix/matrix.md)
- **Raw Pointer Converted to a Reference Through a Type Parameter**: A raw pointer passed as a type parameter and coming back as a reference (`let r: &T = id(p);`, `Vec::<&T>.push(p)`, `Option.Some(p)` for an `Option<&T>`) needs `unsafe` [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Raw Pointer Laundered Through an Aggregate or Binding**: A raw pointer passed through an aggregate (tuple, struct, array, enum) or a pattern binding retains its raw status, so dereferencing it or converting it to a reference needs `unsafe` [side: safe; evidence: example; probes: 9](../../bench/safety_matrix/matrix.md)
- **Raw Pointer Dereferenced After a Container or a Generic or a Closure**: A dereference, a field access or an index through a raw pointer should require `unsafe` even when the pointer arrived through a container, a generic instantiation or a closure capture [side: safe; evidence: example; probes: 5](../../bench/safety_matrix/matrix.md)
- **Safe Function Dereferencing a Raw Pointer Argument**: A function that dereferences a raw pointer it is given requires `unsafe` at the call site, as an `unsafe fn` does in Rust [side: safe; evidence: example; probes: 7](../../bench/safety_matrix/matrix.md)
- **Stdlib `unsafe` Interiors**: Every `unsafe` block in `stdlib/` trusts an invariant the type system does not check - a length that matches its allocation, an index that fits, a pointer that is live, arithmetic that cannot wrap - and checked code must not be able to break one [side: safe; evidence: example; probes: 9](../../bench/safety_matrix/matrix.md)
- **Arena Use After Reset or Free** (surface_syntax.md §11.2.1): A value allocated in an arena cannot be used once `reset`, `reset_to` or `arena_free` releases its memory [side: safe; evidence: routes; probes: 31](../../bench/safety_matrix/matrix.md)
- **Encapsulation (Private Methods)** (surface_syntax.md §11.1.1, §11.1.2): A method, associated function or associated constant that is not `pub` is nameable only from the module that declares its `impl`, so another module cannot reach a private invariant keeper (`c.bump()`, `Widget.SECRET`) [side: safe; evidence: example; probes: 4](../../bench/safety_matrix/matrix.md)
- **Region Escape: Borrowed Value Dropped at Block End** (surface_syntax.md §7.2): A value leaving scope while something that outlives that scope still borrows it is rejected ("cannot let 'x' go out of scope while it is still borrowed"), not only when a reference escapes the function [side: safe; evidence: routes; probes: 22](../../bench/safety_matrix/matrix.md)
- **Data Races**: Not applicable [side: n/a; evidence: n/a; probes: n/a](../../bench/safety_matrix/matrix.md)
- **Uninitialized Local Read**: A local cannot be read before it is written [side: safe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Division by Zero**: Integer division by zero faults deterministically rather than producing a value [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Signed Division Overflow**: `INT_MIN / -1` faults rather than wrapping [side: safe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Shift Overflow** (surface_syntax.md §11.2.6): A shift count must be in `[0, width)` of the shifted type [side: safe; evidence: example; probes: 5](../../bench/safety_matrix/matrix.md)
- **Narrowing Cast Truncation** (surface_syntax.md §11.2.6): A conversion that drops bits cannot happen implicitly; `as` is required and still truncates silently [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Invalid Enum Discriminant**: Casting an integer to an enum type is rejected at compile time; enum values must be constructed via variant constructors [side: safe / unsafe alias; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Variant Reassignment Under a Payload Binding** (surface_syntax.md §5.3): Reassigning an enum to another variant while a payload binding is live cannot reinterpret the payload [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Mutable Statics Hold No References** (surface_syntax.md §11.2.4): A `static mut` cannot have a reference or slice type, or a struct type with a reference field: anything stored in it would outlive what it borrows [side: safe; evidence: example; probes: 8](../../bench/safety_matrix/matrix.md)
- **Non-Scalar `static mut` Access Is Unsafe**: A `static mut` whose type is not a scalar (an integer, a float, `bool`, `char` or a raw pointer) may be read, written or borrowed only inside `unsafe`: a write can retype the place, and the borrow checker does not track borrows of statics across it [side: safe; evidence: example; probes: 9](../../bench/safety_matrix/matrix.md)
- **Immutable Static Assignment**: An immutable `static` variable cannot be assigned to or mutably borrowed [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Trait Bound Enforcement** (surface_syntax.md §3.11): A generic instantiation must satisfy every trait bound, including bounds reached through nested generic impls [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Missing Return**: Control falling off the end of a non-unit function without returning a value is rejected at compile time [side: safe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Unaligned Access**: Unaligned loads/stores are unchecked, and reachable only through `unsafe` [side: unsafe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Stack Exhaustion** (surface_syntax.md §11.2.7): Unbounded recursion faults without a diagnosable guard [side: safe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Sub-word Arithmetic Width** (surface_syntax.md §11.2.6): A `u8`/`u16`/`i8`/`i16` result stays inside its declared type, as a temporary and when stored [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Null Function Pointer Call** (surface_syntax.md §11.2.5): A function pointer obtained without `unsafe` is non-null. `0 as fn(...)` is rejected outright; loading one out of a zeroed aggregate through a raw pointer (`(*v).call`) is a compile error unless it is inside `unsafe { }`, where it remains unchecked and faults on call [side: unsafe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Generic Integer-to-Reference Cast**: References cannot be created null by direct integer cast (`0 as &T` is rejected), and generic casts (`(0 as u64) as T`, `0 as T::Out`, `p as T` from a raw pointer) are rejected at compile time [side: safe; evidence: example; probes: 4](../../bench/safety_matrix/matrix.md)
- **Value Forged by Cast**: `as` cannot make a slice, array, tuple, struct, enum or box out of another type, nor add `mut` to a slice, nor make a `bool` or a `char` out of a number in checked code [side: safe; evidence: example; probes: 23](../../bench/safety_matrix/matrix.md)
- **Associated Type Confusion**: An associated type (`T::Out`) cannot launder a reference past the escape check, nor make a value of one type be read as another [side: safe; evidence: example; probes: 5](../../bench/safety_matrix/matrix.md)
- **Method of Another Instance**: A method of an impl for one instance of a generic type (`impl W<&i32>`) cannot be called on another (`W<i64>`), so its `self` never reads one instance's value as another's [side: safe; evidence: example; probes: 4](../../bench/safety_matrix/matrix.md)
- **Dereference of a Non-Pointer**: `*e` follows an address only: `e` must be a reference, raw pointer or box [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Type Confusion (raw pointer cast)**: Reinterpreting one struct as another via raw pointer cast is unchecked, and reachable only through `unsafe` [side: unsafe; evidence: example; probes: 1](../../bench/safety_matrix/matrix.md)
- **Immutability Enforcement**: A non-`mut` binding cannot be reassigned or mutably borrowed; bindings are immutable by default. `&T` (and non-mut `*T`, which erases to the same IL tag) is read-only: assigning through it, calling a `&mut self` method through it, or passing it where a callee expects `&mut T`/`*mut T` is rejected, whether the `&T` is a locally-initialized `let`, a parameter, a struct field, a returned reference, or an `IndexAddr` place [side: safe; evidence: example; probes: 11](../../bench/safety_matrix/matrix.md)
- **Capturing Closure Escape** (surface_syntax.md §5.2): A capturing closure is never called without its environment, and its environment (in the frame that made it) is never reached after that frame returns [side: safe; evidence: routes; probes: 13](../../bench/safety_matrix/matrix.md)
- **Closure Capture by Reference** (surface_syntax.md §5.2): A closure capturing a reference to a place keeps that place borrowed for the closure's lifetime, rejecting mutation or variant reassignment while the closure is live [side: safe; evidence: routes; probes: 4](../../bench/safety_matrix/matrix.md)
- **Or-Pattern Binding Type**: A name bound in several alternatives of an or-pattern has one type: every alternative must bind it with exactly that type [side: safe; evidence: example; probes: 2](../../bench/safety_matrix/matrix.md)
- **Slice Header Integrity**: A slice-typed place (`[T]`) only ever holds a real `{ptr, len}` header: an array value `[T; N]` is not implicitly accepted where a slice is expected, in `let`, call arguments, struct literals or assignment [side: safe; evidence: example; probes: 3](../../bench/safety_matrix/matrix.md)

### Routes: what each row's evidence walks

The `routes` evidence level means a row's probes were checked against the compiler constructs its mechanism depends on, not only against the shapes someone thought of. The route lists, the vocabulary and how `scripts/check_route_coverage.sh` checks them are in [bench/safety_matrix/matrix.md](../../bench/safety_matrix/matrix.md).

### Evidence levels

The `Evidence` column states how strong a row's evidence is, on a four-level scale:

- `example` - the probes cited in "Proven by" fire the mechanism on the shapes they name.
- `routes` - `scripts/check_route_coverage.sh` passes for the row: every route in `Routes` is named by the `reject-via` set of a cited `compile_reject` probe, and is one a borrow can travel through (the vocabulary in `src/route_set.zrl`).
- `fuzzed` - `routes`, plus the fuzzer generates the row's routes and its semantic oracle and the `--checked` build agree on them.
- `argued` - `fuzzed`, plus an argument that the invariant holds for every route.

A level is a floor, not a ranking of importance: a row at `example` is still proven, it is just proven on examples rather than on routes. `scripts/check_safety_model.sh` rejects an unknown level, a `routes`-or-higher row with no `Routes` list, an `example` row that lists routes, and runs the route-coverage gate when any row is `routes` or higher. `doc/SAFETY.md` §5.1 states how many rows sit at each level, so a reader can see how much of the matrix rests on route evidence.

### Match exhaustiveness

`surface_syntax.md` §5.3 states that matches are enforced at compile time to be exhaustive. The ZIR lowering verifies variant coverage for enums, boolean completeness, and wildcard fallbacks for scalar/slice/range matches before code generation, reporting compile errors for unhandled cases. Guarded arms (`if` guards) do not count toward unconditional exhaustiveness. As a defense-in-depth safety net, the lowering still emits an `@unreachable` block calling `zoril_abort()`, so any unreachable fallthrough terminates deterministically (exit 1) rather than producing an undefined value.

Regarding runtime abort conventions: `zoril_abort()` exits **1** (unhandled logic / unreachable abort), while memory-safety bounds-check traps exit **134** (`128 + SIGABRT`). This distinguishes spatial memory traps from control-flow assertions.

### Gap summary

No row above is marked **GAP** today. That does not mean no hole is open: the 17 holes still open in checked code are routes inside rows the matrix counts as closed, and each is a `known_gap` probe listed under [Known gaps](#known-gaps).

Every program that showed a hole in one of the rows is kept as a `compile_reject` probe (or, for the two drop-count probes, an `accept` that asserts one drop), so the hole cannot reopen unnoticed.

A **GAP** row is a hole in checked code: the compiler accepts something the safety model says it should not, or produces a platform-dependent result. Each is pinned by a `known_gap` probe, listed under [Known gaps](#known-gaps) below, which `make test` reports as a skip until the gap is closed.

**The practice this document follows: a GAP row closes only when all three of these hold.**

1. **Its motivating probes no longer build.** Every exploit that opened the row has been re-run unchanged and no longer builds (or, for a drop-count probe, no longer shows the unsafe behaviour). Those programs become `compile_reject` tests with located errors, and they stay as the evidence.
2. **It reaches the `routes` evidence level.** The row's `Routes` list names every construct its mechanism depends on, and `scripts/check_route_coverage.sh` shows that each is walked by a cited probe. A fix that closes the one exploit someone wrote down while another construct in the same class stays unprobed has not closed the row.
3. **The mutations that disable its mechanism are killed by its own probes.** The row lists the mutation IDs that target its mechanism (for example M21, M22, M37) in its text; `scripts/mutation-check.sh --row '<row name>'` runs exactly those mutations against exactly the probes and tests the row cites, and each one must be caught. A mutation that survives means the row's evidence does not reach the mechanism the row claims.

**Raw pointers in checked code.** Checked code can create a raw pointer (`0 as *mut T`, `&x as *T`) but cannot use one: every dereference, field access and index through it requires `unsafe`. The pointer keeps its raw type through tuples, structs, arrays and enums, pattern bindings, generic calls and closure captures, so it cannot be passed through one of them and come out as a reference (probes [`158_launder_null_ref_tuple.zrl`](../../bench/safety_matrix/probes/158_launder_null_ref_tuple.zrl), [`152_launder_raw_ptr_match_binding.zrl`](../../bench/safety_matrix/probes/152_launder_raw_ptr_match_binding.zrl), [`125_raw_pointer_to_reference_through_generic.zrl`](../../bench/safety_matrix/probes/125_raw_pointer_to_reference_through_generic.zrl), [`154_launder_raw_ptr_closure.zrl`](../../bench/safety_matrix/probes/154_launder_raw_ptr_closure.zrl)). Creating one writes no memory, which is why it stays safe ([`doc/spec/unsafe_policy.md`](unsafe_policy.md) §1, probe [`187_int_to_raw_ptr_cast_safe.zrl`](../../bench/safety_matrix/probes/187_int_to_raw_ptr_cast_safe.zrl)).

A GAP row is what a _decided_ check misses. What a check does when it cannot decide at all is the other half of the picture, and every place a checker could answer "unknown" (the ZIR checker, the ZIL verifier, the summary passes and the lowering's raw-ness checks) was audited, and each is either unreachable or answers conservatively (rejects) - see [What Zoril Checks](../SAFETY.md) §4.4.

Several design points are worth stating directly:

- **Shift overflow:** constant shift counts are checked at compile time and variable ones trap. Masking to the hardware width is available explicitly as `@shl_wrap` / `@shr_wrap`.
- **Escape through a callee:** a function signature states what its result may point into (`#[borrows(..)]`, with Rust-like defaults), and borrows end at their last use. Whether a result points into an argument's own storage or into a buffer the argument references is decided by the callee's body (`ret_storage`, carried in `.zri`), since a signature cannot express it. Rust tells the two apart through ownership (dropping a `Vec` frees its buffer); with arenas, returning a slice of a local `Vec` is safe in Zoril, so the Rust rule would reject correct code.
- **Implicit conversions:** the conversion list under the route grid gives every pair of types the two matchers accept as equal or convertible, with the justification for each and the tests that pin it; the pairs that would not be sound - a shared handle where a mutable one is expected, in the reference, raw and box classes - are refused, and the conversions the language does allow (`&T as *T`, `0 as *T`, and `*T` to `&T` only as `&*p` inside `unsafe`) are listed there too.
- **Narrowing casts:** an implicit conversion that drops bits is rejected, and `as` is the required marker (probes [`37_implicit_narrowing.zrl`](../../bench/safety_matrix/probes/37_implicit_narrowing.zrl) and [`20_narrowing_cast.zrl`](../../bench/safety_matrix/probes/20_narrowing_cast.zrl) pin this from both sides, row `Narrowing Cast Truncation (§11.2.6)`).
- **Stack exhaustion:** accepted as-is (§11.2.7), a deterministic fault on the same footing as division by zero.
- **Raw-pointer operations** (null dereference, null function pointer call, unaligned access, forging a pointer from an integer _and using it_, type confusion, raw-pointer indexing) are reachable only inside an `unsafe` block, are unchecked there, and are pinned by probe pairs. The _creation_ of a raw pointer is not one of them (it is safe; see §5.2), so what the pair pins is that the use is refused.

### Known gaps

Every probe in `bench/safety_matrix/probes/` whose expectation is `known_gap` is listed here, and nothing else is; `scripts/check_safety_model.sh` enforces both directions. The safety matrix reports each as a skip while the compiler still accepts it and fails once it does not, so closing a gap means flipping its probe's expectation, removing its entry, and unmarking its row.

- **[`gap_07_path_same_param.zrl`](../../bench/safety_matrix/probes/gap_07_path_same_param.zrl)**: Storage walk and escape checks filter out i == j when same parameter carries dest and source
- **[`gap_53_same_param_struct_copy.zrl`](../../bench/safety_matrix/probes/gap_53_same_param_struct_copy.zrl)**: The same filter when the parameter is a struct of references (`R { x: &mut wa, y: &wb }`) through which the callee copies a frame view from one of the caller's locals into another, which the caller then stores out. Route class: one parameter carrying both the destination and the value
- **[`gap_11_dest_closure_capture_mut.zrl`](../../bench/safety_matrix/probes/gap_11_dest_closure_capture_mut.zrl)**: Closure storing through captured mutable reference not recognized as escaping frame
- **[`gap_13_ref_local_enum_payload.zrl`](../../bench/safety_matrix/probes/gap_13_ref_local_enum_payload.zrl)**: Storage facts drops provenance for stack reference carried in enum payload
- **[`gap_16_ref_local_fn_val.zrl`](../../bench/safety_matrix/probes/gap_16_ref_local_fn_val.zrl)**: Storage facts drops provenance for stack reference passed through fn value
- **[`gap_18_elem_ref_enum_payload.zrl`](../../bench/safety_matrix/probes/gap_18_elem_ref_enum_payload.zrl)**: Storage facts drops provenance for array/slice element reference in enum payload
- **[`gap_21_elem_ref_fn_val.zrl`](../../bench/safety_matrix/probes/gap_21_elem_ref_fn_val.zrl)**: Storage facts drops provenance for element reference passed through fn value
- **[`gap_23_closure_local_enum_payload.zrl`](../../bench/safety_matrix/probes/gap_23_closure_local_enum_payload.zrl)**: Storage facts drops provenance for stack-capturing closure in enum payload
- **[`gap_26_closure_local_fn_val.zrl`](../../bench/safety_matrix/probes/gap_26_closure_local_fn_val.zrl)**: Storage facts drops provenance for stack-capturing closure passed through fn value
- **[`gap_27_closure_local_param_65.zrl`](../../bench/safety_matrix/probes/gap_27_closure_local_param_65.zrl)**: Parameter bitmask overflow at index >= 64 drops closure provenance
- **[`gap_28_call_summary_mutual_recursion.zrl`](../../bench/safety_matrix/probes/gap_28_call_summary_mutual_recursion.zrl)**: compute_ret_storage_zir lacks interprocedural fixpoint over mutually recursive calls
- **[`gap_54_cycle_store_through_local.zrl`](../../bench/safety_matrix/probes/gap_54_cycle_store_through_local.zrl)**: The same missing fixpoint over a three-function cycle in which one function writes a frame view into a local of its caller, which the caller then stores out. Route class: a store summary through a recursive cycle
- **[`gap_29_dest_closure_call_returns_mut_ref.zrl`](../../bench/safety_matrix/probes/gap_29_dest_closure_call_returns_mut_ref.zrl)**: CallPtr return target check misses closure call returning captured mutable reference
- **[`gap_32_byval_collection_param_store.zrl`](../../bench/safety_matrix/probes/gap_32_byval_collection_param_store.zrl)**: By-value collection parameter treated as external instead of frame-owned storage
- **[`gap_62_byval_arena_param_vec_pushed.zrl`](../../bench/safety_matrix/probes/gap_62_byval_arena_param_vec_pushed.zrl)**: A `Vec` made in an `Arena` passed by value is pushed into the caller's `Vec`; the arena is freed when the callee returns, and the old rules read its storage as external, as `gap_32` does for a by-value `Vec`. Route class: the storage a by-value owning parameter owns, stored into caller memory
- **[`gap_33_param_65_arena_slice_store.zrl`](../../bench/safety_matrix/probes/gap_33_param_65_arena_slice_store.zrl)**: Parameter bitmask overflow at index >= 64 drops arena slice storage provenance
- **[`gap_36_carrier_ref_enum_payload_match.zrl`](../../bench/safety_matrix/probes/gap_36_carrier_ref_enum_payload_match.zrl)**: The summary pass does not follow a pointer into the frame through an enum payload bound in a match arm
- **[`gap_37_local_mutref_field_reset.zrl`](../../bench/safety_matrix/probes/gap_37_local_mutref_field_reset.zrl)**: A slice written into a local's field through a local `&mut` to it is not held by the struct, so an arena reset passes while the field is read. Route class: a store into a local's field or a Box's contents through a pointer to it, which `check_assign` skips (`place_writes_through_pointer`)
- **[`gap_38_param_field_reset.zrl`](../../bench/safety_matrix/probes/gap_38_param_field_reset.zrl)**: The same store made by a callee through its `&mut` parameter. Route class: a store into a local's field or a Box's contents through a pointer to it, which `check_assign` skips (`place_writes_through_pointer`)
- **[`gap_39_method_self_field_reset.zrl`](../../bench/safety_matrix/probes/gap_39_method_self_field_reset.zrl)**: The same store made by a `&mut self` method through `self`. Route class: a store into a local's field or a Box's contents through a pointer to it, which `check_assign` skips (`place_writes_through_pointer`)
- **[`gap_40_local_mutref_field_escape.zrl`](../../bench/safety_matrix/probes/gap_40_local_mutref_field_escape.zrl)**: A slice of a Vec in this frame's arena, written into a local struct's field through a local `&mut` to it, is stored out through `*out = w.s`; written as `w.s = ...` the same store is refused. Route class: a store into a local's field or a Box's contents through a pointer to it
- **[`gap_41_callee_field_escape.zrl`](../../bench/safety_matrix/probes/gap_41_callee_field_escape.zrl)**: The same escape with the field written by a callee through its `&mut` parameter. Route class: a store into a local's field or a Box's contents through a pointer to it
- **[`gap_42_box_field_escape.zrl`](../../bench/safety_matrix/probes/gap_42_box_field_escape.zrl)**: The same escape with the field in a Box's contents (`(*b).s = ...`); with a plain local struct the same program is refused. Route class: a store into a local's field or a Box's contents through a pointer to it
- **[`gap_43_box_field_reset.zrl`](../../bench/safety_matrix/probes/gap_43_box_field_reset.zrl)**: A slice written into a field of a Box's contents is not held by the box, so an arena reset passes while the field is read; with a plain local struct the reset is refused. Route class: a store into a local's field or a Box's contents through a pointer to it
- **[`gap_45_closure_mutref_field_escape.zrl`](../../bench/safety_matrix/probes/gap_45_closure_mutref_field_escape.zrl)**: The same escape with the field written by a closure that captured a local `&mut` to the struct; the closure call's effect on the captured struct is not seen. Route class: a store into a local's field or a Box's contents through a pointer to it
- **[`gap_47_closure_ref_struct_mutref_escape.zrl`](../../bench/safety_matrix/probes/gap_47_closure_ref_struct_mutref_escape.zrl)**: A closure that captured `r = &w`, where the local struct `w` holds the caller's `&mut`, stores a frame view through `*r.out`; the external destination is two hops from the closure environment. Route class: a store whose external destination is reached through references to locals (closure environment, call argument)
- **[`gap_48_closure_ref_ref_struct_mutref_escape.zrl`](../../bench/safety_matrix/probes/gap_48_closure_ref_ref_struct_mutref_escape.zrl)**: The same store three hops from the environment (`rr = &r`, `*rr.out = s`), so a rule following a fixed number of hops misses it. Route class: a store whose external destination is reached through references to locals (closure environment, call argument)
- **[`gap_55_closure_param_forwards_view.zrl`](../../bench/safety_matrix/probes/gap_55_closure_param_forwards_view.zrl)**: A closure called with a destination as its own argument (`cl(out)`, `|o: &mut [i32]| { put(o, view); }`) forwards a captured frame view to a named callee that stores it there; the closure body is clean (the view is `Env`, `o` a parameter) and the call through the closure value is not checked against what its environment holds. Route class: a call through a closure value
- **[`gap_49_call_ret_mutref_callee_write.zrl`](../../bench/safety_matrix/probes/gap_49_call_ret_mutref_callee_write.zrl)**: A `&mut` returned by a call and passed to a writing callee (`write(d, s)` with `d = unwrap_slot(h)`) leaves the outer caller's store summary empty. Route class: a call result (`Call` rvalue) used as a store destination
- **[`gap_50_call_ret_struct_callee_write_slot.zrl`](../../bench/safety_matrix/probes/gap_50_call_ret_struct_callee_write_slot.zrl)**: A struct holding a `&mut` returned by a call and passed to a writing callee (`write_slot(d, s)` with `d = pass_slot(h)`) leaves the outer caller's store summary empty. Route class: a call result (`Call` rvalue) used as a store destination
- **[`gap_51_call_ret_struct_field_callee_write.zrl`](../../bench/safety_matrix/probes/gap_51_call_ret_struct_field_callee_write.zrl)**: A `&mut` field projected from a call-returned struct and passed to a writing callee (`write(d.out, s)` with `d = pass_slot(h)`) leaves the outer caller's store summary empty. Route class: a call result (`Call` rvalue) used as a store destination
- **[`gap_52_closure_passed_to_caller_of_fn_value.zrl`](../../bench/safety_matrix/probes/gap_52_closure_passed_to_caller_of_fn_value.zrl)**: A closure storing a frame view through a captured `&mut` is handed to a function that calls it (`call_it(|| { *out = s; })` with `fn call_it(g: fn()) { g(); }`); the callee's call through `g` stores the environment into itself, which its store summary does not record, so the caller never checks what the closure captured. Accepted with and without `--provenance`; also through two callers, a method taking a `fn`, and a closure bound to a `let` first. Route class: a closure passed as an argument to a callee that calls it
- **[`gap_64_closure_global_store_via_fn_param.zrl`](../../bench/safety_matrix/probes/gap_64_closure_global_store_via_fn_param.zrl)**: A closure that stores a captured frame address into a global (`run(|| { G = r as *i32; })` with `fn run(f: fn()) { f(); }` and `r = &x`) is handed to a function that calls it. The closure body stores `Env` into a global, which is not frame-bound there, and neither the call through `f` nor the call to `run` sees a store into a global; the direct call `cl()` is refused by the old rules, and a `fn` item that stores into a global cannot become a value (`check_fn_value`), but nothing checks a closure. Accepted with and without `--provenance`. Route class: a closure passed as an argument to a callee that calls it, with a global destination (the class of `gap_52`).
- **[`gap_56_extern_copy_extend_from_slice.zrl`](../../bench/safety_matrix/probes/gap_56_extern_copy_extend_from_slice.zrl)**: `Vec.extend_from_slice` copies a slice of frame views into the caller's `Vec` with `memcpy` and declares no `#[stores]`, so no summary records that the slice's elements are stored into `self`. Route class: a safe body that copies reference-carrying elements through an `extern` with no declared effect
- **[`gap_57_match_ref_local_enum_binding_returned.zrl`](../../bench/safety_matrix/probes/gap_57_match_ref_local_enum_binding_returned.zrl)**: A binding of a `match` on a reference to a local enum (`let r = &e; match r { E.A(x) => x, .. }`, also `if let` on `&e` and a `&mut e` scrutinee) is a pointer into the enum, and returning it is accepted. Route class: a payload bound by reference through a reference scrutinee
- **[`gap_58_match_ref_accessor_local_enum_returned.zrl`](../../bench/safety_matrix/probes/gap_58_match_ref_accessor_local_enum_returned.zrl)**: The same binding made inside an accessor (`fn pick(r: &E) -> &P { return match r { .. }; }`), whose result the summary does not tie to `r`, so `return pick(&e)` is accepted. Route class: a payload bound by reference through a reference scrutinee
- **[`gap_59_pushed_vec_holding_frame_views.zrl`](../../bench/safety_matrix/probes/gap_59_pushed_vec_holding_frame_views.zrl)**: A local `Vec<[i32]>` holding a view of a stack array is pushed into the caller's `Vec<Vec<[i32]>>`; the old rules see an owner moved out, not the frame views it holds. Route class: an owner whose elements are frame views, moved into memory that outlives the frame
- **[`gap_60_vec_holding_frame_views_moved_to_pushing_callee.zrl`](../../bench/safety_matrix/probes/gap_60_vec_holding_frame_views_moved_to_pushing_callee.zrl)**: The same `Vec` passed by value to a callee that pushes it into the caller's `Vec`. Route class: an owner whose elements are frame views, moved into memory that outlives the frame
- **[`gap_61_struct_wrapping_vec_of_frame_views_pushed.zrl`](../../bench/safety_matrix/probes/gap_61_struct_wrapping_vec_of_frame_views_pushed.zrl)**: The same `Vec` wrapped in a struct literal and pushed. Route class: an owner whose elements are frame views, moved into memory that outlives the frame
- **[`gap_63_vec_built_around_param_view_in_callee.zrl`](../../bench/safety_matrix/probes/gap_63_vec_built_around_param_view_in_callee.zrl)**: A callee builds a `Vec<[i32]>` around a view of a caller-local `Vec`'s buffer reached through a parameter (`tmp.push(v.as_slice()); *out = tmp;`) and stores it into the caller's slot. Route class: an owner whose elements are frame views, moved into memory that outlives the frame
- **[`gap_44_borrows_attr_reset.zrl`](../../bench/safety_matrix/probes/gap_44_borrows_attr_reset.zrl)**: A `#[borrows()]` method returning a view its receiver holds gives a result that holds no borrow, so an arena reset passes while the result is read; without the attribute the reset is refused. Route class: the liveness route of the `#[borrows()]` laundering that `gap_30` closes for stores
- **[`gap_66_generic_instance_as_fn_value_uninit.zrl`](../../bench/safety_matrix/probes/gap_66_generic_instance_as_fn_value_uninit.zrl)**: A generic function's instance named with type arguments and used as a value (`let f: fn(i32) -> i32 = id::<i32>;`) is accepted, but lowering drops the initializer: the `fn` value's slot is never written and the call faults. A struct field (`H { f: id::<i32> }`) faults the same way, an assignment (`f = id::<i32>;`) is dropped and leaves the old value, an argument gives invalid ZIL, a `return` reports a missing return value. Route class: a conversion site that turns a function into a value (a `let` with a `fn` type, an argument, a struct field, an assignment, a return).
- **[`gap_67_extern_fn_as_fn_value.zrl`](../../bench/safety_matrix/probes/gap_67_extern_fn_as_fn_value.zrl)**: A bare `extern` function converts to a plain `fn` type with no `unsafe` block (`let f: fn(*mut u8, i32, usize) -> *mut u8 = memset;`), and a call through a `fn` value is never marked, so safe code calls C through it: here a safe callee hands `memset` a forged pointer and the write faults. A direct call is refused outside `unsafe`. Route class: a conversion site that turns a function into a value, the `extern` twin of the `unsafe fn` rule (Z-0095).
- **[`gap_68_drop_glue_by_type_name.zrl`](../../bench/safety_matrix/probes/gap_68_drop_glue_by_type_name.zrl)**: A type named like another module's type that has a `Drop` impl is dropped with that impl: `struct Arena { x: i64 }` beside `import "mem.zrl"` is dropped by `stdlib::mem::Arena::drop`, which faults. Two user modules each with an `S`, one with a `Drop`, do the same. The drop glue is found by the bare name `Type::drop`, with no module. Route class: a type's function found by its unqualified name, in row **Drop Exactly Once** (Z-0162).

---

## 3. Mechanisms in Detail

### 3.1 Arena Capacity Analysis (§11.2.1, §11.2.2)

Zoril provides compile-time verification for fixed-capacity memory arenas when capacities and allocation sizes are compile-time constants:

1. **Intra-procedural Tracking (`src/verify.zrl` `fn track_arena_call`):** When `arena_init(cap)` is invoked with a constant literal, the ZIL verifier records `arena_info[ssa].state = ARENA_INITIALIZED` and sets `remaining = cap`. Subsequent calls to `zoril_allocator_alloc(arena, size)` with a constant `size` deduct from `remaining`. If `size > remaining`, the verifier immediately emits:
   ```
   error: arena capacity exceeded at compile time
   ```
2. **Inter-procedural Propagation (`src/verify.zrl` `fn track_arena_call`):** Functions that perform constant allocations record their total allocation footprint in `(*p_func).arena_alloc_bytes`. When caller invokes `callee(arena)` where the arena is passed as the final argument, the caller checks `alloc_bytes > remaining` and reports:
   ```
   error: arena capacity exceeded at compile time (interprocedural)
   ```
3. **Runtime Fallback:** When allocations use dynamic sizes, the compile-time check does not trigger. The runtime allocator in `stdlib/mem.zrl` checks `aligned_offset + size > arena.capacity` and terminates the process with exit code 134.

### 3.2 Bounds Checking (§11.2.3)

Zoril guarantees that index expressions on slices and fixed-size arrays cannot read or write out of bounds:

1. **Read Path (`resolve_place_addr` in `src/lower_zir_to_zil.zrl`):**
   - For arrays: emits comparison between index SSA and constant array length.
   - For slices: loads `len` field from slice fat pointer and emits comparison.
   - If index $\ge$ bound, branches to a trap basic block that executes `sys_exit_group(134)`.
2. **Write Path (`src/lower_zir_to_zil.zrl` `fn resolve_place_addr` & `fn index_addr`):**
   - Assignment LHS retains its `Index` projection so it shares `resolve_place_addr`.
   - The fallback `IndexAddr` rvalue lowering also emits length checks.
   - Both paths branch to trap block with exit 134.
3. **Raw Pointers:**
   - Raw pointers (`*T`, `*mut T`) do not carry length metadata. Indexing a raw pointer emits direct pointer arithmetic without bounds checking.

### 3.3 Region Escape Verification (§11.2.4)

Zoril rejects, at compile time, a function's stack addresses outliving it:

1. **Slot Tracking (`src/verify.zrl`):** Every `'local` slot allocated without an allocator is a stack slot (`is_stack_slot`); `'heap` allocations are not. `track_stack_base` records which slot each derived address (field, element, offset, move, cast) belongs to.
2. **Provenance Propagation:** Operations that derive new pointers from a stack pointer propagate `points_to_stack`:
   - `ILInstr.Cast` (type casts, including `&mut T as *mut T`)
   - `ILInstr.Move` (SSA copies)
   - `ILInstr.Add` (pointer offset arithmetic)
   - `ILInstr.SliceConstruct` and `SliceData`
   - `ILInstr.Bitcast`
   - `ILInstr.Store` into a slot, and `ILInstr.Load` back out of it (`holds_stack_ptr`, per slot)
3. **Return Checking:** On `ILInstr.Return`, if the return operand points to the stack, compilation fails with:
   ```
   error: region escape: returning a pointer to local stack storage
   ```
4. **Store Checking:** A store or `memcpy` that writes a stack pointer, or a value holding one, to memory not derived from this frame's slots (a pointer parameter, a global, a heap allocation, the caller's return slot for an aggregate) fails with:
   ```
   error: region escape: a pointer to local stack storage is written to memory that outlives this function
   ```
5. **Across calls:** A local stack address passed to a callee that returns it or stores it away (`stash(&mut local)`, `put(h, &local)`) is caught through the callee's summary (`ret_storage`, `stores_storage`, `store_targets`, computed from its body and carried in `.zri`): the result points to the stack, or the store is a write of a stack pointer to the target. Calls through a function pointer are not followed.
6. **Owned Box Dropped at Return:** An address derived through a `Box` the function owns and drops (a local box, a by-value parameter, or reached through one by field steps) is treated like a stack address for return and store checks: returning it as a reference or writing it to memory that outlives the function is rejected at compile time (probes [`148_return_ref_to_local_box.zrl`](../../bench/safety_matrix/probes/148_return_ref_to_local_box.zrl), [`149_return_ref_to_param_box.zrl`](../../bench/safety_matrix/probes/149_return_ref_to_param_box.zrl), row `Region Escape: Reference into an Owned Box Dropped at Return (§11.2.4)`). Returning or moving the `Box` itself remains legal.

---

## 4. Threat Model of Language and Runtime Features

This section systematically enumerates the potential misuse vectors for each of Zoril's core language and runtime features from checked code, the defenses implemented across the verification pipeline, and the current boundaries or open gaps.

**Exit-code convention.** A failure the runtime cannot continue past - a bound that does not hold, a capacity that cannot be honoured, a `mmap` that fails (memory exhaustion) - exits **134**, the code the bounds checks, the arena and `make safety-matrix` read as "trapped"; it is not 1, because 1 is indistinguishable from a program that merely returned 1 (`zoril_user_trap` in `stdlib/core0.zrl`, and `bounds_trap` on top of it). A `panic:` path a program may legitimately reach - an I/O failure in `print` / `println` / `eprint` / `eprintln` (or `Result.unwrap` on an `Err(io::Error)`), an `Option.unwrap` on `None` - exits **1**. Pinned by [`tests/stdlib/test_stdlib_mmap_failure_traps.zrl`](../../tests/stdlib/test_stdlib_mmap_failure_traps.zrl), [`tests/stdlib/test_vec_remove_oob_traps.zrl`](../../tests/stdlib/test_vec_remove_oob_traps.zrl) and the `runtime_trap` probes.

### 4.1 Arenas and Arena-Backed Storage (`Vec`, `ByteVec`, `String`, `read_file`)

- **Design Model:** Arenas provide fast region-based bump allocation (`stdlib/mem.zrl`, `zoril_allocator_alloc`). Dynamic collections (`Vec`, `ByteVec`, `String`) and I/O helpers (`read_file`) allocate storage buffers within a designated arena.
- **Misuse Vectors from Safe Code:**
  - _Use-after-free / Use-after-reset:_ An arena is cleared or freed via `arena_reset` or `arena_free`, but pointers, slices, or collections referencing the cleared memory continue to be accessed. This is rejected in checked code: every collection constructor (`Vec::new_in`, `String::new_in`, `ByteVec.new`, `HashMap.new`, `InternTable.new`) and every arena-taking function (`read_file`, `read_stdin`, `[u8]::split`, `list_dir`, ...) takes `&Arena` and hands back a value that borrows that arena, so the borrow checker rejects a reset or destroy while any such value is live (probe [`128_arena_use_after_reset.zrl`](../../bench/safety_matrix/probes/128_arena_use_after_reset.zrl), [`tests/error_reporting/err_arena_handle_reset_while_read_file_slice_live.zrl`](../../tests/error_reporting/err_arena_handle_reset_while_read_file_slice_live.zrl)). A value moved out of the arena's block, where the handle's implicit `Drop` unmaps the arena at the end of that block, is rejected at the block boundary (probe [`159_arena_tied_collection_outlives_block.zrl`](../../bench/safety_matrix/probes/159_arena_tied_collection_outlives_block.zrl)). The `unsafe` `_raw` entry points take a raw pointer and are the documented escape hatch: a value that outlives its arena through one of them is not checked.
  - _Capacity exhaustion:_ Allocations exceeding the arena capacity. Statically caught at compile time when capacity and sizes are constant literals (probes [`tests/error_reporting/err_arena_oom_compile_time.zrl`](../../tests/error_reporting/err_arena_oom_compile_time.zrl), [`tests/error_reporting/err_arena_oom_interprocedural.zrl`](../../tests/error_reporting/err_arena_oom_interprocedural.zrl), row `Intra-procedural Arena Analysis (§11.2.1)` and `Inter-procedural Arena Propagation (§11.2.2)`). For dynamic allocations, the runtime allocator checks capacity and triggers a deterministic trap (`sys_exit_group(134)`). The arena's own mapping is the same class of failure: a `mmap` the kernel refuses (the arena cannot be created at all, or the global-heap path cannot grow) exits 134 with `panic: mmap_or_trap: syscall failed` rather than handing on the kernel's `-errno`.
  - _Buffer reallocation invalidation:_ Pushing into a `Vec` could reallocate the backing buffer, potentially invalidating references to existing elements. In Zoril's bump arenas, old buffers remain allocated in memory without moving or being overwritten, so stale reads never access unmapped memory. Furthermore, Zoril's borrow checker rejects mutating `v.push()` while any reference into `v` is live, whether held in an `Option<&T>` from `v.get(i)` (probe [`64_option_ref_across_push.zrl`](../../bench/safety_matrix/probes/64_option_ref_across_push.zrl)), in a slice from `v.as_slice()` (probe [`65_slice_across_push.zrl`](../../bench/safety_matrix/probes/65_slice_across_push.zrl)), or unwrapped through `.unwrap()` (probe [`147_unwrap_borrow_retention.zrl`](../../bench/safety_matrix/probes/147_unwrap_borrow_retention.zrl), row `Borrow Aliasing: Returned References (§7.2)`).
  - _Integer arithmetic overflow:_ Arithmetic in capacity calculations (e.g., `cap * 8` wrapping around). Identified during audit and scheduled for unbreakable checked arithmetic in the stdlib audit task.

### 4.2 Heap Boxes (`Box<T>`)

- **Design Model:** `Box<T>` represents exclusive heap-allocated ownership (§3.3). In this release a `Box` is not deallocated when it is dropped (it leaks; `KNOWN_ISSUES.md` §5): the checks below hold either way, and freeing at scope end is planned.
- **Misuse Vectors from Safe Code:**
  - _Use-after-move:_ Using a `Box` after moving ownership to another binding, function, or aggregate. Rejected by ZIR affine ownership tracking: once moved, subsequent reads or writes to the place are rejected at compile time (probe [`68_move_in_loop.zrl`](../../bench/safety_matrix/probes/68_move_in_loop.zrl), test [`tests/error_reporting/err_own_use_after_move.zrl`](../../tests/error_reporting/err_own_use_after_move.zrl), row `Use After Move (Linear/Owned) (§7.1)`).
  - _Double drop:_ Reclaiming heap storage multiple times. Checked by compile-time drop-flag and affine move analysis, ensuring a box drops exactly once even across conditional branches (probe [`75_move_out_of_box_drops_once.zrl`](../../bench/safety_matrix/probes/75_move_out_of_box_drops_once.zrl), row `Drop Exactly Once (§7.3, §8.4)`).
  - _Stashing stack pointers in heap boxes:_ Writing an address derived from a local stack frame into a box that could outlive the frame. Statically rejected by the ZIL region verifier (probe [`53_dangling_stack_in_box.zrl`](../../bench/safety_matrix/probes/53_dangling_stack_in_box.zrl), row `Region Escape: Stored Outside the Frame (§11.2.4)`).
  - _Leaking linear resources inside boxes:_ Enclosing linear resources (such as `fd<r>` or `ioring`) in a `Box<T>` without closing them. Statically checked via recursive type analysis (`type_holds_linear`) and rejected at compile time (probe [`146_fd_leak_inside_box.zrl`](../../bench/safety_matrix/probes/146_fd_leak_inside_box.zrl), row `Linear Resource Leakage (§7.1)`).
  - _Returning references into dropped boxes:_ Returning or storing a reference into the heap storage of a `Box` that the function owns and drops at function exit (whether a local box, a by-value parameter, or reached through one by field steps). Statically rejected by the ZIL region verifier treating addresses derived through owned dropped boxes like stack addresses for the return and store checks (probes [`148_return_ref_to_local_box.zrl`](../../bench/safety_matrix/probes/148_return_ref_to_local_box.zrl), [`149_return_ref_to_param_box.zrl`](../../bench/safety_matrix/probes/149_return_ref_to_param_box.zrl), [`150_return_ref_to_param_struct_box.zrl`](../../bench/safety_matrix/probes/150_return_ref_to_param_struct_box.zrl), row `Region Escape: Reference into an Owned Box Dropped at Return (§11.2.4)`).

### 4.3 Linear Resources (`fd`, `ioring`)

- **Design Model:** Linear types (§3.12, §9.4) represent operating-system capabilities that must be consumed exactly once. They are affine in consumption and strictly linear in lifetime.
- **Misuse Vectors from Safe Code:**
  - _Resource leaks:_ Dropping a file descriptor or io_uring instance without invoking `close()` or appropriate cleanup. Rejected by ZIR linear checking: unconsumed linear bindings at scope exit or on early return paths are rejected at compile time (probes [`76_fd_leak.zrl`](../../bench/safety_matrix/probes/76_fd_leak.zrl), [`77_fd_leak_early_return.zrl`](../../bench/safety_matrix/probes/77_fd_leak_early_return.zrl), [`78_fd_leak_one_branch.zrl`](../../bench/safety_matrix/probes/78_fd_leak_one_branch.zrl), row `Linear Resource Leakage (§7.1)`).
  - _Resource leakage inside aggregates:_ Wrapping linear resources inside structs, tuples, enums, fixed-size arrays, or heap boxes and allowing the outer aggregate to drop. Recursively inspected by `type_holds_linear` up to depth 8 and rejected at compile time (probes [`79_fd_leak_inside_struct.zrl`](../../bench/safety_matrix/probes/79_fd_leak_inside_struct.zrl), [`145_fd_leak_inside_array.zrl`](../../bench/safety_matrix/probes/145_fd_leak_inside_array.zrl), [`146_fd_leak_inside_box.zrl`](../../bench/safety_matrix/probes/146_fd_leak_inside_box.zrl)).
  - _Duplication or copying:_ Copying a linear binding via assignment or let binding. Linear types do not implement `Copy`; assignment transfers ownership (move), and duplicate binding uses are rejected (probe [`80_fd_duplicated.zrl`](../../bench/safety_matrix/probes/80_fd_duplicated.zrl)).
  - _Double close:_ Consuming or closing an `fd` more than once. Rejected by move checking: closing an `fd` moves its ownership, and subsequent close calls are rejected as use-after-move (probe [`81_fd_closed_twice.zrl`](../../bench/safety_matrix/probes/81_fd_closed_twice.zrl)).
  - _Capability forgery / Violation:_ Performing write operations on a read-only descriptor `fd<r>`, read operations on a write-only descriptor `fd<w>`, or casting `fd<r>` to `fd<w>`. Enforced at compile time by capability type checking (probes [`82_fd_write_through_read_only.zrl`](../../bench/safety_matrix/probes/82_fd_write_through_read_only.zrl), [`83_fd_read_through_write_only.zrl`](../../bench/safety_matrix/probes/83_fd_read_through_write_only.zrl), [`84_fd_capability_widened_by_cast.zrl`](../../bench/safety_matrix/probes/84_fd_capability_widened_by_cast.zrl), [`189_fd_forge_private_field.zrl`](../../bench/safety_matrix/probes/189_fd_forge_private_field.zrl), row `File Descriptor Capabilities (§3.12, §9.4)`).

### 4.4 `defer` Statements

- **Design Model:** `defer` (§6.1) schedules a block of code to execute upon scope exit in LIFO order.
- **Misuse Vectors from Safe Code:**
  - _Use-after-move within defer:_ A deferred block accessing a variable whose value was moved earlier in the enclosing scope, or code in the scope moving a value that a deferred block will subsequently use. Checked by ZIR borrow and move verification: any conflict between deferred operations and surrounding move states is rejected at compile time (probe [`143_defer_use_after_move.zrl`](../../bench/safety_matrix/probes/143_defer_use_after_move.zrl), row `Defer Use After Move (§7.1, §8.4)`).
  - _Double drop conflict:_ Explicitly dropping a value that an active `defer` statement also drops. Rejected at compile time as an illegal subsequent move/drop (probe [`73_double_drop_with_defer.zrl`](../../bench/safety_matrix/probes/73_double_drop_with_defer.zrl), row `Double Drop (§7.3, §8.4)`).
  - _Failure execution semantics:_ Runtime traps (e.g. index bounds check failures or dynamic capacity traps terminating with exit 134) intentionally bypass deferred execution blocks; defers execute strictly during normal block termination and function return sequences.

### 4.5 Closures and Function Values

- **Design Model:** Closures (§5.2) combine a code pointer with an environment tuple containing captured variables.
- **Misuse Vectors from Safe Code:**
  - _Environment stack escape:_ Returning a capturing closure from its defining stack frame, passing it to an out-parameter, or storing it into caller or heap memory where it could outlive the stack frame that created its environment. Statically rejected by the ZIL region verifier, which tracks closure environment provenance identically to slice data pointers (probes [`41_capturing_closure_to_fn.zrl`](../../bench/safety_matrix/probes/41_capturing_closure_to_fn.zrl), [`115_closure_returned_from_its_frame.zrl`](../../bench/safety_matrix/probes/115_closure_returned_from_its_frame.zrl), [`116_closure_escapes_through_callee.zrl`](../../bench/safety_matrix/probes/116_closure_escapes_through_callee.zrl), [`117_closure_stored_in_caller_vec.zrl`](../../bench/safety_matrix/probes/117_closure_stored_in_caller_vec.zrl), row `Capturing Closure Escape (§5.2)`).
  - _Unsafe type casting:_ Casting function pointers or closures to integers or raw pointers, holding function values in static variables, or passing them across `extern` boundaries. Prohibited at AST and type-checking levels.
  - _Capture by reference aliasing:_ A closure that captures a place by reference maintains an active borrow on that place for the closure's duration. Closure values (`FuncAddr`) inherit borrows of captured references from the environment tuple, so the borrow checker rejects the outer scope reassigning or mutating the referent while the closure is live (probes [`144_closure_ref_capture_mutation.zrl`](../../bench/safety_matrix/probes/144_closure_ref_capture_mutation.zrl), [`151_closure_box_ref_capture_use_after_free.zrl`](../../bench/safety_matrix/probes/151_closure_box_ref_capture_use_after_free.zrl), row `Closure Capture by Reference (§5.2)`).

### 4.6 Globals and Statics

- **Design Model:** Global variables (§4.8) exist with `'static` lifetime and may be immutable (`static`) or mutable (`static mut`).
- **Misuse Vectors from Safe Code:**
  - _Storing references in mutable statics:_ A `static mut` holding a reference or slice would risk retaining a reference to shorter-lived stack or arena memory. The driver forbids `static
    mut` variables from having reference types, slice types, or structs containing references (probe [`87_static_mut_holds_borrow.zrl`](../../bench/safety_matrix/probes/87_static_mut_holds_borrow.zrl), row `Mutable Statics Hold No References (§11.2.4)`).
  - _Mutating immutable statics:_ Assigning to an immutable `static` or taking a mutable borrow (`&mut`) of it. Statically rejected by ZIR borrow checking, which treats immutable statics as shared places (probe [`142_immutable_static_assign.zrl`](../../bench/safety_matrix/probes/142_immutable_static_assign.zrl), row `Immutable Static Assignment`).
  - _Stack address escape into statics:_ Storing a local stack address into a global static. Statically detected and rejected by the ZIL region verifier (probe [`52_dangling_stack_static.zrl`](../../bench/safety_matrix/probes/52_dangling_stack_static.zrl), row `Region Escape: Stored Outside the Frame (§11.2.4)`).
  - _Concurrency and data races:_ The Zoril core language and execution model are single-threaded; data races are not applicable (row `Data Races: N/A`). Reading and writing scalar `static mut` variables requires no unsafe block. **That exemption is a single-thread promise:** it holds because there is no other thread that can read or write the cell concurrently, and it will change when threads arrive - to per-thread statics by default, `unsafe` from a spawned thread, or atomics, as the concurrency design tracked on the [roadmap](../ROADMAP.md) decides.
  - _Non-scalar mutable statics:_ A write to a non-scalar `static mut` can retype the place, and a borrow of it is not tracked across that write, so the checker requires `unsafe` for every access to one (row `Non-Scalar static mut Access Is Unsafe`, probes [`264_static_mut_borrow_across_call.zrl`](../../bench/safety_matrix/probes/264_static_mut_borrow_across_call.zrl) through [`272_immutable_static_enum.zrl`](../../bench/safety_matrix/probes/272_immutable_static_enum.zrl)). The scalar exemption is deliberately narrow: an array, tuple or struct of scalars needs `unsafe` too, a rule that can be loosened later without breaking anyone.

### 4.7 System Calls and Extern Calls

- **Design Model:** Low-level platform interactions take place via raw kernel system calls (`@syscall`, §9.2) and foreign C functions (`extern fn`, §9.1).
- **Misuse Vectors from Safe Code:**
  - _Unchecked foreign C execution:_ Foreign functions cannot be verified by Zoril's type, ownership, or region verifiers. Calling an `extern` function without an enclosing `unsafe` block is rejected at compile time (probes [`140_extern_call_outside_unsafe.zrl`](../../bench/safety_matrix/probes/140_extern_call_outside_unsafe.zrl), [`141_extern_call_unsafe.zrl`](../../bench/safety_matrix/probes/141_extern_call_unsafe.zrl), row `Extern Function Call`).
  - _Arbitrary system calls:_ `@syscall` can invoke kernel operations that violate memory safety (e.g. unmapping memory pages or reading arbitrary pointers). Calling `@syscall` without `unsafe` is rejected at compile time (probes [`129_syscall_outside_unsafe.zrl`](../../bench/safety_matrix/probes/129_syscall_outside_unsafe.zrl), [`130_syscall_unsafe.zrl`](../../bench/safety_matrix/probes/130_syscall_unsafe.zrl), row `System Call`).
  - _Uninitialized stack allocation:_ `@alloca<T>(n)` allocates uninitialized stack memory as `&mut T`. Calling `@alloca` without `unsafe` is rejected at compile time (probes [`131_alloca_outside_unsafe.zrl`](../../bench/safety_matrix/probes/131_alloca_outside_unsafe.zrl), [`132_alloca_unsafe.zrl`](../../bench/safety_matrix/probes/132_alloca_unsafe.zrl), row `Uninitialized Stack Slot`).

### 4.8 Raw Pointers in Public APIs

- **Design Model:** Raw pointers (`*T`, `*mut T`) provide unchecked, untracked address manipulation for systems programming and foreign interfaces (§3.2).
- **Misuse Vectors from Safe Code:**
  - _Dereferencing raw pointers:_ Explicit dereference (`*p`), field access (`p.field`), and indexing (`p[i]`, `&p[i]`) on raw pointers are strictly gated and require an `unsafe` block (probe [`133_raw_ptr_index_borrow.zrl`](../../bench/safety_matrix/probes/133_raw_ptr_index_borrow.zrl), row `Raw-Pointer Indexing (§11.2.3)`).
  - _Raw pointer returned by function:_ Dereferencing a raw pointer returned directly from a function call (e.g., `*f()` or `let p = f(); *p = 1`) without `unsafe` is rejected at compile time (probe [`139_raw_call_result_deref_outside_unsafe.zrl`](../../bench/safety_matrix/probes/139_raw_call_result_deref_outside_unsafe.zrl), row `Raw Pointer Returned by a Function Call`).
  - _Integer-to-pointer forging:_ Forging pointers from arbitrary integers (`n as *T` or `@ptr_from_int`) is safe; _using_ the pointer - and forging a reference or a slice out of it - is gated on `unsafe` (row `Pointer Forgery (Raw Pointers)`, §5.2).
  - _Raw pointer conversion to reference via generics:_ A raw pointer passed through a type parameter stays raw, so it cannot come out as a reference without `unsafe` (probe [`125_raw_pointer_to_reference_through_generic.zrl`](../../bench/safety_matrix/probes/125_raw_pointer_to_reference_through_generic.zrl), `compile_reject`).
  - _Raw pointer laundering through aggregates or bindings:_ A raw pointer passed through a container (tuple, struct, array, enum) or a pattern binding keeps its pointer type, so checked code can neither dereference it nor turn it into a reference; probes [`152_launder_raw_ptr_match_binding.zrl`](../../bench/safety_matrix/probes/152_launder_raw_ptr_match_binding.zrl) through [`158_launder_null_ref_tuple.zrl`](../../bench/safety_matrix/probes/158_launder_null_ref_tuple.zrl) all expect `compile_reject`.
  - _Safe functions dereferencing raw pointers:_ the allocator primitives (`zoril_allocator_alloc`, `zoril_allocator_realloc`, `zoril_allocator_free`) take a raw pointer they write through and are `unsafe fn` now, so a safe call is rejected - probe [`127_safe_fn_derefs_raw_pointer_argument.zrl`](../../bench/safety_matrix/probes/127_safe_fn_derefs_raw_pointer_argument.zrl). The last function of the class, `Args.new(argc, argv: **u8)`, is `unsafe fn` too, and the safe path is `args()`: `_start` records the pair in the runtime, so no caller supplies a pointer - probe [`160_args_raw_pointer_argument.zrl`](../../bench/safety_matrix/probes/160_args_raw_pointer_argument.zrl) pins the rejection (row `Safe Function Dereferencing a Raw Pointer Argument`).

### 4.9 The Stdlib's `unsafe` Interiors (the trusted base)

Every safety claim in this document rests on `stdlib/`, whose `unsafe` blocks are the base the verifier is not asked to check. The audit asked the question that base had never been asked: _which invariant does each block rely on, and can checked code break it?_ Five could be broken, all of one shape - arithmetic or a field the block trusted:

- `Vec::with_capacity_in(&a, 1 << 61)` computed `cap * sizeof(T)` = 0: the Vec claimed 2^61 slots over a zero-byte allocation, so the next allocation aliased it and a `push` overwrote it (probe [`163_vec_capacity_overflow.zrl`](../../bench/safety_matrix/probes/163_vec_capacity_overflow.zrl)).
- `zoril_allocator_alloc(a, u64::MAX)` wrapped `aligned_offset + size`, passed the capacity check and handed the same bytes out twice (probe [`161_arena_allocator_size_wrap.zrl`](../../bench/safety_matrix/probes/161_arena_allocator_size_wrap.zrl)).
- `str_sub(s, 2, u64::MAX)` wrapped `start + len`, skipped the clamp and returned a slice claiming 2^64-1 bytes (`tests/stdlib/test_stdlib_str_sub_clamp.zrl`).
- `args().get((1 << 31) + 5)` truncated the index to `i32`, passed the bounds guard and read past `argv`, with no `unsafe` in the program (probe [`162_args_get_index_truncation.zrl`](../../bench/safety_matrix/probes/162_args_get_index_truncation.zrl)).
- `v.len = 1000000` compiled, and `v.get(999999)` read out of bounds: the fields _were_ the invariant (probes [`164_vec_len_forge.zrl`](../../bench/safety_matrix/probes/164_vec_len_forge.zrl), [`165_vec_set_len_above_cap.zrl`](../../bench/safety_matrix/probes/165_vec_set_len_above_cap.zrl)).

The fixes are what the row `Stdlib unsafe Interiors` records: sizes go through `mem::size_of_n`/`grow_cap` (which trap instead of wrapping), the allocator compares by subtracting from `capacity`, the collections' fields are private behind narrow accessors (`cap`, `as_ptr`, `as_mut_ptr`, `raw_arena`, `unsafe fn set_len` that traps above `cap`, `HashMap::entry_at` that checks its index), and every block now names its invariant in a `// SAFETY:` comment that `scripts/check_safety_comments.sh` requires in `make test`.

What this does _not_ claim: the comments are a review artifact, not a proof. They make each assumption visible at the line that depends on it, and only the five audited classes have tests. The `unsafe fn` primitives stay callable from `unsafe` code by design, and code that keeps its own `unsafe` invariants (the compiler's own arenas, `rt/runtime.s`) is outside what the verifier or this audit sees.

## 5. Unsafe Operation × Route Reachability Grid

The safety model partitions language capabilities into safe operations (verified by the type system, borrow checker, region analyzer, and runtime bounds checks) and unsafe operations (operations that can cause undefined behavior or violate memory safety if executed in an invalid state). Every unsafe operation must be guarded such that checked code cannot execute it under any syntactic or lowering route.

This section provides the exhaustive Reachability Grid across the 5 canonical unsafe operations (alongside the complementary low-level intrinsics `@syscall` and `@alloca`) and the 8 lowering routes available in the Zoril language:

1. **Explicit syntax:** Direct syntactic invocation in user code (`*p`, `&*p`, `@slice(...)`, a call to an `extern` function, `@syscall`, `@alloca`; and the gated half of a pointer conversion, `@ptr_cast<&T>` / `@ptr_from_int<&T>` — creating a raw pointer, `n as *T`, is not gated).
2. **Auto-deref:** Implicit dereferences through field projection (`p.field`), tuple index (`p.0`), method calls (`p.method()`), or array indexing (`p[i]`, `&p[i]`).
3. **Coercion sites:** Implicit type conversions at assignment (`x = y`), `let` binding, function argument passing, return expressions, struct field initialization, and block tail expressions.
4. **Generics:** Type substitution, trait bounds, and generic instantiation where concrete types interact with type parameters.
5. **Closures:** Closure body execution and capture environments (`__env`).
6. **Match bindings:** Destructuring, pattern matching bindings, and variant projection.
7. **`defer`:** Deferred block execution at function/scope exit.
8. **Cross-module imports:** Symbol resolution, signature verification, and re-exports across compilation units.

### Summary Reachability Matrix

- **Raw dereference (`*p`, `p[i]`, `p.field`)**
  - Explicit Syntax: Rejected outside `unsafe` (probes [`14_null_deref.zrl`](../../bench/safety_matrix/probes/14_null_deref.zrl), [`31_null_deref_unsafe.zrl`](../../bench/safety_matrix/probes/31_null_deref_unsafe.zrl))
  - Auto-Deref: Rejected outside `unsafe` (probes [`12_raw_ptr_indexing.zrl`](../../bench/safety_matrix/probes/12_raw_ptr_indexing.zrl), [`120_raw_pointer_field_access.zrl`](../../bench/safety_matrix/probes/120_raw_pointer_field_access.zrl))
  - Coercion Sites: Cannot occur (no implicit deref)
  - Generics: Type parameter cannot deref
  - Closures: Body checked; a capture keeps the raw type, so the dereference is gated (probe [`154_launder_raw_ptr_closure.zrl`](../../bench/safety_matrix/probes/154_launder_raw_ptr_closure.zrl))
  - Match Bindings: A binding keeps the raw type, so the dereference is gated (probes [`152_launder_raw_ptr_match_binding.zrl`](../../bench/safety_matrix/probes/152_launder_raw_ptr_match_binding.zrl), [`157_launder_raw_ptr_option_match.zrl`](../../bench/safety_matrix/probes/157_launder_raw_ptr_option_match.zrl))
  - `defer`: Lowered and gated
  - Cross-Module: Symbol signatures enforce `unsafe` (probe [`139_raw_call_result_deref_outside_unsafe.zrl`](../../bench/safety_matrix/probes/139_raw_call_result_deref_outside_unsafe.zrl))
- **Pointer forging (`n as *T`, `@ptr_from_int`)**
  - Explicit Syntax: Creation accepted; the _use_ rejected outside `unsafe` (probes [`13_forged_pointer.zrl`](../../bench/safety_matrix/probes/13_forged_pointer.zrl), [`122_int_to_raw_pointer_cast.zrl`](../../bench/safety_matrix/probes/122_int_to_raw_pointer_cast.zrl), [`187_int_to_raw_ptr_cast_safe.zrl`](../../bench/safety_matrix/probes/187_int_to_raw_ptr_cast_safe.zrl))
  - Auto-Deref: Cannot occur (only projects)
  - Coercion Sites: Cannot occur (type mismatch)
  - Generics: Cast `n as T` rejected; `@ptr_from_int<T>` gated (probe [`29_generic_null_cast.zrl`](../../bench/safety_matrix/probes/29_generic_null_cast.zrl))
  - Closures: Lowered like any other cast; the capture keeps the raw type, so the dereference in the body is gated
  - Match Bindings: Cannot occur (patterns only bind)
  - `defer`: Lowered, and the use gated where it appears
  - Cross-Module: A constant initializer may hold the address
- **Slice forging (`@slice`)**
  - Explicit Syntax: Rejected outside `unsafe` (probe [`63_slice_forged_from_reference.zrl`](../../bench/safety_matrix/probes/63_slice_forged_from_reference.zrl))
  - Auto-Deref: Cannot occur (only projects)
  - Coercion Sites: Cannot occur (types match or fail)
  - Generics: Intrinsic cannot be genericized
  - Closures: Lowered and gated in closure body
  - Match Bindings: Cannot occur (patterns only slice)
  - `defer`: Lowered and gated
  - Cross-Module: Module interface typed as slice
- **Foreign function calls (`extern fn`)**
  - Explicit Syntax: Rejected outside `unsafe` (probes [`140_extern_call_outside_unsafe.zrl`](../../bench/safety_matrix/probes/140_extern_call_outside_unsafe.zrl), [`141_extern_call_unsafe.zrl`](../../bench/safety_matrix/probes/141_extern_call_unsafe.zrl))
  - Auto-Deref: Cannot occur (no extern methods)
  - Coercion Sites: Cannot occur (fn value rejected; [`tests/error_reporting/err_extern_fn_value_param.zrl`](../../tests/error_reporting/err_extern_fn_value_param.zrl))
  - Generics: Foreign fn cannot satisfy trait
  - Closures: Lowered and gated in closure body
  - Match Bindings: Cannot occur (symbol not a pattern)
  - `defer`: Lowered and gated
  - Cross-Module: Symbol table preserves `is_extern`
- **Raw-to-reference (`*T` -> `&T`)**
  - Explicit Syntax: Rejected outside `unsafe` (probes [`123_raw_pointer_to_reference.zrl`](../../bench/safety_matrix/probes/123_raw_pointer_to_reference.zrl), [`124_raw_pointer_to_reference_unsafe.zrl`](../../bench/safety_matrix/probes/124_raw_pointer_to_reference_unsafe.zrl))
  - Auto-Deref: Rejected outside `unsafe` (probe [`133_raw_ptr_index_borrow.zrl`](../../bench/safety_matrix/probes/133_raw_ptr_index_borrow.zrl))
  - Coercion Sites: Rejected: the projection keeps the raw type, so the conversion is a type error (probe [`158_launder_null_ref_tuple.zrl`](../../bench/safety_matrix/probes/158_launder_null_ref_tuple.zrl))
  - Generics: Rejected: identity keeps the raw type (probe [`125_raw_pointer_to_reference_through_generic.zrl`](../../bench/safety_matrix/probes/125_raw_pointer_to_reference_through_generic.zrl))
  - Closures: Checked at boundaries
  - Match Bindings: Rejected: a binding keeps the raw type (probes [`152_launder_raw_ptr_match_binding.zrl`](../../bench/safety_matrix/probes/152_launder_raw_ptr_match_binding.zrl), [`157_launder_raw_ptr_option_match.zrl`](../../bench/safety_matrix/probes/157_launder_raw_ptr_option_match.zrl))
  - `defer`: Lowered and gated
  - Cross-Module: Signatures enforce `check_raw_into_ref`
- **System call (`@syscall`)**
  - Explicit Syntax: Rejected outside `unsafe` (probes [`129_syscall_outside_unsafe.zrl`](../../bench/safety_matrix/probes/129_syscall_outside_unsafe.zrl), [`130_syscall_unsafe.zrl`](../../bench/safety_matrix/probes/130_syscall_unsafe.zrl))
  - Auto-Deref: Cannot occur (compiler intrinsic)
  - Coercion Sites: Cannot occur (no syscall coercion)
  - Generics: Intrinsic cannot be genericized
  - Closures: Lowered and gated in closure body
  - Match Bindings: Cannot occur (symbol not a pattern)
  - `defer`: Lowered and gated
  - Cross-Module: Intrinsic not exportable
- **Stack allocation (`@alloca`)**
  - Explicit Syntax: Rejected outside `unsafe` (probes [`131_alloca_outside_unsafe.zrl`](../../bench/safety_matrix/probes/131_alloca_outside_unsafe.zrl), [`132_alloca_unsafe.zrl`](../../bench/safety_matrix/probes/132_alloca_unsafe.zrl))
  - Auto-Deref: Cannot occur (compiler intrinsic)
  - Coercion Sites: Cannot occur (no alloca coercion)
  - Generics: Intrinsic cannot be genericized
  - Closures: Lowered and gated in closure body
  - Match Bindings: Cannot occur (symbol not a pattern)
  - `defer`: Lowered and gated
  - Cross-Module: Intrinsic not exportable

_(Note: Table rows begin without leading asterisks to distinguish this route analysis from the 68 normative safety properties in Section 2.)_

---

### 5.1 Raw Pointer Dereference

Dereferencing a raw pointer (`*const T`, `*mut T`) bypasses lifetime and alias tracking; reading or writing through an unaligned, dangling, or null raw pointer leads to segmentation faults or memory corruption.

- **Explicit Syntax:** Gated in ZIR lowering (`lower_unary_expr` in [`src/lower_zir/expr.zrl`](../../src/lower_zir/expr.zrl)). Dereference `*p` checks `place_is_raw_ptr`; if true and `ctx.unsafe_depth == 0`, lowering emits a compile-time error.
  - Proved by probe [`14_null_deref.zrl`](../../bench/safety_matrix/probes/14_null_deref.zrl) (rejection outside `unsafe`) and [`31_null_deref_unsafe.zrl`](../../bench/safety_matrix/probes/31_null_deref_unsafe.zrl) (permitted inside `unsafe`).
  - Attempting to dereference non-pointer types is rejected by [`tests/error_reporting/err_deref_non_pointer.zrl`](../../tests/error_reporting/err_deref_non_pointer.zrl).
- **Auto-Deref:** Field access (`p.field`), tuple element access (`p.0`), method receiver calls (`p.method()`), and indexing (`p[i]`, `&p[i]`) perform implicit dereferences.
  - In [`src/lower_zir/expr.zrl`](../../src/lower_zir/expr.zrl) (`lower_member_access_expr`, `Expr.TupleAccess`, `Expr.Index`), `check_raw_deref_is_marked` and `place_is_raw_ptr` verify that any auto-dereference on a raw pointer base is enclosed in an `unsafe` block.
  - Proved by probes:
    - Index read: [`12_raw_ptr_indexing.zrl`](../../bench/safety_matrix/probes/12_raw_ptr_indexing.zrl) (rejected) vs [`36_raw_ptr_indexing_unsafe.zrl`](../../bench/safety_matrix/probes/36_raw_ptr_indexing_unsafe.zrl) (allowed in `unsafe`).
    - Field access: [`120_raw_pointer_field_access.zrl`](../../bench/safety_matrix/probes/120_raw_pointer_field_access.zrl) (rejected) vs [`121_raw_pointer_field_access_unsafe.zrl`](../../bench/safety_matrix/probes/121_raw_pointer_field_access_unsafe.zrl) (allowed in `unsafe`).
    - Slice raw pointer dereference (`s.ptr.field`): [`126_slice_ptr_deref.zrl`](../../bench/safety_matrix/probes/126_slice_ptr_deref.zrl).
    - Borrow of raw index (`&p[i]`): [`133_raw_ptr_index_borrow.zrl`](../../bench/safety_matrix/probes/133_raw_ptr_index_borrow.zrl), [`tests/error_reporting/err_raw_ptr_index_borrow.zrl`](../../tests/error_reporting/err_raw_ptr_index_borrow.zrl).
    - Field write and tuple access: [`tests/error_reporting/err_raw_ptr_field_write.zrl`](../../tests/error_reporting/err_raw_ptr_field_write.zrl), [`tests/error_reporting/err_raw_ptr_tuple_field.zrl`](../../tests/error_reporting/err_raw_ptr_tuple_field.zrl), [`tests/error_reporting/err_raw_ptr_nested_field.zrl`](../../tests/error_reporting/err_raw_ptr_nested_field.zrl).
- **Coercion Sites:** _Cannot occur._ Zoril has no implicit dereference coercions (e.g. `T` is never implicitly produced from `*T`). A type mismatch is emitted at every coercion site where a value is expected instead of a pointer ([`tests/error_reporting/err_assign_type_mismatch.zrl`](../../tests/error_reporting/err_assign_type_mismatch.zrl)).
- **Generics:** _Cannot occur._ An unconstrained type parameter `T` cannot be dereferenced (`*t` is rejected because `T` is not recognized as a pointer in `src/lower_zir/expr.zrl`; [`tests/error_reporting/err_deref_non_pointer.zrl`](../../tests/error_reporting/err_deref_non_pointer.zrl)). Trait bounds cannot express raw pointer dereferences.
- **Closures:**
  - Explicit dereferences or auto-derefs written inside a closure body are lowered under the closure's local AST context and are rejected if not enclosed in `unsafe` (probe [`14_null_deref.zrl`](../../bench/safety_matrix/probes/14_null_deref.zrl)).
  - A raw pointer captured by a closure keeps its own type in the closure's environment, so a dereference through such a capture is gated like any other (probe [`154_launder_raw_ptr_closure.zrl`](../../bench/safety_matrix/probes/154_launder_raw_ptr_closure.zrl) expects `compile_reject`).
- **Match Bindings:**
  - Patterns cannot dereference raw pointers (`*p` is not a pattern).
  - In `match p { q => ... }` and `match Option.Some(p) { Some(q) => ... }`, the binding `q` carries `p`'s pointer type, so `*q` needs `unsafe` (probes [`152_launder_raw_ptr_match_binding.zrl`](../../bench/safety_matrix/probes/152_launder_raw_ptr_match_binding.zrl), [`157_launder_raw_ptr_option_match.zrl`](../../bench/safety_matrix/probes/157_launder_raw_ptr_option_match.zrl), both `compile_reject`).
- **`defer`:** Deferred blocks are lowered via `lower_block`. Any raw dereference inside a `defer` statement is checked against `unsafe_depth` and rejected outside `unsafe` (probe [`14_null_deref.zrl`](../../bench/safety_matrix/probes/14_null_deref.zrl)).
- **Cross-Module Imports:** Function return types across module interfaces keep the raw pointer's own type, so a raw pointer returned by an imported function is still raw at the call site, and dereferencing it without `unsafe` is rejected (probes [`139_raw_call_result_deref_outside_unsafe.zrl`](../../bench/safety_matrix/probes/139_raw_call_result_deref_outside_unsafe.zrl), [`tests/error_reporting/err_raw_call_result_deref.zrl`](../../tests/error_reporting/err_raw_call_result_deref.zrl)).

---

### 5.2 Pointer Forging

Forging pointers from integers (`n as *T`, `@ptr_from_int(n)`) allows fabricating arbitrary addresses. Creating one is **safe** — this section is about the two things that are not: using it, and forging a _reference_ or a _slice_ instead of a raw pointer.

- **Creating a raw pointer is safe.** `n as *T`, `@ptr_from_int<*T>`, `@ptr_cast<*T>` and their `*mut` forms are accepted outside `unsafe`, and so is `@int_cast<U>`, whose result is a number. Every _use_ of the pointer is gated on its own type (the clause below), so a marker on the creation would sit around checked code and buy nothing — and a fixed hardware address, the memory-mapped-I/O case, needs a spelling in a `static`, whose initializer has nowhere to put an `unsafe` block. The decision is `ZirLowerer.ptr_forge_needs_unsafe` in [`src/lower_zir/utils.zrl`](../../src/lower_zir/utils.zrl).
  - Proved by [`bench/safety_matrix/probes/122_int_to_raw_pointer_cast.zrl`](../../bench/safety_matrix/probes/122_int_to_raw_pointer_cast.zrl), [`187_int_to_raw_ptr_cast_safe.zrl`](../../bench/safety_matrix/probes/187_int_to_raw_ptr_cast_safe.zrl), [`tests/functional/pointers/int_to_raw_ptr_cast.zrl`](../../tests/functional/pointers/int_to_raw_ptr_cast.zrl), [`tests/language/other/static_initializer_fixed_address.zrl`](../../tests/language/other/static_initializer_fixed_address.zrl) (a `static` whose initializer is a fixed address, read back as a value in checked code).
- **Using a forged pointer is gated on the pointer's type.** A dereference, a field access, an index, a method call through it and a conversion to a reference all need `unsafe` (`check_raw_deref_is_marked`, `check_raw_arg_is_marked`, `check_raw_into_ref`), whatever produced the pointer.
  - Proved by probes [`13_forged_pointer.zrl`](../../bench/safety_matrix/probes/13_forged_pointer.zrl), [`33_forged_pointer_unsafe.zrl`](../../bench/safety_matrix/probes/33_forged_pointer_unsafe.zrl), [`tests/error_reporting/err_int_to_raw_ptr_cast_deref.zrl`](../../tests/error_reporting/err_int_to_raw_ptr_cast_deref.zrl) (the located error is at the dereference, not at the cast).
- **A reference or a slice result is still gated.** `@ptr_cast<&T>`, `@ptr_from_int<&T>`, `@ptr_cast<[T]>` and the same intrinsics on a type parameter — which may stand for a reference — need `unsafe` (`check_ptr_forge_is_marked`): nothing checked the null-ness of the reference or the length of the slice. The `as` form of the same conversion is refused outright by `check_cast_validity` ("cannot cast integer to reference type: references cannot be null").
  - Proved by [`tests/error_reporting/err_ptr_cast_to_reference_or_slice.zrl`](../../tests/error_reporting/err_ptr_cast_to_reference_or_slice.zrl), [`tests/error_reporting/err_cast_null_ref.zrl`](../../tests/error_reporting/err_cast_null_ref.zrl).
- **Reinterpretation between raw pointer types** (`p as *U`, `@ptr_cast<*U>(p)`) is the same decision as the creation: it is safe, and what it produces is gated on use ([`bench/safety_matrix/probes/27_type_confusion.zrl`](../../bench/safety_matrix/probes/27_type_confusion.zrl)).
- **Auto-Deref:** _Cannot occur._ Auto-deref only navigates fields and elements of existing pointers and references; it never synthesizes pointers from scalar values.
- **Coercion Sites:** _Cannot occur._ Implicit conversion from integer types (`i32`, `i64`, `usize`) to pointer types is rejected by `types_match` in [`src/lower_zir/utils.zrl`](../../src/lower_zir/utils.zrl) ([`tests/error_reporting/err_assign_type_mismatch.zrl`](../../tests/error_reporting/err_assign_type_mismatch.zrl)).
- **Generics:** Casting an integer to a generic type parameter (`n as T`) is rejected by `lower_cast_expr` in [`src/lower_zir/expr.zrl`](../../src/lower_zir/expr.zrl) ([`tests/error_reporting/err_cast_int_to_type_param.zrl`](../../tests/error_reporting/err_cast_int_to_type_param.zrl), probes [`29_generic_null_cast.zrl`](../../bench/safety_matrix/probes/29_generic_null_cast.zrl), [`90_generic_cast_reinterpret.zrl`](../../bench/safety_matrix/probes/90_generic_cast_reinterpret.zrl)). `@ptr_from_int<T>` / `@ptr_cast<T>` on a type parameter are gated instead, for the same reason: the parameter may stand for a reference.
- **Closures:** A cast inside a closure body is lowered through `lower_cast_expr` like any other, so the same rule applies - and if it produces a raw pointer, the _captured_ pointer keeps its raw type through the environment, which is what gates the dereference inside the body (probe [`154_launder_raw_ptr_closure.zrl`](../../bench/safety_matrix/probes/154_launder_raw_ptr_closure.zrl)).
- **Match Bindings:** _Cannot occur._ Pattern matching decomposes existing structures; it does not execute casts or synthesize addresses.
- **`defer`:** Deferred statements containing a pointer-creation cast are lowered through `lower_cast_expr`; a use of the result is gated where it appears.
- **Cross-Module Imports:** An imported module's `static` may hold a forged address, and its uses need the same `unsafe` as anywhere else; no cross-module route reaches an ungated use.

---

### 5.3 Slice Forging (`@slice`)

Slices (`[T]`, `[mut T]`) package a base pointer and length. Fabricating a slice with an arbitrary length (`@slice(ptr, len)`) can induce out-of-bounds reads or writes.

- **Explicit Syntax:** Gated by `check_slice_forge_is_marked` in [`src/lower_zir/utils.zrl`](../../src/lower_zir/utils.zrl). Calling `@slice(p, n)` where `n != 0` outside `unsafe` is rejected at compile time (probe [`63_slice_forged_from_reference.zrl`](../../bench/safety_matrix/probes/63_slice_forged_from_reference.zrl), [`tests/error_reporting/err_slice_forge_reference.zrl`](../../tests/error_reporting/err_slice_forge_reference.zrl)). (Zero-length empty slices `@slice(p, 0)` are permitted in checked code).
- **Auto-Deref:** _Cannot occur._ Auto-deref accesses existing fields or dereferences pointers; it never constructs slice descriptors.
- **Coercion Sites:** _Cannot occur._ Array-to-slice coercion (`&[T; N]` -> `[T]`) is safe because the compiler synthesizes the exact compile-time constant array length `N`. Coercing arbitrary integers or values to slice types is rejected at compile time (probes [`105_cast_int_to_slice.zrl`](../../bench/safety_matrix/probes/105_cast_int_to_slice.zrl), [`43_array_value_as_slice.zrl`](../../bench/safety_matrix/probes/43_array_value_as_slice.zrl)):
  - Proved by probes [`105_cast_int_to_slice.zrl`](../../bench/safety_matrix/probes/105_cast_int_to_slice.zrl), [`107_cast_int_to_slice_through_alias.zrl`](../../bench/safety_matrix/probes/107_cast_int_to_slice_through_alias.zrl), [`43_array_value_as_slice.zrl`](../../bench/safety_matrix/probes/43_array_value_as_slice.zrl), and [`tests/error_reporting/err_array_value_to_slice_assign.zrl`](../../tests/error_reporting/err_array_value_to_slice_assign.zrl).
- **Generics:** _Cannot occur._ `@slice` is a built-in compiler intrinsic, not a trait or generic method. Type parameter substitution cannot instantiate an unchecked slice construction.
- **Closures:** `@slice` calls inside closure bodies are checked by `check_slice_forge_is_marked`.
- **Match Bindings:** _Cannot occur._ Slice pattern matching (`[first, ..rest]`) decomposes existing slices under bounds validation; it never constructs new unchecked lengths.
- **`defer`:** `@slice` calls in `defer` statements are checked during lowering.
- **Cross-Module Imports:** Exported slices across module interfaces are typed as `[T]` or `[mut T]`. Their slice headers were constructed safely at the source or within an `unsafe` block.

---

### 5.4 Foreign Function Calls (`extern fn`)

Foreign functions implemented in C or assembly cannot be validated by Zoril's safety verifiers. Direct calls to foreign code can perform arbitrary unverified memory operations.

- **Explicit Syntax:** Gated by `check_extern_call_is_marked` in [`src/lower_zir/expr.zrl`](../../src/lower_zir/expr.zrl). Calling an `extern fn` without an enclosing `unsafe` block is rejected at compile time (probes [`140_extern_call_outside_unsafe.zrl`](../../bench/safety_matrix/probes/140_extern_call_outside_unsafe.zrl), [`141_extern_call_unsafe.zrl`](../../bench/safety_matrix/probes/141_extern_call_unsafe.zrl), [`tests/error_reporting/err_extern_call_outside_unsafe.zrl`](../../tests/error_reporting/err_extern_call_outside_unsafe.zrl)).
- **Auto-Deref:** _Cannot occur._ Foreign functions are top-level C symbols; they cannot be defined as struct methods or invoked via auto-deref method dispatch.
- **Coercion Sites:** _Cannot occur._ Passing an `extern fn` as a first-class function pointer value or coercing it to a checked Zoril closure or function type is rejected at compile time ([`tests/error_reporting/err_extern_fn_value_param.zrl`](../../tests/error_reporting/err_extern_fn_value_param.zrl), [`tests/error_reporting/err_fn_value_cast.zrl`](../../tests/error_reporting/err_fn_value_cast.zrl)).
- **Generics:** _Cannot occur._ Foreign functions cannot implement Zoril traits or satisfy generic type bounds.
- **Closures:** Calling an `extern fn` from inside a closure body is checked by `check_extern_call_is_marked` during closure body lowering.
- **Match Bindings:** _Cannot occur._ Foreign functions are callable symbols, not pattern values.
- **`defer`:** Invoking an `extern fn` in a `defer` statement is lowered via `lower_call_expr` and checked by `check_extern_call_is_marked`.
- **Cross-Module Imports:** Re-exported or imported `extern fn` symbols retain `is_extern = true` in the module symbol table. Cross-module calls are checked identically to local extern declarations ([`tests/incremental/c_ffi_unsafe_err.zrl`](../../tests/incremental/c_ffi_unsafe_err.zrl), [`tests/integration/test_ffi.zrl`](../../tests/integration/test_ffi.zrl)).

---

### 5.5 Raw-to-Reference Conversion

Converting an unverified raw pointer (`*T`, `*mut T`) into a safe reference (`&T`, `&mut T`) circumvents borrow checking, alias guarantees, and non-null invariants (probes [`123_raw_pointer_to_reference.zrl`](../../bench/safety_matrix/probes/123_raw_pointer_to_reference.zrl), [`124_raw_pointer_to_reference_unsafe.zrl`](../../bench/safety_matrix/probes/124_raw_pointer_to_reference_unsafe.zrl)).

- **Explicit Syntax:** Explicitly casting or annotating a raw pointer as a reference (`let r: &T = p as &T`) is checked by `check_raw_into_ref` in [`src/lower_zir/utils.zrl`](../../src/lower_zir/utils.zrl) and rejected outside `unsafe` (probes [`123_raw_pointer_to_reference.zrl`](../../bench/safety_matrix/probes/123_raw_pointer_to_reference.zrl), [`124_raw_pointer_to_reference_unsafe.zrl`](../../bench/safety_matrix/probes/124_raw_pointer_to_reference_unsafe.zrl), [`tests/error_reporting/err_raw_ptr_to_ref_let.zrl`](../../tests/error_reporting/err_raw_ptr_to_ref_let.zrl)).
- **Auto-Deref:** Taking a reference to a raw projection (`&p[i]` or `&p.field`) converts raw indirection into a safe borrow. This is gated on `unsafe_depth` in `lower_unary_expr` and `lower_expr`:
  - Proved by probe [`133_raw_ptr_index_borrow.zrl`](../../bench/safety_matrix/probes/133_raw_ptr_index_borrow.zrl) and [`tests/error_reporting/err_raw_ptr_index_borrow.zrl`](../../tests/error_reporting/err_raw_ptr_index_borrow.zrl).
- **Coercion Sites:** Passing `*T` where `&T` or `&mut T` is expected is caught by `check_raw_into_ref` across all direct syntactic positions:
  - Assignment: [`tests/error_reporting/err_raw_ptr_to_ref_assign.zrl`](../../tests/error_reporting/err_raw_ptr_to_ref_assign.zrl)
  - Return expression: [`tests/error_reporting/err_raw_ptr_to_ref_return.zrl`](../../tests/error_reporting/err_raw_ptr_to_ref_return.zrl)
  - Method/function argument: [`tests/error_reporting/err_raw_ptr_to_ref_method_arg.zrl`](../../tests/error_reporting/err_raw_ptr_to_ref_method_arg.zrl)
  - Struct field initialization: [`tests/error_reporting/err_raw_ptr_to_ref_struct_field.zrl`](../../tests/error_reporting/err_raw_ptr_to_ref_struct_field.zrl)
  - Block tail expression: [`tests/error_reporting/err_raw_ptr_to_ref_tail.zrl`](../../tests/error_reporting/err_raw_ptr_to_ref_tail.zrl)
  - An aggregate projection carries the raw type (`let t = (p, 1); let r: &i32 = t.0;`), so the conversion to a reference is a type error (probe [`158_launder_null_ref_tuple.zrl`](../../bench/safety_matrix/probes/158_launder_null_ref_tuple.zrl), `compile_reject`).
- **Generics:**
  - _Direct Cast:_ Casting `p as T` where `T` is a reference type parameter is rejected at compile time (probe [`108_raw_pointer_cast_to_reference_type_param.zrl`](../../bench/safety_matrix/probes/108_raw_pointer_cast_to_reference_type_param.zrl)).
  - A raw pointer passed through an identity generic function `fn id<T>(x: T) -> T` comes back raw (`let r: &i32 = id(p)`): monomorphization substitutes the argument's type, so the conversion is a type error (probe [`125_raw_pointer_to_reference_through_generic.zrl`](../../bench/safety_matrix/probes/125_raw_pointer_to_reference_through_generic.zrl), `compile_reject`; the accepted twin is [`tests/language/generics/type_param_instantiated_with_raw_pointer.zrl`](../../tests/language/generics/type_param_instantiated_with_raw_pointer.zrl)).
- **Closures:** Checked by `check_raw_into_ref` on closure argument and return boundaries.
- **Match Bindings:** Pattern matching does not provide reference-synthesizing patterns for raw pointers, and a pattern variable binding carries the pointer's type with it, so a dereference through the binding is gated (probes [`152_launder_raw_ptr_match_binding.zrl`](../../bench/safety_matrix/probes/152_launder_raw_ptr_match_binding.zrl), [`157_launder_raw_ptr_option_match.zrl`](../../bench/safety_matrix/probes/157_launder_raw_ptr_option_match.zrl), both `compile_reject`).
- **`defer`:** Deferred conversions or coercions are checked by `check_raw_into_ref`.
- **Cross-Module Imports:** Imported function signatures preserve pointer vs reference types, enforcing `check_raw_into_ref` at caller sites.

---

### 5.6 Complementary Low-Level Intrinsics: `@syscall` and `@alloca`

Two additional low-level built-ins bypass safe runtime semantics:

- **`@syscall` (§9.2):** Issues raw kernel system calls, which can map/unmap memory or read arbitrary pointers. Gated strictly at explicit syntax by `check_syscall_is_marked` in [`src/lower_zir/expr.zrl`](../../src/lower_zir/expr.zrl) (probes [`129_syscall_outside_unsafe.zrl`](../../bench/safety_matrix/probes/129_syscall_outside_unsafe.zrl), [`130_syscall_unsafe.zrl`](../../bench/safety_matrix/probes/130_syscall_unsafe.zrl), and [`tests/error_reporting/err_syscall_outside_unsafe.zrl`](../../tests/error_reporting/err_syscall_outside_unsafe.zrl)).
- **`@alloca` (§11.2.5):** Allocates uninitialized stack slots. Gated strictly at explicit syntax by `check_alloca_is_marked` in [`src/lower_zir/expr.zrl`](../../src/lower_zir/expr.zrl) (probes [`131_alloca_outside_unsafe.zrl`](../../bench/safety_matrix/probes/131_alloca_outside_unsafe.zrl), [`132_alloca_unsafe.zrl`](../../bench/safety_matrix/probes/132_alloca_unsafe.zrl), and [`tests/error_reporting/err_alloca_outside_unsafe.zrl`](../../tests/error_reporting/err_alloca_outside_unsafe.zrl)).

Neither intrinsic is reachable through auto-deref, coercion, generics, pattern matching, or cross-module export.

---

### 5.7 Raw Pointers Keep Their Type

The intermediate language gives raw pointers their own types (`RawPtr`, `RawPtrMut`) beside the reference types (`Ptr`, `PtrMut`), and every check that gates a raw pointer decides from that type. A raw pointer keeps it through every route a value can take: a type parameter and its instantiation, a tuple, struct or array and its projections, a pattern binding, and a closure's captured environment. So no route turns one into a reference without `unsafe`, and no route lets checked code dereference, index or project through one. The conversion routes are pinned by [`125_raw_pointer_to_reference_through_generic`](../../bench/safety_matrix/probes/125_raw_pointer_to_reference_through_generic.zrl), [`152_launder_raw_ptr_match_binding`](../../bench/safety_matrix/probes/152_launder_raw_ptr_match_binding.zrl), [`153_launder_raw_ptr_tuple`](../../bench/safety_matrix/probes/153_launder_raw_ptr_tuple.zrl), [`154_launder_raw_ptr_closure`](../../bench/safety_matrix/probes/154_launder_raw_ptr_closure.zrl), [`155_launder_raw_ptr_struct`](../../bench/safety_matrix/probes/155_launder_raw_ptr_struct.zrl), [`156_launder_raw_ptr_array`](../../bench/safety_matrix/probes/156_launder_raw_ptr_array.zrl), [`157_launder_raw_ptr_option_match`](../../bench/safety_matrix/probes/157_launder_raw_ptr_option_match.zrl), [`158_launder_null_ref_tuple`](../../bench/safety_matrix/probes/158_launder_null_ref_tuple.zrl), and the dereference routes by [`181_gap_raw_deref_after_tuple`](../../bench/safety_matrix/probes/181_gap_raw_deref_after_tuple.zrl), [`182_gap_raw_deref_after_generic_struct_field`](../../bench/safety_matrix/probes/182_gap_raw_deref_after_generic_struct_field.zrl), [`183_gap_raw_deref_after_array`](../../bench/safety_matrix/probes/183_gap_raw_deref_after_array.zrl), [`184_gap_raw_deref_after_generic`](../../bench/safety_matrix/probes/184_gap_raw_deref_after_generic.zrl), [`185_gap_raw_deref_after_closure`](../../bench/safety_matrix/probes/185_gap_raw_deref_after_closure.zrl); every one of them is `compile_reject`. No row of the matrix is marked **GAP**; the holes still open are the `known_gap` probes under [Known gaps](#known-gaps).

### 5.8 Implicit Conversions

Two matchers decide whether a value of one type may be used where another is expected, and the safety boundary is the first. `types_match_internal` (`src/lower_zir/utils.zrl`) runs in the ZIR checker, before anything is lowered, so a pair it refuses is a located compile error the programmer sees. The second is the driver's `types_match` (`src/driver/state.zrl`), which decides whether the IL it has been handed is internally consistent while it is emitted; it runs _after_ the checker, so its leniency cannot make a program the checker refused compile - it can only let the emitter bridge a mismatch the checker already allowed, and a mismatch it does not bridge would be a miscompile rather than a hole.

Every pair either matcher accepts is listed below with its justification. The pairs marked _removed_ are refused; each has a test in `tests/error_reporting/` that pins the refusal and a valid twin that pins the direction that stays, so the direction of each relationship is a decision with a test rather than an artifact of a numeric range. This list is what the guarantee statement above cites for "implicit conversions".

- **1**
  - Pair accepted: a type with itself
  - Matcher: both
  - Justification: The same type
  - Disposition: Kept
- **2**
  - Pair accepted: an unknown type with anything
  - Matcher: both
  - Justification: An unresolved type is an inference placeholder, not a value: both matchers treat it as "not decided yet" so a partially-inferred program can be checked.
  - Disposition: Kept, narrowing
- **3**
  - Pair accepted: `unit` with `unit`
  - Matcher: both
  - Justification: The same type; spelled through `is_unit_type`, which also covers the "no result" case
  - Disposition: Kept
- **4**
  - Pair accepted: an aggregate or `fn` type with a pointer to it, at depth 0 only
  - Matcher: both
  - Justification: The IL passes aggregates by reference while the surface language passes them by value, so `S` in a signature and `*S` in the SSA are the same thing. Neither matcher lets a _dereference_ through, which §5.1 decides from the pointer's type
  - Disposition: Kept
- **5**
  - Pair accepted: `&mut T` where `&T` is expected
  - Matcher: both
  - Justification: A callee that only reads through a shared reference is satisfied by a mutable one; this direction takes capability away
  - Disposition: Kept; pinned by `tests/language/memory/pointer_mutability_direction.zrl`
- **6**
  - Pair accepted: `&T` where `&mut T` is expected
  - Matcher: checker
  - Justification: Unsound if accepted: the callee writes through a handle its caller only lent for reading. No program in this tree needs it
  - Disposition: **Removed**: `tests/error_reporting/err_shared_ref_for_mut_param.zrl`
- **7**
  - Pair accepted: `*mut T` where `*T` is expected
  - Matcher: both
  - Justification: The raw twin of row 5, and the same argument: a callee that will not write is satisfied by a pointer that may
  - Disposition: Kept; pinned by `tests/language/memory/pointer_mutability_direction.zrl`
- **8**
  - Pair accepted: `*T` where `*mut T` is expected
  - Matcher: checker
  - Justification: Unsound if accepted: it hands write access through a pointer that was not created for writing, which is a `*T` written through as `*mut T` without a cast. The compiler's own sites make the type say what it is (`mmap_or_trap` returns the mapping it hands out; `target_tuple_types` only reads); a program that needs the conversion writes the cast
  - Disposition: **Removed**: `tests/error_reporting/err_shared_raw_for_mut_param.zrl`
- **9**
  - Pair accepted: `BoxMut<T>` where `Box<T>` is expected
  - Matcher: checker
  - Justification: Row 5's argument for the owning pair
  - Disposition: Kept; pinned by `tests/language/memory/pointer_mutability_direction.zrl`
- **10**
  - Pair accepted: `Box<T>` where `BoxMut<T>` is expected
  - Matcher: checker
  - Justification: Row 6's argument for the owning pair
  - Disposition: **Removed**: `tests/error_reporting/err_shared_box_for_mut_param.zrl`
- **11**
  - Pair accepted: `&T` where `*T` is expected
  - Matcher: both
  - Justification: A reference may be used where a raw pointer is expected, and the call site then needs `unsafe` (the raw-argument rule of §5.1), so the direction only _adds_ a requirement. Both mutability combinations are accepted, which is what `zilc`'s `current_func` field relies on
  - Disposition: Kept
- **12**
  - Pair accepted: `*T` where `&T` is expected
  - Matcher: neither
  - Justification: A raw pointer must not become a reference without `unsafe`. Probe `bench/safety_matrix/probes/125_raw_pointer_to_reference_through_generic.zrl` and its siblings pin the refusal
  - Disposition: Refused by design
- **13**
  - Pair accepted: `Box<T>` with `&T` or with `*T`
  - Matcher: neither
  - Justification: Three different things to hand a callee: a `&T` in a `Box<T>` parameter would make the callee the owner of memory it was only lent, and a `Box<T>` in a `&T` parameter would move the box into the call. `tests/error_reporting/err_box_borrow_passed_as_owned.zrl` pins one direction and `err_box_moved_into_borrow.zrl` the other
  - Disposition: Refused by design
- **14**
  - Pair accepted: same-size primitive types, both floats or both non-floats, non-bools and non-chars
  - Matcher: checker
  - Justification: A sign change (`i32` to `u32`) is the same bits. A float never matches an integer or a bool, which is why the float and bool predicates are part of the test: `let j: i32 = f` would store the float's bits. The char predicate is the third: `char` and `u32` are both four bytes, and `let c: char = n` put a number into a char that neither the type nor the type checker held to a Unicode scalar value, probe 250
  - Disposition: Kept; `bench/safety_matrix/probes/37_implicit_narrowing.zrl` pins the narrowing side
- **15**
  - Pair accepted: same-size primitive types, any pair
  - Matcher: driver
  - Justification: Looser than row 14 on purpose: by the time the driver runs, the checker has decided, and this test only asks whether the value it is emitting can be moved without a conversion
  - Disposition: Kept as an emission allowance
- **16**
  - Pair accepted: a mutable slice where a shared slice is expected
  - Matcher: both
  - Justification: Row 5's argument
  - Disposition: Kept
- **17**
  - Pair accepted: a shared slice where a mutable slice is expected
  - Matcher: neither
  - Justification: Row 6's argument; refused by the mutability test inside the slice arm
  - Disposition: Refused by design
- **18**
  - Pair accepted: two array types of the same length with matching elements
  - Matcher: both
  - Justification: Structural equality, with the element rule applied recursively
  - Disposition: Kept
- **19**
  - Pair accepted: two `fn` types of the same arity, with matching results and parameters that match the other way round
  - Matcher: both
  - Justification: The results are compared in the direction of rows 5 and 6; the parameters in the opposite one (contravariance), because a function that takes `&i32` can stand for one that takes `&mut i32` and never the reverse: the `fn(&mut T)` accepted where a `fn(&T)` was expected (and the `fn(&T)` where a `fn(*T)` was) was rows 6 and 12 wearing a function type, and the removal in row 6 closed it with no separate rule
  - Disposition: Kept
- **20**
  - Pair accepted: two nominal (`user`) types with a common origin or the same mangled name, and matching type arguments
  - Matcher: both
  - Justification: The type is the same declaration after monomorphization; the name check covers instantiations that share no origin record
  - Disposition: Kept
- **21**
  - Pair accepted: a `unit` type argument against a plain-number one, and a generic type named with no arguments against an instance whose arguments are all plain numbers
  - Matcher: checker
  - Justification: `()` is what an argument nothing inferred defaults to (`box List.Nil` inside a `List<i32>`). It stands for a number and for nothing that holds an address: `W<()>` as `W<&i32>` read a reference out of nothing, probe 245
  - Disposition: Narrowed; **`W<()>` for `W<&i32>` removed**
- **23**
  - Pair accepted: what a writable handle points at, converted in either direction
  - Matcher: checker
  - Justification: `&mut &T` as `&mut *T` stored a raw pointer into the caller's reference, and `&mut &mut T` as `&mut &T` aimed a mutable reference at a shared place; behind `&mut`, `*mut`, `BoxMut` or `[mut T]` the types must be the same (`Box` and `BoxMut` count as one), probes 241 and 242
  - Disposition: **Removed**
- **24**
  - Pair accepted: a value of another type put into an array element, a repeat or an enum payload
  - Matcher: checker
  - Justification: These sites cast the value to the expected type without a check; they convert as an argument does (`convert_value_to`) or report a mismatch, probes 246 and 247
  - Disposition: **Removed**
- **25**
  - Pair accepted: a `char` and a same-size integer, in either direction
  - Matcher: checker
  - Justification: `char` is four bytes and `u32` is four bytes, so a number stood in for a char and a char for a number: the first let checked code hold a surrogate or a point above U+10FFFF, which no `char` may be. A `u8` still stands for a `char` (every byte is a scalar value, and that is what a char literal is typed as), and `c as u32` is the explicit way back, probe 249
  - Disposition: **Removed**: `tests/error_reporting/err_char_from_u32.zrl`
- **22**
  - Pair accepted: a reference, raw pointer and box with each other
  - Matcher: neither
  - Justification: Row 13
  - Disposition: Refused by design

The `as` conversions are the explicit half of this list and are deliberately wider:

- `&T as *T` and its mutable twins stay safe, `0 as *T` stays safe, and `n as *T` for **any** integer `n` stays safe (the same argument for every integer is what gives a fixed hardware address a spelling in a `static`). Creating a raw pointer or re-typing one cannot do harm by itself: every _use_ of a raw pointer - dereference, field access, index, and passing it where a reference is expected - needs `unsafe` because the type says it is raw, so gating creation would add an `unsafe` block to checked code and buy nothing. The same decision covers the intrinsics: `@ptr_from_int<*T>`, `@ptr_cast<*T>` and `@int_cast<U>` are safe, while `@ptr_cast<&T>` / `@ptr_from_int<&T>` / `@ptr_cast<[T]>` stay gated (`ptr_forge_needs_unsafe`).
- `&x as *T` does not carry `x`'s borrow. A raw pointer is the language's escape hatch from lifetime tracking, and its dangling uses happen inside `unsafe`, where the programmer has taken responsibility. Carrying the borrow would make the escape hatch leak into checked code's obligations without catching the dangling pointer, which is a use the `unsafe` block already covers.
- `*T` to `&T` is not a cast: it is `&*p` inside `unsafe`, which is where the null check and the lifetime obligation become the programmer's, as in Rust.
