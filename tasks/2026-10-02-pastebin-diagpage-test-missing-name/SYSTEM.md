# Task: pastebin-diagpage-test-missing-name

**Status:** open
**Project:** kant/pastebin, branch `feat/cli-fileshare` (PR #6)
**Found:** 2026-10-02, sweeping all worktrees and branches

## Problem

`web/diagpage-test.mjs` is 33/34:

```
FAIL: ...naming what is missing
```

This was not in the previously recorded failure list — page-test, cli-page-test,
wasm-test and carddebug-test were known; this one is new, or was missed.

It is the same shape as the page-test diagnostics finding: a diagnostics verdict
that is supposed to name what is missing and does not. Fix it together with
`2026-10-02-pastebin-page-test-diagnostics-verdict` — they may well be the same
underlying gap in `web/kant-diag.mjs`, and checking that first avoids two
competing "fixes" to one verdict.

## Verify

```sh
cd /mnt/data1/kant/pastebin-cli-fileshare
node web/diagpage-test.mjs     # want 34/34
```
