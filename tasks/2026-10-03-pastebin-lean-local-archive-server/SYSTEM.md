# Task: pastebin-lean local archive server (disk-backed relay Blocks)
- **Priority:** P2
- **Tags:** lean

**Status:** DONE (code merged; deploy follow-ups open) · **Priority:** HIGH · **Project:** kant/pastebin-lean
**Found:** 2026-10-02, during the integration session (task 2026-10-02-pastebin-lean-arist-integration)
**Repo:** /home/mdupont/projects/pastebin-lean (main = **05f2fba**, commits 556ae58 + 565343a + 05f2fba)

## Outcome (2026-10-03)

Built and merged to kant-zk-pastebin main (mirror
`/mnt/data1/git/github.com/mdupont/kant-zk-pastebin.git`). The initial
design (556ae58/565343a) put an R2-backed block store on the CF worker;
**that was superseded the same day** by Mike's cost constraint —
"we want only p2p data archival and public block storage and p2p
router. minimal cost." — and rebuilt as 05f2fba. Final design:

1. **No R2, no extra CF state.** The R2 worker block store was reverted
   (`worker.js`/`wrangler.toml` back to the pure room router — no block
   endpoints on the worker at all). Zero paid CF surface.
2. **p2p data archival = local disk only.** `DiskBlocks`
   (`server/disk-blocks.mjs`) under `--blocks-dir`/`KANT_BLOCKS`: bytes at
   `<blocks-dir>/<roomRef>/<cid>.bin`, per-room `index.json` (pins + gas
   ledger), full replay on boot, CID re-verified on every read (a
   corrupted file is a 404, never served).
3. **public block storage = the CF Pages snapshot itself.**
   `publisher.mjs --blocks <relay>` emits `b/<cid>.bin` — the raw bytes,
   content-addressed — alongside `b/<cid>.html` + `blocks.json` in the
   static snapshot that `--pages-deploy` pushes to CF Pages. Static
   hosting of immutable CID-verified bytes: free tier, semantically exact.
4. **p2p router = the relay.** Block GETs that miss the local store are
   routed through `--block-mirrors` (comma-separated relay bases, tried in
   order; first copy that verifies against the CID wins, served with
   `x-kant-block-via`). A lying mirror can refuse service, never corrupt.
   Flags: `--block-mirrors` / `KANT_BLOCK_MIRRORS`, `--block-mirror-ms`
   (default 8000).
5. **Pairer** (`server/pair.mjs`) — pairs local ⇄ CF Pages snapshot:
   pulls `archive/blocks.json`, fetches `archive/b/<cid>.bin` for blocks
   local lacks, pins them (CID-verified by the relay). Push-side is the
   publisher cycle. A fresh local server converges to the public archive
   of record unaided. Args: `--pages <url>` (required), `--local`,
   `--rooms`, `--archive-dir` (room discovery by handle only),
   `--interval` (default 300), `--once`.
6. **systemd** (`server/kant-archive.service`, `server/kant-pair.service`) —
   archive relay on :8788 with `--blocks-dir`/`--archive-dir` under
   `/var/lib/kant-zk` and `--block-mirrors http://127.0.0.1:8787`;
   pairer against `--pages ${PAGES_URL}` (env, default
   `https://kant-zk-pastebin.pages.dev`), 300s cycle.

**Tests:** `server/disk-blocks-test.mjs` (5: pin/serve, wrong-cid refusal,
restart replay, corruption refusal, gas budget) + `server/pair-test.mjs`
(rewritten for the static-snapshot shape, 5: pin+list, pull convergence
from a Pages stand-in, idempotent cycle, restart replay, mirror routing
with verification). Full battery **21 suites, 0 fail**.

## Problem

The relay's `Blocks` class (`server/relay.mjs`, ~line 130) is **memory-only**.
`--archive-dir` writes ndjson *metadata* only — on restart every pinned chunk
is gone. A restarted relay cannot serve any previously published kzfile
artifact, and room line replay does not exist either: history lives only in
process memory.

The publisher side already exists: `server/publisher.mjs` (commit `7838df3`)
pushes pastebin spool → Cloudflare Pages. The gap is purely the local relay's
durability.

## Fix

1. **Disk-backed Blocks** under `--archive-dir`: persist chunk bytes
   (CID-keyed files or a small pack format — content-addressed, dedup by CID),
   not just ndjson metadata. Rebuild the in-memory index from disk on startup.
2. **Room line replay on startup**: persist room lines (they are already
   envelope-encoded — use `parseManifest`-style decoding, not
   `startsWith("kzfile")`) and replay them into the Blocks store + room
   history when the relay boots.
3. **systemd unit variant** with `ReadWritePaths=` on the archive dir
   (follow the kant-relay.service hardening pattern: NoNewPrivileges,
   PrivateTmp, PrivateDevices; never run as root — dedicated system user).

## Verify

- Restart the relay; a kzfile published before the restart must fetch+decrypt
  via the file-drop UI (two-browser e2e, `scripts/kant-file-e2e.mjs`
  pattern — in-process mock relay, capture blobs via createObjectURL
  interception, room id = `roomOf(secret)`).
- Suite stays 19/19 green (`web/*-test.mjs` + `test/test-kant-p2p.mjs`).

## Constraints

- Do not regress the gas ledger accounting that lives next to the Blocks store.
- Nix/system-manager deploy, not ad-hoc unit files (see
  pastebin-unmanaged-nginx-configs for why unmanaged config bites).

## Follow-ups (OPEN)

- **Enable the services:** copy `kant-archive.service` + `kant-pair.service`
  to /etc/systemd/system (or system-manager) and set the real `PAGES_URL`.
- **Publisher invocation:** add `--blocks http://127.0.0.1:8788` (or env)
  once the archive relay runs, so block pages emit on each cycle.
- **Port consolidation:** the old relay on :8787 (`kant-relay.service`)
  and the archive relay on :8788 are separate; eventually the archive
  relay should replace :8787 or nginx should route both.
- **Publisher e2e:** end-to-end check of the emitted block pages
  (`b/<cid>.html` + `b/<cid>.bin` + `blocks.json`) on a real Pages deploy.
- **Pairer push cadence:** the pairer's push side only counts blocks the
  publisher will emit — actual edge arrival is the publisher cycle
  cadence, not the pairer's.

## SPARQL Context

```
Blocks mentioning '2026-10-03-pastebin-lean-local-archive-server' in descriptions: 8
  01551220  n0x-pi/.dotagents/tasks/2026-10-03-pastebin-lean-local-archive-server/AGENTS.md  [969 bytes]
  01551220  dotagents/tasks/2026-10-03-pastebin-lean-local-archive-server/SYSTEM.md  [5790 bytes]
  01551220  dotagents/tasks/2026-10-03-pastebin-lean-local-archive-server/SKILL.md  [1212 bytes]
  01551220  n0x-pi/.dotagents/tasks/2026-10-03-pastebin-lean-local-archive-server/SKILL.md  [1212 bytes]
  01551220  n0x-pi/.dotagents/tasks/2026-10-03-pastebin-lean-local-archive-server/SYSTEM.md  [5790 bytes]
  ... and 3 more

```

## Agent Sessions

- `--mnt-data1-time-2026-05-may-31-n0x-pi-.dotagents-tasks-integrate-dasl-lean-proofs--` → `/home/mdupont/.pi/agent/sessions/--mnt-data1-time-2026-05-may-31-n0x-pi-.dotagents-tasks-integrate-dasl-lean-proofs--/2026-07-08T19-18-23-192Z_019f432a-c0d7-729b-a03f-50db48aef9d4.jsonl`
- `--mnt-data1-time-2026-05-may-31-n0x-pi-.dotagents-tasks-2026-07-20-lean-novo-introspector--` → `/home/mdupont/.pi/agent/sessions/--mnt-data1-time-2026-05-may-31-n0x-pi-.dotagents-tasks-2026-07-20-lean-novo-introspector--/2026-07-23T21-37-37-320Z_019f90e9-9e28-7b0d-bb00-ae9cde81fed5.jsonl`
- `--mnt-data1-time-2026-05-may-07-arist-f2265b5a-a673-4176-84aa-796c0ac9ddfa-minilean--` → `/home/mdupont/.pi/agent/sessions/--mnt-data1-time-2026-05-may-07-arist-f2265b5a-a673-4176-84aa-796c0ac9ddfa-minilean--/2026-10-20T14-12-36-427Z_01a159a8-2dcb-76ef-a378-d2e821c2471e.jsonl`
- `--mnt-data1-time-2026-05-may-31-n0x-pi-tasks-fix-pastebin-search--` → `/home/mdupont/.pi/agent/sessions/--mnt-data1-time-2026-05-may-31-n0x-pi-tasks-fix-pastebin-search--/2026-07-12T19-24-17-136Z_019f57c9-9770-7666-94b3-aa0d49178034.jsonl`
- `--mnt-data1-time-2026-05-may-31-n0x-pi-.dotagents-tasks-fix-llm-agents-runners-cleanup--` → `/home/mdupont/.pi/agent/sessions/--mnt-data1-time-2026-05-may-31-n0x-pi-.dotagents-tasks-fix-llm-agents-runners-cleanup--/2026-07-04T14-44-11-955Z_019f2d96-4a33-7bb8-8bd5-ea5363e602fc.jsonl`
- `--mnt-data1-time-2026-05-may-31-n0x-pi-.dotagents-tasks-lean-proof-goappipeline--` → `/home/mdupont/.pi/agent/sessions/--mnt-data1-time-2026-05-may-31-n0x-pi-.dotagents-tasks-lean-proof-goappipeline--/2026-09-11T23-36-29-128Z_01a092d4-68c8-7127-b724-cd6c0a43257d.jsonl`
- `--mnt-data1-time-2026-05-may-31-n0x-pi-tasks-dasl-lean4-fuzz-integration--` → `/home/mdupont/.pi/agent/sessions/--mnt-data1-time-2026-05-may-31-n0x-pi-tasks-dasl-lean4-fuzz-integration--/2026-07-08T19-18-22-962Z_019f432a-bff2-7264-afb9-c89aa44f8f79.jsonl`
- `--mnt-data1-time-2026-09-september-18-lean-worker-worktrees-bone-proof-loop-close-minimal--` → `/home/mdupont/.pi/agent/sessions/--mnt-data1-time-2026-09-september-18-lean-worker-worktrees-bone-proof-loop-close-minimal--/2026-10-19T18-39-28-133Z_01a15576-2385-75d7-a59c-9c0ea7882ab6.jsonl`
- `--mnt-data1-time-2026-10-october-04-lean-workers-union--` → `/home/mdupont/.pi/agent/sessions/--mnt-data1-time-2026-10-october-04-lean-workers-union--/2026-10-08T15-16-22-788Z_01a11c16-4083-76ca-b959-c2a11eda04da.jsonl`
- `--mnt-data1-time-2026-05-may-31-n0x-pi-.dotagents-tasks-verify-microlean-type-system--` → `/home/mdupont/.pi/agent/sessions/--mnt-data1-time-2026-05-may-31-n0x-pi-.dotagents-tasks-verify-microlean-type-system--/2026-07-08T19-18-22-847Z_019f432a-bf7f-7958-8f4f-80a02f355245.jsonl`
- `--mnt-data1-time-2026-09-september-18-lean-worker--` → `/home/mdupont/.pi/agent/sessions/--mnt-data1-time-2026-09-september-18-lean-worker--/2026-10-13T09-53-55-260Z_01a134ae-d43b-70b5-9fdd-916cb0be6f55.jsonl`
- `--mnt-data1-time-2026-05-may-31-n0x-pi-.dotagents-tasks-groups-mathlib-2026-07-24-lean-drisl-canonicity--` → `/home/mdupont/.pi/agent/sessions/--mnt-data1-time-2026-05-may-31-n0x-pi-.dotagents-tasks-groups-mathlib-2026-07-24-lean-drisl-canonicity--/2026-09-12T22-15-03-166Z_01a097b0-36fe-72c2-9a40-775b01b904ee.jsonl`
