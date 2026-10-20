// thunk-test.mjs — what `server/thunk.mjs` can and cannot do today.
//
// Written because the design docs (tasks/thunk-server/DESIGN.md) describe a
// working thunk system and `tasks/thunk-server/WASM.md` proposes replacing it.
// Before replacing something, pin what it actually does.
//
// Each one is a red-to-green gate for phase 0 of WASM.md, not a description of
// working code. A test that passes here means the loader changed, and the
// comment saying so needs updating.
//
// Phase 0 landed 2026-10-03 (tasks/thunk-server/SANDBOX.md): 8 of 10 are green.
// What is fixed: the loader throws no more, `export` is documented as out of
// dialect, and the vm's `module` is the object read back. What is not: the id
// is still a 16-char prefix where `asWitness` wants 64, which is phase 1.
// The sandbox those two tests cover is now covered properly by
// server/sandbox-test.mjs -- they passed on the first fix while three escapes
// were still open.

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

// ── the collisions phase 1 had to remove ────────────────────────────────
// Each of these was a real defect, found by measurement rather than by reading
// the code. They are here because a content hash is only worth having if the
// things it must separate are actually separated.

t("a `//` inside a string does not merge two thunks", async () => {
  // This is the bug that motivated the rewrite. The old id ran the source
  // through `src.replace(/\/\/.*$/gm, "")`, which strips from the first `//`
  // to end of line *wherever it finds one*, including inside a string. Both
  // thunks below cleaned down to `... "http:` and hashed the same, so two
  // thunks fetching different URLs shared one id and one cache entry.
  const withUrl = (url) => `
module.exports.initialState = {};
module.exports.reduce = function reduce(state, input) {
  return { state: { url: "${url}" }, effects: [] };
};
`;
  const a = await Thunk.load(withUrl("http://alpha.example/x"), "fetcher", "1.0.0");
  const b = await Thunk.load(withUrl("http://bravo.evil.example/steal"), "fetcher", "1.0.0");
  if (a.contentHash === b.contentHash) {
    throw new Error(`different URLs share the id ${a.contentHash}`);
  }
  // And the two really are different thunks, so this is not a false alarm.
  if (JSON.stringify(a.apply({}).state) === JSON.stringify(b.apply({}).state)) {
    throw new Error("these two thunks behave identically; the fixture is wrong");
  }
});

t("a comment does not change the id", async () => {
  // The other direction. Comments are not identity, so this must NOT change the
  // id -- that is the whole reason `server/js-scan.mjs` exists.
  const body = (mid) => `
module.exports.initialState = {};
module.exports.reduce = function reduce(state, input) {
  ${mid}
  return { state: { n: state.n }, effects: [] };
};
`;
  const plain = body("");
  const commented = body("// a comment");
  const blocky = body("/* another */");
  const h = await Thunk.load(plain, "r", "1.0.0");
  if (h.contentHash !== (await Thunk.load(commented, "r", "1.0.0")).contentHash) {
    throw new Error("a line comment changed the id");
  }
  if (h.contentHash !== (await Thunk.load(blocky, "r", "1.0.0")).contentHash) {
    throw new Error("a block comment changed the id");
  }
});

t("refs are part of the id", async () => {
  // A thunk built against a different ref is a different thunk even with
  // identical source. Refs are sorted, so listing them in another order is the
  // same set and the same id.
  const base = await Thunk.load(CJS_THUNK, "counter", "1.0.0", {}, []);
  const withRef = await Thunk.load(CJS_THUNK, "counter", "1.0.0", {}, ["lake"]);
  if (base.contentHash === withRef.contentHash) throw new Error("refs did not change the id");
  const ab = await Thunk.load(CJS_THUNK, "counter", "1.0.0", {}, ["a", "b"]);
  const ba = await Thunk.load(CJS_THUNK, "counter", "1.0.0", {}, ["b", "a"]);
  if (ab.contentHash !== ba.contentHash) throw new Error("ref order changed the id");
  if (!Array.isArray(base.refs)) throw new Error("refs is not an array");
});

t("name and version are labels, not identity", async () => {
  // Deliberate, and worth pinning: every thunk in this tree was `0.0.0` or
  // `1.0.0` while the code under it changed, so a version cannot be identity.
  const a = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  const b = await Thunk.load(CJS_THUNK, "totally-different-name", "9.9.9");
  if (a.contentHash !== b.contentHash) {
    throw new Error("a rename changed the content hash");
  }
  // The readable id still carries them, so a log is still legible.
  if (!b.id.includes("totally-different-name@9.9.9")) throw new Error(`id lost its label: ${b.id}`);
});

// ── the call id ──────────────────────────────────────────────────────────

t("callId differs from the thunk id and from other calls", async () => {
  const thunk = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  const a = thunk.callId({ by: 1 });
  const b = thunk.callId({ by: 2 });
  if (a === b) throw new Error("different arguments share a call id");
  if (a === thunk.contentHash) throw new Error("call id is the thunk id");
  if (!/^[0-9a-f]{64}$/.test(a)) throw new Error(`call id is not a witness: ${a}`);
});

t("secretRefs name slots and never carry contents", async () => {
  const thunk = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  const none = thunk.callId({ by: 1 });
  const named = thunk.callId({ by: 1 }, { secretRefs: ["OPENAI_API_KEY"] });
  if (none === named) throw new Error("declaring a secret slot did not change the call id");
  // Order is not identity: two callers listing the same slots are the same call.
  if (thunk.callId({ by: 1 }, { secretRefs: ["a", "b"] })
      !== thunk.callId({ by: 1 }, { secretRefs: ["b", "a"] })) {
    throw new Error("secretRef order changed the call id");
  }
  // The secret's *contents* cannot appear, because there is nowhere to put them:
  // only names are accepted.
  const withContents = thunk.callId({ by: 1 }, { secretRefs: ["sk-live-abc123"] });
  if (typeof withContents !== "string" || withContents.length !== 64) {
    throw new Error("call id shape changed");
  }
});

t("the api set is part of the call id", async () => {
  // A result computed with a narrow api set must not be served to a caller
  // holding a wide one, because the wide one can do more with it.
  const thunk = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  if (thunk.callId({ by: 1 }) === thunk.callId({ by: 1 }, { apiRefs: ["fs"] })) {
    throw new Error("widening the api set did not change the call id");
  }
});

t("argsHash is insensitive to key order and sensitive to values", async () => {
  const thunk = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  // `canonEnc` walks object fields in order, so unsorted keys would hash two
  // spellings of the same value differently -- and JS key order is not part of
  // the value.
  if (thunk.argsHash({ a: 1, b: 2 }) !== thunk.argsHash({ b: 2, a: 1 })) {
    throw new Error("key order changed the args hash");
  }
  if (thunk.argsHash({ a: 1 }) === thunk.argsHash({ a: 2 })) {
    throw new Error("a changed value did not change the args hash");
  }
  // `Kant.Codec.Val` has no float constructor, so a fractional number has no
  // canonical form and therefore no content address. Coercing it to `1` would
  // let two different calls share one cache entry.
  if (thunk.argsHash({ n: 1 }) !== thunk.argsHash({ n: 1 })) {
    throw new Error("1 does not hash to itself");
  }
  for (const fractional of [1.5, -0.25, 1e-7]) {
    let threw = false;
    try { thunk.argsHash({ n: fractional }); } catch { threw = true; }
    if (!threw) throw new Error(`${fractional} was hashed; Kant.Codec.Val has no float`);
  }
  // -0 is not 0 (`1 / -0` is -Infinity), but there is no tag to separate them
  // under, so it is refused rather than silently merged with 0.
  let threw = false;
  try { thunk.argsHash({ n: -0 }); } catch { threw = true; }
  if (!threw) throw new Error("-0 was hashed as 0, which BigInt would have done");
});

t("an input with no content address is refused, not coerced", async () => {
  // Every one of these has no spelling that reads back as itself, so a coerced
  // hash would claim two different calls are one. A loud failure at the call
  // site is recoverable; a wrong cache hit is not.
  const thunk = await Thunk.load(CJS_THUNK, "counter", "0.0.0");
  const cases = {
    undefined: undefined,
    NaN: NaN,
    Infinity: Infinity,
    "a fraction": 1.5,
    "-0": -0,
    "a function": () => 1,
    "a Date": new Date(0),
    "a Map": new Map(),
  };
  for (const [what, value] of Object.entries(cases)) {
    let threw = null;
    try { thunk.argsHash({ v: value }); } catch (e) { threw = e; }
    if (!threw) throw new Error(`${what} was hashed instead of refused`);
    // The message must name the path, or a deeply nested refusal is unusable.
    if (!threw.message.includes("args.v")) {
      throw new Error(`${what} refused without naming the path: ${threw.message}`);
    }
  }
  // A cycle would otherwise recurse until the stack dies.
  const cyclic = {};
  cyclic.self = cyclic;
  let threw = null;
  try { thunk.argsHash(cyclic); } catch (e) { threw = e; }
  if (!threw) throw new Error("a cycle was hashed");
});

t("a thunk id is a value Lean could have computed", async () => {
  // The guard that phase 1 needed and did not have. A seventh codec type does not
  // collide with the others, so every round-trip and injectivity test keeps
  // passing while the JS and the Lean stop agreeing -- and a thunk id that Lean
  // cannot reproduce is an id the swarm cannot verify against a proof.
  const { thunkDefinitionVal, isLeanRepresentable, LEAN_VAL_TAGS } =
    await import("./thunk-id.mjs");
  const t = await Thunk.load(CJS_THUNK, "counter", "1.0.0", {}, ["lake"]);
  if (!isLeanRepresentable(thunkDefinitionVal(CJS_THUNK, ["lake"]))) {
    throw new Error(`the id's preimage uses a shape Lean cannot name: ${LEAN_VAL_TAGS}`);
  }
  // Teeth: the type I actually added, at the top level and buried.
  for (const foreign of [{ t: "float", n: 1.5 }, { t: "obj", fs: [["a", { t: "float", n: 1 }]] }]) {
    if (isLeanRepresentable(foreign)) {
      throw new Error(`a foreign shape passed: ${JSON.stringify(foreign)}`);
    }
  }
  // `ref` and `annot` are Lean's too -- Ipdl defines them -- so they pass.
  if (!isLeanRepresentable({ t: "ref", target: "x" })) {
    throw new Error("ref is a Lean shape and must be allowed");
  }
  if (!isLeanRepresentable({ t: "annot", key: "k", note: "n", body: { t: "int", n: 1n } })) {
    throw new Error("annot is a Lean shape and must be allowed");
  }
});

t("the codec has exactly the six value types Lean has", async () => {
  // `RequestProject/Kant/Codec/Val.lean` defines `Val` with six constructors and
  // proves `canonEnc_injective` over them. IPDL drops floats for binary
  // compatibility and proves the projection is LOSSLESS. So a seventh type here
  // would be a value the wire format is specified to discard, and the JS codec
  // would no longer be a transcription of the Lean one.
  const C = await import("../scripts/kant-codec.mjs");
  if (typeof C.vFloat === "function") {
    throw new Error("the codec has a float; Kant.Codec.Val has no float constructor");
  }
  // The six that do exist, still round-tripping through all five projections.
  const values = [C.vNull, C.vBool(true), C.vInt(-7), C.vStr("x"),
    C.vList([C.vInt(1)]), C.vObj([["k", C.vInt(1)]])];
  for (const v of values) {
    const projections = {
      canon: C.canonDecode(C.canonEnc(v)),
      yaml: C.yamlDecode(C.yamlEnc(v)),
      xml: C.xmlDecode(C.xmlEnc(v)),
      csv: C.csvDecode(C.csvEncode(v)),
      ipdl: C.ipdlRead(C.ipdlText(C.embed(v))),
    };
    for (const [fmt, back] of Object.entries(projections)) {
      if (C.canonEnc(back) !== C.canonEnc(v)) {
        throw new Error(`${fmt} lost ${v.t}: ${JSON.stringify(back)}`);
      }
    }
  }
  // And the tags are distinct, which is what makes injectivity hold.
  const tags = values.map((v) => C.canonEnc(v)[0]);
  if (new Set(tags).size !== tags.length) throw new Error(`tag collision: ${tags}`);
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