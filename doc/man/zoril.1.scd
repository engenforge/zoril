zoril(1)

# NAME

zoril - Self-hosted compiler for the Zoril systems programming language

# SYNOPSIS

*zoril* [_options_] <input.zrl>++
*zoril fmt* [*--check*] <file.zrl>...

# DESCRIPTION

*zoril* is the self-hosted frontend compiler for the Zoril systems programming language. It parses source files, checks type and memory safety rules, performs semantic analysis, and emits textual Zoril Intermediate Language (ZIL) or module interface files (.zri).

Zoril checks memory and type safety at compile time using region-based arena allocations, affine ownership tracking, and non-null fat pointers. For detailed information on the safety model and invariants, refer to *doc/SAFETY.md*.

The compiler accepts exactly one input file. Specifying more than one input file, or an unrecognized option beginning with *-*, is an error. The special argument *--* terminates option processing, allowing file names that begin with a dash to be passed as the input.

# SUBCOMMANDS

*zoril fmt* [*--check*] <file.zrl>...
	Format Zoril source files in place. If *--check* is specified, *zoril fmt* does not modify files; instead, it lists unformatted files and exits with a non-zero status if any formatting changes are needed.

# OPTIONS

*-h*, *--help*
	Display usage instructions and exit.

*-V*, *--version*
	Display compiler version and exit.

*-o* <file>
	Write output to <file>. Defaults to *out.zil*.

*-I* <dir> | *-I* <name>=<dir>
	Add an include root. When specified as *name=dir*, the root anchors module identities under a logical package namespace.

*--root* <dir>
	Set the project root directory for module resolution.

*--emit-zil*
	Emit textual ZIL (the default action).

*-c*, *--compile-only*
	Compile only the specified module without processing or linking dependencies (separate compilation).

*--emit-interface*
	Write the module's public interface summary (.zri) instead of ZIL.

*--write-interface* <file>
	In addition to the primary output, write the module's public interface to <file>.

*--iface-dir* <dir>
	Read imported modules' cached interface definitions from <dir>.

*--require-interface*
	Require an interface file under the interface directory for every import; treat missing interfaces as a fatal compilation error rather than falling back to parsing full module source.

*--emit-deps*
	Print the dependency import graph reachable from the input module.

*--emit-zir-stats*
	Print a census of the ZIR constructs and CFG shape the input lowers to, one line per construct, and exit without emitting ZIL. Used by *scripts/check_route_coverage.sh* to check that the probes cited by a safety matrix row walk every route the row lists.

*--lower-all*
	Developer option. A whole-program build lowers and checks a function of an imported standard-library module only when the program reaches it; the input module and every other import are lowered in full. This option lowers the standard library's functions in full too, as a build did before, so that a check sees every body. Used by *scripts/check_stdlib_bodies.sh*, which compiles each standard-library module this way.

*-v*, *--verbose*
	Report compilation progress, printing each phase, source file, and function as it is processed.

*-W* <lint> | *-A* <lint>
	Enable (*-W*, warn) or disable (*-A*, allow) the specified compiler lint. Supported lints include:
	- *wildcard-arm*: Warn when pattern matches contain catch-all wildcard arms.
	- *redundant-cast*: Warn on redundant type casts (disabled by default).

*--hosted*
	Name the program's entry *zoril_main* instead of *main*, for a program linked into a libc process: *rt/runtime_hosted.o* defines the *main* that C's startup code calls and tail-calls it. Link with *cc*, not *ld*. Nothing else in the output changes, and a build without the flag is unchanged. A trap is libc's *abort* (status 134) and does not flush C stdio.

*--checked*
	Developer option, not a user-facing mode. Instrument the emitted program for memory-safety testing: released arena space stays poisoned and is never handed out again, a local's slot is poisoned where its scope ends, a dropped value is poisoned and a second drop of it traps (exit 134), and a heap block released twice traps instead of unmapping whatever lives there now. A release build contains none of it - the instrumentation is emitted only under this flag, so the emitted ZIL of a program does not change - and it is not a safety mode: nothing about what the compiler accepts changes. See *make test-checked* in *doc/developer_guide.md*.

*--*
	Terminate option processing. All subsequent arguments are treated as input file paths, even if they begin with a dash *-*.


# SEPARATE COMPILATION AND INTERFACES

Zoril supports separate compilation using lightweight interface files (*.zri*). When compiling a module with *-c*, the compiler generates a *.zil* object and, optionally with *--write-interface*, a *.zri* interface describing the public types, traits, functions, and memory summaries. Subsequent compilations can load the pre-computed interface using *--iface-dir*, eliminating the need to re-parse and re-analyze upstream source dependencies.

# EXIT STATUS

*0*
	Compilation, formatting, or query succeeded.

*1*
	A compilation, type checking, syntax, or command-line argument error occurred.

*134*
	A compiler internal assertion or memory constraint was violated (traps).

# EXAMPLES

Compile a standalone program manually using the five-stage pipeline:

```
cat << 'EOF' > hello.zrl
import "io.zrl";
use io::println;

fn main() -> i32 {
    println("Hello, World!");
    return 0;
}
EOF

zoril -I /usr/local/share/zoril/stdlib --emit-zil -o hello.zil hello.zrl
zilc hello.zil hello.ssa
qbe -o hello.s hello.ssa
as -o hello.o hello.s
ld -o hello /usr/local/lib/zoril/runtime.o hello.o
./hello
```

Compile a library module separately and produce its public interface:

```
cat << 'EOF' > math.zrl
pub fn add(a: i64, b: i64) -> i64 {
    return a + b;
}
EOF

zoril -I /usr/local/share/zoril/stdlib -c -o math.zil --write-interface math.zri math.zrl
```

# SEE ALSO

*zilc*(1), *zbuild*(1), *zoril-stdlib*(7)
