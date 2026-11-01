# Task: federated-relay-spec

- **Name:** federated-relay-spec
- **Priority:** P0
- **Area:** kant-zk, relay, p2p, architecture
- **Status:** Draft — specification received, nothing implemented
- **Created:** 2026-10-03
- **Tags:** kant-zk, relay, p2p, architecture

## What this is

A user-supplied specification, "Federated P2P Relay Specification, Draft v0.1",
describing two independently administered Cloudflare deployments (Network N on
`n.example`, Network M on `m.example`) federating selected namespaces through
signed bilateral grants. Durable Objects are the stateful WSS rendezvous,
signalling, fallback-relay and mailbox layer; direct peer-to-peer is preferred
for application data.

The full text lives at `SPEC.md` in this directory. It is 19 sections; the
normative summary is §19.

## This supersedes the no-Durable-Object decision

Recorded plainly because it reverses a decision taken the same day.

Earlier on 2026-10-03 the operator said "we dont want to use durable objects",
then "remove all DO", then "stop them all". Three namespaces were withdrawn
(`kant-relay-v1`, and `kant-zk-relay-wasm` in both accounts) and rooms became
per-isolate memory. That trade was recorded as deliberate and it is now
superseded: §19 makes Durable Objects the stateful layer.

**Why the earlier removal was the wrong cure for the right symptom.** PB-19 was
duration exhaustion — the free tier bills storage *duration*, and a 10s poll
loop with a 10s long poll held four rooms open ~100% of the time. §13 requires
the WebSocket Hibernation API, and per Cloudflare's own pricing docs, "Durable
Objects that are idle and eligible for hibernation are not billed for duration,
even before the runtime has hibernated them." Hibernation plus pacing is the fix;
removing the DO was not, and it cost cross-PoP correctness in exchange.

## Correction: the no-DO path may be viable after all

The arithmetic that says a Durable Object costs `86,400 x 0.128` =
**11,059 GB-s/day per always-on room (85% of the free tier)** was not done when
the reversal was proposed. It is done now, in
`2026-10-03-non-do-relay-research` (PB-33), together with the finding that a
plain Worker is billed **no duration at all** and **zero requests per WebSocket
message**.

Conclusion: the operator's scepticism is correct. With the always-on firewalled
systemd nodes as the single point of coordination, a DO-free relay is cheaper by
an order of magnitude and the DO becomes optional edge infrastructure. §19's
"Durable Objects are the stateful layer" should be restated as "a Durable Object
is an *optional* edge component; the stateful layer is the node fleet."

This supersedes the recommendation below; the reversal it reverses was only
ever forced by the absence of an always-on server.

## Prior work this reuses rather than reinvents

| Spec section | Existing | Where |
|---|---|---|
| §8 canonical codec | DAG-CBOR-adjacent CIDv1, `rawCidOf`, `cidOf` | `web/kant-ipfs.mjs:83,144` |
| §8.4 CONNECT_REQUEST | `parseSignal`, `mesh.onSignal`, `mesh.broadcast`, direct channels | `web/kant-net.mjs:482,721,743,768` |
| §8 envelope encode | `envelopeDecode` / `envelopeEncode` | `web/kantzk.mjs:432` |
| §6.4 bounded queues | room `MAX_LINES`/`MAX_LINE`, pass budget | `server/worker.js:30-31` |
| §5 peer identity | peer ids, witnessed lines, membership by room secret | `web/kant-net.mjs`, `web/kantzk.mjs` |
| Phase 2 direct paths | 369-line libp2p client + Helia vendoring, **unmerged** | `wip/deploy-checkout-20261003` |

Prior task rows that bear on this: PB-17 (relay discovery), PB-18 (dead invite
relay), PB-19 (DO quota), PB-21 (dev worker), PB-25 (Cloudflare token scope).
Prior tasks: `2026-10-02-pastebin-p2p-relay-discovery`,
`2026-10-02-pastebin-invite-dead-relay`, `kant-relay-sqlite-location`.

## Known gaps in the spec itself

1. **§12.1 omits DO duration.** The free tier bills 13,000 GB-s/day of
   duration — the limit PB-19 actually exhausted. Every other row in that table
   matches current docs. Add it, and alert on it in §16.
2. **§13 is currently satisfied in name only.** The only `acceptWebSocket` in the
   repo is wrong: `server/lean-relay.mjs:127` calls it on a WebSocket rather than
   on the Durable Object context. See `2026-10-03-websocket-hibernation-bug/`.
3. **§18 leaves the codec open.** DAG-CBOR is already partly implemented and is
   the only choice that lets client and server share code.

## Published

Issue **#8** on `meta-introspector/kant-zk-pastebin` — "Federated P2P Relay Spec
v0.1 — Phase 1 plan (reverses the no-DO decision; 2 decisions needed)".
https://github.com/meta-introspector/kant-zk-pastebin/issues/8

## Related tasks

- `2026-10-03-federated-relay-phase1` — the Phase 1 slice and its plan
- `2026-10-03-websocket-hibernation-bug` — blocking, small
- `2026-10-03-do-duration-budget` — add duration to the budget model
- `2026-10-03-libp2p-prior-work-triage` — decide what happens to 369 unmerged lines

## Skill

`~/dotagents/skills/kant-federated-relay-planning/` — planning/review
reference: prior-art table, budget arithmetic, the hibernation call site, the
Cloudflare DO deployment traps (new_sqlite_classes, deleted_classes mandatory,
tags drive the class list, migration tags immutable), and the non-vacuity rule
learned from three green-but-wrong suites this session.

## Open questions for the operator

- Does this replace the memory-only relay entirely, or does the no-DO relay stay
  for chat while the federated network gets its own worker? (Asked, unanswered.)
- Two real deployments, or one plus a staging twin?
