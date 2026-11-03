# One provenance model for the store and return rules

This note is the design that the hardening series implements: Z-0009 (origin sets and the store and return rules, behind `--provenance`), Z-0010 (one call summary), Z-0011 (declarations checked against the body) and Z-0012 (the flag on, the old classifiers deleted). Its liveness part is in place for writes into a local's own fields; writes through a pointer to the local are Z-0044. It describes what decides an escape today, why that design keeps leaving holes open, the model that replaces it, how each known hole maps onto the model, what the model will newly reject, and how it lands.

## 1. What decides an escape today

Four mechanisms, at two IR levels, answer overlapping questions:

- **Flow-sensitive borrows (`ActiveBorrow`: borrower local, borrowed place)**
  - Where: `src/check_zir.zrl`, ZIR
  - Decides: conflicts and liveness inside the frame: use after `free`/`reset`/`@drop`/move, the strict reborrow rule, arena epochs
  - Summary it writes: none
- **The buffer-escape rule (`check_borrow_escapes_frame`, `local_storage_external`, `local_is_external_target`, `place_outlives_frame`, `rvalue_storage_external`, `is_collection_type_name`)**
  - Where: `src/check_zir.zrl`, ZIR
  - Decides: whether a returned or stored value carries a borrow of heap storage the frame owns (a collection, a box, an arena) and whether the destination outlives the frame
  - Summary it writes: `stores_storage`/`store_targets` (`storage_walk_zir`)
- **The region verifier (`storage_facts`, `storage_param`, `check_call_stores_stack`, `check_borrows_claim`, `check_fn_value`)**
  - Where: `src/verify.zrl`, ZIL
  - Decides: whether a _stack_ address escapes; whether `#[borrows]`/`#[stores]` claims hold
  - Summary it writes: `ret_storage`, and `stores_storage` again (**overwriting** the ZIR one)
- **The interprocedural summary pass**
  - Where: `src/summary_pass.zrl`, ZIL
  - Decides: `escape`/`stash`/`ret_stack` per parameter, for calls and the `.zri`
  - Summary it writes: `summary_escape`/`summary_stash`/`summary_storage`

`ret_ties` (which parameters a returned reference borrows) is a fifth input, set in `src/driver/module.zrl` from `#[borrows(..)]` or the elision default, never from the body.

So one property - _an address that is only valid while this frame (or something it owns) is live must not leave it_ - is split by kind of storage (heap owned by a local: ZIR; stack slot: ZIL), checked by two analyses with different precision, and summarised three times in 64-bit masks that are combined by overwriting.

## 2. Why the holes keep coming

The probes named here are in `bench/safety_matrix/probes/`; `doc/spec/safety_model.md` lists the ones still open under "Known gaps".

1. **Unknown means allowed.** The classifiers return `false` ("not external", "not carrying") for any shape they do not recognise: a chain of more than 8 copies (`gap_10`), a call returning a struct rather than an enum (`gap_08`), a closure call (`gap_29`), a field write (`gap_09`), a whole assignment to a closure capture (`gap_12`), a type nested in an enum (`gap_13`, `gap_18`, `gap_23`, `gap_36`). Fixing a shape teaches the classifier that shape; the next unrecognised one stays open.
2. **Definitions are chased backwards, per whole local.** `local_storage_external` and `local_is_external_target` search the function for the `let` or whole assignment that defined a local and recurse, so a field write (`sm.r = out`, `w.s = view`), a second assignment, or a value that arrives through a loop is not seen.
3. **Summaries disagree and are computed once.** Three writers, an `i != j` filter (`gap_07`), no bit for parameter 64 onwards (`gap_27`, `gap_33`), no fixpoint over recursive calls (`gap_28`), declarations (`#[borrows]`, the `&self` default) trusted instead of checked (`gap_30`), the later writer replacing the earlier, and the ZIL writer blind to an aggregate passed by value (`gap_32`).
4. **Name lists.** `is_collection_type_name` decides by name which types own storage.

## 3. The model

**Origins.** Every address a value can hold has an origin:

- `Frame(L)` - the stack slot of local `L`, or storage `L` owns (a `Vec`/`String`/`HashMap` buffer, a `Box`, an `Arena`'s blocks, a closure environment). By-value parameters are locals. Inside a closure, an _owned_ capture is `Frame(c)` too: its storage dies when the closure frees or grows it, whatever the frame does.
- `Param(i)` - memory reached _through_ parameter `i` (the referent of a reference parameter, what a by-value aggregate parameter's fields point to). A closure's by-reference capture is a `Param`-like origin of the environment.
- `Static` - globals, string literals, other `static` data.
- `Unknown` - anything the analysis cannot classify. **`Unknown` is treated as `Frame` when it is the value and as external when it is the destination**, so it always rejects.

**Two sets per local.** `O(L)`: the origins of addresses `L` holds (in any field: field-insensitive). `S(L)`: the origins of the storage `L` owns - `Frame(L)` for a fresh `Vec::new()`/`box`, the arena argument's origins for `Vec::new_in(a)` (from the constructor's summary), `S(src)` when `L` is moved or copied from `src`. Both are computed **forwards** to a fixpoint over all statements (flow-insensitive: a local's set is the union over every assignment; a reassigned local keeps its earlier origins, which is conservative and documented).

**Transfer.** For `x.p1..pn = rv` (including `n = 0`, any projections, not through a deref): `O(x) |= O(rv)`, `S(x) |= S(rv)`. Reading any projection of `x` yields `O(x)`. `&p`/`&mut p` of a frame place yields `Frame(p.base)`; through a reference `r`, it yields `O(r)`. A call yields, for each argument `i` the summary ties to the result: `Frame`/address origins of the argument if the result points into its own storage (`ret_storage`), `S(arg) | O(arg)` if it points to what the argument reaches (`ret_ties`). A call through a `fn` value or an `extern` without a summary yields `Unknown`, and counts as storing every reference argument into every other.

**The rules.**

- _Store_: `*r = v`, `r.f = v`, `r[i] = v` through a reference `r` (or into a closure's capture, or a global): if the destination's origins `O(r)` contain anything but `Frame` origins of this frame - a `Param`, a `Static`, a capture environment, or `Unknown` - then `O(v)` must contain no `Frame` and no `Unknown`.
- _Return_: `O(ret)` must contain no `Frame` and no `Unknown`.
- _Call_: for each `i -> j` in the callee's store summary, the caller applies the store rule with value `O(arg_i)` (or `S(arg_i) | O(arg_i)` when the callee stores what `i` reaches) and destination `O(arg_j)`; `j` may equal `i`.

**Liveness** stays where it is: the flow-sensitive `ActiveBorrow` set keeps deciding use after `free`/`reset`/`@drop`/move and the strict reborrow rule, with one change - a write into a projection of `x` adds the right-hand side's borrows to `x` (field-insensitive), instead of dropping them. This change is in place for a write into a local's own fields; a write that reaches the local through a pointer (a local `&mut`, a `&mut` parameter, `self` in a method) does not add them yet (Z-0044).

**The summary** is the same analysis read at the function's edges, with `Param(i)` seeded for each parameter: `ret` = the parameters in `O(ret)`; `stores i -> j` = every store whose value carries `Param(i)` into a destination carrying `Param(j)` (or a global). One computation, on ZIR, written to the function and to the `.zri`; strongly connected components of the call graph iterate from empty to a fixpoint (the sets only grow); bit 63 means "parameter 63 or later" in both directions. `#[borrows(..)]`, `#[stores(..)]` and the `&self` default are **checked** against what the body proves: a declaration may list more than the body does (a wider public contract), never less, except through a reviewed `unsafe` construct. The ZIL verifier keeps its stack-address check as a second net that may only _add_ rejections; it no longer writes a summary.

**Deleted:** `local_storage_external`, `local_is_external_target`, `rvalue_is_external_target`, `place_outlives_frame`, `rvalue_storage_external`, the depth limits, `is_collection_type_name` (ownership of storage comes from the type's structure: a type owns storage if it contains a `Box`, an owning raw pointer, or a type that does), the `i != j` and `& !target` filters, `storage_walk_zir`'s separate mask logic, and the summary role of `storage_facts` and `summary_pass.zrl` (the `.zri` fields stay, filled from the one summary).

**Open question, for Z-0009 to settle.** The transfer above says what a read through a projection of a local yields, but not what a read _through a reference_ yields. Taken literally, `let r = &c; take_ref(r)`, where `take_ref` returns the view `c` holds, gives the result `O(r) = Frame(c)` and is refused, while the safe answer is `O(c)`, the origins of what `c` holds. This is the over-rejection Z-0045 records (a reference to a local carrier passed through a `let`, an identity call or a phi). The model needs a rule for it - for example, a read through `r` yields `O(L)` for each `Frame(L)` in `O(r)`, and stays `Param` or `Unknown` otherwise - or Z-0009 inherits that over-rejection.

## 4. Every known hole against the model

Closed probes are fixed today by the classifiers this model deletes; the model must keep them closed. Open probes are `known_gap` today.

- **`gap_01`, `gap_02`, `gap_03`** (closed)
  - Shape: a view carried in a struct field, tuple slot or array slot of a local, then stored out
  - Caught by: field-insensitive transfer: `O(w)` gets `Frame(v)`
- **`gap_34`, `gap_35`** (closed); **`gap_37`, `gap_38`, `gap_39`** (open)
  - Shape: `w.s = view; a.reset(); w.s[0]`; the same with the write made through a local `&mut`, a `&mut` parameter or `self`
  - Caught by: liveness: a projected write adds the borrow to `w`; through a pointer, to the local the pointer refers to (Z-0044)
- **`gap_12`** (closed); **`gap_11`** (open)
  - Shape: a whole assignment to an owned capture; a store through a captured `&mut`
  - Caught by: the destination is the capture environment (external)
- **`gap_31`** (closed)
  - Shape: `Bundle { tag, a }` or `(a, tag)` makes the arena look external
  - Caught by: `S` per local, not "any operand": `S(b) = Frame(a)`
- **`gap_08`** (closed)
  - Shape: a call returning a struct holding a `&mut`
  - Caught by: `O(sm)` from the call's ties = `Param(h)`
- **`gap_29`** (open)
  - Shape: a closure call returning a captured `&mut`
  - Caught by: a `fn`-value result is `Unknown`, external as a destination
- **`gap_09`** (closed)
  - Shape: `sm.r = out; *sm.r = view`
  - Caught by: forward transfer into a projection
- **`gap_10`** (closed)
  - Shape: ten copies of `out`
  - Caught by: a fixpoint has no depth limit
- **`gap_07`** (open)
  - Shape: one tuple parameter holds destination and value
  - Caught by: `i -> i` allowed in the summary
- **`gap_28`** (open)
  - Shape: mutual recursion
  - Caught by: the strongly-connected-component fixpoint
- **`gap_17`, `gap_22`** (closed); **`gap_27`, `gap_33`** (open)
  - Shape: the value is the 65th parameter
  - Caught by: the overflow bit
- **`gap_04`, `gap_05`, `gap_06`, `gap_30`** (closed)
  - Shape: a method, `&self` method or trait method returning its argument; a `#[borrows()]` function returning its argument
  - Caught by: ties computed from the body; declarations checked
- **`gap_14`, `gap_15`, `gap_19`, `gap_20`, `gap_24`, `gap_25`** (closed)
  - Shape: a stack reference, element reference or stack-capturing closure stored out through a by-value struct, a closure parameter or a closure call
  - Caught by: `Param(w)` for what `w` holds; one summary, also to the `.zri`; a closure call stores as a `fn`-value call does
- **`gap_13`, `gap_18`, `gap_23`, `gap_36`** (open)
  - Shape: the same values stored out through an enum payload, or taken out of one in a `match` arm
  - Caught by: building an enum value is a write of its payload, so `O` carries the payload's origins, and a `match` binding reads them back
- **`gap_16`, `gap_21`, `gap_26`** (open)
  - Shape: the same values stored out through a `fn`-value call
  - Caught by: a call through a `fn` value stores every reference argument into every other (`Unknown`)
- **`gap_32`** (open)
  - Shape: a view of a by-value collection parameter stored out
  - Caught by: a by-value parameter is `Frame(v)` (see §5)
- **`@drop(s.a)`, `@drop(*r)`**
  - Caught by: **not covered**: an ownership rule, outside this model
- **A `static mut` of a type holding a reference**
  - Caught by: **not covered**: type classification, reachable only through `unsafe`
- **The strict reborrow rule**
  - Caught by: **not changed**: liveness
- **Copy, casts, FFI, borrows of a `static mut`**
  - Caught by: **not in scope**: other rules

## 5. What it will newly reject (to measure, not assumed)

- A local reassigned from a frame view to a `static` slice, then stored out (flow-insensitive sets).
- A struct with one frame-owned field and one parameter-derived field, whose parameter-derived field is stored out (field-insensitive sets). If common, make `O` field-sensitive for direct fields only.
- By-value owning parameters (`v: Vec<i32>`) are `Frame(v)`. Today they count as external, so a view of one stored out is accepted (`gap_32`); under the model it is rejected. Today it is a leak, not a crash, because collections are not freed at scope end; with a `Box` parameter it is a stack-address error already.
- Every `#[borrows()]` and `#[stores(..)]` that declares less than the body does. The tree has 82 `#[borrows()]` declarations (`src/`, `stdlib/`, `tools/`), such as `Lexer.text_from`, whose result is a view of source text in the compilation's arena and so outlives the lexer it is read through; each is either proved by the body or becomes an explicit, reviewed exemption.

## 6. How it lands

Behind a flag. The new analysis runs beside the old one under `--provenance`, and reports in warning mode (`--provenance=warn`) on the whole tree (`src/`, `stdlib/`, `tools/`, `corpus/`). The store grid (`scripts/check_store_grid.sh`) is the definition of done: every unsafe cell rejected, the over-rejected twins listed. Then the flag becomes the default and the old classifiers are deleted. In tasks:

- **Z-0009 (B1):** the origin sets and the return and store rules on ZIR, behind the flag, reading the existing summaries.
- **Z-0010 (B2):** the one summary (fixpoint, overflow bit, `i -> i`, `.zri`); the ZIL summaries retired.
- **Z-0011 (B3):** declarations checked, and the exemptions made explicit.
- **Z-0012 (B4):** measure, make the flag the default, delete the old classifiers and the name list.

The self-hosting compiler is itself checked by the new rules, so Z-0009 and Z-0011 measure `src/` first. The ZIL stack-address check stays throughout, so no step weakens what is caught today.

## 7. The alternative

**Three cross-cutting fixes inside the current code:** every classifier fails closed; projected writes and aggregates use the union; one summary with a fixpoint, the overflow bit, `i -> i`, checked declarations and the ZIL verifier add-only. It keeps the backward definition chase, which cannot see a field write without becoming a forward analysis, and it keeps heap and stack escapes in two analyses. Its three fixes converge on this model's analysis anyway (a forward, field-insensitive, fail-closed fact per local) while leaving the four mechanisms and the overlapping summaries in place, so the model replaces them instead.
