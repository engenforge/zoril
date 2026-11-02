zoril-sys(3)

# NAME

zoril-sys - Low-level kernel system calls and memory mapping wrappers

# SYNOPSIS

*import* "sys.zrl";

```
pub fn syscall_failed(ret: i64) -> bool;
```

# DESCRIPTION

The *sys* module provides low-level kernel system calls and memory mapping wrappers for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*syscall_failed*
```
pub fn syscall_failed(ret: i64) -> bool;
```

	Whether a raw syscall's result is an error. Linux reports a failed syscall by returning -errno in
	the result register - any value in [-4095, -1] - and not the libc MAP\_FAILED of -1: a check for
	1 alone misses every other errno, and the caller then uses a value that is not what the syscall
	returns for success. mmap\_or\_trap did exactly that, so a failed mmap handed arena\_init a value
	in that range, the header was written through it, and the process died with 139 and no message
	instead of the panic below.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*mmap_or_trap*
```
pub unsafe fn mmap_or_trap(addr: *u8, length: u64, prot: u64, flags: u64, fd: i64, offset: u64) -> *mut u8;
```

	Caller obligation: parameters must specify valid memory protection and mapping flags; traps on kernel failure.

*munmap_or_trap*
```
pub unsafe fn munmap_or_trap(addr: *u8, length: u64);
```

	Caller obligation: addr and length must specify a currently valid mapped memory range.

*arg_to_slice*
```
pub unsafe fn arg_to_slice(argv: **u8, i: i32) -> [u8];
```

	Converts argv[i] (a C-style nul-terminated string) to a Zoril byte slice.
	Returns an empty slice if i is out of range (argv[i] is a null pointer).

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
