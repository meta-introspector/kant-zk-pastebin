# Task: pastebin-wasm-test-requires-lake-emitwasm

**Status:** open
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
