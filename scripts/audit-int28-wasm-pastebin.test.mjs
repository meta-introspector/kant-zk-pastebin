// INT28 CI test: wasm-pastebin-worker.mjs
// Covers INT28-01 (body limit), INT28-02 (escapeHtml+JSON.stringify),
// INT28-03 (route matching).

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const SRC_FILE = resolve(here, "../server/wasm-pastebin-worker.mjs");

// Mock WebAssembly before importing worker
globalThis.WebAssembly = {
  instantiate: async () => ({ exports: {
    paste_create: () => ({ id: "abc123", url: "/paste/abc123", cid: "bafy", witness: "w" }),
    paste_get: (id) => ({ id, title: "t", content: "c" }),
    paste_browse: () => [],
  }}),
  Module: class {}, Instance: class {},
};
globalThis.fetch = async (url) => {
  if (String(url).includes(".wasm")) {
    return { ok: true, arrayBuffer: async () => new Uint8Array([0,97,115,109]).buffer };
  }
  return { ok: false, status: 404 };
};

const mod = await import(SRC_FILE);
const worker = mod.default;

const mockEnv = {
  WASM_KV: { get: async () => null, put: async () => {} },
  ASSETS: { fetch: async () => ({ arrayBuffer: async () => new Uint8Array([0,97,115,109]).buffer }) },
};

function req(method, path, opts = {}) {
  const headers = new Map(Object.entries(opts.headers || {}));
  return {
    method,
    url: `https://example.com${path}`,
    headers: { get: (k) => headers.get(k.toLowerCase()) || null },
    json: async () => (opts.jsonBody ? JSON.parse(opts.jsonBody) : {}),
  };
}

let passed = 0, failed = 0;
const check = (name, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  console.log(`  ${ok ? "ok  " : "FAIL"} ${name}`);
  if (ok) passed++;
  else { failed++; console.log(`        actual=${JSON.stringify(actual)} expected=${JSON.stringify(expected)}`); }
};

// INT28-01: body limit
{
  const big = "x".repeat(2 * 1024 * 1024);
  const body = JSON.stringify({ content: big, title: "t" });
  const r = await worker.fetch(req("POST", "/api/paste", { jsonBody: body }), mockEnv);
  check("INT28-01 POST 2MB content rejected 413", r.status, 413);
}
{
  const headers = { "content-length": String(2 * 1024 * 1024) };
  const body = JSON.stringify({ content: "small", title: "t" });
  const r = await worker.fetch(req("POST", "/api/paste", { headers, jsonBody: body }), mockEnv);
  check("INT28-01 POST 2MB content-length rejected 413", r.status, 413);
}
{
  const headers = { "content-length": "100" };
  const body = JSON.stringify({ content: "hello", title: "t" });
  const r = await worker.fetch(req("POST", "/api/paste", { headers, jsonBody: body }), mockEnv);
  check("INT28-01 POST small body OK 200", r.status, 200);
}

// INT28-03: route matching
{
  const r = await worker.fetch(req("GET", "/paste?id=abc123"), mockEnv);
  check("INT28-03 GET /paste?id= reaches handler", r.status !== 404, true);
}
{
  const r = await worker.fetch(req("GET", "/paste/abc123"), mockEnv);
  check("INT28-03 GET /paste/X reaches handler", r.status !== 404, true);
}
{
  const r = await worker.fetch(req("GET", "/raw?id=abc123"), mockEnv);
  check("INT28-03 GET /raw?id= reaches handler", r.status !== 404, true);
}
{
  const r = await worker.fetch(req("GET", "/raw/abc123"), mockEnv);
  check("INT28-03 GET /raw/X reaches handler", r.status !== 404, true);
}

// INT28-02: source-level checks (escapeHtml + JSON.stringify)
{
  const src = readFileSync(SRC_FILE, "utf8");
  check("INT28-02 escapeHtml escapes apostrophe",
    /replace\(\s*\/'\//.test(src) || /&#39;/.test(src) || /&apos;/.test(src), true);
  check("INT28-02 uses JSON.stringify for paste.id in onclick",
    /JSON\.stringify\(\s*paste\.id/.test(src), true);
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
