// server/server.mjs — thunk host.
//
// This is the core server that stores, runs, and shares thunks.
// It wraps the existing relay so thunks can operate on the
// same state (e.g., a room-compactor thunk runs on the room state).

import { ThunkStore } from "./thunk-store.mjs";
import { Schedule } from "./schedule.mjs";

export class Server {
  constructor({ thunkStore, schedule, port } = {}) {
    this.thunkStore = thunkStore ?? new ThunkStore("/tmp/thunks");
    this.schedule = schedule ?? new Schedule();
    this.port = port ?? 0;
    this.server = null;
    this.results = new Map(); // id -> last result
    this.errors = new Map();  // id -> last error
  }

  /** Start the HTTP/WebSocket server (extends relay.mjs behavior). */
  async start() {
    // Defer to the existing relay.mjs startup logic for now
    // In the future: this.relay = await import("./relay.mjs"); this.relay.start();
    console.log(`[server] thunk host ready on :${this.port}`);
    return true;
  }

  /** Stop the server. */
  async stop() {
    // this.relay?.stop?.();
    return true;
  }

  /** Store a thunk definition and return its id. */
  storeThunk(def) {
    const t = new Thunk(def, def.initialState);
    return this.thunkStore.store(t);
  }

  /** Run a thunk with the given input and return the result. */
  async runThunk(id, input) {
    try {
      const thunk = await this.thunkStore.get(id);
      if (!thunk) throw new Error(`thunk not found: ${id}`);
      const result = thunk.apply(input);
      this.results.set(id, { ...result, ts: Date.now() });
      return result;
    } catch (e) {
      this.errors.set(id, { error: e.message, ts: Date.now() });
      throw e;
    }
  }

  /** Share a thunk (manifest + current state) for snapshotting/restoring elsewhere. */
  async shareThunk(id) {
    const thunk = await this.thunkStore.get(id);
    if (!thunk) throw new Error(`thunk not found: ${id}`);
    return thunk.share();
  }

  /** Install a schedule manifest — eventually called by the server itself. */
  installSchedule(manifest) {
    this.schedule.installManifest(manifest);
  }

  /** Hooks called by the scheduler when a thunk runs. */
  onThunkResult(id, result) {
    this.results.set(id, { ...result, ts: Date.now() });
  }

  onThunkError(id, error) {
    this.errors.set(id, { error: error.message ?? error, ts: Date.now() });
  }

  /** Diagnostic dump. */
  report() {
    return {
      port: this.port,
      thunks: this.thunkStore.list(),
      schedule: this.schedule.manifest(),
      results: [...this.results.entries()].map(([id, r]) => ({ id, ...r })),
      errors: [...this.errors.entries()].map(([id, e]) => ({ id, ...e })),
      ts: Date.now(),
    };
  }
}
