---
name: pastebin-lean-local-archive-server
description: DONE 2026-10-03 — minimal-cost p2p archive merged to kant-zk-pastebin main (05f2fba). No R2: archival is local DiskBlocks (--blocks-dir), public block storage is the CF Pages snapshot (publisher --blocks emits b/<cid>.bin raw bytes), p2p routing via relay --block-mirrors, pair.mjs pulls local⇄Pages. Deploy follow-ups open (services enable, PAGES_URL). Trigger when deploying the archive pair or extending block pinning.
priority: HIGH
---

# local-archive-server (pastebin-lean)

DONE (minimal-cost shape, superseding the R2 design the same day):
`server/disk-blocks.mjs` (DiskBlocks, `--blocks-dir`/KANT_BLOCKS) gives
the relay durable blocks with replay + corruption refusal; the CF worker
stays a pure room router (no R2); `server/publisher.mjs --blocks` emits
`b/<cid>.bin` raw bytes + `b/<cid>.html` pages into the CF Pages
snapshot (the public block storage); the relay routes block misses via
`--block-mirrors` (CID-verified, `x-kant-block-via`);
`server/pair.mjs` pulls the Pages snapshot into a fresh local server.
systemd: `kant-archive.service` (:8788), `kant-pair.service`.
Full spec + open deploy follow-ups in [SYSTEM.md](SYSTEM.md).
