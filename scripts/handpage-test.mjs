// The canonical page test is web/handpage-test.mjs. This file was a
// byte-identical copy that could not run: it resolved `hand.html` against its
// own directory, so it died with ENOENT on `scripts/hand.html` — the pages live
// in `web/`.
//
// The two were byte-identical, so delegating loses no assertion, and it removes
// the way they could drift apart. scripts/check-all.mjs sweeps this directory
// too, so the path stays.

import "../web/handpage-test.mjs";