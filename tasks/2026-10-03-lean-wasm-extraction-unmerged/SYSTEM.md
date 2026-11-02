# Task: lean-wasm-extraction-unmerged

- **Name:** lean-wasm-extraction-unmerged
- **Priority:** P1
- **Area:** kant-zk-pastebin, lean, wasm, build
- **Status:** open
- **Created:** 2026-10-03
- **Repo:** `meta-introspector/kant-zk-pastebin`
- **Tags:** kant-zk-pastebin, lean, wasm, build

## The problem

**`web/docs/WASM-EXTRACTION.md` is on `main`. The code it describes is not.**

The doc documents a real, working, proved Lean→WebAssembly extractor. The
implementation lives on `feature/lean` (also `feat/build-feed`), 18 files:

```
EmitWasm.lean
RequestProject/Wasm/{Leb128,Syntax,Semantics,Encode,Decode,Kernel,KernelSpec,Extraction}.lean
dist/kant_kernel.wasm
web/{kant-wasm.mjs,wasm-test.mjs,kant_kernel.wasm}
```

A reader on `main` gets the full design and cannot run any of it. Worse, the doc
is the strongest argument in the repo for "Lean as wasm works, no C toolchain
needed" — and the thing backing that claim is unmerged.

## Verified working 2026-10-03

Built and validated in worktree `/mnt/data1/kant/pastebin-lean-merge`:

```
lake exe emitwasm dist   →  wrote dist/kant_kernel.wasm (799 bytes)
                           wrote dist/kernel-vectors.json (21 exported functions)
node web/wasm-test.mjs   →  ok — 799 byte module, 21 exports, 59 golden vectors,
                           agreement with the JS client, all checks passed
```

**Byte-identical to the committed artifact.** ~60s from cold, given mathlib is
prebuilt at `/mnt/data1/lean/mathlib` (9.8 GB, 7,655 oleans, toolchain
`leanprover/lean4:v4.28.0`).

`wasm-test.mjs` checks four things: the engine's own validator accepts it, 59
golden vectors match a running engine, 1024 stego round-trips, and the binary
agrees with `web/kantzk.mjs` — which is itself pinned to Lean-computed vectors.
Three-way agreement.

## What merging needs

1. **`lake-manifest.json` fix.** The manifest declares mathlib as a `git`
   dependency; `lakefile.toml` declares it a `path` dependency to
   `/mnt/data1/lean/mathlib`. Anyone else running `lake exe emitwasm` gets a
   re-clone of mathlib and an hours-long rebuild — or a failure.

   **Decide which is canonical.** A `path` to `/mnt/data1/lean/mathlib` is
   machine-specific and must not merge as-is. Either the manifest is corrected
   to a pinned git rev that resolves, or the path is templated.

2. **`scripts/embed-kernel.mjs`** — mentioned in the doc as part of regeneration
   (`lake exe emitwasm dist` then `node scripts/embed-kernel.mjs`). Confirm it
   is on the branch being merged; the browser loader falls back to
   `web/kant-kernel-embedded.mjs` and `wasm-test.mjs` fails on drift.

3. **Confirm `output-final_aristotle/`** — a full duplicate tree including its own
   copy of all 9 `Wasm/*.lean` files and a second `dist/kant_kernel.wasm`. Decide
   whether it merges or is build detritus. Two copies of proved Lean that can
   drift is the failure mode this whole layer exists to prevent.

## Why this matters beyond the merge

PB-37 (wasm-thunk-format) built the thunk format on top of this module and used
it as the fixture. The first thunk *is* this kernel. And the fragment boundary
that gates every future thunk — no memory, no loops — is a property of this
extractor's `Syntax.lean`/`Semantics.lean`, so widening what thunks can do means
widening this code.

## Related

- **PB-37** `wasm-thunk-format` — the thunk format built on this module
- **PB-32** `libp2p-prior-work-triage` — the other stranded P2P work
- `web/docs/WASM-EXTRACTION.md` on `main` — the design, without the code
- `scripts/build-wasm.sh` — the Lean→C→emscripten route, **scaffolding that has
  never executed**; it refuses to run without `LEAN_WASM_SYSROOT`. Anyone
  reaching for it should read the doc first.