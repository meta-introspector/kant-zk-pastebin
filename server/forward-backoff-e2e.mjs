// forward-backoff-e2e.mjs — the real forward.mjs, against a relay that
// refuses the way the free tier did.  Counts the requests that actually
// leave the process, because the unit tests only prove the arithmetic:
// what matters is that a dead relay is asked far fewer times.
//
// Both failure shapes from production are covered, because they are
// different bridges: the `back` bridge polls the *worker* as its source
// (1014+1042 failures in the journal), while the `fwd` bridge writes to
// it (1 failure).  A source that refuses is the expensive one.
//
//   node server/forward-backoff-e2e.mjs

import http from "node:http";
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import assert from "node:assert/strict";
import { witness } from "../web/kantzk.mjs";

const QUOTA_BODY = "Exceeded allowed duration in Durable Objects free tier.";

let pass = 0, fail = 0;
const t = async (name, fn) => {
  try { await fn(); console.log(`✔ ${name}`); pass++; }
  catch (e) { console.log(`✖ ${name}: ${e.message}`); fail++; }
};

const bytes = (s) => new TextEncoder().encode(s);
const room = witness(Array.from(bytes("e2e room line")));

/** `lines` is served once, then the room is empty and stays that way —
 *  the shape of a real room that has one message in it. */
function fakeRelay({ refuse = false, lines = [] } = {}) {
  const hits = { get: 0, post: 0 };
  let served = false;
  const srv = http.createServer((req, res) => {
    if (req.method === "POST") hits.post++;
    else hits.get++;
    if (refuse) {
      res.writeHead(500, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: false, error: QUOTA_BODY }));
      return;
    }
    if (req.method === "POST") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true, cursor: 1 }));
      return;
    }
    const out = served ? { ok: true, cursor: 1, lines: [] } : { ok: true, cursor: 1, lines };
    served = true;
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(out));
  });
  return {
    hits,
    listen: () => new Promise((r) => srv.listen(0, "127.0.0.1", () => r(srv.address().port))),
  };
}

/** A rooms dir with one room whose source has a line waiting. */
const roomDir = (opts = {}) => {
  const dir = mkdtempSync(join(tmpdir(), "kant-fwd-e2e-"));
  writeFileSync(join(dir, "room.json"), JSON.stringify({
    name: "e2e",
    invite: `https://x/#6b7a696e76697465:00:${Buffer.from("e2e room line").toString("hex")}:e2e`,
    ...opts,
  }));
  return dir;
};

const run = (argv, ms) =>
  new Promise((resolve) => {
    const p = spawn(process.execPath, ["server/forward.mjs", ...argv], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let out = "";
    p.stdout.on("data", (d) => { out += d; });
    p.stderr.on("data", (d) => { out += d; });
    setTimeout(() => { p.kill("SIGKILL"); resolve(out); }, ms);
  });

await t("a source stuck in the quota error is not hammered", async () => {
  // A 1s period: the old flat sleep would be ~1 request/second here, and
  // the 10s production setting was 360/hour per loop with nothing gained.
  const src = fakeRelay({ refuse: true });
  const dst = fakeRelay();
  const sp = await src.listen();
  const dp = await dst.listen();
  const dir = roomDir();
  const logs = await run([
    "--rooms", dir, "--state-dir", dir,
    "--default-from", `http://127.0.0.1:${sp}`,
    "--default-to", `http://127.0.0.1:${dp}`,
    "--interval", "1", "--wait", "0", "--max-interval", "8",
  ], 12000);
  rmSync(dir, { recursive: true, force: true });

  const total = src.hits.get + src.hits.post;
  assert.ok(total / 12 <= 1.0,
    `expected <=1 req/s against a refusing source, got ${(total / 12).toFixed(2)}/s (${total} in 12s)`);
  assert.ok(total < 12, `expected well under 12 requests, got ${total}`);
  assert.match(logs, /out of its Durable Objects duration budget/,
    "the log should name the cause, not just '500'");
  console.log(`    ${total} requests in 12s against a 500ing source`);
});

await t("a destination that refuses stops the line being carried", async () => {
  // The write-side shape: the source is fine, the destination is not.
  const src = fakeRelay({ lines: ["a line"] });
  const dst = fakeRelay({ refuse: true });
  const sp = await src.listen();
  const dp = await dst.listen();
  const dir = roomDir();
  const logs = await run([
    "--rooms", dir, "--state-dir", dir,
    "--default-from", `http://127.0.0.1:${sp}`,
    "--default-to", `http://127.0.0.1:${dp}`,
    "--interval", "1", "--wait", "0", "--once",
  ], 6000);
  rmSync(dir, { recursive: true, force: true });
  // The carry is what fails, so that is the line that must name the
  // cause: a bare "500" here is what left the bridge retrying blindly.
  assert.match(logs, /backlog carry failed/);
  assert.match(logs, /Exceeded allowed duration in Durable Objects free tier/,
    "the relay's own explanation should survive into the log");
  assert.doesNotMatch(logs, /carried \d+ line/, "nothing may claim to be carried");
});

await t("a refusing destination produces few log lines too", async () => {
  const src = fakeRelay({ refuse: true });
  const dst = fakeRelay();
  const sp = await src.listen();
  const dp = await dst.listen();
  const dir = roomDir();
  const logs = await run([
    "--rooms", dir, "--state-dir", dir,
    "--default-from", `http://127.0.0.1:${sp}`,
    "--default-to", `http://127.0.0.1:${dp}`,
    "--interval", "1", "--wait", "0", "--max-interval", "8",
  ], 20000);
  rmSync(dir, { recursive: true, force: true });
  const errs = logs.split("\n").filter((l) => l.includes("poll cycle failed")).length;
  assert.ok(errs <= 3, `a 20s outage should not print ${errs} error lines`);
  console.log(`    ${errs} error lines over a 20s outage`);
});

await t("a healthy pair still carries its line", async () => {
  const src = fakeRelay({ lines: ["a line"] });
  const dst = fakeRelay();
  const sp = await src.listen();
  const dp = await dst.listen();
  const dir = roomDir();
  const logs = await run([
    "--rooms", dir, "--state-dir", dir,
    "--default-from", `http://127.0.0.1:${sp}`,
    "--default-to", `http://127.0.0.1:${dp}`,
    "--interval", "1", "--wait", "0", "--once",
  ], 6000);
  rmSync(dir, { recursive: true, force: true });
  assert.doesNotMatch(logs, /failed/, `unexpected failure: ${logs}`);
  // The backlog carry is silent when it succeeds — only the poll loop
  // announces carried lines — so the destination is the real assertion.
  assert.equal(dst.hits.post, 1, "the line must reach the destination");
  assert.equal(src.hits.get, 1, "and the source should be read once");
});

await t("a 10s interval waits seconds, not milliseconds", async () => {
  // The bug this file exists to catch: the CLI speaks seconds, Backoff
  // speaks milliseconds, and passing the CLI value straight through
  // turned a 10s backoff into a 10ms one — a hot loop hammering a
  // refusing relay ~100x/second, far worse than the flat sleep it
  // replaced.  The unit tests could not see it; the request count can.
  const src = fakeRelay({ refuse: true });
  const dst = fakeRelay();
  const sp = await src.listen();
  const dp = await dst.listen();
  const dir = roomDir();
  const logs = await run([
    "--rooms", dir, "--state-dir", dir,
    "--default-from", `http://127.0.0.1:${sp}`,
    "--default-to", `http://127.0.0.1:${dp}`,
    "--interval", "10", "--wait", "0", "--max-interval", "600",
  ], 5000);
  rmSync(dir, { recursive: true, force: true });

  // One 10s period barely fits in 5s, so the source should be asked
  // once or twice.  A millisecond delay asks it hundreds of times.
  assert.ok(src.hits.get <= 3,
    `a 10s interval must not ask often, got ${src.hits.get} requests in 5s`);
  assert.match(logs, /not retrying for \d+s/,
    "the wait should be stated, so an outage reads as a wait not a fault");
  console.log(`    ${src.hits.get} requests in 5s at --interval 10`);
});

await t("the startup log states the pacing it will use", async () => {
  const src = fakeRelay();
  const dst = fakeRelay();
  const sp = await src.listen();
  const dp = await dst.listen();
  const dir = roomDir();
  const logs = await run([
    "--rooms", dir, "--state-dir", dir,
    "--default-from", `http://127.0.0.1:${sp}`,
    "--default-to", `http://127.0.0.1:${dp}`,
    "--interval", "30", "--wait", "10", "--max-interval", "600", "--once",
  ], 6000);
  rmSync(dir, { recursive: true, force: true });
  assert.match(logs, /polling every 30s, holding at most 10s, backing off to 600s/);
});

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
