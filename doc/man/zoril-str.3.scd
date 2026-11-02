zoril-str(3)

# NAME

zoril-str - Validated UTF-8 string slices and character validation (Str)

# SYNOPSIS

*import* "str.zrl";

```
pub struct Str {
/* private fields */
}
impl Str {
    pub fn from_utf8(bytes: [u8]) -> Option<Str>;
    pub fn as_bytes(self: &Str) -> [u8];
    pub fn len(self: &Str) -> usize;
    pub fn is_empty(self: &Str) -> bool;
    pub fn char_count(self: &Str) -> usize;
    pub fn is_char_boundary(self: &Str, i: usize) -> bool;
    pub fn substr(self: &Str, start: usize, end: usize) -> Option<Str>;
    pub fn starts_with(self: &Str, prefix: [u8]) -> bool;
    pub fn ends_with(self: &Str, suffix: [u8]) -> bool;
    pub fn contains(self: &Str, needle: [u8]) -> bool;
    pub fn find(self: &Str, needle: [u8]) -> Option<usize>;
    pub fn trim(self: &Str) -> Str;
}
pub fn utf8_valid(bytes: [u8]) -> bool;
```

# DESCRIPTION

The *str* module provides validated utf-8 string slices and character validation (str) for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*Str*
```
pub struct Str {
/* private fields */
}
```

	Validated UTF-8 string slice wrapper guarantee-backed by utf8\_valid.

*utf8_valid*
```
pub fn utf8_valid(bytes: [u8]) -> bool;
```

	Validates whether bytes forms a well-formed UTF-8 byte sequence.

*from_utf8*
```
pub fn from_utf8(bytes: [u8]) -> Option<Str>;
```

	Validates bytes and returns Some(Str) if well-formed, or None if invalid UTF-8.

*as_bytes*
```
pub fn as_bytes(self: &Str) -> [u8];
```

	Returns the underlying byte slice.

*len*
```
pub fn len(self: &Str) -> usize;
```

	Returns the length of the string in bytes.

*is_empty*
```
pub fn is_empty(self: &Str) -> bool;
```

	Returns true if the string slice contains zero bytes.

*char_count*
```
pub fn char_count(self: &Str) -> usize;
```

	Returns the total number of Unicode code points in the string.

*is_char_boundary*
```
pub fn is_char_boundary(self: &Str, i: usize) -> bool;
```

	Returns true if byte index i lies on a valid UTF-8 code point boundary.

*substr*
```
pub fn substr(self: &Str, start: usize, end: usize) -> Option<Str>;
```

	Returns a substring slice spanning byte indices [start, end), or None if indices are invalid or not on code point boundaries.

*starts_with*
```
pub fn starts_with(self: &Str, prefix: [u8]) -> bool;
```

	Returns true if the string begins with prefix.

*ends_with*
```
pub fn ends_with(self: &Str, suffix: [u8]) -> bool;
```

	Returns true if the string ends with suffix.

*contains*
```
pub fn contains(self: &Str, needle: [u8]) -> bool;
```

	Returns true if needle occurs within the string.

*find*
```
pub fn find(self: &Str, needle: [u8]) -> Option<usize>;
```

	Returns the byte index of the first occurrence of needle, or None if not found.

*trim*
```
pub fn trim(self: &Str) -> Str;
```

	Returns a subslice with leading and trailing ASCII whitespace removed.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
