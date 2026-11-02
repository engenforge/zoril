zoril-io(3)

# NAME

zoril-io - Direct kernel I/O, typed file descriptors (Fd), and streaming traits

# SYNOPSIS

*import* "io.zrl";

```
pub enum ErrorKind {
NotFound,
PermissionDenied,
AlreadyExists,
Interrupted,
InvalidInput,
WouldBlock,
BrokenPipe,
Other,
}
pub struct Error {
pub errno: i32,
}
pub struct Fd {
/* private fields */
}
pub trait Read {
    fn read(self: &mut Self, buf: [mut u8]) -> Result<usize, Error>;
}
pub trait Write {
    fn write(self: &mut Self, buf: [u8]) -> Result<usize, Error>;
}
pub struct File {
/* private fields */
}
pub struct Stdin {
}
pub struct Stdout {
}
pub struct Stderr {
}
pub struct SliceReader {
pub data: [u8],
pub pos: usize,
}
impl Error {
    pub fn from_linux_errno(errno: i32) -> Error;
    pub fn linux_errno(self: &Error) -> i32;
    pub fn kind(self: &Error) -> ErrorKind;
    pub fn linux_name(self: &Error) -> [u8];
    pub fn detail(self: &Error) -> [u8];
}
impl core::Error for Error {
    pub fn message(self: &Error) -> [u8];
}
impl core::ErrorMessage for Error {
    pub fn error_message(self: &Error) -> [u8];
}
impl Eq for Fd {
    pub fn eq(self: &Fd, other: &Fd) -> bool;
}
impl File {
    pub fn fd(self: &File) -> Fd;
    pub fn close(mut self: File) -> Result<(), Error>;
}
impl Read for File {
    pub fn read(self: &mut File, buf: [mut u8]) -> Result<usize, Error>;
}
impl Write for File {
    pub fn write(self: &mut File, buf: [u8]) -> Result<usize, Error>;
}
impl Drop for File {
    pub fn drop(self: File);
}
impl Read for Fd {
    pub fn read(self: &mut Fd, buf: [mut u8]) -> Result<usize, Error>;
}
impl Write for Fd {
    pub fn write(self: &mut Fd, buf: [u8]) -> Result<usize, Error>;
}
impl Stdin {
    pub fn new() -> Stdin;
}
impl Stdout {
    pub fn new() -> Stdout;
}
impl Stderr {
    pub fn new() -> Stderr;
}
impl Read for Stdin {
    pub fn read(self: &mut Stdin, buf: [mut u8]) -> Result<usize, Error>;
}
impl Write for Stdout {
    pub fn write(self: &mut Stdout, buf: [u8]) -> Result<usize, Error>;
}
impl Write for Stderr {
    pub fn write(self: &mut Stderr, buf: [u8]) -> Result<usize, Error>;
}
impl SliceReader {
    pub fn new(data: [u8]) -> SliceReader;
}
impl Read for SliceReader {
    pub fn read(self: &mut SliceReader, buf: [mut u8]) -> Result<usize, Error>;
}
pub fn stdout() -> Fd;
pub fn stderr() -> Fd;
pub fn stdin() -> Fd;
pub fn write(fd: Fd, buf: [u8]) -> Result<usize, Error>;
pub fn read(fd: Fd, buf: [mut u8]) -> Result<usize, Error>;
pub fn close(fd: Fd) -> Result<(), Error>;
pub fn exit(code: i32) -> never;
pub fn print(s: [u8]);
pub fn println(s: [u8]);
pub fn eprint(s: [u8]);
pub fn eprintln(s: [u8]);
pub fn write_all_fd(fd: Fd, buf: [u8]) -> Result<(), Error>;
pub fn write_all<W: Write>(w: &mut W, buf: [u8]) -> Result<(), Error>;
```

# DESCRIPTION

The *io* module provides direct kernel i/o, typed file descriptors (fd), and streaming traits for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*ErrorKind*
```
pub enum ErrorKind {
NotFound,
PermissionDenied,
AlreadyExists,
Interrupted,
InvalidInput,
WouldBlock,
BrokenPipe,
Other,
}
```

	A portable category of I/O error. Match with a wildcard arm: more categories may be added.

*Error*
```
pub struct Error {
pub errno: i32,
}
```

	Standard I/O error type wrapping an operating-system errno value.

*from_linux_errno*
```
pub fn from_linux_errno(errno: i32) -> Error;
```

	Constructs an Error from a Linux errno number. The number is a Linux fact: other systems
	number their errors differently, so portable code reads kind() instead.

*linux_errno*
```
pub fn linux_errno(self: &Error) -> i32;
```

	Returns the Linux errno number.

*kind*
```
pub fn kind(self: &Error) -> ErrorKind;
```

	Returns the portable category of the error; ErrorKind.Other covers every code without one.

*linux_name*
```
pub fn linux_name(self: &Error) -> [u8];
```

	Returns the symbolic Linux name of the error code (e.g., ENOENT, EACCES).

*detail*
```
pub fn detail(self: &Error) -> [u8];
```

	Returns the descriptive text explanation of the error code.

*message*
```
pub fn message(self: &Error) -> [u8];
```

	Returns the descriptive error message as a byte slice.

*error_message*
```
pub fn error_message(self: &Error) -> [u8];
```

	Returns the formatted error message for diagnostic display.

*Fd*
```
pub struct Fd {
/* private fields */
}
```

	A typed operating-system file descriptor wrapping a raw integer handle.

	Forging an arbitrary descriptor requires unsafe with Fd.from\_unix\_raw(...) because its
	inner raw field is private. Safe code obtains valid descriptors from open, File,
	or standard streams (stdin(), stdout(), stderr()).

*eq*
```
pub fn eq(self: &Fd, other: &Fd) -> bool;
```

	Returns true if both Fd handles wrap the same underlying integer descriptor.

*stdout*
```
pub fn stdout() -> Fd;
```

	Returns a typed file descriptor (Fd) for standard output (fd 1).

*stderr*
```
pub fn stderr() -> Fd;
```

	Returns a typed file descriptor (Fd) for standard error (fd 2).

*stdin*
```
pub fn stdin() -> Fd;
```

	Returns a typed file descriptor (Fd) for standard input (fd 0).

*write*
```
pub fn write(fd: Fd, buf: [u8]) -> Result<usize, Error>;
```

	Writes bytes from buf to descriptor fd, returning the number of bytes written.

*read*
```
pub fn read(fd: Fd, buf: [mut u8]) -> Result<usize, Error>;
```

	Reads bytes from descriptor fd into buf, returning the number of bytes read.

*close*
```
pub fn close(fd: Fd) -> Result<(), Error>;
```

	Closes the open file descriptor fd.

*exit*
```
pub fn exit(code: i32) -> never;
```

	Immediately terminates the current process with exit status code.

*print*
```
pub fn print(s: [u8]);
```

	Writes string s to standard output.

*println*
```
pub fn println(s: [u8]);
```

	Writes string s followed by a newline to standard output.

*eprint*
```
pub fn eprint(s: [u8]);
```

	Writes string s to standard error.

*eprintln*
```
pub fn eprintln(s: [u8]);
```

	Writes string s followed by a newline to standard error.

*write_all_fd*
```
pub fn write_all_fd(fd: Fd, buf: [u8]) -> Result<(), Error>;
```

	Writes all bytes from buf to file descriptor fd, looping until completion.

*Read*
```
pub trait Read {
    fn read(self: &mut Self, buf: [mut u8]) -> Result<usize, Error>;
}
```

	Trait for synchronous stream readers.

	Byte sources and sinks. Generic code written against these traits handles
	files, the standard streams, and in-memory buffers alike. Both return the
	byte count transferred, or an Error.

*read*
```
fn read(self: &mut Self, buf: [mut u8]) -> Result<usize, Error>;
```

	Reads bytes from descriptor fd into buf, returning the number of bytes read.

*Write*
```
pub trait Write {
    fn write(self: &mut Self, buf: [u8]) -> Result<usize, Error>;
}
```

	Trait for synchronous stream writers.

*write*
```
fn write(self: &mut Self, buf: [u8]) -> Result<usize, Error>;
```

	Writes bytes from buf to descriptor fd, returning the number of bytes written.

*write_all*
```
pub fn write_all<W: Write>(w: &mut W, buf: [u8]) -> Result<(), Error>;
```

	Writes all bytes from buf to stream w, looping until completion or error.

*File*
```
pub struct File {
/* private fields */
}
```

	Safe file handle wrapping an Fd with automatic closing on drop.

*fd*
```
pub fn fd(self: &File) -> Fd;
```

	Returns an immutable reference to the wrapped Fd.

*close*
```
pub fn close(mut self: File) -> Result<(), Error>;
```

	Explicitly closes the file handle, returning any error encountered during close.

	Explicitly closes the file, returning any error.
	Callers who care about close errors (e.g. NFS flushes) call this; Drop ignores errors.

*read*
```
pub fn read(self: &mut File, buf: [mut u8]) -> Result<usize, Error>;
```

	Reads bytes from the file into buf.

*write*
```
pub fn write(self: &mut File, buf: [u8]) -> Result<usize, Error>;
```

	Writes bytes from buf into the file.

*drop*
```
pub fn drop(self: File);
```

	Closes the underlying file descriptor if open.

*read*
```
pub fn read(self: &mut Fd, buf: [mut u8]) -> Result<usize, Error>;
```

	Reads bytes from descriptor fd into buf, returning the number of bytes read.

*write*
```
pub fn write(self: &mut Fd, buf: [u8]) -> Result<usize, Error>;
```

	Writes bytes from buf to descriptor fd, returning the number of bytes written.

*Stdin*
```
pub struct Stdin {
}
```

	Standard input stream reader.

	The standard streams. Unlike File they do not own their descriptor, so
	dropping one never closes it.

*Stdout*
```
pub struct Stdout {
}
```

	Standard output stream writer.

*Stderr*
```
pub struct Stderr {
}
```

	Standard error stream writer.

*new*
```
pub fn new() -> Stdin;
```

	Constructs a new Stdin stream reader.

*new*
```
pub fn new() -> Stdout;
```

	Constructs a new Stdout stream writer.

*new*
```
pub fn new() -> Stderr;
```

	Constructs a new Stderr stream writer.

*read*
```
pub fn read(self: &mut Stdin, buf: [mut u8]) -> Result<usize, Error>;
```

	Reads bytes from standard input into buf.

*write*
```
pub fn write(self: &mut Stdout, buf: [u8]) -> Result<usize, Error>;
```

	Writes bytes from buf to standard output.

*write*
```
pub fn write(self: &mut Stderr, buf: [u8]) -> Result<usize, Error>;
```

	Writes bytes from buf to standard error.

*SliceReader*
```
pub struct SliceReader {
pub data: [u8],
pub pos: usize,
}
```

	In-memory stream reader over a byte slice.

*new*
```
pub fn new(data: [u8]) -> SliceReader;
```

	Constructs a SliceReader wrapping data.

*read*
```
pub fn read(self: &mut SliceReader, buf: [mut u8]) -> Result<usize, Error>;
```

	Reads bytes from the underlying slice into buf.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*from_unix_raw*
```
pub unsafe fn from_unix_raw(raw: i32) -> Fd;
```

	Unsafely constructs an Fd wrapping an arbitrary integer descriptor.

	Caller obligation: caller must ensure raw is a valid, open operating-system file descriptor.

*unix_raw*
```
pub fn unix_raw(self: Fd) -> i32;
```

	Returns the underlying integer file descriptor.

*from_fd*
```
pub unsafe fn from_fd(fd: Fd) -> File;
```

	Wraps an existing descriptor in an owned File that closes it on drop.

	Caller obligation: fd must be an open, exclusively-owned descriptor; ownership passes to
	the File, which closes it on drop.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
