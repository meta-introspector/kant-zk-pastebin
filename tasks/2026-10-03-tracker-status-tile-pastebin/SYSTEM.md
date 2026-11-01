# Task
- **Name:** tracker-status-tile-pastebin (TRK-1)
- **Priority:** P2
- **Opened:** 2026-10-03 by agent qoder
- **Related:** tracker PRs #234 (docs), issue #223 (Gate 0), OTC desk PB-22/23/24, pastebin-tile-system skill
- **Tags:** 2026-10-03-tracker-statu

## Goal
Make the kant-pastebin the CTO/desk view for the Twitter-storm tracker: on each state change, compose a **tracker gate board** as a pasted tile; agents and the operator read the newest board instead of polling repo + services. (First manual pilot paste was done 2026-10-03 — this task turns it into a repeatable composer.)

## Data sources (all local)
- Gate state: `gh` read of mfng/tracker issues #223–#226 + PR #234 + AV-1 hold flag
- Fleet aggregates: `scripts/account-watchlist.ts` output **reduced to counts only** (due, next-minute, fleet size 1,646)
- Aristotle delivery state: `aristotle_status.json` `latest_run_status`
- Proof blocks: tasks shmem pool `:8154` (query2proof convention)

## Board format
Plain text (pastebin is text-first; tile auto-detect keys on `title`/`keywords`):
- title: `tracker-gate-board <UTC-date>`; keywords: `["tracker","gate-board","status"]`
- lines: `Gate0 #223: #215 done | #220 HELD(AV-1) | #217 queued`, `Gate1 #224 …`, fleet counts, `aristo main: COMPLETE_WITH_ERRORS`, open risk ids (PB-22/23/24/27)
- POST via API: `curl -s -X POST http://127.0.0.1:8090/paste -H 'content-type: application/json' --data @board.json` (contract read from `scripts/kant-pastebin.mjs`: `{content,title,description,keywords,reply_to}`; chain boards with `reply_to`)

## Hard constraints — PII gate
- **Never** paste account handles, names, hashes, or anything derived from `inputs/accounts.txt`; counts only.
- Never paste token/key-shaped strings; run a pre-post filter (reject if any line matches `[a-z]{3,4}_[0-9a-f]{32,}` or known secret prefixes) — PB-27 is the cautionary tale: **description text lands verbatim in the public index.**
- Spool is world-readable; treat every paste as public and permanent.

## Done when
`scripts/tracker-gate-board.sh` (in tracker repo worktree) composes + PII-filters + posts one board; board renders in the pastebin UI; second board chains via `reply_to`; proof block `proof/tasks/tracker-gate-board/<ts>` with `has_tracker_tile_live=true`.

## Pilot 2026-10-03T12:01Z (agent qoder) — board 1 live
- Paste id `20261003_120035_tracker_gate_board_…` CID `bafkfbf8ccef8dbe58bb4baf5af2beba647c`, 1,633 B, confirmed in `index.jsonl`.
- Proof blocks `proof/tasks/tracker-gate-board/2026-10-03T12:01:09Z` (`has_completed`, `has_board_pasted`); standing goal query returns both; results write-back worked (`sparql/results/…`).
- **Filter lesson**: the key-shaped regex must NOT include `_`/`-` in its 32+-char run class — legit paste-slug ids tripped it (2 false positives); with separators excluded the scan is clean. Use prefixes (`xpl_`, `sk-`, `gh[pousr]_`, `eyJ…`, bare-hex36+, base64-32+) + `key|token|secret…` assignment forms.
- Remaining for "done": scripted composer + `reply_to` chaining (board 2) + render check in UI.
