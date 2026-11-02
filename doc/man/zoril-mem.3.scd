zoril-mem(3)

# NAME

zoril-mem - Safe region-based arena memory management (Arena, ArenaMark)

# SYNOPSIS

*import* "mem.zrl";

```
pub struct ArenaMark {
/* private fields */
}
pub struct Arena {
/* private fields */
}
impl Arena {
    pub fn new(capacity: u64) -> Result<Arena, Error>;
    pub fn reset(self: &mut Arena);
    pub fn mark(self: &Arena) -> ArenaMark;
    pub fn reset_to(self: &mut Arena, mark: ArenaMark);
}
impl Drop for Arena {
    pub fn drop(self: Arena);
}
pub fn bounds_trap(msg: [u8]) -> never;
pub fn capacity_overflow() -> never;
pub fn size_of_n(count: usize, elem_size: usize) -> usize;
pub fn grow_cap(cap: usize) -> usize;
```

# DESCRIPTION

The *mem* module provides safe region-based arena memory management (arena, arenamark) for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*ArenaMark*
```
pub struct ArenaMark {
/* private fields */
}
```

	Opaque snapshot mark recording the allocation state of an arena.

*Arena*
```
pub struct Arena {
/* private fields */
}
```

	Region-based memory arena allocator that allocates memory linearly and frees all objects in bulk.

*new*
```
pub fn new(capacity: u64) -> Result<Arena, Error>;
```

	Creates a new memory arena with the requested byte capacity using mmap.

*reset*
```
pub fn reset(self: &mut Arena);
```

	Resets the arena allocation offset back to zero, invalidating all previously allocated objects.

*mark*
```
pub fn mark(self: &Arena) -> ArenaMark;
```

	Returns a mark recording the current allocation position in the arena.

*reset_to*
```
pub fn reset_to(self: &mut Arena, mark: ArenaMark);
```

	Rewinds the arena allocation offset back to mark, freeing objects allocated after that mark.

	Rewinds the arena to mark.offset within the current generation. Pre-mark allocations
	remain valid across reset\_to unless mutated after mark. If nested marks were taken,
	rewinding to an earlier mark leaves later marks usable only up to their recorded offset;
	allocations made after rewinding have later borrow epochs and cannot be freed by stale
	inner marks while live.

*drop*
```
pub fn drop(self: Arena);
```

	Releases the arena's memory back to the operating system.

*bounds_trap*
```
pub fn bounds_trap(msg: [u8]) -> never;
```

	Internal panic handler triggered on an out-of-bounds memory access.

*capacity_overflow*
```
pub fn capacity_overflow() -> never;
```

	Internal panic handler triggered when an allocation size exceeds capacity.

*size_of_n*
```
pub fn size_of_n(count: usize, elem_size: usize) -> usize;
```

	Computes count \* element\_size with integer overflow trapping.

*grow_cap*
```
pub fn grow_cap(cap: usize) -> usize;
```

	Computes geometric capacity growth for dynamically-resized buffers.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*arena_raw*
```
pub unsafe fn arena_raw(a: &Arena) -> *mut ArenaHeader;
```

	Extracts the raw arena header pointer from an Arena.

	Caller obligation: caller must ensure arena lives as long as the returned header pointer.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
