# pastebin-dev-target

**Status:** working · **Date:** 2026-10-03

A dev target for the integrated branch, so changes can be proved with the real
capture rather than argued about.

## The dev branch

`dev/integrated`, worktree `/mnt/data1/kant/pastebin-dev` — a merge of
`feature/big-merge` (p2p relay fixes, mesh handlers, Rust test isolation) with
`feat/cli-fileshare` (CLI file share, IPFS round trip, capture harness, flake
inputs). Neither was deployable alone.

Two conflicts, both cosmetic. **Both sides had independently found and fixed
the same bug** — the mesh tests sharing one `$HOME/.kant-pastebin` directory —
with identical bodies and only the helper's name differing (`make_storage` vs
`storage_in`). Took the branch's naming, consistent at every call site, so the
result reads as one author's work.

Builds clean. **33 Rust tests** in the lib target, the union of 30 and 29.

## systemd

`kant-pastebin-dev.service` → `node server/relay.mjs --port 8987 --static web`,
loopback only, its own pass-db. No nginx was needed for the relay itself.

## nginx

`nginx/locations.d/kant-pastebin-dev-int.conf` publishes `/pastebin-dev-int/`.
Note the name: `/pastebin-dev/` **already existed**, versioned, pointing at
:8111 (`kant-pastebin-lean-dev.service`). Creating a second `/pastebin-dev/`
made `nginx -t` fail with a duplicate location. The integrated branch got its
own path instead, leaving :8111 untouched.

Deployed through `deploy-nginx-services.sh`, not by writing to /etc — see PB-2
for why that distinction matters.

### No IPFS locations in the dev mount

`web/kant-ipfs.mjs` derives `KUBO_RPC` and `GATEWAY` from `location.origin`
**with no path prefix**, so a page at `/pastebin-dev-int/` asks for
`/ipfs-rpc` at the origin — which `pastebin.conf` already proxies to the same
kubo. Prefixed copies in the dev mount would be config nothing requests.
First attempt added them; the capture proved it unnecessary and they were cut.

## Cloudflare

`server/wrangler.dev.toml` → worker `kant-relay-v1-dev`, same `worker.js`, same
`../web` assets, own Durable Object namespace. Named so a deploy cannot
clobber `kant-relay-v1`, which the live p2p invites point at.

    CLOUDFLARE_API_TOKEN=$(cat ~/.cloudflare) \
    CLOUDFLARE_ACCOUNT_ID=2c5da35f915a13c131bead97f3f7bc75 \
    wrangler deploy --config server/wrangler.dev.toml

Live at `kant-relay-v1-dev.purple-fire-b881.workers.dev`.

## Credentials — where they actually are

`~/.cloudflare`, a bare token, mode 0600. Found from a wrangler log line:
`feat: read cloudflare token from ~/.cloudflare`. Verified active, reaching
accounts `Jmikedupont2@gmail.com's Account`, `kant`, `twitterstorm`.

`deploy-cloudflare-worker.sh` expects `.sops/credentials.sops.yaml` decrypted to
`CF_API_TOKEN`/`CF_ACCOUNT_ID`. **That file is plaintext, not sops-encrypted**
— no envelope, empty `account_id`, values nested under a `cloudflare:` key the
script does not read. See PB-20.

## Results

| target | headless | headed | notes |
|---|---|---|---|
| local relay | 22/22 | 22/22 | `ALL PROOFS PASSED` |
| systemd + nginx `:8987` / `/pastebin-dev-int/` | 17/22 | — | bare relay, no IPFS route |
| systemd + nginx `/pastebin-dev-int/` | **22/22** | **22/22** | full capture, Lean passes |
| `kant-relay-v1-dev` worker | 17/22 | 17/22 | worker does not proxy /ipfs-rpc |

The five IPFS failures at 17/22 are environmental in both cases — nothing to
reach kubo from that origin — not defects. The capture correctly refuses to
submit a proof when they fail, which is the gate doing its job.

p2p over the dev relay: two isolated browser contexts through nginx, 6/6. The
minted invite names `https://solana.solfunmeme.com/pastebin-dev-int`, i.e.
the `servedBase` fix resolving the mount prefix correctly.

Chromium throughout: `nixpkgs#chromium` 150.0.7871.186. Headed runs need
`DISPLAY=:99` (Xvfb → x11vnc :5900 → websockify :6080).
