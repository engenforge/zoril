# Getting Started with Zoril

Welcome to Zoril! This guide walks you through writing and compiling your first Zoril programs, using modules, and calling external C libraries.

To install a prebuilt release on x86-64 Linux, see [Installing a Prebuilt Release](../README.md#installing-a-prebuilt-release-linux-x86-64); to build the toolchain from source, see [Building & Installation](../README.md#building). If you are looking to contribute to the Zoril compiler codebase or run developer verification suites, see the [Developer Guide](developer_guide.md).

In the commands below, `PREFIX` is the installation root, the directory that holds `bin/`, `lib/zoril/` and `share/zoril/`: `/usr/local` after `sudo make install`, `$HOME/.local` after `make install PREFIX=$HOME/.local`, or the directory a prebuilt release was extracted into. QBE and binutils package names are in [Dependencies](dependencies.md).

---

## "Hello World" Walkthrough

Create a file named `hello.zrl`:

```zoril,file=hello.zrl
import "io.zrl";
use io::println;

fn main() -> i32 {
    println("Hello, World!");
    return 0;
}
```

---

## Compiling The Easy Way

The standard way to build Zoril applications is with **`zbuild`**, the incremental build driver. `zbuild` automatically discovers imported modules, tracks dependencies, caches intermediate build outputs, and links the final executable.

Run `zbuild` on your source file:

```sh
zbuild hello.zrl
```

When run for the first time, `zbuild` compiles all necessary dependencies and prints:

```text
compiled: 4 modules
```

This generates the default executable `a.out`. The 4 modules compiled are:

1. **`core0.zrl`:** The core language runtime module containing essential primitives, basic Option and Result types, and panic handling.
2. **`core.zrl`:** Core traits (`Eq`, `Clone`, `Error`, `ErrorMessage`) and methods on `Option`/`Result` (imported by `io.zrl`).
3. **`io.zrl`:** The standard library I/O module containing system call wrappers (`read`, `write`, `open`, `close`, etc.) and print helpers (`println`, `print`).
4. **`hello.zrl`:** Your application source file containing `main()`.

Run your executable:

```sh
./a.out
```

Output:

```text
Hello, World!
```

### Specifying the Output Name

To specify a custom name for the generated binary, pass the `-o` flag:

```sh
zbuild -o hello hello.zrl
```

Output:

```text
compiled: 0 modules
```

Notice that this time `zbuild` reports `compiled: 0 modules`. `zbuild` caches compiled module artifacts in `.zoril-cache` and uses interface hashing. Because neither `hello.zrl` nor any of its imported dependencies changed, no modules needed recompilation; `zbuild` immediately linked the cached objects to create `hello`.

---

## Compiling the Manual Way

Behind the scenes, `zbuild` coordinates each stage of Zoril's multi-stage compilation pipeline. You can also run these individual stages manually:

```text
zoril -I <stdlib>  --emit-zil  ->  zilc  ->  qbe  ->  as  ->  ld  (with runtime.o)
    (Zoril)            ZIL       (ZIL→SSA)  (host)  (host)  (host)
```

1. **Compile Zoril source to ZIL (Intermediate Language):**
   ```sh
   zoril -I $PREFIX/share/zoril/stdlib --emit-zil -o hello.zil hello.zrl
   ```
2. **Lower ZIL to QBE SSA representation:**
   ```sh
   zilc hello.zil hello.ssa
   ```
3. **Compile SSA to assembly with QBE:**
   ```sh
   qbe -o hello.s hello.ssa
   ```
4. **Assemble machine code:**
   ```sh
   as -o hello.o hello.s
   ```
5. **Link machine code with the Zoril assembly runtime:**
   ```sh
   ld -o hello $PREFIX/lib/zoril/runtime.o hello.o
   ```
6. **Run your executable:**
   ```sh
   ./hello
   ```

### Starting from ZIL

A program written directly in ZIL, the Zoril Intermediate Language, skips step 1 and starts at `zilc`. ZIL is specified in [`doc/spec/intermediate_language.md`](spec/intermediate_language.md), and `corpus/zil/` in the source tree has one small program per group of opcodes, each with its expected exit code in its first line:

```sh
zilc 01_arithmetic.zil 01_arithmetic.ssa
qbe -o 01_arithmetic.s 01_arithmetic.ssa
as -o 01_arithmetic.o 01_arithmetic.s
ld -o 01_arithmetic $PREFIX/lib/zoril/runtime.o 01_arithmetic.o
./01_arithmetic; echo $?    # 30
```

With no output file, `zilc` writes the SSA to standard output, so the first three steps can be one pipeline: `zilc 01_arithmetic.zil | qbe | as -o 01_arithmetic.o`. `zbuild` builds `.zrl` programs only.

`zilc` checks a ZIL program's types, but the ownership and region checks run in `zoril`, before it writes ZIL. Hand-written ZIL therefore has none of the guarantees in [What Zoril Checks](SAFETY.md): like `unsafe` code, it is correct only as far as its author made it so.

`zbuild` automates these five steps for every module in your dependency graph.

---

## Creating and Using Modules

Zoril code is organized into modules. Each `.zrl` file is a module whose top-level definitions can be imported into other files.

### 1. Defining a Module

Create a file named `math_utils.zrl`:

```zoril,no-test,file=math_utils.zrl
// By default, definitions are private to the module.
// Use `pub` to expose functions, types, and constants.
pub fn square(x: i64) -> i64 {
    return x * x;
}

pub fn add(a: i64, b: i64) -> i64 {
    return a + b;
}
```

### 2. Importing and Using the Module

In your main program (for example, `app.zrl`):

```zoril,no-test,file=app.zrl
import "io.zrl";
import "math_utils.zrl";

// Bring specific items into scope with `use`
use io::println;
use math_utils::{add, square};

fn main() -> i32 {
    let sum = add(5, 3);
    let sq = square(sum);
    return 0;
}
```

A module's name is its file name without `.zrl`, and the namespace is that name, so a file you import must be named like an identifier: letters, digits and `_`, not starting with a digit, and not a keyword (`math_utils.zrl` is fine; `my-utils.zrl` and `2d.zrl` are rejected at the `import` with `module name 'my-utils' is not an identifier; rename the file`). The program you build can have any file name.

You can also use module namespaces directly or assign aliases with `as`:

```zoril,no-test,file=app_alias.zrl
import "math_utils.zrl" as m;

fn calc() -> i64 {
    return m::square(10);
}

fn main() -> i32 {
    let _ = calc();
    return 0;
}
```

### 3. Compiling Multi-Module Projects

When using `zbuild`, simply point it at your entry file:

```sh
zbuild -o app app.zrl
```

`zbuild` inspects the `import` statements, automatically locates `math_utils.zrl` and standard library modules, compiles any modules that have changed, and links the resulting objects. If modules are stored in separate directories (e.g. `src/` or `lib/`), pass include flags:

```sh
zbuild -I lib -o app app.zrl
```

---

## Calling C Libraries (FFI)

Zoril supports calling functions from external C object files through its Foreign Function Interface (FFI).

> [!NOTE]
> **FFI scope and libc:** by default a Zoril program uses a standalone assembly runtime (`runtime.o`) and no C runtime, so C code it links must not need libc. To call libc (`printf`, `getenv`, `qsort`) or a shared library (`-lz`), build with `--hosted` (below): the program is then linked into an ordinary libc process.
>
> `zbuild` links C objects and libraries too: `--link-object FILE`, `-L DIR`, `-l NAME` and `--link-arg ARG` (see below). The manual pipeline works as well.

### 1. Defining and Declaring Foreign Functions

Consider a standalone C file without libc dependencies, `mylib.c`:

```c,file=mylib.c
// A simple C library function without libc dependencies
int c_add(int a, int b) {
    return a + b;
}
```

In your Zoril code, declare the external C function signature using `extern "C" fn`:

```zoril,no-test
extern "C" fn c_add(a: i32, b: i32) -> i32;
```

### 2. The `unsafe` Boundary

Because foreign C code is outside the scope of the Zoril compiler's safety checks, all calls to `extern` functions must occur within an `unsafe { ... }` block:

```zoril,no-test,file=app_ffi.zrl
extern "C" fn c_add(a: i32, b: i32) -> i32;

fn main() -> i32 {
    let result = unsafe { c_add(40, 2) };
    if result == 42 {
        return 0;
    }
    return 1;
}
```

Calling an `extern` function without `unsafe` results in a compile error: `error: call to extern function requires unsafe block`

### Letting C call Zoril

Give an `extern "C" fn` a body and it becomes a function C can call: an unmangled symbol of the same name, the C calling convention, and a body the compiler checks like any other. Zoril code calls it without `unsafe`.

```zoril,no-test
extern "C" fn zoril_clamp(x: i32, lo: i32, hi: i32) -> i32 {
    if x < lo { return lo; }
    if x > hi { return hi; }
    return x;
}
```

The signature may use only what C can take (sized integers, `bool`, floats, raw pointers); a struct travels as a pointer to it. A trap inside such a function ends the process with the usual status (134 for a bounds failure); nothing unwinds through the C frames.

### Passing a callback to C

Name an `extern "C" fn` where a C function pointer is expected; the pointer type is `extern "C" fn(..)`, and a `*mut u8` carries the `void *userdata`:

```zoril,no-test
extern fn register(cb: extern "C" fn(*mut u8, i32) -> i32, userdata: *mut u8);

extern "C" fn on_event(ud: *mut u8, code: i32) -> i32 {
    return code;
}

fn start(ud: *mut u8) {
    unsafe { register(on_event, ud); }
}
```

Only a function defined with `extern "C" fn` converts; a plain `fn` or a closure does not (they are two words, code and environment). Calling a C function pointer from Zoril needs `unsafe`.

### 3. Passing Data Across FFI

- **Numeric types:** Types like `i32`, `i64`, `u8`, `usize`, `f32`, and `f64` match C ABI primitives directly. Spell the C type, not its width: `ffi::c_int`, `ffi::c_long`, `ffi::c_char`, ... (`import "ffi.zrl";`), because `char` is unsigned on aarch64 Linux and `long` is 32 bits on 64-bit Windows, and a port then changes the aliases instead of your code.
- **Raw pointers:** C pointer types map to Zoril raw pointers (`*u8`, `*mut u8`).
- **Slices:** Zoril slices (`[u8]`) are fat pointers containing both a data pointer and length (`ptr` and `len`). When passing a slice's buffer to a C function expecting a raw pointer, pass `slice.ptr`.

### Hosted mode: calling libc and shared libraries

`--hosted` links the program into a libc process. The program is entered from the C runtime's `main`, the link goes through `cc` (so crt files, libc and dynamic libraries are the platform's), and `main`'s result goes back through libc's `exit`, which flushes C `stdio`. Nothing else about the language changes.

```sh
zbuild --hosted -o app app.zrl                  # app.zrl declares extern fn printf(fmt: *u8, ...) -> i32;
zbuild --hosted -o app -l z app.zrl             # and links libz
zbuild --hosted -o app -l m app.zrl             # libm: extern fn sqrt(x: f64) -> f64; and the rest of <math.h>
zbuild --hosted --link-arg -static -o app app.zrl   # a statically linked executable
```

A static link needs a static version of every library the program links (`libc.a`, `libm.a`, ...). With glibc, the functions that load code at run time - host and user name lookup, `dlopen` - do not work in a static executable; musl has no such limit.

The manual pipeline is the same with two changes: `zoril --hosted ...` names the entry `zoril_main`, and the last step is `cc -o app app.o runtime_hosted.o [-lz ...]` instead of `ld`. A trap (a bounds failure, say) is libc's `abort`: status 134 as in the default mode, and C `stdio` that has not been flushed is lost. `io::exit` (and a panic's exit) ends the process at once with `exit_group`: C `stdio` is not flushed and `atexit` handlers do not run, so return from `main` when the program uses C `stdio`. Default builds are unchanged. The system's libc is not part of the reproducible-build claim.

### 4. Linking External C Code

With `zbuild`, name the C object, or the directory and name of a library, on the command line:

```sh
cc -c mylib.c -o mylib.o
zbuild -o app --link-object mylib.o app_ffi.zrl      # an object file
zbuild -o app -L . -l mylib app_ffi.zrl              # libmylib.a or libmylib.so in .
zbuild -o app --link-arg=-Map=app.map app_ffi.zrl    # anything else ld takes
```

These reach the final link only: changing one relinks and recompiles no module. The manual pipeline is below.

To compile a Zoril program that links against external C code or libraries, compile your C code into an object file and link it during the final linking stage:

```sh,file=build_ffi.sh
# 1. Compile C code
cc -c mylib.c -o mylib.o

# 2. Compile Zoril module to object code
zoril -I $PREFIX/share/zoril/stdlib --emit-zil -o app_ffi.zil app_ffi.zrl
zilc app_ffi.zil app_ffi.ssa
qbe -o app_ffi.s app_ffi.ssa
as -o app_ffi.o app_ffi.s

# 3. Link Zoril runtime, Zoril object, and C object together (without -lc)
ld -o app_ffi $PREFIX/lib/zoril/runtime.o app_ffi.o mylib.o
```

---

## Next Steps

- Explore [A Tour of Zoril](tour.md) for a guide to language syntax, ownership, arenas, pattern matching, structs, and traits.
- Review [What Zoril Checks](SAFETY.md) to understand the compiler's safety model and verification tiers.
