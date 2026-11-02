zoril-unicode(3)

# NAME

zoril-unicode - Unicode scalar values (unicode)

# SYNOPSIS

*import* "unicode.zrl";

```
pub fn char_from_u32(n: u32) -> Option<char>;
```

# DESCRIPTION

The *unicode* module provides unicode scalar values (unicode) for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*char_from_u32*
```
pub fn char_from_u32(n: u32) -> Option<char>;
```

	A char from its Unicode scalar value, or None for a surrogate or a value above
	U+10FFFF. This is the checked counterpart of n as char, the cast that only
	unsafe code may write.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
