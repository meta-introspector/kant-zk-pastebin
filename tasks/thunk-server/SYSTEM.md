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

1. Write `server/thunk.mjs` and `server/thunk-store.mjs` with one example
   transducer; verify load, apply, snapshot, restore, share.
2. Write `server/schedule.mjs` and the systemd driver `server/scheduler.mjs`;
   update `kant-relay.service` so the systemd service runs the scheduler loop.
3. Extend `relay.mjs` to host thunks and expose an API for scheduling.
4. Write `server/snapshot.mjs`; verify a worker snapshot restores with state.
5. Implement the scheduler → server-installed schedule handover.
6. Add tests and update PR #9 with the plan.
