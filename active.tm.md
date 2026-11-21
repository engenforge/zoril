# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [x] +zil +safety +audit +AI-D @zil ZL6 Which common mistakes in hand-written ZIL zilc can catch from what ZIL says id:0mbg3
    > **Created:** 2026-11-13
    > **Context:** the maintainer's decision in id:ahd1c (`future.tm.md`)
    > **Branch:** `zil`
    > **Depends:** id:egsdq, id:rvjcz, id:1dwwz, id:ks44a
    > **Completed:** 2026-11-21

    - **Placed:** after ZL5, which gives zilc the ZIL verifier this task extends.

    - **Why:** ZIL is not checked for memory safety, but zilc should catch the mistakes that are easy to see in ZIL as designed and that happen most often (the maintainer, id:ahd1c).
    - **Do:** list candidate checks, each with a three-line ZIL program that shows the mistake, and say for each whether ZIL as written carries what the check needs. Candidates to start from: a value used after a `move` or `drop` in the same function, a `drop` twice, a `slice_load`/`slice_store` with no dominating `bounds_check` (spec §6.3), the address of an `alloc 'local` returned or stored into a global, a `slice_len` or `slice_ptr` on a value that is not a slice, a `syscall` with an argument count its stub does not take, and a block with no terminator. Corpus mistakes count as evidence of what is common: id:1kaye's string over-read is one. Rank them by how often they would fire and how simple they are, and split each chosen check into an `+AI-G` task with its own numbered **Checks:** and a take-out.
    - **Checks:** C1: every candidate has its program and its answer here, with the zilc output today (`timeout -k 5s 30s build/zilc <file>`). C2: the chosen checks are tasks, placed after this one, with a check-in after them.
    - **Audit results (2026-11-21, `build/zilc` at `ad3b8c8`, cross-checked against `build/zoril --emit-zil` on `src/main.zrl` (538,925 lines: `slice_len=0 slice_ptr=0 slice_load=0 slice_store=0 bounds_check=0 move=11164 drop=0`), `tests/stdlib/test_stdlib_bufio.zrl` (30,182 lines: `unterminated=0 immut_store=1433 same_blk_uam=1`), and all 24 `corpus/zil/` files):**
      - **C1 — Candidate 1a/1b (use after `move` in the same function):**
        - Program 1a: `type T0: struct { x: i32 }; f0: i32 main() { @b0: v1: i32 = const 7; v2: T0 = struct_construct T0, v1; v3: T0 = move v2; v4: T0 = move v2; ret v1 }` -> `zilc` today: `exit=0` (no output).
        - Program 1b: `f0: i32 main() { @b0: v1: PtrMut<i32, 'local> = alloc 'local, i32; v2: i32 = const 7; store v1, v2; v3: PtrMut<i32, 'local> = move v1; v4: i32 = load v1; ret v4 }` -> `zilc` today: `exit=0`.
        - **Does ZIL carry what the check needs? NO.** ZIL has no `Copy` marker on types, and Zoril's lowerer emits `move` on stack slots of `Copy` aggregates and keeps reading fields from the slot in the same block (probed in `test_stdlib_bufio.zrl` at `@entry_2002`: `vbuf_13: Ptr<Slice<u8, 'local>, 'local> = move vbuf_5` followed by `v15: Ptr<u64, 'local> = field_addr vbuf_5, 1`). **Not chosen.**
      - **C1 — Candidate 1c & 2 (use after `drop` and double `drop`):**
        - Program 1c: `f0: i32 main() { @b0: v1: PtrMut<i32, 'local> = alloc 'local, i32; v2: i32 = const 7; store v1, v2; drop v1; v3: i32 = load v1; ret v3 }` -> `zilc` today: `exit=0`.
        - Program 2: `f0: i32 main() { @b0: v1: PtrMut<i32, 'local> = alloc 'local, i32; drop v1; drop v1; v2: i32 = const 0; ret v2 }` -> `zilc` today: `exit=0`.
        - **Does ZIL carry what the check needs? YES.** `zoril` never emits `ILInstr.Drop` (`drop=0` in `src/main.zrl`), so `drop` only appears in hand-written ZIL; `src/verify.zrl` already sets `OwnerState.Dropped` on `ILInstr.Drop` (line 2219) and clones `current_map` across CFG branches, so rejecting `OwnerState.Dropped` in `ILInstr.Drop` and `check_ssa_access` is ~20 lines with zero Zoril false positives. **Chosen (Rank 4 -> `id:pkcsy` ZL6d).**
      - **C1 — Candidate 3 (`slice_load`/`slice_store` without dominating `bounds_check`, spec §6.3):**
        - Program: `f0: u8 main() { @b0: v1: Slice<u8, 'local> = string_const "hi"; v2: i64 = const 5; v3: u8 = slice_load v1, v2; ret v3 }` -> `zilc` today: `exit=0`.
        - **Does ZIL carry what the check needs? NO (as designed).** `BoundsCheckInstr` takes `(idx, len)` rather than `(collection, idx)` (spec §6.3 prose disagrees with the IR), `tools/zilc/src/qbe.zrl` lowers `IL_INSTR_BOUNDS_CHECK` to a no-op (line 2666), and `zoril` emits 0 `bounds_check`/`slice_load`/`slice_store`. Checking only for some `bounds_check` without matching `len == slice_len(base)` and without runtime trapping would be theatrical safety. **Not chosen.**
      - **C1 — Candidate 4 (address of `alloc 'local` returned or stored into a global, plus `phi` sibling):**
        - Program 4a (direct return): `f0: PtrMut<i32, 'local> leak() { @b0: v1: PtrMut<i32, 'local> = alloc 'local, i32; ret v1 }` -> `zilc` today: `exit=1` (`error: region escape: returning a pointer to local stack storage`) — **already caught**.
        - Program 4b (stored into global): `global g0: PtrMut<i32, 'local> = zeroinit; f0: void leak() { @b0: v1: PtrMut<i32, 'local> = alloc 'local, i32; v2: PtrMut<PtrMut<i32, 'local>, 'local> = global_addr g0; store v2, v1; ret }` -> `zilc` today: `exit=0`.
        - Program 4c (returned via `phi`): `f0: PtrMut<i32, 'local> leak(v0: bool, v1: PtrMut<i32, 'local>) { @b0: branch v0, @b1, @b2; @b1: v2: PtrMut<i32, 'local> = alloc 'local, i32; jump @b3; @b2: jump @b3; @b3: v3: PtrMut<i32, 'local> = phi [@b1: v2, @b2: v1]; ret v3 }` -> `zilc` today: `exit=0`.
        - **Does ZIL carry what the check needs? YES.** `src/verify.zrl` already tracks `is_stack_slot`/`points_to_stack` and `ILInstr.GlobalAddr`; tracking `is_global_addr` (propagated through `Cast`/`FieldAddr`/`Add`/`Move`/`Borrow`) to reject storing a stack pointer into a global, plus propagating `points_to_stack` through `Phi`, is ~30 lines. **Chosen (Rank 3 -> `id:djynw` ZL6c).**
      - **C1 — Candidate 5 (`slice_len` or `slice_ptr` on a non-slice, the `id:1kaye` bug class):**
        - Program 5a: `f0: i64 main() { @b0: v1: PtrMut<u8, 'local> = alloc 'local, u8; v2: i64 = slice_len v1; ret v2 }` -> `zilc` today: `exit=0`.
        - Program 5b: `f0: Ptr<u8, 'local> bad() { @b0: v1: i32 = const 42; v2: Ptr<u8, 'local> = slice_ptr v1; ret v2 }` -> `zilc` today: `exit=0`.
        - **Does ZIL carry what the check needs? YES.** `f.get_ssa_type(ssa)` distinguishes `ILType.Slice` from pointers/primitives; applies identically to `slice_len`, `slice_ptr`, `slice_load`, and `slice_store` (~15 lines in `src/il_typecheck.zrl`, zero false positives on Zoril ZIL or `corpus/zil/`). **Chosen (Rank 1 -> `id:0r49n` ZL6a).**
      - **C1 — Candidate 6 (`syscall` with >6 data arguments):**
        - Program: `f0: i64 main() { @b0: v0: i64 = const 1; v1: i64 = syscall v0, v0, v0, v0, v0, v0, v0, v0; ret v1 }` -> `zilc` today: `exit=0` (emits `call $__zoril_syscall_7`, fails at link time).
        - **Does ZIL carry what the check needs? YES.** `SyscallInstr.args.len > 6` (~6 lines in `src/il_typecheck.zrl`; `rt/runtime.s` only provides `__zoril_syscall_0..6`). **Chosen (Rank 1 -> `id:0r49n` ZL6a).**
      - **C1 — Candidate 7 & 11 (block with no terminator, and jump/branch to undefined block):**
        - Program 7: `f0: i32 main() { @b0: v1: i32 = const 42 }` -> `zilc` today: `exit=0` (emits unterminated QBE block).
        - Program 11: `f0: i32 main() { @b0: jump @b99 }` -> `zilc` today: `exit=0` (emits `jmp @b1`, cryptic QBE error).
        - **Does ZIL carry what the check needs? YES.** Every defined block in `f.block_ids()` must be non-empty and end with `Ret`/`Jmp`/`Branch`/`Unreachable`/`VariantMatch`, and every target block ID of `Jmp`/`Branch`/`VariantMatch` must appear in `f.block_ids()`. Verified `unterminated=0` on `test_stdlib_bufio.zrl` and all 24 `corpus/zil/` files (~30 lines in `src/il_typecheck.zrl`). **Chosen (Rank 2 -> `id:epx51` ZL6b).**
      - **C1 — Extra Candidate 8 (`call` with wrong argument count):**
        - Program: `f0: i32 add(v0: i32, v1: i32) { @b0: v2: i32 = add v0, v1; ret v2 }; f1: i32 main() { @b0: v1: i32 = const 1; v2: i32 = call f0(v1); ret v2 }` -> `zilc` today: `exit=0` (`src/il_typecheck.zrl` line 409 stops at `min(args.len, params_len)` without checking arity).
        - **Does ZIL carry what the check needs? YES.** `callee.params_len` and `callee.is_variadic` are on `ILFunction` (~10 lines in `src/il_typecheck.zrl`). **Chosen (Rank 1 -> `id:0r49n` ZL6a).**
      - **C1 — Extra Candidate 9 (`load` from a non-pointer, structural twin of `store`):**
        - Program: `f0: i32 main() { @b0: v1: i32 = const 42; v2: i32 = load v1; ret v2 }` -> `zilc` today: `exit=0` (`src/il_typecheck.zrl` line 341 omits the `pointee(m, pt) == 0` guard that `Store` has at line 306).
        - **Does ZIL carry what the check needs? YES.** Identical 8-line guard to `Store` in `src/il_typecheck.zrl`. **Chosen (Rank 1 -> `id:0r49n` ZL6a).**
      - **C1 — Extra Candidate 10 (`store` through immutable `Ptr<T, 'r>`, spec §6.6):**
        - Program: `f0: i32 main() { @b0: v1: PtrMut<i32, 'local> = alloc 'local, i32; v2: Ptr<i32, 'local> = cast v1; v3: i32 = const 7; store v2, v3; ret v3 }` -> `zilc` today: `exit=0`.
        - **Does ZIL carry what the check needs? NO.** Zoril's lowerer types `alloc 'local, T` as `Ptr<T, 'local>` and stores through it 1,433 times in `test_stdlib_bufio.zrl`. **Not chosen.**
      - **C2:** Chosen checks split into four `+AI-G` tasks placed directly below (`id:0r49n` ZL6a, `id:epx51` ZL6b, `id:djynw` ZL6c, `id:pkcsy` ZL6d) followed by check-in `id:mf9gq`; `id:v2f8h` updated to depend on `id:mf9gq`.

- [ ] +zil +safety +AI-G @zil ZL6a Reject non-slice slice ops, non-pointer load, >6-arg syscall, and wrong call arity in src/il_typecheck.zrl id:0r49n
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:0mbg3

    - **Placed:** directly after `id:0mbg3` (ZL6), Rank 1 common-mistake checks in `src/il_typecheck.zrl`.
    - **Do:**
      1. In `src/il_typecheck.zrl` (`instr_type_issue`), for `ILInstr.SliceLen(src)`, `ILInstr.SlicePtr(src)`, `ILInstr.SliceLoad(sl)` (`sl.base`), and `ILInstr.SliceStore(ss)` (`ss.base`): check that the operand's type (when defined and non-zero) is `ILType.Slice`; otherwise return a clear diagnostic naming the opcode and operand type (e.g. `slice_len of ... which is not a slice`).
      2. In `src/il_typecheck.zrl` (`instr_type_issue`), for `ILInstr.Load(src)`: add the `pointee(m, pt) == 0` check matching `ILInstr.Store` (line 306), returning `load through <ty>, which is not a pointer (the address operand must be pointer-typed)`.
      3. In `src/il_typecheck.zrl` (`instr_type_issue`), for `ILInstr.Syscall(s)`: if `s.args.len > 6 as usize`, return `syscall with more than 6 arguments (runtime supports 0..6)`.
      4. In `src/il_typecheck.zrl` (`instr_type_issue`), for `ILInstr.Call(c)`: when `(c.func_idx as usize) < m.functions.len()`, reject `c.args.len != callee.params_len` for non-variadic callees and `c.args.len < callee.params_len` for variadic callees, naming the expected and actual argument counts.
      5. Add negative ZIL tests under `tests/zilc/` with `// EXPECT:` headers (verified by `scripts/test_zilc_errors.sh`): `slice_len_non_slice.zil`, `slice_ptr_non_slice.zil`, `load_non_pointer.zil`, `syscall_too_many_args.zil`, `call_wrong_arity.zil`.
    - **Checks:**
      - C1 (before): run `timeout -k 5s 30s build/zilc <file> -o /dev/null` on all five new `tests/zilc/` files before editing `src/il_typecheck.zrl`; quote exit code `0` for each.
      - C2 (after): rebuild `build/zoril` and `build/zilc`; `sh scripts/test_zilc_errors.sh` passes all checks including the 5 new tests (quote the 5 `[PASS]` lines).
      - C3 (take-out): temporarily revert the `SliceLen`/`SlicePtr` check in `src/il_typecheck.zrl`, rebuild `build/zilc`, and show `sh scripts/test_zilc_errors.sh` fails on `slice_len_non_slice.zil` and `slice_ptr_non_slice.zil`; restore and rebuild.
      - C4: `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed` pass on `zil` (quote `Total:` lines and `reject-diff: base verdicts: fresh (no cache)`; note fuzz record is stale for `src/` and `tools/zilc/`).
      - Ends with `**Awaiting review:**` bullet for check-in `id:mf9gq`.

- [ ] +zil +safety +AI-G @zil ZL6b Reject unterminated blocks and undefined jump/branch targets in src/il_typecheck.zrl id:epx51
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:0r49n

    - **Placed:** after `id:0r49n` (ZL6a), Rank 2 CFG well-formedness checks in `src/il_typecheck.zrl`.
    - **Do:**
      1. In `src/il_typecheck.zrl` (`type_check_function`), for every block `b` in `f.block_ids()`, verify `b.instructions_len > 0` and its last instruction is a terminator (`ILInstr.Ret(_)`, `ILInstr.Jmp(_)`, `ILInstr.Branch(_)`, `ILInstr.Unreachable`, or `ILInstr.VariantMatch(_)`). Otherwise push a `TypeIssue` (`block ends without a terminator`).
      2. In `src/il_typecheck.zrl` (`type_check_function`), for every `ILInstr.Jmp(target)`, `ILInstr.Branch(br)` (`br.then_block`, `br.else_block`), and `ILInstr.VariantMatch(vm)` (every arm target and default target when non-zero/valid), verify the target block ID appears in `f.block_ids()`. Otherwise push a `TypeIssue` (`branch/jump target names no defined block`).
      3. Add negative ZIL tests under `tests/zilc/` with `// EXPECT:` headers: `block_no_terminator.zil` and `jump_undefined_block.zil`.
    - **Checks:**
      - C1 (before): run `timeout -k 5s 30s build/zilc <file> -o /dev/null` on both new `tests/zilc/` files before editing `src/il_typecheck.zrl`; quote exit code `0` for each.
      - C2 (after): rebuild `build/zoril` and `build/zilc`; `sh scripts/test_zilc_errors.sh` passes all checks including the 2 new tests (quote both `[PASS]` lines).
      - C3 (take-out): temporarily revert the terminator check in `src/il_typecheck.zrl`, rebuild `build/zilc`, and show `sh scripts/test_zilc_errors.sh` fails on `block_no_terminator.zil`; restore and rebuild.
      - C4: `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed` pass on `zil` (quote `Total:` lines and `reject-diff: base verdicts: fresh (no cache)`; note fuzz record is stale for `src/` and `tools/zilc/`).
      - Ends with `**Awaiting review:**` bullet for check-in `id:mf9gq`.

- [ ] +zil +safety +AI-G @zil ZL6c Reject storing local stack pointers into globals and propagate points_to_stack through Phi in src/verify.zrl id:djynw
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:epx51

    - **Placed:** after `id:epx51` (ZL6b), Rank 3 local stack-pointer escape checks in `src/verify.zrl`.
    - **Do:**
      1. In `src/verify.zrl`, add a per-function `is_global_addr: [mut bool]` array (allocated and zeroed beside `points_to_stack`). Set `is_global_addr[ssa] = true` on `ILInstr.GlobalAddr(_)`, and propagate it through `Cast`, `FieldAddr`, `Add`, `Move`, and `Borrow` (when the source has `is_global_addr`).
      2. In `src/verify.zrl` (`mark_store` / `ILInstr.Store(s)`): if `s.ptr < self.uses.len as u32 && self.is_global_addr[s.ptr as usize]` and `s.val < self.uses.len as u32 && (self.is_stack_slot[s.val as usize] || self.points_to_stack[s.val as usize])`, report `region escape: storing a pointer to local stack storage into a global`.
      3. In `src/verify.zrl` (`verify_instr` for `ILInstr.Phi(phi)`): if any predecessor `pr.val` has `is_stack_slot[pr.val] || points_to_stack[pr.val]`, set `points_to_stack[ssa] = true`.
      4. Add negative ZIL tests under `tests/zilc/` with `// EXPECT:` headers: `stack_escape_global.zil` and `stack_escape_phi.zil`.
      5. Ensure storing a `string_const` / `slice_ptr(string_const)` or heap pointer into a global remains accepted (control).
    - **Checks:**
      - C1 (before): run `timeout -k 5s 30s build/zilc <file> -o /dev/null` on `stack_escape_global.zil` and `stack_escape_phi.zil` before editing `src/verify.zrl`; quote exit code `0` for each.
      - C2 (after): rebuild `build/zoril` and `build/zilc`; `sh scripts/test_zilc_errors.sh` passes all checks including both new tests (quote both `[PASS]` lines).
      - C3 (control): a hand-written ZIL program storing `slice_ptr` of `string_const "ok"` into a global compiles with `build/zilc` (`exit=0`).
      - C4 (take-out): temporarily revert the `is_global_addr` store check in `src/verify.zrl`, rebuild `build/zilc`, and show `sh scripts/test_zilc_errors.sh` fails on `stack_escape_global.zil`; restore and rebuild.
      - C5: `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed` pass on `zil` (quote `Total:` lines and `reject-diff: base verdicts: fresh (no cache)`; note fuzz record is stale for `src/` and `tools/zilc/`).
      - Ends with `**Awaiting review:**` bullet for check-in `id:mf9gq`.

- [ ] +zil +safety +AI-G @zil ZL6d Reject use-after-drop and double-drop in src/verify.zrl id:pkcsy
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:djynw

    - **Placed:** after `id:djynw` (ZL6c), Rank 4 `drop`-lifetime checks in `src/verify.zrl`.
    - **Do:**
      1. In `src/verify.zrl` (`verify_instr` for `ILInstr.Drop(ssa)`): before setting `OwnerState.Dropped`, check `self.current_map.get_state(ssa)`; if it is already `OwnerState.Dropped`, report `double drop: value was already dropped`.
      2. In `src/verify.zrl` (`check_ssa_access(ssa, span)` or on operand reads before `verify_instr`): if `self.current_map.get_state(ssa)` is `OwnerState.Dropped`, report `use after drop: value was already dropped` (avoid duplicate error when the instruction itself is `ILInstr.Drop(ssa)`, which reports `double drop`).
      3. Verify `ILInstr.Store` to a dropped stack slot still resets the slot to `OwnerState.Owned` in `mark_store`, and `corpus/zil/05_ownership_move.zil`, `06_ownership_drop.zil`, `13_slices.zil` still compile cleanly.
      4. Add negative ZIL tests under `tests/zilc/` with `// EXPECT:` headers: `use_after_drop.zil` and `double_drop.zil`.
    - **Checks:**
      - C1 (before): run `timeout -k 5s 30s build/zilc <file> -o /dev/null` on `use_after_drop.zil` and `double_drop.zil` before editing `src/verify.zrl`; quote exit code `0` for each.
      - C2 (after): rebuild `build/zoril` and `build/zilc`; `sh scripts/test_zilc_errors.sh` passes all checks including both new tests (quote both `[PASS]` lines).
      - C3 (control): `./scripts/test.sh corpus/zil` passes all 24 tests including `05_ownership_move.zil`, `06_ownership_drop.zil`, and `13_slices.zil` (quote `Total:`).
      - C4 (take-out): temporarily revert the `OwnerState.Dropped` check in `src/verify.zrl`, rebuild `build/zilc`, and show `sh scripts/test_zilc_errors.sh` fails on `use_after_drop.zil` and `double_drop.zil`; restore and rebuild.
      - C5: `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed` pass on `zil` (quote `Total:` lines and `reject-diff: base verdicts: fresh (no cache)`; note fuzz record is stale for `src/` and `tools/zilc/`).
      - Ends with `**Awaiting review:**` bullet for check-in `id:mf9gq`.

- [ ] +zil +safety +review +AI-D @zil @checkin Check-in: review ZL6 common-mistake checks (0r49n, epx51, djynw, pkcsy) id:mf9gq
    > **Created:** 2026-11-21
    > **Branch:** `zil`
    > **Depends:** id:0r49n, id:epx51, id:djynw, id:pkcsy

    - **Placed:** directly after `id:pkcsy` (ZL6d), the last of the ZL6 `+AI-G` batch, per `AGENTS.md` Check-ins.
    - **Review:** the steps of `AGENTS.md` Check-ins; re-run each task's numbered checks and probe sibling routes (e.g. `slice_load`/`slice_store` on non-slice, variadic call arity, `variant_match` undefined target, `alloc 'local` stored into global field via `field_addr`, `drop` in one branch vs sibling branch).

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
    > **Depends:** id:w3vde, id:0mbg3, id:mf9gq, id:mskex, id:4ngz8, id:r1shp, id:rz4da

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
