// INT41-01 CI test: decryptFile bounds manifest.size
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const SRC = resolve(here, "../web/kant-file.mjs");
const mod = await import(SRC);
const { decryptFile, CHUNK_SIZE } = mod;

let passed = 0, failed = 0;
const check = (name, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  console.log(`  ${ok ? "ok  " : "FAIL"} ${name}`);
  if (ok) passed++; else { failed++; console.log(`        actual=${JSON.stringify(actual)} expected=${JSON.stringify(expected)}`); }
};

const fakeChunk = () => new Uint8Array(16);
const STRICT = /invalid manifest size/i;

{
  const m = { size: 2**31 - 1, nonce: Array(12).fill(0), cids: ["a".repeat(64)] };
  let threw = false, err = null;
  try { await decryptFile([1,2,3], m, () => fakeChunk()); } catch (e) { threw = true; err = e.message; }
  check("2GB size rejected", threw, true);
  check("2GB error is invalid manifest size", STRICT.test(err || ""), true);
}
{
  const m = { size: -1, nonce: Array(12).fill(0), cids: ["a".repeat(64)] };
  let threw = false, err = null;
  try { await decryptFile([1,2,3], m, () => fakeChunk()); } catch (e) { threw = true; err = e.message; }
  check("-1 size rejected", threw, true);
  check("-1 error is invalid manifest size", STRICT.test(err || ""), true);
}
{
  const m = { size: 100, nonce: Array(12).fill(0), cids: [] };
  let threw = false, err = null;
  try { await decryptFile([1,2,3], m, () => fakeChunk()); } catch (e) { threw = true; err = e.message; }
  check("empty cids rejected", threw, true);
  check("empty cids error is invalid manifest size", STRICT.test(err || ""), true);
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
