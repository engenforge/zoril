# Zoril Intermediate Representation (ZIR) Specification v0.1.0

## 1. Introduction and Motivation

ZIR is a **mid-level intermediate representation** that sits between the resolved/monomorphized AST and the low-level Zoril IL (ZIL). It is the canonical representation on which all **ownership, borrow, and move checking** is performed.

### 1.1 Position in the Compiler Pipeline

```
Source (.zrl)
  │
  ▼  Lex + Parse
AST                         (surface-faithful parse tree)
  │
  ▼  Resolve + Type-check
Typed AST                   (names resolved, types inferred, generics monomorphized)
  │
  ▼  AST → ZIR lowering     ◄── NEW PHASE
ZIR                         (explicit Places, Moves, Borrows, Drops; CFG; named regions)
  │
  ▼  Borrow check           ◄── CHECK HAPPENS HERE (replaces verify.zrl at ZIL level)
ZIR (annotated)
  │
  ▼  ZIR → ZIL lowering     (replaces much of lower/expr.zrl)
ZIL                         (anonymous SSA, pure compute IR, no ownership annotations)
  │
  ▼  Verify (restricted)    (bounds checks, type safety only — NOT ownership)
ZIL
  │
  ▼  QBE emit
Machine code
```

### 1.2 Why ZIR?

The current approach performs borrow checking at ZIL level (equivalent to LLVM IR). This causes several structural problems that require increasingly complex workarounds:

- **Two `&r` borrows get different SSA IDs**
  - Cause at ZIL Level: Each `lower_address_of` emits a fresh `Load`
  - ZIR Solution: Both borrows reference the same `Place` for `r`
- **Loop re-check false positives**
  - Cause at ZIL Level: Pass 3 starts from wrong entry state
  - ZIR Solution: ZIR dataflow is correct by construction
- **Move detection through pointer indirections**
  - Cause at ZIL Level: Relies on fragile Store→Load→Move chains
  - ZIR Solution: `move` is an explicit statement; no reconstruction needed
- **Drop detection at scope end**
  - Cause at ZIL Level: Inferred via use-count heuristics (`dec_use`)
  - ZIR Solution: `drop` statements inserted explicitly by the AST→ZIR lower
- **Field move tracking**
  - Cause at ZIL Level: Requires `is_implicit_aggregate_ptr` heuristic
  - ZIR Solution: `field_move x.f` is a first-class statement

ZIR is roughly equivalent to Rust's MIR: a desugared, SSA-shaped CFG where ownership concepts are **first-class statements**, not inferred from low-level pointer patterns.

---

## 2. Core Concepts

### 2.1 Places

A **Place** is a path that names a location in memory. Places are the primary subject of borrow checking — borrows, moves, and assignments operate on Places, not on anonymous SSA values.

```
place ::=
    local_id                    -- local variable: `x`
  | place `.` field_name        -- struct field: `x.f`
  | place `.` integer           -- tuple element: `x.0`
  | `*` place                   -- dereference: `*p`
  | place `[` rvalue `]`        -- index (rare; usually slice_load in ZIL)
```

Every Place has a **base local** (the root `local_id`). The borrow checker tracks ownership state at the granularity of base locals, with field-level precision for partial moves.

**Projections**: `x.f`, `*x`, and `x.0` are "projections" of the base local `x`. A projection may be borrowed or moved independently of the rest of the base local, subject to the rules in §4.

### 2.2 Locals

A **local** is a named storage slot in the function frame. Every local has:

- A unique `LocalId` (name-derived, e.g. `_x` for `let x = ...`, `_tmp_42` for compiler temporaries)
- A type `T`
- A `kind`: `Arg` (function parameter), `Let` (immutable binding), `LetMut` (mutable binding), or `Tmp` (compiler-generated temporary)
- A `move_kind`: `Copy` or `Move` (derived from type)

Locals declared `Tmp` with `Copy` type may be freely aliased and are excluded from ownership tracking.

### 2.3 Rvalues

An **rvalue** is the right-hand side of a `let` or `assign` statement. It is a computation that produces a value but does not yet name a storage location.

```
rvalue ::=
    use place                   -- consume (move or copy) a Place
  | ref place                   -- immutable borrow of a Place → &T
  | ref_mut place               -- mutable borrow of a Place → &mut T
  | const literal               -- integer, float, bool, string constant
  | binary_op rvalue rvalue     -- arithmetic / comparison
  | unary_op rvalue             -- negation, bitwise not, etc.
  | call fn_id ( rvalue* )      -- function call producing a value
  | call_ptr rvalue ( rvalue* ) -- indirect call
  | struct_literal T { f: rvalue* }  -- aggregate construction
  | enum_variant T idx rvalue?  -- enum variant construction
  | field place field_name      -- copy/move a field (see §4.3)
  | index place rvalue          -- copy/move an element
  | cast rvalue T               -- type cast (bitwise reinterpretation or numeric)
  | sizeof T                    -- compile-time size
  | syscall int rvalue*         -- system call
```

### 2.4 Regions

A **region** labels the liveness scope of a borrow. Unlike Rust's full lifetime inference, Zoril uses a simplified region model:

```
region ::=
    'static                     -- lives for entire program
  | 'local                      -- current function stack frame
  | 'r<id>                      -- intra-function region variable (assigned by ZIR builder)
```

Every `ref` and `ref_mut` rvalue carries a region annotation `'r<id>`. The borrow checker assigns a fresh region variable to each borrow site and then computes the region's liveness as the set of CFG nodes between the borrow and the last use of the reference.

A borrow `'r<id>` is **valid** at a CFG node `n` if:

- The borrowed Place is not moved or reassigned at any node that dominates `n` and is reachable on any path from the borrow site to `n`.

---

## 3. ZIR Statements

A ZIR function is a CFG of **basic blocks**, each containing a sequence of statements followed by a **terminator**. Statements are side-effecting; rvalues are pure computations embedded within statements.

### 3.1 Statement Forms

```
stmt ::=
    let local_id : T = rvalue           -- declare local, bind value (or `uninit`)
  | assign place = rvalue               -- assign to existing mutable local or field
  | drop place                          -- explicitly drop a Move-type Place (consume without use)
  | call fn_id ( rvalue* )              -- call with no return value (side-effect only)
  | call_ptr rvalue ( rvalue* )         -- indirect call with no return value
  | borrow local_id : &T = ref place 'r       -- immutable borrow binding
  | borrow_mut local_id : &mut T = ref_mut place 'r  -- mutable borrow binding
  | end_borrow local_id                 -- explicit end of borrow lifetime (optional; can be inferred)
  | nop                                 -- no-op placeholder
```

> **Note on `drop`**: The AST→ZIR lowerer inserts `drop` statements at the precise point where a Move-type local goes out of scope (end of its lexical scope, or at each `return` / `break` / `continue` that exits the scope). This replaces the `dec_use` heuristic in the current ZIL verifier.

> **Note on `borrow` / `borrow_mut`**: These are sugar for `let local_id : &T = ref place 'r`. They are kept as distinct statement forms so the borrow checker can track borrow entry points without scanning rvalues.

### 3.2 Terminators

```
terminator ::=
    return rvalue?              -- return from function (drops remaining live locals)
  | jump block_id               -- unconditional branch
  | branch rvalue block_id block_id  -- conditional branch (true/false)
  | panic msg                   -- abort with message (never returns)
```

---

## 4. Ownership and Borrow Rules

These are the rules checked by the ZIR borrow checker. They are stated in terms of Places and Statements, making them implementable as a straightforward dataflow analysis — no heuristics, no pattern matching on pointer types.

### 4.1 Ownership State Machine

Each Place at each CFG node has one of four ownership states:

| State           | Meaning                                           |
| --------------- | ------------------------------------------------- |
| `Uninitialized` | Declared but not yet assigned                     |
| `Owned`         | Value is present and may be used                  |
| `Moved`         | Value has been consumed; use is an error          |
| `Dropped`       | Value was explicitly dropped or went out of scope |

State transitions:

| Event                             | Transition                                       |
| --------------------------------- | ------------------------------------------------ |
| `let x : T = rvalue`              | `x`: Uninitialized → Owned                       |
| `assign x = rvalue`               | `x`: Owned/Moved → Owned (re-initialize)         |
| `use x` in any rvalue (Move type) | `x`: Owned → Moved                               |
| `use x` in any rvalue (Copy type) | `x`: Owned → Owned (no transition)               |
| `drop x`                          | `x`: Owned → Dropped                             |
| `return` (scope exits)            | all Owned Move-type locals → Dropped (auto-drop) |
| `ref x` or `ref_mut x`            | `x` remains Owned; a borrow is created           |

**Error conditions**:

- Using a Place in state `Moved`: `VERIFY_ERR_USE_AFTER_MOVE`
- Using a Place in state `Uninitialized`: `VERIFY_ERR_USE_BEFORE_INIT`
- Place in state `Owned` at function return (Move type, no Drop impl): `VERIFY_ERR_LEAK`

### 4.2 Borrow Rules

When `borrow r = ref x 'r1` is executed:

1. `x` must be in state `Owned`.
2. A borrow `(x, Immutable, 'r1)` is added to the **active borrow set**.
3. While any immutable borrow of `x` is active:
   - `x` may not be moved or dropped.
   - `x` may be the source of additional immutable borrows.
   - `x` may NOT be the source of a mutable borrow.
   - `x` may NOT be assigned to (re-initialized).
4. The borrow expires when region `'r1` ends (at `end_borrow r` or when `r` is last used).

When `borrow_mut r = ref_mut x 'r1` is executed:

1. `x` must be in state `Owned`.
2. No other active borrows (immutable or mutable) of `x` may exist.
3. A borrow `(x, Mutable, 'r1)` is added to the active borrow set.
4. While the mutable borrow is active:
   - `x` may not be moved, dropped, borrowed (immutably or mutably), or assigned.
   - `r` (the mutable reference itself) may be used to read or write `x`.
5. The borrow expires at `end_borrow r` or last use of `r`.

**Conflict detection**: Two borrows conflict if they refer to **overlapping Places** and at least one is mutable. Overlap is determined by projection rules:

- `x` and `x.f` overlap.
- `x.f` and `x.g` do NOT overlap (disjoint fields).
- `*p` and `*q` overlap only if `p` and `q` are known to alias (conservative: assume overlap).

### 4.3 Partial Moves (Field Moves)

A **partial move** extracts a Move-type field from a struct, leaving the containing struct in a "partially moved" state. The ZIR statement `let y : T = field x field_name` performs a partial move.

Rules:

- The base local `x` transitions to state `PartiallyMoved { moved_fields: {field_name} }`.
- Individual fields of `x` in a partially-moved struct retain their own states.
- `x` as a whole may NOT be moved, dropped, or borrowed while any field is moved out.
- Each remaining owned field of `x` must be individually dropped or re-assigned before `x` goes out of scope.
- Re-assigning a moved field (`x.field_name = rvalue`) transitions that field back to Owned and removes it from the `moved_fields` set.

### 4.4 Loop Invariant: Merge at Join Points

At CFG join points (block entries with multiple predecessors), ownership states are **merged** by taking the **most-conservative** state across all incoming paths:

| States on different paths | Merged state                             |
| ------------------------- | ---------------------------------------- |
| Owned + Owned             | Owned                                    |
| Owned + Moved             | **error** (use-after-move on some paths) |
| Owned + Dropped           | **error** (use-after-drop on some paths) |
| Moved + Moved             | Moved                                    |
| Moved + Dropped           | Moved (both are consumed)                |

This merge is computed as a standard dataflow fixed-point. Loop headers are re-visited until the state stabilizes. Because states only move "down" the lattice (Uninitialized < Owned < Moved/Dropped), convergence is guaranteed in at most O(depth-of-loop-nesting) iterations.

This avoids the "Pass 3 re-check with wrong entry state" bug in the current ZIL verifier.

---

## 5. ZIR Function Structure

```
zir_module  = { zir_func_def }

zir_func_def = "fn" fn_name "(" { local_def "," } ")" "->" type "{"
                   { local_def ";" }         -- all locals declared upfront
                   { block_def }
               "}"

local_def   = local_id ":" type ( "arg" | "let" | "let_mut" | "tmp" )

block_def   = block_id ":" { stmt ";" } terminator ";"

stmt        = (see §3.1)

terminator  = (see §3.2)
```

### 5.1 Example

The following Zoril source:

```zoril,no-test
fn push(self: &mut Vec<i32>, val: i32) {
    if self.len >= self.cap {
        let new_data = alloc(self.arena, self.cap * 2);
        // ... copy loop ...
        self.data = new_data;
    }
    self.data[self.len] = val;
    self.len += 1;
}
```

Lowers to ZIR approximately as:

```zir
fn push(_self: &mut Vec<i32> arg, _val: i32 arg) -> unit {
    _new_data: *mut i32  tmp;
    _cond: bool          tmp;
    _new_cap: usize      tmp;

  @entry:
    _cond = use (*_self).len >= (*_self).cap;
    branch _cond @grow @no_grow;

  @grow:
    _new_cap = (*_self).cap * 2;
    _new_data = call alloc((*_self).arena, _new_cap);
    // ... copy loop blocks ...
    assign (*_self).data = use _new_data;   -- _new_data: Copy (*mut i32, not owned), no move
    jump @no_grow;

  @no_grow:
    assign (*_self).data[(*_self).len] = use _val;
    assign (*_self).len = (*_self).len + 1;
    return;
}
```

Note: `_new_data: *mut i32` is a `Copy` type (raw pointer to primitive). The `assign` at `(*_self).data = use _new_data` does not require a move — `_new_data` remains accessible after the assignment. This is in direct contrast to the false-positive "use of moved value" produced by the current ZIL-level verifier.

---

## 6. Relationship to ZIL

ZIL is a pure compute IR. After ZIR borrow checking is complete, ZIR is lowered to ZIL with the following correspondences:

| ZIR concept          | ZIL lowering                                                         |
| -------------------- | -------------------------------------------------------------------- |
| `local x : T`        | `alloc` of appropriate size, or direct SSA if `T` is scalar          |
| `let x = rvalue`     | evaluate rvalue into SSA, `store` into alloc slot                    |
| `assign *x = rvalue` | evaluate rvalue, `store` through pointer                             |
| `use x` (Move type)  | `load` from alloc slot, `store` to destination                       |
| `use x` (Copy type)  | `load` or direct SSA copy                                            |
| `ref x`              | `load` from alloc slot (address of x) — **no fresh Load per borrow** |
| `ref_mut x`          | same as `ref x`                                                      |
| `drop x`             | call `x.drop()` impl if exists; `store` poison pattern in debug mode |
| `borrow r = ref x`   | removed — no `Borrow` instruction in ZIL needed                      |
| `end_borrow r`       | removed                                                              |

**Key difference from current approach**: The `Borrow` / `EndBorrow` / `Release` instructions in ZIL are **removed**. Ownership checking is fully done in ZIR; ZIL becomes a clean, annotation-free compute IR. The ZIL verifier retains only:

- Bounds checking (§6.3 of ZIL spec)
- Type safety (§6.4 of ZIL spec)
- Mutability enforcement (§6.6 of ZIL spec)
- Linear resource rules for `fd` and `async_context` (§6.7 of ZIL spec) — these remain in ZIL because they are resource-level, not variable-level

---

## 7. Borrow Checker Algorithm

The ZIR borrow checker is a standard forward dataflow analysis.

### 7.1 Data Structures

```
OwnershipFact = Map<LocalId, OwnershipState>
BorrowFact    = Set<ActiveBorrow>

ActiveBorrow  = { base: Place, kind: Immutable | Mutable, region: RegionId, borrower: LocalId }

AnalysisState = (OwnershipFact, BorrowFact)
```

### 7.2 Transfer Functions

For each statement, the transfer function takes a pre-state and produces a post-state:

- **`let x = use p`** (Move type): assert `ownership[p.base] == Owned`, set `ownership[p.base] = Moved`, set `ownership[x] = Owned`.
- **`let x = use p`** (Copy type): assert `ownership[p.base] == Owned`, set `ownership[x] = Owned`. `p.base` unchanged.
- **`let x = ref p 'r`**: assert `ownership[p.base] == Owned`, assert no mutable borrow of `p.base` active. Add `(p.base, Immutable, 'r, x)` to borrow set. Set `ownership[x] = Owned`.
- **`let x = ref_mut p 'r`**: assert `ownership[p.base] == Owned`, assert no active borrows of `p.base`. Add `(p.base, Mutable, 'r, x)` to borrow set. Set `ownership[x] = Owned`.
- **`end_borrow x`**: remove borrow with borrower `x` from borrow set.
- **`drop p`**: assert `ownership[p.base] == Owned`. Call drop impl if present. Set `ownership[p.base] = Dropped`.
- **`assign p = rvalue`**: evaluate rvalue transfers; set `ownership[p.base] = Owned`.

### 7.3 Join (Merge) at CFG Join Points

```
merge(s1, s2):
    for each local x:
        state[x] = lattice_meet(s1[x], s2[x])
    borrows = s1.borrows ∩ s2.borrows   -- borrow active on ALL paths
```

Lattice: `Owned > Moved = Dropped > Uninitialized`. "Greater" means "more available." `lattice_meet(Owned, Moved) = Moved` (conflict → error if the local is later used as Owned).

### 7.4 Fixed-Point Computation

Standard worklist algorithm:

1. Initialize entry block with all args = `Owned`, all locals = `Uninitialized`.
2. Process each block in RPO (Reverse Post-Order); add successors to worklist if output state changed.
3. Repeat until worklist is empty.
4. Loop headers automatically converge: states only move toward `Moved`/`Dropped`, never back to `Owned`.

---

## 8. Required Changes to Other Specifications

### 8.1 Changes to ZIL Spec (`intermediate_language.md`)

The following ZIL features become **deprecated / removed** once ZIR borrow checking is in place:

| ZIL feature                                | Status                | Reason                                                |
| ------------------------------------------ | --------------------- | ----------------------------------------------------- |
| `Borrow(BorrowInstr)` instruction          | **Removed**           | Borrow tracking is done in ZIR                        |
| `EndBorrow(SSAId)` instruction             | **Removed**           | Borrow scope is tracked in ZIR                        |
| `Release(SSAId)` instruction               | **Removed**           | Ownership release is tracked in ZIR                   |
| `Move(SSAId)` instruction                  | **Retained**          | Still needed for scalar ownership transfer in ZIL ABI |
| Region annotations on types (`Ptr<T, 'r>`) | **Retained**          | Used for escape analysis                              |
| §6.1 Ownership / Move rules                | **Moved to ZIR spec** | ZIL verifier only handles bounds + types              |
| `VERIFY_ERR_USE_AFTER_MOVE`                | **Moved to ZIR**      | Detected in ZIR, not ZIL                              |
| `VERIFY_ERR_LEAK`                          | **Moved to ZIR**      | Drops explicit in ZIR                                 |

The ZIL verifier is simplified to check only:

- Type correctness of operands
- Bounds check domination for slice/array access
- Mutability (no store through `Ptr<T>`)
- Linear resource rules for `fd` and `async_context` (these remain ZIL-level because the `fd`/`async_context` types are linear at the ZIL type level)

### 8.2 Changes to Surface Syntax Spec (`surface_syntax.md`)

The following additions/clarifications are needed:

- **§7.2 Borrowing**: Add: explicit borrow scope rules — a borrow ends at the last use of the reference or at `end_borrow`. Document the "one mutable borrow OR multiple immutable borrows" rule formally.
- **§7.1 Copy vs. Move**: Add: raw pointer types `*T` and `*mut T` are always **Copy** (they are addresses, not ownership claims).
- **§7.3 Drop Order**: Add: explicit field drop order for partially-moved structs.
- **New §7.5**: Add: "Compiler Guarantees" section listing which errors are caught at which phase (ZIR borrow check vs. ZIL type check).

### 8.3 No Changes to Surface Syntax Grammar

The surface syntax grammar itself does not change. ZIR is an internal representation; users never see it. Lifetime annotations (`'r`) are not exposed in the surface language — regions are inferred by the AST→ZIR lowerer.

---

## 9. Implementation Roadmap

This spec describes the **target state**. The implementation proceeds in stages:

### Stage 1: ZIR Data Structures

Define `Place`, `Local`, `Rvalue`, `Stmt`, `Terminator`, `ZirBlock`, `ZirFunction`, `ZirModule` in a new file `src/zir.zrl`.

### Stage 2: AST → ZIR Lowerer

Implement `src/lower_zir.zrl` that walks the typed/monomorphized AST and emits ZIR statements. The lowerer:

- Assigns a `LocalId` to every `let`-bound variable and function parameter.
- Inserts `drop` statements at scope exits (replacing `dec_use`).
- Emits `borrow` / `borrow_mut` for `&expr` / `&mut expr`.
- Tracks the current scope stack for auto-drop insertion.

### Stage 3: ZIR Borrow Checker

Implement `src/check_zir.zrl` with the dataflow algorithm from §7. This replaces the ownership-tracking parts of `src/verify.zrl`.

### Stage 4: ZIR → ZIL Lowerer

Replace `src/lower_zir/expr.zrl` with a ZIR→ZIL lowerer that is free of ownership concerns (no `Borrow`/`EndBorrow` instructions, no `dec_use` heuristics).

### Stage 5: Simplify ZIL Verifier

Remove ownership rules from `src/verify.zrl`. Retain bounds, type, and linear-resource checks.

### Stage 6: Bootstrap

Self-host the ZIR pipeline through the stage0-C bootstrap compiler (`make`).

---

## 10. Design Decisions and Tradeoffs

### 10.1 No Lifetime Annotations in Source

Zoril does not require programmers to write lifetime annotations (`'a`, `'b`) in source code. Regions are inferred by the AST→ZIR lowerer using lexical scope as the initial approximation, then refined by the borrow checker. This is an intentional simplicity tradeoff: Zoril targets systems programming where borrows are typically short-lived and lexically scoped.

If a borrow cannot be inferred (e.g., a reference escaping a function return), the user must use an owned type (`Box<T>`, arena allocation) instead. This is a conservative but ergonomic choice.

### 10.2 No Inter-procedural Borrow Checking (Initially)

The initial ZIR borrow checker is **intra-procedural**: it checks each function independently. Function signatures carry no explicit lifetime annotations. Callee functions that accept `&T` or `&mut T` are assumed to not retain the reference beyond the call duration.

This is sound for the current Zoril codebase (no cross-function lifetime escapes in stdlib or compiler source). Inter-procedural checking can be added in a future version by adding lifetime parameters to function signatures.

### 10.3 Relationship to current `verify.zrl`

`src/verify.zrl` is not deleted immediately. During the transition:

- ZIR borrow checking is added as a new phase before lowering.
- `verify.zrl` is retained for bounds/type/linear-resource checks.
- Ownership rules in `verify.zrl` are disabled once ZIR checking is complete (guarded by a flag).
- Once ZIR is stable and all tests pass, the ownership code in `verify.zrl` is removed.

This allows incremental validation without breaking the existing test suite.
