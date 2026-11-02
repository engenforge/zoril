# Zoril Best Practices & Refactoring Guidelines

This document outlines software engineering best practices for maintaining a readable, robust, and manageable codebase in Zoril, along with concrete examples of how these practices have been applied to the compiler.

---

## 1. Core Best Practices

### A. Guard Clauses & Early Returns

Instead of nesting code inside deeply branching `if` structures for "happy path" execution, handle errors, validation checks, and base cases first, returning early. This aligns the primary execution path with the left margin of the function, reducing cognitive load.

- **Anti-Pattern (Deeply Nested):**
  ```zoril
  import "core.zrl";

  enum DigitError { Empty, NotADigit }

  fn parse_digit(s: [u8]) -> Result<u8, DigitError> {
      if s.len != 0 {
          let c = s[0];
          if c >= '0' as u8 && c <= '9' as u8 {
              return Result.Ok(c - '0' as u8);
          }
          return Result.Err(DigitError.NotADigit);
      }
      return Result.Err(DigitError.Empty);
  }
  ```
- **Best Practice (Early Return):**
  ```zoril
  import "core.zrl";

  enum DigitError { Empty, NotADigit }

  fn parse_digit(s: [u8]) -> Result<u8, DigitError> {
      if s.len == 0 { return Result.Err(DigitError.Empty); }

      let c = s[0];
      if c < '0' as u8 || c > '9' as u8 { return Result.Err(DigitError.NotADigit); }

      return Result.Ok(c - '0' as u8);
  }
  ```

### B. Single Responsibility & Decomposition

- **Functions:** A function should do exactly one thing. If a function is longer than 50–100 lines or has distinct logical "phases" divided by comments, those phases should be extracted into helper methods.
- **Modules:** Keep files functional and cohesive. Avoid "mega-modules" that exceed 2,000 lines of code. Split files by concern (e.g., separating parsing, type checking, statement lowering, and expression lowering).

### C. Self-Documenting Code over Explanatory Comments

- Use names that express intent (e.g., `is_primitive_type` rather than `check_type_less_than_12`).
- Comments should explain **why** a non-obvious design decision, performance optimization, or compiler hack was made, not **how** the code does it.

### D. Declarative Design & Tables

Where possible, replace long `if/else` or `match` cascades with static lookup tables or arrays. This is simpler to read and cheaper for the CPU to execute.

### E. Explicit Types over Magic Numbers & Sentinel Values

Avoid magic constants (like `0` or `0xffffffff as u32`) to denote failure or default states. Wrap values in `Option<T>` or `Result<T, E>` types to ensure type safety.

---

## 2. Idiomatic Zoril Language Patterns

Zoril's language constructs exist to catch memory-safety bugs (many rejected at compile time, known bounds errors trapped at run time), catch logic errors at compile time, and improve code structure; what is checked, and what is left to the programmer, is [What Zoril Checks](../SAFETY.md). The following patterns should be preferred in all Zoril codebases:

### A. Expression-Oriented block, if, and match

Zoril is expression-oriented: blocks, `if` statements, and `match` blocks all yield values. Instead of declaring uninitialized mutable variables and assigning to them within branches, assign or return the statement directly. This avoids uninitialized variables and simplifies variable scopes.

- **Preferred Style (Expression-Oriented):**
  ```zoril
  enum Status { Success, Failure }

  fn exit_code(status: Status) -> i32 {
      let code = match status {
          Status.Success => 0,
          Status.Failure => 1,
      };
      return code;
  }
  ```

### B. Exhaustive pattern matching (match over cascading if/else)

Cascading tag checks with `if/else` chains do not catch missing variants if a new type or enum is added. Always prefer `match` statements when dealing with sum types or enums. The compiler enforces exhaustiveness, alerting developers if a new variant is unhandled.

- **Preferred Style (Exhaustive Match):**
  ```zoril
  enum Shape {
      Circle(i64),
      Rectangle(i64, i64),
      Point,
  }

  fn corner_count(shape: Shape) -> i32 {
      return match shape {
          Shape.Circle(_) => 0,
          Shape.Rectangle(_, _) => 4,
          Shape.Point => 1,
      };
  }
  ```

### C. The `?` (Try) Operator for early error propagation

When dealing with functions returning `Result<T, E>`, avoid cascading `if/else` error checks. Use the `?` operator to cleanly unpack values on success or propagate errors immediately to the parent caller.

- **Preferred Style (Error Propagation):**
  ```zoril
  import "core.zrl";

  enum MathError { DivideByZero }

  fn safe_divide(a: i32, b: i32) -> Result<i32, MathError> {
      if b == 0 { return Result.Err(MathError.DivideByZero); }
      return Result.Ok(a / b);
  }

  fn half_ratio(a: i32, b: i32) -> Result<i32, MathError> {
      let quotient = safe_divide(a, b)?; // returns the Err to our caller
      return Result.Ok(quotient / 2);
  }
  ```

### D. Last-In First-Out (LIFO) `defer` blocks

For resource cleanup the compiler cannot infer (closing file descriptors, releasing raw handles), immediately register a `defer` block at the point of acquisition; owned resources such as `Arena` free through `Drop`. The compiler ensures `defer` expressions execute in reverse order at scope exit, so the cleanup also runs when the function returns early.

- **Preferred Style (Scope Cleanup):**
  ```zoril
  import "io.zrl";
  import "os/linux.zrl" as os_linux;
  use io::{close};
  use os_linux::open;

  fn load(path: [u8]) -> i32 {
      let fd = match open(path, 0, 0) {
          Ok(fd) => fd,
          Err(_) => { return 1; },
      };
      defer close(fd);

      let log = match open("load.log", 0, 0) {
          Ok(log) => log,
          Err(_) => { return 2; }, // fd closes
      };
      defer close(log);

      return 0; // log closes, then fd: deferred cleanup runs last-in-first-out
  }
  ```

### E. The `Drop` Trait Destructors

For structs that manage dynamically allocated memory or raw system resources, implement the `Drop` trait. Zoril calls `drop` when the resource falls out of scope, so an owned resource is released exactly once and without a manual `free()` call. (A `Drop` type can still leak deliberately; that is not a safety error.)

- **Preferred Style (Drop Destructor):**
  ```zoril
  import "io.zrl";
  use io::{Fd, close};

  struct Descriptor {
      fd: Fd,
  }

  impl Drop for Descriptor {
      fn drop(self: Descriptor) {
          if self.fd.unix_raw() >= 0 { let _ = close(self.fd); }
      }
  }
  ```

  The standard library's `io::File` closes its descriptor this way.

### F. Slices & Bounds-Checked Indexing

Avoid manual pointer arithmetic (`ptr as usize + offset`) wherever possible. Slices (`[T]`, `[mut T]`) carry bounds information and are automatically checked by the compiler during indexing to trap out-of-bounds accesses.

---

## 3. Case Studies: Architecture in Practice

The Zoril compiler demonstrates how these engineering principles are applied in a systems codebase:

### 1. Subsystem Decomposition

Complex compiler pipelines (such as lowering passes) are structured into cohesive sub-modules by responsibility:

- `decl.zrl`: Top-level declarations (functions, constants, types).
- `expr.zrl`: Recursive evaluation of expressions.
- `stmt.zrl`: Control flow and statement lowering.
- `match.zrl`: Pattern matching and destructuring logic.
- `utils.zrl`: Metadata lookups, helper operations, and SSA registries.

This modularity keeps individual files focused and maintainable.

### 2. Consolidated Diagnostic Formatting (DRY)

Repeated diagnostic formatting and error prefixing logic are consolidated into shared helper routines (such as `report_prefix`). This ensures uniform error formatting across the compiler and avoids duplicate string constants in binaries.

### 3. Shallow Nesting via Dedicated Helpers

Complex pattern matching and expression resolution routines avoid deep nesting by decomposing match arms into dedicated helper functions:

- `lower_pattern_ident`: Handles identifier pattern validation and binding.
- `lower_pattern_enum_variant`: Decodes variant checks and payload destructuring.
- `try_lower_enum_variant_member`: Resolves enum variants in member access expressions.
- `try_lower_impl_constant`: Resolves associated implementation constants.

Extracting these operations flattens control flow and keeps logic legible.

### 4. Consistent Module Imports

Imports across modules use explicit, consistent paths, ensuring unambiguous symbol resolution across targets and tools.
