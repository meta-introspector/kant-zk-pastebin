// lean-codec-vectors.mjs — check the JS codec against the values Lean pins.
//
// `scripts/lean-codec-types.mjs` compares the *shapes*: which value types each
// side can name. This compares the *values* -- the golden vector both languages
// are supposed to agree on.
//
// `RequestProject/Kant/Codec/Tests.lean` defines `gSample` as "the value both
// implementations serialise" and pins six outputs with `#guard`:
//
//   #guard String.ofList (canonEnc gSample) == "O3;1;nI+144;2;okT2;xsL2;ZS10;hi \"there\""
//   #guard String.ofList (valHash gSample)
//     == "3c796f2f2a0e2274900747be3ace4d77bc5d9611122ebd3a189b5d4c0c56bbbd"
//   ...
//
// `scripts/codec-test.mjs` asserts the same six strings inline. Until now
// nothing checked that the two files agreed, or that either agreed with Lean --
// so `codec-test.mjs` passing was evidence about the JS codec and nothing else.
//
// The loop closed here has three links, and all three are checked:
//
//   Lean's #guard  ->  this file  ->  what the JS codec produces
//                                     and what codec-test.mjs asserts
//
// Note what is NOT parsed: `gSample`'s Lean term. Since Lean proves
// `canonEnc_injective`, two values with the same canonical text are the same
// value, so matching all six outputs is enough to establish the samples agree.
// Reading the term would be more work and would prove less.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

import { LEAN_REF, readLean } from "./lean-codec-types.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/** Where Lean pins the golden vector. */
export const TESTS_LEAN = "RequestProject/Kant/Codec/Tests.lean";

/**
 * Read a Lean string literal, escapes and all.
 *
 * Lean escapes are not JavaScript's. `\"` and `\\` are shared; the one that bites
 * is the *gap*: a backslash at the end of a line continues the string and eats
 * the next line's leading whitespace. The CSV vector uses it six times, so
 * getting it wrong silently truncates the expected value to its first row --
 * which would compare unequal and look like a codec bug rather than a parser
 * bug.
 */
export function unescapeLeanString(body) {
  let out = "";
  for (let i = 0; i < body.length; i += 1) {
    const c = body[i];
    if (c !== "\\") {
      if (c === "\n") throw new Error("a raw newline in a Lean string; expected a gap");
      out += c;
      continue;
    }
    const d = body[i + 1];
    i += 1;
    switch (d) {
      case "\\": out += "\\"; break;
      case '"': out += '"'; break;
      case "'": out += "'"; break;
      case "n": out += "\n"; break;
      case "r": out += "\r"; break;
      case "t": out += "\t"; break;
      case "0": out += "\0"; break;
      case "\n": {
        // A gap: the newline and the indentation after it are not content.
        while (i + 1 < body.length && /[ \t]/.test(body[i + 1])) i += 1;
        break;
      }
      case "u": {
        const hex = body.slice(i + 1, i + 5);
        if (!/^[0-9a-fA-F]{4}$/.test(hex)) throw new Error(`bad \\u escape: ${hex}`);
        out += String.fromCharCode(parseInt(hex, 16));
        i += 4;
        break;
      }
      case "x": {
        const hex = body.slice(i + 1, i + 3);
        if (!/^[0-9a-fA-F]{2}$/.test(hex)) throw new Error(`bad \\x escape: ${hex}`);
        out += String.fromCharCode(parseInt(hex, 16));
        i += 2;
        break;
      }
      default:
        if (d !== undefined && d >= "0" && d <= "9") {
          const dec = body.slice(i, i + 3);
          if (!/^[0-9]{3}$/.test(dec)) throw new Error(`bad decimal escape: ${dec}`);
          out += String.fromCharCode(parseInt(dec, 10));
          i += 2;
          break;
        }
        throw new Error(`unknown Lean escape: \\${d}`);
    }
  }
  return out;
}

/**
 * Every `#guard String.ofList (...) == "..."` that is about `gSample`, as
 * `{ fn, expected }`.
 *
 * A `#guard` may wrap onto the next line, so the comparison is done on the
 * whole file with the string bodies extracted first -- otherwise a wrapped
 * guard is simply invisible and the vector silently goes unchecked.
 */
export function gSampleGuards(src) {
  const out = [];
  // Find each `#guard`, then scan forward for the first string literal and the
  // expression naming the function applied to gSample.
  const re = /#guard\s+String\.ofList\s*\(([^)]*(?:\([^)]*\)[^)]*)*)\)\s*==\s*"/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const expr = m[1];
    if (!expr.includes("gSample")) continue;
    // The function is the *leading* identifier: `canonEnc gSample`,
    // `ipdlText (embed gSample)`. Taking the trailing one yields `gSample`,
    // which is the argument, and every row then compares against `undefined`.
    const fn = expr.match(/^\s*([A-Za-z][A-Za-z0-9]*)/)?.[1];
    if (!fn) continue;
    // The body runs from just after the opening quote to the matching close.
    let i = m.index + m[0].length;
    let body = "";
    for (;;) {
      if (i >= src.length) throw new Error(`unterminated string in a #guard for ${fn}`);
      const c = src[i];
      if (c === "\\") { body += c + (src[i + 1] ?? ""); i += 2; continue; }
      if (c === '"') break;
      body += c;
      i += 1;
    }
    out.push({ fn, expected: unescapeLeanString(body) });
  }
  return out;
}

/** The JS value the golden vector is about -- `gSample`, spelled as a JS `Val`. */
export function jsSample(C) {
  return C.vObj([
    ["n", C.vInt(144)],
    ["ok", C.vBool(true)],
    ["xs", C.vList([C.vNull, C.vStr('hi "there"')])],
  ]);
}

/** What the JS codec produces for each of the six functions Lean pins. */
export function jsVectors(C) {
  const s = jsSample(C);
  return {
    canonEnc: C.canonEnc(s),
    yamlEnc: C.yamlEnc(s),
    xmlEnc: C.xmlEnc(s),
    ipdlText: C.ipdlText(C.embed(s)),
    valHash: C.valHash(s),
    csvEncode: C.csvEncode(s),
  };
}

/** Run every link of the loop and return one row per check. */
export async function compareVectors(ref = LEAN_REF) {
  const C = await import(`${ROOT}/scripts/kant-codec.mjs`);
  const guards = gSampleGuards(readLean(TESTS_LEAN, ref));
  const js = jsVectors(C);
  // `codec-test.mjs` asserts the same values inline. The digest is the one that
  // can be checked by substring -- the YAML and CSV expectations are assembled
  // from concatenated literals and would need a JS parser to extract, which is
  // not worth it: those two are already covered by the codec comparison below,
  // and that comparison reads the codec's real output rather than a literal.
  const testSrc = readFileSync(`${ROOT}/scripts/codec-test.mjs`, "utf8");

  const rows = [{
    check: "Lean pins the golden vector",
    ok: guards.length === 6,
    detail: guards.length === 6
      ? guards.map((g) => g.fn).join(", ")
      : `expected 6 #guards about gSample, found ${guards.length}`,
  }];

  for (const { fn, expected } of guards) {
    const got = js[fn];
    rows.push({
      check: `JS ${fn} matches Lean's #guard`,
      ok: got === expected,
      detail: got === expected
        ? `${expected.length} chars`
        : `lean=${JSON.stringify(expected.slice(0, 90))} js=${JSON.stringify(String(got).slice(0, 90))}`,
    });
  }

  const digest = js.valHash;
  rows.push({
    check: "codec-test.mjs pins the same digest",
    ok: testSrc.includes(digest),
    detail: testSrc.includes(digest)
      ? digest
      : "the inline digest in codec-test.mjs no longer matches Lean's",
  });
  return { rows, guards, js };
}

// ── cli ─────────────────────────────────────────────────────────

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  let out;
  try {
    out = await compareVectors();
  } catch (e) {
    console.error(`cannot read the Lean codec at ${LEAN_REF.slice(0, 12)}: ${e.message}`);
    console.error("  git fetch origin feature/lean");
    process.exit(2);
  }
  if (process.argv.includes("--json")) {
    console.log(JSON.stringify(out, null, 2));
  } else {
    console.log(`Golden vector, Lean ${LEAN_REF.slice(0, 12)} vs scripts/kant-codec.mjs\n`);
    for (const r of out.rows) console.log(`  ${r.ok ? "ok  " : "FAIL"}  ${r.check}\n        ${r.detail}`);
    const bad = out.rows.filter((r) => !r.ok);
    console.log(`\n${out.rows.length - bad.length}/${out.rows.length} checks pass`);
  }
  process.exit(out.rows.every((r) => r.ok) ? 0 : 1);
}

/*

## What this does not do

It checks the values, not the proofs. A change to Lean's *semantics* that left
`gSample`'s six outputs alone would not be noticed here, and neither would a
`#guard` that was weakened rather than satisfied.

It also inherits the reachability limit of `lean-codec-types.mjs`: the Lean
source is on `feature/lean`, so a checkout without that object exits 2 rather
than passing quietly.

*/