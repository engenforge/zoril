# Current Sprint

Open work, in the order it is done, tracked on the orphan `tasks` branch (SPEC-TASKMARK-05). The rules for reading this file, placing a new task and the priority flag are under "Working on tasks" in `AGENTS.md`: this file is one queue, and position is the only statement of order.

**Series rule (2026-11-05, from id:z0071):** a precision fix that removes origins from a set (an exemption, a split, a moved-storage drop) is first measured alone, on top of the task it serves, to show it is needed; and it comes with probes of its sibling routes (the value built inside the callee, returned from a call, packed into a struct beside a view or a raw pointer).

**Header rule (2026-11-17):** the `>` block under a task holds only the fields a tool or the workflow reads: `Created`, `Due`, `Branch`, `Depends`, `Claimed`, `Completed`, `Check-in`, `Context`, first, then a blank line. Every other note (`Found by`, `Placed`, `Routed by`, `Depends note`, `Depends changed (..)`, `Deferred`, `Promoted`, ...) is a bullet below it (`    - **Found by:** ...`). A multi-word `> **Key name:**` line is not a field to `tm`: it continues the field above it, and under `Depends:` every `id:` on it becomes a dependency (SPEC-TASKMARK-06 §4.4.2). `tm validate --strict` checks this.

- [x] +safety +tests +AI-D @provenance B3b.2 The narrowing `#[borrows(..)]` declarations of the files directly under `src/` and of `src/driver/` are removed, widened or made explicit exemptions id:cmg8n
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:mztqb
    > **Completed:** 2026-11-18 git:a084be8

    - **Split from:** id:mrdtf (2026-11-18), by directory as its **Size** bullet asks. That task's **Constraint** and rule hold here too.
    - **Placed:** after id:mrdtf, as one of its parts. Like id:mrdtf it comes before id:z0011, which id:mrdtf blocks. id:z0011's **Depends:** lists only id:mrdtf, so the maintainer may add this part there.
    - **Scope:** the 30 sites in the files directly under `src/` and in `src/driver/`. Each site is removed, widened to what the body returns, or made an explicit `#[unsafe(borrows(..))]` exemption with a `// SAFETY:` line. The commit lists each site with its decision.
    - **The sites** (id:bfd1z's measurement, each with the reason a held tie would not free it: `unsafe`, an `unsafe` body or an `extern` call; `param-addr`, the result points into the referent itself; `param-owned`, an owning read; `held`, a held tie would free it): `src/check_zir.zrl:1430` (param-owned), `src/check_zir.zrl:1475` (unsafe), `src/check_zir.zrl:2045` (unsafe), `src/check_zir.zrl:4049` (held), `src/check_zir.zrl:83` (unsafe), `src/check_zir.zrl:8945` (unsafe), `src/driver/module.zrl:898` (unsafe), `src/lexer.zrl:241` (param-owned), `src/lexer.zrl:43` (param-addr), `src/lower_zir_to_zil.zrl:108` (unsafe), `src/lower_zir_to_zil.zrl:155` (unsafe), `src/main.zrl:324` (unsafe), `src/main.zrl:433` (unsafe), `src/main.zrl:676` (param-addr,param-owned), `src/module_path.zrl:345` (unsafe), `src/module_path.zrl:411` (param-owned), `src/mono.zrl:1056` (held), `src/mono.zrl:1072` (held), `src/mono.zrl:1133` (held), `src/mono.zrl:1173` (param-owned), `src/mono.zrl:1185` (param-owned), `src/mono.zrl:1326` (unsafe), `src/mono.zrl:1343` (unsafe), `src/mono.zrl:921` (param-owned), `src/mono.zrl:939` (unsafe), `src/resolve.zrl:1485` (unsafe), `src/resolve.zrl:174` (unsafe), `src/resolve.zrl:2206` (unsafe), `src/verify.zrl:1604` (unsafe), `src/verify.zrl:553` (unsafe).
    - **Checks:** C1: before each removal, its default-build refusals in `src/` and `tools/` (id:mztqb's `cost.sh`, with the edit made in a scratch copy). C2: id:bfd1z's measurement (its **Measurement scripts**, with the word and the report patch applied to a scratch copy of the tree after the change) shows this part's sites gone, and none added elsewhere, against id:bfd1z's 84. C3: `src/` builds with `build/zoril-stage1` and with the previous `build/zoril`. C4: `make test` (`Total:` with 0 failed). C5: `make preflight-changed`.
    - **Completion (2026-11-18, git:a084be8):** the 30 functions (33 function and parameter pairs) settled; the commit lists each with its decision.
      - _Widened:_ `ZirAnalysisState::clone` (`&self` default to `#[borrows(arena)]`; first tried as `#[borrows(self, arena)]`, which made `run_block` and `merge_states` new sites, because the default's ties had been inferred from the body, `arena` only), `compute_origins_zir` `(table, arena, file, func)`, `default_output_path` `(arena)`, `parse_args` `(arena, argv)`, `derive_module_identity` `(abs_file, arena)`, `module_resolution_new` `(entry_file, root_opt, arena, table)`, `impl_type_args` gains `imp`, `loop_blocks` gains `func`.
      - _Trusted_ (`#[unsafe(borrows(..))]` with a `// SAFETY:` line, 24 attributes): `Lexer::new` `(source, arena)`, `verify_module` `(arena, o)`, the ZirVerifier, ZirToZilLowerer, Driver, Resolver, SymbolTable, Verifier and Monomorphizer `self` sites, and `Lexer::text_from`. Every `arena_reset` in `src/` is of the driver's `scratch_arena` (`src/driver/module.zrl` :539, :1225, :1285). ZirVerifier and ZirToZilLowerer get it only inside `run_body_passes_in_scratch`, which resets it after they are gone. Resolver, Monomorphizer, Verifier and Driver hold the compilation's arena, which is never reset.
      - C1: the full widening was tried in a scratch copy (`build/mrdtf/src_c`). `build/zoril` refused 8 sites: naming `table` on `Lexer::new` refused `parser/module.zrl:371`, `fmt/fmt.zrl:159`, `:162` and `main.zrl:489` ("cannot mutably borrow 'table' more than once"); naming `m` and `table` on `verify_module` refused `main.zrl:631` and `:646`. Without those two parameters, rc=0, so they are trusted instead. At the commit, `build/zoril ... src/main.zrl` rc=0 and `make` printed 0 warnings.
      - C2: the 33 pairs of this part: 0 plain, 25 `trusted`; nothing else changed (`diff` against the measurement before this part, empty).
      - C3: `build/zoril-stage1 -I stdlib=stdlib -I src -I build/gen --emit-zil -o /dev/null src/main.zrl` rc=0 at git:a084be8 and at git:d41395f. The previous `build/zoril`, built at git:27175cd, compiled git:a084be8's `src/` (rc=0).
      - C4: `make test` at git:d41395f: `Total: 3858 run, 3858 passed, 0 failed, 102 skipped (141.4s)`.
      - C5: `REJECT_DIFF_NO_CACHE=1 make preflight-changed` at git:d41395f, exit 0: `PASS — a clean copy of the tree builds with the default rules, and the compiler reproduces itself.`, `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`, `reject-diff: base verdicts: fresh (no cache)`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 2548 newly refused, of 69167 programs against a484d11487430a4f709006c069b68454b476b98a` (the merge base with `main`, 57 commits back; the same count as before this series of edits, git:92bce83), `All performance thresholds within tolerance of baseline.` One run covers id:cmg8n, id:jzq16 and id:zfeg9, made after the last of their edits.
      - C2 is measured with `build/mrdtf/zoril.w` (id:bfd1z's word and report patch on a copy of `src/`, built with `build/bfd1z/mk.sh`), `build/bfd1z/measure.sh build/mrdtf/zoril.w build/mrdtf/t6`, every root rc=0, and compared by `file fn param` (line numbers drift between runs). At git:d41395f no `src/` or `tools/` entry is plain, 65 are `trusted`, and the stdlib and test entries equal id:bfd1z's. id:z0011's check still has to skip a trusted declaration (id:akapm).
      - The fuzz record is stale for `src/` and `tools/zilc/` (`scripts/check_fuzz_fresh.sh`: `STALE`), as it already was for the branch.

- [x] +safety +tests +AI-D @provenance B3b.3 The narrowing `#[borrows(..)]` declarations of `src/parser/` and `src/fmt/` are removed, widened or made explicit exemptions id:jzq16
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:mztqb
    > **Completed:** 2026-11-18 git:6089d4b

    - **Split from:** id:mrdtf (2026-11-18), by directory as its **Size** bullet asks. That task's **Constraint** and rule hold here too.
    - **Placed:** after id:mrdtf, as one of its parts. Like id:mrdtf it comes before id:z0011, which id:mrdtf blocks. id:z0011's **Depends:** lists only id:mrdtf, so the maintainer may add this part there.
    - **Scope:** the 14 sites in `src/parser/` and `src/fmt/`. Each site is removed, widened to what the body returns, or made an explicit `#[unsafe(borrows(..))]` exemption with a `// SAFETY:` line. The commit lists each site with its decision.
    - **The sites** (id:bfd1z's measurement, each with the reason a held tie would not free it: `unsafe`, an `unsafe` body or an `extern` call; `param-addr`, the result points into the referent itself; `param-owned`, an owning read; `held`, a held tie would free it): `src/fmt/doc.zrl:150` (unsafe), `src/fmt/doc.zrl:221` (unsafe), `src/fmt/doc.zrl:78` (param-owned), `src/parser/decl.zrl:177` (unsafe), `src/parser/decl.zrl:325` (unsafe), `src/parser/decl.zrl:359` (param-owned), `src/parser/decl.zrl:504` (unsafe), `src/parser/decl.zrl:60` (param-owned), `src/parser/decl.zrl:953` (param-owned), `src/parser/expr.zrl:585` (unsafe), `src/parser/module.zrl:81` (unsafe), `src/parser/parse_type.zrl:157` (unsafe), `src/parser/pattern.zrl:40` (unsafe), `src/parser/stmt.zrl:297` (unsafe).
    - **Checks:** C1: before each removal, its default-build refusals in `src/` and `tools/` (id:mztqb's `cost.sh`, with the edit made in a scratch copy). C2: id:bfd1z's measurement (its **Measurement scripts**, with the word and the report patch applied to a scratch copy of the tree after the change) shows this part's sites gone, and none added elsewhere, against id:bfd1z's 84. C3: `src/` builds with `build/zoril-stage1` and with the previous `build/zoril`. C4: `make test` (`Total:` with 0 failed). C5: `make preflight-changed`.
    - **Completion (2026-11-18, git:6089d4b):** the 14 sites settled; the commit lists each with its decision.
      - _Widened:_ `Parser::parse_fn_decl` `#[borrows(self, attr)]` (was the `&self` default), `Doc::render` `#[borrows(arena)]` (was `#[borrows()]`), `Doc::group_ends` `#[borrows(arena)]` (was the default).
      - _Trusted:_ the ten Parser `self` sites (`Parser.arena`: `main.zrl`'s compilation arena, or the formatter's, neither of them ever reset; the only `arena_reset` calls in `src/` are of the driver's scratch arena), and `Doc::cmd_at` (its `text` is a view the document holds).
      - `src/parser/decl.zrl`'s comment-budget row was re-recorded (`scripts/comment_census.sh --record`, keeping only that row: 947 code and 53 comment lines, after 48 against a limit of 50). The commit says why. `sh scripts/check_comment_noise.sh`: `[PASS] comment-census: 136 file(s) within budget`.
      - C1: `build/zoril ... src/main.zrl` rc=0 with the edits, before rebuilding; `make` printed 0 warnings.
      - C2: this part's 14 pairs: 0 plain, 14 `trusted` or gone (`render`, `group_ends` and `parse_fn_decl`'s `attr` gone).
      - C3: `build/zoril-stage1` compiles `src/main.zrl` (rc=0) at git:d41395f; the previous `build/zoril`, built at git:a084be8, compiled it (rc=0).
      - C4: `make test` at git:d41395f: `Total: 3858 run, 3858 passed, 0 failed, 102 skipped (141.4s)`.
      - C5: `REJECT_DIFF_NO_CACHE=1 make preflight-changed` at git:d41395f, exit 0: `PASS — a clean copy of the tree builds with the default rules, and the compiler reproduces itself.`, `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`, `reject-diff: base verdicts: fresh (no cache)`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 2548 newly refused, of 69167 programs against a484d11487430a4f709006c069b68454b476b98a` (the merge base with `main`, 57 commits back; the same count as before this series of edits, git:92bce83), `All performance thresholds within tolerance of baseline.` One run covers id:cmg8n, id:jzq16 and id:zfeg9, made after the last of their edits.
      - C2 is measured with `build/mrdtf/zoril.w` (id:bfd1z's word and report patch on a copy of `src/`, built with `build/bfd1z/mk.sh`), `build/bfd1z/measure.sh build/mrdtf/zoril.w build/mrdtf/t6`, every root rc=0, and compared by `file fn param` (line numbers drift between runs). At git:d41395f no `src/` or `tools/` entry is plain, 65 are `trusted`, and the stdlib and test entries equal id:bfd1z's. id:z0011's check still has to skip a trusted declaration (id:akapm).
      - The fuzz record is stale for `src/` and `tools/zilc/` (`scripts/check_fuzz_fresh.sh`: `STALE`), as it already was for the branch.

- [x] +safety +tests +AI-D @provenance B3b.4 The narrowing `#[borrows(..)]` declarations of `tools/zilc/` are removed, widened or made explicit exemptions id:zfeg9
    > **Created:** 2026-11-18
    > **Branch:** `provenance`
    > **Depends:** id:mztqb
    > **Completed:** 2026-11-18 git:d41395f

    - **Split from:** id:mrdtf (2026-11-18), by directory as its **Size** bullet asks. That task's **Constraint** and rule hold here too.
    - **Placed:** after id:mrdtf, as one of its parts. Like id:mrdtf it comes before id:z0011, which id:mrdtf blocks. id:z0011's **Depends:** lists only id:mrdtf, so the maintainer may add this part there.
    - **Scope:** the 4 sites in `tools/zilc/src/` (zbuild, zman and ztest have none of their own left). Each site is removed, widened to what the body returns, or made an explicit `#[unsafe(borrows(..))]` exemption with a `// SAFETY:` line. The commit lists each site with its decision.
    - **The sites** (id:bfd1z's measurement, each with the reason a held tie would not free it: `unsafe`, an `unsafe` body or an `extern` call; `param-addr`, the result points into the referent itself; `param-owned`, an owning read; `held`, a held tie would free it): `tools/zilc/src/zil_parse.zrl:1031` (unsafe), `tools/zilc/src/zil_parse.zrl:843` (param-owned), `tools/zilc/src/zil_parse.zrl:871` (unsafe), `tools/zilc/src/zil_parse.zrl:987` (unsafe).
    - **Checks:** C1: before each removal, its default-build refusals in `src/` and `tools/` (id:mztqb's `cost.sh`, with the edit made in a scratch copy). C2: id:bfd1z's measurement (its **Measurement scripts**, with the word and the report patch applied to a scratch copy of the tree after the change) shows this part's sites gone, and none added elsewhere, against id:bfd1z's 84. C3: `src/` builds with `build/zoril-stage1` and with the previous `build/zoril`. C4: `make test` (`Total:` with 0 failed). C5: `make preflight-changed`.
    - **Completion (2026-11-18, git:d41395f):** the 4 sites made trusted (`#[unsafe(borrows())]` with a `// SAFETY:` line). `parse_ssa_list`, `parse_string_literal` and `parse_phi_preds` return data in the module's arena, and `tools/zilc/src` has no `arena_reset` call. `parse_region`'s `Region.Custom` holds a view of the ZIL source; its old comment ("A plain value") is replaced by the `SAFETY` line.
      - C1: `build/zoril -I stdlib=stdlib -I src -I tools/zilc/src -I build/gen --emit-zil -o /dev/null tools/zilc/src/main.zrl` rc=0; the trusted flag is read nowhere yet, so no caller can be refused.
      - C2: the 4 pairs are `trusted`; none plain.
      - C3: `build/zoril-stage1` (the `zilc-boot` path) compiles `tools/zilc/src/main.zrl` (rc=0); `make` rebuilt zilc with 0 warnings.
      - C4: `make test` at git:d41395f: `Total: 3858 run, 3858 passed, 0 failed, 102 skipped (141.4s)`.
      - C5: `REJECT_DIFF_NO_CACHE=1 make preflight-changed` at git:d41395f, exit 0: `PASS — a clean copy of the tree builds with the default rules, and the compiler reproduces itself.`, `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`, `reject-diff: base verdicts: fresh (no cache)`, `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 2548 newly refused, of 69167 programs against a484d11487430a4f709006c069b68454b476b98a` (the merge base with `main`, 57 commits back; the same count as before this series of edits, git:92bce83), `All performance thresholds within tolerance of baseline.` One run covers id:cmg8n, id:jzq16 and id:zfeg9, made after the last of their edits.
      - C2 is measured with `build/mrdtf/zoril.w` (id:bfd1z's word and report patch on a copy of `src/`, built with `build/bfd1z/mk.sh`), `build/bfd1z/measure.sh build/mrdtf/zoril.w build/mrdtf/t6`, every root rc=0, and compared by `file fn param` (line numbers drift between runs). At git:d41395f no `src/` or `tools/` entry is plain, 65 are `trusted`, and the stdlib and test entries equal id:bfd1z's. id:z0011's check still has to skip a trusted declaration (id:akapm).
      - The fuzz record is stale for `src/` and `tools/zilc/` (`scripts/check_fuzz_fresh.sh`: `STALE`), as it already was for the branch.

- [ ] +safety +tests +AI-D @provenance id:z0011 B3 Declarations are checked against the body: `#[borrows(..)]`, `#[stores(..)]`, the `&self` default
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Depends:** id:z0049, id:z0064, id:0m61c, id:mztqb, id:mrdtf, id:akapm
    > **Check-in:** stop for review after it.

    - **Rule (Decision 1):** a declaration may list more than the body proves (a wider public contract), never less. For a function with a body the effective ties and stores are the union of what the body proves and any declaration (id:z0010 already sums them); a declaration that claims less than the body is a compile error, the narrowing rule of `CHANGELOG.md`'s pre-1.0 note. The `&self` elision default and the declarations apply as written to bodyless items (`extern`, trait signatures, `.zri` imports). Each of the tree's 82 `#[borrows()]` declarations (such as `Lexer.text_from`) is either proved unnecessary by id:z0010's `ParamAddr`/`ParamContents` summary and removed, or converted into an explicit, reviewed `unsafe` interior with a `// SAFETY:` comment, listed with its decision in the commit. **Stop and report** before changing a `pub` stdlib signature.
    - **Test expectation note:** `tests/error_reporting/err_stores_attribute_false.zrl` currently expects a wider `#[stores]` contract than the body performs to fail; under the wider-contract rule that test changes (stop and document the test change per `AGENTS.md`).
    - **Probes:** an unannotated `&self` method passing a parameter's borrow through, the same through a trait, and safe-code `#[borrows()]` laundering (`gap_30_borrows_attribute_launder` stays rejected; `gap_44_borrows_attr_reset` is rejected once checked declarations refuse the narrowing `#[borrows()]` (it is accepted, exit 77, under `--provenance` at `c323b0e`: a reset hole, not an escape, so the store rules do not see it)); accepted: a `&self` method returning a view of `self` and a wider `#[borrows]`/`#[stores]` public contract. `make test`, `make preflight-changed`. Stop for review.
    - **Blind spot not covered by this check (from id:z0049's review, 2026-11-05):** a body that copies through a bare `extern` proves no store, so a declaration can never be "narrower than the body" there (id:z0060's `extend_from_slice` route). Add a rule here or in a task of its own: a safe function that passes a pointer derived from a parameter to an `extern` with no declared effect must declare its own `#[stores]`/`#[borrows]` (or the `extern` declares its effect). Probe it with id:z0060's reproducer with id:z0060's fix taken out.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").
    - **Added by id:z0073's decision (the maintainer, 2026-11-14):** case B there. A safe function whose `unsafe` block writes a value that can hold a reference or a slice through a raw pointer (one it was given, or one an argument holds: `unsafe { *self.p = r; }`) must declare `#[stores(..)]` naming the argument stored and the one it is stored into, or it is a compile error; the declaration is then a trusted claim (`doc/SAFETY.md` §4.2) and the caller applies the call store rule to it. It is one rule with the bare-`extern` rule of the **Blind spot** bullet above: a safe function may not hide a store behind an operation the checker cannot read. Probe: `put` with and without the declaration (`build/z76/cx.zrl` in id:z0076's text), a caller passing `&x` of a local with `g` reaching outside the frame (refused once declared), the same store of a plain integer (no declaration needed), and the count of functions in `stdlib/`, `src/` and `tools/` that newly need a declaration, measured before the rule is made an error. If that count makes this task more than a session, split the rule into a task of its own directly after this one.
    - **Measured (2026-11-18, on `stream/provenance` at git:5ca36fb):** the check below (`os_check_ties`, patch under **Patch**), built as `build/z11/zoril.new`, refuses under `--provenance` every function whose final body summary ties its result to a parameter `ret_ties` leaves out. The body ties are the ones `os_call` reads: `os_ret_addr`, plus `os_ret_contents` unless the result holds only integers (`os_holds_pointer`). Both sides are limited to types that can hold a reference (`ILModule.type_holds_reference`, raw pointers included), as `inherit_rv_borrows` is, so `grow_cap(cap: usize) -> usize` is not refused. Closures (a trailing `__env`), `extern` items and `.zri` imports are skipped. It runs after `store_origin_summary` for a body outside a cycle, and in `os_fixpoint`'s checking pass for one inside a cycle. `--provenance=warn` makes the refusal a warning.
      - Probes (`build/z11/run.sh`; default build, then `build/z11/zoril.new --provenance`): `gap_44` exit 77, then refused at its `text_from` ("#[borrows(..)] leaves out 'self' ..."); `gap_30` refused, then refused at `launder` by the new check; `selfpass` (unannotated `pick(self: &S, x: [u8]) -> [u8] { return x; }`, then an arena reset) exit 77, then refused ("the result may point into 'x', which the `&self` default does not tie it to"); the trait form `traitpass`, the same; `s.clone()` of a slice, then a reset, exit 77, then refused at `stdlib/core.zrl:258`. These three new holes are probes `gap_99`, `gap_100`, `gap_101` (git:e14d03d), and they stay `known_gap` until the rule is on by default (id:z0065, id:z0012). A generic `id<T>(x: T) -> T` and `v.iter().map(f)` are refused by the default build already.
      - **Counts (`build/z97/measure.sh`, `--provenance=warn`):** 97 distinct sites. Roots: `src/main.zrl` 85 (183 provenance warnings, 268 with the check); zbuild 11, zilc 8, zman 2 (stdlib sites counted again for each root). Test programs: 58 warnings, all at stdlib sites. 12 of the sites are the `&self` default (`src/check_zir.zrl:83`, `src/fmt/doc.zrl:221`, `src/lower_zir/expr.zrl:176` and `:2678`, `src/parser/decl.zrl:333`, and 7 in stdlib); the rest are `#[borrows(..)]` declarations.
      - **Stdlib sites (13; each changes a `pub` contract, so the maintainer decides first):** `args.zrl:46` `Args.get`, `:85` `Args.next`; `bufio.zrl:36` `BufWriter.with_capacity`, `:234` `BufReader.with_capacity` (`inner` by value, a type parameter); `clone.zrl:17` `Clone for Vec<T>` (gap_77), `:35` `Clone for String`; `core.zrl:242` `Clone for Option<T>` (gap_78), `:258` `Clone for [T]` (gap_99); `file.zrl:144` `read_to_end_sized_raw`; `iter.zrl:26` `Iterator.map` (by-value `Self`: an over-report, since the default build refuses that route); `string.zrl:186` `String.clone_in_raw`, `:326` `split_raw`; `vec.zrl:155` `Vec.clone_in_raw`. The last three are `unsafe fn`s whose result is tied to a raw `arena: *mut ArenaHeader` that the `&self` default leaves out.
      - **Tests the check breaks** (`ZORIL_CC=build/z11/zoril.new ./scripts/test.sh tests/language tests/stdlib tests/error_reporting`: `Total: 1068 run, 1063 passed, 5 failed, 0 skipped (7.9s)`), all `// flags: --provenance` tests under `tests/language/memory/provenance/`: `arena_named_through_vec_reference_accepted` (its own two `#[borrows()]`, lines 16 and 20), `clone_returned_accepted` (`core.zrl`, `clone.zrl`), `popped_integer_carries_no_address_accepted` (its own `#[borrows()] fn at0`, whose `Cmd` result holds `text`), `unsafe_fn_summary_accepted` and `unsafe_fn_summary_cycle_accepted` (`string.zrl:326`). So the check cannot land before the stdlib sites are settled, and the two tests' own declarations change their text (stop and report, per `AGENTS.md`).
      - **Not done in this session:** the `#[stores]` wider-contract change (`err_stores_attribute_false.zrl`), the bare-`extern` and raw-store rule (case B), and the 85 `src/` and the `tools/` sites. Split into tasks: id:mztqb, id:mrdtf before this one, and id:f81f3 after it.
      - **Patch** (`build/z11/z0011-check.patch`, against git:5ca36fb; apply with `git apply`):
    ```diff
    diff --git a/src/check_zir.zrl b/src/check_zir.zrl
    index 86da7c2..2d969a6 100644
    --- a/src/check_zir.zrl
    +++ b/src/check_zir.zrl
    @@ -8286,6 +8286,72 @@ pub fn store_origin_summary(
         return grew;
     }
     
    +// The parameters FUNC's result may point into by its final body summary, as a call reads them
    +// (os_call): its ParamAddr ties, and its ParamContents ties unless the result holds only integers.
    +fn os_body_ties(c: &mut OriginSets, module: &ILModule, f: &ILFunction) -> u64 {
    +    if f.ret_ty == 0 as u32 || !os_carries(c, module, f.ret_ty) { return 0 as u64; }
    +    if !os_holds_pointer(module, f.ret_ty, 0 as usize) { return f.os_ret_addr; }
    +    return f.os_ret_addr | f.os_ret_contents;
    +}
    +
    +// `#[borrows(..)]` and the `&self` default are checked against the body (§3, _Checked
    +// contracts_): a call's borrows (inherit_rv_borrows) and every importer read `ret_ties`, so a
    +// result tied in the body to a parameter `ret_ties` leaves out would end that borrow while the
    +// result still points into it. A declaration may be wider than the body, never narrower. A
    +// closure's ties are its environment's, which no declaration names. A rule of `--provenance`,
    +// beside the others until they are the default. Returns the refusals.
    +pub fn os_check_ties(c: &mut OriginSets, module: &ILModule, idx: usize, span: Span) -> u32 {
    +    let f = &module.functions[idx];
    +    if c.rules == PROVENANCE_OFF || f.from_interface || f.is_extern { return 0 as u32; }
    +    if f.params_len > 0 as usize
    +        && type_name_is(c.table.lookup(f.param(f.params_len - 1 as usize).name), "__env") {
    +        return 0 as u32;
    +    }
    +    // A borrow is held only by a value whose type can hold a reference (inherit_rv_borrows), so
    +    // an integer result or argument carries none, whatever address its bits may hold.
    +    if f.ret_ty != 0 as u32 && !module.type_holds_reference(f.ret_ty, 0 as usize) {
    +        return 0 as u32;
    +    }
    +    let missing = os_body_ties(c, module, f) & !f.ret_ties;
    +    if missing == 0 as u64 { return 0 as u32; }
    +    let base = if f.params_len > 0 as usize && f.param(0).name == c.sret_name {
    +        1 as usize
    +    } else {
    +        0 as usize
    +    };
    +    let mut i = 0 as usize;
    +    while i < 63 as usize {
    +        if (missing >> (i as u64)) & 1 as u64 != 0 as u64
    +            && i + base < f.params_len
    +            && module.type_holds_reference(f.param(i + base).ty, 0 as usize) {
    +            let name = c.table.lookup(f.param(i + base).name);
    +            diag_start(c.file, span, if c.rules == PROVENANCE_WARN { "warning" } else { "error" });
    +            eprint("provenance: ");
    +            if f.has_borrows {
    +                eprint("#[borrows(..)] leaves out '");
    +                eprint(name);
    +                eprint("', which the result may point into; ");
    +                eprint("a declaration may name more than the body returns, never less\n");
    +            } else if f.ret_ties == 1 as u64 && i != 0 as usize {
    +                eprint("the result may point into '");
    +                eprint(name);
    +                eprint("', which the `&self` default does not tie it to; add `#[borrows(self, ");
    +                eprint(name);
    +                eprint(")]`\n");
    +            } else {
    +                // A by-value `Self` or type parameter, whose declared type showed no reference.
    +                eprint("the result may point into '");
    +                eprint(name);
    +                eprint("', which the elision default does not tie it to; ");
    +                eprint("add `#[borrows(..)]` naming it\n");
    +            }
    +            return 1 as u32;
    +        }
    +        i = i + 1 as usize;
    +    }
    +    return 0 as u32;
    +}
    +
     // A direct call's result, into OS_T_VO and OS_T_VS, from the callee's summary: an argument in
     // `ret_storage` gives its own origins (the result points into it); one in `ret_ties` gives what is
     // reached through it when it is a reference, and itself and what it reaches otherwise. An owning
    diff --git a/src/driver/module.zrl b/src/driver/module.zrl
    index 9a602f3..d5e31b4 100644
    --- a/src/driver/module.zrl
    +++ b/src/driver/module.zrl
    @@ -1271,6 +1271,14 @@ impl Driver {
                 e.func_idx as usize,
                 &mut origins
             );
    +        if check {
    +            let span = self.module.functions[e.func_idx as usize].decl_span;
    +            let refused =
    +                check_zir::os_check_ties(&mut origins, self.module, e.func_idx as usize, span);
    +            if refused > 0 as u32 && self.provenance == check_zir::PROVENANCE_ON {
    +                self.had_error = true;
    +            }
    +        }
             if check && self.emit_origins && e.source_file == self.target_source_file {
                 check_zir::print_origins(&origins, &e.zir, self.module, self.intern_table);
             }
    @@ -1357,6 +1365,14 @@ impl Driver {
                 self.builder.current_func_idx as usize,
                 &mut origins
             );
    +        if !in_cycle {
    +            let idx = self.builder.current_func_idx as usize;
    +            let span = self.module.functions[idx].decl_span;
    +            let refused = check_zir::os_check_ties(&mut origins, self.module, idx, span);
    +            if refused > 0 as u32 && self.provenance == check_zir::PROVENANCE_ON {
    +                self.had_error = true;
    +            }
    +        }
             if in_cycle {
                 self.os_pending.push(OsPending {
                     func_idx: self.builder.current_func_idx as u32,
    ```
    - **Depends changed (2026-11-18, by this task's measurement):** added id:mztqb and id:mrdtf, the declarations the check refuses; it cannot land before them.
    - **Left here:** apply the patch; add tests under `tests/language/memory/provenance/` (a narrowing `#[borrows()]` refused, a wider one accepted, a `&self` method returning a view of `self` accepted, the `&self` default passing another parameter refused, its trait form refused); the `#[stores]` wider-contract change and the `err_stores_attribute_false.zrl` expectation (stop and report it); `make test`, `make preflight-changed` with the differential. `gap_44`, `gap_99`, `gap_100` and `gap_101` flip when the rule is on by default (id:z0065, id:z0012), not here.
    - **Decision (2026-11-18, the maintainer):** three tiers, recorded in `doc/design/provenance.md` §3, _Checked contracts_. (1) Inferred: with no declaration, the body's ties are added to the elision default (body plus default; body-only waits for id:f81f3 and the differential). (2) Checked: `#[borrows(..)]` may name more than the body returns, never less. (3) Trusted narrowing: `#[unsafe(borrows(..))]` (id:akapm). This replaces the earlier plan of refusing the `&self` default with "add `#[borrows(self, x)]`", which put the notation on every user.
    - **Landed: tier 1, git:21658fa.** `os_infer_ties` adds the body's ties (the same set `os_call` reads, over parameters whose type can hold a reference) to `ret_ties` for any function with a body and no declaration. `ILFunction.ties_inferred` makes the `.zri` write them as `#[borrows(..)]`. `ILFunction.os_in_cycle` with `os_depth` makes the borrow checker read a call into an unfinished recursive cycle as tied to every argument. The one `src/` refusal (`lower_zir/expr.zrl`, `lowered.set(ai, self.check_arg_against(lowered.as_slice()[ai], ..))`) writes the converted arguments into a second vector. gap_100 and gap_101 are flipped to `compile_reject`.
      - **Cost (`build/z11/cost.sh build/zoril`):** 0 default-build refusals over the five roots and the 739 test programs that compile by default. Variant B, which also widens explicit declarations (the union in default mode), refuses 934: `src/main.zrl` 900, zilc 30, zbuild 4. So the tree's narrowing declarations carry weight, and each needs its own decision (id:mztqb, id:mrdtf).
      - **Sibling routes** (`build/z11/p/`, base = git:e14d03d's compiler): `&mut self` (`mutself`), an aggregate result (`aggr`), self-recursion (`cycle_inner`) and mutual recursion (`cycle_mutual`) were accepted by the base (exit 77 or a use of a cleared Vec's view) and are refused now. A closure (`closure`), a generic identity and `iter().map(..)` were refused already. A call through a generic `via<T: Pick>(t: &T, x)` is refused by the free function's own default, so the trait test calls the impl directly.
      - **Across a `.zri`:** `tests/modular/iface_attrs/lib_ties.zrl` with `reject_ties_inferred.zrl` and `accept_ties_inferred_twin.zrl`; `scripts/test_interface_attrs.sh` checks that `pick` gets `#[borrows(self, x)]` and `view` gets none.
      - **Take-outs:** inference off (scratch `build/z11/src_t1`) fails `inferred_ties_self_method_other_param_refused`, `_mut_self_..`, `_aggregate_result_refused` and `_trait_method_..` (direct call). The cycle rule off (`build/z11/src_t2`) fails `inferred_ties_self_recursion_refused` and `_mutual_recursion_refused`. The interface line off fails `test_interface_attrs.sh` ("the interface lost the ties pick's body adds to the default"), and zbuild then accepts `reject_ties_inferred.zrl` while whole-program refuses it.
      - **Checks:** `make test` `Total: 3852 run, 3852 passed, 0 failed, 106 skipped (139.3s)`; `sh scripts/run_safety_matrix.sh` "All probes complete: 475/527 passed. Mismatches: 0"; `make preflight-changed` below.
      - **Preflight (2026-11-18, tree at git:3cf6b86):** `REJECT_DIFF_NO_CACHE=1 make preflight-changed PREFLIGHT_BASE=e14d03d`, rc=0: "All mutations caught."; `[PASS] fuzz-calibrate: all 23 calibration programs are in their fixed state (21 refused, 2 accepted with one drop)`; `reject-diff: base verdicts: fresh (no cache)` and `[PASS] reject-diff: 0 newly accepted (none that must be refused, or all allowed), 2542 newly refused, of 69167 programs against e14d03d9cbe8331d4dc753f8cd78d3d0c7f93c31` (2538 unsafe store-grid cells and gap_100/gap_101 whole-program and under zbuild; no safe twin); checked build `Total: 1477 run, 1477 passed, 0 failed, 0 skipped (108.2s)`; git group `Total: 8 run, 8 passed, 0 failed, 0 skipped (102.2s)`; "All performance thresholds within tolerance of baseline." An earlier run failed only in the `tool-versions` scenario, because docs were edited during it (the tree was dirty). `make test-changed BASE=21658fa` after the record and doc commits: `Total: 3852 run, 3852 passed, 0 failed, 106 skipped (139.2s)`.
      - **Store grid re-recorded:** git:4ef0cf0 removes exactly the 2538 cells the differential reported (class report 51 -> 35: the method, self_method and trait_method paths and the call_method carrier). git:1e1805c removes 106 entries of `store_grid_modular_prov_twin_rejections.txt` that were already stale before this change: recorded with e14d03d's compiler, which changes only that file. The fuzz record is stale after this `src/` change (`bench/fuzz/README.md`).
      - **A gap the design accepts, beside the cycle rule:** a body lowered while a cycle is open, which calls a member that has finished but is still waiting for the fixpoint, reads that member's ties through `os_in_cycle` (all arguments). The origin rules of such a body still read the member's partial summary. That predates this change, and is noted for id:z0065's measurement.
    - **Depends changed (2026-11-18):** added id:akapm, the tier-3 form the remaining narrowings need.
    - **Left here (tier 2):** a declaration narrower than the body is refused (the patch above, `os_check_ties`, reduced to the `has_borrows` branch); the `#[stores]` wider-contract change and the `err_stores_attribute_false.zrl` expectation (stop and report). These land after id:mztqb and id:mrdtf. gap_44 and gap_99 flip when the tree's narrowings are settled. The **Patch** above predates git:21658fa (it adds `os_check_ties` where `os_infer_ties` now stands), so it no longer applies: write the tier-2 check fresh as one more branch of `os_infer_ties` (a function with `has_borrows` whose body ties are not all in `ret_ties`), refusing under `--provenance` as the patch did.
    - **Found by id:mztqb (2026-11-18):** a `#[unsafe(borrows(..))]` callee's trust does not reach its callers under `--provenance`. `os_call` builds the call's result from the callee's body summary, so `Args.next`, which returns `self.get(..)` of a trusted `Args.get`, is still tied to `self` and needs a mark of its own. **Decide here:** whether the call reads a `borrows_trusted` callee's `ret_ties` instead of its body ties (reproducer and counts under id:mztqb's **Re-measured**).

- [ ] +safety +tests +AI-D @provenance B3c A safe function may not hide a store behind a bare `extern` or a raw-pointer write: it declares `#[stores(..)]` id:f81f3
    > **Created:** 2026-11-18
    > **Branch:** `provenance`

    - **Split from:** id:z0011, whose **Blind spot** bullet (id:z0049's review) and **Added by id:z0073's decision** bullet (case B, the maintainer, 2026-11-14) describe one rule: a safe function may not hide a store behind an operation the checker cannot read. Split off because id:z0011's ties check and its 13 + 85 sites fill a session already. The task text there allows this ("If that count makes this task more than a session, split the rule into a task of its own directly after this one").
    - **Placed:** directly after id:z0011, as that bullet asks.
    - **Rule:** a safe function that passes a pointer derived from a parameter to an `extern` that declares no effect, or whose `unsafe` block writes a value that can hold a reference or a slice through a raw pointer (one it was given, or one an argument holds: `unsafe { *self.p = r; }`), must declare `#[stores(..)]` (or `#[borrows(..)]`) naming what it stores and where, or it is a compile error. The declaration is then a trusted claim (`doc/SAFETY.md` §4.2), and the caller applies the call store rule to it.
    - **Probes:** id:z0060's reproducer with id:z0060's fix taken out; `put` with and without the declaration (`build/z76/cx.zrl` in id:z0076's text); a caller passing `&x` of a local where `g` reaches outside the frame (refused once declared); the same store of a plain integer (no declaration needed).
    - **Measure first:** count the functions in `stdlib/`, `src/` and `tools/` that newly need a declaration, with the rule as a warning, before making it an error.

- [ ] +safety +tests +AI-D @provenance L2a A call summary records which arguments the callee may release id:bfcvm
    > **Created:** 2026-11-17
    > **Branch:** `provenance`
    > **Depends:** id:dhded
    > **Placed:** directly before id:kqp9n (L2), which it blocks: L2's release tier conflicts only with a release, and it learns of a release from this fact.

    - **Design:** `doc/design/provenance.md` §3.1, item 2 (git:bdfcac6). The summary gets one new fact, `releases i`: the callee may release storage argument `i` reaches. It is computed from bodies, as the store edges are. A body releases `i` when it calls a releasing primitive on memory whose origins include `ParamAddr(i)` or `ParamContents(i)`, or calls a function whose summary releases an argument carrying them. A call through a `fn` value with no known callee releases everything its arguments and environment reach.
    - **Decide first, and record here:** how the releasing primitives are marked. They are `zoril_allocator_free` (`stdlib/mem_raw.zrl`, the only call to it in `stdlib/` is `Vec.free`) and the arena's reset and free (`stdlib/mem.zrl`: find each body that ends an arena's allocations). Either a trusted attribute on those few bodyless or `unsafe` items, as `#[fresh]` is (§3, _Raw operations_), or something else the design note's rules allow; no list of names in the checker. An `extern` releases nothing unless it is marked.
    - **Do:** compute `releases` in the origin pass (every mode: `os_pass_pending` runs with the rules off by default), keep it through a recursive cycle's fixpoint, write it into the `.zri` beside the store edges, and print it with `--emit-origins` (`releases 0`). Nothing reads it yet, so no program's verdict changes.
    - **Checks:**
        - C1: golden tests under `tests/language/memory/origins/` whose `--emit-origins` shows `releases 0` for `Vec.free`, for each arena reset and free, for `fn kill(v: &mut Vec<i32>) { v.free(); }`, and for a two-level wrapper of `kill`; and no `releases` for `Vec.push` (growth keeps the old buffer: `Vec.grow_to` frees nothing), a getter, and `fn put(out: &mut [i32], v: &Vec<i32>) { *out = v.as_slice(); }`.
        - C2: a recursive pair, one member freeing its argument, where both members' summaries release it.
        - C3: a `.zri` round trip under `tests/modular/iface_attrs/`: a module's releasing function, imported, prints the same `releases` as when compiled whole-program.
        - C4: take the primitives' mark out and watch C1's `Vec.free` golden fail; take the cycle step out and watch C2 fail.
        - C5: no verdict changes: `make test` and `REJECT_DIFF_NO_CACHE=1 make preflight-changed`, quoting the `Total:` lines and `reject-diff: base verdicts: fresh (no cache)` with 0 newly accepted and 0 newly refused.

- [ ] +safety +tests +AI-D @provenance L2 A view stored through a parameter keeps what it views borrowed for the rest of the body (gap_87) id:kqp9n
    > **Created:** 2026-11-14
    > **Branch:** `provenance`
    > **Depends:** id:dhded, id:bfcvm
    > **Check-in:** stop for review after it: a fix to a safety rule.

    - **Placed:** after L1 (id:dhded), which settles its rule, and before id:z0044, its caller-side twin.
    - **Closes:** `gap_87_view_stored_through_param_outlives_free`.

    - **Found (2026-11-14, a review of the plan; probe in git:172c77e on `main`):** `fn k2(out: &mut [i32], v: &mut Vec<i32>) { *out = v.as_slice(); v.free(); }` is accepted by `build/zoril` at git:a662fda (built with `scripts/build_zrl.sh`, run: exit 77 where the buffer held 42) and compiles under `--provenance` on `provenance` at git:92bb15f (`build/zoril --provenance --emit-zil`, rc 0, not run). Accepted the same way, exit 77 on `main`:
      - `fn k2(out: &mut Vec<[i32]>, v: &mut Vec<i32>) { out.push(v.as_slice()); v.free(); }`
      - two callees: `fn fill(h: &mut H, v: &mut Vec<i32>) { h.s = v.as_slice(); }`, `fn kill(v: &mut Vec<i32>) { v.free(); }`, `fn both(h: &mut H, v: &mut Vec<i32>) { fill(h, v); kill(v); }`
      - one parameter: `struct P { a: Vec<i32>, s: [i32] }`, `fn poison(p: &mut P) { p.s = p.a.as_slice(); p.a.free(); }`
    - **Refused today (the twins to keep refused):** the one-parameter form on a local (`p.s = p.a.as_slice(); p.a.free();` in `main`: `cannot mutably borrow 'p.a' while it is already borrowed`), and `let s = v.as_slice(); v.free(); return s[0];`.
    - **Not shown:** `v.push(..)` in place of `v.free()` compiles and the run returned 42 (the old buffer was not reused), so the reallocation route is accepted but not demonstrated; L1 probes it.
    - **Route class:** a view of what a parameter reaches, stored into what a parameter reaches, then invalidated in the same body. id:z0044 does not close it as written: it carries the borrow "to the local the pointer refers to", and here there is none.
    - **Not ready:** L1 writes this task's **Do:** and numbered **Checks:**. They include: `gap_87` flipped to `compile_reject` with its Known gaps entry and `doc/SAFETY.md` §6 class (M) removed; the three sibling forms above as `compile_reject` probes; an accepted twin for each (the store with no later invalidation; the invalidation before the store); the fix taken out and `gap_87` watched to run (exit 77); the rejection differential with every newly refused program listed; `make test` and `make preflight-changed`, each `Total:` quoted.

    - **Ready (2026-11-17, L1 = id:dhded):** the **Not ready** bullet above is answered by `doc/design/provenance.md` §3.1 (git:bdfcac6). This task is holders one and two (the in-body half). id:z0044 is holder three (the caller's half).
    - **Closes (from L1):** `gap_87`, and from id:z0044's former list `gap_37` and `gap_43`, which are in-body (a local `&mut` and a `Box`).
    - **Do:**
        1. In `check_assign`'s two arms for a write through a pointer (`place_writes_through_pointer`; L1's census found no other in-body site), read the destination reach of the written place from the function's origin sets. The origin pass runs on every body in every mode (`os_pass_pending`), so the sets exist without `--provenance`; check that they are computed before the borrow checker runs on the body, and make them so if not.
        2. Holder one: for each `Frame(L)` in the reach, `L` receives the value's borrows, as `w.s = ..` gives them to `w` (the same propagation, `direct` false). These are strict-tier borrows: any `&mut` use of the borrowed place conflicts, as today.
        3. Holder two: a `Param`, `Static`, `Raw` or `Unknown` origin in the reach gives the value's borrows to the frame's outside holder, live until return. These are release-tier borrows: only a release conflicts. A release is a call whose summary releases an argument reaching the borrowed place (id:bfcvm), an `@drop`, or a move or whole overwrite of the owner. Mark the tier on the borrow (a field of `ActiveBorrow`), so that `borrow_counts` and the conflict checks can tell the two apart.
    - **Checks:**
        - C1: `gap_87` refused, with its expectation flipped to `compile_reject`, its Known gaps entry removed and class (M) removed from `doc/SAFETY.md` §6 and §6.1 (no probe count touched).
        - C2: `gap_37` and `gap_43` refused and flipped the same way; class (G)'s text keeps only the routes still open.
        - C3: `compile_reject` probes for L1's p4 (the trait method, `build/provenance/build/dh/p4_trait.zrl`), `out.push(v.as_slice()); v.free();`, and the one-parameter `p.s = p.a.as_slice(); p.a.free();`.
        - C4: accepted twins as tests, each built and run with its exit quoted. The store with no later release; the release before the store; `*out = v.as_slice(); v.push(1);` (release tier: growth is no release); and the field read before `a.reset()` for `gap_37` and `gap_43`. Plus a refused strict-tier twin: `let r = &mut w; r.s = v.as_slice(); v.push(1); w.s[0]`, refused as `w.s = v.as_slice()` is today.
        - C5: the compiler builds as before. `make` succeeds with `src/`'s and zilc's 14 intern-table stores accepted (`self.file_path = self.intern_table.lookup(..)`, which L1's strict scratch refused 142 times), and `build/z97/measure.sh` reports no new error in `tests/` or `stdlib/`.
        - C6: take holder two out and watch `gap_87` build and run 77. Take the tier out (count every borrow as strict) and watch C5's build fail on the first intern-table store.
        - C7: `make test`; `REJECT_DIFF_NO_CACHE=1 make preflight-changed` with `reject-diff: base verdicts: fresh (no cache)` quoted, and every newly refused program listed with its reason. This rule acts in the default mode too, so `main`'s behaviour changes when the branch merges; say so in the completion note.

- [ ] +safety +tests +AI-D @provenance id:z0044 B0.1 A value stored into a local's field through a pointer to the local keeps its borrow
    > **Created:** 2026-11-03
    > **Branch:** `provenance`
    > **Check-in:** stop for review after it.
    > **Depends:** id:z0010, id:dhded, id:bfcvm, id:kqp9n

    - **Closes:** `gap_37_local_mutref_field_reset`, `gap_38_param_field_reset`, `gap_39_method_self_field_reset`, `gap_43_box_field_reset`.
    - **Depends changed (2026-11-14, the maintainer, in a review of the plan):** added id:dhded (L1), the liveness model: L1 decides whether this task's per-local borrow is the rule and rewrites its Do and Checks.

    - **Scope (narrowed to intra-frame liveness, 2026-11-03):** the frame-escape siblings (`gap_40`–`gap_42` and `gap_45`) are handled by id:z0048/id:z0012's origin sets. This task fixes intra-frame `Arena::reset` / `free` / `@drop` liveness (`ActiveBorrow` in `src/check_zir.zrl`), where a slice written into a local struct's field or a `Box`'s contents through a local `&mut`, through a callee's `&mut` parameter, through `self` in a `&mut self` method, or through `*b` on a `Box` is skipped today (`place_writes_through_pointer`), letting `a.reset()` pass while the field is read afterwards.
    - **Do:** carry the stored value's borrows to the local (or `Box` local) the pointer refers to: for a local `&mut` or `Box` deref, through the pointer's borrow/ownership of that local; for a callee, through id:z0010's pairwise `i -> j` store summary (`#[stores(..)]` checked in id:z0011). Probe the sibling routes: a `&mut` held in a struct field, a reborrow, a closure capturing `&mut w` across `a.reset()`, and a trait method; also verify `gap_44_borrows_attr_reset` is rejected once checked `#[borrows()]` is active.
    - **Found by id:z0047 (pre-existing over-rejection):** `fn f(view: [i32]) -> i32 { let mut w = ...; let r = &mut w; r.s = view; ... }` called with stack `f(&data)` is refused today by `src/summary_pass.zrl`; confirm id:z0012's retirement of `summary_pass.zrl` removes that refusal without reopening any reset hole.
    - **Probes:** `gap_37`, `gap_38`, `gap_39` and `gap_43` flip to `compile_reject`, with an accepted twin for each (the field is read before `a.reset()`). Check the over-rejection recorded on id:z0017 does not grow.
    - **Verification:** `make test`, `make preflight-changed`, the rejection differential; `bench/fuzz/README.md` stays stale for `src/`. Stop for review.
    - **Promoted (2026-11-14, the maintainer's request):** from `future.tm.md` with the whole provenance series, in its order there, after the open soundness holes on `main` and before the ZIL series. The series' notes moved to **Sprint notes** ("The provenance series").

    - **Rewritten by L1 (id:dhded, 2026-11-17; design `doc/design/provenance.md` §3.1, git:bdfcac6):** this task is now holder three, the caller's half. The in-body routes moved to L2 (id:kqp9n): `gap_37` (a local `&mut`) and `gap_43` (a `Box`). The **Do:** and **Probes:** above are superseded by the two bullets below, and the `summary_pass.zrl` note above stands.
    - **Closes (from L1):** `gap_38`, `gap_39`, `gap_96` (found by L1), and `gap_87`'s two-callee form (`fill(h, v); kill(v);`). `gap_44` is id:z0011's: the `#[borrows()]` it trusts is a declaration checked against the body, not a holder. So this task no longer depends on id:z0011 (**Depends changed** below).
    - **Do:** at a call, for each store edge `i -> j` of the callee's summary, every local whose `Frame` the destination reach of argument `j` has receives the borrows argument `i` carries. When the edge stores what `i` reaches, each also receives a borrow of the place argument `i` refers to. A target outside the caller's frame goes to the caller's outside holder (L2). All of these are release-tier borrows (L2's mark): they conflict only with a release, so a self-edge `i -> i` (`p.lex(); p.lex();`) is accepted, and `p.lex(); p.free_all();` with `p` still read is refused when `free_all` releases `p`. A call through a `fn` value with no known callee counts as storing every argument into every other, as the escape rules count it.
    - **Checks:**
        - C1: `gap_38`, `gap_39` and `gap_96` refused, each flipped to `compile_reject`, with its Known gaps entry removed and class (G)'s text in `doc/SAFETY.md` §6 and §6.1 updated (no probe count touched).
        - C2: `gap_87`'s two-callee form as a `compile_reject` probe (`fn both(h: &mut H, v: &mut Vec<i32>) { fill(h, v); kill(v); }`).
        - C3: accepted twins as tests, built and run with their exits quoted. `put(&mut s, &v); v.push(1); s[0]` (release tier); `put(&mut s, &v); kill(&mut v);` with `s` not read after; a method storing a view of `self`'s own `Vec` into `self`, called twice; and the reset before the call for `gap_38`.
        - C4: the measurement L1 left to this task: the programs of `tests/`, `stdlib/` and the four tool roots the base accepts and this refuses, read one by one in the completion note. The design's claim is that the release tier refuses none that are safe.
        - C5: take the summary step out and watch `gap_96` build and run 77; make the borrows strict and watch C3's method-called-twice twin be refused.
        - C6: `make test`; `REJECT_DIFF_NO_CACHE=1 make preflight-changed` with `reject-diff: base verdicts: fresh (no cache)` quoted and each newly refused program listed. This acts in the default mode, as L2 does.
    - **Depends changed (2026-11-17, L1):** added id:kqp9n (L2, for the outside holder and the tier mark) and id:bfcvm (`releases`). Removed id:z0011, which this task needed only for `gap_44`; `gap_44` is id:z0011's own.

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
    - **Probes:** every `known_gap` probe the new rules refuse flips to `compile_reject` (at id:z0059: all escape gaps except the liveness ones `gap_37`, `gap_38`, `gap_39`, `gap_43`, `gap_44`; since id:z0060 also `gap_56`, since id:z0061 `gap_57` and `gap_58`, since id:z0062 `gap_59` to `gap_62`, since id:z0072 `gap_63`; re-check each), with its Known gaps entry in `doc/spec/safety_model.md` and line in `doc/SAFETY.md` §6 removed. Accept probes newly refused: none allowed without a task.
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
    - **Flip probes and twin lists (including id:z0045's):** flip all closed `known_gap` probes (`gap_07`, `gap_11`, `gap_13`, `gap_16`, `gap_18`, `gap_21`, `gap_23`, `gap_26`, `gap_27`, `gap_28`, `gap_29`, `gap_32`, `gap_33`, `gap_36`, `gap_40`, `gap_41`, `gap_42`, `gap_44`, `gap_45`, `gap_47`, `gap_48`, `gap_49`, `gap_50`, `gap_51`, `gap_52`, `gap_53`, `gap_54`, `gap_55`) to `compile_reject` and remove their Known gaps entries in `doc/spec/safety_model.md` and `doc/SAFETY.md` §6. Fold in id:z0045: remove the 3402 `ref_{let,identity,phi}` twins (and any id:z0017 twins newly accepted when `summary_pass.zrl` is retired) from `bench/fuzz/store_grid_twin_rejections.txt`, flip `read_through_{ref,identity,phi}.zrl` from `expected compile fail` to running tests, add an `accept` probe for `id:z0045` and a regression test returning `s.as_slice()` from `String.with_capacity(a, cap)` (`a: &Arena`). Because retiring `summary_pass.zrl` and `local_storage_external` accepts more safe programs, run `scripts/check_reject_diff.sh <base>` and list every newly accepted program class in the completion note (none may be unsafe). Update `doc/SAFETY.md` §2.3 and §5–§6, `doc/spec/surface_syntax.md` (`#[borrows]`/`#[stores]`), `README.md`, `KNOWN_ISSUES.md` and `bench/fuzz/store_grid_expected_failures.txt`.
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
