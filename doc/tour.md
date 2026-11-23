# A Tour of Zoril

Zoril is a low-level, statically typed systems programming language that checks memory errors at compile time where it can and traps known bounds errors at run time, with deterministic resource management and native execution. [What Zoril Checks](SAFETY.md) states what is checked and what is left to the programmer; the tour below introduces the mechanisms that do the checking.

This tour provides a rapid walkthrough of Zoril's core concepts: syntax, types, ownership, linear capabilities, and regional memory management.

---

## 1. Syntax and Basic Constructs

Zoril features a clean, expression-oriented syntax inspired by modern systems languages.

### Functions and Variables

Variables are declared with `let` and are **immutable by default**. Mutable variables require the `mut` keyword:

```zoril
fn add(a: i32, b: i32) -> i32 {
    return a + b;
}

fn main() -> i32 {
    let x: i32 = 10;
    let mut counter: i32 = 0;
    counter = counter + 1;
    let total = add(x, counter); // 11
    return 0; // main's return value is the process exit status
}
```

### Control Flow

Zoril provides `if`/`else` expressions, `while` and `for` loops, and pattern matching with `match`:

```zoril,wrap
let x: i32 = -7;

// If expressions evaluate to a value
let sign = if x > 0 { 1 } else if x < 0 { -1 } else { 0 };

// Loop forms
let mut i: usize = 0;
while i < 10 {
    i = i + 1;
}

for idx in 0..10 {
    // idx is bound from 0 up to 9
}
```

### Pattern Matching

Pattern matching is exhaustive and supports destructuring and guards. Like `if`, `match` is an expression:

```zoril
enum Message {
    Quit,
    Move(i32, i32),
    Write([u8]),
}

fn handle(msg: Message) -> i32 {
    return match msg {
        Message.Quit => 0,
        Message.Move(x, y) if x == 0 && y == 0 => 0,
        Message.Move(x, y) => x + y,
        Message.Write(bytes) => bytes.len as i32,
    };
}
```

A `match` must cover every case. Leaving a variant out is a compile error:

```zoril,compile-fail
enum Shape {
    Circle(i64),
    Square(i64),
    Empty,
}

fn area(s: Shape) -> i64 {
    return match s { // error: non-exhaustive match: missing variant 'Empty'
        Shape.Circle(r) => 3 * r * r,
        Shape.Square(w) => w * w,
    };
}

fn main() -> i32 {
    return 0;
}
```

Add the missing arm, or end with the catch-all `_`, which matches whatever the arms above it did not:

```zoril
enum Shape {
    Circle(i64),
    Square(i64),
    Empty,
}

fn area(s: Shape) -> i64 {
    return match s {
        Shape.Circle(r) => 3 * r * r,
        Shape.Square(w) => w * w,
        _ => 0,
    };
}
```

A guarded arm (`... if cond =>`) does not count toward coverage, so a `match` whose last arm for a variant has a guard still needs an arm without one or a `_`.

### Resource Cleanup with `defer`

The `defer` statement schedules an expression or block to run when the enclosing scope exits, whether it falls off the end or leaves early through `return`:

```zoril,wrap
import "io.zrl";
import "os/linux.zrl" as os_linux;
use io::{close};
use os_linux::open;

let fd = match open("log.txt", 0, 0) {
    Ok(fd) => fd,
    Err(_) => { return 1; },
};
defer close(fd);
// Use fd; every return from here on closes it first.
```

Deferred code does not run when the program traps (for example, on an out-of-bounds index): a trap ends the process immediately, and the operating system reclaims its file descriptors and memory.

---

## 2. Type System

Zoril combines primitive scalar types with powerful algebraic data types and traits:

### Primitives

- **Integers:** `u8`, `u16`, `u32`, `u64`, `usize`, `i8`, `i16`, `i32`, `i64`, `isize`
- **Floating point:** `f32`, `f64`
- **Booleans & Characters:** `bool`, `char` (Unicode code point)
- **Unit and Diverging:** `unit` (`()`), `never` (`!`)

### Collections: Arrays and Slices

- **Fixed-size Arrays:** `[T; N]` — allocated inline on the stack or in structs.
- **Slices:** `[T]` or `[mut T]` — fat pointers consisting of a pointer to elements and a `usize` length (`s.len`).

Bounds checking is enforced on all array and slice accesses. When indexing cannot be proven in-bounds at compile time, runtime checks deterministically trap (exit code 134) on out-of-bounds accesses.

### Structs and Enums

```zoril
struct Point {
    x: i64,
    y: i64,
}

impl Point {
    fn new(x: i64, y: i64) -> Point {
        return Point { x: x, y: y };
    }

    fn distance_squared(self: &Point) -> i64 {
        return self.x * self.x + self.y * self.y;
    }
}
```

### Traits and Generics

Zoril supports monomorphized generics, traits, associated types, and default methods:

```zoril
trait Summary {
    type Output;
    fn summarize(self: &Self) -> Self::Output;
}
```

---

## 3. Ownership and Move Semantics

Compile-time safety verification in checked Zoril rests primarily on affine ownership and borrow tracking, without a garbage collector:

Which values copy and which move depends only on the type:

| Type                                                                                                        | Passing or assigning it |
| ----------------------------------------------------------------------------------------------------------- | ----------------------- |
| Numbers, `bool`, `char`, references (`&T`), raw pointers, function pointers, slices (`[T]`)                 | copies                  |
| An all-`Copy` struct, enum, tuple or array with no `Drop`, except a struct or enum with a raw-pointer field | copies                  |
| `Box<T>`, `Vec`, `String`, `HashMap`, `Arena`, `fd`, `&mut T`                                               | moves                   |
| Any type that implements `Drop`, or has a field that moves                                                  | moves                   |

A move leaves the old name unusable; a copy leaves both usable. To keep using a moving value, pass a reference (`&v`), call `clone()` for a second owner, or have the function return it. The full rules are in [`surface_syntax.md`](spec/surface_syntax.md) §7.1.

1. **Affine Ownership:** Each non-`Copy` value has a single owner. Passing a value by value or assigning it moves ownership. Unlike Rust, `Copy` is structural: a struct or enum whose fields are all `Copy` and that does not implement `Drop` is `Copy` without a `derive`. `Box<T>` and types that implement `Drop` are moved.
2. **Move Invalidation:** Once a variable is moved, using it again is a compile error:
   ```zoril,compile-fail
   struct Point { x: i64, y: i64 }

   fn consume(p: Box<Point>) {}

   fn main() -> i32 {
       let p = box Point { x: 1, y: 2 };
       consume(p);
       consume(p); // error: use of moved value 'p'
       return 0;
   }
   ```
3. **Borrowing:**
   - **Shared Borrows (`&T`):** Allow reading the value. Multiple shared borrows can coexist.
   - **Exclusive Mutable Borrows (`&mut T`):** Allow mutating the value. No other references (shared or mutable) may exist simultaneously.
   - Borrows end at their last use (non-lexical lifetimes).

   A function that takes `&T` only reads the value and does not take it, so it can be called any number of times on the same value. To lend the contents of a `Box`, write `&*boxed`: a `&Box<Point>` is not accepted where `&Point` is expected. A function that takes the value itself (`Box<Point>` here) moves it, and the caller cannot use it afterwards (the example above). A type that is `Copy` is copied instead of moved, so passing it by value any number of times is also fine:

   ```zoril
   struct Point { x: i64, y: i64 }

   fn inspect(p: &Point) -> i64 {
       return p.x + p.y;
   }

   fn consume(p: Box<Point>) -> i64 {
       return p.x;
   }

   fn show(p: Point) -> i64 {
       return p.x + p.y;
   }

   fn main() -> i32 {
       let boxed = box Point { x: 1, y: 2 };
       let a = inspect(&*boxed); // borrows the Box's contents
       let b = inspect(&*boxed); // and again: nothing was taken
       let c = consume(boxed);   // moves it; `boxed` is gone after this line

       let p = Point { x: 1, y: 2 }; // all fields are Copy, so Point is Copy
       let d = show(p);
       let e = show(p);              // a copy was passed each time
       return (a + b + c + d + e - 13) as i32;
   }
   ```

---

## 4. Linear Capabilities and Resource Safety

Certain resources represent physical operating system handles or concurrency contexts that must not be duplicated, dropped silently, or leaked. Zoril tracks these as **linear capabilities**:

- **File Descriptors (`fd<r>`, `fd<w>`, `fd<rw>`):** Capability-typed handles that enforce I/O permissions at compile time (e.g., a function that reads cannot be passed an `fd<w>`). The standard library's `io` functions take typed `Fd` handles; linear capability types come from `extern` declarations.
- **Single-Consumption Rule:** A linear capability must be explicitly consumed (e.g. by `close()`). Returning from a function while holding an open linear capability triggers a compile-time leak error:
  ```
  error: linear resource 'fd' (type fd) must be explicitly closed, not dropped
  ```

---

## 5. Regional Memory Management

Rather than relying on a global tracing garbage collector, Zoril structures memory into distinct **regions**:

### Stack Storage

Local variables live in the stack frame. Zoril's verifier rejects returning pointers or references to local stack slots (origin-set provenance and `points_to_stack` tracking), so a dangling stack reference is a compile error ([What Zoril Checks](SAFETY.md) §2.3).

### Explicit Arenas

For applications requiring high-throughput dynamic allocation (such as compilers, parsers, or request handlers), Zoril provides region-allocated **Arenas**:

```zoril,wrap
import "mem.zrl";
import "vec.zrl";
use mem::Arena;
use vec::Vec;

// `Arena.new(capacity)` returns `Result<Arena, Error>`; `Drop` frees the region.
let arena = Arena.new(1024 * 1024).unwrap(); // reserve a 1 MB region

// The vector's storage is bump-allocated inside the arena. `new_in(&arena)`
// ties the vector to the arena at compile time.
let mut squares = Vec::<u64>.new_in(&arena);
let mut i: u64 = 0;
while i < 100 {
    squares.push(i * i);
    i = i + 1;
}
```

When the arena is freed, all memory within it is reclaimed at once, which removes the per-object free overhead and the fragmentation a general heap leaves behind. Every value an arena hands out through checked code is tied to it at compile time: freeing or resetting the arena while a `Vec` built with `new_in(&arena)` — or anything else read out of it — is live is a compile error, and so is moving such a collection out of the block that owns the arena handle, because the handle's implicit `Drop` unmaps the arena at that block's end ([What Zoril Checks](SAFETY.md) §2.4). Only the `unsafe` `_raw` entry points take a raw arena pointer, and those are unchecked by design ([What Zoril Checks](SAFETY.md) §4.1).

### Heap Boxing

For individual heap-allocated values that must outlive their declaring function, `Box<T>` provides owned heap storage:

```zoril
struct Point {
    x: i64,
    y: i64,
}

// The Point outlives this call: the caller owns the box.
fn origin() -> Box<Point> {
    return box Point { x: 0, y: 0 };
}
```

In this release a `Box` is not freed when its owner goes out of scope, and the boxed value's `Drop` does not run: the allocation leaks, as an unfreed collection's buffer does (freeing at scope end is planned; see [Known Issues](../KNOWN_ISSUES.md)). For many short-lived values, an arena is the better tool.

---

## 6. The Checked / Unsafe Boundary

Zoril separates verified checked code from low-level systems programming:

- **Checked Zoril:** The default dialect. Rejects use-after-move, use-after-free, stack escape and double-drop at compile time, and traps out-of-bounds indexing at run time (exit 134). What that does and does not cover is listed tier by tier in [What Zoril Checks](SAFETY.md).
- **`unsafe { ... }` Blocks:** Scope a fixed set of operations, enumerated in [`doc/spec/unsafe_policy.md`](spec/unsafe_policy.md) §1: raw-pointer dereferencing (explicit, or implicit in `p.field`, `p.0`, a method call, or a conversion to a reference), raw-pointer indexing, making a **reference or a slice** out of an integer or a pointer (`@ptr_cast<&T>`, `@ptr_from_int<&T>`, `@ptr_cast<[T]>`, and `@slice`, whose length nothing checks), invoking foreign C functions, system calls (`@syscall`), and uninitialized stack slots (`@alloca`). Calling an `unsafe fn` needs one as well, because its contract is the caller's. _Creating_ a raw pointer (`n as *T`, `@ptr_from_int<*T>`, `@ptr_cast<*T>`, `@int_cast<U>`) is not gated: every use of the pointer is, so the marker belongs on the use.

Inside an `unsafe` block, all other verification checks (type rules, SSA well-formedness, must-use checks) remain fully active.

---

## 7. Reading Files

A small file is read whole into an arena with `file::read_file(path, &arena)`, which returns the file's bytes as a `[u8]` tied to that arena. A large file is read in pieces: open it with `File.options()`, then call `read` (the `io::Read` trait) with a buffer until it returns 0. Memory use is then the buffer, whatever the file's size:

```zoril
import "core.zrl";
import "io.zrl";
import "file.zrl";
use io::{Error, File, Read};
use file::OpenOptions;

// Reads the file at PATH 64 KiB at a time: memory use is the buffer, whatever the file's size.
fn sum_bytes(path: [u8]) -> Result<u64, Error> {
    let mut f = match File.options().read(true).open(path) {
        Result.Ok(f) => f,
        Result.Err(e) => { return Result.Err(e); },
    };
    let mut buf: [u8; 65536] = [0 as u8; 65536];
    let mut sum: u64 = 0;
    while true {
        let n = match f.read(&mut buf) {
            Result.Ok(n) => n,
            Result.Err(e) => { return Result.Err(e); },
        };
        if n == 0 as usize { break; }
        let mut i = 0 as usize;
        while i < n {
            sum = sum + (buf[i] as u64);
            i = i + 1 as usize;
        }
    }
    return Result.Ok(sum);
}
```

`bufio::BufReader` wraps any `Read` with a buffer and reads lines (`read_line`, `read_until`). Version 0.1 has no portable way to read at an offset: on Unix, `os_unix::lseek(f.fd(), offset, 0)` (`import "os/unix.zrl" as os_unix;`) moves a file's position, as code you keep per platform. A portable seek and read-only memory mapping of a file are planned.

---

## 12. Idioms, Subtleties, and Contrasts with C and Rust

Zoril borrows syntax from Rust (`fn`, `let`, `mut`, `match`, `struct`, `enum`, `impl`, `trait`) and low-level semantics from C and QBE (`@syscall`, simple value layout), yet is neither a subset of Rust nor a "safe C". This section catalogs the main places where Zoril differs from C or Rust expectations and the idioms idiomatic code uses instead.

### A. Operator Precedence, Comparisons, and Assignments

Zoril uses **Rust-style operator precedence**: bitwise operators (`&`, `^`, `|`) bind tighter than equality and relational comparisons, comparisons are **non-associative** (chaining `a < b < c` is a compile error; write `a < b && b < c`), and assignments are statements that yield `()` rather than expression values.

```zoril
const MASK: u32 = 4;

fn is_set(status: u32) -> bool {
    return status & MASK != 0; // Parsed as (status & MASK) != 0, unlike C's status & (MASK != 0)
}
```

```zoril,compile-fail
fn in_order(a: i32, b: i32, c: i32) -> bool {
    return a < b < c; // COMPILE ERROR: comparison operators cannot be chained
}
```

```zoril,compile-fail
fn get_val() -> i32 { return 1; }

fn main() -> i32 {
    let mut x = 0;
    if (x = get_val()) { return 1; } // COMPILE ERROR: assignment yields no value
    return 0;
}
```

### B. References, Auto-Dereferencing, and Immutability

Field access and method calls on references (`&T` / `&mut T`) automatically dereference, so write `node.val` rather than `(*node).val` (writing `(*r).field` makes an explicit dereference look like a raw-pointer access to readers and audit tools). Unlike Rust, **Zoril has no interior mutability through `&T`** (no `UnsafeCell`): `&T` is strictly read-only, and mutating behind a pointer requires `&mut T` or `*mut T`. Declaring `let mut r: &T` lets `r` be rebound to another target, not mutated through `*r`:

```zoril
import "core.zrl";

struct Node { val: i64, next: Option<&Node> }

fn read_val(node: &Node) -> i64 {
    return node.val; // auto-deref
}
```

```zoril,compile-fail
fn main() -> i32 {
    let x: i64 = 1;
    let y: i64 = 2;
    let mut r: &i64 = &x;
    r = &y;  // OK: rebinds 'r' to point to 'y'
    *r = 10; // COMPILE ERROR: cannot assign through a shared reference &i64
    return 0;
}
```

### C. Fixed-Size Arrays vs. Slices

Fixed-size arrays `[T; N]` are value types: passing `[u8; 4096]` by value copies 4,096 bytes on the stack. Pass `&[T; N]` or a slice `[T]` / `[mut T]` (a 16-byte `{ptr, len}` fat pointer) instead; use `subslice(s, start, len)` and `subslice_from(s, start)` in `core0.zrl` for bounds-checked sub-slicing. Both reads and writes on arrays and slices are bounds-checked in every build.

```zoril
fn process(data: &[u8; 4096]) {} // 8-byte reference
fn process_slice(data: [u8]) {}  // 16-byte slice (ptr + len)
```

### D. Strict Reborrowing Across `&mut self` Calls

A reference taken into a collection (`Vec`, `String`, `HashMap`) keeps that collection borrowed while the reference is live. Calling a `&mut self` method on the same collection — even through a `&mut` parameter — is rejected at compile time:

```zoril,compile-fail
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

Six idioms work cleanly with strict reborrowing:

1. **End the borrow before mutation:** scope the view so its last use precedes the `&mut self` call.
2. **Copy the value out:** copy a scalar or `Copy` field before calling the mutating method.
3. **Hoist self-derived arguments:** compute arguments that borrow `self` beforehand (pure scalar reads like `v.push(v.len())` are accepted directly).
4. **Keep an index and re-read:** hold an integer index or key across the mutation and re-index afterwards.
5. **Re-look up interned data:** keep an interned ID across operations that may reallocate or reset an arena, then re-fetch the slice.
6. **Split the struct:** put independently mutated fields in separate structs or fields rather than mutating the whole aggregate.

### E. Narrowing Casts, Booleans, Sub-Word Wrapping, and Checked Shifts

Zoril widens integers implicitly (`u8` to `u32`), but **rejects implicit narrowing** — any truncating conversion requires `as`. Conditions must have type `bool` (no truthy/falsy integers). Sub-word arithmetic (`u8`, `i8`, `u16`, `i16`) masks intermediate results modulo $2^N$, and shift counts must lie in `[0, width)` (out-of-range constant counts fail at compile time; variable counts trap with exit 134 unless `@shl_wrap` / `@shr_wrap` is used).

```zoril,compile-fail
fn main() -> i32 {
    let a: u32 = 1000;
    let c: u8 = a as u8; // OK: explicit truncation (232)
    let b: u8 = a;       // COMPILE ERROR: cannot implicitly narrow u32 to u8
    return 0;
}
```

```zoril,compile-fail
fn main() -> i32 {
    let count = 5;
    if count { return 1; } // COMPILE ERROR: condition must be bool
    return 0;
}
```

```zoril,wrap
let a: u8 = 200 as u8;
let b: u8 = 100 as u8;
let c: u8 = a + b;         // 44 (300 mod 256)
let x: u32 = 1;
let n: u32 = 32;
let y = @shl_wrap(x, n);   // 1 << (32 & 31) = 1
```

### F. Structural `Copy` vs. Move-Only Owning Collections

A struct or enum is `Copy` automatically when all its fields are `Copy` and it does not implement `Drop`. `Box<T>`, `Drop` types (`io::File`), and buffer-owning collections (`Vec<T>`, `String`, `ByteVec`, `HashMap`) **move** on assignment or pass-by-value; call `.clone()` for an independent copy, or pass `&T` / `&mut T` to borrow:

```zoril,wrap
import "vec.zrl";
import "clone.zrl";
use vec::Vec;

let mut v1 = Vec::<u8>.new();
v1.push(1);
let v2 = v1.clone(); // allocates an independent buffer
v1.push(2);          // v1.len() is 2, v2.len() is 1
```

### G. Idiomatic Structure and Author Checklist

Prefer guard clauses with early returns, `Option<T>` / `Result<T, E>` with `?` over sentinel values, named constants over magic numbers, and exhaustive `match` over tag ladders:

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

**Checklist for Zoril code authors:**

1. **Bitwise precedence:** `&`, `^`, and `|` bind tighter than `==` and `<`.
2. **Large arrays:** pass `&[T; N]` or `[T]` instead of copying `[T; N]` by value.
3. **Immutability:** mutate through `&mut T` or `*mut T`; `&T` has no interior mutability.
4. **Narrowing casts:** write explicit `as` when discarding bits.
5. **Collections:** pass `&Vec<T>` / `&mut Vec<T>` to share or mutate; `.clone()` when a second owner is needed.
6. **Application `unsafe`:** rely on stdlib types (`Vec`, `String`, `Args`, `File`) so application code stays free of `unsafe`.

---

## Where to Go Next

- **[Getting Started Guide](getting_started.md):** Setup the toolchain and compile your first project.
- **[Surface Language Specification](spec/surface_syntax.md):** Comprehensive reference on Zoril's grammar and semantics.
- **[Safety Model](spec/safety_model.md):** The 72-row verified safety matrix and verification architecture, and [What Zoril Checks](SAFETY.md) for the tiers it adds up to.
- **[Zero-Overhead Analysis](zero_overhead.md):** Detailed performance and abstraction cost measurements.
