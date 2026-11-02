# tools/zbuild — Zoril Incremental Compilation Driver

Part of the [`tools/`](../README.md) toolchain. Implements [`doc/spec/modular_compilation.md`](../../doc/spec/modular_compilation.md) §4–5.

## Role

An incremental compilation driver. It asks the compiler for the import graph (`zoril --emit-deps`), detects and rejects circular dependencies with the cycle printed as a path, tracks source, interface and toolchain digests in `.zoril-cache/manifest.tsv`, applies early cutoff through interface keys, compiles stale modules (`zoril -c` → `zilc` → `qbe` → `as`), and links the objects with host `ld` against `build/runtime.o`.

Written in 100% safe Zoril code with zero unsafe markers (0.00% line density). It builds itself: `zbuild -I stdlib
-I src -I tools/zbuild/src tools/zbuild/src/main.zrl` compiles all 23 of its modules incrementally.

## Layout

| File           | Responsibility                                                                            |
| :------------- | :---------------------------------------------------------------------------------------- |
| `main.zrl`     | Orchestration: options → toolchain → manifest → graph → compile → manifest → link → GC    |
| `options.zrl`  | Command line (unknown flags and missing values are errors)                                |
| `tools.zrl`    | Locating and fingerprinting compiler, `zilc`, `qbe`, `as`, linkers                        |
| `manifest.zrl` | `manifest.tsv` v2 parse/serialize                                                         |
| `graph.zrl`    | `--emit-deps` edges, node interning, topological order, cycle reporting                   |
| `build.zrl`    | Per-module planning and compilation, link line, atomic manifest write, garbage collection |
| `util.zrl`     | Paths, files, numbers, checked child execution                                            |

## Usage

```bash
zbuild [OPTIONS] <entry.zrl>
```

### CLI Options

- **`-o`**
  - Argument: `<path>`
  - Description: Output binary path
  - Default: `./a.out`
- **`-I`**
  - Argument: `<dir>`
  - Description: Add include directory (repeatable)
  - Default: none (the entry's directory is implicit)
- **`--cache-dir`**
  - Argument: `<dir>`
  - Description: Artifact cache directory
  - Default: `.zoril-cache`
- **`--gc`**
  - Argument: —
  - Description: With no entry: drop rows whose source file is gone and delete unreferenced artifacts
  - Default: —
- **`-v`, `--verbose`**
  - Argument: —
  - Description: Print per-module actions (`[compile]`, `[up-to-date]`, `[early-cutoff]`, `[frozen]`)
  - Default: Off
- **`--runtime`**
  - Argument: `<path>`
  - Description: Runtime object
  - Default: `build/runtime.o`
- **`--compiler`, `--zilc`, `--qbe`, `--as`, `--ld`**
  - Argument: `<path>`
  - Description: Tool binaries
  - Default: see below
- **`-h`, `--help`**
  - Argument: —
  - Description: Usage
  - Default: —
- **`-V`, `--version`**
  - Argument: —
  - Description: Display version and exit
  - Default: —

Tool lookup: an explicit flag wins; `zoril` and `zilc` are then looked up next to the `zbuild` binary (`build/zbuild` finds `build/zoril` from any working directory); everything else is searched on `$PATH`.

Exit status: a failing build step ends the build with that step's exit code; a step killed by a signal prints `error: <tool> killed by signal <n>` and exits `128+n`; a step that cannot be started or observed exits 1. A step is never reported successful unless it was seen to exit 0.

## Cache Hierarchy & Manifest

```
.zoril-cache/
├── manifest.tsv           # toolchain identity, per-module rows; written to a temp file and renamed
├── iface/                 # <encode(module path)>.zri
├── obj/                   # <encode(module path)>.<hash8(action key)>.o
└── tmp/                   # intermediates, removed after each module
```

See spec §4 for the encoding and the format. What invalidates a module:

- **Toolchain** — a different compiler, `zilc`, `qbe`, assembler or flag set discards the manifest (tool binaries are re-hashed only when `(path, mtime, size)` changes). The `-I` list is not part of the toolchain: it affects an object only through module identities and the resolved dependency set, both checked per module, so programs with different include lists can share a cache.
- **Source** — `(mtime, size)` pre-filter, else content hash. A source modified within 2 s of being read is recorded as racy (mtime 0) and re-hashed on the next build.
- **Dependency set** — the resolved imports must match the recorded ones, so a file that changes what an unchanged `import` resolves to dirties the importer.
- **Dependency interfaces** — early-cutoff key `SHA256(SHA256(M.zri) ‖ sorted dependency keys)`: an interface change reaches exactly the modules that can see it, including through re-exported types; a body-only edit stops at the edited module.
- **Missing or foreign artifacts** — object gone, or the interface file does not hash to the recorded `.zri` hash (a failed build may have rewritten it). Object names embed the action key (toolchain, source, dependency keys), so a failed build can never overwrite an object that the previous manifest still references.

**Sharing and relocation.** Several programs may share one cache: rows are per module, a build keeps other programs' rows while their source files exist (each row records its absolute source path), and garbage collection deletes only artifacts no row references. Object paths are stored relative to the cache directory, so the same cache works from any working directory. The cache is locked (`flock` on `<cache>/lock`) for the whole build. `zbuild --gc --cache-dir <dir>` prunes rows for deleted sources without building anything.

Modules are compiled against their dependencies' cached interfaces (`--iface-dir`), never their sources, so a dependency's source may be deleted after its first build (`[frozen]`). `--interproc-summary` runs on every module, so cross-module escape checks are enforced in real builds. After a successful build, artifacts the new manifest does not reference are deleted.

## Runtime Pairing

`zbuild` links using host `ld` against the host-assembled runtime object (`build/runtime.o`). An invalid or incompatible runtime object is rejected with an explicit diagnostic.

## Known Limit: an `impl` in a module the caller cannot import

A module is the unit of compilation, so `zoril -c` sees the impls of the target module and of the modules it imports. Methods otherwise go with their type (`surface_syntax.md` §11.1.1), which is why the whole-program compiler resolves `t.helper()` through an `impl T` in any module. When that module is one the caller cannot import — the caller declares the type the other module implements, and the other module imports the caller — the call is rejected:

```
src/driver/state.zrl:310:16: error: no field 'is_aggregate' on '&mut Driver'
src/driver/state.zrl:310:16: note: under -c only the target module and the modules it imports are visible: an `impl Driver` in another module is not, though a whole-program build resolves it
```

No import can close the gap and the driver cannot order the two modules so that both interfaces exist, so such a graph has to be built whole-program, or the type's impls moved into one module with a leaf module both sides import. Module graphs without this cycle — every case in `tests/incremental/` — are unaffected. The compiler's own tree has three such clusters (12 of its 50 modules), so `zbuild` cannot yet build `build/zoril`; the compiler is built whole-program by `make`. `KNOWN_ISSUES.md` §4 records the same limit for users; the planned fix is to compile each strongly connected component of the import-plus-impl graph as one unit.

## Status

**Working.** Verified under `make test TSUITE=incremental` (29 acceptance tests plus the incremental-vs-clean equivalence suite with fault injection).

`--test-break-cutoff` is a test-only fault-injection flag (never propagate interface changes) used by the equivalence suite to prove it can detect a stale cache.
