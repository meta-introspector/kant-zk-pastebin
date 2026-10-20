// The canonical join test is web/join-test.mjs. This file was a stale subset of
// it (9 checks against 16) that also carried the production-state bug: it
// configured the real relay with `{ ...CONFIG, port: 0, host: "127.0.0.1",
// staticDir: "" }`, leaving `passDb` at its default of
// /var/lib/kant-zk/passes.sqlite.
//
// Delegating fixes both at once — the web copy passes a per-PID SQLite in
// tmpdir() and removes it at the end, so no suite in the core run appends to a
// live relay's rate-limit ledger.
//
// scripts/check-all.mjs sweeps this directory too, so the path stays.

import "../web/join-test.mjs";