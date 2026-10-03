// disk-blocks-test.mjs — the durable block store, proven the same way
// the relay proves its in-memory twin: pin, serve, refuse, restart.
// Plus the two things only a disk store can prove: replay and
// corruption refusal.

import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join as pathJoin } from "node:path";
import assert from "node:assert/strict";
import { DiskBlocks } from "./disk-blocks.mjs";
import { CONFIG } from "./relay.mjs";
import { witness } from "../web/kantzk.mjs";

const cfg = { ...CONFIG, maxBlock: 1024, gasStoreBudget: 2048, gasServeBudget: 4096,
  gasWindowMs: 60 * 60 * 1000 };
const dir = mkdtempSync(pathJoin(tmpdir(), "kant-disk-blocks-"));
const bytes = (s) => new TextEncoder().encode(s);
const room = "a".repeat(64);
const cid = witness(Array.from(bytes("hello archive")));

let pass = 0, fail = 0;
const t = async (name, fn) => {
  try { await fn(); console.log(`✔ ${name}`); pass++; }
  catch (e) { console.log(`✖ ${name}: ${e.message}`); fail++; }
};

await t("pin and serve a block", async () => {
  const db = new DiskBlocks(cfg, dir);
  assert.equal(db.put(room, cid, bytes("hello archive")), null);
  const out = db.get(room, cid);
  assert.equal(out.status, undefined);
  assert.deepEqual(out, Buffer.from(bytes("hello archive")));
  db.wipe(room);
});

await t("a wrong cid is refused", async () => {
  const db = new DiskBlocks(cfg, dir);
  const refused = db.put(room, "0".repeat(64), bytes("not those bytes"));
  assert.equal(refused.status, 400);
  db.wipe(room);
});

await t("blocks survive a restart (replay)", async () => {
  {
    const db = new DiskBlocks(cfg, dir);
    assert.equal(db.put(room, cid, bytes("hello archive")), null);
  } // "restart": a fresh store over the same root
  const db2 = new DiskBlocks(cfg, dir);
  const out = db2.get(room, cid);
  assert.equal(out.status, undefined);
  assert.deepEqual(out, Buffer.from(bytes("hello archive")));
  db2.wipe(room);
});

await t("a corrupted file on disk is refused, never served", async () => {
  {
    const db = new DiskBlocks(cfg, dir);
    assert.equal(db.put(room, cid, bytes("hello archive")), null);
  }
  // Corrupt the bytes behind the store's back.
  const ref = (await import("node:crypto")).createHash("sha256").update(room).digest("hex").slice(0, 8);
  writeFileSync(pathJoin(dir, ref, `${cid}.bin`), bytes("tampered"));
  const db2 = new DiskBlocks(cfg, dir);
  const out = db2.get(room, cid);
  assert.equal(out.status, 404);
  db2.wipe(room);
});

await t("gas is charged and refuses over-budget pins", async () => {
  const db = new DiskBlocks(cfg, dir);
  // Three 800-byte pins: 800+800 fits the 2048 budget, the third tips
  // it over — the refusal is 429 (gas), not 413 (size).
  for (let i = 0; i < 3; i++) {
    const b = new Uint8Array(800).fill(65 + i);
    const c = witness(Array.from(b));
    const refused = db.put(room, c, b);
    if (i < 2) assert.equal(refused, null);
    else assert.equal(refused.status, 429);
  }
  db.wipe(room);
});

rmSync(dir, { recursive: true, force: true });
console.log(`ℹ pass ${pass}`);
console.log(`ℹ fail ${fail}`);
process.exit(fail ? 1 : 0);
