// relay-telemetry.mjs — poll the relay fleet on a cadence, and work out how
// often that cadence can actually be sustained.
//
// Three commands:
//
//   --once            one sample per worker, printed
//   --collect N M     poll every M seconds, N times, appending to a series file
//   --analyze         read the series and derive the sustainable interval
//
// The budget arithmetic is the point. Cloudflare's Free plan allots ~100k
// Durable Object requests per account per day, and a poll is at least one
// request to the Worker plus one to the Durable Object behind it. So the
// sustainable interval is a division, not a preference -- and a poll interval
// chosen by feel is how a monitoring loop eats a deployment's whole budget.
//
// What it cannot do, stated plainly: `/stats` returns 404 until the storage
// split is deployed, and this token's GraphQL exposes only `cost` and `viewer`
// rather than the analytics datasets. So the per-room counters are absent and
// the budget figures below come from the spec's planning table, not from the
// account. `readBudget` keeps them in one place so they can be replaced with
// real numbers without touching the arithmetic.

import { readFileSync, writeFileSync, existsSync, appendFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

const SERIES = new URL("../.relay-telemetry.jsonl", import.meta.url).pathname;

const WORKERS = [
  { name: "kant-zk-relay-wasm", url: "https://kant-zk-relay-wasm.jmikedupont2.workers.dev" },
  { name: "otc-desk-relay-v2", url: "https://otc-desk-relay-v2.jmikedupont2.workers.dev" },
  { name: "otc-desk-relay-production", url: "https://otc-desk-relay-production.jmikedupont2.workers.dev" },
];

/**
 * Planning figures, from the spec's §12 table.
 *
 * NOT measured from the account. They are here so the arithmetic is one edit
 * away from real telemetry rather than a guess buried in a formula.
 */
export const readBudget = () => ({
  doRequestsPerDay: 100000,
  workerRequestsPerDay: 100000,
  // A poll costs one Worker invocation plus one Durable Object request.
  requestsPerPoll: 2,
  // Leave headroom: the spec's §16 asks for progressive admission controls
  // before 70% of the daily allocation, and a monitoring loop that consumes
  // the last 30% on its own is not monitoring.
  headroom: 0.5,
});

const fetchJson = async (url, ms = 8000) => {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), ms);
  try {
    const r = await fetch(url, { signal: ac.signal });
    const text = await r.text();
    let json = null;
    try { json = JSON.parse(text); } catch { /* not json */ }
    return { status: r.status, json };
  } catch (e) {
    return { status: 0, json: null, error: String(e?.message ?? e) };
  } finally {
    clearTimeout(timer);
  }
};

/** Only 200 means the relay actually answered. A redirect is not health. */
export const isReachable = (status) => status === 200;

/**
 * `/health` fields, read so that an absent claim stays absent.
 *
 * `durable: false` and "this worker never said" are different facts and the
 * second one is the normal case today, so the field is null unless the worker
 * actually asserted a boolean. Same for `stats`: no `/stats` is recorded as
 * null, never as `{}`, so downstream never reads "no stats" as "zero".
 */
export function normalizeHealth(json, statsJson, statsStatus) {
  return {
    mode: json?.mode ?? null,
    durable: typeof json?.durable === "boolean" ? json.durable : null,
    version: json?.version ?? null,
    statsStatus,
    stats: isReachable(statsStatus) ? statsJson : null,
  };
}

/**
 * One sample per worker.
 *
 * `/stats` is optional on purpose. A worker without it is still worth
 * sampling -- reachability is telemetry too -- but the counters are simply
 * absent, and the sample says so.
 */
export async function sample() {
  const at = new Date().toISOString();
  const out = [];
  for (const w of WORKERS) {
    const h = await fetchJson(`${w.url}/health`);
    const s = await fetchJson(`${w.url}/stats/_probe`);
    out.push({
      at,
      worker: w.name,
      reachable: isReachable(h.status),
      status: h.status,
      latencyMs: null,
      ...normalizeHealth(h.json, s.json, s.status),
    });
  }
  return out;
}

const once = async () => {
  const rows = await sample();
  console.log(pad("worker", 28), pad("ok", 5), pad("mode", 12), pad("durable", 9), pad("/stats", 7), "version");
  console.log("-".repeat(80));
  for (const r of rows) {
    console.log(pad(r.worker, 28), pad(r.reachable ? "yes" : "no", 5),
      pad(r.mode ?? "unknown", 12),
      pad(r.durable === null ? "unknown" : String(r.durable), 9),
      pad(r.statsStatus === 200 ? "yes" : String(r.statsStatus), 7),
      r.version ?? "-");
  }
  const withStats = rows.filter((r) => r.statsStatus === 200).length;
  console.log();
  console.log(`${withStats}/${rows.length} workers expose /stats.`);
  if (!withStats) {
    console.log("The storage split is not deployed, so there is no per-room telemetry to");
    console.log("collect yet. Reachability is still sampled; the counters cannot be.");
  }
};

const collect = async (n, everySec) => {
  console.log(`Collecting ${n} samples every ${everySec}s -> ${SERIES}`);
  if (!existsSync(SERIES)) writeFileSync(SERIES, "");
  for (let i = 0; i < n; i++) {
    const rows = await sample();
    for (const r of rows) appendFileSync(SERIES, JSON.stringify(r) + "\n");
    console.log(`  ${i + 1}/${n}  ${rows.filter((r) => r.reachable).length}/${rows.length} reachable`);
    if (i < n - 1) await new Promise((r) => setTimeout(r, everySec * 1000));
  }
  console.log("done");
};

/**
 * The sustainable interval, in seconds.
 *
 * The arithmetic is deliberately plain: a day has 86400 seconds, a poll costs
 * `requestsPerPoll` requests, the budget is capped at `headroom` of the daily
 * allowance, and the interval is whatever divides those out. What this cannot
 * do is tell you the interval that is *worth* it -- only the one that fits.
 */
export function sustainableIntervalSeconds({ budget = readBudget(), workers = WORKERS.length } = {}) {
  const usable = budget.doRequestsPerDay * budget.headroom;
  // Total polls across all workers, then per worker. The budget is per account,
  // so it cannot be divided per worker before the fan-out is accounted for.
  const pollsPerDayTotal = usable / budget.requestsPerPoll;
  const perWorker = pollsPerDayTotal / Math.max(1, workers);
  const exact = 86400 / perWorker;
  return {
    pollsPerDayPerWorker: perWorker,
    secondsBetweenPollsExact: exact,
    // Rounded UP, never down. `Math.round` turned 10.37s into "every 10s",
    // which this same function then reported as OVER -- an advertised
    // interval that breaks the budget it was derived from is worse than no
    // interval at all.
    secondsBetweenPolls: Math.ceil(exact),
    at: (s) => ({
      requestsPerDay: Math.round((86400 / s) * budget.requestsPerPoll * workers),
      fractionOfBudget: ((86400 / s) * budget.requestsPerPoll * workers) / budget.doRequestsPerDay,
    }),
  };
}

const analyze = () => {
  const s = sustainableIntervalSeconds();
  console.log("Budget (spec §12 planning table, not measured from the account):");
  const b = readBudget();
  console.log(`  DO requests/day     ${b.doRequestsPerDay.toLocaleString()}`);
  console.log(`  usable (${b.headroom} headroom) ${Math.round(b.doRequestsPerDay * b.headroom).toLocaleString()}`);
  console.log(`  per poll            ${b.requestsPerPoll} requests (worker + DO)`);
  console.log(`  workers             ${WORKERS.length}`);
  console.log();
  console.log(`Sustainable interval: every ${s.secondsBetweenPolls}s per worker`);
  console.log(`(exact ${s.secondsBetweenPollsExact.toFixed(2)}s, rounded up so it fits)`);
  console.log();
  console.log(pad("interval", 12), pad("requests/day", 14), "of DO budget");
  console.log("-".repeat(46));
  for (const sec of [10, 30, 60, 300, 900, 3600]) {
    const a = s.at(sec);
    const fits = a.fractionOfBudget <= b.headroom ? "" : "  OVER";
    console.log(pad(`${sec}s`, 12), pad(a.requestsPerDay.toLocaleString(), 14),
      `${(a.fractionOfBudget * 100).toFixed(1)}%${fits}`);
  }
  console.log();
  console.log("This is the ceiling, not the recommendation. Whether a poll is worth its");
  console.log("cost depends on what changes between polls, and /stats is not deployed, so");
  console.log("there is currently nothing on the other end to measure.");
};

const pad = (s, n) => String(s ?? "-").padEnd(n);

// Only when run directly. Importing this module must not poll the fleet:
// scripts/thunk-claims.mjs imports readBudget() from here to re-verify the
// cadence claim, and a ledger that made three network requests per run would be
// a ledger nobody runs offline.
const argv = process.argv.slice(2);
const cmd = argv.find((a) => a.startsWith("--")) ?? "--once";
if (resolve(process.argv[1] ?? "") === fileURLToPath(import.meta.url)) {
  if (cmd === "--once") await once();
  else if (cmd === "--collect") await collect(Number(argv[1 + argv.indexOf("--collect")]) || 5,
                                              Number(argv[2 + argv.indexOf("--collect")]) || 60);
  else if (cmd === "--analyze") analyze();
  else { console.log("usage: relay-telemetry.mjs [--once | --collect N SECONDS | --analyze]"); process.exit(1); }
}