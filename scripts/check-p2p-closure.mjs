#!/usr/bin/env node
// check-p2p-closure.mjs -- assert every file the p2p client imports actually
// reaches dist/.
//
// The Pages build copies the p2p page and its dependencies by hand. That list
// silently rots: add an import to kant-p2p.mjs and CI stays green while the
// browser 404s on the new module. This walks the real import graph from
// p2p.html and fails the build when something is missing, so the drift is
// caught here instead of in the page.
//
//   node scripts/check-p2p-closure.mjs
//
// Exits 0 when dist/ covers the closure, 1 otherwise.

import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const WEB = path.join(root, 'web');
const DIST = path.join(root, 'dist');
const ENTRY = 'p2p.html';

// Deliberately not shipped: guarded by a .catch() in kant-p2p.mjs and it drags
// in the vendored aristotle-wasm binary, which is not part of this crate.
const OPTIONAL = new Set(['arist-wasm.mjs']);

// Loaded at runtime rather than by a static `import`, so the graph walk above
// cannot see them. Listed here so dropping one from the copy step still fails.
//   pastebin_wasm_bg.wasm — fetched by the wasm-bindgen JS glue
//   kant_kernel.wasm      — fetched by kant-wasm.mjs via new URL(...)
const RUNTIME_ASSETS = ['pastebin_wasm_bg.wasm', 'kant_kernel.wasm'];

if (!fs.existsSync(DIST)) {
  console.error('dist/ does not exist — run the Pages build steps first');
  process.exit(1);
}

/** Local `./x` specifiers in a source file, ignoring node: and URLs. */
function localImports(source) {
  const specs = [
    ...source.matchAll(/\bfrom\s+["'`]\.\/([^"'`]+)["'`]/g),
    ...source.matchAll(/\bimport\(\s*["'`]\.\/([^"'`]+)["'`]/g),
  ];
  return specs
    .map(m => m[1])
    .filter(spec => !spec.startsWith('node:') && !spec.includes('://'));
}

const closure = new Set();
const queue = [ENTRY];
const missingOnDisk = [];

while (queue.length) {
  const rel = queue.shift();
  if (closure.has(rel) || OPTIONAL.has(rel)) continue;
  closure.add(rel);

  const abs = path.join(WEB, rel);
  if (!fs.existsSync(abs)) {
    missingOnDisk.push(rel);
    continue;
  }
  queue.push(...localImports(fs.readFileSync(abs, 'utf8')));
}

const shipped = new Set(fs.readdirSync(DIST));
const unshipped = [...closure, ...RUNTIME_ASSETS].filter(f => !shipped.has(f)).sort();

if (missingOnDisk.length || unshipped.length) {
  if (missingOnDisk.length) {
    console.error(`imports reference files that do not exist in web/:\n  ${missingOnDisk.join('\n  ')}`);
  }
  if (unshipped.length) {
    console.error(`p2p import closure is not fully shipped to dist/:\n  ${unshipped.join('\n  ')}`);
    console.error('add each to the "Ship the p2p client" step in .github/workflows/pages.yml');
  }
  process.exit(1);
}

console.log(
  `p2p closure verified: ${closure.size} imported + ` +
    `${RUNTIME_ASSETS.length} runtime-loaded files shipped to dist/`,
);
for (const f of [...closure].sort()) console.log(`  ${f}`);
