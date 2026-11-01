# Task: prune 37 stale branch heads + worktree audit
- **Priority:** P2
- **Tags:** git

**Status:** OPEN (issues #126, #177, #180)

## Facts
- Integration checker containment finding: 37 branch heads not ancestors of
  HEAD (pr-104, pr191, qoder/pr-sweep-20261001, review-pr166..168, rescue
  snapshots etc.) — this finding is deliberate-open until pruned.
- 31 worktrees across /home/mdupont/projects/... and /mnt/data1/twitterstorm/...
  (+ .letta/.qoder nested). #126 audit: superseded ones removable; recovery
  branch holds orphaned docs.

## Rules
Branch deletion is destructive + shared-state — needs operator-approved list,
one confirmation per batch. Verify claim.md/PID before touching worktrees.
Pruning the refs closes 1 of the 2 open checker findings.

## Progress (2026-10-03, integration session)

Done for pastebin-lean + arist (the rest of the 31-worktree audit is still
open):

- Removed worktrees: pastebin-reconcile (fully merged, clean),
  arist-bugfix-fixed (fix-diagonalize-fixed MERGED), aristo-enrich
  (enrich-command MERGED).
- Deleted stale remote-tracking refs `tmp-aristo/main`,
  `tmp-aristo/feature/test1` (from a deleted remote).
- arist main FF'd to `4f4a66a79`; pastebin-lean main = `bbac0ab`, pushed to
  the local mirror.
- Remaining arist worktrees have their own disposition table now:
  task `2026-10-03-arist-july-worktree-cleanup`.
