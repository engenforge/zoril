zoril-string(3)

# NAME

zoril-string - Growable byte strings (String) and inherent methods on [u8]

# SYNOPSIS

*import* "string.zrl";

```
pub struct String {
/* private fields */
}
impl String {
    pub fn new() -> String;
    pub fn new_in(a: &Arena) -> String;
    pub fn with_capacity(a: &Arena, cap: usize) -> String;
    pub fn push_u8(self: &mut String, c: u8);
    pub fn push_str(self: &mut String, s: [u8]);
    pub fn push_u64(self: &mut String, v: u64);
    pub fn push_i64(self: &mut String, v: i64);
    pub fn push_u64_hex(self: &mut String, v: u64);
    pub fn as_mut_vec(self: &mut String) -> &mut Vec<u8>;
    pub fn len(self: &String) -> usize;
    pub fn clear(self: &mut String);
    pub fn as_slice(self: &String) -> [u8];
    pub fn from_str(s: Str) -> String;
    pub fn push_s(self: &mut String, s: Str);
    pub fn as_str(self: &String) -> Option<Str>;
}
impl Write for String {
    pub fn write(self: &mut String, buf: [u8]) -> Result<usize, io::Error>;
}
impl [u8] {
    pub fn starts_with(self: &[u8], prefix: [u8]) -> bool;
    pub fn ends_with(self: &[u8], suffix: [u8]) -> bool;
    pub fn sub(self: &[u8], start: usize, len: usize) -> [u8];
    pub fn trim(self: &[u8]) -> [u8];
    pub fn split(self: &[u8], delim: u8, a: &Arena) -> Vec<[u8]>;
    pub fn find(self: &[u8], needle: [u8]) -> Option<usize>;
    pub fn find_byte(self: &[u8], ch: u8) -> Option<usize>;
    pub fn contains(self: &[u8], needle: [u8]) -> bool;
    pub fn parse_i64(self: &[u8]) -> Option<i64>;
    pub fn parse_u64(self: &[u8]) -> Option<u64>;
}
pub fn is_whitespace(c: u8) -> bool;
```

# DESCRIPTION

The *string* module provides growable byte strings (string) and inherent methods on [u8] for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*String*
```
pub struct String {
/* private fields */
}
```

	Growable byte string buffer with dynamic reallocation support.

*new*
```
pub fn new() -> String;
```

	Creates an empty String.

*new_in*
```
pub fn new_in(a: &Arena) -> String;
```

	Creates an empty String allocated in the specified arena.

	Safe: a String wraps a Vec, whose anchor field borrows the arena, so the
	borrow checker rejects destroying or resetting the arena while the String is live.

*with_capacity*
```
pub fn with_capacity(a: &Arena, cap: usize) -> String;
```

	Creates an empty String with pre-allocated capacity in arena a.

*push_u8*
```
pub fn push_u8(self: &mut String, c: u8);
```

	Appends a single byte to the string.

*push_str*
```
pub fn push_str(self: &mut String, s: [u8]);
```

	Appends a byte slice to the string.

*push_u64*
```
pub fn push_u64(self: &mut String, v: u64);
```

	Formats an unsigned 64-bit integer as decimal digits and appends it to the string.

*push_i64*
```
pub fn push_i64(self: &mut String, v: i64);
```

	Formats a signed 64-bit integer as decimal digits and appends it to the string.

*push_u64_hex*
```
pub fn push_u64_hex(self: &mut String, v: u64);
```

	Formats an unsigned 64-bit integer as hexadecimal digits and appends it to the string.

*as_mut_vec*
```
pub fn as_mut_vec(self: &mut String) -> &mut Vec<u8>;
```

	Returns a mutable reference to the underlying byte vector.

*len*
```
pub fn len(self: &String) -> usize;
```

	Returns the current length of the string in bytes.

*clear*
```
pub fn clear(self: &mut String);
```

	Truncates the string to zero length, preserving allocated capacity.

*as_slice*
```
pub fn as_slice(self: &String) -> [u8];
```

	Returns the string contents as an immutable byte slice.

*from_str*
```
pub fn from_str(s: Str) -> String;
```

	Converts a validated Str into an allocated String.

*push_s*
```
pub fn push_s(self: &mut String, s: Str);
```

	Appends a validated Str to the string.

*as_str*
```
pub fn as_str(self: &String) -> Option<Str>;
```

	Returns a validated Str view of the string if it contains valid UTF-8.

	The contents as a Str, or None if push\_u8/push\_str have left them
	invalid UTF-8.

*write*
```
pub fn write(self: &mut String, buf: [u8]) -> Result<usize, io::Error>;
```

	Implements Write trait for String, appending bytes to the buffer.

*is_whitespace*
```
pub fn is_whitespace(c: u8) -> bool;
```

	Returns true if byte c is an ASCII whitespace character (' ', '\t', '\n', '\r').

*starts_with*
```
pub fn starts_with(self: &[u8], prefix: [u8]) -> bool;
```

	Returns true if the byte slice begins with prefix.

*ends_with*
```
pub fn ends_with(self: &[u8], suffix: [u8]) -> bool;
```

	Returns true if the byte slice ends with suffix.

*sub*
```
pub fn sub(self: &[u8], start: usize, len: usize) -> [u8];
```

	Returns a subslice of length len starting at byte offset start.

*trim*
```
pub fn trim(self: &[u8]) -> [u8];
```

	Returns a slice with leading and trailing ASCII whitespace removed.

*split*
```
pub fn split(self: &[u8], delim: u8, a: &Arena) -> Vec<[u8]>;
```

	Splits a slice on delimiter byte delim, returning a Vec of sub-slices in arena a.

*find*
```
pub fn find(self: &[u8], needle: [u8]) -> Option<usize>;
```

	Returns the index of the first occurrence of needle in the slice, or None.

*find_byte*
```
pub fn find_byte(self: &[u8], ch: u8) -> Option<usize>;
```

	Returns the index of the first occurrence of byte ch in the slice, or None.

*contains*
```
pub fn contains(self: &[u8], needle: [u8]) -> bool;
```

	Returns true if the byte slice contains needle.

*parse_i64*
```
pub fn parse_i64(self: &[u8]) -> Option<i64>;
```

	Parses decimal ASCII digits into a signed 64-bit integer, or None on overflow or invalid character.

*parse_u64*
```
pub fn parse_u64(self: &[u8]) -> Option<u64>;
```

	Parses decimal ASCII digits into an unsigned 64-bit integer, or None on overflow or invalid character.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*new_in_raw*
```
pub unsafe fn new_in_raw(arena: *mut ArenaHeader) -> String;
```

	Creates an empty String using a raw arena header.

	Caller obligation: arena must be valid and initialized.

*with_capacity_in_raw*
```
pub unsafe fn with_capacity_in_raw(arena: *mut ArenaHeader, cap: usize) -> String;
```

	Creates an empty String with pre-allocated capacity using a raw arena header.

	Caller obligation: arena must be valid and initialized.

*raw_arena*
```
pub unsafe fn raw_arena(self: &String) -> *mut ArenaHeader;
```

	The arena this String allocates from (0 for the global heap).

*clone_in_raw*
```
pub unsafe fn clone_in_raw(self: &String, arena: *mut ArenaHeader) -> String;
```

	Clones a String using a raw arena header.

	Caller obligation: arena must be valid and initialized.

	The same-arena clone the Clone impl in clone.zrl needs: it holds only the raw header the
	String already allocates from, not an &Arena.

*split_raw*
```
pub unsafe fn split_raw(self: &[u8], delim: u8, arena: *mut ArenaHeader) -> Vec<[u8]>;
```

	Splits a slice using a raw arena header.

	Caller obligation: arena must be valid and initialized.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
