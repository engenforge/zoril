# Zoril Language Gotchas and Subtleties

**A guide for systems programmers and AI coding agents.** Normative references: [`doc/spec/surface_syntax.md`](../spec/surface_syntax.md), [`doc/spec/safety_model.md`](../spec/safety_model.md), [`doc/spec/unsafe_policy.md`](../spec/unsafe_policy.md).

---

## 1. Overview

Zoril's syntax borrows visual familiarities from Rust (`fn`, `let`, `mut`, `match`, `struct`, `enum`, `impl`, `trait`) and low-level semantics from C and QBE (`@syscall`, simple types, manual memory layout). However, Zoril is neither a subset of Rust nor a "safe C". Programmers and AI models assuming Rust-identical or C-identical semantics will frequently run into subtle compiler errors or unexpected behaviors.

This document catalogs the primary areas where Zoril differs from common developer expectations.

---

## 2. Operator Precedence: Rust Precedence, Not C

One of the most dangerous bugs in C is the precedence inversion between bitwise operators and equality comparisons. Zoril adopts **Rust-style operator precedence**:

|   Precedence    | Operators                        |    Associativity    | Notes                                        |
| :-------------: | :------------------------------- | :-----------------: | :------------------------------------------- |
| **Highest (9)** | `*`, `/`, `%`, `*%`              |        Left         | Multiplicative                               |
|      **8**      | `+`, `-`, `+%`, `-%`             |        Left         | Additive                                     |
|      **7**      | `<<`, `>>`                       |        Left         | Bit shifts                                   |
|      **6**      | `&`                              |        Left         | Bitwise AND (binds tighter than comparisons) |
|      **5**      | `^`                              |        Left         | Bitwise XOR                                  |
|      **4**      | `\|`                             |        Left         | Bitwise OR                                   |
|      **3**      | `==`, `!=`, `<`, `<=`, `>`, `>=` | **Non-associative** | Chained comparisons are compile errors       |
|      **2**      | `&&`                             |        Left         | Short-circuit logical AND                    |
|      **1**      | `\|\|`                           |        Left         | Short-circuit logical OR                     |
| **Lowest (0)**  | `=`, `+=`, `-=`, etc.            |        None         | **Statements only** (yield no value)         |

### Key Precedence Gotchas:

1. **Bitwise AND vs Equality:**
   ```zoril
   const MASK: u32 = 4;

   fn is_set(status: u32) -> bool {
       return status & MASK != 0;
   }
   ```
   - **In Zoril:** Evaluated as `(status & MASK) != 0`. Bitwise operators bind tighter than equality.
   - **In C:** Evaluated as `status & (MASK != 0)`, which tests if `status & 1`.
2. **Comparisons are Non-Associative:**
   ```zoril,compile-fail
   fn in_order(a: i32, b: i32, c: i32) -> bool {
       return a < b < c; // COMPILE ERROR: comparison operators cannot be chained
   }
   ```
   - In Zoril, chained comparisons are rejected at parse time. You must write `a < b && b < c`.
3. **Assignments are Statements:**
   ```zoril,compile-fail
   fn get_val() -> i32 { return 1; }

   fn main() -> i32 {
       let mut x = 0;
       if (x = get_val()) { return 1; } // COMPILE ERROR: did you mean `==`?
       return 0;
   }
   ```
   - Assignments produce no value (`()`). They cannot appear in expressions (`let y = (x = 5);` is also an error), so an accidental assignment in a condition is a compile error.

---

## 3. References, Dereferencing, and Mutability

### A. Automatic Dereferencing on References (`&T` / `&mut T`)

In Zoril, field access and method calls on references automatically dereference:

```zoril
import "core.zrl";

struct Node { val: i64, next: Option<&Node> }

fn read_val(node: &Node) -> i64 {
    return node.val; // Correct: auto-deref
}
```

> [!TIP]
> **Avoid explicit `(*node).val`:** Writing `(*node).val` on a reference `&T` is unnecessary. Furthermore, in pattern match variable bindings where variable types are inferred, explicit dereference syntax can confuse syntactic safety audit scanners. Always prefer direct `node.field`.

### B. Shared References are Strictly Immutable (No `UnsafeCell`)

In Rust, `UnsafeCell<T>` provides "interior mutability" through a shared reference (`&T`). **Zoril has no interior mutability through `&T`.**

- In ZIR (Zoril Intermediate Representation), `&T` erases to `Ptr` (read-only), while `&mut T` erases to `PtrMut` (writable).
- Writing through a shared reference (`(*r).x = 5;` or `r.x = 5;` where `r: &T`) is rejected by the verifier (`check_zir.zrl`).
- If you need to mutate memory behind a pointer, the receiver must be `&mut T` or `*mut T`.

### C. Rebinding vs Mutation

```zoril,compile-fail
fn main() -> i32 {
    let x: i64 = 1;
    let y: i64 = 2;
    let mut r: &i64 = &x;
    r = &y;  // OK: rebinds the reference variable 'r' to point to 'y'
    *r = 10; // COMPILE ERROR: cannot assign through a shared reference &i64
    return 0;
}
```

Declaring `let mut r: &T` makes the _variable_ `r` mutable (it can point to another address), but does _not_ make the referent writable.

---

## 4. Arrays vs Slices: Value Copying vs Fat Pointers

One of the easiest ways to incur unexpected performance overhead is conflating fixed-size arrays with slices:

### A. Fixed-Size Arrays `[T; N]` are Value Types

Fixed-size arrays have value semantics. Passing an array by value **copies the entire array**:

```zoril
fn process(data: [u8; 4096]) {} // COPIES 4,096 BYTES ON THE STACK!
```

To avoid copying, pass a reference or slice:

```zoril
fn process(data: &[u8; 4096]) {} // Passes 8-byte pointer
fn process_slice(data: [u8]) {}  // Passes 16-byte slice descriptor (ptr + len)
```

### B. Slices `[T]` are Dynamically Sized Fat Pointers

A slice is an 8-byte pointer paired with an 8-byte length (`len`).

- `&arr` gives a `[T]` slice of a whole array, and `&mut arr` a `[mut T]`.
- There is no range syntax for re-slicing yet (Rust's `&s[a..b]`). For byte slices, `subslice(s, start, len)` and `subslice_from(s, start)` in `core0.zrl` are the bounds-checked helpers.
- Slices do not own memory; they borrow from the underlying array or buffer.

### C. Mandatory Bounds Checking on Both Reads and Writes

Zoril has no build mode without bounds checks (C leaves indexing unchecked, and Zig's `ReleaseFast` mode omits bounds checks for speed by design):

```zoril,wrap
let mut arr: [i64; 4] = [0 as i64; 4];
let idx: usize = 10;
arr[idx] = 42; // Traps at runtime with exit code 134 (SIGABRT)
```

Bounds checks are unconditional on **both read and write paths** across arrays and slices.

---

## 5. Integer Arithmetic and Type Conversions

### A. Zero Implicit Narrowing Conversions

Zoril never silently truncates integers. Any conversion that could discard bits must be explicit via `as`:

```zoril,compile-fail
fn main() -> i32 {
    let a: u32 = 1000;
    let c: u8 = a as u8;   // OK: explicit truncation (c = 232)
    let b: u8 = a;         // COMPILE ERROR: cannot implicitly narrow 32-bit value to 8 bits
    return 0;
}
```

Widening conversions (`u8` to `u32`) are implicit.

### B. No Truthy/Falsy Integers

Zoril does not allow mixing integers and booleans:

```zoril,compile-fail
fn main() -> i32 {
    let count = 5;
    if count != 0 { return 1; } // OK
    if count { return 1; }      // COMPILE ERROR: condition must be bool
    return 0;
}
```

### C. Sub-Word Arithmetic Wrapping

When performing arithmetic on narrow integers (`u8`, `i8`, `u16`, `i16`), intermediate results are masked back to their declared width:

```zoril,wrap
let a: u8 = 200 as u8;
let b: u8 = 100 as u8;
let c: u8 = a + b; // 44 (200 + 100 = 300; 300 % 256 = 44)
```

Both stored variables and temporary expressions evaluate modulo $2^N$.

### D. Shift Counts Are Checked

In C, shifting by the operand's width or more is undefined behavior, and x86 hardware masks the count to the register width. In Zoril a shift count must be in `[0, width)` of the shifted type: an out-of-range constant count is a compile error, and a variable count is checked at runtime and traps (exit code 134). When masking is what an algorithm wants, say so with `@shl_wrap` / `@shr_wrap`, which mask the count to the operand's width:

```zoril,wrap
let x: u32 = 1;
let n: u32 = 32;
let y = @shl_wrap(x, n); // 1 << (32 & 31) = 1 << 0 = 1
let z = x << n;          // Traps at runtime: count 32 is out of range for u32
```

---

## 6. Pattern Matching and Algebraic Data Types

### A. Match Exhaustiveness is Mandatory

When matching on enums, every variant must be handled:

```zoril,compile-fail
enum Status { Pending, Active, Done }

fn rank(s: Status) -> i32 {
    return match s { // COMPILE ERROR: non-exhaustive match: missing variant 'Done'
        Status.Pending => 1,
        Status.Active => 2,
    };
}
```

If you only care about a subset of variants, provide an explicit wildcard `_ =>`:

```zoril
enum Status { Pending, Active, Done }

fn is_pending(s: Status) -> i32 {
    return match s {
        Status.Pending => 1,
        _ => 0,
    };
}
```

### B. Enums with Variant Payloads

Variants can carry values (tagged unions). When matching on payload variants, bind variables inside parentheses:

```zoril
import "io.zrl";
import "fmt.zrl";
use io::{print, stdout};
use fmt::write_i64;

enum JsonValue {
    Null,
    Bool(bool),
    Int(i64),
    Str([u8]),
}

fn print_value(val: JsonValue) {
    match val {
        JsonValue.Int(n) => { let mut out = stdout(); let _ = write_i64(&mut out, n); },
        JsonValue.Str(s) => print(s),
        _ => (),
    }
}
```

### C. Tuples

Tuples use 0-indexed member access, or can be destructured in a `let`:

```zoril,wrap
let pair: (i64, bool) = (42, true);
let num = pair.0;
let flag = pair.1;
let (n, f) = pair;
```

---

## 7. Memory Safety & Region Boundaries

### A. `Copy` Is Structural, and `Vec` Is `Copy`

A struct or enum is `Copy` when all its fields are `Copy` and it does not implement `Drop`; no `derive` is needed. `Box<T>` and types that implement `Drop` (such as `io::File`) move on assignment or parameter passing:

```zoril,compile-fail
fn main() -> i32 {
    let b1 = box 10;
    let b2 = b1;  // b1 moved to b2
    let b3 = b1;  // COMPILE ERROR: use of moved value 'b1'
    return 0;
}
```

`Vec<T>`, `String`, `ByteVec` and `HashMap` own a buffer, so they are **not** `Copy`: assigning one, passing it by value or capturing it in a closure moves it, and the old binding is unusable. A duplicate has to be asked for, and `.clone()` allocates a new buffer and copies the elements:

```zoril,wrap
import "vec.zrl";
import "clone.zrl";
use vec::Vec;

let mut v1 = Vec::<u8>.new();
v1.push(1);
let v2 = v1.clone(); // a new buffer with the same elements
v1.push(2);          // independent: v1.len() is 2, v2.len() is 1
```

Pass a `&Vec<T>` or `&mut Vec<T>` when a callee should see or change the caller's vector.

### B. Region Escape Is Checked Across Calls

Zoril rejects returning a pointer or reference into the current function's stack frame, both directly and when it comes back through a call (except through the open routes in [What Zoril Checks](../SAFETY.md#6-known-gaps-in-checked-code) §6, class F):

```zoril,compile-fail
fn identity(p: &mut i64) -> &mut i64 { return p; }

fn escape() -> &mut i64 { // COMPILE ERROR: region escape: returning a pointer to local stack storage
    let mut x: i64 = 42;
    return identity(&mut x);
}
```

The error is reported at the function, not at the `return`.

Each function's summary records which parameters its result may point into, so the check also works across modules. See the region escape rows of the [safety model](../spec/safety_model.md) for exactly what is covered.

---

## 8. Summary Checklist for Code Authors

1. **Did you assume C bitwise precedence?** Remember `&` binds tighter than `==`.
2. **Did you pass a big array by value?** Use `&[T; N]` or `[T]` instead of `[T; N]`.
3. **Did you try to mutate behind a `&T`?** Zoril requires `&mut T` or `*mut T`; there is no `UnsafeCell`.
4. **Did you forget `as` on a narrowing cast?** Explicit `as u8` / `as u32` is mandatory.
5. **Did you copy a `Vec` and expect the copies to stay in sync?** Pass `&Vec<T>` / `&mut Vec<T>` instead.
6. **Did you write `unsafe` in application code?** Rely on stdlib abstractions (`Vec`, `String`, `Args`, `File`) so that application code needs no `unsafe`.
