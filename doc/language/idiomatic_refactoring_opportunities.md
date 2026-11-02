# Zoril Idiomatic Patterns and Architecture Guidelines

This document establishes core software engineering patterns and architectural guidelines for writing and maintaining idiomatic Zoril codebases. These principles guide both application development and ongoing compiler maintenance, ensuring code remains robust, readable, and aligned with Zoril's safety model.

---

## 1. Prefer Slices and Indexed Access over Raw Pointer Arithmetic

- **Anti-Pattern (Raw Pointer Arithmetic):** Calculating element offsets using raw pointer arithmetic and type casts:
  ```zoril,no-test
  let p = (self.types as usize + (self.type_count as usize) *% sizeof(Type)) as *mut Type;
  ```
  This pattern is verbose, requires `unsafe` gating, and bypasses bounds checking.

- **Idiomatic Pattern (Slices and Indexed Access):** Use Zoril Slices (`[T]`, `[mut T]`) or native array indexing syntax (`array[i]`). Slices provide safe, bounds-checked views over contiguous memory:
  ```zoril,no-test
  let elem = self.types[i];
  ```
  Where dynamic resizing is required, encapsulate memory within standard collections like `Vec<T>`.

---

## 2. Encapsulate Dynamic Storage in `Vec<T>`

- **Anti-Pattern (Manual Triplet Fields):** Manually managing dynamic buffers using triplet fields (`_ptr`, `_len`, `_cap`) and manual allocator calls across disparate structs:
  ```zoril,no-test
  struct Buffer {
      items_ptr: *mut Item,
      items_len: usize,
      items_cap: usize,
  }
  ```
  Duplicating allocation, reallocation, and growth formulas across multiple structures increases the surface area for memory errors and capacity bugs.

- **Idiomatic Pattern (Standard Collection Encapsulation):** Encapsulate dynamically sized collections inside standard containers (such as `Vec<T>` from `stdlib/vec.zrl` or arena-backed buffers). This centralizes reallocation and capacity growth logic in one well-tested location, keeps container structs lean, and guarantees deterministic cleanup.

---

## 3. Represent Absence and Failure with `Option<T>` and `Result<T, E>`

- **Anti-Pattern (Null Pointers and Sentinel Values):** Returning null pointers (`0 as *mut T`) or numeric sentinel values (`0xffffffff as u32`, `-1 as i32`) to denote failure or missing entries. This requires manual checks that the compiler cannot statically enforce, risking null-dereference faults or ignored error states.

- **Idiomatic Pattern (Algebraic Types):** Use `Option<T>` for values that may be absent and `Result<T, E>` for operations that can fail:
  ```zoril,no-test
  fn find_symbol(name: [u8]) -> Option<SymbolId> { ... }
  fn parse_number(s: [u8]) -> Result<i64, ParseError> { ... }
  ```
  This engages Zoril's type system, requiring callers to explicitly handle all cases using `match` or propagate errors using `?`.

---

## 4. Use Named Constants and Descriptive Accessors

- **Anti-Pattern (Magic Numbers):** Hardcoding literal numbers for primitive type IDs, flags, or configuration values throughout application logic:
  ```zoril,no-test
  if ty_id == 15 { ... } // Magic number representing Unit
  ```

- **Idiomatic Pattern (Named Constants & Helpers):** Declare explicit named constants or expressive helper accessors:
  ```zoril,no-test
  const TYPE_ID_UNIT: u32 = 15;
  // or
  if module.is_unit_type(ty_id) { ... }
  ```
  Named constants make code self-documenting and avoid bugs when internal identifiers are reordered.

---

## 5. Pervasive Use of `match` for Sum Types and Enums

- **Anti-Pattern (Cascading Tag Checks):** Inspecting enums with manual tag comparisons or cascading `if/else` ladders:
  ```zoril,no-test
  if val.tag == TAG_EXPR { ... }
  else if val.tag == TAG_STMT { ... }
  ```
  Cascading checks cannot verify if new variants are handled when the enum evolves.

- **Idiomatic Pattern (Exhaustive Pattern Matching):** Use `match` statements across all sum types (`AST`, `Type`, `ILInstr`, `Token`):
  ```zoril,no-test
  match node {
      AstNode.Expr(e) => handle_expr(e),
      AstNode.Stmt(s) => handle_stmt(s),
      AstNode.Decl(d) => handle_decl(d),
  }
  ```
  Zoril enforces exhaustiveness checking on `match` expressions at compile time, guaranteeing that newly added variants are never silently omitted.

---

## 6. Decompose Subsystems into Cohesive Modules

- **Anti-Pattern (Monolithic Modules):** Creating monolithic files ("mega-modules" exceeding 2,000+ lines) that blend high-level AST traversals, symbol resolution, expression evaluation, and backend emission into a single file.

- **Idiomatic Pattern (Single-Responsibility Subsystems):** Structure subsystems into functionally focused, cohesive modules with clear boundaries. For example, a compiler lowering pass is cleanly divided by responsibility:
  - **Declarations:** Top-level modules, functions, constants, and types.
  - **Statements:** Control flow, loops, and statement sequencing.
  - **Expressions:** Recursive expression evaluation and intermediate values.
  - **Pattern Matching:** Destructuring and variant matching logic.
  - **Utilities:** Metadata lookups, SSA registries, and helper operations.

  This separation of concerns makes subsystems easier to navigate, test in isolation, and audit.

---

## 7. Isolate Complex Subsystems into Dedicated Handlers

- **Anti-Pattern (Interleaved Complex Logic):** Inlining specialized subsystem logic (such as generic monomorphization, symbol mangling, or macro expansion) directly into general-purpose expression evaluators or call handlers.

- **Idiomatic Pattern (Dedicated Subsystem Handlers):** Encapsulate specialized pipelines into dedicated structures with explicit interfaces:
  ```zoril,no-test
  struct Monomorphizer { ... }

  impl Monomorphizer {
      pub fn instantiate_fn(self: &mut Monomorphizer, fn_id: FnId, type_args: [Type]) -> FnId { ... }
      pub fn instantiate_type(self: &mut Monomorphizer, ty_id: TypeId, type_args: [Type]) -> TypeId { ... }
  }
  ```
  This isolates template instantiation and caching from general instruction emission, avoiding duplicated logic.

---

## 8. Use Structured Builders for Intermediate Representations

- **Anti-Pattern (Ad-Hoc Manual Emission):** Manually allocating low-level instructions and types via ad-hoc manipulation of module internals:
  ```zoril,no-test
  (*module).alloc_type(...);
  module.emit(...);
  ```

- **Idiomatic Pattern (Declarative Builder Abstraction):** Use declarative builder abstractions (`ILBuilder`) that expose clean, type-safe APIs for constructing intermediate representations:
  ```zoril,no-test
  builder.emit_call(callee, args);
  builder.get_ptr_type(inner_ty);
  ```
  Builders hide low-level layout details, reduce boilerplate, and enforce representation invariants at construction time.

---

## Summary

Adhering to these patterns—leveraging native slices, `Vec<T>`, `Option<T>`/`Result<T, E>`, exhaustive `match`, and structured modularity—produces code that is safe, maintainable, and idiomatic. These guidelines ensure that both compiler passes and user-space applications leverage the full expressive power and compile-time guarantees of the Zoril language.
