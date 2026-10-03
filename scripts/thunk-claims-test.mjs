// thunk-claims-test.mjs — the claim ledger is only worth having if it can fail.
//
// A checker that always passes and a checker that is right look identical from
// the outside. So this file does two things: it asserts every claim still holds
// against the real tree, and for the claims whose probe is a pure function over
// a string, it feeds in a deliberately broken input and asserts the claim goes
// red. A probe that cannot be made to fail is not a probe.
//
// No network. scripts/relay-telemetry.mjs only runs its collector when invoked
// directly, so importing readBudget() here costs nothing.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { CLAIMS, evaluate, resolveInput, runClaims } from "./thunk-claims.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (p, enc = "utf8") => readFileSync(resolve(ROOT, p), enc);
// A default parameter also fires on an explicit `undefined`, which is how the
// binary claims kept arriving as strings.
const readBin = (p) => readFileSync(resolve(ROOT, p));
/** The real input for a claim, in the encoding that claim expects. */
const inputOf = async (id) => {
  const c = claim(id);
  return c.input.binary ? readBin(c.input.path) : await resolveInput(c.input);
};

let pass = 0, fail = 0;
const failures = [];
const tests = [];
const t = (name, fn) => tests.push([name, fn]);
const claim = (id) => {
  const c = CLAIMS.find((x) => x.id === id);
  if (!c) throw new Error(`no claim ${id}`);
  return c;
};

// ── the ledger itself ───────────────────────────────────────────

t("every claim id is unique and every claim names the doc it backs", () => {
  const ids = CLAIMS.map((c) => c.id);
  const dupes = ids.filter((id, i) => ids.indexOf(id) !== i);
  if (dupes.length) throw new Error(`duplicate ids: ${dupes.join(", ")}`);
  for (const c of CLAIMS) {
    if (!c.doc) throw new Error(`${c.id} does not say which doc it backs`);
    if (!c.claim) throw new Error(`${c.id} has no claim text`);
  }
});

t("every claim still holds against the tree", async () => {
  const rows = await runClaims();
  const bad = rows.filter((r) => !r.ok);
  if (bad.length) {
    throw new Error(
      bad.map((b) => `${b.id}: expected ${JSON.stringify(b.expect)}, got ${JSON.stringify(b.observed)}`).join("; "));
  }
  // The ledger is the thing that stops a doc outliving the code, so it is worth
  // failing loudly if claims get deleted to make it green again.
  if (rows.length < 20) throw new Error(`only ${rows.length} claims — has the ledger been truncated?`);
});

// ── the checker can fail ────────────────────────────────────────
//
// Each of these feeds the real probe an input that should break it. If the
// claim stays green the probe is not testing anything.

const mustFlip = async (id, brokenInput, why) => {
  const c = claim(id);
  const before = await evaluate(c, await resolveInput(c.input));
  if (!before.ok) throw new Error(`${id} does not hold in the first place`);
  const after = await evaluate(c, brokenInput);
  if (after.ok) throw new Error(`${id} still passed on ${why}`);
};

t("thunk-id-truncated goes red when the truncation is removed", () =>
  mustFlip("thunk-id-truncated", read("server/thunk.mjs").replace(/\.slice\(0,\s*16\)/, ".slice(0, 64)"),
    "a full-length hash"));

t("apply-unwraps goes red when the transducer is called as a method", () =>
  // Calling it as `transducers.reduce(...)` binds `this` to the host-side
  // object, which is a realm bridge back into the host global. The claim is
  // about the call being unqualified, so the mutation puts the method call back.
  mustFlip("apply-unwraps",
    read("server/thunk.mjs").replace("const { reduce } = this.#compiled.transducers;",
                                      "const reduce = this.#compiled.transducers.reduce.bind(null);"),
    "a bound call site"));

t("sandbox-has-no-require goes red when createRequire comes back", () =>
  mustFlip("sandbox-has-no-require",
    read("server/thunk.mjs").replace("const vm = await import(\"node:vm\");",
      "const vm = await import(\"node:vm\");\n  const { createRequire } = await import(\"node:module\");"),
    "a createRequire in the loader"));

t("sandbox-refuses-console goes red when console is left in place", () =>
  mustFlip("sandbox-refuses-console",
    read("server/thunk.mjs").replace(/try \{ delete globalThis\.console; \} catch \(e\) \{\}/, ""),
    "an un-deleted console"));

t("sandbox-refuses-dynamic-import goes red when the guard is removed", () =>
  mustFlip("sandbox-refuses-dynamic-import",
    read("server/thunk.mjs").replace(/const forbidden = source\.match\([\s\S]*?\);/, "const forbidden = null;"),
    "no load-time import guard"));

t("snapshot-deep-copies goes red when snapshot stops copying", () =>
  mustFlip("snapshot-deep-copies",
    read("server/thunk.mjs").replace(/JSON\.parse\(JSON\.stringify\(/, "(() => "),
    "a snapshot that returns live state"));

t("schedule-has-no-constraint goes red once a budget appears", () =>
  mustFlip("schedule-has-no-constraint", read("server/schedule.mjs") + "\nconst budget = 100;\n",
    "a budget in the scheduler"));

t("schedule-api goes red when a method is removed", () =>
  mustFlip("schedule-api", read("server/schedule.mjs").replace(/\btick\b/g, "noTick"),
    "a scheduler without tick()"));

t("ipdl-ref-three-sites goes red on a fourth site", () =>
  mustFlip("ipdl-ref-three-sites", read("scripts/kant-codec.mjs") + "\nconst IPDL_REF = null;\n",
    "a fourth IPDL_REF"));

t("ref-never-resolved goes red once a resolver is called", () =>
  mustFlip("ref-never-resolved", "const x = resolveRef(target);\n", "a call to a resolver"));

t("flake-inputs-sha-pinned goes red on a branch input", () =>
  mustFlip("flake-inputs-sha-pinned",
    read("flake.nix").replace(/nixpkgs\.url\s*=\s*"[^"]+"/, 'nixpkgs.url = "github:NixOS/nixpkgs/master"'),
    "a branch instead of a sha"));

t("nora-wildcard-version goes red once the version is pinned", () =>
  mustFlip("nora-wildcard-version",
    read("Cargo.toml").replace(/(rust-unixfs\s*=\s*\{[^}]*version\s*=\s*)"\*"/, '$1"0.1.2"'),
    "a pinned version"));

t("kernel-bytes goes red on a different-sized module", async () =>
  mustFlip("kernel-bytes", Buffer.concat([await inputOf("kernel-bytes"), Buffer.from([0])]),
    "an 800-byte module"));

t("kernel-imports-zero goes red when there is an import", async () => {
  const counter = moduleWithOneImport();
  const mod = new WebAssembly.Module(counter);
  const imports = WebAssembly.Module.imports(mod);
  // Without this the mutation could pass because the counter-example is not a
  // valid module at all, and "the probe threw" looks identical to "the probe
  // saw an import". The first draft of this test had exactly that bug.
  if (imports.length !== 1) throw new Error(`counter-example has ${imports.length} imports`);
  const after = await evaluate(claim("kernel-imports-zero"), counter);
  if (after.ok) throw new Error("kernel-imports-zero passed on a module with an import");
});

t("wasm-test-reads-gitignored-dist goes red once dist is tracked", () =>
  mustFlip("wasm-test-reads-gitignored-dist",
    { test: read("web/wasm-test.mjs"), ignore: read(".gitignore").replace(/^dist\/?$/gm, "  ") },
    "a .gitignore that no longer ignores dist"));

/**
 * A minimal valid wasm module with exactly one import (`env.abort`) and one
 * export. Assembled by hand because there is no wat2wasm here and adding a
 * dependency to prove one byte differs would be the wrong trade — so the
 * section sizes are computed rather than written, and the caller asserts the
 * module really has one import.
 */
function moduleWithOneImport() {
  const str = (s) => [s.length, ...Buffer.from(s)];
  const sect = (id, payload) => [id, payload.length, ...payload];
  return Buffer.from([
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, // magic + version
    ...sect(1, [1, 0x60, 0x00, 0x01, 0x7f]),          // type: () -> i32
    ...sect(2, [1, ...str("env"), ...str("abort"), 0x00, 0x00]), // import env.abort
    ...sect(3, [1, 0x00]),                            // one function of type 0
    ...sect(7, [1, ...str("go"), 0x00, 0x01]),        // export func 1 as "go"
    ...sect(10, [1, 0x04, 0x00, 0x41, 0x00, 0x0b]),   // body: i32.const 0, end
  ]);
}

for (const [name, fn] of tests) {
  try { await fn(); pass++; console.log("  ok  ", name); }
  catch (e) { fail++; failures.push(name); console.log("  FAIL", name, "—", e.message); }
}
console.log(`\n${pass} passed, ${fail} failed`);
if (fail) { console.log("FAILED:", failures.join(", ")); process.exit(1); }