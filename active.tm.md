# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [ ] +safety +tests +AI-G @provenance B3d A raw-pointer write through a loose raw local reaches the caller's parameter targets under `--provenance` id:77rr6
    > **Created:** 2026-11-19
    > **Branch:** `provenance`
    > **Depends:** id:f81f3

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

- [ ] +safety +tests +AI-G @provenance B3f Stage 1: `memcpy` declares its store effect, and a call to an undeclared `extern` with two or more pointer parameters is refused id:716bm
    > **Created:** 2026-11-19
    > **Branch:** `provenance`
    > **Depends:** id:yp1er

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

- [ ] +safety +tests +AI-G @provenance B3g Stage 2: every `extern` that takes a pointer declares its store effect, or a call passing it a parameter or frame pointer is refused id:eb38n
    > **Created:** 2026-11-19
    > **Branch:** `provenance`
    > **Depends:** id:716bm

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

- [ ] +diagnostics +AI-G @provenance id:z0066 B3.9 Provenance diagnostics name the origin they found, once per site
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Depends:** id:0m61c

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

    - **Moved (2026-11-19, the maintainer's request to group `+AI-G` work):** from after id:z0044 to directly after id:eb38n. It joins that batch of `+AI-G` tasks, and its check-in id:h1yk5 follows the batch's check-in id:g764h. Its only dependency, id:0m61c, is complete. Nothing between its old and new places depends on it. The tests id:77rr6 to id:eb38n add may carry `EXPECT:` lines in the old wording, and this task updates them with the rest (C5).

- [ ] +safety +review +AI-D @provenance @checkin Review of the hidden-store fixes: lead 1, `extern` declarations stage 1 and 2 id:g764h
    > **Created:** 2026-11-19
    > **Branch:** `provenance`
    > **Depends:** id:77rr6, id:716bm, id:eb38n

    - **Placed:** directly after id:eb38n, the last `+AI-G` task of the batch it reviews (id:77rr6, id:716bm, id:eb38n, from id:f81f3's decisions).
    - **Review:** the steps of AGENTS.md's check-in list. Re-run each **Awaiting review:** bullet. Probe the sibling routes: a raw write through a raw pointer in a by-value aggregate, a raw pointer held in a `Vec` (an owner: lead 1 leaves it out), a declared `extern` called through a `fn` value, and an `extern` declared in one module and called from another through `zbuild` (the `.zri` round trip). Confirm that gap_102, gap_103 and F9's test are where the decisions put them: refused under `--provenance`, and the default build's status written in their Known gaps entries.

- [ ] +safety +review +AI-D @provenance @checkin Review of the provenance diagnostics wording and de-duplication (id:z0066) id:h1yk5
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Depends:** id:z0066

    - **Placed:** directly after id:z0066, the `+AI-G` batch it reviews (a review of the task list, the maintainer's request, 2026-11-17: id:z0066 had no check-in, and it changes the checker's diagnostics and the `EXPECT:` lines of provenance tests). id:z0065, the next task that builds on it, depends on this one.

    - **Checks:**
      - Re-read the queue and `git log -p` of id:z0066's commits.
      - Re-run id:z0066's C3 (one diagnostic per site and rule at the four sites) and C4 (two rules at one site print both).
      - No program is accepted that was refused: `REJECT_DIFF_NO_CACHE=1 make preflight-changed` shows 0 newly accepted, and the same count under `--provenance` over `tests/language/memory/provenance/` and the `gap_*` probes before and after (a de-duplication keyed too coarsely must not drop the only error of a function).
      - Every `EXPECT:` line changed is in the commit message's list (C5), and none changed from one rule's message to another rule's.

    - **Moved (2026-11-19, with id:z0066):** to directly after id:g764h, so that both check-ins of the `+AI-G` batch run back to back in one `+AI-D` session. It is still before id:z0065, which depends on it.

- [ ] +safety +measurement +AI-D @provenance B1.8c Measure: a store through a local raw pointer adds the stored value's origins to that local, so a heap block holding a frame address cannot leave the frame id:71a06
    > **Created:** 2026-11-14
    > **Branch:** `provenance`
    > **Depends:** id:z0073, id:0m61c
    > **Check-in:** stop for review after it if the rule is kept: it changes a safety rule.

    - **Placed:** before id:z0012, which it blocks: id:z0012 deletes the old region rule, the only rule that refuses case C of id:z0073 today.

    - **Why (the maintainer's decision in id:z0073, 2026-11-14):** case C (a frame address stored, inside `unsafe`, through the result of a `#[fresh]` function or a block from `zoril_allocator_alloc(null, ..)`, the pointer then returned or put into a global) is decided by measurement. The three programs are `tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`, `heap_block_store_through_old_rule_refused.zrl` and `heap_block_into_global_old_rule_refused.zrl`: refused by the old region rule only, accepted by the new rules since id:z0076 (the pointer has no origins, so a store through it reaches nothing they follow).
    - **Candidate rule (not tried; from the review, 2026-11-14):** a store through a raw pointer held by a local `p` (`*p = v`, `p[i] = v`, a field through it) does `O(p) |= O(v)`, as a write into a projection of a local does. `p` then holds `Frame` when `v` does, and the return rule and the store rule refuse `p` leaving the frame. Say first whether the transfer already does this for a raw pointer with origins, and why a pointer with none is skipped.
    - **Measure:** build a scratch compiler with the candidate (under `build/`, never replacing `build/zoril`), with the old rules off as id:z0074 builds it or under `--provenance` alone: 1. the three programs above: refused or not, and by which rule. 2. `--provenance=warn` over `src/main.zrl`, `tools/zbuild/src/main.zrl`, `tools/zilc` and the test programs (`build/z92/measure.sh`, 672 programs at id:z0092): the warning count before and after, and each new warning read (a real escape, or a safe program refused). 3. the store grid under `--provenance`: no unsafe cell newly accepted, the safe twins newly refused counted by axis. Probe the siblings: the pointer copied to a second local before the store; the pointer held in a struct field of a local; the store made by a callee given the pointer; a pointer from `@ptr_from_int` (`Raw`, exempt as a value by id:z0063: say whether it stays exempt as a carrier).
    - **Then decide, by the maintainer's rule:** if the candidate refuses the three and adds no refusal in the tree (or only real escapes), keep it: commit it with the three tests' `EXPECT:` lines naming the new rule, and say so here. If it refuses safe programs in the tree, do not keep it: case C is outside the guarantee, recorded in `doc/spec/safety_model.md` and `doc/spec/unsafe_policy.md` beside case A, and the three tests become tests of the accept (their expected result changes: stop and report, as `AGENTS.md` asks for a changed expectation).
    - **Checks:** C1 the three programs' results before and after, each quoted. C2 the warning counts before and after with their command, and every new warning listed with its reading. C3 the store grid's summary, quoted. C4 each sibling probe's program and result. C5 the decision recorded here with the figure that made it; if kept, the candidate taken out and the three tests watched to fail; `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, each `Total:` and the `fresh (no cache)` line quoted.

    - **Moved (2026-11-17, a review of the queue against `doc/design/provenance.md`, the maintainer's request):** from after id:z0074 to directly before id:z0065, and added to the **Depends:** of id:z0065 and id:z0074. If the candidate rule is kept, it refuses more under the new rules. So it has to land before id:z0065 makes those rules the default and re-records the store grid, and before id:z0074 lists what only the old rules refuse: its three known members (the `#[fresh]` and heap-block tests) are exactly this task's case C. Before, id:z0074 came first in the queue and would have read that list before the decision existed.

- [ ] +safety +design +AI-D @provenance A call result tied through a reference to an owner holds what the owner holds, not the storage it owns, unless its type can point there id:sjqmy
    > **Created:** 2026-11-17
    > **Branch:** `provenance`

    - **Found by:** id:z0084, reading the reproducers P1 to P5 that the check-in id:n177h placed on it (`build/provenance/build/z84/p1.zrl`-`p5.zrl`).
    - **Placed:** directly before id:z0065, which it blocks (P1 to P4 are safe user code the default flip would refuse), and added to its **Depends:**.
    - **Now (compiler git:dadd49e):** P1 (`return v.clone()` of a local `Vec<u8>`), P2 (`Vec<[u8]>` holding a parameter's view), P3 (`String`) are refused by the return rule, which reads only `O`: the clone's result is `_8 O={Frame(_1)}`, `_1` the local `Vec`'s buffer. `Clone for Vec` reads `self.raw` and the elements through `self`, so its summary ties the result to `ParamContents(0)`, and the caller maps that to everything `&v` reaches through (`os_through_plus`), which includes `S(v)`, the buffer. `v.as_slice()` has the same summary bit and must keep `S(v)` (`build/z84/u1.zrl`: `return v.as_slice()` of a local `Vec`). P4 (`out.resize(1, v)`) is refused inside `stdlib/vec.zrl`'s `resize` (`value.clone()` of a by-value parameter, whose storage is `Frame(value)`) and at the call.
    - **Measured (a scratch compiler, not a rule):** in `os_call`'s `in_ties` branch, reading the tie through one level and keeping only what the pointee holds (`os_through_split` into `O`, its `S` dropped) makes P1 to P4 accepted and leaves P5's `c.push(&buf)` refused; it also accepts `build/z84/u1.zrl`, so as it stands it is unsound. The field-insensitive summary cannot tell `self.raw` (what the owner holds) from `self.data` (the storage it owns).
    - **Decide:** how a summary or the caller tells the two apart. Candidates: (a) a summary bit per parameter for "the storage what the parameter reaches owns" beside `ParamContents` (a read of an owner's own raw pointer field through the parameter gives it; `.zri` and edges carry it); (b) at the caller, leave `S` of the pointee out of a tie when the result's type can hold no pointer to anything the pointee's owned storage holds in place (`Vec<u8>` cannot point at a `u8` buffer except through its own `data`, which points into its own storage; `Vec<&u8>` can); (c) accept P1 to P3 as a bound, with a rewrite. Probe each against `u1.zrl`, `vec_clone_frame_views_returned_refused.zrl` (refused today for this reason, not for its views: id:z0084's **Consequence** bullet), `fn wrap(v: &Vec<i32>) -> Vec<[i32]>` pushing `v.as_slice()`, and a `Vec<Arena>` whose arena lies in the buffer.
    - **P5** (`c = v.clone(); c.push(&buf); return c;` with `v: &Vec<[u8]>`): the push is refused by the call store rule because `c`'s storage is the caller's arena (`ParamContents(0)`), which the design treats as external (§3, _Calls through a `fn` value_: "a frame view pushed into such a `Vec` built from a parameter's `fn` value is refused"). The buffer is fresh, and only `c` reaches it, so the stored view is unreachable once `c` is gone; whether that is accepted is part of the decision (id:n177h expected only the return rule). The `return c` refusal stays.
    - **Checks:** C1 the decision and its reason in the design note §3. C2 P1 to P4 accepted (or the bound and its rewrite in `KNOWN_ISSUES.md` §5, written by id:z0065), `u1.zrl` and `vec_clone_frame_views_returned_refused.zrl` refused; with `v.push(&buf)` taken out of the latter, accepted. C3 the siblings above probed, each with a test. C4 the store grid under `--provenance`, `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed`.

    - **Related work parked (2026-11-18, id:bfd1z):** candidate (a) above is close to the `ParamOwned` word id:bfd1z built and measured. That word is a subset of ParamContents, written by an owning read (a raw pointer, a box, a 64-bit integer, a type parameter) and cleared by a read of a reference or a slice. It was not committed, because a held tie would free only 5 of the 84 declaration sites. Its patch against git:cd7e10d (**Patch: the word**), checks C1 to C4 and Findings A to C are in id:bfd1z's text in `completed.tm.md`. Finding A matters here: integers must stay owning reads, since a plain `as` cast makes a pointer with no Raw origin. The word gives the summary what this task needs, but no rule reads it yet. Here it would be read at the caller, in `os_call`'s tie arm: leave out `S` of the pointee where the callee's tie has no ParamOwned. Measure P1 to P5 and `u1.zrl` with the patch applied before choosing between (a), (b) and (c).

- [ ] +safety +tests +AI-D @provenance id:z0065 B4a The new rules on by default, beside the old ones
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Depends:** id:z0064, id:z0075, id:z0088, id:z0092, id:z0180, id:z0093, id:z0094, id:z0097, id:z0087, id:z0086, id:z0084, id:z0089, id:z0090, id:7kbpd, id:z0066, id:h1yk5, id:w17jf, id:nc3ym, id:4by24, id:z0091, id:71a06, id:sjqmy
    > **Check-in:** stop for review after it.

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

- [ ] +safety +tests +AI-D @provenance id:z0074 B4b List every program the old rules refuse and the new rules accept, and read each
    > **Created:** 2026-11-05
    > **Branch:** `provenance`
    > **Depends:** id:z0065, id:71a06

    - **Found by:** the review of id:z0071.

    - **Why:** `leak_vec` (id:z0071) was refused by neither differential the series runs: the rejection differential compares two compilers in the default mode, and `build/rv/provdiff.sh` compares `--provenance` before and after a change over the existing probes. A reviewer found it by hand. id:z0012 deletes the old rules, so every program only they refuse is accepted after it; that list is not computed anywhere.
    - **Do:** run the new rules alone (a scratch compiler with the old rules' refusals off, as `check_reject_diff.sh` builds its base in a scratch worktree, or a developer flag if one is cheaper; say which) and the default compiler over the rejection differential's program set (69,122 at id:z0071, `tests/`, the safety probes, the store grid twins). List every program refused by the default and accepted by the new rules alone, and read each: a real escape gets a fix or a `known_gap` probe before id:z0012; a safe program is recorded as id:z0012's intended acceptance.
    - **Make it a gate** if it is cheap enough: id:z0012's completion note then lists the same set, empty of unsafe programs.
    - **Known members (from id:z0076, 2026-11-06):** `tests/language/memory/provenance/fresh_store_through_old_rule_refused.zrl`, `heap_block_store_through_old_rule_refused.zrl` and `heap_block_into_global_old_rule_refused.zrl` are refused by the old region rule only: a frame address stored through a `#[fresh]` result or a heap block, the pointer then returned or put into a global. Their expected diagnostic names the old rule, so they fail when it goes; id:z0073 decides what replaces it.
    - **Correction (2026-11-17, a review of the task list):** id:z0073's decision (2026-11-14) passed these three programs (its case C) to the measurement id:71a06, which comes after this task in the queue. Until it is done they are members of this task's list, recorded as "decided by id:71a06", not read again here.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +safety +tests +AI-D @provenance A `fn` item or closure that stores its own parameter into a global, made into a value, is refused by the new rules id:4f0ew
    > **Created:** 2026-11-17
    > **Branch:** `provenance`

    - **Found by:** id:4by24, probing the sibling routes of a call through a `fn` value (compiler git:94c0ed2, and the same with id:4by24's change).
    - **Placed:** directly before id:z0012, which it blocks: once the old rules are deleted, both programs below compile and leave a dangling pointer in `G`.
    - **Now:** under `--provenance` the new rules accept both of these; only the old rules refuse them ("region escape: the function stores a reference into memory that outlives a call through a `fn` value"). A call through a `fn` value checks each argument against what the other arguments and the environment reach, never against a global (design note §3, _Calls through a `fn` value_), and the closure rule (id:z0096) applies only the edges whose value is what the environment reaches. An edge whose value is a declared parameter is checked nowhere.
      - `static mut G: *i32 = 0 as *i32; fn stash(r: &i32) { unsafe { G = r as *i32; } } fn apply(f: fn(&i32), r: &i32) { f(r); } fn bad() -> i32 { let x = 1; apply(stash, &x); return 0; } fn main() -> i32 { let _ = bad(); return unsafe { *G }; }` (a `fn` item; id:z0012's **From id:z0092** bullet names this half).
      - The same with `apply(|q: &i32| { unsafe { G = q as *i32; } }, &x);` in `bad` (a closure). The design note §3 _A closure made into a value_ said this one "is refused at `run`'s call"; no test showed it, and it is not (id:4by24 corrected the sentence).
      - A `fn` item bound to a local and called through it is refused, by its summary (`let f: fn(&i32) = stash; let g = f; g(&x);`: "the callee stores an address of this frame into a global (call store rule)").
    - **Do:** decide where a parameter-to-global (or parameter-to-another-parameter) edge of a body made into a value is checked: where the value is made (refuse the edge outright, as `check_fn_value` does), or at every call through a `fn` value (a global destination for every argument, which refuses every frame address handed to a `fn` parameter). Then implement it, with the two programs above as tests, and probe the siblings: an `unsafe fn` value, a method value (`S::get`), a generic instance, a closure in a struct field, a `fn` value returned by a call.
    - **Also:** the header comment of `os_check_closure_value` (`src/check_zir.zrl`) says the same wrong thing as the design note did ("An edge whose value is a declared parameter is checked where the argument is passed"); correct it with the fix.
    - **Checks:** C1 both programs refused under `--provenance` by a `provenance:` diagnostic, with a test each. C2 each sibling probed, refused where unsafe, with a test. C3 the rejection differential (it removes no refusal unless the decision does), `make test`, `REJECT_DIFF_NO_CACHE=1 make preflight-changed`.

- [ ] +safety +tests +AI-D @provenance id:z0012 B4 Make `--provenance` the default, delete the old classifiers, and fix what the measurement found
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0011, id:z0044, id:z0065, id:z0063, id:z0073, id:z0074, id:z0075, id:z0096, id:71a06, id:4f0ew
    > **Check-in:** stop for review after it. **Split here** if the tree needs more than a session of changes.

    - **Depends changed (2026-11-14, the maintainer, by id:z0073's decision):** added id:71a06, which decides case C before the old region rule is deleted.
    - **Split (2026-11-05, from id:z0049's review):** turning the rules on by default beside the old ones is id:z0065 (it only refuses more); this task is now the half that accepts more: delete the old rules and `src/summary_pass.zrl`, with the rejection differential, and the docs and twin lists. The fixes of the measurement are id:z0060 to id:z0063, and the `unsafe fn` exemption item moved to id:z0063, which narrowed it to `Raw`.

    - **Do:** make the new rules the default and remove `--provenance`; resolve every warn-mode rejection recorded in id:z0049 and id:z0011 (a real escape: fix the code; a common over-rejection: apply the decided fix; a leak through a by-value collection parameter: change the code); then delete `local_storage_external`, `local_is_external_target`, `rvalue_is_external_target`, `place_outlives_frame`, `rvalue_storage_external`, `storage_walk_zir`'s mask logic, `note_call_stores_zir`, the depth limits, `is_collection_type_name`, the same-parameter filters, and `src/summary_pass.zrl` (keeping `src/verify.zrl`'s stack-address check as an add-only second net).
    - **Flip probes and twin lists (including id:z0045's):** flip all closed `known_gap` probes (`gap_07`, `gap_11`, `gap_13`, `gap_16`, `gap_18`, `gap_21`, `gap_23`, `gap_26`, `gap_27`, `gap_28`, `gap_29`, `gap_32`, `gap_33`, `gap_36`, `gap_40`, `gap_41`, `gap_42`, `gap_44`, `gap_45`, `gap_47`, `gap_48`, `gap_49`, `gap_50`, `gap_51`, `gap_52`, `gap_53`, `gap_54`, `gap_55`) to `compile_reject` and remove their Known gaps entries in `bench/safety_matrix/README.md` and class entries in `bench/safety_matrix/README.md` / `doc/SAFETY.md` §6. Fold in id:z0045: remove the 3402 `ref_{let,identity,phi}` twins (and any id:z0017 twins newly accepted when `summary_pass.zrl` is retired) from `bench/fuzz/store_grid_twin_rejections.txt`, flip `read_through_{ref,identity,phi}.zrl` from `expected compile fail` to running tests, add an `accept` probe for `id:z0045` and a regression test returning `s.as_slice()` from `String.with_capacity(a, cap)` (`a: &Arena`). Because retiring `summary_pass.zrl` and `local_storage_external` accepts more safe programs, run `scripts/check_reject_diff.sh <base>` and list every newly accepted program class in the completion note (none may be unsafe). Update `doc/SAFETY.md` §2.3 and §5–§6, `doc/spec/surface_syntax.md` (`#[borrows]`/`#[stores]`), `README.md`, `KNOWN_ISSUES.md` and `bench/fuzz/store_grid_expected_failures.txt`.
    - **End criterion of the series (the maintainer, 2026-11-06, at id:z0075):** zero unsafe programs accepted is the hard requirement (the grid, the safety probes, the rejection differential). Zero safe programs refused is not reachable by any checker that accepts no unsafe one; the target is that no remaining refusal is common in user code (the tests as its stand-in), each is a documented class in `KNOWN_ISSUES.md` §5 with a reason and a rewrite (id:z0017 audits them), and its diagnostic says what was found (id:z0066).
    - **Done when:** every unsafe store-grid cell (whole-program and modular) is rejected, no `known_gap` probe of this family remains, the self-hosting fixpoint holds, and `make test` and `make preflight` pass. Stop for review, then close id:z0045 (citing this commit on `main`) and start id:z0017 and id:z0013 (and renew the fuzz record per id:z0003).
    - **From id:z0092 (2026-11-06):** the old rules refuse making a `fn` item that stores into a global or another parameter into a value (`check_fn_value` in `src/verify.zrl`); the new rules have no counterpart, since a call through a `fn` value records no store into a global (design note §3, _Calls through a `fn` value_). Carry it over before deleting the old rules: id:z0096 is the closure half of the same route. **Depends also:** id:z0096.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

    - **Flip list (2026-11-17, a review of the queue):** the probe list under **Flip probes and twin lists** dates from before the split. id:z0065 now flips every escape probe that the new rules refuse (its **Baseline of the probes**), and the liveness tasks ahead of it flip their own. So this task flips only what is still `known_gap` once the old rules are deleted. A probe the old rules alone refused, and that is accepted afterwards, is a hole: id:z0074 lists those, and this task needs that list empty of unsafe programs.

- [ ] +audit +safety +AI-G @provenance id:z0045 A reference to a local carrier passed through a `let`, an identity call or a phi is refused
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0012

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
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +audit +AI-D @provenance id:z0017 A3.5 Twelve safe store-grid twins are rejected
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0012

    - **Depends note:** (do not debug `src/summary_pass.zrl` before id:z0012 deletes it). Over-rejection audit, not a hole.

    - **Cells (before id:z0012):** `{ref_local,elem_ref}__{struct_field,tuple_slot,array_slot}__{closure,param_65}__call_struct_mut__frame_ends` (12 cells) plus 96 cells exposed by id:z0008 in `bench/fuzz/store_grid_twin_rejections.txt`, rejected today by `src/summary_pass.zrl` ("region escape: storing local stack pointer into caller memory"). Also note the sibling found in id:z0047's review: passing a local struct `RefHolder { r: &c }` by value to `take_holder(h)` retains `Frame(c)` (`os_reach_all`).
    - **Over-rejection from id:z0007 (found in its review, 2026-11-03):** liveness borrows are tracked per local, not per field, so `w.s = v.as_slice(); let x = w.s[0]; a.reset(); return x - 42 + w.t - 3;` is refused at `a.reset()` because `w` stays live for `w.t`.
    - **Do (after id:z0012):** inspect every twin still listed in `bench/fuzz/store_grid_twin_rejections.txt` once `summary_pass.zrl` is gone (`param_65` twins should be accepted via the overflow bit; `closure`/`fn`-value twins: Decision 3 is decided (id:z0088), so any still refused after id:z0092 to id:z0094 is a finding, not a bound by design). Fix any unintended over-rejection without reopening any probe, add an `accept` probe for any fixed class, and document any deliberate precision bound (such as field-insensitive borrows) in `KNOWN_ISSUES.md` §5. `make test`, `make preflight-changed`, the rejection differential.
    - **Done when (2026-11-06, the series' end criterion, recorded on id:z0012):** every safe twin still in `bench/fuzz/store_grid_twin_rejections.txt` (and the modular list) is in a class `KNOWN_ISSUES.md` §5 names, with its reason and a rewrite, and none is common in the tests. `closure`/`fn`-value twins follow id:z0088's decision, not the note above.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

- [ ] +safety +docs +AI-D @provenance Close the provenance series: the design note as built, the fuzz record renewed, and the series end criterion checked id:a85sp
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Depends:** id:z0012, id:z0045, id:z0017

    - **Placed:** directly after id:z0017, the last open task of the series. It was found in a review of the queue against `doc/design/provenance.md` (the maintainer's request, 2026-11-17): no open task brought the design note up to date with what was built, or started the fuzz renewal that id:z0003 decided would follow id:z0012.
    - **Why:** the design note says it is "the design that the hardening series implements". Its §4 still marks most rows open (`gap_11`, `gap_40` to `gap_42`, `gap_47`, `gap_48` and others), and its §5 lists what the model "will newly reject (to measure, not assumed)". §6 describes the flag that id:z0012 removes, and lists only the tasks up to id:z0012, not the precision, liveness and closure tasks that were added later. id:z0012 updates `doc/SAFETY.md`, `doc/spec/surface_syntax.md`, `README.md` and `KNOWN_ISSUES.md`, but not this note. The fuzz record has been stale for `src/` since early in the series. id:z0003 (confirmed by the maintainer on 2026-11-03) renews it once, after id:z0012, and id:z0013's generator debt is to be run in the same session.
    - **Do:**
      1. Bring `doc/design/provenance.md` up to date with the rules as built. In §4, give each row the probe that closed it and say whether it is closed. In §5, replace each "to measure" item with the figure that was measured, the task that measured it, and what was decided. In §6, describe the landing as it happened (the flag gone, the old classifiers deleted, the ZIL check kept add-only) and list every task of the series. §1 and §2 stay as history, marked "before the series".
      2. Check the series' end criterion (id:z0012, 2026-11-06). The grid accepts 0 unsafe cells, whole-program and modular; no `known_gap` probe of the escape or liveness families remains; and every safe twin still refused is in a class that `KNOWN_ISSUES.md` §5 names. Where one of these fails, add a task (placed by the AGENTS.md rule) rather than fixing it here.
      3. List each route class added in the series and whether `scripts/fuzz/gen.lua` covers it (id:z0013's **Generator debt**). Add a task for each missing generator feature, placed before the renewal.
      4. The fuzz renewal is the maintainer's: a session takes the machine for hours (id:z0003). Ask the maintainer to start it, and record the request here.
    - **Checks:** C1 every §4 row names its closing probe or its open task, and `rg -n '\(open\)' doc/design/provenance.md` prints only rows with an open task. C2 `sh scripts/check_store_grid.sh` summary quoted, with 0 unsafe accepted. C3 `rg -l 'expected: known_gap' bench/safety_matrix/probes` lists no escape or liveness probe, quoted. C4 the route-class list with its generator coverage, and the tasks it added. C5 `make test-changed`, its `Total:` line quoted. C6 `tm validate --strict doc/tasks/*.tm.md` prints no warning.

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
