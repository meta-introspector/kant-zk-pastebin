// kant-diag.mjs — the net and error log, the verdict, and the shareable run.
//
// This is an unverified transcription of `RequestProject/Kant/Diagnostics.lean`
// (events, the bounded log, sharing without leaking a secret, the report)
// and `RequestProject/Kant/Connectivity.lean` (which relay is used, whether
// two clients can exchange a line, and the verdict when they cannot).
// Every function below corresponds to a Lean definition of the same name,
// and `web/diag-test.mjs` checks it against vectors computed by Lean.

import {
  asciiBytes, asciiChars, witness, natToBytesBE, bytesBEToNat,
  envelopeEncode, envelopeDecode, containsSub,
} from "./kantzk.mjs";

// ------------------------------------------------------------ levels, areas

/** `Kant.Diagnostics.Level.code`. */
export const LEVEL = { info: 1, warn: 2, error: 3 };
export const LEVEL_OF_CODE = Object.fromEntries(
  Object.entries(LEVEL).map(([k, v]) => [v, k]),
);

/** `Kant.Diagnostics.Area.code`. */
export const AREA = {
  config: 1, probe: 2, relay: 3, socket: 4, bus: 5,
  mesh: 6, signal: 7, ingest: 8, app: 9,
};
export const AREA_OF_CODE = Object.fromEntries(
  Object.entries(AREA).map(([k, v]) => [v, k]),
);

const TAG_LOG = asciiBytes("kzlog");
const TAG_REPORT = asciiBytes("kzdiag");

const eqBytes = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

/** Text that survives the wire: printable ASCII, no newline, no control code. */
export const scrub = (s) =>
  Array.from(String(s ?? ""))
    .map((c) => {
      const n = c.codePointAt(0);
      return n >= 32 && n < 127 ? c : " ";
    })
    .join("");

// ------------------------------------------------------------------ events

/** One line of the run (`Kant.Diagnostics.Event`). */
export const event = (seq, ms, level, area, text, detail = "") =>
  ({ seq, ms, level, area, text: scrub(text), detail: scrub(detail) });

/** `printEvent`: one event as one line of text. */
export function printEvent(e) {
  return envelopeEncode({
    tag: TAG_LOG,
    fields: [
      natToBytesBE(e.seq), natToBytesBE(e.ms),
      [LEVEL[e.level] & 0xff], [AREA[e.area] & 0xff],
      asciiBytes(e.text), asciiBytes(e.detail),
    ],
  });
}

/** `parseEvent`: read one line back, `null` when it is not one. */
export function parseEvent(s) {
  const env = envelopeDecode(s);
  if (!env || !eqBytes(env.tag, TAG_LOG) || env.fields.length !== 6) return null;
  const [sq, ms, lc, ac, tx, dt] = env.fields;
  if (lc.length !== 1 || ac.length !== 1) return null;
  const level = LEVEL_OF_CODE[lc[0]];
  const area = AREA_OF_CODE[ac[0]];
  if (!level || !area) return null;
  return {
    seq: Number(bytesBEToNat(sq)),
    ms: Number(bytesBEToNat(ms)),
    level, area,
    text: asciiChars(tx),
    detail: asciiChars(dt),
  };
}

/** `renderLog` / `parseLog`: the run as text, and back. */
export const renderLog = (events) => events.map(printEvent).join("\n");

export function parseLog(s) {
  if (s === "") return [];
  const out = [];
  for (const line of s.split("\n")) {
    const e = parseEvent(line);
    if (!e) return null;
    out.push(e);
  }
  return out;
}

// -------------------------------------------------------------------- log

/** The bounded, ordered run (`Kant.Diagnostics.Log`).
 *
 *  It holds at most `cap` events and counts the rest in `dropped`
 *  (`Log.add_length_le`, `Log.add_total`); the newest event is never the
 *  one trimmed (`Log.add_getLast`); sequence numbers strictly increase and
 *  are never reused (`Log.Wf.record`).
 */
export class DiagLog {
  constructor({ cap = 2000, clock = () => Date.now(), onEvent = () => {} } = {}) {
    this.cap = Math.max(1, cap);
    this.events = [];
    this.dropped = 0;
    this.started = clock();
    this.clock = clock;
    this.onEvent = onEvent;
  }

  /** `Log.total`: how many events the run has produced, kept or dropped. */
  get total() { return this.dropped + this.events.length; }

  /** `Log.add`. */
  add(e) {
    this.events.push(e);
    const excess = this.events.length - this.cap;
    if (excess > 0) {
      this.events.splice(0, excess);
      this.dropped += excess;
    }
    this.onEvent(e, this);
    return e;
  }

  /** `Log.record`: stamp with the next sequence number and the clock. */
  record(level, area, text, detail = "") {
    return this.add(event(this.total, Math.max(0, this.clock() - this.started),
      level, area, text, detail));
  }

  info(area, text, detail) { return this.record("info", area, text, detail); }
  warn(area, text, detail) { return this.record("warn", area, text, detail); }
  error(area, text, detail) {
    return this.record("error", area, text,
      detail instanceof Error ? `${detail.name}: ${detail.message}` : detail);
  }

  /** Keep the run in `storage` under `key`, so a reload — or a crash —
   *  does not lose it.  What is written is exactly `renderLog`, so it
   *  reads back with `parseLog`. */
  persist(key, storage = globalThis.localStorage, { every = 400 } = {}) {
    if (!storage) return this;
    this.store = { key, storage, timer: null, every };
    const flush = () => {
      this.store.timer = null;
      try { storage.setItem(key, this.render()); }
      catch { /* a full or forbidden store must not break the client */ }
    };
    const previous = this.onEvent;
    this.onEvent = (e, log) => {
      previous(e, log);
      if (!this.store.timer) this.store.timer = setTimeout(flush, every);
    };
    flush();
    return this;
  }

  /** Every event that quotes none of `secrets` (`Log.share`). */
  share(secrets = []) { return this.events.filter((e) => clean(secrets, e)); }

  render() { return renderLog(this.events); }
}

/** `Event.mentions`. */
export const mentions = (secret, e) =>
  secret !== "" && (containsSub(secret, e.text) || containsSub(secret, e.detail));

/** `Event.clean`: quotes none of the secrets held. */
export const clean = (secrets, e) => secrets.every((s) => !mentions(s, e));

/** `ref`: a short one-way handle for a room or a secret. */
export const ref = (s) => witness(asciiBytes(s)).slice(0, 8);

// ------------------------------------------------------- where clients meet

/** `Kant.Connectivity.effectiveRelay` — a configured relay wins; failing
 *  that, the page's own origin, but only when it was probed and really
 *  answered as a relay. */
export function effectiveRelay(r) {
  if (r.configured) return r.configured;
  if (r.originIsRelay) return r.origin;
  return "";
}

/** `RelayUsable`. */
export const relayUsable = (r) => (r.configured ? !!r.configuredUp : !!r.originIsRelay);

/** `SharedRelay`. */
export const sharedRelay = (a, b) =>
  relayUsable(a.reach) && relayUsable(b.reach) &&
  effectiveRelay(a.reach) !== "" &&
  effectiveRelay(a.reach) === effectiveRelay(b.reach);

/** `SameBrowser`. */
export const sameBrowser = (a, b) => !!a.bus && !!b.bus && a.browser === b.browser;

/** `Linked`: can these two exchange a line? */
export const linked = (a, b) =>
  a.room === b.room && a.room !== "" && (sameBrowser(a, b) || sharedRelay(a, b));

/** `RelayDown`: a relay was named and did not answer. */
export const relayDown = (c) => !!c.reach.configured && !c.reach.configuredUp;

/** `Kant.Connectivity.diagnose`. */
export function diagnose(a, b) {
  if (a.room === "" || b.room === "") return "noRoom";
  if (a.room !== b.room) return "roomMismatch";
  if (linked(a, b)) return "ok";
  if (relayDown(a) || relayDown(b)) return "relayDown";
  if (a.bus && b.bus) return "onlyThisBrowser";
  return "noTransport";
}

/** `Kant.Connectivity.explain`, verbatim. */
export const EXPLAIN = {
  ok: "ok: you and the other client share a room and a transport",
  noRoom: "no-room: open a room, or paste an invite link",
  roomMismatch: "room-mismatch: the link pasted is not the link that was shown",
  relayDown: "relay-down: the configured relay did not answer; check `relay =` in kant.config",
  onlyThisBrowser:
    "only-this-browser: two separate browsers with no relay between them; serve the page " +
    "with `node server/relay.mjs --static web`, or set `relay =`",
  noTransport: "no-transport: no relay, and no same-browser channel",
};

export const explain = (v) => EXPLAIN[v] ?? "";

export const VERDICT_CODE = {
  ok: 1, noRoom: 2, roomMismatch: 3, relayDown: 4, onlyThisBrowser: 5, noTransport: 6,
};
export const CODE_VERDICT = Object.fromEntries(
  Object.entries(VERDICT_CODE).map(([k, v]) => [v, k]),
);

// ----------------------------------------------------------------- reports

/** The header line of a report (`Kant.Diagnostics.header`). */
export const reportHeader = (r) => envelopeEncode({
  tag: TAG_REPORT,
  fields: [[VERDICT_CODE[r.verdict] & 0xff], asciiBytes(r.room), asciiBytes(r.relay)],
});

export function parseReportHeader(s) {
  const env = envelopeDecode(s);
  if (!env || !eqBytes(env.tag, TAG_REPORT) || env.fields.length !== 3) return null;
  const [vc, rm, rl] = env.fields;
  if (vc.length !== 1) return null;
  const verdict = CODE_VERDICT[vc[0]];
  if (!verdict) return null;
  return { verdict, room: asciiChars(rm), relay: asciiChars(rl) };
}

/** The whole run as one machine-readable block (`renderReport`). */
export const renderReport = (r) =>
  [reportHeader(r), ...r.events.map(printEvent)].join("\n");

/** …and back (`parseReport`). */
export function parseReport(s) {
  const [head, ...rest] = String(s).split("\n");
  const h = parseReportHeader(head);
  if (!h) return null;
  const events = [];
  for (const line of rest) {
    const e = parseEvent(line);
    if (!e) return null;
    events.push(e);
  }
  return { ...h, events };
}

/** The same run as something a person can read, with the machine-readable
 *  block underneath so the page can load it back. */
export function reportText(r, { note = "" } = {}) {
  const lines = [
    "kant-zk diagnostics",
    `verdict: ${explain(r.verdict)}`,
    `room:    ${r.room || "(none)"}`,
    `relay:   ${r.relay || "(none)"}`,
    `events:  ${r.events.length}${r.dropped ? ` (+${r.dropped} dropped)` : ""}`,
  ];
  if (note) lines.push(`note:    ${scrub(note)}`);
  lines.push("");
  for (const e of r.events) {
    lines.push(`${String(e.ms).padStart(7)}ms ${e.level.padEnd(5)} ${e.area.padEnd(7)} ` +
      `${e.text}${e.detail ? `  |  ${e.detail}` : ""}`);
  }
  lines.push("", "--- machine-readable, paste into the diagnostics page ---", renderReport(r));
  return lines.join("\n");
}

/** Pull the machine-readable block out of a pasted report, however much
 *  chat window is wrapped around it. */
export function findReport(text) {
  const lines = String(text ?? "").split(/\r?\n/);
  for (let i = 0; i < lines.length; i += 1) {
    const head = parseReportHeader(lines[i].trim());
    if (!head) continue;
    const events = [];
    for (let j = i + 1; j < lines.length; j += 1) {
      const e = parseEvent(lines[j].trim());
      if (!e) break;
      events.push(e);
    }
    return { ...head, events };
  }
  return null;
}

// ------------------------------------------------------------ probing relays

/**
 * The base URL to probe for a relay, derived from where this page is served.
 *
 * `location.origin` is not it. A relay mounted under a sub-path — and this one
 * is, at https://solana.solfunmeme.com/p2p-relay — answers `/health` and
 * `/room/{room}` under that prefix, so probing the bare origin asks
 * https://solana.solfunmeme.com/health, gets a 404, and the client concludes
 * that nobody outside this browser can join. Which is what it did, silently,
 * while the relay it was looking for was answering perfectly well one path down.
 *
 * The directory the page was served from is the right base: it equals the bare
 * origin when the relay serves at the root, which is the
 * `node server/relay.mjs --static web` case the config describes, and carries
 * the mount prefix when it does not.
 */
export function servedBase(href) {
  try {
    return new URL(".", href).href.replace(/\/+$/, "");
  } catch {
    return "";
  }
}

/** Ask a base URL whether it is a relay.  Never throws: every outcome is
 *  a value, and every outcome is logged. */
export async function probeRelay(base, { fetchImpl = globalThis.fetch, log = null,
                                          timeoutMs = 4000 } = {}) {
  if (!base) return { ok: false, status: 0, reason: "no relay named" };
  const url = `${String(base).replace(/\/+$/, "")}/health`;
  log?.info("probe", "probing a relay", url);
  const ctl = typeof AbortController === "function" ? new AbortController() : null;
  const timer = ctl ? setTimeout(() => ctl.abort(), timeoutMs) : null;
  try {
    const res = await fetchImpl(url, { cache: "no-cache", signal: ctl?.signal });
    if (timer) clearTimeout(timer);
    if (!res.ok) {
      log?.warn("probe", `relay answered ${res.status}`, url);
      return { ok: false, status: res.status, reason: `answered ${res.status}` };
    }
    let body = {};
    try { body = await res.json(); } catch { body = {}; }
    const ok = body && body.ok !== false && typeof body.name === "string";
    if (!ok) {
      log?.warn("probe", "that URL answers, but is not a relay", url);
      return { ok: false, status: res.status, reason: "not a relay" };
    }
    log?.info("probe", `relay up: ${body.name}${body.version ? ` ${body.version}` : ""}`, url);
    return { ok: true, status: res.status, name: body.name, version: body.version ?? "" };
  } catch (e) {
    if (timer) clearTimeout(timer);
    log?.error("probe", "cannot reach that relay", e);
    return { ok: false, status: 0, reason: e && e.message ? e.message : String(e) };
  }
}

/** Work out, by probing, where this client can meet others
 *  (`Kant.Connectivity.Reachability`).  A configured relay is probed and
 *  used; with nothing configured the page's own origin is probed, and used
 *  only if it really is a relay — which is exactly what
 *  `node server/relay.mjs --static web` gives you. */
export async function resolveReachability({ configured = "", origin = "",
                                            fetchImpl = globalThis.fetch,
                                            log = null } = {}) {
  const conf = String(configured || "").trim().replace(/\/+$/, "");
  const org = String(origin || "").trim().replace(/\/+$/, "");
  const reach = { configured: conf, configuredUp: false, origin: org, originIsRelay: false };
  if (conf) {
    const p = await probeRelay(conf, { fetchImpl, log });
    reach.configuredUp = p.ok;
    reach.probe = p;
    log?.record(p.ok ? "info" : "error", "config",
      p.ok ? "using the configured relay" : `the configured relay is down: ${p.reason}`, conf);
    return reach;
  }
  if (org && /^https?:/i.test(org)) {
    const p = await probeRelay(org, { fetchImpl, log });
    reach.originIsRelay = p.ok;
    reach.probe = p;
    log?.record(p.ok ? "info" : "warn", "config",
      p.ok
        ? "no relay configured, but this page is served by one — using it"
        : "no relay configured, and this page is not served by one: only other tabs " +
          "of this browser can find you",
      org);
    return reach;
  }
  log?.warn("config", "no relay, and no http origin to probe", org);
  return reach;
}

/** Move the run left behind by the last page load out of the way, and
 *  return it.  A crash is exactly the case where the log matters most, so
 *  the previous run is kept until the one after it replaces it. */
export function rotateStoredRun(storage = globalThis.localStorage,
                                { key = "kant-diag-run", previous = "kant-diag-previous" } = {}) {
  if (!storage) return [];
  let held = null;
  try { held = storage.getItem(key); } catch { return []; }
  if (!held) return [];
  try { storage.setItem(previous, held); } catch { /* nothing we can do */ }
  return parseLog(held) ?? [];
}

/** The run from before the last reload, if there is one. */
export function previousRun(storage = globalThis.localStorage,
                            { previous = "kant-diag-previous" } = {}) {
  if (!storage) return [];
  try { return parseLog(storage.getItem(previous) ?? "") ?? []; } catch { return []; }
}

/** The client as the diagnostics see it (`Kant.Connectivity.Client`). */
export const clientOf = ({ room = "", reach, bus = false, browser = 0 }) =>
  ({ room, reach, bus: !!bus, browser });
