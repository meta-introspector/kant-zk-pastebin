# The thunk cycle

**Date:** 2026-10-03 · **Status:** proposed · **Companion to** [WASM.md](WASM.md), [IPFS-IPDL.md](IPFS-IPDL.md), [TOOLCHAIN-THUNKS.md](TOOLCHAIN-THUNKS.md)

## The five points

1. Every thunk needs **sops**.
2. `apis + sops + args` ⇒ `results`.
3. `results` are **new thunks, or cached values that return results plus history**.
4. **A lens is an expensive thunk.**
5. Resource constraints are respected and the schedule is **optimal**.

This document is the loop that ties the other three together. They describe what
a thunk *is*; this describes what happens when one runs.

## 1. Every thunk needs sops

Not "some thunks need credentials" — every thunk has a sealed argument surface.
The mechanism is already in the tree: `.sops.yaml` encrypts to an age recipient
(`age1qauw7gyz…`) with a PGP fallback, and `scripts/sops-run.sh` is the sanctioned
way in:

```bash
scripts/sops-run.sh npx wrangler deploy
scripts/sops-run.sh --only CLOUDFLARE_API_TOKEN -- ./deploy.sh
```

`.sops/registry.sops.yaml` holds `CLOUDFLARE_ACCOUNT_ID` and
`CLOUDFLARE_API_TOKEN`.

**Why it is every thunk and not only privileged ones:** a thunk's args are its
identity inputs. If any arg can be secret, then every thunk must be able to
declare a secret arg, and the capability has to exist on the path or it will be
reinvented badly. One mechanism, always present.

The design consequence is sharper than it looks: **a sealed arg is not part of the
id.** From [TOOLCHAIN-THUNKS.md](TOOLCHAIN-THUNKS.md), the id covers
`{ bytes, refs }`. Sealed args are supplied at call time and excluded, so two
thunks differing only in credentials are the same thunk. But then the cache key
cannot be the id alone, because two calls with different secrets may legitimately
produce different results.

So there are two keys:

| key | covers | used for |
|---|---|---|
| **thunk id** | `{ bytes, refs }` | identity, sharing, cache of the *definition* |
| **call id** | `{ thunk id, argsHash, secretRefs, apiRefs }` | cache of the *result* |

`secretRefs` names *which* sealed values were used, not their contents. Two calls
with the same secret and different args get different call ids; two calls with the
same secret under different names do not collide.

`apiRefs` is here because this document contradicted itself for a while. The
table above originally read `{ thunk id, argsHash, secretRefs }` while point 2
below argued that the api set must be part of the call id. The argument is
right and the table was incomplete: a result computed with a narrow api set must
not be served to a caller holding a wide one, because the wide one can do more
with it. Same shape as `secretRefs`, sharper reason.

**This is the one genuinely new piece of machinery in the whole cycle.** Everything
else is naming. This is a cache key.

**Landed 2026-10-03.** Both keys are computed in `server/thunk-id.mjs` through
`valHash` in `scripts/kant-codec.mjs`, which is the tree's one hash function, so
a thunk id and a file witness are the same kind of 64-hex thing and `asWitness`
accepts both. Three things the implementation had to decide that the prose above
did not say:

- **`argsHash` is `valHash` over a conversion, not over the raw args.**
  `valHash` takes a canonical `Val`, and a plain `{by: 1}` throws
  `CodecError: not a canonical value`. The conversion sorts object keys, because
  `canonEnc` walks fields in order and JS key order is not part of the value.
- **The codec has no float, so a fractional argument is refused.**
  `Kant.Codec.Val` defines six constructors — null, bool, int, str, list, obj —
  and `Val.lean:422` proves `canonEnc_injective` over exactly those six. IPDL
  drops floats for binary compatibility and proves its projection `LOSSLESS`.
  Adding a seventh type here would have made the JS `valHash` agree with the
  Lean one on everything both can name and silently disagree on everything else,
  so `argsHash` throws on `1.5` instead. The cost is real: no thunk taking a
  fractional number has a call id yet.
- **Unaddressable inputs are refused, not coerced.** `undefined`, `NaN`,
  `Infinity`, fractions, `-0`, functions, symbols, `Date`, `Map`, cycles: none
  has a spelling that reads back as itself, so a coerced hash would claim two
  different calls are one. This is the default-deny rule from
  [SANDBOX.md](SANDBOX.md), applied to identity rather than to capability.

## 2. `apis + sops + args ⇒ results`

An `api` is a declared capability surface — the functions a thunk may invoke. This
is what replaces "whatever is on `$PATH`", and it is the same move as
[TOOLCHAIN-THUNKS.md](TOOLCHAIN-THUNKS.md) applied to capabilities: the compiler
became a ref, so the runtime surface becomes one too.

```
call = { thunkId, apis: [ApiRef], secretRefs: [SecretRef], args }
result = { callId, thunkId, value, history, ... }
```

Three properties, in the order they matter:

- **The api set is part of the call id.** A thunk run with more apis is a
  different call, because it can do more. Otherwise a cached result computed with
  a narrow api gets returned to a caller holding a wide one.
- **`sops` supplies secrets, never apis.** Separating them keeps "what can this
  do" (public, hashed, shareable) distinct from "what does this know" (sealed).
- **Args are content-addressed.** `argsHash` is `valHash` from
  `scripts/kant-codec.mjs`, which returns a full 64-hex digest and is stable
  across serialization. It needed a conversion from plain values to canonical
  ones — see point 1 — and it covers the six types `Val` has, no more.

The wasm case from [WASM.md](WASM.md) is the degenerate one and worth naming: a
wasm thunk with zero imports needs no apis and no sops, because it cannot reach
anything. The cycle still holds — the api set is empty.

## 3. Results are new thunks, or cached values that return results plus history

Two branches, and the choice between them is a real distinction rather than a
stylistic one.

**A result becomes a thunk** when it is a *description* of further work — a
schedule, a plan, a derived artifact that should be independently addressable and
independently shareable. It gets an id, refs and apis, and can be called again.

**A result is a cached value** when it is *data* — a computed number, a rendered
page, a parsed structure. It gets a call id, the value, and **history**.

History is not optional bookkeeping. It is what makes point 5's "optimal
scheduling" possible at all, because scheduling needs to know what a call has
historically cost and returned. So:

```
CachedValue = { callId, thunkId, value, history: [Observation] }
Observation = { at, durationMs, requests, bytesIn, bytesOut, outcome }
```

`Observation` is the same shape as a telemetry sample in
`scripts/relay-telemetry.mjs`, and for the same reason: it is what a measurement
produces.

**Why history travels with the value rather than beside it.** If history is
separate, then a cached value can be served to someone who cannot see why it was
cached, or recomputed by someone who cannot see it was not. Carrying it makes the
cache self-describing: a peer can check whether the value is still fresh instead
of trusting a TTL it cannot verify.

## 4. A lens is an expensive thunk

The first phrasing of this point was "everything is a lens". That phrasing reads
as a fifth mechanism standing beside points 1–3, which is why it was the weakest
claim in the set. The sharper version is: **a lens is not a kind of thing, it is a
kind of thunk** — one whose job is to observe other thunks, and which is expensive
in four ways that can be measured rather than asserted.

So point 4 is not a peer of points 1–3. It is what they look like when the arg is
another thunk's result and the cost is paid on every poll.

### It is a thunk first

Nothing about being a lens changes the vocabulary:

| cycle term | for a lens |
|---|---|
| thunk id | `{ bytes, refs }` — same shape, so a lens is shareable like any thunk |
| call id | `{thunkId, argsHash, secretRefs}` — **but see cost 1: this does not determine the result** |
| apis | process control: `systemctl`, `pgrep`, and read access to the observed file |
| sops | unchanged; a lens reading sealed state must not be able to name what it read |
| args | the observed events — other thunks' results — plus a cursor |
| result | a cached value with history, where the value is ambiguous and history is the disambiguator |

The worked example is `StreamRegistry` in `dasl-tiles-rust/src/stream.rs`, which is
outside this tree and is the only lens in the project I can point at. It keeps one
`ServiceStream` per service, each holding `pids`, a `last_position` byte offset and
a `hit_count`, and it reads a global `hits.jsonl` written by someone else's eBPF
probe. Its args are another producer's results. That is the definition.

### Four costs, each one measured

**1. Its inputs are ambient, so its call id lies.** `service_pids`
(`stream.rs:63`) discovers what it will observe by shelling out: `systemctl show
<name> --property=MainPID,ControlGroup` (`:65`), then `pgrep -P <pid>` for the
cgroup children (`:88`), falling back to `pgrep -f <name>` (`:77`). Those pids
become the filter and they are never hashed, never an arg, and change under the
lens. Two calls with identical `thunkId` and `argsHash` therefore return different
values. Content-addressing a lens is only honest if the observed surface is either
in the args or in the id — and if it is, the lens stops being shareable across
machines, because pids are machine-local. That is a fork, not a missing feature.

Worse, `hit_count` accumulates under one pid set and is never recomputed when
`refresh_pids()` (`:102`) moves the pids, so the number is not a function of any
current input at all.

**2. N lenses is N passes over the same bytes.** `stream_events(service)`
(`:117`) is per stream; each stream seeks to its own `last_position` and
re-reads. Six registered services is six independent readers of one file, each
parsing every line and discarding the ones that are not its pid. The lens
multiplies read cost by the number of things observed. A shared parse with
per-service cursors is the obvious fix, and it is exactly the shape the cycle
already gives for free: the parse is the thunk, the cursor is its state, and each
service's view is a cheap projection of one cached value.

**3. It shells out to discover what to observe.** `discover_services()` (`:38`)
walks 8 candidate service names and calls `service_pids` for each, which is 2
subprocess spawns per name — **16 processes per discovery pass**. `refresh_pids()`
repeats it for every registered stream. This is why a lens's api set is not
optional: the process table is authority, and phase 3 is what makes it declared
instead of ambient.

**4. It wants a cadence the budget forbids.** `stream.rs:4` says refreshed every
2 seconds; the page actually served carries `meta http-equiv="refresh"
content="3"` (`server.rs:577`). Take 2–3s. `scripts/relay-telemetry.mjs` measured
the sustainable interval at **11s per worker**, with 50% of the Durable Object
allowance held back as headroom. The lens wants 4–5.5× what the budget affords.
That gap is not an implementation detail of point 4; it is the reason a lens has
to be a scheduled thunk instead of a loop.

### Why point 3's history is load-bearing here

`stream_events` returns `vec![]` in two different worlds: no new bytes
(`file_len <= stream.last_position`, `:130`) and no file at all (`File::open`
fails → `:126`). On this machine right now `/dev/shm/d8-2a-monitoring/` does not
exist, so `HITS_PATH` (`:13`) points at nothing and the lens returns the same `[]`
it would return for a healthy service with nothing new to report.

A lens that cannot tell those apart has a result that cannot be cached, shared or
trusted, because every consumer has to go ask the host again to recover the
distinction. So a lens's observation is a different shape from a throttle's:

```
LensObservation = { at, durationMs, bytesRead, inputsObserved, cursor, outcome }
outcome ∈ { fresh, no-new-data, input-missing, unreadable, inputs-changed }
```

`inputs-changed` is the one no throttle needs and every lens does — it is the pids
moving. And it is the honest reason history travels with the value: a peer holding
a lens result has no other way to tell whether the thing observed was alive.

### Where this leaves point 4

It collapses into 1–3 plus 5. There is no lens type, no lens runtime and no lens
store: **a lens is a thunk whose args are another thunk's results.** That also
dissolves the circularity — "but who lenses the lens?" has the same answer as "who
caches the cache?", which is point 3. The observer is a thunk, and a thunk may
observe a thunk.

### And it is only worth paying where history travels

Two facts in this tree say the accumulation machinery is not ready:

- `snapshot()` at `server/thunk.mjs:92` deep-copies state through
  `JSON.parse(JSON.stringify(...))`, so every observation costs a full
  serialization of the cursor state.
- `apply()` at `server/thunk.mjs:104` stores the transducer's whole
  `{ state, effects }` return as the new state (`:106`), so the second `apply`
  reads `state.*` off a wrapper and gets `undefined`. A lens accumulating
  observations through `apply` corrupts on the second one — before any of the four
  costs above are paid at all.

So the phase 5 gate is not "reads are recorded". It is: **a lens survives two
observations and can still tell live from dead.**

## 5. Respect resource constraints, schedule optimally

The constraint is already quantified, which is the useful part.
`scripts/relay-telemetry.mjs` computed it: **every 11s per worker** across three
workers, two requests a poll, half of the 100k/day Durable Object allowance held
back as headroom.

And `scripts/relay-measure.mjs` found something that should change how "optimal"
is defined:

> The passless rate limiter — 10 posts per sender per 10 minutes — caps requests
> long before the write cadence saves anything. DO write cost is second-order next
> to admission control.

So "optimal schedule" is not "minimise writes". It is a constrained optimisation
over several budgets, and the measurement says the binding one is usually
admission control:

```
maximise useful results
subject to  DO requests/day      <= budget x headroom
            writes/day            <= budget
            per-sender post rate   <= admission control
            cpu                   <= available
```

Two things follow that are worth stating before any scheduler is written:

- **Headroom is a constraint, not slack to spend.** The telemetry doc already
  reserves 50%; a scheduler that consumes it is a scheduler that has removed the
  margin that absorbs a traffic spike.
- **Admission control usually binds first.** Any scheduler optimising writes will
  look correct and change nothing.

`server/schedule.mjs` already has a `Schedule` class with `add`, `remove`,
`tick(now)` and `installManifest(manifest)`. **It has no notion of a constraint** —
`grep` for `budget|limit|max|headroom|duration` in it returns nothing. So `tick(now)`
answers "what is due" and nothing about "what can be afforded". That is the whole
of phase 6.

`tasks/do-scheduler-modes/` defines sleeping/awake/overage, and those are exactly
the states an optimal scheduler moves a thunk between — "overage" being load
shedding, which is what you do once the constraint binds.

## The cycle

```
     sops (every thunk)
            │
   apis + sops + args
            │  callId = {thunkId, argsHash, secretRefs}
            ▼
         results ──────────────┬── is it a description of more work?
            │                 │        → new thunk (id, refs, apis) → loop
            │                 │
            │                 └── is it data?
            │                         → cached value + history
            │                              │
            │              a lens is a thunk whose args are
            │              another thunk's results — so this box
            │              is not a new kind, it is this one again
            ▼                              ▼
   lens: 16 spawns to find what          schedule (constraints + history)
   to observe, N passes over the         ↑ reads the lens's history, which
   same bytes, 2–3s wanted vs             is the only thing that says
   11s affordable                         live from dead
```

## Phases

| # | phase | done when |
|---|---|---|
| 0 | [`WASM.md`](WASM.md) 0 | the loader works and the sandbox policy is decided |
| 1 | **call id** | `{thunkId, argsHash, secretRefs}` distinct from thunk id; two calls differing only in secrets are the same thunk but different calls |
| 2 | Secrets as refs | `secretRefs` name slots; contents never enter an id, a log, or a shared value |
| 3 | apis | a declared surface replaces ambient access; the api set is in the call id |
| 4 | Cached value + history | results carry `Observation`s; the same shape as a telemetry sample |
| 5 | Lens = thunk over other thunks' results | a lens survives two observations and can still tell `input-missing` from `no-new-data`; its ambient inputs are either hashed into the args or declared as an api, and the choice is made rather than defaulted |
| 6 | Constrained schedule | `Schedule.tick` takes the 11s and admission-control limits as inputs; today it knows neither; sleeping/awake/overage drive it |

**Phase 1 is the one to build first and it is small.** Almost every later phase
depends on the distinction between "what this thunk is" and "what this call did",
and getting it wrong retrofits a key change through the cache, the sharing, and
the scheduler.

Phases 2–3 are the security-relevant ones and should not be skipped by accident:
without them a thunk has ambient authority and a credential can leak into a shared
id.

## Open

- **Does an api set belong in the id or only in the call id?** I put it in the
  call id. If it belongs in the thunk id, a thunk is no longer portable across
  differing capability sets — which may be the point, or may be too strict.
- **History size.** `Observation` per call grows without bound. Point 3's cache
  and point 5's scheduling want opposite things: the cache wants the value, the
  scheduler wants the series. Probably two tiers, not yet decided.
- **The zero-import wasm thunk is the one thing that cannot be a lens.**
  `web/kant_kernel.wasm` has zero imports, so it has no api surface to observe
  with and no ambient input to observe — it is the cheapest thunk in the set and a
  lens is not among its possible shapes. That follows from point 4 as written and
  is the cleanest evidence that "a lens is an expensive thunk" is a classification
  rather than a slogan.
- **Where does a lens's ambient input go?** Cost 1 is a fork: into the args, which
  makes the lens honest and unshareable, or into a declared api, which keeps it
  shareable and makes the result depend on host state. I have not chosen.
- **Nothing here is implemented.** `Schedule` exists as a class in
  `server/schedule.mjs`; no call id, no apis, no lens, no constrained scheduler.
  Every claim is from reading the tree and the three documents this one extends.