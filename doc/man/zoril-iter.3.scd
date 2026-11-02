zoril-iter(3)

# NAME

zoril-iter - Functional iteration traits and combinators (Iterator, range)

# SYNOPSIS

*import* "iter.zrl";

```
pub trait Iterator {
    type Item;
    fn next(self: &mut Self) -> Option<Self::Item>;
    fn map<U>(self: Self, f: fn(Self::Item) -> U) -> Map<Self, U>;
    fn filter(self: Self, keep: fn(Self::Item) -> bool) -> Filter<Self>;
    fn fold<A>(self: Self, init: A, f: fn(A, Self::Item) -> A) -> A;
    fn collect(self: Self) -> Vec<Self::Item>;
}
pub struct VecIter<T> {
pub vec: &Vec<T>,
pub index: usize,
}
pub struct HashMapIter<K, V> {
pub map: &HashMap<K, V>,
pub slot: usize,
}
pub struct Range {
pub next_value: usize,
pub end: usize,
}
pub struct Map<I, U> {
pub inner: I,
pub f: fn(I::Item) -> U,
}
pub struct Filter<I> {
pub inner: I,
pub keep: fn(I::Item) -> bool,
}
impl<T> Iterator for VecIter<T> {
    pub fn next(self: &mut VecIter<T>) -> Option<&T>;
}
impl<T> Vec<T> {
    pub fn iter(self: &Vec<T>) -> VecIter<T>;
}
impl<K, V> Iterator for HashMapIter<K, V> {
    pub fn next(self: &mut HashMapIter<K, V>) -> Option<(&K, &V)>;
}
impl<K, V> HashMap<K, V> {
    pub fn iter(self: &HashMap<K, V>) -> HashMapIter<K, V>;
}
impl Iterator for Range {
    pub fn next(self: &mut Range) -> Option<usize>;
}
impl<I: Iterator, U> Iterator for Map<I, U> {
    pub fn next(self: &mut Map<I, U>) -> Option<U>;
}
impl<I: Iterator> Iterator for Filter<I> {
    pub fn next(self: &mut Filter<I>) -> Option<I::Item>;
}
pub fn range(start: usize, end: usize) -> Range;
```

# DESCRIPTION

The *iter* module provides functional iteration traits and combinators (iterator, range) for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*Iterator*
```
pub trait Iterator {
    type Item;
    fn next(self: &mut Self) -> Option<Self::Item>;
    fn map<U>(self: Self, f: fn(Self::Item) -> U) -> Map<Self, U>;
    fn filter(self: Self, keep: fn(Self::Item) -> bool) -> Filter<Self>;
    fn fold<A>(self: Self, init: A, f: fn(A, Self::Item) -> A) -> A;
    fn collect(self: Self) -> Vec<Self::Item>;
}
```

	Trait for sequential traversal over collections and generators.

*next*
```
fn next(self: &mut Self) -> Option<Self::Item>;
```

	Advances the iterator and returns the next element, or None when finished.

*map*
```
fn map<U>(self: Self, f: fn(Self::Item) -> U) -> Map<Self, U>;
```

	Returns an iterator adapter that applies f to each element.

*filter*
```
fn filter(self: Self, keep: fn(Self::Item) -> bool) -> Filter<Self>;
```

	Returns an iterator adapter that yields only elements matching predicate keep.

*fold*
```
fn fold<A>(self: Self, init: A, f: fn(A, Self::Item) -> A) -> A;
```

	Folds all elements into an accumulator using function f starting from init.

*collect*
```
fn collect(self: Self) -> Vec<Self::Item>;
```

	Consumes the iterator, collecting all elements into a new heap-allocated Vec.

*VecIter*
```
pub struct VecIter<T> {
pub vec: &Vec<T>,
pub index: usize,
}
```

	Iterator yielding shared references to elements in a Vec.

*next*
```
pub fn next(self: &mut VecIter<T>) -> Option<&T>;
```

	Yields a reference to the next element in the vector.

*iter*
```
pub fn iter(self: &Vec<T>) -> VecIter<T>;
```

	Returns an iterator over elements in the collection.

*HashMapIter*
```
pub struct HashMapIter<K, V> {
pub map: &HashMap<K, V>,
pub slot: usize,
}
```

	Iterator yielding key-value pairs from a HashMap.

*next*
```
pub fn next(self: &mut HashMapIter<K, V>) -> Option<(&K, &V)>;
```

	Yields the next (&K, &V) pair from the hash map.

*iter*
```
pub fn iter(self: &HashMap<K, V>) -> HashMapIter<K, V>;
```

	Returns an iterator over elements in the collection.

*Range*
```
pub struct Range {
pub next_value: usize,
pub end: usize,
}
```

	Half-open integer range iterator [start, end).

*next*
```
pub fn next(self: &mut Range) -> Option<usize>;
```

	Yields the next integer in the range.

*range*
```
pub fn range(start: usize, end: usize) -> Range;
```

	Constructs a Range iterator from start up to (excluding) end.

*Map*
```
pub struct Map<I, U> {
pub inner: I,
pub f: fn(I::Item) -> U,
}
```

	Iterator adapter that maps values using a function.

*next*
```
pub fn next(self: &mut Map<I, U>) -> Option<U>;
```

	Yields the next mapped element.

*Filter*
```
pub struct Filter<I> {
pub inner: I,
pub keep: fn(I::Item) -> bool,
}
```

	Iterator adapter that filters values using a predicate function.

	The iterator v.filter(keep) returns: the items of the inner iterator for which keep(item)
	is true. Items are passed to keep by value, so they must be copyable (references and
	primitives are).

*next*
```
pub fn next(self: &mut Filter<I>) -> Option<I::Item>;
```

	Yields the next element that satisfies the predicate.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
