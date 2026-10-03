# The thunk cycle

**Date:** 2026-10-03 · **Status:** proposed · **Companion to** [WASM.md](WASM.md), [IPFS-IPDL.md](IPFS-IPDL.md), [TOOLCHAIN-THUNKS.md](TOOLCHAIN-THUNKS.md)

## The five points

1. Every thunk needs **sops**.
2. `apis + sops + args` ⇒ `results`.
3. `results` are **new thunks, or cached values that return results plus history**.
4. **Everything is a lens.**
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
| **call id** | `{ thunk id, argsHash, secretRefs }` | cache of the *result* |

`secretRefs` names *which* sealed values were used, not their contents. Two calls
with the same secret and different args get different call ids; two calls with the
same secret under different names do not collide.

**This is the one genuinely new piece of machinery in the whole cycle.** Everything
else is naming. This is a cache key.

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
  `scripts/kant-codec.mjs`, which already returns a full 64-hex digest and is
  stable across serialization. Nothing new to build.

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

## 4. Everything is a lens

This is the strongest claim in the set and the one I have least direct evidence
for in *this* tree — there is no `Lens` in `src/` or `web/` here. It is the
vocabulary the `dasl-tiles` work uses elsewhere in the project, and taken
literally it says: every value, every id, every arg and every result is something
you read *through*, with the read recorded.

What that buys, concretely, is that the five points become observable:

| thing | lens reads | recorded |
|---|---|---|
| sops secret | named slot only | which refs a call used |
| api | the declared surface | what a thunk could reach |
| args | by path | what was actually read |
| result | by path | what was consumed |
| cached value | value + freshness | history |

The payoff is not philosophical. It is that **point 5 stops being a separate
mechanism**. An optimal schedule needs to know what a call reads and what it
returns; if every read and return is a lens event, the schedule is computed from
the same record that the audit log is computed from. One mechanism, two
consumers.

The cost is honest: lensing every read is overhead on the hot path, and
`snapshot()` currently deep-copies state on every call
(`server/thunk.mjs` `snapshot()` does `JSON.parse(JSON.stringify(...))`). Lensing
that without a per-thunk opt-out would make point 3's cache slower than recompute,
which defeats it. So lenses must be **off by default and per-thunk**, with the
swarm preferring lensed thunks because their history is portable.

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
            │                     lens reads recorded
            ▼                              ▼
      lens events ──────────> schedule (constraints + history)
```

## Phases

| # | phase | done when |
|---|---|---|
| 0 | [`WASM.md`](WASM.md) 0 | the loader works and the sandbox policy is decided |
| 1 | **call id** | `{thunkId, argsHash, secretRefs}` distinct from thunk id; two calls differing only in secrets are the same thunk but different calls |
| 2 | Secrets as refs | `secretRefs` name slots; contents never enter an id, a log, or a shared value |
| 3 | apis | a declared surface replaces ambient access; the api set is in the call id |
| 4 | Cached value + history | results carry `Observation`s; the same shape as a telemetry sample |
| 5 | Lenses, per-thunk, opt-in | reads recorded, off by default, on for thunks whose history travels |
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
- **Does lensing compose with the wasm story?** A wasm thunk with zero imports has
  nothing to lens from outside, so lenses are either internal instrumentation or
  they do not apply. That is a real limit on point 4, not a detail.
- **Nothing here is implemented.** `Schedule` exists as a class in
  `server/schedule.mjs`; no call id, no apis, no lens, no constrained scheduler.
  Every claim is from reading the tree and the three documents this one extends.