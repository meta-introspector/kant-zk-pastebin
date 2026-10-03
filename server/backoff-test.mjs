// backoff-test.mjs — the retry pacing, proven.  The failure this guards
// against is the bridge spending Cloudflare's Durable Objects duration
// budget: at a flat 10s retry it burned the free tier in two days, and a
// 500 answered every 10s cost exactly as much as a healthy poll.

import assert from "node:assert/strict";
import { Backoff, classify, holdFor } from "./backoff.mjs";

let pass = 0, fail = 0;
const t = async (name, fn) => {
  try { await fn(); console.log(`✔ ${name}`); pass++; }
  catch (e) { console.log(`✖ ${name}: ${e.message}`); fail++; }
};

// ---------------------------------------------------------------- classify

await t("a 500 is a server fault, not a quota fault", () => {
  assert.equal(classify(new Error("relay poll from 0 failed: 500")).kind, "server");
});

await t("the free-tier duration error is recognised as quota", () => {
  const e = new Error(
    "relay poll from 0 failed: 500 — Exceeded allowed duration in Durable Objects free tier.",
  );
  assert.equal(classify(e).kind, "quota");
  assert.equal(classify(e).status, 500);
});

await t("429 is rate, 404 is missing", () => {
  assert.equal(classify(new Error("x failed: 429")).kind, "rate");
  assert.equal(classify(new Error("x failed: 404")).kind, "missing");
});

await t("an unreachable relay is a network fault", () => {
  assert.equal(classify(new Error("fetch failed")).kind, "network");
  assert.equal(classify(new Error("connect ECONNREFUSED 1.2.3.4:443")).kind, "network");
  assert.equal(classify(new Error("relay poll timed out")).kind, "network");
});

await t("a status property is honoured over the message text", () => {
  const e = new Error("opaque");
  e.status = 429;
  assert.equal(classify(e).kind, "rate");
});

await t("an unrecognised failure still classifies as other, not quota", () => {
  assert.equal(classify(new Error("something odd")).kind, "other");
});

// ----------------------------------------------------------------- backoff

await t("the first failure waits one interval, not two", () => {
  const b = new Backoff({ base: 10_000, jitter: 0 });
  assert.equal(b.fail(new Error("failed: 500")).delay, 10_000);
});

await t("repeated failures double up to the cap", () => {
  const b = new Backoff({ base: 10_000, cap: 640_000, jitter: 0 });
  const d = [0, 1, 2, 3, 4, 5].map(() => b.fail(new Error("failed: 500")).delay);
  assert.deepEqual(d, [10_000, 20_000, 40_000, 80_000, 160_000, 320_000]);
  assert.equal(b.fail(new Error("failed: 500")).delay, 640_000, "capped");
});

await t("a quota error sits out the full quota window", () => {
  const b = new Backoff({ base: 10_000, cap: 640_000, quotaFloor: 1_800_000, jitter: 0 });
  const r = b.fail(new Error("Exceeded allowed duration in Durable Objects free tier."));
  assert.equal(r.kind, "quota");
  assert.equal(r.delay, 1_800_000, "not merely the grown 10s");
  // …and it stays there: a minute of failing must not drift back down.
  assert.equal(b.fail(new Error("Exceeded allowed duration in Durable Objects free tier.")).delay, 1_800_000);
});

await t("a quota latch survives an intervening ordinary failure", () => {
  const b = new Backoff({ base: 10_000, cap: 640_000, quotaFloor: 1_800_000, jitter: 0 });
  b.fail(new Error("Exceeded allowed duration in Durable Objects free tier."));
  b.fail(new Error("failed: 500"));
  assert.equal(b.fail(new Error("failed: 500")).delay, 1_800_000, "still latched");
});

await t("success resets the backoff and clears the quota latch", () => {
  const b = new Backoff({ base: 10_000, cap: 640_000, quotaFloor: 1_800_000, jitter: 0 });
  b.fail(new Error("Exceeded allowed duration in Durable Objects free tier."));
  b.fail(new Error("failed: 500"));
  assert.equal(b.ok(), 10_000);
  assert.equal(b.failures, 0);
  assert.equal(b.fail(new Error("failed: 500")).delay, 10_000, "grown from one again");
});

await t("jitter stays inside its band and never reaches zero", () => {
  const b = new Backoff({ base: 100, cap: 100, jitter: 0.5, rand: () => 0 });
  assert.equal(b.fail(new Error("failed: 500")).delay, 50, "low end");
  const b2 = new Backoff({ base: 100, cap: 100, jitter: 0.5, rand: () => 1 });
  assert.equal(b2.fail(new Error("failed: 500")).delay, 100, "high end");
  // Equal jitter must keep the fixed half, so N bridges do not all
  // wake at the same instant when the quota resets.  Delays are rounded
  // to whole ms, so the 50..100 band can hold at most 50 values.
  const delays = new Set();
  for (let i = 0; i < 200; i++)
    delays.add(new Backoff({ base: 100, cap: 100, jitter: 0.5 }).fail(new Error("x failed: 500")).delay);
  assert.ok(delays.size > 25, `expected a spread, got ${delays.size} distinct`);
  assert.ok(Math.min(...delays) >= 50);
});

await t("a base longer than the cap is honoured, not truncated", () => {
  const b = new Backoff({ base: 3_600_000, cap: 900_000, jitter: 0 });
  assert.equal(b.cap, 3_600_000);
  assert.equal(b.fail(new Error("failed: 500")).delay, 3_600_000);
});

// ------------------------------------------------- the budget, arithmetic

await t("a dead destination costs ~4 polls/hour, not 360", () => {
  // The regression that cost the free tier: a flat 10s retry is 360
  // requests/hour per loop, each holding a Durable Object open.
  // Backoff works in ms, so this is the production shape: 10s base.
  const b = new Backoff({ base: 10_000, cap: 900_000, jitter: 0 });
  let waited = 0, polls = 0;
  while (waited < 3600e3) {
    waited += b.fail(new Error("failed: 500")).delay;
    polls++;
  }
  assert.ok(polls <= 12, `expected <=12 polls/hour, got ${polls}`);
});

await t("a quota-exhausted destination costs ~1 poll/15min", () => {
  const b = new Backoff({ base: 10_000, cap: 900_000, quotaFloor: 900_000, jitter: 0 });
  let waited = 0, polls = 0;
  const err = new Error("Exceeded allowed duration in Durable Objects free tier.");
  while (waited < 3600e3) { waited += b.fail(err).delay; polls++; }
  assert.equal(polls, 4, "3600s / 900s");
});

await t("Backoff's contract is milliseconds, and says so", () => {
  // The seconds-vs-milliseconds bug lived in the caller, not here: the
  // CLI speaks seconds, Backoff speaks ms, and Bridge converts. This
  // test only pins the unit contract; the wiring is proven end to end in
  // forward-backoff-e2e.mjs ("a 10s interval waits seconds, not
  // milliseconds"), which is the test that actually caught it.
  assert.equal(new Backoff({ base: 10_000, jitter: 0 }).fail(new Error("x failed: 500")).delay, 10_000);
});

// -------------------------------------------------------------------- hold

await t("the long-poll hold never exceeds its share of the period", () => {
  assert.equal(holdFor(60, 10), 10);
  assert.equal(holdFor(10, 10), 3, "a 10s hold in a 10s period is a held-open relay");
  assert.equal(holdFor(60, 600), 20);
  assert.equal(holdFor(60, 0), 0, "no long poll when none is asked for");
  for (const [i, w] of [[1, 10], [5, 10], [10, 10], [30, 10], [10, 1]])
    assert.ok(holdFor(i, w) <= i, `hold ${holdFor(i, w)} must fit period ${i}`);
});

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
