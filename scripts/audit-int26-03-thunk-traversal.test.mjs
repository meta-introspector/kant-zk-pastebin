// INT26-03 CI test: ThunkStore.#path refuses unsafe ids.
// Asserts the patch is present: all unsafe ids rejected, safe ids accepted.

import { mkdtempSync, writeFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const { ThunkStore } = await import(resolve(here, "../server/thunk-store.mjs"));

let passed = 0, failed = 0;
const check = (name, actual, expected) => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  console.log(`  ${ok ? "ok  " : "FAIL"} ${name}`);
  if (ok) passed++; else { failed++; console.log(`        actual=${JSON.stringify(actual)} expected=${JSON.stringify(expected)}`); }
};

const storeDir = mkdtempSync(join(tmpdir(), "int26-ci-"));

// 1. store() write traversal refused
{
  const escapeId = `../int26-ci-escape-${process.pid}`;
  const outsidePath = join(storeDir, "..", `${escapeId}.json`);
  try { rmSync(outsidePath, { force: true }); } catch {}
  const store = new ThunkStore(storeDir);
  const fakeThunk = {
    id: escapeId, name: "escape", version: "1.0.0",
    source: "module.exports = {};",
    snapshot: () => ({}), manifest: () => ({}),
  };
  let threw = false;
  try { store.store(fakeThunk); } catch { threw = true; }
  check("store(../escape) refused", threw, true);
  check("store(../escape) did not write outside", existsSync(outsidePath), false);
  try { rmSync(outsidePath); } catch {}
}

// 2. get() read traversal refused
{
  const markerName = `int26-ci-marker-${process.pid}`;
  const markerPath = join(storeDir, "..", `${markerName}.json`);
  writeFileSync(markerPath, JSON.stringify({
    definition: { name: "leaked", version: "0.0.0",
      source: "module.exports = { initialState: {}, reduce: function(s, i) { return s; } };" },
    state: {}, createdAt: 1234567890,
  }), "utf8");
  const store = new ThunkStore(storeDir);
  let threw = false, loaded = null;
  try { loaded = await store.get(`../${markerName}`); } catch { threw = true; }
  check("get(../marker) refused", threw || loaded === null, true);
  try { rmSync(markerPath, { force: true }); } catch {}
}

// 3. unsafe ids refused
{
  const store = new ThunkStore(storeDir);
  const unsafeIds = [
    "../etc/passwd", "../../tmp/pwn", "/etc/passwd", "a/../b",
    "..", ".", "", "../../x@1.0.0:hash", "a\\b", "a%2F..", "...", "....",
  ];
  for (const bad of unsafeIds) {
    let threw = false;
    try {
      store.store({ id: bad, name: "x", version: "1", source: "", snapshot: () => ({}) });
    } catch { threw = true; }
    check(`store(${JSON.stringify(bad)}) refused`, threw, true);
  }
}

// 4. safe ids still accepted
{
  const store = new ThunkStore(storeDir);
  const safeIds = [
    "counter@0.0.0:" + "a".repeat(64),
    "thunk.v1@1.2.3:abc123",
    "a_b-c.d@0.0.0:h",
    "x@1:y",
  ];
  for (const good of safeIds) {
    let threw = false;
    try {
      store.store({ id: good, name: "x", version: "1", source: "", snapshot: () => ({}) });
    } catch { threw = true; }
    check(`store(${JSON.stringify(good)}) accepted`, threw, false);
  }
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
