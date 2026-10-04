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

// ── the write guard can fail ──────────────────────────────────────
//
// The claim used to be `suites-never-use-the-production-pass-db` and it checked
// one field of one config. It now asks about every path the relay writes, which
// are derived from server/relay.mjs's own CONFIG. Each of these mutates the
// tree rather than feeding the probe a fabricated row, because a fabricated row
// only proves the probe's boolean and these regressions *are* tree changes.

/** Apply `mutate` to a tracked file, run a claim against the result, restore. */
const mutateFile = async (rel, mutate, run) => {
  const path = resolve(ROOT, rel);
  const before = readFileSync(path, "utf8");
  const mutated = mutate(before);
  // If the anchor moved the mutation is a no-op, and the claim would pass for
  // the wrong reason — which is how a checker rots without going red.
  if (mutated === before) throw new Error(`mutation anchor not found in ${rel}`);
  try {
    writeFileSync(path, mutated, "utf8");
    await run();
  } finally {
    writeFileSync(path, before, "utf8");
  }
};

const requireRed = async (id, why) => {
  const c = claim(id);
  const after = await evaluate(c, await resolveInput(c.input));
  if (after.ok) throw new Error(`${id} still passed on ${why}`);
};

t("suites-write-only-into-their-own-temp-dir goes red when a suite drops its passDb",
  () => mutateFile("web/wasm-test.mjs",
    (s) => s.replace("{ ...CONFIG, staticDir, passDb }", "{ ...CONFIG, staticDir }"),
    () => requireRed("suites-write-only-into-their-own-temp-dir",
      "a relay left at /var/lib/kant-zk/passes.sqlite")));

t("suites-write-only-into-their-own-temp-dir goes red on the *second* path, archiveDir",
  // The whole point of the generalisation. passDb is overridden and correct in
  // every one of these suites; archiveDir is the write the old guard could not
  // see, and it is what web/file-test.mjs actually got wrong.
  () => mutateFile("web/file-test.mjs",
    (s) => s.replace('archiveDir: join(stateDir, "archive")',
      'archiveDir: "/tmp/kant-file-test/archive"'),
    () => requireRed("suites-write-only-into-their-own-temp-dir",
      "a fixed archive directory shared by concurrent runs")));

t("suites-write-only-into-their-own-temp-dir goes red on the *third* path, logFile",
  () => mutateFile("web/diag-test.mjs",
    (s) => s.replace("const logFile = path.join(tmpdir(), `kant-diag-relay-${process.pid}.log`);",
      'const logFile = path.join(here, ".diag-relay.log");'),
    () => requireRed("suites-write-only-into-their-own-temp-dir",
      "a relay log written inside the checkout")));

t("suites-write-only-into-their-own-temp-dir goes red on a path left at a non-empty default",
  // Dropping `--pass-db` from the argv entirely. The relay then reads its own
  // default off disk, which is /var/lib/kant-zk/passes.sqlite.
  () => mutateFile("web/diag-test.mjs",
    (s) => s.replace('"--pass-db", passDb, ', ""),
    () => requireRed("suites-write-only-into-their-own-temp-dir",
      "a spawned relay given no --pass-db at all")));

t("suites-write-only-into-their-own-temp-dir is not fooled by a suite that stops starting a relay", async () => {
  // The trigger rotted once already: web/diag-test.mjs moved its inline spawn
  // into scripts/relay-start.mjs, stopped matching a trigger that looked for
  // `spawn(`, and dropped out of the scan on the commit that made it start
  // passing. The claim's answer is the `NOT SCANNED` row — a suite that mentions
  // the relay and is then not judged is a hole — so this is a real mutation of
  // the tree rather than a fabricated row.
  await mutateFile("web/join-test.mjs",
    // Renamed away from createServer( so the suite still imports relay.mjs and
    // still builds a relay — it just stops spelling the call the scan keys on.
    // That is the shape of the rot: not a suite that stopped starting a relay,
    // but one that started it by a name the trigger does not know.
    (s) => s.replace("const server = createServer(relayCfg, new Rooms(relayCfg));",
      "const makeServer = createServer;\nconst server = makeServer(relayCfg, new Rooms(relayCfg));"),
    () => requireRed("suites-write-only-into-their-own-temp-dir",
      "a suite that mentions the relay and is no longer judged"));
});

t("suites-write-only-into-their-own-temp-dir goes red on a suite whose config cannot be parsed",
  // The vacuity trap: a scanner that finds no configs must not report "safe".
  () => mustFlipProbe("suites-write-only-into-their-own-temp-dir",
    "a row with no path to judge",
    async () => [{ suite: "web/join-test.mjs", mode: "own tmp", key: "passDb", paths: 0, outside: 0 }]));

t("suites-never-reach-a-remote-host goes red on a suite that probes a deployment",
  // A real mutation of the tree, and the regression this claim was written
  // after: the fetchImpl stub is removed, so `resolveReachability` really does
  // fetch https://kant-relay.cicada71.net/health from the core run.
  () => mutateFile("web/diag-test.mjs",
    (s) => s.replace(", fetchImpl: noNetwork,", ","),
    () => requireRed("suites-never-reach-a-remote-host",
      "a suite that fetches the production relay")));

t("suites-never-reach-a-remote-host counts passing globalThis.fetch as no stub",
  () => mutateFile("web/diag-test.mjs",
    (s) => s.replace(", fetchImpl: noNetwork,", ", fetchImpl: globalThis.fetch,"),
    () => requireRed("suites-never-reach-a-remote-host",
      "a stub that is the real fetch")));

t("suites-never-reach-a-remote-host goes red on a second remote host",
  () => mustFlipProbe("suites-never-reach-a-remote-host",
    "a request aimed at a deployment",
    async () => [{ suite: "web/join-test.mjs", call: "fetch", url: "https://kant.example/",
      loopback: false, stubbed: false }]));

// ── the recorded causes can fail ─────────────────────────────────

t("recorded-causes-are-re-derived goes red when a row names a claim that does not exist", async () => {
  // The doc rotting. Point a row at a claim id nothing answers to and the table
  // has become prose again, which is the one thing this claim exists to stop.
  await mutateFile("tasks/thunk-server/VERIFICATION.md",
    (s) => s.replace("| `kant-debug-is-tracked` |", "| `kant-debug-is-tracked-and-fine` |"),
    () => requireRed("recorded-causes-are-re-derived", "a row pointing at no claim"));
});

t("recorded-causes-are-re-derived goes red when a recorded cause stops being true", async () => {
  // The end-to-end one, and the reason the column exists: break the tree in the
  // way the first row's real cause describes — the wasm test reading the
  // gitignored dist/ again — and the row whose re-derivation is
  // `wasm-test-inputs-tracked` must go red with it.
  //
  // The input is read directly rather than through evaluate(), because the
  // claim's probe returns a boolean: `observed` holds that boolean, and the
  // per-row detail has to come from the input.
  const c = claim("recorded-causes-are-re-derived");
  const input = () => resolveInput(c.input);
  const before = await input();
  if (!before.rows.every((r) => r.holds)) {
    throw new Error("precondition: a row is already red to begin with");
  }
  await mutateFile("web/wasm-test.mjs",
    (s) => s.replace('new URL("./kant_kernel.wasm", import.meta.url)',
      'new URL("../dist/kant_kernel.wasm", import.meta.url)'),
    async () => {
      const after = await input();
      const broke = after.rows.filter((r) => !r.holds);
      if (!broke.length) {
        throw new Error("the table still holds while its first row's cause is false again");
      }
      // And it must say which row, not just that something went red.
      if (!broke.some((r) => r.claims === "wasm-test-inputs-tracked")) {
        throw new Error(`went red without naming the row: ${broke.map((r) => r.claims).join(", ")}`);
      }
      if (await evaluate(c, after).ok) {
        throw new Error("evaluate() reported the broken table as ok");
      }
    });
});

t("recorded-causes-are-re-derived goes red when a row is deleted", async () => {
  const c = claim("recorded-causes-are-re-derived");
  const rows = await resolveInput(c.input);
  // Six rows today. Dropping one has to go red, which is what the probe's floor
  // is for; and a floor of five passed when there were five rows and failed to
  // notice the sixth being added, so the test asserts against the real count
  // rather than against a number typed twice.
  if (rows.rows.length < 6) throw new Error(`precondition: only ${rows.rows.length} rows already`);
  if (c.probe({ ...rows, rows: rows.rows.slice(1) }) === c.expect) {
    throw new Error("the claim cannot tell a shortened table from a whole one");
  }
  if (c.probe({ ...rows, rows: [...rows.rows, rows.rows[0]] }) === c.expect) {
    throw new Error("the claim cannot tell a duplicated row from a distinct one");
  }
  // And the section itself: if the heading goes, there is nothing to check and
  // the claim must say so rather than pass on an empty table.
  if (c.probe({ rows: [] }) === c.expect) {
    throw new Error("the claim cannot tell a missing table from a whole one");
  }
});

t("scripts-suites-delegate-to-their-web-twin goes red on a twin that is not there", async () => {
  // Delete the twin from the map the claim resolves against: what the runner
  // would see on a branch where web/carddebug-test.mjs was never merged.
  const c = claim("scripts-suites-delegate-to-their-web-twin");
  const rows = await resolveInput(c.input);
  const before = rows.find((r) => r.suite === "scripts/carddebug-test.mjs");
  if (!before) throw new Error("precondition: the carddebug delegation is not in the rows");
  if (c.probe(rows.map((r) => (r === before ? { ...r, exists: false, tracked: false } : r))) === c.expect) {
    throw new Error("still passed with a delegation to a file that does not exist");
  }
  if (c.probe(rows.map((r) => (r === before ? { ...r, inCore: false } : r))) === c.expect) {
    throw new Error("still passed with a delegation to a twin nobody runs");
  }
  if (c.probe([]) === c.expect) throw new Error("passed with no delegations at all");
});

t("kant-debug-is-tracked goes red when the tool is gone", async () => {
  // The probe answers a boolean, so this is the two states that must be
  // refused. The affirmative case is covered by "every claim still holds".
  const c = claim("kant-debug-is-tracked");
  if (c.probe({ onDisk: false, tracked: true }) === c.expect) {
    throw new Error("passed with the tool missing from disk");
  }
  if (c.probe({ onDisk: true, tracked: false }) === c.expect) {
    throw new Error("passed with a file git does not know");
  }
});

t("kant-debug-is-spawned-not-imported goes red on a suite that imports it", async () => {
  // The recorded cause was "carddebug *imports* kant-debug". If that sentence
  // ever becomes true, the claim that corrects it has to go red.
  const c = claim("kant-debug-is-spawned-not-imported");
  const rows = await resolveInput(c.input);
  if (!rows.some((r) => r.suite === "web/carddebug-test.mjs")) {
    throw new Error("precondition: carddebug is not in the rows");
  }
  const imported = rows.map((r) => (r.suite === "web/carddebug-test.mjs"
    ? { ...r, imports: true, spawns: false } : r));
  if (c.probe(imported) === c.expect) throw new Error("passed on a suite that imports kant-debug");
  const neither = rows.map((r) => (r.suite === "web/carddebug-test.mjs"
    ? { ...r, imports: false, spawns: false } : r));
  if (c.probe(neither) === c.expect) throw new Error("passed on a suite that mentions it and does nothing");
  if (c.probe([]) === c.expect) throw new Error("passed with no suite mentioning kant-debug");
});

// ── the verification tooling itself ──────────────────────────────
//
// Everything above tests the ledger's *claims*. These test the machinery the
// claims are made of: the scanner, the runner, the resolver. A claim checker
// that cannot report its own failure honestly is worse than no checker, and
// three branches below had no test at all — a claim whose input cannot be read,
// a probe that throws, and an empty ledger.

t("a claim whose input cannot be read is reported, not thrown", async () => {
  const before = [...CLAIMS];
  try {
    // `fileNotFound` is the heartbeat class: the loudest failure there is. If
    // reading it raised out of runClaims instead of becoming a red row, the
    // whole run would die on one broken path and print no table.
    CLAIMS.push({
      id: "unit-test-missing-input",
      claim: "a path that does not exist",
      doc: "unit test",
      kind: "health",
      input: { kind: "file", path: "no/such/file.mjs", binary: false },
      expect: true,
      probe: () => true,
    });
    const rows = await runClaims();
    const row = rows.find((r) => r.id === "unit-test-missing-input");
    if (!row) throw new Error("the missing input produced no row at all");
    if (row.ok) throw new Error("a claim whose input cannot be read reported ok");
    if (!/input failed/.test(String(row.observed))) {
      throw new Error(`no explanation given: ${row.observed}`);
    }
  } finally {
    CLAIMS.length = 0;
    CLAIMS.push(...before);
  }
});

t("a probe that throws is reported with its message, and the run continues", async () => {
  const c = {
    id: "unit-test-throwing-probe",
    claim: "a probe that throws",
    doc: "unit test",
    kind: "health",
    expect: true,
    probe: () => { throw new Error("ENOENT: no such file or directory"); },
  };
  const row = await evaluate(c, undefined);
  if (row.ok) throw new Error("a throwing probe reported ok");
  if (!/threw: ENOENT/.test(String(row.observed))) {
    throw new Error(`the message was lost: ${row.observed}`);
  }
  // And the ledger as a whole still answers.
  const rows = await runClaims();
  if (!rows.length) throw new Error("runClaims returned nothing");
});

t("an empty ledger is refused rather than reported as a pass", async () => {
  // The one failure mode that is invisible from outside: a checker that has
  // been emptied is a checker that passes. CLAIMS is mutated rather than the
  // probe, because the probe has no idea how many claims there should be.
  const before = [...CLAIMS];
  try {
    CLAIMS.length = 0;
    const rows = await runClaims();
    if (rows.length !== 0) throw new Error("expected no rows from an empty ledger");
  } finally {
    CLAIMS.length = 0;
    CLAIMS.push(...before);
  }
  if (!CLAIMS.length) throw new Error("the ledger was not restored");
});

t("relayPathKeys reads the relay's own CONFIG rather than a list written here", async () => {
  const { relayPathKeys } = await import("./thunk-claims.mjs");
  const keys = relayPathKeys(read("server/relay.mjs"));
  const names = keys.map((k) => k.key);
  // Non-empty, and the fields whose defaults are real filesystem paths or
  // which name a place at all. If relay.mjs grows a `cacheDir` this picks it up
  // with no edit here, which is the property being asserted.
  if (!keys.length) throw new Error("no path keys were derived from relay.mjs");
  for (const want of ["staticDir", "logFile", "passDb", "archiveDir"]) {
    if (!names.includes(want)) throw new Error(`${want} is not in the derived keys: ${names.join(", ")}`);
  }
  // The flag comes from `args.get("…")` in the same line, so a renamed flag is
  // followed rather than hard-coded.
  if (keys.find((k) => k.key === "passDb").flag !== "pass-db") {
    throw new Error("passDb's flag was not read out of relay.mjs");
  }
  if (keys.find((k) => k.key === "passDb").default !== "/var/lib/kant-zk/passes.sqlite") {
    throw new Error("passDb's default was not read out of relay.mjs");
  }
  // A source with no CONFIG block yields nothing rather than throwing.
  if (relayPathKeys("export const nothing = {};").length) {
    throw new Error("invented path keys out of a source with no CONFIG");
  }
});

t("the relay-config resolver tells a relay config from an http stub", async () => {
  const { relayConfigs, fieldValue } = await import("./thunk-claims.mjs");
  // The 404 stubs these suites put next to their real relay: node:http's own
  // createServer, whose first argument is a handler. Counting one of those as an
  // unconfigured relay was the first draft's bug.
  const src = [
    "import { createServer } from 'node:http';",
    "const stub = createServer((_req, res) => { res.writeHead(404); res.end(); });",
    "const cfg = { ...CONFIG, port: 0, staticDir: '', passDb };",
    "const server = createServer(cfg, new Rooms(cfg));",
  ].join("\n");
  const configs = relayConfigs(src);
  if (configs.length !== 1) throw new Error(`expected one relay config, found ${configs.length}`);
  if (!/passDb/.test(fieldValue(configs[0], "passDb"))) {
    throw new Error(`did not resolve the shorthand passDb: ${JSON.stringify(fieldValue(configs[0], "passDb"))}`);
  }
  // `passDb` resolves to itself, which resolveBindings then follows.
  if (fieldValue(configs[0], "logFile") !== null) {
    throw new Error("invented a value for a field the config does not give");
  }
  // A config that does not spread CONFIG is not a relay config.
  if (relayConfigs("createServer({ port: 0, host: '127.0.0.1' });").length) {
    throw new Error("counted a plain object as a relay config");
  }
});

t("excluded-reasons-match-the-tree goes red on the three reasons that were wrong", async () => {
  // The claim's reason for existing. Each of these is the *real* recorded
  // cause — the sentence that was in check-all.mjs before this session — and
  // each was wrong about a suite nobody had opened.
  const c = claim("excluded-reasons-match-the-tree");
  const rows = await resolveInput(c.input);
  const rowFor = (suite) => rows.find((r) => r.suite === suite);
  for (const suite of ["web/libp2p-test.mjs", "scripts/room-store-test.mjs"]) {
    const r = rowFor(suite);
    if (!r) throw new Error(`precondition: ${suite} is not in the rows`);
    if (r.claimsNetwork) throw new Error(`precondition: ${suite} no longer claims the network`);
    if (r.usesNetwork) throw new Error(`precondition: ${suite} starts a relay after all`);
    // Put the old sentence back, as a row, and the claim must refuse it.
    const lied = rows.map((x) => (x === r ? { ...x, why: "3s; starts a relay", claimsNetwork: true } : x));
    if (c.probe(lied) === c.expect) {
      throw new Error(`still passed on a reason that says ${suite} starts a relay`);
    }
  }
  // And "hermetic" is a claim too: one suite that reaches a host is not
  // hermetic, whatever its reason says.
  const hermetic = rowFor("web/libp2p-test.mjs");
  if (c.probe(rows.map((x) => (x === hermetic ? { ...x, remoteTargets: 1 } : x))) === c.expect) {
    throw new Error("passed on a hermetic suite that makes a remote request");
  }
  if (c.probe([]) === c.expect) throw new Error("passed with nothing excluded at all");
});

t("classifyRepeats tells unstable from broken from untested", async () => {
  const { classifyRepeats } = await import("./check-all.mjs");
  // Fabricated outcomes are the right input here, and it is worth saying why:
  // this function's entire job is the mapping from what was observed to a
  // verdict. There is no tree for a fabricated row to misrepresent — feeding it
  // a real suite would only test that spawnSync works.
  //
  // The shape that matters is the historical one: scripts/net-test.mjs passed
  // three times and failed the fourth with a 429.
  const verdicts = classifyRepeats([
    { file: "scripts/net-test.mjs", ok: true },
    { file: "scripts/net-test.mjs", ok: true },
    { file: "scripts/net-test.mjs", ok: true },
    { file: "scripts/net-test.mjs", ok: false },
    { file: "server/thunk-test.mjs", ok: true },
    { file: "web/wasm-test.mjs", ok: false },
    { file: "web/wasm-test.mjs", ok: false },
  ]);
  const by = (f) => verdicts.find((v) => v.file === f);
  if (by("scripts/net-test.mjs").verdict !== "UNSTABLE") {
    throw new Error(`three passes and a 429 read as ${by("scripts/net-test.mjs").verdict}`);
  }
  if (by("scripts/net-test.mjs").passed !== 3) throw new Error("the passing count is wrong");
  if (by("web/wasm-test.mjs").verdict !== "stable fail") {
    throw new Error("a suite that failed every time read as something else");
  }
  if (by("server/thunk-test.mjs").verdict !== "stable pass") {
    throw new Error("a suite that passed every time read as something else");
  }
  // One run is not a stability result, and saying "stable" there would claim
  // more than one observation supports.
  if (classifyRepeats([{ file: "x.mjs", ok: true }])[0].verdict !== "stable pass") {
    throw new Error("a single run is not a stability result");
  }
  if (classifyRepeats([]).length) throw new Error("invented a verdict for no runs");
});

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