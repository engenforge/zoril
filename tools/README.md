# Zoril Toolchain

This directory contains compiler utilities and build tools for Zoril.

## Tools

| Tool           | Description                          | Input          | Output                 |
| :------------- | :----------------------------------- | :------------- | :--------------------- |
| `tools/zilc`   | Zoril Intermediate Language compiler | `.zil`         | QBE SSA IR (`.ssa`)    |
| `tools/zbuild` | Incremental compilation driver       | `.zrl` modules | Executable binary      |
| `tools/zman`   | Standard library man page generator  | `.zri`, `.zrl` | `zoril-<module>.3.scd` |

## Compilation Pipeline

A `.zrl` source compiles through the following toolchain:

```text
build/zoril  --emit-zil  ->  build/zilc  ->  qbe  ->  as  ->  ld  (with rt/runtime.s)
   (Zoril)        ZIL         (ZIL→SSA)   (host)  (host)  (host)
```

1. **`build/zoril`** parses source code, validates types and borrow rules, runs safety verification passes, and emits ZIL (`.zil`).
2. **`build/zilc`** lowers ZIL into QBE Intermediate Language (`.ssa`), threading documentation comments.
3. **`qbe`** translates SSA IR into native assembly (`.s`).
4. **`as`** (host assembler) assembles `.s` into ELF object files (`.o`).
5. **`ld`** (host linker) links `.o` files with `build/runtime.o` (`rt/runtime.s`) into an executable.

## Incremental Compilation (`zbuild`)

`tools/zbuild` automates the compilation pipeline with fine-grained dependency tracking:

- Computes module dependency graphs via `zoril --emit-deps`.
- Compiles stale modules in topological order.
- Applies early-cutoff optimization through interface files (`.zri`).
- Caches build artifacts in `.zoril-cache`.
