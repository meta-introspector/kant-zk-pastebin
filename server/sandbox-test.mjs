// sandbox-test.mjs — can a loaded thunk reach the host?
//
// server/thunk-test.mjs asks whether a thunk can read the filesystem and spawn
// a process. Those two tests passed the moment the loader was fixed, and the
// sandbox was still wide open: `module.constructor.constructor` walked from a
// host object in the context to the host Function constructor and from there to
// the host global. Two targeted tests are not an isolation argument, so this
// file enumerates the ways out instead of guessing at one.
//
// Every probe here reports absence in whichever of two ways it happens:
//   - as an exception   (`require` -> ReferenceError)
//   - as the string "undefined" (`typeof fetch` -> "undefined")
// A probe that only looks for "blocked" calls the second kind a leak. The first
// draft of this file did exactly that and reported four escapes that were not
// escapes, which is the same shape of error as a counter-example that only
// passes because it threw.

import { Thunk } from "./thunk.mjs";

/**
 * Each entry is evaluated inside a thunk's own `reduce`, with its own
 * try/catch. Anything that starts with REACHED and does not end in
 * ":undefined" is treated as a real reach.
 */
const ESCAPES = [
  ["require", 'require("node:fs")'],
  ["process", "process.version"],
  ["process.binding", 'process.binding("spawn_sync")'],
  ["globalThis.process", "globalThis.process.version"],
  ["globalThis.require", 'globalThis.require("node:fs")'],
  ["Buffer", 'Buffer.from("x")'],
  ["fetch", "typeof fetch"],
  ["setTimeout", "typeof setTimeout"],
  ["console", "typeof console"],
  // The realm bridge. `module` and `exports` are created inside the context
  // precisely so this chain dead-ends; they used to be host objects.
  ["module-ctor", 'module.constructor.constructor("return typeof process")()'],
  ["exports-ctor", 'exports.constructor.constructor("return typeof process")()'],
  // `this` inside a transducer is `undefined` because apply() calls it
  // unqualified. As a method call it would be the host-side transducers object,
  // and that is the same bridge by another name.
  ["ctor-chain", 'this.constructor.constructor("return typeof process")()'],
  ["Function-ctor", 'Function("return typeof process")()'],
];

const probe = async (expr) => {
  const source = `
    module.exports.initialState = {};
    module.exports.reduce = function (state) {
      var out;
      try { out = "REACHED:" + String(${expr}); }
      catch (e) { out = "blocked:" + (e && e.name); }
      return { state: { out: out }, effects: [] };
    };
  `;
  const thunk = await Thunk.load(source, "probe", "0.0.0");
  return thunk.apply({}).state.out;
};

const reached = (seen) =>
  String(seen).startsWith("REACHED") && !String(seen).endsWith(":undefined");

let pass = 0, fail = 0;
const failures = [];
const tests = [];
const t = (name, fn) => tests.push([name, fn]);

for (const [name, expr] of ESCAPES) {
  t(`a thunk cannot reach the host through ${name}`, async () => {
    const seen = await probe(expr);
    if (reached(seen)) throw new Error(`reached the host: ${seen}`);
  });
}

t("dynamic import is refused at load time, not at call time", async () => {
  // Inside a vm, `import()` raises ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING, which
  // ignores the thunk's try/catch and kills the host process. Supplying an
  // importModuleDynamically callback did not contain it. So the refusal happens
  // before compilation, and a thunk that imports simply does not load.
  const source = `module.exports.initialState = {};
    module.exports.reduce = async () => {
      const m = await import("node:fs");
      return { state: { n: m }, effects: [] };
    };`;
  let threw = null;
  try {
    await Thunk.load(source, "importer", "0.0.0");
  } catch (e) {
    threw = e;
  }
  if (!threw) throw new Error("a thunk with a dynamic import loaded");
  if (!/import/.test(threw.message)) throw new Error(`unclear refusal: ${threw.message}`);
});

t("import.meta is refused too", async () => {
  let threw = null;
  try {
    await Thunk.load(`module.exports.meta = import.meta.url;`, "meta", "0.0.0");
  } catch (e) {
    threw = e;
  }
  if (!threw) throw new Error("a thunk reading import.meta loaded");
});

t("a pure thunk still works, so the sandbox is not just refusal", async () => {
  // A sandbox that rejects everything is not a sandbox, it is an outage.
  const source = `
    module.exports.initialState = { n: 0 };
    module.exports.reduce = function (state, input) {
      return { state: { n: state.n + (input.by ?? 1) }, effects: ["added"] };
    };
  `;
  const thunk = await Thunk.load(source, "counter", "0.0.0");
  thunk.apply({ by: 2 });
  const out = thunk.apply({ by: 3 });
  if (out.state.n !== 5) throw new Error(`n is ${out.state.n}, expected 5`);
  if (!out.effects.includes("added")) throw new Error(`effects lost: ${JSON.stringify(out.effects)}`);
});

t("a transducer sees this === undefined", async () => {
  // Not an escape on its own, but the mechanism behind ctor-chain: apply() must
  // not hand a transducer a host object as its receiver.
  const source = `
    module.exports.initialState = {};
    module.exports.reduce = function () {
      return { state: { self: typeof this }, effects: [] };
    };
  `;
  const thunk = await Thunk.load(source, "this-check", "0.0.0");
  const seen = thunk.apply({}).state.self;
  if (seen !== "undefined") throw new Error(`this is ${seen} inside a transducer`);
});

for (const [name, fn] of tests) {
  try { await fn(); pass++; console.log("  ok  ", name); }
  catch (e) { fail++; failures.push(name); console.log("  FAIL", name, "—", e.message); }
}
console.log(`\n${pass} passed, ${fail} failed`);
if (fail) { console.log("FAILED:", failures.join(", ")); process.exit(1); }