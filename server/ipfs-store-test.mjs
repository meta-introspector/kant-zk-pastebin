// ipfs-store-test.mjs — the worker's IPFS routes and room routing, against
// the deployed worker, plus the refusals that keep the RPC surface small.
// Run from the repo root:
//
//   node server/ipfs-store-test.mjs
//
// The store is the Worker itself: there is no upstream kubo in the path,
// because solana.solfunmeme.com resolves publicly to a LAN address and
// Cloudflare's edge has no route to it (every proxied call returned
// 403/error 1002). The CID agreement check below loads the client's own
// `rawCidOf` rather than restating the algorithm, so client and store
// cannot drift apart silently.
//
// Set SKIP_BINDINGS=1 to skip the Cloudflare API checks (no token needed).
// Set CLOUDFLARE_API_TOKEN to enable them; it is read, never logged.

import assert from "node:assert/strict";

const UPSTREAM = process.env.IPFS_ORIGIN ?? "https://solana.solfunmeme.com";
const WORKER = process.env.WORKER_ORIGIN ?? "https://kant-relay-v1-dev.purple-fire-b881.workers.dev";

let pass = 0, fail = 0;
const t = async (name, fn) => {
  try { await fn(); console.log(`✔ ${name}`); pass++; }
  catch (e) { console.log(`✖ ${name}: ${e.message}`); fail++; }
};

/** The header shaping the proxy applies before calling kubo. */
function kuboHeaders(from = {}) {
  const h = new Headers();
  for (const k of ["content-type", "accept"]) if (from[k]) h.set(k, from[k]);
  h.set("user-agent", "kant-ipfs-proxy/1.0");
  h.delete("origin");
  h.delete("referer");
  h.delete("cookie");
  return h;
}

const rpc = (p, init = {}) =>
  fetch(`${UPSTREAM}/ipfs-rpc${p}`, { method: "POST", ...init, headers: kuboHeaders(init.headers) });

// ── the deployed worker IS the store ──────────────────────────────────────
//
// There is no upstream and no kubo: solana.solfunmeme.com resolves publicly
// to a LAN address, so a Worker cannot reach the local daemon. The store
// computes the CIDv1 raw sha2-256 itself, which must match what the client
// computes independently in kant-ipfs.mjs — that agreement is the whole
// contract, so it is checked against the client's own code here rather than
// against a kubo that is no longer in the path.

// ── the deployed worker ───────────────────────────────────────────────────

if (process.env.SKIP_WORKER) {
  console.log("(worker origin checks skipped)");
} else {
  await t("the deployed worker answers /health", async () => {
    const r = await fetch(`${WORKER}/health`);
    assert.equal(r.status, 200);
    assert.equal((await r.json()).ok, true);
  });

  await t("the store answers", async () => {
    const r = await fetch(`${WORKER}/ipfs-rpc/api/v0/version`, {
      method: "POST", headers: { origin: WORKER },
    });
    assert.equal(r.status, 200, "the store must answer");
  });

  await t("version is reachable — the capture's reachability probe", async () => {
    const r = await fetch(`${WORKER}/ipfs-rpc/api/v0/version`, {
      method: "POST", headers: { origin: WORKER },
    });
    assert.equal(r.status, 200);
    assert.match((await r.json()).Version, /^kant-ipfs/);
  });

  await t("add returns the SAME CIDv1 the client computes for itself", async () => {
    // Load the client's own implementation rather than restating the
    // algorithm, so this fails if either side drifts.
    const { rawCidOf } = await import("../web/kant-ipfs.mjs");
    const bytes = new TextEncoder().encode(`kant-worker-probe-${Date.now()}`);
    const fd = new FormData();
    fd.append("file", new Blob([bytes]), "chunk-0.bin");
    const r = await fetch(`${WORKER}/ipfs-rpc/api/v0/add?cid-version=1&raw-leaves=true&pin=true&quieter=true`,
      { method: "POST", body: fd, headers: { origin: WORKER } });
    const body = await r.text();
    assert.equal(r.status, 200, body);
    const { Hash } = JSON.parse(body.trim().split("\n").pop());
    assert.equal(Hash, await rawCidOf(bytes),
      "the worker and the client must agree on the CID or nothing can be fetched back");
  });

  await t("the gateway serves the chunk back byte-for-byte", async () => {
    const { rawCidOf } = await import("../web/kant-ipfs.mjs");
    const payload = `kant-gw-roundtrip-${Date.now()}`;
    const bytes = new TextEncoder().encode(payload);
    const fd = new FormData();
    fd.append("file", new Blob([bytes]), "chunk-0.bin");
    const add = await fetch(`${WORKER}/ipfs-rpc/api/v0/add?cid-version=1&raw-leaves=true&quieter=true`,
      { method: "POST", body: fd, headers: { origin: WORKER } });
    const { Hash } = JSON.parse((await add.text()).trim().split("\n").pop());
    assert.equal(Hash, await rawCidOf(bytes));
    const back = await fetch(`${WORKER}/ipfs-gw/ipfs/${Hash}`, { headers: { origin: WORKER } });
    assert.equal(back.status, 200);
    assert.equal(await back.text(), payload);
  });

  await t("cat over RPC returns the same bytes as the gateway", async () => {
    const bytes = new TextEncoder().encode(`kant-cat-${Date.now()}`);
    const fd = new FormData();
    fd.append("file", new Blob([bytes]), "c.bin");
    const add = await fetch(`${WORKER}/ipfs-rpc/api/v0/add?cid-version=1&raw-leaves=true&quieter=true`,
      { method: "POST", body: fd, headers: { origin: WORKER } });
    const { Hash } = JSON.parse((await add.text()).trim().split("\n").pop());
    const cat = await fetch(`${WORKER}/ipfs-rpc/api/v0/cat?arg=${Hash}`,
      { method: "POST", headers: { origin: WORKER } });
    assert.equal(await cat.text(), new TextDecoder().decode(bytes));
  });

  await t("the gateway refuses an absent CID", async () => {
    const r = await fetch(`${WORKER}/ipfs-gw/ipfs/bafkreigh2akiscaildc5absygw3rh6ky3ww5bsmtv7udyayemo5ak7dv7ysq`,
      { headers: { origin: WORKER } });
    assert.equal(r.status, 404, `expected 404, got ${r.status}`);
  });

  await t("the store refuses an unsanctioned kubo method", async () => {
    for (const m of ["config", "pin/add", "swarm/peering/list", "key/gen"]) {
      const r = await fetch(`${WORKER}/ipfs-rpc/api/v0/${m}`,
        { method: "POST", headers: { origin: WORKER } });
      assert.equal(r.status, 403, `${m} must not be served; got ${r.status}`);
    }
  });

  await t("the store refuses a cross-origin call", async () => {
    const r = await fetch(`${WORKER}/ipfs-rpc/api/v0/version`,
      { method: "POST", headers: { origin: "https://evil.example" } });
    assert.equal(r.status, 403, `cross-origin must be refused; got ${r.status}`);
  });

  await t("room routing works", async () => {
    const room = `kant-room-${Date.now()}`;
    const r0 = await fetch(`${WORKER}/room/${room}?cursor=0&wait=0`, { headers: { origin: WORKER } });
    assert.equal(r0.status, 200);
    const post = await fetch(`${WORKER}/room/${room}`, {
      method: "POST", body: "hello", headers: { origin: WORKER },
    });
    assert.equal(post.status, 200, await post.text());
    const back = await fetch(`${WORKER}/room/${room}?cursor=0&wait=0`, { headers: { origin: WORKER } });
    const j = await back.json();
    assert.ok(j.lines.includes("hello"), "the line must come back");
  });

  await t("a long poll returns, and does not hold the room past MAX_HOLD", async () => {
    // MAX_HOLD is the ceiling on `wait`. Asking for 600 must not park a
    // request for 600s: resident is what the DO free tier bills, so an
    // unbounded long poll is a billing bug, not a feature.
    const room = `kant-hold-${Date.now()}`;
    const t0 = Date.now();
    const r = await fetch(`${WORKER}/room/${room}?cursor=0&wait=600`,
      { headers: { origin: WORKER }, signal: AbortSignal.timeout(45_000) });
    const ms = Date.now() - t0;
    assert.equal(r.status, 200);
    assert.ok(ms < 20_000, `the capped long poll took ${ms}ms; it must not honour wait=600`);
  });

  await t("two room names are two rooms", async () => {
    // If the router collapsed every room onto one object, this would fail.
    // It is the cheapest guard against a wrong idFromName argument.
    const stamp = Date.now();
    const a = `kant-iso-a-${stamp}`, b = `kant-iso-b-${stamp}`;
    await fetch(`${WORKER}/room/${a}`, { method: "POST", body: "only-a", headers: { origin: WORKER } });
    const jb = await (await fetch(`${WORKER}/room/${b}?cursor=0&wait=0`, { headers: { origin: WORKER } })).json();
    assert.deepEqual(jb.lines, [], "room b must not see room a's line");
  });
}

// ── bindings: the DO must be there, and it must be the only state ─────────
//
// These are what decide cross-PoP correctness, and they are invisible from
// the HTTP surface: an isolate-local Map passes every other check in this
// file. So they are asserted against the deployed script's bindings.
if (process.env.SKIP_BINDINGS) {
  console.log("(binding checks skipped)");
} else {
  const TOKEN = process.env.CLOUDFLARE_API_TOKEN;
  const ACCOUNT = process.env.CLOUDFLARE_ACCOUNT_ID ?? "2c5da35f915a13c131bead97f3f7bc75";
  const NAME = new URL(WORKER).hostname.replace(/\..*$/, "");

  const bindings = async () => {
    if (!TOKEN) throw new Error("set CLOUDFLARE_API_TOKEN, or SKIP_BINDINGS=1");
    const r = await fetch(
      `https://api.cloudflare.com/client/v4/accounts/${ACCOUNT}/workers/services/${NAME}/environments/production/bindings`,
      { headers: { authorization: `Bearer ${TOKEN}` } });
    const j = await r.json();
    if (!r.ok) throw new Error(`bindings API: ${r.status} ${JSON.stringify(j.errors ?? j)}`);
    return j.result ?? j;
  };

  await t("the ROOMS Durable Object namespace is deployed", async () => {
    const list = await bindings();
    const dos = (list.bindings ?? list).filter((b) => b.type === "durable_object_namespace");
    const names = dos.map((b) => b.name);
    assert.ok(names.includes("ROOMS"),
      `ROOMS must be bound so two PoPs share one room; found ${JSON.stringify(names)}`);
  });

  await t("the BLOBS Durable Object namespace is deployed", async () => {
    const list = await bindings();
    const dos = (list.bindings ?? list).filter((b) => b.type === "durable_object_namespace");
    const names = dos.map((b) => b.name);
    assert.ok(names.includes("BLOBS"),
      `BLOBS must be bound so a chunk is not per-PoP; found ${JSON.stringify(names)}`);
  });

  await t("no KV or R2: those need a token scope we do not have", async () => {
    const list = await bindings();
    const kinds = new Set((list.bindings ?? list).map((b) => b.type));
    assert.ok(!kinds.has("kv_namespace"), "KV needs its own token scope; keep the DOs");
    assert.ok(!kinds.has("r2_bucket"), "R2 needs its own token scope; keep the DOs");
  });
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
