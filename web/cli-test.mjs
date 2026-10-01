// Two command-line clients, one relay, one link — and the same session in
// curl, and in the browser client.
//
//   node web/cli-test.mjs
//
// What it checks:
//   1. the pure layer of `web/kant-cli.mjs` against vectors Lean computed
//      (`RequestProject/Kant/Cli.lean`);
//   2. two separate `scripts/kant-cli.mjs` processes, each with its own state
//      file, finding each other over a real `server/relay.mjs` with nothing
//      between them but a link pasted into a chat message;
//   3. the same run again with `--transport curl`, i.e. with every request
//      made by the real `curl` binary;
//   4. the `curl` command lines the CLI prints, executed by a shell, landing
//      in the room and being read by the other client;
//   5. the browser client (`web/kant-net.mjs`, the code `web/index.html`
//      runs) joining the very same link and displaying the very same
//      conversation.

import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import * as C from "./kant-cli.mjs";
import * as N from "./kant-net.mjs";

let checks = 0;
const fail = [];
const ok = (name, cond) => { checks += 1; if (!cond) fail.push(name); };
const eq = (name, got, want) =>
  ok(`${name} (got ${JSON.stringify(got)}, want ${JSON.stringify(want)})`,
    JSON.stringify(got) === JSON.stringify(want));

const root = fileURLToPath(new URL("..", import.meta.url));
const CLI = join(root, "scripts", "kant-cli.mjs");
const hasCurl = spawnSync("curl", ["--version"], { encoding: "utf8" }).status === 0;

// ============================================================ 1. the vectors
// Every value below was computed by Lean; see the `#guard` block at the end of
// RequestProject/Kant/Cli.lean.

const SECRET = Array.from("swordfish").map((c) => c.charCodeAt(0));
const ROOM = "5799c0f1158e3a8e5e8ffcf366b996f3c677124d12536a906495a0aaaf2b2f65";

eq("decNum 0", C.decNum(0), "0");
eq("decNum 7", C.decNum(7), "7");
eq("decNum 1024", C.decNum(1024), "1024");
eq("digitsValue (decNum 90210)", C.digitsValue(C.decNum(90210)), 90210);
eq("the room of a known secret", C.roomOf(SECRET), ROOM);
eq("roomPath", C.roomPath(ROOM), `/room/${ROOM}`);
eq("cursorQuery", C.cursorQuery(3), "?cursor=3");
eq("route of a bare room path", C.route(C.roomPath(ROOM)), { room: ROOM, cursor: 0 });
eq("route of a poll path", C.route(C.roomPath(ROOM) + C.cursorQuery(12)),
  { room: ROOM, cursor: 12 });
eq("route of anything else", C.route("/health"), null);
eq("a GET as a curl line", C.curlLine(C.getReq("http://x/health")),
  "curl -sS http://x/health");
eq("a POST as a curl line", C.curlLine(C.postReq("http://x/room/r", "abc")),
  "curl -sS -X POST -H content-type:text/plain --data-binary abc http://x/room/r");
eq("a curl line reads back as its request",
  C.parseCurlLine(C.curlLine(C.postReq("http://x/room/r", "abc"))),
  C.postReq("http://x/room/r", "abc"));
eq("a GET curl line reads back", C.parseCurlLine("curl -sS http://x/health"),
  C.getReq("http://x/health"));
ok("junk is not a curl line", C.parseCurlLine("wget http://x") === null);

const vecClient = C.openRoom("agent-a", "http://127.0.0.1:8787", SECRET);
eq("the poll request Lean computes", C.curlLine(C.pollFrom(vecClient)),
  `curl -sS http://127.0.0.1:8787/room/${ROOM}?cursor=0`);
eq("the line Lean computes for a message",
  C.printMsg(C.compose(C.openRoom("agent-a", "http://r", SECRET), "hello")),
  "6b7a63686174:3537393963306631313538653361386535653866666366333636623939366633" +
  "6336373731323464313235333661393036343935613061616166326232663635:6167656e742d61" +
  ":01:68656c6c6f:653464376564363962323165336462613163623665643065626361636661303935" +
  "64613730346664373261663239303430386230346239386336356434333262");
const vecCfg = { origin: "https://kant.cicada71.net/" };
eq("the link Lean computes", C.clientLink(vecCfg, vecClient),
  "https://kant.cicada71.net/#6b7a696e76697465:687474703a2f2f3132372e302e302e313a3837" +
  "3837:73776f726466697368:6167656e742d61");
eq("the page part of that link", C.pageOf(C.clientLink(vecCfg, vecClient)),
  "https://kant.cicada71.net/");
eq("joining that link lands in the same room",
  C.clientRoom(C.joinText("agent-b", C.clientLink(vecCfg, vecClient))), ROOM);
eq("...and on the same relay",
  C.joinText("agent-b", C.clientLink(vecCfg, vecClient)).relay, "http://127.0.0.1:8787");

// ====================================================== 2. two live clients

// The relay is a separate process, as it is in real life — and as it has to
// be here, because the clients are separate processes too and this one waits
// for each of them in turn.
const relayPath = join(root, "server", "relay.mjs");
function startRelay(port) {
  const proc = spawn(process.execPath,
    [relayPath, "--port", String(port), "--static", join(root, "web")],
    { stdio: ["ignore", "pipe", "pipe"] });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("relay did not start")), 8000);
    proc.stdout.on("data", (d) => {
      if (String(d).includes("listening")) { clearTimeout(timer); resolve(proc); }
    });
    proc.on("error", reject);
  });
}

const port = 8901 + Math.floor(Math.random() * 90);
const relay = await startRelay(port);
const base = `http://127.0.0.1:${port}`;
const origin = `${base}/`;
const dir = mkdtempSync(join(tmpdir(), "kant-cli-"));

/** One command of the CLI, as an agent would run it. */
function cli(state, args, { transport = "fetch", name = null, json = true } = {}) {
  const argv = [CLI, "--state", join(dir, state), "--origin", origin,
    "--transport", transport];
  if (json) argv.push("--json");
  if (name) argv.push("--name", name);
  const out = spawnSync("node", [...argv, ...args], { encoding: "utf8", cwd: root });
  if (out.status !== 0) {
    return { ok: false, status: out.status, stderr: out.stderr, stdout: out.stdout };
  }
  return json ? JSON.parse(out.stdout) : { ok: true, text: out.stdout.trim() };
}

/** A whole session between two agents, in one transport. */
function session(tag, transport) {
  const A = `${tag}-a.json`;
  const B = `${tag}-b.json`;

  const opened = cli(A, ["open", "--relay", base], { transport, name: `${tag}-a` });
  ok(`[${tag}] the first agent opens a room`, opened.ok === true);
  ok(`[${tag}] the link is the site with the room in the fragment`,
    opened.link.startsWith(`${origin}#`));
  eq(`[${tag}] the page a static host would be asked for`, opened.page, origin);
  eq(`[${tag}] the link carries the room`,
    C.clientRoom(C.joinText("x", opened.link)), opened.room);

  // The link now travels through some other channel entirely: a chat window,
  // a DM, a tweet.  It arrives wrapped in whatever the person typed.
  const pasted = `hey — jump in here: ${opened.link} .\nsee you in a sec\n`;
  const joined = cli(B, ["join", pasted], { transport, name: `${tag}-b` });
  ok(`[${tag}] the second agent joins from the pasted message`, joined.ok === true);
  eq(`[${tag}] both agents are in one room`, joined.room, opened.room);
  eq(`[${tag}] and on one relay`, joined.relay, base);

  const said = cli(A, ["say", "hello from the first terminal"], { transport });
  ok(`[${tag}] the first agent says something`, said.ok === true);
  eq(`[${tag}] the relay took it`, said.cursor, 1);

  const readB = cli(B, ["read"], { transport });
  eq(`[${tag}] the second agent reads it`, readB.view.map((m) => m.text),
    ["hello from the first terminal"]);

  const back = cli(B, ["say", "hello back from the second"], { transport });
  ok(`[${tag}] the second agent answers`, back.ok === true);

  const readA = cli(A, ["read"], { transport });
  eq(`[${tag}] the first agent sees both lines`, readA.view.map((m) => m.text),
    ["hello from the first terminal", "hello back from the second"]);

  const readB2 = cli(B, ["read"], { transport });
  eq(`[${tag}] both agents display the same conversation`,
    readB2.view.map((m) => [m.sender, m.text]), readA.view.map((m) => [m.sender, m.text]));

  const who = cli(A, ["whoami"], { transport });
  eq(`[${tag}] the client knows its own room`, who.room, opened.room);
  eq(`[${tag}] and how far it has read`, who.cursor, 2);

  return { room: opened.room, link: opened.link, view: readA.view, stateA: A, stateB: B };
}

try {
  const viaFetch = session("fetch", "fetch");

  // ================================================ 3. the same run, in curl
  if (hasCurl) {
    const viaCurl = session("curl", "curl");
    eq("curl and fetch give the same conversation",
      viaCurl.view.map((m) => m.text), viaFetch.view.map((m) => m.text));
    ok("the two runs used two different rooms", viaCurl.room !== viaFetch.room);
  } else {
    ok("curl is available", false);
  }

  // ======================================= 4. the printed curl, run by hand
  if (hasCurl) {
    const printed = cli(viaFetch.stateA, ["curl", "say", "typed into the shell"]);
    ok("the CLI prints a curl command", printed.curl.startsWith("curl -sS -X POST"));
    eq("the printed command reads back as the request it makes",
      C.parseCurlLine(printed.curl), printed.request);
    eq("and the relay routes it to this room",
      C.route(C.afterPrefix(base, printed.request.url)).room, viaFetch.room);

    // Run it exactly as printed, in a shell, with globbing off so the `?` of
    // a query string is left alone.
    const shell = spawnSync("sh", ["-c", `set -f; ${printed.curl}`], { encoding: "utf8" });
    eq("the shell runs it", shell.status, 0);
    ok("the relay accepted it", JSON.parse(shell.stdout).ok === true);

    const readB = cli(viaFetch.stateB, ["read"]);
    ok("the other agent reads the hand-typed line",
      readB.view.some((m) => m.text === "typed into the shell"));

    // And the read side too: the poll command, run by hand, returns the room.
    const pollCmd = cli(viaFetch.stateB, ["curl", "read"]);
    const polled = spawnSync("sh", ["-c", `set -f; ${pollCmd.curl}`], { encoding: "utf8" });
    eq("the poll command runs", polled.status, 0);
    const body = JSON.parse(polled.stdout);
    ok("the relay answers with the room", body.ok === true && Array.isArray(body.lines));
  }

  // ==================================== 5. the browser client, same link
  const browser = new N.KantNode({ peer: "browser-tab" });
  const inv = C.findInvite(viaFetch.link);
  ok("the browser client finds the invitation in the same link", inv !== null);
  browser.joinInvite(N.copyInvite(inv));
  eq("the browser lands in the room the CLI opened", browser.room, viaFetch.room);
  await browser.pollOnce();
  const cliTexts = cli(viaFetch.stateA, ["read"]).view.map((m) => m.text);
  const browserTexts = browser.view().map((m) => N.msgText(m));
  eq("the browser displays exactly what the CLI displays", browserTexts, cliTexts);

  await browser.say("hello from the browser");
  const afterBrowser = cli(viaFetch.stateA, ["read"]);
  ok("the CLI hears the browser",
    afterBrowser.view.some((m) => m.text === "hello from the browser"));
  eq("no same-browser bus was in play", browser.bus, null);

  // ============ 6. the same conversation in a link, with no relay at all
  //
  // The other thing an agent can add to a URL is the conversation itself.
  // A third agent that never touches the relay loads the link and holds it.
  const bag = cli(viaFetch.stateA, ["bag"]);
  ok("the conversation fits in one link", bag.bagUrl.startsWith(`${origin}#`));
  eq("the link asks the host for the page and nothing else", bag.page, origin);
  const loaded = cli("reader.json", ["load", bag.bagUrl], { name: "reader" });
  eq("a reader with no relay takes the conversation out of the link",
    loaded.view.map((m) => m.text),
    cli(viaFetch.stateA, ["read"]).view.map((m) => m.text));
  const again = cli("reader.json", ["load", bag.bagUrl], { name: "reader" });
  eq("loading the same link twice adds nothing", again.taken, 0);
  const refused = spawnSync("node",
    [CLI, "--state", join(dir, "reader.json"), "--json", "load", "nothing in here at all"],
    { encoding: "utf8", cwd: root });
  eq("junk is refused", refused.status, 1);

  // ============================== 7. the whole demonstration, as a shell run
  if (hasCurl) {
    const demoPort = 9301 + Math.floor(Math.random() * 90);
    const demo = spawnSync("sh", [join(root, "scripts", "two-agents.sh")], {
      encoding: "utf8", cwd: root, env: { ...process.env, PORT: String(demoPort) },
    });
    eq("scripts/two-agents.sh runs to the end", demo.status, 0);
    ok("...with both agents in one room",
      /both agents are in room [0-9a-f]{64}/.test(demo.stdout));
    ok("...and the same conversation on both sides",
      /same conversation\?\u001b\[0m\nyes:/.test(demo.stdout) || demo.stdout.includes("yes:"));
    ok("...having typed out its curl commands",
      demo.stdout.includes("$ curl -sS -X POST -H content-type:text/plain"));
  }

  // ===================================== the state file is what Lean models
  const st = cli(viaFetch.stateA, ["whoami"]);
  eq("the client's own name survives in its state file", st.self, "fetch-a");
  ok("the state file exists", existsSync(join(dir, viaFetch.stateA)));
} finally {
  relay.kill();
  rmSync(dir, { recursive: true, force: true });
}

console.log(`${checks - fail.length}/${checks} checks passed`);
if (fail.length) {
  for (const f of fail) console.error(`FAIL: ${f}`);
  process.exit(1);
}
