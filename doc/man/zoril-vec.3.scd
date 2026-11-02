zoril-vec(3)

# NAME

zoril-vec - Growable generic arrays (Vec) with arena and allocator support

# SYNOPSIS

*import* "vec.zrl";

```
pub struct Vec<T> {
pub anchor: Option<&Arena>,
/* private fields */
}
impl<T> Vec<T> {
    pub fn new() -> Vec<T>;
    pub fn new_in(a: &Arena) -> Vec<T>;
    pub fn with_capacity(cap: usize) -> Vec<T>;
    pub fn with_capacity_in(a: &Arena, cap: usize) -> Vec<T>;
    pub fn clone_in(self: &Vec<T>, a: &Arena) -> Vec<T>;
    pub fn push(self: &mut Vec<T>, val: T);
    pub fn pop(self: &mut Vec<T>) -> Option<T>;
    pub fn get(self: &Vec<T>, index: usize) -> Option<&T>;
    pub fn get_mut(self: &mut Vec<T>, index: usize) -> Option<&mut T>;
    pub fn ensure_len(self: &mut Vec<T>, min_len: usize);
    pub fn resize(self: &mut Vec<T>, new_len: usize);
    pub fn set(self: &mut Vec<T>, index: usize, val: T);
    pub fn len(self: &Vec<T>) -> usize;
    pub fn cap(self: &Vec<T>) -> usize;
    pub fn as_ptr(self: &Vec<T>) -> *T;
    pub fn as_mut_ptr(self: &mut Vec<T>) -> *mut T;
    pub fn clear(self: &mut Vec<T>);
    pub fn as_slice(self: &Vec<T>) -> [T];
    pub fn as_mut_slice(self: &mut Vec<T>) -> [mut T];
    pub fn remove(self: &mut Vec<T>, index: usize) -> T;
    pub fn free(self: &mut Vec<T>);
    pub fn extend_from_slice(self: &mut Vec<T>, slice: [T]);
}
```

# DESCRIPTION

The *vec* module provides growable generic arrays (vec) with arena and allocator support for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*Vec*
```
pub struct Vec<T> {
pub anchor: Option<&Arena>,
/* private fields */
}
```

	Growable generic array with arena allocation or global allocator backing.

*new*
```
pub fn new() -> Vec<T>;
```

	Creates an empty Vec using the default allocator.

*new_in*
```
pub fn new_in(a: &Arena) -> Vec<T>;
```

	Creates an empty Vec allocated in arena a.

*with_capacity*
```
pub fn with_capacity(cap: usize) -> Vec<T>;
```

	Creates an empty Vec with the requested element capacity using the default allocator.

*with_capacity_in*
```
pub fn with_capacity_in(a: &Arena, cap: usize) -> Vec<T>;
```

	Creates an empty Vec with the requested element capacity allocated in arena a.

*clone_in*
```
pub fn clone_in(self: &Vec<T>, a: &Arena) -> Vec<T>;
```

	Clones all elements of the vector into a new Vec allocated in arena a.

*push*
```
pub fn push(self: &mut Vec<T>, val: T);
```

	Appends an element to the end of the vector, growing capacity if needed.

*pop*
```
pub fn pop(self: &mut Vec<T>) -> Option<T>;
```

	Removes and returns the last element of the vector, or None if empty.

*get*
```
pub fn get(self: &Vec<T>, index: usize) -> Option<&T>;
```

	Returns a shared reference to the element at index, or None if out of bounds.

*get_mut*
```
pub fn get_mut(self: &mut Vec<T>, index: usize) -> Option<&mut T>;
```

	Returns a mutable reference to the element at index, or None if out of bounds.

*ensure_len*
```
pub fn ensure_len(self: &mut Vec<T>, min_len: usize);
```

	Ensures the vector has at least min\_len elements, growing if necessary.

*resize*
```
pub fn resize(self: &mut Vec<T>, new_len: usize);
```

	Resizes the vector to new\_len elements, padding with zero values if growing.

*set*
```
pub fn set(self: &mut Vec<T>, index: usize, val: T);
```

	Replaces the element at index with val, panicking if out of bounds.

*len*
```
pub fn len(self: &Vec<T>) -> usize;
```

	Returns the number of elements in the vector.

*cap*
```
pub fn cap(self: &Vec<T>) -> usize;
```

	Returns the current allocated element capacity of the vector.

*as_ptr*
```
pub fn as_ptr(self: &Vec<T>) -> *T;
```

	The buffer's address, for the callers that do byte-level work on a Vec's own storage
	(the front end computes with raw offsets into span and comment tables). Reading it is
	harmless; what must not be forgeable from safe code is the fields themselves, so
	data/len/cap/raw are private and this is how a caller gets at the buffer.

*as_mut_ptr*
```
pub fn as_mut_ptr(self: &mut Vec<T>) -> *mut T;
```

	As as\_ptr, with the write access &mut self implies.

*clear*
```
pub fn clear(self: &mut Vec<T>);
```

	Removes all elements from the vector without deallocating backing storage.

*as_slice*
```
pub fn as_slice(self: &Vec<T>) -> [T];
```

	Returns the elements as an immutable slice.

*as_mut_slice*
```
pub fn as_mut_slice(self: &mut Vec<T>) -> [mut T];
```

	Returns the elements as a mutable slice.

*remove*
```
pub fn remove(self: &mut Vec<T>, index: usize) -> T;
```

	Removes and returns the element at index, shifting subsequent elements left.

*free*
```
pub fn free(self: &mut Vec<T>);
```

	Explicitly frees the vector's backing memory buffer.

*extend_from_slice*
```
pub fn extend_from_slice(self: &mut Vec<T>, slice: [T]);
```

	Appends all elements from a slice to the end of the vector.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*new_in_raw*
```
pub unsafe fn new_in_raw(arena: *mut ArenaHeader) -> Vec<T>;
```

	Creates an empty Vec using a raw arena header.

	Caller obligation: arena must be valid and initialized.

*with_capacity_in_raw*
```
pub unsafe fn with_capacity_in_raw(arena: *mut ArenaHeader, cap: usize) -> Vec<T>;
```

	Creates an empty Vec with capacity using a raw arena header.

	Caller obligation: arena must be valid and initialized.

*clone_in_raw*
```
pub unsafe fn clone_in_raw(self: &Vec<T>, arena: *mut ArenaHeader) -> Vec<T>;
```

	Clones a vector using a raw arena header.

	Caller obligation: arena must be valid and initialized.

*raw_arena*
```
pub unsafe fn raw_arena(self: &Vec<T>) -> *mut ArenaHeader;
```

	The arena this Vec allocates from (0 for the global heap), for the internals that build a
	scratch Vec in the same arena.

*set_len*
```
pub unsafe fn set_len(self: &mut Vec<T>, n: usize);
```

	The one way to set the length directly (set/push/resize cover the rest), and it keeps
	the invariant the private field exists for: a length above cap is the forged-length fault
	(probe 164), so it traps. Growing is what ensure\_len is for.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
