zoril-proc(3)

# NAME

zoril-proc - Subprocess spawning and execution management (Command, Child)

# SYNOPSIS

*import* "proc.zrl";

```
pub enum ExitStatus {
Exited(i32),
Signaled(i32),
}
pub struct Child {
pub pid: i64,
}
pub struct Command {
pub program: [u8],
pub args: Vec<[u8]>,
/* private fields */
}
impl ExitStatus {
    pub fn is_success(self: &ExitStatus) -> bool;
    pub fn code(self: &ExitStatus) -> Option<i32>;
    pub fn unix_signal(self: &ExitStatus) -> Option<i32>;
}
impl Child {
    pub fn wait(self: &mut Child) -> Result<ExitStatus, Error>;
    pub fn kill(self: &mut Child) -> Result<(), Error>;
    pub fn unix_kill(self: &mut Child, sig: i32) -> Result<(), Error>;
}
impl Command {
    pub fn new(program: [u8], a: &Arena) -> Command;
    pub fn arg(self: &mut Command, val: [u8]);
    pub fn set_stdin(self: &mut Command, fd: Fd);
    pub fn set_stdout(self: &mut Command, fd: Fd);
    pub fn set_stderr(self: &mut Command, fd: Fd);
    pub fn spawn(self: &Command) -> Result<Child, Error>;
    pub fn status(self: &Command) -> Result<ExitStatus, Error>;
}
pub fn spawn_simple(program: [u8], a: &Arena) -> Result<Child, Error>;
pub fn run_simple(program: [u8], a: &Arena) -> Result<ExitStatus, Error>;
```

# DESCRIPTION

The *proc* module provides subprocess spawning and execution management (command, child) for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*ExitStatus*
```
pub enum ExitStatus {
Exited(i32),
Signaled(i32),
}
```

	Exit status code or termination signal of a completed subprocess.

*is_success*
```
pub fn is_success(self: &ExitStatus) -> bool;
```

	Returns true if the subprocess exited cleanly with exit status 0.

*code*
```
pub fn code(self: &ExitStatus) -> Option<i32>;
```

	Returns the integer exit status code if the process exited normally.

*unix_signal*
```
pub fn unix_signal(self: &ExitStatus) -> Option<i32>;
```

	Returns the terminating signal number if the process was killed by a signal. Signals exist on
	the Unixes only, so the name says so.

*Child*
```
pub struct Child {
pub pid: i64,
}
```

	Handle representing a running or completed child process.

*wait*
```
pub fn wait(self: &mut Child) -> Result<ExitStatus, Error>;
```

	Waits for the child process to complete and returns its exit status.

*kill*
```
pub fn kill(self: &mut Child) -> Result<(), Error>;
```

	Forcibly terminates the child process (SIGKILL on the Unixes).

*unix_kill*
```
pub fn unix_kill(self: &mut Child, sig: i32) -> Result<(), Error>;
```

	Sends the Unix signal number sig to the child process.

*Command*
```
pub struct Command {
pub program: [u8],
pub args: Vec<[u8]>,
/* private fields */
}
```

	Process builder configuring program path, arguments, environment, and I/O redirection.

*new*
```
pub fn new(program: [u8], a: &Arena) -> Command;
```

	Creates a new Command for program with arguments allocated in arena a.

	Safe: the returned command holds the arena (through its [u8] fields), so resetting or
	destroying the arena while the command is live is a compile error.

*arg*
```
pub fn arg(self: &mut Command, val: [u8]);
```

	Appends an argument string to the command.

*set_stdin*
```
pub fn set_stdin(self: &mut Command, fd: Fd);
```

	Redirects child standard input to read from file descriptor fd.

*set_stdout*
```
pub fn set_stdout(self: &mut Command, fd: Fd);
```

	Redirects child standard output to write to file descriptor fd.

*set_stderr*
```
pub fn set_stderr(self: &mut Command, fd: Fd);
```

	Redirects child standard error to write to file descriptor fd.

*spawn*
```
pub fn spawn(self: &Command) -> Result<Child, Error>;
```

	Spawns the configured command as an asynchronous child process.

*status*
```
pub fn status(self: &Command) -> Result<ExitStatus, Error>;
```

	Spawns the command and waits for completion, returning the process exit status.

*spawn_simple*
```
pub fn spawn_simple(program: [u8], a: &Arena) -> Result<Child, Error>;
```

	Spawns program with no arguments and default environment.

*run_simple*
```
pub fn run_simple(program: [u8], a: &Arena) -> Result<ExitStatus, Error>;
```

	Runs program with no arguments to completion and returns its exit status.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*new_raw*
```
pub unsafe fn new_raw(program: [u8], arena: *mut ArenaHeader) -> Command;
```

	Creates a new Command using a raw arena header.

	Caller obligation: arena must be valid and program must be non-empty.

*set_envp*
```
pub unsafe fn set_envp(self: &mut Command, envp: **u8);
```

	Sets the environment array pointer for the spawned process.

	Caller obligation: caller must ensure envp is a valid null-terminated array of strings.

*spawn_simple_raw*
```
pub unsafe fn spawn_simple_raw(program: [u8], arena: *mut ArenaHeader) -> Result<Child, Error>;
```

	Spawns a program using a raw arena header.

	Caller obligation: arena must be valid and program must be non-empty.

*run_simple_raw*
```
pub unsafe fn run_simple_raw(program: [u8], arena: *mut ArenaHeader) -> Result<ExitStatus, Error>;
```

	Runs a program to completion using a raw arena header.

	Caller obligation: arena must be valid and program must be non-empty.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
