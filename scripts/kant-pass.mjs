// Limited invitations — kzpass.
//
// A kzinvite is a bearer secret: anyone who has it can post forever.  A
// kzpass is the same invitation plus a spending limit:
//
//   kzpass = invite fields (relay, secret, peer, addrs…)
//          + limit (one-time = 1, group = N)
//          + id     (16 fresh random bytes, names the pass)
//          + sig    (witness(secret ‖ id ‖ limit), 32 bytes)
//
// The signature is derived from the room secret, so only someone who
// knows the secret can mint passes — passing a kzpass around does not
// let its holder mint more.  The relay counts POSTs per pass id and
// refuses once the limit is spent.  The secret inside is the room
// secret, so a kzpass holder is also a room member (they can read the
// room and verify witnesses); what the limit caps is posting.
//
// Encoding is the same hex envelope as every other kant code:
//   kzpass:<relay-hex>:<secret-hex>:<peer-hex>[:<addr-hex>…]:<limit-hex>:<id-hex>:<sig-hex>

import {
  TAG_INVITE, invite, toInvite, ofInvite, copyInvite, pasteInvite,
  freshSecret, roomOf,
} from "./kant-net.mjs";
import { envelopeEncode, envelopeDecode, witness, shareUrl } from "./kantzk.mjs";

export const TAG_PASS = Array.from("kzpass").map((c) => c.charCodeAt(0));

/** Fields of a pass: the invite, then limit, id, sig. */
export function ofPass(p) {
  const fields = ofInvite(p).fields;   // relay, secret, peer, addrs…
  return {
    tag: TAG_PASS,
    fields: [...fields, natField(p.limit), p.id, p.sig],
  };
}

/** Mint a pass for an invite.  Needs the secret (already in the invite). */
export function mintPass(inv, limit = 1) {
  const id = freshSecret(16);
  const sig = passSig(inv.secret, id, limit);
  return { relay: inv.relay, secret: inv.secret, peer: inv.peer, addrs: inv.addrs ?? [], limit, id, sig };
}

/** The signature a pass carries: derived from the room secret. */
export function passSig(secret, id, limit) {
  const sep = [0];
  return Array.from(witnessBytes([...secret, ...sep, ...id, ...sep, ...natField(limit)]));
}

/** Does a pass prove it was minted from `secret`? */
export function passOk(pass, secret) {
  return bytesEq(pass.sig, passSig(secret, pass.id, pass.limit));
}

/** The room a pass opens (same as the invite's). */
export const passRoom = (p) => roomOf(p.secret);

/** The printed code.  A pass holder (limit > 0) gets a kzpass; a bare
 *  invite (limit 0) gets its own kzinvite code — never a crash. */
export const copyPass = (p) =>
  envelopeEncode(p.limit > 0 ? ofPass(p) : ofInvite(p));

/** The same pass as a link (`#kzpass…` fragment). */
export const passUrl = (base, p) => shareUrl(base, ofPass(p));

/** Read a printed code.  Accepts a kzpass (limited) or a kzinvite (unlimited). */
export function pastePass(s) {
  const e = envelopeDecode(s);
  if (!e) return null;
  if (bytesEq(e.tag, TAG_PASS)) return toPass(e);
  const inv = toInvite(e);
  return inv ? { ...inv, limit: 0 } : null;   // 0 = unlimited (owner's invite)
}

function toPass(e) {
  if (!e || !bytesEq(e.tag, TAG_PASS) || e.fields.length < 6) return null;
  const inv = toInvite({ tag: TAG_INVITE, fields: e.fields.slice(0, e.fields.length - 3) });
  if (!inv) return null;
  const limitF = e.fields[e.fields.length - 3];
  const id = e.fields[e.fields.length - 2];
  const sig = e.fields[e.fields.length - 1];
  const limit = bytesBEToNat(limitF);
  if (!Number.isInteger(limit) || limit < 1 || !Array.isArray(id) || id.length !== 16 ||
      !Array.isArray(sig) || sig.length !== 32) return null;
  return { ...inv, limit, id, sig };
}

// ------------------------------------------------------------- internals

const natField = (n) => {
  const out = [];
  let x = n;
  do { out.unshift(x % 256); x = Math.floor(x / 256); } while (x > 0);
  return out;
};

const bytesBEToNat = (b) => b.reduce((a, x) => a * 256 + x, 0);

const bytesEq = (a, b) => Array.isArray(a) && Array.isArray(b) &&
  a.length === b.length && a.every((x, i) => x === b[i]);

// witness() returns hex; the pass sig needs raw bytes.
function witnessBytes(bytes) {
  const hex = witness(bytes);
  const out = [];
  for (let i = 0; i < hex.length; i += 2) out.push(parseInt(hex.slice(i, i + 2), 16));
  return out;
}
