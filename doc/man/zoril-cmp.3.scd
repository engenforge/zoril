zoril-cmp(3)

# NAME

zoril-cmp - Equivalence relations and slice search helpers (Eq, contains)

# SYNOPSIS

*import* "cmp.zrl";

```
impl Eq for bool {
    pub fn eq(self: &bool, other: &bool) -> bool;
}
impl Eq for u8 {
    pub fn eq(self: &u8, other: &u8) -> bool;
}
impl Eq for u16 {
    pub fn eq(self: &u16, other: &u16) -> bool;
}
impl Eq for u32 {
    pub fn eq(self: &u32, other: &u32) -> bool;
}
impl Eq for u64 {
    pub fn eq(self: &u64, other: &u64) -> bool;
}
impl Eq for i8 {
    pub fn eq(self: &i8, other: &i8) -> bool;
}
impl Eq for i16 {
    pub fn eq(self: &i16, other: &i16) -> bool;
}
impl Eq for i32 {
    pub fn eq(self: &i32, other: &i32) -> bool;
}
impl Eq for i64 {
    pub fn eq(self: &i64, other: &i64) -> bool;
}
impl Eq for usize {
    pub fn eq(self: &usize, other: &usize) -> bool;
}
impl Eq for isize {
    pub fn eq(self: &isize, other: &isize) -> bool;
}
impl<T: Eq> Eq for Option<T> {
    pub fn eq(self: &Option<T>, other: &Option<T>) -> bool;
}
pub fn contains<T: Eq>(items: [T], x: &T) -> bool;
```

# DESCRIPTION

The *cmp* module provides equivalence relations and slice search helpers (eq, contains) for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*eq*
```
pub fn eq(self: &bool, other: &bool) -> bool;
```

	Returns true if self and other are equal.

*eq*
```
pub fn eq(self: &u8, other: &u8) -> bool;
```

	Returns true if self and other are equal.

*eq*
```
pub fn eq(self: &u16, other: &u16) -> bool;
```

	Returns true if self and other are equal.

*eq*
```
pub fn eq(self: &u32, other: &u32) -> bool;
```

	Returns true if self and other are equal.

*eq*
```
pub fn eq(self: &u64, other: &u64) -> bool;
```

	Returns true if self and other are equal.

*eq*
```
pub fn eq(self: &i8, other: &i8) -> bool;
```

	Returns true if self and other are equal.

*eq*
```
pub fn eq(self: &i16, other: &i16) -> bool;
```

	Returns true if self and other are equal.

*eq*
```
pub fn eq(self: &i32, other: &i32) -> bool;
```

	Returns true if self and other are equal.

*eq*
```
pub fn eq(self: &i64, other: &i64) -> bool;
```

	Returns true if self and other are equal.

*eq*
```
pub fn eq(self: &usize, other: &usize) -> bool;
```

	Returns true if self and other are equal.

*eq*
```
pub fn eq(self: &isize, other: &isize) -> bool;
```

	Returns true if self and other are equal.

*eq*
```
pub fn eq(self: &Option<T>, other: &Option<T>) -> bool;
```

	Returns true if self and other are equal.

*contains*
```
pub fn contains<T: Eq>(items: [T], x: &T) -> bool;
```

	Returns true if the slice contains an element equal to val.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
