---
name: thunk-server
priority: HIGH
depends_on: federated-p2p-relay, do-scheduler-modes
---

# thunk-server

**Status:** planning · **Date:** 2026-10-03

## Goal

Generalize the kant relay server so it **stores, runs, and shares thunks** —
state machines whose transitions are lambda closures captured as source. Each
state or process can be its own thunk. This is the foundation for:

- server-side scheduling that becomes independent of the scheduler process
- snapshotting a running server as a static worker and re-animating it elsewhere
- moving work across servers without restarting applications

## Instructions

- A thunk is a state machine: `{ snapshot() -> state, resume(state), run(input) }`
- Transitions (lambdas) are captured as source text so they are serializable
  and portable across servers.
- The systemd service is the scheduler for now: it ticks a loop, selects thunks
  to run, hands them to the server, collects results.
- Eventually the server **installs schedules itself** from a manifest, and the
  systemd service becomes a thin launcher.
- Servers are modified, snapshotted, and redeployed as static workers.

## Discoveries

- Existing relay is request-driven, not schedule-driven: `relay.mjs` serves
  endpoints and forwards; `store.js` is state plus a commit cadence; the
  systemd unit runs one long-lived process.
- `kant-relay.service` currently ExecStarts `server/relay.mjs` directly.
- Lambda closures are not serializable as-is; capturing **source text** and
  re-importing on the target server makes thunks portable.
- The store.js design (separate `RoomLog` shared between backends) is a good
  pattern for thunk state too: shared ring arithmetic, backend-specific `load`/`commit`.

## Accomplished

- [x] Federated P2P relay specification (v0.1) — task tracking in place
- [x] Do-scheduler-modes task — three modes (sleeping/awake/overage) defined
- [x] Task record: `tasks/thunk-server/SYSTEM.md`

## Not Done / In Progress

- [ ] Design thunk core: `server/thunk.mjs` (definition, serialization, run)
- [ ] Design thunk storage: `server/thunk-store.mjs` (store/run/list/snapshot)
- [ ] Design scheduler: `server/schedule.mjs` (add/tick/run-all/install)
- [ ] Write systemd driver: `server/scheduler.mjs` (supervisor loop)
- [ ] Extend relay to host thunks (update `server/relay.mjs`)
- [ ] Write snapshot/restore: `server/snapshot.mjs` (static workers)
- [ ] Update `server/kant-relay.service` to run the scheduler
- [ ] Implement a concrete example thunk (e.g., room log compactor)
- [ ] Test thunk sharing across two server instances
- [ ] Transition systemd scheduler → server-installed schedules
- [ ] Benchmark snapshot/restore of a running worker

## Relevant Files

| File | Status | Notes |
|------|--------|-------|
| `server/relay.mjs` | reference | Current request-driven server |
| `server/store.js` | reference | State + commit cadence, good design pattern |
| `server/kant-relay.service` | to update | ExecStart → scheduler driver |
| `server/worker.js` | reference | Cloudflare Durable Object variant |
| `server/pass-store.mjs` | reference | Example of per-thing state |
| `server/archive.mjs` | reference | Per-topic/archive logic |
| `tasks/do-scheduler-modes/` | parent task | Scheduler modes |

## Payload decision: content-addressable wasm

**Thunks are content-addressable wasm and JS, deployed and managed as
experiments.** Native is not being decided — it stays available as a backend
under the same thunk id. Full reasoning, measurements and phases are in
[WASM.md](WASM.md).

**The payload is not one format.** `js`, `wasm`, `lean`, `rust` and `nix` fall
into three groups: wasm is self-contained; `js` and a Rust dylib reach the host;
and `lean`/`rust`/`nix` are *inputs* that a toolchain turns into an artifact, so
they are referenced rather than embedded. The wrapper for those references is
**IPDL over IPFS** — and the codec already exists, at
`scripts/kant-codec.mjs`, with `ref`/`annot` and a full 64-hex `valHash`.
See [IPFS-IPDL.md](IPFS-IPDL.md).

**Compilers are thunks too.** `lake`, `cargo` and `nix` are content-addressed
refs, not ambient `$PATH`. The pattern already runs at scale in
`aristotle-manager-src/splitter-engine`: the splitter applied to itself produced
**2,761 declarations, 2,761 `flake.nix` files, and 175 independent flakes** —
a source file, its dependencies, and a per-declaration build. That is the thunk
shape; it just predates the name. Because the Lean toolchain is formalised and
the kernel is reachable by reflection in `aristotle`, the Lean chain terminates
in something *verifiable* rather than a pinned binary, while the Rust chain only
terminates in a pinned `rustc`. So "verified" and "pinned" are different claims
and the refs should be able to tell them apart. See
[TOOLCHAIN-THUNKS.md](TOOLCHAIN-THUNKS.md).

**The cycle.** Every thunk needs sops; `apis + sops + args` ⇒ results; a result
is either a new thunk or a cached value carrying history; a lens is just an
expensive thunk whose args are another thunk's results; constraints are respected
and the schedule is optimal. Two consequences worth
stating early — a thunk id covers `{bytes, refs}` and excludes sealed args, so
there must be a **second key**, `callId = {thunkId, argsHash, secretRefs}`, or a
credential ends up in a shared id. And "optimal" does not mean "fewest writes":
`scripts/relay-measure.mjs` measured that admission control binds before cadence
does. See [THUNK-CYCLE.md](THUNK-CYCLE.md).

The short version, measured rather than argued: `web/kant_kernel.wasm` is 799
bytes with **zero imports**, so isolation is a property of the artifact instead
of a policy around it, and the payload is 5% of one 16 KiB swarm frame. Three
consequences for the design above:

- `definition.transducers[].source` becomes `definition.bytes` — a module, not
  JS source text
- `id` becomes the full sha256 of those bytes, matching `asWitness`'s 64-hex
  convention rather than today's 16-char prefix
- an experiment is `{ thunk, hypothesis, inputs, cadence, observations, verdict }`,
  after the shape `scripts/relay-measure.mjs` established

**Phase 0 landed 2026-10-03: the loader works and the sandbox is decided.**
`Thunk.load` used to throw `ReferenceError: require is not defined` on every
input. Three separate causes, and fixing the first one is not enough:

- the context object `{ module, exports, require }` threw in an ES module, before
  `runInNewContext` was ever called;
- `new Function` parses its body as a *script*, so the `export function reduce`
  form used throughout [DESIGN.md](DESIGN.md) is a `SyntaxError`. The dialect is
  `module.exports = ...`, documented rather than papered over;
- the vm's `module` was not the object the loader read back.

The sandbox policy is **default-deny**, decided and recorded in
[SANDBOX.md](SANDBOX.md). The one-line alternative was `createRequire`, and it
is exactly what makes the isolation comment false: with it, a thunk doing
`require("node:child_process").execSync("id -u")` returned `REACHED:1000`.
A `js` thunk now gets no host capability at all, and capability comes from the
declared api set instead — the cycle already has that mechanism, so adding
`require` would have been a second, undeclared one.

**The two sandbox tests passed on the first fix and the sandbox was still open.**
That is worth recording rather than hiding:

| escape | why it survived | fix |
|---|---|---|
| `module.constructor.constructor(...)` | a host object placed in a vm context bridges to the host `Function` constructor, then to the host global | create `module`/`exports` inside the context |
| `this.constructor.constructor(...)` in a transducer | `transducers.reduce(...)` is a method call, so `this` binds to the host object — the same bridge by another name | destructure `reduce` so the call is unqualified |
| `console.log` from a thunk | Node injects `console` into every context it creates, and a log is a live handle on the host's stdout | `delete globalThis.console` before loading |

Plus a denial of service rather than an escape: a thunk calling `import()` raises
`ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING`, which ignores the thunk's own
`try`/`catch` and kills the host process. An `importModuleDynamically` callback
did not contain it. The refusal is at load time, before compilation.

So `server/sandbox-test.mjs` enumerates 13 escapes instead of testing one, and
asserts a pure thunk still works — a sandbox that refuses everything is an
outage, not a sandbox. It has teeth: reintroducing the host-object bridge makes
two of its cases fail.

`server/thunk-test.mjs` is 8/10 green. The two red gates are phase 1 — the id is
still a 16-char prefix where `asWitness` wants 64.

`server/example-compactor.mjs`, the one concrete thunk, is still written in the
ESM form and does not parse under this policy. `apply()` accepts both shapes, so
the conversion is mechanical; it was left alone because it is a decision about
the example rather than about the sandbox.

## Design summary (see `DESIGN.md`)

**Thunk** — serializable state machine:
- `definition`: { name, version, initialState, transducers: [{name, source}] }
- `state`: plain serializable snapshot
- `apply(input)`: runs transducer, returns { state, effects }
- `manifest()`: { id, name, version, hash } — shareable without state

**Store** — `ThunkStore`:
- `store(def) -> id`
- `get(id) -> Thunk`
- `list() -> [{id, name, version, timestamp}]`
- `snapshot(id) -> { definition, state }`

**Scheduler** — `Schedule`:
- `add(id, spec)` where spec = `{ interval, cron, or onEvent }`
- `tick(now) -> [{ thunkId, input } ]`
- `runAll(context) -> results`
- `installManifest(manifest)` — eventually server-installed

**Server** — hosts thunks:
- `storeThunk(def)`, `runThunk(id, input)`, `shareThunk(id)`
- `installSchedule(manifest)` — takes over scheduling

**Snapshot** — static workers:
- `snapshotServer(server) -> { manifest, state, ... }`
- `restoreServer(snapshot, env) -> Server`

## Next Actions

0. ~~**Make `Thunk.load` work at all.**~~ Done 2026-10-03, with the sandbox
   policy decided rather than assumed — see [SANDBOX.md](SANDBOX.md) and
   `server/sandbox-test.mjs`. Still open from the original item: fix
   `web/wasm-test.mjs`, which reads the gitignored `dist/` and so fails in a
   fresh checkout even though the embedded copy is byte-identical.
1. **Phase 1: content addressing.** The id is a 16-char prefix where `asWitness`
   wants 64. Make it the full sha256 of the module bytes, and add the second key
   `callId = {thunkId, argsHash, secretRefs}` while doing it — every later phase
   depends on that distinction and getting it wrong retrofits a key change
   through the cache, the sharing and the scheduler. `server/thunk-store.mjs`
   with one example transducer in the `module.exports` dialect, plus converting
   `server/example-compactor.mjs`.
2. Write `server/schedule.mjs` and the systemd driver `server/scheduler.mjs`;
   update `kant-relay.service` so the systemd service runs the scheduler loop.
3. Extend `relay.mjs` to host thunks and expose an API for scheduling.
4. Write `server/snapshot.mjs`; verify a worker snapshot restores with state.
5. Implement the scheduler → server-installed schedule handover.
6. Add tests and update PR #9 with the plan.
