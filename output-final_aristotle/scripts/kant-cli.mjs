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
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import * as C from "../web/kant-cli.mjs";
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
  config: new URL("../web/kant.config", import.meta.url).pathname,
  name: null,
  relay: null,
  wait: 0,
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
    case "-h": case "--help": rest.push("help"); break;
    default: rest.push(tok);
  }
}

const cfg = (() => {
  const base = existsSync(opts.config)
    ? (parseConfig(readFileSync(opts.config, "utf8")) ?? DEFAULT_CONFIG)
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
    const out = spawnSync("curl", args, { encoding: "utf8" });
    if (out.status !== 0) {
      throw new Error(`curl failed (${out.status}): ${out.stderr.trim()}`);
    }
    return out.stdout;
  }
  const r = await fetch(req.url, req.method === "post"
    ? { method: "POST", headers: { "content-type": "text/plain" }, body: req.body }
    : undefined);
  if (!r.ok) throw new Error(`relay ${req.method} failed: ${r.status}`);
  return r.text();
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

function usage() {
  console.log(`kant-cli — the kant-zk-pastebin client for a terminal

  open --relay <url>     open a fresh room on a relay
  link                   the link to send in any chat window
  invite                 the bare invitation code
  room                   the room this client is in
  whoami                 name, relay, room, counters
  join <text>            join the room named by a pasted message or link
  load <url>             load a URL: join a room, or take in a conversation
  say <text>             say something in the room
  read                   read the room and print the conversation
  bag                    the whole conversation as one link (no relay needed)
  watch [--wait 25]      keep reading until interrupted
  health                 ask the relay whether it is there
  curl read|say <text>|link   print the curl command instead of running it

Options: --state <file> --json --transport fetch|curl --print-curl
         --origin <url> --config <file> --name <id> --relay <url>`);
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
      const what = C.loadUrl(text);
      if (what.kind === "bag") {
        // A conversation carried in the link itself: no relay in it at all.
        const taken = C.absorb(c, what.messages.map((m) => C.printMsg(m)));
        save(store(st, c));
        out(`took ${taken} line(s) out of the link`, {
          ok: true, kind: "bag", taken, page: C.pageOf(text.trim()),
          view: C.view(c).map((m) => ({ sender: m.sender, seq: m.seq, text: C.msgText(m) })),
        });
        return;
      }
      if (what.kind === "nothing") {
        const named = describe(classify(text.trim()));
        console.error(`nothing this client can load: ${named}`);
        if (opts.json) console.log(JSON.stringify({ ok: false, kind: "nothing", reason: named },
          null, 2));
        process.exit(1);
      }
      // An invitation: fall through to joining it.
      rest[0] = "join";
      break;
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
        console.error(`nothing to join in that: ${what}`);
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
