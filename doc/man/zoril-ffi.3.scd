zoril-ffi(3)

# NAME

zoril-ffi - C type aliases and helpers for calling C

# SYNOPSIS

*import* "ffi.zrl";

```
```

# DESCRIPTION

The *ffi* module provides c type aliases and helpers for calling c for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*cstr_len*
```
pub unsafe fn cstr_len(p: *u8) -> usize;
```

	Counts the bytes before the first NUL of a C string.

	Caller obligation: p must point at a NUL-terminated sequence of bytes, all readable up to and
	including the NUL.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
