// INT24b-01 CI test: SSRF via unvalidated relay URL.
// Asserts the patch is present: unsafe relays are refused, safe relays work.

import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const Net  = await import(resolve(here, "../web/kant-net.mjs"));
const Diag = await import(resolve(here, "../web/kant-diag.mjs"));

let passed = 0, failed = 0;
const check = (name, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  console.log(`  ${ok ? "ok  " : "FAIL"} ${name}`);
  if (ok) passed++; else { failed++; console.log(`        actual=${JSON.stringify(actual)} expected=${JSON.stringify(expected)}`); }
};

const SECRET = Array.from({ length: 32 }, (_, i) => (i * 7 + 3) & 0xff);
const mkInvite = (relay) => Net.copyInvite(Net.invite(relay, SECRET, "peer", []));
const mockFetch = (calls) => (url) => {
  calls.push(String(url));
  return Promise.resolve({ ok: true, status: 200, json: async () => ({ ok: true, name: "mock", version: "0" }) });
};

{
  const t = mkInvite("https://probe.example.com");
  const d = Net.pasteInvite(t);
  if (!d || d.relay !== "https://probe.example.com") {
    console.error("FATAL: invite roundtrip broken. Refusing to run.");
    process.exit(2);
  }
}

for (const [label, relay] of [
  ["metadata-IP",      "http://169.254.169.254/latest/meta-data/"],
  ["file-scheme",      "file:///etc/passwd"],
  ["gopher-scheme",    "gopher://127.0.0.1:6379/_INFO"],
  ["javascript-scheme","javascript:alert(1)"],
  ["data-scheme",      "data:text/plain,hi"],
  ["ipv6-link-local",  "http://[fe80::1]/"],
  ["multicast",        "http://224.0.0.1/"],
]) {
  const calls = [];
  const node = new Net.KantNode({ peer: "h", fetchImpl: mockFetch(calls) });
  let j = null;
  try { j = node.joinInvite(mkInvite(relay)); } catch (e) { j = { threw: e.message }; }
  check(`joinInvite(${label}) returns null`, j, null);
  check(`joinInvite(${label}) no client`, node.client === null, true);
  if (node.client) await node.client.health().catch(() => {});
  check(`joinInvite(${label}) no fetch`, calls.length, 0);
}

{
  const node = new Net.KantNode({ peer: "h", fetchImpl: mockFetch([]) });
  const j = node.joinInvite(mkInvite("https://relay.example.com"));
  check("joinInvite(https) accepted", j && j.relay, "https://relay.example.com");
}

{
  const node = new Net.KantNode({ peer: "h", fetchImpl: mockFetch([]) });
  const j = node.joinInvite(mkInvite("http://127.0.0.1:8787"));
  check("joinInvite(loopback dev) accepted", j && j.relay, "http://127.0.0.1:8787");
}

for (const [label, relay, expectOk] of [
  ["file",     "file:///etc/passwd",        false],
  ["metadata", "http://169.254.169.254/",   false],
  ["https",    "https://relay.example.com", true],
]) {
  const calls = [];
  const r = await Diag.probeRelay(relay, { fetchImpl: mockFetch(calls) });
  check(`probeRelay(${label}) ok`, r.ok, expectOk);
  check(`probeRelay(${label}) fetch-count`, calls.length, expectOk ? 1 : 0);
}

{
  let threw = false;
  try { new Net.RelayClient("file:///etc/passwd"); } catch { threw = true; }
  check("RelayClient(file) throws", threw, true);
}
{
  const calls = [];
  let threw = false;
  try { new Net.RelaySocket("file:///etc/passwd", "room", { WebSocketImpl: class { constructor(u) { calls.push(String(u)); } addEventListener(){} send(){} close(){} } }); } catch { threw = true; }
  check("RelaySocket(file) throws", threw, true);
  check("RelaySocket(file) no ws", calls.length, 0);
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
