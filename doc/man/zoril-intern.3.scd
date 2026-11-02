zoril-intern(3)

# NAME

zoril-intern - Arena-backed string deduplication and interning table (InternTable)

# SYNOPSIS

*import* "intern.zrl";

```
pub struct InternEntry {
/* private fields */
}
pub struct InternTable {
/* private fields */
}
impl InternTable {
    pub fn new(a: &Arena) -> &mut InternTable;
    pub fn hash(s: [u8]) -> u64;
    pub fn intern(self: &mut InternTable, buf: [u8]) -> u32;
    pub fn lookup(self: &InternTable, id: u32) -> [u8];
}
```

# DESCRIPTION

The *intern* module provides arena-backed string deduplication and interning table (interntable) for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*InternEntry*
```
pub struct InternEntry {
/* private fields */
}
```

	Storage node representing an interned string with its hash and byte slice.

*InternTable*
```
pub struct InternTable {
/* private fields */
}
```

	Arena-backed string interning table that deduplicates strings and maps them to unique 32-bit IDs.

*new*
```
pub fn new(a: &Arena) -> &mut InternTable;
```

	Constructs an empty string interning table allocated in arena a.

	Safe: the returned &mut InternTable borrows the arena, so resetting or destroying the
	arena while the table is live is a compile error.

*hash*
```
pub fn hash(s: [u8]) -> u64;
```

	Computes the 64-bit hash of string buffer buf.

*intern*
```
pub fn intern(self: &mut InternTable, buf: [u8]) -> u32;
```

	Interns a string slice, returning its unique 32-bit integer identifier.

*lookup*
```
pub fn lookup(self: &InternTable, id: u32) -> [u8];
```

	Retrieves the original interned string slice corresponding to 32-bit identifier id.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*new_raw*
```
pub unsafe fn new_raw(arena: *mut ArenaHeader) -> &mut InternTable;
```

	Constructs an intern table using a raw arena header.

	Caller obligation: arena must be valid and initialized.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
