// Tests for server/room-store.mjs — the peer-side replica of a room.
//
// The relay is a mailbox that forgets. This is the copy that does not, so the
// things worth asserting are: it never double-counts, it never rewinds, it
// remembers a trim, and two peers that both hold a line agree on having it
// exactly once.
//
// No network: every relay here is a fake that hands back a scripted poll.
//
//   node scripts/room-store-test.mjs

import assert from "node:assert/strict";
import { RoomStore } from "../server/room-store.mjs";

let pass = 0, fail = 0;
const t = async (name, fn) => {
  try { await fn(); console.log(`  ok    ${name}`); pass++; }
  catch (e) { console.log(`  FAIL  ${name}\n        ${e.message}`); fail++; }
};

/** A relay that serves a scripted log and remembers its cursor. */
function fakeRelay(lines, name = "https://relay.example") {
  const log = [...lines];
  return {
    name,
    get served() { return log.length; },
    poll: async (_room, { from = 0 } = {}) => ({
      lines: log.slice(from),
      cursor: log.length,
      truncated: false,
    }),
  };
}

const L = (...n) => n.map((i) => `line-${i}`);

console.log("recording");

await t("a first poll records every line", () => {
  const s = new RoomStore();
  const r = s.record("room", { lines: L(1, 2, 3), cursor: 3, truncated: false }, { relay: "r1" });
  assert.equal(r.inserted, 3);
  assert.equal(r.duplicate, 0);
  assert.equal(s.cursor("room"), 3);
  assert.equal(s.lines("room").length, 3);
});

await t("re-polling the same lines inserts nothing", () => {
  const s = new RoomStore();
  s.record("room", { lines: L(1, 2, 3), cursor: 3 }, { relay: "r1" });
  const again = s.record("room", { lines: L(1, 2, 3), cursor: 3 }, { relay: "r1" });
  assert.equal(again.inserted, 0, "a re-poll duplicated history");
  assert.equal(again.duplicate, 3);
  assert.equal(s.lines("room").length, 3);
});

await t("a second relay serving the same room adds no duplicates", () => {
  const s = new RoomStore();
  s.record("room", { lines: L(1, 2), cursor: 2 }, { relay: "r1" });
  const via2 = s.record("room", { lines: L(1, 2), cursor: 2 }, { relay: "r2" });
  assert.equal(via2.inserted, 0);
  assert.equal(s.lines("room").length, 2);
  assert.deepEqual(s.relays("room"), ["r1", "r2"], "both relays should be recorded as sources");
});

await t("a duplicate is still attributed to the relay that carried it", () => {
  const s = new RoomStore();
  s.record("room", { lines: L(1), cursor: 1 }, { relay: "r1" });
  s.record("room", { lines: L(1), cursor: 1 }, { relay: "r2" });
  assert.deepEqual(s.relays("room"), ["r1", "r2"]);
});

await t("lines arrive in order and are addressable by ordinal", () => {
  const s = new RoomStore();
  s.record("room", { lines: L(1, 2, 3, 4, 5), cursor: 5 }, { relay: "r1" });
  assert.deepEqual(s.lines("room", { from: 3 }).map((l) => l.text), ["line-3", "line-4", "line-5"]);
  assert.deepEqual(s.lines("room", { from: 1, limit: 2 }).map((l) => l.text), ["line-1", "line-2"]);
});

await t("an unknown room reads empty rather than throwing", () => {
  const s = new RoomStore();
  assert.deepEqual(s.lines("never-seen"), []);
  assert.equal(s.cursor("never-seen"), 0);
  assert.equal(s.has("never-seen"), false);
});

console.log("the cursor only moves forward");

await t("a lower cursor does not rewind the replica", () => {
  const s = new RoomStore();
  s.record("room", { lines: L(1, 2, 3, 4, 5), cursor: 5 }, { relay: "r1" });
  // The relay restarted, or trimmed, and reports from zero.
  s.record("room", { lines: [], cursor: 0, truncated: true }, { relay: "r1" });
  assert.equal(s.cursor("room"), 5, "the replica rewound to a relay that lost its log");
  assert.equal(s.lines("room").length, 5, "lines were lost to a rewind");
});

await t("truncated latches and never un-happens", () => {
  const s = new RoomStore();
  s.record("room", { lines: L(1, 2), cursor: 2 }, { relay: "r1" });
  s.record("room", { lines: [], cursor: 2, truncated: true }, { relay: "r1" });
  s.record("room", { lines: [], cursor: 2, truncated: false }, { relay: "r1" });
  assert.equal(s.stats().detail[0].truncated, true,
    "a later un-truncated poll cleared a trim the replica already suffered");
});

console.log("syncing from a relay");

await t("sync walks a relay forward a poll at a time", async () => {
  const s = new RoomStore();
  const relay = fakeRelay(L(1, 2, 3));
  const first = await s.sync("room", relay.poll, { relay: relay.name });
  assert.equal(first.inserted, 3);
  assert.equal(s.cursor("room"), 3);

  // Nothing new.
  const idle = await s.sync("room", relay.poll, { relay: relay.name });
  assert.equal(idle.inserted, 0);

  // The relay grows.
  relay.poll = async (_r, { from = 0 } = {}) => ({
    lines: [...L(1, 2, 3, 4), "line-5"].slice(from), cursor: 5, truncated: false,
  });
  const more = await s.sync("room", relay.poll, { relay: relay.name });
  assert.equal(more.inserted, 2);
  assert.equal(s.cursor("room"), 5);
});

await t("sync refuses to run without a poll function", async () => {
  const s = new RoomStore();
  await assert.rejects(() => s.sync("room", null), /poll/);
});

console.log("peer to peer");

await t("a peer with no lines contributes nothing", () => {
  const s = new RoomStore();
  s.record("room", { lines: L(1), cursor: 1 }, { relay: "r1" });
  const empty = new RoomStore();
  assert.equal(s.merge("room", empty).inserted, 0);
});

await t("merging a peer's lines adds only what we lack", () => {
  const mine = new RoomStore();
  const theirs = new RoomStore();
  mine.record("room", { lines: L(1, 2), cursor: 2 }, { relay: "r1" });
  theirs.record("room", { lines: L(1, 2, 3, 4), cursor: 4 }, { relay: "r2" });

  const r = mine.merge("room", theirs);
  assert.equal(r.inserted, 2, "expected to gain exactly lines 3 and 4");
  assert.equal(r.duplicate, 2);
  assert.deepEqual(mine.lines("room").map((l) => l.text), L(1, 2, 3, 4));
});

await t("merge keeps our order rather than renumbering to the peer's", () => {
  const mine = new RoomStore();
  const theirs = new RoomStore();
  mine.record("room", { lines: ["a"], cursor: 1 }, { relay: "r1" });
  theirs.record("room", { lines: ["a", "b"], cursor: 2 }, { relay: "r2" });
  mine.merge("room", theirs);
  assert.deepEqual(mine.lines("room").map((l) => l.text), ["a", "b"]);
  assert.deepEqual(mine.lines("room").map((l) => l.ordinal), [1, 2]);
});

await t("a peer's cursor is not adopted", () => {
  // Peer B says it has read to cursor 40 off relay X. That says nothing about
  // what peer A has read, so adopting it would mark unseen lines as seen.
  const mine = new RoomStore();
  const theirs = new RoomStore();
  mine.record("room", { lines: ["a"], cursor: 1 }, { relay: "r1" });
  theirs.record("room", { lines: L(1, 2, 3), cursor: 3 }, { relay: "r2" });
  mine.merge("room", theirs);
  assert.equal(mine.cursor("room"), 1, "a merge moved the read cursor");
});

await t("merge records the peer as the source", () => {
  const mine = new RoomStore();
  const theirs = new RoomStore();
  theirs.record("room", { lines: ["z"], cursor: 1 }, { relay: "r2" });
  mine.merge("room", theirs);
  assert.deepEqual(mine.relays("room"), ["peer:r2"]);
});

await t("merge does not claim the room was synced", () => {
  const mine = new RoomStore();
  const theirs = new RoomStore();
  theirs.record("room", { lines: ["z"], cursor: 1 }, { relay: "r2" });
  mine.merge("room", theirs);
  assert.equal(mine.stats().detail[0].syncedAt, 0, "a peer merge stamped synced_at");
});

await t("merging back and forth converges", () => {
  const a = new RoomStore(), b = new RoomStore();
  a.record("room", { lines: L(1, 2, 3), cursor: 3 }, { relay: "r1" });
  b.record("room", { lines: L(3, 4, 5), cursor: 3 }, { relay: "r2" });
  b.merge("room", a);
  a.merge("room", b);
  b.merge("room", a);
  const ta = a.lines("room").map((l) => l.text).sort();
  const tb = b.lines("room").map((l) => l.text).sort();
  assert.deepEqual(ta, tb, "two peers did not converge");
  assert.deepEqual(ta, L(1, 2, 3, 4, 5).sort());
});

console.log("rooms stay separate");

await t("two rooms do not see each other's lines", () => {
  const s = new RoomStore();
  s.record("alpha", { lines: L(1, 2), cursor: 2 }, { relay: "r1" });
  s.record("beta", { lines: L(9), cursor: 1 }, { relay: "r1" });
  assert.equal(s.lines("alpha").length, 2);
  assert.equal(s.lines("beta").length, 1);
  assert.equal(s.stats().rooms, 2);
});

await t("the same line in two rooms counts twice", () => {
  const s = new RoomStore();
  s.record("alpha", { lines: ["shared"], cursor: 1 }, { relay: "r1" });
  s.record("beta", { lines: ["shared"], cursor: 1 }, { relay: "r1" });
  assert.equal(s.stats().lines, 2, "rooms are not namespaced on the digest");
});

console.log("a replica can be a file");

await t("a file-backed store survives being reopened", async () => {
  const { mkdtempSync, rmSync } = await import("node:fs");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const dir = mkdtempSync(join(tmpdir(), "room-store-"));
  const file = join(dir, "rooms.sqlite");
  try {
    const first = new RoomStore({ file });
    first.record("room", { lines: L(1, 2, 3), cursor: 3 }, { relay: "r1" });
    first.close();

    const second = new RoomStore({ file });
    assert.equal(second.cursor("room"), 3, "the cursor did not survive a reopen");
    assert.deepEqual(second.lines("room").map((l) => l.text), L(1, 2, 3));
    second.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);