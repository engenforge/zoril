zoril-clone(3)

# NAME

zoril-clone - Explicit deep cloning traits and implementations (Clone, Copy)

# SYNOPSIS

*import* "clone.zrl";

```
impl<T: Clone> Clone for Vec<T> {
    pub fn clone(self: &Vec<T>) -> Vec<T>;
}
impl Clone for String {
    pub fn clone(self: &String) -> String;
}
```

# DESCRIPTION

The *clone* module provides explicit deep cloning traits and implementations (clone, copy) for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*clone*
```
pub fn clone(self: &Vec<T>) -> Vec<T>;
```

	Creates an explicit duplicate copy of the value.
	elements hold; it owns its own buffer and records only the arena self allocates from,
	which self holds as a borrow. It points into no storage self owns.

*clone*
```
pub fn clone(self: &String) -> String;
```

	Creates an explicit duplicate copy of the value.
	from, which self holds as a borrow.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
