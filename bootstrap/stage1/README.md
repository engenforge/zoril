# stage1/ — frozen bootstrap compiler

A frozen snapshot of the compiler (`src/`), the `stdlib/` modules it imports, zilc (`tools/zilc/src/`) and the runtime (`rt/runtime.s`), pinned for the `v0.1.0-alpha` release bootstrap. stage0-C builds it into `build/zoril-stage1` and `build/zilc-stage1`, which build `src/`.

**Never edit these files by hand.** They are written in the stage0-C dialect and change only by re-pinning against a newer compiler version.

## Recorded backports

Each entry is a deliberate, minimal change to this frozen snapshot made because the _current_ `src/` or the stdlib modules it imports need the compiler to **parse** a construct the snapshot predates. A backport never changes what this snapshot compiles to; it only keeps it able to read the tree. Re-pinning replaces it with the same feature taken from `src/` and removes the entry.

- **`#[stores(..)]` (parser only).** This snapshot's parser now skips the parenthesized list of a `#\[stores(..)]` attribute, which the standard library's `new_raw`/`push`/`set`/`arg`/`set_envp`/`set_ice_note` carry. Nothing is recorded on the declaration here; the current compiler reads the contract and checks it against the body (`KNOWN_ISSUES.md` §25). Reason: every stdlib module this snapshot compiles to build `src/` is inside the stage1 closure (the contributor guide's "stage1 constraint"), so the attribute had to be parseable here or the stdlib could not carry it before the next re-pin.
