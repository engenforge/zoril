# What Zoril Checks, and What It Leaves to the Programmer

**Zoril is a small, self-hosted systems programming language that rejects many memory errors at compile time and traps known bounds errors at run time. This document lists what is checked and what is left to the programmer.**

Although Zoril was written to reject a large variety of memory safety errors, it is deliberately not described as "memory-safe" since it's still in early development and issues are being identified and resolved. Every memory safety claim below is backed by the verified safety matrix (§5), and the remaining holes that are known are explained in §6. Ordinary programs rarely meet them, and work is ongoing to close them.

---

## 1. In short

Code outside an `unsafe` block is **checked code**: the compiler's goal is that checked code cannot corrupt memory. That is a goal, not a guarantee. The compiler has known memory safety holes (§6) and likely unknown holes as well, so there is still a chance that checked code can make a memory error in rare circumstances. An `unsafe` block allows a short list of operations the compiler cannot verify, and there the programmer is the checker.

Zoril checks in three ways:

1. **At compile time (§2).** Where possible the compiler rejects memory errors in checked code: a value used after it was moved, a reference that outlives the storage it points into, and an arena reset while a value from it is live are compile errors. Which types move and which copy is in the [tour](tour.md#3-ownership-and-move-semantics).

   _Use of moved value: passing a `String` to a function hands it over_

   ```zoril,compile-fail
   import "string.zrl";
   use string::String;

   fn send(msg: String) {}

   fn main() -> i32 {
       let msg = String.new();
       send(msg);
       return msg.len() as i32; // error: use of moved value 'msg'
   }
   ```

   _A borrow that outlives a change: `push` may move the buffer `best` points into_

   ```zoril,compile-fail
   import "vec.zrl";
   use vec::Vec;

   fn main() -> i32 {
       let mut scores = Vec::<i32>.new();
       scores.push(90);
       let best = scores.get(0);
       scores.push(75); // error: cannot mutably borrow 'scores' while it is already borrowed
       return match best {
           Option.Some(s) => *s,
           Option.None => 0,
       };
   }
   ```

2. **At run time (§3).** An index outside an array or slice ends the process with exit status 134 at the access, and nothing after it runs. Some failures that cannot be checked cheaply, such as division by zero, end the process with a fault instead. These traps apply everywhere, `unsafe` blocks included.

3. **Where the checks stop (§4, §6).** An `unsafe` block disables no check: everything above still applies inside it. It adds permission for a fixed list of operations the compiler cannot verify (§4.1): dereferencing raw pointers, calling C, making a system call, and a few others. Those operations are the programmer's responsibility. The standard library needs them for system calls and C interfaces, and Zoril's intent is to keep them contained there, thoroughly reviewed and tested, so that ordinary programs need no `unsafe` at all. The other place the checks stop is the known gaps in checked code (§6), where the compiler accepts something it should reject.

The checks run in every build; there is no release mode that turns them off. A statement that is not in §2 or §3 is not checked.

---

## 2. What the compiler rejects in checked code

Each item holds except through the known gaps in §6. The normative specification is [`doc/spec/safety_model.md`](spec/safety_model.md), and every property's backing probes are tabulated in [`bench/safety_matrix/matrix.md`](../bench/safety_matrix/matrix.md) and [`bench/safety_matrix/README.md`](../bench/safety_matrix/README.md).

### 2.1 Ownership, moves and drops

- **A value cannot be used after it was moved, and a non-`Copy` value is dropped exactly once.** Which types move and which copy is in the [tour](tour.md#3-ownership-and-move-semantics).
- **A value cannot be moved out through a reference** (`return b.r` with `b: &B`), because the owner would still drop it.
- **A method that nothing calls is still checked** by a whole-program build ([`doc/spec/surface_syntax.md`](spec/surface_syntax.md) §11.1.1).

### 2.2 Borrows

- **A mutation cannot happen while a conflicting borrow is live**, and `&mut x` excludes every other active borrow of the place. This includes borrows taken through fields and through patterns (`if let`, `match`, `while let`).
- **A `&T` is read-only**, decided from its declared type rather than from where the value came from ([`doc/spec/unsafe_policy.md`](spec/unsafe_policy.md) §7).

### 2.3 Stack regions and frames

- **A reference or pointer to this function's stack storage cannot leave the function**: not returned, not stored through an out-parameter, into a global or into a heap allocation, and not carried through a cast, a struct, a tuple, a slice or a local.
- **A reference into storage a function owns (a collection, a box or an arena) cannot outlive the function.** A returned or stored view of a local collection is rejected whether or not the collection frees its buffer, and so is a view of a closure's owned capture stored where it outlives the call.
- **A reference into a `Box` the function owns and drops cannot be returned or stored where it outlives the call**; returning or moving the `Box` itself stays legal.
- **A closure's environment cannot outlive its frame**: returning a capturing closure, passing it to an out-parameter, or storing it into caller or heap memory is rejected.

### 2.4 Arenas

- **Storage handed out by an arena is tied to that arena**: resetting or freeing the arena while a value from it is live, or letting an arena-backed collection outlive the arena's block, is a compile error.
- **A constant-size allocation that cannot fit a constant-size arena is rejected before the program runs**, within a function and across direct calls.

### 2.5 Types and conversions

- **Safe casts do not reinterpret memory**: `as` converts between compatible numeric types, between pointer types, and from a reference to a raw pointer, and a narrowing conversion that drops bits needs the explicit marker.
- **An enum value cannot be forged in checked code**: a cast to an enum type is rejected.
- **A constant index that is out of bounds is a compile error.**
- **A `match` covers its cases**: exhaustiveness is verified before code generation, and guarded arms do not count toward it.

### 2.6 Linear resources

- **`fd` and `ioring` cannot be dropped implicitly, leaked, duplicated or closed twice**, not directly, not inside a struct, tuple, enum, array or box, and not on one path of a branch.

### 2.7 The `unsafe` boundary itself

- **Every operation the compiler cannot verify is unreachable from unmarked code.** The marker permits a fixed list of operations (§4.1) and disables no check: region, ownership, borrow, immutability and bounds checks all stay active inside an `unsafe` block ([`doc/spec/unsafe_policy.md`](spec/unsafe_policy.md) §1 is normative).
- **Creating a raw pointer is safe** (`n as *T`); every use of one is gated on the pointer's own type.

---

## 3. Checked at run time

Some checks cannot be made at compile time without rejecting correct programs. The compiler emits them, and a failure ends the process where it happens; nothing after it runs. The exit statuses (134, 136, 139) are what Linux reports, `128 + signal`, so a system without signals reports its own status for the same failures.

- **The generated traps exit 134** (`128 + SIGABRT`), distinct from a program that merely returned non-zero:
  - array and slice bounds, read and write;
  - a variable shift count outside `[0, width)` (a constant one is a compile error);
  - checked standard-library arithmetic that would otherwise forge a length or size (an allocation size that wraps, a capacity that overflows, and `Vec::set_len` above the capacity; only the capacity check is reached from checked code).
- **`panic:` exits 1; memory exhaustion exits 134.** `Option::unwrap` and `Result::unwrap` on the wrong variant and the print helpers (`print`, `println`, `eprint`, `eprintln`) print `panic: <message>` and exit 1. An arena allocation the runtime cannot honour and a mapping the kernel refuses exit 134, like a bounds trap. `zoril_abort()`, reached on an unreachable fall-through, exits 1.
- **Some failures are faults, not traps**, with no source location:
  - integer division or modulo by zero, and `INT_MIN / -1`, die with `SIGFPE` (exit 136);
  - unbounded recursion touches the guard page and dies with `SIGSEGV` (exit 139); there is no stack probe and no recursion limit;
  - a single stack frame larger than the guard-page gap faults on its first access; a program that needs a buffer that large allocates it in an arena.
- **A trap does not run deferred code.** `defer` blocks run on normal block exit and function return; a trap ends the process without them.
- **There is one build configuration.** The runtime checks are never compiled out ([`doc/spec/unsafe_policy.md`](spec/unsafe_policy.md) §6).

---

## 4. The programmer's job

This is the list that matters most for judging the language.

### 4.1 Everything inside `unsafe`

`unsafe` marks a fixed set of operations the compiler cannot verify ([`doc/spec/unsafe_policy.md`](spec/unsafe_policy.md) §1 is normative):

1. dereferencing a raw pointer (`*p`, `&*p`, `p[i]`, `p.field`, a method call through it), including implicitly;
2. making a **reference or a slice** out of an integer, a pointer or a type parameter (`@ptr_cast<&T>`, `@ptr_from_int<&T>`, `@ptr_cast<[T]>`);
3. calling an `extern` function;
4. a system call (`@syscall`);
5. an uninitialized stack slot (`@alloca<T>(1)`);
6. forging a slice from a pointer and a length (`@slice(p, n)`), except where the length is a literal `0`;
7. casting a number to `bool` or `char`.

Calling an **`unsafe fn`** (or converting one into a `fn` value) is an additional route: a function is `unsafe fn` when it requires a precondition the type system cannot prove (in `stdlib/`, for example `Vec::set_len`, `zoril_allocator_alloc`, `arena_free`, and the `*_raw` entry points). Inside these operations nothing is checked. `@slice` is the sharp one, because every later `s[i]` through that slice reads as ordinary checked code.

### 4.2 Trusted claims that are not operations

- **`#[borrows(..)]`** on a function narrows which arguments a returned reference keeps borrowed. The compiler rejects visible contradictions; whether a pointer loaded _through_ a parameter really outlives it is the author's promise. **`#[unsafe(borrows(..))]`** and **`#[unsafe(stores(..))]`** mark trusted contracts that the compiler accepts on the author's word (`doc/spec/unsafe_policy.md` §1).
- **A `*mut T` read out of a `&T` stays writable.** `&T` is read-only for writes that land in its own referent, not for a different unchecked pointer stored there ([`doc/spec/unsafe_policy.md`](spec/unsafe_policy.md) §7). Zoril has no `UnsafeCell`, so there is no sanctioned interior mutability through `&T`.

### 4.3 Arithmetic and control flow

- **Integer overflow wraps** modulo $2^N$ by design.
- **Division by zero and stack exhaustion fault deterministically but are not handled** (§3): the process ends without running its `defer` blocks.
- **`@shl_wrap` / `@shr_wrap`** mask a shift count to the operand's width; that is the explicit opt-out from the shift check.

### 4.4 Limits of the static analyses

Where an analysis cannot decide, it answers conservatively and rejects a program that a more precise analysis would accept; the cost is precision, not soundness. The checkers have 26 such places: in 12 the conservative answer is the design, and the other 14 are places where an unknown could have been accepted and each now answers conservatively and is pinned by a test and a mutation check.

- **No program in this tree needed a lifetime annotation** to satisfy the checker: `src/`, `stdlib/`, `tools/`, the example JSON app, the corpus and the test suites. That is a measurement over this tree's programs, not a claim that annotations are unnecessary in general. Separate compilation is where an unknown interface actually arises; its evidence is incremental scenarios rather than a single corpus.
- **Outside the claim:** the frozen bootstrap compilers, the hand-written interface summaries and the runtime's assembly.

### 4.5 Memory leaks and collection lifecycles

Memory is not checked for leaks. Collections (`Vec`, `String`, `ByteVec`, `HashMap`) have no `Drop`: one that is not `free`d, nor built in an arena, leaks its buffer at scope end. A `Box` leaks too: in this release it is not freed when it goes out of scope, and the boxed value's `Drop` does not run (freeing at scope end is planned; [Known Issues](../KNOWN_ISSUES.md)). Only linear resources (`fd`, `ioring`) must be closed on every path. Build short-lived collections in an arena (`Vec::new_in(&arena)`) or call `free()` when finished.

### 4.6 Not applicable rather than unchecked

- **Data races:** the core language and runtime are single-threaded, so the property is not applicable rather than checked. Reading and writing a scalar `static mut` needs no `unsafe` because of that; the rule will change when threads arrive. A `static mut` of any other type is read, written or borrowed only inside `unsafe`.
- The other limits of `v0.1.0-alpha` (the bootstrap dialect, QBE's code-generation limits, the Linux x86-64 target, what separate compilation does not check) are in [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md).

### 4.7 The FFI boundary

An `extern` declaration is the unsafe contract. The compiler checks the shape of its types (only C-safe ones; slices, references, `Box`, aggregates by value, `char` and `fd` are errors that name what to pass instead) and extends a small result to its declared type, but it cannot see the C signature. Measured with `cc`:

- **Declare the type C returns.** A small result (`u8`/`i8`/`u16`/`i16`/`bool`) is extended before use, so a C function that leaves the upper bits undefined is read correctly. Declaring a _wider_ Zoril type than C returns reads bits the ABI leaves undefined.
- **A `bool` result is a C `_Bool` (0 or 1).** A C `int` returning 2 declared `-> bool` gives a `bool` holding 2, and a two-armed `match` on it reaches `zoril_abort` (exit 1): a program lost, not memory corrupted.
- **There is no nullable C function pointer.** Calling a null one inside `unsafe` faults (exit 139); an API that accepts NULL takes a second signature or a plain `*mut u8`. A raw pointer may become a C function pointer only inside `unsafe`; an integer never may.
- **An exported symbol is the process's definition.** The compiler rejects exporting the symbols the runtime defines and the common libc names; a libc name outside that set (for example `printf`) can still be exported and would interpose libc's in a hosted program.
- **A hand-written `.zri` is trusted.** It can carry `#[export]`, which makes the declarations it holds callable without `unsafe`; an interface is outside the safety claim.
- **A callback re-enters the Zoril code that called C.** A scalar `static mut` is a shared cell, so a callback may write one while a `&mut` to it is live up the stack. The runtime is single-threaded: a callback invoked from another C thread or a signal handler runs unsynchronized Zoril code, so keep callbacks on the calling thread.
- **A callback's userdata is a raw pointer.** Handing C a pointer into a frame that is about to return, and letting C fire the callback later, is use-after-return. An API that can fire after the registering call must clear the callback before the frame returns, as the platform-layer template does (`scripts/test_platform_layer.sh`).

---

## 5. The testing behind this

Every safety claim above is backed by automated verification kept in sync with the repository (`make test` and `make preflight`):

- **Safety matrix and route coverage:** Every row of the safety matrix is backed by executable probes run in both whole-program mode (`make safety-matrix`) and modular `zbuild` mode (`safety-matrix-zbuild`), with `scripts/check_route_coverage.sh` verifying that `routes`-level rows exercise every listed IR/CFG route.
- **Store grid and `--checked` instrumentation:** The compositional store grid checks frame-escape combinations across build modes, while `make test-checked` rebuilds the test suites and probes under `zoril --checked` (which poisons released arena space, expired local slots, dropped values, and freed heap blocks) to turn silent dangling reads into observable traps or faults.
- **Trusted-base `// SAFETY:` audit:** Every `unsafe { }` block in `stdlib/` carries an inline `// SAFETY:` invariant checked by `scripts/check_safety_comments.sh`, and `scripts/check_safety_figures.sh` tracks the trusted-base census and `unsafe` line density across `src/` and `stdlib/` (with application code expected to stay at 0% density).
- **Differential fuzzing against `rustc`:** `scripts/fuzz_safe.sh` generates programs in the shared Zoril/Rust subset and judges them against crash, value-canary, drop-accounting, expected-value, expected-trap, `--checked`, `zbuild` mode-diff, and `rustc` differential oracles.

Live probe counts, trusted-base census figures, and the ZIR/ZIL route reachability audit live in [`bench/safety_matrix/README.md`](../bench/safety_matrix/README.md), and the fuzzing records and coverage reports live in [`bench/fuzz/README.md`](../bench/fuzz/README.md).

---

## 6. Known gaps in checked code

The matrix has no row marked `GAP`, and no `known_gap` probes remain open: the unified provenance rules (`doc/design/provenance.md`) and the two-tier liveness model now run by default beside the existing checks, closing the indirect frame/owner escape, `#[borrows()]` narrowing, and loose raw-pointer store probes.

The verification ledger and probe inventory live in [`bench/safety_matrix/README.md#known-gaps`](../bench/safety_matrix/README.md#known-gaps).

---

## 7. What is not claimed, and how this page is kept true

- **Not claimed:** that these categories are complete, that no hole exists, or that any statement here holds for `unsafe` code, the frozen bootstrap compilers, or a program shape this tree and its fuzzer budget did not exercise. A safety-matrix row closes only when the programs that motivated it are re-run unchanged and no longer build.
- Every public page that makes a safety statement either links to the tier it belongs to or says what the compiler checks. Phrases such as "memory-safe" as an unqualified property, "guarantees memory safety", "provably" and "no dangling pointers" are not used without the tier and the test behind them, nor are "eliminates" and "prevents" in a sentence that names a memory-bug class (use-after-free, dangling, double free, leak, data race, overflow, out-of-bounds, an escaping address); the `safety-model` gate (`scripts/check_safety_model.sh`) fails when one appears without an explicit allowlist comment.
- Live counts and records have their sources of record in [`bench/safety_matrix/README.md`](../bench/safety_matrix/README.md), [`bench/safety_matrix/matrix.md`](../bench/safety_matrix/matrix.md), and [`bench/fuzz/README.md`](../bench/fuzz/README.md), enforced by `safety-model`, `safety-figures` (`scripts/check_safety_figures.sh`), and `fuzz-fresh` (`scripts/check_fuzz_fresh.sh`).
- A new safety claim names the test behind it in the verification ledger (`CONTRIBUTING.md`).
