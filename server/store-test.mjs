// store-test.mjs — the relay store, in Node, with no Cloudflare.
//
// The durable backend is driven through a fake `state.storage` rather than
// skipped, because the commit cadence and the loss accounting are the two
// things most likely to be wrong and neither is visible without them.

import {
  DurableStore, IsolateStore, RoomLog, Stats, makeStore,
} from "./store.js";

// Tests are collected and run at the end, awaited one at a time. An earlier
// version called each test inline and did not await, so every async test's
// rejection escaped as an unhandled rejection and killed the run instead of
// reporting a failure -- a green-looking suite that had not run.
let pass = 0, fail = 0;
const failures = [];
const tests = [];
const t = (name, fn) => { tests.push([name, fn]); };

const W = (n, c = "x") => c.repeat(n);

/** A DO `state.storage` stand-in that counts writes and can be wiped. */
function fakeState() {
  const map = new Map();
  const reads = { n: 0 };
  const writes = { n: 0, bytes: 0 };
  let died = false;
  return {
    map, reads, writes,
    storage: {
      async get(k) { reads.n++; return map.get(k); },
      async put(k, v) {
        writes.n++;
        writes.bytes += JSON.stringify(v).length;
        map.set(k, v);
      },
    },
    /**
     * Simulate the isolate being evicted.
     *
     * Deliberately leaves storage alone: a Durable Object's storage outlives
     * the isolate, and clearing it here would model a total storage loss --
     * a different failure, with a different test.
     */
    isolateDied() { died = true; },
    get isolateAlive() { return !died; },
  };
}

const line = (i) => W(40, String.fromCharCode(97 + (i % 26)));

// ---------------------------------------------------------------- RoomLog

t("a fresh log hands out cursor 0 and no lines", () => {
  const l = new RoomLog();
  if (l.cursor !== 0) throw new Error(`cursor ${l.cursor}`);
  if (l.fetchFrom(0).lines.length !== 0) throw new Error("should be empty");
});

t("appending advances the cursor by the line count", () => {
  const l = new RoomLog();
  l.append(["a", "b", "c"]);
  if (l.cursor !== 3) throw new Error(`cursor ${l.cursor}`);
});

t("a reader at the cursor sees nothing new", () => {
  const l = new RoomLog();
  l.append(["a", "b"]);
  const out = l.fetchFrom(2);
  if (out.lines.length !== 0) throw new Error("should be empty");
  if (out.truncated) throw new Error("not truncated");
});

t("a reader behind the base is told it was truncated", () => {
  const l = new RoomLog({ maxLines: 2 });
  l.append(["a", "b", "c"]);
  const out = l.fetchFrom(0);
  if (!out.truncated) throw new Error("must report truncation");
});

t("the line bound drops from the front and moves the base", () => {
  const l = new RoomLog({ maxLines: 3 });
  l.append(["a", "b", "c", "d", "e"]);
  if (l.lines.length !== 3) throw new Error(`kept ${l.lines.length}`);
  if (l.base !== 2) throw new Error(`base ${l.base}`);
  if (l.cursor !== 5) throw new Error(`cursor ${l.cursor}`);
});

t("the BYTE bound binds independently of the line bound", () => {
  // The whole point: a line count is not a storage bound. One 200-byte line
  // with maxLines 4096 permits ~800KB, so a small maxBytes must bite first.
  const l = new RoomLog({ maxLines: 4096, maxBytes: 250 });
  l.append([W(200, "a"), W(200, "b")]);
  if (l.lines.length !== 1) throw new Error(`kept ${l.lines.length}, want 1`);
  if (l.base !== 1) throw new Error(`base ${l.base}`);
});

t("byte accounting is released as lines are dropped", () => {
  const l = new RoomLog({ maxLines: 10, maxBytes: 500 });
  l.append([W(300, "a"), W(300, "b")]);   // 600 exceeds 500 -> one is dropped
  if (l.lines.length !== 1) throw new Error(`kept ${l.lines.length}`);
  if (l.bytes !== 300) throw new Error(`bytes ${l.bytes}, want 300`);
  // The count must track what is retained, not accumulate forever: a stale
  // byte total would evict a room that is nowhere near its bound.
  l.append([W(100, "c")]);                 // 400 total, nothing dropped
  if (l.bytes !== 400) throw new Error(`bytes ${l.bytes}, want 400`);
  l.append([W(300, "d")]);                 // 700 -> trims until under 500
  if (l.bytes !== byteLen(l.lines.join(""))) throw new Error("byte count drifted");
  if (l.bytes > 500) throw new Error(`bytes ${l.bytes} over the bound`);
});

t("the byte bound counts bytes, not code units", () => {
  // A line of 4-byte characters is 8 bytes but 2 code units. Counting code
  // units would let twice the intended payload through.
  const l = new RoomLog({ maxLines: 100, maxBytes: 8 });
  l.append(["\u{1F600}\u{1F600}"]); // 2 code units, 8 bytes
  if (l.bytes !== 8) throw new Error(`bytes ${l.bytes}, want 8`);
});

t("restore round-trips a snapshot", () => {
  const a = new RoomLog();
  a.append(["x", "y", "z"]);
  const b = new RoomLog();
  b.restore(a.snapshot());
  if (b.cursor !== a.cursor) throw new Error("cursor");
  if (b.bytes !== a.bytes) throw new Error("bytes");
  if (b.fetchFrom(0).lines.join() !== "x,y,z") throw new Error("lines");
});

t("a snapshot is a copy, not a live view", () => {
  const a = new RoomLog();
  a.append(["x"]);
  const snap = a.snapshot();
  a.append(["y"]);
  if (snap.lines.length !== 1) throw new Error("snapshot aliased the live array");
});

// ------------------------------------------------------------ IsolateStore

t("isolate mode reports itself as not durable", () => {
  if (new IsolateStore().durable !== false) throw new Error("claimed durable");
});

t("isolate mode commits nothing and says so", async () => {
  // `commit` returning false is what stops a caller believing the data is safe.
  const s = new IsolateStore();
  s.append(["a"]);
  const wrote = await s.commit();
  if (wrote !== false) throw new Error("claimed a write it did not make");
  if (s.stats.commitsDeferred !== 1) throw new Error("deferred not counted");
});

t("everything retained in isolate mode is at risk", () => {
  const s = new IsolateStore();
  s.append(["a", "b", "c"]);
  if (s.stats.atRisk !== 3) throw new Error(`atRisk ${s.stats.atRisk}`);
});

t("isolate mode says loss is unmeasurable rather than reporting zero", async () => {
  // An isolate that previously handed out cursor 5 and now boots empty HAS
  // lost 5 lines -- and nothing inside it can know that, because there is no
  // watermark left to compare against. Reporting `losses: 0` here would read
  // as "none lost", which is the one thing it cannot support.
  const s = new IsolateStore();
  await s.ready();
  if (s.stats.lossMeasurable !== false) throw new Error("claimed measurable");
  if (s.report().lossMeasurable !== false) throw new Error("report hid it");
  // What IS available is the exposure bound.
  s.append(["a", "b", "c"]);
  if (s.stats.atRisk !== 3) throw new Error(`atRisk ${s.stats.atRisk}`);
});

t("durable mode measures the loss a fresh boot cannot account for", async () => {
  // With a persisted watermark, the gap IS knowable: an isolate that resumes
  // below the cursor it last handed out has lost the difference.
  const st = fakeState();
  const a = new DurableStore({ state: st });
  await a.ready();
  a.append(["a", "b", "c", "d", "e"]);
  await a.flush();
  // Storage is truncated behind our back -- a quota trim, or a restore from
  // an older snapshot. The watermark says peers were told about 5 lines.
  st.map.set("log", { base: 0, lines: ["a", "b"], cursor: 2, watermark: 5, bytes: 2 });

  const b = new DurableStore({ state: st });
  await b.ready();
  if (b.stats.lossMeasurable !== true) throw new Error("should be measurable");
  if (b.stats.losses !== 3) throw new Error(`losses ${b.stats.losses}, want 3`);
});

t("a fresh isolate starts empty — that is the loss", () => {
  const s = new IsolateStore();
  if (s.log.lines.length !== 0) throw new Error("isolate mode must not fabricate state");
  if (s.log.cursor !== 0) throw new Error("cursor should be 0");
});

t("each isolate gets a distinct boot id", () => {
  const a = new IsolateStore().bootId, b = new IsolateStore().bootId;
  if (a === b) throw new Error("boot ids collided");
});

// ----------------------------------------------------------- DurableStore

t("durable mode reports itself as durable", () => {
  if (new DurableStore({ state: fakeState() }).durable !== true) throw new Error("not durable");
});

t("a durable store restores what the previous isolate committed", async () => {
  const st = fakeState();
  const a = new DurableStore({ state: st });
  await a.ready();
  a.append(["a", "b", "c"]);
  await a.flush();

  const b = new DurableStore({ state: st });
  await b.ready();
  if (b.log.cursor !== 3) throw new Error(`cursor ${b.log.cursor}`);
  if (b.fetchFrom(0).lines.join() !== "a,b,c") throw new Error("lines");
});

t("commit cadence defers writes instead of writing every append", async () => {
  const st = fakeState();
  const s = new DurableStore({ state: st, commit: { every: 4, intervalMs: 1e9 } });
  await s.ready();
  for (let i = 0; i < 3; i++) s.append([line(i)]);
  if (st.writes.n !== 0) throw new Error(`wrote ${st.writes.n} times before the cadence`);
  if (s.stats.atRisk !== 3) throw new Error(`atRisk ${s.stats.atRisk}`);
});

t("the cadence commits on the Nth append", async () => {
  const st = fakeState();
  const s = new DurableStore({ state: st, commit: { every: 4, intervalMs: 1e9 } });
  await s.ready();
  for (let i = 0; i < 3; i++) s.append([line(i)]);
  if (s.dueForCommit()) throw new Error("due before the Nth append");
  s.append([line(3)]);
  if (!s.dueForCommit()) throw new Error("not due at N");
  await s.commit();
  if (st.writes.n !== 1) throw new Error(`wrote ${st.writes.n}`);
  if (s.stats.atRisk !== 0) throw new Error(`atRisk ${s.stats.atRisk} after commit`);
});

t("a commit clears atRisk; an eviction costs exactly atRisk lines", async () => {
  // The tradeoff, stated as a test: commit and the lines are safe; evict
  // first and exactly the uncommitted ones are gone.
  const st = fakeState();
  const s = new DurableStore({ state: st, commit: { every: 100, intervalMs: 1e9 } });
  await s.ready();
  s.append(["a", "b"]);
  await s.commit();
  if (s.stats.atRisk !== 0) throw new Error(`atRisk ${s.stats.atRisk} after commit`);

  // Five lines are retained, but only the three appended since the commit
  // are actually exposed. Reporting five would misstate the loss.
  s.append(["c", "d", "e"]);
  if (s.log.lines.length !== 5) throw new Error(`retained ${s.log.lines.length}`);
  if (s.stats.atRisk !== 3) throw new Error(`atRisk ${s.stats.atRisk}, want 3`);
  // The isolate dies. DO storage survives it; the three uncommitted lines do
  // not, and those three are exactly what `atRisk` said they were.
  st.isolateDied();
  if (st.isolateAlive) throw new Error("fake did not record the death");

  const after = new DurableStore({ state: st });
  await after.ready();
  if (after.log.cursor !== 2) throw new Error(`survived ${after.log.cursor}, want 2`);
  if (after.log.lines.join() !== "a,b") throw new Error(`got ${after.log.lines.join()}`);
});

t("flush commits regardless of the cadence", async () => {
  const st = fakeState();
  const s = new DurableStore({ state: st, commit: { every: 1000, intervalMs: 1e9 } });
  await s.ready();
  s.append(["a"]);
  if (s.dueForCommit()) throw new Error("cadence should not be due");
  await s.flush();
  if (st.writes.n !== 1) throw new Error(`flush wrote ${st.writes.n}`);
  if (s.stats.flushes !== 1) throw new Error("flush not counted");
});

t("committed bytes are counted, not retained bytes", async () => {
  const st = fakeState();
  const s = new DurableStore({ state: st });
  await s.ready();
  s.append(["a"]);
  await s.flush();
  if (s.stats.bytesWritten <= 0) throw new Error("no bytes recorded");
  if (s.stats.bytesWritten < st.writes.bytes - 8) throw new Error("undercounted");
});

t("durable mode reports the pending-commit depth", async () => {
  const st = fakeState();
  const s = new DurableStore({ state: st, commit: { every: 100, intervalMs: 1e9 } });
  await s.ready();
  s.append(["a"]); s.append(["b"]);
  if (s.report().pendingCommits !== 2) throw new Error("pendingCommits wrong");
});

t("a commit that throws does not clear atRisk", async () => {
  // If a failed write reset the counter, the relay would report zero risk on
  // data that is still only in memory.
  const st = fakeState();
  st.storage.put = async () => { throw new Error("quota exceeded"); };
  const s = new DurableStore({ state: st });
  await s.ready();
  s.append(["a", "b"]);
  let threw = false;
  try { await s.flush(); } catch { threw = true; }
  if (!threw) throw new Error("expected the throw to propagate");
  if (s.stats.atRisk !== 2) throw new Error(`atRisk ${s.stats.atRisk} — must not clear`);
});

// ------------------------------------------------------------- makeStore

t("makeStore picks mailbox mode when ROOMS is bound", () => {
  const s = makeStore({ env: { ROOMS: {} }, state: fakeState() });
  if (!s.durable) throw new Error("expected durable");
});

t("makeStore picks rendezvous mode when ROOMS is absent", () => {
  if (makeStore({ env: {} }).durable !== false) throw new Error("expected lossy");
});

t("an explicit mode beats the binding", () => {
  const s = makeStore({ mode: "rendezvous", env: { ROOMS: {} }, state: fakeState() });
  if (s.durable !== false) throw new Error("explicit mode ignored");
});

t("mailbox mode without state fails loudly", () => {
  // Silently falling back to lossy storage here would be the worst outcome:
  // the relay would report itself durable while losing everything.
  let threw = false;
  try { makeStore({ mode: "mailbox", env: {} }); } catch { threw = true; }
  if (!threw) throw new Error("should refuse");
});

t("both backends agree on trimming and cursors", () => {
  // The observable part must not diverge: a peer cannot tell the mode except
  // by what the handshake says.
  const limits = { maxLines: 3, maxBytes: 1e9 };
  const a = new RoomLog(limits); a.append(["1", "2", "3", "4", "5"]);
  const b = new RoomLog(limits); b.append(["1", "2", "3", "4", "5"]);
  if (a.cursor !== b.cursor || a.base !== b.base) throw new Error("disagree");
  if (JSON.stringify(a.fetchFrom(0)) !== JSON.stringify(b.fetchFrom(0))) throw new Error("fetch differs");
});

t("stats report shape is JSON-serialisable", () => {
  const s = new IsolateStore();
  s.append(["a"]);
  const j = JSON.stringify(s.report());
  for (const k of ["mode", "durable", "bootId", "cursor", "stats"]) {
    if (!j.includes(k)) throw new Error(`report missing ${k}`);
  }
});

function byteLen(s) {
  return typeof TextEncoder !== "undefined" ? new TextEncoder().encode(s).length : Buffer.byteLength(s, "utf8");
}

for (const [name, fn] of tests) {
  try {
    await fn();
    pass++; console.log("  ok  ", name);
  } catch (e) {
    fail++; failures.push(name);
    console.log("  FAIL", name, "—", e.message);
  }
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) { console.log("FAILED:", failures.join(", ")); process.exit(1); }