# Rust → WASM p2p file sharing, CI check-ins, and the twin deployments — 2026-10-01

Campaign day three for the kant stack: the UUCP invite room, a CI-built and
published CLI, agent check-ins to a relay room from GitHub Actions, and the
pastebin core compiled from Rust to WebAssembly to power file sharing in
p2p chat rooms — deployed as two protocol-identical twins (systemd node
relay and a Cloudflare Worker).

## 1. Joining the UUCP invite room

The spool file `/var/spool/uucp/pastebin/20261001_181922_https_kant_relay_…txt`
carried a `kzinvite` envelope. Filename and fragment hex-decode to:

| field | value |
|---|---|
| relay | `https://kant-relay-v1.purple-fire-b881.workers.dev` |
| tag | `kzinvite` (`6b7a696e76697465`) |
| room secret | `77d82489…78a9` |
| inviter | `peer-9dqvd` |

`scripts/kant-cli.mjs` (already in the repo, `bc70c049`) joined, read, and
posted. Session evidence: hello at cursor 26, inviter replied "i see you",
room at cursor 28 by the end of the join phase. Later posts: CLI release
note (38), CI room invite, wasm launch note (71).

## 2. kant-cli: CI build, publication, and hosting

`dist/kant-cli.mjs` is a single self-contained file (zero runtime deps,
Node ≥ 18) built by `scripts/build-cli.mjs` (esbuild via npm package or a
standalone binary on PATH). `--version` is stamped at build time
(`KANT_VERSION`). Config resolution is bundle-safe:
`$KANT_CONFIG` → `kant.config` next to the running file → `../kant.config`
→ `../web/kant.config` → built-in defaults.

Publication paths:

* **GitHub Actions** — `.github/workflows/kant-cli.yml` runs
  `scripts/cli-test.mjs` (77 checks), builds the bundle, attaches it as an
  artifact, and publishes a GitHub Release on `v*` tags.
* **The site itself** — `.github/workflows/pages.yml` copies the bundle
  into the Pages artifact: `/kant-cli.mjs` + sha256 + version sidecars,
  download link in `static-pastebin/index.html`.
* **Agent skill** — `skills/kant-cli/` documents join/read/say/watch, the
  check-in flow, the wasm core, and the twin deployments.

Test-suite repairs that made CI possible:

* `scripts/cli-test.mjs` imported sibling wrapper modules instead of the
  `web/` pure library → fixed to `../web/…`.
* `scripts/two-agents.sh` was never committed → restored from the sibling
  checkout, then made hermetic (`--pass-db` inside its temp dir).
* `server/` was untracked entirely → `server/relay.mjs` +
  `server/pass-store.mjs` committed so CI has a relay to spawn.
* `pass-store.mjs` uses Node 24's `node:sqlite` → CI runs Node 24.
* The relay eagerly opened `/var/lib/kant-zk/passes.sqlite`, which crashes
  on runners → `makePassStore()` falls back to `os.tmpdir()` when the
  preferred path is unusable; an explicitly configured path still fails
  loudly.

## 3. CI check-ins to a relay room

`scripts/ci-checkin.mjs` posts one stateless, fail-soft line into a room.
Config comes only from the environment — no state file, so concurrent
jobs cannot race. Missing config exits 2 before anything is sent; relay
errors are logged and ignored (exit 0) so a chat outage never fails a
build.

Dual transport per build:

1. **kz chat line** (witness-verified) into the CI room — run id, status,
   commit subject, log link. Room key: `KANT_CI_SECRET` Actions secret;
   relay: `KANT_CI_RELAY` variable.
2. **fleet record** — a plain-JSON line (`kind/repo/workflow/status/
   runId/commit/url/at/sender`) into the named room
   `twitterstorm-fleet-builds` (`KANT_FLEET_RELAY`/`KANT_FLEET_ROOM`).
   This is the same named-room protocol as
   `twitterstorm/tracker → scripts/peer-relay-discovery.ts`, so tracker
   nodes can discover build records and sink them into their sqlite,
   then replicate via the existing `/api/db/sync` snapshot flow.
   Public, append-only: no credential-shaped fields, ever.

The room secret never touched git (`gh secret set`). Verified live:
GitHub-hosted run 36919561267 checked in on both transports; the fleet
room read back the JSON record at cursor 2.

## 4. The Rust core compiled to wasm

`pastebin-wasm/` is a new crate (`cdylib` + `rlib`, wasm-bindgen 0.2.129
pinned to the installed CLI, `opt-level = "s"`, LTO):

* `cid_of_bytes` — CIDv1 / raw (0x55) / sha2-256, base32 multibase,
  byte-identical to `web/kant-ipfs.mjs` `cidOf()` and to
  `kubo add --cid-version=1 --raw-leaves` for ≤ one-chunk inputs;
* `cid_identity` — the 36 identity bytes behind a CID string, with form
  validation;
* `chunk_plan` — the ≤ 256 KiB single-block discipline;
* `kzcid_record` / `parse_kzcid_record` — the room-record JSON codec,
  refusing credential-shaped fields before anything reaches a public room.

`scripts/build-pastebin-wasm.sh` builds wasm32 + bindgen `--target web`
into `web/`, then runs `scripts/wasm-crosscheck.mjs`: **25/25** checks —
wasm CIDs equal the JS CIDs byte-for-byte from 0 B to the 256 KiB
boundary, identity rejects junk, records round-trip, guards fire.
Rust unit tests: 4/4.

`web/kant-ipfs.mjs` prefers the wasm core (lazy init, node-aware: the
`--target web` glue fetches by URL in browsers and accepts explicit bytes
under Node) and keeps the pure-JS path as fallback. `web/p2p.html` shows
which core is live (`rust core ok` / `JS fallback`).

End-to-end proof (`scripts/p2p-wasm-filetest.mjs`): the real node relay,
two `P2PApp` peers, A publishes a file (CID computed by the Rust core),
B receives the kzcid record, fetches the embedded bytes, and the wasm
recompute agrees — PASS, exit 0, CI-wired.

## 5. The twins

One protocol (`server/relay.mjs` ⇄ `server/worker.js`), two runtimes:

| | systemd twin | Cloudflare twin |
|---|---|---|
| process | `kant-p2p-relay.service`, node 24, :8796 | `kant-zk-relay-wasm` worker, DO per room |
| serves | `web/` (p2p.html + wasm core) | same via `[assets]` |
| edge | `https://solana.solfunmeme.com/p2p-relay/` | `https://kant-zk-relay-wasm.purple-fire-b881.workers.dev` |
| health | `{"ok":true,…}` verified | `{"ok":true,…,"platform":"cloudflare"}` verified |

Deployment notes:

* `server/wrangler.toml` was undeployable (main pointed at
  `lean-relay.mjs`, placeholder KV id). Now: `worker.js` main,
  `account_id` pinned, assets = `../web`.
* Account topology discovered via the API: `0ceffbadd0…` =
  `jmikedupont2.workers.dev` (currently **rate-limited, error 1027** —
  plan limits; the old prod relay `kant-zk-relay` lives there and the
  limits are why the wasm twin was initially unreachable from that
  account), `2c5da35f…` = `purple-fire-b881.workers.dev` (kant account —
  healthy, hosts the wasm twin), `0fd159a4…` = `twitterstorm.workers.dev`.
  The token at `~/.cloudflare` spans all three.
* The systemd twin was repointed from the throwaway worktree to the repo
  checkout so it serves the wasm core; the service unit changed
  `WorkingDirectory` only.
* Cross-twin proof: two peers joined a room on the CF worker from the
  node process, A published, B fetched identical bytes, wasm recomputed
  the same CID — PASS. Room round-trip (`POST` → poll) verified by curl
  on both twins.

## 6. State and follow-ups

* Branch `feature/wip` on `meta-introspector/kant-zk-pastebin`; PR opened
  against `main` (see the PR description for scope).
* CI workflow green including the Rust→wasm leg.
* Watchers: main room log `/tmp/kant-buffy-watch.log`, CI room
  `/tmp/kant-ci-watch.log` (state `~/.kant/ci-room.json`).
* Follow-up candidates: migrate `kant-zk-relay` off the rate-limited
  account; fleet sink that tails `twitterstorm-fleet-builds` into sqlite;
  browser gui2proof e2e for the wasm share path through the CF twin;
  gitignore for `dist/` (the bundle is a build product).
