// thunk-claims.mjs — re-verify every claim the thunk-server docs rest on.
//
// The five documents in tasks/thunk-server/ are only as good as the numbers in
// them, and a number that was true when it was written is not evidence later.
// Three mistakes this session all had the same cause: acting on a picture of the
// tree that had stopped being true. So the claims get a checker.
//
//   node scripts/thunk-claims.mjs          table, exit 1 if any claim fails
//   node scripts/thunk-claims.mjs --json   rows as JSON, for the test file
//   node scripts/thunk-claims.mjs --list   ids and claims only
//
// Each claim is a probe over one input plus the value it expects. Keeping the
// probe separable from the file read is what lets thunk-claims-test.mjs mutate
// an input and watch the claim flip — otherwise a checker that always passes
// looks exactly like a checker that is right.
//
// Claims are facts about the tree, not aspirations. Where a claim is a known
// defect (the loader throws, the id is truncated) the claim asserts the defect
// is still there, so this file going red is the signal that phase 0 landed.

import { readFileSync, readdirSync } from "node:fs";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, relative, resolve } from "node:path";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/** This file and its test, excluded from the scans that look for their own names. */
const SELF = ["scripts/thunk-claims.mjs", "scripts/thunk-claims-test.mjs"];

/** A text file in the repo, read as a string. */
const T = (path) => ({ kind: "file", path, binary: false });
/** A binary file in the repo, read as a Buffer. */
const B = (path) => ({ kind: "file", path, binary: true });
/** A value computed from the tree rather than read from one file. */
const D = (id, fn) => ({ kind: "derive", id, fn });
/** No input at all — the probe runs the thing it describes. */
const RUN = () => ({ kind: "run" });

// The identity claims below run a real thunk rather than reading its source,
// because a claim written as "this line contains X" describes a spelling and
// stops holding the moment the code is rewritten correctly.
export const { Thunk } = await import(`${ROOT}/server/thunk.mjs`);
/** The project's own comment stripper, so a scan does not have to reinvent
 *  one — and cannot disagree with the hash about what is code. */
export const { stripComments } = await import(`${ROOT}/server/js-scan.mjs`);

/** The smallest source `Thunk.load` accepts, in the dialect it accepts. */
export const THUNK_SRC = `module.exports.initialState = {};
module.exports.reduce = function reduce(s, i) {
  return { state: { n: s.n + (i.by ?? 1) }, effects: [] };
};`;

// ── the ledger ───────────────────────────────────────────────────

export const CLAIMS = [
  // ── the payload: web/kant_kernel.wasm ─────────────────────────
  {
    id: "kernel-bytes",
    claim: "web/kant_kernel.wasm is 799 bytes",
    doc: "WASM.md, SYSTEM.md",
    kind: "health",
    input: B("web/kant_kernel.wasm"),
    expect: 799,
    probe: (b) => b.length,
  },
  {
    id: "kernel-imports-zero",
    claim: "the kernel imports nothing, so isolation is a property of the artifact",
    doc: "WASM.md",
    kind: "health",
    input: B("web/kant_kernel.wasm"),
    expect: 0,
    probe: (b) => WebAssembly.Module.imports(new WebAssembly.Module(b)).length,
  },
  {
    id: "kernel-exports-21",
    claim: "the kernel exports 21 names, matching KERNEL_EXPORTS in web/kant-wasm.mjs",
    doc: "WASM.md",
    kind: "health",
    input: B("web/kant_kernel.wasm"),
    expect: 21,
    probe: (b) => WebAssembly.Module.exports(new WebAssembly.Module(b)).length,
  },
  {
    id: "kernel-frame-fraction",
    claim: "the kernel is under 5% of one 16 KiB swarm frame",
    doc: "WASM.md, THUNK-CYCLE.md",
    kind: "health",
    input: D("kernel bytes over FRAME_BYTES", () =>
      read(ROOT, "web/kant_kernel.wasm").length / 16384),
    expect: true,
    probe: (fraction) => fraction < 0.05,
  },
  {
    id: "kernel-embedded-identical",
    claim: "the embedded fallback decodes to the same bytes as web/kant_kernel.wasm",
    doc: "WASM.md",
    kind: "health",
    input: D("embedded base64", () => {
      // KERNEL_BASE64 is a multi-line concatenation of string literals, so the
      // only reliable way to read it is to take every literal in the assignment.
      const src = read(ROOT, "web/kant-kernel-embedded.mjs", "utf8");
      const body = src.split("KERNEL_BASE64")[1]?.split(";")[0] ?? "";
      const parts = [...body.matchAll(/"([A-Za-z0-9+/=]*)"/g)].map((m) => m[1]);
      if (!parts.length) return null;
      return Buffer.from(parts.join(""), "base64");
    }),
    expect: true,
    probe: (b) => b !== null && b.equals(read(ROOT, "web/kant_kernel.wasm")),
  },
  {
    id: "kernel-length-constant",
    claim: "KERNEL_LENGTH claims 799, the size of the binary it was generated from",
    doc: "WASM.md",
    kind: "health",
    input: T("web/kant-kernel-embedded.mjs"),
    expect: true,
    probe: (src) => {
      const m = src.match(/KERNEL_LENGTH\s*=\s*(\d+)/);
      return !!m && Number(m[1]) === read(ROOT, "web/kant_kernel.wasm").length;
    },
  },
  {
    id: "kernel-bytes-is-function",
    claim: "kernelBytes is exported as a function, not as a value",
    doc: "WASM.md",
    kind: "health",
    input: T("web/kant-kernel-embedded.mjs"),
    expect: true,
    probe: (src) => /export function kernelBytes\s*\(/.test(src),
  },

  // ── identity: the content hash and the call id ────────────────
  // These run the real code rather than reading it. A claim written as "this
  // line contains `.slice(0, 16)`" describes a spelling; these describe
  // behaviour, and they would still hold if the implementation were rewritten.
  {
    id: "thunk-id-is-64-hex",
    claim: "a thunk's contentHash is the full 64-hex digest, not a 16-char prefix",
    doc: "WASM.md, SYSTEM.md",
    kind: "health",
    input: RUN(),
    expect: true,
    probe: async () => {
      const t = await Thunk.load(THUNK_SRC, "counter", "1.0.0");
      return /^[0-9a-f]{64}$/.test(t.contentHash);
    },
  },
  {
    id: "thunk-id-avoids-name-and-version",
    claim: "renaming a thunk or bumping its version does not change its contentHash",
    doc: "WASM.md, SYSTEM.md",
    kind: "health",
    input: RUN(),
    expect: true,
    probe: async () => {
      const a = await Thunk.load(THUNK_SRC, "counter", "0.0.0");
      const b = await Thunk.load(THUNK_SRC, "other-name", "9.9.9");
      return a.contentHash === b.contentHash;
    },
  },
  {
    id: "thunk-id-separates-urls",
    claim: "two thunks differing only in a `//` inside a string literal get different ids",
    doc: "SYSTEM.md, SANDBOX.md",
    kind: "health",
    input: RUN(),
    expect: true,
    probe: async () => {
      // The bug this pins: the old id stripped comments with a regex, which
      // also stripped `//` inside a string, so a URL was cut at `http:` and
      // every URL in the tree hashed the same.
      const withUrl = (url) =>
        `module.exports.initialState = {};\n` +
        `module.exports.reduce = function reduce(s, i) { return { state: { url: "${url}" }, effects: [] }; };`;
      const a = await Thunk.load(withUrl("http://alpha.example/x"), "f", "1.0.0");
      const b = await Thunk.load(withUrl("http://bravo.evil.example"), "f", "1.0.0");
      return a.contentHash !== b.contentHash;
    },
  },
  {
    id: "thunk-id-ignores-comments",
    claim: "a comment or a reindent does not change a thunk's contentHash",
    doc: "SYSTEM.md",
    kind: "health",
    input: RUN(),
    expect: true,
    probe: async () => {
      const body = (mid) =>
        `module.exports.initialState = {};\n` +
        `module.exports.reduce = function reduce(s, i) {\n  ${mid}\n  return { state: { n: s.n }, effects: [] };\n};`;
      const a = await Thunk.load(body(""), "r", "1.0.0");
      const b = await Thunk.load(body("// a comment"), "r", "1.0.0");
      const c = await Thunk.load(body("/* another */"), "r", "1.0.0");
      return a.contentHash === b.contentHash && a.contentHash === c.contentHash;
    },
  },
  {
    id: "comment-stripper-is-not-a-regex",
    claim: "server/js-scan.mjs scans for comments rather than substituting a regex",
    doc: "SYSTEM.md",
    kind: "health",
    input: T("server/js-scan.mjs"),
    expect: true,
    // The tell is the absence of the two `replace` calls the old version used.
    // A hand-written scanner has no `//`-stripping regex at all.
    probe: (src) => /export function stripComments/.test(src) && !/\.replace\(\/\\\/\.\*\$/.test(src),
  },
  {
    id: "thunk-id-covers-refs",
    claim: "refs are part of the contentHash, and their order is not",
    doc: "TOOLCHAIN-THUNKS.md, IPFS-IPDL.md",
    kind: "health",
    input: RUN(),
    expect: true,
    probe: async () => {
      const a = await Thunk.load(THUNK_SRC, "c", "1.0.0", {}, []);
      const b = await Thunk.load(THUNK_SRC, "c", "1.0.0", {}, ["lake"]);
      const c = await Thunk.load(THUNK_SRC, "c", "1.0.0", {}, ["a", "b"]);
      const d = await Thunk.load(THUNK_SRC, "c", "1.0.0", {}, ["b", "a"]);
      return a.contentHash !== b.contentHash && c.contentHash === d.contentHash;
    },
  },
  {
    id: "call-id-exists",
    claim: "Thunk.callId is distinct from the thunk id and varies with args, secretRefs and apiRefs",
    doc: "THUNK-CYCLE.md",
    kind: "health",
    input: RUN(),
    expect: true,
    probe: async () => {
      const t = await Thunk.load(THUNK_SRC, "c", "1.0.0");
      const base = t.callId({ a: 1 });
      return /^[0-9a-f]{64}$/.test(base)
        && base !== t.contentHash
        && base !== t.callId({ a: 2 })
        && base !== t.callId({ a: 1 }, { secretRefs: ["KEY"] })
        && base !== t.callId({ a: 1 }, { apiRefs: ["fs"] })
        && t.callId({ a: 1 }, { secretRefs: ["x", "y"] })
           === t.callId({ a: 1 }, { secretRefs: ["y", "x"] });
    },
  },
  {
    id: "args-hash-sorts-keys",
    claim: "argsHash ignores object key order, which canonEnc would otherwise encode",
    doc: "THUNK-CYCLE.md",
    kind: "health",
    input: RUN(),
    expect: true,
    probe: async () => {
      const t = await Thunk.load(THUNK_SRC, "c", "1.0.0");
      return t.argsHash({ a: 1, b: 2 }) === t.argsHash({ b: 2, a: 1 })
        && t.argsHash({ a: 1 }) !== t.argsHash({ a: 2 });
    },
  },
  {
    id: "codec-has-no-float",
    claim: "the codec has exactly the six value types that Kant.Codec.Val defines",
    doc: "SYSTEM.md",
    kind: "health",
    input: RUN(),
    expect: true,
    probe: async () => {
      const C = await import(`${ROOT}/scripts/kant-codec.mjs`);
      // Lean proves `canonEnc_injective` over six constructors, and IPDL drops
      // floats for binary compatibility while proving the projection LOSSLESS.
      // A seventh type here would be a value the wire format is specified to
      // discard, and the JS codec would stop being a transcription.
      if (typeof C.vFloat === "function") return false;
      const six = [C.vNull, C.vBool(true), C.vInt(-7), C.vStr("x"),
        C.vList([C.vInt(1)]), C.vObj([["k", C.vInt(1)]])];
      if (six.length !== 6) return false;
      // All six still round-trip through all five projections.
      for (const v of six) {
        const back = [
          C.canonDecode(C.canonEnc(v)),
          C.yamlDecode(C.yamlEnc(v)),
          C.xmlDecode(C.xmlEnc(v)),
          C.csvDecode(C.csvEncode(v)),
          C.ipdlRead(C.ipdlText(C.embed(v))),
        ];
        for (const b of back) {
          if (!b || C.canonEnc(b) !== C.canonEnc(v)) return false;
        }
      }
      // Injectivity, which is what Lean actually proves: distinct tags.
      const tags = six.map((v) => C.canonEnc(v)[0]);
      return new Set(tags).size === tags.length;
    },
  },
  {
    id: "verify-entrypoint-runs-the-suites",
    claim: "npm run verify runs the suites, including both Lean cross-checks",
    doc: "VERIFICATION.md",
    kind: "health",
    input: RUN(),
    expect: true,
    // The repository had 50 tracked suites and nothing that ran them: `npm test`
    // is a puppeteer test needing a live server, and the Makefile has no test
    // target. So a codec change could ship with nothing green-checked, which is
    // how the float got in.
    probe: async () => {
      const { runOne, CORE, trackedSuites, EXCLUDED } =
        await import(`${ROOT}/scripts/check-all.mjs`);
      if (!CORE.includes("scripts/lean-codec-vectors.mjs")) return false;
      if (!CORE.includes("scripts/lean-codec-types.mjs")) return false;
      if (!CORE.includes("scripts/thunk-claims.mjs")) return false;
      // Every tracked suite is in one list or the other, so a new one cannot be
      // added and go unnoticed.
      const known = new Set([...CORE, ...Object.keys(EXCLUDED)]);
      if (trackedSuites().some((f) => !known.has(f))) return false;
      // And the runner really runs them: a stubbed runner would pass the three
      // checks above without executing a thing.
      const r = runOne("scripts/lean-codec-vectors.mjs", 60000);
      return r.ok;
    },
  },
  {
    id: "js-codec-matches-lean-source",
    claim: "the JS codec encodes exactly the value types Kant.Codec defines",
    doc: "VERIFICATION.md",
    kind: "health",
    input: RUN(),
    expect: true,
    // Reads `RequestProject/Kant/Codec/Val.lean` out of this repository's own
    // `feature/lean` at a pinned commit. Red when the object is unreachable,
    // not skipped: a checker that skips quietly when it cannot see the thing it
    // checks reads as a green run, which is the exact failure it exists to
    // catch. The message says how to fix it.
    probe: async () => {
      const { compare } = await import(`${ROOT}/scripts/lean-codec-types.mjs`);
      const out = await compare();
      return out.rows.every((r) => r.ok)
        ? true
        : `JS/Lean type mismatch: ${out.rows.filter((r) => !r.ok).map((r) => r.detail).join(" | ")}`;
    },
  },
  {
    id: "golden-vector-matches-lean",
    claim: "the JS codec produces the six values Lean's #guard pins for gSample",
    doc: "VERIFICATION.md",
    kind: "health",
    input: RUN(),
    expect: true,
    // The value counterpart to `js-codec-matches-lean-source`: that one compares
    // which types each side can name, this one compares what they produce for
    // the value both are documented to serialise. A codec can agree with Lean
    // about its shapes and still serialise differently.
    probe: async () => {
      const { compareVectors } = await import(`${ROOT}/scripts/lean-codec-vectors.mjs`);
      const out = await compareVectors();
      return out.rows.every((r) => r.ok)
        ? true
        : `vector mismatch: ${out.rows.filter((r) => !r.ok).map((r) => r.detail).join(" | ")}`;
    },
  },
  {
    id: "thunk-id-is-lean-representable",
    claim: "a thunk id is a valHash of a value naming only shapes Kant.Codec defines",
    doc: "VERIFICATION.md, SYSTEM.md",
    kind: "health",
    input: RUN(),
    expect: true,
    probe: async () => {
      const { thunkDefinitionVal, isLeanRepresentable, LEAN_VAL_TAGS } =
        await import(`${ROOT}/server/thunk-id.mjs`);
      // `Val.lean:37` has six constructors; `Ipdl.lean` adds `ref` and `annot`.
      // Anything else is a value the wire format is specified to discard.
      if (LEAN_VAL_TAGS.length !== 8) return false;
      if (!isLeanRepresentable(thunkDefinitionVal(THUNK_SRC, ["lake"]))) return false;
      // And the guard has to notice a foreign shape, which is exactly what a
      // JS-only round-trip suite cannot do: a new tag does not collide.
      return !isLeanRepresentable({ t: "float", n: 1.5 })
        && !isLeanRepresentable({ t: "obj", fs: [["a", { t: "float", n: 1 }]] })
        && isLeanRepresentable({ t: "ref", target: "x" });
    },
  },
  {
    id: "fractional-argument-refused",
    claim: "argsHash refuses a non-integer number and -0, because Val has no float",
    doc: "SYSTEM.md, THUNK-CYCLE.md",
    kind: "health",
    input: RUN(),
    expect: true,
    probe: async () => {
      const t = await Thunk.load(THUNK_SRC, "c", "1.0.0");
      for (const n of [1.5, -0.25, 1e-7, -0]) {
        let threw = false;
        try { t.argsHash({ n }); } catch { threw = true; }
        if (!threw) return false;
      }
      // Integers still work, and 1 is 1.
      return t.argsHash({ n: 1 }) === t.argsHash({ n: 1 })
        && t.argsHash({ n: 1 }) !== t.argsHash({ n: 2 });
    },
  },
  {
    id: "unaddressable-input-refused",
    claim: "argsHash throws on a value with no content address rather than coercing it",
    doc: "THUNK-CYCLE.md",
    kind: "health",
    input: RUN(),
    expect: true,
    probe: async () => {
      const t = await Thunk.load(THUNK_SRC, "c", "1.0.0");
      for (const v of [undefined, NaN, Infinity, 1.5, -0, () => 1, new Date(0), new Map()]) {
        let threw = false;
        try { t.argsHash({ v }); } catch { threw = true; }
        if (!threw) return false;
      }
      const cyclic = {};
      cyclic.self = cyclic;
      let threw = false;
      try { t.argsHash(cyclic); } catch { threw = true; }
      return threw;
    },
  },
  {
    id: "witness-needs-64",
    claim: "asWitness accepts only a 64-char hex string",
    doc: "WASM.md",
    kind: "health",
    input: T("web/kant-libp2p.mjs"),
    expect: true,
    probe: (src) => /asWitness[\s\S]{0,200}length !== 64[\s\S]{0,120}\{64\}/.test(src),
  },

  // ── thunk mechanics, including the three known defects ────────
  {
    id: "thunk-loads",
    claim: "Thunk.load loads a valid source; phase 0 fixed the loader",
    doc: "WASM.md, SANDBOX.md",
    kind: "health",
    input: RUN(),
    expect: true,
    probe: async () => {
      const { Thunk } = await import("../server/thunk.mjs");
      const t = await Thunk.load(
        "module.exports.initialState = { n: 0 };\n" +
        "module.exports.reduce = (s, i) => ({ state: { n: s.n + (i.by ?? 1) }, effects: [] });",
        "probe", "0.0.0");
      t.apply({ by: 2 });
      return t.apply({ by: 3 }).state.n === 5;
    },
  },
  {
    id: "sandbox-has-no-require",
    claim: "the vm context is built empty apart from module/exports, so require is unreachable",
    doc: "SANDBOX.md",
    kind: "health",
    input: T("server/thunk.mjs"),
    expect: true,
    // `module` must be created inside the context with runInContext. Passing a
    // host object in is a realm bridge, which is how the first fix still leaked.
    probe: (src) =>
      /runInContext\("var module = \{ exports: \{\} \}; var exports = module\.exports;"/.test(src) &&
      !/createRequire/.test(src),
  },
  {
    id: "sandbox-refuses-console",
    claim: "console is deleted from the context before a thunk loads",
    doc: "SANDBOX.md",
    kind: "health",
    input: T("server/thunk.mjs"),
    expect: true,
    probe: (src) => /delete globalThis\.console/.test(src),
  },
  {
    id: "sandbox-refuses-dynamic-import",
    claim: "a source containing import( is refused at load time, before compilation",
    doc: "SANDBOX.md",
    kind: "health",
    input: T("server/thunk.mjs"),
    expect: true,
    // Refusing during execution does not work: ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING
    // ignores the thunk's try/catch and kills the host process.
    // The guard is one regex literal covering both spellings, so check that it
    // names both rather than that it mentions `import.meta` verbatim -- the
    // source says `import\s*\.\s*meta`.
    probe: (src) =>
      /const forbidden = source\.match\(/.test(src) &&
      /import\\s\*\\\(/.test(src) &&
      /meta/.test(src),
  },
  {
    id: "apply-unwraps",
    claim: "apply() unwraps {state, effects}, so state accumulates across calls",
    doc: "WASM.md, THUNK-CYCLE.md",
    kind: "health",
    input: T("server/thunk.mjs"),
    expect: true,
    probe: (src) => /const \{ reduce \} = this\.#compiled\.transducers;/.test(src),
  },
  {
    id: "snapshot-deep-copies",
    claim: "snapshot() deep-copies state through JSON.parse(JSON.stringify(...))",
    doc: "THUNK-CYCLE.md §4",
    kind: "health",
    input: T("server/thunk.mjs"),
    expect: true,
    probe: (src) => /JSON\.parse\(JSON\.stringify\(/.test(src),
  },

  // ── the scheduler has no notion of a constraint ───────────────
  {
    id: "schedule-has-no-constraint",
    claim: "server/schedule.mjs has no budget/limit/max/headroom/duration vocabulary",
    doc: "THUNK-CYCLE.md §5",
    kind: "defect",
    input: T("server/schedule.mjs"),
    expect: true,
    probe: (src) => !/budget|limit|max|headroom|duration/i.test(src),
  },
  {
    id: "schedule-api",
    claim: "Schedule has add, remove, tick and installManifest",
    doc: "THUNK-CYCLE.md §5",
    kind: "health",
    input: T("server/schedule.mjs"),
    expect: true,
    probe: (src) =>
      ["add", "remove", "tick", "installManifest"].every((m) =>
        new RegExp(`\\b${m}\\s*\\(`).test(src)),
  },

  // ── IPDL: ref is written and read, never resolved ─────────────
  {
    id: "ipdl-ref-three-sites",
    claim: "IPDL_REF appears at exactly 3 sites: defined, projected, read back",
    doc: "IPFS-IPDL.md",
    kind: "health",
    input: T("scripts/kant-codec.mjs"),
    expect: 3,
    probe: (src) => (src.match(/\bIPDL_REF\b/g) || []).length,
  },
  {
    id: "ref-never-resolved",
    claim: "nothing in scripts/, web/ or server/ ever calls a resolver on a ref target",
    doc: "IPFS-IPDL.md",
    kind: "defect",
    input: D("all js sources", () =>
      ["scripts", "web", "server"]
        .flatMap((d) => walk(resolve(ROOT, d)))
        // Excluded on purpose: this file and its test have to *name* a resolver
        // in order to assert that nothing calls one. A claim that scans its own
        // source for the word it is looking for is a claim that always fails.
        .filter((f) => !SELF.includes(relative(ROOT, f)))
        .map((f) => read(ROOT, relative(ROOT, f), "utf8"))
        .join("\n")),
    expect: true,
    // Requires a call site, not just the name. Without the parens this claim
    // trips over its own regex literal in this file, which is the kind of
    // self-reference that makes a checker worthless.
    probe: (src) => !/\b(resolveRef|iResolve|resolveTarget|fetchRef)\s*\(/.test(src),
  },
  {
    id: "ipdl-ref-roundtrips",
    claim: "a doc carrying iRef round-trips the target exactly and hashes stably",
    doc: "IPFS-IPDL.md",
    kind: "health",
    input: RUN(),
    expect: true,
    // Uses the real nixpkgs pin from flake.nix rather than a made-up target, so
    // the claim is about this tree's actual reference and not a fixture.
    probe: async () => {
      const c = await import("./kant-codec.mjs");
      const flake = read(ROOT, "flake.nix", "utf8");
      const target = flake.match(/nixpkgs\.url\s*=\s*"([^"]+)"/)?.[1];
      if (!target) return false;
      const annot = c.iAnnot("dep", "nixpkgs", c.iRef(target));
      const canon = c.project(annot);
      const back = c.recover(canon);
      const viaText = c.ipdlRead(c.ipdlText(annot));
      const h = c.valHash(canon);
      const other = c.valHash(c.project(c.iAnnot("dep", "nixpkgs", c.iRef(target + "0"))));
      return (
        back.body.target === target &&
        viaText?.body?.target === target &&
        h === c.valHash(c.project(back)) &&
        h !== other &&
        h.length === 64
      );
    },
  },

  // ── build inputs are pinned, except one that is not ───────────
  {
    id: "flake-inputs-sha-pinned",
    claim: "every flake input is a github: URL pinned to a 40-hex sha, never a branch",
    doc: "IPFS-IPDL.md, TOOLCHAIN-THUNKS.md",
    kind: "health",
    input: T("flake.nix"),
    expect: true,
    probe: (src) => {
      const urls = [...src.matchAll(/([\w-]+)\.url\s*=\s*"([^"]+)"/g)].map((m) => m[2]);
      return (
        urls.length >= 4 &&
        urls.every((u) => /^github:[^/]+\/[^/]+\/[0-9a-f]{40}$/.test(u))
      );
    },
  },
  {
    id: "nora-wildcard-version",
    claim: "Cargo.toml pins rust-unixfs by version \"*\", a live name-vs-registry dependency",
    doc: "IPFS-IPDL.md",
    kind: "defect",
    input: T("Cargo.toml"),
    expect: true,
    probe: (src) => /rust-unixfs\s*=\s*\{[^}]*version\s*=\s*"\*"/.test(src),
  },

  // ── the measured cadence ──────────────────────────────────────
  {
    id: "telemetry-11s",
    claim: "the sustainable poll interval is every 11s per worker",
    doc: "THUNK-CYCLE.md §5",
    kind: "health",
    input: D("sustainableIntervalSeconds", async () => {
      const { sustainableIntervalSeconds } = await import("./relay-telemetry.mjs");
      return sustainableIntervalSeconds().secondsBetweenPolls;
    }),
    expect: 11,
    probe: (s) => s,
  },
  {
    id: "telemetry-headroom-reserved",
    claim: "half the Durable Object allowance is held back as headroom",
    doc: "THUNK-CYCLE.md §5",
    kind: "health",
    input: D("readBudget", async () => {
      const { readBudget } = await import("./relay-telemetry.mjs");
      return readBudget().headroom;
    }),
    expect: 0.5,
    probe: (h) => h,
  },

  // ── secrets ───────────────────────────────────────────────────
  {
    id: "sops-path-exists",
    claim: "the sops entry point, its config and its registry all exist",
    doc: "THUNK-CYCLE.md §1",
    kind: "health",
    input: D("sops paths", () =>
      [".sops.yaml", ".sops/registry.sops.yaml", "scripts/sops-run.sh"]
        .map((p) => exists(resolve(ROOT, p)))),
    expect: [true, true, true],
    probe: (found) => found,
  },

  // ── a suite must not write outside its own temp directory ──────────────
  //
  // The first version of this guard checked one field of one config: `passDb`,
  // whose default in server/relay.mjs is /var/lib/kant-zk/passes.sqlite. Two
  // tracked suites were starting a relay without overriding it, so every run
  // appended peer_posts rows to a live relay's rate-limit ledger.
  //
  // Checking one field was the mistake the section above this block records,
  // one level down. The relay takes four paths -- `staticDir`, which it only
  // reads, and `logFile`, `passDb` and `archiveDir`, which it writes -- so
  // "passDb is overridden" said nothing at all about the other two writes. And
  // both of those were wrong in the tree: web/diag-test.mjs pointed `--log` at
  // `web/.diag-relay.log`, inside the checkout, and web/file-test.mjs handed the
  // relay a *fixed* `/tmp/kant-file-test/passes.sqlite` and
  // `/tmp/kant-file-test/archive`, shared by every concurrent run of that
  // suite. Neither is visible to a check for one field.
  //
  // So the set of paths is no longer written down here. relayPathKeys() reads
  // the CONFIG block out of server/relay.mjs, keeps every key that names a
  // place on disk, and reports the flag and the env var that override each --
  // so a new `cacheDir` is covered the day it is written, and a path whose
  // relay default is non-empty and which a suite then fails to override is
  // caught by the same rule that caught `passDb`.
  {
    id: "suites-write-only-into-their-own-temp-dir",
    claim: "every path a tracked suite hands a relay is under the OS temp directory, never the checkout and never a shared fixed path",
    doc: "VERIFICATION.md",
    kind: "health",
    input: D("every relay path a tracked suite supplies, against relay.mjs's own CONFIG", async () => {
      const { trackedSuites } = await import(`${ROOT}/scripts/check-all.mjs`);
      const keys = relayPathKeys(read(ROOT, "server/relay.mjs", "utf8"))
        .filter((k) => !RELAY_READ_ONLY.has(k.key));
      return trackedSuites().flatMap((suite) => {
        const src = read(ROOT, suite, "utf8");
        // The candidate set is deliberately wider than the scanned set: every
        // tracked suite that mentions the relay *at all*. A guard cannot
        // notice a suite that has left it — that is the failure this row is for,
        // and it happened: web/diag-test.mjs moved its inline spawn into
        // scripts/relay-start.mjs, stopped matching a trigger that looked for
        // `spawn(`, and dropped out of the scan on the commit that made it
        // start passing. A suite that mentions the relay and is then not
        // scanned is a hole, and it is reported as one rather than as a
        // shorter list.
        const code = withoutComments(src);
        const use = relayUse(src);
        if (!use.mentions) return [];
        // This ledger and its own test are excluded, and the probe below allows
        // no other suite to be. thunk-claims-test.mjs writes a whole suite's
        // source as a *string* — a broken copy of web/diag-test.mjs, to prove a
        // claim can go red — and that string contains `spawn(… relayPath …)` and
        // `--log", logFile`. Distinguishing a spawn call from a spawn call
        // quoted inside a string needs a parser, not a scanner. What the file
        // actually does is write two tracked files and restore both in a
        // `finally`, which is not production state. The rows say so rather than
        // passing quietly.
        if (SELF.includes(suite)) {
          return [{ suite, mode: "excluded", key: null, paths: 1, outside: 0,
            why: "holds a suite's source as a string, and restores what it writes" }];
        }
        // A delegating suite opens no path of its own: it inherits its twin's,
        // and the twin is scanned in its own right.
        if (use.delegates) {
          return [{ suite, mode: "delegates", key: null, paths: 1, outside: 0 }];
        }
        // A suite reaches relay state by running one. Two routes, and both
        // have to be here: an in-process createServer/createRelay, or a child
        // process — which now includes the suites that call the shared
        // scripts/relay-start.mjs rather than spawning inline.
        const { configs, onArgv } = use;
        if (!use.creating) {
          return [{ suite, mode: "NOT SCANNED", key: null, paths: 1, outside: 0,
            why: "mentions the relay but neither builds one nor spawns one" }];
        }
        const roots = tempRoots(code);
        return keys.map((key) => {
          // Every place this suite could hand that path to a relay: each
          // config object, and — when it runs a relay as a child — the argv.
          const sites = [
            ...configs.map((text) => ({ via: "config", expr: fieldValue(text, key.key) })),
            ...(onArgv ? [{ via: "argv", expr: suppliedOnArgv(code, key) }] : []),
          ];
          const judged = sites.map(({ via, expr }) => {
            // Not supplying it is safe only when the relay's own default is
            // empty, i.e. no write happens at all. `passDb`'s default is a real
            // path; `logFile`'s and `archiveDir`'s are "", and those two are why
            // "is passDb set" was never the question to ask.
            if (expr === null) return { via, expr: null, safe: key.default === "" };
            const full = resolveBindings(code, expr);
            return { via, expr, safe: insideTemp(full, roots) };
          });
          const outside = judged.filter((j) => !j.safe);
          return {
            suite,
            key: key.key,
            mode: outside.length ? "OUTSIDE TMP" : "own tmp",
            expr: judged.find((j) => j.expr)?.expr ?? null,
            paths: judged.length,
            outside: outside.length,
          };
        });
      });
    }),
    // Non-empty (so a scan that stopped matching cannot pass vacuously),
    // nothing outside a temp directory, and every row actually looked at
    // something -- a suite whose configs the scanner could not find must not
    // pass by finding nothing.
    expect: true,
    probe: (rows) => rows.length > 0
      && rows.every((r) => r.outside === 0 && r.paths > 0)
      && rows.every((r) => r.mode !== "OUTSIDE TMP")
      // A suite that mentions the relay and is then not judged. Written into
      // the probe only after the mutation test below showed that a NOT SCANNED
      // row is shaped exactly like a passing one — outside: 0, paths: 1 — and
      // sailed through. That is the shape of every guard that rots silently.
      && rows.every((r) => r.mode !== "NOT SCANNED")
      // An `excluded` row is only allowed for this ledger's own files, so the
      // exemption cannot quietly grow.
      && rows.every((r) => r.mode !== "excluded" || SELF.includes(r.suite)),
  },
  {
    id: "suites-never-reach-a-remote-host",
    claim: "no tracked suite lets a request reach a host outside loopback, so a suite called hermetic cannot touch a deployment",
    doc: "VERIFICATION.md",
    kind: "health",
    input: D("every URL a tracked suite hands to something that makes a request", async () => {
      const { trackedSuites } = await import(`${ROOT}/scripts/check-all.mjs`);
      return trackedSuites().flatMap((suite) =>
        requestTargets(read(ROOT, suite, "utf8")).map((r) => ({ ...r, suite })));
    }),
    // Non-empty (a scan that stopped matching cannot pass vacuously), and every
    // target either on this machine / on a name that cannot resolve, or handed
    // to a call that was given a fetch of its own.
    expect: true,
    probe: (rows) => rows.length > 0 && rows.every((r) => r.loopback || r.stubbed),
  },

  // ── the recorded causes, re-derived ──────────────────────────────
  //
  // Every defect below was recorded with a cause, and not one of those causes
  // was accurate enough to act on. The table in VERIFICATION.md therefore grew a
  // third column: the claim that re-derives the real cause from the tree. The
  // four claims here are the ones the five rows point at, and they exist for
  // that table -- without them the column would name nothing.
  {
    id: "scripts-suites-delegate-to-their-web-twin",
    claim: "every suite in scripts/ that delegates to web/ names a twin that exists, is tracked, and is in the core run",
    doc: "VERIFICATION.md",
    kind: "health",
    input: D("each scripts/ delegation, resolved against the tree and the runner's manifest", async () => {
      const { CORE, trackedSuites } = await import(`${ROOT}/scripts/check-all.mjs`);
      const tracked = new Set(execFileSync("git", ["ls-files"], { cwd: ROOT, encoding: "utf8" })
        .split("\n").filter(Boolean));
      return trackedSuites().flatMap((suite) => {
        const src = read(ROOT, suite, "utf8");
        const m = /^import\s+["'](\.\.\/web\/[^"']+)["']/m.exec(src.trim());
        if (!m) return [];
        const twin = relative(ROOT, resolve(dirname(resolve(ROOT, suite)), m[1]));
        return [{
          suite,
          twin,
          // A delegation to a file that is not there, or to one git does not
          // know, is a suite that dies with ERR_MODULE_NOT_FOUND on a clean
          // checkout -- and a twin outside CORE is a twin nobody runs.
          exists: exists(resolve(ROOT, twin)),
          tracked: tracked.has(twin),
          inCore: CORE.includes(twin),
        }];
      });
    }),
    // Non-empty (nine of them today), and each resolves to something real.
    expect: true,
    probe: (rows) => rows.length > 0
      && rows.every((r) => r.exists && r.tracked && r.inCore),
  },
  {
    id: "kant-debug-is-tracked",
    claim: "scripts/kant-debug.mjs exists and git knows it, so the carddebug suites have something to run",
    doc: "VERIFICATION.md",
    kind: "health",
    // This is the row in the table that reads "`scripts/kant-debug.mjs` does
    // not exist". That was true of this branch and false of the repository —
    // the file is on origin/feature/lean and origin/feat/build-feed, and the
    // big merge dropped it. Two suites were BROKEN for a tool that existed.
    input: D("scripts/kant-debug.mjs against the file and against git", () => ({
      onDisk: exists(resolve(ROOT, "scripts/kant-debug.mjs")),
      tracked: execFileSync("git", ["ls-files", "--error-unmatch", "scripts/kant-debug.mjs"],
        { cwd: ROOT, encoding: "utf8" }).trim() === "scripts/kant-debug.mjs",
    })),
    expect: true,
    probe: (r) => r.onDisk === true && r.tracked === true,
  },
  {
    id: "kant-debug-is-spawned-not-imported",
    claim: "the carddebug suites run kant-debug as a child process, which is why the recorded cause said they imported it",
    doc: "VERIFICATION.md",
    kind: "health",
    // The recorded cause here was not incomplete but *misfiled*: carddebug was
    // listed next to four suites that do `import` kant-debug, and it does not.
    // It execs it. The difference matters — an import is checked by a bundler
    // and by the file existing, a spawn is checked by neither, which is exactly
    // why the missing tool survived a "the import is fine" reading.
    input: D("every suite that mentions kant-debug, and how it uses it", async () => {
      const { trackedSuites } = await import(`${ROOT}/scripts/check-all.mjs`);
      return trackedSuites().flatMap((suite) => {
        // Comments out: scripts/carddebug-test.mjs now explains in prose why it
        // delegates, and that prose names the tool. A reference in a comment is
        // not a dependency.
        const src = withoutComments(read(ROOT, suite, "utf8"));
        if (!/kant-debug/.test(src)) return [];
        return [{
          suite,
          imports: /(?:^|\n)\s*import[^;\n]*kant-debug/.test(src),
          spawns: /\b(?:spawn|spawnSync|exec|execSync|execFile|execFileSync)\s*\(/.test(src)
            && /kant-debug/.test(src),
        }];
      });
    }),
    // Non-empty, and every suite that touches kant-debug runs it as a child.
    // A suite that *imports* it would be a different kind of dependency, and
    // one that does neither is a reference to nothing.
    expect: true,
    probe: (rows) => rows.length > 0
      && rows.every((r) => r.spawns && !r.imports),
  },

  // ── the recorded causes are re-derived, not remembered ─────────────
  //
  // The section above is the one that says a recorded cause is a hypothesis.
  // This claim is that sentence made executable: it reads the table out of
  // VERIFICATION.md, insists every row names a claim, insists those claims
  // exist, and then runs them against the tree.
  //
  // Without it the table is prose, and prose about the tree is exactly what
  // this ledger exists to stop believing. With it, deleting a claim to make the
  // ledger green takes the table red with it.
  {
    id: "recorded-causes-are-re-derived",
    claim: "every recorded cause in VERIFICATION.md names a claim that exists and still holds, so the table cannot outlive the tree",
    doc: "VERIFICATION.md",
    kind: "health",
    input: D("the table of recorded causes, and each claim it names", async () => {
      const doc = read(ROOT, "tasks/thunk-server/VERIFICATION.md", "utf8");
      const section = /## The recorded cause was wrong every single time([\s\S]*?)\n##\s/.exec(doc);
      if (!section) return { error: "the section is gone", rows: [] };
      const rows = [];
      for (const line of section[1].split("\n")) {
        if (!line.startsWith("|")) continue;
        const cells = line.split("|").slice(1, -1).map((c) => c.trim());
        // The last cell is the one that must name a claim. Keying on that and
        // not on a leading backtick matters: two of the five rows start with
        // prose ("five suites …", "carddebug …") and a scan keyed on the first
        // cell silently found two rows out of five and called it a pass.
        const named = /^`([a-z0-9-]+)`$/.exec(cells[cells.length - 1] ?? "");
        if (!named) continue;
        rows.push({
          recorded: cells[0],
          truth: cells[1],
          claims: named[1],
        });
      }
      // Each named claim is evaluated against the live tree, so a row whose
      // real cause has stopped being true goes red here too.
      const judged = await Promise.all(rows.map(async (r) => {
        const c = CLAIMS.find((x) => x.id === r.claims);
        if (!c) return { ...r, known: false, holds: false };
        const result = await evaluate(c, await resolveInput(c.input));
        return { ...r, known: true, holds: result.ok };
      }));
      return { rows: judged };
    }),
    expect: true,
    probe: (r) => {
      if (r.error) return false;
      const rows = r.rows;
      // One row per recorded cause, and each row naming a different claim: a
      // table that grows a row pointing at a claim already listed is padding,
      // and a table that loses one has lost the reason a fix was made.
      //
      // MIN is a stated number, not a derived one, and that is a real limit of
      // this claim — nothing in the tree knows how many defects there were. It
      // is written down so that lowering it is a visible edit rather than a
      // quiet one.
      if (rows.length < MIN_RECORDED_CAUSES) return false;
      if (new Set(rows.map((x) => x.claims)).size !== rows.length) return false;
      return rows.every((x) => x.known && x.holds && x.claims);
    },
  },

  {
    id: "excluded-reasons-match-the-tree",
    claim: "every suite check-all.mjs excludes says why, and the reason is still true of the suite it names",
    doc: "VERIFICATION.md",
    kind: "health",
    input: D("each EXCLUDED entry against the suite it names", async () => {
      const { EXCLUDED } = await import(`${ROOT}/scripts/check-all.mjs`);
      return Object.entries(EXCLUDED).map(([suite, why]) => {
        const src = read(ROOT, suite, "utf8");
        const use = relayUse(src);
        // Two claims a reason can make that are checkable from the source: that
        // the suite needs the network, and that it is hermetic. A claim about
        // seconds is not — it is true or false on the day it was measured, and
        // nothing in the tree settles it.
        return {
          suite,
          why,
          claimsNetwork: /\b(?:starts|binds|needs|posts to|against)\s+(?:a\s+)?(?:live|real|production)?\s*relay\b/i.test(why)
            || /\bnot hermetic\b/i.test(why),
          usesNetwork: use.creating || use.delegates,
          claimsHermetic: /\bhermetic\b/i.test(why),
          remoteTargets: requestTargets(src).filter((r) => !r.loopback && !r.stubbed).length,
        };
      });
    }),
    // Non-empty (seven today), and every stated reason that can be checked is.
    expect: true,
    probe: (rows) => rows.length > 0
      && rows.every((r) => !r.claimsNetwork || r.usesNetwork)
      && rows.every((r) => !r.claimsHermetic || r.remoteTargets === 0),
  },

  // ── the kernel conformance test ─────────────────────────────────
  // This was a defect claim (`wasm-test-reads-gitignored-dist`): the test read
  // `dist/`, which is gitignored, so it died with ENOENT on a clean checkout and
  // was filed as broken — while being the only test tying the binary to Lean.
  // Both claims below describe behaviour rather than a spelling, so they keep
  // holding however the test is rewritten.
  {
    id: "wasm-test-inputs-tracked",
    claim: "every artifact web/wasm-test.mjs reads is tracked in git, so it runs on a clean checkout",
    doc: "WASM.md",
    kind: "health",
    input: D("wasm-test read targets against git", () => {
      const src = read(ROOT, "web/wasm-test.mjs", "utf8");
      // Whatever the test opens at start-up, resolved against the test's own
      // directory and then asked of git. Reintroducing `../dist/` fails this
      // because `dist/` is gitignored — not because a literal string came back.
      const targets = [...src.matchAll(/readFile\(\s*new URL\(\s*"([^"]+)"/g)].map((m) => m[1]);
      const dir = resolve(ROOT, "web");
      const tracked = new Set(
        execFileSync("git", ["ls-files"], { cwd: ROOT, encoding: "utf8" })
          .split("\n").filter(Boolean).map((p) => resolve(ROOT, p)),
      );
      return targets.map((t) => ({
        target: t,
        path: relative(ROOT, resolve(dir, t)),
        tracked: tracked.has(resolve(dir, t)),
      }));
    }),
    // Non-empty (so a regex that stopped matching cannot pass vacuously), and
    // every target tracked.
    expect: true,
    probe: (rows) => rows.length > 0 && rows.every((r) => r.tracked),
  },
  {
    id: "kernel-vectors-satisfy-wasm",
    claim: "all 59 tracked golden vectors are satisfied by the tracked binary, so the two agree",
    doc: "WASM.md, SYSTEM.md",
    kind: "health",
    input: D("vectors replayed against the kernel", async () => {
      const wasm = read(ROOT, "web/kant_kernel.wasm");
      const vectors = JSON.parse(read(ROOT, "web/kernel-vectors.json", "utf8")).vectors;
      const { instance } = await WebAssembly.instantiate(wasm, {});
      const bad = [];
      for (const v of vectors) {
        const fn = instance.exports[v.f];
        if (typeof fn !== "function") { bad.push(`${v.f}: missing export`); continue; }
        // wasm i64 results arrive signed; the kernel is unsigned throughout.
        const got = BigInt.asUintN(64, fn(...v.args.map((a) => BigInt(a))));
        if (got !== BigInt(v.expected)) bad.push(`${v.f}(${v.args.join(",")})`);
      }
      return { vectors: vectors.length, unsatisfied: bad };
    }),
    expect: true,
    probe: (r) => r.vectors === 59 && r.unsatisfied.length === 0,
  },

  // ── the Lean proof gate ──────────────────────────────────────
  //
  // The 13-module closure of `Wasm/KernelSpec.lean` used to carry
  // `import Mathlib`, which is why there was no gate at all: on this machine a
  // single `import Mathlib` did not finish elaborating in 401s, and the closure
  // produced zero oleans in 560s. These three claims are the properties that
  // made a gate affordable, plus the build itself.
  {
    id: "lean-gate-imports-nothing-external",
    claim: "the Lean proof tree imports nothing outside itself, so it needs no Mathlib to build",
    doc: "WASM.md",
    kind: "health",
    input: D("every import in the gate tree, resolved against git", () => {
      const tracked = execFileSync("git", ["ls-files", "lean-gate"], {
        cwd: ROOT, encoding: "utf8",
      }).split("\n").filter((p) => p.endsWith(".lean"));
      const rows = [];
      for (const rel of tracked) {
        const src = read(ROOT, rel, "utf8");
        for (const m of src.matchAll(/^import\s+([A-Za-z_][\w'.]*)/gm)) {
          rows.push({ file: rel, module: m[1], internal: m[1].startsWith("RequestProject.") });
        }
      }
      return rows;
    }),
    // Non-empty so a scan that stopped matching cannot pass vacuously, and every
    // import resolves inside the tree.
    expect: true,
    probe: (rows) => rows.length > 0 && rows.every((r) => r.internal),
  },
  {
    id: "lean-spec-proves-every-wasm-export",
    claim: "KernelSpec proves one theorem per exported wasm function, so the extraction links the binary to the Lean definitions",
    doc: "WASM.md",
    kind: "health",
    input: D("each kernel export against the theorems that evaluate its body", () => {
      const kernel = read(ROOT, "lean-gate/RequestProject/Wasm/Kernel.lean", "utf8");
      const spec = read(ROOT, "lean-gate/RequestProject/Wasm/KernelSpec.lean", "utf8");
      const exports = [...kernel.matchAll(
        /name\s*:?=\s*"([a-z0-9_]+)"\s*,\s*arity\s*:?=\s*\d+\s*,\s*body\s*:?=\s*(\w+)/g,
      )].map((m) => ({ export: m[1], body: m[2] }));
      // The theorems are matched to the export's *body*, not its wasm name:
      // `fnv1a_step` is exported with the body `fnvStepE`, and that is the
      // expression `eval_fnvStepE` is about.
      return exports.map((e) => ({
        ...e,
        proved: new RegExp(`Expr\\.eval[^\\n]*\\b${e.body}\\b`).test(spec),
      }));
    }),
    // Non-empty (21 exports) and every one of them evaluated somewhere.
    expect: true,
    probe: (rows) => rows.length > 0 && rows.every((r) => r.proved),
  },
  {
    id: "relay-suites-share-one-start-budget",
    claim: "no suite gives up waiting for the relay with a bare \"relay did not start\" and nothing the relay said",
    doc: "VERIFICATION.md",
    kind: "health",
    input: D("every tracked suite that waits on the relay's stdout, against the shared helper", () => {
      // The defect this guards: four suites each carried their own
      // `reject(new Error("relay did not start")), 8000`. Eight seconds was a
      // guess; the relay's first SQLite connection migrates the pass-db schema
      // and measured 10.5s / 13.6s / 15.4s to say "listening" on a loaded box,
      // so the guess failed and cli-page-test went red with no evidence in the
      // message. One budget, measured, lives in scripts/relay-start.mjs.
      //
      // The trigger is the *shape*: a suite that waits for the relay's own
      // `listening` line. Suites that start a relay and then poll its HTTP
      // health are a different thing and are not caught by this --
      // `scripts/vacuum-bug-test.mjs` does that, and already prints the relay's
      // stderr when the wait fails. `scripts/p2p-wasm-filetest.mjs` waited on
      // stdout before this helper existed, with its own 20s budget; it keeps
      // its own because it already interpolates the relay's stderr into the
      // failure, which is the half of the fix the other four were missing.
      //
      // So the property is the weaker one that is actually true of the tree: a suite
      // may wait on `listening` with its own budget, as p2p-wasm-filetest does,
      // but it may not give up saying nothing but those four words.
      const tracked = execFileSync("git", ["ls-files"], { cwd: ROOT, encoding: "utf8" })
        .split("\n").filter((p) => /\.(mjs|js|ts)$/.test(p) && exists(resolve(ROOT, p)));
      const rows = [];
      for (const suite of tracked) {
        if (suite === "scripts/relay-start.mjs" || SELF.includes(suite)) continue;
        const src = read(ROOT, suite, "utf8");
        if (!/relay\.mjs/.test(src)) continue;
        if (!/includes\(["'`]listening["'`]\)/.test(src)) continue;
        rows.push({
          suite,
          usesSharedHelper: /relay-start\.mjs/.test(src),
          // Exactly those four words, with nothing from the relay: the defect.
          bareRejection: /new Error\(\s*["'`]relay did not start["'`]\s*\)/.test(src),
        });
      }
      return rows;
    }),
    // Non-empty (so a scan that stopped matching cannot pass vacuously) and no
    // suite gives up without saying something.
    expect: true,
    probe: (rows) => rows.length > 0 && rows.every((r) => !r.bareRejection),
  },
  {
    id: "lean-proof-gate-builds",
    claim: "the Lean proof builds with no holes and only core-Lean axioms",
    doc: "WASM.md",
    kind: "health",
    input: RUN(),
    expect: true,
    // Runs scripts/lean-proof-gate.sh, which is what a developer runs. It is a
    // build, not a grep: a wrong hypothesis (`x.toNat < 257` where the export is
    // only meant for `< 256`) makes this fail, and so does a `sorry`.
    probe: () => {
      const r = spawnSync("bash", [resolve(ROOT, "scripts/lean-proof-gate.sh")], {
        cwd: ROOT, encoding: "utf8", timeout: 600_000, maxBuffer: 32 * 1024 * 1024,
      });
      const out = `${r.stdout ?? ""}${r.stderr ?? ""}`;
      return r.status === 0 && /no sorry, no admit, no native_decide/.test(out)
        && /no theorem depends on anything else/.test(out);
    },
  },
];

// ── runner ──────────────────────────────────────────────────────

function read(root, rel, enc) {
  return enc ? readFileSync(resolve(root, rel), enc) : readFileSync(resolve(root, rel));
}
function exists(p) {
  try {
    readFileSync(p);
    return true;
  } catch {
    return false;
  }
}
function walk(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = resolve(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (/\.(mjs|js|ts)$/.test(e.name)) out.push(p);
  }
  return out;
}

// ── what a suite hands a relay, and where a suite may send a request ────
//
// Everything below reads its subject out of server/relay.mjs or out of the
// suite's own source rather than out of a list written here. That is the whole
// point: the previous version of `suites-never-use-the-production-pass-db` named
// `passDb`, and a check that names one field of a four-field interface reports
// nothing about the other three. A derivation that stopped matching the tree
// shows up as a shorter list, and the probes below require the list to still
// contain the fields that matter.

/** The one CONFIG key the relay only reads from; the rest are writes. */
const RELAY_READ_ONLY = new Set(["staticDir"]);

/** How many recorded causes VERIFICATION.md's table is expected to carry.
 *  Stated rather than derived — see `recorded-causes-are-re-derived`. */
const MIN_RECORDED_CAUSES = 6;

/**
 * Every key in server/relay.mjs's CONFIG that names a place on disk, with the
 * argv flag and the env var that override it and the default it falls back to.
 * Derived from the CONFIG block, so a new `cacheDir` is covered on the day it
 * is written and this file needs no edit.
 */
export function relayPathKeys(relaySrc) {
  const block = /export const CONFIG = \{([\s\S]*?)\n\};/.exec(relaySrc);
  if (!block) return [];
  const keys = [];
  for (const line of block[1].split("\n")) {
    const m = /^\s*(\w+):\s*(.*)$/.exec(line);
    if (!m) continue;
    const [, key, value] = m;
    // A key that names a directory, file, database, log or path. The numbers
    // (`maxLine`, `roomTtlMs`) and the strings that are not places (`origin`)
    // do not match, which is the discrimination we want.
    if (!/(Dir|File|Db|Log|Path)$/.test(key)) continue;
    keys.push({
      key,
      flag: /args\.get\(\s*"([^"]+)"/.exec(value)?.[1] ?? null,
      env: /process\.env\.([A-Z_]+)/.exec(value)?.[1] ?? null,
      // The *default* is the last fallback in the chain, not the first string
      // in it — the first is the flag name: `args.get("log") ?? … ?? ""`.
      default: /["']([^"']*)["']/.exec(value.split("??").pop().trim())?.[1] ?? "",
    });
  }
  return keys;
}

/**
 * The relay config objects a suite actually hands to createServer/createRelay,
 * as source text.
 *
 * Resolving the *argument* to the config first is the load-bearing part: most
 * suites pass a variable (`createServer(cfg, new Rooms(cfg))`), so the config
 * is not in the call text at all. And `createServer` is also node:http's, which
 * these suites use for their 404 and SPA stubs — a first draft of this scanner
 * matched `createServer((_req, res) => {...})` and called it an unconfigured
 * relay. Every relay config here spreads CONFIG, so that is the discriminator,
 * and it is checked on the resolved config rather than on the call.
 */
export function relayConfigs(src) {
  const out = [];
  for (const m of src.matchAll(/create(?:Server|Relay)\s*\(/g)) {
    let i = m.index + m[0].length, depth = 1;
    const start = i;
    while (i < src.length && depth > 0) {
      if (src[i] === "(") depth += 1;
      else if (src[i] === ")") depth -= 1;
      i += 1;
    }
    const args = src.slice(start, i - 1).trim();
    let config = args;
    if (!config.startsWith("{")) {
      const name = config.split(",")[0].trim();
      // An object literal, or a plain identifier. Anything else as the first
      // argument is a request handler, and is not a relay.
      if (!/^[A-Za-z_$][\w$]*$/.test(name)) continue;
      const decl = new RegExp(`\\b${name}\\s*=\\s*\\{[^}]*\\}`).exec(src);
      config = decl ? decl[0] : args;
    }
    if (!/CONFIG/.test(config)) continue;
    out.push(config);
  }
  return out;
}

/** Read a value out of source text, up to the `,` `]` `}` or newline that ends
 *  it at nesting depth zero. A regex cannot do this: `join(tmpdir(), name)`
 *  stops a `[^,]+` in the middle of its own argument list, and the truncated
 *  text is then not the expression that was written. */
export function balancedValue(src, start) {
  let i = start, depth = 0;
  while (i < src.length) {
    const ch = src[i];
    if (ch === "(" || ch === "[" || ch === "{") depth += 1;
    else if (ch === ")" || ch === "]" || ch === "}") {
      if (depth === 0) break;
      depth -= 1;
    } else if (depth === 0 && (ch === "," || ch === "\n")) break;
    i += 1;
  }
  return src.slice(start, i).trim();
}

/** The whole argument list of a call, from just after its `(`. balancedValue
 *  cannot do this job: it stops at the first comma at depth zero, which for
 *  `spawn(execPath, [relayPath, …])` is the one before the relay. */
export function callArguments(src, start) {
  let i = start, depth = 1;
  while (i < src.length) {
    const ch = src[i];
    if (ch === "(" || ch === "[" || ch === "{") depth += 1;
    else if (ch === ")" || ch === "]" || ch === "}") {
      depth -= 1;
      if (depth === 0) break;
    }
    i += 1;
  }
  return src.slice(start, i);
}

/** The first argument of a call, as source text. */
export function firstArgument(src, start) {
  return balancedValue(callArguments(src, start), 0);
}

/** The expression a config literal gives `key`, or null if it does not give it.
 *  Shorthand (`{ ...CONFIG, passDb }`) is a supply: the value is that name. */
export function fieldValue(config, key) {
  // `[{\s]` and not `[{[:space:]]`: a POSIX class nested inside a character
  // class is not portable, and the version written first silently matched
  // nothing -- every `passDb` in every config then read as "not supplied",
  // which is the one answer that must never come out of a broken matcher.
  for (const m of config.matchAll(new RegExp(`(?:^|[{\\s])${key}\\b`, "g"))) {
    let i = m.index + m[0].length;
    while (i < config.length && /\s/.test(config[i])) i += 1;
    if (config[i] === ":") return balancedValue(config, i + 1);
    if (config[i] === "," || config[i] === "}" || i >= config.length) return key;
  }
  return null;
}

/** The expression a suite gives a spawned relay, by flag or by env var. */
export function suppliedOnArgv(src, key) {
  if (key.flag) {
    const flag = new RegExp(`["']--${key.flag}["']\\s*,`, "g").exec(src);
    if (flag) return balancedValue(src, flag.index + flag[0].length);
  }
  if (key.env) {
    const env = new RegExp(`process\\.env\\.${key.env}\\s*=\\s*`, "g").exec(src);
    if (env) return balancedValue(src, env.index + env[0].length);
  }
  return null;
}

/** How a suite uses the relay, in one place, so every claim that asks agrees.
 *  `creating` is the load-bearing answer: does this suite actually put a relay
 *  (and therefore a pass database, a log and an archive) into existence. */
export function relayUse(src) {
  const code = withoutComments(src);
  const configs = relayConfigs(code);
  const onArgv = /relay-start\.mjs/.test(code) || spawnsRelayProcess(code);
  return {
    code,
    configs,
    onArgv,
    creating: configs.length > 0 || onArgv,
    delegates: /^import\s+["']\.\.\/(web|scripts)\//m.test(code.trim()),
    mentions: /relay\.mjs|relay-start\.mjs/.test(src),
  };
}

/** Does this suite run a relay as a child process?
 *
 *  The argument list is what is searched, not the file. An earlier version of
 *  this guard asked merely whether the source contained a spawn-family call and
 *  mentioned `relay.mjs` anywhere, and `scripts/thunk-claims-test.mjs` satisfied
 *  both — it spawns the vector checker and it talks about relays in a comment.
 *  Worse, the opposite failure is the one that bit: `web/diag-test.mjs` stopped
 *  matching entirely once it moved its inline `spawn` into
 *  `scripts/relay-start.mjs`, so it dropped out of the guard on the very commit
 *  that made it start passing. A guard whose trigger is a spelling rots the
 *  moment the spelling is fixed. */
export function spawnsRelayProcess(src) {
  return [...src.matchAll(/\b(?:spawn|spawnSync|execFile|execFileSync|execSync)\s*\(/g)]
    .some((m) => /\brelay\w*/i.test(callArguments(src, m.index + m[0].length)));
}

/** The names a suite binds to a directory it created for this run. */
export function tempRoots(src) {
  const names = new Set();
  for (const m of src.matchAll(/(?:const|let|var)\s+(\w+)\s*=\s*(?:await\s+)?(?:fs\.)?mkdtemp(?:Sync)?\s*\(/g))
    names.add(m[1]);
  return names;
}

/** Follow `const x = …` chains so `passDb` is judged by where it points. */
export function resolveBindings(src, expr, depth = 0) {
  if (depth > 4) return expr;
  const name = /^[A-Za-z_$][\w$]*$/.exec(expr.trim());
  if (!name) return expr;
  const decl = new RegExp(`(?:const|let|var)\\s+${name}\\s*=\\s*([^;\n]+)`).exec(src);
  return decl ? resolveBindings(src, decl[1].trim(), depth + 1) : expr;
}

/** Is this path inside the temp area the suite made for itself?
 *  A literal `/tmp/…` is NOT: it is shared by every concurrent run, which is
 *  how a rate-limit ledger outlives the suite that wrote it. */
export function insideTemp(expr, roots) {
  if (/\btmpdir\s*\(\s*\)/.test(expr)) return true;
  return [...roots].some((r) => new RegExp(`\\b${r}\\b`).test(expr));
}

/** The calls in a suite that put something on the wire, with their first
 *  argument's text. Comments go first — a suite that *discusses* reaching a
 *  host has not reached it — and data that merely mentions a URL is not a
 *  request either: only a URL inside a request-making call's own argument
 *  counts, which is why `invite("https://relay.example.org", …)` is fine and
 *  `resolveReachability({ configured: "https://…" })` is not. */
const REQUEST_MAKERS = /\b(?:fetch|probeRelay|resolveReachability|RelayClient|request|connect|dial)\s*\(/g;

/** Comments out, using the project's own scanner, and falling back to no
 *  stripping at all if it refuses the file. The fallback errs towards *more*
 *  rows, not fewer: server/js-scan.mjs is a real scanner and it throws on a
 *  source with a newline inside a regex literal, which a suite may contain. */
function withoutComments(src) {
  try {
    return stripComments(src);
  } catch {
    return src;
  }
}

export function requestTargets(src) {
  const code = withoutComments(src);
  const out = [];
  for (const m of code.matchAll(REQUEST_MAKERS)) {
    const arg = firstArgument(code, m.index + m[0].length);
    const full = resolveBindings(code, arg);
    // A call can name a real host and still never reach it, if it was handed a
    // fetch of its own — which is how web/diag-test.mjs keeps its
    // "a configured relay that is down" case while asserting against
    // kant-relay.cicada71.net. Passing `globalThis.fetch` is not a stub.
    //
    // The value is captured and compared rather than excluded with a negative
    // lookahead, because `\s*` before it backtracks: `fetchImpl: globalThis.fetch`
    // matched `(?!\s*globalThis)` by testing the lookahead against the space.
    const injected = /\bfetchImpl\s*[:,=]\s*([A-Za-z_$][\w$.]*)/.exec(arg)?.[1];
    const stubbed = Boolean(injected) && injected !== "globalThis.fetch";
    for (const url of full.match(/https?:\/\/[^\s"'`]+/g) ?? []) {
      out.push({
        suite: null, call: m[0].replace(/\s*\($/, ""), url,
        loopback: isLoopback(url), stubbed,
      });
    }
  }
  return out;
}

/** Loopback, or a name in a reserved TLD that cannot resolve to a deployment. */
export function isLoopback(url) {
  // The authority is read out with a pattern rather than `new URL`, because the
  // interesting case is a template literal — `http://127.0.0.1:${port}` — which
  // is not a URL until it has run, and which must still be recognised as
  // loopback. The substitution keeps `${…}` from being read as a hostname.
  const host = /^[a-z][a-z0-9+.-]*:\/\/([^/?#\s"'`)]+)/i.exec(url)?.[1] ?? "";
  if (!host) return false;
  const bare = host.replace(/^\[|\]$/g, "").split("@").pop().split(":")[0];
  if (/^(127\.|localhost$|::1$|0\.0\.0\.0$)/.test(bare)) return true;
  return /\.(example|invalid|test|localhost)$/.test(bare)
    || /^(example\.(com|net|org))$/.test(bare);
}

/**
 * Evaluate one claim against one input. Below this line there is no file
 * access, which is the property the test file depends on.
 */
export async function evaluate(claim, raw) {
  const base = { id: claim.id, kind: claim.kind, claim: claim.claim, doc: claim.doc, expect: claim.expect };
  let observed;
  try {
    observed = await claim.probe(raw);
  } catch (e) {
    return { ...base, observed: `threw: ${e.message}`, ok: false };
  }
  return { ...base, observed, ok: deepEq(observed, claim.expect) };
}

function deepEq(a, b) {
  if (Array.isArray(b))
    return Array.isArray(a) && a.length === b.length && a.every((v, i) => deepEq(v, b[i]));
  return a === b;
}

/** Resolve every claim's input and evaluate it against the real tree. */
export async function runClaims() {
  const rows = [];
  for (const claim of CLAIMS) {
    let raw;
    try {
      raw = await resolveInput(claim.input);
    } catch (e) {
      rows.push({
        id: claim.id, kind: claim.kind, claim: claim.claim, doc: claim.doc, expect: claim.expect,
        observed: `input failed: ${e.message}`, ok: false,
      });
      continue;
    }
    rows.push(await evaluate(claim, raw));
  }
  return rows;
}

export async function resolveInput(input) {
  if (input.kind === "run") return undefined;
  if (input.kind === "derive") return await input.fn();
  return read(ROOT, input.path, input.binary ? undefined : "utf8");
}

// ── cli ─────────────────────────────────────────────────────────

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  if (argv.includes("--list")) {
    for (const c of CLAIMS) console.log(`${c.id.padEnd(32)} ${c.claim}`);
    process.exit(0);
  }
  const rows = await runClaims();
  if (argv.includes("--json")) {
    console.log(JSON.stringify(rows, null, 2));
  } else {
    const w = Math.max(...rows.map((r) => r.id.length));
    for (const r of rows) {
      const mark = r.ok ? "  ok" : "FAIL";
      console.log(`${mark}  ${r.id.padEnd(w)}  ${r.claim}${r.kind === "defect" ? "   [defect]" : ""}`);
      if (!r.ok)
        console.log(`      expected ${JSON.stringify(r.expect)}, got ${JSON.stringify(r.observed)}`);
    }
    const bad = rows.filter((r) => !r.ok);
    console.log(`\n${rows.length - bad.length}/${rows.length} claims hold`);
    if (bad.length) {
      const regressed = bad.filter((r) => r.kind === "health");
      const fixed = bad.filter((r) => r.kind === "defect");
      if (fixed.length)
        console.log(`${fixed.length} defect claim(s) went red — that is progress; rewrite them.`);
      if (regressed.length)
        console.log(`${regressed.length} health claim(s) went red — that is a regression.`);
    }
  }
  process.exit(rows.every((r) => r.ok) ? 0 : 1);
}