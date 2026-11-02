zoril-time(3)

# NAME

zoril-time - Monotonic clock and sleep

# SYNOPSIS

*import* "time.zrl";

```
pub fn monotonic_ns() -> i64;
pub fn sleep_ns(ns: i64);
```

# DESCRIPTION

The *time* module provides monotonic clock and sleep for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*monotonic_ns*
```
pub fn monotonic_ns() -> i64;
```

	Nanoseconds on a monotonic clock (CLOCK\_MONOTONIC) with an unspecified starting point. Only the
	difference between two readings means anything. It does not count time the system was suspended.

*sleep_ns*
```
pub fn sleep_ns(ns: i64);
```

	Blocks the calling thread for at least ns nanoseconds. A duration of zero or less returns at
	once. A sleep interrupted by a signal resumes for the time that remained.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
