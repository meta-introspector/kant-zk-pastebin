// diag-test.mjs — the diagnostics module against vectors computed by Lean,
// plus two same-machine connection scenarios driven through the real relay.
//
//   node web/diag-test.mjs

import * as D from "./kant-diag.mjs";
import * as N from "./kant-net.mjs";
import { spawn } from "node:child_process";
import { readFileSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

let pass = 0, fail = 0;
const ok = (name, cond, extra = "") => {
  if (cond) { pass += 1; }
  else { fail += 1; console.error(`FAIL ${name}${extra ? `\n  ${extra}` : ""}`); }
};
const eq = (name, got, want) =>
  ok(name, got === want, `got  ${JSON.stringify(got)}\n  want ${JSON.stringify(want)}`);

// ---------------------------------------------- golden vectors (from Lean)

const e1 = D.event(0, 12, "info", "probe", "probing relay", "http://localhost:8787/health");
const e2 = D.event(1, 340, "error", "relay", "relay post failed", "status=404");

eq("printEvent e1", D.printEvent(e1),
  "6b7a6c6f67::0c:01:02:70726f62696e672072656c6179:687474703a2f2f6c6f63616c686f73743a383738372f6865616c7468");
eq("printEvent e2", D.printEvent(e2),
  "6b7a6c6f67:01:0154:03:03:72656c617920706f7374206661696c6564:7374617475733d343034");
eq("ref", D.ref("kzinvite-secret"), "5f40d0e7");
eq("ref length", D.ref("room").length, 8);

const report = {
  verdict: "onlyThisBrowser",
  room: D.ref("room"),
  relay: "http://localhost:8787",
  events: [e1, e2],
};
eq("renderReport", D.renderReport(report),
  "6b7a64696167:05:3665373163653336:687474703a2f2f6c6f63616c686f73743a38373837\n" +
  "6b7a6c6f67::0c:01:02:70726f62696e672072656c6179:687474703a2f2f6c6f63616c686f73743a383738372f6865616c7468\n" +
  "6b7a6c6f67:01:0154:03:03:72656c617920706f7374206661696c6564:7374617475733d343034");

for (const [v, text] of Object.entries({
  ok: "ok: you and the other client share a room and a transport",
  noRoom: "no-room: open a room, or paste an invite link",
  roomMismatch: "room-mismatch: the link pasted is not the link that was shown",
  relayDown: "relay-down: the configured relay did not answer; check `relay =` in kant.config",
  onlyThisBrowser:
    "only-this-browser: two separate browsers with no relay between them; serve the page " +
    "with `node server/relay.mjs --static web`, or set `relay =`",
  noTransport: "no-transport: no relay, and no same-browser channel",
})) eq(`explain ${v}`, D.explain(v), text);

// ------------------------------------------------------------ round trips

ok("parseEvent round trip", JSON.stringify(D.parseEvent(D.printEvent(e2))) === JSON.stringify(e2));
ok("parseEvent rejects junk", D.parseEvent("not a log line") === null);
ok("parseEvent rejects another envelope",
  D.parseEvent("6b7a7061737465:00") === null);
ok("parseLog round trip",
  JSON.stringify(D.parseLog(D.renderLog([e1, e2]))) === JSON.stringify([e1, e2]));
eq("parseLog of nothing", JSON.stringify(D.parseLog("")), "[]");
ok("parseReport round trip",
  JSON.stringify(D.parseReport(D.renderReport(report))) === JSON.stringify(report));
ok("findReport in a chat message",
  JSON.stringify(D.findReport(
    `hey, it will not connect for me. here is the run:\n${D.renderReport(report)}\nany ideas?`,
  ).events.length) === "2");
ok("reportText carries the block",
  D.parseReport(D.reportText(report).split(
    "--- machine-readable, paste into the diagnostics page ---\n")[1]) !== null);
ok("reportText is readable", D.reportText(report).includes("relay post failed"));

// ----------------------------------------------------------------- the log

{
  let now = 1000;
  const log = new D.DiagLog({ cap: 4, clock: () => now });
  for (let i = 0; i < 10; i += 1) { now += 5; log.record("info", "relay", `line ${i}`); }
  eq("log is bounded", log.events.length, 4);
  eq("log counts what it dropped", log.dropped, 6);
  eq("log total", log.total, 10);
  eq("newest event kept", log.events[log.events.length - 1].text, "line 9");
  ok("sequence numbers increase",
    log.events.every((e, i) => i === 0 || log.events[i - 1].seq < e.seq));
  eq("sequence numbers are not reused", log.events[3].seq, 9);
  ok("timestamps are relative to the start", log.events[3].ms === 50);
  ok("a run reads back", JSON.stringify(D.parseLog(log.render())) === JSON.stringify(log.events));
}

{
  const log = new D.DiagLog({ cap: 10, clock: () => 0 });
  log.info("relay", "posting into room deadbeefcafe", "room=deadbeefcafe");
  log.info("bus", "another tab answered");
  log.error("relay", "post failed", new Error("boom"));
  eq("errors carry the message", log.events[2].detail, "Error: boom");
  const shared = log.share(["deadbeefcafe"]);
  eq("the secret is withheld", shared.length, 2);
  ok("nothing shared quotes the secret",
    shared.every((e) => !e.text.includes("deadbeefcafe") && !e.detail.includes("deadbeefcafe")));
  ok("nothing else is withheld", shared.some((e) => e.text === "another tab answered"));
  eq("no secrets, nothing withheld", log.share([]).length, 3);
  eq("scrubbed of newlines", D.event(0, 0, "info", "app", "a\nb").text, "a b");
}

// --------------------------------------------------- the connection verdict

const reach = (o) => ({ configured: "", configuredUp: false, origin: "", originIsRelay: false, ...o });
const client = (o) => D.clientOf({ room: "r1", reach: reach(o.reach ?? {}), ...o });

{
  // Two tabs of one browser: no server needed.
  const a = client({ bus: true, browser: 1 });
  const b = client({ bus: true, browser: 1 });
  eq("two tabs are linked", D.diagnose(a, b), "ok");

  // Two browsers, nothing configured, plain static host: the failure.
  const c = client({ bus: true, browser: 2 });
  eq("two browsers with no relay", D.diagnose(a, c), "onlyThisBrowser");
  ok("…and are really not linked", D.linked(a, c) === false);

  // The same two, with the page served by a relay: fixed.
  const selfHosted = { origin: "http://localhost:8787", originIsRelay: true };
  const d = client({ bus: true, browser: 1, reach: selfHosted });
  const e = client({ bus: true, browser: 2, reach: selfHosted });
  eq("self-hosted relay links two browsers", D.diagnose(d, e), "ok");
  eq("effectiveRelay picks the origin", D.effectiveRelay(reach(selfHosted)),
    "http://localhost:8787");
  eq("effectiveRelay never guesses",
    D.effectiveRelay(reach({ origin: "https://static.example", originIsRelay: false })), "");
  eq("a configured relay wins",
    D.effectiveRelay(reach({ configured: "https://relay.example", ...selfHosted })),
    "https://relay.example");

  // A configured relay that is down.
  const down = { configured: "https://relay.example", configuredUp: false };
  eq("relay down", D.diagnose(client({ bus: true, browser: 1, reach: down }),
    client({ bus: true, browser: 2, reach: down })), "relayDown");

  // Different rooms, and no room at all.
  eq("room mismatch", D.diagnose(a, client({ room: "r2", bus: true, browser: 1 })),
    "roomMismatch");
  eq("no room", D.diagnose(client({ room: "" }), a), "noRoom");
  eq("no transport", D.diagnose(client({ bus: false, browser: 1 }),
    client({ bus: false, browser: 2 })), "noTransport");
}

// ------------------------------------------------- a real relay, one machine

const here = path.dirname(fileURLToPath(import.meta.url));
const relayPath = path.join(here, "..", "server", "relay.mjs");

const logFile = path.join(here, ".diag-relay.log");
function startRelay(port) {
  const proc = spawn(process.execPath,
    [relayPath, "--port", String(port), "--static", here, "--log", logFile, "--quiet"],
    { stdio: ["ignore", "pipe", "pipe"] });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("relay did not start")), 8000);
    proc.stdout.on("data", (d) => {
      if (String(d).includes("listening")) { clearTimeout(timer); resolve(proc); }
    });
    proc.on("error", reject);
  });
}

const port = 8801 + Math.floor(Math.random() * 90);
let relay = null;
try { relay = await startRelay(port); } catch (e) { console.error(`(no relay: ${e.message})`); }

if (relay) {
  const base = `http://127.0.0.1:${port}`;

  // The page is served by the relay itself, and nothing is configured:
  // `resolveReachability` must find it.  This is the same-machine fix.
  const log = new D.DiagLog({ cap: 100 });
  const found = await D.resolveReachability({ configured: "", origin: base, log });
  ok("the self-hosting origin is discovered", found.originIsRelay === true);
  eq("…and used", D.effectiveRelay(found), base);
  ok("the probe is in the log", log.events.some((e) => e.area === "probe" && e.level === "info"));

  // The deployment we recommend — `relay.mjs --static web` — must actually
  // hand out the app, the diagnostics page and the module behind it.
  for (const [what, file] of [
    ["the app", "index.html"],
    ["the diagnostics page", "diag.html"],
    ["the diagnostics module", "kant-diag.mjs"],
  ]) {
    const res = await fetch(`${base}/${file}`).catch(() => null);
    ok(`the relay serves ${what}`, !!res && res.ok, res ? `status ${res.status}` : "no answer");
  }

  // A configured relay that is not there is reported, not swallowed.
  const log2 = new D.DiagLog({ cap: 100 });
  const missing = await D.resolveReachability({
    configured: "http://127.0.0.1:1", origin: base, log: log2,
  });
  ok("a dead relay is not usable", D.relayUsable(missing) === false);
  ok("…and says so in the log", log2.events.some((e) => e.level === "error"));

  // A static host that is not a relay: the origin must NOT be used.
  const log3 = new D.DiagLog({ cap: 100 });
  const notRelay = await D.resolveReachability({
    configured: "", origin: `${base}/room`, log: log3,
  });
  ok("a non-relay origin is refused", notRelay.originIsRelay === false);
  eq("…and nothing is used", D.effectiveRelay(notRelay), "");

  // Two clients that share no browser at all — no BroadcastChannel, as in
  // two different browsers on one machine — meet over that relay.
  const mk = (peer) => {
    const node = new N.KantNode({ peer, relay: base, log: new D.DiagLog({ cap: 200 }) });
    return node;
  };
  const alice = mk("alice");
  const invite = alice.createRoom(base);
  alice.connect({ bus: false });
  await alice.announceSelf();

  const bob = mk("bob");
  bob.joinInvite(invite);
  bob.connect({ bus: false });
  await bob.announceSelf();

  await alice.pollOnce();
  await bob.pollOnce();
  await alice.say("hello from the other browser");
  await bob.pollOnce();

  eq("same room", alice.room, bob.room);
  ok("bob sees alice", bob.peers().some((p) => p.peer === "alice"));
  ok("bob hears alice", bob.view().some((m) => N.msgText(m) === "hello from the other browser"));

  const va = D.clientOf({ room: alice.room, reach: found, bus: false, browser: 1 });
  const vb = D.clientOf({ room: bob.room, reach: found, bus: false, browser: 2 });
  eq("the verdict agrees", D.diagnose(va, vb), "ok");

  ok("the traffic is logged", bob.log.events.some((e) => e.area === "relay"));
  ok("the log reads back",
    JSON.stringify(D.parseLog(bob.log.render())) === JSON.stringify(bob.log.events));

  const shared = bob.report({ other: va });
  ok("a report can be shared", D.parseReport(D.renderReport(shared)) !== null);
  ok("the shared report hides the invite",
    !D.renderReport(shared).includes(bob.secretHex ?? "\u0000"));

  // The relay keeps its own log, with rooms reduced to a handle.
  const serverLog = readFileSync(logFile, "utf8");
  ok("the relay logged the traffic", /POST \/room\/[0-9a-f]{8} 200/.test(serverLog));
  ok("...and the polls", /GET \/room\/[0-9a-f]{8}/.test(serverLog));
  ok("...without printing any room in full", !serverLog.includes(alice.room));

  alice.stop(); bob.stop();
  relay.kill();
  rmSync(logFile, { force: true });
}

// ------------------------- polling with no relay must idle, never spin
//
// A poll loop that returns at once and goes straight round again starves
// every timer on the page: the clock stops, nothing redraws, and the log
// fills with the same line thousands of times a second.
{
  const lonely = new N.KantNode({ me: "lonely", log: new D.DiagLog({ cap: 200 }) });
  lonely.createRoom();
  lonely.client = null;
  lonely.startPolling({ interval: 40, maxIdleMs: 400 });

  let ticks = 0;
  const tick = () => { ticks += 1; };
  const timer = setInterval(tick, 20);
  await new Promise((r) => setTimeout(r, 300));
  clearInterval(timer);
  lonely.polling = false;

  ok("the page's timers still run while polling finds no relay", ticks >= 5, `ticks ${ticks}`);
  const idle = lonely.log.events.filter((e) => e.text.includes("nothing to poll"));
  ok("...and the log is not flooded", idle.length === 1, `said it ${idle.length} times`);
  lonely.stop();
}

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
