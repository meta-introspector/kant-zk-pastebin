# Task: pastebin-carddebug-missing-kant-debug

**Status:** resolved — the tool was dropped by the big merge, not deleted
**Resolved:** `9f0b7a5d` (see below)
**Project:** kant/pastebin
**Found:** 2026-10-02, sweeping all worktrees and branches

## Problem

`web/carddebug-test.mjs` cannot run at all. It shells out at line 143:

```js
execFileSync(process.execPath, [join(here, "..", "scripts", "kant-debug.mjs"), ...args], ...)
```

and `scripts/kant-debug.mjs` does not exist anywhere in the tree or in git:

```
Cannot find module '/mnt/data1/kant/pastebin-cli-fileshare/scripts/kant-debug.mjs'
```

So the test fails with `MODULE_NOT_FOUND` on the very first invocation, having
checked nothing.

## Fix

One of two, and the choice matters:

* `scripts/kant-debug.mjs` was deleted or renamed and the test was left behind —
  restore the tool or point the test at its new name.
* it was never committed, in which case the test has never run and should be
  deleted rather than "fixed" by writing a new tool to satisfy it.

Check `git log --diff-filter=D -- scripts/kant-debug.mjs` first.

## Verify

```sh
cd /mnt/data1/kant/pastebin-cli-fileshare
node web/carddebug-test.mjs    # must not fail on MODULE_NOT_FOUND
```

## Resolution

The instruction above to check `git log --diff-filter=D` first was the right
one, and it settles the choice: the file was **never deleted**, it was never
committed *to this branch*. It exists on both `origin/feature/lean` and
`origin/feat/build-feed`, byte-identical on the two, and never appeared on
`feature/big-merge` or `main`. So this is a casualty of the big merge, and the
right response is the first of the two options: restore the tool.

Restored `scripts/kant-debug.mjs` byte-for-byte from `origin/feature/lean`. All
twelve symbols it imports (`classify`, `describe`, `report`, `renderReport`,
`single`, `parseConfig`, `parseRelay`, `DEFAULT_CONFIG`, `probeRelay`,
`effectiveRelay`, `diagnose`, `explain`) are exported by the copies on this
branch, so the restore needed no adaptation.

Both suites are now in the core run and green: `web/carddebug-test.mjs` and
`scripts/carddebug-test.mjs`, 73/73 each. `npm run verify`: 41/41.
