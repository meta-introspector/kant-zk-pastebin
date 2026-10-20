// lean-proofs.mjs — the gate on the Lean proof, and the checks around it.
//
//   node scripts/lean-proofs.mjs
//
// `web/wasm-test.mjs` checks that the emitted `.wasm` computes the 59 golden
// vectors. This checks the other end of the same chain: that
// `lean-gate/RequestProject/Wasm/KernelSpec.lean` *proves*, for every exported
// wasm function, that the compiled expression evaluates to the same number as
// the `Kant.Bytes` / `Kant.Dasl` / `Kant.Sneakernet` / `Kant.Stego` definition.
// One theorem per export; together with `Expr.exec_compile` (the compiled code
// evaluates the expression) and `Encode.module` (the bytes are the binary form
// of that code) that is the correctness statement for the extraction:
//
//     Lean definition = wasm expression = emitted .wasm function
//
// There are five kinds of check, and the split is deliberate:
//
//   1. the proof tree is tracked            — a gate over untracked files
//                                             guards nothing on a fresh checkout
//   2. the tree imports nothing external    — the property that makes the build
//                                             possible at all (>400s per module
//                                             with Mathlib, ~10.5s without)
//   3. no holes                             — cheap and unconditional; catches
//                                             a `sorry` even where gokujo is absent
//   4. one theorem per exported function    — the header's "one theorem per
//                                             exported function", checked against
//                                             the kernel's own export table
//   5. the real build                       — `scripts/lean-proof-gate.sh`
//
// (5) is the one that costs anything: ~10.5s cold, ~2.7s warm. It is in the
// core run rather than behind a flag because that is affordable and because a
// gate nobody runs is not a gate.

import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative, resolve } from "node:path";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const GATE_DIR = join(ROOT, "lean-gate");
const GATE = "lean-gate";
const GATE_SH = join(ROOT, "scripts", "lean-proof-gate.sh");

let failures = 0;
function check(ok, what, detail) {
  if (!ok) {
    failures += 1;
    console.error(`not ok — ${what}${detail ? `\n     ${detail}` : ""}`);
  }
}

/** Every `.lean` file under the gate tree, as repo-relative paths. */
function leanFiles(dir = GATE_DIR, acc = []) {
  for (const entry of readdirSync(dir)) {
    // `.gokujo` holds the build cache and the generated audit driver, neither of
    // which is part of the proof.
    if (entry === ".gokujo") continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) leanFiles(full, acc);
    else if (entry.endsWith(".lean")) acc.push(relative(ROOT, full));
  }
  return acc;
}

const files = leanFiles();
const sources = new Map(files.map((f) => [f, readFileSync(join(ROOT, f), "utf8")]));

// ── 1. the tree is tracked ───────────────────────────────────────────────
// The gate would otherwise pass on a developer's machine and evaporate on
// everyone else's: `scripts/embed-kernel.mjs` was referenced by seven tracked
// files and present in none, which is the same shape of defect.
{
  const r = spawnSync("git", ["ls-files", "--error-unmatch", ...files], {
    cwd: ROOT, encoding: "utf8",
  });
  check(r.status === 0,
    "every Lean file in the gate is tracked by git",
    r.status === 0 ? "" : `untracked: ${(r.stderr || "").trim()}`);

  const toolchain = join(GATE, "RequestProject", "lean-toolchain");
  check(sources.size > 0, "the gate tree has Lean files in it");
  const t = readFileSync(join(ROOT, toolchain), "utf8").trim();
  check(t === "leanprover/lean4:v4.28.0",
    `lean-toolchain pins the version the gate compiles with`,
    `read ${JSON.stringify(t)}`);
}

// ── 2. nothing outside core Lean is imported ──────────────────────────────
// Every import must name a module inside this tree. Anything else is either
// Mathlib (400s+ per module to elaborate here) or a dependency the gate does not
// know how to find, and in both cases the build silently becomes optional.
{
  const external = [];
  for (const [file, src] of sources) {
    for (const m of src.matchAll(/^import\s+([A-Za-z_][\w'.]*)/gm)) {
      if (!m[1].startsWith("RequestProject.")) external.push(`${file}: import ${m[1]}`);
    }
  }
  check(external.length === 0,
    "no Lean file imports anything outside the gate tree",
    external.join("\n     "));

  check(!sources.has(join(GATE, "RequestProject", "Wasm", "KernelSpec.lean")) ||
    !/import\s+Mathlib/.test(sources.get(join(GATE, "RequestProject", "Wasm", "KernelSpec.lean"))),
    "the spec itself does not import Mathlib");
}

// ── 3. no holes ───────────────────────────────────────────────────────────
// gokujo's `check` reports holes too; this repeats it statically so the hole
// check survives a machine with no Lean toolchain, and so the failure names the
// file rather than arriving inside a build log.
{
  const holes = [];
  for (const [file, src] of sources) {
    const code = src.replace(/^\s*\/-[\s\S]*?-\/\s*$/gm, "");
    for (const [what, re] of [
      ["sorry", /(^|[^\w.])sorry(?![!\w])/],
      ["admit", /(^|[^\w.])admit(?![!\w])/],
      ["native_decide", /(^|[^\w.])native_decide(?![!\w])/],
    ]) {
      if (re.test(code)) holes.push(`${file}: ${what}`);
    }
  }
  check(holes.length === 0, "the proof tree has no sorry, admit or native_decide",
    holes.join("\n     "));
}

// ── 4. one theorem per exported wasm function ─────────────────────────────
// Read the export table out of the kernel module rather than from a list kept
// elsewhere: the failure being guarded against is the two drifting apart.
{
  const kernel = sources.get(join(GATE, "RequestProject", "Wasm", "Kernel.lean")) ?? "";
  const spec = sources.get(join(GATE, "RequestProject", "Wasm", "KernelSpec.lean")) ?? "";
  // Read each export's *body*, not its wasm name: `fnv1a_step` is exported with
  // the body `fnvStepE`, so the theorem it is proved by is `eval_fnvStepE`.
  // Naming the body is the link the theorem actually claims.
  const exports = [...kernel.matchAll(
    /name\s*:?=\s*"([a-z0-9_]+)"\s*,\s*arity\s*:?=\s*\d+\s*,\s*body\s*:?=\s*(\w+)/g,
  )].map((m) => ({ name: m[1], body: m[2] }));

  check(exports.length > 0, "the kernel module declares exported functions",
    "no `{ name := \"...\", arity := n, body := x }` found in Wasm/Kernel.lean");

  const lemmas = new Set(
    [...spec.matchAll(/theorem\s+(\w+)/g)].map((m) => m[1]),
  );
  // A theorem for an export is one that evaluates *that* expression, so the
  // check is on `Expr.eval` applied to the export's Lean-side name, not on the
  // snake_case spelling appearing in the source.
  const evaluated = new Set(
    [...spec.matchAll(/Expr\.eval[^\n]*?\b([A-Za-z_][A-Za-z0-9_]*E)\b/g)].map((m) => m[1]),
  );
  const missing = exports.filter((e) => !lemmas.has(`eval_${e.body}`));

  check(missing.length === 0,
    `KernelSpec proves every one of the ${exports.length} exported wasm functions`,
    `no theorem named for the body of: ${missing.map((e) => e.name).join(", ")}`);

  // ...and that theorem is about the export's expression, not just its name.
  const unevaluated = exports.filter((e) => !evaluated.has(e.body));
  check(unevaluated.length === 0,
    "each of those theorems evaluates the export's expression",
    `never passed to Expr.eval: ${unevaluated.map((e) => e.body).join(", ")}`);

  // And the axioms are the ones core Lean is allowed to use.
  check(!/\baxiom\s/.test(spec) && !/\bopaque\s/.test(spec),
    "the spec introduces no axiom or opaque constant of its own");
}

// ── 5. the real build ─────────────────────────────────────────────────────
{
  const t0 = Date.now();
  const r = spawnSync("bash", [GATE_SH], {
    cwd: ROOT, encoding: "utf8", timeout: 600_000, maxBuffer: 32 * 1024 * 1024,
  });
  const secs = ((Date.now() - t0) / 1000).toFixed(1);
  const out = `${r.stdout ?? ""}${r.stderr ?? ""}`;
  check(r.status === 0, `the Lean proof builds and audits clean (${secs}s)`,
    out.trim().split("\n").slice(-14).join("\n     "));
  check(/no sorry, no admit, no native_decide/.test(out),
    "gokujo's hole audit agrees", out.trim().split("\n").slice(-6).join("\n     "));
  check(/no theorem depends on anything else/.test(out),
    "every audited theorem rests on propext, Classical.choice and Quot.sound only");

  if (failures === 0) {
    console.log(
      `ok — ${files.length} Lean files, Mathlib-free, no holes, ` +
      `axioms audited, build in ${secs}s`,
    );
  } else {
    console.error(`${failures} check(s) failed`);
    process.exit(1);
  }
}