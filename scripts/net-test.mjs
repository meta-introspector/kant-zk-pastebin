// The canonical network test is web/net-test.mjs. This file was a stale copy
// that predates the fix for the one problem it still had.
//
// It configured the real relay with `{ ...CONFIG, port: 0, host: "127.0.0.1",
// staticDir: "" }`, leaving `passDb` at its default of
// /var/lib/kant-zk/passes.sqlite. That is the production database, so the suite
// wrote its rate-limit counters into deployment state, and because those
// counters are windowed (peerLimit 10 posts per 10 minutes, keyed by room and
// sender) they accumulated across runs. It passed three times and then failed
// the fourth with `relay post 2 line(s) failed: 429` — the flake everyone
// attributed to "it binds a real port".
//
// The bind was never the problem; a relay on an ephemeral port is hermetic.
// web/net-test.mjs already passes a per-PID SQLite in tmpdir() and removes it
// at the end.
//
// Every check here (32) is present in web/net-test.mjs (51), so delegating
// loses nothing. scripts/check-all.mjs sweeps this directory too, so the path
// stays.

import "../web/net-test.mjs";