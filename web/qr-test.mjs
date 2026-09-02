// qr-test.mjs — checks for the QR encoder used to show the chat code.
//
// The matrices produced by `web/kant-qr.mjs` were cross-checked, module
// for module, against an independent QR implementation, for every mask
// (0..7) at versions 1, 9, 11, 20, 25, 28 and 40, and several of them were
// decoded by a camera-grade decoder.  The fingerprints below pin that
// result so a later edit cannot silently change what is printed.
//
// Run:  node web/qr-test.mjs

import assert from "node:assert/strict";
import {
  qrEncode, qrEncodeBytes, qrSvg, qrFingerprint, qrCodewords, rsEncode,
  versionFor, capacityBytes,
} from "./kant-qr.mjs";
import { invite, copyInvite, inviteFitsQr } from "./kant-net.mjs";
import { utf8, CHANNEL_CAPACITY } from "./kantzk.mjs";

let checks = 0;
const check = (name, fn) => { fn(); checks += 1; console.log(`  ok  ${name}`); };

const DEMO_INVITE = invite(
  "https://relay.example.org", utf8("kant-zk demo secret"), "alice",
  [{ transport: "libp2p", locator: "/dns4/relay.example.org/tcp/443/wss" },
   { transport: "iroh", locator: "irohticket1" }],
);

console.log("fingerprints (version-mask-hash)");

const FINGERPRINTS = [
  ["kzchat:abc", "1-7-937c294b"],
  [copyInvite(DEMO_INVITE), "9-2-471d705f"],
  ["https://kant.example/#" + "ab".repeat(400), "20-2-e057a183"],
  ["x".repeat(1500), "28-0-ac53572b"],
  ["y".repeat(2900), "40-1-8290cda6"],
];

for (const [text, fp] of FINGERPRINTS) {
  check(`a ${text.length}-character payload prints as ${fp}`, () =>
    assert.equal(qrFingerprint(qrEncode(text)), fp));
}

console.log("structure");

check("the error-correction codewords are right", () => {
  // Level L, version 1, "kzchat:abc": data then the seven EC codewords.
  assert.deepEqual(qrCodewords(utf8("kzchat:abc"), 1), [
    64, 166, 183, 166, 54, 134, 23, 67, 166, 22, 38, 48,
    236, 17, 236, 17, 236, 17, 236,
    20, 126, 4, 16, 117, 211, 124,
  ]);
});

check("Reed–Solomon of an all-zero block is zero", () =>
  assert.deepEqual(rsEncode([0, 0, 0], 7), [0, 0, 0, 0, 0, 0, 0]));

check("versions grow with the payload", () => {
  assert.equal(versionFor(10), 1);
  assert.equal(versionFor(capacityBytes(1)), 1);
  assert.equal(versionFor(capacityBytes(1) + 1), 2);
  assert.equal(versionFor(2953), 40);
  assert.equal(versionFor(2954), 0);
});

check("the largest version matches the capacity proved in Lean", () =>
  assert.equal(capacityBytes(40), CHANNEL_CAPACITY.qr));

check("matrix sizes follow the version", () => {
  for (const v of [1, 7, 20, 40]) {
    const qr = qrEncodeBytes(utf8("z"), { version: v });
    assert.equal(qr.size, 17 + 4 * v);
    assert.equal(qr.modules.length, qr.size);
  }
});

check("the finder patterns are in all three corners", () => {
  const qr = qrEncode("finder");
  const n = qr.size;
  for (const [r0, c0] of [[0, 0], [0, n - 7], [n - 7, 0]]) {
    assert.equal(qr.modules[r0][c0], 1);
    assert.equal(qr.modules[r0 + 1][c0 + 1], 0);
    assert.equal(qr.modules[r0 + 3][c0 + 3], 1);
  }
});

check("the dark module is dark", () => {
  const qr = qrEncode("dark");
  assert.equal(qr.modules[qr.size - 8][8], 1);
});

console.log("the chat code");

check("a chat invitation fits in one code", () => {
  assert.ok(inviteFitsQr(DEMO_INVITE));
  const qr = qrEncode(copyInvite(DEMO_INVITE));
  assert.ok(qr.version <= 40);
});

check("the code renders as standalone SVG", () => {
  const svg = qrSvg(qrEncode(copyInvite(DEMO_INVITE)), { scale: 3, border: 4 });
  assert.ok(svg.startsWith("<svg xmlns=\"http://www.w3.org/2000/svg\""));
  assert.ok(svg.includes("<rect"));
  assert.ok(svg.endsWith("</svg>"));
});

check("a payload that cannot fit is refused", () => {
  assert.throws(() => qrEncode("z".repeat(3000)));
});

console.log(`\nall ${checks} QR checks passed`);
