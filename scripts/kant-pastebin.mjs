// kant-pastebin.mjs — a pastebin is just a place where you can put one
// text and get one URL, and later get the text back.
//
// The Kant pastebin server is one such place, but so is any other: what
// counts is the pair of verbs, put and get, not whose server it runs on.
// This module speaks the Kant pastebin's HTTP API (POST /paste, GET
// /raw/{id}, GET /api/search) against any base URL — the live service at
// solana.solfunmeme.com/pastebin, a local `nix run`, or any fork — and
// also works with no server at all, against a UUCP spool directory on
// disk: the same directory the live service stores its pastes in.
//
// Nothing here knows about rooms, invitations or chat lines.  Callers
// (kant-cli.mjs `pastebinit` / `accept`, and whatever comes next —
// twitter, discord, telegram, gists, QR codes) put one line of text in
// and take one line of text out; the meaning of the line is theirs.
//
//   import { pasteApi, pasteSpool } from "./kant-pastebin.mjs";
//
//   const api = pasteApi("https://solana.solfunmeme.com/pastebin");
//   const { url } = await api.put("hello");     // -> { id, cid, url, ... }
//   await api.get(url);                          // -> "hello"
//   await api.search("hello");                   // -> [{ id, excerpt, ... }]
//
//   const spool = pasteSpool("/var/spool/uucp/pastebin");
//   spool.list();                                 // -> [{ id, title, ... }]
//   spool.read(id);                               // -> "the paste's text"
//
// Run the checks:  node web/pastebin-test.mjs

import { readFileSync, existsSync } from "node:fs";

// ------------------------------------------------------------- utilities

/** Join a base URL and a path without doubling or losing a slash. */
export function joinUrl(base, path) {
  return `${String(base).replace(/\/+$/, "")}/${String(path).replace(/^\/+/, "")}`;
}

/** A paste URL names a paste on some pastebin: <backend>/paste/<id>,
 *  <backend>/raw/<id>, or a bare id.  The backend is everything before
 *  the last /paste/ or /raw/ segment, so it may itself contain path
 *  segments (https://host/pastebin/paste/<id>).  Returns null for
 *  anything that is not one of those. */
export function parsePasteUrl(url) {
  const s = String(url).trim();
  let m = s.match(/^([a-z][a-z0-9+.-]*:\/\/.+?)\/(?:paste|raw)\/([^/?#]+)/i);
  if (m) return { backend: m[1], id: m[2], raw: /\/raw\//.test(s) };
  m = s.match(/^(?:\/\/[^/]+)?(\/.+?)\/(?:paste|raw)\/([^/?#]+)/);
  if (m) return { backend: m[1], id: m[2], raw: /\/raw\//.test(s) };
  m = s.match(/^[a-z][a-z0-9+.-]*:\/\/[^/]+\/([^/?#]+)/i);
  if (m && !/^(?:paste|raw)$/i.test(m[1])) {
    return { backend: s.slice(0, s.indexOf(`/${m[1]}`)), id: m[1], raw: false };
  }
  if (/^[A-Za-z0-9._-]+$/.test(s) && s.length >= 8) return { backend: "", id: s, raw: false };
  return null;
}

/** Is this text a paste URL?  (For `accept`-style flows: given any line of
 *  text, was it a paste reference?) */
export const isPasteUrl = (s) => parsePasteUrl(String(s).trim()) !== null;

/** The server wraps every paste: a header block (`--- id ---`, Title,
 *  Description, ..., Sheaf) at the front of the stored file, and an
 *  HTML-escaped RDFa sheaf div (`&lt;div typeof="erdfa:SheafSection...`)
 *  at the end of what /raw returns.  Neither is the paste's text.
 *  This strips both, leaving the content as it was posted.  Text that
 *  carries neither wrapper comes back unchanged. */
export function unwrapPaste(text) {
  let t = String(text);
  // the RDFa footer: everything from the escaped sheaf div to the end
  const div = t.indexOf('&lt;div typeof="erdfa:SheafSection');
  if (div !== -1) t = t.slice(0, div);
  // the stored-file header: `--- <id> ---` through the blank line after
  const m = t.match(/^--- [^\n]*---\n(?:[^\n]*\n)*?\n/);
  if (m) t = t.slice(m[0].length);
  return t.replace(/\s+$/, "").replace(/^\n+/, "");
}

// ------------------------------------------------------------------- API

/** A client for one pastebin over HTTP.  `backend` is the base URL of a
 *  Kant pastebin service (the part before `/paste`). */
export function pasteApi(backend, { fetch: fetchNow = fetch, author = null } = {}) {
  const base = String(backend).replace(/\/+$/, "");
  const idUrl = (id) => joinUrl(base, `paste/${encodeURIComponent(id)}`);
  const rawUrl = (id) => joinUrl(base, `raw/${encodeURIComponent(id)}`);

  /** Put one text.  Returns the server's Response record: id, cid,
   *  witness, url, permalink, and — on a fresh post — uucp_path.  The
   *  server content-dedupes: posting the same text again returns the
   *  same paste (url names the slug id, permalink names the CID). */
  async function put(text, { title, description, keywords, replyTo } = {}) {
    const body = { content: String(text) };
    if (title != null) body.title = title;
    if (description != null) body.description = description;
    if (keywords != null) body.keywords = keywords;
    if (replyTo != null) body.reply_to = replyTo;
    const r = await fetchNow(joinUrl(base, "paste"), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!r.ok) throw new Error(`paste POST failed (${r.status}): ${await safeText(r)}`);
    const res = await r.json();
    res.url = absolute(res.url, base);
    res.permalink = absolute(res.permalink, base);
    return res;
  }

  /** Get one paste's raw text by id, paste URL, or raw URL, with the
   *  server's wrappers (header block, RDFa footer) stripped. */
  async function get(urlOrId) {
    const p = parsePasteUrl(urlOrId);
    const id = p ? p.id : String(urlOrId);
    const r = await fetchNow(p && p.raw ? urlOrId : rawUrl(id));
    if (!r.ok) throw new Error(`paste GET failed (${r.status}): ${await safeText(r)}`);
    return unwrapPaste(await r.text());
  }

  /** Full-text search.  Returns the server's result records.  (Spaces
   *  are sent as %20, not +: the server does not decode + in query
   *  values, and a + would be searched for literally.) */
  async function search(q, { limit = 50, mode, scope } = {}) {
    let qs = `q=${encodeURIComponent(String(q))}`;
    if (limit != null) qs += `&limit=${limit}`;
    if (mode != null) qs += `&mode=${encodeURIComponent(mode)}`;
    if (scope != null) qs += `&scope=${encodeURIComponent(scope)}`;
    const r = await fetchNow(`${joinUrl(base, "api/search")}?${qs}`);
    if (!r.ok) throw new Error(`paste search failed (${r.status}): ${await safeText(r)}`);
    const out = await r.json();
    return out.results ?? [];
  }

  /** Ask the pastebin whether it is there.  Returns its health record
   *  (or null when the endpoint is missing — not every pastebin has one). */
  async function health() {
    try {
      const r = await fetchNow(joinUrl(base, "health"));
      if (!r.ok) return null;
      return await r.json();
    } catch { return null; }
  }

  return { put, get, search, health, idUrl, rawUrl };
}

// ------------------------------------------------------------------ spool

/** A client for one pastebin's UUCP spool directory — the same directory
 *  the Kant pastebin service reads and writes its pastes in.  This is the
 *  "read and use the existing pastebin dir" path: no server, no network,
 *  just the files.  `read` resolves the .cid alias files the server's
 *  dedup path writes, so a CID permalink names a paste here too. */
export function pasteSpool(dir) {
  const dirOf = () => String(dir).replace(/\/+$/, "");

  /** The spool index, newest first.  Each line of index.jsonl is one
   *  paste record: id, title, description, keywords, cid, witness,
   *  timestamp, filename, size, uucp_path. */
  function list({ limit = 0, since } = {}) {
    const idx = `${dirOf()}/index.jsonl`;
    if (!existsSync(idx)) return [];
    const out = [];
    const lines = readFileSync(idx, "utf8").split("\n");
    for (let n = lines.length - 1; n >= 0; n -= 1) {
      let e; try { e = JSON.parse(lines[n]); } catch { continue; }
      if (since && (e.timestamp ?? "") < since) continue;
      out.push(e);
      if (limit && out.length >= limit) break;
    }
    return out;
  }

  /** Resolve a CID permalink to the real paste id: a `<bafk-cid>.cid`
   *  file holds the id of the paste that content aliases. */
  function resolve(id) {
    const cidFile = `${dirOf()}/${id}.cid`;
    if (existsSync(cidFile)) {
      const real = (readFileSync(cidFile, "utf8") || "").trim();
      if (real) return real;
    }
    return id;
  }

  /** Read one paste's raw text by id (slug or CID permalink), with the
   *  stored header block stripped.  Returns null when there is no such
   *  paste. */
  function read(id) {
    const real = resolve(id);
    for (const name of [`${real}.txt`, real]) {
      const p = `${dirOf()}/${name}`;
      if (existsSync(p)) {
        try { return unwrapPaste(readFileSync(p, "utf8")); } catch { /* keep trying */ }
      }
    }
    // Fall back to the index's uucp_path (it may point outside the dir).
    const e = list().find((x) => x.id === real);
    if (e && e.uucp_path && existsSync(e.uucp_path)) {
      try { return unwrapPaste(readFileSync(e.uucp_path, "utf8")); } catch { /* nothing */ }
    }
    return null;
  }

  /** Take in pastes from the spool: walk the index from the end and
   *  hand each paste's text to `take`, newest first, until `take` returns
   *  something other than null (that value is the result), or `look`
   *  pastes have been tried (default 50).  This is the spool side of
   *  `accept`: the caller decides what a loadable paste looks like. */
  function take(takeFn, { look = 50, since } = {}) {
    const entries = list({ since });
    const tried = Math.min(look, entries.length);
    for (let n = 0; n < tried; n += 1) {
      const e = entries[n];
      const path = e.uucp_path ?? (e.filename ? `${dirOf()}/${e.filename}` : null);
      if (!path) continue;
      let text; try { text = readFileSync(path, "utf8"); } catch { continue; }
      const got = takeFn(text, e);
      if (got !== null && got !== undefined) return { value: got, entry: e, tried: n + 1 };
    }
    return null;
  }

  return { list, read, resolve, take, dir: dirOf() };
}

// --------------------------------------------------------------- helpers

async function safeText(r) {
  try { return (await r.text()).slice(0, 200); } catch { return ""; }
}

function absolute(u, base) {
  if (!u) return u;
  if (/^https?:\/\//.test(u)) return u;
  return joinUrl(base, u);
}
