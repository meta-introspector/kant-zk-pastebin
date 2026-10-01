# Pastebin Deployment Plan — Restore Nix Build + system-manager Activation

## Objective
Get `deploy.sh deploy` working end-to-end so the pastebin binary is built via Nix/crane and activated via system-manager, restoring the working configuration that uses the local nora cargo directory.

## Current State
- `flake.nix` is broken: syntax errors and crane API mismatch between HEAD version and current working tree
- `.cargo/config.toml` uses `sparse+https://solana.solfunmeme.com/nora/cargo/index/` which crane cannot resolve in the Nix sandbox
- `deploy.sh` was updated to use local nora but `nix build` fails before reaching deployment
- Pastebin binary is not being updated via Nix; system-manager activation has not run successfully

## Root Cause Analysis

### 1. flake.nix corruption
The working tree `flake.nix` was edited away from HEAD (`f8f7b6b`). The HEAD version used the correct crane API:
- `craneLib.vendorCargoDeps` with `overrideVendorCargoPackage`
- `craneLib.buildDepsOnly` + `craneLib.buildPackage`
- `noraCargoPackage` helper to extract crates from `/mnt/data1/nora/storage/cargo`

The current working tree has syntax errors and uses `cargoBuild` without `cargoArtifacts`, and `overrideCargoVendorCrate` instead of `overrideVendorCargoPackage`.

### 2. Crane API mismatch
The current `crane.url` points to `git+file:///mnt/data1/git/github.com/ipetkov/crane.git?ref=omaster` which is an old bare mirror. The local checkout at `/mnt/data1/time-2026/05-may/19/crane` has the working `vendorCargoDeps` + `buildDepsOnly` + `buildPackage` API. The bare mirror may have a different version.

### 3. Nora sparse registry unreachable from Nix sandbox
Even with correct crane API, crane's `vendorCargoRegistries` tries to download crates from `sparse+https://solana.solfunmeme.com/nora/cargo/index/`. The Nix sandbox cannot reach this URL. The `[patch.crates-io]` workaround in `.cargo/config.toml` tells Cargo to use the local nora directory instead of the remote sparse registry.

### 4. .cargo/config.toml misconfiguration
Current `.cargo/config.toml` uses `[registries.nora]` which crane treats as a remote registry. It should use `[patch.crates-io]` with `directory = "/mnt/data1/nora/storage/cargo"` to make crates available locally.

## Supporting Evidence

### File: /mnt/data1/kant/pastebin/flake.nix
Current broken state with `cargoBuild` requiring `cargoArtifacts` and wrong override function name.

### File: /mnt/data1/kant/pastebin/.cargo/config.toml
Current misconfigured sparse registry entry. Needs `[patch.crates-io]` workaround.

### File: /mnt/data1/kant/pastebin/pastebin-system.nix
Minimal system config for pastebin-only deployment via system-manager.

### File: /mnt/data1/kant/pastebin/deploy.sh
Deploy script that uses local nora and `systemConfigs.kant-pastebin-only`.

### File: /mnt/data1/kant/pastebin/Cargo.toml
Shows `erdfa-publish` and `rust-unixfs` using `registry = "nora"`.

### File: /mnt/data1/kant/pastebin/Cargo.lock
Shows `sparse+https://solana.solfunmeme.com/nora/cargo/index/` entries for nora crates.

### File: /mnt/data1/kant/pastebin/NEXT_STEPS.md
Detailed plan for next steps.

### File: /mnt/data1/kant/pastebin/scripts/svg2anim-worker.sh
Worker script with `.dead` extension fix.

### File: /mnt/data1/kant/pastebin/src/gallery.rs
Gallery with GIF suffix-match fallback and `<object>` for SVG.

## Plan

### Step 1: Restore flake.nix to HEAD
```bash
git checkout HEAD -- flake.nix
```

This restores the working crane API:
- `craneLib.vendorCargoDeps { src = src; overrideVendorCargoPackage = ... }`
- `craneLib.buildDepsOnly { ... }` producing `cargoArtifacts`
- `craneLib.buildPackage { cargoArtifacts = cargoArtifacts; ... }`
- `noraCargoPackage` helper function
- `crane.url = "git+file:///mnt/data1/git/github.com/ipetkov/crane.git?ref=omaster"` (old bare mirror that worked)

### Step 2: Fix .cargo/config.toml
Replace `[registries.nora]` with `[patch.crates-io]` workaround:
```toml
[patch.crates-io]
[source.local-nora-workaround]
directory = "/mnt/data1/nora/storage/cargo"
[source.crates-io]
replace-with = "local-nora-workaround"
```

This makes crane's `vendorCargoRegistries` treat nora crates as local files instead of remote sparse registry entries.

### Step 3: Verify flake evaluation
```bash
nix flake check --no-build .
```

Should pass without syntax errors or sparse registry errors.

### Step 4: Build pastebin binary
```bash
nix build .#kant-pastebin
```

Should produce `/nix/store/...-kant-pastebin-0.1.0/bin/kant-pastebin`.

### Step 5: Deploy via system-manager
```bash
bash deploy.sh deploy
```

Should activate `systemConfigs.kant-pastebin-only` and update the pastebin service.

### Step 6: Verify
- Check pastebin serves new binary: `curl http://127.0.0.1:8090/gallery`
- Check svg2anim worker processes jobs
- Check GIF rendering works

## Risks
- If `git checkout HEAD -- flake.nix` fails due to uncommitted changes, manual restore needed
- If old crane bare mirror is corrupted, use `/mnt/data1/time-2026/05-may/19/crane` with `ref=master`
- If `.cargo/config.toml` patch doesn't work, need to investigate crane's handling of `[patch]` sections
