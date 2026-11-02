zoril-local_mem(3)

# NAME

zoril-local_mem - Internal test fixture for memory allocation failure validation

# SYNOPSIS

*import* "local_mem.zrl";

```
pub struct ArenaHeader {
pub start: *u8,
pub offset: u64,
pub capacity: u64,
}
pub fn arena_init(capacity: u64) -> Box<ArenaHeader>;
```

# DESCRIPTION

The *local_mem* module provides internal test fixture for memory allocation failure validation for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*ArenaHeader*
```
pub struct ArenaHeader {
pub start: *u8,
pub offset: u64,
pub capacity: u64,
}
```

	Internal memory arena header used for allocator test fixtures.

*arena_init*
```
pub fn arena_init(capacity: u64) -> Box<ArenaHeader>;
```

	Initializes an arena header structure over a pre-allocated memory buffer.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*zoril_allocator_alloc*
```
pub unsafe fn zoril_allocator_alloc(arena: *mut ArenaHeader, size: u64) -> *u8;
```

	Bumps ARENA's offset and hands back the storage. unsafe because the header is a raw pointer it
	writes through, as in stdlib/mem.zrl (this fixture mirrors that module's primitive).

*zoril_allocator_realloc*
```
pub unsafe fn zoril_allocator_realloc(arena: *mut ArenaHeader, old_ptr: *u8, old_size: u64, new_size: u64) -> *u8;
```

	unsafe for the same reason as zoril\_allocator\_alloc: it writes the header and reads OLD\_PTR.

*arena_free*
```
pub unsafe fn arena_free(arena: *mut ArenaHeader);
```

	Caller obligation: arena must point to a live mapped ArenaHeader.

*memcpy*
```
pub unsafe fn memcpy(dest: *mut u8, src: *mut u8, n: u64);
```

	A byte-at-a-time copy between two raw pointers: the whole body is the
	unsafe interior, exactly as in the non-local mem.zrl.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
