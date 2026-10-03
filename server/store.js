// store.js — the relay's storage, separated from the relay.
//
// `worker.js` used to hold the room log in fields on the Durable Object and
// write the whole `{base, lines}` array on every POST and every websocket
// message. Two problems with that, and this module exists for both:
//
// 1. The write is proportional to the log, not to the change. At MAX_LINES
//    lines of up to MAX_LINE bytes, one append rewrites everything ever
//    retained. So does the commit cadence fix: `commitEvery` appends or
//    `commitIntervalMs` milliseconds, whichever comes first, and `flush()`
//    forces one. The cost moves to a knob instead of being paid per request.
//
// 2. In isolate mode the log is memory, and memory dies. That is not a
//    hypothetical: an isolate is evicted on an idle timer and data written
//    since the last durable commit is simply gone. `atRisk` counts exactly
//    those lines and `losses` counts the ones that were actually lost, so the
//    cadence can be tuned against a number rather than a feeling.
//
// The ring arithmetic is identical in both modes — `RoomLog` owns it and the
// backends differ only in `load` and `commit`. That is deliberate: a peer
// cannot tell which backend it is talking to except by what the handshake says
// about durability, so the parts that are observable must not diverge.

/** Default limits. The relay's protocol limits live in `worker.js`. */
export const DEFAULT_LIMITS = {
  /** Most lines retained. Reached, the oldest are dropped and readers told. */
  maxLines: 4096,
  /** Most bytes retained. The count bound alone is not a bound: one line may
   *  be `maxLine` bytes, so a line count permits maxLines * maxLine. */
  maxBytes: 8 * 1024 * 1024,
  /** Longest single line accepted. */
  maxLine: 262144,
};

/** Commit cadence. `every: 1` reproduces the old write-on-every-append. */
export const DEFAULT_COMMIT = {
  /** Commit after this many appends since the last commit. */
  every: 8,
  /** ...or after this long, whichever comes first. */
  intervalMs: 2000,
};

/**
 * The ring: an ordered, trimmed window of lines with a base offset.
 *
 * Both backends share this, so trimming and cursor arithmetic cannot drift
 * between the durable and lossy modes.
 */
export class RoomLog {
  constructor(limits = {}) {
    this.limits = { ...DEFAULT_LIMITS, ...limits };
    this.base = 0;
    this.lines = [];
    this.bytes = 0;
  }

  /** Highest cursor handed out so far. */
  get cursor() {
    return this.base + this.lines.length;
  }

  /**
   * Append lines, trimming from the front until both bounds hold.
   *
   * Returns how many were dropped, so a caller can report a truncated room
   * rather than silently serving a short one.
   */
  append(lines) {
    for (const l of lines) {
      this.lines.push(l);
      this.bytes += byteLength(l);
    }
    const dropped = this.trim();
    return dropped;
  }

  /** Enforce both bounds. Returns the number of lines dropped. */
  trim() {
    let dropped = 0;
    while (this.lines.length > this.limits.maxLines || this.bytes > this.limits.maxBytes) {
      const gone = this.lines.shift();
      this.bytes -= byteLength(gone);
      this.base += 1;
      dropped += 1;
    }
    return dropped;
  }

  /** Load a persisted snapshot. */
  restore({ base, lines }) {
    this.base = base ?? 0;
    this.lines = Array.isArray(lines) ? lines.slice() : [];
    this.bytes = 0;
    for (const l of this.lines) this.bytes += byteLength(l);
  }

  /**
   * The snapshot to persist.
   *
   * `watermark` is the highest cursor this log ever *handed out*, which is not
   * the same as `cursor`. A peer was told the room had reached `watermark`;
   * if a later boot restores a log holding fewer lines than that, those lines
   * were promised and are gone, and the gap is measurable. Without a separate
   * watermark the two are the same number and the check can never fire.
   */
  snapshot(watermark = 0) {
    return {
      base: this.base,
      lines: this.lines.slice(),
      cursor: this.cursor,
      watermark: Math.max(watermark, this.cursor),
      bytes: this.bytes,
    };
  }

  /**
   * Lines a reader at `cursor` has not seen.
   *
   * `truncated` means the reader fell off the front and there are lines it
   * will never receive — not that the room is empty.
   */
  fetchFrom(cursor) {
    const end = this.cursor;
    const from = Math.max(cursor, this.base);
    return {
      cursor: end,
      lines: this.lines.slice(from - this.base),
      truncated: cursor < this.base,
    };
  }
}

/**
 * Counters. Deliberately plain: they are reported verbatim at `/stats`, so
 * anything added here becomes part of what a client can observe.
 */
export class Stats {
  constructor() {
    this.boots = 0;
    this.appends = 0;
    this.linesIn = 0;
    this.linesDropped = 0;
    this.commits = 0;
    this.bytesWritten = 0;
    this.flushes = 0;
    /** Lines appended but not yet committed. */
    this.atRisk = 0;
    /** Appends since the last commit. */
    this.appendsSinceCommit = 0;
    /** The high-water mark this isolate has handed out. */
    this.issuedCursor = 0;
    /** Lines found missing on boot. Zero is not the same as "none lost". */
    this.losses = 0;
    /** Whether `losses` means anything. False when there is no durable
     *  watermark to compare against, which is the case in isolate mode. */
    this.lossMeasurable = false;
    /** Commits skipped by cadence. */
    this.commitsDeferred = 0;
  }

  toJSON() {
    return { ...this };
  }
}

const byteLength = (s) => {
  // Lines are ASCII in practice (hex-encoded Kant fields), but not
  // guaranteed: count bytes, not code units, so the byte bound is real.
  if (typeof TextEncoder !== "undefined") return new TextEncoder().encode(s).length;
  return Buffer.byteLength(s, "utf8");
};

/**
 * Storage that lives only as long as the isolate.
 *
 * Everything in the log is at risk from the moment it is appended, and `bootId`
 * changes on every construction so a reader can tell two isolates apart. The
 * `durable` flag is what the handshake has to report: in this mode a cursor is
 * a hint about what this isolate happened to see, not a promise.
 */
export class IsolateStore {
  constructor({ limits, commit, bootId } = {}) {
    this.log = new RoomLog(limits);
    this.commitPolicy = { ...DEFAULT_COMMIT, ...commit };
    this.bootId = bootId ?? newBootId();
    this.stats = new Stats();
    this.stats.boots = 1;
    this.sinceCommit = 0;
    this.pendingLines = 0;
    this.lastCommitAt = nowMs();
    this.loaded = Promise.resolve(null);
  }

  /** Whether a commit survives the isolate. */
  get durable() {
    return false;
  }

  /** Nothing to restore: the previous isolate took it with it. */
  async load() {
    return null;
  }

  /** Reload the log and reconcile what the last isolate claimed to have. */
  async ready() {
    const prior = await this.loaded;
    // A previous isolate issued cursors this one cannot account for. The
    // count is the gap, which is the number that matters: not "did we lose
    // something" but "how much".
    //
    // In isolate mode `prior` is always null -- there is nothing left to read
    // -- so `lossMeasurable` stays false. That is the honest answer and it is
    // the argument for syncing to a Durable Object: without one, loss cannot
    // be detected locally at all, only bounded by `atRisk`.
    const watermark = prior?.watermark ?? 0;
    if (watermark > this.log.cursor) {
      // Lines a peer was promised that this boot cannot find. This is the one
      // loss measurement that is actually available, and it needs the durable
      // watermark to mean anything.
      this.stats.losses += watermark - this.log.cursor;
      this.stats.lossMeasurable = true;
    }
    if (this.log.cursor > this.stats.issuedCursor) this.stats.issuedCursor = this.log.cursor;
    return prior;
  }

  append(lines) {
    this.stats.appends += 1;
    this.stats.linesIn += lines.length;
    const dropped = this.log.append(lines);
    this.stats.linesDropped += dropped;
    if (this.log.cursor > this.stats.issuedCursor) this.stats.issuedCursor = this.log.cursor;
    this.sinceCommit += 1;
    this.pendingLines += lines.length;
    // Two different questions, so two different numbers. Isolate mode commits
    // nothing, so EVERY retained line is exposed. Durable mode exposes only
    // what has been appended since the last commit -- counting retained lines
    // there would report 4096 at risk on a room that has committed all of
    // them, which is both wrong and the kind of wrong that gets ignored.
    this.stats.atRisk = this.durable ? this.pendingLines : this.log.lines.length;
    return { cursor: this.log.cursor, dropped };
  }

  fetchFrom(cursor) {
    return this.log.fetchFrom(cursor);
  }

  /** Cadence says whether this append is the one that commits. */
  dueForCommit() {
    return this.sinceCommit >= this.commitPolicy.every ||
      nowMs() - this.lastCommitAt >= this.commitPolicy.intervalMs;
  }

  async commit() {
    // A no-op, but not a silent one: the caller is told the data went
    // nowhere, and `atRisk` already says how much.
    this.stats.commitsDeferred += 1;
    return false;
  }

  /** Write now, whatever the cadence says. */
  async flush() {
    this.stats.flushes += 1;
    return false;
  }

  report() {
    return {
      mode: "rendezvous",
      durable: false,
      // Everything retained is exposed, and how much was actually lost is not
      // knowable from inside an isolate. A client reading this should treat a
      // zero `losses` as "unmeasured", not "none".
      lossMeasurable: this.stats.lossMeasurable,
      bootId: this.bootId,
      cursor: this.log.cursor,
      lines: this.log.lines.length,
      bytes: this.log.bytes,
      stats: this.stats.toJSON(),
    };
  }
}

/**
 * Storage backed by the Durable Object's own storage.
 *
 * The log is written on a cadence rather than per append, so `atRisk` is the
 * number of lines a hard kill would take with it. That is a real tradeoff and
 * it is reported rather than hidden: the caller can always `flush()` before
 * acknowledging a write it does not want to lose.
 */
export class DurableStore extends IsolateStore {
  constructor({ state, key = "log", limits, commit, bootId } = {}) {
    super({ limits, commit, bootId });
    this.state = state;
    this.key = key;
    this.stats.boots = 1;
    this.loaded = this.load_();
  }

  get durable() {
    return true;
  }

  async load_() {
    const kept = await this.state.storage.get(this.key);
    if (kept) {
      this.log.restore(kept);
      // The watermark is what a peer was last promised, so it has to survive
      // the reload: without it the next boot has nothing to measure against
      // and reports zero loss no matter how many lines actually went missing.
      this.stats.issuedCursor = Math.max(this.stats.issuedCursor, kept.watermark ?? 0);
    }
    return kept ?? null;
  }

  async ready() {
    const prior = await super.ready();
    this.lastCommitAt = nowMs();
    this.sinceCommit = 0;
    this.stats.atRisk = 0;
    return prior;
  }

  async commit() {
    const snap = this.log.snapshot(this.stats.issuedCursor);
    await this.state.storage.put(this.key, snap);
    this.stats.commits += 1;
    // Only what has not been committed can be lost. Reset here, after the
    // write succeeded, so a failed commit leaves the exposure standing.
    this.pendingLines = 0;
    this.stats.atRisk = 0;
    // Bytes actually written, not bytes retained: this is what a storage
    // budget is measured against.
    this.stats.bytesWritten += byteLength(JSON.stringify(snap));
    this.sinceCommit = 0;
    this.lastCommitAt = nowMs();
    return true;
  }

  async flush() {
    this.stats.flushes += 1;
    return this.commit();
  }

  report() {
    return {
      ...super.report(),
      mode: "mailbox",
      durable: true,
      // Lines since the last commit: what a hard kill right now would cost.
      pendingCommits: this.sinceCommit,
    };
  }
}

/**
 * Pick a backend.
 *
 * `mode` is explicit when given, because the whole point of supporting both is
 * that the choice is a decision rather than an accident of which bindings
 * happen to be deployed.
 *
 * The fallback probes for *storage*, not for a `ROOMS` binding. A Durable
 * Object has storage by definition and is not handed its own binding; whether
 * the Worker in front binds `ROOMS` tells us about routing, not about whether
 * this room can be written anywhere. Getting that backwards made a real
 * Durable Object silently run as a lossy isolate store.
 */
export function makeStore({ mode, env, state, limits, commit, key } = {}) {
  const hasStorage = Boolean(state?.storage);
  const chosen = mode ?? env?.RELAY_MODE ?? (hasStorage ? "mailbox" : "rendezvous");
  if (chosen === "mailbox") {
    // Refuse rather than downgrade. A relay that believed it was durable while
    // holding everything in memory would report cursors it cannot honour --
    // worse than saying nothing at all.
    if (!hasStorage) throw new Error("mailbox mode needs Durable Object storage");
    return new DurableStore({ state, key, limits, commit });
  }
  return new IsolateStore({ limits, commit });
}

const nowMs = () => (typeof Date !== "undefined" ? Date.now() : 0);

const newBootId = () => {
  const bytes = new Uint8Array(8);
  if (typeof crypto !== "undefined" && crypto.getRandomValues) crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
};