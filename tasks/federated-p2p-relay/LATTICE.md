# Integration lattice

**Date:** 2026-10-03 · **Status:** proposed · **Companion to** [PLAN.md](PLAN.md)

> **Open PRs on 2026-10-03** — three (of the four below), and they are not the
> branches here.
> PR #10 `feat/build-feed` (**Chain A tip**, 1442 files, `CONFLICTING`) is the
> one that matters: it is the tip this lattice's Step 4 exists for, and it is
> far larger than the 57-file conflict count suggested. PR #9 is
> `feature/big-merge` — this branch. PR #2 `feature/wip` is `MERGEABLE` but
> `UNSTABLE` (298 files). PR #1 (an external contributor's fix) turned out
> to be **already merged** while still open, and was closed; its one surviving
> finding is fixed in **#11**, which targets `main` and is independent of this
> lattice. See PLAN.md's Review log for the retraction.

Thirteen remote branches carry work that is in neither `feature/big-merge` nor
`main`. They are not a stack — they are two independent chains plus a set of
isolated snapshots, and the chains have crossed on the same files.

Everything below is derived from `git merge-base --is-ancestor` and
`git merge-tree --write-tree`, not read off branch names.

## The lattice

```
                        fix/sheaf-coordinates-and-hostname (13, 6mo)
                                       │
                    ┌──────────────────┴──────────────────┐
                    │                                     │
   feature/plugin-spinoff-snapshot (94, 5mo)      feature/lean (152)
                    │                                     │
                    └──────────────┬──────────────────────┘
                                   │
                          feat/build-feed (153)  ◄── CHAIN A TIP
                                   ╎
                                   ╎ 57 files conflict
                                   ╎
   feat/cli-fileshare (3) ──> dev/integrated (5) ──> fix/worker-ipfs-proxy (9)
                                                          │
                                       fix/lean-relay-handlewasmload (13)  ◄── CHAIN B TIP

   isolated:  main (1) · wip/mesh-state (1) · wip/service-file (1)
              wip/deploy-checkout (2) · wip/wasm-port-land (1)
```

### The one thing that makes this tractable

**Merge chain tips, not branches.** Ancestry means a single merge of
`feat/build-feed` brings in `feature/lean` *and* `fix/sheaf-coordinates`. A
single merge of `fix/lean-relay-handlewasmload` brings in `fix/worker-ipfs-proxy`,
`dev/integrated`, *and* `feat/cli-fileshare`.

So thirteen branches collapse to **two integration merges**, plus the isolated
snapshots handled individually. There is no need to merge anything twice or in
dependency order.

### The fork inside Chain A

`feature/plugin-spinoff-snapshot` and `feature/lean` both descend from
`fix/sheaf-coordinates` and neither contains the other. They conflict with each
other in **exactly one file** (`.gitignore`), so the fork is cheap to close if
both are wanted.

## Difficulty tiers

Conflict counts from `git merge-tree --write-tree --name-only HEAD origin/<branch>`.

| tier | conflicts | branches | merge base with `feature/big-merge` |
|---|---|---|---|
| **0 — trivial** | 0 | `main`, `feat/cli-fileshare`, `wip/service-file` | recent |
| **1 — trivial** | 1–2 | `wip/mesh-state`, `dev/integrated`, `fix/worker-ipfs-proxy`, **`fix/lean-relay-handlewasmload`** | **13 hours** |
| **2 — moderate** | 16–17 | `wip/wasm-port-land`, `fix/sheaf-coordinates` | ~6 months |
| **3 — heavy** | 24 | `feature/plugin-spinoff-snapshot` | ~5 months |
| **4 — very heavy** | 57 | `feature/lean`, **`feat/build-feed`** | **7 months** |

Tier 1 conflicts are confined to `.gitignore` and `src/mesh.rs` in every case.

### Why the tiers split where they do

The two chains are not comparably hard, and the reason is worth stating plainly:

- **Chain B** shares a merge base with this branch **13 hours old** — 27 local
  commits against 29 remote. Two conflicts.
- **Chain A** shares a merge base **7 months old** — 278 local against 153
  remote. Fifty-seven conflicts, including `Cargo.lock`, `flake.lock`,
  `web/kant-net.mjs`, `web/kant-file.mjs`, `server/relay.mjs`, `server/worker.js`,
  `src/lib.rs`, and the wasm bindings.

Chain A is not a merge. It is seven months of divergent development on the same
files, and treating it as a routine merge is how a branch ends up silently
broken.

### Do not merge `wip/deploy-checkout-20261003`

It carries `a5b8d7ff "libp2p: build against the real 3.x API"`, which is this
branch's `b23c518f` — the same work, under a different hash, snapshotted by a
concurrent agent. Its content is identical. Merging it duplicates the commit for
no gain. The other `wip/*` branches are likewise snapshots of uncommitted work,
not reviewable changes.

## Merge plan

Ordered by risk ascending, so the cheap merges land first and the expensive one
is attempted against an already-updated tree.

### Step 1 — Chain B tip (Tier 1)

```sh
git merge origin/fix/lean-relay-handlewasmload
```

Resolve `.gitignore` and `src/mesh.rs`. Everything else is mechanical.

**This is the one that matters most**, because it carries `317d5099` — the
Durable Object withdrawal. Landing it first means the relay question is settled
before the expensive merge, rather than after.

Then run the full suite. `317d5099` touches `web/kant-net.mjs`, and this branch
has changed that file for the profile, avatar, and libp2p work.

### Step 2 — Isolated snapshots (Tier 0–2), each its own PR

`main`, `feat/cli-fileshare`, `wip/service-file`, `wip/mesh-state`,
`wip/wasm-port-land`. Small and independent; `wip/wasm-port-land` has 16
conflicts but they are build files, not logic.

### Step 3 — The Codec decision

Blocking. See "Blocking decision" in [PLAN.md](PLAN.md). Nothing in Chain A
should be merged before this is settled, because Chain A rewrites
`web/kant-net.mjs`, which is where frame code would live.

### Step 4 — Chain A tip (Tier 4), only with agreement

```sh
git merge origin/feat/build-feed
```

Requires: the codec decided, the DO question settled, and someone who can
review fifty-seven files of seven-month divergence. **Recommend rebasing
`feat/build-feed` onto the post-Step-1 tree rather than three-way merging** — a
merge here resolves conflicts without either side understanding why, and the
result is a tree nobody has run.

Close the `.gitignore` fork with `feature/plugin-spinoff-snapshot` only if that
snapshot is still wanted; it is five months old and its purpose is unclear.

## Supporting the relay with and without a Durable Object

The withdrawal (`317d5099`) and production `kant-relay-v1` disagree: dev has no
DO, production still runs one on its `ROOMS` namespace. Both are deployed. So
this is not a decision to make once, it is a mode the relay has to have.

### The seam already exists

`317d5099` states the invariant that makes DO-less safe, and it is the right
one: **the peers are the record**. Every line carries its own witness, `ingest`
refuses anything that does not verify against the client's own key, and `publish`
sends to the mesh and the bus before it reaches the relay.

That means relay-side durability is a *cache*, not the system of record — and a
cache is exactly the thing that should have two interchangeable
implementations.

### The modular shape

```
                 wire protocol (lines, cursors, witnesses)
                              │
              ┌───────────────┴───────────────┐
              │                               │
        verification                     relay store          ◄── the seam
   (peer-side, always on)                    │
                              ┌───────────────┴───────────────┐
                              │                               │
                      isolate store                   sqlite store
                   (rendezvous mode)                  (mailbox mode)
                   survives a recycle                persists + hibernates
                   forgets on evict                  bounded, TTL, ACKs
```

The wire protocol and the verification path are identical in both modes. Only
the store differs. Concretely, `server/worker.js` currently mixes both: it has
the `Room` class *and* the DO bindings *and* an in-memory `sockets` Set, so
neither mode is cleanly separable today.

### What each mode owes the peer

This is the part that must be explicit, because it is what makes a lossy relay
honest rather than merely lossy:

| | rendezvous (no DO) | mailbox (DO) |
|---|---|---|
| survives isolate recycle | no | yes |
| survives eviction | no | yes |
| peer must hold the room | **yes, always** | only if the relay is unreachable |
| cursor means | "best effort position" | "durable position" |
| on resume | gap possible, peer must reconcile | gap bounded by retention |

A peer cannot treat the two cursors as the same thing. In rendezvous mode a
cursor is advisory; in mailbox mode it is a promise. **The mode has to be
announced in the handshake**, or a peer will trust a cursor that was never
durable.

### What this does to PLAN.md

- **W1 (WebSocket Hibernation)** applies only in mailbox mode. In rendezvous
  mode there is nothing to hibernate.
- **W5 (ACK)** only has meaning in mailbox mode. In rendezvous mode, delivery is
  best-effort and the peer is the record.
- **G3 (byte bound)** applies in both — an isolate has a memory ceiling too,
  though a much lower one.
- **G1–G5 all need re-citing** once Step 1 lands, because that commit rewrites
  `server/worker.js` and every gap in PLAN.md cites a line number there.

The mode flag should be config, not a code fork: `relay.mode = "rendezvous" |
"mailbox"`, with the store chosen at construction and the handshake announcing
which is in use.

## What still needs a person

1. **Is Chain A still wanted?** It is seven months divergent and rewrites the
   relay. If it is dead, say so and the lattice collapses to Step 1. PR #10
   makes this more urgent rather than less: `feat/build-feed` now shows as
   +259,511 / −659,420 across 1442 files, which is not an integration diff, it
   is a rewrite. **Confirm before anyone spends a day on it.**
2. **Are the `wip/*` snapshots wanted at all?** They are uncommitted-work
   captures, not changes.
3. **Who reconciles the Chain A merge?** It should not be whoever happens to be
   holding the branch when it becomes urgent. At 1442 files the conflict count
   (57) understates the work by an order of magnitude, so whoever takes this on
   should be told that number up front.
4. **PR #10 is `CONFLICTING` against `main`** and `mergeStateStatus: DIRTY`, so
   it is not currently mergeable regardless of the answer to (1).