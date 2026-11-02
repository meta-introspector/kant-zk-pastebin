# Task: websocket-hibernation-bug

- **Name:** websocket-hibernation-bug
- **Priority:** P0
- **Area:** kant-zk, relay, cloudflare
- **Status:** open — confirmed, unfixed
- **Created:** 2026-10-03
- **Blocks:** `2026-10-03-federated-relay-phase1`
- **Tags:** kant-zk, relay, cloudflare

## The bug

`server/lean-relay.mjs:127` — the only `acceptWebSocket` in the repository:

```js
const envCtx = { env, server };              // fabricated
envCtx.server.acceptWebSocket(server, envCtx) // called on a WebSocket
```

The Hibernation API entry point is `ctx.acceptWebSocket(ws, tags)` where `ctx`
is the Durable Object's storage context, and `ws` is the accepted socket. The
code calls it as a method *of* the WebSocket, passing a plain object literal as
the `ctx` receiver and the WebSocket as the first argument. Both the receiver
and the argument are wrong. It is not a stylistic mistake about which object
owns the method; nothing about that call can succeed against a real socket.

Consequence: sockets are never hibernated, so every open connection is billed
for duration for its entire lifetime. Cloudflare's own pricing page states
that "Durable Objects that are idle and eligible for hibernation are not billed
for duration, even before the runtime has hibernated them" — the eligibility,
not the eviction, is what saves the budget. A call that never registers the
socket as hibernate-eligible forfeits that exemption permanently.

## Second, distinct site: `server/worker.js:185` (found 2026-10-03)

PR #9's plan lists this as gap G1 and it is **a different defect, not the same
one**:

```js
this.sockets = new Set(); // { ws, cursor }
```

The Hibernation API is **not used at all** here — sockets live in instance
memory. So there are two bugs:

| | `lean-relay.mjs:127` | `worker.js:185` |
|---|---|---|
| Defect | API called wrongly — never succeeds | API not used at all |
| Effect | no sockets ever | sockets held in memory, lost on eviction |
| Failure mode | dead feature, obvious | **silent, and reports healthy** — the log is persisted, so a hibernated room reloads correctly having lost every peer |

The `worker.js` version is strictly worse: it fails the way PB-19's `/health`
stayed 200 while every room read 500. **PB-29 must cover both sites.** Verified
on `feature/big-merge` 2026-10-03 (`worker.js:185`, `:248`, `:252`, `:338`,
`:350` all touch the Set).

## Why it matters now

This is the difference between the federated relay spec (§13, which mandates
the Hibernation API) being a real design and a nominal one. PB-19 exhausted
13,000 GB-s/day of billed duration on the free tier. The whole cure that the
spec now relies on — pacing plus hibernation — is unimplemented at the one call
site where it must be implemented.

It is also, today, dead code. `lean-relay.mjs` is the file behind
`kant-zk-relay-wasm` in both accounts, and no verified traffic reaches this
line: the protocol mismatch fixed earlier in the same session meant the lab
page's posts never arrived. So this has not caused an outage. It will cause one
the first time the relay accepts real sockets.

## The fix

1. Delete the fabricated `envCtx` object.
2. Take the storage context from the Durable Object instance and call
   `ctx.acceptWebSocket(ws, tags)` on it, where `tags` encode the room id so
   `webSocketMessage`/`webSocketClose` can route without a map lookup.
3. Adopt the Hibernation API symmetric side too: `ws.accept()` →
   `ctx.getWebSockets(tag)` on boot for reconnect, `serializeAttachment` /
   `deserializeAttachment` for per-socket state, and
   `setWebSocketAutoResponse` so keepalives do not wake the object.
4. Add a test that fails against the current line. A test that asserts
   `acceptWebSocket` was *called* is vacuous — the current code does call
   something by that name. The test has to run against a DO context
   substitute and assert the socket was registered on **that** object.

## Verification that would prove it

- Unit: a fake `ctx` records `acceptWebSocket(ws, tags)`; assert the receiver
  is the context, not the socket, and that tags carry the room id.
- End-to-end against a real deployed DO: open a socket, let it idle past the
  eviction window, confirm the object is evicted and the client reconnects
  without a message loss, and confirm the free-tier duration counter does not
  advance while idle.
- The regression test must be one that fails on `9fd82eb1`, the current
  `lean-relay.mjs` at `fix/lean-relay-handlewasmload`.

## Notes

Sibling of `2026-10-03-do-duration-budget`: that task changes the model, this
one removes the leak. Both are prerequisites for believing §13.

The room-loss incident during the DO removal on 2026-10-03 was a separate
cause (a `deleted_classes` migration wiped stored rooms) and is not related to
this bug; do not let the two investigations merge.
