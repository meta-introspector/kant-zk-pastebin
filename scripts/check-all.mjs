#!/usr/bin/env node
// check-all.mjs — one command that runs the test suites.
//
//   node scripts/check-all.mjs                  the hermetic suites
//   node scripts/check-all.mjs --all            everything tracked, slow ones too
//   node scripts/check-all.mjs --json           machine-readable
//   node scripts/check-all.mjs --repeat 5       each suite five times
//   node scripts/check-all.mjs --repeat 5 --only web/net-test.mjs
//
// Why this exists: the repository had fifty tracked `*-test.mjs` files and
// nothing that ran them. `npm test` is a puppeteer test that needs a live
// server, and the Makefile has no test target at all. So the suites ran when
// somebody remembered to run them, which is how a `float` constructor got
// added to a transcription of a Lean file, in a shared codec, with every suite
// green.
//
// Three rules this follows, all learned the hard way:
//
//   - **It does not hide failures.** The excluded suites are printed with the
//     reason and their current state. A runner that quietly skips ten broken
//     files is as misleading as no runner, because it reads as coverage.
//   - **It runs everything it claims to, every time.** No caching, no
//     "already passed" state.
//   - **It says when a suite is only sometimes right.** `--repeat` exists for
//     one reason: `scripts/net-test.mjs` passed three times and failed the
//     fourth with `429`, and the cause written down at the time ("it binds a
//     real port") was wrong. A runner that reports one green run as `ok` cannot
//     tell a suite that is right from a suite that is usually right.
//
// It is deliberately not clever about which suites are hermetic: the split is a
// hand-written manifest below, with a stated reason per entry, rather than
// something inferred by grepping for `fetch(`.

import { spawnSync } from "node:child_process";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/** The suites that make up the regression net: hermetic, fast, no relay. */
export const CORE = [
  "scripts/codec-test.mjs",
  "web/codec-test.mjs",
  "server/thunk-test.mjs",
  "server/sandbox-test.mjs",
  "server/store-test.mjs",
  "server/room-test.mjs",
  "scripts/thunk-claims.mjs",
  "scripts/thunk-claims-test.mjs",
  "scripts/lean-codec-types.mjs",
  "scripts/lean-codec-vectors.mjs",
  // Filed as "needs a live relay to measure", which was written by somebody who
  // had not opened it. It is the judgment half of scripts/relay-measure.mjs —
  // classifyHealth, cadence, summarizeCadence — with no relay and no network, and
  // it runs in 0.65s. `excluded-reasons-match-the-tree` now fails if a stated
  // reason stops being true of the suite it names.
  "scripts/relay-measure-test.mjs",
  // The Lean proof itself. `lean-gate/` is the 13-module closure of
  // `Wasm/KernelSpec.lean` with Mathlib removed, so `gokujo check` finishes in
  // ~10.5s cold / ~2.7s warm instead of the 560s-and-no-olean that `import
  // Mathlib` cost. It is in the core run for the same reason as the wasm
  // conformance suite above: it is the other end of the chain that makes the
  // binary mean something, and a gate nobody runs is not a gate.
  "scripts/lean-proofs.mjs",
  "scripts/relay-telemetry-test.mjs",
  "scripts/sharelog-test.mjs",
  "web/sharelog-test.mjs",
  "scripts/uucp-test.mjs",
  "web/uucp-test.mjs",
  "scripts/qr-test.mjs",
  "web/qr-test.mjs",
  "web/pretty-test.mjs",
  "web/diag-test.mjs",
  "web/diagpage-test.mjs",
  "web/handpage-test.mjs",
  "web/flow-test.mjs",
  "scripts/flow-test.mjs",
  "scripts/pastebin-test.mjs",
  "web/pastebin-test.mjs",
  "web/page-test.mjs",
  "web/site-test.mjs",
  "web/join-test.mjs",
  "scripts/join-test.mjs",
  "web/net-test.mjs",
  "scripts/vacuum-bug-test.mjs",
  // The kernel conformance test. It used to read the gitignored `dist/` and
  // fail on a clean checkout, so it sat in EXCLUDED as "BROKEN" — while being
  // the only suite tying the wasm to Lean. It now reads tracked artifacts
  // (web/kant_kernel.wasm, web/kernel-vectors.json) and runs in 0.5s.
  // scripts/wasm-test.mjs delegates to the web copy, so there is one set of
  // assertions rather than two byte-identical copies that could drift.
  "web/wasm-test.mjs",
  "scripts/wasm-test.mjs",
  // The remaining page and card suites. All eight were BROKEN and are now green:
  //   * carddebug (both copies) needed scripts/kant-debug.mjs, which the big
  //     merge dropped — it exists on origin/feature/lean and was restored.
  //   * cli-page needed the querySelectorAll the page uses, plus a transcript
  //     assertion that had been reading markup the renderer stopped emitting.
  //   * the scripts/ page copies resolved their HTML and config against
  //     scripts/ rather than web/, so they died with ENOENT; they now delegate
  //     to the web/ copy, which is a superset of each.
  //
  // The delegating copies are in the core run even though they repeat their
  // web/ twin's assertions: a delegation is code too, and the thing most likely
  // to break here is the delegation itself. Together they add ~3.4s.
  "web/cli-page-test.mjs",
  "web/carddebug-test.mjs",
  "scripts/carddebug-test.mjs",
  "scripts/cli-page-test.mjs",
  "scripts/diagpage-test.mjs",
  "scripts/handpage-test.mjs",
  "scripts/page-test.mjs",
  "scripts/site-test.mjs",
  // The network suite, twice: web/net-test.mjs carries the coverage, and
  // scripts/net-test.mjs used to be a stale copy that wrote rate-limit rows
  // into /var/lib/kant-zk/passes.sqlite. It now delegates. Kept in the core run
  // rather than hidden in --all because a delegation is code, and this one had
  // already silently diverged once.
  "scripts/net-test.mjs",
];

/**
 * Everything else, with the reason it is not in the core run. A suite moves out
 * of this list when it passes and is fast, not when it stops being inconvenient.
 */
export const EXCLUDED = {
  "scripts/cli-test.mjs": "24s; hermetic but slow",
  "web/cli-test.mjs": "4.6s; hermetic but slow",
  "scripts/diag-test.mjs": "8.5s; starts a relay",
  "scripts/forward-test.mjs": "15s; starts a relay",
  // Not what this file was filed as. It reads as a measurement test because of
  // its name; it imports classifyHealth / cadence / summarizeCadence from
  // scripts/relay-measure.mjs, starts no relay, reaches no host, and finishes in
  // 0.65s. It is in the core run above.
  //
  // This one's header is worth reading, because it is what makes the mistake
  // obvious in hindsight: "No network: every relay here is a fake".
  "scripts/room-store-test.mjs": "17s; hermetic but slow \u2014 every relay here is a fake",
  "web/file-test.mjs": "5.6s; hermetic but slow",
  // Its own first paragraph says the pubsub node is injected, "so this runs with
  // no network, no daemon and no CDN". It was filed as "starts a relay", which
  // is a claim about a file nobody opened.
  "web/libp2p-test.mjs": "3.5s; hermetic but slow \u2014 the pubsub node is injected",

  // Broken, and deliberately visible rather than quietly skipped. Empty: every
  // suite that was here has been fixed. The reason each one was wrong is in
  // tasks/thunk-server/VERIFICATION.md, and the core list above carries the fix.
};

/** Run one suite in its own process, so a crash cannot take the runner with it. */
export function runOne(file, timeoutMs) {
  const t0 = Date.now();
  const r = spawnSync(process.execPath, [`${ROOT}/${file}`], {
    cwd: ROOT, encoding: "utf8", timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024,
  });
  const out = `${r.stdout ?? ""}${r.stderr ?? ""}`;
  const lines = out.trim().split("\n").filter(Boolean);
  const timedOut = Boolean(r.error && r.error.code === "ETIMEDOUT");
  return {
    file,
    ok: !timedOut && r.status === 0,
    timedOut,
    status: timedOut ? "timeout" : `exit ${r.status}`,
    ms: Date.now() - t0,
    summary: (lines.find((l) => /passed|checks|claims|No bug/.test(l)) ?? lines[lines.length - 1] ?? "")
      .trim().slice(0, 56),
  };
}

/** Every tracked `*-test.mjs`, so a new one cannot be added and go unnoticed. */
export function trackedSuites() {
  return execFileSync("git", ["ls-files"], { cwd: ROOT, encoding: "utf8" })
    .split("\n")
    .filter((f) => f.endsWith("-test.mjs"));
}

/**
 * Turn N runs of the same suite into one verdict.
 *
 * Three outcomes, and the distinction between the last two is the entire
 * reason `--repeat` exists. A suite that failed every time is broken, and the
 * ordinary run says so. A suite that failed *once* is not broken, it is
 * unreliable, and reporting it as `ok` because the last run happened to pass is
 * how a rate-limit counter nobody owns becomes "a flaky test". With N = 1
 * there is nothing to compare, so the verdict says `stable pass` rather than
 * claiming more than one run can support.
 *
 * @param {{file: string, ok: boolean}[]} runs  every run, in the order they ran
 * @returns {{file: string, runs: number, passed: number, verdict: string}[]}
 */
export function classifyRepeats(runs) {
  const byFile = new Map();
  for (const r of runs) {
    if (!byFile.has(r.file)) byFile.set(r.file, []);
    byFile.get(r.file).push(r.ok);
  }
  return [...byFile].map(([file, oks]) => {
    const passed = oks.filter(Boolean).length;
    return {
      file,
      runs: oks.length,
      passed,
      verdict: passed === oks.length ? "stable pass"
        : passed === 0 ? "stable fail" : "UNSTABLE",
    };
  });
}

/** `--flag value` or `--flag=value`, or undefined. */
function flagValue(argv, flag) {
  const i = argv.findIndex((a) => a === flag || a.startsWith(`${flag}=`));
  if (i === -1) return undefined;
  const arg = argv[i];
  return arg.includes("=") ? arg.slice(flag.length + 1) : argv[i + 1];
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const all = argv.includes("--all");
  const json = argv.includes("--json");
  const repeat = Math.max(1, Number(flagValue(argv, "--repeat") ?? 1));
  const only = flagValue(argv, "--only");
  // Generous: several core suites take 2s, and --all takes 25s for cli-test.
  const timeoutMs = Number(process.env.SUITE_TIMEOUT_MS ?? 90000);

  let listed = all ? [...CORE, ...Object.keys(EXCLUDED)] : CORE;
  if (only) {
    const want = new Set(only.split(",").map((s) => s.trim()).filter(Boolean));
    const missing = [...want].filter((f) => !listed.includes(f));
    if (missing.length) {
      console.error(`not in this run's manifest: ${missing.join(", ")}`);
      process.exit(1);
    }
    listed = listed.filter((f) => want.has(f));
  }

  const runs = [];
  for (let i = 0; i < repeat; i += 1) {
    for (const f of listed) runs.push(runOne(f, timeoutMs));
  }
  // The last round is what the per-suite lines describe; the verdicts are what
  // all of them say together.
  const results = runs.slice(-listed.length);
  const verdicts = repeat > 1 ? classifyRepeats(runs) : null;

  // A suite that is tracked, in neither list, means the manifest is stale. That
  // is the check that stops this file from quietly ceasing to cover the repo.
  const known = new Set([...CORE, ...Object.keys(EXCLUDED)]);
  const unlisted = all || only ? [] : trackedSuites().filter((f) => !known.has(f));

  const failed = verdicts
    ? verdicts.filter((v) => v.passed < v.runs)
    : results.filter((r) => !r.ok);
  const unstable = verdicts ? verdicts.filter((v) => v.verdict === "UNSTABLE") : [];
  const payload = {
    results,
    failed: failed.map((f) => f.file),
    unstable: unstable.map((u) => u.file),
    repeat,
    excluded: all ? {} : EXCLUDED,
    unlisted,
    verdicts,
  };

  if (json) {
    console.log(JSON.stringify(payload, null, 2));
  } else {
    const times = repeat > 1 ? ` \u00d7 ${repeat}` : "";
    console.log(`Running ${listed.length} suite${listed.length === 1 ? "" : "s"}${times}${all ? " (--all)" : ""}\n`);
    for (const v of verdicts ?? results.map((r) => ({ ...r, runs: 1, passed: r.ok ? 1 : 0 }))) {
      const last = results.find((r) => r.file === v.file) ?? {};
      const mark = v.passed === v.runs ? "ok  " : "FAIL";
      const tally = repeat > 1 ? `${v.passed}/${v.runs}`.padStart(5) : "     ";
      console.log(
        `  ${mark} ${tally} ${String(last.ms ?? 0).padStart(6)}ms  ${v.file.padEnd(34)}`
        + ` ${v.passed === v.runs ? last.summary : `${last.status ?? ""} ${last.summary ?? ""}`}`,
      );
    }
    const totalRuns = runs.length;
    const passedRuns = runs.filter((r) => r.ok).length;
    console.log(`\n${passedRuns}/${totalRuns} run${totalRuns === 1 ? "" : "s"} pass`
      + ` across ${listed.length} suite${listed.length === 1 ? "" : "s"}`);
    if (verdicts) {
      if (unstable.length) {
        console.log(`\nFAIL: ${unstable.length} suite(s) are not stable under repetition —`
          + ` they pass sometimes and fail sometimes:`);
        for (const u of unstable) {
          console.log(`  ${u.file.padEnd(34)} ${u.passed}/${u.runs}`);
        }
      } else {
        // Stated rather than omitted. "No suite is unstable" is a claim about
        // the whole run, and a run of one says nothing about it.
        const n = verdicts.length;
        console.log(`\nno suite changed its mind over ${repeat} run${repeat === 1 ? "" : "s"}`
          + ` (${n} suite${n === 1 ? "" : "s"} checked)`);
      }
    } else {
      console.log("\n(one run each: nothing said here about stability —"
        + " use --repeat N to find a suite that is only sometimes right)");
    }
    if (!all) {
      const broken = Object.entries(EXCLUDED).filter(([, why]) => /BROKEN/.test(why));
      if (broken.length) {
        console.log(`\n${broken.length} tracked suites are broken and excluded. They are listed so they stay visible:`);
        for (const [f, why] of broken) console.log(`  ${f.padEnd(34)} ${why}`);
      } else {
        // Stated rather than omitted: "no broken suites" is a claim that stops
        // being true quietly, and this line is what makes it visible when it does.
        console.log("\nno tracked suites are broken");
      }
      const slow = Object.entries(EXCLUDED).filter(([, why]) => !/BROKEN/.test(why));
      if (slow.length) console.log(`\n${slow.length} more excluded for slowness or a live relay; --all runs them.`);
      if (unlisted.length) {
        console.log(`\nFAIL: ${unlisted.length} tracked suite(s) in neither list -- add them to CORE or EXCLUDED:`);
        for (const f of unlisted) console.log(`  ${f}`);
      }
    }
  }
  process.exit(failed.length === 0 && unlisted.length === 0 ? 0 : 1);
}