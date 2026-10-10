---
name: helia-integration
priority: HIGH
depends_on: []
---

# pastebin-helia-integration

**Status:** in_progress · **Date:** 2026-10-03

## Goal

Replace the broken CDN-based Helia (`web/helia.mjs`) with a proper Nix-bundled
vendored ESM implementation in the kant pastebin webapp. This enables in-browser
IPFS operations (add/cat) with CID ground truth matching kubo, so pre-computed
CIDs always match without codec/chunking drift.

## Instructions

- Nix-bundled vendored ESM (no esm.sh CDN).
- Full libp2p dial via websockets + webtransport.
- Blocks under pre-computed CIDs using `cidOf()` from WASM core — Helia must
  never call `content.add()`; use `blockstore.put(CID.parse(cid), bytes)` +
  `pins.add(cid)`.
- Dial failures are non-fatal (swallow + fallback to gateway).
- Measure bundle size (~1-2 MB risk).

## Discoveries

- `web/` has no bundler; hand-written ESM + prebuilt artifacts
  (`pastebin_wasm.js`, `kant_kernel.wasm`, `aristotle_wasm.js`).
- `server/relay.mjs:306` serves vendored ESM with correct MIME map.
- kubo live: RPC `127.0.0.1:5001`, gateway `127.0.0.1:8081`,
  peer `12D3KooWKGj1Q...`.
- `kant-file-ipfs.mjs` delegates to `kant-ipfs.mjs` — zero changes needed.
- `P2PApp` routes through `publishArtifact`/`fetchArtifact`/`ipfsAdd` — no
  signature changes needed.
- `web/kant-helia.mjs` had `CID.parse(cid)` without importing CID (hard
  ReferenceError) and used rejected esm.sh CDN.

## Accomplished

- [x] Created `web/helia-vendor/` scaffold (`package.json`, `build.js`).
- [x] Rewrote `web/kant-helia.mjs` — Nix-vendored ESM imports, correct CID
  imports, pre-computed CID via `blockstore.put()` + `pins.add()`.
- [x] Fixed syntax errors in `web/kant-ipfs.mjs` (stray `}` tokens).
- [x] Exported `unixfsRoot` from `web/kant-ipfs.mjs` for multi-chunk path.
- [x] Verified `web/kant-ipfs.mjs` syntax (`node --check` passes).

## Not Done / In Progress

- [ ] Fix `flake.nix` syntax — `heliaVendor` derivation added but attrset
  malformed (missing semicolons, wrong `apps` structure).
  Validate with `nix-instantiate --parse flake.nix`.
- [ ] Build helia vendor: `nix build .#heliaVendor`.
- [ ] Measure bundle size: `du -sh web/vendor/helia.mjs`.
- [ ] Add Helia CID gate to `pipelight.yml` stage 17.
- [ ] End-to-end test: publish/fetch artifact using only Helia path (no kubo).

## Relevant Files

| File | Status | Notes |
|------|--------|-------|
| `web/kant-helia.mjs` | done | Rewritten — Nix-vendored ESM, pre-computed CID |
| `web/kant-ipfs.mjs` | done | Syntax fixed, `unixfsRoot` exported |
| `web/helia-vendor/package.json` | done | `helia` dependency |
| `web/helia-vendor/build.js` | done | esbuild entry point |
| `flake.nix` | todo | `heliaVendor` derivation, syntax broken |
| `web/p2p.html` | done | Already has `helia-status` span + probe CID |
| `server/relay.mjs:306` | done | MIME map correct |
| `pipelight.yml` | todo | Stage 17 needs Helia CID gate |
| `pastebin-wasm/src/lib.rs:590-615` | ref | CID ground truth test vectors |

## Next Actions

1. Fix `flake.nix` attrset syntax, validate with `nix-instantiate --parse`.
2. `nix build .#heliaVendor` — produces `web/vendor/helia.mjs`.
3. `du -sh web/vendor/helia.mjs` — verify within ~1-2 MB.
4. Insert Helia CID verification in `pipelight.yml` stage 17.
5. E2E test: publish an artifact, fetch it via Helia-only path.