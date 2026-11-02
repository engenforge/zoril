# Zoril Standard Library Specification

This document specifies the standard library as of `v0.1.0-alpha`.

Zoril aims to provide a modern, efficient, and secure foundation for systems programming by bypassing the legacy C standard library (`libc`) and interfacing directly with the kernel.

> [!NOTE]
> This specification documents the core architectural principles, design rationale, and memory invariants of the Zoril standard library. For the complete, compiler-verified reference of all 25 standard library modules, types, and function signatures, consult the system manual pages (`man zoril-stdlib` and `man zoril-<module>`, section 3) generated from `doc/man/*.scd`.

## 1. Core Principles

- **Libc-Free:** The Zoril runtime and standard library do not link against `libc`. All system interactions are performed via direct kernel interrupts (e.g., the `syscall` instruction on x86_64).
- **Modern Defaults:** Use fat pointers for strings and slices, and sum types for error handling.
- **Explicit Resource Management:** Deterministic memory management with explicit allocators.

## 2. Memory Management

### 2.1 Direct Allocation

Zoril interacts with the OS memory manager directly via system calls (e.g., `mmap` and `munmap` on Linux). The standard library provides a raw page allocator as the foundation for higher-level allocators.

### 2.2 Arena Allocators

The user-facing allocator for Zoril programs is `Arena` in `mem.zrl`. It provides safe, region-based allocation with automatic reclamation via `Drop`:

- **`Arena.new(capacity: u64) -> Result<Arena, Error>`**: Reserves a contiguous block of virtual memory with an initial capacity. Returns `Err` (e.g. `ENOMEM` or `EINVAL`) on failure.
- **`arena.reset(&mut self)`**: Rewinds the arena to the beginning and poisons the released region. Calling `reset()` while any reference or collection borrowing the arena is live is rejected at compile time.
- **`arena.mark(&self) -> ArenaMark`**: Captures a checkpoint of the arena's current allocation offset.
- **`arena.reset_to(&mut self, mark: ArenaMark)`**: Rewinds the arena back to a previous mark, poisoning memory allocated past that mark. Traps if the mark is invalid.
- **`Drop for Arena`**: Automatically unmaps the underlying virtual memory when the `Arena` handle goes out of scope.

Low-level compiler and tool internals that require raw allocator entry points use the internal `mem_raw.zrl` module:

- **`arena_init(capacity: u64) -> *mut ArenaHeader`**: Raw allocator mapping entry point (`unsafe fn`).
- **`zoril_allocator_alloc(arena, size)`**: Direct bump-allocation primitive (`unsafe fn`).
- **`arena_free(arena)`**: Direct unmapping primitive (`unsafe fn`).
- **`arena_reset(arena, offset)`**: Direct rewind primitive with memory poisoning (`unsafe fn`).

### 2.3 The `box` Expression

The built-in `box expr` syntax utilizes a default global allocator implemented in Zoril/Assembly that manages memory via `mmap`, bypassing the need for a C-style `malloc`.

## 3. Strings and Slices

### 3.1 Fat Pointers and `[u8]` String Model

Strings (`[u8]`) and Slices (`[T]`) are implemented as fat pointers: a structure containing a pointer to the data and a `usize` length.

- **$O(1)$ Length:** Accessing `.len` is a constant-time operation.
- **Safety:** The verifier uses the length field to enforce bounds checks on all accesses.
- **Equality:** Byte slices are compared directly using standard equality operators (`==` and `!=`).

`[u8]` serves as Zoril's primary byte string type, supporting inherent methods defined in `stdlib/string.zrl`:

- **`s.starts_with(prefix: [u8]) -> bool`**: Returns true if the slice begins with `prefix`.
- **`s.ends_with(suffix: [u8]) -> bool`**: Returns true if the slice ends with `suffix`.
- **`s.sub(start: usize, len: usize) -> [u8]`**: Returns a subslice starting at `start` with at most `len` bytes. Out-of-bounds start returns an empty slice; length is clamped to available remaining bytes without overflow.
- **`s.trim() -> [u8]`**: Strips leading and trailing ASCII whitespace.
- **`s.split(delim: u8, a: &Arena) -> Vec<[u8]>`**: Splits the slice by delimiter byte into a vector allocated in the provided `Arena`.
- **`s.find(sub: [u8]) -> Option<usize>`**: Returns `Option.Some(index)` of the first occurrence of `sub`, or `Option.None`.
- **`s.find_byte(ch: u8) -> Option<usize>`**: Returns `Option.Some(index)` of the first occurrence of byte `ch`, or `Option.None`.
- **`s.contains(sub: [u8]) -> bool`**: Returns true if `sub` appears anywhere in the slice.
- **`s.parse_i64() -> Option<i64>`**: Parses decimal integer with optional leading `+` or `-`, returning `Option.Some(val)` within `[i64::MIN, i64::MAX]` or `Option.None` on format error or arithmetic overflow.
- **`s.parse_u64() -> Option<u64>`**: Parses decimal unsigned integer with optional leading `+`, returning `Option.Some(val)` within `[0, u64::MAX]` or `Option.None` on format error or arithmetic overflow.

Free helper `is_whitespace(c: u8) -> bool` is also provided in `stdlib/string.zrl`. The former free functions `str_*` and `str_eq` have been removed in favor of these inherent methods and direct `==` comparisons.

### 3.2 UTF-8 and `Str` (`str.zrl`)

A `[u8]` is just bytes. `Str` is a byte slice known to hold well-formed UTF-8 (RFC 3629: no overlong forms, surrogates, or code points above U+10FFFF). Its field is private, so a `Str` only comes from a checked constructor:

| Constructor                           | Check                                                             |
| ------------------------------------- | ----------------------------------------------------------------- |
| `@str("literal")`                     | At compile time; invalid UTF-8 is a compile error                 |
| `Str.from_utf8(bytes) -> Option<Str>` | At run time; `None` when invalid (`utf8_valid` is the bare check) |
| `s.substr(start, end) -> Option<Str>` | Byte offsets must be char boundaries                              |

`Str` provides byte access (`as_bytes`, `len`), structural queries (`is_empty`, `char_count`, `is_char_boundary`), and mirrors text operations:

- **`s.substr(start: usize, end: usize) -> Option<Str>`**: Returns a subslice between byte offsets `start` and `end`, requiring both to fall on UTF-8 character boundaries.
- **`s.starts_with(prefix: [u8]) -> bool`**
- **`s.ends_with(suffix: [u8]) -> bool`**
- **`s.contains(sub: [u8]) -> bool`**
- **`s.find(sub: [u8]) -> Option<usize>`**: Returns the byte index of the first occurrence of `sub` starting at a UTF-8 character boundary, or `Option.None` if `sub` is not found, is invalid UTF-8, or matches mid-codepoint.
- **`s.trim() -> Str`**: Trims whitespace while guaranteeing the result remains valid UTF-8.

`String` (`string.zrl`) accepts arbitrary bytes through `push_u8`/`push_str`, so viewing one as text is checked: `as_str() -> Option<Str>`; `push_s(Str)` and `String.from_str(Str)` keep valid text valid.

A `char` holds a Unicode scalar value: no surrogate (U+D800..U+DFFF) and nothing above U+10FFFF. Checked code cannot cast a number to a `char` (a forged `char` would reach `Str`'s invariant and every char match), so `unicode::char_from_u32(n) -> Option<char>` (`unicode.zrl`) is the checked way from a number, `None` for the two ranges the type excludes; `c as u32` takes the value back. A char literal is a `u8`, so `let c: char = 'm'` is a byte standing for a char, which is sound because every byte value is a scalar value.

### 3.3 Byte Buffers: `Vec<u8>` vs Internal `ByteVec`

`Vec<u8>` (`stdlib/vec.zrl`) is the sole user-facing growable byte buffer type in Zoril. It supports all standard vector operations, slicing (`as_slice`, `as_mut_slice`), indexing, and can be backed by an explicit arena via `Vec::<u8>::new_in(&arena)`.

The internal `ByteVec` (`stdlib/bytevec.zrl`) is a minimal bump-backed buffer reserved strictly for compiler code generation and assembler binary emission where zero-overhead arena chunks are required. It is not part of the public application API.

### 3.4 `Vec<T>` Indexing

`Vec<T>` is a privileged standard library type: `v[i]` and `v[i] = val` are lowered by the compiler rather than dispatched through a user-definable index trait, and user-defined types cannot overload `[]` (only slices, arrays and `Vec<T>` are indexable).

- **Out of bounds:** `v[i]`, `v[i] = val` and `v.set(i, val)` compare `i` unsigned against `v.len` and terminate the process with exit code 134 (`SIGABRT`), as slice and array bounds checks do.
- **Fallible access:** `v.get(i)` and `v.get_mut(i)` return `Option<&T>` and `Option<&mut T>` instead of trapping.

## 4. System Interface

### 4.1 Direct Syscalls

The standard library wraps kernel system calls using the `@syscall` intrinsic. On x86_64, the System V ABI is followed for register-based argument passing; on aarch64, the standard ARM ABI is used.

### 4.2 I/O Operations

The `io` module provides direct wrappers for kernel I/O returning `Result`:

- `read(fd: Fd, buffer: [mut u8]) -> Result<usize, io::Error>`
- `write(fd: Fd, data: [u8]) -> Result<usize, io::Error>`
- `close(fd: Fd) -> Result<(), io::Error>`
- `write_all<W: Write>(w: &mut W, buf: [u8]) -> Result<(), io::Error>`: Repeatedly writes until all bytes are written, retrying on `EINTR`.

Opening a file by raw flags is Linux-only and lives in `stdlib/os/linux.zrl` (`os_linux::open`, `os_linux::open_file`); portable code uses `OpenOptions`. The named open flag constants are defined there too: `O_RDONLY`, `O_WRONLY`, `O_RDWR`, `O_CREAT`, `O_EXCL`, `O_NOCTTY`, `O_TRUNC`, `O_APPEND`, `O_NONBLOCK`, `O_DIRECTORY`, and `O_CLOEXEC`.

Configurable file creation and opening is provided by `OpenOptions` in `stdlib/file.zrl` (`File.options() -> OpenOptions`):

```zoril,no-test
let f = File.options()
    .write(true)
    .create(true)
    .truncate(true)
    .unix_mode(0o644)
    .open("file.txt")?;
```

`File.create` and `File.append` are convenience constructors in `stdlib/file.zrl` utilizing `OpenOptions` with default mode `0o644`; a program that calls them imports `file.zrl`. `lseek` and the `LOCK_*` flags are POSIX-only and live in `stdlib/os/unix.zrl`.

For standard streams and common diagnostics, the `io` module provides panic-on-failure print helpers:

- `print(s: [u8])`: Writes `s` to stdout (fd 1).
- `println(s: [u8])`: Writes `s` followed by newline to stdout.
- `eprint(s: [u8])`: Writes `s` to stderr (fd 2).
- `eprintln(s: [u8])`: Writes `s` followed by newline to stderr.

The `print`/`println`/`eprint`/`eprintln` functions intentionally write directly and unbuffered to fd 1 and fd 2 using `write_all`. Diagnostic and panic messages must never remain trapped in a userspace buffer across process exit or crash boundaries.

### 4.3 Stream Traits and Buffered I/O (`io.zrl`, `bufio.zrl`)

Generic code reads and writes bytes through two traits, so one function serves files, the standard streams, and in-memory buffers:

```zoril,no-test
pub trait Read  { fn read(self: &mut Self, buf: [mut u8]) -> Result<usize, io::Error>; }
pub trait Write { fn write(self: &mut Self, buf: [u8]) -> Result<usize, io::Error>; }
```

Both return the byte count transferred on success (`Ok(usize)`), or `Err(io::Error)` on failure. A short count is not an error; `write_all(&mut w, buf)` (`io.zrl`) and `read_to_end(r, arena)` (`file.zrl`) loop until done. Buffered I/O is provided by `BufReader` and `BufWriter` (`bufio.zrl`).

- **`File`**
  - Module: `io.zrl`
  - Implements: `Read`, `Write`
  - Notes: Owns its descriptor; closes on drop. `File.options` and `File.create`/`File.append` (both in `file.zrl`), `File.from_fd`, `File.fd`
- **`Stdin` / `Stdout` / `Stderr`**
  - Module: `io.zrl`
  - Implements: `Read` / `Write` / `Write`
  - Notes: Borrow fds 0/1/2; never close them
- **`SliceReader`**
  - Module: `io.zrl`
  - Implements: `Read`
  - Notes: Reads from an in-memory `[u8]`
- **`String`**
  - Module: `string.zrl`
  - Implements: `Write`
  - Notes: Appends; never short
- **`BufReader<R>`**
  - Module: `bufio.zrl`
  - Implements: `Read`
  - Notes: Buffered reader over an underlying `Read`
- **`BufWriter<W>`**
  - Module: `bufio.zrl`
  - Implements: `Write`
  - Notes: Buffered writer with explicit `flush`, flushed on drop
- **`Fd`**
  - Module: `io.zrl`
  - Implements: `Read`, `Write`
  - Notes: Typed descriptor handle ((`stdin()`, `stdout()`, `stderr()`; `os_linux::open`)); unbuffered I/O. Forging raw integer requires `unsafe`: `Fd.from_unix_raw(n)` builds one and `fd.unix_raw()` reads the integer back (an integer descriptor is a Unix fact, so the names say so)

### 4.4 Process Control and Filesystem Operations (`proc.zrl`, `fsys.zrl`)

Process spawning and management in `proc.zrl` use `Command` and `Child`, with fallible operations returning `Result<_, io::Error>`:

- `Command::new(program, &arena)`: Builds a command tied to an arena.
- `cmd.arg(arg)`: Appends an argument.
- `cmd.set_stdin(fd)` / `cmd.set_stdout(fd)` / `cmd.set_stderr(fd)`: Configures stream redirection with typed `Fd` handles.
- `cmd.spawn() -> Result<Child, io::Error>`: Spawns the process.
- `cmd.status() -> Result<ExitStatus, io::Error>`: Runs and waits for termination.
- `child.wait() -> Result<ExitStatus, io::Error>`: Waits for child completion.
- `child.kill() -> Result<(), io::Error>`: Forcibly terminates the child. `child.unix_kill(sig)` sends a Unix signal number; `ExitStatus.unix_signal()` reports one. The raw process syscalls (`sys_fork`, `sys_execve`, `sys_wait4`, `sys_kill`, `sys_pipe2`, `sys_dup2`, `sys_fstat`) are Linux-only and live in `stdlib/os/linux.zrl`.
- `exit(code: i32) -> never`: Terminates the process via the `exit` syscall (60).

Filesystem and lock operations in `fsys.zrl`:

- `unlink_path(path, &arena) -> Result<(), io::Error>`: Removes a file or directory link.
- `rename_path(from, to, &arena) -> Result<(), io::Error>`: Atomically renames a file.
- `list_dir(path, &arena) -> Result<Vec<[u8]>, io::Error>`: Reads directory entry names.
- `make_dir_all(path, &arena) -> Result<(), io::Error>`: Recursively creates directories.
- `acquire_file_lock(path) -> Result<FileLock, io::Error>`: Acquires an exclusive flock guard that unlocks and closes on `drop`.

### 4.4b C interop (`ffi.zrl`)

`ffi` holds the C type aliases (`c_char`, `c_schar`, `c_uchar`, `c_short`, `c_ushort`, `c_int`, `c_uint`, `c_long`, `c_ulong`, `c_longlong`, `c_ulonglong`, `c_size_t`, `c_float`, `c_double`) with the widths of x86_64 Linux, and `unsafe fn cstr_len(p: *u8) -> usize`. Struct layout is the C layout (`doc/spec/abi.md` §2.1).

### 4.4a Time (`time.zrl`)

- `time::monotonic_ns() -> i64`: nanoseconds on a monotonic clock (`CLOCK_MONOTONIC`); only differences mean anything.
- `time::sleep_ns(ns: i64)`: blocks for at least `ns` nanoseconds, resuming after a signal; zero or less returns at once. Neither call can fail on Linux, so neither returns a `Result`. The wall clock is `fsys::realtime_ns`.

### 4.5 Formatting (`fmt.zrl`)

Formatting primitives in `stdlib/fmt.zrl` are sink-agnostic and format integers and hex directly into any destination implementing `Write`:

- `fmt::write_u64<W: Write>(w: &mut W, v: u64) -> Result<(), io::Error>`
- `fmt::write_i64<W: Write>(w: &mut W, v: i64) -> Result<(), io::Error>`
- `fmt::write_u64_hex<W: Write>(w: &mut W, v: u64) -> Result<(), io::Error>`
- `fmt::write_hex_byte<W: Write>(w: &mut W, b: u8) -> Result<(), io::Error>`

`String` also provides convenience formatting methods in `stdlib/string.zrl`: `s.push_u64(v)`, `s.push_i64(v)`, and `s.push_u64_hex(v)`.

## 5. Error Handling

### 5.1 No `errno`

Zoril rejects global error state. All fallible operations return a `Result<T, E>` sum type. Operating system errors are encapsulated in types such as `io::Error` (`io.zrl`), exposing a portable category via `.kind()` (`io::ErrorKind`), an OS-level description via `.message()`, and the Linux errno number only through the Linux-named `.linux_errno()`.

### 5.2 Mandatory Handling and Unwrap

A `Result` is handled by matching on it, propagating it with `?`, or unwrapping it: `.unwrap()` panics on an error and otherwise returns the value, and `.expect(msg)` panics with a custom message. The compiler does not require a `Result` to be used: a call whose `Result` is discarded (`f();`) compiles without a diagnostic.

### 5.3 `Result` and `?`

`Result<T, E>` is an ordinary enum in `core.zrl`. The `?` operator on a `Result` returns its `Err` from the enclosing function early, and on an `Option` returns its `None`. `trait Error { fn message(self: &Self) -> [u8]; }` is the trait for error types, and `impl Error for [u8]` is provided: a byte slice message returns itself.

## 6. Iteration (`iter.zrl`)

```zoril,no-test
pub trait Iterator {
    type Item;
    fn next(self: &mut Self) -> Option<Self::Item>;
    // map, filter, fold and collect: default methods, below
}
```

An iterator yields items until it returns `None`; loops written against it carry no index to get wrong. The item type is the associated type `Item` (`I::Item` for an iterator type `I`), and the adapters are default methods that take the iterator by value, so every iterator has them and they chain:

- **`v.iter()` (`Vec<T>`)**: `VecIter<T>`, an iterator of `&T` over the elements in order
- **`m.iter()` (`HashMap<K, V>`)**: `HashMapIter<K, V>`, an iterator of `(&K, &V)` in table order
- **`range(start, end)`**: `Range`, an iterator of `usize` over `start..end`
- **`it.map(f: fn(Item) -> U)`**: `Map<I, U>`, an iterator of `U`
- **`it.filter(keep: fn(Item) -> bool)`**: `Filter<I>`, an iterator of `Item`; items are passed to `keep` by value, so they must be copyable (references and primitives are)
- **`it.fold(init: A, f: fn(A, Item) -> A)`**: `A`
- **`it.collect()`**: `Vec<Item>` on the global allocator

`v.iter().map(double).filter(is_even).fold(0, add)` infers every type argument: a method's from its arguments, an iterator's item type from its impl. A bound names the trait alone (`fn sum<I: Iterator>(it: I)`, with `use iter::Iterator;`), and the item type is `I::Item`. The functions passed in are function values, closures included (`v.iter().map(|x: &i32| -> i32 { *x + k })`); an adapter holding a capturing closure cannot outlive the frame that made the closure.

Because Zoril's `..` operator is syntax exclusively for range patterns and `for` loop headers (`for i in start..end`), ranges are not first-class expression values. The standard library provides `iter::range(start, end)` to construct an iterator value over `[start, end)`, enabling full adapter chaining (`range(0, 10).map(...).fold(...)`).

## 7. Equality (`core.zrl`, `cmp.zrl`)

```zoril,no-test
pub trait Eq   { fn eq(self: &Self, other: &Self) -> bool; }
pub trait Hash { fn hash(self: &Self) -> u64; }
```

`Eq` is an equivalence relation; `Hash` must agree with it (equal values hash equally), and `HashMap<K, V>` requires `K: Hash + Eq`. `cmp.zrl` implements `Eq` for `bool`, every integer type and `Option<T: Eq>`, and provides `contains<T: Eq>(items: [T], x: &T) -> bool`. There is no separate `PartialEq`: impl methods share one namespace per type (`Type::method`), so two traits each declaring `eq` would collide on one type; a type whose equality is not an equivalence (a float, where NaN != NaN) does not implement `Eq`. `Hash` is implemented for `i32`, `u32` and `u64` (`hash_impls.zrl`), each by widening to `u64`.

## 8. Duplication (`core.zrl`, `clone.zrl`)

```zoril,no-test
pub trait Clone { fn clone(self: &Self) -> Self; }
pub trait Copy {}
```

`Copy` marks implicit bitwise duplication and is structural: a type is Copy exactly when it owns no `Drop` value, a `T: Copy` bound needs no impl, and `impl Copy for T` is rejected otherwise. `Clone` is explicit and deep: `clone.zrl` implements it for `bool`, every integer type, `Option<T: Clone>`, `Vec<T: Clone>` (element-wise, on the same allocator) and `String` (its own buffer). `#[derive(Clone)]` writes a struct's field-by-field impl; see the surface specification §8.5.

## 9. Collections (`stdlib/hashmap.zrl`)

`HashMap<K, V>` is an open-addressing hash table with linear probing that automatically resizes when its load factor exceeds 0.7. Keys must implement `Hash + Eq`.

- **`new`**
  - Signature: `fn new(arena: &Arena) -> HashMap<K, V>`
  - Description: Allocates an initial 16-slot map in the given arena
- **`insert`**
  - Signature: `fn insert(self: &mut HashMap<K, V>, key: K, value: V)`
  - Description: Inserts or updates an entry; triggers resize if load factor exceeds 0.7
- **`get`**
  - Signature: `fn get(self: &HashMap<K, V>, key: &K) -> Option<&V>`
  - Description: Looks up by key reference, returning a borrowed reference to the value
- **`get_mut`**
  - Signature: `fn get_mut(self: &mut HashMap<K, V>, key: &K) -> Option<&mut V>`
  - Description: Looks up by key reference, returning a mutable reference to the value
- **`contains_key`**
  - Signature: `fn contains_key(self: &HashMap<K, V>, key: &K) -> bool`
  - Description: Checks if key exists in the map
- **`remove`**
  - Signature: `fn remove(self: &mut HashMap<K, V>, key: &K) -> Option<V>`
  - Description: Removes key and returns previous value; shifts following entries to preserve probe chains without tombstones
- **`len`**
  - Signature: `fn len(self: &HashMap<K, V>) -> usize`
  - Description: Number of key-value pairs stored in the map
- **`cap`**
  - Signature: `fn cap(self: &HashMap<K, V>) -> usize`
  - Description: Allocated bucket capacity
- **`iter`**
  - Signature: `fn iter(self: &HashMap<K, V>) -> HashMapIter<K, V>`
  - Description: Yields `(&K, &V)` pairs in table order
