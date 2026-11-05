#!/bin/sh
# scripts/mutation-check.sh — does the test suite actually catch miscompiles?
#
# check_test_strength.sh catches tests that CANNOT fail. It cannot tell a strong
# assertion from a weak one: a test asserting `1 == 1` passes it. This answers
# the harder question directly, by breaking the compiler on purpose and checking
# that the suite notices.
#
# For each mutation: apply it to a staged copy of src/, build that compiler, and
# require that the test suite stops at a new failure not in the baseline set. The
# suite fails fast at the first failing test (ordered by cached catching tests under
# build/mutation_cache/ from previous runs, or discovered with a short per-test
# timeout). The report names the first catching test for each mutation. A mutation
# that leaves the failing set unchanged is a coverage hole, reported as SURVIVED.
# The working tree is never modified. Mutants build in parallel batches
# (build/mutation/<id>/; MUTATION_JOBS, default min(CPUs, GB of available memory)), then
# their suites run one after another, each using every CPU.
#
# Comparing failing sets rather than raw exit status ensures a pre-existing or
# baseline failure does not falsely count as catching a mutant. The baseline suite
# must pass cleanly (0 failing tests).
#
# Why this exists. On 2026-09-12 a real miscompile -- `match l { Cons(v) => v }`
# on a &L returning 132 instead of 7 -- passed 471/471 unit tests and the
# self-hosting fixpoint. The fixpoint is blind to wrong answers by construction:
# a deterministic miscompile reproduces itself perfectly, so it proves the
# compiler is a fixed point, not that it is correct. Only value-checking tests
# cover that, and only this measures whether they are doing their job.
#
# Usage:
#   scripts/mutation-check.sh            # all mutations
#   scripts/mutation-check.sh M2         # one mutation by id
#   scripts/mutation-check.sh --changed  # the mutations of files changed since HEAD/upstream
#
# A different list, stage directory or cache may be pointed at for a self-test or a canary:
#   MUTATION_LIST=<file> MUTATION_STAGE=build/<dir> MUTATION_CACHE=build/<dir> scripts/mutation-check.sh
# (`scripts/test_mutation_check.sh` is the canary this harness is guarded by: it runs two
# mutations whose verdicts must be SURVIVED and caught, so the harness cannot silently lose the
# ability to report either - the defect was that every mutant looked caught.)
#
# `scripts/mutation_uncovered.list` holds the mutations this harness deliberately does not run:
# routes only the separate-compilation path reaches (M106, M107 - the task "Let the mutation
# harness cover the separate-compilation (-c / zbuild) path" wires that list in) and mutations no
# program in the tree distinguishes (M85, M112). Each entry says which it is.
# Which paths each class covers: every mutation is run against the per-file suite (single-shot
# compilation). A mutation on the `-c` / interface path is also run against the incremental scenario,
# listed by id in scripts/mutation_incremental.list, and that is the only class that is.
#
# Exit 0 = every mutation was caught. 1 = at least one survived.

set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
. "$REPO/scripts/env.sh"

ONLY="$1"
ROW=""
CHANGED=""
CHANGED_DESC=""
if [ "$ONLY" = "--row" ]; then
    ROW="${2:-}"
    if [ -z "$ROW" ]; then
        echo "usage: mutation-check.sh --row <row-name-fragment>" >&2
        exit 2
    fi
elif [ "$ONLY" = "--changed" ] && [ -n "${MUTATION_BASE:-}" ]; then
    # The base preflight chose (scripts/lib/preflight_base.sh): `git diff BASE` compares it with the
    # working tree, so committed and uncommitted changes since the base are both covered.
    CHANGED=$( (git diff --name-only "$MUTATION_BASE"; git ls-files --others --exclude-standard) | sort -u)
    commits=$(git rev-list --count "$MUTATION_BASE..HEAD" 2>/dev/null || echo 0)
    CHANGED_DESC="$commits commit(s) and the working tree since $(git rev-parse --short "$MUTATION_BASE" 2>/dev/null || echo "$MUTATION_BASE")"
elif [ "$ONLY" = "--changed" ]; then
    CHANGED=$( (git diff --name-only HEAD; git ls-files --others --exclude-standard) | sort -u)
    if [ -n "$CHANGED" ]; then
        CHANGED_DESC="working tree vs HEAD"
    elif git rev-parse --verify @{upstream} >/dev/null 2>&1; then
        upstream=$(git rev-parse --abbrev-ref @{upstream})
        CHANGED=$(git diff --name-only @{upstream} HEAD | sort -u)
        commits=$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo 0)
        CHANGED_DESC="$commits commit(s) since $upstream"
    else
        CHANGED_DESC="no changes vs upstream / HEAD"
    fi
fi

# wanted ID FILE: whether this run covers mutation ID (of FILE).
wanted() {
    if [ -n "${ROW:-}" ]; then
        printf '%s\n' "$ROW_IDS" | grep -qx -- "$1"
        return $?
    fi
    if [ "$ONLY" = "--changed" ]; then
        printf '%s\n' "$CHANGED" | grep -qx -- "$2"
    else
        [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]
    fi
}

# Each mutation: id | file | sed expression | what it breaks
#
# Keep them surgical. A mutation that stops the compiler building tells us
# nothing about test strength -- it is reported separately as BUILD-FAILED.
# Fields are split on every '@' (IFS='@'), so a pattern cannot contain one: target a
# line without it (an `@syscall` check is reached through its `syscall_marked` flag).
mutations() {
    cat <<'MUT'
M1@@src/builder.zrl@@self.emit_bounds_check_against(idx_ssa, len_ssa, usize_ty, bool_ty, u64_ty, i64_ty);@@return;@@Slice bounds check removed entirely
M2@@src/builder.zrl@@ILInstr.CmpLt(ILBinaryOp { lhs: idx_u, rhs: len_ssa })@@ILInstr.CmpLe(ILBinaryOp { lhs: idx_u, rhs: len_ssa })@@Bounds check off-by-one: idx <= len permits index == len
M3@@src/builder.zrl@@field_idx: 1 as u32 }),@@field_idx: 0 as u32 }),@@Bounds check reads the slice DATA POINTER as its length
M4@@src/verify.zrl@@if self.is_stack_slot[res as usize] || self.points_to_stack[res as usize] {@@if false {@@Region-outlives check disabled: dangling stack returns accepted
M5@@src/lower_zir_to_zil.zrl@@BINARY_LT => { return (*self.builder).emit_with_type(ILInstr.CmpLt(b), res_ty); },@@BINARY_LT => { return (*self.builder).emit_with_type(ILInstr.CmpLe(b), res_ty); },@@The `<` operator lowers to <=, so `a < a` is true
M6@@src/lower_zir_to_zil.zrl@@BINARY_GE => { return (*self.builder).emit_with_type(ILInstr.CmpGe(b), res_ty); },@@BINARY_GE => { return (*self.builder).emit_with_type(ILInstr.CmpGt(b), res_ty); },@@The `>=` operator lowers to >, so `a >= a` is false
M7@@src/lower_zir_to_zil.zrl@@(*self.builder).emit_with_type(ILInstr.Mul(b), res_ty),@@(*self.builder).emit_with_type(ILInstr.Add(b), res_ty),@@The `*` operator lowers to addition
M8@@src/lower_zir_to_zil.zrl@@(*self.builder).emit_with_type(ILInstr.Sub(b), res_ty),@@(*self.builder).emit_with_type(ILInstr.Add(b), res_ty),@@The `-` operator lowers to addition
M9@@src/lower_zir_to_zil.zrl@@ILInstr.Mul(ILBinaryOp { lhs: idx_usize, rhs: elem_size_ssa }),@@ILInstr.Add(ILBinaryOp { lhs: idx_usize, rhs: elem_size_ssa }),@@Index scaling adds the element size instead of multiplying
M10@@src/verify.zrl@@self.report_error("arena capacity exceeded at compile time", span);@@@@Compile-time arena capacity check disabled
M11@@src/verify.zrl@@if escapes {@@if false {@@Escape check for values copied out of the frame disabled: structs and slices holding stack pointers can be returned
M13@@src/lower_zir/utils.zrl@@        if self.expr_is_literal_zero(len_expr) { return; }@@        if true { return; }@@Slice forging no longer needs unsafe (any pointer, any length)
M14@@src/check_zir.zrl@@        if place.base > locals.len as u32 {@@        if place.base >= locals.len as u32 {@@The last local of every function is not checked again (off-by-one)
M15@@src/check_zir.zrl@@        if drop_st == OWN_MOVED {@@        if false {@@An explicit drop of a possibly-moved value is accepted (double drop)
M16@@src/check_zir.zrl@@                            res_ref.maybe_live[j] = ml || st1 == OWN_OWNED || st2 == OWN_OWNED;@@                            res_ref.maybe_live[j] = ml;@@A linear resource closed on only one path is accepted (leak)
M17@@src/lower_zir/utils.zrl@@        if (target_tag == ILTYPE_FD || target_tag == ILTYPE_IORING) && cast_src_ty != target_ty {@@        if false {@@A cast can change a file descriptor's capability
M18@@src/driver/module.zrl@@        if s.is_mut && self.static_type_holds_ref(s.ty, ty) {@@        if false {@@A static mut may hold a reference again (dangles after the caller returns)
M19@@src/lower_zir_to_zil.zrl@@        if (op == BINARY_SHL || op == BINARY_SHR) && !self.is_const_temp(rhs.base, 0 as usize) {@@            if false {@@A variable shift count is no longer range-checked at run time
M20@@src/lower_zir/utils.zrl@@        } else if !c.negative && c.value >= width {@@        } else if false {@@A constant shift count >= the width is no longer a compile error
M21@@src/check_zir.zrl@@        if !self.is_live(b.borrower) { return false; }@@@@Borrows no longer end at their last use (back to lexical)
M22@@src/check_zir.zrl@@        if dest == 0 as u32 || !self.local_holds_reference(dest, locals) { return; }@@        return;@@A call's result no longer keeps its arguments borrowed
M24@@src/verify.zrl@@        if func.has_borrows { self.check_borrows_claim(func); }@@@@A #[borrows] claim is no longer checked against the body
M25@@src/check_zir.zrl@@                            last_was_readonly = !p_sl.def.get_Slice().mutable;@@                            last_was_readonly = false;@@A read-only slice can be written through
M26@@src/lower_zir/utils.zrl@@            if p_ty_exp.def.get_Slice().mutable && !p_ty_act.def.get_Slice().mutable {@@            if false {@@A [T] is accepted where a [mut T] is expected
M27@@src/verify.zrl@@        self.tie_call_result_storage(p_f, args, ssa);@@@@A result pointing into a stack argument's own storage is no longer tied to it
M28@@src/verify.zrl@@        self.check_call_stores_stack(p_f, args, span);@@@@A callee storing a stack argument away is no longer checked
M29@@src/verify.zrl@@        fl.reach[ssa as usize] = fl.reach[src as usize];@@        fl.reach[ssa as usize] = fl.reach[src as usize]; fl.mask[ssa as usize] = fl.mask[ssa as usize] | fl.mask[src as usize];@@A value loaded through a parameter counts as pointing into its storage
M30@@src/verify.zrl@@        if self.is_slice_like(param_ty) {@@        if false {@@A slice or function-value argument counts as stack because its slot is, wherever it points
M31@@src/lower_zir_to_zil.zrl@@            if kind == 1 as u32 && !self.is_aggregate(ty) {@@            if false {@@A reference to a temporary value is the value itself again
M32@@src/builder.zrl@@        self.emit(ILInstr.Unreachable);@@        self.emit(ILInstr.Jmp(ok_block));@@A failed check jumps back into the in-bounds path again
M33@@src/lower_zir/expr.zrl@@        if count > ZirLowerer.ARRAY_REPEAT_UNROLL_MAX {@@        if false {@@An array repeat is unrolled into one store per element again
M34@@src/lower_zir/exhaust.zrl@@            } else if k == EXH_KIND_CTOR && hc == c {@@            } else if k == EXH_KIND_CTOR {@@Exhaustiveness counts any constructor as covering every other
M35@@src/lower_zir/expr.zrl@@        if !base_is_raw && pointee != 0 as u32 {@@        if false {@@A reference is indexed as a raw pointer again
M36@@src/check_zir.zrl@@                self.check_places_moved(elems, span, state, locals);@@                // self.check_places_moved(elems, span, state, locals);@@Tuple and array literals no longer check their elements were not moved
M37@@src/check_zir.zrl@@                for e in elems { self.inherit_borrows_keeping(e.base, dest, rv_bit(rv), state); }@@                for e in elems { self.inherit_borrows(e.base, dest, state, locals); }@@A tuple or array literal no longer keeps its elements' borrows
M38@@src/il_cfg.zrl@@                p_decl.def.get_Array().element,@@                0 as u32,@@An array of references is no longer seen to hold a reference, so a collection from a reference-taking constructor (Vec::new_in(&arena)) is not tied to it and the arena can be destroyed while the collection is live. The walk moved to src/il_cfg.zrl with the helper task (2026-10-12), which is why this mutation's file changed
M39@@src/lower_zir/utils.zrl@@            && self.is_float_type(expected) == self.is_float_type(actual)@@            && true@@A float and a same-size integer are the same type to `let` again (the bits are reinterpreted)
M40@@src/mono.zrl@@                && p_func.source_file == imp.source_file {@@                && true {@@A method instance is reused by name across modules: another module's same-named type's method is called
M41@@src/resolve.zrl@@        rr.check_impl_items_unique();@@@@A method defined twice for one type is accepted, one silently dropped
M42@@src/lower_zir/utils.zrl@@                    if type_decl != 0 as u32 && impl_decl != 0 as u32 && type_decl != impl_decl {@@                    if false {@@An impl is matched to a receiver by its type's name alone, so another module's same-named type's impl is used
M43@@src/lower_zir/expr.zrl@@                if ai < sig.params.len {@@                if false {@@A call through a function pointer no longer checks its arguments' types
M44@@src/lower_zir/decl.zrl@@        if actual_ret_ty == 0 as u32 && ret_place.base != 0 as u32 {@@        if false {@@A body's value is silently dropped when the function declares no result type
M45@@src/lower_zir/expr.zrl@@        if (i.args.len as i64) < min_args || (i.args.len as i64) > max_args {@@        if false {@@An intrinsic given too few arguments crashes the compiler again
M46@@src/resolve.zrl@@        rr.check_type_cycles();@@@@A type containing itself by value is accepted again
M47@@src/lower_zir/expr.zrl@@            if given[idx as usize] {@@            if false {@@A struct literal may give a field twice again
M48@@src/lower_zir/expr.zrl@@                v = self.emit_cast(v, field_ty, span);@@                v = v;@@A struct field value is no longer converted to the field's type
M49@@src/lower_zir/utils.zrl@@            Expr.Cast(c) => { self.collect_free_idents_expr(c.expr, params, out); },@@            Expr.Cast(c) => {},@@A closure use of a local inside a cast is no longer captured
M50@@src/lower_zir/expr.zrl@@        if self.implicit_conv_ok(rt, lt) { return (self.emit_cast(lhs, rt, span), rhs); }@@        if self.implicit_conv_ok(rt, lt) { return (lhs, self.emit_cast(rhs, lt, span)); }@@Mixed-width operands are narrowed to the left one again
M51@@src/resolve.zrl@@                SymbolKind.AssocConst(packed),@@                SymbolKind.Method(packed),@@Impl constants share the method symbol kind again
M52@@src/lower_zir/expr.zrl@@            if !self.int_fits(val_u64, negated, ty) {@@            if false {@@An integer literal is no longer checked against its type
M53@@src/parser/expr.zrl@@        self.quiet = true;@@        self.quiet = false;@@A speculative type-argument parse reports its errors again (`a < (b << c)` fails to parse)
M54@@src/driver/types.zrl@@                                if !self.type_has_impl_for_trait(@@                                if false && !self.type_has_impl_for_trait(@@An impl's trait type argument no longer has to meet the parameter's bound
M55@@src/resolve.zrl@@                if !known {@@                if false {@@An unknown name in a declaration's types resolves to no type again, silently
M56@@src/il_cfg.zrl@@            if p.by_ref { m.types[p.ty as usize - 1 as usize].def.get_Ptr() } else { p.ty }@@            p.ty@@A function's fn type lists the ABI's pointer for an aggregate parameter again
M57@@src/lower_zir/exhaust.zrl@@            if !self.exh_useful(&rows, q, tys, 0 as usize) {@@            if false {@@An unreachable match arm is accepted silently again
M58@@src/lower_zir/exhaust.zrl@@        if lint_enabled(LINT_WILDCARD_ARM) && !m.desugared { self.lint_wildcard_arm(m, ty); }@@@@A `_` arm standing for few enum variants is accepted silently again
M59@@src/resolve.zrl@@            if target != 0 as u32 {@@            if false {@@A qualified name `ns::item` no longer finds the item of the module imported as `ns`
M60@@src/resolve.zrl@@            if prev != 0 as u32 && prev != e.to_module {@@            if false {@@Two imports with one file stem are accepted again, the second silently replacing the first
M61@@src/resolve.zrl@@                if !self.symbol_is_pub(sym) { problem = "it is private: `"; }@@@@A `use` of a private item is accepted again
M62@@src/resolve.zrl@@                        if used_from != 0 as u32 && m == used_from {@@                        if false {@@A name a `use` brings in is no longer preferred over another module's public item of that name
M63@@src/resolve.zrl@@            if module != 0 as u32 {@@            if false {@@A bare name finds any module's public item again, without an import and a `use`
M64@@src/lower_zir/lower_match.zrl@@                        if self.resolver.names_hidden_constant(name) {@@                        if false {@@A pattern naming a constant of another module that is not in scope silently binds a new variable again
M65@@src/resolve.zrl@@                            self.report_unknown_type(ty_id, path.0);@@@@An unknown type name in a function body (a let, a cast, a type argument) is no longer reported
M66@@src/fmt/doc.zrl@@const INDENT_STEP: usize = 4;@@const INDENT_STEP: usize = 2;@@Formatter indentation steps by 2 spaces instead of 4
M67@@src/fmt/doc.zrl@@pub const LINE_WIDTH: usize = 100;@@pub const LINE_WIDTH: usize = 40;@@Formatter line width wraps at 40 columns instead of 100
M68@@src/lower_zir/stmt.zrl@@        self.lower_expr(f.body, 0 as u32);@@        self.lower_expr(f.body, self.current_ret_ty);@@A for range loop lowers its body expecting the function return type again
M69@@src/lower_zir/utils.zrl@@        if !self.place_is_raw_ptr(pl) { return; }@@        return;@@`p.field`, `p.0` and `p.method()` on a raw pointer no longer need unsafe
M70@@src/lower_zir/expr.zrl@@        self.check_cast_validity(&c, &inner_place, target_ty, span);@@        self.check_cast_validity(&c, &inner_place, target_ty, span); if self.unsafe_depth == 0 as u32 && self.resolver.is_raw_ptr_type(c.target_ty) && self.int_prim_bits(self.get_place_type(&inner_place)) != 0 as u32 && !self.expr_is_literal_zero(c.expr) { self.report_error("casting an integer to a raw pointer requires unsafe block", span); }@@The gate on an integer-to-raw-pointer cast is restored - the removed `check_int_to_raw_ptr_is_marked` rule, put back at the cast site - so the accepted twins stop compiling: tests/functional/pointers/int_to_raw_ptr_cast.zrl and tests/language/other/static_initializer_fixed_address.zrl, and probe 122 flips back to compile_reject. The dereference half of the rule is untouched, which is why probe 13 and the raw-dereference error tests still pass under the mutant. The harness reports whichever test notices first (bitcast_usize, another program whose redundant marker this change removed); the four twins above were checked by hand against the mutant and all four are rejected at the cast
M71@@src/lower_zir/utils.zrl@@        if !self.place_is_raw_ptr(arg) { return; }@@        if false { return; }@@A raw pointer passed as a reference argument no longer needs unsafe. (Retargeted when Phase D step 4 removed the `param.is_raw_ptr` clause from the condition above: the type decides it now, and this is the line that still reports.)
M72@@src/lower_zir/utils.zrl@@        if !self.place_is_raw_ptr(value) { return; }@@        if false { return; }@@A raw pointer stored or returned where a reference is expected no longer needs unsafe. (Retargeted with M71, for the same reason: step 4 deleted the `target_is_raw` argument it used to carry.)
M74@@src/lower_zir/expr.zrl@@        let syscall_marked = self.unsafe_depth > 0 as u32;@@        let syscall_marked = true;@@A system call no longer needs unsafe
M75@@src/lower_zir/expr.zrl@@        let alloca_marked = self.unsafe_depth > 0 as u32;@@        let alloca_marked = true;@@An uninitialized alloca slot no longer needs unsafe
M76@@src/lower_zir/expr.zrl@@        if base_is_raw && self.unsafe_depth == 0 as u32 {@@        if false && self.unsafe_depth == 0 as u32 {@@Indexing a raw pointer (`p[i]`, and `&p[i]` through the same lowering) no longer needs unsafe, so safe code reads or writes the address a `*T` names: probe 133_raw_ptr_index_borrow and tests/error_reporting/err_raw_ptr_index_borrow.zrl stop being compile errors
M77@@src/check_zir.zrl@@        self.inherit_borrows_keeping(p.base, dest, via, state);@@        if false { self.inherit_borrows_keeping(p.base, dest, via, state); }@@A reborrow no longer inherits the base local's borrows
M81@@src/verify.zrl@@            let is_boxed = val_tag == ILTYPE_BOXED || val_tag == ILTYPE_BOXEDMUT;@@            let is_boxed = false;@@A reference into an owned box dropped at return is no longer tracked
M82@@src/check_zir.zrl@@                    self.inherit_borrows_captured(env_ptr, dest, rv_bit(rv), state, locals);@@                    if false { self.inherit_borrows_captured(env_ptr, dest, rv_bit(rv), state, locals); }@@A closure value no longer inherits borrows of captured references
M83@@stdlib/mem.zrl@@unsafe { arena_free(self.header); }@@unsafe { arena_free(self.header); arena_free(self.header); }@@Drop for Arena double-frees the arena mapping
M84@@src/il_cfg.zrl@@                    if self.holds_reference_inner(f.ty, depth + 1 as usize, pointers_count) {@@                    if false {@@A struct holding a reference is no longer seen to, so a collection from a reference-taking constructor (Vec::new_in(&arena)) is not tied to it and the arena can be reset or destroyed while the collection is live. The walk moved to src/il_cfg.zrl with the helper task (2026-10-12), which is why this mutation's file changed
M86@@src/il_cfg.zrl@@        if is_reference_tag(tag) || tag == ILTYPE_FN { return true; }@@        if tag == ILTYPE_FN { return true; }@@A pointer or reference *type* is no longer seen to hold a reference at all, so a borrow is not followed through one (the pointer half of the policy, which asks by name since the merge; `is_shared_pointer_tag` here would need an import that only the mutant uses)
M88@@src/check_zir.zrl@@        if local_id == 0 as u32 { return; }@@        if true { return; }@@The block-scope check bails out for every local, so a value going out of scope while a live borrower outlives it is accepted again: the arena, reference, Box, loop, if-arm and match-arm error tests all fail to compile without it
M89@@src/lower_zir/expr.zrl@@        self.pop_scope_exclude(b.end_span, res.base, false);@@        self.pop_scope_exclude(Span { start: 0, end: 0, line: 0, col: 0 }, res.base, false);@@The scope-exit marker goes back to the zero span the parser used to leave (a block's end is not recorded there), so "cannot let ... go out of scope" prints at 0:0 again and the six located EXPECT lines in the err_block_scope_borrow_* tests stop matching
M126@@src/lower_zir/utils.zrl@@            exists = field_name == ptr_id || field_name == data_id || field_name == len_id;@@                exists = true;@@A slice answers "that field exists" for every name, so an unknown field falls through to the sentinel 0xffffffff, which the ZIL uses as a real field index - a read at a garbage offset from safe code. Caught by tests/error_reporting/err_unknown_field_on_slice.zrl.
M124@@src/parser/module.zrl@@            if st.require_interface {@@            if false {@@`--require-interface` is ignored, so an import with no interface falls back to its source - the silent behaviour the flag exists to remove. Caught by test 50 of scripts/test_incremental.sh, which expects the located no-interface error.
M85@@src/il_cfg.zrl@@        let past_limit = depth > 8 as usize;@@        let past_limit = depth > 2 as usize;@@The reference-holding walk gives up two levels deep, so every type nested deeper answers "it might hold a reference" and a result gets tied to parameters it does not borrow. Caught by tests/language/memory/reference_free_result_not_tied_to_parameter.zrl (five struct levels).
M90@@src/check_zir.zrl@@!own_storage,@@true,@@The storage summary is ignored: every call-derived borrow counts as one of what the argument references again, so id(&x) is no longer caught by err_block_scope_borrow_returned_arg and err_block_scope_borrow_self_field
M92@@stdlib/mem_raw.zrl@@pub unsafe fn zoril_allocator_alloc(arena: *mut ArenaHeader, size: u64) -> *mut u8 {@@pub fn zoril_allocator_alloc(arena: *mut ArenaHeader, size: u64) -> *mut u8 {@@The allocator primitive no longer demands `unsafe`, so safe code can hand it a pointer of its choosing again: err_allocator_raw_call_outside_unsafe and probe 127_safe_fn_derefs_raw_pointer_argument stop being compile errors (the wrapped internal call sites still build, since a redundant `unsafe` block is accepted)
M87@@src/il_cfg.zrl@@                            v.payload,@@                            0 as u32,@@An enum holding a reference is no longer seen to, so a result that is an enum with a slice payload (read_file, list_dir, env_var) is not tied to the arena it was read through, while a struct or a reference result still is. The walk moved to src/il_cfg.zrl with the helper task (2026-10-12), which is why this mutation's file changed
M93@@src/check_zir.zrl@@            if self.borrow_counts(b, state, locals) && self.places_overlap(place, &b.base) {@@            if !(b.derived && self.is_temp_local(b.borrower, locals)) && self.places_overlap(place, &b.base) {@@A borrow held by a named local constrains moves until the end of its scope again instead of to its last use, so tests/language/memory/borrow_named_local_ends_at_last_use.zrl is rejected again with "cannot move borrowed value 'a'"
M94@@stdlib/args.zrl@@    pub unsafe fn new(argc: i32, argv: **u8) -> Args {@@    pub fn new(argc: i32, argv: **u8) -> Args {@@`Args.new` no longer demands `unsafe`, so safe code can hand `Args` a pointer of its choosing again: tests/error_reporting/err_args_new_outside_unsafe.zrl stops being a compile error and probe 160_args_raw_pointer_argument.zrl stops being a compile_reject probe
M95@@src/check_zir.zrl@@                if self.type_has_drop(fields[i].ty, depth + 1 as usize) { return true; }@@                if false { return true; }@@The scope-end rule stops following a value's struct fields, so a struct holding an `Arena` reads as freeing nothing again: err_block_scope_borrow_struct_arena_derived.zrl is accepted, and the derived borrow outlives the unmapped region
M96@@src/driver/module.zrl@@            storage_known: f.has_storage@@            storage_known: true || f.has_storage@@A body's storage masks read as known before its ZIR has been read, so a self-recursive call reads "hands back nothing" instead of unknown: err_block_scope_borrow_recursion_cycle.zrl and probe 167_recursion_cycle_storage_unknown.zrl are accepted, and the reference outlives the local's stack slot
M101@@src/check_zir.zrl@@self.inherit_borrows_as(a.base, dest, rv_bit(rv), state, false, locals);@@self.inherit_borrows_as(a.base, dest, rv_bit(rv), state, true, locals);@@A call through a function value reads its result as derived again, so the borrow of the argument is exempt at the local's scope end: err_block_scope_borrow_call_through_value.zrl and probe 171 are accepted
M102@@src/check_zir.zrl@@                for a in args { self.inherit_borrows_keeping(a.base, dest, rv_bit(rv), state); }@@                for a in args { self.inherit_borrows(a.base, dest, state, locals); }@@A value built from an operand forces its inherited borrow back to derived, so a struct literal holding `&x` is exempt at `x`'s scope end: err_block_scope_borrow_aggregate_ref_field.zrl and probe 172 are accepted
M103@@src/check_zir.zrl@@                    self.inherit_borrows_captured(env_ptr, dest, rv_bit(rv), state, locals);@@                    self.inherit_borrows(env_ptr, dest, state, locals);@@A closure's environment forces its captures' borrows back to derived, so a closure that captured a reference to a local is exempt at that local's scope end again: err_block_scope_borrow_closure_capture.zrl and probe 173 are accepted, and calling the closure reads the dead slot (8)
M104@@src/check_zir.zrl@@        self.inherit_borrows_keeping(p.base, dest, via, state);@@        self.inherit_borrows(p.base, dest, state, locals);@@A pointer taken to a place forces that place's borrows back to derived, which is the first step of the closure chain: err_block_scope_borrow_closure_capture.zrl and probe 173 are accepted (the environment inherits the capture's borrow as derived, and the closure inherits it from there)
M105@@src/il_cfg.zrl@@        if past_limit { return true; }@@        if past_limit { return false; }@@The reference question answers "cannot hold a reference" past its recursion limit again, so a borrow is not propagated out of a deeply nested value: err_block_scope_borrow_deep_reference.zrl and probe 174 are accepted, and the reference outlives the local's stack slot (7). One site now (src/il_cfg.zrl, the helper task of 2026-10-12) instead of the three copies this used to name
M108@@src/check_zir.zrl@@        if past_limit_drop { return true; }@@        if past_limit_drop { return false; }@@The scope-end rule's "does this type free storage" question answers "frees nothing" past its recursion limit again, so a derived borrow outliving a value whose `Drop` field sits past the limit is exempt: err_block_scope_borrow_deep_arena_derived.zrl is accepted, and the program reads the unmapped arena (139)
M109@@src/check_zir.zrl@@        if past_limit_copy { return false; }@@        if past_limit_copy { return true; }@@The ZIR checker's copy question answers "`Copy`" past its recursion limit again, so a use of a deeply nested value is not a move and a second use of it is accepted - and a second copy of a value the (now precise) drop walk frees is freed too: probe 176 and err_move_deep_type_after_move.zrl are accepted, and a program built of that shape drops its arena twice and dies with 139
M110@@src/lower_zir/utils.zrl@@        if past_limit_copy { return false; }@@        if past_limit_copy { return true; }@@The lowerer's copy question answers "`Copy`" past its limit again, so `Local.is_copy` is set for a deeply nested non-`Copy` value: no drop is emitted for it at all and it is never freed - tests/language/structs/test_drop_glue_deep.zrl reports 0 drops where it requires 1
M111@@src/driver/state.zrl@@        if past_limit_copy { return false; }@@        if past_limit_copy { return true; }@@The driver's copy question answers "`Copy`" past its limit again (the copy the inventory had missed is the lowerer's `Local.is_copy`; this one decides the driver's own uses of the predicate)
M113@@src/lower_zir/utils.zrl@@        if absent_type { return false; }@@        if absent_type || depth > 10 as usize { return false; }@@The ZIR drop question answers "needs no drop" past ten levels again, so a deeply nested `Drop` value gets no drop flag and a conditional move of it leaks on the path where the move did not happen (and a partial move or an `[v; n]` of such a value is accepted): tests/language/structs/test_drop_glue_deep.zrl reports 0 drops where it requires 1
M114@@src/lower_zir_to_zil.zrl@@        if absent_type { return false; }@@        if absent_type || depth > 10 as usize { return false; }@@The drop glue answers "needs no drop" past ten levels again, so the deepest field's own `drop` is never called for a deeply nested value and its storage is never freed: tests/language/structs/test_drop_glue_deep.zrl reports 0 drops where it requires 1, and the arena loop that exercises it dies at iteration ~126
M115@@src/check_zir.zrl@@        if absent_type { return false; }@@        if absent_type || depth > 8 as usize { return false; }@@The linear walk answers "holds no linear resource" past eight levels again, so an `fd` nested deeper than that is dropped without complaint and leaks: probe 177_deep_fd_leak_rejected.zrl and err_linear_deep_fd_leak.zrl are accepted
M116@@src/check_zir.zrl@@            if *v == ty_id { return true; }@@            if false { return true; }@@The linear walk no longer recognises a type it has already entered, so a recursive type's walk never terminates and the compiler overflows its stack on any linked list (the corpus, tests/language/generics, the stdlib)
M117@@stdlib/sys.zrl@@    return ret < 0 as i64 && ret > -4096 as i64;@@    return ret < 0 as i64 && ret > -2 as i64;@@`syscall_failed` recognises only -1 again - the libc `MAP_FAILED` convention rather than the kernel's -errno range - so a failed mmap (ENOMEM is -12) is read as a mapping: tests/stdlib/test_stdlib_mmap_failure_traps.zrl dies with 139 instead of panicking, and the fixture's own wrapper builds an arena around the forged pointer and exits 0 (tests/stdlib/test_stdlib_local_mem_mmap_failure_traps.zrl)
M118@@src/lower_zir/utils.zrl@@        let both_ref = (tag_exp == ILTYPE_PTR || tag_exp == ILTYPE_PTRMUT)@@        let both_ref = (tag_exp == ILTYPE_PTR || tag_exp == ILTYPE_PTRMUT || tag_exp == ILTYPE_BOXED || tag_exp == ILTYPE_BOXEDMUT)@@A reference stands in for an owned `Box<T>` again (the expected side of the four-tag class): the callee frees memory it does not own, which is what `fn consume(b: Box<Arena>)` called as `consume(&a)` did before the fix - the mutant builds and the error tests that pin the rejection stop reporting it.
M119@@src/check_zir.zrl@@        let assigning_the_binding = place.projections.len == 0 as usize;@@        let assigning_the_binding = true;@@A write through a reference ends the borrow that reference itself holds again (the guard is gone), so a shared borrow is accepted while the `&mut` goes on being used - the hole the fuzzer found first; the error tests pin the rejection.
M120@@src/check_zir.zrl@@        let dropping_the_binding = place.projections.len == 0 as usize;@@        let dropping_the_binding = true;@@A drop of a projected place is recorded against the pointer local again, so the live `&mut` stops counting as a borrow and a value can be moved out of itself - the use after free the owning-type tests pin (`err_self_move_through_mut_ref_arena` exits 139 without the guard).
M121@@src/lower_zir/utils.zrl@@        let mut is_raw = is_raw_pointer_tag(self.get_type_tag(curr_ty));@@        let mut is_raw = false;@@A place that is the raw pointer itself is no longer raw, because the walk takes the type of a *projection* result but not of the local it starts from - so `*p` through a `*mut u32` local is accepted in safe code. Caught by the raw-dereference error tests and probes.
M122@@src/lower_zir/utils.zrl@@        let mutability_ok = !(@@        let mutability_ok = true || !(@@The mutability test inside a pointer class is disabled again, so a shared reference, raw pointer or box stands where a mutable one is expected - the pair the conversion audit of safety_model.md §5.8 removed, pinned by the three err_shared_* error tests.
M127@@src/lower_zir/expr.zrl@@            if !self.check_method_visible(m_decl.is_pub, m_sf, m.member, span) {@@            if !self.check_method_visible(true, m_sf, m.member, span) {@@A method call on a receiver no longer consults `pub`, so a private method of another module is callable from anywhere again (`t.secret()`): the err_private_* / err_method_body_missing_import error tests stop being compile errors, and probe 29 of scripts/test_safety_matrix_cross_module.sh is accepted - the encapsulation hole the task of 2026-10-13 closed.
M128@@src/driver/module.zrl@@        if !self.compile_only && !self.had_error {@@        if false {@@A method nothing calls is no longer checked in whole-program mode, which is demand-driven lowering again: the body is never lowered, so a field, name, privacy or borrow error in it goes unreported until someone calls the method. Caught by tests/error_reporting/err_uncalled_method_{checks,borrow,private_call}.zrl and by step 3 of scripts/test_uncalled_method_emit.sh (the emission half of the rule still holds under this mutant, which is the point: it is the check that the mutant removes).
M129@@src/mono.zrl@@        return !self.target_names_param(imp.target_ty, imp.source_file);@@        return match self.resolver.ast.types[imp.target_ty as usize] { Type.Path(path) => path.1.len == 0 as usize, Type.Primitive(_) => true, _ => false };@@An impl's target is read as one the check phase can resolve only when it is written with no arguments, the test the uncalled-method rule used before it learned to tell `impl W<i32>` from `impl<T> W<T>`: a method nothing calls of a concrete specialisation is unchecked again, so tests/error_reporting/err_uncalled_specialization_method_checks.zrl compiles and step 4 of scripts/test_uncalled_method_emit.sh loses its broken-body control (its two ZIL greps still pass, which is the point of that control: not being emitted is what an unchecked body looks like too).
M130@@src/driver/module.zrl@@        if !self.check_global_initializer(value, ty, form, span, &cv) {@@        if false && !self.check_global_initializer(value, ty, form, span, &cv) {@@A static's or constant's initializer is no longer checked against its declared type, so `static P: Big = 7` compiles again and its 24-byte image holds 7 in the first 8 bytes and compiler heap in the rest: err_static_init_type_mismatch.zrl, err_static_init_string_length.zrl and err_const_init_unsupported_expr.zrl stop being compile errors
M131@@src/driver/module.zrl@@        let alloc_size = if ty_size == 0 as usize { 8 as usize } else { ty_size };@@        let alloc_size = 8 as usize;@@A global's image is allocated 8 bytes whatever its type's size, which is the leak the static-initializer task fixed: a wider type's image reads the compiler's heap past the 8 bytes it owns, so `static MIXED: Mixed = Mixed.A` (16 bytes) emits heap pointers after its tag and two compiles of one source disagree. Caught by scripts/check_static_image_determinism.sh, which the harness runs against the mutant like perf-gate and fmt-check (the per-file suite cannot pin it: what a garbage byte reads as at run time depends on the byte)
M132@@src/lower_zir/utils.zrl@@        return !(is_raw_pointer_tag(tag) || tag == ILTYPE_PRIMITIVE);@@        return true;@@Every creation an intrinsic makes needs `unsafe` again, whatever it produces - a raw pointer, a number or the default `&mut u8`: `@ptr_from_int<*u8>(n)`, `@ptr_cast<*T>(p)` and `@int_cast<u32>(x)` in safe code stop being accepted (tests/language/pointers/ptr_cast_and_int_cast.zrl). The decision the mutant removes is the result-type half of the integer-to-raw-pointer task: only a reference or a slice result is a forge. The harness reports whichever test notices first (err_arena_oom_compile_time, whose stdlib/local_mem.zrl fixture creates a raw pointer in the safe arena_init); the four tests this mutation is about - tests/language/pointers/ptr_cast_and_int_cast.zrl, tests/functional/structs/struct_dependency.zrl, tests/functional/test_saturating_region.zrl and tests/language/other/test_option_ptr.zrl - were checked by hand against the mutant and all four are rejected
M133@@src/check_zir.zrl@@                let is_direct = b.direct;@@                let is_direct = true;@@Every inherited borrow reads as direct again - the lenient answer the old type-equality guess gave a same-type indirect borrow - so a reference handed back through a call that points into a *different* local of the same type is exempted at that local's scope end: probe 220_same_type_borrow_loop_escape.zrl (a Link whose prev points at a loop-local Link) compiles and reads the next iteration's value. Probes 211, 212, 92, 98, 101 and 44 stay rejected under this mutant; 220 is the probe that pins the provenance
M134@@src/driver/module.zrl@@        if self.os_pending.len() > pending_start { self.os_fixpoint(pending_start); }@@        if false { self.os_fixpoint(pending_start); }@@A recursive cycle's summaries are never iterated or its bodies checked: a member that only calls a body still being lowered keeps an empty store summary, so under --provenance a frame view handed into the cycle is accepted (tests/language/memory/provenance/cycle_fixpoint_refused.zrl, Z-0059)
M135@@src/check_zir.zrl@@            if pty != 0 as u32 && is_any_pointer_tag(os_type_def_tag(module, pty)) {@@            if false {@@A `match` on a reference reads its payload's address as the reference's own slot again (`Frame(self)`), not as what the reference holds, so under --provenance an accessor returning a binding of `match self` on a `&E` parameter is refused by the return rule (tests/language/memory/provenance/match_through_ref_accepted.zrl, Z-0061)
M136@@src/check_zir.zrl@@        c.buf[d + k] = c.buf[d + k] & !(c.buf[s + k] & !c.buf[o + k]);@@        c.buf[d + k] = c.buf[d + k];@@A value stored by value keeps the storage it owns as frame addresses again: under --provenance `v.push(Vec.new())` into a caller's Vec is refused by the call store rule, and a builder returning the Vec it pushed a fresh owner into by the return rule (tests/language/memory/provenance/push_owning_element_accepted.zrl, Z-0062)
M137@@src/check_zir.zrl@@        c.buf[d + k] = c.buf[d + k] & !(c.buf[s + k] & !c.buf[o + k]);@@        c.buf[d + k] = c.buf[d + k] & !c.buf[s + k];@@A moved value drops every Frame it owns, also one it holds an address into: a Vec in a by-value Arena parameter holds Frame(a) in both sets and no other Frame, so under --provenance pushing it into a caller's Vec is accepted (tests/language/memory/provenance/push_param_arena_vec_refused.zrl, Z-0062; a local arena's Vec also holds the arena's own storage Frame, so push_arena_vec_refused.zrl stays refused under this mutant)
M138@@src/check_zir.zrl@@            os_add_flag(c, vo, ORIGIN_RAW);@@            os_add_flag(c, vo, ORIGIN_UNKNOWN);@@An address made by `@ptr_from_int` is Unknown again, which the rules refuse: under --provenance a box holding one cannot be returned (tests/language/memory/provenance/raw_ptr_return_accepted.zrl, `arena_init`, Z-0063)
M139@@src/check_zir.zrl@@        ZirRvalue.Syscall(_) => {},@@        ZirRvalue.Syscall(args) => { for a in args { let _ = os_read(c, module, locals, a, vo, vs); } },@@A system call's result carries its arguments' origins again: under --provenance a result returned after passing a frame buffer's address is refused by the return rule (tests/language/memory/provenance/syscall_result_accepted.zrl, `raw_open`, Z-0063)
M140@@src/driver/module.zrl@@        let rules = self.provenance;@@        let rules = if self.module.functions[self.builder.current_func_idx as usize].is_unsafe { check_zir::PROVENANCE_OFF } else { self.provenance };@@Every `unsafe fn` body is exempt from the rules again: under --provenance gap_47's program with an `unsafe` storer compiles and reads a freed arena (tests/language/memory/provenance/unsafe_fn_body_checked_refused.zrl, Z-0063)
M141@@src/check_zir.zrl@@    let mut flags = c.buf[r + OS_W_FLAGS] & (ORIGIN_STATIC | ORIGIN_RAW);@@    let mut flags = c.buf[r + OS_W_FLAGS] & ORIGIN_STATIC;@@A callee's summary drops Raw from its result: under --provenance a caller stores a frame address through the raw pointer it returned, unrefused by the store rule (tests/language/memory/provenance/raw_return_store_through_refused.zrl, Z-0063)
M142@@src/check_zir.zrl@@                } else if elem != 0 as u32 && !idx_mut {@@                } else if false {@@An index into a Vec loses its type again: a field read after it adds Unknown, so under --provenance an accessor returning `self.module.types[i].def` is refused by the return rule (tests/language/memory/provenance/vec_index_field_accepted.zrl, `Monomorphizer.instance_type_args`, Z-0068)
M143@@src/check_zir.zrl@@                } else if !idx_ptr {@@                } else {@@An index through a raw pointer loses its type again: a field address after it adds Unknown, so under --provenance `&self.e[i].v` returned is refused by the return rule (tests/language/memory/provenance/rawptr_index_field_accepted.zrl, `HashMap.get`, Z-0068)
MUT
}

printf 'Mutation testing: break the compiler, require the suite to notice.\n\n'

make build/zoril build/zilc build/runtime.o >build/mutation-make.log 2>&1 || { cat build/mutation-make.log >&2; echo "build/zoril does not build; fix that first."; exit 2; }
# The stage is wiped on every run, so a caller-provided one has to stay under build/.
STAGE="${MUTATION_STAGE:-build/mutation}"
case "$STAGE" in
    build/*) ;;
    *) echo "MUTATION_STAGE must be under build/ (got: $STAGE)" >&2; exit 2 ;;
esac
MUTATION_CACHE="${MUTATION_CACHE:-build/mutation_cache}"

current_toolchain_stamp() {
    _commit=$(git rev-parse HEAD 2>/dev/null || ./scripts/version.sh 2>/dev/null || echo "no-commit")
    _hashes=""
    for _b in build/zoril build/zilc build/runtime.o; do
        if [ -f "$_b" ]; then
            _h=$(sha256_of "$_b" 2>/dev/null | cut -d' ' -f1)
            _hashes="${_hashes}:${_h}"
        fi
    done
    printf '%s%s' "$_commit" "$_hashes"
}

CUR_STAMP=$(current_toolchain_stamp)
if [ -d "$STAGE" ]; then
    OLD_STAMP=$(cat "$STAGE/stamp" 2>/dev/null || true)
    if [ -n "$OLD_STAMP" ] && [ "$OLD_STAMP" != "$CUR_STAMP" ]; then
        rm -rf "$STAGE"
        rm -rf "$MUTATION_CACHE"
    elif [ ! -f "$STAGE/stamp" ]; then
        rm -rf "$STAGE"
    fi
fi

mkdir -p "$STAGE"
# Reset per-run result files: an early exit (e.g. from a surviving mutant) leaves survivors/stale
# behind, which a subsequent run must not falsely report (Z-0069). Cached mutant builds stay.
rm -f "$STAGE/survivors" "$STAGE/stale"
rm -f "$STAGE"/*/caught_by "$STAGE"/*/incremental_passed
printf '%s\n' "$CUR_STAMP" > "$STAGE/stamp"
# Mutants are built by a saved copy of the unmutated compiler.
GOOD="$STAGE/zoril-good"
cp build/zoril "$GOOD"

MUTATION_TIMEOUT="${MUTATION_TIMEOUT:-20}"

# suite_failures COMPILER WORKDIR [MUTANT_ID] — find the first failing test of the mutant.
# If a previous catching test was cached in $MUTATION_CACHE/MUTANT_ID, it runs that test
# first (fast path). Otherwise, it runs the per-file suite with --fail-fast and a short
# timeout (default 5s) to stop at the first new failure. If all per-file tests pass,
# it runs perf-gate, fmt-check and static-image to catch performance, formatting or
# nondeterministic-data regressions.
suite_failures() {
    _cc="$1"
    _work="$2"
    _id="${3:-}"
    mkdir -p "$_work"
    rm -f "$_work/results" "$_work/fails"
    touch "$_work/fails"

    # Use the mutant's stdlib copy (in this call's own WORKDIR) when it has one, else
    # the default repo stdlib. The baseline WORKDIR has no stdlib copy, so it falls back.
    _stdlib="${_work}/stdlib"
    if [ ! -d "$_stdlib" ]; then _stdlib="${ZORIL_STDLIB:-stdlib}"; fi

    # --row: only the cited probes and tests, so a surviving mutation means this row's
    # evidence does not reach its mechanism. The safety matrix reports a compile-reject probe
    # that the mutant now accepts as a mismatch, which is the catch.
    if [ -n "${ROW_PROBES_DIR:-}" ]; then
        mkdir -p "$_work"
        if [ -n "$(ls -A "$ROW_PROBES_DIR" 2>/dev/null)" ]; then
            if ! ZORIL="$_cc" PROBES_DIR="$ROW_PROBES_DIR" ./scripts/run_safety_matrix.sh \
                >> "$_work/suite.log" 2>&1; then
                echo "the row's probes (safety matrix)" > "$_work/fails"
                return 0
            fi
        fi
        if [ -n "${ROW_TEST_PATHS:-}" ]; then
            if ! TR_JOBS="${MUTATION_TEST_JOBS:-6}" TR_TIMEOUT="$MUTATION_TIMEOUT" \
                ZORIL_CC="$_cc" ZORIL_STDLIB="$_stdlib" TR_WORK="$_work/tests" \
                ./scripts/test.sh --quiet $ROW_TEST_PATHS >> "$_work/suite.log" 2>&1; then
                echo "the row's tests" > "$_work/fails"
                return 0
            fi
        fi
        return 0
    fi

    # Fast path: try the cached test from previous runs first.
    if [ -n "$_id" ] && [ -f "$MUTATION_CACHE/$_id" ]; then
        _cached=$(head -n 1 "$MUTATION_CACHE/$_id" 2>/dev/null)
        if [ "$_cached" = "perf-gate" ]; then
            if ! ZORIL_CC="$_cc" PERF_GAP_OUT="$_work/perf" ./scripts/perf_gap.sh --gate-check >> "$_work/suite.log" 2>&1; then
                echo perf-gate > "$_work/fails"
                return 0
            fi
        elif [ "$_cached" = "fmt-check" ]; then
            if ! ZORIL_CC="$_cc" ZORIL_STDLIB="$_stdlib" FMT_CHECK_OUT="$_work/fmt" ./scripts/check_fmt.sh >> "$_work/suite.log" 2>&1; then
                echo fmt-check > "$_work/fails"
                return 0
            fi
        elif [ "$_cached" = "static-image" ]; then
            if ! ZORIL_CC="$_cc" STATIC_IMAGE_WORK="$_work/static-image" ./scripts/check_static_image_determinism.sh >> "$_work/suite.log" 2>&1; then
                echo static-image > "$_work/fails"
                return 0
            fi
        elif [ -f "$_cached" ]; then
            _test_jobs=${MUTATION_TEST_JOBS:-6}
            TR_JOBS="$_test_jobs" TR_TIMEOUT="$MUTATION_TIMEOUT" ZORIL_CC="$_cc" ZORIL_STDLIB="$_stdlib" TR_WORK="$_work/tests" \
                ./scripts/test.sh --quiet --results "$_work/results" "$_cached" > "$_work/suite.log" 2>&1 || true
            _fail=$(awk -F'\t' '$1 == "FAIL" { print $2; exit }' "$_work/results" 2>/dev/null)
            if [ -n "$_fail" ]; then
                echo "$_fail" > "$_work/fails"
                return 0
            fi
        fi
    fi

    # Run per-file tests with --fail-fast and short per-test timeout.
    rm -f "$_work/results"
    _test_jobs=${MUTATION_TEST_JOBS:-6}
    TR_JOBS="$_test_jobs" TR_TIMEOUT="$MUTATION_TIMEOUT" ZORIL_CC="$_cc" ZORIL_STDLIB="$_stdlib" TR_WORK="$_work/tests" \
        ./scripts/test.sh --quiet --fail-fast --results "$_work/results" tests corpus > "$_work/suite.log" 2>&1 || true
    _first_fail=$(awk -F'\t' '$1 == "FAIL" { print $2; exit }' "$_work/results" 2>/dev/null)
    if [ -n "$_first_fail" ]; then
        # Re-verify the single failing test in isolation to guard against transient fork/scheduler flakes.
        if TR_TIMEOUT="$MUTATION_TIMEOUT" ZORIL_CC="$_cc" ZORIL_STDLIB="$_stdlib" TR_WORK="$_work/tests_retry" \
           ./scripts/test.sh --quiet "$_first_fail" >/dev/null 2>&1; then
            _first_fail=""
        fi
    fi
    if [ -n "$_first_fail" ]; then
        echo "$_first_fail" > "$_work/fails"
        if [ -n "$_id" ]; then
            mkdir -p "$MUTATION_CACHE"
            echo "$_first_fail" > "$MUTATION_CACHE/$_id"
        fi
        return 0
    fi

    # Only run perf-gate and fmt-check when per-file tests caught nothing.
    if ! ZORIL_CC="$_cc" PERF_GAP_OUT="$_work/perf" ./scripts/perf_gap.sh --gate-check >> "$_work/suite.log" 2>&1; then
        echo perf-gate > "$_work/fails"
        if [ -n "$_id" ]; then
            mkdir -p "$MUTATION_CACHE"
            echo perf-gate > "$MUTATION_CACHE/$_id"
        fi
        return 0
    fi
    if ! ZORIL_CC="$_cc" ZORIL_STDLIB="$_stdlib" FMT_CHECK_OUT="$_work/fmt" ./scripts/check_fmt.sh >> "$_work/suite.log" 2>&1; then
        echo fmt-check > "$_work/fails"
        if [ -n "$_id" ]; then
            mkdir -p "$MUTATION_CACHE"
            echo fmt-check > "$MUTATION_CACHE/$_id"
        fi
        return 0
    fi
    if ! ZORIL_CC="$_cc" STATIC_IMAGE_WORK="$_work/static-image" ./scripts/check_static_image_determinism.sh >> "$_work/suite.log" 2>&1; then
        echo static-image > "$_work/fails"
        if [ -n "$_id" ]; then
            mkdir -p "$MUTATION_CACHE"
            echo static-image > "$MUTATION_CACHE/$_id"
        fi
        return 0
    fi
}

# build_mutant ID FILE FIND REPL — stage src/ with the mutation applied and build it.
# Leaves ID/status: STALE, BUILD-FAILED or BUILT.
build_mutant() {
    _d="$STAGE/$1"
    mkdir -p "$_d"
    cp -r src "$_d/src"
    # Also stage stdlib so mutations may target it; the test compile uses the
    # mutant copy when present (see suite_failures), exercising stdlib mutations.
    cp -r stdlib "$_d/stdlib"
    # '#' as the sed delimiter: the patterns contain '|' and '/'.
    #
    # Escape BRE metacharacters in the pattern. Escaping only # and & is not
    # enough -- '(*self.builder)' contains a '*' that BRE reads as a repetition
    # operator, and five mutations silently failed to apply because of it.
    _find=$(printf '%s' "$3" | sed 's/[][\.*^$#&]/\\&/g')
    _repl=$(printf '%s' "$4" | sed 's/[#&\\]/\\&/g')
    sed "s#${_find}#${_repl}#" "$_d/$2" > "$_d/$2.tmp" && mv "$_d/$2.tmp" "$_d/$2"
    if cmp -s "$_d/$2" "$2"; then echo STALE > "$_d/status"; return; fi
    if ( ulimit -s 262144 2>/dev/null
         run_with_timeout $TIMEOUT_FOREGROUND -k 5s 600s "$GOOD" -I stdlib=stdlib -I "$_d/src" -I build/gen --emit-zil -o "$_d/zoril.zil" "$_d/src/main.zrl" &&
         run_with_timeout $TIMEOUT_FOREGROUND -k 5s 300s build/zilc "$_d/zoril.zil" "$_d/zoril.ssa" &&
         run_with_timeout $TIMEOUT_FOREGROUND -k 5s 300s "$BACKEND_BIN" -o "$_d/zoril.s" "$_d/zoril.ssa" &&
         "$ASSEMBLER_BIN" -o "$_d/zoril.o" "$_d/zoril.s" &&
         "$LINKER_BIN" -o "$_d/zoril" build/runtime.o "$_d/zoril.o" ) > "$_d/build.log" 2>&1; then
        echo BUILT > "$_d/status"
    else
        echo BUILD-FAILED > "$_d/status"
    fi
}

incremental_list_path() { printf '%s' "${MUTATION_INCREMENTAL:-$(dirname "$0")/mutation_incremental.list}"; }
incremental_mutation() {    # $1 = mutation id
    _lp=$(incremental_list_path)
    [ -f "$_lp" ] || return 1
    grep -qE "^$1([[:space:]]|$)" "$_lp"
}
run_incremental_scenario() {   # $1 = the mutant compiler, $2 = its scratch directory
    # The compiler path is passed through as the harness computed it, which is relative to the repository
    # root - and the next line changes to exactly that root. Making it absolute first is what broke this:
    # the scenario builds about ten of its own paths from a relative compiler and work directory and fails
    # on missing files when handed an absolute one, and the harness read that failure as a catch. Measured
    # with the no-op control canary: before this line went, the canary was reported caught; after, it
    # survives, and so do the verdicts below it mean what they say. (Since 2026-10-15 the scenario makes
    # every path absolute itself and accepts either form, with TR_WORK inside the repository.)
    # `cd` to the repository root the way the harness knows it. It has no `REPO_ROOT`: an earlier fix in
    # this file already had to stop using it. `cd ""` failed here - the log said "cd: null directory" - and
    # the scenario, which is self-locating and expects a compiler and work directory relative to the root,
    # was never run at all. The no-op control canary is what surfaced that: a scenario that never runs looks
    # exactly like one that catches everything.
    ( cd "$(dirname "$0")/.." && TR_WORK="$2/tr" ZORIL_CC="$1" ./scripts/test_incremental.sh ) \
        > "$2/incremental.log" 2>&1
}

printf 'Building the mutants and recording the baseline failures...\n'
# Read from a file, not a pipe: the builds must be children of this shell for `wait`.
# MUTATION_LIST lets the self-test (scripts/test_mutation_check.sh) run its own canaries instead.
if [ -n "${MUTATION_LIST:-}" ]; then
    cp "$MUTATION_LIST" "$STAGE/list"
else
    mutations > "$STAGE/list"
fi
# ── Validate the list before anything runs ─────────────────────────────────────
# Two orphaned continuation lines were once read as mutations with an empty id and file, and `--changed`
# dropped them silently, so `preflight-changed` passed while the full gate went red. A list that cannot be
# read exactly is a hole in the gate rather than a line to skip, so this fails at once, with the line
# number, in every mode: it runs before `--changed` filters anything.
validate_list() {
    _line=0; _ids=""
    while IFS= read -r _l || [ -n "$_l" ]; do
        _line=$((_line + 1))
        case "$_l" in ''|'#'*) continue ;; esac
        _bad=""
        case "$_l" in
            # `M<n>` for the real list; the self-test's canaries are `C<n>`, and every id is a
            # letter followed by a number. A stray continuation line fails here and on the separators.
            [A-Z][0-9]*@@*@@*@@*@@*) : ;;
            *) _bad="not <id>@@<file>@@<pattern>@@<replacement>@@<reason> (id: M<n>, or C<n> for a canary)" ;;
        esac
        _file=$(printf '%s' "$_l" | sed -n 's/^[^@]*@@\([^@]*\)@@.*$/\1/p')
        _find=$(printf '%s' "$_l" | sed -n 's/^[^@]*@@[^@]*@@\([^@]*\)@@.*$/\1/p')
        _repl=$(printf '%s' "$_l" | sed -n 's/^[^@]*@@[^@]*@@[^@]*@@\([^@]*\)@@.*$/\1/p')
        _id=$(printf '%s' "$_l" | sed -n 's/\(^[^@]*\)@@.*$/\1/p')
        if [ -z "$_bad" ] && [ -z "$_file" ]; then _bad="no file"; fi
        if [ -z "$_bad" ] && [ ! -f "$_file" ]; then _bad="file '$_file' does not exist"; fi
        if [ -z "$_bad" ] && [ -z "$_find" ]; then _bad="no search pattern"; fi
        case "$_ids" in *"|$_id|"*) if [ -z "$_bad" ]; then _bad="id $_id is used twice"; fi ;; esac
        if [ -n "$_bad" ]; then
            printf 'mutation-check: list line %d: %s\n  %s\n' "$_line" "$_bad" "$_l" >&2
            exit 2
        fi
        _ids="$_ids|$_id|"
    done < "$1"
}
validate_list "$STAGE/list"
# ── --row: the mutations and probes a safety-matrix row itself names ───────────
# A row lists the mutation IDs that disable its mechanism in its text. This mode selects
# exactly those, and runs exactly the probes and tests the row cites, so closing a row can
# require "each listed mutation is killed by this row's own evidence" without running the
# whole suite for every row.
ROW_IDS=""
ROW_PROBES_DIR=""
ROW_TEST_PATHS=""
if [ -n "$ROW" ]; then
    _row_line=$(awk -F'|' -v name="$ROW" '
        /^\| \*\*/ {
            prop = $2
            gsub(/^[ \t]+|[ \t]+$/, "", prop)
            if (index(prop, name) > 0) { print; exit }
        }' bench/safety_matrix/matrix.md)
    if [ -z "$_row_line" ]; then
        echo "mutation-check: no safety-matrix row matches '$ROW'" >&2
        exit 2
    fi
    ROW_IDS=$(printf '%s\n' "$_row_line" | grep -oE 'M[0-9]+' | sort -u)
    if [ -z "$ROW_IDS" ]; then
        echo "mutation-check: row '$ROW' lists no mutation IDs (add 'Mutations: M<n>, ...' to the row)" >&2
        exit 2
    fi
    ROW_PROBES_DIR="$STAGE/row-probes"
    mkdir -p "$ROW_PROBES_DIR"
    _links=$(printf '%s\n' "$_row_line" | grep -oE '\]\(([^)]+)\)' | sed -E 's/\]\(([^)]+)\)/\1/' | sed 's/#.*//')
    for _l in $_links; do
        case "$_l" in
            /*) _p="$_l" ;;
            *) _p=$( cd doc/spec 2>/dev/null && cd "$(dirname "$_l")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$_l")" ) ;;
        esac
        [ -n "${_p:-}" ] && [ -f "$_p" ] || continue
        case "$_p" in
            */bench/safety_matrix/probes/*.zrl) ln -s "$_p" "$ROW_PROBES_DIR/$(basename "$_p")" ;;
            */tests/*.zrl) ROW_TEST_PATHS="$ROW_TEST_PATHS $_p" ;;
        esac
    done
    if [ -z "$(ls -A "$ROW_PROBES_DIR" 2>/dev/null)" ] && [ -z "$ROW_TEST_PATHS" ]; then
        echo "mutation-check: row '$ROW' cites no probe or test this mode can run" >&2
        exit 2
    fi
    for _id in $ROW_IDS; do
        grep -q "^$_id@@" "$STAGE/list" || {
            echo "mutation-check: row '$ROW' names unknown mutation $_id" >&2
            exit 2
        }
    done
    printf 'Row: %s\nMutations: %s\nProbes: %s\nTests: %s\n\n' "$ROW" \
        "$(printf '%s' "$ROW_IDS" | tr '\n' ' ')" \
        "$(ls -A "$ROW_PROBES_DIR" 2>/dev/null | tr '\n' ' ')" "$ROW_TEST_PATHS"
fi


selected=0
while IFS='@' read -r id _a file _b find _c repl _d desc; do
    wanted "$id" "$file" && selected=$((selected + 1))
done < "$STAGE/list"
if [ "$selected" -eq 0 ]; then
    if [ "$ONLY" = "--changed" ] && [ -n "$CHANGED_DESC" ]; then
        printf 'No mutation targets a changed file (%s).\n' "$CHANGED_DESC"
    else
        printf 'No mutation targets a changed file.\n'
    fi
    exit 0
fi
if [ "$ONLY" = "--changed" ] && [ -n "$CHANGED_DESC" ]; then
    printf 'Targeting %d mutation(s) in files changed in %s.\n' "$selected" "$CHANGED_DESC"
fi
# Each mutant build is a whole self-compile (~0.7 GB peak): started all at once, 74 of them
# exhausted a 32 GB machine. Build in batches of MUTATION_JOBS, by default one per CPU and
# per GB of available memory.
if [ -z "$MUTATION_JOBS" ]; then
    if [ -f /proc/meminfo ]; then
        avail_gb=$(awk '/MemAvailable/ { print int($2 / 1048576) }' /proc/meminfo)
    else
        avail_gb=""
    fi
    MUTATION_JOBS=$(nproc_count)
    if [ -n "$avail_gb" ] && [ "${avail_gb:-0}" -lt "$MUTATION_JOBS" ]; then
        MUTATION_JOBS=$avail_gb
    fi
    [ "$MUTATION_JOBS" -lt 1 ] && MUTATION_JOBS=1
fi
# Baseline failing set, so a mutation is judged by what it ADDS.
suite_failures "$GOOD" "$STAGE/baseline" ""
baseline_fails=$(wc -l < "$STAGE/baseline/fails")
printf 'Baseline: %d failing test(s).\n\n' "$baseline_fails"
if [ "$baseline_fails" -gt 0 ]; then
    printf 'Baseline compiler has failing test(s); fix them first:\n'
    cat "$STAGE/baseline/fails"
    exit 1
fi

launched=0
while IFS='@' read -r id _a file _b find _c repl _d desc; do
    wanted "$id" "$file" || continue
    build_mutant "$id" "$file" "$find" "$repl" &
    launched=$((launched + 1))
    [ $((launched % MUTATION_JOBS)) -eq 0 ] && wait
done < "$STAGE/list"
wait

evaluate_mutant() {
    _id="$1"
    _d="$STAGE/$_id"
    suite_failures "$_d/zoril" "$_d" "$_id"
    _new=$(comm -13 "$STAGE/baseline/fails" "$_d/fails" | sed 's|.*/||; s|\.z[ri]l$||' | tr '\n' ' ')

    # A mutation on the `-c` path changes nothing the per-file suite compiles: those tests are single-shot,
    # and an interface (`.zri`) is only exercised by separate compilation. For the ids in
    # scripts/mutation_incremental.list the scenario runs with the mutant as the compiler, in its own
    # `TR_WORK`, which is also what keeps two runs from sharing a work directory; a failing scenario is the
    # catcher, and one that passes leaves the mutant SURVIVED like any other hole.
    if [ -z "$_new" ] && incremental_mutation "$_id"; then
        if ! run_incremental_scenario "$_d/zoril" "$_d"; then
            _new="the incremental scenario (-c / .zri), see $_id/incremental.log"
        else
            echo 1 > "$_d/incremental_passed"
        fi
    fi
    printf '%s' "$_new" > "$_d/caught_by"
}

total_wanted=0
total_built=0
total_build_failed=0
while IFS='@' read -r id _a file _b find _c repl _d desc; do
    wanted "$id" "$file" || continue
    total_wanted=$((total_wanted + 1))
    st=$(cat "$STAGE/$id/status" 2>/dev/null || true)
    if [ "$st" = "BUILT" ]; then
        total_built=$((total_built + 1))
    elif [ "$st" = "BUILD-FAILED" ]; then
        total_build_failed=$((total_build_failed + 1))
    fi
done < "$STAGE/list"

if [ "$total_wanted" -gt 0 ] && [ "$total_built" -eq 0 ] && [ "$total_build_failed" -gt 0 ]; then
    printf '\nERROR: the mutation stage is stale or broken (every mutant failed to build).\n' >&2
    exit 2
fi

eval_launched=0
_eval_jobs="${MUTATION_EVAL_JOBS:-2}"
if [ "$_eval_jobs" -gt "$MUTATION_JOBS" ]; then
    _eval_jobs="$MUTATION_JOBS"
fi
[ "$_eval_jobs" -lt 1 ] && _eval_jobs=1

while IFS='@' read -r id _a file _b find _c repl _d desc; do
    wanted "$id" "$file" || continue
    case "$(cat "$STAGE/$id/status" 2>/dev/null)" in
        BUILT)
            evaluate_mutant "$id" &
            eval_launched=$((eval_launched + 1))
            [ $((eval_launched % _eval_jobs)) -eq 0 ] && wait
            ;;
    esac
done < "$STAGE/list"
wait

while IFS='@' read -r id _a file _b find _c repl _d desc; do
    wanted "$id" "$file" || continue
    printf '%s  %s\n' "$id" "$desc"
    printf '    %s\n' "$file"
    d="$STAGE/$id"
    case "$(cat "$d/status" 2>/dev/null)" in
        STALE)
            printf '    ERROR — mutation did not apply (pattern no longer matches). Update this script.\n\n'
            echo "$id@@STALE: pattern no longer matches; mutation never ran" >> "$STAGE/stale"
            continue ;;
        BUILT) ;;
        *)
            printf '    BUILD-FAILED — mutation broke the build; says nothing about test strength.\n'
            printf '    See %s/build.log.\n\n' "$d"
            echo "$id@@BUILD-FAILED: the mutant does not build; mutation never ran" >> "$STAGE/stale"
            continue ;;
    esac

    NEW=$(cat "$d/caught_by" 2>/dev/null || true)
    if [ -f "$d/incremental_passed" ]; then
        printf '    the incremental scenario passed under this mutant too - a coverage hole.\n'
    fi

    if [ -z "$NEW" ]; then
        printf '    *** SURVIVED *** no test failed that was not already failing.\n'
        printf '        %s\n\n' "$(rg -o '[0-9]+ run, [0-9]+ passed' "$d/suite.log" | head -1)"
        echo "$id@@$desc" >> "$STAGE/survivors"
    else
        printf '    caught by: %s\n\n' "$NEW"
    fi
done < "$STAGE/list"

if [ -s "$STAGE/stale" ]; then
    printf '\nMUTATIONS THAT NEVER RAN — they proved nothing:\n\n'
    while IFS='@' read -r id _x desc; do printf '  %s  %s\n' "$id" "$desc"; done < "$STAGE/stale"
    printf '\nThe source moved under them. Update the patterns in this script.\n'
    printf 'Reported as a failure deliberately: a mutation that cannot apply is a\n'
    printf 'gate that cannot fail, which is the exact problem this harness exists for.\n'
    exit 1
fi

if [ -s "$STAGE/survivors" ]; then
    printf '\nSURVIVING MUTATIONS — the suite cannot tell these from correct behaviour:\n\n'
    while IFS='@' read -r id _x desc; do printf '  %s  %s\n' "$id" "$desc"; done < "$STAGE/survivors"
    printf '\nEach is a missing test. Add one that fails under the mutation.\n'
    exit 1
fi

printf '\nAll mutations caught.\n'
rm -rf "$STAGE"
exit 0
