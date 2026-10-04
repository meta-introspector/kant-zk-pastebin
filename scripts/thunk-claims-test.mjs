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

import { readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { CLAIMS, evaluate, resolveInput, runClaims, Thunk } from "./thunk-claims.mjs";

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

/** Require that a claim's probe fails when the *thing it measures* is broken.
 *
 *  `broken` is called to produce the observed value the probe would give if the
 *  defect were present -- so it must be written as the defect's behaviour, not
 *  as the negation of the claim. Writing `() => false` here would prove
 *  nothing: it would pass for any claim, including one that had stopped
 *  reading the tree at all.
 */
const mustFlipProbe = async (id, why, broken) => {
  const c = claim(id);
  const before = await evaluate(c, await resolveInput(c.input));
  if (!before.ok) throw new Error(`${id} does not hold in the first place`);
  const observed = await broken();
  if (observed === c.expect) {
    throw new Error(`${id} still passed on ${why} (the mutation reproduced the expected value)`);
  }
};

t("thunk-id-is-64-hex is measuring the real digest", () =>
  // The defect is a truncated id, so the mutation is the truncated digest.
  mustFlipProbe("thunk-id-is-64-hex", "a 16-char digest",
    async () => "0123456789abcdef"));

t("thunk-id-separates-urls goes red under the old regex stripper", () =>
  // The claim answers "these two get different ids". So the mutation has to
  // answer the same question with the *old* id implementation in place, and it
  // must come out `false`: the two collide there, which is the defect. Note the
  // shape -- this asks the claim's question, it does not restate the defect.
  mustFlipProbe("thunk-id-separates-urls", "the old regex comment stripper",
    async () => {
      const src = (url) =>
        `module.exports.initialState = {};\n` +
        `module.exports.reduce = function reduce(s, i) { return { state: { url: "${url}" }, effects: [] }; };`;
      const clean = (s) => s.replace(/\/\/.*$/gm, "").replace(/\/\*[\s\S]*?\*\//g, "").replace(/\n+/g, "\n").trim();
      const different = clean(src("http://alpha.example/x")) !== clean(src("http://bravo.evil.example"));
      return different;
    }));

t("thunk-id-ignores-comments goes red when the hash keeps the comment", () =>
  mustFlipProbe("thunk-id-ignores-comments", "a hash over the raw source",
    async () => {
      const body = (mid) => `module.exports.initialState = {};\nmodule.exports.reduce = function reduce(s, i) {\n  ${mid}\n  return { state: { n: s.n }, effects: [] };\n};`;
      return body("") === body("// a comment");
    }));

t("args-hash-sorts-keys goes red under insertion order", () =>
  // The codec encodes object fields in the order given, so two spellings of the
  // same value hash differently unless the keys are sorted first. This is that
  // difference, taken straight from the codec.
  mustFlipProbe("args-hash-sorts-keys", "unsorted keys",
    async () => {
      const C = await import(`${ROOT}/scripts/kant-codec.mjs`);
      const ab = C.valHash(C.vObj([["a", C.vInt(1)], ["b", C.vInt(2)]]));
      const ba = C.valHash(C.vObj([["b", C.vInt(2)], ["a", C.vInt(1)]]));
      return ab === ba;
    }));

t("codec-has-no-float goes red when a seventh type appears", () =>
  // I added a float to this codec and it passed every JS-side test. It was
  // wrong: `Kant.Codec.Val` has six constructors, `canonEnc_injective` is proved
  // over them, and IPDL drops floats for binary compatibility while proving the
  // projection LOSSLESS. So this claim has to notice the type coming back.
  mustFlipProbe("codec-has-no-float", "a float constructor",
    async () => {
      const C = await import(`${ROOT}/scripts/kant-codec.mjs`);
      return typeof C.vFloat === "function";
    }));

t("js-codec-matches-lean-source goes red when the codec grows a type", async () => {
  // The end-to-end mutation: re-add the float to `canonEnc`, exactly as phase 1
  // did, and require the whole comparison to notice. This is the check that
  // would have prevented that commit.
  const codec = `${ROOT}/scripts/kant-codec.mjs`;
  const before = readFileSync(codec, "utf8");
  const { compare } = await import(`${ROOT}/scripts/lean-codec-types.mjs`);
  try {
    if (!(await compare()).rows.every((r) => r.ok)) {
      throw new Error("js-codec-matches-lean-source does not hold to begin with");
    }
    const withFloat = before.replace(
      '    case "str": return `S${encStr(v.s)}`;',
      '    case "float": return `D${String(v.n)};`;\n    case "str": return `S${encStr(v.s)}`;',
    );
    if (withFloat === before) throw new Error("the mutation did not apply");
    writeFileSync(codec, withFloat, "utf8");
    try {
      const after = await compare();
      if (after.rows.every((r) => r.ok)) {
        throw new Error("still passed with a float in canonEnc");
      }
      // And it must name the offender, not just go red.
      const detail = after.rows.filter((r) => !r.ok).map((r) => r.detail).join(" ");
      if (!detail.includes("float")) {
        throw new Error(`went red without naming the float: ${detail}`);
      }
    } finally {
      writeFileSync(codec, before, "utf8");
    }
  } finally {
    writeFileSync(codec, before, "utf8");
  }
});

t("golden-vector-matches-lean goes red when a tag byte changes", () => {
  // One character: `S` becomes `s` in canonEnc. That is enough to move the
  // canonical text, the IPDL text and the digest, so those rows must go red.
  //
  // This runs the checker as a child process rather than importing it, because
  // `compareVectors` imports the codec and Node caches ES modules: writing the
  // mutated file and re-checking in the same process compares the *old* module
  // and reports nothing. That is why the mutation appeared to have no teeth.
  // A subprocess is also how CI would run it.
  //
  // The mutation also has to touch something gSample actually exercises -- an
  // earlier attempt flipped the `false` branch of bool, which gSample never
  // reaches, and the checker was right to report nothing.
  const codec = `${ROOT}/scripts/kant-codec.mjs`;
  const before = readFileSync(codec, "utf8");
  // The CLI exits non-zero when a check fails, which is exactly the case this
  // mutation wants, so the exit code is captured rather than allowed to throw.
  const run = () => {
    const r = spawnSync(process.execPath, [`${ROOT}/scripts/lean-codec-vectors.mjs`, "--json"], {
      encoding: "utf8",
      cwd: ROOT,
    });
    if (r.status === 2) throw new Error(`checker could not read Lean: ${r.stderr}`);
    return JSON.parse(r.stdout);
  };
  try {
    if (!run().rows.every((r) => r.ok)) {
      throw new Error("golden-vector-matches-lean does not hold to begin with");
    }
    const mutated = before.replace(
      'case "str": return `S${encStr(v.s)}`;',
      'case "str": return `s${encStr(v.s)}`;',
    );
    if (mutated === before) throw new Error("the mutation did not apply");
    writeFileSync(codec, mutated, "utf8");
    const failed = run().rows.filter((r) => !r.ok);
    for (const fn of ["canonEnc", "ipdlText", "valHash"]) {
      if (!failed.some((r) => r.check.includes(fn))) {
        throw new Error(`${fn} did not go red; failed rows were ${failed.map((r) => r.check).join(", ")}`);
      }
    }
  } finally {
    writeFileSync(codec, before, "utf8");
  }
});

t("thunk-id-is-lean-representable goes red when float joins the tag list", () =>
  // The mutation is my float, re-admitted as if Lean had it. A seventh tag
  // collides with nothing, so every round-trip and injectivity test keeps
  // passing -- this is the only kind of check that could ever have caught it.
  //
  // The claim's load-bearing conjunct is that the guard *rejects* a float, so
  // the mutation re-evaluates exactly that conjunct with "float" admitted.
  mustFlipProbe("thunk-id-is-lean-representable", "float admitted as a Lean shape",
    async () => {
      const { LEAN_VAL_TAGS } = await import(`${ROOT}/server/thunk-id.mjs`);
      const tags = [...LEAN_VAL_TAGS, "float"];
      const guard = (v) =>
        v !== null && typeof v === "object" && tags.includes(v.t)
        && (v.t === "list" ? v.xs.every(guard)
          : v.t === "obj" ? v.fs.every(([, x]) => guard(x))
            : true);
      return !guard({ t: "float", n: 1.5 });
    }));

t("fractional-argument-refused goes red when a fraction is hashed", () =>
  mustFlipProbe("fractional-argument-refused", "1.5 rounded to an int",
    async () => {
      const t = await Thunk.load(
        "module.exports.initialState = {};\n" +
        "module.exports.reduce = function reduce(s, i) { return { state: s, effects: [] }; };",
        "c", "1.0.0");
      // The coercion this claim exists to prevent.
      let threw = false;
      try { t.argsHash({ n: Math.trunc(1.5) }); } catch { threw = true; }
      return threw;
    }));

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

// The old defect claim here mutated .gitignore. It is now a health claim, and
// it reads the tree itself, so a fabricated input would only prove the probe's
// boolean. This mutates the real file and restores it, because the regression it
// exists to catch — reading the gitignored `dist/` again — is exactly a change
// to that file.
t("wasm-test-inputs-tracked goes red when the test reads gitignored dist/", async () => {
  const path = resolve(ROOT, "web/wasm-test.mjs");
  const before = readFileSync(path, "utf8");
  const mutated = before.replace(
    'new URL("./kant_kernel.wasm", import.meta.url)',
    'new URL("../dist/kant_kernel.wasm", import.meta.url)',
  );
  // If the anchor moved, the mutation is a no-op and the claim would pass for
  // the wrong reason — which is how a checker rots without going red.
  if (mutated === before) throw new Error("mutation anchor not found in web/wasm-test.mjs");
  try {
    writeFileSync(path, mutated);
    const c = claim("wasm-test-inputs-tracked");
    const after = await evaluate(c, await resolveInput(c.input));
    if (after.ok) throw new Error("still passed on a test that reads dist/");
  } finally {
    writeFileSync(path, before);
  }
});

t("kernel-vectors-satisfy-wasm goes red on a vector the binary fails", () =>
  mustFlipProbe("kernel-vectors-satisfy-wasm", "an unsatisfied golden vector",
    async () => ({ vectors: 59, unsatisfied: ["rotate71(70, 1)"] })));

t("kernel-vectors-satisfy-wasm goes red on a short vector file", () =>
  mustFlipProbe("kernel-vectors-satisfy-wasm", "fewer than 59 vectors",
    async () => ({ vectors: 58, unsatisfied: [] })));

t("suites-never-use-the-production-pass-db goes red on a relay left at the default", () =>
  mustFlipProbe("suites-never-use-the-production-pass-db",
    "a suite whose relay config has no passDb",
    async () => [{ suite: "web/join-test.mjs", mode: "PRODUCTION", calls: 1, unsafe: 1 }]));

t("suites-never-use-the-production-pass-db goes red when a suite drops its passDb", async () => {
  // A real mutation, not a fabricated input. The claim reads the config that
  // actually reaches createServer, and the first draft only grepped the file for
  // the word "passDb" — so a suite could declare it and forget to pass it, and
  // the claim called that safe. Only mutating the call proves otherwise.
  const path = resolve(ROOT, "web/wasm-test.mjs");
  const before = readFileSync(path, "utf8");
  const mutated = before.replace(
    "{ ...CONFIG, staticDir, passDb }", "{ ...CONFIG, staticDir }");
  if (mutated === before) throw new Error("mutation anchor not found in web/wasm-test.mjs");
  try {
    writeFileSync(path, mutated);
    const c = claim("suites-never-use-the-production-pass-db");
    const after = await evaluate(c, await resolveInput(c.input));
    if (after.ok) throw new Error("still passed on a relay using the production passDb");
  } finally {
    writeFileSync(path, before);
  }
});

t("suites-never-use-the-production-pass-db sees a suite that parses no config", () =>
  mustFlipProbe("suites-never-use-the-production-pass-db",
    "a relay whose config could not be found",
    async () => [{ suite: "web/join-test.mjs", mode: "NO CONFIG FOUND", calls: 0 }]));

// ── the Lean proof gate can fail ──────────────────────────────────
//
// These are mutation tests on the *real tree*, not on a fabricated input: the
// claim that matters here is "the proof builds", and a claim about a build can
// only be made to fail by breaking the build.
t("relay-suites-share-one-start-budget goes red when a suite guesses again", async () => {
  // The real defect: four suites each had `reject(new Error("relay did not
  // start")), 8000`, and the rejection carried nothing about the relay. Put
  // that copy back into one suite and the claim has to notice.
  const path = resolve(ROOT, "web/diag-test.mjs");
  const before = readFileSync(path, "utf8");
  try {
    const guessed = before.replace(
      /const startRelay = \(port\) =>[\s\S]*?--pass-db", passDb, "--quiet"\]\);/,
      `function startRelay(port) {
  const proc = spawn(process.execPath,
    [relayPath, "--port", String(port), "--static", here, "--log", logFile,
      "--pass-db", passDb, "--quiet"],
    { stdio: ["ignore", "pipe", "pipe"] });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("relay did not start")), 8000);
    proc.stdout.on("data", (d) => {
      if (String(d).includes("listening")) { clearTimeout(timer); resolve(proc); }
    });
    proc.on("error", reject);
  });
}`);
    if (guessed === before) throw new Error("could not find the shared startRelay to replace");
    writeFileSync(path, guessed);
    const c = claim("relay-suites-share-one-start-budget");
    const after = await evaluate(c, await resolveInput(c.input));
    if (after.ok) throw new Error("still passed on a suite that gives up saying only 'relay did not start'");
  } finally {
    writeFileSync(path, before);
  }
});

t("lean-gate-imports-nothing-external goes red on an outside import", () =>
  mustFlipProbe("lean-gate-imports-nothing-external",
    "a file importing Mathlib",
    async () => [{ file: "lean-gate/RequestProject/Kant/Bytes.lean", module: "Mathlib", internal: false }]));

t("lean-spec-proves-every-wasm-export goes red on an unproved export", () =>
  mustFlipProbe("lean-spec-proves-every-wasm-export",
    "an export with no theorem evaluating it",
    async () => [{ export: "rotate71", body: "rotate71E", proved: false }]));

t("lean-proof-gate-builds goes red when the spec is given a hole", () => {
  const path = resolve(ROOT, "lean-gate/RequestProject/Wasm/KernelSpec.lean");
  const before = readFileSync(path, "utf8");
  const probe = claim("lean-proof-gate-builds").probe;
  try {
    // Replace one real proof with `sorry`. This is the whole point of the
    // claim: the gate is not a grep, so a hole has to break it.
    const marked = before.replace(
      /(theorem eval_rotate71E[\s\S]*?:= by\r?\n)(  norm_num|  simp only)/,
      "$1  sorry\n--");
    if (marked === before) throw new Error("could not find a proof body to hole out");
    writeFileSync(path, marked);
    if (probe(undefined)) throw new Error("the gate still passed with a sorry in the spec");
  } finally {
    writeFileSync(path, before);
  }
});

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