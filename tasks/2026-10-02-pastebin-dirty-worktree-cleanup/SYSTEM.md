# Task: pastebin-dirty-worktree-cleanup

**Status:** open
**Project:** kant/pastebin
**Found:** 2026-10-02

## Problem

Four of the nine worktrees hold state that looks like work in progress and is
not. Each was checked; none contains anything unmerged.

| worktree | state | verdict |
|---|---|---|
| `/mnt/data1/kant/pastebin-wasm-port` (`wasm-port/land-inflight`, 37 dirty files) | the **pre-merge snapshot** of a merge that already happened | nothing to keep; the branch is fully contained in `feature/big-merge` |
| `/mnt/data1/kant/pastebin` (`feature/big-merge`) | 3 submodules `-dirty` at the **same SHAs** (no new commits), plus untracked `mesh-test/`, `tasks/`, `tasks/mesh.rs.local-edit.bak` | `mesh.rs.local-edit.bak` is the *pre-fix* copy — already in the tree; `mesh-test/` is build output |
| `/mnt/data1/kant/pastebin-main-test` (detached) | `kant-pastebin.service` edited to point at the test worktree | deploy scratch |
| `/mnt/data1/kant/pastebin-fix-worktree` (`fix/nora-vendor-merge`) | clean, but carries 21,486 committed spool files | see `pastebin-nora-spool-history-cleanup` |

The `tasks/2026-10-02-pastebin-mesh-fix/SYSTEM.md` in that tree is a completed
task record for the mesh fix; it belongs in `~/dotagents/tasks/`, where the rest
live, and the tree copy is untracked.

## Fix

* `mesh-test/` — add to `.gitignore`; it is a built wasm bundle and an html page.
* `tasks/` — move `2026-10-02-pastebin-mesh-fix/` into `~/dotagents/tasks/`
  (deleting the stale `mesh.rs.local-edit.bak`, which predates the fix).
* `pastebin-wasm-port` — the branch is contained in `feature/big-merge`; the
  dirty files are the old tree. Verify, then reset or remove the worktree.
* `pastebin-main-test` — the service edit is scratch; reset it if that worktree
  is kept.
* check what inside the three submodules is dirty (`cleanssl`, `ssl-test`,
  `erdfa-publish-investigation`) — `ssl-test` has an untracked `target/`.

## Verify

```sh
cd /mnt/data1/kant/pastebin-cli-fileshare
git worktree list
for wt in $(git worktree list --porcelain | grep '^worktree ' | awk '{print $2}'); do
  echo "== $wt: $(git -C $wt status --porcelain | wc -l) dirty"
done
```
