---
name: federated-p2p-relay
priority: HIGH
depends_on: []
---

# federated-p2p-relay

**Status:** draft · **Date:** 2026-10-03 · **Revised:** 2026-10-03

## Purpose

Record the **Federated P2P Relay Specification v0.1** as a task for the kant-pastebin
project: replace the single-network Cloudflare `kant-zk-relay` (Worker + per-room
`Room` Durable Object) with a federated peer-to-peer relay network spanning two
independently administered Cloudflare deployments (Network N, Network M), using
Durable Objects as WebSocket rendezvous, signaling, fallback-relay, and mailbox
layer.

## Specification summary (draft v0.1)

- **Networks**: N on `n.example`, M on `m.example`. Each owns its own
  Cloudflare account, Worker, Durable Objects, authority key, and Free-plan
  allowance. Not an account-pooling or quota-circumvention mechanism.
- **Relay model**: Durable Objects are the WSS server (WebSocket Hibernation API
  mandatory). Peers dial outward via WSS. Direct libp2p QUIC/TCP/WebRTC is
  preferred for application data; DO relay is control-plane + fallback.
- **Object topology**:
  - `gateway:<network>:<peer>:<slot>` — accepts authenticated inbound WSS,
    tracks session epoch + cursors in SQLite.
  - `mailbox:<network>:<recipient>` — per-recipient ordered mailbox, TTL,
    depth/bytes limits.
  - `topic:<network>:<topic>:<partition>` — ordered events, bounded fan-out.
  - `federation:<local>:<remote>:<namespace-map>` — validate bilateral grants,
    bounded outbox/seen-set, import/export over HTTPS, anti-entropy.
- **Frame protocol**: four frame kinds — HELLO, ENVELOPE, ACK, CONNECT_REQUEST.
  Envelopes carry signed payloads by CID or bounded inline bytes.

  > **Correction to v0.1.** The spec's §8 says frames MUST be DAG-CBOR or
  > another canonical binary format, while its §18 lists the canonical codec as
  > an open decision, and its §8.1–8.3 examples are JSON objects. All three
  > cannot hold: those examples are the opposite of a canonical binary
  > encoding. Treat the JSON blocks as **illustrative field lists, not
  > normative wire format**, and the codec as genuinely undecided. This is not
  > academic — see "Blocking decisions" below.
- **Federation**: explicit, signed, expiring bilateral namespace grants (bidir
  required). Bridge transport: N FederationDO -> M Worker HTTPS. Import checks:
  grant validity, both authority signatures, origin signature, TTL, hop_limit,
  path loop, seen-set, size/rate limits.
- **Budget**: Free plan — ~100k Worker requests, 100k DO requests, 10ms CPU
  per invocation/day/account. Prototype defaults: 16 KiB inline payload, 64 KiB
  frame, mailbox depth 100, 2 MiB / 24h TTL, 1 msg/10s sustained per peer.
- **Phases**: (1) single-network GatewayDO+MailboxDO; (2) direct connectivity
  (libp2p identity, candidate signaling, QUIC/WebRTC upgrade); (3) Network M;
  (4) narrow federation; (5) production decision.
- **Normative**: DOs are the stateful WSS rendezvous/fallback layer; direct P2P
  preferred; every relay/federation action authenticated, idempotent, bounded,
  resumable; accounts never used to bypass platform limits.

## Current state of the project

Verified against the tree on 2026-10-03. Several claims in the previous revision
of this file were wrong and are corrected below.

- `server/worker.js`: Cloudflare Worker (`kant-zk-relay-wasm`) with a per-room
  `Room` Durable Object bound as `ROOMS` in `server/wrangler.toml`. Endpoints
  are `POST /room/{room}` and `GET /room/{room}?cursor=N[&wait=S]`, plus a
  WebSocket upgrade. `server/relay.mjs` is the Node twin with the same shape.
- **The relay does not carry JSON frames.** It carries **Kant text lines**, each
  self-certifying via its own witness, tagged `kzchat`, `kzfile`, `kzprof`,
  `kzinvite`, or `kzat`. JSON appears only as the HTTP response envelope
  (`{ok, cursor, lines}`). This matters for the spec: a line *is* its own
  integrity proof, which §8.2's separate `signature` field does not model.
- **libp2p is no longer absent.** `web/kant-libp2p.mjs` carries file chunks over
  gossipsub (45 tests); `src/libp2p_frames.rs` + `src/libp2p_transport.rs` are
  the Rust counterpart (42 tests), byte-identical on the wire to the JS and
  verified by `scripts/frames-crosscheck.sh`. Commits `52349366`, `b23c518f`,
  `f360e985`. Chat deliberately stays on the HTTP relay.
- Cursor-based resume exists (`?cursor=N`, `wait`), and `kzpass` carries a
  per-peer spend ledger persisted in DO storage (`worker.js:207-214`).
- **There is already a bounded, persisted, cursor-trimmed ring** — `MAX_LINES =
  4096` (`worker.js:31`), trimmed with a `base` offset so late readers get
  `truncated` rather than a silently incomplete log (`worker.js:241-243`). So
  part of §9.3 already exists. What is missing is the part that makes it a
  *mailbox*: per-recipient queues rather than one room-wide ring, a **byte**
  bound (only a line count, so one 256 KiB line costs 4096x a short one), a
  TTL, and acknowledgement. A depth-bounded ring with no ACK cannot distinguish
  "delivered" from "queued", which is the whole point of the §6.2 object.
- **Two DO implementations exist and they differ.** `server/worker.js` *does*
  persist its log (`state.storage.put("log", ...)`). The lean-worker rescue DO
  (`minimal/DeskServer-rescue/worker/worker.js`) explicitly does not — it
  reports `durable: false` and has no storage calls at all. Claims about "the
  DO" must say which one.
- **No WebSocket Hibernation API.** `server/worker.js:185` keeps sockets in an
  in-memory `Set`. This is the sharpest concrete gap against §13: the log
  survives an isolate restart but the socket set does not, so a hibernating
  object loses every connection while still appearing healthy.
- **No idempotency.** The only `Set`s are sockets and waiters. The same line can
  be posted twice and will be stored twice, against §9.1.
- **No network identity or revocable membership.** A room is named by
  `witness(secret)` and anyone holding the secret is a member for good. `kzpass`
  adds a rate limit and a proof-of-work check, but has no issuer, no expiry, and
  no revocation. §5 and §10.1 rest entirely on credentials that do not exist.

## Where the spec and the code disagree

Three places where the spec describes something we deliberately built
differently. Each needs a decision, not a silent divergence.

1. **Durable mailbox (§6.2, §13) vs the relay as it stands.** We moved the room
   onto the peer (`server/room-store.mjs`, commit `4661035d`) on the reasoning
   that the relay is a mailbox, not an archive. The spec agrees with that
   direction — the mailbox holds *unacknowledged, bounded* state — but makes
   durability load-bearing, because that is what makes ACK/resume work.
   `server/worker.js` already persists a trimmed ring; the lean-worker rescue DO
   does not persist at all. So the gap is narrower than "add persistence": it is
   per-recipient queues, a byte bound, a TTL, and ACKs, so that a trimmed entry
   can be distinguished from a delivered one.
2. **16 KiB inline payload (§12.3) vs `CHUNK_SIZE = 262144`.** `web/kant-file.mjs:31`
   chunks at 256 KiB and `server/relay.mjs:59` defaults `max-line` to the same.
   The gossipsub path already complies (`FRAME_BYTES` is 16 KiB); the **relay**
   path does not. On the Free plan one line is a large slice of the per-object
   storage ceiling, and §12.4 counts up to eight request/write events per
   accepted message.
3. **Dedup key `(origin_network, from, message_id)` (§9.1) vs content digest.**
   `server/room-store.mjs:56` keys on `(room, digest)` where the digest is
   sha256 of the printed line. Ours is arguably stronger — the digest covers
   content that carries its own witness, so a forged `message_id` buys nothing
   and suppression needs no trusted issuer. But it is not the spec's key, so a
   spec-conformant peer cannot deduplicate against ours.

## Why / relationship to other work

This spec covers the same domain as `helia-integration` (in-browser IPFS
discovery/relaying) but at a different abstraction level: a production-grade
federated transport/rendezvous layer rather than ipfs content-addressing.
`helia-integration` can run on top of this layer once the federation/relaying
infrastructure exists.

The libp2p work already landed is the one part of this spec that is no longer
hypothetical: §3's non-goal against using a DO as a libp2p circuit-relay daemon,
and §11's preference for direct paths over relay frames, are exactly the split
`src/libp2p_transport.rs` implements.

## Non-goals (per spec)

- Keeping a Worker isolate permanently alive.
- Treating a Durable Object as a raw TCP/QUIC circuit-relay daemon.
- Automatically sharing all group data across overlapping users.
- Circumventing Cloudflare limits.
- Global total ordering.
- Carrying large blobs through WebSocket relay frames.

## Blocking decisions

These must be settled before writing frame code, because the encoding has to
match byte-for-byte across implementations and we have already been bitten by
guessing it once (the JS adapter was written against a remembered gossipsub API
and four things were wrong, none of which any test caught).

- **Canonical codec.** DAG-CBOR vs another canonical binary. Note that neither
  is what we ship: the relay carries text lines and the chunk transport carries
  a 41-byte binary frame. Adopting DAG-CBOR means a real migration.
- **Credential format.** Capability tokens vs signed certificates vs VCs. Ties
  directly to the absent §5 network identity.
- **Key revocation distribution and latency target.**
- **Direct browser transport.** WebRTC vs WebTransport vs WSS-only. WebTransport
  in js-libp2p only *dials* — it cannot listen — so a browser peer needs a
  rendezvous regardless of which is chosen.
- **Federation bridge plaintext-metadata vs opaque encrypted envelopes.**
- **Log structure.** Append-only per-mailbox, per-topic Merkle logs, or shared
  IPLD DAG with signed heads.
- **Native public libp2p circuit relays** for raw QUIC/TCP relay semantics.

## Phases from the spec

1. **Phase 1 — Single-network prototype**: GatewayDO + MailboxDO, authenticated
   WSS from a Rust client/home PC, signed envelopes, idempotency, TTL, ACK/resume.
2. **Phase 2 — Direct connectivity**: libp2p identity, peer presence, candidate
   signaling, direct QUIC/WebRTC/hole-punch upgrade, measure relay fallback.
3. **Phase 3 — Second network**: deploy M under its own domain/keys/account;
   verify N and M isolated by default.
4. **Phase 4 — Narrow federation**: one bilateral grant, low-volume shared
   namespace; FederationDO on both sides; duplicate delivery, expiry, revoked
   grants, loops, outage tests; anti-entropy from signed log/DAG roots.
5. **Phase 5 — Production decision**: migrate to Workers Paid or add independent
   VPS libp2p relays when targets exceed the Free plan.

## Next Actions

1. Settle the canonical codec in an implementation decision record before any
   frame code is written. Everything in Phase 1 depends on it.
2. **Add the WebSocket Hibernation API to `server/worker.js`.** Cheapest real
   correctness win in this list: today the log survives hibernation and the
   sockets do not, so the DO reports healthy having dropped every peer.
3. **Add idempotency to the relay**, keyed on the existing line digest rather
   than the spec's `message_id`, so the two implementations agree on what a
   duplicate is. Resolves disagreement 3 above.
4. Reduce `CHUNK_SIZE` and `relay.mjs` `max-line` to the spec's 16 KiB, and
   measure what that does to existing file transfers before committing.
5. Design network identity and signed, expiring, revocable membership (§5). This
   is the largest genuine gap and the prerequisite for federation.
6. Confirm the Free-plan planning numbers in §12 against current Cloudflare
   billing docs — they are planning guidance, and the spec says so.
7. Decide whether this replaces `worker.js`/`Room` or deploys alongside it. Note
   the two existing DO implementations have diverged, so "replace" is now a
   three-way question.