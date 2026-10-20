# Thunk server design

## Overview

A **thunk** is a lambda-based state machine. Transitions are lambdas captured as
source text so the thunk can be stored, sent to another server, and re-created
there. State is a plain serializable snapshot.

```
  definition (source)   state (data)   schedule (when)
        └──────────┬────┴───────┬────┬──────────┘
                     └───────────┴────┘
                           thunk
```

The server **stores** definitions + states, **runs** thunks per schedule, and
**shares** thunks (definition + current state) to other servers.

## Thunk

```javascript
// definition written as a module
export function reduce(state, input) { /* lambda */ return state; }
export const initialState = {};

class Thunk {
  static async load(source, name, version) { /* compile → Thunk */ }

  // shareable fingerprint — sent without state
  manifest() { return { id, name, version, hash(source) }; }

  snapshot() { return this.state; }
  resume(snapshot) { this.state = snapshot; }

  // run one transition; transducers are lambdas re-created from source
  apply(input) { return { state, effects }; }
}
```

**Capture model**: `vm` context loads the source module; the exported lambda is
re-serialized to source text on export. This keeps thunks portable.

## Thunk store

```javascript
class ThunkStore {
  store(def)   -> id;          // persist definition + initial state
  get(id)      -> Thunk;       // restore from definition + snapshot
  list()       -> [{id,name,version,timestamp}];
  snapshot(id) -> { definition, state };  // for sharing/snapshotting
  remove(id)   -> void;
}
```

Backends: in-memory (development) → SQLite/file (production), sharing the ring
arithmetic like `store.js` does for `RoomLog`.

## Scheduler

```javascript
class Schedule {
  add(id, spec)                 // spec: { interval, cron, or onEvent(handler) }
  tick(now) -> [{ thunkId, input }];
  runAll(context) -> results;   // delegate to server
  installManifest(manifest) { ... }  // eventually server-installed
  remove(id) { ... }
}
```

**Systemd-driven (now)**: `scheduler.mjs` runs the loop, calls `tick()`, runs
the returned work on the server.

**Server-installed (later)**: a schedule manifest is part of the server
snapshot; the server runs its own loop and systemd only launches it.

## Server

```javascript
class Server {
  constructor(env) {
    this.store = new ThunkStore(env);
    this.schedule = new Schedule();
  }

  storeThunk(def)     { return this.store.store(def); }
  runThunk(id, input) { return this.store.get(id).apply(input); }
  shareThunk(id)      { return this.store.snapshot(id); }
  installSchedule(m)  { this.schedule.installManifest(m); }
  report()            { return { thunks: ..., scheduled: ... }; }
}
```

`relay.mjs` is extended to instantiate a `Server` and host the existing room
state as a thunk (so rooms become runnable, restorable, shareable units).

## Snapshot / static workers

```javascript
snapshotServer(server) -> { definition, state, scheduleManifest, timestamp };
restoreServer(sn, env) -> Server;   // re-animates with state + schedule
```

A modified server is snapshotted and redeployed as a static worker: another
process restores the snapshot and continues from exactly where it left off.

## Phases

1. **Thunk core** — `thunk.mjs`, `thunk-store.mjs`; example transducer.
2. **Scheduler + systemd driver** — `schedule.mjs`, `scheduler.mjs`; service
   points at the driver.
3. **Server host** — `relay.mjs` hosts thunks; concrete example (room compactor)
   runs per-cadence.
4. **Sharing & snapshots** — `snapshot.mjs`; move a worker across servers.
5. **Self-scheduling** — server installs schedules from a manifest; systemd
   becomes a thin launcher.
6. **Modes** — sleeping/awake/overage built on schedule specs (feeds
   `do-scheduler-modes`).
