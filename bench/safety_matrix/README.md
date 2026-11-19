# Zoril Safety Verification Ledger

This ledger holds the machine-checked safety verification summaries, open `known_gap` probe inventory, trusted-base census, `unsafe` marker-density calibration, and ZIR/ZIL route reachability audit for Zoril. Normative rules and architectural definitions live in [`doc/spec/safety_model.md`](../../doc/spec/safety_model.md) and [`doc/spec/unsafe_policy.md`](../../doc/spec/unsafe_policy.md); the user-facing safety guide is [`doc/SAFETY.md`](../../doc/SAFETY.md), and the full per-row probe table is [`matrix.md`](matrix.md).

---

## 1. Snapshot and Probe Counts

The counts in this ledger and the marker-density rows below are as of **0.1.0-alpha-172-g9e79c80** (2026-11-15); they are refreshed at milestones (`scripts/check_safety_figures.sh --milestone`).

The repository keeps 529 probes in [`probes/`](probes) for the 79-row safety matrix (making up the 529-probe safety matrix), each recording its expectation in its first lines: **382 `compile_reject`**, **76 `accept`**, **8 `runtime_trap`**, **11 `runtime_fault`**, and **52 `known_gap`**. `scripts/run_safety_matrix.sh` runs all of them and fails when an observation differs from the recorded expectation; `make test` gates it (`safety-matrix`) together with `safety-model` (`scripts/check_safety_model.sh`), which keeps this ledger, [`matrix.md`](matrix.md), and the probes consistent in both directions.

In differential fuzzing against `rustc`, the shorter `--release` session on this codebase compiled and ran **755,772** programs across both whole-program and `zbuild` builds (following the **2,638,155** release-bar run on the previous code; see [`bench/fuzz/README.md`](../fuzz/README.md)).

---

## 2. Safety Properties Matrix Summary

Each property is one entry: the claim, which side of the `unsafe` boundary it is on, how strong its evidence is, and how many probes and tests prove it. The full table (mechanism, compiler level, boundary, the probe links and the routes) is [bench/safety_matrix/matrix.md](matrix.md); `scripts/check_safety_model.sh` fails when an entry here differs from its row there.

- **Intra-procedural Arena Analysis** (surface_syntax.md §11.2.1): Constant-size allocations do not exceed constant-size arena capacities within a function [side: safe; evidence: example; probes: 2](matrix.md)
- **Inter-procedural Arena Propagation** (surface_syntax.md §11.2.2): Allocation requirements propagate across function calls to verify arena safety across boundaries [side: safe; evidence: example; probes: 1](matrix.md)
- **Array Length Fits**: A declared array length and an array repeat count that do not fit in 32 bits are compile errors, so the type an array has is the length the program wrote [side: safe; evidence: example; probes: 4](matrix.md)
- **Type Size Fits**: A type whose size exceeds `isize::MAX` is a compile error, so a size never wraps and an in-bounds element address cannot leave the signed 64-bit range [side: safe; evidence: example; probes: 4](matrix.md)
- **Array Bounds Check (Read)** (surface_syntax.md §11.2.3): Out-of-bounds read on fixed-size array traps with exit code 134; an index written as a constant is rejected at compile time [side: safe; evidence: example; probes: 2](matrix.md)
- **Array Bounds Check (Write)** (surface_syntax.md §11.2.3): Out-of-bounds write to fixed-size array traps with exit code 134; an index written as a constant is rejected at compile time [side: safe; evidence: example; probes: 2](matrix.md)
- **Slice Bounds Check (Read)** (surface_syntax.md §11.2.3): Out-of-bounds read on slice traps with exit code 134 [side: safe; evidence: example; probes: 1](matrix.md)
- **Slice Bounds Check (Write)** (surface_syntax.md §11.2.3): Out-of-bounds write to slice traps with exit code 134 [side: safe; evidence: example; probes: 1](matrix.md)
- **Raw-Pointer Indexing** (surface_syntax.md §11.2.3): Indexing a raw pointer (`*T`, `*mut T`) is unchecked, and reachable only through `unsafe`, whether read (`p[i]`) or borrowed (`&p[i]`) [side: unsafe; evidence: example; probes: 3](matrix.md)
- **Indexing Through a Reference** (surface_syntax.md §11.2.3): A reference is indexed as what it refers to: `&[T; N]`, `&[T]` and `&Vec<T>` index the array, slice or vector (bounds-checked as above); a reference to anything else cannot be indexed, so `x[1]` with `x: &u32` is rejected rather than read past `x` [side: safe; evidence: example; probes: 3](matrix.md)
- **Region Escape: Direct Return** (surface_syntax.md §11.2.4): Returning address of local stack variable is rejected at compile time [side: safe; evidence: example; probes: 1](matrix.md)
- **Region Escape: Return via Cast / Ops** (surface_syntax.md §11.2.4): Returning local stack pointer behind casts, moves, or pointer arithmetic is rejected [side: safe; evidence: example; probes: 1](matrix.md)
- **Region Escape: Through Locals and Aggregates** (surface_syntax.md §11.2.4): A stack address held in a local, or in a struct, tuple or slice (including a slice over a local array), cannot be returned [side: safe; evidence: example; probes: 7](matrix.md)
- **Region Escape: Stored Outside the Frame** (surface_syntax.md §11.2.4): A stack address cannot be written to memory that outlives the function: through a pointer parameter, into a global, or into a heap allocation [side: safe; evidence: example; probes: 51](matrix.md)
- **Region Escape: Through a Call** (surface_syntax.md §11.2.4): A stack pointer passed to a function cannot come back out of the frame through it: not handed back (`return stash(&mut s)` dangles like `return &mut s`), and not stored by the callee into memory that outlives the frame (`put(h, &x)` with `fn put(h: &mut H, p: &i32) { h.r = p; }`, or into a global) [side: safe; evidence: example; probes: 7](matrix.md)
- **Region Escape: Reference Returned Through a Call** (surface_syntax.md §11.2.4): A reference into a local's own storage, obtained through a call (`let c = C {..}; return c.get();`), is not returned, whether as `&T`, `Option<&T>` or a struct or slice holding it; nor a reference into a local array obtained through a slice argument (`first(&a)`) [side: safe; evidence: example; probes: 30](matrix.md)
- **Region Escape: Reference into an Owned Box Dropped at Return** (surface_syntax.md §11.2.4): An address derived through a `Box` the function owns and drops (a local box, a by-value parameter, or reached through one by field steps) cannot be returned as a reference or stored where it outlives the function [side: safe; evidence: example; probes: 7](matrix.md)
- **Use After Move (Linear/Owned)** (surface_syntax.md §7.1): Accessing a moved non-`Copy` value (e.g. `Box<T>`) is rejected at compile time; assignment through a moved base (dereference of a moved `Box`, field write through a moved struct that owns storage, write through moved `&mut`) is rejected; reading a value that is not `Copy` by value out of an array or slice element (`let v = a[0];`) is rejected, since the array or slice still holds it [side: safe; evidence: example; probes: 16](matrix.md)
- **Use After Move (Copy/POD)** (surface_syntax.md §7.1): Primitive and structurally Copy values remain usable after assignment [side: safe; evidence: example; probes: 15](matrix.md)
- **Double Drop** (surface_syntax.md §7.3, §8.4): Dropping an already-dropped or unowned value via `@drop` is rejected [side: safe; evidence: example; probes: 13](matrix.md)
- **Drop Exactly Once** (surface_syntax.md §7.3, §8.4): Values that need dropping are dropped exactly once on every path: scope exit, early return, loop break, reassignment, and after a move that happens on only some paths; a by-value parameter is dropped by the callee; a value owned by an aggregate (struct field, enum payload of the active variant, tuple or array element) is dropped when the aggregate is, after the aggregate's own `drop` if it has one. A value is dropped with its own type's `drop`, never that of another module's type of the same name. Moving a field that needs dropping out of a value (`let x = w.d;`) is rejected, since partial moves are not tracked per field; so is reading such a value by value out of an array or slice element (`let s = a[0];`); so is `[v; n]` with n > 1 for such a `v`, and moving a non-`Copy` field or payload out of an enum or struct that implements `Drop` (`match d { D.A(s) => {} }`), and assigning to, mutably borrowing, moving or dropping the scrutinee inside a match guard [side: safe; evidence: example; probes: 14](matrix.md)
- **Defer Use After Move** (surface_syntax.md §7.1, §8.4): A `defer` statement cannot use a value that has already been moved, nor can a value used by a `defer` be moved subsequently on any path [side: safe; evidence: example; probes: 2](matrix.md)
- **Use After Drop** (surface_syntax.md §7.3, §8.4): Accessing a variable after `@drop` is rejected at compile time [side: safe / unsafe alias; evidence: example; probes: 2](matrix.md)
- **Move Out of a Borrow** (surface_syntax.md §7.1, §7.2): A non-`Copy` value cannot be moved out through a reference (`return b.r` with `b: &B`): the owner would still drop it [side: safe; evidence: example; probes: 2](matrix.md)
- **Borrow Aliasing (Exclusive Mutable)** (surface_syntax.md §7.2): Mutable borrow `&mut x` forbids simultaneous active borrows of same place; pattern bindings through a reference (`if let`, `match`, `while let` on `&e`, or on `e` with `e: &mut E`) keep the matched enum borrowed; projected reborrows (`&r.f`) inherit the base reference's borrows; propagating borrows preserves all borrows a value holds; strict reborrowing tracks views through reference variables, so a view through `&mut` keeps the referent borrowed across mutations and `&mut` cannot be copied [side: safe; evidence: routes; probes: 39](matrix.md)
- **Borrow Aliasing: Returned References** (surface_syntax.md §7.2): A value returned by a call that can hold a reference (a reference, slice, `Option<&T>`, or struct holding one) keeps borrowed what its arguments borrow, while the value is live: `c.get()` then `c.set(..)`, `v.get(i)` / `v.as_slice()` kept across `v.push(..)`, or generic `Option.unwrap()` unwrapping a borrowed reference, are rejected [side: safe; evidence: routes; probes: 11](matrix.md)
- **Slice Forging (`@slice`)** (surface_syntax.md §3.5): `@slice(ptr, len)` requires `unsafe` (unless `len` is a literal 0), whether `ptr` is a raw pointer or a reference: the length is what nothing checks [side: safe; evidence: example; probes: 2](matrix.md)
- **Read-Only Slices** (surface_syntax.md §3.5): A `[T]` is a read-only view: its elements can be written only through a `[mut T]`. `&a` gives a `[T]`, `&mut a` a `[mut T]`; a string literal and `Vec.as_slice()` are `[T]`. A `[mut T]` converts to a `[T]`, never the reverse [side: safe; evidence: example; probes: 6](matrix.md)
- **Linear Resource Leakage** (surface_syntax.md §7.1): Linear types (`fd`, `ioring`) cannot be implicitly dropped: not directly, not inside a struct, tuple, enum, array or box, not by an early return, and not on one path of a branch; nor duplicated or closed twice [side: safe; evidence: example; probes: 11](matrix.md)
- **File Descriptor Capabilities** (surface_syntax.md §3.12, §9.4): An `fd<r>` cannot be written through, an `fd<w>` cannot be read through, and a capability cannot be widened or forged [side: safe; evidence: example; probes: 5](matrix.md)
- **Integer Overflow (Wrapping)**: Arithmetic overflow wraps modulo $2^N$ by design [side: safe; evidence: example; probes: 1](matrix.md)
- **Pointer Forgery (Raw Pointers)**: A pointer forged from an integer is unchecked _when it is used_: the dereference or the conversion to a reference is what is gated (each on the pointer's own type), while the creation itself is safe [side: unsafe; evidence: example; probes: 9](matrix.md)
- **Null Dereference** (surface_syntax.md §11.2.5): A reference obtained without `unsafe` is non-null. `0 as &T` and generic `(0 as u64) as T` are rejected outright; forging one from a null raw pointer (`let r: &T = &*p;`) is a compile error unless it is inside `unsafe { }`, where it remains unchecked and faults [side: unsafe; evidence: example; probes: 2](matrix.md)
- **Implicit Raw-Pointer Dereference**: `p.field`, `p.0` and `p.method()` on a raw pointer dereference it as `(*p).field` does, and are reachable only through `unsafe`; a slice's `.ptr` is a raw pointer like any other [side: unsafe; evidence: example; probes: 6](matrix.md)
- **System Call**: `@syscall` reaches the kernel with integers it treats as addresses (`read`, `mmap`, `munmap` write or unmap any memory), and is reachable only through `unsafe` [side: unsafe; evidence: example; probes: 3](matrix.md)
- **Extern Function Call**: Calling an `extern` function is unchecked, and reachable only through `unsafe` [side: unsafe; evidence: example; probes: 3](matrix.md)
- **Extern Signature Types**: An `extern` signature carries only what C can take: `bool`, the sized integers, `usize`/`isize`, the floats and raw pointers. A struct by value, a slice, a reference, a `Box`, a tuple, an array, an enum, a `char` or a `fn` value is a compile error that names the type and what to pass instead [side: safe; evidence: example; probes: 6](matrix.md)
- **C Function Pointers**: A C function pointer (`extern "C" fn(..)`) is a code address from an `extern "C" fn` or from C, never a number or a Zoril function value, and calling one is unchecked, so it needs `unsafe` [side: safe; evidence: example; probes: 5](matrix.md)
- **Implicit Conversions Are Exact Behind a Mutable Handle**: What a `&mut`, `*mut`, `BoxMut` or `[mut T]` points at must be the same type, not a convertible one; function parameters are compared in the opposite direction from results; `()` stands for nothing but a plain number; and a value put into an array element or an enum payload converts as an argument would, or is a mismatch [side: safe; evidence: example; probes: 10](matrix.md)
- **Uninitialized Stack Slot**: `@alloca<T>(1)` returns a `&mut T` to a slot nothing has written; reading it before a write reads a stale value (a wild pointer when `T` is a reference), so it is reachable only through `unsafe` [side: unsafe; evidence: example; probes: 3](matrix.md)
- **Raw Pointer Converted to a Reference**: A raw pointer used where a reference is expected becomes that reference, the same forge as `&*p`, and is reachable only through `unsafe`: as an argument, a `let` with a declared type, an assignment, a `return` or tail result, and a struct field [side: unsafe; evidence: example; probes: 9](matrix.md)
- **Raw Pointer Returned by a Function Call**: A raw pointer returned by a function call (`*mut T` or `*T`) retains its raw status, and dereferencing or writing through it is reachable only through `unsafe`: `let p = f(); *p` and `*f() = v` require `unsafe` [side: unsafe; evidence: example; probes: 3](matrix.md)
- **Raw Pointer Converted to a Reference Through a Type Parameter**: A raw pointer passed as a type parameter and coming back as a reference (`let r: &T = id(p);`, `Vec::<&T>.push(p)`, `Option.Some(p)` for an `Option<&T>`) needs `unsafe` [side: safe; evidence: example; probes: 2](matrix.md)
- **Raw Pointer Laundered Through an Aggregate or Binding**: A raw pointer passed through an aggregate (tuple, struct, array, enum) or a pattern binding retains its raw status, so dereferencing it or converting it to a reference needs `unsafe` [side: safe; evidence: example; probes: 9](matrix.md)
- **Raw Pointer Dereferenced After a Container or a Generic or a Closure**: A dereference, a field access or an index through a raw pointer should require `unsafe` even when the pointer arrived through a container, a generic instantiation or a closure capture [side: safe; evidence: example; probes: 5](matrix.md)
- **Safe Function Dereferencing a Raw Pointer Argument**: A function that dereferences a raw pointer it is given requires `unsafe` at the call site, as an `unsafe fn` does in Rust [side: safe; evidence: example; probes: 7](matrix.md)
- **Stdlib `unsafe` Interiors**: Every `unsafe` block in `stdlib/` trusts an invariant the type system does not check - a length that matches its allocation, an index that fits, a pointer that is live, arithmetic that cannot wrap - and checked code must not be able to break one [side: safe; evidence: example; probes: 9](matrix.md)
- **Arena Use After Reset or Free** (surface_syntax.md §11.2.1): A value allocated in an arena cannot be used once `reset`, `reset_to` or `arena_free` releases its memory [side: safe; evidence: routes; probes: 31](matrix.md)
- **Encapsulation (Private Methods)** (surface_syntax.md §11.1.1, §11.1.2): A method, associated function or associated constant that is not `pub` is nameable only from the module that declares its `impl`, so another module cannot reach a private invariant keeper (`c.bump()`, `Widget.SECRET`) [side: safe; evidence: example; probes: 4](matrix.md)
- **Region Escape: Borrowed Value Dropped at Block End** (surface_syntax.md §7.2): A value leaving scope while something that outlives that scope still borrows it is rejected ("cannot let 'x' go out of scope while it is still borrowed"), not only when a reference escapes the function [side: safe; evidence: routes; probes: 22](matrix.md)
- **Data Races**: Not applicable [side: n/a; evidence: n/a; probes: n/a](matrix.md)
- **Uninitialized Local Read**: A local cannot be read before it is written [side: safe; evidence: example; probes: 1](matrix.md)
- **Division by Zero**: Integer division by zero faults deterministically rather than producing a value [side: safe; evidence: example; probes: 2](matrix.md)
- **Signed Division Overflow**: `INT_MIN / -1` faults rather than wrapping [side: safe; evidence: example; probes: 1](matrix.md)
- **Shift Overflow** (surface_syntax.md §11.2.6): A shift count must be in `[0, width)` of the shifted type [side: safe; evidence: example; probes: 5](matrix.md)
- **Narrowing Cast Truncation** (surface_syntax.md §11.2.6): A conversion that drops bits cannot happen implicitly; `as` is required and still truncates silently [side: safe; evidence: example; probes: 2](matrix.md)
- **Invalid Enum Discriminant**: Casting an integer to an enum type is rejected at compile time; enum values must be constructed via variant constructors [side: safe / unsafe alias; evidence: example; probes: 2](matrix.md)
- **Variant Reassignment Under a Payload Binding** (surface_syntax.md §5.3): Reassigning an enum to another variant while a payload binding is live cannot reinterpret the payload [side: safe; evidence: example; probes: 2](matrix.md)
- **Mutable Statics Hold No References** (surface_syntax.md §11.2.4): A `static mut` cannot have a reference or slice type, or a struct type with a reference field: anything stored in it would outlive what it borrows [side: safe; evidence: example; probes: 8](matrix.md)
- **Non-Scalar `static mut` Access Is Unsafe**: A `static mut` whose type is not a scalar (an integer, a float, `bool`, `char` or a raw pointer) may be read, written or borrowed only inside `unsafe`: a write can retype the place, and the borrow checker does not track borrows of statics across it [side: safe; evidence: example; probes: 9](matrix.md)
- **Immutable Static Assignment**: An immutable `static` variable cannot be assigned to or mutably borrowed [side: safe; evidence: example; probes: 2](matrix.md)
- **Trait Bound Enforcement** (surface_syntax.md §3.11): A generic instantiation must satisfy every trait bound, including bounds reached through nested generic impls [side: safe; evidence: example; probes: 2](matrix.md)
- **Missing Return**: Control falling off the end of a non-unit function without returning a value is rejected at compile time [side: safe; evidence: example; probes: 1](matrix.md)
- **Unaligned Access**: Unaligned loads/stores are unchecked, and reachable only through `unsafe` [side: unsafe; evidence: example; probes: 1](matrix.md)
- **Stack Exhaustion** (surface_syntax.md §11.2.7): Unbounded recursion faults without a diagnosable guard [side: safe; evidence: example; probes: 1](matrix.md)
- **Sub-word Arithmetic Width** (surface_syntax.md §11.2.6): A `u8`/`u16`/`i8`/`i16` result stays inside its declared type, as a temporary and when stored [side: safe; evidence: example; probes: 2](matrix.md)
- **Null Function Pointer Call** (surface_syntax.md §11.2.5): A function pointer obtained without `unsafe` is non-null. `0 as fn(...)` is rejected outright; loading one out of a zeroed aggregate through a raw pointer (`(*v).call`) is a compile error unless it is inside `unsafe { }`, where it remains unchecked and faults on call [side: unsafe; evidence: example; probes: 1](matrix.md)
- **Generic Integer-to-Reference Cast**: References cannot be created null by direct integer cast (`0 as &T` is rejected), and generic casts (`(0 as u64) as T`, `0 as T::Out`, `p as T` from a raw pointer) are rejected at compile time [side: safe; evidence: example; probes: 6](matrix.md)
- **Value Forged by Cast**: `as` cannot make a slice, array, tuple, struct, enum or box out of another type, nor add `mut` to a slice, nor make a `bool` or a `char` out of a number in checked code [side: safe; evidence: example; probes: 23](matrix.md)
- **Associated Type Confusion**: An associated type (`T::Out`) cannot launder a reference past the escape check, nor make a value of one type be read as another [side: safe; evidence: example; probes: 5](matrix.md)
- **Method of Another Instance**: A method of an impl for one instance of a generic type (`impl W<&i32>`) cannot be called on another (`W<i64>`), so its `self` never reads one instance's value as another's [side: safe; evidence: example; probes: 4](matrix.md)
- **Dereference of a Non-Pointer**: `*e` follows an address only: `e` must be a reference, raw pointer or box [side: safe; evidence: example; probes: 2](matrix.md)
- **Early Return Through `?`**: `e?` returns early a value of the enclosing function's return type: `e` itself when it has that type or refers to a value of it, else a fresh value holding `e`'s `Err` payload (or its `None`); any other `e?` is a compile error [side: safe; evidence: example; probes: 15](matrix.md)
- **Type Confusion (raw pointer cast)**: Reinterpreting one struct as another via raw pointer cast is unchecked, and reachable only through `unsafe` [side: unsafe; evidence: example; probes: 1](matrix.md)
- **Immutability Enforcement**: A non-`mut` binding cannot be reassigned or mutably borrowed; bindings are immutable by default. `&T` (and non-mut `*T`, which erases to the same IL tag) is read-only: assigning through it, calling a `&mut self` method through it, or passing it where a callee expects `&mut T`/`*mut T` is rejected, whether the `&T` is a locally-initialized `let`, a parameter, a struct field, a returned reference, or an `IndexAddr` place [side: safe; evidence: example; probes: 11](matrix.md)
- **Capturing Closure Escape** (surface_syntax.md §5.2): A capturing closure is never called without its environment, and its environment (in the frame that made it) is never reached after that frame returns [side: safe; evidence: routes; probes: 13](matrix.md)
- **Closure Capture by Reference** (surface_syntax.md §5.2): A closure capturing a reference to a place keeps that place borrowed for the closure's lifetime, rejecting mutation or variant reassignment while the closure is live [side: safe; evidence: routes; probes: 4](matrix.md)
- **Or-Pattern Binding Type**: A name bound in several alternatives of an or-pattern has one type: every alternative must bind it with exactly that type [side: safe; evidence: example; probes: 2](matrix.md)
- **Slice Header Integrity**: A slice-typed place (`[T]`) only ever holds a real `{ptr, len}` header: an array value `[T; N]` is not implicitly accepted where a slice is expected, in `let`, call arguments, struct literals or assignment [side: safe; evidence: example; probes: 3](matrix.md)

### Routes: what each row's evidence walks

The `routes` evidence level means a row's probes were checked against the compiler constructs its mechanism depends on, not only against the shapes someone thought of. The route lists, the vocabulary and how `scripts/check_route_coverage.sh` checks them are in [bench/safety_matrix/matrix.md](matrix.md).

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

No row above is marked **GAP** today. That does not mean no hole is open: the holes still open in checked code are routes inside rows the matrix counts as closed, and each is a `known_gap` probe listed under [Known gaps](#known-gaps).

Every program that showed a hole in one of the rows is kept as a `compile_reject` probe (or, for the two drop-count probes, an `accept` that asserts one drop), so the hole cannot reopen unnoticed.

A **GAP** row is a hole in checked code: the compiler accepts something the safety model says it should not, or produces a platform-dependent result. Each is pinned by a `known_gap` probe, listed under [Known gaps](#known-gaps) below, which `make test` reports as a skip until the gap is closed.

**The practice this document follows: a GAP row closes only when all three of these hold.**

1. **Its motivating probes no longer build.** Every exploit that opened the row has been re-run unchanged and no longer builds (or, for a drop-count probe, no longer shows the unsafe behaviour). Those programs become `compile_reject` tests with located errors, and they stay as the evidence.
2. **It reaches the `routes` evidence level.** The row's `Routes` list names every construct its mechanism depends on, and `scripts/check_route_coverage.sh` shows that each is walked by a cited probe. A fix that closes the one exploit someone wrote down while another construct in the same class stays unprobed has not closed the row.
3. **The mutations that disable its mechanism are killed by its own probes.** The row lists the mutation IDs that target its mechanism (for example M21, M22, M37) in its text; `scripts/mutation-check.sh --row '<row name>'` runs exactly those mutations against exactly the probes and tests the row cites, and each one must be caught. A mutation that survives means the row's evidence does not reach the mechanism the row claims.

**Raw pointers in checked code.** Checked code can create a raw pointer (`0 as *mut T`, `&x as *T`) but cannot use one: every dereference, field access and index through it requires `unsafe`. The pointer keeps its raw type through tuples, structs, arrays and enums, pattern bindings, generic calls and closure captures, so it cannot be passed through one of them and come out as a reference (probes [`158_launder_null_ref_tuple.zrl`](probes/158_launder_null_ref_tuple.zrl), [`152_launder_raw_ptr_match_binding.zrl`](probes/152_launder_raw_ptr_match_binding.zrl), [`125_raw_pointer_to_reference_through_generic.zrl`](probes/125_raw_pointer_to_reference_through_generic.zrl), [`154_launder_raw_ptr_closure.zrl`](probes/154_launder_raw_ptr_closure.zrl)). Creating one writes no memory, which is why it stays safe ([`doc/spec/unsafe_policy.md`](../../doc/spec/unsafe_policy.md) §1, probe [`187_int_to_raw_ptr_cast_safe.zrl`](probes/187_int_to_raw_ptr_cast_safe.zrl)).

**A raw pointer value may dangle.** A raw pointer in checked code carries no promise that what it points to is live. What is checked is the address the value carries: a raw pointer holding an address of the frame may not be returned or stored where it outlives the frame, as a reference may not (under `--provenance`, [`raw_roundtrip_frame_refused.zrl`](../../tests/language/memory/provenance/raw_roundtrip_frame_refused.zrl), [`raw_ptr_to_frame_from_by_value_owner_refused.zrl`](../../tests/language/memory/provenance/raw_ptr_to_frame_from_by_value_owner_refused.zrl)), and every dereference needs `unsafe`. What is not checked is the lifetime of the storage it points to: a raw pointer copied out of an owner whose `Drop` frees the block it points to (`fn keep(out: &mut *mut u8, b: Buf) { *out = b.data; }`), alone or beside an owned `Vec` in one struct, is accepted in every mode and dangles once the owner is dropped ([`raw_ptr_from_dropped_owner_accepted.zrl`](../../tests/language/memory/provenance/raw_ptr_from_dropped_owner_accepted.zrl), [`raw_ptr_in_owner_from_dropped_owner_accepted.zrl`](../../tests/language/memory/provenance/raw_ptr_in_owner_from_dropped_owner_accepted.zrl)). The checker cannot know that an owner owns what its raw pointer field points to; the `unsafe` block that reads through the pointer is where the programmer checks that the storage is still there ([`doc/spec/unsafe_policy.md`](../../doc/spec/unsafe_policy.md) §1).

A GAP row is what a _decided_ check misses. What a check does when it cannot decide at all is the other half of the picture, and every place a checker could answer "unknown" (the ZIR checker, the ZIL verifier, the summary passes and the lowering's raw-ness checks) was audited, and each is either unreachable or answers conservatively (rejects) - see [What Zoril Checks](../../doc/SAFETY.md) §4.4.

Several design points are worth stating directly:

- **Shift overflow:** constant shift counts are checked at compile time and variable ones trap. Masking to the hardware width is available explicitly as `@shl_wrap` / `@shr_wrap`.
- **Escape through a callee:** a function signature states what its result may point into (`#[borrows(..)]`, with Rust-like defaults), and borrows end at their last use. Whether a result points into an argument's own storage or into a buffer the argument references is decided by the callee's body (`ret_storage`, carried in `.zri`), since a signature cannot express it. Rust tells the two apart through ownership (dropping a `Vec` frees its buffer); with arenas, returning a slice of a local `Vec` is safe in Zoril, so the Rust rule would reject correct code.
- **Implicit conversions:** the conversion list under the route grid gives every pair of types the two matchers accept as equal or convertible, with the justification for each and the tests that pin it; the pairs that would not be sound - a shared handle where a mutable one is expected, in the reference, raw and box classes - are refused, and the conversions the language does allow (`&T as *T`, `0 as *T`, and `*T` to `&T` only as `&*p` inside `unsafe`) are listed there too.
- **Narrowing casts:** an implicit conversion that drops bits is rejected, and `as` is the required marker (probes [`37_implicit_narrowing.zrl`](probes/37_implicit_narrowing.zrl) and [`20_narrowing_cast.zrl`](probes/20_narrowing_cast.zrl) pin this from both sides, row `Narrowing Cast Truncation (§11.2.6)`).
- **Stack exhaustion:** accepted as-is (§11.2.7), a deterministic fault on the same footing as division by zero.
- **Raw-pointer operations** (null dereference, null function pointer call, unaligned access, forging a pointer from an integer _and using it_, type confusion, raw-pointer indexing) are reachable only inside an `unsafe` block, are unchecked there, and are pinned by probe pairs. The _creation_ of a raw pointer is not one of them (it is safe; see section 4.2), so what the pair pins is that the use is refused.

### Known gaps

Every probe in `bench/safety_matrix/probes/` whose expectation is `known_gap` is listed here, and nothing else is; `scripts/check_safety_model.sh` enforces both directions. The safety matrix reports each as a skip while the compiler still accepts it and fails once it does not, so closing a gap means flipping its probe's expectation, removing its entry, and unmarking its row.

- **[`gap_07_path_same_param.zrl`](probes/gap_07_path_same_param.zrl)**: Storage walk and escape checks filter out i == j when same parameter carries dest and source
- **[`gap_53_same_param_struct_copy.zrl`](probes/gap_53_same_param_struct_copy.zrl)**: The same filter when the parameter is a struct of references (`R { x: &mut wa, y: &wb }`) through which the callee copies a frame view from one of the caller's locals into another, which the caller then stores out. Route class: one parameter carrying both the destination and the value
- **[`gap_11_dest_closure_capture_mut.zrl`](probes/gap_11_dest_closure_capture_mut.zrl)**: Closure storing through captured mutable reference not recognized as escaping frame
- **[`gap_13_ref_local_enum_payload.zrl`](probes/gap_13_ref_local_enum_payload.zrl)**: Storage facts drops provenance for stack reference carried in enum payload
- **[`gap_16_ref_local_fn_val.zrl`](probes/gap_16_ref_local_fn_val.zrl)**: Storage facts drops provenance for stack reference passed through fn value
- **[`gap_18_elem_ref_enum_payload.zrl`](probes/gap_18_elem_ref_enum_payload.zrl)**: Storage facts drops provenance for array/slice element reference in enum payload
- **[`gap_21_elem_ref_fn_val.zrl`](probes/gap_21_elem_ref_fn_val.zrl)**: Storage facts drops provenance for element reference passed through fn value
- **[`gap_23_closure_local_enum_payload.zrl`](probes/gap_23_closure_local_enum_payload.zrl)**: Storage facts drops provenance for stack-capturing closure in enum payload
- **[`gap_26_closure_local_fn_val.zrl`](probes/gap_26_closure_local_fn_val.zrl)**: Storage facts drops provenance for stack-capturing closure passed through fn value
- **[`gap_27_closure_local_param_65.zrl`](probes/gap_27_closure_local_param_65.zrl)**: Parameter bitmask overflow at index >= 64 drops closure provenance
- **[`gap_32_byval_collection_param_store.zrl`](probes/gap_32_byval_collection_param_store.zrl)**: By-value collection parameter treated as external instead of frame-owned storage
- **[`gap_62_byval_arena_param_vec_pushed.zrl`](probes/gap_62_byval_arena_param_vec_pushed.zrl)**: A `Vec` made in an `Arena` passed by value is pushed into the caller's `Vec`; the arena is freed when the callee returns, and the old rules read its storage as external, as `gap_32` does for a by-value `Vec`. Route class: the storage a by-value owning parameter owns, stored into caller memory
- **[`gap_33_param_65_arena_slice_store.zrl`](probes/gap_33_param_65_arena_slice_store.zrl)**: Parameter bitmask overflow at index >= 64 drops arena slice storage provenance
- **[`gap_36_carrier_ref_enum_payload_match.zrl`](probes/gap_36_carrier_ref_enum_payload_match.zrl)**: The summary pass does not follow a pointer into the frame through an enum payload bound in a match arm
- **[`gap_38_param_field_reset.zrl`](probes/gap_38_param_field_reset.zrl)**: The same store made by a callee through its `&mut` parameter. Route class: a store into a local's field or a Box's contents through a pointer to it, which `check_assign` skips (`place_writes_through_pointer`)
- **[`gap_39_method_self_field_reset.zrl`](probes/gap_39_method_self_field_reset.zrl)**: The same store made by a `&mut self` method through `self`. Route class: a store into a local's field or a Box's contents through a pointer to it, which `check_assign` skips (`place_writes_through_pointer`)
- **[`gap_41_callee_field_escape.zrl`](probes/gap_41_callee_field_escape.zrl)**: A slice of a Vec in this frame's arena, written into a local struct's field by a callee through its `&mut` parameter, is accepted and then stored out through `*out = w.s`. Route class: a store into a local's field or a Box's contents through a pointer to it
- **[`gap_45_closure_mutref_field_escape.zrl`](probes/gap_45_closure_mutref_field_escape.zrl)**: The same escape with the field written by a closure that captured a local `&mut` to the struct; the closure call's effect on the captured struct is not seen. Route class: a store into a local's field or a Box's contents through a pointer to it
- **[`gap_96_callee_stores_view_then_caller_frees.zrl`](probes/gap_96_callee_stores_view_then_caller_frees.zrl)**: A callee stores a view of one argument into another (`put(&mut s, &v)` with `fn put(out: &mut [i32], v: &Vec<i32>) { *out = v.as_slice(); }`), and the caller then frees the first (`kill(&mut v)`, a callee calling `v.free()`) and reads `s`: a call's store summary gives the stored view's borrow to no local of the caller, so the free does not conflict, and the caller reads the freed buffer (exit 77 where it held 42). `let s = v.as_slice(); v.free();` is refused. Accepted with and without `--provenance`. Route class: a store into a local or a Box's contents through a pointer to it, made by a callee, with the view made in the callee
- **[`gap_97_frame_view_read_through_local_ref_stored_out.zrl`](probes/gap_97_frame_view_read_through_local_ref_stored_out.zrl)**: A frame view read through a local reference to a local struct and stored out (`let s = S { v: &x }; let r = &s; *out = r.v;`): the default rules do not follow the read through `r` back to the view `s` holds, so `*out` keeps the dead frame's address (exit 77 where it held 42), while `*out = s.v` is refused. The same goes for a tuple slot (`r.0`), an array element (`r[0]`), a `&mut` or a reborrow in place of `r`, a copy of `r.v` stored later, a reference to `r`, returning `r.v`, and a callee storing `s.v` through its reference parameter. Refused under `--provenance`. Route class: a frame view read through a pointer to a local aggregate, stored out or returned
- **[`gap_98_frame_view_in_by_value_aggregate_stored_by_callee.zrl`](probes/gap_98_frame_view_in_by_value_aggregate_stored_by_callee.zrl)**: A frame view held by a struct passed by value to a callee that stores it out (`keep(out, Carrier { v: &x })` with `fn keep(out: &mut &i32, c: Carrier) { *out = c.v; }`): the default call store rule does not see the view the by-value argument holds, so `*out` keeps the dead frame's address (exit 77 where it held 42), while `*out = c.v` in the frame itself, and a callee returning `c.v`, are refused. The same goes for a nested struct, a tuple, an array, a method's by-value `self`, a copy bound by `let` or a destructuring pattern in the callee, and the whole struct stored (`*out = c`), and for a raw pointer to the frame in place of the reference. Refused under `--provenance` (`tests/language/memory/provenance/raw_ptr_to_frame_from_by_value_owner_refused.zrl` for the raw pointer). Route class: a frame view held by an aggregate passed by value to a callee that stores it, or the whole aggregate, out
- **[`gap_47_closure_ref_struct_mutref_escape.zrl`](probes/gap_47_closure_ref_struct_mutref_escape.zrl)**: A closure that captured `r = &w`, where the local struct `w` holds the caller's `&mut`, stores a frame view through `*r.out`; the external destination is two hops from the closure environment. Route class: a store whose external destination is reached through references to locals (closure environment, call argument)
- **[`gap_48_closure_ref_ref_struct_mutref_escape.zrl`](probes/gap_48_closure_ref_ref_struct_mutref_escape.zrl)**: The same store three hops from the environment (`rr = &r`, `*rr.out = s`), so a rule following a fixed number of hops misses it. Route class: a store whose external destination is reached through references to locals (closure environment, call argument)
- **[`gap_55_closure_param_forwards_view.zrl`](probes/gap_55_closure_param_forwards_view.zrl)**: A closure called with a destination as its own argument (`cl(out)`, `|o: &mut [i32]| { put(o, view); }`) forwards a captured frame view to a named callee that stores it there; the closure body is clean (the view is what `__env` reaches, `o` a parameter) and the call through the closure value is not checked against what its environment holds. Route class: a call through a closure value
- **[`gap_52_closure_passed_to_caller_of_fn_value.zrl`](probes/gap_52_closure_passed_to_caller_of_fn_value.zrl)**: A closure storing a frame view through a captured `&mut` is handed to a function that calls it (`call_it(|| { *out = s; })` with `fn call_it(g: fn()) { g(); }`); the callee's call through `g` stores the environment into itself, which its store summary does not record, so the caller never checks what the closure captured. Accepted with and without `--provenance`; also through two callers, a method taking a `fn`, and a closure bound to a `let` first. Route class: a closure passed as an argument to a callee that calls it
- **[`gap_64_closure_global_store_via_fn_param.zrl`](probes/gap_64_closure_global_store_via_fn_param.zrl)**: A closure that stores a captured frame address into a global (`run(|| { G = r as *i32; })` with `fn run(f: fn()) { f(); }` and `r = &x`) is handed to a function that calls it. The closure body stores what its `__env` reaches into a global, which is not frame-bound there, and neither the call through `f` nor the call to `run` sees a store into a global; the direct call `cl()` is refused by the old rules, and a `fn` item that stores into a global cannot become a value (`check_fn_value`), but nothing checks a closure. Accepted; under `--provenance` the closure rule refuses it where the closure is made (`tests/language/memory/provenance/closure_value_global_store_refused.zrl`). Route class: a closure passed as an argument to a callee that calls it, with a global destination (the class of `gap_52`).
- **[`gap_94_closure_store_through_captured_raw_ptr_to_global.zrl`](probes/gap_94_closure_store_through_captured_raw_ptr_to_global.zrl)**: A closure storing a frame address through a captured raw pointer to a global (`let gp = &mut G as *mut *i32; let cl = || { unsafe { *gp = r as *i32; } }; cl();` with `r = &x`), called directly or handed to a callee. The body's store goes into the memory the capture `gp` points to, and the caller maps it to the destination reach of `gp`'s local, which follows what a local holds only for a type holding a mutable handle, never a raw pointer's pointee, so the global is lost. The same store with no closure, and through a named function's raw pointer parameter, are refused. Accepted; under `--provenance` a capture's bit as a target is read one level through the capture's local, and it is refused (`tests/language/memory/provenance/known_callee_closure_store_through_raw_ptr_refused.zrl`). Route class: a store through a captured raw pointer (a destination reached through a capture).
- **[`gap_95_callee_store_through_raw_ptr_field_to_global.zrl`](probes/gap_95_callee_store_through_raw_ptr_field_to_global.zrl)**: A callee storing a frame address through a raw pointer to a global that a struct field holds (`put(&s, &x)` with `struct S { p: *mut *i32 }`, `s.p = &mut G as *mut *i32`, and `put` storing `r` through `s.p`). `put`'s summary stores its second argument into what `s` reaches, and the caller maps that to the destination reach of `s`, which follows what a local holds only for a mutable handle, a raw `*mut` pointer being none (counting it as one would make every `Vec` follow what it holds), so the global is never a target. The same store through a raw pointer parameter is refused. Accepted; under `--provenance` the destination reach of a local holding a raw `*mut` that is not part of an owner keeps the `Static` it holds, and it is refused (`tests/language/memory/provenance/callee_store_through_raw_ptr_field_refused.zrl`, also beside a `Vec` in one struct and nested in another struct). Route class: a store through a raw pointer held by a value a callee reaches (`gap_94`'s class, for a named callee).
- **[`gap_56_extern_copy_extend_from_slice.zrl`](probes/gap_56_extern_copy_extend_from_slice.zrl)**: `Vec.extend_from_slice` copies a slice of frame views into the caller's `Vec` with `memcpy` and declares no `#[stores]`, so no summary records that the slice's elements are stored into `self`. Route class: a safe body that copies reference-carrying elements through an `extern` with no declared effect
- **[`gap_102_raw_write_store_hidden_from_summary.zrl`](probes/gap_102_raw_write_store_hidden_from_summary.zrl)**: A safe `put(s: &Slot, r: &i32) { unsafe { *s.p = r; } }`, with `s.p` a raw pointer to the caller's `h.r`, stores `&local` and declares no `#[stores]`. The default build records no store; under `--provenance` the summary records it (`store Param(1) -> ParamContents(0)`), but the caller's destination reach stops at a local holding a raw `*mut` and adds only its `Static`, so the parameter memory `s.p` points into is no target. `h.r` keeps a pointer into a dead frame (exit 77, the stack junk that overwrote it, where it would read 7), in the default build and under `--provenance`. Route class: a safe body that hides a store of a reference-carrying value behind a raw-pointer write, the twin of `gap_56`'s `extern` copy.
- **[`gap_103_extern_copy_store_hidden_through_raw_field.zrl`](probes/gap_103_extern_copy_store_hidden_through_raw_field.zrl)**: A safe `put(s: &Slot, r: &i32)` copies `r` into `*s.p` with `memcpy(s.p as *mut u8, &src as *&i32 as *u8, 8)` and declares no `#[stores]`. A bare `extern` has no store effect, so no summary records the store, and `h.r` keeps a pointer into a dead frame (exit 77) in the default build and under `--provenance`. A direct `memcpy(&mut h.r as *mut &i32 as *mut u8, ..)` into a parameter is refused by the default rules (`region escape: a pointer to local stack storage is written to memory that outlives this function`); the copy through a raw pointer the caller's struct holds is not. Route class: gap_56's, a store hidden behind a bare `extern` copy, here in user code rather than the standard library.
- **[`gap_57_match_ref_local_enum_binding_returned.zrl`](probes/gap_57_match_ref_local_enum_binding_returned.zrl)**: A binding of a `match` on a reference to a local enum (`let r = &e; match r { E.A(x) => x, .. }`, also `if let` on `&e` and a `&mut e` scrutinee) is a pointer into the enum, and returning it is accepted. Route class: a payload bound by reference through a reference scrutinee
- **[`gap_58_match_ref_accessor_local_enum_returned.zrl`](probes/gap_58_match_ref_accessor_local_enum_returned.zrl)**: The same binding made inside an accessor (`fn pick(r: &E) -> &P { return match r { .. }; }`), whose result the summary does not tie to `r`, so `return pick(&e)` is accepted. Route class: a payload bound by reference through a reference scrutinee
- **[`gap_59_pushed_vec_holding_frame_views.zrl`](probes/gap_59_pushed_vec_holding_frame_views.zrl)**: A local `Vec<[i32]>` holding a view of a stack array is pushed into the caller's `Vec<Vec<[i32]>>`; the old rules see an owner moved out, not the frame views it holds. Route class: an owner whose elements are frame views, moved into memory that outlives the frame
- **[`gap_60_vec_holding_frame_views_moved_to_pushing_callee.zrl`](probes/gap_60_vec_holding_frame_views_moved_to_pushing_callee.zrl)**: The same `Vec` passed by value to a callee that pushes it into the caller's `Vec`. Route class: an owner whose elements are frame views, moved into memory that outlives the frame
- **[`gap_61_struct_wrapping_vec_of_frame_views_pushed.zrl`](probes/gap_61_struct_wrapping_vec_of_frame_views_pushed.zrl)**: The same `Vec` wrapped in a struct literal and pushed. Route class: an owner whose elements are frame views, moved into memory that outlives the frame
- **[`gap_63_vec_built_around_param_view_in_callee.zrl`](probes/gap_63_vec_built_around_param_view_in_callee.zrl)**: A callee builds a `Vec<[i32]>` around a view of a caller-local `Vec`'s buffer reached through a parameter (`tmp.push(v.as_slice()); *out = tmp;`) and stores it into the caller's slot. Route class: an owner whose elements are frame views, moved into memory that outlives the frame
- **[`gap_44_borrows_attr_reset.zrl`](probes/gap_44_borrows_attr_reset.zrl)**: A `#[borrows()]` method returning a view its receiver holds gives a result that holds no borrow, so an arena reset passes while the result is read; without the attribute the reset is refused. Route class: the liveness route of the `#[borrows()]` laundering that `gap_30` closes for stores
- **[`gap_78_option_clone_launders_frame_view.zrl`](probes/gap_78_option_clone_launders_frame_view.zrl)**: The clone of `Some(s)`, `s` a view of a stack array, is returned: `o.clone()` is tied to the local `o` by the `&self` default (`Clone for Option<T>` declares no `#[borrows()]`), but the default build's return rule does not follow that tie to the view `o` holds. Returning `o` itself is refused, and `--provenance` refuses the clone (the return rule). Route class: a call result tied to a local whose value holds a frame view, returned
- **[`gap_79_struct_holding_frame_view_pushed.zrl`](probes/gap_79_struct_holding_frame_view_pushed.zrl)**: A struct literal holding a `[u8]` view of a stack array is pushed into the caller's `Vec` (`out.push(H { s: s })`): the bare view is refused with a region-escape error, the struct carrying it is not, so the caller reads the dead frame (exit 77 where the frame held 42). `resize` and `extend_from_slice` of such a struct take the same route. Route class: a struct whose field is a frame view, moved into memory that outlives the frame
- **[`gap_80_struct_view_cloned_into_callers_vec.zrl`](probes/gap_80_struct_view_cloned_into_callers_vec.zrl)**: A struct holding a `[u8]` view of a stack array is cloned into the caller's `Vec` by `out.resize(1, H { s: &buf })`, with `impl Clone for H` returning `H { s: self.s }`: the clone's result is not tied to the view `self` holds, so the caller reads the dead frame (exit 77 where the frame held 42); `extend_from_slice` of an array of such structs is the same. Route class: a `Clone` impl whose result copies a view it does not declare (the class of `gap_78`)

### Open Gap Route Classes

The open holes in checked code above are tracked as 52 `known_gap` probes in [`probes/`](probes) and grouped into 15 route classes (`(A)`–`(O)`):

- **(A) Same-parameter destination and value:** when one parameter carries both an external destination and a borrowed source, the store check allows storing a frame view into external storage ([`gap_07_path_same_param.zrl`](probes/gap_07_path_same_param.zrl)), also when the parameter is a struct of references through which the callee copies between two of the caller's locals ([`gap_53_same_param_struct_copy.zrl`](probes/gap_53_same_param_struct_copy.zrl)).
- **(B) Unrecognised external destinations:** a global a callee reaches through a raw pointer held in a struct field ([`gap_95_callee_store_through_raw_ptr_field_to_global.zrl`](probes/gap_95_callee_store_through_raw_ptr_field_to_global.zrl)).
- **(C) Closures storing frame views:** a closure storing a frame-owned view through a captured mutable reference is accepted ([`gap_11_dest_closure_capture_mut.zrl`](probes/gap_11_dest_closure_capture_mut.zrl)), and so is one storing it through a caller's `&mut` held in a local struct that the closure reaches through one or more local references ([`gap_47_closure_ref_struct_mutref_escape.zrl`](probes/gap_47_closure_ref_struct_mutref_escape.zrl), [`gap_48_closure_ref_ref_struct_mutref_escape.zrl`](probes/gap_48_closure_ref_ref_struct_mutref_escape.zrl)), and so is one that forwards a captured frame view to a named callee storing it through the closure's own parameter ([`gap_55_closure_param_forwards_view.zrl`](probes/gap_55_closure_param_forwards_view.zrl)), and so is one handed to a function that calls it ([`gap_52_closure_passed_to_caller_of_fn_value.zrl`](probes/gap_52_closure_passed_to_caller_of_fn_value.zrl)), also when what it stores is a captured frame address and the destination a global ([`gap_64_closure_global_store_via_fn_param.zrl`](probes/gap_64_closure_global_store_via_fn_param.zrl)), and so is one storing it through a captured raw pointer to a global ([`gap_94_closure_store_through_captured_raw_ptr_to_global.zrl`](probes/gap_94_closure_store_through_captured_raw_ptr_to_global.zrl)).
- **(D) Two-axis aggregate and path combinations:** a reference to a stack local, an element reference, or a stack-capturing closure carried through an enum payload, a `fn` value or a 65th parameter loses provenance and is accepted ([`gap_13_ref_local_enum_payload.zrl`](probes/gap_13_ref_local_enum_payload.zrl), [`gap_36_carrier_ref_enum_payload_match.zrl`](probes/gap_36_carrier_ref_enum_payload_match.zrl), [`gap_16_ref_local_fn_val.zrl`](probes/gap_16_ref_local_fn_val.zrl), [`gap_18_elem_ref_enum_payload.zrl`](probes/gap_18_elem_ref_enum_payload.zrl), [`gap_21_elem_ref_fn_val.zrl`](probes/gap_21_elem_ref_fn_val.zrl), [`gap_23_closure_local_enum_payload.zrl`](probes/gap_23_closure_local_enum_payload.zrl), [`gap_26_closure_local_fn_val.zrl`](probes/gap_26_closure_local_fn_val.zrl), [`gap_27_closure_local_param_65.zrl`](probes/gap_27_closure_local_param_65.zrl)).
- **(E) Call summary limits:** parameters beyond the 64-parameter limit drop provenance, and a callee compiled separately records an empty store summary in its `.zri` ([`gap_33_param_65_arena_slice_store.zrl`](probes/gap_33_param_65_arena_slice_store.zrl)).
- **(F) Storing what by-value owning parameters own:** a view into a `Vec` passed by value is accepted for a store into caller memory ([`gap_32_byval_collection_param_store.zrl`](probes/gap_32_byval_collection_param_store.zrl)), and so is a `Vec` made in an `Arena` passed by value and pushed into the caller's `Vec`, read after the arena is freed ([`gap_62_byval_arena_param_vec_pushed.zrl`](probes/gap_62_byval_arena_param_vec_pushed.zrl)).
- **(G) Stores into a local or a Box's contents through a pointer to it:** a view written into a local struct's field by a callee through its `&mut` parameter or `self` in a method is not recorded as a borrow the caller's struct holds, so an arena reset passes while the field is read ([`gap_38_param_field_reset.zrl`](probes/gap_38_param_field_reset.zrl), [`gap_39_method_self_field_reset.zrl`](probes/gap_39_method_self_field_reset.zrl)); and a frame view written by a callee through its `&mut` parameter or by a closure that captured a local `&mut` to the struct is accepted when it is then stored out ([`gap_41_callee_field_escape.zrl`](probes/gap_41_callee_field_escape.zrl), [`gap_45_closure_mutref_field_escape.zrl`](probes/gap_45_closure_mutref_field_escape.zrl)); and a view a callee makes of one argument and stores into a caller's local through another is held by nothing in the caller, so the caller can free its source while the local is still read ([`gap_96_callee_stores_view_then_caller_frees.zrl`](probes/gap_96_callee_stores_view_then_caller_frees.zrl)).
- **(H) `#[borrows()]` across a reset:** a `#[borrows()]` method returning a view its receiver holds gives a result that holds no borrow, so an arena reset passes while the result is read; the store form of the same laundering is refused ([`gap_30_borrows_attribute_launder.zrl`](probes/gap_30_borrows_attribute_launder.zrl)), but the result's liveness is not checked ([`gap_44_borrows_attr_reset.zrl`](probes/gap_44_borrows_attr_reset.zrl)).
- **(I) Stores hidden behind an `extern` copy or a raw write:** a safe function that copies reference-carrying elements with `memcpy`, or writes a reference through a raw pointer in an `unsafe` block, and declares no `#[stores]` stores them where no summary sees it: `Vec.extend_from_slice` puts views of the caller's stack frame into a longer-lived `Vec` ([`gap_56_extern_copy_extend_from_slice.zrl`](probes/gap_56_extern_copy_extend_from_slice.zrl)), and `unsafe { *s.p = r; }` puts one into the caller's struct ([`gap_102_raw_write_store_hidden_from_summary.zrl`](probes/gap_102_raw_write_store_hidden_from_summary.zrl)), and a user's own `memcpy` through a raw pointer the caller's struct holds does the same ([`gap_103_extern_copy_store_hidden_through_raw_field.zrl`](probes/gap_103_extern_copy_store_hidden_through_raw_field.zrl)).
- **(J) Payloads bound through a reference to a local enum:** a `match` or `if let` on a reference binds the payload by reference, a pointer into the enum; when the enum is a local, returning the binding is accepted, directly ([`gap_57_match_ref_local_enum_binding_returned.zrl`](probes/gap_57_match_ref_local_enum_binding_returned.zrl)) or through an accessor that matches on its reference parameter ([`gap_58_match_ref_accessor_local_enum_returned.zrl`](probes/gap_58_match_ref_accessor_local_enum_returned.zrl)).
- **(K) Owners holding frame views, moved out:** a local `Vec` whose elements are views of a stack array is accepted when it is pushed into the caller's `Vec` ([`gap_59_pushed_vec_holding_frame_views.zrl`](probes/gap_59_pushed_vec_holding_frame_views.zrl)), passed by value to a callee that pushes it ([`gap_60_vec_holding_frame_views_moved_to_pushing_callee.zrl`](probes/gap_60_vec_holding_frame_views_moved_to_pushing_callee.zrl)), or wrapped in a struct first ([`gap_61_struct_wrapping_vec_of_frame_views_pushed.zrl`](probes/gap_61_struct_wrapping_vec_of_frame_views_pushed.zrl)); and a `Vec` a callee builds around a view of a caller-local `Vec`'s buffer is accepted when the callee stores it into the caller's slot ([`gap_63_vec_built_around_param_view_in_callee.zrl`](probes/gap_63_vec_built_around_param_view_in_callee.zrl)). A struct that holds a view of a stack array directly is accepted when it is pushed into the caller's `Vec` (`out.push(H { s: s })`), although the bare view is refused ([`gap_79_struct_holding_frame_view_pushed.zrl`](probes/gap_79_struct_holding_frame_view_pushed.zrl)).
- **(L) A generic `Clone` impl that hides what it clones:** the clone of an `Option` holding a view of a stack array is tied to the local it was cloned from, but the default build does not follow that tie to the view, so it can be returned ([`gap_78_option_clone_launders_frame_view.zrl`](probes/gap_78_option_clone_launders_frame_view.zrl)); so is a user `Clone` impl that copies a view its result does not declare, through `resize` and `extend_from_slice` ([`gap_80_struct_view_cloned_into_callers_vec.zrl`](probes/gap_80_struct_view_cloned_into_callers_vec.zrl)). A direct slice clone, a `Vec` clone, `clone_in` and a `#[derive(Clone)]` struct are refused.
- **(N) Frame views read through a reference to a local aggregate:** a view of the stack held by a local struct, tuple or array, read through a local reference to it (`let r = &s; *out = r.v;`), a reborrow, or a callee's reference parameter, is accepted when stored out or returned, while the same read made directly (`*out = s.v`) is refused ([`gap_97_frame_view_read_through_local_ref_stored_out.zrl`](probes/gap_97_frame_view_read_through_local_ref_stored_out.zrl)).
- **(O) Frame views in an aggregate passed by value to a storing callee:** a view of the stack held by a struct, tuple or array passed by value to a callee that stores it, or the whole aggregate, into the caller's memory (`keep(out, Carrier { v: &x })` with `*out = c.v` in `keep`) is accepted, while the same store made in the frame, or a callee returning the view, is refused ([`gap_98_frame_view_in_by_value_aggregate_stored_by_callee.zrl`](probes/gap_98_frame_view_in_by_value_aggregate_stored_by_callee.zrl)).

### 6.1 The classes by fix and by how often code meets them

The holes above are not each a problem of their own. Each probe belongs to one of three kinds of hole, and each kind has a single fix:

1. **Escape:** an address of the function's frame, or of storage the function owns, outlives the function. The provenance rules (`--provenance`, designed in the repository's [`doc/design/provenance.md`](../../doc/design/provenance.md)) are this fix. Every probe of classes A, C, D, E, F, I, J, K, L, N and O, `gap_95` of class B, and the remaining escape half of class G (`gap_41`, `gap_45`) is refused under `--provenance` today, with a provenance error. What is left is making those rules the default without refusing safe programs the default mode accepts. Those refusals are counted on the store grid and in the test programs, and they are read one by one before the switch.
2. **Invalidation:** a view is read after what it views is freed or its arena is reset, while no local of the frame holds the borrow. This covers the reset half of class G (gap_38, gap_39, gap_96) and class H, all accepted under `--provenance` too. The fix is the liveness model (`doc/design/provenance.md` §3.1): holders one and two are built (closing gap_37, gap_40, gap_42, gap_43, gap_87, class M, and the arena-escape calls gap_28, gap_29, gap_49, gap_50, gap_51, gap_54), leaving only holder three (callees' store summaries for gap_38, gap_39 and gap_96) and `#[borrows()]` narrowing checks (class H). A view held outside the frame, or handed back by a callee, is invalidated only by an operation that releases storage (`free`, an arena reset, a drop), never by growth, which keeps the old buffer (§4.1 of the safety model).
3. **Raw pointer reach:** a store inside an `unsafe` block, through a raw pointer, reaches a global the checker does not see. gap_94 of class C and gap_95 of class B are refused under `--provenance`. A raw `*mut` that is not part of an owner leads a store to the `static mut` it may name, while a `Vec`'s buffer, which is a raw `*mut` too, points into what the `Vec` owns and does not become a destination of every store. Inside `unsafe`, as in Rust, soundness is the programmer's to keep (§4.1), so this kind matters least.

How often ordinary code meets each class is an estimate from what the route needs, not a measurement:

| Class                       | Kind                 | Code meets it                 | `--provenance`      |
| --------------------------- | -------------------- | ----------------------------- | ------------------- |
| (A) one parameter, both     | escape               | rare                          | refused             |
| (B) unseen destinations     | escape, raw pointer  | occasional; gap_95 `unsafe`   | refused             |
| (C) closures                | escape, raw pointer  | common; rare (gap_47, gap_48) | refused             |
| (D) payloads, `fn` values   | escape               | occasional; rare (65th)       | refused             |
| (E) call summary limits     | escape               | occasional; rare (recursion)  | refused             |
| (F) by-value owners         | escape               | occasional                    | refused             |
| (G) stores through `&mut`   | escape, invalidation | common (`&mut self`)          | escape half refused |
| (H) `#[borrows()]`, reset   | invalidation         | occasional                    | accepted            |
| (I) an `extern` copy        | escape               | common (`extend_from_slice`)  | refused             |
| (J) `match` on `&` to local | escape               | common                        | refused             |
| (K) owners of frame views   | escape               | common (`push`)               | refused             |
| (L) `Clone` laundering      | escape               | common (`clone()`)            | refused             |
| (N) reads through `&` local | escape               | common                        | refused             |
| (O) by-value aggregate      | escape               | common                        | refused             |

To see where a class stands, compile its probe with and without the flag: `timeout -k 5s 30s build/zoril --provenance <probe> -I stdlib=stdlib -o out.zil` exits 1 with a `provenance:` error for every probe the last column marks refused, and 0 for the others; every probe exits 0 without the flag.

---

## 3. Trusted-Base Census and Marker Density

`scripts/check_safety_figures.sh --milestone` compares the trusted-base census and marker-density rows below against `stdlib/` and `src/`.

| Figure                           | Value  |
| -------------------------------- | ------ |
| stdlib modules                   | 30     |
| stdlib lines                     | 6,753  |
| stdlib `unsafe { }` blocks       | 187    |
| stdlib modules with such a block | 23     |
| stdlib `unsafe fn` declarations  | 67     |
| of those, public                 | 62     |
| compiler modules                 | 50     |
| compiler lines                   | 51,985 |
| compiler `unsafe { }` blocks     | 904    |

How each figure is counted: every `.zrl` file under the directory, recursively; **lines** are physical lines (`wc -l`); **`unsafe { }` blocks** are occurrences of `unsafe` followed by `{` on the same line; **`unsafe fn` declarations** are lines that start with `unsafe fn` or `pub unsafe fn`.

- **The standard library** holds 187 `unsafe { }` blocks in 23 of its 30 modules. Every one states the invariant it relies on in a `// SAFETY:` comment (`scripts/check_safety_comments.sh`).
- **The compiler** is 50 modules of Zoril, with 904 `unsafe { }` blocks, because a self-hosted compiler also carries its own allocator and IL machinery.

### Marker-density calibration against Rust

Measured on the Rust source tree (a one-time measurement) and recomputed on Zoril by `scripts/check_safety_figures.sh --density`, counting non-blank, non-comment lines inside `unsafe { }` blocks against non-comment LOC (see [`doc/spec/unsafe_policy.md`](../../doc/spec/unsafe_policy.md) §5 for methodology and limits):

| codebase                                 | layer            | line density            |
| ---------------------------------------- | ---------------- | ----------------------- |
| rustc `compiler/` (663k LOC)             | compiler         | **0.61%**               |
| Rust `library/core` + `alloc` (109k LOC) | stdlib / runtime | **6.03%**               |
| Zoril `src/` (45k non-comment LOC)       | compiler         | **4.54%** (904 blocks)  |
| Zoril `stdlib/` (4.9k non-comment LOC)   | stdlib           | **10.94%** (187 blocks) |
| Zoril example JSON tool (1.9k LOC)       | application      | **0.00%** (0 blocks)    |

Live Zoril line counts: 2,043 of 45,004 lines in `src/`, 531 of 4,854 in `stdlib/`, 0 of 1,992 in the example JSON tool.

---

## 4. Unsafe Operation × Route Reachability Grid

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
  - Explicit Syntax: Rejected outside `unsafe` (probes [`14_null_deref.zrl`](probes/14_null_deref.zrl), [`31_null_deref_unsafe.zrl`](probes/31_null_deref_unsafe.zrl))
  - Auto-Deref: Rejected outside `unsafe` (probes [`12_raw_ptr_indexing.zrl`](probes/12_raw_ptr_indexing.zrl), [`120_raw_pointer_field_access.zrl`](probes/120_raw_pointer_field_access.zrl))
  - Coercion Sites: Cannot occur (no implicit deref)
  - Generics: Type parameter cannot deref
  - Closures: Body checked; a capture keeps the raw type, so the dereference is gated (probe [`154_launder_raw_ptr_closure.zrl`](probes/154_launder_raw_ptr_closure.zrl))
  - Match Bindings: A binding keeps the raw type, so the dereference is gated (probes [`152_launder_raw_ptr_match_binding.zrl`](probes/152_launder_raw_ptr_match_binding.zrl), [`157_launder_raw_ptr_option_match.zrl`](probes/157_launder_raw_ptr_option_match.zrl))
  - `defer`: Lowered and gated
  - Cross-Module: Symbol signatures enforce `unsafe` (probe [`139_raw_call_result_deref_outside_unsafe.zrl`](probes/139_raw_call_result_deref_outside_unsafe.zrl))
- **Pointer forging (`n as *T`, `@ptr_from_int`)**
  - Explicit Syntax: Creation accepted; the _use_ rejected outside `unsafe` (probes [`13_forged_pointer.zrl`](probes/13_forged_pointer.zrl), [`122_int_to_raw_pointer_cast.zrl`](probes/122_int_to_raw_pointer_cast.zrl), [`187_int_to_raw_ptr_cast_safe.zrl`](probes/187_int_to_raw_ptr_cast_safe.zrl))
  - Auto-Deref: Cannot occur (only projects)
  - Coercion Sites: Cannot occur (type mismatch)
  - Generics: Cast `n as T` rejected; `@ptr_from_int<T>` gated (probe [`29_generic_null_cast.zrl`](probes/29_generic_null_cast.zrl))
  - Closures: Lowered like any other cast; the capture keeps the raw type, so the dereference in the body is gated
  - Match Bindings: Cannot occur (patterns only bind)
  - `defer`: Lowered, and the use gated where it appears
  - Cross-Module: A constant initializer may hold the address
- **Slice forging (`@slice`)**
  - Explicit Syntax: Rejected outside `unsafe` (probe [`63_slice_forged_from_reference.zrl`](probes/63_slice_forged_from_reference.zrl))
  - Auto-Deref: Cannot occur (only projects)
  - Coercion Sites: Cannot occur (types match or fail)
  - Generics: Intrinsic cannot be genericized
  - Closures: Lowered and gated in closure body
  - Match Bindings: Cannot occur (patterns only slice)
  - `defer`: Lowered and gated
  - Cross-Module: Module interface typed as slice
- **Foreign function calls (`extern fn`)**
  - Explicit Syntax: Rejected outside `unsafe` (probes [`140_extern_call_outside_unsafe.zrl`](probes/140_extern_call_outside_unsafe.zrl), [`141_extern_call_unsafe.zrl`](probes/141_extern_call_unsafe.zrl))
  - Auto-Deref: Cannot occur (no extern methods)
  - Coercion Sites: Cannot occur (fn value rejected; [`tests/error_reporting/err_extern_fn_value_param.zrl`](../../tests/error_reporting/err_extern_fn_value_param.zrl))
  - Generics: Foreign fn cannot satisfy trait
  - Closures: Lowered and gated in closure body
  - Match Bindings: Cannot occur (symbol not a pattern)
  - `defer`: Lowered and gated
  - Cross-Module: Symbol table preserves `is_extern`
- **Raw-to-reference (`*T` -> `&T`)**
  - Explicit Syntax: Rejected outside `unsafe` (probes [`123_raw_pointer_to_reference.zrl`](probes/123_raw_pointer_to_reference.zrl), [`124_raw_pointer_to_reference_unsafe.zrl`](probes/124_raw_pointer_to_reference_unsafe.zrl))
  - Auto-Deref: Rejected outside `unsafe` (probe [`133_raw_ptr_index_borrow.zrl`](probes/133_raw_ptr_index_borrow.zrl))
  - Coercion Sites: Rejected: the projection keeps the raw type, so the conversion is a type error (probe [`158_launder_null_ref_tuple.zrl`](probes/158_launder_null_ref_tuple.zrl))
  - Generics: Rejected: identity keeps the raw type (probe [`125_raw_pointer_to_reference_through_generic.zrl`](probes/125_raw_pointer_to_reference_through_generic.zrl))
  - Closures: Checked at boundaries
  - Match Bindings: Rejected: a binding keeps the raw type (probes [`152_launder_raw_ptr_match_binding.zrl`](probes/152_launder_raw_ptr_match_binding.zrl), [`157_launder_raw_ptr_option_match.zrl`](probes/157_launder_raw_ptr_option_match.zrl))
  - `defer`: Lowered and gated
  - Cross-Module: Signatures enforce `check_raw_into_ref`
- **System call (`@syscall`)**
  - Explicit Syntax: Rejected outside `unsafe` (probes [`129_syscall_outside_unsafe.zrl`](probes/129_syscall_outside_unsafe.zrl), [`130_syscall_unsafe.zrl`](probes/130_syscall_unsafe.zrl))
  - Auto-Deref: Cannot occur (compiler intrinsic)
  - Coercion Sites: Cannot occur (no syscall coercion)
  - Generics: Intrinsic cannot be genericized
  - Closures: Lowered and gated in closure body
  - Match Bindings: Cannot occur (symbol not a pattern)
  - `defer`: Lowered and gated
  - Cross-Module: Intrinsic not exportable
- **Stack allocation (`@alloca`)**
  - Explicit Syntax: Rejected outside `unsafe` (probes [`131_alloca_outside_unsafe.zrl`](probes/131_alloca_outside_unsafe.zrl), [`132_alloca_unsafe.zrl`](probes/132_alloca_unsafe.zrl))
  - Auto-Deref: Cannot occur (compiler intrinsic)
  - Coercion Sites: Cannot occur (no alloca coercion)
  - Generics: Intrinsic cannot be genericized
  - Closures: Lowered and gated in closure body
  - Match Bindings: Cannot occur (symbol not a pattern)
  - `defer`: Lowered and gated
  - Cross-Module: Intrinsic not exportable

_(Note: Table rows begin without leading asterisks to distinguish this route analysis from the 68 normative safety properties in Section 2.)_

---

### 4.1 Raw Pointer Dereference

Dereferencing a raw pointer (`*const T`, `*mut T`) bypasses lifetime and alias tracking; reading or writing through an unaligned, dangling, or null raw pointer leads to segmentation faults or memory corruption.

- **Explicit Syntax:** Gated in ZIR lowering (`lower_unary_expr` in [`src/lower_zir/expr.zrl`](../../src/lower_zir/expr.zrl)). Dereference `*p` checks `place_is_raw_ptr`; if true and `ctx.unsafe_depth == 0`, lowering emits a compile-time error.
  - Proved by probe [`14_null_deref.zrl`](probes/14_null_deref.zrl) (rejection outside `unsafe`) and [`31_null_deref_unsafe.zrl`](probes/31_null_deref_unsafe.zrl) (permitted inside `unsafe`).
  - Attempting to dereference non-pointer types is rejected by [`tests/error_reporting/err_deref_non_pointer.zrl`](../../tests/error_reporting/err_deref_non_pointer.zrl).
- **Auto-Deref:** Field access (`p.field`), tuple element access (`p.0`), method receiver calls (`p.method()`), and indexing (`p[i]`, `&p[i]`) perform implicit dereferences.
  - In [`src/lower_zir/expr.zrl`](../../src/lower_zir/expr.zrl) (`lower_member_access_expr`, `Expr.TupleAccess`, `Expr.Index`), `check_raw_deref_is_marked` and `place_is_raw_ptr` verify that any auto-dereference on a raw pointer base is enclosed in an `unsafe` block.
  - Proved by probes:
    - Index read: [`12_raw_ptr_indexing.zrl`](probes/12_raw_ptr_indexing.zrl) (rejected) vs [`36_raw_ptr_indexing_unsafe.zrl`](probes/36_raw_ptr_indexing_unsafe.zrl) (allowed in `unsafe`).
    - Field access: [`120_raw_pointer_field_access.zrl`](probes/120_raw_pointer_field_access.zrl) (rejected) vs [`121_raw_pointer_field_access_unsafe.zrl`](probes/121_raw_pointer_field_access_unsafe.zrl) (allowed in `unsafe`).
    - Slice raw pointer dereference (`s.ptr.field`): [`126_slice_ptr_deref.zrl`](probes/126_slice_ptr_deref.zrl).
    - Borrow of raw index (`&p[i]`): [`133_raw_ptr_index_borrow.zrl`](probes/133_raw_ptr_index_borrow.zrl), [`tests/error_reporting/err_raw_ptr_index_borrow.zrl`](../../tests/error_reporting/err_raw_ptr_index_borrow.zrl).
    - Field write and tuple access: [`tests/error_reporting/err_raw_ptr_field_write.zrl`](../../tests/error_reporting/err_raw_ptr_field_write.zrl), [`tests/error_reporting/err_raw_ptr_tuple_field.zrl`](../../tests/error_reporting/err_raw_ptr_tuple_field.zrl), [`tests/error_reporting/err_raw_ptr_nested_field.zrl`](../../tests/error_reporting/err_raw_ptr_nested_field.zrl).
- **Coercion Sites:** _Cannot occur._ Zoril has no implicit dereference coercions (e.g. `T` is never implicitly produced from `*T`). A type mismatch is emitted at every coercion site where a value is expected instead of a pointer ([`tests/error_reporting/err_assign_type_mismatch.zrl`](../../tests/error_reporting/err_assign_type_mismatch.zrl)).
- **Generics:** _Cannot occur._ An unconstrained type parameter `T` cannot be dereferenced (`*t` is rejected because `T` is not recognized as a pointer in `src/lower_zir/expr.zrl`; [`tests/error_reporting/err_deref_non_pointer.zrl`](../../tests/error_reporting/err_deref_non_pointer.zrl)). Trait bounds cannot express raw pointer dereferences.
- **Closures:**
  - Explicit dereferences or auto-derefs written inside a closure body are lowered under the closure's local AST context and are rejected if not enclosed in `unsafe` (probe [`14_null_deref.zrl`](probes/14_null_deref.zrl)).
  - A raw pointer captured by a closure keeps its own type in the closure's environment, so a dereference through such a capture is gated like any other (probe [`154_launder_raw_ptr_closure.zrl`](probes/154_launder_raw_ptr_closure.zrl) expects `compile_reject`).
- **Match Bindings:**
  - Patterns cannot dereference raw pointers (`*p` is not a pattern).
  - In `match p { q => ... }` and `match Option.Some(p) { Some(q) => ... }`, the binding `q` carries `p`'s pointer type, so `*q` needs `unsafe` (probes [`152_launder_raw_ptr_match_binding.zrl`](probes/152_launder_raw_ptr_match_binding.zrl), [`157_launder_raw_ptr_option_match.zrl`](probes/157_launder_raw_ptr_option_match.zrl), both `compile_reject`).
- **`defer`:** Deferred blocks are lowered via `lower_block`. Any raw dereference inside a `defer` statement is checked against `unsafe_depth` and rejected outside `unsafe` (probe [`14_null_deref.zrl`](probes/14_null_deref.zrl)).
- **Cross-Module Imports:** Function return types across module interfaces keep the raw pointer's own type, so a raw pointer returned by an imported function is still raw at the call site, and dereferencing it without `unsafe` is rejected (probes [`139_raw_call_result_deref_outside_unsafe.zrl`](probes/139_raw_call_result_deref_outside_unsafe.zrl), [`tests/error_reporting/err_raw_call_result_deref.zrl`](../../tests/error_reporting/err_raw_call_result_deref.zrl)).

---

### 4.2 Pointer Forging

Forging pointers from integers (`n as *T`, `@ptr_from_int(n)`) allows fabricating arbitrary addresses. Creating one is **safe** — this section is about the two things that are not: using it, and forging a _reference_ or a _slice_ instead of a raw pointer.

- **Creating a raw pointer is safe.** `n as *T`, `@ptr_from_int<*T>`, `@ptr_cast<*T>` and their `*mut` forms are accepted outside `unsafe`, and so is `@int_cast<U>`, whose result is a number. Every _use_ of the pointer is gated on its own type (the clause below), so a marker on the creation would sit around checked code and buy nothing — and a fixed hardware address, the memory-mapped-I/O case, needs a spelling in a `static`, whose initializer has nowhere to put an `unsafe` block. The decision is `ZirLowerer.ptr_forge_needs_unsafe` in [`src/lower_zir/utils.zrl`](../../src/lower_zir/utils.zrl).
  - Proved by [`bench/safety_matrix/probes/122_int_to_raw_pointer_cast.zrl`](probes/122_int_to_raw_pointer_cast.zrl), [`187_int_to_raw_ptr_cast_safe.zrl`](probes/187_int_to_raw_ptr_cast_safe.zrl), [`tests/functional/pointers/int_to_raw_ptr_cast.zrl`](../../tests/functional/pointers/int_to_raw_ptr_cast.zrl), [`tests/language/other/static_initializer_fixed_address.zrl`](../../tests/language/other/static_initializer_fixed_address.zrl) (a `static` whose initializer is a fixed address, read back as a value in checked code).
- **Using a forged pointer is gated on the pointer's type.** A dereference, a field access, an index, a method call through it and a conversion to a reference all need `unsafe` (`check_raw_deref_is_marked`, `check_raw_arg_is_marked`, `check_raw_into_ref`), whatever produced the pointer.
  - Proved by probes [`13_forged_pointer.zrl`](probes/13_forged_pointer.zrl), [`33_forged_pointer_unsafe.zrl`](probes/33_forged_pointer_unsafe.zrl), [`tests/error_reporting/err_int_to_raw_ptr_cast_deref.zrl`](../../tests/error_reporting/err_int_to_raw_ptr_cast_deref.zrl) (the located error is at the dereference, not at the cast).
- **A reference or a slice result is still gated.** `@ptr_cast<&T>`, `@ptr_from_int<&T>`, `@ptr_cast<[T]>` and the same intrinsics on a type parameter — which may stand for a reference — need `unsafe` (`check_ptr_forge_is_marked`): nothing checked the null-ness of the reference or the length of the slice. The `as` form of the same conversion is refused outright by `check_cast_validity` ("cannot cast integer to reference type: references cannot be null").
  - Proved by [`tests/error_reporting/err_ptr_cast_to_reference_or_slice.zrl`](../../tests/error_reporting/err_ptr_cast_to_reference_or_slice.zrl), [`tests/error_reporting/err_cast_null_ref.zrl`](../../tests/error_reporting/err_cast_null_ref.zrl).
- **Reinterpretation between raw pointer types** (`p as *U`, `@ptr_cast<*U>(p)`) is the same decision as the creation: it is safe, and what it produces is gated on use ([`bench/safety_matrix/probes/27_type_confusion.zrl`](probes/27_type_confusion.zrl)).
- **Auto-Deref:** _Cannot occur._ Auto-deref only navigates fields and elements of existing pointers and references; it never synthesizes pointers from scalar values.
- **Coercion Sites:** _Cannot occur._ Implicit conversion from integer types (`i32`, `i64`, `usize`) to pointer types is rejected by `types_match` in [`src/lower_zir/utils.zrl`](../../src/lower_zir/utils.zrl) ([`tests/error_reporting/err_assign_type_mismatch.zrl`](../../tests/error_reporting/err_assign_type_mismatch.zrl)).
- **Generics:** Casting an integer to a generic type parameter (`n as T`) is rejected by `lower_cast_expr` in [`src/lower_zir/expr.zrl`](../../src/lower_zir/expr.zrl) ([`tests/error_reporting/err_cast_int_to_type_param.zrl`](../../tests/error_reporting/err_cast_int_to_type_param.zrl), probes [`29_generic_null_cast.zrl`](probes/29_generic_null_cast.zrl), [`90_generic_cast_reinterpret.zrl`](probes/90_generic_cast_reinterpret.zrl)). `@ptr_from_int<T>` / `@ptr_cast<T>` on a type parameter are gated instead, for the same reason: the parameter may stand for a reference.
  - _A parameter named like a top-level item:_ `T` is a parameter whatever else has its name: a global struct, enum or alias, a function (a stdlib function stays unlowered until reached, a user function until its turn), a constant or a static, even when instantiated with the enclosing `impl`'s `Self` type (`Resolver.is_type_param` in [`src/resolve.zrl`](../../src/resolve.zrl); probes [`421_generic_null_cast_param_named_stdlib_fn.zrl`](probes/421_generic_null_cast_param_named_stdlib_fn.zrl), [`422_generic_null_cast_param_named_struct.zrl`](probes/422_generic_null_cast_param_named_struct.zrl), and `tests/error_reporting/err_cast_int_to_*type_param_*.zrl`). Casting an integer to `Self` inside an `impl` for a reference alias is likewise refused by `check_cast_validity` ([`tests/error_reporting/err_cast_int_to_self_ref_alias.zrl`](../../tests/error_reporting/err_cast_int_to_self_ref_alias.zrl)).
- **Closures:** A cast inside a closure body is lowered through `lower_cast_expr` like any other, so the same rule applies - and if it produces a raw pointer, the _captured_ pointer keeps its raw type through the environment, which is what gates the dereference inside the body (probe [`154_launder_raw_ptr_closure.zrl`](probes/154_launder_raw_ptr_closure.zrl)).
- **Match Bindings:** _Cannot occur._ Pattern matching decomposes existing structures; it does not execute casts or synthesize addresses.
- **`defer`:** Deferred statements containing a pointer-creation cast are lowered through `lower_cast_expr`; a use of the result is gated where it appears.
- **Cross-Module Imports:** An imported module's `static` may hold a forged address, and its uses need the same `unsafe` as anywhere else; no cross-module route reaches an ungated use.

---

### 4.3 Slice Forging (`@slice`)

Slices (`[T]`, `[mut T]`) package a base pointer and length. Fabricating a slice with an arbitrary length (`@slice(ptr, len)`) can induce out-of-bounds reads or writes.

- **Explicit Syntax:** Gated by `check_slice_forge_is_marked` in [`src/lower_zir/utils.zrl`](../../src/lower_zir/utils.zrl). Calling `@slice(p, n)` where `n != 0` outside `unsafe` is rejected at compile time (probe [`63_slice_forged_from_reference.zrl`](probes/63_slice_forged_from_reference.zrl), [`tests/error_reporting/err_slice_forge_reference.zrl`](../../tests/error_reporting/err_slice_forge_reference.zrl)). (Zero-length empty slices `@slice(p, 0)` are permitted in checked code).
- **Auto-Deref:** _Cannot occur._ Auto-deref accesses existing fields or dereferences pointers; it never constructs slice descriptors.
- **Coercion Sites:** _Cannot occur._ Array-to-slice coercion (`&[T; N]` -> `[T]`) is safe because the compiler synthesizes the exact compile-time constant array length `N`. Coercing arbitrary integers or values to slice types is rejected at compile time (probes [`105_cast_int_to_slice.zrl`](probes/105_cast_int_to_slice.zrl), [`43_array_value_as_slice.zrl`](probes/43_array_value_as_slice.zrl)):
  - Proved by probes [`105_cast_int_to_slice.zrl`](probes/105_cast_int_to_slice.zrl), [`107_cast_int_to_slice_through_alias.zrl`](probes/107_cast_int_to_slice_through_alias.zrl), [`43_array_value_as_slice.zrl`](probes/43_array_value_as_slice.zrl), and [`tests/error_reporting/err_array_value_to_slice_assign.zrl`](../../tests/error_reporting/err_array_value_to_slice_assign.zrl).
- **Generics:** _Cannot occur._ `@slice` is a built-in compiler intrinsic, not a trait or generic method. Type parameter substitution cannot instantiate an unchecked slice construction.
- **Closures:** `@slice` calls inside closure bodies are checked by `check_slice_forge_is_marked`.
- **Match Bindings:** _Cannot occur._ Slice pattern matching (`[first, ..rest]`) decomposes existing slices under bounds validation; it never constructs new unchecked lengths.
- **`defer`:** `@slice` calls in `defer` statements are checked during lowering.
- **Cross-Module Imports:** Exported slices across module interfaces are typed as `[T]` or `[mut T]`. Their slice headers were constructed safely at the source or within an `unsafe` block.

---

### 4.4 Foreign Function Calls (`extern fn`)

Foreign functions implemented in C or assembly cannot be validated by Zoril's safety verifiers. Direct calls to foreign code can perform arbitrary unverified memory operations.

- **Explicit Syntax:** Gated by `check_extern_call_is_marked` in [`src/lower_zir/expr.zrl`](../../src/lower_zir/expr.zrl). Calling an `extern fn` without an enclosing `unsafe` block is rejected at compile time (probes [`140_extern_call_outside_unsafe.zrl`](probes/140_extern_call_outside_unsafe.zrl), [`141_extern_call_unsafe.zrl`](probes/141_extern_call_unsafe.zrl), [`tests/error_reporting/err_extern_call_outside_unsafe.zrl`](../../tests/error_reporting/err_extern_call_outside_unsafe.zrl)).
- **Auto-Deref:** _Cannot occur._ Foreign functions are top-level C symbols; they cannot be defined as struct methods or invoked via auto-deref method dispatch.
- **Coercion Sites:** _Cannot occur._ Passing an `extern fn` as a first-class function pointer value or coercing it to a checked Zoril closure or function type is rejected at compile time ([`tests/error_reporting/err_extern_fn_value_param.zrl`](../../tests/error_reporting/err_extern_fn_value_param.zrl), [`tests/error_reporting/err_fn_value_cast.zrl`](../../tests/error_reporting/err_fn_value_cast.zrl)).
- **Generics:** _Cannot occur._ Foreign functions cannot implement Zoril traits or satisfy generic type bounds.
- **Closures:** Calling an `extern fn` from inside a closure body is checked by `check_extern_call_is_marked` during closure body lowering.
- **Match Bindings:** _Cannot occur._ Foreign functions are callable symbols, not pattern values.
- **`defer`:** Invoking an `extern fn` in a `defer` statement is lowered via `lower_call_expr` and checked by `check_extern_call_is_marked`.
- **Cross-Module Imports:** Re-exported or imported `extern fn` symbols retain `is_extern = true` in the module symbol table. Cross-module calls are checked identically to local extern declarations ([`tests/incremental/c_ffi_unsafe_err.zrl`](../../tests/incremental/c_ffi_unsafe_err.zrl), [`tests/integration/test_ffi.zrl`](../../tests/integration/test_ffi.zrl)).

---

### 4.5 Raw-to-Reference Conversion

Converting an unverified raw pointer (`*T`, `*mut T`) into a safe reference (`&T`, `&mut T`) circumvents borrow checking, alias guarantees, and non-null invariants (probes [`123_raw_pointer_to_reference.zrl`](probes/123_raw_pointer_to_reference.zrl), [`124_raw_pointer_to_reference_unsafe.zrl`](probes/124_raw_pointer_to_reference_unsafe.zrl)).

- **Explicit Syntax:** Explicitly casting or annotating a raw pointer as a reference (`let r: &T = p as &T`) is checked by `check_raw_into_ref` in [`src/lower_zir/utils.zrl`](../../src/lower_zir/utils.zrl) and rejected outside `unsafe` (probes [`123_raw_pointer_to_reference.zrl`](probes/123_raw_pointer_to_reference.zrl), [`124_raw_pointer_to_reference_unsafe.zrl`](probes/124_raw_pointer_to_reference_unsafe.zrl), [`tests/error_reporting/err_raw_ptr_to_ref_let.zrl`](../../tests/error_reporting/err_raw_ptr_to_ref_let.zrl)).
- **Auto-Deref:** Taking a reference to a raw projection (`&p[i]` or `&p.field`) converts raw indirection into a safe borrow. This is gated on `unsafe_depth` in `lower_unary_expr` and `lower_expr`:
  - Proved by probe [`133_raw_ptr_index_borrow.zrl`](probes/133_raw_ptr_index_borrow.zrl) and [`tests/error_reporting/err_raw_ptr_index_borrow.zrl`](../../tests/error_reporting/err_raw_ptr_index_borrow.zrl).
- **Coercion Sites:** Passing `*T` where `&T` or `&mut T` is expected is caught by `check_raw_into_ref` across all direct syntactic positions:
  - Assignment: [`tests/error_reporting/err_raw_ptr_to_ref_assign.zrl`](../../tests/error_reporting/err_raw_ptr_to_ref_assign.zrl)
  - Return expression: [`tests/error_reporting/err_raw_ptr_to_ref_return.zrl`](../../tests/error_reporting/err_raw_ptr_to_ref_return.zrl)
  - Method/function argument: [`tests/error_reporting/err_raw_ptr_to_ref_method_arg.zrl`](../../tests/error_reporting/err_raw_ptr_to_ref_method_arg.zrl)
  - Struct field initialization: [`tests/error_reporting/err_raw_ptr_to_ref_struct_field.zrl`](../../tests/error_reporting/err_raw_ptr_to_ref_struct_field.zrl)
  - Block tail expression: [`tests/error_reporting/err_raw_ptr_to_ref_tail.zrl`](../../tests/error_reporting/err_raw_ptr_to_ref_tail.zrl)
  - An aggregate projection carries the raw type (`let t = (p, 1); let r: &i32 = t.0;`), so the conversion to a reference is a type error (probe [`158_launder_null_ref_tuple.zrl`](probes/158_launder_null_ref_tuple.zrl), `compile_reject`).
- **Generics:**
  - _Direct Cast:_ Casting `p as T` where `T` is a reference type parameter is rejected at compile time (probe [`108_raw_pointer_cast_to_reference_type_param.zrl`](probes/108_raw_pointer_cast_to_reference_type_param.zrl)).
  - A raw pointer passed through an identity generic function `fn id<T>(x: T) -> T` comes back raw (`let r: &i32 = id(p)`): monomorphization substitutes the argument's type, so the conversion is a type error (probe [`125_raw_pointer_to_reference_through_generic.zrl`](probes/125_raw_pointer_to_reference_through_generic.zrl), `compile_reject`; the accepted twin is [`tests/language/generics/type_param_instantiated_with_raw_pointer.zrl`](../../tests/language/generics/type_param_instantiated_with_raw_pointer.zrl)).
- **Closures:** Checked by `check_raw_into_ref` on closure argument and return boundaries.
- **Match Bindings:** Pattern matching does not provide reference-synthesizing patterns for raw pointers, and a pattern variable binding carries the pointer's type with it, so a dereference through the binding is gated (probes [`152_launder_raw_ptr_match_binding.zrl`](probes/152_launder_raw_ptr_match_binding.zrl), [`157_launder_raw_ptr_option_match.zrl`](probes/157_launder_raw_ptr_option_match.zrl), both `compile_reject`).
- **`defer`:** Deferred conversions or coercions are checked by `check_raw_into_ref`.
- **Cross-Module Imports:** Imported function signatures preserve pointer vs reference types, enforcing `check_raw_into_ref` at caller sites.

---

### 4.6 Complementary Low-Level Intrinsics: `@syscall` and `@alloca`

Two additional low-level built-ins bypass safe runtime semantics:

- **`@syscall` (§9.2):** Issues raw kernel system calls, which can map/unmap memory or read arbitrary pointers. Gated strictly at explicit syntax by `check_syscall_is_marked` in [`src/lower_zir/expr.zrl`](../../src/lower_zir/expr.zrl) (probes [`129_syscall_outside_unsafe.zrl`](probes/129_syscall_outside_unsafe.zrl), [`130_syscall_unsafe.zrl`](probes/130_syscall_unsafe.zrl), and [`tests/error_reporting/err_syscall_outside_unsafe.zrl`](../../tests/error_reporting/err_syscall_outside_unsafe.zrl)).
- **`@alloca` (§11.2.5):** Allocates uninitialized stack slots. Gated strictly at explicit syntax by `check_alloca_is_marked` in [`src/lower_zir/expr.zrl`](../../src/lower_zir/expr.zrl) (probes [`131_alloca_outside_unsafe.zrl`](probes/131_alloca_outside_unsafe.zrl), [`132_alloca_unsafe.zrl`](probes/132_alloca_unsafe.zrl), and [`tests/error_reporting/err_alloca_outside_unsafe.zrl`](../../tests/error_reporting/err_alloca_outside_unsafe.zrl)).

Neither intrinsic is reachable through auto-deref, coercion, generics, pattern matching, or cross-module export.

---

### 4.7 Raw Pointers Keep Their Type

The intermediate language gives raw pointers their own types (`RawPtr`, `RawPtrMut`) beside the reference types (`Ptr`, `PtrMut`), and every check that gates a raw pointer decides from that type. A raw pointer keeps it through every route a value can take: a type parameter and its instantiation, a tuple, struct or array and its projections, a pattern binding, and a closure's captured environment. So no route turns one into a reference without `unsafe`, and no route lets checked code dereference, index or project through one. The conversion routes are pinned by [`125_raw_pointer_to_reference_through_generic`](probes/125_raw_pointer_to_reference_through_generic.zrl), [`152_launder_raw_ptr_match_binding`](probes/152_launder_raw_ptr_match_binding.zrl), [`153_launder_raw_ptr_tuple`](probes/153_launder_raw_ptr_tuple.zrl), [`154_launder_raw_ptr_closure`](probes/154_launder_raw_ptr_closure.zrl), [`155_launder_raw_ptr_struct`](probes/155_launder_raw_ptr_struct.zrl), [`156_launder_raw_ptr_array`](probes/156_launder_raw_ptr_array.zrl), [`157_launder_raw_ptr_option_match`](probes/157_launder_raw_ptr_option_match.zrl), [`158_launder_null_ref_tuple`](probes/158_launder_null_ref_tuple.zrl), and the dereference routes by [`181_gap_raw_deref_after_tuple`](probes/181_gap_raw_deref_after_tuple.zrl), [`182_gap_raw_deref_after_generic_struct_field`](probes/182_gap_raw_deref_after_generic_struct_field.zrl), [`183_gap_raw_deref_after_array`](probes/183_gap_raw_deref_after_array.zrl), [`184_gap_raw_deref_after_generic`](probes/184_gap_raw_deref_after_generic.zrl), [`185_gap_raw_deref_after_closure`](probes/185_gap_raw_deref_after_closure.zrl); every one of them is `compile_reject`. No row of the matrix is marked **GAP**; the holes still open are the `known_gap` probes under [Known gaps](#known-gaps).

### 4.8 Implicit Conversions

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
  - Justification: The IL passes aggregates by reference while the surface language passes them by value, so `S` in a signature and `*S` in the SSA are the same thing. Neither matcher lets a _dereference_ through, which §4.1 decides from the pointer's type
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
  - Justification: A reference may be used where a raw pointer is expected, and the call site then needs `unsafe` (the raw-argument rule of §4.1), so the direction only _adds_ a requirement. Both mutability combinations are accepted, which is what `zilc`'s `current_func` field relies on
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
