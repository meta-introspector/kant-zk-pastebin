#!/usr/bin/env node
// check-all.mjs — one command that runs the test suites.
//
//   node scripts/check-all.mjs           the hermetic suites
//   node scripts/check-all.mjs --all     everything tracked, slow ones too
//   node scripts/check-all.mjs --json    machine-readable
//
// Why this exists: the repository had fifty tracked `*-test.mjs` files and
// nothing that ran them. `npm test` is a puppeteer test that needs a live
// server, and the Makefile has no test target at all. So the suites ran when
// somebody remembered to run them, which is how a `float` constructor got
// added to a transcription of a Lean file, in a shared codec, with every suite
// green.
//
// Two rules this follows, both learned the hard way:
//
//   - **It does not hide failures.** The excluded suites are printed with the
//     reason and their current state. A runner that quietly skips ten broken
//     files is as misleading as no runner, because it reads as coverage.
//   - **It runs everything it claims to, every time.** No caching, no
//     "already passed" state.
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
  "scripts/relay-measure-test.mjs": "needs a live relay to measure",
  "scripts/room-store-test.mjs": "13s; starts a relay",
  "web/file-test.mjs": "5.6s; hermetic but slow",
  "web/libp2p-test.mjs": "3s; starts a relay",
  // Not hermetic, despite looking like its `web/` twin. It binds a real port and
  // posts to a real relay, so it 429s under repetition -- it passed the first
  // survey by luck and failed every run after. Not a flaky test; a networked
  // one, filed next to a hermetic twin that looks identical.
  "scripts/net-test.mjs": "posts to a live relay; 429s when run twice",

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

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const all = process.argv.includes("--all");
  const json = process.argv.includes("--json");
  // Generous: several core suites take 2s, and --all takes 25s for cli-test.
  const timeoutMs = Number(process.env.SUITE_TIMEOUT_MS ?? 90000);

  const listed = all ? [...CORE, ...Object.keys(EXCLUDED)] : CORE;
  const results = listed.map((f) => runOne(f, timeoutMs));

  // A suite that is tracked, in neither list, means the manifest is stale. That
  // is the check that stops this file from quietly ceasing to cover the repo.
  const known = new Set([...CORE, ...Object.keys(EXCLUDED)]);
  const unlisted = all ? [] : trackedSuites().filter((f) => !known.has(f));

  const failed = results.filter((r) => !r.ok);
  const payload = {
    results,
    failed: failed.map((f) => f.file),
    excluded: all ? {} : EXCLUDED,
    unlisted,
  };

  if (json) {
    console.log(JSON.stringify(payload, null, 2));
  } else {
    console.log(`Running ${results.length} suite${results.length === 1 ? "" : "s"}${all ? " (--all)" : ""}\n`);
    for (const r of results) {
      console.log(
        `  ${(r.ok ? "ok  " : "FAIL").padEnd(5)} ${String(r.ms).padStart(6)}ms  ${r.file.padEnd(34)}`
        + ` ${r.ok ? r.summary : `${r.status} ${r.summary}`}`,
      );
    }
    console.log(`\n${results.length - failed.length}/${results.length} suites pass`);
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