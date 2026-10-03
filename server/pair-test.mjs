// pair-test.mjs — the archive pairer, proven end to end: two relays
// (one local with disk blocks, one standing in for the CF twin), a
// block pinned on each, one pairing cycle, and both must agree.

import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join as pathJoin } from "node:path";
import assert from "node:assert/strict";
import { createServer, CONFIG } from "./relay.mjs";
import { witness } from "../web/kantzk.mjs";

const bytes = (s) => new TextEncoder().encode(s);
const room = "b".repeat(64);
const blockA = bytes("pinned on local");
const cidA = witness(Array.from(blockA));
const blockB = bytes("pinned on twin");
const cidB = witness(Array.from(blockB));

const dir = mkdtempSync(pathJoin(tmpdir(), "kant-pair-"));
const cfg = (port, extra = {}) => ({ ...CONFIG, port, host: "127.0.0.1", quiet: true,
  passDb: pathJoin(dir, `passes-${port}.sqlite`), ...extra });

let pass = 0, fail = 0;
const t = async (name, fn) => {
  try { await fn(); console.log(`✔ ${name}`); pass++; }
  catch (e) { console.log(`✖ ${name}: ${e.message}`); fail++; }
};

const local = createServer(cfg(0, { blocksDir: pathJoin(dir, "blocks") }));
const twin = createServer(cfg(0));
await new Promise((r) => local.listen(0, "127.0.0.1", r));
await new Promise((r) => twin.listen(0, "127.0.0.1", r));
const lp = local.address().port, tp = twin.address().port;
const lb = `http://127.0.0.1:${lp}`, tb = `http://127.0.0.1:${tp}`;

// Pin one block on each side.
const put = async (base, cid, b) =>
  (await fetch(`${base}/room/${room}/block/${cid}`, { method: "POST", body: b })).ok;
const list = async (base) => (await (await fetch(`${base}/room/${room}/blocks`)).json()).blocks;
const get = async (base, cid) => await (await fetch(`${base}/room/${room}/block/${cid}`)).arrayBuffer();

await t("both relays pin and list", async () => {
  assert.equal(await put(lb, cidA, blockA), true);
  assert.equal(await put(tb, cidB, blockB), true);
  assert.deepEqual(await list(lb), [cidA]);
  assert.deepEqual(await list(tb), [cidB]);
});

await t("one pairing cycle converges both sides", async () => {
  const { execFile } = await import("node:child_process");
  const { promisify } = await import("node:util");
  const run = promisify(execFile);
  const here = import.meta.dirname;
  const { stdout } = await run(process.execPath, [pathJoin(here, "pair.mjs"),
    "--local", lb, "--twin", tb, "--rooms", room, "--once"]);
  assert.match(stdout, /pushed 1, pulled 1/);
  assert.deepEqual(new Set(await list(lb)), new Set([cidA, cidB]));
  assert.deepEqual(new Set(await list(tb)), new Set([cidA, cidB]));
});

await t("the pushed bytes verify on both sides", async () => {
  assert.deepEqual(Buffer.from(await get(tb, cidA)), Buffer.from(blockA));
  assert.deepEqual(Buffer.from(await get(lb, cidB)), Buffer.from(blockB));
});

await t("a second cycle is a no-op", async () => {
  const { execFile } = await import("node:child_process");
  const { promisify } = await import("node:util");
  const run = promisify(execFile);
  const here = import.meta.dirname;
  const { stdout } = await run(process.execPath, [pathJoin(here, "pair.mjs"),
    "--local", lb, "--twin", tb, "--rooms", room, "--once"]);
  assert.match(stdout, /pushed 0, pulled 0/);
});

await t("the local side's pins survive a relay restart", async () => {
  local.close();
  await new Promise((r) => setTimeout(r, 100)); // let the port drain
  const local2 = createServer(cfg(0, { blocksDir: pathJoin(dir, "blocks") }));
  await new Promise((r) => local2.listen(0, "127.0.0.1", r));
  const lb2 = `http://127.0.0.1:${local2.address().port}`;
  assert.deepEqual(new Set(await list(lb2)), new Set([cidA, cidB]));
  assert.deepEqual(Buffer.from(await get(lb2, cidA)), Buffer.from(blockA));
  assert.deepEqual(Buffer.from(await get(lb2, cidB)), Buffer.from(blockB));
  local2.close();
});

twin.close();
rmSync(dir, { recursive: true, force: true });
console.log(`ℹ pass ${pass}`);
console.log(`ℹ fail ${fail}`);
process.exit(fail ? 1 : 0);
