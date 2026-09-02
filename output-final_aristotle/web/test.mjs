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


// --- feed, clipboard and memes (golden values from Lean) ----------------
const samplePaste = K.makePaste({
  id: "paste_20260902_000000",
  title: "Kant <ZK> Pastebin",
  content: "The Critique of Pure Paste",
  timestamp: "20260902_000000",
});
const replyPaste = K.makePaste({
  id: "paste_20260902_000100",
  title: "Re: Kant <ZK> Pastebin",
  content: "Antinomies of pure pasting",
  timestamp: "20260902_000100",
  replyTo: samplePaste.witness,
});

check("copyText", K.copyText(samplePaste),
  "6b7a7061737465:70617374655f32303236303930325f303030303030:4b616e74203c5a4b3e20506173746562696e:" +
  "546865204372697469717565206f662050757265205061737465:32303236303930325f303030303030:00:" +
  "666638313066323931663138376238303861303138336638336330343636383734353733656635633463366437643965643433306336663764373130663630" +
  "35");
check("copyText of a reply", K.copyText(replyPaste),
  "6b7a7061737465:70617374655f32303236303930325f303030313030:52653a204b616e74203c5a4b3e20506173746562696e:" +
  "416e74696e6f6d696573206f6620707572652070617374696e67:32303236303930325f303030313030:" +
  "01666638313066323931663138376238303861303138336638336330343636383734353733656635633463366437643965643433306336663764373130663" +
  "63035:" +
  "386162383933626538636364376362373038386436613530363566626630393466666632333264336430393664633564346230383737616265633465663139" +
  "32");
check("paste of copied text", K.pasteText(K.copyText(samplePaste)).witness, samplePaste.witness);
check("paste of a copied reply", K.pasteText(K.copyText(replyPaste)).replyTo, samplePaste.witness);
check("copyReceipt", K.copyReceipt(K.receiptOf(samplePaste, 7)),
  "6b7a726573756c74:" +
  "666638313066323931663138376238303861303138336638336330343636383734353733656635633463366437643965643433306336663764373130663630" +
  "35:da5132a0b0f291f1:1a:07");
check("paste of copied results", K.pasteReceipt(K.copyReceipt(K.receiptOf(samplePaste, 7))),
  { witness: samplePaste.witness, cid: samplePaste.cid, bytes: 26, credits: 7 });
check("tampering refused",
  K.toPaste({ tag: K.TAG_PASTE, fields: [
    K.asciiBytes(samplePaste.id), K.asciiBytes(samplePaste.title),
    [0, ...samplePaste.content], K.asciiBytes(samplePaste.timestamp),
    K.optField(null), K.asciiBytes(samplePaste.witness)] }),
  null);
check("share link round trip",
  K.toPaste(K.parseShareUrl(K.shareUrl("https://kant.zk/p", K.ofPaste(samplePaste)))).witness,
  samplePaste.witness);

const feedStore = new K.Store().sync([samplePaste, replyPaste]);
check("feed length", K.view(feedStore).length, 2);
check("newest first", K.newest(K.feed(feedStore))[0].id, replyPaste.id);
check("timeKey", K.timeKey(samplePaste), 20260902000000);
check("search hits", K.search("pure", K.feed(feedStore)).length, 1);
check("search misses", K.search("Hegel", K.feed(feedStore)).length, 0);
check("thread", K.thread(samplePaste, K.feed(feedStore)).length, 2);
check("paging is lossless",
  K.paginate(1, K.feed(feedStore)).flat().map((p) => p.witness),
  K.feed(feedStore).map((p) => p.witness));
check("row body readable", K.unescapeHtml(K.row(samplePaste).body), "The Critique of Pure Paste");

check("copy every post, paste them all back",
  K.pasteAll(K.copyAll([samplePaste, replyPaste])).map((p) => p.witness),
  [samplePaste.witness, replyPaste.witness]);
check("a broken bundle is refused", K.pasteAll("6b7a66656564:00"), null);

const memeCarrier = Array(8192).fill(128);
check("meme payload length", K.memePayload(K.ofPaste(samplePaste)).length, 315);
check("meme first samples", K.memeOfPaste(memeCarrier, samplePaste).slice(0, 24),
  [128, 129, 128, 128, 129, 128, 129, 129, 128, 129, 128, 129, 129, 128, 129, 128,
   128, 129, 128, 128, 129, 129, 128, 129]);
check("meme round trip",
  K.memeToPaste(K.memeOfPaste(memeCarrier, samplePaste)).witness, samplePaste.witness);
check("meme carries the results",
  K.memeToReceipt(K.memeOfReceipt(memeCarrier, K.receiptOf(samplePaste, 7))).credits, 7);
check("meme does not disturb the picture",
  K.memeOfPaste(memeCarrier, samplePaste).every((v, i) => Math.floor(v / 2) === 64), true);
check("meme size unchanged", K.memeOfPaste(memeCarrier, samplePaste).length, memeCarrier.length);
check("a page of the feed fits in one meme",
  K.memeToPastes(K.memeOfPastes(Array(16384).fill(128), [samplePaste, replyPaste]))
    .map((p) => p.witness),
  [samplePaste.witness, replyPaste.witness]);
check("a picture with nothing hidden decodes to nothing",
  K.memeDecode(Array(8192).fill(128)), null);

// --- quote reposts and share cards --------------------------------------
const sampleQuote = K.quoteWith(replyPaste, samplePaste);
check("quote text length", K.copyQuote(sampleQuote).length, 1528);
check("quote text prefix", K.copyQuote(sampleQuote).slice(0, 40),
  "6b7a71756f7465:3662376137303631373337343");
check("copy a quote, paste it back",
  [K.pasteQuote(K.copyQuote(sampleQuote)).comment.witness,
   K.pasteQuote(K.copyQuote(sampleQuote)).original.witness],
  [replyPaste.witness, samplePaste.witness]);
check("a doctored quotation is refused",
  K.pasteQuote(K.envelopeEncode({
    tag: K.TAG_QUOTE,
    fields: [K.asciiBytes(K.copyText(replyPaste)), K.asciiBytes("6b7a7061737465:00")],
  })), null);

const briefPost = {
  id: "a1", title: "hi", content: K.utf8("yes"), timestamp: "20260902",
  witness: K.witness(K.utf8("yes")), cid: K.nestedCid(K.utf8("yes")), replyTo: null,
};
const briefRemark = {
  id: "a2", title: "re", content: K.utf8("no"), timestamp: "20260903",
  witness: K.witness(K.utf8("no")), cid: K.nestedCid(K.utf8("no")), replyTo: null,
};
const briefQuote = K.quoteWith(briefRemark, briefPost);
check("a short quote fits a small meme",
  K.memePayload(K.ofQuote(briefQuote)).length, 737);
check("a quote travels as one picture",
  K.memeToQuote(K.memeOfQuote(memeCarrier, briefQuote)).original.witness, briefPost.witness);

const cardBase = "https://kant.zk/p";
check("card headline", K.headline(samplePaste),
  "Kant &lt;ZK&gt; Pastebin " +
  "ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605");
check("post card length", K.postCard(cardBase, samplePaste).length, 418);
check("post card prefix", K.postCard(cardBase, samplePaste).slice(0, 100),
  "Kant &lt;ZK&gt; Pastebin " +
  "ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605\nhttps://ka");
check("a post pasted from a card is the same post",
  K.toPaste(K.readCard(K.postCard(cardBase, samplePaste))).witness, samplePaste.witness);
check("results card", K.receiptCard(cardBase, K.receiptOf(samplePaste, 7)),
  "ff810f291f187b808a0183f83c0466874573ef5c4c6d7d9ed430c6f7d710f605\n" +
  "https://kant.zk/p#6b7a726573756c74:" +
  "66663831306632393166313837623830386130313833663833633034363638373435373365663563" +
  "346336643764396564343330633666376437313066363035:da5132a0b0f291f1:1a:07");
check("bundle card prefix",
  K.bundleCard(cardBase, [samplePaste, replyPaste]).slice(0, 90),
  "2\nhttps://kant.zk/p#6b7a66656564:36623761373036313733373436353a373036313733373436353566333");
check("a page pasted from a card is the same page",
  K.toPastes(K.readCard(K.bundleCard(cardBase, [samplePaste, replyPaste]))).map((p) => p.witness),
  [samplePaste.witness, replyPaste.witness]);

// --- strips: one share over several pictures ----------------------------
const stillCarrier = Array(1024).fill(128);
const firstPart = K.frames(40, K.asciiBytes(K.envelopeEncode(K.ofPaste(samplePaste))))[0];
check("part envelope text", K.envelopeEncode(K.ofFrame(firstPart)),
  "6b7a70617274::08:" +
  "36623761373036313733373436353a37303631373337343635356633323330333233363330333933");
check("a post takes eight stills", K.stripOfPaste(stillCarrier, 40, samplePaste).length, 8);
check("every still is the size of the template",
  K.stripOfPaste(stillCarrier, 40, samplePaste).every((c) => c.length === 1024), true);
check("first still samples", K.stripOfPaste(stillCarrier, 40, samplePaste)[0].slice(0, 16),
  [128, 129, 128, 128, 129, 128, 129, 129, 128, 129, 128, 129, 129, 128, 129, 128]);
check("a strip reads back as the post",
  K.stripToPaste(K.stripOfPaste(stillCarrier, 40, samplePaste)).witness, samplePaste.witness);
check("the stills may arrive in any order",
  K.stripToPaste([...K.stripOfPaste(stillCarrier, 40, samplePaste)].reverse()).witness,
  samplePaste.witness);
check("a quote takes thirty-nine stills",
  K.stripOfQuote(stillCarrier, 40, sampleQuote).length, 39);
check("a quote survives the strip",
  K.stripToQuote(K.stripOfQuote(stillCarrier, 40, sampleQuote)).original.witness,
  samplePaste.witness);
check("a page survives the strip",
  K.stripToPastes(K.stripOfPastes(stillCarrier, 40, [samplePaste, replyPaste]))
    .map((p) => p.witness),
  [samplePaste.witness, replyPaste.witness]);

console.log(failures === 0 ? "\nAll conformance checks passed." : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
