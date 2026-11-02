zoril-clone(3)

# NAME

zoril-clone - Explicit deep cloning traits and implementations (Clone, Copy)

# SYNOPSIS

*import* "clone.zrl";

```
impl Clone for bool {
    pub fn clone(self: &bool) -> bool;
}
impl Clone for u8 {
    pub fn clone(self: &u8) -> u8;
}
impl Clone for u16 {
    pub fn clone(self: &u16) -> u16;
}
impl Clone for u32 {
    pub fn clone(self: &u32) -> u32;
}
impl Clone for u64 {
    pub fn clone(self: &u64) -> u64;
}
impl Clone for usize {
    pub fn clone(self: &usize) -> usize;
}
impl Clone for i8 {
    pub fn clone(self: &i8) -> i8;
}
impl Clone for i16 {
    pub fn clone(self: &i16) -> i16;
}
impl Clone for i32 {
    pub fn clone(self: &i32) -> i32;
}
impl Clone for i64 {
    pub fn clone(self: &i64) -> i64;
}
impl Clone for isize {
    pub fn clone(self: &isize) -> isize;
}
impl<T: Clone> Clone for Option<T> {
    pub fn clone(self: &Option<T>) -> Option<T>;
}
impl<T: Clone> Clone for [T] {
    pub fn clone(self: &[T]) -> [T];
}
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
pub fn clone(self: &bool) -> bool;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &u8) -> u8;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &u16) -> u16;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &u32) -> u32;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &u64) -> u64;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &usize) -> usize;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &i8) -> i8;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &i16) -> i16;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &i32) -> i32;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &i64) -> i64;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &isize) -> isize;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &Option<T>) -> Option<T>;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &[T]) -> [T];
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &Vec<T>) -> Vec<T>;
```

	Creates an explicit duplicate copy of the value.

*clone*
```
pub fn clone(self: &String) -> String;
```

	Creates an explicit duplicate copy of the value.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
