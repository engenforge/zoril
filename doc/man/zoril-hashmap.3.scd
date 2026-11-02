zoril-hashmap(3)

# NAME

zoril-hashmap - Open-addressing hash table with linear probing (HashMap)

# SYNOPSIS

*import* "hashmap.zrl";

```
pub struct Entry<K, V> {
pub key: K,
pub value: V,
pub occupied: bool,
}
pub struct HashMap<K, V> {
pub anchor: Option<&Arena>,
/* private fields */
}
impl<K: Hash + Eq, V> HashMap<K, V> {
    pub fn new(a: &Arena) -> HashMap<K, V>;
    pub fn insert(self: &mut HashMap<K, V>, key: K, value: V);
    pub fn len(self: &HashMap<K, V>) -> usize;
    pub fn cap(self: &HashMap<K, V>) -> usize;
    pub fn entry_at(self: &HashMap<K, V>, index: usize) -> &Entry<K, V>;
    pub fn get(self: &HashMap<K, V>, key: &K) -> Option<&V>;
    pub fn get_mut(self: &mut HashMap<K, V>, key: &K) -> Option<&mut V>;
    pub fn contains_key(self: &HashMap<K, V>, key: &K) -> bool;
    pub fn remove(self: &mut HashMap<K, V>, key: &K) -> Option<V>;
}
```

# DESCRIPTION

The *hashmap* module provides open-addressing hash table with linear probing (hashmap) for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*Entry*
```
pub struct Entry<K, V> {
pub key: K,
pub value: V,
pub occupied: bool,
}
```

	Key-value pair entry stored inside the hash map table.

*HashMap*
```
pub struct HashMap<K, V> {
pub anchor: Option<&Arena>,
/* private fields */
}
```

	Open-addressing hash table with linear probing and quadratic fallback.

*new*
```
pub fn new(a: &Arena) -> HashMap<K, V>;
```

	Safe: the map borrows the arena through anchor, so destroying or resetting the arena
	while the map is live is a compile error.

*insert*
```
pub fn insert(self: &mut HashMap<K, V>, key: K, value: V);
```

	Inserts a key-value pair into the map, returning the previous value if key was present.

*len*
```
pub fn len(self: &HashMap<K, V>) -> usize;
```

	The number of live entries, and the size of the entry table the iterator walks.

*cap*
```
pub fn cap(self: &HashMap<K, V>) -> usize;
```

	Returns the current number of allocated buckets in the hash table.

*entry_at*
```
pub fn entry_at(self: &HashMap<K, V>, index: usize) -> &Entry<K, V>;
```

	The entry table's slot at INDEX, for the iterator in iter.zrl. The table lives in the
	map's arena, so a slot reference is valid as long as the map is; occupied says whether
	its key and value are live. An index at or above cap is the iterator's own bug, so it
	traps rather than reading outside the table.

*get*
```
pub fn get(self: &HashMap<K, V>, key: &K) -> Option<&V>;
```

	Returns an immutable reference to the value associated with key, or None if absent.

*get_mut*
```
pub fn get_mut(self: &mut HashMap<K, V>, key: &K) -> Option<&mut V>;
```

	Returns a mutable reference to the value associated with key, or None if absent.

*contains_key*
```
pub fn contains_key(self: &HashMap<K, V>, key: &K) -> bool;
```

	Returns true if the map contains an entry for key.

*remove*
```
pub fn remove(self: &mut HashMap<K, V>, key: &K) -> Option<V>;
```

	Removes key and returns its value if present.
	Uses backward-shift deletion to preserve open-addressing probe chains.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*new_raw*
```
pub unsafe fn new_raw(arena: *mut ArenaHeader) -> HashMap<K, V>;
```

	Constructs an empty hash map allocated from a raw arena header.

	Caller obligation: arena must be valid and initialized.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
