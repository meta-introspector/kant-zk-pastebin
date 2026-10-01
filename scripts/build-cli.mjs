#!/usr/bin/env node
// build-cli.mjs — bundle the kant CLI into one self-contained distributable.
//
// The CLI is plain Node with zero runtime dependencies, so the bundle is a
// single .mjs file that runs anywhere Node >= 18 runs:
//
//   node scripts/build-cli.mjs            # dist/kant-cli.mjs (+ .sha256)
//   KANT_VERSION=v1.2.3 node ...          # stamped into --version output
//
// esbuild is used through the npm package when installed, otherwise through
// a standalone `esbuild` binary on PATH (CI: `npm i --no-save esbuild` or
// install the binary; either works).
//
// The bundle keeps `import.meta.url` resolution for kant.config, so dropping
// a kant.config next to the bundle (or pointing KANT_CONFIG at one)
// reconfigures it without a rebuild; with none present it uses the built-in
// defaults.

import { createHash } from "node:crypto";
import { mkdirSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import { execFileSync } from "node:child_process";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const version = process.env.KANT_VERSION ?? "0.0.0-dev";
const outfile = join(root, "dist", "kant-cli.mjs");

const banner = [
  "// kant-cli — the Kant protocol command-line client (bundled).",
  "// Zero runtime dependencies.  Source: meta-introspector/kant-zk-pastebin.",
  `// Version: ${version}`,
].join("\n");
const define = `process.env.KANT_CLI_VERSION=${JSON.stringify(version)}`;
const bannerFlag = `--banner:js=${banner}`;

mkdirSync(join(root, "dist"), { recursive: true });

// ---- locate esbuild: npm package first, then a binary on PATH ------------
async function esbuildModule() {
  try {
    return await import("esbuild");
  } catch {
    return null;
  }
}

function esbuildBinary() {
  for (const dir of (process.env.PATH ?? "").split(":")) {
    if (!dir) continue;
    const p = join(dir, "esbuild");
    try {
      execFileSync(p, ["--version"], { stdio: "ignore" });
      return p;
    } catch {
      /* keep looking */
    }
  }
  return null;
}

const mod = await esbuildModule();
if (mod) {
  await mod.build({
    entryPoints: [join(root, "scripts", "kant-cli.mjs")],
    bundle: true,
    platform: "node",
    target: "node18",
    format: "esm",
    outfile,
    banner: { js: banner },
    define: { "process.env.KANT_CLI_VERSION": JSON.stringify(version) },
    logLevel: "info",
  });
} else {
  const bin = esbuildBinary();
  if (!bin) {
    console.error(
      "build-cli: esbuild not found.  Install it with `npm i --no-save esbuild`",
      "or put a standalone esbuild binary on PATH.",
    );
    process.exit(1);
  }
  const args = [
    join(root, "scripts", "kant-cli.mjs"),
    "--bundle",
    "--platform=node",
    "--format=esm",
    "--target=node18",
    `--outfile=${outfile}`,
    bannerFlag,
    `--define:${define}`,
    "--log-level=info",
  ];
  const r = spawnSync(bin, args, { stdio: "inherit" });
  if (r.status !== 0) process.exit(r.status ?? 1);
}

// ---- sanity check + sidecars ---------------------------------------------
let text = readFileSync(outfile, "utf8");
// Ensure exactly one shebang (the entry's survives the build; add if absent).
if (!text.startsWith("#!")) {
  text = `#!/usr/bin/env node\n${text}`;
  writeFileSync(outfile, text);
}
if (!text.startsWith("#!/usr/bin/env node") || text.length < 1000) {
  console.error("build-cli: bundle is missing or malformed");
  process.exit(1);
}
const sha = createHash("sha256").update(text).digest("hex");
writeFileSync(join(root, "dist", "kant-cli.sha256"), `${sha}  kant-cli.mjs\n`);
writeFileSync(join(root, "dist", "kant-cli.version"), `${version}\n`);
console.log(`build-cli: ${outfile} (${sha.slice(0, 12)}…) version ${version}`);
