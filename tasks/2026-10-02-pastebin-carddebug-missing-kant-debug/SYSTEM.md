# Task: pastebin-carddebug-missing-kant-debug

**Status:** open
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
