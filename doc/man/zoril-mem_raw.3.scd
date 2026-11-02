zoril-mem_raw(3)

# NAME

zoril-mem_raw - Low-level raw memory mapping, bump primitives, and heap allocation

# SYNOPSIS

*import* "mem_raw.zrl";

```
pub struct ArenaHeader {
pub start: *mut u8,
pub offset: u64,
pub capacity: u64,
pub generation: u64,
}
pub const ARENA_HEADER_SIZE: u64 = 64;
pub const ARENA_POISON: i32 = 165;
pub extern fn memcpy(dest: *mut u8, src: *u8, size: u64);
pub extern fn memset(dest: *mut u8, value: i32, size: u64);
```

# DESCRIPTION

The *mem_raw* module provides low-level raw memory mapping, bump primitives, and heap allocation for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*memcpy*
```
pub extern fn memcpy(dest: *mut u8, src: *u8, size: u64);
```

	Caller obligation: dest and src must point to valid memory of at least size bytes; regions must not overlap.

*memset*
```
pub extern fn memset(dest: *mut u8, value: i32, size: u64);
```

	Caller obligation: dest must point to valid writable memory of at least size bytes.

*ArenaHeader*
```
pub struct ArenaHeader {
pub start: *mut u8,
pub offset: u64,
pub capacity: u64,
pub generation: u64,
}
```

	Low-level memory header tracking arena offset, capacity, and backing mmap bounds.

*ARENA_HEADER_SIZE*
```
pub const ARENA_HEADER_SIZE: u64 = 64;
```

	Size in bytes of the ArenaHeader structure (64 bytes).

*ARENA_POISON*
```
pub const ARENA_POISON: i32 = 165;
```

	Poison byte pattern written over freed memory pages in debug mode.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*arena_init*
```
pub unsafe fn arena_init(capacity: u64) -> *mut ArenaHeader;
```

	Allocates an arena mapping, returning a raw pointer to ArenaHeader.
	Traps if mmap fails.

*arena_init_result*
```
pub unsafe fn arena_init_result(capacity: u64) -> Result<*mut ArenaHeader, Error>;
```

	Allocates an arena mapping, returning Result<\*mut ArenaHeader, Error>.

*arena_free*
```
pub unsafe fn arena_free(arena: *mut ArenaHeader);
```

	Caller obligation: arena must point to a live, mapped ArenaHeader.

*arena_reset*
```
pub unsafe fn arena_reset(arena: *mut ArenaHeader, offset: u64);
```

	Caller obligation: arena must point to a live ArenaHeader, and offset must not exceed capacity.

*zoril_allocator_alloc*
```
pub unsafe fn zoril_allocator_alloc(arena: *mut ArenaHeader, size: u64) -> *mut u8;
```

	Caller obligation: arena must be null (global heap) or point to a valid ArenaHeader.

*zoril_allocator_realloc*
```
pub unsafe fn zoril_allocator_realloc(arena: *mut ArenaHeader, old_ptr: *u8, old_size: u64, new_size: u64) -> *u8;
```

	Caller obligation: arena must be valid, and old\_ptr must have been allocated in arena with old\_size.

*zoril_allocator_free*
```
pub unsafe fn zoril_allocator_free(arena: *mut ArenaHeader, ptr: *u8, size: u64);
```

	Caller obligation: arena must be null or a valid ArenaHeader matching ptr's allocation.

*heap_alloc*
```
pub unsafe fn heap_alloc(size: u64) -> *mut u8;
```

	Caller obligation: size bytes must be released by heap\_free with identical size when no longer needed.

*heap_free*
```
pub unsafe fn heap_free(ptr: *u8, size: u64);
```

	Caller obligation: ptr must have been returned by heap\_alloc with exact size.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
