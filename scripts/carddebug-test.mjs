// The canonical carddebug test is web/carddebug-test.mjs. This file used to be
// a byte-identical copy of it -- `diff` reported no difference -- which is the
// one state a delegation exists to end: two copies pass the same assertions
// until the day someone edits one of them, and then the tree carries two suites
// of different lengths with the same name and nobody can tell which is the
// contract.
//
// Both copies were BROKEN for the same reason and both were fixed the same way,
// by restoring `scripts/kant-debug.mjs`. That is the recorded cause for this
// file being wrong twice over: the tool existed on origin/feature/lean and
// origin/feat/build-feed, and the big merge dropped it.
//
// Delegating keeps one implementation, so the two cannot drift again. The path
// stays because scripts/check-all.mjs sweeps this directory too.

import "../web/carddebug-test.mjs";