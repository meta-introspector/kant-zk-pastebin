// crosspop-test.mjs — is the relay ONE store worldwide, or one per PoP?
//
// This is the test that matters most for a p2p relay, and it cannot be done
// with a direct request. Every request from one machine pins to one Cloudflare
// PoP (mine is EWR), so a room and a blob both read back perfectly — whether
// they are Durable Objects or plain per-isolate Maps. An isolate-local Map
// passes every other test in this repo and fails silently in production, when
// two peers in Frankfurt and Sao Paulo meet, find different rooms, and each
// sees an empty log.
//
// So the check leaves the PoP. The worker echoes `pop` (request.cf.colo) in
// every room read, which makes the proof self-contained: write from one PoP,
// read from another, and each response names where it was served. A remote
// read that returns `pop: MIA` and carries the line written at `pop: EWR` is
// one shared object; the same read at `pop: EWR` proves nothing, and is
// reported as UNPROVEN rather than passed.
//
//   node server/crosspop-test.mjs
//
// The vantage point is a generic HTTP proxy, because this machine has only one
// route to the internet. Point HOP_URL at any proxy that will GET a full URL
// and return the body ({url} is substituted, URL-encoded) to use a different
// one. If none can be reached the file reports UNPROVEN and exits non-zero:
// an untested cross-PoP claim is not a passing claim.

import assert from "node:assert/strict";

const WORKER = process.env.WORKER_ORIGIN ?? "https://kant-relay-v1-dev.purple-fire-b881.workers.dev";

let pass = 0, fail = 0, unclear = 0;
const t = async (name, fn) => {
  try { await fn(); console.log(`✔ ${name}`); pass++; }
  catch (e) {
    if (e.unproven) { console.log(`? ${name}: ${e.message}`); unclear++; }
    else { console.log(`✖ ${name}: ${e.message}`); fail++; }
  }
};

const UNPROVEN = (why) => Object.assign(new Error(why), { unproven: true });

/** Generic proxies, so one outage does not hide the result. */
const HOPS = [
  ["allorigins",      (u) => `https://api.allorigins.win/raw?url=${encodeURIComponent(u)}`],
  ["allorigins-get",  (u) => `https://api.allorigins.win/get?url=${encodeURIComponent(u)}`],
  ["corsproxy",       (u) => `https://corsproxy.io/?url=${encodeURIComponent(u)}`],
  ["codetabs",        (u) => `https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(u)}`],
  ["whateverorigin",  (u) => `https://www.whateverorigin.org/get?url=${encodeURIComponent(u)}`],
  ["cors-anywhere",   (u) => `https://cors-anywhere.herokuapp.com/${u}`],
];
if (process.env.HOP_URL) {
  const custom = process.env.HOP_URL;
  HOPS.unshift(["HOP_URL", (u) => custom.includes("{url}") ? custom.replace("{url}", encodeURIComponent(u)) : custom + u]);
}

/**
 * Fetch a URL from outside this machine's PoP.
 *
 * `want` decides whether a response is usable: a proxy that fails returns an
 * HTML error page with status 200, which would otherwise be read as data.
 * These are free public services and they rate-limit, so each is tried twice.
 */
async function offPop(url, want = (b) => b.trim().startsWith("{")) {
  for (const [name, wrap] of HOPS) {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const r = await fetch(wrap(url), {
          headers: { "user-agent": "kant-crosspop/1.0" },
          signal: AbortSignal.timeout(30_000),
        });
        const body = await r.text();
        if (r.ok && want(body)) return { hop: name, body };
      } catch { /* rate-limited or down; try again, then the next one */ }
      await new Promise((r2) => setTimeout(r2, 1500));
    }
  }
  return null;
}

const stamp = Date.now();
const room = `crosspop-${stamp}`;
const line = `written-here-${stamp}`;
const bytes = new TextEncoder().encode(`crosspop-blob-${stamp}`);

await t("the worker reports which PoP served it", async () => {
  const j = await (await fetch(`${WORKER}/room/po-probe-${stamp}?cursor=0&wait=0`)).json();
  assert.ok(j.pop && j.pop !== "unknown",
    "/room reads must carry request.cf.colo, or this file cannot prove anything");
  console.log(`  (this machine is served from ${j.pop})`);
});

await t("a line written here is readable from another PoP", async () => {
  const post = await fetch(`${WORKER}/room/${room}`, { method: "POST", body: line });
  assert.equal(post.status, 200, await post.text());
  const here = await (await fetch(`${WORKER}/room/${room}?cursor=0&wait=0`)).json();
  assert.ok(here.lines.includes(line), "the write must be visible here first");

  const got = await offPop(`${WORKER}/room/${room}?cursor=0&wait=0`);
  if (!got) throw UNPROVEN("no vantage point outside this PoP could be reached");

  const there = JSON.parse(got.body);
  if (there.pop === here.pop) {
    throw UNPROVEN(`both reads landed on ${there.pop}: one isolate, so this proves nothing`);
  }
  assert.ok(there.lines.includes(line),
    `a peer at ${there.pop} did not see the line written at ${here.pop} — the store is per-PoP`);
  console.log(`  (wrote at ${here.pop}, read at ${there.pop} via ${got.hop})`);
});

await t("a block written here is readable from another PoP", async () => {
  // The client's own CID, so a mismatch is a real disagreement between the
  // store and the client rather than two different but self-consistent hashes.
  const { rawCidOf } = await import("../web/kant-ipfs.mjs");
  const cid = await rawCidOf(bytes);
  const fd = new FormData();
  fd.append("file", new Blob([bytes]), "c.bin");
  const add = await fetch(`${WORKER}/ipfs-rpc/api/v0/add?cid-version=1&raw-leaves=true&quieter=true`,
    { method: "POST", body: fd, headers: { origin: WORKER } });
  assert.equal(add.status, 200, await add.text());

  // The gateway returns octets, not JSON, so accept anything that is not HTML.
  const got = await offPop(`${WORKER}/ipfs-gw/ipfs/${cid}`, (b) => !b.trimStart().startsWith("<"));
  if (!got) throw UNPROVEN("no vantage point could read the gateway");

  assert.equal(got.body, new TextDecoder().decode(bytes),
    "the block must come back byte-for-byte from outside this PoP");
  console.log(`  (read via ${got.hop})`);
});

console.log(`\n${pass} passed, ${fail} failed${unclear ? `, ${unclear} unproven` : ""}`);
if (unclear) console.log("unproven is not passing: the cross-PoP claim still needs a vantage point");
process.exit(fail || unclear ? 1 : 0);