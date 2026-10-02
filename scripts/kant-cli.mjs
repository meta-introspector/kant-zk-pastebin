#!/usr/bin/env node
/**
 * kant-cli — the kant-zk-pastebin client for a terminal, and for agents.
 *
 * Everything the browser client does, done from a shell, over exactly the
 * requests the browser makes.  Each request can be printed as the `curl`
 * command that makes it (`--print-curl`), or actually made by `curl`
 * (`--transport curl`), and the results are the same either way: that is the
 * content of `RequestProject/Kant/Cli.lean`.
 *
 * The page is static.  Two agents are assumed to have some other channel —
 * Telegram, Discord, a tweet, a pastebin — over which they can send each
 * other one line of text.  That line is the link: the site, and after the
 * `#`, the room.  Nothing after the `#` ever reaches the host.
 *
 *   # agent A
 *   node scripts/kant-cli.mjs --state a.json open --relay http://127.0.0.1:8787
 *   node scripts/kant-cli.mjs --state a.json link           # send this in the chat
 *   node scripts/kant-cli.mjs --state a.json say 'hello from the terminal'
 *
 *   # agent B, having been sent the link in some chat window
 *   node scripts/kant-cli.mjs --state b.json join 'hey, come in here: <link> .'
 *   node scripts/kant-cli.mjs --state b.json read
 *   node scripts/kant-cli.mjs --state b.json say 'hello back'
 *
 *   # the chat window can be the Kant pastebin itself: agent A posts the
 *   # link there, agent B takes the latest paste out of the UUCP spool
 *   node scripts/kant-cli.mjs --state a.json pastebinit
 *   node scripts/kant-cli.mjs --state b.json accept            # latest in the spool
 *   node scripts/kant-cli.mjs --state b.json accept <url>     # or a paste URL
 *
 *   # and the same thing with nothing but curl
 *   node scripts/kant-cli.mjs --state a.json curl read
 *   node scripts/kant-cli.mjs --state a.json curl say 'hello from the terminal'
 *
 * Options
 *   --state <file>       where this client keeps its state (default kant-cli.json)
 *   --json               print machine-readable JSON (for agents)
 *   --transport fetch|curl   how requests are made (default fetch)
 *   --print-curl         print the curl command for every request made
 *   --origin <url>       the site the links point at (default from kant.config)
 *   --config <file>      the deployment configuration (default web/kant.config)
 *   --name <id>          this client's peer name (default a random one)
 *   --spool <dir>        the UUCP spool `accept` looks in (default $UUCP_SPOOL
 *                        or /var/spool/uucp/pastebin, where the live
 *                        kant-pastebin service stores its pastes)
 *   --backend <url>      the pastebin `pastebinit` posts to
 *                        (default solana.solfunmeme.com/pastebin)
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { basename } from "node:path";

/** Just enough MIME to name a file honestly in the manifest.  The manifest
 *  commits to this string, so it is part of what a peer checks — guessing
 *  octet-stream for everything would be accurate but useless. */
const MIME = {
  txt: "text/plain", md: "text/markdown", html: "text/html",
  css: "text/css", csv: "text/csv", json: "application/json",
  js: "text/javascript", mjs: "text/javascript",
  wasm: "application/wasm", pdf: "application/pdf",
  png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif",
  svg: "image/svg+xml", webp: "image/webp", ico: "image/x-icon",
  zip: "application/zip", gz: "application/gzip", tar: "application/x-tar",
  mp3: "audio/mpeg", wav: "audio/wav", mp4: "video/mp4", webm: "video/webm",
  lean: "text/plain", rs: "text/plain", ts: "text/plain",
};
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import * as C from "../web/kant-cli.mjs";
import * as P from "../web/kant-pastebin.mjs";
import { pastebinChannel } from "../web/kant-share.mjs";
import { parseConfig, DEFAULT_CONFIG } from "../web/kant-site.mjs";
import { classify, describe } from "../web/kant-carddebug.mjs";

// ------------------------------------------------------------- arguments

const argv = process.argv.slice(2);
const opts = {
  state: "kant-cli.json",
  json: false,
  transport: "fetch",
  printCurl: false,
  origin: null,
  // Config lookup order: $KANT_CONFIG, next to the running file (bundled
  // CLI), the repository checkout (../web/), then built-in defaults.  The
  // bundled single-file build keeps this working wherever the file lands.
  config: null,
  name: null,
  relay: null,
  wait: 0,
  spool: process.env.UUCP_SPOOL ?? "/var/spool/uucp/pastebin",
  backend: "solana.solfunmeme.com/pastebin",
};
const rest = [];
for (let i = 0; i < argv.length; i += 1) {
  const tok = argv[i];
  const take = () => argv[(i += 1)];
  switch (tok) {
    case "--state": opts.state = take(); break;
    case "--json": opts.json = true; break;
    case "--transport": opts.transport = take(); break;
    case "--print-curl": opts.printCurl = true; break;
    case "--origin": opts.origin = take(); break;
    case "--config": opts.config = take(); break;
    case "--name": opts.name = take(); break;
    case "--relay": opts.relay = take(); break;
    case "--wait": opts.wait = Number(take()) || 0; break;
    case "--spool": opts.spool = take(); break;
    case "--backend": opts.backend = take(); break;
    case "--out": opts.out = take(); break;
    case "-h": case "--help": rest.push("help"); break;
    case "-V": case "--version":
      console.log(process.env.KANT_CLI_VERSION ?? "0.0.0-dev");
      process.exit(0);
      break;
    default: rest.push(tok);
  }
}

const cfg = (() => {
  const candidates = [
    process.env.KANT_CONFIG,
    new URL("kant.config", import.meta.url).pathname,
    new URL("../kant.config", import.meta.url).pathname,
    new URL("../web/kant.config", import.meta.url).pathname,
  ].filter(Boolean);
  const hit = candidates.find((p) => existsSync(p));
  const base = hit
    ? (parseConfig(readFileSync(hit, "utf8")) ?? DEFAULT_CONFIG)
    : DEFAULT_CONFIG;
  return opts.origin ? { ...base, origin: opts.origin } : base;
})();

// ----------------------------------------------------------- the state

const blank = () => ({
  self: opts.name ?? `agent-${randomBytes(4).toString("hex")}`,
  relay: opts.relay ?? "",
  secret: "",
  seq: 0,
  cursor: 0,
  lines: [],
});

function load() {
  if (!existsSync(opts.state)) return blank();
  const raw = JSON.parse(readFileSync(opts.state, "utf8"));
  return { ...blank(), ...raw };
}

const save = (st) => writeFileSync(opts.state, `${JSON.stringify(st, null, 2)}\n`);

/** The state file keeps the secret as hex; the client works in bytes. */
const client = (st) => ({
  self: st.self,
  relay: st.relay,
  secret: st.secret ? C.hexDecode(st.secret) : [],
  seq: st.seq,
  cursor: st.cursor,
  lines: st.lines,
});

const store = (st, c) => {
  st.self = c.self;
  st.relay = c.relay;
  st.secret = C.hexEncode(c.secret);
  st.seq = c.seq;
  st.cursor = c.cursor;
  st.lines = c.lines;
  return st;
};

// -------------------------------------------------------- the transport

/** Make one request, by `fetch` or by handing the very same arguments to
 *  the `curl` binary.  Both paths use `curlArgv`, so what runs is what
 *  `--print-curl` prints. */
async function send(req) {
  if (opts.printCurl) console.error(`$ ${C.curlLine(req)}`);
  if (opts.transport === "curl") {
    const args = C.curlArgv(req).slice(1);
    const out = spawnSync("curl", args, { encoding: "binary", maxBuffer: 64 * 1024 * 1024 });
    if (out.status !== 0) {
      throw new Error(`curl failed (${out.status}): ${String(out.stderr).trim()}`);
    }
    return out.stdout;
  }
  const r = await fetch(req.url, req.method === "post"
    ? { method: "POST", headers: { "content-type": req.binary ? "application/octet-stream" : "text/plain" },
        body: req.binary ? req.body : req.body }
    : undefined);
  if (!r.ok) throw new Error(`relay ${req.method} failed: ${r.status}`);
  return r.text();
}

/** One request whose *body or result* is binary — a chunk, or a file.  Kept
 *  apart from `send` because that one round-trips text, and a chunk pushed
 *  through it would come back as a UTF-8 string with every byte above 0x7f
 *  replaced.  A file dropped over `--transport curl` would then arrive
 *  corrupt and fail the witness check on every chunk after the first. */
async function sendBinary(req) {
  if (opts.transport === "curl") {
    const args = C.curlArgv(req).slice(1);
    const out = spawnSync("curl", args, {
      encoding: "buffer", maxBuffer: 64 * 1024 * 1024,
    });
    if (out.status !== 0) {
      throw new Error(`curl failed (${out.status}): ${String(out.stderr ?? "").trim()}`);
    }
    return new Uint8Array(out.stdout);
  }
  const r = await fetch(req.url, req.method === "post"
    ? { method: "POST", headers: { "content-type": "application/octet-stream" },
        body: req.body }
    : undefined);
  if (!r.ok) throw new Error(`relay ${req.method} failed: ${r.status}`);
  return new Uint8Array(await r.arrayBuffer());
}

const sendJson = async (req) => JSON.parse(await send(req));

// ---------------------------------------------------------- the commands

const out = (human, data) => {
  if (opts.json) console.log(JSON.stringify(data, null, 2));
  else console.log(human);
};

const needRoom = (c) => {
  if (!c.secret.length) {
    console.error("no room yet: run `open --relay <url>` or `join <link>` first");
    process.exit(2);
  }
};

/** Take in whatever a text carries — a whole conversation in a bag, or an
 *  invitation to join a room — wherever in the text it happens to be.  On
 *  success the state is saved and a report printed; the return is the client
 *  as it now stands (joined or absorbed), or `"nothing"` when no loadable
 *  line is in there. */
function loadText(st, c, text) {
  const what = C.loadUrl(text);
  if (what.kind === "bag") {
    // A conversation carried in the link itself: no relay in it at all.
    const taken = C.absorb(c, what.messages.map((m) => C.printMsg(m)));
    save(store(st, c));
    out(`took ${taken} line(s) out of the link`, {
      ok: true, kind: "bag", taken, page: C.pageOf(text.trim()),
      view: C.view(c).map((m) => ({ sender: m.sender, seq: m.seq, text: C.msgText(m) })),
    });
    return c;
  }
  if (what.kind === "invitation") {
    const joined = C.joinText(c.self, text);
    if (!joined) return "nothing";
    joined.self = c.self;
    save(store(st, joined));
    out(`joined room ${C.clientRoom(joined)}\nrelay ${joined.relay || "(none)"}`, {
      ok: true, room: C.clientRoom(joined), relay: joined.relay, self: joined.self,
      page: C.pageOf(text.trim()),
    });
    return joined;
  }
  return "nothing";
};

function usage() {
  console.log(`kant-cli — the kant-zk-pastebin client for a terminal

  open --relay <url>     open a fresh room on a relay
  link                   the link to send in any chat window
  invite                 the bare invitation code
  room                   the room this client is in
  whoami                 name, relay, room, counters
  join <text>            join the room named by a pasted message or link
  load <url>             load a URL: join a room, or take in a conversation
  pastebinit [text]      post to the pastebin (default: this client's link;
  pastebinit --file <f>    or the given text, a file, or stdin with '-')
  accept [url]           take in a paste: the URL pastebinit printed, or
                         with no argument the latest paste in the spool
  say <text>             say something in the room
  read                   read the room and print the conversation
  drop <file>            encrypt a file for the room and announce it;
                         every chunk is pinned on the relay under its witness
                         and only ciphertext leaves this machine
  files                  the files announced in the room
  fetch <n>              fetch and decrypt file n, writing it to --out
                         (default: the announced name in the cwd)
  quote <n> <text>        reply to file n, quoting it back into the room
  bag                    the whole conversation as one link (no relay needed)
  watch [--wait 25]      keep reading until interrupted
  health                 ask the relay whether it is there
  curl read|say <text>|link   print the curl command instead of running it

Options: --state <file> --json --transport fetch|curl --print-curl
         --origin <url> --config <file> --name <id> --relay <url>
         --spool <dir> --backend <url> --out <path>`);
}

async function main() {
  const cmd = rest[0] ?? "help";
  const st = load();
  const c = client(st);

  switch (cmd) {
    case "help": usage(); return;

    case "open": {
      const relay = opts.relay ?? rest[1] ?? c.relay;
      if (!relay) {
        console.error("open needs a relay: --relay http://127.0.0.1:8787");
        process.exit(2);
      }
      const fresh = C.openRoom(c.self, relay, Array.from(randomBytes(32)));
      save(store(st, fresh));
      const link = C.clientLink(cfg, fresh);
      out(`room ${C.clientRoom(fresh)}\nlink ${link}`, {
        ok: true, self: fresh.self, relay, room: C.clientRoom(fresh), link,
        invite: C.copyInvite(C.clientInvite(fresh)), page: C.pageOf(link),
      });
      return;
    }

    case "link": {
      needRoom(c);
      const link = C.clientLink(cfg, c);
      out(link, { ok: true, link, page: C.pageOf(link), room: C.clientRoom(c) });
      return;
    }

    case "invite": {
      needRoom(c);
      const code = C.copyInvite(C.clientInvite(c));
      out(code, { ok: true, invite: code, room: C.clientRoom(c) });
      return;
    }

    case "room": {
      needRoom(c);
      out(C.clientRoom(c), { ok: true, room: C.clientRoom(c) });
      return;
    }

    case "whoami": {
      out(`name  ${c.self}\nrelay ${c.relay || "(none)"}\nroom  ${
        c.secret.length ? C.clientRoom(c) : "(none)"}\nseq   ${c.seq}\ncursor ${c.cursor}`, {
        ok: true, self: c.self, relay: c.relay,
        room: c.secret.length ? C.clientRoom(c) : "", seq: c.seq, cursor: c.cursor,
        held: c.lines.length,
      });
      return;
    }

    case "bag": {
      needRoom(c);
      const url = C.clientBagUrl(cfg, c);
      out(url, {
        ok: true, bagUrl: url, bag: C.packBag(C.view(c)), page: C.pageOf(url),
        messages: C.view(c).map((m) => ({ sender: m.sender, seq: m.seq, text: C.msgText(m) })),
      });
      return;
    }

    case "load": {
      const text = rest.slice(1).join(" ");
      if (!text) { console.error("load needs a URL or the text somebody sent you"); process.exit(2); }
      const now = loadText(st, c, text);
      if (now === "nothing") {
        const named = describe(classify(text.trim()));
        console.error(`nothing this client can load: ${named.kind}` +
          (named.kind === "page" ? ` ${named.addr}` : ""));
        if (opts.json) console.log(JSON.stringify({ ok: false, kind: "nothing", reason: named },
          null, 2));
        process.exit(1);
      }
      return;
    }

    case "pastebinit": {
      // What to post: the given text, a file, stdin (an explicit `-`), or by
      // default this client's link — the one line the other agent needs.
      let content, what = "text";
      const args = rest.slice(1);
      if (args[0] === "--file") {
        if (!args[1]) { console.error("pastebinit --file needs a path"); process.exit(2); }
        content = readFileSync(args[1], "utf8"); what = args[1];
      } else if (args[0] === "-") {
        content = readFileSync(0, "utf8"); what = "stdin";
      } else if (args.length) {
        content = args.join(" ");
      } else {
        needRoom(c);
        content = `${C.clientLink(cfg, c)}\n`; what = "link";
      }
      // Put it on the pastebin through the carrier layer (kant-pastebin.mjs):
      // no pastebinit binary, just the API every Kant pastebin speaks.
      const ch = pastebinChannel(`https://${opts.backend}`, null);
      const res = await ch.share(content, { title: what === "link" ? "kant invite" : undefined });
      const url = res.url;
      st.lastPaste = url;
      st.lastPasteAt = new Date().toISOString();
      save(store(st, c));
      out(`posted ${what} to the pastebin:\n${url}`, {
        ok: true, url, permalink: res.permalink, id: res.id, cid: res.cid,
        what, room: C.clientRoom(c),
        link: what === "link" ? content.trim() : undefined,
      });
      return;
    }

    case "accept": {
      // Take in a paste: the URL pastebinit printed, or — with no argument —
      // the latest paste in the UUCP spool this client can load.
      const arg = rest.slice(1).join(" ").trim();
      // The carrier layer does the fetching and the spool walking; this
      // command just decides what a loadable paste looks like (loadText).
      const ch = pastebinChannel(`https://${opts.backend}`, opts.spool, {
        takeFn: (text) => (loadText(st, c, text) !== "nothing" ? text : null),
      });
      if (arg) {
        const text = await ch.take(arg);
        if (text == null) {
          console.error(`could not read a paste at ${arg}`);
          if (opts.json) console.log(JSON.stringify({ ok: false, kind: "no-paste", url: arg },
            null, 2));
          process.exit(1);
        }
        const now = loadText(st, c, text);
        if (now === "nothing") {
          const named = describe(classify(text.trim()));
          console.error(`nothing this client can load in that paste: ${named.kind}` +
            (named.kind === "page" ? ` ${named.addr}` : ""));
          if (opts.json) console.log(JSON.stringify({ ok: false, kind: "nothing", reason: named },
            null, 2));
          process.exit(1);
        }
        st.lastAccepted = arg;
        save(store(st, now));
        return;
      }
      // No argument: walk the spool index from the end until a paste loads.
      const got = ch.spool
        ? ch.spool.take((text) => (loadText(st, c, text) !== "nothing" ? text : null))
        : null;
      if (got) {
        st.lastAccepted = got.entry.id ?? got.entry.uucp_path;
        save(store(st, c)); // loadText already saved the joined state
        console.error(`accepted from spool entry ${got.tried} of ${ch.spool.list().length}: ` +
          `${got.entry.id ?? got.entry.uucp_path}`);
        return;
      }
      const looked = ch.spool ? Math.min(50, ch.spool.list().length) : 0;
      console.error(`nothing loadable in the last ${looked} spool entr` +
        `${looked === 1 ? "y" : "ies"}`);
      if (opts.json) console.log(JSON.stringify({ ok: false, kind: "nothing",
        spool: opts.spool, looked }, null, 2));
      process.exit(1);
    }

    default: break;
  }

  switch (rest[0]) {
    case "join": {
      const text = rest.slice(1).join(" ");
      if (!text) { console.error("join needs the text somebody sent you"); process.exit(2); }
      const joined = C.joinText(c.self, text);
      if (!joined) {
        const what = describe(classify(text.trim()));
        console.error(`nothing to join in that: ${what.kind}` +
          (what.kind === "page" ? ` ${what.addr}` : ""));
        if (opts.json) console.log(JSON.stringify({ ok: false, reason: what }, null, 2));
        process.exit(1);
      }
      joined.self = c.self;
      save(store(st, joined));
      out(`joined room ${C.clientRoom(joined)}\nrelay ${joined.relay || "(none)"}`, {
        ok: true, room: C.clientRoom(joined), relay: joined.relay, self: joined.self,
        page: C.pageOf(text.trim()),
      });
      return;
    }

    case "say": {
      needRoom(c);
      const text = rest.slice(1).join(" ");
      if (!text) { console.error("say needs something to say"); process.exit(2); }
      const line = C.printMsg(C.compose(c, text));
      const answer = await sendJson(C.postLine(c, line));
      c.seq += 1;
      C.ingest(c, line);
      save(store(st, c));
      out(`said (relay cursor ${answer.cursor})`, {
        ok: true, said: text, line, cursor: answer.cursor, room: C.clientRoom(c),
        curl: C.curlLine(C.postLine(c, line)),
      });
      return;
    }

    case "drop": {
      needRoom(c);
      const path = rest[1];
      if (!path) { console.error("drop needs a file"); process.exit(2); }
      const bytes = new Uint8Array(readFileSync(path));
      const name = basename(path);
      const mime = MIME[name.split(".").pop()?.toLowerCase()] ?? "application/octet-stream";
      const enc = await C.encryptFor(c.secret, name, mime, bytes);
      // Pin every chunk under its own witness first.  A manifest names its
      // chunks, so a manifest posted over a chunk that never landed would
      // announce a file nobody can finish fetching.
      for (let i = 0; i < enc.cids.length; i += 1) {
        await sendBinary(C.postBlock(c, enc.cids[i], enc.chunks[i]));
      }
      const line = C.manifestLine(c, enc);
      const answer = await sendJson(C.postLine(c, line));
      c.seq += 1;
      C.ingest(c, line);
      save(store(st, c));
      out(`dropped ${name} (${enc.size}B, ${enc.cids.length} chunk(s))`, {
        ok: true, name, mime, size: enc.size, chunks: enc.cids.length,
        cids: enc.cids, line, cursor: answer.cursor, room: C.clientRoom(c),
      });
      return;
    }

    case "files": {
      needRoom(c);
      const ans = await sendJson(C.pollFrom(c));
      for (const l of ans.lines ?? []) C.ingest(c, l);
      c.cursor = ans.cursor ?? c.cursor;
      save(store(st, c));
      const fs2 = C.filesOf(c);
      out(fs2.length
        ? fs2.map((f, i) => `${i}: ${f.name} (${f.size}B, ${f.cids.length} chunk(s))`).join("\n")
        : "(no files announced)",
        { ok: true, count: fs2.length, files: fs2.map((f) => ({
          name: f.name, mime: f.mime, size: f.size, chunks: f.cids.length,
          cids: f.cids, ipfs: f.ipfs ?? [],
        })) });
      return;
    }

    case "fetch": {
      needRoom(c);
      const ans = await sendJson(C.pollFrom(c));
      for (const l of ans.lines ?? []) C.ingest(c, l);
      c.cursor = ans.cursor ?? c.cursor;
      save(store(st, c));
      const fs2 = C.filesOf(c);
      const idx = Number(rest[1]);
      if (!Number.isInteger(idx) || idx < 0 || idx >= fs2.length) {
        console.error(`no file ${rest[1] ?? ""}: the room has ${fs2.length}`);
        process.exit(2);
      }
      const f = fs2[idx];
      const bytes = await C.takeFile(c.secret, f, async (cid) => {
        const b = await sendBinary(C.getBlock(c, cid));
        // `sendBinary` on a GET returns the relay's JSON envelope when the
        // relay answers one; a block is raw, so anything that is not the
        // right length is refused rather than decrypted into garbage.
        return b;
      });
      const target = opts.out ?? f.name;
      writeFileSync(target, bytes);
      out(`fetched ${f.name} -> ${target} (${bytes.length}B)`, {
        ok: true, name: f.name, wrote: target, size: bytes.length,
      });
      return;
    }

    case "quote": {
      needRoom(c);
      const ans = await sendJson(C.pollFrom(c));
      for (const l of ans.lines ?? []) C.ingest(c, l);
      c.cursor = ans.cursor ?? c.cursor;
      const fs2 = C.filesOf(c);
      const idx = Number(rest[1]);
      if (!Number.isInteger(idx) || idx < 0 || idx >= fs2.length) {
        console.error(`no file ${rest[1] ?? ""}: the room has ${fs2.length}`);
        process.exit(2);
      }
      const text = rest.slice(2).join(" ") || `re: ${fs2[idx].name}`;
      const line = C.printTimed(C.sayQuote(C.clientRoom(c), c.self, c.seq + 1, fs2[idx], text));
      const answer = await sendJson(C.postLine(c, line));
      c.seq += 1;
      C.ingest(c, line);
      save(store(st, c));
      out(`quoted ${fs2[idx].name}`, {
        ok: true, quoting: fs2[idx].name, text, line, cursor: answer.cursor,
      });
      return;
    }

    case "read": case "watch": {
      needRoom(c);
      const once = async () => {
        const req = opts.wait
          ? C.getReq(`${C.pollFrom(c).url}&wait=${C.decNum(opts.wait)}`)
          : C.pollFrom(c);
        const answer = await sendJson(req);
        for (const l of answer.lines ?? []) C.ingest(c, l);
        c.cursor = answer.cursor ?? c.cursor;
        save(store(st, c));
        return answer;
      };
      if (cmd === "read") {
        const answer = await once();
        out(C.viewText(c).join("\n"), {
          ok: true, room: C.clientRoom(c), cursor: c.cursor,
          arrived: (answer.lines ?? []).length,
          view: C.view(c).map((m) => ({ sender: m.sender, seq: m.seq, text: C.msgText(m) })),
          lines: c.lines,
          curl: C.curlLine(C.pollFrom(c)),
        });
        return;
      }
      for (;;) {
        const answer = await once();
        for (const l of answer.lines ?? []) {
          const m = C.parseMsg(l);
          if (m) console.log(`${m.sender.slice(0, 8)}: ${C.msgText(m)}`);
        }
        if (!opts.wait) await new Promise((r) => setTimeout(r, 1000));
      }
    }

    case "health": {
      if (!c.relay) { console.error("no relay yet"); process.exit(2); }
      const answer = await sendJson(C.getReq(`${c.relay}/health`));
      out(answer.ok ? `relay ok: ${answer.name ?? ""} ${answer.version ?? ""}` : "not a relay",
        { ok: !!answer.ok, health: answer, curl: C.curlLine(C.getReq(`${c.relay}/health`)) });
      return;
    }

    case "curl": {
      needRoom(c);
      const what = rest[1] ?? "read";
      let req;
      if (what === "read" || what === "poll") req = C.pollFrom(c);
      else if (what === "say") {
        const text = rest.slice(2).join(" ");
        req = C.postLine(c, C.printMsg(C.compose(c, text)));
      } else if (what === "health") req = C.getReq(`${c.relay}/health`);
      else { console.error(`curl what?  read | say <text> | health`); process.exit(2); }
      out(C.curlLine(req), {
        ok: true, curl: C.curlLine(req), argv: C.curlArgv(req), request: req,
        route: C.route(C.afterPrefix(c.relay, req.url) ?? ""),
      });
      return;
    }

    default:
      console.error(`unknown command: ${cmd}`);
      usage();
      process.exit(2);
  }
}

main().catch((e) => {
  console.error(e.message ?? String(e));
  process.exit(1);
});
