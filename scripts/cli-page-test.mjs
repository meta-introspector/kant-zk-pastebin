// The canonical page test is web/cli-page-test.mjs. This file was a
// byte-identical copy that could not run: it resolved `index.html` and
// `kant.config` against its own directory, so it died with ENOENT on
// `scripts/index.html` — the pages live in `web/`.
//
// Delegating keeps one implementation. The web copy is a superset: it adds the
// `querySelectorAll` the page needs (`web/index.html` wires handlers with
// `box.querySelectorAll("a[data-q]")`), and its transcript assertions read the
// markup `lineHtml` in web/kant-pretty.mjs actually emits instead of the old
// flat "name: text" form.
//
// scripts/check-all.mjs sweeps this directory too, so the path stays.

import "../web/cli-page-test.mjs";