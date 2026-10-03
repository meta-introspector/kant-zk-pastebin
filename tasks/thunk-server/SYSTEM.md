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

**`server/thunk.mjs` does not currently work**, which blocks everything above.
`Thunk.load` throws `ReferenceError: require is not defined` on every input: the
file is an ES module, so bare `require` is undefined in its scope and the sandbox
context object `{ module, exports, require }` throws before `runInNewContext` is
called. Two related problems — `new Function` parses its body as a script, so
the `export function reduce` form shown in DESIGN.md is a `SyntaxError`; and the
vm's `module` is not the object passed in, so nothing is exported back.

Two more findings, both from rebuilding the loader in a scratch copy:

- **The `require` leak becomes reachable the moment the loader is fixed.** With
  `createRequire` in place, a thunk doing
  `require("node:child_process").execSync("id -u")` returned `REACHED:1000` — it
  spawned a process and read the uid. So `createRequire`, the obvious fix for the
  first finding, is also what makes the isolation comment false. **Phase 0 must
  decide the sandbox policy, not just make loading work.**
- **`apply()` double-wraps state.** `server/thunk.mjs:107` stores the
  transducer's whole `{state, effects}` return as the new state, so a second
  apply reads `state.n` as `undefined`. Independent of the loader.

I first wrote this up as "the sandbox leaks `require`, so it is remote code
execution by design" and then, when the probe refused to demonstrate it, as "not
currently exploitable". Both were wrong: it is not exploitable *now* because
nothing loads, and it is exploitable as soon as that is fixed.

`server/thunk-test.mjs` pins all of this as red-to-green gates (10 tests, all
currently failing). Under wasm this whole class of question disappears: a module
with zero imports cannot reach the host, so there is no policy to get wrong.

**Every number in these five documents is re-checked by a ledger.**
`scripts/thunk-claims.mjs` holds 23 claims, each a probe over one input with the
value it expects; `scripts/thunk-claims-test.mjs` mutates twelve of them and
asserts each goes red, because a probe that cannot fail is not a probe. Claims
are either **health** (red means a regression) or **defect** (red means a known
defect got fixed and the claim needs rewriting) — seven are defects on purpose,
which is how a fix announces itself. What it cannot cover is stated there too:
the fleet, the other repositories the lens numbers come from, and the
judgements. See [VERIFICATION.md](VERIFICATION.md).

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

0. **Make `Thunk.load` work at all** — it throws on every input today. Use
   `createRequire(import.meta.url)` or drop `require` from the sandbox entirely
   (preferable: the isolation comment already promises it), and make the vm's
   `module` actually the object that gets read back. Also fix
   `web/wasm-test.mjs`, which reads the gitignored `dist/` and so fails in a
   fresh checkout even though the embedded copy is byte-identical.
1. Then: `server/thunk.mjs` and `server/thunk-store.mjs` with one example
   transducer; verify load, apply, snapshot, restore, share. Per `WASM.md`, make
   the identity the full sha256 of the module bytes while doing it.
2. Write `server/schedule.mjs` and the systemd driver `server/scheduler.mjs`;
   update `kant-relay.service` so the systemd service runs the scheduler loop.
3. Extend `relay.mjs` to host thunks and expose an API for scheduling.
4. Write `server/snapshot.mjs`; verify a worker snapshot restores with state.
5. Implement the scheduler → server-installed schedule handover.
6. Add tests and update PR #9 with the plan.
