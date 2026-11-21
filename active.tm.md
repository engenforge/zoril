# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [x] +zil +AI-G @zil ZL2 string_const gives a Slice in the front end and in zilc, read back with slice_ptr id:qpc8d
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil`
    > **Depends:** id:m6vm3
    > **Completed:** 2026-11-21 git:d771472

    - **Placed:** after ZL1, which settles it.

    - **Do:**
      1. Add `IL_INSTR_SLICE_PTR: u32 = 73` and `ILInstr.SlicePtr(SSAId)` in `src/il_instr.zrl` (updating all exhaustive `match`es/accessors in `src/il_instr.zrl`, `src/zil_print.zrl`, `src/il_typecheck.zrl`, `src/verify.zrl`, `tools/zilc/src/zil_parse.zrl`, and `tools/zilc/src/qbe.zrl`). In `zil_parse.zrl`, parse `slice_ptr <ssa>` beside `slice_len`. In `qbe.zrl`, lower `IL_INSTR_SLICE_PTR` to `%vN =l loadl %vS`.
      2. In `tools/zilc/src/qbe.zrl`: in `emit_string_data_sections`, emit `data $SS<id> = align 8 { l $S<id>, l <len> }` beside `data $S<id> = { b ..., b 0 }`; in `IL_INSTR_STRING_CONST`, emit `%vN =l copy $SS<id>`.
      3. In `src/lower_zir_to_zil.zrl`: in `lower_rv_string_const`, emit `ILInstr.StringConst(str_slice)` with type `slice_ty` (`Slice<u8, 'local>`) and return that SSA id directly (removing the entry-block `alloc`, `cast`, and two `store`s). In `lower_stmt`'s `ZirStmt.Let` for `LOCAL_KIND_TMP`, add `ZirRvalue.StringConst(_)` to the `aliases = true` match so `--checked` never poisons `$SS<id>` on `EndBorrow`.
      4. In `src/il_typecheck.zrl`: check `ILInstr.SlicePtr(ssa)` operand is defined (and add `"slice_ptr"` to `instr_opcode`).
      5. Rewrite `corpus/zil/15_io_syscall.zil` and `corpus/zil/19_fd_io.zil` to use `slice_ptr` instead of `bitcast` on their `string_const` values so `15_io_syscall.zil` writes exactly `"IL Syscall\n"` (11 bytes) and `19_fd_io.zil` passes the exact path/data pointers and length.
      6. Update `doc/spec/intermediate_language.md` (§1 grammar, §5.6 Slice Operations, §7 Opcode Summary — 69 opcodes) to document `slice_ptr` beside `slice_len` and remove the stale `slice_data` note.
      7. Regenerate `corpus/zrl_whole_program_zil.sha256` with `UPDATE_GOLDEN=1 sh scripts/test_incremental.sh`.
    - **Checks:**
      - C1: `build/zoril --emit-zil` on a program with a string literal emits `Slice<u8, 'local> = string_const "..."` (quote the line).
      - C2: run `corpus/zil/15_io_syscall.zil` through `build/zilc` -> `qbe` -> `as` -> `ld` and pipe stdout to `wc -c`: prints `11` bytes and exact text `IL Syscall\n`; `corpus/zil/19_fd_io.zil` exits 0.
      - C3: `make test-checked` (or `./scripts/test.sh --flags --checked` on a string-literal test) passes without faulting on `$SS<id>` poisoning.
      - C4: take-out check — revert `IL_INSTR_STRING_CONST` in `qbe.zrl` to `copy $S<id>` (scratch edit) and show `15_io_syscall.zil` fails / prints wrong byte count; restore.
      - C5: `make test` and `make preflight-changed` pass on `zil` (quoting `Total:` lines and selfhost fixpoint; note fuzz record is stale for `src/` and `tools/zilc/`).
    - **Completion note:**
      - Also fixed three QBE lowering interactions in `tools/zilc/src/qbe.zrl` exposed by `Slice<u8, 'local> = string_const`: `IL_INSTR_FIELD_ADDR` handles aggregate `f.val` directly (instead of `get_ptr_inner_type` returning 0), `IL_INSTR_CALL`/`IL_INSTR_CALL_PTR` pass `Slice` / pointer-typed parameters with `l` (`force_ptr`) instead of `:T_N` by-value struct, and `IL_INSTR_STORE` stores `storel` when `s.ptr` points to a pointer (`Ptr<Ptr<...>>`). Updated `README.md` binary size figures (`~38 KB` / `~25 KB` stripped) for `binary-sizes`.
      - C1: `build/zoril --emit-zil corpus/zrl/01_hello_syscall.zrl -I stdlib=stdlib -o build/zl2/01.zil` emitted `v8: Slice<u8, 'local> = string_const "Hello, Zoril!\n"`.
      - C2: `corpus/zil/15_io_syscall.zil` printed `11` bytes and exact text `IL Syscall\n`; `corpus/zil/19_fd_io.zil` exited `0`.
      - C3: `make test-checked` (via `make preflight-changed PREFLIGHT_BASE=HEAD`) passed all 1562 tests without faulting on `$SS<id>` poisoning: `Total: 1562 run, 1562 passed, 0 failed, 0 skipped (107.8s)`.
      - C4: take-out check — reverted `IL_INSTR_STRING_CONST` in `tools/zilc/src/qbe.zrl` to `copy $S<id>`, rebuilt `build/zilc`, and `corpus/zil/15_io_syscall.zil` printed `0` bytes; restored and rebuilt `build/zilc`.
      - C5: `make test`: `Total: 4134 run, 4134 passed, 0 failed, 2 skipped (146.1s)`; `make preflight-changed PREFLIGHT_BASE=HEAD`: `PASS — a clean copy of the tree builds with the default rules, and the compiler reproduces itself.`, `[5] fixpoint — gen3.zil vs gen4.zil must be identical`, `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 0 newly refused, of 69179 programs against 7c3b0071a628890b2812e9bbb51aaa79be938fb6`, `Total: 1562 run, 1562 passed, 0 failed, 0 skipped (107.8s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.3s)`. Fuzz record is stale for `src/` and `tools/zilc/` (renewed in `id:v2f8h`).

- [x] +zil +AI-G @zil ZL3 One spelling for cast: zilc refuses bitcast and the corpus is rewritten id:htrqb
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil`
    > **Depends:** id:qpc8d
    > **Completed:** 2026-11-21 git:40af734

    - **Placed:** after ZL2: the corpus files it rewrites are the ones ZL2 changes.

    - **Do:**
      1. In `tools/zilc/src/zil_parse.zrl` (around line 2022), remove `|| op_str == "bitcast"` from the `cast` branch; add an explicit refusal branch for `op_str == "bitcast"` that reports a parse error naming `cast` (e.g. `unknown opcode 'bitcast' (use 'cast')`) and exits 1.
      2. Rewrite the remaining corpus files that use `bitcast` (`corpus/zil/02_comparison.zil`, `12_enums_sum.zil`, `13_slices.zil`, `24_tuples.zil`, plus verify `15_io_syscall.zil` and `19_fd_io.zil` have none) to use `cast`.
      3. Add a negative test under `tests/zilc/` (and wire it into `scripts/test_zilc_errors.sh`) asserting that `bitcast` is rejected with exit 1 and a diagnostic naming `cast`.
    - **Checks:**
      - C1: `grep -rn 'bitcast' corpus/zil/` prints nothing.
      - C2: `timeout -k 5s 30s build/zilc <bitcast-test.zil> -o /dev/null` exits 1 and prints the diagnostic naming `cast` (quote output); `./scripts/test_zilc_errors.sh` passes.
      - C3: take-out check — temporarily restore `|| op_str == "bitcast"` in `zil_parse.zrl`, rebuild `build/zilc`, and show `scripts/test_zilc_errors.sh` fails; restore.
      - C4: `make test` and `make preflight-changed` pass (quoting `Total:` lines; note fuzz record is stale for `tools/zilc/`).
    - **Completion note:**
      - Also added the four rewritten `corpus/zil/` files (`02_comparison.zil`, `12_enums_sum.zil`, `13_slices.zil`, `24_tuples.zil`) to `bootstrap/stage0-c/tests/outside_dialect.txt` because `stage0-C` only accepts `bitcast`.
      - C1: `grep -rn 'bitcast' corpus/zil/` printed nothing.
      - C2: `timeout -k 5s 30s build/zilc tests/zilc/bitcast_rejected.zil -o /dev/null` exited 1 and printed `zilc: line 6: unknown opcode 'bitcast' (use 'cast')`; `sh scripts/test_zilc_errors.sh` passed all 16 checks.
      - C3: take-out check — restored `|| op_str == "bitcast"` in `tools/zilc/src/zil_parse.zrl`, rebuilt `build/zilc`, and `sh scripts/test_zilc_errors.sh` exited 1 (`[FAIL] tests/zilc/bitcast_rejected.zil`); restored and rebuilt `build/zilc`.
      - C4: `make test`: `Total: 4130 run, 4130 passed, 0 failed, 2 skipped (146.0s)`; `make preflight-changed PREFLIGHT_BASE=HEAD`: `PASS — a clean copy of the tree builds with the default rules, and the compiler reproduces itself.`, `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`, `Total: 1562 run, 1562 passed, 0 failed, 0 skipped (107.7s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.4s)`. Fuzz record is stale for `tools/zilc/` (renewed in `id:v2f8h`).

- [x] +zil +tests +AI-G @zil ZL4 Corpus and per-file tests check the program's output, not only its exit code id:ehh6m
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil`
    > **Depends:** id:htrqb
    > **Completed:** 2026-11-21 git:5f25ee4

    - **Placed:** after ZL3.

    - **Do:**
      1. Add an optional sibling `.stdout` file convention (`<test>.stdout`, e.g. `corpus/zil/15_io_syscall.zil.stdout`) — or `// expected output: <text>` for single-line output — to `scripts/lib/test_runner.sh`. Prefer sibling `<file>.stdout` (handles multi-line output, trailing newlines, and exact byte comparison via `cmp -s` without header-escaping ambiguity, and avoids touching the strict header grammar in `tr_expectations` / `test_test_headers.sh`). In `tr_run_file`, capture the executed binary's stdout separately into `$_dir/stdout.out` (keeping stderr in `$_log` or `$_dir/stderr.out` and appending stdout to `$_log` as before). When `$_file.stdout` exists, compare `$_dir/stdout.out` against `$_file.stdout` with `cmp -s`; on mismatch, fail with `"output mismatch"` and a short diff in `TR_EXPECTED`/`TR_ACTUAL`.
      2. Ensure `tr_discover` in `scripts/lib/test_runner.sh` and `scripts/check_stray_files.sh` / `scripts/check_test_strength.sh` ignore `*.stdout` sibling files (they are fixtures, not tests).
      3. Add `.stdout` files for every printing program in `corpus/zil/` (`15_io_syscall.zil.stdout`) and `corpus/zrl/` (`01_hello_syscall.zrl.stdout`, `17_strings_and_escapes.zrl.stdout`, `18_ffi_and_extern.zrl.stdout`, `27_syscall_io.zrl.stdout`, `38_large_enum_pass_by_value.zrl.stdout`, plus any other `corpus/` program that writes to stdout).
      4. Add a test case (e.g. in `scripts/test_test_headers.sh` or a small scenario) that verifies a program whose stdout differs from its `.stdout` file (including trailing garbage bytes like the 4 KB over-read of `id:1kaye`) fails with `output mismatch`.
    - **Checks:**
      - C1: list every `corpus/` program that writes to stdout and its new `.stdout` file; `./scripts/test.sh corpus/` passes (quote `Total:`).
      - C2: plant trailing bytes into a scratch test's stdout (simulating `id:1kaye`'s 4 KB over-read) with a matching exit code 0: `./scripts/test.sh <scratch>` fails with `output mismatch` (quote `[FAIL]` line).
      - C3: take-out check — temporarily disable the `cmp -s` check in `scripts/lib/test_runner.sh` and show the planted-output test passes vacuously; restore.
      - C4: `make test` passes (quoting `Total:` line).
    - **Completion note:**
      - C1: 6 printing corpus programs and their `.stdout` files: `corpus/zil/15_io_syscall.zil.stdout` (`IL Syscall\n`), `corpus/zrl/01_hello_syscall.zrl.stdout` (`Hello, Zoril!\n`), `corpus/zrl/17_strings_and_escapes.zrl.stdout` (`line1\nline2\n`), `corpus/zrl/18_ffi_and_extern.zrl.stdout` (`Hello from Zoril via direct syscall!\n`), `corpus/zrl/27_syscall_io.zrl.stdout` (`=== Zoril Syscall Demo ===\nThe answer is: 42\n`), `corpus/zrl/38_large_enum_pass_by_value.zrl.stdout` (`pass: match Ident\npass: match Number\npass: match Eof\npass: method Ident\n`). `./scripts/test.sh corpus/` passed: `Total: 67 run, 67 passed, 0 failed, 0 skipped (0.5s)`.
      - C2: `sh scripts/test_test_headers.sh` verified `stdout_ok` passed and `stdout_mismatch` (trailing `"extra"` bytes, exit 0) failed with `[FAIL] build/test-headers/cases/stdout_mismatch.zrl (output mismatch)`.
      - C3: take-out check — disabled `cmp -s` with `false &&` in `scripts/lib/test_runner.sh`, and `sh scripts/test_test_headers.sh` reported `[FAIL] stdout_mismatch: expected '[FAIL] build/test-headers/cases/stdout_mismatch.zrl (output mismatch)', got: [PASS] build/test-headers/cases/stdout_mismatch.zrl (37ms)`; restored.
      - C4: `make test`: `Total: 4130 run, 4130 passed, 0 failed, 2 skipped (146.1s)`.

- [x] +zil +safety +AI-G @zil ZL5 zilc runs the ZIL verifier that the compiler runs id:egsdq
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decisions in id:1kaye (`future.tm.md`), 2026-11-13
    > **Branch:** `zil`
    > **Depends:** id:ehh6m
    > **Completed:** 2026-11-21 git:9af8182

    - **Placed:** after ZL4, last in the series. Check-in `id:rvjcz` follows it.

    - **Do:**
      1. In `tools/zilc/src/main.zrl`, import `verify.zrl` (`use verify::Verifier;`) and run `Verifier.new(arena, &mut module, &mut table, in_path).verify()` after `operand_types_ok` (skipping `check_stores_claims` if `zilc` parses standalone ZIL without `#[stores]` metadata, or ensuring `Verifier.verify()` passes cleanly on all `corpus/zil/` and compiler-emitted `.zil` files). If `verify()` returns non-zero, exit 1 without emitting QBE output.
      2. Verify `closure-private-names` passes for `tools/zilc/src/main.zrl` (importing `verify.zrl` brings `src/diag.zrl` into zilc's closure; ensure no private name collision and that `build/zilc-boot` still builds cleanly through `stage1`).
      3. Add negative ZIL tests under `tests/zilc/` (wired into `scripts/test_zilc_errors.sh`) showing `zilc` rejects a hand-written ZIL file that returns the address of an `alloc 'local` (`region escape: returning a pointer to local stack storage`).
      4. Place the `id:ahd1c` safety-scope statement in `doc/spec/intermediate_language.md` (§6) and `doc/spec/safety_model.md`: Zoril's memory-safety guarantees cover programs compiled from Zoril source; hand-written ZIL is checked by `zilc` for operand types and ZIL-level verification (stack-address escapes, constant arena bounds, and the common-mistake checks of ZL6), not for full memory safety.
    - **Checks:**
      - C1: `timeout -k 5s 30s build/zilc <stack-escape.zil> -o /dev/null` exits 1 with `region escape` diagnostic (quote output); `./scripts/test_zilc_errors.sh` passes.
      - C2: every file in `corpus/zil/` still compiles and passes (`./scripts/test.sh corpus/zil/`, quote `Total:`).
      - C3: `make closure-private-names` and `make selfhost-build-check` pass (`zilc-boot` builds through `stage1`).
      - C4: take-out check — temporarily comment out the `Verifier.verify()` call in `tools/zilc/src/main.zrl`, rebuild `build/zilc`, and show C1's stack-escape test is accepted; restore.
      - C5: `scripts/check_safety_model.sh` and `make test` and `make preflight-changed` pass (quoting `Total:` lines; note fuzz record is stale for `tools/zilc/`).
    - **Completion note:**
      - C1: `timeout -k 5s 30s build/zilc tests/zilc/stack_escape.zil -o /dev/null` exited 1 with `tests/zilc/stack_escape.zil:9:5: error: region escape: returning a pointer to local stack storage`; `sh scripts/test_zilc_errors.sh` passed all 17 checks.
      - C2: `./scripts/test.sh corpus/zil/` passed: `Total: 25 run, 25 passed, 0 failed, 0 skipped (0.2s)`.
      - C3: `./scripts/test.sh --gate closure-private-names` passed (`closure-private-names: tools/zilc/src/main.zrl: 29 modules, no shared private name`, `Total: 3 run, 3 passed, 0 failed, 0 skipped (0.4s)`); `build/zilc-boot` built cleanly through `stage1` and `make selfhost-build-check` passed (`PASS (build only — fixpoint not checked)`).
      - C4: take-out check — commented out `verifier.verify()` in `tools/zilc/src/main.zrl`, rebuilt `build/zilc`, and `tests/zilc/stack_escape.zil` exited `0`; restored and rebuilt `build/zilc`.
      - C5: `sh scripts/check_safety_model.sh`: `PASS: safety_model.md is self-consistent.`; `make test`: `Total: 4130 run, 4130 passed, 0 failed, 2 skipped (147.6s)`; `make preflight-changed PREFLIGHT_BASE=HEAD`: `PASS — a clean copy of the tree builds with the default rules, and the compiler reproduces itself.`, `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`, `Total: 1562 run, 1562 passed, 0 failed, 0 skipped (107.9s)`, `Total: 8 run, 8 passed, 0 failed, 0 skipped (103.2s)`. Fuzz record is stale for `tools/zilc/` (renewed in `id:v2f8h`).

- [x] +zil +review +AI-D @zil @checkin Check-in: review the ZIL +AI-G batch (qpc8d, htrqb, ehh6m, egsdq) id:rvjcz
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:qpc8d, id:htrqb, id:ehh6m, id:egsdq
    > **Completed:** 2026-11-21 git:9af8182

    - **Placed:** directly after id:egsdq (ZL5), the last of the `@zil` `+AI-G` batch (ZL2..ZL5), by the check-in id:3nrvs (`AGENTS.md`, Check-ins, step 3).
    - **Review:** the steps of `AGENTS.md` Check-ins; re-run each task's numbered checks and probe the sibling routes.
    - **Review findings (2026-11-21, commits `d771472..9af8182`):**
      - Re-ran checks across ZL2..ZL5: `build/zoril --emit-zil corpus/zrl/01_hello_syscall.zrl` emits `v8: Slice<u8, 'local> = string_const "Hello, Zoril!\n"`; `grep -rn 'bitcast' corpus/zil/` is empty; `sh scripts/test_zilc_errors.sh` passed all 17 checks; `sh scripts/test_test_headers.sh` passed including `stdout_ok` and `stdout_mismatch`; `sh scripts/check_safety_model.sh` passed (`safety model: 79 rows — 78 proven, 0 GAP (1 N/A)`); `./scripts/test.sh corpus/` passed (`Total: 67 run, 67 passed, 0 failed, 0 skipped (0.5s)`); `sh scripts/check_portability.sh` passed.
      - Probed ZL2 sibling routes (normal, `--checked`, and `zbuild`): direct calls (`[u8]`, `&[u8]`), `fn` pointer calls (`fn([u8])`, `fn(&[u8])` with string literal and array slice), returning `[u8]` and struct holding `[u8]`, loop/branch temporary string literals under `--checked` (no rodata poisoning), storing `&"hello"` into `let r: &[u8]` — all passed.
      - Audited ZL4 corpus stdout: all 6 of 66 corpus tests with non-empty stdout have matching `.stdout` fixtures (0 missed); `tools/ztest/` delegates to `scripts/test.sh` so it inherits `.stdout` checking. Minor note: `scripts/lib/test_runner.sh` uses `head -c 200` for failure preview (non-POSIX flag, supported on GNU/BSD/macOS, passes `check_portability.sh`).
      - **Bug found in ZL2/ZL5 (`src/verify.zrl`):** `ILInstr.SlicePtr` was placed in the no-op arms of both storage-flow / `#[borrows(..)]` analysis (`src/verify.zrl` lines 720–721, where `| ILInstr.SlicePtr(_)` is also duplicated) and `verify_instr` stack-pointer propagation (`src/verify.zrl` line 1652). Probed in hand-written ZIL: returning `slice_construct` of `alloc 'local` is rejected (`error: region escape: returning a pointer to local stack storage`), whereas returning `slice_ptr` of that same slice is silently accepted (`rc=0`). Returning `string_const` and `slice_ptr(string_const)` are both accepted (`rc=0`).
      - **Plan edits:** added `id:1dwwz` (`ZL5b`, `+AI-G`) after `id:rvjcz` to propagate storage-flow and `points_to_stack` through `ILInstr.SlicePtr` (and remove the duplicate match arm) with a negative test, followed by check-in `id:ks44a`; updated `id:0mbg3` `Depends:` to include `id:1dwwz, id:ks44a`.

- [ ] +zil +safety +AI-G @zil ZL5b Propagate stack-pointer and borrows storage flow through ILInstr.SlicePtr in src/verify.zrl id:1dwwz
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:rvjcz

    - **Found by:** check-in `id:rvjcz` probing ZL5 (`id:egsdq`) sibling routes.
    - **Placed:** directly after `id:rvjcz` and before `id:0mbg3` (ZL6), so `src/verify.zrl` catches stack-pointer escapes through `slice_ptr` before ZL6 audits `zilc`'s remaining checks.
    - **Do:**
      1. In `src/verify.zrl`, move `ILInstr.SlicePtr(src)` out of the no-op arm in the storage-flow analysis (lines 720–721, removing both duplicate entries) and add `ILInstr.SlicePtr(src) => { from = src; },` beside `ILInstr.SliceConstruct(sc) => { from = sc.ptr; },` (line 638).
      2. In `src/verify.zrl`, move `ILInstr.SlicePtr(src)` out of the no-op arm in `verify_instr` (line 1652) and propagate `self.is_stack_slot[src] || self.points_to_stack[src]` to `self.points_to_stack[ssa]` beside `ILInstr.SliceConstruct` (line 1612), setting `OwnerState.Owned` on `ssa`.
      3. Add `tests/zilc/slice_ptr_stack_escape.zil` (returning `slice_ptr` of `slice_construct` over `alloc 'local`) with `// EXPECT: region escape: returning a pointer to local stack storage`, verified by `scripts/test_zilc_errors.sh`.
      4. Ensure returning `string_const` and `slice_ptr(string_const)` remain accepted by `zilc` (neither is a stack slot).
    - **Checks:**
      - C1 (before): run `timeout -k 5s 30s build/zilc tests/zilc/slice_ptr_stack_escape.zil -o /dev/null` before editing `src/verify.zrl` and quote exit code `0`.
      - C2 (after): rebuild `build/zoril` and `build/zilc`; `timeout -k 5s 30s build/zilc tests/zilc/slice_ptr_stack_escape.zil -o /dev/null` exits 1 with `region escape: returning a pointer to local stack storage`; `sh scripts/test_zilc_errors.sh` passes all checks.
      - C3 (control): a hand-written ZIL function returning `slice_ptr` of `string_const "hello"` still compiles with `build/zilc` (exit 0).
      - C4 (take-out): revert the `points_to_stack` propagation for `ILInstr.SlicePtr` in `src/verify.zrl`, rebuild `build/zilc`, and show `sh scripts/test_zilc_errors.sh` fails on `tests/zilc/slice_ptr_stack_escape.zil`; restore and rebuild.
      - C5: `make test` and `make preflight-changed` pass on `zil` (quoting `Total:` lines; note fuzz record is stale for `src/` and `tools/zilc/`).
      - Ends with `**Awaiting review:**` bullet for check-in `id:ks44a`.

- [ ] +zil +safety +review +AI-D @zil @checkin Check-in: review ZL5b SlicePtr verifier fix (1dwwz) id:ks44a
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:1dwwz

    - **Placed:** directly after `id:1dwwz` (`+safety` `+AI-G` fix) and before `id:0mbg3`, per `AGENTS.md` Check-ins.
    - **Review:** the steps of `AGENTS.md` Check-ins; re-run `id:1dwwz`'s numbered checks and probe sibling routes (e.g. `slice_ptr` through `phi`, `cast`, or stored into a global/out-param).

- [ ] +zil +safety +audit +AI-D @zil ZL6 Which common mistakes in hand-written ZIL zilc can catch from what ZIL says id:0mbg3
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decision in id:ahd1c (`future.tm.md`)
    > **Branch:** `zil`
    > **Depends:** id:egsdq, id:rvjcz, id:1dwwz, id:ks44a

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

- [ ] +review +AI-D @main @checkin Check-in: review the pre-renewal main +AI-G batch (z0014, z0016, mskex, 4ngz8, r1shp) id:rz4da
    > **Created:** 2026-11-21
    > **Branch:** `main`
    > **Depends:** id:z0014, id:z0016, id:mskex, id:4ngz8, id:r1shp

    - **Placed:** directly after id:r1shp, the last of the pre-renewal `@main` `+AI-G` batch, by the check-in id:3nrvs (`AGENTS.md`, Check-ins, step 3).
    - **Review:** the steps of `AGENTS.md` Check-ins; re-run each task's numbered checks and probe the sibling routes.

- [ ] +fuzz +safety +release +AI-D @main Renew the fuzz record (make fuzz-release) after the provenance and ZIL series id:v2f8h
    > **Created:** 2026-11-20
    > **Branch:** `main`
    > **Depends:** id:w3vde, id:0mbg3, id:mskex, id:4ngz8, id:r1shp, id:rz4da

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
