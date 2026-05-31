---
name: nix-tile-build
description: Build tiles and the main Kant Pastebin binary with Nix. Use when: (1) Building a tile standalone to verify its .so output, (2) Building the full pastebin with all tiles, (3) Debugging build failures (combinedSrc, crate2nix, vendor dir), (4) Updating flake inputs, (5) Deploying to dev/prod instances.
---

# Nix Tile Build

## Build Commands

```bash
# Build main pastebin
nix build                                          # Binary at result/bin/kant-pastebin
nix build --no-link --print-build-logs             # Show compilation output

# Build a single tile standalone
nix build ./tiles/org-tile#                        # Tile .so only
nix build ./tiles/zos-circuit-tile#                # Tile .so only

# Build the combined source derivation (debug)
nix build .#kant-pastebin-src-with-submodules

# Show store paths
nix build --print-out-paths
```

## Flake.Nix Structure

```
flake inputs:
  ├── nixpkgs (unstable)
  ├── erdfa-publish-src      → bare mirror, flake = false
  ├── rust-ipfs-src           → bare mirror, flake = false
  ├── org-tile-src            → input for org-tile's combinedSrc
  └── zos-circuit-tile-src    → input for zos-circuit-tile's combinedSrc

flake outputs:
  ├── packages.default       → buildRustPackage with
  │                            combinedSrc = main source + submodule dirs
  │                            cargoLock.lockFile = ./Cargo.lock
  │                            TILES_DIR = path to tiles in nix store
  └── tiles/<name>           → each tile is a separate flake
```

## BuildRustPackage Configuration

```nix
buildRustPackage {
  src = combinedSrc;
  cargoLock.lockFile = ./Cargo.lock;
  buildInputs = [ openssl pkg-config perl ];
  doCheck = false;
}
```

## CombinedSrc Pattern

The `combinedSrc` derivation merges bare mirror sources into the expected directory structure:

```nix
combinedSrc = runCommand "combined-src" { } ''
  cp -a ${./.} $out
  chmod -R +w $out
  rm -rf $out/erdfa-publish
  cp -a ${erdfa-publish-src} $out/erdfa-publish
  mkdir -p $out/vendor
  cp -a ${rust-ipfs-src} $out/vendor/rust-ipfs
'';
```

## Tile CombinedSrc Pattern

Tiles with path deps need their own combinedSrc to flatten `../../` references:

```nix
combinedSrc = runCommand "tile-src" { } ''
  cp -a ${src} $out
  chmod -R +w $out
  cp -a ${dep1-src} $out/deps/dep1
  cp -a ${dep2-src} $out/deps/dep2
  # Patch ../../ path deps in all Cargo.toml
  sed -i 's|path = "../../dep1"|path = "../deps/dep1"|g' $out/deps/*/Cargo.toml
'';
```

## Dev/Prod Instance Deployment

```bash
# Get store paths
nix build --print-out-paths           # main binary
nix build ./tiles/org-tile# --print-out-paths
nix build ./tiles/zos-circuit-tile# --print-out-paths

# Update systemd service
cat > ~/.config/systemd/user/kant-pastebin-dev.service << 'UNIT'
...
Environment="TILES_DIR=/nix/store/.../lib:/nix/store/.../lib"
UNIT

systemctl --user daemon-reload && systemctl --user restart kant-pastebin-dev
```

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `failed to read Cargo.toml` | Submodule dir missing in build sandbox | Check combinedSrc copies |
| `NAR hash mismatch` | Bare mirror updated | `nix flake lock --update-input <name>` |
| `multihash-codetable` version | Mismatched dep version | Patch Cargo.toml or vendor dir |
| Empty `.so` output | Wrong installPhase | Add `cp -a target/release/*.so $out/lib/` to installPhase |
| proc-macro crate fails | Path deps in submodule not patched | Add `sed -i` in combinedSrc derivation |
