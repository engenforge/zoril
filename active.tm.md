# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [x] +safety +tests +AI-G @provenance B3d A raw-pointer write through a loose raw local reaches the caller's parameter targets under `--provenance` id:77rr6
    > **Created:** 2026-11-19
    > **Branch:** `provenance`
    > **Depends:** id:f81f3
    > **Completed:** 2026-11-20

    - **Placed:** directly after id:f81f3, the decision it implements (decision 1 there).
    - **Do:** in `os_dest_reach` (`src/check_zir.zrl`), right after the step that adds a loose raw local's `Static`, add the parameter words of `O(L)` too, for a local that is `OS_Q_LOOSE_RAW` and not `OS_Q_HANDLE`. This is id:f81f3's F3 patch, `build/f81/lead1.patch`:
      ```diff
      +                if !os_type_has(c, module, lty, OS_Q_HANDLE)
      +                    && os_type_has(c, module, lty, OS_Q_LOOSE_RAW) {
      +                    let dw = dst * c.words;
      +                    let lw = id * c.words;
      +                    c.buf[dw + OS_W_ADDR] = c.buf[dw + OS_W_ADDR] | c.buf[lw + OS_W_ADDR];
      +                    c.buf[dw + OS_W_CONTENTS] = c.buf[dw + OS_W_CONTENTS] | c.buf[lw + OS_W_CONTENTS];
      +                }
      ```
      A comment above it says why: a loose raw local holds no owner, so following all of `O(L)` cannot pull in a `Vec`'s elements, the objection id:95w4z measured against doing this in general.
    - **Tests:** add `tests/language/memory/provenance/raw_write_through_loose_raw_param_refused.zrl` (gap_102's program; `// flags: --provenance`, `// expected compile fail`, `// EXPECT: call store rule`), `raw_write_declared_stores_binds_caller_refused.zrl` (the same with `#[stores(r -> s)]` on `put`, `build/f81/p/decl.zrl`), and `raw_write_integer_through_loose_raw_accepted.zrl` (`r: i32`, `build/f81/p/int.zrl`; `// expected exit 0`).
    - **Docs:** gap_102's Known gaps entry in `bench/safety_matrix/README.md` says the program is refused under `--provenance` and is accepted only by the default build until id:z0065. The probe stays `known_gap`. Its `// gap:` line is a marker line and is left as it is. `doc/design/provenance.md` gets a sentence where id:95w4z's loose-raw step is described.
    - **Scripts (scratch, from id:f81f3; recreate them under `build/77r/` if `build/f81/` is gone):**
      - `mk.sh SRCDIR OUT`, a scratch compiler from a copy of `src/` (`cp -r src build/77r/src_x`, edit it there): `timeout -k 5s 300s build/zoril -I stdlib=stdlib -I "$S" -I build/gen --emit-zil -o "$O.zil" "$S/main.zrl"`, then `timeout -k 5s 300s build/zilc "$O.zil" "$O.ssa"`, `qbe -o "$O.s" "$O.ssa"`, `as -o "$O.o" "$O.s"`, `ld -o "$O" "$O.o" build/runtime.o`. Never replace `build/zoril`. A test run with it: `ZORIL_CC=$PWD/<compiler> ./scripts/test.sh <paths>` (a missing binary fails, so the variable is read).
      - `pdiff.sh BASE NEW`: `find tests bench/safety_matrix/probes -name '*.zrl' ! -name '*_lib.zrl' | sort`; compile each with both compilers, with `-I stdlib=stdlib -I "$(dirname $f)" --provenance -o /dev/null`, under `timeout -k 2 30`; print `$f base=$a new=$b` where the exit codes differ.
      - `rootwarn.sh ZORIL OUT`: for each of `src/main.zrl tools/zilc/src/main.zrl tools/zbuild/src/main.zrl tools/zman/src/main.zrl tools/ztest/src/main.zrl`, run `ZORIL -I stdlib=stdlib -I <root dir> -I src -I build/gen --provenance=warn --emit-zil -o /dev/null <root> 2>&1 | grep provenance`, prefixed with the root, then sort into OUT.
      - `grid.sh`: `ZORIL_CC=<wrapper exec'ing the compiler with --provenance> sh scripts/check_store_grid.sh --dir <d>/work --expected <copy of bench/fuzz/store_grid_expected_failures.txt> --twins <copy of store_grid_twin_rejections.txt> --classes <copy of store_grid_classes.txt>`.
    - **Checks:**
      - C1, before: `build/zoril --provenance -I stdlib=stdlib -o /dev/null bench/safety_matrix/probes/gap_102_raw_write_store_hidden_from_summary.zrl` gives rc=0.
      - C2, after: the same gives rc=1 with `error: provenance: the callee stores an address of this frame into memory that outlives it (call store rule)` at `6:58`. Without `--provenance`: rc=0.
      - C3: the three new tests pass (`./scripts/test.sh tests/language/memory/provenance`).
      - C4, the fix taken out (a scratch compiler built with `mk.sh` without the hunk): the two `_refused` tests fail, the `_accepted` one passes.
      - C5: `pdiff.sh` with the base and new compilers prints exactly one line, `gap_102 ... base=0 new=1`, apart from the three new tests.
      - C6: `rootwarn.sh` gives 183 lines with each compiler, and the two files are identical (`cmp`).
      - C7: the store grid under `--provenance` with each compiler gives 3932 twins refused and identical twin lists (`sort -u` of `work/twin_rejections.txt`, `comm -3` empty), and no unsafe cell accepted.
      - C8: `sh scripts/run_safety_matrix.sh`, `sh scripts/check_safety_model.sh`, `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, quoting each `Total:` line and the `reject-diff: base verdicts: fresh (no cache)` line. The change only refuses more, so the differential must show 0 newly accepted.
      - C9: the fuzz record is stale for `src/` (`scripts/check_fuzz_fresh.sh`); say so.
    - **Ends with:** the fix committed, an `**Awaiting review:**` bullet naming C2, C4, C5 and C7, then `tm done`. The check-in is the `@checkin` task after stage 2.
    - **Awaiting review:** C2 (`gap_102` refused under `--provenance` with `call store rule` at `10:58`, rc=0 without), C4 (base compiler without the hunk fails both `_refused` tests and passes `_accepted`), C5 (`pdiff.sh` prints only `gap_102` and the two new `_refused` tests), C7 (store grid under `--provenance` refuses 3932 twins with `comm -3` empty and 0 unsafe cells accepted).
    - **Checks recorded (2026-11-20, git:560d963):**
      - C1: `build/zoril --provenance -I stdlib=stdlib -o /dev/null bench/safety_matrix/probes/gap_102_raw_write_store_hidden_from_summary.zrl` gave `rc=0`.
      - C2: with `--provenance`, `rc=1` with `bench/safety_matrix/probes/gap_102_raw_write_store_hidden_from_summary.zrl:10:58: error: provenance: the callee stores an address of this frame into memory that outlives it (call store rule)`; without `--provenance`, `rc=0`.
      - C3: `./scripts/test.sh tests/language/memory/provenance` passed: `Total: 154 run, 154 passed, 0 failed, 0 skipped (0.8s)`.
      - C4: with `build/77r/zoril_base` (without the hunk), `raw_write_through_loose_raw_param_refused.zrl` and `raw_write_declared_stores_binds_caller_refused.zrl` failed (`compiled`), `raw_write_integer_through_loose_raw_accepted.zrl` passed (`Total: 4 run, 2 passed, 2 failed, 0 skipped`).
      - C5: `pdiff.sh` between `zoril_base` and `build/zoril` printed only `gap_102_raw_write_store_hidden_from_summary.zrl base=0 new=1` and the two new `_refused` tests.
      - C6: `rootwarn.sh` gave 183 lines with each compiler (`cmp=identical`).
      - C7: `check_store_grid.sh` under `--provenance` gave 3932 twins in both `grid_base` and `grid_new`, `comm -3` on sorted twins was 0 lines, and 0 unsafe cells were accepted.
      - C8: `sh scripts/run_safety_matrix.sh` (`All probes complete: 505/533 passed. Mismatches: 0`), `sh scripts/check_safety_model.sh` (`PASS: safety_model.md is self-consistent.`), `make test` (`Total: 3984 run, 3984 passed, 0 failed, 58 skipped (142.2s)`), `REJECT_DIFF_NO_CACHE=1 make preflight-changed` (`reject-diff: base verdicts: fresh (no cache); base front end 111 s`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 10596 newly refused, of 69173 programs`, `Total: 1516 run, 1516 passed, 0 failed, 0 skipped (109.0s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.7s)`).
      - C9: `scripts/check_fuzz_fresh.sh` reported `STALE` for `src/`, `stdlib/`, `tools/zilc`, `tools/zbuild`, `rt/`.

- [x] +safety +tests +AI-G @provenance B3f Stage 1: `memcpy` declares its store effect, and a call to an undeclared `extern` with two or more pointer parameters is refused id:716bm
    > **Created:** 2026-11-19
    > **Branch:** `provenance`
    > **Depends:** id:yp1er
    > **Completed:** 2026-11-20

    - **Placed:** directly after id:77rr6, in the `+AI-G` batch id:77rr6, id:716bm, id:eb38n and id:z0066, which the check-ins id:g764h and id:h1yk5 review.
    - **The decision this builds:** `doc/design/provenance.md` §3, _Store effects of an `extern`_ (git:a9b60aa, id:yp1er). Read it first. It is the source of everything below. Background is in id:f81f3 (`completed.tm.md`): F4 to F6 and F8.
    - **Do:**
      - 1. _Parser_ (`src/parser/decl.zrl`, `parse_unsafe_attribute` and `parse_stores_list`): accept `unsafe(stores(..))` beside `unsafe(borrows(..))`, with a flag on the attribute, say `stores_trusted`, carried to `FnDecl` as `borrows_trusted` is. Accept a `*` before a pair's source, kept in a third per-pair list, `stores_contents: [bool]`. Errors, each with a test under `tests/error_reporting/`:
        - `#[unsafe(stores(..))]` on a function with a body: `#[unsafe(stores(..))] is for an extern: a body's #[stores(..)] is checked against it`.
        - a plain `#[stores(..)]` on an `extern`: `an extern's #[stores(..)] cannot be checked: write #[unsafe(stores(..))]`.
        - a `*s` pair on a body's `#[stores(..)]`: `the *p form is for an extern`.
        - another attribute under `unsafe(..)`: `only #[borrows(..)] and an extern's #[stores(..)] can be marked unsafe`.
        - `tests/error_reporting/err_unsafe_attr_not_borrows.zrl` (`#[unsafe(stores(a))]` on a body) changes its `EXPECT:` to the first message. id:yp1er decided that change. Name it in the commit message.
      - 2. _The rows:_ give an `extern` with the declaration the summary edge rows of the reference bodies (C2). Its call goes through `os_edge_effects` (`src/check_zir.zrl`), as a body's does, and the default build's masks get the `s -> d` and `-> static` pairs only.
      - 3. _The refusal_ (`os_call`, the `bare_extern` path): under `--provenance`, a call to an `extern` with two or more raw-pointer parameters and no declaration is refused when an argument's origins (the address or contents word) hold a `Frame` or `Param` bit. The message: `the extern 'NAME' declares no #[unsafe(stores(..))], and this call passes it an address of this frame or of a parameter (extern store rule)`.
      - 4. _`memcpy`:_ in `stdlib/mem_raw.zrl`, put `// SAFETY: memcpy copies the n bytes at src into dest, so what src points to is stored where dest points, and it keeps neither pointer.` and `#[unsafe(stores(*src -> dest))]` above `pub extern fn memcpy`, below its comment block. Extend `scripts/check_safety_comments.sh` to require the `// SAFETY:` line above `#[unsafe(stores(` as it does above `#[unsafe(borrows(`. Then run `make man-gen` and `scripts/test_man_pages.sh`.
      - 5. _The `.zri`_ (`src/interface_print.zrl`, `emit_fn`): write the attribute above `extern fn` as written, `*` included. Reading it back goes through the same parser. An imported `extern` without one stays undeclared: the `#[summary]` written for it must not make it count as declared (`bare_extern = f.is_extern && !f.has_summary` in `os_call` reads `has_summary`, so check that path).
      - 6. _Spec_ (commit with the code, not before): in `doc/spec/surface_syntax.md` §2.5, change the `#[unsafe(borrows(..))]` bullet's "`unsafe(..)` marks no other attribute" to "`unsafe(..)` marks one other: an `extern`'s `#[stores(..)]`". Add a bullet for `#[unsafe(stores(p -> q, *p -> q, ...))]` saying what the design note's _The declaration_ and _The pairs_ say. In §9.1, add a paragraph: an `extern` keeps nothing it is given unless it declares it, and under `--provenance` a call to an undeclared `extern` with two or more raw-pointer parameters that passes an address of the frame or a parameter is refused. Give the `memcpy` example. Add an `Extern Store Effects` row to `bench/safety_matrix/matrix.md` and `bench/safety_matrix/README.md` only if `scripts/check_safety_model.sh` needs one for the new tests. Otherwise gap_103's Known gaps entry in `bench/safety_matrix/README.md` says it is refused under `--provenance` and stays `known_gap` until id:z0065.
    - **Must stay accepted:** id:f81f3's F5 list, the 22 safe functions in `src/`, `stdlib/` and `tools/` that call `memcpy` (`build/f81/ext_fns.txt` if it is still there). C6 shows it.
    - **Tests** (new, under `tests/language/memory/provenance/`, each `// flags: --provenance`):
      - `extern_copy_undeclared_refused.zrl`: gap_103's program, `// expected compile fail`, `// EXPECT:` the extern store rule.
      - `extern_copy_declared_frame_source_refused.zrl`: the same with `#[unsafe(stores(*s -> d))]` on its `memcpy`. Refused by the call store rule at `put`'s caller, because `&local` reaches `h.r`.
      - `extern_copy_declared_bytes_accepted.zrl`: a declared `memcpy` copying bytes of a local `[u8; 8]` into a heap `Vec<u8>` the caller owns, `// expected exit 0`. id:f81f3's F6 over-refusal must be gone.
      - `extern_copy_declared_stdlib_accepted.zrl`: `Vec<i32>.clone()` of a local, through stdlib's `memcpy`, `// expected exit 0`.
      - In `tests/modular/iface_attrs/`: `lib_extern_copy.zrl` with a `pub` declared `memcpy` wrapper `extern`, and `lib_extern_bare.zrl` with an undeclared two-pointer `extern`. Callers `prov_reject_extern_copy.zrl`, which passes a frame address through the declared one into a parameter's memory, and `prov_reject_extern_bare.zrl`. Plus a `scripts/test_interface_attrs.sh` assertion that `lib_extern_copy.zri` keeps `#[unsafe(stores(*src -> dest))]` above `extern fn`.
    - **Checks:**
      - C1, before: `timeout -k 5s 30s build/zoril --provenance -I stdlib=stdlib -o /dev/null bench/safety_matrix/probes/gap_103_extern_copy_store_hidden_through_raw_field.zrl` gives rc=0.
      - C2, the rows: `build/yp1/rows_keep.zrl` (recreate if gone: `fn cp(d: *mut &i32, s: *&i32) { unsafe { *d = *s; } }`, `fn st(d: *mut *i32, s: *i32) { unsafe { *d = s; } }`, `fn main() -> i32 { return 0; }`) under `--emit-origins` prints `store ParamContents(1) -> Param(0)` for `cp` and `store Param(1) -> Param(0)` for `st` (recorded by id:yp1er on git:a9b60aa). A declared `extern` with `*s -> d`, and one with `s -> d`, at the same positions behave at a call as `cp` and `st` do. Show it with the two `_refused` tests above, each run again with `cp` or `st` in place of the `extern`: the same verdict and message.
      - C3, after: C1's command gives rc=1 with the extern store rule message at the `memcpy` call in `put`. Without `--provenance`: rc=0, so gap_103 stays `known_gap`.
      - C4: the new tests pass (`./scripts/test.sh tests/language/memory/provenance tests/error_reporting tests/modular`), and `sh scripts/test_interface_attrs.sh` passes.
      - C5, the fix taken out (a scratch compiler without the refusal of Do 3; built with `mk.sh` from id:77rr6's **Scripts**): `extern_copy_undeclared_refused.zrl` and `prov_reject_extern_bare.zrl` fail. With `memcpy`'s declaration taken out of `stdlib/mem_raw.zrl` instead, `extern_copy_declared_stdlib_accepted.zrl` fails.
      - C6: `pdiff.sh` (id:77rr6's **Scripts**) between the compiler before and after prints only gap_103 and the new tests. `rootwarn.sh` gives the same lines with each compiler, since the roots' 22 `memcpy` callers are not refused.
      - C7: the store grid under `--provenance` (id:77rr6's `grid.sh`) gives the same 3932 twins as before, and no unsafe cell is accepted.
      - C8: `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, with its `reject-diff: base verdicts: fresh (no cache)` line and 0 newly accepted. Also `make test`, `sh scripts/run_safety_matrix.sh`, `sh scripts/check_safety_model.sh`, `sh scripts/check_safety_comments.sh`, `make man-gen` with `scripts/test_man_pages.sh`, and the `closure-private-names` gate, since `stdlib/mem_raw.zrl` is in `src/`'s stage1 closure. Quote each `Total:` line.
      - C9: stage1 still builds `src/` with the declaration in place: `make` from a tree with `build/zoril` removed (the stage1 path), rc=0. The fuzz record is stale for `src/` and `stdlib/` (`scripts/check_fuzz_fresh.sh`).
    - **Ends with:** the fix committed, an `**Awaiting review:**` bullet naming C2, C3, C5 and C6, then `tm done`. The check-in is id:g764h.
    - **Awaiting review:** C2 (`*s -> d` and `s -> d` externs match `cp` and `st` with `call store rule` at `put`'s caller), C3 (`gap_103` refused under `--provenance` with `extern store rule` at `12:22`, `rc=0` without), C5 (scratch compiler without Do 3 fails `extern_copy_undeclared_refused.zrl` and `prov_reject_extern_bare.zrl`; removing `memcpy`'s declaration fails `extern_copy_declared_stdlib_accepted.zrl`), C6 (`pdiff.sh` shows `gap_103` + new tests + 4 undeclared 2-ptr extern tests in Stage 2's scope; `rootwarn.sh` gives 189 lines with 0 `memcpy` refusals and 6 `#[borrows()]` warnings on `tools/zbuild` and `tools/ztest`).
    - **Checks recorded (2026-11-20, git:838eafc):**
      - C1: `build/zoril --provenance -I stdlib=stdlib -o /dev/null bench/safety_matrix/probes/gap_103_extern_copy_store_hidden_through_raw_field.zrl` gave `rc=0`.
      - C2: `--emit-origins` on `build/716/rows_keep.zrl` printed `store ParamContents(1) -> Param(0)` for `cp` and `store Param(1) -> Param(0)` for `st`; `cp_twin.zrl`, `st_ext.zrl`, and `st_body.zrl` all gave `rc=1` with `error: provenance: the callee stores an address of this frame into memory that outlives it (call store rule)`.
      - C3: `gap_103` with `--provenance` gave `rc=1` (`12:22: error: provenance: the extern 'memcpy' declares no #[unsafe(stores(..))], and this call passes it an address of this frame or of a parameter (extern store rule)`); without `--provenance`, `rc=0`.
      - C4: `./scripts/test.sh tests/language/memory/provenance tests/error_reporting tests/modular` passed (`Total: 638 run, 638 passed, 0 failed, 0 skipped (2.9s)`); `sh scripts/test_interface_attrs.sh` passed (`[PASS] interface-attrs`).
      - C5: with `build/716/zoril_no_do3`, `extern_copy_undeclared_refused.zrl` and `prov_reject_extern_bare.zrl` failed (`Total: 3 run, 1 passed, 2 failed, 0 skipped`); with `memcpy`'s declaration removed in `build/716/stdlib_nodecl/mem_raw.zrl`, `extern_copy_declared_stdlib_accepted.zrl` failed (`rc=1`, `vec.zrl:181:26: error: provenance: the extern 'memcpy' declares no #[unsafe(stores(..))]...`).
      - C6: `pdiff.sh` between `zoril_base` and `build/zoril` showed `gap_103`, the new tests, and 4 tests with undeclared 2-pointer externs (`141_extern_call_unsafe.zrl`, `test_runtime_memcmp.zrl`, `cb.zrl`, `qsort_callback.zrl`, handled in id:eb38n); `rootwarn.sh` gave 189 lines (0 `memcpy` refusals; 6 `#[borrows()]` warnings on `tools/zbuild/src/util.zrl` and `tools/ztest/src/main.zrl`).
      - C7: `check_store_grid.sh` under `--provenance` gave 3932 twins, `comm -3` = 0 lines, 0 unsafe cells accepted.
      - C8: `REJECT_DIFF_NO_CACHE=1 make preflight-changed` passed (`reject-diff: base verdicts: fresh (no cache); base front end 111 s`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 10596 newly refused, of 69173 programs`, `Total: 1523 run, 1523 passed, 0 failed, 0 skipped (109.2s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.5s)`); `make test` passed (`Total: 3996 run, 3996 passed, 0 failed, 58 skipped (146.2s)`); `sh scripts/run_safety_matrix.sh` (`All probes complete: 505/533 passed. Mismatches: 0`), `sh scripts/check_safety_model.sh` (`PASS: safety_model.md is self-consistent.`), `sh scripts/check_safety_comments.sh` (`PASS: all 179 stdlib unsafe blocks state the invariant they rely on.`), `make man-gen` + `scripts/test_man_pages.sh` (`[PASS] man-pages`), and `closure-private-names` (inside `make test`) all passed.
      - C9: stage1 built `src/` (`rm -f build/zoril && make` -> `rc=0`, `Fixpoint reached: 22994485 bytes of ZIL, identical across two self-hosted generations`); `scripts/check_fuzz_fresh.sh` reported `STALE` for `src/`, `stdlib/`, `tools/zilc`, `tools/zbuild`, `rt/`.

- [x] +safety +tests +AI-G @provenance B3g Stage 2: every `extern` that takes a pointer declares its store effect, or a call passing it a parameter or frame pointer is refused id:eb38n
    > **Created:** 2026-11-19
    > **Branch:** `provenance`
    > **Depends:** id:716bm
    > **Completed:** 2026-11-20

    - **Placed:** directly after id:716bm, whose boundary it removes. It must be done before the series ends (id:z0012), because it ends stage 1's departure from principle 1 (id:f81f3's decision 2).
    - **The decision this builds:** `doc/design/provenance.md` §3, _Store effects of an `extern`_, the _stage 2_ half (git:a9b60aa, id:yp1er). id:716bm built the declaration, its rows, the `.zri` and the stage 1 refusal. This task widens the refusal only.
    - **Do:**
      - Under `--provenance`, apply id:716bm's extern store rule to every `extern` with a parameter that can carry an address (`os_carries`: a raw pointer, or `u64`, `usize`, `i64` or `isize`) or a variadic tail. Apply it also to a call through an `extern "C" fn` value, which has no declaration to read: the message there is `a call through a C function pointer passes it an address of this frame or of a parameter (extern store rule)`.
      - Give each such `extern` in `stdlib/`, `src/`, `tools/`, `tests/` and `bench/` that the widened rule refuses its declaration. That is `#[unsafe(stores())]` where it keeps nothing, with a `// SAFETY:` line in `stdlib/`. In a test, add it only where the rule refuses the test; a test's verdict must not change.
    - **First, the sibling probe (id:f81f3's F9):** add `tests/language/memory/provenance/extern_one_pointer_keeps_frame_refused.zrl` with `// link: extern_one_pointer_keep.s` (`// link:` as `tests/integration/test_ffi.zrl` uses it; check how `scripts/test.sh` resolves the path). The `.s` defines `keep(p)`, which stores `p` in a Zoril `static mut KEPT: *i32` by its symbol. A safe `put(r: &i32) { unsafe { keep(r as *i32); } }` is called with `&local`, then a later safe read goes through an `unsafe` load of `KEPT`. If the `static mut` symbol cannot be reached from the `.s`, have the `.s` keep `p` in its own data and add a second `extern` `kept() -> *i32`. Record which one was used.
    - **Checks:**
      - C1, before: the probe compiled with `--provenance` and run gives rc=0 and prints, or exits with, the dead frame's value. Quote it. Without `--provenance`: the same.
      - C2, a measurement before the error: build the rule as a warning first, and count the refused calls, by `extern`, over the five roots (`rootwarn.sh`, id:77rr6's **Scripts**) and over `tests/` and `bench/` (`pdiff.sh`). Record the counts here before making it an error. If any refused call in `src/`, `stdlib/` or `tools/` is a real hidden store, stop and report it as a finding: it would be a hole, on the public side of `SECURITY.md` (a program shape).
      - C3, after: the probe is refused with the extern store rule under `--provenance` and accepted without it. Add the route to gap_103's Known gaps entry or to class (I) in `bench/safety_matrix/README.md`, as the default build's open route, until id:z0065. Leave the probe counts alone.
      - C4, the fix taken out (the widening reverted in a scratch compiler, built with `mk.sh` from id:77rr6's **Scripts**): the probe is accepted again. With the C function pointer case reverted, a test calling through an `extern "C" fn` value with `&local as *u8` (add `extern_c_fn_pointer_frame_refused.zrl`) is accepted.
      - C5: `pdiff.sh` between the compiler before and after shows only the new tests. Every other changed verdict is a declaration this task added, or it is a stop.
      - C6: the store grid under `--provenance` gives the same 3932 twins and no unsafe cell accepted (`grid.sh`).
      - C7: `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, with its `reject-diff: base verdicts: fresh (no cache)` line and 0 newly accepted. Also `make test`, `sh scripts/run_safety_matrix.sh`, `sh scripts/check_safety_model.sh`, `sh scripts/check_safety_comments.sh`, `make man-gen` with `scripts/test_man_pages.sh`, and stage1 building `src/` (`make` with `build/zoril` removed). Quote each `Total:` line. The fuzz record is stale.
      - C8: `doc/spec/surface_syntax.md` §9.1's paragraph from id:716bm reads "every `extern` that can be passed an address" instead of "two or more raw-pointer parameters".
    - **Ends with:** the fix committed, an `**Awaiting review:**` bullet naming C1 to C5, then `tm done`. The check-in is id:g764h.
    - **Awaiting review:** C1 (before: F9 probe exited 77 with and without `--provenance`, using `kept()` in `extern_one_pointer_keep.s`), C2 (warning measurement: 75 `memset` on 5 roots; 149 on `tests/`/`bench/`: 114 `memset`, 7 `memcmp`, 3 `memcpy`, 2 each `window_*`/`set_frame_callback`/`run`/`destroy`/`clear_frame_callback`/`c_reenter`/`blit_rgba`, 1 each `write`/`stash`/`qsort`/`keep`/`c_run_vtable`/`c_for_each`/`__zoril_syscall_3`; 0 hidden stores in `src/`, `stdlib/`, `tools/`), C3 (`extern_one_pointer_keeps_frame_refused.zrl` and `extern_c_fn_pointer_frame_refused.zrl` refused under `--provenance`, accepted without), C4 (`zoril_base` accepts both new tests), C5 (`pdiff.sh` shows only `extern_c_fn_pointer_frame_refused.zrl`, `extern_one_pointer_keeps_frame_refused.zrl`, and `fn_value_result_accepted.zrl` before its `through_c` fix).
    - **Checks recorded (2026-11-20, git:1aa3e43):**
      - C1: `extern_one_pointer_keeps_frame_refused.zrl` (using `extern_one_pointer_keep.s` with `kept() -> *i32`) compiled and run before the change exited `77` (the dead frame's overwritten stack junk) both with `--provenance` (`prov_run_rc=77`) and without (`def_run_rc=77`).
      - C2: warning-mode measurement: `rootwarn.sh` on 5 roots gave 75 `memset`; `tests/` and `bench/safety_matrix/probes/` gave 149 total (`114 memset`, `7 memcmp`, `3 memcpy`, `2 window_has_userdata`, `2 window_frames`, `2 window_checksum`, `2 set_frame_callback`, `2 run`, `2 destroy`, `2 clear_frame_callback`, `2 c_reenter`, `2 blit_rgba`, `1 write`, `1 stash`, `1 qsort`, `1 keep`, `1 c_run_vtable`, `1 c_for_each`, `1 __zoril_syscall_3`). No hidden store in `src/`, `stdlib/`, or `tools/`.
      - C3: `./scripts/test.sh tests/language/memory/provenance/extern_one_pointer_keeps_frame_refused.zrl tests/language/memory/provenance/extern_c_fn_pointer_frame_refused.zrl` passed (`Total: 3 run, 3 passed, 0 failed, 0 skipped (0.1s)`); both are accepted without `--provenance`; F9 route added to `gap_103`'s Known gaps entry in `bench/safety_matrix/README.md`.
      - C4: with `build/eb3/zoril_base` (without Stage 2 widening or C fn pointer check), both `extern_c_fn_pointer_frame_refused.zrl` and `extern_one_pointer_keeps_frame_refused.zrl` compiled and failed the `_refused` test (`Total: 3 run, 1 passed, 2 failed, 0 skipped`).
      - C5: `pdiff.sh` between `zoril_base` and `build/zoril` showed `extern_c_fn_pointer_frame_refused.zrl`, `extern_one_pointer_keeps_frame_refused.zrl`, and `fn_value_result_accepted.zrl` (whose `through_c` was updated to pass `&K as *i32` instead of a parameter pointer, then passed).
      - C6: `check_store_grid.sh` under `--provenance` gave 3932 twins, `comm -3` = 0 lines, 0 unsafe cells accepted.
      - C7: `REJECT_DIFF_NO_CACHE=1 make preflight-changed` passed (`reject-diff: base verdicts: fresh (no cache); base front end 111 s`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 10596 newly refused, of 69173 programs`, `Total: 1525 run, 1525 passed, 0 failed, 0 skipped (109.1s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.6s)`); `make test` passed (`Total: 4000 run, 4000 passed, 0 failed, 58 skipped (143.4s)`); `sh scripts/run_safety_matrix.sh` (`All probes complete: 505/533 passed. Mismatches: 0`), `sh scripts/check_safety_model.sh` (`PASS: safety_model.md is self-consistent.`), `sh scripts/check_safety_comments.sh` (`PASS: all 180 stdlib unsafe blocks state the invariant they rely on.`), `make man-gen` + `scripts/test_man_pages.sh` (`[PASS] man-pages`), and stage1 build (`rm -f build/zoril && make` -> `rc=0`, `Fixpoint reached: 23008480 bytes of ZIL`) all passed. Fuzz record is stale.
      - C8: `doc/spec/surface_syntax.md` §9.1 updated to "every undeclared `extern` that can be passed an address ... or through an `extern "C" fn` value".

- [x] +diagnostics +AI-G @provenance id:z0066 B3.9 Provenance diagnostics name the origin they found, once per site
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Depends:** id:0m61c
    > **Completed:** 2026-11-20

    - **Found by:** id:z0049's review (correction 8).

    - **Now:** the return rule says "the returned value holds an address of this frame" also when the returned origins are only `Unknown`, and the call store rule often prints the same warning twice at one location: under `--provenance=warn`, `src/fmt/doc.zrl:111:21`, `src/driver/module.zrl:1338:13`, `tools/zbuild/src/build.zrl:580:17`, `tests/unit/test_empty_compile_and_tool_errors.zrl:65:5` (re-checked 2026-11-06 after id:z0092).
    - **Stale examples (2026-11-06):** the `Unknown`-only return was `fn mk3(n: u64) -> Box<H> { let p = @ptr_from_int<*u8>(n); return box H { p: p, n: n }; }`, now accepted (`@ptr_from_int` gives `Raw` since id:z0063), and the duplicate was `fn add(v: &mut Vec<Vec<i32>>) { v.push(Vec::<i32>.new()); }`, now accepted. Find a current `Unknown`-only return first: the sources left are a summary-less call (a `.zri` import with no summary) and an index the walk cannot type.
    - **Do:** word each rule's message by the origin that triggered it (`Frame`: an address of this frame; `Unknown`: an address the compiler cannot trace), and print one diagnostic per site and rule. Update the `EXPECT:` lines of the provenance tests that change, and say so in the commit message.
    - **Checks:**
      - C1: a current `Unknown`-only return, as a program under 15 lines, recorded in this task with the message it gets today (quoted). If none is found in the session, stop and report what was tried: the wording change waits for one.
      - C2: one test per wording (`Frame`, `Unknown`), each with an `// EXPECT:` line for its new message, under `tests/language/memory/provenance/`; both pass.
      - C3: under `--provenance=warn`, each of the four sites in **Now** prints one diagnostic per rule: for each, `grep -c '<file>:<line>:<col>'` on the compiler's output is 1 (or 0 if the site is now accepted); quote the four counts.
      - C4: a test with two different rules at one site prints both (one each), so the de-duplication is per rule, not per site.
      - C5: every `EXPECT:` line changed, listed in the commit message (`git diff --stat -- tests` matches the list).
      - C6: `make test` and `make preflight-changed`, each `Total:` line quoted.
    - **Checks recorded (2026-11-20, git:9d4fc28):**
      - C1: `build/z66/unk_zri.zrl` (`import "nolib.zri"; fn f() -> *u8 { return nolib::mk(); } fn main() -> i32 { return 0; }` with `nolib.zri` `pub fn mk() -> *u8;`) got `build/z66/unk_zri.zrl:2:24: error: provenance: the returned value holds an address of this frame (return rule)` before the change.
      - C2: `return_frame_wording_refused.zrl` (`the returned value holds an address of this frame (return rule)`) and `return_unknown_wording_refused.zrl` (`the returned value holds an address the compiler cannot trace (return rule)`) both pass (`./scripts/test.sh tests/language/memory/provenance`: `Total: 163 run, 163 passed, 0 failed, 0 skipped (0.9s)`).
      - C3: under `--provenance=warn`: `src/fmt/doc.zrl:111:21 count=0`, `src/driver/module.zrl:1338:13 count=0`, `tools/zbuild/src/build.zrl:580:17 count=0`, `tests/unit/test_empty_compile_and_tool_errors.zrl:65:5 count=1` (down from 2).
      - C4: `two_rules_one_site_refused.zrl` prints both `call store rule` and `return rule` at `15:12` (one each) and passes.
      - C5: 0 existing `EXPECT:` lines changed (`git diff --stat -- tests` is empty); the 4 new test files are listed in the commit message.
      - C6: `make test` passed (`Total: 4006 run, 4006 passed, 0 failed, 58 skipped (144.4s)`); `make preflight-changed` passed (`[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 10596 newly refused, of 69173 programs`, `Total: 1528 run, 1528 passed, 0 failed, 0 skipped (109.1s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.7s)`).
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

    - **Moved (2026-11-19, the maintainer's request to group `+AI-G` work):** from after id:z0044 to directly after id:eb38n. It joins that batch of `+AI-G` tasks, and its check-in id:h1yk5 follows the batch's check-in id:g764h. Its only dependency, id:0m61c, is complete. Nothing between its old and new places depends on it. The tests id:77rr6 to id:eb38n add may carry `EXPECT:` lines in the old wording, and this task updates them with the rest (C5).

- [x] +safety +review +AI-D @provenance @checkin Review of the hidden-store fixes: lead 1, `extern` declarations stage 1 and 2 id:g764h
    > **Created:** 2026-11-19
    > **Branch:** `provenance`
    > **Depends:** id:77rr6, id:716bm, id:eb38n
    > **Completed:** 2026-11-20 git:103295f

    - **Placed:** directly after id:eb38n, the last `+AI-G` task of the batch it reviews (id:77rr6, id:716bm, id:eb38n, from id:f81f3's decisions).
    - **Review:** the steps of AGENTS.md's check-in list. Re-run each **Awaiting review:** bullet. Probe the sibling routes: a raw write through a raw pointer in a by-value aggregate, a raw pointer held in a `Vec` (an owner: lead 1 leaves it out), a declared `extern` called through a `fn` value, and an `extern` declared in one module and called from another through `zbuild` (the `.zri` round trip). Confirm that gap_102, gap_103 and F9's test are where the decisions put them: refused under `--provenance`, and the default build's status written in their Known gaps entries.
    - **Review recorded (2026-11-20, git:103295f):**
      - Commits reviewed: `560d963` (id:77rr6), `838eafc` (id:716bm), `1aa3e43` (id:eb38n).
      - Re-ran **Awaiting review:** checks: `gap_102` (`rc=1` under `--provenance` at `10:58` `call store rule`, `rc=0` without), `gap_103` (`rc=1` under `--provenance` at `12:22` `extern store rule`, `rc=0` without), `extern_one_pointer_keeps_frame_refused.zrl` (`rc=1` under `--provenance` at `12:28` `extern store rule`, `rc=0` without), `extern_c_fn_pointer_frame_refused.zrl` (`rc=1` under `--provenance` at `14:14` `extern store rule`, `rc=0` without); `./scripts/test.sh tests/language/memory/provenance tests/error_reporting tests/modular`, `sh scripts/test_interface_attrs.sh`, `sh scripts/check_safety_comments.sh`, and `sh scripts/check_safety_model.sh` all passed.
      - Sibling probes (in `build/g76/`):
        1. Raw write through raw pointer in a by-value aggregate (`fn put(s: Slot, r: &i32)`): refused under `--provenance` (`call store rule`).
        2. Raw pointer held in a `Vec<*mut &i32>` (an owner): accepted under `--provenance` and exits `77` (dead frame junk), as expected because lead 1 intentionally excludes owners (`!OS_Q_HANDLE && OS_Q_LOOSE_RAW`, per id:f81f3 / id:95w4z).
        3. Declared `extern` called through a `fn` value: direct local binding (`let f: fn(...) = unsafe { memcpy }; f(...)`) is refused (`call store rule`, resolved by `os_known_call`). However, an `extern fn` (both declared `#[unsafe(stores(p -> static))]` and undeclared) made into a Zoril `fn(*i32)` value via `unsafe { keep }` and passed to a `fn` parameter `apply(f: fn(*i32), p: *i32)` is accepted under `--provenance` (`os_is_c_fn_ptr` is false for `fn(...)`, and `os_known_call` does not know a parameter). Added to id:4f0ew's sibling list.
        4. `zbuild` `.zri` round trip: both `#[unsafe(stores(*src -> dest))] pub extern fn memcpy` (refused by `call store rule`) and undeclared `pub extern fn keep(p: *i32)` (refused by `extern store rule`) survive `.zri` emission and separate compilation through `build/zbuild --provenance`.
      - Defects found and fixed in `git:103295f`: `tests/language/memory/provenance/extern_one_pointer_keep.s` was ignored by `*.s` in `.gitignore` and never committed (would be missing in a fresh clone/tarball); `scripts/check_clean_tree.sh` had a duplicate exemption line; two test comments carried `(id:eb38n)`. Added `!tests/language/memory/provenance/extern_one_pointer_keep.s` to `.gitignore`, tracked the `.s` file, deduplicated `check_clean_tree.sh`, and removed the task IDs from test comments (`sh scripts/check_clean_tree.sh` passed; `./scripts/test.sh` on the two tests: `Total: 3 run, 3 passed, 0 failed, 0 skipped (0.1s)`).
      - Verified `stage0-c` change in `838eafc` is justified under `AGENTS.md` (unblocks stage0-c's suites parsing `stdlib/mem_raw.zrl`, with regression test `bootstrap/stage0-c/tests/fixed_bugs/unsafe_stores_attribute_ignored.zrl`), `fn_value_result_accepted.zrl` edit in `1aa3e43` adapts `through_c` to the new `extern "C" fn` rule without weakening coverage, and `gap_102`/`gap_103`/F9's status in `bench/safety_matrix/README.md` matches the decisions.

- [x] +safety +review +AI-D @provenance @checkin Review of the provenance diagnostics wording and de-duplication (id:z0066) id:h1yk5
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Depends:** id:z0066
    > **Completed:** 2026-11-20 git:9d4fc28

    - **Placed:** directly after id:z0066, the `+AI-G` batch it reviews (a review of the task list, the maintainer's request, 2026-11-17: id:z0066 had no check-in, and it changes the checker's diagnostics and the `EXPECT:` lines of provenance tests). id:z0065, the next task that builds on it, depends on this one.

    - **Checks:**
      - Re-read the queue and `git log -p` of id:z0066's commits.
      - Re-run id:z0066's C3 (one diagnostic per site and rule at the four sites) and C4 (two rules at one site print both).
      - No program is accepted that was refused: `REJECT_DIFF_NO_CACHE=1 make preflight-changed` shows 0 newly accepted, and the same count under `--provenance` over `tests/language/memory/provenance/` and the `gap_*` probes before and after (a de-duplication keyed too coarsely must not drop the only error of a function).
      - Every `EXPECT:` line changed is in the commit message's list (C5), and none changed from one rule's message to another rule's.

    - **Moved (2026-11-19, with id:z0066):** to directly after id:g764h, so that both check-ins of the `+AI-G` batch run back to back in one `+AI-D` session. It is still before id:z0065, which depends on it.
    - **Review recorded (2026-11-20, git:9d4fc28):**
      - Re-read queue and `git show 9d4fc28`: `os_mark_diag` keys on `(rule, span.line, span.col)` per function and only suppresses duplicates after the first diagnostic for that `(rule, line, col)` has already incremented `c.errors`, so it cannot drop the only error of a function. `os_origin_msg` selects the Frame vs Unknown wording via `os_has_any_frame`.
      - Re-ran C3 under `--provenance=warn`: `src/fmt/doc.zrl:111:21 count=0`, `src/driver/module.zrl:1338:13 count=0`, `tools/zbuild/src/build.zrl:580:17 count=0`, `tests/unit/test_empty_compile_and_tool_errors.zrl:65:5 count=1`.
      - Re-ran C4 on `two_rules_one_site_refused.zrl`: prints both `call store rule` and `return rule` at `15:12` (one each).
      - Verified no program accepted that was refused: `REJECT_DIFF_NO_CACHE=1 make preflight-changed` passed (`reject-diff: base verdicts: fresh (no cache); base front end 111 s`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 10596 newly refused, of 69173 programs`, `Total: 1528 run, 1528 passed, 0 failed, 0 skipped (109.3s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.6s)`). Under `--provenance`, before (`1aa3e43`, `build/h1y/zoril_before`) and after (`HEAD`) both gave `provenance 107/162 refused; gap_* 99/103 refused`.
      - Verified C5: `git show --stat 9d4fc28 -- tests/` shows 0 existing `EXPECT:` lines changed and only the 4 new files listed in the commit message. No defects found.

- [x] +safety +measurement +AI-D @provenance B1.8c Measure: a store through a local raw pointer adds the stored value's origins to that local, so a heap block holding a frame address cannot leave the frame id:71a06
    > **Created:** 2026-11-14
    > **Branch:** `provenance`
    > **Depends:** id:z0073, id:0m61c
    > **Check-in:** stop for review after it if the rule is kept: it changes a safety rule.
    > **Completed:** 2026-11-20 git:9a29f44

    - **Placed:** before id:z0012, which it blocks: id:z0012 deletes the old region rule, the only rule that refuses case C of id:z0073 today.

    - **Why (the maintainer's decision in id:z0073, 2026-11-14):** case C (a frame address stored, inside `unsafe`, through the result of a `#[fresh]` function or a block from `zoril_allocator_alloc(null, ..)`, the pointer then returned or put into a global) is decided by measurement. The three programs are `tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`, `heap_block_store_through_old_rule_refused.zrl` and `heap_block_into_global_old_rule_refused.zrl`: refused by the old region rule only, accepted by the new rules since id:z0076 (the pointer has no origins, so a store through it reaches nothing they follow).
    - **Candidate rule (not tried; from the review, 2026-11-14):** a store through a raw pointer held by a local `p` (`*p = v`, `p[i] = v`, a field through it) does `O(p) |= O(v)`, as a write into a projection of a local does. `p` then holds `Frame` when `v` does, and the return rule and the store rule refuse `p` leaving the frame. Say first whether the transfer already does this for a raw pointer with origins, and why a pointer with none is skipped.
    - **Measure:** build a scratch compiler with the candidate (under `build/`, never replacing `build/zoril`), with the old rules off as id:z0074 builds it or under `--provenance` alone: 1. the three programs above: refused or not, and by which rule. 2. `--provenance=warn` over `src/main.zrl`, `tools/zbuild/src/main.zrl`, `tools/zilc` and the test programs (`build/z92/measure.sh`, 672 programs at id:z0092): the warning count before and after, and each new warning read (a real escape, or a safe program refused). 3. the store grid under `--provenance`: no unsafe cell newly accepted, the safe twins newly refused counted by axis. Probe the siblings: the pointer copied to a second local before the store; the pointer held in a struct field of a local; the store made by a callee given the pointer; a pointer from `@ptr_from_int` (`Raw`, exempt as a value by id:z0063: say whether it stays exempt as a carrier).
    - **Then decide, by the maintainer's rule:** if the candidate refuses the three and adds no refusal in the tree (or only real escapes), keep it: commit it with the three tests' `EXPECT:` lines naming the new rule, and say so here. If it refuses safe programs in the tree, do not keep it: case C is outside the guarantee, recorded in `doc/spec/safety_model.md` and `doc/spec/unsafe_policy.md` beside case A, and the three tests become tests of the accept (their expected result changes: stop and report, as `AGENTS.md` asks for a changed expectation).
    - **Checks:** C1 the three programs' results before and after, each quoted. C2 the warning counts before and after with their command, and every new warning listed with its reading. C3 the store grid's summary, quoted. C4 each sibling probe's program and result. C5 the decision recorded here with the figure that made it; if kept, the candidate taken out and the three tests watched to fail; `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, each `Total:` and the `fresh (no cache)` line quoted.

    - **Moved (2026-11-17, a review of the queue against `doc/design/provenance.md`, the maintainer's request):** from after id:z0074 to directly before id:z0065, and added to the **Depends:** of id:z0065 and id:z0074. If the candidate rule is kept, it refuses more under the new rules. So it has to land before id:z0065 makes those rules the default and re-records the store grid, and before id:z0074 lists what only the old rules refuse: its three known members (the `#[fresh]` and heap-block tests) are exactly this task's case C. Before, id:z0074 came first in the queue and would have read that list before the decision existed.
    - **Measured (2026-11-20, scratch compiler `build/71a/zoril_cand` on `git:103295f`, awaiting maintainer decision):**
      - **Why a raw pointer with origins or without is skipped today:** in `src/check_zir.zrl`, `os_walk` sets `tm |= O(p) | S(p)` and `crossed = true` on `*p = v`, and `os_store` then calls `os_write_memory(dm, vo, vs)` and returns without ever writing into `O(p)` (`pl.base`). When `p` has origins (`O(p) = {Frame(slot)}`), `os_write_memory` updates `O(slot)`, not `O(p)`. When `p` comes from `#[fresh]` or `zoril_allocator_alloc(0, ..)`, `O(p) = S(p) = {}` (`#[fresh]` clears `ORIGIN_RAW`), so `dm` is empty, `os_write_memory` updates zero locals, `os_check_store` sees `os_external(os_dest_reach(dm)) == false`, and `return p` / `G = p` see `O(p) = {}`.
      - **Candidate patch (`build/71a/src_cand/src/check_zir.zrl`):** track `walk_raw` in `os_walk` (set when `steps_in` crosses `ILTYPE_RAWPTR` or `ILTYPE_RAWPTRMUT`), and in `ZirStmt.Assign` after `os_store`, when `crossed && raw_crossed`, do `O(pl.base) |= O(v)` (`os_or(c, pl.base as usize, os_t(c, OS_T_VO))`).
      - **C1 (the three case-C tests under `--provenance`):** before (`./build/zoril`), all 3 emit only `region escape: a pointer to local stack storage is written to memory that outlives this function` (0 `provenance:` diagnostics). After (`./build/71a/zoril_cand`), `fresh_store_through_old_rule_refused.zrl` -> `17:23: error: provenance: the returned value holds an address of this frame (return rule)`; `heap_block_store_through_old_rule_refused.zrl` -> `13:23: error: provenance: the returned value holds an address of this frame (return rule)`; `heap_block_into_global_old_rule_refused.zrl` -> `18:9: error: provenance: a value holding an address of this frame is stored into memory that outlives it (store rule)` and `23:5: error: provenance: the callee stores an address the compiler cannot trace into a global (call store rule)`.
      - **C2 (`--provenance=warn` over the 5 roots + `pdiff.sh` over `tests/` and `bench/safety_matrix/probes/`):** `pdiff count: 0` across `tests/` and `bench/safety_matrix/probes/`. On the 5 roots (`sh build/71a/rootwarn.sh`), `188` before -> `190` after (`+2` new warnings, both on safe code in `src/`; 0 in `tools/*`): (1) `src/check_zir.zrl:89:9`: `ZirAnalysisState::clone` (`#[borrows(arena)]`) warns `#[borrows(..)] leaves out 'self'` because `*dest = ZirAnalysisState { ..., borrows: self.borrows.clone_in_raw(arena), ... }` copies `ParamContents(self)` from `clone_in_raw` (id:sjqmy's precision issue) into `O(dest)`; (2) `src/main.zrl:901:15`: `parse_program(&o, ...)` gains `the callee stores an address the compiler cannot trace into memory that outlives it (call store rule)` (and `906:12` shifts from `into a global` to `into memory that outlives it`), from `*mr_owned = mr` and `(*(*parser).state).iface_dir = o.iface_dir` into the arena.
      - **C3 (store grid under `--provenance`, `build/71a/zoril_cand_prov.sh`):** 0 unsafe cells accepted; 3932 safe twins refused (`comm -3` against `bench/fuzz/store_grid_twin_rejections.txt` = 0 lines).
      - **C4 (sibling probes in `build/71a/sibs/`):** `sib1_copy.zrl` (`let q = p; unsafe { *q = &x; } return p;`) is NOT refused by provenance (old region rule only; `O(q)` gets `Frame(x)`, `O(p)` stays `{}`); `sib2_struct_field.zrl` (`let s = S { p: block() }; unsafe { *s.p = &x; } return s;`) is REFUSED by `return rule` (`11:25`); `sib3_callee.zrl` (`fn put(p: *mut &i32, r: &i32) { unsafe { *p = r; } } ... put(p, &x); return p;`) is NOT refused by provenance (old region rule only; `O(p)` is `{}`); `sib4a_ptr_from_int_plain.zrl` and `sib4c_ptr_from_int_int_store.zrl` stay ACCEPTED; `sib4b_ptr_from_int_frame_store.zrl` is refused by `store rule` (base and cand) and also `return rule` (cand).
      - **C5 (decision, maintainer approved Option 1 on 2026-11-20, git:9a29f44):** do not keep the candidate (refuses 2 safe sites in `src/` and misses the aliasing copy and callee siblings `sib1_copy`/`sib3_callee`). Documented case C beside case A in `doc/spec/safety_model.md` §3.2 and `doc/spec/unsafe_policy.md` §1 as outside the provenance guarantee. Kept the three case-C tests as `expected compile fail` while the old region rule remains active, updated their comments to state the decision, and noted on `id:z0074` and `id:z0012` that they flip to accept tests when `id:z0012` deletes the old region rule. `make test-changed BASE=HEAD`: `Total: 945 run, 945 passed, 0 failed, 0 skipped (15.5s)` (no compiled code changed; `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed` not re-run per AGENTS.md, covered by `id:h1yk5` on `git:9d4fc28`).

- [x] +safety +design +AI-D @provenance A call result tied through a reference to an owner holds what the owner holds, not the storage it owns, unless its type can point there id:sjqmy
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Completed:** 2026-11-20 git:04be73c

    - **Found by:** id:z0084, reading the reproducers P1 to P5 that the check-in id:n177h placed on it (`build/provenance/build/z84/p1.zrl`-`p5.zrl`).
    - **Placed:** directly before id:z0065, which it blocks (P1 to P4 are safe user code the default flip would refuse), and added to its **Depends:**.
    - **Now (compiler git:dadd49e):** P1 (`return v.clone()` of a local `Vec<u8>`), P2 (`Vec<[u8]>` holding a parameter's view), P3 (`String`) are refused by the return rule, which reads only `O`: the clone's result is `_8 O={Frame(_1)}`, `_1` the local `Vec`'s buffer. `Clone for Vec` reads `self.raw` and the elements through `self`, so its summary ties the result to `ParamContents(0)`, and the caller maps that to everything `&v` reaches through (`os_through_plus`), which includes `S(v)`, the buffer. `v.as_slice()` has the same summary bit and must keep `S(v)` (`build/z84/u1.zrl`: `return v.as_slice()` of a local `Vec`). P4 (`out.resize(1, v)`) is refused inside `stdlib/vec.zrl`'s `resize` (`value.clone()` of a by-value parameter, whose storage is `Frame(value)`) and at the call.
    - **Measured (a scratch compiler, not a rule):** in `os_call`'s `in_ties` branch, reading the tie through one level and keeping only what the pointee holds (`os_through_split` into `O`, its `S` dropped) makes P1 to P4 accepted and leaves P5's `c.push(&buf)` refused; it also accepts `build/z84/u1.zrl`, so as it stands it is unsound. The field-insensitive summary cannot tell `self.raw` (what the owner holds) from `self.data` (the storage it owns).
    - **Decide:** how a summary or the caller tells the two apart. Candidates: (a) a summary bit per parameter for "the storage what the parameter reaches owns" beside `ParamContents` (a read of an owner's own raw pointer field through the parameter gives it; `.zri` and edges carry it); (b) at the caller, leave `S` of the pointee out of a tie when the result's type can hold no pointer to anything the pointee's owned storage holds in place (`Vec<u8>` cannot point at a `u8` buffer except through its own `data`, which points into its own storage; `Vec<&u8>` can); (c) accept P1 to P3 as a bound, with a rewrite. Probe each against `u1.zrl`, `vec_clone_frame_views_returned_refused.zrl` (refused today for this reason, not for its views: id:z0084's **Consequence** bullet), `fn wrap(v: &Vec<i32>) -> Vec<[i32]>` pushing `v.as_slice()`, and a `Vec<Arena>` whose arena lies in the buffer.
    - **P5** (`c = v.clone(); c.push(&buf); return c;` with `v: &Vec<[u8]>`): the push is refused by the call store rule because `c`'s storage is the caller's arena (`ParamContents(0)`), which the design treats as external (§3, _Calls through a `fn` value_: "a frame view pushed into such a `Vec` built from a parameter's `fn` value is refused"). The buffer is fresh, and only `c` reaches it, so the stored view is unreachable once `c` is gone; whether that is accepted is part of the decision (id:n177h expected only the return rule). The `return c` refusal stays.
    - **Checks:** C1 the decision and its reason in the design note §3. C2 P1 to P4 accepted (or the bound and its rewrite in `KNOWN_ISSUES.md` §5, written by id:z0065), `u1.zrl` and `vec_clone_frame_views_returned_refused.zrl` refused; with `v.push(&buf)` taken out of the latter, accepted. C3 the siblings above probed, each with a test. C4 the store grid under `--provenance`, `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed`.

    - **Related work parked (2026-11-18, id:bfd1z):** candidate (a) above is close to the `ParamOwned` word id:bfd1z built and measured. That word is a subset of ParamContents, written by an owning read (a raw pointer, a box, a 64-bit integer, a type parameter) and cleared by a read of a reference or a slice. It was not committed, because a held tie would free only 5 of the 84 declaration sites. Its patch against git:cd7e10d (**Patch: the word**), checks C1 to C4 and Findings A to C are in id:bfd1z's text in `completed.tm.md`. Finding A matters here: integers must stay owning reads, since a plain `as` cast makes a pointer with no Raw origin. The word gives the summary what this task needs, but no rule reads it yet. Here it would be read at the caller, in `os_call`'s tie arm: leave out `S` of the pointee where the callee's tie has no ParamOwned. Measure P1 to P5 and `u1.zrl` with the patch applied before choosing between (a), (b) and (c).
    - **Analysis (2026-11-20, on `git:9a29f44`, awaiting maintainer decision):**
      - **Current behavior of P1–P5 and `u1.zrl`:** since `id:mztqb` (`4241f2c`, `cd7e10d`, 2026-11-18) dropped `#[borrows()]` from `Clone for Vec<T>` and `Clone for String`, P1, P2, and P3 are **already refused in the default build** by the borrow checker (`cannot return 'v' a reference into storage owned by this frame...`) as well as under `--provenance` (`return rule`). P4 (`out.resize(1, v)` with `v: Vec<[u8]>`) is the only one accepted in the default build and refused under `--provenance` (`stdlib/vec.zrl:399:22` store rule + `p4.zrl:4:85` call store rule); 0 `.resize()` calls in `src/`, `stdlib/`, `tools/`, or `tests/` pass an owning `T` (all pass scalars or non-owning structs, and `423_resize_clones_drop_type_accepted.zrl` / `clone_returned_accepted.zrl` pass under `--provenance`). P5 is refused in both modes (`c.push(&buf)` is a real arena escape when `v` is arena-backed, since `v.clone()` reuses `v.raw_arena()`). `u1.zrl` is refused in both modes.
      - **Candidate (a) (`ParamOwned` / `ret_held`):** `id:bfd1z`'s inferred word alone does **not** fire on `Clone for Vec<T>` or `Clone for String` (`stdlib/clone.zrl`), because both contain `unsafe` blocks and call `self.raw_arena()` (`*mut ArenaHeader`), setting `os_ret_owned` to all-1s (`os_ret_held == 0`). Making (a) work on `Clone` requires H2 (`id:42ae2`: `#[unsafe(borrows(*self))]`) + H3 (`id:mqh84`: borrow checker reading `ret_held`), which the maintainer deferred to `future.tm.md` after `id:z0012` on 2026-11-18.
      - **Candidate (b) (caller type-based `S`-drop):** cannot make P1–P3 compile while the borrow checker keeps `self` borrowed until H2+H3; only frees P4 (0 callers in the tree), and is fragile on `Vec<Arena>` (returned `Vec`'s `arena: *mut ArenaHeader` can point into `v`'s buffer) and `Vec<T>`'s raw `data: *mut T`.
      - **Recommendation — Candidate (c):** document P1–P4 as a known bound in `doc/design/provenance.md` §3 and `KNOWN_ISSUES.md` §5 (with rewrites: move directly / `clone_in(&arena)` / push loop) until H2+H3 (`id:42ae2`, `id:mqh84`) resume after `id:z0012` (where `os_call`'s tie arm reads `ret_held` alongside H3's borrow-checker change). Keep P5's `c.push(&buf)` and `return c` both refused. Add the sibling tests (`u1.zrl`, `wrap(v: &Vec<i32>) -> Vec<[i32]>`, `Vec<Arena>`, `vec_clone_frame_views_returned_refused.zrl`) and close `id:sjqmy`.
    - **Checks recorded (2026-11-20, maintainer approved Candidate (c), git:04be73c):**
      - C1: recorded Candidate (c) and its reason in `doc/design/provenance.md` §3 (_Ties through a reference to an owner_).
      - C2: recorded the bound and rewrites in `KNOWN_ISSUES.md` §5, and noted the `os_call` `ret_held` hook on `id:mqh84` in `future.tm.md`. `vec_as_slice_returned_refused.zrl` (`u1.zrl`) and `vec_clone_frame_views_returned_refused.zrl` both refused by `return rule`.
      - C3: added and verified all 4 sibling refusal tests under `tests/language/memory/provenance/`: `vec_as_slice_returned_refused.zrl`, `vec_wrap_slice_returned_refused.zrl`, `vec_arena_element_returned_refused.zrl`, and `vec_clone_push_frame_view_refused.zrl` (P5, `call store rule` + `return rule`).
      - C4: `make test-changed BASE=HEAD` ran the full suite and passed (`Total: 4014 run, 4014 passed, 0 failed, 58 skipped (144.5s)`). No compiled code changed; store grid and `REJECT_DIFF_NO_CACHE=1 make preflight-changed` unchanged from `id:h1yk5` on `git:9d4fc28`.

- [x] +safety +tests +AI-D @provenance B4a.1 Fix extend_from_slice (probes 419/420), String.push_str byte-copy ties (zbuild/ztest), and undeclared externs in tests id:fnr7r
    > **Created:** 2026-11-20
    > **Branch:** `provenance`
    > **Depends:** id:sjqmy
    > **Completed:** 2026-11-20 git:bb7a091

    - **Placed:** before id:z0065, which it blocks (3 `accept` probes and 6 warnings in `tools/zbuild` + `tools/ztest` fail under `--provenance`, and id:z0065 forbids newly refusing `accept` probes without a task).
    - **Do:**
      - 1. `Vec::extend_from_slice` (`stdlib/vec.zrl:409`): remove or fix `#[stores(slice -> self)]` so `419_extend_from_slice_stack_bytes_accepted.zrl` and `420_extend_from_slice_caller_arena_views_accepted.zrl` are accepted under `--provenance`, while `gap_56_extern_copy_extend_from_slice.zrl` and `418_extend_from_slice_frame_views_rejected.zrl` stay refused (verify both default and `--provenance` modes; check whether the body's `Clone` loop already carries the store summary now that `Clone` dropped `#[borrows()]`).
      - 2. `String.push_str` byte-copy ties (`tools/zbuild/src/util.zrl:127` `join_path`, `tools/ztest/src/main.zrl:54,62` `cat2`/`item_path`): decide why `memcpy`'s `#[unsafe(stores(*src -> dest))]` on `u8` bytes ties a `String` (`u8` elements) to its source slice (whether `String.push_str` / `os_edge_effects` should not propagate origins into non-carrying `u8` storage, or whether `join_path`/`cat2`/`item_path` take `#[unsafe(borrows(..))]`), implement the chosen fix, and verify 0 warnings in `tools/zbuild` and `tools/ztest` under `--provenance=warn`.
      - 3. Undeclared `extern`s in tests: add `#[unsafe(stores(..))]` to `bench/safety_matrix/probes/141_extern_call_unsafe.zrl` (`memcmp`), `tests/stdlib/test_runtime_memcmp.zrl`, `tests/ffi_callback/include/cb.zrl`, `tests/hosted/include/qsort_callback.zrl`, and `tests/platform_layer/include/platform.zrl` (and inspect `platform.zrl:55` unknown-call store rule) without changing any test's expected verdict.
    - **Checks:**
      - C1: `419`, `420`, and `141` pass under `--provenance`; `gap_56` and `418` stay refused under `--provenance` (and `418` in default mode).
      - C2: `tools/zbuild/src/main.zrl` and `tools/ztest/src/main.zrl` produce 0 provenance warnings under `--provenance=warn`.
      - C3: the 5 undeclared-`extern` tests compile under `--provenance` with their existing verdicts unchanged.
      - C4: `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed` (0 newly accepted, quoting `reject-diff: base verdicts: fresh (no cache)`), and `sh scripts/run_safety_matrix.sh`.
    - **Checks recorded (2026-11-20, git:bb7a091):**
      - Decision for item 2: `extend_bytes` calls `memcpy` (`#[unsafe(stores(*src -> dest))]`) on `bytes.ptr`, giving `extend_bytes` / `String.push_str` a `ParamContents(1) -> ParamContents(0)` edge that even refused copying a local `String.as_slice()` into an `Arena`-backed `String`. Added `os_contents_non_carrying` in `src/check_zir.zrl` so `os_param_origin(..., contents=true)` skips safe slices/references (`[T]`, `&T`, `&mut T`) whose element/referent type carries no address (`!os_carries`), while keeping raw pointers (`*u8`) tracked for `memcpy` (`gap_103`). Added regression test `tests/language/memory/provenance/string_push_str_local_into_arena_accepted.zrl`.
      - C1: under `--provenance`, `419`, `420`, and `141` all gave `rc=0`; `gap_56` (`call store rule`) and `418` (`call store rule` + borrow error) gave `rc=1` under `--provenance`, and `418` stayed `rc=1` in default mode.
      - C2: `tools/zbuild/src/main.zrl` and `tools/ztest/src/main.zrl` both produced 0 provenance warnings under `--provenance=warn`.
      - C3: `141_extern_call_unsafe.zrl`, `test_runtime_memcmp.zrl`, `cb.zrl`, `qsort_callback.zrl`, `platform.zrl`, and `app.zrl` all compiled with `rc=0` under `--provenance` (`platform.zrl`/`app.zrl` pass `Frame` by value to `handler` so `trampoline` does not hand a stack reference to an unknown `fn` value); `./scripts/test_platform_layer.sh` and `./scripts/test_ffi_callback.sh` passed.
      - C4: `make test` passed (`Total: 4016 run, 4016 passed, 0 failed, 58 skipped (144.2s)`); `REJECT_DIFF_NO_CACHE=1 make preflight-changed` passed (`reject-diff: base verdicts: fresh (no cache); base front end 112 s`, `[PASS] reject-diff: 2 newly accepted (none that must be refused, or all allowed), 10596 newly refused, of 69173 programs against a484d11487430a4f709006c069b68454b476b98a` — both newly accepted are `bench/safety_matrix/probes/141_extern_call_unsafe.zrl` whole-program and zbuild, `probe-accept`, because base `a484d11` does not parse `#[unsafe(stores())]`; `Total: 1533 run, 1533 passed, 0 failed, 0 skipped (109.3s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.6s)`); `sh scripts/run_safety_matrix.sh` passed (`All probes complete: 505/533 passed. Mismatches: 0`); `make man-gen` + `scripts/test_man_pages.sh` passed (`[PASS] man-pages`). Fuzz record is stale for `src/` and `stdlib/`.

- [x] +safety +tests +AI-D @provenance B4a.2 Resolve the remaining src/ --provenance=warn sites and inspect the 7 non-extern tests id:ejjzw
    > **Created:** 2026-11-20
    > **Branch:** `provenance`
    > **Depends:** id:fnr7r
    > **Completed:** 2026-11-20 git:d1ef2e9

    - **Placed:** before id:z0065, which it blocks (`src/main.zrl` has 182 `--provenance=warn` warnings and 7 non-extern tests fail under `--provenance`).
    - **Do:**
      - 1. Resolve the 3 root warning sites in `src/` (`src/driver/module.zrl:1422,1452,1477,1501` `Driver::lower_fn_body` pushing `OsPending { zir: zir_func }`; `src/driver/module.zrl:864` `Driver::set_ice_context` causing 14 global warnings; and `src/mono.zrl:296` / `src/lower_zir/expr.zrl:3373` passing `&f` plus the 162 `Unknown` call-store warnings propagating through the `lower_expr` mutual-recursion cycle), following id:z0064's classification (real escape: fix code; safe arena-lifetime invariant: explicit `unsafe` with `// SAFETY:` or code restructuring).
      - 2. Inspect and resolve the 7 remaining non-extern tests newly refused under `--provenance`: `tests/language/closures/closure_type_inference.zrl`, `tests/language/enums/variant_several_args_drop_once.zrl`, `tests/language/match/match_by_value_drops_once.zrl`, `tests/language/match/match_skipped_parts_dropped.zrl`, `tests/language/memory/origins/byval_vec_param.zrl`, `tests/language/modules/trait_names.zrl`, and `tests/unit/test_empty_compile_and_tool_errors.zrl`. Stop and report if any test's expected verdict would change.
    - **Checks:**
      - C1: all 5 roots (`src/main.zrl`, `tools/zilc`, `tools/zbuild`, `tools/zman`, `tools/ztest`) produce **0** provenance warnings under `--provenance=warn`.
      - C2: all 7 tests pass under `--provenance` (or any real escape / precision task is split and reported).
      - C3: `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed` (quoting each `Total:` line and `reject-diff: base verdicts: fresh (no cache)`).
    - **Checks recorded (2026-11-20, git:d1ef2e9):**
      - Root causes in `src/`: all 182 warnings collapsed to 3 stack-address roots — `Monomorphizer::instantiate_function` (`src/mono.zrl`, copying `Decl.Fn(f)` onto the stack; fixed by matching `p_decl` by reference), `ZirLowerer::lower_closure` (`src/lower_zir/expr.zrl`, stack `FnDecl`; fixed by allocating in `self.arena`), and `Driver::lower_fn_body` (`src/driver/module.zrl`, stack `ZirFunction`, `OriginSets`, and `ZirModule`; fixed by allocating in `self.scratch_arena`). Once those 3 were fixed, all 162 `Unknown` cycle warnings and all 14 `set_ice_context` global warnings disappeared.
      - C1: under `--provenance=warn`, all 5 roots produced **0** provenance warnings (`src/main.zrl -> 0`, `tools/zilc/src/main.zrl -> 0`, `tools/zbuild/src/main.zrl -> 0`, `tools/zman/src/main.zrl -> 0`, `tools/ztest/src/main.zrl -> 0`).
      - C2: 6 of the 7 tests pass under `--provenance` (`rc=0`) with existing verdicts unchanged: `closure_type_inference.zrl` and `trait_names.zrl` fixed by skipping non-pointer arguments (`!os_holds_pointer`) as store destinations in `os_unknown_call` (`Iterator::fold` with `u64`/`usize` accumulator); `variant_several_args_drop_once.zrl`, `match_by_value_drops_once.zrl`, and `match_skipped_parts_dropped.zrl` updated to use a `static mut DROP_FLAG` in `count()` instead of passing a stack address to an unknown `fn(*mut u8)`; `test_empty_compile_and_tool_errors.zrl` uses a local `Arena` for `Command` instead of storing stack slices into the caller's `arena`. The 7th test (`tests/language/memory/origins/byval_vec_param.zrl`) is `gap_32` itself (an intentional unsafe program with `// expected exit 42` in default mode); it stays unchanged here and flips to `// expected compile fail` in `id:z0065` when `--provenance` becomes the default.
      - C3: `make test` passed (`Total: 4016 run, 4016 passed, 0 failed, 58 skipped (143.9s)`); `REJECT_DIFF_NO_CACHE=1 make preflight-changed` passed (`reject-diff: base verdicts: fresh (no cache); base front end 112 s`, `[PASS] reject-diff: 2 newly accepted (none that must be refused, or all allowed), 10596 newly refused, of 69173 programs against a484d11487430a4f709006c069b68454b476b98a` — the same 2 `141_extern_call_unsafe.zrl` `probe-accept` entries; `Total: 1533 run, 1533 passed, 0 failed, 0 skipped (109.2s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.7s)`). Fuzz record is stale for `src/`.

- [x] +safety +tests +AI-D @provenance id:z0065 B4a The new rules on by default, beside the old ones
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Depends:** id:z0064, id:z0075, id:z0088, id:z0092, id:z0180, id:z0093, id:z0094, id:z0097, id:z0087, id:z0086, id:z0084, id:z0089, id:z0090, id:7kbpd, id:z0066, id:h1yk5, id:w17jf, id:nc3ym, id:4by24, id:z0091, id:71a06, id:sjqmy, id:fqf8x, id:fnr7r, id:ejjzw
    > **Check-in:** stop for review after it.
    > **Completed:** 2026-11-20 git:1aba284

    - **Split from:** id:z0012.
    - **Depends changed (2026-11-15, the check-in id:n177h):** id:z0084 added: it is the over-rejection of safe user code (a clone of a local `Vec` or `String` returned, `Vec<Vec<T>>.resize`) that this task requires to have its own task done first.
    - **Ordering note:** this task only refuses more, and depends in substance only on id:z0064 (the tree must be clean); the maintainer may move it ahead of id:z0011 and id:z0044 to close the escape holes for users sooner. (id:z0085 and id:z0091 are deferred to `future.tm.md`, and id:z0095 and id:z0096 are holes in both modes, not dependencies.)

    - **Do:** make the rules of `--provenance` run by default **in addition to** the old rules (nothing is deleted here; the old rules still run). Keep `--provenance=warn` as a developer option or retire it; decide and record. Resolve whatever the default build of `src/`, `stdlib/`, `tools/` and `tests/` now refuses, per id:z0064's classification (a real escape: fix the code; an over-rejection: it should already have its own task done).
    - **Code changes id:z0064 left here (2026-11-06):** `Driver::lower_fn_body` pushes `OsPending { zir: zir_func }` into `self.os_pending` (`src/driver/module.zrl`, 2 warnings): `zir_func`'s slices are tied to the local `zir_low` though they live in the driver's scratch arena; change the code or route it to id:z0084's rule. `Driver::set_ice_context` stores an arena-built note into a global through `set_ice_note`'s `#[stores(note -> static)]` (`src/driver/module.zrl:864`): a true store, safe only because the arena lives as long as the program, and no warning of its own once the other roots are gone; if the default build refuses it, an explicit `unsafe` with a `// SAFETY:` comment naming that invariant, not a rule.
    - **Probes:** every `known_gap` probe the new rules refuse flips to `compile_reject` (at id:z0059: all escape gaps except the liveness ones `gap_37`, `gap_38`, `gap_39`, `gap_43`, `gap_44`; since id:z0060 also `gap_56`, since id:z0061 `gap_57` and `gap_58`, since id:z0062 `gap_59` to `gap_62`, since id:z0072 `gap_63`; re-check each), with its Known gaps entry and class bullet in `bench/safety_matrix/README.md` (and `doc/SAFETY.md` §6 if listed there) removed. Accept probes newly refused: none allowed without a task.
    - **Store grid:** re-record `bench/fuzz/store_grid_expected_failures.txt` and `store_grid_twin_rejections.txt` (and the modular pair) under the new default; list in the completion note every twin newly refused, by axis.
    - **Accepted refusal (id:z0075, 2026-11-06):** the 18 safe twins refused because an assignment to a local's field keeps the field's old origins (`{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{same_param,store_param_65}__{deref_out,field_out}__frame_ends`) stay refused: add a `KNOWN_ISSUES.md` §5 entry with the reduced program from id:z0091 (`future.tm.md`), the fix that would remove it, and how to rewrite: give the field its final value when the local is built (`let carrier_tup = (src_val, 10);` in place of `(&seed, 10)` then `carrier_tup.0 = src_val;`: no warning, checked on id:z0064's compiler). Any other twin newly refused here needs a task, per the rule above.
    - **Verification:** `make test`, `make preflight-changed` (the differential must show 0 newly accepted; list the newly refused programs), `sh scripts/check_store_grid.sh`, the self-hosting fixpoint. The fuzz record goes stale for `src/`. Stop for review.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **Depends changed (2026-11-17, a review of the task list, the maintainer's request):** removed id:z0011 and id:z0044, which the **Ordering note** above already says are not blockers (this task flips no liveness probe and checks no declaration; its place after them in the queue is unchanged, and the maintainer may still move it). Added id:w17jf and id:nc3ym: the store grid's safe twins that the new rules refuse and the default accepts today (2250 at git:98a1efc, 780 of them id:w17jf's, figures in id:nc3ym) are over-rejections this task requires to have their tasks done first. Added id:h1yk5, the check-in of id:z0066.
    - **When the rules become the default (2026-11-14):** flip the `main` probes the provenance rules close and the old rules do not: `gap_79` and `gap_80` (id:z0183), `gap_77` and `gap_78` (id:z0180), each with its Known gaps entry and `doc/SAFETY.md` §6 sentence, and check the class (K) and (F) probes `gap_59` to `gap_63`, which a by-value-aggregate fix in the old rules closed in part (id:z0183's **Tried** bullet).

    - **Measured by id:nc3ym (2026-11-17, compiler git:3e34cc3):** this task would newly refuse 890 safe store-grid twins, in three roots: R1, a field assignment keeping the field's old origins (id:z0091's class), 186 twins; R2, one tuple parameter carrying both the destination and a read-only `Static` value, 224 twins (id:z0086, 96 of them also id:4by24); R3, a call through a `fn` value, 480 twins (id:4by24). The **Accepted refusal** bullet above names 18 of R1's 186 cells. The other 168 are the same cause through other destinations and paths (`closure_capture_mut`, `closure_owned_capture`, `closure_call_mut` and the `fn_val` path). id:z0091 is in `future.tm.md`. Whether to widen the accepted bound to all 186 or to promote id:z0091 before this task is the maintainer's decision; id:nc3ym recommends promoting it (see there).

    - **Accepted refusal superseded (2026-11-17, the maintainer):** R1's refusals, the 18 above included, are fixed by id:z0091 (promoted, added to **Depends:**) and not accepted as a bound, so no `KNOWN_ISSUES.md` §5 entry is written for them.

    - **Baseline of the probes (2026-11-17, `provenance` at git:94c0ed2, `build/zoril --provenance -I stdlib=stdlib` on each `known_gap` probe of `bench/safety_matrix/probes/`):** 42 of the 49 are refused and 7 are accepted. The 7 are liveness gaps, and each has its task ahead of this one: `gap_37`, `gap_43` and `gap_87` (id:kqp9n), `gap_38`, `gap_39` and `gap_96` (id:z0044), and `gap_44` (id:z0011). So this task flips every escape probe still `known_gap`, the 42 refused here, `gap_64`, `gap_94` and `gap_95` among them (the old rules still accept those three). Re-run the loop on the tree as it is when this task starts, and quote both counts.
    - **Since id:4by24 and id:z0091 (2026-11-17, compiler git:5d0c6ea):** under `--provenance` the store grid refuses exactly the default record's 3932 twins (`sort -u` of `build/provenance/build/z91/grid/work/twin_rejections.txt` against `bench/fuzz/store_grid_twin_rejections.txt`: 0 either way) and accepts no unsafe cell, so id:nc3ym's 890 newly refused twins are gone. One more probe flips here: `gap_97` (git:ff009df), a frame view read through a local reference to a local struct and stored out, accepted by the default rules and refused under `--provenance`, so 43 of the 50 `known_gap` probes are refused.
    - **One more since id:z0073 (2026-11-18):** `gap_98` (git:43b8f17), a frame view in an aggregate passed by value to a callee that stores it out (`keep(out, Carrier { v: &x })` with `*out = c.v`; also a tuple, an array, a nested struct, a by-value `self`, the whole struct, and a raw pointer to the frame in place of the reference), accepted by the default rules and refused under `--provenance` (the call store rule), so 44 of the 51 `known_gap` probes are refused. Flip it here, with its Known gaps entry and class (O) in `doc/SAFETY.md` §6.

    - **Since id:f81f3's decision (2026-11-19):** gap_102 is refused under `--provenance` once id:77rr6 is done, and gap_103 is refused once id:716bm is done. Both stay `known_gap` in the default build until this task. Flip them here with the rest of **Baseline of the probes**, unless id:yp1er's item 4 already closed gap_103 in the default build. That ends the decision's departure from principles 1 and 7.
    - **Baseline updated after id:kqp9n and id:z0044 (2026-11-19, compiler git:28b628f):** id:kqp9n and id:z0044 flipped 24 `known_gap` probes in default mode (the 6 liveness probes `gap_37`, `gap_38`, `gap_39`, `gap_43`, `gap_87`, `gap_96` plus 18 arena-escape probes `gap_07`, `gap_11`, `gap_28`, `gap_29`, `gap_33`, `gap_40`–`gap_42`, `gap_45`, `gap_47`–`gap_55`). 28 `known_gap` probes remain: 26 are refused under `--provenance` (including `gap_44`), and 2 are accepted (`gap_102` and `gap_103`). Added id:fqf8x to **Depends:** to fix the six UAF bugs found in id:bfcvm/id:kqp9n/id:z0044 before flipping the default rules.
    - **Pre-flip baseline measured (2026-11-20, compiler `git:04be73c`, scratch in `build/z65/`):**
      - `known_gap` probes: **28 of 28** remaining `known_gap` probes are now refused under `--provenance` (0 accepted — `gap_102` and `gap_103` are now refused too).
      - `accept` probes newly refused under `--provenance` (3 — requires tasks/decisions per "Accept probes newly refused: none allowed without a task"): `419_extend_from_slice_stack_bytes_accepted.zrl` and `420_extend_from_slice_caller_arena_views_accepted.zrl` (both refused because `Vec::extend_from_slice` declares `#[stores(slice -> self)]`, which `os_call` treats as storing `slice`'s own address into `self`, even though `Clone` no longer has `#[borrows()]`), and `141_extern_call_unsafe.zrl` (undeclared `extern fn memcmp`, refused by Stage 2 `extern store rule`).
      - 5 roots under `--provenance=warn` (188 total): `tools/zilc` 0, `tools/zman` 0, `tools/zbuild` 2 (`util.zrl:127` `join_path`), `tools/ztest` 4 (`main.zrl:54,62` `cat2`/`item_path` — all 6 in zbuild/ztest are `String.push_str` -> `memcpy`'s `#[unsafe(stores(*src -> dest))]` on `u8` bytes), `src/main.zrl` 182 (6 frame warnings at `mono.zrl:296`, `expr.zrl:3373`, `driver/module.zrl:1422,1452,1477,1501`; 14 global warnings from `Driver::set_ice_context`; 162 `Unknown` call-store warnings propagating through the `lower_expr` mutual-recursion cycle).
      - Non-gap tests newly refused under `--provenance` (15, excluding the 3 `accept` probes above): 3 `tests/modular/iface_attrs/` provenance-rejection fixtures (`lib_narrow`, `prov_reject_narrowing`, `prov_reject_p65`); 5 undeclared-`extern` tests (`cb.zrl`, `qsort_callback.zrl`, `app.zrl`, `platform.zrl`, `test_runtime_memcmp.zrl`); and 7 other tests (`closure_type_inference.zrl`, `variant_several_args_drop_once.zrl`, `match_by_value_drops_once.zrl`, `match_skipped_parts_dropped.zrl`, `byval_vec_param.zrl`, `trait_names.zrl`, `test_empty_compile_and_tool_errors.zrl`).
    - **Completed (2026-11-20, git:1aba284, awaiting check-in review):**
      - Enabled `PROVENANCE_ON` by default in `src/main.zrl` and `src/driver/state.zrl` beside the legacy verifier (`Driver.had_provenance_error` kept separate from `had_error` so `verify_module` still runs until `id:z0012`); kept `--provenance` (accepted) and `--provenance=warn` (developer option) until `id:z0012`.
      - Marked `stdlib/file.zrl`'s `read_to_end_sized_raw<R: Read>` with `#[unsafe(borrows(arena))]` (with `// SAFETY:` comment) and regenerated `doc/man/zoril-file.3` so stdlib interface emission passes under default provenance.
      - Flipped all 28 remaining `known_gap` probes (`gap_13`, `gap_16`, `gap_18`, `gap_21`, `gap_23`, `gap_26`, `gap_27`, `gap_32`, `gap_36`, `gap_44`, `gap_56`–`gap_64`, `gap_78`–`gap_80`, `gap_94`, `gap_95`, `gap_97`, `gap_98`, `gap_102`, `gap_103`) to `compile_reject` (28 of 28 refused, 0 remaining), flipped `tests/language/memory/origins/byval_vec_param.zrl` (`gap_32`) to `expected compile fail`, and removed the closed Known gaps entries from `bench/safety_matrix/README.md` and `doc/SAFETY.md` §6 (leaving milestone counts untouched).
      - Re-recorded the whole-program and modular store grids: 0 failing unsafe cells (down from 14,577 whole-program and 125 modular), 0 soundness hole classes, and 0 newly refused safe twins (3,932 whole-program and 8 modular, unchanged).
      - **Verification:** `sh scripts/check_safety_model.sh` (`PASS: safety_model.md is self-consistent.`, `[PASS] Known gaps lists exactly the 0 known_gap probes`), `sh scripts/run_safety_matrix.sh` (`All probes complete: 533/533 passed. Mismatches: 0`), `sh scripts/check_store_grid.sh` (`[PASS] store-grid: all 0 expected failing cells match (34320 valid cells, 3932 over-rejected twins, 0 hole classes, 0 generator errors in 122s)`), `make test` (`Total: 4072 run, 4072 passed, 0 failed, 2 skipped (142.3s)`), `REJECT_DIFF_NO_CACHE=1 make preflight-changed` (`reject-diff: base verdicts: fresh (no cache); base front end 111 s`, `[PASS] reject-diff: 2 newly accepted (none that must be refused, or all allowed), 17237 newly refused, of 69173 programs against a484d11487430a4f709006c069b68454b476b98a` — both newly accepted are `bench/safety_matrix/probes/141_extern_call_unsafe.zrl` whole-program and zbuild `probe-accept`, because base `a484d11` does not parse `#[unsafe(stores())]`; `Total: 1533 run, 1533 passed, 0 failed, 0 skipped (106.0s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.5s)`). Fuzz record is stale for `src/` and `stdlib/`. Stopping for check-in review per `Check-in:`.

- [x] +safety +tests +AI-D @provenance id:z0074 B4b List every program the old rules refuse and the new rules accept, and read each
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Depends:** id:z0065, id:71a06
    > **Completed:** 2026-11-20 git:1aba284

    - **Found by:** the review of id:z0071.

    - **Why:** `leak_vec` (id:z0071) was refused by neither differential the series runs: the rejection differential compares two compilers in the default mode, and `build/rv/provdiff.sh` compares `--provenance` before and after a change over the existing probes. A reviewer found it by hand. id:z0012 deletes the old rules, so every program only they refuse is accepted after it; that list is not computed anywhere.
    - **Do:** run the new rules alone (a scratch compiler with the old rules' refusals off, as `check_reject_diff.sh` builds its base in a scratch worktree, or a developer flag if one is cheaper; say which) and the default compiler over the rejection differential's program set (69,122 at id:z0071, `tests/`, the safety probes, the store grid twins). List every program refused by the default and accepted by the new rules alone, and read each: a real escape gets a fix or a `known_gap` probe before id:z0012; a safe program is recorded as id:z0012's intended acceptance.
    - **Make it a gate** if it is cheap enough: id:z0012's completion note then lists the same set, empty of unsafe programs.
    - **Known members (from id:z0076, 2026-11-06):** `tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`, `heap_block_store_through_old_rule_refused.zrl` and `heap_block_into_global_old_rule_refused.zrl` are refused by the old region rule only: a frame address stored through a `#[fresh]` result or a heap block, the pointer then returned or put into a global. Their expected diagnostic names the old rule, so they fail when it goes; id:z0073 decides what replaces it.
    - **Correction (2026-11-17, a review of the task list):** id:z0073's decision (2026-11-14) passed these three programs (its case C) to the measurement id:71a06, which comes after this task in the queue. Until it is done they are members of this task's list, recorded as "decided by id:71a06", not read again here.
    - **Resolved by id:71a06 (2026-11-20, git:9a29f44):** case C is not kept and is documented as outside the provenance guarantee (`doc/spec/safety_model.md` §3.2, `doc/spec/unsafe_policy.md` §1); these three programs are intended acceptances when `id:z0012` deletes the old region rule.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **Measured and classified (2026-11-20, scratch compiler `build/z74/new/build/zoril` on `git:1aba284`):**
      - **Method:** built a scratch compiler (`build/z74/new/build/zoril`) with legacy ZIR frame-escape checks (`check_borrow_escapes_frame_depth`, `check_rvalue_escapes_frame` in `src/check_zir.zrl`), legacy ZIL region-escape and `#[borrows]` checks (`src/verify.zrl` lines 692, 1117, 1163, 1185, 1257, 1899, 2023), and `InterprocSummaryPass` enforcement (`src/main.zrl`) disabled, keeping provenance, borrow aliasing, move/drop, and L2 liveness active. Ran `REJECT_DIFF_NO_CACHE=1 sh scripts/check_reject_diff.sh --bins build/z74/base build/z74/new` over all 69,173 store-grid + safety-matrix programs (whole-program and modular `zbuild`), plus a parallel scan of all `tests/*.zrl` (`! -name '*_lib.zrl'`).
      - **Store grid (68,640 cells + twins):** **0** unsafe cells newly accepted; **3,912** safe twins newly accepted (3,402 `ref_{let,identity,phi}` from `id:z0045`; 438 `{struct_field,tuple_slot,array_slot}`; 72 `{direct,struct_scalar,call_method,call_local}`), leaving only 20 over-rejected twins in the 34,320-cell grid. All 3,912 are intended acceptances for `id:z0012`.
      - **Safety matrix probes (533 probes, whole-program + zbuild):** 2 `compile_reject` probes newly accepted (`398_carrier_from_call_stashed_in_global.zrl` and `402_carrier_ref_through_let_stashed_in_global.zrl`, whole-program and zbuild = 4 lines of `3916 accepted, 0 refused, of 69173 programs`, `reject-diff: base verdicts: fresh (no cache); base front end 114 s`). Both store `as *i32 as usize` into `static mut KEEP: usize` (the documented `id:z0071` integer-store boundary); changing `KEEP` to `*i32` causes the new-rules-alone compiler to refuse both (`call store rule`).
      - **`tests/` scan:** 10 programs newly accepted, **0** new soundness holes:
        1. 4 known safe intended acceptances for `id:z0012`: `read_through_ref.zrl`, `read_through_identity.zrl`, `read_through_phi.zrl` (`id:z0045`), and `box_byval_param_write.zrl`.
        2. 3 known `id:71a06` case-C intended acceptances for `id:z0012`: `fresh_store_through_old_rule_refused.zrl`, `heap_block_store_through_old_rule_refused.zrl`, `heap_block_into_global_old_rule_refused.zrl`.
        3. `tests/error_reporting/err_primitive_method_escape.zrl`: stores `self as *u64 as usize` into `static mut KEEP: usize` (same `id:z0071` integer-store boundary as `398`/`402`).
        4. `tests/interproc_summary/cross_module/global_stash_caller.zrl`: hand-written legacy `global_stash_lib.zri` with old `stash = 1` and no provenance `edge` fields.
        5. `tests/error_reporting/err_unsafe_borrows_visible_lie.zrl`: `#[unsafe(borrows(b))] fn pick(a: &T, b: &T) -> &i32 { return &a.v; }` — refused by `verify.zrl:692` today, not by `os_infer_ties`. Noted on `id:z0012` to preserve the visible-lie check (or add a `ParamAddr` visible-lie check to `os_infer_ties`) before deleting `verify.zrl:692`.
      - **Gate note:** `scripts/check_reject_diff.sh --bins` already provides this exact differential in ~3 minutes; no separate gate script is needed once `id:z0012` deletes the old rules.

- [x] +safety +tests +AI-D @provenance A `fn` item or closure that stores its own parameter into a global, made into a value, is refused by the new rules id:4f0ew
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Completed:** 2026-11-20 git:06e9e69

    - **Found by:** id:4by24, probing the sibling routes of a call through a `fn` value (compiler git:94c0ed2, and the same with id:4by24's change).
    - **Placed:** directly before id:z0012, which it blocks: once the old rules are deleted, both programs below compile and leave a dangling pointer in `G`.
    - **Now:** under `--provenance` the new rules accept both of these; only the old rules refuse them ("region escape: the function stores a reference into memory that outlives a call through a `fn` value"). A call through a `fn` value checks each argument against what the other arguments and the environment reach, never against a global (design note §3, _Calls through a `fn` value_), and the closure rule (id:z0096) applies only the edges whose value is what the environment reaches. An edge whose value is a declared parameter is checked nowhere.
      - `static mut G: *i32 = 0 as *i32; fn stash(r: &i32) { unsafe { G = r as *i32; } } fn apply(f: fn(&i32), r: &i32) { f(r); } fn bad() -> i32 { let x = 1; apply(stash, &x); return 0; } fn main() -> i32 { let _ = bad(); return unsafe { *G }; }` (a `fn` item; id:z0012's **From id:z0092** bullet names this half).
      - The same with `apply(|q: &i32| { unsafe { G = q as *i32; } }, &x);` in `bad` (a closure). The design note §3 _A closure made into a value_ said this one "is refused at `run`'s call"; no test showed it, and it is not (id:4by24 corrected the sentence).
      - A `fn` item bound to a local and called through it is refused, by its summary (`let f: fn(&i32) = stash; let g = f; g(&x);`: "the callee stores an address of this frame into a global (call store rule)").
    - **Do:** decide where a parameter-to-global (or parameter-to-another-parameter) edge of a body made into a value is checked: where the value is made (refuse the edge outright, as `check_fn_value` does), or at every call through a `fn` value (a global destination for every argument, which refuses every frame address handed to a `fn` parameter). Then implement it, with the two programs above as tests, and probe the siblings: an `unsafe fn` value, a method value (`S::get`), a generic instance, a closure in a struct field, a `fn` value returned by a call, and an `extern fn` (declared `#[unsafe(stores(p -> static))]` or undeclared) made into a Zoril `fn(...)` value via `unsafe { keep }` and passed to a `fn` parameter (found by id:g764h: accepted under `--provenance` because `os_is_c_fn_ptr` is false for `fn(...)`).
    - **Also:** the header comment of `os_check_closure_value` (`src/check_zir.zrl`) says the same wrong thing as the design note did ("An edge whose value is a declared parameter is checked where the argument is passed"); correct it with the fix.
    - **Checks:** C1 both programs refused under `--provenance` by a `provenance:` diagnostic, with a test each. C2 each sibling probed, refused where unsafe, with a test. C3 the rejection differential (it removes no refusal unless the decision does), `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed`.
    - **Checks recorded (2026-11-20, git:06e9e69):**
      - **Decision:** refuse parameter-to-global edges where the `fn` value is made (`os_check_fn_value`, `OS_RULE_FN_VALUE` on `ZirRvalue.FuncAddr`), while leaving parameter-to-parameter edges to `os_unknown_call` at call sites (refusing globals at call sites would reject every callback taking `&T`). Also refuse any undeclared address-taking `extern fn` (or declared `extern fn` with a `-> static` edge) made into a Zoril `fn` value (not `extern "C" fn`). Updated `os_check_closure_value`'s comment and `doc/design/provenance.md` §3. Updated `Driver::set_ice_context` (`src/driver/module.zrl`) to format into a process-lifetime static buffer (`ICE_NOTE_PTR`) so `driver_lower_fn_instance` carries no parameter-to-global edge when passed to `Monomorphizer::set_lowerer`.
      - C1: `fn_value_param_global_store_refused.zrl` and `closure_param_global_store_refused.zrl` both refused with `provenance: a function or closure that stores a parameter into a global cannot be made into a fn value (fn value rule)`.
      - C2: all 7 siblings probed and tested under `tests/language/memory/provenance/`: `fn_value_unsafe_fn_param_global_store_refused.zrl`, `fn_value_method_param_global_store_refused.zrl`, `fn_value_generic_param_global_store_refused.zrl`, `fn_value_closure_in_struct_param_global_store_refused.zrl`, `fn_value_returned_param_global_store_refused.zrl`, `fn_value_extern_declared_global_store_refused.zrl`, `fn_value_extern_undeclared_refused.zrl`, plus positive twin `fn_value_extern_declared_empty_accepted.zrl` (`Total: 11 run, 11 passed, 0 failed, 0 skipped (0.1s)`).
      - C3: `make test` passed (`Total: 4092 run, 4092 passed, 0 failed, 2 skipped (142.2s)`); `REJECT_DIFF_NO_CACHE=1 make preflight-changed` passed (`reject-diff: base verdicts: fresh (no cache); base front end 112 s`, `[PASS] reject-diff: 2 newly accepted (none that must be refused, or all allowed), 17237 newly refused, of 69173 programs against a484d11487430a4f709006c069b68454b476b98a` — the same 2 `141_extern_call_unsafe.zrl` `probe-accept` entries; `Total: 1543 run, 1543 passed, 0 failed, 0 skipped (109.2s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.7s)`). Fuzz record is stale for `src/`.

- [x] +safety +tests +AI-D @provenance id:z0012 B4 Make `--provenance` the default, delete the old classifiers, and fix what the measurement found
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0011, id:z0044, id:z0065, id:z0063, id:z0073, id:z0074, id:z0075, id:z0096, id:71a06, id:4f0ew
    > **Check-in:** stop for review after it. **Split here** if the tree needs more than a session of changes.
    > **Completed:** 2026-11-20 git:0edf99f

    - **Depends changed (2026-11-14, the maintainer, by id:z0073's decision):** added id:71a06, which decides case C before the old region rule is deleted.
    - **Split (2026-11-05, from id:z0049's review):** turning the rules on by default beside the old ones is id:z0065 (it only refuses more); this task is now the half that accepts more: delete the old rules and `src/summary_pass.zrl`, with the rejection differential, and the docs and twin lists. The fixes of the measurement are id:z0060 to id:z0063, and the `unsafe fn` exemption item moved to id:z0063, which narrowed it to `Raw`.

    - **Do:** make the new rules the default and remove `--provenance`; resolve every warn-mode rejection recorded in id:z0049 and id:z0011 (a real escape: fix the code; a common over-rejection: apply the decided fix; a leak through a by-value collection parameter: change the code); then delete `local_storage_external`, `local_is_external_target`, `rvalue_is_external_target`, `place_outlives_frame`, `rvalue_storage_external`, `storage_walk_zir`'s mask logic, `note_call_stores_zir`, the depth limits, `is_collection_type_name`, the same-parameter filters, and `src/summary_pass.zrl` (keeping `src/verify.zrl`'s stack-address check as an add-only second net).
    - **Flip probes and twin lists (including id:z0045's):** flip all closed `known_gap` probes (`gap_07`, `gap_11`, `gap_13`, `gap_16`, `gap_18`, `gap_21`, `gap_23`, `gap_26`, `gap_27`, `gap_28`, `gap_29`, `gap_32`, `gap_33`, `gap_36`, `gap_40`, `gap_41`, `gap_42`, `gap_44`, `gap_45`, `gap_47`, `gap_48`, `gap_49`, `gap_50`, `gap_51`, `gap_52`, `gap_53`, `gap_54`, `gap_55`) to `compile_reject` and remove their Known gaps entries in `bench/safety_matrix/README.md` and class entries in `bench/safety_matrix/README.md` / `doc/SAFETY.md` §6. Fold in id:z0045: remove the 3402 `ref_{let,identity,phi}` twins (and any id:z0017 twins newly accepted when `summary_pass.zrl` is retired) from `bench/fuzz/store_grid_twin_rejections.txt`, flip `read_through_{ref,identity,phi}.zrl` from `expected compile fail` to running tests, add an `accept` probe for `id:z0045` and a regression test returning `s.as_slice()` from `String.with_capacity(a, cap)` (`a: &Arena`). Because retiring `summary_pass.zrl` and `local_storage_external` accepts more safe programs, run `scripts/check_reject_diff.sh <base>` and list every newly accepted program class in the completion note (none may be unsafe). Update `doc/SAFETY.md` §2.3 and §5–§6, `doc/spec/surface_syntax.md` (`#[borrows]`/`#[stores]`), `README.md`, `KNOWN_ISSUES.md` and `bench/fuzz/store_grid_expected_failures.txt`.
    - **End criterion of the series (the maintainer, 2026-11-06, at id:z0075):** zero unsafe programs accepted is the hard requirement (the grid, the safety probes, the rejection differential). Zero safe programs refused is not reachable by any checker that accepts no unsafe one; the target is that no remaining refusal is common in user code (the tests as its stand-in), each is a documented class in `KNOWN_ISSUES.md` §5 with a reason and a rewrite (id:z0017 audits them), and its diagnostic says what was found (id:z0066).
    - **Done when:** every unsafe store-grid cell (whole-program and modular) is rejected, no `known_gap` probe of this family remains, the self-hosting fixpoint holds, and `make test` and `make preflight` pass. Stop for review, then close id:z0045 (citing this commit on `main`) and start id:z0017 and id:z0013 (and renew the fuzz record per id:z0003).
    - **From id:z0092 (2026-11-06):** the old rules refuse making a `fn` item that stores into a global or another parameter into a value (`check_fn_value` in `src/verify.zrl`); the new rules have no counterpart, since a call through a `fn` value records no store into a global (design note §3, _Calls through a `fn` value_). Carry it over before deleting the old rules: id:z0096 is the closure half of the same route. **Depends also:** id:z0096.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

    - **Flip list (2026-11-17, a review of the queue):** the probe list under **Flip probes and twin lists** dates from before the split. id:z0065 now flips every escape probe that the new rules refuse (its **Baseline of the probes**), and the liveness tasks ahead of it flip their own. So this task flips only what is still `known_gap` once the old rules are deleted. A probe the old rules alone refused, and that is accepted afterwards, is a hole: id:z0074 lists those, and this task needs that list empty of unsafe programs.
    - **From id:71a06 (2026-11-20, git:9a29f44):** when deleting the old region rule here, flip the three case-C tests (`fresh_store_through_old_rule_refused.zrl`, `heap_block_store_through_old_rule_refused.zrl`, `heap_block_into_global_old_rule_refused.zrl`) to accept tests (`expected exit 0`) for the documented `unsafe` raw-heap-pointer boundary.
    - **From id:z0074 (2026-11-20):** when deleting the old rules here: (1) preserve the visible direct-parameter lie check for `#[unsafe(borrows(..))]` (`err_unsafe_borrows_visible_lie.zrl`); (2) update `398_carrier_from_call_stashed_in_global.zrl`, `402_carrier_ref_through_let_stashed_in_global.zrl`, and `err_primitive_method_escape.zrl` to store `*i32`/`*u64` rather than `usize` (the `id:z0071` integer-store boundary); (3) update `global_stash_lib.zri` to include provenance `edge` fields (or retire the legacy `stash = 1` fixture); (4) expect 3,912 safe store-grid twins newly accepted (leaving 20).
    - **Completed (2026-11-20, git:0edf99f):**
      - Deleted `src/summary_pass.zrl`, the legacy ZIR frame-escape classifiers in `src/check_zir.zrl` (`local_storage_external`, `rvalue_storage_external`, `place_storage_external`, `is_buffer_external_call`, `is_buffer_anchored_call`, `is_unsafe_call`, `check_borrow_escapes_frame*`, `os_local_storage_external`, `rvalue_is_external_target`, `local_is_external_target`, `place_carries_borrow`, `place_outlives_frame`, `check_rvalue_escapes_frame`), and the legacy ZIL checks in `src/verify.zrl` (`check_borrows_claim`, `check_fn_value`, `check_call_stores_stack`, store-escape errors; kept `verify.zrl`'s direct stack-return check as an add-only second net). Removed `--provenance` and `--provenance=warn` from `zoril`, `zbuild`, man pages (`doc/man/{zoril,zbuild}.1{,.scd}`), specs, and tests (stripped `// flags: --provenance` from 182 tests). Preserved `#[unsafe(borrows(..))]` visible-lie checking in `os_infer_ties` and conservative refusal for summary-less imported calls in `os_call`.
      - Updated probes `398` and `402` and `err_primitive_method_stash_helper.zrl` (`*i32`/`*u64`), updated `global_stash_lib.zri` to provenance `edge` format, flipped `read_through_{ref,identity,phi}.zrl`, `box_byval_param_write.zrl`, and the 3 `id:71a06` case-C tests to `expected exit 0`, added probe `429_read_through_ref_let_carrier_accepted.zrl` (`id:z0045` accept probe) and `tests/language/memory/provenance/string_with_capacity_arena_slice_accepted.zrl`, updated `doc/SAFETY.md`, `KNOWN_ISSUES.md`, `doc/spec/surface_syntax.md`, `doc/spec/modular_compilation.md`.
      - Retired obsolete `verify.zrl` mutations (`M4`, `M11`, `M24`, `M27`–`M30`, `M81`), retargeted Canary `C5` to `.zri` provenance edge loading (`src/driver/module.zrl`), updated `c26_fn_value_store_stack` in `scripts/fuzz/gen.lua` to a cross-frame `fn`-value stack escape (`fn_store_call(&mut hh, fn_store_put)`), and removed `bench/fuzz/store_grid_modular_prov_*`.
      - **Verification:**
        - `make test`: `Total: 4096 run, 4096 passed, 0 failed, 2 skipped (142.5s)`.
        - `REJECT_DIFF_NO_CACHE=1 make preflight-changed`: passed (`All mutations caught.`, `PASS — a clean copy of the tree builds with the default rules, and the compiler reproduces itself.`, `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)` [26/26 rows in `fuzz_calibrate.sh`], `reject-diff: base verdicts: fresh (no cache); base front end 111 s`, `[PASS] reject-diff: 3874 newly accepted (none that must be refused, or all allowed), 17237 newly refused, of 69174 programs against a484d11487430a4f709006c069b68454b476b98a`, `--checked` `Total: 1544 run, 1544 passed, 0 failed, 0 skipped (110.8s)`, `git` scenarios `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.5s)`).
        - Newly accepted classes (3,874 total, 0 unsafe): 3,870 safe store-grid twins freed from `bench/fuzz/store_grid_twin_rejections.txt` (3,402 `ref_{let,identity,phi}` from `id:z0045` plus 468 safe carrier/struct/tuple/array twins) + 2 `141_extern_call_unsafe.zrl` `probe-accept` entries + 2 safe test flips (`read_through_*` / `box_byval_param_write` / case-C `unsafe` raw-heap-pointer boundary per `id:71a06`).
        - `sh scripts/check_store_grid.sh`: `[PASS] store-grid-modular: all 0 expected failing cells match (318 two-module cells, 0 over-rejected twins, 0 generator errors)` and `[PASS] store-grid: all 0 expected failing cells match (34320 valid cells, 62 over-rejected twins, 0 hole classes, 0 generator errors in 172s)`.
        - `sh scripts/check_safety_model.sh`: `PASS: safety_model.md is self-consistent.` (`79 rows — 78 proven, 0 GAP (1 N/A)`, 0 `known_gap` probes).
        - Fuzz record is stale for `src/` (to be renewed after `id:z0012` per `id:z0003` / `id:7h57z`). Note: `make preflight` (full slow gate) not yet run; stopping here for the required check-in review. `id:z0045` remains open to close citing this commit on `main`.

- [x] +safety +AI-D @provenance Callee store into outer struct via inner-block local reference escapes scope (`release_only` skipped on non-`Drop` locals) id:nhk9n
    > **Created:** 2026-11-20
    > **Branch:** `provenance`
    > **Completed:** 2026-11-20 git:883c834

    - **Found by:** id:z0012 (2026-11-20), while probing inner-block variants of `c26_fn_value_store_stack`. Pre-existing since `id:kqp9n` (`git:dd6c6d8`).
    - **Placed:** directly after id:z0012, as a follow-up soundness hole found while finishing it.
    - **Reproducer (100% checked code, compiles and exits 92 under `--checked` reading poisoned stack memory):**
      `struct FnStoreH { p: &i32 } fn fn_store_put(h: &mut FnStoreH, p: &i32) { h.p = p; } fn main() -> i32 { let hx: i32 = 7; let mut hh = FnStoreH { p: &hx }; { let hn: i32 = 9; fn_store_put(&mut hh, &hn); } if *hh.p != 9 { return 92; } return 0; }` (also reproduces when `fn_store_put` is called through a `fn(&mut FnStoreH, &i32)` value).
    - **Root cause:** `give_arg_borrows_to_target` (`src/check_zir.zrl`) records the callee's store as a `release_only: true` borrow on `hh`, and `check_local_scope_end` (`src/check_zir.zrl:3298`) checks `((!b.release_only && !b.derived) || self.local_type_has_drop(local_id, locals))`, skipping `release_only` borrows when `hn: i32` has no `Drop` impl even though `hn`'s stack slot is released at block end. Naively dropping `!b.release_only` from line 3298 rejects slice locals passed by value (`tools/zbuild/src/manifest.zrl:106`, `src/mono.zrl:871`) because `give_arg_borrows_to_target`'s fallback records `derived: false` even for `[T]`/`&T` arguments whose backing storage is not the local's own stack slot.
    - **Do:** distinguish borrows of a local's own stack slot (`&hn` passed as a reference argument) from borrows of a slice/reference local's backing target in `give_arg_borrows_to_target` (or `check_local_scope_end`), reject both the direct-call and `fn`-value inner-block reproducers, add safety probes, and run `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed`.
    - **Done (`git:883c834` on `stream/provenance`):**
      - `src/check_zir.zrl`: in `check_scope_end_borrowed`, check `(!b.derived && (!b.release_only || b.borrower != OUTSIDE_BORROWER)) || self.local_type_has_drop(local_id, locals)` so frame-local borrowers (`hh`) are never exempted by `release_only` (while `OUTSIDE_BORROWER` on non-`Drop` locals stays covered by the provenance escape rules). In `give_arg_borrows_to_target`, distinguish `from_addr` (`ParamAddr`) from `from_contents` (`ParamContents`), track `direct_inner` through `by_ref` slice arguments (`StructLiteral(ILTYPE_SLICE)` / `Cast` to slice / `inherit_reborrow`), treat slice indexing (`Projection.Index` on `ILTYPE_SLICE`/pointer) as non-local in `borrowed_storage_is_local`, and use converged `os_ret_addr` in `inherit_rv_borrows` when `os_known` is true.
      - `src/driver/module.zrl`: defer `ZirVerifier` for recursive-cycle members to `verify_pending` after `os_fixpoint` converges so cycle calls see final `os_edges`/`ret_ties` instead of falling back to `apply_unknown_store_borrows`.
      - `scripts/mutation-check.sh`: updated `M77` and `M104` patterns for inlined `inherit_reborrow`.
      - Added 5 safety probes (`bench/safety_matrix/probes/430_callee_store_inner_block_ref_outlives_scope.zrl` through `434_callee_store_outer_ref_via_inner_carrier_accepted.zrl`): direct call, `fn` value, `by_ref` slice of inner array, double-ref `&&i32` deref, and accepted outer-ref twin via inner carrier. Also probed sibling routes (unknown `fn` param, closure capturing `&mut hh`, inner closure capturing `&hn`, `&[i32]` deref, `extend_from_slice` of inner-array slices, `RefHolder` by ref and by value, struct field `&s.a`, array element `&arr[0]`, mutual recursion, plus `195_nested_slice_array_escape.zrl` and `420_extend_from_slice_caller_arena_views_accepted.zrl`).
      - `make test`: `Total: 4106 run, 4106 passed, 0 failed, 2 skipped (143.0s)`.
      - `REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=HEAD~1`: clean-tree 4-gen selfhost fixpoint `PASS`, `All mutations caught.`, `fuzz-calibrate` `PASS`, `reject-diff: base verdicts: fresh (no cache); base front end 114 s`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 8 newly refused, of 69179 programs against 0edf99f147fc3a2e28bf5abc4955de5f35f16a1a` (probes 430–433 × whole-program + zbuild), checked suite `Total: 1544 run, 1544 passed, 0 failed, 0 skipped (111.0s)`, git scenarios `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.7s)`, benchmarks within tolerance, `Figures @ 2026-11-20 (883c834): 539 probes, 52424 compiler lines, 4.59%/10.93% density`.
      - Fuzz record (`bench/fuzz/README.md`) is stale for `src/` (already stale for the provenance series, to be renewed under `id:a85sp` / `id:z0003`).

- [x] +audit +safety +AI-G @provenance id:z0045 A reference to a local carrier passed through a `let`, an identity call or a phi is refused
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0012
    > **Completed:** 2026-11-20 git:0edf99f

    - **Depends note:** (do not edit `src/summary_pass.zrl` before id:z0012 retires it; close with id:z0012). Over-rejection, not a hole; related to id:z0017.

    - **Now:** a safe program that hands a callee a reference to a local struct, and stores what the callee returns, is accepted when the reference is written in the call (`take_ref(&c)`) and refused when it first goes through a `let`, an identity function or an `if`. The callee returns the view the struct holds (`c.v`), not a pointer into the struct; the checker reads the result as a pointer into the caller's stack frame. Error: "region escape: returning a pointer to local stack storage via sret".
    - **In the grid:** all 3402 safe twins of the `ref_let`, `ref_identity` and `ref_phi` carriers (1134 each; id:z0041) are refused, and every twin of `ref_direct` is accepted. They are in `bench/fuzz/store_grid_twin_rejections.txt`: `grep -E '__ref_(let|identity|phi)__' bench/fuzz/store_grid_twin_rejections.txt`.
    - **Reproducer** (checked on the compiler of this commit, and the compiler before id:z0007 refuses it too, so it is not caused by that change). With `let r = &c;` and `take_ref(r)` in `f`, it is refused; with `take_ref(&c)` and no `let`, it is accepted, builds with `scripts/build_zrl.sh`, and exits 0:

    ```zoril
    struct Carrier { v: [i32] }
    fn take_ref(c: &Carrier) -> [i32] { return c.v; }

    fn f(out: &mut [i32], view: [i32]) {
        let c = Carrier { v: view };
        let r = &c;
        *out = take_ref(r);
    }

    fn main() -> i32 {
        let data = [42, 0];
        let mut dest: [i32] = @slice(0 as *i32, 0);
        f(&mut dest, &data);
        return dest[0] - 42;
    }
    ```

    - **Same refusal, other forms:** `take_ref(id_ref(&c))` with `fn id_ref(c: &Carrier) -> &Carrier { return c; }`, and `let r = if pick() > 0 { &a } else { &b }; take_ref(r)` with two carriers `a` and `b` and `fn pick() -> i32 { return 1; }`.
    - **Do:** find where a reference that passed through a `let`, a call or a join stops being read as "the reference to `c`" and becomes "a pointer into `c`'s storage", so that the callee's result is tied to the whole frame. Fix it so `take_ref` is tied to what `c.v` points at, not to `c`. This makes the checker accept more, so run the rejection differential (`scripts/check_reject_diff.sh <base>`) and list every program the base rejects and the change accepts; none of the store grid's unsafe cells may become accepted. Move the three carriers' twins out of the twin record in the same commit, and add one of the forms above as an `accept` probe.
    - **Checks:** (this task makes a checker accept more and closes with id:z0012, so its review is `+AI-D`, as for every `+safety` check-in.)
      - C1: the three forms above (`let`, identity call, `if` join), each built with `scripts/build_zrl.sh` and run: exit 0; quote each.
      - C2: `grep -cE '__ref_(let|identity|phi)__' bench/fuzz/store_grid_twin_rejections.txt` is 0 after the change (3402 before); quote both.
      - C3: `sh scripts/check_store_grid.sh`: no unsafe cell accepted; quote its summary.
      - C4: the rejection differential (`scripts/check_reject_diff.sh <base>`): every program the base rejects and the change accepts, listed in the completion note with its reason; none unsafe.
      - C5: the `accept` probe under `bench/safety_matrix/probes/`, and `sh scripts/run_safety_matrix.sh` passing; quote its summary.
      - C6: `make test` and `make preflight-changed`, each `Total:` line quoted, citing id:z0012's commit on `main`.
    - **Finding (2026-11-03):** id:z0047's read-through rule (`os_through_plus` on reference arguments) already gives `got O={Param(1)} S={}` on all three forms (`tests/language/memory/origins/read_through_{ref,identity,phi}.zrl`), `src/verify.zrl` accepts them with zero errors, and the sole refusal (`src/summary_pass.zrl:716`, "region escape: returning a pointer to local stack storage via sret") comes from `InterprocSummaryPass`, which id:z0012 retires and deletes. Do not change `src/summary_pass.zrl` beforehand; close this task with id:z0012 once the 3402 twins leave `bench/fuzz/store_grid_twin_rejections.txt`, the `accept` probe is added, and the rejection differential is recorded, citing id:z0012's commit on `main`.
    - **Done (`git:0edf99f` on `stream/provenance`, verified on tip `git:883c834`; awaiting merge to `main`):**
      - C1 (`scripts/build_zrl.sh` + run in `build/provenance` on `883c834`): `read_through_ref exit=0`, `read_through_identity exit=0`, `read_through_phi exit=0`.
      - C2 (`grep -cE '__ref_(let|identity|phi)__' bench/fuzz/store_grid_twin_rejections.txt`): `3402` before (`06e9e69`) -> `0` after (`883c834` / `0edf99f`).
      - C3 (`sh scripts/check_store_grid.sh` on `883c834`): `[PASS] store-grid-modular: all 0 expected failing cells match (318 two-module cells, 0 over-rejected twins, 0 generator errors)` and `[PASS] store-grid: all 0 expected failing cells match (34320 valid cells, 62 over-rejected twins, 0 hole classes, 0 generator errors in 119s)`.
      - C4 (`reject-diff` from `id:z0012` `0edf99f` vs `a484d11` + `id:nhk9n` `883c834` vs `0edf99f`): `[PASS] reject-diff: 3874 newly accepted (none that must be refused, or all allowed), 17237 newly refused, of 69174 programs against a484d11487430a4f709006c069b68454b476b98a` (3,870 safe store-grid twins including the 3,402 `ref_{let,identity,phi}` twins from `id:z0045` + 468 safe carrier/struct/tuple/array twins, 2 `141_extern_call_unsafe.zrl` `probe-accept` entries, 2 safe test flips for `read_through_*` / `box_byval_param_write` / `id:71a06` case-C raw-heap-pointer boundary; 0 unsafe), followed by `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 8 newly refused, of 69179 programs against 0edf99f147fc3a2e28bf5abc4955de5f35f16a1a`.
      - C5 (`bench/safety_matrix/probes/429_read_through_ref_let_carrier_accepted.zrl` + `sh scripts/run_safety_matrix.sh` on `883c834`): `All probes complete: 539/539 passed. Mismatches: 0`.
      - C6 (citing `id:z0012` `git:0edf99f` and `id:nhk9n` `git:883c834` on `stream/provenance`, no code edits since `883c834`): `make test`: `Total: 4106 run, 4106 passed, 0 failed, 2 skipped (143.0s)` (`0edf99f`: `Total: 4096 run, 4096 passed, 0 failed, 2 skipped (142.5s)`); `REJECT_DIFF_NO_CACHE=1 make preflight-changed`: `Total: 1544 run, 1544 passed, 0 failed, 0 skipped (111.0s)` (checked suite) and `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.5s)` (`git` scenarios).
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [x] +audit +AI-D @provenance id:z0017 A3.5 Twelve safe store-grid twins are rejected
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0012
    > **Completed:** 2026-11-20 git:357e908

    - **Depends note:** (do not debug `src/summary_pass.zrl` before id:z0012 deletes it). Over-rejection audit, not a hole.

    - **Cells (before id:z0012):** `{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{closure,param_65}__call_struct_mut__frame_ends` (12 cells) plus 96 cells exposed by id:z0008 in `bench/fuzz/store_grid_twin_rejections.txt`, rejected today by `src/summary_pass.zrl` ("region escape: storing local stack pointer into caller memory"). Also note the sibling found in id:z0047's review: passing a local struct `RefHolder { r: &c }` by value to `take_holder(h)` retains `Frame(c)` (`os_reach_all`).
    - **Over-rejection from id:z0007 (found in its review, 2026-11-03):** liveness borrows are tracked per local, not per field, so `w.s = v.as_slice(); let x = w.s[0]; a.reset(); return x - 42 + w.t - 3;` is refused at `a.reset()` because `w` stays live for `w.t`.
    - **Do (after id:z0012):** inspect every twin still listed in `bench/fuzz/store_grid_twin_rejections.txt` once `summary_pass.zrl` is gone (`param_65` twins should be accepted via the overflow bit; `closure`/`fn`-value twins: Decision 3 is decided (id:z0088), so any still refused after id:z0092 to id:z0094 is a finding, not a bound by design). Fix any unintended over-rejection without reopening any probe, add an `accept` probe for any fixed class, and document any deliberate precision bound (such as field-insensitive borrows) in `KNOWN_ISSUES.md` §5. `make test`, `make preflight-changed`, the rejection differential.
    - **Done when (2026-11-06, the series' end criterion, recorded on id:z0012):** every safe twin still in `bench/fuzz/store_grid_twin_rejections.txt` (and the modular list) is in a class `KNOWN_ISSUES.md` §5 names, with its reason and a rewrite, and none is common in the tests. `closure`/`fn`-value twins follow id:z0088's decision, not the note above.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **Audit & completion (2026-11-20, git:357e908 on `stream/provenance`):**
      - Audited all 62 twins in `bench/fuzz/store_grid_twin_rejections.txt` (and 0 in `store_grid_modular_twin_rejections.txt`): every original `param_65`/`closure`/`fn_val` `call_struct_mut` twin was already accepted after `id:z0012`. The 62 remaining fell into exactly two classes:
        1. **20 `{elem_ref,ref_local}__enum_payload__*__return_val__frame_ends` twins** (including `closure`, `fn_val`, `param_65`): `scripts/fuzz/store_grid.lua` emitted `Option.None => { let dummy_err = 0; return &dummy_err; }`, returning a genuine stack reference in the dead `None` arm (which also masked the `Some` escape in the 20 unsafe cells). Fixed `store_grid.lua` to emit `static DUMMY_ERR: i32 = 0;` and `return &DUMMY_ERR;`; all 20 unsafe cells stay rejected and all 20 safe twins are now accepted.
        2. **42 `{elem_ref,ref_local}__{array_slot,struct_field,tuple_slot}__{direct,helper,method,mutual_rec,self_method,trait_method,two_level_helper}__return_val__frame_ends` twins**: ZIR provenance accepts the strong update (`id:z0091`), and only `src/verify.zrl`'s flow-insensitive add-only stack-return second net (`region escape: returning a pointer to local stack storage`) refuses them because the aggregate is seeded with `&seed` before being overwritten with `ref_param`. Documented as a deliberate precision bound in `KNOWN_ISSUES.md` §5 with rewrite (initialize the aggregate directly with `src_val`).
      - Checked the two named siblings: `RefHolder { r: &c }` passed by value to `take_holder(h)` already compiles and is accepted; per-local (field-insensitive) liveness borrows (`w.s = v.as_slice(); let x = w.s[0]; a.reset(); return x - 42 + w.t - 3;`) are still refused at `a.reset()` and are documented as a deliberate precision bound in `KNOWN_ISSUES.md` §5 with rewrite. Removed the two stale pre-provenance bullets from `KNOWN_ISSUES.md` §5.
      - Verification: `sh scripts/check_store_grid.sh`: `[PASS] store-grid-modular: all 0 expected failing cells match (318 two-module cells, 0 over-rejected twins, 0 generator errors)` and `[PASS] store-grid: all 0 expected failing cells match (34320 valid cells, 42 over-rejected twins, 0 hole classes, 0 generator errors in 119s)`. `make test-changed BASE=HEAD`: `Total: 152 run, 152 passed, 0 failed, 0 skipped (15.4s)` (no compiled code in `src/`, `stdlib/`, or `tools/` changed; `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed` covered by `id:nhk9n` on `git:883c834`).

- [x] +safety +docs +AI-D @provenance Close the provenance series: the design note as built, the fuzz record renewed, and the series end criterion checked id:a85sp
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Depends:** id:z0012, id:z0045, id:z0017
    > **Completed:** 2026-11-20 git:992e4da

    - **Placed:** directly after id:z0017, the last open task of the series. It was found in a review of the queue against `doc/design/provenance.md` (the maintainer's request, 2026-11-17): no open task brought the design note up to date with what was built, or started the fuzz renewal that id:z0003 decided would follow id:z0012.
    - **Why:** the design note says it is "the design that the hardening series implements". Its §4 still marks most rows open (`gap_11`, `gap_40` to `gap_42`, `gap_47`, `gap_48` and others), and its §5 lists what the model "will newly reject (to measure, not assumed)". §6 describes the flag that id:z0012 removes, and lists only the tasks up to id:z0012, not the precision, liveness and closure tasks that were added later. id:z0012 updates `doc/SAFETY.md`, `doc/spec/surface_syntax.md`, `README.md` and `KNOWN_ISSUES.md`, but not this note. The fuzz record has been stale for `src/` since early in the series. id:z0003 (confirmed by the maintainer on 2026-11-03) renews it once, after id:z0012, and id:z0013's generator debt is to be run in the same session.
    - **Do:**
      1. Bring `doc/design/provenance.md` up to date with the rules as built. In §4, give each row the probe that closed it and say whether it is closed. In §5, replace each "to measure" item with the figure that was measured, the task that measured it, and what was decided. In §6, describe the landing as it happened (the flag gone, the old classifiers deleted, the ZIL check kept add-only) and list every task of the series. §1 and §2 stay as history, marked "before the series".
      2. Check the series' end criterion (id:z0012, 2026-11-06). The grid accepts 0 unsafe cells, whole-program and modular; no `known_gap` probe of the escape or liveness families remains; and every safe twin still refused is in a class that `KNOWN_ISSUES.md` §5 names. Where one of these fails, add a task (placed by the AGENTS.md rule) rather than fixing it here.
      3. List each route class added in the series and whether `scripts/fuzz/gen.lua` covers it (id:z0013's **Generator debt**). Add a task for each missing generator feature, placed before the renewal.
      4. The fuzz renewal is the maintainer's: a session takes the machine for hours (id:z0003). Ask the maintainer to start it, and record the request here.
    - **Checks:** C1 every §4 row names its closing probe or its open task, and `rg -n '\(open\)' doc/design/provenance.md` prints only rows with an open task. C2 `sh scripts/check_store_grid.sh` summary quoted, with 0 unsafe accepted. C3 `rg -l 'expected: known_gap' bench/safety_matrix/probes` lists no escape or liveness probe, quoted. C4 the route-class list with its generator coverage, and the tasks it added. C5 `make test-changed`, its `Total:` line quoted. C6 `tm validate --strict doc/tasks/*.tm.md` prints no warning.
    - **Checks recorded (2026-11-20, git:992e4da on `stream/provenance`):**
      - **C1:** updated `doc/design/provenance.md` (§1–§2 marked "before the series", §3 updated to default provenance, §4 every row closed with closing tasks/probes including `gap_49`–`gap_65`, `gap_77`–`gap_80`, `gap_94`–`gap_103`, `425`–`433`, §5 replaced with measured figures and decisions, §6 updated with the landing and full task list). `grep -n '(open)' doc/design/provenance.md`: `(0 matches)`.
      - **C2:** `sh scripts/check_store_grid.sh` (from `id:z0017` `git:357e908`, unchanged code): `[PASS] store-grid-modular: all 0 expected failing cells match (318 two-module cells, 0 over-rejected twins, 0 generator errors)` and `[PASS] store-grid: all 0 expected failing cells match (34320 valid cells, 42 over-rejected twins, 0 hole classes, 0 generator errors in 119s)`. All 42 remaining twins belong to the single `verify.zrl` flow-insensitive stack-return class documented in `KNOWN_ISSUES.md` §5. Series end criterion satisfied.
      - **C3:** `grep -l 'expected: known_gap' bench/safety_matrix/probes/*.zrl`: `(0 matches)` (0 `known_gap` probes remain in the entire repository).
      - **C4 (route-class generator coverage in `scripts/fuzz/gen.lua`):**
        - Covered (partial): `match` binding through a reference to a local enum (`gap_57`, `gap_58` — `match-binding-through-reference` / `match-borrowed-enum-payload`).
        - Outside `gen.lua`'s safe-subset scope (require `unsafe`/`extern`, pinned by safety probes and `tests/language/memory/provenance/`): closure/`fn`-value global stores (`gap_64`, `id:4f0ew`), `unsafe fn`/`extern fn` as `fn` values (`gap_65`, `gap_67`), loose raw pointer / `extern` hidden stores (`gap_94`, `gap_95`, `gap_102`, `gap_103`).
        - Missing safe-subset features — added 3 tasks before `id:z0013` in `doc/tasks/future.tm.md`: `id:mskex` (indirect closure `&Holder`/`&&Holder` `gap_47`/`gap_48`, closure passed to `fn` callee / forwarding view `gap_52`/`gap_55`, mutual recursion `gap_28`/`gap_54`), `id:4ngz8` (release-tier liveness through `&mut`/`Box`/callee `put`+`kill` `gap_37`–`gap_39`/`gap_43`/`gap_87`/`gap_96`/`425`–`428`, inner-block callee store `430`–`433`, `&self` elision returning other param `gap_44`/`gap_99`–`gap_101`), and `id:r1shp` (`extend_from_slice`/`.clone()` `gap_56`/`gap_77`/`gap_78`/`gap_80`, container-of-views pushed/moved `gap_59`–`gap_63`/`gap_79`, local-ref-to-struct & by-value aggregate `gap_97`/`gap_98`).
      - **C5:** `make test-changed BASE=HEAD`: `Total: 4106 run, 4106 passed, 0 failed, 2 skipped (142.8s)`.
      - **C6:** `tm validate --strict doc/tasks/*.tm.md` passed with 0 warnings.
      - **Fuzz renewal request (item 4):** requested the maintainer to schedule the post-provenance fuzz renewal run (`make fuzz-release`, per `id:z0003`) once `stream/provenance` merges to `main` (and after `id:mskex`, `id:4ngz8`, `id:r1shp` if desired in the same session).

- [ ] +safety +precision +AI-G @provenance H2 `#[unsafe(borrows(*self))]` declares a result tied only to what the referent holds; the interface carries it; Vec and String clones use it id:42ae2
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:bfd1z

    - **Promoted (provenance, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, next to id:mqh84 and id:22qty, before the history squash (id:6d5wy): H2 and H3 change `src/` and `stdlib/` on the `provenance` branch, so they land before it is cleaned up and merged. The maintainer approved resuming them for the next release (2026-11-20), which also approves the new `pub` `Vec.empty_like` that the **Stop and report first** bullet waits for; the design note's "Ties through a reference to an owner" paragraph and `KNOWN_ISSUES.md` §5 (the `v.clone()` and `Vec<T>::resize` bound) are updated when H3 lands.
    - **Placed:** after id:bfd1z, whose `ret_held` it sets by declaration; id:2sdmk's decision (4).
    - **Moved (2026-11-18, the maintainer's decision):** from directly after id:bfd1z to directly after id:z0044, with H3 and the check-in id:22qty. H3 cannot land before id:z0044 and id:kqp9n (P9 of id:2sdmk), and a trusted form and summary bit added before id:z0011 and id:z0012 are more for those to check and carry over. H2 stays tied to H3, so it moves with it. If id:bfd1z's count is small, the three move to `future.tm.md` instead.
    - **Stop and report first:** `Vec.empty_like` is a new `pub` stdlib method and `Clone for Vec<T>`'s body changes; both wait for the maintainer's approval of id:2sdmk.
    - **Scope:** the parser accepts `*self` (and `*p` for a reference parameter `p`) only inside `#[unsafe(borrows(..))]`, setting the parameter's `ret_held` bit as well as its `ret_ties` bit; the interface writers keep the form and write a `ret_held` `#[summary]` key; `scripts/check_safety_comments.sh` requires a `// SAFETY:` line above it as for the other `#[unsafe(..)]`; `doc/spec/surface_syntax.md` and `doc/spec/unsafe_policy.md` name it. Stdlib: `Vec.empty_like` with the declaration, `Clone for Vec<T>` rewritten on it with no `unsafe`, `Clone for String` with the declaration.
    - **Checks:** C1: `tests/error_reporting/` tests: `*self` in a plain `#[borrows(..)]` refused, `*x` for a by-value parameter refused. C2: `--emit-origins` on `build/2sdmk/shapes.zrl` shows a held bit for `cl` (`Vec<[u8]>`) and none for `Vec<S>.clone` (P2). C3: `tests/modular/iface_attrs/` case: the `.zri` of a module with the declaration has `ret_held`, and an importer reads it (the key removed from the `.zri` by hand: the importer's held bit is gone). C4: `make test`, `make preflight-changed`, rejection differential with no newly accepted program (the borrow checker does not read `ret_held` until H3).

    - **Deferred (2026-11-18, by the maintainer's decision recorded in id:2sdmk):** id:bfd1z counted 5 held sites among the 84 of `src/` and `tools/`, which is small, so H2, H3 and id:22qty move to `future.tm.md`, to resume after id:z0012.
    - **Start from id:bfd1z's patch:** the word and `ILFunction.os_ret_held` this task sets by declaration were not committed. Apply id:bfd1z's **Patch: the word** first, re-run its C1 to C4, and write the design note paragraph and the `unsafe` obligation that id:bfd1z's scope named. Also read its Findings A to C.

- [ ] +safety +precision +AI-G @provenance H3 A call tied to an argument only through what its referent holds borrows what the referent holds, not the referent, so probe 307 is accepted id:mqh84
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:42ae2, id:z0044, id:kqp9n

    - **Promoted (provenance, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, after id:42ae2, which it depends on (its blockers id:z0044 and id:kqp9n are complete).
    - **Placed:** after id:42ae2; id:2sdmk's decision (2), and id:2sdmk's checks C1 to C3.
    - **Moved (2026-11-18, the maintainer's decision):** with id:42ae2, to after id:z0044; its blockers id:z0044 and id:kqp9n are now before it (see id:42ae2).
    - **Scope:** `inherit_rv_borrows`'s `Call` arm reads the callee's `ret_held`, as decision (2) says; P1 to P8 of id:2sdmk become tests (`tests/language/memory/` or probes) with their expected verdicts; probe 307 flipped to `accept`.
    - **Checks:** C1: probe 307 `accept`; gap_77, P1, P2, P3, P5, P6, P8 and P9 refused, each as a test. C2: with the copy of the referent's borrows taken out (the direct borrow dropped, nothing copied), P3 and P5 are accepted (the check sees the defect); restored, refused. C3: P7: `sh scripts/run_safety_matrix.sh` with 0 mismatches, and the `safety-matrix-zbuild` and `zbuild-diff` gates pass. C4: `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, every newly accepted program listed with its reason.
    - **Ends with a check-in:** the `@checkin` task after it reviews H2 and H3.

    - **Deferred (2026-11-18, by the maintainer's decision recorded in id:2sdmk):** id:bfd1z counted 5 held sites among the 84 of `src/` and `tools/`, which is small, so H2, H3 and id:22qty move to `future.tm.md`, to resume after id:z0012.
    - **Check to add:** id:bfd1z's Finding B, P9's class inside one body, beside P9.
    - **From id:sjqmy (2026-11-20, git:04be73c):** when this task lands, also have `os_call`'s tie arm read `ret_held` (using `os_through_split` into `O`, dropping `S` of the pointee) so P1–P4 (`return v.clone()` of local `Vec`/`String`, and `Vec<Vec<[u8]>>::resize`) are accepted alongside probe 307, and remove the `KNOWN_ISSUES.md` §5 bound.

- [ ] +safety +AI-D @provenance @checkin Check-in: review H2 and H3 (the trusted held declaration, and the caller rule that frees probe 307) id:22qty
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:42ae2, id:mqh84

    - **Promoted (provenance, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, after id:mqh84, the batch it reviews, before the history squash (id:6d5wy).
    - **Placed:** directly after id:mqh84, the batch it reviews (H2, H3; H1 is `+AI-D` and closes itself).
    - **Moved (2026-11-18, the maintainer's decision):** with id:42ae2 and id:mqh84, to stay directly after the batch it reviews.
    - **Review:** re-run H3's C1 to C3 and P1 to P8 of id:2sdmk; probe the sibling routes: a held tie through a trait call resolved per instance, a `Box` receiver, a field receiver (`s.v.clone()`), a `match` binding receiver, and an import whose `.zri` has no `ret_held` key.

    - **Deferred (2026-11-18, by the maintainer's decision recorded in id:2sdmk):** id:bfd1z counted 5 held sites among the 84 of `src/` and `tools/`, which is small, so H2, H3 and id:22qty move to `future.tm.md`, to resume after id:z0012.

- [ ] +git +AI-D @provenance Clean up and squash the commit history in the provenance worktree before merging to main id:6d5wy
    > **Created:** 2026-11-20
    > **Branch:** `provenance`
    > **Depends:** id:a85sp, id:22qty

    - **Placed:** after id:a85sp and the H2/H3 batch with its check-in id:22qty (the maintainer's request, 2026-11-20), before merging `stream/provenance` into `main` (id:w3vde).
    - **Do:** review the 107 commits on `stream/provenance` (`build/provenance`, `main..HEAD`) and squash multi-commit task sequences, fixups, and per-file micro-commits into clean, concise logical commits following `AGENTS.md`'s "Code branches" rules:
      - Combine several commits of one task (e.g., per-file `#[borrows(..)]` check-in/tightening runs, fixups to the preceding commit, or probe+fix pairs where no later task's notes need them apart) into one commit whose body preserves every `Task:` line.
      - Keep commits of distinct tasks separate where a later task's notes rely on telling them apart, and keep a local backup branch pointing at the old tip (`992e4da`) until the merge to `main` is published.
      - Verify tree identity (`git rev-parse <new>^{tree}` equals `git rev-parse <old>^{tree}`).
      - Update every rewritten SHA cited in `doc/tasks/*.tm.md` in a single task commit listing the old -> new SHA pairs.
    - **Checks:** C1 `git -C build/provenance rev-parse HEAD^{tree}` equals the pre-squash tip's tree SHA (`992e4da^{tree}`), quoted. C2 `git -C build/provenance log --oneline main..HEAD` commit count before and after, quoted. C3 old tip preserved on a local backup branch. C4 every rewritten SHA in `doc/tasks/*.tm.md` updated and `tm validate --strict doc/tasks/*.tm.md` prints no warning.

- [ ] +merge +safety +AI-D @provenance Merge the provenance branch into main id:w3vde
    > **Created:** 2026-11-20
    > **Branch:** `provenance`
    > **Depends:** id:6d5wy

    - **Placed:** directly after id:6d5wy (the maintainer's request, 2026-11-20), landing the completed provenance series on `main`.
    - **Do:** merge the cleaned-up provenance branch into `main` (maintainer's decision), resolving any conflicts in recorded figures (`corpus/zrl_whole_program_zil.sha256`, `bench/fuzz/*`, safety figures) by recomputing them from the merged tree (`UPDATE_GOLDEN=1` in `scripts/test_incremental.sh`), never by taking a side. Update `id:z0045` if needed to cite the commit on `main`. Push `bench/records` if preflight appends rows.
    - **Checks:** C1 `git log -n 5 --oneline main` shows the merge commit on `main`. C2 `make test` on `main`, `Total:` line quoted. C3 `REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=<main before the merge>` on `main`, quoting each `Total:` line and the `reject-diff: base verdicts: fresh (no cache)` line. C4 `sh scripts/check_store_grid.sh` summary quoted (0 unsafe cells accepted).

- [ ] +generics +types +AI-G @main id:z0032 G1 `impl<T: Copy> Source<T> for S` fails to bind `T` when it appears only in the trait's arguments
    > **Created:** 2026-11-03
    > **Context:** Rejected in both build modes.
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, first of the `main` `+AI-G` group that follows the merge of `provenance` (id:w3vde); order inside the group is not critical.
    - **Reproducer:** `trait Source<T> { fn pull(self: &Self, fallback: T) -> T; } struct S { x: i32 } impl<T: Copy> Source<T> for S { fn pull(self: &S, fallback: T) -> T { return fallback; } } fn main() -> i32 { let s = S { x: 1 }; return s.pull(42) - 42; }` gives `type mismatch: expected &S, found bool`.
    - **Cause:** `impl_scope` (`src/mono.zrl`) binds an `impl`'s type parameters only by matching its target type. **Direction:** unify the trait's type arguments to bind the rest, mangle the bound arguments into the method name, and reject a parameter that appears in neither at the `impl` header.

- [ ] +types +diagnostics +AI-G @main A call with turbofish checks the number of type arguments id:7sb2k
    > **Created:** 2026-11-14
    > **Context:** found by id:z0100's probes.
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, in the `main` `+AI-G` group after id:w3vde; order inside the group is not critical.
    - **Placed:** in `future.tm.md`: a diagnostic gap, not a soundness hole; no task depends on it.

    - **Found:** a call ignores a wrong number of type arguments: `id::<i32, i32>(3)` with `fn id<T>(x: T) -> T` and `g::<i32>(3)` with a non-generic `g` both compile and run (exit 0 for `return id::<i32, i32>(3) - 3;`), and `id::<>(3)` infers `T`. The value form refuses each since git:dc006a0 (`a generic function named as a value needs one type argument for each of its type parameters`, `type arguments given to a function that is not generic`). `direct_callee` in `src/lower_zir/expr.zrl` passes `type_args` to `instantiate_function` without comparing the count with `ff.type_params.len`; a method call (`instantiate_method`) is the twin to probe.
    - **Do:** refuse a count that is not zero and not the declaration's (zero still infers), and type arguments on a non-generic function, at the call as the value form does; an error test per form; `make test`, `make preflight-changed` (the differential lists the newly refused programs).

- [ ] +modular +AI-G @main Two modules that each define a private const of the same name fail to assemble: the const's symbol is not qualified by its module id:5342d
    > **Created:** 2026-11-14
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, in the `main` `+AI-G` group after id:w3vde; order inside the group is not critical.
    - **Placed:** in `future.tm.md`: found by check-in id:9y3ke; a build failure on a correct program, not a soundness hole.

    - **Found (2026-11-14, `main` at git:b26ca47):** modules `ma.zrl` with `const LIM: i32 = 1;` and `mb.zrl` with `const LIM: i32 = 2;`, each read by a `pub fn`, imported by one `main`: `build/zoril` emits both as the symbol `z3LIME`, and the assembler fails with ``Error: symbol `z3LIME' is already defined`` (`build/z135/priv/const/`). Functions are qualified by their module (`z6stdlib3mem5Arena4dropE`); a const is not. The program is correct and should build.
    - **Do:** qualify a const's symbol by its module, as a function's is, in whole-program and separate compilation (the `.zri` names the symbol the importer references). Probe a `pub const` read from another module, a `static`, and a const of the same name in a module and in the program's root.
    - **Checks:** C1 the program above builds and exits 0, whole-program and through `zbuild` (a test under `tests/modular/`). C2 take the change out and watch C1 fail to assemble. C3 `make test` and `make preflight-changed`, each `Total:` quoted.

- [ ] +stdlib +tests +AI-G @main id:z0182 `Vec.resize` shrinking and `Vec.clear` drop the elements they remove
    > **Created:** 2026-11-11
    > **Context:** by id:z0174.
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, in the `main` `+AI-G` group after id:w3vde; order inside the group is not critical.
    - **Now:** `resize(new_len, value)` with `new_len < len`, and `clear()`, only set `len`: the removed elements are never dropped. A leak, not a memory hole (nothing reads them again), but it breaks "drop exactly once" for a `T` with a `Drop`, as `truncate`/`clear` do in Rust.
    - **Do:** drop each removed element, last first, before setting `len`; probe a `Drop` counter through both, and an arena-backed `Vec` (whose `free` is a no-op).
    - **Checks:** C1 a run-time test counting one drop per removed element for both; C2 take the drop out and watch it count 0; C3 `make test`, its `Total:` quoted.

- [ ] +tests +AI-G @main An or-pattern whose alternatives bind different names is refused with a clear diagnostic id:vdgj4
    > **Created:** 2026-11-14
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, in the `main` `+AI-G` group after id:w3vde; order inside the group is not critical.
    - **Placed:** in `future.tm.md` by the check-in id:vvtam: a spec rule not enforced and a poor diagnostic, not a hole (a binding missing from the alternative that matched is caught as `use of uninitialized variable` when it is read).

    - **Found (2026-11-14, id:vvtam):** `doc/spec/surface_syntax.md` §"OR Patterns" says every alternative must bind the same set of names. `match x { I.A(n) | I.B(m) => { return 1; } }` (`enum I { A(i32), B(i32) }`) is accepted. `match x { O.A(s, _) | O.D => {}, _ => {} }` (`S: Drop`) is refused only as `use of uninitialized variable 'a temporary'`, at line 1 column 1 of the enclosing function, and `I.A(n) | I.B => { return n; }` is refused as `use of uninitialized variable 'n'`. The compiler at git:c161107 behaves the same.
    - **Do:** in `Pattern.Or` (`src/lower_zir/lower_match.zrl`), collect the names each alternative binds (the per-alternative symbol set `bind_pattern_name` defines). If one alternative's set differs from the first's, report `a binding in an or-pattern must appear in every alternative: '<name>' is missing from one` at the pattern's span, next to the existing `a binding in an or-pattern must have the same type in every alternative` check.
    - **Checks:**
      - C1: `tests/error_reporting/err_or_pattern_binding_missing.zrl` (`// expected compile fail`, `// EXPECT: a binding in an or-pattern must appear in every alternative`) passes under `./scripts/test.sh`. It holds the three programs above, one per function, and the direct `build/zoril --emit-zil` output shows the new error once for each.
      - C2: with the new check commented out, C1 fails (`I.A(n) | I.B(m)` compiles).
      - C3: `REJECT_DIFF_NO_CACHE=1 make preflight-changed` exits 0. Quote the `fresh (no cache)` line and list every newly refused program with its reason; any test in `tests/` that is newly refused is a finding to report, not one to rewrite.
      - C4: full `make test` passes; quote the `Total:` line.

- [ ] +diagnostics +AI-G @main id:z0015 `zoril` stops after a bounded number of errors, and says when a file does not look like Zoril source
    > **Created:** 2026-11-03
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, last of the `main` `+AI-G` group after id:w3vde; it touches `src/diag.zrl`, which stage1 compiles, so use only what the pinned stage1 accepts.
    - **Now:** 300 KB of random bytes named `junk.zrl` gives about 139,000 error lines (12 MB); 160 KB of prose about 33,000. `zbuild` passes the same output through. Reproduce: `head -c 300000 /dev/urandom > junk.zrl; ./build/zoril -I stdlib=stdlib --emit-zil -o o.zil junk.zrl 2>&1 | wc -l`.
    - **Do:** count errors in `diag_start` (`src/diag.zrl`); past the limit (default 20) print one line naming `--error-limit N` (0 removes the limit) and exit 1. `zbuild --error-limit N` passes it to every `zoril -c`; both man pages and `--help` say so. Before lexing, refuse a NUL byte or invalid UTF-8 with one line; if the limit is reached before the first declaration, the stopping line says the file does not look like Zoril source. `src/diag.zrl` is in stage1's closure: use only what stage1 accepts (a `static mut` counter).
    - **Checks:**
      - C1: before the change, the reproducer in **Now**: the line count, quoted. And no existing error test expects more than 20 errors: `grep -c 'EXPECT:'` per file under `tests/`, the largest count quoted (if one is over 20, stop and report: the default changes).
      - C2: a program with 25 type errors: 20 error lines, then the stopping line naming `--error-limit N`, exit 1; with `--error-limit 0`, all 25; with `--error-limit 3`, 3; quote each count.
      - C3: a NUL byte, invalid UTF-8, and 160 KB of prose: one line each, the prose one saying the file does not look like Zoril source; the reproducer from **Now** prints at most 21 lines; quote each.
      - C4: the same through `zbuild --error-limit N` in `scripts/test_zbuild_errors.sh`, passing.
      - C5: `zoril --help`, `zbuild --help` and both man pages name `--error-limit` (`make man`, `sh scripts/test_man_pages.sh`).
      - C6: `rm build/zoril && make` (stage1 builds `src/diag.zrl`) and `make`, no warning.
      - C7: take the counter's check out (a scratch edit) and watch C2 fail; restore.
      - C8: the `KNOWN_ISSUES.md` entry removed or updated; `make test` and `make preflight-changed`, each `Total:` line quoted; the fuzz record is stale for `src/`.

- [ ] +types +diagnostics +AI-D @main A pattern that moves several values out of a tuple or struct is accepted id:ts1jg
    > **Created:** 2026-11-14
    > **Context:** found by id:z0176's sibling probes.
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, first of the `main` `+AI-D` group after the `+AI-G` group; order inside the group is not critical. Re-probe against id:z0176's arm-scope change first.
    - **Placed:** in `future.tm.md`: a false refusal (the safe side), no task depends on it; after id:z0176's fix, whose arm-scope change it should be re-probed against.

    - **Found (`main` at git:8d4670b, `S: Drop`):** each is refused with `use of moved value`, though it moves each value once: `let (s, k) = t;` with `t: (S, i32)`, `let W { s: s, k: k } = w;` with `struct W { s: S, k: i32 }`, `match w { W { s: s, k: k } => .. }`, and `T.A((s, k))` for `enum T { A((S, i32)), B }` (`use of moved value 'the value of the expression at ..'`). Binding the aggregate whole (`T.A(t)`, `F.A(w)`) is accepted.
    - **Do:** find which move the checker sees twice (the destructured place, then a field of it), and accept a pattern whose bindings move disjoint parts; the rejection differential lists every newly accepted program, each read for a second owner.

- [ ] +tests +AI-D @main A by-value pattern that binds a part needing a drop beside any other part is refused with `use of moved value` id:2bx4a
    > **Created:** 2026-11-14
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, in the `main` `+AI-D` group; order inside the group is not critical.
    - **Placed:** in `future.tm.md` by the check-in id:vvtam: a correct program refused, not a hole, and it predates that batch (stage1 refuses it too).

    - **Found (2026-11-14, id:vvtam, scratch `build/vvtam/p/`):** with `struct S { p: *mut u8 }` and `impl Drop for S`, each of these is refused, at the second binding, with `use of moved value 'w'` (or `'the value of the expression at L:C'` for a temporary scrutinee): `let w = (mk(fp), 1); let (x, z) = w;` (the second part is an `i32`), `let w = (mk(fp), mk(fp)); let (x, z) = w;`, `match w { (x, z) => {} }`, `match e { P.A(x, z) => {}, P.B => {} }`, `let W2 { a: x, b: z } = w;`, `let W2 { a: x, b: z } = W2 { .. };`. Binding one part and skipping the others (`let (x, _) = w;`, `P.A(s, _)`) is accepted and drops each value once (`tests/language/match/match_skipped_parts_dropped.zrl`). Without a `Drop` type in the aggregate (`(T, T)`, `T` a plain struct) it is accepted. `build/zoril` at git:7877894, the compiler at git:c161107 and `build/zoril-stage1` all refuse it, and no test in `tests/` binds two parts of an aggregate that needs a drop.
    - **Lead:** the first by-value binding seems to mark the scrutinee moved before the next sub-pattern reads its part. Compare `bind_pattern_name` (`src/lower_zir/lower_match.zrl`) with the borrow checker's view of `Let(x, Use(w.0))` followed by a read of `w.1`.
    - **Do:** diagnose (`+AI-D`: the cause is unknown), then settle the fix in this task's text and re-tag it `+AI-G` if it is mechanical. The fix must keep `match_skipped_parts_dropped.zrl` and `match_by_value_drops_once.zrl` passing and add the six programs above as drop-count cases (each part dropped once). It makes the checker accept more, so the rejection differential applies.

- [ ] +docs +tests +AI-D @main The safety pages' probe and hole counts are checked against the tree id:594de
    > **Created:** 2026-11-14
    > **Context:** found while closing id:z0100.
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, in the `main` `+AI-D` group; order inside the group is not critical. Its counts matter right after id:z0065 and id:z0012 closed every `known_gap` probe.
    - **Placed:** in `future.tm.md`: documentation drift with no safety effect; no task depends on it.

    - **Found:** `scripts/check_safety_figures.sh` checks `doc/SAFETY.md` §5.3 and the density rows of `doc/spec/unsafe_policy.md`, but not the probe counts in `doc/SAFETY.md` §5 ("**366 `compile_reject`**, ... **46 `known_gap`**") and §6 ("tracked as 46 `known_gap` probes"), nor the open-hole count in `doc/spec/safety_model.md` ("the 18 holes still open"), nor `doc/STABILITY.md`'s "16 open soundness holes", "72 safety properties" and "79-row architecture matrix". At git:891b76e `gap_80` made 47 `known_gap` probes while both `doc/SAFETY.md` lines said 46; `doc/STABILITY.md`'s 16 and `safety_model.md`'s 19 (now 18) already disagree.
    - **Do:** decide which of these counts each page should state at all (a page can link to the table instead of repeating a number); recompute the ones kept from the probes' `// expected:` lines and the Known gaps table in `check_safety_figures.sh`, and fail on a mismatch; a planted wrong count shows the check fails.

- [ ] +diagnosis +AI-D @main Two stage0c gates race on `build/zoril-c` in `make test` (`mv: cannot stat build/zoril-c.tmp`) id:nf1fv
    > **Created:** 2026-11-13
    > **Context:** found while doing id:z0136, which it did not cause.
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, last of the `main` `+AI-D` group, before the `@zil` series. Retagged `@main`: the race is in `make test`'s stage0c gates, which a release's tarball check runs, not in the `testinfra` series.
    - **Placed:** future file, under Evidence and tooling: not blocking, and not a one-session fix until the cause is known.

    - **Seen:** `./scripts/test.sh --gates` failed `stage0c-corpus` (and once `stage0c-error-locations`) with `exited 2 without reporting a failing item`, in two of five runs on one host. `build/gates/stage0c-corpus.log` ends `mv: cannot stat 'build/zoril-c.tmp': No such file or directory` and `make: *** [Makefile:122: build/zoril-c] Error 1`. Both gates run `make -C bootstrap/stage0-c test_*` at once, and both can decide `build/zoril-c` needs rebuilding.
    - **Next:** read `bootstrap/stage0-c/Makefile` around line 122 and find whether the rule writes `build/zoril-c.tmp` under one name for every make; a rebuilt-once step before the gates start (or a per-process temporary name) would end it. The stage0 compiler is frozen except for a blocking bug, but the freeze covers the compiler, not its Makefile; ask the maintainer if a change there is needed.

- [ ] +zil +decision +AI-D @zil ZL1 Settle the slice form of string_const and the slice_ptr opcode, and check what the pinned stage1 feeds zilc id:m6vm3
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)

    - **Placed:** after the provenance series (`id:z0017`), before ZL2 to ZL6. Nothing in `testinfra` depends on it. ZL4 changes the per-file runner, which `testinfra` rewrites (id:z0139).

    - **Depends changed (2026-11-17, a review of the task list, the maintainer's request):** removed id:z0017. It stated the order (this series after the provenance series), which the task's position states already; nothing in ZL1 to ZL6 needs a provenance task's result, and the series is on a branch of its own off `main`. `tm next` still offers the provenance tasks first; `tm next @zil` now offers this task, so a second session can take the series while the provenance series runs, if the maintainer wants that. To hold it back instead, restore the line.
    - **Why:** `string_const` is to give a `Slice<u8, 'local>` everywhere, as the spec says (id:1kaye, decision 1). Hand-written ZIL then needs `slice_ptr` to get the data pointer back.
    - **Decide, and write into ZL2 to ZL5 as their **Do:** and numbered **Checks:**:** (a) What a slice-typed `string_const` lowers to in zilc's QBE output: a static `{ptr, len}` pair beside the bytes, whose address is the value, or another layout. It must match how the front end's slice slots are laid out (pointer at offset 0, `usize` length at 8, today's `v5` slot in `--emit-zil`). (b) How the front end uses it: copy the pair into the slot, or use the value directly. (c) `slice_ptr`'s syntax, typing and spec entry beside `slice_len` (`doc/spec/intermediate_language.md` §5), and whether the front end's cast-and-load idiom is replaced by it. (d) What the pinned stage1 feeds to which zilc: does any path pass ZIL written by `bootstrap/stage1/` to the new `build/zilc`, `zilc-boot` included? If one does, the new zilc must also accept the old form until a re-pin, which is the maintainer's. (e) Which recorded figures change (`corpus/zrl_whole_program_zil.sha256`, the safety figures) and how each is recomputed.
    - **Also place:** the statement, decided in id:ahd1c, that ZIL is not checked for memory safety (`doc/spec/intermediate_language.md` and `doc/spec/safety_model.md`: the claims cover programs compiled from Zoril source, and zilc catches the common mistakes listed by ZL6). Put it into one of ZL2 to ZL5, or into a task of its own.
    - **Checks:** C1: each of (a) to (e) answered here, with the command that showed it for (d). C2: ZL2 to ZL5 each have a **Do:** and numbered **Checks:**, with a take-out check.

- [ ] +zil +AI-G @zil ZL2 string_const gives a Slice in the front end and in zilc, read back with slice_ptr id:qpc8d
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:m6vm3

    - **Placed:** after ZL1, which settles it.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope: the front end emits the slice form, zilc lowers it, the type check and `src/verify.zrl` type it, `slice_ptr` is added, the spec matches, and `corpus/zil/15_io_syscall.zil` and `19_fd_io.zil` are rewritten to print exactly their strings.

- [ ] +zil +AI-G @zil ZL3 One spelling for cast: zilc refuses bitcast and the corpus is rewritten id:htrqb
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:qpc8d

    - **Placed:** after ZL2: the corpus files it rewrites are the ones ZL2 changes.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope: `tools/zilc/src/zil_parse.zrl` refuses `bitcast` with a diagnostic that names `cast`, and the six corpus files that use it (`02_comparison`, `12_enums_sum`, `13_slices`, `15_io_syscall`, `19_fd_io`, `24_tuples`) use `cast`. The spec's line 92 stays true.

- [ ] +zil +tests +AI-G @zil ZL4 Corpus and per-file tests check the program's output, not only its exit code id:ehh6m
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:htrqb

    - **Placed:** after ZL3.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope (decision 3): a per-file test can state its expected output (a header directive or a sibling file, chosen in ZL1, read by the one header reader, `tr_expectations`, or by its replacement in `ztest`). Every `corpus/zil/` program and every corpus program that prints states its output. A check plants the 4 KB over-read of id:1kaye and shows that the test fails.

- [ ] +zil +safety +AI-G @zil ZL5 zilc runs the ZIL verifier that the compiler runs id:egsdq
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil` (new, off `main`; created when ZL1 starts)
    > **Depends:** id:ehh6m

    - **Placed:** after ZL4, last in the series. A check-in follows it, added by ZL1 with the series' other check-ins.

    - **Not ready:** ZL1 writes this task's **Do:** and **Checks:**. Scope (decision 4, the small step): zilc runs `src/verify.zrl` on what it parses, as the compiler does after lowering, so hand-written ZIL gets the same ZIL-level checks (stack-address escape, constant arena allocations) that compiled programs get. Not a borrow checker; that question is id:ahd1c.

- [ ] +zil +safety +audit +AI-D @zil ZL6 Which common mistakes in hand-written ZIL zilc can catch from what ZIL says id:0mbg3
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decision in id:ahd1c (`future.tm.md`)
    > **Branch:** `zil`
    > **Depends:** id:egsdq

    - **Placed:** after ZL5, which gives zilc the ZIL verifier this task extends.

    - **Why:** ZIL is not checked for memory safety, but zilc should catch the mistakes that are easy to see in ZIL as designed and that happen most often (the maintainer, id:ahd1c).
    - **Do:** list candidate checks, each with a three-line ZIL program that shows the mistake, and say for each whether ZIL as written carries what the check needs. Candidates to start from: a value used after a `move` or `drop` in the same function, a `drop` twice, a `slice_load`/`slice_store` with no dominating `bounds_check` (spec §6.3), the address of an `alloc 'local` returned or stored into a global, a `slice_len` or `slice_ptr` on a value that is not a slice, a `syscall` with an argument count its stub does not take, and a block with no terminator. Corpus mistakes count as evidence of what is common: id:1kaye's string over-read is one. Rank them by how often they would fire and how simple they are, and split each chosen check into an `+AI-G` task with its own numbered **Checks:** and a take-out.
    - **Checks:** C1: every candidate has its program and its answer here, with the zilc output today (`timeout -k 5s 30s build/zilc <file>`). C2: the chosen checks are tasks, placed after this one, with a check-in after them.

- [ ] +tools +AI-G @main id:z0014 `zilc` refuses text it does not recognise between declarations, and a file that is not ZIL
    > **Created:** 2026-11-03
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, after id:0mbg3 (the `@zil` series), not before: ZL2 and ZL3 edit `tools/zilc/src/zil_parse.zrl` and the `corpus/zil/` files this task's checks run on, and a later edit of the same parser avoids a conflict.
    - **Now:** `zilc` exits 0 with no message on random bytes, and on `printf '\x01\x02 zz garbage\n'` it writes a stray global parsed out of the word `garbage`. `ZilParser.parse_module` (`tools/zilc/src/zil_parse.zrl`) dispatches on a declaration's first byte and skips any other byte, so text between declarations is dropped silently.
    - **Do:** at top level, after trivia, accept only the declaration forms of `doc/spec/intermediate_language.md` and report anything else as `zilc: line N: expected a declaration, found '<token>'` with exit 1; before parsing, refuse a NUL byte or invalid UTF-8 with one line. Keep the first-error behaviour.
    - **Checks:**
      - C1: before the change, `printf '\x01\x02 zz garbage\n' > build/z14/g.zil; timeout 10 build/zilc build/z14/g.zil -o build/z14/g.ssa; echo $?` and the `.ssa` it writes; quote both (exit 0 and a stray global today).
      - C2: one `tests/zilc/` case per refusal: a stray word between two functions, control bytes, a NUL byte, invalid UTF-8; each fails before the change (run the new tests against the old `build/zilc` and quote) and passes after.
      - C3: each refusal's message is the one in **Do** (`zilc: line N: expected a declaration, found '<token>'`, or the one-line NUL/UTF-8 refusal), with exit 1; quote each.
      - C4: every file in `corpus/zil/` still compiles and gives its expected exit (`./scripts/test.sh corpus/zil` or the scenario that runs them); quote its `Total:` line.
      - C5: take the top-level check out (a scratch edit) and watch the stray-word case pass silently again; restore.
      - C6: the `KNOWN_ISSUES.md` entry removed or updated; `make test` and `make preflight-changed`, each `Total:` line quoted; the completion note says the fuzz record is stale for `tools/zilc/`.

- [ ] +tools +AI-G @main id:z0016 `zbuild` builds a program written in ZIL, and refuses any other input with one line
    > **Created:** 2026-11-03
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, after id:z0014, in the `+AI-G` group before the fuzz renewal; it builds `.zil` files through the slice form ZL2 settles.
    - **Now:** `zbuild 01_arithmetic.zil` (from `corpus/zil/`) parses the ZIL as Zoril and prints about thirty `expected declaration` errors; the manual pipeline (`zilc`, `qbe`, `as`, `ld` with the runtime) works and exits 30.
    - **Do:** a root ending in `.zil` skips the module graph and the front end and runs `zilc`, `qbe`, `as` and the link with `zbuild`'s usual linker and runtime choice, honouring `-o` and the cache directory; `--checked` with a `.zil` root is refused with one line. A root ending in neither `.zrl` nor `.zil` is refused with one line naming both. Update `doc/man/zbuild.1.scd` (`make man`), `zbuild --help`, and "Starting from ZIL" in `doc/getting_started.md`.
    - **Checks:**
      - C1: before the change, `build/zbuild corpus/zil/01_arithmetic.zil -o build/z16/a; echo $?` and the first three error lines, quoted.
      - C2: after, the same builds and `build/z16/a; echo $?` prints 30; every file in `corpus/zil/` gives its expected exit code (a loop in a new scenario, or in `scripts/test_user_paths.sh` with the installed `zbuild`); quote the loop's summary.
      - C3: `-o` and the cache directory are honoured: the binary lands at the `-o` path, and a second build of the same `.zil` reuses the cache (the scenario checks the cache directory's contents).
      - C4: `zbuild foo.txt` and `zbuild --checked x.zil`: one line each, exit nonzero; quote both.
      - C5: take the `.zil` branch out (a scratch edit) and watch C2's scenario fail; restore.
      - C6: `doc/man/zbuild.1.scd` (`make man`), `zbuild --help` and "Starting from ZIL" in `doc/getting_started.md` updated; `sh scripts/test_man_pages.sh` passes; the doc snippet scenario (`./scripts/test.sh --scenario getting-started`) passes.
      - C7: the `KNOWN_ISSUES.md` entry removed or updated; `make test` and `make preflight-changed`, each `Total:` line quoted; the fuzz record is stale for `tools/zbuild/`.

- [ ] +fuzz +safety +AI-G @main Fuzzer generator: add indirect closure, fn-value forwarding, and mutual-recursion route builders id:mskex
    > **Created:** 2026-11-20
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, in the generator group before the fuzz renewal id:v2f8h, which depends on it.
    - **Placed:** before id:z0013 and the post-provenance fuzz renewal (id:a85sp item 3, generator debt).
    - **Do:** add compositional builders and feature tags to `scripts/fuzz/gen.lua` (with matching Rust twin emission) for: (1) closures capturing `&Holder` / `&&Holder` where `Holder` holds `&mut` (`gap_47`, `gap_48`); (2) a capturing closure passed to a `fn(...)` callee that invokes it (`gap_52`) or forwards a view through a closure parameter (`gap_55`); (3) mutually recursive helpers storing a view through a local (`gap_28`, `gap_54`).
    - **Checks:** C1 `lua scripts/fuzz/gen.lua --features` lists the new tags. C2 `make fuzz-short` runs cleanly with 0 `gen-bug`s and covers all new tags. C3 `make fuzz-calibrate` passes. C4 `make test-changed BASE=HEAD`, its `Total:` quoted.

- [ ] +fuzz +safety +AI-G @main Fuzzer generator: add release-tier liveness, inner-block callee store, and method-elision route builders id:4ngz8
    > **Created:** 2026-11-20
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, in the generator group before the fuzz renewal id:v2f8h, which depends on it.
    - **Placed:** before id:z0013 and the post-provenance fuzz renewal (id:a85sp item 3, generator debt).
    - **Do:** add compositional builders and feature tags to `scripts/fuzz/gen.lua` (with matching Rust twin emission) for: (1) release-tier liveness: a view stored through a local `&mut`, `&mut` parameter, `self`, `Box`, or two-callee `put`+`kill` followed by `free`/`reset` (`gap_37`–`gap_39`, `gap_43`, `gap_87`, `gap_96`, `425`–`428`); (2) a callee (direct or `fn` value) storing an inner-block local reference into an outer-block struct (`430`–`433`, `id:nhk9n`); (3) a `&self` method returning a view from another parameter followed by `reset` (`gap_44`, `gap_99`–`gap_101`).
    - **Checks:** C1 `lua scripts/fuzz/gen.lua --features` lists the new tags. C2 `make fuzz-short` runs cleanly with 0 `gen-bug`s and covers all new tags. C3 `make fuzz-calibrate` passes. C4 `make test-changed BASE=HEAD`, its `Total:` quoted.

- [ ] +fuzz +safety +AI-G @main Fuzzer generator: add container-of-views, extend_from_slice/Clone, and by-value aggregate route builders id:r1shp
    > **Created:** 2026-11-20
    > **Branch:** `main`

    - **Promoted (main, 2026-11-20, the maintainer's request):** from `future.tm.md` for the next release, in the generator group before the fuzz renewal id:v2f8h, which depends on it.
    - **Placed:** before id:z0013 and the post-provenance fuzz renewal (id:a85sp item 3, generator debt).
    - **Do:** add compositional builders and feature tags to `scripts/fuzz/gen.lua` (with matching Rust twin emission) for: (1) `Vec::extend_from_slice` and `.clone()` copying views into an external container (`gap_56`, `gap_77`, `gap_78`, `gap_80`); (2) an owned `Vec` or struct holding frame views pushed or moved into a callee (`gap_59`–`gap_63`, `gap_79`); (3) a frame view read through a local reference to a local struct or passed in a by-value aggregate to a callee that stores it out (`gap_97`, `gap_98`).
    - **Checks:** C1 `lua scripts/fuzz/gen.lua --features` lists the new tags. C2 `make fuzz-short` runs cleanly with 0 `gen-bug`s and covers all new tags. C3 `make fuzz-calibrate` passes. C4 `make test-changed BASE=HEAD`, its `Total:` quoted.

- [ ] +fuzz +safety +release +AI-D @main Renew the fuzz record (make fuzz-release) after the provenance and ZIL series id:v2f8h
    > **Created:** 2026-11-20
    > **Branch:** `main`
    > **Depends:** id:w3vde, id:0mbg3, id:mskex, id:4ngz8, id:r1shp

    - **Placed:** after the remaining `@zil` tasks (id:0mbg3) and the generator-debt tasks id:mskex, id:4ngz8 and id:r1shp, and before the release task (id:jtk00), per the maintainer's request (2026-11-20), so the renewed record covers the provenance route classes.
    - **Do:** on a clean `main` tree with `rustc` available, run the release-bar fuzz renewal (`make fuzz-release`, per `id:z0003` and `bench/fuzz/README.md`), triage any findings, update `bench/fuzz/README.md` with the renewed record and commit hashes, and verify `scripts/check_fuzz_fresh.sh` reports fresh for `src/`, `stdlib/`, `tools/zilc`, `tools/zbuild`, and `rt/`.
    - **Checks:** C1 `make fuzz-release` summary line quoted (0 faults, 0 unclassified candidates, 0 `knownblind`, all calibration rows in fixed state). C2 `sh scripts/check_fuzz_fresh.sh` reports fresh for all tracked components. C3 `make test-changed BASE=HEAD`, its `Total:` line quoted.

- [ ] +release +AI-D @main Cut the new release (version bump, changelog, make preflight, tarballs, and tag) id:jtk00
    > **Created:** 2026-11-20
    > **Branch:** `main`
    > **Depends:** id:v2f8h

    - **Placed:** after the fuzz renewal (id:v2f8h), per the maintainer's request (2026-11-20).
    - **Do:** prepare and cut the next Zoril release on `main`:
      1. Bump the version, update `CHANGELOG.md`, `README.md`, `KNOWN_ISSUES.md`, and `doc/SAFETY.md` / release notes for the provenance and ZIL series.
      2. Run the full `make preflight` gate on `main` (and push `bench/records`).
      3. Build and verify the release source tarballs (`make dist`, unpack into an empty directory, build and run `make test` from the tarball with `git` off `PATH`).
      4. Maintainer tags and publishes the release (never push tags from an agent session).
    - **Checks:** C1 `make preflight` passes end to end, quoting each `Total:` line and the store-grid summary. C2 `make dist` produces the release tarball, and building + running `make test` from the unpacked tarball (with no `.git` and `git` off `PATH`) passes, quoting `Total:`. C3 `sh scripts/check_fuzz_fresh.sh` reports fresh. C4 release tag created by the maintainer.
