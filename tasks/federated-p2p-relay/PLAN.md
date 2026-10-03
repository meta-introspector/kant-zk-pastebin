# federated-p2p-relay — implementation plan

**Date:** 2026-10-03 (updated: measurement + PR review) · **Status:** in progress · **Spec:** [SYSTEM.md](SYSTEM.md)

## Scope

This plan covers the work between the tree as it stands and the Federated P2P
Relay Specification v0.1, for the relay path only. It does not cover libp2p
transport for file chunks — that is done (`52349366`, `b23c518f`, `f360e985`).

Every "gap" below was checked against a file and line on 2026-10-03. Where the
spec and the code disagree, both positions are stated rather than only the one
that is easier to implement.

## Status

Three commits landed after this plan was written and change what it says. Read
this section before the workstreams; the gaps G1–G7 below are still accurate,
but two of them are now partly addressed and one number has a measurement.

| commit | effect on this plan |
|---|---|
| `9cee0daf` | Partly closes **G7**. Storage is split out of the worker into `server/store.js` (`IsolateStore` / `DurableStore`), and `/stats` reports `mode` and `durable`. The lean-worker question is now "which modes are deployed", not "which DO is authoritative". |
| `f4235436` | Supplies the number **W3** and **W4** were asking to be measured, and changes W3's cost. |
| `9d9ba0ee` | Gives the polling cadence a number instead of a preference: every 11s per worker, at the spec §12 budget with 50% headroom. |

**Not deployed.** `9cee0daf` and `9d9ba0ee` are committed but not live: zero of
three known workers answer `/stats` (`kant-zk-relay-wasm`, `otc-desk-relay-v2`,
`otc-desk-relay-production`, all 404). So the split's behaviour is verified in
tests only. Deploying it is the precondition for every measurement below being
real, and this token's Cloudflare GraphQL exposes only `cost` and `viewer`, not
the analytics datasets, so the account's actual spend cannot be pulled either.
`scripts/relay-telemetry.mjs` states both facts on every run rather than
reporting a budget figure as if it were observed.

### What the cadence measurement changed

`f4235436` measured the thing **W3** optimises for. Over 100 POSTs at the
relay's real admission control — the passless limiter is 10 posts per sender
per 10 minutes — `every:1` performs 101 writes and `every:8` performs 13, an 87%
reduction. But the limiter caps requests long before cadence saves any writes,
so DO write cost is **second-order next to admission control**. Cadence matters
when a room has many senders, or when passes raise the ceiling.

That reorders the work. A byte bound (W3) and a commit-cadence knob are worth
less than an admission-control story, and the 256 KiB inline payload (G4/W4)
is the largest single driver of bytes-per-request.

## Baseline

| # | Gap | Evidence | Severity |
|---|---|---|---|
| G1 | No WebSocket Hibernation API; sockets live in an in-memory `Set` | `server/worker.js:185` | correctness |
| G2 | No idempotency — `append` stores a duplicate line twice | `server/worker.js:240` (`this.lines.push(l)`) | correctness |
| G3 | Ring is bounded by line count only, so one 256 KiB line costs 4096 short ones | `server/worker.js:31`, `:241-243` | budget |
| G4 | Inline payload is 256 KiB against the spec's 16 KiB cap | `web/kant-file.mjs:31`, `server/relay.mjs:59` | budget |
| G5 | No ACK, so a trimmed entry is indistinguishable from a delivered one | no `ack` in `server/worker.js` | design |
| G6 | No network identity, expiry, or revocation; membership is "holds the secret" | `web/kant-net.mjs:144` | blocks federation |
| G7 | Two DO implementations have diverged | `server/worker.js` persists; lean-worker `worker.js:146` reports `durable: false` | maintenance |

## Workstreams

Ordered by dependency, then cost. W1–W4 are independent of each other and can be
taken in any order or in parallel.

### W1 — WebSocket Hibernation API (G1)

**Why first.** It is the cheapest real correctness win here, and it is a
*silent* failure today: the log is persisted, so a hibernating object reloads
correctly while having lost every peer, and reports healthy. Nothing in the
current code notices.

**Change.** Replace the socket `Set` with `state.acceptWebSocket()` plus
`state.getWebSockets()`, moving `{ws, cursor}` into serialized attachments so
the peer and its cursor survive hibernation. Register the
`webSocketMessage` / `webSocketClose` handlers rather than per-socket closures.

**Proof.** A test that constructs the DO, hibernates it, and asserts the
attachments still identify the peer and its cursor. It must be shown to fail
against the current in-memory `Set` — otherwise it is testing the mock.

**Risk.** Low. The room logic does not change; only socket lifetime does.

### W2 — Idempotency keyed on the line digest (G2, and disagreement 3)

**Why.** §9.1 requires `(origin_network, from, message_id)`. We key on
`(room, digest)` where the digest is sha256 of the printed line
(`server/room-store.mjs:56`). Ours is arguably the stronger key — the digest
covers content that carries its own witness, so a forged `message_id` buys
nothing and suppression needs no trusted issuer. But a spec-conformant peer
cannot deduplicate against ours, so this has to be decided rather than left
implicit.

**Decision needed**, not just code: adopt the spec key, keep ours and document
the divergence, or carry both. Recommendation: keep the digest as primary and
treat `message_id` as an optional secondary index, so both agree on what a
duplicate is.

**Proof.** Post the same line twice, assert one stored record and one logical
outcome. Also assert the peer-side `room-store` and the relay agree — they are
two implementations of the same rule.

**Risk.** Low. Additive; the digest index needs pruning alongside the ring.

### W3 — Byte bound on the ring (G3)

**Change.** Track total retained bytes alongside `MAX_LINES` and trim on both.
Report which bound caused a trim, because a peer seeing `truncated` needs to
know whether it missed messages or only bytes.

**Reordered.** `f4235436` showed the write cadence is already tunable and worth
87% of writes under load (`9cee0daf` made it configurable). A byte bound caps
memory per room; a cadence knob caps write *operations*. Both matter, and the
measurement says admission control dominates both — see the Status section.

**Proof.** A room of 4096 short lines plus one oversized line must not exceed
the byte cap. The failure this prevents is specific: at 256 KiB per line the
current line-count bound permits ~1 GiB against a 1 GB per-object storage
ceiling, so the object starts failing writes rather than shedding load.

**Risk.** Low, but W4 changes the line size underneath it — do W4 first or
revisit the numbers after.

### W4 — Bring inline payloads to 16 KiB (G4)

**Change.** `CHUNK_SIZE` 262144 → 16384 in `web/kant-file.mjs`, and `max-line`
likewise in `server/relay.mjs`.

**Measure before committing.** A 256 KiB chunk becomes 16 frames, so a transfer
costs 16x the frame count on whichever path carries chunks inline. The gossipsub
path already complies (`FRAME_BYTES` is 16 KiB), so this only affects the relay
path — but it is a real cost and should be a number, not an assumption.

**Proof.** A file transfer over the relay completes at the new chunk size, and a
frame-count comparison against the old size is recorded in the commit.

**Risk.** Medium — this is the one workstream that can regress throughput.

### W5 — ACK and cursor semantics (G5)

**Depends on** W1 (ACKs need sockets that survive) and W2 (an ACK is only
idempotent if the delivery it acknowledges is).

**Change.** The spec's ACK frame carries a direction and a cursor. Decide what a
cursor acknowledges in a room-wide ring — the last *delivered* position is not
the same as the last *stored* position, and only the first lets a trimmed entry
be distinguished from a delivered one.

**This is the mailbox.** Until it exists, the relay is a bounded log and not the
§6.2 object, regardless of how it is described.

**Proof.** A peer that receives nothing, disconnects, reconnects, and resumes
from its last ACK gets exactly what it missed. And a peer that ACKs then
disconnects does not get the same messages again.

**Risk.** Medium. This is the first change that alters what a peer observes.

### W6 — Network identity and revocable membership (G6)

**Blocks all federation.** §5 and §10.1 rest on credentials that do not exist.
Today `roomOf(secret) = witness(secret)` (`web/kant-net.mjs:144`): everyone with
the secret is a member permanently, and no one can be removed. `kzpass` adds a
rate limit and a proof-of-work check, but has no issuer, no expiry, and no
revocation.

**Change.** A network authority key per network; signed, expiring membership
credentials bound to peer identity, network, and role; a revocation path with a
stated latency target (§18 leaves that open).

**Proof.** A revoked member's next request fails; an expired credential fails;
a credential issued by the wrong network's key fails. All three are the same
shape of check and should be one test with three cases.

**Risk.** High, and it is a protocol change — but nothing downstream can be
built correctly without it, so it should not be deferred past W5.

### W7 — Reconcile the two DOs (G7)

**Mostly done in `9cee0daf`,** which split storage into `server/store.js` with
an `IsolateStore` and a `DurableStore` behind one `makeStore({mode, …})`, and
made the write cadence tunable (`RELAY_COMMIT_EVERY`, `RELAY_COMMIT_INTERVAL_MS`).
`/stats` and `/health` now report `mode` and `durable`.

**What remains** is that nothing is deployed. `makeStore` probes `state?.storage`
rather than `env.ROOMS`, and a mailbox without storage **throws** rather than
degrading — which is correct, but means the decision is untested against a real
deployment. The census in `f4235436` found `otc-desk-relay-v2` self-reporting
`durable: false` with the note `"consumers sync lines into their own sqlite"`,
and `kant-zk-relay-production` reporting zeros across rooms/lines/sockets/peers.

**Proof.** Deploy, then re-run `scripts/relay-measure.mjs --fleet` and confirm
each worker names a mode instead of `unknown`. A worker that still reports
unknown has not been migrated, and should be listed rather than assumed.

**Also open:** the team's branches contradict each other on this. `317d5099`
withdrew the Durable Object on dev; `1ca352a3` put DOs back; `1b772bcb` reverted
that. One of those is a mistake, and the lattice cannot merge until it is
identified.

## Sequencing

```
W1 ──┬──> W5 <── W2
     │     │
W3 ──┘     └──> W6 ──> federation (spec Phase 4)
W4 (independent, but measure first)

W7 — mostly done (9cee0daf); what remains is deployment, not code
```

**Ahead of all of it: deploy W7.** Until a `/stats` answers, W3 and W4 are being
tuned against no observation, and the polling loop in `9d9ba0ee` samples
reachability only. That is the cheapest next move and it unblocks the rest.

## Blocking decisions

**The canonical codec must be settled before W5 writes any frame code.** The
spec says DAG-CBOR in §8, calls it an open question in §18, and illustrates the
frames as JSON in §8.1–8.3. All three cannot hold, and the encoding has to match
byte-for-byte across implementations.

This is not hypothetical: the JS libp2p adapter was first written against a
remembered API, and four things were wrong — the wrong package, `evt.data`
instead of `evt.detail.data` (so every peer looked silent with no error
anywhere), a `subscribe` return value that does not exist, and a `tcp()` listen
address that is impossible in a browser. **No test caught any of them.** The fix
was to read the real source, and the tests were then built to fail when the
implementation is wrong. Any new frame code should start the same way.

## Verification

Everything in W1–W7 is JS or Rust in this repository, so the suites already
exist:

| suite | count |
|---|---|
| `web/libp2p-test.mjs` | 45 |
| `web/net-test.mjs` | 51 |
| `web/page-test.mjs` | 88 |
| `web/pretty-test.mjs` | 48 |
| `scripts/cli-test.mjs` | 77 |
| `scripts/room-store-test.mjs` | 20 |
| `scripts/forward-test.mjs` | 8 |
| `server/store-test.mjs` | 32 |
| `server/room-test.mjs` | 28 |
| `scripts/relay-measure-test.mjs` | 18 |
| `scripts/relay-telemetry-test.mjs` | 16 |
| `cargo test --lib` (see `docs/RUST_TESTS.md` for the invocation) | 75 |
| `scripts/frames-crosscheck.sh` | 20 |

### A test suite that cannot fail is a liability, not evidence

The `rust-ipfs` submodule must be initialised (`git submodule update --init
vendor/rust-ipfs`) or the crate will not build at all — this bit during review
of PR #1.

Of the sixteen telemetry tests, **three mutations survived the first pass**:
`requestsPerPoll` halved, `durable` coerced from `null` to `false`, and
`status >= 200` accepted for reachability. All three passed because the live
fleet happens to answer 200 on every worker, so probing the real endpoint
cannot distinguish a correct check from a wrong one. The fix was to test
`isReachable` and `normalizeHealth` as pure functions, off the wire. A test
whose subject is a live service can only ever assert what that service happens
to be doing today.

## Review log

**PR #1** (`twilwa`, `fix(access): use public paste access urls`) — reviewed
2026-10-03. The intent is right and the two tests are genuinely good: they
assert the absence of `localhost:8090` and of the old `ipfs cat` line, which is
the actual regression. Three findings, in the order they block a merge:

1. **It introduces reflected XSS.** `normalized_base_url()` derives the origin
   from `connection_info().host()`, which prefers `X-Forwarded-Host` over
   `Host`, and interpolates it into the paste page **unescaped** inside an
   `onclick` attribute. Before the PR that value came from `BASE_URL`, an
   operator-controlled env var; after, it comes from the request. Verified by
   probe, not by reading: a request with
   `X-Forwarded-Host: evil"><script>alert(1)</script>` returns
   `raw_tag=true escaped=false`, with the tag intact in all three command
   divs. Needs HTML-escaping on the interpolated origin, and a test with a
   hostile header that fails against the current code.
2. **It does not compile.** Against this tree: `PasteIndex` has gained a `root`
   field the PR's base predates, and `store_blocks()` in `ipfs.rs` assumes one
   `cid` type where `rust-unixfs` and `ipld-core` resolve the crate from two
   different registries and get distinct types. The PR's own `cargo test` claim
   in its description is not reproducible here. (A bridge exists — convert by
   bytes — but that belongs in the PR, not in review.)
3. **143 of its ~1454 diff lines are `rustfmt`.** The substantive change is
   about 70 lines. Worth splitting so the security fix is reviewable on its own.

The two rust changes are otherwise sound and better than what they replace:
`write_block` now returns whether it wrote, so a partial DAG cannot report
success, and `ipfs_add_bytes` fails closed when no repo exists rather than
returning a CID that resolves to nothing.

**A suite that cannot go red is not evidence.** Every workstream above should
add at least one test, and each new test should be shown to fail against the
current code before it is shown to pass. Three defects this cycle were green
under a passing suite: a bridge that reported success having carried nothing, a
relay filter keyed on the wrong witness, and a nonce test that passed against a
code path never taken.

## Out of scope

- Federation between networks (spec Phase 4) — blocked on W6.
- Production migration off the Free plan (Phase 5) — a decision, not code.
- `helia-integration` — separate task; can sit on top of this later.
- Anything requiring a second Cloudflare account. Two accounts is only
  legitimate if N and M are genuinely separately administered with independent
  membership, keys, and operations. If they share an operator and a user base,
  the spec's own non-goals forbid it.