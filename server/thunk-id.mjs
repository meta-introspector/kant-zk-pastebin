// thunk-id.mjs — the two keys of a thunk: the id and the call id.
//
//   thunk id = valHash({ bytes, refs })   identity, sharing, definition cache
//   call id  = valHash({ thunkId, argsHash, secretRefs, apiRefs })
//
// Neither key is truncated and neither is made by hashing a string with a
// hand-rolled recipe. Both go through `valHash` in `scripts/kant-codec.mjs`,
// which is the one hash function in the tree, so a thunk id and a file witness
// are the same kind of thing and `asWitness` accepts both.
//
// The distinction between the two keys is the whole point. A thunk id covers
// the *definition*, so two peers that agree on it are provably running the same
// bytes. A call id covers one *invocation* -- same bytes, different arguments,
// different secrets -- so it is the key of a result cache and never of a
// definition cache. Collapsing them is how you serve a cached result computed
// from different arguments to someone who asked for these.

import { valHash, vObj, vList, vStr, vInt, vNull, vBool } from "../scripts/kant-codec.mjs";
import { stripComments } from "./js-scan.mjs";

/** Thrown when a value has no content address, so no id can be computed for it.
 *  Named rather than returned, because the alternative -- coercing it to
 *  something hashable -- is how two different calls end up sharing one entry. */
export class UnaddressableError extends Error {}

/** Guard against a cycle, which would otherwise recurse until the stack dies. */
const MAX_DEPTH = 64;

/**
 * Convert a plain JS value into a canonical `Val`, so `valHash` can hash it.
 *
 * Three rules, each of which was a collision before it was a rule:
 *
 *  - **Object keys are sorted.** `canonEnc` walks `fs` in order and the order is
 *    part of the encoding, so `{a:1,b:2}` and `{b:2,a:1}` would otherwise hash
 *    differently while being the same value. JS object key order is insertion
 *    order, which is not part of the value.
 *
 *  - **A non-integer number is refused, not rounded and not made a string.**
 *    `Kant.Codec.Val` has six constructors -- null, bool, int, str, list, obj
 *    -- and no float, so there is no canonical form for `1.5` to hash into.
 *    IPDL drops floats for binary compatibility, and the Lean side proves
 *    `project_embed` is `LOSSLESS`, so a float carried here would be a value the
 *    wire format is specified to discard. Coercing it to `1` would let two
 *    genuinely different calls share one cache entry, which is the failure this
 *    whole module exists to prevent.
 *
 *  - **Anything else is refused, not coerced.** `undefined`, functions, symbols,
 *    `NaN`, `Infinity`, class instances. There is no spelling of those that
 *    reads back as the same thing, so a coerced hash would claim two different
 *    values are one. An unaddressable input is a loud failure at the call site,
 *    which is recoverable; a wrong cache hit is not.
 *
 * @param {*} x
 * @param {string} path  where we are, for the error message
 * @returns {object} a canonical Val
 */
export function toVal(x, path = "$") {
  return convert(x, path, 0);
}

function convert(x, path, depth) {
  if (depth > MAX_DEPTH) {
    throw new UnaddressableError(`${path}: nested deeper than ${MAX_DEPTH}`);
  }
  if (x === null) return vNull();
  switch (typeof x) {
    case "boolean":
      return vBool(x);
    case "string":
      return vStr(x);
    case "bigint":
      return vInt(x);
    case "number":
      // `Number.isInteger` and not `x % 1 === 0`: the latter is true for NaN and
      // Infinity, which have no canonical form at all.
      if (!Number.isFinite(x)) {
        throw new UnaddressableError(`${path}: ${String(x)} has no content address`);
      }
      if (!Number.isInteger(x)) {
        throw new UnaddressableError(
          `${path}: ${x} is not an integer, and Kant.Codec.Val has no float -- ` +
          `a fractional argument has no content address`,
        );
      }
      // Negative zero is refused too, and for a sharper reason than "no float":
      // `vInt` holds a BigInt and `BigInt(-0)` is `0n`, so routing `-0` there
      // would make it the same value as `0`. They are not -- a thunk can tell
      // them apart with `1 / x`, which is `-Infinity` -- and there is no tag to
      // separate them under, so this is an unaddressable value rather than a
      // value hashed wrongly.
      if (Object.is(x, -0)) {
        throw new UnaddressableError(`${path}: -0 has no content address`);
      }
      return vInt(x);
    case "undefined":
      throw new UnaddressableError(`${path}: undefined has no content address`);
    case "function":
      throw new UnaddressableError(`${path}: a function has no content address`);
    case "symbol":
      throw new UnaddressableError(`${path}: a symbol has no content address`);
    default:
      break;
  }
  if (Array.isArray(x)) {
    return vList(x.map((item, i) => convert(item, `${path}[${i}]`, depth + 1)));
  }
  const proto = Object.getPrototypeOf(x);
  if (proto !== Object.prototype && proto !== null) {
    throw new UnaddressableError(
      `${path}: ${x.constructor?.name ?? "object"} is not a plain object`,
    );
  }
  // Sorted, because canonEnc encodes fields in order and JS does not consider
  // key order part of the value.
  const keys = Object.keys(x).sort();
  const fs = keys.map((k) => [k, convert(x[k], `${path}.${k}`, depth + 1)]);
  return vObj(fs);
}

/**
 * The content hash of a thunk definition.
 *
 * `bytes` is canonicalized with `stripComments` first, so a comment or a
 * reindent does not change the id -- two peers that differ only in commentary
 * are running the same thunk.
 *
 * What it does *not* normalize is spacing *between* tokens on one line, or the
 * line structure itself. Both are deliberate. Joining two lines can change what
 * an automatic-semicolon-insertion rule does, and dropping the space in
 * `return x` would change it to `returnx`, so removing optional whitespace
 * needs a full tokenizer with an adjacency table for `+ +`, `- -`, `a in b` and
 * the rest. Getting that table wrong merges two genuinely different thunks into
 * one id, and a merged id is the exact failure this file exists to remove. An
 * id that is merely sensitive to reformatting costs a cache entry; an id that
 * collides costs correctness. So this normalizes what is safe to normalize and
 * stops there, and the id is a hash of a canonicalized source rather than of
 * its exact bytes.
 *
 * `refs` are the names of things this thunk depends on. They are part of the id
 * because a thunk built against a different ref is a different thunk, even with
 * identical source: TOOLCHAIN-THUNKS.md is the argument, and it is the same
 * argument `Cargo.toml` pinning `core2 0.4.0` makes the hard way.
 *
 * @param {string} source  the thunk source text
 * @param {string[]} [refs]  dependency names, sorted here
 * @returns {string} 64 hex chars
 */
export function thunkContentHash(source, refs = []) {
  return valHash(vObj([
    ["bytes", vStr(stripComments(source))],
    ["refs", vList([...refs].sort().map((r) => vStr(String(r))))],
  ]));
}

/** The hash of a call's arguments, independent of which thunk is running. */
export function argsHash(args) {
  return valHash(toVal(args, "args"));
}

/**
 * The call id: `{ thunkId, argsHash, secretRefs, apiRefs }`, hashed.
 *
 * `secretRefs` are *names* of sealed values, never contents. Two calls with the
 * same secret under different names get different call ids, which is correct --
 * the point of naming a slot is that the caller can say which one it meant --
 * and two calls with the same name and different contents get the *same* id,
 * which is also correct, because a secret's contents must never enter an id, a
 * log line, or a value shared with anyone else.
 *
 * `apiRefs` is here for the same reason as `secretRefs`, and for a sharper
 * reason: a result computed with a narrow api set must not be served to a
 * caller holding a wide one, because the wide one can do more with it.
 *
 * @param {{ thunkId: string, args?: object, secretRefs?: string[],
 *           apiRefs?: string[] }} call
 * @returns {string} 64 hex chars
 */
export function callHash({ thunkId, args = {}, secretRefs = [], apiRefs = [] }) {
  return valHash(vObj([
    ["thunkId", vStr(String(thunkId))],
    ["argsHash", vStr(argsHash(args))],
    ["secretRefs", vList([...secretRefs].sort().map((r) => vStr(String(r))))],
    ["apiRefs", vList([...apiRefs].sort().map((r) => vStr(String(r))))],
  ]));
}