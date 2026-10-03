# Task: pastebin-wasm-test-requires-lake-emitwasm

**Status:** resolved — the test reads tracked artifacts, not build output
**Resolved:** `4da487d2`
**Project:** kant/pastebin
**Found:** 2026-10-02, sweeping all worktrees and branches

## Problem

`web/wasm-test.mjs` fails on a clean tree:

```
Error: ENOENT: no such file or directory, open '.../dist/kant_kernel.wasm'
```

This is **not** a broken test — its own header states the precondition:

```
//   lake exe emitwasm dist && node web/wasm-test.mjs
```

`dist/kant_kernel.wasm` and `dist/kernel-vectors.json` are build artifacts (and
`dist` is gitignored), so the test only runs after a Lean `emitwasm` build. It
reads like a failure to anyone sweeping the suite, and it has presumably been
skipped rather than run for that reason.

## Fix

Give it a build step so a sweep cannot mistake it for broken:

* a `make test-wasm` (or nix app) that runs `lake exe emitwasm dist` and then
  the test, and
* have the suite skip it with a clear "needs emitwasm" message when
  `dist/kant_kernel.wasm` is absent, instead of `ENOENT`.

The golden vectors it checks come from the same Lean module the wasm is emitted
from, so this is the only test that ties the Rust and JS semantics together —
worth making runnable rather than skipping.

## Verify

```sh
lake exe emitwasm dist && node web/wasm-test.mjs
```

## Resolution

The fix chosen was neither of the two proposed here. Skipping the suite with a
"needs emitwasm" message would have kept the only test tying the wasm to Lean
out of the run, which is the thing worth protecting; and a `make test-wasm`
target would still not run under `npm run verify`, so a sweep would still skip
it silently.

Instead `scripts/embed-kernel.mjs` makes the artifacts tracked rather than build
output, and the test reads those. Both of the gitignored dependencies had to be
handled — this task named only `kant_kernel.wasm`, but `kernel-vectors.json` was
a second, and fixing the first alone would have left the test still dying with
ENOENT.

`web/kant_kernel.wasm` turned out to be tracked already, so only the vectors
needed a new home. `web/wasm-test.mjs` and `scripts/wasm-test.mjs` are both in
the core run and green; `npm run verify`: 41/41.
