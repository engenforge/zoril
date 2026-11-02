# Zoril Application Binary Interface (ABI) and Data Layout

This document defines the canonical Data Layout and Application Binary Interface (ABI) for the Zoril programming language. Both the bootstrap compiler (`zoril-c`) and the self-hosted compiler (`zoril`) MUST adhere to these rules to ensure binary compatibility and correct memory semantics.

## 1. Primitive Types

All primitive types have a natural size and alignment:

| Type                  | Size (Bytes) | Alignment (Bytes) | Notes                                                               |
| :-------------------- | :----------- | :---------------- | :------------------------------------------------------------------ |
| `unit`                | 0            | 1                 | Zero-sized type.                                                    |
| `bool`                | 1            | 1                 | 0 = false, 1 = true.                                                |
| `u8`, `i8`            | 1            | 1                 |                                                                     |
| `u16`, `i16`          | 2            | 2                 |                                                                     |
| `u32`, `i32`, `f32`   | 4            | 4                 |                                                                     |
| `u64`, `i64`, `f64`   | 8            | 8                 |                                                                     |
| `usize`, `isize`      | 8            | 8                 | Pointer-sized; 8 bytes on every current target.                     |
| `ptr`, `box`          | 8            | 8                 | Pointer to memory.                                                  |
| `fn`                  | 16           | 8                 | Function value: code, then environment (null for a named function). |
| `extern "C" fn(..)`   | 8            | 8                 | C function pointer: the code address alone, no environment.         |
| `fd`, `async_context` | 8            | 8                 | Resource handles.                                                   |

## 2. Compound Types

### 2.1 Tuples and Structs

- Fields are laid out in the **exact order** of their declaration.
- Each field is aligned to its natural alignment requirements. Padding bytes are inserted before a field if the current offset is not a multiple of the field's alignment.
- The alignment of the tuple/struct itself is the maximum alignment among all of its fields (or 1 if empty).
- The total size of the tuple/struct is padded at the end to be a multiple of its overall alignment.

**Promise.** For a `struct` whose fields all have a C layout (primitives, raw pointers, references as pointers, arrays of those, nested such structs, and zero-sized fields, which contribute nothing), this is the C layout and a stable promise (`doc/STABILITY.md`, "Struct layout"), pinned by `scripts/test_struct_layout.sh` against the host C compiler. A field of an unpromised type (`enum`, tuple, slice, `Box`) removes the promise for the whole struct. Tuples, enums, slices and `Box` carry no layout promise.

### 2.2 Arrays

- An array `[T; N]` is laid out as `N` contiguous elements of type `T`.
- The size of an array is `N * padded_size(T)`.
- The alignment of the array is the alignment of `T`.

### 2.3 Slices

- A slice `[T]` (or `str`) at runtime is a "fat pointer" consisting of a pointer and a length.
- Layout:
  1. `ptr`: 8 bytes (alignment 8)
  2. `len`: 8 bytes (`usize`, alignment 8)
- Total size: 16 bytes. Alignment: 8 bytes.

## 3. Sum Types (Enums)

Enums in Zoril are discriminated unions (tagged unions).

### 3.1 Tag Numbering

- Variants are assigned integer tags starting from `0` and incrementing by 1 in declaration order, unless explicitly overridden.
- If a variant has an explicit tag (e.g., `A = 10`), subsequent variants without explicit tags continue incrementing from that value (e.g., `11`, `12`).

### 3.2 Layout Rules

The layout of a sum type is composed of a `tag` followed by a `payload`.

1. **Tag:** The tag is a 32-bit unsigned integer (`u32`), taking 4 bytes and having an alignment of 4 bytes.
2. **Payload Offset:** The payload begins after the tag, with padding inserted to satisfy the alignment requirements of the largest variant's payload.
   ```
   payload_offset = align_to(4, max_variant_align)
   ```
3. **Alignment:** The alignment of the entire enum is the maximum of the tag's alignment (4) and the `max_variant_align`.
   ```
   enum_align = max(4, max_variant_align)
   ```
4. **Total Size:** The total size is the `payload_offset` plus the size of the largest variant payload (`max_variant_size`), padded to a multiple of `enum_align`.
   ```
   total_size = align_to(payload_offset + max_variant_size, enum_align)
   ```

_Note: Future optimizations may introduce "Compact Enums" which use `u8` or `u16` tags for enums with fewer variants, provided the overall alignment rules are respected. Until such optimizations are fully specified and implemented in both compilers, the 4-byte tag is standard._

## 4. Calling Conventions

### 4.1 Small Values

Values $\le$ 16 bytes (primitives, pointers, slices, small structs) are typically passed in registers according to the target architecture's standard C ABI (e.g., System V AMD64 ABI).

A function value (`fn(..) -> R`, 16 bytes: code, then environment) is passed by value as the aggregate `{ l, l }`, which the System V classification puts in two integer registers. It is returned through `sret` like other aggregates.

### 4.2 Large Aggregates

Values $>$ 16 bytes (large structs, large enums) must be passed by reference.

- **Arguments:** The caller allocates space on its stack, copies the aggregate into that space, and passes a pointer to the callee.
- **Return Values (sret):** The caller allocates space for the return value and passes a pointer to this space as an implicit first argument. The callee writes the return value directly into this pointer.

## 5. Name Mangling

Symbols are mangled from their module path, type and name, as described in `modular_compilation.md` §3.1; methods are mangled as components `(type, method)`. Only `main` and `extern "C"` functions keep plain names. No mangled name is a name in the language.

## 6. Stable Integer Tags for Internal Enums

The following integer tags are used by the bootstrap compiler (`zoril-c`) in its serialized metadata format. The self-hosted compiler MUST use these same values when reading or writing that metadata. These tags govern the bootstrap compiler's on-disk representation and are distinct from the in-memory `ILInstr` enum variant tags used by the self-hosted compiler at runtime (which are an internal implementation detail, not a cross-compiler contract).

### 6.1 IL Type Kinds (`ILTypeKind`)

| Tag | Name         | Tag | Name                     |
| :-- | :----------- | :-- | :----------------------- |
| 0   | `IL_TY_UNIT` | 14  | `IL_TY_SLICE`            |
| 1   | `IL_TY_BOOL` | 15  | `IL_TY_ARRAY`            |
| 2   | `IL_TY_U8`   | 16  | `IL_TY_SUM`              |
| 3   | `IL_TY_U16`  | 17  | `IL_TY_STRUCT`           |
| 4   | `IL_TY_U32`  | 18  | `IL_TY_VAR`              |
| 5   | `IL_TY_U64`  | 19  | `IL_TY_GENERIC_INSTANCE` |
| 6   | `IL_TY_I8`   | 20  | `IL_TY_FD`               |
| 7   | `IL_TY_I16`  | 21  | `IL_TY_ASYNC_CONTEXT`    |
| 8   | `IL_TY_I32`  | 22  | `IL_TY_FN`               |
| 9   | `IL_TY_I64`  | 23  | `IL_TY_TUPLE`            |
| 10  | `IL_TY_F32`  | 24  | `IL_TY_NEVER`            |
| 11  | `IL_TY_F64`  | 25  | `IL_TY_USIZE`            |
| 12  | `IL_TY_PTR`  | 26  | `IL_TY_ISIZE`            |
| 13  | `IL_TY_BOX`  |     |                          |

### 6.2 Surface AST Node Kinds

#### 6.2.1 Expressions (`ExprKind`)

| Tag | Name          | Tag | Name           |
| :-- | :------------ | :-- | :------------- |
| 0   | `EXPR_INT`    | 12  | `EXPR_STRING`  |
| 1   | `EXPR_FLOAT`  | 13  | `EXPR_UNARY`   |
| 2   | `EXPR_BOOL`   | 14  | `EXPR_BOX`     |
| 3   | `EXPR_VAR`    | 15  | `EXPR_CAST`    |
| 4   | `EXPR_BINARY` | 16  | `EXPR_TRY`     |
| 5   | `EXPR_CALL`   | 17  | `EXPR_ARRAY`   |
| 6   | `EXPR_BLOCK`  | 18  | `EXPR_INDEX`   |
| 7   | `EXPR_IF`     | 19  | `EXPR_CLOSURE` |
| 8   | `EXPR_WHILE`  | 20  | `EXPR_TUPLE`   |
| 9   | `EXPR_STRUCT` | 21  | `EXPR_SIZEOF`  |
| 10  | `EXPR_MEMBER` | 22  | `EXPR_ALIGNOF` |
| 11  | `EXPR_MATCH`  | 23  | `EXPR_RETURN`  |

#### 6.2.2 Statements (`StmtKind`)

| Tag | Name            | Tag | Name            |
| :-- | :-------------- | :-- | :-------------- |
| 0   | `STMT_RESERVED` | 4   | `STMT_FOR`      |
| 1   | `STMT_RETURN`   | 5   | `STMT_BREAK`    |
| 2   | `STMT_EXPR`     | 6   | `STMT_CONTINUE` |
| 3   | `STMT_LET`      | 7   | `STMT_DEFER`    |

#### 6.2.3 Patterns (`PatternKind`)

| Tag | Name              | Tag | Name            |
| :-- | :---------------- | :-- | :-------------- |
| 0   | `PATTERN_VARIANT` | 3   | `PATTERN_CHAR`  |
| 1   | `PATTERN_INT`     | 4   | `PATTERN_RANGE` |
| 2   | `PATTERN_BOOL`    | 5   | `PATTERN_WILD`  |

#### 6.2.4 Type Definitions (`TypeDefKind`)

| Tag | Name              |
| :-- | :---------------- |
| 0   | `TYPE_DEF_STRUCT` |
| 1   | `TYPE_DEF_ENUM`   |

## 7. Compiler Internal Invariants

This section defines the internal conventions used by the Zoril compilers to ensure interoperability.

### 7.1 SSA Value Numbering

SSA IDs (`vN`) are local to a function and start at `v1`.

1. **Implicit Parameters:**
   - **`v1`**: Reserved for the `sret` (structural return) pointer if the function returns a large aggregate (> 16 bytes).
   - **Implicit Context Pointer**: Only a closure takes one: an implicit `Ptr<unit, 'local>` parameter named `__env`, its _last_ parameter, through which it reads its captured-environment tuple. A call through a function value passes the value's environment word after the arguments; a plain function has no such parameter and never reads it (under the System V ABI the caller owns the argument area, so an extra trailing argument is harmless). Plain functions, `main` and externs take no context pointer.
2. **Explicit Parameters:** Assigned in declaration order immediately following any implicit parameters.
3. **Internal Values:** Instruction result IDs continue incrementing from the last parameter ID.
4. **Sentinel:** `v0` is reserved as a "null/invalid" sentinel and must never be assigned as an instruction result.

### 7.2 Hardcoded Region IDs

The following region IDs are reserved and must be used exactly as defined:

| Region Name | Hex ID       | Description                    |
| :---------- | :----------- | :----------------------------- |
| `'static`   | `0xFFFFFFF1` | Global/Static lifetime.        |
| `'local`    | `0xFFFFFFF2` | Function stack frame lifetime. |
| `'heap`     | `0xFFFFFFF3` | Heap-allocated (Box) lifetime. |

### 7.3 Name Mangling Rules

#### 7.3.1 Type Mangling

The canonical mangling for types is:

- **Primitives:** `u8`, `u16`, `u32`, `u64`, `i8`, `i16`, `i32`, `i64`, `f32`, `f64`, `bool`, `unit`, `usize`, `isize`.
- **Pointers:** `p` + `<pointee>` (e.g., `&u32` -> `pu32`).
- **Boxes:** `b` + `<pointee>` (e.g., `Box<i32>` -> `bi32`).
- **Slices:** `s` + `<element>` (e.g., `[u8]` -> `su8`).
- **Arrays:** `a` + `<length>` + `<element>` (e.g., `[u8; 10]` -> `a10u8`).
- **Tuples:** `t` + `<element1>` + `<element2>`... (e.g., `(u8, i32)` -> `tu8i32`).
- **Methods:** `<TypeName>_<methodName>` (e.g., `Point_new`).
- **Generics:** Pre-mangled during lowering to `<BaseName>_<Arg1>_<Arg2>` (e.g., `Option_i32`).

#### 7.3.2 Symbol Mangling & Link Invariant

Modern Zoril symbols (functions, methods, statics) are mangled using the injective length-prefixed format defined in `doc/spec/modular_compilation.md §3.1`:

```
<mangled>   ::= "z" <comp>+ "E"
<comp>      ::= <len> <ident>
<len>       ::= [1-9][0-9]*
```

Special symbols preserved unmangled (bare names):

- `main`, `abort`, `malloc`, `free`
- `__zoril_syscall_*`
- `zoril_main`, the entry of a program built with `--hosted` (see below)
- Functions declared with `extern "C"`, and functions Zoril defines with `extern "C" fn name(..) { body }` (exported for C to call)

**Hosted mode.** `zoril --hosted` names the program's entry `zoril_main`. The HOSTED branch of `rt/runtime.s` (assembled with `as --defsym HOSTED=1` into `runtime_hosted.o`) replaces the default entry and libc's names: it defines no `_start`, `memcpy`, `memset`, `memcmp`, `write`, `abort`, `malloc` or `free` (libc owns them, and `abort` is the trap), defines the `main(argc, argv)` that C startup code calls, and keeps the Zoril-only names (`__zoril_syscall_N`, `zoril_argc`, `zoril_argv`, `zoril_slice_eq`, `zoril_allocator_alloc`, `zoril_abort`, the io_uring wrappers). The program links with `cc`; its result is returned to C startup code, which calls `exit`.

> **Link Invariant:** Object files may only be linked with objects from the same emitter generation. Bootstrap stages (e.g. stage0-C) and modern self-hosted tools maintain internal symbol consistency; cross-generation linking is unsupported.

### 7.4 Zero-Sized Type (ZST) Handling

- `unit` (and `never`) have **size 0** and **alignment 1**.
- **Passing:** ZSTs are completely omitted from machine-level function arguments and return values.
- **Storage:** ZST fields in structs occupy 0 bytes. A struct containing only ZST fields has size 0.
- **Operations:** Loads and stores of ZSTs are treated as no-ops by the backend.

### 7.5 Built-in Intrinsic Signatures

The compiler expects the following symbols to be provided by the runtime:

- `memcpy(l %dest, l %src, l %size)`
- `memcmp(l %p1, l %p2, l %size) -> w` (returns 0 if equal)
- `memset(l %dest, w %val, l %size)`
- `zoril_allocator_alloc(l %arena, l %size) -> l` (returns pointer)
- `__zoril_syscall_0` through `__zoril_syscall_6` (register-based syscall wrappers)
- `abort()` (emergency termination)

### 7.6 Constant Folding Arithmetic

The compiler performs constant folding using 64-bit unsigned integers for all integral types. To maintain correctness:

- Intermediate results MUST be truncated to the target type's bit-width (e.g., `& 0xFFFFFFFF` for `u32/i32`) before performing comparisons or further operations.
- This ensures that signed overflow behaves correctly during compile-time evaluation (e.g., `i32::MAX +% 1` correctly becomes a negative value for the purpose of a `< 0` comparison).
