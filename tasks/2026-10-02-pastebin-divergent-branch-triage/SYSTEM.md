# Task: pastebin-divergent-branch-triage

**Status:** open
**Project:** kant/pastebin
**Found:** 2026-10-02

## Problem

Five branches are 60 to 114 commits ahead of `feat/cli-fileshare` on lines of
development nobody has touched since. They are not stale in the "delete it" sense
— they are separate efforts that were never merged:

| branch | ahead | behind | what it is |
|---|---|---|---|
| `feature/plugin-spinoff-snapshot-20260416-132607` | 114 | 248 | microflakes for submodule crates, on origin |
| `feature/plugin-spinoff` | 75 | 248 | "pure Rust headless browser tests with static analysis" |
| `feature/kant-kategorie` | 60 | 248 | plugin refactor plan for erdfa/zkperf/zos |
| `fix/sheaf-coordinates-and-hostname` | 60 | 248 | on origin |
| local `main` | 59 | 248 | `fix: nix build working with all submodules resolved` — behind origin/main, not ahead in content |

Merging these into the JS/CLI branch is not a merge, it is a fork: they touch
Rust modules the file-share work never opens.

## Fix

Triage each: **rebase onto a current base and land it**, **archive it**, or
**delete it**. The two on origin (`plugin-spinoff-snapshot`,
`sheaf-coordinates`) need a decision recorded on the repo, not just locally.

Local `main` is the easy one: it is behind `origin/main` and its tip commit is
already in origin's history, so it can probably be deleted outright.

## Verify

```sh
cd /mnt/data1/kant/pastebin-cli-fileshare
for b in feature/plugin-spinoff feature/kant-kategorie fix/sheaf-coordinates-and-hostname main; do
  echo "== $b: $(git log --oneline HEAD..$b | wc -l) ahead"
done
```

Each remaining branch should have a recorded decision.
