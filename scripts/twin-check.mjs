#!/usr/bin/env node
// twin-check.mjs — assert the relay twins are actually in sync.
//
// The systemd twin and the Cloudflare Worker speak one protocol but are
// deployed independently, so nothing stops one from going stale. That
// happened silently: both answered version "1.0.0" while serving different
// copies of the wasm core, and a peer publishing through one twin would
// compute a CID the other twin could not reproduce.
//
// This checks the two things that actually have to agree:
//
//   1. both /health endpoints answer and name the commit they serve;
//   2. the wasm core is byte-identical on both legs.
//
// Usage:
//   node scripts/twin-check.mjs [--systemd http://127.0.0.1:8796]
//                              [--cloudflare https://<worker>.workers.dev]
//                              [--allow-drift]        # warn, exit 0
//   KANT_COMMIT_EXPECTED=<sha>  additionally require that exact commit
//
// Exit 0 = twins agree, 1 = drift (or unreachable), 2 = bad usage.

import { createHash } from "node:crypto";

const args = process.argv.slice(2);
const arg = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};

const SYSTEMD = arg("--systemd", process.env.KANT_SYSTEMD_RELAY ?? "http://127.0.0.1:8796");
const CLOUDFLARE = arg(
  "--cloudflare",
  process.env.KANT_CF_RELAY ?? "https://kant-zk-relay-wasm.purple-fire-b881.workers.dev",
);
const ALLOW_DRIFT = args.includes("--allow-drift");
const EXPECTED = process.env.KANT_COMMIT_EXPECTED ?? "";

const problems = [];
const notes = [];
const say = (msg) => console.log(msg);

async function getJson(url, timeoutMs = 20000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: ctrl.signal });
    const body = await res.text();
    if (!res.ok) throw new Error(`HTTP ${res.status}: ${body.slice(0, 120)}`);
    return JSON.parse(body);
  } finally {
    clearTimeout(t);
  }
}

async function sha256(url, timeoutMs = 60000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: ctrl.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const buf = Buffer.from(await res.arrayBuffer());
    return { hash: createHash("sha256").update(buf).digest("hex"), bytes: buf.length };
  } finally {
    clearTimeout(t);
  }
}

const twins = [
  ["systemd", SYSTEMD],
  ["cloudflare", CLOUDFLARE],
];

say("== relay twins ==");
const health = {};
for (const [name, base] of twins) {
  try {
    const h = await getJson(`${base.replace(/\/$/, "")}/health`);
    health[name] = h;
    say(`  ${name.padEnd(11)} ok commit=${h.commit || "(none)"} platform=${h.platform || "?"}`);
    if (!h.ok) problems.push(`${name}: /health reports ok=${h.ok}`);
    if (!h.commit) {
      problems.push(
        `${name}: /health reports no commit — cannot tell which build this is (redeploy with the commit stamped)`,
      );
    }
  } catch (e) {
    problems.push(`${name}: /health unreachable at ${base} — ${e.message}`);
    say(`  ${name.padEnd(11)} UNREACHABLE ${e.message}`);
  }
}

// Both twins answered: their commits must match.
const named = Object.entries(health).filter(([, h]) => h.commit);
if (named.length === 2) {
  const [[aName, a], [bName, b]] = named;
  if (a.commit === b.commit) {
    say(`  commits agree: ${a.commit}`);
  } else {
    problems.push(
      `commit drift: ${aName}=${a.commit} ${bName}=${b.commit} — one twin is stale, redeploy it`,
    );
  }
}

if (EXPECTED && named.length) {
  const stale = named.filter(([, h]) => h.commit !== EXPECTED);
  if (stale.length) {
    problems.push(
      `expected commit ${EXPECTED} but ${stale.map(([n]) => n).join(", ")} serve(s) something else`,
    );
  }
}

say("== wasm core ==");
const wasm = {};
for (const [name, base] of twins) {
  const url = `${base.replace(/\/$/, "")}/pastebin_wasm_bg.wasm`;
  try {
    const w = await sha256(url);
    wasm[name] = w;
    say(`  ${name.padEnd(11)} ${w.bytes} bytes  ${w.hash.slice(0, 16)}`);
  } catch (e) {
    problems.push(`${name}: wasm core not served at ${url} — ${e.message}`);
    say(`  ${name.padEnd(11)} MISSING ${e.message}`);
  }
}

const namedWasm = Object.entries(wasm);
if (namedWasm.length === 2) {
  const [[aName, a], [bName, b]] = namedWasm;
  if (a.hash === b.hash) {
    say(`  wasm identical on both twins`);
  } else {
    // Not fatal on its own: peers only care that CIDs agree. Flag it loudly
    // anyway, because it means the twins were built from different sources.
    problems.push(
      `wasm drift: ${aName}=${a.hash.slice(0, 12)} (${a.bytes}B) ${bName}=${b.hash.slice(0, 12)} (${b.bytes}B) — redeploy the stale leg`,
    );
  }
}

if (notes.length) {
  say("");
  for (const n of notes) say(`note: ${n}`);
}

say("");
if (problems.length === 0) {
  say(`OK — twins agree on commit${namedWasm.length === 2 ? " and wasm" : ""}`);
  process.exit(0);
}

say(`${problems.length} problem(s):`);
for (const p of problems) say(`  - ${p}`);
if (ALLOW_DRIFT) {
  say("\n--allow-drift: reporting as warnings, exiting 0");
  process.exit(0);
}
process.exit(1);
