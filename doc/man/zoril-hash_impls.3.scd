zoril-hash_impls(3)

# NAME

zoril-hash_impls - Primitive type implementations of the Hash trait

# SYNOPSIS

*import* "hash_impls.zrl";

```
impl Hash for i32 {
    pub fn hash(self: &i32) -> u64;
}
impl Hash for u64 {
    pub fn hash(self: &u64) -> u64;
}
impl Hash for u32 {
    pub fn hash(self: &u32) -> u64;
}
```

# DESCRIPTION

The *hash_impls* module provides primitive type implementations of the hash trait for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*hash*
```
pub fn hash(self: &i32) -> u64;
```

	Computes the 64-bit FNV-1a hash value for the integer.

*hash*
```
pub fn hash(self: &u64) -> u64;
```

	Computes the 64-bit FNV-1a hash value for the integer.

*hash*
```
pub fn hash(self: &u32) -> u64;
```

	Computes the 64-bit FNV-1a hash value for the integer.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
