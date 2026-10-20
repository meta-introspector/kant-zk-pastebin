// relay-measure-test.mjs — the measurement tool's judgment, tested.
//
// A measurement tool that reports "unknown" as "safe" is worse than none: it
// would be used to decide a deployment is fine. So the classification is the
// part under test, and the cadence curve is asserted to be monotonic -- if a
// looser cadence ever wrote more, the whole trade would be fictional.

import { classifyHealth, cadence, summarizeCadence } from "./relay-measure.mjs";

let pass = 0, fail = 0;
const failures = [];
const tests = [];
const t = (name, fn) => { tests.push([name, fn]); };

// ------------------------------------------------------- classifyHealth

t("a worker that says nothing about storage is UNKNOWN, not false", () => {
  // The distinction the whole tool exists to preserve. `durable: false` is a
  // statement; an absent field is silence, and reading silence as a statement
  // is how a lossy deployment gets filed under safe.
  const c = classifyHealth({ ok: true, name: "x", version: "1.0.0" });
  if (c.mode !== "unknown") throw new Error(`mode ${c.mode}`);
  if (c.durable !== null) throw new Error(`durable ${c.durable}, want null`);
  if (!c.reachable) throw new Error("should be reachable");
});

t("an explicit false is false", () => {
  const c = classifyHealth({ ok: true, durable: false, state: "in memory, no archive" });
  if (c.durable !== false) throw new Error(`durable ${c.durable}`);
});

t("an explicit true is true", () => {
  if (classifyHealth({ durable: true, mode: "mailbox" }).durable !== true) throw new Error("durable");
});

t("durable without a mode does not invent one", () => {
  const c = classifyHealth({ durable: true });
  if (c.mode !== "unknown") throw new Error(`mode ${c.mode}`);
  if (c.durable !== true) throw new Error("durable lost");
});

t("a non-boolean durable is not coerced", () => {
  // `durable: "false"` as a string is a lie in the JSON, not a truth value.
  const c = classifyHealth({ durable: "false" });
  if (c.durable !== null) throw new Error(`coerced to ${c.durable}`);
});

t("a 404 is unreachable, not lossy", () => {
  const c = classifyHealth({ error: "not found" }, 404);
  if (c.reachable) throw new Error("claimed reachable");
  if (c.mode !== "unknown") throw new Error(`mode ${c.mode}`);
});

t("a non-JSON body is unreachable, not parsed", () => {
  const c = classifyHealth(null, 200);
  if (c.reachable) throw new Error("claimed reachable");
});

t("a null body is unreachable", () => {
  if (classifyHealth(null, 200).reachable) throw new Error("claimed reachable");
});

t("a 500 from a live worker is unreachable", () => {
  if (classifyHealth({ ok: false }, 500).reachable) throw new Error("claimed reachable");
});

t("version is read when present and null when not", () => {
  if (classifyHealth({ version: "2.0.0" }).version !== "2.0.0") throw new Error("version");
  if (classifyHealth({ ok: true }).version !== null) throw new Error("invented a version");
});

// ---------------------------------------------------------------- the curve

t("a looser cadence never writes more", async () => {
  const rows = await cadence({ posts: 40 });
  for (let i = 1; i < rows.length; i++) {
    if (rows[i].writes > rows[i - 1].writes) {
      throw new Error(`every:${rows[i].every} wrote ${rows[i].writes} > ${rows[i - 1].writes}`);
    }
    if (rows[i].writeBytes > rows[i - 1].writeBytes) {
      throw new Error(`every:${rows[i].every} wrote more BYTES`);
    }
  }
});

t("a looser cadence never widens less than a tighter one", async () => {
  // The tradeoff must be real in both directions: if exposure did not grow,
  // the writes would be free and the knob would be a fiction.
  const rows = await cadence({ posts: 40 });
  for (let i = 1; i < rows.length; i++) {
    if (rows[i].peakAtRisk < rows[i - 1].peakAtRisk) {
      throw new Error(`every:${rows[i].every} exposure ${rows[i].peakAtRisk} < ${rows[i - 1].peakAtRisk}`);
    }
  }
});

t("every:1 commits on every append — the old behaviour", async () => {
  const rows = await cadence({ posts: 20 });
  const one = rows.find((r) => r.every === 1);
  if (!one) throw new Error("no row for every:1");
  // 20 posts plus the final flush.
  if (one.commits !== 21) throw new Error(`commits ${one.commits}, want 21`);
  if (one.peakAtRisk !== 0) throw new Error(`atRisk ${one.peakAtRisk} at every:1`);
});

t("the exposure window at every:N is bounded by N", async () => {
  const rows = await cadence({ posts: 40 });
  const r = rows.find((x) => x.every === 8);
  if (!r) throw new Error("no row for every:8");
  // One line per post, so N posts means at most N-1 uncommitted before the
  // commit lands. It has to stay bounded or the cadence buys writes with data.
  if (r.peakAtRisk > r.every) throw new Error(`atRisk ${r.peakAtRisk} > every ${r.every}`);
});

t("the experiment reports refused posts rather than claiming full volume", async () => {
  // The failure this tool already made once: it summarised "100 POSTs" when
  // the rate limiter had accepted 10. The warning is the guard.
  const rows = await cadence({ posts: 12 });
  const accepted = rows[0].appends;
  if (accepted > 12) throw new Error("claimed more appends than posts");
  if (accepted !== 12) {
    // Refused posts must show up as fewer appends, not as a clean run.
    if (rows[0].commits >= 12) throw new Error("counts imply every post landed");
  }
});

t("the summary reports accepted posts, not requested ones", () => {
  // The exact mistake this tool made: 10 posts accepted, "100 POSTs" claimed.
  const rows = [{ appends: 10, writes: 11 }, { appends: 10, writes: 6 },
                { appends: 10, writes: 3 }, { appends: 10, writes: 2 }];
  const s = summarizeCadence(rows, 100);
  if (s.accepted !== 10) throw new Error(`accepted ${s.accepted}`);
  if (!s.short) throw new Error("short posts not flagged");
});

t("the summary is not short when every post landed", () => {
  const rows = [{ appends: 100, writes: 101 }, { appends: 100, writes: 51 },
                { appends: 100, writes: 26 }, { appends: 100, writes: 13 }];
  const s = summarizeCadence(rows, 100);
  if (s.short) throw new Error("claimed short");
  if (s.savingVsBaseline !== 87) throw new Error(`saving ${s.savingVsBaseline}`);
});

t("the summary survives an empty experiment", () => {
  const s = summarizeCadence([], 10);
  if (s.accepted !== 0) throw new Error(`accepted ${s.accepted}`);
  if (!s.short) throw new Error("empty run should read as short");
  if (s.savingVsBaseline !== 0) throw new Error("saving from no rows");
});

for (const [name, fn] of tests) {
  try { await fn(); pass++; console.log("  ok  ", name); }
  catch (e) { fail++; failures.push(name); console.log("  FAIL", name, "—", e.message); }
}
console.log(`\n${pass} passed, ${fail} failed`);
if (fail) { console.log("FAILED:", failures.join(", ")); process.exit(1); }