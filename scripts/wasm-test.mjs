// The canonical kernel conformance test is web/wasm-test.mjs. This file used to
// be a byte-identical copy of it, but the two could not both pass: `scripts/`
// has no tracked `kant_kernel.wasm`, so this copy's "the default candidate list
// finds the binary" assertion fell through to the embedded fallback and failed
// whenever the gitignored `dist/` was absent — which is always, in a checkout.
//
// Delegating keeps one implementation, so the two cannot drift again. The path
// stays because scripts/check-all.mjs sweeps this directory too.

import "../web/wasm-test.mjs";