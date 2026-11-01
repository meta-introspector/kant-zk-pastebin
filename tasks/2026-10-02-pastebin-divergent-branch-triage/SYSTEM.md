# Task: pastebin-divergent-branch-triage

**Status:** resolved — 14 branches deleted, 9 kept, decisions recorded
**Project:** kant/pastebin
**Found:** 2026-10-02
**Resolved:** 2026-11-01

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

## Resolution (2026-11-01)

The five branches in the table are not five efforts. They are **one base and
one commit each**, and the real picture only shows up when you check ancestry
rather than counting commits.

All eight plugin-era branches descend from the same place: `ef3f59ad`
(2026-03-16). Four of them — `backup/main-was-afe4a248`,
`feature/kant-kategorie`, `fix/sheaf-coordinates-and-hostname`,
`fix/js-var-script-breakout` — are 59 or 60 commits on top of it, and they
each hold exactly one commit the others do not:

| branch | its one unique commit | what it is |
|---|---|---|
| `feature/kant-kategorie` | `1fa98e04` | `PLUGIN_REFACTOR.md` — the plugin refactor plan for erdfa/zkperf/zos |
| `fix/sheaf-coordinates-and-hostname` | `6f59d3ba` | `flake.lock` |
| `fix/js-var-script-breakout` | `d08aadc4` | `js_string_escape` — a `js_var` value could close the script element it lives in |
| `backup/main-was-afe4a248` | — | the base itself; an ancestor of two of the above |

They look independent and are not: `backup/main-was-afe4a248` is an **ancestor**
of `feature/kant-kategorie` and of `feat/build-feed`, and `feature/kant-kategorie`
is an **ancestor** of `feature/plugin-spinoff-snapshot-20260416-132607`. Each
of the three siblings has already cross-merged the other two's tip commit, so
the only thing each one adds is its own single commit.

### Deleted — content is in a surviving branch

| branch | why it is safe |
|---|---|
| `backup/main-was-afe4a248` | ancestor of `feature/kant-kategorie` and `feat/build-feed`; every file it has is present in both |
| `feature/lean` | ancestor of `feat/build-feed` (which is `feature/lean` plus one commit); every file it has is present there |
| `feature/plugin-spinoff` | ancestor of `feature/plugin-spinoff-snapshot-20260416-132607`; every file it has is present there |
| `feature/kant-kategorie` | ancestor of `feature/plugin-spinoff-snapshot-20260416-132607`; `PLUGIN_REFACTOR.md` is present there |

Each is kept as a tag under `archive/2026-11-review/`, and the tags are
pushed, so nothing is lost — `git show archive/2026-11-review/<branch>` still
works.

### Kept — these hold work nothing else has

| branch | commits | what only it has | decision |
|---|---|---|---|
| `feat/build-feed` | 153 | 94 commits: the carrier layer, `kzpass`, the archive and forward services, the self-deploying stack | keep — the largest unmerged effort |
| `feature/plugin-spinoff-snapshot-20260416-132607` | 114 | 55 commits: the HTML/CSS/JS parsers, the orbifold and conformal work, the plugin architecture | keep — a separate effort from the above |
| `fix/js-var-script-breakout` | 60 | `d08aadc4` | keep — **it cannot be merged on its own**: the `js_var` feature it fixes is not on `main` at all |
| `fix/sheaf-coordinates-and-hostname` | 60 | `6f59d3ba` | keep — `flake.lock`; `main`'s is newer and supersedes it, but the branch is on `origin` and this is the recorded decision point |

The `js_var` point is the one worth being careful about. `PR #11` was **closed**,
not merged, and that was right: `main` has no `js_var` — no `js_var` in
`src/`, no `js_var` in `web/` — so there is nothing on `main` for the fix to
fix. The whole plugin line (`plugin.toml`, `category/kant/`, `js_var`) was
never merged. The fix has to travel with the feature, which means the
decision is not "merge this one commit" but "land the plugin line or archive
it".

### The decision that is still open

`feat/build-feed` and `feature/plugin-spinoff-snapshot-20260416-132607` are
two large, unrelated efforts forked from the same March base, each touching
Rust modules the other never opens. Neither can be merged casually: `main` has
been rewritten several times since March, and these branches are 391 commits
behind it.

They are kept, and they are the only thing in the branch list that needs a
decision from a person. The options are unchanged from the original task —
rebase onto a current base and land it, archive it, or delete it — but the
task's premise needed correcting: this is not "five branches", it is "two
efforts, plus two single-commit branches that belong to them, plus one base
that is already inside two others".

