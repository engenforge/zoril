# Zoril Bootstrap Layering

This document describes the default source bootstrap: the frozen C99 seed compiler builds a frozen snapshot of the compiler, and that snapshot builds the self-hosted compiler in `src/`. The release tree keeps the two seeds under `bootstrap/stage0-c/` and `bootstrap/stage1/`; their dialect and known issues are summarized in [`KNOWN_ISSUES.md`](../../KNOWN_ISSUES.md).

## 1. The three layers

```text
Layer 1 (frozen):  stage0-C  (C implementation, fixed, not evolving)
        │  compiles (via QBE)
        ▼
Layer 2 (subset):  the stage1 snapshot  (Zoril, constrained to the stage0-C subset)
        │  builds
        ▼
Layer 3 (full):    src/ compiler and every full-idiomatic Zoril program
                    (stdlib/, tests/, tools/, ...)
```

### Layer 1 — stage0-C

`stage0-C` is the permanent cold-start bootstrap compiler: a C implementation of a fixed subset of Zoril. It lowers that subset to QBE IR and is never extended with new language features. It exists solely to produce Layer 2 from source.

### Layer 2 — the subset-constrained snapshot

The `stage1` snapshot is a frozen copy of the compiler, the standard library modules it imports, `zilc` and the runtime. It is written in the same deliberate **subset** of Zoril that `stage0-C` accepts (no struct or tuple match patterns, no `if let`/`while let`, no tuple destructuring in `let`, numeric-only `for` ranges), and it is what `stage0-C` builds.

This constraint is what keeps the source bootstrap alive: as long as the `stage1` snapshot stays inside the stage0-C subset, a working `zoril` can always be regenerated from `stage0-C` plus the source tree, independent of any other toolchain.

### Layer 3 — full idiomatic Zoril

The snapshot is fully capable of compiling **full** Zoril — generics, exhaustive `match`, closures, traits, the lot. Layer 3 is therefore every Zoril program written the way the language is meant to be used, including the `src/` compiler itself. In practice the snapshot compiles the compiler, `stdlib/`, `tools/`, and the entire `tests/` corpus.

## 2. Why a subset at Layer 2 and full at Layer 3

The subset is a property of the **source** at Layer 2, not of the **compiler's capability**. The compiler built from the snapshot implements the complete Zoril language; only its own source text is held back to the subset so that `stage0-C` can still build it. Layer 3 programs are under no such restriction.

This separation is the key invariant of the bootstrap: a single frozen C compiler (auditable once) anchors an indefinitely evolving, fully-idiomatic-Zoril compiler, without ever requiring the C compiler to grow.
