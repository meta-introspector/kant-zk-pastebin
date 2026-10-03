#!/usr/bin/env node
// publish-proof.mjs — run the checks and publish them to the gui2proof site.
//
// The gui2proof control surface (nginx `location ^~ /gui2proof/`, proxying
// to the GUI2Proof server on 127.0.0.1:9890) shows the *latest* run from
// its artifact root. A run is a directory holding a proof-manifest.json in
// the `gui2lean4-proof/v1` shape:
//
//   { schema, capturedAt, url, checks: [{ name, ok, ... }], artifacts: {...} }
//
// so writing one here is all it takes for the results to appear on the
// site — no changes to that project, and nothing to keep in sync with it.
//
// What runs, in order:
//   1. scripts/audit-web.mjs --selftest   (the browserless front-end audit)
//   2. web/test.mjs and every web/*-test.mjs
//   3. scripts/kant-file-e2e.mjs          (two real browsers; skipped with
//                                          --skip-e2e, which needs an X
//                                          display and takes a minute)
//
// A failure anywhere is recorded as a failing check rather than aborting
// the run: a proof that says which check broke is worth more than no proof.
//
// Usage: node scripts/publish-proof.mjs [--skip-e2e] [--keep]
//
// The run directory is named so it sorts last, because the site only ever
// displays the newest one — an older timestamp would publish a result
// nobody can see.

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import {
  mkdirSync, writeFileSync, readFileSync, readdirSync, copyFileSync, existsSync,
} from "node:fs";
import { join } from "node:path";
import { argv, exit } from "node:process";

const args = argv.slice(2);
const SKIP_E2E = args.includes("--skip-e2e");

// Where the GUI2Proof server looks. Overridable, and the same variable the
// server itself reads, so the two can never disagree by accident.
const ARTIFACT_ROOT = process.env.GUI2LEAN4_ARTIFACT_ROOT ||
  "/home/mdupont/projects/arist/data/gui2lean4/proofs";
const SITE = process.env.GUI2PROOF_URL || "http://localhost/gui2proof/";

const run = (cmd, argvList, opts = {}) => new Promise((resolve) => {
  const started = Date.now();
  const child = spawn(cmd, argvList, { cwd: process.cwd(), ...opts });
  let out = "";
  child.stdout.on("data", (d) => { out += d; });
  child.stderr.on("data", (d) => { out += d; });
  child.on("error", (e) => resolve({ code: 127, out: `${out}${e.message}`, ms: Date.now() - started }));
  child.on("close", (code) => resolve({ code: code ?? 1, out, ms: Date.now() - started }));
});

const sha256 = (path) =>
  createHash("sha256").update(readFileSync(path)).digest("hex");

const checks = [];
const record = (name, ok, extra = {}) => {
  checks.push({ name, ok: Boolean(ok), ...extra });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}`);
};

// ------------------------------------------------------------------ 1. audit
{
  const r = await run(process.execPath, ["scripts/audit-web.mjs", "--selftest"]);
  const selftest = /SELFTEST OK/.test(r.out);
  // The audit prints an ERROR/WARN heading only when there is at least one,
  // so an absent heading means zero — not "unknown".
  const count = (label) => {
    const m = new RegExp(`^${label} \\((\\d+)\\)`, "m").exec(r.out);
    return m ? Number(m[1]) : 0;
  };
  const errors = count("ERROR");
  const warns = count("WARN");
  record("audit: tokenizer selftest", selftest);
  record("audit: no errors", selftest && errors === 0, { errors, warnings: warns });
  if (selftest) {
    console.log(`      ${errors} error(s), ${warns} warning(s)`);
  } else {
    console.log(r.out.split("\n").slice(0, 6).join("\n      "));
  }
}

// ----------------------------------------------------------------- 2. suites
const suites = ["web/test.mjs",
  ...readdirSync("web").filter((f) => f.endsWith("-test.mjs")).sort().map((f) => `web/${f}`)];
for (const s of suites) {
  const r = await run(process.execPath, [s]);
  const tail = r.out.trim().split("\n").pop() ?? "";
  const m = /(\d+)\/(\d+)/.exec(tail);
  record(`suite ${s}`, r.code === 0, {
    ms: r.ms,
    ...(m ? { passed: Number(m[1]), total: Number(m[2]) } : {}),
    ...(r.code === 0 ? {} : { detail: tail.slice(0, 200) }),
  });
}

// ------------------------------------------------------------ 3. browser e2e
if (!SKIP_E2E) {
  const r = await run(process.execPath, ["scripts/kant-file-e2e.mjs"]);
  const e2eOk = /all checks passed/.test(r.out);
  record("e2e: two browsers drop and fetch a file", e2eOk, {
    ms: r.ms,
    ...(e2eOk ? {} : { detail: r.out.trim().split("\n").slice(-4).join(" | ").slice(0, 300) }),
  });
} else {
  console.log("SKIP  e2e (--skip-e2e)");
}

// ------------------------------------------------------------------ publish
// sortKey puts this run last among run-* names, since the site only shows
// the newest by string sort.
const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "");
const runName = `run-${stamp}-pastebin-tests`;
const dir = join(ARTIFACT_ROOT, runName);
mkdirSync(dir, { recursive: true });

// Artifacts: the machine-readable detail, plus the e2e's screenshots so the
// site shows what the run actually looked like rather than only verdicts.
const artifacts = {};
const addArtifact = (file, from) => {
  if (!existsSync(from)) return false;
  copyFileSync(from, join(dir, file));
  artifacts[file] = { sha256: sha256(join(dir, file)) };
  return true;
};

const detail = {
  capturedAt: new Date().toISOString(),
  cwd: process.cwd(),
  suites: suites.length,
  checks,
};
writeFileSync(join(dir, "results.json"), JSON.stringify(detail, null, 2));
artifacts["results.json"] = { sha256: sha256(join(dir, "results.json")) };

let shots = 0;
for (const f of ["01-a-room.png", "02-b-joined.png", "03-a-dropped.png", "04-b-sees-file.png"]) {
  if (addArtifact(f, join("e2e-out-file", f))) shots += 1;
}
if (addArtifact("timeline.json", "e2e-out-file/timeline.json")) shots += 1;

const passed = checks.filter((c) => c.ok).length;
const manifest = {
  schema: "gui2lean4-proof/v1",
  capturedAt: new Date().toISOString(),
  url: SITE,
  title: "pastebin-lean: unit suites, front-end audit, browser e2e",
  summary: `${passed}/${checks.length} checks passed` +
    (shots ? `, ${shots} e2e artifacts` : ""),
  checks,
  artifacts,
};
writeFileSync(join(dir, "proof-manifest.json"), JSON.stringify(manifest, null, 2));

console.log(`\n${passed}/${checks.length} checks passed`);
console.log(`published ${runName}`);
console.log(`  ${dir}`);
console.log(`  ${SITE}`);
exit(passed === checks.length ? 0 : 1);