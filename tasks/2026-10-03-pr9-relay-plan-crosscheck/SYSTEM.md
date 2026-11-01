# Task: pr9-relay-plan-crosscheck

- **Name:** pr9-relay-plan-crosscheck
- **Priority:** P1
- **Area:** kant-zk, relay, planning
- **Status:** open — two independent plans now exist for the same spec
- **Created:** 2026-10-03
- **Subject:** PR #9 `tasks/federated-p2p-relay/{SYSTEM,PLAN}.md` on
- **Tags:** kant-zk, relay, planning
  `feature/big-merge`

## What happened

Reviewing the open PRs surfaced a problem I had not accounted for: **PR #9
already contains a plan for this exact spec**, dated 2026-10-03, written
independently, with a 7-item gap table (G1–G7) and 7 sequenced workstreams
(W1–W7).

Two plans for one spec, neither referencing the other. This task reconciles
them. Recorded rather than merged-in-place because the divergence is real and
needs a decision, not a diff.

## Overlap — my plan independently reached the same conclusions

| My work | PR #9 plan | Same? |
|---|---|---|
| PB-29 / W1 hibernation | W1, gap G1 | **yes** — both put it first |
| grant verification (Phase 1 item 3) | W6, gap G6 "blocks all federation" | **yes** |
| §12.1 omits DO duration | §Budget: "~100k DO requests, 10ms CPU" | **yes** — same omission |
| §18 leaves the codec open | "Blocking decisions", codec must be settled before W5 | **yes** — and it is stricter |
| DAG-CBOR | undecided | **yes** |
| non-vacuity rule | "A suite that cannot go red is not evidence" + 3 named green-but-broken defects | **yes** — same lesson, same three cases |
| codec/frame work needs real-API reading | the libp2p `evt.data` vs `evt.detail.data` post-mortem | **yes** |

Seven independent agreements is a good sign for the shape of the work. It also
means **the plan in PR #9 is the better artifact** — it has file:line evidence
per gap, named risk per workstream, a test count per suite, and an explicit
sequence. Mine has the cost arithmetic and the node-first architecture, which
its plan lacks.

## Real divergences — three, and two matter

### 1. Durable Objects are the stateful layer vs. they are optional

PR #9's spec summary states it as normative: *"Durable Objects are the WSS
server (WebSocket Hibernation API mandatory)"*, and its §Budget lists DO
requests as a headline line item with no duration figure.

`2026-10-03-non-do-relay-research` (PB-33) concludes the opposite on cost: a DO
costs **11,059 GB-s/day per always-on room = 85% of the free tier**, while a
plain Worker is billed **no duration at all** and **zero requests per
WebSocket message**. With the always-on firewalled systemd nodes available, the
stateful layer should be the nodes and the DO should be optional edge fallback.

PR #9 also misses the duration row entirely — the same gap I found in §12.1,
which independently confirms PB-30 is a real spec defect and not my
misreading.

**This is the decision that must be made before W1–W7 sequencing means
anything**, because W1–W5 are all "make the DO relay correct". If the DO is
demoted to edge fallback, W3/W4 (byte bounds, 16 KiB inline) still apply to the
node relay, but W5 (ACK/mailbox) is largely superseded by node-side mailboxes.

### 2. The hibernation bug is in **two** places, and they are different bugs

I filed PB-29 against `server/lean-relay.mjs:127` — `envCtx.server.acceptWebSocket(server, envCtx)`, a call with the wrong receiver and wrong argument.

PR #9's G1 is against `server/worker.js:185` — `this.sockets = new Set()`, i.e.
**no hibernation API used at all**; sockets live in an in-memory Set and
`accept()` is presumably called normally.

Both are real and they are different defects:

| | lean-relay.mjs:127 | worker.js:185 |
|---|---|---|
| Defect | API called wrongly — never succeeds | API not used at all |
| Effect | no sockets ever | sockets held in instance memory, lost on eviction |
| Consequence | feature is dead | **silent**: log is persisted, so a hibernated room reloads correctly having lost every peer, and reports healthy |
| My framing | cost leak (duration never exempt) | — |

PR #9's characterisation of the *consequence* is better than mine and is worth
keeping: the `worker.js` version fails **silently and reports healthy**, which is
strictly worse than failing loudly. That is the same failure mode as PB-19's
`/health` staying 200 while every room read 500.

**PB-29 needs widening to cover both sites.** It currently names one.

### 3. G4 (256 KiB inline vs spec's 16 KiB) is not in my plan at all

`web/kant-file.mjs:31` `CHUNK_SIZE = 262144` against `server/relay.mjs:59`
`max-line`. The spec says 16 KiB. PR #9 flags it as medium risk and correctly
notes a 256 KiB chunk becomes 16 frames at 16 KiB — a 16× frame-count
increase on whichever path carries chunks inline.

I missed this entirely. It is a genuine budget and throughput gap that the
cost arithmetic in PB-33 does not cover, because frame *count* is not duration.

## What PR #9 gets right that I should adopt

- **Evidence per gap.** File and line for every claim. My gaps cite lines for
  existing code but not for the absent thing.
- **W2's idempotency decision (G2).** `server/worker.js:240` `this.lines.push(l)`
  stores a duplicate twice. §9.1 wants `(origin_network, from, message_id)`; the
  code keys on `(room, digest)`. PR #9's recommendation — digest primary,
  `message_id` as optional secondary index — is a real answer to a question I
  did not know to ask.
- **G7: two divergent DO implementations.** `server/worker.js` persists; the
  lean-worker rescue reports `durable: false`. "The relay" is ambiguous in every
  other document too. Real, and I did not see it.
- **G3: the ring is bounded by line count only.** One 256 KiB line against
  4096 short ones; at the current sizes the line-count bound permits ~1 GiB
  against a 1 GB per-object storage ceiling, so writes start failing rather
  than shedding load. That is a sharper failure-mode statement than mine.
- **A note on tests built after the bug, not before.** The libp2p adapter was
  first written against a remembered API and four things were wrong — wrong
  package, `evt.data` instead of `evt.detail.data` (every peer looked silent, no
  error anywhere), a `subscribe` return value that does not exist, an impossible
  browser `tcp()` listen address. **No test caught any of them.**

## The failure mode this review itself exhibited

I wrote PB-32 asserting the libp2p work was *"369 lines, never merged, never
executed, imported by nothing"* — based on a `wip/*` snapshot branch. The
reality on `feature/big-merge` is **690 lines, 768 lines of tests, 45 passing
checks, plus `src/libp2p_frames.rs` and `src/libp2p_transport.rs`**, with PR #9
stating the work is *done*. A triage task written from that premise would most
likely have concluded "discard".

Two of the three findings in this task — the missed G4 and the missed G2/G3 —
come from the same cause: **I planned from the spec text and from one stale
branch, and did not read the repo's existing plan or the open PRs.** The
enrichment pass I ran earlier looked for *prior tasks* and *prior code* and did
not look for *prior plans on open branches*.

Concretely: `git log origin/feature/big-merge --oneline` and `gh pr list` should
have been step one of the enrichment pass, not something done afterwards on
request.

## Recommended reconciliation

1. **Decide divergence 1 first** — node-first vs DO-primary. It determines
   whether W1–W7 is the work list or a subset of it.
2. **Widen PB-29** to both hibernation sites, and adopt PR #9's better
   characterisation of the silent failure.
3. **Adopt G2/G3/G4/G7** into the plan; they are real gaps I missed.
4. **Merge the two plans into one** in the repo — not two, since two plans for
   one spec is how the divergence above goes unnoticed.
5. **Delete the stale `wip/*` libp2p snapshot** so the next reader does not
   repeat my mistake.

## Related

- `2026-10-03-libp2p-prior-work-triage` — the correction to PB-32
- `2026-10-03-non-do-relay-research` (PB-33) — the node-first architecture
- `2026-10-03-websocket-hibernation-bug` (PB-29) — needs widening
- PR #9, PR #2, PR #1 — reviewed in the same pass