# Known Issues in Zoril v0.1.0-alpha

This document records known limitations, bootstrap dialect boundaries, and open issues across the shipped Zoril components. In accordance with the release policy, any issue that had a straightforward fix has been resolved; remaining items are documented here with the technical rationale.

---

## 1. Bootstrap Compilers (`stage0-C` and `stage1`) Known Issues

`stage0-C` is a frozen C99 bootstrap compiler whose sole purpose is compiling the pinned `stage1` snapshot. It is modified only when a bug blocks the bootstrap process. `stage1` (`bootstrap/stage1/`, built as `build/zoril-stage1`) is that snapshot; on a fresh checkout it compiles `src/` and the stdlib modules `src/` imports, so those modules may use only what it handles (see the `stage1` issues below).

### Bug #14: Local variable named `ast` misresolves when importing `ast.zrl`

- **Symptom:** In a module importing `ast.zrl`, declaring a function parameter or local variable named `ast: *mut AST` causes field access on that variable (e.g. `(*ast).decls.data`) to fail with `"Slice has no member 'data'"`. The bootstrap compiler misidentifies the field access as a call to the method `AST::decls()`.
- **Workaround:** Name the parameter or variable something other than `ast` (e.g., `tree`).
- **Impact:** Zero impact on normal compilation or the bootstrap chain. No code in `src/` triggers this pattern. The test `tests/bootstrap/repro_bootstrap_find_impl.zrl` tracks this repro and is reported as a known skip in stage0-C's functional suite.
- **Why not fixed for release:** `stage0-C` is frozen for stability. Fixing this requires refactoring identifier resolution across types and methods in C; it will be addressed only if a future `stage1` re-pin trips it.

### Dialect Limitations in `stage0-C`

`stage0-C` compiles only a frozen bootstrap dialect, not the full Zoril surface language. Specifically:

- `for` loops are numeric ranges only (`for i in 0..N`).
- No match guards (`Pat if cond => ...`).
- No struct or tuple match patterns (`Foo { field }` or `(a, b)`).
- `==` and `!=` operate only on word-sized scalar types and fieldless enums.
- Single trait bound per type parameter (no `K: Hash + Eq`).
- No associated types or trait default methods.
- No number-to-`char` conversion: `n as char` and `@int_cast<char>(n)` are both rejected with `type mismatch: expected type_27, found u32`, so no stdlib module it compiles can make a char from a number. `stdlib/unicode.zrl`, whose `char_from_u32` does (`unsafe { n as char }`), is therefore kept out of the modules `src/` and the stage0-C test suite import; the self-hosted compiler accepts the cast.

These limits do not affect user code because user code is compiled by the self-hosted compiler (`build/zoril`), which supports the full language.

### `stage1`: two modules with a private function of the same name are refused

- **Symptom:** when two imported modules each define a private function with the same name, and each calls its own, `build/zoril-stage1` reports `cannot access private function: <name>` at the call in the second module. `build/zoril` accepts the program. Reproduction: modules `ma.zrl` and `mb.zrl`, each with a private `fn helper(x: i32) -> bool` and a `pub fn` that calls it, both imported by one `main` (`use ma::a_check; use mb::b_check;`); stage1 fails with `mb.zrl:2:41: error: cannot access private function: helper`.
- **Impact:** none on user code or on today's bootstrap. It constrains the modules `src/` imports: no two of them may define a private function of the same name. `stdlib/proc.zrl` and `stdlib/fsys.zrl` each define a private `has_interior_nul`, so stage1 refuses any program importing both (`tools/zbuild/src/main.zrl` among them); `src/` does not import `proc.zrl`.
- **Workaround:** give the private functions distinct names in any module that joins the `src/` closure (`build/zoril -I stdlib=stdlib -I build/gen --emit-deps src/main.zrl` lists it).
- **Why not fixed:** `stage1` changes only by a re-pin or a recorded backport (`doc/bootstrap/two_stage.md` §3), which is the maintainer's decision. Tracked in task Z-0135.

### `stage1`: some stdlib paths are built into programs that crash

- **Symptom:** built by `build/zoril-stage1` and `build/zilc-stage1` (the pipeline `build/zilc-boot` uses), `tests/stdlib/test_stdlib_fd.zrl` and `tests/stdlib/test_stdlib_io_result.zrl` compile without a diagnostic and then crash with a segmentation fault: in `zoril_allocator_alloc` (`stdlib/mem_raw.zrl`), called from `test_pipe_large_buffer`, and in `arena_free` (`stdlib/mem_raw.zrl`), called from `Arena::drop` (`stdlib/mem.zrl`) in `test_command_redirect_stdout`. Built by `build/zoril` through the same steps, both exit 0. The cause is not yet known.
- **Impact:** none on user code, which `build/zoril` compiles. `mem.zrl` and `mem_raw.zrl` are among the modules `src/` imports, so an edit to `src/` that starts reaching such a path would get a compiler built wrongly on a fresh checkout, seen only if the self-hosting fixpoint differs.
- **Why not fixed:** the cause is under investigation in task Z-0135; a fix to `stage1` itself is a re-pin or a recorded backport, the maintainer's decision.

---

## 2. Code Generation and Backend (QBE) Limits

### Linear Enum Tag Dispatch Chains

Because QBE does not provide native jump tables or indirect branch tables, `match` statements over sum types or enums with many variants lower to sequential comparison branches. On workloads with large enum dispatch loops (such as virtual machine byte-code dispatch), this introduces measurable overhead compared to C compilers that emit jump tables.

### Extreme Function Size Limit in QBE

For functions containing tens of thousands of instructions in a single basic block or function body, QBE's register allocator may hit an internal parallel-move capacity limit. Real-world Zoril code and all modules in `src/` and `stdlib/` remain well below this threshold.

---

## 3. Toolchain & Platform Support

### Target Architecture

`v0.1.0-alpha` targets **Linux x86_64**. Portability to other operating systems (FreeBSD, OpenBSD, macOS, Windows) and CPU architectures (AArch64, RISC-V) is planned for future milestones; see [the roadmap](doc/ROADMAP.md#portability).

### `zoril` and `zbuild` print every error a file produces

- **Symptom:** given a file that is not Zoril source, `zoril` (and `zbuild`, which passes its output through) reports an error for nearly every token: 300 KB of random bytes produce about 140,000 error lines, and 160 KB of English prose about 33,000.
- **What works:** a Zoril program's errors are reported in full, and the first one is where to start.
- **Workaround:** `zoril ... 2>&1 | head -20`.
- **Fix planned (post-release):** a default limit on the number of errors, with an option to change it, and a one-line refusal of a file that contains a NUL byte, is not UTF-8, or produces only errors before its first declaration.

### `zilc` skips text it does not recognise between declarations

- **Symptom:** `zilc` reads a declaration where its first word says one starts, and steps over anything else at the top level of a file. A file of random bytes is therefore accepted with no message and lowered to an empty program, and a stray word can be read as the start of a declaration it was not meant to be. A malformed declaration is still reported, at its line, and `zilc` stops there.
- **What works:** every ZIL file `zoril --emit-zil` writes, and hand-written ZIL whose top level holds only declarations and comments (see "Starting from ZIL" in [Getting Started](doc/getting_started.md#starting-from-zil); `zilc` checks types, while the ownership and region checks run in `zoril`).
- **Fix planned (post-release):** text between declarations, a NUL byte and invalid UTF-8 become errors.

### `zbuild` builds `.zrl` programs only

- **Symptom:** `zbuild prog.zil` parses the ZIL as Zoril and prints a page of `expected declaration` errors.
- **Workaround:** build a ZIL file with `zilc`, `qbe`, `as` and `ld`, as in "Starting from ZIL" in [Getting Started](doc/getting_started.md#starting-from-zil).
- **Fix planned (post-release):** `zbuild` builds a `.zil` file through the same steps, and refuses any other input with one line.

---

## 4. Separate Compilation (`zoril -c` and `tools/zbuild`)

### A method's `impl` must be reachable through imports, not just through the type

- **Symptom:** `zbuild` reports `no field 'helper' on '&mut T'` (with the note "under -c only the target module and the modules it imports are visible: an `impl T` in another module is not, though a whole-program build resolves it") for a call that the whole-program compiler accepts.
- **Why:** methods go with their type, whichever module the `impl` is in (`surface_syntax.md` §11.1.1), so the whole-program compiler resolves `t.helper()` by searching every `impl T` in the program. `-c` compiles one module against its imports, so it can only see the `impl`s in that unit. When the module holding the `impl` is one the caller cannot import — the caller declares a type that the other module's `impl` targets, and the other module imports the caller — no import can close the gap; the compiler rejects the call, and the driver cannot order the two modules so that both interfaces exist.
- **What works:** every module graph whose `impl`s are reachable through imports, including every two-module case with no such cycle (`tests/incremental/`), which is what `zbuild` is gated on.
- **What does not:** a mutual `impl`-dependency cycle. The compiler's own source has three clusters (`src/driver/state.zrl`, the `parser/` cluster, and the `lower_zir/` cluster: 12 of its 50 modules fail `-c`), so `zbuild` cannot yet build `build/zoril`; the compiler is built whole-program (`make`), as it has been all along.
- **Workaround for a project:** build the program whole-program, or move a type's `impl`s into one module and give it a leaf module that both sides import.
- **Fix planned (post-release):** compilation groups — compile each strongly connected component of the import-plus-impl graph as one unit, one object and one interface per member.

### A method nothing calls is checked by a whole-program build, not by `-c`

- **Symptom:** a field, name, privacy, type or borrow error inside a method that nothing calls is reported by `zoril <program>.zrl` and by nothing a `-c` build runs, so the error appears late - when someone first calls the method, or when the program is built whole.
- **Why:** a whole-program build sees the program and checks every method of it whose `Self` is known as written, called or not - every method of an `impl` whose target type is written with no type parameter (`impl W<i32>` included); a method of an `impl` with a free type parameter, and a generic method, are still checked when an instance is made (`doc/spec/surface_syntax.md` §11.1.1). `-c` sees one translation unit and checks the public methods of its target module, which is as much of the rule as it can carry. A private method of the target module that nothing calls is in neither: no other module may call it, and `-c` does not check it, because a `-c` build emits what it checks.
- **What works:** every program built whole-program, which is what `make`, the test suite and `zoril build` do; the error is reported there, in the module that owns the method, whether or not anything ever called it.
- **Workaround for a `-c`-only project:** build the program whole-program once (or call the method from a test) to have its bodies checked.
- **Fix planned:** check the unchecked half in `-c` too - lower the target module's methods that nothing calls, as the whole-program build does, and drop them again before the ZIL is written (`Driver.check_uncalled_methods`, whose drop is `ILModule.drop_check_only_code`) - once the incremental scenarios can measure the extra work it costs a rebuild.

### Naming a private static, generic function or generic method of another module under separate compilation reports that it does not exist rather than that it is private

- **Symptom:** attempting to `use` a private `static`, or a private generic function that no public generic body uses, reports `cannot use 'priv::hidden': the module defines no 'hidden'` under `zbuild` / `zoril -c`, whereas a whole-program compilation (`zoril`) reports `cannot use 'priv::hidden': it is private: 'hidden'`. Calling a private generic method of an imported type reports `no field 'secret' on 'W'` under `zbuild`, and `cannot access private method: secret` whole-program. (A private trait is reported as private in both.)
- **Why:** the interface carries every private non-generic function and method as a signature (so the importer can say `private`, and see a second `Counter::get` or a second exported `extern "C"` symbol), every type and constant, and a private trait that one of its impls names; it does not carry these three, whose edits would otherwise reach dependants.
- **What works:** the error is still reported, only the word differs.

### A generic `pub fn` that stores a reference parameter without `#[stores]` is warned about by a whole-program build, not by `zbuild`

- **Symptom:** the warning `this`pub fn`stores the reference parameter ... add`#[stores(...)]`` for a generic function or method appears when the program is built whole, and not under `zbuild`.
- **Why:** a generic body is checked where it is instantiated, and under `-c` the instantiating module reads the body from the interface, whose lines are not the source's: the warning would name the interface's line under the source's file name, so it is not given (`FnDecl.from_interface`). The module's own `-c` build does not instantiate the body. The declared contract is carried in the interface either way, so callers are checked against it.
- **Workaround:** build the program whole-program once; a standard-library function never needs it (`scripts/test_interface_attrs.sh`).

---

## 5. Memory safety: what the compiler does not check

This section lists limits that produce a wrong result or a rejected program. It is not the list of what a program may do to itself: [What Zoril Checks](doc/SAFETY.md) states that in three tiers, and the probes behind each tier are in `bench/safety_matrix/probes/`.

- **Inside `unsafe`**, six operations are unchecked - dereferencing a raw pointer (including indexing one, `p[i]`, and field access through it), making a reference or a slice out of an integer, a pointer or a type parameter, `@slice` from a raw pointer, `extern` calls, `@syscall` and `@alloca` - and so is calling an `unsafe fn` ([`doc/spec/unsafe_policy.md`](doc/spec/unsafe_policy.md) §1 is normative). `unsafe` does not disable verification: region, ownership, borrow, immutability and bounds checks all stay active inside it.
- **Failures that fault rather than diagnose:** integer division and modulo by zero, and `INT_MIN / -1`, die with `SIGFPE` (exit 136); unbounded recursion touches the guard page and dies with `SIGSEGV` (exit 139). Neither names a line, and neither runs the program's `defer` blocks. Integer overflow wraps by design. `panic: <message>` failures that can be handled or that signal a mistake - `Option::unwrap`/`Result::unwrap` on the wrong variant, the `print` / `println` / `eprint` / `eprintln` I/O helpers - exit 1 instead.
- **A `Box` is never freed, and its boxed value's `Drop` does not run when the `Box` goes out of scope.** `box expr` allocates on the heap, and nothing releases the allocation when the `Box` goes out of scope or is dropped after a move: a program that boxes a value in a loop grows by that value's size each iteration (3,000 boxes of 1 MiB reach 3 GB). A `Box<T>` whose `T` implements `Drop` does not call it at scope end, nor for a `Box` moved into a call; an explicit `@drop(b)` does call it, and still frees nothing. It is a leak, not a memory-safety hole - the memory stays valid, and every borrow and move check holds. Workaround: build short-lived values in an arena (`mem::Arena`) or on the stack, and do cleanup a value needs (closing a descriptor, say) explicitly rather than in a boxed value's `Drop`. Fix planned (post-release): `Box` frees its allocation and drops its contents at scope end.
- **A reference to a local aggregate that arrives through a value is read as pointing at the stack.** `let c = Carrier { v: &STATIC }; let r = &c; return ex_ref(r);` is rejected (`region escape: returning a pointer to local stack storage`) although `c` holds a static's address, because the interprocedural summary pass cannot name the slot behind `r` and fails closed (`ex_ref(&c)`, which names it, is accepted; probe 405). The same reading is what rejects the unsafe forms (probes 400-404). The unified provenance model replaces it after the launch.
- **What the static analyses cannot see:** the checks answer conservatively where they cannot decide, which rejects a correct program rather than accepting a wrong one, and the audit's bounds are [What Zoril Checks](doc/SAFETY.md) §4.4. The standard library's and the compiler's own `unsafe` interiors are the trusted base ([What Zoril Checks](doc/SAFETY.md) §5.3), and `-c`/`zbuild` checks less of a program than a whole-program build (§4 above).
- **Open soundness holes in checked code:** 17 known soundness holes in checked code (where views of frame-owned storage escape through indirect aggregates, call summaries, closures, or unchecked parameters) are tracked as `known_gap` probes in [`doc/spec/safety_model.md#known-gaps`](doc/spec/safety_model.md#known-gaps) and documented in [`doc/SAFETY.md`](doc/SAFETY.md) §6. They are planned to be closed after the alpha by a unified provenance model.
- **What the fuzzing evidence does not cover:** the release-bar budget bounds what was tried, not the language; the fuzzer's scope and its limits are [What Zoril Checks](doc/SAFETY.md) §5.2.
- **A unit or missing generic argument still stands for a plain number.** `()` is what an argument nothing inferred defaults to, so `W<()>` is accepted where `W<i32>` is expected and reads an unspecified number - not an address, which is what probe 245 pins. closing it needs inference to leave an argument unresolved rather than defaulting it to `()`, which is a larger change than a check; the fix narrowed the wildcard to plain numbers instead.
