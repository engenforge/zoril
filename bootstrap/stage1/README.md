# stage1/ — frozen bootstrap compiler

A frozen snapshot of the compiler (`src/`), the `stdlib/` modules it imports, zilc (`tools/zilc/src/`) and the runtime (`rt/runtime.s`), shipped with the `v0.1.0-alpha` release bootstrap. It is an older `src/` ported to the stage0-C dialect, not that release's `src/`. stage0-C builds it into `build/zoril-stage1` and `build/zilc-stage1`, which build `src/`.

**Never edit these files by hand.** They are written in the stage0-C dialect and change only by re-pinning against a newer compiler version.

## Recorded backports

Each entry is a deliberate, minimal change to this frozen snapshot made because the _current_ `src/` or the stdlib modules it imports need the compiler to **parse** a construct the snapshot predates. A backport never changes what this snapshot compiles to; it only keeps it able to read the tree. Re-pinning replaces it with the same feature taken from `src/` and removes the entry.

- **`#[stores(..)]` (parser only).** This snapshot's parser now skips the parenthesized list of a `#\[stores(..)]` attribute, which the standard library's `new_raw`/`push`/`set`/`arg`/`set_envp`/`set_ice_note` carry. Nothing is recorded on the declaration here; the current compiler reads the contract and checks it against the body (`KNOWN_ISSUES.md` §25). Reason: every stdlib module this snapshot compiles to build `src/` is inside the stage1 closure (the contributor guide's "stage1 constraint"), so the attribute had to be parseable here or the stdlib could not carry it before the next re-pin.
- **`#[unsafe(borrows(..))]` (parser only).** This snapshot's parser reads `#\[unsafe(borrows(a, ..))]` as it reads `#\[borrows(a, ..)]`, and records nothing of the `unsafe`. The current compiler alone checks a `#\[borrows(..)]` against its body, and the `unsafe` form is the one it trusts where the declaration names less than the body returns (`doc/design/provenance.md` §3, tier 3). Reason: the `src/` and `tools/zilc/src/` declarations that are such trusted narrowings are compiled by this snapshot, so the form had to be parseable here before the next re-pin.
