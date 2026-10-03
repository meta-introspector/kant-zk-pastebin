// relay-telemetry-test.mjs — the telemetry collector's arithmetic and sampling.
//
// The collector's job is to say what is true about the fleet. A collector that
// reports an interval it has just proved is over budget is worse than one that
// reports nothing, so the arithmetic gets tested against itself first.

import { sustainableIntervalSeconds, readBudget, sample as liveSample, isReachable, normalizeHealth } from "./relay-telemetry.mjs";

// Four sampling tests would otherwise spend twelve requests on the live fleet.
// Sample once, share the rows, and the shape assertions still hold -- what
// they check is the collector's output shape, not four separate afternoons.
let rowsPromise = null;
const sample = () => (rowsPromise ??= liveSample());

let pass = 0, fail = 0;
const failures = [];
const tests = [];
const t = (name, fn) => { tests.push([name, fn]); };

const B = () => readBudget();

// ------------------------------------------------------- the arithmetic

t("a poll is charged for the worker AND the durable object", () => {
  // The one number that makes the interval what it is. A poll hits the Worker
  // and then the Durable Object behind it, so it costs 2 requests. Halve this
  // and every advertised interval silently doubles.
  const b = B();
  if (b.requestsPerPoll !== 2) throw new Error(`requestsPerPoll=${b.requestsPerPoll}, expected 2`);
  // 3 workers, one poll a minute, 2 requests each:
  const expected = (86400 / 60) * 2 * 3;
  if (sustainableIntervalSeconds({ workers: 3 }).at(60).requestsPerDay !== expected) {
    throw new Error(`minute polling across 3 workers != ${expected}`);
  }
});

t("the advertised interval is affordable under its own budget", () => {
  // The bug this exists to catch: the headline said "every 10s" while the
  // table beneath it marked 10s as OVER. Exact was 10.37s and Math.round
  // rounded DOWN into the red.
  const s = sustainableIntervalSeconds({ workers: 3 });
  const a = s.at(s.secondsBetweenPolls);
  const b = B();
  if (a.fractionOfBudget > b.headroom) {
    throw new Error(`advertised ${s.secondsBetweenPolls}s costs ${(a.fractionOfBudget * 100).toFixed(1)}%, over ${b.headroom}`);
  }
});

t("rounding never lands below the exact interval", () => {
  const s = sustainableIntervalSeconds({ workers: 3 });
  if (s.secondsBetweenPolls < s.secondsBetweenPollsExact) {
    throw new Error(`${s.secondsBetweenPolls} < exact ${s.secondsBetweenPollsExact}`);
  }
});

t("a shorter interval always costs more", () => {
  const s = sustainableIntervalSeconds({ workers: 3 });
  let prev = Infinity;
  for (const sec of [5, 10, 30, 60, 300, 900]) {
    const cost = s.at(sec).requestsPerDay;
    if (cost > prev) throw new Error(`at ${sec}s cost rose`);
    prev = cost;
  }
});

t("cost scales with the worker count", () => {
  // The budget is per ACCOUNT, so adding workers divides it further: each one
  // is polled LESS often. Getting this backwards is the easy mistake -- it
  // would advertise the same interval to a 3-worker fleet as to a single
  // worker and overspend the account threefold.
  const one = sustainableIntervalSeconds({ workers: 1 });
  const three = sustainableIntervalSeconds({ workers: 3 });
  if (!(three.secondsBetweenPollsExact > one.secondsBetweenPollsExact)) {
    throw new Error(`3 workers (${three.secondsBetweenPollsExact.toFixed(2)}s) not looser than 1 (${one.secondsBetweenPollsExact.toFixed(2)}s)`);
  }
  // Linear in the fan-out, modulo the ceil: 3x the exact interval, so the
  // rounded value may be one second under the triple but never under it.
  if (three.secondsBetweenPolls < one.secondsBetweenPolls * 3 - 1) {
    throw new Error(`3 workers (${three.secondsBetweenPolls}s) tighter than 3x of 1 (${one.secondsBetweenPolls * 3}s)`);
  }
  // The same interval costs more when the fleet is bigger.
  if (one.at(60).requestsPerDay === three.at(60).requestsPerDay) {
    throw new Error("request cost ignored the worker count");
  }
  if (three.at(60).requestsPerDay !== one.at(60).requestsPerDay * 3) {
    throw new Error(`${three.at(60).requestsPerDay} != 3 x ${one.at(60).requestsPerDay}`);
  }
  // And the interval each worker gets is the same share of budget, whichever
  // fleet it belongs to.
  for (const n of [1, 3, 7]) {
    const s = sustainableIntervalSeconds({ workers: n });
    const a = s.at(s.secondsBetweenPolls);
    if (a.fractionOfBudget > B().headroom) {
      throw new Error(`${n} workers: advertised ${s.secondsBetweenPolls}s costs ${(a.fractionOfBudget * 100).toFixed(1)}%`);
    }
  }
});

t("a bigger budget buys a shorter interval", () => {
  const small = sustainableIntervalSeconds({ budget: { ...B(), doRequestsPerDay: 10000 } });
  const big = sustainableIntervalSeconds({ budget: { ...B(), doRequestsPerDay: 1000000 } });
  if (!(big.secondsBetweenPolls < small.secondsBetweenPolls)) throw new Error("no effect");
});

t("more headroom buys a shorter interval", () => {
  const tight = sustainableIntervalSeconds({ budget: { ...B(), headroom: 0.1 } });
  const loose = sustainableIntervalSeconds({ budget: { ...B(), headroom: 0.9 } });
  if (!(loose.secondsBetweenPolls < tight.secondsBetweenPolls)) throw new Error("no effect");
});

t("headroom of 1.0 still leaves the interval finite and positive", () => {
  const s = sustainableIntervalSeconds({ budget: { ...B(), headroom: 1 } });
  if (!(s.secondsBetweenPolls > 0)) throw new Error(`${s.secondsBetweenPolls}`);
});

t("zero workers does not divide by zero", () => {
  const s = sustainableIntervalSeconds({ workers: 0 });
  if (!Number.isFinite(s.secondsBetweenPolls)) throw new Error(`${s.secondsBetweenPolls}`);
});

t("the fraction is a fraction, not a percentage", () => {
  const s = sustainableIntervalSeconds({ workers: 3 });
  const f = s.at(3600).fractionOfBudget;
  if (f >= 1) throw new Error(`hourly polling is ${f} of budget`);
  if (f <= 0) throw new Error(`hourly polling is ${f}`);
});

// ---------------------------------------------------------- the sampling

t("only a 200 counts as reachable", () => {
  // Tested against the function, not against the live fleet, where every
  // worker happens to answer 200 -- so the live sample cannot tell a correct
  // `=== 200` from a looser `>= 200` at all.
  if (!isReachable(200)) throw new Error("200 is not reachable");
  for (const s of [0, 201, 301, 302, 400, 404, 500, 503]) {
    if (isReachable(s)) throw new Error(`${s} counted as reachable`);
  }
});

t("health claims are read, not invented", () => {
  // Everything here happens offline, because the live fleet's /health payloads
  // are not what the collector has to be robust against -- old workers,
  // rolled-back deploys, and error pages are.
  const none = normalizeHealth(null, null, 404);
  if (none.durable !== null) throw new Error(`no health -> durable=${JSON.stringify(none.durable)}`);
  if (none.mode !== null) throw new Error(`no health -> mode=${JSON.stringify(none.mode)}`);
  if (none.stats !== null) throw new Error(`no health -> stats=${JSON.stringify(none.stats)}`);

  const silent = normalizeHealth({ version: "1.0.0" }, null, 404);
  if (silent.durable !== null) throw new Error(`durable defaulted to ${JSON.stringify(silent.durable)}`);
  if (silent.version !== "1.0.0") throw new Error("lost the version");

  // A worker that says `false` must keep saying false -- that is the whole
  // point of distinguishing it from silence.
  const saysFalse = normalizeHealth({ durable: false }, null, 404);
  if (saysFalse.durable !== false) throw new Error(`false became ${JSON.stringify(saysFalse.durable)}`);
  const saysTrue = normalizeHealth({ durable: true }, null, 404);
  if (saysTrue.durable !== true) throw new Error("lost a true");

  // A string is not a boolean claim, however confident the string.
  const stringy = normalizeHealth({ durable: "false", mode: "isolate" }, null, 404);
  if (stringy.durable !== null) throw new Error(`"false" read as ${JSON.stringify(stringy.durable)}`);
  if (stringy.mode !== "isolate") throw new Error("lost the mode");

  const withStats = normalizeHealth({}, { rooms: 2 }, 200);
  if (withStats.stats?.rooms !== 2) throw new Error("lost the stats");
  // 200 on stats but a null body must stay null, not become `{}`.
  const emptyBody = normalizeHealth({}, null, 200);
  if (emptyBody.stats !== null) throw new Error(`200 with no body -> ${JSON.stringify(emptyBody.stats)}`);
});

t("a sample records every worker with a timestamp", async () => {
  const rows = await sample();
  if (rows.length < 1) throw new Error("no rows");
  for (const r of rows) {
    if (!r.worker) throw new Error("row without a worker name");
    if (!r.at || Number.isNaN(Date.parse(r.at))) throw new Error(`bad timestamp ${r.at}`);
  }
});

t("a worker without /stats records null, not an empty object", async () => {
  // The distinction that matters downstream: "no stats" must never serialise
  // as `{}` and then read as zero of everything.
  const rows = await sample();
  for (const r of rows) {
    if (r.statsStatus !== 200 && r.stats !== null) {
      throw new Error(`${r.worker} stats=${JSON.stringify(r.stats)} without a 200`);
    }
  }
});

t("an absent durability claim stays null rather than becoming false", async () => {
  const rows = await sample();
  for (const r of rows) {
    if (typeof r.durable !== "boolean" && r.durable !== null) {
      throw new Error(`${r.worker} durable=${JSON.stringify(r.durable)}`);
    }
  }
});

t("samples carry enough to tell a worker apart from a name", async () => {
  const rows = await sample();
  for (const r of rows) {
    if (!("status" in r)) throw new Error("no status");
    if (!("reachable" in r)) throw new Error("no reachability");
    if (!("statsStatus" in r)) throw new Error("no stats status");
  }
});

for (const [name, fn] of tests) {
  try { await fn(); pass++; console.log("  ok  ", name); }
  catch (e) { fail++; failures.push(name); console.log("  FAIL", name, "—", e.message); }
}
console.log(`\n${pass} passed, ${fail} failed`);
if (fail) { console.log("FAILED:", failures.join(", ")); process.exit(1); }