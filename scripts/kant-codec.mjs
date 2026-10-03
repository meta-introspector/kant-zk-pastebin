// kant-codec.mjs — the standard proof codec: one canonical object, and
// adapters to and from IPDL, XML, CSV, YAML and raw text.
//
// An unverified transcription of `RequestProject/Kant/Codec/*.lean`.  Every
// function here matches a Lean definition of the same name, and
// `web/codec-test.mjs` pins them against the same golden vectors the Lean
// files check with `#guard`.
//
// The canonical value is a tagged object:
//
//   { t: "null" }
//   { t: "bool", b: Boolean }
//   { t: "int",  n: BigInt }
//   { t: "str",  s: String }
//   { t: "list", xs: [Val] }
//   { t: "obj",  fs: [[String, Val]] }
//
// and an IPDL document is the same, plus
//
//   { t: "ref",   target: String }
//   { t: "annot", key: String, note: String, body: Ipdl }
//
// Text is handled as arrays of code points, exactly as the Lean side
// handles `List Char`, so string lengths agree on all of Unicode.

import { witness } from "./kantzk.mjs";

// ------------------------------------------------------------ constructors

export const vNull = { t: "null" };
export const vBool = (b) => ({ t: "bool", b: !!b });
export const vInt = (n) => ({ t: "int", n: BigInt(n) });
export const vStr = (s) => ({ t: "str", s: String(s) });
export const vList = (xs) => ({ t: "list", xs: xs.slice() });
export const vObj = (fs) => ({ t: "obj", fs: fs.map(([k, v]) => [String(k), v]) });

export const iRef = (target) => ({ t: "ref", target: String(target) });
export const iAnnot = (key, note, body) => ({ t: "annot", key, note, body });

const cps = (s) => Array.from(s);
const cpLength = (s) => cps(s).length;

/** A cursor over the code points of a piece of text. */
class Cursor {
  constructor(text) {
    this.cs = cps(text);
    this.i = 0;
  }
  get done() { return this.i >= this.cs.length; }
  peek(k = 0) { return this.cs[this.i + k]; }
  next() {
    if (this.done) throw new CodecError("unexpected end of input");
    return this.cs[this.i++];
  }
  expect(c) {
    const got = this.next();
    if (got !== c) throw new CodecError(`expected ${JSON.stringify(c)}, got ${JSON.stringify(got)}`);
  }
  take(n) {
    if (this.i + n > this.cs.length) throw new CodecError("string runs past the end");
    const out = this.cs.slice(this.i, this.i + n).join("");
    this.i += n;
    return out;
  }
  startsWith(lit) {
    const l = cps(lit);
    for (let k = 0; k < l.length; k += 1) if (this.cs[this.i + k] !== l[k]) return false;
    return true;
  }
  strip(lit) {
    if (!this.startsWith(lit)) return false;
    this.i += cps(lit).length;
    return true;
  }
  need(lit) { if (!this.strip(lit)) throw new CodecError(`expected ${JSON.stringify(lit)}`); }
}

/** A decode failure.  Never thrown out of the exported decoders: they
 *  return `null`, which is what `Option.none` is on the Lean side. */
export class CodecError extends Error {}

const DIGITS = "0123456789";
const digitVal = (c) => (c !== undefined && DIGITS.includes(c) ? DIGITS.indexOf(c) : null);

// -------------------------------------------------- canonical serialization

/** `Kant.Codec.natDigits`. */
export const natDigits = (n) => BigInt(n).toString(10);

/** `Kant.Codec.encStr`: length-prefixed, so nothing needs escaping. */
export const encStr = (s) => `${cpLength(s)};${s}`;

/** `Kant.Codec.encInt`: an explicit sign, the digits, then `;`. */
export const encInt = (n) => `${BigInt(n) < 0n ? "-" : "+"}${(BigInt(n) < 0n ? -BigInt(n) : BigInt(n)).toString(10)};`;

/** `Kant.Codec.canonEnc`: the deterministic serialization, suitable for
 *  hashing. */
export function canonEnc(v) {
  switch (v.t) {
    case "null": return "Z";
    case "bool": return v.b ? "T" : "F";
    case "int": return `I${encInt(v.n)}`;
    case "str": return `S${encStr(v.s)}`;
    case "list": return `L${v.xs.length};${v.xs.map(canonEnc).join("")}`;
    case "obj": return `O${v.fs.length};${v.fs.map(([k, x]) => encStr(k) + canonEnc(x)).join("")}`;
    default: throw new CodecError(`not a canonical value: ${v.t}`);
  }
}

function readNat(cur) {
  let acc = 0n;
  for (;;) {
    const c = cur.next();
    if (c === ";") return acc;
    const d = digitVal(c);
    if (d === null) throw new CodecError("not a digit");
    acc = acc * 10n + BigInt(d);
  }
}

function readStrC(cur) { return cur.take(Number(readNat(cur))); }

function readIntC(cur) {
  const sign = cur.next();
  if (sign !== "-" && sign !== "+") throw new CodecError("missing sign");
  const n = readNat(cur);
  return sign === "-" ? -n : n;
}

function pVal(cur) {
  const c = cur.next();
  switch (c) {
    case "Z": return vNull;
    case "T": return vBool(true);
    case "F": return vBool(false);
    case "I": return vInt(readIntC(cur));
    case "S": return vStr(readStrC(cur));
    case "L": {
      const n = Number(readNat(cur));
      const xs = [];
      for (let k = 0; k < n; k += 1) xs.push(pVal(cur));
      return vList(xs);
    }
    case "O": {
      const n = Number(readNat(cur));
      const fs = [];
      for (let k = 0; k < n; k += 1) {
        const key = readStrC(cur);
        fs.push([key, pVal(cur)]);
      }
      return vObj(fs);
    }
    default: throw new CodecError(`unknown tag ${JSON.stringify(c)}`);
  }
}

/** Run a parser over the whole of a piece of text; `null` on any failure. */
function whole(text, parse) {
  try {
    const cur = new Cursor(text);
    const v = parse(cur);
    return cur.done ? v : null;
  } catch (e) {
    if (e instanceof CodecError) return null;
    throw e;
  }
}

/** `Kant.Codec.canonDecode`. */
export const canonDecode = (s) => whole(s, pVal);

/** `Kant.Codec.charBytes`: four bytes per code point, so the map is
 *  injective on all of Unicode. */
export function charBytes(c) {
  const n = c.codePointAt(0);
  return [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255];
}

/** `Kant.Codec.valHash`: the content identity of a canonical value. */
export function valHash(v) {
  const bytes = [];
  for (const c of cps(canonEnc(v))) bytes.push(...charBytes(c));
  return witness(bytes);
}

// -------------------------------------------------------------- YAML codec

const Y_ESCAPES = { "\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r", "\t": "\\t" };
const Y_UNESCAPES = { "\\": "\\", '"': '"', n: "\n", r: "\r", t: "\t" };

/** `Kant.Codec.esc`. */
export const yesc = (s) => cps(s).map((c) => Y_ESCAPES[c] ?? c).join("");

/** `Kant.Codec.encNumY`. */
export const encNumY = (n) => BigInt(n).toString(10);

/** `Kant.Codec.yamlEnc`: the human-readable flow projection. */
export function yamlEnc(v) {
  switch (v.t) {
    case "null": return "null";
    case "bool": return v.b ? "true" : "false";
    case "int": return encNumY(v.n);
    case "str": return `"${yesc(v.s)}"`;
    case "list": return `[${v.xs.map(yamlEnc).join(", ")}]`;
    case "obj": return `{${v.fs.map(([k, x]) => `"${yesc(k)}": ${yamlEnc(x)}`).join(", ")}}`;
    default: throw new CodecError(`not a canonical value: ${v.t}`);
  }
}

function readQuoted(cur) {
  let out = "";
  for (;;) {
    const c = cur.next();
    if (c === '"') return out;
    if (c === "\\") {
      const d = cur.next();
      const e = Y_UNESCAPES[d];
      if (e === undefined) throw new CodecError("unknown escape");
      out += e;
    } else out += c;
  }
}

function yVal(cur) {
  const c = cur.peek();
  if (c === '"') { cur.next(); return vStr(readQuoted(cur)); }
  if (c === "[") {
    cur.next();
    const xs = [];
    if (cur.strip("]")) return vList(xs);
    for (;;) {
      xs.push(yVal(cur));
      if (cur.strip("]")) return vList(xs);
      cur.need(", ");
    }
  }
  if (c === "{") {
    cur.next();
    const fs = [];
    if (cur.strip("}")) return vObj(fs);
    for (;;) {
      cur.expect('"');
      const k = readQuoted(cur);
      cur.need(": ");
      fs.push([k, yVal(cur)]);
      if (cur.strip("}")) return vObj(fs);
      cur.need(", ");
    }
  }
  if (cur.strip("null")) return vNull;
  if (cur.strip("true")) return vBool(true);
  if (cur.strip("false")) return vBool(false);
  let sign = 1n;
  if (cur.peek() === "-") { cur.next(); sign = -1n; }
  if (digitVal(cur.peek()) === null) throw new CodecError("not a value");
  let acc = 0n;
  while (digitVal(cur.peek()) !== null) acc = acc * 10n + BigInt(digitVal(cur.next()));
  return vInt(sign * acc);
}

/** `Kant.Codec.yamlDecode`. */
export const yamlDecode = (s) => whole(s, yVal);

// --------------------------------------------------------------- XML codec

const X_ESCAPES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;" };

/** `Kant.Codec.xesc`. */
export const xesc = (s) => cps(s).map((c) => X_ESCAPES[c] ?? c).join("");

/** `Kant.Codec.xmlEnc`: elements, attributes and text nodes, distinctly. */
export function xmlEnc(v) {
  switch (v.t) {
    case "null": return "<null/>";
    case "bool": return v.b ? "<bool>true</bool>" : "<bool>false</bool>";
    case "int": return `<int>${encNumY(v.n)}</int>`;
    case "str": return `<str>${xesc(v.s)}</str>`;
    case "list": return `<list>${v.xs.map(xmlEnc).join("")}</list>`;
    case "obj":
      return `<obj>${v.fs.map(([k, x]) => `<entry key="${xesc(k)}">${xmlEnc(x)}</entry>`).join("")}</obj>`;
    default: throw new CodecError(`not a canonical value: ${v.t}`);
  }
}

function readXUntil(cur, term) {
  let out = "";
  for (;;) {
    if (cur.done) return out;
    if (cur.peek() === term) return out;
    if (cur.peek() === "&") {
      if (cur.strip("&amp;")) { out += "&"; continue; }
      if (cur.strip("&lt;")) { out += "<"; continue; }
      if (cur.strip("&gt;")) { out += ">"; continue; }
      if (cur.strip("&quot;")) { out += '"'; continue; }
      if (cur.strip("&apos;")) { out += "'"; continue; }
      throw new CodecError("unknown entity");
    }
    out += cur.next();
  }
}

function readXNumber(cur) {
  let sign = 1n;
  if (cur.peek() === "-") { cur.next(); sign = -1n; }
  if (digitVal(cur.peek()) === null) throw new CodecError("not a number");
  let acc = 0n;
  while (digitVal(cur.peek()) !== null) acc = acc * 10n + BigInt(digitVal(cur.next()));
  return sign * acc;
}

function xVal(cur) {
  if (cur.strip("<null/>")) return vNull;
  if (cur.strip("<bool>true</bool>")) return vBool(true);
  if (cur.strip("<bool>false</bool>")) return vBool(false);
  if (cur.strip("<int>")) { const n = readXNumber(cur); cur.need("</int>"); return vInt(n); }
  if (cur.strip("<str>")) { const s = readXUntil(cur, "<"); cur.need("</str>"); return vStr(s); }
  if (cur.strip("<list>")) {
    const xs = [];
    while (!cur.strip("</list>")) xs.push(xVal(cur));
    return vList(xs);
  }
  if (cur.strip("<obj>")) {
    const fs = [];
    while (!cur.strip("</obj>")) {
      cur.need('<entry key="');
      const k = readXUntil(cur, '"');
      cur.need('">');
      fs.push([k, xVal(cur)]);
      cur.need("</entry>");
    }
    return vObj(fs);
  }
  throw new CodecError("not an element");
}

/** `Kant.Codec.xmlDecode`. */
export const xmlDecode = (s) => whole(s, xVal);

// --------------------------------------------------------------- CSV codec

/** `Kant.Codec.csvHeader`. */
export const CSV_HEADER = "object_id,object_type,field,value,value_type,parent_id\n";

const csvField = (s) => `"${cps(s).map((c) => (c === '"' ? '""' : c)).join("")}"`;

const rowText = (r) => [r.objectId, r.objectType, r.field, r.value, r.valueType, r.parentId]
  .map(csvField).join(",") + "\n";

/** `Kant.Codec.rowsVal`: the preorder table of a value, with a row per
 *  node and a child count where the node has children. */
export function rowsVal(id, parent, field, v) {
  switch (v.t) {
    case "null": return [{ objectId: id, objectType: "value", field, value: "", valueType: "null", parentId: parent }];
    case "bool": return [{ objectId: id, objectType: "value", field, value: v.b ? "true" : "false", valueType: "bool", parentId: parent }];
    case "int": return [{ objectId: id, objectType: "value", field, value: encNumY(v.n), valueType: "integer", parentId: parent }];
    case "str": return [{ objectId: id, objectType: "value", field, value: v.s, valueType: "string", parentId: parent }];
    case "list": {
      const rows = [{ objectId: id, objectType: "list", field, value: natDigits(v.xs.length), valueType: "count", parentId: parent }];
      v.xs.forEach((x, i) => rows.push(...rowsVal(`${id}/${natDigits(i)}`, id, natDigits(i), x)));
      return rows;
    }
    case "obj": {
      const rows = [{ objectId: id, objectType: "object", field, value: natDigits(v.fs.length), valueType: "count", parentId: parent }];
      v.fs.forEach(([k, x], i) => rows.push(...rowsVal(`${id}/${natDigits(i)}`, id, k, x)));
      return rows;
    }
    default: throw new CodecError(`not a canonical value: ${v.t}`);
  }
}

/** `Kant.Codec.csvEncode`. */
export const csvEncode = (v) => CSV_HEADER + rowsVal("r", "", "", v).map(rowText).join("");

function readCsvCell(cur, term) {
  cur.expect('"');
  let out = "";
  for (;;) {
    const c = cur.next();
    if (c === '"') {
      if (cur.peek() === '"') { cur.next(); out += '"'; continue; }
      cur.expect(term);
      return out;
    }
    out += c;
  }
}

function readRow(cur) {
  const objectId = readCsvCell(cur, ",");
  const objectType = readCsvCell(cur, ",");
  const field = readCsvCell(cur, ",");
  const value = readCsvCell(cur, ",");
  const valueType = readCsvCell(cur, ",");
  const parentId = readCsvCell(cur, "\n");
  return { objectId, objectType, field, value, valueType, parentId };
}

function readRowVal(rows) {
  if (rows.length === 0) throw new CodecError("no rows");
  const r = rows.shift();
  if (r.valueType === "null") return vNull;
  if (r.valueType === "bool") return vBool(r.value === "true");
  if (r.valueType === "integer") return vInt(BigInt(r.value));
  if (r.valueType === "string") return vStr(r.value);
  if (r.valueType === "count") {
    const n = Number(r.value);
    if (!Number.isInteger(n) || n < 0) throw new CodecError("bad count");
    if (r.objectType === "list") {
      const xs = [];
      for (let k = 0; k < n; k += 1) xs.push(readRowVal(rows));
      return vList(xs);
    }
    if (r.objectType === "object") {
      const fs = [];
      for (let k = 0; k < n; k += 1) {
        const key = rows.length ? rows[0].field : null;
        if (key === null) throw new CodecError("missing entry");
        fs.push([key, readRowVal(rows)]);
      }
      return vObj(fs);
    }
    throw new CodecError("bad container");
  }
  throw new CodecError("unknown value type");
}

/** `Kant.Codec.csvDecode`. */
export function csvDecode(s) {
  try {
    const cur = new Cursor(s);
    if (!cur.strip(CSV_HEADER)) return null;
    const rows = [];
    while (!cur.done) rows.push(readRow(cur));
    const v = readRowVal(rows);
    return rows.length === 0 ? v : null;
  } catch (e) {
    if (e instanceof CodecError) return null;
    throw e;
  }
}

// -------------------------------------------------------------- IPDL codec

/** `Kant.Codec.ipdlRefKey` and friends: the keys the adapter reserves for
 *  constructs the canonical model has no constructor for. */
export const IPDL_REF = "$ipdl.ref";
export const IPDL_ANNOT = "$ipdl.annotation";
export const IPDL_NOTE = "$ipdl.note";
export const IPDL_BODY = "$ipdl.body";
export const IPDL_HEADER = "ipdl/1.0;";

/** `Kant.Codec.embed`: a canonical value as an IPDL document. */
export function embed(v) {
  switch (v.t) {
    case "list": return { t: "list", xs: v.xs.map(embed) };
    case "obj": return { t: "obj", fs: v.fs.map(([k, x]) => [k, embed(x)]) };
    default: return v;
  }
}

/** `Kant.Codec.project`: an IPDL document as a canonical value. */
export function project(i) {
  switch (i.t) {
    case "list": return vList(i.xs.map(project));
    case "obj": return vObj(i.fs.map(([k, x]) => [k, project(x)]));
    case "ref": return vObj([[IPDL_REF, vStr(i.target)]]);
    case "annot":
      return vObj([[IPDL_ANNOT, vStr(i.key)], [IPDL_NOTE, vStr(i.note)], [IPDL_BODY, project(i.body)]]);
    default: return i;
  }
}

/** `Kant.Codec.rebuild`: recognising the reserved shapes. */
export function rebuild(fs) {
  if (fs.length === 1 && fs[0][0] === IPDL_REF && fs[0][1].t === "str") return iRef(fs[0][1].s);
  if (fs.length === 3 && fs[0][0] === IPDL_ANNOT && fs[1][0] === IPDL_NOTE && fs[2][0] === IPDL_BODY
      && fs[0][1].t === "str" && fs[1][1].t === "str") {
    return iAnnot(fs[0][1].s, fs[1][1].s, fs[2][1]);
  }
  return { t: "obj", fs };
}

/** `Kant.Codec.recover`: a canonical value read back as an IPDL document,
 *  references and annotations included. */
export function recover(v) {
  switch (v.t) {
    case "list": return { t: "list", xs: v.xs.map(recover) };
    case "obj": return rebuild(v.fs.map(([k, x]) => [k, recover(x)]));
    default: return v;
  }
}

/** `Kant.Codec.ipdlText`. */
export const ipdlText = (i) => IPDL_HEADER + canonEnc(project(i));

/** `Kant.Codec.ipdlRead`. */
export function ipdlRead(s) {
  const cur = new Cursor(s);
  if (!cur.strip(IPDL_HEADER)) return null;
  const v = canonDecode(cur.cs.slice(cur.i).join(""));
  return v === null ? null : recover(v);
}

// ------------------------------------------------------- raw text and detect

/** `Kant.Codec.splitLines`. */
export const splitLines = (s) => s.split("\n");

/** `Kant.Codec.joinLines`. */
export const joinLines = (ls) => ls.join("\n");

/** `Kant.Codec.rawDoc`: raw text with the original kept as a field, not as
 *  a by-product. */
export const rawDoc = (encoding, s) => ({
  text: s,
  encoding,
  lines: splitLines(s),
  detected: [{ kind: "line", offset: 0, length: cpLength(s) }],
  confidence: 100,
});

/** Every format the codec offers. */
export const FORMATS = ["canonical", "yaml", "xml", "csv", "ipdl", "text", "unknown"];

/** `Kant.Codec.detect`: declared, then signature, then syntax, then the
 *  raw-text fallback. */
export function detect(declared, s) {
  if (declared) return declared;
  if (s.startsWith(IPDL_HEADER)) return "ipdl";
  if (s.startsWith(CSV_HEADER)) return "csv";
  if (xmlDecode(s) !== null) return "xml";
  if (canonDecode(s) !== null) return "canonical";
  if (yamlDecode(s) !== null) return "yaml";
  return "text";
}

/** `Kant.Codec.encodeVal`. */
export function encodeVal(fmt, v) {
  switch (fmt) {
    case "yaml": return yamlEnc(v);
    case "xml": return xmlEnc(v);
    case "csv": return csvEncode(v);
    case "ipdl": return ipdlText(embed(v));
    default: return canonEnc(v);
  }
}

/** `Kant.Codec.decodeVal`. */
export function decodeVal(fmt, s) {
  switch (fmt) {
    case "yaml": return yamlDecode(s);
    case "xml": return xmlDecode(s);
    case "csv": return csvDecode(s);
    case "ipdl": { const i = ipdlRead(s); return i === null ? null : project(i); }
    default: return canonDecode(s);
  }
}

/** Two canonical values mean the same thing exactly when their canonical
 *  texts agree (`Kant.Codec.canonEnc_injective`). */
export const sameValue = (a, b) => canonEnc(a) === canonEnc(b);

// ------------------------------------------------------ the proof object

/** The status vocabulary (`Kant.Codec.Status`). */
export const STATUSES = ["UNKNOWN", "PENDING", "VALID", "INVALID", "PARTIAL", "ERROR", "CONFLICT", "UNSUPPORTED"];

/** The severity vocabulary (`Kant.Codec.Severity`). */
export const SEVERITIES = ["INFO", "WARNING", "ERROR", "FATAL"];

/** The preservation levels (`Kant.Codec.Loss`). */
export const LOSSINESS = ["LOSSLESS", "LOSSY", "PARTIAL", "FAILED"];

const S = (s) => vStr(s ?? "");
const L = (xs) => vList(xs ?? []);

/** An input (`Kant.Codec.Inp.toVal`). */
export const inputVal = (i) => vObj([
  ["id", S(i.id)], ["name", S(i.name)], ["type", S(i.type)], ["value", i.value ?? vNull],
  ["encoding", S(i.encoding)], ["units", S(i.units)], ["constraints", L(i.constraints)],
]);

/** An output (`Kant.Codec.Outp.toVal`). */
export const outputVal = (o) => vObj([
  ["id", S(o.id)], ["name", S(o.name)], ["type", S(o.type)], ["value", o.value ?? vNull],
  ["encoding", S(o.encoding)], ["claims", L(o.claims)], ["certificate", o.certificate ?? vNull],
]);

/** The minimal interchange profile (`Kant.Codec.Obj.minimal`): the fields
 *  every system must support.  A `PARTIAL` projection, not a lossless one. */
export const minimalVal = (o) => vObj([
  ["id", S(o.id)], ["kind", S(o.kind)],
  ["inputs", L((o.inputs ?? []).map(inputVal))],
  ["outputs", L((o.outputs ?? []).map(outputVal))],
  ["status", S(o.status ?? "UNKNOWN")],
]);

/** The transformation ledger entry for one conversion
 *  (`Kant.Codec.conversionRecord`). */
export const conversionRecord = (fmt, hash) => ({
  id: "export",
  operation: "encode",
  source: "canonical",
  destination: fmt,
  inputHash: hash,
  outputHash: hash,
  codec: fmt,
  codecVersion: "codec/1.0",
  lossiness: "LOSSLESS",
  errors: [],
  warnings: [],
});

/** The schema version this codec writes. */
export const SCHEMA_VERSION = "proof-schema/1.0";
