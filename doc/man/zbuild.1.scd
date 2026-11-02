zbuild(1)

# NAME

zbuild - Incremental compilation driver for the Zoril language

# SYNOPSIS

*zbuild* [_options_] <entry.zrl>++
*zbuild* *--gc* [*--cache-dir* <dir>]

# DESCRIPTION

*zbuild* is the incremental compilation driver for the Zoril systems programming language. It orchestrates the multi-stage compilation pipeline (*zoril*(1), *zilc*(1), *qbe*(1), *as*(1), and *ld*(1)) across the complete dependency graph reachable from the entry module.

# COMPILATION CACHE AND INCREMENTAL REBUILDS

*zbuild* caches compiled intermediate objects and interface summaries inside the build cache directory (by default *.zoril-cache* in the current working directory). Rebuild decisions are computed using cryptographic SHA-256 hashes of module interfaces rather than file modification timestamps alone. When an upstream module changes without modifying its public interface, downstream modules that depend on it are not recompiled.

At the conclusion of a build, *zbuild* reports the compilation volume:

```
compiled: N modules
```

If no dependencies or source files have changed since the previous build, *zbuild* reports *compiled: 0 modules* and links the existing cached artifacts directly.

# MODULE RESOLUTION

When a source file executes *import "foo.zrl"*, *zbuild* searches for the imported module in the following order:
1. Relative to the importing source file's directory.
2. In include directories specified with *-I* in left-to-right order.
3. In the project root directory specified with *--root*.
4. In the installed standard library directory (discovered relative to the *zbuild*
binary at *../share/zoril/stdlib*).

# OPTIONS

*-h*, *--help*
	Display usage summary and exit.

*-V*, *--version*
	Display version information and exit.

*-o* <path>
	Set the output executable path. Defaults to *./a.out*.

*-I* <dir>
	Add an include directory to the module search path. Repeatable.

*--root* <dir>
	Set the project root directory.

*--cache-dir* <dir>
	Specify an alternative build cache directory. Defaults to *.zoril-cache*.

*--gc*
	Garbage-collect the build cache. When invoked without an entry module, *zbuild* removes database records whose source files no longer exist on disk and deletes unreferenced object and interface artifacts.

*-v*, *--verbose*
	Enable detailed progress output, reporting cache hits, misses, and execution of underlying pipeline tools.

*--compiler* <path>
	Explicit path to the *zoril*(1) compiler frontend binary.

*--zilc* <path>
	Explicit path to the *zilc*(1) intermediate lowerer binary.

*--qbe* <path>
	Explicit path to the QBE code generator binary. Overrides *BACKEND_BIN*.

*--as* <path>
	Explicit path to the system assembler binary. Overrides *ASSEMBLER_BIN*.

*--ld* <path>
	Explicit path to the system linker binary. Overrides *LINKER_BIN*.

*--hosted*
	Build a program that is linked into a libc process: the compiler is run with *--hosted*, the link goes through *cc* with *runtime_hosted.o* instead of *ld* with *runtime.o*, and the linker is given only *PATH* as its environment. The flag is part of the toolchain id, so objects built with and without it are never reused for each other.

*--cc* <path>
	The C compiler driver that links a *--hosted* program. Overrides *LINK_CC*; defaults to *cc*.

*--link-object* <file>
	Link this object file (a C object, say) into the program, after the program's own objects. Repeatable. A file that does not exist is an error naming it. *--link-object*, *-L*, *-l* and *--link-arg* reach the linker in the order they are given.

*-L* <dir>
	Add a library search directory to the link. Repeatable. *-L*<dir> is also accepted.

*-l* <name>
	Link the library *lib*<name> (*lib*<name>*.a* or *lib*<name>*.so*). Repeatable. *-l*<name> is also accepted.

*--link-arg* <arg>
	Pass <arg> to the linker as it is. Repeatable. Link inputs reach the final link only: changing one relinks the program and recompiles no module.

*--runtime* <path>
	Path to the Zoril runtime assembly object (*runtime.o*). By default, *zbuild* locates the runtime relative to its own binary at *../lib/zoril/runtime.o*.

*--checked*
	Developer option, not a user-facing mode: build the program with *zoril --checked*, which instruments it for memory-safety testing. The mode is part of the toolchain id, so objects built with and without it are never reused for each other. A release build is unaffected.

# ENVIRONMENT

*BACKEND_BIN*
	Default path to the QBE backend binary (default: *qbe*).

*ASSEMBLER_BIN*
	Default path to the system assembler binary (default: *as*).

*LINKER_BIN*
	Default path to the system linker binary (default: *ld*).

*LINK_CC*
	Default C compiler driver for linking a *--hosted* program (default: *cc*).

# CURRENT LIMITS

*zbuild* links Zoril modules with the assembly runtime object (*ld*, no libc), or with *--hosted* into a libc process (*cc*). C objects, libraries and linker arguments are added with *--link-object*, *-L*, *-l* and *--link-arg*. It does not read a project file, and it builds for Linux x86_64 only.

# EXIT STATUS

*0*
	Build or cache operation completed successfully.

*1*
	A compilation, linking, or dependency resolution error occurred.

# EXAMPLES

Build an application executable:

```
cat << 'EOF' > main.zrl
import "io.zrl";
use io::println;

fn main() -> i32 {
    println("Hello from zbuild!");
    return 0;
}
EOF

zbuild -o app main.zrl
./app
```

Clean obsolete build artifacts from the cache:

```
zbuild --gc
```

# SEE ALSO

*zoril*(1), *zilc*(1), *zoril-stdlib*(7)
