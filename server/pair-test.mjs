// pair-test.mjs — the archive pairer, proven end to end with the
// minimal-cost shape: the CF side is a STATIC snapshot (a plain file
// server standing in for CF Pages: blocks.json + b/<cid>.bin), the
// local side is the relay with durable blocks.  Pin on each side, one
// pairing cycle, both must agree.

import { mkdtempSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join as pathJoin } from "node:path";
import http from "node:http";
import { readFileSync as rf } from "node:fs";
import { createHash } from "node:crypto";
import assert from "node:assert/strict";
import { createServer, CONFIG } from "./relay.mjs";
import { witness } from "../web/kantzk.mjs";

const bytes = (s) => new TextEncoder().encode(s);
const roomA = "b".repeat(64); // pinned locally, missing from pages
const blockA = bytes("pinned on local");
const cidA = witness(Array.from(blockA));
const roomB = "c".repeat(64); // in the pages snapshot, missing locally
const blockB = bytes("pinned on pages");
const cidB = witness(Array.from(blockB));

const dir = mkdtempSync(pathJoin(tmpdir(), "kant-pair-"));
const cfg = (extra = {}) => ({ ...CONFIG, port: 0, host: "127.0.0.1", quiet: true,
  passDb: pathJoin(dir, "passes.sqlite"), ...extra });

let pass = 0, fail = 0;
const t = async (name, fn) => {
  try { await fn(); console.log(`✔ ${name}`); pass++; }
  catch (e) { console.log(`✖ ${name}: ${e.message}`); fail++; }
};

// The local archive relay (durable blocks).
const local = createServer(cfg({ blocksDir: pathJoin(dir, "blocks") }));
await new Promise((r) => local.listen(0, "127.0.0.1", r));
const lb = `http://127.0.0.1:${local.address().port}`;

// The "CF Pages" stand-in: a static snapshot dir served over http.
const snap = pathJoin(dir, "snap", "archive");
mkdirSync(pathJoin(snap, "b"), { recursive: true });
writeFileSync(pathJoin(snap, "b", `${cidB}.bin`), blockB);
writeFileSync(pathJoin(snap, "blocks.json"),
  JSON.stringify([{ ref: roomRef8(roomB), cid: cidB, size: blockB.length }]));
function roomRef8(room) {
  return createHash("sha256").update(room).digest("hex").slice(0, 8);
}
const pages = http.createServer((req, res) => {
  const p = req.url.replace(/^\/archive/, "");
  const file = { "/blocks.json": pathJoin(snap, "blocks.json"),
    [`/b/${cidB}.bin`]: pathJoin(snap, "b", `${cidB}.bin`) }[p];
  if (!file) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { "content-type": "application/octet-stream" });
  res.end(rf(file));
});
await new Promise((r) => pages.listen(0, "127.0.0.1", r));
const pb = `http://127.0.0.1:${pages.address().port}`;

const put = async (base, room, cid, b) =>
  (await fetch(`${base}/room/${room}/block/${cid}`, { method: "POST", body: b })).ok;
const list = async (base, room) => (await (await fetch(`${base}/room/${room}/blocks`)).json()).blocks;
const get = async (base, room, cid) => await (await fetch(`${base}/room/${room}/block/${cid}`)).arrayBuffer();

await t("the local relay pins and lists", async () => {
  assert.equal(await put(lb, roomA, cidA, blockA), true);
  assert.deepEqual(await list(lb, roomA), [cidA]);
});

await t("one pairing cycle pulls the pages snapshot into the local store", async () => {
  const { execFile } = await import("node:child_process");
  const { promisify } = await import("node:util");
  const run = promisify(execFile);
  const here = import.meta.dirname;
  const { stdout } = await run(process.execPath, [pathJoin(here, "pair.mjs"),
    "--local", lb, "--pages", pb, "--rooms", roomA, "--once"]);
  assert.match(stdout, /pulled 1/);
  // The pulled block is pinned under its room HANDLE (all the snapshot
  // knows) — and the bytes verify.
  assert.deepEqual(await list(lb, roomRef8(roomB)), [cidB]);
  assert.deepEqual(Buffer.from(await get(lb, roomRef8(roomB), cidB)), Buffer.from(blockB));
});

await t("a second cycle is a no-op", async () => {
  const { execFile } = await import("node:child_process");
  const { promisify } = await import("node:util");
  const run = promisify(execFile);
  const here = import.meta.dirname;
  const { stdout } = await run(process.execPath, [pathJoin(here, "pair.mjs"),
    "--local", lb, "--pages", pb, "--rooms", roomA, "--once"]);
  assert.match(stdout, /pulled 0/);
});

await t("the local side's pins survive a relay restart", async () => {
  local.close();
  await new Promise((r) => setTimeout(r, 100)); // let the port drain
  const local2 = createServer(cfg({ blocksDir: pathJoin(dir, "blocks") }));
  await new Promise((r) => local2.listen(0, "127.0.0.1", r));
  const lb2 = `http://127.0.0.1:${local2.address().port}`;
  assert.deepEqual(await list(lb2, roomA), [cidA]);
  assert.deepEqual(await list(lb2, roomRef8(roomB)), [cidB]);
  assert.deepEqual(Buffer.from(await get(lb2, roomA, cidA)), Buffer.from(blockA));
  local2.close();
});

await t("the p2p router serves a miss from a mirror", async () => {
  // A relay with NO local copy of the block, configured with a mirror
  // that has it: the GET must be routed to the mirror and the bytes
  // must verify.  A lying mirror can refuse service, never corrupt.
  const holder = createServer(cfg({})); // in-memory blocks
  await new Promise((r) => holder.listen(0, "127.0.0.1", r));
  const hb = `http://127.0.0.1:${holder.address().port}`;
  assert.equal(await put(hb, roomA, cidA, blockA), true);
  const router = createServer(cfg({ blockMirrors: [hb] }));
  await new Promise((r) => router.listen(0, "127.0.0.1", r));
  const rb = `http://127.0.0.1:${router.address().port}`;
  const out = await fetch(`${rb}/room/${roomA}/block/${cidA}`);
  assert.equal(out.status, 200);
  assert.deepEqual(Buffer.from(await out.arrayBuffer()), Buffer.from(blockA));
  assert.equal(out.headers.get("x-kant-block-via") != null, true);
  router.close();
});

pages.close();
rmSync(dir, { recursive: true, force: true });
console.log(`ℹ pass ${pass}`);
console.log(`ℹ fail ${fail}`);
process.exit(fail ? 1 : 0);
