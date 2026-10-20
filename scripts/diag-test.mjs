// The canonical diagnostics test is web/diag-test.mjs. This file was a stale
// subset of it (30 checks against 34) that also carried the production-state
// bug: it spawned `server/relay.mjs` without `--pass-db`, so the child's pass
// store defaulted to /var/lib/kant-zk/passes.sqlite and this suite wrote three
// peer_posts rows into it per run.
//
// Delegating fixes both at once — the web copy gives the relay a per-PID SQLite
// in tmpdir() and removes it afterwards.
//
// scripts/check-all.mjs sweeps this directory too, so the path stays.

import "../web/diag-test.mjs";