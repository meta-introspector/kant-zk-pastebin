#!/usr/bin/env node
// kant-join.mjs — minimal kant room client: join a room, say something, read the transcript.
//
// Zero dependencies. Implements the kant-zk wire format directly:
//   room   = hex(witness(secret))            (FNV-1a based 32-byte digest)
//   kzchat = hex envelope: tag, room, sender, seq, body, self-witness
//   POST   {relay}/room/{room}  header x-kant-invite|kzpass, body = one hex line
//   GET    {relay}/room/{room}?cursor=N
//
// Usage:
//   node kant-join.mjs <relay-url> <secret-hex> "hello from me"        # post + read
//   node kant-join.mjs <relay-url> <secret-hex> --read                 # read only
//   node kant-join.mjs <relay-url> <secret-hex> --invite [limit]       # mint invite/kzpass
//
// Example (the demo room — its secret was already public in the repo):
//   node kant-join.mjs https://kant-relay-v1.purple-fire-b881.workers.dev \
//     62651636c8b5344a09507cc02b35df991378c33ec70e0ef96e738ee9223db97e "hi!"

const MASK64 = (1n << 64n) - 1n;
const FNV_OFFSET = 14695981039346656037n, FNV_PRIME = 1099511628211n;
const utf8 = (s) => [...new TextEncoder().encode(s)];
// Array.from, not .map: on a Uint8Array, .map coerces the hex strings back into
// numbers ("9c" -> NaN -> 0) and silently corrupts the field.
const hexEncode = (b) => Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
const hexDecode = (s) => s.match(/../g).map((h) => parseInt(h, 16));

function fnv1a(bytes) {
  let h = FNV_OFFSET;
  for (const b of bytes) h = ((h ^ BigInt(b & 0xff)) * FNV_PRIME) & MASK64;
  return h;
}
// 32-byte digest: four salted FNV-1a rounds (the Lean-proved `Kant.Bytes.digest`).
function digest(bytes) {
  const out = [];
  for (let i = 0; i < 4; i++) {
    const h = fnv1a([i, ...bytes]);
    for (let j = 7; j >= 0; j--) out.push(Number((h >> BigInt(8 * j)) & 0xffn));
  }
  return out;
}
const witness = (b) => hexEncode(digest(b));          // the self-certifying check value
const roomOf = (secret) => witness(secret);           // room name = witness of the secret

// ---- envelopes (hex fields joined by ':') --------------------------------
const env = (tag, fields) => hexEncode(utf8(tag)) + fields.map(hexEncode).map((h) => ":" + h).join("");
const natBytes = (n) => { const o = []; do { o.unshift(n % 256); n = Math.floor(n / 256); } while (n > 0); return o; };

function kzchat(room, sender, seq, text) {
  const fields = [utf8(room), utf8(sender), natBytes(seq), utf8(text)];
  return env("kzchat", [...fields, hexDecode(witness([fields[0], 0, fields[1], 0, fields[2], 0, fields[3]].flat()))]);
}
function kzinvite(relay, secret, peer) {
  return env("kzinvite", [utf8(relay), secret, utf8(peer)]);
}
// kzpass = invite + limit + 16-byte id + 32-byte sig = witness(secret ‖ 0 ‖ id ‖ 0 ‖ limit)
// field order matters: kzpass:<relay>:<secret>:<peer>[:<addr>…]:<limit>:<id>:<sig>
function kzpass(relay, secret, peer, limit) {
  const id = crypto.getRandomValues(new Uint8Array(16));
  const sig = hexDecode(witness([...secret, 0, ...id, 0, ...natBytes(limit)]));
  return env("kzpass", [utf8(relay), secret, utf8(peer), natBytes(limit), id, sig]);
}

// ---- main -----------------------------------------------------------------
const [relay, secretHex, ...rest] = process.argv.slice(2);
if (!relay || !secretHex) {
  console.error("usage: node kant-join.mjs <relay-url> <secret-hex> [\"message\" | --read | --invite [limit]]");
  process.exit(1);
}
const secret = hexDecode(secretHex.replace(/^0x/, ""));
const room = roomOf(secret);
const peer = "peer-" + Math.random().toString(36).slice(2, 8);
console.log(`room  ${room}\nrelay ${relay}\npeer  ${peer}`);

const arg = rest[0] ?? "hello from kant-join.mjs";
if (arg === "--invite") {
  const limit = Number(rest[1] ?? 0);
  console.log(limit > 0 ? `kzpass (limit ${limit}):\n${kzpass(relay, secret, peer, limit)}`
                        : `kzinvite (unlimited):\n${kzinvite(relay, secret, peer)}`);
  console.log(`browser link: ${relay}/#${kzinvite(relay, secret, peer)}`);
} else if (arg !== "--read") {
  const line = kzchat(room, peer, Math.floor(Date.now() / 1000), arg);
  const r = await fetch(`${relay}/room/${room}`, {
    method: "POST",
    headers: { "content-type": "text/plain", "x-kant-invite": kzinvite(relay, secret, peer) },
    body: line,
  });
  console.log("POST", r.status, await r.text());
}

const g = await fetch(`${relay}/room/${room}?cursor=0`);
const out = await g.json();
console.log("GET ", g.status, `cursor=${out.cursor} lines=${out.lines?.length}`);
for (const l of out.lines ?? []) {
  const f = l.split(":").map(hexDecode), tag = String.fromCharCode(...f[0]);
  if (tag === "kzchat") console.log(`  [${String.fromCharCode(...f[2])}] ${new TextDecoder().decode(Uint8Array.from(f[4]))}`);
  else console.log(`  <${tag} line>`);
}
