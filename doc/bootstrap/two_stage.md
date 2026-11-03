# Two-Stage Source Bootstrap

A source build goes through two frozen layers. `stage0-C`, a C99 compiler for a fixed subset of Zoril, builds a frozen snapshot of the compiler; the snapshot then builds `src/`, the production compiler, which rebuilds itself to a fixpoint. The snapshot is what lets `src/` use more of the language than `stage0-C` itself accepts.

```text
stage0-C (C99)  --builds-->  stage1/ (frozen Zoril, stage0-C dialect)
                               -> build/zoril-stage1, build/zilc-stage1
build/zoril-stage1  --compiles-->  src/  ->  build/zoril  (the production compiler)
build/zoril         --compiles-->  tools/zilc/src/  ->  build/zilc
```

`src/` and the `stdlib/` modules it imports are therefore limited by what the pinned snapshot accepts, which is the full language as of the freeze, rather than by `stage0-C`. The release tree keeps the two seeds under `bootstrap/stage0-c/` and `bootstrap/stage1/`; the snapshot's dialect and known issues are summarized in [`KNOWN_ISSUES.md`](../../KNOWN_ISSUES.md).

## 1. Freeze set

The snapshot holds the import closures of `src/main.zrl` and `tools/zilc/src/main.zrl`, plus the runtime used to link the snapshot's binaries:

| Part              | Contents                                          |
| ----------------- | ------------------------------------------------- |
| `src/`            | every module in the compiler's import closure     |
| `stdlib/`         | the standard library modules that closure imports |
| `tools/zilc/src/` | `main`, `qbe`, `zil_parse`                        |
| `rt/`             | `runtime.s`, to link the stage1 binaries          |

It mirrors the repository paths under its own directory, plus a `PIN` file naming the pinned release. It is built with include roots inside the snapshot only and is never edited by hand.

After a freeze:

- `stdlib/` modules **outside** the freeze set are compiled only by `build/zoril`, so they may use any feature `src/` implements.
- The frozen `stdlib/` modules are still imported by `src/`, so the snapshot compiles them when it builds `src/`. They, like `src/`, may use only what the snapshot accepts.
- **Runtime compatibility:** `build/zoril` links with the current `rt/runtime.s`, and code the snapshot compiled calls runtime symbols (`zoril_abort`, `zoril_slice_eq`, ...). The current runtime must keep every symbol the pinned snapshot can emit.

## 2. Build paths

- **Clean build** (no `build/`): `stage0-C` → the pinned `stage1` snapshot → `src/` → `build/zoril`, then `build/zilc` through the boot zilc. `build/zoril` is a generation-2 binary, so every later compile is much faster than generation 1.
- **Rebuild** after a `src/` change: `build/zoril` rebuilds `src/` itself, the self-rebuild steady state `build/zilc` already uses. If a change breaks the compiler, deleting `build/zoril` falls back to the snapshot path.

**Which zilc assembles which ZIL.** ZIL is a text format that only moves forward: a compiler writes whatever spellings the `src/` it was built from knows, and a zilc of an older vintage cannot read a newer ZIL. The zilc must therefore follow the front end that wrote the ZIL in hand, and the `$(TARGET)` rule names that pairing rather than guessing it:

- ZIL written by `build/zoril-stage1` — the frozen front end — is assembled by `build/zilc-stage1`, the zilc of the same freeze. They were built together and agree.
- ZIL written by a compiler built from `src/` is assembled by `build/zilc`, or by `build/zilc-boot` when no `build/zilc` exists yet. `build/zilc-boot` is a zilc of the _current_ sources built through the snapshot path: the snapshot's front end compiles `tools/zilc/src`, and `build/zilc-stage1` links the result.

A re-pin is not the fix for a dialect mismatch: the mismatch returns with the next dialect change, while a boot zilc always tracks `tools/zilc/src`. zilc reports an unknown type name, and a byte at which the declaration dispatch made no progress, instead of looping (`tests/zilc/unknown_type_name.zil`, `tests/zilc/declaration_no_progress.zil`).

**Gates.** `scripts/selfhost-check.sh` — run by `make preflight` and by `make preflight-changed`, in the background beside `mutation-check` and waited on before the bench step — answers both questions in a **clean copy of the tree with no `build/`**, through the Makefile's default rules. That is the point: it takes the snapshot branch and the boot zilc, the path a fresh checkout takes, and no other gate enters it because every other gate starts from an existing `build/zoril`. So it proves `src/` stays within what the snapshot accepts _and_ that the compiler reproduces itself. `make test` keeps the self-rebuild and its fixed-bug and suite gates; the cheap half alone (`stage0-C` → the pinned snapshot → `src/`, in this tree) is `--build-only`.

## 3. Re-pin and backport policy

Each snapshot must be compilable by `stage0-C`, so the snapshot is never appended to (no stage2, stage3, ...). It may be **replaced**:

- Until a re-pin, `src/` and the frozen `stdlib/` modules may use only what the pinned snapshot accepts. The snapshot gate in preflight enforces it.
- A re-pin replaces the snapshot with a newer snapshot of `src/` that has been ported back into the `stage0-C` dialect by hand. It is expected to be rare: only when the compiler's own source needs a language feature added after the freeze.
- A deliberate **backport** may add a language feature the frozen compiler must parse (`use` / `ns::item`, `unsafe fn`). It is made through the re-pin procedure and recorded in the commit that carries it; a runtime fix moves `bootstrap/stage1/rt/runtime.s` with `rt/runtime.s`, because the `runtimes` gate requires the two to stay byte-identical.
  - **Backport recorded:** `bootstrap/stage1/rt/runtime.s` gained a `.note.GNU-stack` section (`.section .note.GNU-stack,"",@progbits`, which marks the stack non-executable) as a byte-identical copy of the same addition to `rt/runtime.s`. It changes no symbol and no code: the stage1 binaries link the object and now get a non-executable `GNU_STACK` instead of `RWE`. It is not a language backport and not a re-pin; `bootstrap/stage1/PIN` is unchanged.
- Verification, scripted in the source repository: `stage0-C` builds the candidate, the candidate builds current `src/`, the fixpoint holds, `make test` and `make preflight` pass, and `bootstrap/stage1/PIN` records the release it was pinned for.

## 4. Carried limits

- **Complexity ceiling:** `stage0-C`'s verifier rejects a function with more than 10,000 IL instructions or 1,000 blocks. Blocks are the binding limit in practice. A re-pin re-measures the headroom.
- The `stage0-C` dialect and its known bugs apply to the snapshot's source, which is today's `src/` and already complies. The dialect workarounds stay in the snapshot permanently; see [`KNOWN_ISSUES.md`](../../KNOWN_ISSUES.md) for the seed's known bugs and limits.

## 5. Host dependencies

A C99 compiler, `make`, QBE, `as` and `ld`. QBE is documented as a build dependency, not vendored: it is packaged on the major distributions, and the fixpoint compares ZIL, which is produced before QBE, so version differences cannot break it. `config.mk` resolves QBE from `PATH` (`command -v qbe`) with an optional `QBE_BIN` override.
