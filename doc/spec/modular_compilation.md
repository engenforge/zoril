# Zoril Modular Compilation and Artifact Caching Specification

This specification defines the formal compilation unit boundaries, interface summary format (`.zri`), symbol mangling rules, dependency graph resolution, and artifact caching protocol for the Zoril programming language.

Adherence to this specification ensures that Zoril toolchains can perform separate compilation of independent modules and sub-second incremental touch rebuilds without whole-program inlining.

---

## 1. Compilation Units and Scopes

### 1.1 Translation Unit (TU)

A **Translation Unit (TU)** is defined as a single Zoril source file (`.zrl`) or a cohesive module directory compiled as an independent unit.

In modular compilation mode (`zoril -c <module.zrl>` or `zoril build --incremental`):

1. **Target Module**: The primary source file specified on the command line. The compiler produces machine code, debug symbols, and object symbols (`.o`) **only** for declarations belonging to the target module.
2. **Imported Modules**: Modules referenced via `import "<path>.zrl";`. Declarations loaded from imported modules provide type definitions, function signatures, constants, and generic templates required to compile the target module. **No machine code or object symbols are emitted for non-generic imported functions.**

A TU carries the impls its target module and that module's imports declare, and its method bodies are checked where they are lowered: `-c` checks the public methods of its target module, while a whole-program build checks every method of the program, called or not (`surface_syntax.md` §11.1.1, which also says why the two differ). Methods go with their type (`surface_syntax.md` §11.1.1), which a whole-program build reads as "any `impl T` in the program"; in `-c` the `impl` has to be in the TU, so a module that calls a method whose `impl` sits in a module it cannot import — the caller declares the type, the other module implements it and imports the caller — is rejected, with the note that names the limit. Such a graph is an SCC of the import-plus-impl relation; `KNOWN_ISSUES.md` §4 states the limit for users, and compilation groups are the planned post-release fix.

### 1.2 Visibility and Linkage

Zoril enforces lexical visibility at the module boundary:

- **`pub` Declarations**: Exported across module boundaries. Emitted with global linkage (ELF `STB_GLOBAL`, QBE `export`) in the module's object file (`.o`).
- **Non-`pub` (Private) Declarations**: Internal to the declaring module. Emitted with local linkage (ELF `STB_LOCAL`, QBE unexported) or inlined. Downstream modules attempting to access private declarations fail at resolve time.
- **Private declarations reachable from a public generic body**: A `pub` generic function (or a `pub` method of a generic impl, or of a method with its own type parameters) is instantiated in the _consumer's_ TU, so anything its body mentions must be linkable from there. Private functions and methods named in such a body (as `f()`, `x.m()`, or `T.m()`) are emitted with global linkage; the resolver still rejects any direct cross-module reference to them. The analysis over-approximates (it matches identifiers and member names in the body's expression range, so a local variable shadowing a private function name exports it needlessly) but never under-approximates. A private function that no public generic body mentions stays `STB_LOCAL`. Known limits: private _generic_ functions called by a public generic body are not carried in the `.zri`, and statics are data symbols local to their TU.
- **Top-Level `main`**: The program entry point must have public visibility and unmangled symbol name `main` (ELF `STB_GLOBAL`).

---

## 2. Module Interfaces (`.zri`)

To decouple compilation units and avoid downstream recompilations when an internal function body changes, Zoril defines the **Zoril Interface (`.zri`)** format.

### 2.1 Interface Contents

An interface summary contains the minimal syntactic declarations necessary for downstream typechecking and lowering:

1. **Public Structs**: All struct definitions and field types (including padding/alignment rules).
2. **Public Enums**: Variant tags, payloads, and discriminants.
3. **Public Type Aliases**: Aliased type targets.
4. **Public Constants**: Evaluated compile-time constant values.
5. **Public Function Signatures**: Function name, parameter types, and return type, terminated with a semicolon `;` (the function body `{ ... }` is omitted).
6. **Generic Definitions**: Full AST templates for generic structs, enums, functions, and traits, allowing downstream monomorphization.
7. **Module Identity and Imports**: A first line `// zri-module: <source path>` names the source module the interface describes, followed by one `import "<canonical source path>";` per module the source resolved (sorted, de-duplicated). The interface is therefore self-contained: a consumer resolves the types it mentions through the imports, and the interface hash covers what the module depends on. Imports in a `.zri` name canonical paths, not paths relative to where the `.zri` is stored.
8. **Escape Summaries**: `#[summary(escape, stash, ret_stack, alloc, storage, stores, into)]` on every non-generic exported function and method (§7.4). `alloc` (constant arena bytes the body allocates) is part of the interface on purpose: the verifier's interprocedural arena-capacity check reads it from imported functions, so a body edit that changes it must invalidate dependants. `storage`, `stores` and `into` are parameter bit masks the verifier computes from the body: the parameters whose own storage the result may point into, those whose storage the body writes outside its frame, and the parameters whose memory receives those writes (bit 63: a global or memory of unknown origin). A caller passing a pointer into its own frame uses them to reject the dangling result or write (`safety_model.md`, Region Escape rows). Edits that change none of these leave the `.zri` byte-identical.
9. **Private Declarations Used by Public Generic Bodies**: emitted without `pub` (signature only, or the full template if generic) with the same summary annotation, so the body can be instantiated and linked in the consumer (§1.2). They remain unnameable from outside the module.

An imported function whose interface carries no `#[summary]` is an unknown callee: the interprocedural pass assumes it stashes every pointer-like parameter and may return any of them (never the optimistic all-zero masks).

### 2.2 Concrete Syntax Example

Given source module `math.zrl`:

```zrl
pub struct Vec2 {
    pub x: i64,
    pub y: i64,
}

fn private_dot(a: &Vec2, b: &Vec2) -> i64 {
    return a.x * b.x + a.y * b.y;
}

pub fn length_sq(v: &Vec2) -> i64 {
    return private_dot(v, v);
}
```

The generated interface `math.zri` is:

```zrl
// zri-module: math.zrl
pub struct Vec2 {
    pub x: i64,
    pub y: i64,
}

#[summary(escape = 0, stash = 0, ret_stack = false, alloc = 0, storage = 0, stores = 0, into = 0)]
pub fn length_sq(v: &Vec2) -> i64;
```

### 2.3 Early-Cutoff Invalidation Rule

When a source file `M.zrl` is modified:

1. The compiler lowers `M.zrl` and derives its new interface `M.zri`.
2. The cryptographic fingerprint `H_new = SHA256(M.zri)` is compared against `H_prev`:
   - **Case 1 (`H_new != H_prev`)**: The public interface changed (e.g. signature or struct layout modified). All modules transitively depending on `M` are marked dirty and scheduled for recompilation.
   - **Case 2 (`H_new == H_prev`)**: Only internal implementation details changed (e.g. function body edit). `M.o` is updated, but **all downstream dependants skip recompilation**. The build proceeds directly to the link step.

---

## 3. Symbol Mangling and ABI Boundaries

### 3.1 Symbol Mangling Scheme

All Zoril symbols emitted to object files (`.o`) and SSA intermediate representations must conform to a deterministic, injective naming grammar.

#### 3.1.1 The Length-Prefixed Grammar

Zoril adopts length-prefixed component mangling over the module's canonical repo-relative path (omitting leading `./` and trailing `.zrl`) and declaration name:

```text
symbol    := "z" component+ "E"
component := <decimal-length> <identifier-or-path-bytes>
```

In QBE SSA intermediate representations, symbols are prefixed with `$` per QBE syntax (e.g. `$z4math3addE`). In emitted assembly (`.s`) and object files (`.o`), the leading `$` is stripped by the backend, producing ELF global/local symbols starting with `z` (e.g. `z4math3addE`).

Examples:

- **Free Function**
  - Source Location & Syntax: `math.zrl` :: `pub fn add(...)`
  - Canonical Components: `["math", "add"]`
  - Mangled Symbol (ELF): `z4math3addE`
  - QBE SSA Symbol: `$z4math3addE`
- **Hierarchical Function**
  - Source Location & Syntax: `a/util.zrl` :: `pub fn parse(...)`
  - Canonical Components: `["a", "util", "parse"]`
  - Mangled Symbol (ELF): `z1a4util5parseE`
  - QBE SSA Symbol: `$z1a4util5parseE`
- **Method**
  - Source Location & Syntax: `geo.zrl` :: `impl Vec2 { pub fn norm(...) }`
  - Canonical Components: `["geo", "Vec2", "norm"]`
  - Mangled Symbol (ELF): `z3geo4Vec24normE`
  - QBE SSA Symbol: `$z3geo4Vec24normE`
- **Module Static**
  - Source Location & Syntax: `net/state.zrl` :: `pub static mut PORT: u16`
  - Canonical Components: `["net", "state", "PORT"]`
  - Mangled Symbol (ELF): `z3net5state4PORTE`
  - QBE SSA Symbol: `$z3net5state4PORTE`
- **Root Single-File Function**
  - Source Location & Syntax: `input.zrl` (no dir) :: `pub fn run(...)`
  - Canonical Components: `["input", "run"]`
  - Mangled Symbol (ELF): `z5input3runE`
  - QBE SSA Symbol: `$z5input3runE`

**Canonical module path, project roots, and build mode.** The module identity is derived from the project root and include directories:

1. **Project Root Discovery:** Specified explicitly via `--root <dir>`, or discovered automatically by ascending parent directories from the entry file until reaching a project marker (`.git`, `zoril.toml`, `Zoril.toml`, `.zoril-root`), falling back to the entry file's directory.
2. **Root Derivation:** Any source file residing within the project root has its module identity defined as its relative path within that root (e.g. `<root>/a/b.zrl` has module identity `a/b.zrl`).
3. **Include Roots (`-I [name=]<dir>`):** Source files resolved through include directories outside the project root have their module identity prefixed by the include root name:
   - **Named form (`-I name=dir`):** The explicit `name` becomes the prefix (e.g. `-I x_lib=path/to/x/lib` maps `<x/lib>/s.zrl` to `x_lib/s.zrl`). Imports may be written as `import "x_lib/s.zrl"` to explicitly identify the root, or the prefix may be stripped from the filesystem search path so `import "s.zrl"` also resolves in that directory.
   - **Bare form (`-I dir`):** The include root name defaults to the basename of `dir` (e.g. `-I path/to/stdlib` maps `<stdlib>/sys.zrl` to `stdlib/sys.zrl`).
   - **Collision Rule:** If two `-I` entries (bare or named) would share the same prefix, the compiler rejects the invocation with a located diagnostic: `error: conflicting include root name '<name>': <path1> and
     <path2>; disambiguate with -I <name>=<dir>`. This ensures every source file under any include root has a unique module identity. Include directories whose absolute path is within the project root are silently ignored (they are already covered by root derivation) — except that, when the root is only the fallback (no `--root`, no marker), a _named_ include root still takes precedence, so `zoril -c x/lib/s.zrl -I xl=x/lib` is `xl/s` rather than `s`. The entry's own directory, which the compiler adds to the import search path, is not an include root. **Unanchored compiles:** with no project root and no named root, identities are relative to the entry's directory, so `x/lib/s.zrl` and `y/lib/s.zrl` compiled separately are both `s` and their objects must not be linked together. Anchor such builds with `--root`, a marker file, or `-I name=dir` (zbuild always passes `--root`).
4. **Deduplication by Resolved File:** The parser deduplicates imports by the resolved canonical file path. If two different import strings resolve to the same physical file, the file is loaded only once. If two different physical files resolve to the same module identity, the compiler rejects the program with a located diagnostic naming both files: `error: multiple distinct files map to module identity '<identity>': <file1> and <file2>`.
5. **Root Confinement:** Every resolved import path must resolve within the project root or one of the configured include roots. A path that resolves outside every root is rejected with a located diagnostic (`<file>:<line>:<col>: error: path resolves outside every root: <norm_path>`).

The module component for mangling is formed from the module identity, normalized (`./` and empty segments removed, omitting `.zrl`/`.zri` extension), with one component per directory segment. Bytes outside `[A-Za-z0-9_]` within a segment are replaced by `_` so every component is a legal symbol. The same identity is used consistently across symbol mangling, `.zri` `zri-module:` headers, `zbuild` cache keys, and `--emit-deps` output, ensuring that a file accessed via different relative paths, absolute paths, or include roots produces the exact same module identity, symbols, and objects. The ZIL printer writes every Zoril-ABI function module-qualified (`a::util::parse`, methods `a::util::Point::norm`) in both `-c` and whole-program mode, and `zilc` turns each `::` segment into one component. Only the unmangled set (§3.1.5) and `extern "C"` names stay plain, decided by one predicate (`is_unmangled_symbol_name` in `src/il_cfg.zrl`) shared by the printer and `zilc`.

**Methods.** Methods are mangled as components `(type, method)`, never `Type_method`.

**Interfaces carry module identity.** A `.zri` begins with `// zri-module: <source path>`. Declarations loaded from it take that path as their module, so symbols referenced through an interface match the ones the source's own compilation exports regardless of where the `.zri` file is stored. A `.zri` written from a root the compiler was told is the standard library also carries `// zri-stdlib: 1` on the next line: that provenance cannot be re-derived from an interface's location or from its `zri-module:` name, since a project's own `stdlib/` directory can produce the same identity.

**An include root's name is not a trust decision.** Whether a root is standard library code is decided by the explicit `-I stdlib=<dir>` form (or the compiler's own installation, which it adds under that name), never by a root's basename or by a directory called `stdlib` inside the project root - the same identity rules above apply to a user's `stdlib/` tree, and nothing about it is trusted more than any other include root.

#### 3.1.2 Why Flat Underscore Joining Fails (Worked Collision Examples)

Naive underscore-delimited mangling schemes (such as `$z_<mod>_<name>`) are **not injective**. They produce silent symbol collisions across distinct modules and declarations:

1. **Underscore Boundary Ambiguity**:
   - Module `mod0` with function `calc_x` mangles to `$z_mod0_calc_x`.
   - Module `mod0_calc` with function `x` mangles to `$z_mod0_calc_x`. Under underscore joining, these two distinct functions produce identical link symbols, causing duplicate-symbol link errors or silent mis-linking. Under length-prefixed mangling:
   - `mod0` :: `calc_x` mangles to `z4mod06calc_xE`.
   - `mod0_calc` :: `x` mangles to `z9mod0_calc1xE`. The symbols are strictly distinct.

2. **Directory Hierarchy Ambiguity (Bare Basenames)**:
   - Module `core/util.zrl` with function `init` mangles to `$z_util_init`.
   - Module `net/util.zrl` with function `init` mangles to `$z_util_init`. Under length-prefixed mangling including canonical paths:
   - `core/util.zrl` :: `init` mangles to `z4core4util4initE`.
   - `net/util.zrl` :: `init` mangles to `z3net4util4initE`. Names from different packages and subdirectories cannot collide, because every path component is length-prefixed.

#### 3.1.3 Decode Rule (Invertibility)

The mangling format is strictly invertible back to its component path and declaration without requiring a compiler symbol table:

1. Verify the string begins with `'z'` and ends with `'E'`.
2. Advance index $i$ to position 1.
3. While $i < \text{len} - 1$:
   - Parse decimal integer length $L$ from digits at index $i$.
   - Advance $i$ past the digits to the first non-digit byte.
   - Extract slice of length $L$: this is component $C_k$.
   - Advance $i \leftarrow i + L$.
4. Ensure index $i$ equals $\text{len} - 1$ and string ends with `'E'`.
5. The extracted components $[C_1, C_2, \dots, C_{n-1}, C_n]$ partition into:
   - Module canonical path: $C_1 / C_2 / \dots / C_{n-1}\text{.zrl}$ (or $C_1 / \dots / C_{n-2}$ for methods).
   - Declaration name: $C_n$ (preceded by type name $C_{n-1}$ for methods).

#### 3.1.4 Character Set and Toolchain Compatibility

The length-prefixed grammar uses characters exclusively from `[A-Za-z0-9_]`. Although standard assemblers accept `.` in symbol identifiers, the mangling grammar deliberately avoids `.` or other punctuation characters. This guarantees that:

- Host assembler (`as`), host linker (`ld`), and backend (QBE) process the symbols without lexer modifications or special escaping.
- Symbols are valid C-compatible identifier strings in debugging and inspection tools (`nm`, `objdump`).

#### 3.1.5 Unmangled Compatibility Surface

To ensure exact binary and runtime compatibility with the bootstrap runtime (`rt/runtime.s`), the following symbols MUST NOT be mangled and retain their raw symbol names:

- `main`: The application entry point (ELF `main`, QBE `$main`).
- `abort`: Process abort handler called on safety panics.
- `__zoril_syscall_*`: Low-level kernel interface shims (`__zoril_syscall_1`, `__zoril_syscall_6`, etc.).
- `malloc`, `free`: Runtime memory management functions defined in `rt/runtime.s`.
- Foreign C Functions: Any function declared with `extern "C" fn <name>(...)` emits as raw `$name`.

### 3.2 Zoril Calling Convention vs. Foreign C ABI

Zoril differentiates internal language calls from foreign C FFI calls:

1. **Zoril Internal ABI (Safe)**:
   - First parameter passes the closure environment pointer `__env: Ptr<unit, 'local>` (lowered as 64-bit pointer).
   - When calling a top-level non-closure function across module boundaries, callers pass `const 0` as `%v__env`.
   - Aggregates >16 bytes or structs with non-trivial layouts use implicit pointer passing or `__sret` pointer.
   - Cross-module calls are fully typechecked and safe; no `unsafe` blocks are permitted or required.
2. **Foreign C ABI (`extern "C" fn`)**:
   - Adheres strictly to the System V AMD64 ABI.
   - No `__env` pointer is passed.
   - Arguments pass via `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`.
   - Invocations are treated as foreign operations and require explicit `unsafe { ... }` blocks.

---

## 4. Cache Directory Hierarchy (`.zoril-cache/`)

Artifact caching is managed under the `.zoril-cache/` directory in the project workspace (or customizable via `--cache-dir <dir>`).

### 4.1 Directory Structure

```
.zoril-cache/
├── manifest.tsv           # Toolchain identity, dependency registry, and hash table (written atomically)
├── iface/                 # Cached interfaces, one flat file per module
│   └── src%2Fmath.zri     #   <encode(module path)>.zri
├── obj/                   # Cached machine-code object files
│   └── src%2Fmath.a1b2c3d4.o   #   <encode(module path)>.<source hash8>.o
└── tmp/                   # Intermediates (.zil .ssa .s), deleted after each successful module build
```

`encode` drops the `.zrl`/`.zri` extension and writes `/` as `%2F`, `%` as `%25`, and any byte outside `[A-Za-z0-9_.-]` as `%XX`: reversible, one directory level, so `a/b.zrl` and `a_b.zrl` cannot collide and a path can never climb out of the cache. The compiler and the driver share the encoding (`src/module_path.zrl`). After a successful build the driver deletes every file under `obj/`, `iface/` and `tmp/` that the new manifest does not reference.

### 4.2 Manifest Schema (`manifest.tsv`, v3)

```tsv
# zbuild manifest v3
#written	1759152020000000000
#toolchain	9f8e7d...
#tool	zoril	/repo/build/zoril	1759151000000000000	1050760	8552f644...
#tool	zilc	/repo/build/zilc	1759151100000000000	205448	3ab64a68...
#tool	qbe	/usr/bin/qbe	1759100000000000000	286544	59f0a4a0...
#tool	as	/usr/bin/as	1759100100000000000	879712	3dfdf600...
src/math.zrl	1759152000000000000	812	a1b2c3d4...	e5f60718...	obj/src%2Fmath.a1b2c3d4.o	stdlib/mem.zrl	5c6d7e...	/repo/src/math.zrl
```

Module rows: `module_path`, `source_mtime` (ns), `source_size`, `source_sha256`, `iface_key` (§5.2), `object_path` (relative to the cache directory, so the cache works from any working directory), `dependencies` (comma-separated resolved import paths; may be empty), `zri_sha256` (hash of the module's own `.zri`), `source_file` (absolute path the module was read from). Rows with fewer than 8 columns are dropped (rebuild).

**Shared caches.** Rows are per module, so several programs may share a cache. A build keeps rows for modules outside its own graph while their `source_file` exists, and drops them once it is gone; garbage collection deletes only artifacts no row references. `zbuild --gc --cache-dir <dir>` prunes such rows without building. The whole build runs under an exclusive `flock` on `<cache>/lock`.

**Crash and failure safety.** The manifest is written only after every module compiled, so a build that fails part-way leaves the previous rows in force. Nothing that build wrote may be mistaken for what those rows describe:

- the object name is `<encode(path)>.<hash8(action key)>.o`, where the action key is `SHA256(toolchain ‖ source_sha256 ‖ sorted dependency interface keys)`, so recompiling a module against a changed dependency never overwrites the object an existing row points to (unreferenced objects are collected later);
- the `.zri` has a fixed name (the compiler finds it by module), so its hash is recorded and re-verified: a module whose interface file does not hash to `zri_sha256` is rebuilt, which rewrites it.

Invalidation inputs, all of which are part of the decision:

- **Toolchain.** `#toolchain` is `SHA256` over the content hashes of the compiler, `zilc`, `qbe` and the assembler, and the compiler flags zbuild passes (not the `-I` list: include roots affect an object only through module identities and the resolved dependency set, both checked per module). A mismatch discards the whole manifest: objects only link with objects of the same emitter generation (`doc/spec/abi.md`). Tool binaries are re-hashed only when their `(path, mtime, size)` changed.
- **Source.** The `(mtime, size)` pre-filter skips hashing only when both match the row. A row recorded while its source was modified less than 2 s earlier ("racy", as in git's index) is stored with mtime 0 and is always re-hashed. Otherwise the decision is by `source_sha256`.
- **Dependency set.** The recorded `dependencies` must equal the freshly resolved import set; a new file that changes what an unchanged `import` resolves to therefore dirties the importer.
- **Dependency interfaces.** Via `iface_key` (§5.2).
- **Artifacts.** A missing object or interface dirties the module. A row that fails to parse is dropped, which only ever costs a rebuild of that module.

---

## 5. Dependency Graph and Incremental Build Protocol

### 5.1 Directed Acyclic Graph (DAG) Construction

1. The driver asks the compiler for the graph: `zoril --emit-deps <entry> -I <dirs> --iface-dir <cache>/iface` prints every import edge reachable from the entry as `<importer>\t<imported file>` (sorted, de-duplicated), lexing only the `import` declarations. The driver never scans source text itself, so what an import names is decided in exactly one place (`src/parser.zrl`: relative to the importing file, then each `-I` directory, with the `.zri` and `zoril/` prefix rules).
2. A module whose source file no longer exists is served from its cached interface and manifest row.
3. A Directed Acyclic Graph (DAG) is constructed where edges represent `import` dependencies: `A -> B` denotes "module A depends on module B".
4. Circular dependencies are rejected at resolve time (by the compiler, with the cycle printed as a path) and again when the driver orders the graph.

### 5.2 Incremental Build Algorithm

For each module $M$ in topological order (leaves first):

```
1. Compute current source hash: H_src = SHA256(read(M.zrl))
2. Lookup previous entry in manifest: Entry_prev
3. If Entry_prev exists (the manifest's toolchain identity matches the current toolchain),
   Entry_prev.source_sha256 == H_src, the recorded dependency set equals the resolved one, and M's object and
   interface exist:
       If none of M's dependencies changed their iface key:
           Mark M as UP_TO_DATE. Skip compilation.
           Continue.
4. Compile M (dependencies are read from their cached interfaces, never from their sources):
       zoril -c M.zrl -I <include_dirs> --iface-dir <cache>/iface --interproc-summary \
             --write-interface <cache>/iface/<M>.zri -o <tmp>/M.zil
       zilc <tmp>/M.zil <tmp>/M.ssa
       qbe -o <tmp>/M.s <tmp>/M.ssa
       as -o <cache>/obj/<M>.<hash8(action key)>.o <tmp>/M.s
5. Read M.zri (written in step 4) and compute the early-cutoff key
       H_iface = SHA256(SHA256(M.zri) || "\n" || key(dep_1) || "\n" || ... || key(dep_n))
   over M's direct dependencies sorted by key. An interface exposes types of its own imports, so a module can
   depend on an interface it never imports directly (main -> b -> c, main reads a field of c's struct through
   b); folding the dependencies' keys into M's key propagates a change exactly as far as it is visible.
   A body-only edit leaves SHA256(M.zri) unchanged, hence the key unchanged, hence dependants untouched.
6. If Entry_prev exists and Entry_prev.iface_sha256 == H_iface:
       Mark M's interface as UNCHANGED (early cutoff for downstream nodes).
   Else:
       Mark M's interface as CHANGED (triggers downstream recompilation).
7. Update manifest.tsv with new hashes and object path.
```

### 5.3 Link Invocation

When all modules in the DAG are processed:

1. Collect object files: all newly compiled `.o` files + all `UP_TO_DATE` cached `.o` files.
2. Ensure runtime object `runtime.o` is present.
3. Execute link command: `ld -o <out_bin> <obj1.o> <obj2.o> ... <objN.o> build/runtime.o`
4. Complete build.

---

## 6. Monomorphization and Generics

### 6.1 Generic AST Preservation

Because Zoril employs whole-function monomorphization rather than dynamic dispatch for generics, generic struct and function templates cannot be emitted into a single object file ahead of time.

- In `.zri` interface files, generic templates (`fn id<T>(x: T) -> T { ... }`) retain their full definition.
- When module `A` instantiates `id::<i64>`, the specialization is generated within `A`'s compilation unit.

### 6.2 Deduplication of Specializations (TU-Local Instantiation)

For generic functions and methods, Zoril adopts **TU-local instantiation** as the standard placement model:

1. **Local Linkage**: Every specialized instance (`id::<i64>`, `Vec::<Point>::push`, etc.) is emitted with local linkage (`STB_LOCAL` in ELF, `local f<id>` in ZIL, and unexported `function` in QBE/SSA IR) inside the translation unit that instantiated it.
2. **Conflict Freedom**: Because specializations carry local binding, two independent modules `A` and `B` that instantiate identical specializations (e.g. `id::<i64>`) produce independent `STB_LOCAL` definitions in `A.o` and `B.o`. The linker (`ld`) resolves intra-module references to each unit's local copy with zero duplicate-symbol collisions and zero cross-module symbol pollution.
3. **Future Optimization (ELF COMDAT)**: Section-group deduplication via ELF COMDAT sections (`.text.<name>`) with weak symbols (`STB_WEAK`) remains available as a binary-size optimization in a future sprint.

---

## 7. Safety Invariants Across Module Boundaries

All Zoril safety model guarantees (`doc/spec/safety_model.md`) are maintained across translation-unit boundaries:

1. **Bounds Checking (§11.2.3)**: Slices passed across module boundaries carry `(ptr, len)`. All read and write accesses remain bounded by the receiver's checks.
2. **Stack Escape Checking (§11.2.4)**: Returning or storing away a pointer to local stack storage is rejected, also through calls: the `storage`, `stores` and `into` summaries in `.zri` let a caller see what an imported function does with a pointer into the caller's frame.
3. **Move and Affine Checking**: Value moves across function parameters are enforced by the caller using the parameter types declared in `.zri`.
4. **Interprocedural Summaries**: Escape masks and allocation summaries computed by `InterprocSummaryPass` (`src/summary_pass.zrl`) are serialized into `.zri` annotations, allowing downstream callers to verify region containment across module boundaries.
