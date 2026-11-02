zoril-core(3)

# NAME

zoril-core - Fundamental sum types (Option, Result) and standard traits

# SYNOPSIS

*import* "core.zrl";

```
pub enum Option<T> {
None,
Some(T),
}
pub enum Result<T, E> {
Ok(T),
Err(E),
}
pub trait Eq {
    fn eq(self: &Self, other: &Self) -> bool;
}
pub trait Clone {
    fn clone(self: &Self) -> Self;
}
pub trait Copy {
}
pub trait Hash {
    fn hash(self: &Self) -> u64;
}
pub trait Error {
    fn message(self: &Self) -> [u8];
}
pub trait ErrorMessage {
    fn error_message(self: &Self) -> [u8];
}
impl<T> Option<T> {
    pub fn is_some(self: &Option<T>) -> bool;
    pub fn is_none(self: &Option<T>) -> bool;
    pub fn unwrap(self: Option<T>) -> T;
    pub fn expect(self: Option<T>, msg: [u8]) -> T;
    pub fn take(self: &mut Option<T>) -> Option<T>;
    pub fn get_ref(self: &Option<T>) -> &T;
    pub fn get_mut(self: &mut Option<T>) -> &mut T;
}
impl<T, E> Result<T, E> {
    pub fn is_ok(self: &Result<T, E>) -> bool;
    pub fn is_err(self: &Result<T, E>) -> bool;
    pub fn ok(self: Result<T, E>) -> Option<T>;
    pub fn unwrap(self: Result<T, E>) -> T;
    pub fn err(self: Result<T, E>) -> Option<E>;
    pub fn map<U>(self: Result<T, E>, f: fn(T) -> U) -> Result<U, E>;
    pub fn map_err<F>(self: Result<T, E>, f: fn(E) -> F) -> Result<T, F>;
}
impl<T, E: ErrorMessage> Result<T, E> {
    pub fn expect(self: Result<T, E>, msg: [u8]) -> T;
}
impl Error for i32 {
    pub fn message(self: &i32) -> [u8];
}
impl ErrorMessage for i32 {
    pub fn error_message(self: &i32) -> [u8];
}
```

# DESCRIPTION

The *core* module provides fundamental sum types (option, result) and standard traits for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*Option*
```
pub enum Option<T> {
None,
Some(T),
}
```

	Sum type representing an optional value: either Some(T) or None.

*is_some*
```
pub fn is_some(self: &Option<T>) -> bool;
```

	Returns true if the option contains a Some value.

*is_none*
```
pub fn is_none(self: &Option<T>) -> bool;
```

	Returns true if the option is None.

*unwrap*
```
pub fn unwrap(self: Option<T>) -> T;
```

	Extracts the contained value, panicking if the option is None.

*expect*
```
pub fn expect(self: Option<T>, msg: [u8]) -> T;
```

	Extracts the contained value, panicking with msg if the option is None.

*take*
```
pub fn take(self: &mut Option<T>) -> Option<T>;
```

	Takes the value out of the option, leaving None in its place.

*get_ref*
```
pub fn get_ref(self: &Option<T>) -> &T;
```

	Returns an immutable reference to the contained value, panicking if None.

*get_mut*
```
pub fn get_mut(self: &mut Option<T>) -> &mut T;
```

	Returns a mutable reference to the contained value, panicking if None.

*Result*
```
pub enum Result<T, E> {
Ok(T),
Err(E),
}
```

	Sum type representing success (Ok(T)) or failure (Err(E)).

*is_ok*
```
pub fn is_ok(self: &Result<T, E>) -> bool;
```

	Returns true if the result is Ok.

*is_err*
```
pub fn is_err(self: &Result<T, E>) -> bool;
```

	Returns true if the result is Err.

*ok*
```
pub fn ok(self: Result<T, E>) -> Option<T>;
```

	Converts from Result<T, E> to Option<T>, discarding the error if any.

*unwrap*
```
pub fn unwrap(self: Result<T, E>) -> T;
```

	Extracts the contained Ok value, panicking if the result is Err.

*err*
```
pub fn err(self: Result<T, E>) -> Option<E>;
```

	Converts from Result<T, E> to Option<E>, discarding the success value if any.

*map*
```
pub fn map<U>(self: Result<T, E>, f: fn(T) -> U) -> Result<U, E>;
```

	Applies function f to the contained Ok value, leaving Err untouched.

*map_err*
```
pub fn map_err<F>(self: Result<T, E>, f: fn(E) -> F) -> Result<T, F>;
```

	Applies function f to the contained Err value, leaving Ok untouched.

*Eq*
```
pub trait Eq {
    fn eq(self: &Self, other: &Self) -> bool;
}
```

	Trait for types supporting equality comparisons.

	Equality that is an equivalence relation: reflexive, symmetric and
	transitive. Implementations for the primitive types and Option are in cmp.zrl.

*eq*
```
fn eq(self: &Self, other: &Self) -> bool;
```

	Returns true if self and other are equal.

*Clone*
```
pub trait Clone {
    fn clone(self: &Self) -> Self;
}
```

	Trait for types supporting explicit deep duplication.

	Explicit duplication. A clone owns its own copy of everything the original
	owns (a cloned String gets its own buffer). Implementations for the primitive
	types, Option, Vec and String are in clone.zrl; #[derive(Clone)] writes one
	for a struct whose fields all implement Clone.

*clone*
```
fn clone(self: &Self) -> Self;
```

	Creates an explicit duplicate copy of the value.

*Copy*
```
pub trait Copy {
}
```

	Marker trait indicating that values of this type can be copied bitwise.

	Implicit, bitwise duplication on assignment and argument passing. Copy is
	structural: a type is Copy exactly when it owns no value that implements
	Drop, so a T: Copy bound needs no impl, and impl Copy for T is rejected
	for a type that is not.

*Hash*
```
pub trait Hash {
    fn hash(self: &Self) -> u64;
}
```

	Trait for types that can be hashed into a 64-bit integer.

*hash*
```
fn hash(self: &Self) -> u64;
```

	Computes the 64-bit hash of the value.

*Error*
```
pub trait Error {
    fn message(self: &Self) -> [u8];
}
```

	Trait for types that represent an error condition.

*message*
```
fn message(self: &Self) -> [u8];
```

	Returns the descriptive error message as a byte slice.

*ErrorMessage*
```
pub trait ErrorMessage {
    fn error_message(self: &Self) -> [u8];
}
```

	Trait for types that provide a human-readable diagnostic error message.

*error_message*
```
fn error_message(self: &Self) -> [u8];
```

	Returns the formatted error message for diagnostic display.

*expect*
```
pub fn expect(self: Result<T, E>, msg: [u8]) -> T;
```

	Extracts the contained Ok value, panicking with msg and the formatted error detail if Err.

*message*
```
pub fn message(self: &i32) -> [u8];
```

	Returns the descriptive error message as a byte slice.

*error_message*
```
pub fn error_message(self: &i32) -> [u8];
```

	Returns the formatted error message for diagnostic display.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
