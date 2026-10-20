// relay-start.mjs — start a test relay and wait for it to actually be listening.
//
// Four suites each had their own copy of this:
//
//   const timer = setTimeout(() => reject(new Error("relay did not start")), 8000);
//   proc.stdout.on("data", (d) => { if (String(d).includes("listening")) ... });
//
// The 8000 was a guess, and it was wrong twice over. `server/relay.mjs` opens
// its SQLite pass database on start-up and the first connection migrates the
// schema, so "listening" arrives after that — 2.9s on an idle box, and
// 10.5s / 13.6s / 15.4s on this one with a load average of 15 on 24 cores.
// Under `npm run verify`, which runs the relay-backed suites back to back while
// everything else competes for the same cores, 8s is not a budget, it is a
// coin toss. `web/cli-page-test.mjs` and its delegating copy
// `scripts/cli-page-test.mjs` are how this was found: both went red in a verify
// run with `relay did not start`, having passed in the four runs before.
//
// The second thing wrong with the copies: on timeout they reject with four
// words and no evidence. So the caller cannot tell "the relay was slow" from
// "the relay crashed on start-up" from "the port was taken", which is exactly
// the shape of problem that gets a wrong cause written down. This one reports
// what the relay said, and its exit status if it died.
//
// The budget is 30s: 2x the worst measurement above, on a box half this
// loaded. It is not a licence to wait forever — a relay that cannot start in
// 30s is broken, and the message says so.

import { spawn } from "node:child_process";

/** How long to wait for the relay's `listening` line, in ms. */
export const RELAY_START_BUDGET_MS = 30_000;

/**
 * Spawn `server/relay.mjs` and resolve with the child once it reports it is
 * listening.
 *
 * @param {string} relayPath  absolute path to server/relay.mjs
 * @param {number} port       the port to bind
 * @param {string[]} extra    further arguments, e.g. --static, --pass-db
 * @param {{budgetMs?: number}} [opts]
 * @returns {Promise<import("node:child_process").ChildProcess>}
 */
export function startRelay(relayPath, port, extra = [], opts = {}) {
  const budgetMs = opts.budgetMs ?? RELAY_START_BUDGET_MS;
  const started = Date.now();
  const proc = spawn(process.execPath, [relayPath, "--port", String(port), ...extra], {
    stdio: ["ignore", "pipe", "pipe"],
  });
  return new Promise((resolve, reject) => {
    let stderr = "";
    let done = false;
    const settle = (fn, arg) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      fn(arg);
    };
    const timer = setTimeout(() => {
      proc.kill();
      const said = stderr.trim().slice(0, 400);
      settle(reject, new Error(
        `relay did not report listening on ${port} within ${budgetMs}ms ` +
        `(waited ${Date.now() - started}ms; the budget is ${
          RELAY_START_BUDGET_MS}ms because start-up migrates the pass-db schema ` +
        `and measured 10.5-15.4s on a loaded box)` +
        (said ? `\nrelay said: ${said}` : "\nrelay said nothing on stderr"),
      ));
    }, budgetMs);
    proc.stderr.on("data", (d) => { stderr += d; });
    proc.stdout.on("data", (d) => {
      if (String(d).includes("listening")) settle(resolve, proc);
    });
    proc.on("error", (e) => settle(reject, e));
    proc.on("exit", (code, signal) => {
      const said = stderr.trim().slice(0, 400);
      settle(reject, new Error(
        `relay exited before listening (exit ${code}${signal ? `, ${signal}` : ""})` +
        (said ? `\nrelay said: ${said}` : "\nrelay said nothing on stderr"),
      ));
    });
  });
}