// The canonical page test is web/diagpage-test.mjs. This file was a
// byte-identical copy that could not run: it resolved `diag.html` against its
// own directory, so it died with ENOENT on `scripts/diag.html` — the pages live
// in `web/`.
//
// The two were byte-identical, so delegating loses no assertion, and it removes
// the way they could drift apart — which is how the sibling wasm-test copies
// came to disagree about whether they passed. scripts/check-all.mjs sweeps this
// directory too, so the path stays.

import "../web/diagpage-test.mjs";