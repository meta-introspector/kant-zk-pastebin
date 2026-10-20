# Task: pastebin-pr5-pr1-superseded

**Status:** open
**Project:** meta-introspector/kant-zk-pastebin
**Found:** 2026-10-02

## Problem

PR #5 and PR #1 are both superseded by PR #6 and should be closed with a
pointer, not left open to be merged later into a tree they no longer fit.

**PR #5** (`fix/mesh-state-methods` → `feature/big-merge`, +836/−24). Its fix is
already on the base: `940d76fb` brought the mesh rebuild across, and
`src/mesh.rs` has carried the six `MeshState` storage proxies and the
`map_err(ErrorInternalServerError)` conversions since. PR #6 took the missing
part — the four tests, which `src/mesh.rs` did not have at all.

The branch cannot merge even in principle: it is based on `598ec603`, where the
mesh handlers lived in `src/handlers.rs`. They live in `src/mesh.rs` now, and
`src/handlers.rs` has been rewritten several times since.

**PR #1** (`codex/fix-public-access-commands` → `main`, CONFLICTING/DIRTY,
+687/−206). Its real finding was in `src/ipfs.rs`: `write_block` discarded every
failure and `ipfs_add_bytes` returned a root CID for a DAG with no leaves in it.
PR #6 fixed that (`88257336`). Its 738-line `handlers.rs` rewrite predates the
current file and the thing it was fixing — public access URLs — already exists
as the `/ipfs/{cid}` proxy route.

## Fix

Close both with a comment naming PR #6. Do not merge either.

Also update the registry row `PM1 pastebin-mesh-state-methods-fix` in
`~/dotagents/TASKS.md` from `in_progress` to done, since the fix landed and the
tests are on `feat/cli-fileshare`.

## Also worth cleaning while in there

PR #5 commits `src/handlers.rs.bak`, a 445-line copy of the file it edited,
referenced by nothing. It is being dropped rather than merged; if PR #5 is
closed as-is the file goes with it.
