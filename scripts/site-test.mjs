// The canonical page test is web/site-test.mjs. This file was a byte-identical
// copy that could not run: it resolved `kant.config` against its own directory,
// so it died with ENOENT on `scripts/kant.config` — the site config lives
// beside `web/index.html`, in `web/`.
//
// (check-all.mjs recorded this one as "looks for scripts/index.html", which was
// the wrong file: it is the config that is missing.)
//
// The two were byte-identical, so delegating loses no assertion. It also removes
// the way they could drift apart. scripts/check-all.mjs sweeps this directory
// too, so the path stays.

import "../web/site-test.mjs";