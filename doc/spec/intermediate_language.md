# Zoril IL Specification

This document specifies the intermediate language as of `v0.1.0-alpha`.

Zoril IL is a low-level, textual Intermediate Representation (IR) designed for memory safety verification and lowering to the QBE compiler backend. It uses Explicit Static Single Assignment (SSA) form and mandatory region/ownership annotations.

This specification documents the **textual ZIL grammar exactly as produced by the self-hosted compiler's `--emit-zil` flag** (`src/zil_print.zrl`, printing `ILModule` from `src/il_cfg.zrl`, `src/il_type.zrl`, and `src/il_instr.zrl`), so that a textual ZIL parser/reader or a standalone ZIL compiler can be built directly against it.

A few representation notes that recur throughout this document:

- **Region erasure in types**: the in-memory `ILType.Ptr`/`PtrMut`/`Slice` variants store only the pointee/element type — no region. The printer therefore always prints the placeholder region `'local` for these constructors; the only instructions that carry a _real_ `Region` value are `alloc` and `region_cast`. A future ZIL parser must treat the printed region on `Ptr`/`PtrMut`/`Slice` as syntax-only (it is not stored back into the type).
- **Reserved opcodes**: a handful of opcodes are defined in `ILInstr` and handled by the verifier and printer, but are never constructed by any current lowering pass (`borrow`, `borrow_mut`, `end_borrow`, `release`, `likely`, `unlikely`). They are documented here because they are part of the textual grammar a parser must accept, even though real compiler output will not currently contain them.

## 1. Formal Grammar (EBNF)

```ebnf
module      = { type_def | global_def | func_def } ;

type_def    = "type" type_id ":" ( struct_def | sum_def ) ;
struct_def  = "struct" "{" [ field_list ] "}" ;
sum_def     = "sum" "{" [ variant_list ] "}" ;
field_list  = field { "," field } ;
field       = name ":" type ;
variant_list = variant { "," variant } ;
variant     = name ":" type ;

global_def  = "global" global_id ":" type name "=" "{" [ byte_list ] "}" ;
global_id   = "g" integer ;
byte_list   = integer { "," integer } ;

func_def    = func_id ":" type name "(" [ param_list ] ")" "{" { block } "}" ;
param_list  = param { "," param } [ "," "..." ] ;
param       = name ":" type ;

block       = block_id ":" { instruction } ;

instruction = [ ssa_id ":" type "=" ] opcode [ operands ] ;

opcode      = arith_op | cmp_op | overflow_op | mem_op | safety_op
            | slice_op | array_op | sum_op | aggregate_op
            | control_op | hint_op | fd_op | async_context_op ;

arith_op    = "add" | "sub" | "mul" | "div" | "rem" | "neg" | "not"
            | "and" | "or" | "xor" | "shl" | "shr" ;
cmp_op      = "cmp_lt" | "cmp_le" | "cmp_gt" | "cmp_ge" | "cmp_eq" | "cmp_ne" ;
overflow_op = "wrapping_add" | "saturating_add" | "checked_add" ;
mem_op      = "alloc" | "load" | "store" | "drop" ;
safety_op   = "bounds_check" | "move" | "borrow" | "borrow_mut" | "end_borrow"
            | "release" | "region_cast" | "cast" ;
slice_op    = "slice_load" | "slice_store" | "slice_len" | "slice_construct" ;
array_op    = "array_construct" | "array_load" | "array_store" ;
sum_op      = "is_some" | "unwrap" | "variant_match" | "sum_construct" ;
aggregate_op = "struct_construct" | "tuple_construct" ;
control_op  = "call" | "call_ptr" | "ret" | "branch" | "jump" | "const" | "phi"
            | "global_addr" | "func_addr" | "field_addr"
            | "string_const" | "syscall" ;
hint_op     = "param" | "likely" | "unlikely" | "get_env" ;
fd_op       = "fd_open" | "fd_close" | "fd_read" | "fd_write" ;
async_context_op  = "async_setup" | "async_enter" | "async_close" ;

type        = primitive | ptr_type | box_type | slice_type | array_type
            | fn_type | tuple_type | fd_type | "async_context" | user_type | var_type ;
primitive   = "u8" | "u16" | "u32" | "u64"
            | "i8" | "i16" | "i32" | "i64"
            | "usize" | "isize"
            | "f32" | "f64" | "bool" | "char" | "unit" | "never" ;
ptr_type    = ( "Ptr" | "PtrMut" ) "<" type "," region ">" ;
box_type    = ( "Box" | "BoxMut" ) "<" type ">" ;
slice_type  = "Slice" "<" type "," region ">" ;
array_type  = "[" type ";" integer "]" ;
fn_type     = "fn" "(" [ type_list ] [ "," "..." ] ")" "->" type ;
tuple_type  = "(" type { "," type } [ "," ] ")" ;
fd_type     = "fd" "<" fd_cap ">" ;
fd_cap      = "r" | "w" | "rw" ;
user_type   = "T" integer [ "<" type_list ">" ] ;
var_type    = name ;
type_list   = type { "," type } ;

region      = "'" name ;
ssa_id      = "v" [ name "_" ] integer ;
block_id    = ( "@b" | "@" name "_" ) integer ;
func_id     = "f" integer ;
type_id     = "T" integer ;
name        = identifier ;
```

Notes on the grammar above (divergences from a "clean room" ZIL design that the printer's output actually exhibits):

- `global_def` carries **both** a numeric `global_id` (`g<N>`) and the global's source `name`, e.g. `global g0: [u8; 14] greeting = { ... }`. An ID-only or name-only form is not produced.
- `tuple_type`: a one-element tuple `(T,)` is printed with a trailing comma to disambiguate it from a parenthesised type; tuples of two or more elements have no trailing comma.
- `var_type` is printed as the type variable's source name (e.g. `T`) when interned, or the literal text `var` when the name is empty (this occurs for synthetic/anonymous type variables introduced during generic resolution).
- `elem_addr`, `slice_data`, `bitcast`, `wrapping_sub`, `wrapping_mul`, `checked_sub`, and `checked_mul` are **not** opcodes (`src/il_instr.zrl` has no corresponding `IL_INSTR_*` constants). `cast` (§5.5) performs numeric and pointer type conversion.
- **`ssa_id`/`block_id` carry optional source-name hints** ("deobfuscated" form, mirroring the equivalent feature in the QBE emitter): when `ILFunction.ssa_names[id]` / `BasicBlock.name` records a source-level name, the printer emits `v<name>_<id>` / `@<name>_<id>` instead of the bare `v<id>` / `@b<id>` forms — e.g. `vcount_7`, `@loop_body_3`. The trailing `_<id>` is always present and is what makes the form unambiguous: a reader can recover the numeric SSA/block id by taking the suffix after the last `_`, regardless of whether a name hint was present. Compiler internals (e.g. temporaries with no source name) always print the bare numeric form.
- **Source-correlated `//` comments** appear above instructions when the originating source line carries an associated comment (`ILModule.instr_comments` / `instr_spans`), in the form `// <line>: <source text>`, e.g. `// 13: let _t1 = "..."`. A run of consecutive instructions that map to the same comment text and source line is annotated only once, not per-instruction. These are documentation-only; a parser may skip any line beginning with `//`.

## 2. Module Structure

A module consists of type definitions, global variables, and functions.

```zil,no-test
// Type Definition
type T1: struct { x: i32, y: i32 }
type T2: sum { None: unit, Some: i32 }

// Global Variable
global g0: [u8; 5] greeting = { 72, 101, 108, 108, 111 }

// Function (note the deobfuscated `va_2`/`vb_3`/`vsum_4` SSA names, taken from
// the source identifiers `a`, `b`, `sum` — see the note on ssa_id/block_id
// name hints above; an internal temporary with no source name, like `v5`
// here, still prints in plain numeric form)
f0: i32 add(a: i32, b: i32) {
  @b0:
    va_2: i32 = param 1
    vb_3: i32 = param 2
    vsum_4: i32 = add va_2, vb_3
    v5: i32 = const 0
    ret vsum_4
}

// Function whose argument is an aggregate, passed by pointer (shown here in
// plain numeric form — `v1`/`v3`/`@b1` — to keep the focus on `param`/`memcpy`
// semantics rather than name hints; whether a given SSA value or block prints
// with a name hint depends only on whether the compiler recorded one for it)
f1: i32 area(__env: Ptr<unit, 'local>, s: Ptr<T2, 'local>) {
  @b1:
    v1: Ptr<unit, 'local> = param 0
    v3: Ptr<T1, 'local> = param 1
    v4: u64 = const 8
    v5: unit = call memcpy(v2, v3, v4)
    ...
}
```

The `param` opcode (§5.9) materialises an incoming argument into an SSA value at function entry; the compiler emits it only for arguments that are tracked as addressable locals (e.g. when the argument is later borrowed or is an aggregate copied into a local stack slot via `memcpy`, as in `f1` above — there `param 1` yields a `Ptr<T1, 'local>` to the caller's copy, which is then `memcpy`'d into the callee's own `T1` slot). Simple scalar parameters that are never re-bound, like `add`'s `a`/`b`, are referenced directly via the SSA IDs recorded in `ILFunction.params[i].ssa` and need no `param` instruction in the body.

## 3. Type System

### 3.1 Primitives

| Type                      | Size          | Description                                                                     |
| ------------------------- | ------------- | ------------------------------------------------------------------------------- |
| `u8`, `u16`, `u32`, `u64` | 1/2/4/8 bytes | Unsigned integers                                                               |
| `i8`, `i16`, `i32`, `i64` | 1/2/4/8 bytes | Signed integers                                                                 |
| `usize`, `isize`          | 4/8 bytes     | Pointer-sized integers (platform dependent)                                     |
| `f32`                     | 4 bytes       | IEEE 754 single-precision float                                                 |
| `f64`                     | 8 bytes       | IEEE 754 double-precision float                                                 |
| `bool`                    | 1 byte        | Boolean values (`true`, `false`)                                                |
| `char`                    | 4 bytes       | Unicode scalar value                                                            |
| `unit`                    | 0 bytes       | The empty type                                                                  |
| `never`                   | —             | The bottom type; a value of this type never materialises (diverging expression) |

### 3.2 Pointer and Collection Types

| Type            | Description                                              |
| --------------- | -------------------------------------------------------- |
| `Ptr<T, 'r>`    | Immutable non-owning pointer to `T` in region `'r`       |
| `PtrMut<T, 'r>` | Mutable non-owning pointer to `T` in region `'r`         |
| `Box<T>`        | Owned heap-allocated pointer (immutable through the box) |
| `BoxMut<T>`     | Owned heap-allocated pointer (mutable through the box)   |
| `Slice<T, 'r>`  | Fat pointer (`*T` data + `usize` len) carrying a region  |
| `[T; N]`        | Fixed-size array                                         |

**Region erasure**: in-memory, `ILType.Ptr`/`ILType.PtrMut`/`ILType.Slice` (`ILTYPE_PTR=1`, `ILTYPE_PTRMUT=2`, `ILTYPE_SLICE=5`) store _only_ the pointee/element type index — they carry no `Region` value at all. The textual printer therefore always renders the placeholder region `'local` for these three constructors, regardless of the pointer's actual provenance. The only two instructions that carry a real `Region` payload are `alloc` (`AllocInstr.region`) and `region_cast` (`RegionCastInstr.region`); a `Region` is one of `'static`, `'local`, `'heap`, or a named custom region (`Region.Custom([u8])`, printed verbatim as `'<name>`).

There is also no separate `SliceMut<T, 'r>` constructor in the in-memory type system: `ILSlice` carries a `mutable` flag (the surface `[mut T]`), which the front end checks, but both print as the one `Slice<T, 'local>` form and nothing after the front end distinguishes them. (`Box<T>` and `BoxMut<T>`, by contrast, _are_ distinct `ILType` variants — `ILTYPE_BOXED=3` / `ILTYPE_BOXEDMUT=4` — and print accordingly.)

### 3.3 Function Pointer Type

`fn(T1, T2, ...) -> R` — a pointer to a function with the given signature (one word). Variadic function pointers include `...` after the last parameter type.

A surface function value is two words, its code and its environment; the front end writes its type as the tuple `(fn(T1, ..) -> R, Ptr<unit, 'local>)`, builds one with `func_addr` and two stores, and calls one by loading both words and passing the environment as the callee's `__env` argument to `call_ptr`.

### 3.4 Tuple Type

`(T1, T2, ...)` — an anonymous product type, printed as a parenthesised, comma-separated type list. The empty tuple `()` is the `unit` type. A single-element tuple is printed with a trailing comma, `(T,)`, to distinguish it syntactically from a parenthesised type.

### 3.5 File Descriptor Type

`fd<r>`, `fd<w>`, `fd<rw>` — typed file descriptors with capability annotations. Linear type (non-copy, must be closed exactly once).

### 3.6 Async Context Type

`async_context` — abstract async I/O context (e.g., io_uring on Linux, kqueue on BSD). Linear type (non-copy, must be closed exactly once).

### 3.7 Type Variable and Generic Instance

- **`<name>` / `var`**: Type variable — printed as its source name (e.g. `T`) when known, or the literal `var` for anonymous/synthetic type variables with no interned name
- **`T<id><type_args>`**: Generic instance (e.g., `T7<i32>`) — a concrete instantiation of user-defined generic type `T7`

### 3.8 User-Defined Types

`T<id>` references a `struct` or `sum` type definition by numeric ID. Nominal typing: two user-defined types are equal only if their IDs match.

## 4. Type Lattice and Coercion Rules

### 4.1 Lattice Structure

The Zoril IL type system forms a bounded partial order with:

- **Reflexivity**: T \<: T for all T.
- **Antisymmetry**: If S \<: T and T \<: S then S = T.
- **Transitivity**: If R \<: S and S \<: T then R \<: T.

### 4.2 Subtyping (Assignability)

A type S is assignable to T (S \<: T) if any of the following hold:

1. **Identity**: S and T are the same type.
1. **Numeric widening** (explicit `cast` only): Signed integers widen along i8 \<: i16 \<: i32 \<: i64; unsigned along u8 \<: u16 \<: u32 \<: u64. Implicit coercion does not apply; a `move` instruction with type mutation is required.
1. **Region covariance**: Ptr\<T, 'rs> \<: Ptr\<T, 'rt> when 'rs outlives 'rt. The pointee type T must be identical (invariant).
1. **Nominal identity**: User-defined types (Tn) are assignable only if their numeric IDs match.
1. **Mutability**: PtrMut\<T, 'r> is assignable to Ptr\<T, 'r> (mutable to immutable coercion).

### 4.3 Copy vs. Move Semantics

- **Copy**: All primitives (u8-u64, i8-i64, f32, f64, bool, char, unit, never), Ptr\<T, 'r>, structurally-copy user-defined types (Tn where all fields are Copy and no Drop impl)
- **Move**: Box<T>, BoxMut<T>, Slice<T, 'r>, [T; N], fd, async_context, user-defined types (Tn) that contain at least one Move field or implement Drop

Copy types may be freely duplicated. Move types obey linear ownership — each value may be used exactly once. The verifier tracks Move values through the ownership state machine: AVAILABLE -> MOVED (on any consuming use).

A user-defined type Tn is **structurally Copy** if every field is Copy and the type has no Drop implementation. The compiler determines this recursively at the point of use; if any field transitively contains a Move type (Box<T>, Slice<T>, [T; N], fd, async_context, or another non-copy Tn), the containing type is Move. Types with a Drop impl are always Move.

The `never` type is the bottom type: a value of type `never` is assignable to any type, because the expression that produced it never actually yields a value (control diverges via `return`, `break`, or `continue`). The verifier treats uses of `never`-typed operands in unreachable blocks as valid — they will never execute.

### 4.4 Region Outlives Relation

- `'static` is the longest-lived region (outlives everything).
- `'local` is the current function's stack frame.
- `'heap` is the heap region (used by Box<T>).
- A Ptr may be coerced (via `region_cast`) to a shorter-lived region.

### 4.5 Variance Summary

| Constructor        | Region    | Pointee / Element   |
| ------------------ | --------- | ------------------- |
| Ptr\<T, 'r>        | Covariant | Invariant           |
| PtrMut\<T, 'r>     | Covariant | Invariant           |
| Box<T> / BoxMut<T> | —         | Invariant           |
| Slice<T, 'r>       | —         | Invariant           |
| [T; N]             | —         | Invariant           |
| Tn (struct/sum)    | —         | Invariant (nominal) |

## 5. Instruction Set

### 5.1 Arithmetic (12 opcodes)

`vN: T = <op> vA, vB` for the binary forms; `vN: T = <op> vA` for the two unary forms (`neg`, `not`).

| Opcode | Description                        |
| ------ | ---------------------------------- |
| `add`  | Addition                           |
| `sub`  | Subtraction                        |
| `mul`  | Multiplication                     |
| `div`  | Division                           |
| `rem`  | Remainder (modulo)                 |
| `neg`  | Arithmetic (sign) negation — unary |
| `not`  | Bitwise complement — unary         |
| `and`  | Bitwise AND                        |
| `or`   | Bitwise OR                         |
| `xor`  | Bitwise XOR                        |
| `shl`  | Left shift                         |
| `shr`  | Right shift                        |

Binary-form operands must have the same type. Works for integer and floating-point types (`neg` also applies to floats; `not` is integer/bool-only).

### 5.2 Comparison (6 opcodes)

`vN: bool = <op> vA, vB`

| Opcode   | Description           |
| -------- | --------------------- |
| `cmp_lt` | Less than             |
| `cmp_le` | Less than or equal    |
| `cmp_gt` | Greater than          |
| `cmp_ge` | Greater than or equal |
| `cmp_eq` | Equal                 |
| `cmp_ne` | Not equal             |

Result type is always `bool`. Operands must have matching types. Supports signed/unsigned integer comparison and floating-point comparison.

### 5.3 Explicit Overflow (3 opcodes)

`vN: T = <op> vA, vB`

- **`wrapping_add`**: Addition with wrapping on overflow
- **`saturating_add`**: Addition clamped to max value on overflow
- **`checked_add`**: Addition with overflow detection — currently lowered identically to `wrapping_add` (plain wrapping `add`) by the QBE backend; the `Option<T>`-returning checked semantics described by the surface-level API are not yet implemented in codegen

Only the `_add` forms exist as distinct opcodes (`IL_INSTR_WRAPPING_ADD`, `IL_INSTR_SATURATING_ADD`, `IL_INSTR_CHECKED_ADD`). `wrapping_sub`, `wrapping_mul`, `checked_sub`, and `checked_mul` have no `IL_INSTR_*` counterpart and no surface-level syntax that lowers to them.

### 5.4 Memory (4 opcodes)

| Opcode  | Syntax                                        | Description                         |
| ------- | --------------------------------------------- | ----------------------------------- |
| `alloc` | `vN: Ptr<T, 'r> = alloc 'r, T [, vAllocator]` | Allocate memory in region           |
| `load`  | `vN: T = load vP`                             | Load value from pointer             |
| `store` | `store vP, vV`                                | Store value to pointer              |
| `drop`  | `drop vV`                                     | Release owned value (Box, fd, etc.) |

The optional allocator operand on `alloc` allows custom allocators (arena, page, etc.). The front end does not emit one today: `box(allocator) expr` is rejected (§7.4 of the surface syntax) and `box expr` allocates on the global heap, so the operand is reachable only from hand-written ZIL.

### 5.5 Safety and Ownership (8 opcodes)

- **`bounds_check`**
  - Syntax: `bounds_check vI, vL`
  - Description: Assert index < length
- **`move`**
  - Syntax: `vN: T = move vS`
  - Description: Transfer ownership of a move-type value
- **`borrow` / `borrow_mut`**
  - Syntax: `vN: Ptr<T,'r> = borrow vS` / `vN: PtrMut<T,'r> = borrow_mut vS`
  - Description: Take an (im)mutable borrow of a value
- **`end_borrow`**
  - Syntax: `end_borrow vB`
  - Description: End the lifetime of a value produced by `borrow`/`borrow_mut`
- **`release`**
  - Syntax: `release vB`
  - Description: Release a borrowed/refcounted value outside of normal `drop` semantics
- **`region_cast`**
  - Syntax: `vN: Ptr<T, 'r2> = region_cast 'r2, vS`
  - Description: Cast pointer to a shorter-lived region
- **`cast`**
  - Syntax: `vN: T2 = cast vS`
  - Description: Numeric/pointer type conversion (`IL_INSTR_CAST`/`CastInstr{val, target_ty}`; there is no separate `bitcast` opcode)

`borrow`/`borrow_mut` are two textual spellings of a single instruction (`ILInstr.Borrow{val, is_mut}` / `IL_INSTR_BORROW`); the printed mnemonic is chosen by the `is_mut` flag, mirroring how `Box`/`BoxMut` share one `Boxed`/`BoxedMut` family but `Ptr`/`PtrMut` are distinct types.

**Reserved, not yet emitted**: `borrow`, `borrow_mut`, `end_borrow`, and `release` are fully defined in `ILInstr` and handled by the verifier (which treats `end_borrow`/`release` as ending a borrow's lifetime by marking the borrower SSA value `Moved`) and by the textual printer, but **no lowering pass currently constructs them** — `grep`-ing the lowering sources for `ILInstr.Borrow`/`EndBorrow`/`Release` turns up only the `enum`/accessor definitions, the verifier's handling, and the printer's emission code. A textual ZIL reader/parser must still accept them (they are part of the grammar and may appear in hand-written or future-emitted ZIL), but real `--emit-zil` output will not contain them today.

### 5.6 Slice Operations (4 opcodes)

| Opcode            | Syntax                                          | Description                                               |
| ----------------- | ----------------------------------------------- | --------------------------------------------------------- |
| `slice_load`      | `vN: T = slice_load vS, vI`                     | Load element from slice at index                          |
| `slice_store`     | `slice_store vS, vI, vV`                        | Store element to slice at index                           |
| `slice_len`       | `vN: u64 = slice_len vS`                        | Get slice length                                          |
| `slice_construct` | `vN: Slice<T, 'local> = slice_construct vP, vL` | Create a fat-pointer slice from a data pointer and length |

`slice_data` (extracting the raw data pointer from a fat slice) has no `IL_INSTR_*` counterpart and is not emitted; it has been removed from this revision of the spec. Element addressing for slices is performed inline by `slice_load`/`slice_store` (see also `field_addr`/§5.9 for struct-field addressing — there is likewise no separate `elem_addr` opcode).

### 5.7 Array Operations (3 opcodes)

| Opcode            | Syntax                                     | Description                      |
| ----------------- | ------------------------------------------ | -------------------------------- |
| `array_construct` | `vN: [T; N] = array_construct v1, v2, ...` | Build array from elements        |
| `array_load`      | `vN: T = array_load vA, vI`                | Load element from array at index |
| `array_store`     | `array_store vA, vI, vV`                   | Store element to array at index  |

### 5.8 Sum Type / Option Operations (4 opcodes)

| Opcode          | Syntax                                      | Description                                           |
| --------------- | ------------------------------------------- | ----------------------------------------------------- |
| `is_some`       | `vN: bool = is_some vO`                     | Test if option/sum has payload                        |
| `unwrap`        | `vN: Ptr<T, 'local> = unwrap vO`            | Extract a pointer to the payload (must be guarded)    |
| `variant_match` | `vN: bool = variant_match vS, T<id>, <idx>` | Test whether `vS`'s active variant tag equals `<idx>` |
| `sum_construct` | `vN: Tn = sum_construct T<id>, <idx>, vP`   | Construct enum variant                                |

**`variant_match` is a value-producing comparison, not a branch.** In the `ILInstr.VariantMatch` representation (`VariantMatchInstr{val, type_id, variant_idx}` — no block-ID fields), it is typed as `bool` and produces an ordinary SSA value that a _separate_ `branch` instruction then consumes as its condition:

```zil
v18: bool = variant_match v2, T18, 0
branch v18, @b3, @b4
```

**`unwrap` yields a pointer, not the payload value.** `ILInstr.Unwrap(SSAId)` is typed by the builder as `Ptr<T, 'local>` (a pointer to the payload storage), which the caller then `load`s if it needs the value by-value — e.g. `v45: Ptr<u32, 'local> = unwrap v2` followed by `v46: u32 = load v45`.

**Note on variant indices:** The `<idx>` operand in `variant_match` and `sum_construct` refers to the **declaration index** (0-based) of the variant in the `TypeDef`. However, if the variant was defined with an **explicit tag** in the surface syntax (e.g., `Variant = 42`), the compiler utilizes that tag value for the machine-level comparison in `variant_match` and for storage in `sum_construct`.

### 5.9 Aggregate Construction (2 opcodes)

- **`struct_construct`**
  - Syntax: `vN: Tn = struct_construct T<id>[, v1, v2, ...]`
  - Description: Build a struct value from per-field SSA values (the comma before the field list is omitted when there are no fields)
- **`tuple_construct`**
  - Syntax: `vN: (T1, ...) = tuple_construct v1, v2, ...`
  - Description: Build a tuple value from element SSA values

These two opcodes (`IL_INSTR_STRUCT_CONSTRUCT` / `IL_INSTR_TUPLE_CONSTRUCT`), together with `array_construct` (§5.7), are how the compiler materialises aggregate literals as single SSA values before storing or returning them.

### 5.10 Control Flow (12 opcodes)

- **`call`**
  - Syntax: `vN: T = call <target>(v1, v2, ...)`
  - Description: Call function by ID or by name
- **`call_ptr`**
  - Syntax: `vN: T = call_ptr vF(v1, v2, ...)`
  - Description: Indirect call via function pointer (`vF`'s args list does **not** include a separate environment operand in the textual form — see `CallPtrInstr.env_ssa`, which the printer currently does not emit)
- **`ret`**
  - Syntax: `ret vV` or bare `ret`
  - Description: Return from function; the bare form is used when the function returns `unit`/`never` (`Ret`'s SSA operand is `NO_SSA`, i.e. `0xffffffff`)
- **`branch`**
  - Syntax: `branch vC, @bT, @bE`
  - Description: Conditional jump — `vC` must be `bool`
- **`jump`**
  - Syntax: `jump @bT`
  - Description: Unconditional jump
- **`const`**
  - Syntax: `vN: T = const <value>`
  - Description: Load an integer, float, or boolean constant (`true`/`false` for `bool`; floats print with exactly 6 fractional digits)
- **`phi`**
  - Syntax: `vN: T = phi [@b1: v1, @b2: v2, ...]`
  - Description: SSA phi node
- **`global_addr`**
  - Syntax: `vN: Ptr<T, 'static> = global_addr g<id>`
  - Description: Address of global variable
- **`func_addr`**
  - Syntax: `vN: fn(...) -> T = func_addr f<id>`
  - Description: Address of function (for fn ptrs)
- **`field_addr`**
  - Syntax: `vN: Ptr<F, 'r> = field_addr vS, <idx>`
  - Description: Address of struct field `<idx>` (0-based declaration index)
- **`string_const`**
  - Syntax: `vN: Slice<u8, 'local> = string_const "..."`
  - Description: String literal constant (escaped with `\n`/`\r`/`\t`/`\"`/`\\`/`\xHH`)
- **`syscall`**
  - Syntax: `vN: T = syscall vNum, v1, v2, ...`
  - Description: Direct kernel system call

**`call`'s target is `f<id>` when the callee resolves to a function defined in this module, or a bare identifier (e.g. `call memcpy(...)`) for external/runtime functions that have no corresponding `ILFunction`** (resolution is via `ILModule.find_function_by_name`, falling back to the raw interned name string — `CallInstr{args, name_id, is_extern}`).

**`syscall`'s `num` operand is an SSA value reference (`vNum`), not a literal integer** — `SyscallInstr{num: SSAId, args: [SSAId]}` stores the syscall number itself as an SSA value that must be defined (typically by a preceding `const`); it is not a literal integer. The instruction is lowered to a call to the assembly runtime function `__zoril_syscall_N`, where `N` is the argument count. The underlying implementation is platform-specific: on x86_64 Linux/OpenBSD these stubs place the arguments into the correct System V ABI registers (`rax`, `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`) and execute the `syscall` instruction; on aarch64 the `svc` instruction is used with the ARM calling convention.

There is no generic `elem_addr` opcode: array/slice element access goes through `array_load`/`array_store`/`slice_load`/`slice_store` directly.

### 5.11 Function Parameters and Optimization Hints (4 opcodes)

- **`param`**
  - Syntax: `vN: T = param <idx>`
  - Description: Materialise incoming argument `<idx>` as an SSA value at function entry (see §2 for when this is emitted)
- **`likely`**
  - Syntax: `vN: bool = likely vC`
  - Description: Branch-prediction hint: `vC` is likely `true`
- **`unlikely`**
  - Syntax: `vN: bool = unlikely vC`
  - Description: Branch-prediction hint: `vC` is likely `false`
- **`get_env`**
  - Syntax: `vN: T = get_env`
  - Description: Fetch the current function's captured-environment pointer (used by closure lowering)

**Reserved, not yet emitted**: like the borrow-tracking opcodes in §5.5, `likely` and `unlikely` are fully defined and handled by the verifier/printer but are never constructed by any current lowering pass — no optimization-hint instrumentation pass exists yet. `param` and `get_env`, by contrast, **are** actively emitted (`src/lower_zir_to_zil.zrl`).

### 5.12 File Descriptor I/O (4 opcodes)

- **`fd_open`**
  - Syntax: `vN: fd<cap> = fd_open vP, <flags>, <mode>`
  - Description: Open file (`<flags>`/`<mode>` are literal integers — `FDOpenInstr{path, flags: u64, mode: u64}`, not SSA references)
- **`fd_close`**
  - Syntax: `fd_close vF`
  - Description: Close file descriptor (consumes fd)
- **`fd_read`**
  - Syntax: `vN: i64 = fd_read vF, vBuf`
  - Description: Read from fd into buffer (requires read cap)
- **`fd_write`**
  - Syntax: `vN: i64 = fd_write vF, vBuf`
  - Description: Write buffer to fd (requires write cap)

`fd_read`/`fd_write` take exactly **two** SSA operands — `FDIOInstr{fd, buf}` carries no separate count operand. The transfer length is presumably derived from `vBuf`'s slice length by the lowering/codegen layer.

### 5.13 Async I/O Ring (3 opcodes)

- **`async_setup`**
  - Syntax: `vN: async_context = async_setup vE`
  - Description: Create async mechanism instance
- **`async_enter`**
  - Syntax: `vN: i64 = async_enter vR, <to_submit>, <min_complete>`
  - Description: Submit/wait for completions — `<to_submit>`/`<min_complete>` are literal `u32` counts (`IORingEnterInstr{ring, to_submit: u32, min_complete: u32}`), not SSA references
- **`async_close`**
  - Syntax: `async_close vR`
  - Description: Close async_context (consumes it)

## 6. Safety Rules and Error Catalog

The Zoril Verifier ensures safety by checking for the following rules.

### 6.1 Ownership and Move Semantics

Non-copy types are moved on assignment/call. Use-after-move is a verification error.

| Error Code                  | Description                                     |
| --------------------------- | ----------------------------------------------- |
| `VERIFY_ERR_USE_AFTER_MOVE` | Owned value used after being moved              |
| `VERIFY_ERR_DOUBLE_DROP`    | Value dropped more than once                    |
| `VERIFY_ERR_LEAK`           | Owned value not consumed before function return |

### 6.2 Region and Lifetime Discipline

A pointer cannot outlive its region. `'static` outlives everything.

| Error Code                    | Description                 |
| ----------------------------- | --------------------------- |
| `VERIFY_ERR_REFERENCE_ESCAPE` | Pointer outlives its region |

### 6.3 Bounds Discipline

`slice_load`, `slice_store`, `array_load`, and `array_store` require a dominating `bounds_check` on the same (collection, index) SSA pair before any access.

An access at block B, instruction k is safe if there exists a block D and instruction j such that:

1. D dominates B (or D = B and j < k), and
1. Instruction j in D is `bounds_check` on the same (collection, index) pair.

The verifier precomputes a checked-pair set for each block using a forward dominator-tree walk.

| Error Code                        | Description                                       |
| --------------------------------- | ------------------------------------------------- |
| `VERIFY_ERR_MISSING_BOUNDS_CHECK` | Collection access without dominating bounds check |

### 6.4 Type Safety

| Error Code                 | Description                        |
| -------------------------- | ---------------------------------- |
| `VERIFY_ERR_TYPE_MISMATCH` | Instruction operand has wrong type |

### 6.5 Sum Type Safety

`unwrap` on an Option/Result requires a dominating guard (`is_some` or `variant_match`) that confirms the variant before extraction.

| Error Code                    | Description                             |
| ----------------------------- | --------------------------------------- |
| `VERIFY_ERR_UNHANDLED_OPTION` | Unwrap without dominating variant guard |

### 6.6 Mutability Enforcement

Stores through immutable pointers (`Ptr<T, 'r>`) are rejected. `PtrMut<T, 'r>`, `Box<T>`/`BoxMut<T>` (both heap-owning, addressed the same way at the IL level) permit store operations; surface-level mutability of the boxed value is distinguished by the `Box<T>` vs `BoxMut<T>` constructor (`ILTYPE_BOXED` vs `ILTYPE_BOXEDMUT`), mirroring `Ptr<T, 'r>` vs `PtrMut<T, 'r>`.

### 6.7 Linear Resource Rules

File descriptors (`fd`) and I/O rings (`async_context`) are linear resources:

- Must be consumed (closed) exactly once.
- Capability checking: `fd_read` rejects `fd<w>`; `fd_write` rejects `fd<r>`.
- `fd_close` and `async_close` move/consume the resource.
- `async_enter` borrows the ring (non-consuming).
- Unclosed resources at function return produce `VERIFY_ERR_LEAK`.

### 7. Complete Opcode Summary

Total: 68 opcodes (one per `IL_INSTR_*` constant in `src/il_instr.zrl`, `IL_INSTR_ADD = 0` through `IL_INSTR_RELEASE = 67`; `borrow`/`borrow_mut` share a single constant, `IL_INSTR_BORROW`, distinguished by the `is_mut` flag — see §5.5).

- **Arithmetic**
  - Count: 12
  - Opcodes: add, sub, mul, div, rem, neg, not, and, or, xor, shl, shr
- **Comparison**
  - Count: 6
  - Opcodes: cmp_lt, cmp_le, cmp_gt, cmp_ge, cmp_eq, cmp_ne
- **Overflow**
  - Count: 3
  - Opcodes: wrapping_add, saturating_add, checked_add
- **Memory**
  - Count: 4
  - Opcodes: alloc, load, store, drop
- **Safety & Ownership**
  - Count: 7
  - Opcodes: bounds_check, move, borrow / borrow_mut, end_borrow, release, region_cast, cast
- **Slice**
  - Count: 4
  - Opcodes: slice_load, slice_store, slice_len, slice_construct
- **Array**
  - Count: 3
  - Opcodes: array_construct, array_load, array_store
- **Sum type**
  - Count: 4
  - Opcodes: is_some, unwrap, variant_match, sum_construct
- **Aggregate construction**
  - Count: 2
  - Opcodes: struct_construct, tuple_construct
- **Control**
  - Count: 12
  - Opcodes: call, call_ptr, ret, branch, jump, const, phi, global_addr, func_addr, field_addr, string_const, syscall
- **Function params & hints**
  - Count: 4
  - Opcodes: param, likely, unlikely, get_env
- **File I/O**
  - Count: 4
  - Opcodes: fd_open, fd_close, fd_read, fd_write
- **Async I/O**
  - Count: 3
  - Opcodes: async_setup, async_enter, async_close

(12+6+3+4+7+4+3+4+2+12+4+4+3 = 68.)

The opcodes `borrow`/`borrow_mut`, `end_borrow`, `release`, `likely`, and `unlikely` are _reserved_: defined and handled by the verifier/printer, but never constructed by any lowering pass today (§5.5, §5.11).

## 8. Runtime Environment

A Zoril-compatible runtime or assembly stub must provide the following symbols for linking:

- **`_start`**: Entry point for the executable. Initializes the environment and calls `main`.
- **`__zoril_syscall_N`**: Assembly stubs for system calls (N=0..6).
- **`memcpy`**: Efficient memory copy (used for struct/enum assignment).
- **`memcmp`**: Memory comparison (used for string/slice equality).
- **`malloc` / `free`**: Basic memory management for `Box<T>` (lowerable to `mmap`/`munmap`).
- **`abort`**: Emergency termination (e.g., on verifier failure or stack overflow).
- **`zoril_panic`**: User-facing panic handler.
