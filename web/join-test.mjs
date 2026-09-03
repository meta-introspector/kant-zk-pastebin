// Two devices, one relay: the cross-device join that used to fail.
//
// This is the case a second tab of the same browser never exercised.  There is
// no `BroadcastChannel` in Node, so the only thing that can carry a line here
// is the relay — exactly the situation of a phone and a laptop.  The relay is
// the real one, `server/relay.mjs`.
//
//   node web/join-test.mjs

import { createServer, CONFIG, Rooms } from "../server/relay.mjs";
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

const relayCfg = { ...CONFIG, port: 0, host: "127.0.0.1", staticDir: "" };
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
}

console.log(`${checks - fail.length}/${checks} checks passed`);
if (fail.length) {
  for (const f of fail) console.error(`FAIL: ${f}`);
  process.exit(1);
}
