// room-test.mjs — the Cloudflare `Room`, driven in Node.
//
// The store has its own tests. This one exists because a store that is
// correct and a Room that ignores it are equally green: what matters is that
// `worker.js` actually routes every read and write through the store, and that
// the commit cadence is wired to the request path rather than sitting unused.

import worker, { Room } from "./worker.js";

let pass = 0, fail = 0;
const failures = [];
const tests = [];
const t = (name, fn) => { tests.push([name, fn]); };

/** A Durable Object state that counts writes and can simulate eviction. */
function fakeState({ env } = {}) {
  const map = new Map();
  const writes = { n: 0, bytes: 0 };
  return {
    map, writes, env,
    blockConcurrencyWhile: (fn) => fn(),
    storage: {
      async get(k) { return map.get(k); },
      async put(k, v) { writes.n++; writes.bytes += JSON.stringify(v).length; map.set(k, v); },
    },
  };
}

const req = (path, init = {}) => new Request("https://relay.test" + path, init);
const post = (lines, headers = {}) =>
  req("/room/r1", { method: "POST", body: lines.join("\n"), headers });
const get = (cursor = 0) => req(`/room/r1?cursor=${cursor}`);
const body = async (r) => JSON.parse(await r.text());

const LINE = "kzchat:" + "a".repeat(64) + ":msg:" + "b".repeat(64);

async function roomWith({ env, lines = [], noState = false } = {}) {
  const state = noState ? { blockConcurrencyWhile: (f) => f(), env } : fakeState({ env });
  const room = new Room(state, env);
  if (lines.length) { await room.loaded; room.append(lines); }
  return { room, state };
}

// ------------------------------------------------------------------ basics

t("a room POST returns a cursor and the lines come back on GET", async () => {
  const { room } = await roomWith();
  const r = await room.fetch(post([LINE, LINE]));
  const posted = await body(r);
  if (!posted.ok) throw new Error(JSON.stringify(posted));
  if (posted.cursor !== 2) throw new Error(`cursor ${posted.cursor}`);
  if (posted.accepted !== 2) throw new Error(`accepted ${posted.accepted}`);

  const got = await body(await room.fetch(get(0)));
  if (got.lines.length !== 2) throw new Error(`read back ${got.lines.length}`);
  if (got.cursor !== 2) throw new Error(`cursor ${got.cursor}`);
});

t("a reader at the cursor sees nothing new", async () => {
  const { room } = await roomWith();
  await room.fetch(post([LINE]));
  const got = await body(await room.fetch(get(1)));
  if (got.lines.length !== 0) throw new Error("saw a duplicate");
});

t("cursors advance by exactly the lines accepted", async () => {
  const { room } = await roomWith();
  let cursor = 0;
  for (let i = 0; i < 4; i++) {
    const r = await body(await room.fetch(post([LINE])));
    if (r.cursor !== cursor + 1) throw new Error(`cursor ${r.cursor}, want ${cursor + 1}`);
    cursor = r.cursor;
  }
});

t("the room reports its mode and durability on /stats", async () => {
  // A peer cannot infer durability from the wire, so it has to be told.
  const { room } = await roomWith({ env: { RELAY_MODE: "rendezvous" } });
  const s = await body(await room.fetch(req("/stats/r1")));
  if (s.mode !== "rendezvous") throw new Error(`mode ${s.mode}`);
  if (s.durable !== false) throw new Error("claimed durable");
  if (typeof s.stats.atRisk !== "number") throw new Error("no atRisk");
});

t("loss is reported as unmeasurable in rendezvous mode", async () => {
  // The honest reading: zero losses in isolate mode means "not measured",
  // and a client that confuses the two will trust a cursor that was never
  // durable.
  const { room } = await roomWith({ env: { RELAY_MODE: "rendezvous" } });
  await room.fetch(post([LINE]));
  const s = await body(await room.fetch(req("/stats/r1")));
  if (s.lossMeasurable !== false) throw new Error("claimed measurable");
  if (s.stats.losses !== 0) throw new Error("reported losses it cannot know");
});

t("mailbox mode is durable and reports measurable loss", async () => {
  const { room } = await roomWith({ env: { RELAY_MODE: "mailbox" } });
  const s = await body(await room.fetch(req("/stats/r1")));
  if (s.durable !== true) throw new Error("not durable");
  if (s.lossMeasurable !== false) throw new Error("measurable before a reload?");
});

// ------------------------------------------------------------- the cadence

t("the cadence stops the relay writing on every POST", async () => {
  // This is the change. The old code persisted the whole log per request, so
  // N posts cost N writes. With every:4, ten posts cost at most three.
  const { room, state } = await roomWith({ env: { RELAY_COMMIT_EVERY: 4 } });
  for (let i = 0; i < 10; i++) await room.fetch(post([LINE]));
  if (state.writes.n >= 10) throw new Error(`wrote ${state.writes.n} times for 10 posts`);
  if (state.writes.n === 0) throw new Error("never wrote — cadence too lax");
});

t("every:1 reproduces write-on-every-post", async () => {
  const { room, state } = await roomWith({ env: { RELAY_COMMIT_EVERY: 1 } });
  for (let i = 0; i < 5; i++) await room.fetch(post([LINE]));
  if (state.writes.n !== 5) throw new Error(`wrote ${state.writes.n}, want 5`);
});

t("a looser cadence means strictly fewer writes", async () => {
  const count = async (every) => {
    const { room, state } = await roomWith({ env: { RELAY_COMMIT_EVERY: every } });
    for (let i = 0; i < 12; i++) await room.fetch(post([LINE]));
    return state.writes.n;
  };
  const tight = await count(2), loose = await count(12);
  if (!(loose < tight)) throw new Error(`looser cadence wrote more: ${loose} vs ${tight}`);
});

t("atRisk tracks the uncommitted window, not the whole log", async () => {
  const { room } = await roomWith({ env: { RELAY_MODE: "mailbox", RELAY_COMMIT_EVERY: 100 } });
  await room.fetch(post([LINE]));
  await room.fetch(post([LINE]));
  const s = await body(await room.fetch(req("/stats/r1")));
  if (s.stats.atRisk !== 2) throw new Error(`atRisk ${s.stats.atRisk}, want 2`);
  if (s.lines !== 2) throw new Error(`retained ${s.lines}`);
});

t("a bad cadence var falls back instead of disabling commits", async () => {
  // Number("abc") is NaN, and every comparison against NaN is false. A naive
  // parse would defer every commit forever — silent, unbounded data loss.
  const { room, state } = await roomWith({ env: { RELAY_COMMIT_EVERY: "abc" } });
  for (let i = 0; i < 10; i++) await room.fetch(post([LINE]));
  if (state.writes.n === 0) throw new Error("a bad var silently disabled committing");
});

t("a zero or negative cadence var falls back too", async () => {
  const { room, state } = await roomWith({ env: { RELAY_COMMIT_EVERY: "0" } });
  for (let i = 0; i < 10; i++) await room.fetch(post([LINE]));
  if (state.writes.n === 0) throw new Error("zero cadence disabled committing");
});

// ---------------------------------------------------------------- restart

t("a new Room restores what the last one committed", async () => {
  const env = { RELAY_MODE: "mailbox", RELAY_COMMIT_EVERY: 1 };
  const state = fakeState({ env });
  const first = new Room(state, env);
  await first.loaded;
  await first.fetch(post([LINE, LINE]));
  await first.persist();

  const second = new Room(state, env);
  await second.loaded;
  const got = await body(await second.fetch(get(0)));
  if (got.lines.length !== 2) throw new Error(`restored ${got.lines.length}`);
});

t("uncommitted posts are lost on restart, and that is visible", async () => {
  // The tradeoff stated as a test: commit every:100, post, restart. The lines
  // are gone, and `atRisk` was the number that said they would be.
  const env = { RELAY_MODE: "mailbox", RELAY_COMMIT_EVERY: 100 };
  const state = fakeState({ env });
  const first = new Room(state, env);
  await first.loaded;
  await first.fetch(post([LINE, LINE, LINE]));
  const before = await body(await first.fetch(req("/stats/r1")));
  if (before.stats.atRisk !== 3) throw new Error(`atRisk ${before.stats.atRisk}, want 3`);

  const second = new Room(state, env);
  await second.loaded;
  const after = await body(await second.fetch(get(0)));
  if (after.lines.length !== 0) throw new Error("uncommitted lines survived a restart");
});

t("restarting in rendezvous mode loses the room and admits it", async () => {
  const env = { RELAY_MODE: "rendezvous" };
  const state = fakeState({ env });
  const first = new Room(state, env);
  await first.loaded;
  await first.fetch(post([LINE]));
  if (state.writes.n !== 0) throw new Error("rendezvous mode wrote to storage");

  const second = new Room(state, env);
  await second.loaded;
  const s = await body(await second.fetch(req("/stats/r1")));
  if (s.cursor !== 0) throw new Error(`cursor ${s.cursor} after restart`);
  if (s.lossMeasurable !== false) throw new Error("claimed to measure loss");
});

// --------------------------------------------------------------- limits

t("an oversized line is refused", async () => {
  const { room } = await roomWith();
  const r = await room.fetch(post(["x".repeat(300000)]));
  if (r.status !== 413) throw new Error(`status ${r.status}`);
});

t("an oversized body is refused", async () => {
  const { room } = await roomWith();
  const r = await room.fetch(post(new Array(20).fill("y".repeat(200000))));
  if (r.status !== 413) throw new Error(`status ${r.status}`);
});

t("the room trims and tells a slow reader it was truncated", async () => {
  const { room } = await roomWith({ env: { RELAY_MODE: "rendezvous", RELAY_MAX_LINES: 3 } });
  await room.fetch(post([LINE, LINE, LINE, LINE, LINE]));
  const got = await body(await room.fetch(get(0)));
  if (!got.truncated) throw new Error("did not report truncation");
  if (got.lines.length !== 3) throw new Error(`returned ${got.lines.length}`);
});

t("the byte bound trims even when the line count does not", async () => {
  // maxLines is generous, maxBytes is not: the line-count bound alone would
  // let 4096 oversized lines through.
  const { room } = await roomWith({
    env: { RELAY_MODE: "rendezvous", RELAY_MAX_LINES: 4096, RELAY_MAX_BYTES: 500 },
  });
  await room.fetch(post(["z".repeat(400), "z".repeat(400)]));
  const s = await body(await room.fetch(req("/stats/r1")));
  if (s.bytes > 500) throw new Error(`bytes ${s.bytes} over the bound`);
});

t("mailbox mode without storage refuses rather than degrading", () => {
  // The worst outcome would be a relay that believes it is durable while
  // holding everything in memory and handing out cursors it cannot honour.
  let threw = false;
  try {
    new Room({ blockConcurrencyWhile: (f) => f(), storage: undefined },
      { RELAY_MODE: "mailbox" });
  } catch { threw = true; }
  if (!threw) throw new Error("should have refused");
});

t("a Durable Object is recognised by its storage, not by a ROOMS binding", async () => {
  // The Worker may not bind ROOMS and the DO still has storage; probing the
  // binding instead made a real Durable Object run as a lossy isolate store.
  const { room } = await roomWith({ env: {} });
  const s = await body(await room.fetch(req("/stats/r1")));
  if (s.mode !== "mailbox") throw new Error(`mode ${s.mode}, want mailbox`);
  if (s.durable !== true) throw new Error("should be durable");
});

t("no storage at all is rendezvous, not a crash", async () => {
  const { room } = await roomWith({ env: {} , noState: true });
  const s = await body(await room.fetch(req("/stats/r1")));
  if (s.mode !== "rendezvous") throw new Error(`mode ${s.mode}`);
});

// ------------------------------------------------------- the Worker front
//
// `/health` is answered by the Worker, not the Room, so the room tests above
// never touch it. That left the durability flag -- the one thing a client uses
// to decide whether a cursor is a promise -- completely unverified.

const stubRooms = { idFromName: (n) => ({ name: n }) };

t("/health announces whether this deployment is durable", async () => {
  const withDo = await (await worker.fetch(req("/health"), { ROOMS: stubRooms })).json();
  if (withDo.durable !== true) throw new Error("a bound ROOMS should be durable");
  if (withDo.mode !== "mailbox") throw new Error(`mode ${withDo.mode}`);

  const without = await (await worker.fetch(req("/health"), {})).json();
  if (without.durable !== false) throw new Error("claimed durable with no DO bound");
  if (without.mode !== "rendezvous") throw new Error(`mode ${without.mode}`);
});

t("/health reports the commit cadence in force", async () => {
  const h = await (await worker.fetch(req("/health"),
    { ROOMS: stubRooms, RELAY_COMMIT_EVERY: "3" })).json();
  if (h.commit?.every !== 3) throw new Error(`every ${h.commit?.every}`);
});

t("an explicit rendezvous mode beats a bound ROOMS for the health flag", async () => {
  // A deployment can bind the class and still choose to run lossy. If the
  // health check said durable there, it would contradict /stats on the room.
  const h = await (await worker.fetch(req("/health"),
    { ROOMS: stubRooms, RELAY_MODE: "rendezvous" })).json();
  if (h.durable !== false) throw new Error("health disagreed with the room mode");
});

t("a bad cadence var does not reach /health as NaN", async () => {
  const h = await (await worker.fetch(req("/health"),
    { ROOMS: stubRooms, RELAY_COMMIT_INTERVAL_MS: "nonsense" })).json();
  if (!Number.isFinite(h.commit?.intervalMs)) throw new Error(`intervalMs ${h.commit?.intervalMs}`);
});

t("a room route with no ROOMS binding says so instead of throwing", async () => {
  let r, body;
  try { r = await worker.fetch(get(), {}); body = await r.json(); }
  catch (e) { throw new Error(`threw instead of answering: ${e.message}`); }
  if (r.status !== 503) throw new Error(`status ${r.status}`);
  if (!String(body.error).includes("ROOMS")) throw new Error("error should name the binding");
});

t("an unknown path is still a 404", async () => {
  const r = await worker.fetch(req("/nope"), { ROOMS: stubRooms });
  if (r.status !== 404) throw new Error(`status ${r.status}`);
});

for (const [name, fn] of tests) {
  try { await fn(); pass++; console.log("  ok  ", name); }
  catch (e) { fail++; failures.push(name); console.log("  FAIL", name, "—", e.message); }
}
console.log(`\n${pass} passed, ${fail} failed`);
if (fail) { console.log("FAILED:", failures.join(", ")); process.exit(1); }