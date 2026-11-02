zoril-bytevec(3)

# NAME

zoril-bytevec - Internal bump-backed byte vector buffers (ByteVec)

# SYNOPSIS

*import* "bytevec.zrl";

```
pub struct ByteVec {
/* private fields */
}
impl ByteVec {
    pub fn new(a: &Arena) -> &mut ByteVec;
    pub fn push(self: &mut ByteVec, b: u8);
    pub fn push_slice(self: &mut ByteVec, s: [u8]);
    pub fn as_slice(self: &ByteVec) -> [u8];
    pub fn len(self: &ByteVec) -> usize;
    pub fn cap(self: &ByteVec) -> usize;
    pub fn as_ptr(self: &ByteVec) -> *u8;
    pub fn as_mut_ptr(self: &mut ByteVec) -> *mut u8;
}
```

# DESCRIPTION

The *bytevec* module provides internal bump-backed byte vector buffers (bytevec) for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*ByteVec*
```
pub struct ByteVec {
/* private fields */
}
```

	Internal growable byte vector backed by bump-allocated memory from an arena.

*new*
```
pub fn new(a: &Arena) -> &mut ByteVec;
```

	Safe: the returned &mut ByteVec borrows the arena, so resetting or destroying the
	arena while the ByteVec is live is a compile error.

*push*
```
pub fn push(self: &mut ByteVec, b: u8);
```

	Appends a single byte to the end of the byte vector.

*push_slice*
```
pub fn push_slice(self: &mut ByteVec, s: [u8]);
```

	Appends all bytes from slice to the byte vector.

*as_slice*
```
pub fn as_slice(self: &ByteVec) -> [u8];
```

	Returns the contents of the byte vector as an immutable byte slice.

*len*
```
pub fn len(self: &ByteVec) -> usize;
```

	Returns the number of bytes currently stored in the byte vector.

*cap*
```
pub fn cap(self: &ByteVec) -> usize;
```

	Returns the allocated byte capacity of the byte vector.

*as_ptr*
```
pub fn as_ptr(self: &ByteVec) -> *u8;
```

	As Vec::as\_ptr: reading the buffer's address is harmless, the fields are private so the
	address cannot be forged, and &mut self is what as\_mut\_ptr adds.

*as_mut_ptr*
```
pub fn as_mut_ptr(self: &mut ByteVec) -> *mut u8;
```

	Returns a raw mutable pointer to the beginning of the buffer.

	Caller obligation: caller must not read beyond len or write beyond cap.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*new_raw*
```
pub unsafe fn new_raw(arena: *mut ArenaHeader) -> &mut ByteVec;
```

	Constructs an empty ByteVec allocated from a raw arena header.

	Caller obligation: caller must ensure arena is valid and initialized.

	The internal escape hatch for a raw arena pointer: the canonical unsafe-inside /
	safe-outside constructor (unsafe\_policy.md §2). The result is not tied to the arena.

*push_range*
```
pub unsafe fn push_range(self: &mut ByteVec, ptr: *u8, start: usize, len: usize);
```

	Appends bytes from a raw pointer range [start, end) to the byte vector.

	Caller obligation: start and end must point to valid accessible memory.

*raw_arena*
```
pub unsafe fn raw_arena(self: &ByteVec) -> *mut ArenaHeader;
```

	The arena this buffer allocates from (0 for the global heap).

*set_len*
```
pub unsafe fn set_len(self: &mut ByteVec, n: usize);
```

	The length may only be set within the allocation (probe 164); growing goes through push.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
