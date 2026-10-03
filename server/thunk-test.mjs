// thunk-test.mjs — what `server/thunk.mjs` can and cannot do today.
//
// Written because the design docs (tasks/thunk-server/DESIGN.md) describe a
// working thunk system and `tasks/thunk-server/WASM.md` proposes replacing it.
// Before replacing something, pin what it actually does.
//
// The tests below are expected to FAIL against the current implementation.
// That is the point: each one is a red-to-green gate for phase 0 of WASM.md,
// not a description of working code. A test that passes here means the loader
// changed, and the comment saying so needs updating.

import { Thunk } from "./thunk.mjs";

let pass = 0;
let fail = 0;
const failures = [];
const tests = [];
const t = (name, fn) => tests.push([name, fn]);

// A thunk in the form loadSource can actually parse: `new Function` builds a
// script body, so `export` is a SyntaxError. DESIGN.md shows the module form
// everywhere; that is finding 2 in WASM.md.
const CJS_THUNK = `
module.exports.initialState = { n: 0 };
module.exports.reduce = function reduce(state, input) {
  return { state: { n: state.n + (input.by ?? 1) }, effects: [] };
};
`;

// ── phase 0: the loader works at all ────────────────────────────────────

t("a trivial thunk loads", async () => {
  const thunk = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  if (!thunk) throw new Error("no thunk returned");
  if (thunk.name !== "counter") throw new Error(`name is ${thunk.name}`);
});

t("reduce is exported to the caller", async () => {
  // Finding 3: the vm's `module` is not the object loadSource reads back, so
  // nothing lands in `transducers` and Thunk.load throws "needs a reduce".
  const thunk = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  const out = thunk.apply({ by: 2 });
  if (out?.state?.n !== 2) throw new Error(`apply gave ${JSON.stringify(out?.state)}`);
});

t("state accumulates across applies", async () => {
  const thunk = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  thunk.apply({ by: 1 });
  const out = thunk.apply({ by: 4 });
  if (out.state.n !== 5) throw new Error(`n is ${out.state.n}, expected 5`);
});

t("snapshot and resume round-trip", async () => {
  const thunk = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  thunk.apply({ by: 3 });
  const snap = thunk.snapshot();
  const fresh = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  fresh.resume(snap);
  const out = fresh.apply({ by: 1 });
  if (out.state.n !== 4) throw new Error(`after resume n is ${out.state.n}, expected 4`);
});

// ── what a thunk must NOT be able to do ─────────────────────────────────

t("a thunk cannot read the host filesystem", async () => {
  // The loadSource comment promises "no access to the host process". Today the
  // path throws before a thunk runs, so this passes for the wrong reason --
  // which is exactly why it should be a test. Once phase 0 lands, this is the
  // assertion that decides whether the comment is true.
  const source = `
    module.exports.initialState = {};
    module.exports.reduce = function (state, input) {
      var reached;
      try { reached = "REACHED-FS"; require("node:fs"); }
      catch (e) { reached = "blocked:" + (e && e.code); }
      return { state: { reached: reached }, effects: [] };
    };
  `;
  let thunk;
  try {
    thunk = await Thunk.load(source, "sandbox", "0.0.0");
  } catch (e) {
    throw new Error(`cannot even load, so this proves nothing: ${e.message}`);
  }
  const seen = thunk.apply({}).state.reached;
  if (seen !== "blocked:undefined" && !String(seen).startsWith("blocked")) {
    throw new Error(`require reached the host: ${seen}`);
  }
});

t("a thunk cannot spawn a process", async () => {
  const source = `
    module.exports.initialState = {};
    module.exports.reduce = function (state, input) {
      var reached;
      try { require("node:child_process").execSync("echo pwned"); reached = "REACHED-PROC"; }
      catch (e) { reached = "blocked:" + (e && e.code); }
      return { state: { reached: reached }, effects: [] };
    };
  `;
  let thunk;
  try {
    thunk = await Thunk.load(source, "sandbox", "0.0.0");
  } catch (e) {
    throw new Error(`cannot even load, so this proves nothing: ${e.message}`);
  }
  const seen = thunk.apply({}).state.reached;
  if (!String(seen).startsWith("blocked")) {
    throw new Error(`a thunk spawned a process: ${seen}`);
  }
});

// ── content addressing (phase 1 of WASM.md) ──────────────────────────────

t("id is the full sha256 of the bytes", async () => {
  // WASM.md phase 1: today id is a 16-char prefix, which asWitness rejects.
  const thunk = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  const hex = /^[0-9a-f]+$/.test(thunk.id.split(":").pop() ?? "");
  if (!hex) throw new Error(`id tail is not hex: ${thunk.id}`);
  const len = thunk.id.split(":").pop().length;
  if (len !== 64) throw new Error(`witness is ${len} chars, asWitness requires 64`);
});

t("different bytes give different ids", async () => {
  const a = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  // A comment would not do: `cleanSource` strips those, so two sources differing
  // only in comments are the same thunk by design. Change the code instead.
  const b = await Thunk.load(
    CJS_THUNK.replace("(input.by ?? 1)", "(input.by ?? 2)"),
    "counter",
    "0.0.0"
  );
  if (a.id === b.id) throw new Error(`both are ${a.id}`);
});

t("the same bytes give the same id", async () => {
  const a = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  const b = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  if (a.id !== b.id) throw new Error(`${a.id} != ${b.id}`);
});

t("manifest carries a content hash and no state", async () => {
  const thunk = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  thunk.apply({ by: 7 });
  const m = thunk.manifest();
  const json = JSON.stringify(m);
  if (json.includes('"n":7')) throw new Error(`manifest leaked state: ${json}`);
  const hash = m.contentHash ?? m.sourceHash;
  if (!hash) throw new Error(`manifest has no hash: ${json}`);
  if (String(hash).length !== 64) throw new Error(`hash is ${String(hash).length} chars`);
});

for (const [name, fn] of tests) {
  try {
    await fn();
    pass++;
    console.log("  ok  ", name);
  } catch (e) {
    fail++;
    failures.push(name);
    console.log("  FAIL", name, "—", e.message);
  }
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) {
  console.log(
    "\nThese are expected to fail against the current implementation. They are\n" +
      "the red-to-green gates for phase 0 and phase 1 of tasks/thunk-server/WASM.md:\n" +
      "  - the loader throws on every input (require undefined in an ES module)\n" +
      "  - `new Function` parses a script, so `export` cannot work\n" +
      "  - the vm's `module` is not the object loadSource reads back\n" +
      "  - id is a 16-char prefix, and asWitness requires 64\n" +
      "Once one of these goes green, update the comment at the top of this file."
  );
  console.log("\nFAILED:", failures.join(", "));
  process.exit(1);
}