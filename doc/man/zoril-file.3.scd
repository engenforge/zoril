zoril-file(3)

# NAME

zoril-file - File handle abstraction (File), OpenOptions, and file helpers

# SYNOPSIS

*import* "file.zrl";

```
pub struct OpenOptions {
/* private fields */
}
impl OpenOptions {
    pub fn new() -> OpenOptions;
    pub fn read(mut self: OpenOptions, read: bool) -> OpenOptions;
    pub fn write(mut self: OpenOptions, write: bool) -> OpenOptions;
    pub fn append(mut self: OpenOptions, append: bool) -> OpenOptions;
    pub fn truncate(mut self: OpenOptions, truncate: bool) -> OpenOptions;
    pub fn create(mut self: OpenOptions, create: bool) -> OpenOptions;
    pub fn create_new(mut self: OpenOptions, create_new: bool) -> OpenOptions;
    pub fn unix_mode(mut self: OpenOptions, mode: u64) -> OpenOptions;
    pub fn open(self: &OpenOptions, path: [u8]) -> Result<File, Error>;
}
impl File {
    pub fn options() -> OpenOptions;
    pub fn create(path: [u8]) -> Result<File, Error>;
    pub fn append(path: [u8]) -> Result<File, Error>;
}
pub fn read_to_end_sized<R: Read>(r: &mut R, initial_cap: u64, a: &Arena) -> Result<[u8], Error>;
pub fn read_to_end<R: Read>(r: &mut R, a: &Arena) -> Result<[u8], Error>;
pub fn read_file(path: [u8], a: &Arena) -> Result<[u8], Error>;
pub fn read_stdin(a: &Arena) -> Result<[u8], Error>;
pub fn write_file(path: [u8], data: [u8]) -> Result<(), Error>;
pub fn append_file(path: [u8], data: [u8]) -> Result<(), Error>;
```

# DESCRIPTION

The *file* module provides file handle abstraction (file), openoptions, and file helpers for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*OpenOptions*
```
pub struct OpenOptions {
/* private fields */
}
```

	Options and flags configuring how a File handle is opened.

*new*
```
pub fn new() -> OpenOptions;
```

	Creates a blank set of open options with default settings (read-only).

*read*
```
pub fn read(mut self: OpenOptions, read: bool) -> OpenOptions;
```

	Configures whether the file will be opened with read access.

*write*
```
pub fn write(mut self: OpenOptions, write: bool) -> OpenOptions;
```

	Configures whether the file will be opened with write access.

*append*
```
pub fn append(mut self: OpenOptions, append: bool) -> OpenOptions;
```

	Configures whether writes will append to the end of the file.

*truncate*
```
pub fn truncate(mut self: OpenOptions, truncate: bool) -> OpenOptions;
```

	Configures whether opening an existing file truncates its length to zero.

*create*
```
pub fn create(mut self: OpenOptions, create: bool) -> OpenOptions;
```

	Configures whether a new file will be created if it does not already exist.

*create_new*
```
pub fn create_new(mut self: OpenOptions, create_new: bool) -> OpenOptions;
```

	Configures whether a new file must be created, failing if it already exists.

*unix_mode*
```
pub fn unix_mode(mut self: OpenOptions, mode: u64) -> OpenOptions;
```

	Sets the permission bits (mode) applied when a new file is created.

*open*
```
pub fn open(self: &OpenOptions, path: [u8]) -> Result<File, Error>;
```

	Opens the file at path with the configured options.

*options*
```
pub fn options() -> OpenOptions;
```

	Returns a blank OpenOptions instance for configuring file open options.

*create*
```
pub fn create(path: [u8]) -> Result<File, Error>;
```

	Creates or truncates a file at path for writing with default permissions (0o644).

*append*
```
pub fn append(path: [u8]) -> Result<File, Error>;
```

	Opens a file at path in append-only write mode, creating it if needed.

*read_to_end_sized*
```
pub fn read_to_end_sized<R: Read>(r: &mut R, initial_cap: u64, a: &Arena) -> Result<[u8], Error>;
```

	Reads r until end of input into a buffer grown in the arena. initial\_cap sizes
	the first allocation; 0 picks a default. The bytes are a slice of the arena, so the
	borrow checker ties the result to the &Arena it was read through.

*read_to_end*
```
pub fn read_to_end<R: Read>(r: &mut R, a: &Arena) -> Result<[u8], Error>;
```

	Reads all remaining bytes from reader r into a newly allocated byte slice in arena a.

*read_file*
```
pub fn read_file(path: [u8], a: &Arena) -> Result<[u8], Error>;
```

	Opens and reads the entire contents of the file at path into a byte slice allocated in arena a.

*read_stdin*
```
pub fn read_stdin(a: &Arena) -> Result<[u8], Error>;
```

	Reads all available data from standard input into a byte slice allocated in arena a.

*write_file*
```
pub fn write_file(path: [u8], data: [u8]) -> Result<(), Error>;
```

	Writes the entire byte buffer data to the file at path, creating or truncating it.

*append_file*
```
pub fn append_file(path: [u8], data: [u8]) -> Result<(), Error>;
```

	Appends the entire byte buffer data to the file at path, creating it if needed.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*read_to_end_sized_raw*
```
pub unsafe fn read_to_end_sized_raw<R: Read>(r: &mut R, initial_cap: u64, arena: *mut ArenaHeader) -> Result<[u8], Error>;
```

	Reads all bytes from reader r with an initial buffer hint.

	Caller obligation: arena must be valid and initialized.

*read_to_end_raw*
```
pub unsafe fn read_to_end_raw<R: Read>(r: &mut R, arena: *mut ArenaHeader) -> Result<[u8], Error>;
```

	Reads all bytes from reader r using a raw arena header.

	Caller obligation: arena must be valid and initialized.

*read_file_raw*
```
pub unsafe fn read_file_raw(path: [u8], arena: *mut ArenaHeader) -> Result<[u8], Error>;
```

	Reads the entire contents of a file using a raw arena header.

	Caller obligation: arena must be valid and path must contain no interior NUL bytes.

*read_stdin_raw*
```
pub unsafe fn read_stdin_raw(arena: *mut ArenaHeader) -> Result<[u8], Error>;
```

	Reads all data from standard input using a raw arena header.

	Caller obligation: arena must be valid and initialized.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
