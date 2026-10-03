# Task: pastebin-nora-spool-history-cleanup

**Status:** open
**Project:** kant/pastebin
**Found:** 2026-10-02

## Problem

`fix/nora-vendor-merge` carries **21,486 files** that are job records:

```
spool/svg2anim-jobs/ff95e8c23c20d358
spool/svg2anim-jobs/ff987e4438678068
... 21,484 more
```

Five commits, four of them are `deploy: auto-commit before nix build`, and
together they are **+5,187,531 lines**. A `svg2anim` spool directory was
committed by a deploy script that ran `git add -A` from the repo root.

Its one real commit — `e9c406f5 fix: use <object> for SVG rendering in paste
view` — is already in the tree at `src/handlers.rs:1096` and
`src/gallery.rs:233`, so there is nothing to take from the branch.

## Fix

Do not merge this branch. Two separate things:

1. **`gitignore` `spool/`** and remove it from the index, so the next
   auto-commit-before-build does not do it again. This is the actual bug; check
   what the deploy wrapper commits and tighten it.
2. **Decide about the history.** The files only exist on this one branch, which
   was never merged, so `git rm -r --cached spool/` on the branch (or simply
   abandoning the branch) is enough — no filter-branch rewrite needed. If that
   branch is ever to be merged, drop `spool/` from it first.
