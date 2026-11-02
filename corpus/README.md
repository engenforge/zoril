# Zoril Few-Shot Corpus

Canonical reference programs for the Zoril programming language. This corpus is designed to teach the complete current Zoril surface language and intermediate language by example, to people first and to AI tools second.

## Purpose

The programs in `zrl/` exercise the core of the surface language (the table below lists what each covers), while the files in `zil/` exercise the Intermediate Language (ZIL) opcodes and verifier. The corpus is a set of examples, not a complete feature list: it does not yet cover `if let` and `while let`, match guards, attributes (`#[borrows]`, `#[stores]`, `#[export]`), `extern "C" fn` definitions, `@slice` and `@alloca`, `impl Copy`/`Clone` and `#[derive(Clone)]`, or linear `fd<..>` types; [`doc/spec/surface_syntax.md`](../doc/spec/surface_syntax.md) specifies them and [`doc/tour.md`](../doc/tour.md) shows several. They serve as:

1. **Learning material** for developers new to Zoril
2. **Conformance tests** for new compiler implementations
3. **Examples for AI tools** working on Zoril code

## Directory Structure

- `zrl/`: Zoril surface language programs.
- `zil/`: Zoril Intermediate Language programs. Each states its expected exit code in its first line; to build one by hand, see "Starting from ZIL" in [Getting Started](../doc/getting_started.md#starting-from-zil).

## Surface Language Feature Coverage (zrl/)

| #  | File                               | Features                                                              |
| -- | ---------------------------------- | --------------------------------------------------------------------- |
| 01 | hello_syscall                      | @syscall, string literals, slices, .ptr/.len                          |
| 02 | primitives_and_literals            | all numeric types, hex/bin/oct, underscores, as cast, char literals   |
| 03 | operators_and_precedence           | all binary/bitwise/logical ops, compound assignment, precedence       |
| 04 | control_flow                       | if/else if, while, for..in, break, continue, block expressions        |
| 05 | structs_and_methods                | struct, impl, self, method calls, (\*ptr).method(), trailing commas   |
| 06 | enums_and_match                    | enum, bare variants, match, qualified construction, payloads, OR pats |
| 07 | option_and_result                  | generic enums, ? operator, error propagation                          |
| 08 | generics                           | generic structs/functions, type inference, explicit type args         |
| 09 | traits                             | trait, impl Trait for Type, trait bounds, static dispatch             |
| 10 | closures                           | non-capturing lambdas, capturing closures, fn pointer types           |
| 11 | ownership_and_move                 | Box, move semantics, @drop, linear ownership                          |
| 12 | borrows                            | &T, &mut T, dereference, borrow of fields                             |
| 13 | arrays_and_slices                  | [T; N], [T], indexing, .len, bounds-checked access                    |
| 14 | tuples                             | (T1, T2), .0/.1 access, tuples as return types                        |
| 15 | type_aliases                       | type keyword, aliasing primitives and composite types                 |
| 16 | defer                              | defer ordering (LIFO), cleanup patterns                               |
| 17 | strings_and_escapes                | escape sequences, raw strings (r"..."), .ptr, .len, char literals     |
| 18 | ffi_and_extern                     | @syscall, direct I/O, bypassing libc, kernel interface                |
| 19 | sizeof_alignof                     | sizeof(T), alignof(T), primitives, structs, tuples, generics          |
| 20 | function_pointers                  | fn(T)->R type, indirect calls, callback patterns                      |
| 21 | allocators                         | box, Box<T>, region tracking                                          |
| 22 | branch_annotations                 | @likely, @unlikely                                                    |
| 23 | globals_and_constants              | const, static, static mut, multi-function global access               |
| 24 | comments                           | `//` single-line, `/* */` multi-line, `/* /* */ */` nested            |
| 25 | linked_list                        | generics + Box + enums + match + recursion combined                   |
| 26 | expression_oriented                | blocks/if/match as expressions, implicit returns                      |
| 27 | syscall_io                         | direct POSIX I/O, integer-to-string conversion                        |
| 28 | generic_container                  | generic Stack with methods, Option returns                            |
| 29 | bit_manipulation                   | hex/binary literals, bitwise ops, flag patterns                       |
| 30 | trait_polymorphism                 | multiple traits per type, generic constraint composition              |
| 31 | hashmap                            | stdlib HashMap<K,V> auto-resizing, Hash/Drop traits, import           |
| 32 | stdlib_methods                     | Option is_some/is_none, Result methods, core.zrl import               |
| 33 | vec_and_string                     | stdlib Vec<T> push/len/get, String, import chain, auto drop           |
| 34 | drop_trait                         | Drop trait, automatic resource cleanup, RAII pattern                  |
| 35 | method_receiver_shapes             | &T, &mut T, *T, *mut T, Box<T> receivers; explicit deref dispatch     |
| 36 | ptr_field_write_and_deref_patterns | (\*ptr).field read/write; pointer == / != null; chained deref writes  |
| 37 | never_type                         | never type, infinite loop, panic coercion, diverging match arms       |
| 38 | large_enum_pass_by_value           | stress-testing large enum layouts and by-value passing semantics      |
| 39 | range_patterns                     | range patterns (.. and ..=) in match expressions, char ranges         |
| 40 | wrapping_arithmetic                | wrapping operators +%, -%, *% (modulo arithmetic)                     |
| 41 | float_comparisons                  | <, <=, >, >=, ==, != on f32 and f64                                   |
| 42 | traits_and_iterators               | default methods, associated types, iterator chains, closure values    |

## Intermediate Language Coverage (zil/)

| #  | File              | Features                                                                         |
| -- | ----------------- | -------------------------------------------------------------------------------- |
| 01 | arithmetic        | add, sub, mul, div, rem                                                          |
| 02 | comparison        | lt, le, gt, ge, eq, ne                                                           |
| 03 | bitwise           | and, or, xor, shl, shr                                                           |
| 04 | memory            | alloc, load, store                                                               |
| 05 | ownership_move    | move, region_cast                                                                |
| 06 | ownership_drop    | drop, auto_drop semantics                                                        |
| 07 | branching         | branch, jump                                                                     |
| 08 | calls             | call, func_addr                                                                  |
| 09 | phi               | phi instruction, basic block merging                                             |
| 10 | globals           | global_addr, global data definitions                                             |
| 11 | structs           | field_addr, struct type definitions                                              |
| 12 | enums_sum         | sum_construct, variant_match, unwrap, is_some                                    |
| 13 | slices            | slice_construct, slice_len, slice_load, slice_store                              |
| 14 | bounds_checks     | bounds_check instruction                                                         |
| 15 | io_syscall        | syscall, direct I/O                                                              |
| 16 | async             | async_setup, async_enter, async_close                                            |
| 17 | overflow          | wrapping_add/sub/mul, saturating_add, checked_add/sub/mul                        |
| 18 | func_ptr          | func_addr, call_ptr (indirect calls)                                             |
| 19 | fd_io             | fd_open, fd_write, fd_close                                                      |
| 20 | variadic          | variadic function definition and call                                            |
| 21 | raw_pointer_types | RawPtr/RawPtrMut type spellings through the parser, verifier, layout and codegen |
| 22 | region_cast       | region_cast (casting a pointer to a shorter-lived region)                        |
| 23 | array_construct   | array_construct, array_load, bounds_check                                        |
| 24 | tuples            | tuple allocation, field_addr, load and store                                     |

## Whole-Program Hashes

`zrl_whole_program_zil.sha256` records the SHA-256 of the whole-program ZIL emitted for each of the 42 `zrl/` programs. `scripts/test_incremental.sh` regenerates the hashes and compares them, so any unintended change in whole-program emission fails the test; regenerate the file deliberately with `UPDATE_GOLDEN=1` in a dedicated commit when an emission change is intended.
