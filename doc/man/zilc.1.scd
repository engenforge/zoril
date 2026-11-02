zilc(1)

# NAME

zilc - Intermediate representation lowerer (ZIL to QBE SSA)

# SYNOPSIS

*zilc* [_options_] <input.zil> [_output.ssa_]

# DESCRIPTION

*zilc* lowers Zoril Intermediate Language (ZIL) into QBE Static Single Assignment (SSA) intermediate representation. It forms the second stage of the Zoril compilation pipeline, bridging the compiler frontend (*zoril*(1)) and the machine code backend (*qbe*(1)).

The output goes to _output.ssa_, or to the file named by *-o*; with neither, *zilc* writes it to standard output.

# OPTIONS

*-o*, *--output* <file>
	Write lowered QBE SSA output to <file>.

*-m*, *--module* <name>
	Override the target module name used during SSA generation.

*-h*, *--help*
	Display usage instructions and command-line options, then exit.

*-V*, *--version*
	Display version information and exit.

# EXAMPLES

Lower a program *zoril*(1) wrote, or one written by hand, and build it with the host tools:

```
zilc prog.zil prog.ssa
qbe -o prog.s prog.ssa
as -o prog.o prog.s
ld -o prog /usr/local/lib/zoril/runtime.o prog.o
```

With no output file the SSA goes to standard output:

```
zilc prog.zil | qbe | as -o prog.o
```

*zilc* checks types; the ownership and region checks run in *zoril*(1) before it writes ZIL, so hand-written ZIL carries none of them.

# EXIT STATUS

*0*
	Compilation and lowering succeeded.

*>0*
	An error occurred during parsing, validation, or SSA lowering.

# SEE ALSO

*zoril*(1), *zbuild*(1)
