# tools/zilc — Zoril Intermediate Language Compiler

Part of the Zoril toolchain (see [`tools/README.md`](../README.md)).

## Role

Compiles textual ZIL (Zoril Intermediate Language) into QBE SSA IR, threading file-level and per-function documentation comments from `.zil` into the emitted `.ssa`.

`zilc` is written in 100% Zoril and self-hosts as part of the compiler build pipeline.

## Input / Output

| Input        | Output              |
| :----------- | :------------------ |
| ZIL (`.zil`) | QBE SSA IR (`.ssa`) |

## Usage

```bash
build/zilc [options] [input.zil] [output.ssa]
```

### Options

| Flag                    | Description                                                                       |
| :---------------------- | :-------------------------------------------------------------------------------- |
| `-o`, `--output <file>` | Write QBE SSA output to `<file>` (default: second positional argument, or stdout) |
| `-m`, `--module <name>` | Override module name                                                              |
| `-h`, `--help`          | Show this help message                                                            |
| `-V`, `--version`       | Display version and exit                                                          |

If `input.zil` is omitted, `zilc` reads textual ZIL from standard input.

## Compilation Pipeline Integration

```text
build/zoril --emit-zil -> build/zilc -> qbe -> as -> ld
```
