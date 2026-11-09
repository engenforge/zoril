# What Zoril Checks, and What It Leaves to the Programmer

**Zoril is a small, self-hosted systems programming language that rejects many memory errors at compile time and traps known bounds errors at run time. This document lists what is checked and what is left to the programmer.**

Although Zoril was written to reject a large variety of memory safety errors, it is deliberately not described as "memory-safe" since it's still in early development and issues are being identified and resolved. Every memory safety claim below names a test that pins it, a large body of testing stands behind the claims (§5), and the remaining holes that are known are listed with examples (§6). Ordinary programs rarely meet them, and work is ongoing to close them.

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

Each item holds except through the known gaps in §6. Each names one or two tests that pin it. [`doc/spec/safety_model.md`](spec/safety_model.md) has the full matrix: 78 rows, each with the mechanism, where it is implemented, and every probe and test that proves it.

### 2.1 Ownership, moves and drops

- **A value cannot be used after it was moved, and a non-`Copy` value is dropped exactly once.** Which types move and which copy is in the [tour](tour.md#3-ownership-and-move-semantics). Pinned by [`73_double_drop_with_defer.zrl`](../bench/safety_matrix/probes/73_double_drop_with_defer.zrl) and [`143_defer_use_after_move.zrl`](../bench/safety_matrix/probes/143_defer_use_after_move.zrl).
- **A value cannot be moved out through a reference** (`return b.r` with `b: &B`), because the owner would still drop it. Pinned by [`71_move_out_of_shared_ref.zrl`](../bench/safety_matrix/probes/71_move_out_of_shared_ref.zrl).
- **A method that nothing calls is still checked** by a whole-program build ([`doc/spec/surface_syntax.md`](spec/surface_syntax.md) §11.1.1).

### 2.2 Borrows

- **A mutation cannot happen while a conflicting borrow is live**, and `&mut x` excludes every other active borrow of the place. This includes borrows taken through fields and through patterns (`if let`, `match`, `while let`). Pinned by [`57_shared_then_mut_borrow.zrl`](../bench/safety_matrix/probes/57_shared_then_mut_borrow.zrl) and [`58_two_mut_borrows.zrl`](../bench/safety_matrix/probes/58_two_mut_borrows.zrl).
- **A `&T` is read-only**, decided from its declared type rather than from where the value came from ([`doc/spec/unsafe_policy.md`](spec/unsafe_policy.md) §7). Pinned by [`tests/error_reporting/err_shared_ref_struct_field_write.zrl`](../tests/error_reporting/err_shared_ref_struct_field_write.zrl).

### 2.3 Stack regions and frames

- **A reference or pointer to this function's stack storage cannot leave the function**: not returned, not stored through an out-parameter, into a global or into a heap allocation, and not carried through a cast, a struct, a tuple, a slice or a local. Pinned by [`tests/error_reporting/ec_region_escape_return.zrl`](../tests/error_reporting/ec_region_escape_return.zrl) and probes [`44_dangling_stack_slice_store.zrl`](../bench/safety_matrix/probes/44_dangling_stack_slice_store.zrl) through [`53_dangling_stack_in_box.zrl`](../bench/safety_matrix/probes/53_dangling_stack_in_box.zrl).
- **A reference into storage a function owns (a collection, a box or an arena) cannot outlive the function.** A returned or stored view of a local collection is rejected whether or not the collection frees its buffer, and so is a view of a closure's owned capture stored where it outlives the call. Pinned by probes [`278_local_vec_buffer_returned.zrl`](../bench/safety_matrix/probes/278_local_vec_buffer_returned.zrl) through [`292_hashmap_view_returned.zrl`](../bench/safety_matrix/probes/292_hashmap_view_returned.zrl) and [`336_store_param_ref_slice_rejected.zrl`](../bench/safety_matrix/probes/336_store_param_ref_slice_rejected.zrl) through [`377_closure_shared_ref_referent_stored_out_accepted.zrl`](../bench/safety_matrix/probes/377_closure_shared_ref_referent_stored_out_accepted.zrl).
- **A reference into a `Box` the function owns and drops cannot be returned or stored where it outlives the call**; returning or moving the `Box` itself stays legal. Pinned by [`148_return_ref_to_local_box.zrl`](../bench/safety_matrix/probes/148_return_ref_to_local_box.zrl) and the accepted twin [`tests/language/memory/return_owned_box_positive.zrl`](../tests/language/memory/return_owned_box_positive.zrl).
- **A closure's environment cannot outlive its frame**: returning a capturing closure, passing it to an out-parameter, or storing it into caller or heap memory is rejected. Pinned by [`41_capturing_closure_to_fn.zrl`](../bench/safety_matrix/probes/41_capturing_closure_to_fn.zrl) and [`115_closure_returned_from_its_frame.zrl`](../bench/safety_matrix/probes/115_closure_returned_from_its_frame.zrl).

### 2.4 Arenas

- **Storage handed out by an arena is tied to that arena**: resetting or freeing the arena while a value from it is live, or letting an arena-backed collection outlive the arena's block, is a compile error. Pinned by [`128_arena_use_after_reset.zrl`](../bench/safety_matrix/probes/128_arena_use_after_reset.zrl) and [`159_arena_tied_collection_outlives_block.zrl`](../bench/safety_matrix/probes/159_arena_tied_collection_outlives_block.zrl).
- **A constant-size allocation that cannot fit a constant-size arena is rejected before the program runs**, within a function and across direct calls. Pinned by [`tests/error_reporting/err_arena_oom_compile_time.zrl`](../tests/error_reporting/err_arena_oom_compile_time.zrl) and [`tests/error_reporting/err_arena_oom_interprocedural.zrl`](../tests/error_reporting/err_arena_oom_interprocedural.zrl).

### 2.5 Types and conversions

- **Safe casts do not reinterpret memory**: `as` converts between compatible numeric types, between pointer types, and from a reference to a raw pointer, and a narrowing conversion that drops bits needs the explicit marker. Pinned by [`37_implicit_narrowing.zrl`](../bench/safety_matrix/probes/37_implicit_narrowing.zrl) and [`20_narrowing_cast.zrl`](../bench/safety_matrix/probes/20_narrowing_cast.zrl).
- **An enum value cannot be forged in checked code**: a cast to an enum type is rejected. Pinned by [`21_invalid_enum_tag.zrl`](../bench/safety_matrix/probes/21_invalid_enum_tag.zrl).
- **A constant index that is out of bounds is a compile error.** Pinned by [`tests/error_reporting/err_const_index_out_of_bounds.zrl`](../tests/error_reporting/err_const_index_out_of_bounds.zrl).
- **A `match` covers its cases**: exhaustiveness is verified before code generation, and guarded arms do not count toward it.

### 2.6 Linear resources

- **`fd` and `ioring` cannot be dropped implicitly, leaked, duplicated or closed twice**, not directly, not inside a struct, tuple, enum, array or box, and not on one path of a branch. Pinned by [`76_fd_leak.zrl`](../bench/safety_matrix/probes/76_fd_leak.zrl) and [`81_fd_closed_twice.zrl`](../bench/safety_matrix/probes/81_fd_closed_twice.zrl).

### 2.7 The `unsafe` boundary itself

- **Every operation the compiler cannot verify is unreachable from unmarked code.** The marker permits a fixed list of operations (§4.1) and disables no check: region, ownership, borrow, immutability and bounds checks all stay active inside an `unsafe` block ([`doc/spec/unsafe_policy.md`](spec/unsafe_policy.md) §1 is normative). Pinned by pairs of probes, one without the marker expecting a compile error and one inside `unsafe { }`: raw-pointer dereference ([`14_null_deref.zrl`](../bench/safety_matrix/probes/14_null_deref.zrl), [`31_null_deref_unsafe.zrl`](../bench/safety_matrix/probes/31_null_deref_unsafe.zrl)), raw-pointer indexing ([`12_raw_ptr_indexing.zrl`](../bench/safety_matrix/probes/12_raw_ptr_indexing.zrl)), forging a reference or a slice ([`123_raw_pointer_to_reference.zrl`](../bench/safety_matrix/probes/123_raw_pointer_to_reference.zrl), [`63_slice_forged_from_reference.zrl`](../bench/safety_matrix/probes/63_slice_forged_from_reference.zrl)), `extern` calls ([`140_extern_call_outside_unsafe.zrl`](../bench/safety_matrix/probes/140_extern_call_outside_unsafe.zrl)), `@syscall` ([`129_syscall_outside_unsafe.zrl`](../bench/safety_matrix/probes/129_syscall_outside_unsafe.zrl)) and `@alloca` ([`131_alloca_outside_unsafe.zrl`](../bench/safety_matrix/probes/131_alloca_outside_unsafe.zrl)).
- **Creating a raw pointer is safe** (`n as *T`); every use of one is gated on the pointer's own type. Pinned by [`187_int_to_raw_ptr_cast_safe.zrl`](../bench/safety_matrix/probes/187_int_to_raw_ptr_cast_safe.zrl).

---

## 3. Checked at run time

Some checks cannot be made at compile time without rejecting correct programs. The compiler emits them, and a failure ends the process where it happens; nothing after it runs. The exit statuses (134, 136, 139) are what Linux reports, `128 + signal`, so a system without signals reports its own status for the same failures.

- **The generated traps exit 134** (`128 + SIGABRT`), distinct from a program that merely returned non-zero:
  - array and slice bounds, read and write ([`08_oob_array_read.zrl`](../bench/safety_matrix/probes/08_oob_array_read.zrl), [`10_oob_array_write.zrl`](../bench/safety_matrix/probes/10_oob_array_write.zrl), [`11_oob_slice_write.zrl`](../bench/safety_matrix/probes/11_oob_slice_write.zrl), [`tests/language/memory/bounds_array_oob.zrl`](../tests/language/memory/bounds_array_oob.zrl));
  - a variable shift count outside `[0, width)` (a constant one is a compile error) ([`19_shift_overflow.zrl`](../bench/safety_matrix/probes/19_shift_overflow.zrl));
  - the checked standard-library arithmetic that would otherwise forge a length or size: an allocation size that wraps ([`161_arena_allocator_size_wrap.zrl`](../bench/safety_matrix/probes/161_arena_allocator_size_wrap.zrl)), a capacity that overflows ([`163_vec_capacity_overflow.zrl`](../bench/safety_matrix/probes/163_vec_capacity_overflow.zrl)), and `Vec::set_len` above the capacity ([`165_vec_set_len_above_cap.zrl`](../bench/safety_matrix/probes/165_vec_set_len_above_cap.zrl)). Only the capacity check is reached from checked code; the other two are `unsafe fn`s, where the trap is better than a forged length but not something checked code can rely on.
- **`panic:` exits 1; memory exhaustion exits 134.** `Option::unwrap` and `Result::unwrap` on the wrong variant and the print helpers (`print`, `println`, `eprint`, `eprintln`) print `panic: <message>` and exit 1. An arena allocation the runtime cannot honour and a mapping the kernel refuses exit 134, like a bounds trap. `zoril_abort()`, reached on an unreachable fall-through, exits 1.
- **Some failures are faults, not traps**, with no source location:
  - integer division or modulo by zero, and `INT_MIN / -1`, die with `SIGFPE` (exit 136) ([`16_div_by_zero.zrl`](../bench/safety_matrix/probes/16_div_by_zero.zrl), [`18_signed_div_overflow.zrl`](../bench/safety_matrix/probes/18_signed_div_overflow.zrl));
  - unbounded recursion touches the guard page and dies with `SIGSEGV` (exit 139); there is no stack probe and no recursion limit ([`25_stack_overflow.zrl`](../bench/safety_matrix/probes/25_stack_overflow.zrl));
  - a single stack frame larger than the guard-page gap faults on its first access ([`254_large_stack_frame_faults.zrl`](../bench/safety_matrix/probes/254_large_stack_frame_faults.zrl)); a program that needs a buffer that large allocates it in an arena.
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
6. forging a slice from a pointer and a length (`@slice(p, n)`), except where the length is a literal `0`.

Calling an **`unsafe fn`** is a seventh route: a function is `unsafe fn` when it requires a precondition the type system cannot prove (in `stdlib/`, for example `Vec::set_len`, `zoril_allocator_alloc`, `arena_free` and the `*_raw` entry points; §5.3 counts them). Inside these operations nothing is checked. `@slice` is the sharp one, because every later `s[i]` through that slice reads as ordinary checked code.

### 4.2 Trusted claims that are not operations

- **`#[borrows(..)]`** on a function narrows which arguments a returned reference keeps borrowed. The compiler rejects the visible contradiction ([`93_borrows_attribute_lie.zrl`](../bench/safety_matrix/probes/93_borrows_attribute_lie.zrl)); whether a pointer loaded _through_ a parameter really outlives it is the author's promise.
- **A `*mut T` read out of a `&T` stays writable.** `&T` is read-only for writes that land in its own referent, not for a different unchecked pointer stored there ([`doc/spec/unsafe_policy.md`](spec/unsafe_policy.md) §7). Zoril has no `UnsafeCell`, so there is no sanctioned interior mutability through `&T`.

### 4.3 Arithmetic and control flow

- **Integer overflow wraps** modulo 2^N by design ([`tests/language/basic/wrapping_arithmetic.zrl`](../tests/language/basic/wrapping_arithmetic.zrl)).
- **Division by zero and stack exhaustion fault deterministically but are not handled** (§3): the process ends without running its `defer` blocks.
- **`@shl_wrap` / `@shr_wrap`** mask a shift count to the operand's width; that is the explicit opt-out from the shift check.

### 4.4 Limits of the static analyses

Where an analysis cannot decide, it answers conservatively and rejects a program that a more precise analysis would accept; the cost is precision, not soundness. The checkers have 26 such places. In 12 the conservative answer is the design. The other 14 are places where an unknown could have been accepted; each now answers conservatively and is pinned by a probe or test and a mutation check, so none is open. One of them is copied in a second checker that runs later, and no test can tell that copy's answer apart, because the first checker has already rejected every program it would matter for. The first point below is the measured result: the conservative answers cost no annotation anywhere in this tree.

- **No program in this tree needed a lifetime annotation** to satisfy the checker: `src/`, `stdlib/`, `tools/`, the example JSON app, the corpus and the test suites. That is a measurement over this tree's programs, not a claim that annotations are unnecessary in general. Separate compilation is where an unknown interface actually arises; its evidence is an incremental scenario, not a corpus.
- **Outside the claim:** the frozen bootstrap compilers, the hand-written interface summaries and the runtime's assembly.

### 4.5 Memory leaks and collection lifecycles

Memory is not checked for leaks. Collections (`Vec`, `String`, `ByteVec`, `HashMap`) have no `Drop`: one that is not `free`d, nor built in an arena, leaks its buffer at scope end. A `Box` leaks too: in this release it is not freed when it goes out of scope, and the boxed value's `Drop` does not run (freeing at scope end is planned; [Known Issues](../KNOWN_ISSUES.md)). Only linear resources (`fd`, `ioring`) must be closed on every path. Build short-lived collections in an arena (`Vec::new_in(&arena)`) or call `free()` when finished.

### 4.6 Not applicable rather than unchecked

- **Data races:** the core language and runtime are single-threaded, so the property is not applicable rather than checked. Reading and writing a scalar `static mut` needs no `unsafe` because of that; the rule will change when threads arrive. A `static mut` of any other type is read, written or borrowed only inside `unsafe` ([`264_static_mut_borrow_across_call.zrl`](../bench/safety_matrix/probes/264_static_mut_borrow_across_call.zrl) through [`272_immutable_static_enum.zrl`](../bench/safety_matrix/probes/272_immutable_static_enum.zrl)).
- The other limits of `v0.1.0-alpha` (the bootstrap dialect, QBE's code-generation limits, the Linux x86-64 target, what separate compilation does not check) are in [`KNOWN_ISSUES.md`](../KNOWN_ISSUES.md).

### 4.7 The FFI boundary

An `extern` declaration is the unsafe contract. The compiler checks the shape of its types (only C-safe ones; slices, references, `Box`, aggregates by value, `char` and `fd` are errors that name what to pass instead) and extends a small result to its declared type, but it cannot see the C signature. Measured with `cc`:

- **Declare the type C returns.** A small result (`u8`/`i8`/`u16`/`i16`/`bool`) is extended before use, so a C function that leaves the upper bits undefined is read correctly. Declaring a _wider_ Zoril type than C returns reads bits the ABI leaves undefined.
- **A `bool` result is a C `_Bool` (0 or 1).** A C `int` returning 2 declared `-> bool` gives a `bool` holding 2, and a two-armed `match` on it reaches `zoril_abort` (exit 1): a program lost, not memory corrupted.
- **There is no nullable C function pointer.** Calling a null one inside `unsafe` faults (measured 139); an API that accepts NULL takes a second signature or a plain `*mut u8`. A raw pointer may become a C function pointer only inside `unsafe`; an integer never may (probes 273-277).
- **An exported symbol is the process's definition.** The compiler rejects exporting the symbols the runtime defines and the common libc names; a libc name outside that set (measured: `printf`) can still be exported and would interpose libc's in a hosted program.
- **A hand-written `.zri` is trusted.** It can carry `#[export]`, which makes the declarations it holds callable without `unsafe`; an interface is outside the safety claim.
- **A callback re-enters the Zoril code that called C.** A scalar `static mut` is a shared cell, so a callback may write one while a `&mut` to it is live up the stack. The runtime is single-threaded: a callback invoked from another C thread or a signal handler runs unsynchronized Zoril code, so keep callbacks on the calling thread.
- **A callback's userdata is a raw pointer.** Handing C a pointer into a frame that is about to return, and letting C fire the callback later, is use-after-return. An API that can fire after the registering call must clear the callback before the frame returns, as the platform-layer template does (`tests/platform_layer/include/platform.zrl`, pinned by `scripts/test_platform_layer.sh`).

---

## 5. The testing behind this

### 5.1 The safety matrix

The repository keeps 488 probes in [`bench/safety_matrix/probes/`](../bench/safety_matrix/probes), each recording its expectation in its first lines: **355 `compile_reject`**, **70 `accept`**, **8 `runtime_trap`**, **11 `runtime_fault`**, and **44 `known_gap`**. `scripts/run_safety_matrix.sh` runs all of them and fails when an observation differs from the recorded expectation; `make test` gates it (`safety-matrix`) together with `safety-model`, which keeps [`doc/spec/safety_model.md`](spec/safety_model.md) and the probes consistent in both directions.

Each matrix row carries an evidence level: **6 rows at `routes`**, **72 at `example`**, and **0 at `fuzzed`** or `argued`. `example` means the cited probes fire the mechanism on the shapes they name; `routes` means every route the row lists is named by a cited `compile_reject` probe (`scripts/check_route_coverage.sh`); `fuzzed` adds generated programs for the row's routes, and `argued` adds an argument that the invariant holds for every route. The levels are defined in [`safety_model.md`](spec/safety_model.md) and validated by `scripts/check_safety_model.sh`.

Mutation counts are not cited here, and fuzzing is cited only from the record in [`bench/fuzz/README.md`](../bench/fuzz/README.md).

### 5.2 Fuzzing

The fuzzer generates programs from the subset Zoril and Rust share, compiles and runs each one, and checks the result against several oracles: a `rustc` differential oracle for programs Zoril accepts, expected values computed by the generator, the runtime trap checks, the checked build and drop accounting. [`bench/fuzz/README.md`](../bench/fuzz/README.md) describes it and holds the records.

- **The release bar** is a fixed budget of generated programs that compile and run with no fault and no accepted program the oracle flags. **2,638,155** programs compiled and ran against a bar of 2,500,000 (7,056,025 generated in `--mode mix`, seeds 1-882000 x 8 over 16 workers, 17 h 31 min of wall time), with 0 faults and 0 candidates, and 80 of 80 features covered. It ran on the previous code; the compiler has changed since, so its fingerprint names other code.
- **On the code released here,** a shorter `--release` session compiled and ran **755,772** of 1,976,026 generated programs (seeds 1-247000 x 8, 16 workers, 7 h 14 min), and built every one both whole-program and with an installed `zbuild`: 2,731,822 builds compared, 0 disagreements, with 0 faults, 0 candidates and 94 of 94 features covered. A full release-bar run on this code is planned soon, and its record will replace the short session's. `scripts/check_fuzz_fresh.sh` says which record describes the sources in the tree.
- **What it reaches:** 94 declared features covering ownership and moves, borrows and their ends, writes through a `&mut`, references in structs, tuples, `Option`s, arrays and slices, closures that capture owning values, `Box`, `Drop` types, arenas and collections tied to an arena, raw pointers in structs, function-pointer calls, pattern destructuring and the capability-mismatch family. Each program enables a random half of the builders (swarm testing), and the 28 known-hole shapes are ordinary builders too.
- **What it does not reach:** programs are small (about 30 lines), use a little of the standard library, never write `defer`, have `id<T>` as their only generic, and contain no `unsafe`, so the `unsafe` boundary with everything in §4.1 is not fuzzed. A budget bounds what was tried; it does not bound the language.

### 5.3 The trusted base

Safe code is only as good as the `unsafe` code under it, so the project measures its own boundary. `scripts/check_safety_figures.sh` prints these figures and fails `make test` when they and the tree disagree.

| Figure                           | Value  |
| -------------------------------- | ------ |
| stdlib modules                   | 30     |
| stdlib lines                     | 6,263  |
| stdlib `unsafe { }` blocks       | 170    |
| stdlib modules with such a block | 23     |
| stdlib `unsafe fn` declarations  | 63     |
| of those, public                 | 59     |
| compiler modules                 | 50     |
| compiler lines                   | 46,845 |
| compiler `unsafe { }` blocks     | 843    |

How each one is counted: every `.zrl` file under the directory, recursively; **lines** are physical lines (`wc -l`); **`unsafe { }` blocks** are occurrences of `unsafe` followed by `{` on the same line; **`unsafe fn` declarations** are lines that start with `unsafe fn` or `pub unsafe fn`. That is a different question from `scripts/marker_density.sh`, which counts raw-pointer dereference sites over non-comment lines (58 marker lines for `stdlib`, 264 for `src`).

- **The standard library** holds 170 `unsafe { }` blocks in 23 of its 30 modules. Every one states the invariant it relies on in a `// SAFETY:` comment, and `scripts/check_safety_comments.sh` fails `make test` when a block does not. The comments are a review artifact, not a proof.
- **An audit of those invariants** asked which of them checked code could break. Five could, all of one shape (arithmetic or a field the block trusted): a `Vec` capacity that overflowed to zero ([`163_vec_capacity_overflow.zrl`](../bench/safety_matrix/probes/163_vec_capacity_overflow.zrl)), an allocation size that wrapped ([`161_arena_allocator_size_wrap.zrl`](../bench/safety_matrix/probes/161_arena_allocator_size_wrap.zrl)), a string `sub` skipping its clamp ([`tests/stdlib/test_stdlib_str_sub_clamp.zrl`](../tests/stdlib/test_stdlib_str_sub_clamp.zrl)), an `Args::get` index truncated to `i32` ([`162_args_get_index_truncation.zrl`](../bench/safety_matrix/probes/162_args_get_index_truncation.zrl)), and a public `Vec::len` field ([`164_vec_len_forge.zrl`](../bench/safety_matrix/probes/164_vec_len_forge.zrl)). Sizes now go through `mem::size_of_n` and `grow_cap`, which trap instead of wrapping, and the collections' fields are private behind narrow accessors.
- **The compiler** is 50 modules of Zoril, with 843 `unsafe { }` blocks, because a self-hosted compiler also carries its own allocator and IL machinery. The calibration against rustc and Rust's standard library is in [`doc/spec/unsafe_policy.md`](spec/unsafe_policy.md) §5, with about 2-3% line density for `src/` as the target. `rt/runtime.s` and the hand-written summaries are outside the verifier.
- **An application written against the safe interface needs no `unsafe` at all.** An example JSON tool written in Zoril (a CLI to query, format and validate JSON; 9 modules and 1,992 non-comment lines; not yet published) holds **0 `unsafe { }` blocks** and measures 0.00% under `scripts/marker_density.sh`. Its test suite fails if an `unsafe` block returns.

---

## 6. Known gaps in checked code

The matrix has no row marked `GAP`. The holes that remain open in checked code are tracked as 43 `known_gap` probes in [`bench/safety_matrix/probes/`](../bench/safety_matrix/probes) and listed in the [Known gaps](spec/safety_model.md#known-gaps) table. Ordinary code rarely reaches them: each needs a view of storage the function owns (or a reference to its stack) to be stored or returned through one of the routes below. They are known, and the unified provenance model planned for after the launch is meant to close all of them. For example, this function is accepted although the arena dies when it returns while `out` keeps the view (class A, [`gap_07_path_same_param.zrl`](../bench/safety_matrix/probes/gap_07_path_same_param.zrl)):

```zoril,no-test
fn stash_pair(p: (&mut [i32], [i32])) { *p.0 = p.1; }

fn escape_storer(out: &mut [i32]) {
    let mut a = match Arena.new(65536) { Result.Ok(a) => a, Result.Err(_) => { return; } };
    let mut v = Vec::<i32>.new_in(&a);
    v.push(42);
    stash_pair((out, v.as_slice()));  // the destination and the view travel in one parameter
}                                     // accepted: `a` is gone, `out` still views its storage
```

The open classes:

- **(A) Same-parameter destination and value:** when one parameter carries both an external destination and a borrowed source, the store check allows storing a frame view into external storage ([`gap_07_path_same_param.zrl`](../bench/safety_matrix/probes/gap_07_path_same_param.zrl)), also when the parameter is a struct of references through which the callee copies between two of the caller's locals ([`gap_53_same_param_struct_copy.zrl`](../bench/safety_matrix/probes/gap_53_same_param_struct_copy.zrl)).
- **(B) Unrecognised external destinations:** a destination reached through a closure call that returns a mutable reference is missed ([`gap_29_dest_closure_call_returns_mut_ref.zrl`](../bench/safety_matrix/probes/gap_29_dest_closure_call_returns_mut_ref.zrl)).
- **(C) Closures storing frame views:** a closure storing a frame-owned view through a captured mutable reference is accepted ([`gap_11_dest_closure_capture_mut.zrl`](../bench/safety_matrix/probes/gap_11_dest_closure_capture_mut.zrl)), and so is one storing it through a caller's `&mut` held in a local struct that the closure reaches through one or more local references ([`gap_47_closure_ref_struct_mutref_escape.zrl`](../bench/safety_matrix/probes/gap_47_closure_ref_struct_mutref_escape.zrl), [`gap_48_closure_ref_ref_struct_mutref_escape.zrl`](../bench/safety_matrix/probes/gap_48_closure_ref_ref_struct_mutref_escape.zrl)), and so is one that forwards a captured frame view to a named callee storing it through the closure's own parameter ([`gap_55_closure_param_forwards_view.zrl`](../bench/safety_matrix/probes/gap_55_closure_param_forwards_view.zrl)), and so is one handed to a function that calls it ([`gap_52_closure_passed_to_caller_of_fn_value.zrl`](../bench/safety_matrix/probes/gap_52_closure_passed_to_caller_of_fn_value.zrl)), also when what it stores is a captured frame address and the destination a global ([`gap_64_closure_global_store_via_fn_param.zrl`](../bench/safety_matrix/probes/gap_64_closure_global_store_via_fn_param.zrl)).
- **(D) Two-axis aggregate and path combinations:** a reference to a stack local, an element reference, or a stack-capturing closure carried through an enum payload, a `fn` value or a 65th parameter loses provenance and is accepted ([`gap_13_ref_local_enum_payload.zrl`](../bench/safety_matrix/probes/gap_13_ref_local_enum_payload.zrl), [`gap_36_carrier_ref_enum_payload_match.zrl`](../bench/safety_matrix/probes/gap_36_carrier_ref_enum_payload_match.zrl), [`gap_16_ref_local_fn_val.zrl`](../bench/safety_matrix/probes/gap_16_ref_local_fn_val.zrl), [`gap_18_elem_ref_enum_payload.zrl`](../bench/safety_matrix/probes/gap_18_elem_ref_enum_payload.zrl), [`gap_21_elem_ref_fn_val.zrl`](../bench/safety_matrix/probes/gap_21_elem_ref_fn_val.zrl), [`gap_23_closure_local_enum_payload.zrl`](../bench/safety_matrix/probes/gap_23_closure_local_enum_payload.zrl), [`gap_26_closure_local_fn_val.zrl`](../bench/safety_matrix/probes/gap_26_closure_local_fn_val.zrl), [`gap_27_closure_local_param_65.zrl`](../bench/safety_matrix/probes/gap_27_closure_local_param_65.zrl)).
- **(E) Call summary limits:** a store inside mutually recursive calls has no interprocedural fixpoint, parameters beyond the 64-parameter limit drop provenance, a callee compiled separately records an empty store summary in its `.zri`, and a store destination reached through a call result and passed to a writing callee leaves the caller's store summary empty ([`gap_28_call_summary_mutual_recursion.zrl`](../bench/safety_matrix/probes/gap_28_call_summary_mutual_recursion.zrl), [`gap_54_cycle_store_through_local.zrl`](../bench/safety_matrix/probes/gap_54_cycle_store_through_local.zrl), [`gap_33_param_65_arena_slice_store.zrl`](../bench/safety_matrix/probes/gap_33_param_65_arena_slice_store.zrl), [`gap_49_call_ret_mutref_callee_write.zrl`](../bench/safety_matrix/probes/gap_49_call_ret_mutref_callee_write.zrl), [`gap_50_call_ret_struct_callee_write_slot.zrl`](../bench/safety_matrix/probes/gap_50_call_ret_struct_callee_write_slot.zrl), [`gap_51_call_ret_struct_field_callee_write.zrl`](../bench/safety_matrix/probes/gap_51_call_ret_struct_field_callee_write.zrl)).
- **(F) Storing what by-value owning parameters own:** a view into a `Vec` passed by value is accepted for a store into caller memory ([`gap_32_byval_collection_param_store.zrl`](../bench/safety_matrix/probes/gap_32_byval_collection_param_store.zrl)), and so is a `Vec` made in an `Arena` passed by value and pushed into the caller's `Vec`, read after the arena is freed ([`gap_62_byval_arena_param_vec_pushed.zrl`](../bench/safety_matrix/probes/gap_62_byval_arena_param_vec_pushed.zrl)).
- **(G) Stores into a local or a Box's contents through a pointer to it:** a view written into a local struct's field through a local `&mut`, a `&mut` parameter of a callee, or `self` in a method, or into a field of a Box's contents, is not recorded as a borrow the struct or box holds, so an arena reset passes while the field is read ([`gap_37_local_mutref_field_reset.zrl`](../bench/safety_matrix/probes/gap_37_local_mutref_field_reset.zrl), [`gap_38_param_field_reset.zrl`](../bench/safety_matrix/probes/gap_38_param_field_reset.zrl), [`gap_39_method_self_field_reset.zrl`](../bench/safety_matrix/probes/gap_39_method_self_field_reset.zrl), [`gap_43_box_field_reset.zrl`](../bench/safety_matrix/probes/gap_43_box_field_reset.zrl)); and a frame view written the same way through a local `&mut`, a callee's `&mut` parameter or into a Box's contents is accepted when it is then stored out ([`gap_40_local_mutref_field_escape.zrl`](../bench/safety_matrix/probes/gap_40_local_mutref_field_escape.zrl), [`gap_41_callee_field_escape.zrl`](../bench/safety_matrix/probes/gap_41_callee_field_escape.zrl), [`gap_42_box_field_escape.zrl`](../bench/safety_matrix/probes/gap_42_box_field_escape.zrl)), or by a closure that captured a local `&mut` to the struct ([`gap_45_closure_mutref_field_escape.zrl`](../bench/safety_matrix/probes/gap_45_closure_mutref_field_escape.zrl)).
- **(H) `#[borrows()]` across a reset:** a `#[borrows()]` method returning a view its receiver holds gives a result that holds no borrow, so an arena reset passes while the result is read; the store form of the same laundering is refused ([`gap_30_borrows_attribute_launder.zrl`](../bench/safety_matrix/probes/gap_30_borrows_attribute_launder.zrl)), but the result's liveness is not checked ([`gap_44_borrows_attr_reset.zrl`](../bench/safety_matrix/probes/gap_44_borrows_attr_reset.zrl)).
- **(I) Stores hidden behind an `extern` copy:** a safe function that copies reference-carrying elements with `memcpy` and declares no `#[stores]` stores them where no summary sees it: `Vec.extend_from_slice` puts views of the caller's stack frame into a longer-lived `Vec` ([`gap_56_extern_copy_extend_from_slice.zrl`](../bench/safety_matrix/probes/gap_56_extern_copy_extend_from_slice.zrl)).
- **(J) Payloads bound through a reference to a local enum:** a `match` or `if let` on a reference binds the payload by reference, a pointer into the enum; when the enum is a local, returning the binding is accepted, directly ([`gap_57_match_ref_local_enum_binding_returned.zrl`](../bench/safety_matrix/probes/gap_57_match_ref_local_enum_binding_returned.zrl)) or through an accessor that matches on its reference parameter ([`gap_58_match_ref_accessor_local_enum_returned.zrl`](../bench/safety_matrix/probes/gap_58_match_ref_accessor_local_enum_returned.zrl)).
- **(K) Owners holding frame views, moved out:** a local `Vec` whose elements are views of a stack array is accepted when it is pushed into the caller's `Vec` ([`gap_59_pushed_vec_holding_frame_views.zrl`](../bench/safety_matrix/probes/gap_59_pushed_vec_holding_frame_views.zrl)), passed by value to a callee that pushes it ([`gap_60_vec_holding_frame_views_moved_to_pushing_callee.zrl`](../bench/safety_matrix/probes/gap_60_vec_holding_frame_views_moved_to_pushing_callee.zrl)), or wrapped in a struct first ([`gap_61_struct_wrapping_vec_of_frame_views_pushed.zrl`](../bench/safety_matrix/probes/gap_61_struct_wrapping_vec_of_frame_views_pushed.zrl)); and a `Vec` a callee builds around a view of a caller-local `Vec`'s buffer is accepted when the callee stores it into the caller's slot ([`gap_63_vec_built_around_param_view_in_callee.zrl`](../bench/safety_matrix/probes/gap_63_vec_built_around_param_view_in_callee.zrl)).
- **(L) A generic instance made into a `fn` value:** `id::<i32>` written as a value rather than called is accepted but lowers to nothing, so `let f: fn(i32) -> i32 = id::<i32>;` leaves the value uninitialized and the call jumps through stack garbage ([`gap_66_generic_instance_as_fn_value_uninit.zrl`](../bench/safety_matrix/probes/gap_66_generic_instance_as_fn_value_uninit.zrl)).
- **(M) An `extern` function made into a `fn` value:** a bare `extern` converts to a plain `fn` type with no `unsafe` block, so safe code calls C through the value while a direct call needs `unsafe`; a safe callee hands `memset` a forged pointer and the write faults ([`gap_67_extern_fn_as_fn_value.zrl`](../bench/safety_matrix/probes/gap_67_extern_fn_as_fn_value.zrl)).

---

## 7. What is not claimed, and how this page is kept true

- **Not claimed:** that these categories are complete, that no hole exists, or that any statement here holds for `unsafe` code, the frozen bootstrap compilers, or a program shape this tree and its fuzzer budget did not exercise. The matrix's practice is to treat a row as closed only when the programs that motivated it are re-run unchanged and no longer build.
- Every public page that makes a safety statement either links to the tier it belongs to or says what the compiler checks. Phrases such as "memory-safe" as an unqualified property, "guarantees memory safety", "provably" and "no dangling pointers" are not used without the tier and the test behind them, nor are "eliminates" and "prevents" in a sentence that names a memory-bug class (use-after-free, dangling, double free, leak, data race, overflow, out-of-bounds, an escaping address); the `safety-model` gate (`scripts/check_safety_model.sh` in `make test`) fails a build when one appears on a line without an explicit allowlist comment.
- Every number here has a source of record: the safety matrix and its probes, the Known gaps table, [`bench/fuzz/README.md`](../bench/fuzz/README.md). Two gates enforce it: `safety-figures` (`scripts/check_safety_figures.sh`) recomputes every §5.3 figure from the tree, and `fuzz-fresh` (`scripts/check_fuzz_fresh.sh`) checks the record's fingerprint against `src/`, `stdlib/`, `tools/zilc/`, `tools/zbuild/` and `rt/` and that every page quoting the record's headline figure quotes the same one.
- A new safety claim names the test behind it (`CONTRIBUTING.md`).
