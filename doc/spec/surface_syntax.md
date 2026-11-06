# Zoril Surface Language Specification

This document specifies the surface language as of `v0.1.0-alpha`.

## 1. Overview

Zoril is a statically-typed, imperative systems programming language with ownership checking and expression-oriented syntax; [What Zoril Checks](../SAFETY.md) lists what is checked and what is left to the programmer. The surface language compiles to Zoril IL, which is then verified and lowered to machine code via the QBE backend.

- **File extension**: `.zrl`
- **Compiler binary**: `build/zoril` (self-hosted Zoril compiler), `bootstrap/stage0-c/build/zoril-c` (bootstrap C implementation)
- **Target**: Linux x86_64 (via QBE)
- **Paradigm**: Imperative with functional influences (expression-oriented, immutable-by-default, sum types, pattern matching, traits)
- **Gotchas and subtleties**: See [`doc/language/gotchas_and_subtleties.md`](../language/gotchas_and_subtleties.md) for detailed comparisons with C and Rust (operator precedence, reference mutability, array copying semantics).

## 2. Lexical Elements

### 2.1 Keywords (31) and reserved words (9)

```
fn       let      mut      return   as
if       else     while    for      in
loop     break    continue defer    match
struct   enum     type     trait    impl
box      const    static   import   pub
extern   sizeof   alignof  try      unsafe
use
```

`true` and `false` are boolean literals (§2.3), not keyword tokens.

Nine more words are **reserved**: `async`, `await`, `dyn`, `move`, `where`, `yield`, `macro`, `union` and `super`. Each is a compile error wherever it appears — "`async` is a reserved word, kept for a future feature" — and is not an identifier. Reserving them is what lets a future feature add the word without breaking a program that used it as a name; before 1.0 the set can grow (it never shrinks), and every addition is listed in `KNOWN_ISSUES.md`.

### 2.2 Comments

- Single-line: `// comment`
- Multi-line: `/* comment */` (supports nesting: `/* /* inner */ */`)

### 2.3 Literals

| Kind      | Examples                                                                  |
| --------- | ------------------------------------------------------------------------- |
| Integer   | `0`, `42`, `255`, `0xFF`, `0b1010`, `0o755`, `1_000_000`, `0u64`, `42i32` |
| Float     | `3.14`, `0.5`, `1_000.5`, `1.0f32`, `2.5f64`                              |
| Boolean   | `true`, `false`                                                           |
| String    | `"hello\n"`, `r"C:\path\to\file"`                                         |
| Character | `'a'`, `'\n'`, `'\x41'`                                                   |

Numeric literals may contain underscores (`_`) as visual separators. Integer literals support binary (`0b`), octal (`0o`), and hexadecimal (`0x`) prefixes. Both integer and floating-point literals support alphanumeric suffixes to specify types:

- **Integer suffixes**: `u8`, `u16`, `u32`, `u64`, `i8`, `i16`, `i32`, `i64`
- **Float suffixes**: `f32`, `f64`

A float literal is the double nearest its decimal value, as in C (`0.3` is not `0.1 + 0.2`). It is an `f32` with that suffix or where an `f32` is expected (`let c: f32 = 0.25;`), else an `f64`; an integer literal where a float is expected is that float (`let d: f64 = 5;`).

String escape sequences: `\n`, `\t`, `\r`, `\0`, `\\`, `\"`, `\'`, `\xHH`.

**Raw Strings**: Strings prefixed with `r` (e.g., `r"raw\string"`) do not interpret escape sequences. Backslashes are treated as literal characters. Raw strings also support unescaped multiline content.

Character literals are syntactic sugar for integer constants (type `u8`).

### 2.4 Annotations

Annotations begin with `@` and modify the following expression or statement:

| Annotation               | Meaning                                                                                                     |
| ------------------------ | ----------------------------------------------------------------------------------------------------------- |
| `@likely`                | Branch prediction hint (taken path)                                                                         |
| `@unlikely`              | Branch prediction hint (not-taken path)                                                                     |
| `@syscall(num, args...)` | Direct Linux system call                                                                                    |
| `@drop(x)`               | Manual resource consumption                                                                                 |
| `@slice(ptr, len)`       | Construct a slice fat pointer from a pointer and length (`unsafe` unless `len` is literally 0)              |
| `@ptr_cast<*T>(expr)`    | Reinterpret-cast a value to pointer type `*T` (unsafe to produce a `&T` or a slice; safe for a raw pointer) |
| `@ptr_from_int<*T>(n)`   | Read an integer `n` as a raw pointer of type `*T` (safe; every use of the pointer needs `unsafe`)           |
| `@int_cast<U>(expr)`     | Reinterpret-cast a value to integer type `U` (safe)                                                         |
| `@str("literal")`        | A `Str` (`str.zrl`) holding the literal; invalid UTF-8 is a compile error                                   |

### 2.5 Attributes

Attributes begin with `#[]` and modify the following declaration:

- **`#[must_use]`**: Emits a compiler warning if the return value of this function is discarded.
- **`#[derive(Clone)]`**: On a struct: generates its field-by-field `Clone` impl (§8.5).
- **`#[borrows(p, ...)]`**: On a function: the reference it returns points into these parameters only; `#[borrows()]` into none of them (§7.2).
- **`#[stores(p -> q, ...)]`**: On a function: the body stores parameter `p`'s own storage into `q`'s memory. No arrow means `self`; `-> static` means a global. Checked against the body's computed store summary when the body is verified, so a false one is an error in its own module; a `pub fn` that stores a reference parameter without declaring it warns, naming the attribute to add (§7.2).
- **`#[fresh]`**: On an `unsafe fn` whose result type is written as a raw pointer (`*T` or `*mut T`; an alias of one is refused, since the rule is on the written type): each call returns memory that no other live pointer reaches and that the caller owns, such as an allocator's anonymous `mmap`, or a value that is no valid address (a failure the caller tests for before use, as `mmap_anon`'s -errno). It is the author's claim, not checked, like any `unsafe` obligation ([`unsafe_policy.md`](unsafe_policy.md) §1). The provenance rules read it (`doc/design/provenance.md` §3, _Raw operations_): a call's result does not count as memory outside the frame for the address the function made from an integer; every other origin of the result is still checked. That the memory is fresh is not checked, only where the attribute is written. On a safe function, a function returning anything else, or an item that is not a function it is an error. An interface (`.zri`) keeps it.

One more attribute exists but is not part of the checked-code surface: `#[summary(...)]`, which the compiler writes into a `.zri` interface to describe a body's storage behaviour.

The borrow checker's arena epoch exemption recognizes `mem::Arena::mark` and `mem::Arena::reset_to` by _where the declaration was loaded from_ - a module of the standard library, module identity `stdlib/..` - and their names, never by a user file's name: a library of your own in a file called `mem.zrl` gets no exemption and its `reset_to` conflicts with every live borrow of the value ([`probe 218`](../../bench/safety_matrix/probes/218_fake_mem_arena_spoof.zrl)).

Example:

```zoril
#[must_use]
fn allocate_resource() -> i32 { return 1; }

fn use_val(x: i32) {}

fn main() {
    let r = allocate_resource();
    use_val(r);                  // Correct: result is used

    allocate_resource();         // Warning: unused result from #[must_use] function 'allocate_resource'

    let x = allocate_resource(); // Warning: x is unused (result is still considered discarded)

    let _ = allocate_resource(); // Correct: explicit discard via wildcard suppresses warning
}
```

### 2.6 Operators and Punctuation

#### Unary Operators (Prec 25)

| Operator    | Meaning             |
| ----------- | ------------------- |
| `-expr`     | Arithmetic negation |
| `!expr`     | Logical/bitwise NOT |
| `*expr`     | Pointer dereference |
| `&expr`     | Immutable borrow    |
| `&mut expr` | Mutable borrow      |

The `&` and `&mut` operators create a borrow of the given expression. If the expression is a local variable of type `T`, the result is `&T`.

**A `Box` is not converted to a reference implicitly.** A `Box<T>` or a `&Box<T>` given where `&T` is expected is a type error; borrow the contents with `&*b` (or `&mut *b`) ([`tests/error_reporting/err_box_moved_into_borrow.zrl`](../../tests/error_reporting/err_box_moved_into_borrow.zrl)). Field access and method calls do reach through a `Box`: `b.x` and `b.sum()` act on the boxed value.

#### Postfix Operators (Prec 21)

| Operator      | Meaning                              |
| ------------- | ------------------------------------ |
| `expr.field`  | Member access                        |
| `expr.0`      | Tuple element access (numeric index) |
| `expr[index]` | Array/slice indexing                 |
| `expr(args)`  | Function call                        |
| `expr?`       | Try operator (early return on error) |

#### Type Cast (Prec 20)

| Operator    | Meaning            |
| ----------- | ------------------ |
| `expr as T` | Explicit type cast |

#### Binary Operators (by precedence, highest first)

Zoril uses Rust's operator ordering: the bitwise operators bind tighter than comparisons, so `x & MASK != 0` means `(x & MASK) != 0` (unlike C, where `!=` binds tighter; see [`doc/language/gotchas_and_subtleties.md`](../language/gotchas_and_subtleties.md#2-operator-precedence-rust-precedence-not-c)).

| Prec | Operators                                                                  | Associativity               |
| ---- | -------------------------------------------------------------------------- | --------------------------- |
| 9    | `*` `/` `%` `*%`                                                           | Left                        |
| 8    | `+` `-` `+%` `-%`                                                          | Left                        |
| 7    | `<<` `>>`                                                                  | Left                        |
| 6    | `&` (bitwise AND)                                                          | Left                        |
| 5    | `^` (bitwise XOR)                                                          | Left                        |
| 4    | `\|` (bitwise OR)                                                          | Left                        |
| 3    | `==` `!=` `<` `<=` `>` `>=`                                                | Non-associative (see below) |
| 2    | `&&` (logical AND, short-circuit)                                          | Left                        |
| 1    | `\|\|` (logical OR, short-circuit)                                         | Left                        |
| 0    | `=` `+=` `-=` `*=` `/=` `%=` `&=` `\|=` `^=` `<<=` `>>=` `+%=` `-%=` `*%=` | Right                       |

Precedence 3 is non-associative: `a < b < c` is a parse error (use `a < b && b < c`); parenthesized groupings like `(a < b) == (c < d)` are fine.

`bool` does not mix with the integer types: binary operators reject operand pairs where exactly one side is `bool`, arithmetic/shift/relational operators reject `bool` entirely (`==`, `!=`, `&`, `|`, `^` work on two bools), `&&`/`||` require `bool`, and `if`/`while` conditions must be `bool`-typed expressions. Convert explicitly with `as` where integer/bool interplay is intended.

Standard arithmetic operators (`+`, `-`, `*`) perform **wrapping (two's-complement modular) arithmetic** in all build modes, matching C/QBE semantics; overflow does not panic. Use the explicit wrapping operators (`+%`, `-%`, `*%`) to document that wraparound is intentional — they behave identically to the plain operators today, but keep code meaning stable if a future compiler version adds opt-in overflow checking to the plain operators.

The `==` and `!=` operators work on pointer types (`*T`, `*mut T`, `Box<T>`): two pointers compare equal if they hold the same address. Null-pointer checks use `0 as *T` as the sentinel:

```zoril
fn check_ptr(p: *i32, q: *i32) -> bool {
    let null: *i32 = 0 as *i32;
    if p == null { return true; }   // null check
    if p != q   { return true; }    // identity check
    return false;
}
```

`==` and `!=` are defined for these operand types, and rejected at compile time for all others ([`tests/error_reporting/err_binary_operand_types.zrl`](../../tests/error_reporting/err_binary_operand_types.zrl)):

- Integers, `bool`, `char` and floats compare by value; pointers by address.
- Fieldless enums compare by discriminant.
- Slices (`[T]`, including string literals) compare by length and contents, when `T` is an integer, `bool`, `char` or pointer type. Both operands must have the same element type. Slices of floats or aggregates are rejected, because byte equality is not value equality for them (NaN, `-0.0`, padding; [`tests/error_reporting/err_eq_slice_float.zrl`](../../tests/error_reporting/err_eq_slice_float.zrl), [`tests/error_reporting/err_eq_slice_mismatch.zrl`](../../tests/error_reporting/err_eq_slice_mismatch.zrl)).
- Structs, tuples, arrays and payload-carrying enums are rejected: `match` on them, compare fields, or implement `Eq` ([standard_library.md](standard_library.md) §7) and call `.eq()` ([`tests/error_reporting/err_eq_struct.zrl`](../../tests/error_reporting/err_eq_struct.zrl), [`tests/error_reporting/err_eq_tuple.zrl`](../../tests/error_reporting/err_eq_tuple.zrl), [`tests/error_reporting/err_eq_array.zrl`](../../tests/error_reporting/err_eq_array.zrl), [`tests/error_reporting/err_eq_payload_enum.zrl`](../../tests/error_reporting/err_eq_payload_enum.zrl)).

#### Punctuation

```
( ) { } [ ] < >
; : :: , . ..  ...
-> =>
```

### 2.6 Type Casting Rules

The `as` operator supports the following conversions:

| From                           | To                     | Semantics                                                               |
| ------------------------------ | ---------------------- | ----------------------------------------------------------------------- |
| Any integer                    | Any integer            | Truncates or zero/sign-extends; modular on narrowing                    |
| Integer                        | Float (`f32`, `f64`)   | Converts; may lose precision                                            |
| Float                          | Integer                | Truncates toward zero                                                   |
| `u64`, `i64`, `usize`, `isize` | `*T`, `*mut T`         | Reinterprets as an address; `0 as *T` is null (using it needs `unsafe`) |
| Pointer                        | `u64`, `usize`         | Reinterprets as numeric address                                         |
| `*T`                           | `*mut T` (and reverse) | Pointer mutability coercion                                             |
| `[mut T]`                      | `[T]`                  | Drops write access (the reverse is an error)                            |

No other `as` produces a slice, array, tuple, struct, enum or box: a cast to one of those types is an error unless it is the identity, through a type alias too (`5 as [u8]`, `x as P` are rejected; probes [`105_cast_int_to_slice.zrl`](../../bench/safety_matrix/probes/105_cast_int_to_slice.zrl), [`106_cast_int_to_struct.zrl`](../../bench/safety_matrix/probes/106_cast_int_to_struct.zrl), [`tests/error_reporting/err_cast_to_enum.zrl`](../../tests/error_reporting/err_cast_to_enum.zrl)). A cast to a type parameter or an associated type (`T`, `T::Out`) is an error from an integer ([`tests/error_reporting/err_cast_int_to_type_param.zrl`](../../tests/error_reporting/err_cast_int_to_type_param.zrl)), and otherwise converts only one number to another: what it stands for may be a reference.

A number does not become a `bool` or a `char` in checked code: `5 as bool` and `0xD800 as char` are errors (write `n != 0`; `unicode::char_from_u32` is the checked conversion and returns `None` for a surrogate or a value above U+10FFFF). `bool` and `char` follow the same rule: inside `unsafe` the cast compiles and the value is the caller's responsibility (a forged `bool` that reaches a two-armed `match` aborts with exit 1). `char` and `u32` do not match each other implicitly; a `u8` stands for a `char` (a char literal is a `u8`), and `c as u32` and `c as u8` take the value back. The intrinsics `@int_cast<T>`, `@ptr_cast<T>` and `@ptr_from_int<T>` follow the same rules.

`bool` never converts implicitly. Between the numeric primitive types, the current compiler implicitly adjusts widths at `let` bindings, call arguments, returns, and `match` arm results (including narrowing, which wraps modularly); all other conversions require explicit `as`. Unsuffixed integer literals take their type from the surrounding context when it is an integer type, defaulting to `i32` (`i64` when the value does not fit). _Note: the implicit width adjustment is under review and may become an error in a future version — prefer explicit `as`._

## 3. Type System

### 3.1 Primitive Types

| Type                   | Size          | Description                                                            |
| ---------------------- | ------------- | ---------------------------------------------------------------------- |
| `bool`                 | 1 byte        | Boolean (`true` / `false`)                                             |
| `u8` `u16` `u32` `u64` | 1/2/4/8 bytes | Unsigned integers                                                      |
| `i8` `i16` `i32` `i64` | 1/2/4/8 bytes | Signed integers                                                        |
| `usize` `isize`        | 4/8 bytes     | Pointer-sized unsigned/signed integers                                 |
| `f32`                  | 4 bytes       | IEEE 754 single-precision float                                        |
| `f64`                  | 8 bytes       | IEEE 754 double-precision float                                        |
| `unit` / `()`          | 0 bytes       | Empty type (also the empty tuple)                                      |
| `never`                | —             | Bottom type; assignable to any type; produced by diverging expressions |

The `never` type is the bottom type. It is the result type of expressions that never yield a value: a block whose last statement is `return`/`break`/`continue`, a `match` where every arm diverges, or an `if`/`else` where both branches diverge. A `never`-typed value is assignable to any type, so diverging arms and branches are compatible with their surrounding expression context without requiring an explicit value.

### 3.2 Pointer Types

| Syntax   | Description                  |
| -------- | ---------------------------- |
| `&T`     | Immutable reference to `T`   |
| `&mut T` | Mutable reference to `T`     |
| `*T`     | Immutable raw pointer to `T` |
| `*mut T` | Mutable raw pointer to `T`   |

### 3.3 Box (Owned Heap Pointer)

`Box<T>` is an owned, heap-allocated pointer. It is always mutable. A `Box` is not freed when it goes out of scope, and its pointee's `Drop` (if `T` has one) does not run: like a collection that is not `free`d, it leaks its allocation. Freeing at scope end is planned ([Known Issues](../../KNOWN_ISSUES.md), §5); until then, put short-lived values in an arena or on the stack.

### 3.4 Arrays

`[T; N]` is a fixed-size array of `N` elements of type `T`. Array literals: `[1, 2, 3]`. Arrays support trailing commas (`[1, 2,]`). A length or repeat count above 4294967295 is an error (`array length does not fit`, `array repeat count does not fit`). A type whose size is above `isize::MAX` (a deeply nested array, say) is an error where the program writes it, and so is one nested more than 100 levels deep by value: such a type has no size the compiler can compute without wrapping.

### 3.5 Slices

`[T]` is a fat pointer (pointer + length) viewing a contiguous sequence of `T`. A `[T]` is read-only, as a `&T` is: `s[i] = v`, `&mut s[i]` and a `&mut self` method call on `s[i]` are errors. `[mut T]` is the mutable slice, which may also write its elements. String literals (`"hello"`) produce `[u8]` slices.

- `&a` on an array `[T; N]` gives a `[T]` wherever a slice is expected; `&mut a` (on a `mut` array) gives a `[mut T]`. The slice keeps `a` borrowed while it is live, as `&a` does.
- A `[mut T]` is accepted wherever a `[T]` is expected; a `[T]` is never accepted as a `[mut T]`.
- `@slice(p, len)` is a `[mut T]` when `p` is a `*mut T` or `&mut T`, otherwise a `[T]`. With a literal length 0 it is a `[T]` unless a `[mut T]` is expected there.
- `Vec.as_slice()` gives a `[T]`, `Vec.as_mut_slice()` a `[mut T]`.
- For programmers coming from Rust: `[T]` is Rust's `&[T]` and `[mut T]` is its `&mut [T]`. Zoril's `&mut [T]` is a mutable reference to a read-only slice (the slice value can be replaced, its elements cannot be written); a function that fills a buffer takes `[mut u8]`.

Every slice value exposes two built-in pseudo-fields accessed with standard `.field` syntax:

| Field  | Type  | Description                                                                          |
| ------ | ----- | ------------------------------------------------------------------------------------ |
| `.ptr` | `*T`  | Raw pointer to the first element (for either slice kind; raw pointers are unchecked) |
| `.len` | `u64` | Number of elements (string `.len` excludes the null terminator)                      |

These fields are not struct fields but compiler-synthesized member accesses. A slice fat pointer is created with the `@slice(ptr, len)` builtin: `@slice(raw_ptr as *T, count)`. Nothing checks `len`, so `@slice` needs an `unsafe` block (unless `len` is a literal 0); to use a whole array wherever a slice is expected (an argument, a `let` with a slice type, an assignment, a struct field), write `&a` or `&mut a`, which needs none.

### 3.6 Tuples

`(T1, T2, ...)` is an anonymous product type. Elements are accessed by numeric index (`tup.0`, `tup.1`). The empty tuple `()` is equivalent to `unit`. Tuple literals: `(expr1, expr2, ...)`. Tuples support trailing commas (`(1, 2,)`).

### 3.7 Structs

User-defined product types with named fields:

```zoril
struct Point {
    x: i32,
    y: i32,
}
```

Structs may be generic: `struct Wrapper<T> { value: T }`. Struct definitions and literals support trailing commas.

Generic structs can use explicit type arguments via the turbofish syntax in literals. The double-colon (`::`) is optional before the type arguments:

```zoril
struct Wrapper<T> { value: T }
fn main() {
    let w1 = Wrapper::<i32> { value: 42 };
    let w2 = Wrapper<i32> { value: 42 }; // same as above
}
```

A type argument on a bare enum variant (`O.N::<i32>`) is not accepted: it is neither a call nor a struct literal, and the front end says so. Give the type on the binding (`let o: O<i32> = O.N;`) or, for a variant with a payload, call it (`O.S::<i32>(3)`).

If omitted, the compiler attempts to infer the type arguments from the field values.

### 3.8 Enums (Sum Types)

Tagged unions with optional payloads:

```zoril
enum Option<T> {
    None, // Bare variant without explicit `()`
    Some(T),
}
```

Variants are constructed as `Option.Some(value)` or `Option.None`. Enum declarations support trailing commas.

**Variant construction syntax:**

- `Type.Variant` — bare variant (no payload)
- `Type.Variant(expr)` — payload variant

Both forms also appear as patterns in `match` arms (see §5.3).

**Explicit tags:** Variants may be assigned explicit integer tags using `=`:

```zoril
enum TokenKind {
    Ident = 1,
    Int = 2,
    String = 3,
    Plus = 43,
}
```

If tags are omitted, variants are assigned incrementing values starting from 0. Explicit tags are useful for FFI and for maintaining stable values across compiler bootstrap stages.

### 3.9 Function Pointer Types

`fn(T1, T2) -> R` denotes a function pointer type. Variadic function pointers use `...`: `fn(i32, ...) -> i32`.

`extern "C" fn(T1, T2) -> R` denotes a **C function pointer**: one thin code address (8 bytes, no environment), the type a C callback has. Its parameters and result obey the `extern` signature rules (§9.1). A function defined with `extern "C" fn name(..) { body }` converts to it by naming it, with no cast; nothing else does: a plain `fn`, a closure, a `fn` value and an integer are each a compile error, because a Zoril function value is two words. Calling a value of this type needs `unsafe`, because the code it points at was never checked. It may be a parameter or result of an `extern` function, a struct field (a table of callbacks), and a generic argument. There is no null form: an API that accepts NULL declares a second signature taking `*u8`. Inside `unsafe`, a raw pointer converts to it (`p as extern "C" fn(..)`, the `dlsym`-style lookup; non-null is the caller's obligation) but an integer does not: write the address as a raw pointer first (probes [`274_cfn_pointer_in_unsafe.zrl`](../../bench/safety_matrix/probes/274_cfn_pointer_in_unsafe.zrl), [`275_cfn_int_inside_unsafe.zrl`](../../bench/safety_matrix/probes/275_cfn_int_inside_unsafe.zrl)). A C function pointer casts to its own type and to no other signature (probes [`277_cfn_same_type_cast.zrl`](../../bench/safety_matrix/probes/277_cfn_same_type_cast.zrl), [`276_cfn_different_signature.zrl`](../../bench/safety_matrix/probes/276_cfn_different_signature.zrl)). Checked code cannot make one from a number or a pointer (probes [`273_cfn_pointer_outside_unsafe.zrl`](../../bench/safety_matrix/probes/273_cfn_pointer_outside_unsafe.zrl), [`263_cfn_intrinsic_forge.zrl`](../../bench/safety_matrix/probes/263_cfn_intrinsic_forge.zrl)).

### 3.10 Generics

Functions, structs, and enums may be parameterized by type variables:

```zoril
fn identity<T>(x: T) -> T { return x; }
struct Pair<A, B> { first: A, second: B }
```

Type arguments can be explicit (`identity::<i32>(42)`) or inferred from arguments. Turbofish syntax (`::<...>`) is also supported on member access: `w.map::<i32>(double)`.

All generics are monomorphized: each unique instantiation produces a separate concrete definition.

**`.` vs `::` convention:** `.` is the item-access operator for types and values — enum variants (`Option.Some`), associated functions and constants (`Vec.new`, `Type.CONST`), fields, and methods all use it. `::` is used for module namespaces and imports (`import "math.zrl" as m; m::square(x)`, `use io::println`, `use ast::{Span, Token}`), as well as the turbofish `::<...>` for explicit type arguments (`identity::<i32>(42)`). Code and documentation should use `.` for types and instances, and `::` for module paths and generic instantiation.

### 3.11 Trait Bounds

Type parameters may be constrained by trait bounds:

```zoril
trait Display { fn display(self); }
fn print_value<T: Display>(x: T) { x.display(); }
```

### 3.12 Linear Resource Types

`fd<r>`, `fd<w>`, `fd<rw>` (typed file descriptors) and `async_context` (async I/O ring) are linear resource types. They must be consumed (closed) exactly once before leaving scope; failure to do so is a verification error.

## 4. Declarations

### 4.1 Functions

```zoril,no-test
fn name(param: Type, ...) -> ReturnType {
    body
}
```

- `pub fn` — public visibility
- `unsafe fn` / `pub unsafe fn` — unsafe function: calling requires an `unsafe` block or an enclosing `unsafe fn` body; the function's entire body is an unsafe context
- `extern fn` — external (C FFI) declaration, no body; calling one needs `unsafe`
- `extern "C" fn name(..) { body }` — a Zoril function C can call: an unmangled symbol `name`, the C calling convention, no environment parameter, a body checked like any other. It may not be generic, and its signature follows the `extern` type rules (§9.1). Zoril code calls it without `unsafe`, because the body is checked. Two of them with one name in a program are an error. `extern fn f() { .. }` without the `"C"` is an error. A trap inside one ends the process with the usual status (134, 136, ...); nothing unwinds through C frames.
- Variadic: `extern fn printf(fmt: *u8, ...) -> i32;`
- Generic: `fn foo<T>(x: T) -> T { ... }`

Function parameters and call arguments support trailing commas.

### 4.2 Variables

```zoril,wrap
let x: i32 = 42;        // immutable, explicit type
let y = 10;              // immutable, inferred type
let mut z = 0;           // mutable
z = z + 1;               // reassignment (mutable only)
```

A later `let` may rebind (shadow) an existing name, as in Rust: the new binding may have a different type, and its initializer sees the previous binding (`let x = 5; let x = x + 10;` gives 15). Shadowing follows scope: a binding introduced inside a block ends with the block.

`let` also takes a pattern (§5.3) that matches every value of its type, and binds each name in it; `mut` goes on each binding that needs it (`P { mut x, .. }` too):

```zoril,no-test
let (a, b) = pair();
let P { x, y: mut y2 } = p;
let (mut n, _, Line { a: P { x: ax, .. }, .. }) = t;
```

A pattern that can fail to match (`let Some(x) = o;`) is an error naming a value it misses; use `if let` or `match` there. Bindings, moves and borrows follow the `match` rules.

### 4.3 Structs

```zoril
struct Name {
    field1: i32,
    field2: u64,
}
```

Generic: `struct Name<T> { field: T }`

A struct has the C layout: fields in declaration order at their natural alignment, size padded to the largest alignment (`doc/spec/abi.md` §2.1). This is a promise (`doc/STABILITY.md`); enums, tuples, slices and `Box` have none. Spell C types with the `ffi` module aliases (`ffi::c_int`, `ffi::c_long`, ...).

### 4.4 Enums

```zoril
enum Name {
    Variant1(i32),
    Variant2,
}
```

Generic: `enum Result<T, E> { Ok(T), Err(E) }`

### 4.5 Type Aliases

```zoril
type Byte = u8;
type StringSlice = [u8];
```

An alias names one type; it takes no type parameters (`type Pair<T> = (T, T);` is an error).

### 4.6 Traits

```zoril,no-test
trait Name {
    type Assoc;
    fn method(self: &Self, args...) -> ReturnType;
    fn provided(self: &Self) -> Self::Assoc { ... }
}
```

A trait declares methods and associated types. A method with a body is a _default_: an impl that does not define it gets it, with `Self` the impl's type and the trait's type parameters bound to the impl's trait arguments. `type Assoc;` declares an associated type, which each impl defines (`type Assoc = T;`) and which is named through a type: `Self::Assoc` in the trait and its impls, `T::Assoc` for a type parameter, `Type::Assoc` for a type. It stands for the type the impl for that type defines, with the impl's parameters bound; a type no impl defines it for, or two impls do, is an error where the name is used.

`Self` is a special type alias that refers to the concrete type implementing the trait. It may appear in types within a trait declaration or its `impl` block. `Self` is not a keyword; it is resolved at the point of `impl Trait for Type` to the implementing `Type`. A trait's name is a module item like a type's: another module names it through its path (`iter::Iterator`) or a `use` (`use iter::Iterator;`), the prelude's (`Eq`, `Clone`, `Copy`, `Hash`, `Error`) are seen everywhere, and two modules may each declare a trait of one name. `Drop` is known to the language without a declaration.

### 4.7 Impl Blocks

```zoril,no-test
impl Type {
    fn method(self: &Type, x: i32) -> i32 { ... }
    pub fn public_method(self: &Type) -> i32 { ... }
    const LIMIT: i32 = 100;
    type Handle = Ptr<Type, 0>;
}

impl Trait for Type {
    fn method(self: &Type) -> i32 { ... }
}
```

In addition to `fn` methods, impl blocks may contain `pub` visibility annotations, `const` declarations, and `type` items (associated types, §4.6). An `impl Trait for Type` defines every method of the trait that has no default and every associated type it declares, and nothing else; its methods are public, as the trait's are.

An impl's methods and constants belong to the type: they are reached through it, as `Type::method(args)` or `Type.method(args)` (no receiver is added), `Type::CONST` or `Type.CONST`, and `x.method(args)`, which passes `x` (or `&x`) as `self`. They have no free-function names, so a function named `Type_method` is unrelated to them. Method calls look through pointers and `Box<T>`, several layers deep, to find the method; `(*p).method()` also works. How methods are named in the object file is the compiler's business (`modular_compilation.md` §3.1).

Inherent methods can also be declared directly on slice types, including generic slices `impl<T> [T]` and concrete element types like `impl [u8]`. Method call resolution performs automatic referencing (`&`) and dereferencing on slice receivers, allowing methods taking `self: &[u8]` to be invoked seamlessly on both slice values (`[u8]`) and slice references (`&[u8]`). Standard library string operations (such as `.starts_with()`, `.sub()`, `.trim()`, and `.split()`) are defined directly on `[u8]` via these slice inherent methods.

For coherence across modules, inherent methods on slice types are unique: defining duplicate methods in the same or separate `impl` blocks for a slice type is a compile error (`tests/error_reporting/err_slice_duplicate_method.zrl`). Furthermore, overlapping method names between generic slice impls (`impl<T> [T]`) and concrete slice impls (such as `impl [u8]`) are forbidden (`tests/error_reporting/err_slice_overlapping_method.zrl`), and user code cannot redefine inherent slice methods already provided by the standard library.

Function and method calls are strictly validated for argument count. For non-variadic functions, the number of arguments must exactly match the parameter count. For variadic functions, the number of arguments must be at least the number of fixed parameters.

### 4.8 Constants and Statics

```zoril
const MAX: i32 = 100;
static mut counter: i32 = 0;
```

`const` values are compile-time constants. `static` values are global variables with a fixed address.

A `static mut` whose type is a **scalar** - an integer, a float, `bool`, `char` or a raw pointer - may be read, written and borrowed in checked code. Any other `static mut` (an enum, a struct, a tuple, an array or a `Box`) may be read, written or borrowed only inside `unsafe` (or an `unsafe fn`): a write can change the type stored in it while a borrow of it is live, and borrows of statics are not tracked across such a write. Arrays, tuples and structs made only of scalars are not exempted yet. An immutable `static` is unchanged: it is fixed by its initializer and reading it cannot see a retyped value. The full rule and its probes are `safety_model.md` §4.6 and the row `Non-Scalar static mut Access Is Unsafe`.

A `static`'s or `const`'s initializer becomes the declared type's bytes in the program image at compile time, so it must be one of a few constant forms:

- An **integer constant expression**: an integer, `char` or `bool` literal, a named constant, a cast, and `+ - * / % & | ^ << >>` over those (with unary `-` and `!` too). Division, modulo and a right shift read the operand signedness from the declared type, so `const HALF: i32 = -7 / 2` is `-3`. A cast is a cast the language allows here, so `const NULL: *mut u8 = 0 as *mut u8` and a fixed address such as `static CONSOLE: *mut u32 = 0x40000000 as *mut u32;` are both constants: creating a raw pointer is safe, and every _use_ of one needs `unsafe`, which is where the marker goes (`doc/spec/unsafe_policy.md` §1).
- A **float**: a float literal, with an optional sign and an `f32`/`f64` suffix or cast; an integer constant expression is also a value of a float type (`const RATIO: f64 = 2`). Arithmetic _on_ floats is not evaluated yet.
- A **byte string**, for a `[u8; N]`: its bytes become the array's, so its length must equal `N` (`const NAME: [u8; 5] = "hello"`). In a function body a string literal is a slice `[u8]`, which a data section cannot hold; here it is the array of its own length.
- A **variant with no payload**: its image is its discriminant (`static C: Color = Color.Green`).

The initializer is checked against the declared type by the same rules a `let` of that type answers to, so `static P: Big = 7` is the type mismatch `let p: Big = 7` is, and `static X: u64 = "abc"` names the string's own type. Everything a constant context cannot hold - a struct or array literal, a call, another `static`'s name - is reported at the initializer.

### 4.9 Imports

```zoril,no-test
import "path/to/module.zrl";
```

An import loads the named source file into the program. Paths are resolved relative to the directory containing the importing file, then under each include root. Circular imports are detected and rejected ([`tests/error_reporting/err_circular_import.zrl`](../../tests/error_reporting/err_circular_import.zrl)). The import makes a namespace through which the file's public items are named (`module::item`), and `use` brings items in to be written bare (§11.1.1).

## 5. Expressions

All expressions produce a value. Zoril is expression-oriented: blocks, `if`, and `match` are expressions.

### 5.1 Expression Kinds (21)

| Kind            | Syntax                                       | Description                                                           |
| --------------- | -------------------------------------------- | --------------------------------------------------------------------- |
| Integer literal | `42`                                         | Integer constant                                                      |
| Float literal   | `3.14`                                       | Floating-point constant                                               |
| Boolean literal | `true`, `false`                              | Boolean constant                                                      |
| String literal  | `"hello"`                                    | Static byte slice                                                     |
| Variable        | `name`                                       | Variable reference                                                    |
| Binary          | `a + b`                                      | Binary operation                                                      |
| Unary           | `-x`, `!b`, `*p`, `&v`, `&mut v`             | Unary operation                                                       |
| Call            | `f(args)`, `x.method(args)`                  | Function/method call                                                  |
| Block           | `{ stmts; expr }`                            | Block expression                                                      |
| If              | `if cond { ... } else { ... }`               | Conditional expression                                                |
| If let          | `if let pattern = expr { ... } else { ... }` | Conditional on a pattern match (§6.1)                                 |
| Match           | `match expr { arms }`                        | Pattern matching                                                      |
| Struct literal  | `Point { x: 1, y: 2 }`                       | Struct construction                                                   |
| Member access   | `expr.field`                                 | Field access                                                          |
| Index           | `expr[index]`                                | Array/slice indexing                                                  |
| Box             | `box expr`                                   | Global-heap allocation (`box(allocator) expr` is unimplemented, §7.4) |
| Cast            | `expr as Type`                               | Explicit type conversion                                              |
| Try             | `expr?`                                      | Early return on error                                                 |
| Array literal   | `[1, 2, 3]`                                  | Array construction                                                    |
| Tuple literal   | `(a, b, c)`                                  | Tuple construction                                                    |
| Closure         | `\|params\| { body }`, `\|params\| expr`     | Lambda expression                                                     |
| Sizeof/Alignof  | `sizeof(T)`, `alignof(T)`                    | Compile-time type query                                               |

### 5.2 Closures

```zoril,wrap
let add = |x: i32, y: i32| -> i32 { x + y };
let inc = |x: i32| -> i32 { x + 1 };
```

```zoril,no-test
let inc = |x: i32| x + 1;           // the result is the body's type
apply(|x| x * 2, 3);                // x: i32 from apply's fn(i32) -> i32
```

A closure's parameter types may be left out where the context expects a function type (an argument, a `let` or field type, a generic method's parameter once its other arguments fix the type arguments), and its body may be one expression. With no `-> R`, its result is the expected function type's, or with none known, its body's type (the first `return` value or the tail); a struct, tuple, slice or other aggregate result must be written.

A closure is a function value like a named function's: a `fn(..) -> R` value is two words, the code and its environment (`doc/spec/abi.md`), so a closure can be passed, stored, returned into the same frame's values and reassigned like any `fn` value. Variables are captured implicitly from the enclosing scope, by copy, when the closure is made; no explicit capture list is required. The captures live in the frame that made the closure, so a capturing closure must not outlive it: returning one, or storing it (or a value holding it) where the caller or a global reaches, is a region escape error. A named function's environment is null.

**What a closure captures, and how.** A closure captures each local of the enclosing function it names, at the point the closure is made; there is no capture list. Three rules, one per kind of value (probes 298-302):

- **A `Copy` value is copied.** The closure keeps the value as it was when the closure was made; later changes to the outer binding are not visible inside it, and the outer binding keeps working (`tests/language/closures/capture_copy_is_copied.zrl`).
- **An owning value is moved.** That is a collection (`Vec`, `String`, `ByteVec`, `HashMap`), a `Box`, an `Arena`, or a struct or enum containing one, recursively. The outer binding cannot be used or dropped afterwards - "use of moved value", "cannot drop value that may have been moved" - and the closure's environment is the value's only owner, so an explicit `@drop` of the outer binding while the closure is live is rejected (`err_capture_owning_value_moves.zrl`, `err_capture_drop_after_move.zrl`). A collection is not `Copy` for this purpose even though its fields are: the buffer behind them is what makes it owned. The environment owns the value across calls, so moving out of a capture (`return v;`, `let w = v;`) or explicitly dropping it (`@drop(v);`) inside the closure is rejected (`cannot move out of a closure capture`; `err_closure_capture_move_out.zrl`, `err_closure_capture_drop_box.zrl`, `err_closure_capture_drop_vec.zrl`): doing so inside one call would leave the environment dangling for the next. Because the closure owns the moved value, it may mutate it or assign to its fields across calls (`tests/language/closures/closure_mutates_owning_capture.zrl`). A view of a closure's owned capture counts as storage owned by this frame under the store rule: it cannot be returned, and cannot be stored through a captured &mut, into another capture, into a global, or into a parameter's referent. The move is the `move` keyword's future spelling if a borrow-capture form is added later.
- **A reference is copied as a reference, and keeps its borrow.** The closure stores the pointer; the borrow it carries keeps the pointed-to value borrowed while the closure is live, so the existing frame rules apply: a capturing closure must not outlive what it borrows, and returning one, or storing it where the caller or a global reaches, is a region escape error. No capture is by reference to the _variable_ itself: a closure cannot rebind an outer local. Assigning to or mutably borrowing a captured `Copy` variable is rejected at compile time (`the closure holds a copy of 'n'; assigning to it changes only the copy; capture a '&mut' reference instead`; `tests/error_reporting/err_closure_assign_captured_var.zrl`). A closure can mutate through a captured mutable reference (`&mut T`), which mutates the referent (`tests/language/closures/closure_mutates_captured_mut_ref.zrl`).

Function values cannot be compared with `==`, cast with `as`, held in a `static` or `const`, or passed to or returned from an `extern` function, which follows the C convention of one code pointer; a callback is an `extern "C" fn` converted to the C function pointer type (§3.9).

**A `fn` value carries the callee's store contract.** The checker sees the arguments at a direct call, so it rejects one that hands a stack address to a parameter the callee stores elsewhere. Through a `fn` value it sees neither the callee nor the arguments, so a named function or closure whose body writes one of its reference parameters into another parameter's storage or into a global cannot become a `fn` value: taking its address is ``region escape: the function stores a reference into memory that outlives a call through a `fn` value``. The rule is part of what the type means, so a `fn` value obtained from anywhere (a parameter, a field, a returned value) was made by a coercion this rule already checked; an `extern "C" fn` pointer is outside it and is `unsafe` to call. A function that only reads through its parameters is unaffected, whether named or a closure (probes [`293_fn_value_store_stack_ref.zrl`](../../bench/safety_matrix/probes/293_fn_value_store_stack_ref.zrl) to [`297_fn_value_stores_nothing.zrl`](../../bench/safety_matrix/probes/297_fn_value_stores_nothing.zrl)).

### 5.3 Match Patterns

A `match` arm has the form `pattern [if guard] => expr` or `pattern [if guard] => { block }`. Matches are enforced at compile time to be exhaustive, looking inside nested patterns: every enum variant, both `bool` values, and every combination of them in tuples, structs and payloads must be covered, or a wildcard (`_`) or binding must catch the rest. Integers, chars and slices are covered only by a wildcard or binding (ranges and literals never add up to all values). The error names a value that is not covered: `non-exhaustive match: missing case`Some(None)``. Guarded arms (`if` guards) do not count toward exhaustiveness. At runtime, any unreachable fallthrough triggers a deterministic `zoril_abort()` trap. A `_` arm on an enum that stands for only a few variants (at most three, or at most a third of the enum) is warned about by the `wildcard-arm` lint, on by default (`-A wildcard-arm` turns it off, `-W` on): listing those variants makes a variant added later a compile error at this match, which is the point of the exhaustiveness check. A `_` arm that diverges (`_ => panic(..)`) is exempt, as is the `else` of an `if let`. An arm the arms before it already cover is warned about as unreachable.

Patterns (in precedence order):

| Pattern           | Syntax                            | Meaning                                                            |
| ----------------- | --------------------------------- | ------------------------------------------------------------------ |
| Bare variant      | `Variant`                         | Matches enum variant with no payload                               |
| Payload binding   | `Variant(name)`                   | Matches variant with payload; binds payload to `name`              |
| Qualified bare    | `Type.Variant`                    | Matches bare variant using explicit enum type prefix               |
| Qualified payload | `Type.Variant(name)`              | Matches payload variant using explicit type prefix                 |
| Nested payload    | `Variant(pat)`, `Variant(p1, p2)` | Matches the payload; several patterns match a tuple payload        |
| Tuple             | `(p1, p2, ..)`                    | Matches each element; `(p)` only groups, `(p,)` is a 1-tuple       |
| Struct            | `Name { f: pat, g, .. }`          | Matches named fields; `g` binds field `g`; `..` ignores the rest   |
| Binding           | `name`                            | Matches anything and binds it (a constant's name compares instead) |
| Mutable binding   | `mut name`                        | Matches anything and binds it mutably                              |
| Literal           | `1`, `-1`, `'a'`, `true`          | Matches that value                                                 |
| OR pattern        | `Pat1 \| Pat2`                    | Matches if any of the separated patterns match                     |
| Range pattern     | `start..end`                      | Matches if value is in range `[start, end)`                        |
| Inclusive range   | `start..=end`                     | Matches if value is in range `[start, end]`                        |
| Wildcard          | `_`                               | Matches any value; use as the final (catch-all) arm                |

Qualified patterns are interchangeable with unqualified ones; the type prefix is optional and useful when the variant name would be ambiguous or as an aid to readability.

Patterns nest freely, with literals, ranges, `_` and bindings at the leaves:

```zoril,no-test
match shape {
    Shape.Pt(P { x: 0, y }) => y,          // a struct pattern inside a payload
    Shape.Pair(1, b) => b + 1000,          // a tuple payload, element by element
    Shape.Pair(a, b) => a + b,
    Shape.Empty => -1,
}
```

Tuple, struct and payload patterns see through a reference: matching a `&T` against them binds by reference (Rust's "match ergonomics"), so in `match &s { Shape.Pt(P { x, .. }) => .. }` `x` is a `&i32`. Bindings copy only when the value matched is not behind a reference.

The match expression can dereference a borrowed value before dispatching:

```zoril,no-test
fn is_some<T>(opt: &Option<T>) -> bool {
    return match *opt {
        Some(v) => true,
        None => false,
    };
}
```

When the match subject dereferences a borrow, a payload binding gives access to the payload in place: `Copy` payloads may be used freely, and reading fields of a non-`Copy` payload is allowed. Moving (consuming) a non-`Copy` payload out of a borrowed subject is an ownership error — the borrower does not own the payload ("cannot move out of borrow"; `tests/error_reporting/ec_match_move_from_borrow.zrl`).

**Range Patterns:** Numeric and character values can be matched against ranges.

- `start..end` matches values greater than or equal to `start` and strictly less than `end`.
- `start..=end` matches values greater than or equal to `start` and less than or equal to `end`. Ranges work for all integral types and character literals.

Example:

```zoril
fn classify_char(c: u8) -> i32 {
    return match c {
        'a'..='z' | 'A'..='Z' => 1, // Letter
        '0'..='9' => 2,             // Digit
        _ => 0,                     // Other
    };
}
```

**OR Patterns:** Multiple variants can be matched in a single arm using the `|` operator. All patterns in an OR-pattern arm must bind the same set of variables with the same names and types. If multiple variants carry payloads that need to be bound, each must specify the binding explicitly: `VariantA(name) | VariantB(name) => ...`. The compiler ensures that all matched variants in the arm provide the same bindings.

If a variant carries a payload but you do not wish to use it in that specific arm, the wildcard `_` can be used as a binding name: `VariantA(_) | VariantB => ...`. This is particularly useful in OR patterns where some variants have payloads and others do not, provided no variables are bound in that arm.

Pattern bindings (`name` in `Variant(name)`) are local variables in the arm body. The bound value is moved out of the matched expression (or copied if the type is `Copy`).

Match arm bodies are full expressions, including method calls, block expressions, and further `match` expressions:

```zoril
enum MaybeInt { Some(i32), None, }

fn get_or_default(opt: MaybeInt, default: i32) -> i32 {
    let result = match opt {
        Some(x) => x,
        None    => default,
    };
    return result;
}
```

Block arm bodies may use `return`, `break`, or `continue` to diverge instead of producing a value. Such arms have the **never type** and are excluded from the match result type — the match expression takes its type from the non-diverging arms only. If every arm diverges the entire match expression has type `never`:

```zoril,no-test
fn describe(op: *mut Op) -> u32 {
    return match *op {
        Op.Add       => { return 0 as u32; },
        Op.Sub       => { return 1 as u32; },
        Op.Mul(val)  => { return val; },
    };
}
```

**Note:** The wildcard `_` arm must appear last. Matches are enforced at compile time to be exhaustive; any unreachable fallthrough triggers a deterministic `zoril_abort()` at runtime.

## 6. Statements

### 6.1 Statement Kinds (9)

| Kind             | Syntax                                                                     |
| ---------------- | -------------------------------------------------------------------------- |
| Return           | `return expr;`                                                             |
| Expression       | `expr;`                                                                    |
| Let binding      | `let [mut] name [: Type] = expr;` or `let pattern [: Type] = expr;` (§4.2) |
| While loop       | `while cond { body }`                                                      |
| While-let loop   | `while let pattern = expr { body }`                                        |
| Infinite loop    | `loop { body }`                                                            |
| For loop         | `for var in start..end { body }` (range is half-open: `[start, end)`)      |
| For-in loop      | `for pattern in expr { body }` (a slice, an array, or an iterator)         |
| Break            | `break;`                                                                   |
| Continue         | `continue;`                                                                |
| Defer            | `defer { body }` or `defer expr;`                                          |
| If statement     | `if cond { body } [else { body }]`                                         |
| If-let statement | `if let pattern = expr { body } [else { body }]`                           |

The special variable name `_` (wildcard) can be used in a let binding to explicitly discard a value. This is useful for suppressing `#[must_use]` warnings. Wildcard bindings do not introduce a new name into the scope and can be used multiple times. If the discarded value is a non-Copy type, it is dropped immediately.

`if let` and `while let` take any pattern (§5.3), nested ones included. `if let P = e { A } else
{ B }` means `match e { P => { A }, _ => { B } }`, and `while let P = e { body }` means `loop {
match e { P => { body }, _ => break } }`: `e` is evaluated again on every iteration, after a `continue` too, and the pattern's bindings exist only in the body. Bindings, borrows and moves follow the `match` rules, so `if let Some(x) = &opt` binds `x` by reference. `else if let` chains like `else if`.

```zoril,no-test
let mut it = v.iter();
while let Some(x) = it.next() {
    if *x == 0 { continue; }
    total = total + *x;
}
```

`for pattern in expr` evaluates `expr` once. Over a slice or a fixed array it visits each element in order, binding it by reference (`x` is `&T`), with no `Option` per element. Over any other value it calls `next()` (as `stdlib/iter.zrl`'s iterators define it) until that returns `None`, and matches each item against the pattern. The pattern must match every value, as in a `let`; `continue` moves on to the next element. The iterable is dropped after the loop.

```zoril,no-test
for x in v.iter() { total = total + *x; }       // Vec: through its iterator
for P { x, y } in points { d = d + *y - *x; }   // a slice of P
for (k, v) in m.iter() { .. }                   // HashMap entries
```

An array's `len` is its size, a constant.

`break` and `continue` are expressions as well as statements, so they can end a match arm (`_ => break`).

The left side of `=` and of a compound assignment must be a place: a local, parameter or static, a field, a tuple element, an index or a dereference (parentheses are transparent). A literal, an arithmetic value, a call result or a cast is rejected with `invalid assignment target` ([`ec_assign_literal_target.zrl`](../../tests/error_reporting/ec_assign_literal_target.zrl), [`ec_assign_call_target.zrl`](../../tests/error_reporting/ec_assign_call_target.zrl)). Operators take only the operand classes they define: arithmetic takes integers (and floats where the operator is defined), bitwise operators and shifts take integers, relational comparison takes integers, floats or chars, and equality takes two operands of one comparable type. Unit, references in arithmetic, slices, function values, boxes, tuples, arrays, structs and enums are rejected by name ([`ec_unit_arithmetic.zrl`](../../tests/error_reporting/ec_unit_arithmetic.zrl), [`ec_reference_arithmetic.zrl`](../../tests/error_reporting/ec_reference_arithmetic.zrl), [`ec_operator_slice_operands.zrl`](../../tests/error_reporting/ec_operator_slice_operands.zrl)), and a reference is never compared with an integer (`r == 3` is an error). Only `+` and `-` on a raw pointer inside `unsafe` is pointer arithmetic ([`ec_raw_pointer_arithmetic_safe.zrl`](../../tests/error_reporting/ec_raw_pointer_arithmetic_safe.zrl)).

Note: `if` can appear as both an expression (yielding a value) and a statement (discarding the value). When both branches diverge (each ends in `return`, `break`, or `continue`) the if expression has the **never type** and the code following it is unreachable.

## 7. Memory and Ownership

### 7.1 Copy vs. Move

- **Copy**: All primitives (`bool`, integers, floats, `unit`), pointers (`&T`, `*T`, `*mut T`) and function pointers, slice values (`[T]` — the ptr/len header copies; the referenced elements are not duplicated), arrays `[T; N]` and tuples whose elements are all `Copy`, structs and enums whose fields are all `Copy`, that do not implement `Drop`, and that do not opt out under the raw-pointer rule.
- **Move**: `Box<T>`, `fd`, `async_context`, arrays/tuples with a `Move` element type, structs and enums that contain at least one `Move` field, that implement `Drop`, or that directly declare a raw-pointer field without an explicit `impl Copy`.

Copy types may be freely duplicated. Move types follow linear ownership: each value must be used exactly once. Use-after-move is a compile-time error.

A user-defined struct or enum is **structurally Copy** if every field is `Copy` and the type does not implement `Drop`. However, under **Option A+ (the raw-pointer opt-out)**: a struct or enum that **directly contains a raw-pointer field or payload, written as a raw pointer in its own declaration** (`*T` or `*mut T`, including inside array or tuple field types such as `[*mut u8; 2]` or `(*mut u8, usize)`), is **not** `Copy` unless it explicitly declares `impl Copy for T {}`. Owning collections (`Vec<T>`, `String`, `ByteVec`, `HashMap`) declare raw-pointer buffer fields, so an assignment, a by-value argument or a closure capture moves them (`let w = v;` leaves `v` unusable), and a duplicate has to be asked for with `clone()`, which allocates a new buffer. A struct or enum holding one is not `Copy` either. Conversely, non-owning handle types (such as `BasicBlock` or `ILFunction` pointing into arena memory) opt back into `Copy` with `impl Copy for T {}`. Generic types like `Option<*mut T>` remain `Copy` because their field is a type parameter `T`, not a declared raw pointer. Arrays and tuples stay purely structural.

### 7.2 Borrowing

- `&expr` creates an immutable borrow. Multiple immutable borrows may coexist.
- `&mut expr` creates a mutable borrow. Only one mutable borrow may exist at a time.
- Stores through immutable pointers are rejected by the verifier ([`tests/error_reporting/err_const_ptr_write.zrl`](../../tests/error_reporting/err_const_ptr_write.zrl), probe [`94_write_through_readonly_slice.zrl`](../../bench/safety_matrix/probes/94_write_through_readonly_slice.zrl)).
- **A borrow lasts until the last use of what holds it**, not until the end of its scope:

  ```zoril,no-test
  let r = v.get(0);
  use(r);        // last use of r
  v.push(1);     // fine: r is no longer live
  ```

  A use on any later path keeps it alive, so a borrow used again in the next loop iteration is live across the whole loop. The same holds for a borrow held _inside_ a value - a struct local, or an `Option` field such as a collection's arena anchor: [`tests/language/memory/borrow_named_local_ends_at_last_use.zrl`](../../tests/language/memory/borrow_named_local_ends_at_last_use.zrl) is accepted, while moving the borrowed value while the borrower is still live is rejected ([`tests/error_reporting/err_borrow_named_local_used_after_move.zrl`](../../tests/error_reporting/err_borrow_named_local_used_after_move.zrl)). A value with a `Drop` impl is live until its drop ([`tests/error_reporting/err_borrow_drop_local_blocks_move.zrl`](../../tests/error_reporting/err_borrow_drop_local_blocks_move.zrl)).

**What a returned value borrows.** A value returned by a call that can hold a reference — a reference, a slice, an `Option<&T>`, a struct holding one — may point into the call's arguments, so it keeps them borrowed while it is live. Which arguments: **`self` if the function takes a reference `self`, otherwise all of its reference and pointer parameters.**

```zoril,no-test
let first = v.get(0);   // borrows v (get takes &self)
v.push(1);              // error while `first` is still used below: the push may move v's buffer
use(first);
```

When a result points somewhere else — typically memory in an arena that outlives the call — the function says so with `#[borrows(..)]`, naming the parameters it does point into:

```zoril,no-test
#[borrows()]            // copied into an arena that outlives the table, not into either parameter
pub fn intern(self: &mut Table, name: [u8]) -> [u8] { ... }

#[borrows(text)]        // a slice of text, never of cfg
pub fn first_word(cfg: &Config, text: [u8]) -> [u8] { ... }
```

The compiler rejects the visible lie (returning an address computed from a parameter the attribute does not list; probe [`93_borrows_attribute_lie.zrl`](../../bench/safety_matrix/probes/93_borrows_attribute_lie.zrl)); beyond that the attribute is a trusted claim, like `unsafe` (`unsafe_policy.md`). The tie is part of the signature, so it is written into `.zri` interfaces and checked across modules without the callee's body.

**A declared store contract.** `#[stores(..)]` states the other half of what the summary computes: the parameters whose own storage a body writes into another parameter or a global. Each form is one pair — `#[stores(p)]` into `self`, `#[stores(p -> q)]` into `q`, `#[stores(p -> static)]` into a global — and a function may declare several. The compiler checks the declaration against the body: a source it never stores, or a target that receives nothing, is an error in the module that declares it. A generic body is exempt from the per-instance check (what it stores depends on its type arguments) and the declaration is a promise there, as `#[borrows]` is beyond the visible lie. A `pub fn` that stores a reference parameter without declaring it warns (not an error until 1.0) and names the attribute to add; the standard library ships with its declarations, so code written against this release already carries the contracts. Callers are unaffected in this release: the inferred summary is what the checker reads.

**Attributes are the only extension point for borrow and region contracts.** The language has no lifetime annotations: a quote already starts a character literal, and the premise of the design is that no `'a`-style parameter, argument or bound is ever added. A contract the checker needs from a function is written as an attribute on it — `#[borrows(..)]` for the arguments a result may point into, `#[stores(..)]` for what a body stores and where (§2.5) — and a future contract extends that set rather than the syntax. The same reasoning applies to any other contract a later feature needs to state: it is declared beside the signature, visible in the `.zri`, and checked against the body where that is possible.

_Coming from Rust:_ the default is Rust's lifetime elision stated as one rule. Where Rust would require explicit lifetimes (several reference parameters, no `self`), Zoril ties the result to all of them rather than refusing. `#[borrows(..)]` plays the role of naming a lifetime; `#[borrows()]` has no safe-Rust equivalent (it corresponds to an arena lifetime the signature cannot name). Raw pointers are checked too: returning a stack pointer through a function that hands its argument back is rejected, which Rust does not track (probe [`07_dangling_stack_callee.zrl`](../../bench/safety_matrix/probes/07_dangling_stack_callee.zrl), [`tests/error_reporting/ec_region_escape_return.zrl`](../../tests/error_reporting/ec_region_escape_return.zrl)).

**A `&mut T` is not `Copy`.** Binding one with `let` or storing it in a struct field moves it: after `let b = a;`, using `a` is rejected (`use of moved value 'a'`; [`err_mut_ref_copy_rejected.zrl`](../../tests/error_reporting/err_mut_ref_copy_rejected.zrl)). Passing it as an argument does not move it, because the call reborrows it for its duration, so `bump(a); bump(a);` compiles. Assigning through a projection whose base has been moved (`*b = 5;` after `let c = b;`) is rejected the same way ([`err_assign_deref_after_move.zrl`](../../tests/error_reporting/err_assign_deref_after_move.zrl)).

**A reference into `self` across a `&mut self` call (the strict reborrow rule).** When a method or view takes a reference into `self` (such as `v.get(0)`, `s.as_slice()`, or an element reference), the referent remains borrowed while that view is live. Calling a mutating method on `self` (`&mut self`) while holding the reference is rejected at compile time (probe [`309_mut_vec_param_view_across_free.zrl`](../../bench/safety_matrix/probes/309_mut_vec_param_view_across_free.zrl)):

```zoril,no-test
import "vec.zrl";
use vec::Vec;

fn first_then_free(v: &mut Vec<i32>) -> i32 {
    let r = v.get(0).unwrap();
    v.free(); // COMPILE ERROR: cannot mutably borrow 'v' while it is already borrowed
    return *r;
}

fn main() -> i32 {
    let mut v = Vec::<i32>.new();
    v.push(10);
    return first_then_free(&mut v);
}
```

`v.free()` releases the buffer `r` points into, so reading `*r` afterwards would be a use-after-free. The strict reborrow rule rejects this for a local `Vec` and also for a collection reached through a `&mut` parameter or reference (probes [`309_mut_vec_param_view_across_free.zrl`](../../bench/safety_matrix/probes/309_mut_vec_param_view_across_free.zrl) and [`311_mut_arena_param_view_across_reset.zrl`](../../bench/safety_matrix/probes/311_mut_arena_param_view_across_reset.zrl); this example is compiled in `doc/language/walkthrough.md`).

**Idioms for working with `&mut self` and views:**

1. **End the borrow before mutation:** Scope the view so its borrow ends before the mutating call:
   ```zoril,no-test
   let val = { *v.get(0).unwrap() };
   v.push(val + 1);
   ```
2. **Copy the value out:** When the element type is `Copy` (or can be cloned), copy the field or element out before mutating `self` (`self.items[i].tag` rather than a long-lived reference).
3. **Hoist self-derived arguments:** If an argument to a mutating call is derived from `self` (such as `self.f(self.g(..))`), evaluate and bind the argument before the mutating call if `self.g` borrows `self`. Note that atomic scalar arguments like `v.push(v.len())` are accepted because the argument is evaluated before the method body mutates `self`.
4. **Keep an index and re-read:** Instead of holding a reference across a mutation, store the integer index or key, perform the mutation, and re-fetch the element.
5. **Re-look up interned data:** Instead of holding a slice into a table's arena across operations that mutate or reset the arena, keep an interned handle (id) and look it up when needed.
6. **Split the struct:** If different methods need independent fields of a struct, split the struct into independent sub-components or pass only the needed fields as `&mut` parameters.

Raw pointer field access and mutation uses parenthesized dereference syntax, inside `unsafe`:

```zoril
struct Node { value: i32, }

fn read_field(ptr: *Node) -> i32 {
    return unsafe { (*ptr).value };   // read field through raw pointer
}

fn write_field(ptr: *mut Node, val: i32) {
    unsafe { (*ptr).value = val; }    // write field through raw pointer (requires *mut T)
}
```

Both read and write compile to direct memory operations through the pointer; no copy of the pointed-to struct is made. This extends to chained accesses: `(*ptr.inner).field = val` loads `ptr.inner` (a `*mut Inner`) and writes directly through that pointer.

### 7.3 Drop Order

When a scope exits:

1. All `defer` statements execute in reverse order of declaration (LIFO).
1. All local variables are dropped in reverse order of declaration.

### 7.4 Allocators

`box expr` allocates on the global heap using a built-in allocator that manages memory directly via system calls (e.g., `mmap`/`munmap`).

The grammar also accepts an explicit allocator — `box(allocator) expr` — but that form is **not implemented**, and the compiler rejects it with `arena allocation with box(allocator) is not implemented; use Vec, String or HashMap with new_in(&arena)` (see [`tests/error_reporting/err_box_allocator_not_implemented.zrl`](../../tests/error_reporting/err_box_allocator_not_implemented.zrl)). It previously compiled to a frame-local slot with the allocator operand dropped, so such a value was never placed in the allocator's region.

To allocate in an arena, build the value with one of the arena's own constructors: they take `&Arena`, allocate from it, and tie the result to the arena at compile time, so resetting or destroying the arena while the value is live is an error.

## 8. Generics and Traits

### 8.1 Monomorphization

All generics are resolved at compile time via monomorphization. Each unique type instantiation (e.g., `Wrapper<i32>`, `Wrapper<bool>`) generates a separate concrete type definition and function body in the IL. No runtime polymorphism is involved.

### 8.2 Type Inference

Generic function and method calls infer type arguments from the types of the passed expressions (and from the impls named by bounds), then from the type the call's result is expected to have (`let o: Option<u64> = none()`). A generic type named without arguments in a call (`let v: Vec<u32> = Vec.new()`) is the instance the context expects. Explicit type arguments may be provided when inference is ambiguous: `identity::<i32>(42)`. Turbofish syntax is also supported on member access: `w.map::<i32>(double)`; a method type parameter no argument determines must be given that way.

### 8.3 Traits

Traits define a set of method signatures that types must implement:

```zoril
struct Point { x: i32, y: i32 }

trait Printable {
    fn to_string(self: &Self) -> [u8];
}

impl Printable for Point {
    fn to_string(self: &Point) -> [u8] { return "point"; }
}
```

A trait method with a body is a default method, and a trait may declare associated types (§4.6). The standard library's `Iterator` uses both: its item type is `type Item;`, and its adapters are default methods, so they chain on any iterator (`v.iter().map(f).fold(0, add)`).

Trait methods are dispatched statically. When a generic function has a trait bound (`fn f<T: Printable>(x: T)`), the compiler resolves the concrete method at monomorphization time. Each call of a generic function checks its type arguments against the bounds: a struct, enum or primitive type argument without an impl of the bound trait is a compile error (`type 'Plain' does
not implement trait 'Named'`), whether or not the body calls a method of that trait. References, slices, tuples and other structural type arguments are not checked.

### 8.4 The Drop Trait

`Drop` is a built-in trait used for automatic resource cleanup. It has exactly one method:

```zoril,no-test
trait Drop {
    fn drop(self: Self);
}
```

- **Semantics:** `drop` is called automatically at the end of scope (or upon early return via `return` or `?`) for any local variable of a type that implements `Drop`. The order of dropping is the reverse order of declaration (LIFO), after any `defer` blocks execute.
- **Recognition:** the compiler finds the trait by the name `Drop`. A program may declare `trait Drop` itself (as a library with its own `drop` signature does), and an `impl Drop for T` written against that declaration, or with no declaration at all, is the one drop glue calls. A path-qualified name (`m::Drop`) is a different trait to the drop caller: its `impl` is not run at scope exit.
- **Constraints:** Types that implement `Drop` are automatically non-`Copy`, regardless of their fields.
- **Explicit Drop:** The drop behavior can be explicitly triggered using the `@drop(x)` builtin or by calling the method directly via `x.drop()`. This takes ownership of the value, so the automatic drop at scope exit does not run.
- **Move Suppression:** If a value is moved (e.g., passed by value to a function or returned), the automatic drop is suppressed in the current scope.

### 8.5 Copy, Clone and `#[derive(Clone)]`

A type is **Copy** when it owns no value that implements `Drop` (directly, or through a field, enum payload, tuple element or array element) and does not opt out under the raw-pointer rule. Copy values are duplicated bitwise by assignment and argument passing; any other value is moved. `core.zrl` names the property with a marker trait:

```zoril,no-test
trait Copy {}
trait Clone { fn clone(self: &Self) -> Self; }
```

`Copy` is structural by default: a `T: Copy` bound holds for every Copy type without an explicit impl. However, types directly declaring raw-pointer fields or payloads (`*T`, `*mut T`) opt out of `Copy` by default because raw pointers often represent owned heap buffers (as in `Vec` and `String`). A struct or enum declaring raw-pointer fields can opt back into `Copy` by declaring `impl Copy for T {}` (e.g. for non-owning handles into arena memory). `impl Copy for T {}` is rejected for a type that is not Copy due to implementing `Drop` or holding a move field ([`tests/error_reporting/ec_impl_copy_for_drop_type.zrl`](../../tests/error_reporting/ec_impl_copy_for_drop_type.zrl), [`tests/error_reporting/ec_copy_bound_drop_type.zrl`](../../tests/error_reporting/ec_copy_bound_drop_type.zrl)). `Clone` is explicit duplication: a clone owns its own copy of whatever the original owns. Placing `#[derive(Clone)]` on a struct generates

```zoril,no-test
impl<T..: Clone> Clone for S<T..> {
    fn clone(self: &S<T..>) -> S<T..> { return S { f: self.f.clone(), .. }; }
}
```

which requires every field type to implement `Clone`. Only `Clone` can be derived, and only for structs.

## 9. FFI and System Interface

### 9.1 Extern Functions

```zoril
extern fn external_add(a: i32, b: i32) -> i32;
```

Extern functions have no body. They are linked from external binary object files (`.o`) using standard system toolchains (e.g., `ld`). Variadic extern functions use `...` after the last named parameter.

An `extern` signature may use only what C can take: `bool`, the sized integers, `usize`/`isize`, `f32`, `f64`, and raw pointers `*T`/`*mut T` (and `never` or no type as a result). Slices (pass `s.ptr` and the length), references, `Box`, tuples, arrays, enums, closures, `fn` values and structs by value are errors that name the type and what to pass instead: a struct travels as a raw pointer to it. Declaring a body for an `extern` function is an error: `an extern function declaration has no body`. An `extern` function cannot be generic (C has one function per name). In a call to a variadic `extern` function the unnamed arguments are promoted as C does: an `f32` becomes a `double`, an integer narrower than `int` is extended, and the call carries the variadic marker.

### 9.2 System Calls

```zoril
fn write(fd: u32, buf: [u8]) -> i64 {
    // The kernel reads `buf.len` bytes from `buf.ptr`; the slice vouches for them.
    return unsafe { @syscall(1, fd, buf.ptr, buf.len) };
}
```

`@syscall(num, args...)` emits a direct system call instruction. Arguments are passed in the platform-specific ABI registers (e.g., System V AMD64 or ARM64). It requires `unsafe`: the kernel takes addresses as plain integers, so a call can write or unmap any memory (`unsafe_policy.md` §1). A safe wrapper, like this `write`, takes the address from a value that vouches for it.

### 9.3 String Lowering

String literals are lowered to static global byte arrays with a null terminator. When passed to C functions (extern), they are automatically treated as `*u8` (C-compatible `char*`). In Zoril code, they are `[u8]` slices with `.ptr` and `.len` accessors.

The `.len` field reports the number of content bytes and does **not** count the null terminator (`"hello".len == 5`). The null byte is present in memory at `ptr[len]` for C interoperability but is not visible through the slice interface.

### 9.4 Typed File Descriptors

```zoril
// fd<r> = read-only, fd<w> = write-only, fd<rw> = read-write
```

File descriptors are linear resources. The verifier enforces:

- `fd_read` requires `fd<r>` or `fd<rw>`
- `fd_write` requires `fd<w>` or `fd<rw>`
- `fd_close` consumes the descriptor (rejecting double-close)
- Unclosed descriptors at scope exit are a leak error

## 10. Standard Library

The standard library is Zoril source in `stdlib/` (`$DATADIR/zoril/stdlib` when installed), brought in with `import`. Its types and functions are specified in [standard_library.md](standard_library.md) and documented module by module in the manual pages (`man zoril-stdlib`, `man zoril-<module>`, section 3).

## 11. Modules and Compile-Time Safety

### 11.1 Modules

#### 11.1.1 Imports and Namespaces

An import makes a namespace named by the imported file's stem, or by an `as` name. An item of another module is written through its namespace, or brought in bare by `use`:

```zoril,no-test
import "stdlib/io.zrl";          // the namespace `io`
import "stdlib/mem.zrl" as m;    // the namespace `m`
use io::write;                       // `write` written bare
use m::Arena;

fn main() -> i32 {
    let _ = write(1, "hi\n");
    let _ = io::write(1, "and qualified\n");
    let a = Arena.new(4096 as u64).unwrap();
    ...
}
```

- `ns::item` names a public item of the module imported as `ns`, wherever a name can appear: expressions, types (`v::Vec<i32>`), patterns (`core::Option.Some(x)`) and struct literals. `ns::T.f()`, `ns::T::f()` and `ns::T::CONST` reach a type's methods and constants.
- `use ns::name;` and `use ns::{a, b};` bring public items in, to be written bare. A `use` of an unknown or private item, or of a name the file defines itself, is an error; `pub use` is not supported.
- A bare name is, in order: the file's own item, one a `use` brings in, one of the **prelude** (the public items of `core.zrl` and `core0.zrl`: `Option`, `Result`, `ICE`, ..., in scope in every module of a program that loads core), or a builtin type.
- A file sees only the modules it imports itself, not their imports.
- A module's name is its file stem. The root program may have any file name (nothing names it), but a module that is imported must have an identifier as its name - not a keyword, not starting with a digit, with no `-`, `.` or space - and the compiler says so at the `import` (`module name 'my-mod' is not an identifier; rename the file`), `as` or not.
- Two imports with one stem are an error asking for `as`; two modules may each define a public item of one name, told apart by their namespaces.
- Methods go with their type: `x.f()` and `T.f()` find `f` in any impl of `T`, whichever module the impl is in. Naming the method is still the module boundary's business: without `pub` on it, only the module that declares the impl may call it (`cannot access private method: f`), as with a private field. An impl of a trait is public, as the trait is, so its methods need no `pub`.
- A method body is checked whether or not anything calls it. A whole-program build lowers every method of every `impl` whose target type is written with no type parameter (`impl S`, `impl Tr for S`, `impl Clone for i32`, `impl W<i32>`, `impl Pair<u8, bool>`) in the program, in its own module and in its imports, `pub` or not, a trait's default body included; a method of an `impl` with a free type parameter - one that declares parameters of its own (`impl<A> Tr<A> for S`) or whose target is written with one (`impl<T> W<T>`, and `impl W<T>`, which names the target type's own) - is checked when an instance is made, like a generic method's body. A method cannot ship with a field, name, privacy, type or borrow error that surfaces first in the build of whoever calls it - which was the _caller's_ error, about code it did not write (`Driver.check_uncalled_methods`, `Monomorphizer.impl_target_is_concrete`; the specialisation's half is `tests/error_reporting/err_uncalled_specialization_method_checks.zrl` with its accepted twin).
- The bodies nothing calls are dropped again before the ZIL is written, so what a program emits and runs is what its _called_ code lowers to, byte for byte. A `-c` build applies the same rule to the public methods of its target module (`Driver.instantiate_impl_methods`), which is as much of it as one TU can carry: a private method nothing calls is left to the whole-program build that can see the whole program, and a module built only through `-c` may therefore report an error only when the program is built whole.
- A _generic_ method's body is checked when it is instantiated: it has no `Self` or type arguments to check against before then, and instantiating is the first moment its body is a body. `fn bad<T>(x: T) -> i32 { return x.nope; }` is accepted while nothing calls `bad`, and rejected at the call that makes `T` concrete (`tests/language/generics/uncalled_generic_method_not_checked.zrl`, `tests/error_reporting/err_generic_method_body_instantiated.zrl`).
- A pattern naming a constant that is not in scope is an error (it would otherwise bind a new variable that matches everything).

#### 11.1.2 Encapsulation (Private by Default)

Only items marked with `pub` are accessible from other modules. This includes struct fields: a field not marked `pub` cannot be read, written, or named in a struct literal outside the file that declares the struct (`cannot access private field: bytes`), which is what lets a type such as `Str` guarantee an invariant through its constructors.

#### 11.1.3 One Module per File

A module imported from several files is one module: it is loaded and checked once, and every importer sees the same items and the same statics.

### 11.2 Compile-Time Memory Safety

For the complete safety matrix, compiler mechanisms across the two-level ZIR/ZIL pipeline, architectural boundaries, and test proofs for every claim, see [safety_model.md](safety_model.md).

#### 11.2.1 Intra-procedural Arena Analysis

The compiler statically verifies that constant-size allocations do not exceed constant-size arena capacities within a single function.

#### 11.2.2 Inter-procedural Propagation

The compiler propagates allocation requirements up the call stack to verify arena safety across function boundaries.

#### 11.2.3 Runtime Bounds Checking

Indexing a slice or a fixed-size array is bounds-checked at run time. An out-of-range index traps with exit code 134 (128 + `SIGABRT`) rather than reading or writing past the end. For a slice the bound is its `len`; for an array it is the size in its type. The trap is a raw `exit` syscall, not a call into the standard library, so it works in a program that imports nothing. An index into a fixed-size array that is written as a constant (`data[99]`, `d[3 as usize]`, the array reached directly or through a reference) is checked at compile time instead: out of range, it is an error (`index 99 is out of bounds for an array of length 3`).

**Indexing a raw pointer is deliberately not checked.** A pointer carries no length, so there is nothing to check against. This is the one indexing form that can read out of bounds, and it is intentional — see `tests/language/memory/bounds_ptr_unchecked.zrl`, which asserts it.

> **Scope, stated precisely.** This covers _indexing_. It is not a general memory-safety guarantee: a pointer produced from an arbitrary integer is safe to create, but restricting where it may be _used_ to `unsafe` is all that stands between it and any address in the process. A specification that overclaims here is worse than one that underclaims.

#### 11.2.4 Region Outlives

Returning a pointer into the current function's own stack storage is rejected at compile time (probe [`05_dangling_stack_direct.zrl`](../../bench/safety_matrix/probes/05_dangling_stack_direct.zrl)):

```zoril,no-test
fn dangle() -> *mut S {
    let mut s = S { a: 1 };
    return &mut s;      // error: region escape: returning a pointer to local stack storage
}
```

The check keys on whether the returned value _points into_ local storage, not on its declared type. Returning a pointer derived from a pointer **parameter** is therefore accepted, as is returning a pointer read out of a local that holds only non-stack pointers — the local holds the pointer, it is not what the pointer points at.

Holding the address in between does not hide it. These are rejected too: keeping it in a local and returning that; returning a struct, tuple or slice that contains it (including a slice over a local array); and writing it anywhere that outlives the call — through a pointer parameter, into a global, or into a heap allocation (probes [`45_dangling_stack_via_local.zrl`](../../bench/safety_matrix/probes/45_dangling_stack_via_local.zrl), [`46_dangling_stack_in_struct.zrl`](../../bench/safety_matrix/probes/46_dangling_stack_in_struct.zrl), [`47_dangling_stack_in_tuple.zrl`](../../bench/safety_matrix/probes/47_dangling_stack_in_tuple.zrl), [`49_dangling_stack_slice_return.zrl`](../../bench/safety_matrix/probes/49_dangling_stack_slice_return.zrl), [`51_dangling_stack_out_param.zrl`](../../bench/safety_matrix/probes/51_dangling_stack_out_param.zrl), [`52_dangling_stack_static.zrl`](../../bench/safety_matrix/probes/52_dangling_stack_static.zrl), [`53_dangling_stack_in_box.zrl`](../../bench/safety_matrix/probes/53_dangling_stack_in_box.zrl)):

```zoril,no-test
fn leak(out: &mut *mut i32) {
    let mut x: i32 = 42;
    *out = &mut x;      // error: region escape: a pointer to local stack storage is written
}                       //        to memory that outlives this function
```

The tracking is per local, not per field, so it errs toward rejecting: a pointer read from a local that also holds a stack pointer somewhere in it is treated as a stack pointer.

The same holds across calls. Each function's body is summarized by where its result may point (into a parameter's own storage, or only into what the parameter references) and by which parameters' storage it stores away, and into what; the summaries travel in `.zri` interfaces. So a stack pointer handed to a callee cannot come back out of the frame either way:

```zoril,no-test
fn stash(p: *mut S) -> *mut S { return p; }
fn leak() -> *mut S {
    let mut s = S { a: 1 };
    return stash(&mut s);   // error: region escape: returning a pointer to local stack storage
}

struct H { r: &i32 }
fn put(h: &mut H, p: &i32) { h.r = p; }
fn fill(h: &mut H) {
    let x = 5;
    put(h, &x);             // error: ... written to memory that outlives this function
}
```

The distinction the summary draws is what keeps arenas usable: `c.get()` returning `&self.v` on a local `c` is rejected (probe [`92_ref_into_local_returned_through_call.zrl`](../../bench/safety_matrix/probes/92_ref_into_local_returned_through_call.zrl), [`tests/error_reporting/err_ref_into_local_through_call.zrl`](../../tests/error_reporting/err_ref_into_local_through_call.zrl)), while `v.as_slice()` or `v.get(i)` on a local `Vec`, which point into the `Vec`'s buffer, may be returned. What is not followed: calls through a function pointer, and pointers rebuilt from integers other than by pointer-sized arithmetic, both only in `unsafe` code.

#### 11.2.5 Non-null references and the `unsafe` boundary

**A reference or function pointer obtained without `unsafe` is non-null**, including through an aggregate or a pattern binding, which keep a raw pointer's type (row "Raw Pointer Laundered Through an Aggregate or Binding" in [safety_model.md](safety_model.md#2-safety-properties-matrix), probe [`158_launder_null_ref_tuple.zrl`](../../bench/safety_matrix/probes/158_launder_null_ref_tuple.zrl)); every route to a null one is closed or gated (probes [`14_null_deref.zrl`](../../bench/safety_matrix/probes/14_null_deref.zrl), [`26_null_fn_pointer.zrl`](../../bench/safety_matrix/probes/26_null_fn_pointer.zrl), [`31_null_deref_unsafe.zrl`](../../bench/safety_matrix/probes/31_null_deref_unsafe.zrl), [`32_null_fn_pointer_unsafe.zrl`](../../bench/safety_matrix/probes/32_null_fn_pointer_unsafe.zrl)):

- `0 as &T`, `0 as &mut T` and `0 as fn(...) -> R` are rejected outright, as is the generic form `(0 as u64) as T` where `T` is instantiated with a reference type ([`tests/error_reporting/err_cast_null_ref.zrl`](../../tests/error_reporting/err_cast_null_ref.zrl), [`tests/error_reporting/err_cast_null_fn.zrl`](../../tests/error_reporting/err_cast_null_fn.zrl), probe [`29_generic_null_cast.zrl`](../../bench/safety_matrix/probes/29_generic_null_cast.zrl)).
- A reference can otherwise only be forged from a raw pointer, `let r: &T = &*p;`, and that dereference requires `unsafe`. The same holds for loading a function pointer out of a raw-pointer aggregate, `let f = (*v).call;`.

So `Option<&T>` is a guarantee rather than a convention: the `Some` case cannot itself hold null.

**Raw pointers stay nullable, and that is the boundary.** `0 as *T` and `0 as *mut T` are accepted — raw pointers are the documented unchecked escape hatch (§11.2.3), and a null check on every dereference would cost a branch per access for a guarantee the type already declines to make. Inside `unsafe { }`, dereferencing a null raw pointer is unchecked and faults with `SIGSEGV`; that is the intended behaviour, not an omission.

> **What this section does and does not claim.** It claims that _unmarked_ code cannot produce a null reference or function pointer (subject to the aggregate laundering gap above). Non-dangling is §11.2.4's subject, with its own limits (calls through function pointers); nor does it claim that `unsafe` code cannot produce a null one — it plainly can, and `bench/safety_matrix/probes/31_null_deref_unsafe.zrl` and `32_null_fn_pointer_unsafe.zrl` assert exactly that, while `14_null_deref.zrl` and `26_null_fn_pointer.zrl` assert the unmarked forms are compile errors. The guarantee is about reachability, and it is pinned from both sides.

`doc/spec/unsafe_policy.md` is normative for the marker itself: which operations it permits, why it does not disable the other checks, the role of `unsafe fn` for interfaces whose safety contract cannot be verified, and why block granularity is preferred for internal logic.

#### 11.2.6 Integer width: conversions, shifts, and where the wrapping rule stops

Zoril's arithmetic wraps modulo $2^N$ rather than trapping. This section states the three places where operand _width_ enters that rule, because "wraps modulo $2^N$" does not by itself say what $N$ is, and in two of the three cases the answer today is not the one the type declares.

**A conversion that drops bits must be written.** An implicit conversion — `let`, assignment, argument passing, `return`, or a struct-literal field — is accepted only when it cannot lose information. Widening is implicit:

```zoril,no-test
let a: u8  = 200 as u8;
let b: u32 = a;             // ok: u8 fits in u32
```

Narrowing is rejected, and `as` is how you ask for it (probes [`37_implicit_narrowing.zrl`](../../bench/safety_matrix/probes/37_implicit_narrowing.zrl), [`20_narrowing_cast.zrl`](../../bench/safety_matrix/probes/20_narrowing_cast.zrl)):

```zoril,no-test
let big: u32 = 300 as u32;
let c: u8 = big;            // error: cannot implicitly narrow 32-bit value to 8 bits
let d: u8 = big as u8;      // ok: 44. `as` is the marker, exactly as `unsafe` is for raw pointers
```

This is the same shape as the raw-pointer boundary in §11.2.3: the operation stays available and stays unchecked, but it cannot happen without a syntactic mark a reader can grep for. `as` still truncates silently and deliberately — the decision recorded here is that _silence plus invisibility_ was the defect, not truncation itself. `bench/safety_matrix/probes/37_implicit_narrowing.zrl` pins the rejection and `20_narrowing_cast.zrl` pins that `as` still truncates.

Floats follow the same rule: `f32` to `f64` is implicit, but `f64` to `f32`, and any conversion between an integer type and a float type (which loses a fraction, or an integer's low bits), must be written with `as`.

The operands of a binary operator follow it too. Two numeric operands of different types meet at the wider one (`u8 + u32` is a `u32`, `i32 + i64` an `i64`); a pair where neither converts to the other without loss, such as an integer and a float, is an error. A compound assignment converts its right side to the target's type as `=` does, so `x += wide` with a narrower `x` is an error. A shift's count is not converted: it may be any integer type.

A negative literal is typed against its destination, so `let x: i32 = -2147483648;` is accepted: the magnitude does not fit in `i32` but the negated value does, and the two are not lowered separately.

An integer literal must be a value of its type: `let a: u8 = 300;`, `let b: u32 = -1;` and a `-1` pattern on a `u32` are errors. A literal with nothing giving it a type is an `i32`, an `i64` when it does not fit one, and a `u64` when it does not fit that (`0xffffffffffffffff as u64`).

**A shift count must be in `[0, width)` of the shifted type.** `<<`, `>>`, `<<=` and `>>=` with a count outside that range are an error:

- a **constant** count is checked at compile time (`x << 32` on a `u32` does not compile), so an in-range constant shift carries no run-time check at all;
- a **variable** count is checked at run time, and an out-of-range one traps like a failed bounds check (exit 134). The count is compared unsigned, so a negative count traps too.

Without the check the hardware would mask the count to the width of the _register_ the shift is emitted in (5 bits for everything up to 32-bit, 6 for 64-bit), so `1u32 << 32` would be `1` and `1u8 << 40` would shift by 8: a silent, platform-dependent wrong answer. When masking is what an algorithm wants, say so with `@shl_wrap(x, n)` / `@shr_wrap(x, n)`: the count is masked to the _operand's_ width (`@shl_wrap(1u8, 9)` is `2`), and no check is emitted.

**Sub-word arithmetic wraps at its declared width, not the register's.** A `u8`, `i8`, `u16` or `i16` result of `+`, `-`, `*`, `/` or `<<` is masked back down to the declared width, so the value is inside its own type whether it is still a temporary or has been stored:

```zoril,no-test
let a: u8 = 200 as u8;
let stored: u8 = a + 100 as u8;   // 44
a + 100 as u8 == 44 as u8         // true — the temporary is 44 as well
```

This is what "wraps modulo $2^N$" means for narrow types, and $N$ is the declared width. The mask applies to plain `+`, `-`, `*`, `/` and `<<` as well as the explicitly wrapping `+%`, `-%` and `*%`, so a plain `200u8 + 100u8` is 44 whether it is held in a temporary or stored. `u32` and `u64` need no extra masking, since a 32-bit register truncates a `u32` by itself.

Note the interaction with the previous paragraph: `1u8 << 40` masks the _count_ to 8 (a machine property) and then masks the _result_ to 8 bits (a language property), giving 0. The two masks are unrelated, and only the second is something the specification guarantees.

#### 11.2.7 Stack exhaustion

Unbounded recursion is not diagnosed and not guarded. There is no stack probe, no recursion-depth limit, and no guard-page handler: the process touches the guard page and dies with `SIGSEGV` (exit 139), the same way a null dereference inside `unsafe { }` does.

**The cost of this is triage, not safety.** No memory is corrupted — the fault is the kernel stopping the program at the boundary, which is the outcome a stack probe would also produce. What is lost is the ability to tell the two apart from the outside: an exit code of 139 does not say whether the program ran out of stack or followed a bad pointer, and those have very different causes. A compiler that emitted a distinguishable diagnostic would not be safer, it would be easier to debug.

This is **accepted as-is**, on the same grounds as division by zero (§ "Division by Zero" in `doc/spec/safety_model.md`): a deterministic fault with no diagnostic. It is not scoped by `unsafe` and cannot be — recursion is ordinary code. `bench/safety_matrix/probes/25_stack_overflow.zrl` pins the fault.
