# kant p2p webapp — IPFS artifacts over relay rooms, wasm experiments in-browser

Goal-base #8/#11 realized on the kant-zk stack: **peers meet in a relay room, share
artifacts by IPFS CID, and run wasm experiments locally** — the relay carries
coordination lines (small JSON), never bulk bytes unless a peer explicitly embeds a
fallback copy, and every byte that moves is verified against its CID on arrival.

## Pieces

| File | Role |
|---|---|
| `web/kant-ipfs.mjs` | CIDv1/raw/sha2-256 computed **client-side** (matches `kubo add --cid-version=1 --raw-leaves` for ≤256 KiB), kubo RPC add+pin, gateway cat, `kzcid` room records (pinned or embedded-fallback) |
| `web/kant-p2p.mjs` | `P2PApp`: presence, publish/subscribe over any relay transport (`RelayClient`/`RelaySocket`), dedupe by CID, repin relay copies into local kubo, experiment dispatch |
| `web/p2p.html` | UI: join room → publish file/text → fetch/verify → run experiments |
| `web/kant-wasm.mjs` + `dist/kant_kernel.wasm` | the **Lean-proved** kernel (`merge_cids`, `mk_cid`, …) — experiments run on math with proofs |
| `web/arist-wasm.mjs` + `web/aristotle_wasm*` | vendored `aristotle-wasm` crate (from the arist repo) as the heavier experiment module: project validation, deploy-config generation, Aristotle API client |
| `experiments/aristotle-wasm/` | the vendored crate + `prebuilt/aristotle_wasm.wasm` |
| `scripts/build-arist-wasm.sh` | rebuild the glue (wasm-bindgen `--target web`); falls back to the prebuilt blob when cargo lacks the wasm target |
| `test/test-kant-p2p.mjs` | 20 unit tests: CID shape/RFC4648 vectors, record envelopes, kubo/gateway fallbacks, lying-gateway rejection, relay dedupe, oversized-line refusal |

## Run it

```bash
node server/relay.mjs --port 8787 --host 127.0.0.1 --static web
# open http://127.0.0.1:8787/p2p.html — join, publish, share the room name
```

Two browser windows in the same room = two peers; publish from one, fetch from the
other. With a local kubo running (RPC 5001 / gateway 8080) publishes are pinned and
`via=ipfs`; without one they ride the room as embedded fallbacks (`via=room`) and any
peer with kubo can `repin` them, re-announcing `pinned:true`.

## Deploy

- **Existing edge:** the host already fronts the relay at `https://solana.solfunmeme.com/relay/`
  (`services.d/kant-relay.conf` → 127.0.0.1:8787). Redeploying the web dir with these
  files (systemd unit `kant-relay.service` points `--static` at a checkout/nix store
  path) exposes `/relay/p2p.html`. This repo's copy of the unit shows the canonical flags.
- **Any static host / object store / pinned IPFS dir:** the app is plain ESM — serve
  `web/` anywhere; point `relay` at any kant-zk relay (or the Cloudflare Worker in
  `server/worker.js`).
- **A peer without a server:** `file://` works for the kernel (embedded fallback in
  `kant-kernel-embedded.mjs`); the relay part needs a reachable relay.

## Security posture

- Room name = the credential (relay stores only its hash; pass-db optional per relay).
- CIDs are computed client-side and re-verified on every fetch — a lying gateway or a
  tampered room line fails the comparison and is dropped (`fetchArtifact` returns null).
- Embedded fallbacks are capped (≤256 KiB artifact, ≤60 KB room line) so a room cannot
  be inflated by bulk abuse; the relay's own `--max-line` backstops this.
- No secrets in the client: the arist module's API key is operator-supplied at runtime
  and never persisted; the relay never learns artifact bytes unless embedded on purpose.

## Status

- 20/20 unit tests, plus the repo's existing suites still green
  (wasm kernel 59 golden vectors, site 47/47, sharelog 64/64).
- Live e2e (two `P2PApp` peers, real relay, real CIDv1 `bafkrei…`):
  publish → announce → fetch → verify → `merge-cids` → matching room digests. PASS.
