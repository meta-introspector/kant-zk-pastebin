// uucp-test.mjs — conformance checks for the relay-free static sneakernet.
//
// The pure functions of `web/kant-uucp.mjs` are checked against vectors
// computed by Lean; `RequestProject/Kant/Demo.lean` checks the same
// numbers with `#guard`, so the two sides cannot drift.  The rest of the
// file exercises the protocol end to end with no server of any kind:
// bags in DMs, bags cut into tweets, a bang path, a static page and the
// staleness that follows from publishing a snapshot.
//
// Run:  node web/uucp-test.mjs

import assert from "node:assert/strict";
import { utf8, witness, asciiBytes, envelopeEncode, natToBytesBE } from "./kantzk.mjs";
import { roomOf, printMsg, parseMsg, msgWitness, TAG_CHAT } from "./kant-net.mjs";
import {
  packBag, openBag, readBagUrl, thread, readThread, threadLength,
  bagForCarrier, CARRIER_CAPACITY, SneakerNode, Site, exchange, route,
  TAG_BAG, loadNode, saveNode, shareKit,
} from "./kant-uucp.mjs";

let checks = 0;
const check = (name, fn) => { fn(); checks += 1; console.log(`  ok  ${name}`); };

// ------------------------------------------------ vectors computed by Lean

const ROOM = roomOf(utf8("kant-zk demo secret"));

const LEAN = {
  room: "bd71dd50a1ee00eaa91ea3fb701d151f8bc3059f81b1766c51ea8736f88acec1",
  bagLength: 1192,
  bagWitness: "1e3c0d3ce7a0b792ed7bcb7d2cf3ea1dc1f6c3bdb7b1ff28ff5bbc0c036b3073",
  threadParts: 12,
  partLengths: [215, 217, 217, 217, 217, 217, 217, 217, 217, 217, 217, 201],
};

const alice = SneakerNode.blank("alice");
alice.write(ROOM, "hello");
alice.write(ROOM, "second");

console.log("golden vectors from Lean");

check("room matches Lean", () => assert.equal(ROOM, LEAN.room));
check("spool of two written lines", () => assert.equal(alice.spool.length, 2));
check("bag length matches Lean", () => assert.equal(alice.bag().length, LEAN.bagLength));
check("bag digest matches Lean", () =>
  assert.equal(witness(asciiBytes(alice.bag())), LEAN.bagWitness));
check("thread part count matches Lean", () =>
  assert.equal(thread(100, alice.bag()).length, LEAN.threadParts));
check("thread part sizes match Lean", () =>
  assert.deepEqual(thread(100, alice.bag()).map((t) => t.length), LEAN.partLengths));

// --------------------------------------------------------------- round trips

console.log("\nmailbags");

check("a bag pasted out of a DM is the same messages", () => {
  const ms = openBag(alice.bag());
  assert.equal(ms.length, 2);
  assert.deepEqual(ms.map(printMsg), alice.view().map(printMsg));
});

check("a bag travels as a link", () => {
  const u = alice.bagLink("https://kant.example/");
  assert.deepEqual(readBagUrl(u).map(printMsg), alice.view().map(printMsg));
});

check("a bag is plain ASCII", () =>
  assert.ok([...alice.bag()].every((c) => c.charCodeAt(0) < 128)));

check("a doctored line spoils the whole bag", () => {
  // The witness of a real line, kept in place over a body somebody else
  // swapped in: exactly what a hostile courier would hand you.
  const real = alice.spool[0];
  const doctored = envelopeEncode({
    tag: TAG_CHAT,
    fields: [
      asciiBytes(real.room), asciiBytes(real.sender), natToBytesBE(real.seq),
      utf8("goodbye"), asciiBytes(msgWitness(real)),
    ],
  });
  assert.equal(parseMsg(doctored), null);
  const forged = envelopeEncode({
    tag: TAG_BAG,
    fields: [asciiBytes(doctored), asciiBytes(printMsg(real))],
  });
  assert.equal(openBag(forged), null);
});

check("pasting a forgery changes nothing", () => {
  const bob = SneakerNode.blank("bob");
  bob.paste(alice.bag());
  const before = bob.spool.length;
  const r = bob.paste("not a bag at all");
  assert.equal(r.accepted, false);
  assert.equal(bob.spool.length, before);
});

// ------------------------------------------------------------- no relay

console.log("\nhanding bags around, with no server");

check("one bag catches the receiver up", () => {
  const bob = SneakerNode.blank("bob");
  bob.paste(alice.bag());
  assert.deepEqual(bob.view().map(printMsg), alice.view().map(printMsg));
  assert.ok(bob.fresherThan(alice));
});

check("the same knowledge produces the same code", () => {
  const bob = SneakerNode.blank("bob");
  bob.paste(alice.bag());
  assert.equal(bob.bag(), alice.bag());
});

check("pasting the same code twice adds nothing", () => {
  const bob = SneakerNode.blank("bob");
  bob.paste(alice.bag());
  const r = bob.paste(alice.bag());
  assert.equal(r.added, 0);
  assert.equal(bob.spool.length, 2);
});

check("no paste, no news", () => {
  const bob = SneakerNode.blank("bob");
  bob.sneakernet([]);
  assert.equal(bob.spool.length, 0);
  assert.deepEqual(bob.view(), []);
});

check("the order codes are pasted in does not matter", () => {
  const carol = SneakerNode.blank("carol");
  carol.write(ROOM, "ping");
  const dave = SneakerNode.blank("dave");
  dave.write(ROOM, "pong");

  const x = SneakerNode.blank("x");
  x.sneakernet([alice.bag(), carol.bag(), dave.bag()]);
  const y = SneakerNode.blank("y");
  y.sneakernet([dave.bag(), alice.bag(), carol.bag()]);

  assert.deepEqual(x.view().map(printMsg), y.view().map(printMsg));
  assert.equal(x.spool.length, 4);
});

check("two bags, one each way, and both sides agree", () => {
  const a = SneakerNode.blank("alice");
  a.write(ROOM, "hello");
  const c = SneakerNode.blank("carol");
  c.write(ROOM, "ping");
  const [a2, c2] = exchange(a, c);
  assert.deepEqual(a2.view().map(printMsg), c2.view().map(printMsg));
});

check("a bang path delivers a!c!d", () => {
  const a = SneakerNode.blank("alice");
  a.write(ROOM, "hello");
  const c = SneakerNode.blank("carol");
  c.write(ROOM, "ping");
  const d = SneakerNode.blank("dave");
  const last = route(a, [c, d]);
  assert.ok(last.fresherThan(a));
  assert.equal(d.spool.length, 2);
});

// ------------------------------------------------------------ tweet threads

console.log("\ntweets");

check("a big bag is cut into tweet-sized parts", () => {
  const parts = bagForCarrier(alice.bag(), "tweet");
  assert.ok(parts.length > 1);
  for (const p of parts) assert.ok(p.length <= CARRIER_CAPACITY.tweet, `${p.length} chars`);
});

check("the parts reassemble in any order", () => {
  const parts = thread(100, alice.bag());
  const shuffled = [...parts].reverse();
  assert.equal(readThread(shuffled), alice.bag());
  const interleaved = [parts[3], parts[0], ...parts.slice(4), parts[1], parts[2]];
  assert.equal(readThread(interleaved), alice.bag());
});

check("a threaded bag pastes back into a node", () => {
  const parts = thread(100, alice.bag());
  const bob = SneakerNode.blank("bob");
  const r = bob.paste([...parts].reverse().join("\n"));
  assert.ok(r.accepted);
  assert.deepEqual(bob.view().map(printMsg), alice.view().map(printMsg));
});

check("a small bag needs no thread", () => {
  const tiny = SneakerNode.blank("tiny");
  tiny.write(ROOM, "hi");
  const parts = bagForCarrier(tiny.bag(), "dm");
  assert.equal(parts.length, 1);
  assert.equal(threadLength(100, tiny.bag()) > 1, true);
});

// ------------------------------------------------------------ static site

console.log("\nthe static server");

check("a visitor who pastes the page catches up with the publisher", () => {
  const site = new Site().publish("/feed.txt", alice);
  const vic = SneakerNode.blank("vic");
  site.visit("/feed.txt", vic);
  assert.deepEqual(vic.view().map(printMsg), alice.view().map(printMsg));
});

check("serving never changes the site", () => {
  const site = new Site().publish("/feed.txt", alice);
  const before = JSON.stringify([...site.files]);
  const [same, body] = site.serve("/feed.txt");
  assert.equal(body, alice.bag());
  assert.equal(JSON.stringify([...same.files]), before);
});

check("a page is a snapshot: later lines stay invisible", () => {
  const publisher = SneakerNode.blank("alice");
  publisher.write(ROOM, "hello");
  const site = new Site().publish("/feed.txt", publisher);
  publisher.write(ROOM, "written after publishing");

  const vic = SneakerNode.blank("vic");
  site.visit("/feed.txt", vic);
  assert.equal(vic.spool.length, 1);
  assert.equal(publisher.spool.length, 2);

  // ... until a fresher code is pasted.
  site.publish("/feed.txt", publisher);
  site.visit("/feed.txt", vic);
  assert.equal(vic.spool.length, 2);
});

check("publishing one path leaves the others alone", () => {
  const site = new Site().publish("/a.txt", alice);
  const other = SneakerNode.blank("carol");
  other.write(ROOM, "ping");
  site.publish("/b.txt", other);
  assert.equal(site.get("/a.txt"), alice.bag());
});

// ------------------------------------------------------------- persistence

console.log("\nkeeping state between visits");

check("a node survives being stored and reloaded", () => {
  const store = new Map();
  const storage = { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, v) };
  saveNode(alice, storage);
  const again = loadNode("alice", storage);
  assert.deepEqual(again.view().map(printMsg), alice.view().map(printMsg));
  assert.equal(again.clock, alice.clock);
});

check("the share kit reports how the code must travel", () => {
  const kit = shareKit(alice, { base: "https://kant.example/", carrier: "tweet" });
  assert.equal(kit.fitsOne, false);
  assert.ok(kit.parts.length > 1);
  assert.ok(kit.link.includes("#"));
  assert.deepEqual(readBagUrl(kit.link).map(printMsg), alice.view().map(printMsg));
});

console.log(`\nall ${checks} sneakernet checks passed`);
