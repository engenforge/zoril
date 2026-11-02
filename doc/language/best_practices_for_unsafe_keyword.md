# The Role and Scoping of `unsafe` in Systems Languages

This document surveys how modern systems programming languages (such as Rust and Zoril) define the role and boundaries of `unsafe` code blocks, and outlines best practices for scoping unsafe operations.

---

## 1. The Philosophy of `unsafe`

In systems programming languages with compile-time safety verification, the `unsafe` keyword is not an escape hatch or an indicator of defective design; it is a fundamental tool for interacting with the hardware and building safe abstractions.

Compilers use conservative static analysis. Any verifier that rejects memory-safety violations must reject some programs that are valid but whose safety cannot be statically proven. The `unsafe` keyword marks blocks where the programmer takes explicit responsibility for upholding invariants the compiler cannot automatically verify.

---

## 2. When `unsafe` is Required

In low-level systems programming, `unsafe` blocks are typically required for:

1. **Foreign Function Interfaces (FFI):** Interoperating with C, assembly, or OS syscalls where the compiler cannot analyze foreign calling conventions or pointer invariants.
2. **Direct Hardware and Memory Mapping:** Accessing physical MMIO registers, page tables, or OS-level shared memory regions.
3. **Core Data Structure Primitives:** Implementing growable buffers (`Vec`), hash tables, ring buffers, or intrusive collections that require raw pointers and custom allocation logic.
4. **Performance-Critical Transformations:** Performing unchecked pointer arithmetic or casting when preconditions have already been proven by surrounding invariants.

---

## 3. The Safe Abstraction Principle

The defining pattern in modern safe systems languages is the **safe abstraction**:

- **Strict Containment:** `unsafe` code must be minimized and confined to the smallest feasible scope (e.g., individual functions or internal helper routines).
- **Publicly Safe Interfaces:** The outer interface presented to consumers must be completely safe. A user calling public APIs without the `unsafe` keyword should never be able to trigger memory corruption or undefined behavior.
- **Application Logic Should Be 100% Safe:** Standard application software (parsers, web backends, CLI tools, compilers) should generally contain zero `unsafe` blocks, relying instead on safe standard library collections and interfaces.

---

## 4. `unsafe` in Zoril

Zoril follows this safe abstraction philosophy with a minimal, explicit definition:

- **Strict Gating:** In Zoril, `unsafe { ... }` gates exactly six low-level operations:
  1. Dereferencing raw pointers (`*p`, and a method or field access through one).
  2. Indexing raw pointers (`p[i]`).
  3. Making a reference or a slice out of an integer or a raw pointer (`@ptr_cast<&T>`, `@ptr_from_int<&T>`, `@ptr_cast<[T]>`).
  4. Unchecked slice construction (`@slice`).
  5. Foreign C function invocation (`extern fn`).
  6. A raw system call (`@syscall`) and an uninitialized stack slot (`@alloca`). _Creating_ a raw pointer (`n as *T`, `@ptr_from_int<*T>`, `@ptr_cast<*T>`, `@int_cast<U>`) needs no marker: every _use_ of the pointer is gated, so the marker belongs on the use (`doc/spec/unsafe_policy.md` §1).
- **Active Verifier:** Type checking, borrow checking, and linear resource verification remain fully active inside `unsafe` blocks; only the specific gated primitive operations are enabled.
- **Auditable Marker Density:** Compiler verification gates continuously track unsafe marker density across the entire codebase (`scripts/marker_density.sh`), ensuring low-level primitives remain tightly localized.
