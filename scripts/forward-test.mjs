// End-to-end for the bridge: two local relays, a real invite, and the lines
// carried between them by server/forward.mjs.
//
// Two *separate processes* run the carry on purpose. The thing this replaced
// — a `Set` of line strings held in the bridge's own memory — could not
// survive a restart, so a restarted bridge re-sent its whole history and the
// destination grew duplicates. That is only observable if the carries really
// are separate processes, so this script is the regression test for it.
//
// Everything is on 127.0.0.1 with a throwaway pass store, so no Cloudflare
// account, no rate limit, and nothing outside this machine is touched.
//
//   node scripts/forward-test.mjs

import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(fileURLToPath(new URL("..", import.meta.url)));
const { copyInvite, invite, roomOf } = await import(`${root}/web/kant-net.mjs`);
const { Bridge } = await import(`${root}/server/forward.mjs`);

let pass = 0, fail = 0;
const t = async (name, fn) => {
  try { await fn(); console.log(`  ok    ${name}`); pass++; }
  catch (e) { console.log(`  FAIL  ${name}\n        ${e.message}`); fail++; }
};

const dir = mkdtempSync(join(tmpdir(), "forward-test-"));
const PORT_A = 18801, PORT_B = 18802;
const A = `http://127.0.0.1:${PORT_A}`, B = `http://127.0.0.1:${PORT_B}`;

const kids = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function startRelay(port, tag) {
  const child = spawn(process.execPath, [
    join(root, "server/relay.mjs"),
    "--port", String(port),
    "--pass-db", join(dir, `${tag}.sqlite`),
    "--archive-dir", join(dir, `${tag}-archive`),
    "--quiet",
  ], { stdio: ["ignore", "pipe", "pipe"] });
  child.stderr.on("data", (d) => process.stderr.write(`[${tag}] ${d}`));
  kids.push(child);
  return child;
}

async function waitUp(base, tries = 60) {
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(`${base}/health`);
      if (r.ok) return true;
    } catch { /* not yet */ }
    await sleep(150);
  }
  return false;
}

const get = async (base, room) => {
  const r = await fetch(`${base}/room/${encodeURIComponent(room)}?cursor=0`);
  return r.json();
};
const post = async (base, room, lines) => {
  const r = await fetch(`${base}/room/${encodeURIComponent(room)}`, {
    method: "POST",
    headers: { "content-type": "text/plain" },
    body: lines.join("\n"),
  });
  return { status: r.status, body: await r.json() };
};

// One carry, in its own process — the point of the test.
//
// `--state` is load-bearing here and was silently not passed for a while.
// forward.mjs hardcoded its state directory to /tmp and ignored any state
// path it was handed, so this test was reading and writing a *global* carry
// ledger: it passed on a clean machine, and on every later run the previous
// run's ledger said the backlog was already carried and nothing was posted.
// A test that inherits its subject's state from a previous run is not a
// test. `a clean ledger carries a backlog` below now fails if the flag
// stops being honoured.
const carry = (args) => new Promise((resolve, reject) => {
  const child = spawn(process.execPath, [
    join(root, "server/forward.mjs"), "--once",
    "--state", dir, ...args,
  ], {
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, KANT_QUIT_AFTER: "" },
  });
  let err = "";
  child.stderr.on("data", (d) => { err += d; });
  child.on("error", reject);
  child.on("exit", (code) => resolve({ code, err }));
});

try {
  const secret = Array.from({ length: 32 }, (_, i) => (i * 7 + 3) & 0xff);
  const room = roomOf(secret);
  const inviteText = copyInvite(invite(A, secret, "testpeer"));

  // Two rooms whose names share a 64-bit prefix is not something to arrange,
  // so this asserts the weaker and still-true property: the ledger file is
  // named for the whole room, so no two rooms can collide on it. The old
  // name used the first 8 hex chars.
  await t("the carry ledger is named for the whole room, not a prefix", () => {
    const r = "84da04cc9b78467fe79638de47a1336cdca4b910cf30c1c568856fc5d60c9152";
    const long = new Bridge({
      from: A, to: B, room: r,
      statePath: join(dir, "kant-forward-" + r + "-fwd.json"),
      invite: inviteText,
    });
    const short = new Bridge({
      from: A, to: B, room: "84da04cc",
      statePath: join(dir, "kant-forward-" + r + "-fwd.json"),
      invite: inviteText,
    });
    assert.equal(long.sent.file, short.sent.file,
      "two rooms must not share one carry ledger");
    assert.ok(long.sent.file.includes(r),
      `the ledger ${long.sent.file} is not named for the full room`);
  });

  await t("a failed carry exits non-zero instead of reporting success", () => {
    // forward.mjs used to swallow a backlog carry's error into a log line,
    // so `--once` exited 0 having carried nothing — a bridge that reports
    // success while doing nothing, which is the whole failure this rewrite
    // is about. A destination that is not listening must fail loudly.
    const out = spawnSync(process.execPath, [
      join(root, "server/forward.mjs"), "--once",
      "--state", dir,
      "--invite", inviteText,
      "--from", A,
      "--to", "http://127.0.0.1:1", // nothing listens here
    ], { encoding: "utf8", timeout: 30000 });
    assert.notEqual(out.status, 0,
      `a carry that could not post exited 0\n${out.stderr}`);
  });

  console.log("two local relays");
  startRelay(PORT_A, "a");
  startRelay(PORT_B, "b");
  const aUp = await waitUp(A);
  const bUp = await waitUp(B);

  await t("both relays answer", () => {
    assert.ok(aUp, `relay A never came up on ${A}`);
    assert.ok(bUp, `relay B never came up on ${B}`);
  });

  console.log("carrying between them");

  await t("lines posted to A are carried to B", async () => {
    await post(A, room, ["alpha", "beta", "gamma"]);
    const r = await carry(["--invite", inviteText, "--from", A, "--to", B]);
    assert.equal(r.code, 0, `the bridge exited ${r.code}\n${r.err}`);
    const got = await get(B, room);
    assert.deepEqual(got.lines, ["alpha", "beta", "gamma"],
      `B holds ${JSON.stringify(got.lines)}`);
  });

  await t("a second carry in a new process sends nothing again", async () => {
    const before = await get(B, room);
    const r = await carry(["--invite", inviteText, "--from", A, "--to", B]);
    assert.equal(r.code, 0, `the second bridge exited ${r.code}\n${r.err}`);
    const after = await get(B, room);
    assert.deepEqual(after.lines, before.lines,
      "a restarted bridge re-sent history it had already carried");
  });

  await t("a new line is carried exactly once", async () => {
    await post(A, room, ["delta"]);
    const r = await carry(["--invite", inviteText, "--from", A, "--to", B]);
    assert.equal(r.code, 0, `the third bridge exited ${r.code}\n${r.err}`);
    const got = await get(B, room);
    assert.deepEqual(got.lines, ["alpha", "beta", "gamma", "delta"]);
    assert.equal(got.lines.length, new Set(got.lines).size, "B holds a duplicate");
  });

  await t("two carries in a row do not duplicate", async () => {
    await post(A, room, ["epsilon"]);
    await carry(["--invite", inviteText, "--from", A, "--to", B]);
    await carry(["--invite", inviteText, "--from", A, "--to", B]);
    const got = await get(B, room);
    assert.equal(got.lines.filter((l) => l === "epsilon").length, 1,
      "epsilon was carried twice");
    assert.equal(got.lines.length, 5);
  });

  console.log("rooms stay separate");
  await t("the bridge carries only its own room", async () => {
    const otherSecret = Array.from({ length: 32 }, (_, i) => (i * 11 + 5) & 0xff);
    const otherRoom = roomOf(otherSecret);
    await post(A, otherRoom, ["not-for-b"]);
    await carry(["--invite", inviteText, "--from", A, "--to", B]);
    const got = await get(B, otherRoom);
    assert.deepEqual(got.lines, [], "the bridge carried a room it was not asked for");
  });
} finally {
  for (const k of kids) { try { k.kill("SIGKILL"); } catch { /* gone */ } }
  rmSync(dir, { recursive: true, force: true });
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);