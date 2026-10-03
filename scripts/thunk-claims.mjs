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
import { execFileSync } from "node:child_process";
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