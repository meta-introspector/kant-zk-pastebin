---
name: cf-test-deploy
priority: HIGH
depends_on: federated-p2p-relay, thunk-server, do-scheduler-modes
---

# cf-test-deploy

**Status:** planning · **Date:** 2026-10-03

## Goal

Deploy a **minimal test Worker** to Cloudflare as a known-good baseline.
This gives us a deployable unit we can iterate on: add thunks, scheduler,
federation, and DO modes in subsequent deploys without risking breaking the
relay that's already live on the kant account.

The strategy: **start with a Worker that only answers `/health`,
then progressively add features in follow-up deploys.**

## Instructions

- Keep the test Worker as small as possible: no Durable Objects, no
  persistence, no complex dependencies on first deploy.
- Each deploy must be idempotent and non-destructive to the existing
  `kant-zk-relay-wasm` Worker on the kant account.
- Use a separate name and subdomain (e.g., `kant-zk-test`) so the test
  deployment never collides with the production relay.
- Version every deploy so `/health` can name the build.
- Verify each stage with `curl` before moving to the next.

## Discoveries

- Existing production relay: `server/worker.js` + `server/wrangler.toml`
  (name `kant-zk-relay-wasm`, account `0ceffbadd0a04623896f5317a1e40d94`).
- Deploy script: `deploy-cloudflare-worker.sh` already handles sops secrets,
  wrangler login, and twin-drift verification.
- The production Worker already imports `./store.js` (a local ESM module), so
  Cloudflare Workers support multi-file Workers and can import from the same
  directory. This means thunks, scheduler, and snapshot modules can be added
  without changing the deployment model.
- Free plan limits (per spec §12): ~100k Worker requests, 100k DO requests,
  10ms CPU/invocation/day. A `/health`-only Worker uses essentially none of
  that budget.

## Accomplished

- [x] Thunk server implementation (`server/thunk.mjs`, `thunk-store.mjs`,
      `schedule.mjs`, `scheduler.mjs`, `server.mjs`, `snapshot.mjs`,
      `example-compactor.mjs`)
- [x] DO scheduler modes specification (`tasks/do-scheduler-modes/SYSTEM.md`)
- [x] Federated P2P relay specification (`tasks/federated-p2p-relay/`)

## Not Done / In Progress

- [ ] Create minimal test Worker: `server/test-worker.js`
- [ ] Create minimal test config: `server/wrangler-test.toml`
- [ ] Add `test-deploy` command to `deploy-cloudflare-worker.sh`
- [ ] Deploy the minimal Worker and verify `/health` responds
- [ ] Add first feature: thunk store + one scheduled thunk
- [ ] Add second feature: DO-based state persistence
- [ ] Add third feature: scheduler loop
- [ ] Verify the test Worker coexists with the production relay
- [ ] Promote test Worker to production when ready

## Relevant Files

| File | Status | Notes |
|------|--------|-------|
| `server/worker.js` | production | Existing relay Worker (434 lines) |
| `server/wrangler.toml` | production | Config for `kant-zk-relay-wasm` |
| `server/store.js` | production | Shared ring/storage logic |
| `server/thunk.mjs` | new (phase 1) | Thunk core |
| `server/thunk-store.mjs` | new (phase 1) | Persistent store |
| `server/schedule.mjs` | new (phase 2) | Scheduler |
| `server/scheduler.mjs` | new (phase 2) | systemd driver |
| `server/server.mjs` | new (phase 2) | Thunk host |
| `server/snapshot.mjs` | new (phase 3) | Snapshot/restore |
| `deploy-cloudflare-worker.sh` | reference | Existing deploy script |
| `server/test-worker.js` | todo | Minimal `/health` Worker |
| `server/wrangler-test.toml` | todo | Config for test Worker |

## Phases

### Phase 0 — Baseline
Minimal Worker that answers `/health` only. No Durable Objects.

```javascript
export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/health") {
      return Response.json({ ok: true, name: "kant-zk-test", version: "0.0.1" });
    }
    return new Response("not found", { status: 404 });
  },
};
```

Config: `wrangler-test.toml` with `name = "kant-zk-test"`,
`main = "test-worker.js"`.

### Phase 1 — Thunk storage
Add `server/thunk.mjs` + `server/thunk-store.mjs` as imports to the test
Worker. Add `/thunks` and `/thunks/{id}` endpoints.

### Phase 2 — Thunk scheduling
Add `server/schedule.mjs` to the test Worker. Add `/schedule` endpoint.
Verify the scheduler loop runs on each request (tick-based for now).

### Phase 3 — Durable Object state
Add a `Room` Durable Object binding to the test Worker. Add
`/room/{room}` endpoint. Verify DO state persists across requests.

### Phase 4 — Snapshot
Add `server/snapshot.mjs`. Add `/snapshot` and `/restore` endpoints.
Verify a thunk snapshot can be serialized and deserialized.

### Phase 5 — Promote
Once the test Worker is stable, migrate it to the production relay
(`server/worker.js`) by moving the features over in order.

## Next Actions

1. Create `server/test-worker.js` with `/health` only.
2. Create `server/wrangler-test.toml` with `name = "kant-zk-test"`.
3. Add `test-deploy` command to `deploy-cloudflare-worker.sh`.
4. Deploy and verify: `curl https://kant-zk-test.<account>.workers.dev/health`.
5. For each subsequent phase, update the test Worker and redeploy.
6. After phase 5, remove the test Worker and use the production relay.

## Budget Notes

A `/health`-only Worker on the Free plan:
- 1 request per `/health` call
- 0 Durable Object requests
- 0 SQLite writes
- 0 storage

This is negligible against the Free plan limits and lets us iterate freely.
Budget pressure only starts with Phase 3 (DO state) and Phase 4 (snapshot).
