// The canonical page test is web/page-test.mjs. This file was an older copy
// that could not run: it resolved `index.html` against its own directory, so it
// died with ENOENT on `scripts/index.html` — the pages live in `web/`.
//
// The web copy is a strict superset. It adds the `querySelectorAll` the page
// needs, a dozen assertions about the pretty-printed transcript, and — the
// reason this copy was actively worse than broken — it awaits the join clicks.
// The join handler is async, so the two `$("btn-dojoin").click()` calls here
// returned before the handler settled and the assertions after them "passed for
// the wrong reason".
//
// Delegating keeps one implementation. scripts/check-all.mjs sweeps this
// directory too, so the path stays.

import "../web/page-test.mjs";