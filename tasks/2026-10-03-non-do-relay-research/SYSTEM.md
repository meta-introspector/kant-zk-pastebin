# Task: non-do-relay-research

- **Name:** non-do-relay-research
- **Priority:** P0
- **Area:** kant-zk, relay, cloudflare, cost, architecture
- **Status:** open — verdict below, verification outstanding
- **Created:** 2026-10-03
- **Operator framing:** *"we are forced to reverse non-do unless you have a way
  to make it happen. but i am sceptical. we can always explore non-do as a
  research task in penny pinching."*
- **Related:** PB-28 (spec), PB-29 (hibernation), PB-30 (DO duration budget),
- **Tags:** kant-zk, relay, cloudflare, cost, architecture
  PB-31 (phase 1), PB-33 (this task)

## Verdict, up front

**There is a way, and with the always-on firewalled systemd nodes it is
strictly cheaper than Durable Objects — not marginally cheaper, cheaper by
an order of magnitude, because Cloudflare does not bill the nodes at all.**

The operator's scepticism is well-founded and the arithmetic below is why. I
under-sold the no-DO case when I recommended the reversal; the numbers were
already in hand and I did not do them. Correcting that.

The node fleet is the load-bearing input here, not a detail. Without an
always-on server, Durable Objects are the *only* single point of coordination
Cloudflare offers, and the reversal becomes genuinely forced. With them, the
DO is optional infrastructure and the cost argument for it largely
disappears.

## The arithmetic (verified against live Cloudflare pricing, 2026-10-03)

### Durable Objects — Workers Free tier

| | |
|---|---|
| Requests | 100,000 / day |
| **Duration** | **13,000 GB-s / day** |
| Rows read | 5 million / day |
| Rows written | 100,000 / day |
| Stored | 5 GB |

Duration is billed for the **allocated 128 MB regardless of actual usage**, so
one DO held open continuously costs:

```
86,400 s × 0.128 GB = 11,059 GB-s/day
```

**One always-on room consumes 85% of the entire free tier.** Four rooms held
open = 44,236 GB-s = **3.4× over budget**. This is precisely the PB-19 failure
and precisely why it recurred.

At the PB-19-fixed pacing (60s period, 20s long poll, 33% duty):

```
0.333 × 11,059 = 3,686 GB-s/day per room
4 rooms = 14,746 GB-s/day  → still over budget
```

So even the *fixed* configuration was over budget at four rooms. Client-side
pacing bought headroom; it did not buy safety. Hibernation is what makes it
free — but only while a room is idle.

### Plain Worker WebSockets — Workers Free tier

From Cloudflare's pricing footnotes, read directly:

- *"**No charge for duration**"* for Workers (the DO line is the only duration
  charge in the platform).
- *"WebSocket connections made to a Worker are charged as a request,
  representing the initial Upgrade connection made to establish the WebSocket.
  **WebSocket messages routed through a Worker do not count as requests.**"*
- *"There is no hard limit on duration for HTTP-triggered Workers. As long as
  the client remains connected, the Worker can continue processing."*

So a Worker's WebSocket relay costs **one request per connection and nothing
per message, and nothing per hour held open.**

Against 100,000 requests/day, one reconnect per client per 5 minutes
(12/day) = **~8,300 clients/day within the free tier.** Compare with the DO
ceiling above: one room.

This is not a marginal difference. The DO's request quota looks comparable
(100k/day) but it is also carrying a 13,000 GB-s duration charge that a
Worker does not have at all.

### The one thing a plain Worker genuinely cannot do

Stated plainly, because it is the real constraint and it is not a cost
constraint:

> *"If your application needs to coordinate among multiple WebSocket
> connections, such as a chat room or game match, you will need clients to send
> messages to a single-point-of-coordination. Durable Objects provide a
> single-point-of-coordination for Cloudflare Workers."*

There is no way around this inside the Worker. A plain Worker is one isolate
with one memory; two sockets into the same Worker are not guaranteed the same
isolate and cannot see each other's state. Room fan-out, mailboxes and
signalling all need one place to stand.

**The nodes are that place.** They are already deployed, already systemd-managed,
and not billed by Cloudflare in any respect. `kant-zk-relay.service`,
`kant-p2p-relay.service` and `kant-zk-forward.service` ("self-maintaining room
bridges to relay twins") are already doing exactly this shape of job.

So the architecture is not "Worker instead of DO". It is **node instead of
DO**, with the Worker doing only what Workers are genuinely good at.

## Proposed target architecture

```
        client (browser / CLI / mobile)
                  │
                  │  wss://
        ┌─────────▼──────────┐
        │  CF Worker         │  no DO
        │  · static assets   │  1 req per connection
        │  · IPFS blobs      │  0 req per message
        │  · grant verify    │  0 duration charge
        │  · invite resolve  │
        └─────────┬──────────┘
                  │  proxied to node (state-free hop)
        ┌─────────▼──────────┐
        │  always-on node    │  systemd, firewalled
        │  · rooms           │  NOT billed by Cloudflare
        │  · mailboxes       │  single point of coordination
        │  · signalling      │  unlimited duration
        │  · federation      │
        └────────────────────┘
```

The Worker is a **state-free front door** — which is precisely the role the
Workers runtime is designed for, and precisely the role that does not need a
DO. The node holds what needs holding.

`server/forward.mjs` + `server/backoff.mjs` (PB-19) already implement
relay-to-relay federation with backoff. That is the DO-free half of the
federated spec, already running.

## Concrete hybrid routing policy

The split is not "DO fallback" in the abstract — it needs a rule the client can
evaluate, and the rule falls out of the billing facts rather than taste.

**The cost driver is held duration, not traffic.** A DO costs 11,059 GB-s/day
per always-on instance. Whether a DO path is viable is therefore a question
about *how long it holds a connection*, not how much it carries. So the
routing rule is:

> **A DO may hold a connection only while bytes are actually moving on it.**
> It must never be a rendezvous that merely waits.

That is a sharp and testable line, and it splits the three candidate uses of a
DO very differently:

| Use | DO held duration | Verdict |
|---|---|---|
| **Signalling / rendezvous** — holds a socket open waiting for a peer to appear | 100% of the wait | **Never.** This is the PB-19 shape. 11,059 GB-s/day per room to learn that nobody called. |
| **Idle mailbox delivery** — socket open, no data | 100% of idle | **Never.** Same failure, smaller. |
| **Active fallback relay** — socket open *and* carrying a live direct-channel that failed | only while relaying | **Yes.** Bounded by the direct-channel attempt window, and idle time collapses to zero once hibernation is correct. |

So the DO's only legitimate role is **a fallback data path for peers whose
direct channel failed** — and even then it should hold for a bounded attempt
window (e.g. 60s), not for the life of the room. A peer that cannot get a
direct channel within 60s goes back to polling, which costs one request per
poll and no duration.

**Routing rule for the client:**

1. Announce on the node. Always. Zero duration, zero message cost.
2. Attempt direct P2P (§8.4 CONNECT_REQUEST over the existing
   `mesh.onSignal` / direct-channel path). This is the preferred path in the
   spec and it is the one that costs the least of anything.
3. If the direct attempt fails, take a **bounded** DO fallback relay for up to
   60s of actual traffic, then fall back to node polling.
4. Never hold a DO socket open while idle.

**Budget consequence:** a room is a node room, so it costs nothing. The DO
population is only the transient set of peers currently mid-relay-fallback. At
60s worst-case hold, even 50 simultaneous fallbacks is
`50 × 60s × 0.128 GB` = **384 GB-s/day** — 3% of the 13,000 tier. Compare with
four DO-held rooms at 44,236 GB-s. The mix is not a marginal saving here; it is
the difference between 3% and 340% of budget.

**This makes PB-29 important again.** With a DO in the mix, the hibernation bug
stops being merely a latent bug: `accept()` bills the entire connection
lifetime, and step 3's bounded window is only bounded *if hibernation works*.
Fix it before any DO fallback path carries traffic. (De-prioritising it is
correct for a node-only design and wrong for the hybrid.)

## Open verification items — read before trusting the verdict

Ordered by how much they could change the conclusion.

1. **Do the nodes have public ingress? — CORRECTED 2026-10-03 (PB-39): auth comes
   first, and the "not installed" reason is now stale.** `cloudflared` 2026.9.3 IS
   installed (`~/.local/bin/cloudflared`); no tunnel was created because
   `thunk-relay` has **no authentication of any kind** — every mutating route is open
   to anyone who reaches the port, two of them `DELETE`. The hardcoded
   `127.0.0.1` bind at `thunk-relay.mjs:281` was the entire security model. So
   "install the binary and configure a tunnel" is the wrong next step; it would publish
   an unauthenticated, world-writable, erasable store. Gate the relay first
   (fail-closed bearer, sops-sourced, timing-safe), then tunnel.

   Original finding, still valid as history: the nodes are described as firewalled and
   `cloudflared` was not installed on this host,
   with no `/etc/cloudflared` or `~/.cloudflared`. Options: Cloudflare Tunnel
   (free, outbound-only, fits a firewalled node), a direct port + TLS, or a
   private WireGuard overlay for node-to-node federation. Until one exists,
   "node as coordination point" is a design, not a deployment.

   **This is now blocking a second thing, and that one is already built.**
   `thunk-relay` is deployed on the node (`127.0.0.1:8971`, systemd, enabled at
   boot) and **parked purely for lack of ingress** — the wasm thunk format is
   finished and pushed (`b1fa68d`, PR #232), but nothing outside this machine can
   reach it. See **PB-37**. Resolving item 1 here unblocks both, so it is worth
   doing before more relay design work rather than after.
2. **Is there an idle timeout on plain-Worker WebSockets on Free/Pro?** A
   secondary source (websocket.org) states a 100-second idle timeout for
   Free/Pro. If real, the Worker cannot hold a rendezvous without keepalives —
   which is cheap and message-free under the footnote above, so likely fine,
   but it must be measured, not assumed. Note this cuts *against* the DO
   design too, since a hibernating DO has the same exposure.
3. **Does the repo actually have a node-side WebSocket server?** Grep says
   **no.** `server/worker.js` is the only file mentioning WebSocket upgrade,
   and it is the Cloudflare Worker, not a node daemon. `package.json` has no
   `ws` dependency; `Cargo.toml` has no `ws`/`axum`/`tungstenite`. Building the
   node-side WSS server is real work and is the main cost of this path.
   **Caveat:** this grep was run on `/mnt/data1/kant/pastebin-ipfsproxy`, and
   PR #9 adds Rust transport modules that may provide this. Re-check against
   `feature/big-merge` before treating it as confirmed — see
   `2026-10-03-pr9-relay-plan-crosscheck`.
4. **Worker CPU ceiling.** 10ms/invocation on Free. Fine for proxying frames,
   must not be where grant verification or CID computation happens if we ever
   exceed it. Grant verification is Ed25519 — measure it.
5. **Egress.** Workers have no data-transfer charge, but node egress is a real
   household/hosting cost. Probably trivial at this scale; worth one number.

## What this does *not* change

- **PB-29 (hibernation bug) stays open** and stays worth fixing — wrong
  receiver, wrong argument, and it is what makes DO WebSockets expensive. It is
  needed *before* any DO fallback path carries traffic.
- **PB-30 (duration budget) stays open.** The arithmetic here is the fix; it
  should be written into §12.1 which still omits the 13,000 GB-s row.
- **PB-32 (libp2p triage) — corrected, and now favourable.** The libp2p work is
  substantially complete on PR #9, not stranded. Phase 2 de-risks.
- **PB-28/PB-31 (the spec) needs restating.** §19's "Durable Objects are the
  stateful layer" should become "a Durable Object is an *optional* edge
  component; the stateful layer is the always-on node fleet."

## Recommendation

Restructure Phase 1 to **node-first, DO-optional**, and run this research task
in parallel as the cost/feasibility check. Concretely:

1. Resolve verification item 1 (ingress). Everything else is moot without it.
2. Resolve item 3 — re-check against PR #9's Rust transport modules first.
3. Fix PB-29 regardless; it is small and it is correct.
4. Update §12.1 with the duration row and the 11,059 GB-s/day arithmetic.
5. Cross-check against PR #9's `tasks/federated-p2p-relay/PLAN.md`, which is a
   prior independent plan for the same spec.

If ingress turns out to be hard, the DO path remains available as the fallback
and the hybrid becomes DO-primary — which is exactly the shape the operator
proposed, so neither outcome wastes work.