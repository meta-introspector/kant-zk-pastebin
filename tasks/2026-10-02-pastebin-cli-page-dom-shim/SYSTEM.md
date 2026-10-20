# Task: pastebin-cli-page-dom-shim

**Status:** open
**Project:** kant/pastebin, branch `feat/cli-fileshare` (PR #6)
**Found:** 2026-10-02, sweeping all worktrees and branches

## Problem

`web/cli-page-test.mjs` is 8/9. The one failure is not a product bug:

```
FAIL: the page ran without throwing (box.querySelectorAll is not a function
      or its return value is not iterable)
```

The test drives `web/index.html` through a minimal DOM shim. That shim has no
`querySelectorAll`, so the page throws while rendering and the test reports it
as a page failure.

This is the same defect that was already fixed in `scripts/../page-test.mjs` by
commit `1c921a46` ("Fixed page-test.mjs's DOM shim lacking querySelectorAll (it
crashed outright)"). The fix was applied to one copy of the shim and not the
other.

## Fix

Either give the shim in `web/cli-page-test.mjs` a `querySelectorAll`, or — better
— extract the shim both tests use into one module so the next page change
cannot drift past it again. Then re-run.

## Verify

```sh
cd /mnt/data1/kant/pastebin-cli-fileshare
node web/cli-page-test.mjs     # want 9/9
```

Baseline for comparison: the same file is 8/9 on an untouched `feature/big-merge`
worktree, so this is not a regression from PR #6.
