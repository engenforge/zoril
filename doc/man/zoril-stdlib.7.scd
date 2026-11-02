zoril-stdlib(7)

# NAME

zoril-stdlib - Overview of the Zoril standard library modules

# SYNOPSIS

*import* "<module>.zrl";++
*use* <module>::{<item>, ...};

# DESCRIPTION

The Zoril standard library provides fundamental data structures, memory
management allocators, I/O streams, filesystem primitives, and process
execution facilities without depending on the legacy C standard library (*libc*).
All operating system interactions are performed via direct kernel system calls.

# INSTALLATION AND DISCOVERY

Standard library modules are installed as source files (*.zrl*) into:

```
$DATADIR/zoril/stdlib/ (default: /usr/local/share/zoril/stdlib/)
```

The compiler (*zoril*(1)) and driver (*zbuild*(1)) automatically locate the
standard library relative to their executable path (*../share/zoril/stdlib*).
Alternatively, the search location can be specified explicitly using the
*-I* command-line option.

# MODULE OVERVIEW

*zoril-args*(3)
	Command-line argument inspection and iteration (*Args*).

*zoril-bufio*(3)
	Buffered stream wrappers (*BufReader*, *BufWriter*).

*zoril-bytevec*(3)
	Internal bump-backed byte vector buffers (*ByteVec*).

*zoril-clone*(3)
	Explicit deep cloning traits and implementations (*Clone*, *Copy*).

*zoril-cmp*(3)
	Equivalence relations and slice search helpers (*Eq*, *contains*).

*zoril-core*(3)
	Fundamental sum types (*Option*, *Result*) and standard traits.

*zoril-core0*(3)
	Low-level runtime panic, abort, trap, and byte swap primitives.

*zoril-file*(3)
	File handle abstraction (*File*), *OpenOptions*, and file read/write helpers.

*zoril-ffi*(3)
	C type aliases (*c_int*, *c_long*, ...) and *cstr_len* for calling C.

*zoril-fmt*(3)
	Sink-agnostic formatting for decimal integers and hexadecimal bytes.

*zoril-fsys*(3)
	Filesystem operations (*list_dir*, *make_dir_all*, *acquire_file_lock*).

*zoril-hash_impls*(3)
	Primitive type implementations of the *Hash* trait.

*zoril-hashmap*(3)
	Open-addressing hash table with linear probing (*HashMap*).

*zoril-intern*(3)
	Arena-backed string deduplication and interning table (*InternTable*).

*zoril-io*(3)
	Direct kernel I/O, typed file descriptors (*Fd*), and *Read*/*Write* traits.

*zoril-iter*(3)
	Functional iteration traits and combinators (*Iterator*, *range*).

*zoril-local_mem*(3)
	Internal test fixture for memory allocation failure validation.

*zoril-mem*(3)
	Safe region-based arena memory management (*Arena*, *ArenaMark*).

*zoril-mem_raw*(3)
	Low-level raw memory mapping, bump primitives, and heap allocation.

*zoril-os_linux*(3)
	Linux-only interface: *O_* open flags and opening by raw flags. Imported as *os/linux.zrl*.

*zoril-os_unix*(3)
	POSIX-only interface: file lock flags and *lseek*. Imported as *os/unix.zrl*.

*zoril-proc*(3)
	Subprocess spawning and execution management (*Command*, *Child*).

*zoril-sha256*(3)
	Cryptographic SHA-256 digest computation (*Sha256*).

*zoril-softfp*(3)
	Software floating-point arithmetic primitives.

*zoril-str*(3)
	Validated UTF-8 string slices and character validation (*Str*).

*zoril-string*(3)
	Growable byte strings (*String*) and inherent methods on *[u8]*.

*zoril-sys*(3)
	Low-level kernel system calls and memory mapping wrappers.

*zoril-time*(3)
	Monotonic clock and sleep (*monotonic_ns*, *sleep_ns*).

*zoril-unicode*(3)
	Checked conversion from a Unicode scalar value to a *char* (*char_from_u32*).

*zoril-vec*(3)
	Growable generic arrays (*Vec<T>*) with arena and allocator support.

# SEE ALSO

*zoril*(1), *zbuild*(1),
*zoril-args*(3), *zoril-bufio*(3), *zoril-bytevec*(3), *zoril-clone*(3),
*zoril-cmp*(3), *zoril-core*(3), *zoril-core0*(3), *zoril-file*(3), *zoril-ffi*(3),
*zoril-fmt*(3), *zoril-fsys*(3), *zoril-hash_impls*(3), *zoril-hashmap*(3),
*zoril-intern*(3), *zoril-io*(3), *zoril-iter*(3), *zoril-local_mem*(3),
*zoril-mem*(3), *zoril-mem_raw*(3), *zoril-os_linux*(3), *zoril-os_unix*(3),
*zoril-proc*(3), *zoril-sha256*(3),
*zoril-softfp*(3), *zoril-str*(3), *zoril-string*(3), *zoril-sys*(3), *zoril-time*(3),
*zoril-unicode*(3), *zoril-vec*(3)
