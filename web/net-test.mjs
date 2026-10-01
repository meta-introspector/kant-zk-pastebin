// net-test.mjs — conformance checks for the discovery / chat / relay layer.
//
// Two kinds of check:
//   1. the pure functions of `web/kant-net.mjs` against golden vectors
//      computed by Lean (`RequestProject/Kant/Demo.lean` checks the same
//      strings with `#guard`, so the two sides cannot drift);
//   2. an end-to-end run of the real relay from `server/relay.mjs`: two
//      clients that have never met exchange an invitation, discover each
//      other, chat over HTTP polling and over a WebSocket, and are shown
//      a hostile relay's forged line.
//
// Run:  node web/net-test.mjs

import assert from "node:assert/strict";
import {
  roomOf, invite, copyInvite, pasteInvite, inviteUrl, parseInviteUrl, inviteFitsQr,
  announce, printAnnounce, parseAnnounce, rosterMerge, rosterInsert, rosterKnows,
  rosterBest, acceptPeers, message, msgWitness, printMsg, parseMsg, sayText, msgText,
  accept, receive, transcript, printSignal, parseSignal, Server, KantNode, RelayClient,
} from "./kant-net.mjs";
import { utf8, asciiBytes, envelopeEncode, natToBytesBE } from "./kantzk.mjs";
import { createServer, Rooms, CONFIG } from "../server/relay.mjs";

let checks = 0;
const check = (name, fn) => { fn(); checks += 1; console.log(`  ok  ${name}`); };
const checkAsync = async (name, fn) => { await fn(); checks += 1; console.log(`  ok  ${name}`); };

// -------------------------------------------------- vectors computed by Lean

const SECRET = utf8("kant-zk demo secret");
const ADDRS = [
  { transport: "libp2p", locator: "/dns4/relay.example.org/tcp/443/wss" },
  { transport: "iroh", locator: "irohticket1" },
];
const INVITE = invite("https://relay.example.org", SECRET, "alice", ADDRS);
const ANNOUNCE = announce("alice", 7, ADDRS);

const LEAN = {
  room: "bd71dd50a1ee00eaa91ea3fb701d151f8bc3059f81b1766c51ea8736f88acec1",
  invite:
    "6b7a696e76697465:68747470733a2f2f72656c61792e6578616d706c652e6f7267:6b616e742d7a6b2064656d6f20736563726574:616c696365:032f646e73342f72656c61792e6578616d706c652e6f72672f7463702f3434332f777373:0269726f687469636b657431",
  announce:
    "6b7a70656572:616c696365:07:032f646e73342f72656c61792e6578616d706c652e6f72672f7463702f3434332f777373:0269726f687469636b657431",
  msgWitness: "2493daf48dda511be13a96a953fd10a49a744fc1cff4e209d1435304d28b6602",
  msg:
    "6b7a63686174:62643731646435306131656530306561613931656133666237303164313531663862633330353966383162313736366335316561383733366638386163656331:616c696365:01:68656c6c6f:32343933646166343864646135313162653133613936613935336664313061343961373434666331636666346532303964313433353330346432386236363032",
};

console.log("golden vectors from Lean");

check("roomOf matches Lean", () => assert.equal(roomOf(SECRET), LEAN.room));
check("copyInvite matches Lean", () => assert.equal(copyInvite(INVITE), LEAN.invite));
check("printAnnounce matches Lean", () => assert.equal(printAnnounce(ANNOUNCE), LEAN.announce));

const MSG = message(LEAN.room, "alice", 1, utf8("hello"));
check("msgWitness matches Lean", () => assert.equal(msgWitness(MSG), LEAN.msgWitness));
check("printMsg matches Lean", () => assert.equal(printMsg(MSG), LEAN.msg));

// ------------------------------------------------------------- round trips

console.log("round trips");

check("an invitation survives the QR text", () => {
  const back = pasteInvite(copyInvite(INVITE));
  assert.equal(back.relay, INVITE.relay);
  assert.equal(back.peer, INVITE.peer);
  assert.deepEqual(back.secret, INVITE.secret);
  assert.deepEqual(back.addrs, INVITE.addrs);
});

check("an invitation survives a link", () => {
  const back = parseInviteUrl(inviteUrl("https://kant.example/", INVITE));
  assert.equal(back.relay, INVITE.relay);
  assert.deepEqual(back.addrs, INVITE.addrs);
});

check("both sides of a code compute the same room", () => {
  const back = pasteInvite(copyInvite(INVITE));
  assert.equal(roomOf(back.secret), roomOf(INVITE.secret));
});

check("the invitation fits in one QR code", () => assert.ok(inviteFitsQr(INVITE)));

check("an announcement survives the wire", () => {
  assert.deepEqual(parseAnnounce(printAnnounce(ANNOUNCE)), ANNOUNCE);
});

check("a chat line survives the wire", () => {
  const back = parseMsg(printMsg(MSG));
  assert.equal(back.sender, "alice");
  assert.equal(msgText(back), "hello");
});

check("a signalling line survives the wire", () => {
  const sig = { room: LEAN.room, from: "alice", to: "bob", kind: "offer", payload: '{"a":1}' };
  assert.deepEqual(parseSignal(printSignal(sig)), sig);
});

// ------------------------------------------------------------- forged lines

console.log("what a hostile relay cannot do");

const TAMPERED = envelopeEncode({
  tag: asciiBytes("kzchat"),
  fields: [asciiBytes(MSG.room), asciiBytes(MSG.sender), natToBytesBE(MSG.seq),
           utf8("goodbye"), asciiBytes(msgWitness(MSG))],
});

check("a doctored line does not parse", () => assert.equal(parseMsg(TAMPERED), null));
check("a doctored line is dropped, not displayed", () =>
  assert.deepEqual(accept([], TAMPERED), []));
check("garbage is dropped", () => assert.deepEqual(accept([], "not an envelope"), []));
check("a doctored line cannot change the transcript", () => {
  const lines = [printMsg(MSG), printMsg(message(LEAN.room, "bob", 2, utf8("hi there")))];
  assert.deepEqual(transcript(receive([], [...lines, TAMPERED])),
    transcript(receive([], lines)));
});

// ------------------------------------------------------- order independence

console.log("order independence");

const lineA = printMsg(message(LEAN.room, "alice", 1, utf8("hello")));
const lineB = printMsg(message(LEAN.room, "bob", 2, utf8("hi there")));
const lineC = printMsg(message(LEAN.room, "carol", 3, utf8("hello both")));

check("the transcript does not depend on arrival order", () => {
  const orders = [
    [lineA, lineB, lineC], [lineC, lineB, lineA], [lineB, lineA, lineC],
    [lineB, lineC, lineA], [lineC, lineA, lineB], [lineA, lineC, lineB],
  ];
  const first = transcript(receive([], orders[0])).map(msgText);
  for (const o of orders) assert.deepEqual(transcript(receive([], o)).map(msgText), first);
  assert.deepEqual(first, ["hello", "hi there", "hello both"]);
});

check("a line heard twice is kept once", () => {
  assert.equal(receive([], [lineA, lineA, lineB]).length, 2);
});

check("a roster is a set, whatever the order", () => {
  const a = announce("alice", 1, ADDRS);
  const b = announce("bob", 4, []);
  const r1 = rosterMerge([], [a, b, a]);
  const r2 = rosterMerge([], [b, a]);
  assert.equal(r1.length, r2.length);
  assert.ok(rosterKnows(r1, "alice") && rosterKnows(r1, "bob"));
});

check("the freshest announcement wins", () => {
  const r = rosterMerge([], [announce("alice", 1, []), announce("alice", 9, ADDRS),
                             announce("alice", 3, [])]);
  assert.equal(rosterBest(r, "alice").seq, 9);
  assert.equal(rosterBest(r, "nobody"), null);
});

check("discovery is transitive", () => {
  const c = rosterInsert([], announce("carol", 1, []));
  const b = rosterMerge(rosterInsert([], announce("bob", 1, [])), c);
  const a = rosterMerge(rosterInsert([], announce("alice", 1, [])), b);
  assert.ok(rosterKnows(a, "carol"));
});

// ---------------------------------------------------- the in-memory relay

console.log("relay semantics");

check("posting appends, polling resumes from the cursor", () => {
  const sv = new Server();
  sv.post("room", lineA);
  const first = sv.fetch("room", 0);
  assert.deepEqual(first.lines, [lineA]);
  sv.post("room", lineB);
  const next = sv.fetch("room", first.cursor);
  assert.deepEqual(next.lines, [lineB]);
  assert.equal(next.cursor, 2);
});

check("rooms do not leak into each other", () => {
  const sv = new Server();
  sv.post("one", lineA);
  assert.deepEqual(sv.fetch("two", 0).lines, []);
});

check("peers are discovered from a poll", () => {
  const sv = new Server();
  sv.post("room", printAnnounce(announce("alice", 1, ADDRS)));
  sv.post("room", printAnnounce(announce("bob", 1, [])));
  const roster = acceptPeers([], sv.fetch("room", 0).lines);
  assert.ok(rosterKnows(roster, "alice"));
  assert.ok(rosterKnows(roster, "bob"));
});

// -------------------------------------------------- the real relay, end to end

console.log("the real relay (server/relay.mjs)");

// A throwaway pass DB: the anonymous rate limit (10 lines / 10 min per
// sender) is per-DB, and a shared default DB makes back-to-back runs
// fail with 429s from the previous run's spending.
const cfg = { ...CONFIG, port: 0, host: "127.0.0.1", staticDir: "",
  passDb: `/tmp/kant-net-test-${process.pid}/passes.sqlite` };
const server = createServer(cfg, new Rooms(cfg));
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}`;

await checkAsync("the relay reports itself healthy", async () => {
  const h = await (await fetch(`${base}/health`)).json();
  assert.equal(h.name, "kant-zk-relay");
});

await checkAsync("two strangers meet through an invitation", async () => {
  // Alice opens a room and shows a code.
  const alice = new KantNode({ peer: "alice", relay: base });
  const code = alice.createRoom(base);
  assert.ok(code.length > 0);

  // Bob scans it: same room, no secret on the wire.
  const bob = new KantNode({ peer: "bob", relay: base });
  const scanned = bob.joinInvite(code);
  assert.ok(scanned);
  assert.equal(bob.room, alice.room);

  // Both announce themselves and poll.
  await alice.announceSelf();
  await bob.announceSelf();
  await alice.pollOnce();
  await bob.pollOnce();

  assert.ok(bob.peers().some((p) => p.peer === "alice"), "bob found alice");
  assert.ok(alice.peers().some((p) => p.peer === "bob"), "alice found bob");

  // And they chat.
  await alice.say("hello bob");
  await bob.say("hello alice");
  await alice.pollOnce();
  await bob.pollOnce();

  const seen = (n) => n.view().map(msgText);
  assert.deepEqual(seen(alice), seen(bob), "identical transcripts");
  assert.ok(seen(alice).includes("hello bob"));
  assert.ok(seen(alice).includes("hello alice"));
});

await checkAsync("a late joiner catches up from cursor zero", async () => {
  const alice = new KantNode({ peer: "alice", relay: base });
  const code = alice.createRoom(base);
  await alice.say("first");
  await alice.say("second");

  const carol = new KantNode({ peer: "carol", relay: base });
  carol.joinInvite(code);
  await carol.pollOnce();
  assert.deepEqual(carol.view().map(msgText), ["first", "second"]);
});

await checkAsync("polling in stages loses nothing", async () => {
  const client = new RelayClient(base);
  const room = roomOf(utf8("staged room"));
  await client.post(room, [lineA]);
  const first = await client.poll(room);
  assert.equal(first.lines.length, 1);
  await client.post(room, [lineB, lineC]);
  const second = await client.poll(room);
  assert.deepEqual(second.lines, [lineB, lineC]);
  client.rewind(room);
  const all = await client.poll(room);
  assert.equal(all.lines.length, 3);
});

await checkAsync("a long poll wakes up when somebody speaks", async () => {
  const client = new RelayClient(base);
  const room = roomOf(utf8("long poll room"));
  await client.poll(room);
  const waiting = client.poll(room, { wait: 5 });
  setTimeout(() => { new RelayClient(base).post(room, [lineA]).catch(() => {}); }, 50);
  const out = await waiting;
  assert.deepEqual(out.lines, [lineA]);
});

await checkAsync("a client refuses a forged line from the relay", async () => {
  const client = new RelayClient(base);
  const room = roomOf(utf8("hostile room"));
  await client.post(room, [TAMPERED, printMsg(MSG)]);
  const out = await client.poll(room);
  const kept = receive([], out.lines);
  assert.equal(kept.length, 1);
  assert.equal(msgText(kept[0]), "hello");
});

await checkAsync("a websocket carries the same room", async () => {
  const room = roomOf(utf8("socket room"));
  const wsUrl = `${base.replace("http", "ws")}/ws/${room}?cursor=0`;
  const got = [];
  const ws = new WebSocket(wsUrl);
  await new Promise((r) => ws.addEventListener("open", r));
  const done = new Promise((resolve) => {
    ws.addEventListener("message", (ev) => {
      const msg = JSON.parse(ev.data);
      got.push(...msg.lines);
      if (got.length >= 2) resolve();
    });
  });
  ws.send(lineA);
  await new RelayClient(base).post(room, [lineB]);
  await done;
  ws.close();
  const kept = receive([], got);
  assert.equal(kept.length, 2);
});

await checkAsync("clients that took different routes agree", async () => {
  const room = roomOf(utf8("mixed routes"));
  const client = new RelayClient(base);
  await client.post(room, [lineA, lineB, lineC]);
  const viaRelay = await client.poll(room);

  // The second client got the same lines in a different order, over a
  // data channel and a QR scan rather than from the relay.
  const shuffled = [viaRelay.lines[2], viaRelay.lines[0], viaRelay.lines[1]];
  assert.deepEqual(
    transcript(receive([], viaRelay.lines)).map(printMsg),
    transcript(receive([], shuffled)).map(printMsg),
  );
});

server.close();
await new Promise((r) => setTimeout(r, 10));

console.log(`\nall ${checks} discovery / relay checks passed`);
