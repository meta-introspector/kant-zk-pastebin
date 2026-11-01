// poll-pacing-test.mjs — does an idle client actually stop asking?
//
// The relay is a rendezvous holding nothing worth keeping, so the only load a
// client creates is the requests it makes. A fixed interval charges a busy
// room and a dead one exactly the same, which is why the loop now grows the
// gap when nothing arrives and drops it back the moment something does.
//
// This counts real calls through a fake relay rather than reading the code, so
// a loop that looks right but polls flat still fails here. Run:
//
//   node web/poll-pacing-test.mjs

import assert from "node:assert/strict";
import { KantNode } from "./kant-net.mjs";

let pass = 0, fail = 0;
const t = async (name, fn) => {
  try { await fn(); console.log(`✔ ${name}`); pass++; }
  catch (e) { console.log(`✖ ${name}: ${e.message}`); fail++; }
};

const quiet = (ms) => new Promise((r) => setTimeout(r, ms));

/** A node whose relay returns `script` lines, one entry per poll. */
function fake(script, { onCall } = {}) {
  const node = new KantNode({ room: "pacing", peer: "pacer" });
  let i = 0;
  node.client = {
    async poll() {
      onCall?.(i);
      const lines = script[i] ?? [];
      i += 1;
      return { cursor: i, lines };
    },
    async post() { return { ok: true }; },
  };
  node.room = "pacing";
  return node;
}

await t("an idle client polls far less often than the old fixed interval", async () => {
  const gaps = [];
  const node = fake([], { onCall: (i) => gaps.push(i) });
  node.startPolling({ interval: 5, idleMs: 20, maxIdleMs: 120 });
  await quiet(500);
  node.stop();

  // The loop doubles from idleMs to maxIdleMs, so by 500ms it should be
  // making on the order of ten calls, not the ~100 a 5ms fixed interval gave.
  const calls = gaps.length;
  assert.ok(calls <= 25, `idle client made ${calls} calls in 500ms; the backoff is not taking effect`);
  assert.ok(calls >= 4, `idle client made only ${calls} calls; polling stopped entirely`);
});

await t("the gap actually grows, rather than staying at idleMs", async () => {
  const times = [];
  const node = fake([], { onCall: () => times.push(Date.now()) });
  node.startPolling({ interval: 5, idleMs: 20, maxIdleMs: 400 });
  await quiet(900);
  node.stop();

  const span = (a, b) => (times[b] - times[a]);
  const first = span(0, 1), last = span(times.length - 3, times.length - 1) / 2;
  assert.ok(last > first * 2,
    `the gap did not grow: early ~${first}ms, late ~${Math.round(last)}ms`);
});

await t("a line arriving drops the gap straight back to the busy interval", async () => {
  // Busy for a while, then silent: the timing must fall, then rise.
  const script = [];
  for (let i = 0; i < 12; i++) script.push([`busy-${i}`]);
  script.push([], [], [], [], [], [], [], []);
  const times = [];
  const node = fake(script, { onCall: () => times.push(Date.now()) });
  node.startPolling({ interval: 20, idleMs: 40, maxIdleMs: 400 });
  await quiet(1000);
  node.stop();

  assert.ok(times.length >= 12, `only ${times.length} polls; not enough to see the change`);
  const duringBusy = times[6] - times[5];
  const afterQuiet = times[times.length - 1] - times[times.length - 2];
  assert.ok(duringBusy < afterQuiet,
    `busy gap ${duringBusy}ms should be tighter than the idle gap ${afterQuiet}ms`);
});

await t("idle polls are jittered, so a room's clients do not return as one herd", async () => {
  // The danger of a fixed backoff is that every client backs off by the same
  // amount and returns together. Drive many nodes and check the first gap
  // after going idle is not identical across them.
  const firstIdleGap = [];
  for (let n = 0; n < 6; n++) {
    const script = [];
    for (let i = 0; i < 4; i++) script.push([`x-${n}-${i}`]);
    script.push([], [], [], [], [], [], [], [], []);
    const times = [];
    const node = fake(script, { onCall: () => times.push(Date.now()) });
    node.startPolling({ interval: 10, idleMs: 60, maxIdleMs: 500 });
    await quiet(700);
    node.stop();
    // the gap right after the last busy poll
    firstIdleGap.push(times[5] - times[4]);
  }
  const distinct = new Set(firstIdleGap).size;
  assert.ok(distinct > 1,
    `all 6 clients waited ${firstIdleGap[0]}ms to go idle — that is a herd, not a backoff`);
});

await t("stop() ends the loop", async () => {
  let calls = 0;
  const node = fake([], { onCall: () => calls++ });
  node.startPolling({ interval: 5, idleMs: 10, maxIdleMs: 20 });
  await quiet(120);
  node.stop();
  const at = calls;
  await quiet(120);
  assert.equal(calls, at, `polling continued after stop(): ${calls - at} more calls`);
});

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);