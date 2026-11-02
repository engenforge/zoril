zoril-os_unix(3)

# NAME

zoril-os_unix - POSIX-only operating-system interface: file locks and seeking

# SYNOPSIS

*import* "os_unix.zrl";

```
pub const LOCK_SH: u64 = 1;
pub const LOCK_EX: u64 = 2;
pub const LOCK_NB: u64 = 4;
pub const LOCK_UN: u64 = 8;
#[must_use]
pub fn lseek(fd: Fd, offset: i64, whence: u64) -> i64;
```

# DESCRIPTION

The *os_unix* module provides posix-only operating-system interface: file locks and seeking for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*LOCK_SH*
```
pub const LOCK_SH: u64 = 1;
```

	File lock flag: acquire a shared lock.

*LOCK_EX*
```
pub const LOCK_EX: u64 = 2;
```

	File lock flag: acquire an exclusive lock.

*LOCK_NB*
```
pub const LOCK_NB: u64 = 4;
```

	File lock flag: non-blocking lock request.

*LOCK_UN*
```
pub const LOCK_UN: u64 = 8;
```

	File lock flag: release an existing lock.

*lseek*
```
#[must_use]
pub fn lseek(fd: Fd, offset: i64, whence: u64) -> i64;
```

	Repositions the file offset of open descriptor fd according to offset and whence (SEEK\_SET, SEEK\_CUR, SEEK\_END).

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
