zoril-fsys(3)

# NAME

zoril-fsys - Filesystem operations, directory listing, and file locking

# SYNOPSIS

*import* "fsys.zrl";

```
pub struct FileLock {
/* private fields */
}
impl FileLock {
    pub fn fd(self: &FileLock) -> Fd;
}
impl Drop for FileLock {
    pub fn drop(self: FileLock);
}
pub fn unlink_path(path: [u8], a: &Arena) -> Result<(), Error>;
pub fn rename_path(from: [u8], to: [u8], a: &Arena) -> Result<(), Error>;
pub fn list_dir(path: [u8], a: &Arena) -> Result<Vec<[u8]>, Error>;
pub fn realtime_ns() -> i64;
pub fn path_is_executable(path: [u8], a: &Arena) -> bool;
pub fn exe_dir(a: &Arena) -> [u8];
pub fn env_var(name: [u8], a: &Arena) -> Option<[u8]>;
pub fn find_in_path(name: [u8], a: &Arena) -> Option<[u8]>;
pub fn make_dir_all(path: [u8], a: &Arena) -> Result<(), Error>;
pub fn acquire_file_lock(path: [u8]) -> Result<FileLock, Error>;
```

# DESCRIPTION

The *fsys* module provides filesystem operations, directory listing, and file locking for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*unlink_path*
```
pub fn unlink_path(path: [u8], a: &Arena) -> Result<(), Error>;
```

	Deletes the filesystem entry at path.

*rename_path*
```
pub fn rename_path(from: [u8], to: [u8], a: &Arena) -> Result<(), Error>;
```

	Renames or moves a filesystem entry from path from to path to.

*list_dir*
```
pub fn list_dir(path: [u8], a: &Arena) -> Result<Vec<[u8]>, Error>;
```

	Names (without "." and "..") of the entries in a directory, or an error if it cannot be read.

*realtime_ns*
```
pub fn realtime_ns() -> i64;
```

	Nanoseconds since the Unix epoch (CLOCK\_REALTIME), comparable with file mtimes.

*path_is_executable*
```
pub fn path_is_executable(path: [u8], a: &Arena) -> bool;
```

	Returns true if the file at path exists and has executable permissions for the current user.

*exe_dir*
```
pub fn exe_dir(a: &Arena) -> [u8];
```

	Directory of the running executable ("" if it cannot be determined).

*env_var*
```
pub fn env_var(name: [u8], a: &Arena) -> Option<[u8]>;
```

	Value of an environment variable, read from /proc/self/environ.

*find_in_path*
```
pub fn find_in_path(name: [u8], a: &Arena) -> Option<[u8]>;
```

	Resolves a bare command name by searching $PATH; names containing '/' are returned as given.

*make_dir_all*
```
pub fn make_dir_all(path: [u8], a: &Arena) -> Result<(), Error>;
```

	mkdir -p: create path and any missing parents (mode 0755).

*FileLock*
```
pub struct FileLock {
/* private fields */
}
```

	Advisory file lock guard providing RAII unlocking on drop.

*fd*
```
pub fn fd(self: &FileLock) -> Fd;
```

	Returns the file descriptor associated with this file lock.

*drop*
```
pub fn drop(self: FileLock);
```

	Releases the advisory file lock.

*acquire_file_lock*
```
pub fn acquire_file_lock(path: [u8]) -> Result<FileLock, Error>;
```

	Opens path (creating it if needed with mode 0644) and acquires an exclusive lock via flock.
	Returns a FileLock guard that unlocks and closes the descriptor on drop.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*unlink_path_raw*
```
pub unsafe fn unlink_path_raw(path: [u8], arena: *mut ArenaHeader) -> Result<(), Error>;
```

	Deletes the filesystem entry at path using a raw arena.

	Caller obligation: arena must be valid and path must contain no interior NUL bytes.

*rename_path_raw*
```
pub unsafe fn rename_path_raw(from: [u8], to: [u8], arena: *mut ArenaHeader) -> Result<(), Error>;
```

	Renames a filesystem entry using a raw arena.

	Caller obligation: arena must be valid and paths must contain no interior NUL bytes.

*list_dir_raw*
```
pub unsafe fn list_dir_raw(path: [u8], arena: *mut ArenaHeader) -> Result<Vec<[u8]>, Error>;
```

	Lists entries in a directory using a raw arena.

	Caller obligation: arena must be valid and path must contain no interior NUL bytes.

*path_is_executable_raw*
```
pub unsafe fn path_is_executable_raw(path: [u8], arena: *mut ArenaHeader) -> bool;
```

	Checks if path is executable using a raw arena.

	Caller obligation: arena must be valid and path must contain no interior NUL bytes.

*exe_dir_raw*
```
pub unsafe fn exe_dir_raw(arena: *mut ArenaHeader) -> [u8];
```

	Returns the directory containing the current executable.

	Caller obligation: arena must be valid and initialized.

*env_var_raw*
```
pub unsafe fn env_var_raw(name: [u8], arena: *mut ArenaHeader) -> Option<[u8]>;
```

	Reads an environment variable using a raw arena.

	Caller obligation: arena must be valid and name must contain no interior NUL bytes.

*find_in_path_raw*
```
pub unsafe fn find_in_path_raw(name: [u8], arena: *mut ArenaHeader) -> Option<[u8]>;
```

	Locates a binary in the system PATH using a raw arena.

	Caller obligation: arena must be valid and name must contain no interior NUL bytes.

*make_dir_all_raw*
```
pub unsafe fn make_dir_all_raw(path: [u8], arena: *mut ArenaHeader) -> Result<(), Error>;
```

	Recursively creates directories using a raw arena.

	Caller obligation: arena must be valid and path must contain no interior NUL bytes.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
