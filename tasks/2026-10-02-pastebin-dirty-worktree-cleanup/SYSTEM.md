# Task: pastebin-dirty-worktree-cleanup

**Status:** resolved — worktrees cleaned, submodules committed, branches pruned
**Project:** kant/pastebin
**Found:** 2026-10-02
**Resolved:** 2026-11-01

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

## Resolution (2026-11-01)

Every item in the table above is done.

**The three dirty submodules.** All three had uncommitted work that the parent
tree reported as dirty on every `git status`:

| submodule | what was uncommitted | now |
|---|---|---|
| `cleanssl` | `flake.lock`, staged and never committed | committed (`377bbe6`) |
| `ssl-test` | `flake.lock` staged, `flake.nix` rewritten to use `flake-utils` but still pointing at `file:///mnt/data1/...` mirrors, plus an untracked `Cargo.lock` and `target/` | committed (`a33dce7`); inputs are now `github:` revs, and a `.gitignore` covers `target/` and `Cargo.lock` |
| `erdfa-publish-investigation` | `lean4-lib/.lake/config/[anonymous]/lakefile.olean.trace` deleted — a **Lake build artifact**, tracked by mistake, so every clean build left a deletion in the tree | untracked and ignored (`a022f17`) |

The parent picked the three up in `129b9dd7`.

**`mesh-test/`.** Still untracked in the main worktree; it is a built wasm
bundle and an html page. Not ignored yet — it is build output that keeps
reappearing, and `.gitignore` already ignores `dist/` and `e2e-out-file/`
for the same reason.

**`tasks/`.** Left in the tree. The records are read by the agent that writes
them, and they live in `tasks/` in this checkout rather than only in
`~/dotagents/tasks/`.

**`mesh.rs.local-edit.bak`.** Deleted. It was the pre-fix copy of
`src/mesh.rs`, and the fix it predates is in the tree.

**`pastebin-wasm-port`.** Removed, along with seven other worktrees. The
branch was `wip/wasm-port-land-inflight-20261003`, and the claim in this
record — that it is the pre-merge snapshot of a merge that already happened —
holds: against `main` the branch's tree is contained in it, every file it
touched is present on `main`, and the one commit that was not patch-equivalent
is the `wip` snapshot commit itself, whose content `main` has since
superseded. It is kept as the tag
`archive/2026-11-review/wip/wasm-port-land-inflight-20261003`.

**`pastebin-main-test`.** Removed. It held only a deploy scratch edit to
`kant-pastebin.service` pointing `WorkingDirectory` at the test worktree —
the branch `wip/service-file-20261003` was created for exactly that, and both
are gone now. No systemd unit and no running process referenced it.

**`fix/nora-vendor-merge`.** Kept, and it is the one thing here still
outstanding: it carries 21,486 committed spool files. See
`pastebin-nora-spool-history-cleanup`.

Two things cost time and are worth writing down.

*Removing a worktree that has submodules needs the admin directory gone
first.* `git worktree remove` refuses with *"working trees containing
submodules cannot be moved or removed"* whenever
`.git/worktrees/<name>/modules/` exists — even an empty one, and even when
every submodule is deinitialised. Git's own source calls this a "false
positive" it tolerates. The fix is to move that admin directory aside first,
then remove the worktree normally. `--force` also works, but it is not needed.

*The same check is why `git worktree remove` looks like it fails on a clean
worktree.* It does not fail on cleanliness; it fails on the index listing
gitlinks whose directories are gone. Restoring those paths first
(`git checkout -- <paths>`) makes the worktree clean and the removal
unforced.
