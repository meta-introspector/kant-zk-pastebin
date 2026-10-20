// server/schedule.mjs — scheduler for thunks.
//
// systemd drives the loop now: scheduler.mjs calls `tick()` each
// period and runs the returned work on the server. Later the
// server installs schedules from a manifest and runs its own loop.

export class Schedule {
  #items = new Map(); // id -> { spec, nextAt, pending }
  #manifest = null;

  add(id, spec) {
    if (!["interval", "cron", "onEvent"].some((k) => k in spec)) throw new Error("schedule spec needs interval | cron | onEvent");
    this.#items.set(id, { spec, nextAt: this.#next(spec), pending: false });
    return id;
  }

  remove(id) {
    return this.#items.delete(id);
  }

  get ids() { return [...this.#items.keys()]; }

  /** Schedule loop entry point. Returns work to run. */
  tick(now) {
    const nowMs = now ?? Date.now();
    const out = [];
    for (const [id, item] of this.#items) {
      if (item.nextAt <= nowMs) {
        out.push({ id, input: { type: "tick", when: nowMs } });
        item.pending = true;
        item.nextAt = this.#next(item.spec, nowMs);
      }
    }
    return out;
  }

  /**
   * @param {object} context { server, thunkStore }
   */
  async runAll(context) {
    const now = Date.now();
    const pending = this.tick(now);
    await Promise.all(pending.map(({ id, input }) => this.#run(id, input, context)));
    return pending;
  }

  async #run(id, input, ctx) {
    try {
      const thunk = await ctx.thunkStore.get(id);
      if (!thunk) throw new Error(`thunk ${id} not found`);
      const result = thunk.apply(input);
      ctx.server.onThunkResult(id, result);
    } catch (e) {
      ctx.server.onThunkError(id, e);
    }
  }

  /** Next fire time. */
  #next(spec, after = 0) {
    if ("interval" in spec) return (after || Date.now()) + Number(spec.interval);
    if ("cron" in spec) return this.#cron(spec.cron, after);
    if ("onEvent" in spec) return after; // fired when event arrives
    throw new Error("no schedule spec");
  }

  #cron(expr, after = 0) {
    // simple "*/n" interval support; expand to a cron-like object
    if (!expr.startsWith("*/")) return after;
    const n = Number(expr.slice(2));
    return after + (n * 60 * 1000);
  }

  /** Eventually server-installed: load a manifest so the server owns its schedule. */
  installManifest(manifest) {
    this.#manifest = manifest;
    for (const entry of manifest) {
      this.add(entry.id, entry.spec);
    }
  }

  manifest() {
    return [...this.#items].map(([id, item]) => ({ id, spec: item.spec }));
  }
}
