# Zoril Language Walkthrough

Zoril is a low-level language for high-integrity systems that rejects many memory errors at compile time and traps known bounds errors at run time; [What Zoril Checks](../SAFETY.md) lists what is checked and what is left to the programmer. It features a modern surface syntax that lowers to a rigorous, pointer-safe Intermediate Representation (IL) with explicit region and ownership tracking.

## 1. Basics

### Memory Management Philosophy

Zoril combines two powerful concepts: **Automatic Safety** and **Explicit Control**.

1. **Ownership and Regions (Automatic Safety)**: ownership is the mechanism the compiler checks. Every `Box<T>` has exactly one owner (in this release a `Box` is not freed when its owner goes out of scope; see [Known Issues](../../KNOWN_ISSUES.md)). Use-after-move, double-free and the use of a value after it is dropped are rejected at compile time, without a garbage collector. What this does not cover - `unsafe`, the failures that fault rather than diagnose, and the limits of the analyses - is the other two tiers of [What Zoril Checks](../SAFETY.md).

2. **Allocators (Explicit Control)**: While the compiler handles _when_ to free memory, it allows the programmer to control _how_ that memory is allocated. `box expr` uses the global heap. An arena is an explicit region: `Arena.new(capacity)` returns an owning handle (`Result<Arena, Error>`), and the constructors that take `&Arena` (`Vec::new_in(&arena)`, `String::new_in(&arena)`, `HashMap.new(&arena)`, `read_file(path, &arena)`) allocate from it and tie the value to that handle, so resetting or dropping the arena while the value is live is a compile error.
   - **Performance**: Allocating many objects in an Arena is significantly faster than the system heap.
   - **Predictability**: You can ensure no "stop-the-world" pauses or unpredictable latency.

The raw primitives (`arena_init`, `heap_alloc`, `zoril_allocator_alloc`, `arena_free`, `arena_reset`, or anything reached through `arena_raw`) in `mem_raw.zrl` are `unsafe fn`: there the compiler no longer sees the arena, and a use after a reset or free is the programmer's responsibility. The `box(allocator) expr` form is rejected rather than silently mis-compiled - it never reached the arena (see [Allocators](../spec/surface_syntax.md#74-allocators)).

### Functions and Variables

Functions are declared with `fn`. Variables are immutable by default, but can be made mutable with `mut`.

```zoril
fn add(a: i32, b: i32) -> i32 {
    return a + b;
}

fn main() -> i32 {
    let x = 10;
    let mut y = 20;
    y = add(x, y);
    return 0;
}
```

### Wrapping Arithmetic

Integer arithmetic operators (`+`, `-`, `*`) wrap on overflow, identically in every build. The explicit wrapping operators (`+%`, `-%`, `*%`) state that intent at the call site. Narrow integer types (`u8`, `u16`, `i8`, `i16`) wrap at their declared width.

### Expression-Oriented

Most Zoril constructs are expressions. The last expression in a block (without a semicolon) is the block's value. A function body's final expression is also its return value, but Zoril code, including the standard library, conventionally uses an explicit `return`.

```zoril,wrap
let x = 5;
let result = if x > 0 {
    1
} else {
    0
};
```

## 2. Memory Safety

### Ownership

Zoril uses ownership for heap-allocated values (`box T`). When an owned value is moved, the original becomes invalid.

```zoril
fn consume(b: Box<i32>) {
    // b is dropped here
}

fn main() -> i32 {
    let b = box 10;
    consume(b);
    // consume(b); // Error: use of moved value 'b'
    return 0;
}
```

### The Drop Trait

For custom resource cleanup, Zoril provides the `Drop` trait. Types implementing `Drop` have their `drop` method called automatically when they go out of scope.

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

The standard library's `io::File` is such a type: it closes its descriptor when dropped.

### References and Regions

A reference (`&T` shared, `&mut T` exclusive) borrows a value without taking ownership. The verifier tracks the region each reference points into and rejects any reference that would outlive its data, such as one into a returning function's stack frame (except through the open routes in [What Zoril Checks](../SAFETY.md#6-known-gaps-in-checked-code) §6). Raw pointers (`*T`, `*mut T`) are the unchecked escape hatch; dereferencing one requires `unsafe`.

```zoril
struct Point { x: i32, y: i32 }

fn get_x(p: &Point) -> i32 {
    return p.x;
}
```

### A Reference into `self` Across a `&mut self` Call (Strict Reborrowing)

When taking a reference into a data structure (such as an element of a `Vec` or a slice of a `String`), that reference keeps the referent borrowed for as long as the reference remains live. Calling a mutating method on that same structure while the reference is live is rejected at compile time (probe [`309_mut_vec_param_view_across_free.zrl`](../../bench/safety_matrix/probes/309_mut_vec_param_view_across_free.zrl)):

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

`v.free()` releases the buffer `r` points into, so reading `*r` afterwards would be a use-after-free. On a local `Vec` this was always rejected; the strict reborrow rule extends it to a collection reached through a `&mut` parameter or reference, where it used to compile.

**Idioms for working with `&mut self` and views:**

1. **End the borrow before mutation:** Scope the view so its borrow ends before the mutating call.
2. **Copy the value out:** Copy a scalar or `Copy` field before calling the mutating method.
3. **Hoist self-derived arguments:** If an argument to a mutating method is derived from `self`, compute it beforehand if it borrows `self`. Scalar reads like `v.push(v.len())` are accepted directly.
4. **Keep an index and re-read:** Retain an integer index or key across the mutation, then re-index afterwards.
5. **Re-look up interned data:** Hold an interned key across operations that might reset the underlying arena, and re-fetch the slice when needed.
6. **Split the struct:** Structure data so methods operate on independent fields rather than the whole aggregate.

## 3. Custom Types

### Structs

```zoril
struct Rect {
    width: i32,
    height: i32,
}

impl Rect {
    fn area(self: &Rect) -> i32 {
        return self.width * self.height;
    }
}
```

### Enums (Sum Types)

Enums are tagged unions: each variant may carry a payload.

```zoril
enum Shape {
    Circle(i64),
    Rect(i64, i64),
}
```

The standard library's `Option<T>` (`enum Option<T> { None, Some(T) }`) and `Result<T, E>` (`enum Result<T, E> { Ok(T), Err(E) }`) in `core.zrl` are enums too, and are how functions report a missing value or an error:

```zoril
import "core.zrl";

fn divide(a: i32, b: i32) -> Option<i32> {
    if b == 0 {
        return Option.None;
    }
    return Option.Some(a / b);
}
```

### Pattern Matching

```zoril
import "core.zrl";

fn handle_option(opt: Option<i32>) -> i32 {
    return match opt {
        Some(v) => v,
        None => 0,
    };
}
```

## 4. Modern Features

### Defer

The `defer` statement schedules code to run at the end of the current scope.

```zoril
import "io.zrl";
import "os/linux.zrl" as os_linux;
use io::{close};
use os_linux::open;

fn process() -> i32 {
    let fd = match open("data.txt", 0, 0) {
        Ok(fd) => fd,
        Err(_) => { return 1; },
    };
    defer close(fd);

    // ... use fd ...
    return 0; // close runs here, on every return path
}
```

### For Loops and Ranges

```zoril
fn sum_to(n: i32) -> i32 {
    let mut s = 0;
    for i in 0..n {
        s = s + i;
    }
    return s;
}
```

## 5. Low-level Integration

### System Calls

`@syscall` makes a direct Linux system call, without libc. The kernel treats some arguments as addresses, so a call can write or unmap any memory, and it needs `unsafe`. The standard library's `io` module wraps it in safe functions over slices and descriptors.

```zoril
fn exit(code: i32) {
    unsafe { @syscall(60, code); } // 60 is SYS_exit on x86_64 Linux
}
```
