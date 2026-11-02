# `zoril fmt` — Source Code Formatter

`zoril fmt` is the standard source code formatter for Zoril programs. It automatically formats `.zrl` source files according to the standard Zoril style guide.

## Usage

```bash
zoril fmt [--check] <file.zrl>...
```

### Options

- `--check`: Does not write formatted code back to disk. Instead, prints the path of each file that needs formatting and exits with status 1 if any unformatted file was found. Exits 0 if all specified files are already formatted.

### Exit Status

- `0`: Success. Every file was already formatted (under `--check`) or was successfully formatted in place.
- `1`: Failure. Under `--check`, one or more files differ from the formatted layout. In default formatting mode, indicates that a file could not be read, contained syntax or lexing errors, or failed the lossless safety check.
- `2`: Command-line usage error (unrecognized option or no files specified).

## Safety and Atomicity Guarantees

`zoril fmt` is designed to be completely safe to run in developer workflows and automated CI pipelines:

1. **Modular parsing**: Each file is parsed in isolation. External module imports do not need to exist or be reachable on the filesystem to format a file.
2. **Lossless token and comment preservation**: Before writing any formatted output to disk, `zoril fmt` re-lexes the formatted output and compares its tokens and comments against the original input. If any token or comment differs or is dropped, formatting is aborted, a diagnostic error is reported pointing to the location of the difference, and the source file is left untouched.
3. **Atomic writes and permission preservation**: When formatting in place, output is written to a temporary sibling file (`<file>.fmt_tmp`), matched to the original file's permissions, and atomically renamed over the target file. If formatting or disk writing fails midway, original files are never truncated or corrupted. When formatting through a symlink, the target file is written directly to preserve the link, so that path is not atomic like a normal in-place format.

## Default Style Rules

The formatter enforces the official Zoril style:

### Indentation and Spacing

- Indentation is **4 spaces**. Hard tabs (`\t`) are not used for indentation.
- Maximum line width target is **100 columns**.
- At most one blank line is preserved between declarations, statements, or comment blocks. Redundant consecutive blank lines are collapsed to a single blank line.

### Declarations

- Top-level items (`import`, `use`, `fn`, `struct`, `enum`, `trait`, `impl`, `type`, `const`, `static`) are placed at column 0.
- Struct, enum, and trait bodies are indented 4 spaces.
- If a function signature exceeds 100 columns, parameters wrap onto separate lines indented 4 spaces, with the return type and opening brace aligned following the closing parenthesis.

### Control Flow and Statements

- Blocks (`{ ... }`) use 4-space indentation.
- Single-line blocks (`{ ... }`), single-line struct literals, and single-line `match` expressions that fit within 100 columns are preserved on one line when written on one line in the source.
- Multi-line `match` arms place patterns on indented lines; multi-statement arm bodies use `{ ... }` blocks.
- When an `if`, `while`, or `for` statement wraps, the body begins on a new indented line.

### Expressions and Wraps

- **Function call argument lists**: Break one argument per line indented 4 spaces when exceeding the 100-column limit. When a call has a single argument that is a struct literal, closure, block, array literal, or match expression, the argument stays right after the opening parenthesis `(` ("hugging") rather than breaking the outer argument list.
- **Binary operator chains**: Long chains of operators of the same precedence (such as arithmetic or logical operators) break before each operator when exceeding 100 columns, with continuation lines indented 4 spaces.
- **Struct, tuple, and array literals**: Items break across lines when exceeding the 100-column limit. The formatter preserves existing tokens and comments verbatim and never adds or removes trailing commas.

### Comments

- Line comments (`//`) and block comments (`/* ... */`) are preserved verbatim.
- Trailing line comments on the same line as code maintain their relative source column alignment where line length allows.
- Comments inside declaration and statement blocks maintain the indentation level of their surrounding scope.
