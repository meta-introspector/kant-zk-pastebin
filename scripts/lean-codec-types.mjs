// lean-codec-types.mjs — read the Lean codec's value types out of this repository.
//
// `scripts/kant-codec.mjs` is a transcription of `RequestProject/Kant/Codec/*.lean`
// and its header says so. A transcription is a claim that can rot, and this one
// did: phase 1 added a `{t: "float"}` constructor to the JS side, every JS test
// passed, and nothing noticed. A new tag collides with nothing, so round-trip,
// injectivity and projection tests all keep agreeing while the two languages
// quietly stop agreeing with each other.
//
// So this reads the Lean source and compares, rather than trusting a list typed
// out by hand. The source is in THIS repository -- it is on `feature/lean`, not
// on this branch and not a flake input, which is why `find` missed it and why an
// earlier reading of the tree concluded the correspondence was unverifiable.
//
//   node scripts/lean-codec-types.mjs          table, exit 1 on any mismatch
//   node scripts/lean-codec-types.mjs --json   machine-readable
//
// What this can and cannot do is stated at the bottom of the file, and it is
// worth reading before trusting a green run.

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/** Where the Lean codec lives, in this repository.
 *
 *  Pinned to a commit rather than to the branch name, for the same reason every
 *  flake input here is pinned: a branch name means any upstream commit silently
 *  changes what this checks, which is the failure mode `base-check.sh` exists to
 *  catch. `feature/lean` is on `origin`, so the object is fetchable. */
export const LEAN_REF = "a3cd85b49d74ab6745c9b23651f9abbee69143f4";

/** The Lean file defining the canonical value type. */
export const VAL_LEAN = "RequestProject/Kant/Codec/Val.lean";

/** The Lean file defining the IPDL-only shapes. */
export const IPDL_LEAN = "RequestProject/Kant/Codec/Ipdl.lean";

/** Read a file out of the pinned Lean commit. Throws if it is not there. */
export function readLean(path, ref = LEAN_REF) {
  return execFileSync("git", ["show", `${ref}:${path}`], {
    cwd: ROOT,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  });
}

/** The constructor names of a Lean `inductive`, in declaration order.
 *
 *  Parsed from the declaration rather than matched against a known list, so a
 *  constructor added to Lean shows up here without this file being edited. That
 *  is the whole point: the failure being guarded against is a list that stopped
 *  matching the thing it describes.
 */
export function leanConstructors(src, inductiveName) {
  const start = src.search(new RegExp(`^inductive\\s+${inductiveName}\\b`, "m"));
  if (start < 0) throw new Error(`no \`inductive ${inductiveName}\` in the Lean source`);
  // The declaration ends at `deriving`, or at the first line that is not a
  // constructor and not blank.
  const rest = src.slice(start).split("\n");
  const names = [];
  for (let i = 1; i < rest.length; i += 1) {
    const line = rest[i];
    if (/^\s*deriving\b/.test(line)) break;
    const m = line.match(/^\s*\|\s*([A-Za-z_][A-Za-z0-9_']*)/);
    if (m) names.push(m[1]);
    else if (line.trim() !== "" && !/^\s*\|/.test(line)) break;
  }
  return names;
}

/** Everything `Kant.Codec` can name: `Val`'s constructors plus `Ipdl`'s own. */
export function leanValTypes(ref = LEAN_REF) {
  const val = leanConstructors(readLean(VAL_LEAN, ref), "Val");
  // `Ipdl` is the canonical value plus two shapes the canonical model has no
  // constructor for, carried in reserved keys. It is a separate inductive with
  // its own copy of the six, so the two extra are the difference.
  const ipdl = leanConstructors(readLean(IPDL_LEAN, ref), "Ipdl");
  const extra = ipdl.filter((n) => !val.includes(n));
  return [...val, ...extra];
}

/** The value types the JS codec's `canonEnc` can actually encode.
 *
 *  Read from the `switch (v.t)` in `canonEnc` rather than by calling the
 *  constructors. Calling them does not work: `vInt(null)` throws from `BigInt`,
 *  `vList(null)` throws on `.map`, and `vStr(null)` cheerfully returns the tag
 *  `str` for a value that was never a string -- so a probe both misses types and
 *  invents them. The switch is the exhaustive list, and a type with no case
 *  throws `not a canonical value`, which is the behaviour being relied on.
 */
export function jsEncodedTypes() {
  const src = readFileSync(`${ROOT}/scripts/kant-codec.mjs`, "utf8");
  const start = src.search(/export function canonEnc\b/);
  if (start < 0) throw new Error("no canonEnc in scripts/kant-codec.mjs");
  const body = src.slice(start, src.indexOf("\n}", start));
  return [...body.matchAll(/case "([a-z]+)"/g)].map((m) => m[1]);
}

/** The tag list `server/thunk-id.mjs` claims Lean can name. */
export async function declaredLeanTags() {
  const { LEAN_VAL_TAGS } = await import(`${ROOT}/server/thunk-id.mjs`);
  return [...LEAN_VAL_TAGS];
}

/** Compare all three lists. Returns one row per disagreement. */
export async function compare(ref = LEAN_REF) {
  const lean = leanValTypes(ref);
  const js = jsEncodedTypes();
  const declared = await declaredLeanTags();
  // `ref` and `annot` are IPDL document shapes, not canonical values: they live
  // in reserved keys and `project` folds them into an object before `canonEnc`
  // ever sees them. So the encodable set is Lean's minus those two.
  const encodable = lean.filter((t) => t !== "ref" && t !== "annot");

  const rows = [
    { check: "lean source is reachable", ok: true, detail: `${lean.length} types: ${lean.join(", ")}` },
    {
      check: "canonEnc encodes exactly Lean's canonical types",
      ok: encodable.length === js.length && encodable.every((t) => js.includes(t)),
      detail: js.length === encodable.length && encodable.every((t) => js.includes(t))
        ? `both: ${js.join(", ")}`
        : `js encodes ${js.join(", ")}; Lean's canonical types are ${encodable.join(", ")}`,
    },
    {
      check: "the JS codec encodes no type Lean cannot name",
      ok: js.every((t) => lean.includes(t)),
      detail: js.filter((t) => !lean.includes(t)).length
        ? `JS-only: ${js.filter((t) => !lean.includes(t)).join(", ")}`
        : "none",
    },
    {
      check: "LEAN_VAL_TAGS matches the Lean source",
      ok: lean.every((t) => declared.includes(t)) && declared.every((t) => lean.includes(t)),
      detail: declared.filter((t) => !lean.includes(t)).length
        ? `declared but not in Lean: ${declared.filter((t) => !lean.includes(t)).join(", ")}`
        : `declared: ${declared.join(", ")}`,
    },
  ];
  return { rows, lean, js, declared };
}

// ── cli ─────────────────────────────────────────────────────────

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  let out;
  try {
    out = await compare();
  } catch (e) {
    console.error(`cannot read the Lean codec at ${LEAN_REF.slice(0, 12)}: ${e.message}`);
    console.error("It is on this repository's `feature/lean`. Fetch it with:");
    console.error(`  git fetch origin feature/lean`);
    process.exit(2);
  }
  if (process.argv.includes("--json")) {
    console.log(JSON.stringify(out, null, 2));
  } else {
    console.log(`Lean codec at ${LEAN_REF.slice(0, 12)} (RequestProject/Kant/Codec)\n`);
    for (const r of out.rows) console.log(`  ${r.ok ? "ok  " : "FAIL"}  ${r.check}\n        ${r.detail}`);
    const bad = out.rows.filter((r) => !r.ok);
    console.log(`\n${out.rows.length - bad.length}/${out.rows.length} checks pass`);
  }
  process.exit(out.rows.every((r) => r.ok) ? 0 : 1);
}

/*

## What this does not do

It compares the *shapes*. It cannot tell you a constructor's semantics drifted,
that a `#guard` vector changed, or that a Lean proof was weakened -- it reads
declarations, not proofs.

It also cannot run where the pinned object is absent. The Lean source is on
`feature/lean` and not on `feature/big-merge`, so a CI checkout of this branch
has no such object and this exits 2 with instructions rather than reporting a
false pass. That is deliberate: a checker that skips silently when it cannot see
the thing it checks is worse than no checker, because it reads as a green run.

The failure it exists to prevent is not subtle in hindsight -- a seventh tag that
collides with nothing -- but it is invisible to every other tool here, precisely
because they all check the JS against itself.

*/