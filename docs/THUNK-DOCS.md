# Thunk Infrastructure: Nora-to-Thunk Bridge

**Date:** 2026-10-03 · **Status:** green · **Branch:** `feature/big-merge`

**Companion documents:** [`VERIFICATION.md`](../tasks/thunk-server/VERIFICATION.md), [`SANDBOX.md`](../tasks/thunk-server/SANDBOX.md), [`THUNK-CYCLE.md`](../tasks/thunk-server/THUNK-CYCLE.md), [`MESH_NETWORKING.md`](../MESH_NETWORKING.md)

## Overview

The thunk infrastructure turns any package registry into a source of **portable, content-addressed, sandbox-executed transition functions**. The Nora-to-Thunk bridge is the first adapter: it reads published Rust crates from Nora, wraps each one as a thunk, and advertises them across the Kant-ZK relay mesh.

The same adapter pattern can be applied to any registry (Nora/cargo, PyPI, npm, GitHub tags, Twitterstorm modules) — see "Extending to Other Registries".

## What a thunk is

A thunk is a first-class state machine:

```js
// Dialect: module.exports, no require/import allowed
module.exports = {
  reduce(state, input) { /* return new state */ },
  initialState: { /* ... */ }
};
```

Key properties:

| Property | Why it matters |
|---|---|
| **Content-addressed** | `thunk id = name@version:<sha256-of-source-plus-refs>`. The id is a hash over source bytes and declared refs only — `name`/`version` are human labels, not identity. |
| **Portably serializable** | The transducer is captured as source text; the definition travels as bytes, not as a live object. |
| **Sandboxed** | Executed in a `node:vm` context with a `module` shim, `globalThis.console` deleted, and dynamic `import()` refused at load time. No `process`, `Buffer`, timers, or host globals leak in. |
| **Stateful & shareable** | `snapshot()` captures the state; `resume(snapshot)` restores it; `share()` produces a manifest (definition-only fingerprint) for safe cross-peer exchange. |

## Architecture

```
+------------------+     +------------------+     +-----------------------+
| Nora registry    |     |  nora-thunk-     |     |  thunk-server (9787)  |
| :4000            |---> |  thunk-bridge    |---> |  (stores/runs/shares) |
| rust crates      |     |  (reads metadata |     +-----------+-----------+
+------------------+     |   -> thunk defs) |               |
                         +------------------+               |
                                                                v
+------------------+               +-----------------------+    +-----------------+
|  Relay mesh      |<--------------|  publish-to-all      |--->|  Nix flakes     |
|  :8787           |    (announce  |  (nix/nora/forge)    |    |  package.json   |
|  /ws/{room}      |               +-----------------------+    |  git repo       |
+------------------+               +-----------------------+    +-----------------+
         ^                              |
         |            (pub/sub between peer thunk-servers)
         +--- /ws/thunk-servers
```

### 1. `nora-thunk-bridge.mjs` — the adapter

Located at `server/nora-thunk-bridge.mjs`. One process, one pass:

1. Reads crate directories from Nora's storage (`/mnt/data1/nora/storage/cargo/<crate>/metadata.json`).
2. Parses each `metadata.json`, extracting `crate.name` and the latest `crate.versions[0].num`.
3. Wraps each crate into a thunk definition via `makeThunkFromCrate()` — a `reduce(state, input)` transducer plus `initialState`.
4. Loads the source into a `Thunk` (`server/thunk.mjs`) and persists it in a `ThunkStore` (`server/thunk-store.mjs`, JSON files under `thunks/<id>.json`).
5. Announces each published thunk's availability on the relay's `thunk-servers` room (`/ws/{room}`), so other peer servers can `GET /thunk/{id}`.

Environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `NORA_URL` | `http://localhost:4000` | Nora registry API base |
| `NORA_STORAGE` | `/mnt/data1/nora/storage/cargo` | Path to Nora's cargo crate directory |
| `THUNK_SERVER_PORT` | `9787` | Thunk server HTTP port to store into |
| `RELAY_URL` | `http://localhost:8787` | Chat/p2p relay base |
| `DISCOVERY_ROOM` | `thunk-servers` | Relay room used for mesh discovery |
| `THUNK_STORE_DIR` | `/tmp/thunks-bridge` | Thunk persistence directory |

Run:

```bash
node server/nora-thunk-bridge.mjs
```

Each line reports: `[nora-thunk-bridge] <crate>@<version> -> <thunk-id> (announced: true)` with a final `okCount/total` summary.

### 2. `thunk-server.mjs` — the mesh endpoint

HTTP endpoints:

| Endpoint | Method | Purpose |
|---|---|---|
| `/health` | GET | `ok`, `serverId`, `peers`, `thunks`, `version` |
| `/thunk/store` | POST | `{source, name, version}` → stores a thunk, returns `{ok, id}` |
| `/thunk/run` | POST | `{thunkId, input}` → `{ok, id, state, effects}` |
| `/thunk/share` | GET | `{?id}` → `{manifest, state, source}` (safe to send to peers) |
| `/thunk/list` | GET | list persisted thunks |
| `/thunk/publish` | POST | `{thunkId, targets}` → publish to `nix`/`nora`/`forge` |
| `/peers` | GET | discovered peer servers |
| `/thunk/demo` | POST | demo: load `example-compactor.mjs`, run a compaction |

Mesh protocol (WebSocket `/ws/thunk-servers` + HTTP `/room/thunk-servers`):

- **Presence**: `POST /room/{room}` with `{type: thunk-server-ping, serverId, endpoint, timestamp}`. Peers are tracked in `peers` and exposed at `/peers`.
- **Pings** every 30s to keep the mesh alive.
- **Request/response**: a peer receiving a `{type: thunk-request, thunkId, action}` can serve `run` or `share`.

### 3. `thunk-publish.mjs` — publish back to registries

Three targets, each receiving a `publishBundle(thunk)` = `{manifest, state, source, name, version, id}`:

- **Nix** (`publishToNix`): writes `thunk-source.mjs`, `default.nix`, `flake.nix`, `thunk.json` under `/tmp/nix-thunks/<safeName>`.
- **Nora** (`publishToNora`): writes `package.json` + `index.mjs` wrapping the thunk source, then `POST /npm/publish` to the Nora registry.
- **Forge** (`publishToForge`): writes `thunk.mjs` + `thunk.json` metadata + README under `/tmp/forge-thunks/<repoName>`; creates a Forgejo repo via its API.

Run via `thunk-server POST /thunk/publish/demo` (targets all three) or `POST /thunk/publish` with a `targets` array.

### 4. `thunk.mjs` + `thunk-store.mjs` — the core

- **`Thunk.load(source, name, version, schema?, refs?)`** — compiles the source *inside* the context (`vm.Script(...).runInContext`), extracts `reduce` + `initialState`, and builds the thunk with the content hash. Dynamic `import`/`import.meta` in source is refused at load.
- **`Thunk.apply(input)`** → `{state, effects}` — runs one transition, recording `state-change` in effects.
- **`Thunk.snapshot()` / `resume(snapshot)`** — durable state capture.
- **`Thunk.share()`** → `{manifest, state, source}` — the portable bundle.
- **`ThunkStore`** — disk-backed store under `<dir>/<id>.json` with an in-memory cache; `store()`, `get()`, `list()`, `remove()`, `snapshot()`.

## End-to-end example

```bash
# 1. Run the mesh-aware thunk server
node server/thunk-server.mjs --port 9787

# 2. Run the bridge (fetches Nora crates -> stores -> announces)
node server/nora-thunk-bridge.mjs

# 3. Query the store via HTTP
curl -s http://localhost:9787/thunk/list | jq .

# 4. Run a transition on a known thunk id
curl -s -X POST http://localhost:9787/thunk/run \
  -H "Content-Type: application/json" \
  -d '{"thunkId":"<id>","input":{"type":"fetch"}}' | jq .

# 5. Share a thunk safely across the mesh
curl -s http://localhost:9787/thunk/share?id=<id> | jq .
```

## Extending to Other Registries

Every adapter is the same shape:

1. **`noraCrateList()` → `Promise<{name, version, metadataPath, ...}>[]`** — enumerate available packages for the target registry. For Nora it scans `fs.readdirSync(NORA_STORAGE)` and parses `metadata.json`; for a registry API you'd instead `GET /api/v1/packages` and parse the response.
2. **`makeThunkFromCrate(crate)` → `{name, version, source}`** — produce thunk source text. Nora maps a compiled Rust crate to a metadata-crawler transducer; for other sources you map whatever assets the package exposes (docs, ABI, schema) into `reduce`/`initialState`.
3. **`storeThunk(thunk)`** — reuse `Thunk.load` + `ThunkStore.store` unchanged.
4. **`advertiseOnRelay(id, name, version)`** — reuse the relay announcement unchanged.

To apply this to `~/projects/twitterstorm/`, you'd:

- Replace the enumeration step with a walk of `twitterstorm/` module files or a git tag list.
- Wrap each module's public API as a thunk source (export its reducer + initial state).
- Point `THUNK_STORE_DIR` to a twitterstorm-specific store and re-run the bridge.

The mesh + store + server code is reused verbatim.

## Verification

Health is maintained by the claim ledger:

```bash
node scripts/thunk-claims.mjs           # health/defect claims, exits 1 on failure
node scripts/thunk-claims.mjs --json
```

The ledger covers sandbox escapes (`sandbox-has-no-require`, `sandbox-refuses-console`, `sandbox-refuses-dynamic-import`), the content-hash shape, and call-id separation.

## Next steps

1. **Twitterstorm thunkification** (`~/projects/twitterstorm/`): apply the adapter pattern above to tweet-stream and timeline modules.
2. Add `thunk-claims` entries for bridge-specific behavior (crate discovery, announce round-trip).
3. Persist the bridge's announced inventory on disk so a restarted server can re-join the mesh with the same inventory.
