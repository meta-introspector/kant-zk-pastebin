# Task: federated-relay-phase1

- **Name:** federated-relay-phase1
- **Priority:** P0
- **Area:** kant-zk, relay, p2p, architecture
- **Status:** Draft plan — awaiting operator decision on the two questions in
  *Blocking decisions* below
**Depends on:** 2026-10-03-websocket-hibernation-bug
- **Created:** 2026-10-03
- **Parent:** `2026-10-03-federated-relay-spec`
- **Blocked by:** `2026-10-03-websocket-hibernation-bug` (P0, small)
- **Tags:** kant-zk, relay, p2p, architecture

## Scope

Phase 1 is the smallest slice of the spec that (a) is genuinely useful on its
own, and (b) is enough to falsify the risky parts before more of the spec is
built on top of it. It is not "the spec, less stuff".

Five work items, in dependency order.

### 1. Fix hibernation (this is the whole of `2026-10-03-websocket-hibernation-bug`)

Do this first because it is small, it is independently correct, and it is the
load-bearing assumption under everything else. Until sockets are
hibernate-eligible, every GB-s of Durable Object duration is billed, and §13 is
a claim rather than an implementation. `server/lean-relay.mjs:127` currently
calls `acceptWebSocket` on the wrong receiver with the wrong argument.

Exit: a test that fails on `9fd82eb1` and passes after, plus a real deployed
observation that an idle socket stops accruing duration.

### 2. One namespace, federated, end to end

Pick the single cheapest namespace — the one with the fewest invariants and the
least state. Do not start with the room namespace, which carries the ordering
guarantees, the `MAX_LINES`/`MAX_LINE` bounds, and the witnessed-line identity
model all at once. A namespace is only proven federated once a message posted
on Network N is readable on Network M, and the first namespace should be the
one where that proves the least.

Exit: a signed bilateral grant in place, one message crossing, verified with the
real client path (`KantNode` / `say()` / `pollOnce`), not a curl against
`/health`.

### 3. Grant verification as a separate, testable unit

§5's signed grants are the trust boundary. Implement verification as a pure
function with a test vector set before any transport depends on it: valid,
expired, revoked, wrong-network, wrong-namespace, bad signature, replayed
nonce. Six negative cases, not one positive case.

Exit: a test file where every negative case has an assertion. If a test only
ever exercises the accept path, the verifier is untested.

### 4. Reuse the merged codec, do not write a new one

§8 canonical codec and §8.4 CONNECT_REQUEST are already implemented and
already interoperable: `cidOf` / `rawCidOf` (CIDv1, raw, sha2-256) in
`web/kant-ipfs.mjs:83,144`, `envelopeEncode` / `envelopeDecode` in
`web/kantzk.mjs:432`, and `parseSignal` / `mesh.onSignal` / `mesh.broadcast` /
the direct-channel `onclose` in `web/kant-net.mjs:482,721,743,768`. Bounded
queues exist too, at `server/worker.js:30-31`.

Phase 1 should import these. A second codec is a second source of truth for
CID computation, and the in-Worker blob store work this session already had to
make agree with the client's `rawCidOf` is the shape of bug that duplication
produces.

§18 leaves the codec open; resolve it to DAG-CBOR in Phase 1, because it is
the only option where client and server can share code.

### 5. Budget enforcement, not just budget documentation

`2026-10-03-do-duration-budget` computes the number;
`2026-10-03-websocket-hibernation-bug` stops the leak. Phase 1 must also make
the *decision* PB-19 never made: a maximum concurrent-room count on the free
tier, enforced, with an alert at 50% of the daily duration budget. A relay
that can exceed its budget by having a popular room is not shippable, and
"we will keep an eye on it" is the thing that already failed.

Exit: an enforced cap, a 50%-of-budget alert, and a written projection for the
configuration being shipped.

## Explicitly not in Phase 1

- Direct peer-to-peer transport. That is Phase 2 and it is the largest risk in
  the spec; Phase 1 deliberately proves the federated *relay* path first, so a
  failure is attributable.
- The libp2p / Helia work. That is
  `2026-10-03-libp2p-prior-work-triage`, and it is independent of Phase 1.
- Multi-namespace federation beyond the one.
- Anything that changes the client page's user-visible behaviour. Phase 1 is
  invisible to users, which is how it stays small.

## Sequencing and reversibility

Each item lands as its own commit on its own branch, in the order above, so any
one can be abandoned without stranding the others. Item 1 is a fix to existing
code and can be merged on its own merits, before any decision about the rest of
the spec is made. That is deliberate: it is the one piece of this plan that is
correct regardless of how the two blocking questions are answered.

## Test plan

- Unit: grant verifier (7 vectors incl. 6 negatives); hibernation
  receiver/tag assertion that fails on the current line; codec round-trip
  against `rawCidOf` and `envelopeEncode`.
- Integration: one message N → M over the real client path.
- Cost: projected GB-s/day for the shipping configuration, written down and
  checked against the 13,000 GB-s/day tier.
- Non-vacuity: each test must be shown to fail against the pre-change code.
  This session has twice been caught by a test that passed against broken
  behaviour — `server/ipfs-store-test.mjs` asserted on a plain `POST /version`
  and passed against a worker with two Durable Objects, and a backoff unit
  suite passed while a seconds/milliseconds mismatch produced 1847 requests in
  12 seconds. A test that has never been observed failing is not evidence.

## Blocking decisions (asked 2026-10-03, still unanswered)

1. **Does the federated network replace the memory-only relay, or run beside
   it?** The no-Durable-Object decision was taken the same day as the spec was
   written, and the spec reverses it. Both are defensible: replacement is
   simpler and restores cross-PoP correctness; parallel is reversible and
   keeps chat working if the DO path regresses. The plan above works either
   way, but the *deployment* differs and item 1 should not wait on it.
2. **Two real deployments, or one plus a staging twin?** A staging twin costs
   a second worker name and a second domain but is the only way to exercise a
   signed-grant handshake between two *independently administered* networks
   without a second operator. Given the spec's premise is bilateral
   federation between separately administered deployments, testing N against M
   on one account proves the crypto but not the trust model.

## Risks

- **The spec reverses a deliberate decision made hours earlier.** If the
  reversal is not fully intended, Phase 1 is the wrong work and this task
  should be closed rather than executed. Resolved by question 1.
- **Budget regression.** Restoring Durable Objects re-opens the exact failure
  PB-19 was opened for. Mitigated by items 1 and 5, and the first deployment
  should be a single room with a hard cap.
- **Trust model untested with a real second operator.** Mitigated by question 2.
