// Two devices, one relay: the cross-device join that used to fail.
//
// This is the case a second tab of the same browser never exercised.  There is
// no `BroadcastChannel` in Node, so the only thing that can carry a line here
// is the relay — exactly the situation of a phone and a laptop.  The relay is
// the real one, `server/relay.mjs`.
//
//   node web/join-test.mjs

import { createServer, CONFIG, Rooms } from "../server/relay.mjs";
import { rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import * as N from "./kant-net.mjs";
import * as F from "./kant-flow.mjs";

let checks = 0;
const fail = [];
const ok = (name, cond) => { checks += 1; if (!cond) fail.push(name); };
const eq = (name, got, want) =>
  ok(`${name} (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`, got === want);

const cfg = {
  origin: "https://kant.cicada71.net/",
  caption: "kant-zk-pastebin",
  picture: "./kant-logo.svg",
  alt: "the Kant pastebin logo",
};

// Its own pass database, in tmpdir, for the reason web/net-test.mjs gives:
// `passDb` defaults to /var/lib/kant-zk/passes.sqlite, which is production
// state. `createServer` opens that store eagerly and every POST writes a
// `peer_posts` row, so this suite was appending its own lines to the live
// relay's rate-limit ledger — measured at five rows per run, on a database that
// also belongs to whatever is deployed on this machine. The rows are pruned
// only once the 10-minute window passes, so a test run leaves state behind that
// outlives it.
const passDb = join(tmpdir(), `kant-join-test-${process.pid}.sqlite`);
const relayCfg = { ...CONFIG, port: 0, host: "127.0.0.1", staticDir: "", passDb };
const server = createServer(relayCfg, new Rooms(relayCfg));

await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}`;

try {
  // The relay says it is there — which is what the share screen now shows.
  const health = await (await fetch(`${base}/health`)).json();
  ok("the relay answers /health", health.ok === true);

  // Device one: the host.  The relay comes from the configuration, not from
  // `location.origin`, and it goes into the invitation absolutely.
  const host = new N.KantNode({ peer: "peer-host", relay: base });
  host.createRoom(base);
  const link = F.inviteUrl(cfg, N.invite(host.relayBase, host.secret, host.self, host.addrs));

  ok("the link carries the page, not the bare code", link.startsWith(cfg.origin + "#"));
  ok("the invitation carries the relay absolutely",
    N.parseInviteUrl(link).relay === base);

  // Device two: the guest, who pastes the whole message their friend sent.
  const pasted = `hey — come in here: ${link} .\nsee you in a sec\n`;
  const found = F.findInvite(pasted);
  ok("the guest's messy paste yields an invitation", found !== null);

  const guest = new N.KantNode({ peer: "peer-guest" });
  const joined = guest.joinInvite(N.copyInvite(found));
  ok("the guest joins", joined !== null);
  eq("both devices are in the same room", guest.room, host.room);
  eq("the guest picked the relay out of the link", guest.relayBase, base);

  // Nothing but the relay is available: no BroadcastChannel, no WebRTC.
  ok("no same-browser bus is in play", host.bus === null && guest.bus === null);
  ok("no direct peer channels are in play", host.mesh === null && guest.mesh === null);

  await host.announceSelf();
  await guest.announceSelf();
  await host.say("hello from the laptop");
  await guest.pollOnce();
  eq("the guest sees the host's line", guest.view().length, 1);
  eq("...and it is the right line", N.msgText(guest.view()[0]), "hello from the laptop");

  await guest.say("hello from the phone");
  await host.pollOnce();
  eq("the host sees the guest's line", host.view().length, 2);
  ok("...and knows about the guest",
    host.peers().some((p) => p && p.peer === "peer-guest"));

  // ---- an invitation that names a relay which does not answer ----
  //
  // The failure this covers is silent and was live: an invite minted while
  // the deployment named a dead relay kept sending joiners to it, even though
  // the page was served by a working relay holding the same room. The banner
  // read healthy (it describes the serving relay), the join reported success
  // (the room id is derived locally), and every actual exchange 504'd.
  const stale = new N.KantNode({ peer: "peer-stale" });
  stale.joinInvite(N.copyInvite(N.invite("http://127.0.0.1:1", host.secret, "peer-host", [])));

  // Before settling, it is pointed at the dead relay — the bug.
  eq("an unprobed invite points at the dead relay", stale.relayBase, "http://127.0.0.1:1");

  const dropped = await stale.settleRelay({ fallback: "", timeoutMs: 700 });
  ok("with no fallback there is nowhere to go", dropped.fellBack === false);
  eq("…so the dead relay is kept", stale.relayBase, "http://127.0.0.1:1");

  const settled = await stale.settleRelay({ fallback: base, timeoutMs: 700 });
  ok("a dead invite relay falls back to the serving one", settled.fellBack === true);
  eq("…which is now the relay in use", stale.relayBase, base);
  eq("…and the client was rebuilt for it", stale.client?.base, base);
  ok("…and the log says so loudly",
    stale.log.events.some((e) => e.level === "error" && /did not answer/.test(e.text)));
  ok("…naming the relay it gave up on",
    stale.log.events.some((e) => e.level === "error" && e.detail === "http://127.0.0.1:1"));

  // Same room, working relay: the fallback must actually carry a line, or the
  // fallback is worse than useless — it silently puts people in a dead room.
  await stale.say("hello from the stale invite");
  await host.pollOnce();
  // `body` is a byte array, so this needs `msgText` — as the checks above do.
  ok("the line crosses after falling back",
    host.view().some((l) => l && N.msgText(l) === "hello from the stale invite"));

  // A relay that DOES answer must be kept: this is the case the relay field
  // exists for — two peers on different relays, where only the invite knows.
  const live = new N.KantNode({ peer: "peer-live" });
  live.joinInvite(N.copyInvite(N.invite(base, host.secret, "peer-host", [])));
  const kept = await live.settleRelay({ fallback: "http://127.0.0.1:1", timeoutMs: 700 });
  ok("a working invite relay is not overridden", kept.fellBack === false);
  eq("…it is still the one in the invite", live.relayBase, base);

  // The same relay twice is not a fallback at all; nothing is probed.
  const same = new N.KantNode({ peer: "peer-same", relay: base });
  same.joinInvite(N.copyInvite(N.invite(base, host.secret, "peer-host", [])));
  const noop = await same.settleRelay({ fallback: base });
  eq("naming the fallback as the fallback is a no-op", noop.fellBack, false);
  eq("…and the relay is untouched", same.relayBase, base);

  // No relay in the invite, and none to fall back to: same-browser only.
  const none = new N.KantNode({ peer: "peer-none" });
  none.joinInvite(N.copyInvite(N.invite("", host.secret, "peer-host", [])));
  const noneRes = await none.settleRelay({});
  ok("an invite with no relay and no fallback goes nowhere", noneRes.fellBack === false);
  eq("…and has no client", none.client, null);

  // A relay that is not there must fail visibly rather than silently: the
  // client keeps working, but nothing crosses.
  const lonely = new N.KantNode({ peer: "peer-lonely", relay: "http://127.0.0.1:1" });
  lonely.joinInvite(N.copyInvite(found));
  lonely.relayBase = "http://127.0.0.1:1";
  lonely.client = new N.RelayClient("http://127.0.0.1:1");
  let threw = false;
  await lonely.pollOnce().catch(() => { threw = true; });
  ok("an unreachable relay is an error the client can see", threw);
} finally {
  server.close();
  server.closeAllConnections?.();
  // The store holds the handle, so the file goes after the server is closed.
  // -wal and -shm are SQLite's own and are removed with it.
  for (const suffix of ["", "-wal", "-shm"]) rmSync(`${passDb}${suffix}`, { force: true });
}

console.log(`${checks - fail.length}/${checks} checks passed`);
if (fail.length) {
  for (const f of fail) console.error(`FAIL: ${f}`);
  process.exit(1);
}
