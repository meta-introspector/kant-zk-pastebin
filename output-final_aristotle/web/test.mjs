// Conformance test: the JavaScript transcription in `kantzk.mjs` must
// agree with the Lean development.  The expected values below were
// computed by Lean (see `RequestProject/Kant/Demo.lean`), so this test
// pins the JS port to the proved specification.
//
//   node web/test.mjs

import * as K from "./kantzk.mjs";

let failures = 0;
function check(name, actual, expected) {
  const a = JSON.stringify(actual, (_, v) => (typeof v === "bigint" ? v.toString() : v));
  const e = JSON.stringify(expected, (_, v) => (typeof v === "bigint" ? v.toString() : v));
  if (a === e) {
    console.log(`ok    ${name}`);
  } else {
    failures += 1;
    console.log(`FAIL  ${name}\n  expected ${e}\n  actual   ${a}`);
  }
}

const sample = K.utf8("The Critique of Pure Paste");

// --- content addressing (golden values from Lean) -----------------------
check("witness", K.witness(sample),
  "ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605");
check("daslHex", K.daslHex(K.nestedCid(sample)), "0xda5132a0b0f291f1");
check("cidType", Number(K.cidType(K.nestedCid(sample))), 3);
check("orbifold", K.orbifoldCoords(sample), { l: 60, m: 29, n: 5 });

// --- eRDFa ---------------------------------------------------------------
check("escape", K.escapeHtml('<a href="x">&</a>'),
  "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;");
check("escape/unescape round trip",
  K.unescapeHtml(K.escapeHtml('<a href="x">&</a>')), '<a href="x">&</a>');

// --- framing -------------------------------------------------------------
const fs8 = K.frames(8, sample);
check("frame payloads", fs8.map((f) => [f.seq, f.payload]), [
  [0, [84, 104, 101, 32, 67, 114, 105, 116]],
  [1, [105, 113, 117, 101, 32, 111, 102, 32]],
  [2, [80, 117, 114, 101, 32, 80, 97, 115]],
  [3, [116, 101]],
]);
check("reassemble in order", K.reassemble(fs8), sample);
check("reassemble shuffled", K.reassemble([...fs8].reverse()), sample);
check("5MB cap respected",
  K.frames(K.SOCIAL_LIMIT, sample).every((f) => f.payload.length <= K.SOCIAL_LIMIT), true);

// --- stego ---------------------------------------------------------------
check("embedBits", K.embedBits(Array(24).fill(128), K.toBits([65, 66, 67])),
  [128, 129, 128, 128, 128, 128, 128, 129, 128, 129, 128, 128,
   128, 128, 129, 128, 128, 129, 128, 128, 128, 128, 129, 129]);
const carrier = Array(512).fill(128);
check("stego round trip", K.extractBlob(3, K.embedBlob(carrier, [65, 66, 67])), [65, 66, 67]);
check("stego distortion ≤ 1",
  K.embedBlob(carrier, [65, 66, 67]).every((v, i) => Math.floor(v / 2) === Math.floor(carrier[i] / 2)),
  true);

// --- code movies ---------------------------------------------------------
check("rleEncode", K.rleEncode([1, 1, 1, 2, 2]), [[1, 3], [2, 2]]);
check("rle round trip", K.rleDecode(K.rleEncode([1, 1, 1, 2, 2])), [1, 1, 1, 2, 2]);
check("godel", K.godel([1, 2, 3]), 29586n);
check("godel round trip", K.ungodel(K.godel([1, 2, 3])).map(Number), [1, 2, 3]);
const movie = [[1, 1, 1, 2, 2], [3, 3, 3, 3], [4]];
check("movieGodel", K.movieGodel(movie), 644468914277383917536159541511687883n);
check("movie round trip", K.unmovie(K.movieGodel(movie)).map((f) => f.map(Number)), movie);

// --- circuits ------------------------------------------------------------
const circ = K.Circuit.and(K.Circuit.inp(0), K.Circuit.not(K.Circuit.or(K.Circuit.inp(1), K.Circuit.const(false))));
check("circuit encoding",
  K.circuitEncode(circ),
  14201637985718948065654113358945453826445462254920583295862733277493589504347349328460647492128812649750452609025365036526804693787128596430882432278838316016367358280911827552055263551018125504173501337246516587531406704750981427104998025998210424842905527755260452099681129816575008677n);
check("circuit round trip", K.circuitTokens(K.circuitDecode(K.circuitEncode(circ))),
  K.circuitTokens(circ));
check("circuit eval", K.circuitEval((i) => i === 0, circ), true);
check("circuit eval 2", K.circuitEval(() => true, circ), false);

// --- store, sync, credits ------------------------------------------------
const p = K.makePaste({ id: "paste_1", title: "t", content: "hello", timestamp: "now" });
const a = new K.Store().sync([p, p]);
const b = new K.Store().sync([p]);
check("store dedup", a.entries.length, 1);
check("sync converges", a.get(p.witness).witness, b.get(p.witness).witness);

const L = new K.Ledger().serve("peer-a", 4 * 1024).serve("peer-b", 512);
check("credits earned", L.balance("peer-a"), 4);
check("sub-KiB earns nothing", L.balance("peer-b"), 0);
check("overdraft refused", L.spend("peer-a", 5), null);
check("spend debits", L.spend("peer-a", 3).balance("peer-a"), 1);

console.log(failures === 0 ? "\nAll conformance checks passed." : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
