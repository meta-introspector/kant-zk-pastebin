# Federated P2P Relay Specification — Draft v0.1

> Verbatim as supplied by the operator on 2026-10-03. Kept unmodified so task
> notes and the issue can cite sections without paraphrasing drifting from it.
> Section numbers (§) are used throughout the sibling task files.

## 1. Status and purpose

Status: Draft v0.1

This specification defines a small federated peer-to-peer network composed of two independently administered Cloudflare deployments:

- Network N on domain `n.example`
- Network M on domain `m.example`

Each deployment uses a Cloudflare Worker and SQLite-backed Durable Objects on the Workers Free plan. The deployments federate only selected namespaces through explicit, signed policy. They are separate administrative domains, not an account-pooling or quota-circumvention mechanism.

The system uses Cloudflare Durable Objects as a WebSocket rendezvous, signaling, fallback-relay, and mailbox layer. It prefers direct peer-to-peer transport for application data whenever a direct path can be established.

## 2. Goals

- Let native and browser-compatible peers discover each other and exchange authenticated messages.
- Permit peers behind NAT or firewalls to maintain outbound WSS connections to a reachable endpoint.
- Prefer direct libp2p QUIC/TCP/WebRTC connectivity after discovery/signaling.
- Use a Durable Object relay only when direct communication is unavailable or as a short-lived fallback.
- Support offline store-and-forward delivery with bounded retention.
- Federate selected namespaces between Network N and Network M.
- Preserve each network's independent membership, policy, keys, quotas, and operations.
- Fit a conservative private prototype within Free-plan limits.

## 3. Non-goals

- Keeping a Cloudflare Worker isolate permanently alive.
- Treating a Durable Object as a raw TCP/QUIC libp2p circuit-relay daemon.
- Automatically sharing all group data because users overlap between networks.
- Circumventing Cloudflare limits by creating accounts, identities, or workloads solely to multiply a free quota.
- Providing global total ordering across all topics or networks.
- Carrying large content blobs through WebSocket relay frames.

## 4. Deployment model

```
                         Direct paths preferred
        ┌───────────────────────< QUIC / TCP / WebRTC >───────────────────────┐
        │                                                                      │
        ▼                                                                      ▼
     Peer A                                                                Peer B
        │                                                                      │
        │ WSS fallback/control                                                │ WSS fallback/control
        ▼                                                                      ▼
┌───────────────────────┐      explicit federation       ┌───────────────────────┐
│ Network N: n.example  │ <────────────────────────────> │ Network M: m.example  │
│ Cloudflare account N  │                                │ Cloudflare account M  │
│ Worker + Durable Obj. │                                │ Worker + Durable Obj. │
└───────────────────────┘                                └───────────────────────┘
        │                                                              │
        ├── GatewayDO: incoming WSS peers                              ├── GatewayDO
        ├── MailboxDO: recipient mailbox                               ├── MailboxDO
        ├── TopicDO: topic partition                                   ├── TopicDO
        └── FederationDO: exported/imported namespaces                 └── FederationDO
```

A peer, including a home PC behind NAT, opens an outbound WSS connection to the appropriate gateway endpoint. The Durable Object is the WebSocket server. This direction is mandatory for hibernation-friendly operation:

```
Peer / home PC  ─── dials outward via WSS ───> Worker ───> Durable Object
```

The Durable Object MUST NOT rely on a permanently open outbound socket to a home PC or another Durable Object.

## 5. Network identity

Each network has independent long-lived public-key identities:

| Network | Domain | Network ID | Authority key |
|---|---|---|---|
| N | n.example | `network:N` | `K_N` |
| M | m.example | `network:M` | `K_M` |

A participant has a stable application/libp2p identity `peer_id` derived from a public key. Membership is separate from identity:

- N membership is a signed, expiring credential issued under `K_N`.
- M membership is a signed, expiring credential issued under `K_M`.
- A user who belongs to both groups holds two credentials.

Dual membership alone grants no automatic federation or forwarding authorization.

## 6. Object topology

### 6.1 GatewayDO

Name: `gateway:<network-id>:<peer-id>:<slot>` where `<slot>` is normally `a` or `b`. A peer SHOULD connect to two slots when practical for redundant control/fallback paths.

Responsibilities:

- Accept authenticated inbound WSS from the peer.
- Store only reconnect-safe socket metadata using WebSocket attachments.
- Track session epoch and last acknowledged cursors in SQLite storage.
- Route envelopes to local mailbox/topic/federation objects.
- Deliver locally queued messages to the connected peer.

### 6.2 MailboxDO

Name: `mailbox:<network-id>:<recipient-peer-id>`

Responsibilities:

- Serialize per-recipient mailbox operations.
- Deduplicate messages.
- Maintain an ordered recipient cursor.
- Enforce maximum depth, total bytes, and TTL.
- Deliver messages to a currently connected gateway or retain them for pull/resume.

### 6.3 TopicDO

Name: `topic:<network-id>:<topic-id>:<partition>`

Responsibilities:

- Order events within one topic partition.
- Maintain topic subscribers and bounded fan-out state.
- Deduplicate content by origin message ID or CID.
- Persist subscription and delivery cursor state required after hibernation.

A topic MUST be partitioned before it becomes hot. The network configuration defines the partition function and routing epoch.

### 6.4 FederationDO

Name: `federation:<local-network-id>:<remote-network-id>:<namespace-map-id>`

Responsibilities:

- Validate the bilateral federation grant.
- Maintain a bounded outbox and seen-set for the federation link.
- Export allowed envelopes to the remote federation API.
- Import remote envelopes only after verifying origin signatures, policy, expiry, and loop controls.
- Run anti-entropy reconciliation for durable shared logs when configured.

## 7. Routing and direct connectivity

### 7.1 Route preference

A peer MUST prefer routes in this order:

1. Same-LAN/private-overlay path.
2. Direct public QUIC/TCP path.
3. Hole-punched direct QUIC/TCP/WebRTC path.
4. Native libp2p circuit relay, if an independent public relay exists.
5. Durable Object WSS relay path.
6. Durable mailbox/store-and-forward path.

The relay layer is control-plane and fallback infrastructure, not the mandatory data plane.

### 7.2 Connection upgrade

1. A peer publishes signed presence with candidate addresses and capabilities.
2. Another peer requests a connection through the recipient's GatewayDO or rendezvous endpoint.
3. The control layer forwards candidate information and a signed nonce.
4. The peers attempt a direct connection.
5. If a direct path succeeds, application data SHOULD use it.
6. The WSS relay remains available as a bounded fallback until the direct path is stable.
7. If direct connectivity fails, messages use relay/mailbox semantics.

## 8. Frame protocol

Frames are binary, canonically encoded as DAG-CBOR or another explicitly versioned canonical binary format. The implementation MUST enforce frame-size limits before decoding.

### 8.1 HELLO

```json
{ "v": 1, "kind": "hello", "peer_id": "<peer-id>", "network_id": "network:N",
  "session_epoch": 42, "membership": "<signed credential>",
  "last_inbound_ack": 103, "last_outbound_ack": 96,
  "capabilities": ["wss-relay", "quic", "webrtc"], "signature": "<peer signature>" }
```

### 8.2 ENVELOPE

```json
{ "v": 1, "kind": "envelope", "message_id": "<32-byte random ID or origin sequence ID>",
  "origin_network": "network:N", "from": "<peer-id>",
  "to": { "kind": "peer", "id": "<recipient peer-id>" },
  "sequence": 104, "created_at": 0, "expires_at": 0,
  "payload_cid": "bafy...", "payload": "<optional bounded inline bytes>",
  "signature": "<origin peer signature>" }
```

For topic delivery, `to` is `{ "kind": "topic", "id": "<topic-id>", "partition": 3 }`.

### 8.3 ACK

```json
{ "v": 1, "kind": "ack", "peer_id": "<peer-id>", "direction": "inbound",
  "cursor": 104, "signature": "<peer signature>" }
```

### 8.4 CONNECT_REQUEST

A small signaling frame containing candidate addresses, a nonce, a target peer ID, and an expiry. It MUST NOT be confused with proof that a direct path is reachable.

## 9. Durable delivery rules

### 9.1 Idempotency

Mailbox and topic objects MUST treat `(origin_network, from, message_id)` as a unique delivery key. If a duplicate arrives, the object MUST return the original logical outcome without creating a second delivery record.

### 9.2 Ordering

Ordering is defined per mailbox and per topic partition only. No global ordering is implied between different mailboxes, topics, Durable Objects, Network N, or Network M. Clients MUST tolerate duplicate delivery and resume using cursors.

### 9.3 Bounded queues

Every mailbox and federation outbox MUST define maximum messages, maximum bytes, maximum retention time, behavior on quota exhaustion, and a dead-letter or explicit rejection outcome. A sender MUST receive an explicit failure when a destination queue cannot accept an envelope. Silent unbounded retention is prohibited.

## 10. Federation between N and M

### 10.1 Federation is explicit

N and M federate only through a signed namespace mapping. A mapping is invalid unless both network authorities have signed it for bidirectional exchange.

```json
{ "v": 1, "kind": "federation-grant", "network_a": "network:N", "network_b": "network:M",
  "namespace_a": "g/shared-project", "namespace_b": "g2/shared-project",
  "direction": "bidirectional", "allowed_types": ["message", "presence", "cid-announcement"],
  "max_payload_bytes": 65536, "retention_seconds": 86400, "hop_limit": 3,
  "not_before": 0, "expires_at": 0, "policy_cid": "bafy...",
  "signatures": ["<K_N signature>", "<K_M signature>"] }
```

The safe default is no federation.

### 10.2 Bridge transport

The N-side FederationDO calls M's public federation ingress endpoint over HTTPS using a signed federation envelope. The M-side Worker routes the request to its FederationDO, which verifies it and writes idempotently to the destination topic/mailbox.

```
N Topic/Mailbox DO
        │
        ▼
N FederationDO ── HTTPS signed envelope ──> M Worker ──> M FederationDO
        │                                                        │
        └──── bounded outbox / retry / cursor ───────────────────┘
```

This is a logical federation mesh. It is not a permanent all-to-all WebSocket mesh between Durable Objects.

### 10.3 Federation envelope

```json
{ "v": 1, "kind": "federated-envelope", "message_id": "<origin message ID>",
  "message_cid": "bafy...", "origin_network": "network:N",
  "origin_namespace": "g/shared-project", "destination_network": "network:M",
  "destination_namespace": "g2/shared-project", "origin_author": "<peer-id>",
  "origin_signature": "<signature over original envelope>", "grant_cid": "bafy...",
  "hop_limit": 3, "path": ["network:N"], "expires_at": 0,
  "bridge_signature": "<N federation bridge signature>" }
```

### 10.4 Import checks

The importing network MUST reject an envelope unless all of the following hold:

- The federation grant is known, unexpired, and authorizes this direction.
- Both required network-authority signatures validate.
- The original author signature validates.
- The namespace mapping and allowed type match.
- The envelope has not expired.
- `hop_limit` is greater than zero.
- The destination network is not already in `path`.
- The message key is not in the durable seen-set.
- The payload size and rate limits are satisfied.

### 10.5 Loop prevention

Each federation hop MUST decrement `hop_limit` and append the forwarding network to `path`. The durable seen-set key is `(origin_network, message_id)`. Content-addressed payloads MAY additionally be deduplicated by CID.

## 11. Content-addressed payloads

- Large payloads MUST NOT be carried through ordinary relay frames.
- Store the content as a CAR/IPLD block set or other content-addressed object.
- Announce its CID, size, codec, and optional availability hints in a signed envelope.
- Retrieve bulk blocks through a direct peer path when available.
- Fall back to a bounded HTTPS/object gateway or an explicitly provisioned relay only when policy allows.

This keeps Durable Objects focused on routing, authorization, small control messages, and bounded fallback delivery.

## 12. Free-plan budget

The Free plan is appropriate for a low-volume private prototype, not a high-rate message bus.

### 12.1 Per-account budget

Each independent deployment has its own legitimate account and its own Free-plan allowance. The following table is planning guidance and MUST be checked against current Cloudflare billing documentation before deployment.

| Resource | Conservative planning limit per account/day |
|---|---|
| Worker requests | 100,000 |
| Durable Object requests | 100,000 |
| Worker CPU per invocation | 10 ms |
| SQLite rows read | 5,000,000 |
| SQLite rows written | 100,000 |
| Total SQLite DO storage | 5 GB |
| SQLite storage per object | 1 GB |

On the Free plan, Durable Objects use SQLite-backed storage. Limits reset at 00:00 UTC. Exceeding a hard free allocation can cause operations to fail, so the application MUST impose lower internal limits and expose budget telemetry.

### 12.2 Two-domain combined planning envelope

| Resource | N | M | Combined planning total |
|---|---|---|---|
| Worker requests/day | 100,000 | 100,000 | 200,000 |
| DO requests/day | 100,000 | 100,000 | 200,000 |
| SQLite writes/day | 100,000 | 100,000 | 200,000 |
| SQLite storage | 5 GB | 5 GB | 10 GB |

This combined figure is not a license to split one workload across accounts to evade limits. Federation traffic consumes budget on both sides: an export, import, persistence action, delivery event, and acknowledgement can together cost multiple requests and writes for one user-visible message.

### 12.3 Prototype rate limits

| Control | Initial default |
|---|---|
| Max inline envelope payload | 16 KiB |
| Max accepted relay frame | 64 KiB |
| Max direct-message rate per peer | 1 message / 10 seconds sustained |
| Burst allowance | 5 messages |
| Max mailbox depth | 100 messages |
| Max mailbox retained bytes | 2 MiB |
| Mailbox TTL | 24 hours |
| Max topic fan-out | 20 recipients per envelope |
| Presence publication period | 2–5 minutes unless active signaling requires more |
| Federation retry rate | Exponential backoff with jitter |
| Federation outbox TTL | 24 hours |

At one message every ten seconds, one peer generates 8,640 messages/day before forwarding and storage overhead. A private prototype should start substantially below that rate.

### 12.4 Budget accounting

For each accepted logical message, track at least:

- worker ingress request
- source Durable Object message event
- source storage writes
- federation export/import events, if applicable
- destination Durable Object event
- destination storage writes
- recipient delivery event
- ACK event/write, if used

The system MUST report estimates of request and row-write consumption by network, peer, topic, mailbox, and federation link.

## 13. Durable Object hibernation rules

- All WebSocket-serving objects MUST use the Durable Object WebSocket Hibernation API.
- Correctness-critical state MUST be persisted in SQLite.
- Socket attachment metadata MUST be sufficient to identify the peer/session after wakeup.
- In-memory maps are caches only and MUST be reconstructible.
- No `setInterval` or frequent application ping loop may be used solely to keep an object resident.
- A low-frequency liveness ping MAY be used only when the application needs dead-peer detection.
- A peer MUST reconnect and resume after any socket loss.

## 14. Security requirements

- Authenticate every WSS upgrade before accepting application frames.
- Use TLS/WSS for all public endpoints.
- Verify membership credential, signature, expiry, audience/network ID, and revocation state.
- Bind tickets to peer ID, destination object/role, expiry, and byte/message limits.
- Store private keys outside deployment artifacts and rotate keys with signed transition records.
- Rate-limit by peer identity and network-level abuse policy, not only by IP address.
- Enforce strict binary decoding limits, nesting limits, and canonical serialization.
- Require idempotency keys and TTL on every relayed or federated message.
- Keep federation payloads end-to-end encrypted when bridge operators must not read content.
- Audit grant issuance, revocation, import rejection, queue overflow, and key-rotation events.

## 15. Failure handling

| Failure | Required behavior |
|---|---|
| Worker isolate disappears | Client request/socket is retried or reconnects; DO state is authoritative |
| DO hibernates | Reload SQLite state and socket attachment metadata on next event |
| Peer loses WSS | Peer reconnects with a newer session epoch and ACK cursors |
| Direct P2P path fails | Revert to relay path or mailbox delivery |
| Network N cannot reach M | N retains a bounded federation outbox and retries with backoff until expiry |
| Duplicate federation delivery | M detects seen key and returns idempotent success |
| Federation policy revoked | Reject new imports/exports; retain or purge queued material according to policy |
| Queue full | Return explicit backpressure/rejection; do not silently drop accepted data |
| Account reaches quota | Reject/defer low-priority work and alert operators; do not assume a second account is failover capacity |

## 16. Observability

Each network SHOULD export metrics for:

- Worker and Durable Object requests per day.
- SQLite read/write rows per day.
- Active and hibernating WebSocket count per object type.
- Direct-connection success rate versus relay fallback rate.
- Mailbox depth, bytes, age, expiry, rejection, and ACK lag.
- Federation import/export counts, retries, duplicate suppression, policy rejection, and outbox depth.
- Per-peer and per-topic rate-limit rejections.
- Session reconnects, epoch changes, and direct-path migration failures.

Alert before 70 percent of any daily Free-plan allocation and apply progressive admission controls before the hard limit.

## 17. Implementation phases

**Phase 1: Single-network prototype.** One domain and one Cloudflare account. GatewayDO plus MailboxDO. Authenticated WSS from a Rust client/home PC. Signed envelopes, idempotency, TTL, ACK/resume. Direct-connect candidate exchange only; no federation yet.

**Phase 2: Direct connectivity.** Add libp2p identity integration. Add peer presence and candidate-address signaling. Attempt direct QUIC/WebRTC/hole-punch upgrade. Measure relay fallback percentage.

**Phase 3: Second independent network.** Deploy Network M under its own domain, authority key, operations, and account. Implement the same protocol with a distinct network ID. Verify that N and M remain isolated by default.

**Phase 4: Narrow federation.** Create one bilateral grant for a low-volume shared namespace. Add FederationDO on both sides. Test duplicate delivery, expiry, revoked grants, loops, and one-side outage. Add anti-entropy based on signed log/DAG roots.

**Phase 5: Production decision.** Move to Workers Paid or add independent persistent VPS libp2p relays when observed traffic, message frequency, fan-out, retention, or reliability targets exceed the Free plan.

## 18. Open decisions

- Canonical codec: DAG-CBOR versus another canonical binary protocol.
- Credential format: capability tokens, signed membership certificates, or verifiable credentials.
- Key revocation distribution and maximum revocation-latency target.
- Direct browser transport: WebRTC, WebTransport, or WSS-only fallback.
- Whether federation bridges see plaintext metadata only or opaque encrypted envelopes.
- Log structure: append-only per-mailbox logs, per-topic Merkle logs, or a shared IPLD DAG with mutable signed heads.
- Whether native public libp2p circuit relays are added for clients requiring raw QUIC/TCP relay semantics.

## 19. Normative summary

- Durable Objects are the stateful WSS rendezvous/fallback layer.
- Direct peer communication is preferred for ordinary data transfer.
- Every relay and federation action is authenticated, idempotent, bounded, and resumable.
- Network N and Network M federate only through signed, narrow, expiring bilateral namespace grants.
- Each account is independently operated; accounts are never used to bypass a platform limit.
- Large content moves by CID over the best available path, not through ordinary Durable Object relay frames.
