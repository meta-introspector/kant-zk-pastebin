// Conformance checks for web/kant-codec.mjs against the golden vectors the
// Lean side pins with `#guard` in RequestProject/Kant/Codec/Tests.lean, plus
// the whole of the specification's required test list.
//
//   node web/codec-test.mjs

import * as C from "./kant-codec.mjs";

let checks = 0;
const fail = [];
function ok(name, cond) {
  checks += 1;
  if (!cond) fail.push(name);
}
function eq(name, got, want) {
  ok(`${name} (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`, got === want);
}

// -------------------------------------------------- the golden vector

// The same value the Lean side serialises, and the same five texts it
// produces for it.
const sample = C.vObj([
  ["n", C.vInt(144)],
  ["ok", C.vBool(true)],
  ["xs", C.vList([C.vNull, C.vStr('hi "there"')])],
]);

eq("canonEnc", C.canonEnc(sample), 'O3;1;nI+144;2;okT2;xsL2;ZS10;hi "there"');
eq("yamlEnc", C.yamlEnc(sample), '{"n": 144, "ok": true, "xs": [null, "hi \\"there\\""]}');
eq("xmlEnc", C.xmlEnc(sample),
  '<obj><entry key="n"><int>144</int></entry><entry key="ok"><bool>true</bool></entry>'
  + '<entry key="xs"><list><null/><str>hi &quot;there&quot;</str></list></entry></obj>');
eq("csvEncode", C.csvEncode(sample),
  'object_id,object_type,field,value,value_type,parent_id\n'
  + '"r","object","","3","count",""\n'
  + '"r/0","value","n","144","integer","r"\n'
  + '"r/1","value","ok","true","bool","r"\n'
  + '"r/2","list","xs","2","count","r"\n'
  + '"r/2/0","value","0","","null","r/2"\n'
  + '"r/2/1","value","1","hi ""there""","string","r/2"\n');
eq("ipdlText", C.ipdlText(C.embed(sample)),
  'ipdl/1.0;O3;1;nI+144;2;okT2;xsL2;ZS10;hi "there"');
eq("valHash", C.valHash(sample),
  "3c796f2f2a0e2274900747be3ace4d77bc5d9611122ebd3a189b5d4c0c56bbbd");

// ------------------------------------------------------- the harness

const CODECS = ["canonical", "yaml", "xml", "csv", "ipdl", "text", "unknown"];

function roundTrips(v) {
  return CODECS.every((f) => {
    const back = C.decodeVal(f, C.encodeVal(f, v));
    return back !== null && C.sameValue(back, v);
  });
}

function check(name, v) { ok(`round trip: ${name}`, roundTrips(v)); }

// ------------------------------------------- the required test list

check("empty object", C.vObj([]));
check("empty list", C.vList([]));
check("minimal object", C.minimalVal({
  id: "p1", kind: "theorem", inputs: [], outputs: [], status: "VALID",
}));
check("nested object", C.vObj([
  ["a", C.vObj([["b", C.vList([C.vInt(1), C.vObj([["c", C.vStr("d")]])])]])],
  ["e", C.vList([C.vList([C.vList([C.vNull])])])],
]));

const manyIO = C.vObj([
  ["inputs", C.vList([
    C.inputVal({ id: "i1", name: "n", type: "integer", value: C.vInt(144) }),
    C.inputVal({ id: "i2", name: "matrix", type: "matrix", value: C.vList([C.vList([C.vInt(1), C.vInt(0)]), C.vList([C.vInt(0), C.vInt(1)])]) }),
  ])],
  ["outputs", C.vList([
    C.outputVal({ id: "o1", name: "factorization", type: "list", value: C.vList([C.vInt(2), C.vInt(2), C.vInt(2), C.vInt(2), C.vInt(3), C.vInt(3)]) }),
    C.outputVal({ id: "o2", name: "witness", type: "text", value: C.vStr("144 = 2^4 * 3^2") }),
  ])],
]);
check("multiple inputs and outputs", manyIO);

// A missing field is a decode failure, not an invented object.
ok("missing field", C.canonDecode("O1;") === null);

// An unknown field survives in the extension namespace.
const withUnknown = C.vObj([
  ["id", C.vStr("p1")],
  ["extensions", C.vObj([["vendor.system_x", C.vObj([["k", C.vInt(7)]])], ["experimental.foo", C.vStr("bar")]])],
]);
check("unknown field", withUnknown);
ok("unknown field kept", C.canonEnc(C.decodeVal("yaml", C.encodeVal("yaml", withUnknown))) === C.canonEnc(withUnknown));

// An invalid type is a failure, not a silent coercion.
ok("invalid type", C.canonDecode("I144;") === null);

// Malformed input is kept as raw text rather than called invalid.
const malformed = "Q>>> not any format <<<";
eq("malformed detected as text", C.detect(null, malformed), "text");
eq("malformed preserved", C.rawDoc("utf-8", malformed).text, malformed);
ok("malformed does not parse", C.decodeVal("canonical", malformed) === null);

check("unicode", C.vObj([
  ["greek", C.vStr("Ὠ φ ε")], ["han", C.vStr("定理")],
  ["emoji", C.vStr("🙂🧮")], ["combining", C.vStr("éé")],
]));
check("large numbers", C.vList([
  C.vInt(18446744073709551616n), C.vInt(-18446744073709551616n),
  C.vInt(170141183460469231731687303715884105727n), C.vInt(0),
]));
check("null values", C.vObj([["a", C.vNull], ["b", C.vList([C.vNull, C.vNull])]]));
check("duplicate identifiers", C.vObj([["k", C.vInt(1)], ["k", C.vInt(2)]]));

// References and annotations: constructs with no canonical constructor,
// carried in the reserved keys rather than discarded.
const ref = C.iRef("obj-17");
const annot = C.iAnnot("author", "checked by hand", C.vInt(3));
ok("reference survives", C.canonEnc(C.project(C.recover(C.project(ref)))) === C.canonEnc(C.project(ref)));
ok("reference recognised", C.recover(C.project(ref)).t === "ref");
ok("annotation survives", C.recover(C.project(annot)).t === "annot");
eq("annotation note", C.recover(C.project(annot)).note, "checked by hand");

// Errors and warnings.
const diagnosed = C.vObj([
  ["errors", C.vList([C.vObj([
    ["code", C.vStr("TYPE_MISMATCH")], ["severity", C.vStr("ERROR")],
    ["field", C.vStr("inputs[0].value")], ["expected", C.vStr("integer")],
    ["actual", C.vStr("string")], ["recoverable", C.vBool(true)],
  ])])],
  ["warnings", C.vList([C.vObj([
    ["code", C.vStr("COERCED")], ["severity", C.vStr("WARNING")],
    ["cause", C.vStr("schema declares integer")],
    ["resolution", C.vStr("string to integer coercion")],
  ])])],
]);
check("errors and warnings", diagnosed);

// Every status in the vocabulary, including partial, failed and successful.
ok("statuses", C.STATUSES.every((s) => roundTrips(C.vObj([["status", C.vStr(s)]]))));
eq("INVALID is not ERROR", C.STATUSES.indexOf("INVALID") === C.STATUSES.indexOf("ERROR"), false);

// Lossy conversion: the minimal profile is a projection, and says so.
const fullA = { id: "p1", kind: "theorem", status: "VALID", inputs: [], outputs: [], procedure: "replay" };
const fullB = { ...fullA, procedure: "recheck" };
ok("minimal profile is lossy", C.canonEnc(C.minimalVal(fullA)) === C.canonEnc(C.minimalVal(fullB)));
ok("and the full objects differ", fullA.procedure !== fullB.procedure);

// ------------------------------------------- the proof-specific cases

const pValid = C.vObj([
  ["id", C.vStr("proof-001")], ["kind", C.vStr("factorisation")],
  ["inputs", C.vList([C.inputVal({ id: "i1", name: "n", type: "integer", value: C.vInt(144) })])],
  ["outputs", C.vList([C.outputVal({ id: "o1", name: "result", type: "integer", value: C.vInt(12), certificate: C.vStr("12*12=144") })])],
  ["status", C.vStr("VALID")],
]);
const pOther = C.vObj([
  ["id", C.vStr("proof-001")], ["kind", C.vStr("factorisation")],
  ["inputs", C.vList([C.inputVal({ id: "i1", name: "n", type: "integer", value: C.vInt(144) })])],
  ["outputs", C.vList([C.outputVal({ id: "o1", name: "result", type: "integer", value: C.vInt(13), certificate: C.vStr("13*13=144") })])],
  ["status", C.vStr("VALID")],
]);

check("known valid proof", pValid);
ok("known valid proof compares equal to itself", C.sameValue(pValid, pValid));
ok("known contradictory results differ", !C.sameValue(pValid, pOther));
ok("content identity separates them", C.valHash(pValid) !== C.valHash(pOther));

// -------------------------------------------------- cross-format exchange

for (const f of CODECS) {
  for (const g of CODECS) {
    const there = C.decodeVal(f, C.encodeVal(f, pValid));
    ok(`cross format ${f} -> ${g}`,
      there !== null && C.encodeVal(g, there) === C.encodeVal(g, pValid));
  }
}

// The transformation ledger records every conversion, with a hash.
for (const f of CODECS) {
  const rec = C.conversionRecord(f, C.valHash(pValid));
  ok(`ledger ${f}`, rec.inputHash === rec.outputHash && rec.lossiness === "LOSSLESS"
    && rec.codecVersion === "codec/1.0");
}

// ---------------------------------------------------------------- report

if (fail.length === 0) {
  console.log(`codec: ${checks} checks passed`);
} else {
  console.error(`codec: ${fail.length} of ${checks} checks FAILED`);
  for (const f of fail) console.error(`  - ${f}`);
  process.exit(1);
}
