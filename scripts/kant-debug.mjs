#!/usr/bin/env node
/**
 * kant-debug - say what a pasted code is, and why two of them do not connect.
 *
 * Usage:
 *   node scripts/kant-debug.mjs <first> [second]
 *   node scripts/kant-debug.mjs --stdin          # two blocks separated by a
 *                                                # line containing only ---
 *   node scripts/kant-debug.mjs --probe          # also check the deployment
 *   node scripts/kant-debug.mjs --where-is-the-log
 *
 * <first> and <second> may each be a file name, or the text itself: a whole
 * pasted share card, a bare `kzcard:` / `kzinvite:` line, or a page link.
 *
 * The rules it applies are proved in `RequestProject/Kant/CardDebug.lean`
 * and `RequestProject/Kant/Connectivity.lean`.
 */
import { readFileSync, existsSync } from "node:fs";
import { classify, describe, report, renderReport, single } from "../web/kant-carddebug.mjs";
import { parseConfig, parseRelay, DEFAULT_CONFIG } from "../web/kant-site.mjs";
import { probeRelay, effectiveRelay, diagnose, explain as explainVerdict }
  from "../web/kant-diag.mjs";

const LOG_HELP = `Where the log is
----------------
There is no server-side log of a browser session, because on a static host
there is no server in the conversation at all.  The run log lives in three
places, all of them on your own machine:

  1. The Diagnostics card at the bottom of the page (index.html) - the live
     tail of the current run, with Copy, Save and Open the diagnostics page.
  2. web/diag.html - the whole run as a table, "Run the checks on this
     machine", a copyable link that carries the run in its fragment, and
     "Load the run from before the last reload".
  3. The relay, if you run one:  node server/relay.mjs --log relay.log
     writes every request, refusal and socket event.

If the deployed copy of the site has no Diagnostics card, it predates this
work: redeploy web/ and the log appears.`;

function usage() {
  console.log(`kant-debug - what is this code, and why will these two not connect?

  node scripts/kant-debug.mjs <first> [second]
  node scripts/kant-debug.mjs --stdin
  node scripts/kant-debug.mjs --probe [--config web/kant.config]
  node scripts/kant-debug.mjs --where-is-the-log

Options:
  --config <file>   the deployment configuration (default web/kant.config)
  --probe           ask the configured relay and the origin whether they are
                    relays, and say whether two devices could meet at all
  --json            print the report as JSON
  --stdin           read both blocks from standard input, separated by ---
`);
}

const argv = process.argv.slice(2);
const opts = { config: "web/kant.config", probe: false, json: false, stdin: false };
const rest = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--config") opts.config = argv[++i];
  else if (a === "--probe") opts.probe = true;
  else if (a === "--json") opts.json = true;
  else if (a === "--stdin") opts.stdin = true;
  else if (a === "--where-is-the-log" || a === "--log") { console.log(LOG_HELP); process.exit(0); }
  else if (a === "-h" || a === "--help") { usage(); process.exit(0); }
  else rest.push(a);
}

const readBlock = (s) => (s && existsSync(s) ? readFileSync(s, "utf8") : s ?? "");

function loadConfig(file) {
  if (!existsSync(file)) return { ...DEFAULT_CONFIG };
  const text = readFileSync(file, "utf8");
  const cfg = parseConfig(text) ?? { ...DEFAULT_CONFIG };
  cfg.relay = parseRelay(text) ?? "";
  return cfg;
}

const cfg = loadConfig(opts.config);

let first = "";
let second = "";
if (opts.stdin) {
  const all = readFileSync(0, "utf8");
  const parts = all.split(/^\s*---\s*$/m);
  first = parts[0] ?? "";
  second = parts[1] ?? parts[0] ?? "";
} else {
  if (!rest.length && !opts.probe) { usage(); process.exit(1); }
  first = rest.length ? readBlock(rest[0]) : "";
  second = rest.length > 1 ? readBlock(rest[1]) : "";
}

if (first && second) {
  const r = report(first, second, cfg.origin);
  if (opts.json) console.log(JSON.stringify(r, null, 2));
  else console.log(renderReport(r).join("\n"));
} else if (first) {
  const c = classify(first);
  const r = { code: describe(c), note: single(c) };
  if (opts.json) console.log(JSON.stringify(r, null, 2));
  else {
    for (const [k, v] of Object.entries(r.code)) {
      if (v === null || v === undefined || (Array.isArray(v) && !v.length)) continue;
      console.log(`${k.padEnd(8)}${Array.isArray(v) ? v.join(", ") : v}`);
    }
    console.log("");
    console.log(r.note);
  }
}

if (opts.probe) {
  console.log("");
  console.log(`origin  ${cfg.origin}`);
  console.log(`relay   ${cfg.relay === "" ? "(not configured)" : cfg.relay}`);
  const configured = cfg.relay ? await probeRelay(cfg.relay) : { ok: false, reason: "not configured" };
  const origin = await probeRelay(cfg.origin);
  console.log(`configured relay: ${configured.ok ? "up" : `no (${configured.reason})`}`);
  console.log(`origin as relay:  ${origin.ok ? "yes" : `no (${origin.reason})`}`);
  const reach = {
    configured: cfg.relay,
    configuredUp: configured.ok,
    origin: cfg.origin,
    originIsRelay: origin.ok,
  };
  const meet = effectiveRelay(reach);
  console.log(`meeting point:    ${meet === "" ? "(none - two devices cannot meet)" : meet}`);
  // Two devices, same room, this deployment: what would the page say?
  const room = "0".repeat(64);
  const a = { room, reach, bus: true, browser: 1 };
  const b = { room, reach, bus: true, browser: 2 };
  const v = diagnose(a, b);
  console.log(`two devices:      ${v}`);
  console.log(explainVerdict(v));
  if (meet === "") {
    console.log("");
    console.log("Fix: set `relay = https://<your relay>` in " + opts.config +
      " and redeploy, or serve the page with `node server/relay.mjs --static web`.");
  }
}
