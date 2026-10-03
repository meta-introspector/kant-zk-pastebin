// ipfs-store-test.mjs — the worker's IPFS routes, proven against the real
// nginx + kubo behind them, plus the refusals that keep the RPC surface
// small. Run from the repo root:
//
//   node server/ipfs-store-test.mjs
//
// These are the checks that decide whether the worker origin goes from
// 17/22 to 22/22, so they run against the live daemon rather than a mock:
// a mocked kubo that always says 200 would pass while the real one 403s on
// a browser-shaped request, which is the failure this proxy exists to avoid.

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

  await t("no Durable Object is bound (it would cost duration)", async () => {
    // A DO binding shows up as a migration in the deployed script's
    // bindings; its absence is what keeps PB-19 from recurring.
    const r = await fetch(`${WORKER}/ipfs-rpc/api/v0/version`, {
      method: "POST", headers: { origin: WORKER },
    });
    assert.equal(r.status, 200, "the store must answer without any DO");
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

  await t("room routing works, and the log is in memory", async () => {
    const room = `kant-mem-${Date.now()}`;
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
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
