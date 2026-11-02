zoril-os_linux(3)

# NAME

zoril-os_linux - Linux-only operating-system interface: open(2) flags, opening by raw flags, and raw process syscalls

# SYNOPSIS

*import* "os_linux.zrl";

```
pub const O_RDONLY: u64 = 0;
pub const O_WRONLY: u64 = 1;
pub const O_RDWR: u64 = 2;
pub const O_CREAT: u64 = 64;
pub const O_EXCL: u64 = 128;
pub const O_NOCTTY: u64 = 256;
pub const O_TRUNC: u64 = 512;
pub const O_APPEND: u64 = 1024;
pub const O_NONBLOCK: u64 = 2048;
pub const O_DIRECTORY: u64 = 65536;
pub const O_CLOEXEC: u64 = 524288;
pub fn open(path: [u8], flags: u64, mode: u64) -> Result<Fd, Error>;
pub fn open_file(path: [u8], flags: u64, mode: u64) -> Result<File, Error>;
pub fn sys_fork() -> Result<i64, Error>;
pub fn sys_kill(pid: i64, sig: i32) -> Result<(), Error>;
pub fn sys_dup2(oldfd: Fd, newfd: Fd) -> Result<Fd, Error>;
pub fn sys_fstat(fd: Fd, out_size: &mut i64, out_mtime: &mut i64) -> Result<(), Error>;
```

# DESCRIPTION

The *os_linux* module provides linux-only operating-system interface: open(2) flags, opening by raw flags, and raw process syscalls for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*O_RDONLY*
```
pub const O_RDONLY: u64 = 0;
```

	Open flag: open for reading only.

*O_WRONLY*
```
pub const O_WRONLY: u64 = 1;
```

	Open flag: open for writing only.

*O_RDWR*
```
pub const O_RDWR: u64 = 2;
```

	Open flag: open for reading and writing.

*O_CREAT*
```
pub const O_CREAT: u64 = 64;
```

	Open flag: create file if it does not exist.

*O_EXCL*
```
pub const O_EXCL: u64 = 128;
```

	Open flag: error if O\_CREAT is set and file exists.

*O_NOCTTY*
```
pub const O_NOCTTY: u64 = 256;
```

	Open flag: do not assign controlling terminal.

*O_TRUNC*
```
pub const O_TRUNC: u64 = 512;
```

	Open flag: truncate file length to 0 on open.

*O_APPEND*
```
pub const O_APPEND: u64 = 1024;
```

	Open flag: append data to end of file on each write.

*O_NONBLOCK*
```
pub const O_NONBLOCK: u64 = 2048;
```

	Open flag: non-blocking I/O mode.

*O_DIRECTORY*
```
pub const O_DIRECTORY: u64 = 65536;
```

	Open flag: fail if path is not a directory.

*O_CLOEXEC*
```
pub const O_CLOEXEC: u64 = 524288;
```

	Open flag: set close-on-exec flag on the descriptor.

*open*
```
pub fn open(path: [u8], flags: u64, mode: u64) -> Result<Fd, Error>;
```

	Opens a file by path, raw Linux O\_\* flags, and permission bits, returning its descriptor.

*open_file*
```
pub fn open_file(path: [u8], flags: u64, mode: u64) -> Result<File, Error>;
```

	Opens a file by path, raw Linux O\_\* flags, and permission bits, returning a File that closes
	the descriptor on drop.

*sys_fork*
```
pub fn sys_fork() -> Result<i64, Error>;
```

	Raw kernel fork system call wrapper.

*sys_kill*
```
pub fn sys_kill(pid: i64, sig: i32) -> Result<(), Error>;
```

	Raw kernel kill system call wrapper.

*sys_dup2*
```
pub fn sys_dup2(oldfd: Fd, newfd: Fd) -> Result<Fd, Error>;
```

	Raw kernel dup2 system call wrapper.

*sys_fstat*
```
pub fn sys_fstat(fd: Fd, out_size: &mut i64, out_mtime: &mut i64) -> Result<(), Error>;
```

	Raw kernel fstat system call wrapper.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*sys_execve*
```
pub unsafe fn sys_execve(pathname: *u8, argv: **u8, envp: **u8) -> Result<(), Error>;
```

	Caller obligation: pathname, argv, and envp must be valid null-terminated C string pointers.

*sys_wait4*
```
pub unsafe fn sys_wait4(pid: i64, wstatus: *mut i32, options: i32) -> Result<i64, Error>;
```

	Caller obligation: wstatus must be null or point to valid writable storage for an i32 status code.

*sys_pipe2*
```
pub unsafe fn sys_pipe2(pipefd: *mut [i32; 2], flags: i32) -> Result<(), Error>;
```

	Caller obligation: pipefd must point to valid writable storage for two i32 descriptors.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
