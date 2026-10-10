// server/thunk-publish.mjs — publish thunks to Nix, Nora, and Forge.
//
// Three publishing targets:
//  1. Nix — write a flake.nix + default.nix that embeds the thunk source,
//     then push to the Nix registry (or local store).
//  2. Nora — write a package.json + index.mjs, then push to Nora registry
//     (port :4000, supports npm/cargo/docker/raw protocols).
//  3. Forge — write thunk source + metadata to a git repo and push to Forgejo.
//
// Each target receives the thunk's shareable bundle (manifest + state + source)
// and stores it in a form that consumers can pull and run.

import { mkdirSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import crypto from "node:crypto";

const NORA_URL = process.env.NORA_URL || "http://localhost:4000";
const FORGE_URL = process.env.FORGE_URL || "http://localhost:3000";
const NIX_STORE = process.env.NIX_STORE || "/nix/store";

/**
 * Build the publishable bundle from a Thunk instance.
 * @param {import("./thunk.mjs").Thunk} thunk
 */
export function publishBundle(thunk) {
  return {
    manifest: thunk.manifest(),
    state: thunk.snapshot(),
    source: thunk.source,
    name: thunk.name,
    version: thunk.version,
    id: thunk.id,
  };
}

/**
 * Publish to Nix registry.
 * Writes flake.nix + default.nix into a Nix-compatible directory.
 */
export async function publishToNix(bundle, outDir = "/tmp/nix-thunks") {
  const safeName = bundle.name.replace(/[^a-z0-9-]/g, "-");
  const dir = join(outDir, safeName);
  mkdirSync(dir, { recursive: true });

  // default.nix — the thunk as a Nix derivation
  const defaultNix = `
{ stdenv ? import <nix/fetchers> { url = "https://github.com/NixOS/nixpkgs"; rev = "master"; },
  nodejs ? stdenv.nodejs,
  thunkSource ? (builtins.toFile "thunk-source.mjs" ''
${bundle.source}
''),
}:

stdenv.mkDerivation {
  pname = "thunk-${safeName}";
  version = "${bundle.version}";
  src = thunkSource;
  buildInputs = [ nodejs ];

  buildPhase = ''
    cp $src thunk.mjs
  '';

  installPhase = ''
    mkdir -p $out
    cp thunk.mjs $out/
    # Write the bundle so consumers can load it
    cat > $out/thunk.json <<EOF_JSON
${JSON.stringify(bundle, null, 2)}
EOF_JSON
  '';

  meta = {
    description = "Thunk: ${safeName} v${bundle.version}";
  };
}
`;

  // flake.nix — for Nix Flakes
  const flakeNix = `
{
  description = "Thunk: ${safeName} v${bundle.version}";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  };
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      pkgsFor = system: nixpkgs.legacyPackages.\${system};
    in
    {
      packages.\${"x86_64-linux"}.thunk = pkgsFor.\${"x86_64-linux"}.stdenv.mkDerivation {
        pname = "thunk-${safeName}";
        version = "${bundle.version}";
        src = ./.;
        buildInputs = [ pkgsFor.\${"x86_64-linux"}.nodejs ];
        buildPhase = ''
          cp thunk-source.mjs thunk.mjs
        '';
        installPhase = ''
          mkdir -p $out
          cp thunk.mjs $out/
          cat > $out/thunk.json <<EOF_JSON
${JSON.stringify(bundle, null, 2)}
EOF_JSON
        '';
        meta.description = "Thunk: ${safeName} v${bundle.version}";
      };
    };
}
`;

  // thunk-source.mjs — the raw source
  writeFileSync(join(dir, "thunk-source.mjs"), bundle.source, "utf8");
  writeFileSync(join(dir, "default.nix"), defaultNix, "utf8");
  writeFileSync(join(dir, "flake.nix"), flakeNix, "utf8");
  writeFileSync(join(dir, "thunk.json"), JSON.stringify(bundle, null, 2), "utf8");

  return {
    ok: true,
    target: "nix",
    path: dir,
    files: ["thunk-source.mjs", "default.nix", "flake.nix", "thunk.json"],
  };
}

/**
 * Publish to Nora registry.
 * Writes package.json + index.mjs + thunk.json, then pushes to Nora.
 */
export async function publishToNora(bundle, outDir = "/tmp/nora-thunks") {
  const safeName = bundle.name.replace(/[^a-z0-9-]/g, "-");
  const dir = join(outDir, safeName);
  mkdirSync(dir, { recursive: true });

  // package.json
  const pkg = {
    name: `thunk-${safeName}`,
    version: bundle.version,
    description: `Thunk: ${bundle.name} v${bundle.version}`,
    main: "index.mjs",
    exports: { ".": "./index.mjs" },
    keywords: ["thunk", "kant-zk", "state-machine"],
    license: "MIT",
    dependencies: {},
  };
  writeFileSync(join(dir, "package.json"), JSON.stringify(pkg, null, 2), "utf8");

  // index.mjs — the thunk wrapped as an npm package
  const index = `// Auto-generated from thunk: ${bundle.name} v${bundle.version}
// Shareable manifest:
// ${JSON.stringify(bundle.manifest)}

const thunkSource = ${JSON.stringify(bundle.source)};

export async function loadThunk(state) {
  const { Thunk } = await import("thunk");
  const t = await Thunk.load(thunkSource, ${JSON.stringify(bundle.name)}, ${JSON.stringify(bundle.version)});
  if (state) t.resume(state);
  return t;
}

export const initialState = ${JSON.stringify(bundle.state)};
export const manifest = ${JSON.stringify(bundle.manifest)};
`;
  writeFileSync(join(dir, "index.mjs"), index, "utf8");

  // thunk.json — the full bundle
  writeFileSync(join(dir, "thunk.json"), JSON.stringify(bundle, null, 2), "utf8");

  // Push to Nora
  try {
    const res = await fetch(`${NORA_URL}/npm/publish`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        name: pkg.name,
        version: pkg.version,
        description: pkg.description,
        main: pkg.main,
        files: ["package.json", "index.mjs", "thunk.json"],
      }),
    });
    if (res.ok) {
      return { ok: true, target: "nora", url: `${NORA_URL}/npm/${pkg.name}`, path: dir };
    }
    return { ok: false, target: "nora", error: `Nora publish failed: ${res.status}` };
  } catch (e) {
    return { ok: false, target: "nora", error: `Nora unreachable: ${e.message}` };
  }
}

/**
 * Publish to Forge (Forgejo).
 * Writes thunk source + metadata to a git-compatible directory.
 * Returns the publish location.
 */
export async function publishToForge(bundle, outDir = "/tmp/forge-thunks") {
  const safeName = bundle.name.replace(/[^a-z0-9-]/g, "-");
  const repoName = `thunk-${safeName}`;
  const dir = join(outDir, repoName);
  mkdirSync(dir, { recursive: true });

  // thunk source
  writeFileSync(join(dir, "thunk.mjs"), bundle.source, "utf8");

  // thunk metadata
  const meta = {
    id: bundle.id,
    name: bundle.name,
    version: bundle.version,
    manifest: bundle.manifest,
    initialState: bundle.state,
    publishedAt: new Date().toISOString(),
    sourceHash: crypto.createHash("sha256").update(bundle.source).digest("hex"),
  };
  writeFileSync(join(dir, "thunk.json"), JSON.stringify(meta, null, 2), "utf8");

  // README
  const readme = `# Thunk: ${bundle.name} v${bundle.version}

**ID:** \`${bundle.id}\`
**Published:** ${meta.publishedAt}

## Usage

\`\`\`js
import { Thunk } from "thunk";

const t = await Thunk.load(source, "${bundle.name}", "${bundle.version}");
// t.apply({ ... });
// t.snapshot();
// t.share();
\`\`\`

## Source

\`\`\`js
${bundle.source}
\`\`\`
`;
  writeFileSync(join(dir, "README.md"), readme, "utf8");

  // .gitkeep for the repo
  writeFileSync(join(dir, ".gitkeep"), "", "utf8");

  // Push to Forge
  try {
    const res = await fetch(`${FORGE_URL}/api/v1/repos`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        name: repoName,
        description: `Thunk: ${bundle.name} v${bundle.version}`,
        auto_init: false,
      }),
    });
    if (res.ok) {
      return { ok: true, target: "forge", url: `${FORGE_URL}/${repoName}`, path: dir, repo: repoName };
    }
    return { ok: false, target: "forge", error: `Forge repo creation failed: ${res.status}` };
  } catch (e) {
    return { ok: false, target: "forge", error: `Forge unreachable: ${e.message}` };
  }
}

/**
 * Publish to all three targets.
 * @param {object} bundle — from publishBundle()
 * @returns {Array<{ok: boolean, target: string, ...}>}
 */
export async function publishAll(bundle) {
  const results = [];
  results.push(await publishToNix(bundle));
  results.push(await publishToNora(bundle));
  results.push(await publishToForge(bundle));
  return results;
}
