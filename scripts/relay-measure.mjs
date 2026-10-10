// relay-measure.mjs — measure the relay fleet, and the commit cadence.
//
// Two jobs, because "reduce DO time" needs a number before it needs a config:
//
//   --fleet     poll the known deployments and report what each claims about
//               its own storage. Cheap, no credentials, tells you which of the
//               two modes each worker is actually running.
//
//   --cadence   drive the Room against a fake Durable Object and count what
//               each commit cadence costs. This is the experiment that turns
//               the cadence from a guess into a curve: fewer writes, but a
//               wider window of uncommitted lines.
//
//   --room URL  poll a deployed worker's /stats, if it has one.
//
// A worker built before the storage split answers /health without `mode` or
// `durable`, and /stats with a 404. The census reports that as `unknown`
// rather than guessing, because "this deployment might be lossy" and "this
// deployment is lossy" are different sentences.

import { Room } from "../server/worker.js";

const FLEET = [
  { name: "kant-zk-relay-wasm", url: "https://kant-zk-relay-wasm.jmikedupont2.workers.dev", owner: "pastebin" },
  { name: "otc-desk-relay-v2", url: "https://otc-desk-relay-v2.jmikedupont2.workers.dev", owner: "lean-worker" },
  { name: "otc-desk-relay-mailbox", url: "https://otc-desk-relay-mailbox.jmikedupont2.workers.dev", owner: "lean-worker" },
  { name: "kant-relay-v1", url: "https://kant-relay-v1.mike.workers.dev", owner: "relay-v1" },
  { name: "kant-relay-v1-dev", url: "https://kant-relay-v1-dev.mike.workers.dev", owner: "relay-v1" },
];

/**
 * What the experiment actually did, as opposed to what it was asked to do.
 *
 * Exported because the tool got this wrong once already: it summarised "100
 * POSTs" when the rate limiter had accepted 10. The numbers were real, the
 * sentence about them was not, and no test caught it -- the test asserted on
 * the counters rather than on what gets said out loud.
 */
export function summarizeCadence(rows, requested) {
  const accepted = rows.length ? rows[0].appends : 0;
  return {
    accepted,
    requested,
    short: accepted !== requested,
    savingVsBaseline: rows.length ? Math.round((1 - rows[3].writes / rows[0].writes) * 100) : 0,
  };
}

/**
 * Read a worker's self-description.
 *
 * Exported and pure so the one judgment that matters can be tested without a
 * network: a worker that omits `mode` is UNKNOWN, not false. Collapsing those
 * two is how a lossy deployment gets reported as a safe one -- the tool exists
 * to prevent exactly that, so it had better not make the mistake itself.
 */
export function classifyHealth(json, status = 200) {
  if (status !== 200 || !json || typeof json !== "object") {
    return { reachable: false, mode: "unknown", durable: null, version: null, reachableStatus: status };
  }
  return {
    reachable: true,
    // Absent field stays unknown. Only an explicit false is false.
    mode: typeof json.mode === "string" ? json.mode : "unknown",
    durable: typeof json.durable === "boolean" ? json.durable : null,
    // A worker may report durability without naming a mode; do not invent one.
    version: typeof json.version === "string" ? json.version : null,
    reachableStatus: status,
  };
}

const get = async (url, ms = 8000) => {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), ms);
  try {
    const r = await fetch(url, { signal: ac.signal });
    const text = await r.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* not json: a CF error page */ }
    return { status: r.status, json, text: text.slice(0, 120) };
  } catch (e) {
    return { status: 0, json: null, text: String(e?.message ?? e).slice(0, 80) };
  } finally {
    clearTimeout(timer);
  }
};

const pad = (s, n) => String(s ?? "-").padEnd(n);
const padL = (s, n) => String(s ?? "-").padStart(n);

// ------------------------------------------------------------------ fleet

export async function fleet() {
  console.log("Polling the fleet. A worker without `mode` predates the storage split.\n");
  console.log(pad("worker", 24), pad("owner", 12), pad("status", 7), pad("mode", 12),
    pad("durable", 9), "version");
  console.log("-".repeat(88));

  const rows = [];
  for (const w of FLEET) {
    const r = await get(`${w.url}/health`);
    const c = classifyHealth(r.json, r.status);
    const j = r.json ?? {};
    const mode = c.mode;
    const durable = c.durable === null ? "unknown" : String(c.durable);
    rows.push({ ...w, status: r.status, mode, durable, version: j.version ?? "-" });
    console.log(pad(w.name, 24), pad(w.owner, 12), pad(r.status || "ERR", 7),
      pad(mode, 12), pad(durable, 9), j.version ?? "-");
    if (r.status !== 200) console.log("   ", r.text);
  }

  const unknown = rows.filter((x) => x.mode === "unknown").length;
  console.log();
  console.log(`${rows.length - unknown}/${rows.length} report their storage mode.`);
  if (unknown) {
    console.log("Those answering `unknown` were built before the storage split, so a");
    console.log("cursor from them is a promise nobody has checked. Treat as rendezvous");
    console.log("until deployed.");
  }
  return rows;
}

// ---------------------------------------------------------------- cadence

/** A Durable Object state that counts writes, for the experiment. */
function fakeState() {
  const map = new Map();
  const writes = { n: 0, bytes: 0 };
  return {
    map, writes,
    blockConcurrencyWhile: (f) => f(),
    storage: {
      async get(k) { return map.get(k); },
      async put(k, v) { writes.n++; writes.bytes += JSON.stringify(v).length; map.set(k, v); },
    },
  };
}

/**
 * One kzchat line.
 *
 * The sender field (part 2) varies per line because the relay's passless rate
 * limit is *per sender*: 10 posts per 10 minutes. Posting as one sender caps
 * the experiment at 10 requests, and a summary that then says "100 POSTs"
 * would be reporting work that never happened. A distinct sender per post is
 * what a room with several peers actually looks like.
 */
const hexAscii = (s) => Buffer.from(s, "utf8").toString("hex");
const TAG_CHAT = hexAscii("kzchat");

const line = (i) => {
  const sender = `peer${String(i).padStart(6, "0")}`;
  // Part 0 must be the HEX of "kzchat", not the literal: `senderOfLine`
  // hex-decodes it and compares to the ASCII. A literal tag decodes to null,
  // the sender comes back unidentified, and every post lands in one shared
  // "anonymous" bucket -- which is how a malformed client ends up rate
  // limited as if it were everybody.
  return [TAG_CHAT, hexAscii("room1"), hexAscii(sender), "00", hexAscii("m" + i)].join(":");
};

export async function cadence({ posts = 100, sizes = 1 } = {}) {
  console.log(`Commit cadence experiment: ${posts} POSTs of ${sizes} line(s) each,`);
  console.log("driving the real Room against a fake Durable Object.\n");

  const rows = [];
  for (const every of [1, 2, 4, 8, 16, 32, 64]) {
    const state = fakeState();
    const env = { RELAY_MODE: "mailbox", RELAY_COMMIT_EVERY: String(every) };
    const room = new Room(state, env);
    await room.loaded;

    let peakAtRisk = 0;
    for (let i = 0; i < posts; i++) {
      const batch = Array.from({ length: sizes }, (_, k) => line(i * sizes + k));
      await room.fetch(new Request("https://x.test/room/r", { method: "POST", body: batch.join("\n") }));
      peakAtRisk = Math.max(peakAtRisk, room.store.stats.atRisk);
    }
    await room.store.flush();

    const s = await (await room.fetch(new Request("https://x.test/stats/r"))).json();
    rows.push({
      every,
      appends: s.stats.appends,
      commits: s.stats.commits,
      deferred: s.stats.commitsDeferred,
      writes: state.writes.n,
      writeBytes: state.writes.bytes,
      peakAtRisk,
    });
  }

  const base = rows[0];
  console.log(pad("every", 7), padL("commits", 9), padL("writes saved", 13),
    padL("write bytes", 12), padL("peak atRisk", 13), "exposure cost");
  console.log("-".repeat(74));
  for (const r of rows) {
    const saved = base.writes - r.writes;
    const pct = Math.round((saved / base.writes) * 100);
    console.log(pad(r.every, 7), padL(r.commits, 9), padL(`${saved} (${pct}%)`, 13),
      padL(r.writeBytes, 12), padL(r.peakAtRisk, 13),
      r.peakAtRisk === 0 ? "none" : `${r.peakAtRisk} lines`);
  }

  console.log();
  const summary = summarizeCadence(rows, posts);
  const actuallyPosted = summary.accepted;
  if (summary.short) {
    console.log(`WARNING: only ${actuallyPosted} of ${posts} POSTs were accepted.`);
    console.log("The rate limiter refused the rest, so these numbers understate cost.");
  } else {
    console.log(`Baseline (every:1) is what the relay did before this change: ${base.writes} writes,`);
    console.log(`${base.writeBytes.toLocaleString()} bytes, for ${actuallyPosted} POSTs.`);
  }
  const e8 = rows.find((r) => r.every === 8);
  if (e8) {
    console.log(`every:8 writes ${e8.writes} times (${Math.round((1 - e8.writes / base.writes) * 100)}% fewer)`);
    console.log(`and leaves at most ${e8.peakAtRisk} lines uncommitted at any moment.`);
  }
  console.log();
  console.log("That last column is the whole tradeoff: writes bought with an exposure");
  console.log("window. /stats reports it live, so the cadence can be set against the");
  console.log("room's real traffic rather than a guess.");
  console.log();
  console.log("Read this next to the rate limiter before acting on it: the relay refuses");
  console.log("10 passless posts per sender per 10 minutes. That caps requests long");
  console.log("before the cadence saves anything, so DO write cost is second-order next");
  console.log("to admission control. The cadence matters when a room has many senders,");
  console.log("or when passes raise the ceiling.");
  return rows;
}

// ------------------------------------------------------------------- room

async function room(url, roomName) {
  const h = await get(`${url}/health`);
  const s = await get(`${url}/stats/${roomName}`);
  console.log(`${url}/health`);
  console.log("  ", h.json ? JSON.stringify(h.json) : h.text);
  console.log(`${url}/stats/${roomName}`);
  console.log("  ", s.json ? JSON.stringify(s.json, null, 2).split("\n").join("\n   ") : s.text);
}

// ------------------------------------------------------------------- main

const argv = process.argv.slice(2);
const which = argv.find((a) => a.startsWith("--")) ?? "--fleet";

if (which === "--fleet") await fleet();
else if (which === "--cadence") await cadence({
  posts: Number(argv[argv.indexOf("--cadence") + 1]) || 100,
});
else if (which === "--room") await room(argv[1 + argv.indexOf("--room")], argv[2 + argv.indexOf("--room")]);
else {
  console.log("usage: relay-measure.mjs [--fleet | --cadence [posts] | --room <url> <room>]");
  process.exit(1);
}