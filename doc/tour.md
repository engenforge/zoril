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

Local variables live in the stack frame. Zoril's verifier rejects returning pointers or references to local stack slots (`points_to_stack` tracking), so a dangling stack reference is a compile error, except through the open routes in [What Zoril Checks](SAFETY.md#6-known-gaps-in-checked-code) §6 (class E).

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

When the arena is freed, all memory within it is reclaimed at once, which removes the per-object free overhead and the fragmentation a general heap leaves behind. Every value an arena hands out through checked code is tied to it at compile time: freeing or resetting the arena while a `Vec` built with `new_in(&arena)` — or anything else read out of it — is live is a compile error, and so is moving such a collection out of the block that owns the arena handle, because the handle's implicit `Drop` unmaps the arena at that block's end ([`159_arena_tied_collection_outlives_block.zrl`](../bench/safety_matrix/probes/159_arena_tied_collection_outlives_block.zrl)), except through the open routes in [What Zoril Checks](SAFETY.md#6-known-gaps-in-checked-code) §6 (class A). Only the `unsafe` `_raw` entry points take a raw arena pointer, and those are unchecked by design ([What Zoril Checks](SAFETY.md) §4.1).

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

## Where to Go Next

- **[Getting Started Guide](getting_started.md):** Setup the toolchain and compile your first project.
- **[Surface Language Specification](spec/surface_syntax.md):** Comprehensive reference on Zoril's grammar and semantics.
- **[Safety Model](spec/safety_model.md):** The 72-row verified safety matrix and verification architecture, and [What Zoril Checks](SAFETY.md) for the tiers it adds up to.
- **[Zero-Overhead Analysis](zero_overhead.md):** Detailed performance and abstraction cost measurements.
