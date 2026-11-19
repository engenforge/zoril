# Zoril Surface Language Specification

This document specifies the Zoril surface language (`v0.1.0-alpha`).

## 1. Overview

Zoril is a statically typed, imperative, expression-oriented systems programming language with immutable-by-default bindings, algebraic data types, static generics, and compile-time ownership and borrow checking.

- **Source file extension**: `.zrl`
- **Paradigm**: Imperative and expression-oriented with sum types, exhaustive pattern matching, traits, and monomorphized generics
- **Memory model**: Value semantics with structural `Copy`, move ownership, non-lexical borrowing, deterministic scope-exit drops, and explicit `unsafe` boundaries

## 2. Lexical Elements

### 2.1 Keywords and Reserved Words

The following words are **keywords** and cannot be used as identifiers:

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

The following words are **reserved** for future language features and produce a compile-time error wherever they appear as identifiers: `async`, `await`, `dyn`, `move`, `where`, `yield`, `macro`, `union`, `super`.

An identifier begins with an ASCII letter or `_`, followed by any number of ASCII letters, digits, or `_`.

### 2.2 Comments

- Single-line comments begin with `//` and extend to the end of the line.
- Multi-line block comments are delimited by `/*` and `*/` and nest arbitrarily (`/* outer /* inner */ */`).

### 2.3 Literals

| Kind      | Examples                                                                     |
| --------- | ---------------------------------------------------------------------------- |
| Integer   | `0`, `42`, `0xFF`, `0b1010`, `0o755`, `1_000_000`, `0u64`, `42i32`, `1usize` |
| Float     | `3.14`, `0.5`, `1_000.5`, `1.0f32`, `2.5f64`                                 |
| Boolean   | `true`, `false`                                                              |
| String    | `"hello\n"`, `r"C:\path\to\file"`                                            |
| Character | `'a'`, `'\n'`, `'\x41'`                                                      |

**Numeric literals** may contain `_` as a visual separator. Integer literals accept decimal, hexadecimal (`0x`), binary (`0b`), and octal (`0o`) prefixes and optional type suffixes:

- **Integer suffixes**: `u8`, `u16`, `u32`, `u64`, `usize`, `i8`, `i16`, `i32`, `i64`, `isize`
- **Float suffixes**: `f32`, `f64`

An unsuffixed integer literal takes its type from the surrounding context when an integer or float type is expected (`let d: f64 = 5;`); otherwise it defaults to `i32`, widening to `i64` or `u64` if the value does not fit. A literal must fit the range of its resolved type (§11.2.6).

A floating-point literal represents the IEEE 754 value nearest its decimal notation. It has type `f32` if suffixed with `f32` or if an `f32` is expected; otherwise it has type `f64`.

**String literals** have type `[u8]` (a read-only byte slice) and recognize the escape sequences `\n`, `\t`, `\r`, `\0`, `\\`, `\"`, `\'`, and `\xHH`. **Raw string literals**, prefixed with `r` (e.g., `r"raw\text"`), interpret backslashes literally and may span multiple lines.

**Character literals** denote a single byte and have type `u8` (which converts implicitly to `char`; §2.7).

### 2.4 Annotations

Annotations (built-in intrinsics) begin with `@` and modify or form an expression:

| Annotation               | Meaning                                                                               |
| ------------------------ | ------------------------------------------------------------------------------------- |
| `@likely(expr)`          | Branch prediction hint favoring the taken path                                        |
| `@unlikely(expr)`        | Branch prediction hint favoring the not-taken path                                    |
| `@syscall(num, args...)` | Direct OS system call (`unsafe`; returns `i64`)                                       |
| `@drop(x)`               | Explicitly consume and drop `x` (§8.4)                                                |
| `@slice(ptr, len)`       | Construct a slice from pointer and length (`unsafe` unless `len` is literal `0`)      |
| `@ptr_cast<T>(expr)`     | Reinterpret-cast to pointer type `T` (`unsafe` for `&T`, `&mut T`, or slices)         |
| `@ptr_from_int<T>(n)`    | Construct a pointer of type `T` from integer `n` (`unsafe` for `&T`, `&mut T`, `[T]`) |
| `@int_cast<U>(expr)`     | Cast a value to integer type `U` (follows `as` rules; §2.7)                           |
| `@str("literal")`        | Construct a validated UTF-8 `Str` from a string literal (compile error if invalid)    |
| `@shl_wrap(x, n)`        | Left shift with `n` masked to the bit width of `x` (never traps; §11.2.6)             |
| `@shr_wrap(x, n)`        | Right shift with `n` masked to the bit width of `x` (never traps; §11.2.6)            |
| `@alloca<T>(count)`      | Allocate uninitialized stack storage for `count` elements of `T` (`unsafe`)           |

### 2.5 Attributes

Attributes are written `#[...]` immediately before the declaration they modify:

- **`#[must_use]`**: On a function; emits a compiler warning if the return value is discarded without being bound and used or explicitly ignored with `let _ = ...`.
- **`#[derive(Clone)]`**: On a struct; generates a field-by-field `Clone` implementation (§8.5).
- **`#[borrows(p, ...)]`**: On a function; declares that any reference or view returned by the function may point only into the listed parameters, or into none of them for `#[borrows()]` (§7.2).
- **`#[unsafe(borrows(p, ...))]`**: On a function; declares a narrower `#[borrows(..)]` contract that the compiler trusts beyond what static analysis proves (for example, returning a slice read through a raw pointer into longer-lived memory). Calling the function remains safe; the `unsafe` marks the trusted assumption on the declaration. `unsafe(..)` marks no other attribute (§7.2).
- **`#[stores(p -> q, ...)]`**: On a function; declares that the body stores parameter `p`'s storage into memory reached through `q` (omitting `-> q` targets `self`; `-> static` targets global memory). Checked against the function body (§7.2).
- **`#[fresh]`**: On an `unsafe fn` whose written return type is a raw pointer (`*T` or `*mut T`; type aliases are not accepted): asserts that each call returns newly allocated memory reachable by no other live pointer (or an error sentinel tested before use). The compiler checks only placement and return type; the freshness claim itself is trusted.

Compiler-generated module interfaces may also contain `#[summary(...)]` and `#[export]`; neither is part of user-written source syntax.

Example of `#[must_use]`:

```zoril
#[must_use]
fn allocate_resource() -> i32 { return 1; }

fn use_val(x: i32) {}

fn main() {
    let r = allocate_resource();
    use_val(r);                  // ok: result is used
    let _ = allocate_resource(); // ok: explicit wildcard discard
}
```

### 2.6 Operators and Punctuation

Operators are listed below from highest to lowest precedence. Unlike C, bitwise operators (`&`, `^`, `|`) bind tighter than comparison operators (`x & MASK != 0` parses as `(x & MASK) != 0`).

| Prec | Class          | Operators                                                                  | Assoc |
| ---- | -------------- | -------------------------------------------------------------------------- | ----- |
| 13   | Postfix        | `e.field`, `e.0`, `e[i]`, `e(args)`, `e?`, `e::<T>`                        | Left  |
| 12   | Unary / Prefix | `-e`, `!e`, `*e`, `&e`, `&mut e`, `box e`, `try e`                         | Right |
| 11   | Type cast      | `e as T`                                                                   | Left  |
| 10   | Multiplicative | `*` `/` `%` `*%`                                                           | Left  |
| 9    | Additive       | `+` `-` `+%` `-%`                                                          | Left  |
| 8    | Shift          | `<<` `>>`                                                                  | Left  |
| 7    | Bitwise AND    | `&`                                                                        | Left  |
| 6    | Bitwise XOR    | `^`                                                                        | Left  |
| 5    | Bitwise OR     | `\|`                                                                       | Left  |
| 4    | Comparison     | `==` `!=` `<` `<=` `>` `>=`                                                | None  |
| 3    | Logical AND    | `&&` (short-circuit)                                                       | Left  |
| 2    | Logical OR     | `\|\|` (short-circuit)                                                     | Left  |
| 1    | Assignment     | `=` `+=` `-=` `*=` `/=` `%=` `+%=` `-%=` `*%=` `&=` `\|=` `^=` `<<=` `>>=` | Right |

Because postfix `.` binds tighter than prefix `*`, accessing a field through a raw pointer requires parentheses: `(*ptr).field`.

**Key operator rules:**

- **Borrowing (`&`, `&mut`)**: Creates an immutable (`&T`) or mutable (`&mut T`) reference to a place. A `Box<T>` or `&Box<T>` does not implicitly coerce to `&T`; borrow its contents explicitly with `&*b` or `&mut *b`. Field access and method calls dereference `Box<T>` automatically (`b.field`, `b.method()`).
- **Non-associative comparisons**: Chained comparisons such as `a < b < c` are a parse error; write `a < b && b < c`.
- **Boolean discipline**: `bool` does not mix with numeric types. Arithmetic, shift, and relational operators reject `bool`; `==`, `!=`, `&`, `|`, and `^` accept two `bool` operands; `&&`, `||`, `if`, and `while` require `bool`.
- **Arithmetic operands**: Standard arithmetic (`+`, `-`, `*`) performs wrapping two's-complement arithmetic for integers (§11.2.6). The explicit wrapping operators (`+%`, `-%`, `*%`) behave identically and document intentional wraparound. Only `+` and `-` on raw pointers inside `unsafe` perform pointer arithmetic.
- **Equality (`==`, `!=`)**: Defined for integers, floats, `bool`, `char`, pointers (`*T`, `*mut T`, `Box<T>`, comparing addresses), fieldless enums (comparing discriminants), and slices `[T]` of identical element type where `T` is an integer, `bool`, `char`, or pointer (comparing length and elements). Equality on structs, tuples, arrays, payload-carrying enums, function values, or slices of floats/aggregates is a compile-time error; use `match`, field comparisons, or an `Eq` trait implementation.
- **Assignment targets**: The left-hand side of `=` or a compound assignment must be a mutable place (local, parameter, static, field, tuple index, array/slice index, or dereference). Assignments yield `unit`.

```zoril
fn check_ptr(p: *i32, q: *i32) -> bool {
    let null: *i32 = 0 as *i32;
    if p == null { return true; }
    if p != q { return true; }
    return false;
}
```

#### Punctuation

```
( ) { } [ ] < >
; : :: , . .. ..= ...
-> =>
```

### 2.7 Type Casting Rules

Explicit casts use `expr as T`:

| From                           | To                     | Semantics                                                        |
| ------------------------------ | ---------------------- | ---------------------------------------------------------------- |
| Any integer                    | Any integer            | Truncates (modularly) or zero-/sign-extends                      |
| Integer                        | Float (`f32`, `f64`)   | Numeric conversion; may lose precision                           |
| Float                          | Integer                | Truncates toward zero                                            |
| `u8`                           | `char`                 | Widens byte (`0..=255`) to Unicode scalar value                  |
| `char`                         | Integer                | Extracts scalar code point (truncating if narrower than 32-bit)  |
| Fieldless enum                 | Integer                | Extracts discriminant value                                      |
| `u64`, `i64`, `usize`, `isize` | `*T`, `*mut T`         | Reinterprets as raw address (`0 as *T` is null; use is `unsafe`) |
| Raw pointer                    | `u64`, `usize`         | Reinterprets pointer address as integer                          |
| `*T`                           | `*mut T` (and reverse) | Changes raw-pointer mutability                                   |
| `[mut T]`                      | `[T]`                  | Drops element write access (reverse is an error)                 |
| Raw pointer                    | `extern "C" fn(..)`    | Reinterprets as C function pointer (`unsafe` only; §3.9)         |

**Disallowed casts:**

- Casting to a reference (`&T`, `&mut T`), Zoril `fn` value, linear handle (`fd<..>`, `async_context`), slice (other than `[mut T] as [T]`), array, tuple, struct, enum, or `Box<T>` is a compile-time error unless it is an identity cast (including through type aliases).
- Casting an integer to a type parameter `T` or associated type `T::Assoc` is a compile-time error; other casts to a type parameter are allowed only between scalar primitives.
- Casting a number to `bool` or a non-`u8` number to `char` is a compile-time error outside `unsafe`. Inside `unsafe` the cast compiles and validity is the caller's obligation (a forged `bool` reaching a two-armed `match` traps with exit code 1).
- `@int_cast<T>`, `@ptr_cast<T>`, and `@ptr_from_int<T>` enforce the same validity rules as `as`.

**Implicit conversions:**

- **Widening** between numeric primitives is implicit only when no bits or precision are lost: an integer converts implicitly to an integer of equal or greater bit width, and `f32` converts implicitly to `f64`. Narrowing (`u32` to `u8`, `f64` to `f32`) and all integer-to-float or float-to-integer conversions require explicit `as` (§11.2.6).
- `u8` converts implicitly to `char`; no other numeric type converts implicitly to or from `char`.
- `bool` never converts implicitly.
- In binary arithmetic and comparisons, two numeric operands of different types promote to the wider type when one converts implicitly to the other; otherwise the expression is a compile-time error.

## 3. Type System

### 3.1 Primitive Types

| Type                   | Size          | Description                                                            |
| ---------------------- | ------------- | ---------------------------------------------------------------------- |
| `bool`                 | 1 byte        | Boolean (`true` or `false`)                                            |
| `u8` `u16` `u32` `u64` | 1/2/4/8 bytes | Unsigned two's-complement integers                                     |
| `i8` `i16` `i32` `i64` | 1/2/4/8 bytes | Signed two's-complement integers                                       |
| `usize` `isize`        | Pointer-sized | Unsigned/signed pointer-width integers (8 bytes on 64-bit targets)     |
| `f32`                  | 4 bytes       | IEEE 754 single-precision float                                        |
| `f64`                  | 8 bytes       | IEEE 754 double-precision float                                        |
| `char`                 | 4 bytes       | Unicode scalar value (`U+0000`–`U+D7FF`, `U+E000`–`U+10FFFF`)          |
| `unit` / `()`          | 0 bytes       | Empty type (the 0-tuple)                                               |
| `never`                | —             | Bottom type; coerced to any expected type; produced by diverging forms |

An expression has type `never` if it never yields a value: `return`, `break`, `continue`, a block ending in a diverging expression, or an `if`/`match` in which every branch diverges.

### 3.2 Pointer Types

| Syntax   | Description                                 |
| -------- | ------------------------------------------- |
| `&T`     | Immutable non-null reference to `T`         |
| `&mut T` | Mutable exclusive non-null reference to `T` |
| `*T`     | Immutable nullable raw pointer to `T`       |
| `*mut T` | Mutable nullable raw pointer to `T`         |

Creating a raw pointer is safe; dereferencing or indexing one requires `unsafe` (§11.2.5).

### 3.3 Box (Owned Heap Pointer)

`Box<T>` is an owned, always-mutable heap allocation created with `box expr` (§7.4). Currently a `Box<T>` is not automatically freed at scope exit and its pointee's `Drop` does not run automatically; short-lived allocations should use the stack or an arena.

### 3.4 Arrays

`[T; N]` is a fixed-size homogeneous array of `N` elements. Arrays can be constructed as element lists (`[1, 2, 3]`, trailing commas allowed) or repeat literals (`[0; 16]`).

Array lengths and repeat counts must fit in `u32` (at most `4294967295`). Types whose total byte size exceeds `isize::MAX` or whose by-value nesting depth exceeds 100 levels are compile-time errors.

### 3.5 Slices

`[T]` is a read-only fat pointer (pointer + element count) viewing a contiguous sequence of `T`; `[mut T]` is a mutable slice permitting element writes (`s[i] = v`, `&mut s[i]`, `&mut self` methods on elements). String literals produce `[u8]`.

- Borrowing an array `[T; N]` with `&a` coerces to `[T]` where a slice is expected; `&mut a` on a mutable array coerces to `[mut T]`. The slice keeps `a` borrowed while live.
- `[mut T]` coerces implicitly to `[T]`; the reverse is a compile-time error.
- `&mut [T]` is a mutable reference to a read-only slice header (the slice binding may be replaced, but its elements remain read-only).
- `@slice(p, len)` produces `[mut T]` when `p` is `*mut T` or `&mut T`, and `[T]` otherwise. When `len` is literal `0`, it is safe and produces `[T]` unless `[mut T]` is expected; for any other length, `@slice` requires `unsafe`.

Every slice exposes two compiler-synthesized fields:

| Field  | Type  | Description                                                            |
| ------ | ----- | ---------------------------------------------------------------------- |
| `.ptr` | `*T`  | Raw pointer to the first element                                       |
| `.len` | `u64` | Number of elements (for string literals, excludes the null terminator) |

### 3.6 Tuples

`(T1, T2, ...)` is an anonymous product type. Elements are accessed by zero-based index (`t.0`, `t.1`). `()` is equivalent to `unit`. Tuple literals support trailing commas (`(1, 2,)`); `(x,)` constructs a 1-tuple whereas `(x)` groups an expression.

### 3.7 Structs

User-defined product types with named fields (trailing commas allowed in declarations and literals):

```zoril
struct Point {
    x: i32,
    y: i32,
}
```

Structs may be generic (`struct Wrapper<T> { value: T }`). Explicit type arguments on struct literals may be written with or without `::` (`Wrapper::<i32> { value: 42 }` or `Wrapper<i32> { value: 42 }`), or omitted when inferable from field values:

```zoril
struct Wrapper<T> { value: T }

fn main() {
    let w1 = Wrapper::<i32> { value: 42 };
    let w2 = Wrapper<i32> { value: 42 };
}
```

### 3.8 Enums (Sum Types)

Tagged unions whose variants may optionally carry payloads (trailing commas allowed):

```zoril
enum Option<T> {
    None,
    Some(T),
}
```

Variants are constructed as `Type.Variant` (bare) or `Type.Variant(expr)` (payload), and matched using the same forms (§5.3). Type arguments cannot be attached directly to a bare variant (`Option.None::<i32>` is an error); annotate the binding (`let o: Option<i32> = Option.None;`) or supply type arguments on payload calls (`Option.Some::<i32>(3)`).

Variants may carry explicit integer discriminants with `=`. Omitted tags increment sequentially from `0`:

```zoril
enum TokenKind {
    Ident = 1,
    Int = 2,
    Plus = 43,
}
```

### 3.9 Function Pointer Types

- **`fn(T1, T2) -> R`**: A Zoril function value consisting of two words (a code pointer and an environment pointer). Named functions have a null environment; closures capture their environment (§5.2). Variadic signatures use `...`: `fn(i32, ...) -> i32`.
- **`extern "C" fn(T1, T2) -> R`**: A thin C-ABI function pointer (a single code address with no environment), governed by the `extern` signature rules (§9.1). Only a named `extern "C" fn` definition coerces to it implicitly; ordinary `fn` items, closures, `fn` values, and integers do not. Calling a C function pointer requires `unsafe`. Inside `unsafe`, a raw pointer may be cast to a C function pointer (`p as extern "C" fn(..)`), with non-nullness being the caller's obligation; casting directly from an integer or between distinct C function pointer signatures is a compile-time error.

### 3.10 Generics

Functions, structs, enums, traits, and `impl` blocks may declare type parameters `<T, U, ...>`. All generics are resolved by compile-time monomorphization (§8.1). Type arguments are inferred where possible or specified explicitly via turbofish syntax (`identity::<i32>(42)`, `w.map::<i32>(f)`).

```zoril
fn identity<T>(x: T) -> T { return x; }
struct Pair<A, B> { first: A, second: B }
```

**Item-access convention:** `.` accesses items belonging to types and values (enum variants `Option.Some`, associated functions `Vec.new`, associated constants `T.CONST`, fields, and methods). `::` is used for module paths (`m::item`, `use a::{b, c}`) and turbofish generic instantiation (`::<T>`).

### 3.11 Trait Bounds

Type parameters may require trait implementations using `T: Trait`:

```zoril
trait Display { fn display(self); }
fn print_value<T: Display>(x: T) { x.display(); }
```

### 3.12 Linear Resource Types

`fd<r>` (read-only), `fd<w>` (write-only), `fd<rw>` (read-write), and `async_context` are linear resource types. Each value must be consumed exactly once before its owning scope exits; failing to consume one or consuming it twice is a compile-time error (§9.4).

## 4. Declarations

### 4.1 Functions

```zoril,no-test
[pub] [unsafe] fn name[<T, ...>](param: Type, ...) [-> ReturnType] {
    body
}
```

- Omitting `-> ReturnType` defaults the return type to `unit`. Parameter and argument lists allow trailing commas.
- `pub fn` exports the function from its module (§11.1.2).
- `unsafe fn` declares a function with caller-enforced preconditions. Its entire body is an `unsafe` context; calling it or converting it into a `fn` value requires `unsafe` (§11.2.5).
- `extern fn name(param: Type, ...) [-> ReturnType];` declares a foreign C-ABI function with no body (calling it requires `unsafe`; §9.1).
- `extern "C" fn name(param: Type, ...) [-> ReturnType] { body }` exports a Zoril function with an unmangled symbol and the C calling convention. It cannot be generic or variadic, must obey the `extern` signature rules (§9.1), and must have a unique name across the program. Its body is type- and borrow-checked normally, so Zoril code may call it without `unsafe`. Any runtime trap inside it terminates the process without unwinding through C frames.

### 4.2 Variables

```zoril,wrap
let x: i32 = 42;    // immutable, explicit type
let y = 10;         // immutable, inferred type
let mut z = 0;      // mutable binding
z = z + 1;
```

Bindings are immutable by default. A subsequent `let` in the same or an inner scope may shadow an existing name with a new binding (possibly of a different type); the initializer evaluates in the scope of the previous binding.

`let` accepts any irrefutable pattern (§5.3), with `mut` placed on individual bindings that require mutability:

```zoril,no-test
let (a, b) = pair();
let Point { x, y: mut y2 } = p;
let (mut n, _, Line { a: Point { x: ax, .. }, .. }) = t;
```

A refutable pattern (such as `let Option.Some(x) = opt;`) is a compile-time error; use `if let` or `match`. A wildcard binding (`let _ = expr;`) discards the value without introducing a name and immediately drops any non-`Copy` result.

### 4.3 Structs

```zoril
struct Name {
    field1: i32,
    field2: u64,
}
```

Generic form: `struct Name<T> { field: T }`. Individual fields default to module-private and may be marked `pub` (§11.1.2).

Structs guarantee C-compatible layout: fields are laid out in declaration order at their natural alignment, with total size padded to the largest field alignment. Enums, tuples, slices, and `Box<T>` have unspecified layout.

### 4.4 Enums

```zoril
enum Name {
    Variant1(i32),
    Variant2,
}
```

Generic form: `enum Result<T, E> { Ok(T), Err(E) }`.

### 4.5 Type Aliases

```zoril
type Byte = u8;
type StringSlice = [u8];
```

A type alias defines a transparent synonym for a single type. Generic type aliases (`type Pair<T> = (T, T);`) are not supported.

### 4.6 Traits

```zoril,no-test
trait Name {
    type Assoc;
    fn method(self: &Self, x: i32) -> i32;
    fn provided(self: &Self) -> Self::Assoc { ... }
}
```

A trait declares method signatures, optional default method bodies, and optional associated types (`type Assoc;`).

- `Self` is a special alias (not a keyword) resolved within each `impl Trait for Type` to the implementing concrete `Type`.
- Associated types are defined in each `impl` (`type Assoc = ConcreteType;`) and referenced as `Self::Assoc`, `T::Assoc`, or `Type::Assoc`. Referencing an associated type that has zero or multiple matching `impl` definitions is a compile-time error.
- Traits are module-scoped items addressed through module paths or `use` imports. Prelude traits (`Eq`, `Clone`, `Copy`, `Hash`, `Error`) are in scope automatically; `Drop` is recognized by the language directly (§8.4).

### 4.7 Impl Blocks

```zoril,no-test
impl Type {
    fn method(self: &Type, x: i32) -> i32 { ... }
    pub fn public_method(self: &Type) -> i32 { ... }
    const LIMIT: i32 = 100;
    type Handle = *Type;
}

impl Trait for Type {
    fn method(self: &Type) -> i32 { ... }
}
```

An `impl` block attaches methods, constants, and associated types to a type. An `impl Trait for Type` must define every required method (those without defaults) and every associated type of the trait; its methods are automatically public.

- Associated functions and constants are called on the type (`Type.method(args)` or `Type::method(args)`, `Type.CONST` or `Type::CONST`).
- Method calls (`x.method(args)`) pass `x` (or `&x` / `&mut x`) as `self`, automatically dereferencing through references, raw pointers (in `unsafe`), and `Box<T>`.
- Inherent `impl` blocks may also target slice types, either generic (`impl<T> [T]`) or concrete (`impl [u8]`), with automatic referencing/dereferencing on slice receivers. Duplicate inherent slice methods, overlaps between generic and concrete slice impls, and redefinitions of standard library slice methods are compile-time errors.
- Call argument counts must match non-variadic parameter counts exactly, and must supply at least the fixed parameters for variadic functions.

### 4.8 Constants and Statics

```zoril
const MAX: i32 = 100;
static mut counter: i32 = 0;
```

`const` defines a compile-time constant value; `static` defines a global variable at a fixed address in the program image.

**Constant initializers** are evaluated at compile time and type-checked by the same rules as `let`. Permitted initializer forms are:

- **Integer constant expressions**: integer, `char`, or `bool` literals, named constants, valid casts (including fixed addresses such as `0x40000000 as *mut u32`), unary `-`/`!`, and binary `+ - * / % & | ^ << >>` (with signedness of `/`, `%`, and `>>` determined by the declared type).
- **Float constants**: optionally signed float literals (with optional `f32`/`f64` suffix or cast) or integer constant expressions typed as float. Float arithmetic in constant initializers is not evaluated.
- **Byte strings**: string literals initializing `[u8; N]` where the byte length equals `N`.
- **Fieldless enum variants**: e.g., `static C: Color = Color.Green;`.

Calls, struct/array literals, and references to other `static` items are not valid constant initializers.

**Mutable statics (`static mut`):**

- A `static mut` of a **scalar** type (integer, float, `bool`, `char`, or raw pointer) may be read, written, and borrowed in checked code.
- A `static mut` of a **non-scalar** type (struct, enum, tuple, array, or `Box<T>`) may be read, written, or borrowed only inside `unsafe` (borrows of statics are not tracked across retyping writes).
- A `static mut` cannot have a reference or slice type, or a struct containing one (§11.2.4).
- Immutable `static` items may be read freely in checked code.

### 4.9 Imports

```zoril,no-test
import "path/to/module.zrl";
import "path/to/module.zrl" as alias;
use alias::Item;
```

An `import` loads the target source file (resolved relative to the importing file's directory, then include roots) and binds its namespace. Circular imports are compile-time errors. Module namespacing, visibility, and `use` resolution are specified in §11.1.

## 5. Expressions

Zoril is expression-oriented: blocks, `if`, `if let`, `match`, and `unsafe` blocks produce values.

### 5.1 Expression Kinds

| Kind             | Syntax                                   | Description                                        |
| ---------------- | ---------------------------------------- | -------------------------------------------------- |
| Literal          | `42`, `3.14`, `true`, `'a'`, `"hi"`      | Constant value                                     |
| Variable / Path  | `x`, `m::item`                           | Local, parameter, static, constant, or module item |
| Binary           | `a + b`                                  | Binary operation                                   |
| Unary            | `-x`, `!b`, `*p`, `&v`, `&mut v`         | Prefix operation                                   |
| Call             | `f(args)`, `x.method(args)`              | Function or method invocation                      |
| Block            | `{ stmts; expr }`                        | Lexical scope yielding trailing expression         |
| Unsafe block     | `unsafe { stmts; expr }`                 | Block permitting `unsafe` operations (§11.2.5)     |
| If               | `if cond { ... } else { ... }`           | Conditional expression                             |
| If let           | `if let pat = expr { ... } else { ... }` | Pattern-conditional expression (§6.1)              |
| Match            | `match expr { arms }`                    | Exhaustive pattern match (§5.3)                    |
| Struct literal   | `Point { x: 1, y: 2 }`                   | Struct construction                                |
| Member access    | `expr.field`, `expr.0`                   | Struct field or tuple element access               |
| Index            | `expr[index]`                            | Array, slice, or raw-pointer indexing              |
| Box              | `box expr`                               | Global-heap allocation (§7.4)                      |
| Cast             | `expr as Type`                           | Explicit type conversion (§2.7)                    |
| Try              | `expr?`, `try expr`                      | Early error propagation                            |
| Array literal    | `[1, 2, 3]`, `[0; 8]`                    | Array construction                                 |
| Tuple literal    | `(a, b, c)`                              | Tuple construction                                 |
| Closure          | `\|params\| { body }`, `\|params\| expr` | Anonymous function value (§5.2)                    |
| Sizeof / Alignof | `sizeof(T)`, `alignof(T)`                | Compile-time size or alignment in bytes (`usize`)  |
| Annotation       | `@syscall(...)`, `@slice(...)`, ...      | Built-in intrinsic (§2.4)                          |
| Diverging        | `return [e]`, `break`, `continue`        | Control transfer with type `never`                 |

### 5.2 Closures

```zoril,wrap
let add = |x: i32, y: i32| -> i32 { x + y };
let inc = |x: i32| -> i32 { x + 1 };
```

```zoril,no-test
let double = |x: i32| x * 2;
apply(|x| x * 2, 3); // parameter type inferred from expected fn(i32) -> i32
```

Parameter types may be omitted when an expected function type is available from context (call argument, `let` annotation, struct field, or resolved generic method). If `-> R` is omitted, the return type is taken from context or inferred from the body (aggregate return types must be annotated when no expected function type is present).

A closure produces a `fn(..) -> R` value (two words: code pointer and environment pointer). Its environment lives in the creating stack frame, so returning a capturing closure or storing it where it can outlive its creating frame is a region-escape error (§11.2.4).

**Capture semantics:** Closures implicitly capture referenced outer locals at the point of closure creation, with no explicit capture list:

- **`Copy` values are copied.** Later changes to the outer binding are not seen by the closure. Assigning to or mutably borrowing a captured `Copy` binding inside the closure is a compile-time error; capture a `&mut` reference instead.
- **Owning (non-`Copy`) values are moved** into the closure environment (collections, `Box<T>`, `Arena`, `Drop` types, or aggregates containing them). The outer binding becomes moved and cannot be used or dropped afterwards. Inside the closure, the environment owns the capture across calls: mutating it, reading it, and matching it by reference are permitted, while moving it (or any non-`Copy` field/element/payload of it) out or calling `@drop` on it is a compile-time error. A view into an owned capture counts as frame-owned storage and cannot escape the closure.
- **References are copied as references and retain their borrows** while the closure is live. Mutating through a captured `&mut T` mutates the referent. Rebinding an outer variable directly is not possible.

**Function value restrictions:** `fn` values cannot be compared with `==`, cast with `as`, stored in a `const` or `static`, or passed across `extern` C boundaries (use `extern "C" fn` callbacks; §3.9). Furthermore, a named function or closure whose body stores a reference parameter into another parameter's memory or a global cannot be coerced to a `fn` value, because indirect calls cannot check caller-side storage lifetimes.

### 5.3 Match Patterns

A `match` expression dispatches on a scrutinee against ordered arms of the form `pattern [if guard] => expr` or `pattern [if guard] => { block }`.

| Pattern           | Syntax                            | Meaning                                                         |
| ----------------- | --------------------------------- | --------------------------------------------------------------- |
| Bare variant      | `Variant`                         | Matches a fieldless enum variant                                |
| Payload variant   | `Variant(pat)`, `Variant(p1, p2)` | Matches a payload variant (multiple patterns for tuple payload) |
| Qualified variant | `Type.Variant`, `Type.Variant(p)` | Variant pattern with explicit enum type prefix                  |
| Tuple             | `(p1, p2, ...)`                   | Matches tuple elements; `(p,)` is a 1-tuple                     |
| Struct            | `Name { f: pat, g, .. }`          | Matches struct fields; `g` shorthand binds `g`; `..` skips rest |
| Binding           | `name`, `mut name`                | Matches any value and binds it (immutable or mutable)           |
| Constant          | `CONST_NAME`                      | Compares against an in-scope constant                           |
| Literal           | `1`, `-1`, `'a'`, `true`          | Matches an exact literal value                                  |
| OR pattern        | `Pat1 \| Pat2`                    | Matches if any alternative matches                              |
| Range             | `start..end`, `start..=end`       | Half-open `[start, end)` or inclusive `[start, end]` range      |
| Wildcard          | `_`                               | Catch-all pattern; binds nothing; must appear last              |

Patterns nest arbitrarily across variants, tuples, and structs:

```zoril,no-test
match shape {
    Shape.Pt(Point { x: 0, y }) => y,
    Shape.Pair(1, b) => b + 1000,
    Shape.Pair(a, b) => a + b,
    Shape.Empty => -1,
}
```

**Pattern and exhaustiveness rules:**

- **Exhaustiveness:** Every `match` must cover all possible values of the scrutinee's type (looking inside nested tuples, structs, enums, and `bool`). Integers, characters, and slices require a wildcard or catch-all binding. Guarded arms (`if guard`) do not contribute to exhaustiveness. Unreachable arms emit a warning, as does an overly broad `_` arm on an enum unless the arm diverges. Any unreachable runtime fallthrough traps deterministically (exit code 1).
- **Guards:** An `if guard` expression may read the scrutinee and arm bindings, but cannot mutate, mutably borrow, move, or `@drop` the scrutinee (by-value bindings are formed before the guard runs).
- **Match ergonomics and ownership:** Matching a `&T` or `&mut T` binds sub-patterns by reference and keeps the referent borrowed while the binding is live (so mutating through the matched `&mut T` is rejected until the binding's last use). Matching a dereferenced borrow (`match *opt`) allows reading fields and copying `Copy` payloads, but moving a non-`Copy` payload out is a compile-time error. By-value pattern bindings move non-`Copy` values and copy `Copy` values.
- **OR patterns:** All alternatives in `Pat1 | Pat2` must bind the exact same set of variable names with identical types. `_` may discard a payload when no variables are bound (`VariantA(_) | VariantB => ...`).
- **Range patterns:** Supported for all integer types and character literals:

```zoril
fn classify_char(c: u8) -> i32 {
    return match c {
        'a'..='z' | 'A'..='Z' => 1,
        '0'..='9' => 2,
        _ => 0,
    };
}
```

- **Arm types and divergence:** Non-diverging arms must agree on a common result type. Arms ending in `return`, `break`, or `continue` have type `never` and are excluded when determining the `match` result type:

```zoril
enum MaybeInt { Some(i32), None, }

fn get_or_default(opt: MaybeInt, default: i32) -> i32 {
    let result = match opt {
        Some(x) => x,
        None => default,
    };
    return result;
}
```

## 6. Statements

### 6.1 Statement Kinds

| Kind        | Syntax                                           |
| ----------- | ------------------------------------------------ |
| Let binding | `let pattern [: Type] = expr;` (§4.2)            |
| Expression  | `expr;`                                          |
| Return      | `return [expr];`                                 |
| If          | `if cond { body } [else { body }]`               |
| If let      | `if let pattern = expr { body } [else { body }]` |
| While       | `while cond { body }`                            |
| While let   | `while let pattern = expr { body }`              |
| Loop        | `loop { body }`                                  |
| For range   | `for var in start..end { body }`                 |
| For-in      | `for pattern in expr { body }`                   |
| Break       | `break;`                                         |
| Continue    | `continue;`                                      |
| Defer       | `defer { body }` or `defer expr;`                |

- **`if let` and `while let`** accept any pattern (§5.3), follow `match` binding/borrow rules, and support `else if let` chains. `while let P = e { body }` re-evaluates `e` on every iteration (including after `continue`) and exits when `P` does not match.
- **`for var in start..end`** iterates over the half-open integer range `[start, end)`, binding a single identifier `var`.
- **`for pattern in expr`** evaluates `expr` once and drops the iterable when the loop finishes. Over a slice or fixed array, it visits each element in order by reference (`&T`). Over any other value, it repeatedly calls `.next()` until `Option.None` is returned and matches each item against the irrefutable `pattern`:

```zoril,no-test
for x in v.iter() { total = total + *x; }
for Point { x, y } in points { d = d + *y - *x; }
for (k, v) in m.iter() { ... }
```

- **`break` and `continue`** are expressions of type `never` as well as statements, allowing arms such as `_ => break`.
- **`defer`** schedules a block or expression to execute when the enclosing scope exits (§7.3).

## 7. Memory and Ownership

### 7.1 Copy vs. Move

Every type is either `Copy` or `Move`:

- **`Copy`**: Primitives (`bool`, integers, floats, `char`, `unit`), immutable references (`&T`), raw pointers (`*T`, `*mut T`), function pointers, slices (`[T]`, `[mut T]` — copying the header without duplicating elements), arrays and tuples whose elements are all `Copy`, and structs/enums whose fields are all `Copy`, that do not implement `Drop`, and that do not directly declare a raw pointer without opting back in.
- **`Move`**: `&mut T`, `Box<T>`, `fd<..>`, `async_context`, types implementing `Drop`, arrays/tuples containing a `Move` type, and structs/enums containing a `Move` field or directly declaring a raw-pointer field without `impl Copy`.

`Copy` values are duplicated bitwise on assignment, argument passing, and capture. `Move` values transfer ownership; using a binding after it has been moved is a compile-time error.

**Raw-pointer `Copy` opt-out:** A struct or enum that directly writes a raw-pointer type (`*T` or `*mut T`, including inside an array or tuple field) in its own declaration is non-`Copy` by default, so owning collections such as `Vec<T>`, `String`, `ByteVec`, and `HashMap` move rather than silently aliasing their buffers. Non-owning handles containing raw pointers may opt back into `Copy` via `impl Copy for T {}` (§8.5). Generic wrappers such as `Option<*mut T>` remain `Copy` because their declaration uses a type parameter rather than a raw pointer.

**No move out of indexed elements:** Moving a non-`Copy` value out of an array or slice element (`let v = a[i];`, passing `a[i]` by value, returning it, or binding it by value in a pattern) is a compile-time error; borrow it (`&a[i]`), mutate it in place, or clone it.

### 7.2 Borrowing

- **Aliasing:** Multiple `&T` borrows of a place may coexist; a `&mut T` borrow is exclusive. Writing through an immutable reference or read-only slice is a compile-time error.
- **Non-lexical borrow lifetime:** A borrow remains active until the **last use** of the value holding it (including inside a struct or `Option` local, or across loop back-edges), rather than until the end of the lexical block. Values implementing `Drop` remain live until their drop runs.
- **Non-`Copy` mutable references:** Binding a `&mut T` with `let` or storing it in a field moves it. Passing a `&mut T` as a call argument reborrows it for the duration of the call rather than moving it.
- **Strict reborrow rule:** Holding a view or reference derived from a value (e.g., `let r = v.get(0);` or `let s = v.as_slice();`) keeps the source borrowed until the view's last use. Invoking a `&mut self` method (such as `v.push(...)` or `v.free()`) while the view is still live is a compile-time error—for both locals and collections accessed through `&mut` parameters.

**Returned-reference ties (`#[borrows]`):** A call whose return type can hold a reference or view ties its result to its arguments, keeping them borrowed while the result is live:

1. **Default & inferred ties:** By default, the result borrows `self` if the function takes a reference `self`, otherwise all reference and pointer parameters. For a function with a body and no `#[borrows(..)]`, the compiler also adds any other parameters the body returns a view of. Inside a mutually recursive cycle, calls conservatively borrow all arguments.
2. **Checked contract (`#[borrows(p, ...)]`):** Explicitly lists the parameters the return value may borrow (`#[borrows()]` for none, e.g., arena-allocated results). A declaration may list more parameters than the body returns, never fewer: directly returning an address computed from an unlisted parameter is always a compile-time error, and under `--provenance` checking any narrowing below the body's inferred ties is a compile-time error.
3. **Trusted narrowing (`#[unsafe(borrows(p, ...))]`):** Marks a narrower contract when static analysis cannot prove independence (for example, a view read through a raw pointer into longer-lived memory). Calling the function remains safe; callers use its declared ties in place of the body's inferred ties, while direct returns of an unlisted parameter's address remain a compile-time error.

```zoril,no-test
#[borrows()]
pub fn intern(self: &mut Table, name: [u8]) -> [u8] { ... }

#[borrows(text)]
pub fn first_word(cfg: &Config, text: [u8]) -> [u8] { ... }
```

**Declared store contracts (`#[stores]`):** `#[stores(p -> q, ...)]` declares that a function body stores parameter `p`'s storage into memory reached through `q` (`#[stores(p)]` targets `self`; `#[stores(p -> static)]` targets a global). A declaration may be wider than what the body stores; omitting a store the body makes is a compile-time error in that module (generic bodies are exempt from per-instance checking). A `pub fn` that stores a reference parameter without declaring `#[stores(..)]` emits a warning. Under `--provenance`, callers are held to declared store contracts as well as inferred summaries.

Zoril has no lifetime annotation syntax (`'a`); function-level attributes (`#[borrows]`, `#[stores]`) are the sole mechanism for expressing cross-boundary borrow and storage contracts.

**Raw-pointer access and stores:** Dereferencing a raw pointer requires `unsafe` and performs direct memory loads/stores without copying the pointee:

```zoril
struct Node { value: i32, }

fn read_field(ptr: *Node) -> i32 {
    return unsafe { (*ptr).value };
}

fn write_field(ptr: *mut Node, val: i32) {
    unsafe { (*ptr).value = val; }
}
```

Assigning through a raw pointer (`*p = v`, `(*p).f = v`, `p[i] = v`) does **not** run `Drop` on the overwritten slot, because raw memory may be uninitialized. Assigning through a mutable reference (`*r = v`) drops the previous value because references always point to initialized storage.

### 7.3 Drop Order

When a scope exits (normally, via `return`, `?`, `break`, or `continue`):

1. All `defer` statements execute in reverse order of declaration (LIFO).
2. All live, unmoved local variables are dropped in reverse order of declaration (LIFO).

A `defer` body executes while its enclosing scope is already exiting and therefore cannot transfer control out of that scope with `return`, `?`, or a `break`/`continue` targeting an outer loop.

### 7.4 Allocators

`box expr` allocates on the global heap. The grammar accepts `box(allocator) expr`, but explicit allocator placement via `box` is not implemented and produces a compile-time error. Arena allocation is performed through arena-backed constructors (taking `&Arena`), which tie the allocated value's borrow lifetime to the arena so resetting or destroying the arena while the value is live is a compile-time error.

## 8. Generics and Traits

### 8.1 Monomorphization

Generics are resolved entirely at compile time via monomorphization: each distinct concrete instantiation generates its own specialized type definition and function body with no runtime dispatch overhead.

### 8.2 Type Inference

Generic calls infer type arguments from argument types, trait bounds, and the expected result type (`let o: Option<u64> = none();`, `let v: Vec<u32> = Vec.new();`). Explicit type arguments may be provided via turbofish (`identity::<i32>(42)`, `w.map::<i32>(f)`), and are required for method type parameters not determined by arguments or expected type.

### 8.3 Traits

```zoril
struct Point { x: i32, y: i32 }

trait Printable {
    fn to_string(self: &Self) -> [u8];
}

impl Printable for Point {
    fn to_string(self: &Point) -> [u8] { return "point"; }
}
```

Traits support required methods, default methods, and associated types (§4.6). Trait dispatch is static and resolved at monomorphization. Every call to a generic function verifies that concrete struct, enum, and primitive type arguments satisfy all declared trait bounds, whether or not the body invokes a method from the trait.

### 8.4 The Drop Trait

`Drop` is the built-in trait for deterministic scope-exit cleanup:

```zoril,no-test
trait Drop {
    fn drop(self: Self);
}
```

- **Invocation:** `drop` runs automatically in LIFO order when an unmoved local leaves scope, after `defer` blocks (§7.3).
- **Recognition:** The compiler recognizes the trait by the unqualified name `Drop` (either built-in or declared directly in scope); a module-qualified trait such as `m::Drop` is distinct and does not run at scope exit.
- **Constraints:** Implementing `Drop` makes a type non-`Copy`. Moving a non-`Copy` field or payload out of a `Drop` type via pattern matching is a compile-time error; matching by reference (`match &d`), discarding with `_`, or moving the `Drop` value as a whole is allowed.
- **Explicit drop and moves:** Calling `@drop(x)` or `x.drop()` consumes `x` immediately and suppresses automatic scope-exit drop. Moving `x` (passing by value or returning) likewise suppresses automatic drop in the current scope.

### 8.5 Copy, Clone, and `#[derive(Clone)]`

The marker trait `Copy` and explicit duplication trait `Clone` are defined as:

```zoril,no-test
trait Copy {}
trait Clone { fn clone(self: &Self) -> Self; }
```

- `Copy` is structural by default (§7.1): any structurally `Copy` type satisfies `T: Copy` without an explicit `impl`.
- A struct or enum that opted out of `Copy` solely because it directly declares a raw-pointer field may opt back in with `impl Copy for T {}`. Writing `impl Copy for T {}` on a type that implements `Drop` or contains a `Move` field is a compile-time error.
- `#[derive(Clone)]` is supported on structs only and generates a field-by-field `Clone` implementation requiring every field type to implement `Clone`:

```zoril,no-test
impl<T..: Clone> Clone for S<T..> {
    fn clone(self: &S<T..>) -> S<T..> { return S { f: self.f.clone(), ... }; }
}
```

## 9. FFI and System Interface

### 9.1 Extern Functions

```zoril
extern fn external_add(a: i32, b: i32) -> i32;
```

An `extern fn` declaration names an external C-ABI function with no body, resolved at link time. Calling an `extern fn` requires `unsafe`. Variadic declarations place `...` after the last named parameter; unnamed arguments follow C default argument promotions (`f32` to `f64`, integers narrower than `i32` extended). Declaring a body on a plain `extern fn` (without `"C"`) or making an `extern` function generic is a compile-time error.

**Permitted C-ABI signature types:**

- `bool`, sized integers (`i8`–`i64`, `u8`–`u64`), `isize`, `usize`, `f32`, `f64`
- Raw pointers (`*T`, `*mut T`) and C function pointers (`extern "C" fn(..)`)
- `unit` or `never` (or omitted) as a return type
- Linear `fd<..>` handles in bodyless foreign `extern fn` declarations (not in `extern "C" fn` definitions or C function pointer types; pass `i32` instead)

`char`, slices (pass `.ptr` and `.len`), references, `Box<T>`, tuples, arrays, structs by value (pass a raw pointer), enums, closures, and Zoril `fn` values are disallowed in `extern` signatures.

### 9.2 System Calls

```zoril
fn write(fd: u32, buf: [u8]) -> i64 {
    return unsafe { @syscall(1, fd, buf.ptr, buf.len) };
}
```

`@syscall(num, args...)` invokes a direct OS system call using the target platform's syscall ABI and returns `i64`. Because the kernel treats pointer arguments as unchecked integers, `@syscall` requires `unsafe`.

### 9.3 String Lowering

String literals are stored in read-only static memory with a trailing null byte (`\0`) at `ptr[len]`. In Zoril expressions they have type `[u8]` with `.len` excluding the null terminator (`"hello".len == 5`). When passed directly to an `extern` function expecting `*u8`, a string literal converts automatically to a null-terminated C pointer.

### 9.4 Typed File Descriptors

```zoril
// fd<r> = read-only, fd<w> = write-only, fd<rw> = read-write
```

Typed file descriptors (`fd<r>`, `fd<w>`, `fd<rw>`) are linear resources (§3.12):

- Read operations require `fd<r>` or `fd<rw>`.
- Write operations require `fd<w>` or `fd<rw>`.
- Closing consumes the descriptor; closing twice or leaving a descriptor unclosed at scope exit is a compile-time error.

## 10. Standard Library

Zoril ships a source-level standard library imported via `import` (§4.9, §11.1). Its core prelude (automatically in scope whenever core is loaded) provides fundamental types and traits including `Option<T>`, `Result<T, E>`, `Copy`, `Clone`, `Eq`, `Hash`, and `Error`. Additional modules provide collections (`Vec<T>`, `String`, `ByteVec`, `HashMap<K, V>`), validated UTF-8 strings (`Str`), iterators (`Iterator`), arenas (`Arena`), I/O, formatting, Unicode utilities (`unicode::char_from_u32`), and C FFI type aliases (`ffi::c_int`, `ffi::c_long`, etc.).

## 11. Modules and Compile-Time Safety

### 11.1 Modules

#### 11.1.1 Imports and Namespaces

Each `import` binds a namespace named by the imported file's stem (or by an explicit `as alias`):

```zoril,no-test
import "io.zrl";          // namespace `io`
import "mem.zrl" as m;    // namespace `m`
use io::write;
use m::Arena;

fn main() -> i32 {
    let _ = write(1, "hi\n");
    let _ = io::write(1, "and qualified\n");
    let a = Arena.new(4096 as u64).unwrap();
    return 0;
}
```

- **Qualified paths:** `ns::item` accesses any public item of module `ns` in expressions, types (`v::Vec<i32>`), patterns (`core::Option.Some(x)`), and struct literals. Associated items are reached via `ns::T.f()`, `ns::T::f()`, and `ns::T.CONST` / `ns::T::CONST`.
- **`use` declarations:** `use ns::name;` and `use ns::{a, b};` bring public items into bare scope. Importing a private, nonexistent, or locally shadowed item is a compile-time error. Re-exporting via `pub use` is not supported.
- **Name lookup order:** A bare name resolves to (1) a local/module item, (2) a `use`-imported item, (3) a prelude item, or (4) a built-in type. A module sees only its own direct imports, not transitive imports of those modules.
- **Module names:** An imported file's stem must be a valid identifier (not a keyword, not starting with a digit, and containing no `-`, `.`, or whitespace), regardless of whether `as` is used. Duplicate stems in the same file require `as` aliases to disambiguate.
- **Method lookup & checking:** Methods belong to their target type and are found across `impl` blocks for that type, subject to module visibility (`pub` required across modules except for trait impls, which are public). All concrete (non-generic) `impl` method bodies in a program are type- and borrow-checked even if uncalled; generic functions and generic `impl` methods are checked upon instantiation.
- **Constant patterns:** Referencing an out-of-scope constant in a pattern is a compile-time error.

#### 11.1.2 Encapsulation (Private by Default)

All declarations and struct fields are private to their defining module unless marked `pub`. Accessing a private function, type, method, or struct field (including in struct literals) from another module is a compile-time error.

#### 11.1.3 One Module per File

A source file imported by multiple modules is loaded and checked once; all importers share a single module identity, type definitions, and `static` variables.

### 11.2 Compile-Time Memory Safety

#### 11.2.1 Intra-procedural Arena Analysis

Within a single function, the compiler statically verifies that constant-size arena allocations do not exceed known constant arena capacities.

#### 11.2.2 Inter-procedural Propagation

Arena allocation requirements are propagated across call boundaries to check arena capacity safety inter-procedurally.

#### 11.2.3 Runtime Bounds Checking

All array and slice indexing is bounds-checked:

- **Runtime check:** Out-of-bounds reads or writes on a slice (against `.len`) or fixed array (against `N`) trap deterministically with exit code `134` (`SIGABRT`). Bounds checks are always enabled.
- **Compile-time check:** Indexing a fixed-size array with a compile-time constant out-of-range index (`data[99]`) is a compile-time error.
- **Raw pointers:** Indexing a raw pointer (`*T`, `*mut T`) is intentionally unchecked and requires `unsafe`.

#### 11.2.4 Region Outlives

Returning or storing an address that points into the current function's stack frame—or into storage owned by a local of that frame—so that it can outlive the frame is a compile-time error:

```zoril,no-test
fn dangle() -> *mut S {
    let mut s = S { a: 1 };
    return &mut s; // error: returning a pointer to local stack storage
}

fn leak(out: &mut *mut i32) {
    let mut x: i32 = 42;
    *out = &mut x; // error: local address written to memory that outlives this function
}
```

- **Transitive tracking:** Region escape is tracked through intermediate locals, structs, tuples, enums, slices (including slices over local arrays), closures, global statics, `Box<T>`, and pointer parameters. Tracking is per-local (conservative across fields).
- **Inter-procedural summaries:** Functions are summarized by whether their return value points into a parameter's own storage versus what the parameter references, and which parameters' storage they write into other parameters or globals. This rejects returning or stashing a local address through helper callees while permitting returning pointers derived from parameters or longer-lived buffers:

```zoril,no-test
fn stash(p: *mut S) -> *mut S { return p; }
fn bad() -> *mut S {
    let mut s = S { a: 1 };
    return stash(&mut s); // error: region escape
}
```

- **Raw pointers:** Creating or storing a raw pointer value that later dangles after its owner is explicitly freed is unchecked at creation; the `unsafe` dereference is responsible for storage liveness. However, a raw pointer carrying an address of the current stack frame is still forbidden from escaping the frame.

#### 11.2.5 Non-Null References and the `unsafe` Boundary

Any reference (`&T`, `&mut T`) or Zoril `fn` value produced without `unsafe` is guaranteed non-null. Direct casts from integers or raw pointers to references or `fn` values are compile-time errors (including through generic type parameters). Consequently, `Option<&T>` guarantees that `Option.Some` carries a non-null reference.

Raw pointers (`*T`, `*mut T`) remain nullable (`0 as *T` is valid); dereferencing a null raw pointer inside `unsafe` faults with `SIGSEGV`.

**The `unsafe` boundary:** Entering an `unsafe { ... }` block or `unsafe fn` body does **not** disable borrow checking, ownership/move tracking, region outlives, immutability, or runtime bounds checks. It enables only the following enumerated operations:

1. Dereferencing or indexing a raw pointer (`*p`, `&*p`, `p[i]`, field/tuple/method access through `*T`/`*mut T`), and raw-pointer `+`/`-` arithmetic.
2. Forging a reference or slice from a pointer or integer (`@ptr_cast<&T>`, `@ptr_from_int<&T>`, `@ptr_cast<[T]>`, or `@slice(p, len)` with non-zero `len`).
3. Calling an `extern` function or a C function pointer (`extern "C" fn(..)`).
4. Calling an `unsafe fn`, or converting an `unsafe fn` into a `fn` value.
5. Casting a raw pointer to a C function pointer (`p as extern "C" fn(..)`).
6. Invoking `@syscall` or allocating uninitialized stack memory with `@alloca`.
7. Reading, writing, or borrowing a non-scalar `static mut` (§4.8).
8. Casting a number to `bool` or a non-`u8` number to `char` (§2.7).

#### 11.2.6 Integer Width, Conversions, and Shifts

- **Lossy conversions must be explicit:** Implicit conversion accepts only lossless widening (§2.7). Narrowing (`u32` to `u8`, `f64` to `f32`) and integer-float conversions are compile-time errors unless written with `as`, which explicitly requests truncation/conversion:

```zoril,no-test
let big: u32 = 300 as u32;
let bad: u8 = big;       // error: implicit narrowing
let ok: u8 = big as u8;  // ok: 44
```

- **Literal range and negation:** An integer literal must fit its destination type (`let a: u8 = 300;` and `let b: u32 = -1;` are compile-time errors). Negative literals are typed together with their sign, so `let min: i32 = -2147483648;` is valid.
- **Checked shift counts:** For `<<`, `>>`, `<<=`, and `>>=`, the shift count must lie in `[0, bit_width)` of the left operand (any integer type is accepted for the count):
  - Constant counts outside `[0, bit_width)` are compile-time errors.
  - Variable counts are checked at runtime as unsigned values; an out-of-range or negative count traps with exit code `134`.
  - When wrapping/masked shift counts are desired, use `@shl_wrap(x, n)` or `@shr_wrap(x, n)`, which mask `n` to the bit width of `x` without trapping.
- **Wrapping at declared width:** Integer arithmetic (`+`, `-`, `*`, `/`, `<<`, `+%`, `-%`, `*%`) wraps modulo $2^N$, where $N$ is the declared bit width of the operand type. Sub-word types (`u8`, `i8`, `u16`, `i16`) mask intermediate results to their declared width both in temporaries and when stored:

```zoril,no-test
let a: u8 = 200 as u8;
let b: u8 = a + 100 as u8; // 44
a + 100 as u8 == 44 as u8  // true
```

#### 11.2.7 Stack Exhaustion

Unbounded recursion is neither statically diagnosed nor guarded by stack probes. Exhausting the thread stack faults deterministically on the OS guard page with `SIGSEGV` (exit code `139`).

## Appendix A. Condensed Grammar

Notation: `[x]` optional, `{x}` zero or more repetitions, `a | b` alternatives, quoted tokens are terminals.

```ebnf
Program       = { ImportDecl | UseDecl | Item } ;
ImportDecl    = "import" STRING [ "as" IDENT ] ";" ;
UseDecl       = "use" IDENT "::" ( IDENT | "{" IdentList "}" ) ";" ;

Item          = { Attr } ( [ "pub" ] ( FnDecl | StructDecl | EnumDecl
                  | TypeAlias | TraitDecl | ConstDecl | StaticDecl )
                | ImplDecl ) ;
Attr          = "#" "[" ( IDENT [ "(" ... ")" ]
                        | "unsafe" "(" IDENT "(" ... ")" ")" ) "]" ;

FnDecl        = [ "unsafe" ] [ "extern" [ "\"C\"" ] ] "fn" IDENT [ TypeParams ]
                "(" [ ParamList ] ")" [ "->" Type ] ( Block | ";" ) ;
StructDecl    = "struct" IDENT [ TypeParams ] "{" [ FieldList ] "}" ;
EnumDecl      = "enum" IDENT [ TypeParams ] "{" [ VariantList ] "}" ;
TypeAlias     = "type" IDENT "=" Type ";" ;
TraitDecl     = "trait" IDENT [ TypeParams ] "{" { AssocType | FnDecl } "}" ;
ImplDecl      = "impl" [ TypeParams ] [ Type "for" ] Type "{" { ImplItem } "}" ;
ConstDecl     = "const" IDENT ":" Type "=" Expr ";" ;
StaticDecl    = "static" [ "mut" ] IDENT ":" Type "=" Expr ";" ;

Type          = PrimType | Path [ TypeArgs ]
              | "&" [ "mut" ] Type | "*" [ "mut" ] Type
              | "[" [ "mut" ] Type "]" | "[" Type ";" Expr "]"
              | "(" [ TypeList ] ")" | "Box" "<" Type ">"
              | [ "extern" "\"C\"" ] "fn" "(" [ TypeList [ "..." ] ] ")" [ "->" Type ]
              | "fd" "<" ( "r" | "w" | "rw" ) ">" | "async_context" ;

Block         = "{" { Stmt } [ Expr ] "}" ;
Stmt          = "let" Pattern [ ":" Type ] "=" Expr ";"
              | "return" [ Expr ] ";" | "break" ";" | "continue" ";"
              | "defer" ( Block | Expr ";" )
              | "while" ( "let" Pattern "=" Expr | Expr ) Block
              | "loop" Block
              | "for" ( IDENT "in" Expr ".." Expr | Pattern "in" Expr ) Block
              | Expr [ ";" ] ;

Pattern       = OrPat ;
OrPat         = BasePat { "|" BasePat } ;
BasePat       = "_" | [ "mut" ] IDENT | Literal [ ( ".." | "..=" ) Literal ]
              | Path [ "(" [ PatList ] ")" | "{" [ FieldPatList ] "}" ]
              | "(" [ PatList ] ")" ;
```
