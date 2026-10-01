// kant-qr.mjs — a self-contained QR encoder, so the chat code can be shown
// offline with no library, no CDN and no server.
//
// Byte mode, error-correction level L (the level whose 2953-byte capacity
// is the `Kant.Sneakernet.Channel.qr` bound proved in Lean), versions 1
// to 40, automatic version and mask selection.  It renders the invitation
// text produced by `kant-net.mjs` (`copyInvite`), which is pure ASCII, so
// the byte mode encoding is exact.
//
// `web/qr-test.mjs` checks the module matrices against fixed fingerprints
// that were cross-checked against an independent QR implementation.

// (count, total codewords, data codewords) per block group, level L, v1..v40.
const RS_BLOCKS_L = [
  [[1,26,19]],[[1,44,34]],[[1,70,55]],[[1,100,80]],[[1,134,108]],[[2,86,68]],
  [[2,98,78]],[[2,121,97]],[[2,146,116]],[[2,86,68],[2,87,69]],[[4,101,81]],
  [[2,116,92],[2,117,93]],[[4,133,107]],[[3,145,115],[1,146,116]],
  [[5,109,87],[1,110,88]],[[5,122,98],[1,123,99]],[[1,135,107],[5,136,108]],
  [[5,150,120],[1,151,121]],[[3,141,113],[4,142,114]],[[3,135,107],[5,136,108]],
  [[4,144,116],[4,145,117]],[[2,139,111],[7,140,112]],[[4,151,121],[5,152,122]],
  [[6,147,117],[4,148,118]],[[8,132,106],[4,133,107]],[[10,142,114],[2,143,115]],
  [[8,152,122],[4,153,123]],[[3,147,117],[10,148,118]],[[7,146,116],[7,147,117]],
  [[5,145,115],[10,146,116]],[[13,145,115],[3,146,116]],[[17,145,115]],
  [[17,145,115],[1,146,116]],[[13,145,115],[6,146,116]],[[12,151,121],[7,152,122]],
  [[6,151,121],[14,152,122]],[[17,152,122],[4,153,123]],[[4,152,122],[18,153,123]],
  [[20,147,117],[4,148,118]],[[19,148,118],[6,149,119]],
];

// Centres of the alignment patterns, v1..v40.
const ALIGN_POS = [
  [],[6,18],[6,22],[6,26],[6,30],[6,34],[6,22,38],[6,24,42],[6,26,46],[6,28,50],
  [6,30,54],[6,32,58],[6,34,62],[6,26,46,66],[6,26,48,70],[6,26,50,74],
  [6,30,54,78],[6,30,56,82],[6,30,58,86],[6,34,62,90],[6,28,50,72,94],
  [6,26,50,74,98],[6,30,54,78,102],[6,28,54,80,106],[6,32,58,84,110],
  [6,30,58,86,114],[6,34,62,90,118],[6,26,50,74,98,122],[6,30,54,78,102,126],
  [6,26,52,78,104,130],[6,30,56,82,108,134],[6,34,60,86,112,138],
  [6,30,58,86,114,142],[6,34,62,90,118,146],[6,30,54,78,102,126,150],
  [6,24,50,76,102,128,154],[6,28,54,80,106,132,158],[6,32,58,84,110,136,162],
  [6,26,54,82,110,138,166],[6,30,58,86,114,142,170],
];

const remainderBits = (v) =>
  v === 1 ? 0 : v <= 6 ? 7 : v <= 13 ? 0 : v <= 20 ? 3 : v <= 27 ? 4 : v <= 34 ? 3 : 0;

/** Data capacity in bytes at level L, per version. */
export function capacityBytes(version) {
  const blocks = RS_BLOCKS_L[version - 1];
  const dataCw = blocks.reduce((n, [c, , d]) => n + c * d, 0);
  const header = 4 + (version < 10 ? 8 : 16);
  return dataCw - Math.ceil(header / 8);
}

/** The smallest version that holds `n` bytes, or 0 if none does. */
export function versionFor(n) {
  for (let v = 1; v <= 40; v++) if (capacityBytes(v) >= n) return v;
  return 0;
}

// ------------------------------------------------------------- GF(256)

const EXP = new Uint8Array(512);
const LOG = new Uint8Array(256);
(() => {
  let x = 1;
  for (let i = 0; i < 255; i++) {
    EXP[i] = x;
    LOG[x] = i;
    x <<= 1;
    if (x & 0x100) x ^= 0x11d;
  }
  for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
})();

const gmul = (a, b) => (a === 0 || b === 0 ? 0 : EXP[LOG[a] + LOG[b]]);

function generatorPoly(n) {
  let poly = [1];
  for (let i = 0; i < n; i++) {
    const next = new Array(poly.length + 1).fill(0);
    for (let j = 0; j < poly.length; j++) {
      next[j] ^= poly[j];
      next[j + 1] ^= gmul(poly[j], EXP[i]);
    }
    poly = next;
  }
  return poly;
}

/** Reed–Solomon error-correction codewords for one block. */
export function rsEncode(data, ecCount) {
  const gen = generatorPoly(ecCount);
  const res = new Array(ecCount).fill(0);
  for (const b of data) {
    const factor = b ^ res[0];
    res.shift();
    res.push(0);
    for (let i = 0; i < ecCount; i++) res[i] ^= gmul(gen[i + 1], factor);
  }
  return res;
}

// ------------------------------------------------------- the bit stream

class Bits {
  constructor() { this.bits = []; }
  push(value, len) { for (let i = len - 1; i >= 0; i--) this.bits.push((value >> i) & 1); }
  get length() { return this.bits.length; }
}

function codewords(bytes, version) {
  const blocks = RS_BLOCKS_L[version - 1];
  const dataCw = blocks.reduce((n, [c, , d]) => n + c * d, 0);
  const bits = new Bits();
  bits.push(0b0100, 4);                      // byte mode
  bits.push(bytes.length, version < 10 ? 8 : 16);
  for (const b of bytes) bits.push(b & 0xff, 8);
  const capacity = dataCw * 8;
  if (bits.length > capacity) throw new Error("payload too long for this version");
  for (let i = 0; i < 4 && bits.length < capacity; i++) bits.bits.push(0);
  while (bits.length % 8 !== 0) bits.bits.push(0);
  const data = [];
  for (let i = 0; i < bits.length; i += 8) {
    let v = 0;
    for (let j = 0; j < 8; j++) v = (v << 1) | bits.bits[i + j];
    data.push(v);
  }
  const pad = [0xec, 0x11];
  while (data.length < dataCw) data.push(pad[(data.length - bits.length / 8) % 2]);

  // Split into blocks, compute error correction, interleave.
  const dataBlocks = [], ecBlocks = [];
  let off = 0;
  for (const [count, total, dcount] of blocks) {
    for (let i = 0; i < count; i++) {
      const block = data.slice(off, off + dcount);
      off += dcount;
      dataBlocks.push(block);
      ecBlocks.push(rsEncode(block, total - dcount));
    }
  }
  const out = [];
  const maxData = Math.max(...dataBlocks.map((b) => b.length));
  for (let i = 0; i < maxData; i++) for (const b of dataBlocks) if (i < b.length) out.push(b[i]);
  const maxEc = Math.max(...ecBlocks.map((b) => b.length));
  for (let i = 0; i < maxEc; i++) for (const b of ecBlocks) if (i < b.length) out.push(b[i]);
  return out;
}

/** The interleaved codeword stream (data then error correction) that a
 *  version encodes; exposed for tests. */
export const qrCodewords = (bytes, version) => codewords(Array.from(bytes), version);

// ------------------------------------------------------------ the matrix

const FINDER = [
  [1,1,1,1,1,1,1],[1,0,0,0,0,0,1],[1,0,1,1,1,0,1],[1,0,1,1,1,0,1],
  [1,0,1,1,1,0,1],[1,0,0,0,0,0,1],[1,1,1,1,1,1,1],
];

function blankMatrix(version) {
  const size = 17 + 4 * version;
  const m = Array.from({ length: size }, () => new Array(size).fill(null));
  const reserved = Array.from({ length: size }, () => new Array(size).fill(false));

  const put = (r, c, v) => { m[r][c] = v; reserved[r][c] = true; };

  // Finder patterns and separators.
  for (const [r0, c0] of [[0, 0], [0, size - 7], [size - 7, 0]]) {
    for (let r = 0; r < 7; r++) for (let c = 0; c < 7; c++) put(r0 + r, c0 + c, FINDER[r][c]);
    for (let i = -1; i <= 7; i++) {
      for (const [r, c] of [[r0 - 1, c0 + i], [r0 + 7, c0 + i], [r0 + i, c0 - 1], [r0 + i, c0 + 7]]) {
        if (r >= 0 && r < size && c >= 0 && c < size && m[r][c] === null) put(r, c, 0);
      }
    }
  }

  // Alignment patterns.
  const pos = ALIGN_POS[version - 1];
  for (const r0 of pos) for (const c0 of pos) {
    if ((r0 <= 8 && c0 <= 8) || (r0 <= 8 && c0 >= size - 9) || (r0 >= size - 9 && c0 <= 8)) continue;
    for (let dr = -2; dr <= 2; dr++) for (let dc = -2; dc <= 2; dc++) {
      const dark = Math.max(Math.abs(dr), Math.abs(dc)) !== 1;
      put(r0 + dr, c0 + dc, dark ? 1 : 0);
    }
  }

  // Timing patterns.
  for (let i = 8; i < size - 8; i++) {
    if (m[6][i] === null) put(6, i, i % 2 === 0 ? 1 : 0);
    if (m[i][6] === null) put(i, 6, i % 2 === 0 ? 1 : 0);
  }

  // Dark module and the format-information areas.
  put(size - 8, 8, 1);
  for (let i = 0; i <= 8; i++) {
    if (m[8][i] === null) { m[8][i] = 0; reserved[8][i] = true; }
    if (m[i][8] === null) { m[i][8] = 0; reserved[i][8] = true; }
  }
  for (let i = 0; i < 8; i++) {
    if (m[8][size - 1 - i] === null) { m[8][size - 1 - i] = 0; reserved[8][size - 1 - i] = true; }
    if (m[size - 1 - i][8] === null) { m[size - 1 - i][8] = 0; reserved[size - 1 - i][8] = true; }
  }

  // Version information (version 7 and up).
  if (version >= 7) {
    for (let i = 0; i < 6; i++) for (let j = 0; j < 3; j++) {
      m[size - 11 + j][i] = 0; reserved[size - 11 + j][i] = true;
      m[i][size - 11 + j] = 0; reserved[i][size - 11 + j] = true;
    }
  }

  return { m, reserved, size };
}

function placeData(m, reserved, size, data, version) {
  const bits = [];
  for (const b of data) for (let i = 7; i >= 0; i--) bits.push((b >> i) & 1);
  for (let i = 0; i < remainderBits(version); i++) bits.push(0);

  let idx = 0, upward = true;
  for (let col = size - 1; col > 0; col -= 2) {
    if (col === 6) col -= 1; // skip the vertical timing pattern
    for (let k = 0; k < size; k++) {
      const row = upward ? size - 1 - k : k;
      for (const c of [col, col - 1]) {
        if (reserved[row][c]) continue;
        m[row][c] = idx < bits.length ? bits[idx] : 0;
        idx += 1;
      }
    }
    upward = !upward;
  }
}

const MASKS = [
  (r, c) => (r + c) % 2 === 0,
  (r) => r % 2 === 0,
  (r, c) => c % 3 === 0,
  (r, c) => (r + c) % 3 === 0,
  (r, c) => (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0,
  (r, c) => ((r * c) % 2) + ((r * c) % 3) === 0,
  (r, c) => (((r * c) % 2) + ((r * c) % 3)) % 2 === 0,
  (r, c) => (((r + c) % 2) + ((r * c) % 3)) % 2 === 0,
];

function penalty(m, size) {
  let score = 0;
  // Rule 1: runs of five or more.
  for (let i = 0; i < size; i++) {
    for (const line of [m[i], m.map((row) => row[i])]) {
      let run = 1;
      for (let j = 1; j < size; j++) {
        if (line[j] === line[j - 1]) run += 1;
        else { if (run >= 5) score += 3 + (run - 5); run = 1; }
      }
      if (run >= 5) score += 3 + (run - 5);
    }
  }
  // Rule 2: 2x2 blocks.
  for (let r = 0; r < size - 1; r++) for (let c = 0; c < size - 1; c++) {
    const v = m[r][c];
    if (v === m[r][c + 1] && v === m[r + 1][c] && v === m[r + 1][c + 1]) score += 3;
  }
  // Rule 3: finder-like patterns.
  const pat1 = [1,0,1,1,1,0,1,0,0,0,0], pat2 = [0,0,0,0,1,0,1,1,1,0,1];
  const match = (line, i, p) => p.every((v, k) => line[i + k] === v);
  for (let i = 0; i < size; i++) {
    const row = m[i], col = m.map((r) => r[i]);
    for (let j = 0; j + 11 <= size; j++) {
      if (match(row, j, pat1) || match(row, j, pat2)) score += 40;
      if (match(col, j, pat1) || match(col, j, pat2)) score += 40;
    }
  }
  // Rule 4: overall balance.
  const dark = m.flat().filter((v) => v === 1).length;
  const pct = (dark * 100) / (size * size);
  score += 10 * Math.floor(Math.abs(pct - 50) / 5);
  return score;
}

function formatBits(mask) {
  const ecBits = 0b01; // level L
  let value = (ecBits << 3) | mask;
  let rem = value << 10;
  for (let i = 14; i >= 10; i--) if ((rem >> i) & 1) rem ^= 0x537 << (i - 10);
  return ((value << 10) | rem) ^ 0x5412;
}

function versionBits(version) {
  let rem = version << 12;
  for (let i = 17; i >= 12; i--) if ((rem >> i) & 1) rem ^= 0x1f25 << (i - 12);
  return (version << 12) | rem;
}

function applyFormat(m, size, mask) {
  const bits = formatBits(mask);
  const bit = (i) => (bits >> i) & 1;
  // Column 8, top to bottom, then row 8, right to left.
  for (let i = 0; i < 15; i++) {
    const b = bit(i);
    if (i < 6) m[i][8] = b;
    else if (i < 8) m[i + 1][8] = b;
    else m[size - 15 + i][8] = b;
  }
  for (let i = 0; i < 15; i++) {
    const b = bit(i);
    if (i < 8) m[8][size - 1 - i] = b;
    else if (i < 9) m[8][15 - i] = b;
    else m[8][14 - i] = b;
  }
  m[size - 8][8] = 1; // the dark module
}

function applyVersion(m, size, version) {
  if (version < 7) return;
  const bits = versionBits(version);
  for (let i = 0; i < 18; i++) {
    const b = (bits >> i) & 1;
    const r = Math.floor(i / 3), c = i % 3;
    m[size - 11 + c][r] = b;
    m[r][size - 11 + c] = b;
  }
}

/** Encode bytes as a QR matrix: `{ version, size, modules }`, where
 *  `modules[r][c]` is 1 for a dark module. */
export function qrEncodeBytes(bytes, { version = 0, mask = -1 } = {}) {
  const v = version || versionFor(bytes.length);
  if (!v) throw new Error("payload does not fit in a QR code");
  const data = codewords(bytes, v);

  let best = null;
  const masks = mask >= 0 ? [mask] : [0, 1, 2, 3, 4, 5, 6, 7];
  for (const mk of masks) {
    const { m, reserved, size } = blankMatrix(v);
    placeData(m, reserved, size, data, v);
    for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) {
      if (!reserved[r][c] && MASKS[mk](r, c)) m[r][c] ^= 1;
    }
    applyFormat(m, size, mk);
    applyVersion(m, size, v);
    const score = penalty(m, size);
    if (!best || score < best.score) best = { score, modules: m, size, mask: mk };
  }
  return { version: v, size: best.size, modules: best.modules, mask: best.mask };
}

/** Encode ASCII/UTF-8 text as a QR matrix. */
export const qrEncode = (text, opts) =>
  qrEncodeBytes(Array.from(new TextEncoder().encode(text)), opts);

/** Render a matrix as a standalone SVG string. */
export function qrSvg(qr, { scale = 4, border = 4, dark = "#000", light = "#fff" } = {}) {
  const dim = (qr.size + 2 * border) * scale;
  const rects = [];
  for (let r = 0; r < qr.size; r++) {
    for (let c = 0; c < qr.size; c++) {
      if (qr.modules[r][c] !== 1) continue;
      rects.push(
        `<rect x="${(c + border) * scale}" y="${(r + border) * scale}" ` +
        `width="${scale}" height="${scale}"/>`,
      );
    }
  }
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${dim}" height="${dim}" ` +
    `viewBox="0 0 ${dim} ${dim}" shape-rendering="crispEdges">` +
    `<rect width="${dim}" height="${dim}" fill="${light}"/>` +
    `<g fill="${dark}">${rects.join("")}</g></svg>`
  );
}

/** Draw a matrix into a canvas element. */
export function qrDraw(canvas, qr, { scale = 4, border = 4, dark = "#000", light = "#fff" } = {}) {
  const dim = (qr.size + 2 * border) * scale;
  canvas.width = dim;
  canvas.height = dim;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = light;
  ctx.fillRect(0, 0, dim, dim);
  ctx.fillStyle = dark;
  for (let r = 0; r < qr.size; r++) for (let c = 0; c < qr.size; c++) {
    if (qr.modules[r][c] === 1) ctx.fillRect((c + border) * scale, (r + border) * scale, scale, scale);
  }
  return canvas;
}

/** Export a QR matrix as a PNG blob. */
export async function qrPng(qr, { scale = 4, border = 4, dark = "#000", light = "#fff" } = {}) {
  const dim = (qr.size + 2 * border) * scale;
  const canvas = document.createElement("canvas");
  canvas.width = dim;
  canvas.height = dim;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = light;
  ctx.fillRect(0, 0, dim, dim);
  ctx.fillStyle = dark;
  for (let r = 0; r < qr.size; r++) for (let c = 0; c < qr.size; c++) {
    if (qr.modules[r][c] === 1) ctx.fillRect((c + border) * scale, (r + border) * scale, scale, scale);
  }
  return new Promise((resolve) => canvas.toBlob(resolve, "image/png"));
}

/** Copy a QR matrix to clipboard as PNG. */
export async function qrCopyPng(qr, opts = {}) {
  const blob = await qrPng(qr, opts);
  if (!navigator.clipboard || !navigator.clipboard.write) throw new Error("clipboard not available");
  await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })]);
}

/** A compact fingerprint of a matrix, for tests. */
export function qrFingerprint(qr) {
  let h = 0x811c9dc5;
  for (const row of qr.modules) for (const v of row) {
    h ^= v & 1;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return `${qr.version}-${qr.mask}-${h.toString(16).padStart(8, "0")}`;
}
