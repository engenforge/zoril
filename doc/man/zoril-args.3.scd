zoril-args(3)

# NAME

zoril-args - Command-line argument inspection and iteration

# SYNOPSIS

*import* "args.zrl";

```
pub struct Args {
/* private fields */
}
impl Args {
    pub fn len(self: &Args) -> usize;
    pub fn get(self: &Args, index: usize) -> Option<[u8]>;
    pub fn program_name(self: &Args) -> [u8];
    pub fn has_next(self: &Args) -> bool;
    pub fn next(self: &mut Args) -> Option<[u8]>;
}
pub extern fn zoril_argc() -> i32;
pub extern fn zoril_argv() -> **u8;
pub fn args() -> Args;
```

# DESCRIPTION

The *args* module provides command-line argument inspection and iteration for Zoril programs.
All operations interface directly with kernel facilities or safe region-allocated
memory without relying on the C runtime library.

# ITEMS

*zoril_argc*
```
pub extern fn zoril_argc() -> i32;
```

	Returns the number of command-line arguments passed to the process.

	The process arguments the runtime recorded before it called main, handed back through these
	(the zoril\_argc/zoril\_argv accessors in rt/runtime.s). Declared here so that the only code
	that ever holds the raw argv is args() below.

*zoril_argv*
```
pub extern fn zoril_argv() -> **u8;
```

	Returns the raw pointer to the null-terminated array of argument strings.

	Caller obligation: caller must not mutate the array or access pointers beyond argc.

*Args*
```
pub struct Args {
/* private fields */
}
```

	Iterator over command-line arguments provided by the runtime environment.

*len*
```
pub fn len(self: &Args) -> usize;
```

	Returns the total number of command-line arguments.

*get*
```
pub fn get(self: &Args, index: usize) -> Option<[u8]>;
```

	Returns the argument at index as a byte slice, or None if index is out of bounds.

*program_name*
```
pub fn program_name(self: &Args) -> [u8];
```

	Returns the program invocation name (argv[0]) as a byte slice.

*has_next*
```
pub fn has_next(self: &Args) -> bool;
```

	Returns true if more arguments remain to be yielded.

*next*
```
pub fn next(self: &mut Args) -> Option<[u8]>;
```

	Yields the next argument as a byte slice, or None when all arguments have been consumed.

*args*
```
pub fn args() -> Args;
```

	Returns an Args iterator initialized with process command-line arguments.

	The arguments this process was started with. Safe: the values come from the kernel by way of the
	runtime, and no caller can name them, so nothing here points at memory the program does not own.
	Prefer this to Args.new, which needs unsafe for the case where the caller already has an
	(argc, argv) pair of its own, as a main(argc: i32, argv: \*\*u8) receives.

# INTERNAL

The following unsafe escape hatches are intended for the bootstrap compiler
and standard library internals:

*new*
```
pub unsafe fn new(argc: i32, argv: **u8) -> Args;
```

	Constructs an Args iterator from raw argc and argv pointers.

	Caller obligation: caller must ensure argv is non-null and points to valid strings for argc elements.

	Requires unsafe: the caller vouches that argv points at argc NUL-terminated strings it
	may read from. Safe code uses args() below, which takes both from the runtime.

# RETURN VALUES AND ERRORS

Fallible operations return `Result<T, io::Error>` or `Option<T>` rather than
setting an errno global. Programming errors and bounds violations trap or panic
with diagnostic exit statuses (see *doc/SAFETY.md*).

# SEE ALSO

*zoril*(1), *zbuild*(1), *zoril-stdlib*(7)
