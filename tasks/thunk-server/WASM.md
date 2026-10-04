# Content-addressable thunks

**Date:** 2026-10-03 · **Status:** proposed · **Parent:** [SYSTEM.md](SYSTEM.md) · **Companion:** [DESIGN.md](DESIGN.md)

## The decision

**The end goal is extracting Lean 4 as wasm and shipping it as content-addressable
thunks, deployed and managed as experiments.**

Native is not being decided. It stays available as a *backend* under the same
thunk id, so the choice is deferred rather than foreclosed — but the swarm path is
wasm, and the wasm path is what gets built.

This document covers only what changes in [DESIGN.md](DESIGN.md). The thunk
model — `{ snapshot, resume, apply }`, captured transitions, a schedule — is
unchanged. What changes is what fills a thunk and how it is named.

## Why wasm is not a trade-off here

The claim that wasm costs something — size, speed, an extra hop — is testable
against what is already in the tree, so it was tested rather than argued.

`web/kant_kernel.wasm`, emitted by `lake exe emitwasm` from the encoder in
`RequestProject/Wasm/Encode.lean` and proved in `KernelSpec.lean`:

| property | measured |
|---|---|
| size | **799 bytes** |
| imports | **0** |
| exports | **21**, all `i64 -> ... -> i64` |
| determinism | same input, same output, repeatedly |
| embedded fallback | `web/kant-kernel-embedded.mjs`, byte-identical to the binary |

799 bytes is 5% of one 16 KiB frame. Against `FRAME_BYTES` in
`web/kant-libp2p.mjs:58`, transport cost is not a consideration at this size —
the payload rides in existing frames with no new transport work.

**Zero imports is the load-bearing property.** A module with no imports cannot
reach the host, so isolation is a property of the artifact rather than a policy
enforced around it. That is a stronger guarantee than anything the JS path can
offer, and it is what makes swarm-wasm the default rather than merely an option.

## What changes in the thunk

### 1. The definition stops being source text

[DESIGN.md](DESIGN.md) defines a thunk's `definition` as
`{ name, version, initialState, transducers: [{name, source}] }`, and
`server/thunk.mjs:57` loads that source to rebuild the lambdas. (That loader
does not currently run at all — see below — so this section describes the shape
to move to, not a working system to modify.)

Under wasm, the definition becomes:

```
definition = { name, version, format, bytes, exports, initialState }
```

- `format` is `"wasm"` or `"js"` — the backend, not the identity
- `bytes` is the module
- `exports` is the callable surface, checked on load

`initialState` and `schema` stay exactly as they are.

### 2. Identity is the hash of the bytes

**Done 2026-10-03.** The id is `valHash({ bytes, refs })` — the full 64-hex
digest from the same hash function file witnesses use, so `asWitness` accepts a
thunk id and the two are the same kind of thing.

I wrote this section proposing the full digest and not noticing that the
16-char prefix was hiding a collision underneath it. `cleanSource` stripped
comments with a regex, which also strips `//` inside a string literal, so any two
thunks mentioning a URL hashed the same:

```
fetcher@1.0.0:23e5f2ab254649ad  ->  {"url":"http://alpha.example/x"}
fetcher@1.0.0:23e5f2ab254649ad  ->  {"url":"http://BRAVO.evil.example/steal"}
```

One id, one cache entry, two behaviours. The prefix was the smaller problem.
`server/js-scan.mjs` is now a real scanner that tracks string, template and
regex state, and it still ignores comments — that part was the original intent
and it is worth keeping. `SYSTEM.md` has the details and the three tests.

`refs` are in the id, `name` and `version` are not, and there is a second key:

```
thunk id = valHash({ bytes, refs })
call id  = valHash({ thunkId, argsHash, secretRefs, apiRefs })
```

The original proposal, for the record:

```js
export const asWitness = (s) => {
  if (typeof s !== "string" || s.length !== 64) return null;
  ...
};
```

A truncated witness is a collision waiting for someone to grind it. Thunk ids
travel over the same transport as file witnesses, so they should obey the same
rule. The existing `manifest()` shape carries `sourceHash`; it becomes
`contentHash`, full length, and `manifest()` keeps working.

### 3. Transducers become calls, not closures

`reduce(state, input)` stops being a captured lambda and becomes a dispatch over
the export surface:

```
apply(input) -> { state, effects }
  1. validate input against schema
  2. call the named export with input
  3. write result into state
  4. return { state, effects }
```

For the kernel this is calling one of `KERNEL_EXPORTS`. For a single Lean
declaration it is the emitted function. The state machine is unchanged — only
its edges moved.

**Effectively total.** A wasm thunk cannot do anything the exported surface does
not already permit, because it has no imports. There is no `require`, no
`process`, no clock. This is the property that makes the swarm safe.

## `server/thunk.mjs` does not work at all

I wrote this section first as "the sandbox leaks `require`, so it is remote code
execution by design". **That was wrong**, and probing it is what showed why.

`scripts/thunk-sandbox-probe.mjs` and `.cjs` run the real `Thunk.load` and a
reproduction of `loadSource` (server/thunk.mjs:130-142). Three findings, in the
order they matter:

**1. No thunk can be loaded.** `Thunk.load` throws `ReferenceError: require is
not defined` on every input, including the trivial `module.exports.reduce = …`.
`server/thunk.mjs` is an ES module, so bare `require` is `undefined` in its
scope — the context object `{ module, exports, require }` throws before
`runInNewContext` is ever called. Nothing in [DESIGN.md](DESIGN.md) or the
checklist in [SYSTEM.md](SYSTEM.md) can be true today.

**2. `export` syntax cannot work either.** `loadSource` wraps the source in
`new Function(…)`, whose body parses as a *script*, not a module. The
`export function reduce` form shown throughout [DESIGN.md](DESIGN.md) is a
`SyntaxError`. A thunk must assign to `module.exports`. The design documents
everywhere show the module form.

**3. The sandbox `module` is not the object passed in.** Inside the vm, `module`
is not the context property of that name, so `module.exports.x = …` does not land
on the object `loadSource` reads afterwards. In the reproduction,
`Object.keys(passed.exports)` is `[]` and `runInNewContext` returns `undefined`,
while the vm's own `module` global does not exist either. So even with `require`
supplied, nothing is exported back.

**4. Once the loader is fixed, the `require` leak is real and reachable.** I
rebuilt `loadSource` in a scratch copy — `createRequire` plus `module` declared
inside the vm script — and a thunk doing
`require("node:child_process").execSync("id -u")` returned **`REACHED:1000`**.
It spawned a process and read the uid. So the comment's claim of *"no access to
the host process"* is false, and `timeout` bounds duration, not capability.

This is why the order matters. Today the leak is unreachable *only because
nothing loads*. The obvious fix for finding 1 — `createRequire(import.meta.url)`
— is precisely what turns the leak live. Fixing phase 0 without deciding the
sandbox policy makes things strictly worse.

Two honest options, to be chosen together with the phase-0 fix:

- **drop `require` from the sandbox entirely** — a thunk gets no host module
  access, which is what the comment already promises. Then the two capability
  tests in `server/thunk-test.mjs` pass for a real reason.
- **keep it and label the backend trusted** — a thunk that imports can spawn
  processes, so it must never be carried by the swarm.

**4b. `apply()` double-wraps state.** `server/thunk.mjs:107` assigns the
transducer's *whole* return value to the new state, so a transducer returning
`{ state, effects }` yields:

```
apply() -> { state: { state: { n: 2 }, effects: [] }, effects: ["state-change"] }
```

where [DESIGN.md](DESIGN.md) specifies `{ state: { n: 2 }, effects: [] }`. The
state after one apply is the transducer's wrapper, so the second apply reads
`state.n` as `undefined` and the arithmetic breaks. This is independent of the
loader and would survive a fix to it.

Either way this is the argument for wasm in one line: **a module with zero
imports cannot reach the host, so there is no policy to get wrong.** The 21
`KERNEL_EXPORTS` are the whole surface.

## Experiments

Thunks are **deployed and managed as experiments**, which is the shape
`scripts/relay-measure.mjs` already established for the relay: a hypothesis, a
cadence, a measured curve, and a summary that reports what happened rather than
what was asked for.

An experiment:

```
experiment = {
  thunk,              // content-addressed definition
  hypothesis,         // what this run is testing, in one sentence
  inputs,             // what it is fed
  cadence,            // how often
  observations: [],   // appended, never overwritten
  verdict             // written after, not derived silently
}
```

Three rules, each earned from a defect this cycle:

1. **An experiment records what happened, not what was requested.**
   `scripts/relay-measure.mjs:39` — `summarizeCadence` originally reported
   "100 POSTs" when the rate limiter had accepted 10. The counters were honest;
   the sentence was not.

2. **An experiment that cannot fail is not an experiment.** The 16 tests in
   `scripts/relay-telemetry.mjs` had three mutations survive the first pass,
   because the live fleet answered 200 everywhere and so could not distinguish a
   correct check from a wrong one.

3. **A deployment is a content hash, so "what is running" has one answer.**
   Two peers running the same thunk id are provably running the same bytes.
   This is what the id change buys, and it is the whole reason to do this before
   the thunk count grows.

## Phases

| # | phase | done when |
|---|---|---|
| 0 | **`loadSource` works, and the sandbox policy is decided** | `Thunk.load` accepts a trivial thunk; `apply` does not double-wrap; the two capability tests pass for a real reason. Today it throws on everything. |
| 1 | Content addressing | **done.** `id` is `valHash({ bytes, refs })`, 64 hex, no prefix; `callId` is a separate key. A fractional argument is refused, because `Kant.Codec.Val` has no float and IPDL drops them |
| 2 | wasm backend | a `format: "wasm"` thunk loads, applies, snapshots, resumes |
| 3 | Kernel as a thunk | the 21 `KERNEL_EXPORTS` are reachable through `apply(input)` |
| 4 | Swarm transport | a thunk crosses `web/kant-libp2p.mjs` frames; JS and Rust agree byte-for-byte |
| 5 | Experiments | `runExperiment()` records observations and a verdict; cadence is measured, not chosen |
| 6 | JS backend labelled | `format: "js"` is refused by the swarm, or explicitly trusted |

**Phase 0 was not in the original list** and it gates everything after it. It is
one small fix, and until it lands phases 1–3 are unmeasurable — there is no
thunk to hash.

Phases 0–3 are one afternoon each and need nothing from the network. Phase 4 is
the first one that touches the relay.

## Related

[IPFS-IPDL.md](IPFS-IPDL.md) extends this from one payload format to several, and
covers the case where the payload is a *source* (`lean`, `rust`, `nix`) rather
than an artifact. It reuses `valHash` from `scripts/kant-codec.mjs` as the thunk
id, so phase 1 and the IPDL resolver should be built together rather than
sequenced.

[TOOLCHAIN-THUNKS.md](TOOLCHAIN-THUNKS.md) then takes it one step further: the
compilers are thunks too, and the Lean chain terminates in a kernel rather than a
pinned binary — so "verified" and "pinned" become distinguishable claims.

## Decisions needed

**Does the swarm carry `js` thunks at all?** Phase 6 is blocked on this. Either
the swarm refuses them, or they are labelled trusted and carried anyway. The
first is safer; the second is more useful for a trusted private swarm.

There is no admission-control seam to hang this on yet. The nearest is
`admit()` in `server/pass-store.mjs:75`, which gates *lines in a room* by pass,
sender and time — it has no notion of a code payload and would need a separate
check. The 143-line backlog still cannot cross `pass-store.mjs:admit()` either,
so that file is already a known choke point. Worth deciding where the `format`
check lives before writing it twice.

**Is state still JSON?** It is now, and it should stay — it is what makes
`snapshot()` a one-liner and what lets state cross the transport without a
schema negotiation. But state grows, and JSON has no width limit. Worth revisiting
when a state first exceeds a frame.

**Does the kernel stay a single 799-byte module, or become per-declaration?**
Per-declaration means smaller payloads and finer-grained content addressing, at
the cost of many modules to fetch. One module is simpler and already fits a frame.

## Related

[THUNK-CYCLE.md](THUNK-CYCLE.md) is the loop these three feed: sops on every
thunk, `apis + sops + args` ⇒ results, results as new thunks or cached values
with history, a lens an expensive thunk over other thunks' results, and a schedule
constrained by measured budgets.

## Open

- ~~`web/wasm-test.mjs` reads `dist/kant_kernel.wasm` directly, and `dist/` is
  gitignored, so the test fails in a fresh checkout even though the embedded
  copy is byte-identical.~~ **Fixed.** The test now reads tracked artifacts
  (`web/kant_kernel.wasm`, `web/kernel-vectors.json`), which
  `scripts/embed-kernel.mjs` writes from `lake exe emitwasm`'s output and whose
  `--check` mode verifies them against it. Two claims replace the old
  `wasm-test-reads-gitignored-dist` defect: `wasm-test-inputs-tracked` asks git
  whether every file the test opens is tracked, and `kernel-vectors-satisfy-wasm`
  replays the 59 vectors against the binary. Both were mutation-tested — they go
  red when the `dist/` read is reintroduced and when a vector is corrupted.
- ~~There is no gate on the Lean side: `Wasm/KernelSpec.lean` proves one theorem
  per exported function, but nothing here ever compiled it.~~ **Fixed.**
  `lean-gate/` is the 13-module closure of `KernelSpec` with Mathlib removed —
  the Mathlib closure did not build (a bare `import Mathlib` took >401 s and
  the tree produced 0 oleans in 560 s) — and `scripts/lean-proof-gate.sh` runs
  `gokujo check` on it in **10.5 s cold / 2.7 s warm**, with `LEAN_PATH` unset so
  the Mathlib-freedom is enforced rather than assumed. `scripts/lean-proofs.mjs`
  runs it in the core suite. Two of the theorems it carries turned out to be
  false on the way (`eval_cantorPairE` claimed the kernel computes `Nat.pair`,
  which it does not; `reassemble_perm` is refuted by
  `[⟨5,5,[1]⟩,⟨9,9,[3]⟩]` vs `[⟨5,5,[2]⟩,⟨9,9,[3]⟩]`); both are restated or
  omitted, with the counterexamples, in `lean-gate/README.md` and in
  `Kant/Sneakernet.lean`. Three claims back it.
- `server/thunk-store.mjs` and `server/snapshot.mjs` are untracked and unreviewed.
  Phase 2 depends on the store.
- Nothing here is tested against a live swarm. Every wasm claim in this document
  is from reading the binary: `WebAssembly.Module.imports` returned `[]` and
  `mergeCids(1n, 2n)` returned the same value twice.