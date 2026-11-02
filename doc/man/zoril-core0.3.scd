zoril-core0(3)

# NAME

zoril-core0 - Low-level runtime panic, abort, trap, and byte swap primitives

# SYNOPSIS

*import* "core0.zrl";

```
pub fn is_str_eq(a: [u8], b: [u8]) -> bool;
pub fn subslice(s: [u8], start: usize, len: usize) -> [u8];
pub fn subslice_from(s: [u8], start: usize) -> [u8];
pub fn is_digit(c: u8) -> bool;
pub fn is_hex_digit(c: u8) -> bool;
pub fn hex_digit_val(c: u8) -> u8;
pub fn is_alpha(c: u8) -> bool;
pub extern fn zoril_abort() -> never;
pub fn zoril_user_trap(msg: [u8]) -> never;
pub fn zoril_user_panic(msg: [u8]) -> never;
pub fn zoril_user_panic_error(msg: [u8], err: [u8]) -> never;
pub fn set_ice_note(note: [u8]);
pub fn ICE(msg: [u8]) -> never;
```

# DESCRIPTION

The *core0* module provides low-level runtime panic, abort, trap, and byte swap primitives for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*is_str_eq*
```
pub fn is_str_eq(a: [u8], b: [u8]) -> bool;
```

	Returns true if two byte slices have identical lengths and byte contents.

*subslice*
```
pub fn subslice(s: [u8], start: usize, len: usize) -> [u8];
```

	s[start .. start + len], bounds-checked. Re-slicing a byte slice has no safe
	spelling in the surface language yet (Rust writes &s[a..b]), so every caller
	was doing the pointer arithmetic itself; this is the one marked site, and it
	traps rather than reading past the end.

*subslice_from*
```
pub fn subslice_from(s: [u8], start: usize) -> [u8];
```

	s[start ..], bounds-checked.

*is_digit*
```
pub fn is_digit(c: u8) -> bool;
```

	Returns true if byte c is an ASCII decimal digit ('0' through '9').

*is_hex_digit*
```
pub fn is_hex_digit(c: u8) -> bool;
```

	Returns true if byte c is an ASCII hexadecimal digit ('0'-'9', 'a'-'f', 'A'-'F').

*hex_digit_val*
```
pub fn hex_digit_val(c: u8) -> u8;
```

	Converts a hex digit character to its 0-15 value. Returns 0 for non-hex
	digits (callers are expected to have already validated via is\_hex\_digit).

*is_alpha*
```
pub fn is_alpha(c: u8) -> bool;
```

	Returns true if byte c is an ASCII alphabetic character ('a'-'z', 'A'-'Z').

*zoril_abort*
```
pub extern fn zoril_abort() -> never;
```

	Immediately terminates the process with an abort trap status.

*zoril_user_trap*
```
pub fn zoril_user_trap(msg: [u8]) -> never;
```

	The trap: a failure the program cannot continue past and cannot be expected to handle - a bound
	that does not hold, an allocation the runtime cannot honour, a failed mmap. It exits 134, the
	code the bounds checks, the arena and make safety-matrix read as "trapped", and not 1, because 1
	is indistinguishable from a program that merely returned 1 (doc/spec/safety\_model.md §4).

*zoril_user_panic*
```
pub fn zoril_user_panic(msg: [u8]) -> never;
```

	Prints a diagnostic panic message to standard error and terminates the process.

*zoril_user_panic_error*
```
pub fn zoril_user_panic_error(msg: [u8], err: [u8]) -> never;
```

	Prints a diagnostic message and error detail to standard error and terminates the process.

*set_ice_note*
```
pub fn set_ice_note(note: [u8]);
```

	Registers an internal compiler error diagnostic context string.

*ICE*
```
pub fn ICE(msg: [u8]) -> never;
```

	An internal error: a bug in the program itself (in a compiler, the compiler), not in its
	input. Exits with 134.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*is_mem_eq*
```
pub unsafe fn is_mem_eq(a: *u8, b: *u8, len: u64) -> bool;
```

	Compares two memory buffers for byte-level equality.

	Caller obligation: pointers a and b must be valid for len bytes.

*u64_to_str*
```
pub unsafe fn u64_to_str(val: u64, buf: *mut u8) -> [u8];
```

	Formats an unsigned 64-bit integer into a decimal byte string in buf, returning the formatted slice.

*swap_bytes*
```
pub unsafe fn swap_bytes(a: *mut u8, b: *mut u8, len: u64);
```

	Swaps len bytes between two memory regions.

	Caller obligation: src and dst must be valid for len bytes and non-overlapping.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
